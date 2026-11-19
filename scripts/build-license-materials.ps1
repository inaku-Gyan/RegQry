[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][ValidateSet('production', 'tests')][string]$Scope,
    [Parameter(Mandatory)][ValidateSet('x86_64-pc-windows-msvc', 'aarch64-pc-windows-msvc')][string]$Target,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][string]$ReportDirectory,
    [string]$CargoAbout
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bundle/support.ps1')
$projectRoot = Split-Path -Parent $PSScriptRoot
$ManifestPath = (Get-Item -LiteralPath $ManifestPath).FullName
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$reportRoot = [IO.Path]::GetFullPath($ReportDirectory)
if ($outputRoot.TrimEnd('\') -ieq $reportRoot.TrimEnd('\') -or $reportRoot.StartsWith($outputRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or $outputRoot.StartsWith($reportRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Keep license payload and collection reports in separate directories' }
if (Test-Path -LiteralPath $outputRoot) { throw 'License OutputDirectory must not exist' }
if (Test-Path -LiteralPath $reportRoot) { throw 'License ReportDirectory must not exist' }
if (-not $CargoAbout) { $CargoAbout = (Get-Command cargo-about.exe -ErrorAction Stop).Source }
$CargoAbout = (Get-Item -LiteralPath $CargoAbout).FullName
$tools = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'tools.psd1')
$toolVersion = & $CargoAbout --version
if ($LASTEXITCODE -ne 0 -or $toolVersion -cne ('cargo-about ' + $tools.CargoAbout)) { throw 'The pinned cargo-about version is required' }
$toolchain = '1.100.0-' + (Get-BundleEnvironment).nativeTarget
$compiler = @(& rustc ('+' + $toolchain) -Vv)
if ($LASTEXITCODE -ne 0 -or $compiler -notcontains 'release: 1.100.0') { throw 'Rust 1.100.0 is required for distribution materials' }
$configName = if ($Scope -eq 'tests') { 'about-tests.toml' } else { 'about.toml' }
$config = Join-Path $projectRoot $configName
$template = Join-Path $projectRoot 'about.hbs'
$sourceRoot = Split-Path -Parent $ManifestPath
$lock = Join-Path $sourceRoot 'Cargo.lock'
$lockSha = (Get-FileHash -LiteralPath $lock -Algorithm SHA256).Hash.ToLowerInvariant()
New-Item -ItemType Directory -Path $outputRoot | Out-Null
New-Item -ItemType Directory -Path $reportRoot | Out-Null
$saved = @{ RUSTUP_TOOLCHAIN = [Environment]::GetEnvironmentVariable('RUSTUP_TOOLCHAIN', 'Process') }
$record = [ordered]@{
    schemaVersion = 1
    status = 'fail'
    scope = $Scope
    target = $Target
    tool = $toolVersion
    toolSha256 = (Get-FileHash -LiteralPath $CargoAbout -Algorithm SHA256).Hash.ToLowerInvariant()
    compiler = $compiler
    lockSha256 = $lockSha
    config = $configName
    configSha256 = (Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash.ToLowerInvariant()
    templateSha256 = (Get-FileHash -LiteralPath $template -Algorithm SHA256).Hash.ToLowerInvariant()
    features = 'Cargo default features; no additional root features'
    cargoPackages = @()
    files = @()
    error = $null
}
Push-Location -LiteralPath $sourceRoot
try {
    $env:RUSTUP_TOOLCHAIN = $toolchain
    $arguments = @('generate', '--locked', '--fail', '--manifest-path', $ManifestPath, '--config', $config, '--target', $Target)
    $rawJson = Join-Path $reportRoot 'cargo-about.json'
    & $CargoAbout @arguments --format json --output-file $rawJson 2> (Join-Path $reportRoot 'cargo-about-json.stderr.txt')
    if ($LASTEXITCODE -ne 0) { throw 'cargo-about license gathering failed' }
    $data = Get-Content -LiteralPath $rawJson -Raw -Encoding utf8 | ConvertFrom-Json
    $notices = Join-Path $outputRoot 'THIRD-PARTY-NOTICES.txt'
    & $CargoAbout @arguments $template --output-file $notices 2> (Join-Path $reportRoot 'cargo-about-text.stderr.txt')
    if ($LASTEXITCODE -ne 0) { throw 'cargo-about notice rendering failed' }
    $rendered = (Get-Content -LiteralPath $notices -Raw -Encoding utf8).Replace("`r`n", "`n")
    $packages = @{}
    $licenseRoot = Join-Path $outputRoot 'licenses'
    New-Item -ItemType Directory -Path $licenseRoot | Out-Null
    foreach ($license in $data.licenses) {
        if (-not $license.source_path -or -not $license.text -or -not $rendered.Contains($license.text.Replace("`r`n", "`n").Trim())) {
            throw 'A license lacks its original source text or differs from the rendered notices; generic fallback is not accepted'
        }
        foreach ($used in $license.used_by) {
            $crate = $used.crate
            $identity = $crate.name + ' ' + $crate.version
            if (-not $packages.ContainsKey($identity)) {
                $packages[$identity] = [ordered]@{ name = $crate.name; version = $crate.version; license = $crate.license; selected = @(); sourceFiles = @() }
                # Preserve supplementary notices and all packaged license alternatives,
                # without attempting to parse their license language ourselves.
                $crateRoot = Split-Path -Parent $crate.manifest_path
                foreach ($file in Get-ChildItem -LiteralPath $crateRoot -File | Where-Object { $_.Name -match '^(?i:licen[cs]e|copying|copyright|notice|unlicense)([-_.].*)?$' }) {
                    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'License input must be a regular file' }
                    $destination = 'licenses/crates/' + $crate.name + '-' + $crate.version + '/' + $file.Name
                    $path = Join-Path $outputRoot $destination
                    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
                    Copy-Item -LiteralPath $file.FullName -Destination $path
                    $packages[$identity].sourceFiles += $destination
                }
            }
            $packages[$identity].selected += [ordered]@{ id = $license.id; source = [IO.Path]::GetFileName($license.source_path) }
        }
    }
    # Cross-check coverage against Cargo's target/edge-filtered graph. cargo-about
    # remains the license resolver; Cargo remains the dependency/feature resolver.
    $edges = if ($Scope -eq 'tests') { 'normal,build,dev' } else { 'normal,build' }
    $tree = @(& cargo ('+' + $toolchain) tree --locked --manifest-path $ManifestPath --target $Target --edges $edges --prefix none --format '{p} features=[{f}]')
    if ($LASTEXITCODE -ne 0) { throw 'Cargo distribution graph failed' }
    [IO.File]::WriteAllLines((Join-Path $reportRoot 'cargo-tree.txt'), [string[]]$tree, [Text.UTF8Encoding]::new($false))
    $graph = @{}
    foreach ($line in $tree) {
        if ($line -notmatch '^([a-zA-Z0-9_-]+) v([^ ]+) .*features=\[([^\]]*)\]') { throw ('Unrecognized Cargo graph entry: ' + $line) }
        $identity = $Matches[1] + ' ' + $Matches[2]
        if (-not $packages.ContainsKey($identity)) { throw ('Missing dependency notices: ' + $identity) }
        if (-not $graph.ContainsKey($identity)) { $graph[$identity] = @() }
        $graph[$identity] += $Matches[3]
    }
    if ($graph.Count -ne $packages.Count) { throw 'License and target dependency graphs differ' }
    foreach ($identity in @($packages.Keys | Sort-Object)) {
        $packages[$identity].features = @($graph[$identity] | Sort-Object -Unique)
        $record.cargoPackages += $packages[$identity]
    }
    $sysroot = & rustc ('+' + $toolchain) --print sysroot
    if ($LASTEXITCODE -ne 0) { throw 'Cannot locate the actual Rust toolchain notices' }
    $rustDoc = Join-Path $sysroot 'share/doc/rust'
    $rustRoot = Join-Path $licenseRoot 'rust'
    New-Item -ItemType Directory -Path $rustRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $rustDoc 'COPYRIGHT-library.html') -Destination (Join-Path $rustRoot 'COPYRIGHT-library.html')
    foreach ($licenseName in @('MIT', 'APACHE')) {
        $licenseFiles = @(Get-ChildItem -LiteralPath (Join-Path $rustDoc 'html/static.files') -Filter ('LICENSE-' + $licenseName + '-*.txt') -File)
        if ($licenseFiles.Count -ne 1) { throw 'Install rust-docs for the pinned toolchain; original Rust license files are required' }
        Copy-Item -LiteralPath $licenseFiles[0].FullName -Destination (Join-Path $rustRoot ('LICENSE-' + $licenseName))
    }
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'docs/distribution.md') -Destination (Join-Path $licenseRoot 'DISTRIBUTION.md')
    if ((Get-FileHash -LiteralPath $lock -Algorithm SHA256).Hash.ToLowerInvariant() -cne $lockSha) { throw 'Lockfile changed during license collection' }
    foreach ($item in Get-ChildItem -LiteralPath $outputRoot -Recurse -File | Sort-Object FullName) {
        $record.files += [ordered]@{
            path = $item.FullName.Substring($outputRoot.Length + 1).Replace('\', '/')
            size = $item.Length
            sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    $record.status = 'pass'
    Write-BundleJson -Value $record -Path (Join-Path $licenseRoot 'materials.json')
    Write-Output ('Collected ' + $Scope + ' distribution notices for ' + $packages.Count + ' Cargo packages: ' + $Target)
} catch {
    $record.error = $_.Exception.Message
    throw
} finally {
    try { Write-BundleJson -Value $record -Path (Join-Path $reportRoot 'result.json') }
    finally { try { Restore-BundleEnvironment -Saved $saved } finally { Pop-Location } }
}

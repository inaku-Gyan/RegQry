[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceArchive,
    [string]$OutputDirectory,
    [ValidateSet('x86_64-pc-windows-msvc', 'aarch64-pc-windows-msvc')][string]$Target,
    [string]$Dumpbin
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bundle/support.ps1')
$projectRoot = Split-Path -Parent $PSScriptRoot
$SourceArchive = (Get-Item -LiteralPath $SourceArchive).FullName
$runId = [guid]::NewGuid().ToString('N')
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot ('artifacts/test-bundles/' + $runId) }
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $outputRoot) { throw 'OutputDirectory must not exist; existing bundles are never overwritten' }
$environment = Get-BundleEnvironment
if (-not $Target) { $Target = $environment.nativeTarget }
if ($Target -ne $environment.nativeTarget) { throw 'Build portable test bundles on the matching native architecture' }
$toolchain = '1.100.0-' + $Target
$compiler = @(& rustc ('+' + $toolchain) -Vv)
if ($LASTEXITCODE -ne 0 -or $compiler -notcontains 'release: 1.100.0' -or $compiler -notcontains ('host: ' + $Target)) {
    throw 'The pinned native Rust 1.100.0 toolchain is required'
}
$cargoVersion = & cargo ('+' + $toolchain) -V
if ($LASTEXITCODE -ne 0 -or $cargoVersion -notmatch '^cargo 1\.100\.0 ') { throw 'Cargo 1.100.0 is required' }
$entries = @(& tar -tf $SourceArchive)
if ($LASTEXITCODE -ne 0 -or $entries.Count -eq 0) { throw 'Cannot list source archive' }
$top = ($entries[0] -split '/')[0]
if ($top -notmatch '^regqry-[0-9][a-zA-Z0-9.+-]*$') { throw 'Unexpected source archive root' }
foreach ($entry in $entries) {
    if (-not $entry.StartsWith($top + '/', [StringComparison]::Ordinal) -or $entry -match '(^|/)\.\.?(/|$)|\\|:') { throw 'Unexpected source archive path' }
}
$runRoot = Join-Path ([IO.Path]::GetTempPath()) ('regqry-bundle-' + $runId)
$sourceRoot = Join-Path $runRoot 'source'
New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
New-Item -ItemType Directory -Path $outputRoot | Out-Null
& tar -xf $SourceArchive -C $sourceRoot
if ($LASTEXITCODE -ne 0) { throw 'Source extraction failed' }
$unpacked = Join-Path $sourceRoot $top
if (Test-Path -LiteralPath (Join-Path $unpacked '.cargo/config.toml')) { throw 'Repository Cargo configuration must not be required by the archive' }
$savedEnvironment = @{}
$savedConsoleEncoding = [Console]::OutputEncoding
$savedOutputEncoding = $OutputEncoding
foreach ($name in @('CARGO_TARGET_DIR', 'CARGO_BUILD_WARNINGS', 'CARGO_ENCODED_RUSTFLAGS', 'RUSTFLAGS', 'RUSTC_WRAPPER', 'RUSTC_WORKSPACE_WRAPPER')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$result = [ordered]@{
    schemaVersion = 1
    status = 'fail'
    scope = 'native development test-bundle build; not a frozen release candidate'
    startedAtUtc = [DateTime]::UtcNow.ToString('o')
    target = $Target
    source = $null
    environment = $environment
    compiler = $compiler
    cargo = $cargoVersion
    rustFlags = @('-C', 'target-feature=+crt-static')
    buildRoot = $runRoot
    bundle = $null
    error = $null
}
Push-Location -LiteralPath $unpacked
try {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Text.UTF8Encoding]::new($false)
    $env:CARGO_TARGET_DIR = Join-Path $runRoot 'target'
    $env:CARGO_BUILD_WARNINGS = 'deny'
    $env:RUSTFLAGS = $null
    $env:RUSTC_WRAPPER = $null
    $env:RUSTC_WORKSPACE_WRAPPER = $null
    $env:CARGO_ENCODED_RUSTFLAGS = '-C' + [char]0x1f + 'target-feature=+crt-static'
    $metadataText = & cargo ('+' + $toolchain) metadata --locked --no-deps --format-version 1
    if ($LASTEXITCODE -ne 0) { throw 'Archive metadata failed' }
    $metadata = $metadataText | ConvertFrom-Json
    $package = @($metadata.packages | Where-Object name -eq 'regqry')[0]
    if (-not $package -or $top -cne ('regqry-' + $package.version)) { throw 'Archive/package identity mismatch' }
    $vcs = Get-Content -LiteralPath (Join-Path $unpacked '.cargo_vcs_info.json') -Raw -Encoding utf8 | ConvertFrom-Json
    $result.source = [ordered]@{
        file = [IO.Path]::GetFileName($SourceArchive)
        sha256 = (Get-FileHash -LiteralPath $SourceArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        lockSha256 = (Get-FileHash -LiteralPath (Join-Path $unpacked 'Cargo.lock') -Algorithm SHA256).Hash.ToLowerInvariant()
        git = $vcs.git
    }
    $bundleName = 'regqry-v' + $package.version + '-tests-' + $Target
    $bundleRoot = Join-Path $outputRoot $bundleName
    $testRoot = Join-Path $bundleRoot 'tests'
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $testMessages = @(& cargo ('+' + $toolchain) test --locked --release --target $Target --no-run --message-format=json-render-diagnostics)
    if ($LASTEXITCODE -ne 0) { throw 'Static-CRT test compilation failed' }
    [IO.File]::WriteAllLines((Join-Path $outputRoot 'cargo-test.jsonl'), [string[]]$testMessages, [Text.UTF8Encoding]::new($false))
    $buildMessages = @(& cargo ('+' + $toolchain) build --locked --release --target $Target --bin regqry --message-format=json-render-diagnostics)
    if ($LASTEXITCODE -ne 0) { throw 'Static-CRT CLI compilation failed' }
    [IO.File]::WriteAllLines((Join-Path $outputRoot 'cargo-build.jsonl'), [string[]]$buildMessages, [Text.UTF8Encoding]::new($false))
    $cliArtifacts = @($buildMessages | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.reason -eq 'compiler-artifact' -and $_.target.name -eq 'regqry' -and $_.executable -and -not $_.profile.test })
    if ($cliArtifacts.Count -ne 1) { throw 'Cannot identify the actual CLI compiler artifact' }
    Copy-Item -LiteralPath $cliArtifacts[0].executable -Destination (Join-Path $bundleRoot 'regqry.exe')
    $harnesses = @($testMessages | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.reason -eq 'compiler-artifact' -and $_.profile.test -and $_.executable })
    if ($harnesses.Count -eq 0) { throw 'Cargo produced no native test harnesses' }
    $tests = @()
    foreach ($harness in $harnesses) {
        $file = [IO.Path]::GetFileName($harness.executable)
        $copied = Join-Path $testRoot $file
        if (Test-Path -LiteralPath $copied) { throw 'Test executable name collision' }
        Copy-Item -LiteralPath $harness.executable -Destination $copied
        $listed = Invoke-BundleProcess -Program $copied -Arguments @('--list', '--format=terse')
        $ignored = Invoke-BundleProcess -Program $copied -Arguments @('--ignored', '--list', '--format=terse')
        if ($listed.timedOut -or $listed.exitCode -ne 0 -or $listed.stderr -or $ignored.timedOut -or $ignored.exitCode -ne 0 -or $ignored.stderr) { throw 'Cannot enumerate compiled tests' }
        [string[]]$names = @($listed.stdout -split "`r?`n" | Where-Object { $_ -match ': test$' })
        [Array]::Sort($names, [StringComparer]::Ordinal)
        $ignoredNames = @($ignored.stdout -split "`r?`n" | Where-Object { $_ -match ': test$' })
        $tests += [ordered]@{
            path = 'tests/' + $file
            targetName = $harness.target.name
            targetKind = $harness.target.kind
            names = $names
            runnable = $names.Count - $ignoredNames.Count
            ignored = $ignoredNames.Count
        }
    }
    foreach ($file in @('run-tests.ps1', 'run-vm-tests.ps1', 'support.ps1', 'README.md')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('bundle/' + $file)) -Destination (Join-Path $bundleRoot $file)
    }
    Copy-Item -LiteralPath (Join-Path $unpacked 'LICENSE') -Destination (Join-Path $bundleRoot 'LICENSE')
    $executables = @(Get-ChildItem -LiteralPath $bundleRoot -Recurse -File -Filter '*.exe' | Sort-Object FullName | ForEach-Object FullName)
    & (Join-Path $PSScriptRoot 'check-pe.ps1') -Executable $executables -Target $Target -ReportDirectory (Join-Path $bundleRoot 'pe') -Dumpbin $Dumpbin
    Copy-Item -LiteralPath (Join-Path $bundleRoot 'pe/result.json') -Destination (Join-Path $bundleRoot 'dll-imports.json')
    $files = @()
    foreach ($item in Get-ChildItem -LiteralPath $bundleRoot -Recurse -File | Sort-Object FullName) {
        $files += [ordered]@{
            path = $item.FullName.Substring($bundleRoot.Length + 1).Replace('\', '/')
            size = $item.Length
            sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    $manifest = [ordered]@{
        schemaVersion = 1
        kind = 'regqry-development-test-bundle'
        version = $package.version
        target = $Target
        source = $result.source
        compiler = $compiler
        cargo = $cargoVersion
        rustFlags = $result.rustFlags
        environment = $environment
        tests = $tests
        files = $files
    }
    Write-BundleJson -Value $manifest -Path (Join-Path $bundleRoot 'bundle-manifest.json')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Add-Type -AssemblyName System.IO.Compression
    $zip = Join-Path $outputRoot ($bundleName + '.zip')
    $archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($item in Get-ChildItem -LiteralPath $bundleRoot -Recurse -File | Sort-Object FullName) {
            $entry = $bundleName + '/' + $item.FullName.Substring($bundleRoot.Length + 1).Replace('\', '/')
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $item.FullName, $entry, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally { $archive.Dispose() }
    $result.bundle = [ordered]@{
        directory = $bundleRoot
        archive = $zip
        sha256 = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        manifestSha256 = (Get-FileHash -LiteralPath (Join-Path $bundleRoot 'bundle-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $result.status = 'pass'
    Write-Output ('Built native test bundle: ' + $zip)
} catch {
    $result.error = $_.Exception.Message
    throw
} finally {
    try { Write-BundleJson -Value $result -Path (Join-Path $outputRoot 'build.json') }
    finally {
        try {
            Restore-BundleEnvironment -Saved $savedEnvironment
        } finally {
            try { [Console]::OutputEncoding = $savedConsoleEncoding; $OutputEncoding = $savedOutputEncoding }
            finally { Pop-Location }
        }
    }
}

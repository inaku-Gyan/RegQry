[CmdletBinding()]
param([switch]$AllowDirty)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$previousWarnings = $env:CARGO_BUILD_WARNINGS
Push-Location -LiteralPath $projectRoot
try {
    $env:CARGO_BUILD_WARNINGS = 'deny'
    $packageArgs = @('package', '--locked')
    if ($AllowDirty) { $packageArgs += '--allow-dirty' }
    $files = @(& cargo @packageArgs --list)
    if ($LASTEXITCODE -ne 0) { throw 'Package file listing failed' }
    $files = @($files | ForEach-Object { $_.Replace('\', '/') })
    foreach ($file in $files) {
        if ($file -match '^(\.scratch/|\.github/|\.cargo/|scripts/|docs/agents/|target/|artifacts/|AGENTS\.md$|GLOSSARY\.md$)') {
            throw ('Development-only file in package: ' + $file)
        }
    }
    foreach ($required in @('Cargo.toml', 'Cargo.lock', 'README.md', 'LICENSE', 'src/main.rs', 'src/lib.rs', 'tests/cli.rs', 'docs/usage.md', 'docs/matching.md', 'docs/compatibility.md')) {
        if ($required -notin $files) { throw ('Missing package input: ' + $required) }
    }
    & cargo build --release --locked
    if ($LASTEXITCODE -ne 0) { throw 'Release build failed' }
    & cargo @packageArgs
    if ($LASTEXITCODE -ne 0) { throw 'Source packaging/build verification failed' }
    $metadataText = & cargo metadata --locked --no-deps --format-version 1
    if ($LASTEXITCODE -ne 0) { throw 'Cargo metadata failed' }
    $metadata = $metadataText | ConvertFrom-Json
    $package = @($metadata.packages | Where-Object name -eq 'regqry')[0]
    $archive = Join-Path $metadata.target_directory ('package/regqry-' + $package.version + '.crate')
    $runId = [guid]::NewGuid().ToString('N')
    $reportDir = Join-Path $projectRoot ('artifacts/package-check/' + $runId)
    $runDir = Join-Path ([System.IO.Path]::GetTempPath()) ('regqry-package-' + $runId)
    $sourceDir = Join-Path $runDir 'source'
    $installDir = Join-Path $runDir 'installed'
    New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    & tar -xf $archive -C $sourceDir
    if ($LASTEXITCODE -ne 0) { throw 'Source archive extraction failed' }
    $unpacked = Join-Path $sourceDir ('regqry-' + $package.version)
    $activeToolchain = & rustup show active-toolchain
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify the installation toolchain' }
    $toolchainArg = '+' + ($activeToolchain -split ' ')[0]
    Push-Location -LiteralPath $unpacked
    try {
        & cargo $toolchainArg install --path $unpacked --locked --root $installDir --target-dir (Join-Path $runDir 'target')
        if ($LASTEXITCODE -ne 0) { throw 'Independent source installation failed' }
    }
    finally { Pop-Location }
    $installed = Join-Path $installDir 'bin/regqry.exe'
    $version = & $installed --version
    if ($LASTEXITCODE -ne 0 -or $version -ne ('regqry ' + $package.version)) { throw 'Installed CLI version mismatch' }
    $help = & $installed --help
    if ($LASTEXITCODE -ne 0 -or ($help -join "`n") -notmatch 'Usage: regqry \[QUERY OPTIONS\]') { throw 'Installed CLI help failed' }
    [ordered]@{
        status = 'pass'
        scope = 'native development package check; not formal platform acceptance'
        archive = $archive
        sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
        version = $version
        source = $unpacked
        install = $installDir
        toolchain = ($activeToolchain -split ' ')[0]
        checkedAtUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $reportDir 'result.json') -Encoding utf8
    Write-Output ('Independent source installation verified: ' + $version)
}
finally {
    $env:CARGO_BUILD_WARNINGS = $previousWarnings
    Pop-Location
}

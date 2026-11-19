[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BundleArchive,
    [ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedArchiveSha256,
    [ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedManifestSha256,
    [string]$ReportDirectory,
    [string]$PowerShell7
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bundle/support.ps1')
$archive = (Get-Item -LiteralPath $BundleArchive).FullName
$runId = [guid]::NewGuid().ToString('N')
if (-not $ReportDirectory) { $ReportDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) ('artifacts/test-bundle-check/' + $runId) }
$reportRoot = [IO.Path]::GetFullPath($ReportDirectory)
if (Test-Path -LiteralPath $reportRoot) { throw 'ReportDirectory must not exist' }
New-Item -ItemType Directory -Path $reportRoot | Out-Null
$runRoot = Join-Path ([IO.Path]::GetTempPath()) ('regqry-relocation-' + $runId)
$relocated = Join-Path $runRoot ('moved ' + [char]0x03A9 + ' bundle')
$working = Join-Path $runRoot 'unrelated-working-directory'
New-Item -ItemType Directory -Path $relocated, $working -Force | Out-Null
$savedEnvironment = @{}
foreach ($name in @('PATH', 'CARGO_HOME', 'CARGO_TARGET_DIR', 'RUSTUP_HOME', 'RUSTUP_TOOLCHAIN', 'REGQRY_TEST_BIN')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$result = [ordered]@{
    schemaVersion = 1
    status = 'fail'
    scope = 'relocated development tests with Cargo/rustc absent from PATH; not a clean-system claim'
    startedAtUtc = [DateTime]::UtcNow.ToString('o')
    archive = $archive
    archiveSha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    relocated = $relocated
    runnerReport = 'tests/result.json'
    error = $null
}
Push-Location -LiteralPath $working
try {
    if ($ExpectedArchiveSha256 -and $result.archiveSha256 -ine $ExpectedArchiveSha256) { throw 'Bundle ZIP hash differs from the expected identity' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -notmatch '^[a-zA-Z0-9_./+-]+$' -or $entry.FullName -match '(^|/)\.\.?(/|$)' -or $entry.FullName.StartsWith('/')) { throw 'Unexpected bundle ZIP path' }
        }
    } finally { $zip.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $relocated)
    $roots = @(Get-ChildItem -LiteralPath $relocated -Directory)
    if ($roots.Count -ne 1 -or @(Get-ChildItem -LiteralPath $relocated -File).Count -ne 0) { throw 'Bundle ZIP must contain one top-level directory' }
    foreach ($name in $savedEnvironment.Keys) { Remove-Item -LiteralPath ('Env:\' + $name) -ErrorAction SilentlyContinue }
    $env:PATH = (Join-Path $env:SystemRoot 'System32') + ';' + $env:SystemRoot
    if (Get-Command cargo,rustc -ErrorAction SilentlyContinue) { throw 'Relocation check must run without Cargo/rustc on PATH' }
    $runnerArgs = @{ ReportDirectory = (Join-Path $reportRoot 'tests') }
    if ($ExpectedManifestSha256) { $runnerArgs.ExpectedManifestSha256 = $ExpectedManifestSha256 }
    if ($PowerShell7) { $runnerArgs.PowerShell7 = $PowerShell7 }
    & (Join-Path $roots[0].FullName 'run-tests.ps1') @runnerArgs
    $ran = Get-Content -LiteralPath (Join-Path $reportRoot 'tests/result.json') -Raw -Encoding utf8 | ConvertFrom-Json
    if ($ran.status -ne 'pass' -or $ran.environment.cargoOnPath -or $ran.environment.rustcOnPath) { throw 'Relocated runner did not complete without build tools on PATH' }
    $result.status = 'pass'
    $result.passedTests = $ran.passedTests
    $result.manifestSha256 = $ran.manifestSha256
    Write-Output ('Relocated test bundle verified: ' + $ran.passedTests + ' tests')
} catch {
    $result.error = $_.Exception.Message
    throw
} finally {
    try { Write-BundleJson -Value $result -Path (Join-Path $reportRoot 'result.json') }
    finally {
        Restore-BundleEnvironment -Saved $savedEnvironment
        Pop-Location
    }
}

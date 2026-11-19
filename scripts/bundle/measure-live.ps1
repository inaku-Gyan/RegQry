[CmdletBinding()]
param(
    [switch]$ReadOnlyLiveRegistry,
    [string]$PowerShell7,
    [ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedManifestSha256,
    [string]$ReportDirectory = (Join-Path ([IO.Path]::GetTempPath()) ('regqry-live-' + [guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'support.ps1')
$reportRoot = [IO.Path]::GetFullPath($ReportDirectory)
$prefix = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
if ($reportRoot.TrimEnd('\') -eq $PSScriptRoot.TrimEnd('\') -or $reportRoot.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Store observations outside the verified bundle' }
if (Test-Path -LiteralPath $reportRoot) { throw 'ReportDirectory must not exist' }
New-Item -ItemType Directory -Path $reportRoot | Out-Null
$result = [ordered]@{
    schemaVersion=1; kind='regqry-live-observation'; status='fail'
    scope='read-only aggregate observation; existing registry is not a correctness dataset; no raw registry output retained'
    startedAtUtc=[DateTime]::UtcNow.ToString('o'); environment=$null
    manifestSha256=$null; source=$null; observerHarnessesStarted=0; observation=$null; error=$null
}
$saved=@{}
foreach($name in @('REGQRY_TEST_BIN','REGQRY_TEST_PWSH','REGQRY_LIVE_CONFIRM')) { $saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
try {
    if (-not $ReadOnlyLiveRegistry) { throw 'Requires -ReadOnlyLiveRegistry; this observes the existing HKCU/HKLM registry without retaining key names or data' }
    $manifestPath=Join-Path $PSScriptRoot 'bundle-manifest.json'
    $result.manifestSha256=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ExpectedManifestSha256 -and $result.manifestSha256 -ine $ExpectedManifestSha256) { throw 'Observation bundle differs from expected manifest identity' }
    $result.environment=Get-BundleEnvironment
    if ($result.environment.elevated) { throw 'Live baseline requires a non-elevated token' }
    Remove-Item -LiteralPath Env:\REGQRY_LIVE_CONFIRM -ErrorAction SilentlyContinue
    $preflight=@{ReportDirectory=(Join-Path $reportRoot 'preflight');ExpectedManifestSha256=$result.manifestSha256}
    if ($PowerShell7) { $preflight.PowerShell7=$PowerShell7 }
    & (Join-Path $PSScriptRoot 'run-tests.ps1') @preflight
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    $result.source=$manifest.source
    $inventory=@($manifest.tests | Where-Object targetName -eq 'vm_registry')
    if ($inventory.Count -ne 1 -or $inventory[0].path -notmatch '^tests/[a-zA-Z0-9_.-]+\.exe$' -or 'performance::live_queries: test' -cnotin $inventory[0].names) { throw 'Missing aggregate observation harness' }
    $env:REGQRY_TEST_BIN=Join-Path $PSScriptRoot 'regqry.exe'
    $env:REGQRY_LIVE_CONFIRM='readonly-aggregate-only'
    $result.observerHarnessesStarted++
    $ran=Invoke-BundleProcess -Program (Join-Path $PSScriptRoot $inventory[0].path) -Arguments @('--ignored','--exact','performance::live_queries','--test-threads=1','--nocapture') -TimeoutSeconds 900
    [IO.File]::WriteAllText((Join-Path $reportRoot 'observer.stdout.txt'),$ran.stdout,[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $reportRoot 'observer.stderr.txt'),$ran.stderr,[Text.UTF8Encoding]::new($false))
    $metrics=@([regex]::Matches($ran.stdout,'(?m)^METRIC [^\r\n]+') | ForEach-Object Value)
    $result.observation=[ordered]@{exitCode=$ran.exitCode;timedOut=$ran.timedOut;elapsedMs=$ran.elapsedMs;metrics=$metrics;stdout='observer.stdout.txt';stderr='observer.stderr.txt'}
    if ($ran.timedOut -or $ran.exitCode -ne 0 -or -not $ran.stdout.Contains('LIVE_OBSERVATION actual_cli=true output=aggregate-only') -or -not $ran.stdout.Contains('test result: ok. 1 passed; 0 failed; 0 ignored;') -or $metrics.Count -ne 12) { throw 'Live observation failed or timed out; keep existing aggregate records, do not call it a completed baseline' }
    $result.status='observed'
    Write-Output 'Recorded twelve live query observations; inspect complete/exit fields, not a correctness or platform pass'
} catch { $result.error=$_.Exception.Message; throw }
finally {
    $result.finishedAtUtc=[DateTime]::UtcNow.ToString('o')
    try { Write-BundleJson -Value $result -Path (Join-Path $reportRoot 'result.json') }
    finally { Restore-BundleEnvironment -Saved $saved }
}

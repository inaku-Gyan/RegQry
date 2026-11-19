[CmdletBinding()]
param([Parameter(Mandatory)][string]$BundleDirectory,[string]$ReportDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'bundle/support.ps1')
$bundle=(Get-Item -LiteralPath $BundleDirectory).FullName
if (-not $ReportDirectory) { $ReportDirectory=Join-Path (Split-Path -Parent $PSScriptRoot) ('artifacts/performance-gates/'+[guid]::NewGuid().ToString('N')) }
$reportRoot=[IO.Path]::GetFullPath($ReportDirectory)
if (Test-Path -LiteralPath $reportRoot) { throw 'ReportDirectory must not exist' }
New-Item -ItemType Directory -Path $reportRoot | Out-Null
$result=[ordered]@{schemaVersion=1;status='fail';scope='live-observer rejection probes; no live registry queries';cases=@();error=$null}
$saved=@{REGQRY_LIVE_CONFIRM=[Environment]::GetEnvironmentVariable('REGQRY_LIVE_CONFIRM','Process')}
try {
    foreach($case in @('not-opted-in','wrong-manifest')) {
        $parameters=@{ReportDirectory=(Join-Path $reportRoot $case)}
        if ($case -eq 'wrong-manifest') { $parameters.ReadOnlyLiveRegistry=$true; $parameters.ExpectedManifestSha256='0'*64 }
        $expected=if($case -eq 'not-opted-in'){'Requires -ReadOnlyLiveRegistry'}else{'Observation bundle differs from expected manifest identity'}
        $env:REGQRY_LIVE_CONFIRM='caller-marker'
        $caught=$null
        try { & (Join-Path $bundle 'measure-live.ps1') @parameters } catch { $caught=$_.Exception.Message }
        if (-not $caught -or -not $caught.Contains($expected) -or $env:REGQRY_LIVE_CONFIRM -cne 'caller-marker') { throw ('Live guard failed: '+$case) }
        $record=Get-Content -LiteralPath (Join-Path $parameters.ReportDirectory 'result.json') -Raw -Encoding utf8|ConvertFrom-Json
        if ($record.status -ne 'fail' -or $record.observerHarnessesStarted -ne 0 -or (Test-Path -LiteralPath (Join-Path $parameters.ReportDirectory 'preflight'))) { throw 'Rejected live observation reached payload execution' }
        $result.cases += [ordered]@{name=$case;status='pass';expectedRejection=$caught;observerHarnessesStarted=0}
    }
    Remove-Item -LiteralPath Env:\REGQRY_LIVE_CONFIRM -ErrorAction SilentlyContinue
    $manifest=Get-Content -LiteralPath (Join-Path $bundle 'bundle-manifest.json') -Raw -Encoding utf8|ConvertFrom-Json
    $result.manifestSha256=(Get-FileHash -LiteralPath (Join-Path $bundle 'bundle-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    $inventory=@($manifest.tests|Where-Object targetName -eq 'vm_registry')
    if ($inventory.Count -ne 1 -or $inventory[0].path -notmatch '^tests/[a-zA-Z0-9_.-]+\.exe$') { throw 'Invalid observation harness' }
    $ran=Invoke-BundleProcess -Program (Join-Path $bundle $inventory[0].path) -Arguments @('--ignored','--exact','performance::live_queries','--nocapture')
    Write-BundleJson -Value $ran -Path (Join-Path $reportRoot 'direct-ignored.json')
    if ($ran.timedOut -or $ran.exitCode -eq 0 -or -not $ran.stderr.Contains('missing REGQRY_LIVE_CONFIRM') -or $ran.stdout.Contains('LIVE_OBSERVATION') -or $ran.stdout.Contains('VM_OPERATION_START')) { throw 'Direct ignored live observer bypassed its guard' }
    $result.cases += [ordered]@{name='direct-ignored';status='pass';exitCode=$ran.exitCode}
    $result.status='pass'
    'Performance rejection gates passed: '+$result.cases.Count
} catch { $result.error=$_.Exception.Message; throw }
finally {try {Write-BundleJson -Value $result -Path (Join-Path $reportRoot 'result.json')} finally {Restore-BundleEnvironment -Saved $saved}}

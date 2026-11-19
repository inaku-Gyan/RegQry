[CmdletBinding()]
param([Parameter(Mandatory)][string]$Configuration)
$ErrorActionPreference = 'Stop'
$env:PSModulePath = (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/Modules') + ';' + (Join-Path $env:ProgramFiles 'WindowsPowerShell/Modules')
$config = Get-Content -LiteralPath $Configuration -Raw -Encoding utf8 | ConvertFrom-Json
if ($config.schemaVersion -ne 1) { throw 'Unsupported hosted worker configuration' }
. (Join-Path $config.bundle 'support.ps1')
$record = [ordered]@{ schemaVersion=1; kind='regqry-hosted-query-worker'; status='fail'; environment=$null; profile=$null; error=$null; startedAtUtc=[DateTime]::UtcNow.ToString('o') }
try {
    $record.environment = Get-BundleEnvironment
    if ($record.environment.elevated) { throw 'Hosted query worker must have a non-elevated token' }
    if ((Get-FileHash -LiteralPath (Join-Path $config.bundle 'bundle-manifest.json')).Hash.ToLowerInvariant() -cne $config.manifestSha256) { throw 'Hosted worker bundle identity changed' }
    $record.profile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    $userHive = [Microsoft.Win32.Registry]::Users.OpenSubKey($record.environment.userSid)
    if (-not $userHive) { throw 'The query profile must remain loaded under its actual SID' }
    try {
        $software = $userHive.OpenSubKey('Software')
        $classes = $userHive.OpenSubKey('Software\Classes')
        try { if (-not $software -or -not $classes) { throw 'Query profile Software and Software\Classes must be initialized before fixture preparation' } }
        finally { if ($classes) { $classes.Dispose() }; if ($software) { $software.Dispose() } }
        # The process and this handle remain alive across the administrator's
        # preparation, so HKU/HKCU never fall back to the runner's profile.
        Write-BundleJson ([ordered]@{status='ready';environment=$record.environment;profile=$record.profile;userHiveLoaded=$true;classesReady=$true}) ($config.ready + '.tmp')
        [IO.File]::Move(($config.ready + '.tmp'), $config.ready)
        $waiting = [Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Path -LiteralPath $config.start)) {
            if ($waiting.Elapsed.TotalSeconds -ge 900) { throw 'Administrator preparation handshake timed out' }
            Start-Sleep -Milliseconds 200
        }
        $signal = Get-Content -LiteralPath $config.start -Raw -Encoding utf8 | ConvertFrom-Json
        if ($signal.status -cne 'prepared' -or (Get-FileHash -LiteralPath $config.context).Hash.ToLowerInvariant() -cne $signal.contextSha256) { throw 'Prepared fixture context identity changed' }
        $env:PATH = (Join-Path $env:WINDIR 'System32') + ';' + $env:WINDIR
        & (Join-Path $config.bundle 'run-vm-tests.ps1') -Phase Query -DisposableVm -ContextPath $config.context -PowerShell7 $config.powerShell7 -ExpectedManifestSha256 $config.manifestSha256 -ReportDirectory (Join-Path $config.reports 'query-bundle')
        $query = Get-Content -LiteralPath (Join-Path $config.reports 'query-bundle/result.json') -Raw -Encoding utf8 | ConvertFrom-Json
        if ($query.status -cne 'pass' -or $query.environment.elevated -or $query.environment.userSid -cne $record.environment.userSid -or $query.globalHarnessesStarted -ne 6) { throw 'Hosted query suite did not complete under the expected ordinary identity' }
        $record.status = 'pass'
    } finally { $userHive.Dispose() }
} catch { $record.error = $_.Exception.Message; throw }
finally { $record.finishedAtUtc=[DateTime]::UtcNow.ToString('o'); Write-BundleJson $record (Join-Path $config.reports 'worker-result.json') }

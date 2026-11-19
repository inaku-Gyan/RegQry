[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BundleDirectory,
    [string]$ReportDirectory
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bundle/support.ps1')
$bundle = (Get-Item -LiteralPath $BundleDirectory).FullName
$runId = [guid]::NewGuid().ToString('N')
if (-not $ReportDirectory) { $ReportDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) ('artifacts/vm-gates/' + $runId) }
$reportRoot = [IO.Path]::GetFullPath($ReportDirectory)
if (Test-Path -LiteralPath $reportRoot) { throw 'ReportDirectory must not exist' }
New-Item -ItemType Directory -Path $reportRoot | Out-Null
$result = [ordered]@{
    schemaVersion = 1; status = 'fail'; scope = 'VM opt-in/identity rejection probes; no global fixture creation'
    startedAtUtc = [DateTime]::UtcNow.ToString('o'); manifestSha256 = $null; source = $null; cases = @(); error = $null
}
$saved = @{}
foreach ($name in @('REGQRY_TEST_BIN', 'REGQRY_TEST_PWSH', 'REGQRY_LIVE_CONFIRM', 'REGQRY_VM_CONFIRM', 'REGQRY_VM_PHASE', 'REGQRY_VM_ID', 'REGQRY_VM_NONCE', 'REGQRY_VM_QUERY_SID', 'REGQRY_VM_ROLLBACK')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    $manifest = Get-Content -LiteralPath (Join-Path $bundle 'bundle-manifest.json') -Raw -Encoding utf8 | ConvertFrom-Json
    $result.manifestSha256 = (Get-FileHash -LiteralPath (Join-Path $bundle 'bundle-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    $result.source = $manifest.source
    $harness = @($manifest.tests | Where-Object targetName -eq 'vm_registry')
    if ($harness.Count -ne 1 -or $harness[0].path -notmatch '^tests/[a-zA-Z0-9_.-]+\.exe$') { throw 'Missing or invalid VM harness path' }
    $fixtureContext = [ordered]@{
        schemaVersion = 1; kind = 'regqry-disposable-vm-context'; status = 'prepared'
        id = 'a' * 32; nonce = 'b' * 64; querySid = 'S-1-5-21-1-2-3-1000'
        rollbackReference = 'synthetic-gate-context-not-a-real-vm'
        manifestSha256 = '0' * 64
    }
    foreach ($case in @('not-opted-in', 'unsafe-prepare-identity', 'existing-prepare-context', 'unprepared-context', 'different-bundle', 'query-identity-override')) {
        $contextPath = Join-Path $reportRoot ($case + '.json')
        $parameters = @{ Phase = 'Query'; ContextPath = $contextPath; DisposableVm = $true; ReportDirectory = (Join-Path $reportRoot $case) }
        $expected = switch ($case) {
            'not-opted-in' { $parameters.DisposableVm = $false; 'Requires -DisposableVm' }
            'unsafe-prepare-identity' { $parameters.Phase = 'Prepare'; $parameters.QuerySid = 'BA'; $parameters.RollbackReference = 'fake'; 'Preparation requires an ordinary-user QuerySid' }
            'existing-prepare-context' {
                Write-BundleJson -Value $fixtureContext -Path $contextPath
                $parameters.Phase = 'Prepare'; $parameters.QuerySid = $fixtureContext.querySid; $parameters.RollbackReference = 'fake'
                'Preparation context must not exist'
            }
            'unprepared-context' {
                $fixtureContext.status = 'preparing'
                Write-BundleJson -Value $fixtureContext -Path $contextPath
                $fixtureContext.status = 'prepared'
                'Invalid or incomplete preparation context'
            }
            'different-bundle' { Write-BundleJson -Value $fixtureContext -Path $contextPath; 'Query bundle differs from the prepared bundle' }
            'query-identity-override' { $parameters.QuerySid = $fixtureContext.querySid; 'Query uses the prepared identity' }
        }
        $errorText = $null
        try { & (Join-Path $bundle 'run-vm-tests.ps1') @parameters }
        catch { $errorText = $_.Exception.Message }
        if (-not $errorText -or $errorText -notmatch [regex]::Escape($expected)) { throw ('VM gate did not reject ' + $case + ': ' + $errorText) }
        $record = Get-Content -LiteralPath (Join-Path $parameters.ReportDirectory 'result.json') -Raw -Encoding utf8 | ConvertFrom-Json
        if ($record.status -ne 'fail' -or $record.globalHarnessesStarted -ne 0 -or (Test-Path -LiteralPath (Join-Path $parameters.ReportDirectory 'preflight'))) { throw ('Rejected VM context reached execution: ' + $case) }
        $result.cases += [ordered]@{ name = $case; status = 'pass'; expectedRejection = $errorText; globalHarnessesStarted = 0 }
    }
    $actualEnvironment = Get-BundleEnvironment
    $roleContext = [ordered]@{
        schemaVersion = 1; kind = 'regqry-disposable-vm-context'; status = 'prepared'
        id = 'a' * 32; nonce = 'b' * 64; querySid = $(if ($actualEnvironment.elevated) { $actualEnvironment.userSid } else { 'S-1-5-21-1-2-3-1000' })
        rollbackReference = 'synthetic-gate-context-not-a-real-vm'; computerName = $env:COMPUTERNAME
        manifestSha256 = (Get-FileHash -LiteralPath (Join-Path $bundle 'bundle-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
        setupEnvironment = $actualEnvironment
    }
    $roleContextPath = Join-Path $reportRoot 'query-role-context.json'
    Write-BundleJson -Value $roleContext -Path $roleContextPath
    $errorText = $null
    $roleReport = Join-Path $reportRoot 'query-token-role'
    try { & (Join-Path $bundle 'run-vm-tests.ps1') -Phase Query -DisposableVm -ContextPath $roleContextPath -ReportDirectory $roleReport }
    catch { $errorText = $_.Exception.Message }
    if (-not $errorText -or $errorText -notmatch 'Query requires the prepared user SID and a non-elevated token') { throw ('Query role gate did not reject: ' + $errorText) }
    $record = Get-Content -LiteralPath (Join-Path $roleReport 'result.json') -Raw -Encoding utf8 | ConvertFrom-Json
    if ($record.globalHarnessesStarted -ne 0 -or (Test-Path -LiteralPath (Join-Path $roleReport 'preflight'))) { throw 'Rejected query role reached execution' }
    $result.cases += [ordered]@{ name = $(if ($actualEnvironment.elevated) { 'query-elevated-token' } else { 'query-wrong-sid' }); status = 'pass'; expectedRejection = $errorText; globalHarnessesStarted = 0 }
    # Remove the only global-capable harness from a disposable copy: even a broken verifier cannot run it.
    # This reaches the post-environment-clear preflight failure under either runner token role.
    $copyRoot = Join-Path ([IO.Path]::GetTempPath()) ('regqry-vm-inert-gate-' + $runId)
    if (Test-Path -LiteralPath $copyRoot) { throw 'Inert gate copy must not exist' }
    Copy-Item -LiteralPath $bundle -Destination $copyRoot -Recurse
    $inertHarness = Get-Item -LiteralPath (Join-Path $copyRoot $harness[0].path)
    if (-not $inertHarness.FullName.StartsWith($copyRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or $inertHarness.PSIsContainer -or ($inertHarness.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Inert gate must remove only its copied regular harness file' }
    Remove-Item -LiteralPath $inertHarness.FullName
    $preflightContextPath = Join-Path $reportRoot 'preflight-context.json'
    $preflightPhase = if ($actualEnvironment.elevated) { 'Prepare' } else { 'Query' }
    $parameters = @{ Phase = $preflightPhase; DisposableVm = $true; ContextPath = $preflightContextPath; ReportDirectory = (Join-Path $reportRoot 'preflight-restoration') }
    if ($preflightPhase -eq 'Prepare') { $parameters.QuerySid = $fixtureContext.querySid; $parameters.RollbackReference = $fixtureContext.rollbackReference }
    else { $roleContext.querySid = $actualEnvironment.userSid; Write-BundleJson -Value $roleContext -Path $preflightContextPath }
    [Environment]::SetEnvironmentVariable('REGQRY_VM_PHASE', '', 'Process')
    Remove-Item -LiteralPath Env:\REGQRY_VM_ID -ErrorAction SilentlyContinue
    $beforeFailure = @{}
    foreach ($name in $saved.Keys) { $beforeFailure[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    $errorText = $null
    try { & (Join-Path $copyRoot 'run-vm-tests.ps1') @parameters }
    catch { $errorText = $_.Exception.Message }
    if (-not $errorText -or $errorText -notmatch [regex]::Escape('Missing bundle payload: ' + $harness[0].path)) { throw ('Inert VM preflight did not reject: ' + $errorText) }
    foreach ($name in $beforeFailure.Keys) {
        if ([Environment]::GetEnvironmentVariable($name, 'Process') -cne $beforeFailure[$name]) { throw ('VM preflight failed to restore ' + $name) }
    }
    $record = Get-Content -LiteralPath (Join-Path $parameters.ReportDirectory 'result.json') -Raw -Encoding utf8 | ConvertFrom-Json
    $preflight = Get-Content -LiteralPath (Join-Path $parameters.ReportDirectory 'preflight/result.json') -Raw -Encoding utf8 | ConvertFrom-Json
    if ($record.globalHarnessesStarted -ne 0 -or $preflight.processesStarted -ne 0) { throw 'Invalid VM payload reached execution' }
    if ($preflightPhase -eq 'Prepare' -and (Test-Path -LiteralPath $preflightContextPath)) { throw 'Invalid payload created a preparation context' }
    $result.cases += [ordered]@{ name = 'preflight-environment-restoration'; status = 'pass'; expectedRejection = $errorText; globalHarnessesStarted = 0; inertCopy = $copyRoot }
    # Direct --ignored cannot bypass the harness's independent Rust guard.
    foreach ($name in $saved.Keys) { Remove-Item -LiteralPath ('Env:\' + $name) -ErrorAction SilentlyContinue }
    foreach ($case in @('vm_prepare', 'vm_roots_and_physical_views', 'vm_minimum_permissions_and_partial_failure', 'vm_link_sources_explicit_aliases_cycles_and_lookalikes', 'processes::vm_cli_processes', 'shells::vm_cli_shells', 'performance::vm_scaling_baseline')) {
        $logName = $case.Replace('::', '.')
        $ran = Invoke-BundleProcess -Program (Join-Path $bundle $harness[0].path) -Arguments @('--ignored', '--exact', $case, '--nocapture')
        [IO.File]::WriteAllText((Join-Path $reportRoot ($logName + '.stdout.txt')), $ran.stdout, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $reportRoot ($logName + '.stderr.txt')), $ran.stderr, [Text.UTF8Encoding]::new($false))
        if ($ran.timedOut -or $ran.exitCode -eq 0 -or -not $ran.stderr.Contains('missing REGQRY_VM_CONFIRM') -or $ran.stdout.Contains('VM_OPERATION_START') -or $ran.stdout.Contains('FIXTURE_CREATED')) { throw ('Direct ignored test bypassed the VM guard: ' + $case) }
        $result.cases += [ordered]@{ name = 'direct-ignored-' + $case; status = 'pass'; exitCode = $ran.exitCode; globalHarnessesStarted = 0 }
    }
    $result.status = 'pass'
    Write-Output ('VM rejection gates passed: ' + $result.cases.Count)
} catch { $result.error = $_.Exception.Message; throw }
finally {
    $result.finishedAtUtc = [DateTime]::UtcNow.ToString('o')
    try { Write-BundleJson -Value $result -Path (Join-Path $reportRoot 'result.json') }
    finally { Restore-BundleEnvironment -Saved $saved }
}

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputDirectory,
    [Parameter(Mandatory)][string]$ReportDirectory,
    [Parameter(Mandatory)][string]$PowerShell7,
    [switch]$GitHubHostedVm
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release/support.ps1')
# The explicit opt-in and real workflow context precede any account or registry
# mutation. This runner is not for a developer workstation or self-hosted job.
if (-not $GitHubHostedVm -or $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
    $env:GITHUB_REPOSITORY -cne 'inaku-Gyan/RegQry' -or $env:GITHUB_RUN_ID -notmatch '^\d+$' -or $env:GITHUB_RUN_ATTEMPT -notmatch '^\d+$') {
    throw 'Requires explicit opt-in in the canonical GitHub-hosted Windows job'
}
$native = Get-BundleEnvironment
if (-not $native.elevated -or $native.runnerProcessMachine -ne 0) { throw 'Hosted preparation requires the native elevated runner token' }
$inputRoot = (Get-Item -LiteralPath $InputDirectory).FullName
$reportRoot = New-ReleaseDirectory $ReportDirectory
$built = Read-ReleaseJson (Join-Path $inputRoot 'build.json')
$head = & git -C (Split-Path -Parent $PSScriptRoot) rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $built.status -cne 'pass' -or $built.kind -cne 'regqry-native-assets' -or
    $built.scriptsCommit -cne $head -or $built.source.git.sha1 -cne $head -or $built.scriptsDirty -or $built.target -cne $native.nativeTarget) {
    throw 'Hosted fixture inputs must match the actual native clean checkout'
}
$userName = 'regqry' + [guid]::NewGuid().ToString('N').Substring(0, 10)
$sharedRoot = New-ReleaseDirectory (Join-Path $env:RUNNER_TEMP ('regqry-hosted-' + [guid]::NewGuid().ToString('N')))
$record = [ordered]@{
    schemaVersion = 1; kind = 'regqry-hosted-registry-check'; status = 'fail'
    scope = 'actual hosted ordinary-user registry checks; not clean/minimum or visible-terminal acceptance'
    startedAtUtc = [DateTime]::UtcNow.ToString('o'); target = $built.target; source = $built.source
    userArchiveSha256 = $built.user.sha256; testArchiveSha256 = $built.tests.sha256
    setupEnvironment = $native; querySid = $null; queryEnvironment = $null; sharedDirectory = $sharedRoot
    workflow = [ordered]@{ repository=$env:GITHUB_REPOSITORY; runId=$env:GITHUB_RUN_ID; attempt=$env:GITHUB_RUN_ATTEMPT; job=$env:GITHUB_JOB; workflowRef=$env:GITHUB_WORKFLOW_REF; runner=$env:RUNNER_NAME; image=$env:ImageOS; imageVersion=$env:ImageVersion }
    lifecycle = [ordered]@{ mode='github-hosted-job'; contract='https://docs.github.com/en/actions/how-tos/manage-runners/github-hosted-runners/use-github-hosted-runners'; observedDestruction=$false; accountRemoved=$false }
    worker = $null; error = $null
}
$account = $null; $process = $null; $processStarted = $false; $password = $null; $workerOut = $null; $workerErr = $null
$saved = @{}
foreach ($name in @('GH_TOKEN','GITHUB_TOKEN','CARGO_REGISTRY_TOKEN','CARGO_REGISTRIES_CRATES_IO_TOKEN')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    # Preserve original reports. Only local archive locations in this derived
    # record change when moving an artifact between fresh hosted machines.
    $built.sourceArchive = Join-Path $inputRoot $built.source.file
    $built.user.archive = Join-Path $inputRoot ([IO.Path]::GetFileName($built.user.archive))
    $built.tests.archive = Join-Path $inputRoot ('tests/' + [IO.Path]::GetFileName($built.tests.archive))
    foreach ($asset in @(@{path=$built.sourceArchive;hash=$built.source.sha256},@{path=$built.user.archive;hash=$built.user.sha256},@{path=$built.tests.archive;hash=$built.tests.sha256})) {
        if ((Get-ReleaseHash $asset.path) -cne $asset.hash) { throw 'Downloaded hosted input archive differs from its build record' }
    }
    Write-BundleJson $built (Join-Path $reportRoot 'relocated-build.json')
    & (Join-Path $PSScriptRoot 'check-release-assets.ps1') -BuildReport (Join-Path $reportRoot 'relocated-build.json') -ReportDirectory (Join-Path $reportRoot 'asset-preflight') -PowerShell7 $PowerShell7
    $expanded = Expand-ReleaseZip $built.tests.archive (Join-Path $sharedRoot 'bundle')
    $bundleRoot = Join-Path $expanded ('regqry-v' + $built.version + '-tests-' + $built.target)
    if ((Get-ReleaseHash (Join-Path $bundleRoot 'bundle-manifest.json')) -cne $built.tests.manifestSha256) { throw 'Hosted bundle manifest identity changed' }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'hosted/worker.ps1') -Destination (Join-Path $sharedRoot 'worker.ps1')
    $workerReports = New-ReleaseDirectory (Join-Path $sharedRoot 'reports')
    $contextPath = Join-Path $sharedRoot 'fixture-context.json'
    $startPath = Join-Path $sharedRoot 'start-query.json'
    $readyPath = Join-Path $workerReports 'ready.json'
    $configuration = [ordered]@{ schemaVersion=1; bundle=$bundleRoot; manifestSha256=$built.tests.manifestSha256; context=$contextPath; start=$startPath; ready=$readyPath; reports=$workerReports; powerShell7=$PowerShell7 }
    $configurationPath = Join-Path $sharedRoot 'worker-config.json'
    Write-BundleJson $configuration $configurationPath
    $random = [byte[]]::new(32); $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($random) } finally { $rng.Dispose() }
    $password = ConvertTo-SecureString ([Convert]::ToBase64String($random) + 'aA1!') -AsPlainText -Force
    $account = New-LocalUser -Name $userName -Password $password -AccountExpires ([DateTime]::Now.AddDays(1)) -Description 'Disposable RegQry hosted acceptance user'
    $record.querySid = $account.SID.Value
    Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $account
    if (@(Get-LocalGroupMember -SID 'S-1-5-32-544' | Where-Object { $_.SID.Value -ceq $account.SID.Value }).Count -ne 0) { throw 'Query account must not belong to Administrators' }
    & icacls.exe $sharedRoot /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' ('*' + $account.SID.Value + ':(OI)(CI)RX') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot secure hosted shared inputs' }
    & icacls.exe $workerReports /grant:r ('*' + $account.SID.Value + ':(OI)(CI)M') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot grant the query account its report directory' }
    foreach ($name in $saved.Keys) { Remove-Item -LiteralPath ('Env:\' + $name) -ErrorAction SilentlyContinue }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $start.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + (Join-Path $sharedRoot 'worker.ps1') + '" -Configuration "' + $configurationPath + '"'
    $start.WorkingDirectory = $sharedRoot; $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.UserName = $userName; $start.Domain = $env:COMPUTERNAME; $start.Password = $password; $start.LoadUserProfile = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false, $true); $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false, $true)
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $start
    if (-not $process.Start()) { throw 'Cannot start the ordinary-user profile holder' }
    $processStarted = $true
    $workerOut = $process.StandardOutput.ReadToEndAsync(); $workerErr = $process.StandardError.ReadToEndAsync()
    $readyWatch = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $readyPath)) {
        if ($process.HasExited) { throw 'Ordinary worker exited before its profile/token readiness handshake' }
        if ($readyWatch.Elapsed.TotalSeconds -ge 120) { throw 'Ordinary worker profile readiness timed out' }
        Start-Sleep -Milliseconds 200
    }
    $ready = Read-ReleaseJson $readyPath
    if ($ready.status -cne 'ready' -or $ready.environment.userSid -cne $record.querySid -or $ready.environment.elevated -or
        $ready.environment.nativeTarget -cne $built.target -or -not $ready.userHiveLoaded -or -not $ready.classesReady) { throw 'Ordinary worker token/profile/native identity is invalid' }
    $record.queryEnvironment = $ready.environment
    $lifecycleReference = 'github-actions:' + $env:GITHUB_REPOSITORY + '/runs/' + $env:GITHUB_RUN_ID + '/attempts/' + $env:GITHUB_RUN_ATTEMPT + '/jobs/' + $env:GITHUB_JOB
    & (Join-Path $bundleRoot 'run-vm-tests.ps1') -Phase Prepare -DisposableVm -ContextPath $contextPath -QuerySid $record.querySid -RollbackReference $lifecycleReference -PowerShell7 $PowerShell7 -ExpectedManifestSha256 $built.tests.manifestSha256 -ReportDirectory (Join-Path $reportRoot 'prepare')
    Write-BundleJson ([ordered]@{ status='prepared'; contextSha256=(Get-ReleaseHash $contextPath) }) ($startPath + '.tmp')
    [IO.File]::Move(($startPath + '.tmp'), $startPath)
    if (-not $process.WaitForExit(1500000)) { throw 'Ordinary query worker timed out' }
    if ($process.ExitCode -ne 0) { throw 'Ordinary query worker failed; inspect its original streams and reports' }
    $record.worker = Read-ReleaseJson (Join-Path $workerReports 'worker-result.json')
    if ($record.worker.status -cne 'pass' -or $record.worker.environment.elevated -or $record.worker.environment.userSid -cne $record.querySid) { throw 'Ordinary query worker did not provide matching successful evidence' }
    $record.status = 'pass'
} catch { $record.error = $_.Exception.Message; throw }
finally {
    try {
        if ($processStarted) {
            if (-not $process.HasExited) {
                & (Join-Path $env:WINDIR 'System32/taskkill.exe') /PID $process.Id /T /F | Out-Null
                if (-not $process.WaitForExit(10000)) { throw 'Owned worker tree did not stop' }
            }
            if ($workerOut) { [IO.File]::WriteAllText((Join-Path $reportRoot 'worker.stdout.txt'), $workerOut.GetAwaiter().GetResult(), [Text.UTF8Encoding]::new($false)) }
            if ($workerErr) { [IO.File]::WriteAllText((Join-Path $reportRoot 'worker.stderr.txt'), $workerErr.GetAwaiter().GetResult(), [Text.UTF8Encoding]::new($false)) }
        }
        if ($process) { $process.Dispose() }
        if ($account) {
            $currentAccount = Get-LocalUser -Name $userName
            if ($currentAccount.SID.Value -cne $account.SID.Value) { throw 'Temporary query account changed; refuse cleanup of another identity' }
            Remove-LocalUser -SID $account.SID
            $record.lifecycle.accountRemoved = $true
        }
        if (Test-Path -LiteralPath (Join-Path $sharedRoot 'reports')) { Copy-Item -LiteralPath (Join-Path $sharedRoot 'reports') -Destination (Join-Path $reportRoot 'ordinary') -Recurse }
        if (Test-Path -LiteralPath (Join-Path $sharedRoot 'fixture-context.json')) { Copy-Item -LiteralPath (Join-Path $sharedRoot 'fixture-context.json') -Destination $reportRoot }
    } catch { $record.status = 'fail'; $record.error = ($record.error + '; cleanup: ' + $_.Exception.Message); throw }
    finally {
        if ($password) { $password.Dispose() }
        $record.finishedAtUtc = [DateTime]::UtcNow.ToString('o')
        try { Write-BundleJson $record (Join-Path $reportRoot 'result.json') }
        finally { Restore-BundleEnvironment $saved }
    }
}

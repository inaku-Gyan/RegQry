[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Prepare', 'Query')][string]$Phase,
    [Parameter(Mandatory)][string]$ContextPath,
    [switch]$DisposableVm,
    [string]$QuerySid,
    [string]$RollbackReference,
    [ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedManifestSha256,
    [string]$ReportDirectory = (Join-Path ([IO.Path]::GetTempPath()) ('regqry-vm-results-' + [guid]::NewGuid().ToString('N')))
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'support.ps1')
$reportRoot = [IO.Path]::GetFullPath($ReportDirectory)
$contextFile = [IO.Path]::GetFullPath($ContextPath)
$bundlePrefix = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
foreach ($path in @($reportRoot, $contextFile)) {
    if ($path.TrimEnd('\') -eq $PSScriptRoot.TrimEnd('\') -or $path.StartsWith($bundlePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Context and reports must be outside the verified bundle' }
}
if (Test-Path -LiteralPath $reportRoot) { throw 'ReportDirectory must not exist' }
New-Item -ItemType Directory -Path $reportRoot | Out-Null
$result = [ordered]@{
    schemaVersion = 1; status = 'fail'; phase = $Phase
    scope = 'explicit disposable-VM registry suite; operator rollback and formal matrix binding are separate'
    startedAtUtc = [DateTime]::UtcNow.ToString('o')
    manifestSha256 = $null; environment = $null; contextSha256 = $null
    context = $null; globalHarnessesStarted = 0; cases = @()
    cleanup = 'not-started'; error = $null
}
$names = @('REGQRY_TEST_BIN', 'REGQRY_VM_CONFIRM', 'REGQRY_VM_PHASE', 'REGQRY_VM_ID', 'REGQRY_VM_NONCE', 'REGQRY_VM_QUERY_SID', 'REGQRY_VM_ROLLBACK')
$saved = @{}
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$context = $null
try {
    # This is an explicit operator attestation, not a heuristic claim that VM detection proves disposability.
    if (-not $DisposableVm) { throw 'Requires -DisposableVm and a rollback reference; never run this suite on a developer workstation' }
    if ($Phase -eq 'Prepare') {
        if (Test-Path -LiteralPath $contextFile) { throw 'Preparation context must not exist; rerunning preparation never adopts an existing fixture' }
        if ($QuerySid -notmatch '^S-1-5-21-[0-9]+-[0-9]+-[0-9]+-[0-9]+$' -or [string]::IsNullOrWhiteSpace($RollbackReference)) { throw 'Preparation requires an ordinary-user QuerySid and a nonempty RollbackReference' }
        $canonicalSid = [Security.Principal.SecurityIdentifier]::new($QuerySid)
        if ($canonicalSid.Value -cne $QuerySid) { throw 'QuerySid must use its canonical form' }
    } else {
        if ($QuerySid -or $RollbackReference) { throw 'Query uses the prepared identity; do not override QuerySid or RollbackReference' }
        $contextItem = Get-Item -LiteralPath $contextFile
        if ($contextItem.PSIsContainer -or ($contextItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Context must be a regular file' }
        $context = Get-Content -LiteralPath $contextFile -Raw -Encoding utf8 | ConvertFrom-Json
        if ($context.schemaVersion -ne 1 -or $context.kind -ne 'regqry-disposable-vm-context' -or $context.status -ne 'prepared' -or
            $context.id -cnotmatch '^[a-f0-9]{32}$' -or $context.nonce -cnotmatch '^[a-f0-9]{64}$' -or
            $context.querySid -notmatch '^S-1-5-21-[0-9]+-[0-9]+-[0-9]+-[0-9]+$' -or
            [string]::IsNullOrWhiteSpace($context.rollbackReference) -or $context.manifestSha256 -cnotmatch '^[a-f0-9]{64}$') {
            throw 'Invalid or incomplete preparation context'
        }
    }
    $manifestPath = Join-Path $PSScriptRoot 'bundle-manifest.json'
    $result.manifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ExpectedManifestSha256 -and $result.manifestSha256 -ine $ExpectedManifestSha256) { throw 'VM bundle manifest differs from the expected identity' }
    if ($context -and $context.manifestSha256 -cne $result.manifestSha256) { throw 'Query bundle differs from the prepared bundle' }
    $result.environment = Get-BundleEnvironment
    if ($Phase -eq 'Prepare' -and -not $result.environment.elevated) { throw 'Preparation requires elevation; query must run separately without elevation' }
    if ($Phase -eq 'Query') {
        if ($result.environment.elevated -or $result.environment.userSid -cne $context.querySid) { throw 'Query requires the prepared user SID and a non-elevated token' }
        if ($result.environment.osVersion -cne $context.setupEnvironment.osVersion -or $result.environment.nativeTarget -cne $context.setupEnvironment.nativeTarget -or
            $env:COMPUTERNAME -cne $context.computerName) { throw 'Prepared context belongs to a different machine/environment' }
    }
    # Run the existing complete payload/PE/inventory verifier; ignored VM cases stay ignored here.
    foreach ($name in $names) { Remove-Item -LiteralPath ('Env:\' + $name) -ErrorAction SilentlyContinue }
    & (Join-Path $PSScriptRoot 'run-tests.ps1') -ReportDirectory (Join-Path $reportRoot 'preflight') -ExpectedManifestSha256 $result.manifestSha256
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    $inventory = @($manifest.tests | Where-Object targetName -eq 'vm_registry')
    if ($inventory.Count -ne 1 -or $inventory[0].ignored -ne 5) { throw 'Expected the complete VM harness with five ignored cases' }
    $expectedCases = @('processes::vm_cli_processes: test', 'vm_link_sources_explicit_aliases_cycles_and_lookalikes: test', 'vm_minimum_permissions_and_partial_failure: test', 'vm_prepare: test', 'vm_roots_and_physical_views: test')
    foreach ($case in $expectedCases) { if ($case -cnotin $inventory[0].names) { throw 'VM harness inventory is incomplete' } }
    if ($Phase -eq 'Prepare') {
        $random = [byte[]]::new(32)
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($random) } finally { $rng.Dispose() }
        $context = [ordered]@{
            schemaVersion = 1; kind = 'regqry-disposable-vm-context'; status = 'preparing'
            id = [guid]::NewGuid().ToString('N'); nonce = ([BitConverter]::ToString($random)).Replace('-', '').ToLowerInvariant()
            querySid = $QuerySid; rollbackReference = $RollbackReference; computerName = $env:COMPUTERNAME
            manifestSha256 = $result.manifestSha256; source = $manifest.source
            setupEnvironment = $result.environment; preparedAtUtc = $null
            cleanup = 'VM rollback/destruction required; no recursive deletion or link-target cleanup'
        }
        # CreateNew is intentional: no overwrite even if a concurrent preparation won the path.
        $json = ($context | ConvertTo-Json -Depth 20) + "`n"
        $stream = [IO.File]::Open($contextFile, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json); $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    }
    $result.context = $context
    $result.contextSha256 = (Get-FileHash -LiteralPath $contextFile -Algorithm SHA256).Hash.ToLowerInvariant()
    $env:REGQRY_TEST_BIN = Join-Path $PSScriptRoot 'regqry.exe'
    $env:REGQRY_VM_CONFIRM = 'disposable-vm-rollback-required'
    $env:REGQRY_VM_PHASE = $Phase.ToLowerInvariant()
    $env:REGQRY_VM_ID = $context.id
    $env:REGQRY_VM_NONCE = $context.nonce
    $env:REGQRY_VM_QUERY_SID = $context.querySid
    $env:REGQRY_VM_ROLLBACK = $context.rollbackReference
    $result.cleanup = 'VM_ROLLBACK_REQUIRED'
    $cases = if ($Phase -eq 'Prepare') { @('vm_prepare') } else { @('vm_roots_and_physical_views', 'vm_minimum_permissions_and_partial_failure', 'vm_link_sources_explicit_aliases_cycles_and_lookalikes', 'processes::vm_cli_processes') }
    foreach ($case in $cases) {
        $result.globalHarnessesStarted++
        $ran = Invoke-BundleProcess -Program (Join-Path $PSScriptRoot $inventory[0].path) -Arguments @('--ignored', '--exact', $case, '--test-threads=1', '--nocapture') -TimeoutSeconds 180
        [IO.File]::WriteAllText((Join-Path $reportRoot ($case + '.stdout.txt')), $ran.stdout, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $reportRoot ($case + '.stderr.txt')), $ran.stderr, [Text.UTF8Encoding]::new($false))
        $passed = -not $ran.timedOut -and $ran.exitCode -eq 0 -and $ran.stdout.Contains('test result: ok. 1 passed; 0 failed; 0 ignored;')
        $result.cases += [ordered]@{ name = $case; status = $(if ($passed) { 'pass' } else { 'fail' }); arguments = $ran.arguments; exitCode = $ran.exitCode; timedOut = $ran.timedOut; elapsedMs = $ran.elapsedMs; stdout = $case + '.stdout.txt'; stderr = $case + '.stderr.txt' }
    }
    if (@($result.cases | Where-Object status -ne 'pass').Count -ne 0) { throw 'VM suite failed; preserve records and roll back the disposable VM' }
    if ($Phase -eq 'Prepare') {
        $context.status = 'prepared'
        $context.preparedAtUtc = [DateTime]::UtcNow.ToString('o')
        Write-BundleJson -Value $context -Path $contextFile
    }
    $result.contextSha256 = (Get-FileHash -LiteralPath $contextFile -Algorithm SHA256).Hash.ToLowerInvariant()
    $result.status = 'pass'
    Write-Output ('VM ' + $Phase + ' passed; rollback/destruction remains required')
} catch {
    $result.error = $_.Exception.Message
    throw
} finally {
    $result.finishedAtUtc = [DateTime]::UtcNow.ToString('o')
    try { Write-BundleJson -Value $result -Path (Join-Path $reportRoot 'result.json') }
    finally { Restore-BundleEnvironment -Saved $saved }
}

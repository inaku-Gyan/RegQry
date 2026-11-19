function Read-ReleaseEvidenceFile {
    param([string]$Root, [string]$Path)
    Assert-ReleasePath $Path
    $file = Join-Path $Root $Path
    Get-ReleaseHash $file | Out-Null
    $file
}

function Expand-ReleaseEvidenceArchive {
    param([string]$Archive, [string]$Tag)
    # Short extraction paths also support deeply nested logs on PowerShell 5.1.
    $expanded = Expand-ReleaseZip $Archive (Join-Path ([IO.Path]::GetTempPath()) ('rq-evidence-' + [guid]::NewGuid().ToString('N')))
    $items = @(Get-ChildItem -LiteralPath $expanded -Force)
    if ($items.Count -ne 1 -or -not $items[0].PSIsContainer -or $items[0].Name -cne ('regqry-' + $Tag + '-acceptance')) { throw 'Acceptance ZIP requires exactly its canonical versioned root directory' }
    $items[0].FullName
}

function Get-ReleaseEvidencePrefix {
    param([string]$Path)
    $Path.Substring(0, $Path.LastIndexOf('/') + 1)
}

function Assert-ReleaseRunLogs {
    param([string]$Root, [object]$Run, [string]$Prefix, [int]$Passed, [int]$Ignored)
    if ($Run.status -cne 'pass' -or $Run.exitCode -ne 0 -or $Run.timedOut -ne $false -or $Run.elapsedMs -lt 0) { throw 'A required executed test did not pass' }
    $stdoutPath = Read-ReleaseEvidenceFile $Root ($Prefix + $Run.stdout)
    Read-ReleaseEvidenceFile $Root ($Prefix + $Run.stderr) | Out-Null
    $stdout = [IO.File]::ReadAllText($stdoutPath, [Text.UTF8Encoding]::new($false, $true))
    if (-not [regex]::IsMatch($stdout, ('test result: ok\. ' + $Passed + ' passed; 0 failed; ' + $Ignored + ' ignored;'))) { throw 'Recorded result is not supported by its raw harness output' }
    $stdout
}

function Assert-ReleasePortableRecord {
    param([string]$Root, [string]$Path, [object]$Build, [string]$Sid)
    $portable = Read-ReleaseJson (Read-ReleaseEvidenceFile $Root $Path)
    $environment = $portable.environment
    if ($portable.status -cne 'pass' -or $portable.manifestSha256 -cne $Build.tests.manifestSha256 -or $portable.source.sha256 -cne $Build.source.sha256 -or
        $portable.source.git.sha1 -cne $Build.source.git.sha1 -or $environment.elevated -ne $false -or $environment.userSid -cne $Sid -or
        $environment.nativeTarget -cne $Build.target -or $environment.runnerProcessMachine -ne 0 -or
        $environment.cargoOnPath -ne $false -or $environment.rustcOnPath -ne $false) { throw 'Portable acceptance must match the native candidate and actual ordinary token without build tools on PATH' }
    if (@($portable.tests).Count -ne @($Build.testInventory).Count -or @($Build.testInventory).Count -eq 0) { throw 'Portable harness inventory is incomplete' }
    $prefix = Get-ReleaseEvidencePrefix $Path
    $count = 0
    foreach ($test in $portable.tests) {
        $expected = @($Build.testInventory | Where-Object path -ceq $test.path)
        if ($expected.Count -ne 1 -or $expected[0].runnable -ne $test.runnable -or $expected[0].ignored -ne $test.ignored) { throw 'Portable harness identity/counts differ from the frozen inventory' }
        Assert-ReleaseRunLogs $Root $test $prefix $test.runnable $test.ignored | Out-Null
        $count += $test.runnable
    }
    if ($count -le 0 -or $portable.passedTests -ne $count) { throw 'Portable run did not execute the declared inventory' }
    $count
}

function Assert-ReleaseFixturePhase {
    param([string]$Root, [string]$Path, [string]$Phase, [object]$Build, [string]$Sid)
    $record = Read-ReleaseJson (Read-ReleaseEvidenceFile $Root $Path)
    $elevated = $Phase -ceq 'Prepare'
    if ($record.status -cne 'pass' -or $record.phase -cne $Phase -or $record.environment.elevated -ne $elevated -or
        $record.environment.nativeTarget -cne $Build.target -or $record.environment.runnerProcessMachine -ne 0 -or
        $record.manifestSha256 -cne $Build.tests.manifestSha256 -or $record.context.source.sha256 -cne $Build.source.sha256 -or
        $record.context.source.git.sha1 -cne $Build.source.git.sha1 -or $record.context.querySid -cne $Sid -or
        $record.context.id -cnotmatch '^[a-f0-9]{32}$' -or $record.context.nonce -cnotmatch '^[a-f0-9]{64}$' -or
        $record.contextSha256 -cnotmatch '^[a-f0-9]{64}$' -or $record.context.rollbackReference -cnotmatch '^github-actions:inaku-Gyan/RegQry/runs/[0-9]+/attempts/[0-9]+/jobs/[a-zA-Z0-9_-]+$') { throw 'Fixture phase does not identify the native candidate, guarded context and required token role' }
    if (-not $elevated -and $record.environment.userSid -cne $Sid) { throw 'Query token differs from the prepared ordinary identity' }
    $names = if ($elevated) { @('vm_prepare') } else { @('vm_roots_and_physical_views','vm_minimum_permissions_and_partial_failure','vm_link_sources_explicit_aliases_cycles_and_lookalikes','processes::vm_cli_processes','shells::vm_cli_shells','performance::vm_scaling_baseline') }
    if (@($record.cases).Count -ne $names.Count -or $record.globalHarnessesStarted -ne $names.Count) { throw 'Required fixture case inventory is incomplete' }
    $prefix = Get-ReleaseEvidencePrefix $Path
    foreach ($name in $names) {
        $case = @($record.cases | Where-Object name -ceq $name)
        if ($case.Count -ne 1) { throw ('Missing fixture case: ' + $name) }
        $stdout = Assert-ReleaseRunLogs $Root $case[0] $prefix 1 0
        if ($stdout -notmatch ('VM_OPERATION_START phase=' + $Phase.ToLowerInvariant() + ' id=' + [regex]::Escape($record.context.id))) { throw 'Fixture raw log lacks its guarded identity/phase' }
        if ($name -ceq 'shells::vm_cli_shells' -and $stdout -notmatch 'SHELL_SUMMARY shells=3 cases_per_shell=[1-9][0-9]* status=pass scope=owned-vm-query') { throw 'All three actual query shells are required' }
    }
    $record
}

function Assert-ReleaseHostedStage {
    param([string]$Root, [string]$Path, [string]$ProvenancePath, [object]$Candidate, [object]$Build, [string]$Origin)
    $hosted = Read-ReleaseJson (Read-ReleaseEvidenceFile $Root $Path)
    $proof = Read-ReleaseJson (Read-ReleaseEvidenceFile $Root $ProvenancePath)
    if ($hosted.schemaVersion -ne 1 -or $hosted.kind -cne 'regqry-hosted-registry-check' -or $hosted.status -cne 'pass' -or
        $hosted.target -cne $Build.target -or $hosted.source.sha256 -cne $Build.source.sha256 -or $hosted.source.git.sha1 -cne $Candidate.commit -or
        $hosted.userArchiveSha256 -cne $Build.user.sha256 -or $hosted.testArchiveSha256 -cne $Build.tests.sha256 -or
        $hosted.installation -cne $Origin -or $hosted.querySid -notmatch '^S-1-5-21-([0-9]+-){3}[0-9]+$' -or
        $hosted.setupEnvironment.elevated -ne $true -or $hosted.setupEnvironment.nativeTarget -cne $Build.target -or
        $hosted.queryEnvironment.elevated -ne $false -or $hosted.queryEnvironment.userSid -cne $hosted.querySid -or
        $hosted.queryEnvironment.nativeTarget -cne $Build.target -or $hosted.queryEnvironment.runnerProcessMachine -ne 0 -or
        $hosted.queryEnvironment.osVersion -cne $hosted.setupEnvironment.osVersion -or [string]::IsNullOrWhiteSpace($hosted.workflow.imageVersion) -or
        $hosted.setupEnvironment.userSid -ceq $hosted.querySid -or $hosted.lifecycle.mode -cne 'github-hosted-job' -or
        $hosted.lifecycle.accountRemoved -ne $true -or $hosted.lifecycle.observedDestruction -ne $false) { throw 'Hosted acceptance lacks the original candidate, separate ordinary account, or honest provider lifecycle record' }
    $expectedLabel = if ($Build.target -ceq 'x86_64-pc-windows-msvc') { 'windows-2025-vs2026' } else { 'windows-11-vs2026-arm' }
    $os = [version]$hosted.queryEnvironment.osVersion
    $expectedProduct = if ($Build.target -ceq 'x86_64-pc-windows-msvc') { 3 } else { 1 }
    if ($os.Major -ne 10 -or $hosted.queryEnvironment.osProductType -ne $expectedProduct -or ($expectedProduct -eq 1 -and $os.Build -lt 26100)) { throw 'Hosted record does not identify its actual Windows Server/client environment' }
    if ($proof.schemaVersion -ne 1 -or $proof.kind -cne 'regqry-github-hosted-provenance' -or
        $proof.run.repository.id -ne 1462950131 -or $proof.run.path -cne '.github/workflows/release.yml' -or
        $proof.run.head_sha -cne $Candidate.commit -or $proof.run.head_branch -cne $Candidate.tag -or $proof.run.event -cnotin @('push','workflow_dispatch') -or
        $proof.run.id -ne $hosted.workflow.runId -or $proof.job.run_id -ne $proof.run.id -or $proof.job.run_attempt -ne $hosted.workflow.attempt -or
        $proof.job.id -le 0 -or $proof.job.head_sha -cne $Candidate.commit -or $proof.job.status -cne 'completed' -or $proof.job.conclusion -cne 'success' -or $proof.job.runner_name -cne $hosted.workflow.runner -or
        $proof.job.runner_group_name -cne 'GitHub Actions' -or $expectedLabel -cnotin @($proof.job.labels) -or 'self-hosted' -cin @($proof.job.labels) -or
        [DateTimeOffset]$proof.job.completed_at -lt [DateTimeOffset]$hosted.finishedAtUtc -or
        [DateTimeOffset]$proof.job.started_at -gt [DateTimeOffset]$hosted.startedAtUtc -or
        $hosted.workflow.repository -cne 'inaku-Gyan/RegQry') { throw 'Original GitHub run/job provenance does not establish a successful native hosted release job' }
    $prefix = Get-ReleaseEvidencePrefix $Path
    $ready = Read-ReleaseJson (Read-ReleaseEvidenceFile $Root ($prefix + 'ordinary/ready.json'))
    if ($ready.status -cne 'ready' -or $ready.environment.userSid -cne $hosted.querySid -or $ready.environment.elevated -ne $false -or
        $ready.environment.runnerProcessMachine -ne 0 -or $ready.environment.nativeTarget -cne $Build.target -or $ready.environment.osVersion -cne $hosted.setupEnvironment.osVersion -or
        $ready.userHiveLoaded -ne $true -or $ready.classesReady -ne $true -or [string]::IsNullOrWhiteSpace($ready.profile)) { throw 'The actual ordinary profile/token readiness handshake is missing' }
    $prepare = Assert-ReleaseFixturePhase $Root ($prefix + 'prepare/result.json') Prepare $Build $hosted.querySid
    $lifecycleReference = 'github-actions:inaku-Gyan/RegQry/runs/' + $hosted.workflow.runId + '/attempts/' + $hosted.workflow.attempt + '/jobs/' + $hosted.workflow.job
    if ($prepare.context.rollbackReference -cne $lifecycleReference) { throw 'Fixture lifecycle reference differs from its actual hosted workflow job' }
    $worker = Read-ReleaseJson (Read-ReleaseEvidenceFile $Root ($prefix + 'ordinary/worker-result.json'))
    foreach ($queryName in @('query-bundle','query-installed')) {
        $queryPath = $prefix + 'ordinary/' + $queryName + '/result.json'
        $query = Assert-ReleaseFixturePhase $Root $queryPath Query $Build $hosted.querySid
        if ($query.context.id -cne $prepare.context.id -or $query.context.nonce -cne $prepare.context.nonce -or $query.contextSha256 -cne $prepare.contextSha256 -or $query.context.rollbackReference -cne $lifecycleReference -or
            $query.environment.osVersion -cne $prepare.environment.osVersion -or $query.environment.cargoOnPath -ne $false -or $query.environment.rustcOnPath -ne $false) { throw 'Query fixture, machine or isolated PATH differs from preparation' }
        Assert-ReleasePortableRecord $Root ((Get-ReleaseEvidencePrefix $queryPath) + 'preflight/result.json') $Build $hosted.querySid | Out-Null
        $expectedCli = if ($queryName -ceq 'query-bundle') { $Build.user.cliSha256 } else { $worker.installation.cliSha256 }
        $expectedOrigin = if ($queryName -ceq 'query-bundle') { 'bundle' } else { 'installed' }
        if ($query.cli.sha256 -cne $expectedCli -or $query.cli.origin -cne $expectedOrigin) { throw 'The fixture suite did not use the expected bundled/installed CLI' }
    }
    $install = $worker.installation
    if ($worker.kind -cne 'regqry-hosted-query-worker' -or $worker.status -cne 'pass' -or $worker.environment.elevated -ne $false -or
        $worker.environment.userSid -cne $hosted.querySid -or $worker.environment.nativeTarget -cne $Build.target -or $worker.environment.runnerProcessMachine -ne 0 -or
        $install.cliSha256 -cne $hosted.worker.installation.cliSha256 -or $install.status -cne 'pass' -or $install.origin -cne $Origin -or
        $install.sourceSha256 -cne $Build.source.sha256 -or $install.cliSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $install.compiler -cnotcontains 'release: 1.100.0' -or $install.compiler -cnotcontains ('host: ' + $Build.target) -or
        $install.compilerSha256 -cnotmatch '^[a-f0-9]{64}$' -or $install.cargoSha256 -cne $Build.toolset.cargoSha256 -or
        $install.command.exitCode -ne 0 -or $install.command.timedOut -ne $false -or '--locked' -cnotin @($install.command.arguments) -or
        $Build.target -cnotin @($install.command.arguments)) { throw 'Actual pinned ordinary-user source installation evidence is incomplete' }
    $installPrefix = $prefix + 'ordinary/'
    Read-ReleaseEvidenceFile $Root ($installPrefix + $install.command.stdout) | Out-Null
    $installLog = [IO.File]::ReadAllText((Read-ReleaseEvidenceFile $Root ($installPrefix + $install.command.stderr)), [Text.UTF8Encoding]::new($false, $true))
    if (-not [regex]::IsMatch($installLog, 'Installed package.*regqry')) { throw 'Original Cargo output does not support the recorded installation' }
    if ($Origin -ceq 'registry' -and ('--path' -cin @($install.command.arguments) -or '--version' -cnotin @($install.command.arguments) -or ('=' + $Candidate.version) -cnotin @($install.command.arguments) -or $install.registryArchiveSha256 -cne $Build.source.sha256)) { throw 'Registry installation must use the exact version and actual downloaded archive bytes' }
    if ($Origin -ceq 'source-archive' -and '--path' -cnotin @($install.command.arguments)) { throw 'Candidate source installation must use its original unpacked archive' }
    [ordered]@{ target=$Build.target; osVersion=$hosted.queryEnvironment.osVersion; ordinarySid=$hosted.querySid; tests=(@($Build.testInventory | ForEach-Object runnable) | Measure-Object -Sum).Sum; origin=$Origin; runId=$proof.run.id; jobId=$proof.job.id; cliSha256=$install.cliSha256 }
}

function Assert-ReleaseEvidence {
    param([object]$Candidate, [string]$CandidateId, [string]$Root, [switch]$RequireRegistry)
    $evidence = Read-ReleaseJson (Join-Path $Root 'acceptance.json')
    if ($evidence.schemaVersion -ne 2 -or $evidence.kind -cne 'regqry-release-acceptance' -or $evidence.candidateId -cne $CandidateId -or
        $evidence.commit -cne $Candidate.commit -or $evidence.tag -cne $Candidate.tag -or $evidence.status -cne 'pass' -or $evidence.stage -cnotin @('source','registry') -or
        ($RequireRegistry -and $evidence.stage -cne 'registry')) { throw 'Actions-only acceptance schema 2 must identify the frozen candidate and required source/registry stage' }
    Assert-ReleaseInventory $Root @($evidence.files) @('acceptance.json')
    if (@($evidence.assets).Count -ne 5) { throw 'Acceptance must bind all five frozen core archives' }
    foreach ($asset in $Candidate.assets) {
        $bound = @($evidence.assets | Where-Object name -ceq $asset.name)
        if ($bound.Count -ne 1 -or $bound[0].sha256 -cne $asset.sha256) { throw 'Acceptance uses different archive bytes' }
    }
    if (@($evidence.checks).Count -ne 14) { throw 'All fourteen acceptance groups need original records' }
    for ($number=1; $number -le 14; $number++) {
        $check = @($evidence.checks | Where-Object id -ceq ('A{0:00}' -f $number))
        if ($check.Count -ne 1 -or $check[0].status -cne 'pass' -or @($check[0].records).Count -eq 0 -or [string]::IsNullOrWhiteSpace($check[0].observation)) { throw ('Missing or failed acceptance group A{0:00}' -f $number) }
        foreach ($path in $check[0].records) { Read-ReleaseEvidenceFile $Root $path | Out-Null }
    }
    $audit = Read-ReleaseJson (Read-ReleaseEvidenceFile $Root 'quality/dependencies.json')
    $model = Read-ReleaseJson (Read-ReleaseEvidenceFile $Root 'quality/release-model.json')
    if ($audit.status -cne 'pass' -or $audit.tool -cne 'cargo-deny 0.21.0' -or $audit.lockSha256 -cne $Candidate.lockSha256 -or
        @($audit.advisoryDatabases).Count -eq 0 -or @($audit.indexSnapshot).Count -eq 0 -or [string]::IsNullOrWhiteSpace($audit.fetchedAtUtc) -or
        $model.status -cne 'pass' -or @($model.cases).Count -eq 0 -or @($model.cases|Where-Object status -cne 'pass').Count -ne 0 -or $model.scope -notmatch 'synthetic') { throw 'Original pinned dependency audit and explicitly synthetic release-model records are required' }
    foreach ($id in @('minimum-clean-clients','visible-terminal-and-physical-keyboard')) {
        $deferred = @($evidence.deferredChecks | Where-Object id -ceq $id)
        if ($deferred.Count -ne 1 -or $deferred[0].status -cne 'not-run') { throw 'Deferred minimum/clean/visual/physical checks must remain explicitly unexecuted' }
    }
    if (@($evidence.deferredChecks).Count -ne 2) { throw 'Deferred checks must identify exactly the two accepted unexecuted groups' }
    if (@($evidence.platforms).Count -ne 2) { throw 'Both native hosted architectures are required' }
    $summary = @()
    foreach ($id in @('hosted-x64','hosted-arm64')) {
        $platform = @($evidence.platforms | Where-Object id -ceq $id)
        if ($platform.Count -ne 1 -or $platform[0].status -cne 'pass') { throw ('Missing or failed hosted platform: ' + $id) }
        $platform = $platform[0]
        $target = if ($id -ceq 'hosted-x64') { 'x86_64-pc-windows-msvc' } else { 'aarch64-pc-windows-msvc' }
        $build = @($Candidate.builds | Where-Object target -ceq $target)[0]
        $source = Assert-ReleaseHostedStage $Root $platform.sourceRun $platform.sourceProvenance $Candidate $build 'source-archive'
        $registry = $null
        if ($evidence.stage -ceq 'registry') { $registry = Assert-ReleaseHostedStage $Root $platform.registryRun $platform.registryProvenance $Candidate $build 'registry' }
        $summary += [ordered]@{ id=$id; target=$target; source=$source; registry=$registry; tests=$source.tests }
    }
    if ($evidence.stage -ceq 'registry') {
        $originalArchive = Read-ReleaseEvidenceFile $Root 'original/source-acceptance.zip'
        if ($evidence.sourceArchiveSha256 -cnotmatch '^[a-f0-9]{64}$' -or (Get-ReleaseHash $originalArchive) -cne $evidence.sourceArchiveSha256) { throw 'The preserved original source acceptance archive is missing or changed' }
        $originalRoot = Expand-ReleaseEvidenceArchive $originalArchive $Candidate.tag
        $original = Read-ReleaseJson (Join-Path $originalRoot 'acceptance.json')
        if ($original.stage -cne 'source') { throw 'Registry evidence must retain the original source-stage archive without a recursive registry chain' }
        Assert-ReleaseEvidence $Candidate $CandidateId $originalRoot | Out-Null
        foreach ($file in $original.files) {
            $current = @($evidence.files|Where-Object path -ceq $file.path)
            if ($current.Count -ne 1 -or $current[0].sha256 -cne $file.sha256 -or $current[0].size -ne $file.size) { throw 'Original source acceptance content changed during registry collection' }
        }
        foreach ($platform in $original.platforms) {
            $current = @($evidence.platforms|Where-Object id -ceq $platform.id)[0]
            if ($current.sourceRun -cne $platform.sourceRun -or $current.sourceProvenance -cne $platform.sourceProvenance) { throw 'Registry evidence replaced its original source-stage identity' }
        }
    }
    $summary
}

function Read-ReleaseEvidenceFile {
    param([string]$Root, [string]$Path)
    Assert-ReleasePath $Path
    $file = Join-Path $Root $Path
    Get-ReleaseHash $file | Out-Null
    $file
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

function Assert-ReleaseEvidence {
    param([object]$Candidate, [string]$CandidateId, [string]$Root, [switch]$RequireRegistry)
    $evidence = Read-ReleaseJson (Join-Path $Root 'acceptance.json')
    if ($evidence.schemaVersion -ne 1 -or $evidence.kind -cne 'regqry-release-acceptance' -or $evidence.candidateId -cne $CandidateId -or $evidence.commit -cne $Candidate.commit -or $evidence.tag -cne $Candidate.tag -or $evidence.status -cne 'pass') { throw 'Acceptance evidence does not identify the frozen candidate' }
    Assert-ReleaseInventory $Root @($evidence.files) @('acceptance.json')
    if (@($evidence.assets).Count -ne 5) { throw 'Acceptance must bind all five frozen core archives' }
    foreach ($asset in $Candidate.assets) {
        $bound = @($evidence.assets | Where-Object name -ceq $asset.name)
        if ($bound.Count -ne 1 -or $bound[0].sha256 -cne $asset.sha256) { throw 'Acceptance uses different archive bytes' }
    }
    # The A01-A14 index is an operator mapping, backed by original records. It
    # supplements, never substitutes for, the executable/environment checks below.
    if (@($evidence.checks).Count -ne 14) { throw 'All fourteen acceptance groups need records' }
    for ($number = 1; $number -le 14; $number++) {
        $check = @($evidence.checks | Where-Object id -ceq ('A{0:00}' -f $number))
        if ($check.Count -ne 1 -or $check[0].status -cne 'pass' -or @($check[0].records).Count -eq 0 -or [string]::IsNullOrWhiteSpace($check[0].observation)) { throw ('Missing or failed acceptance group A{0:00}' -f $number) }
        foreach ($path in $check[0].records) { Read-ReleaseEvidenceFile $Root $path | Out-Null }
    }
    if (@($evidence.platforms).Count -ne 3) { throw 'The three formal native client systems are required' }
    $summary = @()
    foreach ($id in @('win10-x64', 'win11-x64', 'win11-arm64')) {
        $platform = @($evidence.platforms | Where-Object id -ceq $id)
        if ($platform.Count -ne 1) { throw ('Missing or duplicate formal platform: ' + $id) }
        $platform = $platform[0]
        $target = if ($id -ceq 'win11-arm64') { 'aarch64-pc-windows-msvc' } else { 'x86_64-pc-windows-msvc' }
        $build = @($Candidate.builds | Where-Object target -ceq $target)[0]
        if ($platform.status -cne 'pass' -or $platform.channel -cne 'general-availability' -or [string]::IsNullOrWhiteSpace($platform.edition) -or [string]::IsNullOrWhiteSpace($platform.displayVersion)) { throw 'Formal acceptance needs actual stable client edition/version records' }
        $portablePath = Read-ReleaseEvidenceFile $Root $platform.portable
        $portable = Read-ReleaseJson $portablePath
        $environment = $portable.environment
        $os = [version]$environment.osVersion
        if ($environment.nativeTarget -cne $target -or $environment.runnerProcessMachine -ne 0 -or $environment.osProductType -ne 1 -or $environment.elevated -ne $false -or $environment.cargoOnPath -ne $false -or $environment.rustcOnPath -ne $false -or $environment.userSid -notmatch '^S-1-5-21-([0-9]+-){3}[0-9]+$') { throw 'Portable acceptance must use a native ordinary-user client without Cargo/rustc on PATH' }
        if ($os.Major -ne 10 -or ($id -ceq 'win10-x64' -and ($os.Build -ne 19045 -or $platform.displayVersion -cne '22H2')) -or ($id -ceq 'win11-x64' -and $os.Build -lt 22000) -or ($id -ceq 'win11-arm64' -and $os.Build -lt 26100)) { throw 'Formal OS build does not cover the required client matrix' }
        if ($portable.status -cne 'pass' -or $portable.manifestSha256 -cne $build.tests.manifestSha256 -or $portable.source.sha256 -cne $build.source.sha256 -or $portable.source.git.sha1 -cne $Candidate.commit) { throw 'Portable run uses another candidate' }
        $prefix = $platform.portable.Substring(0, $platform.portable.LastIndexOf('/') + 1)
        $count = 0
        if (@($portable.tests).Count -ne @($build.testInventory).Count -or @($build.testInventory).Count -eq 0) { throw 'Portable harness inventory is incomplete' }
        foreach ($test in $portable.tests) {
            $expected = @($build.testInventory | Where-Object path -ceq $test.path)
            if ($expected.Count -ne 1 -or $expected[0].runnable -ne $test.runnable -or $expected[0].ignored -ne $test.ignored) { throw 'Portable harness counts/identity differ from the frozen binary inventory' }
            Assert-ReleaseRunLogs $Root $test $prefix $test.runnable $test.ignored | Out-Null
            $count += $test.runnable
        }
        if ($count -le 0 -or $portable.passedTests -ne $count) { throw 'Portable run did not execute the declared test inventory' }
        $clean = Read-ReleaseJson (Read-ReleaseEvidenceFile $Root $platform.cleanSystem)
        if ($clean.kind -cne 'regqry-clean-system-record' -or $clean.status -cne 'pass' -or [string]::IsNullOrWhiteSpace($clean.snapshotId) -or $clean.target -cne $target -or $clean.osVersion -cne $environment.osVersion -or $clean.developmentToolsInstalled -ne $false -or $clean.extraRuntimeInstalled -ne $false -or $clean.candidateId -cne $CandidateId -or @($clean.inventoryRecords).Count -eq 0) { throw 'A restricted PATH is insufficient evidence of a clean system' }
        foreach ($path in $clean.inventoryRecords) { Read-ReleaseEvidenceFile $Root $path | Out-Null }
        $prepare = Read-ReleaseJson (Read-ReleaseEvidenceFile $Root $platform.vmPrepare)
        $query = Read-ReleaseJson (Read-ReleaseEvidenceFile $Root $platform.vmQuery)
        if ($prepare.status -cne 'pass' -or $prepare.phase -cne 'Prepare' -or $prepare.environment.elevated -ne $true -or $query.status -cne 'pass' -or $query.phase -cne 'Query' -or $query.environment.elevated -ne $false -or $query.environment.userSid -cne $query.context.querySid -or $query.environment.osVersion -cne $environment.osVersion -or $query.environment.nativeTarget -cne $target -or $prepare.context.id -cne $query.context.id -or $prepare.context.nonce -cne $query.context.nonce -or $prepare.contextSha256 -cne $query.contextSha256 -or $query.manifestSha256 -cne $build.tests.manifestSha256 -or $prepare.manifestSha256 -cne $query.manifestSha256) { throw 'VM setup/query identity, privileges or candidate differ' }
        foreach ($phase in @(@{ record = $prepare; path = $platform.vmPrepare; cases = @('vm_prepare') }, @{ record = $query; path = $platform.vmQuery; cases = @('vm_roots_and_physical_views', 'vm_minimum_permissions_and_partial_failure', 'vm_link_sources_explicit_aliases_cycles_and_lookalikes', 'processes::vm_cli_processes', 'shells::vm_cli_shells', 'performance::vm_scaling_baseline') })) {
            if (@($phase.record.cases).Count -ne $phase.cases.Count) { throw 'Required VM case inventory is incomplete' }
            $phasePrefix = $phase.path.Substring(0, $phase.path.LastIndexOf('/') + 1)
            foreach ($name in $phase.cases) {
                $case = @($phase.record.cases | Where-Object name -ceq $name)
                if ($case.Count -ne 1) { throw ('Missing VM case: ' + $name) }
                $stdout = Assert-ReleaseRunLogs $Root $case[0] $phasePrefix 1 0
                if ($stdout -notmatch ('VM_OPERATION_START phase=' + $phase.record.phase.ToLowerInvariant() + ' id=' + [regex]::Escape($query.context.id))) { throw 'VM raw log does not identify the guarded fixture/phase' }
                if ($name -ceq 'shells::vm_cli_shells') {
                    foreach ($shell in @('cmd', 'powershell', 'pwsh')) { if ($stdout -notmatch $shell) { throw 'Formal shell case must actually run all three shells' } }
                    if ($stdout -notmatch 'SHELL_SUMMARY shells=3 cases_per_shell=[1-9][0-9]* status=pass scope=owned-vm-query') { throw 'A required formal shell was not run' }
                }
            }
        }
        $rollback = Read-ReleaseJson (Read-ReleaseEvidenceFile $Root $platform.rollback)
        if ($rollback.kind -cne 'regqry-vm-rollback-record' -or $rollback.status -cne 'pass' -or $rollback.contextId -cne $query.context.id -or $rollback.reference -cne $query.context.rollbackReference -or $rollback.action -cnotin @('rollback', 'destroy') -or @($rollback.records).Count -eq 0 -or [DateTimeOffset]$rollback.completedAtUtc -le [DateTimeOffset]$query.finishedAtUtc) { throw 'Actual external VM rollback/destruction evidence is required' }
        foreach ($path in $rollback.records) { Read-ReleaseEvidenceFile $Root $path | Out-Null }
        $install = Read-ReleaseJson (Read-ReleaseEvidenceFile $Root $platform.sourceInstall)
        if ($install.kind -cne 'regqry-formal-source-install' -or $install.status -cne 'pass' -or $install.candidateId -cne $CandidateId -or $install.sourceSha256 -cne $build.source.sha256 -or $install.target -cne $target -or $install.osVersion -cne $environment.osVersion -or $install.compiler -cnotcontains 'release: 1.100.0' -or $install.compiler -cnotcontains ('host: ' + $target) -or $install.cliSha256 -cnotmatch '^[a-f0-9]{64}$' -or $install.elevated -ne $false -or @($install.records).Count -eq 0 -or $install.privateFixtureExitCode -ne 0 -or $install.source -cne 'candidate-archive') { throw 'Actual candidate-archive source installation with private fixture evidence is required' }
        foreach ($path in $install.records) { Read-ReleaseEvidenceFile $Root $path | Out-Null }
        $terminals = if ($id -ceq 'win10-x64') { @('classic') } elseif ($id -ceq 'win11-x64') { @('windows-terminal') } else { @('classic', 'windows-terminal') }
        if (@($platform.terminals).Count -ne ($terminals.Count * 2)) { throw 'The visible terminal matrix is incomplete' }
        foreach ($terminal in $terminals) {
            foreach ($width in @(80, 120)) {
                $visual = @($platform.terminals | Where-Object { $_.terminal -ceq $terminal -and $_.columns -eq $width })
                if ($visual.Count -ne 1 -or $visual[0].status -cne 'pass' -or $visual[0].visible -ne $true -or $visual[0].physicalCtrlCExitCode -ne 130 -or [string]::IsNullOrWhiteSpace($visual[0].version) -or [string]::IsNullOrWhiteSpace($visual[0].measurement) -or @($visual[0].records).Count -eq 0) { throw 'Visible terminal, measured width and physical cancellation observations are required' }
                foreach ($path in $visual[0].records) { Read-ReleaseEvidenceFile $Root $path | Out-Null }
            }
        }
        if ($RequireRegistry) {
            $registry = Read-ReleaseJson (Read-ReleaseEvidenceFile $Root $platform.registryInstall)
            if ($registry.kind -cne 'regqry-formal-source-install' -or $registry.status -cne 'pass' -or $registry.source -cne 'crates.io' -or $registry.candidateId -cne $CandidateId -or $registry.sourceSha256 -cne $build.source.sha256 -or $registry.target -cne $target -or $registry.osVersion -cne $environment.osVersion -or $registry.elevated -ne $false -or $registry.privateFixtureExitCode -ne 0 -or $registry.compiler -cnotcontains 'release: 1.100.0' -or $registry.compiler -cnotcontains ('host: ' + $target) -or $registry.cliSha256 -cnotmatch '^[a-f0-9]{64}$' -or @($registry.records).Count -eq 0) { throw 'After Cargo publication, actual registry installation/private-fixture records are required on all three systems' }
            foreach ($path in $registry.records) { Read-ReleaseEvidenceFile $Root $path | Out-Null }
        }
        $summary += [ordered]@{ id = $id; osVersion = $environment.osVersion; target = $target; tests = $count; registry = [bool]$RequireRegistry }
    }
    $summary
}

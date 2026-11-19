[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReportDirectory)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release/support.ps1')
. (Join-Path $PSScriptRoot 'release/evidence.ps1')
. (Join-Path $PSScriptRoot 'release/acceptance.ps1')
$reportRoot = New-ReleaseDirectory $ReportDirectory
$fixtureRoot = New-ReleaseDirectory (Join-Path ([IO.Path]::GetTempPath()) ('rq-rel-' + [guid]::NewGuid().ToString('N')))
$result = [ordered]@{ schemaVersion = 1; status = 'fail'; scope = 'synthetic release-state/evidence model with mocked remote commands; no real publication, credentials, registry fixture, native ARM execution or formal acceptance'; fixtureRoot = $fixtureRoot; cases = @(); error = $null }
$saved = @{}
foreach ($name in @('GITHUB_ACTIONS', 'GITHUB_REF', 'GITHUB_REPOSITORY', 'GITHUB_EVENT_NAME', 'GITHUB_OUTPUT', 'GITHUB_STEP_SUMMARY', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT', 'GITHUB_SHA')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process'); Remove-Item -LiteralPath ('Env:\' + $name) -ErrorAction SilentlyContinue }
$originalLocation = (Get-Location).Path
$previousModel = Get-Variable -Name RegQryReleaseModel -Scope Global -ErrorAction SilentlyContinue
$global:RegQryReleaseModel = @{ projectRoot = (Split-Path -Parent $PSScriptRoot) }
$global:RegQryReleaseModel.fakeCommit = 'a' * 40
$global:RegQryReleaseModel.remote = $null; $global:RegQryReleaseModel.remoteFiles = @{}; $global:RegQryReleaseModel.nextId = 1; $global:RegQryReleaseModel.writes = 0
$global:RegQryReleaseModel.remoteFailure = $false; $global:RegQryReleaseModel.downloadCorruption = $false; $global:RegQryReleaseModel.uploadFailure = $false
$global:RegQryReleaseModel.checkoutFailure = ''; $global:RegQryReleaseModel.packageVersion = '0.1.0'
$global:RegQryReleaseModel.httpRequests = 0; $global:RegQryReleaseModel.settingsReads = 0
$global:RegQryReleaseModel.notesRequests = 0
$global:RegQryReleaseModel.originalArtifacts = @{}

function Invoke-WebRequest {
    $global:RegQryReleaseModel.httpRequests++
    throw 'Synthetic model forbids unmocked HTTP'
}

function Test-ReleaseCase {
    param([string]$Name, [scriptblock]$Body)
    & $Body
    $result.cases += [ordered]@{ name = $Name; status = 'pass' }
}
function Assert-Rejected {
    param([scriptblock]$Body, [string]$Reason)
    $caught = $false
    try { & $Body | Out-Null } catch { if ($_.Exception.Message -notmatch $Reason) { throw }; $caught = $true }
    if (-not $caught) { throw ('Expected rejection: ' + $Reason) }
}
function git {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'status') { if ($global:RegQryReleaseModel.checkoutFailure -ceq 'dirty') { ' M Cargo.lock' }; return }
    if ($args[0] -eq 'rev-parse') { $global:RegQryReleaseModel.fakeCommit; return }
    if ($args[0] -eq 'merge-base') { if ($global:RegQryReleaseModel.checkoutFailure -ceq 'ancestry') { $global:LASTEXITCODE = 1 }; return }
    throw 'Unexpected git command in synthetic release model'
}
function cargo {
    $global:LASTEXITCODE = 0
    if ($args -contains 'metadata') { '{"packages":[{"name":"regqry","version":"' + $global:RegQryReleaseModel.packageVersion + '","rust_version":"1.100.0","edition":"2024","source":null}],"target_directory":"unused-synthetic-target"}'; return }
    throw 'Unexpected Cargo execution in synthetic release model'
}
function Get-Content {
    [CmdletBinding()]
    param([string]$LiteralPath, [switch]$Raw, [string]$Encoding)
    if ($LiteralPath -ceq (Join-Path $global:RegQryReleaseModel.projectRoot 'CHANGELOG.md')) { return "# Changelog`n`n## [0.1.0] - 2026-11-19`n`nSynthetic release only.`n" }
    Microsoft.PowerShell.Management\Get-Content @PSBoundParameters
}
function gh {
    $arguments = @($args); $global:LASTEXITCODE = 0
    if ($global:RegQryReleaseModel.remoteFailure) { $global:LASTEXITCODE = 1; return }
    if ($arguments[0] -ceq 'api') {
        $endpoint = @($arguments | Where-Object { $_ -like 'repos/*' })[0]
        if ($endpoint -ceq 'repos/inaku-Gyan/RegQry') { '{"id":1462950131,"full_name":"inaku-Gyan/RegQry","default_branch":"main","permissions":{"admin":true,"push":' + $(if ($global:RegQryReleaseModel.noPushVisibility -or $global:RegQryReleaseModel.installationToken) { 'false' } else { 'true' }) + '}}'; return }
        if ($endpoint -ceq 'repos/inaku-Gyan/RegQry/releases/generate-notes') {
            if ($arguments -cnotcontains 'POST' -or $arguments -cnotcontains 'tag_name=v0.1.0') { throw 'Capability check did not use the exact tagged generate-notes request' }
            $global:RegQryReleaseModel.notesRequests++
            if ($global:RegQryReleaseModel.noPushVisibility) { $global:LASTEXITCODE = 1; return }
            if ($global:RegQryReleaseModel.malformedNotes) { '{"message":"not a permission proof"}'; return }
            '{"name":"Synthetic capability check only","body":"Not saved or used as release notes."}'
            return
        }
        if ($endpoint -match '/commits/') { $global:RegQryReleaseModel.fakeCommit; return }
        if ($endpoint -match '/releases\?') { if ($global:RegQryReleaseModel.remote) { '[[' + ($global:RegQryReleaseModel.remote | ConvertTo-Json -Depth 40 -Compress) + ']]' } else { '[[]]' }; return }
        if ($endpoint -match '/assets\?') { '[' + (ConvertTo-Json -InputObject @($global:RegQryReleaseModel.remote.assets) -Depth 40 -Compress) + ']'; return }
        if ($endpoint -match '/actions/runs/[0-9]+/artifacts\?') {
            ConvertTo-Json -InputObject @($global:RegQryReleaseModel.originalArtifacts.Keys | ForEach-Object { @{name=$_;expired=$false} }) -Compress
            return
        }
        if ($endpoint -match '/actions/runs/6000/attempts/1/jobs\?') { ConvertTo-Json -InputObject @($global:RegQryReleaseModel.actionsJobs) -Depth 40 -Compress; return }
        if ($endpoint -match '/actions/runs/6000$') { $global:RegQryReleaseModel.actionsRun | ConvertTo-Json -Depth 40 -Compress; return }
        if ($endpoint -match '/immutable-releases$') {
            if ($arguments -contains 'PUT') { $global:RegQryReleaseModel.writes++; $global:RegQryReleaseModel.settingsEnabled = $true; return }
            $global:RegQryReleaseModel.settingsReads++
            if ($global:RegQryReleaseModel.settingsDenied) { $global:LASTEXITCODE = 1; return }
            '{"enabled":' + $(if ($global:RegQryReleaseModel.settingsEnabled) { 'true' } else { 'false' }) + '}'
            return
        }
        throw ('Unexpected mocked API endpoint: ' + $endpoint)
    }
    if ($arguments[0] -ceq 'run' -and $arguments[1] -ceq 'download') {
        $name = $arguments[[array]::IndexOf($arguments, '--name') + 1]
        $directory = $arguments[[array]::IndexOf($arguments, '--dir') + 1]
        if (-not $global:RegQryReleaseModel.originalArtifacts.ContainsKey($name)) { throw 'Synthetic original artifact is unavailable' }
        Copy-Item -LiteralPath $global:RegQryReleaseModel.originalArtifacts[$name] -Destination $directory
        return
    }
    if ($arguments[0] -cne 'release') { throw 'Unexpected remote command' }
    switch ($arguments[1]) {
        'create' {
            $global:RegQryReleaseModel.writes++
            $global:RegQryReleaseModel.remote = [pscustomobject]@{ id = 123; tag_name = 'v0.1.0'; draft = $true; immutable = $false; body = 'Synthetic notes'; assets = @() }
        }
        'upload' {
            $global:RegQryReleaseModel.writes++
            $path = $arguments[3]; $name = Split-Path -Leaf $path
            if ($global:RegQryReleaseModel.remoteFiles.ContainsKey($name)) { throw 'Mock refuses overwriting an existing asset' }
            $destination = Join-Path $fixtureRoot ('remote-' + $global:RegQryReleaseModel.nextId)
            Copy-Item -LiteralPath $path -Destination $destination
            $global:RegQryReleaseModel.remoteFiles[$name] = $destination
            $global:RegQryReleaseModel.remote.assets += [pscustomobject]@{ name = $name; id = $global:RegQryReleaseModel.nextId++; size = (Get-Item -LiteralPath $path).Length; digest = 'sha256:' + (Get-ReleaseHash $path); state = 'uploaded' }
            if ($global:RegQryReleaseModel.uploadFailure) { $global:RegQryReleaseModel.uploadFailure = $false; $global:LASTEXITCODE = 1 }
        }
        'download' {
            $name = $arguments[[array]::IndexOf($arguments, '--pattern') + 1]
            $directory = $arguments[[array]::IndexOf($arguments, '--dir') + 1]
            Copy-Item -LiteralPath $global:RegQryReleaseModel.remoteFiles[$name] -Destination (Join-Path $directory $name)
            if ($global:RegQryReleaseModel.downloadCorruption) { [IO.File]::AppendAllText((Join-Path $directory $name), 'changed') }
        }
        'edit' {
            $global:RegQryReleaseModel.writes++
            if ($arguments -contains '--notes-file') {
                $path = $arguments[[array]::IndexOf($arguments, '--notes-file') + 1]
                $global:RegQryReleaseModel.remote.body = [IO.File]::ReadAllText($path)
                return
            }
            if ($arguments -notcontains '--draft=false') { throw 'Unexpected synthetic release edit' }
            $global:RegQryReleaseModel.remote.draft = $false
            $global:RegQryReleaseModel.remote.immutable = $global:RegQryReleaseModel.settingsEnabled
            if ($global:RegQryReleaseModel.publishFailure) { $global:LASTEXITCODE = 1; $global:RegQryReleaseModel.publishFailure = $false }
        }
        default { throw 'Synthetic model forbids unexpected release writes' }
    }
}

function New-ModelHostedStage {
    param([object]$Candidate, [object]$Build, [string]$Root, [string]$Relative, [string]$Origin, [string]$ProofPath)
    $stageRoot = New-ReleaseDirectory (Join-Path $Root $Relative)
    $ordinaryRoot = New-ReleaseDirectory (Join-Path $stageRoot 'ordinary')
    $os = if ($Build.target -ceq 'x86_64-pc-windows-msvc') { '10.0.26100' } else { '10.0.26200' }
    $environment = [ordered]@{ osVersion=$os; osProductType=$(if ($Build.target -ceq 'x86_64-pc-windows-msvc') {3} else {1}); nativeTarget=$Build.target; runnerProcessMachine=0; elevated=$false; cargoOnPath=$false; rustcOnPath=$false; userSid='S-1-5-21-1-2-3-1001'; powerShell='synthetic' }
    $setup = $environment | ConvertTo-Json | ConvertFrom-Json
    $setup.elevated = $true; $setup.userSid = 'S-1-5-21-1-2-3-500'
    $runner = 'synthetic-' + $Origin + '-' + $Build.target
    $workflow = @{ repository='inaku-Gyan/RegQry'; runId=6000; attempt=1; job='acceptance'; runner=$runner; imageVersion='synthetic'; workflowRef=('inaku-Gyan/RegQry/.github/workflows/release.yml@refs/tags/' + $Candidate.tag) }
    $context = @{ id=('1'*32); nonce=('2'*64); querySid=$environment.userSid; source=$Build.source; rollbackReference='github-actions:inaku-Gyan/RegQry/runs/6000/attempts/1/jobs/acceptance' }
    Write-BundleJson @{ status='ready'; environment=$environment; profile='C:\Users\SyntheticQuery'; userHiveLoaded=$true; classesReady=$true } (Join-Path $ordinaryRoot 'ready.json')
    $installedSha = '4' * 64
    foreach ($phase in @(@{path='prepare';name='Prepare';environment=$setup;origin='bundle';cli=$Build.user.cliSha256},@{path='ordinary/query-bundle';name='Query';environment=$environment;origin='bundle';cli=$Build.user.cliSha256},@{path='ordinary/query-installed';name='Query';environment=$environment;origin='installed';cli=$installedSha})) {
        $phaseRoot = New-ReleaseDirectory (Join-Path $stageRoot $phase.path)
        $names = if ($phase.name -ceq 'Prepare') { @('vm_prepare') } else { @('vm_roots_and_physical_views','vm_minimum_permissions_and_partial_failure','vm_link_sources_explicit_aliases_cycles_and_lookalikes','processes::vm_cli_processes','shells::vm_cli_shells','performance::vm_scaling_baseline') }
        $vm = [ordered]@{ status='pass'; phase=$phase.name; environment=$phase.environment; context=$context; contextSha256=('3'*64); manifestSha256=$Build.tests.manifestSha256; globalHarnessesStarted=$names.Count; cases=@(); finishedAtUtc='2026-11-19T00:08:00Z'; cli=@{origin=$phase.origin;sha256=$phase.cli} }
        foreach ($name in $names) {
            $log = $name.Replace('::','.')
            $stdout = 'SYNTHETIC MODEL' + [char]10 + 'VM_OPERATION_START phase=' + $phase.name.ToLowerInvariant() + ' id=' + $context.id + [char]10
            if ($name -ceq 'shells::vm_cli_shells') { $stdout += 'SHELL name=cmd status=pass cases=1' + [char]10 + 'SHELL name=powershell status=pass cases=1' + [char]10 + 'SHELL name=pwsh status=pass cases=1' + [char]10 + 'SHELL_SUMMARY shells=3 cases_per_shell=1 status=pass scope=owned-vm-query' + [char]10 }
            $stdout += 'test result: ok. 1 passed; 0 failed; 0 ignored;' + [char]10
            [IO.File]::WriteAllText((Join-Path $phaseRoot ($log + '.stdout.txt')), $stdout)
            [IO.File]::WriteAllText((Join-Path $phaseRoot ($log + '.stderr.txt')), '')
            $vm.cases += @{name=$name;status='pass';exitCode=0;timedOut=$false;elapsedMs=1;stdout=($log+'.stdout.txt');stderr=($log+'.stderr.txt')}
        }
        Write-BundleJson $vm (Join-Path $phaseRoot 'result.json')
        if ($phase.name -ceq 'Query') {
            $preflight = New-ReleaseDirectory (Join-Path $phaseRoot 'preflight')
            $portable = @{status='pass';manifestSha256=$Build.tests.manifestSha256;source=$Build.source;environment=$environment;tests=@();passedTests=0}
            foreach ($test in $Build.testInventory) {
                $log = [IO.Path]::GetFileNameWithoutExtension($test.path)
                $text = 'SYNTHETIC MODEL' + [char]10 + 'test result: ok. ' + $test.runnable + ' passed; 0 failed; ' + $test.ignored + ' ignored;' + [char]10
                [IO.File]::WriteAllText((Join-Path $preflight ($log+'.stdout.txt')), $text)
                [IO.File]::WriteAllText((Join-Path $preflight ($log+'.stderr.txt')), '')
                $portable.tests += @{path=$test.path;status='pass';exitCode=0;timedOut=$false;elapsedMs=1;runnable=$test.runnable;ignored=$test.ignored;stdout=($log+'.stdout.txt');stderr=($log+'.stderr.txt')}
                $portable.passedTests += $test.runnable
            }
            Write-BundleJson $portable (Join-Path $preflight 'result.json')
        }
    }
    $arguments = @('install','--locked','--target',$Build.target,'--root','synthetic-root','--target-dir','synthetic-target')
    $arguments += if ($Origin -ceq 'registry') { @('regqry','--version',('=' + $Candidate.version)) } else { @('--path','synthetic-source') }
    $command = @{program='synthetic-cargo';arguments=$arguments;exitCode=0;timedOut=$false;elapsedMs=1;stdout='installation.stdout.txt';stderr='installation.stderr.txt'}
    [IO.File]::WriteAllText((Join-Path $ordinaryRoot 'installation.stdout.txt'), '')
    [IO.File]::WriteAllText((Join-Path $ordinaryRoot 'installation.stderr.txt'), 'SYNTHETIC Installed package regqry')
    $install = @{status='pass';origin=$Origin;sourceSha256=$Build.source.sha256;registryArchiveSha256=$(if ($Origin -ceq 'registry') {$Build.source.sha256} else {$null});compiler=$Build.compiler;compilerSha256=('5'*64);cargoSha256=$Build.toolset.cargoSha256;cliSha256=$installedSha;command=$command}
    $worker = @{kind='regqry-hosted-query-worker';status='pass';environment=$environment;installation=$install}
    Write-BundleJson $worker (Join-Path $ordinaryRoot 'worker-result.json')
    $hosted = @{schemaVersion=1;kind='regqry-hosted-registry-check';status='pass';target=$Build.target;source=$Build.source;userArchiveSha256=$Build.user.sha256;testArchiveSha256=$Build.tests.sha256;setupEnvironment=$setup;queryEnvironment=$environment;querySid=$environment.userSid;installation=$Origin;workflow=$workflow;lifecycle=@{mode='github-hosted-job';accountRemoved=$true;observedDestruction=$false};worker=$worker;startedAtUtc='2026-11-19T00:01:00Z';finishedAtUtc='2026-11-19T00:09:00Z'}
    Write-BundleJson $hosted (Join-Path $stageRoot 'result.json')
    $label = if ($Build.target -ceq 'x86_64-pc-windows-msvc') {'windows-2025-vs2026'} else {'windows-11-vs2026-arm'}
    $jobId = $(if ($Origin -ceq 'registry') {7100} else {7000}) + $(if ($Build.target -ceq 'x86_64-pc-windows-msvc') {1} else {2})
    $proof = @{schemaVersion=1;kind='regqry-github-hosted-provenance';run=@{id=6000;repository=@{id=1462950131};path='.github/workflows/release.yml';head_sha=$Candidate.commit;head_branch=$Candidate.tag;event='push'};job=@{id=$jobId;head_sha=$Candidate.commit;run_id=6000;run_attempt=1;status='completed';conclusion='success';runner_name=$runner;runner_group_name='GitHub Actions';labels=@($label);started_at='2026-11-19T00:00:00Z';completed_at='2026-11-19T00:10:00Z'}}
    Write-BundleJson $proof (Join-Path $Root $ProofPath)
}

function New-ModelEvidence {
    param([object]$Candidate, [string]$CandidateId, [string]$Root)
    New-Item -ItemType Directory -Path $Root | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Root 'provenance') | Out-Null
    $quality = New-ReleaseDirectory (Join-Path $Root 'quality')
    Write-BundleJson @{status='pass';tool='cargo-deny 0.21.0';lockSha256=$Candidate.lockSha256;fetchedAtUtc='2026-11-19T00:00:00Z';advisoryDatabases=@(@{commit=('a'*40)});indexSnapshot=@(@{path='synthetic';sha256=('b'*64)})} (Join-Path $quality 'dependencies.json')
    Write-BundleJson @{status='pass';scope='synthetic release-state model only';cases=@(@{name='synthetic';status='pass'})} (Join-Path $quality 'release-model.json')
    [IO.File]::WriteAllText((Join-Path $Root 'operator.txt'), 'SYNTHETIC MODEL. No profile, account, VM, cleanup, installation or formal acceptance actually ran.')
    $evidence = [ordered]@{schemaVersion=2;kind='regqry-release-acceptance';status='pass';stage='source';sourceArchiveSha256=$null;candidateId=$CandidateId;tag=$Candidate.tag;commit=$Candidate.commit;assets=@($Candidate.assets|ForEach-Object {@{name=$_.name;sha256=$_.sha256}});checks=@();platforms=@();deferredChecks=@(@{id='minimum-clean-clients';status='not-run'},@{id='visible-terminal-and-physical-keyboard';status='not-run'});files=@()}
    for ($index=1;$index -le 14;$index++) { $evidence.checks += @{id=('A{0:00}' -f $index);status='pass';observation='synthetic model only';records=@('operator.txt')} }
    foreach ($id in @('hosted-x64','hosted-arm64')) {
        $target = if ($id -ceq 'hosted-x64') {'x86_64-pc-windows-msvc'} else {'aarch64-pc-windows-msvc'}
        $build = @($Candidate.builds|Where-Object target -ceq $target)[0]
        foreach ($stage in @('source')) {
            $origin = if ($stage -ceq 'source') {'source-archive'} else {'registry'}
            New-ModelHostedStage $Candidate $build $Root ($stage+'/'+$id) $origin ('provenance/'+$stage+'-'+$id+'.json')
        }
        $evidence.platforms += @{id=$id;status='pass';sourceRun=('source/'+$id+'/result.json');sourceProvenance=('provenance/source-'+$id+'.json');registryRun=$null;registryProvenance=$null}
    }
    $evidence.files = @(Get-ReleaseInventory $Root)
    Write-BundleJson $evidence (Join-Path $Root 'acceptance.json')
    $copyRoot = New-ReleaseDirectory (Join-Path ([IO.Path]::GetTempPath()) ('rq-model-source-' + [guid]::NewGuid().ToString('N')))
    $sourceRoot = Join-Path $copyRoot ('regqry-' + $Candidate.tag + '-acceptance')
    Copy-Item -LiteralPath $Root -Destination $sourceRoot -Recurse
    $sourceArchive = Join-Path $copyRoot 'source.zip'
    Write-BundleArchive $sourceRoot $sourceArchive
    $originals = New-ReleaseDirectory (Join-Path $Root 'original')
    Copy-Item -LiteralPath $sourceArchive -Destination (Join-Path $originals 'source-acceptance.zip')
    $evidence.stage='registry';$evidence.sourceArchiveSha256=Get-ReleaseHash $sourceArchive
    foreach ($platform in $evidence.platforms) {
        $target = if ($platform.id -ceq 'hosted-x64') {'x86_64-pc-windows-msvc'} else {'aarch64-pc-windows-msvc'}
        $build = @($Candidate.builds|Where-Object target -ceq $target)[0]
        New-ModelHostedStage $Candidate $build $Root ('registry/'+$platform.id) registry ('provenance/registry-'+$platform.id+'.json')
        $platform.registryRun='registry/'+$platform.id+'/result.json'
        $platform.registryProvenance='provenance/registry-'+$platform.id+'.json'
    }
    $evidence.files = @(Get-ReleaseInventory $Root|Where-Object path -cne 'acceptance.json')
    Write-BundleJson $evidence (Join-Path $Root 'acceptance.json')
}


try {
    $buildRoot = New-ReleaseDirectory (Join-Path $fixtureRoot 'builds')
    $sourceRoot = New-ReleaseDirectory (Join-Path $fixtureRoot 'source/regqry-0.1.0')
    [IO.File]::WriteAllText((Join-Path $sourceRoot 'Cargo.toml'), "[package]`nname = `"regqry`"`nversion = `"0.1.0`"`n")
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Cargo.lock') -Destination $sourceRoot
    $sourceFiles = @(Get-ReleaseInventory $sourceRoot)
    $source = [pscustomobject]@{ file = 'regqry-0.1.0.crate'; sha256 = 'b' * 64; lockSha256 = Get-ReleaseHash (Join-Path $sourceRoot 'Cargo.lock'); git = [pscustomobject]@{ sha1 = $global:RegQryReleaseModel.fakeCommit } }
    foreach ($target in @('x86_64-pc-windows-msvc', 'aarch64-pc-windows-msvc')) {
        $root = New-ReleaseDirectory (Join-Path $buildRoot $target)
        New-Item -ItemType Directory -Path (Join-Path $root 'tests'), (Join-Path $root 'check') | Out-Null
        $sourceArchive = Join-Path $root $source.file
        & tar -czf $sourceArchive -C (Split-Path -Parent $sourceRoot) 'regqry-0.1.0/Cargo.toml' 'regqry-0.1.0/Cargo.lock'
        if ($LASTEXITCODE -ne 0) { throw 'Synthetic archive creation failed' }
        # Reuse one original archive; two independent compression timestamps are
        # deliberately not assumed byte-reproducible.
        if ($target -ceq 'aarch64-pc-windows-msvc') { Copy-Item -LiteralPath (Join-Path $buildRoot ('x86_64-pc-windows-msvc/' + $source.file)) -Destination $sourceArchive }
        $source.sha256 = Get-ReleaseHash $sourceArchive
        foreach ($kind in @('user', 'tests')) {
            $name = if ($kind -ceq 'user') { 'regqry-v0.1.0-' + $target } else { 'regqry-v0.1.0-tests-' + $target }
            $payload = New-ReleaseDirectory (Join-Path $fixtureRoot ('payload/' + $name))
            [IO.File]::WriteAllText((Join-Path $payload 'regqry.exe'), 'Synthetic identity data only; not a PE and never executed')
            $cliSha256 = Get-ReleaseHash (Join-Path $payload 'regqry.exe')
            $inventory = @(for ($index = 0; $index -lt 4; $index++) { @{ path = "tests/harness$index.exe"; runnable = @(0, 6, 7, 34)[$index]; ignored = @(0, 0, 8, 0)[$index] } })
            Write-BundleJson ([ordered]@{ target = $target; version = '0.1.0'; source = $source; tests = $inventory; files = @(@{ path = 'regqry.exe'; sha256 = $cliSha256 }) }) (Join-Path $payload 'bundle-manifest.json')
            $archive = Join-Path $root ($(if ($kind -ceq 'tests') { 'tests/' } else { '' }) + $name + '.zip')
            Write-BundleArchive $payload $archive
            $value = [ordered]@{ archive = $archive; sha256 = Get-ReleaseHash $archive; manifestSha256 = Get-ReleaseHash (Join-Path $payload 'bundle-manifest.json'); cliSha256 = $cliSha256 }
            if ($kind -ceq 'user') { $user = $value } else { $tests = $value }
        }
        $build = [ordered]@{ status = 'pass'; scriptsDirty = $false; scriptsCommit = $global:RegQryReleaseModel.fakeCommit; target = $target; version = '0.1.0'; source = $source; sourceFiles = $sourceFiles; compiler = @('release: 1.100.0', ('host: ' + $target)); cargo = 'cargo 1.100.0 (synthetic)'; rustFlags = @('-C', 'target-feature=+crt-static'); environment = @{ nativeTarget = $target }; toolset = @{ linkerSha256 = 'c' * 64; cargoSha256 = 'd' * 64; kernel32LibrarySha256 = 'f' * 64; ucrtLibrarySha256 = '0' * 64; sdkVersion = 'synthetic' }; user = $user; tests = $tests }
        Write-BundleJson $build (Join-Path $root 'build.json')
        Write-BundleJson @{ status = 'pass'; userArchiveSha256 = $user.sha256; testArchiveSha256 = $tests.sha256 } (Join-Path $root 'check/result.json')
    }
    $checkoutRoot = New-ReleaseDirectory (Join-Path $fixtureRoot 'checkout')
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'Cargo.lock') -Destination $checkoutRoot
    [IO.File]::WriteAllText((Join-Path $checkoutRoot 'CHANGELOG.md'), "# Changelog`n`n## [0.1.0] - 2026-11-19`n`nSynthetic release only.`n")
    Test-ReleaseCase 'stable tag / clean main ancestor / reviewed changelog' { Get-ReleaseCheckout $checkoutRoot 'v0.1.0' | Out-Null }
    foreach ($tag in @('v01.1.0', '0.1.0', 'v0.1.0-rc.1', 'main')) { Test-ReleaseCase ('reject tag ' + $tag) { Assert-Rejected { Get-ReleaseCheckout $checkoutRoot $tag } 'stable vMAJOR' } }
    Test-ReleaseCase 'reject dirty checkout' { $global:RegQryReleaseModel.checkoutFailure = 'dirty'; try { Assert-Rejected { Get-ReleaseCheckout $checkoutRoot 'v0.1.0' } 'clean' } finally { $global:RegQryReleaseModel.checkoutFailure = '' } }
    Test-ReleaseCase 'reject unmerged tag' { $global:RegQryReleaseModel.checkoutFailure = 'ancestry'; try { Assert-Rejected { Get-ReleaseCheckout $checkoutRoot 'v0.1.0' } 'merged' } finally { $global:RegQryReleaseModel.checkoutFailure = '' } }
    Test-ReleaseCase 'reject Cargo/tag version mismatch' { $global:RegQryReleaseModel.packageVersion = '0.2.0'; try { Assert-Rejected { Get-ReleaseCheckout $checkoutRoot 'v0.1.0' } 'disagree' } finally { $global:RegQryReleaseModel.packageVersion = '0.1.0' } }
    Test-ReleaseCase 'API failure is unknown, never absence' { $global:RegQryReleaseModel.remoteFailure = $true; try { Assert-Rejected { Get-ReleaseRemote 'inaku-Gyan/RegQry' 'v0.1.0' } 'unknown' } finally { $global:RegQryReleaseModel.remoteFailure = $false }; if ($global:RegQryReleaseModel.writes -ne 0) { throw 'Read failure caused a mutation' } }
    # Exercise the unchanged top-level script. Only external metadata/remote
    # commands and the not-yet-prepared changelog entry are supplied by the model.
    $modelScript = Join-Path $PSScriptRoot 'release.ps1'
    Test-ReleaseCase 'freeze exact original core assets and verify downloads' { & $modelScript -Action Freeze -Tag 'v0.1.0' -InputDirectory $buildRoot -OutputDirectory (Join-Path $fixtureRoot 'freeze') | Out-Null; if (@($global:RegQryReleaseModel.remote.assets).Count -ne 6) { throw 'Incomplete frozen asset set' } }
    $candidatePath = $global:RegQryReleaseModel.remoteFiles['candidate-manifest.json']
    $candidate = Read-ReleaseJson $candidatePath
    Test-ReleaseCase 'candidate validates both native model identities' { Assert-ReleaseCandidate $candidate 'v0.1.0' $global:RegQryReleaseModel.fakeCommit }
    Test-ReleaseCase 'frozen rerun performs no writes or builds' { $before = $global:RegQryReleaseModel.writes; & $modelScript -Action Freeze -Tag 'v0.1.0' -InputDirectory $buildRoot -OutputDirectory (Join-Path $fixtureRoot 'freeze-retry') | Out-Null; if ($global:RegQryReleaseModel.writes -ne $before) { throw 'Frozen retry mutated assets' } }
    Test-ReleaseCase 'dispatch reads original candidate without rebuilding' { $env:GITHUB_EVENT_NAME = 'workflow_dispatch'; try { & $modelScript -Action Inspect -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'inspect') | Out-Null } finally { Remove-Item Env:\GITHUB_EVENT_NAME }; if ($global:RegQryReleaseModel.writes -ne 7) { throw 'Recovery changed the assets' } }
    Test-ReleaseCase 'installation token with Contents write is accepted despite push false' {
        $global:RegQryReleaseModel.installationToken = $true; $before = $global:RegQryReleaseModel.writes; $requests = $global:RegQryReleaseModel.notesRequests
        try { & $modelScript -Action Inspect -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'installation-token') | Out-Null } finally { $global:RegQryReleaseModel.installationToken = $false }
        if ($global:RegQryReleaseModel.writes -ne $before) { throw 'Capability check saved a release or changed assets' }
        if ($global:RegQryReleaseModel.notesRequests -ne ($requests + 1)) { throw 'Inspect skipped the actual write-capability check' }
    }
    Test-ReleaseCase 'malformed capability response cannot establish draft visibility' {
        $global:RegQryReleaseModel.malformedNotes = $true; $before = $global:RegQryReleaseModel.writes
        try { Assert-Rejected { & $modelScript -Action Inspect -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'malformed-visibility') } 'Draft visibility' } finally { $global:RegQryReleaseModel.malformedNotes = $false }
        if ($global:RegQryReleaseModel.writes -ne $before) { throw 'Malformed capability response caused a write' }
    }
    Test-ReleaseCase 'missing push visibility is not interpreted as absence of drafts' {
        $global:RegQryReleaseModel.noPushVisibility = $true; $before = $global:RegQryReleaseModel.writes
        try { Assert-Rejected { & $modelScript -Action Inspect -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'invisible-draft') } 'Draft visibility' } finally { $global:RegQryReleaseModel.noPushVisibility = $false }
        if ($global:RegQryReleaseModel.writes -ne $before) { throw 'Filtered visibility caused a write' }
    }
    Test-ReleaseCase 'changed same-name asset stops without clobber' {
        $sourceAsset = @($candidate.assets | Where-Object name -ceq $source.file)[0]
        $changed = Join-Path (New-ReleaseDirectory (Join-Path $fixtureRoot 'changed')) $source.file
        [IO.File]::WriteAllText($changed, 'different bytes')
        $before = $global:RegQryReleaseModel.writes; Assert-Rejected { Sync-ReleaseAsset 'inaku-Gyan/RegQry' 'v0.1.0' $changed } 'conflict'
        if ($global:RegQryReleaseModel.writes -ne $before) { throw 'Conflict overwrote a remote asset' }
    }
    Test-ReleaseCase 'corrupted actual download is rejected' { $global:RegQryReleaseModel.downloadCorruption = $true; try { Assert-Rejected { & $modelScript -Action Inspect -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'bad-download') } 'differs' } finally { $global:RegQryReleaseModel.downloadCorruption = $false } }
    Test-ReleaseCase 'missing draft core asset restores original bytes with new server ID' {
        $name = $source.file
        $global:RegQryReleaseModel.remote.assets = @($global:RegQryReleaseModel.remote.assets | Where-Object name -cne $name); $global:RegQryReleaseModel.remoteFiles.Remove($name)
        $originals = New-ReleaseDirectory (Join-Path $fixtureRoot 'originals')
        foreach ($asset in $candidate.assets) {
            $path = if ($asset.name -ceq $name) { Join-Path $buildRoot ('x86_64-pc-windows-msvc/' + $name) } else { $global:RegQryReleaseModel.remoteFiles[$asset.name] }
            Copy-Item -LiteralPath $path -Destination (Join-Path $originals $asset.name)
        }
        & $modelScript -Action Restore -Tag 'v0.1.0' -InputDirectory $originals -OutputDirectory (Join-Path $fixtureRoot 'restore') | Out-Null
        Assert-ReleaseRemoteCandidate $candidate $global:RegQryReleaseModel.remote
    }
    Test-ReleaseCase 'upload succeeded remotely but command failed: retry skips exact file' {
        $path = Join-Path $fixtureRoot 'example.txt'; [IO.File]::WriteAllText($path, 'preserved bytes')
        $global:RegQryReleaseModel.uploadFailure = $true
        Assert-Rejected { Sync-ReleaseAsset 'inaku-Gyan/RegQry' 'v0.1.0' $path } 'unknown'
        $before = $global:RegQryReleaseModel.writes
        Sync-ReleaseAsset 'inaku-Gyan/RegQry' 'v0.1.0' $path | Out-Null
        if ($global:RegQryReleaseModel.writes -ne $before) { throw 'Uncertain upload was repeated' }
    }
    foreach ($mutation in @('commit', 'native', 'compiler', 'flags', 'source', 'duplicate-id', 'missing-sdk')) {
        Test-ReleaseCase ('reject candidate ' + $mutation) {
            $copy = $candidate | ConvertTo-Json -Depth 40 | ConvertFrom-Json
            switch ($mutation) {
                'commit' { $copy.commit = 'b' * 40 }
                'native' { $copy.builds[1].environment.nativeTarget = 'x86_64-pc-windows-msvc' }
                'compiler' { $copy.builds[1].compiler = @('release: 1.99.1') }
                'flags' { $copy.builds[0].rustFlags = @() }
                'source' { $copy.builds[1].source.sha256 = '0' * 64 }
                'duplicate-id' { $copy.assets[1].id = $copy.assets[0].id }
                'missing-sdk' { $copy.builds[0].toolset.sdkVersion = '' }
            }
            Assert-Rejected { Assert-ReleaseCandidate $copy 'v0.1.0' $global:RegQryReleaseModel.fakeCommit } 'candidate|native|identity|source|SDK'
        }
    }
    Test-ReleaseCase 'partial draft cannot trigger rebuilding' {
        $savedAssets = $global:RegQryReleaseModel.remote.assets; $global:RegQryReleaseModel.remote.assets = @(); try { Assert-Rejected { & $modelScript -Action Inspect -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'partial') } 'partial draft' } finally { $global:RegQryReleaseModel.remote.assets = $savedAssets }
    }
    Test-ReleaseCase 'fresh dispatch cannot build a new candidate' {
        $savedRemote = $global:RegQryReleaseModel.remote; $global:RegQryReleaseModel.remote = $null; $env:GITHUB_EVENT_NAME = 'workflow_dispatch'
        try { Assert-Rejected { & $modelScript -Action Inspect -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'fresh-dispatch') } 'already frozen' } finally { $global:RegQryReleaseModel.remote = $savedRemote; Remove-Item Env:\GITHUB_EVENT_NAME }
    }
    Test-ReleaseCase 'bare pass file cannot substitute for acceptance evidence' {
        $root = New-ReleaseDirectory (Join-Path $fixtureRoot 'empty-evidence')
        Write-BundleJson @{ status = 'pass' } (Join-Path $root 'acceptance.json')
        Assert-Rejected { Assert-ReleaseEvidence $candidate (Get-ReleaseHash $candidatePath) $root } 'frozen candidate'
    }
    $evidenceRoot = Join-Path $fixtureRoot 'regqry-v0.1.0-acceptance'
    $candidateId = Get-ReleaseHash $candidatePath
    New-ModelEvidence $candidate $candidateId $evidenceRoot
    $evidenceScript = Join-Path $PSScriptRoot 'release-evidence.ps1'
    Test-ReleaseCase 'new evidence template never marks observations passed' {
        $directory = Join-Path $fixtureRoot 'new-evidence'
        & $evidenceScript -Action New -CandidatePath $candidatePath -ExpectedCandidateSha256 $candidateId -Directory $directory | Out-Null
        $template = Read-ReleaseJson (Join-Path $directory 'acceptance.json')
        if ($template.status -cne 'missing' -or @($template.checks | Where-Object status -cne 'missing').Count -ne 0) { throw 'Unexecuted template claimed acceptance' }
        Assert-Rejected { & $evidenceScript -Action Pack -CandidatePath $candidatePath -ExpectedCandidateSha256 $candidateId -Directory $directory -ArchivePath (Join-Path $fixtureRoot 'missing-evidence.zip') } 'frozen candidate'
    }
    Test-ReleaseCase 'wrong recorded candidate ID cannot create an evidence template' {
        Assert-Rejected { & $evidenceScript -Action New -CandidatePath $candidatePath -ExpectedCandidateSha256 ('f' * 64) -Directory (Join-Path $fixtureRoot 'wrong-template') } 'recorded candidate ID'
    }
    Test-ReleaseCase 'complete synthetic evidence packs once without inventing results' {
        $archive = Join-Path $fixtureRoot 'synthetic-accepted.zip'
        & $evidenceScript -Action Pack -CandidatePath $candidatePath -ExpectedCandidateSha256 $candidateId -Directory $evidenceRoot -ArchivePath $archive -RequireRegistry | Out-Null
        Assert-Rejected { & $evidenceScript -Action Pack -CandidatePath $candidatePath -ExpectedCandidateSha256 $candidateId -Directory $evidenceRoot -ArchivePath $archive -RequireRegistry } 'never overwritten'
    }
    Test-ReleaseCase 'complete synthetic hosted-role/log matrix passes the data validator' { $summary = @(Assert-ReleaseEvidence $candidate $candidateId $evidenceRoot -RequireRegistry); if ($summary.Count -ne 2) { throw 'Evidence did not cover both model hosted architectures' } }
    foreach ($mutation in @('candidate-id','not-run','legacy-schema','deferred-pass','wrong-os-type','emulated','wrong-bundle','elevated-query','empty-log','missing-case','unrun-shell','unloaded-profile','self-hosted','wrong-workflow','wrong-run','wrong-tag','wrong-job-commit','wrong-lifecycle','failed-job','account-not-removed','invented-destruction','wrong-worker-cli','wrong-installed-cli','wrong-registry-source','wrong-cache','original-source-changed','original-archive-changed')) {
        Test-ReleaseCase ('reject evidence ' + $mutation) {
            $root = Join-Path $fixtureRoot ('evidence-' + $mutation)
            Copy-Item -LiteralPath $evidenceRoot -Destination $root -Recurse
            $data = Read-ReleaseJson (Join-Path $root 'acceptance.json')
            $hostedPath = Join-Path $root 'source/hosted-x64/result.json'
            $queryPath = Join-Path $root 'source/hosted-x64/ordinary/query-bundle/result.json'
            $portablePath = Join-Path $root 'source/hosted-x64/ordinary/query-bundle/preflight/result.json'
            $readyPath = Join-Path $root 'source/hosted-x64/ordinary/ready.json'
            $proofPath = Join-Path $root 'provenance/source-hosted-x64.json'
            $workerPath = Join-Path $root 'registry/hosted-x64/ordinary/worker-result.json'
            $installedPath = Join-Path $root 'source/hosted-x64/ordinary/query-installed/result.json'
            $hosted = Read-ReleaseJson $hostedPath; $query = Read-ReleaseJson $queryPath
            $portable = Read-ReleaseJson $portablePath; $ready = Read-ReleaseJson $readyPath
            $proof = Read-ReleaseJson $proofPath; $worker = Read-ReleaseJson $workerPath
            $installed = Read-ReleaseJson $installedPath
            switch ($mutation) {
                'candidate-id' { $data.candidateId = 'f'*64 }
                'not-run' { $data.checks[0].status = 'not-run' }
                'legacy-schema' { $data.schemaVersion = 1 }
                'deferred-pass' { $data.deferredChecks[0].status = 'pass' }
                'wrong-os-type' { $hosted.queryEnvironment.osProductType = 1 }
                'emulated' { $portable.environment.runnerProcessMachine = 34404 }
                'wrong-bundle' { $portable.manifestSha256 = 'e'*64 }
                'elevated-query' { $query.environment.elevated = $true }
                'empty-log' { [IO.File]::WriteAllText((Join-Path $root 'source/hosted-x64/ordinary/query-bundle/preflight/harness1.stdout.txt'), '') }
                'missing-case' { $query.cases = @($query.cases | Select-Object -Skip 1) }
                'unrun-shell' {
                    $path = Join-Path $root 'source/hosted-x64/ordinary/query-bundle/shells.vm_cli_shells.stdout.txt'
                    [IO.File]::WriteAllText($path, ([IO.File]::ReadAllText($path).Replace('shells=3','shells=2')))
                }
                'unloaded-profile' { $ready.userHiveLoaded = $false }
                'self-hosted' { $proof.job.runner_group_name = 'Self-hosted' }
                'wrong-workflow' { $proof.run.path = '.github/workflows/ci.yml' }
                'wrong-run' { $proof.job.run_id = 6001 }
                'wrong-tag' { $proof.run.head_branch = 'main' }
                'wrong-job-commit' { $proof.job.head_sha = 'e'*40 }
                'wrong-lifecycle' { $query.context.rollbackReference = 'github-actions:inaku-Gyan/RegQry/runs/6001/attempts/1/jobs/acceptance' }
                'failed-job' { $proof.job.conclusion = 'failure' }
                'account-not-removed' { $hosted.lifecycle.accountRemoved = $false }
                'invented-destruction' { $hosted.lifecycle.observedDestruction = $true }
                'wrong-worker-cli' { $hosted.worker.installation.cliSha256 = 'e'*64 }
                'wrong-installed-cli' { $installed.cli.sha256 = 'e'*64 }
                'wrong-registry-source' { $worker.installation.origin = 'source-archive' }
                'wrong-cache' { $worker.installation.registryArchiveSha256 = 'e'*64 }
                'original-source-changed' { [IO.File]::AppendAllText((Join-Path $root 'operator.txt'), 'changed original source record') }
                'original-archive-changed' { [IO.File]::AppendAllText((Join-Path $root 'original/source-acceptance.zip'), 'changed original ZIP') }
            }
            foreach ($pair in @(@{path=$hostedPath;value=$hosted},@{path=$queryPath;value=$query},@{path=$portablePath;value=$portable},@{path=$readyPath;value=$ready},@{path=$proofPath;value=$proof},@{path=$workerPath;value=$worker},@{path=$installedPath;value=$installed})) { Write-BundleJson $pair.value $pair.path }
            $data.files = @(Get-ReleaseInventory $root | Where-Object path -cne 'acceptance.json')
            Write-BundleJson $data (Join-Path $root 'acceptance.json')
            Assert-Rejected { Assert-ReleaseEvidence $candidate $candidateId $root -RequireRegistry } 'acceptance|candidate|native|harness|inventory|shell|profile|provenance|registry|installed|installation|deferred|Windows|token|hosted|fixture|lifecycle'
        }
    }

    foreach ($name in @('../escape.txt', 'C:/escape.txt', 'a\b', 'a/./b', '/absolute')) { Test-ReleaseCase ('reject unsafe evidence path ' + $name) { Assert-Rejected { Assert-ReleasePath $name } 'Unsafe' } }
    # Replace the HTTP boundary, keeping the real checksum/state/inventory logic.
    $global:RegQryReleaseModel.registryArchive = Join-Path $buildRoot ('x86_64-pc-windows-msvc/' + $source.file)
    $global:RegQryReleaseModel.registryHash = Get-ReleaseHash $global:RegQryReleaseModel.registryArchive
    function Get-ModelRegistryResponse {
        param([string]$Url, [string]$OutFile)
        $state = $global:RegQryReleaseModel.registryState
        $hash = $global:RegQryReleaseModel.registryHash
        if ($state -ceq 'network-failure') { throw 'Synthetic registry request failed; state is unknown' }
        if ($state -ceq 'bootstrap') { return @{ status = 404; content = $null } }
        if ($Url -match 'index.crates.io') {
            if ($state -ceq 'unpublished') { return @{ status = 200; content = '{"vers":"0.0.1","cksum":"old","yanked":false}' } }
            if ($state -ceq 'wrong-index') { $hash = 'f' * 64 }
            return @{ status = 200; content = '{"vers":"0.1.0","cksum":"' + $hash + '","yanked":' + $(if ($state -ceq 'yanked') { 'true' } else { 'false' }) + '}' }
        }
        if ($Url -match '/api/v1/crates/regqry/0.1.0$') {
            if ($state -cin @('unpublished', 'propagating')) { return @{ status = 404; content = $null } }
            if ($state -ceq 'wrong-api') { $hash = 'f' * 64 }
            return @{ status = 200; content = '{"version":{"num":"0.1.0","checksum":"' + $hash + '","yanked":false}}' }
        }
        if ($Url -match '/api/v1/crates/regqry$') { return @{ status = 200; content = '{"versions":[{"num":"0.0.1"}]}' } }
        if ($OutFile) {
            Copy-Item -LiteralPath $global:RegQryReleaseModel.registryArchive -Destination $OutFile
            if ($state -ceq 'corrupt-archive') { [IO.File]::AppendAllText($OutFile, 'corrupt') }
            return @{ status = 200; content = $null }
        }
        throw 'Unexpected synthetic registry request'
    }
    function Get-ReleaseHttp {
        param([string]$Url, [string]$OutFile)
        Get-ModelRegistryResponse $Url $OutFile
    }
    function Invoke-WebRequest {
        [CmdletBinding()]
        param([uri]$Uri, [string]$OutFile, [hashtable]$Headers, [switch]$UseBasicParsing)
        if ($Uri.AbsoluteUri -match '^https://github.com/inaku-Gyan/RegQry/releases/download/v0.1.0/(.+)$') {
            Copy-Item -LiteralPath $global:RegQryReleaseModel.remoteFiles[$Matches[1]] -Destination $OutFile
            return [pscustomobject]@{ Content = $null }
        }
        $response = Get-ModelRegistryResponse $Uri.AbsoluteUri $OutFile
        if ($response.status -ne 200) { throw 'Synthetic full-action request is not published' }
        [pscustomobject]@{ Content = $response.content }
    }
    foreach ($state in @('published', 'bootstrap', 'unpublished')) {
        Test-ReleaseCase ('registry state ' + $state) {
            $global:RegQryReleaseModel.registryState = $state
            $root = New-ReleaseDirectory (Join-Path $fixtureRoot ('registry-' + $state))
            $record = Get-ReleaseRegistry $candidate $root
            $expected = if ($state -ceq 'bootstrap') { 'bootstrap-required' } else { $state }
            if ($record.status -cne $expected) { throw 'Incorrect registry state' }
        }
    }
    foreach ($state in @('wrong-index', 'wrong-api', 'yanked', 'corrupt-archive', 'propagating', 'network-failure')) {
        Test-ReleaseCase ('reject registry ' + $state) {
            $global:RegQryReleaseModel.registryState = $state
            $root = New-ReleaseDirectory (Join-Path $fixtureRoot ('registry-' + $state))
            Assert-Rejected { Get-ReleaseRegistry $candidate $root } 'conflict|differs|unknown|propagating'
        }
    }
    $global:RegQryReleaseModel.registryState = 'published'
    $settingsScript = Join-Path $PSScriptRoot 'configure-release.ps1'
    Test-ReleaseCase 'local settings status never silently enables a disabled setting' {
        $global:RegQryReleaseModel.settingsEnabled = $false; $before = $global:RegQryReleaseModel.writes
        Assert-Rejected { & $settingsScript -ReportPath (Join-Path $fixtureRoot 'settings-disabled.json') } 'not enabled'
        if ($global:RegQryReleaseModel.writes -ne $before) { throw 'Read-only status changed repository settings' }
    }
    Test-ReleaseCase 'explicit local setup enables immutable releases then reads actual state' {
        & $settingsScript -EnableImmutable -ReportPath (Join-Path $fixtureRoot 'settings-enabled.json') | Out-Null
        $settings = Read-ReleaseJson (Join-Path $fixtureRoot 'settings-enabled.json')
        if ($settings.status -cne 'pass' -or -not $settings.settings.enabled) { throw 'Setup failed to verify enabled state' }
    }
    Test-ReleaseCase 'enabled local settings verification is read only' {
        $before = $global:RegQryReleaseModel.writes
        & $settingsScript -ReportPath (Join-Path $fixtureRoot 'settings-verified.json') | Out-Null
        if ($global:RegQryReleaseModel.writes -ne $before) { throw 'Verification wrote settings' }
    }
    Test-ReleaseCase 'CI Cargo inspection requires no administrator settings access' {
        $global:RegQryReleaseModel.settingsDenied = $true; $before = $global:RegQryReleaseModel.settingsReads
        try { & $modelScript -Action CargoStatus -Tag 'v0.1.0' -EvidenceDirectory $evidenceRoot -OutputDirectory (Join-Path $fixtureRoot 'cargo-no-admin') | Out-Null } finally { $global:RegQryReleaseModel.settingsDenied = $false }
        if ($global:RegQryReleaseModel.settingsReads -ne $before) { throw 'CI queried administrator settings' }
    }
    function rustup { throw 'Synthetic model forbids actual native installation' }
    Test-ReleaseCase 'registry input rejects a different candidate before installation' {
        Assert-Rejected { & $modelScript -Action RegistryInstall -Tag 'v0.1.0' -CandidatePath $candidatePath -ExpectedCandidateSha256 ('f' * 64) -OutputDirectory (Join-Path $fixtureRoot 'wrong-install-input') } 'accepted candidate ID'
    }
    Test-ReleaseCase 'registry worker uses pinned local candidate without GitHub draft access' {
        $global:RegQryReleaseModel.remoteFailure = $true
        try { Assert-Rejected { & $modelScript -Action RegistryInstall -Tag 'v0.1.0' -CandidatePath $candidatePath -ExpectedCandidateSha256 $candidateId -OutputDirectory (Join-Path $fixtureRoot 'local-install-input') } 'forbids actual native installation' } finally { $global:RegQryReleaseModel.remoteFailure = $false }
    }
    $global:RegQryReleaseModel.remote.assets = @($global:RegQryReleaseModel.remote.assets | Where-Object name -cne 'example.txt')
    $global:RegQryReleaseModel.remoteFiles.Remove('example.txt')
    $env:GITHUB_ACTIONS='true'; $env:GITHUB_REF='refs/tags/v0.1.0'; $env:GITHUB_REPOSITORY='inaku-Gyan/RegQry'
    $env:GITHUB_RUN_ID='6000'; $env:GITHUB_RUN_ATTEMPT='1'; $env:GITHUB_SHA=$candidate.commit
    $global:RegQryReleaseModel.actionsJobs = @()
    foreach ($stage in @('source','registry')) {
        $inputs = New-ReleaseDirectory (Join-Path $fixtureRoot ($stage + '-inputs'))
        foreach ($id in @('hosted-x64','hosted-arm64')) {
            $target = if ($id -ceq 'hosted-x64') { 'x86_64-pc-windows-msvc' } else { 'aarch64-pc-windows-msvc' }
            Copy-Item -LiteralPath (Join-Path $evidenceRoot ($stage+'/'+$id)) -Destination (Join-Path $inputs $target) -Recurse
            $proof = Read-ReleaseJson (Join-Path $evidenceRoot ('provenance/'+$stage+'-'+$id+'.json'))
            $global:RegQryReleaseModel.actionsRun = $proof.run
            $global:RegQryReleaseModel.actionsJobs += $proof.job
        }
    }
    $collector = Join-Path $PSScriptRoot 'collect-release-evidence.ps1'
    $sourceCollected = Join-Path $fixtureRoot 'col-src'
    $registryCollected = Join-Path $fixtureRoot 'col-reg'
    Test-ReleaseCase 'acceptance inputs contain only original frozen source and native archives' {
        $root = Join-Path $fixtureRoot 'inputs-ready'
        $before = $global:RegQryReleaseModel.writes
        & $modelScript -Action AcceptanceInputs -Tag 'v0.1.0' -OutputDirectory $root | Out-Null
        if ($global:RegQryReleaseModel.writes -ne $before) { throw 'Missing evidence was invented or staged' }
        foreach ($build in $candidate.builds) {
            $targetRoot = Join-Path $root ('inputs/'+$build.target)
            if ((Get-ReleaseHash (Join-Path $targetRoot $source.file)) -cne $source.sha256) { throw 'Acceptance rebuilt its source input' }
            $record = Read-ReleaseJson (Join-Path $targetRoot 'build.json')
            if ($record.source.sha256 -cne $build.source.sha256 -or $record.tests.sha256 -cne $build.tests.sha256) { throw 'Acceptance changed its frozen build input' }
        }
    }
    Test-ReleaseCase 'collector binds original source logs and completed GitHub job provenance' {
        & $collector -Stage Source -CandidatePath $candidatePath -ExpectedCandidateSha256 $candidateId -InputDirectory (Join-Path $fixtureRoot 'source-inputs') -QualityDirectory (Join-Path $evidenceRoot 'quality') -OutputDirectory $sourceCollected | Out-Null
        $collected = Read-ReleaseJson (Join-Path $sourceCollected 'result.json')
        if ($collected.status -cne 'pass' -or $collected.stage -cne 'Source') { throw 'Source collection failed' }
        $global:RegQryReleaseModel.originalArtifacts['source-acceptance-original'] = $collected.archive
    }
    $collectedSource = Read-ReleaseJson (Join-Path $sourceCollected 'result.json')
    Test-ReleaseCase 'registry collector preserves the exact original source archive and files' {
        & $collector -Stage Registry -CandidatePath $candidatePath -ExpectedCandidateSha256 $candidateId -InputDirectory (Join-Path $fixtureRoot 'registry-inputs') -SourceArchive $collectedSource.archive -ExpectedSourceSha256 $collectedSource.sha256 -OutputDirectory $registryCollected | Out-Null
        $collected = Read-ReleaseJson (Join-Path $registryCollected 'result.json')
        $accepted = Read-ReleaseAcceptanceArchive $candidate $candidateId registry $collected.archive
        if ($accepted.evidence.sourceArchiveSha256 -cne $collectedSource.sha256) { throw 'Registry collection replaced its original source acceptance' }
    }
    $collectedRegistry = Read-ReleaseJson (Join-Path $registryCollected 'result.json')
    Test-ReleaseCase 'staging interrupted after upload reconciles the same original evidence' {
        $global:RegQryReleaseModel.uploadFailure = $true
        Assert-Rejected { & $modelScript -Action StageEvidence -Tag 'v0.1.0' -EvidenceStage source -InputDirectory $sourceCollected -OutputDirectory (Join-Path $fixtureRoot 'stage-src-fail') } 'unknown'
        $asset = @($global:RegQryReleaseModel.remote.assets | Where-Object name -ceq 'regqry-v0.1.0-source-acceptance.zip')[0]
        $before = $global:RegQryReleaseModel.writes
        & $modelScript -Action AcceptanceInputs -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'stage-src-retry') | Out-Null
        $after = @($global:RegQryReleaseModel.remote.assets | Where-Object name -ceq $asset.name)[0]
        if ($global:RegQryReleaseModel.writes -ne $before -or $after.id -ne $asset.id -or $after.digest -cne $asset.digest) { throw 'Evidence retry repacked or overwrote an accepted original' }
    }
    Test-ReleaseCase 'accepted source asset missing from draft restores original Actions bytes' {
        $name='regqry-v0.1.0-source-acceptance.zip'
        $global:RegQryReleaseModel.remote.assets=@($global:RegQryReleaseModel.remote.assets|Where-Object name -cne $name)
        $global:RegQryReleaseModel.remoteFiles.Remove($name)
        & $modelScript -Action AcceptanceInputs -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'restore-src-artifact') | Out-Null
        if ((Get-ReleaseHash $global:RegQryReleaseModel.remoteFiles[$name]) -cne $collectedSource.sha256) { throw 'Source restoration changed its original ZIP' }
    }
    Test-ReleaseCase 'uploaded original artifact without draft marker is reconciled before collection' {
        $global:RegQryReleaseModel.originalArtifacts['registry-acceptance-original']=$collectedRegistry.archive
        & $modelScript -Action AcceptanceInputs -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'restore-unmarked') | Out-Null
        if ((Get-ReleaseHash $global:RegQryReleaseModel.remoteFiles['regqry-v0.1.0-registry-acceptance.zip']) -cne $collectedRegistry.sha256) { throw 'Unmarked artifact was repacked' }
    }
    Test-ReleaseCase 'accepted evidence cannot be replaced by differently compressed or appended bytes' {
        $root = New-ReleaseDirectory (Join-Path $fixtureRoot 'changed-evidence')
        $archive = Join-Path $root 'regqry-v0.1.0-source-acceptance.zip'
        Copy-Item -LiteralPath $collectedSource.archive -Destination $archive
        [IO.File]::AppendAllText($archive, 'changed-archive-bytes')
        $before = $global:RegQryReleaseModel.writes
        Assert-Rejected { & $modelScript -Action StageEvidence -Tag 'v0.1.0' -EvidenceStage source -InputDirectory $root -OutputDirectory (Join-Path $fixtureRoot 'reject-repacked') } 'original evidence bytes differ'
        if ($global:RegQryReleaseModel.writes -ne $before) { throw 'Conflicting evidence caused a remote write' }
    }
    Test-ReleaseCase 'source original restores from durable registry archive after artifacts expire' {
        $name='regqry-v0.1.0-source-acceptance.zip'
        $global:RegQryReleaseModel.remote.assets=@($global:RegQryReleaseModel.remote.assets|Where-Object name -cne $name)
        $global:RegQryReleaseModel.remoteFiles.Remove($name)
        $global:RegQryReleaseModel.originalArtifacts.Remove('source-acceptance-original')
        & $modelScript -Action AcceptanceInputs -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'restore-durable-src') | Out-Null
        if ((Get-ReleaseHash $global:RegQryReleaseModel.remoteFiles[$name]) -cne $collectedSource.sha256) { throw 'Durable source original was replaced' }
    }
    Test-ReleaseCase 'lost accepted original cannot trigger fresh evidence collection' {
        $name='regqry-v0.1.0-registry-acceptance.zip'
        $asset=@($global:RegQryReleaseModel.remote.assets|Where-Object name -ceq $name)[0]
        $file=$global:RegQryReleaseModel.remoteFiles[$name]
        $global:RegQryReleaseModel.remote.assets=@($global:RegQryReleaseModel.remote.assets|Where-Object name -cne $name)
        $global:RegQryReleaseModel.remoteFiles.Remove($name)
        $global:RegQryReleaseModel.originalArtifacts.Remove('registry-acceptance-original')
        $before=$global:RegQryReleaseModel.writes
        try { Assert-Rejected { & $modelScript -Action AcceptanceInputs -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'lost-reg-original') } 'original artifact is unavailable' }
        finally {
            $global:RegQryReleaseModel.remote.assets += $asset
            $global:RegQryReleaseModel.remoteFiles[$name]=$file
        }
        if ($global:RegQryReleaseModel.writes -ne $before) { throw 'Lost originals caused replacement evidence' }
    }
    Test-ReleaseCase 'finalization interrupted after validation upload resumes original ZIP' {
        $global:RegQryReleaseModel.uploadFailure = $true
        Assert-Rejected { & $modelScript -Action Finalize -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'finalize-interrupted') } 'unknown'
        $validation = @($global:RegQryReleaseModel.remote.assets | Where-Object name -ceq 'regqry-v0.1.0-validation.zip')[0]
        $hash = $validation.digest; $id = $validation.id
        & $modelScript -Action Finalize -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'finalize-resume') | Out-Null
        $after = @($global:RegQryReleaseModel.remote.assets | Where-Object name -ceq 'regqry-v0.1.0-validation.zip')[0]
        if ($after.digest -cne $hash -or $after.id -ne $id) { throw 'Recovery rebuilt or replaced the original validation ZIP' }
    }
    Test-ReleaseCase 'complete finalization retry skips every existing asset' {
        $before = $global:RegQryReleaseModel.writes
        & $modelScript -Action Finalize -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'finalize-complete-retry') | Out-Null
        if ($global:RegQryReleaseModel.writes -ne $before) { throw 'Retry rewrote final assets' }
        if (@($global:RegQryReleaseModel.remote.assets).Count -ne 11) { throw 'The final set must include both original acceptance archives' }
    }
    Test-ReleaseCase 'registry original restores from final validation after Actions artifacts expire' {
        $name='regqry-v0.1.0-registry-acceptance.zip'
        $global:RegQryReleaseModel.remote.assets=@($global:RegQryReleaseModel.remote.assets|Where-Object name -cne $name)
        $global:RegQryReleaseModel.remoteFiles.Remove($name)
        & $modelScript -Action AcceptanceInputs -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'restore-durable-reg') | Out-Null
        if ((Get-ReleaseHash $global:RegQryReleaseModel.remoteFiles[$name]) -cne $collectedRegistry.sha256) { throw 'Registry restoration changed its accepted original' }
    }
    Test-ReleaseCase 'unexpected mutable publication is reported without automatic rollback' {
        $global:RegQryReleaseModel.settingsEnabled = $false
        Assert-Rejected { & $modelScript -Action Publish -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'publish-settings-disabled') } 'not immutable'
        if ($global:RegQryReleaseModel.remote.draft) { throw 'Partial public state was misreported as a draft' }
        # Reset only the synthetic server for the next independent scenario.
        $global:RegQryReleaseModel.remote.draft = $true
    }
    Test-ReleaseCase 'remote publication succeeded but command failed: next run only verifies' {
        $global:RegQryReleaseModel.settingsEnabled = $true; $global:RegQryReleaseModel.publishFailure = $true
        $global:RegQryReleaseModel.settingsDenied = $true; $settingsReads = $global:RegQryReleaseModel.settingsReads
        Assert-Rejected { & $modelScript -Action Publish -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'publish-interrupted') } 'unknown'
        if ($global:RegQryReleaseModel.remote.draft -or -not $global:RegQryReleaseModel.remote.immutable) { throw 'Synthetic public state was not reached' }
        $before = $global:RegQryReleaseModel.writes
        & $modelScript -Action Publish -Tag 'v0.1.0' -OutputDirectory (Join-Path $fixtureRoot 'publish-reconciled') | Out-Null
        if ($global:RegQryReleaseModel.writes -ne $before) { throw 'Recovery repeated publication' }
        if ($global:RegQryReleaseModel.settingsReads -ne $settingsReads) { throw 'CI promotion required administrator settings access' }
    }
    Test-ReleaseCase 'complete source inventory rejects an added file' {
        [IO.File]::WriteAllText((Join-Path $sourceRoot 'extra.txt'), 'extra')
        Assert-Rejected { Assert-ReleaseInventory $sourceRoot $sourceFiles } 'incomplete'
    }
    if ((Get-Location).Path -cne $originalLocation) { throw 'Release tools changed the caller working directory' }
    $result.status = 'pass'
    Write-Output ('Release model gates passed: ' + $result.cases.Count)
} catch { $result.error = $_.Exception.Message; throw }
finally {
    Restore-BundleEnvironment $saved
    if ($previousModel) { $global:RegQryReleaseModel = $previousModel.Value } else { Remove-Variable RegQryReleaseModel -Scope Global }
    Write-BundleJson $result (Join-Path $reportRoot 'result.json')
}

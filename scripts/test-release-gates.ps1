[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReportDirectory)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release/support.ps1')
. (Join-Path $PSScriptRoot 'release/evidence.ps1')
$reportRoot = New-ReleaseDirectory $ReportDirectory
$fixtureRoot = New-ReleaseDirectory (Join-Path ([IO.Path]::GetTempPath()) ('regqry-release-model-' + [guid]::NewGuid().ToString('N')))
$result = [ordered]@{ schemaVersion = 1; status = 'fail'; scope = 'synthetic release-state/evidence model with mocked remote commands; no real publication, credentials, registry fixture, native ARM execution or formal acceptance'; fixtureRoot = $fixtureRoot; cases = @(); error = $null }
$saved = @{}
foreach ($name in @('GITHUB_ACTIONS', 'GITHUB_REF', 'GITHUB_REPOSITORY', 'GITHUB_EVENT_NAME', 'GITHUB_OUTPUT', 'GITHUB_STEP_SUMMARY')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process'); Remove-Item -LiteralPath ('Env:\' + $name) -ErrorAction SilentlyContinue }
$originalLocation = (Get-Location).Path
$previousModel = Get-Variable -Name RegQryReleaseModel -Scope Global -ErrorAction SilentlyContinue
$global:RegQryReleaseModel = @{ projectRoot = (Split-Path -Parent $PSScriptRoot) }
$global:RegQryReleaseModel.fakeCommit = 'a' * 40
$global:RegQryReleaseModel.remote = $null; $global:RegQryReleaseModel.remoteFiles = @{}; $global:RegQryReleaseModel.nextId = 1; $global:RegQryReleaseModel.writes = 0
$global:RegQryReleaseModel.remoteFailure = $false; $global:RegQryReleaseModel.downloadCorruption = $false; $global:RegQryReleaseModel.uploadFailure = $false
$global:RegQryReleaseModel.checkoutFailure = ''; $global:RegQryReleaseModel.packageVersion = '0.1.0'
$global:RegQryReleaseModel.httpRequests = 0; $global:RegQryReleaseModel.settingsReads = 0

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
        if ($endpoint -ceq 'repos/inaku-Gyan/RegQry') { '{"id":1462950131,"full_name":"inaku-Gyan/RegQry","default_branch":"main","permissions":{"admin":true,"push":' + $(if ($global:RegQryReleaseModel.noPushVisibility) { 'false' } else { 'true' }) + '}}'; return }
        if ($endpoint -match '/commits/') { $global:RegQryReleaseModel.fakeCommit; return }
        if ($endpoint -match '/releases\?') { if ($global:RegQryReleaseModel.remote) { '[[' + ($global:RegQryReleaseModel.remote | ConvertTo-Json -Depth 40 -Compress) + ']]' } else { '[[]]' }; return }
        if ($endpoint -match '/assets\?') { '[' + (ConvertTo-Json -InputObject @($global:RegQryReleaseModel.remote.assets) -Depth 40 -Compress) + ']'; return }
        if ($endpoint -match '/immutable-releases$') {
            if ($arguments -contains 'PUT') { $global:RegQryReleaseModel.writes++; $global:RegQryReleaseModel.settingsEnabled = $true; return }
            $global:RegQryReleaseModel.settingsReads++
            if ($global:RegQryReleaseModel.settingsDenied) { $global:LASTEXITCODE = 1; return }
            '{"enabled":' + $(if ($global:RegQryReleaseModel.settingsEnabled) { 'true' } else { 'false' }) + '}'
            return
        }
        throw ('Unexpected mocked API endpoint: ' + $endpoint)
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
            if ($arguments -notcontains '--draft=false') { throw 'Unexpected synthetic release edit' }
            $global:RegQryReleaseModel.writes++
            $global:RegQryReleaseModel.remote.draft = $false
            $global:RegQryReleaseModel.remote.immutable = $global:RegQryReleaseModel.settingsEnabled
            if ($global:RegQryReleaseModel.publishFailure) { $global:LASTEXITCODE = 1; $global:RegQryReleaseModel.publishFailure = $false }
        }
        default { throw 'Synthetic model forbids unexpected release writes' }
    }
}

function New-ModelEvidence {
    param([object]$Candidate, [string]$CandidateId, [string]$Root)
    New-Item -ItemType Directory -Path $Root | Out-Null
    [IO.File]::WriteAllText((Join-Path $Root 'operator.txt'), 'SYNTHETIC MODEL. No VM, terminal, cleanup or installation actually ran.')
    $evidence = [ordered]@{ schemaVersion = 1; kind = 'regqry-release-acceptance'; status = 'pass'; candidateId = $CandidateId; tag = $Candidate.tag; commit = $Candidate.commit; assets = @($Candidate.assets | ForEach-Object { @{ name = $_.name; sha256 = $_.sha256 } }); checks = @(); platforms = @(); files = @() }
    for ($index = 1; $index -le 14; $index++) { $evidence.checks += @{ id = 'A{0:00}' -f $index; status = 'pass'; observation = 'synthetic'; records = @('operator.txt') } }
    foreach ($id in @('win10-x64', 'win11-x64', 'win11-arm64')) {
        $target = if ($id -ceq 'win11-arm64') { 'aarch64-pc-windows-msvc' } else { 'x86_64-pc-windows-msvc' }
        $build = @($Candidate.builds | Where-Object target -ceq $target)[0]
        $os = if ($id -ceq 'win10-x64') { '10.0.19045' } else { '10.0.26100' }
        $environment = @{ osVersion = $os; nativeTarget = $target; runnerProcessMachine = 0; osProductType = 1; elevated = $false; cargoOnPath = $false; rustcOnPath = $false; userSid = 'S-1-5-21-1-2-3-1001' }
        $rootPath = Join-Path $Root $id; New-Item -ItemType Directory -Path $rootPath | Out-Null
        $portable = @{ status = 'pass'; manifestSha256 = $build.tests.manifestSha256; source = $build.source; environment = $environment; tests = @(); passedTests = 47 }
        for ($index = 0; $index -lt 4; $index++) {
            $runnable = @(0, 6, 7, 34)[$index]; $ignored = @(0, 0, 8, 0)[$index]
            $portable.tests += @{ path = "tests/harness$index.exe"; status = 'pass'; exitCode = 0; timedOut = $false; elapsedMs = 1; runnable = $runnable; ignored = $ignored; stdout = "harness$index.stdout.txt"; stderr = "harness$index.stderr.txt" }
            [IO.File]::WriteAllText((Join-Path $rootPath "harness$index.stdout.txt"), "SYNTHETIC`ntest result: ok. $runnable passed; 0 failed; $ignored ignored;`n")
            [IO.File]::WriteAllText((Join-Path $rootPath "harness$index.stderr.txt"), '')
        }
        Write-BundleJson $portable (Join-Path $rootPath 'portable.json')
        Write-BundleJson @{ kind = 'regqry-clean-system-record'; status = 'pass'; snapshotId = 'synthetic'; target = $target; osVersion = $os; developmentToolsInstalled = $false; extraRuntimeInstalled = $false; candidateId = $CandidateId; inventoryRecords = @('operator.txt') } (Join-Path $rootPath 'clean.json')
        $context = @{ id = '1' * 32; nonce = '2' * 64; querySid = $environment.userSid; rollbackReference = 'synthetic-snapshot' }
        foreach ($phase in @('Prepare', 'Query')) {
            $phaseEnvironment = $environment | ConvertTo-Json | ConvertFrom-Json; $phaseEnvironment.elevated = $phase -ceq 'Prepare'
            $vm = @{ status = 'pass'; phase = $phase; environment = $phaseEnvironment; context = $context; contextSha256 = '3' * 64; manifestSha256 = $build.tests.manifestSha256; cases = @(); finishedAtUtc = '2026-11-19T00:30:00Z' }
            $cases = if ($phase -ceq 'Prepare') { @('vm_prepare') } else { @('vm_roots_and_physical_views', 'vm_minimum_permissions_and_partial_failure', 'vm_link_sources_explicit_aliases_cycles_and_lookalikes', 'processes::vm_cli_processes', 'shells::vm_cli_shells', 'performance::vm_scaling_baseline') }
            foreach ($name in $cases) {
                $log = $name.Replace('::', '.')
                $vm.cases += @{ name = $name; status = 'pass'; exitCode = 0; timedOut = $false; elapsedMs = 1; stdout = "$log.stdout.txt"; stderr = "$log.stderr.txt" }
                $text = "SYNTHETIC`nVM_OPERATION_START phase=$($phase.ToLowerInvariant()) id=$($context.id)`n"
                if ($name -ceq 'shells::vm_cli_shells') { $text += "SHELL_CHECKS manual_terminal=not-run cmd powershell pwsh`nSHELL_SUMMARY shells=3 cases_per_shell=8 status=pass scope=owned-vm-query`n" }
                [IO.File]::WriteAllText((Join-Path $rootPath "$log.stdout.txt"), $text + "test result: ok. 1 passed; 0 failed; 0 ignored;`n")
                [IO.File]::WriteAllText((Join-Path $rootPath "$log.stderr.txt"), '')
            }
            Write-BundleJson $vm (Join-Path $rootPath ($phase + '.json'))
        }
        Write-BundleJson @{ kind = 'regqry-vm-rollback-record'; status = 'pass'; contextId = $context.id; reference = $context.rollbackReference; action = 'destroy'; records = @('operator.txt'); completedAtUtc = '2026-11-19T01:00:00Z' } (Join-Path $rootPath 'rollback.json')
        foreach ($channel in @('candidate-archive', 'crates.io')) {
            Write-BundleJson @{ kind = 'regqry-formal-source-install'; status = 'pass'; source = $channel; candidateId = $CandidateId; sourceSha256 = $build.source.sha256; target = $target; osVersion = $os; compiler = @('release: 1.100.0', ('host: ' + $target)); cliSha256 = '4' * 64; elevated = $false; privateFixtureExitCode = 0; records = @('operator.txt') } (Join-Path $rootPath ($channel + '.json'))
        }
        $terminals = if ($id -ceq 'win10-x64') { @('classic') } elseif ($id -ceq 'win11-x64') { @('windows-terminal') } else { @('classic', 'windows-terminal') }
        $visual = @(foreach ($terminal in $terminals) { foreach ($columns in @(80, 120)) { @{ terminal = $terminal; columns = $columns; visible = $true; status = 'pass'; physicalCtrlCExitCode = 130; version = 'synthetic'; measurement = 'synthetic'; records = @('operator.txt') } } })
        $evidence.platforms += @{ id = $id; status = 'pass'; channel = 'general-availability'; edition = 'Synthetic'; displayVersion = $(if ($id -ceq 'win10-x64') { '22H2' } else { '24H2' }); portable = "$id/portable.json"; cleanSystem = "$id/clean.json"; vmPrepare = "$id/Prepare.json"; vmQuery = "$id/Query.json"; rollback = "$id/rollback.json"; sourceInstall = "$id/candidate-archive.json"; registryInstall = "$id/crates.io.json"; terminals = $visual }
    }
    $evidence.files = @(Get-ReleaseInventory $Root)
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
    $evidenceRoot = Join-Path $fixtureRoot 'complete-model-evidence'
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
    Test-ReleaseCase 'complete synthetic environment/log matrix passes the data validator' { $summary = @(Assert-ReleaseEvidence $candidate $candidateId $evidenceRoot -RequireRegistry); if ($summary.Count -ne 3) { throw 'Evidence did not cover three model systems' } }
    foreach ($mutation in @('candidate-id', 'not-run', 'server', 'emulated', 'minimum-build', 'wrong-bundle', 'elevated-query', 'empty-log', 'missing-case', 'unrun-shell', 'no-clean-inventory', 'no-rollback', 'wrong-registry-source', 'wrong-width', 'invisible-terminal', 'failed-cancel')) {
        Test-ReleaseCase ('reject evidence ' + $mutation) {
            $root = Join-Path $fixtureRoot ('evidence-' + $mutation)
            Copy-Item -LiteralPath $evidenceRoot -Destination $root -Recurse
            $data = Read-ReleaseJson (Join-Path $root 'acceptance.json')
            $portablePath = Join-Path $root 'win10-x64/portable.json'; $portable = Read-ReleaseJson $portablePath
            switch ($mutation) {
                'candidate-id' { $data.candidateId = 'f' * 64 }
                'not-run' { $data.checks[0].status = 'not-run' }
                'server' { $portable.environment.osProductType = 3 }
                'emulated' { $portable.environment.runnerProcessMachine = 34404 }
                'minimum-build' { $portable.environment.osVersion = '10.0.19044' }
                'wrong-bundle' { $portable.manifestSha256 = 'e' * 64 }
                'elevated-query' { $portable.environment.elevated = $true }
                'empty-log' { [IO.File]::WriteAllText((Join-Path $root 'win10-x64/harness1.stdout.txt'), '') }
                'missing-case' { $path = Join-Path $root 'win10-x64/Query.json'; $vm = Read-ReleaseJson $path; $vm.cases = @($vm.cases | Select-Object -Skip 1); Write-BundleJson $vm $path }
                'unrun-shell' { $path = Join-Path $root 'win10-x64/shells.vm_cli_shells.stdout.txt'; [IO.File]::WriteAllText($path, ([IO.File]::ReadAllText($path).Replace('shells=3', 'shells=2'))) }
                'no-clean-inventory' { $path = Join-Path $root 'win10-x64/clean.json'; $record = Read-ReleaseJson $path; $record.inventoryRecords = @(); Write-BundleJson $record $path }
                'no-rollback' { $path = Join-Path $root 'win10-x64/rollback.json'; $record = Read-ReleaseJson $path; $record.status = 'not-run'; Write-BundleJson $record $path }
                'wrong-registry-source' { $path = Join-Path $root 'win10-x64/crates.io.json'; $record = Read-ReleaseJson $path; $record.source = 'candidate-archive'; Write-BundleJson $record $path }
                'wrong-width' { $data.platforms[0].terminals[0].columns = 79 }
                'invisible-terminal' { $data.platforms[0].terminals[0].visible = $false }
                'failed-cancel' { $data.platforms[0].terminals[0].physicalCtrlCExitCode = 0 }
            }
            Write-BundleJson $portable $portablePath
            $data.files = @(Get-ReleaseInventory $root | Where-Object path -cne 'acceptance.json')
            Write-BundleJson $data (Join-Path $root 'acceptance.json')
            Assert-Rejected { Assert-ReleaseEvidence $candidate $candidateId $root -RequireRegistry } 'acceptance|candidate|client|native|harness|inventory|shell|clean|rollback|registry|terminal|width'
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
    $installRoot = New-ReleaseDirectory (Join-Path $fixtureRoot 'registry-installs')
    foreach ($target in @('x86_64-pc-windows-msvc', 'aarch64-pc-windows-msvc')) {
        $root = New-ReleaseDirectory (Join-Path $installRoot $target)
        Write-BundleJson @{ status = 'pass'; action = 'RegistryInstall'; state = 'installed-from-registry'; candidateId = $candidateId; environment = @{ nativeTarget = $target }; sourceSha256 = $source.sha256 } (Join-Path $root 'result.json')
        foreach ($name in @('install.stdout.txt', 'install.stderr.txt', 'version.stdout.txt', 'version.stderr.txt', 'help.stdout.txt', 'help.stderr.txt')) { [IO.File]::WriteAllText((Join-Path $root $name), 'SYNTHETIC') }
        Write-BundleJson @{ status = 'published'; candidateSha256 = $source.sha256 } (Join-Path $root 'registry.json')
    }
    Test-ReleaseCase 'finalization interrupted after validation upload resumes original ZIP' {
        $global:RegQryReleaseModel.uploadFailure = $true
        Assert-Rejected { & $modelScript -Action Finalize -Tag 'v0.1.0' -InputDirectory $installRoot -EvidenceDirectory $evidenceRoot -OutputDirectory (Join-Path $fixtureRoot 'finalize-interrupted') } 'unknown'
        $validation = @($global:RegQryReleaseModel.remote.assets | Where-Object name -ceq 'regqry-v0.1.0-validation.zip')[0]
        $hash = $validation.digest; $id = $validation.id
        & $modelScript -Action Finalize -Tag 'v0.1.0' -InputDirectory $installRoot -OutputDirectory (Join-Path $fixtureRoot 'finalize-resume') | Out-Null
        $after = @($global:RegQryReleaseModel.remote.assets | Where-Object name -ceq 'regqry-v0.1.0-validation.zip')[0]
        if ($after.digest -cne $hash -or $after.id -ne $id) { throw 'Recovery rebuilt or replaced the original validation ZIP' }
    }
    Test-ReleaseCase 'complete finalization retry skips every existing asset' {
        $before = $global:RegQryReleaseModel.writes
        & $modelScript -Action Finalize -Tag 'v0.1.0' -InputDirectory $installRoot -OutputDirectory (Join-Path $fixtureRoot 'finalize-complete-retry') | Out-Null
        if ($global:RegQryReleaseModel.writes -ne $before) { throw 'Retry rewrote final assets' }
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

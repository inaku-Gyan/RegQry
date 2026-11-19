[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Inspect', 'Source', 'Freeze', 'Restore', 'AcceptanceInputs', 'StageEvidence', 'Evidence', 'CargoStatus', 'CargoPreflight', 'CargoPublish', 'RegistryInstall', 'Finalize', 'Publish')][string]$Action,
    [Parameter(Mandatory)][string]$Tag,
    [string]$Repository = 'inaku-Gyan/RegQry',
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$InputDirectory,
    [string]$EvidenceDirectory,
    [ValidateSet('source', 'registry')][string]$EvidenceStage = 'source',
    [string]$CandidatePath,
    [string]$ExpectedCandidateSha256,
    [switch]$LocalBootstrap
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release/support.ps1')
. (Join-Path $PSScriptRoot 'release/evidence.ps1')
. (Join-Path $PSScriptRoot 'release/acceptance.ps1')
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($Repository -cne 'inaku-Gyan/RegQry') { throw 'Release operations are restricted to the canonical repository' }
$outputRoot = New-ReleaseDirectory $OutputDirectory
$script:ReleaseTag = $Tag
$record = [ordered]@{ schemaVersion = 1; action = $Action; status = 'fail'; tag = $Tag; startedAtUtc = [DateTime]::UtcNow.ToString('o'); candidateId = $null; state = $null; error = $null }
function Set-ReleaseOutput {
    param([string]$Name, [string]$Value)
    if ($Value.Contains("`n") -or $Value.Contains("`r")) { throw 'Invalid workflow output' }
    if ($env:GITHUB_OUTPUT) { [IO.File]::AppendAllText($env:GITHUB_OUTPUT, $Name + '=' + $Value + "`n", [Text.UTF8Encoding]::new($false)) }
}
function Get-FrozenCandidate {
    param([switch]$AllowMissingAssets)
    $release = Get-ReleaseRemote $Repository $Tag
    $manifest = @($release.assets | Where-Object name -ceq 'candidate-manifest.json')
    if ($manifest.Count -ne 1) { throw 'A complete frozen candidate is required; recovery never builds a replacement' }
    $path = Get-ReleaseAsset $Repository $manifest[0] $outputRoot
    $candidate = Read-ReleaseJson $path
    Assert-ReleaseCandidate $candidate $Tag $checkout.commit
    if (-not $AllowMissingAssets) { Assert-ReleaseRemoteCandidate $candidate $release }
    $record.candidateId = Get-ReleaseHash $path
    Set-ReleaseOutput candidate_id $record.candidateId
    [ordered]@{ candidate = $candidate; release = $release; path = $path }
}
function Read-AcceptanceInput {
    param([switch]$RequireRegistry)
    if ($EvidenceDirectory) { return (Get-Item -LiteralPath $EvidenceDirectory).FullName }
    $stage = if ($RequireRegistry) { 'registry' } else { 'source' }
    $accepted = Resolve-ReleaseStagedEvidence $Repository $frozen.release $candidate $record.candidateId $stage (Join-Path $outputRoot 'accepted-evidence')
    if (-not $accepted) { throw ('Original ' + $stage + ' acceptance is missing; keep the frozen draft and complete its hosted acceptance jobs') }
    $accepted.root
}
try {
    $checkout = Get-ReleaseCheckout $projectRoot $Tag
    $localInstallInput = $Action -ceq 'RegistryInstall' -and $CandidatePath
    if (-not $localInstallInput) {
        $repo = (Invoke-ReleaseGh @('api', "repos/$Repository")) -join "`n" | ConvertFrom-Json
        if ($repo.id -ne 1462950131 -or $repo.full_name -cne $Repository -or $repo.default_branch -cne 'main') { throw 'Remote repository identity changed' }
        if ($Action -ceq 'Inspect') { Assert-ReleaseDraftVisibility $Repository $Tag }
        $remoteCommit = (Invoke-ReleaseGh @('api', "repos/$Repository/commits/$Tag", '--jq', '.sha')) -join ''
        if ($remoteCommit -cne $checkout.commit) { throw 'The actual remote tag moved or differs from the checkout' }
        $remote = Get-ReleaseRemote $Repository $Tag
    }
    if ($Action -ceq 'Inspect') {
        if ($remote -and @($remote.assets | Where-Object name -ceq 'candidate-manifest.json').Count -eq 1) {
            $frozen = Get-FrozenCandidate
            foreach ($asset in $frozen.candidate.assets) {
                $item = @($frozen.release.assets | Where-Object name -ceq $asset.name)[0]
                Get-ReleaseAsset $Repository $item $outputRoot | Out-Null
            }
            $record.state = if ($remote.draft) { 'frozen' } else { 'published' }
            if (-not $remote.draft -and -not $remote.immutable) { throw 'The public release is not immutable' }
        } else {
            if ($env:GITHUB_EVENT_NAME -ceq 'workflow_dispatch') { throw 'Manual recovery requires an already frozen candidate at this exact tag ref' }
            if ($remote) { throw 'A partial draft already exists; rerun its original failed staging job using the original build artifacts, never rebuild it' }
            $record.state = 'fresh'
        }
        Set-ReleaseOutput state $record.state
        Set-ReleaseOutput version $checkout.version
        Set-ReleaseOutput commit $checkout.commit
    } elseif ($Action -ceq 'Source') {
        if ($remote) { throw 'Source construction is prohibited after staging began' }
        & (Join-Path $PSScriptRoot 'check-package.ps1')
        $archive = Join-Path $checkout.targetDirectory ('package/regqry-' + $checkout.version + '.crate')
        Copy-Item -LiteralPath $archive -Destination $outputRoot
        $record.sourceSha256 = Get-ReleaseHash $archive
    } elseif ($Action -ceq 'Freeze') {
        if (-not $InputDirectory) { throw 'Freeze requires the original dual-native build outputs' }
        if ($remote -and @($remote.assets | Where-Object name -ceq 'candidate-manifest.json').Count -gt 0) {
            Get-FrozenCandidate | Out-Null
            $record.state = 'already-frozen'
        } else {
            if ($env:GITHUB_EVENT_NAME -ceq 'workflow_dispatch') { throw 'Manual recovery cannot create a new candidate' }
            $builds = @()
            $localAssets = @()
            foreach ($target in @('x86_64-pc-windows-msvc', 'aarch64-pc-windows-msvc')) {
                $root = Join-Path $InputDirectory $target
                $build = Read-ReleaseJson (Join-Path $root 'build.json')
                $check = Read-ReleaseJson (Join-Path $root 'check/result.json')
                if ($check.status -cne 'pass' -or $check.userArchiveSha256 -cne $build.user.sha256 -or $check.testArchiveSha256 -cne $build.tests.sha256) { throw 'Native archive checks are missing or use different bytes' }
                $build | Add-Member -NotePropertyName assetCheck -NotePropertyValue $check
                foreach ($kind in @('user', 'tests')) {
                    $name = if ($kind -ceq 'user') { 'regqry-' + $Tag + '-' + $target } else { 'regqry-' + $Tag + '-tests-' + $target }
                    $relative = if ($kind -ceq 'user') { $name + '.zip' } else { 'tests/' + $name + '.zip' }
                    $manifest = Read-BundleZipManifest (Join-Path $root $relative) ($name + '/bundle-manifest.json') $build.$kind.manifestSha256
                    if ($manifest.target -cne $target -or $manifest.version -cne $checkout.version -or $manifest.source.sha256 -cne $build.source.sha256 -or $manifest.source.git.sha1 -cne $checkout.commit) { throw 'Actual ZIP manifest differs from the native build identity' }
                    $cli = @($manifest.files | Where-Object path -ceq 'regqry.exe')
                    if ($cli.Count -ne 1 -or $cli[0].sha256 -cne $build.user.cliSha256) { throw 'User/test ZIPs do not carry the same production executable' }
                    if ($kind -ceq 'tests') { $build | Add-Member -NotePropertyName testInventory -NotePropertyValue @($manifest.tests) }
                }
                $builds += $build
                $localAssets += Join-Path $root ('regqry-' + $Tag + '-' + $target + '.zip')
                $localAssets += Join-Path $root ('tests/regqry-' + $Tag + '-tests-' + $target + '.zip')
            }
            $sourceName = 'regqry-' + $checkout.version + '.crate'
            $sourcePath = Join-Path (Join-Path $InputDirectory 'x86_64-pc-windows-msvc') $sourceName
            if ((Get-ReleaseHash $sourcePath) -cne (Get-ReleaseHash (Join-Path (Join-Path $InputDirectory 'aarch64-pc-windows-msvc') $sourceName))) { throw 'Native builds used different source archives' }
            $sourceExtract = Join-Path $outputRoot 'source-inventory'
            Get-ReleaseSourceInventory $sourcePath $checkout.version $sourceExtract | Out-Null
            foreach ($build in $builds) { Assert-ReleaseInventory (Join-Path $sourceExtract ('regqry-' + $checkout.version)) @($build.sourceFiles) }
            $localAssets += $sourcePath
            # Validate everything possible before the first remote mutation.
            $planned = @(); $index = 1
            foreach ($path in $localAssets) { $planned += [ordered]@{ name = Split-Path -Leaf $path; id = $index++; size = (Get-Item -LiteralPath $path).Length; sha256 = Get-ReleaseHash $path } }
            $candidate = [ordered]@{ schemaVersion = 1; kind = 'regqry-release-candidate'; repository = $Repository; repositoryId = 1462950131; releaseId = 0; tag = $Tag; version = $checkout.version; commit = $checkout.commit; lockSha256 = $checkout.lockSha256; createdAtUtc = [DateTime]::UtcNow.ToString('o'); runId = $env:GITHUB_RUN_ID; runAttempt = $env:GITHUB_RUN_ATTEMPT; builds = $builds; assets = $planned }
            Assert-ReleaseCandidate ([pscustomobject]$candidate) $Tag $checkout.commit
            if ($remote) {
                foreach ($asset in $remote.assets) {
                    $plannedAsset = @($planned | Where-Object { $_.name -ceq $asset.name })
                    if ($plannedAsset.Count -ne 1 -or $plannedAsset[0].size -ne $asset.size -or $asset.digest -cne ('sha256:' + $plannedAsset[0].sha256)) { throw 'Partial draft conflicts with the preserved build inputs; no uploads are allowed' }
                }
            }
            $notesPath = Join-Path $outputRoot 'notes.md'
            $notes = $checkout.notes + "`n`nUnsigned Windows MSVC binaries. See the candidate and validation manifests for archive identities and actual acceptance records.`n"
            foreach ($target in @('x86_64-pc-windows-msvc', 'aarch64-pc-windows-msvc')) { $notes += "`n- [$target](https://github.com/$Repository/releases/download/$Tag/regqry-$Tag-$target.zip)" }
            [IO.File]::WriteAllText($notesPath, $notes + "`n", [Text.UTF8Encoding]::new($false))
            if (-not $remote) {
                Invoke-ReleaseGh @('release', 'create', $Tag, '--repo', $Repository, '--verify-tag', '--draft', '--title', ('RegQry ' + $checkout.version), '--notes-file', $notesPath) | Out-Null
                $remote = Wait-ReleaseCreatedDraft $Repository $Tag
            } else { $remote = Get-ReleaseRemote $Repository $Tag }
            if (-not $remote.draft) { throw 'Only the original draft can be frozen' }
            $candidate.releaseId = $remote.id
            $candidate.assets = @(foreach ($path in $localAssets) { Sync-ReleaseAsset $Repository $Tag $path })
            # Embed original build/check log bytes so candidate recovery does not
            # depend on expiring Actions artifacts or build-machine paths.
            $candidate.records = @(foreach ($target in @('x86_64-pc-windows-msvc', 'aarch64-pc-windows-msvc')) {
                $root = (Get-Item -LiteralPath (Join-Path $InputDirectory $target)).FullName
                foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @('.json', '.jsonl', '.txt') -and $_.FullName.Substring($root.Length + 1).Replace('\', '/') -match '^(check/|user-license-report/|tests/(build\.json|cargo-[^/]+\.jsonl|test-license-report/))' } | Sort-Object FullName) {
                    [ordered]@{ path = $target + '/' + $file.FullName.Substring($root.Length + 1).Replace('\', '/'); sha256 = Get-ReleaseHash $file.FullName; bytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName)) }
                }
            })
            $manifestPath = Join-Path $outputRoot 'candidate-manifest.json'
            Write-BundleJson $candidate $manifestPath
            Sync-ReleaseAsset $Repository $Tag $manifestPath | Out-Null
            $record.candidateId = Get-ReleaseHash $manifestPath
            $record.state = 'frozen'
        }
    } else {
        if ($localInstallInput) {
            if ($ExpectedCandidateSha256 -cnotmatch '^[a-f0-9]{64}$' -or (Get-ReleaseHash $CandidatePath) -cne $ExpectedCandidateSha256) { throw 'Registry install input differs from the accepted candidate ID' }
            $candidateInput = Read-ReleaseJson $CandidatePath
            Assert-ReleaseCandidate $candidateInput $Tag $checkout.commit
            $record.candidateId = $ExpectedCandidateSha256
            $frozen = [ordered]@{ candidate = $candidateInput; path = $CandidatePath; release = $null }
        } else { $frozen = Get-FrozenCandidate -AllowMissingAssets:($Action -ceq 'Restore') }
        $candidate = $frozen.candidate
        if ($Action -ceq 'Restore') {
            if (-not $InputDirectory -or -not $frozen.release.draft) { throw 'Restore requires preserved original core files and an existing draft' }
            foreach ($asset in $candidate.assets) {
                $path = Join-Path $InputDirectory $asset.name
                if ((Get-ReleaseHash $path) -cne $asset.sha256 -or (Get-Item -LiteralPath $path).Length -ne $asset.size) { throw 'Restore input differs from the original frozen bytes' }
                $existing = @($frozen.release.assets | Where-Object name -ceq $asset.name)
                if ($existing.Count -gt 1 -or ($existing.Count -eq 1 -and ($existing[0].size -ne $asset.size -or $existing[0].digest -cne ('sha256:' + $asset.sha256)))) { throw 'Existing remote asset conflicts with the original frozen bytes; no repairs are allowed' }
            }
            foreach ($asset in $candidate.assets) { Sync-ReleaseAsset $Repository $Tag (Join-Path $InputDirectory $asset.name) | Out-Null }
            Assert-ReleaseRemoteCandidate $candidate (Get-ReleaseRemote $Repository $Tag)
            $record.state = 'original-core-assets-restored'
        } elseif ($Action -ceq 'AcceptanceInputs') {
            $inputs = New-ReleaseDirectory (Join-Path $outputRoot 'inputs')
            Copy-Item -LiteralPath $frozen.path -Destination (Join-Path $inputs 'candidate-manifest.json')
            $core = New-ReleaseDirectory (Join-Path $outputRoot 'core')
            foreach ($asset in $candidate.assets) { Get-ReleaseAsset $Repository (@($frozen.release.assets | Where-Object name -ceq $asset.name)[0]) $core | Out-Null }
            foreach ($build in $candidate.builds) {
                $targetRoot = New-ReleaseDirectory (Join-Path $inputs $build.target)
                $testRoot = New-ReleaseDirectory (Join-Path $targetRoot 'tests')
                Write-BundleJson $build (Join-Path $targetRoot 'build.json')
                Copy-Item -LiteralPath (Join-Path $core $build.source.file) -Destination $targetRoot
                Copy-Item -LiteralPath (Join-Path $core ('regqry-' + $Tag + '-' + $build.target + '.zip')) -Destination $targetRoot
                Copy-Item -LiteralPath (Join-Path $core ('regqry-' + $Tag + '-tests-' + $build.target + '.zip')) -Destination $testRoot
            }
            foreach ($stage in @('source', 'registry')) {
                $accepted = Resolve-ReleaseStagedEvidence $Repository (Get-ReleaseRemote $Repository $Tag) $candidate $record.candidateId $stage (Join-Path $outputRoot ($stage + '-evidence'))
                if ($accepted) {
                    Copy-Item -LiteralPath $accepted.archive -Destination (Join-Path $inputs (Get-ReleaseAcceptanceName $Tag $stage))
                    Set-ReleaseOutput ($stage + '_state') 'accepted'
                    Set-ReleaseOutput ($stage + '_sha256') $accepted.sha256
                } else { Set-ReleaseOutput ($stage + '_state') 'missing' }
            }
            $record.state = 'original-inputs-ready'
        } elseif ($Action -ceq 'StageEvidence') {
            if (-not $InputDirectory) { throw 'Evidence staging requires the preserved original ZIP' }
            $archive = Join-Path $InputDirectory (Get-ReleaseAcceptanceName $Tag $EvidenceStage)
            $accepted = Set-ReleaseStagedEvidence $Repository $frozen.release $candidate $record.candidateId $EvidenceStage $archive (New-ReleaseDirectory (Join-Path $outputRoot 'stage'))
            Set-ReleaseOutput ($EvidenceStage + '_sha256') $accepted.sha256
            $record.state = 'original-evidence-staged'
        } elseif ($Action -ceq 'Evidence') {
            $evidenceRoot = Read-AcceptanceInput
            $record.evidence = Assert-ReleaseEvidence $candidate $record.candidateId $evidenceRoot
            $record.state = 'accepted'
        } elseif ($Action -ceq 'CargoStatus') {
            $evidenceRoot = Read-AcceptanceInput
            $record.evidence = Assert-ReleaseEvidence $candidate $record.candidateId $evidenceRoot
            $registry = Get-ReleaseRegistry $candidate $outputRoot
            $record.state = $registry.status
            if ($registry.status -ceq 'bootstrap-required') { throw 'First publication requires local Windows bootstrap of this accepted candidate, followed by Trusted Publisher binding; CI accepts no API token' }
            if ($registry.status -ceq 'unpublished' -and $frozen.release.body -match '<!-- regqry-cargo-attempt:') { throw 'An earlier Cargo upload may have reached the registry; state remains unknown and automatic re-upload is blocked' }
            Set-ReleaseOutput state $record.state
        } elseif ($Action -cin @('CargoPreflight', 'CargoPublish')) {
            $evidenceRoot = Read-AcceptanceInput
            $record.evidence = Assert-ReleaseEvidence $candidate $record.candidateId $evidenceRoot
            $native = Get-BundleEnvironment
            if ($native.nativeTarget -cne 'x86_64-pc-windows-msvc') { throw 'Strict Cargo packaging/publishing runs on native x64 Windows' }
            $sourceBuild = @($candidate.builds | Where-Object target -ceq $native.nativeTarget)[0]
            $compiler = @(& rustc +1.100.0 -Vv)
            if ($LASTEXITCODE -ne 0 -or ($compiler -join "`n") -cne ($sourceBuild.compiler -join "`n")) { throw 'Cargo preflight compiler differs from candidate construction' }
            $cargoPath = & rustup which --toolchain 1.100.0 cargo
            if ($LASTEXITCODE -ne 0 -or (Get-ReleaseHash $cargoPath) -cne $sourceBuild.toolset.cargoSha256) { throw 'Cargo binary differs from candidate construction' }
            $saved = @{}
            foreach ($name in @('CARGO_TARGET_DIR', 'CARGO_BUILD_WARNINGS', 'RUSTUP_TOOLCHAIN', 'RUSTC', 'RUSTC_WRAPPER', 'RUSTC_WORKSPACE_WRAPPER')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
            Push-Location -LiteralPath $projectRoot
            try {
                $env:CARGO_TARGET_DIR = Join-Path $outputRoot 'target'; $env:CARGO_BUILD_WARNINGS = 'deny'
                $env:RUSTUP_TOOLCHAIN = '1.100.0-x86_64-pc-windows-msvc'
                foreach ($name in @('RUSTC', 'RUSTC_WRAPPER', 'RUSTC_WORKSPACE_WRAPPER')) { Remove-Item -LiteralPath ('Env:\' + $name) -ErrorAction SilentlyContinue }
                $record.package = Invoke-ReleaseProcess $cargoPath @('package', '--locked') (Join-Path $outputRoot 'package')
                if ($record.package.exitCode -ne 0 -or $record.package.timedOut) { throw 'Strict pre-publication packaging failed' }
                $archive = Join-Path $env:CARGO_TARGET_DIR ('package/regqry-' + $candidate.version + '.crate')
                $source = @($candidate.assets | Where-Object name -ceq ('regqry-' + $candidate.version + '.crate'))[0]
                if ((Get-ReleaseHash $archive) -cne $source.sha256) { throw 'Repeated Cargo archive SHA-256 differs; publication is blocked' }
                if ($Action -ceq 'CargoPublish') {
                    if ($LocalBootstrap -and $env:GITHUB_ACTIONS -eq 'true') { throw 'Local bootstrap is never a CI token fallback' }
                    if (-not $LocalBootstrap -and ($env:GITHUB_ACTIONS -ne 'true' -or -not $env:CARGO_REGISTRY_TOKEN -or $env:REGQRY_OIDC_AUTH -cne 'true')) { throw 'CI publication requires the official OIDC exchange in the release job' }
                    $registry = Get-ReleaseRegistry $candidate (New-ReleaseDirectory (Join-Path $outputRoot 'before-publish'))
                    if ($registry.status -ceq 'published') { $record.state = 'already-published' }
                    else {
                        if ($registry.status -ceq 'bootstrap-required' -and -not $LocalBootstrap) { throw 'New crate requires local bootstrap' }
                        if ($frozen.release.body -match '<!-- regqry-cargo-attempt:') { throw 'A prior upload attempt must be reconciled; do not blindly publish again' }
                        if ($LocalBootstrap) { Assert-ReleaseImmutableSettings $Repository }
                        $bodyPath = Join-Path $outputRoot 'upload-attempt.md'
                        [IO.File]::WriteAllText($bodyPath, $frozen.release.body + "`n<!-- regqry-cargo-attempt: $($record.candidateId) $([DateTime]::UtcNow.ToString('o')) -->`n", [Text.UTF8Encoding]::new($false))
                        Invoke-ReleaseGh @('release', 'edit', $Tag, '--repo', $Repository, '--notes-file', $bodyPath) | Out-Null
                        $record.publish = Invoke-ReleaseProcess $cargoPath @('publish', '--locked', '--registry', 'crates-io') (Join-Path $outputRoot 'publish')
                        # Regardless of Cargo exit/timeout, inspect actual registry
                        # state once. No upload is retried inside this invocation.
                        $after = Get-ReleaseRegistry $candidate (New-ReleaseDirectory (Join-Path $outputRoot 'after-publish'))
                        if ($after.status -cne 'published') { throw 'Cargo upload outcome is not confirmed; retain the attempt marker and retry verification later, not the upload' }
                        $record.state = 'published-and-verified'
                    }
                } else { $record.state = 'strict-package-match' }
            } finally { Pop-Location; Restore-BundleEnvironment $saved }
        } elseif ($Action -ceq 'RegistryInstall') {
            $registry = Get-ReleaseRegistry $candidate $outputRoot
            if ($registry.status -cne 'published') { throw 'Registry installation requires the verified exact uploaded archive' }
            $native = Get-BundleEnvironment
            if ($native.nativeTarget -cnotin @('x86_64-pc-windows-msvc', 'aarch64-pc-windows-msvc')) { throw 'Registry installation must run natively' }
            $saved = @{}
            foreach ($name in @('CARGO_HOME', 'CARGO_TARGET_DIR', 'RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS', 'RUSTC', 'RUSTC_WRAPPER', 'RUSTC_WORKSPACE_WRAPPER', 'RUSTUP_TOOLCHAIN')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
            Push-Location -LiteralPath $outputRoot
            try {
                foreach ($name in $saved.Keys) { Remove-Item -LiteralPath ('Env:\' + $name) -ErrorAction SilentlyContinue }
                $env:CARGO_HOME = Join-Path $outputRoot 'cargo-home'; $env:CARGO_TARGET_DIR = Join-Path $outputRoot 'target'
                $toolchain = '1.100.0-' + $native.nativeTarget
                $env:RUSTUP_TOOLCHAIN = $toolchain
                $cargoPath = & rustup which --toolchain $toolchain cargo
                if ($LASTEXITCODE -ne 0) { throw 'Pinned native Cargo is unavailable' }
                $record.compiler = @(& rustc ('+' + $toolchain) -Vv)
                if ($LASTEXITCODE -ne 0 -or $record.compiler -cnotcontains 'release: 1.100.0' -or $record.compiler -cnotcontains ('host: ' + $native.nativeTarget)) { throw 'Registry installation requires the pinned native compiler' }
                $record.install = Invoke-ReleaseProcess $cargoPath @('install', 'regqry', '--version', ('=' + $candidate.version), '--locked', '--registry', 'crates-io', '--root', (Join-Path $outputRoot 'installed')) (Join-Path $outputRoot 'install')
                if ($record.install.exitCode -ne 0 -or $record.install.timedOut) { throw 'Fresh registry installation failed' }
                $cached = @(Get-ChildItem -LiteralPath (Join-Path $env:CARGO_HOME 'registry/cache') -Recurse -File | Where-Object Name -ceq ('regqry-' + $candidate.version + '.crate'))
                $source = @($candidate.assets | Where-Object name -ceq ('regqry-' + $candidate.version + '.crate'))[0]
                if ($cached.Count -ne 1 -or (Get-ReleaseHash $cached[0].FullName) -cne $source.sha256) { throw 'Cargo did not install the actual matching crates.io archive' }
                $installed = Join-Path $outputRoot 'installed/bin/regqry.exe'
                $version = Invoke-ReleaseProcess $installed @('--version') (Join-Path $outputRoot 'version') 30
                $help = Invoke-ReleaseProcess $installed @('--help') (Join-Path $outputRoot 'help') 30
                if ($version.exitCode -ne 0 -or $version.timedOut -or (Get-Content -LiteralPath (Join-Path $outputRoot 'version.stdout.txt') -Raw -Encoding utf8).TrimEnd("`r", "`n") -cne ('regqry ' + $candidate.version) -or $help.exitCode -ne 0 -or $help.timedOut -or (Get-Content -LiteralPath (Join-Path $outputRoot 'help.stdout.txt') -Raw -Encoding utf8) -notmatch 'Usage: regqry \[QUERY OPTIONS\]') { throw 'Fresh registry executable version/help check failed' }
                $record.environment = $native; $record.cliSha256 = Get-ReleaseHash $installed
                $record.sourceSha256 = $source.sha256; $record.state = 'installed-from-registry'
            } finally { Pop-Location; Restore-BundleEnvironment $saved }
        } elseif ($Action -ceq 'Finalize') {
            $acceptedStages = @{}
            foreach ($stage in @('source', 'registry')) {
                $accepted = Resolve-ReleaseStagedEvidence $Repository (Get-ReleaseRemote $Repository $Tag) $candidate $record.candidateId $stage (Join-Path $outputRoot ($stage + '-original'))
                if (-not $accepted) { throw 'Both original hosted acceptance archives must be staged before finalization' }
                $acceptedStages[$stage] = $accepted
            }
            if ($acceptedStages.registry.evidence.sourceArchiveSha256 -cne $acceptedStages.source.sha256) { throw 'Registry acceptance is not based on the original source acceptance archive' }
            $existingValidation = @($frozen.release.assets | Where-Object name -ceq ('regqry-' + $Tag + '-validation.zip'))
            $existingBuild = @($frozen.release.assets | Where-Object name -ceq 'build-manifest.json')
            if ($existingBuild.Count -ne 0 -and $existingValidation.Count -ne 1) { throw 'Final build manifest exists without its original validation archive; recover the preserved original bytes' }
            if ($existingValidation.Count -eq 0) {
            $evidenceRoot = $acceptedStages.registry.root
            $record.evidence = Assert-ReleaseEvidence $candidate $record.candidateId $evidenceRoot -RequireRegistry
            $registry = Get-ReleaseRegistry $candidate (New-ReleaseDirectory (Join-Path $outputRoot 'registry'))
            if ($registry.status -cne 'published') { throw 'Cargo must be public and exact before GitHub finalization' }
            $validationRoot = New-ReleaseDirectory (Join-Path $outputRoot ('regqry-' + $Tag + '-validation'))
            Copy-Item -LiteralPath $evidenceRoot -Destination (Join-Path $validationRoot 'acceptance') -Recurse
            Copy-Item -LiteralPath (Join-Path $outputRoot 'registry/registry.json') -Destination $validationRoot
            $originals = New-ReleaseDirectory (Join-Path $validationRoot 'original')
            foreach ($stage in @('source', 'registry')) { Copy-Item -LiteralPath $acceptedStages[$stage].archive -Destination (Join-Path $originals ($stage + '-acceptance.zip')) }
            $buildRecords = New-ReleaseDirectory (Join-Path $validationRoot 'candidate-records')
            foreach ($file in $candidate.records) {
                Assert-ReleasePath $file.path
                $path = Join-Path $buildRecords $file.path
                New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
                [IO.File]::WriteAllBytes($path, [Convert]::FromBase64String($file.bytes))
                if ((Get-ReleaseHash $path) -cne $file.sha256) { throw 'Embedded candidate log bytes differ' }
            }
            $validationArchive = Join-Path $outputRoot ('regqry-' + $Tag + '-validation.zip')
            $validationFiles = @(Get-ReleaseInventory $validationRoot)
            Write-BundleArchive $validationRoot $validationArchive
            } else {
                # Recover the original archive; never recompress it when a later
                # manifest/checksum upload failed or the Actions run expired.
                $validationArchive = Get-ReleaseAsset $Repository $existingValidation[0] $outputRoot
                $expanded = Expand-ReleaseZip $validationArchive (Join-Path $outputRoot 'existing-validation')
                $validationRoot = Join-Path $expanded ('regqry-' + $Tag + '-validation')
                $record.evidence = Assert-ReleaseEvidence $candidate $record.candidateId (Join-Path $validationRoot 'acceptance') -RequireRegistry
                $validationFiles = @(Get-ReleaseInventory $validationRoot)
            }
            foreach ($stage in @('source', 'registry')) {
                if ((Get-ReleaseHash (Join-Path $validationRoot ('original/' + $stage + '-acceptance.zip'))) -cne $acceptedStages[$stage].sha256) { throw 'Final validation archive changed the original accepted ZIP bytes' }
            }
            $assets = @($candidate.assets)
            $candidateAsset = @($frozen.release.assets | Where-Object name -ceq 'candidate-manifest.json')[0]
            $assets += [ordered]@{ name = 'candidate-manifest.json'; id = $candidateAsset.id; size = $candidateAsset.size; sha256 = $record.candidateId }
            foreach ($stage in @('source', 'registry')) {
                $accepted = $acceptedStages[$stage]
                $assets += [ordered]@{ name=(Get-ReleaseAcceptanceName $Tag $stage); id=$accepted.asset.id; size=$accepted.asset.size; sha256=$accepted.sha256 }
            }
            $assets += Sync-ReleaseAsset $Repository $Tag $validationArchive
            if ($existingBuild.Count -eq 1) {
                $buildPath = Get-ReleaseAsset $Repository $existingBuild[0] $outputRoot
                $buildManifest = Read-ReleaseJson $buildPath
                if ($buildManifest.schemaVersion -ne 1 -or $buildManifest.kind -cne 'regqry-release-build' -or $buildManifest.tag -cne $Tag -or $buildManifest.candidateId -cne $record.candidateId -or $buildManifest.commit -cne $candidate.commit -or $buildManifest.releaseId -ne $candidate.releaseId -or @($buildManifest.assets).Count -ne $assets.Count) { throw 'Existing final build manifest identifies another candidate or asset set' }
                foreach ($asset in $assets) {
                    $original = @($buildManifest.assets | Where-Object name -ceq $asset.name)
                    if ($original.Count -ne 1 -or $original[0].size -ne $asset.size -or $original[0].sha256 -cne $asset.sha256) { throw 'Existing final build manifest changed an original asset identity' }
                }
                Assert-ReleaseInventory $validationRoot @($buildManifest.validationFiles)
            } else {
                $buildManifest = [ordered]@{ schemaVersion = 1; kind = 'regqry-release-build'; tag = $Tag; commit = $candidate.commit; candidateId = $record.candidateId; releaseId = $candidate.releaseId; assets = $assets; validationFiles = $validationFiles; finalizedAtUtc = [DateTime]::UtcNow.ToString('o') }
                $buildPath = Join-Path $outputRoot 'build-manifest.json'; Write-BundleJson $buildManifest $buildPath
            }
            $assets += Sync-ReleaseAsset $Repository $Tag $buildPath
            $sums = @($assets | Sort-Object { $_.name } | ForEach-Object { $_.sha256 + '  ' + $_.name }) -join "`n"
            $sumsPath = Join-Path $outputRoot 'SHA256SUMS'
            [IO.File]::WriteAllText($sumsPath, $sums + "`n", [Text.UTF8Encoding]::new($false))
            Sync-ReleaseAsset $Repository $Tag $sumsPath | Out-Null
            $record.state = 'all-assets-staged'
        } elseif ($Action -ceq 'Publish') {
            # This also handles retries after public success. Download and check
            # the complete exact attachment set before any mutation.
            $expectedNames = @($candidate.assets.name) + @('candidate-manifest.json', (Get-ReleaseAcceptanceName $Tag 'source'), (Get-ReleaseAcceptanceName $Tag 'registry'), ('regqry-' + $Tag + '-validation.zip'), 'build-manifest.json', 'SHA256SUMS')
            $remote = Get-ReleaseRemote $Repository $Tag
            if (@($remote.assets).Count -ne $expectedNames.Count -or @($remote.assets | Where-Object name -cnotin $expectedNames).Count -ne 0) { throw 'Final remote attachment set is incomplete or contains undeclared assets; recover original files before publishing' }
            foreach ($asset in $remote.assets) { if ($asset.name -cne 'candidate-manifest.json') { Get-ReleaseAsset $Repository $asset $outputRoot | Out-Null } }
            $build = Read-ReleaseJson (Join-Path $outputRoot 'build-manifest.json')
            if ($build.schemaVersion -ne 1 -or $build.kind -cne 'regqry-release-build' -or $build.tag -cne $Tag -or $build.commit -cne $candidate.commit -or $build.candidateId -cne $record.candidateId -or $build.releaseId -ne $remote.id -or @($build.assets).Count -ne 9 -or @($build.assets.name | Select-Object -Unique).Count -ne 9) { throw 'Final build manifest has a different identity or asset set' }
            $expectedBuildAssets = @($expectedNames | Where-Object { $_ -cnotin @('build-manifest.json', 'SHA256SUMS') })
            if (@($build.assets | Where-Object name -cnotin $expectedBuildAssets).Count -ne 0) { throw 'Final build manifest omits an original archive or includes an undeclared asset' }
            foreach ($asset in $build.assets) {
                $actual = @($remote.assets | Where-Object name -ceq $asset.name)
                if ($actual.Count -ne 1 -or $actual[0].size -ne $asset.size -or $actual[0].digest -cne ('sha256:' + $asset.sha256)) { throw 'Final asset identity changed after staging' }
            }
            $expectedSums = @($remote.assets | Where-Object name -cne 'SHA256SUMS' | Sort-Object { $_.name } | ForEach-Object { (Get-ReleaseHash (Join-Path $outputRoot $_.name)) + '  ' + $_.name }) -join "`n"
            if ([IO.File]::ReadAllText((Join-Path $outputRoot 'SHA256SUMS')) -cne ($expectedSums + "`n")) { throw 'SHA256SUMS does not cover the complete actual asset set' }
            $expanded = Expand-ReleaseZip (Join-Path $outputRoot ('regqry-' + $Tag + '-validation.zip')) (Join-Path $outputRoot 'validation')
            $validationRoot = Join-Path $expanded ('regqry-' + $Tag + '-validation')
            Assert-ReleaseInventory $validationRoot @($build.validationFiles)
            $record.evidence = Assert-ReleaseEvidence $candidate $record.candidateId (Join-Path $validationRoot 'acceptance') -RequireRegistry
            foreach ($stage in @('source', 'registry')) {
                $archive = Join-Path $outputRoot (Get-ReleaseAcceptanceName $Tag $stage)
                Read-ReleaseAcceptanceArchive $candidate $record.candidateId $stage $archive | Out-Null
                if ((Get-ReleaseHash (Join-Path $validationRoot ('original/' + $stage + '-acceptance.zip'))) -cne (Get-ReleaseHash $archive)) { throw 'Public acceptance asset differs from the original retained inside validation' }
            }
            $registry = Get-ReleaseRegistry $candidate (New-ReleaseDirectory (Join-Path $outputRoot 'registry-final'))
            if ($registry.status -cne 'published') { throw 'Exact Cargo publication must be confirmed before GitHub promotion' }
            if ($remote.draft) {
                # Immutability is enforced by the repository setting configured
                # with the maintainer's existing local identity. CI does not read
                # admin settings; verify the actual public release below.
                Invoke-ReleaseGh @('release', 'edit', $Tag, '--repo', $Repository, '--draft=false', '--verify-tag') | Out-Null
            }
            $remote = Get-ReleaseRemote $Repository $Tag
            if ($remote.draft -or -not $remote.immutable) { throw 'GitHub publication is partial or is not immutable; do not modify the assets or tag' }
            Assert-ReleaseRemoteCandidate $candidate $remote
            $publicRoot = New-ReleaseDirectory (Join-Path $outputRoot 'public-downloads')
            $record.publicDownloads = @()
            foreach ($asset in $remote.assets) {
                $path = Join-Path $publicRoot $asset.name
                # Read the public release URL without forwarding GH_TOKEN.
                Invoke-WebRequest -Uri ("https://github.com/$Repository/releases/download/$Tag/" + $asset.name) -UseBasicParsing -OutFile $path | Out-Null
                if ((Get-Item -LiteralPath $path).Length -ne $asset.size -or ('sha256:' + (Get-ReleaseHash $path)) -cne $asset.digest) { throw 'Public download differs after publication; preserve the partial-state record and use a new version for changed assets' }
                $record.publicDownloads += [ordered]@{ name = $asset.name; size = $asset.size; sha256 = Get-ReleaseHash $path }
            }
            $record.state = 'published-and-verified'
        }
    }
    $record.status = 'pass'
    Write-Output ($Action + ': ' + $record.state)
} catch {
    $record.error = $_.Exception.Message
    if ($env:GITHUB_STEP_SUMMARY) { [IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, "Release stopped at $Action. $($record.error)`n", [Text.UTF8Encoding]::new($false)) }
    throw
} finally {
    $record.finishedAtUtc = [DateTime]::UtcNow.ToString('o')
    Write-BundleJson $record (Join-Path $outputRoot 'result.json')
}

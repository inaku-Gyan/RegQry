[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Source','Registry')][string]$Stage,
    [Parameter(Mandatory)][string]$CandidatePath,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedCandidateSha256,
    [Parameter(Mandatory)][string]$InputDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$QualityDirectory,
    [string]$SourceArchive,
    [string]$ExpectedSourceSha256
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release/support.ps1')
. (Join-Path $PSScriptRoot 'release/evidence.ps1')
if ((Get-ReleaseHash $CandidatePath) -cne $ExpectedCandidateSha256) { throw 'Frozen candidate identity differs before collection' }
$candidate = Read-ReleaseJson $CandidatePath
Assert-ReleaseCandidate $candidate $candidate.tag $candidate.commit
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne 'inaku-Gyan/RegQry' -or
    $env:GITHUB_REF -cne ('refs/tags/' + $candidate.tag) -or $env:GITHUB_SHA -cne $candidate.commit) {
    throw 'Formal collection requires the actual canonical tagged Actions workflow'
}
$outputRoot = New-ReleaseDirectory $OutputDirectory
$name = 'regqry-' + $candidate.tag + '-acceptance'
$root = Join-Path $outputRoot $name
if ($Stage -ceq 'Registry') {
    if (-not $SourceArchive -or $ExpectedSourceSha256 -cnotmatch '^[a-f0-9]{64}$' -or (Get-ReleaseHash $SourceArchive) -cne $ExpectedSourceSha256) { throw 'Registry collection requires the preserved original source acceptance archive and its hash' }
    $original = Expand-ReleaseEvidenceArchive $SourceArchive $candidate.tag
    Assert-ReleaseEvidence $candidate $ExpectedCandidateSha256 $original | Out-Null
    if ((Read-ReleaseJson (Join-Path $original 'acceptance.json')).stage -cne 'source') { throw 'Registry collection must start from the original source-stage archive' }
    Copy-Item -LiteralPath $original -Destination $root -Recurse
    $evidence = Read-ReleaseJson (Join-Path $root 'acceptance.json')
    $originals = New-ReleaseDirectory (Join-Path $root 'original')
    Copy-Item -LiteralPath $SourceArchive -Destination (Join-Path $originals 'source-acceptance.zip')
    $evidence.stage = 'registry'
    $evidence.sourceArchiveSha256 = $ExpectedSourceSha256
} else {
    if (-not $QualityDirectory) { throw 'Source collection requires original dependency and release-model records' }
    New-ReleaseDirectory $root | Out-Null
    $qualityRoot = New-ReleaseDirectory (Join-Path $root 'quality')
    foreach ($file in @('dependencies.json','release-model.json')) {
        Copy-Item -LiteralPath (Join-Path $QualityDirectory $file) -Destination $qualityRoot
    }
    $evidence = [ordered]@{
        schemaVersion=2;kind='regqry-release-acceptance';status='pass';stage='source';sourceArchiveSha256=$null;candidateId=$ExpectedCandidateSha256;tag=$candidate.tag;commit=$candidate.commit
        assets=@($candidate.assets|ForEach-Object{[ordered]@{name=$_.name;sha256=$_.sha256}})
        checks=@();platforms=@();deferredChecks=@(@{id='minimum-clean-clients';status='not-run'},@{id='visible-terminal-and-physical-keyboard';status='not-run'});files=@()
    }
    New-ReleaseDirectory (Join-Path $root 'provenance') | Out-Null
}
$stageName = $Stage.ToLowerInvariant()
$stageRoot = New-ReleaseDirectory (Join-Path $root $stageName)
foreach ($id in @('hosted-x64','hosted-arm64')) {
    $target = if ($id -ceq 'hosted-x64') { 'x86_64-pc-windows-msvc' } else { 'aarch64-pc-windows-msvc' }
    $inputRoot = (Get-Item -LiteralPath (Join-Path $InputDirectory $target)).FullName
    Get-ReleaseInventory $inputRoot | Out-Null
    $hosted = Read-ReleaseJson (Join-Path $inputRoot 'result.json')
    if ($hosted.status -cne 'pass' -or $hosted.target -cne $target -or $hosted.source.git.sha1 -cne $candidate.commit -or
        $hosted.workflow.runId -notmatch '^[0-9]+$' -or $hosted.workflow.attempt -notmatch '^[0-9]+$') { throw 'A required original hosted result did not execute successfully for this candidate' }
    $runId = $hosted.workflow.runId; $attempt = $hosted.workflow.attempt
    $run = (Invoke-ReleaseGh @('api',("repos/inaku-Gyan/RegQry/actions/runs/$runId"))) -join [char]10 | ConvertFrom-Json
    $jobs = (Invoke-ReleaseGh @('api','--paginate','--slurp',("repos/inaku-Gyan/RegQry/actions/runs/$runId/attempts/$attempt/jobs?per_page=100"),'--jq','[.[].jobs[]]')) -join [char]10 | ConvertFrom-Json
    $matchingJobs = @($jobs | Where-Object {
        $_.runner_name -ceq $hosted.workflow.runner -and $_.run_attempt -eq $attempt -and $_.status -ceq 'completed' -and
        [DateTimeOffset]$_.started_at -le [DateTimeOffset]$hosted.startedAtUtc -and [DateTimeOffset]$_.completed_at -ge [DateTimeOffset]$hosted.finishedAtUtc
    })
    if ($matchingJobs.Count -ne 1) { throw 'Cannot identify one actual completed hosted job for this original result' }
    $proofPath = 'provenance/' + $stageName + '-' + $id + '.json'
    Write-BundleJson ([ordered]@{schemaVersion=1;kind='regqry-github-hosted-provenance';run=$run;job=$matchingJobs[0]}) (Join-Path $root $proofPath)
    Copy-Item -LiteralPath $inputRoot -Destination (Join-Path $stageRoot $id) -Recurse
    if ($Stage -ceq 'Source') {
        $evidence.platforms += [ordered]@{id=$id;status='pass';sourceRun=($stageName+'/'+$id+'/result.json');sourceProvenance=$proofPath;registryRun=$null;registryProvenance=$null}
    } else {
        $platform = @($evidence.platforms|Where-Object id -ceq $id)
        if ($platform.Count -ne 1) { throw 'Original source platform is missing or duplicated' }
        $platform[0].registryRun = $stageName+'/'+$id+'/result.json'
        $platform[0].registryProvenance = $proofPath
    }
}
if ($Stage -ceq 'Source') {
    for ($number=1;$number -le 14;$number++) {
        $records = @('source/hosted-x64/result.json','source/hosted-arm64/result.json')
        $observation = 'Original ordinary-user fixture, portable and installed-source records; raw case logs and candidate identities are checked.'
        if ($number -eq 12) { $records=@('quality/dependencies.json');$observation='Fresh pinned dependency audit and native candidate build records.' }
        if ($number -eq 14) { $records=@('quality/release-model.json');$observation='Explicit synthetic failure-recovery checks plus frozen candidate identity; actual channel promotion is verified separately after this pre-publication gate.' }
        $evidence.checks += [ordered]@{id=('A{0:00}' -f $number);status='pass';observation=$observation;records=$records}
    }
}
$evidence.files = @(Get-ReleaseInventory $root | Where-Object path -cne 'acceptance.json')
Write-BundleJson $evidence (Join-Path $root 'acceptance.json')
$summary = @(Assert-ReleaseEvidence $candidate $ExpectedCandidateSha256 $root -RequireRegistry:($Stage -ceq 'Registry'))
$archive = Join-Path $outputRoot ('regqry-' + $candidate.tag + '-' + $stageName + '-acceptance.zip')
Write-BundleArchive $root $archive
Write-BundleJson ([ordered]@{schemaVersion=1;kind='regqry-collected-acceptance';status='pass';stage=$Stage;candidateId=$ExpectedCandidateSha256;tag=$candidate.tag;commit=$candidate.commit;archive=$archive;sha256=(Get-ReleaseHash $archive);platforms=$summary}) (Join-Path $outputRoot 'result.json')
Write-Output ('Collected original ' + $stageName + ' acceptance: ' + (Get-ReleaseHash $archive))

function Get-ReleaseAcceptanceName {
    param([string]$Tag, [string]$Stage)
    if ($Stage -cnotin @('source','registry')) { throw 'Unknown acceptance stage' }
    'regqry-' + $Tag + '-' + $Stage + '-acceptance.zip'
}

function Get-ReleaseAcceptanceMarker {
    param([object]$Release, [string]$Stage, [string]$CandidateId)
    $prefix = '<!-- regqry-' + $Stage + '-acceptance '
    $pattern = [regex]::Escape($prefix) + 'candidate=([a-f0-9]{64}) sha256=([a-f0-9]{64}) run=([0-9]+) artifact=([a-zA-Z0-9_-]+) -->'
    $markers = [regex]::Matches([string]$Release.body, $pattern)
    if ($markers.Count -eq 0) {
        if (([string]$Release.body).Contains($prefix)) { throw 'Malformed accepted-evidence marker; do not replace unknown original bytes' }
        return $null
    }
    if ($markers.Count -ne 1 -or $markers[0].Groups[1].Value -cne $CandidateId -or $markers[0].Groups[4].Value -cne ($Stage + '-acceptance-original')) { throw 'Accepted-evidence marker identifies another candidate or ambiguous original' }
    [ordered]@{ sha256=$markers[0].Groups[2].Value; runId=$markers[0].Groups[3].Value; artifact=$markers[0].Groups[4].Value }
}

function Read-ReleaseAcceptanceArchive {
    param([object]$Candidate, [string]$CandidateId, [string]$Stage, [string]$Archive)
    $root = Expand-ReleaseEvidenceArchive $Archive $Candidate.tag
    $evidence = Read-ReleaseJson (Join-Path $root 'acceptance.json')
    if ($evidence.stage -cne $Stage) { throw 'Acceptance archive identifies the wrong source/registry stage' }
    Assert-ReleaseEvidence $Candidate $CandidateId $root -RequireRegistry:($Stage -ceq 'registry') | Out-Null
    [ordered]@{ archive=$Archive; sha256=(Get-ReleaseHash $Archive); root=$root; evidence=$evidence }
}

function Get-ReleaseStagedEvidence {
    param([string]$Repository, [object]$Release, [object]$Candidate, [string]$CandidateId, [string]$Stage, [string]$Directory)
    $name = Get-ReleaseAcceptanceName $Candidate.tag $Stage
    $assets = @($Release.assets|Where-Object name -ceq $name)
    if ($assets.Count -eq 0) { return $null }
    if ($assets.Count -ne 1) { throw 'Ambiguous staged acceptance asset' }
    $download = New-ReleaseDirectory $Directory
    $archive = Get-ReleaseAsset $Repository $assets[0] $download
    $value = Read-ReleaseAcceptanceArchive $Candidate $CandidateId $Stage $archive
    $marker = Get-ReleaseAcceptanceMarker $Release $Stage $CandidateId
    if ($marker -and $marker.sha256 -cne $value.sha256) { throw 'Staged evidence differs from its original accepted-byte marker' }
    $value.asset = $assets[0]
    $value
}

function Set-ReleaseStagedEvidence {
    param([string]$Repository, [object]$Release, [object]$Candidate, [string]$CandidateId, [string]$Stage, [string]$Archive, [string]$Directory)
    if (-not $Release.draft) { throw 'Never upload or replace acceptance evidence on a public release' }
    $expectedName = Get-ReleaseAcceptanceName $Candidate.tag $Stage
    if ([IO.Path]::GetFileName($Archive) -cne $expectedName) { throw 'Original acceptance archive name differs from the frozen version/stage' }
    $value = Read-ReleaseAcceptanceArchive $Candidate $CandidateId $Stage $Archive
    $marker = Get-ReleaseAcceptanceMarker $Release $Stage $CandidateId
    if ($marker -and $marker.sha256 -cne $value.sha256) { throw 'Accepted original evidence bytes differ; restore originals instead of repacking' }
    if (-not $marker) {
        if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_RUN_ID -notmatch '^[0-9]+$') { throw 'First evidence staging requires its original Actions artifact and run identity' }
        $line = '<!-- regqry-' + $Stage + '-acceptance candidate=' + $CandidateId + ' sha256=' + $value.sha256 + ' run=' + $env:GITHUB_RUN_ID + ' artifact=' + $Stage + '-acceptance-original -->'
        $notesPath = Join-Path $Directory ($Stage + '-acceptance-notes.txt')
        [IO.File]::WriteAllText($notesPath, ([string]$Release.body).TrimEnd() + [char]10 + [char]10 + $line + [char]10, [Text.UTF8Encoding]::new($false))
        # The original ZIP is uploaded as an Actions artifact before this step.
        # Record its hash/reference before the potentially uncertain asset upload.
        Invoke-ReleaseGh @('release','edit',$Candidate.tag,'--repo',$Repository,'--notes-file',$notesPath) | Out-Null
    }
    Sync-ReleaseAsset $Repository $Candidate.tag $Archive | Out-Null
    $actual = Get-ReleaseRemote $Repository $Candidate.tag
    Get-ReleaseStagedEvidence $Repository $actual $Candidate $CandidateId $Stage (Join-Path $Directory 'verified-remote')
}

function Resolve-ReleaseStagedEvidence {
    param([string]$Repository, [object]$Release, [object]$Candidate, [string]$CandidateId, [string]$Stage, [string]$Directory)
    $existing = Get-ReleaseStagedEvidence $Repository $Release $Candidate $CandidateId $Stage (Join-Path $Directory 'existing')
    if ($existing) { return $existing }
    $marker = Get-ReleaseAcceptanceMarker $Release $Stage $CandidateId
    if (-not $marker) {
        # A failed job can have uploaded the original Actions artifact before
        # recording its draft marker. Discover that successful upload rather
        # than collecting/recompressing a second purported original on retry.
        if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_RUN_ID -notmatch '^[0-9]+$') { return $null }
        $artifactName = $Stage + '-acceptance-original'
        $artifacts = @(Get-ReleaseApiItems "repos/$Repository/actions/runs/$($env:GITHUB_RUN_ID)/artifacts?per_page=100" 'artifacts')
        $originalArtifacts = @($artifacts | Where-Object name -ceq $artifactName)
        if ($originalArtifacts.Count -eq 0) { return $null }
        if ($originalArtifacts.Count -ne 1 -or $originalArtifacts[0].expired -ne $false) { throw 'Original acceptance artifact is ambiguous or expired; never create a replacement original' }
        $artifactRoot = New-ReleaseDirectory (Join-Path $Directory 'unmarked-original')
        Invoke-ReleaseGh @('run','download',$env:GITHUB_RUN_ID,'--repo',$Repository,'--name',$artifactName,'--dir',$artifactRoot) | Out-Null
        $archive = Join-Path $artifactRoot (Get-ReleaseAcceptanceName $Candidate.tag $Stage)
        return Set-ReleaseStagedEvidence $Repository $Release $Candidate $CandidateId $Stage $archive (New-ReleaseDirectory (Join-Path $Directory 'reconciled-original'))
    }
    if (-not $Release.draft) { throw 'A public release is missing its original acceptance asset' }
    $original = $null
    if ($Stage -ceq 'source') {
        $registry = Get-ReleaseStagedEvidence $Repository $Release $Candidate $CandidateId registry (Join-Path $Directory 'registry-original')
        if ($registry) { $original = Join-Path $registry.root 'original/source-acceptance.zip' }
    }
    if (-not $original) {
        $validationAsset = @($Release.assets|Where-Object name -ceq ('regqry-' + $Candidate.tag + '-validation.zip'))
        if ($validationAsset.Count -eq 1) {
            $download = New-ReleaseDirectory (Join-Path $Directory 'validation-original')
            $validation = Get-ReleaseAsset $Repository $validationAsset[0] $download
            $expanded = Expand-ReleaseZip $validation (Join-Path $download 'expanded')
            $validationRoot = Join-Path $expanded ('regqry-' + $Candidate.tag + '-validation')
            Assert-ReleaseEvidence $Candidate $CandidateId (Join-Path $validationRoot 'acceptance') -RequireRegistry | Out-Null
            $original = Join-Path $validationRoot ('original/' + $Stage + '-acceptance.zip')
        }
    }
    if (-not $original) {
        $artifactRoot = New-ReleaseDirectory (Join-Path $Directory 'original-artifact')
        Invoke-ReleaseGh @('run','download',$marker.runId,'--repo',$Repository,'--name',$marker.artifact,'--dir',$artifactRoot) | Out-Null
        $original = Join-Path $artifactRoot (Get-ReleaseAcceptanceName $Candidate.tag $Stage)
    }
    if ((Get-ReleaseHash $original) -cne $marker.sha256) { throw 'Preserved accepted evidence is missing or has a different hash; never reconstruct accepted ZIPs' }
    $restore = New-ReleaseDirectory (Join-Path $Directory 'restore')
    $archive = Join-Path $restore (Get-ReleaseAcceptanceName $Candidate.tag $Stage)
    Copy-Item -LiteralPath $original -Destination $archive
    Set-ReleaseStagedEvidence $Repository $Release $Candidate $CandidateId $Stage $archive (New-ReleaseDirectory (Join-Path $Directory 'restored-record'))
}

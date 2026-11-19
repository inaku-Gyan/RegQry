[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CandidatePath,
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$Commit,
    [string]$AssetDirectory,
    [string]$EvidenceDirectory,
    [string]$ReportPath
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release/support.ps1')
. (Join-Path $PSScriptRoot 'release/evidence.ps1')
$result = [ordered]@{ schemaVersion = 1; status = 'fail'; tag = $Tag; commit = $Commit; candidateId = $null; assets = 0; evidence = $null; error = $null; checkedAtUtc = [DateTime]::UtcNow.ToString('o') }
try {
    $candidate = Read-ReleaseJson $CandidatePath
    Assert-ReleaseCandidate $candidate $Tag $Commit
    $result.candidateId = Get-ReleaseHash $CandidatePath
    if ($AssetDirectory) {
        foreach ($asset in $candidate.assets) {
            $path = Join-Path $AssetDirectory $asset.name
            if ((Get-ReleaseHash $path) -cne $asset.sha256 -or (Get-Item -LiteralPath $path).Length -ne $asset.size) { throw ('Candidate asset differs: ' + $asset.name) }
            $result.assets++
        }
    }
    if ($EvidenceDirectory) { $result.evidence = Assert-ReleaseEvidence $candidate $result.candidateId $EvidenceDirectory }
    $result.status = 'pass'
    Write-Output ('Release identity verified: ' + $result.candidateId)
} catch { $result.error = $_.Exception.Message; throw }
finally { if ($ReportPath) { Write-BundleJson $result $ReportPath } }

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('New', 'Pack')][string]$Action,
    [Parameter(Mandatory)][string]$CandidatePath,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedCandidateSha256,
    [Parameter(Mandatory)][string]$Directory,
    [string]$ArchivePath,
    [switch]$RequireRegistry
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release/support.ps1')
. (Join-Path $PSScriptRoot 'release/evidence.ps1')
if ((Get-ReleaseHash $CandidatePath) -cne $ExpectedCandidateSha256) { throw 'Candidate manifest differs from the previously recorded candidate ID' }
$candidate = Read-ReleaseJson $CandidatePath
Assert-ReleaseCandidate $candidate $candidate.tag $candidate.commit
$root = [IO.Path]::GetFullPath($Directory).TrimEnd('\')
Assert-ReleasePath (Split-Path -Leaf $root)
if ($Action -ceq 'New') {
    New-ReleaseDirectory $root | Out-Null
    $record = [ordered]@{ schemaVersion = 1; kind = 'regqry-release-acceptance'; status = 'missing'; candidateId = $ExpectedCandidateSha256; tag = $candidate.tag; commit = $candidate.commit; assets = @($candidate.assets | ForEach-Object { [ordered]@{ name = $_.name; sha256 = $_.sha256 } }); checks = @(); platforms = @(); files = @() }
    for ($index = 1; $index -le 14; $index++) { $record.checks += [ordered]@{ id = 'A{0:00}' -f $index; status = 'missing'; observation = ''; records = @() } }
    foreach ($id in @('win10-x64', 'win11-x64', 'win11-arm64')) {
        $record.platforms += [ordered]@{ id = $id; status = 'missing'; channel = ''; edition = ''; displayVersion = ''; portable = "$id/portable/result.json"; cleanSystem = "$id/clean.json"; vmPrepare = "$id/prepare/result.json"; vmQuery = "$id/query/result.json"; rollback = "$id/rollback.json"; sourceInstall = "$id/source-install.json"; registryInstall = "$id/registry-install.json"; terminals = @() }
    }
    Write-BundleJson $record (Join-Path $root 'acceptance.json')
    [IO.File]::WriteAllText((Join-Path $root 'README.txt'), "UNEXECUTED TEMPLATE. Every status starts missing.`nCollect actual original records described in docs/release-evidence.md.`nPack validates identities and evidence; it never changes a status to pass.`n", [Text.UTF8Encoding]::new($false))
    Write-Output ('Created unexecuted acceptance template: ' + $root)
} else {
    if (-not $ArchivePath) { throw 'Pack requires a new ArchivePath outside the evidence directory' }
    $archive = [IO.Path]::GetFullPath($ArchivePath)
    if ($archive.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence archive must be outside its own inventory' }
    if (Test-Path -LiteralPath $archive) { throw 'Evidence archives are never overwritten' }
    $record = Read-ReleaseJson (Join-Path $root 'acceptance.json')
    $record.files = @(Get-ReleaseInventory $root | Where-Object path -cne 'acceptance.json')
    Write-BundleJson $record (Join-Path $root 'acceptance.json')
    Assert-ReleaseEvidence $candidate $ExpectedCandidateSha256 $root -RequireRegistry:$RequireRegistry | Out-Null
    Write-BundleArchive $root $archive
    Write-Output ('Acceptance ZIP SHA-256: ' + (Get-ReleaseHash $archive))
}

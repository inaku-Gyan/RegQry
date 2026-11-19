[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$')][string]$Repository,
    [Parameter(Mandatory)][ValidatePattern('^[0-9]+$')][string]$RunId,
    [Parameter(Mandatory)][string]$ReportDirectory
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release/support.ps1')
$root = New-ReleaseDirectory $ReportDirectory
$record = [ordered]@{
    schemaVersion=1;kind='regqry-github-api-contract';status='fail'
    scope='actual gh and read-only workflow metadata; no release or registry writes'
    repository=$Repository;runId=$RunId;powerShell=$PSVersionTable.PSVersion.ToString()
    ghVersion=$null;jobCount=0;artifactCount=0;readAttempts=0;error=$null
}
try {
    $version = @(& gh --version)
    if ($LASTEXITCODE -ne 0 -or $version.Count -eq 0 -or $version[0] -notmatch '^gh version [0-9]') { throw 'Cannot identify the real GitHub CLI' }
    $record.ghVersion = $version[0]
    $consistent = $false
    for ($attempt=0; $attempt -lt 3; $attempt++) {
        $record.readAttempts++
        $paged = @(Get-ReleaseApiItems "repos/$Repository/actions/runs/$RunId/jobs?per_page=1" 'jobs')
        $wide = @(Get-ReleaseApiItems "repos/$Repository/actions/runs/$RunId/jobs?per_page=100" 'jobs')
        $ids = @($paged | ForEach-Object { [string]$_.id })
        $wideIds = @($wide | ForEach-Object { [string]$_.id })
        # Jobs can be scheduled while this read-only check is running. Re-read a
        # changing list, and only compare a complete stable pair of responses.
        if ($ids.Count -ge 2 -and @($ids | Sort-Object -Unique).Count -eq $ids.Count -and
            @($paged | Where-Object { $_.id -le 0 -or $_.run_id -ne [long]$RunId }).Count -eq 0 -and
            $ids.Count -eq $wideIds.Count -and @(Compare-Object $ids $wideIds).Count -eq 0) {
            $consistent = $true; $record.jobCount = $ids.Count; break
        }
    }
    if (-not $consistent) { throw 'Real gh did not return matching complete job pages; workflow metadata may still be changing' }
    $artifacts = @(Get-ReleaseApiItems "repos/$Repository/actions/runs/$RunId/artifacts?per_page=1" 'artifacts')
    $artifactIds = @($artifacts | ForEach-Object { [string]$_.id })
    if (@($artifacts | Where-Object { $_.id -le 0 -or [string]::IsNullOrWhiteSpace($_.name) }).Count -ne 0 -or
        @($artifactIds | Sort-Object -Unique).Count -ne $artifacts.Count) { throw 'Real gh artifact pages contain invalid or duplicate records' }
    $record.artifactCount = $artifacts.Count
    $record.status = 'pass'
    Write-Output ('GitHub API contract verified with real ' + $record.ghVersion + ': ' + $record.jobCount + ' jobs, ' + $record.artifactCount + ' artifacts')
} catch { $record.error = $_.Exception.Message; throw }
finally { Write-BundleJson $record (Join-Path $root 'result.json') }

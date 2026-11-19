[CmdletBinding()]
param([switch]$EnableImmutable, [string]$ReportPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release/support.ps1')
if ($env:GITHUB_ACTIONS -eq 'true') { throw 'Release settings use the existing local administrator gh login, never CI credentials' }
if (-not $ReportPath) { $ReportPath = Join-Path (Split-Path -Parent $PSScriptRoot) ('artifacts/release-settings-' + [guid]::NewGuid().ToString('N') + '.json') }
$ReportPath = [IO.Path]::GetFullPath($ReportPath)
if (Test-Path -LiteralPath $ReportPath) { throw 'Settings records are never overwritten' }
New-Item -ItemType Directory -Path (Split-Path -Parent $ReportPath) -Force | Out-Null
$record = [ordered]@{ schemaVersion = 1; kind = 'regqry-release-settings'; status = 'fail'; repository = 'inaku-Gyan/RegQry'; repositoryId = 1462950131; operation = $(if ($EnableImmutable) { 'enable-and-verify' } else { 'verify' }); settings = $null; checkedAtUtc = [DateTime]::UtcNow.ToString('o'); error = $null }
try {
    $repo = (Invoke-ReleaseGh @('api', 'repos/inaku-Gyan/RegQry')) -join "`n" | ConvertFrom-Json
    if ($repo.id -ne $record.repositoryId -or $repo.full_name -cne $record.repository -or $repo.permissions.admin -ne $true) { throw 'Local release configuration requires the canonical repository and existing administrator access' }
    if ($EnableImmutable) { Invoke-ReleaseGh @('api', '--method', 'PUT', 'repos/inaku-Gyan/RegQry/immutable-releases') | Out-Null }
    $record.settings = (Invoke-ReleaseGh @('api', 'repos/inaku-Gyan/RegQry/immutable-releases')) -join "`n" | ConvertFrom-Json
    if ($record.settings.enabled -ne $true) { throw 'Immutable releases are not enabled; explicitly use -EnableImmutable for initial setup' }
    $record.status = 'pass'
    Write-Output 'Immutable releases enabled and verified; CI needs no administrator credential'
} catch { $record.error = $_.Exception.Message; throw }
finally { Write-BundleJson $record $ReportPath }

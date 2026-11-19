[CmdletBinding()]
param(
    [string]$CacheParent = [System.IO.Path]::GetTempPath(),
    [string]$ConfigPath,
    [string]$ReportDirectory
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $ConfigPath) { $ConfigPath = Join-Path $projectRoot 'deny.toml' }
if (-not $ReportDirectory) { $ReportDirectory = Join-Path $projectRoot 'artifacts/dependencies' }
$tools = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'tools.psd1')
$toolVersion = & cargo deny --version
if ($LASTEXITCODE -ne 0 -or $toolVersion -ne ('cargo-deny ' + $tools.CargoDeny)) {
    throw ('cargo-deny ' + $tools.CargoDeny + ' is required; see CONTRIBUTING.md')
}
$cache = Join-Path $CacheParent ('regqry-audit-' + [guid]::NewGuid().ToString('N'))
if (Test-Path -LiteralPath $cache) { throw 'Audit requires a fresh cache directory' }
New-Item -ItemType Directory -Path $cache -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
$previousCargoHome = $env:CARGO_HOME
$operation = 'fetch'
$record = [ordered]@{
    status = 'fail'
    tool = $toolVersion
    cache = $cache
    config = (Resolve-Path -LiteralPath $ConfigPath).Path
    lockSha256 = (Get-FileHash -LiteralPath (Join-Path $projectRoot 'Cargo.lock') -Algorithm SHA256).Hash.ToLowerInvariant()
    startedAtUtc = [DateTime]::UtcNow.ToString('o')
}
Push-Location -LiteralPath $projectRoot
try {
    $env:CARGO_HOME = $cache
    & cargo deny --locked --config $ConfigPath fetch db index
    if ($LASTEXITCODE -ne 0) { throw 'Dependency database/index fetch failed; check was not run' }
    $record.fetchedAtUtc = [DateTime]::UtcNow.ToString('o')
    $databases = @(Get-ChildItem -LiteralPath (Join-Path $cache 'advisory-dbs') -Directory)
    if (-not $databases.Count) { throw 'No fetched advisory database is available' }
    $record.advisoryDatabases = @(
        foreach ($database in $databases) {
            $commit = & git -C $database.FullName rev-parse HEAD
            if ($LASTEXITCODE -ne 0) { throw 'Cannot identify the fetched advisory snapshot' }
            [ordered]@{ directory = $database.Name; commit = $commit }
        }
    )
    $indexRoot = Join-Path $cache 'registry/index'
    $record.indexSnapshot = @(
        Get-ChildItem -LiteralPath $indexRoot -File -Recurse | Sort-Object FullName | ForEach-Object {
            [ordered]@{
                path = $_.FullName.Substring($indexRoot.Length + 1).Replace('\', '/')
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    )
    $operation = 'check'
    & cargo deny --locked --config $ConfigPath check advisories bans licenses sources
    if ($LASTEXITCODE -ne 0) { throw 'Dependency checks failed' }
    $record.status = 'pass'
}
finally {
    try {
        $record.operation = $operation
        $record.finishedAtUtc = [DateTime]::UtcNow.ToString('o')
        $record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $ReportDirectory 'result.json') -Encoding utf8
    }
    finally {
        $env:CARGO_HOME = $previousCargoHome
        Pop-Location
    }
}

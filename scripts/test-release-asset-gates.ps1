[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildReport,
    [Parameter(Mandatory)][string]$ReportDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bundle/support.ps1')
$builtText = Get-Content -LiteralPath $BuildReport -Raw -Encoding utf8
$built = $builtText | ConvertFrom-Json
if ($built.status -cne 'pass') { throw 'Successful native assets are required for rejection probes' }
$reportRoot = [IO.Path]::GetFullPath($ReportDirectory)
if (Test-Path -LiteralPath $reportRoot) { throw 'Gate ReportDirectory must not exist' }
New-Item -ItemType Directory -Path $reportRoot | Out-Null
$copies = Join-Path ([IO.Path]::GetTempPath()) ('regqry-asset-gates-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $copies | Out-Null
$record = [ordered]@{ schemaVersion = 1; status = 'fail'; scope = 'controlled asset rejection probes; no global registry access'; copiesRoot = $copies; cases = @(); error = $null }
$before = @{}
foreach ($name in @('PATH', 'RUSTUP_TOOLCHAIN', 'REGQRY_TEST_BIN', 'REGQRY_TEST_PWSH', 'REGQRY_LIVE_CONFIRM')) { $before[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$location = (Get-Location).Path
function Update-ProbeFile {
    param([object]$Manifest, [string]$Root, [string]$Relative)
    $entry = @($Manifest.files | Where-Object path -ceq $Relative)[0]
    if (-not $entry) { throw 'Probe fixture has no file entry to update' }
    $path = Join-Path $Root $Relative
    $entry.size = (Get-Item -LiteralPath $path).Length
    $entry.sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}
try {
    foreach ($case in @('archive-hash', 'manifest-hash', 'source-hash', 'changed-cli', 'missing-notices', 'wrong-license-scope', 'empty-license-graph', 'missing-rust-notices', 'changed-license-text', 'broken-document-link', 'unsafe-zip-path', 'duplicate-zip-entry', 'test-cli-identity')) {
        $copy = $builtText | ConvertFrom-Json
        $caseRoot = Join-Path $copies $case
        New-Item -ItemType Directory -Path $caseRoot | Out-Null
        $userName = 'regqry-v' + $built.version + '-' + $built.target
        $userRoot = Join-Path $caseRoot $userName
        Copy-Item -LiteralPath $built.user.directory -Destination $userRoot -Recurse
        $manifestPath = Join-Path $userRoot 'bundle-manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
        $expected = switch ($case) {
            'archive-hash' { 'Asset archive hash mismatch' }
            'manifest-hash' { 'User manifest differs' }
            'source-hash' { 'Cargo source archive hash mismatch' }
            'changed-cli' {
                $stream = [IO.File]::Open((Join-Path $userRoot 'regqry.exe'), [IO.FileMode]::Append)
                try { $stream.WriteByte(0) } finally { $stream.Dispose() }
                'User payload hash mismatch: regqry.exe'
            }
            'missing-notices' {
                Remove-Item -LiteralPath (Join-Path $userRoot 'THIRD-PARTY-NOTICES.txt')
                $manifest.files = @($manifest.files | Where-Object path -cne 'THIRD-PARTY-NOTICES.txt')
                'Missing required user payload: THIRD-PARTY-NOTICES.txt'
            }
            { $_ -in @('wrong-license-scope', 'empty-license-graph', 'missing-rust-notices') } {
                $path = Join-Path $userRoot 'licenses/materials.json'
                $materials = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
                if ($case -eq 'wrong-license-scope') { $materials.scope = 'tests' }
                elseif ($case -eq 'empty-license-graph') { $materials.cargoPackages = @() }
                else {
                    $relative = 'licenses/rust/COPYRIGHT-library.html'
                    Remove-Item -LiteralPath (Join-Path $userRoot $relative)
                    $materials.files = @($materials.files | Where-Object path -cne $relative)
                    $manifest.files = @($manifest.files | Where-Object path -cne $relative)
                }
                Write-BundleJson -Value $materials -Path $path
                Update-ProbeFile -Manifest $manifest -Root $userRoot -Relative 'licenses/materials.json'
                if ($case -eq 'wrong-license-scope') { 'license materials differ' }
                elseif ($case -eq 'empty-license-graph') { 'license graph is empty' }
                else { 'Missing required distribution material: licenses/rust/COPYRIGHT-library.html' }
            }
            'changed-license-text' {
                $relative = 'licenses/rust/LICENSE-MIT'
                [IO.File]::AppendAllText((Join-Path $userRoot $relative), 'changed', [Text.UTF8Encoding]::new($false))
                Update-ProbeFile -Manifest $manifest -Root $userRoot -Relative $relative
                'Distribution license file differs: licenses/rust/LICENSE-MIT'
            }
            'broken-document-link' {
                [IO.File]::AppendAllText((Join-Path $userRoot 'README.md'), "`n[Missing](docs/missing.md)`n", [Text.UTF8Encoding]::new($false))
                Update-ProbeFile -Manifest $manifest -Root $userRoot -Relative 'README.md'
                'Broken or external local documentation link: README.md -> docs/missing.md'
            }
            'unsafe-zip-path' { 'Invalid or duplicate user ZIP entry' }
            'duplicate-zip-entry' { 'Invalid or duplicate user ZIP entry' }
            'test-cli-identity' {
                $testName = 'regqry-v' + $built.version + '-tests-' + $built.target
                $testRoot = Join-Path $caseRoot $testName
                Copy-Item -LiteralPath $built.tests.directory -Destination $testRoot -Recurse
                $testManifestPath = Join-Path $testRoot 'bundle-manifest.json'
                $testManifest = Get-Content -LiteralPath $testManifestPath -Raw -Encoding utf8 | ConvertFrom-Json
                @($testManifest.files | Where-Object path -ceq 'regqry.exe')[0].sha256 = '0' * 64
                Write-BundleJson -Value $testManifest -Path $testManifestPath
                $copy.tests.archive = Join-Path $caseRoot ($testName + '.zip')
                Write-BundleArchive -Root $testRoot -Archive $copy.tests.archive
                $copy.tests.sha256 = (Get-FileHash -LiteralPath $copy.tests.archive -Algorithm SHA256).Hash.ToLowerInvariant()
                $copy.tests.manifestSha256 = (Get-FileHash -LiteralPath $testManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
                'User and test bundle CLI/source identities differ'
            }
        }
        Write-BundleJson -Value $manifest -Path $manifestPath
        $copy.user.manifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $copy.user.directory = $userRoot
        $copy.user.archive = Join-Path $caseRoot ($userName + '.zip')
        Write-BundleArchive -Root $userRoot -Archive $copy.user.archive
        if ($case -in @('unsafe-zip-path', 'duplicate-zip-entry')) {
            $zip = [IO.Compression.ZipFile]::Open($copy.user.archive, [IO.Compression.ZipArchiveMode]::Update)
            $entry = if ($case -eq 'unsafe-zip-path') { $userName + '/../outside.txt' } else { $userName + '/REGQRY.EXE' }
            try { $zip.CreateEntry($entry) | Out-Null } finally { $zip.Dispose() }
        }
        $copy.user.sha256 = (Get-FileHash -LiteralPath $copy.user.archive -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($case -eq 'archive-hash') { $copy.user.sha256 = '0' * 64 }
        if ($case -eq 'manifest-hash') { $copy.user.manifestSha256 = '0' * 64 }
        if ($case -eq 'source-hash') { $copy.source.sha256 = '0' * 64 }
        $copyReport = Join-Path $caseRoot 'build.json'
        Write-BundleJson -Value $copy -Path $copyReport
        $checkRoot = Join-Path $reportRoot $case
        $failure = $null
        try { & (Join-Path $PSScriptRoot 'check-release-assets.ps1') -BuildReport $copyReport -ReportDirectory $checkRoot }
        catch { $failure = $_.Exception.Message }
        if (-not $failure -or $failure -notmatch [regex]::Escape($expected)) { throw ('Asset gate did not reject ' + $case + ': ' + $failure) }
        $rejected = Get-Content -LiteralPath (Join-Path $checkRoot 'result.json') -Raw -Encoding utf8 | ConvertFrom-Json
        if ($rejected.status -cne 'fail' -or $rejected.processesStarted -ne 0 -or (Test-Path -LiteralPath (Join-Path $checkRoot 'tests'))) { throw ('Rejected asset started payload execution: ' + $case) }
        foreach ($name in $before.Keys) {
            if ([Environment]::GetEnvironmentVariable($name, 'Process') -cne $before[$name]) { throw ('Rejected asset changed ' + $name) }
        }
        if ((Get-Location).Path -cne $location) { throw 'Rejected asset changed the caller working directory' }
        $record.cases += [ordered]@{ name = $case; status = 'pass'; expectedRejection = $failure; processesStarted = 0 }
    }
    foreach ($asset in @($built.user, $built.tests)) {
        if ((Get-FileHash -LiteralPath $asset.archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $asset.sha256) { throw 'Gate probes changed an original asset' }
    }
    $record.status = 'pass'
    Write-Output ('Release asset rejection gates passed: ' + $record.cases.Count)
} catch {
    $record.error = $_.Exception.Message
    throw
} finally {
    Write-BundleJson -Value $record -Path (Join-Path $reportRoot 'result.json')
}

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BundleDirectory,
    [string]$BundleArchive,
    [string]$ReportDirectory,
    [string]$DynamicExecutable
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bundle/support.ps1')
$bundleRoot = (Get-Item -LiteralPath $BundleDirectory).FullName
$originalManifest = Join-Path $bundleRoot 'bundle-manifest.json'
$originalHash = (Get-FileHash -LiteralPath $originalManifest -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest = Get-Content -LiteralPath $originalManifest -Raw -Encoding utf8 | ConvertFrom-Json
$runId = [guid]::NewGuid().ToString('N')
if (-not $ReportDirectory) { $ReportDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) ('artifacts/test-bundle-gates/' + $runId) }
$reportRoot = [IO.Path]::GetFullPath($ReportDirectory)
if (Test-Path -LiteralPath $reportRoot) { throw 'ReportDirectory must not exist' }
New-Item -ItemType Directory -Path $reportRoot | Out-Null
$copies = Join-Path ([IO.Path]::GetTempPath()) ('regqry-bundle-gates-' + $runId)
New-Item -ItemType Directory -Path $copies | Out-Null
$result = [ordered]@{
    schemaVersion = 1
    status = 'fail'
    scope = 'controlled invalid-bundle and PE gate probes; no global registry access'
    startedAtUtc = [DateTime]::UtcNow.ToString('o')
    manifestSha256 = $originalHash
    copiesRoot = $copies
    cases = @()
    error = $null
}
$savedBin = $env:REGQRY_TEST_BIN
try {
    foreach ($case in @('manifest-hash', 'changed-cli', 'missing-payload', 'extra-executable', 'missing-test-inventory', 'failed-pe-check', 'wrong-license-scope', 'empty-license-graph', 'missing-license-notices')) {
        $copy = Join-Path $copies $case
        Copy-Item -LiteralPath $bundleRoot -Destination $copy -Recurse
        $copyManifestPath = Join-Path $copy 'bundle-manifest.json'
        $copyManifest = Get-Content -LiteralPath $copyManifestPath -Raw -Encoding utf8 | ConvertFrom-Json
        $runnerArgs = @{ ReportDirectory = (Join-Path $reportRoot $case) }
        $expected = switch ($case) {
            'manifest-hash' {
                $runnerArgs.ExpectedManifestSha256 = '0' * 64
                'manifest hash differs'
            }
            'changed-cli' {
                $file = [IO.File]::Open((Join-Path $copy 'regqry.exe'), [IO.FileMode]::Append)
                try { $file.WriteByte(0) } finally { $file.Dispose() }
                'Bundle hash mismatch: regqry.exe'
            }
            'missing-payload' {
                Remove-Item -LiteralPath (Join-Path $copy 'LICENSE')
                'Missing bundle payload: LICENSE'
            }
            'extra-executable' {
                [IO.File]::WriteAllBytes((Join-Path $copy 'unlisted.exe'), [byte[]]@(0))
                'Undeclared bundle file: unlisted.exe'
            }
            'missing-test-inventory' {
                $copyManifest.tests = @($copyManifest.tests | Select-Object -Skip 1)
                Write-BundleJson -Value $copyManifest -Path $copyManifestPath
                'Executable absent from test inventory'
            }
            'failed-pe-check' {
                $pePath = Join-Path $copy 'dll-imports.json'
                $pe = Get-Content -LiteralPath $pePath -Raw -Encoding utf8 | ConvertFrom-Json
                $pe.status = 'fail'
                Write-BundleJson -Value $pe -Path $pePath
                $file = @($copyManifest.files | Where-Object path -eq 'dll-imports.json')[0]
                $file.sha256 = (Get-FileHash -LiteralPath $pePath -Algorithm SHA256).Hash.ToLowerInvariant()
                $file.size = (Get-Item -LiteralPath $pePath).Length
                Write-BundleJson -Value $copyManifest -Path $copyManifestPath
                'no successful matching PE check'
            }
            { $_ -in @('wrong-license-scope', 'empty-license-graph') } {
                $path = Join-Path $copy 'licenses/materials.json'
                $materials = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
                if ($case -eq 'wrong-license-scope') { $materials.scope = 'production' }
                else { $materials.cargoPackages = @() }
                Write-BundleJson -Value $materials -Path $path
                $file = @($copyManifest.files | Where-Object path -eq 'licenses/materials.json')[0]
                $file.sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
                $file.size = (Get-Item -LiteralPath $path).Length
                Write-BundleJson -Value $copyManifest -Path $copyManifestPath
                if ($case -eq 'wrong-license-scope') { 'license materials differ' } else { 'license graph is empty' }
            }
            'missing-license-notices' {
                Remove-Item -LiteralPath (Join-Path $copy 'THIRD-PARTY-NOTICES.txt')
                $copyManifest.files = @($copyManifest.files | Where-Object path -ne 'THIRD-PARTY-NOTICES.txt')
                Write-BundleJson -Value $copyManifest -Path $copyManifestPath
                'Missing required bundle file: THIRD-PARTY-NOTICES.txt'
            }
        }
        $env:REGQRY_TEST_BIN = 'parent-environment-must-survive'
        $errorText = $null
        try { & (Join-Path $copy 'run-tests.ps1') @runnerArgs }
        catch { $errorText = $_.Exception.Message }
        if (-not $errorText -or $errorText -notmatch [regex]::Escape($expected)) { throw ('Gate did not reject ' + $case + ': ' + $errorText) }
        $record = Get-Content -LiteralPath (Join-Path $runnerArgs.ReportDirectory 'result.json') -Raw -Encoding utf8 | ConvertFrom-Json
        if ($record.status -ne 'fail' -or $record.processesStarted -ne 0 -or @($record.tests).Count -ne 0) { throw ('Gate started a payload process: ' + $case) }
        if ($env:REGQRY_TEST_BIN -cne 'parent-environment-must-survive') { throw 'Failed runner did not restore its environment' }
        $result.cases += [ordered]@{ name = $case; status = 'pass'; expectedRejection = $errorText; processesStarted = $record.processesStarted }
    }
    $otherTarget = if ($manifest.target -eq 'x86_64-pc-windows-msvc') { 'aarch64-pc-windows-msvc' } else { 'x86_64-pc-windows-msvc' }
    $errorText = $null
    try { & (Join-Path $PSScriptRoot 'check-pe.ps1') -Executable (Join-Path $bundleRoot 'regqry.exe') -Target $otherTarget -ReportDirectory (Join-Path $reportRoot 'wrong-pe-machine') }
    catch { $errorText = $_.Exception.Message }
    if (-not $errorText -or $errorText -notmatch 'PE machine mismatch') { throw ('Wrong PE machine did not fail: ' + $errorText) }
    $result.cases += [ordered]@{ name = 'wrong-pe-machine'; status = 'pass'; expectedRejection = $errorText }
    if ($BundleArchive) {
        $priorLocation = (Get-Location).Path
        $priorEnvironment = @{}
        foreach ($name in @('PATH', 'CARGO_HOME', 'CARGO_TARGET_DIR', 'RUSTUP_HOME', 'RUSTUP_TOOLCHAIN', 'REGQRY_TEST_BIN')) {
            $priorEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        $errorText = $null
        $zipReport = Join-Path $reportRoot 'archive-hash'
        try { & (Join-Path $PSScriptRoot 'check-test-bundle.ps1') -BundleArchive $BundleArchive -ExpectedArchiveSha256 ('0' * 64) -ReportDirectory $zipReport }
        catch { $errorText = $_.Exception.Message }
        if (-not $errorText -or $errorText -notmatch 'ZIP hash differs') { throw ('Wrong ZIP identity did not fail: ' + $errorText) }
        if ((Get-Location).Path -cne $priorLocation) { throw 'Rejected ZIP did not restore its working directory' }
        foreach ($name in $priorEnvironment.Keys) {
            if ([Environment]::GetEnvironmentVariable($name, 'Process') -cne $priorEnvironment[$name]) { throw ('Rejected ZIP changed ' + $name) }
        }
        if (Test-Path -LiteralPath (Join-Path $zipReport 'tests/result.json')) { throw 'Rejected ZIP started its runner' }
        $result.cases += [ordered]@{ name = 'archive-hash'; status = 'pass'; expectedRejection = $errorText }
        try {
            [Environment]::SetEnvironmentVariable('RUSTUP_HOME', '', 'Process')
            Remove-Item -LiteralPath Env:\RUSTUP_TOOLCHAIN -ErrorAction SilentlyContinue
            $failureEnvironment = @{}
            foreach ($name in $priorEnvironment.Keys) { $failureEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
            $errorText = $null
            $failedRunReport = Join-Path $reportRoot 'relocation-error-restoration'
            try { & (Join-Path $PSScriptRoot 'check-test-bundle.ps1') -BundleArchive $BundleArchive -ExpectedManifestSha256 ('0' * 64) -ReportDirectory $failedRunReport }
            catch { $errorText = $_.Exception.Message }
            if (-not $errorText -or $errorText -notmatch 'manifest hash differs') { throw ('Relocated invalid manifest did not fail: ' + $errorText) }
            foreach ($name in $failureEnvironment.Keys) {
                if ([Environment]::GetEnvironmentVariable($name, 'Process') -cne $failureEnvironment[$name]) { throw ('Failed relocation changed ' + $name) }
            }
            if ((Get-Location).Path -cne $priorLocation) { throw 'Failed relocation changed working directory' }
            $failedRun = Get-Content -LiteralPath (Join-Path $failedRunReport 'tests/result.json') -Raw -Encoding utf8 | ConvertFrom-Json
            if ($failedRun.status -ne 'fail' -or $failedRun.processesStarted -ne 0) { throw 'Invalid relocated manifest started a payload' }
            $result.cases += [ordered]@{ name = 'relocation-error-restoration'; status = 'pass'; expectedRejection = $errorText; processesStarted = 0 }
        } finally { Restore-BundleEnvironment -Saved $priorEnvironment }
    }
    if ($DynamicExecutable) {
        $errorText = $null
        try { & (Join-Path $PSScriptRoot 'check-pe.ps1') -Executable $DynamicExecutable -Target $manifest.target -ReportDirectory (Join-Path $reportRoot 'dynamic-crt') }
        catch { $errorText = $_.Exception.Message }
        if (-not $errorText -or $errorText -notmatch 'Unapproved DLL or dynamic CRT import') { throw ('Dynamic CRT did not fail: ' + $errorText) }
        $result.cases += [ordered]@{ name = 'dynamic-crt'; status = 'pass'; expectedRejection = $errorText }
    }
    if ((Get-FileHash -LiteralPath $originalManifest -Algorithm SHA256).Hash.ToLowerInvariant() -cne $originalHash) { throw 'Gate probes changed the original bundle manifest' }
    $result.status = 'pass'
    Write-Output ('Portable bundle rejection gates passed: ' + $result.cases.Count)
} catch {
    $result.error = $_.Exception.Message
    throw
} finally {
    $result.finishedAtUtc = [DateTime]::UtcNow.ToString('o')
    try { Write-BundleJson -Value $result -Path (Join-Path $reportRoot 'result.json') }
    finally { $env:REGQRY_TEST_BIN = $savedBin }
}

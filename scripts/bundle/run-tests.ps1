[CmdletBinding()]
param(
    [string]$ReportDirectory = (Join-Path ([IO.Path]::GetTempPath()) ('regqry-test-results-' + [guid]::NewGuid().ToString('N'))),
    [ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedManifestSha256,
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'support.ps1')
$bundleRoot = $PSScriptRoot
$reportRoot = [IO.Path]::GetFullPath($ReportDirectory)
$bundlePrefix = [IO.Path]::GetFullPath($bundleRoot).TrimEnd('\') + '\'
if ($reportRoot.TrimEnd('\') -eq $bundleRoot.TrimEnd('\') -or $reportRoot.StartsWith($bundlePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Store test reports outside the verified bundle'
}
if (Test-Path -LiteralPath $reportRoot) { throw 'ReportDirectory must not exist' }
New-Item -ItemType Directory -Path $reportRoot | Out-Null
$result = [ordered]@{
    schemaVersion = 1
    status = 'fail'
    scope = 'portable development tests; not formal VM, clean-system or release acceptance'
    startedAtUtc = [DateTime]::UtcNow.ToString('o')
    manifestSha256 = $null
    source = $null
    environment = $null
    processesStarted = 0
    tests = @()
    error = $null
}
$savedBin = $env:REGQRY_TEST_BIN
try {
    $manifestPath = Join-Path $bundleRoot 'bundle-manifest.json'
    $result.manifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ExpectedManifestSha256 -and $result.manifestSha256 -ine $ExpectedManifestSha256) { throw 'Bundle manifest hash differs from the expected identity' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or $manifest.kind -ne 'regqry-development-test-bundle') { throw 'Unsupported bundle manifest' }
    if ((Get-Item -LiteralPath $bundleRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Bundle root must not be a reparse point' }
    $items = @(Get-ChildItem -LiteralPath $bundleRoot -Recurse -Force)
    foreach ($item in $items) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Bundle must not contain reparse points' }
    }
    $declared = @{}
    foreach ($file in $manifest.files) {
        if ($file.path -notmatch '^[a-zA-Z0-9_./-]+$' -or $file.path -match '(^|/)\.\.?(/|$)' -or $file.path.StartsWith('/') -or $declared.ContainsKey($file.path)) {
            throw 'Invalid or duplicate bundle file identity'
        }
        $declared[$file.path] = $true
        $path = Join-Path $bundleRoot $file.path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw ('Missing bundle payload: ' + $file.path) }
        $item = Get-Item -LiteralPath $path
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Bundle payload must contain regular files' }
        if ($item.Length -ne $file.size -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.sha256) {
            throw ('Bundle hash mismatch: ' + $file.path)
        }
    }
    foreach ($item in $items) {
        if (-not $item.PSIsContainer) {
            $relative = $item.FullName.Substring($bundlePrefix.Length).Replace('\', '/')
            if ($relative -ne 'bundle-manifest.json' -and -not $declared.ContainsKey($relative)) { throw ('Undeclared bundle file: ' + $relative) }
        }
    }
    foreach ($required in @('regqry.exe', 'run-tests.ps1', 'support.ps1', 'dll-imports.json', 'LICENSE')) {
        if (-not $declared.ContainsKey($required)) { throw ('Missing required bundle file: ' + $required) }
    }
    $pe = Get-Content -LiteralPath (Join-Path $bundleRoot 'dll-imports.json') -Raw -Encoding utf8 | ConvertFrom-Json
    if ($pe.schemaVersion -ne 1 -or $pe.status -ne 'pass' -or $pe.target -ne $manifest.target) { throw 'Bundle has no successful matching PE check' }
    $checkedExecutables = @{}
    foreach ($entry in $pe.executables) {
        if ($checkedExecutables.ContainsKey($entry.file)) { throw 'Duplicate PE executable identity' }
        $checkedExecutables[$entry.file] = $entry.sha256
    }
    $testPaths = @{}
    foreach ($test in $manifest.tests) {
        if ($testPaths.ContainsKey($test.path) -or -not $declared.ContainsKey($test.path) -or $test.path -notmatch '^tests/[a-zA-Z0-9_.-]+\.exe$') { throw 'Invalid or duplicate test executable identity' }
        $testPaths[$test.path] = $true
    }
    $exeCount = 0
    foreach ($file in $manifest.files) {
        if ($file.path -match '\.exe$') {
            $name = [IO.Path]::GetFileName($file.path)
            if ($checkedExecutables[$name] -cne $file.sha256) { throw ('Executable differs from PE check: ' + $file.path) }
            if ($file.path -ne 'regqry.exe' -and -not $testPaths.ContainsKey($file.path)) { throw ('Executable absent from test inventory: ' + $file.path) }
            $exeCount++
        } elseif ($file.path -match '\.dll$') { throw 'This bundle format does not distribute additional DLLs' }
    }
    if ($exeCount -ne $checkedExecutables.Count) { throw 'PE executable inventory differs from bundle files' }
    $result.source = $manifest.source
    $result.environment = Get-BundleEnvironment
    if ($result.environment.nativeTarget -ne $manifest.target) { throw 'Bundle target differs from native Windows architecture; emulation is not native acceptance' }
    $env:REGQRY_TEST_BIN = Join-Path $bundleRoot 'regqry.exe'
    $result.processesStarted++
    $version = Invoke-BundleProcess -Program $env:REGQRY_TEST_BIN -Arguments @('--version') -TimeoutSeconds $TimeoutSeconds
    if ($version.timedOut -or $version.exitCode -ne 0 -or $version.stdout -cne ("regqry " + $manifest.version + "`n") -or $version.stderr) {
        throw 'Bundled CLI version check failed'
    }
    $total = 0
    foreach ($test in $manifest.tests) {
        if (-not $declared.ContainsKey($test.path) -or $test.path -notmatch '^tests/[a-zA-Z0-9_.-]+\.exe$') { throw 'Undeclared test executable' }
        $program = Join-Path $bundleRoot $test.path
        $result.processesStarted++
        $listed = Invoke-BundleProcess -Program $program -Arguments @('--list', '--format=terse') -TimeoutSeconds $TimeoutSeconds
        [string[]]$names = @($listed.stdout -split "`r?`n" | Where-Object { $_ -match ': test$' })
        [Array]::Sort($names, [StringComparer]::Ordinal)
        if ($listed.timedOut -or $listed.exitCode -ne 0 -or $listed.stderr -or ($names -join "`n") -cne (@($test.names) -join "`n")) {
            throw ('Test inventory differs from the bundle: ' + $test.path)
        }
        $result.processesStarted++
        $ran = Invoke-BundleProcess -Program $program -Arguments @('--test-threads=1', '--nocapture') -TimeoutSeconds $TimeoutSeconds
        $logName = [IO.Path]::GetFileNameWithoutExtension($test.path)
        [IO.File]::WriteAllText((Join-Path $reportRoot ($logName + '.stdout.txt')), $ran.stdout, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $reportRoot ($logName + '.stderr.txt')), $ran.stderr, [Text.UTF8Encoding]::new($false))
        $summary = [regex]::Match($ran.stdout, 'test result: ok\. (\d+) passed; 0 failed; (\d+) ignored;')
        $passed = $summary.Success -and -not $ran.timedOut -and $ran.exitCode -eq 0 -and [int]$summary.Groups[1].Value -eq $test.runnable -and [int]$summary.Groups[2].Value -eq $test.ignored
        $result.tests += [ordered]@{
            path = $test.path
            status = $(if ($passed) { 'pass' } else { 'fail' })
            exitCode = $ran.exitCode
            timedOut = $ran.timedOut
            elapsedMs = $ran.elapsedMs
            runnable = $test.runnable
            ignored = $test.ignored
            arguments = $ran.arguments
            stdout = $logName + '.stdout.txt'
            stderr = $logName + '.stderr.txt'
        }
        if (-not $passed) { throw ('Portable test failed: ' + $test.path) }
        $total += $test.runnable
    }
    if ($total -eq 0) { throw 'Bundle ran no tests' }
    $result.status = 'pass'
    $result.passedTests = $total
    Write-Output ('Portable tests passed: ' + $total)
} catch {
    $result.error = $_.Exception.Message
    throw
} finally {
    $env:REGQRY_TEST_BIN = $savedBin
    $result.finishedAtUtc = [DateTime]::UtcNow.ToString('o')
    Write-BundleJson -Value $result -Path (Join-Path $reportRoot 'result.json')
}

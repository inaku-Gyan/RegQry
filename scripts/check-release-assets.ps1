[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildReport,
    [Parameter(Mandatory)][string]$ReportDirectory,
    [string]$PowerShell7
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bundle/support.ps1')
$built = Get-Content -LiteralPath $BuildReport -Raw -Encoding utf8 | ConvertFrom-Json
if ($built.schemaVersion -ne 1 -or $built.kind -cne 'regqry-native-assets' -or $built.status -cne 'pass') { throw 'A successful native asset build is required' }
$reportRoot = [IO.Path]::GetFullPath($ReportDirectory)
if (Test-Path -LiteralPath $reportRoot) { throw 'Asset check ReportDirectory must not exist' }
New-Item -ItemType Directory -Path $reportRoot | Out-Null
$runRoot = Join-Path ([IO.Path]::GetTempPath()) ('RegQry assets space ' + [char]0x7a7a + [char]0x95f4 + '-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot | Out-Null
$record = [ordered]@{
    schemaVersion = 1
    status = 'fail'
    scope = 'development asset identity, no-query CLI and relocation checks; not formal clean/minimum-system acceptance'
    source = $built.source
    target = $built.target
    userArchiveSha256 = $built.user.sha256
    testArchiveSha256 = $built.tests.sha256
    environment = $null
    runRoot = $runRoot
    processesStarted = 0
    commands = @()
    error = $null
}
$saved = @{ PATH = [Environment]::GetEnvironmentVariable('PATH', 'Process') }
try {
    foreach ($asset in @($built.user, $built.tests)) {
        if ((Get-FileHash -LiteralPath $asset.archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $asset.sha256) { throw 'Asset archive hash mismatch' }
    }
    if ((Get-FileHash -LiteralPath $built.sourceArchive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $built.source.sha256) { throw 'Cargo source archive hash mismatch' }
    $userName = 'regqry-v' + $built.version + '-' + $built.target
    if ([IO.Path]::GetFileName($built.user.archive) -cne ($userName + '.zip')) { throw 'User archive name differs from its version/target' }
    $testName = 'regqry-v' + $built.version + '-tests-' + $built.target
    if ([IO.Path]::GetFileName($built.tests.archive) -cne ($testName + '.zip') -or $built.source.file -cne ('regqry-' + $built.version + '.crate') -or [IO.Path]::GetFileName($built.sourceArchive) -cne $built.source.file) { throw 'Test/source archive name differs from its version/target' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    # Check the complete ZIP namespace before extraction, including case-folded
    # collisions, absolute/parent paths, extra roots and directories.
    $zip = [IO.Compression.ZipFile]::OpenRead($built.user.archive)
    try {
        $entries = @{}
        if ($zip.Entries.Count -eq 0) { throw 'Empty user archive' }
        foreach ($entry in $zip.Entries) {
            if (-not $entry.FullName.StartsWith($userName + '/', [StringComparison]::Ordinal) -or $entry.FullName -notmatch '^[a-zA-Z0-9_./-]+$' -or $entry.FullName -match '(^|/)\.\.?(/|$)' -or $entry.FullName.EndsWith('/') -or $entries.ContainsKey($entry.FullName)) { throw 'Invalid or duplicate user ZIP entry' }
            $entries[$entry.FullName] = $true
        }
    } finally { $zip.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($built.user.archive, $runRoot)
    $userRoot = Join-Path $runRoot $userName
    $manifestPath = Join-Path $userRoot 'bundle-manifest.json'
    if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $built.user.manifestSha256) { throw 'User manifest differs from the expected identity' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or $manifest.kind -cne 'regqry-user-bundle' -or $manifest.version -cne $built.version -or $manifest.target -cne $built.target -or $manifest.source.sha256 -cne $built.source.sha256 -or $manifest.source.lockSha256 -cne $built.source.lockSha256 -or $manifest.source.git.sha1 -cne $built.source.git.sha1) { throw 'User bundle input identity mismatch' }
    $declared = @{}
    foreach ($file in $manifest.files) {
        if ($file.path -notmatch '^[a-zA-Z0-9_./-]+$' -or $file.path -match '(^|/)\.\.?(/|$)' -or $file.path.StartsWith('/') -or $declared.ContainsKey($file.path) -or $file.path -eq 'bundle-manifest.json') { throw 'Invalid user file identity' }
        $declared[$file.path] = $file
        $item = Get-Item -LiteralPath (Join-Path $userRoot $file.path)
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -ne $file.size -or (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.sha256) { throw ('User payload hash mismatch: ' + $file.path) }
        if ($file.path -match '\.(exe|dll|ps1|cmd|bat)$' -and $file.path -cne 'regqry.exe') { throw 'Unexpected executable payload in user ZIP' }
    }
    foreach ($item in Get-ChildItem -LiteralPath $userRoot -Recurse -Force) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'User payload contains a reparse point' }
        if (-not $item.PSIsContainer) {
            $relative = $item.FullName.Substring($userRoot.Length + 1).Replace('\', '/')
            if ($relative -cne 'bundle-manifest.json' -and -not $declared.ContainsKey($relative)) { throw 'Undeclared user payload' }
        }
    }
    foreach ($file in @('regqry.exe', 'README.md', 'LICENSE', 'CHANGELOG.md', 'BUILD.txt', 'THIRD-PARTY-NOTICES.txt', 'licenses/materials.json', 'dll-imports.json', 'docs/usage.md', 'docs/matching.md', 'docs/compatibility.md')) {
        if (-not $declared.ContainsKey($file)) { throw ('Missing required user payload: ' + $file) }
    }
    Assert-BundleLicenseMaterials -Root $userRoot -Scope production -Target $built.target -LockSha256 $built.source.lockSha256
    $pe = Get-Content -LiteralPath (Join-Path $userRoot 'dll-imports.json') -Raw -Encoding utf8 | ConvertFrom-Json
    if ($pe.status -cne 'pass' -or $pe.target -cne $built.target -or @($pe.executables).Count -ne 1 -or $pe.executables[0].file -cne 'regqry.exe' -or $pe.executables[0].sha256 -cne $declared['regqry.exe'].sha256 -or $built.user.cliSha256 -cne $declared['regqry.exe'].sha256) { throw 'User CLI differs from its successful PE check' }
    $testEntry = 'regqry-v' + $built.version + '-tests-' + $built.target + '/bundle-manifest.json'
    $testManifest = Read-BundleZipManifest -Archive $built.tests.archive -Entry $testEntry -ExpectedSha256 $built.tests.manifestSha256
    if ($testManifest.kind -cne 'regqry-development-test-bundle' -or $testManifest.target -cne $built.target -or $testManifest.version -cne $built.version -or $testManifest.source.sha256 -cne $built.source.sha256 -or $testManifest.source.lockSha256 -cne $built.source.lockSha256 -or $testManifest.source.git.sha1 -cne $built.source.git.sha1 -or @($testManifest.files | Where-Object { $_.path -ceq 'regqry.exe' -and $_.sha256 -ceq $built.user.cliSha256 }).Count -ne 1) { throw 'User and test bundle CLI/source identities differ' }
    foreach ($item in Get-ChildItem -LiteralPath $userRoot -Recurse -File -Filter '*.md') {
        $text = Get-Content -LiteralPath $item.FullName -Raw -Encoding utf8
        foreach ($link in [regex]::Matches($text, '\]\(([^\s)]+)\)')) {
            $target = $link.Groups[1].Value
            if ($target -match '^(https?://|#|mailto:)') { continue }
            $target = ($target -split '#', 2)[0]
            $resolved = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $item.FullName) $target))
            if (-not $resolved.StartsWith($userRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw ('Broken or external local documentation link: ' + $item.Name + ' -> ' + $target) }
        }
    }
    $env:PATH = (Join-Path $env:WINDIR 'System32') + ';' + $PSHOME
    $record.environment = Get-BundleEnvironment
    if ($record.environment.nativeTarget -cne $built.target -or $record.environment.cargoOnPath -or $record.environment.rustcOnPath) { throw 'Run the relocated asset check natively without Cargo or rustc on PATH' }
    $unrelated = Join-Path $runRoot 'unrelated-working-directory'
    New-Item -ItemType Directory -Path $unrelated | Out-Null
    Push-Location -LiteralPath $unrelated
    try {
        foreach ($option in @('--version', '--help')) {
            $record.processesStarted++
            $ran = Invoke-BundleProcess -Program (Join-Path $userRoot 'regqry.exe') -Arguments @($option)
            $record.commands += $ran
            if ($ran.timedOut -or $ran.exitCode -ne 0 -or $ran.stderr) { throw 'Relocated user CLI failed' }
            if ($option -eq '--version' -and $ran.stdout -cne ('regqry ' + $built.version + "`n")) { throw 'User CLI version mismatch' }
            if ($option -eq '--help' -and $ran.stdout -notmatch 'Usage: regqry \[QUERY OPTIONS\]') { throw 'User CLI help mismatch' }
        }
    } finally { Pop-Location }
    # Execute the frozen test ZIP independently; it verifies its full inventory
    # and test-scope materials before any CLI or harness starts.
    & (Join-Path $PSScriptRoot 'check-test-bundle.ps1') -BundleArchive $built.tests.archive -ExpectedArchiveSha256 $built.tests.sha256 -ExpectedManifestSha256 $built.tests.manifestSha256 -ReportDirectory (Join-Path $reportRoot 'tests') -PowerShell7 $PowerShell7
    $record.status = 'pass'
    Write-Output ('Native asset identity and relocation passed: ' + $built.target)
} catch {
    $record.error = $_.Exception.Message
    throw
} finally {
    try { Write-BundleJson -Value $record -Path (Join-Path $reportRoot 'result.json') }
    finally { Restore-BundleEnvironment -Saved $saved }
}

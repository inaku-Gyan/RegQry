[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceArchive,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateSet('x86_64-pc-windows-msvc', 'aarch64-pc-windows-msvc')][string]$Target,
    [string]$Dumpbin,
    [string]$CargoAbout,
    [switch]$AllowDirty
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bundle/support.ps1')
$projectRoot = Split-Path -Parent $PSScriptRoot
$SourceArchive = (Get-Item -LiteralPath $SourceArchive).FullName
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $outputRoot) { throw 'Asset OutputDirectory must not exist; existing assets are never rebuilt in place' }
$native = Get-BundleEnvironment
if (-not $Target) { $Target = $native.nativeTarget }
if ($Target -cne $native.nativeTarget) { throw 'Release assets require a matching native Windows build' }
$head = & git -C $projectRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify the build scripts commit' }
$changes = @(& git -C $projectRoot status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the build checkout' }
if (-not $AllowDirty -and $changes.Count -ne 0) { throw 'Release asset construction requires a clean checkout' }
$entries = @(& tar -tf $SourceArchive)
if ($LASTEXITCODE -ne 0 -or $entries.Count -eq 0) { throw 'Cannot list the Cargo archive' }
$archiveName = ($entries[0] -split '/')[0]
if ($archiveName -notmatch '^regqry-[0-9][a-zA-Z0-9.+-]*$') { throw 'Unexpected Cargo archive root' }
$vcsText = & tar -xOf $SourceArchive ($archiveName + '/.cargo_vcs_info.json')
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the Cargo archive commit' }
$vcs = $vcsText | ConvertFrom-Json
if ($vcs.git.sha1 -cne $head -or (-not $AllowDirty -and $vcs.git.dirty)) { throw 'Source archive and build scripts must belong to the same clean commit' }
New-Item -ItemType Directory -Path $outputRoot | Out-Null
$record = [ordered]@{
    schemaVersion = 1
    kind = 'regqry-native-assets'
    status = 'fail'
    scope = 'asset construction only; candidate freezing and formal acceptance are separate'
    startedAtUtc = [DateTime]::UtcNow.ToString('o')
    scriptsCommit = $head
    scriptsDirty = $changes.Count -ne 0
    target = $Target
    version = $null
    source = $null
    sourceArchive = $null
    sourceFiles = @()
    compiler = @()
    cargo = $null
    rustFlags = @()
    environment = $native
    tests = $null
    user = $null
    error = $null
}
try {
    $testOutput = Join-Path $outputRoot 'tests'
    & (Join-Path $PSScriptRoot 'build-test-bundle.ps1') -SourceArchive $SourceArchive -OutputDirectory $testOutput -Target $Target -Dumpbin $Dumpbin -CargoAbout $CargoAbout
    $built = Get-Content -LiteralPath (Join-Path $testOutput 'build.json') -Raw -Encoding utf8 | ConvertFrom-Json
    if ($built.status -cne 'pass' -or $built.source.git.sha1 -cne $head -or (-not $AllowDirty -and $built.source.git.dirty)) {
        throw 'Source archive and build scripts must belong to the same clean commit'
    }
    $testManifest = Get-Content -LiteralPath (Join-Path $built.bundle.directory 'bundle-manifest.json') -Raw -Encoding utf8 | ConvertFrom-Json
    $record.version = $testManifest.version
    $record.source = $built.source
    $record.compiler = $built.compiler
    $record.cargo = $built.cargo
    $record.rustFlags = $built.rustFlags
    foreach ($item in Get-ChildItem -LiteralPath $built.sourceDirectory -Recurse -Force -File | Sort-Object FullName) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Cargo archive contents must be regular files' }
        $record.sourceFiles += [ordered]@{ path = $item.FullName.Substring($built.sourceDirectory.Length + 1).Replace('\', '/'); size = $item.Length; sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    $record.sourceArchive = Join-Path $outputRoot $built.source.file
    Copy-Item -LiteralPath $SourceArchive -Destination $record.sourceArchive
    if ((Get-FileHash -LiteralPath $record.sourceArchive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $built.source.sha256) { throw 'Cargo source archive changed during asset construction' }
    $record.tests = $built.bundle
    $bundleName = 'regqry-v' + $record.version + '-' + $Target
    $userRoot = Join-Path $outputRoot $bundleName
    New-Item -ItemType Directory -Path $userRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $built.bundle.directory 'regqry.exe') -Destination $userRoot
    foreach ($file in @('README.md', 'LICENSE', 'CHANGELOG.md')) {
        Copy-Item -LiteralPath (Join-Path $built.sourceDirectory $file) -Destination $userRoot
    }
    # Include the archive's complete public documentation link closure. Development
    # agent rules, repository scripts and validation logs are not user payload.
    $docs = Join-Path $userRoot 'docs'
    New-Item -ItemType Directory -Path $docs | Out-Null
    foreach ($file in @('usage.md', 'matching.md', 'compatibility.md', 'testing.md', 'vm-testing.md', 'architecture.md', 'terminal-validation.md', 'performance.md', 'distribution.md')) {
        Copy-Item -LiteralPath (Join-Path $built.sourceDirectory ('docs/' + $file)) -Destination $docs
    }
    $materialRoot = Join-Path $outputRoot 'user-materials'
    & (Join-Path $PSScriptRoot 'build-license-materials.ps1') -ManifestPath (Join-Path $built.sourceDirectory 'Cargo.toml') -Scope production -Target $Target -OutputDirectory $materialRoot -ReportDirectory (Join-Path $outputRoot 'user-license-report') -CargoAbout $CargoAbout
    Copy-Item -LiteralPath (Join-Path $materialRoot 'THIRD-PARTY-NOTICES.txt') -Destination $userRoot
    Copy-Item -LiteralPath (Join-Path $materialRoot 'licenses') -Destination $userRoot -Recurse
    Assert-BundleLicenseMaterials -Root $userRoot -Scope production -Target $Target -LockSha256 $built.source.lockSha256
    # Preserve the CLI's actual inspection from the test build, with only that PE
    # entry. The user and test packages carry the identical production executable.
    $pe = Get-Content -LiteralPath (Join-Path $built.bundle.directory 'dll-imports.json') -Raw -Encoding utf8 | ConvertFrom-Json
    $cliPe = @($pe.executables | Where-Object file -ceq 'regqry.exe')
    if ($cliPe.Count -ne 1) { throw 'The production executable has no unique PE record' }
    $pe.executables = $cliPe
    New-Item -ItemType Directory -Path (Join-Path $userRoot 'pe') | Out-Null
    foreach ($log in @($cliPe[0].importsLog, $cliPe[0].headersLog)) {
        Copy-Item -LiteralPath (Join-Path $built.bundle.directory $log) -Destination (Join-Path $userRoot $log)
    }
    Write-BundleJson -Value $pe -Path (Join-Path $userRoot 'dll-imports.json')
    [IO.File]::WriteAllText((Join-Path $userRoot 'BUILD.txt'), "RegQry $($record.version)`nTarget: $Target`nUnsigned executable; no Authenticode signature.`nExtract the complete directory, then run regqry.exe --help.`nSee docs/distribution.md and THIRD-PARTY-NOTICES.txt for distribution materials.`n", [Text.UTF8Encoding]::new($false))
    $files = @(
        foreach ($item in Get-ChildItem -LiteralPath $userRoot -Recurse -File | Sort-Object FullName) {
            [ordered]@{ path = $item.FullName.Substring($userRoot.Length + 1).Replace('\', '/'); size = $item.Length; sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
        }
    )
    $manifest = [ordered]@{
        schemaVersion = 1
        kind = 'regqry-user-bundle'
        version = $record.version
        target = $Target
        source = $built.source
        compiler = $built.compiler
        cargo = $built.cargo
        rustFlags = $built.rustFlags
        environment = $built.environment
        files = $files
    }
    Write-BundleJson -Value $manifest -Path (Join-Path $userRoot 'bundle-manifest.json')
    $zip = Join-Path $outputRoot ($bundleName + '.zip')
    Write-BundleArchive -Root $userRoot -Archive $zip
    $record.user = [ordered]@{
        directory = $userRoot
        archive = $zip
        sha256 = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        manifestSha256 = (Get-FileHash -LiteralPath (Join-Path $userRoot 'bundle-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
        cliSha256 = $cliPe[0].sha256
    }
    $record.status = 'pass'
    Write-Output ('Built native user and test assets: ' + $Target)
} catch {
    $record.error = $_.Exception.Message
    throw
} finally {
    $record.finishedAtUtc = [DateTime]::UtcNow.ToString('o')
    Write-BundleJson -Value $record -Path (Join-Path $outputRoot 'build.json')
}

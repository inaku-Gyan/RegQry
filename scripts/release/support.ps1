# Release-specific identity and remote-state glue. Cargo, gh and .NET own their
# package, authentication, HTTP and archive protocols.
. (Join-Path $PSScriptRoot '../bundle/support.ps1')

function Get-ReleaseHash {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Release inputs must be regular files' }
    (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-ReleasePath {
    param([string]$Path)
    if ($Path -cnotmatch '^[a-zA-Z0-9_.-]+(/[a-zA-Z0-9_.-]+)*$' -or $Path -match '(^|/)\.\.?(/|$)') { throw ('Unsafe release path: ' + $Path) }
}

function Read-ReleaseJson {
    param([string]$Path)
    [Text.UTF8Encoding]::new($false, $true).GetString([IO.File]::ReadAllBytes((Get-Item -LiteralPath $Path).FullName)).TrimStart([char]0xfeff) | ConvertFrom-Json
}

function New-ReleaseDirectory {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $full) { throw ('Release output must be new: ' + $full) }
    New-Item -ItemType Directory -Path $full | Out-Null
    $full
}

function Get-ReleaseInventory {
    param([string]$Root)
    $full = (Get-Item -LiteralPath $Root).FullName.TrimEnd('\')
    @(foreach ($item in Get-ChildItem -LiteralPath $full -Force -Recurse | Sort-Object FullName) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Release directories must not contain reparse points' }
        if (-not $item.PSIsContainer) {
            $relative = $item.FullName.Substring($full.Length + 1).Replace('\', '/')
            Assert-ReleasePath $relative
            [ordered]@{ path = $relative; size = $item.Length; sha256 = Get-ReleaseHash $item.FullName }
        }
    })
}

function Assert-ReleaseInventory {
    param([string]$Root, [object[]]$Files, [string[]]$Exclude = @())
    $actual = @(Get-ReleaseInventory $Root | Where-Object path -cnotin $Exclude)
    if ($actual.Count -ne $Files.Count -or $Files.Count -eq 0) { throw 'Release file inventory is incomplete' }
    $seen = @{}
    foreach ($file in $Files) {
        Assert-ReleasePath $file.path
        if ($seen.ContainsKey($file.path) -or $file.sha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid or duplicate release file identity' }
        $seen[$file.path] = $true
        $match = @($actual | Where-Object path -ceq $file.path)
        if ($match.Count -ne 1 -or $match[0].size -ne $file.size -or $match[0].sha256 -cne $file.sha256) { throw ('Release file differs: ' + $file.path) }
    }
}

function Expand-ReleaseZip {
    param([string]$Archive, [string]$Destination)
    # Validate the complete namespace before extraction, including Windows case
    # collisions and directory/file aliases. No payload is ever executed here.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead((Get-Item -LiteralPath $Archive).FullName)
    $names = @{}
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName
            Assert-ReleasePath $name
            if ($names.ContainsKey($name)) { throw 'Duplicate or colliding ZIP entry' }
            $names[$name] = $true
        }
        foreach ($name in $names.Keys) {
            $parent = $name
            while ($parent.Contains('/')) {
                $parent = $parent.Substring(0, $parent.LastIndexOf('/'))
                if ($names.ContainsKey($parent)) { throw 'ZIP directory/file collision' }
            }
        }
    } finally { $zip.Dispose() }
    $root = New-ReleaseDirectory $Destination
    [IO.Compression.ZipFile]::ExtractToDirectory((Get-Item -LiteralPath $Archive).FullName, $root)
    $root
}

function Invoke-ReleaseGh {
    param([string[]]$Arguments)
    $result = @(& gh @Arguments)
    if ($LASTEXITCODE -ne 0) { throw ('GitHub operation failed; state is unknown: ' + ($Arguments | Select-Object -First 3) -join ' ') }
    $result
}

function Assert-ReleaseDraftVisibility {
    param([string]$Repository, [string]$Tag)
    # A Contents-write installation token can report permissions.push false.
    # Generate-notes requires Contents write but saves no release/tag; its text
    # is never used as release notes.
    try {
        $notes = (Invoke-ReleaseGh @('api', '--method', 'POST', "repos/$Repository/releases/generate-notes", '--raw-field', ('tag_name=' + $Tag))) -join "`n" | ConvertFrom-Json
        if ($notes -isnot [pscustomobject] -or $notes.name -isnot [string] -or [string]::IsNullOrWhiteSpace($notes.name) -or $notes.body -isnot [string]) { throw 'Unexpected generate-notes response' }
    } catch { throw ('Draft visibility requires a successful Contents write capability check; state is unknown: ' + $_.Exception.Message) }
}

function Get-ReleaseRemote {
    param([string]$Repository, [string]$Tag)
    # Listing succeeds before absence is concluded. Auth/network/404 errors never
    # turn into permission to create another release.
    $pages = (Invoke-ReleaseGh @('api', '--paginate', '--slurp', "repos/$Repository/releases?per_page=100")) -join "`n" | ConvertFrom-Json
    $found = @(foreach ($page in $pages) { foreach ($release in $page) { if ($release.tag_name -ceq $Tag) { $release } } })
    if ($found.Count -gt 1) { throw 'Multiple releases use the requested tag' }
    if ($found.Count -eq 1) {
        $release = $found[0]
        $assetPages = (Invoke-ReleaseGh @('api', '--paginate', '--slurp', "repos/$Repository/releases/$($release.id)/assets?per_page=100")) -join "`n" | ConvertFrom-Json
        $release.assets = @(foreach ($page in $assetPages) { foreach ($asset in $page) { $asset } })
        $seen = @{}
        foreach ($asset in $release.assets) {
            Assert-ReleasePath $asset.name
            if ($asset.name.Contains('/') -or $seen.ContainsKey($asset.name) -or $asset.state -cne 'uploaded' -or $asset.digest -cnotmatch '^sha256:[a-f0-9]{64}$') { throw 'Incomplete or ambiguous remote release assets' }
            $seen[$asset.name] = $true
        }
        $release
    }
}

function Assert-ReleaseImmutableSettings {
    param([string]$Repository)
    $settings = (Invoke-ReleaseGh @('api', "repos/$Repository/immutable-releases")) -join "`n" | ConvertFrom-Json
    if ($settings.enabled -ne $true) { throw 'Immutable releases must be enabled and readable before publication' }
}

function Get-ReleaseAsset {
    param([string]$Repository, [object]$Asset, [string]$Directory)
    $path = Join-Path $Directory $Asset.name
    if (Test-Path -LiteralPath $path) { throw 'Downloads must not overwrite local files' }
    # gh handles authenticated draft downloads; shell redirection would corrupt
    # binary output in Windows PowerShell 5.1.
    Invoke-ReleaseGh @('release', 'download', $script:ReleaseTag, '--repo', $Repository, '--pattern', $Asset.name, '--dir', $Directory) | Out-Null
    if ((Get-Item -LiteralPath $path).Length -ne $Asset.size -or ('sha256:' + (Get-ReleaseHash $path)) -cne $Asset.digest) { throw ('Downloaded release asset differs: ' + $Asset.name) }
    $path
}

function Sync-ReleaseAsset {
    param([string]$Repository, [string]$Tag, [string]$Path)
    $name = Split-Path -Leaf $Path
    Assert-ReleasePath $name
    $localHash = Get-ReleaseHash $Path
    $release = Get-ReleaseRemote $Repository $Tag
    if (-not $release) { throw 'Cannot attach assets without the existing release' }
    $existing = @($release.assets | Where-Object name -ceq $name)
    if ($existing.Count -eq 0) {
        if (-not $release.draft) { throw 'Cannot add missing assets to a public release' }
        # Never --clobber. An upload error may have succeeded remotely; a later
        # recovery reads actual state rather than blindly repeating it.
        Invoke-ReleaseGh @('release', 'upload', $Tag, $Path, '--repo', $Repository) | Out-Null
        $release = Get-ReleaseRemote $Repository $Tag
        $existing = @($release.assets | Where-Object name -ceq $name)
    }
    if ($existing.Count -ne 1 -or $existing[0].size -ne (Get-Item -LiteralPath $Path).Length -or $existing[0].digest -cne ('sha256:' + $localHash)) { throw ('Remote asset identity conflict: ' + $name) }
    $downloadRoot = New-ReleaseDirectory (Join-Path ([IO.Path]::GetTempPath()) ('regqry-asset-' + [guid]::NewGuid().ToString('N')))
    $script:ReleaseTag = $Tag
    Get-ReleaseAsset $Repository $existing[0] $downloadRoot | Out-Null
    [ordered]@{ name = $name; id = $existing[0].id; size = $existing[0].size; sha256 = $localHash }
}

function Get-ReleaseCheckout {
    param([string]$Root, [string]$Tag, [string]$MainRef = 'refs/remotes/origin/main')
    if ($Tag -cnotmatch '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw 'Release tag must be a stable vMAJOR.MINOR.PATCH version' }
    if ($env:GITHUB_ACTIONS -eq 'true' -and ($env:GITHUB_REF -cne ('refs/tags/' + $Tag) -or $env:GITHUB_REPOSITORY -ine 'inaku-Gyan/RegQry')) { throw 'Release workflow must run at the actual tag ref in the canonical repository' }
    Push-Location -LiteralPath $Root
    try {
        $changes = @(& git status --porcelain --untracked-files=all)
        if ($LASTEXITCODE -ne 0 -or $changes.Count -ne 0) { throw 'Release checkout must be clean' }
        $commit = & git rev-parse ($Tag + '^{commit}')
        if ($LASTEXITCODE -ne 0 -or $commit -cnotmatch '^[a-f0-9]{40}$') { throw 'Cannot resolve release tag commit' }
        $head = & git rev-parse HEAD
        if ($LASTEXITCODE -ne 0 -or $head -cne $commit) { throw 'HEAD must be the tagged commit' }
        & git merge-base --is-ancestor $commit $MainRef
        if ($LASTEXITCODE -ne 0) { throw 'Tagged commit has not been merged into main' }
        $metadata = @(& cargo +1.100.0 metadata --locked --format-version 1)
        if ($LASTEXITCODE -ne 0) { throw 'Locked Cargo metadata failed' }
        $metadata = $metadata -join "`n" | ConvertFrom-Json
        $package = @($metadata.packages | Where-Object { $_.name -ceq 'regqry' -and -not $_.source })
        if ($package.Count -ne 1 -or ('v' + $package[0].version) -cne $Tag -or $package[0].rust_version -cne '1.100.0' -or $package[0].edition -cne '2024') { throw 'Tag, Cargo version, locked graph and toolchain disagree' }
        $changelog = Get-Content -LiteralPath (Join-Path $Root 'CHANGELOG.md') -Raw -Encoding utf8
        $pattern = '(?ms)^## \[' + [regex]::Escape($package[0].version) + '\] - [0-9]{4}-[0-9]{2}-[0-9]{2}\r?\n(.+?)(?=^## |\z)'
        $entry = [regex]::Matches($changelog, $pattern)
        if ($entry.Count -ne 1 -or [string]::IsNullOrWhiteSpace($entry[0].Groups[1].Value)) { throw 'A reviewed dated CHANGELOG entry is required for this exact version' }
        [ordered]@{ tag = $Tag; version = $package[0].version; commit = $commit; lockSha256 = Get-ReleaseHash (Join-Path $Root 'Cargo.lock'); notes = $entry[0].Value.Trim(); targetDirectory = $metadata.target_directory }
    } finally { Pop-Location }
}

function Assert-ReleaseCandidate {
    param([object]$Candidate, [string]$Tag, [string]$Commit)
    if ($Candidate.schemaVersion -ne 1 -or $Candidate.kind -cne 'regqry-release-candidate' -or $Candidate.tag -cne $Tag -or $Candidate.commit -cne $Commit -or $Candidate.repository -cne 'inaku-Gyan/RegQry' -or $Candidate.repositoryId -ne 1462950131 -or ('v' + $Candidate.version) -cne $Tag -or $Candidate.lockSha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Frozen candidate identity differs from the tag/repository' }
    $expected = @('regqry-' + $Candidate.version + '.crate')
    foreach ($target in @('x86_64-pc-windows-msvc', 'aarch64-pc-windows-msvc')) {
        $expected += 'regqry-' + $Tag + '-' + $target + '.zip'
        $expected += 'regqry-' + $Tag + '-tests-' + $target + '.zip'
        $build = @($Candidate.builds | Where-Object target -ceq $target)
        if ($build.Count -ne 1 -or $build[0].status -cne 'pass' -or $build[0].scriptsDirty -or $build[0].scriptsCommit -cne $Commit -or $build[0].source.git.sha1 -cne $Commit -or $build[0].source.git.dirty -or $build[0].source.lockSha256 -cne $Candidate.lockSha256 -or $build[0].environment.nativeTarget -cne $target -or $build[0].compiler -cnotcontains 'release: 1.100.0' -or $build[0].compiler -cnotcontains ('host: ' + $target) -or $build[0].cargo -cnotmatch '^cargo 1\.100\.0 ' -or ($build[0].rustFlags -join ' ') -cne '-C target-feature=+crt-static') { throw 'Candidate requires two native clean pinned builds of the same source' }
        if (-not $build[0].toolset -or $build[0].toolset.linkerSha256 -cnotmatch '^[a-f0-9]{64}$' -or $build[0].toolset.cargoSha256 -cnotmatch '^[a-f0-9]{64}$' -or $build[0].toolset.kernel32LibrarySha256 -cnotmatch '^[a-f0-9]{64}$' -or $build[0].toolset.ucrtLibrarySha256 -cnotmatch '^[a-f0-9]{64}$' -or [string]::IsNullOrWhiteSpace($build[0].toolset.sdkVersion)) { throw 'Candidate must record its selected MSVC linker, Cargo binary and Windows SDK' }
    }
    if (@($Candidate.builds).Count -ne 2 -or @($Candidate.assets).Count -ne 5) { throw 'Candidate core asset set is incomplete' }
    $ids = @{}
    foreach ($name in $expected) {
        $asset = @($Candidate.assets | Where-Object name -ceq $name)
        if ($asset.Count -ne 1 -or $asset[0].id -le 0 -or $asset[0].size -le 0 -or $asset[0].sha256 -cnotmatch '^[a-f0-9]{64}$' -or $ids.ContainsKey([string]$asset[0].id)) { throw 'Candidate core asset identity is invalid or duplicated' }
        $ids[[string]$asset[0].id] = $true
    }
    $source = @($Candidate.assets | Where-Object name -ceq $expected[0])[0]
    foreach ($build in $Candidate.builds) {
        if ($build.source.sha256 -cne $source.sha256 -or $build.sourceFiles.Count -eq 0) { throw 'Both native builds must use the identical complete source archive' }
        foreach ($kind in @('user', 'tests')) {
            $name = if ($kind -eq 'user') { 'regqry-' + $Tag + '-' + $build.target + '.zip' } else { 'regqry-' + $Tag + '-tests-' + $build.target + '.zip' }
            $asset = @($Candidate.assets | Where-Object name -ceq $name)[0]
            if ($asset.sha256 -cne $build.$kind.sha256 -or $build.$kind.manifestSha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Candidate build and archive identities disagree' }
        }
    }
}

function Assert-ReleaseRemoteCandidate {
    param([object]$Candidate, [object]$Release)
    if (-not $Release -or $Release.id -ne $Candidate.releaseId -or $Release.tag_name -cne $Candidate.tag) { throw 'Candidate belongs to another release' }
    foreach ($asset in $Candidate.assets) {
        $remote = @($Release.assets | Where-Object name -ceq $asset.name)
        # A deleted draft attachment can be restored from the original bytes.
        # Its new server ID is trace metadata; name/size/SHA remain immutable.
        if ($remote.Count -ne 1 -or $remote[0].size -ne $asset.size -or $remote[0].digest -cne ('sha256:' + $asset.sha256)) { throw ('Frozen remote asset missing or replaced: ' + $asset.name) }
    }
}

function Invoke-ReleaseProcess {
    param([string]$Program, [string[]]$Arguments, [string]$LogPrefix, [int]$TimeoutSeconds = 1800)
    # Release commands use no shell. These project-controlled arguments need no
    # embedded quote or final backslash; reject those rather than invent quoting.
    foreach ($argument in $Arguments) { if ($argument.Contains('"') -or $argument.EndsWith('\') -or $argument.Contains("`n") -or $argument.Contains("`r")) { throw 'Unsupported release process argument' } }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Program
    $start.Arguments = (@($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' ')
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false, $true)
    $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false, $true)
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $start
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) { throw 'Cannot start release command' }
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) { $process.Kill(); $process.WaitForExit() }
        $out = $stdout.GetAwaiter().GetResult(); $err = $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText($LogPrefix + '.stdout.txt', $out, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($LogPrefix + '.stderr.txt', $err, [Text.UTF8Encoding]::new($false))
        [ordered]@{ program = $Program; arguments = $Arguments; exitCode = $process.ExitCode; timedOut = $timedOut; elapsedMs = $clock.Elapsed.TotalMilliseconds; stdout = [IO.Path]::GetFileName($LogPrefix) + '.stdout.txt'; stderr = [IO.Path]::GetFileName($LogPrefix) + '.stderr.txt' }
    } finally { $process.Dispose(); $clock.Stop() }
}

function Get-ReleaseSourceInventory {
    param([string]$Archive, [string]$Version, [string]$Directory)
    $entries = @(& tar -tf $Archive)
    if ($LASTEXITCODE -ne 0 -or $entries.Count -eq 0) { throw 'Cannot list Cargo source archive' }
    $prefix = 'regqry-' + $Version + '/'
    $seen = @{}
    foreach ($entry in $entries) {
        Assert-ReleasePath $entry
        if (-not $entry.StartsWith($prefix, [StringComparison]::Ordinal) -or $seen.ContainsKey($entry)) { throw 'Unsafe or duplicate Cargo archive member' }
        $seen[$entry] = $true
    }
    $root = New-ReleaseDirectory $Directory
    & tar -xf $Archive -C $root
    if ($LASTEXITCODE -ne 0) { throw 'Cannot extract Cargo source archive' }
    Get-ReleaseInventory (Join-Path $root ('regqry-' + $Version))
}

function Get-ReleaseHttp {
    param([string]$Url, [string]$OutFile)
    if ($Url -cnotmatch '^https://(crates\.io|index\.crates\.io|static\.crates\.io)/') { throw 'Unexpected registry URL' }
    try {
        $parameters = @{ Uri = $Url; UseBasicParsing = $true; Headers = @{ 'User-Agent' = 'RegQry release verification (https://github.com/inaku-Gyan/RegQry)' }; ErrorAction = 'Stop' }
        if ($OutFile) { $parameters.OutFile = $OutFile }
        $response = Invoke-WebRequest @parameters
        [ordered]@{ status = 200; content = $(if ($OutFile) { $null } else { [string]$response.Content }) }
    } catch {
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { return [ordered]@{ status = 404; content = $null } }
        throw 'Registry request failed; publication state is unknown'
    }
}

function Get-ReleaseRegistry {
    param([object]$Candidate, [string]$Directory)
    $index = Get-ReleaseHttp 'https://index.crates.io/re/gq/regqry'
    $api = Get-ReleaseHttp ('https://crates.io/api/v1/crates/regqry/' + $Candidate.version)
    $crate = @($Candidate.assets | Where-Object name -ceq ('regqry-' + $Candidate.version + '.crate'))[0]
    $entry = @()
    if ($index.status -eq 200) { $entry = @($index.content -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object vers -ceq $Candidate.version) }
    $record = [ordered]@{ schemaVersion = 1; status = 'unknown'; version = $Candidate.version; candidateSha256 = $crate.sha256; indexStatus = $index.status; apiStatus = $api.status; checkedAtUtc = [DateTime]::UtcNow.ToString('o'); archive = $null; files = @() }
    if ($entry.Count -eq 1 -and $api.status -eq 200) {
        $metadata = $api.content | ConvertFrom-Json
        if ($entry[0].yanked -or $entry[0].cksum -cne $crate.sha256 -or $metadata.version.num -cne $Candidate.version -or $metadata.version.checksum -cne $crate.sha256 -or $metadata.version.yanked) { throw 'Registry version/checksum conflicts with the frozen candidate; Cargo may already be public' }
        $archive = Join-Path $Directory $crate.name
        $download = Get-ReleaseHttp ('https://static.crates.io/crates/regqry/' + $crate.name) $archive
        if ($download.status -ne 200 -or (Get-ReleaseHash $archive) -cne $crate.sha256 -or (Get-Item -LiteralPath $archive).Length -ne $crate.size) { throw 'The actual registry archive differs from the frozen candidate' }
        $files = @(Get-ReleaseSourceInventory $archive $Candidate.version (Join-Path $Directory 'registry-source'))
        $sourceBuild = @($Candidate.builds | Where-Object target -ceq 'x86_64-pc-windows-msvc')[0]
        $sourceRoot = Join-Path $Directory ('registry-source/regqry-' + $Candidate.version)
        Assert-ReleaseInventory $sourceRoot @($sourceBuild.sourceFiles)
        $record.status = 'published'; $record.archive = $archive; $record.files = $files
    } elseif ($entry.Count -eq 0 -and $api.status -eq 404) {
        $package = Get-ReleaseHttp 'https://crates.io/api/v1/crates/regqry'
        if ($index.status -eq 404 -and $package.status -eq 404) { $record.status = 'bootstrap-required' }
        elseif ($index.status -eq 200 -and $package.status -eq 200) {
            $metadata = $package.content | ConvertFrom-Json
            if (@($metadata.versions | Where-Object num -ceq $Candidate.version).Count -eq 0) { $record.status = 'unpublished' }
        }
    }
    if ($record.status -ceq 'unknown') { throw 'Registry API/index disagree or are still propagating; do not retry publication' }
    Write-BundleJson $record (Join-Path $Directory 'registry.json')
    $record
}

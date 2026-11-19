[CmdletBinding()]
param([Parameter(Mandatory)][string]$Configuration)
$ErrorActionPreference = 'Stop'
$env:PSModulePath = (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/Modules') + ';' + (Join-Path $env:ProgramFiles 'WindowsPowerShell/Modules')
$config = Get-Content -LiteralPath $Configuration -Raw -Encoding utf8 | ConvertFrom-Json
if ($config.schemaVersion -ne 1) { throw 'Unsupported hosted worker configuration' }
. (Join-Path $config.library 'release/support.ps1')
# A credentialed process can inherit the caller's environment. Its temporary
# files and compiler cache must be owned by the actual query account.
$workerTemp = New-ReleaseDirectory (Join-Path $config.work 'temp')
$env:TEMP = $workerTemp; $env:TMP = $workerTemp
$env:PATH = (Join-Path $env:WINDIR 'System32') + ';' + $env:WINDIR
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$record = [ordered]@{ schemaVersion=1; kind='regqry-hosted-query-worker'; status='fail'; environment=$null; profile=$null; installation=$null; error=$null; startedAtUtc=[DateTime]::UtcNow.ToString('o') }
try {
    $record.environment = Get-BundleEnvironment
    if ($record.environment.elevated) { throw 'Hosted query worker must have a non-elevated token' }
    if ((Get-FileHash -LiteralPath (Join-Path $config.bundle 'bundle-manifest.json')).Hash.ToLowerInvariant() -cne $config.manifestSha256) { throw 'Hosted worker bundle identity changed' }
    $record.profile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    $userHive = [Microsoft.Win32.Registry]::Users.OpenSubKey($record.environment.userSid)
    if (-not $userHive) { throw 'The query profile must remain loaded under its actual SID' }
    try {
        $software = $userHive.OpenSubKey('Software')
        $classes = $userHive.OpenSubKey('Software\Classes')
        try { if (-not $software -or -not $classes) { throw 'Query profile Software and Software\Classes must be initialized before fixture preparation' } }
        finally { if ($classes) { $classes.Dispose() }; if ($software) { $software.Dispose() } }
        # The process and this handle remain alive across the administrator's
        # preparation, so HKU/HKCU never fall back to the runner's profile.
        Write-BundleJson ([ordered]@{status='ready';environment=$record.environment;profile=$record.profile;userHiveLoaded=$true;classesReady=$true}) ($config.ready + '.tmp')
        [IO.File]::Move(($config.ready + '.tmp'), $config.ready)
        $waiting = [Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Path -LiteralPath $config.start)) {
            if ($waiting.Elapsed.TotalSeconds -ge 900) { throw 'Administrator preparation handshake timed out' }
            Start-Sleep -Milliseconds 200
        }
        $signal = Get-Content -LiteralPath $config.start -Raw -Encoding utf8 | ConvertFrom-Json
        if ($signal.status -cne 'prepared' -or (Get-FileHash -LiteralPath $config.context).Hash.ToLowerInvariant() -cne $signal.contextSha256) { throw 'Prepared fixture context identity changed' }
        $env:PATH = (Join-Path $env:WINDIR 'System32') + ';' + $env:WINDIR
        & (Join-Path $config.bundle 'run-vm-tests.ps1') -Phase Query -DisposableVm -ContextPath $config.context -PowerShell7 $config.powerShell7 -ExpectedManifestSha256 $config.manifestSha256 -ReportDirectory (Join-Path $config.reports 'query-bundle')
        $query = Get-Content -LiteralPath (Join-Path $config.reports 'query-bundle/result.json') -Raw -Encoding utf8 | ConvertFrom-Json
        if ($query.status -cne 'pass' -or $query.environment.elevated -or $query.environment.userSid -cne $record.environment.userSid -or $query.globalHarnessesStarted -ne 6) { throw 'Hosted query suite did not complete under the expected ordinary identity' }
        $env:CARGO_HOME = New-ReleaseDirectory (Join-Path $config.work 'cargo-home')
        $env:CARGO_TARGET_DIR = New-ReleaseDirectory (Join-Path $config.work 'cargo-target')
        $env:RUSTC = $config.compiler
        $env:PATH = (Split-Path -Parent $config.compiler) + ';' + (Join-Path $env:WINDIR 'System32') + ';' + $env:WINDIR
        foreach ($name in @('CARGO_ENCODED_RUSTFLAGS','RUSTFLAGS','RUSTC_WRAPPER','RUSTC_WORKSPACE_WRAPPER','GH_TOKEN','GITHUB_TOKEN','CARGO_REGISTRY_TOKEN','CARGO_REGISTRIES_CRATES_IO_TOKEN')) {
            Remove-Item -LiteralPath ('Env:\' + $name) -ErrorAction SilentlyContinue
        }
        $compiler = @(& $config.compiler -Vv)
        if ($LASTEXITCODE -ne 0 -or $compiler -cnotcontains 'release: 1.100.0' -or $compiler -cnotcontains ('host: ' + $config.target)) { throw 'Installation compiler must be the native Rust 1.100.0 toolchain' }
        if ((Get-ReleaseHash $config.archive) -cne $config.sourceSha256) { throw 'Original Cargo archive changed before installation' }
        $installRoot = Join-Path $config.work 'installed'
        $arguments = @('install','--locked','--root',$installRoot,'--target',$config.target,'--target-dir',$env:CARGO_TARGET_DIR)
        $arguments += if ($config.registryInstall) { @('regqry','--version',('=' + $config.version)) } else { @('--path',$config.source) }
        $installation = Invoke-ReleaseProcess $config.cargo $arguments (Join-Path $config.reports 'installation') 1800
        if ($installation.timedOut -or $installation.exitCode -ne 0) { throw 'Ordinary-user Cargo installation failed' }
        $registryArchiveSha256 = $null
        if ($config.registryInstall) {
            $archives = @(Get-ChildItem -LiteralPath (Join-Path $env:CARGO_HOME 'registry/cache') -Recurse -File -Filter ('regqry-' + $config.version + '.crate'))
            if ($archives.Count -ne 1 -or (Get-ReleaseHash $archives[0].FullName) -cne $config.sourceSha256) { throw 'The actual registry Cargo archive differs from the candidate bytes' }
            $registryArchiveSha256 = Get-ReleaseHash $archives[0].FullName
        }
        $installedCli = Join-Path $installRoot 'bin/regqry.exe'
        $record.installation = [ordered]@{ status='pass'; origin=$(if ($config.registryInstall) { 'registry' } else { 'source-archive' }); sourceSha256=$config.sourceSha256; registryArchiveSha256=$registryArchiveSha256; compiler=$compiler; compilerSha256=(Get-ReleaseHash $config.compiler); cargoSha256=(Get-ReleaseHash $config.cargo); cliSha256=(Get-ReleaseHash $installedCli); command=$installation }
        $env:PATH = (Join-Path $env:WINDIR 'System32') + ';' + $env:WINDIR
        & (Join-Path $config.bundle 'run-vm-tests.ps1') -Phase Query -DisposableVm -ContextPath $config.context -PowerShell7 $config.powerShell7 -ExpectedManifestSha256 $config.manifestSha256 -CliPath $installedCli -ReportDirectory (Join-Path $config.reports 'query-installed')
        $installedQuery = Read-ReleaseJson (Join-Path $config.reports 'query-installed/result.json')
        if ($installedQuery.status -cne 'pass' -or $installedQuery.environment.elevated -or $installedQuery.environment.userSid -cne $record.environment.userSid -or $installedQuery.globalHarnessesStarted -ne 6 -or $installedQuery.cli.sha256 -cne $record.installation.cliSha256) { throw 'The installed CLI did not pass the owned fixture suite under the ordinary identity' }
        $record.status = 'pass'
    } finally { $userHive.Dispose() }
} catch { $record.error = $_.Exception.Message; throw }
finally { $record.finishedAtUtc=[DateTime]::UtcNow.ToString('o'); Write-BundleJson $record (Join-Path $config.reports 'worker-result.json') }

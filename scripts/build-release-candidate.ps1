[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceArchive,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][ValidateSet('x86_64-pc-windows-msvc', 'aarch64-pc-windows-msvc')][string]$Target,
    [string]$CargoAbout
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release/support.ps1')
$native = Get-BundleEnvironment
if ($native.nativeTarget -cne $Target) { throw 'A release candidate must be built on its native architecture' }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$component = if ($Target -ceq 'aarch64-pc-windows-msvc') { 'Microsoft.VisualStudio.Component.VC.Tools.ARM64' } else { 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64' }
$install = @(& $vswhere -latest -products '*' -requires $component -property installationPath)
if ($LASTEXITCODE -ne 0 -or $install.Count -ne 1) { throw 'Cannot find the installed native MSVC toolchain' }
$vcvars = Join-Path $install[0] 'VC/Auxiliary/Build/vcvarsall.bat'
if (-not (Test-Path -LiteralPath $vcvars) -or $vcvars.Contains('"')) { throw 'Cannot identify vcvarsall.bat' }
$arch = if ($Target -ceq 'x86_64-pc-windows-msvc') { 'x64' } else { 'arm64' }
$saved = @{}
$names = @('PATH', 'INCLUDE', 'LIB', 'LIBPATH', 'VCToolsInstallDir', 'VCToolsVersion', 'WindowsSdkDir', 'WindowsSDKVersion', 'UCRTVersion', 'UniversalCRTSdkDir', 'CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER', 'CARGO_TARGET_AARCH64_PC_WINDOWS_MSVC_LINKER')
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    # Capture, but never print, inherited environment output. Only the explicit
    # tool variables below are adopted or recorded; credentials are not logged.
    # Pass cmd its command line directly. PowerShell 5.1's native marshalling
    # otherwise adds another quote layer around a spaced vcvarsall path. /u
    # makes the internal `set` output UTF-16 regardless of the current code page.
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $env:WINDIR 'System32/cmd.exe'
    $start.Arguments = '/d /u /s /c ""' + $vcvars.Replace('/', '\') + '" ' + $arch + ' >nul && set"'
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::Unicode
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'Cannot start native MSVC environment selection' }
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) { $process.Kill(); $process.WaitForExit(); throw 'Native MSVC environment selection timed out' }
        $captured = $stdout.GetAwaiter().GetResult(); $stderr.GetAwaiter().GetResult() | Out-Null
        if ($process.ExitCode -ne 0) { throw 'Native MSVC environment initialization failed' }
        $lines = @($captured -split "`r?`n")
    } finally { $process.Dispose() }
    foreach ($line in $lines) {
        $pair = $line -split '=', 2
        if ($pair.Count -eq 2 -and $pair[0] -in $names) { [Environment]::SetEnvironmentVariable($pair[0], $pair[1], 'Process') }
    }
    $hostName = if ($arch -ceq 'x64') { 'Hostx64' } else { 'Hostarm64' }
    $linker = Join-Path $env:VCToolsInstallDir ('bin/' + $hostName + '/' + $arch + '/link.exe')
    $dumpbin = Join-Path (Split-Path -Parent $linker) 'dumpbin.exe'
    $sdkVersion = $env:WindowsSDKVersion.TrimEnd('\')
    $sdkLib = Join-Path $env:WindowsSdkDir ('Lib/' + $sdkVersion + '/um/' + $arch + '/kernel32.lib')
    $ucrtLib = Join-Path $env:WindowsSdkDir ('Lib/' + $env:UCRTVersion + '/ucrt/' + $arch + '/libucrt.lib')
    $toolset = [ordered]@{
        visualStudio = $install[0]; vcToolsVersion = $env:VCToolsVersion
        linker = $linker; linkerVersion = (Get-Item -LiteralPath $linker).VersionInfo.FileVersion; linkerSha256 = Get-ReleaseHash $linker
        sdkDirectory = $env:WindowsSdkDir; sdkVersion = $sdkVersion; ucrtVersion = $env:UCRTVersion
        kernel32Library = $sdkLib; kernel32LibrarySha256 = Get-ReleaseHash $sdkLib
        ucrtStaticLibrary = $ucrtLib; ucrtLibrarySha256 = Get-ReleaseHash $ucrtLib
        librarySearch = $env:LIB; includeSearch = $env:INCLUDE
    }
    $cargoPath = & rustup which --toolchain ('1.100.0-' + $Target) cargo
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify the actual pinned Cargo binary' }
    $toolset.cargoSha256 = Get-ReleaseHash $cargoPath
    $linkerVariable = 'CARGO_TARGET_' + $Target.ToUpperInvariant().Replace('-', '_') + '_LINKER'
    [Environment]::SetEnvironmentVariable($linkerVariable, $linker, 'Process')
    & (Join-Path $PSScriptRoot 'build-release-assets.ps1') -SourceArchive $SourceArchive -OutputDirectory $OutputDirectory -Target $Target -Dumpbin $dumpbin -CargoAbout $CargoAbout
    $reportPath = Join-Path $OutputDirectory 'build.json'
    $report = Read-ReleaseJson $reportPath
    $report | Add-Member -NotePropertyName toolset -NotePropertyValue $toolset
    Write-BundleJson $report $reportPath
} finally { Restore-BundleEnvironment $saved }

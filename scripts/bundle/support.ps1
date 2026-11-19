# Shared by the build-machine check and the portable, Cargo-free test runner.
function Write-BundleJson {
    param([object]$Value, [string]$Path)
    $json = $Value | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
}

function Restore-BundleEnvironment {
    param([hashtable]$Saved)
    foreach ($name in $Saved.Keys) {
        # PowerShell/.NET now distinguish an absent variable from an empty one.
        # Passing $null to the string overload can instead create an empty value.
        if ($null -eq $Saved[$name]) {
            Remove-Item -LiteralPath ('Env:\' + $name) -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($name, [string]$Saved[$name], 'Process')
        }
    }
}

function Invoke-BundleProcess {
    param([string]$Program, [string[]]$Arguments, [int]$TimeoutSeconds = 120)
    # All callers pass fixed harness switches, not shell command strings.
    foreach ($argument in $Arguments) {
        if ($argument -notmatch '^[a-zA-Z0-9_=:.-]+$') { throw 'Unsupported harness argument' }
    }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Program
    $start.Arguments = $Arguments -join ' '
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false, $true)
    $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false, $true)
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) { throw ('Cannot start ' + $Program) }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) { $process.Kill(); $process.WaitForExit() }
        [ordered]@{
            arguments = $Arguments
            exitCode = $process.ExitCode
            timedOut = $timedOut
            elapsedMs = $clock.Elapsed.TotalMilliseconds
            stdout = $stdout.GetAwaiter().GetResult()
            stderr = $stderr.GetAwaiter().GetResult()
        }
    } finally { $process.Dispose(); $clock.Stop() }
}

function Get-BundleEnvironment {
    if (-not ('RegQryBundleNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class RegQryBundleNative {
    [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool IsWow64Process2(IntPtr process, out ushort machine, out ushort nativeMachine);
    [DllImport("advapi32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool GetTokenInformation(IntPtr token, int kind, out uint value, uint size, out uint returned);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct VersionInfo {
        public uint size, major, minor, build, platform;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string servicePack;
        public ushort servicePackMajor, servicePackMinor, suite;
        public byte productType, reserved;
    }
    [DllImport("ntdll.dll", CharSet=CharSet.Unicode)]
    static extern int RtlGetVersion(ref VersionInfo info);
    public static VersionInfo Version() {
        var info = new VersionInfo();
        info.size = (uint)Marshal.SizeOf(info);
        int status = RtlGetVersion(ref info);
        if (status != 0) throw new InvalidOperationException("RtlGetVersion: " + status);
        return info;
    }
    public static bool Elevated() {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), 8, out token))
            throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            uint value, returned;
            if (!GetTokenInformation(token, 20, out value, 4, out returned))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            return value != 0;
        } finally { CloseHandle(token); }
    }
}
'@
    }
    [uint16]$processMachine = 0
    [uint16]$nativeMachine = 0
    if (-not [RegQryBundleNative]::IsWow64Process2([RegQryBundleNative]::GetCurrentProcess(), [ref]$processMachine, [ref]$nativeMachine)) {
        throw 'Cannot determine native Windows architecture'
    }
    $nativeTarget = switch ($nativeMachine) {
        0x8664 { 'x86_64-pc-windows-msvc' }
        0xAA64 { 'aarch64-pc-windows-msvc' }
        default { throw ('Unsupported native machine: ' + $nativeMachine) }
    }
    $version = [RegQryBundleNative]::Version()
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        [ordered]@{
            osVersion = ('{0}.{1}.{2}' -f $version.major, $version.minor, $version.build)
            osProductType = $version.productType
            nativeTarget = $nativeTarget
            nativeMachine = $nativeMachine
            runnerProcessMachine = $processMachine
            runnerIs64Bit = [Environment]::Is64BitProcess
            elevated = [RegQryBundleNative]::Elevated()
            userSid = $identity.User.Value
            powerShell = $PSVersionTable.PSVersion.ToString()
            cargoOnPath = [bool](Get-Command cargo -ErrorAction SilentlyContinue)
            rustcOnPath = [bool](Get-Command rustc -ErrorAction SilentlyContinue)
        }
    } finally { $identity.Dispose() }
}

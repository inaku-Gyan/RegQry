# Compatibility and shells

The formal acceptance targets are native `x86_64-pc-windows-msvc` on Windows 10 22H2 / Windows 11 stable clients, and native `aarch64-pc-windows-msvc` on Windows 11 24H2 or later stable clients. Both ZIP and Cargo channels share these OS targets. Windows Server, x86 executables, GNU ABI, and cross-architecture emulation are outside the initial formal matrix.

These are commitments to validate before release, not claims that this development build passed the matrix. Hosted x64 Server and ARM64 newer Windows records do not replace minimum-client tests. Non-Windows compilation deliberately fails with an English Windows-only message.

Both native architectures must verify 32/64 logical registry views. On ARM64, the 32-bit promise is the x86 view; the 64-bit view is native ARM64. View selection is independent of executable bitness and does not change the CLI process environment used by expansion.

Planned ZIP packages explicitly use static MSVC CRT, undergo final DLL checks, and run on clean minimum systems without Rust, Build Tools, or an extra runtime installation. Those packages are not yet available. Cargo installation requires the fixed Rust version or a newer accepted compiler, native MSVC C++ tools, and a Windows SDK; only Rust 1.100.0 is tested. Registry-source installation does not inherit repository-only Cargo configuration.

Supported shell targets are cmd, Windows PowerShell 5.1, and PowerShell 7, in the classic console and optional Windows Terminal. The program uses fixed UTF-8 and does not change the host's profile, code page, or persistent settings.

System-error diagnostics request US English explicitly and retain the Win32 numeric code. If that English message is unavailable, a fixed English fallback accompanies the code rather than switching to the host's language.

For PowerShell object capture, explicitly configure the current process and restore its settings:

```powershell
$savedConsole = [Console]::OutputEncoding
$savedOutput = $OutputEncoding
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $lines = & regqry --help
    $queryStatus = $LASTEXITCODE
    $lines | Out-File -FilePath help.txt -Encoding utf8
} finally {
    [Console]::OutputEncoding = $savedConsole
    $OutputEncoding = $savedOutput
}
```

Windows PowerShell 5.1 `>` writes UTF-16LE even when decoding was configured correctly; `Out-File -Encoding utf8` writes UTF-8 with a BOM. Its stderr redirection can add PowerShell error formatting. Capture `$LASTEXITCODE` immediately. For original program bytes, use cmd directly, for example `regqry --help > help.txt`. Do not assume every PowerShell version/pipeline preserves native bytes.

PowerShell single quotes preserve ordinary backslashes and prevent expansion of `%NAME%` by PowerShell itself. In cmd, single quotes are literal and percent expansion differs. Use the relevant shell's quoting rules, especially for embedded quotes, empty arguments, and trailing backslashes. `--option=value` binds an option value but cannot recover text already changed by the shell. Display escapes are not an additional CLI input language.

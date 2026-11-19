# Compatibility and shells

The formal acceptance targets are native `x86_64-pc-windows-msvc` on Windows 10 22H2 / Windows 11 stable clients, and native `aarch64-pc-windows-msvc` on Windows 11 24H2 or later stable clients. Both ZIP and Cargo channels share these OS targets. Windows Server, x86 executables, GNU ABI, and cross-architecture emulation are outside the initial formal matrix.

These are commitments to validate before release, not claims that this development build passed the matrix. Hosted x64 Server and ARM64 newer Windows records do not replace minimum-client tests. Non-Windows compilation deliberately fails with an English Windows-only message.

Both native architectures must verify 32/64 logical registry views. On ARM64, the 32-bit promise is the x86 view; the 64-bit view is native ARM64. View selection is independent of executable bitness and does not change the CLI process environment used by expansion.

The native asset builder explicitly uses static MSVC CRT and checks all executable DLL imports. User and test ZIPs share the identical production CLI and carry their own production/test license graphs. They must still run on clean minimum systems without Rust, Build Tools, or an extra runtime installation; released user packages are not yet available. Cargo installation requires the fixed Rust version or a newer accepted compiler, native MSVC C++ tools, and a Windows SDK; only Rust 1.100.0 is tested. Registry-source installation does not inherit repository-only Cargo configuration.

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

For portable examples, bind an empty pattern as `--name=` and a leading hyphen as `--data=-legacy`. A literal double quote can be expressed using the regex library's `\x22`, such as `--name '^Quote\x22Name$'` in PowerShell or `--name "^Quote\x22Name$"` in cmd. This avoids differences in native quote marshalling between Windows PowerShell and newer PowerShell versions. Regex backslashes are still interpreted by the regex engine: matching a saved `A\B` requires `^A\\B$`.

In a cmd batch file, double literal percent signs: `--data "%%NAME%%"` passes the regex `%NAME%`. PowerShell uses `--data '%NAME%'`. These are shell-specific spellings, not new CLI expansion behavior. For a cmd double-quoted ROOT ending in a backslash, double that final backslash before the closing quote, for example `--key-root "HKCU\Software\\"`; omitting the optional final separator is simpler.

The shell harness writes UTF-8/BOM PowerShell scripts for Windows PowerShell 5.1 and uses UTF-8 batch input inside its own console. It checks raw cmd streams, explicitly decoded PowerShell string capture, `Out-File -Encoding utf8`, and `>` separately. Windows PowerShell 5.1's nonempty `>` output is UTF-16LE/BOM; its UTF-8 Out-File has a BOM. PowerShell 7.4+ native stdout redirection must preserve the original bytes; older PowerShell 7 is checked as decoded UTF-8 text. Stderr formatting is checked for retained diagnostics rather than byte equality. See [Microsoft encoding guidance](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding) and [native redirection](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_redirection). Actual query/shell and [manual terminal acceptance](terminal-validation.md) remain distinct from the ordinary no-query tests.

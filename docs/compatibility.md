# Compatibility and shells

The compatibility targets are native `x86_64-pc-windows-msvc` on Windows 10 22H2 / Windows 11 stable clients, and native `aarch64-pc-windows-msvc` on Windows 11 24H2 or later stable clients. Both ZIP and Cargo channels share these targets. x86 executables, GNU ABI and cross-architecture emulation are outside the initial matrix. Non-Windows compilation deliberately fails with an English Windows-only message.

Automated acceptance uses the available standard GitHub-hosted native x64 Windows Server and ARM64 Windows 11 images, with their actual OS/image versions recorded. The minimum client versions, x64 Windows 11 client and Windows installations without developer tools are not directly exercised and are not first-release gates. Compatibility targets describe intended use; the validation records identify the environments actually tested.

Both native architectures must verify 32/64 logical registry views. On ARM64, the 32-bit promise is the x86 view; the 64-bit view is native ARM64. View selection is independent of executable bitness and does not change the CLI process environment used by expansion.

The native asset builder explicitly uses static MSVC CRT and checks all executable DLL imports. User and test ZIPs share the identical production CLI and carry their own production/test license graphs. Relocated execution with Rust/Cargo removed from PATH verifies the carried files; the hosted machine still contains development tools. Released user packages are not yet available. Cargo installation requires the fixed Rust version or a newer accepted compiler, native MSVC C++ tools, and a Windows SDK; only Rust 1.100.0 is tested. Registry-source installation does not inherit repository-only Cargo configuration.

Shell targets are cmd, Windows PowerShell 5.1 and PowerShell 7. Automated checks capture actual UTF-8/output/exit behavior and deliver real console control events. Human-visible classic-console/Windows-Terminal layout at 80/120 columns and physical-keyboard Ctrl+C are deferred. The program uses fixed UTF-8 and does not change the host's profile, code page or persistent settings. See the [hosted acceptance contract](https://github.com/inaku-Gyan/RegQry/blob/main/docs/hosted-acceptance.md).

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

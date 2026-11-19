//! Actual shell parsing and encoding, separate from manual terminal acceptance.
use super::{child, machine_path, processes, text};
use crate::support::vm::{Context, assert_marker, set};
use std::{
    ffi::OsStr,
    fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::Duration,
};
use windows_sys::Win32::System::Console::{GetConsoleCP, GetConsoleOutputCP};
use windows_sys::Win32::System::Registry::{
    KEY_QUERY_VALUE, KEY_WOW64_64KEY, REG_EXPAND_SZ, REG_OPTION_OPEN_LINK,
};
use winreg::RegKey;

pub(super) fn prepare(root: &RegKey, context: &Context) {
    let shell = child(root, "Shell 空间", KEY_WOW64_64KEY, context, 9);
    let leaf = child(&shell, "节点 空间", KEY_WOW64_64KEY, context, 9);
    text(&leaf, r"A\B", r"C:\Program Files\节点\bin\");
    text(&leaf, "", "");
    text(&leaf, "-legacy", "literal %REGQRY_SHELL_SENTINEL% $HOME");
    text(&leaf, "Quote\"Name", "say \"hello\"");
    let expand = "%REGQRY_SHELL_SENTINEL%\0"
        .encode_utf16()
        .flat_map(u16::to_le_bytes)
        .collect::<Vec<_>>();
    set(&leaf, OsStr::new("Env"), REG_EXPAND_SZ, &expand);
}

struct Case {
    name: &'static str,
    args: Vec<String>,
    cmd: String,
    ps: String,
    code: i32,
    query: bool,
}
fn case(name: &'static str, args: &[&str], cmd: &'static str, ps: &'static str, code: i32) -> Case {
    Case {
        name,
        args: args.iter().map(|s| (*s).into()).collect(),
        cmd: cmd.into(),
        ps: ps.into(),
        code,
        query: false,
    }
}
fn cases(root: Option<&str>, denied: &str) -> Vec<Case> {
    let mut cases = vec![
        case("bare", &[], "", "", 0),
        case("short-help", &["-h"], "-h", "-h", 0),
        case("long-help", &["--help"], "--help", "--help", 0),
        case("version", &["-V"], "-V", "-V", 0),
        case(
            "unicode-error",
            &["--name=[节点"],
            "--name=\"[节点\"",
            "'--name=[节点'",
            2,
        ),
        // Bound empty/leading-dash arguments survive even Windows PowerShell's
        // legacy native argument marshalling. Invalid ROOT prevents any query.
        case(
            "empty-bound",
            &["--name=", "--key-root=HKCU:"],
            "--name= --key-root=HKCU:",
            "--name= --key-root=HKCU:",
            2,
        ),
        case(
            "dash-bound",
            &["--data=-legacy", "--key-root=HKCU:"],
            "--data=-legacy --key-root=HKCU:",
            "--data=-legacy --key-root=HKCU:",
            2,
        ),
        case(
            "percent-literal",
            &["--data=[%REGQRY_SHELL_SENTINEL%"],
            "--data=\"[%%REGQRY_SHELL_SENTINEL%%\"",
            "'--data=[%REGQRY_SHELL_SENTINEL%'",
            2,
        ),
    ];
    if let Some(root) = root {
        for mut item in [
            case(
                "unicode-path",
                &[
                    "--key",
                    "^节点 空间$",
                    "--name",
                    r"^A\\B$",
                    "--data",
                    r"^C:\\Program Files\\节点\\bin\\$",
                ],
                "--key \"^节点 空间$\" --name \"^A\\\\B$\" --data \"^C:\\\\Program Files\\\\节点\\\\bin\\\\$\"",
                "--key '^节点 空间$' --name '^A\\\\B$' --data '^C:\\\\Program Files\\\\节点\\\\bin\\\\$'",
                0,
            ),
            case(
                "default-name",
                &["--name=^$"],
                r#"--name="^$""#,
                "'--name=^$'",
                0,
            ),
            case(
                "empty-query-pattern",
                &["--name=", "-t", "sz"],
                "--name= -t sz",
                "--name= -t sz",
                0,
            ),
            case(
                "literal-data",
                &[
                    "--name=-legacy",
                    "--data",
                    r"^literal %REGQRY_SHELL_SENTINEL% \$HOME$",
                ],
                "--name=-legacy --data \"^literal %%REGQRY_SHELL_SENTINEL%% \\$HOME$\"",
                "--name=-legacy --data '^literal %REGQRY_SHELL_SENTINEL% \\$HOME$'",
                0,
            ),
            case(
                "quoted-name",
                &["--name", r"^Quote\x22Name$"],
                "--name \"^Quote\\x22Name$\"",
                "--name '^Quote\\x22Name$'",
                0,
            ),
            case(
                "expanded",
                &["--name=^Env$", "--data-expand=^expanded-节点$"],
                r#"--name="^Env$" --data-expand="^expanded-节点$""#,
                "'--name=^Env$' '--data-expand=^expanded-节点$'",
                0,
            ),
            case(
                "quiet",
                &["--name=^not-present$"],
                r#"--name="^not-present$""#,
                "'--name=^not-present$'",
                1,
            ),
            case(
                "partial",
                &["--key-root", denied, "--name", r"^A\\B$"],
                "--key-root \"%REGQRY_SHELL_DENIED%\" --name \"^A\\\\B$\"",
                "--key-root $env:REGQRY_SHELL_DENIED --name '^A\\\\B$'",
                2,
            ),
        ] {
            // Each root has a space and a final backslash. The batch spelling
            // doubles the final slash before the native closing quote.
            let mut args = vec!["--key-root".into(), format!("{root}\\"), "--view=64".into()];
            args.append(&mut item.args);
            item.args = args;
            item.query = true;
            cases.push(item);
        }
    }
    cases
}

fn pwsh() -> Option<PathBuf> {
    if let Some(path) = std::env::var_os("REGQRY_TEST_PWSH") {
        let path = PathBuf::from(path);
        assert!(
            path.is_absolute() && path.is_file(),
            "REGQRY_TEST_PWSH must name an installed absolute pwsh.exe"
        );
        assert!(
            path.file_name()
                .and_then(OsStr::to_str)
                .is_some_and(|name| name.eq_ignore_ascii_case("pwsh.exe")),
            "REGQRY_TEST_PWSH must name pwsh.exe"
        );
        return Some(path);
    }
    let mut candidates = vec![
        PathBuf::from(std::env::var_os("ProgramFiles").unwrap()).join(r"PowerShell\7\pwsh.exe"),
    ];
    if let Some(path) = std::env::var_os("PATH") {
        candidates.extend(std::env::split_paths(&path).map(|dir| dir.join("pwsh.exe")));
    }
    candidates
        .into_iter()
        .find(|path| path.is_absolute() && path.is_file())
}
fn lf(text: &str) -> String {
    text.replace("\r\n", "\n")
}
fn decoded(bytes: &[u8]) -> String {
    if let Some(bytes) = bytes.strip_prefix(&[0xff, 0xfe]) {
        assert_eq!(bytes.len() % 2, 0);
        String::from_utf16(
            &bytes
                .as_chunks::<2>()
                .0
                .iter()
                .map(|b| u16::from_le_bytes(*b))
                .collect::<Vec<_>>(),
        )
        .unwrap()
    } else {
        String::from_utf8(
            bytes
                .strip_prefix(&[0xef, 0xbb, 0xbf])
                .unwrap_or(bytes)
                .to_vec(),
        )
        .unwrap()
    }
}
fn save_script(path: &Path, text: &str, bom: bool) {
    let mut bytes = if bom {
        vec![0xef, 0xbb, 0xbf]
    } else {
        Vec::new()
    };
    bytes.extend_from_slice(text.replace('\n', "\r\n").as_bytes());
    fs::write(path, bytes).unwrap();
}
fn scripts(directory: &Path, cases: &[Case]) {
    let mut batch = String::from(
        "@echo off\nsetlocal DisableDelayedExpansion\nchcp 65001 >codepage.txt\nif errorlevel 1 exit /b 3\nver >version.txt\n",
    );
    let mut ps = String::from(
        r#"$ErrorActionPreference = 'Continue'
$savedConsole = [Console]::OutputEncoding
$savedOutput = $OutputEncoding
try {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Text.UTF8Encoding]::new($false)
    $PSNativeCommandUseErrorActionPreference = $false
    $PSStyle.OutputRendering = 'PlainText'
    $queryRoot = $env:REGQRY_SHELL_ROOT + '\'
    if ($PSVersionTable.PSVersion.Major -le 5 -and $queryRoot.Contains(' ')) {
        $queryRoot += '\'
    }
"#,
    );
    // PS5 has no PSStyle; guard it rather than producing an unrelated diagnostic.
    ps = ps.replace("    $PSStyle.OutputRendering = 'PlainText'", "    if (Get-Variable PSStyle -ErrorAction SilentlyContinue) { $PSStyle.OutputRendering = 'PlainText' }");
    ps.push_str("    [IO.File]::WriteAllText('version.txt', $PSVersionTable.PSVersion.ToString(), [Text.UTF8Encoding]::new($false))\n");
    for item in cases {
        let prefix_cmd = if item.query {
            r#"--key-root "%REGQRY_SHELL_ROOT%\\" --view=64 "#
        } else {
            ""
        };
        let prefix_ps = if !prefix_cmd.is_empty() {
            "--key-root $queryRoot --view=64 "
        } else {
            ""
        };
        batch.push_str(&format!("\"%REGQRY_SHELL_BIN%\" {prefix_cmd}{} >{}.stdout 2>{}.stderr\n>{}.exit echo %errorlevel%\n", item.cmd, item.name, item.name, item.name));
        ps.push_str(&format!(r#"    $lines = @(& $env:REGQRY_SHELL_BIN {prefix_ps}{args} 2> {name}.capture.stderr)
    $code = $LASTEXITCODE
    [IO.File]::WriteAllText('{name}.capture.exit', [string]$code, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllLines('{name}.capture', [string[]]$lines, [Text.UTF8Encoding]::new($false, $true))
    $lines | Out-File -FilePath {name}.outfile -Encoding utf8 -Width 32767
    & $env:REGQRY_SHELL_BIN {prefix_ps}{args} > {name}.redirect 2> {name}.redirect.stderr
    $code = $LASTEXITCODE
    [IO.File]::WriteAllText('{name}.redirect.exit', [string]$code, [Text.UTF8Encoding]::new($false))
"#, args = item.ps, name = item.name));
    }
    batch.push_str("exit /b 0\n");
    ps.push_str("} finally {\n    [Console]::OutputEncoding = $savedConsole\n    $OutputEncoding = $savedOutput\n}\nexit 0\n");
    save_script(&directory.join("run.cmd"), &batch, false);
    save_script(&directory.join("run.ps1"), &ps, true);
}

pub(super) fn checks(directory: &Path, query: bool) -> String {
    let context = query.then(|| Context::require("query"));
    let root = context.as_ref().map(|context| {
        let parent = context.machine(KEY_WOW64_64KEY);
        let key = parent
            .open_subkey_with_options_flags(
                "Shell 空间",
                REG_OPTION_OPEN_LINK,
                KEY_QUERY_VALUE | KEY_WOW64_64KEY,
            )
            .unwrap();
        assert_marker(&key, &context.nonce);
        machine_path(context, "Shell 空间")
    });
    let root = root.unwrap_or_else(|| r"HKLM\Software\RegQryShellSyntax_空间".into());
    let denied = context
        .as_ref()
        .map(|context| machine_path(context, "Acl\\Denied"))
        .unwrap_or_else(|| format!(r"{root}\Denied"));
    let mut cases = cases(Some(&root), &denied);
    if !query {
        for item in cases.iter_mut().filter(|item| item.query) {
            // Exercise every VM command's shell syntax, but force the already
            // tested all-options validation path to reject before registry I/O.
            item.args.push("--key-root=HKCU:".into());
            item.cmd.push_str(" --key-root=HKCU:");
            item.ps.push_str(" --key-root=HKCU:");
            item.code = 2;
        }
    }
    let bin = crate::support::cli::binary();
    assert!(bin.is_absolute() && bin.is_file());
    let windows = PathBuf::from(std::env::var_os("SystemRoot").unwrap());
    let ps5 = windows.join(r"System32\WindowsPowerShell\v1.0\powershell.exe");
    let mut shells = vec![
        ("cmd", windows.join(r"System32\cmd.exe")),
        ("powershell", ps5.clone()),
    ];
    let mut record =
        format!("SHELL_CHECKS actual_cli={bin:?} vm_query={query} manual_terminal=not-run\n");
    if let Some(pwsh) = pwsh() {
        shells.push(("pwsh", pwsh));
    } else {
        assert!(
            !query,
            "VM shell acceptance requires installed PowerShell 7; set REGQRY_TEST_PWSH to its absolute path"
        );
        record.push_str("SHELL pwsh status=not-run reason=not-installed-or-not-located\n");
    }
    let references = cases
        .iter()
        .map(|item| {
            let output = Command::new(&bin)
                .args(&item.args)
                .env("REGQRY_SHELL_SENTINEL", "expanded-节点")
                .stdin(Stdio::null())
                .output()
                .unwrap();
            assert_eq!(
                output.status.code(),
                Some(item.code),
                "{} {:?}",
                item.name,
                output
            );
            let stdout = String::from_utf8(output.stdout.clone()).unwrap();
            let stderr = String::from_utf8(output.stderr.clone()).unwrap();
            if item.code == 0 {
                assert!(stderr.is_empty());
            } else if item.code == 1 {
                assert!(stdout.is_empty() && stderr.is_empty());
            } else {
                assert!(stderr.contains(if query && item.name == "partial" {
                    "search incomplete"
                } else {
                    "error:"
                }));
            }
            if query {
                match item.name {
                    "unicode-path" => assert!(stdout.contains("节点") && stdout.contains(r"A\\B")),
                    "default-name" => assert!(
                        stdout.contains("(default)") && stdout.matches("  VALUE ").count() == 1
                    ),
                    "empty-query-pattern" => assert_eq!(stdout.matches("  VALUE ").count(), 4),
                    "literal-data" | "quoted-name" | "expanded" | "partial" => {
                        assert_eq!(stdout.matches("  VALUE ").count(), 1)
                    }
                    _ => (),
                }
            }
            record.push_str(&format!(
                "REFERENCE {} args={:?} exit={}\nSTDOUT {stdout}\nSTDERR {stderr}\n",
                item.name, item.args, item.code
            ));
            output
        })
        .collect::<Vec<_>>();
    for (name, program) in &shells {
        let work = directory.join(name);
        fs::create_dir(&work).unwrap();
        scripts(&work, &cases);
        let mut command = Command::new(program);
        command
            .current_dir(&work)
            .env("REGQRY_SHELL_BIN", &bin)
            .env("REGQRY_SHELL_ROOT", &root)
            .env("REGQRY_SHELL_DENIED", &denied)
            .env("REGQRY_SHELL_SENTINEL", "expanded-节点")
            .stdin(Stdio::null());
        if *name == "cmd" {
            command.args(["/D", "/Q", "/C", "run.cmd"]);
        } else {
            command.args([
                "-NoLogo",
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                "run.ps1",
            ]);
            if *name == "powershell" {
                command.env("PSModulePath", ps5.parent().unwrap().join("Modules"));
            }
        }
        let output = command.output().unwrap();
        assert!(
            output.status.success(),
            "shell {name}: {output:?}; command={command:?}; files={:?}; script={}",
            fs::read_dir(&work)
                .unwrap()
                .map(|entry| entry.unwrap().file_name())
                .collect::<Vec<_>>(),
            fs::read_to_string(work.join("run.cmd")).unwrap()
        );
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "unexpected shell {name} diagnostics: {output:?}"
        );
        let version = fs::read_to_string(work.join("version.txt")).unwrap();
        if *name == "powershell" {
            assert!(version.starts_with("5.1."));
        }
        if *name == "pwsh" {
            assert!(version.starts_with("7."));
        }
        let modern_redirect =
            *name == "pwsh" && version.split('.').nth(1).unwrap().parse::<u32>().unwrap() >= 4;
        record.push_str(&format!(
            "SHELL name={name} program={program:?} version={version:?} status=pass cases={}\n",
            cases.len()
        ));
        for (item, reference) in cases.iter().zip(&references) {
            if *name == "cmd" {
                assert_eq!(
                    fs::read(work.join(format!("{}.stdout", item.name))).unwrap(),
                    reference.stdout,
                    "cmd {} stdout",
                    item.name
                );
                assert_eq!(
                    fs::read(work.join(format!("{}.stderr", item.name))).unwrap(),
                    reference.stderr,
                    "cmd {} stderr",
                    item.name
                );
                assert_eq!(
                    fs::read_to_string(work.join(format!("{}.exit", item.name)))
                        .unwrap()
                        .trim(),
                    item.code.to_string()
                );
            } else {
                let expected = lf(std::str::from_utf8(&reference.stdout).unwrap());
                for suffix in ["capture", "outfile", "redirect"] {
                    let path = work.join(format!("{}.{suffix}", item.name));
                    let bytes = fs::read(path)
                        .unwrap_or_else(|error| panic!("{name} {} {suffix}: {error}", item.name));
                    assert_eq!(
                        lf(&decoded(&bytes)),
                        expected,
                        "{name} {} {suffix}; exit={:?}; stderr={}",
                        item.name,
                        fs::read_to_string(work.join(format!("{}.capture.exit", item.name)))
                            .unwrap_or_default(),
                        decoded(
                            &fs::read(work.join(format!("{}.capture.stderr", item.name)))
                                .unwrap_or_default()
                        )
                    );
                    if !bytes.is_empty() {
                        if *name == "pwsh" || suffix == "capture" {
                            assert!(
                                !bytes.starts_with(&[0xff, 0xfe])
                                    && !bytes.starts_with(&[0xef, 0xbb, 0xbf]),
                                "{name} {} {suffix} must be UTF-8 without BOM",
                                item.name
                            );
                        }
                        if *name == "powershell" && suffix == "redirect" {
                            assert!(bytes.starts_with(&[0xff, 0xfe]));
                        }
                        if *name == "powershell" && suffix == "outfile" {
                            assert!(bytes.starts_with(&[0xef, 0xbb, 0xbf]));
                        }
                        if modern_redirect && suffix == "redirect" {
                            assert_eq!(&bytes, &reference.stdout);
                        }
                    }
                }
                for suffix in ["capture", "redirect"] {
                    assert_eq!(
                        fs::read_to_string(work.join(format!("{}.{suffix}.exit", item.name)))
                            .unwrap(),
                        item.code.to_string()
                    );
                    let error = decoded(
                        &fs::read(work.join(format!("{}.{suffix}.stderr", item.name))).unwrap(),
                    );
                    if reference.stderr.is_empty() {
                        assert!(error.is_empty(), "{name} {}: {error}", item.name);
                    } else {
                        assert!(
                            error.contains(if query && item.name == "partial" {
                                "search incomplete"
                            } else {
                                "error:"
                            }),
                            "{error}"
                        );
                        if item.name == "unicode-error" {
                            assert!(error.contains("节点"), "{error}");
                        }
                        if item.name == "percent-literal" {
                            assert!(error.contains("%REGQRY_SHELL_SENTINEL%"), "{error}");
                        }
                    }
                }
            }
        }
        let mut paths = fs::read_dir(&work)
            .unwrap()
            .map(|entry| entry.unwrap().path())
            .collect::<Vec<_>>();
        paths.sort();
        // Preserve original bytes, including BOMs/line endings, in the captured
        // harness log before explicit removal of this private temporary directory.
        for path in paths {
            let bytes = fs::read(&path).unwrap();
            record.push_str(&format!(
                "SHELL_FILE {name}/{} bytes={} hex={}\n",
                path.file_name().unwrap().to_string_lossy(),
                bytes.len(),
                hex::encode(bytes)
            ));
        }
    }
    record.push_str(&format!(
        "SHELL_SUMMARY shells={} cases_per_shell={} status=pass scope={}\n",
        shells.len(),
        cases.len(),
        if query {
            "owned-vm-query"
        } else {
            "no-query-help-and-invalid-input"
        }
    ));
    record
}

fn run(mode: &str) {
    // SAFETY: these parameterless APIs only observe this process's console.
    let before = unsafe { (GetConsoleCP(), GetConsoleOutputCP()) };
    let directory = tempfile::Builder::new()
        .prefix("regqry-shell 空间 ")
        .tempdir()
        .unwrap();
    fs::write(directory.path().join("request.txt"), mode).unwrap();
    assert!(!processes::hidden_worker(
        directory.path(),
        Duration::from_secs(90)
    ));
    println!(
        "{}",
        fs::read_to_string(directory.path().join("result.txt")).unwrap()
    );
    directory.close().unwrap();
    // SAFETY: observe the same calling console after our isolated job is gone.
    assert_eq!(
        unsafe { (GetConsoleCP(), GetConsoleOutputCP()) },
        before,
        "shell tests changed the caller's console code pages"
    );
}
#[test]
fn shell_invocation_and_encoding_without_registry_queries() {
    run("shell-probe");
}
#[test]
#[ignore = "explicit disposable VM: actual CLI queries in cmd, Windows PowerShell 5.1 and PowerShell 7"]
fn vm_cli_shells() {
    let context = Context::require("query");
    context.machine(KEY_WOW64_64KEY);
    run("shell-vm");
}

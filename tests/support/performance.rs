//! Fixed owned fixtures and privacy-preserving observations of the actual CLI.
use super::{child, machine_path, processes, text};
use crate::support::{
    cli,
    vm::{self, Context, assert_marker, set},
};
use std::{
    collections::{BTreeMap, BTreeSet},
    ffi::OsStr,
    fs::{self, OpenOptions},
    io::{BufRead, BufReader, Cursor, Write},
    path::Path,
    process::Command,
    thread,
    time::{Duration, Instant},
};
use windows_sys::Win32::System::Registry::{
    KEY_QUERY_VALUE, KEY_WOW64_64KEY, REG_BINARY, REG_DWORD, REG_EXPAND_SZ, REG_OPTION_OPEN_LINK,
};
use winreg::RegKey;

const WIDTHS: [usize; 3] = [64, 512, 4096];
const DEPTHS: [usize; 3] = [16, 64, 256];
const NAMES: [&str; 4] = ["Text", "Raw", "Expand", "Ordinal"];
const LIVE_CONFIRM: &str = "readonly-aggregate-only";

fn populate(root: &RegKey, mut create: impl FnMut(&RegKey, &str) -> RegKey) {
    for width in WIDTHS {
        let branch = create(root, &format!("W{width:04}"));
        for index in 0..width {
            let key = create(&branch, &format!("Node{index:04}"));
            text(
                &key,
                "Text",
                &format!("fixed-节点-{index:04} {}", "x".repeat(64)),
            );
            let mut bytes = [0xA5; 256];
            bytes[..4].copy_from_slice(&[0xDE, 0xAD, 0xBE, 0xEF]);
            bytes[4..8].copy_from_slice(&(index as u32).to_le_bytes());
            set(&key, OsStr::new("Raw"), REG_BINARY, &bytes);
            set(
                &key,
                OsStr::new("Ordinal"),
                REG_DWORD,
                &(index as u32).to_le_bytes(),
            );
            let expand = "%REGQRY_SCALE_TEST_VAR%\0"
                .encode_utf16()
                .flat_map(u16::to_le_bytes)
                .collect::<Vec<_>>();
            set(&key, OsStr::new("Expand"), REG_EXPAND_SZ, &expand);
        }
    }
    for depth in DEPTHS {
        let mut parent = create(root, &format!("D{depth:04}"));
        for level in 1..=depth {
            parent = create(&parent, &format!("K{level:04}"));
            text(&parent, "Payload", &format!("depth-{level:04}"));
        }
    }
}
pub(super) fn prepare(root: &RegKey, context: &Context) {
    let scale = child(root, "Scale", KEY_WOW64_64KEY, context, 9);
    populate(&scale, |parent, name| {
        child(parent, name, KEY_WOW64_64KEY, context, 9)
    });
}

#[derive(Debug, Default)]
struct OutputStats {
    first_us: Option<u128>,
    records: usize,
    bytes: usize,
    // None for live observations: never retain registry identities or contents.
    identities: Option<BTreeSet<String>>,
    duplicate: bool,
}
fn consume(mut reader: impl BufRead, started: Instant, collect: bool) -> OutputStats {
    let mut result = OutputStats {
        identities: collect.then(BTreeSet::new),
        ..Default::default()
    };
    let mut heading = String::new();
    loop {
        let mut line = String::new();
        let bytes = reader
            .read_line(&mut line)
            .expect("cannot decode stdout as UTF-8");
        if bytes == 0 {
            break;
        }
        result.bytes += bytes;
        let line = line.trim_end_matches(['\r', '\n']);
        if collect && (line.starts_with("[32] ") || line.starts_with("[64] ")) {
            heading = line.into();
        }
        let record = line.starts_with("KEY [")
            || line.starts_with("  VALUE ")
            || line.starts_with("  UNSET ");
        if !record {
            continue;
        }
        result
            .first_us
            .get_or_insert_with(|| started.elapsed().as_micros());
        result.records += 1;
        if let Some(identities) = &mut result.identities {
            let identity = if let Some(key) = line.strip_prefix("KEY ") {
                format!("KEY\0{key}")
            } else {
                // Fixed-fixture names are simple ASCII. Live output never enters
                // this parser or stores a heading/identity.
                let value = line
                    .strip_prefix("  VALUE ")
                    .expect("unexpected fixture UNSET");
                let name = value
                    .split_once("  ")
                    .expect("missing fixture value columns")
                    .0;
                format!("VALUE\0{heading}\0{name}")
            };
            result.duplicate |= !identities.insert(identity);
        }
    }
    result
}
#[derive(Debug, Default)]
struct ErrorStats {
    lines: usize,
    win32: BTreeMap<u32, usize>,
    incomplete: bool,
}
fn errors(reader: impl BufRead) -> ErrorStats {
    let mut result = ErrorStats::default();
    for line in reader.lines() {
        let line = line.expect("cannot decode stderr as UTF-8");
        result.lines += 1;
        result.incomplete |= line.contains("search incomplete");
        // Recognize the terminal "Win32 N: message" field, not a mention in
        // an arbitrary target name. Ambiguous extra-colon messages stay counted
        // as diagnostic lines without guessing a code.
        if let Some(code) = line
            .rsplit(": ")
            .nth(1)
            .and_then(|field| field.strip_prefix("Win32 "))
            .and_then(|code| code.parse::<u32>().ok())
        {
            *result.win32.entry(code).or_default() += 1;
        }
        // Deliberately drop the diagnostic's target and message here.
    }
    result
}
fn measure(
    command: Command,
    expected: Option<&BTreeSet<String>>,
) -> (i32, OutputStats, ErrorStats, u128, usize) {
    let started = Instant::now();
    let mut query = processes::spawn(command);
    let stdout = query.0.stdout.take().unwrap();
    let stderr = query.0.stderr.take().unwrap();
    let collect = expected.is_some();
    let output = thread::spawn(move || consume(BufReader::new(stdout), started, collect));
    let errors = thread::spawn(move || errors(BufReader::new(stderr)));
    let code = processes::wait_for(&mut query, Duration::from_secs(60));
    let memory = processes::peak(&query);
    let output = output.join().expect("stdout consumer failed");
    let errors = errors.join().expect("stderr consumer failed");
    let total = started.elapsed().as_micros();
    if let Some(expected) = expected {
        assert_eq!(code, if expected.is_empty() { 1 } else { 0 });
        assert_eq!(errors.lines, 0);
        assert!(!output.duplicate, "duplicate fixture identity");
        assert_eq!(output.identities.as_ref().unwrap(), expected);
        assert_eq!(output.records, expected.len());
    }
    assert_eq!(output.first_us.is_some(), output.records != 0);
    (code, output, errors, total, memory)
}
fn metric(
    label: &str,
    pass: usize,
    args: &[String],
    measured: &(i32, OutputStats, ErrorStats, u128, usize),
) -> String {
    let (code, output, errors, total, memory) = measured;
    format!(
        "METRIC case={label} pass={pass} exit={code} complete={} records={} output_bytes={} first_result_us={} total_us={total} peak_working_set_bytes={memory} diagnostic_lines={} win32={:?} incomplete={} cache=uncontrolled consumer=immediate-drain cancel_to_exit_us=N/A\nARGS {args:?}\n",
        *code < 2,
        output.records,
        output.bytes,
        output
            .first_us
            .map(|value| value.to_string())
            .unwrap_or_else(|| "N/A".into()),
        errors.lines,
        errors.win32,
        errors.incomplete
    )
}
fn trace(directory: &Path, line: &str) {
    OpenOptions::new()
        .create(true)
        .append(true)
        .open(directory.join("progress.txt"))
        .unwrap()
        .write_all(line.as_bytes())
        .unwrap();
}
fn command(args: &[String]) -> Command {
    let mut command = Command::new(cli::binary());
    command.args(args);
    command
}
struct Case {
    label: String,
    args: Vec<String>,
    expected: BTreeSet<String>,
}
fn values(root: &str, count: usize, names: &[&str]) -> BTreeSet<String> {
    (0..count)
        .flat_map(|index| {
            names
                .iter()
                .map(move |name| format!("VALUE\0[64] {root}\\Node{index:04}\0\"{name}\""))
        })
        .collect()
}
fn depth_values(root: &str, from: usize, depth: usize) -> BTreeSet<String> {
    let mut key = root.to_owned();
    (1..=depth)
        .filter_map(|level| {
            key.push_str(&format!("\\K{level:04}"));
            (level >= from).then(|| format!("VALUE\0[64] {key}\0\"Payload\""))
        })
        .collect()
}
fn cases(base: &str) -> Vec<Case> {
    let mut result = Vec::new();
    for width in WIDTHS {
        let root = format!("{base}\\W{width:04}");
        for (label, filter, expected) in [
            (
                "keys",
                vec![],
                (0..width)
                    .map(|index| format!("KEY\0[64] {root}\\Node{index:04}"))
                    .collect(),
            ),
            (
                "dense",
                vec!["--name", "^(Text|Raw|Expand|Ordinal)$"],
                values(&root, width, &NAMES),
            ),
            (
                "text",
                vec!["--name=^Text$", "--data=fixed-节点"],
                values(&root, width, &["Text"]),
            ),
            (
                "hex",
                vec!["--name=^Raw$", "--data-hex=DEADBEEF"],
                values(&root, width, &["Raw"]),
            ),
            (
                "expand",
                vec!["--name=^Expand$", "--data-expand=^expanded-节点$"],
                values(&root, width, &["Expand"]),
            ),
        ] {
            let mut args = vec!["--key-root".into(), root.clone(), "--view=64".into()];
            args.extend(filter.into_iter().map(String::from));
            result.push(Case {
                label: format!("width-{width}-{label}"),
                args,
                expected,
            });
        }
    }
    for depth in DEPTHS {
        let root = format!("{base}\\D{depth:04}");
        result.push(Case {
            label: format!("depth-{depth}"),
            args: vec![
                "--key-root".into(),
                root.clone(),
                "--view=64".into(),
                "--name=^Payload$".into(),
            ],
            expected: depth_values(&root, 1, depth),
        });
    }
    let root = format!("{base}\\D0256");
    let nested = format!(
        "{root}{}",
        (1..=16)
            .map(|level| format!("\\K{level:04}"))
            .collect::<String>()
    );
    for relative in [false, true] {
        let mut args = vec![
            "--key-root".into(),
            root.clone(),
            "--key-root".into(),
            nested.clone(),
            "--key-root".into(),
            root.clone(),
            "--view=64".into(),
            "--name=^Payload$".into(),
        ];
        if relative {
            args.push("--key=^K0017".into());
        }
        result.push(Case {
            label: format!("overlap-relative-{relative}"),
            args,
            expected: depth_values(&root, if relative { 17 } else { 1 }, 256),
        });
    }
    result.push(Case {
        label: "quiet".into(),
        args: vec![
            "--key-root".into(),
            format!("{base}\\W4096"),
            "--view=64".into(),
            "--name=^not-present$".into(),
        ],
        expected: BTreeSet::new(),
    });
    result
}
pub(super) fn vm_measure(directory: &Path) -> String {
    let context = Context::require("query");
    let root = context.machine(KEY_WOW64_64KEY);
    let scale = root
        .open_subkey_with_options_flags(
            "Scale",
            REG_OPTION_OPEN_LINK,
            KEY_QUERY_VALUE | KEY_WOW64_64KEY,
        )
        .unwrap();
    assert_marker(&scale, &context.nonce);
    let cases = cases(&machine_path(&context, "Scale"));
    let mut result = format!(
        "ACTUAL_CLI_SCALE fixture_version=1 widths={WIDTHS:?} depths={DEPTHS:?} case_count={} passes=2 binary_seed=A5-prefix-DEADBEEF-index-u32le text_pad=64\n",
        cases.len()
    );
    trace(directory, &result);
    for pass in 1..=2 {
        for case in &cases {
            trace(
                directory,
                &format!(
                    "START case={} pass={pass} args={:?}\n",
                    case.label, case.args
                ),
            );
            let mut command = command(&case.args);
            command.env("REGQRY_SCALE_TEST_VAR", "expanded-节点");
            let measured = measure(command, Some(&case.expected));
            let line = metric(&case.label, pass, &case.args, &measured);
            trace(directory, &line);
            result.push_str(&line);
        }
    }
    result
}
fn require_live() {
    assert!(
        std::env::var("REGQRY_LIVE_CONFIRM").is_ok_and(|value| value == LIVE_CONFIRM),
        "missing REGQRY_LIVE_CONFIRM; use measure-live.ps1 -ReadOnlyLiveRegistry; this observes existing registry data without retaining it"
    );
}
pub(super) fn live_measure(directory: &Path) -> String {
    require_live();
    let mut result = String::from(
        "LIVE_OBSERVATION actual_cli=true output=aggregate-only correctness=not-asserted cache=uncontrolled passes=2\n",
    );
    trace(directory, &result);
    for pass in 1..=2 {
        for (label, args) in [
            ("default-key", vec!["--key=.*"]),
            (
                "scoped-key",
                vec!["--key-root", r"HKCU\Software", "--key=Microsoft"],
            ),
            (
                "scoped-name",
                vec!["--key-root", r"HKCU\Software", "--name=Path"],
            ),
            (
                "scoped-data",
                vec!["--key-root", r"HKCU\Software", "--data-i=windows"],
            ),
            (
                "scoped-hex",
                vec!["--key-root", r"HKCU\Software", "--data-hex=DEADBEEF"],
            ),
            ("expanded", vec!["--key-root", "HKCU", "--data-expand=."]),
        ] {
            let args = args.into_iter().map(String::from).collect::<Vec<_>>();
            trace(
                directory,
                &format!("START case={label} pass={pass} args={args:?}\n"),
            );
            let measured = measure(command(&args), None);
            assert!(
                matches!(measured.0, 0..=2),
                "unexpected CLI status during observation"
            );
            let line = metric(label, pass, &args, &measured);
            trace(directory, &line);
            result.push_str(&line);
        }
    }
    result
}
pub(super) fn control_probe() -> String {
    let started = Instant::now();
    let private = "[64] HKCU\\private-target\n  VALUE \"secret-value\"  REG_SZ (1) \"secret-data\"\nKEY [64] HKCU\\private-key\n";
    let summary = consume(Cursor::new(private), started, false);
    assert_eq!(summary.records, 2);
    assert!(summary.identities.is_none() && summary.first_us.is_some());
    assert!(
        !format!("{summary:?}").contains("private") && !format!("{summary:?}").contains("secret")
    );
    let empty = consume(Cursor::new("[64] header-only\n"), started, false);
    assert!(empty.first_us.is_none() && empty.records == 0);
    let errors = errors(Cursor::new(
        "regqry: private-path secret-data: open: Win32 5: Access denied.\nregqry: private: Win32 999: fake: decode: Invalid UTF-16\nregqry: search incomplete (1 error)\n",
    ));
    assert_eq!(errors.win32.get(&5), Some(&1));
    assert_eq!(errors.win32.len(), 1);
    assert!(
        errors.incomplete
            && !format!("{errors:?}").contains("private")
            && !format!("{errors:?}").contains("secret")
    );
    let directory = tempfile::tempdir().unwrap();
    let command = processes::producer_command(directory.path());
    let result = measure(command, None);
    assert_eq!(result.0, 0);
    assert_eq!(result.1.records, 4096);
    assert_eq!(result.2.lines, 0);
    assert!(result.4 > 0);
    directory.close().unwrap();
    format!(
        "CONTROL_PROBE aggregate-consumer privacy=checked source=constructed-producer not-registry-query\n{}",
        metric("constructed-producer", 1, &[], &result)
    )
}
fn run(mode: &str, seconds: u64) {
    let directory = tempfile::Builder::new()
        .prefix("regqry-perf 空间 ")
        .tempdir()
        .unwrap();
    fs::write(directory.path().join("request.txt"), mode).unwrap();
    assert!(!processes::hidden_worker(
        directory.path(),
        Duration::from_secs(seconds)
    ));
    println!(
        "{}",
        fs::read_to_string(directory.path().join("result.txt")).unwrap()
    );
    directory.close().unwrap();
}
#[test]
fn aggregate_consumer_and_process_measurement() {
    run("scale-probe", 90);
}
#[test]
fn private_generated_fixture_roundtrips_deep_and_wide_data() {
    let directory = tempfile::tempdir().unwrap();
    {
        let root = RegKey::load_app_key(directory.path().join("scaling.hiv"), true).unwrap();
        populate(&root, |parent, name| {
            vm::create(parent, OsStr::new(name), 0, None).unwrap()
        });
        for width in WIDTHS {
            let branch = root.open_subkey(format!("W{width:04}")).unwrap();
            assert_eq!(branch.enum_keys().count(), width);
            for index in [0, width - 1] {
                let key = branch.open_subkey(format!("Node{index:04}")).unwrap();
                let (kind, bytes) = vm::raw(&key, "Raw");
                assert_eq!(kind, REG_BINARY);
                assert_eq!(bytes.len(), 256);
                assert_eq!(&bytes[..4], &[0xDE, 0xAD, 0xBE, 0xEF]);
                assert_eq!(&bytes[4..8], &(index as u32).to_le_bytes());
            }
        }
        for depth in DEPTHS {
            let path = format!(
                "D{depth:04}{}",
                (1..=depth)
                    .map(|level| format!("\\K{level:04}"))
                    .collect::<String>()
            );
            let direct = root.open_subkey(path);
            println!(
                "PRIVATE_FIXTURE_DIRECT_OPEN depth={depth} status={:?}",
                direct
                    .as_ref()
                    .map(|_| ())
                    .map_err(|error| error.raw_os_error())
            );
            drop(direct);
            // Like product recursion, reopen one component at a time. A single
            // long-path API call is a different native operation, not a depth cap.
            let mut key = root.open_subkey(format!("D{depth:04}")).unwrap();
            for level in 1..=depth {
                key = key.open_subkey(format!("K{level:04}")).unwrap();
            }
            let (kind, bytes) = vm::raw(&key, "Payload");
            assert_eq!(kind, 1);
            assert_eq!(
                bytes,
                format!("depth-{depth:04}\0")
                    .encode_utf16()
                    .flat_map(u16::to_le_bytes)
                    .collect::<Vec<_>>()
            );
        }
    }
    directory.close().unwrap();
}
#[test]
#[ignore = "explicit disposable VM: exact fixed-fixture scaling series"]
fn vm_scaling_baseline() {
    let context = Context::require("query");
    context.machine(KEY_WOW64_64KEY);
    run("scale-vm", 540);
}
#[test]
#[ignore = "explicit read-only live observation: aggregate output only, no correctness dataset"]
fn live_queries() {
    require_live();
    run("live-performance", 840);
}

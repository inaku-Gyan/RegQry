use super::*;
use crate::{
    cli,
    output::Output,
    registry::{Child, WindowsSource},
};
use std::{cell::Cell, collections::BTreeMap};

mod native;

fn plan(args: &[&str]) -> Plan {
    let matches = cli::command()
        .try_get_matches_from(std::iter::once("regqry").chain(args.iter().copied()))
        .unwrap();
    cli::query_plan(&matches).unwrap()
}
fn bytes(text: &str) -> Vec<u8> {
    text.encode_utf16().flat_map(u16::to_le_bytes).collect()
}
type Stored = (OsString, u32, Vec<u8>);
#[derive(Default)]
struct Node {
    children: Vec<String>,
    values: Vec<Stored>,
    failure: Option<u32>,
    deny_enum: bool,
    read_failure: Option<i32>,
}
#[derive(Default)]
struct Memory {
    nodes: BTreeMap<String, Node>,
    child_reads: Cell<usize>,
}
impl Memory {
    fn node(&mut self, path: &str, children: &[&str], values: Vec<Stored>) {
        self.nodes.insert(
            path.into(),
            Node {
                children: children.iter().map(|s| (*s).into()).collect(),
                values,
                ..Default::default()
            },
        );
    }
    fn fixture() -> Self {
        let mut source = Self::default();
        source.node("HKCU", &["Vendor"], vec![]);
        source.node("HKCU\\Vendor", &["Acme"], vec![]);
        source.node(
            "HKCU\\Vendor\\Acme",
            &["Leaf"],
            vec![
                ("A".into(), 1, bytes("foo\0")),
                ("B".into(), 4, 42u32.to_le_bytes().to_vec()),
            ],
        );
        source.node("HKCU\\Vendor\\Acme\\Leaf", &[], vec![]);
        source
    }
}
impl Source for Memory {
    type Key = String;
    fn open_root(&self, root: &Root, _: View) -> io::Result<String> {
        let path = root.full_path()?.into_string().unwrap();
        if self.nodes.contains_key(&path) {
            Ok(path)
        } else {
            Err(io::Error::from_raw_os_error(2))
        }
    }
    fn open_child(&self, key: &String, name: &OsStr, _: View, values: bool) -> io::Result<String> {
        let child = registry::join(OsStr::new(key), name)?
            .into_string()
            .unwrap();
        let node = self
            .nodes
            .get(&child)
            .ok_or_else(|| io::Error::from_raw_os_error(2))?;
        if !values && node.deny_enum {
            return Err(io::Error::from_raw_os_error(5));
        }
        Ok(child)
    }
    fn child_at(&self, key: &String, index: u32) -> io::Result<Option<Child>> {
        self.child_reads.set(self.child_reads.get() + 1);
        let node = &self.nodes[key];
        if node.failure == Some(index) {
            return Err(io::Error::from_raw_os_error(5));
        }
        Ok(node.children.get(index as usize).map(|name| Child {
            name: name.into(),
            modified: 116_444_736_000_000_000,
        }))
    }
    fn value_at(&self, key: &String, index: u32) -> io::Result<Option<OsString>> {
        Ok(self.nodes[key]
            .values
            .get(index as usize)
            .map(|(name, _, _)| name.clone()))
    }
    fn read(&self, key: &String, name: &OsStr) -> io::Result<RawValue> {
        if let Some(code) = self.nodes[key].read_failure {
            return Err(io::Error::from_raw_os_error(code));
        }
        self.nodes[key]
            .values
            .iter()
            .find(|(n, _, _)| registry::ordinal(n, name).unwrap() == Ordering::Equal)
            .map(|(n, k, b)| RawValue::new(n.clone(), *k, b.clone()))
            .ok_or_else(|| io::Error::from_raw_os_error(2))
    }
}
fn run<R: Source>(plan: &Plan, source: &R) -> (Summary, String, String) {
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    let result = execute(
        plan,
        &Environment::from_entries(vec![("A".into(), "expanded".into())]),
        source,
        &mut Output::new(&mut stdout, &mut stderr),
        &AtomicBool::new(false),
    );
    (
        result,
        String::from_utf8(stdout).unwrap(),
        String::from_utf8(stderr).unwrap(),
    )
}

#[test]
fn relative_roots_are_evaluated_before_dedup_and_never_pruned() {
    let source = Memory::fixture();
    let query = plan(&[
        "--key-root",
        "HKCU",
        "--key-root",
        "HKCU\\Vendor",
        "--key",
        "^Acme$",
        "--view",
        "64",
    ]);
    let (summary, stdout, stderr) = run(&query, &source);
    assert_eq!(summary.code(), 0);
    assert_eq!(stdout, "KEY [64] HKCU\\Vendor\\Acme\n");
    assert!(stderr.is_empty());
    let (summary, stdout, _) = run(
        &plan(&[
            "--key-root",
            "HKCU\\Vendor\\Acme",
            "--key",
            "^Acme$",
            "--view",
            "64",
        ]),
        &source,
    );
    assert_eq!(summary.code(), 1);
    assert!(stdout.is_empty());
    let (_, stdout, _) = run(
        &plan(&[
            "--key-root",
            "HKCU",
            "--key-root",
            "HKCU\\Vendor",
            "--key",
            "Acme",
            "--view",
            "64",
            "--view",
            "64",
        ]),
        &source,
    );
    assert_eq!(stdout.lines().count(), 2);
}
#[test]
fn key_globs_cover_zero_components_and_time_bounds_are_strict() {
    let source = Memory::fixture();
    for (pattern, count) in [
        ("Vendor\\**", 3),
        ("**\\Acme", 1),
        ("Vendor\\*", 1),
        ("**", 3),
    ] {
        let (summary, stdout, _) = run(
            &plan(&["--key-root", "HKCU", "--key-glob", pattern, "--view", "64"]),
            &source,
        );
        assert_eq!(summary.code(), 0, "{pattern}");
        assert_eq!(stdout.lines().count(), count, "{pattern}");
    }
    for bound in ["--key-modified-after", "--key-modified-before"] {
        assert_eq!(
            run(
                &plan(&[
                    "--key-root",
                    "HKCU",
                    bound,
                    "1970-01-01T00:00:00Z",
                    "--view",
                    "64"
                ]),
                &source
            )
            .0
            .code(),
            1
        );
    }
    assert_eq!(
        run(
            &plan(&[
                "--key-root",
                "HKCU",
                "--key-modified-after",
                "1969-01-01T00:00:00Z",
                "--key-modified-before",
                "1971-01-01T00:00:00Z",
                "--view",
                "64"
            ]),
            &source
        )
        .0
        .code(),
        0
    );
}
#[test]
fn all_value_groups_apply_to_the_same_value_and_types_exclude_globally() {
    let source = Memory::fixture();
    let (summary, stdout, stderr) = run(
        &plan(&[
            "--key-root",
            "HKCU\\Vendor",
            "--name",
            "^A$",
            "--data",
            "42",
            "--view",
            "64",
        ]),
        &source,
    );
    assert_eq!(summary.code(), 1);
    assert!(stdout.is_empty() && stderr.is_empty());
    let (summary, stdout, _) = run(
        &plan(&[
            "--key-root",
            "HKCU\\Vendor",
            "--name-glob",
            "a",
            "--data",
            "foo",
            "-t",
            "sz",
            "-t",
            "dword",
            "-T",
            "dword",
            "--view",
            "64",
        ]),
        &source,
    );
    assert_eq!(summary.code(), 0);
    assert!(stdout.contains("\"A\"  REG_SZ (1)"));
    assert!(!stdout.contains("\"B\""));
}
#[test]
fn missing_defaults_empty_values_and_zero_bytes_remain_distinct() {
    let mut source = Memory::default();
    source.node("HKCU", &["Unset", "Empty", "Zero", "None"], vec![]);
    source.node("HKCU\\Unset", &[], vec![("Named".into(), 1, bytes("\0"))]);
    source.node("HKCU\\Empty", &[], vec![("".into(), 1, bytes("\0"))]);
    source.node("HKCU\\Zero", &[], vec![("".into(), 3, vec![])]);
    source.node("HKCU\\None", &[], vec![("".into(), 0, vec![0])]);
    for (filter, matches) in [
        ("--data-not-set", 1),
        ("--data-empty", 2),
        ("--data-zero-length", 1),
    ] {
        let (summary, stdout, stderr) = run(
            &plan(&["--key-root", "HKCU", filter, "--name", "^$", "--view", "64"]),
            &source,
        );
        assert_eq!(summary.code(), 0);
        assert_eq!(
            stdout.lines().filter(|s| s.starts_with("  ")).count(),
            matches
        );
        assert!(stderr.is_empty());
        if filter == "--data-not-set" {
            assert!(stdout.contains("Default value not set"));
            assert!(!stdout.contains("bytes"));
        }
    }
    assert_eq!(
        run(
            &plan(&[
                "--key-root",
                "HKCU",
                "--data-not-set",
                "-t",
                "sz",
                "--view",
                "64"
            ]),
            &source
        )
        .0
        .code(),
        1
    );
}
#[test]
fn decoding_failure_is_required_only_when_no_or_condition_decides() {
    let mut source = Memory::fixture();
    source.nodes.get_mut("HKCU\\Vendor\\Acme").unwrap().values = vec![("Bad".into(), 1, vec![65])];
    let (summary, stdout, stderr) = run(
        &plan(&["--key-root", "HKCU\\Vendor", "--data", "A", "--view", "64"]),
        &source,
    );
    assert_eq!(summary.code(), 2);
    assert!(stdout.is_empty());
    assert!(stderr.contains("match value") && stderr.contains("search incomplete"));
    for extra in [vec!["--data-hex", "41"], vec!["-t", "sz"]] {
        let mut args = vec!["--key-root", "HKCU\\Vendor", "--view", "64"];
        if extra[0] == "--data-hex" {
            args.extend(["--data", "A"]);
        }
        args.extend(extra);
        let (summary, stdout, stderr) = run(&plan(&args), &source);
        assert_eq!(summary.code(), 0);
        assert!(stdout.contains("interpretation unavailable") && stdout.contains("hex[41]"));
        assert!(stderr.is_empty());
    }
}
#[test]
fn expansion_only_matches_expand_sz_and_case_flags_are_per_condition() {
    let mut source = Memory::fixture();
    source.nodes.get_mut("HKCU\\Vendor\\Acme").unwrap().values = vec![
        ("Saved".into(), 1, bytes("%A%\0")),
        ("Expanded".into(), 2, bytes("%a%\0")),
    ];
    let (summary, stdout, _) = run(
        &plan(&[
            "--key-root",
            "HKCU\\Vendor",
            "--data-expand",
            "^expanded$",
            "--view",
            "64",
        ]),
        &source,
    );
    assert_eq!(summary.code(), 0);
    assert!(stdout.contains("\"Expanded\""));
    assert!(!stdout.contains("\"Saved\""));
    assert!(stdout.contains("%a%"));
    assert_eq!(
        run(
            &plan(&[
                "--key-root",
                "HKCU\\Vendor",
                "--data",
                "^%a%$",
                "--name",
                "Saved",
                "--view",
                "64"
            ]),
            &source
        )
        .0
        .code(),
        1
    );
    assert_eq!(
        run(
            &plan(&[
                "--key-root",
                "HKCU\\Vendor",
                "--data-i",
                "^%a%$",
                "--name",
                "Saved",
                "--view",
                "64"
            ]),
            &source
        )
        .0
        .code(),
        0
    );
}
#[test]
fn a_failed_range_does_not_hide_other_roots_or_independent_value_access() {
    let mut source = Memory::fixture();
    source.nodes.get_mut("HKCU").unwrap().failure = Some(0);
    source
        .nodes
        .get_mut("HKCU\\Vendor\\Acme")
        .unwrap()
        .deny_enum = true;
    let (summary, stdout, stderr) = run(
        &plan(&[
            "--key-root",
            "HKCU",
            "--key-root",
            "HKCU\\Vendor",
            "--name",
            "A",
            "--view",
            "64",
        ]),
        &source,
    );
    assert_eq!(summary.code(), 2);
    assert!(stdout.contains("\"A\""));
    assert!(
        stderr.contains("Win32 5")
            && stderr.contains("open subkeys")
            && stderr.contains("search incomplete")
    );
}
#[test]
fn identity_comparison_is_case_insensitive_but_views_and_value_names_are_distinct() {
    let mut seen = Seen::default();
    let target = |view, key: &str, name: Option<&str>| Target {
        view,
        key: key.into(),
        name: name.map(OsString::from),
    };
    assert!(
        seen.insert(&target(View::V64, "HKCU\\Name", Some("A\\B")))
            .unwrap()
    );
    assert!(
        !seen
            .insert(&target(View::V64, "hkcu\\name", Some("a\\b")))
            .unwrap()
    );
    assert!(
        seen.insert(&target(View::V32, "HKCU\\Name", Some("A\\B")))
            .unwrap()
    );
    assert!(
        seen.insert(&target(View::V64, "HKCU\\Name\\A", Some("B")))
            .unwrap()
    );
}
#[test]
fn malformed_names_keep_raw_identity_and_only_necessary_matching_fails() {
    use std::os::windows::ffi::OsStringExt;
    let mut source = Memory::fixture();
    let raw_name = OsString::from_wide(&[0xD800]);
    source.nodes.get_mut("HKCU\\Vendor\\Acme").unwrap().values =
        vec![(raw_name.clone(), 3, vec![1])];
    let (_, stdout, stderr) = run(
        &plan(&["--key-root", "HKCU\\Vendor", "-t", "binary", "--view", "64"]),
        &source,
    );
    assert!(stdout.contains("\\u16{D800}"));
    assert!(stderr.is_empty());
    assert_eq!(
        run(
            &plan(&["--key-root", "HKCU\\Vendor", "--name", "x", "--view", "64"]),
            &source
        )
        .0
        .code(),
        2
    );
    assert_eq!(
        run(
            &plan(&[
                "--key-root",
                "HKCU\\Vendor",
                "--name",
                "x",
                "--data-hex",
                "FF",
                "--view",
                "64"
            ]),
            &source
        )
        .0
        .code(),
        1
    );
    let mut path_a = OsString::from("HKCU\\Vendor\\");
    path_a.push(&raw_name);
    let mut path_b = OsString::from("hkcu\\vendor\\");
    path_b.push(&raw_name);
    assert_eq!(
        registry::ordinal_path(&path_a, &path_b).unwrap(),
        Ordering::Equal
    );
    assert!(registry::ordinal(&raw_name, &OsString::from_wide(&[0xD801])).is_err());
}
#[test]
fn system_diagnostics_use_english_or_explicit_english_fallback() {
    let message = registry::error_text(&io::Error::from_raw_os_error(2));
    assert!(message.starts_with("Win32 2: "));
    assert!(
        message.contains("system cannot find")
            || message.contains("English system message unavailable"),
        "{message}"
    );
    assert!(
        registry::error_text(&io::Error::from_raw_os_error(-1))
            .contains("English system message unavailable")
    );
}
#[test]
fn deleted_keys_and_read_failures_are_never_missing_default_values() {
    let mut source = Memory::default();
    source.node("HKCU", &["A"], vec![]);
    source.node("HKCU\\A", &[], vec![]);
    let query = plan(&["--key-root", "HKCU", "--data-not-set", "--view", "64"]);
    for code in [3, 5, 1018] {
        source.nodes.get_mut("HKCU\\A").unwrap().read_failure = Some(code);
        let (summary, stdout, stderr) = run(&query, &source);
        assert_eq!(summary.code(), 2);
        assert!(stdout.is_empty());
        assert!(stderr.contains(&format!("Win32 {code}:")) && stderr.contains("search incomplete"));
    }
}
struct Interrupting<'a> {
    signal: &'a AtomicBool,
    fail: bool,
    count: usize,
}
impl Sink for Interrupting<'_> {
    fn key(&mut self, _: &Target) -> io::Result<()> {
        self.count += 1;
        if self.fail {
            Err(io::Error::other("closed consumer"))
        } else {
            self.signal.store(true, AtomicOrdering::Relaxed);
            Ok(())
        }
    }
    fn value(&mut self, target: &Target, _: Option<&RawValue>) -> io::Result<()> {
        self.key(target)
    }
    fn diagnostic(&mut self, _: &Target, _: &str, _: &io::Error) -> io::Result<()> {
        Ok(())
    }
    fn finish(&mut self, _: &Summary) -> io::Result<()> {
        Ok(())
    }
}
#[test]
fn output_is_streamed_and_cancel_or_write_failure_stops_more_reads() {
    for (fail, expected) in [(false, 130), (true, 2)] {
        let source = Memory::fixture();
        let cancelled = AtomicBool::new(false);
        let mut sink = Interrupting {
            signal: &cancelled,
            fail,
            count: 0,
        };
        let summary = execute(
            &plan(&["--key-root", "HKCU", "--view", "64"]),
            &Environment::capture(),
            &source,
            &mut sink,
            &cancelled,
        );
        assert_eq!(summary.code(), expected);
        assert_eq!(sink.count, 1);
        assert_eq!(source.child_reads.get(), 1);
    }
}

#[test]
fn a_closed_windows_pipe_on_write_or_flush_stops_the_query_with_status_two() {
    use std::io::{BufWriter, Write, pipe};
    for buffered in [false, true] {
        let (consumer, producer) = pipe().unwrap();
        drop(consumer);
        // The OS reader is closed. A large BufWriter postpones the same real
        // broken-pipe error until Output's per-record flush.
        let writer: Box<dyn Write> = if buffered {
            Box::new(BufWriter::with_capacity(65536, producer))
        } else {
            Box::new(producer)
        };
        let source = Memory::fixture();
        let mut stderr = Vec::new();
        let summary = execute(
            &plan(&["--key-root=HKCU", "--view=64"]),
            &Environment::from_entries(vec![]),
            &source,
            &mut Output::new(writer, &mut stderr),
            &AtomicBool::new(false),
        );
        assert_eq!(summary.code(), 2);
        assert!(summary.output_failed && summary.incomplete);
        assert_eq!(source.child_reads.get(), 1);
        let diagnostic = String::from_utf8(stderr).unwrap();
        assert!(
            diagnostic.contains("write result")
                && diagnostic.contains("Win32 ")
                && diagnostic.contains("search incomplete"),
            "{diagnostic}"
        );
    }
}

struct Application<'a> {
    hive: &'a winreg::RegKey,
    native: WindowsSource<'a>,
}
impl Source for Application<'_> {
    type Key = winreg::RegKey;
    fn open_root(&self, root: &Root, _: View) -> io::Result<Self::Key> {
        self.hive
            .open_subkey_with_flags(&root.path, winreg::enums::KEY_ENUMERATE_SUB_KEYS)
    }
    fn open_child(
        &self,
        key: &Self::Key,
        name: &OsStr,
        view: View,
        values: bool,
    ) -> io::Result<Self::Key> {
        self.native.open_child(key, name, view, values)
    }
    fn child_at(&self, key: &Self::Key, index: u32) -> io::Result<Option<Child>> {
        self.native.child_at(key, index)
    }
    fn value_at(&self, key: &Self::Key, index: u32) -> io::Result<Option<OsString>> {
        self.native.value_at(key, index)
    }
    fn read(&self, key: &Self::Key, name: &OsStr) -> io::Result<RawValue> {
        self.native.read(key, name)
    }
}
#[test]
fn native_private_application_hive_preserves_long_names_unknown_types_and_raw_bytes() {
    use std::os::windows::ffi::OsStrExt;
    let temp = tempfile::tempdir().unwrap();
    {
        let hive = winreg::RegKey::load_app_key(temp.path().join("fixture.hiv"), true).unwrap();
        let (key, _) = hive.create_subkey("Vendor\\Acme").unwrap();
        let set = |name: &str, kind: u32, bytes: &[u8]| {
            let wide: Vec<_> = OsStr::new(name).encode_wide().chain(Some(0)).collect();
            // SAFETY: this handle belongs exclusively to the newly created private application hive;
            // name and data buffers are valid for the lengths passed. No global registry root is modified.
            assert_eq!(
                unsafe {
                    windows_sys::Win32::System::Registry::RegSetValueExW(
                        key.raw_handle(),
                        wide.as_ptr(),
                        0,
                        kind,
                        bytes.as_ptr(),
                        bytes.len() as u32,
                    )
                },
                0
            );
        };
        set("Payload", 1, &bytes("A\0B\0"));
        let long_name = "N".repeat(6000);
        let raw = vec![0xAD; 256 * 1024];
        set(&long_name, 0xF00D, &raw);
        let cancelled = AtomicBool::new(false);
        let native = WindowsSource {
            cancelled: &cancelled,
        };
        let actual = native.read(&key, OsStr::new(&long_name)).unwrap();
        assert_eq!(actual.kind, 0xF00D);
        assert_eq!(actual.bytes, raw);
        let source = Application {
            hive: &hive,
            native,
        };
        let (summary, stdout, stderr) = run(
            &plan(&[
                "--key-root",
                "HKCU\\Vendor",
                "--key",
                "^Acme$",
                "--name",
                "^Payload$",
                "--data",
                "B",
                "--view",
                "64",
            ]),
            &source,
        );
        assert_eq!(summary.code(), 0, "{stderr}");
        assert!(stdout.contains("HKCU\\Vendor\\Acme") && stdout.contains("\"A\\0B\" (8 bytes)"));
        assert!(stderr.is_empty());
        let (summary, stdout, stderr) = run(
            &plan(&["--key-root", "HKCU\\Vendor", "-t", "0xF00D", "--view", "64"]),
            &source,
        );
        assert_eq!(summary.code(), 0, "{stderr}");
        assert!(
            stdout.contains(&long_name)
                && stdout.contains("UNKNOWN (61453)")
                && stdout.contains("262144 bytes")
                && stdout.contains("[preview truncated]")
        );
        let (summary, stdout, stderr) = run(
            &plan(&[
                "--key-root",
                "HKCU\\Vendor",
                "--data-not-set",
                "--view",
                "64",
            ]),
            &source,
        );
        assert_eq!(summary.code(), 0, "{stderr}");
        assert!(stdout.contains("Default value not set"));
    }
    temp.close().unwrap();
}

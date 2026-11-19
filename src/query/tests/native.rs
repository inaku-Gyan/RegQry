use super::*;
use std::os::windows::ffi::{OsStrExt, OsStringExt};
use winreg::RegKey;

fn private_hive(test: impl FnOnce(&RegKey, &Application<'_>)) {
    let temp = tempfile::tempdir().unwrap();
    {
        let hive = RegKey::load_app_key(temp.path().join("fixture.hiv"), true).unwrap();
        let cancelled = AtomicBool::new(false);
        let source = Application {
            hive: &hive,
            native: WindowsSource {
                cancelled: &cancelled,
            },
        };
        test(&hive, &source);
    }
    temp.close().unwrap();
}

fn set_raw(key: &RegKey, name: &OsStr, kind: u32, bytes: &[u8]) {
    use windows_sys::{Wdk::System::Registry::NtSetValueKey, Win32::Foundation::UNICODE_STRING};
    let mut wide: Vec<_> = name.encode_wide().collect();
    let length = u16::try_from(wide.len() * 2).unwrap();
    let name = UNICODE_STRING {
        Length: length,
        MaximumLength: length,
        Buffer: wide.as_mut_ptr(),
    };
    // RegSetValueExW requires terminated string input and can append a NUL for
    // legacy callers. Use the existing native binding for deliberately malformed
    // fixtures, then require an exact byte-for-byte readback below.
    // SAFETY: writes are restricted to this test's private hive; the counted name
    // and raw byte buffer stay live and initialized for their explicit lengths.
    assert_eq!(
        unsafe {
            NtSetValueKey(
                key.raw_handle(),
                &name,
                0,
                kind,
                bytes.as_ptr().cast(),
                u32::try_from(bytes.len()).unwrap(),
            )
        },
        0,
        "NtSetValueKey must create the exact private fixture"
    );
}

#[test]
fn native_malformed_data_remains_exact_and_only_necessary_interpretation_fails() {
    private_hive(|hive, source| {
        let key = hive.create_subkey("Data\\Cases").unwrap().0;
        let cases = [
            ("SzZero", 1, vec![], true),
            ("SzEmpty", 1, bytes("\0"), true),
            ("SzNoTerminator", 1, bytes("A"), true),
            ("SzInternalNul", 1, bytes("A\0B\0"), true),
            ("SzExtraNul", 1, bytes("A\0\0"), true),
            ("SzOdd", 1, vec![0x41], false),
            ("SzSurrogate", 1, vec![0, 0xD8], false),
            ("ExpandOdd", 2, vec![0x41], false),
            ("MultiEmptyOne", 7, bytes("\0"), true),
            ("MultiEmptyTwo", 7, bytes("\0\0"), true),
            ("MultiZero", 7, vec![], false),
            ("MultiMissingEnd", 7, bytes("A\0"), false),
            ("MultiExtraEnd", 7, bytes("A\0\0\0"), false),
            ("MultiPrematureEnd", 7, bytes("A\0\0B\0\0"), false),
            ("MultiSurrogate", 7, vec![0, 0xD8, 0, 0, 0, 0], false),
            ("DwordShort", 4, vec![1, 2, 3], false),
            ("DwordZeroLength", 4, vec![], false),
            ("DwordBigEndian", 5, vec![0x12, 0x34, 0x56, 0x78], true),
            ("QwordShort", 11, vec![0; 7], false),
            ("QwordLong", 11, vec![0; 9], false),
            ("BinaryZero", 3, vec![], true),
            ("UnknownZero", 0xF00D, vec![], true),
        ];
        for (name, kind, saved, decodable) in &cases {
            set_raw(&key, OsStr::new(name), *kind, saved);
            let raw = source.read(&key, OsStr::new(name)).unwrap();
            assert_eq!(raw.kind, *kind, "{name}");
            assert_eq!(
                raw.bytes, *saved,
                "{name}: Windows must not normalize the saved bytes"
            );
            assert_eq!(raw.decoded().is_ok(), *decodable, "{name}");
            let name_pattern = format!("^{name}$");
            let (summary, stdout, stderr) = run(
                &plan(&[
                    "--key-root",
                    "HKCU\\Data",
                    "--name",
                    &name_pattern,
                    "--view",
                    "64",
                ]),
                source,
            );
            assert_eq!(summary.code(), 0, "{name}: {stderr}");
            assert!(stderr.is_empty(), "{name}: {stderr}");
            assert!(
                stdout.contains(&format!("({} bytes)", saved.len())),
                "{name}: {stdout}"
            );
            if !decodable {
                assert!(
                    stdout.contains("interpretation unavailable"),
                    "{name}: {stdout}"
                );
                let hex = saved
                    .iter()
                    .map(|byte| format!("{byte:02X}"))
                    .collect::<Vec<_>>()
                    .join(" ");
                assert!(stdout.contains(&format!("hex[{hex}]")), "{name}: {stdout}");
                for predicate in ["--data=.", "--data-empty"] {
                    let (summary, stdout, stderr) = run(
                        &plan(&[
                            "--key-root",
                            "HKCU\\Data",
                            "--name",
                            &name_pattern,
                            predicate,
                            "--view",
                            "64",
                        ]),
                        source,
                    );
                    assert_eq!(summary.code(), 2, "{name} {predicate}: {stderr}");
                    assert!(stdout.is_empty());
                    assert!(stderr.contains("match value") && stderr.contains("search incomplete"));
                }
            }
        }
        for (predicate, expected_names) in [
            (
                "--data-zero-length",
                vec![
                    "SzZero",
                    "MultiZero",
                    "DwordZeroLength",
                    "BinaryZero",
                    "UnknownZero",
                ],
            ),
            (
                "--data-empty",
                vec![
                    "SzZero",
                    "SzEmpty",
                    "MultiEmptyOne",
                    "MultiEmptyTwo",
                    "BinaryZero",
                ],
            ),
        ] {
            let (summary, stdout, stderr) = run(
                &plan(&["--key-root", "HKCU\\Data", predicate, "--view", "64"]),
                source,
            );
            assert_eq!(
                summary.code(),
                if predicate == "--data-empty" { 2 } else { 0 },
                "{stderr}"
            );
            for (name, _, _, _) in &cases {
                assert_eq!(
                    stdout.contains(&format!("VALUE \"{name}\"")),
                    expected_names.contains(name),
                    "{predicate} {name}: {stdout}"
                );
            }
        }
        let (summary, stdout, stderr) = run(
            &plan(&[
                "--key-root",
                "HKCU\\Data",
                "--name=^SzOdd$",
                "--data=.",
                "--data-hex=41",
                "--view=64",
            ]),
            source,
        );
        assert_eq!(summary.code(), 0, "{stderr}");
        assert!(stdout.contains("interpretation unavailable") && stderr.is_empty());
        assert_eq!(
            run(
                &plan(&[
                    "--key-root",
                    "HKCU\\Data",
                    "--name=^DwordBigEndian$",
                    "--data=^305419896$",
                    "--view=64",
                ]),
                source
            )
            .0
            .code(),
            0
        );
        assert_eq!(
            run(
                &plan(&[
                    "--key-root",
                    "HKCU\\Data",
                    "--name=^ExpandOdd$",
                    "--data-expand=.",
                    "--view=64",
                ]),
                source
            )
            .0
            .code(),
            2
        );
    });
}

#[test]
fn native_unpaired_surrogates_in_key_and_value_names_are_not_replaced_for_matching() {
    private_hive(|hive, source| {
        let key_name = OsString::from_wide(&[0xD800]);
        let mut path = OsString::from("Keys\\");
        path.push(&key_name);
        let key = hive.create_subkey(&path).unwrap().0;
        set_raw(&key, OsStr::new("Normal"), 3, &[0xFE]);
        let parent = hive.open_subkey("Keys").unwrap();
        assert_eq!(source.child_at(&parent, 0).unwrap().unwrap().name, key_name);
        let (summary, stdout, stderr) = run(&plan(&["--key-root=HKCU\\Keys", "--view=64"]), source);
        assert_eq!(summary.code(), 0, "{stderr}");
        assert!(stdout.contains("\\u16{D800}") && !stdout.contains('\u{FFFD}'));
        let (summary, stdout, stderr) = run(
            &plan(&["--key-root=HKCU\\Keys", "--key=.", "--view=64"]),
            source,
        );
        assert_eq!(summary.code(), 2);
        assert!(stdout.is_empty() && stderr.contains("match key"));
        assert_eq!(
            run(
                &plan(&["--key-root=HKCU\\Keys", "-t=binary", "--view=64"]),
                source
            )
            .0
            .code(),
            0
        );

        let value_key = hive.create_subkey("Names\\Cases").unwrap().0;
        let value_name = OsString::from_wide(&[b'A' as u16, 0xDC00, b'B' as u16]);
        set_raw(&value_key, &value_name, 3, &[0xFE]);
        assert_eq!(source.value_at(&value_key, 0).unwrap().unwrap(), value_name);
        let (summary, stdout, stderr) = run(
            &plan(&["--key-root=HKCU\\Names", "--data-hex=FE", "--view=64"]),
            source,
        );
        assert_eq!(summary.code(), 0, "{stderr}");
        assert!(stdout.contains("A\\u16{DC00}B") && !stdout.contains('\u{FFFD}'));
        assert_eq!(
            run(
                &plan(&["--key-root=HKCU\\Names", "--name=A", "--view=64",]),
                source
            )
            .0
            .code(),
            2
        );
        // The data group can disqualify a candidate without interpreting its name.
        let (summary, stdout, stderr) = run(
            &plan(&[
                "--key-root=HKCU\\Names",
                "--name=A",
                "--data-hex=FF",
                "--view=64",
            ]),
            source,
        );
        assert_eq!(summary.code(), 1);
        assert!(stdout.is_empty() && stderr.is_empty());
    });
}

struct RemovedAfterEnumeration<'a> {
    application: &'a Application<'a>,
    delete_key: bool,
    removed: Cell<bool>,
}
impl Source for RemovedAfterEnumeration<'_> {
    type Key = RegKey;
    fn open_root(&self, root: &Root, view: View) -> io::Result<Self::Key> {
        self.application.open_root(root, view)
    }
    fn open_child(
        &self,
        key: &Self::Key,
        name: &OsStr,
        view: View,
        values: bool,
    ) -> io::Result<Self::Key> {
        self.application.open_child(key, name, view, values)
    }
    fn child_at(&self, key: &Self::Key, index: u32) -> io::Result<Option<Child>> {
        self.application.child_at(key, index)
    }
    fn value_at(&self, key: &Self::Key, index: u32) -> io::Result<Option<OsString>> {
        let entry = self.application.value_at(key, index)?;
        if let Some(name) = &entry
            && !self.removed.replace(true)
        {
            if self.delete_key {
                self.application.hive.delete_subkey("Race\\Gone")?;
            } else {
                let writable = self
                    .application
                    .hive
                    .open_subkey_with_flags("Race\\Gone", winreg::enums::KEY_SET_VALUE)?;
                writable.delete_value(name)?;
            }
        }
        Ok(entry)
    }
    fn read(&self, key: &Self::Key, name: &OsStr) -> io::Result<RawValue> {
        self.application.read(key, name)
    }
}

#[test]
fn native_removal_between_enumeration_and_read_reports_incomplete_and_keeps_other_roots() {
    for delete_key in [false, true] {
        private_hive(|hive, application| {
            let key = hive.create_subkey("Race\\Gone").unwrap().0;
            set_raw(&key, OsStr::new("Data"), 3, &[0xFE]);
            let other = hive.create_subkey("Other\\Readable").unwrap().0;
            set_raw(&other, OsStr::new("Data"), 3, &[0xAD]);
            let source = RemovedAfterEnumeration {
                application,
                delete_key,
                removed: Cell::new(false),
            };
            let (summary, stdout, stderr) = run(
                &plan(&[
                    "--key-root=HKCU\\Race",
                    "--key-root=HKCU\\Other",
                    "-t=binary",
                    "--view=64",
                ]),
                &source,
            );
            assert_eq!(summary.code(), 2, "{stderr}");
            assert!(source.removed.get());
            assert!(stdout.contains("HKCU\\Other\\Readable") && stdout.contains("hex[AD]"));
            assert!(!stdout.contains("Default value not set") && !stdout.contains("UNSET"));
            let code = if delete_key {
                "Win32 1018:"
            } else {
                "Win32 2:"
            };
            assert!(
                stderr.contains(code)
                    && stderr.contains("read value")
                    && stderr.contains("search incomplete"),
                "{stderr}"
            );
        });
    }
}

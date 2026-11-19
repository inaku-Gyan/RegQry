#![cfg(windows)]
mod support;
use std::{ffi::OsStr, io, path::PathBuf, time::Duration};
use support::vm::*;
use windows_sys::Win32::System::Registry::*;
use winreg::RegKey;

fn sddl(context: &Context, access: u32) -> String {
    // Protected, non-inheriting DACL: setup/System retain full access; the ordinary SID gets exactly access.
    format!(
        "O:BAG:BAD:P(A;;KA;;;BA)(A;;KA;;;SY)(A;;0x{access:x};;;{})",
        context.sid
    )
}
fn child(parent: &RegKey, name: &str, view: u32, context: &Context, access: u32) -> RegKey {
    let key = create(parent, OsStr::new(name), view, Some(&sddl(context, access))).unwrap();
    assert_admin_owner(&key);
    mark(&key, &context.nonce);
    key
}
fn cli(args: &[&str], status: i32) -> (String, String) {
    let bin = PathBuf::from(
        std::env::var_os("REGQRY_TEST_BIN").expect("runner must bind the bundled CLI"),
    );
    let output = assert_cmd::Command::new(bin)
        .args(args)
        .timeout(Duration::from_secs(15))
        .assert()
        .code(status)
        .get_output()
        .clone();
    let stdout = String::from_utf8(output.stdout).unwrap();
    let stderr = String::from_utf8(output.stderr).unwrap();
    println!("QUERY args={args:?} exit={status}\nSTDOUT\n{stdout}STDERR\n{stderr}END_QUERY");
    if status < 2 {
        assert!(stderr.is_empty(), "{stderr}");
    } else {
        assert!(stderr.contains("search incomplete"), "{stderr}");
    }
    (stdout, stderr)
}
fn machine_path(context: &Context, suffix: &str) -> String {
    format!("HKLM\\Software\\{}\\{suffix}", context.base())
}

#[test]
fn vm_context_rejects_missing_and_unsafe_identities_without_registry_access() {
    assert!(Context::parse(|_| None, "prepare").is_err());
    let lookup = |name: &str| {
        Some(match name {
            "REGQRY_VM_CONFIRM" => CONFIRM.into(),
            "REGQRY_VM_PHASE" => "prepare".into(),
            "REGQRY_VM_ID" => "a".repeat(32),
            "REGQRY_VM_NONCE" => "b".repeat(64),
            "REGQRY_VM_QUERY_SID" => "S-1-5-21-1-2-3-1000".into(),
            "REGQRY_VM_ROLLBACK" => "snapshot-before-regqry".into(),
            _ => unreachable!(),
        })
    };
    assert!(Context::parse(lookup, "prepare").is_ok());
    assert!(Context::parse(lookup, "query").is_err());
    for (name, invalid) in [
        ("REGQRY_VM_ID", "..\\Software"),
        ("REGQRY_VM_NONCE", "0"),
        ("REGQRY_VM_QUERY_SID", "BA"),
        ("REGQRY_VM_ROLLBACK", " "),
        ("REGQRY_VM_CONFIRM", "yes"),
    ] {
        assert!(
            Context::parse(
                |key| if key == name {
                    Some(invalid.into())
                } else {
                    lookup(key)
                },
                "prepare"
            )
            .is_err()
        );
    }
}

#[test]
fn private_fixture_collision_preserves_existing_data_and_marker() {
    let temp = tempfile::tempdir().unwrap();
    {
        let hive = RegKey::load_app_key(temp.path().join("ownership.hiv"), true).unwrap();
        let key = create(&hive, OsStr::new("Fixture"), 0, None).unwrap();
        mark(&key, &[1; 32]);
        text(&key, "Payload", "saved");
        let before = raw(&key, "Payload");
        assert_eq!(
            create(&hive, OsStr::new("Fixture"), 0, None)
                .err()
                .unwrap()
                .kind(),
            io::ErrorKind::AlreadyExists
        );
        assert_marker(&key, &[1; 32]);
        assert_eq!(raw(&key, "Payload"), before);
        // Keep Win32 string-writing preconditions here. Deliberately malformed
        // strings use NtSetValueKey in the internal native data-layout tests.
        set(&key, OsStr::new("Raw"), 0xF00D, &[0x41]);
        assert_eq!(raw(&key, "Raw"), (0xF00D, vec![0x41]));
        assert!(create(&hive, OsStr::new("..\\Escape"), 0, None).is_err());
    }
    temp.close().unwrap();
}

#[test]
fn application_hive_rejects_individual_security_descriptors() {
    let (sid, elevated) = token().unwrap();
    println!("PRIVATE_HIVE_TOKEN sid={sid} elevated={elevated}");
    let temp = tempfile::tempdir().unwrap();
    {
        let hive = RegKey::load_app_key(temp.path().join("security.hiv"), true).unwrap();
        let failure = create(
            &hive,
            OsStr::new("Owned"),
            0,
            Some(&format!("O:{sid}D:P(A;;KA;;;{sid})")),
        )
        .err()
        .unwrap();
        // Application hives use the file's security descriptor, not independent per-key ACLs.
        assert_eq!(failure.raw_os_error(), Some(5));
        let key = create(&hive, OsStr::new("Inherited"), 0, None).unwrap();
        assert!(owner(&key).starts_with("S-1-"));
        mark(&key, &[2; 32]);
        assert_marker(&key, &[2; 32]);
        assert!(create(&hive, OsStr::new("Invalid"), 0, Some("invalid SDDL")).is_err());
    }
    temp.close().unwrap();
}

#[test]
#[ignore = "explicit disposable VM: elevated preparation; never ordinary CI"]
fn vm_prepare() {
    let context = Context::require("prepare");
    // Open existing parents only. Every mutated component below must be newly created.
    let machine = RegKey::predef(HKEY_LOCAL_MACHINE);
    for view in [KEY_WOW64_32KEY, KEY_WOW64_64KEY] {
        let parent = machine
            .open_subkey_with_flags("Software", KEY_CREATE_SUB_KEY | view)
            .unwrap();
        let root = child(&parent, &context.base(), view, &context, 9);
        let views = child(&root, "Views", view, &context, 9);
        text(&views, "Sentinel", "root-must-not-be-returned");
        let leaf = child(&views, "Leaf", view, &context, 9);
        text(
            &leaf,
            "Sentinel",
            if view == KEY_WOW64_32KEY {
                "physical-view-32"
            } else {
                "physical-view-64"
            },
        );
        let acl = child(&root, "Acl", view, &context, 9);
        for (name, access) in [
            ("ValuesOnly", 1),
            ("EnumOnly", 8),
            ("Denied", 0),
            ("Readable", 9),
        ] {
            let node = child(&acl, name, view, &context, access);
            text(&node, "Payload", name);
            if name == "EnumOnly" {
                let leaf = child(&node, "Leaf", view, &context, 9);
                text(&leaf, "Payload", "past-enum-only");
            }
        }
        if view == KEY_WOW64_64KEY {
            let target = child(&root, "Target", view, &context, 9);
            let branch = child(&target, "Branch", view, &context, 9);
            let leaf = child(&branch, "Leaf", view, &context, 9);
            text(&leaf, "OutsideMarker", "owned-outside-search-root");
            let links = child(&root, "Links", view, &context, 9);
            let native = format!("\\Registry\\Machine\\Software\\{}", context.base());
            for (name, target) in [
                ("Source", format!("{native}\\Target")),
                ("Cycle", format!("{native}\\Links")),
                ("Broken", format!("{native}\\Missing")),
            ] {
                link(&links, name, view, &sddl(&context, 9), &target, &context);
            }
            let fake = child(&links, "Pretender", view, &context, 9);
            set(
                &fake,
                OsStr::new("SymbolicLinkValue"),
                REG_LINK,
                &format!("{native}\\Target")
                    .encode_utf16()
                    .flat_map(u16::to_le_bytes)
                    .collect::<Vec<_>>(),
            );
            let leaf = child(&fake, "Leaf", view, &context, 9);
            text(&leaf, "InsideMarker", "normal-key-must-recurse");
        }
    }
    let users = RegKey::predef(HKEY_USERS);
    let user_software = users
        .open_subkey_with_flags(
            format!("{}\\Software", context.sid),
            KEY_CREATE_SUB_KEY | KEY_WOW64_64KEY,
        )
        .unwrap();
    let root = child(
        &user_software,
        &context.base(),
        KEY_WOW64_64KEY,
        &context,
        9,
    );
    let outer = child(&root, "Outer", KEY_WOW64_64KEY, &context, 9);
    text(&outer, "Payload", "excluded-root-value");
    let leaf = child(&outer, "Leaf", KEY_WOW64_64KEY, &context, 9);
    text(&leaf, "A\\B", "literal-name");
    let classes = users
        .open_subkey_with_flags(
            format!("{}\\Software\\Classes", context.sid),
            KEY_CREATE_SUB_KEY | KEY_WOW64_64KEY,
        )
        .unwrap();
    let root = child(&classes, &context.base(), KEY_WOW64_64KEY, &context, 9);
    let leaf = child(&root, "Leaf", KEY_WOW64_64KEY, &context, 9);
    text(&leaf, "Payload", "user-classes-merged-view");
    let root = child(
        &RegKey::predef(HKEY_CURRENT_CONFIG),
        &context.base(),
        KEY_WOW64_64KEY,
        &context,
        9,
    );
    let leaf = child(&root, "Leaf", KEY_WOW64_64KEY, &context, 9);
    text(&leaf, "Payload", "current-hardware-profile");
    println!(
        "PREPARATION_COMPLETE id={} cleanup=VM_ROLLBACK_REQUIRED",
        context.id
    );
}

#[test]
#[ignore = "explicit disposable VM: requires prepared fixtures and ordinary query token"]
fn vm_roots_and_physical_views() {
    let context = Context::require("query");
    for view in [KEY_WOW64_32KEY, KEY_WOW64_64KEY] {
        context.machine(view);
    }
    for (hive, path) in [
        (HKEY_CURRENT_USER, format!("Software\\{}", context.base())),
        (
            HKEY_USERS,
            format!("{}\\Software\\{}", context.sid, context.base()),
        ),
        (HKEY_CLASSES_ROOT, context.base()),
        (HKEY_CURRENT_CONFIG, context.base()),
    ] {
        let root = RegKey::predef(hive)
            .open_subkey_with_options_flags(
                path,
                REG_OPTION_OPEN_LINK,
                KEY_QUERY_VALUE | KEY_WOW64_64KEY,
            )
            .unwrap();
        assert_marker(&root, &context.nonce);
    }
    let path = machine_path(&context, "Views");
    let (both, _) = cli(&["--key-root", &path, "--name", "^Sentinel$"], 0);
    for view in ["32", "64"] {
        assert!(both.contains(&format!("[{view}] {path}\\Leaf\n")));
        assert!(both.contains(&format!("\"physical-view-{view}\"")));
        let (one, _) = cli(
            &[
                "--key-root",
                &path,
                "--name",
                "^Sentinel$",
                "--view",
                view,
                "--view",
                view,
            ],
            0,
        );
        assert_eq!(one.matches("VALUE ").count(), 1);
        assert!(one.contains(&format!("physical-view-{view}")));
        assert!(!one.contains("root-must-not-be-returned"));
    }
    assert_eq!(both.matches("VALUE ").count(), 2);
    let user = format!("HKCU\\Software\\{}", context.base());
    let outer = format!("{user}\\Outer");
    let (out, _) = cli(
        &[
            "--key-root",
            &user,
            "--key-root",
            &outer,
            "--key",
            "^Leaf$",
            "--view",
            "64",
        ],
        0,
    );
    assert_eq!(out, format!("KEY [64] {outer}\\Leaf\n"));
    let (out, _) = cli(
        &["--key-root", &outer, "--name", "^Payload$", "--view", "64"],
        1,
    );
    assert!(out.is_empty());
    // A backslash in a value name is a literal value-name character.
    let (out, _) = cli(
        &["--key-root", &outer, "--name-glob", r"A\B", "--view", "64"],
        0,
    );
    assert!(out.contains(r#"VALUE "A\\B""#));
    for (path, data) in [
        (
            format!("HKU\\{}\\Software\\{}\\Outer", context.sid, context.base()),
            "literal-name",
        ),
        (
            format!("HKCR\\{}", context.base()),
            "user-classes-merged-view",
        ),
        (
            format!("HKCC\\{}", context.base()),
            "current-hardware-profile",
        ),
    ] {
        let (out, _) = cli(&["--key-root", &path, "--data", data, "--view", "64"], 0);
        assert!(out.contains(data));
        if path.starts_with("HKCR") {
            assert!(out.contains("merged view"));
        }
    }
}

#[test]
#[ignore = "explicit disposable VM: requires prepared ACLs and ordinary query token"]
fn vm_minimum_permissions_and_partial_failure() {
    let context = Context::require("query");
    context.machine(KEY_WOW64_64KEY);
    let parent = RegKey::predef(HKEY_LOCAL_MACHINE);
    let root = format!("Software\\{}\\Acl", context.base());
    // Independently prove this token cannot open KEY_READ; success would invalidate the fixture.
    for (name, granted, denied) in [
        ("ValuesOnly", KEY_QUERY_VALUE, KEY_ENUMERATE_SUB_KEYS),
        ("EnumOnly", KEY_ENUMERATE_SUB_KEYS, KEY_QUERY_VALUE),
    ] {
        let path = format!("{root}\\{name}");
        parent
            .open_subkey_with_flags(&path, granted | KEY_WOW64_64KEY)
            .unwrap();
        for rights in [denied, KEY_READ] {
            assert_eq!(
                parent
                    .open_subkey_with_flags(&path, rights | KEY_WOW64_64KEY)
                    .err()
                    .unwrap()
                    .raw_os_error(),
                Some(5)
            );
        }
        println!("ACL_VERIFIED {name} granted={granted:#x} denied={denied:#x} KEY_READ=denied");
    }
    let path = machine_path(&context, "Acl");
    let (out, err) = cli(
        &["--key-root", &path, "--name", "^Payload$", "--view", "64"],
        2,
    );
    for text in ["ValuesOnly", "past-enum-only", "Readable"] {
        assert!(out.contains(&format!("\"{text}\"")), "{out}");
    }
    assert!(!out.contains("\"Denied\""));
    assert!(err.contains("Win32 5") && err.contains("ValuesOnly") && err.contains("Denied"));
    let enum_root = format!("{path}\\EnumOnly");
    let (out, _) = cli(&["--key-root", &enum_root, "--view", "64"], 0);
    assert_eq!(out, format!("KEY [64] {enum_root}\\Leaf\n"));
    let (out, _) = cli(
        &[
            "--key-root",
            &path,
            "--key",
            r"^EnumOnly\\Leaf$",
            "--name",
            "^Payload$",
            "--view",
            "64",
        ],
        2,
    );
    // Denied/ValuesOnly still prevent a complete recursive search even when their key filters fail.
    assert!(out.contains("past-enum-only"));
}

#[test]
#[ignore = "explicit disposable VM: creates links during preparation; rollback is the cleanup boundary"]
fn vm_link_sources_explicit_aliases_cycles_and_lookalikes() {
    let context = Context::require("query");
    context.machine(KEY_WOW64_64KEY);
    let path = machine_path(&context, "Links");
    let (out, _) = cli(&["--key-root", &path, "--view", "64"], 0);
    let mut actual = out.lines().collect::<Vec<_>>();
    actual.sort_unstable();
    let mut expected = ["Source", "Cycle", "Broken", "Pretender", "Pretender\\Leaf"]
        .map(|name| format!("KEY [64] {path}\\{name}"));
    expected.sort_unstable();
    assert_eq!(actual, expected);
    cli(
        &[
            "--key-root",
            &path,
            "--name",
            "^OutsideMarker$",
            "--view",
            "64",
        ],
        1,
    );
    let (out, _) = cli(
        &[
            "--key-root",
            &path,
            "--name",
            "^InsideMarker$",
            "--view",
            "64",
        ],
        0,
    );
    assert!(out.contains("normal-key-must-recurse"));
    let (out, _) = cli(
        &[
            "--key-root",
            &path,
            "--name",
            "^SymbolicLinkValue$",
            "-t",
            "link",
            "--view",
            "64",
        ],
        0,
    );
    assert_eq!(out.matches("VALUE ").count(), 4);
    let alias = format!("{path}\\Source");
    let (out, _) = cli(
        &[
            "--key-root",
            &alias,
            "--name",
            "^OutsideMarker$",
            "--view",
            "64",
        ],
        0,
    );
    assert!(out.starts_with(&format!("[64] {alias}\\Branch\\Leaf\n")));
    assert!(out.contains("owned-outside-search-root"));
    cli(
        &["--key-root", &format!("{path}\\Broken"), "--view", "64"],
        2,
    );
}

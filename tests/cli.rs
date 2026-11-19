#![cfg(windows)]

use assert_cmd::Command;
use std::path::PathBuf;

fn command() -> Command {
    let path = if let Some(path) = std::env::var_os("REGQRY_TEST_BIN") {
        PathBuf::from(path)
    } else {
        let test = std::env::current_exe().unwrap();
        test.ancestors()
            .skip(1)
            .take(6)
            .map(|directory| directory.join("regqry.exe"))
            .find(|candidate| candidate.is_file())
            .expect("CLI not found beside the test or in Cargo output; set REGQRY_TEST_BIN")
    };
    assert!(
        path.is_file(),
        "CLI not found: {}; set REGQRY_TEST_BIN",
        path.display()
    );
    Command::new(path)
}

#[test]
fn bare_and_short_help_do_not_query() {
    let bare = command().assert().success().get_output().clone();
    let short = command().arg("-h").assert().success().get_output().clone();
    assert!(!bare.stdout.is_empty());
    assert!(bare.stderr.is_empty());
    assert!(short.stderr.is_empty());
    assert!(
        String::from_utf8(bare.stdout)
            .unwrap()
            .contains("regqry [QUERY OPTIONS]")
    );
    assert!(
        !String::from_utf8(short.stdout)
            .unwrap()
            .contains("MATCHING\n")
    );
}

#[test]
fn long_help_lists_aliases_and_contract() {
    let result = command()
        .arg("--help")
        .assert()
        .success()
        .get_output()
        .clone();
    assert!(result.stderr.is_empty());
    let help = String::from_utf8(result.stdout).unwrap();
    for text in [
        "MATCHING",
        "data-case-insensitive",
        "data-glob-case-insensitive",
        "130",
        "HKCU",
        "HKLM",
        "descendants",
    ] {
        assert!(help.contains(text), "{text}");
    }
}

#[test]
fn version_is_manifest_version() {
    command()
        .arg("--version")
        .assert()
        .success()
        .stdout(format!("regqry {}\n", env!("CARGO_PKG_VERSION")))
        .stderr("");
}

#[test]
fn invalid_inputs_fail_before_query_execution() {
    for args in [
        vec!["search"],
        vec!["show", "HKCU"],
        vec!["--name-regex", "x"],
        vec!["--data-regex", "x"],
        vec!["--name"],
        vec!["--name", "("],
        vec!["--data", "(?=x)"],
        vec!["--name-glob", "[z-a]"],
        vec!["--data-glob", "[[:digit:]]"],
        vec!["--view", "16"],
        vec!["--key-root="],
        vec!["--key-root", "HKCU:"],
        vec!["--type", "4294967296"],
        vec!["--type=sz,dword"],
        vec!["--data-hex="],
        vec!["--data-hex=F"],
        vec!["--key-modified-after=1year"],
    ] {
        let result = command().args(&args).assert().code(2).get_output().clone();
        assert!(result.stdout.is_empty(), "{args:?}");
        let error = String::from_utf8(result.stderr).unwrap();
        assert!(
            !error.contains("query execution is not implemented"),
            "{args:?}"
        );
        assert!(error.contains("error:"), "{args:?}");
    }
}

#[test]
fn otherwise_valid_patterns_are_validated_before_registry_access() {
    for mut args in [
        vec!["--view=64"],
        vec!["--name="],
        vec!["--name-glob="],
        vec!["--key-root", r"HKCU\Software", "--key-glob", r"**\Acme"],
        vec!["--data=-legacy"],
        vec!["--data-not-set", "--data-not-set"],
    ] {
        args.push("--key-root=HKCU:");
        let result = command()
            .args(args)
            .assert()
            .code(2)
            .stdout("")
            .get_output()
            .clone();
        let error = String::from_utf8(result.stderr).unwrap();
        assert!(error.contains("ROOT must start"), "{error}");
    }
}

#[test]
fn redirected_help_is_utf8_without_ansi_sequences() {
    let temp = tempfile::tempdir().unwrap();
    let output = temp.path().join("help.txt");
    let mut child = std::process::Command::new(command().get_program())
        .arg("--help")
        .stdout(std::fs::File::create(&output).unwrap())
        .spawn()
        .unwrap();
    assert!(child.wait().unwrap().success());
    let bytes = std::fs::read(output).unwrap();
    assert!(!bytes.contains(&0x1b));
    assert!(String::from_utf8(bytes).unwrap().contains("MATCHING"));
}

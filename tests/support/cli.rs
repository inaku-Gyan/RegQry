use std::path::PathBuf;

pub fn binary() -> PathBuf {
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
        path.is_absolute() && path.is_file(),
        "CLI not found: {path:?}; set REGQRY_TEST_BIN"
    );
    path
}

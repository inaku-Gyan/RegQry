# RegQry development test bundle

Extract the whole ZIP, then run `./run-tests.ps1` from Windows PowerShell 5.1 or PowerShell 7. Use `-ReportDirectory C:\path\to\new-results` to choose a new results directory outside the bundle. The default is a fresh directory under the current user's temporary directory. No Cargo, rustc, Build Tools, network access, elevation, or globally navigable registry fixture is required.

The runner checks every declared file's SHA-256 and rejects extra files before starting the CLI or test executables. Pass `-ExpectedManifestSha256 HASH` to check the manifest against a separately retained identity. Keep that hash and the original ZIP hash with external evidence; these hashes establish byte identity, not publisher authentication. The target must match native Windows architecture. Emulated execution is rejected for this check.

The bundle contains the actual CLI, Rust test harnesses, their complete test inventory, DLL import/header reports, and runner scripts. Tests use memory, temporary files, and a private application hive that unloads when its handles close. Globally navigable root/view/ACL/link tests are separate disposable-VM work. Ignored tests stay ignored and are recorded separately. Reports contain the bundle/source identities, actual Windows version, process/native architecture, token elevation, PowerShell version, harness arguments, exit codes, and captured UTF-8 streams.

A timeout is a test failure, not a completed query. A successful run verifies this test layer on the recorded machine. It does not prove the formal minimum/clean-system, ordinary-user, real-console, or release matrix. These development bundles are not frozen release candidates and are not public release assets; final release packaging must add the reviewed third-party distribution materials.

`dll-imports.json` records direct and delay-load imports inspected by MSVC dumpbin. Static CRT and reviewed system imports are required. This does not prove dynamically loaded DLLs, imported API availability, or clean minimum-system execution.

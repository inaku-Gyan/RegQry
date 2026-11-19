# Contributing

Use the Rust version pinned in `rust-toolchain.toml`, with rustfmt and Clippy. Development is native Windows MSVC; install the matching C++ build tools and Windows SDK. There is one supported compiler version, with no separate older MSRV test line.

Run the local checks from PowerShell 5.1 or PowerShell 7:

```powershell
./scripts/check.ps1
```

For changes in progress, `./scripts/check.ps1 -AllowDirty` permits Cargo packaging of an uncommitted checkout. Release packaging always requires a clean tag. Individual checks are available with `-Check format`, `lint`, `test`, or `package`. Native CI runs on x64 and ARM64; the script can enforce a native compiler host with `-ExpectedHost`.

Native CI also builds static-CRT user and test ZIPs from the Cargo archive, collects their production/test-specific license materials, checks PE imports, runs relocated assets without Cargo on PATH, and probes rejected file/inventory/architecture states. See [portable test commands](docs/testing.md) and [asset construction](docs/releasing.md). These hosted runs do not replace minimum-system or clean-system acceptance.

The [real registry VM suite](docs/vm-testing.md) uses separate elevated setup and ordinary-user query phases. Its tests are ignored by default. CI checks the opt-in/identity guards without creating global fixtures; VM rollback/destruction remains a required external cleanup step.

The checks use locked dependencies, rustfmt, default Clippy, and warnings as errors. Add narrowly scoped lint exceptions only with a reason. Necessary unsafe Windows calls must state their SAFETY invariants. Add tests for observable contracts and meaningful failure cases; there is no global coverage percentage requirement.

Dependency checks use the fixed cargo-deny version in `scripts/tools.psd1`. Install it with Cargo or use that exact official prebuilt release already installed elsewhere:

```powershell
$version = (Import-PowerShellDataFile ./scripts/tools.psd1).CargoDeny
cargo install --version $version --locked cargo-deny
./scripts/check-dependencies.ps1
```

The audit creates a fresh Cargo home and advisory database for each run, explicitly fetches both database and index, then checks advisories, duplicate versions, licenses, and sources for both Windows targets, including test dependencies. Fetch failure blocks the check. Reports are written under `artifacts/`; a pass is current to that run, not an assurance about future advisories. See `deny.toml` for policy. Exceptions must be scoped and document a reason and review deadline; advisory exceptions use the tool's native expiry support.

Commit `Cargo.lock`. Compiler, dependency/features, tool, or action upgrades go through PR review. Check behavior as well as dependency versions. Add a dependency when its implementation is needed; registry and cancellation dependencies now accompany their query implementations.

Asset construction requires cargo-about 0.9.3 from `scripts/tools.psd1` and the pinned toolchain's `rust-docs` component. Install that exact version with `cargo install --version 0.9.3 --locked cargo-about`, or pass an existing official executable using `-CargoAbout`. Its graph filtering and hash-checked clarifications are reviewed configuration, not a substitute for the separate dependency audit. Read [distribution materials](docs/distribution.md) when changing dependency licenses or carried assets.

Use Conventional Commit categories such as `feat`, `fix`, `docs`, `chore`, and `ci` for principal changes and PR titles. Use ordinary merge commits, with Git's normal merge message. No squash-only rule or hard gate on every intermediate/historical commit applies. Local hooks are optional.

Keep public documentation in English. Chinese domain/planning material remains valid. Update user-visible behavior, the matching reference, and the changelog together. Stable guidance belongs in Git; `.scratch/` stays local. See [testing](docs/testing.md), [architecture](docs/architecture.md), and [compatibility](docs/compatibility.md).

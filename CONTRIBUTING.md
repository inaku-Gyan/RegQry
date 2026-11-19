# Contributing

Use the Rust version pinned in `rust-toolchain.toml`, with rustfmt and Clippy. Development is native Windows MSVC; install the matching C++ build tools and Windows SDK. There is one supported compiler version, with no separate older MSRV test line.

Run the local checks from PowerShell 5.1 or PowerShell 7:

```powershell
./scripts/check.ps1
```

For changes in progress, `./scripts/check.ps1 -AllowDirty` permits Cargo packaging of an uncommitted checkout. Release packaging always requires a clean tag. Individual checks are available with `-Check format`, `lint`, `test`, or `package`. Native CI runs on x64 and ARM64; the script can enforce a native compiler host with `-ExpectedHost`.

Native CI also builds static-CRT user and test ZIPs from the Cargo archive, using the same MSVC/SDK selection wrapper as tagged release construction on both architectures. It preserves selected tool/library identities, collects production/test-specific license materials, checks PE imports, runs relocated assets without Cargo on PATH, and probes rejected file/inventory/architecture states. See [portable test commands](docs/testing.md) and [asset construction](docs/releasing.md). Hosted checks record their actual systems; minimum/clean clients are unexecuted compatibility targets outside the first-release gates.

Release-script changes also run `./scripts/test-release-gates.ps1 -ReportDirectory artifacts/release-gates`. This uses synthetic records and mocked remote/clock boundaries, including actual gh argument constraints, delayed readback, interrupted uploads/publication and evidence rejection. It performs no real release, credential exchange or global registry writes. Native x64 CI separately runs `check-github-api.ps1` against its current workflow, using a Contents-read/Actions-read token and the actual gh executable. That read-only check compares multi-page job responses with the complete list and inspects artifact metadata; its report is retained with the native records. Read [the release route](docs/releasing.md) and [evidence contract](docs/release-evidence.md) before changing those gates.

The [real registry VM suite](docs/vm-testing.md) uses separate elevated setup and ordinary-user query phases. Its tests are ignored by default in ordinary builds. Dedicated [hosted acceptance jobs](docs/hosted-acceptance.md) explicitly create private fixtures in fresh Actions VMs and run both the bundled and independently installed CLI as a standard user. Original job provenance and the provider's automatic-decommissioning contract supply lifecycle evidence without an invented destruction receipt. Never run this suite on a workstation.

The checks use locked dependencies, rustfmt, default Clippy, and warnings as errors. Add narrowly scoped lint exceptions only with a reason. Necessary unsafe Windows calls must state their SAFETY invariants. Add tests for observable contracts and meaningful failure cases; there is no global coverage percentage requirement.

Dependency checks use the fixed cargo-deny version in `scripts/tools.psd1`. Install it with Cargo or use that exact official prebuilt release already installed elsewhere:

```powershell
$version = (Import-PowerShellDataFile ./scripts/tools.psd1).CargoDeny
cargo install --version $version --locked cargo-deny
./scripts/check-dependencies.ps1
```

The audit creates a fresh Cargo home and advisory database for each run, explicitly fetches both database and index, then checks advisories, duplicate versions, licenses, and sources for both Windows targets, including test dependencies. Fetch failure blocks the check. Reports are written under `artifacts/`; a pass is current to that run, not an assurance about future advisories. See `deny.toml` for policy. Exceptions must be scoped and document a reason and review deadline; advisory exceptions use the tool's native expiry support.

Commit `Cargo.lock`. Compiler, dependency/features, tool, or action upgrades go through PR review. Check behavior as well as dependency versions. Add a dependency when its implementation is needed; registry and cancellation dependencies now accompany their query implementations.

Asset construction requires cargo-about 0.9.3 from `scripts/tools.psd1` and the pinned toolchain's `rust-docs` component. Install that exact version with `cargo install --version 0.9.3 --locked --features cli cargo-about`, or pass an existing official executable using `-CargoAbout`. The `cli` feature is required to install its executable. Its graph filtering and hash-checked clarifications are reviewed configuration, not a substitute for the separate dependency audit. Read [distribution materials](docs/distribution.md) when changing dependency licenses or carried assets.

Use Conventional Commit categories such as `feat`, `fix`, `docs`, `chore`, and `ci` for principal changes and PR titles. Use ordinary merge commits, with Git's normal merge message. No squash-only rule or hard gate on every intermediate/historical commit applies. Local hooks are optional.

Keep public documentation in English. Chinese domain/planning material remains valid. Update user-visible behavior, the matching reference, and the changelog together. Stable guidance belongs in Git; `.scratch/` stays local. See [testing](docs/testing.md), [architecture](docs/architecture.md), and [compatibility](docs/compatibility.md).

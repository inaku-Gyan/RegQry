# Contributing

Use the Rust version pinned in `rust-toolchain.toml`, with rustfmt and Clippy. Development is native Windows MSVC; install the matching C++ build tools and Windows SDK. There is one supported compiler version, with no separate older MSRV test line.

Run the local checks from PowerShell 5.1 or PowerShell 7:

```powershell
./scripts/check.ps1
```

For changes in progress, `./scripts/check.ps1 -AllowDirty` permits Cargo packaging of an uncommitted checkout. Release packaging always requires a clean tag. Individual checks are available with `-Check format`, `lint`, `test`, or `package`. Native CI runs on x64 and ARM64; the script can enforce a native compiler host with `-ExpectedHost`.

The checks use locked dependencies, rustfmt, default Clippy, and warnings as errors. Add narrowly scoped lint exceptions only with a reason. Necessary unsafe Windows calls must state their SAFETY invariants. Add tests for observable contracts and meaningful failure cases; there is no global coverage percentage requirement.

Dependency checks use the fixed cargo-deny version in `scripts/tools.psd1`. Install it with Cargo or use that exact official prebuilt release already installed elsewhere:

```powershell
$version = (Import-PowerShellDataFile ./scripts/tools.psd1).CargoDeny
cargo install --version $version --locked cargo-deny
./scripts/check-dependencies.ps1
```

The audit creates a fresh Cargo home and advisory database for each run, explicitly fetches both database and index, then checks advisories, duplicate versions, licenses, and sources for both Windows targets, including test dependencies. Fetch failure blocks the check. Reports are written under `artifacts/`; a pass is current to that run, not an assurance about future advisories. See `deny.toml` for policy. Exceptions must be scoped and document a reason and review deadline; advisory exceptions use the tool's native expiry support.

Commit `Cargo.lock`. Compiler, dependency/features, tool, or action upgrades go through PR review. Check behavior as well as dependency versions. Add a dependency when its implementation is needed; the selected registry/cancellation crates will enter the manifest with those modules.

Use Conventional Commit categories such as `feat`, `fix`, `docs`, `chore`, and `ci` for principal changes and PR titles. Use ordinary merge commits, with Git's normal merge message. No squash-only rule or hard gate on every intermediate/historical commit applies. Local hooks are optional.

Keep public documentation in English. Chinese domain/planning material remains valid. Update user-visible behavior, the matching reference, and the changelog together. Stable guidance belongs in Git; `.scratch/` stays local. See [testing](docs/testing.md), [architecture](docs/architecture.md), and [compatibility](docs/compatibility.md).

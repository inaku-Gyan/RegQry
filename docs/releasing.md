# Release preparation and assets

RegQry has not published a release. Native asset construction is implemented; tag orchestration, candidate freezing, formal evidence validation, crates.io bootstrap/OIDC publication, registry installation and immutable GitHub Release promotion remain pending. Do not treat a successful development asset build as authorization or evidence to publish.

The agreed release route is a `vVERSION` tag on a reviewed commit already merged into `main`. `Cargo.toml` is the version source; Cargo.lock, CLI version, tag, changelog and assets must agree. A version preparation PR reviews the English changelog. Normal development uses ordinary merges. The initial version is 0.1.0; compatible additions and breaking changes increment the minor component during 0.x, fixes increment patch, and breaking changes are explicitly called out. Options, matching semantics, exit statuses and promised output behavior form the compatibility contract.

## Construct native assets

Use a clean checkout, Rust 1.100.0 with the `rust-docs` component, native MSVC C++ tools/Windows SDK, and cargo-about 0.9.3. Run separately on native x64 and ARM64 Windows. Cross-compilation or emulation is not native acceptance. The scripts support Windows PowerShell 5.1 and PowerShell 7.

```powershell
rustup component add rust-docs --toolchain 1.100.0
cargo install --version 0.9.3 --locked cargo-about
./scripts/check.ps1 -Check package
# Adapt the source path if CARGO_TARGET_DIR is set.
./scripts/build-release-assets.ps1 `
  -SourceArchive target/package/regqry-0.1.0.crate `
  -OutputDirectory artifacts/native-assets
./scripts/check-release-assets.ps1 `
  -BuildReport artifacts/native-assets/build.json `
  -ReportDirectory artifacts/native-asset-check
./scripts/test-release-asset-gates.ps1 `
  -BuildReport artifacts/native-assets/build.json `
  -ReportDirectory artifacts/native-asset-gates
```

An existing matching cargo-about executable can be selected using `-CargoAbout`; MSVC inspection can use `-Dumpbin`. `-Target` must match the native Windows architecture. `-AllowDirty` is only for development probes and is recorded; a frozen candidate requires clean inputs. Every output/report directory must be new. Existing archives are never overwritten or silently rebuilt.

The builder verifies the archive and scripts' commit identity, then delegates to `build-test-bundle.ps1`. That extracts the real Cargo archive outside Git and compiles the production CLI and all native harnesses with explicit `-C target-feature=+crt-static`. It checks every executable's PE machine/imports. Both ZIPs use that same production executable; the user ZIP is not a separate untested build. [License collection](distribution.md) uses the extracted manifest/lock and separate production/test graphs. There is no dependency on unshipped repository Cargo configuration.

For each target, `build.json` records the source archive, original source/lock/commit identities, build-script identity/dirty state, actual native environment, and ZIP/manifest/CLI hashes. Detailed test build, compiler/Cargo output, PE and material records remain alongside it. The directory contains:

| File | Purpose |
| --- | --- |
| `regqry-0.1.0.crate` | Preserved original Cargo source archive |
| `regqry-v0.1.0-TARGET.zip` | User directory: executable, README/changelog/license, linked public docs, production notices and identity/PE records |
| `tests/regqry-v0.1.0-tests-TARGET.zip` | Actual CLI and all native harnesses/runners, test notices and complete test/PE/file inventory |
| `build.json` | Native build inputs and original asset byte identities |
| `user-license-report/`, `tests/test-license-report/` | Raw cargo-about output, Cargo graph and collection result |

The asset checker verifies both archives and source identities, checks the user ZIP namespace and complete inventory, validates production materials and local Markdown link closure, and compares user/test CLI identities before execution. It relocates the user directory to a new space/Unicode path, starts `--version`/`--help` from an unrelated directory with Cargo/rustc removed from PATH, then runs the independently relocated test ZIP. An optional `-PowerShell7` selects an installed shell for test checks. It restores the calling PATH and working directory on success/failure. No query against existing registry data is used by these asset checks; ordinary harnesses use private application hives or constructed inputs.

Rejection probes change only disposable copies. They cover archive/manifest/source corruption, changed executable, absent notices, wrong license scope, empty dependency graph, omitted Rust notices, altered license text, broken documentation links, parent traversal/case collisions in ZIP names and mismatched user/test CLI identities. All must fail before starting a payload. The portable test runner has separate scope/material/inventory/architecture rejection probes. Copies and build directories are preserved for inspection; none is a release candidate merely because it exists.

CI builds and checks these native assets on its two hosted architectures and preserves temporary Actions artifacts. A local x64 run does not establish that remote CI or native ARM64 ran. Neither a restricted PATH nor hosted execution establishes a clean minimum Windows client. Actual platform/VM/shell/terminal checks are listed in [testing](testing.md), [VM testing](vm-testing.md) and [the validation index](validation/README.md).

## Remaining release chain

The single planned `release.yml` uses tag push for normal releases and dispatch on that same existing tag only for recovery. It will reuse CI, build from one preserved x64 source archive on both native architectures, stage a GitHub draft, freeze candidate identities and validate the complete external evidence. Missing/failed evidence keeps the draft unpublished, with no separate human approval button. The required x64 Windows 10 22H2, stable x64 Windows 11 and native ARM64 Windows 11 24H2 resources are still missing.

The first new crates.io package is bootstrapped locally on Windows only after candidate acceptance. CI always uses official OIDC Trusted Publishing, with no API-token fallback. Release promotion publishes/verifies Cargo first, including the exact registry archive/index hash and both native registry installations, then makes the same GitHub draft public. Preflight repeated Cargo packaging and the actual uploaded registry archive must exactly match the frozen candidate SHA-256. A source-equivalent archive is insufficient.

Frozen user/test ZIPs and notices are promoted byte for byte. The final asset set also contains `candidate-manifest.json`, `regqry-vVERSION-validation.zip`, `build-manifest.json` and `SHA256SUMS`, with no circular hash references. Durable evidence belongs to the draft/final release, not solely expiring Actions artifacts. Before public promotion the complete actual draft contents must be downloaded/verified, with immutable releases enabled and verified. SHA-256/release attestations do not replace Authenticode; executables are unsigned in the initial release.

Recovery reads actual remote state first: same version/name and hash skips an already completed step, a missing asset can use the preserved original file, and any differing hash stops. It never overwrites assets, moves/reuses a published tag, rebuilds frozen ZIPs, or rolls back an already public channel. Cargo timeouts require querying the exact version before another upload; report partial publication explicitly. None of these remote publication/recovery paths has been implemented or exercised yet.

# Release preparation and assets

RegQry has not published a release. Native assets and the tag/draft/evidence/Cargo/OIDC/recovery workflow are implemented locally. Remote workflow execution, formal acceptance and actual channel publication remain unverified. Repository immutability is configured through the maintainer's existing local gh identity; CI needs no App, PAT or administrator-settings token. Development asset or mocked-state checks do not establish a release.

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

## Tag workflow and frozen candidate

The single [release.yml](../.github/workflows/release.yml) uses tag push for normal releases and dispatch on that same existing tag only for recovery. `release.ps1 -Action Inspect` first verifies clean HEAD/tag, actual remote tag commit, ancestry in fetched origin/main, locked Cargo metadata and one dated `## [VERSION] - YYYY-MM-DD` changelog entry. The current Unreleased entry deliberately cannot pass release preparation. No command creates or moves a Git tag.

Fresh runs reuse CI, preserve one verified x64 Cargo archive, then build on both native architectures. `build-release-candidate.ps1` selects the installed MSVC environment through vswhere/vcvarsall, pins Cargo's actual linker path, and records linker/Cargo binary hashes, selected SDK/UCRT versions and representative SDK import-library hashes. These identify actual selected tools, not only a dumpbin version. Existing package checks still validate the original source, static CRT, license materials and relocated assets.

Freeze checks both ZIP manifests and complete source inventories before creating the draft, uploads/downloads the five core archives with no clobber, and finally attaches `candidate-manifest.json`. Its SHA-256 is the candidate ID. It contains original server asset IDs/names/sizes/hashes, both native build/check records, test inventories and original build/license/check log bytes. Draft recovery therefore does not require a build-machine path or an unexpired Actions artifact. Keep an independent copy of the original candidate and all archives as well.

If staging fails before the candidate manifest exists, rerun the original failed staging job with its original build artifacts. A whole-run retry detects the partial draft and refuses a new build. Once frozen, recovery skips native asset construction and refreshes dependency checks. Missing/failed [formal evidence](release-evidence.md) keeps the draft unpublished; no separate approval button is added. The required x64 Windows 10 22H2, stable x64 Windows 11 and native ARM64 Windows 11 24H2 resources remain missing.

## Evidence, Cargo and final promotion

Supply a preserved acceptance ZIP using `evidence_url` and `evidence_sha256` on recovery, or the matching `RELEASE_EVIDENCE_URL` / `RELEASE_EVIDENCE_SHA256` repository variables before rerunning the failed jobs. These are data inputs, never release refs or code. The workflow sends no GitHub/Cargo credentials to that HTTPS host. Every file and required result is validated after the supplied archive digest and complete safe ZIP namespace are checked. Preserve the original archive outside expiring Actions storage until it is inside the final validation attachment.

```powershell
gh workflow run release.yml --ref v0.1.0 `
  -f evidence_url=https://YOUR-HOST/accepted-original.zip `
  -f evidence_sha256=THE_RECORDED_LOWERCASE_SHA256
```

Dispatch requires the actual existing tag ref and a frozen candidate. It cannot start a new release or regenerate ZIPs. Main must already contain the workflow definition. See the evidence guide for separate pre-Cargo source-archive acceptance and post-Cargo registry-install evidence; a missing latter record can leave Cargo public while GitHub remains a draft.

Draft [listing visibility requires push access](https://docs.github.com/en/rest/releases/releases#list-releases). Inspect therefore has contents write for visibility, checks the returned push permission and performs only reads. A filtered read-only listing never means that a candidate is absent. Native registry-install workers receive the Cargo job's candidate manifest plus its pinned SHA through the current run's artifact; they need no draft access, retain contents read, and clear GH_TOKEN during source compilation.

The first new crates.io package is bootstrapped locally on Windows only after candidate acceptance. CI always uses official OIDC Trusted Publishing, with no API-token fallback. Release promotion publishes/verifies Cargo first, including the exact registry archive/index hash and both native registry installations, then makes the same GitHub draft public. Preflight repeated Cargo packaging and the actual uploaded registry archive must exactly match the frozen candidate SHA-256. A source-equivalent archive is insufficient.

For the first real version, use the accepted candidate and clean tag on native x64 Windows, Rust/Cargo 1.100.0, and the standard local Cargo credential mechanism. Do not put the short-lived bootstrap credential in command arguments, repository files or CI. The script verifies the candidate's Cargo binary/compiler and repeated archive before publishing:

```powershell
./scripts/release.ps1 -Action CargoPublish -Tag v0.1.0 -LocalBootstrap `
  -EvidenceDirectory C:/acceptance-v0.1.0 -OutputDirectory artifacts/local-bootstrap
```

After verifying the real registry bytes, bind crates.io Trusted Publishing to `inaku-Gyan/RegQry`, `release.yml`, environment `release`, then revoke the bootstrap token. CI uses the pinned official `rust-lang/crates-io-auth-action` and its automatic post-job revocation, even when verifying an already locally published version. Configure the release environment for `v*` tag refs without required reviewers. No first-publish token secret, PAT or alternate Cargo authentication path exists in CI.

Registry inspection compares the exact-version API, sparse index checksum, actual downloaded archive and every original file. Disagreement, network failure or propagation is unknown, never permission to upload. Immediately before invoking Cargo, publication writes a candidate-bound attempt marker in the draft notes. A later run may verify a matching published version, but an absent version with an earlier attempt marker blocks automatic re-upload. Preserve the logs and reconcile the actual provider state; scripts never remove this marker or guess that an upload failed. An unresolved attempt can require abandoning the version.

Each hosted native architecture installs the exact crates.io version with a fresh Cargo home/target/install root and checks the cached source checksum and installed version/help. These no-query hosted checks are distinct from the required ordinary-user/private-fixture registry installations on the three formal clients. Finalization waits for both sets. No global fixture runs on the hosted build runners.

Frozen user/test ZIPs and notices are promoted byte for byte. The final asset set also contains `candidate-manifest.json`, `regqry-vVERSION-validation.zip`, `build-manifest.json` and `SHA256SUMS`, with no circular hash references. Durable evidence belongs to the draft/final release, not solely expiring Actions artifacts. Before public promotion the complete actual draft contents must be downloaded/verified, with immutable releases enabled and verified. SHA-256/release attestations do not replace Authenticode; executables are unsigned in the initial release.

The validation archive includes original external records, both native registry-install logs and embedded candidate build logs. It excludes build-manifest/SHA256SUMS; build-manifest excludes its own hash. Finalization retries reuse the original remote validation ZIP and build manifest, then fill only missing deterministic checksum material. `Publish` downloads the complete nine-asset set, checks inventories, current registry bytes and final evidence before promoting that same draft. A public-success/command-failure retry only verifies actual state.

**Repository setup without an App:** the [settings API](https://docs.github.com/en/rest/repos/repos#check-if-immutable-releases-are-enabled-for-a-repository) requires administrator permissions, so use the existing local maintainer gh login for initial setup. This fulfills the agreed enable-and-verify requirement without introducing a CI credential. The script checks the canonical repository ID and current administrator access, performs an explicit enable only when requested, then reads the actual setting and saves a credential-free record:

```powershell
# Initial setup; no tag/release/package is created.
./scripts/configure-release.ps1 -EnableImmutable
# Read-only check during later release preparation, before pushing its tag.
./scripts/configure-release.ps1
```

Keep this repository setting enabled. GitHub [enforces immutability when the draft is published](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases). CI validates the actual public release's immutable flag and downloads/hashes, using GITHUB_TOKEN; it does not treat a saved setup record or variable as a live settings read. If an administrator disables the setting, the actual mutable publication is reported as partial failure afterward; the workflow never deletes/reopens it or replaces assets. A changed public artifact needs a new version. This avoids the unnecessary per-run administrator-read/App requirement. First local Cargo bootstrap additionally checks the setting through that same existing local identity.

Recovery reads actual remote state first: same version/name and hash skips an already completed step, a missing core draft asset can use `-Action Restore -InputDirectory ORIGINAL_CORE_FILES`, and any differing hash stops. Restore validates all five originals first, then re-uploads only missing attachments. A restored attachment gets a new server ID; its original candidate ID remains trace metadata and content identity must still match exactly. A missing original candidate manifest or unrecoverable bytes blocks automation rather than creating a new identity. Scripts never overwrite assets, move/reuse a published tag, rebuild frozen ZIPs, or roll back an already public channel.

Run `./scripts/test-release-gates.ps1 -ReportDirectory artifacts/release-gates` for synthetic remote-state/evidence fault injection. It exercises the actual orchestration script with mocked remote/metadata boundaries and synthetic data, without real publication, credentials or global registry writes. Actual tag permissions, channel operations, recovery, OIDC and minimum/ARM clients still require remote rehearsal and acceptance.

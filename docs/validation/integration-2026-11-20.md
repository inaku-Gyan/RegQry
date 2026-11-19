# Remote integration, 2026-11-20

The implementation is available in [the integration PR](https://github.com/inaku-Gyan/RegQry/pull/1). Its checks record the current revision's remote outcome. This record preserves the first completed run and the resulting fixes; a passing step does not make that failed run successful.

## First hosted run

[Run 44570693866](https://github.com/inaku-Gyan/RegQry/actions/runs/44570693866), `pull_request`, tested branch commit `c431184c5b6326d84e11884ea8b57711838b49fe` using synthetic merge commit `4146aa9618a1b431a6d91e76d07ce83948f7632f`. Its overall result was **failure**.

- Both native Rust 1.100.0 hosts (`x86_64-pc-windows-msvc` and `aarch64-pc-windows-msvc`) passed Clippy, **47 ordinary tests** and independent outside-Git installation from the real Cargo archive. The **8 opt-in VM/live cases stayed ignored**. Native ARM64 execution is now observed; it is not a cross-compilation claim.
- The x64 release-state model passed **73 synthetic checks**. Native/VM/visual data inside that model remain synthetic.
- The fresh online cargo-deny 0.21.0 check passed both Windows dependency targets, including development dependencies. RustSec commit: `074ea9a7ed619f511b5b7374c7a97e98d1e98be4`; fetched `2026-11-19T16:54:10.7114368Z`. Cargo.lock SHA-256: `4302706560ffc6a88cc84ff6e1850f16ff5abc906e1b87dfb540606d86caccfd`.
- Linux correctly emitted the product's Windows-only compilation error. Its verification step then failed because `rg` was absent on that runner. The check now uses the available POSIX `grep -F`.
- Both asset jobs stopped because the cargo-about installation produced no executable. The [fixed 0.9.3 manifest](https://github.com/EmbarkStudios/cargo-about/blob/0.9.3/Cargo.toml) requires its `cli` feature for that binary; Cargo returned success with a warning. CI, release installation and contributor commands now explicitly select `--features cli`. Workflow installation also checks the actual executable/version immediately. Local earlier prebuilt-tool checks had not exercised this source-installation path.

Original job logs, package records, dependency snapshot and failed asset reports were downloaded to `artifacts/first-remote/` and `artifacts/first-native-*.log` in the implementation worktree. These developer/Actions records are not frozen release evidence.

## Actual repository configuration

The existing local gh administrator identity created environment `release` and its sole deployment policy, `type=tag`, `name=v*`, then read both back at `2026-11-19T16:52:25Z`. There is no wait timer or required reviewer. The [credential-free setup record](release-environment-2026-11-20.json) identifies canonical repository ID 1462950131 and the returned environment/policy IDs. No App, PAT, secret or Cargo credential was added. The separate earlier immutable-release setting remains documented in [the release setup record](release-settings-2026-11-20.json).

No tag, draft, crate or public release was created during this integration check. Actual tag-trigger/freeze/recovery/OIDC/channel execution and formal clean/minimum Windows clients, disposable VM tests and visible terminals still need their own evidence. Hosted native ARM64 checks do not replace the required clean ARM64 Windows 11 24H2 acceptance.

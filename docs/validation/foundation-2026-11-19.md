# Foundation checks, 2026-11-19

Scope: local development validation of the `chore/project-foundation` working tree. These are not formal platform or release acceptance records. Registry queries are not implemented. The maintainer approved jiff 1.0.1 as the replacement for chrono/humantime on 2026-11-19.

Environment: native x64 Windows build 10.0.26300.0; Rust/Cargo 1.100.0, rustfmt and Clippy from that toolchain; native MSVC. Ordinary-user/clean-machine status was not established for these checks. Package scripts were executed with Windows PowerShell 5.1.26100.9818 and PowerShell 7.7.0.

| Check | Result and limits |
| --- | --- |
| Format and default Clippy, all targets | Pass, locked graph, warnings as errors |
| Rust and real CLI tests | Pass: 7 rule tests and 6 CLI tests, including aliases, invalid inputs, help/version, explicit unavailable-query status, and UTC/fixed-age/midnight ambiguity |
| Warnings-as-errors policy probe | Pass: an isolated warning fixture exits 101 under `CARGO_BUILD_WARNINGS=deny` |
| Dependency audit | Pass: cargo-deny 0.21.0, both Windows targets, production/test dependencies, fresh Cargo home, no advisory exceptions; advisories/bans/licenses/sources pass |
| Audit provenance | RustSec commit `7133866a6b44d6d3e1994ae6a48a296553c3c3da`, 50 index-cache file hashes recorded; lock SHA-256 `011789adaf4b1be02d78688f9dad176ba3413fe4a1d1c4cd48fe9de85b87c611`; completed 2026-11-19T09:43:09Z |
| Fetch failure probe | Pass: a fresh cache with an unavailable index fails during fetch, writes fail/fetch, and does not execute the check; a configuration-validation failure was separately observed and is not counted as the fetch probe |
| Audit report-writing failure | Pass: forcing `result.json` to be a directory triggers a write failure; the caller's Cargo home and working directory are still restored |
| Advisory expiry probe | Pass: isolated chrono metadata graph with the same scoped RUSTSEC-2026-0543 exception exits 0 for 2099-01-01 and 1 for 2000-01-01; this fixture is not in the product graph or source package |
| Source package/install | Pass: 17-file package, Cargo verification, extraction outside the repository, isolated target/install directories, explicit active toolchain, installed version/help; both PowerShell versions. No upload performed |
| Windows ARM64 compilation | Pass for `cargo check --locked --target aarch64-pc-windows-msvc` on this x64 host; not native ARM64 execution |
| Windows-only guard | Pass for Linux cross-target check with the actual product Windows-only marker; network/download failure was rejected as insufficient evidence. Actual Ubuntu CI remains pending |
| Workflow validation | Pass with official actionlint 1.7.12, allowing only its missing catalog entry for the already selected hosted `windows-11-vs2026-arm` label; no other lint ignored. Remote Actions execution remains pending |
| Documentation/scripts | Relative documentation links, PowerShell 5.1 syntax, and ASCII script-source encoding checked |

Commands are available in the contribution guide and check scripts. Transient package/audit results are local `artifacts/` outputs; this summary preserves scope and snapshot identity, not release-candidate evidence. Independent installs used a temporary directory outside the checkout to avoid inherited repository configuration and Windows deep-path linker failures. No global PATH, profile, execution policy, or repository settings were changed.

A manually selected audit cache under the deeply nested worktree hit a Windows Git path-length failure. That run was not counted as a pass; the successful refresh above used the script's default OS temporary directory.

Native ARM64 execution, minimum Windows clients, true ordinary-user/ACL/views/links, clean-system DLL/CRT checks, portable candidate bundles, actual registry installs, OIDC publishing, and immutable Release verification remain pending as listed in the [validation index](README.md).

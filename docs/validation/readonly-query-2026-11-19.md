# Readonly query checks, 2026-11-19

Scope: local development validation of `feat/readonly-query`, based on foundation commit `4118164b6913c7164f013b259e1ceeb523592f5b`. This is the first implemented readonly query path, not formal platform or release acceptance.

Environment: native x64 Windows 10.0.26300.0, Rust/Cargo 1.100.0 and native MSVC. Ordinary-user and clean-machine status was not established. No production query writes to the registry; test setup writes only through a new private application-hive handle in a unique temporary directory.

| Check | Result and scope |
| --- | --- |
| Format, default Clippy and tests | Pass with locked dependencies and warnings as errors: 26 internal tests plus 6 actual CLI subprocess tests |
| Query/data/output rules | Constructed data covers relative overlapping roots, descendant-only scope, key globs, strict times, same-value AND, type exclusion, data OR, explicit expansion, missing/empty/zero-length states, malformed data/names, view identities, output failure, atomic cancellation and streaming before further reads |
| Missing default boundary | Only the explicit value-not-found code confirms absence; path failure, access denied and deleted-key cases remain incomplete and never produce UNSET |
| Native application hive | Pass: actual CLI argument builder/plan, native reader, query executor and grouped output; 6,000-character value name, unknown u32 type code, 256 KiB raw payload, internal NUL preservation and missing default. All handles close and explicit temporary-directory cleanup succeeds |
| CLI smoke | Pass: actual executable with redirected streams and no new console, a fresh random missing HKCU root, empty stdout, English Win32 2 diagnostic, one-error incomplete footer and exit 2. The smoke creates no global key |
| Dependency audit | Pass: cargo-deny 0.21.0, fresh Cargo home/index/DB, both Windows targets including tests; advisories/bans/licenses/sources pass with no exceptions |
| Audit identity | RustSec `7133866a6b44d6d3e1994ae6a48a296553c3c3da`, 58 index-cache hashes; lock SHA-256 `4302706560ffc6a88cc84ff6e1850f16ff5abc906e1b87dfb540606d86caccfd`; completed 2026-11-19T10:30:07Z |
| ARM64 compilation | Pass for `cargo check --locked --target aarch64-pc-windows-msvc` on x64; no native ARM64 execution claim |
| Non-Windows guard | Linux cross-target check fails with the actual product Windows-only marker. Initial missing-cache failures were not counted as passes; locked sources were fetched before the successful rejection check |

The application hive exercises the private handle path, not public CLI ROOT addressing, physical WOW64 view isolation, per-child ACLs or registry links. Normal CLI subprocess tests remain registry-free. Real console Ctrl+C delivery, minimum clients, native ARM64 runs, ordinary-user tokens, physical view sentinels, ACL/link/race VM cases, relocated test bundles, terminal/shell acceptance, DLL/CRT checks and performance/memory baselines remain pending in the [validation index](README.md).

Deduplication currently uses a sorted identity vector with fallible ordinal comparisons; insertion can move existing identities. No throughput, memory ceiling or full-machine duration is claimed. No result sorting follows from this internal structure.

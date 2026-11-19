# Release asset tooling checks, 2026-11-19

Implementation branch: `build/release-assets`, based on `b3bf91573ac13c008f31ddeb57fff92cfe703d80`. This record covers development asset tooling. It is not a frozen candidate, native ARM64 run, minimum/clean-system acceptance or publication record. See [asset construction](../releasing.md).

Implemented:

- Fixed cargo-about 0.9.3 production/test configurations and a plain-text template. Generation uses the extracted Cargo manifest/lock with explicit Windows target filtering, checks coverage against Cargo's normal/build or normal/build/dev graph, retains original license texts and supplementary packaged notices, and includes the actual Rust 1.100.0 standard-library copyright/license files.
- Hash-checked clarifications for windows-sys/windows-link's lowercase `license-mit` files preserve Microsoft's original copyright. difflib 0.4.0 omitted LICENSE from its archive; the test graph retrieves its original immutable upstream file and checks SHA-256. Generic fallback text without a source is rejected. This uses cargo-about's resolver rather than implementing a license parser.
- Native user/test ZIPs from the actual source archive, with one shared production executable, explicit static CRT, PE checks, complete file/material identities, source archive/normalized file identities, compiler/linkage settings and actual native environment. No existing ZIP is overwritten.
- User ZIP namespace/inventory/production-material checks, documentation link closure, pre-execution user/test CLI identity comparison, Unicode/space relocation and help/version without Cargo on PATH. The actual test archive is independently relocated and verified.
- Thirteen user asset rejection probes and three additional portable license probes. Wrong hashes, missing/wrong-scope/empty/altered materials, absent Rust notices, broken docs, unsafe/colliding ZIP paths and mismatched CLI identities fail before payload execution. CI now constructs/checks native user/test assets and preserves them as temporary artifacts on both hosted targets; remote execution remains pending.

Executed development probes:

- Both target-filtered graphs generated successfully: production **28 Cargo packages / 66 material files**, tests **40 packages / 88 files**, for each of x64 and ARM64. This is graph filtering on an x64 host, not ARM64 executable execution. Reports are `artifacts/license-reports/*/result.json`; configuration and source/lock/tool hashes are recorded.
- A dirty-checkout source package with 35 files passed normal Cargo verification and independent outside-Git installation/help/version. The first x64 static-CRT user/test asset build from that archive passed all five PE checks, license collection, archive identity and local documentation checks.
- The first relocated archive run passed **47 ordinary tests**, leaving **8 opt-in cases ignored**. The initial 10 user rejection probes and 12 portable rejection probes passed in PowerShell 7.7.0. The expanded 13 user rejection probes and 17-file syntax parse passed in actual Windows PowerShell 5.1.26100.9818. Probe records live under `artifacts/assets-probe*`; these dirty probes are distinct from subsequent clean-commit archives.
- actionlint 1.7.12 and whitespace checks passed. The actionlint invocation retains the existing explicit exception for its missing `windows-11-vs2026-arm` label catalog entry; no workflow errors were otherwise ignored.

The host is a native x64 development Windows client 10.0.26300, with non-elevated token recorded by the runners. Removing Cargo/rustc from PATH does not establish that developer tools or runtimes are absent from the system. Tests write private application-hive/temp fixtures only; these asset checks do not query the user's existing registry or create global VM fixtures. The prior aggregate-only live observations were not rerun.

Production Rust code, dependency versions/features and Cargo.lock are unchanged. The lock remains SHA-256 `4302706560ffc6a88cc84ff6e1850f16ff5abc906e1b87dfb540606d86caccfd`. The earlier same-day online dependency audit still binds that graph; no new audit run is claimed by license collection. cargo-about does not replace the dependency audit or the additional native/runtime/asset review described in [distribution materials](../distribution.md).

## Subsequent clean-commit verification

The artifacts below bind **`130ebce96585949c9e53b2025cdfedc327a384c3`**, the clean implementation commit. This section was added afterward as documentation only; it does not relabel/rebuild those artifacts as a later commit's output.

Normal Cargo packaging verified 35 files, 293.6 KiB uncompressed, and an independent outside-Git source installation/version/help passed at `2026-11-19T15:13:47Z`. Repeating normal `cargo package --locked` under the same pinned compiler/Cargo and clean commit produced the identical archive SHA-256. The preserved 82,022-byte `.crate` is `11cd483960d26adec9ba7be2f423bf016f24db4fc41e3658d793bf9e5ed802a1`. Records: `artifacts/package-check/21ae3ca11d9b4835be45b4720e3d7543/result.json`, `artifacts/asset-source-repeat.json`.

The native x64 asset build completed at `2026-11-19T15:14:22Z`, preserving the source's full 35-file inventory, including normalized/original Cargo.toml, lock and VCS metadata. All five static-CRT executables passed PE inspection. `artifacts/native-assets-final/build.json` binds:

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| User ZIP | 1,524,644 | `11599fb0d78ad6a36488362a4d4a6eeccb9138d800ddaf634174d7d356982714` |
| Test ZIP | 5,194,410 | `837990bfc6da97d06c9dac88a2a1591e29ca70ea7fd11b16082dd7e126ff4a1e` |
| Shared CLI | — | `a7826d0eb08a956ac3686bd40143ce37c1f2b6236e948b6dc552b361da735c44` |

User manifest SHA-256: `60338bbfe68fdc7a2329e6cb947f1bfccdb9ab976bc1b09a35b7ae72290a04d9`; test manifest: `819da1f086e0afb59ced8f86dbdb643e741d90f98ded257b438f11847464d6bf`.

The same untouched ZIP bytes passed in **Windows PowerShell 5.1.26100.9818 and PowerShell 7.7.0**: each ran **47 ordinary tests**, kept **8 opt-in tests ignored**, and passed **43 rejection probes** (13 user assets, 12 portable tests, 15 VM guards, 3 live-observer guards). The native x64 Windows client 10.0.26300 runners recorded non-elevated tokens, no Cargo/rustc on PATH, and restored the caller's environment/working directory, including absent/empty variables and unrelated opt-in values. They finished at `15:15:31Z` / `15:15:27Z`; records: `artifacts/asset-ps51*` and `artifacts/asset-ps7*`. No global VM fixture or live observation was run.

Missing formal VM/native ARM64/minimum/clean-client/shell/visual records remain release blockers. Candidate freezing, evidence validation, OIDC/bootstrap, actual registry installs, immutable release settings and remote recovery/publication are not implemented or exercised by this phase. No push, PR, merge, tag or public release was made.

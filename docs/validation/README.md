# Validation status

No formal platform or release acceptance has passed yet. This index distinguishes the foundation's local/CI checks from future candidate evidence.

Local development checks are recorded in [foundation checks, 2026-11-19](foundation-2026-11-19.md).

The subsequent query implementation has its own [readonly query checks](readonly-query-2026-11-19.md). These records do not replace the formal matrix below.

Portable test tooling is recorded in [portable bundle checks](portable-bundle-2026-11-19.md), including native x64 static CRT, relocation, PowerShell 5.1/7, and failure probes.

The explicit two-phase global suite and its unexecuted VM boundary are recorded in [VM tooling checks](vm-tools-2026-11-19.md).

Private-hive mutation, malformed names/data and real closed-pipe output are recorded in [native read stability checks](native-read-2026-11-19.md).

Hidden-console delivery and process-control tooling are recorded in [CLI process tooling checks](cli-processes-2026-11-19.md); the new actual CLI VM cases remain unexecuted.

Actual no-query calls through cmd/Windows PowerShell 5.1/PowerShell 7 and their byte/exit-code checks are recorded in [shell tooling checks](shells-2026-11-19.md). The owned-VM query case and manual terminal template are implemented, not executed acceptance.

Fixed deep/wide generation, the aggregate consumer and opt-in observation tools are recorded in [performance tooling checks](performance-2026-11-19.md). Actual candidate VM scaling remains unexecuted; live observations use their own aggregate-only status and do not establish correctness/platform acceptance.

Twelve actual readonly queries on the development machine are recorded in [development live observations](live-development-2026-11-19.md). All were incomplete, with recorded exit 2; no raw registry contents were retained.

Native user/test ZIP construction and original third-party notices are recorded in [release asset tooling checks](release-assets-2026-11-19.md). These are development assets; formal acceptance and publication remain pending.

Tag/candidate/evidence/OIDC/recovery tooling, synthetic state tests and actual selected-tool x64 construction are recorded in [release orchestration checks](release-pipeline-2026-11-20.md). Repository setup uses the existing local gh identity; CI checks actual immutable publication without an App. No real channel operation has run.

| Requirement | Current status |
| --- | --- |
| Native x64 and ARM64 hosted checks | Workflow implemented; remote execution pending |
| x64 Windows 10 22H2 ordinary user and clean system | Missing environment |
| Representative x64 Windows 11 client | Product acceptance not run |
| Native ARM64 Windows 11 24H2 ordinary user and clean system | Missing environment |
| Actual 32/64 view, ACL, links, long/malformed values | Opt-in ROOT/view/ACL/link VM suite implemented, not run; x64 private-hive long/malformed data and controlled changes checked; ARM64 execution pending |
| Three shells on each formal system; 80/120-column representative console/Terminal runs | Local three-shell no-query checks passed; owned-VM query case and manual record template implemented; formal/visual acceptance not run |
| Actual CLI Ctrl+C, closed pipeline and fixed generated streaming baseline | VM case implemented, not run; isolated constructed-producer control probe passed locally |
| Deep/wide scaling and representative live-query baselines | Generator/private-hive readback and consumer checked; twelve aggregate-only development live observations recorded, all incomplete; actual CLI VM/formal series not run |
| Portable candidate test bundles and DLL checks | Development builder, x64 DLL checks and relocated tests passed; frozen candidates, ARM64 and clean minimum systems pending |
| Production/test distribution materials and user ZIPs | Implemented; both Windows dependency graphs checked; local native x64 asset checks passed; native ARM64 execution and final distribution review pending |
| Candidate source/ZIP hashes and repeatable Cargo archive | Construction/freezing/recovery implemented; local clean x64 repetition and state model checked; actual frozen tagged candidate pending |
| First local crates.io initialization, Trusted Publisher, registry installs and immutable release | Scripts/workflow implemented; existing local identity handles repository setup, no App/PAT fallback; real channel execution pending |

Later versioned records must identify commit/candidate, actual OS build and host/process/target architecture, compiler/SDK, user token/setup privileges, input fixture ownership, exact commands/output/exit/cleanup, and CLI/source/ZIP/test-bundle hashes. An unexecuted or missing case is never pass. Keep raw/structured evidence and test bundles with the final Release, with stable pointers here; Actions artifacts alone are temporary.

# Validation status

No formal platform or release acceptance has passed yet. This index distinguishes the foundation's local/CI checks from future candidate evidence.

Local development checks are recorded in [foundation checks, 2026-11-19](foundation-2026-11-19.md).

The subsequent query implementation has its own [readonly query checks](readonly-query-2026-11-19.md). These records do not replace the formal matrix below.

Portable test tooling is recorded in [portable bundle checks](portable-bundle-2026-11-19.md), including native x64 static CRT, relocation, PowerShell 5.1/7, and failure probes.

The explicit two-phase global suite and its unexecuted VM boundary are recorded in [VM tooling checks](vm-tools-2026-11-19.md).

Private-hive mutation, malformed names/data and real closed-pipe output are recorded in [native read stability checks](native-read-2026-11-19.md).

Hidden-console delivery and process-control tooling are recorded in [CLI process tooling checks](cli-processes-2026-11-19.md); the new actual CLI VM cases remain unexecuted.

Actual no-query calls through cmd/Windows PowerShell 5.1/PowerShell 7 and their byte/exit-code checks are recorded in [shell tooling checks](shells-2026-11-19.md). The owned-VM query case and manual terminal template are implemented, not executed acceptance.

| Requirement | Current status |
| --- | --- |
| Native x64 and ARM64 hosted checks | Workflow implemented; remote execution pending |
| x64 Windows 10 22H2 ordinary user and clean system | Missing environment |
| Representative x64 Windows 11 client | Product acceptance not run |
| Native ARM64 Windows 11 24H2 ordinary user and clean system | Missing environment |
| Actual 32/64 view, ACL, links, long/malformed values | Opt-in ROOT/view/ACL/link VM suite implemented, not run; x64 private-hive long/malformed data and controlled changes checked; ARM64 execution pending |
| Three shells on each formal system; 80/120-column representative console/Terminal runs | Local three-shell no-query checks passed; owned-VM query case and manual record template implemented; formal/visual acceptance not run |
| Actual CLI Ctrl+C, closed pipeline and fixed generated streaming baseline | VM case implemented, not run; isolated constructed-producer control probe passed locally |
| Portable candidate test bundles and DLL checks | Development builder, x64 DLL checks and relocated tests passed; frozen candidates, ARM64 and clean minimum systems pending |
| Candidate source/ZIP hashes and repeatable Cargo archive | Release implementation pending |
| First local crates.io initialization, Trusted Publisher, registry installs and immutable release | Release implementation pending |

Later versioned records must identify commit/candidate, actual OS build and host/process/target architecture, compiler/SDK, user token/setup privileges, input fixture ownership, exact commands/output/exit/cleanup, and CLI/source/ZIP/test-bundle hashes. An unexecuted or missing case is never pass. Keep raw/structured evidence and test bundles with the final Release, with stable pointers here; Actions artifacts alone are temporary.

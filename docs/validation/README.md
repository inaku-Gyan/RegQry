# Validation status

No frozen-candidate release acceptance or channel publication has passed yet. Actual native hosted development checks, including standard-user registry queries and independent source installations, have passed. This index distinguishes executed development evidence, required candidate checks and deferred client/manual coverage. Older dated records retain the requirements and unexecuted state at that point; current policy is the [hosted acceptance contract](../hosted-acceptance.md).

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

The first actual hosted x64/ARM64 execution, its integration failures/fixes and the tag-only release environment are recorded in [remote integration checks](integration-2026-11-20.md). Subsequent loaded standard-user profiles, actual fixture suites and independent source installations are recorded in [hosted ordinary-user checks](hosted-acceptance-2026-11-20.md). [Merged main CI](https://github.com/inaku-Gyan/RegQry/actions/runs/44592042469) passed all six jobs.

| Requirement | Current status |
| --- | --- |
| Native x64 and ARM64 hosted checks | Both native jobs passed Clippy, 47 ordinary tests, packaging/source install, static-CRT assets and rejection probes; dedicated standard-user jobs also passed |
| x64 Windows 10 22H2 ordinary user and clean system | Unexecuted compatibility target; deferred outside first-release gates |
| Representative x64 Windows 11 client | Unexecuted compatibility target; deferred outside first-release gates |
| Native ARM64 Windows 11 minimum 24H2 and clean system | Later native hosted Win11 build executed; exact minimum/clean client remains unexecuted and deferred |
| Actual 32/64 view, ACL, links, long/malformed values | Owned ROOT/view/ACL/link suite passed as a standard user on both hosted architectures, using both bundled and independently source-installed CLIs; native long/malformed application-hive tests also passed |
| Three actual shells and automatic UTF-8/output/exit checks | Passed for actual fixture queries on both native hosts and both executable origins; each frozen candidate must repeat them |
| Visible terminals at 80/120 columns and physical keyboard Ctrl+C | Not run; deferred outside first-release gates |
| Actual CLI Ctrl+C, closed pipeline and generated streaming baseline | Actual owned-fixture CLI process case passed on both native hosts and both executable origins; generated real console event establishes automated cancellation, not physical input |
| Deep/wide scaling and representative live-query baselines | Actual fixed owned-fixture scaling passed on both native hosts and both origins; twelve separate development live observations remain incomplete and are not correctness evidence |
| Portable candidate test bundles and DLL checks | Both native development ZIPs passed import/relocation/inventory checks; frozen candidate execution pending, minimum/clean systems deferred |
| Production/test distribution materials and user ZIPs | Both native development builders and production/test notices/material/import checks passed; actual candidate distribution remains pending |
| Candidate source/ZIP hashes and repeatable Cargo archive | Construction/freezing/recovery implemented; local clean x64 repetition and state model checked; actual frozen tagged candidate pending |
| First local crates.io initialization, Trusted Publisher, registry installs and immutable release | Scripts/workflow implemented; existing local identity handles repository setup, no App/PAT fallback; real channel execution pending |

Later versioned records must identify commit/candidate, actual OS build and host/process/target architecture, compiler/SDK, user token/setup privileges, input fixture ownership, exact commands/output/exit/cleanup, and CLI/source/ZIP/test-bundle hashes. An unexecuted or missing case is never pass. Keep raw/structured evidence and test bundles with the final Release, with stable pointers here; Actions artifacts alone are temporary.

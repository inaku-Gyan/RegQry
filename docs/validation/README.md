# Validation status

No formal platform or release acceptance has passed yet. This index distinguishes the foundation's local/CI checks from future candidate evidence.

Local development checks are recorded in [foundation checks, 2026-11-19](foundation-2026-11-19.md).

The subsequent query implementation has its own [readonly query checks](readonly-query-2026-11-19.md). These records do not replace the formal matrix below.

| Requirement | Current status |
| --- | --- |
| Native x64 and ARM64 hosted checks | Workflow implemented; remote execution pending |
| x64 Windows 10 22H2 ordinary user and clean system | Missing environment |
| Representative x64 Windows 11 client | Product acceptance not run |
| Native ARM64 Windows 11 24H2 ordinary user and clean system | Missing environment |
| Actual 32/64 view, ACL, links, long/malformed values | Reader/query implemented; private-hive subset checked; global VM suites pending |
| Three shells on each formal system; 80/120-column representative console/Terminal runs | Product acceptance not run |
| Portable candidate test bundles and DLL checks | Implementation pending |
| Candidate source/ZIP hashes and repeatable Cargo archive | Release implementation pending |
| First local crates.io initialization, Trusted Publisher, registry installs and immutable release | Release implementation pending |

Later versioned records must identify commit/candidate, actual OS build and host/process/target architecture, compiler/SDK, user token/setup privileges, input fixture ownership, exact commands/output/exit/cleanup, and CLI/source/ZIP/test-bundle hashes. An unexecuted or missing case is never pass. Keep raw/structured evidence and test bundles with the final Release, with stable pointers here; Actions artifacts alone are temporary.

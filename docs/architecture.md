# Architecture

RegQry uses one Cargo package with a thin binary and an internal library. The library is for project assembly and tests, with no stable public Rust API promise. Only the CLI module exists in the foundation stage; remaining modules are added with their actual implementation.

| Module | Responsibility |
| --- | --- |
| `cli` | Parse options and validate the query before registry access |
| `registry` | Windows handles, minimum read permissions, views, raw reads, and bounded buffer retries |
| `value` | Lossless raw names/type/bytes and shared, lazy interpretation |
| `query` | Traverse a readonly source, evaluate groups, deduplicate identities, and track completeness |
| `output` | Consume results synchronously and write grouped UTF-8 previews and diagnostics |

The query module's internal readonly interface will have a real Windows adapter and constructed test data. It is not a general CRUD/plugin interface. Use winreg 0.56.0 for handle ownership and suitable opening operations; windows-sys 0.61.2 fills raw value and timed-key-enumeration gaps. Add these direct dependencies when the registry implementation lands. Use ctrlc 3.5.3 with cancellation. Existing clap, regex, yash-fnmatch, jiff, and hex handle general parsing.

Time parsing uses jiff 1.0.1 instead of the originally planned chrono/humantime, following [RUSTSEC-2026-0543](https://rustsec.org/advisories/RUSTSEC-2026-0543.html) and [RUSTSEC-2026-0542](https://rustsec.org/advisories/RUSTSEC-2026-0542.html). These are maintenance notices, not vulnerability reports. The maintainer approved the replacement on 2026-11-19. Enable only std, system time zones, and platform timezone data. Duration terms are delegated to Jiff with fixed 24-hour days; system-timezone discovery and ambiguous/nonexistent midnight fail explicitly.

Retain raw UTF-16 names, u32 type codes, and exact saved bytes. Missing default values are a separate state. Interpretation is shared by matching and previewing; escaped presentation never becomes matching input. Unknown types remain queryable by code/raw bytes.

Traversal is initially single-threaded and streaming, with no sorting or hidden result/depth/data caps. Resident data includes traversal state, the current necessary value, output context, and deduplication identities; total memory is not constant. Repeated roots are evaluated in their own relative context before deduplication, and different views retain independent identities.

Explicit roots follow normal Windows path resolution. Recursion opens one child component at a time with OPEN_LINK and observes the source, avoiding target traversal. Registry reads require only the permissions needed by the operation. All unsafe system-call adaptation stays in the Windows module with explicit safety reasoning.

SZ/EXPAND_SZ decoding uses saved length and removes at most one final NUL; malformed UTF-16 remains raw. MULTI_SZ accepts one or two NULs for an empty sequence and requires complete termination for nonempty sequences. Integer types require exact sizes and correct byte order. Necessary interpretation failures remain distinguishable from empty data and ordinary nonmatches.

Queries capture one start time and process environment, then validate all options before registry access. A read gets at most eight retries after its first attempt; capacity/allocation failure or exhausted retries makes the search incomplete. Cancellation and output errors must preserve the agreed final status. No registry access is implemented in the foundation stage.

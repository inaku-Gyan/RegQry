# Testing

The foundation tests cover help/version, the actual CLI argument contract, pattern/type/root/time validation, repeated aliases, and explicit development status. They do not query or modify the registry. Run `cargo test --locked` or the contribution check script.

Integration tests find the CLI relative to their runtime executable, or use the explicit `REGQRY_TEST_BIN` path. They do not embed the build machine's absolute directory. This supports later portable test bundles; the test bundle generator is not implemented yet.

As query modules land, add deterministic in-memory rules/error tests and native reader tests in temporary application hives. Ordinary tests need no administrator and do not create globally navigable registry fixtures. Application hives do not prove CLI ROOT, WOW64 views, or per-child ACL behavior.

Real root/view/ACL/link cases run only in explicitly started, disposable VM suites. Create a private namespace with a fresh identity, check creation disposition and ownership, and limit cleanup to that fixture. Links use VM rollback/destruction as the final cleanup boundary. Test setup privileges and the actual ordinary-user query token are separate. Never use the user's existing registry as a fixed expected-result dataset.

Portable test bundles must contain the actual candidate CLI/test executables/helpers/fixtures and their hashes. Check every executable's DLL/CRT dependencies. Run relocated bundles on clean minimum systems without Cargo. Doctests that require rustc stay in build environments.

Record pass, fail, not-run, and missing separately. Native hosted CI is distinct from x64 Windows 10 22H2 / x64 Windows 11 / ARM64 Windows 11 24H2 acceptance, ordinary users, clean systems, and actual shell/console runs. Missing resources remain release blockers. See [validation status](https://github.com/inaku-Gyan/RegQry/blob/main/docs/validation/README.md).

Performance acceptance initially records a baseline rather than a quantitative SLA: first actual result, total duration, peak working set, and Ctrl+C-to-exit time, using fixed generated data and representative live queries. Verify streaming, cancellation 130, long results and no hidden truncation of matching. Deduplication memory may grow with identities; do not assert constant memory or a sorted traversal order.

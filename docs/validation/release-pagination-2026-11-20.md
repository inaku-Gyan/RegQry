# Real pagination and draft readback, 2026-11-20

The [actual v0.1.1 workflow](https://github.com/inaku-Gyan/RegQry/actions/runs/44614892151) passed Inspect, four quality jobs, Source and both native builds at commit `e3aa56e541c829dd70525a0da3ffa3e77d608e43`. Source SHA-256 is `5c0897211613bbf6ca12cb345778c4756bef2da52ebdfc407caddfd80832253b`, 83,557 bytes. No source acceptance or channel publication passed.

## Original frozen candidate and recovery

The first Freeze created an empty draft but its immediate list readback did not observe it. A [read-only Actions probe](https://github.com/inaku-Gyan/RegQry/actions/runs/44619178524) later confirmed that the installation token could list the same draft, get it by ID and read it through gh/GraphQL. REST lookup by tag returned 404 for the draft. The original reader also worked with the local maintainer identity.

Only failed jobs were rerun; source/native assets were not rebuilt. Attempt 2 froze draft ID `451946069` and the five original archives, plus `candidate-manifest.json` SHA-256 **03d86f28d5c9b013b2f312816a1a0ac3af71b08b29982f0f65d7ee48f7b7b025**. These originals and both version tags remain unchanged. The candidate is not formally accepted or public.

## CLI failure and correction

AcceptanceInputs then stopped before HTTP: gh rejects `--slurp` together with `--jq` or `--template`. The exact command was reproduced with real gh 2.104.0 in 0.36 seconds. The original mock had accepted impossible CLI arguments. Two affected calls read workflow artifacts and completed-job provenance.

The corrected code delegates pagination to `gh api --paginate --slurp` and decodes its raw pages with the existing PowerShell JSON decoder. Empty item arrays, single items and all pages are retained. Missing/scalar collections and null records are unknown, not empty. The mock now enforces the real argument constraint and supplies actual page envelopes.

Freeze also permits eight GET readback attempts after confirmed creation, with one-second waits between missing results. It does not repeat creation or upload. A read error stops immediately. The actual top-level Freeze regression first failed with the same original exception, then passed after two delayed reads with the exact original seven writes. Exhausted reads and API errors remain rejected.

## Executed checks

- Real top-level pagination regression failed with `GitHub operation failed; state is unknown: api --paginate --slurp` before the fix.
- The full synthetic model passed **104 cases** separately in PowerShell 7 and Windows PowerShell 5.1.26100.9818. Remote commands and the clock are mocked; this is not formal acceptance.
- The real gh client and production decoder read the completed v0.1.1 run in both shells: **16 jobs** with page size 1 matched the wide response, and **11 artifacts** were retained. No release or registry mutations occurred. Native x64 CI now repeats this actual client contract with a read-only token, before Rust construction.
- Source-byte preparation found that shared main retained 21 CR bytes in LICENSE despite LF index/attributes and clean Git status. A fresh detached tag checkout matched all 33 original source files. Future bootstrap uses a fresh tag checkout and still requires the full Cargo archive hash check.

Original model records, both real-client reports, failed job logs, readback probe and frozen source are retained under `.scratch/registry-cli-implementation/` and the isolated pagination worktree. Version 0.1.2 carries the correction; dependencies/features and Rust query semantics are unchanged. Its actual tag, frozen acceptance, local Cargo bootstrap, OIDC and final public downloads still require their own execution.

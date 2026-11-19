# Release collection stage checks, 2026-11-20

## Actual tagged execution

The [v0.1.2 tag workflow](https://github.com/inaku-Gyan/RegQry/actions/runs/44628919528) passed Inspect, quality checks, source packaging, both native asset builds, Freeze and acceptance-input export. The original draft is 452027399, bound to commit `952ce51a6cfb0fd9512aa15d8bab66144fe1dfcf` and candidate ID `d23f0d676785141cda9533dc5aa217c34553ae008a680cc5ad7e83c1f47a04b0`.

Both actual standard-user source jobs passed: [native x64](https://github.com/inaku-Gyan/RegQry/actions/runs/44628919528/job/135941716729) and [native ARM64](https://github.com/inaku-Gyan/RegQry/actions/runs/44628919528/job/135941716712). Each executed the bundled CLI and an independent installation from the frozen source archive against owned fixtures. The hosted records preserve real non-elevated tokens, loaded profiles, original query logs and account removal; `observedDestruction` remains false.

The [collector](https://github.com/inaku-Gyan/RegQry/actions/runs/44628919528/job/135943033086) then failed with `Original source platform is missing or duplicated`. No source acceptance archive was staged, Cargo job ran or channel became public. Original tags and frozen assets remain unchanged.

## Reproduction and correction

PowerShell's `ValidateSet('Source', 'Registry')` accepts lowercase arguments without changing their spelling. The workflow passes `source` / `registry`, while the collector compared `Source` / `Registry` case-sensitively. A lowercase source call initialized a source record, then incorrectly entered registry-platform update logic.

The regression calls the actual collector using the workflow's lowercase parameters. Before the fix it reproduced the exact exception. The collector now normalizes its validated stage once at entry. Its existing canonical report spelling and lowercase archive/evidence stages remain consistent. Additional cases cover original and mixed-case spellings for both stages, retaining the exact original source acceptance archive during registry collection.

All **108 synthetic release-state/evidence checks passed** on Windows PowerShell 5.1 and PowerShell 7. These model tests explicitly mock remote operations; they are not hosted acceptance or a channel publication.

A separate local diagnostic replay also passed using both original v0.1.2 hosted payloads, the original dependency audit and actual read-only GitHub job metadata. It checks the complete collection path against real report shapes. Its output is explicitly local diagnostic data, was never staged and cannot replace the corrected tag's hosted collection job.

The correction prepares version **0.1.3**. Rust query code, dependency versions/features, toolchain, frozen ZIPs and earlier tags are unchanged. The new tag must repeat actual frozen-candidate acceptance and the Cargo/OIDC/GitHub route. Minimum/clean clients, visible terminal layout and physical-keyboard checks remain deferred under the [hosted acceptance contract](../hosted-acceptance.md).

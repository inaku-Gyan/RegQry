# Release evidence records

Formal acceptance uses the exact frozen candidate and fresh native GitHub-hosted x64 Windows Server / ARM64 Windows 11 jobs. The [hosted acceptance contract](hosted-acceptance.md) distinguishes these executed environments from intended client compatibility. Minimum/clean clients and visible-terminal/physical-keyboard review are deferred and must remain `not-run`. Synthetic model fixtures test the validator; they are never formal acceptance.

The tag workflow collects records automatically through [acceptance.yml](../.github/workflows/acceptance.yml). It first exports the original frozen source, user/test archives and candidate manifest through `AcceptanceInputs`. The ordinary-user jobs have read-only workflow access and no publication credentials. After both complete, `collect-release-evidence.ps1` reads actual run/job metadata through the GitHub API, retains the original report trees and validates the evidence before packing it once.

An optional unexecuted template is available for inspecting the data contract:

```powershell
./scripts/release-evidence.ps1 -Action New `
  -CandidatePath C:/candidate-manifest.json -ExpectedCandidateSha256 CANDIDATE_ID `
  -Directory C:/regqry-v0.1.0-acceptance
```

Every required template status starts `missing`; the two deferred groups start `not-run`. Keep `pass`, `fail`, `not-run`, `missing` distinct. `Pack` recalculates the file inventory and checks records; it never changes statuses. Preserve original report trees and relative stdout/stderr references without editing raw logs. Paths inside the archive use ASCII; original Unicode stays inside the records. Reparse points, parent paths, case collisions and undeclared files are rejected before extraction or interpretation. No archived code is executed by the evidence validator.

`acceptance.json` binds schema version **2**, kind `regqry-release-acceptance`, status, `stage` (`source` or `registry`), candidateId, tag, commit and all five core asset name/SHA pairs. `checks` contains exactly one A01-A14 mapping each, with status, observation and nonempty original-record paths. The actual ordinary tests and guarded fixture cases cover CLI/filter/data/query/root/output/process/scaling contracts; fresh dependency records and explicitly synthetic recovery-model results cover their respective checks. A group-level pass never substitutes for the detailed records. `files` inventories every file except acceptance.json by path/size/SHA. The source stage cannot claim that channel publication already occurred; final promotion verifies the actual registry and public downloads separately.

The two `platforms` entries are `hosted-x64` and `hosted-arm64`. Each points to `sourceRun` / `sourceProvenance`, and later `registryRun` / `registryProvenance`. The reports retain actual OS build/product type, runner image version, target and process/native architecture. Emulation or a self-hosted job cannot fill these records. A newer ARM64 runner does not establish execution on the minimum 24H2 build; x64 Server does not establish x64 client execution.

Each original stage retains and checks:

| Record | Required content |
| --- | --- |
| controller result | Original source/user/test identities, separate elevated preparation and ordinary query SIDs, actual OS/image, matching workflow/run/attempt, successful temporary-account removal |
| ordinary/ready.json | Actual non-elevated native token, loaded user hive and initialized Software/Classes; the profile holder stays alive during preparation |
| prepare/result.json | One elevated preparation case and its raw output, candidate manifest and owned context ID/nonce/hash |
| ordinary/query-bundle/ | Complete portable inventory plus six actual Query cases using the frozen bundled CLI |
| ordinary/worker-result.json and installation logs | Independent installation by the ordinary account, pinned native Rust/Cargo identities, command/exit/timeout, source and installed executable hashes |
| ordinary/query-installed/ | Complete portable preflight, then all six Query cases using that exact independently installed CLI |
| provenance/*.json | Original REST run and completed successful job, canonical repository ID, release.yml, exact tag/commit, actual hosted runner/label and enclosing timestamps |
| quality/*.json | Fresh cargo-deny 0.21.0 audit with lock/database/index identity and the explicitly synthetic release-model result |

Both query executions require actual ROOT/view, minimum-permission/partial-failure, link, process, shell and scaling cases. Raw logs must support the recorded pass counts and guarded phase/context. The Shell case needs all three shells and its `owned-vm-query` summary. Its `manual_terminal=not-run` marker is correct. The process/scaling cases use the actual installed/bundled CLI and owned fixture, not constructed-producer or live-observation substitutes.

GitHub's [per-job hosted-VM lifecycle](https://docs.github.com/en/actions/how-tos/manage-runners/github-hosted-runners/use-github-hosted-runners) is the accepted fixture-disposal evidence. `lifecycle.observedDestruction` stays false: the workflow cannot observe its own VM being destroyed. Actual run/job records bind that contract to execution; a fabricated external destruction receipt is rejected. The existing `RollbackReference` field carries `github-actions:REPOSITORY/runs/RUN/attempts/ATTEMPT/jobs/JOB` for this path.

Source installation uses `cargo install --path` on the original extracted candidate archive, with its complete source inventory checked. Registry installation uses the exact crates.io version, a fresh ordinary-user cache/target/install root and the actual cached .crate SHA matching the frozen source. Both record the exact executable subsequently used for the fixture suite. Version/help-only execution is insufficient.

`deferredChecks` retains `minimum-clean-clients` and `visible-terminal-and-physical-keyboard` as `not-run`. Restricted PATH and hidden-console events cannot turn either into pass. Their detailed optional manual procedure remains in [the terminal guide](terminal-validation.md).

The source stage is packed once as `regqry-vVERSION-source-acceptance.zip`, uploaded first as the `source-acceptance-original` Actions artifact, then recorded by hash/run/artifact in the draft notes and uploaded/download-verified as a durable draft asset. Registry collection starts from that exact original ZIP, copies all its original files unchanged, and embeds the ZIP as `original/source-acceptance.zip`. It adds only actual registry records/provenance and binds the source ZIP hash. The resulting `regqry-vVERSION-registry-acceptance.zip` follows the same artifact/marker/durable-asset sequence.

Recovery reuses a valid durable ZIP unchanged. If an upload was interrupted, it reconciles the original artifact/marker before collecting again. A missing accepted source ZIP can be restored from the original embedded inside registry evidence; either stage can be restored from the final validation archive or its original, unexpired Actions artifact. A different hash, expired/lost originals or a missing public asset stops recovery. There is no external HTTPS evidence-host input and no rebuilding accepted ZIPs. Final validation retains both original stage ZIPs as well as the complete expanded records.

Missing or failed required records keep GitHub at the draft. Cargo can already be public while registry acceptance is incomplete; record that partial state without rolling back or replacing the candidate. See [the release route](releasing.md) for authentication, the first local package bootstrap and final promotion.

# Release evidence records

Use the exact frozen candidate ID and original archives. This data contract checks record identity and completeness; actual operator observations, VM state, clean-system inventories and visual review remain human evidence. Synthetic model fixtures are only tests of the validator and must never be submitted as acceptance.

Create an unexecuted template, using the candidate SHA recorded by the staging run:

```powershell
./scripts/release-evidence.ps1 -Action New `
  -CandidatePath C:/candidate-manifest.json -ExpectedCandidateSha256 CANDIDATE_ID `
  -Directory C:/acceptance-v0.1.0
```

Every status starts `missing`. Replace it only after actual execution. Keep `pass`, `fail`, `not-run`, `missing` distinct. `Pack` never changes statuses. Copy original portable and VM runner report trees into the nominated locations; their stdout/stderr references remain relative to the report, with no renamed or edited raw logs. Use ASCII file paths in the archive, while retaining original Unicode inside records and screenshots. No reparse points, parent paths, case collisions, unexpected files or payload execution are accepted.

`acceptance.json` binds schema version 1, kind `regqry-release-acceptance`, status, candidateId, tag, commit and all five core asset name/SHA pairs. `checks` contains exactly one A01–A14 mapping each, with status, concrete observation and nonempty `records` paths relative to this directory. These map the accepted CLI, filtering, patterns, data states, fidelity, query context, reads, roots/views/ACL/links, output/shells, completeness/cancellation, performance, engineering, platform/portable, and release/recovery requirements to original evidence. A group-level pass does not replace the detailed checks below. `files` inventories every original file except acceptance.json itself, by path/size/SHA; Pack calculates it.

The three `platforms` entries are `win10-x64`, `win11-x64`, `win11-arm64`. Record status, actual edition, displayVersion and channel `general-availability`. Client product type and native process/host identity come from the actual portable report. Win10 requires build 19045 / 22H2; x64 Win11 requires a stable client build; ARM64 Win11 requires build 26100 or later. A newer development/preview build, Server or emulation does not cover these records.

Each platform points to:

| Field | Required original record |
| --- | --- |
| portable | `run-tests.ps1` result.json and all referenced harness logs, matching the frozen manifest/source and exact test inventory, ordinary token, native client, Cargo/rustc absent from PATH |
| vmPrepare / vmQuery | Original elevated Prepare and separate ordinary-user Query result.json trees from `run-vm-tests.ps1`; same context ID/nonce/hash/candidate, all seven phase-specific VM cases, actual guarded-fixture markers and passing raw summaries |
| cleanSystem | Operator/VM inventory record described below; PATH removal alone is insufficient |
| rollback | Actual external rollback/destruction record after VM Query completed |
| sourceInstall | Actual independent candidate-archive installation and private-fixture query on that client |
| registryInstall | Actual independent crates.io installation/private-fixture query on that client, collected after Cargo publication; required for final GitHub promotion |
| terminals | Actual visible terminal observations at 80 and 120 columns |

The VM Shell case must record all three actual shells and the `owned-vm-query` passing summary. Its `manual_terminal=not-run` marker is correct: visible review is independent. VM performance/process cases retain their actual measurements and known-fixture results, not apparatus-only or live-observation substitutes. Keep external context and cleanup records with original logs.

Supplemental JSON records use these fields (record paths are relative to the acceptance root):

| kind | Fields in addition to status |
| --- | --- |
| regqry-clean-system-record | candidateId, snapshotId, target, osVersion, developmentToolsInstalled=false, extraRuntimeInstalled=false, inventoryRecords pointing to actual VM/software/runtime inventories |
| regqry-vm-rollback-record | contextId, reference equal to the prepared rollbackReference, action `rollback` or `destroy`, completedAtUtc after query completion, records pointing to actual hypervisor/external cleanup logs |
| regqry-formal-source-install | candidateId, source `candidate-archive` or `crates.io`, sourceSha256, target, osVersion, compiler containing original `rustc -Vv` lines, cliSha256 of that installed executable, elevated=false, privateFixtureExitCode=0, records pointing to exact install commands/logs, source/cache/lock identity and the private-fixture query logs |

Source-install evidence must identify the exact installed executable used by the query and its owned fixture/context/cleanup. Do not use `--path` as proof of registry installation, a cached old executable, or hosted version/help as proof of private-fixture acceptance. Registry source SHA must equal the actual downloaded/index-verified candidate archive. Keep setup/query and clean-snapshot lifecycles explicit if separate VM snapshots are used.

Each `terminals` entry has terminal (`classic` or `windows-terminal`), columns (80 or 120), status, visible=true, actual version, measurement describing how actual dimensions were read, physicalCtrlCExitCode=130 and records linking screenshots/transcripts/exact commands/font/scaling/encoding and observed results from [the terminal guide](terminal-validation.md). Required combinations are Win10 classic; x64 Win11 Windows Terminal; ARM64 Win11 both. Automated hidden-console cancellation cannot fill these visual records.

After completing pre-Cargo acceptance:

```powershell
./scripts/release-evidence.ps1 -Action Pack `
  -CandidatePath C:/candidate-manifest.json -ExpectedCandidateSha256 CANDIDATE_ID `
  -Directory C:/acceptance-v0.1.0 -ArchivePath C:/accepted-pre-cargo.zip
```

Preserve that original ZIP and its printed hash at an HTTPS location the runner can download without credentials. Supply its URL/hash to the same existing-tag recovery. After the actual registry version is public and installed/tested on all three clients, add those original registryInstall records, then pack a **new** archive path using `-RequireRegistry`. Update the evidence input for recovery; the candidate/user/test ZIP bytes stay identical. Finalization preserves the submitted evidence bytes/files inside the durable validation archive.

Missing or failed records stop at the draft. Cargo can already be public while post-Cargo evidence is missing; this is an explicitly reported partial release, not a rollback or a reason to replace the candidate. Once the final validation archive is staged, recovery uses that original archive and never recompresses it. See [the release route](releasing.md) for authentication and current publication blockers.

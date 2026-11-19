# Development live observations, 2026-11-19

Status: **observed; all twelve queries incomplete**. This is a development-machine performance baseline, not a correctness, minimum-client, clean-system, ARM64 or release acceptance pass. No raw registry keys, value names, data or diagnostic targets are retained. The observer's ordinary preflight uses private application-hive files; the actual live queries make no HKCU/HKLM writes.

The measured tools/CLI came from clean source commit `e6840aaa5630589c9fbc3ff35577b2460877c15f`, Rust/Cargo 1.100.0, native x64 MSVC and explicit static CRT. This record was added afterward; the identities below bind that already tested archive rather than any later documentation-only commit.

Environment: Windows client development system 10.0.26300 (cmd reported 10.0.26300.9974), native and process x64, non-elevated user token, PowerShell 7.7.0. Exact SID and environment are in the local JSON. Observation ran from `2026-11-19T14:32:26Z` to `14:34:06Z`. Cache state/system load were uncontrolled, the consumer drained immediately and the process environment was inherited without the fixture-specific variable. This is not a verified cold/warm comparison.

Every query returned exit **2**, with `complete=false`. The default-key query reported 3,044 recognized Win32 5 access-denied diagnostics plus its incomplete summary. Other queries also had diagnostics; their target/message text was deliberately discarded. A zero-row HEX observation therefore is not a complete quiet no-match result. Both passes happened to have the same counts; this mutable registry is not an expected-result dataset.

| Case | Records per pass | Total seconds, pass 1 / 2 | First record ms, pass 1 / 2 | Peak MiB, pass 1 / 2 |
| --- | ---: | ---: | ---: | ---: |
| default-key | 856,251 | 45.039 / 38.294 | 19.398 / 6.136 | 167.91 / 167.93 |
| scoped-key | 34,664 | 1.109 / 0.949 | 9.376 / 7.839 | 15.91 / 15.91 |
| scoped-name | 624 | 1.022 / 0.963 | 7.799 / 10.355 | 7.97 / 7.95 |
| scoped-data | 2,424 | 1.255 / 1.224 | 20.336 / 20.105 | 10.11 / 10.14 |
| scoped-hex | 0 | 1.130 / 1.114 | N/A / N/A | 9.71 / 9.50 |
| expanded | 312 | 1.128 / 1.149 | 10.451 / 9.195 | 10.20 / 10.27 |

Query arguments and metric definitions are in [performance measurement](../performance.md). The default count includes separate logical views, not a count of unique physical keys. Timing includes process startup, pipe/decoder work and exit/drain; peak working set belongs to the actual CLI. No quantitative SLA or optimization decision follows from two observations. The separate exact-result VM scaling/cancellation cases remain unexecuted.

Recorded identities:

| Input / output | SHA-256 |
| --- | --- |
| `regqry-0.1.0.crate` | `7f11d17275fdc94af1b2781f047ecd94aacebad4bd553d8fd5dd55414d975e97` |
| x64 development test ZIP | `953bf5db52641cb66e8ec64b46e8d3a248f04ec59903c8c2b1a947886219446c` |
| Test-bundle manifest | `32bc038dc770c48a4c2b9140283cbec101eaef6a5aecc44ff068455069c9c558` |
| Actual bundled `regqry.exe` | `de8b06ff9147d0364a92d6efce2a40f3517005206bd5ffd0137eb306cc3df3f6` |
| Cargo.lock | `4302706560ffc6a88cc84ff6e1850f16ff5abc906e1b87dfb540606d86caccfd` |

The clean source archive contains 34 files, passed Cargo verification and independent installation outside Git, and repeated normal packaging produced the same archive SHA. All five native CLI/test PE files passed machine/import checks. The same ZIP, without rebuilding, passed **47 ordinary tests, nine portable-bundle rejection probes, fifteen VM rejection probes and three observer rejection probes** under actual Windows PowerShell 5.1.26100.9818 and PowerShell 7.7.0. Both relocation runs had Cargo/rustc absent from PATH, non-elevated tokens and restored caller environment. All eight opt-in cases remained ignored there; the live observer was invoked separately afterward.

Local raw/structured records, relative to the implementation checkout:

- `artifacts/performance-final/build.json`, `artifacts/performance-source/regqry-0.1.0.crate`, `artifacts/performance-repeat-source.json`.
- `artifacts/package-check/ef1e7a418a014755b7f38ea7a558892b/result.json`.
- `artifacts/performance-ps51*` and `artifacts/performance-ps7*` for relocated tests and rejection probes, completed at 14:32:11Z / 14:32:23Z.
- `artifacts/performance-live/result.json`, `observer.stdout.txt` and `observer.stderr.txt`, containing aggregate observations, not raw registry streams.

No tag, upload, merge, public release or channel setting changed. These are development artifacts; frozen candidates and formal resources/third-party distribution materials/release implementation remain pending. See the separate [tooling checks](performance-2026-11-19.md) for fixture/probe scope.

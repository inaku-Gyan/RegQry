# Performance measurement

The first release records baselines without a quantitative latency or memory SLA. RegQry remains single-threaded, streaming and unsorted, with no hidden result/depth/data limits. Deduplication identities and the complete currently needed value can grow memory. A fixture size or watchdog is not a product cap. Formal acceptance still requires the frozen candidate on the formal systems.

| Layer | Input / correctness | Evidence |
| --- | --- | --- |
| Ordinary apparatus | Constructed 4,096-record producer, privacy/first-record assertions; private application-hive generator/readback | Consumer, process-memory API and fixture checks; not actual CLI query performance |
| Disposable-VM scaling | Actual CLI and fresh owned/marked registry data, ordinary query token | Exact full identity sets, no duplicates, fixed filter outcomes and timings |
| Live observation | Actual CLI, existing HKCU/HKLM data, non-elevated token | Aggregates only; not a fixed correctness dataset or formal platform pass |

The VM layer follows the setup/query/rollback lifecycle in the source archive's VM instructions. Ordinary tests and CI never run either ignored query layer automatically. Live observation is read-only, creates no registry fixture and requires its own opt-in independently of VM confirmation.

## Fixed generator, version 1

Under the VM's owned native-64 `Scale` key:

- `W0064`, `W0512`, `W4096` contain that many direct `Node0000`-style children.
- Each node has Text (SZ: `fixed-节点-NNNN ` plus 64 `x` characters), Raw (256 BINARY bytes: DE AD BE EF, little-endian u32 index, then A5), Ordinal (little-endian DWORD index), and Expand (EXPAND_SZ: `%REGQRY_SCALE_TEST_VAR%`). Only this fixed layer sets that process variable to `expanded-节点`.
- `D0016`, `D0064`, `D0256` contain chains of that many one-component-created `K0001`-style keys, each with Payload SZ `depth-NNNN`.
- VM ownership markers are additional binary values. Explicit fixture-name filters exclude them from data workloads. All children retain fresh creation dispositions and owner/nonce/ACL checks.

The generator is bound to the source commit/archive and logs these parameters: 4,672 wide nodes, 336 chain nodes, six branches and Scale itself, with 19,024 workload data values excluding ownership markers.

The 21-query series runs twice: five at each width (keys, four-value dense results, text, HEX and expansion); three full chains; two overlapping-root cases; and quiet zero-match. Exact identity sets are compared without assuming output order. Overlap adds the level-16 key as another root and repeats the outer root; relative `^K0017` must still emit levels 17–256 after the outer context matched none. This verifies relative matching before deduplication. The complete series has 76,416 result records across both passes.

An ordinary private-hive test builds the full fixture, checks direct-child counts, first/last binary indices and deepest saved payloads, then closes/removes its files. It reopens chains one component at a time, like product recursion. On the development system a single API call opening the 64/256-level path returned Win32 87, while component opens worked. This observation is not a product depth cap or a claim about every Windows build. The selected 256 levels are a test dimension within native tree limits; see [Microsoft registry limits](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-element-size-limits) and [RegOpenKeyExW](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regopenkeyexw).

## Representative live observation

Extract the complete matching-native test bundle and run without elevation, keeping reports outside it:

```powershell
./measure-live.ps1 -ReadOnlyLiveRegistry -ReportDirectory C:\RegQryResults\live-unique
# Optional: -ExpectedManifestSha256 HASH -PowerShell7 C:\path\to\pwsh.exe
```

The runner verifies the complete bundle and ordinary tests first. It runs these fixed queries twice in order:

| Case | Arguments |
| --- | --- |
| default-key | `--key=.*` (default HKCU/HKLM and all supported views) |
| scoped-key | `--key-root HKCU\Software --key=Microsoft` |
| scoped-name | `--key-root HKCU\Software --name=Path` |
| scoped-data | `--key-root HKCU\Software --data-i=windows` |
| scoped-hex | `--key-root HKCU\Software --data-hex=DEADBEEF` |
| expanded | `--key-root HKCU --data-expand=.` |

The observer inherits the process environment without injecting the fixed-fixture variable. It decodes/discards streams one line at a time and retains no key paths, value names, previews or diagnostic targets/messages. Reports contain only static arguments, output byte/record counts, diagnostic-line counts, numeric Win32-code frequencies, completeness/exit status and metrics. Current line buffers are transient; no full result set or raw live-output archive is collected.

Results reflect the current profile, permissions and mutations. Exit 2 stays incomplete even with hits; no item has a predefined identity/count. Zero records have no first-result timestamp. Report status is `observed`, distinct from a correctness pass. Preserve manifest/source identity and actual OS/native/process/token details. Development observations do not replace the formal client/ARM64/candidate matrix.

## Metric boundaries

- `first_result_us` starts before process creation and ends when the consumer reads a complete actual KEY, VALUE or UNSET record. Group headings do not count. Zero records use `N/A`.
- `total_us` includes startup, exit and output/error drain. The 5 ms exit-wait polling overhead is included.
- `peak_working_set_bytes` is the CLI's K32GetProcessMemoryInfo PeakWorkingSetSize, not observer memory or sampled current RSS.
- The consumer drains immediately, including real pipe/decoder cost. The separate VM Ctrl+C case controls backpressure and records cancellation-to-exit; this normal-drain series uses `cancel_to_exit_us=N/A`.
- Cache and system load are uncontrolled. Pass 1 is not a verified cold-cache run; pass 2 is repetition, not statistical confidence. No cache flush, host performance setting or product delay is introduced.
- Each CLI has a 60-second watchdog; outer VM scaling/live wrappers allow 600/900 seconds, with slightly shorter hidden-job deadlines. Timeouts fail and kill owned descendants; they never count as successful cancellation or completion.

Keep incomplete, failed, not-run and missing distinct. Actual CLI VM measurements remain unexecuted until a prepared disposable VM runs them. A local live baseline may be recorded independently with the above privacy boundary; it does not make the release ready.

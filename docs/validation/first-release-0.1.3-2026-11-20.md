# RegQry 0.1.3 first-release validation, 2026-11-20

RegQry 0.1.3 is public on [GitHub Releases](https://github.com/inaku-Gyan/RegQry/releases/tag/v0.1.3) and [crates.io](https://crates.io/crates/regqry/0.1.3). GitHub publication completed at **2026-11-20 00:01:05 UTC**. The [actual tag workflow](https://github.com/inaku-Gyan/RegQry/actions/runs/44636293489) completed successfully after recovery of its first-crate bootstrap boundary.

## Frozen identity

| Field | Value |
| --- | --- |
| Tag | `v0.1.3` |
| Annotated tag object | `22f165b307cfdf84bfddf40507bcce7bc3c4748f` |
| Commit | `d6afa70dcef9b2b443f46093319c173357b6c791` |
| GitHub Release ID | `452066966` |
| Candidate ID | `386ccde8eae258120a16e640a23e63e3cafd127d0406b19bfee0ee734ee15462` |
| Cargo archive SHA-256 | `ec6c2cfb25c35e08801cf8e451ea5173429da2bf14a39b89a8bee6c6f927ff90` |
| Source acceptance ZIP SHA-256 | `cd43591890eb424611dc0e38fda8979412019db42439cbb16fbe7b43ad889c28` |
| Registry acceptance ZIP SHA-256 | `1e273f5fd2da5f771b8a84c5776f9aa8070a18c2078f59d86ff797e5ae4711f9` |

The five core archives and candidate manifest were frozen before acceptance. Native local packaging, repeated pre-publication packaging, the crates.io API/index and actual downloaded archive all matched the 84,189-byte Cargo archive. All 33 original source files also matched the fresh tag checkout. ZIPs were promoted unchanged.

## Executed acceptance

Both native hosts ran the full prepared fixture suite as genuine non-elevated standard users with loaded profiles. Source acceptance exercised the bundled CLI and an independent installation of the frozen source archive. Registry acceptance repeated the suite with the bundled CLI and an exact-version crates.io installation from an empty user cache. Both registry caches contained the exact Cargo archive above.

| Registry acceptance host | Native target | Actual OS / runner image | Query token |
| --- | --- | --- | --- |
| x64 Windows Server | `x86_64-pc-windows-msvc` | `10.0.26100`, `win25-vs2026` / `20261116.315.1` | Standard user, not elevated |
| ARM64 Windows 11 | `aarch64-pc-windows-msvc` | `10.0.26200`, `win11-vs2026-arm64` / `20261112.217.1` | Standard user, not elevated |

The fourteen acceptance groups passed, covering field/filter behavior, real ROOT/view/ACL/link cases, malformed and long data, streaming and process controls, three-shell UTF-8/exit behavior, distribution materials, scaling observations and release gates. The recovery model is explicitly synthetic; actual channel operations have their separate executed records. Accounts were removed successfully. Hosted VM disposal relies on the provider contract; records correctly retain `observedDestruction: false`.

Original source jobs: [x64](https://github.com/inaku-Gyan/RegQry/actions/runs/44636293489/job/135965920146), [ARM64](https://github.com/inaku-Gyan/RegQry/actions/runs/44636293489/job/135965920026). Registry jobs: [x64](https://github.com/inaku-Gyan/RegQry/actions/runs/44636293489/job/135973664730), [ARM64](https://github.com/inaku-Gyan/RegQry/actions/runs/44636293489/job/135973664861). Raw original logs, provenance, compiler/environment identities and individual case results are in the Release archives.

## Authentication, recovery and public bytes

Attempt 1 constructed and accepted the frozen candidate, then stopped at the expected local initialization requirement for a new crate. The accepted archive was uploaded once locally. The owner saved the exact Trusted Publisher binding for `inaku-Gyan/RegQry`, `release.yml`, environment `release`. Attempt 2 reran only failed jobs and reused the original candidate/source evidence. The [actual Cargo job](https://github.com/inaku-Gyan/RegQry/actions/runs/44636293489/job/135972857892) passed the official OIDC exchange, verified the already-published exact version and completed automatic short-lived-token revocation. No API-token fallback, GitHub App, PAT or additional approval environment was introduced.

The owner confirmed revocation of the temporary local upload token, and standard Cargo logout completed. Local records contain no token values. Future releases use CI OIDC.

Finalization and publication passed. The actual public Release reports `immutable: true`; all eleven assets were anonymously downloaded and their sizes/SHA-256 verified after publication. Independent original copies and the public verification record were also retained locally. The [candidate manifest](https://github.com/inaku-Gyan/RegQry/releases/download/v0.1.3/candidate-manifest.json), [build manifest](https://github.com/inaku-Gyan/RegQry/releases/download/v0.1.3/build-manifest.json) and [SHA256SUMS](https://github.com/inaku-Gyan/RegQry/releases/download/v0.1.3/SHA256SUMS) identify the exact assets.

The Release includes the original [source acceptance ZIP](https://github.com/inaku-Gyan/RegQry/releases/download/v0.1.3/regqry-v0.1.3-source-acceptance.zip), [registry acceptance ZIP](https://github.com/inaku-Gyan/RegQry/releases/download/v0.1.3/regqry-v0.1.3-registry-acceptance.zip) and [complete validation ZIP](https://github.com/inaku-Gyan/RegQry/releases/download/v0.1.3/regqry-v0.1.3-validation.zip). Registry/validation archives preserve the original source ZIP bytes; durable evidence is available independently of expiring Actions artifacts.

## Deferred coverage

Exact minimum and clean clients (x64 Windows 10 22H2 / Windows 11, ARM64 Windows 11 24H2), visible terminal layouts at 80/120 columns and physical-keyboard Ctrl+C remain unexecuted under the [hosted acceptance contract](../hosted-acceptance.md). Actual hosted checks and generated console Ctrl+C events do not establish those results. Executables are unsigned. The [compatibility targets](../compatibility.md) retain these distinctions.

# Hosted ordinary-user development checks

These are actual GitHub Actions development runs, not frozen-candidate release acceptance. The user accepted Actions-only resources, separate compatibility/verified-host statements, provider lifecycle evidence and deferred minimum/clean/manual-terminal coverage. The current contract is [hosted acceptance](../hosted-acceptance.md); release evidence uses [schema 2](../release-evidence.md).

[PR 2](https://github.com/inaku-Gyan/RegQry/pull/2), tested branch head `16555ba2184a7e3f7a424530a3700e3af1af20bd`, passed [all six jobs](https://github.com/inaku-Gyan/RegQry/actions/runs/44588768075). Ordinary merge produced main `f47fcec8a8106f51b4ea63c2ca94edcd770e0d33`; [all six main jobs](https://github.com/inaku-Gyan/RegQry/actions/runs/44592042469) also passed. The PR assets use synthetic merge commit `412b6ef233a34d2417df7a1d303cd38114d06c48`, which is different from the branch head and final main commit. Their exact original .crate SHA-256 on both targets is `ac72acd3053fa2d3309b6d125ee1b5b1f27f9aa2ab929e292e06473fbfdd4070`.

The retained original PR controller trees are the Actions artifacts `hosted-registry-x86_64-pc-windows-msvc` and `hosted-registry-aarch64-pc-windows-msvc`. They contain preparation, readiness, bundled/installed query records, ordinary portable preflights and installation streams. These temporary artifacts are development evidence; final release records must live durably with their version.

| Actual PR environment | x64 | ARM64 |
| --- | --- | --- |
| OS build / product type | 10.0.26100 / Server (3) | 10.0.26200 / client (1) |
| Hosted image version | win25-vs2026 20261103.298.1 | win11-vs2026-arm64 20261112.217.1 |
| Native machine / process machine | 34404 / 0 | 43620 / 0 |
| Standard-user PowerShell | 5.1.26100.33648 | 5.1.26100.9974 |
| Query token | Actual separate non-elevated local Users account | Actual separate non-elevated local Users account |
| Loaded profile | Actual SID hive and Software/Classes verified | Actual SID hive and Software/Classes verified |
| Bundled CLI / installed CLI fixture cases | 6 passed / 6 passed | 6 passed / 6 passed |
| Independent original-archive installation | Native Rust/Cargo 1.100.0, fresh user cache/target/root | Native Rust/Cargo 1.100.0, fresh user cache/target/root |
| Temporary account removal | Passed | Passed |

Each Query execution passed the exact bundled ordinary harness inventory (47 tests; eight opt-in cases stay ignored there), then explicitly ran the six guarded query cases: ROOTs/physical views, permissions/partial failures, links/aliases/cycles, actual CLI process behavior, three actual shells and fixed scaling data. It recorded Cargo/rustc absent from the query PATH and the exact bundled or independently installed program hash. Preparation ran once as the separate administrator against new owned fixtures. No existing user registry was used as a fixed expected dataset.

The first run, [44581114388](https://github.com/inaku-Gyan/RegQry/actions/runs/44581114388), exposed cmd stripping unquoted regex carets. The next, [44583885022](https://github.com/inaku-Gyan/RegQry/actions/runs/44583885022), exposed Windows PowerShell 5.1 marshalling a space-containing ROOT ending in a backslash. The final change quotes cmd patterns and doubles the PS5 trailing backslash at the native argument boundary. Failed runs remain failed; they are not included in the successful result.

GitHub supplied a new hosted VM per job. The controller removed the temporary account, and the platform lifecycle contract covers later VM disposal. `observedDestruction=false` is intentional; no VM destruction receipt was fabricated. No developer workstation ran the global fixture suite.

Not executed: a frozen version tag/candidate, actual crates.io installation, OIDC publication, final immutable release/download verification, minimum/clean Windows clients, visible 80/120-column rendering or physical-keyboard Ctrl+C. The last two coverage groups remain explicitly deferred. Source installation and hidden-console events cannot be reported as those missing observations.

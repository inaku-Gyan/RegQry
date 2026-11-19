# GitHub Actions as the only acceptance environment

Verified 2026-11-20. Scope: standard GitHub-hosted runners; official documentation/source and existing RegQry runs only. No accounts, VMs or registry fixtures were created, and no workflow was manually dispatched. This report supplies facts for an acceptance decision; it changes no gate.

## Available systems

The [official image catalog, pinned at fbb26cb](https://github.com/actions/runner-images/blob/fbb26cb01c3651ea3a0347e54bfa2ef83d740d49/README.md), lists:

| Native architecture | Standard Windows labels | OS family |
| --- | --- | --- |
| x64 | `windows-latest`, `windows-2025`, `windows-2025-vs2026` | Windows Server 2025 |
| x64 | `windows-2022` | Windows Server 2022 |
| ARM64 | `windows-11-arm`, `windows-11-vs2026-arm` | Windows 11 ARM64 |

There is no standard Windows 10 22H2 or x64 Windows 11 label, nor a Windows 11 ARM64 24H2 selector in that catalog. Image updates are weekly; an OS-family label does not freeze a particular image build. [GitHub's reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners#supported-runners-and-hardware-resources) confirms the labels for public/private repositories. `-latest` means GitHub's latest stable image, not necessarily the vendor's newest OS.

## What this repository actually ran

Both [PR run 44572565411](https://github.com/inaku-Gyan/RegQry/actions/runs/44572565411) (`45c07e6`) and [main run 44574672987](https://github.com/inaku-Gyan/RegQry/actions/runs/44574672987) (`20c2e9a`) concluded `success`, including both native jobs. The main run's job logs and downloaded `native-assets-<target>/native-assets/build.json` plus `native-asset-check/tests/tests/result.json` record:

| Main-run job | OS / product type | Native target | Elevated | PowerShell |
| --- | --- | --- | --- | --- |
| [x64](https://github.com/inaku-Gyan/RegQry/actions/runs/44574672987/job/135738817881) | Server 2025 Datacenter, `10.0.26100` / `3` | `x86_64-pc-windows-msvc` | `true` | `7.6.9` |
| [ARM64](https://github.com/inaku-Gyan/RegQry/actions/runs/44574672987/job/135738817948) | Windows 11, `10.0.26200` / `1` | `aarch64-pc-windows-msvc` | `true` | `7.6.10` |

Exact images were `windows-2025-vs2026` `20261103.298.1` and `windows-11-vs2026-arm64` `20261115.219.1`. Microsoft maps Windows 11 build `26200` to [25H2](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information). Do not conflate the PR and main environments. Relocated tests recorded Cargo/rustc absent from PATH, not absent from the machine. Logs explicitly leave the global VM cases ignored. These are hosted development checks, not clean minimum-client or ordinary-user acceptance.

## Isolation, lifecycle and privileges

[GitHub documents](https://docs.github.com/en/actions/how-tos/manage-runners/github-hosted-runners/use-github-hosted-runners#using-a-github-hosted-runner) a new VM per job, shared by all steps of that job, then automatic decommissioning when the job finishes. Thus elevated preparation and ordinary-user queries must share one job; separate jobs do not share a registry. The [single-CPU exception](https://docs.github.com/en/actions/reference/runners/github-hosted-runners#single-cpu-runners) is `ubuntu-slim`, a new container on a shared VM, not a Windows option. [Self-hosted runners](https://docs.github.com/en/actions/reference/security/secure-use#hardening-for-self-hosted-runners) have no equivalent clean ephemeral-VM guarantee.

Windows hosted VMs run as administrators with [UAC disabled](https://docs.github.com/en/actions/reference/runners/github-hosted-runners#administrative-privileges). A normal `run:` step is therefore insufficient evidence of an ordinary query token. GitHub's security description of a [clean isolated VM](https://docs.github.com/en/actions/reference/security/secure-use#hardening-for-self-hosted-runners) describes job isolation, not a Windows installation without developer tools.

The sources establish provider-managed decommissioning. This investigation found no tenant-visible per-job destruction receipt or snapshot-rollback record. Job success alone is not an observation of destruction. Whether run/job identity plus the provider lifecycle contract can replace the project's externally recorded rollback/destruction evidence is a policy decision.

## Ordinary-user mechanism: documented, not executed here

Windows provides [New-LocalUser](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/new-localuser?view=powershell-5.1) (or [`net user /add`](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/net-user)) and [Add-LocalGroupMember](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/add-localgroupmember?view=powershell-5.1). A prospective job could create a fresh local account, grant ordinary Users membership, exclude administrator/privileged membership, and launch its query process using [`Start-Process -Credential -LoadUserProfile`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process). Use a generated job-local password, hidden child window, explicit readable/writable paths, bounded waits, and captured output/exit status. These are implementation requirements, not a tested GitHub recipe; native shell/module availability and actual token rights need verification on both hosts.

At API level, [CreateProcessWithLogonW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createprocesswithlogonw) runs with supplied local credentials; the account needs Log On Locally permission. `LOGON_WITH_PROFILE` loads its hive under HKU. Omitting profile loading can produce HKCU results inconsistent with interactive logon. `LOGON_NETCREDENTIALS_ONLY` retains the caller's local token and cannot establish an ordinary-user query.

The existing [preparation harness](https://github.com/inaku-Gyan/RegQry/blob/20c2e9adfe53699ef6f250eb31924f23430c3c9a/tests/vm_registry.rs#L210) opens existing `HKU\<QuerySid>\Software` and `...\Software\Classes`; its [wrapper](https://github.com/inaku-Gyan/RegQry/blob/20c2e9adfe53699ef6f250eb31924f23430c3c9a/scripts/bundle/run-vm-tests.ps1#L60) rejects elevated/mismatched queries. Consequently the user's profile must remain loaded across elevated preparation and queries. A candidate orchestration is one ordinary-user worker kept alive behind a readiness handshake while the administrator prepares fixtures, then released to query. It must verify both parent keys, SID, non-elevated token, architecture and bundle identity before global writes. A short profile-initialization process followed by exit is not sufficient evidence of that prerequisite.

Alternatively an administrator can explicitly hold a [LoadUserProfile](https://learn.microsoft.com/en-us/windows/win32/api/userenv/nf-userenv-loaduserprofilew) profile handle, close hive handles, then unload it; that API requires backup/restore privileges. Neither approach, fresh `Software\Classes` readiness, nor cleanup/cancellation behavior was exercised here. The account's token still would not reproduce default desktop UAC configuration.

## Clean images, nesting and terminals

[Hosted images contain preinstalled tools and change weekly](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners#preinstalled-software-for-github-owned-images). Removing tools from PATH or uninstalling selected packages cannot establish the original clean-minimum-system condition. The same source says nested virtualization is technically possible but unsupported, experimental, and has no stability/performance/compatibility guarantees. A nested guest is therefore an untested investigation, not an available standard acceptance environment.

[Larger runners](https://docs.github.com/en/actions/reference/runners/larger-runners#runner-images) offer a Base Windows 11 Desktop partner image. [Custom images](https://docs.github.com/en/actions/how-tos/manage-runners/larger-runners/use-custom-images) require an eligible organization/enterprise plan, permissions, configuration and billing; their documented Windows image-generation platform is x64. They start from a selectable base image, not a documented standard-runner arbitrary-ISO facility. This route was not provisioned, and neither exact minimum versions nor a Windows ARM64 custom-image route was established.

The [runner process source](https://github.com/actions/runner/blob/b34a11f6ff02fac6ef996b1eed70bcb8776c8afa/src/Runner.Sdk/ProcessInvoker.cs) redirects stdin/stdout/stderr and normally creates no window. Inference: Actions logs and automated width tests cannot demonstrate human-visible classic-console/Windows-Terminal rendering at 80/120 columns or physical keyboard input. [Workflow cancellation](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-cancellation) targets the step entry process and can escalate to Ctrl+Break/process-tree termination. It is not the project's physical-keyboard acceptance. [`GenerateConsoleCtrlEvent`](https://learn.microsoft.com/en-us/windows/console/generateconsolectrlevent) can supply genuine automated console-event evidence; it cannot establish a physical keypress or visual inspection.

## Evidence categories for the next decision

| Category | Honest Actions-only status |
| --- | --- |
| Native build/test/package, relocation/import checks | Executed hosted development evidence, tied to exact run and bytes |
| Separate ordinary-token ROOT/view/ACL/link/process/shell/scaling suite | Feasible mechanism to implement and verify; currently unexecuted |
| Provider disposal boundary | Documented guarantee; project acceptance substitution undecided |
| Clean Win10 22H2, representative x64 Win11, minimum ARM64 24H2 | Not supplied by standard catalog; current runs do not prove them |
| Human-visible terminal and physical Ctrl+C | Missing under the current execution constraint |

The remaining choices concern the supported OS/clean-system promise, acceptable lifecycle evidence, and treatment of manual visual/keyboard requirements. Keeping, revising or explicitly waiving those requirements needs a separate decision; this report selects none.

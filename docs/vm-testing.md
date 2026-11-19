# Disposable-VM registry checks

These checks exercise the native CLI against freshly created, globally navigable registry fixtures. Use a disposable VM with a recorded snapshot/rollback or destruction procedure. The opt-in is an operator assertion; the tools do not infer disposability from a VM vendor string. A passing query report does not complete cleanup or the formal release matrix.

Build a [portable test bundle](testing.md) on each matching native architecture. It contains `vm_registry` and `run-vm-tests.ps1`. Ordinary `cargo test`, the portable runner and hosted CI leave the four VM cases ignored. CI runs rejection probes, not elevated fixture setup. The three ordinary helper tests use constructed inputs or private application-hive files only.

Application hives cannot supply the ACL fixture: their security comes from the hive file, and [Windows rejects an individual key's security descriptor](https://learn.microsoft.com/en-us/windows-hardware/drivers/kernel/filtering-registry-operations-on-application-hives). An ordinary test verifies that rejection and exercises descriptor/token/owner helper code without creating a global fixture. It is not a successful per-key ACL test.

The VM must have both an administrator for setup and the intended ordinary query account. Sign in as that query account first so its user hive and `Software\Classes` are loaded. Record its SID from that account's shell:

```powershell
[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
```

Extract the complete ZIP to a directory readable by both accounts. Use the same verified bytes in both phases. Keep the context and reports outside that directory. In the administrator's elevated PowerShell, supply the actual query SID and the actual rollback reference:

```powershell
# From the extracted bundle; the context parent directory must already exist.
./run-vm-tests.ps1 -Phase Prepare -DisposableVm `
  -QuerySid 'S-1-5-21-111-222-333-1001' `
  -RollbackReference 'VM identifier / snapshot identifier before RegQry' `
  -ContextPath C:\RegQryValidation\context.json `
  -ReportDirectory C:\RegQryValidation\prepare
```

The placeholder SID is not a fixture account to create. Copy the actual SID instead. Preparation opens existing parent keys, creates a random `RegQryAcceptance_<id>` namespace, and rejects any existing component rather than adopting it. It verifies Administrators as the key owner and writes a random binary ownership marker. Actual link-source keys retain their defined single `SymbolicLinkValue` without synthetic marker values; their owning fixture root is marked and each creation disposition is recorded.

Preparation touches only new descendants of HKLM\Software in each view, HKU\<query SID>\Software, that user's Software\Classes, and HKCC. It applies protected, non-inheriting DACLs to the new keys, retaining full access for setup/System and granting only the needed bits to the query SID. It never changes the common parent ACLs, the user's existing values, host account policies or UAC. Setup fails if the target profile is not loaded, its required parents are absent, permissions are insufficient, or a fixture already exists. The context remains `preparing` on any failure, preventing query reuse; use a new VM run after rollback.

From a separate non-elevated shell of the query account:

```powershell
./run-vm-tests.ps1 -Phase Query -DisposableVm `
  -ContextPath C:\RegQryValidation\context.json `
  -ReportDirectory "$env:TEMP\regqry-vm-query-unique-run"
```

The wrapper verifies context, complete bundle/PE/test inventories, native architecture and prepared bundle identity. It checks that the query SID matches and the token is not elevated; the Rust harness independently repeats the phase/identity/token checks. Both phases record the actual environment. Each query logs its argument array, UTF-8 streams, exit code and elapsed time; a 15-second per-query watchdog fails a loop rather than reporting successful cancellation. The machine name and OS/native architecture must match the setup record. No account credentials are accepted or stored.

The query cases cover:

- Distinct 32/64-bit HKLM sentinels through explicit and default views, repeated view deduplication, all five ordinary ROOT aliases, root values excluded, relative overlapping roots evaluated before deduplication, literal backslashes in value names and HKCR's merged label. A user-only HKCR fixture proves the logical access path, not every merge-precedence rule or physical-source tracing.
- Separate query-value/enumerate permissions. The harness independently verifies that `KEY_READ` is denied, the intended single access bit succeeds and its opposite is denied. Readable values and descendants survive sibling ACL errors, while the query exits 2 with diagnostics. A protected root does not require broad `KEY_READ` to enumerate.
- A real link to a target outside the search root but inside the owned fixture, a cycle, a broken target and a regular lookalike key. Recursive search sees sources without following targets; the lookalike still recurses. Explicit roots resolve a real alias normally. REG_LINK contents use the object-manager path without a terminating NUL, as specified by [MS-RRP symbolic-link semantics](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rrp/d5ce9dcc-1f90-4f5a-b076-cc1d2c9b4195). This suite checks local Windows behavior rather than assuming remote-protocol behavior is sufficient evidence.

See [Microsoft access rights](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-key-security-and-access-rights) for why query-value and enumeration are separate. Access bits are checked on actual fresh opens with the ordinary token, not inferred from the SDDL text.

After either phase starts a global harness, every report explicitly says `VM_ROLLBACK_REQUIRED`. Preserve the context, both reports and streams outside the VM, then roll back or destroy the VM and retain that external operation's identity/result with the run. The tools deliberately provide no recursive registry cleanup and never chase a link to delete its target. The disposable VM is the fixture lifecycle boundary. If setup fails partway, retain its creation trace and use the same rollback boundary; do not rerun setup against that partial namespace. A later evidence gate must require the external cleanup record as well as successful setup/query records.

The current suite does not yet exercise concurrent key/value mutation, forced retry exhaustion, malformed native names/data, actual console Ctrl+C, shell encoding, terminal layout or performance. Private-hive and constructed tests cover subsets separately; do not mark the whole acceptance group passed. Run this suite on native x64 Windows 10 22H2, representative x64 Windows 11 and native ARM64 Windows 11 24H2 as part of the established matrix; hosted checks or cross-compilation cannot replace them. No formal VM run has been recorded yet.

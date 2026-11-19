# Portable development bundle checks, 2026-11-19

These are local development-tool checks. No formal candidate, minimum-system, clean-system, ARM64, VM, or release acceptance is claimed. Product Rust code and dependency selection are unchanged from the readonly-query implementation.

The initial build used the clean source archive for `c5b5fa1ea7266799195bc6685e4411aa48624c03`, SHA-256 `77a1ab22ab250607896e5d4902224fd737732bc192945bae2c3b433650d9e15b`, lock SHA-256 `4302706560ffc6a88cc84ff6e1850f16ff5abc906e1b87dfb540606d86caccfd`. Rust/Cargo 1.100.0 native x64 compiled the extracted source outside the repository with `-C target-feature=+crt-static`. Executable paths came from Cargo JSON rather than preexisting build-directory contents.

The bundle contains the CLI and three actual harnesses: 26 library tests, six CLI subprocess tests, and an empty binary harness. All 32 tests ran after relocation; no tests are currently ignored. The application-hive case uses a private file/handle and checks cleanup; no globally navigable fixture was created. During runner iteration, disposable development copies reused these exact executables and regenerated only the runner payload/manifest/ZIP. This was not promotion or replacement of a frozen candidate.

## Executed checks

| Check | Result |
| --- | --- |
| All four executables, MSVC dumpbin 14.43.34810.0 | Correct x64 machine; direct and delay-load imports limited to reviewed Windows DLLs; no dynamic CRT |
| ZIP paths | Explicit `/` entries; verified extraction, including the PowerShell 5.1 ZIP behavior that required this adaptation |
| Relocated directory | New temporary path with spaces and Greek Omega, unrelated current directory, explicit bundled CLI |
| Windows PowerShell 5.1.26100.9818 | 32 tests passed; captured UTF-8 streams; Cargo/rustc absent from PATH |
| PowerShell 7.7.0 | Same 32 tests passed with the same bundle; Cargo/rustc absent from PATH |
| Controlled rejection probes in both shells | Ten probes passed, listed below; failed bundle identities started no payload process |
| Environment restoration | Location and Cargo/Rustup/test/PATH variables preserved on successful and failed relocation; absent and empty variables distinguished on PowerShell 7 |
| Script syntax and encoding | Windows PowerShell parser; all new `.ps1` files ASCII-compatible |
| Workflow lint | actionlint 1.7.12 passed with only its known catalog omission for the previously verified `windows-11-vs2026-arm` label ignored |

The rejection probes cover expected manifest hash, changed CLI bytes, missing payload, extra executable, omitted harness inventory, failed PE check, wrong PE machine, expected ZIP hash, failure after relocation/environment clearing, and an actual dynamic-CRT development executable. The last is an optional supplied fixture; CI runs the other nine. Environment assertions exposed and fixed PowerShell 7's absent-versus-empty behavior rather than treating an empty variable as removed.

The import union was `advapi32.dll`, `api-ms-win-core-synch-l1-2-0.dll`, `bcryptprimitives.dll`, `kernel32.dll`, `ntdll.dll`, and `userenv.dll`. Raw imports/headers and dumpbin identity are inside the bundle. This is static import inspection, not proof of every dynamically loaded DLL/API or clean-system behavior.

Both runner records identify Windows `10.0.26300`, workstation product type 1, native/process x64 and non-elevated tokens. PowerShell 5.1 ran under the sandbox identity; PowerShell 7 ran under the workspace owner's identity. Both are on the developer host and do not replace the formal ordinary-user/minimum-client matrix. The final runner-iteration records finished at 11:48:34Z and 11:48:49Z. Their development ZIP SHA-256 is `38770f57e4875bf36c03e1487792b98b594bba5561a289c955adb0f45a9db884`, manifest SHA-256 `bcffc79914bd93c65a30f1951b3f8c516bd846a51a8d746ff9451fb6c362a558`; later clean-commit checks retain their own identities in local build/result JSON.

## Remaining acceptance

Native ARM64 execution and remote CI have not run. The clean minimum systems, real views/ACL/links and console cancellation, shell/visual matrix, performance baseline, third-party distribution materials, frozen candidate association and release workflow remain pending. Development bundles are not public release assets. A restricted PATH on this host does not establish an absence of installed developer tools or runtimes. See [testing](../testing.md) for repeatable commands and [validation status](README.md) for the formal matrix.

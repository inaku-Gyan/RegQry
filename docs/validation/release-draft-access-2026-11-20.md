# Installation-token draft visibility, 2026-11-20

The first real tag, `v0.1.0`, points to merged main `c973d5029211f22fa0d25085ba4dc17398956507`. All six preparation PR jobs passed, but [the actual tag workflow](https://github.com/inaku-Gyan/RegQry/actions/runs/44608849190) failed at Inspect with `Draft visibility requires push access; absence cannot be inferred from this listing`. Every downstream job was skipped. No candidate, Cargo upload or GitHub Release was created. The original tag remains unchanged; corrected code uses version 0.1.1.

## Diagnosis

The original job setup reported `Contents: write` and `Metadata: read`. A separate diagnostic branch compared two real installation tokens in fresh hosted jobs: one Contents write, one Contents read. Both repository responses identified canonical repository ID 1462950131 and returned all user-role flags, including `permissions.push`, as false. The returned user-role flag therefore did not establish the token's actual Contents grant.

The [first diagnostic](https://github.com/inaku-Gyan/RegQry/actions/runs/44609865816) deliberately omitted a required field from a draft request. Both tokens returned HTTP 422 before permission evaluation, so this was rejected as a capability test. Its read-control assertion intentionally remained failed; it is not recorded as a successful permission check. Both before/after Release inventories were empty.

The [second diagnostic](https://github.com/inaku-Gyan/RegQry/actions/runs/44610294484), commit `2ed94740efbff9b8cefaa5c865c41f4a3d954c9b`, called `POST /repos/inaku-Gyan/RegQry/releases/generate-notes` with the existing tag. Both actual jobs passed their assertions:

| Token | Repository push flag | Actual generate-notes response | Release inventory |
| --- | --- | --- | --- |
| Contents write | false | HTTP 200 | Empty before and after |
| Contents read | false | HTTP 403 | Empty before and after |

The official [endpoint contract](https://docs.github.com/en/rest/releases/releases#generate-release-notes-content-for-a-release) requires Contents write and states that generated notes are not saved. No tag, Release, attachment or publication credential was created by the diagnostic. The branch is not merged into the product workflow.

## Fix and regression seam

Inspect now requires successful generate-notes capability verification before listing drafts. A failed request or malformed response remains unknown and blocks progression. Generated name/body are discarded; the reviewed CHANGELOG remains the release body. The change needs neither a GitHub App nor a PAT, and adds no manual approval.

The top-level release-state regression first replayed the installation-token response with `push: false` through the unchanged Inspect script. `test-release-gates.ps1 -ReportDirectory artifacts/draft-access-red` failed with the exact original visibility exception in 1.2 seconds. After the fix, the same caller scenario succeeded, required the exact tagged capability request and asserted zero remote mutations. A malformed response and a token denied that operation were also rejected. The full model passed 96 cases separately in PowerShell 7 and Windows PowerShell 5.1.26100.9818; these are synthetic regression/recovery checks, not frozen-candidate or channel acceptance. PowerShell 5.1 parsing, 30 local document links and locked 0.1.1 metadata also passed.

Original failed-run metadata/log/result and both diagnostic response trees are retained locally under `.scratch/registry-cli-implementation/v0.1.0-inspect-failure/`. Original red/green model records remain in the isolated fix worktree and its local progress logs. This record establishes the diagnosis and checks above; the corrected real tag/frozen candidate/OIDC/publication path still needs its own execution.

Native PR/main CI now uses `build-release-candidate.ps1`, the same MSVC/SDK selection wrapper used by tagged construction, before the unchanged asset/relocation checks. This closes the previously unexecuted native ARM64 wrapper path before another version tag. Development construction still does not freeze or formally accept a candidate; actual native results remain required.

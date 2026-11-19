# Manual terminal acceptance record

This manual matrix is deferred under the Actions-only first-release contract and is not a publication gate. Automated three-shell UTF-8/output/exit checks and actual console control events remain required. The following entries stay `not-run` until a human actually observes them.

This is an unexecuted template. Copy it outside the verified test bundle and replace fields with actual observations and evidence links. A filled checkbox or an automated hidden-console run does not establish visual acceptance. Use the already prepared disposable VM fixture and the same verified CLI/test-bundle bytes; never create a fixture on the workstation for this check. Preserve external VM rollback/destruction evidence after the run.

Deferred representative runs:

| Native system | Terminal | Columns | Status |
| --- | --- | --- | --- |
| x64 Windows 10 22H2 | Classic console | 80 and 120 | not-run |
| x64 Windows 11 stable | Windows Terminal | 80 and 120 | not-run |
| ARM64 Windows 11 24H2 | Classic console | 80 and 120 | not-run |
| ARM64 Windows 11 24H2 | Windows Terminal | 80 and 120 | not-run |

All three shells (cmd, Windows PowerShell 5.1, PowerShell 7) additionally need invocation/encoding records on each system. The VM shell case supplies those process-level checks; record its result and raw-log identity here. Do not multiply the visual table into every historical shell/terminal version.

For each visual run record:

- Candidate ID if frozen; otherwise explicitly `development, not formal acceptance`.
- Commit, version, CLI SHA-256, user ZIP/source/test ZIP/manifest hashes and VM context hash.
- Actual OS edition/build/stability, native/process architecture, ordinary-user SID and token elevation.
- Terminal name/version, shell executable/version, display scaling/font, actual buffer and window columns/rows, encoding/code page, exact commands and working directory.
- Scenario status (`pass`, `fail`, `not-run`, `missing`), observed behavior, stdout/stderr/exit code, and screenshot/transcript/raw-output locations where applicable.
- Setup/query run identities, external snapshot identity and rollback/destruction result.

Resize the actual visible terminal to 80, then 120 columns. Record how the dimensions were measured. A text file wrapped at a nominated width is not a terminal rendering. Preserve host settings; any current-session UTF-8 setup must be restored. The CLI itself changes no host settings. Use PowerShell's explicit UTF-8 capture recipe from the compatibility document in the source archive; cmd raw file redirection is a separate byte check.

In the ordinary query account, read the prepared context, derive the private base name as `RegQryAcceptance_<context.id>`, and use its actual value in the following commands. `BASE` below is a placeholder to replace, not a new environment variable for the product. PowerShell quotes are shown; cmd requires double quotes.

| Scenario / actual CLI arguments | Expected observation | Status / evidence |
| --- | --- | --- |
| Bare `regqry`, `-h`, then `--help` | Short/long help distinction, English, readable at both widths, no query, exit 0 | not-run |
| `--key-root 'HKLM\Software\BASE\Shell 空间' --view 64 --name=` | One key group, multiple value rows, Unicode and complete identities, empty default distinct, preview/type/bytes readable | not-run |
| `--key-root 'HKLM\Software\BASE\Long' --view 64 --data 'END-OF-LARGE-VALUE$'` | Full 6,000-unit value name, bounded data preview with external truncation marker, 1,048,614 stored bytes; normal terminal wrapping does not alter identity | not-run |
| `--key-root 'HKLM\Software\BASE\Long' --view 64 --name '^A\nB\t\x1B$'` | Name/data control characters escaped, no emitted ESC or extra record lines; Unicode text readable | not-run |
| `--key-root 'HKLM\Software\BASE\Shell 空间' --view 64 --name '^not-present$'` | Both streams empty, no pause/pager/prompt, exit 1 | not-run |
| Add `--key-root 'HKLM\Software\BASE\Acl\Denied'` to the shell query | Readable results survive; located English diagnostics and `search incomplete` on stderr; exit 2 | not-run |
| `--key-root 'HKLM\Software\BASE\Bulk' --view 64 --name '^Payload[0-7]$'`, physically press Ctrl+C after a VALUE arrives while still running | Prior results remain, cancellation reported, exit 130; record actual event-to-exit observation and method | not-run |

If the query finishes before the keyboard event, cancellation is not tested; record `not-run` and repeat on the owned fixture with a visible consumer. Never call a completed query “cancelled.” The automated job's generated console event remains separate evidence. Capture exit status immediately (`$LASTEXITCODE` in PowerShell, `%errorlevel%` in cmd); do not let the next command overwrite it.

Result order is unspecified. Review group boundaries and full identities without asserting a sort. Mark any replacement characters, broken Unicode, hidden identity truncation, confusing continuation/truncation, accidental control execution or unexpected prompts as failures and retain the evidence. Missing systems/terminals remain release blockers; this template grants no waiver.

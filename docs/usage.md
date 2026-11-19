# Usage

This development build provides help, version reporting, and argument validation. Query execution is pending; valid query invocations currently exit 2 with an explicit development-status diagnostic. Examples below document the agreed query interface.

```text
regqry [QUERY OPTIONS]
regqry -h | --help
regqry -V | --version
```

No arguments and `-h` print short help. `--help` prints the full reference. Help and version exit 0 without querying the registry. There are no subcommands, positional patterns, separate viewing mode, pager, prompts, or stdin target lists.

Once implemented, providing any query option starts a query. Defaults are `--key-root HKCU --key-root HKLM` and both supported views. A root can be any full key path; explicit roots replace the defaults. Only descendants are searched, including those descendants' values. The root itself and its own values are excluded.

PowerShell examples:

```powershell
regqry --key-root 'HKCU\Software' --key-glob '**\Acme'
regqry --key-root 'HKLM\Software\Vendor' --key '^Acme$' --name '^InstallPath$' --view 64
regqry --name 'Path' --data-i 'vendor'
regqry --name '^$'
regqry --data-not-set
regqry --type sz --type dword --not-type dword
```

`--name Path` is a substring regex; `--name '^Path$'` constrains the whole name. To locate a known key itself, use its parent as the root. With only root/key/time/view conditions, results are keys. A name/data/type condition selects individual values. `--name '.*'` enumerates actual values; only explicit `--data-not-set` adds missing-default states.

Each argument takes one value; repeat the option for multiple conditions. Use `--data=-legacy` for a leading hyphen and `--name=` for an empty regex. The program adds no generic escape decoding or environment expansion to arguments. Shell quoting, regex/glob syntax, and output escaping are separate; see [matching](matching.md) and [compatibility](compatibility.md).

The agreed query exit codes are 0 for complete queries with matches, 1 for complete zero matches, 2 for invalid input/incomplete execution/output failure, and 130 for cancellation. Zero matches produce no stdout or stderr. Partial failures retain prior results but still exit 2. Live traversal is not a consistent registry snapshot.

Default output will stream consecutive values grouped by key/view, preserving full identity. It is fixed UTF-8 text; diagnostics use stderr. Previews are explicitly limited and marked when truncated, and do not limit matching. Extra output-format/detail controls are deferred.

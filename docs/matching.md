# Matching reference

This is the agreed query contract. The foundation build validates arguments; execution is pending.

| Group | Options |
| --- | --- |
| Roots | `--key-root ROOT` |
| Relative key path | `--key REGEX`, `--key-glob GLOB` |
| Value name | `--name REGEX`, `--name-glob GLOB` |
| Data | `--data REGEX`, `--data-i REGEX` / `--data-case-insensitive REGEX`, `--data-expand REGEX`, `--data-glob GLOB`, `--data-iglob GLOB` / `--data-glob-case-insensitive GLOB`, `--data-hex HEX`, `--data-not-set`, `--data-empty`, `--data-zero-length` |
| Value type | `-t` / `--type TYPE`, `-T` / `--not-type TYPE` |

Every option is repeatable. Roots/key/name/data conditions are ORed within each group, with AND between groups. Name, data, and type must match the same value. Positive types are ORed, then all excluded types are removed; any type condition requires an actual value. An omitted group adds no restriction. Repeating a flag without a value is idempotent.

`--view 32` and `--view 64` form a union; omitted views mean all supported views. `--key-modified-after TIME` and `--key-modified-before TIME` all apply with strict comparisons. The owning key's last-write time applies to value results.

Regex matches substrings using the `regex` crate's Unicode syntax. Key/name patterns default to case-insensitive, data patterns to case-sensitive. The `-i` data forms carry independent patterns rather than changing surrounding options. Inline flags can override defaults. Look-around and backreferences are unsupported. `--name-regex` and `--data-regex` are not accepted aliases.

Glob matches the whole field with `*`, `?`, character sets/ranges, and `!`/`^` set negation. Unclosed `[` is literal; descending ranges and POSIX bracket extensions are rejected. In key globs, `\` separates components and standalone `**` spans zero or more components: `Vendor\**` includes `Vendor`, and `**\Acme` includes direct and deeper keys. Ordinary glob atoms stay within one component. `/` is a name character. In name/data globs, both slashes are literal. A failed key filter never prunes its descendants.

ROOT accepts case-insensitive HKCU, HKLM, HKCR, HKU, HKCC and the corresponding full HKEY names. Backslash separates path components; one trailing backslash is accepted. Other empty components, remote paths, PowerShell `HKCU:` drive syntax, and performance roots are rejected. Name whitespace and non-hive UTF-16 units are preserved.

TYPE accepts official REG names or their suffixes, case-insensitively, with `-` and `_` equivalent; unsigned decimal or `0x` u32 codes support unknown types. Leading zeroes remain decimal. No signs, comma lists, or type bitmasks are accepted.

TIME accepts a strict `YYYY-MM-DD` local midnight, offset-bearing RFC 3339, or an integer age composed of ns/us/ms/s/m/h/d/w, such as `1h30m`. One day is 24 hours; months/years/fractions are rejected. Ambiguous or nonexistent local midnight requires an explicit-offset timestamp. Relative ages use one query-start instant.

Text data matching uses saved SZ/EXPAND_SZ strings, each MULTI_SZ element independently, or unsigned decimal DWORD/QWORD text. Other types are not guessed as text. `--data-hex` matches a raw byte subsequence including terminators/byte order; provide nonempty byte pairs with optional ASCII whitespace.

`--data-not-set` selects a confirmed missing default value, with no type/data. `--data-empty` selects logical emptiness in an actual supported value, not integer zero. `--data-zero-length` selects any actual value with zero stored bytes. REG_NONE is an actual type, not an absence marker.

Only `--data-expand` expands saved EXPAND_SZ text, using one CLI-process environment snapshot. Expansion pairs the nearest percent signs left to right; empty `%%`, unknown names, and unmatched percent signs remain literal. Variable names use Windows ordinal case-insensitive comparison; empty values substitute empty text. Inserted text is not scanned again. Patterns are not expanded, and changing views does not change this environment.

Necessary read/interpretation failures make the query incomplete, with diagnostics, even if other results exist. An inapplicable data type is an ordinary nonmatch. Another sufficient OR condition can avoid unnecessary decoding. Filtering never uses escaped/truncated output as input.

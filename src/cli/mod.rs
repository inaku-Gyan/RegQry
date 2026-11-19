mod validate;

use clap::builder::{OsStringValueParser, TypedValueParser, ValueParser};
use clap::{Arg, ArgAction, Command};
use jiff::Timestamp;
use std::io::Write;
use std::process::ExitCode;

const REFERENCE: &str = "MATCHING
  Repeated conditions within root, key, name, or data groups are ORed.
  Different groups are ANDed; name, data, and type must match the same value.
  Positive types are ORed, then every excluded type is removed.
  Views form a union. Time bounds are strict and all apply.

  Roots default to HKCU and HKLM. Explicit roots replace these defaults.
  Only descendants are searched; a root and its own values are excluded.
  Key patterns use paths relative to each root. Overlapping roots are
  evaluated separately before identities are deduplicated within each view.

  Regex searches substrings. Key/name matching ignores case by default;
  data is case-sensitive unless its own option says otherwise. Inline regex
  flags can override defaults. Look-around and backreferences are unsupported.
  Glob matches the whole field using * ? [] (no POSIX extensions).
  In key globs, backslash separates components and standalone ** spans zero
  or more components. In name/data globs, slashes are literal characters.

DATA
  Text: saved SZ/EXPAND_SZ, each MULTI_SZ element, or unsigned decimal
  DWORD/QWORD. Binary, NONE, and unknown types are not guessed as text.
  --data-expand applies only to EXPAND_SZ, with a single nonrecursive pass
  using the CLI process environment captured at query start. Unknown %NAME%
  references are preserved. Saved data and default previews remain unchanged.
  HEX is a nonempty sequence of byte pairs, with optional ASCII whitespace.
  Not-set means a missing default value, not an empty string or REG_NONE.
  Empty means logically empty data; zero-length means zero stored bytes.

TARGETS AND TIME
  ROOT: HKCU/HKLM/HKCR/HKU/HKCC or their HKEY_* names, optionally followed
  by a backslash-separated path. One trailing backslash is accepted. Other
  empty components, PowerShell drive syntax, and remote paths are rejected.
  TYPE: REG_SZ, sz, expand-sz, etc. (case-insensitive, - and _ equivalent),
  or a decimal/0x hexadecimal u32 type code. Repeat options for multiple types.
  TIME: YYYY-MM-DD at local midnight, RFC 3339 with an offset, or integer
  ages such as 7d or 1h30m (ns/us/ms/s/m/h/d/w; 1d = 24h). Ambiguous or
  nonexistent local midnight is rejected. Relative ages share one start time.

EXAMPLES (PowerShell; query execution is not available in this build)
  regqry --key-root 'HKCU\\Software' --key-glob '**\\Acme'
  regqry --name '^Path$' --data-i 'vendor' --view 64
  regqry --type sz --type dword --not-type dword
  regqry --data-hex 'DE AD BE EF'

EXIT STATUS
  0  Complete query with matches, or help/version
  1  Complete query with no matches (both output streams are empty)
  2  Invalid input, incomplete query, or output failure
  130  Canceled; prior output is retained

  Results use fixed UTF-8 text. Diagnostics use stderr. There is no sorting,
  paging, stdin target list, or interactive mode. Bind a leading-hyphen value
  with --option=value. Shell quoting and output escaping are different.
  See docs/compatibility.md for PowerShell encoding and redirection details.";

pub(crate) fn command() -> Command {
    let started_at = Timestamp::now();
    let time_parser = ValueParser::new(move |value: &str| validate::time(value, started_at));
    let mut cmd = Command::new("regqry")
        .version(env!("CARGO_PKG_VERSION"))
        .about("Search the Windows Registry")
        .before_help(
            "Development build: help and validation only; query execution is not yet available.",
        )
        .override_usage("regqry [QUERY OPTIONS]")
        .term_width(80)
        .max_term_width(80)
        .args_override_self(true)
        .after_help("Use --help for the full matching reference. No arguments display this help.")
        .after_long_help(REFERENCE)
        .arg(
            Arg::new("key-root")
                .long("key-root")
                .value_name("ROOT")
                .action(ArgAction::Append)
                .help_heading("Scope")
                .help("Search descendants of this root (repeatable; default: HKCU and HKLM)")
                .value_parser(OsStringValueParser::new().try_map(validate::root)),
        )
        .arg(
            Arg::new("view")
                .long("view")
                .value_name("VIEW")
                .action(ArgAction::Append)
                .help_heading("Scope")
                .help("Select 32 or 64 (repeatable; default: all supported views)")
                .value_parser(["32", "64"]),
        );

    for (name, help, parser, heading) in [
        (
            "key",
            "Regex on the relative key path (ignores case)",
            ValueParser::new(validate::regex_i),
            "Key filters",
        ),
        (
            "key-glob",
            "Glob on the relative key path (ignores case)",
            ValueParser::new(validate::key_glob),
            "Key filters",
        ),
        (
            "name",
            "Regex on the value name (ignores case)",
            ValueParser::new(validate::regex_i),
            "Value filters",
        ),
        (
            "name-glob",
            "Glob on the value name (ignores case)",
            ValueParser::new(validate::glob_i),
            "Value filters",
        ),
        (
            "data",
            "Regex on saved data text",
            ValueParser::new(validate::regex),
            "Data filters",
        ),
        (
            "data-i",
            "Independent case-insensitive data regex",
            ValueParser::new(validate::regex_i),
            "Data filters",
        ),
        (
            "data-expand",
            "Regex after expanding EXPAND_SZ environment references",
            ValueParser::new(validate::regex),
            "Data filters",
        ),
        (
            "data-glob",
            "Glob on saved data text",
            ValueParser::new(validate::glob),
            "Data filters",
        ),
        (
            "data-iglob",
            "Independent case-insensitive data glob",
            ValueParser::new(validate::glob_i),
            "Data filters",
        ),
        (
            "data-hex",
            "Raw byte subsequence, e.g. 'DE AD BE EF'",
            ValueParser::new(validate::hex),
            "Data filters",
        ),
        (
            "type",
            "Include a value type (positive types are ORed)",
            ValueParser::new(validate::value_type),
            "Value filters",
        ),
        (
            "not-type",
            "Exclude a value type (all exclusions apply)",
            ValueParser::new(validate::value_type),
            "Value filters",
        ),
        (
            "key-modified-after",
            "Key last-write time strictly after TIME",
            time_parser.clone(),
            "Time filters",
        ),
        (
            "key-modified-before",
            "Key last-write time strictly before TIME",
            time_parser,
            "Time filters",
        ),
    ] {
        let value_name = match name {
            "key" | "name" | "data" | "data-i" | "data-expand" => "REGEX",
            "type" | "not-type" => "TYPE",
            "data-hex" => "HEX",
            "key-modified-after" | "key-modified-before" => "TIME",
            _ => "GLOB",
        };
        let mut arg = Arg::new(name)
            .long(name)
            .value_name(value_name)
            .action(ArgAction::Append)
            .value_parser(parser)
            .help(help)
            .help_heading(heading);
        arg = match name {
            "type" => arg.short('t'),
            "not-type" => arg.short('T'),
            "data-i" => arg.visible_alias("data-case-insensitive"),
            "data-iglob" => arg.visible_alias("data-glob-case-insensitive"),
            _ => arg,
        };
        cmd = cmd.arg(arg);
    }
    for (name, help) in [
        ("data-not-set", "Match a confirmed missing default value"),
        (
            "data-empty",
            "Match logically empty data in an existing value",
        ),
        (
            "data-zero-length",
            "Match an existing value with zero stored bytes",
        ),
    ] {
        cmd = cmd.arg(
            Arg::new(name)
                .long(name)
                .action(ArgAction::SetTrue)
                .help_heading("Data filters")
                .help(help),
        );
    }
    cmd
}

pub(crate) fn run() -> ExitCode {
    let args: Vec<_> = std::env::args_os().collect();
    let mut cmd = command();
    if args.len() == 1 {
        return match cmd.print_help() {
            Ok(()) => ExitCode::SUCCESS,
            Err(error) => {
                let _ = writeln!(
                    std::io::stderr().lock(),
                    "regqry: cannot write help: {error}"
                );
                ExitCode::from(2)
            }
        };
    }
    match cmd.try_get_matches_from(args) {
        Ok(_) => {
            let _ = writeln!(
                std::io::stderr().lock(),
                "regqry: query execution is not implemented in this development build"
            );
            ExitCode::from(2)
        }
        Err(error) => {
            let code = if error.use_stderr() { 2 } else { 0 };
            if error.print().is_err() {
                return ExitCode::from(2);
            }
            ExitCode::from(code)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn repeated_conditions_and_aliases_accumulate() {
        let args = command()
            .try_get_matches_from([
                "regqry",
                "--name=",
                "--name=Path",
                "--data-i=one",
                "--data-case-insensitive=two",
                "--view=32",
                "--view=64",
                "--data-not-set",
                "--data-not-set",
            ])
            .unwrap();
        assert_eq!(args.get_many::<regex::Regex>("name").unwrap().count(), 2);
        assert_eq!(args.get_many::<regex::Regex>("data-i").unwrap().count(), 2);
        assert_eq!(args.get_many::<String>("view").unwrap().count(), 2);
        assert!(args.get_flag("data-not-set"));
    }

    #[test]
    fn type_aliases_use_the_same_code() {
        let args = command()
            .try_get_matches_from([
                "regqry", "-t", "sz", "-t", "REG_SZ", "-t", "1", "-t", "0x1", "-T", "none",
            ])
            .unwrap();
        assert_eq!(
            args.get_many::<u32>("type")
                .unwrap()
                .copied()
                .collect::<Vec<_>>(),
            [1, 1, 1, 1]
        );
        assert_eq!(
            args.get_many::<u32>("not-type")
                .unwrap()
                .copied()
                .collect::<Vec<_>>(),
            [0]
        );
    }
}

use jiff::{Timestamp, civil::Date, fmt::friendly::SpanParser, tz::TimeZone};
use regex::{Regex, RegexBuilder};
use std::ffi::OsString;
use std::os::windows::ffi::OsStrExt;
use yash_fnmatch::ast::{Ast, Atom, BracketAtom, BracketItem};

pub(super) fn root(value: OsString) -> Result<OsString, String> {
    let units: Vec<_> = value.encode_wide().collect();
    if units.contains(&0) {
        return Err("ROOT contains a NUL code unit".into());
    }
    let mut components = units.split(|unit| *unit == b'\\' as u16);
    let hive = String::from_utf16(components.next().unwrap_or_default())
        .map_err(|_| "ROOT must start with HKCU, HKLM, HKCR, HKU, or HKCC")?;
    if !matches!(
        hive.to_ascii_uppercase().as_str(),
        "HKCU"
            | "HKEY_CURRENT_USER"
            | "HKLM"
            | "HKEY_LOCAL_MACHINE"
            | "HKCR"
            | "HKEY_CLASSES_ROOT"
            | "HKU"
            | "HKEY_USERS"
            | "HKCC"
            | "HKEY_CURRENT_CONFIG"
    ) {
        return Err("ROOT must start with HKCU, HKLM, HKCR, HKU, or HKCC".into());
    }
    let mut rest = components.peekable();
    while let Some(component) = rest.next() {
        if component.is_empty() && rest.peek().is_some() {
            return Err("ROOT contains an empty path component".into());
        }
    }
    Ok(value)
}

pub(super) fn regex(value: &str) -> Result<Regex, String> {
    compile_regex(value, false)
}
pub(super) fn regex_i(value: &str) -> Result<Regex, String> {
    compile_regex(value, true)
}

fn compile_regex(value: &str, ignore_case: bool) -> Result<Regex, String> {
    RegexBuilder::new(value)
        .case_insensitive(ignore_case)
        .build()
        .map_err(|e| e.to_string())
}

pub(crate) fn compile_glob(value: &str, ignore_case: bool) -> Result<Regex, String> {
    let ast = Ast::new(yash_fnmatch::without_escape(value));
    for atom in &ast.atoms {
        if let Atom::Bracket(bracket) = atom {
            for item in &bracket.items {
                let basic = match item {
                    BracketItem::Atom(atom) => matches!(atom, BracketAtom::Char(_)),
                    BracketItem::Range(range) => {
                        matches!(range.start(), BracketAtom::Char(_))
                            && matches!(range.end(), BracketAtom::Char(_))
                    }
                };
                if !basic {
                    return Err("POSIX bracket extensions are not supported; use * ? []".into());
                }
            }
        }
    }
    let mut config = yash_fnmatch::Config::default();
    config.anchor_begin = true;
    config.anchor_end = true;
    let source = ast.to_regex(&config).map_err(|e| e.to_string())?;
    RegexBuilder::new(&source)
        .case_insensitive(ignore_case)
        .dot_matches_new_line(true)
        .build()
        .map_err(|e| e.to_string())
}

fn validate_glob(value: &str, ignore_case: bool, is_key: bool) -> Result<String, String> {
    if is_key {
        for component in value.split('\\') {
            if component != "**" {
                compile_glob(component, ignore_case)?;
            }
        }
    } else {
        compile_glob(value, ignore_case)?;
    }
    Ok(value.to_owned())
}

pub(super) fn key_glob(value: &str) -> Result<String, String> {
    validate_glob(value, true, true)
}
pub(super) fn glob(value: &str) -> Result<String, String> {
    validate_glob(value, false, false)
}
pub(super) fn glob_i(value: &str) -> Result<String, String> {
    validate_glob(value, true, false)
}

pub(super) fn hex(value: &str) -> Result<Vec<u8>, String> {
    let compact: String = value.chars().filter(|c| !c.is_ascii_whitespace()).collect();
    if compact.is_empty() {
        return Err("HEX must contain at least one complete byte".into());
    }
    hex::decode(compact).map_err(|e| e.to_string())
}

pub(super) fn value_type(value: &str) -> Result<u32, String> {
    let name = value.to_ascii_lowercase().replace('-', "_");
    let name = name.strip_prefix("reg_").unwrap_or(&name);
    let known = match name {
        "none" => Some(0),
        "sz" => Some(1),
        "expand_sz" => Some(2),
        "binary" => Some(3),
        "dword" | "dword_little_endian" => Some(4),
        "dword_big_endian" => Some(5),
        "link" => Some(6),
        "multi_sz" => Some(7),
        "resource_list" => Some(8),
        "full_resource_descriptor" => Some(9),
        "resource_requirements_list" => Some(10),
        "qword" | "qword_little_endian" => Some(11),
        _ => None,
    };
    if let Some(code) = known {
        return Ok(code);
    }
    let result = if let Some(hex) = value
        .strip_prefix("0x")
        .or_else(|| value.strip_prefix("0X"))
    {
        if hex.is_empty() || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err("TYPE requires a known name or unsigned u32 code".into());
        }
        u32::from_str_radix(hex, 16)
    } else {
        if value.is_empty() || !value.bytes().all(|b| b.is_ascii_digit()) {
            return Err("TYPE requires a known name or unsigned u32 code".into());
        }
        value.parse()
    };
    result.map_err(|e| format!("TYPE is outside the unsigned u32 range: {e}"))
}

pub(super) fn time(value: &str, started_at: Timestamp) -> Result<Timestamp, String> {
    let bytes = value.as_bytes();
    if bytes.len() == 10
        && bytes[4] == b'-'
        && bytes[7] == b'-'
        && bytes
            .iter()
            .enumerate()
            .all(|(i, b)| i == 4 || i == 7 || b.is_ascii_digit())
    {
        let date = value.parse::<Date>().map_err(|e| e.to_string())?;
        let zone =
            TimeZone::try_system().map_err(|e| format!("cannot determine local time zone: {e}"))?;
        return local_midnight(date, &zone);
    }
    static RFC3339: std::sync::LazyLock<Regex> = std::sync::LazyLock::new(|| {
        Regex::new(r"\A[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt][0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?(?:[Zz]|[+-][0-9]{2}:[0-9]{2})\z")
            .expect("valid RFC 3339 shape")
    });
    if RFC3339.is_match(value) {
        return value.parse::<Timestamp>().map_err(|e| e.to_string());
    }
    static AGE: std::sync::LazyLock<Regex> = std::sync::LazyLock::new(|| {
        Regex::new(r"\A(?:[0-9]+(?:ns|us|ms|s|m|h|d|w))+\z").expect("valid age syntax")
    });
    if !AGE.is_match(value) {
        return Err("TIME requires YYYY-MM-DD, RFC 3339 with an offset, or an integer age (ns/us/ms/s/m/h/d/w)".into());
    }
    // Jiff requires descending, unique units in one span. Parse each allowed
    // term with the library so our repeated/any-order age contract is preserved.
    static TERM: std::sync::LazyLock<Regex> = std::sync::LazyLock::new(|| {
        Regex::new(r"[0-9]+(?:ns|us|ms|s|m|h|d|w)").expect("valid age term syntax")
    });
    let mut bound = started_at;
    for term in TERM.find_iter(value) {
        let age = SpanParser::new()
            .parse_span(term.as_str())
            .and_then(|span| span.to_duration(jiff::SpanRelativeTo::days_are_24_hours()))
            .map_err(|e| e.to_string())?;
        bound = bound
            .checked_sub(age)
            .map_err(|e| format!("TIME is outside the supported timestamp range: {e}"))?;
    }
    Ok(bound)
}

fn local_midnight(date: Date, zone: &TimeZone) -> Result<Timestamp, String> {
    zone.to_ambiguous_timestamp(date.at(0, 0, 0, 0))
        .unambiguous()
        .map_err(|e| {
            format!("local midnight is ambiguous or nonexistent; use RFC 3339 with an offset: {e}")
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::windows::ffi::OsStringExt;

    #[test]
    fn roots_preserve_names_and_reject_empty_components() {
        for valid in [
            r"hKcU",
            r"HKEY_LOCAL_MACHINE\",
            r"HKCU\Name/With/Slashes",
            r"HKU\ Name ",
        ] {
            assert!(root(valid.into()).is_ok(), "{valid}");
        }
        for invalid in [
            "",
            r"HKCU:",
            r"\\machine\HKCU",
            r"HKCU\\",
            r"HKCU\A\\B",
            "HKCU\\A\0B",
        ] {
            assert!(root(invalid.into()).is_err(), "{invalid:?}");
        }
        let abnormal = OsString::from_wide(&[72, 75, 67, 85, 92, 0xD800]);
        assert_eq!(root(abnormal.clone()).unwrap(), abnormal);
    }

    #[test]
    fn glob_uses_unicode_and_rejects_only_actual_extensions() {
        assert!(compile_glob("É", true).unwrap().is_match("é"));
        assert!(compile_glob("?", false).unwrap().is_match("😀"));
        assert!(compile_glob(r"A\B", false).unwrap().is_match(r"A\B"));
        assert!(glob("[").is_ok());
        for invalid in ["[z-a]", "[[:digit:]]", "[[.x|y.]]", "[[=x=]]"] {
            assert!(glob(invalid).is_err(), "{invalid}");
        }
    }

    #[test]
    fn type_numbers_and_hex_have_strict_boundaries() {
        assert_eq!(value_type("0xffffffff").unwrap(), u32::MAX);
        assert_eq!(value_type("0008").unwrap(), 8);
        for invalid in ["+1", "-1", "0x", "4294967296", "sz,dword", "REG_1"] {
            assert!(value_type(invalid).is_err(), "{invalid}");
        }
        assert_eq!(hex("DE ad\t00").unwrap(), [0xde, 0xad, 0]);
        for invalid in ["", " ", "A", "DE\u{a0}AD", "0xFF"] {
            assert!(hex(invalid).is_err(), "{invalid:?}");
        }
    }

    #[test]
    fn time_ages_share_a_start_and_disallow_wide_duration_syntax() {
        let start: Timestamp = "2026-11-19T12:00:00Z".parse().unwrap();
        assert_eq!(
            time("1h30m", start).unwrap(),
            start - jiff::SignedDuration::from_secs(90 * 60)
        );
        assert_eq!(
            time("1d", start).unwrap(),
            start - jiff::SignedDuration::from_secs(24 * 60 * 60)
        );
        assert_eq!(
            time("1w", start).unwrap(),
            start - jiff::SignedDuration::from_secs(7 * 24 * 60 * 60)
        );
        assert_eq!(time("30m1h", start).unwrap(), time("1h30m", start).unwrap());
        assert_eq!(
            time("1h1h", start).unwrap(),
            start - jiff::SignedDuration::from_secs(2 * 60 * 60)
        );
        assert_eq!(time("2026-11-19T14:00:00+02:00", start).unwrap(), start);
        for invalid in [
            "1year",
            "1month",
            "1.5h",
            "1 hour",
            "2026-2-01",
            "2026-02-30",
            "2026-11-19T12:00:00",
            "999999999999999999999999w",
        ] {
            assert!(time(invalid, start).is_err(), "{invalid}");
        }
    }

    #[test]
    fn ambiguous_and_nonexistent_midnight_are_rejected() {
        let gap = TimeZone::get("America/Sao_Paulo").unwrap();
        assert!(local_midnight("2018-11-04".parse().unwrap(), &gap).is_err());
        let fold = TimeZone::get("America/Havana").unwrap();
        assert!(local_midnight("2020-11-01".parse().unwrap(), &fold).is_err());
        assert!(local_midnight("2020-11-02".parse().unwrap(), &fold).is_ok());
    }
}

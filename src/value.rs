use regex::Regex;
use std::{
    ffi::{OsStr, OsString},
    sync::{LazyLock, OnceLock},
};

pub(crate) struct RawValue {
    pub(crate) name: OsString,
    pub(crate) kind: u32,
    pub(crate) bytes: Vec<u8>,
    decoded: OnceLock<Result<Decoded, &'static str>>,
}
pub(crate) enum Decoded {
    Text(String),
    List(Vec<String>),
    Integer(u64),
    Raw,
}
impl RawValue {
    pub(crate) fn new(name: OsString, kind: u32, bytes: Vec<u8>) -> Self {
        Self {
            name,
            kind,
            bytes,
            decoded: OnceLock::new(),
        }
    }
    pub(crate) fn decoded(&self) -> Result<&Decoded, &'static str> {
        self.decoded
            .get_or_init(|| decode(self.kind, &self.bytes))
            .as_ref()
            .map_err(|e| *e)
    }
    pub(crate) fn empty(&self) -> Result<bool, &'static str> {
        Ok(match self.decoded()? {
            Decoded::Text(s) => s.is_empty(),
            Decoded::List(s) => s.is_empty(),
            Decoded::Integer(_) => false,
            Decoded::Raw => matches!(self.kind, 0 | 3) && self.bytes.is_empty(),
        })
    }
    pub(crate) fn text_matches(&self, regex: &Regex) -> Result<bool, &'static str> {
        Ok(match self.decoded()? {
            Decoded::Text(text) => regex.is_match(text),
            Decoded::List(items) => items.iter().any(|text| regex.is_match(text)),
            Decoded::Integer(number) => regex.is_match(&number.to_string()),
            Decoded::Raw => false,
        })
    }
}
fn decode(kind: u32, bytes: &[u8]) -> Result<Decoded, &'static str> {
    match kind {
        1 | 2 | 7 => {
            if !bytes.len().is_multiple_of(2) {
                return Err("odd UTF-16 byte length");
            }
            let mut units: Vec<_> = bytes
                .as_chunks::<2>()
                .0
                .iter()
                .map(|b| u16::from_le_bytes(*b))
                .collect();
            if kind != 7 {
                if units.last() == Some(&0) {
                    units.pop();
                }
                return String::from_utf16(&units)
                    .map(Decoded::Text)
                    .map_err(|_| "invalid UTF-16");
            }
            if units.as_slice() == [0] || units.as_slice() == [0, 0] {
                return Ok(Decoded::List(Vec::new()));
            }
            if !units.ends_with(&[0, 0]) {
                return Err("MULTI_SZ is missing its sequence terminator");
            }
            units.truncate(units.len() - 2);
            let mut items = Vec::new();
            for item in units.split(|c| *c == 0) {
                if item.is_empty() {
                    return Err("MULTI_SZ has content after its sequence terminator");
                }
                items.push(String::from_utf16(item).map_err(|_| "invalid UTF-16")?);
            }
            Ok(Decoded::List(items))
        }
        4 | 5 => {
            let array: [u8; 4] = bytes
                .try_into()
                .map_err(|_| "DWORD requires exactly 4 bytes")?;
            Ok(Decoded::Integer(u64::from(if kind == 5 {
                u32::from_be_bytes(array)
            } else {
                u32::from_le_bytes(array)
            })))
        }
        11 => Ok(Decoded::Integer(u64::from_le_bytes(
            bytes
                .try_into()
                .map_err(|_| "QWORD requires exactly 8 bytes")?,
        ))),
        _ => Ok(Decoded::Raw),
    }
}

pub(crate) struct Environment(Vec<(OsString, OsString)>);
impl Environment {
    #[cfg(test)]
    pub(crate) fn from_entries(entries: Vec<(OsString, OsString)>) -> Self {
        Self(entries)
    }
    pub(crate) fn capture() -> Self {
        Self(std::env::vars_os().collect())
    }
    pub(crate) fn expand(&self, text: &str) -> Result<String, String> {
        static REFERENCES: LazyLock<Regex> =
            LazyLock::new(|| Regex::new("%[^%]*%").expect("environment reference regex"));
        let mut error = None;
        let expanded = REFERENCES.replace_all(text, |captures: &regex::Captures<'_>| {
            let source = &captures[0];
            let name = &source[1..source.len() - 1];
            if !name.is_empty() {
                for (key, value) in &self.0 {
                    match crate::registry::ordinal(key, OsStr::new(name)) {
                        Ok(std::cmp::Ordering::Equal) => {
                            return value.to_str().map(str::to_owned).unwrap_or_else(|| {
                                error = Some(
                                    "environment replacement contains invalid UTF-16".to_owned(),
                                );
                                source.to_owned()
                            });
                        }
                        Ok(_) => {}
                        Err(e) => error = Some(format!("cannot compare environment name: {e}")),
                    }
                }
            }
            source.to_owned()
        });
        match error {
            Some(e) => Err(e),
            None => Ok(expanded.into_owned()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn utf16(text: &str) -> Vec<u8> {
        text.encode_utf16().flat_map(u16::to_le_bytes).collect()
    }
    #[test]
    fn stored_strings_keep_internal_and_extra_nuls() {
        for (stored, expected) in [
            ("", ""),
            ("\0", ""),
            ("A", "A"),
            ("A\0", "A"),
            ("A\0B\0", "A\0B"),
            ("\0\0", "\0"),
            ("A\0\0", "A\0"),
        ] {
            let value = RawValue::new("".into(), 1, utf16(stored));
            assert!(matches!(value.decoded(), Ok(Decoded::Text(s)) if s == expected));
        }
        for bytes in [vec![65, 0, 255], vec![0, 216]] {
            assert!(RawValue::new("".into(), 1, bytes).decoded().is_err());
        }
    }
    #[test]
    fn multi_sz_and_integer_boundaries_are_exact() {
        for stored in ["\0", "\0\0"] {
            assert!(RawValue::new("".into(), 7, utf16(stored)).empty().unwrap());
        }
        let list = RawValue::new("".into(), 7, utf16("A\0B\0\0"));
        assert!(matches!(list.decoded(), Ok(Decoded::List(items)) if items == &["A", "B"]));
        for stored in ["", "\0\0\0", "A\0", "A\0\0\0", "A\0\0B\0\0"] {
            assert!(
                RawValue::new("".into(), 7, utf16(stored))
                    .decoded()
                    .is_err(),
                "{stored:?}"
            );
        }
        assert!(matches!(
            RawValue::new("".into(), 5, vec![0, 0, 0, 1]).decoded(),
            Ok(Decoded::Integer(1))
        ));
        assert!(RawValue::new("".into(), 4, vec![]).decoded().is_err());
        assert!(!RawValue::new("".into(), 4, vec![0; 4]).empty().unwrap());
    }
    #[test]
    fn expansion_is_snapshot_based_and_nonrecursive() {
        let env = Environment(vec![
            ("A".into(), "%B%".into()),
            ("b".into(), "two".into()),
            ("E".into(), "".into()),
        ]);
        assert_eq!(
            env.expand("%a%%B%/%E%/%%A%/%UNKNOWN%/%").unwrap(),
            "%B%two//%%A%/%UNKNOWN%/%"
        );
    }
}

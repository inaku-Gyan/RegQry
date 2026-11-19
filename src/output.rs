use crate::{
    query::{Sink, Summary, Target},
    value::{Decoded, RawValue},
};
use std::{
    ffi::OsStr,
    io::{self, Write},
    os::windows::ffi::OsStrExt,
};

fn escaped(character: char) -> String {
    match character {
        '\\' => "\\\\".into(),
        '"' => "\\\"".into(),
        '\n' => "\\n".into(),
        '\r' => "\\r".into(),
        '\t' => "\\t".into(),
        '\0' => "\\0".into(),
        c if c.is_control() => format!("\\u{{{:X}}}", c as u32),
        c => c.to_string(),
    }
}
pub(crate) fn name(name: &OsStr, quote: bool) -> String {
    let mut output = String::new();
    if quote {
        output.push('"');
    }
    for unit in char::decode_utf16(name.encode_wide()) {
        match unit {
            Ok('\\') if !quote => output.push('\\'),
            Ok(character) => output.push_str(&escaped(character)),
            Err(error) => output.push_str(&format!("\\u16{{{:04X}}}", error.unpaired_surrogate())),
        }
    }
    if quote {
        output.push('"');
    }
    output
}
fn path(path: &OsStr) -> String {
    let needs_quotes = char::decode_utf16(path.encode_wide()).any(|unit| match unit {
        Ok(c) => c.is_control() || c == '"',
        Err(_) => true,
    });
    if needs_quotes {
        name(path, true)
    } else {
        path.to_str().expect("valid unquoted path").to_owned()
    }
}
fn preview_text<T: AsRef<str>>(items: impl IntoIterator<Item = T>, list: bool) -> (String, bool) {
    let mut output = if list {
        String::from("[")
    } else {
        String::new()
    };
    let mut count = usize::from(list);
    let mut truncated = false;
    for (index, item) in items.into_iter().enumerate() {
        let prefix = if index == 0 { "\"" } else { ", \"" };
        if count + prefix.len() + 1 + usize::from(list) > 120 {
            truncated = true;
            break;
        }
        output.push_str(prefix);
        count += prefix.len();
        for character in item.as_ref().chars() {
            let token = escaped(character);
            let size = token.chars().count();
            if count + size + 1 + usize::from(list) > 120 {
                truncated = true;
                break;
            }
            output.push_str(&token);
            count += size;
        }
        output.push('"');
        count += 1;
        if truncated {
            break;
        }
    }
    if list {
        output.push(']');
    }
    (output, truncated)
}
fn raw_preview(bytes: &[u8]) -> (String, bool) {
    (
        format!(
            "hex[{}]",
            bytes
                .iter()
                .take(32)
                .map(|b| format!("{b:02X}"))
                .collect::<Vec<_>>()
                .join(" ")
        ),
        bytes.len() > 32,
    )
}
fn preview(value: &RawValue) -> (String, bool) {
    match value.decoded() {
        Ok(Decoded::Text(text)) => preview_text([text], false),
        Ok(Decoded::List(items)) => preview_text(items, true),
        Ok(Decoded::Integer(integer)) => (
            format!(
                "{integer} (0x{integer:0width$X})",
                width = if value.kind == 11 { 16 } else { 8 }
            ),
            false,
        ),
        Ok(Decoded::Raw) => raw_preview(&value.bytes),
        Err(reason) => {
            let (raw, truncated) = raw_preview(&value.bytes);
            (
                format!("[interpretation unavailable: {reason}] {raw}"),
                truncated,
            )
        }
    }
}
fn type_name(kind: u32) -> &'static str {
    match kind {
        0 => "REG_NONE",
        1 => "REG_SZ",
        2 => "REG_EXPAND_SZ",
        3 => "REG_BINARY",
        4 => "REG_DWORD",
        5 => "REG_DWORD_BIG_ENDIAN",
        6 => "REG_LINK",
        7 => "REG_MULTI_SZ",
        8 => "REG_RESOURCE_LIST",
        9 => "REG_FULL_RESOURCE_DESCRIPTOR",
        10 => "REG_RESOURCE_REQUIREMENTS_LIST",
        11 => "REG_QWORD",
        _ => "UNKNOWN",
    }
}
pub(crate) struct Output<W, E> {
    stdout: W,
    stderr: E,
    last_key: Option<(crate::registry::View, std::ffi::OsString)>,
}
impl<W: Write, E: Write> Output<W, E> {
    pub(crate) fn new(stdout: W, stderr: E) -> Self {
        Self {
            stdout,
            stderr,
            last_key: None,
        }
    }
    fn heading(&mut self, target: &Target, prefix: &str) -> io::Result<()> {
        writeln!(
            self.stdout,
            "{prefix}[{}] {}{}",
            target.view.label(),
            path(&target.key),
            if target.key.encode_wide().take(5).eq("HKCR\\".encode_utf16()) {
                " (merged view)"
            } else {
                ""
            }
        )
    }
}
impl<W: Write, E: Write> Sink for Output<W, E> {
    fn key(&mut self, target: &Target) -> io::Result<()> {
        self.heading(target, "KEY ")?;
        self.stdout.flush()
    }
    fn value(&mut self, target: &Target, value: Option<&RawValue>) -> io::Result<()> {
        if self
            .last_key
            .as_ref()
            .is_none_or(|(view, key)| *view != target.view || key != &target.key)
        {
            if self.last_key.is_some() {
                writeln!(self.stdout)?;
            }
            self.heading(target, "")?;
            self.last_key = Some((target.view, target.key.clone()));
        }
        let value_name = target.name.as_ref().expect("value target");
        let value_name = if value_name.is_empty() {
            "\"\" (default)".into()
        } else {
            name(value_name, true)
        };
        match value {
            Some(value) => {
                let (preview, truncated) = preview(value);
                writeln!(
                    self.stdout,
                    "  VALUE {value_name}  {} ({})  {preview}{} ({} bytes)",
                    type_name(value.kind),
                    value.kind,
                    if truncated {
                        " [preview truncated]"
                    } else {
                        ""
                    },
                    value.bytes.len()
                )?;
            }
            None => writeln!(self.stdout, "  UNSET {value_name}  Default value not set")?,
        }
        self.stdout.flush()
    }
    fn diagnostic(
        &mut self,
        target: &Target,
        operation: &str,
        error: &io::Error,
    ) -> io::Result<()> {
        let value = target
            .name
            .as_ref()
            .map(|n| format!(" value {}", name(n, true)))
            .unwrap_or_default();
        writeln!(
            self.stderr,
            "regqry: [{}] {}{value}: {operation}: {}",
            target.view.label(),
            path(&target.key),
            name(OsStr::new(&crate::registry::error_text(error)), false)
        )?;
        self.stderr.flush()
    }
    fn finish(&mut self, summary: &Summary) -> io::Result<()> {
        let flush = self.stdout.flush();
        if let Err(error) = &flush {
            writeln!(
                self.stderr,
                "regqry: cannot flush stdout: {}",
                crate::registry::error_text(error)
            )?;
        }
        if summary.cancelled {
            writeln!(self.stderr, "regqry: search canceled")?;
        } else if summary.incomplete {
            writeln!(
                self.stderr,
                "regqry: search incomplete ({} error{})",
                summary.errors,
                if summary.errors == 1 { "" } else { "s" }
            )?;
        }
        self.stderr.flush()?;
        flush
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::windows::ffi::OsStringExt;
    #[test]
    fn previews_preserve_escape_units_and_mark_limits() {
        let (text, truncated) = preview_text([&"\n".repeat(80)], false);
        assert!(truncated);
        assert!(text.chars().count() <= 120);
        assert!(text.ends_with("\\n\""));
        assert_eq!(
            preview_text(std::iter::empty::<&str>(), true),
            ("[]".into(), false)
        );
        assert!(raw_preview(&[0; 33]).1);
        assert_eq!(
            name(&std::ffi::OsString::from_wide(&[0xD800, 10]), true),
            "\"\\u16{D800}\\n\""
        );
    }
    #[test]
    fn grouped_output_matches_the_agreed_default_and_unset_layout() {
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();
        let mut output = Output::new(&mut stdout, &mut stderr);
        let target = Target {
            view: crate::registry::View::V64,
            key: "HKCU\\Software\\Acme".into(),
            name: Some("".into()),
        };
        output
            .value(&target, Some(&RawValue::new("".into(), 1, vec![0, 0])))
            .unwrap();
        let literal = Target {
            name: Some("(Default)".into()),
            ..target.clone()
        };
        output
            .value(
                &literal,
                Some(&RawValue::new("(Default)".into(), 4, vec![1, 0, 0, 0])),
            )
            .unwrap();
        let missing = Target {
            key: "HKCU\\Software\\Unset".into(),
            ..target
        };
        output.value(&missing, None).unwrap();
        output.finish(&Summary::default()).unwrap();
        assert_eq!(
            String::from_utf8(stdout).unwrap(),
            "[64] HKCU\\Software\\Acme\n  VALUE \"\" (default)  REG_SZ (1)  \"\" (2 bytes)\n  VALUE \"(Default)\"  REG_DWORD (4)  1 (0x00000001) (4 bytes)\n\n[64] HKCU\\Software\\Unset\n  UNSET \"\" (default)  Default value not set\n"
        );
        assert!(stderr.is_empty());
        assert_eq!(
            path(OsStr::new("HKCU\\Line\nBreak")),
            "\"HKCU\\\\Line\\nBreak\""
        );
    }
}

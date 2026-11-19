use std::{
    cmp::Ordering,
    ffi::{OsStr, OsString},
    io,
    os::windows::ffi::{OsStrExt, OsStringExt},
    sync::atomic::{AtomicBool, Ordering as AtomicOrdering},
};
use windows_sys::Win32::{
    Foundation::{ERROR_MORE_DATA, ERROR_NO_MORE_ITEMS, ERROR_SUCCESS, FILETIME},
    Globalization::CompareStringOrdinal,
    System::Registry::{
        self, KEY_ENUMERATE_SUB_KEYS, KEY_QUERY_VALUE, KEY_WOW64_32KEY, KEY_WOW64_64KEY,
        REG_OPTION_OPEN_LINK,
    },
};
use winreg::RegKey;

#[cfg(test)]
mod tests;

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub(crate) enum View {
    V32,
    V64,
}
impl View {
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::V32 => "32",
            Self::V64 => "64",
        }
    }
    fn flag(self) -> u32 {
        match self {
            Self::V32 => KEY_WOW64_32KEY,
            Self::V64 => KEY_WOW64_64KEY,
        }
    }
}
pub(crate) fn available_views() -> io::Result<Vec<View>> {
    use windows_sys::Win32::System::{
        SystemInformation::{
            IMAGE_FILE_MACHINE_AMD64, IMAGE_FILE_MACHINE_ARM64, IMAGE_FILE_MACHINE_I386,
        },
        Threading::{GetCurrentProcess, IsWow64Process2},
    };
    let mut process_machine = 0;
    let mut native_machine = 0;
    // SAFETY: the current-process pseudo-handle is valid and requires no closing;
    // both output pointers refer to initialized, writable machine-code variables.
    if unsafe {
        IsWow64Process2(
            GetCurrentProcess(),
            &mut process_machine,
            &mut native_machine,
        )
    } == 0
    {
        return Err(io::Error::last_os_error());
    }
    match native_machine {
        IMAGE_FILE_MACHINE_AMD64 | IMAGE_FILE_MACHINE_ARM64 => Ok(vec![View::V32, View::V64]),
        IMAGE_FILE_MACHINE_I386 => Ok(vec![View::V32]),
        machine => Err(io::Error::other(format!(
            "unsupported native Windows machine type 0x{machine:04X}"
        ))),
    }
}

#[derive(Clone, Debug)]
pub(crate) struct Root {
    pub(crate) hive: &'static str,
    pub(crate) path: OsString,
}
impl Root {
    pub(crate) fn validated(value: &OsStr) -> Self {
        let units: Vec<_> = value.encode_wide().collect();
        let end = units.iter().position(|c| *c == 92).unwrap_or(units.len());
        let name = String::from_utf16(&units[..end])
            .expect("validated hive")
            .to_ascii_uppercase();
        let hive = match name.as_str() {
            "HKCU" | "HKEY_CURRENT_USER" => "HKCU",
            "HKLM" | "HKEY_LOCAL_MACHINE" => "HKLM",
            "HKCR" | "HKEY_CLASSES_ROOT" => "HKCR",
            "HKU" | "HKEY_USERS" => "HKU",
            "HKCC" | "HKEY_CURRENT_CONFIG" => "HKCC",
            _ => unreachable!("validated hive"),
        };
        let mut path = units.get(end + 1..).unwrap_or_default();
        if path.last() == Some(&92) {
            path = &path[..path.len() - 1];
        }
        Self {
            hive,
            path: OsString::from_wide(path),
        }
    }
    pub(crate) fn full_path(&self) -> io::Result<OsString> {
        join(OsStr::new(self.hive), &self.path)
    }
}

pub(crate) fn join(parent: &OsStr, name: &OsStr) -> io::Result<OsString> {
    let mut path = OsString::new();
    path.try_reserve(
        parent
            .len()
            .checked_add(name.len())
            .and_then(|n| n.checked_add(1))
            .ok_or_else(|| io::Error::other("path capacity overflow"))?,
    )
    .map_err(io::Error::other)?;
    path.push(parent);
    if !parent.is_empty() && !name.is_empty() {
        path.push("\\");
    }
    path.push(name);
    Ok(path)
}

pub(crate) fn ordinal(a: &OsStr, b: &OsStr) -> io::Result<Ordering> {
    let a: Vec<_> = a.encode_wide().collect();
    let b: Vec<_> = b.encode_wide().collect();
    ordinal_units(&a, &b)
}
pub(crate) fn error_text(error: &io::Error) -> String {
    use windows_sys::Win32::System::Diagnostics::Debug::{
        FORMAT_MESSAGE_FROM_SYSTEM, FORMAT_MESSAGE_IGNORE_INSERTS, FormatMessageW,
    };
    let Some(code) = error.raw_os_error() else {
        return error.to_string();
    };
    let mut buffer = [0u16; 1024];
    // SAFETY: buffer is writable for the supplied capacity; system messages ignore
    // inserts, and no variadic arguments or externally supplied format is used.
    let length = unsafe {
        FormatMessageW(
            FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
            std::ptr::null(),
            code as u32,
            0x0409,
            buffer.as_mut_ptr(),
            buffer.len() as u32,
            std::ptr::null(),
        )
    };
    let message = (length > 0 && (length as usize) < buffer.len())
        .then(|| String::from_utf16(&buffer[..length as usize]).ok())
        .flatten();
    format!(
        "Win32 {code}: {}",
        message
            .as_deref()
            .map(str::trim_end)
            .filter(|s| !s.is_empty())
            .unwrap_or("Windows operation failed; English system message unavailable")
    )
}
pub(crate) fn ordinal_path(a: &OsStr, b: &OsStr) -> io::Result<Ordering> {
    let a: Vec<_> = a.encode_wide().collect();
    let b: Vec<_> = b.encode_wide().collect();
    let mut a = a.split(|c| *c == 92);
    let mut b = b.split(|c| *c == 92);
    loop {
        match (a.next(), b.next()) {
            (Some(a), Some(b)) => {
                let order = ordinal_units(a, b)?;
                if order != Ordering::Equal {
                    return Ok(order);
                }
            }
            (None, None) => return Ok(Ordering::Equal),
            (None, Some(_)) => return Ok(Ordering::Less),
            (Some(_), None) => return Ok(Ordering::Greater),
        }
    }
}
fn ordinal_units(a: &[u16], b: &[u16]) -> io::Result<Ordering> {
    if a == b {
        return Ok(Ordering::Equal);
    }
    let valid_a = char::decode_utf16(a.iter().copied()).all(|c| c.is_ok());
    let valid_b = char::decode_utf16(b.iter().copied()).all(|c| c.is_ok());
    if !valid_a || !valid_b {
        if !valid_a && !valid_b {
            return Err(io::Error::other(
                "cannot reliably compare distinct malformed UTF-16 names",
            ));
        }
        return Ok(valid_a.cmp(&valid_b));
    }
    if a.is_empty() {
        return Ok(Ordering::Less);
    }
    if b.is_empty() {
        return Ok(Ordering::Greater);
    }
    let len_a = i32::try_from(a.len())
        .map_err(|_| io::Error::other("name exceeds ordinal comparison range"))?;
    let len_b = i32::try_from(b.len())
        .map_err(|_| io::Error::other("name exceeds ordinal comparison range"))?;
    // SAFETY: both buffers live throughout the call and lengths count initialized UTF-16 units.
    match unsafe { CompareStringOrdinal(a.as_ptr(), len_a, b.as_ptr(), len_b, 1) } {
        1 => Ok(Ordering::Less),
        2 => Ok(Ordering::Equal),
        3 => Ok(Ordering::Greater),
        _ => Err(io::Error::last_os_error()),
    }
}

pub(crate) struct Child {
    pub(crate) name: OsString,
    pub(crate) modified: u64,
}
pub(crate) fn confirmed_value_missing(error: &io::Error) -> bool {
    error.raw_os_error() == Some(windows_sys::Win32::Foundation::ERROR_FILE_NOT_FOUND as i32)
}
pub(crate) trait Source {
    type Key;
    fn open_root(&self, root: &Root, view: View) -> io::Result<Self::Key>;
    fn open_child(
        &self,
        key: &Self::Key,
        name: &OsStr,
        view: View,
        values: bool,
    ) -> io::Result<Self::Key>;
    fn child_at(&self, key: &Self::Key, index: u32) -> io::Result<Option<Child>>;
    fn value_at(&self, key: &Self::Key, index: u32) -> io::Result<Option<OsString>>;
    fn read(&self, key: &Self::Key, name: &OsStr) -> io::Result<crate::value::RawValue>;
}

pub(crate) struct WindowsSource<'a> {
    pub(crate) cancelled: &'a AtomicBool,
}
impl WindowsSource<'_> {
    fn check_cancel(&self) -> io::Result<()> {
        check_cancel(self.cancelled)
    }
}
fn check_cancel(cancelled: &AtomicBool) -> io::Result<()> {
    if cancelled.load(AtomicOrdering::Relaxed) {
        Err(io::Error::new(io::ErrorKind::Interrupted, "cancelled"))
    } else {
        Ok(())
    }
}
fn grow<T: Clone + Default>(buffer: &mut Vec<T>, required: usize) -> io::Result<()> {
    let next = buffer
        .len()
        .checked_mul(2)
        .and_then(|n| n.checked_add(1))
        .map(|n| n.max(required))
        .filter(|n| *n <= u32::MAX as usize)
        .ok_or_else(|| io::Error::other("registry buffer capacity overflow"))?;
    buffer
        .try_reserve_exact(next - buffer.len())
        .map_err(io::Error::other)?;
    buffer.resize(next, T::default());
    Ok(())
}
fn exhausted() -> io::Error {
    io::Error::other("Win32 234: registry buffer changed through eight retries")
}

enum BufferRead<T> {
    Done(T),
    More(usize),
}

// Share the retry/cancellation boundary across the three raw operations. Each
// attempt supplies the current initialized capacity; failed output is discarded.
fn buffered<T: Clone + Default, R>(
    cancelled: &AtomicBool,
    initial: usize,
    mut operation: impl FnMut(&mut [T]) -> io::Result<BufferRead<R>>,
) -> io::Result<(Vec<T>, R)> {
    check_cancel(cancelled)?;
    let mut buffer = Vec::new();
    grow(&mut buffer, initial)?;
    for attempt in 0..=8 {
        check_cancel(cancelled)?;
        match operation(&mut buffer)? {
            BufferRead::Done(value) => return Ok((buffer, value)),
            BufferRead::More(required) => {
                check_cancel(cancelled)?;
                if attempt == 8 {
                    return Err(exhausted());
                }
                grow(&mut buffer, required)?;
            }
        }
    }
    unreachable!()
}

fn enum_key(
    key: &RegKey,
    index: u32,
    name: &mut [u16],
) -> io::Result<BufferRead<Option<(usize, u64)>>> {
    let mut length = name.len() as u32;
    let mut modified = FILETIME {
        dwLowDateTime: 0,
        dwHighDateTime: 0,
    };
    // SAFETY: key owns a live handle, name is writable for length units, and optional outputs are null.
    let code = unsafe {
        Registry::RegEnumKeyExW(
            key.raw_handle(),
            index,
            name.as_mut_ptr(),
            &mut length,
            std::ptr::null(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            &mut modified,
        )
    };
    match code {
        ERROR_SUCCESS if (length as usize) < name.len() => Ok(BufferRead::Done(Some((
            length as usize,
            (u64::from(modified.dwHighDateTime) << 32) | u64::from(modified.dwLowDateTime),
        )))),
        ERROR_SUCCESS => Err(io::Error::other("invalid returned key name length")),
        ERROR_NO_MORE_ITEMS => Ok(BufferRead::Done(None)),
        // The name-length output is only specified on success. Grow independently
        // rather than treating a failed call's output as a capacity hint.
        ERROR_MORE_DATA => Ok(BufferRead::More(0)),
        code => Err(io::Error::from_raw_os_error(code as i32)),
    }
}

fn enum_value(key: &RegKey, index: u32, name: &mut [u16]) -> io::Result<BufferRead<Option<usize>>> {
    let mut length = name.len() as u32;
    // SAFETY: name is writable for length units; no data/type outputs are requested.
    let code = unsafe {
        Registry::RegEnumValueW(
            key.raw_handle(),
            index,
            name.as_mut_ptr(),
            &mut length,
            std::ptr::null(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
        )
    };
    match code {
        ERROR_SUCCESS if (length as usize) < name.len() => {
            Ok(BufferRead::Done(Some(length as usize)))
        }
        ERROR_SUCCESS => Err(io::Error::other("invalid returned value name length")),
        ERROR_NO_MORE_ITEMS => Ok(BufferRead::Done(None)),
        ERROR_MORE_DATA => Ok(BufferRead::More(0)),
        code => Err(io::Error::from_raw_os_error(code as i32)),
    }
}

fn query_value(
    key: &RegKey,
    name: &OsStr,
    bytes: &mut [u8],
) -> io::Result<BufferRead<(u32, usize)>> {
    let name: Vec<_> = name.encode_wide().chain(Some(0)).collect();
    let mut size = bytes.len() as u32;
    let mut kind = 0;
    // SAFETY: name is NUL-terminated, bytes is writable for size bytes, and key owns the handle.
    let code = unsafe {
        Registry::RegQueryValueExW(
            key.raw_handle(),
            name.as_ptr(),
            std::ptr::null(),
            &mut kind,
            bytes.as_mut_ptr(),
            &mut size,
        )
    };
    match code {
        ERROR_SUCCESS if size as usize <= bytes.len() => {
            Ok(BufferRead::Done((kind, size as usize)))
        }
        ERROR_SUCCESS => Err(io::Error::other("invalid returned value data length")),
        // These ordinary roots provide a documented required-byte count; the
        // special performance-data roots, whose count is undefined, are rejected.
        ERROR_MORE_DATA => Ok(BufferRead::More(size as usize)),
        code => Err(io::Error::from_raw_os_error(code as i32)),
    }
}

impl Source for WindowsSource<'_> {
    type Key = RegKey;
    fn open_root(&self, root: &Root, view: View) -> io::Result<RegKey> {
        self.check_cancel()?;
        let raw = match root.hive {
            "HKCU" => Registry::HKEY_CURRENT_USER,
            "HKLM" => Registry::HKEY_LOCAL_MACHINE,
            "HKCR" => Registry::HKEY_CLASSES_ROOT,
            "HKU" => Registry::HKEY_USERS,
            "HKCC" => Registry::HKEY_CURRENT_CONFIG,
            _ => unreachable!(),
        };
        RegKey::predef(raw).open_subkey_with_flags(&root.path, KEY_ENUMERATE_SUB_KEYS | view.flag())
    }
    fn open_child(
        &self,
        key: &RegKey,
        name: &OsStr,
        view: View,
        values: bool,
    ) -> io::Result<RegKey> {
        self.check_cancel()?;
        key.open_subkey_with_options_flags(
            name,
            REG_OPTION_OPEN_LINK,
            (if values {
                KEY_QUERY_VALUE
            } else {
                KEY_ENUMERATE_SUB_KEYS
            }) | view.flag(),
        )
    }
    fn child_at(&self, key: &RegKey, index: u32) -> io::Result<Option<Child>> {
        let (name, entry) = buffered(self.cancelled, 256, |buffer| enum_key(key, index, buffer))?;
        Ok(entry.map(|(length, modified)| Child {
            name: OsString::from_wide(&name[..length]),
            modified,
        }))
    }
    fn value_at(&self, key: &RegKey, index: u32) -> io::Result<Option<OsString>> {
        let (name, entry) = buffered(self.cancelled, 256, |buffer| enum_value(key, index, buffer))?;
        Ok(entry.map(|length| OsString::from_wide(&name[..length])))
    }
    fn read(&self, key: &RegKey, name: &OsStr) -> io::Result<crate::value::RawValue> {
        let (mut bytes, (kind, size)) =
            buffered(self.cancelled, 256, |buffer| query_value(key, name, buffer))?;
        bytes.truncate(size);
        Ok(crate::value::RawValue::new(name.to_owned(), kind, bytes))
    }
}

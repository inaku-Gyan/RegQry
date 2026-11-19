//! Helpers for the explicitly invoked disposable-VM harness, never product APIs.
use std::{ffi::OsStr, io, os::windows::ffi::OsStrExt, ptr};
use windows_sys::Win32::{
    Foundation::{CloseHandle, ERROR_SUCCESS, LocalFree},
    Security::{
        Authorization::{
            ConvertSidToStringSidW, ConvertStringSecurityDescriptorToSecurityDescriptorW,
        },
        GetSecurityDescriptorOwner, GetTokenInformation, OWNER_SECURITY_INFORMATION,
        SECURITY_ATTRIBUTES, TOKEN_ELEVATION, TOKEN_QUERY, TOKEN_USER, TokenElevation, TokenUser,
    },
    System::{
        Registry::*,
        Threading::{GetCurrentProcess, OpenProcessToken},
    },
};
use winreg::RegKey;

pub const MARKER: &str = "RegQryFixtureOwner";
pub const CONFIRM: &str = "disposable-vm-rollback-required";

pub fn wide(text: &OsStr) -> Vec<u16> {
    text.encode_wide().chain(Some(0)).collect()
}
fn check(code: u32) -> io::Result<()> {
    if code == ERROR_SUCCESS {
        Ok(())
    } else {
        Err(io::Error::from_raw_os_error(code as i32))
    }
}

// APIs below allocate LocalAlloc memory. Its lifetime includes all uses of returned SIDs/SDs.
struct Local(*mut std::ffi::c_void);
impl Drop for Local {
    fn drop(&mut self) {
        // SAFETY: this is a non-null allocation returned by a documented LocalAlloc API.
        unsafe {
            LocalFree(self.0);
        }
    }
}
fn sid_string(sid: *mut std::ffi::c_void) -> io::Result<String> {
    let mut text = ptr::null_mut();
    // SAFETY: callers supply a SID in a live system token/security descriptor; output is writable.
    if unsafe { ConvertSidToStringSidW(sid, &mut text) } == 0 {
        return Err(io::Error::last_os_error());
    }
    let _allocation = Local(text.cast());
    let mut len = 0;
    // SAFETY: the successful API returns a NUL-terminated UTF-16 SID allocation.
    unsafe {
        while *text.add(len) != 0 {
            len += 1;
        }
        String::from_utf16(std::slice::from_raw_parts(text, len)).map_err(io::Error::other)
    }
}
pub fn token() -> io::Result<(String, bool)> {
    let mut handle = ptr::null_mut();
    // SAFETY: the current-process pseudo-handle is valid and the output receives an owned token.
    if unsafe { OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut handle) } == 0 {
        return Err(io::Error::last_os_error());
    }
    let result = (|| {
        let mut elevation = TOKEN_ELEVATION { TokenIsElevated: 0 };
        let mut size = 0;
        // SAFETY: elevation is a suitably sized/aligned initialized TOKEN_ELEVATION output.
        if unsafe {
            GetTokenInformation(
                handle,
                TokenElevation,
                (&mut elevation as *mut TOKEN_ELEVATION).cast(),
                std::mem::size_of_val(&elevation) as u32,
                &mut size,
            )
        } == 0
        {
            return Err(io::Error::last_os_error());
        }
        // SAFETY: a null, zero-size output asks the system for the required buffer size.
        unsafe {
            GetTokenInformation(handle, TokenUser, ptr::null_mut(), 0, &mut size);
        }
        let mut buffer = vec![0usize; (size as usize).div_ceil(std::mem::size_of::<usize>())];
        // SAFETY: the word buffer is aligned for TOKEN_USER and has at least size writable bytes.
        if unsafe {
            GetTokenInformation(
                handle,
                TokenUser,
                buffer.as_mut_ptr().cast(),
                size,
                &mut size,
            )
        } == 0
        {
            return Err(io::Error::last_os_error());
        }
        // SAFETY: the successful call initialized a TOKEN_USER within this still-live aligned buffer.
        let user = unsafe { &*buffer.as_ptr().cast::<TOKEN_USER>() };
        Ok((sid_string(user.User.Sid)?, elevation.TokenIsElevated != 0))
    })();
    // SAFETY: OpenProcessToken succeeded; this closes exactly that owned handle.
    unsafe {
        CloseHandle(handle);
    }
    result
}

pub struct Context {
    pub id: String,
    pub nonce: Vec<u8>,
    pub sid: String,
}
impl Context {
    pub fn parse(get: impl Fn(&str) -> Option<String>, phase: &str) -> io::Result<Self> {
        let required = |name| {
            get(name).filter(|s| !s.is_empty()).ok_or_else(|| {
                io::Error::other(format!(
                    "missing {name}; use run-vm-tests.ps1 in a disposable VM"
                ))
            })
        };
        if required("REGQRY_VM_CONFIRM")? != CONFIRM || required("REGQRY_VM_PHASE")? != phase {
            return Err(io::Error::other(
                "disposable VM confirmation/phase mismatch",
            ));
        }
        let id = required("REGQRY_VM_ID")?;
        let nonce = required("REGQRY_VM_NONCE")?;
        let sid = required("REGQRY_VM_QUERY_SID")?;
        let rollback = required("REGQRY_VM_ROLLBACK")?;
        if id.len() != 32
            || !id.bytes().all(|c| c.is_ascii_hexdigit())
            || nonce.len() != 64
            || !nonce.bytes().all(|c| c.is_ascii_hexdigit())
            || !regex::Regex::new(r"^S-1-5-21-[0-9]+-[0-9]+-[0-9]+-[0-9]+$")
                .unwrap()
                .is_match(&sid)
            || rollback.trim().is_empty()
        {
            return Err(io::Error::other("invalid disposable VM identity"));
        }
        Ok(Self {
            id,
            nonce: hex::decode(nonce).map_err(io::Error::other)?,
            sid,
        })
    }
    pub fn require(phase: &str) -> Self {
        let context = Self::parse(|name| std::env::var(name).ok(), phase).unwrap();
        let (sid, elevated) = token().unwrap();
        if phase == "prepare" {
            assert!(elevated, "setup requires an elevated token");
        } else {
            assert!(!elevated, "queries require a non-elevated token");
            assert_eq!(sid, context.sid, "query user differs from prepared fixture");
        }
        println!(
            "VM_OPERATION_START phase={phase} id={} sid={sid} elevated={elevated}",
            context.id
        );
        context
    }
    pub fn base(&self) -> String {
        format!("RegQryAcceptance_{}", self.id)
    }
    pub fn machine(&self, view: u32) -> RegKey {
        let key = RegKey::predef(HKEY_LOCAL_MACHINE)
            .open_subkey_with_options_flags(
                format!("Software\\{}", self.base()),
                REG_OPTION_OPEN_LINK,
                KEY_QUERY_VALUE | view,
            )
            .unwrap();
        assert_marker(&key, &self.nonce);
        key
    }
}

/// Create one fresh component. An existing key is never populated or assigned a new ACL.
pub fn create(parent: &RegKey, name: &OsStr, view: u32, sddl: Option<&str>) -> io::Result<RegKey> {
    create_options(parent, name, view, sddl, REG_OPTION_NON_VOLATILE)
}
pub fn link(parent: &RegKey, name: &str, view: u32, sddl: &str, target: &str, context: &Context) {
    let owned_prefix = format!("\\Registry\\Machine\\Software\\{}\\", context.base());
    assert_eq!(
        view, KEY_WOW64_64KEY,
        "object-manager paths here identify the native fixture"
    );
    assert!(
        target.starts_with(&owned_prefix),
        "link must target this fixture namespace"
    );
    let key = create_options(
        parent,
        OsStr::new(name),
        view,
        Some(sddl),
        REG_OPTION_CREATE_LINK,
    )
    .unwrap();
    assert_admin_owner(&key);
    // MS-RRP 3.1.1.11 requires an object-manager path WITHOUT a terminating NUL.
    set(
        &key,
        OsStr::new("SymbolicLinkValue"),
        REG_LINK,
        &target
            .encode_utf16()
            .flat_map(u16::to_le_bytes)
            .collect::<Vec<_>>(),
    );
}
fn create_options(
    parent: &RegKey,
    name: &OsStr,
    view: u32,
    sddl: Option<&str>,
    options: u32,
) -> io::Result<RegKey> {
    let units = wide(name);
    if units.len() < 2 || units[..units.len() - 1].iter().any(|u| *u == 0 || *u == 92) {
        return Err(io::Error::other(
            "fixture creation requires one nonempty component",
        ));
    }
    let mut descriptor = ptr::null_mut();
    let allocation = if let Some(sddl) = sddl {
        let sddl = wide(OsStr::new(sddl));
        // SAFETY: input is NUL-terminated, revision 1 is SDDL_REVISION_1, outputs are writable.
        if unsafe {
            ConvertStringSecurityDescriptorToSecurityDescriptorW(
                sddl.as_ptr(),
                1,
                &mut descriptor,
                ptr::null_mut(),
            )
        } == 0
        {
            return Err(io::Error::last_os_error());
        }
        Some(Local(descriptor))
    } else {
        None
    };
    let security = SECURITY_ATTRIBUTES {
        nLength: std::mem::size_of::<SECURITY_ATTRIBUTES>() as u32,
        lpSecurityDescriptor: descriptor,
        bInheritHandle: 0,
    };
    let mut raw = ptr::null_mut();
    let mut disposition = 0;
    // SAFETY: parent is live, this is one NUL-terminated component, and optional SD lives through the call.
    check(unsafe {
        RegCreateKeyExW(
            parent.raw_handle(),
            units.as_ptr(),
            0,
            ptr::null(),
            options,
            KEY_ALL_ACCESS | view,
            if allocation.is_some() {
                &security
            } else {
                ptr::null()
            },
            &mut raw,
            &mut disposition,
        )
    })?;
    // winreg's wrapper closes real handles on Drop (only predefined pseudo-handles are exempt).
    let key = RegKey::predef(raw);
    if disposition != REG_CREATED_NEW_KEY {
        return Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            "fixture component already exists; untouched",
        ));
    }
    println!("FIXTURE_CREATED component={name:?} view={view:#x} disposition={disposition}");
    Ok(key)
}
pub fn set(key: &RegKey, name: &OsStr, kind: u32, data: &[u8]) {
    let name = wide(name);
    // SAFETY: callers use only a newly created fixture/private-hive handle; buffers live for the call.
    check(unsafe {
        RegSetValueExW(
            key.raw_handle(),
            name.as_ptr(),
            0,
            kind,
            data.as_ptr(),
            u32::try_from(data.len()).unwrap(),
        )
    })
    .unwrap();
}
pub fn text(key: &RegKey, name: &str, value: &str) {
    set(
        key,
        OsStr::new(name),
        REG_SZ,
        &value
            .encode_utf16()
            .chain(Some(0))
            .flat_map(u16::to_le_bytes)
            .collect::<Vec<_>>(),
    );
}
pub fn raw(key: &RegKey, name: &str) -> (u32, Vec<u8>) {
    let name = wide(OsStr::new(name));
    let mut size = 0;
    let mut kind = 0;
    // SAFETY: live handle and terminated name; null data requests the saved length.
    check(unsafe {
        RegQueryValueExW(
            key.raw_handle(),
            name.as_ptr(),
            ptr::null(),
            &mut kind,
            ptr::null_mut(),
            &mut size,
        )
    })
    .unwrap();
    let mut bytes = vec![0; size as usize];
    // SAFETY: buffer has the size requested by the previous call; these fixtures are quiescent.
    check(unsafe {
        RegQueryValueExW(
            key.raw_handle(),
            name.as_ptr(),
            ptr::null(),
            &mut kind,
            bytes.as_mut_ptr(),
            &mut size,
        )
    })
    .unwrap();
    bytes.truncate(size as usize);
    (kind, bytes)
}
pub fn mark(key: &RegKey, nonce: &[u8]) {
    set(key, OsStr::new(MARKER), REG_BINARY, nonce);
}
pub fn assert_marker(key: &RegKey, nonce: &[u8]) {
    assert_eq!(
        raw(key, MARKER),
        (REG_BINARY, nonce.to_vec()),
        "fixture ownership marker differs"
    );
}
pub fn assert_admin_owner(key: &RegKey) {
    assert_eq!(
        owner(key),
        "S-1-5-32-544",
        "fixture must be owned by Administrators, not the query user"
    );
}
pub fn owner(key: &RegKey) -> String {
    let mut size = 0;
    // SAFETY: null output queries the required descriptor length.
    unsafe {
        RegGetKeySecurity(
            key.raw_handle(),
            OWNER_SECURITY_INFORMATION,
            ptr::null_mut(),
            &mut size,
        );
    }
    let mut buffer = vec![0usize; (size as usize).div_ceil(std::mem::size_of::<usize>())];
    // SAFETY: aligned buffer has at least size writable bytes; successful result stays live below.
    check(unsafe {
        RegGetKeySecurity(
            key.raw_handle(),
            OWNER_SECURITY_INFORMATION,
            buffer.as_mut_ptr().cast(),
            &mut size,
        )
    })
    .unwrap();
    let mut owner = ptr::null_mut();
    let mut defaulted = 0;
    // SAFETY: descriptor was returned by the system and remains live through SID conversion.
    assert_ne!(
        unsafe {
            GetSecurityDescriptorOwner(buffer.as_mut_ptr().cast(), &mut owner, &mut defaulted)
        },
        0
    );
    sid_string(owner).unwrap()
}

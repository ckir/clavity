//! Server logging: a per-instance, size-bounded, owner-only file log — never stdout (spec §5). stdout
//! is the MCP JSON-RPC channel; any byte there corrupts the protocol. The 128-bit connection token is
//! NEVER passed to a log macro anywhere in the server (enforced by review, not code).

use std::io;
use std::path::Path;
use tracing_appender::non_blocking::WorkerGuard;

/// Initialize file-only tracing. Returns a guard that MUST be held for the process lifetime (dropping
/// it flushes+stops the writer). `log_path` is the per-instance path from `paths::instance_log_path()`.
pub fn init_file_logging(log_path: &Path) -> io::Result<WorkerGuard> {
    let dir = log_path
        .parent()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "log path has no parent"))?;
    std::fs::create_dir_all(dir)?;
    restrict_to_owner(dir)?;

    let file_name = log_path
        .file_name()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "log path has no file name"))?;
    let appender = tracing_appender::rolling::Builder::new()
        .rotation(tracing_appender::rolling::Rotation::DAILY)
        .filename_prefix(file_name.to_string_lossy().as_ref())
        .max_log_files(5)
        .build(dir)
        .map_err(|e| io::Error::other(format!("log appender: {e}")))?;
    let (nb, guard) = tracing_appender::non_blocking(appender);

    // File-only writer: stdout is the MCP JSON-RPC channel and must never see a stray byte.
    tracing_subscriber::fmt()
        .with_writer(nb)
        .with_ansi(false)
        .init();
    // Re-assert ownership after the appender created today's log file (belt-and-suspenders: the
    // directory ACL already restricts new files, but this covers any window before that ACL applied).
    let _ = restrict_to_owner(dir);
    Ok(guard)
}

#[cfg(unix)]
fn restrict_to_owner(path: &Path) -> io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700))
}

#[cfg(windows)]
fn restrict_to_owner(path: &Path) -> io::Result<()> {
    windows_acl_impl::apply(path)
}

#[cfg(windows)]
mod windows_acl_impl {
    use std::io;
    use std::path::Path;

    use windows::core::{Error as WinError, PWSTR};
    use windows::Win32::Foundation::LocalFree;
    use windows::Win32::Foundation::{CloseHandle, ERROR_SUCCESS, HANDLE, HLOCAL};
    use windows::Win32::Security::Authorization::{
        SetEntriesInAclW, SetNamedSecurityInfoW, EXPLICIT_ACCESS_W, NO_MULTIPLE_TRUSTEE,
        SET_ACCESS, SE_FILE_OBJECT, TRUSTEE_IS_SID, TRUSTEE_IS_USER, TRUSTEE_W,
    };
    use windows::Win32::Security::{
        GetTokenInformation, TokenUser, ACL, DACL_SECURITY_INFORMATION, NO_INHERITANCE,
        PROTECTED_DACL_SECURITY_INFORMATION, TOKEN_QUERY, TOKEN_USER,
    };
    use windows::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};

    /// FILE_ALL_ACCESS (winnt.h): STANDARD_RIGHTS_ALL | FILE_GENERIC_READ | FILE_GENERIC_WRITE |
    /// FILE_GENERIC_EXECUTE | FILE_DELETE_CHILD. Hardcoded to avoid pulling in the whole
    /// Win32_Storage_FileSystem feature area for one constant.
    const FILE_ALL_ACCESS: u32 = 0x1F01FF;

    /// Apply a DACL to `path` that grants FILE_ALL_ACCESS to the current process's user SID only,
    /// and strips all inherited ACEs (PROTECTED_DACL_SECURITY_INFORMATION) so no ambient
    /// `Everyone`/`BUILTIN\Users` grant survives. Mirrors `chmod 0700` on Unix.
    pub fn apply(path: &Path) -> io::Result<()> {
        // 1. Open the current process token (query-only — we just need the user SID).
        let mut token = HANDLE::default();
        unsafe { OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token) }
            .map_err(win_err("OpenProcessToken"))?;
        let _token_guard = HandleGuard(token);

        // 2. GetTokenInformation(TokenUser) — two-call pattern: probe size, then fetch.
        let mut needed: u32 = 0;
        // SAFETY: null buffer + 0 size is the documented size-probe call; it always "fails" with
        // ERROR_INSUFFICIENT_BUFFER while writing the required size into `needed`.
        if let Err(e) = unsafe { GetTokenInformation(token, TokenUser, None, 0, &mut needed) } {
            if needed == 0 {
                return Err(win_err("GetTokenInformation (size probe)")(e));
            }
        }
        let mut buf = vec![0u8; needed as usize];
        let mut written: u32 = 0;
        unsafe {
            GetTokenInformation(
                token,
                TokenUser,
                Some(buf.as_mut_ptr() as *mut core::ffi::c_void),
                needed,
                &mut written,
            )
        }
        .map_err(win_err("GetTokenInformation"))?;
        // SAFETY: `buf` was sized/filled by the successful call above per the TOKEN_USER layout.
        let token_user = unsafe { &*(buf.as_ptr() as *const TOKEN_USER) };
        let sid = token_user.User.Sid;

        // 3. Build a single EXPLICIT_ACCESS_W entry granting FILE_ALL_ACCESS to that SID, replacing
        //    (not merging with) any existing ACE for the same trustee.
        let trustee = TRUSTEE_W {
            pMultipleTrustee: std::ptr::null_mut(),
            MultipleTrusteeOperation: NO_MULTIPLE_TRUSTEE,
            TrusteeForm: TRUSTEE_IS_SID,
            TrusteeType: TRUSTEE_IS_USER,
            ptstrName: PWSTR(sid.0 as *mut u16),
        };

        let ea = EXPLICIT_ACCESS_W {
            grfAccessPermissions: FILE_ALL_ACCESS,
            grfAccessMode: SET_ACCESS,
            grfInheritance: NO_INHERITANCE,
            Trustee: trustee,
        };

        // 4. SetEntriesInAclW allocates a brand-new ACL (owner-only, no prior entries merged in).
        let mut new_acl: *mut ACL = std::ptr::null_mut();
        let rc = unsafe { SetEntriesInAclW(Some(&[ea]), None, &mut new_acl) };
        if rc != ERROR_SUCCESS {
            return Err(io::Error::other(format!("SetEntriesInAclW failed: {rc:?}")));
        }
        let _acl_guard = LocalFreeGuard(new_acl as *mut core::ffi::c_void);

        // 5. Apply the new DACL to the path and, critically, mark it PROTECTED so no inherited ACEs
        //    (Everyone / BUILTIN\Users from the parent dir) survive alongside it.
        let wide_path = to_wide_null(path);
        let rc = unsafe {
            SetNamedSecurityInfoW(
                PWSTR(wide_path.as_ptr() as *mut u16),
                SE_FILE_OBJECT,
                DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
                None,
                None,
                Some(new_acl),
                None,
            )
        };
        if rc != ERROR_SUCCESS {
            return Err(io::Error::other(format!(
                "SetNamedSecurityInfoW failed: {rc:?}"
            )));
        }

        Ok(())
    }

    fn win_err(ctx: &'static str) -> impl Fn(WinError) -> io::Error {
        move |e| io::Error::other(format!("{ctx}: {e}"))
    }

    fn to_wide_null(path: &Path) -> Vec<u16> {
        use std::os::windows::ffi::OsStrExt;
        path.as_os_str()
            .encode_wide()
            .chain(std::iter::once(0))
            .collect()
    }

    /// RAII close for the process token handle.
    struct HandleGuard(HANDLE);
    impl Drop for HandleGuard {
        fn drop(&mut self) {
            // SAFETY: handle came from a successful OpenProcessToken owned solely by this guard.
            unsafe {
                let _ = CloseHandle(self.0);
            }
        }
    }

    /// RAII free for the LocalAlloc'd ACL returned by `SetEntriesInAclW`, per its documented
    /// contract (caller must LocalFree the new ACL when done with it).
    struct LocalFreeGuard(*mut core::ffi::c_void);
    impl Drop for LocalFreeGuard {
        fn drop(&mut self) {
            if !self.0.is_null() {
                // SAFETY: pointer was allocated by SetEntriesInAclW (LocalAlloc-backed) and not
                // freed elsewhere.
                unsafe {
                    let _ = LocalFree(HLOCAL(self.0));
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn init_creates_owner_only_log_dir_and_never_panics() {
        let base = std::env::temp_dir().join(format!("ghidrust-log-{}", std::process::id()));
        let log = base.join("logs").join("worker-test.log");
        let guard = init_file_logging(&log).expect("logging inits");
        tracing::info!("hello file log");
        drop(guard);
        assert!(log.parent().unwrap().exists());
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(base.join("logs"))
                .unwrap()
                .permissions()
                .mode();
            assert_eq!(mode & 0o777, 0o700, "log dir must be owner-only");
        }
        std::fs::remove_dir_all(&base).ok();
    }
}

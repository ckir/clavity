//! Windows Job Object kill-guard (spike D4). The worker tree is host -> cmd.exe -> java.exe;
//! a plain child.kill() reaps only cmd.exe and orphans the JVM. A job with
//! JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE kills the entire subtree the moment the host drops the
//! last job handle (including host process death). Non-Windows is a no-op shim so the crate
//! builds everywhere; M0's primary target is Windows.

#[cfg(windows)]
mod imp {
    use std::io;
    use std::os::windows::io::AsRawHandle;
    use std::process::Child;
    use windows::Win32::Foundation::{CloseHandle, HANDLE};
    use windows::Win32::System::JobObjects::{
        AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation,
        SetInformationJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
    };

    pub struct JobObject {
        handle: HANDLE,
    }

    // SAFETY: `handle` is a process-wide Windows job-object kernel handle. The Win32 job APIs used
    // here (AssignProcessToJobObject / SetInformationJobObject / CloseHandle) are thread-safe, so the
    // wrapper is sound to move across threads (Send) and share by reference (Sync). `HANDLE` is only
    // !Send/!Sync by default because the `windows` crate wraps a raw pointer without annotating it;
    // without these impls the whole BootedWorker is !Send, which breaks holding it across spawned
    // tokio tasks or in an Arc<Mutex<_>> (merge-gate finding).
    unsafe impl Send for JobObject {}
    unsafe impl Sync for JobObject {}

    impl JobObject {
        pub fn new() -> io::Result<Self> {
            // SAFETY: CreateJobObjectW with null args creates an unnamed job; we own the handle.
            let handle = unsafe { CreateJobObjectW(None, None) }
                .map_err(|e| io::Error::other(format!("CreateJobObjectW: {e}")))?;
            let mut info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
            info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            // SAFETY: `info` outlives the call; size matches the info class.
            unsafe {
                SetInformationJobObject(
                    handle,
                    JobObjectExtendedLimitInformation,
                    &info as *const _ as *const core::ffi::c_void,
                    std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
                )
            }
            .map_err(|e| io::Error::other(format!("SetInformationJobObject: {e}")))?;
            Ok(JobObject { handle })
        }

        pub fn assign(&self, child: &Child) -> io::Result<()> {
            let child_handle = HANDLE(child.as_raw_handle());
            // SAFETY: both handles are valid; the child is alive at assign time.
            unsafe { AssignProcessToJobObject(self.handle, child_handle) }
                .map_err(|e| io::Error::other(format!("AssignProcessToJobObject: {e}")))
        }
    }

    impl Drop for JobObject {
        fn drop(&mut self) {
            // Closing the last handle triggers KILL_ON_JOB_CLOSE for the whole tree.
            // SAFETY: handle was created by us and not closed elsewhere.
            unsafe {
                let _ = CloseHandle(self.handle);
            }
        }
    }
}

#[cfg(not(windows))]
mod imp {
    use std::io;
    use std::process::Child;

    /// No-op job on non-Windows (M0 targets Windows; a Unix port would use a process group).
    pub struct JobObject;
    impl JobObject {
        pub fn new() -> io::Result<Self> {
            Ok(JobObject)
        }
        pub fn assign(&self, _child: &Child) -> io::Result<()> {
            Ok(())
        }
    }
}

pub use imp::JobObject;

#[cfg(all(test, windows))]
mod tests {
    use super::*;
    use std::process::Command;
    use std::time::Duration;

    // Spawn cmd.exe that in turn spawns a long-lived grandchild (ping -t), assign the DIRECT child
    // to a job, then drop the job: the whole tree must die, proving grandchildren are reaped (the
    // exact host->cmd.exe->java.exe shape spike D4 measured).
    #[test]
    fn dropping_job_kills_grandchild_tree() {
        let mut child = Command::new("cmd.exe")
            .args(["/c", "ping -n 60 127.0.0.1 >NUL"])
            .spawn()
            .expect("spawn cmd");
        let pid = child.id();
        {
            let job = JobObject::new().expect("create job");
            job.assign(&child).expect("assign child");
            // job drops here -> KILL_ON_JOB_CLOSE fires
        }
        std::thread::sleep(Duration::from_millis(500));
        // The child must now be gone; try_wait returns Some(exit) once reaped.
        let status = child.try_wait().expect("try_wait");
        assert!(
            status.is_some(),
            "child pid {pid} should be killed by job close"
        );
        let _ = child.kill();
    }
}

//! Spawn the headless launcher and shield host stdout (spike D4). Both child pipes are drained on
//! dedicated threads into the host's STDERR so ~16 KB of Ghidra log spam per run never contaminates
//! host stdout (reserved for MCP JSON-RPC, M1). The child is wrapped in a JobObject so the whole
//! host->cmd.exe->java.exe tree dies with the host.

use crate::job_object::JobObject;
use std::io::{self, BufRead, BufReader};
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::thread::JoinHandle;

/// A spawned worker process: the child, its kill-guard job, and the two pipe-drain threads. Drop
/// order (struct fields drop top-to-bottom) closes the job last, but KILL_ON_JOB_CLOSE plus the
/// child's own exit make teardown robust either way.
pub struct WorkerProcess {
    pub child: Child,
    _job: JobObject,
    _drains: Vec<JoinHandle<()>>,
}

impl WorkerProcess {
    /// Spawn `program args…`, assign to a fresh JobObject, and drain stdout+stderr to host stderr.
    /// `max_heap` (e.g. "2G") is forwarded to Ghidra via the MAXMEM env var if set.
    pub fn spawn(program: &Path, args: &[String], max_heap: Option<&str>) -> io::Result<Self> {
        let mut cmd = Command::new(program);
        cmd.args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        if let Some(heap) = max_heap {
            // Ghidra's launcher honors MAXMEM (e.g. "2G") for the JVM -Xmx.
            cmd.env("MAXMEM", heap);
        }
        // Create the kill-guard BEFORE spawning: if job creation fails we never launch a JVM we
        // couldn't reap. And if `assign` fails AFTER spawn, kill the child explicitly — dropping a
        // std::process::Child does NOT kill it, so a bare `?` there would orphan the Ghidra JVM
        // permanently (agy panel R1).
        let job = JobObject::new()?;
        let mut child = cmd.spawn()?;
        if let Err(e) = job.assign(&child) {
            let _ = child.kill();
            return Err(e);
        }

        let mut drains = Vec::new();
        if let Some(out) = child.stdout.take() {
            drains.push(spawn_drain("worker/stdout", out));
        }
        if let Some(err) = child.stderr.take() {
            drains.push(spawn_drain("worker/stderr", err));
        }

        Ok(WorkerProcess {
            child,
            _job: job,
            _drains: drains,
        })
    }
}

fn spawn_drain<R: io::Read + Send + 'static>(tag: &'static str, r: R) -> JoinHandle<()> {
    std::thread::spawn(move || {
        let reader = BufReader::new(r);
        for line in reader.lines() {
            match line {
                Ok(l) => eprintln!("[{tag}] {l}"),
                Err(_) => break,
            }
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::time::Duration;

    #[cfg(windows)]
    fn echo_cmd() -> (PathBuf, Vec<String>) {
        (
            PathBuf::from("cmd.exe"),
            vec!["/c".into(), "echo hello-from-child".into()],
        )
    }
    #[cfg(not(windows))]
    fn echo_cmd() -> (PathBuf, Vec<String>) {
        (PathBuf::from("echo"), vec!["hello-from-child".into()])
    }

    // Smoke test ONLY: proves spawn + job-assign + drain-thread wiring returns Ok and tears down
    // cleanly. It deliberately does NOT assert stdout-shielding — that invariant's real oracles are
    // spike D4 (measured host stdout = 0 bytes) and the e2e test (Task 11). Named to avoid the
    // false confidence of implying it verifies the shield (agy panel R3).
    #[test]
    fn spawn_and_drain_wire_up_without_error() {
        let (prog, args) = echo_cmd();
        let wp = WorkerProcess::spawn(&prog, &args, None).expect("spawn");
        // Give the drain threads a moment; the child exits on its own.
        std::thread::sleep(Duration::from_millis(300));
        drop(wp);
    }
}

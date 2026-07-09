//! Shared fixture helpers for the gated in-process integration tests (crucible.rs, respawn.rs).
//! All live-worker tests are gated on GHIDRUST_E2E=1 + the fixture env vars.
// Each test binary includes this module via `mod common;` but uses a DIFFERENT subset of the helpers
// (e.g. the write-suite helpers are used only by writenav.rs), so per-binary dead_code is expected here.
#![allow(dead_code)]

use ghidra_ipc::error::{ErrorCode, ErrorEnvelope};
use ghidrust::config::RawConfig;
use ghidrust::paths::versioned_script_dir;
use ghidrust::state::ServerState;
use std::sync::Arc;

pub fn env(n: &str) -> Option<String> {
    std::env::var(n).ok().filter(|s| !s.is_empty())
}

pub fn enabled() -> bool {
    env("GHIDRUST_E2E").as_deref() == Some("1")
}

/// Build ServerState from the fixture env (same vars as boot_e2e.rs). `bootstrap_program` is the BARE
/// leaf of the fixture program VFS path; `bootstrap_program_path` is the full `/`-path.
pub fn fixture_state() -> Arc<ServerState> {
    let program =
        env("GHIDRUST_FIXTURE_PROGRAM").expect("GHIDRUST_FIXTURE_PROGRAM (VFS path e.g. /add.exe)");
    let bare = program.rsplit('/').next().unwrap().to_string();
    let raw = RawConfig {
        ghidra_install_dir: env("GHIDRA_INSTALL_DIR"),
        project_dir: env("GHIDRUST_FIXTURE_PROJECT_DIR"),
        project_name: env("GHIDRUST_FIXTURE_PROJECT_NAME"),
        bootstrap_program: Some(bare),
        bootstrap_program_path: Some(program),
        max_heap: None,
    };
    let cfg = raw.resolve().expect("fixture config resolves");
    Arc::new(ServerState::new(cfg, versioned_script_dir()))
}

/// Poll a call until the background warmup boot is Ready (WORKER_WARMING → retry). Bounds the wait so a
/// stuck boot fails the test instead of hanging.
pub async fn call_when_warm(
    state: &Arc<ServerState>,
    tool: &str,
    sel: &str,
    method: &str,
    params: serde_json::Value,
) -> Result<serde_json::Value, ErrorEnvelope> {
    for _ in 0..60 {
        match ghidrust::execute::call_worker(state, tool, sel, method, params.clone()).await {
            Err(e) if e.error.code == ErrorCode::WorkerWarming => {
                tokio::time::sleep(std::time::Duration::from_secs(1)).await;
            }
            other => return other.map(|(v, _canon)| v),
        }
    }
    panic!("worker never warmed within 60s");
}

/// RAII guard: deletes the ephemeral fixture copy on drop so the write suite doesn't leak ~5 project
/// copies per run (agy plan-review R3/R4). Use `.path` to boot/inspect the copy.
///
/// DROP-ORDER IS LOAD-BEARING (agy R4): the guard must drop AFTER the `ServerState` that owns the JVM,
/// or `remove_dir_all` races a live Ghidra handle and Windows denies it. `fixture_state_ephemeral`
/// returns `(guard, state)` and every test binds `let (dir, state) = …` — Rust drops locals in reverse
/// declaration order, so `state` (JVM killed via JobObject) drops BEFORE `dir` (cleanup). Even so the
/// JobObject kill is async, so `drop` spin-retries to absorb the few-ms handle-release lag on Windows.
pub struct EphemeralFixture {
    pub path: std::path::PathBuf,
}
impl Drop for EphemeralFixture {
    fn drop(&mut self) {
        // Windows keeps the Ghidra .lock / program-DB handles open for a few ms after the JobObject kill
        // and denies deletion (ERROR_SHARING_VIOLATION). Spin-retry up to ~2s so cleanup actually happens
        // instead of silently orphaning the copy (a plain best-effort `.ok()` leaves the R3 leak unfixed).
        for _ in 0..40 {
            if !self.path.exists() || std::fs::remove_dir_all(&self.path).is_ok() {
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(50)); // sync Drop context — std sleep, not tokio
        }
    }
}

/// Copy the fixture project dir to a fresh temp dir and return `(guard, state)` — guard FIRST so it drops
/// LAST (see the drop-order note above). Write e2e MUST use this (spec §11) so it never mutates the shared
/// read-suite fixture. Booting a SECOND state against the SAME `guard.path` (drop the first state first)
/// is the hard-restart durability oracle (§11).
pub fn fixture_state_ephemeral() -> (EphemeralFixture, Arc<ServerState>) {
    use std::sync::atomic::{AtomicUsize, Ordering};
    static SEQ: AtomicUsize = AtomicUsize::new(0); // unique even if two tests share a PID (non-nextest runner)
    let src = env("GHIDRUST_FIXTURE_PROJECT_DIR").expect("GHIDRUST_FIXTURE_PROJECT_DIR");
    let uniq = format!(
        "{}-{}",
        std::process::id(),
        SEQ.fetch_add(1, Ordering::Relaxed)
    );
    let dst = std::env::temp_dir().join(format!("ghidrust-w-{uniq}"));
    copy_dir_all(std::path::Path::new(&src), &dst).expect("copy fixture project");
    let state = fixture_state_at(&dst);
    (EphemeralFixture { path: dst }, state)
}

/// Like fixture_state() but with GHIDRUST_FIXTURE_PROJECT_DIR overridden to `dir` (boots against an
/// already-mutated ephemeral copy — the second leg of the hard-restart oracle). CAPTURE + RESTORE the
/// original value (agy plan-review): set_var is process-global, so leaving it mutated would make the NEXT
/// fixture_state_ephemeral() copy this temp dir instead of the pristine source, cascading corruption
/// under -j1.
pub fn fixture_state_at(dir: &std::path::Path) -> Arc<ServerState> {
    let orig = std::env::var("GHIDRUST_FIXTURE_PROJECT_DIR").expect("GHIDRUST_FIXTURE_PROJECT_DIR");
    std::env::set_var("GHIDRUST_FIXTURE_PROJECT_DIR", dir);
    let state = fixture_state(); // reads the env var during boot
    std::env::set_var("GHIDRUST_FIXTURE_PROJECT_DIR", orig); // restore before returning
    state
}

fn copy_dir_all(src: &std::path::Path, dst: &std::path::Path) -> std::io::Result<()> {
    std::fs::create_dir_all(dst)?;
    for entry in std::fs::read_dir(src)? {
        let e = entry?;
        let p = e.path();
        let d = dst.join(e.file_name());
        if p.file_name()
            .is_some_and(|n| n.to_string_lossy().contains(".lock"))
        {
            continue;
        } // never copy a lock
        if p.is_dir() {
            copy_dir_all(&p, &d)?;
        } else {
            std::fs::copy(&p, &d)?;
        }
    }
    Ok(())
}

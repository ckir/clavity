//! Server state: the single worker held behind an async mutex, its active attachment + address
//! canonicalizer, the poison set, and a permit semaphore. Lazy single-flight boot (spec §5); strict
//! inner<outer timeouts (spec §4.7); transparent crash respawn (spec §4.3) lives in `execute.rs`.

use crate::config::ServerConfig;
use crate::poison::{PoisonSet, DEFAULT_POISON_CAPACITY};
use ghidra_ipc::address::AddressCanonicalizer;
use ghidra_ipc::error::{ErrorCode, ErrorEnvelope};
use ghidra_worker_ctl::boot::BootedWorker;
use std::path::PathBuf;
use std::sync::Mutex as StdMutex;
use tokio::sync::{Mutex, Semaphore};

/// The worker script version this binary requires; must equal `GhidrustWorker.java`'s
/// `WORKER_SCRIPT_VERSION` (bumped to "0.7.0" for M2d: the `set_local` write method + the structured
/// `locals[]` array on `inspect_function`). Bump BOTH in lockstep whenever the worker's method surface
/// changes. Exact-match (not semver-range) is sufficient because the worker is embedded + hash-extracted,
/// so host and worker are always the same build in practice (spec §5).
pub const EXPECTED_WORKER_VERSION: &str = "0.7.0";

/// Max concurrent in-flight+queued tool calls before `SERVER_BUSY` (spec §5 / §9.4).
pub const SERVER_PERMITS: usize = 4;

/// A booted, attached worker plus the derived per-program address canonicalizer.
pub struct WorkerHolder {
    pub booted: BootedWorker,
    /// The last program that a request SUCCESSFULLY attached (spec §4.3 state-commit ordering). On
    /// boot this is the bootstrap program (learned from `worker_info`).
    pub active_program_path: Option<String>,
    /// Canonicalizer for the active program's address geometry (rebuilt on each successful attach).
    pub canon: AddressCanonicalizer,
}

// There is exactly ONE WorkerSlot instance (behind `ServerState.worker: Mutex<WorkerSlot>`), so the
// large-variant padding is ~360 bytes ONCE. Boxing `Ready` (clippy's suggestion) would add a heap
// indirection on the hot path (every RPC touches `Ready(h)`) for no real memory win — allow instead.
#[allow(clippy::large_enum_variant)]
pub enum WorkerSlot {
    Empty,
    Booting,
    Ready(WorkerHolder),
    /// A deterministic, non-retryable failure (version-skew). Every tool returns this without a reboot.
    Fatal(ErrorEnvelope),
}

pub struct ServerState {
    pub cfg: ServerConfig,
    pub script_dir: PathBuf,
    pub worker: Mutex<WorkerSlot>,
    pub poison: StdMutex<PoisonSet>,
    pub sem: Semaphore,
    /// Signalled by `spawn_boot` when a background boot finishes (success OR failure), so a caller
    /// waiting out `warming_deadline` (execute.rs §4.7) wakes promptly instead of polling blind.
    pub boot_done: tokio::sync::Notify,
    /// Count of worker boots attempted (test-only single-flight assertion; spec §8).
    pub boot_count: std::sync::atomic::AtomicUsize,
}

impl ServerState {
    pub fn new(cfg: ServerConfig, script_dir: PathBuf) -> Self {
        Self {
            cfg,
            script_dir,
            worker: Mutex::new(WorkerSlot::Empty),
            poison: StdMutex::new(PoisonSet::new(DEFAULT_POISON_CAPACITY)),
            sem: Semaphore::new(SERVER_PERMITS),
            boot_done: tokio::sync::Notify::new(),
            boot_count: std::sync::atomic::AtomicUsize::new(0),
        }
    }

    /// Number of worker boots attempted (test-only single-flight assertion; spec §8).
    pub fn boot_count(&self) -> usize {
        self.boot_count.load(std::sync::atomic::Ordering::SeqCst)
    }

    /// Boot a worker, verify version, call worker_info to learn the bootstrap program + geometry, and
    /// build the canonicalizer.
    pub(crate) async fn boot_and_probe(&self) -> Result<WorkerHolder, ErrorEnvelope> {
        self.boot_count
            .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        use ghidra_ipc::protocol::AttachResult;
        // Extract the worker script into the per-version dir (idempotent by hash).
        crate::worker_asset::extract_worker(&self.script_dir)
            .map_err(|e| boot_env(format!("extract worker script: {e}")))?;
        let wcfg = self.cfg.worker_config(self.script_dir.clone());
        let mut booted = ghidra_worker_ctl::boot::boot_worker(&wcfg)
            .await
            .map_err(|e| boot_env(format!("boot worker: {e}")))?;
        // Version-skew is deterministic → the caller makes it Fatal.
        check_worker_version(&booted.announce.worker_script_version)?;
        // Learn the bootstrap program + geometry (spec §6/§7), with a deadline so a worker that
        // handshakes then hangs before answering worker_info doesn't wedge the slot forever (R4 seat-M).
        let info = tokio::time::timeout(
            self.cfg.rpc_deadline,
            booted
                .conn
                .request(&mk("worker_info", serde_json::json!({}))),
        )
        .await
        .map_err(|_| {
            boot_env("worker booted but did not answer worker_info before the deadline".to_string())
        })?
        .map_err(|e| boot_env(format!("worker_info: {e}")))?;
        let result = expect_success(info)?;
        let attach: AttachResult = serde_json::from_value(result)
            .map_err(|e| boot_env(format!("worker_info shape: {e}")))?;
        let canon = AddressCanonicalizer::new(attach.default_space.clone(), attach.pointer_size);
        Ok(WorkerHolder {
            booted,
            active_program_path: attach.attached,
            canon,
        })
    }
}

impl ServerState {
    /// Spawn the single-flight background boot. Caller must have set the slot to `Booting` while
    /// holding the lock (so exactly one boot runs). On completion the task stores Ready/Fatal, or
    /// resets to Empty on a transient failure (retryable).
    pub fn spawn_boot(self: std::sync::Arc<Self>) {
        tokio::spawn(async move {
            let outcome = self.boot_and_probe().await;
            {
                let mut slot = self.worker.lock().await;
                if matches!(&*slot, WorkerSlot::Booting) {
                    match outcome {
                        Ok(holder) => *slot = WorkerSlot::Ready(holder),
                        Err(e) if e.error.code == ErrorCode::WorkerIncompatible => {
                            *slot = WorkerSlot::Fatal(e)
                        }
                        Err(_transient) => *slot = WorkerSlot::Empty,
                    }
                }
            }
            self.boot_done.notify_waiters();
        });
    }

    /// Start the single-flight warmup boot: if the slot is `Empty`, mark it `Booting` under the lock and
    /// spawn the background boot; a slot already `Booting`/`Ready`/`Fatal` is left alone so exactly one
    /// boot ever runs. This is the ONLY correct way to kick a warmup — calling `spawn_boot` directly on an
    /// `Empty` slot leaves it `Empty` (spawn_boot publishes only when it finds `Booting`), so a racing
    /// `wait_until_ready` would launch a SECOND concurrent boot (two JVMs → project `LockException`).
    pub async fn start_warmup(self: &std::sync::Arc<Self>) {
        let mut slot = self.worker.lock().await;
        if matches!(&*slot, WorkerSlot::Empty) {
            *slot = WorkerSlot::Booting;
            drop(slot);
            std::sync::Arc::clone(self).spawn_boot();
        }
    }
}

/// Pure: decide whether an announced worker version is compatible. Skew → a sticky `WORKER_INCOMPATIBLE`
/// envelope (spec §5).
pub fn check_worker_version(announced: &str) -> Result<(), ErrorEnvelope> {
    if announced == EXPECTED_WORKER_VERSION {
        Ok(())
    } else {
        Err(ErrorEnvelope::new(
            ErrorCode::WorkerIncompatible,
            format!("worker script version {announced} != required {EXPECTED_WORKER_VERSION}"),
        ))
    }
}

/// A structured boot/transport failure envelope (retryable).
fn boot_env(msg: impl Into<String>) -> ErrorEnvelope {
    ErrorEnvelope::new(ErrorCode::WorkerUnavailable, msg.into())
}

/// Re-attach `last_good` on a freshly-booted holder if it differs from the boot's initial attachment
/// (spec §4.3). Best-effort: a re-attach failure is swallowed (the fresh worker is still usable at its
/// bootstrap program; the caller's retry will surface any real problem).
pub async fn boot_reattach(fresh: &mut WorkerHolder, last_good: Option<String>) {
    use ghidra_ipc::protocol::AttachResult;
    let Some(path) = last_good else { return };
    if fresh.active_program_path.as_deref() == Some(path.as_str()) {
        return;
    }
    let resp = fresh
        .booted
        .conn
        .request(&mk(
            "attach_program",
            serde_json::json!({ "program_path": path }),
        ))
        .await;
    if let Ok(r) = resp {
        if let Ok(v) = expect_success(r) {
            if let Ok(a) = serde_json::from_value::<AttachResult>(v) {
                fresh.active_program_path = a.attached;
                fresh.canon = AddressCanonicalizer::new(a.default_space, a.pointer_size);
            }
        }
    }
}

/// Build an RpcRequest with a fixed id=1 (single in-flight request per conn — the worker services one
/// at a time; the id is validated by `WorkerConn` per §4.4).
pub fn mk(method: &str, params: serde_json::Value) -> ghidra_ipc::rpc::RpcRequest {
    use ghidra_ipc::rpc::{JsonRpcVersion, RpcId, RpcRequest};
    RpcRequest {
        jsonrpc: JsonRpcVersion,
        id: RpcId::Number(1),
        method: method.to_string(),
        params: Some(params),
    }
}

/// Turn an `RpcResponse` into its `result` Value, or map a worker `Failure` into a structured envelope.
pub fn expect_success(
    resp: ghidra_ipc::rpc::RpcResponse,
) -> Result<serde_json::Value, ErrorEnvelope> {
    use ghidra_ipc::error_map::map_worker_error;
    use ghidra_ipc::rpc::RpcResponse;
    match resp {
        RpcResponse::Success { result, .. } => Ok(result),
        RpcResponse::Failure { error, .. } => {
            let code = error
                .get("code")
                .and_then(|c| c.as_str())
                .unwrap_or("WORKER_UNAVAILABLE");
            let message = error
                .get("message")
                .and_then(|m| m.as_str())
                .unwrap_or("worker error");
            let mut env = map_worker_error(code, message);
            // Preserve any candidates the worker attached (AMBIGUOUS_SYMBOL — spec §6) into details.
            if let Some(c) = error.get("candidates") {
                env = env.with_details(serde_json::json!({ "candidates": c }));
            }
            // Generic details object (RENAME_CONFLICT, INVALID_PARAMS.reason — spec §4). Mutually exclusive
            // with the candidates channel above; prefer the explicit object when the worker sent one.
            if let Some(d) = error.get("details") {
                env = env.with_details(d.clone());
            }
            Err(env)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matching_version_is_compatible() {
        assert!(check_worker_version(EXPECTED_WORKER_VERSION).is_ok());
    }

    #[test]
    fn expected_worker_version_is_0_7_0() {
        assert_eq!(EXPECTED_WORKER_VERSION, "0.7.0");
    }

    #[test]
    fn skewed_version_is_fatal_incompatible() {
        let err = check_worker_version("9.9.9").unwrap_err();
        assert_eq!(err.error.code, ErrorCode::WorkerIncompatible);
        assert!(err.error.message.contains("9.9.9"));
    }

    #[test]
    fn expect_success_lifts_worker_details_object() {
        let resp = ghidra_ipc::rpc::RpcResponse::Failure {
            jsonrpc: ghidra_ipc::rpc::JsonRpcVersion,
            id: ghidra_ipc::rpc::RpcId::Number(1),
            error: serde_json::json!({
                "code": "RENAME_CONFLICT", "message": "current name is 'compute', not 'x'",
                "details": { "address": "ram:00401000", "expected": "x", "actual": "compute" }
            }),
        };
        let env = expect_success(resp).unwrap_err();
        assert_eq!(env.error.code, ghidra_ipc::error::ErrorCode::RenameConflict);
        assert_eq!(env.error.details.unwrap()["actual"], "compute");
    }
}

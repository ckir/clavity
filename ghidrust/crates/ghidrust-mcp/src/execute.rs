//! The request engine (spec §4.3/§4.4/§4.7/§5): the ordered pipeline every tool call runs through.
//! Returns either a worker `result` Value (plus a snapshot of the active canonicalizer for the caller
//! to canonicalize addresses) or a structured `ErrorEnvelope`.

use crate::state::{boot_reattach, expect_success, mk, ServerState, WorkerHolder, WorkerSlot};
use ghidra_ipc::address::AddressCanonicalizer;
use ghidra_ipc::error::{ErrorCode, ErrorEnvelope};
use serde_json::Value;
use std::sync::Arc;
use tokio::time::timeout;

/// Terminal "reproducible crash" error (spec §4.3 poison-pill).
fn poison_terminal() -> ErrorEnvelope {
    ErrorEnvelope::new(
        ErrorCode::WorkerUnavailable,
        "this request reproducibly crashed the worker and has been blocked; change the selector",
    )
    .with_details(serde_json::json!({ "reproducible_crash": true }))
}

fn server_busy() -> ErrorEnvelope {
    ErrorEnvelope::new(ErrorCode::ServerBusy, "worker at capacity")
}

fn worker_warming() -> ErrorEnvelope {
    ErrorEnvelope::new(
        ErrorCode::WorkerWarming,
        "the Ghidra worker is still starting",
    )
}

/// Run one tool call. `selector` is the poison/short-circuit key component (e.g. the `function` arg,
/// or the `program_path`); pass `""` for selector-less calls. Returns `(result_value, canon_snapshot)`.
pub async fn call_worker(
    state: &Arc<ServerState>,
    tool: &str,
    selector: &str,
    method: &str,
    params: Value,
) -> Result<(Value, AddressCanonicalizer), ErrorEnvelope> {
    // 1) PRE-LOCK poison check (§4.3 round-7 seat-1).
    {
        let mut p = state.poison.lock().unwrap();
        if p.contains(tool, selector) {
            return Err(poison_terminal());
        }
    }
    // 2) Readiness wait (§4.7): NO permit, NO lock held during the wait (R2 seat-A).
    wait_until_ready(state).await?;
    // 3) Bounded permit — acquired BEFORE contending for the worker mutex (R3 seat-F).
    let _permit = state.sem.try_acquire().map_err(|_| server_busy())?;
    // 4) Run the RPC with transparent crash respawn (§4.3), respawn BOOT OUTSIDE the lock (R3 seat-G).
    run_with_respawn(state, tool, selector, method, params).await
}

/// Wait until the worker slot is `Ready`, kicking a single-flight background boot if `Empty`. Waits up
/// to `warming_deadline` (in ≤250 ms slices, woken early by `boot_done`); a boot longer than the budget
/// returns `WORKER_WARMING`. Holds the slot lock only for the instantaneous state checks, never across
/// the wait, and never while holding a permit (R2 seat-A).
async fn wait_until_ready(state: &Arc<ServerState>) -> Result<(), ErrorEnvelope> {
    let deadline = tokio::time::Instant::now() + state.cfg.warming_deadline;
    loop {
        {
            let mut slot = state.worker.lock().await;
            match slot_kind(&slot) {
                SlotKind::Ready => return Ok(()),
                SlotKind::Fatal => {
                    if let WorkerSlot::Fatal(e) = &*slot {
                        return Err(e.clone());
                    }
                    unreachable!("slot_kind said Fatal");
                }
                SlotKind::Empty => {
                    *slot = WorkerSlot::Booting;
                    drop(slot);
                    Arc::clone(state).spawn_boot();
                }
                SlotKind::Booting => { /* fall through to wait, lock released below */ }
            }
        }
        let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
        if remaining.is_zero() {
            return Err(worker_warming());
        }
        let slice = remaining.min(std::time::Duration::from_millis(250));
        let _ = tokio::time::timeout(slice, state.boot_done.notified()).await;
    }
}

/// Copyable classification of the worker slot, so a caller can inspect state and THEN take a `&mut`
/// borrow without an overlapping-borrow error (R2 seat-D).
#[derive(Clone, Copy)]
enum SlotKind {
    Empty,
    Booting,
    Ready,
    Fatal,
}

fn slot_kind(s: &WorkerSlot) -> SlotKind {
    match s {
        WorkerSlot::Empty => SlotKind::Empty,
        WorkerSlot::Booting => SlotKind::Booting,
        WorkerSlot::Ready(_) => SlotKind::Ready,
        WorkerSlot::Fatal(_) => SlotKind::Fatal,
    }
}

/// Acquire the worker mutex and run the RPC. On a transport crash, respawn OUTSIDE the lock (R3 seat-G)
/// and retry once; a second crash on the same request poisons the selector (§4.3). Attach state commits
/// atomically under the lock (R2 seat-C).
async fn run_with_respawn(
    state: &Arc<ServerState>,
    tool: &str,
    selector: &str,
    method: &str,
    params: Value,
) -> Result<(Value, AddressCanonicalizer), ErrorEnvelope> {
    let last_good = {
        let mut slot = state.worker.lock().await;
        let holder = match &mut *slot {
            WorkerSlot::Ready(h) => h,
            WorkerSlot::Fatal(e) => return Err(e.clone()),
            _ => return Err(worker_warming()),
        };
        if !holder.booted.conn.is_poisoned() {
            match rpc_once(holder, method, params.clone(), state.cfg.rpc_deadline).await {
                RpcOutcome::Ok(v) => {
                    commit_attach_if_needed(holder, method, &v);
                    return Ok((v, holder.canon.clone()));
                }
                RpcOutcome::Domain(e) => return Err(e),
                RpcOutcome::Crash => { /* fall through to respawn */ }
            }
        }
        match std::mem::replace(&mut *slot, WorkerSlot::Booting) {
            WorkerSlot::Ready(mut h) => {
                h.booted.lifecycle.on_crash();
                let lg = h.active_program_path.clone();
                tracing::warn!(last_good = ?lg, %method, "worker crashed; respawning OUTSIDE lock (others get WORKER_WARMING)");
                drop(h);
                lg
            }
            other => {
                *slot = other;
                return Err(worker_warming());
            }
        }
    };

    respawn_and_retry(state, tool, selector, method, params, last_good).await
}

/// Reboot a fresh worker (OUTSIDE the lock; slot is `Booting` so concurrent callers get WORKER_WARMING),
/// re-attach last good, and retry ONCE before publishing. A second crash poisons the selector.
async fn respawn_and_retry(
    state: &Arc<ServerState>,
    tool: &str,
    selector: &str,
    method: &str,
    params: Value,
    last_good: Option<String>,
) -> Result<(Value, AddressCanonicalizer), ErrorEnvelope> {
    let mut guard = BootingResetGuard::new(state);
    let mut fresh = match state.boot_and_probe().await {
        Ok(h) => h,
        Err(e) => {
            reset_booting_to_empty(state, &mut guard).await;
            return Err(e);
        }
    };
    boot_reattach(&mut fresh, last_good).await;
    match rpc_once(&mut fresh, method, params, state.cfg.rpc_deadline).await {
        RpcOutcome::Ok(v) => {
            commit_attach_if_needed(&mut fresh, method, &v);
            let canon = fresh.canon.clone();
            publish_ready(state, fresh, &mut guard).await;
            Ok((v, canon))
        }
        RpcOutcome::Domain(e) => {
            publish_ready(state, fresh, &mut guard).await;
            Err(e)
        }
        RpcOutcome::Crash => {
            drop(fresh);
            state.poison.lock().unwrap().insert(tool, selector);
            reset_booting_to_empty(state, &mut guard).await;
            Err(poison_terminal())
        }
    }
}

/// RAII guard resetting a `Booting` slot back to `Empty` if a respawn future is dropped before reaching
/// a terminal state (R5 cancellation-safety). Drop cannot await, so it uses a sync `try_lock`; on
/// contention it detaches a cleanup task. Idempotent: only resets if the slot is still `Booting`.
struct BootingResetGuard<'a> {
    state: &'a Arc<ServerState>,
    armed: bool,
}

impl<'a> BootingResetGuard<'a> {
    fn new(state: &'a Arc<ServerState>) -> Self {
        Self { state, armed: true }
    }
    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for BootingResetGuard<'_> {
    fn drop(&mut self) {
        if !self.armed {
            return;
        }
        if let Ok(mut slot) = self.state.worker.try_lock() {
            if matches!(&*slot, WorkerSlot::Booting) {
                *slot = WorkerSlot::Empty;
            }
            self.state.boot_done.notify_waiters();
        } else {
            let s = Arc::clone(self.state);
            tokio::spawn(async move {
                let mut slot = s.worker.lock().await;
                if matches!(&*slot, WorkerSlot::Booting) {
                    *slot = WorkerSlot::Empty;
                }
                s.boot_done.notify_waiters();
            });
        }
    }
}

/// Publish a freshly-booted worker into the slot (from `Booting`) and wake warming waiters. Disarms the
/// cancellation guard INSIDE the lock, after the write (R6 seat-P).
async fn publish_ready(
    state: &Arc<ServerState>,
    holder: WorkerHolder,
    guard: &mut BootingResetGuard<'_>,
) {
    {
        let mut slot = state.worker.lock().await;
        *slot = WorkerSlot::Ready(holder);
        guard.disarm();
    }
    state.boot_done.notify_waiters();
}

/// Reset a `Booting` slot back to `Empty` (retryable) after a failed respawn; wake warming waiters.
/// Only resets if still `Booting`. Disarms the guard INSIDE the lock, after the write (R6 seat-P).
async fn reset_booting_to_empty(state: &Arc<ServerState>, guard: &mut BootingResetGuard<'_>) {
    {
        let mut slot = state.worker.lock().await;
        if matches!(&*slot, WorkerSlot::Booting) {
            *slot = WorkerSlot::Empty;
        }
        guard.disarm();
    }
    state.boot_done.notify_waiters();
}

/// If the just-succeeded call was `attach_program`, commit the new active program + canonicalizer into
/// the holder WHILE THE SLOT LOCK IS STILL HELD (R2 seat-C atomicity). A parse failure leaves the prior
/// attachment intact.
fn commit_attach_if_needed(holder: &mut WorkerHolder, method: &str, result: &Value) {
    if method != "attach_program" {
        return;
    }
    if let Ok(a) = serde_json::from_value::<ghidra_ipc::protocol::AttachResult>(result.clone()) {
        holder.active_program_path = a.attached;
        holder.canon = AddressCanonicalizer::new(a.default_space, a.pointer_size);
    }
}

enum RpcOutcome {
    Ok(Value),
    Domain(ErrorEnvelope),
    Crash,
}

/// One RPC with poison-on-drop (§4.4) + rpc_deadline (§4.7). A transport error OR a deadline overrun is
/// a crash (respawn); a worker `Failure` frame is a domain error (worker alive).
async fn rpc_once(
    holder: &mut WorkerHolder,
    method: &str,
    params: Value,
    deadline: std::time::Duration,
) -> RpcOutcome {
    let req = mk(method, params);
    holder.booted.conn.poison();
    let res = timeout(deadline, holder.booted.conn.request_raw(&req)).await;
    match res {
        Ok(Ok(resp)) => {
            holder.booted.conn.unpoison();
            match expect_success(resp) {
                Ok(v) => RpcOutcome::Ok(v),
                Err(e) => RpcOutcome::Domain(e),
            }
        }
        Ok(Err(_io)) => RpcOutcome::Crash,
        Err(_elapsed) => RpcOutcome::Crash,
    }
}

/// Attach a program. The active-program + canon commit happens ATOMICALLY inside the engine under the
/// worker lock (via `commit_attach_if_needed`) — NOT here (R2 seat-C). This wrapper only supplies the
/// poison-key selector and runs the same crash/respawn engine (§4.3).
pub async fn attach_program(
    state: &Arc<ServerState>,
    program_path: &str,
) -> Result<Value, ErrorEnvelope> {
    let params = serde_json::json!({ "program_path": program_path });
    let (v, _canon) = call_worker(
        state,
        "attach_program",
        program_path,
        "attach_program",
        params,
    )
    .await?;
    Ok(v)
}

/// Snapshot the active canonicalizer (for canonicalizing an error-path candidate list).
pub async fn current_canon(state: &Arc<ServerState>) -> Option<AddressCanonicalizer> {
    let slot = state.worker.lock().await;
    match &*slot {
        WorkerSlot::Ready(h) => Some(h.canon.clone()),
        _ => None,
    }
}

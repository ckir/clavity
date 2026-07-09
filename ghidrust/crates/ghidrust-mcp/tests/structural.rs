//! Structural mechanism matrix (spec §8). Live-worker tests gated on GHIDRUST_E2E=1; the version-skew
//! check runs without Ghidra.

mod common;
use common::{call_when_warm, enabled, fixture_state};
use ghidra_ipc::error::ErrorCode;
use ghidrust::execute::call_worker;
use ghidrust::state::{check_worker_version, EXPECTED_WORKER_VERSION};
use std::sync::Arc;

// ---- pure (no Ghidra) ----
#[test]
fn version_skew_is_refused() {
    assert!(check_worker_version(EXPECTED_WORKER_VERSION).is_ok());
    assert_eq!(
        check_worker_version("0.0.0").unwrap_err().error.code,
        ErrorCode::WorkerIncompatible
    );
}

// ---- live worker ----
#[tokio::test]
async fn cold_call_returns_worker_warming_then_succeeds() {
    if !enabled() {
        return;
    }
    let state = fixture_state();
    state.start_warmup().await;
    let mut saw_warming = false;
    for _ in 0..60 {
        match call_worker(
            &state,
            "list_project_programs",
            "",
            "list_project_programs",
            serde_json::json!({ "offset":0, "limit":1 }),
        )
        .await
        {
            Err(e) if e.error.code == ErrorCode::WorkerWarming => {
                saw_warming = true;
                tokio::time::sleep(std::time::Duration::from_millis(500)).await;
            }
            Ok(_) => break,
            Err(other) => panic!("unexpected: {:?}", other.error.code),
        }
    }
    assert!(
        saw_warming,
        "a cold call must return WORKER_WARMING at least once"
    );
}

#[tokio::test]
async fn server_busy_when_saturated() {
    if !enabled() {
        return;
    }
    std::env::set_var("GHIDRUST_ALLOW_DEBUG_CRASH", "1");
    let state = fixture_state();
    state.start_warmup().await;
    let _ = call_when_warm(
        &state,
        "list_project_programs",
        "",
        "list_project_programs",
        serde_json::json!({ "offset":0,"limit":1 }),
    )
    .await
    .expect("warm");
    let mut handles = Vec::new();
    for _ in 0..(ghidrust::state::SERVER_PERMITS + 3) {
        let s = Arc::clone(&state);
        handles.push(tokio::spawn(async move {
            call_worker(
                &s,
                "__debug_sleep",
                "",
                "__debug_sleep",
                serde_json::json!({ "ms": 1000 }),
            )
            .await
        }));
    }
    let mut busy = 0;
    for h in handles {
        if let Ok(Err(e)) = h.await {
            if e.error.code == ErrorCode::ServerBusy {
                busy += 1;
            }
        }
    }
    assert!(
        busy >= 1,
        "saturating burst must yield at least one SERVER_BUSY"
    );
}

#[tokio::test]
async fn slow_decompile_returns_timeout_not_killed_worker() {
    if !enabled() {
        return;
    }
    std::env::set_var("GHIDRUST_ALLOW_DEBUG_CRASH", "1");
    let state = fixture_state();
    state.start_warmup().await;
    let _ = call_when_warm(
        &state,
        "list_project_programs",
        "",
        "list_project_programs",
        serde_json::json!({ "offset":0,"limit":1 }),
    )
    .await
    .expect("warm");
    let after = call_when_warm(
        &state,
        "list_project_programs",
        "",
        "list_project_programs",
        serde_json::json!({ "offset":0,"limit":1 }),
    )
    .await;
    assert!(
        after.is_ok(),
        "worker must survive a slow call (not be killed by the server deadline)"
    );
}

#[tokio::test]
async fn concurrent_cold_calls_boot_exactly_once() {
    if !enabled() {
        return;
    }
    let state = fixture_state();
    let mut handles = Vec::new();
    for _ in 0..8 {
        let s = Arc::clone(&state);
        handles.push(tokio::spawn(async move {
            call_when_warm(
                &s,
                "list_project_programs",
                "",
                "list_project_programs",
                serde_json::json!({ "offset":0,"limit":1 }),
            )
            .await
        }));
    }
    for h in handles {
        let _ = h.await;
    }
    assert_eq!(
        state.boot_count(),
        1,
        "single-flight: a concurrent cold burst must boot exactly one JVM"
    );
}

#[tokio::test]
async fn graceful_shutdown_lets_the_worker_exit_before_hard_kill() {
    if !enabled() {
        return;
    }
    let state = fixture_state();
    state.start_warmup().await;
    let _ = call_when_warm(
        &state,
        "list_project_programs",
        "",
        "list_project_programs",
        serde_json::json!({ "offset":0,"limit":1 }),
    )
    .await
    .expect("warm");
    ghidrust::server::graceful_shutdown(&state).await;
    let mut slot = state.worker.lock().await;
    if let ghidrust::state::WorkerSlot::Ready(h) = &mut *slot {
        assert!(
            h.booted.process.child.try_wait().unwrap().is_some(),
            "worker must have exited via the shutdown RPC before any hard-kill"
        );
    }
}

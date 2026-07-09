//! Crash/respawn + poison behavior (spec §4.3/§4.4). In-process; SIGKILLs the JVM via __debug_crash.
//! Gated on GHIDRUST_E2E=1 (real Ghidra) AND sets GHIDRUST_ALLOW_DEBUG_CRASH=1 for the worker.

mod common;
use common::{call_when_warm, enabled, fixture_state};
use ghidra_ipc::error::ErrorCode;
use ghidrust::execute::call_worker;

#[tokio::test]
async fn crash_is_transparently_respawned_and_reattached() {
    if !enabled() {
        return;
    }
    std::env::set_var("GHIDRUST_ALLOW_DEBUG_CRASH", "1");
    let state = fixture_state();
    state.start_warmup().await;
    let func = std::env::var("GHIDRUST_FIXTURE_FUNCTION").unwrap();
    // warm + one good call
    let _ = call_when_warm(
        &state,
        "inspect_function",
        &func,
        "inspect_function",
        serde_json::json!({ "function": func, "max_c_lines": 100 }),
    )
    .await
    .expect("first ok");
    // crash the worker
    let crashed = call_worker(
        &state,
        "debug",
        "crash",
        "__debug_crash",
        serde_json::json!({}),
    )
    .await;
    assert!(crashed.is_err(), "crash call should error (transport died)");
    // next call must transparently respawn + re-attach + succeed (agent sees only a latency spike §4.3)
    let v = call_when_warm(
        &state,
        "inspect_function",
        &func,
        "inspect_function",
        serde_json::json!({ "function": func, "max_c_lines": 100 }),
    )
    .await
    .expect("respawned ok");
    let fc: ghidra_ipc::protocol::FunctionContext = serde_json::from_value(v).unwrap();
    assert!(!fc.c.is_empty());
}

#[tokio::test]
async fn reproducible_crash_is_poisoned_and_short_circuits() {
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
    // First __debug_crash: crashes; respawn; retry once also crashes on the SAME selector → poisoned.
    // (Manual match instead of `.unwrap_err()`: the Ok side is `(Value, AddressCanonicalizer)` and
    // `AddressCanonicalizer` doesn't implement `Debug`, which `unwrap_err()` requires.)
    let first = match call_worker(
        &state,
        "__debug_crash",
        "x",
        "__debug_crash",
        serde_json::json!({}),
    )
    .await
    {
        Err(e) => e,
        Ok(_) => panic!("expected __debug_crash to error"),
    };
    assert_eq!(first.error.code, ErrorCode::WorkerUnavailable);
    assert_eq!(
        first.error.details.as_ref().unwrap()["reproducible_crash"],
        true
    );
    // Second identical request must SHORT-CIRCUIT (pre-lock) with the same terminal error, without a
    // third boot. Assert the terminal error + fast return.
    let start = std::time::Instant::now();
    let second = match call_worker(
        &state,
        "__debug_crash",
        "x",
        "__debug_crash",
        serde_json::json!({}),
    )
    .await
    {
        Err(e) => e,
        Ok(_) => panic!("expected __debug_crash to error"),
    };
    assert_eq!(
        second.error.details.as_ref().unwrap()["reproducible_crash"],
        true
    );
    assert!(
        start.elapsed() < std::time::Duration::from_secs(2),
        "poison short-circuit must be fast (no reboot)"
    );
}

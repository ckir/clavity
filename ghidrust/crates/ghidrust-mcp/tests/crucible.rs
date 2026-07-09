//! In-process Crucible assertions (spec §8): drive ServerState/execute directly so garbage inputs
//! return the RIGHT structured ErrorCode. Gated on GHIDRUST_E2E=1 + fixture env (real Ghidra).

mod common;
use common::{call_when_warm, enabled, fixture_state};
use ghidra_ipc::error::ErrorCode;
use ghidrust::execute::{attach_program, call_worker};

#[tokio::test]
async fn inspect_function_returns_real_c_on_bootstrap_program() {
    if !enabled() {
        eprintln!("skip: set GHIDRUST_E2E=1 + fixture env");
        return;
    }
    let state = fixture_state();
    state.start_warmup().await;
    let func = common::env("GHIDRUST_FIXTURE_FUNCTION").expect("FIXTURE_FUNCTION");
    // Drive call_worker directly (call_when_warm discards the canon), then canonicalize the raw worker
    // FunctionContext exactly as the tool handler (server.rs) does — proving space:offset -> 0x end to
    // end. (call_worker returns the RAW worker shape; canonicalization is the handler's job, §6.)
    let mut got = None;
    for _ in 0..60 {
        match call_worker(
            &state,
            "inspect_function",
            &func,
            "inspect_function",
            serde_json::json!({ "function": func, "max_c_lines": 2000 }),
        )
        .await
        {
            Err(e) if e.error.code == ErrorCode::WorkerWarming => {
                tokio::time::sleep(std::time::Duration::from_secs(1)).await;
            }
            Ok(pair) => {
                got = Some(pair);
                break;
            }
            Err(e) => panic!("inspect failed: {:?} {}", e.error.code, e.error.message),
        }
    }
    let (v, canon) = got.expect("worker warmed + inspect ok within 60s");
    let fc: ghidra_ipc::protocol::FunctionContext = serde_json::from_value(v).unwrap();
    assert!(!fc.c.is_empty(), "decompiled C must be non-empty");
    let fc = ghidrust::tools::canonicalize_function_context(&canon, fc);
    assert!(
        fc.entry_point.starts_with("0x"),
        "entry_point canonical after handler-canon: {}",
        fc.entry_point
    );
}

#[tokio::test]
async fn crucible_domain_errors() {
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
        serde_json::json!({ "offset": 0, "limit": 10 }),
    )
    .await
    .expect("list ok");

    // hallucinated name → NOT_A_FUNCTION
    let e = call_when_warm(
        &state,
        "inspect_function",
        "no_such_fn_zzz",
        "inspect_function",
        serde_json::json!({ "function": "no_such_fn_zzz", "max_c_lines": 100 }),
    )
    .await
    .unwrap_err();
    assert_eq!(e.error.code, ErrorCode::NotAFunction);
    // NOTE: suggested_action canonicalization (server.rs GhidrustServer::err_canon) is applied by the
    // TOOL HANDLER, NOT by call_worker which returns the code's default action. This engine-layer test
    // asserts the CODE (its stated purpose); the action text itself is pinned in
    // ghidra_ipc::error::retired_bridge_actions_name_shipped_tools.

    // address with no function defined → NOT_A_FUNCTION (unanalyzed hint)
    let e = call_when_warm(
        &state,
        "inspect_function",
        "0x00000000",
        "inspect_function",
        serde_json::json!({ "function": "0x00000000", "max_c_lines": 100 }),
    )
    .await
    .unwrap_err();
    assert_eq!(e.error.code, ErrorCode::NotAFunction);

    // wrong program_path → PROGRAM_NOT_FOUND
    let e = attach_program(&state, "/does_not_exist.bin")
        .await
        .unwrap_err();
    assert_eq!(e.error.code, ErrorCode::ProgramNotFound);

    // list pagination caps
    let v = call_when_warm(
        &state,
        "list_project_programs",
        "",
        "list_project_programs",
        serde_json::json!({ "offset": 0, "limit": 1 }),
    )
    .await
    .unwrap();
    let lp: ghidra_ipc::protocol::ListProjectPrograms = serde_json::from_value(v).unwrap();
    assert!(lp.programs.len() <= 1);
}

// M2d set_local e2e. Gated by GHIDRUST_E2E=1. Run from PowerShell, -j1 (single JVM per worker):
//   $env:GHIDRUST_E2E="1"; cargo nextest run -p ghidrust-mcp --test setlocal -j1
mod common;
use common::*;
use ghidrust::state::ServerState;
use std::sync::Arc;

// Fixture facts pinned by the Task 0 live spike (docs/superpowers/spikes/M2d-local-retype-notes.md) and
// the canonical `tests/fixtures/README.md` import. `locals_demo`'s address-taken scalar `acc` is the ONLY
// clean decompiler STACK local across the whole fixture (every other function decompiles to
// register-only locals, which set_local v1 rejects — Q4 allow-list = stack only):
//
//   FN locals_demo customStorage=false
//     local_24   stack:-0x24  uint     <- acc; THE retype/rename target for this suite
//     aiStack_18 stack:-0x18  int[4]   <- buf; an unrelated sibling (untouched by these tests)
//     local_8    stack:-0x8   int
//     local_4    stack:-0x4   uint
//     param_1    ECX:4  (register param, excluded from locals[] — the param-reject case, test 7)
//
// A same-size retype uint->int on local_24 is clean & deterministic (spike Q1/Q3). Renaming it uses
// "packet_len". The oversize case grows the 4-byte slot to an 8-byte type (double) per spike guidance.
const P_FN: &str = "locals_demo";
const LOCAL_ACC: &str = "stack:-0x24"; // local_24 : uint @ stack:-0x24 (acc)

async fn set_local_call(
    state: &Arc<ServerState>,
    target: &str,
    variable: &str,
    new_type: Option<&str>,
    new_name: Option<&str>,
    expected_type: Option<&str>,
    expected_name: Option<&str>,
) -> Result<serde_json::Value, serde_json::Value> {
    let mut jp = serde_json::json!({ "target": target, "variable": variable });
    if let Some(t) = new_type {
        jp["new_type"] = serde_json::Value::String(t.to_string());
    }
    if let Some(n) = new_name {
        jp["new_name"] = serde_json::Value::String(n.to_string());
    }
    if let Some(t) = expected_type {
        jp["expected_type"] = serde_json::Value::String(t.to_string());
    }
    if let Some(n) = expected_name {
        jp["expected_name"] = serde_json::Value::String(n.to_string());
    }
    call_when_warm(state, "set_local", target, "set_local", jp)
        .await
        .map_err(|e| serde_json::to_value(e).unwrap())
}

// Read the current FunctionContext (for the `locals[]` re-read oracle).
async fn read_context(state: &Arc<ServerState>, target: &str) -> serde_json::Value {
    call_when_warm(
        state,
        "inspect_function",
        target,
        "inspect_function",
        serde_json::json!({ "function": target }),
    )
    .await
    .expect("inspect")
}

// Test 1 — retype the stack local; re-read locals[] reflects the new type.
#[tokio::test]
async fn set_local_retype_stack_local_reflects_in_locals() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let r = set_local_call(&state, P_FN, LOCAL_ACC, Some("int"), None, None, None)
        .await
        .expect("retype");
    assert_eq!(r["status"], "retyped");
    assert_eq!(r["type"], "int");
    assert_eq!(r["storage"], LOCAL_ACC);
    assert_eq!(r["durable"], true);
    let fc = read_context(&state, P_FN).await;
    let locals = fc["locals"].as_array().unwrap();
    let hit = locals
        .iter()
        .find(|l| l["storage"] == LOCAL_ACC)
        .expect("edited local present in locals[]");
    assert_eq!(hit["type"], "int");
}

// Test 2 — rename; durable across a hard restart; re-applying the same rename via the storage handle
// after the restart is already_applied (proves the DB, not just in-memory state, holds the new name).
#[tokio::test]
async fn set_local_rename_persists_across_restart() {
    if !enabled() {
        return;
    }
    let (dir, state) = fixture_state_ephemeral();
    let r = set_local_call(
        &state,
        P_FN,
        LOCAL_ACC,
        None,
        Some("packet_len"),
        None,
        None,
    )
    .await
    .expect("rename");
    assert_eq!(r["status"], "renamed");
    assert_eq!(r["name"], "packet_len");
    assert_eq!(r["durable"], true);
    drop(state);
    // Boot a SECOND JVM on the same on-disk copy; the DB name must have persisted.
    let state2 = fixture_state_at(&dir.path);
    let again = set_local_call(
        &state2,
        P_FN,
        LOCAL_ACC,
        None,
        Some("packet_len"),
        None,
        None,
    )
    .await
    .expect("persisted");
    assert_eq!(
        again["status"], "already_applied",
        "rename must have persisted to disk"
    );
}

// Test 3 — combined new_type + new_name -> status:set.
#[tokio::test]
async fn set_local_combined_retype_and_rename_returns_set() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let r = set_local_call(
        &state,
        P_FN,
        LOCAL_ACC,
        Some("int"),
        Some("packet_len"),
        None,
        None,
    )
    .await
    .expect("set");
    assert_eq!(r["status"], "set");
    assert_eq!(r["type"], "int");
    assert_eq!(r["name"], "packet_len");
}

// Test 4a — idempotent re-apply USING THE STORAGE HANDLE of an already-applied edit -> already_applied.
#[tokio::test]
async fn set_local_idempotent_reapply_via_storage_handle() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let a = set_local_call(
        &state,
        P_FN,
        LOCAL_ACC,
        Some("int"),
        Some("packet_len"),
        None,
        None,
    )
    .await
    .expect("set");
    assert_eq!(a["status"], "set");
    let b = set_local_call(
        &state,
        P_FN,
        LOCAL_ACC,
        Some("int"),
        Some("packet_len"),
        None,
        None,
    )
    .await
    .expect("noop");
    assert_eq!(b["status"], "already_applied");
}

// Test 4b — name-instability proof: after renaming local_24 -> packet_len, retry the SAME edit via the
// OLD NAME handle ("local_24") -> VARIABLE_NOT_FOUND (the name is a weak/stale selector; storage is the
// stable primary key, per spike Q2/D-STORAGE-KEY).
#[tokio::test]
async fn set_local_old_name_after_rename_is_variable_not_found() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let r = set_local_call(
        &state,
        P_FN,
        LOCAL_ACC,
        None,
        Some("packet_len"),
        None,
        None,
    )
    .await
    .expect("rename");
    assert_eq!(r["status"], "renamed");
    let err = set_local_call(&state, P_FN, "local_24", Some("int"), None, None, None)
        .await
        .unwrap_err();
    assert_eq!(err["error"]["code"], "VARIABLE_NOT_FOUND");
}

// Test 5 — expected_type drift -> STATE_CONFLICT with details.actual echoing the real current type.
#[tokio::test]
async fn set_local_expected_type_drift_conflicts() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    // local_24's real current type is "uint" (spike-confirmed); assert a wrong expected_type.
    let err = set_local_call(
        &state,
        P_FN,
        LOCAL_ACC,
        Some("int"),
        None,
        Some("NoSuchExpectedType"),
        None,
    )
    .await
    .unwrap_err();
    assert_eq!(err["error"]["code"], "STATE_CONFLICT");
    assert_eq!(err["error"]["details"]["actual"], "uint");
}

// Test 6 — bogus storage/name -> VARIABLE_NOT_FOUND; details.nearest is bounded (<=5 entries, NOT the
// whole locals[] list — spec §4.1 R1-Seat5).
#[tokio::test]
async fn set_local_bogus_storage_is_variable_not_found_with_bounded_nearest() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let err = set_local_call(&state, P_FN, "stack:-0x999", Some("int"), None, None, None)
        .await
        .unwrap_err();
    assert_eq!(err["error"]["code"], "VARIABLE_NOT_FOUND");
    let nearest = err["error"]["details"]["nearest"].as_array().unwrap();
    assert!(
        nearest.len() <= 5,
        "nearest must be bounded to <=5 entries, got {}: {nearest:?}",
        nearest.len()
    );
}

// Test 7 — a PARAMETER target is rejected -> INVALID_PARAMS pointing at set_prototype (params live in
// the prototype, not locals[]; compute's param_1 is a register param excluded from set_local's targets).
#[tokio::test]
async fn set_local_param_target_is_invalid_params_pointing_at_set_prototype() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let err = set_local_call(&state, "compute", "param_1", Some("int"), None, None, None)
        .await
        .unwrap_err();
    assert_eq!(err["error"]["code"], "INVALID_PARAMS");
    let msg = err["error"]["message"].as_str().unwrap_or("");
    assert!(
        msg.contains("set_prototype"),
        "message should point the agent at set_prototype: {msg}"
    );
}

// Test 8 — unresolvable new_type -> DATATYPE_NOT_FOUND.
#[tokio::test]
async fn set_local_unresolvable_type_is_datatype_not_found() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let err = set_local_call(
        &state,
        P_FN,
        LOCAL_ACC,
        Some("NoSuchType_xyz"),
        None,
        None,
        None,
    )
    .await
    .unwrap_err();
    assert_eq!(err["error"]["code"], "DATATYPE_NOT_FOUND");
}

// Test 8b — new_type:"void" is not a legal variable type -> INVALID_PARAMS.
#[tokio::test]
async fn set_local_void_type_is_invalid_params() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let err = set_local_call(&state, P_FN, LOCAL_ACC, Some("void"), None, None, None)
        .await
        .unwrap_err();
    assert_eq!(err["error"]["code"], "INVALID_PARAMS");
}

// Test 8c — a type that OVERFLOWS the stack frame -> INVALID_PARAMS (Ghidra throws InvalidInputException
// "Data type does not fit within variable stack constraints", caught by withTransaction, per spec §4.1
// "oversize/overlap"). NOTE (verified live via a headless probe against this fixture): unlike a fixed-slot
// register/param, a STACK local has room to GROW — `double` (8B) and even `char[16]` are ACCEPTED on the
// 4-byte `local_24` slot. Only a type large enough to overrun the available stack space is rejected;
// `char[64]` reliably throws. So "oversize" here means "overflows the frame", not merely "bigger than now".
#[tokio::test]
async fn set_local_oversize_type_is_invalid_params() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let err = set_local_call(&state, P_FN, LOCAL_ACC, Some("char[64]"), None, None, None)
        .await
        .unwrap_err();
    assert_eq!(err["error"]["code"], "INVALID_PARAMS");
}

// Test 8d — a new_type name that resolves to >1 DB type -> AMBIGUOUS_DATATYPE with details.candidates.
// "byte" is a REAL, previously-confirmed-live ambiguous name in this exact fixture (Ghidra's builtin
// /byte vs the PDB's /fixture.pdb/std/byte) — see writesurface.rs's
// set_datatype_does_not_delete_following_neighbour, which documents the same collision for set_datatype.
// This is not fabricated: it reuses resolveTypeByName's findDataTypes(name) ambiguity path, the same
// mechanism get_datatype/set_datatype already exercise against this fixture.
#[tokio::test]
async fn set_local_ambiguous_type_name_is_ambiguous_datatype() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let err = set_local_call(&state, P_FN, LOCAL_ACC, Some("byte"), None, None, None)
        .await
        .unwrap_err();
    assert_eq!(err["error"]["code"], "AMBIGUOUS_DATATYPE");
    let cands = err["error"]["details"]["candidates"].as_array().unwrap();
    assert!(
        cands.len() > 1,
        "expected >1 candidate for the ambiguous 'byte': {cands:?}"
    );
}

// Test 9 — neither new_type nor new_name given -> INVALID_PARAMS.
#[tokio::test]
async fn set_local_no_mutation_fields_is_invalid_params() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let err = set_local_call(&state, P_FN, LOCAL_ACC, None, None, None, None)
        .await
        .unwrap_err();
    assert_eq!(err["error"]["code"], "INVALID_PARAMS");
}

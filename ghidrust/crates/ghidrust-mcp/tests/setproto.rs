// M2c set_prototype e2e. Gated by GHIDRUST_E2E=1. Run from PowerShell, -j1 (single JVM per worker):
//   $env:GHIDRUST_E2E="1"; cargo nextest run -p ghidrust-mcp --test setproto -j1
mod common;
use common::*;
use ghidrust::state::ServerState;
use std::sync::Arc;

// Fixture facts discovered LIVE (Task 7 Step 0) against the ghidrust-fix build, real Ghidra 12.1.2, via a
// temporary `_discover` test that dumped inspect_function on every candidate. All five fixture functions
// take only `uint` scalar params (fixture.c), so the decompiler-change oracle (test 3) retypes add_two's
// first param to `Rect *` (a known fixture struct, g_rect is `Rect`) and asserts the decompiled C header
// re-renders it — a NON-circular oracle: `c` is decompiler output (proves disposeDecompiler dropped the
// cache + re-ran), while the structured `prototype` echo independently proves the Program-DB write.
//
//   add_two   ram:140001000  uint __cdecl add_two(uint param_1, uint param_2)   { return param_1 + param_2; }
//   mul       ram:140001020  uint __cdecl mul(uint param_1, uint param_2)       { return param_1 * param_2; }
//   compute     ram:140001040  uint __cdecl compute(uint param_1, uint param_2)
//   locals_demo ram:140001070  uint __cdecl locals_demo(uint param_1)  (M2d: stack-local set_local target)
//   api_entry   ram:1400010f0  uint __cdecl api_entry(uint param_1)
//   main        ram:140001120  int  __cdecl main(void)
//   g_rect    ram:140075000  Rect global (a NON-function data address — NOT_A_FUNCTION oracle, writesurface.rs:19)
const P_FN: &str = "add_two";
const D_RECT: &str = "ram:140075000"; // g_rect — a data address, not a function

async fn set_prototype_call(
    state: &Arc<ServerState>,
    target: &str,
    return_type: &str,
    calling_convention: &str,
    params: serde_json::Value, // e.g. json!([{"name":"a","type":"int"}])
    variadic: bool,
    expected_signature: Option<&str>,
) -> Result<serde_json::Value, serde_json::Value> {
    let mut jp = serde_json::json!({
        "target": target, "return_type": return_type,
        "calling_convention": calling_convention, "params": params, "variadic": variadic
    });
    if let Some(e) = expected_signature {
        jp["expected_signature"] = serde_json::Value::String(e.to_string());
    }
    call_when_warm(state, "set_prototype", target, "set_prototype", jp)
        .await
        .map_err(|e| serde_json::to_value(e).unwrap())
}

// Read the current DB signature string of a function (for the CAS echo + assertions).
async fn read_signature(state: &Arc<ServerState>, target: &str) -> serde_json::Value {
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

// Test 1 — durability across a hard restart.
#[tokio::test]
async fn set_prototype_persists_across_restart() {
    if !enabled() {
        return;
    }
    let (dir, state) = fixture_state_ephemeral();
    // add_two is `uint add_two(uint param_1, uint param_2)`; renaming the params a/b is a real change.
    let r = set_prototype_call(
        &state,
        "add_two",
        "uint",
        "__cdecl",
        serde_json::json!([{"name":"a","type":"uint"},{"name":"b","type":"uint"}]),
        false,
        None,
    )
    .await
    .expect("set");
    assert_eq!(r["status"], "set");
    assert_eq!(r["durable"], true);
    drop(state);
    // Boot a SECOND JVM on the same on-disk copy; the DB signature must have persisted.
    let state2 = fixture_state_at(&dir.path);
    let again = set_prototype_call(
        &state2,
        "add_two",
        "uint",
        "__cdecl",
        serde_json::json!([{"name":"a","type":"uint"},{"name":"b","type":"uint"}]),
        false,
        None,
    )
    .await
    .expect("persisted");
    assert_eq!(
        again["status"], "already_applied",
        "signature must have persisted to disk"
    );
}

// Test 1b — positive CAS (echo the real signature).
#[tokio::test]
async fn set_prototype_positive_cas_echo_succeeds() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let sig = read_signature(&state, "mul").await["signature"]
        .as_str()
        .unwrap()
        .to_string();
    // Echo the exact current signature as expected_signature on a REAL edit (change return type).
    let r = set_prototype_call(
        &state,
        "mul",
        "long",
        "__cdecl",
        serde_json::json!([{"name":"a","type":"uint"},{"name":"b","type":"uint"}]),
        false,
        Some(&sig),
    )
    .await
    .expect("cas ok");
    // Proves read `signature` and worker CAS use the SAME prototype-string overload.
    assert_eq!(r["status"], "set");
}

// Test 2 — idempotency via isEquivalent.
#[tokio::test]
async fn set_prototype_identical_twice_is_idempotent() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let p = serde_json::json!([{"name":"a","type":"int"},{"name":"b","type":"int"}]);
    let a = set_prototype_call(&state, "add_two", "int", "__cdecl", p.clone(), false, None)
        .await
        .expect("set");
    assert_eq!(a["status"], "set");
    let b = set_prototype_call(&state, "add_two", "int", "__cdecl", p, false, None)
        .await
        .expect("noop");
    assert_eq!(b["status"], "already_applied");
}

// Test 3 — decompiler-change oracle: retype add_two's first param to `Rect *` and assert the decompiled C
// re-renders it (proves disposeDecompiler dropped the cache), plus the structured prototype echoes the DB.
#[tokio::test]
async fn set_prototype_propagates_into_decompiler() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let r = set_prototype_call(
        &state,
        P_FN,
        "uint",
        "__cdecl",
        serde_json::json!([{"name":"r","type":"Rect *"},{"name":"b","type":"uint"}]),
        false,
        None,
    )
    .await
    .expect("set");
    assert_eq!(r["status"], "set");
    // Re-read: the decompiled C must reflect the applied pointer type (re-decompilation happened).
    let fc = read_signature(&state, P_FN).await;
    let c = fc["c"].as_str().unwrap();
    assert!(
        c.contains("Rect"),
        "decompiled C did not reflect the applied Rect* param: {c}"
    );
    // The structured read is symmetric: prototype echoes the DB signature just written.
    assert_eq!(fc["prototype"]["params"][0]["type"], "Rect *");
}

// Test 4 — expected_signature drift -> STATE_CONFLICT.
#[tokio::test]
async fn set_prototype_wrong_expected_signature_conflicts() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let sig = read_signature(&state, "compute").await["signature"]
        .as_str()
        .unwrap()
        .to_string();
    let err = set_prototype_call(
        &state,
        "compute",
        "int",
        "__cdecl",
        serde_json::json!([]),
        false,
        Some("int __cdecl compute(WRONG)"),
    )
    .await
    .unwrap_err();
    assert_eq!(err["error"]["code"], "STATE_CONFLICT");
    assert_eq!(err["error"]["details"]["actual"], sig);
}

// Test 5 — type-resolution errors.
#[tokio::test]
async fn set_prototype_type_errors() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    // Unknown return type -> DATATYPE_NOT_FOUND (and un-parseable, so no synthesis).
    let e1 = set_prototype_call(
        &state,
        "add_two",
        "NoSuchType_zzz",
        "__cdecl",
        serde_json::json!([{"type":"int"}]),
        false,
        None,
    )
    .await
    .unwrap_err();
    assert_eq!(e1["error"]["code"], "DATATYPE_NOT_FOUND");
}

// Test 6 — the P1 runtime residual, resolved to the documented fallback (spec §7 P1). Ghidra's
// DataTypeParser does NOT parse the C function-pointer declarator `void (*)(int)` (verified live: it
// errors "Unrecognized data type of 'void ('"). Per the spec P1 fallback, an un-nameable AND un-parseable
// type is scoped out to DATATYPE_NOT_FOUND rather than a whole-signature C-parse — the worker's
// synthesizeType catch surfaces exactly that. This proves the fallback is clean (no crash / WORKER_
// UNAVAILABLE): the agent must spell a complex type as a named typedef instead (documented in SKILL.md).
// (Pointer-to-named-type synthesis, e.g. `Rect *`, DOES work via DataTypeParser — exercised by test 3.)
#[tokio::test]
async fn set_prototype_unparseable_fn_pointer_is_datatype_not_found() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let fp = serde_json::json!([{"name":"cb","type":"void (*)(int)"}]);
    let e = set_prototype_call(&state, "add_two", "void", "__cdecl", fp, false, None)
        .await
        .unwrap_err();
    assert_eq!(e["error"]["code"], "DATATYPE_NOT_FOUND");
}

// Test 7 — varargs.
#[tokio::test]
async fn set_prototype_variadic() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let r = set_prototype_call(
        &state,
        "add_two",
        "int",
        "__cdecl",
        serde_json::json!([{"name":"fmt","type":"char *"}]),
        true,
        None,
    )
    .await
    .expect("set");
    assert_eq!(r["status"], "set");
    let fc = read_signature(&state, "add_two").await;
    assert_eq!(fc["prototype"]["variadic"], true);
    assert!(
        fc["signature"].as_str().unwrap().contains("..."),
        "varargs must render in the prototype string"
    );
}

// Test 8 — boundary/negatives.
#[tokio::test]
async fn set_prototype_boundaries() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    // (a) non-function address -> NOT_A_FUNCTION. g_rect is a data address.
    let e_nf = set_prototype_call(
        &state,
        D_RECT,
        "int",
        "__cdecl",
        serde_json::json!([]),
        false,
        None,
    )
    .await
    .unwrap_err();
    assert_eq!(e_nf["error"]["code"], "NOT_A_FUNCTION");
    // (b) void param type -> INVALID_PARAMS.
    let e_void = set_prototype_call(
        &state,
        "add_two",
        "int",
        "__cdecl",
        serde_json::json!([{"type":"void"}]),
        false,
        None,
    )
    .await
    .unwrap_err();
    assert_eq!(e_void["error"]["code"], "INVALID_PARAMS");
    // (c) bad calling convention -> INVALID_PARAMS listing the valid set.
    let e_cc = set_prototype_call(
        &state,
        "add_two",
        "int",
        "NoSuchCC",
        serde_json::json!([]),
        false,
        None,
    )
    .await
    .unwrap_err();
    assert_eq!(e_cc["error"]["code"], "INVALID_PARAMS");
    // (d) a THUNK/EXTERNAL import and (e) a custom-storage function: the ghidrust-fix build statically
    //     links the CRT (printf is a DEFINED function, not a thunk/import) and has no custom-storage
    //     function, so both rejects are untestable in this fixture — covered by the worker's up-front
    //     isThunk/isExternal/hasCustomVariableStorage guards (Task 5) and documented here.
}

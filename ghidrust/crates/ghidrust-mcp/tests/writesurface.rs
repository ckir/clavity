// M2b write-surface e2e. Gated by GHIDRUST_E2E=1. Run from PowerShell, -j1 (single JVM per worker):
//   $env:GHIDRUST_E2E="1"; cargo nextest run -p ghidrust-mcp --test writesurface -j1
mod common;
use common::*;
use ghidrust::state::ServerState;
use std::sync::Arc;

// Fixture addresses discovered (Task 8) against the ghidrust-fix build, via a temporary `_discover`
// test that dumped list_data_items / list_strings / list_segments / inspect_function(api_entry,main)
// and then describe_address probes, all run live against real Ghidra 12.1.2. Provenance:
//
//   inspect_function(api_entry).data_refs -> { "address": "ram:140062000" -> the string literal
//     "https://example.test/beacon" is what g_banner (the char* global at ram:140075018, itself a
//     data_ref of api_entry) POINTS TO. list_strings shows it as
//     { "address": "ram:140062000", "encoding": "TerminatedCString", "length": 28,
//       "value": "https://example.test/beacon" } — a distinct (legacy) type from Ghidra's built-in
//     "string", so set_datatype(.., "string") is expected to apply (not already_applied).
//
//   list_data_items(filter=g_rect)   -> { "address": "ram:140075000", "data_type": "Rect",   "size": 16 }
//   list_data_items(filter=g_color)  -> { "address": "ram:140075010", "data_type": "Color",  "size": 4  }
//   list_data_items(filter=g_banner) -> { "address": "ram:140075018", "data_type": "char *", "size": 8  }
//   describe_address(ram:140075020) -> defined uint  "__scrt_native_dllmain_reason"
//   describe_address(ram:140075024) -> defined int   "__scrt_default_matherr" (ends at 0x28)
//   describe_address(ram:140075028) -> NO data_type field => genuinely UNDEFINED
//   describe_address(ram:140075030) -> NO data_type field => genuinely UNDEFINED
//   describe_address(ram:140075040) -> defined ulong64 "__security_cookie" (starts at 0x40)
//   => ram:140075028..0x3f is a 24-byte undefined gap in the initialized, writable, non-code .data
//     segment, comfortably clear of g_rect/g_color/g_banner (0x00-0x20) and __security_cookie (0x40).
const D_STRING: &str = "ram:140062000";
const D_NEIGH: &str = "ram:140075028";
const D_NEIGH_NEXT: &str = "ram:14007502c"; // D_NEIGH + 4
const D_NEIGH_OFFCUT: &str = "ram:140075029"; // D_NEIGH + 1

async fn comment_call(
    state: &Arc<ServerState>,
    target: &str,
    ctype: &str,
    new_comment: &str,
    expected: Option<&str>,
) -> Result<serde_json::Value, serde_json::Value> {
    let mut jp =
        serde_json::json!({ "target": target, "comment_type": ctype, "new_comment": new_comment });
    if let Some(e) = expected {
        jp["expected_comment"] = serde_json::Value::String(e.to_string());
    }
    call_when_warm(state, "comment", target, "comment", jp)
        .await
        .map_err(|e| serde_json::to_value(e).unwrap())
}

async fn set_datatype_call(
    state: &Arc<ServerState>,
    target: &str,
    datatype_name: &str,
    expected: Option<&str>,
) -> Result<serde_json::Value, serde_json::Value> {
    let mut jp = serde_json::json!({ "target": target, "datatype_name": datatype_name });
    if let Some(e) = expected {
        jp["expected_datatype"] = serde_json::Value::String(e.to_string());
    }
    call_when_warm(state, "set_datatype", target, "set_datatype", jp)
        .await
        .map_err(|e| serde_json::to_value(e).unwrap())
}

#[tokio::test]
async fn comment_plate_persists_across_restart() {
    if !enabled() {
        return;
    }
    let (dir, state) = fixture_state_ephemeral();
    let r = comment_call(&state, "mul", "plate", "decrypts the payload", None)
        .await
        .expect("set");
    assert_eq!(r["status"], "set");
    assert_eq!(r["durable"], true);
    drop(state);
    let state2 = fixture_state_at(&dir.path);
    let again = comment_call(&state2, "mul", "plate", "decrypts the payload", None)
        .await
        .expect("persisted");
    assert_eq!(
        again["status"], "already_applied",
        "plate comment must have persisted to disk"
    );
}

#[tokio::test]
async fn comment_identical_twice_is_idempotent() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let a = comment_call(&state, "add_two", "eol", "adds two ints", None)
        .await
        .expect("set");
    assert_eq!(a["status"], "set");
    let b = comment_call(&state, "add_two", "eol", "adds two ints", None)
        .await
        .expect("noop");
    assert_eq!(b["status"], "already_applied");
}

#[tokio::test]
async fn comment_guard_conflict_then_clear() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    comment_call(&state, "add_two", "pre", "real note", None)
        .await
        .expect("set");
    let err = comment_call(&state, "add_two", "pre", "new", Some("WRONG"))
        .await
        .unwrap_err();
    assert_eq!(err["error"]["code"], "STATE_CONFLICT");
    assert_eq!(err["error"]["details"]["actual"], "real note");
    let cl = comment_call(&state, "add_two", "pre", "", None)
        .await
        .expect("clear");
    assert_eq!(cl["status"], "cleared");
    assert_eq!(cl["previous_comment"], "real note");
}

#[tokio::test]
async fn comment_offcut_is_rejected() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    set_datatype_call(&state, D_NEIGH, "int", None)
        .await
        .expect("define 4-byte int");
    let err = comment_call(&state, D_NEIGH_OFFCUT, "eol", "ghost", None)
        .await
        .unwrap_err();
    assert_eq!(err["error"]["code"], "INVALID_PARAMS");
    let ok = comment_call(&state, D_NEIGH, "eol", "real", None)
        .await
        .expect("at-start ok");
    assert_eq!(ok["status"], "set");
}

#[tokio::test]
async fn set_datatype_string_persists() {
    if !enabled() {
        return;
    }
    let (dir, state) = fixture_state_ephemeral();
    let s = set_datatype_call(&state, D_STRING, "string", None)
        .await
        .expect("string set");
    assert_eq!(s["status"], "set");
    assert!(
        s["length"].as_i64().unwrap() >= 1,
        "string sized dynamically, not -1"
    );
    drop(state);
    let state2 = fixture_state_at(&dir.path);
    let again = set_datatype_call(&state2, D_STRING, "string", None)
        .await
        .expect("persisted");
    assert_eq!(
        again["status"], "already_applied",
        "string type persisted to disk"
    );
}

#[tokio::test]
async fn set_datatype_identical_twice_is_idempotent() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let a = set_datatype_call(&state, D_NEIGH, "int", None)
        .await
        .expect("set");
    assert!(a["status"] == "set" || a["status"] == "already_applied");
    let b = set_datatype_call(&state, D_NEIGH, "int", None)
        .await
        .expect("noop");
    assert_eq!(b["status"], "already_applied");
}

#[tokio::test]
async fn set_datatype_negative_oracles() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let nf = set_datatype_call(&state, D_NEIGH, "NoSuchType_zzz", None)
        .await
        .unwrap_err();
    assert_eq!(nf["error"]["code"], "DATATYPE_NOT_FOUND");
    let ip = set_datatype_call(&state, "mul", "int", None)
        .await
        .unwrap_err();
    assert_eq!(ip["error"]["code"], "INVALID_PARAMS");
    let ci = set_datatype_call(&state, "mul", "undefined", None)
        .await
        .unwrap_err();
    assert_eq!(ci["error"]["code"], "INVALID_PARAMS");
}

#[tokio::test]
async fn set_datatype_does_not_delete_following_neighbour() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    // "byte" is AMBIGUOUS in this fixture (Ghidra builtin /byte vs the PDB's /fixture.pdb/std/byte) —
    // a fixture-data adjustment (not a contract change): use "undefined1", Ghidra's unambiguous
    // built-in 1-byte type, for staging the two adjacent single-byte units.
    set_datatype_call(&state, D_NEIGH, "undefined1", None)
        .await
        .expect("neigh defined");
    set_datatype_call(&state, D_NEIGH_NEXT, "undefined1", None)
        .await
        .expect("neighbour defined");
    let err = set_datatype_call(&state, D_NEIGH, "double", None)
        .await
        .unwrap_err();
    assert_eq!(err["error"]["code"], "INVALID_PARAMS");
    let neigh = set_datatype_call(&state, D_NEIGH_NEXT, "undefined1", None)
        .await
        .expect("neighbour survived");
    assert_eq!(
        neigh["status"], "already_applied",
        "neighbour must survive an overlapping apply"
    );
}

#[tokio::test]
async fn set_datatype_clear_sentinel_roundtrip() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    set_datatype_call(&state, D_NEIGH, "int", None)
        .await
        .expect("define");
    let cl = set_datatype_call(&state, D_NEIGH, "undefined", None)
        .await
        .expect("clear");
    assert_eq!(cl["status"], "cleared");
    assert_eq!(cl["datatype"], "undefined");
    assert!(cl["previous_datatype"].as_str().is_some());
    let again = set_datatype_call(&state, D_NEIGH, "undefined", None)
        .await
        .expect("noop");
    assert_eq!(again["status"], "already_applied");
}

#[tokio::test]
async fn set_datatype_expected_undefined_guard_and_offcut_reject() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    set_datatype_call(&state, D_NEIGH, "int", None)
        .await
        .expect("define");
    set_datatype_call(&state, D_NEIGH, "undefined", None)
        .await
        .expect("clear");
    let ok = set_datatype_call(&state, D_NEIGH, "int", Some("undefined"))
        .await
        .expect("guard ok on undefined");
    assert_eq!(ok["status"], "set");
    let conflict = set_datatype_call(&state, D_NEIGH, "char", Some("undefined"))
        .await
        .unwrap_err();
    assert_eq!(conflict["error"]["code"], "STATE_CONFLICT");
    assert_eq!(conflict["error"]["details"]["actual"], "int");
    let err = set_datatype_call(&state, D_NEIGH_OFFCUT, "byte", None)
        .await
        .unwrap_err();
    assert_eq!(err["error"]["code"], "INVALID_PARAMS");
}

#[tokio::test]
async fn data_refs_excludes_stack_slots() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    // inspect_function's param key is `function` (verified in GhidrustWorker.resolveFunction), not
    // `target` — the prompt's pasted snippet used `target`, which would raise INVALID_PARAMS here.
    let jp = serde_json::json!({ "function": "api_entry" });
    let v = call_when_warm(
        &state,
        "inspect_function",
        "api_entry",
        "inspect_function",
        jp,
    )
    .await
    .expect("inspect");
    let data_refs = v["data_refs"].as_array().unwrap();
    assert!(
        !data_refs.is_empty(),
        "expected api_entry to have >=1 data_ref, got {data_refs:?}"
    );
    for r in data_refs {
        let a = r["address"].as_str().unwrap();
        assert!(
            !a.starts_with("stack:") && !a.contains("register:"),
            "no local slots in data_refs: {a}"
        );
    }
}

// M2b comment read-back tidy: `comment` writes must be visible through all three read tools in one
// worker boot. "mul" target resolves (resolveTargetAddress) to its entry-point SYMBOL address, so both
// the plate and the eol comment written here land at the SAME address — the function's entry point —
// which is also what inspect_function reports as entry_point and what describe_address is queried at.
#[tokio::test]
async fn comments_are_readable_after_write() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    // 1. Write a plate comment on a function and an eol comment on its entry instruction.
    let f = "mul"; // a real fixture function
    comment_call(&state, f, "plate", "dogfood: read-back check", None)
        .await
        .expect("plate set");
    comment_call(&state, f, "eol", "entry note", None)
        .await
        .expect("eol set");

    // 2. inspect_function surfaces them in the comments[] array.
    let insp = call_when_warm(
        &state,
        "inspect_function",
        f,
        "inspect_function",
        serde_json::json!({ "function": f }),
    )
    .await
    .expect("inspect");
    let arr = insp["comments"].as_array().expect("comments array present");
    assert!(
        arr.iter()
            .any(|c| c["type"] == "plate" && c["comment"] == "dogfood: read-back check"),
        "inspect_function.comments must contain the plate comment, got {arr:?}"
    );
    assert!(
        arr.iter()
            .any(|c| c["type"] == "eol" && c["comment"] == "entry note"),
        "inspect_function.comments must contain the eol comment, got {arr:?}"
    );
    // each row has a canonical address (ram:.. / 0x.. — mirror whatever the other addresses use)
    assert!(arr[0]["address"].as_str().is_some());

    // 3. describe_address at the entry surfaces the comments object.
    let entry = insp["entry_point"]
        .as_str()
        .expect("entry_point")
        .to_string();
    let da = call_when_warm(
        &state,
        "describe_address",
        &entry,
        "describe_address",
        serde_json::json!({ "address": entry }),
    )
    .await
    .expect("describe");
    assert_eq!(da["comments"]["plate"], "dogfood: read-back check");
    assert_eq!(da["comments"]["eol"], "entry note");

    // 4. get_disassembly of the function shows the eol comment on the entry instruction's comments object.
    let dis = call_when_warm(
        &state,
        "get_disassembly",
        f,
        "get_disassembly",
        serde_json::json!({ "target": f }),
    )
    .await
    .expect("disasm");
    let ins = dis["instructions"].as_array().expect("instructions");
    assert!(
        ins.iter().any(|i| i["comments"]["eol"] == "entry note"),
        "get_disassembly must surface the eol comment in an instruction's comments object"
    );
}

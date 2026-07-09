//! In-process read/nav tool assertions (M1b): drive ServerState/execute directly against a real
//! Ghidra worker. Gated on GHIDRUST_E2E=1 + fixture env (mirrors crucible.rs/respawn.rs).

mod common;
use common::{call_when_warm, enabled, fixture_state};

#[tokio::test]
async fn find_functions_lists_known_function() {
    if !enabled() {
        eprintln!("skip: set GHIDRUST_E2E=1 + fixture env");
        return;
    }
    let state = fixture_state();
    state.start_warmup().await;
    let v = call_when_warm(
        &state,
        "find_functions",
        "",
        "find_functions",
        serde_json::json!({ "filter": "compute", "offset": 0, "limit": 100 }),
    )
    .await
    .unwrap();
    let names: Vec<&str> = v["functions"]
        .as_array()
        .unwrap()
        .iter()
        .map(|f| f["name"].as_str().unwrap())
        .collect();
    assert!(names.contains(&"compute"), "expected compute in {names:?}"); // NOT []==[]
}

#[tokio::test]
async fn resolve_symbol_finds_known_symbol() {
    if !enabled() {
        eprintln!("skip: set GHIDRUST_E2E=1 + fixture env");
        return;
    }
    let state = fixture_state();
    state.start_warmup().await;
    let v = call_when_warm(
        &state,
        "resolve_symbol",
        "api_entry",
        "resolve_symbol",
        serde_json::json!({ "name": "api_entry" }),
    )
    .await
    .unwrap();
    let candidates = v["candidates"].as_array().unwrap();
    assert!(
        !candidates.is_empty(),
        "expected >=1 candidate, got {candidates:?}"
    );
    assert!(candidates[0]["address"].as_str().is_some());
}

#[tokio::test]
async fn list_symbols_import_bucket_contains_a_win32_import() {
    if !enabled() {
        eprintln!("skip: set GHIDRUST_E2E=1 + fixture env");
        return;
    }
    let state = fixture_state();
    state.start_warmup().await;
    let v = call_when_warm(
        &state,
        "list_symbols",
        "",
        "list_symbols",
        serde_json::json!({ "kind": "import" }),
    )
    .await
    .unwrap();
    let names: Vec<&str> = v["symbols"]
        .as_array()
        .unwrap()
        .iter()
        .map(|s| s["name"].as_str().unwrap())
        .collect();
    // NOT []==[]. `printf` is NOT here: clang statically links the MSVC CRT, so printf is a DEFINED
    // function, not a DLL import. The real imports are the Win32 syscalls printf funnels into
    // (WriteFile / GetStdHandle / kernel32.*). Assert a genuine one is present.
    assert!(!names.is_empty(), "import bucket unexpectedly empty");
    assert!(
        names.contains(&"WriteFile"),
        "expected a Win32 import like WriteFile in {names:?}"
    );
}

#[tokio::test]
async fn list_symbols_export_bucket_contains_api_entry() {
    if !enabled() {
        eprintln!("skip: set GHIDRUST_E2E=1 + fixture env");
        return;
    }
    let state = fixture_state();
    state.start_warmup().await;
    let v = call_when_warm(
        &state,
        "list_symbols",
        "",
        "list_symbols",
        serde_json::json!({ "kind": "export" }),
    )
    .await
    .unwrap();
    let names: Vec<&str> = v["symbols"]
        .as_array()
        .unwrap()
        .iter()
        .map(|s| s["name"].as_str().unwrap())
        .collect();
    assert!(
        names.contains(&"api_entry"),
        "expected api_entry in {names:?}"
    ); // NOT []==[]
}

#[tokio::test]
async fn list_strings_regex_filter_matches_url_shaped_string() {
    if !enabled() {
        eprintln!("skip: set GHIDRUST_E2E=1 + fixture env");
        return;
    }
    let state = fixture_state();
    state.start_warmup().await;
    // regex:true is REQUIRED here — substring is the default and "https?://.*" is a regex pattern.
    let v = call_when_warm(
        &state,
        "list_strings",
        "",
        "list_strings",
        serde_json::json!({ "filter": "https?://.*", "regex": true }),
    )
    .await
    .unwrap();
    let values: Vec<&str> = v["strings"]
        .as_array()
        .unwrap()
        .iter()
        .map(|s| s["value"].as_str().unwrap())
        .collect();
    assert!(
        values.iter().any(|s| s.contains("example.test")),
        "expected a string containing example.test in {values:?}"
    ); // NOT []==[]
}

#[tokio::test]
async fn get_xrefs_to_add_two_includes_compute_caller() {
    if !enabled() {
        eprintln!("skip: set GHIDRUST_E2E=1 + fixture env");
        return;
    }
    let state = fixture_state();
    state.start_warmup().await;
    let v = call_when_warm(
        &state,
        "get_xrefs",
        "add_two",
        "get_xrefs",
        serde_json::json!({ "target": "add_two", "direction": "to" }),
    )
    .await
    .unwrap();
    let from_functions: Vec<&str> = v["xrefs"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|x| x["from_function"].as_str())
        .collect();
    assert!(
        from_functions.contains(&"compute"),
        "expected a ref from_function == compute in {from_functions:?}"
    ); // NOT []==[]
}

#[tokio::test]
async fn get_disassembly_add_two_has_instructions_with_mnemonics() {
    if !enabled() {
        eprintln!("skip: set GHIDRUST_E2E=1 + fixture env");
        return;
    }
    let state = fixture_state();
    state.start_warmup().await;
    let v = call_when_warm(
        &state,
        "get_disassembly",
        "add_two",
        "get_disassembly",
        serde_json::json!({ "target": "add_two" }),
    )
    .await
    .unwrap();
    let instructions = v["instructions"].as_array().unwrap();
    assert!(
        !instructions.is_empty(),
        "expected >=1 instruction, got {instructions:?}"
    ); // NOT []==[]
    let first = &instructions[0];
    assert!(first["address"].as_str().is_some());
    let mnemonic = first["mnemonic"].as_str().unwrap();
    assert!(!mnemonic.is_empty(), "expected a non-empty mnemonic");
}

#[tokio::test]
async fn read_bytes_at_add_two_entry_returns_hex_and_clamps_length() {
    if !enabled() {
        eprintln!("skip: set GHIDRUST_E2E=1 + fixture env");
        return;
    }
    let state = fixture_state();
    state.start_warmup().await;
    let resolved = call_when_warm(
        &state,
        "resolve_symbol",
        "add_two",
        "resolve_symbol",
        serde_json::json!({ "name": "add_two" }),
    )
    .await
    .unwrap();
    let address = resolved["candidates"][0]["address"]
        .as_str()
        .expect("expected a resolve_symbol candidate address")
        .to_string();

    let v = call_when_warm(
        &state,
        "read_bytes",
        &address,
        "read_bytes",
        serde_json::json!({ "address": address, "length": 4 }),
    )
    .await
    .unwrap();
    let bytes = v["bytes"].as_str().unwrap();
    assert_eq!(
        bytes.len(),
        8,
        "expected 4 bytes == 8 hex chars, got {bytes:?}"
    ); // NOT []==[]

    let v2 = call_when_warm(
        &state,
        "read_bytes",
        &address,
        "read_bytes",
        serde_json::json!({ "address": address, "length": 99999 }),
    )
    .await
    .unwrap();
    assert_eq!(v2["truncated"].as_bool(), Some(true));
    assert_eq!(v2["length"].as_u64(), Some(4096));
}

#[tokio::test]
async fn get_datatype_rect_is_struct_with_four_members() {
    if !enabled() {
        eprintln!("skip: set GHIDRUST_E2E=1 + fixture env");
        return;
    }
    let state = fixture_state();
    state.start_warmup().await;
    let v = call_when_warm(
        &state,
        "get_datatype",
        "Rect",
        "get_datatype",
        serde_json::json!({ "name": "Rect" }),
    )
    .await
    .unwrap();
    assert_eq!(v["kind"].as_str(), Some("struct"));
    let members = v["members"].as_array().unwrap();
    assert_eq!(members.len(), 4, "expected 4 members, got {members:?}");
}

#[tokio::test]
async fn get_datatype_color_is_enum_with_string_values() {
    if !enabled() {
        eprintln!("skip: set GHIDRUST_E2E=1 + fixture env");
        return;
    }
    let state = fixture_state();
    state.start_warmup().await;
    let v = call_when_warm(
        &state,
        "get_datatype",
        "Color",
        "get_datatype",
        serde_json::json!({ "name": "Color" }),
    )
    .await
    .unwrap();
    assert_eq!(v["kind"].as_str(), Some("enum"));
    let values = v["values"].as_array().unwrap();
    assert!(
        !values.is_empty(),
        "expected >=1 enum value, got {values:?}"
    ); // NOT []==[]
    for val in values {
        assert!(
            val["value"].is_string(),
            "expected a string enum value, got {val:?}"
        );
    }
}

#[tokio::test]
async fn list_segments_includes_executable_text_segment() {
    if !enabled() {
        eprintln!("skip: set GHIDRUST_E2E=1 + fixture env");
        return;
    }
    let state = fixture_state();
    state.start_warmup().await;
    let v = call_when_warm(
        &state,
        "list_segments",
        "",
        "list_segments",
        serde_json::json!({}),
    )
    .await
    .unwrap();
    let segments = v["segments"].as_array().unwrap();
    let text = segments
        .iter()
        .find(|s| s["name"].as_str() == Some(".text"));
    assert!(text.is_some(), "expected a .text segment in {segments:?}"); // NOT []==[]
    assert_eq!(text.unwrap()["executable"].as_bool(), Some(true));
}

#[tokio::test]
async fn list_data_items_filter_finds_g_rect() {
    if !enabled() {
        eprintln!("skip: set GHIDRUST_E2E=1 + fixture env");
        return;
    }
    let state = fixture_state();
    state.start_warmup().await;
    let v = call_when_warm(
        &state,
        "list_data_items",
        "",
        "list_data_items",
        serde_json::json!({ "filter": "g_rect" }),
    )
    .await
    .unwrap();
    let data = v["data"].as_array().unwrap();
    let hit = data.iter().find(|d| {
        d["name"].as_str() == Some("g_rect")
            || d["data_type"]
                .as_str()
                .map(|t| t.contains("Rect"))
                .unwrap_or(false)
    });
    assert!(
        hit.is_some(),
        "expected g_rect (or a Rect-typed item) in {data:?}"
    ); // NOT []==[]
}

#[tokio::test]
async fn inspect_function_data_refs_includes_g_banner() {
    if !enabled() {
        eprintln!("skip: set GHIDRUST_E2E=1 + fixture env");
        return;
    }
    let state = fixture_state();
    state.start_warmup().await;
    let v = call_when_warm(
        &state,
        "inspect_function",
        "api_entry",
        "inspect_function",
        serde_json::json!({ "function": "api_entry" }),
    )
    .await
    .unwrap();
    let data_refs = v["data_refs"].as_array().unwrap();
    let hit = data_refs
        .iter()
        .find(|d| d["name"].as_str() == Some("g_banner"));
    assert!(
        hit.is_some(),
        "expected a data_refs entry naming g_banner in {data_refs:?}"
    ); // NOT []==[]
}

#[tokio::test]
async fn describe_address_at_add_two_entry_names_containing_function() {
    if !enabled() {
        eprintln!("skip: set GHIDRUST_E2E=1 + fixture env");
        return;
    }
    let state = fixture_state();
    state.start_warmup().await;
    let resolved = call_when_warm(
        &state,
        "resolve_symbol",
        "add_two",
        "resolve_symbol",
        serde_json::json!({ "name": "add_two" }),
    )
    .await
    .unwrap();
    let address = resolved["candidates"][0]["address"]
        .as_str()
        .expect("expected a resolve_symbol candidate address")
        .to_string();

    let v = call_when_warm(
        &state,
        "describe_address",
        &address,
        "describe_address",
        serde_json::json!({ "address": address }),
    )
    .await
    .unwrap();
    assert_eq!(v["mapped"].as_bool(), Some(true));
    assert_eq!(
        v["containing_function"]["name"].as_str(),
        Some("add_two"),
        "expected containing_function.name == add_two, got {v:?}"
    );
}

#[tokio::test]
async fn describe_address_unmapped_returns_mapped_false_not_an_error() {
    if !enabled() {
        eprintln!("skip: set GHIDRUST_E2E=1 + fixture env");
        return;
    }
    let state = fixture_state();
    state.start_warmup().await;
    let v = call_when_warm(
        &state,
        "describe_address",
        "0xffffffff0",
        "describe_address",
        serde_json::json!({ "address": "0xffffffff0" }),
    )
    .await
    .unwrap(); // NOT an error result — describe_address is total.
    assert_eq!(
        v["mapped"].as_bool(),
        Some(false),
        "expected mapped:false for a clearly-unmapped address, got {v:?}"
    );
}

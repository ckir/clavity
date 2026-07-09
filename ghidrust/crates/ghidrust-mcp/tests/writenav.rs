mod common;
use common::*;

use ghidrust::state::ServerState;
use std::sync::Arc;

// All tests early-return unless enabled() (GHIDRUST_E2E=1). Run from PowerShell, -j1.
// Fixture functions renamed here (mul/compute) live only on the EPHEMERAL copy, so the shared read
// suite is unaffected (spec §11).

async fn rename_call(
    state: &Arc<ServerState>,
    target: &str,
    expected: &str,
    new_name: &str,
) -> Result<serde_json::Value, serde_json::Value> {
    let jp =
        serde_json::json!({ "target": target, "expected_name": expected, "new_name": new_name });
    call_when_warm(state, "rename", target, "rename", jp)
        .await
        .map_err(|e| serde_json::to_value(e).unwrap()) // typed ErrorEnvelope -> { "error": { code, message, … } }
}

async fn resolve_symbol_call(
    state: &Arc<ServerState>,
    name: &str,
) -> Result<serde_json::Value, serde_json::Value> {
    let jp = serde_json::json!({ "name": name });
    call_when_warm(state, "resolve_symbol", name, "resolve_symbol", jp)
        .await
        .map_err(|e| serde_json::to_value(e).unwrap())
}

#[tokio::test]
async fn rename_then_already_applied_is_idempotent() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    // 1) rename mul -> mul_renamed  (expected_name = current)
    let v = rename_call(&state, "mul", "mul", "mul_renamed")
        .await
        .expect("renamed");
    assert_eq!(v["status"], "renamed");
    assert_eq!(v["previous_name"], "mul");
    assert_eq!(v["durable"], true);
    // 2) re-issue targeting the CURRENT name -> already_applied (CAS semantic-noop; current == new_name,
    //    checked FIRST before expected). NOTE (spec §6 scoping, agy-reviewed): `already_applied` is only
    //    reachable via the CURRENT name (or an address). A blind respawn-retry that replays the ORIGINAL
    //    target ("mul") would instead get SYMBOL_NOT_FOUND — the old name no longer resolves. That is a
    //    benign false-negative (the edit already persisted), documented in the M2a spike note; the engine
    //    stays unchanged (Option 3 host-side address-canonicalization deferred to M2b).
    let v2 = rename_call(&state, "mul_renamed", "mul_renamed", "mul_renamed")
        .await
        .expect("noop");
    assert_eq!(v2["status"], "already_applied");
    assert!(v2.get("previous_name").is_none());
}

#[tokio::test]
async fn wrong_expected_name_is_rename_conflict() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let e = rename_call(&state, "compute", "WRONG_NAME", "compute2")
        .await
        .unwrap_err();
    assert_eq!(e["error"]["code"], "RENAME_CONFLICT");
    assert_eq!(e["error"]["details"]["actual"], "compute");
}

#[tokio::test]
async fn namespace_name_is_invalid_params() {
    if !enabled() {
        return;
    }
    let (_dir, state) = fixture_state_ephemeral();
    let e = rename_call(&state, "compute", "compute", "Foo::bar")
        .await
        .unwrap_err();
    assert_eq!(e["error"]["code"], "INVALID_PARAMS");
}

#[tokio::test]
async fn invalid_name_is_invalid_params_with_reason() {
    if !enabled() {
        return;
    }
    // spec §11.4 + the INVALID_PARAMS details.reason channel. A new name containing whitespace makes
    // Ghidra's Symbol.setName throw InvalidInputException ("Symbol name contains invalid characters"),
    // caught by withTransaction, whose exact message must land in details.reason so the LLM can self-correct.
    // NOTE (both verified live vs Ghidra 12.1.2): renaming to an EXISTING function name does NOT throw
    // (Ghidra allows duplicate global FUNCTION names, disambiguated by address); and an EMPTY name does NOT
    // throw either — only genuinely-invalid characters (space/tab/newline) do. Hence the space-containing name.
    let (_dir, state) = fixture_state_ephemeral();
    let e = rename_call(&state, "mul", "mul", "a b").await.unwrap_err();
    assert_eq!(e["error"]["code"], "INVALID_PARAMS");
    assert!(
        e["error"]["details"]["reason"].as_str().is_some(),
        "the exact Ghidra exception message must be carried in details.reason"
    );
}

#[tokio::test]
async fn durability_survives_a_hard_jvm_restart() {
    if !enabled() {
        return;
    }
    let (dir, state) = fixture_state_ephemeral();
    rename_call(&state, "mul", "mul", "mul_persisted")
        .await
        .expect("renamed");
    drop(state); // kill JVM-A so the next read cannot come from its in-memory DomainFile cache (spec §11)
                 // Boot JVM-B against the SAME on-disk ephemeral copy and confirm the name persisted to disk.
    let state2 = fixture_state_at(&dir.path);
    let sym = resolve_symbol_call(&state2, "mul_persisted")
        .await
        .expect("symbol persists on disk");
    // resolve_symbol returns { candidates: [ { name, address, … } ] } — NOT a flat name.
    assert_eq!(sym["candidates"][0]["name"], "mul_persisted");
}

#[tokio::test]
async fn clean_shutdown_releases_the_lock() {
    if !enabled() {
        return;
    }
    let (dir, state) = fixture_state_ephemeral();
    // warm it, then graceful shutdown (spec §7 S1).
    let _ = rename_call(&state, "mul", "mul", "mul_x").await;
    ghidrust::server::graceful_shutdown(&state).await;
    drop(state);
    // Bounded poll: Ghidra/OS teardown deletes the .lock asynchronously, so an instant assert races it.
    let lock = dir.path.join("fixtureproj.lock");
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(3);
    while lock.exists() && std::time::Instant::now() < deadline {
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    }
    assert!(
        !lock.exists(),
        "project .lock must be gone after clean shutdown (S1)"
    );
}

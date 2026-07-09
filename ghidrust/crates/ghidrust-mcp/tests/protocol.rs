//! Protocol-layer test (spec §8/§4.2): schema-invalid params → JSON-RPC -32602 BEFORE the handler.
//! No Ghidra worker needed — rejection happens at rmcp's deserialize boundary (server.rs doc-comment:
//! the `#[tool]` macro's generated argument parsing returns `rmcp::ErrorData::invalid_params(..)` on a
//! schema mismatch, which the framework surfaces as JSON-RPC error code -32602 automatically). Runs
//! under plain `just test` — no GHIDRUST_E2E gate, no live worker.

use ghidrust::config::ServerConfig;
use ghidrust::server::GhidrustServer;
use ghidrust::state::ServerState;
use rmcp::model::{CallToolRequestParam, ClientInfo};
use rmcp::{ClientHandler, ServiceError, ServiceExt};
use std::sync::Arc;
use std::time::Duration;

/// Minimal client handler: this test never receives a server->client request (sampling/roots/etc.), so
/// the trait's defaults suffice — mirrors rmcp's own `DummyClientHandler` in
/// `tests/test_tool_macros.rs::test_optional_i64_field_with_null_input`.
#[derive(Debug, Clone, Default)]
struct DummyClientHandler {}

impl ClientHandler for DummyClientHandler {
    fn get_info(&self) -> ClientInfo {
        ClientInfo::default()
    }
}

/// A `ServerConfig` with placeholder paths. This is safe here ONLY because the -32602 rejection happens
/// at rmcp's deserialize boundary, before `GhidrustServer::inspect_function`'s body — and therefore the
/// worker — is ever reached; the config's paths are never dereferenced. `RawConfig::resolve()` would
/// reject these placeholders (no real Ghidra install / project dir), so we bypass it and build the
/// already-validated `ServerConfig` struct directly (every field is `pub`).
fn dummy_cfg() -> ServerConfig {
    ServerConfig {
        ghidra_install_dir: std::env::temp_dir(),
        project_dir: std::env::temp_dir(),
        project_name: "unused".to_string(),
        bootstrap_program: "unused.exe".to_string(),
        bootstrap_program_path: "/unused.exe".to_string(),
        max_heap: None,
        boot_timeout: Duration::from_secs(1),
        rpc_deadline: Duration::from_secs(1),
        warming_deadline: Duration::from_secs(1),
    }
}

#[tokio::test]
async fn schema_invalid_params_yield_minus_32602() {
    // 1. Minimal ServerState driven directly (NOT via `server::serve`, which also kicks a background
    //    warmup boot). The worker never boots here: the bad-param call below is rejected pre-dispatch.
    let state = Arc::new(ServerState::new(
        dummy_cfg(),
        ghidrust::paths::versioned_script_dir(),
    ));
    let server = GhidrustServer::new(state);

    // 2. In-memory duplex transport pair (EXACT pattern used by rmcp's own
    //    `test_optional_i64_field_with_null_input` in tests/test_tool_macros.rs).
    let (server_io, client_io) = tokio::io::duplex(4096);

    // 3. Serve the server half; serve the client half. `.serve()` performs the initialize handshake on
    //    both sides automatically.
    let server_handle = tokio::spawn(async move {
        let running = server.serve(server_io).await.expect("server handshake");
        let _ = running.waiting().await;
    });
    let client = DummyClientHandler::default()
        .serve(client_io)
        .await
        .expect("client handshake");

    // 4. Call inspect_function with a schema-invalid max_c_lines (InspectArgs::max_c_lines is a u64;
    //    a string value fails schema validation before the handler body runs).
    let err = client
        .call_tool(CallToolRequestParam {
            name: "inspect_function".into(),
            arguments: Some(
                serde_json::json!({ "function": "main", "max_c_lines": "not-a-number" })
                    .as_object()
                    .unwrap()
                    .clone(),
            ),
        })
        .await
        .expect_err("schema-invalid params must be rejected as a protocol error");

    // 5. Assert the JSON-RPC code is -32602 (ErrorCode::INVALID_PARAMS) — rejected before the handler ran.
    match err {
        ServiceError::McpError(data) => assert_eq!(
            data.code.0, -32602,
            "expected INVALID_PARAMS (-32602), got code {} ({})",
            data.code.0, data.message
        ),
        other => panic!("expected ServiceError::McpError(-32602), got: {other:?}"),
    }

    client.cancel().await.expect("client cancel");
    let _ = server_handle.await;
}

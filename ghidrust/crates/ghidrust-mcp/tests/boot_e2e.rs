//! End-to-end thin-slice proof (spec §14): boot a real Ghidra worker, attach a program, decompile
//! a known function, get C back. Skipped unless GHIDRUST_E2E=1 and the fixture env vars are set.
//! (agy risk note A: if boot hangs on Windows, suspect an EDR/firewall intercept of the unsigned
//! Java process before suspecting this code.)

use ghidra_ipc::rpc::{JsonRpcVersion, RpcId, RpcRequest, RpcResponse};
use ghidra_worker_ctl::boot::boot_worker;
use ghidra_worker_ctl::config::WorkerConfig;
use std::path::PathBuf;
use std::time::Duration;

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok()
}

fn req(id: i64, method: &str, params: serde_json::Value) -> RpcRequest {
    RpcRequest {
        jsonrpc: JsonRpcVersion,
        id: RpcId::Number(id),
        method: method.to_string(),
        params: Some(params),
    }
}

#[tokio::test]
async fn boot_attach_decompile_end_to_end() {
    if env("GHIDRUST_E2E").as_deref() != Some("1") {
        eprintln!("skipping boot_e2e (set GHIDRUST_E2E=1 + fixture env vars)");
        return;
    }
    let script_dir = std::env::temp_dir().join("ghidrust-e2e-scripts");
    ghidrust::worker_asset_extract(&script_dir);

    // `GHIDRUST_FIXTURE_PROGRAM` is the program's absolute VFS path (e.g. `/add.exe`) — the form
    // `attach_program`'s `getFile()` requires ("Absolute path must begin with '/'"). But Ghidra's
    // `-process` bootstrap filter matches by *bare file name* and rejects a slash-bearing value with
    // "invalid filename specified" (verified against Ghidra 12.1.2). So derive the bare leaf name for
    // `bootstrap_program` here; the folder is already pinned by the project location.
    let program = env("GHIDRUST_FIXTURE_PROGRAM").expect("PROGRAM");
    let process_name = program.rsplit('/').next().unwrap_or(&program).to_string();

    let cfg = WorkerConfig {
        ghidra_install_dir: PathBuf::from(env("GHIDRA_INSTALL_DIR").expect("GHIDRA_INSTALL_DIR")),
        project_dir: PathBuf::from(env("GHIDRUST_FIXTURE_PROJECT_DIR").expect("PROJECT_DIR")),
        project_name: env("GHIDRUST_FIXTURE_PROJECT_NAME").expect("PROJECT_NAME"),
        bootstrap_program: process_name,
        script_dir,
        script_name: "GhidrustWorker.java".to_string(),
        max_heap: None,
        boot_timeout: Duration::from_secs(120),
    };

    let mut w = boot_worker(&cfg).await.expect("worker boots");
    assert_eq!(w.announce.protocol_version, 1);
    let attach = w
        .conn
        .request(&req(
            1,
            "attach_program",
            serde_json::json!({ "program_path": program }),
        ))
        .await
        .expect("attach ok");
    assert!(
        matches!(attach, RpcResponse::Success { .. }),
        "attach: {attach:?}"
    );

    let func = env("GHIDRUST_FIXTURE_FUNCTION").unwrap();
    let dec = w
        .conn
        .request(&req(
            2,
            "decompile_function",
            serde_json::json!({ "name": func }),
        ))
        .await
        .expect("decompile ok");
    match dec {
        RpcResponse::Success { result, .. } => {
            let c = result["c"].as_str().expect("c text");
            assert!(!c.is_empty(), "decompiled C must be non-empty");
            eprintln!("decompiled:\n{c}");
        }
        other => panic!("decompile failed: {other:?}"),
    }

    // Clean shutdown: worker exits, process is reaped by the job on drop.
    let _ = w
        .conn
        .send(&req(3, "shutdown", serde_json::json!({})))
        .await;
}

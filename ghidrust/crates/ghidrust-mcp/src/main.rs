//! ghidrust-mcp host binary. `serve` runs the real MCP stdio server (M1a); `boot-smoke` is a dev
//! subcommand that drives the worker-boot thin slice end-to-end. stdout stays reserved for MCP
//! JSON-RPC, so `serve` logs only to the per-instance file log, and `boot-smoke` logs only to stderr.

use std::path::PathBuf;
use std::time::Duration;

#[tokio::main]
async fn main() {
    let mut args = std::env::args().skip(1);
    match args.next().as_deref() {
        Some("serve") => {
            let rest: Vec<String> = args.collect(); // flags after `serve` (R3 seat-J: don't drop them)
            if let Err(code) = run_serve(rest).await {
                std::process::exit(code);
            }
        }
        Some("boot-smoke") => {
            tracing_subscriber::fmt()
                .with_writer(std::io::stderr)
                .init();
            boot_smoke().await;
        }
        Some("skill") => {
            // `args.any(..)` (not `collect()` then `iter().any(..)`) — avoids clippy::needless_collect
            // under the `-D warnings` gate. `args` is the remaining `env::args().skip(1)` iterator after
            // the subcommand was consumed by the match scrutinee; we only need a bool, so consume it here.
            if args.any(|a| a == "--emit") {
                // stdout is safe here: `skill` is a one-shot CLI utility invocation, NOT the `serve`
                // MCP JSON-RPC channel. `print!` (no trailing newline) keeps the output byte-identical
                // to the SHIPPED PLUGIN COPY - not to skill/SKILL.md, whose maintainer-facing HTML
                // comment header `emit_bytes()` strips - so `ghidrust skill --emit > SKILL.md` round-trips
                // into plugin/skills/ghidra-re-driver/SKILL.md exactly. Pinned by tests/skill_emit.rs.
                // (`ghidrust::` is the LIB crate - `main.rs` is a separate bin crate in this package,
                // exactly as the existing `ghidrust::config::` / `ghidrust::server::` uses above.)
                print!("{}", ghidrust::skill_asset::emit_bytes());
            } else {
                eprintln!(
                    "usage: ghidrust skill --emit   (writes the embedded driver skill to stdout)"
                );
                std::process::exit(2);
            }
        }
        _ => {
            eprintln!("ghidrust {}", env!("CARGO_PKG_VERSION"));
            eprintln!("usage: ghidrust serve        (env: GHIDRA_INSTALL_DIR, GHIDRUST_PROJECT_DIR, GHIDRUST_PROJECT_NAME, GHIDRUST_BOOTSTRAP_PROGRAM)");
            eprintln!(
                "       ghidrust boot-smoke   (dev; env: GHIDRA_INSTALL_DIR, GHIDRUST_FIXTURE_*)"
            );
        }
    }
}

/// Resolve config (CLI>env>file>default), init file logging, and serve. Returns Err(exit_code) on a
/// fatal config/logging failure — reported to STDERR (NOT stdout, which is the MCP channel).
async fn run_serve(cli: Vec<String>) -> Result<(), i32> {
    // Precedence CLI > env > default (§7). A CLI flag silently ignored would be a config trap
    // (plan-panel R3 seat-J), so flags DO layer over env here. File-config is deferred to M3 (spec §7
    // marks the config file optional / part of `ghidrust install`).
    let flags = parse_flags(&cli);
    let pick = |flag: &str, env: &str| flags.get(flag).cloned().or_else(|| env_or_none(env));
    let raw = ghidrust::config::RawConfig {
        ghidra_install_dir: pick("ghidra-install-dir", "GHIDRA_INSTALL_DIR"),
        project_dir: pick("project-dir", "GHIDRUST_PROJECT_DIR"),
        project_name: pick("project-name", "GHIDRUST_PROJECT_NAME"),
        bootstrap_program: pick("bootstrap-program", "GHIDRUST_BOOTSTRAP_PROGRAM"),
        bootstrap_program_path: pick("bootstrap-program-path", "GHIDRUST_BOOTSTRAP_PROGRAM_PATH"),
        max_heap: pick("max-heap", "GHIDRUST_MAX_HEAP"),
    };
    let cfg = match raw.resolve() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("ghidrust serve: configuration error: {e}");
            return Err(2);
        }
    };
    let log_path = ghidrust::paths::instance_log_path();
    let _guard = match ghidrust::logging::init_file_logging(&log_path) {
        Ok(g) => g,
        Err(e) => {
            eprintln!(
                "ghidrust serve: cannot initialize log at {}: {e}",
                log_path.display()
            );
            return Err(3);
        }
    };
    tracing::info!(?log_path, "ghidrust serve starting");
    if let Err(e) = ghidrust::server::serve(cfg).await {
        tracing::error!("serve terminated: {e}");
        return Err(1);
    }
    Ok(())
}

fn env_or_none(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|s| !s.is_empty())
}

/// Parse `--key value` and `--key=value` flags into a map (R3 seat-J). Non-flag tokens are skipped;
/// unknown flags are collected (forward-compat) — they simply don't match any `pick(...)` above.
fn parse_flags(args: &[String]) -> std::collections::HashMap<String, String> {
    let mut map = std::collections::HashMap::new();
    let mut i = 0;
    while i < args.len() {
        if let Some(rest) = args[i].strip_prefix("--") {
            if let Some((k, v)) = rest.split_once('=') {
                map.insert(k.to_string(), v.to_string());
                i += 1;
            } else if i + 1 < args.len() {
                map.insert(rest.to_string(), args[i + 1].clone());
                i += 2;
            } else {
                i += 1;
            }
        } else {
            i += 1;
        }
    }
    map
}

async fn boot_smoke() {
    let script_dir = std::env::temp_dir().join("ghidrust-smoke-scripts");
    ghidrust::worker_asset_extract(&script_dir);
    let cfg = ghidra_worker_ctl::config::WorkerConfig {
        ghidra_install_dir: PathBuf::from(env("GHIDRA_INSTALL_DIR")),
        project_dir: PathBuf::from(env("GHIDRUST_FIXTURE_PROJECT_DIR")),
        project_name: env("GHIDRUST_FIXTURE_PROJECT_NAME"),
        bootstrap_program: env("GHIDRUST_FIXTURE_PROGRAM"),
        script_dir,
        script_name: "GhidrustWorker.java".to_string(),
        max_heap: None,
        boot_timeout: Duration::from_secs(120),
    };
    let mut w = ghidra_worker_ctl::boot::boot_worker(&cfg)
        .await
        .expect("worker boots (if it hangs on Windows, check EDR/firewall on the loopback bind)");
    eprintln!("booted worker: {:?}", w.announce);
    let program = env("GHIDRUST_FIXTURE_PROGRAM");
    let func = env("GHIDRUST_FIXTURE_FUNCTION");
    let attach = w
        .conn
        .request(&mk(
            1,
            "attach_program",
            serde_json::json!({ "program_path": program }),
        ))
        .await
        .unwrap();
    eprintln!("attach: {attach:?}");
    let dec = w
        .conn
        .request(&mk(
            2,
            "decompile_function",
            serde_json::json!({ "name": func }),
        ))
        .await
        .unwrap();
    eprintln!("decompile: {dec:?}");
    let _ = w.conn.send(&mk(3, "shutdown", serde_json::json!({}))).await;
}

fn env(name: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| panic!("missing env var {name}"))
}

fn mk(id: i64, method: &str, params: serde_json::Value) -> ghidra_ipc::rpc::RpcRequest {
    ghidra_ipc::rpc::RpcRequest {
        jsonrpc: ghidra_ipc::rpc::JsonRpcVersion,
        id: ghidra_ipc::rpc::RpcId::Number(id),
        method: method.to_string(),
        params: Some(params),
    }
}

//! MCP stdio server (lands across Tasks 12-15 of the M1a "Crucible" plan).
//!
//! PINNED rmcp API (version 0.8.5) — reused by tools.rs / server.rs:
//!   - server trait: rmcp::ServerHandler
//!   - tool declaration: #[rmcp::tool_router] on the `impl` block (generates
//!     `Self::tool_router()`), #[rmcp::tool(description = "...")] on each async method,
//!     #[rmcp::tool_handler] on the `impl ServerHandler for T` block (wires
//!     call_tool/list_tools)
//!   - server info: rmcp::model::ServerInfo { instructions, capabilities, .. },
//!     rmcp::model::ServerCapabilities::builder().enable_tools().build()
//!   - tool result OK: rmcp::model::CallToolResult::success(vec![Content::text(s)])
//!   - tool result domain-err: rmcp::model::CallToolResult::error(vec![Content::text(s)])
//!     // isError:true
//!   - text content: rmcp::model::Content::text(String)
//!   - structured content: rmcp::model::CallToolResult::structured(serde_json::Value)
//!     (success, sets `structured_content` + mirrors it as text) and
//!     `CallToolResult::structured_error(Value)` for the error case; `CallToolResult` also
//!     exposes `into_typed::<T>()` to deserialize back
//!   - schema-invalid params: the #[tool] macro's generated argument parsing returns
//!     `rmcp::ErrorData::invalid_params(msg, None)` on failure, which the framework surfaces
//!     as JSON-RPC error code -32602 (ErrorCode::INVALID_PARAMS) automatically — no manual
//!     mapping needed
//!   - stdio serve entry: rmcp::ServiceExt::serve(handler, rmcp::transport::stdio()).await?,
//!     then `service.waiting().await?`
//!
//! Pinned by compiling a throwaway one-tool probe (`rmcp_probe.rs`, deleted after Task 1) against
//! the real, resolved `rmcp = "0.8.5"` — see `crates/ghidrust-mcp/Cargo.toml`.
//!
//! Additional API facts nailed down while wiring Tasks 15/16 (kept here so the pinned block stays the
//! single source of truth):
//!   - `#[tool]`-annotated methods must return a type implementing `IntoCallToolResult`. The blanket
//!     impls only cover `T: IntoContents` (Content/String/()), `Result<T, E>` where both sides are
//!     `IntoContents`, and — the one we use — `Result<CallToolResult, rmcp::ErrorData>` (verified in
//!     `rmcp-0.8.5/src/handler/server/tool.rs`). A bare `-> CallToolResult` return does NOT satisfy the
//!     trait. Every tool method here therefore returns `Result<CallToolResult, rmcp::ErrorData>` and
//!     always yields `Ok(..)` — domain failures are encoded as `CallToolResult::error(..)` inside the Ok,
//!     never as the method's own `Err`.
//!   - `#[tool_router]`/`#[tool]` attribute values are parsed by `darling`'s `FromMeta`, whose default
//!     `from_expr` only accepts `Expr::Lit` (a literal) or `Expr::Group`; a bare identifier/path (e.g. a
//!     `const DESC: &str` referenced as `description = DESC`) is `Expr::Path` and is rejected at macro
//!     expansion (`darling_core::from_meta::from_expr`, confirmed by reading the source — not just
//!     inferred). So `#[tool(description = "...")]` needs the literal text inline; the `DESC_*` consts in
//!     `tools.rs` stay the single authored copy of the wording and this file's literals are byte-for-byte
//!     copies of them (checked by the `tool_descriptions_match_tools_rs_consts` regression test below).
//!   - `schemars` is reachable as `rmcp::schemars` (re-exported when both `macros`+`server` features are
//!     on — `rmcp-0.8.5/src/lib.rs`), and `server` itself pulls in `dep:schemars`, so no direct `schemars`
//!     dependency was added to `Cargo.toml`. The `#[derive(schemars::JsonSchema)]` on the arg structs
//!     below resolves via the module-level `use rmcp::schemars;` — the derive macro's generated code
//!     references a bare `schemars::` path (see `schemars_derive-1.2.1/src/lib.rs`), which needs that
//!     name in local scope (proc-macro derive output is call-site-hygienic for paths).
//!   - `rmcp::handler::server::tool::ToolRouter<Self>` is the field type `#[tool_router]`/`#[tool_handler]`
//!     expect by default (field literally named `tool_router`, populated via `Self::tool_router()`).

use crate::config::ServerConfig;
use crate::state::ServerState;
use ghidra_ipc::error::{ErrorCode, ErrorEnvelope};
use ghidra_ipc::protocol::FunctionContext;
use rmcp::handler::server::tool::ToolRouter;
use rmcp::handler::server::wrapper::Parameters;
use rmcp::model::{CallToolResult, Content, ServerCapabilities, ServerInfo};
use rmcp::schemars;
use rmcp::ServerHandler;
use std::sync::Arc;

/// The MCP server: one attached-worker state shared with the tool methods, plus the rmcp-generated
/// tool router (spec §5).
pub struct GhidrustServer {
    pub state: Arc<ServerState>,
    tool_router: ToolRouter<Self>,
}

impl GhidrustServer {
    pub fn new(state: Arc<ServerState>) -> Self {
        Self {
            state,
            tool_router: Self::tool_router(),
        }
    }

    /// Shared Err-path handling for tools that can throw AMBIGUOUS_SYMBOL with address-bearing
    /// candidates (get_xrefs, get_disassembly): canonicalize `details.candidates[].address` using the
    /// live canonicalizer before returning the error result. Other codes pass through unchanged.
    async fn err_canon(&self, mut e: ghidra_ipc::error::ErrorEnvelope) -> CallToolResult {
        if e.error.code == ghidra_ipc::error::ErrorCode::AmbiguousSymbol {
            if let Some(d) = e.error.details.as_mut() {
                if let Some(canon) = crate::execute::current_canon(&self.state).await {
                    crate::tools::canonicalize_candidates(&canon, d);
                }
            }
        }
        err_result(&e)
    }
}

/// Serve MCP over stdio until the client disconnects. Kicks off warmup right after the transport is up
/// (spec §5) and performs graceful shutdown on exit (spec §4.6).
pub async fn serve(cfg: ServerConfig) -> std::io::Result<()> {
    let script_dir = crate::paths::versioned_script_dir();
    let state = Arc::new(ServerState::new(cfg, script_dir));
    let server = GhidrustServer::new(Arc::clone(&state));
    // Warmup: single-flight background boot (spec §5); sets Booting so the tool path returns
    // WORKER_WARMING while it boots (start_warmup is the one correct kick — never bare spawn_boot).
    state.start_warmup().await;
    // Serve over stdio (EXACT pinned call: rmcp::ServiceExt::serve(server, rmcp::transport::stdio()).await).
    let running = rmcp::ServiceExt::serve(server, rmcp::transport::stdio())
        .await
        .map_err(std::io::Error::other)?;
    // Shut down on stdio EOF OR signal (Ctrl-C / SIGTERM) — spec §4.6.
    tokio::select! {
        _ = running.waiting() => { tracing::info!("stdio closed; shutting down"); }
        _ = shutdown_signal() => { tracing::info!("signal received; shutting down"); }
    }
    graceful_shutdown(&state).await;
    Ok(())
}

async fn shutdown_signal() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        let mut term = match signal(SignalKind::terminate()) {
            Ok(s) => s,
            Err(_) => {
                let _ = tokio::signal::ctrl_c().await;
                return;
            }
        };
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {}
            _ = term.recv() => {}
        }
    }
    #[cfg(not(unix))]
    {
        let _ = tokio::signal::ctrl_c().await;
    }
}

/// Best-effort orderly worker release: a short `shutdown` RPC, WAIT bounded for exit, then drop
/// (JobObject kills the tree). `WorkerProcess.child` is a std::process::Child (blocking wait) so this
/// uses a bounded try_wait poll (R6 seat-Q) — a one-shot at exit, not a hot loop.
pub async fn graceful_shutdown(state: &Arc<ServerState>) {
    use crate::state::mk;
    let mut slot = state.worker.lock().await;
    if let crate::state::WorkerSlot::Ready(h) = &mut *slot {
        let _ = h
            .booted
            .conn
            .send(&mk("shutdown", serde_json::json!({})))
            .await;
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        loop {
            match h.booted.process.child.try_wait() {
                Ok(Some(_status)) => break,
                Ok(None) if std::time::Instant::now() < deadline => {
                    tokio::time::sleep(std::time::Duration::from_millis(100)).await;
                }
                _ => break,
            }
        }
    }
}

// Params structs derive rmcp's schema (JsonSchema + Deserialize) so schema-invalid input yields -32602
// BEFORE the handler runs (spec §4.2 protocol layer). Field types ARE the first defense.
#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct ListProgramsArgs {
    #[serde(default)]
    pub offset: u64,
    #[serde(default = "default_limit")]
    pub limit: u64,
}
fn default_limit() -> u64 {
    200
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct AttachArgs {
    pub program_path: String,
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct InspectArgs {
    pub function: String,
    #[serde(default = "default_max_c_lines")]
    pub max_c_lines: u64,
}
fn default_max_c_lines() -> u64 {
    2000
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct FindFunctionsArgs {
    #[serde(default)]
    pub filter: Option<String>,
    #[serde(default)]
    pub regex: bool,
    #[serde(default)]
    pub offset: u64,
    #[serde(default = "default_find_limit")]
    pub limit: u64,
}
fn default_find_limit() -> u64 {
    100
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct ResolveSymbolArgs {
    pub name: String,
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct ListSymbolsArgs {
    #[serde(default)]
    pub kind: Option<String>,
    #[serde(default)]
    pub filter: Option<String>,
    #[serde(default)]
    pub regex: bool,
    #[serde(default)]
    pub offset: u64,
    #[serde(default = "default_find_limit")]
    pub limit: u64,
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct ListStringsArgs {
    #[serde(default)]
    pub filter: Option<String>,
    #[serde(default)]
    pub regex: bool,
    #[serde(default)]
    pub offset: u64,
    #[serde(default = "default_list_strings_limit")]
    pub limit: u64,
}
fn default_list_strings_limit() -> u64 {
    200
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct GetXrefsArgs {
    pub target: String,
    #[serde(default = "default_direction")]
    pub direction: String,
    #[serde(default)]
    pub offset: u64,
    #[serde(default = "default_find_limit")]
    pub limit: u64,
}
fn default_direction() -> String {
    "both".to_string()
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct GetDisassemblyArgs {
    pub target: String,
    #[serde(default)]
    pub offset: u64,
    #[serde(default = "default_list_strings_limit")]
    pub limit: u64,
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct ReadBytesArgs {
    pub address: String,
    #[serde(default)]
    pub offset: i64,
    #[serde(default = "default_read_bytes_length")]
    pub length: u64,
}
fn default_read_bytes_length() -> u64 {
    256
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct GetDatatypeArgs {
    pub name: String,
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct ListSegmentsArgs {}

#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct ListDataItemsArgs {
    #[serde(default)]
    pub filter: Option<String>,
    #[serde(default)]
    pub regex: bool,
    #[serde(default)]
    pub offset: u64,
    #[serde(default = "default_list_strings_limit")]
    pub limit: u64,
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct DescribeAddressArgs {
    pub address: String,
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct RenameArgs {
    pub target: String,
    pub expected_name: String,
    pub new_name: String,
}

/// Wire enum for the `comment` channel. schemars emits a fixed `enum` in the JSON schema, so a bad value
/// is rejected with -32602 before it reaches the worker. serde `lowercase` matches the worker's strings.
#[derive(serde::Deserialize, serde::Serialize, schemars::JsonSchema, Clone, Copy)]
#[serde(rename_all = "lowercase")]
pub enum CommentChannel {
    Eol,
    Pre,
    Post,
    Plate,
    Repeatable,
}
impl CommentChannel {
    fn as_str(self) -> &'static str {
        match self {
            CommentChannel::Eol => "eol",
            CommentChannel::Pre => "pre",
            CommentChannel::Post => "post",
            CommentChannel::Plate => "plate",
            CommentChannel::Repeatable => "repeatable",
        }
    }
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct CommentArgs {
    pub target: String,
    pub comment_type: CommentChannel,
    pub new_comment: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expected_comment: Option<String>,
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct SetDatatypeArgs {
    pub target: String,
    pub datatype_name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expected_datatype: Option<String>,
}

/// One parameter of a `set_prototype` request. `name` is optional — omit (or send "") to auto-name
/// (`param_1…`); the worker coerces "" → null before `ParameterImpl`. `type_` serializes as `type`.
#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct ParamArg {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(rename = "type")]
    pub type_: String,
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct SetPrototypeArgs {
    pub target: String,
    pub return_type: String,
    pub calling_convention: String,
    /// Ordered parameter list; empty `[]` = no arguments.
    pub params: Vec<ParamArg>,
    #[serde(default)]
    pub variadic: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expected_signature: Option<String>,
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct SetLocalArgs {
    pub target: String,
    /// Storage handle ("stack:-0x18") — preferred — or the local's current name.
    pub variable: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub new_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub new_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expected_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expected_name: Option<String>,
}

/// Turn an `ErrorEnvelope` into an isError CallToolResult (spec §4.2 domain layer).
fn err_result(env: &ErrorEnvelope) -> CallToolResult {
    let text = serde_json::to_string(env).unwrap_or_else(|_| "{\"error\":\"serialize\"}".into());
    CallToolResult::error(vec![Content::text(text)])
}

/// OK result carrying a JSON value as text.
fn ok_result(v: &serde_json::Value) -> CallToolResult {
    let text = serde_json::to_string(v).unwrap_or_else(|_| "null".into());
    CallToolResult::success(vec![Content::text(text)])
}

#[rmcp::tool_router]
impl GhidrustServer {
    #[rmcp::tool(
        description = "List the programs (binaries) in the open Ghidra project as VFS paths (e.g. \"/add.exe\"). Use this first to discover a program_path to pass to attach_program. Results are paginated: pass offset and limit (default 200); the reply's `total` and `truncated` tell you if more remain. Read-only; no program needs to be attached."
    )]
    async fn list_project_programs(
        &self,
        Parameters(args): Parameters<ListProgramsArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        let params = serde_json::json!({ "offset": args.offset, "limit": args.limit });
        match crate::execute::call_worker(
            &self.state,
            "list_project_programs",
            "",
            "list_project_programs",
            params,
        )
        .await
        {
            Ok((v, _canon)) => Ok(ok_result(&v)),
            Err(e) => Ok(err_result(&e)),
        }
    }

    #[rmcp::tool(
        description = "Attach the worker to a program so inspect_function targets it. `program_path` is the absolute VFS path from list_project_programs (must begin with '/', e.g. \"/add.exe\"). One program is attached at a time; attaching switches. On boot a bootstrap program is already attached, so you can inspect_function immediately without calling this first."
    )]
    async fn attach_program(
        &self,
        Parameters(args): Parameters<AttachArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        match crate::execute::attach_program(&self.state, &args.program_path).await {
            Ok(v) => Ok(ok_result(&v)),
            Err(e) => Ok(err_result(&e)),
        }
    }

    #[rmcp::tool(
        description = "Decompile and describe one function in the attached program. `function` is EITHER a symbol name (e.g. \"main\") OR a canonical address. Addresses use the form space:offset in hex — the default code space renders as a bare 0x value like \"0x00401000\", and other spaces keep their prefix like \"EXTERNAL:0x00000001\". If a name matches multiple functions you get an AMBIGUOUS_SYMBOL error listing each candidate's address — re-call with the disambiguating address. The reply includes the decompiled C (capped from the top by max_c_lines, default 2000; c_truncated=true means the body was longer — raise max_c_lines to see more), the signature, calling convention, thunk info, and callers/callees. A caller or callee with external=true is an imported library function with NO body — identify it by name; do not pass it back to inspect_function. To reach a function you can't name, navigate callers/callees from one you can (e.g. an entry point or export)."
    )]
    async fn inspect_function(
        &self,
        Parameters(args): Parameters<InspectArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        let params =
            serde_json::json!({ "function": args.function, "max_c_lines": args.max_c_lines });
        match crate::execute::call_worker(
            &self.state,
            "inspect_function",
            &args.function,
            "inspect_function",
            params,
        )
        .await
        {
            Ok((v, canon)) => match serde_json::from_value::<FunctionContext>(v) {
                Ok(fc) => {
                    let fc = crate::tools::canonicalize_function_context(&canon, fc);
                    let v = serde_json::to_value(&fc).unwrap_or(serde_json::Value::Null);
                    Ok(ok_result(&v))
                }
                Err(e) => Ok(err_result(&ErrorEnvelope::new(
                    ErrorCode::ParseError,
                    format!("inspect_function result shape: {e}"),
                ))),
            },
            Err(e) => Ok(self.err_canon(e).await),
        }
    }

    #[rmcp::tool(
        description = "List defined functions in the attached program, optionally narrowed by a `filter` matched against the function name IN the worker (so only matches cross the wire). The filter is a substring match by default; pass regex:true for a regular-expression match (linear-time, length-capped). Returns cheap metadata per hit (name, canonical entry_point, signature, calling_convention, is_thunk, size, external) — NOT the decompiled C or call edges; use inspect_function for those. Paginated: pass offset and limit (default 100); page until has_more is false."
    )]
    async fn find_functions(
        &self,
        Parameters(args): Parameters<FindFunctionsArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        let params = serde_json::json!({
            "filter": args.filter,
            "regex": args.regex,
            "offset": args.offset,
            "limit": args.limit,
        });
        match crate::execute::call_worker(
            &self.state,
            "find_functions",
            "",
            "find_functions",
            params,
        )
        .await
        {
            Ok((mut v, canon)) => {
                crate::tools::canonicalize_functions(&canon, &mut v);
                Ok(ok_result(&v))
            }
            Err(e) => Ok(err_result(&e)),
        }
    }

    #[rmcp::tool(
        description = "Resolve a symbol NAME to its address(es); enumerates every match; 0 → SYMBOL_NOT_FOUND; call this after an AMBIGUOUS_SYMBOL from inspect_function."
    )]
    async fn resolve_symbol(
        &self,
        Parameters(args): Parameters<ResolveSymbolArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        let params = serde_json::json!({ "name": args.name });
        match crate::execute::call_worker(
            &self.state,
            "resolve_symbol",
            &args.name,
            "resolve_symbol",
            params,
        )
        .await
        {
            Ok((mut v, canon)) => {
                crate::tools::canonicalize_addr_array(&canon, &mut v, "candidates", "address");
                Ok(ok_result(&v))
            }
            Err(e) => Ok(err_result(&e)),
        }
    }

    #[rmcp::tool(
        description = "List raw symbol-table entries in the attached program, optionally narrowed by `kind` (import | export | defined | all, default all) and by a `filter` matched against the symbol name IN the worker (so only matches cross the wire). The filter is a substring match by default; pass regex:true for a regular-expression match (linear-time, length-capped). For a function's signature, calling convention, or size, use find_functions instead — this returns raw symbol-table entries, not function metadata. Paginated: pass offset and limit (default 100); page until has_more is false."
    )]
    async fn list_symbols(
        &self,
        Parameters(args): Parameters<ListSymbolsArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        let params = serde_json::json!({
            "kind": args.kind,
            "filter": args.filter,
            "regex": args.regex,
            "offset": args.offset,
            "limit": args.limit,
        });
        match crate::execute::call_worker(&self.state, "list_symbols", "", "list_symbols", params)
            .await
        {
            Ok((mut v, canon)) => {
                crate::tools::canonicalize_addr_array(&canon, &mut v, "symbols", "address");
                Ok(ok_result(&v))
            }
            Err(e) => Ok(err_result(&e)),
        }
    }

    #[rmcp::tool(
        description = "List defined string data in the attached program, optionally narrowed by a `filter` matched against the string value IN the worker (so only matches cross the wire). The filter is a substring match by default; pass regex:true for a regular-expression match (linear-time, length-capped) — e.g. to find URL-shaped strings without pulling every string across the wire, use filter:\"https?://.*\", regex:true. Paginated: pass offset and limit (default 200); page until has_more is false."
    )]
    async fn list_strings(
        &self,
        Parameters(args): Parameters<ListStringsArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        let params = serde_json::json!({
            "filter": args.filter,
            "regex": args.regex,
            "offset": args.offset,
            "limit": args.limit,
        });
        match crate::execute::call_worker(&self.state, "list_strings", "", "list_strings", params)
            .await
        {
            Ok((mut v, canon)) => {
                crate::tools::canonicalize_addr_array(&canon, &mut v, "strings", "address");
                Ok(ok_result(&v))
            }
            Err(e) => Ok(err_result(&e)),
        }
    }

    #[rmcp::tool(
        description = "List cross-references to or from `target`, a name-or-address selector (any symbol — function, data label, or string, not just functions). `direction` is one of to | from | both (default both): `to` returns references INTO target, `from` returns references OUT of target. If `target` names multiple symbols you get an AMBIGUOUS_SYMBOL error enumerating each candidate's address — re-call with the disambiguating address. Each result row has from_address, to_address, ref_type (e.g. CALL, DATA, READ), and from_function when the reference's source falls inside a defined function. Paginated: pass offset and limit (default 100); page until has_more is false."
    )]
    async fn get_xrefs(
        &self,
        Parameters(args): Parameters<GetXrefsArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        let params = serde_json::json!({
            "target": args.target,
            "direction": args.direction,
            "offset": args.offset,
            "limit": args.limit,
        });
        match crate::execute::call_worker(
            &self.state,
            "get_xrefs",
            &args.target,
            "get_xrefs",
            params,
        )
        .await
        {
            Ok((mut v, canon)) => {
                crate::tools::canonicalize_addr_array(&canon, &mut v, "xrefs", "from_address");
                crate::tools::canonicalize_addr_array(&canon, &mut v, "xrefs", "to_address");
                Ok(ok_result(&v))
            }
            Err(e) => Ok(self.err_canon(e).await),
        }
    }

    #[rmcp::tool(
        description = "List the disassembled instructions of one function in the attached program. `target` is EITHER a symbol name OR a canonical address, resolved the same way as inspect_function's `function` parameter. If `target` names multiple functions you get an AMBIGUOUS_SYMBOL error enumerating each candidate's address — re-call with the disambiguating address. Each instruction has address, bytes (lowercase hex), mnemonic, operands, and comment when an EOL comment is present. The reply's `total` is the EXACT instruction count of the function's body. Paginated: pass offset and limit (default 200); page until has_more is false."
    )]
    async fn get_disassembly(
        &self,
        Parameters(args): Parameters<GetDisassemblyArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        let params = serde_json::json!({
            "target": args.target,
            "offset": args.offset,
            "limit": args.limit,
        });
        match crate::execute::call_worker(
            &self.state,
            "get_disassembly",
            &args.target,
            "get_disassembly",
            params,
        )
        .await
        {
            Ok((mut v, canon)) => {
                crate::tools::canonicalize_addr_array(&canon, &mut v, "instructions", "address");
                Ok(ok_result(&v))
            }
            Err(e) => Ok(self.err_canon(e).await),
        }
    }

    #[rmcp::tool(
        description = "Read raw bytes at `address` in the attached program, optionally shifted by a signed DECIMAL byte `offset` (default 0) — the reply's `address` echoes address+offset, canonicalized. `length` is the number of bytes to read (default 256), clamped to a maximum of 4096; the reply's `truncated` flag is true when the clamp applied, and `length` then reflects the actual (clamped) byte count returned. `bytes` is lowercase hex. ADDRESS_NOT_FOUND if address+offset is out of bounds or the memory there is not readable."
    )]
    async fn read_bytes(
        &self,
        Parameters(args): Parameters<ReadBytesArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        let params = serde_json::json!({
            "address": args.address,
            "offset": args.offset,
            "length": args.length,
        });
        match crate::execute::call_worker(
            &self.state,
            "read_bytes",
            &args.address,
            "read_bytes",
            params,
        )
        .await
        {
            Ok((mut v, canon)) => {
                crate::tools::canonicalize_addr_field(&canon, &mut v, "address");
                Ok(ok_result(&v))
            }
            Err(e) => Ok(err_result(&e)),
        }
    }

    #[rmcp::tool(
        description = "Look up a data type DEFINITION by name (e.g. \"Rect\", \"Color\") in the attached program's data type manager — for defined data INSTANCES/globals use list_data_items instead. Returns `kind` (\"struct\"|\"union\"|\"enum\"|other) and `size`; struct/union kinds also return `members` (name, type, offset, size) and enum kinds return `values` (name, value — value is a STRING, not a number, since Ghidra enum constants can carry full 64-bit values that would lose precision as a bare JSON number). If `name` matches more than one type you get an AMBIGUOUS_DATATYPE error listing each candidate's fully-qualified path in details.candidates — re-call get_datatype with that qualified name."
    )]
    async fn get_datatype(
        &self,
        Parameters(args): Parameters<GetDatatypeArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        let params = serde_json::json!({ "name": args.name });
        match crate::execute::call_worker(
            &self.state,
            "get_datatype",
            &args.name,
            "get_datatype",
            params,
        )
        .await
        {
            Ok((v, _canon)) => Ok(ok_result(&v)),
            Err(e) => Ok(err_result(&e)),
        }
    }

    #[rmcp::tool(
        description = "List the memory map (segments/blocks) of the attached program: name, start/end (canonical addresses), size, and the readable/writable/executable/initialized flags. NOT paginated — segment counts are small. Use this to distinguish code (e.g. .text, executable=true) from data/bss segments before reading bytes or listing data items."
    )]
    async fn list_segments(
        &self,
        Parameters(_args): Parameters<ListSegmentsArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        let params = serde_json::json!({});
        match crate::execute::call_worker(&self.state, "list_segments", "", "list_segments", params)
            .await
        {
            Ok((mut v, canon)) => {
                crate::tools::canonicalize_addr_array(&canon, &mut v, "segments", "start");
                crate::tools::canonicalize_addr_array(&canon, &mut v, "segments", "end");
                Ok(ok_result(&v))
            }
            Err(e) => Ok(err_result(&e)),
        }
    }

    #[rmcp::tool(
        description = "List defined data INSTANCES/globals in the attached program (address, name when a listing label is present, data_type, value when cheaply renderable, size) — for type DEFINITIONS (struct/union/enum layouts) use get_datatype instead. Optionally narrowed by a `filter` matched against the item's label IN the worker (so only matches cross the wire). The filter is a substring match by default; pass regex:true for a regular-expression match (linear-time, length-capped). Paginated: pass offset and limit (default 200); page until has_more is false."
    )]
    async fn list_data_items(
        &self,
        Parameters(args): Parameters<ListDataItemsArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        let params = serde_json::json!({
            "filter": args.filter,
            "regex": args.regex,
            "offset": args.offset,
            "limit": args.limit,
        });
        match crate::execute::call_worker(
            &self.state,
            "list_data_items",
            "",
            "list_data_items",
            params,
        )
        .await
        {
            Ok((mut v, canon)) => {
                crate::tools::canonicalize_addr_array(&canon, &mut v, "data", "address");
                Ok(ok_result(&v))
            }
            Err(e) => Ok(err_result(&e)),
        }
    }

    #[rmcp::tool(
        description = "address → what is here (dual of resolve_symbol); total — mapped:false for an unmapped address, never an error. `address` is a canonical space:offset string. On a mapped address the reply also carries `segment` (the containing memory block's name), `is_code` (true when an instruction starts there), `containing_function` (name + entry_point, when the address falls inside a defined function), `symbol` (name + kind, the primary symbol at the address, when one exists), and `data_type` (when defined data starts there). Use this to identify an address you got from get_xrefs, read_bytes, or elsewhere without knowing in advance whether it names a function, data, or neither."
    )]
    async fn describe_address(
        &self,
        Parameters(args): Parameters<DescribeAddressArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        let params = serde_json::json!({ "address": args.address });
        match crate::execute::call_worker(
            &self.state,
            "describe_address",
            &args.address,
            "describe_address",
            params,
        )
        .await
        {
            Ok((mut v, canon)) => {
                crate::tools::canonicalize_addr_field(&canon, &mut v, "address");
                if let Some(cf) = v.get_mut("containing_function") {
                    crate::tools::canonicalize_addr_field(&canon, cf, "entry_point");
                }
                Ok(ok_result(&v))
            }
            Err(e) => Ok(err_result(&e)),
        }
    }

    #[rmcp::tool(
        description = "Rename the primary symbol (function or label) at an address. Compare-and-swap: pass expected_name = the symbol's CURRENT name; the rename applies only if it still matches (else RENAME_CONFLICT with the actual name). If it already equals new_name you get status:already_applied. The edit is saved to disk (durable). new_name must be a bare local name (no namespaces). target is an address or the current name."
    )]
    async fn rename(
        &self,
        Parameters(args): Parameters<RenameArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        let params = serde_json::json!({
            "target": args.target, "expected_name": args.expected_name, "new_name": args.new_name
        });
        match crate::execute::call_worker(&self.state, "rename", &args.target, "rename", params)
            .await
        {
            Ok((mut v, canon)) => {
                crate::tools::canonicalize_addr_field(&canon, &mut v, "address");
                Ok(ok_result(&v))
            }
            Err(e) => Ok(self.err_canon(e).await),
        }
    }

    #[rmcp::tool(
        description = "Set or clear a comment on the code unit at an address. comment_type selects the channel (eol|pre|post|plate|repeatable); plate is the function/block header. new_comment is the text; an empty string clears it. Idempotent: if the comment already equals new_comment you get status:already_applied. Pass expected_comment ONLY to guard against drift (else STATE_CONFLICT with the actual value); you do not need to echo the current comment on the normal path. The edit is saved to disk (durable). target is an address or a symbol name."
    )]
    async fn comment(
        &self,
        Parameters(args): Parameters<CommentArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        let mut params = serde_json::json!({
            "target": args.target,
            "comment_type": args.comment_type.as_str(),
            "new_comment": args.new_comment,
        });
        if let Some(exp) = &args.expected_comment {
            params["expected_comment"] = serde_json::Value::String(exp.clone());
        }
        match crate::execute::call_worker(&self.state, "comment", &args.target, "comment", params)
            .await
        {
            Ok((mut v, canon)) => {
                crate::tools::canonicalize_addr_field(&canon, &mut v, "address");
                Ok(ok_result(&v))
            }
            Err(e) => Ok(self.err_canon(e).await),
        }
    }

    #[rmcp::tool(
        description = "Apply a named data type to the DATA at an address (retype a global/data location). datatype_name is resolved by name (DATATYPE_NOT_FOUND / AMBIGUOUS_DATATYPE with candidates). The literal \"undefined\" CLEARS the defined data at the address (frees the space). Idempotent: if the location already has an equivalent type you get status:already_applied. Pass expected_datatype ONLY to guard against drift (its value is the current type's display name, or \"undefined\" to assert the location is untyped). Retyping a function PARAMETER is part of set_prototype (whole-signature); retyping a function LOCAL variable is set_local. The edit is saved to disk (durable). target is an address or a symbol name."
    )]
    async fn set_datatype(
        &self,
        Parameters(args): Parameters<SetDatatypeArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        let mut params = serde_json::json!({
            "target": args.target,
            "datatype_name": args.datatype_name,
        });
        if let Some(exp) = &args.expected_datatype {
            params["expected_datatype"] = serde_json::Value::String(exp.clone());
        }
        match crate::execute::call_worker(
            &self.state,
            "set_datatype",
            &args.target,
            "set_datatype",
            params,
        )
        .await
        {
            Ok((mut v, canon)) => {
                crate::tools::canonicalize_addr_field(&canon, &mut v, "address");
                Ok(ok_result(&v))
            }
            Err(e) => Ok(self.err_canon(e).await),
        }
    }

    #[rmcp::tool(
        description = "Replace a function's whole signature at once: return type, parameters, calling convention, and varargs. Supply the signature as STRUCTURED fields, not a C string. `target` is the function's address or current name. `return_type` and each `params[].type` are resolved by name (DATATYPE_NOT_FOUND / AMBIGUOUS_DATATYPE with candidates); a function-pointer or anonymous type you spell out (e.g. \"void (*)(int)\") is synthesized on the fly. `params` is an ordered list of {name?, type}; an empty list [] means no arguments (do NOT pass [{type:\"void\"}]). `calling_convention` must be one the program recognizes (e.g. __cdecl, __stdcall, __fastcall, or Ghidra's default/unknown) — an unknown one returns INVALID_PARAMS listing the valid set. `variadic:true` adds trailing ... . Read the current signature as these same fields from inspect_function's `prototype`, change what you need, and send the whole thing back. Idempotent: if the signature is already equivalent you get status:already_applied. Pass expected_signature (the current `signature` string from inspect_function) ONLY to guard against drift (else STATE_CONFLICT). Correcting a wrong signature is the highest-leverage edit — it re-derives the decompiled C (fixes in_<reg>/extraout_<reg> noise). A thunk, an external import, or a function with custom variable storage is rejected with INVALID_PARAMS — do not retry it. The edit is saved to disk (durable)."
    )]
    async fn set_prototype(
        &self,
        Parameters(args): Parameters<SetPrototypeArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        let mut params = serde_json::json!({
            "target": args.target,
            "return_type": args.return_type,
            "calling_convention": args.calling_convention,
            "params": args.params.iter().map(|p| {
                let mut o = serde_json::json!({ "type": p.type_ });
                if let Some(n) = &p.name {
                    o["name"] = serde_json::Value::String(n.clone());
                }
                o
            }).collect::<Vec<_>>(),
            "variadic": args.variadic,
        });
        if let Some(exp) = &args.expected_signature {
            params["expected_signature"] = serde_json::Value::String(exp.clone());
        }
        match crate::execute::call_worker(
            &self.state,
            "set_prototype",
            &args.target,
            "set_prototype",
            params,
        )
        .await
        {
            Ok((mut v, canon)) => {
                crate::tools::canonicalize_addr_field(&canon, &mut v, "address");
                Ok(ok_result(&v))
            }
            Err(e) => Ok(self.err_canon(e).await),
        }
    }

    #[rmcp::tool(
        description = "Retype and/or rename ONE local variable of a function (a decompiler body variable like uVar1 or local_18 — NOT a parameter, which is set_prototype's job, and NOT a global, which is set_datatype's). `target` is the function's address or name. `variable` is the local's STORAGE handle (e.g. \"stack:-0x18\", \"EAX:4\") as shown in inspect_function's `locals[]` — prefer it, because the decompiler silently renames unlocked locals across edits; a bare current name also works but is a weaker handle. Supply `new_type` (resolved by name, DATATYPE_NOT_FOUND / AMBIGUOUS_DATATYPE; a spelled-out fn-pointer/anon type is synthesized) and/or `new_name` (bare, no namespaces); at least one is required. Idempotent: if every field you provide already matches you get status:already_applied. Pass expected_type / expected_name ONLY to guard against drift (else STATE_CONFLICT). A too-large or overlapping type, or a name that collides with another local, returns INVALID_PARAMS with the reason — pick a smaller type or a free name. A miss on the storage/name handle returns VARIABLE_NOT_FOUND (re-read locals[]). The edit is saved to disk (durable), and re-derives the decompiled C. Read locals from inspect_function, change one, send it back."
    )]
    async fn set_local(
        &self,
        Parameters(args): Parameters<SetLocalArgs>,
    ) -> Result<CallToolResult, rmcp::ErrorData> {
        let mut params = serde_json::json!({
            "target": args.target,
            "variable": args.variable,
        });
        if let Some(t) = &args.new_type {
            params["new_type"] = serde_json::Value::String(t.clone());
        }
        if let Some(n) = &args.new_name {
            params["new_name"] = serde_json::Value::String(n.clone());
        }
        if let Some(t) = &args.expected_type {
            params["expected_type"] = serde_json::Value::String(t.clone());
        }
        if let Some(n) = &args.expected_name {
            params["expected_name"] = serde_json::Value::String(n.clone());
        }
        match crate::execute::call_worker(
            &self.state,
            "set_local",
            &args.target,
            "set_local",
            params,
        )
        .await
        {
            Ok((v, _canon)) => Ok(ok_result(&v)),
            Err(e) => Ok(self.err_canon(e).await),
        }
    }
}

#[rmcp::tool_handler]
impl ServerHandler for GhidrustServer {
    fn get_info(&self) -> ServerInfo {
        ServerInfo {
            instructions: Some(
                "ghidrust: inspect a Ghidra project's programs and decompiled functions. Start with \
                 list_project_programs to find a program_path, optionally attach_program to switch \
                 targets, then inspect_function by name or canonical address."
                    .to_string(),
            ),
            capabilities: ServerCapabilities::builder().enable_tools().build(),
            ..Default::default()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Regression guard: the literal `description = "..."` text embedded in each `#[tool]` attribute
    /// above must stay byte-for-byte identical to the reviewed `DESC_*` consts in `tools.rs` (the macro
    /// attribute can't reference a const directly — see the doc-comment note at the top of this file).
    #[test]
    fn tool_descriptions_match_tools_rs_consts() {
        let list = GhidrustServer::list_project_programs_tool_attr();
        let attach = GhidrustServer::attach_program_tool_attr();
        let inspect = GhidrustServer::inspect_function_tool_attr();
        let find = GhidrustServer::find_functions_tool_attr();
        let resolve = GhidrustServer::resolve_symbol_tool_attr();
        let list_symbols = GhidrustServer::list_symbols_tool_attr();
        let list_strings = GhidrustServer::list_strings_tool_attr();
        let get_xrefs = GhidrustServer::get_xrefs_tool_attr();
        let get_disassembly = GhidrustServer::get_disassembly_tool_attr();
        let read_bytes = GhidrustServer::read_bytes_tool_attr();
        let get_datatype = GhidrustServer::get_datatype_tool_attr();
        let list_segments = GhidrustServer::list_segments_tool_attr();
        let list_data_items = GhidrustServer::list_data_items_tool_attr();
        let describe_address = GhidrustServer::describe_address_tool_attr();
        let rename = GhidrustServer::rename_tool_attr();
        let comment = GhidrustServer::comment_tool_attr();
        let set_datatype = GhidrustServer::set_datatype_tool_attr();
        let set_prototype = GhidrustServer::set_prototype_tool_attr();
        let set_local = GhidrustServer::set_local_tool_attr();
        assert_eq!(
            list.description.as_deref(),
            Some(crate::tools::DESC_LIST_PROJECT_PROGRAMS)
        );
        assert_eq!(
            attach.description.as_deref(),
            Some(crate::tools::DESC_ATTACH_PROGRAM)
        );
        assert_eq!(
            inspect.description.as_deref(),
            Some(crate::tools::DESC_INSPECT_FUNCTION)
        );
        assert_eq!(
            find.description.as_deref(),
            Some(crate::tools::DESC_FIND_FUNCTIONS)
        );
        assert_eq!(
            resolve.description.as_deref(),
            Some(crate::tools::DESC_RESOLVE_SYMBOL)
        );
        assert_eq!(
            list_symbols.description.as_deref(),
            Some(crate::tools::DESC_LIST_SYMBOLS)
        );
        assert_eq!(
            list_strings.description.as_deref(),
            Some(crate::tools::DESC_LIST_STRINGS)
        );
        assert_eq!(
            get_xrefs.description.as_deref(),
            Some(crate::tools::DESC_GET_XREFS)
        );
        assert_eq!(
            get_disassembly.description.as_deref(),
            Some(crate::tools::DESC_GET_DISASSEMBLY)
        );
        assert_eq!(
            read_bytes.description.as_deref(),
            Some(crate::tools::DESC_READ_BYTES)
        );
        assert_eq!(
            get_datatype.description.as_deref(),
            Some(crate::tools::DESC_GET_DATATYPE)
        );
        assert_eq!(
            list_segments.description.as_deref(),
            Some(crate::tools::DESC_LIST_SEGMENTS)
        );
        assert_eq!(
            list_data_items.description.as_deref(),
            Some(crate::tools::DESC_LIST_DATA_ITEMS)
        );
        assert_eq!(
            describe_address.description.as_deref(),
            Some(crate::tools::DESC_DESCRIBE_ADDRESS)
        );
        assert_eq!(
            rename.description.as_deref(),
            Some(crate::tools::DESC_RENAME)
        );
        assert_eq!(
            comment.description.as_deref(),
            Some(crate::tools::DESC_COMMENT)
        );
        assert_eq!(
            set_datatype.description.as_deref(),
            Some(crate::tools::DESC_SET_DATATYPE)
        );
        assert_eq!(
            set_prototype.description.as_deref(),
            Some(crate::tools::DESC_SET_PROTOTYPE)
        );
        assert_eq!(
            set_local.description.as_deref(),
            Some(crate::tools::DESC_SET_LOCAL)
        );
    }

    #[test]
    fn comment_args_rejects_bad_channel_and_missing_field() {
        let bad = serde_json::json!({"target":"main","comment_type":"footnote","new_comment":"x"});
        assert!(serde_json::from_value::<CommentArgs>(bad).is_err());
        let missing = serde_json::json!({"target":"main","new_comment":"x"});
        assert!(serde_json::from_value::<CommentArgs>(missing).is_err());
        let ok = serde_json::json!({"target":"main","comment_type":"plate","new_comment":"x"});
        assert!(serde_json::from_value::<CommentArgs>(ok).is_ok());
    }

    #[test]
    fn set_datatype_args_schema() {
        let missing = serde_json::json!({"target":"main"}); // no datatype_name
        assert!(serde_json::from_value::<SetDatatypeArgs>(missing).is_err());
        let ok = serde_json::json!({"target":"0x402000","datatype_name":"int"});
        assert!(serde_json::from_value::<SetDatatypeArgs>(ok).is_ok());
        let guarded =
            serde_json::json!({"target":"g","datatype_name":"int","expected_datatype":"undefined"});
        assert!(serde_json::from_value::<SetDatatypeArgs>(guarded).is_ok());

        // set_prototype: target/return_type/calling_convention/params required; params element needs `type`.
        let missing = serde_json::json!({"target":"compute","return_type":"int","calling_convention":"__cdecl"});
        assert!(serde_json::from_value::<SetPrototypeArgs>(missing).is_err());
        let ok = serde_json::json!({"target":"compute","return_type":"int","calling_convention":"__cdecl","params":[]});
        assert!(serde_json::from_value::<SetPrototypeArgs>(ok).is_ok());
        let bad_param = serde_json::json!({"target":"c","return_type":"int","calling_convention":"__cdecl","params":[{"name":"a"}]});
        assert!(serde_json::from_value::<SetPrototypeArgs>(bad_param).is_err()); // element missing `type`
        let full = serde_json::json!({"target":"c","return_type":"int","calling_convention":"__cdecl","params":[{"name":"a","type":"int"}],"variadic":true,"expected_signature":"x"});
        assert!(serde_json::from_value::<SetPrototypeArgs>(full).is_ok());
    }

    #[test]
    fn set_local_args_schema_has_target_and_variable() {
        let schema = schemars::schema_for!(SetLocalArgs);
        let json = serde_json::to_value(&schema).unwrap();
        let props = &json["properties"];
        assert!(props.get("target").is_some());
        assert!(props.get("variable").is_some());
        assert!(props.get("new_type").is_some());
        assert!(props.get("new_name").is_some());
    }
}

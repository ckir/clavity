//! mcp-core — shared MCP server primitives (STUB / skeleton).
//!
//! Real implementation lands with the first plugin. Planned surface
//! (see docs/superpowers/plans/2026-06-17-universal-dual-plugin-restructure.md):
//!   - `Tool { name, description, input_schema }`
//!   - `Server { name, version, tools, on_call }` with `handle()` + `run()`
//!   - `log()` — writes to STDERR only (stdout must stay JSON-RPC pure).
//!
//! TODO(first-plugin): implement the stdio JSON-RPC loop + dispatch.

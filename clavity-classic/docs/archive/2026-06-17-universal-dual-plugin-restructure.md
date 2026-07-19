# Universal Dual-Plugin Restructure Implementation Plan

> ## 🗄️ ARCHIVED — superseded, kept for provenance only
>
> Design artifact from the pre-monorepo clavity-classic tree, frozen by the 2026-07-09 vendor-in
> (`63fbef8`). The work it describes has since shipped and been restructured. **Do not read it as a
> description of the current tree.** Excluded from the docs-rationalize pass by `docs/docs-spec.md`.
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the repo into a Cargo workspace that produces a minimal "universal" plugin (`scaffold`) installable by **both** `claude plugin install` and `agy plugin install` from one generated directory.

**Architecture:** A workspace with a shared `crates/mcp-core` (stdio JSON-RPC MCP server, stderr-only logging), per-plugin members under `plugins/`, and an `xtask` packager that reads a per-plugin `plugin.toml` single-source-of-truth and generates **both** hosts' manifest/mcp/hooks files into `dist/<plugin>/`. Old v1 code is preserved on a `v1` branch.

**Tech Stack:** Rust 2021, `serde` + `serde_json` (JSON), `toml` (plugin.toml), no async runtime. MCP over newline-delimited JSON-RPC 2.0 on stdio.

**Spec:** `2026-06-17-universal-dual-plugin-restructure-design.md`

**Verified external formats** (Claude docs 2026-06-17 + agy peer consults `req-djbdx6998nv0` / `req-djbeby5zp30k` / `req-djbemw4gbpoo`):
- Claude: `.claude-plugin/plugin.json` `{name,version,description}`; `.mcp.json` `mcpServers` with `${CLAUDE_PLUGIN_ROOT}` path var; `hooks/hooks.json`; `skills/<n>/SKILL.md`; no plugin `rules/`.
- agy: root `plugin.json` `{name,version,description}` (no `author`); `mcp_config.json` `mcpServers` with **relative** command (CWD=plugin-root, no path var); `hooks.json` (same shape as Claude); install **copies-not-builds**; MCP server must keep **stdout pure** (logs→stderr); Windows command needs `.exe`.
- **UNVERIFIED — confirm live in Task 9:** agy's session-start hook **event name** (assumed `SessionStart`); that `claude plugin install <local dir>` accepts a local path; mutual file-tolerance (each CLI ignores the other's sibling files).

---

## File Structure

| Path | Responsibility |
|---|---|
| `Cargo.toml` | workspace root: `members = ["crates/*", "plugins/*", "xtask"]` |
| `.gitignore` | ignore `/target`, `/dist` |
| `crates/mcp-core/` | shared lib: JSON-RPC dispatch, `Server`, `Tool`, stderr `log()` |
| `plugins/scaffold/` | the scaffold plugin: bin crate + `plugin.toml` + shared `skills/ rules/ hooks/` |
| `xtask/` | packager: parse `plugin.toml`, generate both hosts' files, assemble `dist/` |
| `docs/plugin-formats.md` | canonical verified-format reference the generators target |
| `dist/` | generated, gitignored — installable payload |

---

## Task 1: Cut the v1 branch and convert main to a workspace skeleton

**Files:**
- Create: `Cargo.toml` (workspace root, replacing the v1 binary manifest), `.gitignore`
- Delete: `src/`, `tests/`, `agy_skills/` (preserved on the `v1` branch)

- [ ] **Step 1: Preserve v1 on a branch and push it**

```bash
git switch -c v1
git push -u origin v1
git switch main
```

Expected: branch `v1` exists locally and on the remote, pointing at the current `main` tip. You are back on `main`.

- [ ] **Step 2: Replace the root `Cargo.toml` with a workspace manifest**

Overwrite `Cargo.toml` with exactly:

```toml
[workspace]
resolver = "2"
members = ["crates/*", "plugins/*", "xtask"]

[workspace.package]
edition = "2021"
license = "MIT"
repository = "https://github.com/ckir/clavity"

[workspace.dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
toml = "0.8"
```

- [ ] **Step 3: Write `.gitignore`**

Overwrite `.gitignore` with exactly:

```gitignore
/target
/dist
```

- [ ] **Step 4: Remove the v1 source (it lives on the `v1` branch)**

```bash
git rm -r src tests agy_skills
```

Expected: those paths are staged for deletion. (`docs/`, `.github/`, `LICENSE`, `CLAUDE.md`, `CONTRIBUTING.md`, `README.md`, `ROADMAP.md` are kept.)

- [ ] **Step 5: Verify the empty workspace resolves**

Run: `cargo metadata --no-deps --format-version 1 > NUL`
Expected: exits 0 (no members yet is fine; a `members` glob matching nothing is allowed).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: cut v1 branch; convert main to a Cargo workspace skeleton"
```

---

## Task 2: `crates/mcp-core` — JSON-RPC dispatch (TDD)

**Files:**
- Create: `crates/mcp-core/Cargo.toml`, `crates/mcp-core/src/lib.rs`

- [ ] **Step 1: Create the crate manifest**

`crates/mcp-core/Cargo.toml`:

```toml
[package]
name = "mcp-core"
version = "0.1.0"
edition.workspace = true
license.workspace = true

[dependencies]
serde_json = { workspace = true }
```

- [ ] **Step 2: Write the failing tests**

Create `crates/mcp-core/src/lib.rs` with ONLY the tests first (the impl comes in Step 4). Paste:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{json, Value};

    fn test_server() -> Server<impl Fn(&str, &Value) -> Result<String, String>> {
        Server {
            name: "test".to_string(),
            version: "9.9.9".to_string(),
            tools: vec![Tool {
                name: "echo".to_string(),
                description: "echoes text".to_string(),
                input_schema: json!({ "type": "object", "properties": {} }),
            }],
            on_call: |name, args| match name {
                "echo" => Ok(args.get("text").and_then(|t| t.as_str()).unwrap_or("").to_string()),
                other => Err(format!("unknown tool: {other}")),
            },
        }
    }

    fn parse(resp: &str) -> Value {
        serde_json::from_str(resp).expect("response is valid JSON")
    }

    #[test]
    fn initialize_echoes_protocol_and_server_info() {
        let s = test_server();
        let resp = s.handle(r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#).unwrap();
        let v = parse(&resp);
        assert_eq!(v["id"], json!(1));
        assert_eq!(v["result"]["protocolVersion"], json!("2025-06-18"));
        assert_eq!(v["result"]["serverInfo"]["name"], json!("test"));
        assert_eq!(v["result"]["capabilities"]["tools"], json!({}));
    }

    #[test]
    fn tools_list_returns_declared_tools() {
        let s = test_server();
        let resp = s.handle(r#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#).unwrap();
        let v = parse(&resp);
        assert_eq!(v["result"]["tools"][0]["name"], json!("echo"));
    }

    #[test]
    fn tools_call_returns_text_content() {
        let s = test_server();
        let resp = s.handle(r#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{"text":"hi"}}}"#).unwrap();
        let v = parse(&resp);
        assert_eq!(v["result"]["content"][0]["type"], json!("text"));
        assert_eq!(v["result"]["content"][0]["text"], json!("hi"));
    }

    #[test]
    fn unknown_method_is_error_minus_32601() {
        let s = test_server();
        let resp = s.handle(r#"{"jsonrpc":"2.0","id":4,"method":"nope"}"#).unwrap();
        let v = parse(&resp);
        assert_eq!(v["error"]["code"], json!(-32601));
    }

    #[test]
    fn notification_without_id_yields_no_response() {
        let s = test_server();
        assert!(s.handle(r#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#).is_none());
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cargo test -p mcp-core`
Expected: FAIL — `cannot find type Server`/`Tool` (impl not written yet).

- [ ] **Step 4: Write the minimal implementation**

Prepend to `crates/mcp-core/src/lib.rs` (above the `#[cfg(test)] mod tests`):

```rust
use serde_json::{json, Value};

/// Write a diagnostic line to **stderr**. NEVER write diagnostics to stdout:
/// stdout carries JSON-RPC and any stray byte breaks the MCP transport.
pub fn log(msg: &str) {
    eprintln!("[mcp] {msg}");
}

pub struct Tool {
    pub name: String,
    pub description: String,
    pub input_schema: Value,
}

pub struct Server<F>
where
    F: Fn(&str, &Value) -> Result<String, String>,
{
    pub name: String,
    pub version: String,
    pub tools: Vec<Tool>,
    pub on_call: F,
}

impl<F> Server<F>
where
    F: Fn(&str, &Value) -> Result<String, String>,
{
    /// Handle one JSON-RPC message line. `Some(json)` for requests,
    /// `None` for notifications (no `id`) or unparseable input.
    pub fn handle(&self, line: &str) -> Option<String> {
        let msg: Value = match serde_json::from_str(line) {
            Ok(v) => v,
            Err(e) => {
                log(&format!("parse error: {e}"));
                return None;
            }
        };
        let id = msg.get("id").cloned()?; // notifications have no id -> None
        let method = msg.get("method").and_then(|m| m.as_str()).unwrap_or("");
        let params = msg.get("params").cloned().unwrap_or(Value::Null);
        match method {
            "initialize" => Some(success(id, self.initialize(&params))),
            "tools/list" => Some(success(id, self.tools_list())),
            "tools/call" => Some(self.tools_call(id, &params)),
            other => Some(error(id, -32601, &format!("method not found: {other}"))),
        }
    }

    fn initialize(&self, params: &Value) -> Value {
        let protocol = params
            .get("protocolVersion")
            .and_then(|v| v.as_str())
            .unwrap_or("2025-06-18");
        json!({
            "protocolVersion": protocol,
            "capabilities": { "tools": {} },
            "serverInfo": { "name": self.name, "version": self.version }
        })
    }

    fn tools_list(&self) -> Value {
        let tools: Vec<Value> = self
            .tools
            .iter()
            .map(|t| json!({ "name": t.name, "description": t.description, "inputSchema": t.input_schema }))
            .collect();
        json!({ "tools": tools })
    }

    fn tools_call(&self, id: Value, params: &Value) -> String {
        let name = params.get("name").and_then(|n| n.as_str()).unwrap_or("");
        let args = params.get("arguments").cloned().unwrap_or(Value::Null);
        match (self.on_call)(name, &args) {
            Ok(text) => success(id, json!({ "content": [ { "type": "text", "text": text } ] })),
            Err(e) => error(id, -32603, &e),
        }
    }

    /// Read newline-delimited JSON-RPC from `reader`; write responses to `writer`.
    pub fn run<R: std::io::BufRead, W: std::io::Write>(
        &self,
        mut reader: R,
        mut writer: W,
    ) -> std::io::Result<()> {
        let mut line = String::new();
        loop {
            line.clear();
            if reader.read_line(&mut line)? == 0 {
                return Ok(()); // EOF
            }
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            if let Some(resp) = self.handle(trimmed) {
                writeln!(writer, "{resp}")?;
                writer.flush()?;
            }
        }
    }
}

pub fn success(id: Value, result: Value) -> String {
    json!({ "jsonrpc": "2.0", "id": id, "result": result }).to_string()
}

pub fn error(id: Value, code: i64, message: &str) -> String {
    json!({ "jsonrpc": "2.0", "id": id, "error": { "code": code, "message": message } }).to_string()
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cargo test -p mcp-core`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add crates/mcp-core
git commit -m "feat(mcp-core): stdio JSON-RPC MCP server with stderr-only logging"
```

---

## Task 3: `crates/mcp-core` — stdout-purity run-loop test (TDD)

**Files:**
- Test: `crates/mcp-core/src/lib.rs` (extend the `tests` module)

- [ ] **Step 1: Write the failing test**

Add inside `mod tests` (before the closing brace):

```rust
    #[test]
    fn run_loop_emits_only_jsonrpc_to_writer() {
        use std::io::BufReader;
        let s = test_server();
        let input = b"{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/list\"}\n";
        let mut out: Vec<u8> = Vec::new();
        s.run(BufReader::new(&input[..]), &mut out).unwrap();
        let text = String::from_utf8(out).unwrap();
        // The notification produced NO output line; only the request did.
        let lines: Vec<&str> = text.lines().collect();
        assert_eq!(lines.len(), 1, "exactly one response line expected, got: {text:?}");
        let v: Value = serde_json::from_str(lines[0]).expect("each stdout line must be valid JSON-RPC");
        assert_eq!(v["id"], json!(7));
    }
```

- [ ] **Step 2: Run to verify it passes** (the `run` impl already exists from Task 2)

Run: `cargo test -p mcp-core run_loop_emits_only_jsonrpc_to_writer`
Expected: PASS. (If it fails, the loop is writing non-JSON to the writer — fix the loop, not the test.)

- [ ] **Step 3: Commit**

```bash
git add crates/mcp-core
git commit -m "test(mcp-core): assert run-loop keeps stdout JSON-RPC-pure"
```

---

## Task 4: `plugins/scaffold` — the hello MCP server bin crate

**Files:**
- Create: `plugins/scaffold/Cargo.toml`, `plugins/scaffold/src/main.rs`

- [ ] **Step 1: Create the bin crate manifest**

`plugins/scaffold/Cargo.toml`:

```toml
[package]
name = "scaffold-server"
version = "0.1.0"
edition.workspace = true
license.workspace = true

[[bin]]
name = "scaffold-server"
path = "src/main.rs"

[dependencies]
mcp-core = { path = "../../crates/mcp-core" }
serde_json = { workspace = true }
```

- [ ] **Step 2: Write the server entrypoint**

`plugins/scaffold/src/main.rs`:

```rust
use mcp_core::{Server, Tool};
use serde_json::json;

fn main() -> std::io::Result<()> {
    let server = Server {
        name: "scaffold".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        tools: vec![Tool {
            name: "hello".to_string(),
            description: "Returns a greeting, proving the dual-compat plugin's MCP server works."
                .to_string(),
            input_schema: json!({ "type": "object", "properties": {} }),
        }],
        on_call: |name, _args| match name {
            "hello" => Ok("hello from the scaffold universal plugin".to_string()),
            other => Err(format!("unknown tool: {other}")),
        },
    };
    mcp_core::log("scaffold-server starting");
    let stdin = std::io::stdin();
    let stdout = std::io::stdout();
    server.run(stdin.lock(), stdout.lock())
}
```

- [ ] **Step 3: Build and smoke-test the server over a pipe**

Run (PowerShell):

```pwsh
cargo build -p scaffold-server
'{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | ./target/debug/scaffold-server.exe
```

Expected: one line of stdout JSON containing `"name":"hello"`; the `[mcp] scaffold-server starting` line appears on **stderr**, not interleaved into the JSON line.

- [ ] **Step 4: Commit**

```bash
git add plugins/scaffold/Cargo.toml plugins/scaffold/src
git commit -m "feat(scaffold): hello MCP server built on mcp-core"
```

---

## Task 5: `plugins/scaffold` — payload assets + `plugin.toml` SSOT

**Files:**
- Create: `plugins/scaffold/plugin.toml`, `plugins/scaffold/skills/hello/SKILL.md`, `plugins/scaffold/rules/no-secrets.md`, `plugins/scaffold/hooks/on-start.ps1`

- [ ] **Step 1: Write the single-source-of-truth `plugin.toml`**

`plugins/scaffold/plugin.toml`:

```toml
[plugin]
name = "scaffold"
version = "0.1.0"
description = "Dual-compat scaffold plugin: installs in both Claude Code and Antigravity."

[mcp]
server_name = "scaffold"
crate = "scaffold-server"
binary = "scaffold-server.exe"

[[hook]]
# Host-neutral lifecycle event; xtask maps it per host (see agy event-name note in Task 6).
event = "SessionStart"
script = "hooks/on-start.ps1"

[[rule]]
file = "rules/no-secrets.md"
```

- [ ] **Step 2: Write the shared skill**

`plugins/scaffold/skills/hello/SKILL.md`:

```markdown
---
name: scaffold-hello
description: Use to confirm the scaffold universal plugin is installed; calls the hello MCP tool.
---

# Scaffold Hello

This skill confirms the dual-compatible scaffold plugin is active. When invoked,
call the `hello` tool exposed by the `scaffold` MCP server and report its reply.
```

- [ ] **Step 3: Write the rule**

`plugins/scaffold/rules/no-secrets.md`:

```markdown
# Rule: no secrets in output

Never print credentials, tokens, or private keys to stdout or into committed files.
```

- [ ] **Step 4: Write the hook script** (writes an observable marker + a stdout line)

`plugins/scaffold/hooks/on-start.ps1`:

```powershell
$marker = Join-Path $env:TEMP "scaffold-hook-fired.txt"
Set-Content -Path $marker -Value (Get-Date -Format o)
Write-Output "scaffold plugin hook fired"
```

- [ ] **Step 5: Commit**

```bash
git add plugins/scaffold/plugin.toml plugins/scaffold/skills plugins/scaffold/rules plugins/scaffold/hooks
git commit -m "feat(scaffold): plugin.toml SSOT + skill, rule, and hook payload"
```

---

## Task 6: `xtask` — plugin.toml model + file generators (TDD)

**Files:**
- Create: `xtask/Cargo.toml`, `xtask/src/main.rs`, `xtask/src/gen.rs`

- [ ] **Step 1: Create the xtask manifest**

`xtask/Cargo.toml`:

```toml
[package]
name = "xtask"
version = "0.1.0"
edition.workspace = true
license.workspace = true

[dependencies]
serde = { workspace = true }
serde_json = { workspace = true }
toml = { workspace = true }
```

- [ ] **Step 2: Write the failing generator tests**

`xtask/src/gen.rs`:

```rust
use serde::Deserialize;
use serde_json::{json, Value};

#[derive(Debug, Deserialize)]
pub struct Manifest {
    pub plugin: PluginMeta,
    pub mcp: Option<McpDef>,
    #[serde(default)]
    pub hook: Vec<HookDef>,
    #[serde(default)]
    pub rule: Vec<RuleDef>,
}

#[derive(Debug, Deserialize)]
pub struct PluginMeta {
    pub name: String,
    pub version: String,
    pub description: String,
}

#[derive(Debug, Deserialize)]
pub struct McpDef {
    pub server_name: String,
    #[serde(rename = "crate")]
    pub crate_name: String,
    pub binary: String,
}

#[derive(Debug, Deserialize)]
pub struct HookDef {
    pub event: String,
    pub script: String,
}

#[derive(Debug, Deserialize)]
pub struct RuleDef {
    pub file: String,
}

/// agy's session-start hook event name is UNVERIFIED (agy consult req-djbemw4gbpoo).
/// Assumed equal to Claude's until confirmed live (Task 9). Change here if it differs.
pub fn agy_event(claude_event: &str) -> String {
    claude_event.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> Manifest {
        toml::from_str(
            r#"
[plugin]
name = "scaffold"
version = "0.1.0"
description = "Dual-compat scaffold plugin."
[mcp]
server_name = "scaffold"
crate = "scaffold-server"
binary = "scaffold-server.exe"
[[hook]]
event = "SessionStart"
script = "hooks/on-start.ps1"
[[rule]]
file = "rules/no-secrets.md"
"#,
        )
        .unwrap()
    }

    fn p(s: &str) -> Value {
        serde_json::from_str(s).unwrap()
    }

    #[test]
    fn manifests_are_name_version_description_only() {
        let m = fixture();
        let expected = json!({ "name": "scaffold", "version": "0.1.0", "description": "Dual-compat scaffold plugin." });
        assert_eq!(p(&claude_manifest(&m)), expected);
        assert_eq!(p(&agy_manifest(&m)), expected);
    }

    #[test]
    fn claude_mcp_uses_plugin_root_var() {
        let m = fixture();
        let v = p(&claude_mcp(&m));
        assert_eq!(
            v["mcpServers"]["scaffold"]["command"],
            json!("${CLAUDE_PLUGIN_ROOT}/bin/scaffold-server.exe")
        );
    }

    #[test]
    fn agy_mcp_uses_relative_path() {
        let m = fixture();
        let v = p(&agy_mcp(&m));
        assert_eq!(
            v["mcpServers"]["scaffold"]["command"],
            json!("./bin/scaffold-server.exe")
        );
    }

    #[test]
    fn claude_hooks_wrap_event_with_plugin_root_command() {
        let m = fixture();
        let v = p(&claude_hooks(&m));
        let cmd = v["hooks"]["SessionStart"][0]["hooks"][0]["command"].as_str().unwrap();
        assert!(cmd.contains("${CLAUDE_PLUGIN_ROOT}"), "got: {cmd}");
        assert!(cmd.contains("hooks/on-start.ps1"), "got: {cmd}");
    }

    #[test]
    fn agy_hooks_use_relative_command_and_matcher() {
        let m = fixture();
        let v = p(&agy_hooks(&m));
        let entry = &v["hooks"]["SessionStart"][0];
        assert_eq!(entry["matcher"], json!(".*"));
        let cmd = entry["hooks"][0]["command"].as_str().unwrap();
        assert!(cmd.starts_with("pwsh"), "got: {cmd}");
        assert!(cmd.contains("./hooks/on-start.ps1"), "got: {cmd}");
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `cargo test -p xtask`
Expected: FAIL — `cannot find function claude_manifest` etc.

- [ ] **Step 4: Implement the generators**

Add to `xtask/src/gen.rs` (above the `#[cfg(test)]` module):

```rust
fn pretty(v: Value) -> String {
    serde_json::to_string_pretty(&v).unwrap()
}

pub fn claude_manifest(m: &Manifest) -> String {
    pretty(json!({ "name": m.plugin.name, "version": m.plugin.version, "description": m.plugin.description }))
}

pub fn agy_manifest(m: &Manifest) -> String {
    // Same required fields as Claude (agy: name/version/description; no `author`).
    claude_manifest(m)
}

fn mcp_json(server_name: &str, command: String) -> String {
    let mut servers = serde_json::Map::new();
    servers.insert(server_name.to_string(), json!({ "command": command, "args": [] }));
    pretty(json!({ "mcpServers": servers }))
}

pub fn claude_mcp(m: &Manifest) -> String {
    let mcp = m.mcp.as_ref().expect("claude_mcp called on a plugin with no [mcp]");
    mcp_json(&mcp.server_name, format!("${{CLAUDE_PLUGIN_ROOT}}/bin/{}", mcp.binary))
}

pub fn agy_mcp(m: &Manifest) -> String {
    let mcp = m.mcp.as_ref().expect("agy_mcp called on a plugin with no [mcp]");
    mcp_json(&mcp.server_name, format!("./bin/{}", mcp.binary))
}

pub fn claude_hooks(m: &Manifest) -> String {
    let mut events = serde_json::Map::new();
    for h in &m.hook {
        let cmd = format!("pwsh -NoProfile -File \"${{CLAUDE_PLUGIN_ROOT}}/{}\"", h.script);
        events.insert(
            h.event.clone(),
            json!([ { "hooks": [ { "type": "command", "command": cmd } ] } ]),
        );
    }
    pretty(json!({ "hooks": events }))
}

pub fn agy_hooks(m: &Manifest) -> String {
    let mut events = serde_json::Map::new();
    for h in &m.hook {
        let cmd = format!("pwsh -NoProfile -File \"./{}\"", h.script);
        events.insert(
            agy_event(&h.event),
            json!([ { "matcher": ".*", "hooks": [ { "type": "command", "command": cmd, "async": false } ] } ]),
        );
    }
    pretty(json!({ "hooks": events }))
}
```

- [ ] **Step 5: Run to verify pass**

Run: `cargo test -p xtask`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add xtask/Cargo.toml xtask/src/gen.rs
git commit -m "feat(xtask): plugin.toml model + dual-host file generators"
```

---

## Task 7: `xtask` — rule mirror, payload copy, and the packager (TDD)

**Files:**
- Create: `xtask/src/pack.rs`
- Modify: `xtask/src/gen.rs` (add `mirror_rule_skill`)

- [ ] **Step 1: Write the failing rule-mirror test**

Add to `xtask/src/gen.rs` inside `mod tests`:

```rust
    #[test]
    fn rule_mirror_emits_named_skill_with_body() {
        let skill = mirror_rule_skill("no-secrets", "# Rule\n\nNever print secrets.");
        assert!(skill.starts_with("---\nname: rule-no-secrets\n"), "got: {skill}");
        assert!(skill.contains("Never print secrets."), "got: {skill}");
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cargo test -p xtask rule_mirror_emits_named_skill_with_body`
Expected: FAIL — `cannot find function mirror_rule_skill`.

- [ ] **Step 3: Implement `mirror_rule_skill`**

Add to `xtask/src/gen.rs` (above the test module):

```rust
/// Render a rule's markdown as a Claude-side skill (Claude has no plugin `rules/`).
pub fn mirror_rule_skill(stem: &str, rule_body: &str) -> String {
    let first_line = rule_body.lines().find(|l| !l.trim().is_empty()).unwrap_or("Project rule");
    let desc = first_line.trim_start_matches('#').trim();
    format!(
        "---\nname: rule-{stem}\ndescription: \"Project rule (mirrored): {desc}\"\n---\n\n{rule_body}\n"
    )
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cargo test -p xtask rule_mirror_emits_named_skill_with_body`
Expected: PASS.

- [ ] **Step 5: Write the packager**

`xtask/src/pack.rs`:

```rust
use crate::gen::*;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Clone, Copy, PartialEq)]
pub enum Mode {
    Universal,
    Split,
}

/// Build the plugin's binary (if any), generate both hosts' files, and assemble dist/.
pub fn package(plugin_dir: &Path, dist_root: &Path, mode: Mode) -> std::io::Result<Vec<PathBuf>> {
    let toml_text = fs::read_to_string(plugin_dir.join("plugin.toml"))?;
    let m: Manifest = toml::from_str(&toml_text).expect("plugin.toml parses");

    // 1. Build the binary (agy/Claude install do NOT build — ship pre-compiled).
    let built_binary = if let Some(mcp) = &m.mcp {
        let status = Command::new("cargo")
            .args(["build", "--release", "-p", &mcp.crate_name])
            .status()?;
        assert!(status.success(), "cargo build failed for {}", mcp.crate_name);
        Some(PathBuf::from("target/release").join(&mcp.binary))
    } else {
        None
    };

    let mut written = Vec::new();
    let targets: Vec<(PathBuf, Option<Host>)> = match mode {
        Mode::Universal => vec![(dist_root.join(&m.plugin.name), None)],
        Mode::Split => vec![
            (dist_root.join(format!("{}-claude", m.plugin.name)), Some(Host::Claude)),
            (dist_root.join(format!("{}-agy", m.plugin.name)), Some(Host::Agy)),
        ],
    };

    for (out, host) in targets {
        fs::create_dir_all(&out)?;
        let claude = host != Some(Host::Agy); // universal & claude-split get Claude files
        let agy = host != Some(Host::Claude); // universal & agy-split get agy files

        if claude {
            write_file(&out.join(".claude-plugin/plugin.json"), &claude_manifest(&m), &mut written)?;
            if m.mcp.is_some() {
                write_file(&out.join(".mcp.json"), &claude_mcp(&m), &mut written)?;
            }
            if !m.hook.is_empty() {
                write_file(&out.join("hooks/hooks.json"), &claude_hooks(&m), &mut written)?;
            }
        }
        if agy {
            write_file(&out.join("plugin.json"), &agy_manifest(&m), &mut written)?;
            if m.mcp.is_some() {
                write_file(&out.join("mcp_config.json"), &agy_mcp(&m), &mut written)?;
            }
            if !m.hook.is_empty() {
                write_file(&out.join("hooks.json"), &agy_hooks(&m), &mut written)?;
            }
        }

        // Shared payload: skills, hook scripts, binary.
        copy_dir(&plugin_dir.join("skills"), &out.join("skills"), &mut written)?;
        copy_dir(&plugin_dir.join("hooks"), &out.join("hooks"), &mut written)?;
        if let (Some(mcp), Some(bin)) = (&m.mcp, &built_binary) {
            let dest = out.join("bin").join(&mcp.binary);
            fs::create_dir_all(dest.parent().unwrap())?;
            fs::copy(bin, &dest)?;
            written.push(dest);
        }

        // Rules: native dir for agy-split; mirrored skill where Claude is served
        // (universal ships ONLY the mirror, per spec §5, to avoid agy double-load).
        for r in &m.rule {
            let body = fs::read_to_string(plugin_dir.join(&r.file)).unwrap_or_default();
            let stem = Path::new(&r.file).file_stem().unwrap().to_string_lossy().to_string();
            let ship_native = host == Some(Host::Agy);
            if ship_native {
                write_file(&out.join(&r.file), &body, &mut written)?;
            } else {
                let skill = mirror_rule_skill(&stem, &body);
                write_file(&out.join(format!("skills/rule-{stem}/SKILL.md")), &skill, &mut written)?;
            }
        }
    }
    Ok(written)
}

#[derive(PartialEq, Clone, Copy)]
enum Host {
    Claude,
    Agy,
}

fn write_file(path: &Path, contents: &str, written: &mut Vec<PathBuf>) -> std::io::Result<()> {
    fs::create_dir_all(path.parent().unwrap())?;
    fs::write(path, contents)?;
    written.push(path.to_path_buf());
    Ok(())
}

fn copy_dir(src: &Path, dst: &Path, written: &mut Vec<PathBuf>) -> std::io::Result<()> {
    if !src.exists() {
        return Ok(());
    }
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let target = dst.join(entry.file_name());
        if entry.file_type()?.is_dir() {
            copy_dir(&entry.path(), &target, written)?;
        } else {
            fs::create_dir_all(target.parent().unwrap())?;
            fs::copy(entry.path(), &target)?;
            written.push(target);
        }
    }
    Ok(())
}
```

- [ ] **Step 6: Wire up `main.rs` with a package-tree test**

`xtask/src/main.rs`:

```rust
mod gen;
mod pack;

use pack::Mode;
use std::path::Path;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 || args[1] != "package" {
        eprintln!("usage: cargo xtask package <plugin> [--mode universal|split]");
        std::process::exit(2);
    }
    let plugin = &args[2];
    let mode = match args.iter().position(|a| a == "--mode").and_then(|i| args.get(i + 1)) {
        Some(s) if s == "split" => Mode::Split,
        _ => Mode::Universal,
    };
    let plugin_dir = Path::new("plugins").join(plugin);
    let written = pack::package(&plugin_dir, Path::new("dist"), mode).expect("package failed");
    eprintln!("packaged {plugin}: {} files into dist/", written.len());
}

#[cfg(test)]
mod tests {
    use super::pack::{package, Mode};
    use std::path::Path;

    #[test]
    fn universal_package_emits_both_host_manifests() {
        let tmp = std::env::temp_dir().join(format!("xtask-test-{}", std::process::id()));
        let plugin_dir = tmp.join("plugins/demo");
        std::fs::create_dir_all(plugin_dir.join("skills/x")).unwrap();
        std::fs::write(plugin_dir.join("skills/x/SKILL.md"), "---\nname: x\ndescription: x\n---\n").unwrap();
        std::fs::write(
            plugin_dir.join("plugin.toml"),
            "[plugin]\nname=\"demo\"\nversion=\"0.1.0\"\ndescription=\"d\"\n",
        )
        .unwrap();
        let dist = tmp.join("dist");
        package(&plugin_dir, &dist, Mode::Universal).unwrap();
        assert!(dist.join("demo/.claude-plugin/plugin.json").exists());
        assert!(dist.join("demo/plugin.json").exists());
        assert!(dist.join("demo/skills/x/SKILL.md").exists());
        std::fs::remove_dir_all(&tmp).ok();
    }
}
```

(Note: this test builds no binary because the `demo` fixture has no `[mcp]` section.)

- [ ] **Step 7: Run the full xtask test suite**

Run: `cargo test -p xtask`
Expected: PASS (all generator tests + the mirror test + the package-tree test).

- [ ] **Step 8: Generate the real scaffold dist and eyeball it**

Run: `cargo run -p xtask -- package scaffold`
Expected: `dist/scaffold/` exists containing `.claude-plugin/plugin.json`, `plugin.json`, `.mcp.json`, `mcp_config.json`, `hooks/hooks.json`, `hooks.json`, `skills/hello/SKILL.md`, `skills/rule-no-secrets/SKILL.md`, `hooks/on-start.ps1`, and `bin/scaffold-server.exe`.

- [ ] **Step 9: Commit**

```bash
git add xtask/src
git commit -m "feat(xtask): rule->skill mirror + dual-mode packager assembling dist/"
```

---

## Task 8: Docs — verified-format reference + README rewrite

**Files:**
- Create: `docs/plugin-formats.md`
- Modify: `README.md`

- [ ] **Step 1: Write `docs/plugin-formats.md`**

Create it capturing the verified formats so the generators have a canonical, provenance-tagged reference. Use exactly this content:

```markdown
# Plugin formats (verified reference)

Provenance: Claude docs (code.claude.com/docs/en/plugins-reference, 2026-06-17);
agy peer consults req-djbdx6998nv0 / req-djbeby5zp30k / req-djbemw4gbpoo (2026-06-17).
Re-verify after a `claude` or `agy` update (see the spec's §10 open items).

## Disjoint filenames (the "universal" mechanism)
| Concern | Claude reads | agy reads |
| --- | --- | --- |
| Manifest | `.claude-plugin/plugin.json` | `plugin.json` |
| MCP config | `.mcp.json` | `mcp_config.json` |
| Hooks | `hooks/hooks.json` | `hooks.json` |

Shared: `skills/`, `hooks/` scripts, `bin/`. Both manifest sets coexist in one dir
because each CLI ignores the other's files (ASSUMPTION — re-verify).

## Manifest (both): `{ "name", "version", "description" }` — agy does NOT require `author`.

## MCP server command
- Claude `.mcp.json`: `"${CLAUDE_PLUGIN_ROOT}/bin/<binary>.exe"`
- agy `mcp_config.json`: `"./bin/<binary>.exe"` (agy sets CWD = plugin root)

## Hooks (same shape both): `{ "hooks": { "<EVENT>": [ { "matcher"?, "hooks": [ { "type":"command", "command" } ] } ] } }`
- agy hook commands also run with CWD = plugin root.
- UNVERIFIED: agy's session-start event NAME (assumed `SessionStart`) — confirm via agy `/hooks`.

## Install
- Both copy/stage only — NO build step. Ship pre-compiled binaries.
- agy stages to `~/.gemini/antigravity-cli/plugins/<name>/`.
- agy does NOT `chmod +x` on Unix (handle in xtask for the Unix port).

## MCP transport
Newline-delimited JSON-RPC 2.0 on stdio. stdout MUST stay JSON-RPC-pure; all logs/panics → stderr.
```

- [ ] **Step 2: Rewrite `README.md` for the new charter**

Replace `README.md` with a description of the repo as a Cargo workspace producing universal dual-compatible plugins. Include: the charter sentence, the `## Build a plugin` section (`cargo run -p xtask -- package <plugin>` → install `dist/<plugin>/` with `claude plugin install` / `agy plugin install`), the file-structure table from this plan, the dev loop (`cargo test --all`, `cargo clippy --all-targets -- -D warnings`, `cargo fmt --all --check`), and a pointer to `docs/plugin-formats.md` and the spec. Note that v1 lives on the `v1` branch.

- [ ] **Step 3: Verify the whole workspace is green**

Run: `cargo test --all && cargo clippy --all-targets -- -D warnings && cargo fmt --all --check`
Expected: tests PASS; clippy clean (no warnings); fmt reports no diffs.

- [ ] **Step 4: Commit**

```bash
git add docs/plugin-formats.md README.md
git commit -m "docs: verified plugin-formats reference + README for the workspace charter"
```

---

## Task 9: Live acceptance — install scaffold in both CLIs (manual runbook)

**Files:** none (a runbook; record results, then fix any discrepancy in code/docs).

This proves all four component types and resolves the UNVERIFIED items. Not automated.

- [ ] **Step 1: Package the scaffold**

Run: `cargo run -p xtask -- package scaffold`
Expected: `dist/scaffold/` regenerated.

- [ ] **Step 2: Install + verify in Claude Code**

```bash
claude plugin install ./dist/scaffold
```
Verify in Claude: (a) install accepted; (b) the `scaffold` MCP server lists and the `hello` tool returns its greeting; (c) the `scaffold-hello` skill is listed; (d) the `rule-no-secrets` mirrored skill is present; (e) the `SessionStart` hook fires (`%TEMP%\scaffold-hook-fired.txt` is created on a fresh session). Record pass/fail per item.

- [ ] **Step 3: Install + verify in agy**

```bash
agy plugin install ./dist/scaffold
```
Verify in agy: (a) install accepted (staged to `~/.gemini/antigravity-cli/plugins/scaffold/`); (b) the `scaffold` MCP server lists and `hello` returns its greeting (confirms relative-path + CWD=plugin-root + stdout purity); (c) the skill is available; (d) the hook fires — **and run `/hooks` to read the actual session-start event NAME**.

- [ ] **Step 4: Resolve the event-name uncertainty**

If agy's session-start event name is NOT `SessionStart`, update `agy_event()` in `xtask/src/gen.rs` to map it, update the corresponding test, update `docs/plugin-formats.md`, re-run `cargo test -p xtask`, re-package, and re-verify Step 3(d).

- [ ] **Step 5: Decide the packaging-mode default + rules handling**

Based on Steps 2–3: if both CLIs tolerate the other's sibling files (no install error), keep **universal** as the default. If either errors, switch the default to **split** (`--mode split`) and document why. Record the decision and the resolved UNVERIFIED items back into the spec's §10.

- [ ] **Step 6: Commit any fixes + the recorded results**

```bash
git add -A
git commit -m "test: live dual-CLI acceptance for scaffold; resolve agy event name + mode default"
```

---

## Notes for the executor
- **stdout purity is sacred** (Tasks 2–4): never add a `println!` to a server path; use `mcp_core::log` (stderr). The Task 3 test guards this.
- **Respect the repo gate**: `cargo test --all`, `cargo clippy --all-targets -- -D warnings`, `cargo fmt --all --check`. Do not invent stricter flags.
- **External formats are the oracle**: `docs/plugin-formats.md` + the agy consult examples define correct output. If a generated file looks wrong, the verified format wins — do not edit a generator test to match buggy output; surface the conflict.
- **Tasks 1–8 are hermetic** (no live agy needed). **Task 9 needs both live CLIs.**

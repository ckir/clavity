# ghidrust

Drive a persistent headless Ghidra JVM from your AI agent — 19 reverse-engineering tools over MCP.

## What's in here
Binary `ghidrust` on your PATH; the plugin runs `ghidrust serve` as an MCP server exposing **19 tools**:
- **Read / navigate (14):** `list_project_programs`, `attach_program`, `inspect_function`, `find_functions`,
  `list_symbols`, `list_strings`, `list_data_items`, `list_segments`, `resolve_symbol`, `describe_address`,
  `get_xrefs`, `get_disassembly`, `read_bytes`, `get_datatype`.
- **Write (durable, saved to disk, 5):** `rename`, `comment`, `set_datatype`, `set_prototype`, `set_local`.

Plus the `ghidra-re-driver` skill. That `skills/ghidra-re-driver/SKILL.md` is GENERATED from the binary —
regenerate it, never hand-edit it, with:
```bash
ghidrust skill --emit | awk '/^---/{p=1} p' > skills/ghidra-re-driver/SKILL.md
```
(The `awk` strips the binary's leading license/provenance comment so the YAML frontmatter is the first line —
Claude Code requires that for the skill to register. The license travels with the plugin via the `NOTICE` file.)

## Install / registration
Ships in the `clavity` umbrella. Install the binary via the `ghidrust-v<N>` GitHub Release installer
(`ghidrust-setup-<VERSION>.exe`), and add the plugin from this repo's marketplace.

**Runtime prerequisites (you must install these yourself):**
- **Ghidra 12.1.2** — set `GHIDRA_INSTALL_DIR` to its root (the installer offers to set it).
- **JDK 21** — Ghidra 12.1.2 requires `application.java.min=21`.
- A Ghidra **project you have already created and fully analyzed in the Ghidra GUI, then CLOSED**
  (v1.0 ATTACHES to an analyzed project; it cannot import/analyze — a GUI-locked project can't be attached).

### Uninstall
Windows Add/Remove Programs removes the binary + its PATH entry. It intentionally leaves
`GHIDRA_INSTALL_DIR` (shared) and `%USERPROFILE%\.ghidrust` (your data).

## MCP configuration
The 4 required values are non-secret env vars (each has a `--kebab` CLI flag; precedence flag > env):
- `GHIDRA_INSTALL_DIR` — Ghidra install root (machine-stable; set once, e.g. via the installer).
- `GHIDRUST_PROJECT_DIR` — dir holding the `<name>.gpr`/`.rep`.
- `GHIDRUST_PROJECT_NAME` — the Ghidra project name.
- `GHIDRUST_BOOTSTRAP_PROGRAM` — a **bare** program filename already in the project (e.g. `add.exe`).

Optional: `GHIDRUST_MAX_HEAP` (JVM `-Xmx`, e.g. `4G`, for large binaries), `GHIDRUST_HOME` (relocate the
`.ghidrust` data dir), `GHIDRUST_BOOTSTRAP_PROGRAM_PATH` (VFS path if the bootstrap program is in a subfolder).

**One server = one Ghidra project.** For per-project config or multiple projects, register the server per
workspace with a project-scoped `.mcp.json` (this overrides the bundled env-only registration):
```json
{
  "mcpServers": {
    "ghidrust": {
      "command": "ghidrust",
      "args": ["serve"],
      "env": {
        "GHIDRUST_PROJECT_DIR": "<absolute path to the dir holding your .gpr/.rep>",
        "GHIDRUST_PROJECT_NAME": "<your Ghidra project name>",
        "GHIDRUST_BOOTSTRAP_PROGRAM": "<bare program filename, e.g. add.exe>"
      }
    }
  }
}
```
> **Project-lock:** one Ghidra project ↔ at most ONE live `ghidrust serve`, and the Ghidra GUI CLOSED. Two
> servers on the same project collide on Ghidra's `project.lock`. Different workspaces must target different projects.

## Troubleshooting
- Logs: `<data>/logs/worker-<pid>.log`, rotated daily (5 kept), owner-only. `<data>` = `GHIDRUST_HOME` or
  `%USERPROFILE%\.ghidrust`. **Log verbosity is fixed in v1.0 — there is no `RUST_LOG`.**
- First call after a cold start returns `WORKER_WARMING` (JVM warm-up) — wait a few seconds, don't hammer.
- Run live e2e from **PowerShell** (Git Bash mangles the `/`-prefixed `-process` arg).
- Keep the installer and this plugin at the same version (they update on separate channels).

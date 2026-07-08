# clavity — pair Claude with a live agy peer

Clavity pairs [Claude Code](https://claude.com/claude-code) with [Antigravity (`agy`)](https://antigravity.google),
shipped as universal dual-plugins. It is one tool in the [`clavity` umbrella](README.md).

## Quick Start

Run this in **PowerShell** (not `cmd.exe`) to install:

```powershell
irm https://raw.githubusercontent.com/ckir/clavity/main/install/clavity-install.ps1 | iex
```

*Note: The installer is unsigned, so Windows SmartScreen may warn on first run (choose "More info" →
"Run anyway"). The script resolves the latest GitHub release and verifies the installer's SHA-256
automatically.*

The installer will prompt you to choose between the **.NET** (Primary) or **Classic** (Failover) host
variant, and allow you to opt-in to extras like `agy-autotrain` or `commonmemory`.

Start a paired session:
```powershell
clavity-ls start C:\path\to\your\project
```

*(To uninstall, use Windows Add/Remove Programs. It cleanly de-registers the plugin from each agent).*

## The Ecosystem

Clavity is split into **Core Hosts** (the routing engines) and **Extra Plugins** (optional skills). The
single installation script handles both.

### The Core Hosts (Pick One)

- **`clavity-dotnet` (Primary)**
  The modern, greenfield **.NET 10** rebuild. It turns `agy` into an interactive superpower for Claude via
  a local Language Server (LS-API MCP bridge). Claude spawns an MCP server that exposes three core tools:
  - `agy_look` / `agy_status`: Check what `agy` is doing.
  - `agy_ask`: Send a task or message to `agy` and wait for its reply. Useful for design review, second
    opinions, and delegated parallel work.
  - **Multi-session:** Each Claude instance drives its *own* isolated `agy` instance.
  - **Dynamic send-model:** Drives `agy` using the model your conversation last used, instead of forcing a
    baked-in default.

- **`clavity-classic` (Failover)**
  The original Rust-based psmux doorbell bridge. Claude drives a live, signed-in `agy` peer in the same
  folder over a doorbell mechanism and the agentmemory bus (for review, second opinions, delegated work).
  **This is a fallback solution.** If a future `antigravity-cli` update breaks the `.NET` Language Server
  integration, you can reinstall using the `classic` variant to keep working.

### The Extra Plugins (Opt-In)

- **`commonmemory`**
  A shared cross-agent memory convention. Teaches Claude and `agy` to tag notes (decisions, gotchas, bug
  fixes) with `[common]` and proactively share context via the agentmemory bus.
- **`agy-autotrain`**
  Allows Claude to drive `agy` like a model (`clavity ask`) and auto-trains clavity's knowledge from
  everyday usage. It captures insights, verifies them, and compiles them into a project-agnostic manual.

## Developer & Contributor Guide

If you want to build your own dual-plugins or contribute to Clavity, this section is for you.

### Project Layout

| Path | Role |
| --- | --- |
| `plugins/<name>/` | A universal dual-plugin (contains both manifest sets + `skills/`, ± a server). |
| `docs/plugin-formats.md` | The verified Claude + Agy plugin-format reference. |
| `docs/agy-*.md` | Agy behavior/assumptions references + design specs & plans. |

### Dual-Manifest Architecture
The two CLIs read disjoint filenames, so both manifest sets coexist in one directory:
- **Claude reads:** `.claude-plugin/plugin.json`, `.mcp.json`, `hooks/hooks.json`
- **Agy reads:** `plugin.json`, `mcp_config.json`, `hooks.json`

### Building the Source
To build the `.NET` host:
```bash
dotnet build -c Release
dotnet test -c Release --filter "Category!=LiveAgy"
```
*(Live-agy tests are gated out of CI as they require a running instance).*

### Adding a Plugin
1. Create `plugins/<name>/`.
2. Add both manifest sets and any `skills/` following `docs/plugin-formats.md`. (See `clavity-classic`
   and `commonmemory` as working examples).

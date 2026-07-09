# clavity-classic — required manual wiring

The installer placed `clavity.exe` on your PATH. Classic uses **manual wiring by design** (unlike the
zero-touch dotnet variant) — finish these one-time steps, then `clavity start` does the rest.

## 1. Register the agentmemory bus MCP in BOTH agents (clavity's data channel)

**Claude Code:**

    claude mcp add agentmemory -s user -- npx @agentmemory/agentmemory mcp

**agy** — add to `%USERPROFILE%\.gemini\config\mcp_config.json` (i.e. `C:\Users\<You>\.gemini\config\...`)
under `mcpServers` (Windows needs `cmd /c` for a bare `npx`):

    "agentmemory": { "command": "cmd", "args": ["/c", "npx", "@agentmemory/agentmemory", "mcp"] }

Restart each agent after editing. (Even the dotnet variant requires this — agentmemory is a separate
prerequisite, not something either installer registers.)

## 2. Add the claudavity doorbell pointer to `%USERPROFILE%\.gemini\GEMINI.md` (one-time)

(That's `C:\Users\<You>\.gemini\GEMINI.md` — paste the path into Explorer's address bar to get there.)

Append this block (re-running is harmless — it's idempotent guidance, not config):

    <!-- clavity-classic doorbell (safe to keep) -->
    When you see `claudavity: check your inbox and act on any request from claude, then reply on the bus.`
    (or are told to check claudavity/claude signals), invoke the claudavity-responder skill and follow it.
    A request whose instruction is exactly `[ping]` -> reply `[req_id=...] READY` immediately.

The responder skill itself is auto-installed by `clavity start` — you do not copy it by hand.

## 3. Launch

    clavity start C:\path\to\your\project

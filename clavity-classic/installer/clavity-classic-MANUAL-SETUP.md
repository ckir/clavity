# clavity-classic — required manual wiring

The installer placed `clavity.exe` on your PATH. Classic uses **manual wiring by design** (unlike the
zero-touch dotnet variant) — finish these one-time steps, then `clavity start` does the rest.

## Prerequisites

- **[Claude Code](https://claude.com/claude-code)** — the master agent, already installed and signed in.
- **`agy`** (Antigravity CLI) — the paired agent, already installed and signed in.
- **[psmux](https://github.com/psmux/psmux)** (ships as `psmux`/`pmux`/`tmux`) on your `PATH`. If it
  lives somewhere not on `PATH`, set `AGY_TMUX_BIN` to its full path instead.

## 1. Register the agentmemory bus MCP in BOTH agents (clavity's data channel)

**Claude Code:**

    claude mcp add agentmemory -s user -- npx -y @agentmemory/agentmemory mcp

**agy** — add to `%USERPROFILE%\.gemini\config\mcp_config.json` (i.e. `C:\Users\<You>\.gemini\config\...`)
under `mcpServers` (Windows needs `cmd /c` for a bare `npx`):

    "agentmemory": { "command": "cmd", "args": ["/c", "npx", "-y", "@agentmemory/agentmemory", "mcp"] }

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

Run from your normal shell so agy inherits your signed-in session.

    clavity C:\path\to\your\project           # folder (bare = start)
    clavity -c                                # current folder; forwards -c (continue) to claude
    clavity C:\path\to\your\project --resume   # folder + flags forwarded to claude
    clavity start C:\path\to\your\project      # explicit form, identical

The folder must be the **first** argument and must not start with `-`. If it's omitted — or the
first argument is a flag — the current folder is used and every argument is forwarded to `claude`.
So write `clavity C:\proj --resume`, **not** `clavity --resume C:\proj`.

**On first launch a visible watch tab opens** (Windows Terminal) attached to agy, so you can
answer agy's auth/login prompts — it asks fairly often. Disable with `AGY_WATCH=0`. Attach
manually anytime with `tmux attach -t claude_agy`. To hide agy while keeping it alive, **detach**
with `Ctrl-b d` — **closing** the tab tears down the whole session (the next launch is then a
fresh start).

**Give agy a moment after launch.** It loads its MCP servers (agentmemory included) a few seconds
after starting. Before driving it, gate on `clavity ping` (sends `[ping]`, rings the doorbell,
blocks for agy's `READY` reply) and retry until it exits 0.

# clavity-classic (universal dual-plugin) — live-agy remote control

Packages the `clavity` binary: Claude drives a live, signed-in **agy** peer in the same folder over a
**psmux doorbell** + the **agentmemory bus**. Installs in BOTH Claude Code and Antigravity from one
directory.

> clavity-classic drives a *persistent live* agy — and with the one-line `escape-time` setup below
> it's smooth (the old "keyboard lock" turned out to be a psmux default, now fixed).

## What's in here

- `skills/claudavity-responder/` — agy-side responder (reacts to the doorbell, replies on the bus)
- `skills/clavity-driving/` — Claude-side driving protocol
- `tmux.conf` — the `escape-time` snippet
- `.claude-plugin/plugin.json` + `plugin.json` — Claude + agy manifests

## Install / registration

There's no marketplace listing yet, so you install from a local clone of this repo.

**1. Repo + the `clavity` binary**
```bash
git clone https://github.com/ckir/clavity && cd clavity
cargo install --path clavity-classic   # puts `clavity` on PATH (or use the clavity-classic standalone installer)
```

**2. psmux** — install a tmux/psmux build; ensure `tmux` (or `psmux` / `pmux`) is on your PATH.

**3. Wire up the agentmemory bus in BOTH agents** — see [MCP configuration](#mcp-configuration)
below. **Nothing works without it**; it is clavity's data channel, not an optional extra.

**4. Make Esc responsive** (the keyboard-lock fix) — add the bundled [`tmux.conf`](tmux.conf) to
`~/.tmux.conf`:
```tmux
set -g escape-time 10
set -s escape-time 10
```
Apply it with a fresh psmux server — `tmux kill-server` once (the next `clavity start` reads it).
Verify: `tmux show-options -s escape-time` → `10`. *(Why: psmux's 500 ms default holds every bare
Esc ~half a second, so you can't Esc out of agy's popups — that was the "lock". One press now.)*

> **Note (binary source):** the `clavity` binary now sets `escape-time 10` itself on session creation,
> so once you rebuild it (`cargo install --path clavity-classic --force`, i.e. step 1) this step
> becomes optional belt-and-suspenders. *(The old note here said `--branch clavity-classic`; that
> branch no longer exists — every member lives on `main` in the monorepo.)*

**5. Install the plugin in both CLIs** (from the repo root):
```bash
claude plugin install ./clavity-classic/plugin
agy    plugin install ./clavity-classic/plugin
```
Install only *stages* the skills — they register on each CLI's **next launch** (step 7 does that);
restart a CLI you already have open.

**6. Give agy its trigger rule** — see [MCP configuration](#mcp-configuration). Installing the plugin
makes the responder skill *available* but does **not** make agy fire it on its own.

**7. Run it**
```
clavity start C:\path\to\project     # launches a FRESH agy (in psmux) + Claude Code in the folder
```
The fresh launch picks up everything above — the agentmemory MCP config, the plugin skills, agy's
`GEMINI.md` rule, and (via a fresh psmux server) `escape-time`. Then, in Claude, ask it to drive agy
(e.g. *"use clavity to ask agy to review src/foo"*): Claude uses the bundled **clavity-driving**
skill (`clavity ping` for readiness, `clavity ask "…"` for a round-trip); agy uses
**claudavity-responder**. Observe agy any time with `clavity capture` (read-only — never locks).

**Platforms.** Windows: ✅ verified end-to-end. Linux: 🚧 compiles in CI, runtime unverified.
macOS: 🚧 unverified.

## MCP configuration

### The agentmemory bus (required, both agents)

clavity's data channel is the shared agentmemory store, so the **same** MCP server must be registered
in **both** Claude Code and agy, pointing at the same daemon (default `:3111`). Both CLIs run the same
global `@agentmemory/agentmemory` module, so they implicitly share one store — that shared store *is*
the bus.

**Claude Code** — `claude mcp add agentmemory -s user -- npx @agentmemory/agentmemory mcp`, i.e. in
`~/.claude.json` under `mcpServers`:
```json
"agentmemory": { "type": "stdio", "command": "npx", "args": ["@agentmemory/agentmemory", "mcp"] }
```

**agy** — in `~/.gemini/config/mcp_config.json` under `mcpServers` (on Windows a bare `npx` must be
launched via `cmd /c`):
```json
"agentmemory": { "command": "cmd", "args": ["/c", "npx", "@agentmemory/agentmemory", "mcp"] }
```

Restart each agent after editing its config. Verify Claude sees the bus (the `memory_signal_send` /
`memory_signal_read` tools are available); **`clavity doctor` does not check this**, so confirm it
once during setup.

### agy's responder trigger (required, one-time)

`clavity start` **auto-installs/refreshes** the responder skill into
`~/.gemini/antigravity-cli/skills/` on every launch (it's embedded in the binary), so you normally
don't copy it by hand. You do still need a **one-time pointer in `~/.gemini/GEMINI.md`** so agy
reliably invokes it — add something like:

> When you see the line `claudavity: check your inbox and act on any request from claude, then reply
> on the bus.` (or are told to check claudavity/claude signals), invoke the **`claudavity-responder`**
> skill and follow it: read **only your own** inbox (`memory_signal_read agentId="agy"
> unreadOnly="true"`), checkpoint, do the request, and reply on the bus. A request whose instruction
> is exactly `[ping]` → reply `[req_id=…] READY` immediately (no checkpoint).

The responder makes a **non-intrusive `git stash` checkpoint** before editing the live tree, then
replies on the bus; a `[ping]`-only request is fast-pathed (READY, no checkpoint). On Windows its
checkpoint command is **PowerShell** (agy's shell is pwsh). To install it manually anyway:
```pwsh
Copy-Item -Recurse agy_skills/claudavity-responder `
  "$HOME/.gemini/antigravity-cli/skills/claudavity-responder"
```

> **Note:** agy reads the skill once per session and caches it, so a *running* agy won't see skill
> edits until its next restart.

## Troubleshooting

Much smaller once `escape-time` is fixed (Install step 4).

- **Don't use `/mcp`'s `[Restart]` / `[Disable]` inside agy** — it can deadlock
  (`"loading already in progress"`); to change MCP servers, edit `~/.gemini/config/mcp_config.json`
  and restart agy. A flaky server (e.g. an unused **serena** entry) is a common culprit.
- **Watch-tab raw-mode / mouse-leak:** only if you actively *type* in an attached `tmux attach`
  watch tab while agy holds the terminal, then **hard-kill** agy. Observing via `clavity capture`
  (or running `AGY_WATCH=0`) avoids it. If a terminal gets stranded (mouse-move spews `[…M` codes),
  reset it:
  ```powershell
  [Console]::Write("`e[?1000l`e[?1002l`e[?1003l`e[?1006l`e[?1049l")
  ```
- **agy auth:** agy prompts for login periodically — answer it at agy's terminal.
- **Recovery:** from any *other* shell, `clavity cancel` sends Esc to agy through the psmux server.

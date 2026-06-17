# clavity-classic (universal dual-plugin) — v1 live-agy remote control

Packages clavity **v1**: Claude drives a live, signed-in **agy** peer in the same folder over a
**psmux doorbell** + the **agentmemory bus**. Installs in BOTH Claude Code and Antigravity from one
directory.

> Want a fully hands-off, spawn-on-demand agy instead? See **clavity v2**. clavity-classic drives a
> *persistent live* agy — and with the one-line `escape-time` setup (step 4) it's smooth (the old
> "keyboard lock" turned out to be a psmux default, now fixed).

## Quickstart (from zero)
There's no marketplace listing yet, so you install from a local clone of this repo.

**1. Repo + the `clavity` binary**
```bash
git clone https://github.com/ckir/clavity && cd clavity
cargo install --git https://github.com/ckir/clavity --branch v1   # puts `clavity` on PATH
```

**2. psmux** — install a tmux/psmux build; ensure `tmux` (or `psmux` / `pmux`) is on your PATH.

**3. agentmemory bus** — the shared message bus. Configure the SAME store in BOTH CLIs, then restart each:
- **Claude Code:** `claude mcp add agentmemory -s user -- npx @agentmemory/agentmemory mcp`
- **agy:** add under `mcpServers` in `~/.gemini/config/mcp_config.json` (a bare `npx` on Windows
  needs `cmd /c`):
  ```json
  "agentmemory": { "command": "cmd", "args": ["/c", "npx", "@agentmemory/agentmemory", "mcp"] }
  ```
Both CLIs run the same global `@agentmemory/agentmemory` module, so they implicitly share one store
— that shared store is the bus.

**4. Make Esc responsive** (the keyboard-lock fix) — add the bundled [`tmux.conf`](tmux.conf) to
`~/.tmux.conf`:
```tmux
set -g escape-time 10
set -s escape-time 10
```
Apply it with a fresh psmux server — `tmux kill-server` once (the next `clavity start` reads it).
Verify: `tmux show-options -s escape-time` → `10`. *(Why: psmux's 500 ms default holds every bare
Esc ~half a second, so you can't Esc out of agy's popups — that was the "lock". One press now.)*

**5. Install the plugin in both CLIs** (from the repo root):
```bash
claude plugin install ./plugins/clavity-classic
agy    plugin install ./plugins/clavity-classic
```
Install only *stages* the skills — they register on each CLI's **next launch** (step 7 does that);
restart a CLI you already have open.

**6. Configure agy's automatic trigger** — installing the plugin makes the responder skill
*available*, but does **not** make agy fire it on its own. Add a one-time rule to
`~/.gemini/GEMINI.md` so agy auto-invokes it when it sees the doorbell line:
```
When you see the line "claudavity: check your inbox and act on any request from claude, then reply
on the bus." invoke the claudavity-responder skill: read ONLY your own inbox
(memory_signal_read agentId="agy" unreadOnly="true"), checkpoint, do the request, and reply on the
bus. A request whose instruction is exactly [ping] -> reply [req_id=...] READY immediately.
```

**7. Run it**
```
clavity start C:\path\to\project     # launches a FRESH agy (in psmux) + Claude Code in the folder
```
The fresh launch picks up everything above — the agentmemory MCP config, the plugin skills, agy's
`GEMINI.md` rule, and (via a fresh psmux server) `escape-time`. Then, in Claude, ask it to drive agy
(e.g. *"use clavity to ask agy to review src/foo"*): Claude uses the bundled **clavity-driving**
skill (`clavity ping` for readiness, `clavity ask "…"` for a round-trip); agy uses
**claudavity-responder**. Observe agy any time with `clavity capture` (read-only — never locks).

## Minor gotchas (much smaller once `escape-time` is fixed)
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

## Platforms
Windows: ✅ verified end-to-end. Linux: 🚧 compiles in CI, runtime unverified. macOS: 🚧 unverified.

## Contents
- `skills/claudavity-responder/` — agy-side responder (reacts to the doorbell, replies on the bus)
- `skills/clavity-driving/` — Claude-side driving protocol
- `tmux.conf` — the `escape-time` snippet
- `.claude-plugin/plugin.json` + `plugin.json` — Claude + agy manifests

> **Note (v1 source):** the `clavity` binary now sets `escape-time 10` itself on session creation
> (v1 branch). After you rebuild it (`cargo install … --branch v1 --force`), step 4's `~/.tmux.conf`
> becomes optional belt-and-suspenders.

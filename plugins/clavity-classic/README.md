# clavity-classic (universal dual-plugin) — v1 live-agy remote control

Packages clavity **v1**: Claude drives a live, signed-in **agy** peer in the same folder over a
**psmux doorbell** + the **agentmemory bus**. Installs in BOTH Claude Code and Antigravity from
one directory.

> Want a fully hands-off, spawn-on-demand agy instead? See **clavity v2**. clavity-classic is for
> driving a *persistent live* agy session — and with the one-line `escape-time` setup below it's a
> smooth experience (the old "keyboard lock" turned out to be a psmux default, now fixed).

## Prerequisites (an advanced power-user workflow)
1. **The `clavity` binary** (builds for your platform from the v1 branch):
   `cargo install --git https://github.com/ckir/clavity --branch v1`
2. **psmux** (`psmux` / `pmux` / `tmux`) on your PATH.
3. **agentmemory** MCP server configured in BOTH Claude Code and agy (the shared bus).

## ⚙️ Required setup — make Esc responsive (this *is* the "keyboard lock" fix)
psmux defaults `escape-time` to **500 ms**, which holds every bare **Esc** for half a second while
it waits to see whether it's the start of an arrow/function-key sequence. Inside a psmux session
that makes Esc feel **dropped/laggy** — you can't Esc out of agy's popups/states, which feels like
a "keyboard lock." Fixing it is the single biggest quality-of-life win.

Add the bundled [`tmux.conf`](tmux.conf) snippet to your **`~/.tmux.conf`**:
```tmux
set -g escape-time 10
set -s escape-time 10
```
Then start a **fresh psmux server** so it loads (escape-time is read at session creation):
`tmux kill-server` once, or `clavity stop` before your next `clavity start`. Verify:
```
tmux show-options -s escape-time      # expect: escape-time 10
```
With this set, Esc closes agy's `/mcp` popup in **one press** and the "lock" is gone.

## Install (both CLIs, one directory)

    claude plugin install ./plugins/clavity-classic
    agy    plugin install ./plugins/clavity-classic

## Use
Start agy + Claude in a folder (`clavity start <folder>`), then ask Claude to drive agy — it uses
the bundled **clavity-driving** skill (`clavity ping` for readiness, `clavity ask "…"` for a
round-trip). agy uses the bundled **claudavity-responder** skill to react to the doorbell and reply
on the bus. Observe agy any time with `clavity capture` (read-only — never locks).

## Minor gotchas (much smaller once `escape-time` is fixed)
- **Don't use `/mcp`'s `[Restart]` / `[Disable]` inside agy** — it can deadlock
  (`"loading already in progress"`); to change MCP servers, edit `~/.gemini/config/mcp_config.json`
  and restart agy. A flaky server (e.g. an unused **serena** entry) is a common culprit — remove it.
- **Watch-tab raw-mode / mouse-leak:** only happens if you actively *type* in an attached `tmux
  attach` watch tab while agy holds the terminal, and then **hard-kill** agy. Observing via `clavity
  capture` (or running `AGY_WATCH=0`) avoids it. If a terminal ever gets stranded (moving the mouse
  spews `[…M` escape codes), reset it:
  ```powershell
  [Console]::Write("`e[?1000l`e[?1002l`e[?1003l`e[?1006l`e[?1049l")
  ```
  …or just open a fresh shell.
- **agy auth:** agy prompts for login periodically — answer it at agy's terminal (you're there).
- **Recovery:** from any *other* shell, `clavity cancel` sends Esc to agy through the psmux server,
  reaching it even if a client terminal is wedged.

## Platforms
Windows: ✅ verified end-to-end. Linux: 🚧 compiles in CI, runtime unverified. macOS: 🚧 unverified.

## Contents
- `skills/claudavity-responder/` — agy-side responder (reacts to the doorbell, replies on the bus)
- `skills/clavity-driving/` — Claude-side driving protocol
- `tmux.conf` — the `escape-time` snippet (add to `~/.tmux.conf`)
- `.claude-plugin/plugin.json` + `plugin.json` — Claude + agy manifests

> **Follow-up (v1 source):** the `clavity` binary should set `escape-time 10` itself when it creates
> the psmux session, so the fix isn't dependent on a hand-placed `~/.tmux.conf`. Tracked for the next
> v1 rebuild.

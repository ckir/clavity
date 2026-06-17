# clavity-classic (universal dual-plugin) — v1 live-agy remote control

Packages clavity **v1**: Claude drives a live, signed-in **agy** peer in the same folder over a
**psmux doorbell** + the **agentmemory bus**. Installs in BOTH Claude Code and Antigravity from
one directory.

> **Most users want clavity v2 instead** — it is spawn-on-demand and **lock-free**. Use
> clavity-classic only if you specifically want to drive a *persistent live* agy session and
> accept the keyboard-lock trade-off below.

## Prerequisites (out-of-band — an advanced power-user workflow)
1. **The `clavity` binary** (builds for your platform from the v1 branch):
   `cargo install --git https://github.com/ckir/clavity --branch v1`
2. **psmux** (`psmux` / `pmux` / `tmux`) on your PATH.
3. **agentmemory** MCP server configured in BOTH Claude Code and agy (the shared bus).

## Install (both CLIs, one directory)

    claude plugin install ./plugins/clavity-classic
    agy    plugin install ./plugins/clavity-classic

## Use
Start agy + Claude in a folder (`clavity start <folder>`), then ask Claude to drive agy — it uses
the bundled **clavity-driving** skill (`clavity ping` for readiness, `clavity ask "…"` for a
round-trip). agy uses the bundled **claudavity-responder** skill to react to the doorbell and
reply on the bus.

## ⚠️ Keyboard lock — read this
clavity v1's auto-attached "watch tab" runs an **interactive `tmux attach`**, which puts YOUR
terminal into raw mode (no echo) — your keystrokes get swallowed by agy, a "keyboard lock". A
hard-kill of agy leaves psmux redrawing escape sequences to the attached terminal. To avoid it:
- **Run with `AGY_WATCH=0`** (no auto-attach). Observe agy with `clavity capture`; `tmux attach
  -t claude_agy` MANUALLY only to answer an auth prompt, then detach (`Ctrl-b d`).
- **Recovery if locked:** from a DIFFERENT (non-attached) shell, run `clavity cancel` (sends
  Escape to agy). The send-keys path reaches agy through the psmux server even when your client
  terminal is raw-mode-locked.
- For a fully lock-free experience, use **clavity v2**.

## Platforms
Windows: ✅ verified end-to-end. Linux: 🚧 compiles in CI, runtime unverified. macOS: 🚧 unverified.

## Contents
- `skills/claudavity-responder/` — agy-side responder (reacts to the doorbell, replies on the bus)
- `skills/clavity-driving/` — Claude-side driving protocol
- `.claude-plugin/plugin.json` + `plugin.json` — Claude + agy manifests

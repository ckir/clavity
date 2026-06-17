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

## ⚠️ Keyboard lock & escape-sequence spew — read this
clavity v1's auto-attached "watch tab" runs an **interactive `tmux attach`**, which makes tmux take
over YOUR terminal: it enables **raw mode** (no echo — your keystrokes get swallowed by agy = the
"keyboard lock") and **mouse-tracking mode** (`\e[?1000h` / `?1003h` / `?1006h`). On a clean
detach/exit tmux resets these — but a **hard-kill** of agy, or agy's `/mcp` reload **deadlocking**
(`"loading already in progress"`), skips the cleanup and **strands your terminal in those modes**.
Symptom: moving the mouse spews escape sequences like `[555;115;1M[555;114;1M…` — those are
**mouse-movement reports your un-reset terminal is emitting** (not agy, which is already gone).

**Avoid it (recommended default):**
- **Run agy with `AGY_WATCH=0`** — no `tmux attach` on your terminal, so tmux never puts it into
  raw/mouse mode and nothing can leak. Observe agy with `clavity capture`; `tmux attach -t
  claude_agy` MANUALLY only to answer an auth prompt, then detach (`Ctrl-b d`).

**Recovery if your terminal is already stranded:**
- **Unstick agy** from a DIFFERENT (non-attached) shell: `clavity cancel` sends Escape through the
  psmux *server*, reaching agy even when your client terminal is locked. (Escape **cannot** close a
  *deadlocked* `/mcp` reload — that needs an agy restart.)
- **Reset your terminal** — disable mouse-reporting + exit alt-screen (pwsh):
  ```powershell
  [Console]::Write("`e[?1000l`e[?1002l`e[?1003l`e[?1006l`e[?1015l`e[?1049l")
  ```
  …or simply **close the tab and open a fresh shell**.

For a fully lock-free experience (no live TUI, no watch tab, no `/mcp`), use **clavity v2**.

## Platforms
Windows: ✅ verified end-to-end. Linux: 🚧 compiles in CI, runtime unverified. macOS: 🚧 unverified.

## Contents
- `skills/claudavity-responder/` — agy-side responder (reacts to the doorbell, replies on the bus)
- `skills/clavity-driving/` — Claude-side driving protocol
- `.claude-plugin/plugin.json` + `plugin.json` — Claude + agy manifests

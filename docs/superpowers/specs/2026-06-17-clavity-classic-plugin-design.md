# clavity-classic — Packaging the clavity Binary as a Distributable Universal Plugin — Design

**Date:** 2026-06-17
**Status:** Approved (design); implementation plan pending.
**Author:** Costas Kirgoussios (with Claude + agy consults)

---

## 1. Context & purpose

The `clavity` binary is the original Rust remote-control: Claude drives a live, signed-in `agy` peer
over a **psmux `send-keys` doorbell** + the **agentmemory signal bus**; agy runs the
`claudavity-responder` skill. It is **Windows-verified** (Linux compiles in CI but is
runtime-unverified; macOS unverified). Its source is preserved on the **`clavity-classic` branch**.

This subproject packages that binary as **`clavity-classic`** — a **universal dual-plugin** installable
by *both* `claude plugin install` and `agy plugin install` — so it can be **distributed to other
people** who want the live-agy driving model. The binary's code is treated as a **frozen, preserved
artifact**: this work adds packaging around it, not changes to it.

---

## 2. Locked decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Approach A — skills-only plugin** (no MCP server) | The clavity binary has no MCP server; it is a CLI driven by shell commands. The plugin ships the two skills + manifests + README. *(agy consult: a skills-only plugin registers fine; zero gotchas.)* |
| D2 | **Binary via `cargo install --git … --branch clavity-classic`** | Builds `clavity` from the clavity-classic branch on the user's own machine → every platform handled, **no prebuilt binaries, no release pipeline, no crates.io publish**. |
| D3 | **Name: `clavity-classic`** | Signals "the original" live-persistent-agy driving model, distinct from the lighter-weight suite plugins. |
| D4 | **Keyboard lock: document + keep the binary frozen** | The lock is structural (below), not a quick fix; document the root cause + the `AGY_WATCH=0` workaround rather than modify the preserved binary. |

---

## 3. Verified facts — the keyboard-lock root cause

*(Sources: live diagnosis 2026-06-17 — psmux `escape-time` inspection + a one-Esc `/mcp`-close
test; earlier user observations; agy consult `req-djbj3rtx2als`; the clavity-classic branch's
`src/main.rs`/`src/tmux.rs`.)*

**The dominant cause is psmux's `escape-time` default — not the attach.** psmux/tmux defaults
`escape-time` to **500 ms**: every bare **Esc** is held ~half a second while psmux waits to see if
it's the start of an escape sequence (arrow/function keys). Inside a psmux session that makes Esc
feel **dropped/laggy** — you cannot Esc out of agy's popups/states — which is the bulk of what felt
like a "keyboard lock." **Fix: `escape-time 10`.** *Verified live 2026-06-17: with `escape-time 10`,
a single Esc closes agy's `/mcp` popup that previously needed multiple tries or hung.* Because the
value is read at **session creation**, it must be set **before** the session exists — via
`~/.tmux.conf` (the server reads it at startup) **or** by clavity setting it just before
`new-session` (the clavity-classic source patch).

**Secondary, smaller contributors** (matter far less once `escape-time` is fixed):
- The watch tab's **interactive `tmux attach`** puts the user's terminal into raw mode; if the user
  actively *types* there while agy holds the terminal, keystrokes are swallowed. Mitigated by
  **`AGY_WATCH=0`** + observing via `clavity capture` (which shells out via `capture-pane -p` —
  **no attach**, so observation is always lock-free).
- A **hard-kill** of agy (or the `/mcp` *restart* deadlock) leaves the attached terminal stranded in
  raw + mouse-tracking mode → moving the mouse spews `[…M` reports (emitted by the un-reset terminal,
  not the dead agy). Reset with the mouse-mode-disable sequence, or just open a fresh shell.
- agy has **no `--no-tui`/`--plain`** continuous mode (only `--print` one-shot) *(agy consult)* —
  irrelevant now, since the fix is at the psmux layer, which clavity controls.

**Conclusion:** ship `escape-time 10` as required setup — clavity sets it on session creation (the
clavity-classic source patch), and the plugin also documents the `~/.tmux.conf` snippet. With that,
the live driving model is smooth; the attach/mouse-leak items become minor `AGY_WATCH=0`-style edge
cases, and **`clavity cancel`** (server-side Esc from another shell) remains the recovery if a client
terminal ever wedges.

---

## 4. Architecture — plugin contents

`plugins/clavity-classic/` (lives in this repo; sources distilled from the `clavity-classic` branch):

```
plugins/clavity-classic/
├── .claude-plugin/plugin.json      # Claude manifest  (name/version/description)
├── plugin.json                     # agy manifest     (same fields; disjoint filename → coexists)
├── skills/
│   ├── claudavity-responder/SKILL.md   # agy-side responder — copied VERBATIM from the clavity-classic branch
│   └── clavity-driving/SKILL.md        # Claude-side driving protocol — distilled from the branch's
│                                       #   docs/agy-remote-control-protocol.md
└── README.md                       # prerequisites, install, the lock caveat/workaround, platforms
```

- **No MCP config** (`.mcp.json`/`mcp_config.json`) — the clavity binary has no MCP server.
- **No bundled binary** — delivered via `cargo install` (D2).
- Both manifests carry `name: "clavity-classic"`, `version` (tracks the clavity binary's version), `description`.

### 4.1 `claudavity-responder` skill (agy)
Copied verbatim from `clavity-classic:agy_skills/claudavity-responder/SKILL.md`. Teaches agy to react
to the psmux doorbell line, read its own inbox, checkpoint, act, and reply on the bus. This is all agy
needs (agy does not run the binary — Claude does).

### 4.2 `clavity-driving` skill (Claude)
Distilled from `clavity-classic:docs/agy-remote-control-protocol.md` into a focused `SKILL.md`: the
exact Claude-side procedure to drive agy — `clavity ask`/`ring`/`capture`/`ping`, the `[req_id]`
envelope conventions, and the per-mode request templates — so Claude knows how to use the `clavity`
CLI once the binary is on PATH.

---

## 5. Prerequisites (documented in the README)
1. **Rust + the binary:** `cargo install --git https://github.com/ckir/clavity --branch clavity-classic`
   (puts `clavity` on PATH; builds for the user's platform).
2. **psmux** (`psmux`/`pmux`/`tmux`) on PATH.
3. **agentmemory** MCP server configured in **both** Claude Code and agy (the shared bus).
4. *(Optional)* the SessionStart hook that injects the "live agy peer" reminder.

---

## 6. Install & use (README)
```
claude plugin install ./plugins/clavity-classic
agy    plugin install ./plugins/clavity-classic
```
Then, in Claude, ask it to drive agy (`clavity ask "…"`). The README **recommends running with
`AGY_WATCH=0` by default** (no auto-attach → no lock) and observing agy via `clavity capture`,
attaching manually only for auth. It prominently carries the **keyboard-lock caveat** (§3) and the
**`clavity cancel`-from-another-shell recovery** (§3).

---

## 7. Platform support (documented honestly)
| Platform | Status |
|---|---|
| Windows | ✅ verified end-to-end |
| Linux | 🚧 compiles in CI; runtime unverified |
| macOS | 🚧 unverified |

---

## 8. Testing / acceptance
- **Packaging acceptance (automatable):** `claude plugin install ./plugins/clavity-classic` and
  `agy plugin install ./plugins/clavity-classic` are accepted; both skills are discovered; the
  JSON manifests parse. (Mirrors the scaffold acceptance discipline.)
- **Full driving acceptance (manual, power-user):** with the binary + psmux + agentmemory present,
  a `clavity ask` round-trip works — this is the clavity binary's existing live runbook, not
  re-derived here.

---

## 9. Non-goals
- No bundled prebuilt binaries; no cross-platform release pipeline (rejected: Option B).
- No MCP-server wrapper (rejected: Option C — would change the clavity binary's paradigm).
- **No changes to the clavity binary's code** — it stays frozen; the lock is documented, not patched.

---

## 10. Risks
- **Out-of-band prerequisites** (binary, psmux, agentmemory) — acceptable for an advanced
  power-user workflow *(agy consult)*; mitigated by a clear README + `clavity doctor`.
- **The keyboard lock** — structural; mitigated by documentation + `AGY_WATCH=0`.
- **External-contract drift** — the clavity binary depends on agy's TUI footer markers / psmux
  behavior; the clavity-classic branch's own `docs/agy-assumptions.md` is the re-verification
  reference.

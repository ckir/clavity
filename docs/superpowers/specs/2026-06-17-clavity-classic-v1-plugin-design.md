# clavity-classic — v1 as a Distributable Universal Plugin — Design

**Date:** 2026-06-17
**Status:** Approved (design); implementation plan pending.
**Author:** Costas Kirgoussios (with Claude + agy consults)

---

## 1. Context & purpose

clavity **v1** is the original Rust remote-control: Claude drives a live, signed-in `agy` peer
over a **psmux `send-keys` doorbell** + the **agentmemory signal bus**; agy runs the
`claudavity-responder` skill. It is **Windows-verified** (Linux compiles in CI but is
runtime-unverified; macOS unverified). v1 is preserved on the **`v1` branch**.

This subproject packages v1 as **`clavity-classic`** — a **universal dual-plugin** installable by
*both* `claude plugin install` and `agy plugin install` — so it can be **distributed to other
people** who want the live-agy driving model. v1's code is treated as a **frozen, preserved
artifact**: this work adds packaging around it, not changes to it.

> **Relationship to clavity v2:** v2 (spawn-on-demand headless agy, all-Python) supersedes v1's
> driving model and is **lock-free**. `clavity-classic` is for users who specifically want the
> live-persistent-agy paradigm and accept its trade-offs (below).

---

## 2. Locked decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Approach A — skills-only plugin** (no MCP server) | v1 has no MCP server; it is a CLI driven by shell commands. The plugin ships the two skills + manifests + README. *(agy consult: a skills-only plugin registers fine; zero gotchas.)* |
| D2 | **Binary via `cargo install --git … --branch v1`** | Builds `clavity` from the v1 branch on the user's own machine → every platform handled, **no prebuilt binaries, no release pipeline, no crates.io publish**. |
| D3 | **Name: `clavity-classic`** | Distinct from the v2 plugin (`clavity`); signals "the original". |
| D4 | **Keyboard lock: document + keep v1 frozen** | The lock is structural (below), not a quick fix; document the root cause + the `AGY_WATCH=0` workaround rather than modify the preserved binary. |

---

## 3. Verified facts — the keyboard-lock root cause

*(Sources: user's firsthand observation of the lock + the post-kill escape flush, 2026-06-17;
agy consult `req-djbj3rtx2als`; v1 `src/main.rs`/`src/tmux.rs` inspection.)*

**The lock lives in clavity's own plumbing — the interactive `tmux attach` in the watch tab — not
in agy.** Mechanism:

- v1's `open_watch_tab` opens a Windows Terminal tab running an **interactive `tmux attach -t
  claude_agy`** (so the user can answer agy's frequent auth prompts). A tmux **client takes over
  the host terminal**: it puts the user's terminal into **raw mode** (local echo + line editing
  disabled) and drives it with control sequences. So while attached, the terminal the user types
  into is under **psmux's** control — keystrokes are captured, not echoed = the **keyboard lock**.
- agy, inside the pane, *additionally* runs its own full-screen TUI in raw mode — but the terminal
  the **user** physically interacts with is the **tmux client** terminal, whose mode is set by the
  attach. A `send-keys` doorbell into the same pane compounds the collision.
- **The escape sequences seen after hard-killing agy came from "our side", not agy** — a killed
  process emits nothing. With agy's process gone, **psmux (still alive) redrew the pane (now a
  shell) and emitted control sequences to the attached terminal**, and the tmux client kept the
  terminal in raw mode until detached. *(User correction; supersedes the earlier "agy TUI teardown"
  hypothesis.)*
- agy has **no `--no-tui`/`--plain`/`TERM=dumb`** continuous mode (only `--print` one-shot), so
  switching agy out of TUI mode is not an option *(agy consult)* — but it is also **not necessary**,
  because the capture happens at the **tmux-attach** layer, which clavity fully controls.
- `clavity capture` uses `capture-pane -p` (it shells out — **no attach**), so observation never
  captures the user's terminal; the lock is purely about the **interactive attach**.

**Conclusion:** the keyboard lock is caused by the **interactive `tmux attach` watch tab (clavity's
plumbing)**, which raw-modes the user's terminal. Zero-code-change mitigation: run with
**`AGY_WATCH=0`** (no auto-attached watch tab) → the user's terminal is never captured by tmux → no
lock; observe agy via `clavity capture`, and `tmux attach` **manually only to answer an auth
prompt**, then detach (`Ctrl-b d`). (A read-only watch tab via `tmux attach -r`, or a terminal
reset on detach, are possible future v1 improvements — explicitly out of scope here to keep v1
frozen.)

**Recovery if a terminal does lock:** run **`clavity cancel`** (server-side Escape via
`send-keys`) — or any `clavity` command — from a **different, non-attached shell** to drive/unstick
agy. The send-keys path goes through the psmux *server* and reaches agy even when the user's
attached client terminal is raw-mode-locked. *(Verified live 2026-06-17: two `clavity cancel`
Escapes cleared a stuck `/mcp` modal that the user's own Esc could not reach.)*

---

## 4. Architecture — plugin contents

`plugins/clavity-classic/` (lives in this repo; sources distilled from the `v1` branch):

```
plugins/clavity-classic/
├── .claude-plugin/plugin.json      # Claude manifest  (name/version/description)
├── plugin.json                     # agy manifest     (same fields; disjoint filename → coexists)
├── skills/
│   ├── claudavity-responder/SKILL.md   # agy-side responder — copied VERBATIM from the v1 branch
│   └── clavity-driving/SKILL.md        # Claude-side driving protocol — distilled from v1's
│                                       #   docs/agy-remote-control-protocol.md
└── README.md                       # prerequisites, install, the lock caveat/workaround, platforms
```

- **No MCP config** (`.mcp.json`/`mcp_config.json`) — v1 has no MCP server.
- **No bundled binary** — delivered via `cargo install` (D2).
- Both manifests carry `name: "clavity-classic"`, `version` (track v1's version), `description`.

### 4.1 `claudavity-responder` skill (agy)
Copied verbatim from `v1:agy_skills/claudavity-responder/SKILL.md`. Teaches agy to react to the
psmux doorbell line, read its own inbox, checkpoint, act, and reply on the bus. This is all agy
needs (agy does not run the binary — Claude does).

### 4.2 `clavity-driving` skill (Claude)
Distilled from `v1:docs/agy-remote-control-protocol.md` into a focused `SKILL.md`: the exact
Claude-side procedure to drive agy — `clavity ask`/`ring`/`capture`/`ping`, the `[req_id]` envelope
conventions, and the per-mode request templates — so Claude knows how to use the `clavity` CLI once
the binary is on PATH.

---

## 5. Prerequisites (documented in the README)
1. **Rust + the binary:** `cargo install --git https://github.com/ckir/clavity --branch v1`
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
attaching manually only for auth. It prominently carries the **keyboard-lock caveat** (§3), the
**`clavity cancel`-from-another-shell recovery** (§3), and a pointer to **clavity v2 for a fully
lock-free experience**.

---

## 7. Platform support (documented honestly)
| Platform | Status |
|---|---|
| Windows | ✅ verified end-to-end (v1) |
| Linux | 🚧 compiles in CI; runtime unverified |
| macOS | 🚧 unverified |

---

## 8. Testing / acceptance
- **Packaging acceptance (automatable):** `claude plugin install ./plugins/clavity-classic` and
  `agy plugin install ./plugins/clavity-classic` are accepted; both skills are discovered; the
  JSON manifests parse. (Mirrors the scaffold/v2 acceptance discipline.)
- **Full driving acceptance (manual, power-user):** with the binary + psmux + agentmemory present,
  a `clavity ask` round-trip works — this is v1's existing live runbook, not re-derived here.

---

## 9. Non-goals
- No bundled prebuilt binaries; no cross-platform release pipeline (rejected: Option B).
- No MCP-server wrapper (rejected: Option C — would change v1's paradigm).
- **No changes to v1's code** — it stays frozen; the lock is documented, not patched.

---

## 10. Risks
- **Out-of-band prerequisites** (binary, psmux, agentmemory) — acceptable for an advanced
  power-user workflow *(agy consult)*; mitigated by a clear README + `clavity doctor`.
- **The keyboard lock** — structural; mitigated by documentation + `AGY_WATCH=0`, and by steering
  users to v2.
- **External-contract drift** — v1 depends on agy's TUI footer markers / psmux behavior; v1's own
  `docs/agy-assumptions.md` (on the branch) is the re-verification reference.

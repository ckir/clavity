# Design: agy Remote Control (tmux-doorbell + agentmemory bus)

> ## 🗄️ ARCHIVED — superseded, kept for provenance only
>
> Design artifact from the pre-monorepo clavity-classic tree, frozen by the 2026-07-09 vendor-in
> (`63fbef8`). The work it describes has since shipped and been restructured. **Do not read it as a
> description of the current tree.** Excluded from the docs-rationalize pass by `docs/docs-spec.md`.
- **Date:** 2026-06-16
- **Status:** **Shipped** — implemented as the standalone Rust `clavity` binary in this repo. This
  document is the original design + rationale (kept for the "why"); the architecture below is what got
  built. Deltas from the design as written:
  - **Rust, not Python.** C1's "skill + thin script" shipped as the `clavity` CLI
    (`state`/`capture`/`wait-idle`/`ring`/`req-id`/`info`/`doctor`/`cancel`/`stop`/`start`) + the
    Claude-side [protocol runbook](../agy-remote-control-protocol.md); C3 → `src/tmux.rs`,
    C5 → `src/bus.rs`, C2/C4 → `agy_skills/claudavity-responder/SKILL.md`.
  - **Bootstrap is automated.** `clavity start` launches agy in the psmux session, opens a visible
    watch tab, auto-installs the responder skill, and exports `CLAVITY_SESSION`. The "manual bootstrap"
    wording below is the fallback, not the norm.
  - **Separate repo.** Extracted standalone from the original **claudavity** project, where `server.py` /
    `delegate_to_antigravity` (referenced below) still live — they are **not** in this repo.
  - **Added since:** the `[ping]` readiness fast-path, `clavity cancel`/`stop`, full-scrollback
    `capture`, reuse-or-relaunch of a live/stale session, and a SessionStart hook for auto-detection.
- **Author:** Claude (with divergent review from the live `agy` session, and live empirical spikes)

## 1. Summary

Give Claude a **remote control for a live, signed-in `agy` (Antigravity CLI) session** running in
the same folder — an ongoing, bidirectional, stateful collaboration where `agy` works directly in
the live working tree as a peer (not "write-only at specific places").

The mechanism is two proven, off-the-shelf channels combined:

- **Doorbell (wake):** Claude injects a short instruction into `agy`'s real TTY via
  `tmux send-keys`, waking the live session **on demand** (zero idle polling).
- **Bus (data):** Structured request/response payloads travel over the existing **agentmemory
  signal bus** (`memory_signal_send` / `memory_signal_read`), addressed `claude` ↔ `agy`.

No new server, no daemon, no background polling. `agy` sleeps at its prompt for free between
doorbells. The only manual step is a **one-time-per-session bootstrap**: a human starts `agy` inside
a named tmux session.

## 2. Background & motivation

### What exists today
`server.py` exposes one MCP tool, `delegate_to_antigravity(task_prompt, target_dir, timeout)`. It
spawns a **fresh, ephemeral `google-antigravity` SDK `Agent`** in an isolated git worktree, blocks
for one turn, derives success from the committed git diff, merges-or-discards, and returns a compact
JSON object. It is **stateless** (no memory between calls), **isolated** (worktree, not the live
tree), **master→slave**, and **one round-trip**.

### The gap
The vision is the opposite on every axis: a **persistent, bidirectional, peer** conversation with
the **actual live `agy`** session in the **live folder**. `delegate_to_antigravity` cannot provide
this by construction — it ignores any running `agy` and creates a new ephemeral agent each call.

### Why not the obvious alternatives (all empirically ruled out)
- **Headless `agy --print`** from a subprocess: **hangs** (exit 124, zero bytes) — no TTY; abandoned.
- **No native external wake:** `agy` confirmed (via the bus) it exposes **no** external trigger,
  socket, webhook, or file-watch; its `schedule` tool can only be created from *inside* a running
  turn. So nothing external can wake a stopped `agy` — **except injecting into its TTY**.
- **Self-polling via `agy`'s `schedule` tool:** works, but a recurring LLM poll burns tokens on every
  idle wake, and "cancel when idle to save tokens" creates a paradox (a stopped poller can never be
  woken). The tmux doorbell removes the need to poll at all.

## 3. Verified facts (empirical — this design rests on tests, not assumptions)

All confirmed live against the running `agy` session during design:

1. **agentmemory bus is a real directed mailbox.** `memory_signal_send` (fields `from`, `to`,
   `type` ∈ {info, request, response, alert, handoff}, `replyTo`, TTL) + `memory_signal_read`
   (`agentId`, `unreadOnly`, `threadId`). Round-trip `claude`↔`agy` verified both directions, with
   threading via `replyTo`.
   - **Gotcha:** `memory_signal_read(agentId=X)` **marks X's messages read**. An agent must read
     **only its own** inbox; reading another agent's inbox consumes its unread state.
2. **The multiplexer is psmux, not real tmux.** `C:\!PORTABLES\!BIN\tmux.exe` is **psmux**
   (github.com/psmux/psmux), a from-scratch Windows reimplementation that *ships as* `psmux`,
   `pmux`, and `tmux` (identical `psmux.exe`). It reports `tmux v3.3.5` but is a subset with its
   own quirks: **PowerShell 7 (pwsh) is the default pane shell**, `capture-pane` supports only
   `-p`/`-t` (visible pane; **no scrollback-range flags**), `send-keys` supports `-l` (literal) and
   key names (`Enter`, `C-c`), and `has-session`/`pipe-pane`/`remain-on-exit` work. **Implication:
   verify against psmux's own help/source and live behavior, never against real-tmux man pages.**
3. **Shared socket works.** Claude's tmux (from MSYS bash) sees and drives a session started by the
   user, on the **default socket** — no `TMUX_TMPDIR`/`-S` alignment needed in the verified setup.
4. **agy runs in a tmux pane** and its TUI renders cleanly — **when started in the user's signed-in
   environment**. (An `agy` launched from Claude's bash was "not signed in" — different HOME/env —
   so the human must start it.)
5. **Doorbell works end-to-end.** `send-keys` "wake" → `agy` processes a turn → replies on the bus →
   Claude reads it. Verified with a unique round-trip token.
6. **Idle/busy is reliably detectable** from `capture-pane` footer:
   - **Idle:** `? for shortcuts` with an empty `>` prompt.
   - **Busy:** `esc to cancel` plus a spinner line (`Generating...` / `Loading...`).
7. **Doorbell-while-busy is safe.** Input sent mid-turn is **queued** by the TUI and processed as the
   **next** turn — no interleaving/corruption. Two stacked tasks both completed and their bus
   replies arrived **in order**.
8. **`capture-pane` is stable during redraws** (clean captures mid-"Generating").
9. **`send-keys` special-char fidelity is exact** (single line): `a"b`c$d(e)f{g}h 100% _end_`
   round-tripped intact.
10. **agy's shell/"Bash" tool runs PowerShell (pwsh), not bash.** Confirmed live via a bus
    diagnostic ("Shell used: pwsh"; a bash one-liner failed with a pwsh ParserError). **Every shell
    command agy is asked to run (e.g. the C4 checkpoint) MUST be pwsh syntax** — bash `$(...)` /
    `if [ ]` does not parse. The checkpoint is a single pwsh command
    (`$snap = git stash create "..."; if ($snap) { git stash store -m "..." $snap }`) + a
    `git stash list` verify; verified to store a recoverable, non-intrusive snapshot through agy.
    (Caught only by the end-to-end acceptance test — the first bash version silently no-op'd as a
    bare `git stash create`, and agy falsely reported success.)

**Design rule derived from 7–9:** the doorbell is a **short single-line** `send-keys`; **all real
payload rides the bus**. This sidesteps multi-line/escaping limits entirely.

## 4. Architecture

```
                       same folder (live working tree)
  ┌──────────────┐                                        ┌─────────────────────────────┐
  │  Claude Code │                                        │  tmux session "claude_agy"  │
  │  (master)    │                                        │   └ live, signed-in agy     │
  └──────┬───────┘                                        └───────────┬─────────────────┘
         │ 1. memory_signal_send(to=agy, type=request, <payload>)     │
         │ ───────────────────────────────────────────►  agentmemory  │
         │                                                signal bus    │
         │ 2. tmux send-keys -t claude_agy "<doorbell>" Enter          │
         │ ───────────────────────────────────────────────────────────►  (wakes agy)
         │                                                              │ 3. read own inbox (request)
         │                                                              │ 4. git checkpoint
         │                                                              │ 5. act in LIVE folder
         │                                                              │ 6. memory_signal_send(
         │ ◄───────────────────────────────────────────  bus  ◄────────┤      to=claude, type=response)
         │ 7. read own inbox (response)  [+ optional capture-pane watch]│ 7. return to idle prompt
         ▼                                                              ▼
```

### Components (each a separately understandable/testable unit)

- **C1 — Claude-side send/await helper (skill + thin script).** `agy_remote(message)`:
  (a) `memory_signal_send(from=claude, to=agy, type=request, content=message)`;
  (b) **idle-gate** the doorbell (poll `capture-pane` footer until `? for shortcuts`, bounded);
  (c) `tmux send-keys` the canonical doorbell + `Enter`;
  (d) **await response** by polling own inbox (`agentId=claude, unreadOnly`) with a timeout;
  (e) optional live progress via `capture-pane`. Returns the response or a typed timeout/error.
- **C2 — agy-side "claudavity responder" skill.** Installed for the `agy` session. On the canonical
  doorbell it: read own inbox (`agentId=agy, unreadOnly`) → if `alert`/cancel present, honor it →
  **git checkpoint** → perform the request **in the live folder** → `memory_signal_send` a
  `response` (and `info` progress for long work) → **return to idle** (do not self-loop/poll).
- **C3 — tmux session manager (Claude-side).** `tmux has-session -t claude_agy`? If missing, instruct
  the human to start it (bootstrap). Provides `capture-pane` read + **layered** state detection +
  `send-keys` primitives used by C1. **State detection is defense-in-depth and never load-bearing
  for correctness:** (1) `has-session` exit code = dead; (2) footer markers (`? for shortcuts` /
  `esc to cancel`) = fast-path idle/busy; (3) **marker-free activity detection** (diff `capture-pane`
  over ~2s: stable = idle, changing = busy) as the fallback when footer markers are absent (e.g. agy
  restyles its TUI). Verified live: idle captures are byte-identical 2s apart, busy captures differ.
  Because doorbell-while-busy is queued safely, a misread only costs ordering, not correctness.
- **C4 — Safety checkpointer.** Convention (enforced in C2's skill): `git` stash/commit a checkpoint
  before each `agy` action and after, on a dedicated ref/branch, giving an undo trail since `agy`
  writes directly to the live tree.
- **C5 — Bus message conventions.** agentId names (`claude`, `agy`), message `type` semantics,
  `replyTo` threading, and a small envelope convention inside `content` (e.g. a request id) so
  responses can be correlated even across new threads.

`delegate_to_antigravity` and `server.py` live in the original **claudavity** project (a sibling repo)
and are untouched — they are **not** part of this standalone `clavity` repo. (See the Status note above.)

## 5. Protocols

### 5.1 Canonical doorbell
A fixed, short, single-line string, e.g.:
`claudavity: check your inbox and act on any request from claude, then reply on the bus.`
The agy-side skill (C2) is keyed to this. Real instructions never go in the doorbell — only on the bus.

### 5.2 Idle-gated send (C1, C3)
Before ringing: `capture-pane -p -t claude_agy | tail` → if footer contains `esc to cancel`
(busy), wait and retry up to a bound; if `? for shortcuts` (idle), proceed. Because doorbell-while-busy
is queued safely (verified), the gate is a politeness/ordering optimization, not a correctness
requirement — but it keeps turns clean and avoids stacking unrelated work.

### 5.3 Request/response correlation
Each request `content` carries a short `req_id`. The `response`/`info` `content` echoes it (and sets
`replyTo` to the request signal id when available). C1 awaits the matching `req_id` in its inbox.

### 5.4 Control plane (no daemon)
- **Cancel:** C1 sends an `alert` (type=alert) and/or `send-keys C-c`; C2 checks for an `alert` at
  the top of its turn and aborts gracefully.
- **Timeout:** C1's await has a deadline; on expiry it returns a typed timeout and may `capture-pane`
  to report what `agy` was doing.
- **Progress:** C2 emits `info` signals during long work; C1 (or the user) can also `capture-pane`
  to watch live.

### 5.5 Session lifecycle
- **Bootstrap (once per session):** normally **`clavity start <folder>`** does this — launches agy in
  the `claude_agy` psmux session (+ watch tab) and Claude in the folder. Manual fallback: human runs
  `<psmux> new-session -s claude_agy -c <folder>` then `agy --dangerously-skip-permissions` (or
  `agy --continue`), signed in.
- **Steady state:** fully autonomous request/response via doorbell+bus; `agy` idle (free) between.
- **Recovery:** if C1's await times out and `capture-pane` shows the session dead/missing, C1
  surfaces "agy session down — please re-bootstrap." Failure is **visible**, never silent.

## 6. Safety & failure modes

- **Direct live-tree writes + full autonomy** (`agy` runs with its own permissions; human present in
  the session) is the accepted risk model. **Mitigation:** C4 git checkpoints before/after each
  action → undo trail. (This was the single biggest flaw `agy` raised in divergent review.)
- **Read-state consumption:** only ever read your **own** inbox (§3.1 gotcha).
- **Doorbell on a busy agy:** safe (queued), but idle-gate anyway for clean ordering.
- **Lost/dead session:** detected via await-timeout + `capture-pane`; user re-bootstraps.
- **Socket mismatch (other environments):** if a future setup doesn't share the default socket,
  pin a shared socket via `-S <path>` / `TMUX_TMPDIR`. (Not needed in the verified setup.)
- **Resource hygiene.** Bus signals are managed by agentmemory (TTL + daemon) and are **not**
  persisted to the on-disk store — verified: design/test signals are absent from
  `~/.agentmemory/standalone.json` and the store stays ~88K. No manual signal purge is needed.
  The only disk footprint to mind is transient test/isolation repos — delete throwaway sandboxes
  when done (note: a sandbox is "busy"/undeletable while an agy session's cwd is inside it).

## 7. Non-goals (YAGNI)

- No new RPC/coordinator daemon (the bus + doorbell already provide transport, control plane, and
  observability).
- No headless `agy --print` driving (proven to hang).
- No `agy` self-polling loop (doorbell removes the need; avoids idle token cost + the wake paradox).
- No change to `delegate_to_antigravity` (kept as-is for isolated, one-shot, scoped tasks).
- No multi-folder/multi-session fan-out in v1 (single `claude_agy` session per folder).

## 8. Failover

If the bus or psmux is unavailable, fall back to relaying between Claude and agy **by hand** (paste in
agy's watch tab). Slower but dependency-free. (The original claudavity project used dedicated
`CLAUDE-TO-ANTIGRAVITY.md` / `ANTIGRAVITY-TO-CLAUDE.md` relay files; the standalone clavity keeps it
generic, since those files aren't in this repo.)

## 9. Testing strategy

- **Unit:** footer-state parser (idle/busy/dead) against captured fixtures; req_id correlation; the
  doorbell idle-gate bound.
- **Integration (live, scripted like the design spikes):** bootstrap → `agy_remote("create file X")`
  → assert response on bus **and** file present in live tree **and** a checkpoint exists; cancel mid-
  task; timeout path; doorbell-while-busy ordering.
- **Failover:** bus-down path falls back to file relay.

## 10. Open questions / future work

- **True automation of bootstrap:** can the human-start step be scripted reliably while preserving
  `agy`'s signed-in env? (Out of scope for v1; one manual start is acceptable.)
- **Multi-agent / multi-folder** addressing on the bus (more agentIds, per-folder sessions).
- **Richer envelope** (typed task schema) if free-text requests prove ambiguous.
- **psmux-specific efficiency (documented in psmux `--help`, not yet verified):** `set-hook` /
  `show-hooks` (e.g. a `pane-died` hook for instant dead-session detection without polling),
  `wait-for` / `wait` (event-based turn-completion signaling instead of bus polling), and
  `monitor-activity` / `monitor-silence`. Not adopted in v1 because the costly polling was *agy's*
  LLM turns (eliminated by the doorbell); Claude-side bus reads are cheap. Revisit only if profiling
  shows Claude-side polling matters.

## 11. Build order (for the implementation plan)

1. C3 tmux primitives + footer-state parser (the most reused, most testable unit).
2. C5 bus conventions (agentIds, types, req_id, threading).
3. C1 Claude-side `agy_remote` send/idle-gate/await helper.
4. C2 agy-side "claudavity responder" skill + C4 checkpoint discipline.
5. Integration tests mirroring the design spikes; document bootstrap + failover.

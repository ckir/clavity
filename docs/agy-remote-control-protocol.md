# agy Remote Control — Claude-side orchestration protocol (C1)

The procedure Claude follows to drive the live, signed-in `agy` session in the same folder.
Transport is the **agentmemory signal bus** (Claude's own `memory_signal_send` / `memory_signal_read`
MCP tools) for payloads; the **doorbell** (`clavity ring`) wakes agy. The `clavity` binary provides
the psmux/state plumbing and the bus id convention (`clavity req-id`). See the design spec at
`docs/superpowers/specs/2026-06-16-agy-remote-control-design.md`.

> **Correctness rests on the bus, not the TUI.** State detection (idle/busy) is best-effort and
> never load-bearing — a misread only affects ordering, because a doorbell sent while agy is busy is
> safely queued and processed as the next turn.

## Preconditions (bootstrap — one human step per session)
1. A human has started the session, signed in, in the target folder. Easiest is **`clavity start
   <folder>`** — it starts agy in the `claude_agy` psmux session (skip-permissions) *and* Claude
   Code in the same folder. Manual equivalent: `<psmux> new-session -s claude_agy -c <folder>` then
   `agy --dangerously-skip-permissions` (or `agy --continue`).
2. Verify reachability: `clavity state` → expect `idle`/`busy` (not `dead`). If `dead`, ask the
   human to bootstrap; do not proceed.

## Readiness — agy's MCP servers load lazily after launch

`clavity state` reaching `idle` does **not** mean agy can use the bus yet: after launch agy takes a
few seconds to load its MCP servers (agentmemory included), and its idle prompt can appear *before*
that finishes. There is no reliable pane marker for "MCP ready", so gate first contact on a **bus
round-trip** — agy can only reply once agentmemory is loaded:

1. `memory_signal_send(from=claude, to=agy, type=request, content="[req_id=<id>] [ping]")`. The
   `[ping]` marker triggers the responder's **fast-path**: agy replies `[req_id=<id>] READY`
   immediately, skipping the checkpoint and any file work (a ping never touches files).
2. `clavity ring`.
3. Poll `memory_signal_read(agentId=claude, unreadOnly=true)` for the matching reply; if none within
   ~10s, `clavity ring` again (retry a few times). Once the `READY` pong arrives, agy + its bus are live.

(The human equivalent, in the watch tab, is typing `list your active mcp servers` and seeing
`agentmemory` listed.)

## Driving conventions (agy's stated preferences)

agy defined these — follow them when phrasing requests for best results.

**Request shape — DO:**
- Lead with a clear **imperative goal** ("Implement X in `src/y.rs`").
- List the **exact file paths in scope** (saves agy searching).
- Give a **Definition of Done / how to verify** (e.g. "verify with `cargo test --test foo`") — agy is
  biased toward acting and verifying.
- State **guardrails** explicitly ("Do NOT modify `src/legacy.rs`").
- Prefer Markdown sections: `### Goal`, `### Files in scope`, `### Verification`, `### Guardrails`.
- **Carry your own context** — you and agy have *separate* context windows. If you just read a long
  log, paste the relevant stack trace into the request; agy can't see what you saw.
- For analysis/review only, say it outright: **"Just REPLY on the bus — do NOT write or edit files."**
  agy's default bias is to start coding. For scripts, say whether to *write* or *run* them.

**AVOID:**
- Vague scope ("fix the bug") — give the error/trace or the precise behavior mismatch.
- Guessing **line numbers** — agy's edit tools need exact string matches; point to function/class names.
- Interactive confirmations ("does this make sense?") — agy can't chat; it replies only when done or blocked.

**Scoping:** one focused task, or a few closely-related ones ("add endpoints A, B, C to `api.rs`").
Don't batch disparate/complex work or anything touching >5 files — split into sequential phases
(rule of thumb: one focused PR's worth per request).

**Clarify / cancel:** agy reads the bus **only at the start of a turn** — it cannot ingest new
instructions mid-turn. To pivot: `clavity cancel` (Escape) + an `alert` `[req_id=…] cancel`, let it
return to idle, then send the new request.

**Reply envelope** agy returns (`type=response`, `replyTo` = your request's signal id):
```
[req_id=<id>] done: <one-line summary>
checkpoint=<sha|clean|none>

### Changes Made
- <files changed + what>
### Verification
- <commands run + outcomes>
### Notes/Issues
- <warnings / follow-ups / blockers>
```
On failure it leads with `[req_id=<id>] failed: <reason>`. A `[ping]` gets just `[req_id=<id>] READY`.

## Send a request and await the reply
1. **Mint id + envelope:** `clavity req-id "<self-contained instruction for agy>"` prints the full
   `[req_id=<id>] <instruction>` content (or `clavity req-id` for a bare id).
2. **Put it on the bus:** call `memory_signal_send(from="claude", to="agy", type="request",
   content=<envelope>)`. **Record the returned signal `id`** (`request_signal_id`) — it is the
   robust correlation key.
3. **Ring the doorbell:** `clavity ring` (idle-gated; sends the canonical doorbell). The doorbell
   carries no payload — agy reads the request from its inbox.
4. **Await the response** (bounded loop, e.g. ≤ `timeout` seconds, poll every ~2–3 s):
   - `memory_signal_read(agentId="claude", unreadOnly="true")` — **only your own inbox** (reading
     another agent's inbox consumes its unread state).
   - A signal matches when `replyTo == request_signal_id` (robust) or the `req_id` appears in its
     `content` (fallback — agy may echo it bare or tagged).
   - On match → return it. On no match → liveness-check `clavity state`; if `dead`, abort with
     "agy session down — re-bootstrap"; else keep waiting until the deadline.
5. **On timeout:** capture context with `clavity capture` (what agy was doing) and report a typed
   timeout. Do not silently assume failure.

## Cancel an in-flight task
- **`clavity cancel`** interrupts agy's *current* turn (sends `Escape` — agy's busy footer reads
  "esc to cancel"). This is the way to stop work already in progress.
- Also post `memory_signal_send(from="claude", to="agy", type="alert", content="[req_id=<id>] cancel")`
  so the responder skips the task if it hasn't started — but the responder only reads the bus at the
  **start** of a turn, so a mid-task alert isn't seen until the turn ends. Hence `clavity cancel` for
  in-progress work; the `alert` for not-yet-started work.

## Notes
- **Payloads always go on the bus**, never in the doorbell — keeps `send-keys` to a short, fixed,
  escaping-safe line (verified: special chars survive, but the bus avoids the question entirely).
- **Long tasks:** the responder emits `type="info"` progress signals; surface them, or
  `capture-pane` to watch live.
- **Failover:** if the bus or psmux is unavailable, fall back to relaying between Claude and agy **by
  hand** — paste messages into agy's watch tab and paste its replies back. Slower, but dependency-free.
- **Teardown:** `clavity stop` kills the psmux session when you're done, so agy doesn't orphan.
- **agy writes within its workspace.** agy's native file-creation tool only accepts paths **inside
  its working folder** (its cwd — the folder `clavity start <folder>` launched it in). Paths outside
  are rejected (`not a valid artifact path; artifacts must be in …/brain/…`) and only work if agy
  falls back to its shell. So **frame requests to operate on the launch folder**; for anything
  outside it, tell agy explicitly to write via its shell. (Observed in agy's logs during the project
  audit, which targeted a different folder than agy's cwd.)
- This runbook can later be promoted to a harness skill so Claude invokes it automatically.

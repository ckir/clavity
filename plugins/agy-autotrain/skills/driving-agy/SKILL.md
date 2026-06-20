---
name: driving-agy
description: Use whenever you want a second opinion, design review, red-team, or independent cross-model perspective from the agy peer. Drive agy yourself via `clavity ask` (no user command needed). Encodes the one front door, the task-assignment protocol that stops agy misfiring, and auto-prepends the golden header.
---

# driving-agy — call agy like a model, correctly

You (Claude) drive agy. **You call it yourself, autonomously, via the `clavity` CLI in the Bash tool —
never wait for the human to type a `/command`, and never make them invoke anything.** If a task wants
an independent review / second opinion / generative design partner, just call agy.

## The one front door

Two invocation shapes — both are plain Bash calls you make directly:

- **Sync (simple, blocking):**
  `clavity ask "<payload>" --timeout 580`
  Returns agy's reply on stdout. Use for short consults. **Caveat (verified):** agy's first token is
  *minute-scale* (~9–10 min is normal), so a sync call **often times out at the cap even though agy
  replied** — the reply is still on the bus; recover it (see Recovery).

- **Async (preferred for anything non-trivial — don't burn wall-clock blocking):**
  1. `req=$(clavity req-id "agy consult")` — mint an id.
  2. Send the request on the bus as `claude → agy`, type `request`, content = the `[req_id=…]` envelope
     + your payload (use the agentmemory MCP `memory_signal_send`, or `clavity ask --no-ring` patterns).
  3. `clavity ring` — wake agy.
  4. **Go do other work.** Later, collect: `clavity await-reply --req-id "$req" --thread-id "<thread>"`
     (or read the bus scoped to that thread). agy replies on a **new thread** each time — correlate by
     `req_id` / `replyTo`, never by the request's own thread.

> Pick async by default for reviews/design consults so you keep working while agy thinks. Use sync only
> for quick exchanges where blocking a few minutes is fine.

## ALWAYS auto-prepend the golden header

Before sending **any** payload, prepend the contents of `../../knowledge/golden-header.md` (the
compiled critical anti-patterns + load-bearing assumptions). If that file is missing or empty, silently
skip it. This is what keeps every call shaped by everything the loop has learned.

## Task-assignment protocol (this is what stops agy misfiring)

agy is bold and acts on what you give it. Frame the task precisely:

- **Review / red-team / consult → loud REVIEW-ONLY banner.** Open the payload with a 🛑 banner that
  forbids edits/commits and **enumerates** the forbidden actions (no file writes, no git, no bridge
  task). Without it, agy will *execute* a task you meant as a review. End with explicit permission to
  return "no blockers."
- **Phase isolation.** Never mix research and implementation in one payload. Tag
  `[PHASE: EXPLORATION]` (gather/opine, no build) **or** `[PHASE: EXECUTION]` (build to a spec) — mixing
  fills agy's context with raw search output and degrades the build.
- **Mandatory checkpoint for mutating delegations.** If you delegate a task that changes files, the
  payload must instruct agy to make a recoverable checkpoint (`git stash` / temp branch) **before**
  touching the tree.
- **Delegated implementation → name the oracle + the done-condition + "no scope creep."** Seed the
  exact invariants/tests that define correct; tell it to STOP and report rather than adapt on a mismatch.
- **Seed invariants, don't ask it to "find bugs."** agy verifies far better than it discovers; give it
  the specific things to confirm/refute and permission that "no must-fix is valid."

## Routing — agy vs a Claude subagent

Use **agy** for an *independent second-model* view (divergent review, generative design partner, a
different provider's opinion on Claude's work) or non-blocking async orchestration. Use a **Claude
subagent** for mechanical sweeps / well-specified implementation. Don't route to agy-on-a-weak-model
what Claude should just keep. Full routing + model-selection detail: `../../knowledge/agy-capabilities.md` §F.

## Capture what you learn

The moment agy reveals something general (a new strength, a latency fact, a failure mode, or an
anti-pattern in how you prompted it), invoke the **agy-learn** skill to capture it. That is how this
file and the golden header get smarter.

## Recovery / diagnostics (not the default path)

Only when something looks wrong (a sync `ask` "timed out", agy seems stuck):
- `clavity state` → `idle | busy | dead`.
- `clavity capture --viewport` → see agy's pane (error banners, what it's doing).
- Read the bus for the reply: agentmemory `memory_signal_read(agentId=claude, unreadOnly=true)` —
  a sync `ask` that "timed out" usually has its reply waiting here (agy was just slow).
- Backend overload / daemon flap / quota lockout are real (see `../../knowledge/agy-capabilities.md` §B):
  on a silent timeout, wait, then **re-send with a fresh req-id** (a bare re-ring finds nothing if your
  request was already consumed).
- `clavity cancel` (Escape) interrupts agy's turn; `clavity doctor` preflights the session.

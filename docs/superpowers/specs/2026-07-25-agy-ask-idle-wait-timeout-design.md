# clavity-ls `agy_ask` idle-wait timeout — Design

**Status:** design (brainstormed; AGY-FIRST divergent pass folded; owner delegated the approach pick to
the consuming agent as internals-expert). Product: `clavity-dotnet` (the `clavity-ls` .NET MCP language
server). NOT part of the ship-agy-workflow epic — this is the POST-SP-D follow-up.

## Problem

`agy_ask` sends a message to agy's conversation, then waits for agy to go idle before returning agy's
reply. The wait is a single client-side cap: `CancellationTokenSource.CancelAfter(DefaultIdleWaitTimeout)`
(`AgyView.cs:106` = `TimeSpan.FromSeconds(120)`; enforced at `AgyView.cs:173`) wrapping ONE server-side
idle-wait gRPC call (`LsClient.WaitForConversationFullyIdleAsync`, `LsClient.cs:94`). On timeout the code
builds a diagnostic and throws `AgyModalHangException`, which `McpTools.cs:40` serializes as
`{"status":"possible_modal", ...}`. The user's message is already sent (`SendUserCascadeMessage` runs
before the wait guard) — only the WAIT abandons; the caller must then manually paste-retrieve agy's reply.

Observed live: a capstone review advanced agy ~66 steps and finished healthily, but the 120s cap fired
mid-review and forced a manual retrieval. The friction is ours (a too-short, elapsed-only cap), not agy
flakiness.

## Root-cause analysis (the load-bearing insight)

There are TWO idle layers:
- **Server-side (agy-ls):** the RPC reports the conversation "fully idle" after `IdleInactivityTimeoutSeconds`
  (= 30) of no activity + `IdleStabilizationSeconds` (= 2) stabilization.
- **Client-side:** the 120s `CancelAfter` is only *how long the client waits for that server "idle" signal*.

Therefore the 120s client cap fires ONLY when agy is **continuously active** for 120s (the server never
reports idle) — i.e. a healthy long turn. A genuinely inactive / modal-stuck agy produces no steps, the
server reports idle within ~32s, and the client returns normally (never trips the 120s cap). So
"possible_modal" today mostly fires on *healthy long work*, and the misnomer is tolerated for compat.

The correct fix follows directly: **do not abandon a wait while agy is still making progress; bound it by
an absolute maximum instead.** This is robust to the exact server-idle semantics: whether a stall shows up
as a server "idle" return or a client window timeout, a progress-extensible deadline with an absolute cap
behaves correctly in every case.

## Approach chosen (from the AGY-FIRST divergent pass)

agy's divergent pass produced four approaches — progress-based stall timeout (its pick,
`[VERDICT: CONSTRAINT_INVERSION]`); a configurable env-var cap; raising the constant to 600s; and a
submit-then-poll handle. Chosen (consuming-agent's call, converging with agy's pick plus a safety rail):

**Progress-extensible deadline + bounded absolute-max backstop + env knobs.**

Rejected: raising the constant alone (still elapsed-based — doesn't fix the root cause; a true runaway
wastes the whole cap). Submit-then-poll (agy's #4) — most robust against any hang and matches the
"message already sent" reality, but bloats caller turn count / tokens / transcript and changes the
`agy_ask` contract for every caller; recorded as a possible future direction, out of scope here.

## Design

### Algorithm (replaces the single `CancelAfter` wait in `AgyView.AskAsync`)

```
before          = <step count before the send>          // already computed today
lastProgress    = before
overallDeadline = now + MaxSeconds                        // MaxSeconds == 0 -> no absolute cap
loop:
    windowSecs = StallSeconds
    if MaxSeconds > 0:
        windowSecs = min(StallSeconds, secondsUntil(overallDeadline))
        if windowSecs <= 0:
            -> possible_modal(limit = "absolute_max")     // total budget exhausted
    timedOut = await WaitForConversationFullyIdleAsync(conv, Idle*, cancelAfter = windowSecs)
    if not timedOut:
        return <normal reply>                             // server reported idle: agy is done (unchanged)
    total = await <probe step count>                      // same GetCascadeTrajectoryAsync used by the diagnostic
    if total > lastProgress:
        lastProgress = total
        continue                                          // agy advanced -> reset the stall window
    else:
        -> possible_modal(limit = "stall")                // no progress within StallSeconds
```

- The **stall window** resets whenever the step count advances; the **absolute deadline** keeps counting
  and is the hard stop.
- The happy path (server reports idle before the window elapses) is unchanged — a fast reply behaves
  exactly as today.
- The step-count probe reuses the existing trajectory fetch already performed by
  `BuildTimeoutDiagnosticAsync` (`AgyView.cs:200`); no new gRPC surface.

### Configuration (follows the existing `AgyEnvironment` + `Program.cs` pattern)

Add to `AgyEnvironment`:
- `CLAVITY_AGY_IDLE_STALL_SECONDS` — max seconds with NO step progress before declaring `possible_modal`.
  Default **120** (preserves today's felt latency-to-modal-detection).
- `CLAVITY_AGY_IDLE_MAX_SECONDS` — absolute max total wait regardless of progress. Default **600**;
  **0 = unbounded** (rely purely on progress + the server idle signal).

**Role split (F1 — why two knobs):** the STALL window is the primary hang guard — it already bounds every
no-progress condition (a hung RPC, a modal-stuck agy, a dead conversation all present as "no new steps in
`StallSeconds`"). The ABSOLUTE MAX therefore guards only two residual cases: a *step-producing runaway*
(agy emitting steps forever without idling) and total caller-latency. Because the stall window is the real
safety net, the max is deliberately generous; 600s is a middle default (a legitimately long review that
exceeds it returns `absolute_max`, NOT a modal claim, with a "raise `CLAVITY_AGY_IDLE_MAX_SECONDS`" hint).
Operators who run very long reviews can raise it or set `0`; the value is not load-bearing for correctness.

Parsed in `Program.cs` when building `AgyViewOptions` (invalid / unset -> the default). Both flow into
`AgyView` as options, replacing the hardcoded `DefaultIdleWaitTimeout` usage. `DefaultIdleWaitTimeout`
becomes the default for `CLAVITY_AGY_IDLE_STALL_SECONDS` (semantic: it was always really a
no-further-idle window, not a whole-turn budget).

### Error handling / result shape

- The `possible_modal` JSON gains one additive field: `limit` ∈ `{"stall","absolute_max"}`, alongside the
  existing `status` / `operation` / `elapsedSeconds` / `hint` / `diagnostic`. Backward-compatible (a field
  addition; the `status` string and existing fields are unchanged).
- `elapsedSeconds` reports the TOTAL elapsed wait (not one window), so it is honest about how long we
  actually waited.
- The `hint` text is refined to name the actual condition: a `stall` hint keeps the terminal-modal
  guidance; an `absolute_max` hint says agy was still progressing but exceeded the max budget (raise
  `CLAVITY_AGY_IDLE_MAX_SECONDS` or investigate a runaway) — do NOT tell the user to look for a modal when
  agy was demonstrably active.
- A hung gRPC call (the RPC itself never returns) is bounded by the same window `cancelAfter`; it surfaces
  as a `stall` (no progress) — correct.
- **Progress-probe failure (F2):** if the per-window step-count probe (`GetCascadeTrajectoryAsync`) itself
  throws or times out, the loop must FAIL-TOWARD `possible_modal` (treat the window as no-progress and give
  up with a diagnostic), never spin retrying — this matches today's behavior (the diagnostic build already
  runs in the timeout path) and keeps the tool call bounded.
- **Caller cancellation (F3):** each window's `WaitForConversationFullyIdleAsync` must be linked to the
  outer `cancellationToken` (as today via `CreateLinkedTokenSource`), so a caller-initiated cancel aborts
  the whole loop promptly — the loop's own stall/max deadlines are ADDITIONAL to, not a replacement for,
  the caller's token. A caller cancel is NOT a `possible_modal`; it propagates as cancellation.

### Components touched

- `AgyView.cs` — the wait loop in `AskAsync`; consume the two new option values; `DefaultIdleWaitTimeout`
  becomes the stall default.
- `AgyEnvironment.cs` — two new env-var name constants + parse helpers.
- `Program.cs` — resolve the two env vars into `AgyViewOptions`.
- `AgyViewOptions` — two new option properties (stall window, absolute max).
- `McpTools.cs` — add the `limit` field to the `possible_modal` payload.
- `ModalGuard` / the hint builder — the `stall` vs `absolute_max` hint split.

## Testing

Extend `AgyAskIntegrationTests` (the in-proc fake-LS suite; scripts busy→idle via a `TimeSpan idleDelay`
and can script step counts):
1. **Long-but-progressing returns the reply, not `possible_modal`** — steps advance across several stall
   windows, then the fake goes idle -> normal reply. (The regression this whole change exists to fix.)
2. **Stall -> `possible_modal` with `limit:"stall"`** — never idle, no new steps within one stall window.
3. **Absolute-max -> `possible_modal` with `limit:"absolute_max"`** — steps advance forever, total exceeds
   `MaxSeconds` (set small in the test).
4. **Env parse** — `CLAVITY_AGY_IDLE_STALL_SECONDS` / `CLAVITY_AGY_IDLE_MAX_SECONDS` parsed, applied,
   invalid falls back to default, `MAX=0` disables the absolute cap.
5. **Unchanged fast idle** — a conversation that idles immediately returns the reply with no extra
   trajectory probes (happy path untouched).

Keep the tests time-scaled (small stall/max seconds via options) so the suite stays fast. `ModalGuardTests`
updated for the hint split.

## Out of scope

- Submit-then-poll handle model (agy's #4) — future direction if the block-and-wait model ever needs to go.
- Renaming the `possible_modal` status string (compat).
- The server-side (agy-ls) idle parameters — unchanged; this is purely the client-side wait.

## Open questions

None blocking. The two defaults (stall 120s, max 600s) are chosen to preserve today's modal-detection feel
while giving a healthy 5-minute review room; they are env-overridable, so the values are not load-bearing.

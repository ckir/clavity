# Consumer-experience trio (clavity-dotnet) — design

> **What this is.** Three small, cohesive improvements to the MCP surface a **Claude** uses to drive a live **agy**
> peer (`agy_look` / `agy_status` / `agy_ask`). Motivated by a first-person consumer critique: the tool works but
> (a) `agy_ask` can hang opaquely, (b) its reply is a flat list of reverse-engineered step-kind codes, and (c)
> `agy_status` can't say whether agy is busy. Design forks were taken to agy first (divergent pass, cascade
> 44a22f08) and the user; agy's central reframe is folded (below).

## The reframe that shaped this (agy-first, user-approved)

agy challenged the original "heartbeat / liveness" framing: *liveness is a human-UX construct; an LLM consumer
doesn't feel anxiety, it feels token-burn and polling loops.* Correct. So #1 is **not** a heartbeat — the call
**should** block (the consumer has nothing useful to do mid-consult, and handing an LLM partial work makes it
wander off-goal). The real need is: don't hang **silently**, and on timeout report **where** agy stopped. This
also shrinks #3 to its one honest use (the pre-fire check), since a correctly-blocking `agy_ask` rarely needs a
status probe.

## Scope: who consumes this

The consumer is an LLM (Claude), not a human at a screen. It calls the tools over MCP (stdio). `agy_ask` is a
**synchronous** call: the caller is blocked until it returns and receives **only** the final value — so anything
written to clavity-ls stderr helps a human watching the terminal, not the LLM. Every consumer-facing improvement
here therefore lives in the **tool return value**, not in logs.

---

## Feature 1 — `agy_ask`: block correctly, fail diagnostically

**Today.** `AgyView.AskAsync` sends, then awaits `WaitForConversationFullyIdle` bounded by `DefaultIdleWaitTimeout`
(120s); on timeout it throws `AgyModalHangException`, which `McpTools.RunAsync` serializes to
`{ status: "possible_modal", … }` — but with no information about *where* agy was when the wait expired.

**Change.** Keep the blocking wait and the sane bound (120s default; the bound stays well under any MCP transport
timeout — a multi-minute hang must not risk the client severing the call). On timeout, **before** surfacing the
error, fetch the current trajectory once and compute a **diagnostic** so the consumer can decide retry / wait-more
/ abandon:

```
TimeoutDiagnostic {
  int    TotalSteps;            // current step count
  int    NewAgySteps;           // agy-produced steps = TotalSteps - (pre_send_count + 1). The +1 discounts the
                                // Kind-14 user step that SendUserCascadeMessage injects, so 0 ⇒ agy produced
                                // NOTHING (it never started) — not a false "1".
  int    LastStepKind;          // kind of the newest step
  string LastStepClass;         // "assistant" | "tool" | "user" | "unknown" — derived from LastStepKind via the
                                // kind map (plan task). The hang-vs-slow signal (see below).
  string LastStepSummary;       // bounded text of the newest step (≤ 500 chars), or null
}
```

**Interpreting it (no baked-in wrong verdict, fail-safe on the unknown).** The diagnostic exposes facts; it does
NOT assert "hang." The sound reading: `NewAgySteps == 0` **and** `LastStepClass ∈ {user, assistant}` ⇒ likely a
true hang/modal (agy stalled on an LLM turn or never started) → escalate to the human. `LastStepClass == "tool"`
(with or without new steps) ⇒ agy is mid tool/command execution (e.g. a long `npm install`/`cargo build` emits
**zero** steps while running) ⇒ **slow, not hung** → retrying with a longer timeout is reasonable, do NOT abandon.
**`LastStepClass == "unknown"`** (a step kind not yet in the map — the map is point-in-time, agy may add kinds) ⇒
**treat as `tool`/slow** (AGY-AFTER r2): the dangerous error is falsely abandoning a healthy run, so the unknown
case fails toward "slow," never toward "hang." Surfaced through the
existing modal path: `McpTools.RunAsync` returns
`{ status: "possible_modal", operation: "WaitForConversationFullyIdle", hint, diagnostic: { … } }`.

> Folded from AGY-AFTER round 1: (a) the off-by-one — the injected user step made the old `NewStepsSinceSend`
> always ≥ 1; (b) a long-running tool emits 0 steps, so a naive "no new steps ⇒ hang" would tell the consumer to
> abandon a healthy build — the `LastStepClass` split fixes both.

**Out of scope (agy alternatives considered, rejected):** stderr heartbeat (human-only, not for the LLM);
continuation-token chunking (LLM-distraction risk — wanders off-goal / forgets to resume); async fire-and-forget +
bus wakeup (reintroduces the agentmemory-signal infra this variant avoids). All recorded as deliberate non-goals.

---

## Feature 2 — `agy_ask`: tripartite typed reply

**Today.** `agy_ask` returns a `BoundedTrajectory` = a flat `IReadOnlyList<BoundedStep(int Kind, string? Text)>`.
The consumer must pattern-match reverse-engineered kinds (15 = assistant, 14 = user, 90/8/23 = ?) and skip
`Text: null` steps to find "the answer." That decode tax is the complaint.

**Change.** `agy_ask` returns a purpose-built reply DTO that separates agy's answer from its activity:

```
AskReply {
  string  CascadeId;
  string? Answer;                      // CONVENIENCE: text of the TRAILING CONTIGUOUS run of assistant steps
                                       // (Kind-15, assistant_output field 20.1) at the END of the delta, joined,
                                       // within AskMaxStepChars. NULL (and JSON-OMITTED) iff the delta does NOT
                                       // end in an assistant step (ran out on a tool/error step → read Activity).
  IReadOnlyList<ActivityItem> Activity;// COMPLETE RECORD: EVERY step of the delta, in order, summarized — NOTHING
                                       // is ever dropped (incl. non-trailing assistant prose). Overlaps Answer for
                                       // the trailing run, by design.
  bool    AnswerTruncated;             // the trailing prose was size-capped — the consumer MUST agy_look for the rest.
  bool    ActivityTruncated;           // the activity list was size-capped (HEAD-dropped) — usually ignorable.
}
ActivityItem { int Kind; string Label; string? Summary }
  // Label from a known-kind map (14=user, 15=assistant, others "step <kind>" until identified). Summary = bounded
  // text for steps that carry prose (assistant/user), else null — never a tool's full output (context-bloat risk).
```

**Budget order (AGY-AFTER r3):** `Answer` is projected **first** and gets first claim on the size budget (it sets
`AnswerTruncated` only if the trailing prose alone exceeds `AskMaxStepChars`); `Activity` then consumes the
**remaining** budget — so a long run of intermediate tool steps can never starve the critical answer. **`Activity`
truncates from the HEAD (drops the OLDEST steps), preserving the tail** — the final steps, where a fatal error
manifests, must survive (`ActivityTruncated` flags it).

`Answer` is the field the consumer reads when agy actually answered. **Anchoring on the trailing assistant run —
not joining all assistant text — is deliberate** (AGY-AFTER r1): for `[Assistant("I'll run X"), Tool(FAILED)]`,
joining every assistant step would surface the optimistic *pre-failure* prose and **hide the failure**; instead
`Answer` is empty and the consumer reads `Activity`. **`Activity` is the COMPLETE timeline** (AGY-AFTER r2 — an
earlier "non-assistant steps only" draft would have *annihilated* a non-trailing assistant step like
`[Assistant("I found the bug"), Tool(cleanup)]`: excluded from both `Answer` and `Activity`). It is cheap on
context (summaries, not raw payloads). When the prose itself was capped (`AnswerTruncated: true`) the consumer
reads the whole cascade via `agy_look` (cascade id is in the reply); `ActivityTruncated` alone is usually
ignorable — the split lets the consumer tell which.

**`agy_look` is unchanged** — it keeps returning the size-bounded `BoundedTrajectory` glance. Only `agy_ask` gets
the typed reply. (`BoundedView.Summarize` is reused internally to extract assistant text + apply caps.)

**Deferred (documented, YAGNI):** a `Reasoning` field (agy's thinking, `CascadeAssistantOutput` field 3) — not
modeled today; add later if the consumer needs agy's chain-of-thought. A "semantic-diff / drop-successful-tools"
shape (agy's 2.3) is rejected: successful tool output (`git status`, `ls`) often carries the information the
consumer needs.

---

## Feature 3 — `agy_status`: busy / idle (pre-fire check)

**Today.** `agy_status` returns `{ CascadeId, TotalSteps, Truncated }` (built from `LookAsync`) — it does **not**
say whether agy is idle, working, or stuck, which is the one thing a caller checks before firing an `agy_ask`
(the "don't drive a busy agy" rule; matters when a human is using the agy UI concurrently).

**Change.** Add a cheap liveness probe and report it:

```
AgyStatus {
  string CascadeId;
  int    TotalSteps;
  string State;          // "idle" | "working" | "unknown"
  int    LastStepKind;
}
```

**Probe (primary): bounded idle-wait under a short client deadline.** Do **not** shrink the `inactivity`
parameter — that *redefines* "idle" as "quiet for 10 ms," which any normal inter-step gap (LLM TTFT, tool startup)
satisfies, yielding a **false "idle"** mid-cascade and risking an overlapping ask (AGY-AFTER round 1). Instead keep
`inactivity` **realistic** (≈ the existing `IdleInactivityTimeoutSeconds`, or ~1 s) — the true definition of idle —
and bound the *call* with a **short client cancellation deadline** (~300 ms): if `WaitForConversationFullyIdle`
**returns** within the deadline ⇒ **idle**; if the deadline **cancels** it first ⇒ **working**; an RPC error ⇒
**unknown**. The cancellation token is the probe's budget; the `inactivity` value stays honest.

**Local fast-path first (AGY-AFTER r2/r3).** Before any network probe, if an `agy_ask` is in flight **for the same
`CascadeId`**, return `State: "working"` immediately — correct (we *are* driving it), free, and it sidesteps any
same-conversation overlap between the probe's `WaitForConversationFullyIdle` and the ask's. **The in-flight tracker
MUST be keyed by `CascadeId`** (a `ConcurrentDictionary<string,_>` on the singleton `AgyView`), **not** a single
view-wide bool: `AgyView` is a process singleton and, under multi-session pairing, an ask in flight for
conversation A must NOT make an `agy_status` on idle conversation B return `"working"` (which would permanently
block driving B) — the r3 cross-conversation-contamination defect. (This is a *fast-path*, NOT the rejected
sole-source mutex: when **no** local ask is in flight for that id it still hits the network, so it does NOT go
blind to a human driving agy via the UI — the multi-actor case the probe exists for. A single Claude cannot
self-collide anyway since it is blocked inside its own ask; agy's "gRPC servers reject overlapping waits" claim is
unverified for this LS, so the fast-path is cheap insurance, not a proven necessity.)

**One live spike** confirms the network-probe semantics: whether `WaitForConversationFullyIdle` measures inactivity
from *last activity* (an already-idle conversation returns immediately, well inside 300 ms — the design assumption)
vs from *call time* (it would never return in 300 ms, breaking the probe). **The spike is GO/NO-GO for the network
probe.** If it shows call-time semantics, **do NOT fall back to a velocity probe** — velocity reads a long-running
tool (a 60 s compile emits 0 steps) as a **false `idle`**, and for a pre-fire check a false `idle` is the one
dangerous direction (it causes the very collision the check exists to prevent). The probe must **fail safe**: an
unviable network probe ⇒ `State: "unknown"` (never a guessed `idle`), and the consumer treats `unknown`
conservatively (proceed with caution / prefer to wait). In that degraded case `agy_status` still gives the
local-driving signal; its network busy/idle value is simply `unknown`.

**"Stuck/modal" is inferred, not probed** — there is no LS surface for an agy-UI modal; it only manifests as the
`agy_ask` timeout (Feature 1's diagnostic). `agy_status` reports `idle`/`working`/`unknown` only; it does not claim
`stuck`. Honest boundary.

*Client-side mutex (agy's 3.3) rejected:* tracking `_isDriving` in the MCP server is blind to concurrent human-UI
activity — exactly the multi-actor case the probe exists for.

---

## Architecture / components

All three are contained changes to the existing units (no new subsystems):

- `src/Clavity.Ls/AgyView.cs` — `AskAsync` returns `AskReply` (was `BoundedTrajectory`); on idle-wait timeout build
  `TimeoutDiagnostic`. New `StatusAsync()` (or extend the status path) runs the probe → `AgyStatus`.
- `src/Clavity.Ls/BoundedView.cs` — add the answer/activity projection used by `AskReply` (reuse existing caps).
- New DTOs (`AskReply`, `ActivityItem`, `AgyStatus`, `TimeoutDiagnostic`) — co-located with the view/result types.
- `src/Clavity.Ls/LsClient.cs` — a thin `IsIdleAsync(inactivityMs)` wrapper over `WaitForConversationFullyIdle`
  for the probe (or the velocity fallback over `GetCascadeTrajectoryAsync`).
- `src/Clavity.Mcp/McpTools.cs` — `AgyAsk` returns the serialized `AskReply`; `AgyStatus` returns `AgyStatus`;
  `RunAsync`'s modal path includes the `TimeoutDiagnostic`.
- `AgyModalHangException` — carries the `TimeoutDiagnostic` (or a sibling exception does).

## Data flow

`agy_ask` → connect/resolve → fetch pre-send trajectory (count delimits the delta; already happens) → send →
`WaitForConversationFullyIdle`(bounded) → **(idle)** fetch trajectory, project delta into `AskReply{Answer,
Activity}` → return; **(timeout)** fetch trajectory, build `TimeoutDiagnostic`, return via the modal path.
`agy_status` → connect/resolve → probe (`IsIdleAsync` micro-timeout) + one trajectory read → `AgyStatus`.

## Error handling

- Timeout is **not** an exception-to-the-consumer black box anymore — it returns the structured diagnostic. The
  driver never crashes; it gets an actionable `silent` vs `progressing` signal.
- Probe failure (RPC error/unreachable) ⇒ `State: "unknown"` (never throw from a status check).
- All existing connect/boot-race/`AgyConversationPendingException` behavior is unchanged.

## Testing

- **Unit (`BoundedView` answer/activity projection)** — the highest-value tests, pure, no server:
  - delta ends in an assistant step ⇒ `Answer` = its text, `AnswerTruncated` false;
  - delta ends on a tool step but an earlier assistant step exists (`[Assistant("found bug"), Tool]`) ⇒ `Answer`
    **empty** AND the assistant prose **present in `Activity`** (the r2 annihilation regression — the single most
    important test here);
  - trailing contiguous assistant run of 2 steps ⇒ both joined into `Answer`;
  - over-cap prose ⇒ `AnswerTruncated` true; over-cap activity only ⇒ `ActivityTruncated` true, `AnswerTruncated`
    false (the split).
- **In-proc fake LS** (`FakeAskLs` pattern) — `TimeoutDiagnostic` on a never-idle script: only the injected user
  step present ⇒ `NewAgySteps == 0` (the off-by-one regression); `LastStepClass` drives interpretation
  (tool/unknown ⇒ slow, user/assistant ⇒ hang). Probe: fake answers `WaitForConversationFullyIdle` fast when idle
  / blocks past the ~300 ms deadline when working ⇒ `State: idle|working`; an `AgyView` with an in-flight ask ⇒
  `State: working` **without** a network call (the fast-path); probe RPC error ⇒ `State: unknown`.
- **Live acceptance** (`Category=LiveAgy`, excluded from CI) — **the one live-agy dependency**: the GO/NO-GO spike
  for the deadline-bounded probe (does `WaitForConversationFullyIdle` measure inactivity from last-activity, so an
  idle conversation returns inside 300 ms?). On NO-GO, `agy_status` ships with network `State: unknown` + the
  local fast-path only (no velocity fallback).

## Backward compatibility (measured)

`agy_ask` and `agy_status` change their JSON return shape. **Verified by grep (AGY-AFTER round 1): no skill or doc
parses the old shape** — `plugins/**.md` contains zero references to `BoundedStep`/`Steps`/`Kind`, and the driving
skills never describe a parse schema. So there is **no lockstep skill rewrite required**: the new DTOs are
self-describing JSON and the LLM consumer reads `Answer` / `State` directly. (agy's review claimed the skills
hardcode the old schema and would break — measured false; recorded so the claim isn't re-raised.) The only
contract consumers are the MCP tools' own callers (Claude), which read fields by name.

## Out of scope

- Heartbeat / streaming / chunking / async-webhook for `agy_ask` (Feature 1 non-goals, above).
- Modeling agy's reasoning field, tool-step payloads, or a semantic-diff reply (Feature 2 deferrals/rejections).
- A `stuck` state in `agy_status` (no LS surface).
- Any change to `agy_look`, the send path's model resolution (separate epic item #3), or the connect/boot race.

## Exhaustiveness self-audit

- **Contracts/shapes:** `AskReply`, `ActivityItem`, `AgyStatus`, `TimeoutDiagnostic` fully specified (field names +
  types + semantics). ✓
- **Placeholders:** none. The one open empirical question (micro-timeout debounce) is explicitly bounded to a
  named live spike with a named fallback (velocity) — resolved in the plan, not papered over. ✓
- **Edges:** delta ends on a non-assistant step ⇒ empty `Answer`, failure visible in `Activity` (no hidden
  failure); off-by-one user step discounted in `NewAgySteps`; slow-tool vs hang via `LastStepClass`; over-budget
  reply (`Truncated` + `agy_look` pointer); probe false-idle race (deadline-not-inactivity); probe failure
  (`unknown`); unknown step kinds (`"step <kind>"` label / `LastStepClass:"unknown"`); human-concurrent-UI (why the
  mutex is rejected). ✓
- **Requirement → section:** each of the 3 wants → its own feature section + architecture/testing coverage. ✓
- **AGY-AFTER round 1:** 5 findings — 4 folded (timeline-anchoring, off-by-one, slow-tool-vs-hang, false-idle
  race), 1 (skill breakage) measured false and recorded. ✓
- **Carried to the plan (not gaps):** (a) build the step-kind → class map (assistant/tool/user/unknown) from the
  golden, powering both `ActivityItem.Label` and `LastStepClass`; (b) the live spike for the
  deadline-bounded idle probe (last-activity vs call-time semantics) + the velocity fallback; (c) exact placement
  of the new DTOs.

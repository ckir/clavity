---
name: clavity-ls-driving
description: Use to drive a paired agy peer via the clavity-ls MCP tools (agy_look / agy_status / agy_ask) — when to look vs ask, write/quota semantics, handling waiting/modal results, and convening multi-lens review panels.
---

# Driving agy with clavity-ls (MCP)

You (Claude) drive a paired agy over its Language Server via three MCP tools exposed by `clavity-ls`:

- **`agy_look`** — read the active conversation's bounded trajectory. No quota; safe to call freely.
- **`agy_status`** — lightweight liveness pre-fire check; returns `{ CascadeId, TotalSteps, State, LastStepKind }`.
  Its `CascadeId` is the session's cascade id — the **same** id `agy_ask` returns for that session, so you can
  correlate a pre-fire `agy_status` with the `agy_ask` you then send.
- **`agy_ask`** — send a message and return agy's reply. **This is a quota-consuming WRITE** that posts a
  human-visible message in agy's tab. Use it for an independent second-model review / generative design
  partner — not for chatter. Prefer `agy_look` when you only need to observe.

## Results you must handle

- **`waiting_for_human`** — agy is up but has no conversation yet. STOP and wait for the human to start or
  continue the agy session; do NOT loop-retry.
- **`possible_modal`** — the idle-wait hit the client timeout. agy may have a blocking modal open — **or** the
  turn is simply LONG and still progressing (a big multi-seat / multi-part ask can outrun the wait). Before you
  surface a "hang": re-check `agy_status` and compare `TotalSteps` to before you fired — if it advanced, agy is
  working, so wait, don't retry. A reply produced *after* the timeout is **not** auto-redelivered: retrieve it
  with a minimal follow-up `agy_ask` ("resend your last result") once agy is idle, and correlate by content (or
  by `CascadeId`). Never blindly re-fire the original ask. Keep single asks small/pure-text to stay inside the
  wait window.
- **`Answer == null` — NOT empty, NOT an error.** `Answer` is only set when agy's turn ends on assistant
  prose. When agy *tool-terminates* a turn (writes its verdict, then does a trailing tool step like a memory
  write and yields), the delta ends on a non-assistant step and `Answer` is null **by design** ("failure not
  hidden" — the tool step could have failed). The prose is NOT lost: read the **last assistant (Kind-15) step
  in `Activity`** — the projection gives that step the full Answer budget, so a tool-terminated verdict survives
  intact. Do **not** treat null `Answer` as "no reply" and do **not** blindly re-ask; only re-ask if `Activity`
  has no assistant step, or `ActivityTruncated` is true and the tail you need was dropped.

## Task-assignment protocol — what stops agy misfiring

<!-- KEEP IN SYNC WITH clavity-driving (plugins/clavity-classic/skills/clavity-driving/SKILL.md) -->

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

## Multi-lens panels — the high-leverage review mode

A single-persona review under-covers a high-stakes artifact. For serious review, in ONE `agy_ask` instruct agy
to convene a **panel**: several expert SEATS at once, each under its own heading, each hunting a DIFFERENT
flaw-class, each free to say "no new findings", closing with a one-line **PANEL VERDICT**. Panels reliably
catch what a solo pass misses.

**Trigger gate — state it before convening.** Name the concrete build or spend this artifact will drive. If
you can't name one, it's a single-pass artifact — do NOT panel it. Reserve panels for high-leverage specs,
plans, designs, and correctness-critical code.

**Run rounds, not one shot:**
1. Convene the panel inside the REVIEW-ONLY banner (above). Each seat reports findings or "no new findings".
2. Between rounds: fold the valid findings into the artifact, then re-convene with (a) the running
   **"already-folded — do NOT re-raise"** list pasted in, and (b) rotated/refreshed seats so each round hunts
   a NEW flaw-class instead of re-deriving solved ones.
3. STOP when a full panel lands no live challenge — or when agy starts reasoning from a superseded version of
   the artifact (that drift is the diminishing-returns signal, not a new defect).

**Verify before folding.** agy makes confident false claims, and a panel does NOT self-consistency-check —
seats may contradict each other or an earlier round. Confirm any bare factual claim by measurement before you
fold it; reject the false ones. One panel is the FLOOR, not the ceiling — review is investment, not cost.

### Seat palette — a priority reminder, NOT a required roster

You compose the optimal panel for THIS artifact. The seats below are a starting palette: use the ones that
fit, drop the ones that don't, and **invent new seats** when the artifact needs a lens not listed. Bias wide
(many seats) for high-leverage work.

- **General-adversarial** — logic gaps, contradictions, unhandled cases ("what breaks this?").
- **Security / threat-model** — trust boundaries, injection, privilege, adversarial worst-case inputs.
- **Release / ops** — deployability, failure recovery, observability, upgrade/rollback.
- **API / wire-contract** — interface stability, serialization/encoding, versioning, cross-component shape agreement.
- **UX / operator** — how it feels to the consumer (human or agent): error legibility, discoverability.
- **Performance / resource-efficiency** — steady-state cost: algorithmic complexity, memory, latency/throughput, contention (distinct from security's adversarial exhaustion).
- **Automated-security / scannability (SAST/SCA/DAST)** — will automated scanners find the flaw, or is there a blind spot? dependency/CVE/license gates kept honest; parse/IPC boundaries fuzzing-ready and failures observable.
- **Rotating bench** (swap in per artifact): concurrency/async-correctness · platform-specific · data-corruption/stream-integrity · scope-discipline (YAGNI) · thesis-coherence · boot/lifecycle · test-oracle adequacy.

## agy is a peer, not an oracle — the decision loop

The value of a paired agy is a *second model* on your work. Two disciplines get most of it, and one caveat
keeps it honest:

- **Consult FIRST on hard forks.** On a real design / scope / approach / sequencing fork, get agy's read
  BEFORE you commit to a path — a second model catches what you rationalize past. But the **human owns the
  decision**: hand them BOTH agy's recommendation AND your own, and let them choose. Never delegate the final
  call to agy.
- **Review AFTER you author.** When you finish a spec, plan, or design, proactively route the finished
  artifact to agy (REVIEW-ONLY, or a full panel) BEFORE presenting it to the human — don't wait to be asked.
- **Verify, never rubber-stamp.** agy is bold and states confident false claims. Confirm any bare factual
  claim by measurement before acting on it, and fold agy's findings together with your OWN assessment —
  rubber-stamping its praise (or caving to a wrong objection) throws away the second opinion you paid for.

## Injection is automatic — do NOT prepend the golden header yourself

`clavity-ls` reads `%USERPROFILE%\.clavity\golden-header.md` (when the agy-autotrain add-on is installed) and
prepends it to every `agy_ask` for you. Do NOT read or prepend it manually. If the file is absent (add-on not
installed), the binary simply skips it and you drive with this baseline protocol.

If the human asks you to permanently remember a project rule and no `agy-curate` skill is present, permanent
learning needs the **agy-autotrain** add-on — tell them to re-run the clavity installer and tick it.

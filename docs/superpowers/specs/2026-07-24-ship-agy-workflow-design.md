# Ship the agy-driving WORKFLOW to users — Design

**Status:** Design endorsed by the driving session (2026-07-24). Panel-hardened: AGY-AFTER round 1 folded
(driving-session solo panel + live agy escalation + one AGY-NEGOTIATE turn). Rounds continue until GREEN;
owner spec-review is the final gate before any plan. Decomposes into sub-projects; each gets its own plan.

**Goal:** Ship the owner's four-part peer-driving workflow — **AGY-FIRST → AGY-NEGOTIATE → AGY-AFTER →
AGY-CAPSTONE** — into the shipped clavity driver plugins, so any user running the superpowers flow gets the
disciplines firing automatically at the right workflow moments, gated by superpowers' own approval
breakpoints. The workflow has proven its value in this project; this productizes it out of the author's
personal `~/.claude` config.

**Supersedes** the ME1-centric epic `2026-07-22-ship-agy-disciplines-design.md` (`c5da9d9`) for this effort.
ME1 (the consult guard) and AGY-LEARN (the knowledge loop) are **out of scope** here.

---

## Posture: best-effort prompt-discipline, not a code-enforced sandbox (panel R1)

This design ships **best-effort, in-flow prompt-discipline** — the same mechanism the already-shipped
AGY-AFTER discipline and the entire superpowers flow use: a hook injects a directive; the active LLM obeys
it. It is deliberately **NOT** a code-enforced sandbox. The honest consequences, which the rest of this spec
does not paper over:

- **Firing is a directive, not a guarantee.** An injected `additionalContext` directive is a strong nudge
  the LLM *usually* obeys — not a deterministic trigger. The disciplines may occasionally not fire.
- **The `[VERDICT]` token and verify-by-measurement are self-reported**, not parsed or enforced by code. The
  LLM could confabulate them. Forcing functions (below) make hollow compliance *visible to the human at the
  superpowers breakpoint*; they do not make it impossible.
- **The correct bar is "materially better than the unaided baseline," not determinism.** A seatbelt reminder
  you can ignore still lifts the population outcome. This is proven in-project (this very spec's review caught
  two real regressions via exactly this prompt-discipline).

Where a stronger guarantee is cheaply available it is added as a **forcing function** (Decision 2). Where a
hazard is *system-level* and cannot be prompt-fixed (Decision 1, the firing trigger), it is fixed
**structurally in the hook** before shipping — not left to prompt compliance.

---

## What the value actually is

The value is **not** "consult agy." The external peer is confidently wrong often enough that naively folding
its advice would *degrade* output (observed: agy's own proposed fix for a 0-byte-oracle crash was wrong; its
verdicts carry identical confidence right or wrong). **The load-bearing discipline is what wraps the
consult:**

1. **Verify every bare factual claim by measurement before folding it** — strengthened by a forcing function
   (Decision 2.6): the driver must **quote the measured output** it claims, so an empty "verified" is visibly
   hollow to the human. (This is best-effort, per Posture — a forcing function, not a lock.)
2. **Negotiate a synthesis on disagreement** rather than defer-to-peer or dismiss-the-peer.

A shipped skill that fires a consult but omits the verify-and-quote step is a footgun (it folds
confabulations unchecked) and is disallowed.

---

## Background: what ships today vs what is personal

| Discipline | What it does | Ships today? | Where |
|---|---|---|---|
| **AGY-AFTER** | adversarial multi-round panel over a finished artifact | ✅ yes | `adversarial-panel-review` skill + `agy-after-reminder.sh` (byte-identical in both driver plugins, kept honest by `check-seed-artifacts-synced.sh`) |
| **AGY-FIRST** | consult agy on a design/scope fork before deciding | ❌ personal | `~/.claude/CLAUDE.md` rule 1 + `~/.claude/hooks/agy-seam-inject.sh` (`*brainstorm*` arm) |
| **AGY-NEGOTIATE** | formal driver↔peer negotiation on disagreement | ❌ not formalized | author types "negotiate with agy" ad hoc |
| **AGY-CAPSTONE** | rounds-until-green review of committed code before "done" | ❌ personal | `~/.claude/CLAUDE.md` rule 1c + `agy-seam-inject.sh` (`*subagent-driven-development*|*executing-plans*` arm) |

**Verified fact about today's mechanics:** everything is **nudge-based**. `agy-seam-inject.sh` is a
`PreToolUse(Skill)` hook injecting `additionalContext` on a skill match; `agy-after-reminder.sh` is a
`PostToolUse(Write|Edit)` hook injecting context on a spec/plan write. **A Claude Code hook cannot invoke the
MCP `agy_ask` tool — only the LLM can** — so no hook "runs" agy; it directs the already-active LLM to. This
is the mechanism this design productizes (nudge → "run now" directive), NOT a headless shell-out.

Transports differ; the shipped AGY-AFTER skill already parameterizes per transport and is the pattern:
- **clavity-dotnet** → MCP `agy_ask` (a `clavity-ls` server), after an `agy_status` idle-check.
- **clavity-classic** → `clavity ask --review-only` CLI (psmux).

---

## Product model

| Layer | Install | Contains |
|---|---|---|
| **Tier 1 — driver** (`clavity-classic` **or** `clavity-dotnet`) | required (pick one) | the four discipline skills + the auto-fire hook + the (already-shipped) AGY-AFTER skill/hook |
| **Prerequisite for auto-fire ONLY** | superpowers | the disciplines auto-fire off superpowers workflow phases; **without superpowers they remain manually invokable** but do not auto-fire |

superpowers is a prerequisite for the **auto-fire** experience only — not for the disciplines to exist or
work (Decision 3). "Prerequisite" everywhere in this spec means "prerequisite for auto-fire."

---

## Decision 1 — Mechanism: best-effort auto-fire in-flow, LLM-executed, superpowers-gated

The disciplines ship as **first-class manually-invokable skills** per driver plugin, **plus a per-plugin
auto-fire hook** (the productized `agy-seam-inject.sh`), upgraded from "remind me to consider agy" to **"run
agy now as part of this phase"** (a directive — best-effort per Posture, not a guarantee).

- The consult is **LLM-executed inside the active session** — never a headless hook shelling out. This is
  what keeps it safe: no blocking-hang of the user's shell, no headless agy loop that could mutate files.
- **Consults are framed REVIEW-ONLY.** Every auto-fired ask states its review-only scope (the disciplines
  produce advice/review, not mutations) — a lesson paid for in-project (a bare "review-only" once let the peer
  write to the tree anyway). The shipped skills frame the ask correctly; the full guard that *verifies* the
  peer honored review-only is ME1 (deferred, out of scope here).
- **The human approval gate is superpowers' own breakpoints** (present-approaches, review-spec, review-plan,
  completion checkpoint). The user approves there, not per-discipline.
- **`.no-agy` kill-switch** (cwd or `~/.claude`) suppresses all auto-fire, mirroring the existing hooks.
  **But it must not silently disable (panel R2-S4):** a forgotten global `~/.claude/.no-agy` would silently
  kill the disciplines for every project. The SessionStart liveness line (Decision 3) MUST still announce
  when `.no-agy` is suppressing them (*"[AGY-DISCIPLINES] suppressed by .no-agy at <path>"*). *(I diverged
  from agy's proposed fix — it wanted the global scope removed. Kept it for consistency with the already-
  shipped AGY-AFTER hook, which honors `~/.claude/.no-agy`; making it LOUD addresses agy's actual concern —
  the silence, not the global option — without fragmenting the kill-switch across disciplines.)*
- **Debounce (F9 — restored R1; lifecycle fixed R2).** The hook MUST debounce: it fires a discipline's
  directive **at most once per phase transition**, never once per raw skill invocation (an iteratively-invoked
  skill would otherwise inject the directive repeatedly — token drain + context noise). **The marker MUST have
  a real clear/expire lifecycle (panel R2-S1):** keyed to the current `HEAD` commit hash (so a genuinely new
  cycle — a new commit, a later spec on the same branch — re-fires) and/or cleared on a known phase transition
  (push/merge). A marker with no expiry keyed only to the branch would **permanently silence** the discipline
  for the branch's life — forbidden. **The marker is set only AFTER a consult actually runs; a
  `SKIPPED-UNREACHABLE`/failed consult MUST clear (or never set) it (panel R2-S2)** so the next trigger
  retries — a debounced *failure* must not swallow the only attempt. **Marker ownership (panel R3-S1):** the
  marker is WRITTEN by the discipline **skill** (which runs in-flow and knows the consult's outcome — it
  records "consulted at `HEAD <hash>`" only on a completed consult) and merely READ by the **hook** to decide
  whether to inject. A `PreToolUse` hook fires *before* the consult and cannot itself set-after/clear-on-skip,
  so it must not own the marker; an LLM that ignores the injected directive simply never writes a marker, and
  the next trigger re-fires (best-effort non-compliance self-heals to a retry). Marker files namespaced per
  plugin (Decision 4).

### Seam → discipline map
| superpowers signal | Discipline | Directive (best-effort) |
|---|---|---|
| `*brainstorm*` skill invoked | **AGY-FIRST** | at the approaches step, run a divergent agy consult on the fork; end with a `[VERDICT]` token (Decision 2) |
| `Write|Edit` on `docs/superpowers/(specs|plans)/*.md` | **AGY-AFTER** | run the adversarial panel over the artifact — **already shipped** (`agy-after-reminder.sh`); sole AGY-AFTER trigger |
| completion of `*subagent-driven-development*` / `*executing-plans*` | **AGY-CAPSTONE** | rounds-until-green over the committed diff; human adjudicates GREEN; end with a `[VERDICT]` token |

- **AGY-AFTER double-fire fixed (F3, panel R1):** the artifact-write hook is the **sole** AGY-AFTER trigger.
  A separate `*writing-plans*` skill seam would double-fire on a written plan (both the Skill hook and the
  artifact hook see it), so it is **dropped** — a plan write is already an artifact write.
- AGY-NEGOTIATE has no superpowers phase — it is a conditional sub-step of AGY-FIRST/CAPSTONE (Decision 2).

### Structural gating fix — AGY-CAPSTONE completion trigger (F4/agy Seat 1, panel R1) — MUST resolve before ship
`PreToolUse(Skill)` fires at a skill's **start**, and iterative skills (`executing-plans`) are invoked many
times — so hooking `PreToolUse(Skill)` would inject the capstone directive N times = unbounded spam. agy's
panel established this is a **system-level** hazard: it cannot be prompt-fixed (the LLM sees N injected blocks
regardless of what they say). The capstone auto-fire therefore MUST use a **once-per-completion** trigger,
resolved structurally in the SP-B/SP-C plans before shipping. Candidate mechanisms (decide in-plan):
(a) hook-level debounce keyed to a per-branch "capstone-done" marker; (b) bind to the `finishing-a-development-
branch` skill as the genuine completion signal instead of `executing-plans`; (c) a git `pre-push` hook as the
"done" proxy. Until one is chosen and tested, AGY-CAPSTONE ships **manual-invocation only**; auto-fire for it
is gated on this fix.

---

## Decision 2 — AGY-NEGOTIATE, formalized (agy-refined, panel R1)

Today the owner triggers it manually ("negotiate with agy") on an observed driver↔peer disagreement and
wants "the optimal AGREED solution from both agents to approve." Formalized:

1. **Verdict token (self-reported, ASCII-only — F7 fixed).** Every AGY-FIRST and AGY-CAPSTONE consult ends
   with exactly one token. **ASCII only — no em-dash** (a non-ASCII token is a mojibake risk; this project has
   hit `ΓÇö` corruption). Grammar:
   - `[VERDICT: ALIGNED]` — driver and peer agree; proceed.
   - `[VERDICT: REJECTED - <measured reason>]` — the peer is factually wrong, killed by measurement; the
     driver overrides without negotiation and **quotes the measurement that killed it**.
   - `[VERDICT: NEGOTIATE - <one-line material reason>]` — a *material* disagreement remains.
   The token is **self-reported, not code-parsed** (Posture). The human sees it at the superpowers breakpoint;
   a missing/malformed token is itself a visible signal something went wrong.
2. **Materiality floor.** AGY-NEGOTIATE engages only on `NEGOTIATE`, emitted only when the delta changes
   **architecture, performance, or security** — never style/naming/trivia (those → `ALIGNED`, driver yields).
3. **Hard round cap (default `MAX_NEGOTIATE_ROUNDS = 2`, tunable).** Round 1 driver presents measured
   evidence / peer counters; round 2 driver attempts synthesis.
4. **Impasse default (no forced synthesis).** Not converged at the cap → the driver declares **IMPASSE**,
   documents both positions, and hands the tie-break to the human at the superpowers breakpoint.
5. **Manual backstop.** The owner's "negotiate with agy" stays a manual trigger regardless of token.
6. **Verify-by-measurement forcing function (the spine, F5 strengthened).** Before folding any peer factual
   claim, the driver must **quote the measured output** (tool stdout / file line) it relies on. A `REJECTED`
   or a fold with no quoted measurement is visibly hollow to the human. Best-effort (Posture), not a lock.
7. **agy-unreachable outcome (F9 defined R1; recorded R2).** If the consult cannot run (no live peer / no
   auth), the driver emits `[VERDICT: SKIPPED-UNREACHABLE]`, and **proceeds** — it never hangs and never
   hard-blocks "done." A skip MUST (a) clear/not-set the debounce marker so the next trigger retries
   (Decision 1), and (b) be written to an **out-of-band durable record** (an append-only log line the user can
   check), not reported only in chat — a chat-only report can be summarized away by the LLM (the ME1 F19
   lesson: a relayed warning is not a guaranteed-visibility channel). Best-effort: a skipped consult is
   surfaced out-of-band, never silently swallowed.

> Cap note: the standing "repeat-until-green" waiver applies to **AGY-CAPSTONE panels**, a different
> discipline. A cap on **negotiation** is safe because the human tie-breaks at the cap.

---

## Decision 2b — AGY-CAPSTONE round cap (F8 — restored, panel R1)

The shipped AGY-CAPSTONE runs "rounds-until-green" over committed code. On a stranger's budget an unbounded
loop is a token-drain hazard (the peer can re-assert a confabulated defect every round). The shipped capstone
MUST carry a **hard `MAX_CAPSTONE_ROUNDS` ceiling (default tunable) + a human override at the cap** — the same
halt-and-ask precedent as `adversarial-panel-review`'s round-3 halt. GREEN is **human-adjudicated** (the peer
cannot self-declare GREEN). (The author's personal capstone waives the cap for their own use; the SHIPPED
build carries it.)

**Human-override feedback loop (panel R2-S3).** A self-reported `[VERDICT: ALIGNED]`/GREEN is not the end of
the gate — it is a *proposal* the human confirms or rejects at the superpowers completion breakpoint. The
skill MUST make the override concrete: if the human rejects a self-declared GREEN (or names an unaddressed
defect), the driver **re-enters capstone rounds** on that defect rather than treating the book as closed.
Without this loop the "human adjudication" is an illusion — the human could only veto by restarting the whole
flow. The re-entry counts against `MAX_CAPSTONE_ROUNDS`.

---

## Decision 2c — Execution mode: async-deferral (creative) vs sync-gate (completion)

From first-hand use, the disciplines split by whether blocking is correct — and the shipped mechanism already
reflects this (the personal seam-inject hook tags each seam `MODE=async-deferral` or `MODE=sync-gate`; the
shipped `agy-after-reminder` folds "before presenting to the user").

- **Async-deferral — AGY-FIRST + AGY-AFTER (the creative phase).** agy latency is minute-scale; blocking the
  user's brainstorming/artifact flow on it is bad UX. Fire the consult (in the background where the transport
  allows), let the user keep working, and FOLD agy's reply before the artifact is finalized or acted on.
  **Interruption policy:** if the user proceeds before agy replies, continue — but HALT and ALERT if the late
  reply flags a severe defect. (This is exactly the shipped AGY-AFTER behavior.)
- **Sync-gate — AGY-CAPSTONE (the completion gate).** Its DONE-CONDITION *is* the review: the driver MUST NOT
  declare the plan complete until the capstone is GREEN or explicitly waived. Deferring it async would let
  "done" slip through before the review lands — defeating the gate. It blocks the agent's **completion claim**
  (not the user's shell), per Decision 2b's human-adjudicated GREEN + override loop.
- **AGY-NEGOTIATE** inherits its parent consult's mode (it runs inside a FIRST/CAPSTONE flow once a `NEGOTIATE`
  verdict is emitted).

This axis is why AGY-CAPSTONE uniquely cannot be "fire and forget" — its value *is* the blocking, whereas
AGY-FIRST/AFTER's value survives being deferred.

---

## Decision 3 — No-superpowers degradation & runtime deps: LOUD, never silent (agy-refined, panel R1)

A user who installs a driver but not superpowers, or on a bare machine, must never be silently stranded.

1. **Disciplines stay manually invokable** — they work without superpowers; only auto-fire is lost.
2. **Loud SessionStart notice**, prefixed with a distinct **`[AGY-DISCIPLINES]`** tag so it stands out from
   boot text: *"agy disciplines need superpowers to auto-fire — install it, or invoke the skills manually."*
3. **Silent-version-break guard.** The SessionStart check verifies the **specific hooked superpowers skill
   IDs still exist**, not merely that superpowers is installed; on a miss, fail loud
   (*"[AGY-DISCIPLINES] superpowers installed but expected workflow hooks not found — auto-fire disabled"*).
   **Robustness caveat (agy Seat 3):** superpowers exposes no stable API for its skill IDs, so the check must
   be resilient to install-path/OS differences and must **fail toward a loud, actionable message, never a
   false-positive that disables a working setup**; SP-D decides the exact probe (and may scope it to a
   presence check + a documented "if auto-fire seems dead, run the skill manually" line rather than a fragile
   ID probe).
4. **Runtime-dependency guard (F6, panel R1).** The hooks require `jq` and `bash` on PATH; a bare Windows box
   may lack them → the hook silently no-ops = a silent-orphan by another door. Each hook MUST detect its deps
   and, if absent, emit a loud `[AGY-DISCIPLINES]` "guard inactive: missing <dep>" line — **never a silent
   no-op**. SP-C decides detection placement (per-hook preamble vs a SessionStart probe).

### Edge cases (resolve in the plans)
- superpowers present but a hooked skill renamed → 3.3 fail-loud path.
- agy unreachable at fire time → Decision 2.7 (`SKIPPED-UNREACHABLE`, proceed).
- **Both drivers installed** (mid-migration classic→dotnet): skills are **plugin-namespaced**
  (`clavity-dotnet:X` vs `clavity-classic:X`), so same-named byte-identical skills do **not** collide — the
  shipped byte-identical `adversarial-panel-review` proves this in v13. The residue is **hook double-fire**
  (both plugins' hooks see the same phase → two paid consults). **Bounded by the product rule (panel R2):
  the two drivers are MUTUALLY EXCLUSIVE — run one, never both** — so both-installed is a *transient migration
  state*, not steady-state. Resolution: **accept the transient** (per-plugin state namespacing prevents
  corruption; at worst a duplicate consult during migration), document it, and do NOT engineer cross-plugin
  coordination for an unsupported configuration.

---

## Decision 4 — Packaging: Option A (per-plugin self-contained)

Each driver plugin ships its **own copies** of the discipline skills + the auto-fire hook, parameterized per
transport — mirroring how AGY-AFTER already ships (duplicated, kept honest by a sync-check). Standalone
installability is the supreme virtue; a shared core fights it.

- **Transport delta lives in the skill body** as a single inline clause per skill (dotnet `agy_ask` after
  `agy_status`; classic `clavity ask --review-only`) — hooks stay transport-agnostic. **This is why
  same-named skills stay byte-identical across plugins** (the delta is inside the shared body, resolved by the
  driving agent's own transport), so `check-seed-artifacts-synced.sh`'s byte-identical assertion holds — no
  namespace/anti-drift conflict (refutes panel Seat 4's dilemma).
- **State files namespaced per plugin** — the debounce marker + any capstone-done marker live under a
  per-plugin path (not a shared `${TMPDIR}` slot), so two installed drivers can't race/clobber (edge case).
- **Anti-drift:** extend `scripts/check-seed-artifacts-synced.sh` (`just seed-sync-check`, in `lefthook.yml`
  pre-push) — add the new skill files + any new hook scripts to its byte-identical enumeration and its
  `scripts/README.md` row. If the auto-fire hook adds a new `hooks.json` event key, add a mirrored `jq -S`
  diff for it.

---

## Sub-project decomposition (epic — each SP its own plan)

- **SP-A — AGY-FIRST + AGY-NEGOTIATE skills + the `[VERDICT]` contract.** Coupled (NEGOTIATE is a sub-step of
  FIRST). Per-plugin, per-transport. The quote-the-measurement forcing function + ASCII token grammar +
  materiality floor + round cap + impasse + `SKIPPED-UNREACHABLE`. Manual-invocation tests.
- **SP-B — AGY-CAPSTONE skill.** Per-plugin rounds-until-green over committed diff; **hard round cap +
  human-adjudicated GREEN** (Decision 2b); quote-the-measurement spine; do-not-re-raise ledger; `[VERDICT]`.
- **SP-C — the productized auto-fire hook.** Per-plugin; nudge→directive; the seam→discipline map; the
  **debounce** (F9); the **runtime-dependency guard** (F6); the `.no-agy` kill-switch; **and the resolved
  capstone completion-trigger** (the Decision 1 structural gate) — auto-fire for capstone is blocked until
  this lands.
- **SP-D — docs + tests + anti-drift.** superpowers-prerequisite-for-auto-fire messaging + the Decision 3
  degradation/version/dep guards; the **new hook-activation test category** (synthetic `PreToolUse(Skill)` /
  `PostToolUse` payload → assert the right directive fires once for a matching phase, silent otherwise, and
  suppressed under `.no-agy`); extend `check-seed-artifacts-synced.sh`.

**Order:** SP-A → SP-B → SP-C → SP-D. SP-A/SP-B define the skills SP-C's hook fires; SP-C is gated on the
capstone-trigger fix; SP-D documents/tests/drift-guards.

**Cheap validation spike first (F10).** Before committing the full build, SP-C runs a small spike measuring
the single biggest risk: does an injected "run now" directive reliably make the agent execute the consult in
practice? Measure it; don't assume it.

---

## Testing posture

Per-plugin, reusing the AGY-AFTER shipping pattern (duplicated artifact + sync-check). **New test category
(none exists):** pipe a synthetic hook payload through each auto-fire hook and assert (a) a matching phase →
the correct discipline directive **once** (debounce holds on repeat invocation); (b) a non-matching skill →
silent (`exit 0`); (c) `.no-agy` present → suppressed; (d) a missing dep → the loud `[AGY-DISCIPLINES]` line,
never a silent no-op. Skill-level tests assert the ASCII `[VERDICT]` grammar and the manual-invocation path
works without superpowers.

---

## Non-goals / explicitly deferred
- ME1 (consult guard) and AGY-LEARN (knowledge loop) — out of scope this effort.
- **Code-enforced determinism** — a non-goal by design (Posture); the disciplines are best-effort
  prompt-discipline. Deferred: code-wrapping the classic `clavity ask` path to *enforce* the verify step
  (possible later since classic owns its CLI; not now).
- A headless auto-run mechanism (hook shelling out to `clavity ask`) — rejected (blocking-hang / silent
  mutation); the disciplines run in-flow, LLM-executed.
- Merging the two driver plugins; supporting non-superpowers users with *auto-fire* (they get manual
  invocation + a loud notice).

## Gaps flagged for the plans (not the spec)
- SP-A: exact `[VERDICT]` placement + the materiality-floor wording the skill uses.
- SP-B/SP-C: the chosen capstone completion-trigger mechanism (Decision 1 gate) + the round-cap default.
- SP-C: the debounce key + the dependency-detection placement + the "directive actually fires" spike.
- SP-D: the exact SessionStart wording + the superpowers-skill-ID probe (robust, fail-toward-loud).
- SP-A/SP-C: the **hook↔skill marker contract** — the exact marker path + format + HEAD-hash key the skill
  writes and the hook reads must be a single documented constant shared by both (panel R3 verification).

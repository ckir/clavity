# SP-C — the productized auto-fire hook — Design

**Status:** Design approved by the owner (2026-07-25): trigger posture = **best-effort auto-fire**
(owner-decided over agy's hard-enforcement challenge); **both arms** in scope. AGY-FIRST divergent consult
run before the fork (agy conv `3053bcc9`, review-only, wrote nothing — verified). Awaiting AGY-AFTER panel +
owner spec-review before the plan.

**Goal:** Ship the per-plugin **auto-fire hook** that productizes the author's personal `agy-seam-inject.sh`
into both driver plugins (byte-identical), upgrading the "remind me to consider agy" nudge into a best-effort
**"run the discipline now"** directive at the right superpowers workflow phases — wiring the AGY-FIRST and
AGY-CAPSTONE skills SP-A/SP-B already shipped, and resolving the Decision-1 capstone completion-trigger gate
that blocked capstone auto-fire.

**Governing epic:** `docs/superpowers/specs/2026-07-24-ship-agy-workflow-design.md` (Decision 1 = mechanism +
debounce; Decision 3 = runtime-dep/degradation guards; Decision 4 = per-plugin packaging + anti-drift). This
sub-project spec resolves the gaps that epic flagged for SP-C (lines 333, 335-336) and the structural gate
(epic lines 139-148). It does **not** re-litigate settled epic decisions.

**Baseline:** SP-A (`agy-first` skill) and SP-B (`agy-capstone` skill) are COMPLETE on local `main` (HEAD
`0f5e3a1`, capstone-GREEN). The marker contract `docs/agy-disciplines-marker-contract.md` is committed and is
the shared source of truth this hook READS.

---

## Posture: best-effort prompt-discipline (inherited, reaffirmed)

SP-C inherits the epic's ratified Posture verbatim: this ships **best-effort, in-flow prompt-discipline**, not
a code-enforced sandbox. The hook injects an `additionalContext` directive; the in-session LLM chooses to act
on it. Firing is a strong nudge the LLM *usually* obeys — never a guarantee. The correct bar is "materially
better than the unaided baseline," not determinism.

**Owner decision (2026-07-25):** agy used its challenge-right to argue for dropping auto-fire in favor of a
git `pre-push` **hard-block** (abort the push unless `agy-capstone.head == HEAD`) — trading "fragile
prompt-discipline" for "a concrete system constraint." The owner **rejected** that reversal: hard enforcement
contradicts the ratified Posture, is the explicitly-deferred ME1 enforcement class, and conflicts with the
standing "owner owns every push" rule (a hard block would abort every push that is not capstone-GREEN). SP-C
ships best-effort auto-fire.

### Honest known gap (folded from agy's challenge, not engineered away)
agy's substantive finding — the **semantic-bypass** failure mode — is real and is documented here rather than
silently omitted: **if the agent skips `finishing-a-development-branch` and pushes / declares "done" directly
in chat, capstone auto-fire never triggers and unreviewed code can ship.** This is an accepted best-effort
limitation consistent with the Posture ("firing is a directive, not a guarantee"). Mitigations that stay
within the Posture (manual capstone invocation always works; the AGY-CAPSTONE CLAUDE.md rule is the backstop
that binds even without the hook) are the answer; a hard push-block is out of scope by owner decision. A
future stronger guarantee is the deferred ME1 class, not this sub-project.

---

## Decision 1 — Trigger mechanism: `finishing-a-development-branch` + HEAD-idempotency debounce

**The structural problem (epic F4).** `PreToolUse(Skill)` fires at a skill's **start**, and the plan-execution
skills (`executing-plans`, `subagent-driven-development`) are invoked **many times** during one
implementation. Hooking `PreToolUse(Skill)` on them would inject the capstone directive N times, mid-build,
before the code is done — unbounded spam at the wrong moment. This is a system-level hazard that cannot be
prompt-fixed (the LLM sees N injected blocks regardless of their content).

**Resolution (candidate (b) + idempotency debounce — owner-approved; agy independently converged on the same
primary mechanism).** Bind the capstone directive to **`PreToolUse(Skill)` matching `*finishing-a-development-
branch*`**, guarded by the marker debounce below. `finishing-a-development-branch` is the superpowers flow's
genuine completion ceremony — invoked **once**, at the end, after implementation commits exist and before
merge/PR. Verified: both `subagent-driven-development` and `executing-plans` terminate by invoking
`finishing-a-development-branch` (it is the terminal node of the subagent-driven-development process graph).
Hooking its start therefore fires exactly once, at the correct moment.

This satisfies all five success criteria: (1) at most once per completion per HEAD (debounce); (2) fires after
implementation (finishing is post-build); (3) re-arms when HEAD advances (marker != HEAD); (4) no
mid-implementation injection (execution skills are no longer hooked for capstone); (5) degrades safe — if
`finishing-a-development-branch` is never invoked, the hook simply stays silent (the documented semantic-bypass
gap, plus the manual/CLAUDE.md backstop).

**Reconciliation with the epic seam-map.** The epic's seam-map table (epic line 132) names the capstone
trigger as "completion of `subagent-driven-development` / `executing-plans`"; that names the *intent* (fire at
completion), and the epic's own F4 (epic lines 139-148) flags the literal execution-skill trigger as the
unresolved spam hazard and lists candidate (b) — bind to `finishing-a-development-branch` — as the structural
fix. D1 chooses (b): both execution skills require `finishing-a-development-branch` as their terminal
sub-skill (verified: `subagent-driven-development` process-graph terminal node; `executing-plans` SKILL.md:36
`REQUIRED SUB-SKILL`), so it is the genuine once-per-completion signal. D1 therefore *resolves* the epic's
explicitly-flagged gate; it does not contradict a settled decision.

**Overlap with a merge-gate review = moot for the shipped product.** agy noted that binding capstone to
`finishing-a-development-branch` could collide with a merge-gate review on the same seam. Verified by
measurement: the *shipped* AGY-AFTER hook (`agy-after-reminder.sh`) fires **only** on
`PostToolUse(Write|Edit)` for `docs/superpowers/(specs|plans)/*.md` — never on `finishing-a-development-
branch`. The overlap exists only in the author's *personal* `agy-seam-inject.sh` (which has both a merge-gate
arm and a capstone arm); the product has no such collision. Nothing to fold.

---

## Decision 2 — The two arms (seam → discipline map)

SP-C ships **both** arms (owner-confirmed 2026-07-25). AGY-AFTER already ships as a separate hook on
artifact-write and is untouched.

| Seam (`PreToolUse` Skill match) | Discipline | Debounce marker | Directive intent (best-effort) |
|---|---|---|---|
| `*brainstorm*` | **AGY-FIRST** | `agy-first.head` | at the 2-3-approaches step, run the divergent agy consult on the fork; end with an ASCII `[VERDICT]` token (SP-A grammar) |
| `*finishing-a-development-branch*` | **AGY-CAPSTONE** | `agy-capstone.head` | run rounds-until-green over the committed diff; human adjudicates GREEN; end with an ASCII `[VERDICT]` token (SP-B grammar) |

- **AGY-AFTER is not an SP-C arm** — its sole trigger stays the artifact-write hook (epic F3 double-fire fix).
- **AGY-NEGOTIATE is not a seam** — it is a conditional sub-step inside AGY-FIRST/CAPSTONE (SP-A/SP-B), not a
  hook trigger.
- The directive **points at the discipline skill** for the actual procedure; the hook does not restate the
  skill's steps (the skill is the single source of truth, and this keeps the injected string bounded).

**Brainstorm-arm debounce nuance (accepted best-effort limit).** `agy-first.head` keyed to HEAD suppresses a
*second distinct design fork* brainstormed at the same HEAD with no commit between. This is the marker
contract as written and is accepted: the debounce's job is to stop re-injection across a multi-step brainstorm
skill's repeated sub-invocations; a genuinely new fork at the same HEAD can always be handled by manual
AGY-FIRST invocation. Documented, not re-opened.

---

## Decision 3 — Debounce read contract (reuse the committed marker contract)

SP-C's hook is the **reader** side of the already-committed `docs/agy-disciplines-marker-contract.md`
(Option S). It introduces **no new marker semantics**:

- Marker dir `.clavity/agy-marks/` (repo-cwd-relative, gitignored); file `<discipline>.head`; content = bare
  `git rev-parse HEAD` sha.
- **Hook logic:** on a seam match, resolve current HEAD; if `<discipline>.head` exists **and** its content ==
  current HEAD → the discipline was already consulted this cycle → **do not inject** (`exit 0`, silent).
  Otherwise → inject the directive.
- The hook **never writes** the marker (a `PreToolUse` hook fires before the consult and cannot know its
  outcome; the skill owns the write on its terminal state). A non-compliant LLM that ignores the directive
  simply never writes a marker → the next trigger re-fires (best-effort non-compliance self-heals to a retry).
- **Base-dir agreement (pinned — the hook must NOT anchor to git-toplevel).** The hook resolves
  `.clavity/agy-marks/` as a **bare cwd-relative** path (relative to the session cwd), EXACTLY as the shipped
  SP-B skill writes it — `clavity-dotnet/plugin/skills/agy-capstone/SKILL.md:208` writes a bare
  `.clavity/agy-marks/agy-capstone.head`, not a `git rev-parse --show-toplevel`-anchored path. Writer (skill)
  and reader (hook) run in the same session at the same cwd, so a bare relative path makes them agree whether
  the session was launched from the repo root or a subdirectory. The plan MUST NOT "improve" the hook to
  anchor at git-toplevel: that would diverge from the cwd-relative writer in a launched-from-subdirectory
  session and defeat the debounce. (Verified in AGY-AFTER round 1: the peer first proposed git-toplevel, then
  measured the shipped writer and retracted it as the very bug it would introduce.) The marker-contract doc's
  "repo-cwd-relative" phrasing means **cwd-relative, not repo-root-anchored**.
- If HEAD cannot resolve (no repo / no commits) → treat as "no marker match" → inject (safe: re-fires).
  **Accepted limit:** without a resolvable HEAD the debounce is inert (the skill cannot write a HEAD-keyed
  marker either), so in a non-git context the arm has no debounce backstop and could re-inject. This is
  correctness-safe (re-fire never corrupts) and is bounded in practice (a capstone in a non-repo has nothing
  to review; a brainstorm consult is cheap and rarely multi-fires), so it is accepted rather than engineered
  around — consistent with best-effort Posture.

---

## Decision 4 — Runtime-dependency guard (F6): jq in-hook, bash at SessionStart

The hook requires `jq` (to emit the structured JSON) and `bash` (to run at all). A bare Windows box may lack
them → a silent no-op is a silent-orphan by another door, which is forbidden.

- **`jq` — per-hook preamble, seam-scoped.** The hook checks `command -v jq` at its top. Without `jq` it
  cannot parse the stdin JSON to read the skill name, so it falls back to a **field-bounded** `grep` on the
  raw stdin — matching the `skill` field value specifically (e.g. `"skill"[[:space:]]*:[[:space:]]*"[^"]*`
  anchored to a seam name), **never a bare substring** (a bare `grep finishing-a-development-branch` would
  false-match that name mentioned in another skill's args → a spurious loud line). `grep` is present in the
  bare Git-Bash environments that may lack `jq`. **Only on a seam match** does it emit a loud,
  `printf`-hardcoded (no jq needed) additionalContext line
  `[AGY-DISCIPLINES] guard inactive: missing jq - disciplines will not auto-fire` (pure ASCII — project
  mojibake discipline) and exit 0. This is **never a silent no-op, and never a loud line on every non-seam
  Skill call** — the guard must not itself become the spam. The loud line is a fixed string, so it needs no
  jq to format.
- **Fail-open boundary (honest limit).** The hook is fail-open (`exit 0` on any error, never block the
  tool). The guard makes the **known** silent-orphan doors loud (missing `jq` here; missing `bash` / `.no-agy`
  via SP-D's SessionStart). An **unexpected** runtime error beyond those (e.g. malformed input, a surprise
  `git` failure) still fails silently — indistinguishable from a correct debounce — which is the accepted
  cost of never blocking the tool, consistent with best-effort Posture. It is not exhaustively guarded.
- **`bash` — SessionStart (SP-D).** A bash hook cannot self-detect a missing bash (it never launches). If
  `bash` is absent, Claude Code surfaces a hook-launch error, and the loud "auto-fire disabled" messaging
  belongs to SP-D's SessionStart degradation notice (epic Decision 3). SP-C documents this boundary; it does
  not build the SessionStart probe.

---

## Decision 5 — `.no-agy` kill-switch + degradation boundary

- The hook honors `.no-agy` in `cwd` **or** `~/.claude` (suppresses all injection, `exit 0`), mirroring both
  the personal `agy-seam-inject.sh` and the shipped `agy-after-reminder.sh`.
- The **loud SessionStart announce** when `.no-agy` is suppressing the disciplines (epic Decision 3, so a
  forgotten global `.no-agy` is never silent) is **SP-D** scope (SessionStart is a distinct hook event). SP-C
  builds only the `PreToolUse` suppression; the announce is coordinated with SP-D.

---

## Decision 6 — F10 validation spike, first

Before the full build, SP-C runs the epic's mandated cheap spike (epic F10, line 303): **measure** that an
injected "run now" directive reliably makes the agent execute the consult in practice — do not assume it. The
risk is largely retired by this entire epic (SP-0/A/B) having been driven by exactly this
inject-directive→LLM-executes-consult mechanism, and by the shipped AGY-AFTER hook demonstrably firing; but
the spec requires an explicit measurement, so it is Task 1 of the SP-C plan (a documented result, not an
assumption). **Pass/fail:** the spike PASSES if the injected "run now" directive is acted on (the consult is
executed) in a controlled trial; it FAILS if the directive does not fire at all. On FAIL, **halt and surface
to the owner before further build** — never silently proceed on a dead trigger. (A partial/flaky result is
itself the honest best-effort finding, not a blocker, per Posture.)

---

## Decision 7 — Packaging: per-plugin, byte-identical, transport-agnostic (epic Decision 4)

- One hook script `plugin/hooks/agy-seam-inject.sh` per driver plugin, **byte-identical** across
  clavity-dotnet and clavity-classic. Byte-identity holds **because the injected directive points at the
  discipline skill** rather than naming a transport — the per-transport clause (dotnet `agy_ask` after
  `agy_status`; classic `clavity ask --review-only`) lives inside the (also byte-identical) skill body,
  resolved by the driving agent. The hook is transport-agnostic. (This is the change from the personal hook,
  which hardcodes `clavity ask`.)
- **Registration:** each `plugin/hooks/hooks.json` gains a new `PreToolUse` block with matcher `"Skill"`
  invoking `bash "${CLAUDE_PLUGIN_ROOT}/hooks/agy-seam-inject.sh"`, alongside the existing `PostToolUse` block.
- **Anti-drift:** extend `scripts/check-seed-artifacts-synced.sh` — add `hooks/agy-seam-inject.sh` to the
  byte-identical enumeration + a mirrored `jq -S` diff of the new `hooks.json` `PreToolUse` block (matching how
  the `PostToolUse` block is guarded), and add the `scripts/README.md` row. Runs at pre-push (owner's action).

---

## Testing posture

- **SP-C ships a focused synthetic-payload smoke** validating the hook it builds: pipe a synthetic
  `PreToolUse(Skill)` payload and assert (a) a matching seam → the correct discipline directive **once**, and
  debounce holds when the marker == HEAD; (b) a non-matching skill → silent (`exit 0`, no output); (c)
  `.no-agy` present → suppressed. This is the minimum to prove the hook's own behavior.
- **The comprehensive hook-activation test category is SP-D** (epic line 298): the full matrix including the
  missing-dep loud-line assertion and the `PostToolUse` AGY-AFTER path, generalized as a reusable category.
  SP-C's smoke is a focused subset; SP-D subsumes and extends it.

---

## Sub-project boundary — SP-C vs SP-D

| Concern | SP-C (this) | SP-D |
|---|---|---|
| The `PreToolUse(Skill)` hook + both arms + debounce read + jq guard + `.no-agy` suppress | ✅ | |
| The completion-trigger structural fix | ✅ | |
| The F10 spike | ✅ | |
| Focused hook smoke | ✅ | |
| SessionStart degradation notice (superpowers-missing, `.no-agy`-suppressing announce, bash-missing) | | ✅ |
| superpowers-skill-ID robustness probe | | ✅ |
| Comprehensive hook-activation test category + docs (prerequisite messaging) | | ✅ |
| `check-seed-artifacts-synced.sh` enrollment of the new hook + hooks.json diff | ✅ (adds its own artifact) | ✅ (any SP-D additions) |

---

## Non-goals / explicitly deferred
- **Hard push-block / any code-enforced capstone gate** — rejected by owner (Posture reversal; ME1
  enforcement class, deferred). agy's semantic-bypass concern is documented as an accepted best-effort gap.
- **Headless auto-run** (hook shelling out to `clavity ask`) — rejected by the epic (blocking-hang / silent
  mutation); the consult runs in-flow, LLM-executed.
- **SessionStart guards, the skill-ID probe, and the comprehensive test category** — SP-D.
- **Retrofitting the jq guard onto the already-shipped `agy-after-reminder.sh`** (which today uses `jq`
  unguarded) — an honest consistency gap, but out of SP-C scope (that hook already ships that way);
  flagged for SP-D to fold when it generalizes the dep-guard.
- ME1 (consult guard) and AGY-LEARN (knowledge loop) — out of scope this epic.

---

## Gaps flagged for the plan (not the spec)
- The exact injected-directive **wording** for each arm (bounded strings; point at the skill; ASCII only; no
  transport literal) — authored in the plan, mirroring the personal hook's arms minus the transport hardcode.
- The exact `hooks.json` `PreToolUse` block JSON + how it merges with the existing `PostToolUse` block.
- The `printf`-hardcoded missing-jq loud-line JSON (no jq available to format it).
- The F10 spike's concrete procedure + pass/fail criterion.
- The smoke fixtures (synthetic payload shape for `PreToolUse(Skill)`; how debounce is exercised against a
  staged marker file).
- The `check-seed-artifacts-synced.sh` diff form for the new `hooks.json` `PreToolUse` block.

---

## Exhaustiveness self-audit (per the finished-spec discipline)
- **Under-specified "what":** the marker read-contract, arm directives' intent, hook registration shape, and
  the jq/bash guard split are all specified here; byte-level directive strings + hooks.json JSON are
  deliberately deferred to the plan (flagged above with where each resolves) — the *contracts* (transport-
  agnostic, ASCII `[VERDICT]`, marker read == HEAD, loud-not-silent dep guard) are pinned, not vague.
- **Placeholders / TBD:** none. Every deferred item names WHERE it resolves (plan) and its binding contract.
- **Missing cases / state combos covered:** seam match + marker==HEAD (silent) / marker!=HEAD (inject) / no
  marker (inject) / HEAD-unresolvable (inject) / `.no-agy` (suppress) / non-matching skill (silent) / jq
  missing (loud line) / bash missing (SP-D SessionStart) / `finishing-a-development-branch` never invoked
  (documented semantic-bypass gap) / both-drivers-installed (transient, per epic Decision 4 — mutual
  exclusivity bounds it; not re-engineered here).
- **Requirement → section mapping:** trigger mechanism → D1; both arms → D2; debounce → D3; dep guard → D4;
  `.no-agy` → D5; F10 spike → D6; packaging/byte-identity/anti-drift → D7; tests → Testing posture; SP-C/SP-D
  split → boundary table. Every epic-flagged SP-C gap (epic lines 333, 335-336) is addressed.
- **Remaining open items:** none blocking; all deferred items are plan-level mechanics with pinned contracts.

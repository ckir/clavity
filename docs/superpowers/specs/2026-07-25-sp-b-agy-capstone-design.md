# SP-B — the AGY-CAPSTONE discipline skill — Design

**Status:** Design drafted 2026-07-25. **AGY-AFTER panel-hardened to GREEN** (2026-07-25): 8 rounds
(driving-session solo panel + live-agy escalation each round) + 2 owner-triggered AGY-NEGOTIATE turns;
~16 findings folded (each verified by measurement), 1 fork owner-negotiated to `[VERDICT: ALIGNED]`
(single-slot marker), round 8 landed clean (agy `[VERDICT: ALIGNED]`, "coherent as a system"). Owner
waived the round-3 cap ("run until green"). Owner spec-review is the final gate before the plan.
Sub-project **SP-B** of the ship-agy-workflow epic
([`2026-07-24-ship-agy-workflow-design.md`](2026-07-24-ship-agy-workflow-design.md), committed
`3f31d85`). The epic-level decisions live in that parent spec; this document decides only what is
SP-B-specific and does **not** relitigate the parent. Gated behind SP-0 (plugin rename → `clavity:`
namespace) and SP-A (agy-first skill), both COMPLETE and capstone-GREEN on local `main` (unpushed).

**Goal:** Ship `agy-capstone` — a manually-invokable discipline skill, byte-identical in both driver
plugins — that runs a **convergent, rounds-until-green review of already-COMMITTED code** before the
driving agent may declare a plan "done". It productizes the author's personal AGY-CAPSTONE rule
(`~/.claude/CLAUDE.md` rule 1c) into the shipped plugins, mirroring the SP-A `agy-first` pattern.

**Scope boundary (from the parent decomposition):** SP-B ships the **skill only**, manual-invocation.
The auto-fire hook, the debounce, and the structural "once-per-completion" trigger are **SP-C** and are
explicitly out of scope here (auto-fire for capstone is gated on SP-C's completion-trigger fix
regardless). SP-B mechanically extends the SP-A lint/seed-sync/marker-contract machinery.

---

## What the capstone is FOR (why it is not the panel, not agy-first)

The parent spec ships three review disciplines that must not be conflated:

| Discipline | Reviews | How | Terminal |
|---|---|---|---|
| **AGY-AFTER** (`adversarial-panel-review`, shipped) | an **artifact** (spec/plan) | reasons over the document | panel GREEN |
| **AGY-FIRST** (`agy-first`, SP-A) | a **fork before deciding** | divergent creative consult | `[VERDICT]` |
| **AGY-CAPSTONE** (`agy-capstone`, **this SP**) | **executable committed code** | peer reasons + **driver measures** | human-adjudicated GREEN |

The capstone's distinct, load-bearing value is catching **reachable behavioural defects in the code
that actually shipped** — the class a pre-execution artifact review structurally cannot, because that
review never runs the code. This was proven in-project: a capstone caught a reachable protected-file
gate-evasion and an index-smuggle that four plan-panel rounds all missed.

**Structural decision (agy-consulted 2026-07-25, [VERDICT: ALIGNED]; owner-approved):**
`agy-capstone` is a **self-contained skill (Option A)**, mirroring `agy-first`'s shape — NOT a thin
delegator to `adversarial-panel-review`. Delegation was rejected: the panel skill is anchored in
"reason over text, never run the code," so injecting a "now execute" delta produces prompt
schizophrenia. A shared core (Option C) was rejected by the parent's Decision 4 (standalone
installability). Self-contained keeps per-plugin byte-identity and a mechanical lint/seed-sync
extension.

---

## Design principle: convergent LOOP, creative-adversarial DISCOVERY

`agy-first`'s spirit is **creative divergence**, driven by forcing functions (invert the constraint,
extreme-resource, cross-domain analogy) rather than a vague "be creative" dial. The capstone's *mode*
is the opposite — convergent, rounds-until-green — but it **inherits that creative DNA, pointed at
teardown instead of generation.** The loop converges; the defect *discovery* inside each round must be
creatively adversarial, or the capstone degrades into a rote checklist that misses the non-obvious
reachable defect that is its entire reason to exist.

Concretely, each round's peer consult is framed with the PROVEN adversarial-panel-review seat personas
+ forcing functions, not a flat "find bugs":
- **Personas = the panel's seat palette, reused (owner steer 2026-07-25 — they have proven productive).**
  The capstone selects the same defect-class lenses `adversarial-panel-review` uses — Axiom Breaker
  (contradictions / unstated invariants), Cascade Analyst (unhandled failure paths), Mechanism Gamer
  (gameable gates / false-GREEN), Protocol Pedant (contract / serialization), State Corruptor, Boundary
  Smuggler, and the rest — but points them at COMMITTED CODE, seating each whose trigger the diff meets.
  This reuses the persona **vocabulary**, not a code dependency on the panel skill: the capstone stays
  self-contained and does not delegate. Override with a sharper bespoke lens when the diff calls for it.
- **Forcing functions (creative, not checklist):** each seated persona must produce a **reachable**
  defect citing **file:line** — invert the happy path (what input/state/sequence breaks this?), the
  hostile/malformed input, the concurrent / re-entrant / out-of-order case, the boundary / empty / zero
  / overflow case, a cross-domain failure analogy — never a contrived or exotic edge.
- **Reachability floor:** the same severity floor `adversarial-panel-review` uses to stop nitpicking.

---

## Division of labor: peer REVIEWS, driver MEASURES (single execution cost)

**Decision (owner, 2026-07-25):** the peer must **never run the test suite.** Execution is
**driver-side, once.**

- **Peer role — review-only reasoning.** agy reads the committed diff/range and *reasons*: enumerates
  reachable defects, cites file:line, predicts what breaks and under what input/state. It does **not**
  execute tests or the code. This is explicit in the consult framing and consistent with the review-only
  safety envelope.
- **Driver role — run-and-quote (the spine).** For every peer finding, the **driver** runs the relevant
  test/probe itself and **quotes the measured stdout** (or the file line) that confirms or kills the
  finding *before folding it*. The peer states false claims with full confidence; the driver's
  measurement is what makes a fold safe. A fold with no quoted measurement is visibly hollow.

**Rationale (cost):** the driver must run the code to prove any fix regardless, so execution happens
once on the driver side. Asking the peer to *also* run the suite is a pure double cost — a second
full run in agy's workspace, minute-scale and quota-consuming — for zero added confidence, since the
driver re-measures every finding anyway. This is why the "Execution-Prover peer-lens palette" agy
floated is **not** adopted: it reads as peer-side execution.

---

## The skill's shape (self-contained, mirrors agy-first)

`agy-capstone/SKILL.md` carries these sections (parallel to `agy-first/SKILL.md`, adapted to the
convergent code-review mode):

1. **Frontmatter** — `name: agy-capstone` + a description covering: convergent rounds-until-green over
   committed code, peer-reviews/driver-measures, hard round cap + human-adjudicated GREEN, ends with a
   `[VERDICT]` token, best-effort prompt-discipline, manually invokable (auto-fire added separately).
   **The description MUST carry a restrictive trigger (panel R2, Activation Auditor):** invoke ONLY
   before declaring a plan/implementation COMPLETE — explicitly NOT on routine intermediate commits — so
   the LLM (which routes skill discovery on the description) does not over-fire the capstone mid-plan and
   trap the operator in premature GREEN breakpoints + a redundant paid review. Mirror the scoped-trigger
   precedent agy-first's description set.
2. **When to use** — before declaring any plan/implementation COMPLETE; review the COMMITTED
   implementation (executable code + tests), never the plan artifact.
3. **Transport** — identical inline clause to agy-first (dotnet `agy_ask` after `agy_status` idle-check;
   classic `clavity ask --review-only`). This is what keeps the body byte-identical across plugins.
4. **Safety envelope** — mirrors agy-first's five points (snapshot before; forbidden-actions banner;
   permission to pass; **point at files, not summaries** — write the review brief + commit-range to
   `.clavity/seams/<topic>.md` and send the path; diff-after breach handling = surface loudly + revert
   only the peer's touched paths), **plus** the scratch-dir designation lesson: any measure-and-reproduce
   framing must name `.clavity/scratch/<topic>/` so the peer never writes to cwd.
   **Breach handling DIVERGES from agy-first because the capstone is a GATE (panel R4, Axiom Breaker).**
   agy-first (advisory) emits `[VERDICT: SKIPPED-UNREACHABLE]` on a breach and proceeds. The capstone
   MUST NOT: a review-only breach (the peer mutated the tree) is a security event and a *non-connectivity*
   review failure, so — consistent with §12 — after surfacing loudly and reverting the peer's touched
   paths, the driver **HALTS-AND-ASKS the human** (do NOT auto-proceed, do NOT emit
   `SKIPPED-UNREACHABLE`, which §12 reserves for genuine connectivity failures and which auto-proceeds
   the gate). The human then decides: re-run the capstone cleanly, or explicitly waive (which writes the
   WAIVED audit line, §13). Emitting the auto-proceed token on a breach would reopen the gate-bypass §12
   closed.
5. **Review range** — how the driver picks what to review: the range of commits the just-finished plan
   produced (`<plan-base>..HEAD`, e.g. the branch's commits since the plan started). The driver states
   the range explicitly in the brief; the peer reviews only that diff (assume surrounding code correct
   unless obviously flawed; no open-ended global discovery — same scope-binding the panel uses).
   **Fold-commit re-extension (panel R1, Axiom Breaker).** Each round's folded fixes are themselves new
   committed code, so the range MUST be re-extended to the post-fold `HEAD` and the final clean round
   MUST cover those fix commits before the driver may declare GREEN — otherwise the capstone greens a
   `HEAD` whose newest commits (its own fixes) were never reviewed. The marker (§13) records that
   post-fold reviewed `HEAD`.
   **Exclude generated/vendored files (panel R3, Boundary Smuggler).** The reviewed diff excludes
   lockfiles, minified/generated assets, and generated manifests (git pathspec `:(exclude)` or a
   documented exclude list). They are not human-authored behaviour; a large generated diff both buries
   real findings and risks overflowing the reviewer's context — a **diff-bomb** that (per §12) must never
   silently pass the gate.
6. **The convergent round** — send the peer the committed range + the creative-adversarial framing
   (the seated personas + forcing functions + reachability floor above) + the do-not-re-raise ledger;
   ask it to enumerate reachable defects citing file:line. Intermediate rounds report progress and loop;
   they emit **no** token — the driver emits a `[VERDICT]` token only at a terminal disposition or
   completion proposal (§11).
   **Commit before the next round (panel R1, Literal Implementer).** The peer reviews COMMITTED code
   (`<base>..HEAD`), which ignores the working tree — so the driver MUST `git commit` every
   measurement-verified fold-fix BEFORE re-capturing `HEAD` and launching the next round. A fix left
   uncommitted sends the peer the identical broken diff next round; it re-raises the defect and the
   driver would falsely claim it was already fixed.
7. **Verify before you fold (the spine)** — the driver's run-and-quote obligation above. Quote the
   measured output for every folded finding.
8. **Do-not-re-raise ledger** — a running list of already-folded/already-refuted findings, **inlined
   into every round's brief** (the peer's context can truncate across a long review; a shorthand
   "see round 1" can point at something it no longer holds). Ledger entries are plain factual findings,
   not the driver's rationale.
9. **Round cap + human-adjudicated GREEN + override re-entry (Decision 2b)** — below.
10. **AGY-NEGOTIATE reference** — a material disagreement (architecture/performance/security) inside a
    capstone round runs the same AGY-NEGOTIATE sub-protocol agy-first defines (materiality floor, 2-round
    cap, impasse → human tie-break). The capstone body references it inline rather than re-deriving it.
    **It AUTO-fires (owner steer 2026-07-25):** the driver runs the negotiation the moment a material
    driver↔peer disagreement surfaces (a `[VERDICT: NEGOTIATE]` emission or the driver rejecting a peer
    finding it deems material) — it does NOT wait for the human to ask, and it does NOT pre-emptively kick
    the raw disagreement to the human as a fork-question. The human is brought in only on IMPASSE at the
    round cap, or is shown the already-CONVERGED result. Manual "negotiate with agy" stays a backstop.
11. **The four ASCII `[VERDICT]` tokens** — reused verbatim from agy-first, but emitted by the driver at
    a terminal disposition / completion proposal, not per review round (below).
12. **If the peer is unreachable** — `[VERDICT: SKIPPED-UNREACHABLE]` + the gate-specific handling below.
13. **Debounce marker (hook contract)** — Option-S marker, written on the terminal state (below).

---

## Token model: reuse the four agy-first tokens; GREEN is a meta-state (lint unchanged)

**Decision (agy + driver, 2026-07-25; refined by AGY-NEGOTIATE at panels R5+R6):** the capstone reuses
**exactly** agy-first's four ASCII `[VERDICT]` forms — no fifth token. The **DRIVER** owns and emits them
(agy-first SKILL.md:80-83 — the token is the driver's self-report, not the peer's). But unlike
agy-first's one-shot advisory model ("exactly one token as the last line"), the capstone is a
multi-round, multi-proposal **gate**, so emission is keyed to **disposition, not a fixed count** (panel
R6, Axiom Breaker — the rigid one-token rule fractured on override loops and out-of-band waivers):

- **Intermediate fold-and-loop review rounds emit NO token (panel R5).** A round that finds defects,
  measures them, and folds the real ones just reports progress and loops (§5/§6); it has no terminal
  disposition yet. This closes the R5 trap: a *per-round* token had no valid value for a folded-dirty
  round (not `ALIGNED` — §5 requires a clean round first; not `REJECTED` — folded, not killed; not
  `NEGOTIATE` — no disagreement).
- **The driver emits a token at each terminal disposition / completion proposal.** An
  `[VERDICT: ALIGNED]` completion proposal **MAY RECUR** — if the human rejects it and the driver
  re-enters rounds (§9 override loop), the driver proposes `ALIGNED` again after the next clean round, so
  `ALIGNED` can be emitted more than once across the run (this is expected, not a violation).
- **A human WAIVER is NOT tokenized.** It is the human's out-of-band terminal action (at the round cap,
  or on a §4 breach), recorded in the audit log (§13 `WAIVED` line), NOT emitted as a `[VERDICT]`. This
  is why the four-token grammar needs no "unclean-waiver" form (panel R6).

The single terminal token:
- `[VERDICT: ALIGNED]` — the capstone reached a **clean terminal round**: every finding across the run
  is either folded (fixed + measured clean) OR killed by measurement (`REJECTED`), and no material
  unrefuted defect remains. A run whose findings were ALL refuted-by-measurement **is** `ALIGNED` — a
  peer hallucination the driver kills does not block completion (else "run until green" with an eager
  peer loops forever inventing fresh refuted findings — panel R3, Resource Vampire). Proposes completion;
  the human adjudicates GREEN.
- `[VERDICT: REJECTED - <measured reason>]` — a **per-finding disposition**, not a capstone terminus
  (panel R7): a specific peer finding killed by the driver's measurement, quoted and ledgered. It is
  **non-blocking — it does NOT halt the convergent loop.** A run whose findings were all folded or all
  `REJECTED` reaches a clean round and terminates as `ALIGNED` (not `REJECTED`). `REJECTED` is retained
  (a) for SP-A lint compliance (the string must appear in `SKILL.md`) and (b) to label a killed finding
  in the driver's writeup/ledger. This resolves the R3-vs-original tension: a "killed finding" is a
  ledger-and-continue outcome, never an abort (the abort semantics agy-first's one-shot `REJECTED` had do
  not apply to a convergent gate).
- `[VERDICT: NEGOTIATE - <material reason>]` — a MATERIAL driver↔peer disagreement remains at an impasse;
  runs AGY-NEGOTIATE (§10). **A peer merely REPORTING defects is NOT this** — that is the normal
  convergent case the driver verifies, folds, and loops on; it never auto-fires negotiation (panel R5).
- `[VERDICT: SKIPPED-UNREACHABLE]` — the consult could not run (genuine connectivity failure only; §12).

**GREEN is a human-adjudicated META-state, not a token.** A terminal `[VERDICT: ALIGNED]` is a
*proposal*; GREEN is reached only when the human confirms the clean terminal round at the completion
checkpoint. This keeps the vocabulary unified across all disciplines and leaves the SP-A lint's four
required forms **unchanged** — SP-B adds only `'agy-capstone'` to the lint's `$skills` array (the lint
already anticipates this: `# SP-B appends 'agy-capstone'`).

---

## Round cap + human-adjudicated GREEN + override re-entry (parent Decision 2b)

The shipped capstone MUST carry a hard ceiling; an unbounded loop is a token-drain on a stranger's
budget (the peer can re-assert a confabulated defect every round).

- **`MAX_CAPSTONE_ROUNDS` — default `3`** (tunable), matching `adversarial-panel-review`'s round-3
  halt-and-ask precedent. At the cap, **halt and ask the human** ("still finding substance at round 3 —
  continue or ship?") rather than looping or silently stopping. *(The author's personal capstone waives
  the cap — "repeat until green"; the SHIPPED build carries it. Parent Decision 2b.)*
- **GREEN is human-adjudicated** — the peer cannot self-declare GREEN. A self-reported round-ALIGNED is
  a proposal the human confirms or rejects at the superpowers completion breakpoint (or in-chat under
  manual invocation, which has no breakpoint).
- **Write happens on RESUME, not at the proposal (panel R1, resolved with agy).** The driver session
  persists across the adjudication pause — the same persistent-session mechanic the shipped AGY-AFTER
  async-fold relies on (parent Decision 2c) — so the marker write (§13) is reachable as the driver's
  next sequential action AFTER the human confirms. The skill MUST make this explicit: the driver resumes
  post-confirmation and writes the marker then; it does NOT stop dead at the `ALIGNED` proposal, and it
  does NOT write on the unconfirmed proposal (that reintroduces the premature-marker hole, §13).
- **Override re-entry loop (parent R2-S3)** — if the human rejects a proposed GREEN or names an
  unaddressed defect, the driver **re-enters capstone rounds on that defect** rather than treating the
  book as closed. Without this loop the "human adjudication" is illusory (the human could only veto by
  restarting the whole flow).
- **Cap vs override interaction (panel R1, Cascade Analyst).** A human "continue" / re-entry answer at
  the cap **authorizes** the ordered work to run — the named-defect fix and its re-review proceed, and
  the cap does NOT re-halt inside that authorized extension. A human-ordered re-entry on a *named* defect
  is authorized work, never a "still finding substance" auto-halt. The halt-and-ask re-triggers only if,
  after the authorized extension, findings are STILL live and no fresh override is given — so the ceiling
  holds (every further block needs a new human OK) without trapping the operator in an instant re-prompt
  loop. Re-entry rounds increment the reported round number, but the cap is a halt-and-**ask** gate, not
  a hard stop that fires before the human's ordered fix runs.

---

## Execution mode: sync-gate (parent Decision 2c)

The capstone is a **sync-gate**: it blocks the **agent's completion claim** — the driver MUST NOT
declare the plan complete until the capstone is GREEN or explicitly waived. It does **not** block the
user's shell. Deferring it async would let "done" slip through before the review lands, defeating the
gate. Its value *is* the blocking (unlike AGY-FIRST/AFTER, whose value survives being deferred).

---

## Unreachable peer at a completion GATE

If the peer is unreachable (no live peer / no auth / idle-check never clears), the driver emits
`[VERDICT: SKIPPED-UNREACHABLE]` and **proceeds — never hangs, never hard-blocks "done"** (parent
Decision 2.7). But because the capstone is a *gate*, a skip is a weaker guarantee than a skip of the
advisory disciplines, so the skill MUST make the skip **loud and durable**:
- surface in-chat that the completion **gate was skipped** and name the range it did not review, so the
  human can decide whether to accept "done" un-reviewed;
- append a durable line to `.clavity/agy-marks/skipped.log`
  (`<iso-8601>  agy-capstone  SKIPPED-UNREACHABLE  HEAD=<sha>`), creating `.clavity/agy-marks/` first if
  absent — identical mechanism to agy-first's skip log;
- write **no** consulted marker, so the next trigger retries.

**A review FAILURE is not an unreachable peer (panel R3, Boundary Smuggler).** `SKIPPED-UNREACHABLE` is
reserved for a genuine *connectivity* failure (offline / no auth / idle-check never clears). A review
that fails because the diff is **too large to review** (context/API overflow) is NOT that — and treating
it as `SKIPPED-UNREACHABLE`-and-proceed would let a **diff-bomb** (or an accidentally huge lockfile
change) silently BYPASS the completion gate. An oversized-diff or any non-connectivity review crash MUST
instead **halt-and-ask the human** (chunk the review, or the human decides) — never auto-proceed. The
gate's value is defeated the moment "too big to review" silently equals "gate passed." (The
generated-file exclusion in §5 shrinks this surface; this bullet closes the residual.)

---

## Debounce marker (Option-S, hook contract — read by SP-C)

Mirrors the SP-A marker contract exactly (`docs/agy-disciplines-marker-contract.md`):
- **Path:** `.clavity/agy-marks/agy-capstone.head` — a single discipline-keyed marker, **no plugin-id**
  prefix (Option S, ratified in SP-A: byte-identical body cannot carry a per-plugin literal; drivers are
  mutually exclusive so a shared marker correctly debounces the shared phase).
- **Content:** the output of `git rev-parse HEAD` at the terminal state, nothing else. If HEAD cannot
  resolve, skip writing the marker (the discipline simply re-fires next trigger — safe).
- **Written only on the TERMINAL state** — human-confirmed GREEN **or** explicit human waiver. A
  self-declared round-ALIGNED that the human has not yet confirmed, an override re-entry still in
  progress, or a `SKIPPED-UNREACHABLE`/breach writes **no** marker. A new HEAD (new commits) re-arms the
  gate.
- **Premature-write bound (Posture limit, panel R1 Mechanism Gamer).** "Human-confirmed" is itself
  self-reported — a driver that confabulates confirmation could write the marker early and silence
  SP-C's auto-fire. This is best-effort, not code-enforced (parent Posture), but the blast radius is
  **bounded to one `HEAD`**: a premature marker silences the gate only for that exact commit, and any
  subsequent commit re-arms it (the HEAD-sha key is the bound). Enforcing it (parsing the transcript for
  a real human OK) is ME1's job — deferred, out of scope.
- **Waiver observability (panel R2, Blindspot Auditor).** A human WAIVER and a mechanically-verified
  GREEN both write the same bare-sha marker, so they are indistinguishable in the durable record — a
  post-mortem could not tell a review gap (capstone missed the bug) from a process bypass (human waived).
  A waiver therefore MUST also append a durable audit line
  (`<iso-8601>  agy-capstone  WAIVED  HEAD=<sha>`) to the same append-only log the `SKIPPED-UNREACHABLE`
  path uses (§"Unreachable peer at a completion GATE"), so GREEN / WAIVED / SKIPPED are all
  distinguishable after the fact. The marker **content stays the bare sha** — SP-C's hook reads
  `content == current HEAD` (marker-contract doc), so encoding `WAIVED` into the marker itself would
  break that read; the observability lives in the log, not the marker.
- `.clavity/` is gitignored runtime state — never commit a marker. `mkdir -p .clavity/agy-marks/` before
  any write (absent on a fresh clone).
- **Branch-switch transient — ACCEPTED (panel R2 -> owner-triggered AGY-NEGOTIATE, [VERDICT: ALIGNED]).**
  Because the marker is a single bare sha, it "forgets" a sha's GREEN status across a branch switch:
  green `HEAD=A`, switch away and green `HEAD=B`, return to `A` and hit a completion trigger with NO new
  commits, and the gate re-arms -> a redundant review of already-green `A`. This is ACCEPTED, not fixed:
  (a) it already exists in the shipped agy-first single-slot marker; (b) the human adjudicates every
  GREEN, so a re-fire on already-green code is a single instant waiver; (c) the scenario is rare (needs a
  return to an already-green sha AND a no-new-commit completion trigger); (d) the alternative (an
  append-only GREEN-sha log) would diverge the two disciplines' markers, break SP-C's uniform
  `content == HEAD` read, and add an unbounded log needing pruning. Documenting the bounded transient
  beats over-engineering it — consistent with the parent's accept-rare-transients posture (Decision 3).
  agy independently measured the three cited files and concurred.

*(The hook that READS this marker to decide whether to auto-fire, and the structural once-per-completion
trigger, are SP-C. SP-B only defines the WRITE contract.)*

---

## Enrollment (mechanical, mirrors SP-A)

1. **Lint** — add `'agy-capstone'` to `scripts/check-agy-discipline-skills.ps1` `$skills` array. The
   four `[VERDICT]` forms, both transports, the `.clavity/agy-marks/` marker constant, and pure-ASCII
   invariants all apply unchanged. Add pinning Pester tests for the new skill (happy-path lint pass;
   non-ASCII rejection; missing-VERDICT rejection — parallel to the agy-first tests).
2. **Seed-sync** — add `skills/agy-capstone/SKILL.md` to `scripts/check-seed-artifacts-synced.sh`'s
   byte-identical enumeration (the two plugin copies must stay identical; unlike the responder pair,
   there is no id/name divergence to strip — a plain `diff -q` is correct).
3. **Marker-contract doc** — extend `docs/agy-disciplines-marker-contract.md` to document
   `agy-capstone.head` alongside `agy-first.head` (same format/HEAD-key; note the terminal-state write
   difference: capstone writes on human-confirmed GREEN, not on the raw completed consult).
4. **`justfile` / `lefthook.yml`** — already wired in SP-A (`check-agy-skills` runs the lint over the
   whole `$skills` array; seed-sync runs in pre-push). No new recipe/hook needed; the new skill is
   picked up automatically once added to the arrays above.
5. **`scripts/README.md`** — the lint's row already covers "agy-discipline skills"; no change unless the
   row enumerates skill names (it does not).

---

## Testing posture

- **Existing-test integrity (panel R1, measured — MUST fix in-plan).** The current agy-first Pester
  *rejection* tests (`scripts/tests/check-agy-discipline-skills.Tests.ps1`) stage a scratch `-Root`
  containing only `agy-first/SKILL.md` and assert exit 1. The moment `'agy-capstone'` joins the lint's
  `$skills`, the lint reports `MISSING: agy-capstone` under that scratch root and exits 1 **for that
  reason** — so those tests still go red but for the wrong cause, silently losing their discriminating
  power (a real agy-first breakage would no longer be what fails them). The plan MUST stage a valid
  `agy-capstone/SKILL.md` alongside `agy-first/SKILL.md` in **each** rejection-test fixture root.
  Additionally the happy-path test runs the lint against the **real repo** (no `-Root` override), so it
  requires the real `agy-capstone/SKILL.md` to be committed together with the `$skills` change (author
  the SKILL.md first, or in the same commit).
- **Lint/Pester** — the new pinning tests above, run under `just check-agy-skills` + `just test-scripts`.
- **Seed-sync** — `just seed-sync-check` proves the two `agy-capstone/SKILL.md` copies are byte-identical.
- **Manual-invocation smoke** — both `SKILL.md` files are discoverable; `name: agy-capstone` on line 2;
  the skill body names the four tokens, both transports, the marker constant.
- No hook-activation test here — that category is SP-D (there is no capstone hook until SP-C).

---

## Non-goals / explicitly deferred

- **Auto-fire, the debounce hook, and the once-per-completion structural trigger** — SP-C. SP-B ships
  manual-invocation only (which is all capstone gets until SP-C's trigger fix lands anyway).
- **Peer-side test execution** — rejected (double cost); the peer reasons, the driver measures.
- **A fifth `[VERDICT: GREEN]` token / any lint-invariant change** — rejected (fractures the vocabulary
  for no structural gain; GREEN is a human-adjudicated meta-state).
- **Merging capstone with `adversarial-panel-review`, or a shared core** — rejected (parent Decision 4;
  static/dynamic boundary).
- **Code-enforced determinism** — a non-goal by the parent's Posture; best-effort prompt-discipline.

---

## Exhaustiveness self-audit (2026-07-25)

- **Under-specified "what":** token grammar, marker path/format/write-trigger, transport clause, review
  range, round-cap default (`3`), and the skill's section list are all pinned above — no "TBD".
- **Contracts:** the four tokens, the `.clavity/agy-marks/agy-capstone.head` marker (Option S), and the
  seed-sync/lint enrollment are stated concretely.
- **Edge cases covered:** unreachable peer at a gate; human rejects a proposed GREEN (override re-entry,
  no instant re-halt loop); round cap hit while still finding substance (halt-and-ask); review-only
  breach (halt-and-ask, NOT auto-proceed); HEAD unresolvable (skip marker); byte-identity across plugins
  (plain `diff -q`); fold-fixes committed + range re-extended before GREEN; diff-bomb / oversized diff
  (generated-file exclusion + halt-not-silent-skip); single-slot marker branch-switch transient
  (accepted, documented); token model over a multi-round gate (intermediate=no token, ALIGNED recurs,
  REJECTED per-finding, waiver out-of-band).
- **Panel-hardened:** all of the above beyond the first three bullets were folded during the 8-round
  AGY-AFTER panel + 2 AGY-NEGOTIATE turns (each verified by measurement); round 8 clean.
- **Deferred-with-owner:** none silently. Auto-fire/hook/trigger explicitly → SP-C; hook-activation tests
  → SP-D; both named in Non-goals.
- **Requirement → section:** every parent Decision that touches capstone (2, 2b, 2c, 4, and the SP-B
  decomposition line) maps to a section here.

## Gaps flagged for the PLAN (not the spec)

- Exact `SKILL.md` prose (extracted/authored to satisfy the lint; ASCII-only) and its line-level
  sections — authored in the plan, mirroring the agy-first plan's extract-and-verify method.
- The precise `check-seed-artifacts-synced.sh` insertion line and the marker-contract-doc edit.
- Confirm `MAX_CAPSTONE_ROUNDS = 3` default with the owner in-plan (tunable; parent flagged it as a plan
  gap).
- The exact Pester fixtures for the new pinning tests (each rejection fixture must also stage a valid
  `agy-capstone/SKILL.md` — panel R1).
- The exact generated/vendored-file exclude list or git pathspec for the reviewed diff (panel R3).
- The waiver audit-log line format + file (shared with the `SKIPPED-UNREACHABLE` skip.log — panel R2).

# agy observations inbox (raw, project-agnostic)

Captured live by `agy-learn`; drained by `agy-curate` into the GROWTH region of the shared
golden-header (`golden-header.growth.md`) via `curate-commit`. The driver-owned SEED manuals
(`agy-capabilities.md` / `agy-assumptions.md`) are never edited by this loop. One bullet per
observation. Project nouns are forbidden here (Structured Abstraction Schema). Provenance tags:
`[corpus]` observed live · `[doc]` from docs · `[local]` this install · `[verified]` ≥2 sources.

## Pending

- [heuristic] (driver/probabilistic) `[corpus]` An INDEPENDENT-MODEL adversarial round earns its cost most on
  GATE / COMPARISON logic: given a scoped artifact plus a concrete drift scenario to reason about, the peer
  caught a structural FALSE-GREEN -- a diff-based gate whose selector PROJECTED AWAY a load-bearing
  discriminator field (comparing a filtered inner object while dropping the parent's discriminator), so a
  divergence in that field compared identical and passed. The same-model author's own multi-seat self-panel
  had cleared the same selector across two prior rounds; the independent model does not share the author's
  blind spot on "what my own comparison silently omits." Driving implication: when an artifact defines a gate
  that compares a PROJECTION/subset of a structure, specifically route it to the peer with a named drift
  scenario ("flip field X in one side -- does the gate still bite?") rather than trusting a same-model panel;
  and VERIFY the peer's fix by measurement (here the projection-vs-wrapper fix was confirmed by running both
  selectors on synthetic drift). (1st observation of the projection-drops-discriminator variant.)

- [anti-pattern] (peer/probabilistic) `[corpus]` The peer's UNSOLICITED SELF-CORRECTION channel is not more
  reliable than the rest of its reply — it can be the *least* reliable part. Asked to verify claims against
  files and report `CORRECTION: <what I got wrong>` on any divergence, the peer volunteered a confident
  correction that INVERTED the true values: it attributed file A's real measurement to file B, and supplied
  for file A a number matching no artifact in the tree. The driver's original framing had been correct. This
  is dangerous precisely because a correction is socially framed as the peer having checked harder, so it
  reads as higher-confidence than an ordinary assertion and invites the driver to overwrite a correct belief.
  Driving implication: a `CORRECTION:` block is a CLAIM like any other and must be measured before folding —
  and when the correction concerns a quantity, re-measure rather than reasoning about plausibility. When
  challenged with the actual measurement the peer conceded immediately and its dependent conclusion changed
  materially, so the correction had also propagated into a downstream design answer — re-ask any fork whose
  premise the false correction touched, don't just discard the correction. (1st observation of the
  correction-channel variant; the general confabulation pattern is already promoted.)

- [heuristic] (driver/probabilistic) `[corpus]` Asked for a TIGHT INLINE structured answer (N numbered items,
  bounded sentences each), the peer instead WROTE the answer to a markdown file in its own private working
  directory and replied inline with only a one-paragraph preamble plus a `file:///` pointer. The reply came back
  idle and NOT truncated — so this is not the oversized-reply mode; it is the peer electing file transport for
  multi-part structured output on its own. Driving implication: when you ask for a structured multi-item verdict,
  expect to have to READ a returned path rather than parse the inline body, and budget a follow-up read; asking
  for terseness does not prevent it. (1st observation — needs a 2nd before promotion per the heuristic rubric.)

- [anti-pattern] (driver/probabilistic) `[corpus]` The peer's suggested FIX is fallible INDEPENDENTLY of its
  FINDING: a correct defect report routinely arrives with a fix that is wrong or incomplete. Across one
  convergent review series the peer (a) correctly identified a real state-latch bug but proposed a naive
  "reset every iteration" fix that REGRESSED a healthy path (a budget-clamped final poll threw a benign
  timeout the naive reset misread), and later (b) its accepted narrower fix still missed a startup-transient
  ORDERING edge that the very next round surfaced. Driving implication: a peer's fix is a fresh CLAIM — trace
  the full case-matrix of the fix by measurement before folding it, not just the finding; pin each fold with a
  regression test that goes RED on the pre-fix code; and ALWAYS re-run a fresh review round after folding,
  because the fix introduces its own edges (here rounds N+1 and N+2 each caught a defect in the prior round's
  fix). Distinct from the already-noted "verify the peer's fix" point: here the finding was fully correct and
  only the fix was defective, twice in a row. (1st observation of the correct-finding-defective-fix variant.)

- [heuristic] (driver/probabilistic) `[corpus]` A peer TEST-COVERAGE / exhaustiveness audit OVER-COUNTS: it
  will confidently report a "gap" that an existing test already covers. Asked to audit two suites, the peer
  returned 5 ranked gaps; independent verification by reading each cited test showed one was already pinned by
  an existing hung-boundary test — a false positive that would have produced a redundant, timing-flaky test had
  it been folded unread. Driving implication: treat every claimed coverage gap as a claim — read the cited
  test (and grep for a sibling that already exercises the same path) before writing anything; the audit's value
  is real but its gap list must be filtered by measurement, exactly like a defect panel's findings. (1st
  observation of the coverage-audit-over-counts variant.)

- [heuristic] (driver/probabilistic) `[corpus]` On a DESIGN-FORK consult (not a defect review), the peer will
  confidently assert that a constraint written into your OWN artifact is "actually false" and propose a
  mechanism that routes around it. Treat this as a high-value signal: here the peer correctly spotted that an
  over-broad "no hook can enforce this ordering" claim was refutable, because a state-marker that is written
  ONLY at a terminal success is itself readable by a DIFFERENT hook than the one the claim was reasoning
  about. But its proposed replacement mechanism was simultaneously (a) IMPRECISE on the exact state semantics
  (the marker actually meant success-OR-explicitly-waived, not success-only) and (b) INCOMPLETE on a
  load-bearing detail (which trigger EVENT re-fires the second hook AFTER the first writes its marker within
  the same lifecycle step). Driving implication: a peer's "your premise is false" is worth verifying against
  the source of truth (it is often partly right and overturns a genuine blind spot), but do NOT fold its
  proposed replacement without tracing the full state-AND-trigger case-matrix — the premise-challenge and the
  mechanism are separate claims, and the mechanism routinely arrives directionally-right-but-underspecified.
  Distinct from the correct-finding-defective-fix REVIEW variant: this is a GENERATIVE design proposal and the
  peer's move was to overturn a premise, not patch a bug. (1st observation of the design-consult
  premise-overturn variant.)

- [heuristic] (driver/probabilistic) `[corpus]` On a CONVERGENT multi-round adversarial review driven toward a
  clean terminal state, the peer trends toward MANUFACTURING ever-lower-value findings round over round if each
  round's framing implies findings are expected of it - early rounds surfaced real, measurement-verified defects,
  but by later rounds the finds decayed from correctness bugs to test-of-test brittleness nits and finally to
  contrived/exotic edges. To reach an HONEST terminal GREEN rather than an infinite tail of manufactured nits,
  the final round(s) must explicitly (a) set a STRICT severity floor (correctness / safety / contract / real
  coverage only - name the exclusions: stylistic, hypothetical-unreachable, defensive-hardening-of-already-fail-
  safe-code) AND (b) AUTHORIZE a clean verdict as an acceptable, expected outcome ("state plainly it is CLEAN if
  sound; I want an honest clean verdict, not manufactured findings"). Given that framing the peer returned a
  genuine CLEAN once the code was sound, having produced real folds earlier - so the convergence was honest, not
  a rubber-stamp. Complements the existing "force depth, don't dial it": that stops theater-compliance on the
  DISCOVERY side; this stops manufactured-findings on the CONVERGENCE side. Driving implication: pair open/deep
  framing in early rounds with an explicit floor + permission-to-be-clean in the closing round. (1st observation
  of the convergence-permission variant.)

<!-- Drain log 2026-07-19 (agy peer; 2 pending → recompiled GROWTH + driver cheatsheet):
  1) [assumption] (driver/deterministic) oversized-REASONING-reply truncates-to-HEAD (NOT a hang) — REFINEMENT
     of the already-promoted oversized-turn anti-pattern. Not tool-fixable (recovery = decompose / file-transport,
     a driving move) → NO fix-the-tool-backlog item. FOLDED into GROWTH: the last anti-pattern now distinguishes
     the two modes OPPOSITELY (bundled-tool-action / serialized-deep-consult = false-hang; a single oversized
     REASONING reply = returns idle + HEAD-truncated + tail-recoverable). Verified by the 2026-07-13 A2b probe
     PASS + this session's clean bounded agy_ask consult (AnswerTruncated=false, idle, no hang).
  2) [heuristic] (driver/probabilistic) negotiate-for-synthesis — agy concedes a concretely-argued technical
     risk (named failure mode) but holds structural/architectural calls; push for convergence, don't accept its
     first verdict. ≥2 obs (2026-07-15 + this session's Option-B fork consult where agy conceded the Access-Denied
     runtime-write risk); corroborates the user's treat-agy-with-respect feedback. FOLDED into driver-cheatsheet
     bullet #2 (extends the existing "negotiate, don't fold or dismiss"), synced to core + shared runtime path.
  GROWTH committed via `clavity-ls curate-commit` (SEED 2067 + GROWTH 4755 = 6822 < 16KB; sha256 sidecar). No
  rule retired; no Empirical Assumption newly promoted (entry 1 refined an already-promoted, probe-verified item). -->

<!-- Drain log 2026-07-13 (agy peer; ~36 pending → compiled GROWTH + driver cheatsheet):
  Triage: nearly all entries are peer/probabilistic (peer psychology) or driver/probabilistic (driving
  moves); the sole (driver/deterministic) entry (self-committing-delegation stale-index) is NOT tool-fixable
  (only fix is a driving move: reconcile VCS) → carried as a driver rule, NO fix-the-tool-backlog item.
  Distilled the ~36 into meta-patterns, DEDUPED against the SEED floor (which already holds: no-banner→exec,
  mix-phases, no-checkpoint, find-bugs-open-ended, bimodal-latency+bus-recovery, new-thread-correlation,
  verifies>>discovers, quota-lock-fallback):
  - GROWTH (golden-header.growth.md, via `clavity-ls curate-commit`; 4.4KB, SEED+GROWTH=6.5KB < 16KB cap):
    5 new anti-patterns (internal-fact+cross-session confabulation; vague-dials→theater vs forcing-functions;
    seeded-defect→over-application; panel-not-a-code-gate + pre-stated-invariants→confirmation; bundled-action/
    oversized-turn→false-hang + parked-reply-recovery via step-count/new-thread/filepath-transport) + 4 new
    load-bearing assumptions (name-domain+lens/spec-oracle to steer latent breadth; open-framing>closed-menus
    for design; process-alive≠endpoint-reachable; direction-right-specifics-wrong + OS/concurrency-internals
    strength).
  - Driver cheatsheet (driver-cheatsheet.core.md + shared %USERPROFILE%\.clavity\driver-cheatsheet.md,
    atomic): added "force depth, don't dial it" to the existing 3 (verify-volunteered-facts, don't-lead-frame,
    panel-advisory).
  Empirical-assumption live synthetic probes EXECUTED 2026-07-13 vs live agy 1.1.1 (bridge clavity-dotnet
  0.2.1, cascade 4764460f) — see verify/assertions.md: A2a bounded-ask-in-window PASS; A2b oversized→recoverable
  PASS (mode refined — a single oversized *reasoning* reply returns idle but truncates to HEAD, does NOT hang;
  hang is bundled/serialized-only; the refinement is re-captured to this inbox above for the next drain); A6
  process-alive≠endpoint-reachable PARTIAL (positive confirmed live, alive-but-unreachable negative deferred).
  Remaining promoted items are behavioral tendencies with ≥2 cross-session observations (heuristic rubric) or
  reinforce already-verified SEED. No rule retired (fixes + CI regression tests deferred per skill §5.C-D). -->

<!-- Drain log 2026-06-20 (agy 1.0.10):
  - A1/A3 (banner-honored, new-thread) → promoted to agy-assumptions.md "Driving-protocol assumptions".
  - A2 + DRIFT-CORRECTION + "block resolved" latency lines → reconciled into ONE bimodal A2 assumption
    (the two superseded ~9–10 min lines dropped; the leftover sync caveat in driving-agy/SKILL.md fixed).
  - A4 (phase isolation) + A5 (checkpoint-before-mutation) → harness probes run & PASS (assertions.md),
    then promoted to "Driving-protocol assumptions".
  - Anti-patterns (no-banner→executes, mix-phases, no-checkpoint, find-bugs-open-ended, global-config-
    overrides-front-door) → "Failure modes — driver anti-patterns" in agy-assumptions.md.
  - Heuristics (verifies>>discovers, critique+generative pairing) → already canonical in capabilities §A
    (reinforced, no dup).
  - Subagent-CAN-reach-peer-via-CLI → capabilities §F routing.
  - golden-header.md recompiled + version-stamped. -->
- [anti-pattern] (driver/deterministic) A review brief that names its IN-SCOPE findings with a term and then reuses that SAME term for a closing catch-all section about OUT-OF-SCOPE observations gets a null answer every time: the peer believes it already answered that question above. Use two visibly different labels.  ·  `[corpus]` · 2026-08-08
- [anti-pattern] (driver/probabilistic) A closing catch-all section that explicitly permits a null answer makes null the cheapest compliant response, so it is chosen regardless of what was noticed. Replace the open invitation with named sub-questions that HAVE no null answer - the least-clear part of the brief and how it was resolved, a file opened outside the review scope and what was noticed in it, an assumption made that the brief did not state. Every artifact has a weakest point and every reviewer makes assumptions.  ·  `[corpus]` · 2026-08-08
- [assumption] (driver/deterministic) The peer CLI exposes named SPECIALIST agents (list them with the agent subcommand) and selects one per session with an --agent flag. A driver that only ever uses the default conversational ask is leaving a whole capability class unused - a specialist reviewer is a different lens, not just a differently-worded prompt. BUT the flag is NOT reachable from a headless single-shot invocation: that path hangs and times out, the same no-TTY hang already known for headless invocation generally. So a specialist is only usable if the LIVE session was started with it - which means choosing the agent is a session-launch decision, not a per-question one, and a driver talking to an already-running peer over a bus cannot switch lens mid-conversation.  ·  `[corpus]` · 2026-08-09

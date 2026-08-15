# agy observations inbox (raw, project-agnostic)

Captured live by `agy-learn`; drained by `agy-curate` into the GROWTH region of the shared
golden-header (`golden-header.growth.md`) via `curate-commit`. The driver-owned SEED manuals
(`agy-capabilities.md` / `agy-assumptions.md`) are never edited by this loop. One bullet per
observation. Project nouns are forbidden here (Structured Abstraction Schema). Provenance tags:
`[corpus]` observed live · `[doc]` from docs · `[local]` this install · `[verified]` ≥2 sources.

## Pending

- [assumption] (driver/deterministic) `[verified]` A peer materializes large diffs into its WORKING
  DIRECTORY regardless of instruction. Measured twice: once under a self-contradictory banner, and again
  under a corrected one that explicitly forbade repository-root writes AND named a scratch directory for
  exactly that purpose - it wrote two diff files to the root and left the offered scratch directory empty.
  This is not a prompt-wording problem and cannot be fixed by a louder banner. Plan to DETECT and REMOVE
  the artifacts after each consult (they are untracked, so an explicit-path commit never picks them up),
  and do not read their presence as evidence of a breach worth escalating.
  - 2026-08-12 - agy 1.1.12

- [heuristic] (driver/probabilistic) `[corpus]` Late-round finding MANUFACTURE tracks an exhausted TARGET,
  not an exhausted round budget. The known anti-pattern says a long review thread starts inventing findings
  once it runs dry. Measured across four rounds on one range where each round was given genuinely NEW
  unreviewed code (the previous round's fix commit): counts ran 6, 6, 4, 4 - never reaching zero - yet the
  FOURTH round's findings were all verified real, including three defects inside the driver's own fixes.
  So a non-zero late count is not itself the tell. Re-read the tell as: findings that rest on premises not
  in the artifact. Give a late round fresh unreviewed material and it stays productive; give it the same
  material again and it starts padding.
  - 2026-08-12 - agy 1.1.12

- [assumption] (driver/deterministic) `[verified]` Citation accuracy is STEERABLE by one instruction.
  A peer's quoted text is reliable while its line numbers are not. Adding the explicit direction
  "re-derive the line number from the file you actually read rather than estimating it" moved accuracy
  from 0 of 6 correct to 4 of 6 in the next round on the same corpus. It is a cheap, measurable lever -
  and worth spending, because a wrong line number costs the driver verification time on a real finding.
  - 2026-08-12 - agy 1.1.12

- [heuristic] (driver/probabilistic) `[corpus]` LICENSING the null answer gets honest nulls. Told in the
  brief that "no new findings" and "I could not find one" were named, correct, valid replies, a peer used
  both - including on the seat aimed directly at the construct under test, and on a question that asked it
  to enumerate bypasses. Those abstentions are evidence the construct held; without the licence the same
  slots return padding that has to be verified and discarded.
  - 2026-08-12 - agy 1.1.12

- [anti-pattern] (driver/deterministic) `[corpus]` A peer holding a LONG-LIVED conversation carries
  instructions from EARLIER tasks and can act on them inside a new, unrelated request - measured: it
  created a working file for a prior task's topic that the current request never mentioned, while
  otherwise following the current one. The stale directive fires silently and its side effects read as
  part of the current task. Scope each request explicitly and forbid acting on any earlier task's
  instructions by name, rather than assuming a fresh request resets the peer's obligations.
  - 2026-08-12 - agy 1.1.12

- [assumption] (driver/probabilistic) `[verified]` A peer's QUOTED TEXT is reliable while its LINE
  NUMBERS are not: in one review every one of six citations quoted real code and every one named the
  wrong line, several off by hundreds and one citing a line beyond the file's length. Measured on two
  different underlying models, so treat it as general rather than a property of one. Anchor every
  finding on the quoted string and re-locate it yourself; never act on a peer's line number, and never
  dismiss a finding because its line number is wrong.
  - 2026-08-12 - agy 1.1.12

- [anti-pattern] (driver/deterministic) `[corpus]` A forbidden-actions banner that states the same
  permission TWICE in conflicting terms - forbidding a scratch location and then offering one inside
  it - leaves the peer to resolve the contradiction, and it may resolve it by writing somewhere worse
  (the repository root). **REFUTED THE SAME SESSION - see the entry below: a CORRECTED, non-contradictory
  banner did not stop it either, so the contradiction was not the cause.**
  State each permission exactly once, name the single permitted write location positively, and forbid
  creation everywhere else in the same clause.
  - 2026-08-12 - agy 1.1.12

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

- [anti-pattern] (driver/deterministic) A peer's file-DISCOVERY tools may honour the repository's ignore-file, so an artifact living under an ignored path reads to the peer as NON-EXISTENT even though a direct read by exact path would succeed - it may then report the file missing and refuse the whole task. Measured: a glob of the containing directory returned 3 entries where the directory held 60. When pointing a peer at an ignored or untracked artifact, give the EXACT path, state plainly that discovery will not list it, and instruct a direct read; require it to quote the read error rather than infer absence from a listing.  ·  `[corpus]` · 2026-08-11
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
- [heuristic] (driver/probabilistic) A peer finding whose stated MECHANISM is wrong can still be pointing at a REAL defect on the line it cites. The causal story and the location fail independently: the peer reads the line correctly and then reasons badly about why it is wrong. So verify the LINE before judging the explanation - a driver who refutes the mechanism and closes the finding discards the defect along with it. Measured: a finding claimed a cross-reference pointed at deleted text (false - the text had been replaced), while the same line really did contradict a correction made in that very commit.  ·  `[corpus]` · 2026-08-12
- [anti-pattern] (driver/probabilistic) A review brief that asks numbered questions ALONGSIDE a findings table will get its most serious defect delivered as a QUESTION ANSWER rather than a table row, where it is easily skimmed past. Measured: the highest-severity defect of one round - a reachable ordering bug - arrived only in the prose reply. The peer treats the table as "the findings you asked for" and the questions as somewhere else to put things. Add an explicit line telling it to promote anything real from an answer into the table, and read every answer as a possible finding; adding that line visibly changed later rounds.  ·  `[corpus]` · 2026-08-12
- [heuristic] (driver/probabilistic) When a peer reports "A contradicts B" it usually does not adjudicate, and the side its framing implies is wrong is often the CORRECT one. Measured twice in one review: both times it framed the new text as contradicting an existing table, and both times the TABLE was the false side - folding as framed would have corrected the correct half. Require every contradiction finding to name which side it believes is false and why, then check that claim independently of the contradiction itself.  ·  `[corpus]` · 2026-08-12
- [assumption] (driver/probabilistic) A peer given ONE substantive counter-turn - pointed at file and line and asked to re-derive, never handed your own measurement - will reverse its position outright rather than defend it, including reversing MULTIPLE independent recommendations at once. Measured: it flipped both of two unrelated decisions after a single counter-turn, conceding its load-bearing argument rested on an invariant that did not exist and that its own proposed alternative failed the threat it had itself described. Do not read a total reversal as capitulation - check whether it re-derived from the files (creditable) or merely agreed (not) - and verify the REVERSED position as freshly as the original.  ·  `[corpus]` · 2026-08-12
- [heuristic] (driver/probabilistic) A peer's finding about a repeated fact will name SOME instances and miss others, so treat every such finding as a lead rather than an inventory. Measured: it named two of three sites of a duplicated rule; the third used a paraphrase and evaded both its search and the driver's own first grep. Always re-sweep the FACT in several wordings after accepting an instance-list finding.  ·  `[corpus]` · 2026-08-12
- [assumption] (driver/deterministic) A numbered quote-check with an out-of-range line number as its control separates a peer that opened the file from one reconstructing it from context: asked to quote line N verbatim "or reply DOES NOT EXIST", a reading peer returns the literal DOES NOT EXIST for a line past EOF and exact text for the real ones. Give the licence explicitly, put the control among genuine line numbers, and place it far past EOF rather than at EOF+1. This is the cheap standing defence against a confidently fabricated review.  ·  `[corpus]` · 2026-08-12
- [anti-pattern] (driver/deterministic) A review-only banner that states only the POSITIVE placement rule ("write any scratch output under <named dir>") is a materially weaker constraint than the same rule paired with an ENUMERATED NEGATIVE ("and never into the working directory, never at the repository root"). Measured across four consults in one review: the round whose banner carried the negative clause produced no stray file; the driver then shortened the banner for later rounds, and the first later round that actually demanded a fresh measurement wrote a scratch script to the repository root. Two variables moved together (weaker wording, higher measurement demand) so this is correlation rather than proven causation - but the negative clause is free, so never drop it once written. Corollary: when a stray write appears, diff your OWN banners across rounds before attributing it to the peer.  ·  `[corpus]` · 2026-08-12
- [anti-pattern] (driver/deterministic) A peer asked to audit a body of work will silently audit only PART of it, and its own "files I read" block is the cheapest place to catch that. Measured: a coverage audit listed nine files where the brief scoped fifteen, omitting the largest test file and the very document its headline finding was about. Always require a machine-checkable list of files actually opened, DIFF it against the scope you set, and audit the remainder yourself - the unread remainder is where the driver's own independent read found a gap the peer never had the chance to see.  ·  `[corpus]` · 2026-08-12
- [anti-pattern] (driver/deterministic) A peer's file-DISCOVERY tools may honour the repository's ignore-file, so an artifact living under an ignored path reads to the peer as NON-EXISTENT even though a direct read by exact path would succeed - it may then report the file missing and refuse the whole task. Measured: a glob of the containing directory returned 3 entries where the directory held 60. When pointing a peer at an ignored or untracked artifact, give the EXACT path, state plainly that discovery will not list it, and instruct a direct read; require it to quote the read error rather than infer absence from a listing.  ·  `[corpus]` · 2026-08-11
- [anti-pattern] (driver/probabilistic) A peer REFUTING your work deserves the same measurement you give a peer FINDING a defect, because a refutation fails in a quieter way. Measured: a peer called a defensive call dead because an adjacent guard "already skips such lines" - it conflated two neighbouring concepts (a line that is ENTIRELY whitespace, which the guard did skip, with a line that has content AND padding, which it did not), and the call was load-bearing. Accepting it would have removed working code on a confident and wrong argument. Check a refutation against the same standard as a finding: run the predicate on both cases and read the answer.  ·  `[corpus]` · 2026-08-12
- [assumption] (driver/deterministic) A peer can return a CLEAN verdict while its own body lists findings worth folding, because it is scoring the artifact rather than applying your stop condition. Measured: a review answered "clear it" and, in the same reply, three defects that each earned a fix. Read the findings and apply the discipline yourself - the verdict token is the peer opinion, not the gate. Corollary that is cheap and worked: ask the stop question EXPLICITLY as its own numbered item ("should this review stop - answer from severity and reachability, not round count, and do not manufacture a finding to justify continuing"), because a peer asked directly will recommend stopping honestly while a peer left to infer it keeps producing rounds.  ·  `[corpus]` · 2026-08-12
- [heuristic] (driver/probabilistic) The round AFTER a fold is where the next defect lives, and this holds even when the fold was correct. Measured across five consecutive review rounds on one small artifact: every fold but the last contained a defect, and the most serious single finding of the whole run was a hole the PREVIOUS round fix had introduced - a change made for good reasons on one axis that broke a different axis nobody was looking at. Never accept a verdict on the fold that produced it; run one more round whose explicit subject is the fix, and treat a round that folds NOTHING as the only valid stopping state.  ·  `[corpus]` · 2026-08-12
- [heuristic] (driver/probabilistic) A review payload that POINTS AT a file for its seat list and protocol yields a thinner review than one that INLINES them, even when the peer does read the file; measured back-to-back on the same artifact, the pointer round returned 5 findings of which 4 died under measurement, the inline round returned 6 of which 3 were real defects. Inline the protocol; use the file for detail only.  ·  `[corpus]` · 2026-08-15

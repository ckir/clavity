# agy observations inbox (raw, project-agnostic)

Captured live by `agy-learn`; drained by `agy-curate` into the GROWTH region of the shared
golden-header (`golden-header.growth.md`) via `curate-commit`. The driver-owned SEED manuals
(`agy-capabilities.md` / `agy-assumptions.md`) are never edited by this loop. One bullet per
observation. Project nouns are forbidden here (Structured Abstraction Schema). Provenance tags:
`[corpus]` observed live · `[doc]` from docs · `[local]` this install · `[verified]` ≥2 sources.

## Pending

- [assumption] (driver/deterministic) `[corpus]` An oversized reply can fail the ask transport OUTRIGHT — surfacing
  as a tool ERROR, not as a truncated answer — while the peer has already completed the work in full. The error is
  therefore not evidence the request was lost. Distinguish the two cases by STEP COUNT: a pre-ask reading vs a
  post-error reading that has advanced (and returned to idle) proves the payload landed and was processed. The
  recovery move is NOT to re-send the original request — that double-posts a visible message, burns quota, and makes
  the peer redo the analysis — but to send a small follow-up that explicitly says the reply was lost in transport,
  forbids redoing the work or re-reading files, and demands the SAME conclusions re-stated under a hard character
  budget. This reliably retrieves the parked result. Note the trajectory read-back is not a substitute: it is
  size-bounded and can be truncated to older steps, so it may show none of the relevant exchange even when the
  reply exists. (Refines the already-promoted parked-reply-recovery rule, which covered the truncate-to-HEAD and
  hang modes but not the hard transport-error mode nor the compact-restatement retrieval move.)

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

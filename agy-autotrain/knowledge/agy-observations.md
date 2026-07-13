# agy observations inbox (raw, project-agnostic)

Captured live by `agy-learn`; drained by `agy-curate` into the canonical manual
(`agy-capabilities.md` / `agy-assumptions.md`) and recompiled into `golden-header.md`. One bullet per
observation. Project nouns are forbidden here (Structured Abstraction Schema). Provenance tags:
`[corpus]` observed live · `[doc]` from docs · `[local]` this install · `[verified]` ≥2 sources.

## Pending

- [assumption] (driver/deterministic) An oversized single-turn *reasoning* reply does NOT trip the idle-wait "false hang" — the peer goes idle normally, but the bounded transport truncates the delivered reply to its HEAD (a size flag signals the truncation). The hang/timeout failure mode is specific to bundled tool-actions or serialized deep consults, not a large single reply. Recover truncation by re-asking for ONLY the missing tail (decompose) or routing the reply through file transport; the full content exists peer-side and is fully recoverable.  ·  `[corpus]` · 2026-07-13 · agy 1.1.1

<!-- drained 2026-07-13, then re-opened with 1 fresh capture (above) from the 2026-07-13 verify-harness re-run -->
<!-- empty — drained 2026-07-13 (see drain log below) -->

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

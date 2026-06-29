# agy observations inbox (raw, project-agnostic)

Captured live by `agy-learn`; drained by `agy-curate` into the canonical manual
(`agy-capabilities.md` / `agy-assumptions.md`) and recompiled into `golden-header.md`. One bullet per
observation. Project nouns are forbidden here (Structured Abstraction Schema). Provenance tags:
`[corpus]` observed live · `[doc]` from docs · `[local]` this install · `[verified]` ≥2 sources.

## Pending

- [anti-pattern] Asking the peer agent to ASSERT verifiable EXTERNAL facts it cannot observe (does a CLI command/flag/file exist, exact API/wire shapes) makes it CONFABULATE confidently — the wrong answer is a DRIVING fault (bad question framing), not the agent being unreliable. It is a reasoning/judgment engine, not a fact oracle: scope questions to JUDGMENT / design / red-teaming (its strength) and FEED the ground truth (paste the --help, the file, the schema) instead of asking it to recall. It still reliably surfaces real author blind-spots — keep using it for that — but verify any bare factual claim it volunteers.  ·  `[corpus]` · 2026-06-29
- [heuristic] Rotating the reviewer persona across rounds (correctness → contract/ops → security → UX → feasibility) surfaces progressively DISTINCT real flaws; returns diminish and go negative once the reviewer starts repeating an already-refuted claim — stop there.  ·  `[corpus]` · 2026-06-29

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

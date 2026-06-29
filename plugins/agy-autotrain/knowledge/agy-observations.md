# agy observations inbox (raw, project-agnostic)

Captured live by `agy-learn`; drained by `agy-curate` into the canonical manual
(`agy-capabilities.md` / `agy-assumptions.md`) and recompiled into `golden-header.md`. One bullet per
observation. Project nouns are forbidden here (Structured Abstraction Schema). Provenance tags:
`[corpus]` observed live · `[doc]` from docs · `[local]` this install · `[verified]` ≥2 sources.

## Pending

- [anti-pattern] Asking the peer agent to ASSERT verifiable EXTERNAL facts it cannot observe (does a CLI command/flag/file exist, exact API/wire shapes) makes it CONFABULATE confidently — the wrong answer is a DRIVING fault (bad question framing), not the agent being unreliable. It is a reasoning/judgment engine, not a fact oracle: scope questions to JUDGMENT / design / red-teaming (its strength) and FEED the ground truth (paste the --help, the file, the schema) instead of asking it to recall. It still reliably surfaces real author blind-spots — keep using it for that — but verify any bare factual claim it volunteers.  ·  `[corpus]` · 2026-06-29
- [heuristic] Rotating the reviewer persona across rounds (correctness → contract/ops → security → UX → feasibility) surfaces progressively DISTINCT real flaws; returns diminish and go negative once the reviewer starts repeating an already-refuted claim — stop there.  ·  `[corpus]` · 2026-06-29
- [heuristic] The peer agent can carry a VERY large installed skill catalog (observed 1500+ skills, incl. a full review-lens suite: requesting/receiving-code-review, systematic-debugging, TDD, verification-before-completion). Its review power is then gated by skill SELECTION, not availability: name the DOMAIN + the LENS explicitly in a consult (e.g. "apply your <domain> / security / wire-contract review lens") so it engages the matching specialized skill instead of a generic pass. Breadth stays latent until the payload steers it.  ·  `[corpus]` · 2026-06-29
- [anti-pattern] Framing a root-cause consult around your OWN hypothesis ("confirm that X is the cause") anchors the peer to CONFIRM it — it will even marshal observable evidence it pulls (logs, tool output) to FIT your premise rather than independently deriving the true cause, yielding a confident false-GREEN. Present the symptoms and raw evidence NEUTRALLY and ask it to derive the cause itself; never embed your hypothesis as the premise. (Distinct from the fact-oracle anti-pattern: here the peer CAN observe the evidence, yet the leading frame still biases its conclusion — so neutral framing matters even when grounding data is available.)  ·  `[corpus]` · 2026-06-29
- [anti-pattern] Seeding a review with a SPECIFIC known defect + its fix and asking the peer to "find more like this" makes it OVER-APPLY the pattern: it flags every superficially-similar construct as having the same bug WITHOUT verifying the underlying mechanism, producing a flood of confident false positives (observed: told of a CRLF-in-loop bug, it then claimed the same defect in scalar captures that a language built-in already sanitizes). Mitigation: ask for an open bug hunt WITHOUT naming the class, or require it to PROVE each instance against the actual mechanism (cite the exact failing operation), and independently measure before mass-acting on its hits. The symptom-name anchors it harder than a neutral "audit for correctness."  ·  `[corpus]` · 2026-06-29

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

---
name: agy-curate
description: Periodic maintenance — drain the agy-observations inbox into the canonical manual, dedupe/prune/resolve drift, re-verify testable claims, recompile the golden header, and empty the inbox. Run when the inbox grows or before promoting knowledge to global.
---

# agy-curate — drain the inbox, optimise the manual, recompile the header

Deliberate and offline. This is the optimiser of the loop. Inputs: `../../knowledge/agy-observations.md`
(inbox), `../../knowledge/agy-capabilities.md` + `../../knowledge/agy-assumptions.md` (canonical),
`../../verify/assertions.md` (probes).

## For each inbox entry — decide

- **promote** — into the right canonical section (capabilities for strengths/routing/heuristics;
  assumptions for testable constraints; **anti-patterns → a "Failure Modes" section in
  `agy-assumptions.md`**). Subject to the **promotion rubric** below.
- **reinforce** — already canonical: add a corroborating provenance tag / bump confidence.
- **contradict** — conflicts with a canonical claim: resolve it. Newer `[local]`/`[corpus]` wins for the
  current agy version; if sources genuinely disagree, record a `[conflict]`.
- **drop** — noise, too specific, or duplicate.

## Promotion rubric (curation-fatigue guard — do not skip)

- A **Heuristic** promotes only with **≥2 independent observations across different sessions**
  (one-off impressions stay in the inbox).
- An **Empirical Assumption** promotes only after a **100% pass in the verify harness**:

  > 🛑 STOP: before promoting any Empirical Assumption you MUST open `../../verify/run-verification.md`,
  > physically execute its synthetic `clavity ask` probe against the live agy, and record the real
  > outcome in `../../verify/assertions.md`. Never mark a probe "pass" from memory or assumption.

  If a probe **fails**, that is drift: keep/return the item to the inbox, fix the canonical claim, and
  update its probe alongside.

## Recompile the golden header

Rewrite `../../knowledge/golden-header.md` from the now-current canonical docs — dense, payload-ready:

1. **`[⚠️ CRITICAL ANTI-PATTERNS]` at the very top** — the failure modes the driver must avoid (extracted
   and front-loaded; knowing how *not* to prompt agy is the most actionable context).
2. The handful of load-bearing **Empirical Assumptions** (banner-honored, latency, new-thread replies,
   checkpoint discipline).
3. Keep it short — it is prepended to *every* `clavity ask`; trim anything not decision-changing.

## Finish

- **Empty the inbox** (entries are now canonical or dropped) — reset `## Pending` to empty.
- Stamp the canonical docs' "verified against agy <version>" where probes were re-run.
- If the loop has proven out in-project, this is the point to **promote** the skills + knowledge to the
  global config (the trial-then-globalise step).

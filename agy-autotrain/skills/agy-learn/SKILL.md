---
name: agy-learn
description: Use the moment you learn something general about the agy peer (a strength, latency fact, failure mode, or a prompting anti-pattern in how you drove it). Sanitises the observation into a project-agnostic rule and appends it to the knowledge inbox. Fast, live, mid-task.
---

# agy-learn — capture one agy observation, project-agnostic

Capture is cheap and live; curation is slow and offline (see **agy-curate**). This skill only appends
to the inbox — it never edits the canonical docs.

## Step 1 — Structured Abstraction Schema (the hard gate)

Do NOT free-text "strip the project nouns" — you will leak context. Force the observation through three
fields and **store only the third**:

- `[Abstract Context Pattern]` — the *kind* of situation, no specifics. (e.g. "resolving a
  time-of-check/time-of-use race in persisted state")
- `[Observed Agent Behavior]` — what agy did, no specifics. (e.g. "identified a missing DB uniqueness
  constraint spanning async boundaries")
- `[General Rule]` — the portable takeaway, **zero** project nouns (no language, file, ticket, product,
  or company names). (e.g. "agy can trace concurrency flaws across files when asked to review
  data-flow safety — seed it the invariant")

If you cannot express a real `[General Rule]` without a project noun, **do not capture it.** An empty
inbox beats a project journal.

## Step 2 — Classify the entry

- **Empirical Assumption** — a *testable* constraint about agy (e.g. "honors a loud REVIEW-ONLY banner:
  makes no edits"). These get a probe in `../../verify/assertions.md` and gate on the harness.
- **Heuristic** — a soft routing/driving guideline (e.g. "agy verifies better than it discovers").
- **Anti-Pattern** — a way *the driver* breaks agy (e.g. "a long checklist with no intermediate
  checkpoints → agy silently skips a step"). The highest-value class: it sharpens the driving protocol.

## Step 3 — Append one bullet to the inbox

Append to `../../knowledge/agy-observations.md` (create it with the header below if missing). One line:

```
- [<class>] <General Rule>  ·  `[corpus]` · <YYYY-MM-DD> · agy <version-if-known>
```

where `<class>` ∈ `assumption | heuristic | anti-pattern`. Then return to your task immediately —
do not curate now. The inbox is drained later by **agy-curate**.

## Inbox file header (create if missing)

```
# agy observations inbox (raw, project-agnostic)

Captured live by `agy-learn`; drained by `agy-curate` into the canonical manual. One bullet per
observation. Project nouns are forbidden here (Structured Abstraction Schema). Provenance tags:
`[corpus]` observed live · `[doc]` from docs · `[local]` this install · `[verified]` ≥2 sources.

## Pending
```

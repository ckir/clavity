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

## Step 2 — Classify the entry (the two-axis tag)

Every entry must carry EXACTLY ONE tag from each axis (spec §5.C-A):
1. **Target:** is this about the `peer` (model psychology/limits) or the `driver` (tools, bridge, UI)?
2. **Determinism:** is this `probabilistic` (a tendency) or `deterministic` (a hard reproducible failure)?

*Examples:*
- `peer/probabilistic` → agy tends to agree with a leading question.
- `driver/deterministic` → the VS Code extension truncates stdout at 8KB.

Do NOT invent tags. The four valid combinations are exhaustively binned during curate triage:
- `peer/probabilistic` → Golden-Header manual.
- `peer/deterministic` → *Does not exist (models are not deterministic). Treat as probabilistic.*
- `driver/probabilistic` → Driver Cheatsheet (carried until fixed).
- `driver/deterministic` → Fix-the-tool backlog (not knowledge, fix it).

## Step 3 — Append one bullet to the inbox

Append to `../../knowledge/agy-observations.md` (create it with the header below if missing). One line:

```
- [x] <target>/<determinism> · <General Rule>  ·  `[corpus]` · <YYYY-MM-DD> · agy <version-if-known>
```

Then return to your task immediately — do not curate now. The inbox is drained later by **agy-curate**.

## Inbox file header (create if missing)

```
# agy observations inbox (raw, project-agnostic)

Captured live by `agy-learn`; drained by `agy-curate` into the canonical manual. One bullet per
observation. Project nouns are forbidden here (Structured Abstraction Schema). Provenance tags:
`[corpus]` observed live · `[doc]` from docs · `[local]` this install · `[verified]` ≥2 sources.

## Pending
```

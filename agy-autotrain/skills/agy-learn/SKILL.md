---
name: agy-learn
description: Use the moment you learn something general about the agy peer (a strength, latency fact, failure mode, or a prompting anti-pattern in how you drove it). Sanitises the observation into a project-agnostic rule and appends it to the knowledge inbox. Fast, live, mid-task.
---

# agy-learn - capture one agy observation, project-agnostic

Capture is cheap and live; curation is slow and offline (see **agy-curate**). This skill only appends
to the inbox - it never edits the canonical docs.

## Step 1 - Structured Abstraction Schema (the hard gate)

Do NOT free-text "strip the project nouns" - you will leak context. Force the observation through three
fields and **store only the third**:

- `[Abstract Context Pattern]` - the *kind* of situation, no specifics. (e.g. "resolving a
  time-of-check/time-of-use race in persisted state")
- `[Observed Agent Behavior]` - what agy did, no specifics. (e.g. "identified a missing DB uniqueness
  constraint spanning async boundaries")
- `[General Rule]` - the portable takeaway, **zero** project nouns (no language, file, ticket, product,
  or company names). (e.g. "agy can trace concurrency flaws across files when asked to review
  data-flow safety - seed it the invariant")

If you cannot express a real `[General Rule]` without a project noun, **do not capture it.** An empty
inbox beats a project journal.

## Step 2 - Classify the entry

- **Empirical Assumption** - a *testable* constraint about agy (e.g. "honors a loud REVIEW-ONLY banner:
  makes no edits"). These get a probe in `../../verify/assertions.md` and gate on the harness.
- **Heuristic** - a soft routing/driving guideline (e.g. "agy verifies better than it discovers").
- **Anti-Pattern** - a way *the driver* breaks agy (e.g. "a long checklist with no intermediate
  checkpoints -> agy silently skips a step"). The highest-value class: it sharpens the driving protocol.

### Also tag two axes (the triage inputs `agy-curate` reads - spec section 4)

- **Audience:** `peer` (shapes the agy peer's behavior -> destined for the golden-header) *
  `driver` (shapes how *you* drive the peer -> destined for the driver cheatsheet or a tool fix).
- **Nature:** `probabilistic` (peer psychology / judgment tendency - NOT mechanically fixable) *
  `deterministic` (a reproducible tool/bridge behavior with a reproducible workaround - a software defect).

If a `deterministic` observation's only mitigation is a *driving move* (not a code change), it is still a
knowledge rule - `agy-curate` decides tool-fixability. Capture the axes; do not pre-judge the routing here.

## Step 3 - Append one bullet to the inbox

### Resolve the inbox FIRST - this skill ships in more than one copy

**There is exactly ONE live inbox: the one the nudge hook counts.** That hook resolves
`${CLAUDE_PLUGIN_ROOT}/knowledge/agy-observations.md`, which for a hook is the INSTALLED plugin tree.
**A path relative to THIS file is not that path** whenever the skill is invoked from a repo checkout or a
git worktree, because those carry their own `agy-autotrain/knowledge/agy-observations.md`.

**MEASURED 2026-08-15, and this is why the rule exists:** the two inboxes had diverged to **30 pending in
the repo copy and 18 in the installed one, with ZERO overlap** - four capstone sessions' worth of real
captures written to a copy nothing drains and nothing counts. They were committed to git, so they looked
saved; they were simply invisible to the loop.

Resolve in this order, and do not skip to the fallback:

1. **`$CLAUDE_PLUGIN_ROOT/knowledge/agy-observations.md`** if that variable is set. (It is set for HOOK
   invocations. **Measured: it is UNSET in a skill-context shell call**, so expect to fall through.)
2. **This skill's own base directory** - the harness states it when the skill is invoked - resolved as
   `<base>/../../knowledge/agy-observations.md`, **but ONLY if that base directory is the INSTALLED
   plugin tree** (on Windows, under `.../Programs/agy-autotrain/plugins/agy-autotrain/...`).
3. **If the base directory is a repository checkout or a worktree, STOP.** Do not append there and do not
   invent a path. Say so, and ask where the installed inbox is. **A capture written to the wrong copy is
   worse than a capture not taken**: it reads as done, it survives review, and it never reaches curation.

**Then verify what you actually wrote**, in the same turn: print the resolved absolute path and the new
pending count. If that path is not the one the nudge reports on, the capture did not land.

Append to the resolved inbox (create it with the header below if missing). One line:

```
- [<class>] (<audience>/<nature>) <General Rule>  *  `[corpus]` * <YYYY-MM-DD> * agy <version-if-known>
```

**The separator shown above is an ASCII asterisk so this document itself stays pure ASCII. The LIVE inbox
delimits with U+00B7 MIDDLE DOT, not an asterisk** - match the existing bullets in the file you are
appending to, not this rendering.

where `<class>`  in  `assumption | heuristic | anti-pattern`, `<audience>`  in  `peer | driver`,
`<nature>`  in  `probabilistic | deterministic`. Then return to your task immediately -
do not curate now. The inbox is drained later by **agy-curate**.

## Inbox file header (create if missing)

```
# agy observations inbox (raw, project-agnostic)

Captured live by `agy-learn`; drained by `agy-curate` into the GROWTH region of the shared
golden-header (`golden-header.growth.md`) via `curate-commit`. The driver-owned SEED manuals
(`agy-capabilities.md` / `agy-assumptions.md`) are never edited by this loop. One bullet per
observation. Project nouns are forbidden here (Structured Abstraction Schema). Provenance tags:
`[corpus]` observed live * `[doc]` from docs * `[local]` this install * `[verified]` >=2 sources.

## Pending
```

**Same caveat as above:** the provenance-tag separators rendered here as `*` are **U+00B7 MIDDLE DOT** in
the live inbox. `agy-observations.md` carries a standing `encoding` exemption for exactly that reason; this
file does not, which is why the code point is named rather than pasted.

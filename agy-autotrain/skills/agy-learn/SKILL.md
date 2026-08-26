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

### The inbox has exactly ONE path

```
<USERPROFILE or HOME>/.clavity/agy-observations.md
```

That is the whole rule. It is user-local state, beside the golden-header files, for exactly the reason
they live there: **every copy of this skill resolves it identically and nothing can shadow it.**

**Do NOT resolve it relative to this file, and do NOT consult `CLAUDE_PLUGIN_ROOT`.** This skill ships in
more than one copy - an install, a repo checkout, every git worktree - and a relative path resolves to
whichever copy happens to be running. **MEASURED 2026-08-15, which is why the inbox was moved out of the
plugin tree entirely:** the two inboxes had diverged to **30 pending in the repo copy and 18 in the
installed one, with ZERO overlap** - four capstone sessions' worth of real captures written to a copy
nothing drained and nothing counted. They were committed to git, so they looked saved.

**Create the DIRECTORY if it is absent, not just the file.** `~/.clavity/` is created by a clavity
driver's installer, and this plugin can legitimately be installed with **no driver present** - its own
installer has no `[Dirs]` section and its post-install text says so. So a first capture on such a machine
must `mkdir -p` the directory before appending, or it fails on the one path that has no fallback left.

**An inbox left behind in a plugin tree is DEAD - ignore it.** Do not read it, do not merge it, do not
prefer it. The one-time migration of any such file is the installer's job and it runs once; anything
still sitting there afterwards is a stale artifact of an older layout.

**If the append fails, say so in the same turn rather than dropping the observation.** There is no
staging file any more and no fallback path to park it in - the single canonical location is what removed
the need for both - so a failure you swallow is an observation nobody ever finds.

### Appending is safe during a drain; this is why

**Appending is the SAFEST thing you can do, and it is not perfectly safe. Both halves are true and the
second was missing here until 2026-08-27.**

A drain moves the `## Pending` region to a staging snapshot and then rewrites the inbox. That closes the
LARGE window - an append landing during the 30-60s curator run goes into the now-empty `## Pending` and
drains next time, losing nothing. But `drain-lib.ps1` states the residue in as many words: *"a narrow
SUB-SECOND race remains - an agy-learn append between this read and the inbox rewrite is clobbered"*,
because this skill is deliberately a dumb, uncoordinated appender and coordination is a spec non-goal.

This paragraph previously said `agy-curate` "**claims** the inbox by renaming it before it reads
anything", and concluded "**neither case loses a bullet**". Neither statement was true: there is no
claiming rename of the inbox - the only `Move-Item` in that path moves a TEMP file onto the staging
snapshot - and the code comment asserts the opposite of the guarantee. Promising a safety property the
implementation documents as absent is worse than stating the residue, because it stops the reader taking
the one precaution that helps.

**So: only ever APPEND** - never read-then-rewrite the file, which would clobber whatever the drain is
about to write back - and if a bullet ever seems to vanish during a drain, that sub-second race is the
first thing to suspect rather than the last.

**Then verify what you wrote, with a check you can actually perform.** In the same turn, print the
**resolved absolute path** and the **new pending count** you observe after appending. Both are within
reach: you know the path and you can count the file.

Do not try to compare it against what the nudge hook reported. That hook runs at SessionStart and writes
to a previous session's output, which you cannot read mid-task. Printing the path and count is what lets
the OPERATOR make that comparison; your job is to surface the two facts, not to reconcile them.

> **KNOWN GAP, stated rather than papered over: this rule is unguarded by construction.** It is prose an
> agent follows, and nothing tests compliance - the verify-then-print step above is the only feedback, and
> it depends on the same agent. What the move DID buy is that the rule is now one line instead of a
> resolution order, so there is far less of it to get wrong. **A capstone reviewer once proposed a CI
> check asserting the repo copy of `agy-observations.md` is never modified; that fix was wrong and was
> rejected**, and after the move the repo no longer carries a live inbox at all, so the question is moot.

Append to that path (creating the directory, then the file with the header below, if absent). One line:

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

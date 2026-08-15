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
   `<base>/../../knowledge/agy-observations.md`, **unless that tree is a CHECKOUT.**

   **Test for the checkout, do not pattern-match the install.** Install roots vary by platform and by
   product (`.../Programs/<product>/plugins/...`, `~/.claude/plugins/cache/...`,
   `~/.gemini/config/plugins/...` are all real), so any "is it under X" test excludes a legitimate
   install somewhere and sends it to the STOP branch for no reason. The reliable discriminator is the
   opposite one, and it is platform-independent: **run `git -C <base> rev-parse --is-inside-work-tree`.
   A repo checkout or worktree answers `true`; an installed tree has no `.git` at or above it and
   answers non-zero.** Use the base directory only when that check says it is NOT a work tree.
3. **If it IS a work tree, do not append there.** But do not lose the observation either - see below.

**NEVER DISCARD THE CAPTURE IN ORDER TO OBEY THIS RULE.** Capture is cheap and mid-task, which is exactly
why an instruction to "stop and ask" loses observations: the rule interrupts a task the agent then
resumes, and the bullet exists only in a context window that moves on. So, in this order:

   a. **Write the bullet to `<USERPROFILE or HOME>/.clavity/agy-observations.staged.md` FIRST** (append,
      creating the file if absent). That directory is machine-local, outside every plugin tree and every
      checkout, and already holds the runtime golden-header files - so both copies of this skill resolve
      it identically and nothing can shadow it.
   b. **Then** tell the operator the capture is staged there and ask where the installed inbox is.

   **A capture written to the wrong copy is worse than a capture not taken** - it reads as done, survives
   review, and never reaches curation. A capture staged in a known machine-local file is neither.

**Then verify what you actually wrote**, in the same turn: print the resolved absolute path and the new
pending count. If that path is not the one the nudge reports on, the capture did not land.

> **KNOWN GAP, stated rather than papered over: this rule is unguarded by construction.** It is prose an
> agent follows, and nothing tests compliance - the verify-then-print step above is the only feedback, and
> it depends on the same agent. **A capstone reviewer proposed a CI check asserting the repo copy of
> `agy-observations.md` is never modified; that fix is wrong and was rejected** - the repo copy is the
> INSTALL SEED and is legitimately updated (it carries deliberately-committed entries today), so such a
> gate would forbid a normal operation and would already be failing. A presence-grep asserting these
> paragraphs exist would be the vacuous-oracle shape this project removes on sight. **The honest state is:
> unguarded, with the cost recorded here.**
>
> **Related debt, deliberately not fixed in this change:** the canonical inbox lives inside the plugin
> tree rather than the machine-local runtime directory that holds the golden-header files. Moving it there
> would remove the two-copies problem at the root instead of instructing around it. **It is NOT the
> emergency it looks like** - the installer excludes this file from the blanket copy and ships it
> `onlyifdoesntexist uninsneveruninstall`, so an update does not overwrite it and an uninstall does not
> remove it (a reviewer claimed the next update would destroy the backlog; the installer refutes that).
> The move touches both skills, the nudge hook and its suite, and the installer, so it is tracked work.

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

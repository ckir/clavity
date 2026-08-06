---
slug: inbox-snapshot-misses-slash-command-path
variant: both
observed: 2026-08-03
source-inbox-entry: "the pre-drain snapshot hook did not fire when agy-curate was invoked as a"
status: open
last-triaged: 2026-08-06   # oracle: hooks.json still registers only PreToolUse:Skill / SessionStart / PreCompact and has no UserPromptSubmit event at all -> neither mitigation landed, confirmed still open
---

# The pre-drain inbox snapshot silently does not happen when agy-curate is invoked as a slash command

## Steps to Reproduce

On a machine with agy-autotrain installed (verified against 0.3.0):

1. Note the newest snapshot: `ls -t <plugin>/knowledge/agy-observations.md.*.bak | head -1`
2. Invoke the curator as a **slash command**: `/agy-autotrain:agy-curate`
3. Re-check. **No new `.bak` is created.** Measured 2026-08-03: newest remained
   `agy-observations.md.20260803-072336.bak` from the previous drain, and it differed from the live file.
4. Now invoke the same skill through the **Skill tool** instead. A snapshot appears.

Root cause is in `<plugin>/hooks/hooks.json`:

```json
"PreToolUse": [ { "matcher": "Skill", "hooks": [ ... agy-inbox-snapshot.sh ... ] } ]
```

The matcher is the **`Skill` tool**. A slash-command invocation loads the skill body directly without
issuing a `Skill` tool call, so `PreToolUse` never fires for it. The slash command is the most natural
way to run this skill, so the common path is the unprotected one.

The `agy-curate` skill text already anticipates this — *"the `agy-inbox-snapshot` hook does this
automatically when this skill is invoked through the `Skill` tool; do it by hand if you got here another
way"* — but that is honor-system, and it failed in practice on the first slash-command run after the hook
was installed. The previous drain's log recorded "first run where it fired on its own", which reads as
"the automation now works" and makes a later reader less likely to check.

## Code-level Mitigation

The snapshot must not depend on which invocation path was used. In order of preference:

1. **Snapshot inside `curate-commit`.** Before accepting a GROWTH publish, have the binary copy the
   resolved inbox to a timestamped `.bak` and fail closed if it cannot. This is invocation-path-independent
   and covers the only step that can destroy inbox content. It does not cover a drain that resets the inbox
   without publishing, so pair it with 2.
2. **Add a `UserPromptSubmit` hook matching the slash-command name** (`^/agy-autotrain:agy-curate\b`)
   alongside the existing `PreToolUse` matcher, so both entry paths snapshot. Guard against
   double-snapshotting in one run by making `agy-inbox-snapshot.sh` a no-op when the newest `.bak` is
   already byte-identical to the live file — it should be idempotent regardless.
3. Failing both, make the FIRST step of the skill body a snapshot with a verify-and-abort, rather than a
   parenthetical aside that a reader who trusts the hook will skip.

Option 2 alone is the smallest change that closes the observed hole; option 1 is the one that survives a
future third invocation path.

## Notes

- Determinism: reproducible on demand, not a peer-judgment tendency — it is a matcher-scope bug in our own
  hook wiring, so it passes the determinism refusal gate with a concrete mitigation above.
- Variant: the hook ships in the agy-autotrain plugin, which is variant-agnostic, so `both`.
- No carried driver-cheatsheet rule is needed: the skill already documents the manual fallback. The defect
  is that the fallback is easy to skip, which a code fix removes rather than a driving rule.
- Sibling class: `curate-nudge-age-reads-drain-log-dates` — also a hook whose guard silently does not do
  what its presence implies. Both were found by RUNNING the drain, not by reading the hook.

## Disposition — open-work sweep, 2026-08-06

**KEPT — all three clauses met.**

1. **Silent loss.** The pre-drain snapshot does not happen on the slash-command path, so a drain that goes
   wrong has no `.bak` to recover from — and nothing reports the omission. Measured 2026-08-03: no new
   `.bak` appeared, and the newest one already differed from the live file.
2. **Unavoidable.** Invoking the curator as a slash command is the natural way to run it; the Skill-tool
   path that *does* snapshot is the less obvious one.
3. **Mechanism.** Register the missing event in `hooks.json` (there is no `UserPromptSubmit` registration
   today) or move the snapshot into the skill body. Two named options, both bounded.

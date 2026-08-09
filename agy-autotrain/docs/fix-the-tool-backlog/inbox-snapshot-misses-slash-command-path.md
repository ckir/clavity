---
slug: inbox-snapshot-misses-slash-command-path
variant: both
observed: 2026-08-03
source-inbox-entry: "the pre-drain snapshot hook did not fire when agy-curate was invoked as a"
status: fixed
last-triaged: 2026-08-07   # FIXED in 704a2e5. Mitigation 2 shipped, but NOT in the form proposed below - see "Fixed" section. Mitigation 1 was deliberately NOT implemented and should not be. The earlier PARTIAL note read: "covers mitigation 2 ONLY ... UNVERIFIED for mitigation 1 (a snapshot inside the curate-commit BINARY, which leaves no trace in hooks.json) and mitigation 3"; that caution was right, and investigating mitigation 1 properly is what showed it to be architecturally wrong.
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

The `agy-curate` skill text already anticipates this - *"the `agy-inbox-snapshot` hook does this
automatically when this skill is invoked through the `Skill` tool; do it by hand if you got here another
way"* - but that is honor-system, and it failed in practice on the first slash-command run after the hook
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
   already byte-identical to the live file - it should be idempotent regardless.
3. Failing both, make the FIRST step of the skill body a snapshot with a verify-and-abort, rather than a
   parenthetical aside that a reader who trusts the hook will skip.

Option 2 alone is the smallest change that closes the observed hole; option 1 is the one that survives a
future third invocation path.

## Notes

- Determinism: reproducible on demand, not a peer-judgment tendency - it is a matcher-scope bug in our own
  hook wiring, so it passes the determinism refusal gate with a concrete mitigation above.
- Variant: the hook ships in the agy-autotrain plugin, which is variant-agnostic, so `both`.
- No carried driver-cheatsheet rule is needed: the skill already documents the manual fallback. The defect
  is that the fallback is easy to skip, which a code fix removes rather than a driving rule.
- Sibling class: `curate-nudge-age-reads-drain-log-dates` - also a hook whose guard silently does not do
  what its presence implies. Both were found by RUNNING the drain, not by reading the hook.

## Disposition - open-work sweep, 2026-08-06

**KEPT - all three clauses met.**

1. **Silent loss.** The pre-drain snapshot does not happen on the slash-command path, so a drain that goes
   wrong has no `.bak` to recover from - and nothing reports the omission. Measured 2026-08-03: no new
   `.bak` appeared, and the newest one already differed from the live file.
2. **Unavoidable.** Invoking the curator as a slash command is the natural way to run it; the Skill-tool
   path that *does* snapshot is the less obvious one.
3. **Mechanism.** Register the missing event in `hooks.json` (as of the 2026-08-06 sweep there was no
   `UserPromptSubmit` registration; **one was added 2026-08-07 - see the Fixed section below**) or move the
   snapshot into the skill body. Two named options, both bounded.

## Fixed - 2026-08-07 (`704a2e5`)

`UserPromptSubmit` is now registered in `agy-autotrain/hooks/hooks.json`, and `agy-inbox-snapshot.sh`
accepts both payload shapes: `.tool_input.skill` from `PreToolUse`, and `.prompt` from `UserPromptSubmit`.
Both the jq path and the jq-absent fallback handle both shapes. Everything from the `[ -f "$OBS" ]` guard
onward - the three invariants, the dedup, the FIFO prune - is byte-identical to before.

**Pinning tests, all in `scripts/tests/agy-inbox-snapshot.Tests.ps1`:**

- `snapshots when agy-curate is invoked as a SLASH COMMAND` - the reported defect, verbatim.
- `snapshots on a slash command WITH trailing arguments` - `/agy-autotrain:agy-curate --dry-run`.
- `does NOT snapshot on an ordinary prompt that merely mentions agy-curate` - the control that keeps the
  match anchored rather than a bare substring.
- `still snapshots on the Skill-tool path` - regression guard on the path that already worked.
- `burns only ONE slot when both paths fire in the same drain` - the dedup invariant, which now matters
  more because the hook has two ways to fire in one drain.

### Two corrections to the mitigations proposed above. Both were established by measurement.

**Mitigation 2 shipped, but NOT as the declarative `matcher` regex it proposes.** The entry recommends
`"matcher": "^/agy-autotrain:agy-curate\b"` on the `UserPromptSubmit` registration. **Nothing establishes
that a `matcher` is evaluated against prompt text for that event.** The schema permits the key
syntactically, but both first-party plugins that register this event - `hookify` and `security-guidance`
- do so **bare** and inspect the prompt inside their own script. Building on the matcher would have been
an unchecked assumption, and it would have failed **silently**: the hook would simply never fire, which is
this very defect restored one layer down. **The registration is therefore bare and the match is done in
the script.**

**Mitigation 1 was NOT implemented, and should not be.** It says to snapshot "inside `curate-commit`".
`curate-commit` is not an agy-autotrain script - it is a **driver CLI verb implemented twice**, at
`clavity-dotnet/src/Clavity.Ls/CliVerbs.cs:36` and `clavity-classic/src/main.rs:700`. It reads the
compiled golden-header from stdin and writes the GROWTH region in a directory resolved from
`CLAVITY_GOLDEN_HEADER`. **It has no knowledge of the inbox at all.** Implementing mitigation 1 would make
the clavity driver binary, in two languages, depend on the *agy-autotrain plugin's* file layout
(`${CLAUDE_PLUGIN_ROOT}/knowledge/agy-observations.md`) - a coupling between two independently installed
plugins. The entry did not notice this, which is why mitigation 2 wins here rather than being the fallback
the entry treats it as.

Mitigation 3 (a snapshot as the skill body's first step) was not needed and was not implemented.

### Known limit

**A tab or newline between the command and its arguments does not trigger a snapshot.** MEASURED
2026-08-07 during the plan-2 capstone, with a firing space-separator control: `/agy-autotrain:agy-curate`
followed by a tab fails on **both** the jq path and the grep fallback, identically. The peer that raised it
predicted a divergence between the two paths; there is none, because the fallback greps the RAW payload,
where a tab is the two characters `\t` and a backslash is not `[[:space:]]`. The four `case` patterns are a
deliberate complete set and were not widened: a tab as an argument separator in a typed slash command is
below the reachability floor. Recorded here so the next reader does not re-derive it.

The fix covers the two invocation paths that exist today. A **third** future entry path would need the
same treatment - which is the durable concern mitigation 1 was reaching for, even though its specific
remedy is wrong. If a third path appears, the right answer is to widen this hook, not to couple the driver
binary to a plugin's file layout.

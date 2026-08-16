# Task 1 measurement - the skill base-directory locator

**Date:** 2026-08-16   **Commit:** 8a2c2dc

## Probe A - $CLAUDE_PLUGIN_ROOT in a skill-context shell call
- Result: <UNSET>
- Control (count of other CLAUDE_* vars visible to the same probe): 8
  (`CLAUDE_CODE_CHILD_SESSION`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_PID`, `CLAUDE_EFFORT`,
  `CLAUDE_CODE_USE_POWERSHELL_TOOL`, `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_EXECPATH`)

The control is non-zero, so the probe can see the environment and the UNSET result is meaningful.
M1 still holds.

## Probe B - the harness base-directory line for a `clavity:` skill
- Skill invoked: clavity:ls-driving
- Line present: YES
- Verbatim line: `Base directory for this skill: C:\Users\user\AppData\Local\Programs\clavity-dotnet\plugins\clavity\skills\ls-driving`

**Resolved-target check (not in the template; recorded because Panel R1 measured that a locator
resolving to a non-existent directory ships as a silent no-op that still passes a presence-grep).**
`<BASE>/../../hooks/` resolves to
`C:\Users\user\AppData\Local\Programs\clavity-dotnet\plugins\clavity\hooks`, which EXISTS and holds the
12 shipped `.sh` hooks plus `hooks.json`. So the relative walk is real, not merely well-formed.

## Consequence (tick exactly one)
- [x] **RESOLVED** - Probe B is YES. Task 4, Task 6 and ALL of Task 7 proceed, using
      `bash "<BASE>/../../hooks/agy-mark.sh"` as the invocation, where **`<BASE>` stays that literal
      token in the file** - it is the skill's own base directory as the harness supplies it at
      invocation time, NOT a path you write out. Task 7 Step 1 says the same; the two must agree,
      because writing a real path there differs per plugin and breaks the byte-identity pin.
- [ ] **BLOCKED** - Probe B is NO. Task 6 is SKIPPED and recorded as a tracked ROADMAP item.
      **Task 7 is NOT skipped: its 14c rows are skipped and its 14h rows still ship** - item 14h
      has no dependency on this locator. Tasks 5 and 8 (the hook half and the ROADMAP rewrite)
      still ship.
      **Task 4 is NOT skipped either: it ships its Step 1b append-corruption fix and DEFERS the
      helper call**, with 14c's skill half. Task 4's own header states this; it was missing from
      this list, and an executor following only this block would have shipped the helper call that
      Panel R1 measured as a silent no-op on exactly this path.
      **Do NOT invent a glob, a search path, or a hardcoded install location** (spec `:652`).

---

**Step 5 branch decision:** RESOLVED - the remaining plan proceeds unchanged. No task is skipped,
no ROADMAP deferral line is needed in Task 8.

> ⚠ A stale fixture copy of this file exists at
> `.clavity/scratch/capstone-14h/tree/docs/superpowers/plans/2026-08-14-anomaly-hotfix-batch-task1-measurement.md`
> containing the single line `- [x] **BLOCKED**`. It is a capstone-14h probe fixture under gitignored
> runtime state, NOT a prior measurement. This file is the measurement.

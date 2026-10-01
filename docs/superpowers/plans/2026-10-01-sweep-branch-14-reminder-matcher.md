# ROADMAP Sweep Branch 14 (section 57 + 57b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `agy-test-audit-reminder.sh` run on PowerShell tool calls and pin its matcher (section 57), and make `agy-mark-stamp.Tests.ps1` launch Git Bash rather than whatever `bash` PATH finds first (57b).

**Architecture:** One manifest line in each plugin's `hooks/hooks.json`, one new registration row, and two launch sites in one test suite. No hook script changes. A plugin pair, so a version bump (dotnet 0.10.0 -> 0.10.1, classic 0.9.0 -> 0.9.1), capstone, test audit and owner reinstall.

**Tech Stack:** Claude Code plugin `hooks.json`; Pester 5 (pwsh 7); Git Bash.

**Matcher semantics:** whether Claude Code anchors a `matcher` regex is not measured here and does not matter for
this change: the tool is named exactly `PowerShell`, which `Bash|PowerShell|Write|Edit` matches either way.

**Decisions (AGY-FIRST `.clavity/seams/branch14-forks.md`, ALIGNED, owner-approved 2026-10-01):** F1 matcher
`Bash|PowerShell|Write|Edit` (not `mcp__.*agy_ask`: a consult is not a code change); F2 pin with `Should -BeExactly`
like the sibling rows; F3 the seven-hook `input=$(cat)` anomaly stays on the conveyor (not this branch); F4 57b uses
`Get-GitBashOrThrow` at both sites.

---

## File structure

- Modify `clavity-dotnet/plugin/hooks/hooks.json:32` and `clavity-classic/plugin/hooks/hooks.json:32` - the
  matcher of the group that owns `agy-test-audit-reminder.sh`.
- Modify `scripts/tests/plugin-hooks-registration.Tests.ps1` - one `It ... -ForEach dotnet,classic` row after the
  `leaves agy-seam-inject.sh on PreToolUse Skill` row (currently `:120-126`). Suite 35 -> 37.
- Modify `scripts/tests/agy-mark-stamp.Tests.ps1` - dot-source `BashHookHelpers.ps1` in `BeforeAll`; `:19` and
  `:167` launch `$script:Bash`. Suite stays 11.
- Modify `scripts/tests/_partition.md:1095` - registration count 35 -> 37.
- Bump via `scripts/bump-version.ps1` (writes every version source, self-verifies).
- Modify `clavity-dotnet/ROADMAP.md` - close section 57 (and 57b) in its header.

---

### Task 1: Pin the reminder's matcher, then widen it (section 57)

**Files:**
- Test: `scripts/tests/plugin-hooks-registration.Tests.ps1` (insert after the row ending at `:126`)
- Modify: `clavity-dotnet/plugin/hooks/hooks.json:32`, `clavity-classic/plugin/hooks/hooks.json:32`

- [x] **Step 1: Write the failing row.** Insert after the `leaves agy-seam-inject.sh on PreToolUse Skill` row:

```powershell
    It 'registers agy-test-audit-reminder.sh on PostToolUse Bash|PowerShell|Write|Edit - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        # ROADMAP section 57. The hook reads no tool_name, so the matcher decides only WHEN it gets a chance
        # to run: without PowerShell a GREEN capstone's audit nudge waits for the next Bash/Write/Edit call.
        # EXACT, like the siblings: a 'contains PowerShell' pin would pass a matcher narrowed to PowerShell
        # alone. Not mcp__.*agy_ask - a consult is not a code change (AGY-FIRST, 2026-10-01).
        $matchers = @(Get-OwningMatchers -Manifest $script:Manifests[$Driver] -Event 'PostToolUse' -Script 'agy-test-audit-reminder.sh')
        $matchers.Count | Should -Be 1
        $matchers[0]    | Should -BeExactly 'Bash|PowerShell|Write|Edit'
    }
```

- [x] **Step 2: Run it; expect exactly the two new rows to fail.**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/plugin-hooks-registration.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 35, Failed: 2`; the two failures are the new row for dotnet and classic, each failing
on its `-BeExactly` line with `Bash|Write|Edit` as the actual value (read the failure text; the wording is Pester's).

- [x] **Step 3: Widen the matcher in both manifests** (line 32 in each):

```json
        "matcher": "Bash|PowerShell|Write|Edit",
```

- [x] **Step 4: Run it; expect green.** Same command. Expected: `Tests Passed: 37, Failed: 0`.

- [x] **Step 5: Mutant check (driver, not committed).** Revert ONLY the classic manifest line to `Bash|Write|Edit`:
expect exactly `registers agy-test-audit-reminder.sh ... - classic` red (and the dotnet row green); restore the
Step 3 line and confirm the two manifests are byte-identical in that block again (`git diff --stat` shows both).

- [x] **Step 6: Commit.**

```bash
git add clavity-dotnet/plugin/hooks/hooks.json clavity-classic/plugin/hooks/hooks.json scripts/tests/plugin-hooks-registration.Tests.ps1
git commit -m "fix(hooks): run the test-audit reminder on PowerShell calls and pin its matcher (section 57)"
```

### Task 2: Launch Git Bash in the stamp suite (57b)

**Files:**
- Modify: `scripts/tests/agy-mark-stamp.Tests.ps1:1-2`, `:19`, `:167`

The failing control already exists and is MEASURED: `.clavity/scratch/branch14/control57b.ps1` (System32 first on
PATH, as a plain pwsh on this box) gives `Passed=3 Failed=8`. Ten rows go through `Invoke-Stamp`; seven failed, and the
eighth failure is the degraded-clock row. The three that PASSED are the rejection rows (`:80`, `:89`, `:107`): they
assert only `ExitCode -Not -Be 0`, which WSL's exit 127 satisfies as well as the script's designed exit 64 - they
passed for the wrong reason (panel round 1, Mechanism Gamer). Step 1b fixes that first, so the control must then go
`Passed=0 Failed=11`. The oracle is that the same script gives `Passed=11 Failed=0` after the launcher fix.

- [x] **Step 1: Dot-source the helper.** Replace the first two lines of `BeforeAll`:

```powershell
BeforeAll {
    $script:Mark = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'clavity-dotnet/plugin/hooks/agy-mark.sh'
```

with:

```powershell
BeforeAll {
    $script:Mark = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'clavity-dotnet/plugin/hooks/agy-mark.sh'
    # PIN GIT BASH (ROADMAP section 57b). A bare `bash` is a PATH lookup, and from a plain pwsh on a machine
    # with WSL it resolves to C:\WINDOWS\system32\bash.exe first: MEASURED 2026-10-01, 8 of 11 rows then fail
    # with exit 127 and say nothing about agy-mark.sh. CI is green only because its runner has no WSL.
    . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
    $script:Bash = Get-GitBashOrThrow
```

- [x] **Step 1b: Make the three rejection rows name their rejection.** In each (the `It` lines are `:80`, `:89`,
`:107`; the assertion lines to replace are `:84`, `:102`, `:114`), replace
`$res.ExitCode | Should -Not -Be 0` with `$res.ExitCode | Should -Be 64` plus one message assertion (`Invoke-Stamp`
merges stderr into `.Out`), the oracle being `clavity-dotnet/plugin/hooks/agy-mark.sh` `stamp)` arm:

```powershell
            # :80 row (missing arguments)
            $res.ExitCode | Should -Be 64 -Because 'the usage error, not merely any failure: exit 127 from a bash that cannot run the script also fails'
            $res.Out      | Should -Match 'need <discipline> <consult-cascade-id> <review-cascade-id>'
            # :89 row (consult id)
            $res.ExitCode | Should -Be 64 -Because 'the whitespace check, not merely any failure'
            $res.Out      | Should -Match 'consult-cascade-id must not contain whitespace'
            # :107 row (review id)
            $res.ExitCode | Should -Be 64 -Because 'the whitespace check, not merely any failure'
            $res.Out      | Should -Match 'review-cascade-id must not contain whitespace'
```

Run the control: expect `Passed=0 Failed=11` (all three now red under WSL). Mutant (driver): delete the review-id
`case` block in `agy-mark.sh`; expect the `:107` row red on its `-Be 64` line (the call then exits 0 and writes an
ISOLATED row). Restore.

- [x] **Step 2: `:19`** - in `Invoke-Stamp`, replace `$out = & bash $script:Mark @MarkArgs 2>&1 | Out-String` with:

```powershell
            $out = & $script:Bash $script:Mark @MarkArgs 2>&1 | Out-String
```

- [x] **Step 3: `:167`** - replace the OUTER `bash` only:

```powershell
                & $script:Bash -c 'PATH="./shim:$PATH" bash "$1" stamp agy-capstone cascade-aaa cascade-bbb' _ $script:Mark 2>&1 | Out-Null
```

The inner `bash "$1"` stays: it is resolved by Git Bash's own PATH, which the `Git\bin\bash.exe` wrapper seeds
with `/usr/bin`, and the row prepends `./shim` inside bash, so the `date` shim still wins (AGY-FIRST F4).

- [x] **Step 4: Run the control; expect green under a WSL-first PATH.**

Run: `pwsh -NoProfile -File .clavity/scratch/branch14/control57b.ps1`
Expected: `first bash: C:\WINDOWS\system32\bash.exe` and `Passed=11 Failed=0`.

- [x] **Step 5: Run it normally too.** `pwsh -NoProfile -c "Invoke-Pester scripts/tests/agy-mark-stamp.Tests.ps1 -Output Detailed -CI"` -> `Tests Passed: 11, Failed: 0`.

- [x] **Step 6: Mutant check (driver, not committed).** Restore the bare `& bash` at `:19` only and re-run the
control: expect 10 red (every `Invoke-Stamp` row, the three rejection rows included after Step 1b) and the
degraded-clock row green. Then restore it at `:167` only:
expect exactly the degraded-clock row red. Restore the fixed file and confirm `git diff` shows only Steps 1-3.

- [x] **Step 7: Commit.**

```bash
git add scripts/tests/agy-mark-stamp.Tests.ps1
git commit -m "test(agy-mark-stamp): launch Git Bash, not the first bash on PATH (section 57b)"
```

### Task 3: Partition count, version bump, ROADMAP close

- [x] **Step 1:** `scripts/tests/_partition.md:1095` - `35 tests` -> `37 tests`, and append to that row's note
`(+2 2026-10-01: section 57 test-audit-reminder PostToolUse matcher row)`. Commit:
`test(partition): plugin-hooks-registration 35 -> 37 tests (section 57 row)`.

- [x] **Step 2: Bump.**

```bash
pwsh -NoProfile -File scripts/bump-version.ps1 dotnet 0.10.1
pwsh -NoProfile -File scripts/bump-version.ps1 classic 0.9.1
git diff --stat
```

Expected: each ends with its `check-versions.ps1` self-verify passing; the diff touches only version lines (the
same nine files as `fa394e52`). ISCC compile of `clavity-classic/installer/clavity-classic.iss` with `/O` passed
through `cygpath -w` prints `Successful compile`. Commit:
`chore(version): bump dotnet 0.10.0 -> 0.10.1 and classic 0.9.0 -> 0.9.1`.

- [x] **Step 3: Close the ROADMAP section.** In `clavity-dotnet/ROADMAP.md` `### §57` header append
` · ✅ **FIXED 2026-10-01 on sweep Branch 14 (`<task-1 sha>`, 57b `<task-2 sha>`) - the reminder runs on PowerShell
calls under an exactly-pinned matcher; the stamp suite launches Git Bash**`. Run
`pwsh -NoProfile -File scripts/check-roadmap-claims.ps1` -> `OK`. Tick this plan's boxes. Commit:
`docs(roadmap): close section 57 and publish the Branch 14 plan` (stage the ROADMAP and this plan).

### Task 4: Full gates (driver, before the capstone)

- [x] The FULL `scripts/tests` suite, detached, Git `usr\bin` first on PATH (NOT `test-scripts-fast`; a bare `bash`
in a plain pwsh resolves to WSL). Expected: 0 failed. lefthook pre-push `--all-files` exit 0. Then AGY-CAPSTONE over
`b2eb9d5b..HEAD`, AGY-TEST-AUDIT, merge `--no-ff` to local main, HALT for the owner's reinstall (install 0.10.1).

---

## Self-review

- Spec coverage: section 57 fix outline (matcher in both plugins + an exact registration row killed by a mutant)
  -> Task 1; "the hook reads no tool_name - verify" -> measured (0 matches) before planning; 57b outline (helper
  dot-sourced, both sites, failing control first) -> Task 2; blast radius (bump, capstone, audit, reinstall) ->
  Tasks 3-4.
- Not covered, deliberately: the seven-hook `input=$(cat)` anomaly (F3); a repo-wide guard against bare `bash` in
  any `*.Tests.ps1` (a candidate for the test audit, not this plan - no other suite has one today, grep-measured).
- Line citations grep-verified 2026-10-01 at `b2eb9d5b`: `hooks.json:32` (both), registration row `:120-126`,
  stamp `:19`/`:167`, `_partition.md:1095`.

## Stand-downs

Panel round 1 (solo + agy cascade `c16d9026`, PANEL VERDICT GREEN, two DEBT items folded: the assertion line numbers
in Task 2 Step 1b, and the matcher-anchoring note above). Below the floor (agy): whether `NotebookEdit` should also
wake the hook - no such call occurs in this workflow and the ROADMAP outline scopes the change to PowerShell; the inner
`bash "$1"` at `:167` resolving differently under a future Git for Windows - the wrapper's PATH seeding is what
`BashHookHelpers.ps1` already relies on for every other hook suite.

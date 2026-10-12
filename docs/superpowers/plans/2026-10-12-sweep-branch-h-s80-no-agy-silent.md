# Branch H, section 80: `.no-agy` makes the liveness hook silent - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** With a `.no-agy` kill-switch present and nothing else wrong, `agy-liveness-check.sh` prints nothing at all (today it still sends the model one `suppressed by .no-agy at <path>` line).

**Architecture:** In both branches of the hook (no-`jq` and `jq`), the `.no-agy` check stops announcing. The `jq` branch keeps emitting the ownership/override notes it already collects (they are actionable faults), without the suppression sentence. Nothing else in the hook changes.

**Tech Stack:** bash 3.2+ hook; PowerShell 7 + Pester 6 suite; the repo `justfile` gates.

**Spec:** `clavity-dotnet/ROADMAP.md` entry `### §80` (owner ruling 2026-10-08: `.no-agy` makes `agy-liveness-check.sh` SILENT; the open sentence it was split from is quoted there) and the Branch H paragraph of `docs/superpowers/specs/2026-10-08-final-sweep-sequence-design.md`. Owner confirmation of the behavior below, including the ownership exception, was given in chat 2026-10-12.

## Global Constraints

- `clavity-dotnet/plugin/hooks/agy-liveness-check.sh` and `clavity-classic/plugin/hooks/agy-liveness-check.sh` stay BYTE-IDENTICAL (copy with `cp`, then `cmp`).
- The hook never writes to stderr and exits 0 in every end-state; its text is pure ASCII; it stays fail-open (`set +e`). It gets cheaper under `.no-agy` (the `jq -nc` of `_emit` disappears from the silent case); no other path gains a process.
- The kill-switch still WINS: under `.no-agy` neither the superpowers-not-live advisory nor the jq-missing advisory may appear (no fall-through, no triple message).
- No plugin version bump (the release does it). Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Any suite whose test COUNT changes must have its `scripts/tests/_partition.md` row count refreshed in the same branch (measured on section 78: `test-suite-registration.Tests.ps1` goes red otherwise).

## Review Focus

- `.no-agy` at each of its three locations (repo root, session directory, `~/.claude/`) silences the hook, on BOTH the `jq` path and the no-`jq` path (the no-`jq` global location was untested).
- Under `.no-agy` an ownership finding (a shipped hook also registered personally, a `.clavity/` wiring, an unreadable settings file) still reaches the owner as `systemMessage`, and no emitted text contains `suppressed by`.
- `.no-agy` still beats the not-live and jq-missing advisories (silence, not a fall-through).
- Without `.no-agy`, nothing changes: the advisory still fires (positive control), a healthy install stays silent.
- stdout empty AND stderr empty AND exit 0 in every silent end-state.

---

### Task 1: The hook stops announcing, tests pin it, classic mirror follows

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-liveness-check.sh` - header comment lines 15-39 (the surface criterion and EXIT-CODE CONTRACT items 3 and 4); the no-`jq` branch lines 83-116 (comment block, the `_json` helper at 104, and the two announcing `if` blocks at 108 and 113); the kill-switch block lines 310-364 (comment from 310, the `if [ -f "$root/.no-agy" ] ... fi` block starting at 336). KEEP the `_emit` function defined above line 336: the live and not-live branches still use it.
- Copy to: `clavity-classic/plugin/hooks/agy-liveness-check.sh`
- Test: `scripts/tests/agy-liveness-check.Tests.ps1` - five existing rows (named below) and three new ones.
- Modify: `scripts/tests/_partition.md` - the `agy-liveness-check.Tests.ps1` row's count (and an appended "time NOT re-measured" note).

**Interfaces:**
- Consumes: the suite helpers `New-TempRepo`, `New-ConfigFixture`, `New-CleanHome`, `Payload`, `Invoke-BashHook`, `Remove-TestPath`, and `$script:NoJqPath` (all defined in the suite's `BeforeAll`, lines 1-35).
- Produces: nothing later tasks use except the new row count for Task 2's bookkeeping.

**The two replacement blocks** (the only algorithmic content; the tests determine the rest). No-`jq` branch, replacing lines 83-116 (keep a 3-line comment citing ROADMAP section 80 and the owner ruling):

```bash
if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  exit 0   # SILENT (ROADMAP section 80): no jq, so no ownership check to report either
fi
```

`jq` branch, replacing the whole body of the `if [ -f "$root/.no-agy" ] ... fi` block that starts at line 336 (the `suppressed` path variable and the `_m` message are deleted; `_emit` runs only when there is an ownership note, and with no note the block falls out silently):

```bash
if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  # SILENT (ROADMAP section 80). An ownership note is an actionable fault and still reaches the owner and the model.
  [ -n "$ownership_note" ] && _emit "$ownership_note" "$ownership_note"
  exit 0
fi
```

- [ ] **Step 1: Baseline.** `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Files scripts/tests/agy-liveness-check.Tests.ps1 -ShowMessages`. Expected on this Linux box (measured 2026-10-12): `passed=40 failed=0 skipped=1`. Note the skipped row's name. Also record `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Files scripts/tests/check-seed-artifacts-synced.Tests.ps1,scripts/tests/plugin-hooks-registration.Tests.ps1` totals (they reference this hook).

- [ ] **Step 2: Write the failing rows** (edit in place where a row exists; each silent assertion is `$r.ExitCode | Should -Be 0`, `$r.StdOut | Should -BeNullOrEmpty`, `$r.StdErr | Should -BeNullOrEmpty`):
  1. Row at line 147, rename to `is SILENT (exit 0, no output, no stderr) under .no-agy in cwd, even with superpowers disabled`; keep its fixtures; drop the envelope-surface assertions (there is no envelope any more).
  2. Row at line 170, rename to `is SILENT under a global $HOME/.claude/.no-agy, with superpowers disabled`, and change its fixture from `New-ConfigFixture $true` to `New-ConfigFixture $false`. This is load-bearing: MEASURED 2026-10-12, a LIVE superpowers with no `.no-agy` at all already prints 0 bytes, so a silent row on a live install cannot tell the kill-switch from a healthy install; with superpowers DISABLED the hook speaks (434 bytes) unless the kill-switch is honoured. Every silent row below must use a fixture where the hook WOULD speak without `.no-agy` (superpowers disabled, or no `jq`).
  3. Row at line 185, rename to `a ROOT .no-agy silences a session started in a SUBDIRECTORY`; silent assertions only. Its positive control (row at line 199, `still ADVISES from that same subdirectory when .no-agy is absent`) stays unchanged and must keep passing.
  4. Row at line 211, rename to `no-jq: a ROOT .no-agy silences a subdirectory session, with no jq warning either`; silent assertions (it already builds the payload and `PATH = $script:NoJqPath`).
  5. NEW row `no-jq: a global $HOME/.claude/.no-agy is silent too`: `$h = New-CleanHome`, create `$h/.claude/.no-agy`, run with `PATH = $script:NoJqPath; HOME = $h` and `Payload`; silent assertions.
  6. Row at line 287 (`STILL reports ownership when .no-agy is present (constraint 5)`): keep the fixtures; replace its `suppressed by` match with: parse stdout as JSON; `systemMessage` matches `agy-liveness-check`; `hookSpecificOutput.additionalContext` matches `agy-liveness-check` and does NOT match `suppressed by`; stdout does not match `suppressed by` anywhere.
  7. NEW row `STILL reports an unreadable settings file under .no-agy, and still says nothing about suppression`: `$cfg = New-ConfigFixture $true`, then overwrite `$cfg/settings.json` with the text `{not json`; global `.no-agy` in `New-CleanHome`; run as in row 6. Expect exit 0, `systemMessage` matches `settings unreadable`, stdout does not match `suppressed by` and does not match `superpowers not detected`.
  The row at line 416 (`REPORTS a .clavity/ wiring at USER scope even under .no-agy`) is NOT edited and must stay green.

- [ ] **Step 3: Run to verify they fail.** Same Pester command. Expected: rows 1, 2, 3, 4, 5, 6, 7 red (the hook still announces), every other row green. Row 5 and row 7 are the two with no prior coverage; confirm each fails for the stated reason (an announcement on stdout), not for a fixture error.

- [ ] **Step 4: Implement** the two replacement blocks above; delete `_json` (its only users were the two removed `printf` lines - verify with `grep -n _json` before and after); rewrite the three comment regions listed under Files so no comment still claims the kill-switch announces, quotes the owner ruling of 2026-10-08, and keeps the sentence that the model-visible diagnostic is deliberately given up (the trade named in ROADMAP section 80). `bash -n` must print nothing; the file stays ASCII; and `grep -n -i "announce\|suppressed by" clavity-dotnet/plugin/hooks/agy-liveness-check.sh` must return only lines that describe the OLD behavior as history ("used to", "until section 80"), never one that says the hook announces.

- [ ] **Step 5: Mirror.** `cp clavity-dotnet/plugin/hooks/agy-liveness-check.sh clavity-classic/plugin/hooks/agy-liveness-check.sh && cmp clavity-dotnet/plugin/hooks/agy-liveness-check.sh clavity-classic/plugin/hooks/agy-liveness-check.sh`.

- [ ] **Step 6: Run to verify they pass.** The Pester command of Step 1: `failed=0`, every row green, `skipped` unchanged; the two sync/registration suites of Step 1 unchanged.

- [ ] **Step 7: Mutants, ONE AT A TIME** (back up the hook first; overwrite BOTH plugin copies with each mutant so no byte-identical row masks the result; restore from the backup, not `git checkout`). Expected: only the named rows go red. (a) restore the `suppressed by` line in the `jq` branch: rows 1, 2, 3, 6, 7. (b) restore the announcement in the no-`jq` branch: rows 4, 5. (c) delete the ownership emission under `.no-agy` (bare `exit 0`): rows 6, 7 and the row at line 416. (d) make the hook ignore `.no-agy` (in all three kill-switch `-f` tests, change `.no-agy"` to `.no-agy.x"`, in both branches): rows 1 to 5 and row 7 go red because the hook now speaks, and the positive control at line 199 stays green.

- [ ] **Step 8: Refresh the partition count.** Run `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Files scripts/tests/test-suite-registration.Tests.ps1 -ShowMessages`; it reports the discovered count for `agy-liveness-check.Tests.ps1` (41 before, so 43 after the two new rows). Set that count in the `agy-liveness-check.Tests.ps1` row of `scripts/tests/_partition.md` and append `; 41 -> 43 2026-10-12 (section 80: +2 rows), time NOT re-measured` to the row's trailing note; leave the runtime figure alone. Re-run the registration suite: all green.

- [ ] **Step 9: Commit** the hook, its mirror, the test file and `_partition.md`: `fix(hooks): .no-agy makes the liveness hook silent; ownership notes still reach the owner (section 80)`.

---

### Task 2: Close the ROADMAP entry

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md` (`### §80` status and body)

- [ ] **Step 1: Status.** Replace the `**Status:**` line with `**Status:** IMPLEMENTED 2026-10-12 - built on <branch> (`<sha of Task 1's commit>`)` (the sha in BACKTICKS); keep the replaced line, the legacy line and every existing `>` line, adding the replaced one as one more `> **Previous status:**` line above them. Append one short paragraph to the entry body: the behavior built (silent under `.no-agy`; ownership and settings-unreadable notes still surface, without the suppression sentence), the trade (the model is no longer told at boot why the disciplines are off; the sibling hooks were already silent under `.no-agy`), and that the open sentence quoted from section 31 is resolved by the owner ruling.
- [ ] **Step 2: Verify.** `just check-tracker-status` and `pwsh -NoProfile -File scripts/check-roadmap-claims.ps1` both print OK.
- [ ] **Step 3: Full census, both lanes** (`agy-liveness-check.Tests.ps1` is in the SLOW recipe, `test-suite-registration.Tests.ps1` in the FAST one; measured 2026-10-12). `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Recipe test-scripts-slow -Exclude hook-spawn-budget`: expect `files=48 excluded=1 passed=1204 failed=83 badContainers=19` (the 2026-10-12 baseline 1202 plus this branch's 2 new rows). `just test-scripts-fast-parallel`: expect `passed=634 failed=59` unchanged (the partition count refresh keeps the registration row green). Any other number is investigated against the per-suite counts, not accepted.
- [ ] **Step 4: Commit:** `docs(roadmap): section 80 implemented - .no-agy makes the liveness hook silent`.

## Self-review (run 2026-10-12)

- **Spec coverage:** the ruling (silent), the three kill-switch locations, both `jq` paths, the ownership exception and the model-trade are each covered by a row or a step; the README sentence that `agy-liveness-check` "still runs under `.no-agy` and reports that personal registrations remain" (`clavity-dotnet/plugin/README.md:193`) stays true, so no README edit.
- **Gaps carried, with where they resolve:** whether the kill-switch ought also to silence the settings-unreadable note (my call: it stays, because it is an ownership-check failure, row 7 pins it) - resolved by the owner's reading of this plan; the classic README copy is not touched for the same reason as the dotnet one.
- **Proportion:** two tasks; bodies appear only for the two replacement blocks the tests do not determine.

## Panel record (adversarial-panel-review, solo, 2026-10-12; no agy round: the owner was told this small change would get the solo panel only)

Seated: Axiom Breaker, Cascade Analyst, Literal Implementer, Mechanism Gamer, State Corruptor (no shared or ordered state: dropped as "no new findings"); dropped for cause: Boundary Smuggler, Protocol Pedant, Resource Vampire, Dependency Cynic, Activation Auditor (the change touches no wire contract, trust zone, resource or registration).
- `FOLDED:` row 2 would have been a vacuous row (silent on a live install with or without the kill-switch; MEASURED 0 bytes without `.no-agy`) - it now uses a disabled-superpowers fixture, and the rule that every silent row must use a fixture where the hook would speak is stated (Mechanism Gamer). Mutant (d) made concrete (Literal Implementer). Kill-switch block range corrected from 310-357 to 310-364 and the lane of the suite stated (slow; `agy-liveness-check.Tests.ps1`) after reading the lines (Axiom Breaker, Cascade Analyst). A `grep` check added so no stale "announces" comment survives (Literal Implementer).
- Premises measured before the plan relied on them: today, a corrupt settings file under a global `.no-agy` reaches the owner as `systemMessage` ("settings unreadable") and a plain `.no-agy` sends the model exactly one `suppressed by` line; the suite's baseline is `passed=40 failed=0 skipped=1` (41 discovered).


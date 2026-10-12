# Branch H, section 75: three hooks that misread a file or platform written differently - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three hooks stop misreading their input: a CRLF `assertions.md` and a CRLF observations inbox read like their LF twins, a UTF-8-BOM inbox still gets its pre-drain snapshot, and the 7-day snooze marker's age no longer depends on GNU-only `date -r`.

**Architecture:** One small mechanism per defect, each in its own hook: a CR strip as the first rule of each of two awk programs; a first-line-only BOM strip in the snapshot hook's existing bash loop; `find FILE -mmin -10080` in place of `date -r` for the snooze age. Each task is red-green with a failing control first.

**Tech Stack:** bash 3.2+ hooks; awk (POSIX); PowerShell 7 + Pester 6; the repo `justfile` gates.

**Spec:** `clavity-dotnet/ROADMAP.md` entry `### §75` (its three numbered defects and "Plan shape"; the owner approved this scope in chat 2026-10-12) and the Branch H paragraph of `docs/superpowers/specs/2026-10-08-final-sweep-sequence-design.md`.

## Global Constraints

- Hook files involved (single copies, no plugin mirror): `.claude/hooks/agy-verify-reminder.sh`, `agy-autotrain/hooks/agy-curate-nudge.sh`, `agy-autotrain/hooks/agy-inbox-snapshot.sh`. Fail-open and read-only behavior unchanged; stdout and stderr contracts unchanged; hook source stays pure ASCII (write the BOM as `$'\xEF\xBB\xBF'`, never a literal byte).
- Process budget: no hook gains a process. The snooze path costs the same as before (one command substitution plus one external command: `find` where `date -r` was). Verified on the budget row `worst: snooze expired + 16 recent entries` (`-Max 9`, `hook-spawn-budget.Rows.ps1:319`), which is Windows-only and stays unrun here.
- Every new "red" row must use a fixture where the hook behaves DIFFERENTLY with and without the fix (the lesson of section 80: a row on a fixture where the hook is silent either way proves nothing); each distractor row says so.
- Any suite whose test count changes gets its `scripts/tests/_partition.md` row count refreshed in the SAME task (section 78 lesson): measured counts are verify-reminder 8 -> 10, curate-nudge 38 -> 41, inbox-snapshot 41 -> 44.
- No plugin version bump (the release does it). Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- BSD behavior (`date -r` takes EPOCH SECONDS; BSD `find -mmin`) is read from documentation and is NOT measured here (no macOS); the tests use a `BASH_ENV` `date` shim, the technique section 73's rows already use in `agy-curate-nudge.Tests.ps1`.

## Review Focus

- A CRLF file must give the SAME output as its LF twin for BOTH awk hooks, including a CRLF file whose content is current/recent (the silent case), not only the stale one.
- A BOM must be stripped from line 1 ONLY, and only from the header test: a near-miss first line with a BOM (not the inbox header) must still NOT be snapshotted.
- The snooze: a fresh marker silences under BSD `date` semantics; a 6-day marker still silences; an 8-day marker no longer silences (the nudge fires) - the snooze must not become "forever".
- No hook's behavior changes for plain LF / BOM-less / GNU input (the existing rows are the control and must stay green).
- The two awk edits must not change how a normal row, separator or heading is matched (CR strip only touches a trailing CR).

---

### Task 1: `agy-verify-reminder` reads a CRLF `assertions.md`

**Files:**
- Modify: `.claude/hooks/agy-verify-reminder.sh` (the awk program starting at line 79, `findings=$(awk -F'|' ...`; its first rule, the separator rule, is at line 94)
- Test: `scripts/tests/agy-verify-reminder.Tests.ps1` (fixture `New-VerifyFx` at line 14-24)
- Modify: `scripts/tests/_partition.md` (this suite's row: count and appended note)

**Interfaces:** Consumes `New-VerifyFx` / `Invoke-Verify` from the suite's `BeforeAll`. Produces: nothing used later.

- [ ] **Step 1: Baseline.** `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Files scripts/tests/agy-verify-reminder.Tests.ps1 -ShowMessages`. Expected (measured 2026-10-12): `passed=4 failed=4`; the four failures are `EMITS for a stale PASS cell`, `takes the LEFTMOST version...`, `EMITS NOROWS guidance when the table has no data rows`, `resolves a cwd carrying a \u escape...`.
- [ ] **Step 2: Make the fixture portable** (needed so any row here can run on Linux; MEASURED on a throwaway copy 2026-10-12: it takes the suite from 4 passed / 4 failed to 8 / 0, and the hook is untouched). In `New-VerifyFx`: (a) build `Path` with `[IO.Path]::PathSeparator` between its four parts instead of the literal `;`; (b) right after the `WriteAllText` of `fakebin/agy`, add `if (-not $IsWindows) { [IO.File]::SetUnixFileMode((Join-Path $root 'fakebin/agy'), [IO.UnixFileMode]'UserRead, UserWrite, UserExecute') }` (the fake had no execute bit, so `command -v agy` never found it). Re-run: `passed=8 failed=0`. Commit nothing yet.
- [ ] **Step 3: Write the failing rows.** (1) `reads a CRLF assertions.md exactly like the LF one`: `$f = New-VerifyFx -DotnetCell 'PASS 1.0.0'` (a stale cell, so the LF twin EMITS), then overwrite `<cwd>/agy-autotrain/verify/assertions.md` with the same three lines joined by `` `r`n `` and a trailing `` `r`n `` using `[IO.File]::WriteAllText`; `Invoke-Verify $f`; assert stdout matches `A1 \[dotnet\] PASS 1\.0\.0 \(live 9\.9\.9\)` and does NOT match `no probe rows`. (2) `stays SILENT for a CRLF table whose cells are current`: same but `-DotnetCell 'PASS 9.9.9'`; assert stdout `Should -BeNullOrEmpty`. Both fail today (the hook emits NOROWS for any CRLF table; row 2 is the discriminating one: LF is silent, CRLF speaks).
- [ ] **Step 4: Run to verify red.** Expected: exactly those two rows fail (`passed=8 failed=2`), row 1 with the NOROWS text where the stale-cell text was expected, row 2 with output where none was expected.
- [ ] **Step 5: Implement.** Insert `{ sub(/\r$/, "") }` as the FIRST pattern-action rule of the awk program (immediately before the separator rule at line 94, after the function definitions), with a 3-line comment citing ROADMAP section 75 and the measured gawk 5.3.2 result. Assigning to `$0` re-splits the fields for the `-F'|'` program. `bash -n` clean; ASCII.
- [ ] **Step 6: Run to verify green:** `passed=10 failed=0`. Mutant (one, on a scratch copy of the hook, restored from a backup): delete the new rule - rows 1 and 2 go red and the other eight stay green.
- [ ] **Step 7: Partition count.** Run `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Files scripts/tests/test-suite-registration.Tests.ps1 -ShowMessages`; set this suite's row count to the number it reports (10) and append `; 8 -> 10 2026-10-12 (section 75: +2 rows), time NOT re-measured`; re-run: all green.
- [ ] **Step 8: Commit** (hook, test file, `_partition.md`): `fix(hooks): agy-verify-reminder reads a CRLF assertions.md (section 75)`.

---

### Task 2: `agy-curate-nudge` reads a CRLF inbox and honours the snooze on BSD

**Files:**
- Modify: `agy-autotrain/hooks/agy-curate-nudge.sh` (the snooze block at lines 52-56; the awk program starting at line 90, `scan="$(awk 'function flush(){...}` whose first rule is `/^##[ \t]+Pending[ \t]*$/{p=1;next}` on the same line)
- Test: `scripts/tests/agy-curate-nudge.Tests.ps1`
- Modify: `scripts/tests/_partition.md` (this suite's row)

**Interfaces:** Consumes `New-NudgeEnv -Inbox <text>` (returns `.Root` and `.Env`) and `New-DatedInbox <date>` from the suite's `BeforeAll`, and `Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env ...`. Produces: nothing used later.

- [ ] **Step 1: Baseline.** `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Files scripts/tests/agy-curate-nudge.Tests.ps1 -ShowMessages`: `passed=38 failed=0` (measured 2026-10-12).
- [ ] **Step 2: Write the failing rows.** (1) `nudges for a CRLF inbox exactly like the LF one`: inbox `(New-DatedInbox '2020-01-01')` with every `` `n `` replaced by `` `r`n ``; `New-NudgeEnv -Inbox $crlf`; assert stdout matches `agy-curate nudge` and `oldest pending entry \(2020-01-01\)`, exit 0. (2) DISTRACTOR `stays SILENT for a CRLF inbox whose only entry is recent` (passes before AND after: it pins that stripping the CR does not invent a nudge): `New-DatedInbox $script:Today` with CRLF; stdout `Should -BeNullOrEmpty`. (3) `honours a FRESH snooze under BSD date semantics (date -r takes epoch seconds)`: inbox `New-DatedInbox '2020-01-01'` (LF); write a shim file under the env root whose content is the single line `date() { if [ "$1" = "-r" ]; then case "$2" in ''|*[!0-9]*) echo "date: illegal time format" >&2; return 1;; esac; fi; command date "$@"; }` and add `BASH_ENV = <that path, forward slashes>` to `$e.Env`; assertions in order: no marker -> stdout matches `agy-curate nudge` (precondition); fresh marker (`Set-Content` an empty file at `<root>/home/.clavity/.agy-curate-snooze`) -> `Should -BeNullOrEmpty`; marker aged 6 days (`(Get-Item -Force -LiteralPath $snooze).LastWriteTime = (Get-Date).AddDays(-6)`) -> silent; aged 8 days -> matches `agy-curate nudge`.
- [ ] **Step 3: Run to verify red.** Expected: rows 1 and 3 fail (row 1: no nudge for CRLF; row 3: the fresh-marker assertion sees a nudge because the shim rejects a path for `date -r`), row 2 passes. `passed=38 failed=2` plus the 3 new = `passed=39 failed=2`.
- [ ] **Step 4: Implement.** (a) awk: insert `{ sub(/\r$/, "") }` as the first rule, directly after the `function flush(){...}` definition and before `/^##[ \t]+Pending[ \t]*$/{p=1;next}`. (b) Snooze: replace lines 53-56 (the `if [ -f "$SNOOZE" ]; then ... fi` block, including the `now`/`mt` assignments) with `if [ -f "$SNOOZE" ] && [ -n "$(find "$SNOOZE" -mmin -10080 2>/dev/null)" ]; then exit 0; fi` (10080 minutes = 7 days; `find` replaces the GNU-only `date -r`) and rewrite the comment on line 52 to say the age comes from `find -mmin`, with a note that the granularity is a minute and that BSD `find -mmin` is from documentation. `now` is still assigned later at line 107 for the age gate: leave that. `bash -n` clean; ASCII; `grep -n 'date -r' agy-autotrain/hooks/agy-curate-nudge.sh` returns nothing outside a comment describing the old behavior.
- [ ] **Step 5: Run to verify green:** `passed=41 failed=0`, including the existing `honours a FRESH .agy-curate-snooze and ignores a STALE one` (fresh, 6 days, 8 days) and the section-73 age-gate rows. Mutants, ONE AT A TIME on a scratch copy restored from a backup: (a) delete the awk rule - rows 1 red; (b) put `date -r "$SNOOZE" +%s` back for the snooze - row 3 red; (c) change `-mmin -10080` to `-mmin -60` - the 6-day assertion of row 3 and of the existing snooze row go red.
- [ ] **Step 6: Partition count:** as Task 1 Step 7; this suite 38 -> 41, note `; 38 -> 41 2026-10-12 (section 75: +3 rows), time NOT re-measured`.
- [ ] **Step 7: Commit** (hook, test file, `_partition.md`): `fix(hooks): agy-curate-nudge reads a CRLF inbox and ages the snooze without GNU-only date -r (section 75)`.

---

### Task 3: `agy-inbox-snapshot` snapshots a BOM inbox

**Files:**
- Modify: `agy-autotrain/hooks/agy-inbox-snapshot.sh` (the variable line before the loop that sets `hdr=0; pend=0; bullet=0; p=0`; the loop at line 96; the CR strip at line 99; the header test at line 100)
- Test: `scripts/tests/agy-inbox-snapshot.Tests.ps1`
- Modify: `scripts/tests/_partition.md` (this suite's row)

**Interfaces:** Consumes `New-PluginRoot <body>` / `New-PluginRoot $null`, `HookEnv $r`, `Payload 'agy-autotrain:agy-curate'`, `BakCount $r`, `$script:Good` from the suite's `BeforeAll`. Produces: nothing used later.

- [ ] **Step 1: Baseline.** `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Files scripts/tests/agy-inbox-snapshot.Tests.ps1 -ShowMessages`: `passed=40 failed=1` (measured 2026-10-12); the one failure, `honours every SLASH-COMMAND contract on the jq-ABSENT fallback branch too`, stays failing and is not yours.
- [ ] **Step 2: Write the failing rows,** each with `$r = New-PluginRoot $null` and the inbox written with `[IO.File]::WriteAllBytes` (the three BOM bytes `0xEF,0xBB,0xBF` followed by the UTF-8 bytes of the body): (1) `snapshots a UTF-8-BOM inbox (the BOM is part of line 1)`: body `$script:Good`; `BakCount $r | Should -Be 1`. (2) `snapshots a BOM + CRLF inbox`: body `$script:Good` with `` `n `` -> `` `r`n ``; `BakCount` 1. (3) DISTRACTOR `does NOT snapshot a BOM file whose first line is not the inbox header` (passes before AND after): body `"# some other file`n`n## Pending`n`n- [assumption] (peer/probabilistic) a rule`n"`; `BakCount | Should -Be 0` (the BOM strip must not widen the header test).
- [ ] **Step 3: Run to verify red.** Expected: rows 1 and 2 fail (`BakCount` 0, expected 1), row 3 passes: `passed=41 failed=3` (the three failures: rows 1, 2 and the baseline row).
- [ ] **Step 4: Implement.** Add `first=1` to the variable line `hdr=0; pend=0; bullet=0; p=0`; inside the loop, immediately after the CR strip (line 99) add `if [ "$first" -eq 1 ]; then first=0; line=${line#$'\xEF\xBB\xBF'}; fi` so ONLY line 1 is stripped (a BOM elsewhere means nothing). Add a 3-line comment citing ROADMAP section 75 and the measurement (0 `.bak` for BOM+LF and BOM+CRLF, 1 for plain). Verified 2026-10-12: that pattern strips the BOM identically under `LC_ALL=C`, `en_US.UTF-8` and `C.UTF-8`. `bash -n` clean; ASCII.
- [ ] **Step 5: Run to verify green:** `passed=43 failed=1` (only the baseline row). Mutants, one at a time on a scratch copy restored from a backup: (a) delete the BOM strip - rows 1, 2 red; (b) strip the BOM on EVERY line - all rows still green (a BOM on later lines is not part of this change: say so in the report, do not add a row for it); (c) delete the `first` guard and strip a leading `#` instead - row 3 red.
- [ ] **Step 6: Partition count:** 41 -> 44, note `; 41 -> 44 2026-10-12 (section 75: +3 rows), time NOT re-measured`.
- [ ] **Step 7: Commit** (hook, test file, `_partition.md`): `fix(hooks): agy-inbox-snapshot snapshots a UTF-8-BOM inbox (section 75)`.

---

### Task 4: Close the ROADMAP entry and run the census

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md` (`### §75`)

- [ ] **Step 1: Status.** Replace the `**Status:**` line with `**Status:** IMPLEMENTED 2026-10-12 - built on <branch> (`<Task 1 sha>`, `<Task 2 sha>`, `<Task 3 sha>`)` (the shas in BACKTICKS); keep every existing `>` line and add the replaced line above them as one more `> **Previous status:**` line. Append one paragraph `**Built.**`: the three fixes (CR strip in two awk programs, first-line BOM strip, `find -mmin` snooze), what each measurement showed on 2026-10-12 (CRLF `assertions.md` gave the misleading NOROWS and a CRLF inbox silenced the nudge on gawk 5.3.2, the second marked "not measured on Linux" in this entry; BOM gave 0 `.bak` against 1 for plain), and what stays unmeasured (BSD semantics read from documentation and shimmed; the Windows spawn-budget row `worst: snooze expired + 16 recent entries`). State plainly that the entry's "the same BOM shape likely exists in the other inbox readers" claim was REFUTED by measurement: `agy-curate-nudge` and `agy-verify-reminder` both read a BOM file correctly because neither tests line 1.
- [ ] **Step 2: Verify.** `just check-tracker-status` and `pwsh -NoProfile -File scripts/check-roadmap-claims.ps1` both print OK.
- [ ] **Step 3: Census, both lanes** (all three suites are in the SLOW recipe). `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Recipe test-scripts-slow -Exclude hook-spawn-budget`: expect `files=48 excluded=1 passed=1216 failed=79 badContainers=18` - derived from the 2026-10-12 baseline 1204 / 83 / 19: +4 (the verify-reminder rows that now pass on Linux) +2 (its new rows) +3 +3, and `agy-verify-reminder` leaves the failing-suite list. `just test-scripts-fast-parallel`: `passed=634 failed=59` unchanged. Any other number is investigated against the per-suite counts, not accepted.
- [ ] **Step 4: Commit:** `docs(roadmap): section 75 implemented - CRLF, BOM and BSD date -r in three hooks`.

## Self-review (run 2026-10-12)

- **Spec coverage:** the entry's three defects and its Plan shape are Tasks 1-3 (defect 1 covers both awk hooks, split across Tasks 1 and 2); the unmeasured item 3 is covered by the shim row; the entry's "likely other readers" claim is measured and refuted (Task 4 records it).
- **Gaps carried, with where they resolve:** BSD `date`/`find` semantics (documentation only; shim) and the Windows budget row for the expired-snooze path (unrun here) - recorded in the ROADMAP paragraph, resolved by a Mac or Windows run.
- **Proportion:** four tasks; bodies appear only for the shim line and the two small code insertions that the rows do not determine.

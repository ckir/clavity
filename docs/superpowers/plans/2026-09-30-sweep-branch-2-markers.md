# ROADMAP sweep Branch 2 - marker / ledger hooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close ROADMAP §39, §40, §51, §52 and the peer-scratch backlog item in both driver plugins, bump both plugin versions, and hand the owner a reinstall.

**Architecture:** Every change lands in `clavity-dotnet/plugin/` first and is then COPIED byte-for-byte to `clavity-classic/plugin/` (the shared hooks and discipline skills are byte-identical today, and `scripts/tests/plugin-hooks-payload.Tests.ps1` + `scripts/check-seed-artifacts-synced.sh` enforce it). Tests live in `scripts/tests/` and run on Windows only (CI is `windows-latest`). Every guard change is proven by a failing control before the fix and a logic mutant after it.

**Tech Stack:** bash (Git Bash) hooks, jq, PowerShell 7 + Pester 5 tests, `just`, lefthook.

**Spec:** `docs/superpowers/specs/2026-09-29-roadmap-sweep-sequence-design.md`, section "Branch 2" and "The sequence" (cycle (a)-(f), "Closing a header", "Plugin-pair branches").

---

## Owner rulings this plan implements (2026-09-30, after AGY-FIRST)

The consult is `.clavity/seams/branch2-forks.md`, the peer's reply `.clavity/seams/branch2-forks.reply.md`, and
the negotiation turn `.clavity/seams/branch2-forks-negotiate.md` (the peer withdrew two proposals there, both
measured wrong by the driver). The peer ended ALIGNED on all four forks.

| item | ruling |
|---|---|
| §52 | The test-audit skill's marker content becomes the ledger row's RANGE END, not ambient HEAD. |
| §51 | `agy-mark.sh head`: when the cwd is inside a git work tree, refuse unless `git cat-file -e <sha>^{commit}` succeeds; with no repository or no git, write without checking. Applies to EVERY discipline, not only those with a ledger. |
| §39 | ONE shared path-building function, sourced by the writer and every reader. No test. |
| §40 | Two test rows: a 6-character ledger token is REFUSED, a 7-character one is ACCEPTED. |
| peer-scratch | REPLACES the step-0 "Option 3" ruling: `agy-liveness-check.sh` reports any hook command in the three settings files that runs from `.clavity/`. |

## Re-measurement at the branch start (spec step (a)), 2026-09-30 on `main` `b29c4df2`

All five items still reproduce (script: `.clavity/scratch/branch2/remeasure.ps1`, output beside it):

- §39: no row in `scripts/tests/agy-mark.Tests.ps1` names the case of a discipline; the reader moved to `agy-seam-inject.sh:133`.
- §40: `_agl_i=7` -> `_agl_i=6` in `agy-ledger-lib.sh:107` leaves `agy-ledger-lib.Tests.ps1` 32/32 green.
- §51: `head agy-capstone <first 8 chars of HEAD + 32 zeros>` wrote that sha and exited 0; `git cat-file -e` on it answered 128.
- §52: `agy-mark.sh head agy-test-audit <HEAD>` refused `ABSENT mentioned=0` when HEAD was the ledger commit `8829274c`.
- peer-scratch: `agy-consult-guard-lib.sh:292` still prunes `scratch/` by name.

## Standing rules for every task (paste into every dispatch)

- **Step 0 - STATE VERIFICATION.** Open every file the task names and confirm the quoted "current" text is there, verbatim. If it differs, STOP and report `STATE_MISMATCH: <what>`. Line numbers here were measured on `b29c4df2`; earlier tasks of THIS plan shift them, so locate by the quoted text, never by the number.
- **SHAPE-DIVERGENCE STOP.** If making something work would change the shape, type or encoding of any value in the code given here, STOP and report `[original] -> [yours] because <reason>`.
- **Tests are already written in this plan - implement until they pass.** Do not edit a test to match the code; if a test looks wrong, the test is the oracle: STOP and report the conflict.
- **Write every script or probe with the Write tool.** The Bash tool on this box drops one backslash from `\\` and runs backticks inside double quotes as commands.
- **Never run two Pester suites at once.** A run with no `Tests Passed:` line was ABORTED, not green.
- **Mirror = copy.** After editing a file under `clavity-dotnet/plugin/`, copy it over its `clavity-classic/plugin/` twin with `Copy-Item -LiteralPath <dotnet> -Destination <classic> -Force` and confirm `(Get-FileHash <a>).Hash -eq (Get-FileHash <b>).Hash`.
- **ASCII only** in every file this plan touches under `plugin/` and in every new test line.
- **Stage explicit paths only; never commit anything under `.clavity/`.** End each commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **ANOMALIES** and **FILES** clauses from the `open-issues` skill go in every implementer dispatch.

## How to run one suite (used by every task)

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/<suite>.Tests.ps1 -Output Detailed -CI"
```

Expected on success: a `Tests Passed: <N>, Failed: 0` line. A logic mutant is proven by running the same
command with the mutant applied and seeing the NAMED row fail; restore with `git checkout -- <file>` (stage
your real edits with `git add` BEFORE applying any mutant, so the checkout cannot eat them).

---

### Task 0: Cut the branch and check the tools

**Files:** none.

- [ ] **Step 1: Branch from main**

```powershell
git checkout main
git rev-parse HEAD            # expect b29c4df2b5548f303141b981c5933ef89084dd4c (the branch base)
git checkout -b sweep/branch-2-markers
```

- [ ] **Step 2: Confirm the version-bump tools (needed by Task 7)**

`scripts/bump-version.ps1` bumps classic through `cargo set-version` (cargo-edit) and `uv lock`.

```powershell
cargo set-version --help | Select-Object -First 1   # cargo-edit present?
Get-Command uv
```

If `cargo set-version` is missing, install it: `cargo install cargo-edit --locked` (it is declared in the
project's recommended tools). Re-run the check; expect a help line.

---

### Task 1: §40 - pin the 7-character ledger-token boundary (test only)

**Files:**
- Modify: `scripts/tests/agy-ledger-lib.Tests.ps1`

- [ ] **Step 1: Add a 6-character ledger body.** Insert this block immediately AFTER the `$script:HeaderOnlyLedger = @'...'@` block and BEFORE `        function New-LedgerRepo {`:

```powershell
        # ROADMAP section 40. The row token is SIX characters: one short of the shortest abbreviation the
        # reader accepts (agy-ledger-lib.sh builds its alternation from prefixes of length 7 and up).
        $script:SixCharLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `<<SHORT6>>` | 1 | GREEN | fold `deadbee` |
'@
```

- [ ] **Step 2: Teach the fixture the new placeholder.** In `New-LedgerRepo`, replace

```powershell
                $text = $LedgerBody.Replace('<<SHORT>>', $sha.Substring(0, 7)).Replace('<<FULL>>', $sha)
```

with

```powershell
                $text = $LedgerBody.Replace('<<SHORT6>>', $sha.Substring(0, 6)).Replace('<<SHORT>>', $sha.Substring(0, 7)).Replace('<<FULL>>', $sha)
```

- [ ] **Step 3: Add the two boundary rows.** Insert this Context immediately BEFORE the line
`    Context 'pinned against the REAL shipped ledger' {`:

```powershell
    Context 'the seven-character ROW-token boundary (ROADMAP section 40)' {
        # The QUERY bound has a row (above). The ROW-token bound had none on either side: MEASURED
        # 2026-09-30, changing `_agl_i=7` to `_agl_i=6` left all 32 rows green. These two pin both edges.
        It 'REFUSES a ledger token of SIX characters - one short of the shortest accepted abbreviation' {
            $r = New-LedgerRepo -LedgerBody $script:SixCharLedger
            $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out
            $out | Should -Not -Match 'FOUND' -Because 'six characters must not authenticate a sha; the alternation starts at seven'
            $out | Should -Match 'ABSENT' -Because 'a refusal must still say what it found'
        }

        It 'ACCEPTS a ledger token of EXACTLY seven characters - the boundary itself' {
            $r = New-LedgerRepo -LedgerBody $script:BareLedger
            (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out |
                Should -Match 'FOUND' -Because 'seven characters is the shortest abbreviation the ledger writes, and it must authenticate'
        }
    }

```

- [ ] **Step 4: Run the suite.** Expect `Tests Passed: 34, Failed: 0`.

- [ ] **Step 5: Prove each row by its mutant.** `git add scripts/tests/agy-ledger-lib.Tests.ps1` first.
  - Mutant A: in `clavity-dotnet/plugin/hooks/agy-ledger-lib.sh` change `    _agl_i=7` to `    _agl_i=6`. Run the suite. Expect the SIX-character row to fail by name. Restore: `git checkout -- clavity-dotnet/plugin/hooks/agy-ledger-lib.sh`.
  - Mutant B: change `    _agl_i=7` to `    _agl_i=8`. Expect the EXACTLY-seven row to fail by name (other rows may fail too). Restore the same way.

- [ ] **Step 6: Commit**

```powershell
git add scripts/tests/agy-ledger-lib.Tests.ps1
git commit -m "test(ledger): pin the 7-character row-token boundary on both sides (section 40)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: §51 - `head` refuses a sha that names no commit

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-mark.sh` (then copy to `clavity-classic/plugin/hooks/agy-mark.sh`)
- Modify: `scripts/tests/agy-mark.Tests.ps1`

- [ ] **Step 1: Move the existing rows that pass a MADE-UP sha inside a git fixture onto the real HEAD.** The
fix makes a nonexistent sha a refusal, so every row that relied on writing one would start failing for the
wrong reason. Exactly these, located by their text:

1. In `It 'RESOLVES ITS OWN HELPERS when invoked by an all-BACKSLASH Windows path'` replace
   `            $sha = 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'` with
   `            $sha = (& git -C $d rev-parse HEAD).Trim()`.
2. In `It 'a rejected HEAD write fails too - not just a rejected log write'` replace
   `            $r = Invoke-Mark -Cwd $d -MarkArgs @('head','agy-first','0123456789abcdef0123456789abcdef01234567')` with
   ```powershell
            $sha = (& git -C $d rev-parse HEAD).Trim()
            $r = Invoke-Mark -Cwd $d -MarkArgs @('head','agy-first',$sha)
   ```
3. In BOTH `-ForEach` tables of `Context 'the shield is called on EVERY mode'` (`restores a broken shield` and
   `PRESERVES a human negation`), change ONLY the head entry
   `            @{ Mode = @('head','agy-first','deadbeefdeadbeefdeadbeefdeadbeefdeadbeef') },` to
   `            @{ Mode = @('head','agy-first','<HEAD>') },`. Leave the `log` entries alone: `log` never checks existence.
   Then in each of those two row bodies, replace the line `            Invoke-Mark -Cwd $d -MarkArgs $Mode | Out-Null` with
   ```powershell
            $head = (& git -C $d rev-parse HEAD).Trim()
            $markArgs = @($Mode | ForEach-Object { if ($_ -eq '<HEAD>') { $head } else { $_ } })
            Invoke-Mark -Cwd $d -MarkArgs $markArgs | Out-Null
   ```
4. In `It 'FORWARDS $AGY_SESSION_ID to the helper'`, immediately after
   `            & git -C $d commit -q -m 'track to create a PERSISTENT fault'` add
   `            $sha = (& git -C $d rev-parse HEAD).Trim()`, then replace `'deadbeef'` with `$sha` in the three
   `Invoke-Mark ... @('head','agy-first','deadbeef')` calls of that row.

Leave these alone - they refuse BEFORE the sha is looked at: the `refuses a <discipline> containing a
separator` row (`@('head',$D,'deadbeef')`), the `exits 1 and writes NOTHING when the helper cannot be loaded`
row, and every `log` row.

- [ ] **Step 2: Add the two new rows.** Insert them at the END of `Context 'head mode'`, immediately after the
`ANCHORS TO CWD, matching agy-seam-inject.sh:124 - the subdirectory pin` row's closing `}`:

```powershell
        It 'REFUSES a sha that names no commit in this repository, and writes no marker (ROADMAP section 51)' {
            # MEASURED 2026-09-30 before the fix: `head agy-capstone <first 8 of HEAD + 32 zeros>` wrote that
            # sha and exited 0, while `git cat-file -e <it>^{commit}` answered 128. The marker is what the
            # auto-fire hooks compare with HEAD, so a sha that names nothing silently re-arms the gate.
            $d = New-MarkFixture
            $real = (& git -C $d rev-parse HEAD).Trim()
            $fake = $real.Substring(0, 8) + ('0' * 32)
            & git -C $d cat-file -e "$fake^{commit}" 2>$null
            $LASTEXITCODE | Should -Not -Be 0 -Because 'the fixture sha must really name no commit, or this row proves nothing'
            $r = Invoke-Mark -Cwd $d -MarkArgs @('head','agy-first',$fake)
            $r.ExitCode | Should -Be 1
            $r.Err | Should -Match 'does not name a commit'
            (Test-Path -LiteralPath (Join-Path $d '.clavity/agy-marks/agy-first.head')) | Should -BeFalse -Because 'a refused write must leave no marker'
        }

        It 'WRITES without the commit check outside a git repository - the writer stays git-optional' {
            # ROADMAP section 27 keeps agy-mark.sh git-optional, and the section 51 owner ruling keeps it so:
            # no repository, or no git on PATH, means no check - not a refusal. Both make the same rev-parse
            # probe fail, so this one row pins both.
            $d = Join-Path ([IO.Path]::GetTempPath()) ("marknogit-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path (Join-Path $d '.clavity') | Out-Null
            [void]$script:Fixtures.Add($d)   # FIXTURE HYGIENE
            [IO.File]::WriteAllText((Join-Path $d '.clavity/.gitignore'), "*`n")
            & git -C $d rev-parse --is-inside-work-tree 2>$null | Out-Null
            $LASTEXITCODE | Should -Not -Be 0 -Because 'the fixture must really be outside any git work tree, or this row proves nothing'
            $sha = 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
            $r = Invoke-Mark -Cwd $d -MarkArgs @('head','agy-first',$sha)
            $r.ExitCode | Should -Be 0 -Because "outside a repository there is nothing to check against; stderr was: $($r.Err)"
            (Get-Content -Raw -LiteralPath (Join-Path $d '.clavity/agy-marks/agy-first.head')) | Should -BeExactly $sha
        }
```

If the second row's precondition assertion fails (the temp directory sits inside some git work tree on this
machine), STOP and report `STATE_MISMATCH` - do not move the fixture on your own.

- [ ] **Step 3: Run the suite - the failing control.** Expect exactly ONE failure: `REFUSES a sha that names no
commit ...` (the fix is not in yet). Every other row, including the Step 1 rows and the git-optional row,
passes. Record the counts. If anything else fails, STOP and report.

- [ ] **Step 4: Implement.** In `clavity-dotnet/plugin/hooks/agy-mark.sh`, in the `head)` arm, immediately
after the line `        _check_sha "$sha"` insert:

```bash
        # ROADMAP section 51: the sha must NAME A COMMIT. MEASURED 2026-09-30: a mistyped full sha (the
        # real first 8 characters plus 32 zeros) was written and exited 0 - the ledger gate below matched
        # its 7-character prefix, and nothing asked git whether it resolves. A nonexistent sha silently
        # re-arms every auto-fire hook that compares the marker with HEAD.
        # Checked only where git can answer: no repository, or no git on PATH, means no check, so the
        # writer stays git-optional (ROADMAP section 27) - both make the rev-parse probe fail. It sits
        # BEFORE the ledger gate on purpose: it applies to every discipline, including the NO-LEDGER
        # majority, and --gate-override does not bypass it - no ruling makes a nonexistent commit valid.
        if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            git -C "$root" cat-file -e "$sha^{commit}" >/dev/null 2>&1 ||
                _die_refuse "sha does not name a commit in this repository: [$sha] - pass the full sha of the commit the discipline covered, e.g. \$(git rev-parse <sha>)"
        fi
```

- [ ] **Step 5: Run the suite.** Expect `Failed: 0` and a total equal to Step 3's total (the one failing row
now passes; `_partition.md` records 47 before this task, so expect 49 - if Step 3 measured a different total,
trust the measurement and say so).

- [ ] **Step 6: Prove the guard by two logic mutants.** `git add` the hook and the suite first.
  - Mutant A: replace `            git -C "$root" cat-file -e "$sha^{commit}" >/dev/null 2>&1 ||` with `            true ||`. Expect `REFUSES a sha that names no commit ...` to fail by name.
  - Mutant B: replace `        if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then` with `        if true; then`. Expect `WRITES without the commit check outside a git repository ...` to fail by name.
  Restore after each with `git checkout -- clavity-dotnet/plugin/hooks/agy-mark.sh`.

- [ ] **Step 7: Mirror and run the gate suites.**

```powershell
Copy-Item -LiteralPath clavity-dotnet/plugin/hooks/agy-mark.sh -Destination clavity-classic/plugin/hooks/agy-mark.sh -Force
```

Run `plugin-hooks-payload` (expect all green) and `bash scripts/check-seed-artifacts-synced.sh` (expect exit 0).

- [ ] **Step 8: Commit**

```powershell
git add clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh scripts/tests/agy-mark.Tests.ps1
git commit -m "fix(agy-mark): head refuses a sha that names no commit, where git can answer (section 51)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: §39 - one shared marker-path builder for the writer and every reader

**Files:**
- Create: `clavity-dotnet/plugin/hooks/agy-marker-lib.sh` (then copy to `clavity-classic/plugin/hooks/`)
- Modify: `clavity-dotnet/plugin/hooks/agy-mark.sh`, `agy-seam-inject.sh`, `agy-test-audit-reminder.sh`, `agy-consult-recovery.sh` (then copy each to classic)

No new test (owner ruling). The existing suites of the four scripts are the regression net and must stay
green: `agy-mark`, `agy-seam-inject`, `agy-test-audit-reminder`, `agy-consult-recovery`. **Run all four
BEFORE Step 1 and record each total** - Step 7 compares against those numbers, not against `_partition.md`.

Each caller keeps its OWN ANCHOR: the writer and `agy-seam-inject.sh` join the path to the cwd,
`agy-test-audit-reminder.sh` to its cwd, `agy-consult-recovery.sh` to the git root. Only the RELATIVE part
moves into the library. Do not change any anchor.

- [ ] **Step 1: Create `clavity-dotnet/plugin/hooks/agy-marker-lib.sh`** with exactly this content (LF line endings):

```bash
#!/usr/bin/env bash
# The ONE place the debounce-marker path is built (ROADMAP section 39).
#
# SOURCED, NEVER EXECUTED - it must not call `exit`: agy-mark.sh (a process) and three fail-open hooks
# source it. The writer (agy-mark.sh) and every reader (agy-seam-inject.sh, agy-test-audit-reminder.sh,
# agy-consult-recovery.sh) each used to build `.clavity/agy-marks/<discipline>.head` on its own, and the
# invariant that they agree - the SAME discipline string, unmodified, in the SAME shape - was asserted
# nowhere. A one-sided change (a writer that lowercases, a reader that does not) would land the marker where
# no reader looks; on a case-insensitive filesystem the two names even resolve to one file, so the
# divergence would show only on the case-sensitive platforms CI does not run. Building the path in one
# function makes that divergence impossible by construction rather than detectable by a test.
# The discipline string is used RAW - agy-ledger-lib.sh derives the ledger path from the same string, and
# its comment explains why normalising either path alone would turn a non-issue into a bypass.
#
# agy_marker_rel <out-var> <discipline>
# Sets <out-var> to the marker path relative to the caller's anchor. `printf -v` rather than command
# substitution: two callers are hooks that run on every tool call, and each fork costs ~126ms on Windows.
agy_marker_rel() {
    printf -v "$1" '.clavity/agy-marks/%s.head' "$2"
}
```

- [ ] **Step 2: The writer.** In `agy-mark.sh`, immediately after the line
`command -v agy_ledger_lookup >/dev/null 2>&1 || _die_refuse "ledger helper loaded but agy_ledger_lookup is not defined: [$_ledger_lib]"` insert:

```bash

# Load the marker-path builder (ROADMAP section 39): the writer and every reader build the path with it.
_marker_lib="$_self_dir/agy-marker-lib.sh"
[ -f "$_marker_lib" ] || _die_refuse "marker-path helper not found beside this script: [$_marker_lib]"
# shellcheck source=agy-marker-lib.sh
. "$_marker_lib" 2>/dev/null || _die_refuse "marker-path helper could not be sourced: [$_marker_lib]"
command -v agy_marker_rel >/dev/null 2>&1 || _die_refuse "marker-path helper loaded but agy_marker_rel is not defined: [$_marker_lib]"
```

and replace `        rel=".clavity/agy-marks/$discipline.head"` with `        agy_marker_rel rel "$discipline"`.

- [ ] **Step 3: `agy-seam-inject.sh`.** Replace

```bash
head=$(git -C "$cwd_path" rev-parse HEAD 2>/dev/null)
marker="$cwd_path/.clavity/agy-marks/$discipline.head"
if [ -n "$head" ] && [ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$head" ]; then
```

with

```bash
head=$(git -C "$cwd_path" rev-parse HEAD 2>/dev/null)
# ROADMAP section 39: the relative path comes from the SAME builder the writer uses. If the builder cannot
# be loaded the debounce cannot run, so fall through and inject - the safe direction, as for an
# unresolvable HEAD below.
_rel=''
. "$(dirname "$0" 2>/dev/null)/agy-marker-lib.sh" 2>/dev/null && agy_marker_rel _rel "$discipline"
marker=''
[ -n "$_rel" ] && marker="$cwd_path/$_rel"
if [ -n "$head" ] && [ -n "$marker" ] && [ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$head" ]; then
```

- [ ] **Step 4: `agy-test-audit-reminder.sh`.** Replace the line `DIR_CONST=".clavity/agy-marks"` with

```bash
# ROADMAP section 39: both marker paths come from the SAME builder agy-mark.sh writes with. If it cannot be
# loaded both stay empty, both reads come back empty, and the gate stays SILENT - it can then see no GREEN,
# which is the safe answer at this hook's capstone call site.
_cap_rel=''; _aud_rel=''
if . "$(dirname "$0" 2>/dev/null)/agy-marker-lib.sh" 2>/dev/null; then
  agy_marker_rel _cap_rel agy-capstone
  agy_marker_rel _aud_rel agy-test-audit
fi
```

and in `gate()` replace

```bash
  cap=$(cat "$cwd/$DIR_CONST/agy-capstone.head" 2>/dev/null)
```
with
```bash
  cap=''; [ -n "$_cap_rel" ] && cap=$(cat "$cwd/$_cap_rel" 2>/dev/null)
```
and
```bash
  aud=$(cat "$cwd/$DIR_CONST/agy-test-audit.head" 2>/dev/null)
```
with
```bash
  aud=''; [ -n "$_aud_rel" ] && aud=$(cat "$cwd/$_aud_rel" 2>/dev/null)
```

Then grep the file for `DIR_CONST`: expect zero hits (header comment lines 4 and 6 name the path in prose;
leave them).

- [ ] **Step 5: `agy-consult-recovery.sh`.** Immediately after the line `_tokens='agy-capstone|agy-panel|agy-test-audit|agy-first'` insert

```bash
# ROADMAP section 39: the marker path comes from the SAME builder agy-mark.sh writes with. If it cannot be
# loaded no seam can be shown concluded, so every candidate is surfaced - the loud direction for a reader
# whose job is recovery.
_marker_lib_ok=0
. "$(dirname "$0" 2>/dev/null)/agy-marker-lib.sh" 2>/dev/null && _marker_lib_ok=1
```

and in the loop replace

```bash
    _marker="$root/.clavity/agy-marks/$_tok.head"
    # Concluded iff the seam's OWN marker is newer than it.
    if [ -e "$_marker" ] && [ "$_marker" -nt "$_s" ]; then
```
with
```bash
    _marker=''
    if [ "$_marker_lib_ok" = 1 ]; then agy_marker_rel _mrel "$_tok"; _marker="$root/$_mrel"; fi
    # Concluded iff the seam's OWN marker is newer than it.
    if [ -n "$_marker" ] && [ -e "$_marker" ] && [ "$_marker" -nt "$_s" ]; then
```

- [ ] **Step 6: Confirm no builder remains outside the library.**

```powershell
rg -n 'agy-marks/\$|agy-marks/\$\{' clavity-dotnet/plugin/hooks
```
Expect: no hits. (`agy-marks/skipped.log` and `agy-marks/consults.log` are log files, not markers; they may stay.)

- [ ] **Step 7: Mirror all five files to classic**, then run in turn: `agy-mark`, `agy-seam-inject`,
`agy-test-audit-reminder`, `agy-consult-recovery`, `plugin-hooks-payload`, and
`bash scripts/check-seed-artifacts-synced.sh`. Expect every suite `Failed: 0` with EXACTLY the totals you
recorded before Step 1; a changed total means a row was skipped or lost - report it.

- [ ] **Step 8: Commit**

```powershell
git add clavity-dotnet/plugin/hooks/agy-marker-lib.sh clavity-classic/plugin/hooks/agy-marker-lib.sh `
        clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh `
        clavity-dotnet/plugin/hooks/agy-seam-inject.sh clavity-classic/plugin/hooks/agy-seam-inject.sh `
        clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh clavity-classic/plugin/hooks/agy-test-audit-reminder.sh `
        clavity-dotnet/plugin/hooks/agy-consult-recovery.sh clavity-classic/plugin/hooks/agy-consult-recovery.sh
git commit -m "refactor(hooks): one shared builder for the marker path, used by the writer and all readers (section 39)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: peer-scratch - report a hook wired from `.clavity/`

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-liveness-check.sh` (then copy to classic)
- Modify: `scripts/tests/agy-liveness-check.Tests.ps1`
- Modify: `clavity-dotnet/plugin/README.md` and `clavity-classic/plugin/README.md` (section `## Hook ownership`)

- [ ] **Step 1: Write the rows.** Insert immediately after the closing `}` of
`It 'REPORTS a duplicate registered in settings.local.json'`:

```powershell
    It 'REPORTS a hook wired from .clavity/ (settings.local.json, a Windows backslash path)' {
        # The 2026-08-30 shape (docs/backlog/peer-scratch-dir-contains-executable-session-hooks.md): three
        # probes under .clavity/scratch/ were live SessionStart hooks in settings.local.json. .clavity/scratch/
        # is the directory every review-only brief hands the agy peer as its write area, so a hook wired from
        # there executes whatever the peer may have written.
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        $proj = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-proj-" + [Guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $proj '.claude') -Force | Out-Null
            @{ hooks = @{ SessionStart = @( @{ hooks = @( @{ type='command'; command='bash "C:\repo\.clavity\scratch\probe\abs-probe.sh"' } ) } ) } } |
                ConvertTo-Json -Depth 8 | Set-Content (Join-Path $proj '.claude/settings.local.json') -Encoding ascii
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $proj }
            $r.ExitCode | Should -Be 0
            $j = $r.StdOut | ConvertFrom-Json
            $j.systemMessage | Should -Match 'run from \.clavity/' -Because 'a hook wired into the peer write area is an ACTIONABLE FAULT, so it earns the owner''s screen'
            $j.systemMessage | Should -Match 'settings\.local\.json' -Because 'the note must name the file to fix'
        } finally { Remove-Item $cfg,$h,$proj -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'REPORTS a .clavity/ wiring at USER scope even under .no-agy (constraint 5)' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        try {
            @{ enabledPlugins = @{ 'superpowers@superpowers-marketplace' = $true }
               hooks = @{ SessionStart = @( @{ hooks = @( @{ type='command'; command='bash "$CLAUDE_PROJECT_DIR/.clavity/scratch/x/probe.sh"' } ) } ) }
            } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $cfg 'settings.json') -Encoding ascii
            New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 0
            $j = $r.StdOut | ConvertFrom-Json
            $j.systemMessage | Should -Match 'run from \.clavity/' -Because 'the kill-switch must not hide a wiring into the peer write area'
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT for a command that only LOOKS like .clavity/: <Cmd>' -ForEach @(
        @{ Cmd = 'bash "$CLAUDE_PROJECT_DIR/clavity/hooks/probe.sh"' }
        @{ Cmd = 'bash "/x/.clavity-old/probe.sh"' }
        @{ Cmd = 'bash "/x/my.clavity/probe.sh"' }
    ) {
        # Near-misses: no leading dot; a sibling directory name; `.clavity` inside a longer segment. A check
        # that fires on these cries wolf on every start, which trains the owner to stop reading the notice.
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        try {
            @{ enabledPlugins = @{ 'superpowers@superpowers-marketplace' = $true }
               hooks = @{ SessionStart = @( @{ hooks = @( @{ type='command'; command=$Cmd } ) } ) }
            } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $cfg 'settings.json') -Encoding ascii
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -BeNullOrEmpty -Because "a near-miss must not be reported: [$Cmd]"
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

- [ ] **Step 2: Run the suite - the failing control.** Expect exactly the two REPORTS rows to fail (the three
near-miss rows pass today, since nothing reports anything yet). Record counts.

- [ ] **Step 3: Implement.** In `agy-liveness-check.sh`, replace

```bash
    if ! personal_raw=$(jq -r '(.hooks // {}) as $h
                               | [$h[][].hooks[]]              as $entries
                               | [$entries[].command // empty] as $cmds
                               | "\($entries | length) \($cmds | length) \([$cmds[] | ascii_downcase | scan("[a-z0-9._-]+\\.sh")] | unique | join(" "))"' "$f" 2>/dev/null); then
```

with

```bash
    # The THIRD field counts commands that run from .clavity/ (peer-scratch backlog item, replacing its
    # "Option 3"): that directory is the agy peer's sanctioned write area, so a hook wired from it executes
    # whatever the peer may have written. Backslashes are folded to `/` first so a Windows path matches, and
    # the character before `.clavity/` must not continue a name, so `my.clavity/` and `.clavity-old/` do not.
    if ! personal_raw=$(jq -r '(.hooks // {}) as $h
                               | [$h[][].hooks[]]              as $entries
                               | [$entries[].command // empty] as $cmds
                               | [$cmds[] | gsub("\\\\"; "/") | ascii_downcase | select(test("(^|[^a-z0-9._-])\\.clavity/"))] as $wired
                               | "\($entries | length) \($cmds | length) \($wired | length) \([$cmds[] | ascii_downcase | scan("[a-z0-9._-]+\\.sh")] | unique | join(" "))"' "$f" 2>/dev/null); then
```

replace `    read -r entry_count cmd_count personal <<<"$personal_raw"` with
`    read -r entry_count cmd_count wired_count personal <<<"$personal_raw"`, and immediately AFTER the
`if [ "${entry_count:-0}" -gt 0 ] && [ "${cmd_count:-0}" -eq 0 ]; then ... fi` block insert

```bash
    if [ "${wired_count:-0}" -gt 0 ]; then
      ownership_note="${ownership_note}[AGY-DISCIPLINES] $wired_count hook command(s) in $f run from .clavity/ - that directory is the agy peer's sanctioned write area, so a hook wired from it runs whatever the peer may have written; move the script out of .clavity/ or remove the registration, then restart or /clear this session"$'\n'
    fi
```

In the header comment, change the ACTIONABLE FAULT line
`#   an ACTIONABLE FAULT  - superpowers not live, jq missing, a personal hook overriding a shipped one -`
to
`#   an ACTIONABLE FAULT  - superpowers not live, jq missing, a personal hook overriding a shipped one, a hook wired from .clavity/ -`.

- [ ] **Step 4: Run the suite.** Expect `Failed: 0` and the count 5 higher than before Step 1.

- [ ] **Step 5: Prove it by four logic mutants** (`git add` first; restore each with `git checkout -- clavity-dotnet/plugin/hooks/agy-liveness-check.sh`):
  - A: delete the `ownership_note=...run from .clavity/...` line. Expect both REPORTS rows to fail.
  - B: replace `gsub("\\\\"; "/") | ` with nothing. Expect the backslash REPORTS row to fail.
  - C: replace `test("(^|[^a-z0-9._-])\\.clavity/")` with `test("clavity/")`. Expect the `clavity/hooks` near-miss row to fail.
  - D: replace `test("(^|[^a-z0-9._-])\\.clavity/")` with `test("\\.clavity/")`. Expect the `my.clavity` near-miss row to fail.

- [ ] **Step 6: README.** In BOTH `clavity-dotnet/plugin/README.md` and `clavity-classic/plugin/README.md`,
section `## Hook ownership`, append this paragraph after the one ending `...never by shadowing the shipped copy.`:

```markdown
**A hook must not run from `.clavity/`.** That directory is the agy peer's sanctioned write area: every
review-only brief hands it `.clavity/scratch/` to write in. A hook registered from there executes whatever
the peer may have written, so the startup check reports any hook command in your user, project or
project-local `settings.json` that runs from `.clavity/`, even under `.no-agy`. Move such a script out of
`.clavity/` or remove its registration.
```

- [ ] **Step 7: Mirror the hook, run `plugin-hooks-payload` and `check-seed-artifacts-synced.sh`, then commit**

```powershell
Copy-Item -LiteralPath clavity-dotnet/plugin/hooks/agy-liveness-check.sh -Destination clavity-classic/plugin/hooks/agy-liveness-check.sh -Force
git add clavity-dotnet/plugin/hooks/agy-liveness-check.sh clavity-classic/plugin/hooks/agy-liveness-check.sh `
        scripts/tests/agy-liveness-check.Tests.ps1 clavity-dotnet/plugin/README.md clavity-classic/plugin/README.md
git commit -m "feat(liveness): report a hook wired from .clavity/, the peer's write area (peer-scratch item)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: §52 - the marker content is the ledger row's range end

**Files:**
- Modify: `clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md` and `clavity-dotnet/plugin/skills/agy-capstone/SKILL.md` (then copy both to classic)
- Modify: `docs/agy-disciplines-marker-contract.md`

**Load `superpowers:writing-skills` BEFORE editing either SKILL.md** (standing owner rule).

The capstone skill carries the SAME defect: its content line already says "the REVIEWED sha", but its command
writes `$(git rev-parse HEAD)`, which at write time is the ledger commit and is refused. It is fixed here
because it is the same contradiction in the sibling skill; the owner is told at hand-off.

- [ ] **Step 1: agy-test-audit, section `## Debounce marker`.** Replace the command line
`bash "<BASE>/../../hooks/agy-mark.sh" head "agy-test-audit" "$(git rev-parse HEAD)"` with
`bash "<BASE>/../../hooks/agy-mark.sh" head "agy-test-audit" "$(git rev-parse <RANGE-END>)"`.

Replace the whole `- **Content:** ambient `HEAD`, exactly as the command above writes it. ...` bullet,
including its quoted `> This line said ...` paragraph (it ends `...rule requires a re-capstone before the
branch is done.`), with:

```markdown
- **Content:** the sha the ledger row's range ENDS on - the last commit this audit covered: the last
  gap-fold commit if the run folded any, otherwise the audited tip. Put it in place of `<RANGE-END>`
  above; `git rev-parse` expands a short sha into the full one the writer expects. If it cannot resolve,
  skip writing (the discipline re-fires next trigger - safe).

  > NOT ambient `HEAD`, which is what this line said until 2026-09-30 (ROADMAP section 52). The row above
  > must be committed BEFORE the marker, so at write time HEAD is the ledger commit - and a commit cannot
  > name itself, so no row records it and the writer's ledger gate REFUSES it. MEASURED twice: the ledger
  > commits `e1ee49ec` and `8829274c` were each refused `ABSENT`, and each row's range end was accepted. The
  > range end still silences the reminder hook: it goes quiet when the audit marker STILL DESCRIBES HEAD -
  > equals it, or is an ancestor of it with nothing executable landed since - and the only commit after
  > it is the docs-only ledger row.
```

In the same section, replace (the file wraps these lines differently - match the words, not the line breaks)
`abort writes NO marker (the discipline re-fires next trigger). If closing gaps advanced HEAD by touching
executable code, the capstone GREEN no longer describes HEAD - do not paper over that by choosing a
different sha to record; re-run AGY-CAPSTONE, per the capstone-invalidation rule above.` with
`abort writes NO marker (the discipline re-fires next trigger). If closing gaps changed implementation
SOURCE (not only tests), the capstone GREEN no longer covers it - re-run AGY-CAPSTONE, per the
capstone-invalidation rule above, before writing this marker.`

Earlier in the file (section on the ledger row, the paragraph beginning `Without this row the marker is the
only trace`), replace `ambient `HEAD`, not a record of what was audited.` with
`one sha for the reminder hook to compare - not a record of the audited range, its rounds or its verdict.`
(Panel round 2, peer: simply swapping in "the ledger row's range end" would call that sha "not a record of
what was audited" while it IS the audited range end - a contradiction inside the same skill.)

- [ ] **Step 2: agy-capstone, section `## Debounce marker`.** Replace the command line
`bash "<BASE>/../../hooks/agy-mark.sh" head "agy-capstone" "$(git rev-parse HEAD)"` with
`bash "<BASE>/../../hooks/agy-mark.sh" head "agy-capstone" "$(git rev-parse <REVIEWED-SHA>)"`, and at the END
of the `- **Content:** the REVIEWED sha - ...` bullet append the sentence:
`Put it in place of `<REVIEWED-SHA>` above. Do NOT substitute `$(git rev-parse HEAD)` at write time: the ledger row is committed first, so HEAD is then the ledger commit, which no row records and the writer refuses (ROADMAP section 52).`

- [ ] **Step 3: Sweep both skills for the old wording** (the incomplete-fold law):

```powershell
rg -n -i 'ambient .?HEAD|rev-parse HEAD\)"' clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md clavity-dotnet/plugin/skills/agy-capstone/SKILL.md
```
Every hit left must be one that is still TRUE (e.g. the capstone's "NOT an ambient HEAD re-sampled" and the
`log` command lines, which record ambient HEAD by design). Report each remaining hit and why it stays.

- [ ] **Step 4: The contract doc** `docs/agy-disciplines-marker-contract.md`:
  - Replace `- **Content:** the commit sha from `git rev-parse HEAD` at consult time, and nothing else. If HEAD cannot` / `  resolve (no repo / no commits), no marker is written (the discipline re-fires — safe).` with:
    ```markdown
    - **Content:** a bare commit sha, and nothing else. `agy-first`: HEAD at consult time. `agy-capstone`: the
      REVIEWED sha captured at the confirmed GREEN. `agy-test-audit`: the sha its ledger row's range ends on.
      For the two disciplines that own a ledger the sha is the row's range end, never ambient HEAD at write
      time - that is the ledger commit itself, which no row can record (ROADMAP §52). If the sha cannot
      resolve, no marker is written (the discipline re-fires — safe). Where git can answer, `agy-mark.sh`
      refuses a sha that names no commit (ROADMAP §51).
    ```
  - Replace `  In every case the content stays the bare `git rev-parse HEAD` sha, so the SP-C hook's` with `  In every case the content stays a bare commit sha, so the SP-C hook's`.
  - Replace `  next trigger). Content is the audited `git rev-parse HEAD`.` with `  next trigger). Content is the sha its ledger row's range ends on.`

- [ ] **Step 5: Mirror both skills and run the skill gates.**

```powershell
Copy-Item -LiteralPath clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md -Destination clavity-classic/plugin/skills/agy-test-audit/SKILL.md -Force
Copy-Item -LiteralPath clavity-dotnet/plugin/skills/agy-capstone/SKILL.md -Destination clavity-classic/plugin/skills/agy-capstone/SKILL.md -Force
just check-agy-skills
just check-skill-frontmatter
bash scripts/check-seed-artifacts-synced.sh
```
Expect `agy-discipline skills OK`, `check-skill-frontmatter: OK`, and exit 0.

- [ ] **Step 6: Commit**

```powershell
git add clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md clavity-classic/plugin/skills/agy-test-audit/SKILL.md `
        clavity-dotnet/plugin/skills/agy-capstone/SKILL.md clavity-classic/plugin/skills/agy-capstone/SKILL.md `
        docs/agy-disciplines-marker-contract.md
git commit -m "fix(skills): write the marker at the ledger row's range end, not ambient HEAD (section 52)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Registration counts and the backlog stub

**Files:**
- Modify: `scripts/tests/_partition.md` (a GATE: its per-suite counts are checked)
- Modify: `docs/backlog/peer-scratch-dir-contains-executable-session-hooks.md`

- [ ] **Step 1: Measure the real counts** of `agy-ledger-lib`, `agy-mark`, `agy-liveness-check` (one suite at a
time) and update each row's test count in `_partition.md`, appending to its note
`; N -> M on 2026-09-30 (sweep Branch 2), runtime NOT re-measured.` Do not change the seconds.

- [ ] **Step 2: Run `test-suite-registration`.** Expect `Failed: 0`.

- [ ] **Step 3: Close the backlog stub.** Change its `**Status:**` line to begin
`**Status:** CLOSED 2026-09-30 on sweep Branch 2 - Option 3 was REPLACED by an owner ruling after AGY-FIRST: agy-liveness-check.sh now reports any hook command in the three settings files that runs from .clavity/ (<Task 4 sha>).`
and append a section:

```markdown
## Closure 2026-09-30 - why Option 3 was replaced

Under Git Bash on Windows the executable bit is not stored; it is inferred (for example from a `#!` first
line), so censusing it under `scratch/` would flag every script the peer legitimately writes there - and a
bit-only record misses an already-executable file whose content changes. The live risk this item named is
a hook being WIRED to run from the peer's write area, so that is what is now checked, at every startup and
for a human's wiring as well as the peer's. The consult guard still records `scratch/` by name only; that is
unchanged and deliberate.
```

- [ ] **Step 4: Commit**

```powershell
git add scripts/tests/_partition.md docs/backlog/peer-scratch-dir-contains-executable-session-hooks.md
git commit -m "test(partition): register Branch 2's suite counts; close the peer-scratch backlog item" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Bump both plugin versions

A same-version reinstall is a measured no-op (the plugin runs from the installed cache), so the version must
move for the owner's reinstall to pick any of this up. Both members bump because every change is a
byte-identical pair. Precedent: `0ac35e45`.

**Files:** written by `scripts/bump-version.ps1` - dotnet: both `plugin.json`; classic: `Cargo.toml`,
`Cargo.lock`, `agy-mcp-bridge/pyproject.toml`, `agy-mcp-bridge/uv.lock`, `installer/clavity-classic.iss`,
both `plugin.json`.

- [ ] **Step 1: Bump**

```powershell
just bump dotnet 0.9.3
just bump classic 0.8.2
```
Expect `check-versions: class 'all' OK (dotnet) = 0.9.3` and `... (classic) = 0.8.2`.

Then `git diff --stat` and `git diff clavity-classic/agy-mcp-bridge/uv.lock clavity-classic/Cargo.lock`: each
lock file must change ONLY its own package's version line (precedent `0ac35e45`: one line each). If `uv lock`
or `cargo set-version` re-resolved any dependency, STOP and report - a dependency move is not part of this branch.

- [ ] **Step 2: Compile the classic installer** (standing build lesson: an `.iss` change is compiled, never
eyeballed). Locate `ISCC.exe` with `Get-Command ISCC` (measured 2026-09-30: `C:\Program Files\Inno Setup 7\ISCC.exe`, on PATH) and run it
on `clavity-classic/installer/clavity-classic.iss`. Expect `Successful compile`. If ISCC is absent, STOP and report.
Do not commit the compiled output.

- [ ] **Step 3: Commit** - subject `chore(version)`, NEVER `chore(release)` (release tooling matches that prefix):

```powershell
git add clavity-dotnet/plugin/plugin.json clavity-dotnet/plugin/.claude-plugin/plugin.json `
        clavity-classic/Cargo.toml clavity-classic/Cargo.lock clavity-classic/agy-mcp-bridge/pyproject.toml `
        clavity-classic/agy-mcp-bridge/uv.lock clavity-classic/installer/clavity-classic.iss `
        clavity-classic/plugin/plugin.json clavity-classic/plugin/.claude-plugin/plugin.json
git commit -m "chore(version): bump dotnet 0.9.2 -> 0.9.3 and classic 0.8.1 -> 0.8.2" -m "Makes sweep Branch 2 (sections 39, 40, 51, 52 and the peer-scratch check) reachable by an installed plugin: a same-version reinstall is a no-op. Both members bump because every change is a byte-identical pair." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Close the ROADMAP headers and publish this plan (LAST commit before the capstone)

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md`
- Add: `docs/superpowers/plans/2026-09-30-sweep-branch-2-markers.md` (this file)

- [ ] **Step 1:** Append to each header, citing the fix shas from Tasks 1-5 (never this commit's own sha):
  - `### §39 ...` -> ` · ✅ **FIXED 2026-09-30 on sweep Branch 2 (`<Task 3 sha>`) - one shared builder, agy-marker-lib.sh, used by the writer and all three readers; no test, by owner ruling**`
  - `### §40 ...` -> ` · ✅ **FIXED 2026-09-30 on sweep Branch 2 (`<Task 1 sha>`) - rows on both sides of the 7-character edge, each killed by its mutant**`
  - `### §51 ...` -> ` · ✅ **FIXED 2026-09-30 on sweep Branch 2 (`<Task 2 sha>`) - refuses where git can answer; no repository or no git means no check**`
  - `### §52 ...` -> ` · ✅ **FIXED 2026-09-30 on sweep Branch 2 (`<Task 5 sha>`) - the skill writes the ledger row's range end; the capstone skill's command had the same defect and is fixed with it**`

- [ ] **Step 2: Gates.** `just check-injected-context` (expect `OK`) and `just check-control-bytes` (expect `control bytes ok`).

- [ ] **Step 3: Commit**

```powershell
git add clavity-dotnet/ROADMAP.md
# docs/superpowers/plans/* is gitignored (.gitignore:41); the owner ruled at step 0 to keep publishing plans,
# and the Branch 1 plan is tracked the same way. -f for THIS one path only.
git add -f docs/superpowers/plans/2026-09-30-sweep-branch-2-markers.md
git commit -m "docs(roadmap): close sections 39, 40, 51, 52 and publish the Branch 2 plan" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## After the tasks (driver only - spec steps (d)-(f) and the plugin-pair halt)

1. **Full repo gates:** `lefthook run pre-push --all-files`, `just check-injected-context`, and the fast Pester half.
2. **AGY-CAPSTONE** over `b29c4df2..<Task 8 sha>` until GREEN; the owner adjudicates. Ledger row, then the marker at the reviewed sha.
3. **AGY-TEST-AUDIT** over the same range; ledger row, then the marker at the row's range end (the rule Task 5 writes down).
4. **Merge** to local `main` (`--no-ff`); the owner pushes.
5. **HALT for the reinstall.** Record the halt in the execution index, then ask the owner to reinstall with Claude Code fully closed, through the plugin manager, never `clavity-install.ps1`. Start nothing until the owner confirms AND the installed version reads 0.9.3:

```powershell
(Get-Content -Raw "$env:USERPROFILE\.claude\plugins\installed_plugins.json" | ConvertFrom-Json).plugins.'clavity@clavity' | Select-Object version, installPath
```

## Stand-downs

AGY-AFTER panel: a driver solo round (3 folded), peer round 1 (no findings; its reply was flagged INCOMPLETE
by the 13b check because the driver's brief put the wrong terminal token last, and its file list skipped five
quoted files, so it was not counted as clean), and peer round 2 (all 15 quoted anchors it checked found; one
DEBT folded into Task 5 Step 1). A driver census of all 36 quoted anchors passed
(`.clavity/scratch/branch2/quote-census.ps1`). Peer discards below the floor: a settings file deleted between
the existence check and the jq read (a race already present); the marker library failing to source in a
reader hook (each reader's fallback was traced to the safe direction).

- **No test for §39** - owner ruling. The peer's first test recipe was measured VACUOUS: `Get-Item <path>`
  echoes the case of the path you pass, not the case on disk (`.clavity/scratch/branch2/verify-forks.out.txt`).
- **No separate "no git on PATH" row for §51.** It takes the same branch as "no repository" (the rev-parse
  probe fails), which the git-optional row pins.
- **The wiring check sits inside the shipped-hook-list branch** of `agy-liveness-check.sh`: if the plugin's
  own `hooks.json` is unreadable, the hook already reports that and checks nothing else, the wiring included.
- **The wiring check matches ANY `.clavity/` path, including a user-level `~/.clavity/`.** That directory is
  not the peer's scratch zone, so a hook wired from it would be reported too. Accepted: MEASURED 2026-09-30,
  none of the three real settings files wires a hook from any `.clavity/` path (the three hits in
  `settings.local.json` are permission rules, which the check does not read), and the note's remedy - move
  the script - is harmless for a user-level script. Narrowing it would mean resolving absolute paths against
  the project root inside jq, for no measured case.
- **`agy-consult-recovery.sh` anchors markers at the git root, the writer at the cwd.** That is a different
  axis from §39 (the anchor, not the name) and is not changed here.

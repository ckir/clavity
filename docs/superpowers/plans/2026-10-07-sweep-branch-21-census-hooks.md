# Branch 21 — the eight census hooks under the 16-process ceiling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring every measured census path of the eight Branch-21 hooks to at most 16 processes per run (3 of them bash boot), without changing any hook's observable behaviour, and fold ROADMAP §72, §73, §64, §59-in-full and the three 2026-10-07 inventory defects into the same branch.

**Architecture:** Branch 20's method, applied to eight more hooks: replace subprocesses with bash builtins (`IFS= read -r -d ''` stdin, `[[ =~ ]]` + `BASH_REMATCH`, parameter expansion, `printf -v '%(fmt)T'` gated at bash ≥ 4.2), measured per path by the Windows Job Object harness (`Measure-BashHookProcesses`). Two phases by owner ruling 2026-10-07: phase 1 = the two hooks with design forks (`agy-inbox-snapshot`, `agy-discipline-reaching` + the shared `agy-shield-lib.sh`), closed by their own AGY-CAPSTONE round; phase 2 = the six fork-free hooks and the folds. Owner-ruled forks: Fork 1 = 1A+1C (one `ls -1t` before the copy serves dedup and prune; one `rm -f --` for all surplus backups; mtime order kept). Fork 2 = 2A+2B (builtins; `git check-ignore` first, `rev-parse` only when its rc is neither 0 nor 1); §41's prepend (`mktemp`/`cat`/`mv`) is NOT touched; 2D (find gating) is the sanctioned reserve and the arithmetic below shows the `!`-negation path needs it, so it activates as a builtin-glob gate.

**Tech Stack:** bash hooks (Git Bash / bash 3.2-compatible fallbacks), Pester 5 suites under `scripts/tests/`, the Branch-20 process-count harness (`scripts/tests/BashHookHelpers.ps1`, `hook-spawn-budget.Tests.ps1` + `hook-spawn-budget.Rows.ps1`).

---

## Context — measured baseline (2026-10-07, tip `6a6224ce`; `.clavity/scratch/b21-measure/before-summary.txt`)

130 census paths re-measured, r1 == r2 on every row, 44 paths over 16 (totals INCLUDE the 3 boot processes):

| hook | paths over 16 | worst | notes |
|---|---|---|---|
| `agy-autotrain/hooks/agy-inbox-snapshot.sh` | 12 | 67 | steady state 37; even "Pending empty" is 18; jq and no-jq paths both over |
| `clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh` (+ shared `agy-shield-lib.sh`) | 6 | 36 | `!`-negation repeat 34 and tracked-jsonl 20/18 RECUR every SessionStart |
| `clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh` | 7 | 35 | steady state 17; lookup paths 20–35 |
| `.claude/hooks/agy-verify-reminder.sh` | 5 | 24 | has NO test suite today |
| `.claude/hooks/docs-audit-reminder.sh` | 5 | 22 | every generated-view path 22 |
| `clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh` | 4 | 23 | all four = the jq path |
| `clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh` | 4 | 21 | TMPDIR-fallback worst |
| `agy-autotrain/hooks/migrate-inbox.sh` | 1 | 17 | RECOVER path only |

`agy-anomaly-dispatch-reminder.sh` (max 11) and `agy-anomaly-model-notice.sh` (max 14) are UNDER the ceiling — their §59 work is the stderr-under-empty-PATH fix only. `agy-curate-nudge.sh` is already budgeted by Branch 20; its §73 work is the `date -d` line.

**Owner rulings binding this plan (2026-10-07):**
- Criterion: EVERY census path ≤ 16, including recurring failure states. One budget row per formerly-over path.
- Fork 1 = 1A+1C. Fork 2 = 2A+2B; §41's prepend untouched; find-gating is the reserve (it activates — see Task 2 arithmetic).
- One branch, two phases; phase 1 gets its own capstone round before phase 2 starts.
- Scope: §69 + §72 (stale test-audit debounce sweep) + §73 (curate `date -d`) + §64 (`mktemp -d` failure test) + §59 in full (the three hooks still printing stderr under an empty PATH: `assertion-strength-reminder.sh`, `agy-anomaly-dispatch-reminder.sh`, `agy-anomaly-model-notice.sh` — the other four §59 hooks were fixed by Branch 20, measured 2026-10-07) + the three inventory defects (`AGY_INBOX_SNAPSHOT_KEEP=08` arithmetic abort; the `[ \t]` heading-class mismatch in `agy-inbox-snapshot.sh`; `printf %(fmt)T` called with no bash-4.2 gate in `agy-discipline-reaching.sh:121` and `assertion-strength-reminder.sh:37,107`).

**Repo disciplines that bind every task below:**
- Stage EXPLICIT paths; never commit anything under `.clavity/`.
- Mirror every change to a dotnet-plugin hook into its byte-identical classic copy (`cp` dotnet → classic), then run `bash scripts/check-seed-artifacts-synced.sh` (expect exit 0). Applies to: `agy-discipline-reaching.sh`, `agy-shield-lib.sh`, `agy-anomaly-reminder.sh`, `assertion-strength-reminder.sh`, `agy-anomaly-dispatch-reminder.sh`, `agy-anomaly-model-notice.sh`. NOT to `fetch-clavity-ls.sh` (dotnet-only) or the agy-autotrain / `.claude/hooks` files.
- Plugin-shipped hooks (dotnet, classic, agy-autotrain trees) must stay pure ASCII (`plugin-hooks-payload.Tests.ps1` gates it). `.claude/hooks/*` are repo-local and exempt (both already carry em dashes).
- `scripts/tests/_partition.md` counts are a GATE: after each suite change, run the suite, read its `Tests Passed:` tally, and update that suite's count row with a dated note (`N -> M 2026-10-07 (Branch 21: <what>), time not re-measured`). Never compute the count from `It` blocks (`-ForEach` expands).
- Never run two Pester suites at once; a run with no `Tests Passed:` line is ABORTED, not green.
- Wall-clock is NOT a gate (TIMING discipline); the process COUNT is.
- Every new/changed test must be proven NON-VACUOUS by a logic mutant (see Mutant protocol).
- Commit messages: end with this session's standard `Co-Authored-By:` trailer.

**Bash-version rules (from Branch 20, reused verbatim):**
- `IFS= read -r -d '' var` (stdin slurp) is bash ≥ 2.04 — no gate needed; it replaces `$(cat)` everywhere.
- `[[ =~ ]]` with a PATTERN VARIABLE (`re='...'; [[ $x =~ $re ]]`) is bash-3.2-safe — always use the variable form, never an inline quoted pattern.
- `printf -v x '%(fmt)T' -1` is bash ≥ 4.2 — ALWAYS gate it: `if [ -z "${CLAVITY_HOOK_BASH3:-}" ] && ((BASH_VERSINFO[0]*100+BASH_VERSINFO[1] >= 402)); then printf -v ...; else <date fallback>; fi`. The harness's compat rows force the fallback with `CLAVITY_HOOK_BASH3=1` and assert byte-identical output + the row's `-Verify` effect on BOTH paths.
- Redirect order is load-bearing: `2>/dev/null` BEFORE `< "$file"`, or a failed open leaks the OS error (measured, Branch 18).

## Measure / run commands (used by every task)

```powershell
# One hook's budget + compat rows only (PP1: every -Expect row also JSON-parses the envelope):
$env:HSB_HOOK = '<hook-file-name>.sh'
pwsh -NoProfile -c "Invoke-Pester scripts/tests/hook-spawn-budget.Tests.ps1 -Output Detailed -CI"
Remove-Item env:HSB_HOOK
# Expected when the task is done: Tests Passed: <all>, Failed: 0 (plus 1 skipped census/debt row under HSB_HOOK).
```

```powershell
# Census re-measurement for one hook (counts + per-line trace; writes nothing to the repo):
pwsh -NoProfile -File .clavity/scratch/hook-perf/b20-protos/scratch-b20/census/run.ps1 `
  -Filter '^<hook-name>\|' -Out C:/Users/user/Development/Rust/clavity/.clavity/scratch/b21-measure/after-<hook-name>.jsonl
# Read the printed table: every row's R1/R2 must be <= 16.
```

## Mutant protocol (per feedback rules; run from the repo root)

`git add` the files under test FIRST. Apply each mutant with a FILE script (never a heredoc/stdin python): the script reads the target, asserts the `old` string occurs EXACTLY once, writes the mutant, and you then assert `git diff` is non-empty, run ONLY the named suite, confirm the NAMED row(s) went red, and restore the saved bytes (verify `git diff` clean afterwards). Template:

```python
# scratchpad/mut.py  <name>
import subprocess, sys
PATHS = [r"<file>", ...]          # mirrors get the same edit
OLD, NEW = "<old>", "<new>"
saved = {p: open(p, encoding='utf-8', newline='').read() for p in PATHS}
for p in PATHS:
    s = saved[p]; assert s.count(OLD) == 1, (p, s.count(OLD))
    open(p, 'w', encoding='utf-8', newline='').write(s.replace(OLD, NEW))
print('applied; run the suite, then restore')
# restore step (second invocation or finally-block): write saved[p] back per path
```

## File structure (what this branch creates / modifies)

- Modify (hooks): `agy-autotrain/hooks/agy-inbox-snapshot.sh` · `clavity-dotnet/plugin/hooks/agy-shield-lib.sh` (+ classic mirror) · `clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh` (+ classic) · `clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh` (+ classic) · `clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh` (+ classic) · `.claude/hooks/agy-verify-reminder.sh` · `.claude/hooks/docs-audit-reminder.sh` · `clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh` · `agy-autotrain/hooks/migrate-inbox.sh` · `clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh` (+ classic) · `clavity-dotnet/plugin/hooks/agy-anomaly-model-notice.sh` (+ classic) · `agy-autotrain/hooks/agy-curate-nudge.sh`
- Modify (tests): `scripts/tests/hook-spawn-budget.Rows.ps1` (new budget rows + two fixture helpers + `$B21Debt` emptied entry-by-entry) · the existing suites named per task · `scripts/tests/_partition.md`
- Create: `scripts/tests/agy-verify-reminder.Tests.ps1` (+ its `justfile` slow-list registration + `_partition.md` row)
- Modify (docs, Task 12): `clavity-dotnet/ROADMAP.md` (§69 progress, §72/§73/§64/§59 shipped notes)

Each task ends in its own commit(s); the `$B21Debt` entry for a hook is removed IN THE SAME COMMIT that brings its paths under the ceiling (the Rows file's own rule).

---

# PHASE 1 — the two fork hooks (own capstone round at Task 3)

### Task 1: `agy-inbox-snapshot.sh` — Fork 1A+1C, KEEP base-10, heading class, builtins

**Files:**
- Modify: `agy-autotrain/hooks/agy-inbox-snapshot.sh` (lines 13–14, 22, 52–73, 95, 100–112 as of `6a6224ce`)
- Modify: `scripts/tests/hook-spawn-budget.Rows.ps1` (new helper + 6 rows; remove the `agy-inbox-snapshot.sh` `$B21Debt` entry)
- Modify: `scripts/tests/agy-inbox-snapshot.Tests.ps1` (3 new rows; `$script:Hook` already points at the hook)
- Modify: `scripts/tests/_partition.md` (two count rows)

- [ ] **Step 1: Add the budget rows (the failing control — they are RED against today's hook).** In `scripts/tests/hook-spawn-budget.Rows.ps1`, immediately after the `function New-BudgetRow { ... }` block and the `$D/$C/$A/$L` line, add the fixture helper (dot-sourced in both BeforeDiscovery and BeforeAll, so it is visible to `-ForEach` and to row Setup blocks):

```powershell
function Add-FxInbox {
    # The canonical inbox lives in the FIXTURE home (${USERPROFILE:-$HOME} -> $fx.Home), never the real one.
    param($Fx, [int]$Baks = 0, [switch]$EmptyPending)
    $d = Join-Path $Fx.Home '.clavity'; New-Item -ItemType Directory -Force -Path $d | Out-Null
    $obs = Join-Path $d 'agy-observations.md'
    $body = "# agy observations inbox (raw, project-agnostic)`n`nprose`n`n## Pending`n`n"
    if (-not $EmptyPending) { $body += "- [heuristic] (driver/probabilistic) a rule * ``[corpus]`` * 2026-10-01 * agy 1.3.1`n" }
    [IO.File]::WriteAllText($obs, $body)
    for ($i = 1; $i -le $Baks; $i++) {
        $p = '{0}.202601{1:d2}-000000.bak' -f $obs, $i
        [IO.File]::WriteAllText($p, "old $i")
        # Distinct ascending mtimes: index 1 is the OLDEST. Ordering is mtime (fork 1C), not name.
        [IO.File]::SetLastWriteTimeUtc($p, [datetime]::UtcNow.AddMinutes($i - $Baks - 5))
    }
    $obs
}
function Get-FxBaks { param($Fx) @(Get-ChildItem -LiteralPath (Join-Path $Fx.Home '.clavity') -Filter 'agy-observations.md.*.bak' -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object Name) }
```

Then, in the rows list (`$script:Rows = @(...)`), after the existing `$A/agy-inbox-snapshot.sh` rows (there are TWO today — grep `'\$A/agy-inbox-snapshot'` and keep them; if either existing row's Name duplicates one below, keep the existing row and skip the duplicate), add:

```powershell
    # --- agy-inbox-snapshot.sh: the Branch 21 census paths (PreToolUse Skill + UserPromptSubmit) ---
    New-BudgetRow "$A/agy-inbox-snapshot.sh" 'curate skill, steady state: 5 baks -> snapshot + prune 1' {
        param($fx) [void](Add-FxInbox $fx -Baks 5); New-ToolPayload $fx 'Skill' @{ skill = 'agy-autotrain:agy-curate' } } -Silent -Verify {
        param($fx) (Get-FxBaks $fx).Count | Should -Be 5 }
    New-BudgetRow "$A/agy-inbox-snapshot.sh" 'curate skill, 20 baks -> snapshot + prune 16 in ONE rm' {
        param($fx) [void](Add-FxInbox $fx -Baks 20); New-ToolPayload $fx 'Skill' @{ skill = 'agy-autotrain:agy-curate' } } -Silent -Verify {
        param($fx) $left = Get-FxBaks $fx; $left.Count | Should -Be 5
        # IDENTITY, not count: the survivors are the four NEWEST old slots (17..20) plus the new snapshot.
        foreach ($n in 17..20) { ($left -match ('202601{0:d2}-000000' -f $n)).Count | Should -Be 1 } }
    New-BudgetRow "$A/agy-inbox-snapshot.sh" 'curate via UserPromptSubmit prompt, no baks -> first snapshot' {
        param($fx) [void](Add-FxInbox $fx); ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'UserPromptSubmit'; prompt = '/agy-curate' } } -Silent -Verify {
        param($fx) (Get-FxBaks $fx).Count | Should -Be 1 }
    New-BudgetRow "$A/agy-inbox-snapshot.sh" 'curate skill, newest bak identical -> dedup, no rotate' {
        param($fx) $obs = Add-FxInbox $fx; Copy-Item -LiteralPath $obs -Destination "$obs.20260101-000000.bak"
        New-ToolPayload $fx 'Skill' @{ skill = 'agy-autotrain:agy-curate' } } -Silent -Verify {
        param($fx) (Get-FxBaks $fx).Count | Should -Be 1 }
    New-BudgetRow "$A/agy-inbox-snapshot.sh" 'curate skill, Pending empty -> invariant 2 refuses, silent' {
        param($fx) [void](Add-FxInbox $fx -EmptyPending); New-ToolPayload $fx 'Skill' @{ skill = 'agy-autotrain:agy-curate' } } -Silent -Verify {
        param($fx) (Get-FxBaks $fx).Count | Should -Be 0 }
    New-BudgetRow "$A/agy-inbox-snapshot.sh" 'non-curate prompt (hot path, silent)' {
        param($fx) [void](Add-FxInbox $fx); ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'UserPromptSubmit'; prompt = 'hello' } } -Silent -Verify {
        param($fx) (Get-FxBaks $fx).Count | Should -Be 0 }
```

- [ ] **Step 2: Run the rows and verify they FAIL on the current hook** (counts over the ceiling — this is the failing control):

Run (PowerShell): `$env:HSB_HOOK='agy-inbox-snapshot.sh'; pwsh -NoProfile -c "Invoke-Pester scripts/tests/hook-spawn-budget.Tests.ps1 -Output Detailed -CI"; Remove-Item env:HSB_HOOK`
Expected: FAIL — the four snapshot rows exceed `Max` (census: 37/67/33/25 total vs 16), the two silent rows pass. If a row fails for a DIFFERENT reason (fixture never reached its path), fix the fixture before touching the hook.

- [ ] **Step 3: Rewrite the hook.** Apply these edits to `agy-autotrain/hooks/agy-inbox-snapshot.sh` (every cited line verified at `6a6224ce`):

(a) Lines 13–14 (the KEEP guard) — the 08 fix (inventory defect 1). Replace:

```bash
case "$KEEP" in ''|*[!0-9]*) KEEP=5 ;; esac
[ "$KEEP" -lt 1 ] && KEEP=5
```

with:

```bash
case "$KEEP" in ''|*[!0-9]*) KEEP=5 ;; esac
# Base-10, explicitly: a leading zero ("08") passes the digit check above, and bash then reads it as
# OCTAL in arithmetic - $((KEEP + 1)) aborts "value too great for base" (measured 2026-10-07), the
# prune never runs, and the ring grows without bound. 10# makes the knob mean what the operator typed.
KEEP=$((10#$KEEP))
[ "$KEEP" -lt 1 ] && KEEP=5
```

(b) Line 22 — the stdin read. Replace `input=$(cat 2>/dev/null)` with:

```bash
# BUILTIN, not $(cat): no fork, and under an empty PATH nothing is written to stderr (the section-59
# shape; same idiom as agy-anomaly-reminder.sh:37). read -d '' returns non-zero at EOF while still
# having filled $input - a bare call under set +e.
IFS= read -r -d '' input
```

(c) Lines 52–72 (the whole `matched` block, both the jq and the grep branches). Replace with ONE classification — the regexes are the current no-jq ones (lines 67 and 69) verbatim, moved to `[[ =~ ]]`:

```bash
# ONE classifier, no jq and no grep - the raw payload already decides. JSON escaping is what makes the
# raw match safe (Branch 20, measured): a "skill" or "prompt" KEY smuggled inside a value arrives as
# \"skill\" - the backslash breaks the match - so only the real top-level/tool_input field can fire.
# FIELD-BOUNDED and, for the prompt, ANCHORED at the start and bounded at the end - same reasoning as
# the jq branch this replaces: a prompt that merely discusses the curator must not burn a slot.
matched=""
re_skill='"skill"[[:space:]]*:[[:space:]]*"[^"]*agy-curate"'
re_prompt='"prompt"[[:space:]]*:[[:space:]]*"/(agy-autotrain:)?agy-curate([[:space:]][^"]*)?"'
if [[ $input =~ $re_skill ]] || [[ $input =~ $re_prompt ]]; then matched=1; fi
[ -z "$matched" ] && exit 0
```

(d) Lines 80–95 (the three invariants: two greps + awk|grep). Replace with one builtin pass. This also FOLDS inventory defect 2: grep's `[ \t]` class matched the literal characters `t` and `\` (measured: `##tPending` matched) while the awk read a real tab — the awk was downstream and stricter, so the NET behaviour (fire iff the awk's reading opens Pending) is preserved exactly by using the awk's semantics, now with a REAL tab via `$'...'`:

```bash
# --- Three stateless invariants, one builtin pass. Open/close rules match the canonical reader
# (drain-lib.ps1) and agy-curate-nudge.sh: open on '^##[ \t]+Pending[ \t]*$' (REAL tab - grep's
# bracket [ \t] matched literal 't'/'\' and disagreed with the awk it gated, measured 2026-10-07),
# close on any '^#+[ \t]' heading. The bullet class keeps the hyphen: anti-pattern must match.
hdr=0; pend=0; bullet=0; p=0
re_pending=$'^##[ \t]+Pending[ \t]*$'
re_close=$'^#+[ \t]'
re_bullet='^- \[[a-z-]+\]'
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in '# agy observations inbox'*) hdr=1 ;; esac
  if [[ $line =~ $re_pending ]]; then p=1; pend=1; continue; fi
  if [[ $line =~ $re_close ]]; then p=0; continue; fi
  if [ "$p" -eq 1 ] && [[ $line =~ $re_bullet ]]; then bullet=1; fi
done 2>/dev/null < "$OBS"
[ "$hdr" -eq 1 ] || exit 0
[ "$pend" -eq 1 ] || exit 0
[ "$bullet" -eq 1 ] || exit 0
```

(The unreadable-file case is unchanged: a failed open runs no loop body, all three flags stay 0, exit 0 — exactly what the failed greps did; `2>/dev/null` sits BEFORE `<` so the open failure stays silent.)

(e) Lines 100–112 (dedup + stamp + prune) — forks 1A + 1C. Replace:

```bash
latest=$(ls -1t "${OBS}".*.bak 2>/dev/null | head -n 1)
if [ -n "$latest" ] && cmp -s "$OBS" "$latest"; then exit 0; fi

stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null) || exit 0
```
…and the `ls -1t | tail | while rm` prune, with:

```bash
# ONE listing, BEFORE the copy, serving BOTH consumers (fork 1C, owner-ruled 2026-10-07): its first
# entry is the dedup comparand, and - because the snapshot written below is strictly newest - the
# prune's surplus is exactly this OLD list from index KEEP-1 on. mtime order is kept deliberately
# (1B name-order was rejected: a hand-copied .bak or a moved clock would change which slot dies).
# bash-3-safe array fill: no mapfile.
baks=()
while IFS= read -r _b; do [ -n "$_b" ] && baks+=("$_b"); done < <(ls -1t "${OBS}".*.bak 2>/dev/null)
if [ "${#baks[@]}" -gt 0 ] && cmp -s "$OBS" "${baks[0]}"; then exit 0; fi

if [ -z "${CLAVITY_HOOK_BASH3:-}" ] && ((BASH_VERSINFO[0]*100+BASH_VERSINFO[1] >= 402)); then
  printf -v stamp '%(%Y%m%d-%H%M%S)T' -1 2>/dev/null
else
  stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null)
fi
[ -n "$stamp" ] || exit 0
if ! cp "$OBS" "${OBS}.${stamp}.bak" 2>/dev/null; then
  printf '%s\n' "[AGY-INBOX-SNAPSHOT] could not write ${OBS}.${stamp}.bak - the drain will run UNPROTECTED" >&2
  exit 0
fi

# FIFO prune, ONE rm for every surplus slot (fork 1A): after the cp there are ${#baks[@]}+1 slots;
# keep the newest $KEEP. 16 per-file rm processes (32 spawns) could never fit the 16-process ceiling.
if [ "${#baks[@]}" -ge "$KEEP" ]; then
  rm -f -- "${baks[@]:$((KEEP - 1))}" 2>/dev/null
fi

exit 0
```

Arithmetic check the executor should re-derive, not trust: 20 old + 1 new = 21, KEEP=5 ⇒ delete 16 = old indices 4..19 = `${baks[@]:4}` ✓; 5 old ⇒ delete `${baks[@]:4}` = 1 ✓; fewer than KEEP old ⇒ no rm ✓.

- [ ] **Step 4: Budget rows green.** Re-run the Step-2 command. Expected: `Tests Passed:` with Failed: 0 among the inbox-snapshot rows (both the `row` and auto-generated `compat` variants; compat forces `CLAVITY_HOOK_BASH3=1`, where the only divergence is `date` instead of `%()T` — output stays empty, `-Verify` passes on both).

- [ ] **Step 5: Behaviour rows in `scripts/tests/agy-inbox-snapshot.Tests.ps1`.** The suite's `$script:Hook` already points at the hook and its BeforeAll builds isolated HOME fixtures — add three `It` rows using the suite's existing payload/fixture helpers (open the file first; if its helper names differ from what a row needs, adapt the row to the suite's own helpers rather than importing new ones):

```powershell
    It 'prunes with AGY_INBOX_SNAPSHOT_KEEP=08 (base-10, not octal) and keeps the newest 8' {
        # Control before the fix: $((KEEP + 1)) aborted "value too great for base", the prune never ran.
        # 10 old baks + 1 new = 11, KEEP=8 -> the 3 OLDEST die.
        # (Build: inbox + 10 baks with ascending mtimes, env AGY_INBOX_SNAPSHOT_KEEP='08', curate Skill payload.)
        $r = <invoke the hook with the suite's runner, -Env @{ AGY_INBOX_SNAPSHOT_KEEP = '08' }>
        $r.StdErr | Should -BeNullOrEmpty
        <bak listing>.Count | Should -Be 8
        foreach ($gone in 1..3) { <bak listing> -match ('202601{0:d2}' -f $gone) | Should -BeNullOrEmpty }
    }
    It 'opens the Pending region on a REAL-tab heading ("##<TAB>Pending") and snapshots' {
        # The heading written with an actual TAB between ## and Pending; one pending bullet; expect 1 new .bak.
    }
    It 'does NOT open the region on "##tPending" (the literal t that grep''s [ \t] class wrongly matched)' {
        # Same fixture with the heading '##tPending'; expect 0 .bak files (net behaviour preserved:
        # the old awk refused this file too - the fix makes the two readers agree, it does not change the net).
    }
```

Fill the `<...>` with the suite's own helper calls — the assertions above are the contract; the helpers are whatever the file already uses (STATE-VERIFICATION applies: open the suite before writing).

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/agy-inbox-snapshot.Tests.ps1 -Output Detailed -CI"`
Expected: all green (the pre-existing ~32 rows prove behaviour preservation; the 3 new rows prove the folds).

- [ ] **Step 6: Mutants (each must turn its named row red, then restore):**
1. `KEEP=$((10#$KEEP))` → `KEEP=$((KEEP))` ⇒ the KEEP=08 row red.
2. In `re_pending`, the real tab class `[ \t]` → `[ t]` (literal t) ⇒ the real-tab row red AND the `##tPending` row red.
3. `${baks[@]:$((KEEP - 1))}` → `${baks[@]:$KEEP}` (off-by-one keeps one extra) ⇒ the 20-baks budget row's `-Verify` red (count 6).
4. Delete the `cmp -s` dedup line ⇒ the dedup budget row's `-Verify` red (count 2).
After each: restore, re-run the touched suite green, `git status --short` clean of surprises.

- [ ] **Step 7: Remove the `agy-inbox-snapshot.sh` entry from `$script:B21Debt`** in `hook-spawn-budget.Rows.ps1` (the line `@{ Hook = 'agy-inbox-snapshot.sh'; ... Total = 67 }`). Re-run the Step-2 command: the debt row still fails locally (7 entries left) — that is expected until Task 12; the inbox-snapshot rows are green.

- [ ] **Step 8: `_partition.md`:** update the `agy-inbox-snapshot.Tests.ps1` row (`32 tests` today) and the `hook-spawn-budget.Tests.ps1` row (`109 tests` today) to the tallies the Step-4/Step-5 runs printed, each with the dated note.

- [ ] **Step 9: Commit:**

```bash
git add agy-autotrain/hooks/agy-inbox-snapshot.sh scripts/tests/agy-inbox-snapshot.Tests.ps1 scripts/tests/hook-spawn-budget.Rows.ps1 scripts/tests/_partition.md
git commit -m "perf(hooks): agy-inbox-snapshot under the 16-process ceiling (fork 1A+1C; KEEP base-10; tab heading class)"
```

### Task 2: `agy-shield-lib.sh` (2A+2B + glob-gated finds) and `agy-discipline-reaching.sh`

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-shield-lib.sh` (lines 47, 88–95, 111, 124–128, 217–231 NOT touched (§41), 364–394, 396–457 as of `6a6224ce`) + byte-identical copy to `clavity-classic/plugin/hooks/agy-shield-lib.sh`
- Modify: `clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh` (lines 120–121, 130) + classic copy
- Modify: `scripts/tests/hook-spawn-budget.Rows.ps1` (helper + 6 rows; remove the `agy-discipline-reaching.sh` `$B21Debt` entry)
- Modify: `scripts/tests/agy-shield-lib.Tests.ps1` (2 new rows)
- Modify: `scripts/tests/_partition.md`

**Why the find-gating reserve (2D) activates — the arithmetic.** On the recurring `!`-negation path, after 2A+2B the spawns are: boot 3 + prepend (`mktemp`+`cat`+`mv`, §41-protected) 6 + `check-ignore -q` 2 + `ls-files` 2 + `check-ignore -v` 2 = 15, PLUS the sweep-latch `find` (2, per NEW session key) and the `_agy_shield_say` `find` (2, first marker per class+key) = 19. Over. The owner-sanctioned reserve therefore activates as a BUILTIN GLOB gate: each `find` runs only when the glob shows a candidate besides the files this very run just created. On a fresh fixture (and any healthy repo) both finds are skipped → 15; a repo carrying genuinely stale temps pays +2 once and is then clean again.

- [ ] **Step 1: Budget rows (failing control).** In `hook-spawn-budget.Rows.ps1` add, next to `Add-FxInbox`:

```powershell
function Set-FxShield {
    # $Text = $null -> .clavity exists with NO .gitignore; otherwise the shield holds exactly $Text.
    param($Fx, $Text)
    $d = Join-Path $Fx.Repo '.clavity'; New-Item -ItemType Directory -Force -Path $d | Out-Null
    if ($null -ne $Text) { [IO.File]::WriteAllText((Join-Path $d '.gitignore'), $Text) }
}
```

and these rows (the hook needs a git repo — the default fixture IS one — plus `.clavity/`, which `Set-FxShield` creates; payload = `New-SessionStartPayload $fx`, whose session_id is `s1`). All six are `-Silent` + `-Verify` deliberately: every message on these paths goes to STDERR, and the PP1 fold made `-Expect` parse STDOUT as a JSON envelope, so stdout must be empty and the row's proof is the file effect:

```powershell
    # --- agy-discipline-reaching.sh + the shared agy-shield-lib.sh: the Branch 21 census paths ---
    New-BudgetRow "$D/agy-discipline-reaching.sh" 'normal FIRST session (shield ok, sweep latch, row written)' {
        param($fx) Set-FxShield $fx "*`n"; New-SessionStartPayload $fx } -Silent -Verify {
        param($fx) (Join-Path $fx.Repo '.clavity/discipline-reaching.jsonl') | Should -Exist }
    New-BudgetRow "$D/agy-discipline-reaching.sh" 'shield file MISSING -> created with *' {
        param($fx) Set-FxShield $fx $null; New-SessionStartPayload $fx } -Silent -Verify {
        param($fx) (Get-Content -LiteralPath (Join-Path $fx.Repo '.clavity/.gitignore') -Raw) | Should -Match '\*' }
    New-BudgetRow "$D/agy-discipline-reaching.sh" 'shield lacks * -> appended' {
        param($fx) Set-FxShield $fx "foo.txt`n"; New-SessionStartPayload $fx } -Silent -Verify {
        param($fx) @(Get-Content -LiteralPath (Join-Path $fx.Repo '.clavity/.gitignore')) -contains '*' | Should -BeTrue }
    New-BudgetRow "$D/agy-discipline-reaching.sh" 'shield has a ! negation -> PREPEND, first session' {
        param($fx) Set-FxShield $fx "!discipline-reaching.jsonl`n"; New-SessionStartPayload $fx } -Silent -Verify {
        param($fx) $s = @(Get-Content -LiteralPath (Join-Path $fx.Repo '.clavity/.gitignore'))
        $s[0] | Should -BeExactly '*'; $s[1] | Should -BeExactly '!discipline-reaching.jsonl' }
    New-BudgetRow "$D/agy-discipline-reaching.sh" 'shield has a ! negation, REPEAT session (swept marker present)' {
        param($fx) Set-FxShield $fx "!discipline-reaching.jsonl`n"
        New-Item -ItemType File -Path (Join-Path $fx.Repo '.clavity/.clavity-shield-swept-s1') | Out-Null
        New-SessionStartPayload $fx } -Silent -Verify {
        param($fx) (Get-Content -LiteralPath (Join-Path $fx.Repo '.clavity/.gitignore'))[0] | Should -BeExactly '*' }
    New-BudgetRow "$D/agy-discipline-reaching.sh" 'jsonl TRACKED by git -> persistent message, marker written' {
        param($fx) Set-FxShield $fx "*`n"
        [IO.File]::WriteAllText((Join-Path $fx.Repo '.clavity/discipline-reaching.jsonl'), "{}`n")
        Invoke-FxGit $fx @('add', '-f', '.clavity/discipline-reaching.jsonl')
        New-SessionStartPayload $fx } -Silent -Verify {
        param($fx) (Join-Path $fx.Repo '.clavity/.clavity-shield-persistent-s1') | Should -Exist }
```

Run with `HSB_HOOK='agy-discipline-reaching.sh'`. Expected: the negation rows and the tracked row FAIL on count (census 36/34/20 vs 16), the rest pass — the failing control.

- [ ] **Step 2: Rewrite `agy-shield-lib.sh`** (dotnet copy first; classic is a byte-copy in Step 6). The file is SOURCED by bash hooks only (`agy-discipline-reaching.sh`, `agy-mark.sh` under `set -u`, `agy-ledger-lib.sh`, the open-issues snippet) — bash-3.2-safe bashisms are legal; update the line-74 "POSIX sh" aside where it conflicts. Six edits:

(a) Line 47: `_AS_CR=$(printf '\r')` → `_AS_CR=$'\r'` (ANSI-C quoting, bash ≥ 2.0; kills one subshell). Keep the trailing comment.

(b) Lines 88–95, `_agy_shield_markerdir`: return via a GLOBAL instead of stdout, so callers stop paying a `$( )` subshell:

```bash
_agy_shield_markerdir() {
    _asm_root=${1:-}
    _asm_dir=''
    if [ -n "$_asm_root" ] && [ -d "$_asm_root/.clavity" ] && [ -w "$_asm_root/.clavity" ]; then
        _asm_dir="$_asm_root/.clavity"
    fi
}
```

Caller at line 111: `_ass_dir=$(_agy_shield_markerdir "$_ass_root")` → `_agy_shield_markerdir "$_ass_root"; _ass_dir=$_asm_dir`. Caller at line 364: `_as_swdir=$(_agy_shield_markerdir "$_as_root")` → `_agy_shield_markerdir "$_as_root"; _as_swdir=$_asm_dir`. (No `local` exists in this file; `_asm_dir` is one more file-scoped global, matching every other helper here.)

(c) Lines 124–128, the `_agy_shield_say` prune — glob-gate it (2D). Replace the bare `find` with:

```bash
    # GATED BY A BUILTIN GLOB (Branch 21, owner reserve 2D): the prune pays its 2 processes only when a
    # candidate exists BESIDES the marker this call just created and a sweep marker this same RUN just
    # latched (_as_swept_now / _as_sweep are the sweep gate's globals; unset on the validation paths that
    # reach here before agy_shield's sweep block, when the [ ] tests are simply false). An unmatched glob
    # stays a literal string and [ -e ] rejects it - no nullglob needed.
    _ass_stale=0
    for _ass_f in "$_ass_dir"/.clavity-shield-*; do
        [ "$_ass_f" = "$_ass_marker" ] && continue
        [ "${_as_swept_now:-}" = 1 ] && [ "$_ass_f" = "${_as_sweep:-}" ] && continue
        [ -e "$_ass_f" ] && { _ass_stale=1; break; }
    done
    [ "$_ass_stale" -eq 1 ] && find "$_ass_dir" -maxdepth 1 -name '.clavity-shield-*' -mtime +30 -delete 2>/dev/null
```

(d) Stage A2's three `grep` probes (line 193 and 195) → one builtin read + pattern tests. Replace:

```bash
    if grep -qFx '*' "$_as_shield" 2>/dev/null || grep -qFx "*$_AS_CR" "$_as_shield" 2>/dev/null; then
        :                                       # a bare * is present: append nothing.
    elif [ -f "$_as_shield" ] && grep -q '^!' "$_as_shield" 2>/dev/null; then
```

with:

```bash
    # ONE builtin read replaces the three grep probes (Branch 21, fork 2A). The grouped redirect keeps
    # the three-state contract the greps carried: open FAILS (missing or ACL-unreadable - the [ -r ]
    # builtin lies about Windows ACLs, so the OPEN is the oracle) -> _as_readable=0, and both tests
    # below fall through to the same branches a grep exit of 2 took. read -d '' returns non-zero at
    # EOF while having filled the variable, hence the `|| :` inside the group. Wrapping the content in
    # newlines makes "a LINE equal to *" one substring test, first and last lines included.
    _as_c=''; _as_readable=0
    if { IFS= read -r -d '' _as_c || :; } 2>/dev/null < "$_as_shield"; then _as_readable=1; fi
    _as_w=$'\n'${_as_c}$'\n'
    if [ "$_as_readable" -eq 1 ] && { [[ $_as_w == *$'\n*\n'* ]] || [[ $_as_w == *$'\n*'"$_AS_CR"$'\n'* ]]; }; then
        :                                       # a bare * is present: append nothing.
    elif [ -f "$_as_shield" ] && [ "$_as_readable" -eq 1 ] && [[ $_as_w == *$'\n!'* ]]; then
```

Everything inside the two branches — including the whole `mktemp`/`cat`/`mv` prepend at 217–231 and both append branches — stays byte-identical (§41: the prepend is owner-deferred; a failing control must exist before anyone touches it).

(e) The sweep block (lines 364–394): adopt the globals + glob gate. Replace the block from `_as_swdir=$(...)` through the gated `find` with:

```bash
    _agy_shield_markerdir "$_as_root"; _as_swdir=$_asm_dir
    _as_swept_now=0
    if [ -z "$_as_swdir" ]; then
        printf 'agy-shield: sweep gate disabled - "%s" is not a writable directory. Stale .gitignore.tmp.* files will accumulate.\n' "$_as_root/.clavity" >&2
    else
        _as_sweep="$_as_swdir/.clavity-shield-swept-${_as_key:-nosession}"
        if [ -f "$_as_sweep" ]; then
            :   # already swept for this key - the gate doing its job, and NOT a failure to report.
        elif : 2>/dev/null > "$_as_sweep"; then
            _as_swept_now=1
            # (comment block 372–386 kept verbatim)
            # GATED BY A BUILTIN GLOB (Branch 21, reserve 2D): on a healthy repository the only matches
            # are the marker files this very run created, and the find's 2 processes would push the
            # recurring !-negation path to 19 of 16 (measured arithmetic in the plan). Skip it unless a
            # candidate OTHER than this run's own sweep marker exists; a stale-temp repo pays +2 once.
            _as_stale=0
            for _as_f in "$_as_dir"/.gitignore.tmp.* "$_as_dir"/.clavity-shield-*; do
                [ "$_as_f" = "$_as_sweep" ] && continue
                [ -e "$_as_f" ] && { _as_stale=1; break; }
            done
            [ "$_as_stale" -eq 1 ] && find "$_as_dir" -maxdepth 1 \( -name '.gitignore.tmp.*' -o -name '.clavity-shield-*' \) -mtime +30 -delete 2>/dev/null
        else
            printf 'agy-shield: sweep gate could not latch at "%s" - stale .gitignore.tmp.* files will accumulate.\n' "$_as_sweep" >&2
        fi
    fi
```

(f) Stage B (lines 396–457) — fork 2B, check-ignore first. Replace lines 400–403 and the B4 tail (451–457) so the block reads:

```bash
    # ---------------------------------------------------------------- Stage B: verify the EFFECT.
    # check-ignore FIRST (Branch 21, owner fork 2B): on every healthy call it answers alone, and the
    # rev-parse probe runs ONLY when it could not (rc neither 0 nor 1) - to tell "not a work tree"
    # (NORMAL, SILENT - B1) from a real git failure inside one (B4). MEASURED 2026-10-07: outside a
    # repo check-ignore exits 128 with `fatal:` on stderr - already suppressed by the 2>/dev/null this
    # line has carried all along - and inside one it exits 0 (ignored) or 1 (not). No path's ANSWER
    # changes; the only delta is one fewer git process on every rc-0/rc-1 call.
    git -C "$_as_root" check-ignore -q -- "$_as_rel" 2>/dev/null
    _as_ci=$?

    if [ "$_as_ci" -eq 0 ]; then
        return 0                                # B2: ignored. Done. SILENT.
    fi

    if [ "$_as_ci" -ne 1 ]; then
        # B1/B4, split AFTER the probe instead of before it.
        git -C "$_as_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
        _agy_shield_say environment "$_as_key" \
            "git check-ignore failed (exit $_as_ci) inside a work tree; the shield text was asserted but its effect could not be verified for $_as_rel" "$_as_root"
        return 0
    fi

    # B3 (rc == 1): the block at 409–449 stays byte-identical EXCEPT the -v probe loses its `head`:
```

and inside B3, line 429: `_as_why=$(git -C "$_as_root" check-ignore -v -- "$_as_rel" 2>/dev/null | head -n 1)` →

```bash
            _as_why=$(git -C "$_as_root" check-ignore -v -- "$_as_rel" 2>/dev/null)
            _as_why=${_as_why%%$'\n'*}          # first line, builtin - no head process
```

(A missing git binary still exits silently: bash's command-not-found for `check-ignore` lands on the redirected stderr, rc=127 ≠ 1, the rev-parse probe also fails, return 0 — same as today.)

- [ ] **Step 3: `agy-discipline-reaching.sh`, two edits** (+ classic copy in Step 6):

(a) Line 130: `. "$(dirname "$0")/agy-shield-lib.sh" 2>/dev/null || true` →

```bash
# Builtin dirname (Branch 21): ${0%[/\\]*} handles both separators Windows bash can hand us; a $0 with
# no separator at all leaves the string unchanged, hence the `.` fallback (the D1 idiom, Branch 20).
_dr_src=${0%[/\\]*}
[ "$_dr_src" = "$0" ] && _dr_src=.
. "$_dr_src/agy-shield-lib.sh" 2>/dev/null || true
```

(b) Lines 120–121 (inventory defect 3 — `%()T` with no gate; this hook must still work on macOS bash 3.2):

```bash
# printf's %()T is a bash >= 4.2 builtin - gate it (Branch 21; macOS /bin/bash is 3.2, where an
# ungated call leaves ts EMPTY and the row's timestamp field silently lies). TZ=UTC is exported above.
if [ -z "${CLAVITY_HOOK_BASH3:-}" ] && ((BASH_VERSINFO[0]*100+BASH_VERSINFO[1] >= 402)); then
  printf -v ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1
else
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
fi
```

- [ ] **Step 4: Budget rows green.** Re-run the Step-1 command (`HSB_HOOK='agy-discipline-reaching.sh'`). Expected: Failed: 0 (compat rows included — the bash3 path's only divergence is the `date` fallback, whose 2 extra processes still fit: 15 + 2 = 17 is NOT paid because the fallback replaces nothing on the negation path's count path… verify by the run, and if the compat negation row exceeds Max, raise ONLY that row's `-Max` to 15 with a comment naming the `date` fallback as the cause — the compat row asserts equal OUTPUT, the count ceiling stays 13 beyond boot for the primary row).

- [ ] **Step 5: Shield-lib behaviour rows** in `scripts/tests/agy-shield-lib.Tests.ps1` (open the file; use its `New-FixtureRepo` + existing invoke pattern — the suite drives `agy_shield` through its own shim; add rows with that shim):

```powershell
    It 'still sweeps a genuinely stale temp through the glob gate (Branch 21: gated find, not a dead find)' {
        # Fixture: repo + .clavity + shield '!x' (the prepend path, where the sweep latches), PLUS a
        # planted .gitignore.tmp.OLDOLD whose LastWriteTimeUtc is 40 days ago. After one agy_shield
        # call: the stale temp is GONE (the find ran), the fresh sweep marker SURVIVES.
    }
    It 'stays SILENT outside a work tree after the check-ignore-first reorder (B1)' {
        # Fixture: a plain directory (no .git) + .clavity. agy_shield exits 0, stdout AND stderr empty.
    }
```

Assertions as stated; fixture mechanics follow the suite's own helpers. Run the suite (SLOW — background it; `Invoke-Pester scripts/tests/agy-shield-lib.Tests.ps1 -Output Detailed -CI`). Expected: all 45 existing rows + 2 new green — the 45 are the behaviour-preservation proof for 2A/2B.

- [ ] **Step 6: Mirror + mutants.**

```bash
cp clavity-dotnet/plugin/hooks/agy-shield-lib.sh clavity-classic/plugin/hooks/agy-shield-lib.sh
cp clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh clavity-classic/plugin/hooks/agy-discipline-reaching.sh
bash scripts/check-seed-artifacts-synced.sh   # expect exit 0
```

Mutants (applied to BOTH mirror copies at once, suites re-run, then restored):
1. In the sweep gate, delete the line `_as_stale=1; break; }` body's assignment (make the loop never set it) ⇒ the planted-stale-temp row red.
2. In Stage B, change `if [ "$_as_ci" -ne 1 ]` → `-ne 0` ⇒ the outside-work-tree row red (B3 unreachable, tracked-jsonl budget row's `-Verify` red too).
3. In `_agy_shield_say`'s gate, drop the `[ "$_ass_f" = "$_ass_marker" ] && continue` exclusion ⇒ the negation-REPEAT budget row red on count (find runs every call).
4. In the A2 read, change `_as_w=$'\n'${_as_c}$'\n'` → `_as_w=${_as_c}` ⇒ existing shield rows red (first-line `*` no longer matches).

- [ ] **Step 7: Remove the `agy-discipline-reaching.sh` entry from `$B21Debt`;** update `_partition.md` rows for `agy-shield-lib.Tests.ps1` (45 today) and `hook-spawn-budget.Tests.ps1` from the printed tallies.

- [ ] **Step 8: Commit:**

```bash
git add clavity-dotnet/plugin/hooks/agy-shield-lib.sh clavity-classic/plugin/hooks/agy-shield-lib.sh clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh clavity-classic/plugin/hooks/agy-discipline-reaching.sh scripts/tests/agy-shield-lib.Tests.ps1 scripts/tests/hook-spawn-budget.Rows.ps1 scripts/tests/_partition.md
git commit -m "perf(hooks): agy-shield-lib + discipline-reaching under the ceiling (fork 2A+2B, glob-gated finds; %()T gated)"
```

### Task 3: Phase-1 measurement + the phase-1 AGY-CAPSTONE round (owner-ruled)

**Files:** none in the repo (scratch + seams only; `.clavity/` is never committed).

- [ ] **Step 1: Re-measure every census path of both phase-1 hooks** with the census runner (`-Filter '^(agy-inbox-snapshot|agy-discipline-reaching)\|'`, `-Out .clavity/scratch/b21-measure/after-phase1.jsonl`). Expected: EVERY row ≤ 16, r1 == r2. Any row over: return to the owning task; the glob-gate reserve and, only with a new owner ruling, further measures.
- [ ] **Step 2: Run the two behaviour suites + the budget suite once more, sequentially** (never two at once): `agy-inbox-snapshot.Tests.ps1`, `agy-shield-lib.Tests.ps1`, then `hook-spawn-budget.Tests.ps1` un-filtered (expected: only the `carries no Branch 21 debt` row red — 6 entries remain).
- [ ] **Step 3: Phase-1 capstone round** (the driver, not a subagent, per the owner's two-phase ruling): invoke the `agy-capstone` skill over the two phase-1 commits (range `6a6224ce..HEAD`), seam `.clavity/seams/capstone-branch21-phase1.md`, full safety envelope. Fold/reject per the discipline; commit any folds; do NOT write a completion marker (the branch-final capstone owns that). Phase 2 starts only after this round is clean or its findings are dispositioned.

---

# PHASE 2 — the six fork-free hooks and the folds

### Task 4: `agy-anomaly-reminder.sh` — the jq path goes builtin

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh` (lines 87–97, 157–181 as of `6a6224ce`) + classic copy
- Modify: `scripts/tests/hook-spawn-budget.Rows.ps1` (2 rows; remove the `agy-anomaly-reminder.sh` `$B21Debt` entry)
- Modify: `scripts/tests/agy-anomaly-reminder.Tests.ps1` (1 new row)
- Modify: `scripts/tests/_partition.md`

- [ ] **Step 1: Budget rows (failing control; the hook EMITS on these paths, and its envelope carries both `systemMessage` and `hookSpecificOutput`, so `-Expect` works under the PP1 JSON check).** The suite's existing single row stays; add:

```powershell
    New-BudgetRow "$D/agy-anomaly-reminder.sh" '3 untriaged with dates -> EMIT the oldest' {
        param($fx)
        $d = Join-Path $fx.Repo '.clavity'; New-Item -ItemType Directory -Force -Path $d | Out-Null
        @('# Untriaged anomalies (local, never committed)', '',
          '- [defect] a * src/a.rs:1 * 2026-09-01 * task=x',
          '- [tool] b * n/a * 2026-08-15 * task=y',
          '- [process] c * n/a * 2026-09-20 * task=z') | Set-Content -LiteralPath (Join-Path $d 'local-anomalies.md')
        New-SessionStartPayload $fx } -Expect '3 untriaged (oldest 2026-08-15)'
    New-BudgetRow "$D/agy-anomaly-reminder.sh" '50 untriaged (scaling: the count loop is builtin)' {
        param($fx)
        $d = Join-Path $fx.Repo '.clavity'; New-Item -ItemType Directory -Force -Path $d | Out-Null
        $lines = @('# Untriaged anomalies (local, never committed)', '') + (1..50 | ForEach-Object { "- [defect] n$_ * n/a * 2026-09-0$(1 + ($_ % 8)) * task=t" })
        $lines | Set-Content -LiteralPath (Join-Path $d 'local-anomalies.md')
        New-SessionStartPayload $fx } -Expect '50 untriaged'
```

Run with `HSB_HOOK='agy-anomaly-reminder.sh'`. Expected: both FAIL on count (census: 23 vs 16).

- [ ] **Step 2: Rewrite the two regions.**

(a) Lines 87–97 (cwd via jq) — raw-regex with a jq FALLBACK for payloads the raw read cannot decode. Replace lines 87–94 (`cwd=$(printf ... jq ...)` through `[ -z "$cwd_path" ] && cwd_path="."`) with:

```bash
# Raw-regex cwd first (Branch 21): the SessionStart payload's top-level fields carry no user content,
# so the raw match cannot be spoofed (JSON escaping breaks a smuggled key - Branch 20, measured). The
# raw value keeps JSON escaping: collapse the doubled backslashes; and if stripping every \\ pair
# still leaves a lone backslash, the value carries an escape this read cannot decode (\uXXXX, \t...)
# - pay the jq call for that rare payload rather than resolving a wrong path silently.
cwd=''
[[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && cwd=${BASH_REMATCH[1]}
_ar_probe=${cwd//\\\\/}
if [[ $_ar_probe == *\\* ]]; then
  cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)
  cwd_path=${cwd//\\//}
else
  cwd_path=${cwd//\\\\//}
fi
[ -z "$cwd_path" ] && cwd_path="."
```

(Line 97's file-as-cwd resolution and everything after stay untouched. NOTE the two normalization spellings — the comment at the old lines 88–92 explains why they must differ; keep that comment, adapted.)

(b) Lines 157–181 (`grep -c`, then `grep | awk | grep -oE | sort | head`) — one builtin pass. Replace from `n=$(grep -c ...)` through `[ -n "$oldest" ] && oldest=" (oldest $oldest)"` with:

```bash
# Present-but-unreadable is NOT "no anomalies" - probe by OPENING the file (the open consults Windows
# ACLs; the -r builtin does not - same oracle class as the grep exit code this replaces).
if ! { :; } 2>/dev/null < "$f"; then
  msg="[AGY-ANOMALIES] $f exists but cannot be read - untriaged anomalies NOT counted"
  jq -nc --arg m "$msg" '{systemMessage:$m,hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
  exit 0
fi

# ONE builtin pass: count the entries and track the oldest capture date. An ENTRY is a bullet whose
# first token is ANY bracketed word (see the retained comment above). The date is the field BEFORE the
# first `task=` field, fields split on ' * ' - the awk this replaces anchored on task= for the same
# measured reasons (a date inside the prose, a ' * ' inside the fact or the task).
n=0; oldest=''
re_entry='^- \[[^]]*\]'
re_date='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
while IFS= read -r line || [ -n "$line" ]; do
  [[ $line =~ $re_entry ]] || continue
  n=$((n + 1))
  rest=$line; prev=''; d=''
  while :; do
    case "$rest" in
      *' * '*) field=${rest%%' * '*}; rest=${rest#*' * '} ;;
      *)       field=$rest;           rest='' ;;
    esac
    case "$field" in task=*) d=$prev; break ;; esac
    prev=$field
    [ -z "$rest" ] && break
  done
  if [[ $d =~ $re_date ]]; then
    if [ -z "$oldest" ] || [[ $d < $oldest ]]; then oldest=$d; fi
  fi
done 2>/dev/null < "$f"
[ "$n" -eq 0 ] && exit 0
[ -n "$oldest" ] && oldest=" (oldest $oldest)"
```

(The final `msg=` + `jq -nc` emission at 188–189 stays — jq owns the escaping for `$f`, a real path.)

- [ ] **Step 3: Budget rows green** (re-run Step 1; also the auto compat rows — output on the bash3 path is byte-identical because nothing here is version-gated).

- [ ] **Step 4: Behaviour row** in `scripts/tests/agy-anomaly-reminder.Tests.ps1` (use its `New-RepoWithAnomaly` / `New-CleanHome` helpers — open the file first):

```powershell
    It 'resolves a cwd carrying a \u escape through the jq fallback and still counts' {
        # Fixture: a repo whose directory name contains a non-ASCII char (e.g. "ano-é"); the payload's
        # cwd is JSON-encoded by ConvertTo-Json, which emits \u00e9 - the raw regex alone cannot decode
        # it. Expect: stdout envelope carrying "1 untriaged" (the jq fallback resolved the real path).
    }
```

Mutant: delete the `if [[ $_ar_probe == *\\* ]]` fallback branch (always take the raw arm) ⇒ this row red. Second mutant: `d=$prev` → `d=$field` ⇒ the `3 untriaged` budget row's `-Expect` red (oldest wrong). Restore both.

- [ ] **Step 5: Mirror, debt, partition, commit.**

```bash
cp clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh clavity-classic/plugin/hooks/agy-anomaly-reminder.sh
bash scripts/check-seed-artifacts-synced.sh
git add clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh clavity-classic/plugin/hooks/agy-anomaly-reminder.sh scripts/tests/agy-anomaly-reminder.Tests.ps1 scripts/tests/hook-spawn-budget.Rows.ps1 scripts/tests/_partition.md
git commit -m "perf(hooks): agy-anomaly-reminder jq path goes builtin (raw cwd + one-pass count/oldest)"
```
(Remove the `agy-anomaly-reminder.sh` `$B21Debt` entry in this same commit; update the two `_partition.md` rows from the printed tallies.)

### Task 5: `assertion-strength-reminder.sh` — builtins + §59 + §72 + `%()T` gates

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh` (lines 15, 30, 35–37, 53–54, 101–107, 125) + classic copy
- Modify: `scripts/tests/hook-spawn-budget.Rows.ps1` (3 rows; remove its `$B21Debt` entry)
- Modify: `scripts/tests/assertion-strength-reminder.Tests.ps1` (3 new rows)
- Modify: `scripts/tests/_partition.md`, and in Task 12 the ROADMAP §72 note

- [ ] **Step 1: Budget rows (failing control).** Existing single row stays; add:

```powershell
    New-BudgetRow "$D/assertion-strength-reminder.sh" 'test file, FIRST touch of the session -> marker + prune + emit' {
        param($fx) New-ToolPayload $fx 'Write' @{ file_path = ($fx.RepoFwd + '/scripts/tests/x.Tests.ps1'); content = 'x' } } -Expect 'ASSERTION-STRENGTH'
    New-BudgetRow "$D/assertion-strength-reminder.sh" 'TMPDIR unusable -> HOME/.clavity-tmp fallback still emits' {
        param($fx)
        [IO.File]::WriteAllText((Join-Path $fx.Root 'blockfile'), 'x')
        $fx.Env.TMPDIR = (($fx.Root -replace '\\', '/') + '/blockfile/sub')   # parent is a FILE: unusable
        New-ToolPayload $fx 'Write' @{ file_path = ($fx.RepoFwd + '/scripts/tests/x.Tests.ps1'); content = 'x' } } -Expect 'ASSERTION-STRENGTH'
    New-BudgetRow "$D/assertion-strength-reminder.sh" 'non-test file (the hottest path, silent)' {
        param($fx) New-ToolPayload $fx 'Write' @{ file_path = ($fx.RepoFwd + '/src/a.cs'); content = 'x' } } -Silent
```

Run with `HSB_HOOK='assertion-strength-reminder.sh'`. Expected: the two emit rows FAIL on count (census 17/21 vs 16).

- [ ] **Step 2: Six edits to the hook.**

(a) Line 15: `input=$(cat)` → `IFS= read -r -d '' input` (§59: under an empty PATH, `cat`'s not-found noise was the measured stderr leak; the builtin is silent).

(b) Line 30 (the degraded-path `printf | grep -Eq`) → the same ERE via `[[ =~ ]]` (kills the second measured stderr leak AND 3 processes):

```bash
  re_dg='"(file_path|path)"[[:space:]]*:[[:space:]]*"[^"]*([./\\][Tt]ests\.ps1|[Tt]ests\.cs|[Tt]est\.cs|_test\.(py|rs)|[./\\]test_[^"\\/]*\.(py|rs))"'
  if [[ $input =~ $re_dg ]]; then
```

(The pattern text is byte-identical to the grep's; only the engine moved. The 'degraded predicate agrees with the primary predicate' row pins the equivalence.)

(c) Lines 35–37 and 101–107 (`printf -v ... 'day%(%Y%m%d)T'` — inventory defect 3): wrap BOTH sites:

```bash
    if [ -z "${CLAVITY_HOOK_BASH3:-}" ] && ((BASH_VERSINFO[0]*100+BASH_VERSINFO[1] >= 402)); then
      printf -v dsid 'day%(%Y%m%d)T' -1
    else
      dsid="day$(date +%Y%m%d 2>/dev/null)"
    fi
```
(and identically for `sid` at 103–108, keeping each site's surrounding comment).

(d) Lines 53–54 (two jq calls) → ONE, the Branch-20 `\u0001`-join idiom (a raw regex is NOT safe here — a Write payload's `content` field is user text that can legally contain `"file_path":"..."`, so the extraction must stay scoped to `.tool_input`, which only jq can do):

```bash
out=$(jq -j '(.tool_input.file_path // .tool_input.path // ""), "\u0001", (.cwd // ".")' <<<"$input" 2>/dev/null)
fp=${out%%$'\001'*}
cwd=${out#*$'\001'}
[ -z "$fp" ] && exit 0
```

(e) Line 125 (the create-path `find`) — §72's new home, zero added processes:

```bash
    # -mtime +30, NOT +7 (see the retained comment above) - and since Branch 21 the glob also sweeps
    # the test-audit reminder's per-session debounce files (ROADMAP section 72): agy-test-audit-reminder.sh
    # keeps one HEAD sha per session at ${TMPDIR:-/tmp}/claude-agy-test-audit-reminder.<sid>, and only a
    # PreCompact in that SAME session deletes it, so every session that ends without compacting leaks one.
    # This find already runs at most once per session, on the path that just proved the directory
    # writable - widening its -name group costs ZERO processes, and a >30-day-old debounce belongs to a
    # dead session (deleting it merely re-arms a reminder that session can no longer receive).
    find "$_cand" -maxdepth 1 \( -name '.clavity-assert-*' -o -name 'claude-agy-test-audit-reminder.*' \) -mtime +30 -delete 2>/dev/null
```

- [ ] **Step 3: Budget + compat rows green** (re-run Step 1; the compat emit rows' only divergence is the `date` fallback — same output text).

- [ ] **Step 4: Three behaviour rows** in `scripts/tests/assertion-strength-reminder.Tests.ps1` (helpers: `New-Payload`, `New-IsolatedHome` — open the file first):

```powershell
    It 'writes NOTHING to stderr under an empty PATH (section 59), on both a test and a non-test payload' {
        # Invoke with -Env @{ PATH = '' } twice: payload file_path 'src/x.Tests.ps1' and 'src/a.cs'.
        # Both runs: ExitCode 0 and StdErr EXACTLY empty. (Red control measured 2026-10-07: line 15
        # printed "cat: command not found" and line 30 "grep: command not found".)
    }
    It 'sweeps a stale claude-agy-test-audit-reminder.* debounce on marker creation (section 72) and spares a fresh one' {
        # Fixture TMPDIR holds claude-agy-test-audit-reminder.dead (mtime 40 days ago) and
        # claude-agy-test-audit-reminder.live (now). One test-file write -> the dead file is GONE,
        # the live one and the new .clavity-assert-seen-* marker remain.
    }
    It 'still debounces per-day under CLAVITY_HOOK_BASH3=1 when the payload has no session_id (the %()T gate)' {
        # Two invocations, -Env @{ CLAVITY_HOOK_BASH3 = '1' }, payloads WITHOUT session_id:
        # first emits, second is silent (the day-key marker from the date fallback matched).
    }
```

Mutants: (1) revert the find glob to the single `-name '.clavity-assert-*'` ⇒ §72 row red; (2) in (b) change `[Tt]ests` → `[Tt]est` ⇒ the existing 'degraded predicate agrees' row red; (3) drop the `else dsid=...` fallback (leave dsid empty under BASH3) ⇒ the day-key row red (second invocation emits again). Restore each.

- [ ] **Step 5: Mirror, debt, partition, commit** (same shape as Task 4; files: the two hook copies, the suite, Rows, `_partition.md`; message: `perf(hooks): assertion-strength-reminder builtins; stderr-silent PATHless (s59); stale test-audit debounce sweep (s72)`).

### Task 6: `.claude/hooks/agy-verify-reminder.sh` + its NEW suite

**Files:**
- Modify: `.claude/hooks/agy-verify-reminder.sh` (lines 17, 20–21, 35)
- Create: `scripts/tests/agy-verify-reminder.Tests.ps1`
- Modify: `justfile` (append the new suite to the `test-scripts-slow` Invoke-Pester list)
- Modify: `scripts/tests/hook-spawn-budget.Rows.ps1` (2 rows + a fake-agy helper; remove its `$B21Debt` entry)
- Modify: `scripts/tests/_partition.md` (new row + budget row bump)

- [ ] **Step 1: Rewrite the three spawn sites.**

(a) Line 17: `input=$(cat 2>/dev/null)` → `IFS= read -r -d '' input`.
(b) Lines 20–21 (jq cwd) → raw regex (a SessionStart payload; no user-content fields — same safety argument as Task 4, and this hook treats an undecodable cwd as not-this-repo silence, so no jq fallback is needed; the `command -v jq` guard at line 18 STAYS — the emit path still uses jq):

```bash
cwd=''
[[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && cwd=${BASH_REMATCH[1]}
cwd=${cwd//\\\\//}
[ -z "$cwd" ] && exit 0
```

(c) Line 35: `live=$(timeout 8 "$agy_bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)` →

```bash
_vr_out=$(timeout 8 "$agy_bin" --version 2>/dev/null)
live=''
re_ver='([0-9]+\.[0-9]+\.[0-9]+)'
[[ $_vr_out =~ $re_ver ]] && live=${BASH_REMATCH[1]}
```
(bash `=~` returns the LEFTMOST match — the same first-match the `grep -oE | head -1` pair took.)

- [ ] **Step 2: Create `scripts/tests/agy-verify-reminder.Tests.ps1`** — a small suite, self-contained (the hook had NONE; these rows are the behaviour floor the budget rows lean on):

```powershell
Describe 'agy-verify-reminder.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot '.claude/hooks/agy-verify-reminder.sh'
        $script:GitUsr = Join-Path (Split-Path -Parent (Split-Path -Parent (Get-GitBashOrThrow))) 'usr\bin'
        $script:JqDir = Split-Path -Parent (Get-Command jq).Source
        function New-VerifyFx {
            param([string]$DotnetCell = 'PASS 9.9.9')
            $root = Join-Path ([IO.Path]::GetTempPath()) ('avr-' + [Guid]::NewGuid().ToString('N'))
            $cwd = Join-Path $root 'repo'
            New-Item -ItemType Directory -Force -Path (Join-Path $cwd 'agy-autotrain/verify'), (Join-Path $root 'fakebin') | Out-Null
            @('| id | dotnet | classic |', '|----|--------|---------|', "| A1 | $DotnetCell | N/A |") |
                Set-Content -LiteralPath (Join-Path $cwd 'agy-autotrain/verify/assertions.md')
            # A fake agy the hook finds via PATH; prints a parsable version and exits 0.
            [IO.File]::WriteAllText((Join-Path $root 'fakebin/agy'), "#!/bin/sh`necho agy 9.9.9`n")
            [pscustomobject]@{ Root = $root; Cwd = $cwd
                Path = ((Join-Path $root 'fakebin') + ';' + $script:GitUsr + ';' + $script:JqDir + ';C:\WINDOWS\system32') }
        }
        function Invoke-Verify { param($Fx)
            Invoke-BashHook -HookPath $script:Hook -Payload ('{"cwd":"' + (($Fx.Cwd) -replace '\\', '\\') + '"}') -Env @{ PATH = $Fx.Path }
        }
    }
    It 'EMITS for a stale PASS cell (recorded version behind the live one)' {
        $f = New-VerifyFx -DotnetCell 'PASS 1.0.0'
        try { $r = Invoke-Verify $f
            $r.StdOut | Should -Match 'A1 \[dotnet\] PASS 1\.0\.0 \(live 9\.9\.9\)'; $r.ExitCode | Should -Be 0
        } finally { Remove-Item $f.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'stays SILENT when every applicable cell is current' {
        $f = New-VerifyFx -DotnetCell 'PASS 9.9.9'
        try { (Invoke-Verify $f).StdOut | Should -BeNullOrEmpty } finally { Remove-Item $f.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'EMITS NOROWS guidance when the table has no data rows' {
        $f = New-VerifyFx
        try {
            Set-Content -LiteralPath (Join-Path $f.Cwd 'agy-autotrain/verify/assertions.md') -Value '# empty'
            (Invoke-Verify $f).StdOut | Should -Match 'no probe rows could be read'
        } finally { Remove-Item $f.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'stays SILENT with no agy anywhere (not installed -> nothing to verify against)' {
        $f = New-VerifyFx
        try {
            Remove-Item (Join-Path $f.Root 'fakebin/agy')
            $r = Invoke-BashHook -HookPath $script:Hook -Payload ('{"cwd":"' + (($f.Cwd) -replace '\\', '\\') + '"}') -Env @{ PATH = ($script:GitUsr + ';' + $script:JqDir); LOCALAPPDATA = (Join-Path $f.Root 'lad') }
            $r.StdOut | Should -BeNullOrEmpty; $r.StdErr | Should -BeNullOrEmpty
        } finally { Remove-Item $f.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'stays SILENT outside the clavity repo (no assertions.md under cwd)' {
        $f = New-VerifyFx
        try {
            Remove-Item (Join-Path $f.Cwd 'agy-autotrain') -Recurse -Force
            (Invoke-Verify $f).StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $f.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
```

- [ ] **Step 3: Register the suite** in the `justfile` `test-scripts-slow` recipe's `Invoke-Pester @(...)` list (append `'scripts/tests/agy-verify-reminder.Tests.ps1'` before the closing `)`), and add a `_partition.md` row: `agy-verify-reminder.Tests.ps1  <measured>s  5 tests  <- SLOW, NEW 2026-10-07 (Branch 21: the hook had no suite), one run, box load uncontrolled`. Run the suite; expected `Tests Passed: 5`.

- [ ] **Step 4: Budget rows.** The Rows file's existing `$L/agy-verify-reminder.sh` row stays; add (fake agy keeps the count deterministic — the REAL agy's child-process count floats with its version):

```powershell
    New-BudgetRow "$L/agy-verify-reminder.sh" 'stale rows -> EMIT (fake agy on PATH)' {
        param($fx)
        $v = Join-Path $fx.Repo 'agy-autotrain/verify'; New-Item -ItemType Directory -Force -Path $v, (Join-Path $fx.Root 'fakebin') | Out-Null
        @('| id | dotnet | classic |', '|----|--------|---------|', '| A1 | PASS 1.0.0 | N/A |') | Set-Content -LiteralPath (Join-Path $v 'assertions.md')
        [IO.File]::WriteAllText((Join-Path $fx.Root 'fakebin/agy'), "#!/bin/sh`necho agy 9.9.9`n")
        $fx.Env.PATH = ((Join-Path $fx.Root 'fakebin') + ';' + $fx.Env.PATH)
        New-SessionStartPayload $fx } -Expect 'VERIFY-HARNESS reminder'
    New-BudgetRow "$L/agy-verify-reminder.sh" 'all rows current -> silent (fake agy on PATH)' {
        param($fx)
        $v = Join-Path $fx.Repo 'agy-autotrain/verify'; New-Item -ItemType Directory -Force -Path $v, (Join-Path $fx.Root 'fakebin') | Out-Null
        @('| id | dotnet | classic |', '|----|--------|---------|', '| A1 | PASS 9.9.9 | N/A |') | Set-Content -LiteralPath (Join-Path $v 'assertions.md')
        [IO.File]::WriteAllText((Join-Path $fx.Root 'fakebin/agy'), "#!/bin/sh`necho agy 9.9.9`n")
        $fx.Env.PATH = ((Join-Path $fx.Root 'fakebin') + ';' + $fx.Env.PATH)
        New-SessionStartPayload $fx } -Silent
```

(If `$fx.Env.PATH` is not pre-populated by `New-HookFixture`, set it from `$env:PATH` first — open the fixture function and match its shape; STATE-VERIFICATION applies.) Run with `HSB_HOOK='agy-verify-reminder.sh'`; expected green (these rows were never red pre-rewrite — the hook's count was PATH-profile-dependent; the suite rows above are the behaviour floor, the budget rows pin the ceiling from now on).

- [ ] **Step 5: Mutants:** (1) in (c) change `re_ver` to `'([0-9]+\.[0-9]+)'` ⇒ the stale-EMIT suite row red (live `9.9` ≠ cell version shape… the row asserts `(live 9\.9\.9)`); (2) in (b) drop the `${cwd//\\\\//}` collapse ⇒ every suite row red (path never resolves → silent). Restore.

- [ ] **Step 6: Commit** (`.claude/hooks/agy-verify-reminder.sh`, the new suite, `justfile`, Rows, `_partition.md`; remove its `$B21Debt` entry): `perf(hooks): agy-verify-reminder builtins + first test suite`.

### Task 7: `.claude/hooks/docs-audit-reminder.sh` — all-builtin counting

**Files:**
- Modify: `.claude/hooks/docs-audit-reminder.sh` (lines 9, 18–27)
- Modify: `scripts/tests/docs-audit-reminder.Tests.ps1` (no new rows needed — its 7 rows already cover EMIT/silent/CRLF/unrecognisable; they are the preservation proof)
- Modify: `scripts/tests/hook-spawn-budget.Rows.ps1` (2 rows; remove its `$B21Debt` entry), `scripts/tests/_partition.md`

- [ ] **Step 1: Budget rows (failing control):**

```powershell
    New-BudgetRow "$L/docs-audit-reminder.sh" 'generated view, 3 open findings -> EMIT' {
        param($fx)
        $d = Join-Path $fx.Repo 'docs'; New-Item -ItemType Directory -Force -Path $d | Out-Null
        @('# docs audit findings (GENERATED 2026-10-07)', '', '## a.md', '- f1', '- f2', '- f3') | Set-Content -LiteralPath (Join-Path $d 'docs-audit-findings.md')
        $fx.Env.CLAUDE_PROJECT_DIR = $fx.RepoFwd
        New-SessionStartPayload $fx } -Expect '3 open finding'
    New-BudgetRow "$L/docs-audit-reminder.sh" 'generated view, (no findings) only -> silent' {
        param($fx)
        $d = Join-Path $fx.Repo 'docs'; New-Item -ItemType Directory -Force -Path $d | Out-Null
        @('# docs audit findings (GENERATED 2026-10-07)', '', '## a.md', '- (no findings)') | Set-Content -LiteralPath (Join-Path $d 'docs-audit-findings.md')
        $fx.Env.CLAUDE_PROJECT_DIR = $fx.RepoFwd
        New-SessionStartPayload $fx } -Silent
```

Run with `HSB_HOOK='docs-audit-reminder.sh'`; expected: both FAIL on count (census 22 vs 16).

- [ ] **Step 2: Rewrite lines 9 and 18–27:**

```bash
root="${CLAUDE_PROJECT_DIR:-$PWD}"
```

```bash
# First line, builtin (the failed-open case keeps the old head|grep behaviour: an unreadable view is
# "not a recognisable generated view", never a silent pass). 2>/dev/null BEFORE < - redirect order.
first=''
{ IFS= read -r first || :; } 2>/dev/null < "$view"
first=${first%$'\r'}
case "$first" in '# docs audit findings (GENERATED'*) : ;; *)
  emit "[DOCS-AUDIT] docs/docs-audit-findings.md exists but is not a recognisable generated view - open findings NOT counted. Re-run just docs-audit." ;;
esac

# One builtin pass replaces tr + three greps. CR is stripped PER LINE (the tr stripped it file-wide;
# only line-end CRs occur in a CRLF save, so the per-line strip sees the same lines).
findings=0; empty=0; unconfirmed=0
re_unc='^## .+ — AUDIT-'
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%$'\r'}
  case "$line" in
    '- (no findings)') findings=$((findings + 1)); empty=$((empty + 1)) ;;
    '- '*)             findings=$((findings + 1)) ;;
  esac
  [[ $line =~ $re_unc ]] && unconfirmed=$((unconfirmed + 1))
done 2>/dev/null < "$view"
open=$((findings - empty))
[ "$open" -le 0 ] && [ "$unconfirmed" -le 0 ] && exit 0
emit "[DOCS-AUDIT] ${open} open finding(s) and ${unconfirmed} unconfirmed doc(s) in docs/docs-audit-findings.md - read it and triage."
```

(`emit` itself is already printf-only. The em dash in `re_unc` matches the one the renderer writes — this file is repo-local and already non-ASCII, exempt from the plugin ASCII sweep.)

- [ ] **Step 3: Suites.** Run `docs-audit-reminder.Tests.ps1` (expected: 7/7 green — the preservation proof) and the budget rows (green). Mutant: remove the `'- (no findings)')` case arm ⇒ the suite's no-findings-silent row red AND the silent budget row red. Restore.

- [ ] **Step 4: Commit** (hook, Rows, `_partition.md`; remove its `$B21Debt` entry): `perf(hooks): docs-audit-reminder counts with builtins`.

### Task 8: `fetch-clavity-ls.sh` — steady state and lookup paths + §64

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh` (lines 29–34, 44–46, 48–55, 58, 71–72) — dotnet-only, NO classic mirror
- Modify: `scripts/tests/fetch-clavity-ls.Tests.ps1` (2 new rows incl. the §64 row; `New-Fx` is its fixture helper — open the file first)
- Modify: `scripts/tests/hook-spawn-budget.Rows.ps1` (2 rows; remove its `$B21Debt` entry), `scripts/tests/_partition.md`

- [ ] **Step 1: Budget rows (failing control).** The existing steady-state row stays; add (fake curl via a prepended PATH dir, the census technique):

```powershell
    New-BudgetRow "$D/fetch-clavity-ls.sh" 'release lookup FAILS (fake curl = false) -> manual-install note' {
        param($fx)
        $fb = Join-Path $fx.Root 'fakebin'; New-Item -ItemType Directory -Force -Path $fb, (Join-Path $fx.Root 'root') | Out-Null
        Copy-Item (Join-Path $script:GitUsrBin 'false.exe') (Join-Path $fb 'curl.exe')
        [IO.File]::WriteAllText((Join-Path $fx.Root 'root/plugin.json'), '{"version":"9.9.9"}')
        $fx.Env.CLAUDE_PLUGIN_DATA = (($fx.Root -replace '\\', '/') + '/data')
        $fx.Env.CLAUDE_PLUGIN_ROOT = (($fx.Root -replace '\\', '/') + '/root')
        $fx.Env.PATH = ($fb + ';' + $fx.Env.PATH)
        New-SessionStartPayload $fx } -Expect 'release lookup failed'
    New-BudgetRow "$D/fetch-clavity-ls.sh" 'lookup EMPTY (fake curl = true, jq present) -> no-asset note' {
        param($fx)
        $fb = Join-Path $fx.Root 'fakebin'; New-Item -ItemType Directory -Force -Path $fb, (Join-Path $fx.Root 'root') | Out-Null
        Copy-Item (Join-Path $script:GitUsrBin 'true.exe') (Join-Path $fb 'curl.exe')
        [IO.File]::WriteAllText((Join-Path $fx.Root 'root/plugin.json'), '{"version":"9.9.9"}')
        $fx.Env.CLAUDE_PLUGIN_DATA = (($fx.Root -replace '\\', '/') + '/data')
        $fx.Env.CLAUDE_PLUGIN_ROOT = (($fx.Root -replace '\\', '/') + '/root')
        $fx.Env.PATH = ($fb + ';' + $fx.Env.PATH)
        New-SessionStartPayload $fx } -Expect 'no release asset named'
```

with, near the other Rows-file constants: `$script:GitUsrBin = Join-Path (Split-Path -Parent (Split-Path -Parent (Get-GitBashOrThrow))) 'usr\bin'`. Run with `HSB_HOOK='fetch-clavity-ls.sh'`; expected: the existing steady row (17) and both new rows (23/31) FAIL on count.

- [ ] **Step 2: Five edits to the hook.**

(a) Lines 29–34, `_json_str`/`_say` — builtin escaping, result via a global (kills `sed|tr` + the `$( )` subshell on EVERY note path):

```bash
# Builtin JSON string escape (Branch 21): backslash first, then double quote, then the only control
# characters these messages can carry - \n, \r, \t from a weird CLAUDE_PLUGIN_DATA value. The old
# `sed | tr -d '\000-\037'` stripped the whole C0 range; every message here is fixed ASCII text plus
# $TARGET, so after the three expansions below no other control character can remain.
_json_str() {
  _js=${1//\\/\\\\}
  _js=${_js//\"/\\\"}
  _js=${_js//$'\n'/ }; _js=${_js//$'\r'/}; _js=${_js//$'\t'/ }
}
_say() {
  echo "$1" >&2
  _json_str "$1"
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$_js" "$_js"
}
```

(b) Lines 44–46 (VER via `sed -n | head -1`) — builtin first-matching-line read; the regex keeps sed's greedy `.*` prefix, so the LAST `"version"` on the first matching line wins, exactly as before:

```bash
VER=''
if [ -f "$ROOT/plugin.json" ]; then
  re_ver='.*"version"[[:space:]]*:[[:space:]]*"([^"]*)"'
  while IFS= read -r _l || [ -n "$_l" ]; do
    if [[ $_l =~ $re_ver ]]; then VER=${BASH_REMATCH[1]}; break; fi
  done 2>/dev/null < "$ROOT/plugin.json"
fi
[ -n "$VER" ] || { _note "could not read plugin version"; exit 0; }
```

(c) Lines 48–55 (platform via two `uname`) — `$OSTYPE`/`$HOSTTYPE` first, `uname` ONLY in the fallback arm so every real platform costs zero processes and an exotic shell keeps the old byte-exact behaviour:

```bash
# Platform -> .NET RID. $OSTYPE/$HOSTTYPE are bash builtins set at startup - no uname processes on any
# platform bash actually names; the *) arm keeps the original uname probe for anything exotic.
case "${OSTYPE:-}" in
  linux*)        _rid=linux-x64 ;;
  darwin*)       case "${HOSTTYPE:-}" in arm64|aarch64) _rid=osx-arm64 ;; *) _rid=osx-x64 ;; esac ;;
  msys*|cygwin*) _rid=win-x64 ;;
  *)
    _os=$(uname -s 2>/dev/null); _arch=$(uname -m 2>/dev/null)
    case "$_os" in
      Linux)   _rid=linux-x64 ;;
      Darwin)  case "$_arch" in arm64|aarch64) _rid=osx-arm64 ;; *) _rid=osx-x64 ;; esac ;;
      MINGW*|MSYS*|CYGWIN*|Windows_NT) _rid=win-x64 ;;
      *) _note "unsupported platform '${_os:-$OSTYPE}/${_arch:-$HOSTTYPE}'"; exit 0 ;;
    esac ;;
esac
```

(d) Line 58 (stamp via `$(cat)`):

```bash
_st=''
IFS= read -r _st 2>/dev/null < "$STAMP"
if [ -x "$TARGET" ] && [ "$_st" = "$VER" ]; then exit 0; fi
```
(The stamp is written with `printf '%s'` and no newline — `read` returns non-zero there but still fills `_st`; a missing stamp leaves it empty, same as the old `cat 2>/dev/null`.)

(e) Lines 71–72 (the no-jq URL grep|head pair) — builtin, anchored to the download-url FIELD with the asset's dots escaped (the old bare `grep -o` matched un-anchored with live dots; the new form is strictly tighter and first-match, which `head -1` already took):

```bash
  _re_asset=${ASSET//./\\.}
  re_url='"browser_download_url"[[:space:]]*:[[:space:]]*"(https://[^"]*/'$_re_asset')"'
  re_sha='"browser_download_url"[[:space:]]*:[[:space:]]*"(https://[^"]*/'$_re_asset'\.sha256)"'
  _url=''; _shaurl=''
  [[ $_json =~ $re_url ]] && _url=${BASH_REMATCH[1]}
  [[ $_json =~ $re_sha ]] && _shaurl=${BASH_REMATCH[1]}
```

The jq branch (67–69) and the whole download/verify/extract tail stay untouched — the first-run network path is not a census row.

- [ ] **Step 3: Budget rows green** (re-run Step 1; compat rows: nothing version-gated here, byte-identical output).

- [ ] **Step 4: Two suite rows** in `scripts/tests/fetch-clavity-ls.Tests.ps1` (its `New-Fx` builds the env + fake-PATH fixture — open the file and reuse):

```powershell
    It 'notes "mktemp failed" and places NOTHING when mktemp exits non-zero (ROADMAP section 64)' {
        # Fixture: fake curl that SUCCEEDS returning a release json naming the asset (the suite already
        # fakes curl via a PATH script - reuse that shape), plus a fake mktemp (a script `exit 1`) FIRST
        # on PATH. Expect: stdout envelope matching 'mktemp failed', exit 0, and no file at the TARGET path.
    }
    It 'extracts the plain asset URL, not the .sha256 one, on the no-jq path (the anchored builtin regex)' {
        # Fixture json carrying BOTH browser_download_url entries (.tar.gz and .tar.gz.sha256), no jq on
        # PATH: the hook must pick the .tar.gz URL for _url (observable: the download attempt hits the
        # plain-asset URL / the failure note names it; follow the suite's existing fake-curl assertion shape).
    }
```

Mutants: (1) delete `|| { _note "mktemp failed"; exit 0; }` from line 77 ⇒ the §64 row red (this is §64's named non-vacuity proof); (2) in (e) drop the `${ASSET//./\\.}` escaping and the closing-quote anchor (revert toward the loose match) ⇒ the sha-vs-plain row red. Restore.

- [ ] **Step 5: Commit** (hook, suite, Rows, `_partition.md` — fetch suite row `10 tests` today and the budget row; remove its `$B21Debt` entry): `perf(hooks): fetch-clavity-ls builtins on every non-network path; mktemp-failure test (s64)`.

### Task 9: `migrate-inbox.sh` — builtin `_size`

**Files:**
- Modify: `agy-autotrain/hooks/migrate-inbox.sh` (lines 36–42, 51–52, 56, 70, 89–90, 98) — agy-autotrain-only, no mirror
- Modify: `scripts/tests/agy-autotrain-migrate-inbox.Tests.ps1` (1 new row)
- Modify: `scripts/tests/hook-spawn-budget.Rows.ps1` (1 row; remove its `$B21Debt` entry), `scripts/tests/_partition.md`

- [ ] **Step 1: Budget row (failing control):**

```powershell
    New-BudgetRow "$A/migrate-inbox.sh" 'RECOVER an interrupted migration (sidecar back, then complete)' {
        param($fx)
        $old = Join-Path $fx.Root 'lad/Programs/agy-autotrain/plugins/agy-autotrain/knowledge'
        New-Item -ItemType Directory -Force -Path $old | Out-Null
        [IO.File]::WriteAllText((Join-Path $old 'agy-observations.md.migrated-14g'), "- [h] rescued`n")
        $fx.Env.LOCALAPPDATA = (Join-Path $fx.Root 'lad')
        New-SessionStartPayload $fx } -Silent -Verify {
        param($fx)
        $new = Join-Path $fx.Home '.clavity/agy-observations.md'
        $new | Should -Exist
        (Get-Content -LiteralPath $new -Raw) | Should -Match 'rescued' }
```

Run with `HSB_HOOK='migrate-inbox.sh'`; expected FAIL on count (census 17 vs 16). (The hook's "migrated" line goes to stderr; stdout is empty, so `-Silent` + `-Verify` is the honest shape.)

- [ ] **Step 2: Rewrite `_size` (lines 36–42) as a three-state builtin that sets a global** — callers only ever test `= 0`, `= -1`, `-gt 0`, so the exact byte count was never consumed (verified by reading lines 51–98):

```bash
# Three-state size probe, builtins only (Branch 21): _SZ = 0 absent-or-empty, -1 unreadable-or-not-a-
# regular-file, 1 non-empty. The .iss lesson stands: a failed READ must never look like an empty file
# - and the probe is an actual OPEN, because the -r builtin does not consult Windows ACLs. No caller
# ever used the byte count itself (they test =0, =-1, -gt 0), so the wc process bought nothing.
_size() {
  if [ ! -e "$1" ]; then _SZ=0; return; fi
  if [ ! -f "$1" ]; then _SZ=-1; return; fi
  if ! { :; } 2>/dev/null < "$1"; then _SZ=-1; return; fi
  if [ -s "$1" ]; then _SZ=1; else _SZ=0; fi
}
```

Call sites (all six): `destsize=$(_size "$NEW")` → `_size "$NEW"; destsize=$_SZ` (lines 51, 89); `asidesize=$(_size "$ASIDE")` → `_size "$ASIDE"; asidesize=$_SZ` (line 52; the line-52 `[ ! -e ]` pre-test can stay). Line 70: `if ! mkdir -p "$NEWDIR" 2>/dev/null` → `if [ ! -d "$NEWDIR" ] && ! mkdir -p "$NEWDIR" 2>/dev/null` (skips the process when the dir exists — the common case).

- [ ] **Step 3: Budget row green; suite green** (`agy-autotrain-migrate-inbox.Tests.ps1`, 9 rows — the preservation proof). Add one row:

```powershell
    It 'stops and rolls back when the destination is a DIRECTORY (size unreadable, nothing clobbered)' {
        # Fixture: OLD exists with content; NEW path pre-created as a DIRECTORY. Expect: stderr matching
        # 'could not be read', OLD restored (the claim rolled back), the directory untouched.
    }
```

Mutant: in `_size`, change the `[ ! -f "$1" ]` arm to set `_SZ=0` ⇒ this row red (the hook would treat the directory as an empty destination and walk into the cp-fail path with the WRONG message). Restore.

- [ ] **Step 4: Commit** (hook, suite, Rows, `_partition.md`; remove its `$B21Debt` entry — the LAST entry, so `$script:B21Debt = @()` remains and the debt row goes GREEN locally): `perf(hooks): migrate-inbox three-state builtin size probe`.

### Task 10: §59 — the two under-ceiling hooks stop printing stderr under an empty PATH

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh` (line 36) + classic copy
- Modify: `clavity-dotnet/plugin/hooks/agy-anomaly-model-notice.sh` (line 19) + classic copy
- Modify: `scripts/tests/agy-anomaly-dispatch-reminder.Tests.ps1`, `scripts/tests/agy-anomaly-model-notice.Tests.ps1` (1 row each), `scripts/tests/_partition.md`

- [ ] **Step 1: The failing controls, measured first** (red before the fix — record the output in the task log):

```bash
printf '{}' | PATH= "C:/Program Files/Git/bin/bash.exe" clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh
# stderr today: "line 36: cat: command not found"   (exit 0)
printf '{}' | PATH= "C:/Program Files/Git/bin/bash.exe" clavity-dotnet/plugin/hooks/agy-anomaly-model-notice.sh
# stderr today: "line 19: cat: command not found"   (exit 0)
```

- [ ] **Step 2: One-line swaps.** In both files replace `input=$(cat)` with `IFS= read -r -d '' input` plus the one-line comment: `# BUILTIN, not $(cat): no fork, and nothing on stderr under an empty PATH (ROADMAP section 59; same idiom as agy-anomaly-reminder.sh).`

- [ ] **Step 3: One row per suite** (each suite has `$script:NoJqPath`-style env plumbing — these rows use an EMPTY PATH, which is stricter):

```powershell
    It 'writes NOTHING to stderr under an EMPTY PATH, and still delivers its envelope (section 59)' {
        # dispatch-reminder: payload '{}' with -Env @{ PATH = '' } -> StdErr EXACTLY empty, ExitCode 0,
        # StdOut still carries the PreToolUse envelope (the no-jq branch emits regardless).
    }
    It 'writes NOTHING to stderr under an EMPTY PATH (silent no-jq path, section 59)' {
        # model-notice: payload '{}' with -Env @{ PATH = '' } -> StdErr empty, StdOut empty, ExitCode 0.
    }
```

- [ ] **Step 4: Mutant** (both files at once): revert `IFS= read -r -d '' input` → `input=$(cat)` ⇒ both new rows red (stderr carries `cat: command not found`). Restore.
- [ ] **Step 5: Mirror both to classic, run `bash scripts/check-seed-artifacts-synced.sh`, run both suites + `_partition.md` bumps, commit:** `fix(hooks): dispatch-reminder + model-notice read stdin with the builtin (s59 closes)`.

### Task 11: §73 — `agy-curate-nudge.sh` age gate without GNU `date -d`

**Files:**
- Modify: `agy-autotrain/hooks/agy-curate-nudge.sh` (lines 78–83; helper inserted after line 16)
- Modify: `scripts/tests/agy-curate-nudge.Tests.ps1` (3 new rows)
- Modify: `scripts/tests/_partition.md`

- [ ] **Step 1: Insert the helper** (after the `SNOOZE=` line 16, before the opt-out block):

```bash
# Days since the civil epoch for a YYYY-MM-DD string (Hinnant's days_from_civil), bash-3.2-safe
# arithmetic only (ROADMAP section 73: BSD/macOS date has no `-d <date>` parse, so the age nudge never
# fired there; the GNU-only call is gone entirely). UTC day count, where date -d used local midnight -
# the boundary can shift by up to the UTC offset, accepted for a 30-day threshold.
_dfc() {
  _y=$1; _m=$((10#$2)); _d=$((10#$3))
  [ "$_m" -le 2 ] && _y=$((_y - 1))
  if [ "$_y" -ge 0 ]; then _era=$((_y / 400)); else _era=$(((_y - 399) / 400)); fi
  _yoe=$((_y - _era * 400))
  _doy=$(((153 * ((_m + 9) % 12) + 2) / 5 + _d - 1))
  _doe=$((_yoe * 365 + _yoe / 4 - _yoe / 100 + _doy))
  _DFC=$((_era * 146097 + _doe - 719468))
}
```

- [ ] **Step 2: Replace the age gate (lines 79–83)** — the whole `if [ -n "$oldest" ]` block:

```bash
age_stale=0
re_iso='^([0-9]{4})-([0-9]{2})-([0-9]{2})$'
if [[ $oldest =~ $re_iso ]]; then
  _mo=$((10#${BASH_REMATCH[2]})); _da=$((10#${BASH_REMATCH[3]}))
  # Range-validate what `date -d` used to reject: 2026-13-45 must not arm the gate.
  if [ "$_mo" -ge 1 ] && [ "$_mo" -le 12 ] && [ "$_da" -ge 1 ] && [ "$_da" -le 31 ]; then
    if [ -z "${CLAVITY_HOOK_BASH3:-}" ] && ((BASH_VERSINFO[0]*100+BASH_VERSINFO[1] >= 402)); then printf -v now '%(%s)T' -1 2>/dev/null; else now=$(date +%s); fi
    _dfc "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    if [ -n "$now" ] && [ "$(( now / 86400 - _DFC ))" -ge "$MAX_AGE_DAYS" ]; then age_stale=1; fi
  fi
fi
```

- [ ] **Step 3: Three rows** in `scripts/tests/agy-curate-nudge.Tests.ps1` (helper `New-NudgeEnv` — open the file; the inbox bullets use the MIDDLE-DOT separator the suite already writes):

```powershell
    It 'fires the age nudge for a 40-day-old pending entry, with NO date -d available to the hook' {
        # Inbox: ONE pending entry dated (Get-Date).ToUniversalTime().AddDays(-40).ToString('yyyy-MM-dd')
        # (count 1 < threshold, so ONLY the age gate can fire). Expect stdout matching 'over 30 days old'.
        # The hook must no longer contain `date -d` at all - also assert:
        (Get-Content -LiteralPath $script:Hook -Raw) | Should -Not -Match 'date -d'
    }
    It 'computes the same day number as GNU date -d for five dates including a leap day' {
        # The equivalence control (law 4: passing AND failing control in one oracle): for each of
        # 2024-02-29, 2026-01-01, 1999-12-31, 2026-10-07, 2100-01-01, run bash twice -
        #   a) `date -d <d> +%s` divided by 86400 (GNU reference, UTC via TZ=UTC), and
        #   b) a snippet sourcing nothing: the _dfc function body pasted from the hook via
        #      `bash -c '. <(sed -n "/^_dfc()/,/^}/p" <hook>); _dfc <y> <m> <d>; echo $_DFC'`
        # and assert a == b for every date, plus one DELIBERATE mismatch control (feed b a wrong day
        # and assert the comparison FAILS) so the oracle can return its failing answer.
    }
    It 'does NOT arm the age gate on an out-of-range date (2026-13-45)' {
        # Inbox: one pending entry dated 2026-13-45, count under threshold. Expect: silent (exit 0, no
        # output) - exactly what date -d's rejection produced.
    }
```

- [ ] **Step 4: Mutants:** (1) `_doy` formula `+ 2)` → `+ 1)` ⇒ the equivalence row red; (2) delete the month/day range test ⇒ the 2026-13-45 row red. Restore each. Run the suite under `CLAVITY_HOOK_BASH3=1` too (one extra invocation of the 40-day row's command with that env — the suite's compat shape) — the age nudge still fires on the pure-bash path.
- [ ] **Step 5: Capture the sibling anomaly, do not fix it:** line 38's `mt="$(date -r "$SNOOZE" +%s)"` is ALSO GNU-only (`date -r` on BSD takes epoch seconds, not a file), so the SNOOZE never silences the nudge on macOS. Out of §73's scope — append one `open-issues` entry to `.clavity/local-anomalies.md` (type `defect`, anchor `agy-autotrain/hooks/agy-curate-nudge.sh:38`, task `Branch 21 Task 11`) for the owner's next triage.
- [ ] **Step 6: Commit** (hook, suite, `_partition.md`): `fix(hooks): curate-nudge age gate computes days in bash (s73 - macOS date has no -d)`.

### Task 12: Close-out — debt row green, full census, gates, ROADMAP

**Files:**
- Modify: `scripts/tests/hook-spawn-budget.Rows.ps1` (only if any `$B21Debt` residue remains — expected state after Task 9: `$script:B21Debt = @()` with the owner-ruling comment retained above it)
- Modify: `clavity-dotnet/ROADMAP.md` (§69, §72, §73, §64, §59 headers/notes)
- Modify: `scripts/tests/_partition.md` (final `hook-spawn-budget` tally)

- [ ] **Step 1: Full census re-measurement** of all eight hooks + the two §59 hooks (the Measure command from the preamble, `-Filter '^(agy-inbox-snapshot|agy-discipline-reaching|agy-anomaly-reminder|agy-verify-reminder|docs-audit-reminder|assertion-strength-reminder|fetch-clavity-ls|migrate-inbox|agy-anomaly-dispatch-reminder|agy-anomaly-model-notice)\|'`, `-Out .clavity/scratch/b21-measure/after.jsonl`). Expected: EVERY row ≤ 16, r1 == r2. Record the per-hook before→after worst counts for the ROADMAP note.
- [ ] **Step 2: Full budget suite, un-filtered** (background it — it exceeds the foreground cap): `pwsh -NoProfile -c "Invoke-Pester scripts/tests/hook-spawn-budget.Tests.ps1 -Output Detailed -CI"`. Expected: Failed: 0 — including the census row (every registered hook still has ≥ 1 row) and the `carries no Branch 21 debt` row, now GREEN because the list is empty. Then update that row's `_partition.md` note: the debt row is no longer "1 row RED locally".
- [ ] **Step 3: Repo gates, sequentially:** `bash scripts/check-seed-artifacts-synced.sh` (0) · `pwsh -NoProfile -c "Invoke-Pester scripts/tests/plugin-hooks-payload.Tests.ps1, scripts/tests/plugin-hooks-registration.Tests.ps1 -Output Detailed -CI"` (ASCII + byte-identical pairs + registration; expected all green) · `pwsh -NoProfile -File scripts/check-injected-context.ps1` (the emitted messages did not change text, only their plumbing — expected OK) · `pwsh -NoProfile -File scripts/check-control-bytes.ps1` if present per pre-push config (expected OK).
- [ ] **Step 4: ROADMAP updates** (`clavity-dotnet/ROADMAP.md`):
  - §69: append a SHIPPED note with the measured before→after table (from Step 1) and the two fixture-helper homes (`Add-FxInbox`, `Set-FxShield` in the Rows file).
  - §72: header → shipped; body notes the owner-accepted home CHANGE: the sweep rides `assertion-strength-reminder.sh`'s create-path `find` (zero added processes), not a SessionStart hook as first sketched.
  - §73: header → shipped; note the UTC-day-boundary divergence and the captured `date -r` sibling anomaly.
  - §64: header → shipped (the mktemp-failure row + its mutant).
  - §59: header → shipped; body already names the three remaining hooks — note all three now read stdin with the builtin and the empty-PATH stderr rows pin it (and that Branch 20 had silently fixed the other four).
- [ ] **Step 5: Fast half as the final sweep** (background): `just test-scripts-fast` — expected `Tests Passed: ~670+, Failed: 0`; then `just test-scripts-slow` (background, AFTER fast completes) — expected Failed: 0 now that the debt row is green.
- [ ] **Step 6: Commit:** `git add clavity-dotnet/ROADMAP.md scripts/tests/_partition.md scripts/tests/hook-spawn-budget.Rows.ps1` → `docs(roadmap): Branch 21 shipped notes - s69 counts, s72 home, s73 divergence, s64, s59 closed`.

---

## After the tasks (disciplines, not plan steps)

1. **AGY-CAPSTONE** over the whole branch (`6a6224ce..HEAD`, which re-extends over every fold) — the phase-1 round (Task 3) does not substitute; rounds until GREEN, owner adjudicates, ledger row BEFORE marker.
2. **AGY-TEST-AUDIT** (hook-nudged after capstone GREEN; ~5x leaner after /compact — tell the owner and follow their answer).
3. **finishing-a-development-branch** — the owner owns every push; on push, watch the `ci-scripts` jq step and the (now green) debt row.

## Self-audit (the writing-plans exhaustiveness pass, run 2026-10-07)

- **Spec coverage:** §69's eight hooks → Tasks 1, 2, 4, 5, 6, 7, 8, 9 (one each; every measured-over path has a budget row). §72 → Task 5(e). §73 → Task 11. §64 → Task 8 Step 4. §59 → Task 5(a)(b) + Task 10. Inventory defect 1 (KEEP=08) → Task 1(a); defect 2 (`[ \t]`) → Task 1(d); defect 3 (`%()T` ungated) → Task 2 Step 3(b) + Task 5(c). Phase split + phase-1 capstone → Task 3. Criterion (every census path ≤ 16) → per-task budget rows + Task 12 Step 1. Debt-list emptying per-commit → each task's final step; Task 9 removes the last entry.
- **Known deliberate gaps, stated:** (1) Three suite-row blocks (Task 1 Step 5, Task 2 Step 5, Task 4 Step 4, Task 8 Step 4, Task 9 Step 3, Task 10 Step 3, Task 11 Step 3 partially) give COMPLETE assertions but defer fixture-helper NAMES to the suite file being extended — those suites were not fully read at plan time; STATE-VERIFICATION (open the file first, `STATE_MISMATCH` on divergence) is the guard, the same convention Branch 20's plan used. (2) Task 2 Step 4 names a contingency (`-Max` 15 on ONE compat row) that only materialises if the measured bash3 fallback cost exceeds the ceiling — the run decides, not the plan. (3) `agy-curate-nudge`'s `date -r` snooze defect is explicitly captured-not-fixed (Task 11 Step 5).
- **Type/name consistency:** `Add-FxInbox`/`Get-FxBaks`/`Set-FxShield`/`$script:GitUsrBin` are defined once (Tasks 1, 2, 8) and used only after their defining task; `_SZ`, `_DFC`, `_asm_dir`, `_as_swept_now` globals are each defined in the same edit that reads them. `$B21Debt` entry names match the live file's `Hook` keys (verified at `6a6224ce`).
- **Line-citation discipline:** every `file:line` in this plan was read at `6a6224ce` during planning (2026-10-07); Tasks 4–11 execute after phase 1 commits, which do NOT touch those files' cited regions — if any drift is found at execution, STOP and re-verify rather than adapt.

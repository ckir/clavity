# SessionStart Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the discipline-reaching recorder from `SessionEnd` (where its registered path does not resolve, so it is cancelled and writes nothing) to `SessionStart`, and update its only consumer to read the new schema honestly.

**Architecture:** The hook stays subprocess-free and capture-only: it names a session and its transcript, then stops. Two consent guards move AFTER the repo-root walk because they depend on it. The report gains a version-3 branch, deduplication by `session_id`, a reordered pipeline (parse → collapse → slice → expand), and a third partition bucket for sessions still being written.

**Tech Stack:** Bash (no subprocesses — bash regex, `printf %()T`, in-shell `.git` walk), PowerShell 7 + Pester 5, Inno Setup manifests as JSON, `just` recipes, lefthook pre-commit.

**Design:** `docs/superpowers/specs/2026-08-05-sessionstart-capture-design.md` — panel-GREEN at round 12, owner-accepted 2026-08-05.

---

## Before you start — five facts that will cost you an hour each

1. **Both driver plugins must stay byte-identical** for `agy-discipline-reaching.sh`. `clavity-dotnet/plugin/hooks/` and `clavity-classic/plugin/hooks/` hold copies enforced by `scripts/check-seed-artifacts-synced.sh` and `scripts/tests/plugin-hooks-payload.Tests.ps1`. **Every hook edit is two identical edits.** Never hand-type the second — copy the first.
2. **`justfile` is LF.** Editing it has silently converted it to CRLF four times in this repo. After touching it run `grep -c $'\r' justfile` and expect `0`.
3. **`docs/superpowers/*` is gitignored** (`.gitignore:32`). Plan and spec files need `git add -f`. **`.clavity/` is also gitignored (`.gitignore:45`) — never force-add it.**
4. **Use the Grep tool, not bash `grep`, for "are any left?" questions.** During review bash `grep` returned a false zero on strings that were verifiably present.
5. **Test registration in `justfile` is an explicit list, not a glob.** This plan adds no new suite, so no registration change is needed — but if you split a suite, it will silently never run until listed.

**Run tests with:** `pwsh -Command "Invoke-Pester -Path scripts/tests/<suite>.Tests.ps1 -Output Detailed"` for a single suite. The whole fast half is `just test-scripts-fast` (~250s; run it before the final commit, not between every step).

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh` | the capture hook | consent guards move after the root walk; schema `v:3`; header rewrite |
| `clavity-classic/plugin/hooks/agy-discipline-reaching.sh` | byte-identical twin | same, copied |
| `clavity-dotnet/plugin/hooks/hooks.json` | dotnet registration | add to the `SessionStart` four-source block; delete the `SessionEnd` block |
| `clavity-classic/plugin/hooks/hooks.json` | classic registration | same |
| `scripts/discipline-reaching-report.ps1` | the only consumer | `v:3` branch, dedup, pipeline reorder, provisional bucket, 3-way partition, refusal reasons |
| `scripts/tests/agy-discipline-reaching.Tests.ps1` | hook suite | retarget payload shape; add consent + schema cases |
| `scripts/tests/discipline-reaching-report.Tests.ps1` | report suite | add dedup, ordering, provisional, `v:3` cases; fix stale premises |
| `scripts/tests/plugin-hooks-registration.Tests.ps1` | registration gate | **add this hook — it was never covered, which is why v17 shipped broken** |
| `clavity-dotnet/ROADMAP.md` | owner-facing §0 | `:254` names the wrong event and the superseded spec |
| `justfile` | recipe docs | `:90` names the wrong event |
| `scripts/README.md` | script inventory | `:55` description goes stale |
| `scripts/tests/_partition.md` | measured test oracle | re-measure after suites change |

---

## Task 1: Hook — move the consent guards after the root walk

The `.no-agy` check currently runs at `:51`, before the walk at `:58-66` decides where the row is written. A user with `.no-agy` at their repo root who launches Claude in `repo/src` is not suppressed, and the hook writes into their tree anyway. The same walk falls back to `cwd` when no `.git` exists, so a non-repo directory gets a `.clavity/` folder.

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh:51-66`
- Modify: `clavity-classic/plugin/hooks/agy-discipline-reaching.sh:51-66`
- Test: `scripts/tests/agy-discipline-reaching.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

**Extend the existing `-ForEach` block at `:201-212` — do NOT add a separate `It`.** That block already parameterises the opt-out scopes, so the subdirectory scope belongs in its data. This raises the TEST count without changing the BLOCK count, which is the distinction `_partition.md` turns on. Replace the whole block with:

```powershell
    It 'is SILENT under .no-agy (<Scope>) and writes nothing' -ForEach @(
        @{ Scope = 'workspace' }, @{ Scope = 'global' }, @{ Scope = 'root-from-subdir' }
    ) {
        $r = New-TempRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            $cwdArg = $r
            switch ($Scope) {
                'workspace' { New-Item -ItemType File -Path (Join-Path $r '.no-agy') -Force | Out-Null }
                'global'    { New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null }
                'root-from-subdir' {
                    # THE SHIPPED BYPASS: the opt-out is at the repo ROOT that would be written to, while
                    # the session was launched in a SUBDIRECTORY. Before the fix this WROTE a row.
                    New-Item -ItemType File -Path (Join-Path $r '.no-agy') -Force | Out-Null
                    $cwdArg = Join-Path $r 'src'
                    New-Item -ItemType Directory -Path $cwdArg -Force | Out-Null
                }
            }
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $cwdArg $tx) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            Get-Record $r | Should -BeNullOrEmpty -Because 'an opt-out anywhere on the path to the write target must suppress the write'
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

Assert that NO file is created — not merely that the exit code is 0, which the bypass also satisfies.

And add the non-git case as its own `It` (it is a different guard, not another opt-out scope):

```powershell
    It 'writes NOTHING and creates no directory when cwd has no .git ancestor' {
        $d = Join-Path ([IO.Path]::GetTempPath()) ("nogit-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        $h = New-CleanHome; $tx = New-Transcript
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $d $tx) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            Test-Path -LiteralPath (Join-Path $d '.clavity') | Should -BeFalse -Because 'a session outside a repo has no project to attribute reaching to'
        } finally { Remove-Item $d,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

- [ ] **Step 2: Run them and watch them fail**

```
pwsh -Command "Invoke-Pester -Path scripts/tests/agy-discipline-reaching.Tests.ps1 -Output Detailed"
```

Expected: exactly two FAIL — the new `root-from-subdir` case of the `-ForEach` block (on `Get-Record $r | Should -BeNullOrEmpty`, because a row was written) and the non-git test (on `Test-Path ... | Should -BeFalse`, because `.clavity` was created). The `workspace` and `global` cases must still PASS; if either of those breaks, you changed behaviour the fix was meant to preserve. **If a new case passes here, stop — the guard you are about to add already exists and this plan is out of date.**

- [ ] **Step 3: Replace lines 51-66 of the dotnet hook**

Replace this block:

```bash
if [ -f "$cwd_path/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  exit 0
fi

# Repo root by walking up for .git, in-shell. `git rev-parse --show-toplevel` is more precise but costs a
# process start, and process COUNT is the entire budget here. A .git entry matches as a directory (normal
# clone) or a file (worktree/submodule). Fallback stays cwd, so a non-repo cwd behaves as before.
root=$cwd_path
_d=$cwd_path
while [ -n "$_d" ] && [ "$_d" != "/" ] && [ "$_d" != "." ]; do
  if [ -e "$_d/.git" ]; then root=$_d; break; fi
  _p=${_d%/*}
  [ "$_p" = "$_d" ] && break
  [ -z "$_p" ] && break
  _d=$_p
done
```

with:

```bash
# The GLOBAL opt-out does not depend on the repo root, so it is checked first and cheaply.
[ -f "$HOME/.claude/.no-agy" ] && exit 0

# Repo root by walking up for .git, in-shell. `git rev-parse --show-toplevel` is more precise but costs a
# process start, and process COUNT is the entire budget here. A .git entry matches as a directory (normal
# clone) or a file (worktree/submodule).
root=$cwd_path
_d=$cwd_path
while [ -n "$_d" ] && [ "$_d" != "/" ] && [ "$_d" != "." ]; do
  if [ -e "$_d/.git" ]; then root=$_d; break; fi
  _p=${_d%/*}
  [ "$_p" = "$_d" ] && break
  [ -z "$_p" ] && break
  _d=$_p
done

# NO REPOSITORY, NO ROW. $root is reassigned ONLY when the walk finds a .git, so a .git under $root here is
# exactly equivalent to "the walk succeeded" - no flag variable is needed, and testing $cwd_path instead
# would reintroduce the subdirectory bug fixed directly below. A session outside any repo has no project to
# attribute reaching to, so the row would be unattributable anyway.
[ -e "$root/.git" ] || exit 0

# WORKSPACE OPT-OUT, CHECKED AFTER THE WALK - this is the fix. Checking only $cwd_path meant a .no-agy at
# the repo ROOT did not suppress a session launched in a SUBDIRECTORY, while the write below still landed
# in that root. MEASURED: cwd=repo/src with repo/.no-agy present WROTE a row; cwd=repo wrote nothing.
# Both paths are tested: a .no-agy in a subdirectory still suppresses that subdirectory.
if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
  exit 0
fi
```

- [ ] **Step 4: Copy the file verbatim to the classic driver**

```bash
cp clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh clavity-classic/plugin/hooks/agy-discipline-reaching.sh
diff clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh clavity-classic/plugin/hooks/agy-discipline-reaching.sh && echo "IDENTICAL"
```

Expected: `IDENTICAL`.

- [ ] **Step 5: Run the suite and watch them pass**

```
pwsh -Command "Invoke-Pester -Path scripts/tests/agy-discipline-reaching.Tests.ps1 -Output Detailed"
```

Expected: PASS, all tests including the two new ones and every pre-existing regression.

- [ ] **Step 6: Prove the fix is load-bearing**

Temporarily delete the `[ -e "$root/.git" ] || exit 0` line, re-run, confirm the non-git test FAILS, then restore it. A guard no test can kill is a guard you have not verified.

- [ ] **Step 7: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh clavity-classic/plugin/hooks/agy-discipline-reaching.sh scripts/tests/agy-discipline-reaching.Tests.ps1
git commit -m "fix(hooks): .no-agy did not suppress a subdirectory launch, and non-git dirs got a .clavity/"
```

---

## Task 2: Hook — schema v:3

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh:40-44` and `:76-80`
- Modify: `clavity-classic/plugin/hooks/agy-discipline-reaching.sh` (copy)
- Test: `scripts/tests/agy-discipline-reaching.Tests.ps1`

- [ ] **Step 1: Update the `Payload` test helper at `:67`**

Replace:

```powershell
        function Payload { param([string]$Cwd, [string]$Tx, [string]$Reason = 'prompt_input_exit', [string]$Sid = 'sess-1')
            $o = @{ cwd = ($Cwd -replace '\\','/'); session_id = $Sid; hook_event_name = 'SessionEnd'; reason = $Reason }
            if ($null -ne $Tx) { $o.transcript_path = ($Tx -replace '\\','/') }
            $o | ConvertTo-Json -Compress
        }
```

with:

```powershell
        function Payload { param([string]$Cwd, [string]$Tx, [string]$Source = 'startup', [string]$Sid = 'sess-1', [string]$Model = 'claude-opus-5')
            $o = @{ cwd = ($Cwd -replace '\\','/'); session_id = $Sid; hook_event_name = 'SessionStart'; source = $Source; model = $Model }
            if ($null -ne $Tx) { $o.transcript_path = ($Tx -replace '\\','/') }
            $o | ConvertTo-Json -Compress
        }
```

**Any existing call passing `-Reason 'x'` must become `-Source 'x'`.** Search the file for `-Reason` and update each.

- [ ] **Step 2: Add the schema test**

```powershell
    It 'writes schema v:3 with source and model, and no reason field' {
        $r = New-TempRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx -Source 'compact' -Model 'claude-opus-5[1m]') -Env @{ HOME = $h } | Out-Null
            $rec = Get-Record $r
            $rec.Last.v              | Should -Be 3
            $rec.Last.source         | Should -BeExactly 'compact'
            $rec.Last.model          | Should -BeExactly 'claude-opus-5[1m]'
            $rec.Last.scan_status    | Should -BeExactly 'deferred'
            $rec.Last.PSObject.Properties.Name | Should -Not -Contain 'reason' -Because 'source says how a session BEGAN; reason said how it ended'
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

- [ ] **Step 3: Run and watch it fail**

```
pwsh -Command "Invoke-Pester -Path scripts/tests/agy-discipline-reaching.Tests.ps1 -Output Detailed"
```

Expected: FAIL on `$rec.Last.v | Should -Be 3` (it is 2).

- [ ] **Step 4: Change the extraction block at `:40-44`**

Replace:

```bash
cwd=''; sid=''; reason=''; tx=''
[[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]             && cwd=${BASH_REMATCH[1]}
[[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]      && sid=${BASH_REMATCH[1]}
[[ $input =~ \"reason\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]          && reason=${BASH_REMATCH[1]}
[[ $input =~ \"transcript_path\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && tx=${BASH_REMATCH[1]}
```

with (note `src`, not `source` — `source` is a bash builtin and shadowing it invites confusion):

```bash
cwd=''; sid=''; src=''; model=''; tx=''
[[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]             && cwd=${BASH_REMATCH[1]}
[[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]      && sid=${BASH_REMATCH[1]}
[[ $input =~ \"source\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]          && src=${BASH_REMATCH[1]}
[[ $input =~ \"model\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]           && model=${BASH_REMATCH[1]}
[[ $input =~ \"transcript_path\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && tx=${BASH_REMATCH[1]}
```

- [ ] **Step 5: Change the emit block at `:76-80`**

Replace:

```bash
# v:2 is the CAPTURE shape. v:1 was the analyse-at-SessionEnd shape and SHIPPED in v17, so both can coexist
# on an upgraded machine; the report reads each by its own version. Values are emitted exactly as they
# arrived - already escaped - so no re-escaping step exists to get wrong.
printf '{"v":2,"session_id":"%s","timestamp":"%s","reason":"%s","transcript_path":"%s","scan_status":"%s"}\n' \
  "$sid" "$ts" "$reason" "$tx" "$status" >> "$out/discipline-reaching.jsonl" 2>/dev/null
```

with:

```bash
# v:3 is the SessionStart capture shape. v:1 (analyse-at-SessionEnd) SHIPPED in v17 and v:2 (SessionEnd
# capture) exists on dev machines, so all three can coexist on an upgraded machine; the report reads each by
# its own version rather than guessing. Values are emitted exactly as they arrived - already JSON-escaped by
# the caller - so no re-escaping step exists to get wrong. `model` is recorded and deliberately NOT reported:
# capture is the irreversible half, and a field not written at session N cannot be recovered at N+1.
printf '{"v":3,"session_id":"%s","timestamp":"%s","source":"%s","model":"%s","transcript_path":"%s","scan_status":"%s"}\n' \
  "$sid" "$ts" "$src" "$model" "$tx" "$status" >> "$out/discipline-reaching.jsonl" 2>/dev/null
```

- [ ] **Step 6: Update the file header at `:2-3`**

Replace:

```bash
# AGY-ANOMALIES discipline-reaching recorder (plugin-shipped). SessionEnd. CAPTURE ONLY, NO SUBPROCESSES.
# ROADMAP section 0 step 1a. Design + measurements: docs/superpowers/specs/2026-08-04-discipline-efficacy-design.md
```

with:

```bash
# AGY-ANOMALIES discipline-reaching recorder (plugin-shipped). SessionStart. CAPTURE ONLY, NO SUBPROCESSES.
# ROADMAP section 0 step 1a. Design + measurements: docs/superpowers/specs/2026-08-05-sessionstart-capture-design.md
```

- [ ] **Step 7: Rewrite the rationale block at `:8-17`**

The current block explains the subprocess-free design as a response to teardown cancellation. That was the DURATION theory, and it is wrong — the cause was that `${CLAUDE_PLUGIN_ROOT}` does not resolve at `SessionEnd`. Leaving it means the next reader inherits the wrong model from the code. Replace the whole block with:

```bash
# WHY IT IS WRITTEN WITHOUT jq, date, OR git.
# NOT because of teardown pressure - that was a wrong diagnosis that cost three rounds. The real cause of
# the v17 failure was that ${CLAUDE_PLUGIN_ROOT} DOES NOT RESOLVE at SessionEnd (cancelled 3/3 with the
# variable at 20,9s / 1,5s / 0,6s; an absolute path from the same manifest worked 2/2 - one axis varied,
# the other never). Duration was a confound: a SLOWER hook registered elsewhere survived.
# The subprocess-free form is kept anyway on its own merits: a hook that runs at EVERY session start should
# be cheap, and the rewrite carries three fixes worth keeping - byte-exact Windows paths, CR stripping, and
# pipe-safe stdin.
#
# WHY RAW PASSTHROUGH IS SAFE - the trick that removes jq from the WRITE side too. The payload already
# holds each value JSON-ESCAPED. Copying that escaped text straight into the output re-emits it
# byte-for-byte, so nothing is unescaped and re-escaped - which is exactly where an earlier version
# corrupted Windows paths (@tsv doubled every backslash). `[^"]*` is the correct extractor because a double
# quote is an ILLEGAL character in a Windows filename, so no value here can contain one.
```

- [ ] **Step 8: Copy to classic and verify identical**

```bash
cp clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh clavity-classic/plugin/hooks/agy-discipline-reaching.sh
diff clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh clavity-classic/plugin/hooks/agy-discipline-reaching.sh && echo "IDENTICAL"
```

- [ ] **Step 9: Run and watch it pass**

```
pwsh -Command "Invoke-Pester -Path scripts/tests/agy-discipline-reaching.Tests.ps1 -Output Detailed"
```

Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh clavity-classic/plugin/hooks/agy-discipline-reaching.sh scripts/tests/agy-discipline-reaching.Tests.ps1
git commit -m "feat(hooks): schema v:3 - source replaces reason, model recorded"
```

---

## Task 3: Manifests — register on SessionStart, delete the SessionEnd block

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/hooks.json:50-56` and `:66-72`
- Modify: `clavity-classic/plugin/hooks/hooks.json` (same two blocks)
- Test: `scripts/tests/plugin-hooks-registration.Tests.ps1`

- [ ] **Step 1: Write the failing registration test**

This suite asserts registration for seven hooks and has never covered this one — which is exactly why v17's broken `SessionEnd` registration was never examined by any structural gate. Add, following the file's established `-ForEach` idiom:

```powershell
    It 'registers agy-discipline-reaching.sh on SessionStart startup|resume|clear|compact - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        $m = $script:Manifests[$Driver]
        $matchers = @(Get-OwningMatchers -Manifest $m -Event 'SessionStart' -Script 'agy-discipline-reaching.sh')
        $matchers.Count | Should -Be 1 -Because 'exactly one SessionStart object may own this hook'
        $matchers[0] | Should -BeExactly 'startup|resume|clear|compact' -Because 'the owner ruled it fires on all four sources'
    }

    It 'registers agy-discipline-reaching.sh on SessionEnd NOWHERE - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        $m = $script:Manifests[$Driver]
        @(Get-OwningMatchers -Manifest $m -Event 'SessionEnd' -Script 'agy-discipline-reaching.sh') |
            Should -BeNullOrEmpty -Because '${CLAUDE_PLUGIN_ROOT} does not resolve at SessionEnd; the hook is cancelled and writes nothing'
    }
```

- [ ] **Step 2: Run and watch both fail**

```
pwsh -Command "Invoke-Pester -Path scripts/tests/plugin-hooks-registration.Tests.ps1 -Output Detailed"
```

Expected: the `SessionStart` test FAILS (`Count` is 0), the `SessionEnd` test FAILS (it finds one).

- [ ] **Step 3: Add the hook to the existing SessionStart block**

In `clavity-dotnet/plugin/hooks/hooks.json`, the block at `:50-56` currently reads:

```json
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-anomaly-reminder.sh\"" },
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-anomaly-model-notice.sh\"" }
        ]
      }
```

Add a third entry:

```json
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-anomaly-reminder.sh\"" },
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-anomaly-model-notice.sh\"" },
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-discipline-reaching.sh\"", "timeout": 10 }
        ]
      }
```

This block is reused deliberately: those two hooks are observed firing in production under that matcher, so the registration is one already known to work.

- [ ] **Step 4: Delete the whole SessionEnd block**

Remove `:66-72` entirely — the trailing comma on the `PreCompact` block must go too, since `SessionEnd` was the last key:

```json
    "SessionEnd": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-discipline-reaching.sh\"", "timeout": 10 }
        ]
      }
    ]
```

Delete the key, not just its inner entry. An empty event registration is a listener that resolves nothing and still reads as though teardown capture exists.

- [ ] **Step 5: Verify the JSON still parses, both drivers**

```bash
node -e "JSON.parse(require('fs').readFileSync('clavity-dotnet/plugin/hooks/hooks.json','utf8')); console.log('dotnet OK')"
```

Expected: `dotnet OK`. A dangling comma after deleting the last key is the likely failure.

- [ ] **Step 6: Apply the identical change to classic and verify**

```bash
node -e "JSON.parse(require('fs').readFileSync('clavity-classic/plugin/hooks/hooks.json','utf8')); console.log('classic OK')"
```

Note: the two `hooks.json` files are **not** byte-identical (classic registers `agy-drive-session-reset.sh`, which dotnet does not). Do not `cp` this one — edit both.

- [ ] **Step 7: Run the registration suite and the parity gate**

```
pwsh -Command "Invoke-Pester -Path scripts/tests/plugin-hooks-registration.Tests.ps1 -Output Detailed"
bash scripts/check-seed-artifacts-synced.sh
```

Expected: Pester PASS including `ships no hook file that is reachable from nowhere` (which would have caught deleting the `SessionEnd` block without adding the `SessionStart` entry). Sync check exits 0.

- [ ] **Step 8: Commit**

```bash
git add clavity-dotnet/plugin/hooks/hooks.json clavity-classic/plugin/hooks/hooks.json scripts/tests/plugin-hooks-registration.Tests.ps1
git commit -m "fix(hooks): register the recorder on SessionStart, delete the SessionEnd block"
```

---

## Task 4: Report — read v:3

`scripts/discipline-reaching-report.ps1:132` routes any unrecognised version to `$unsupported` and drops it. Shipping `v:3` rows without this makes the recorder write rows the only consumer discards.

**Files:**
- Modify: `scripts/discipline-reaching-report.ps1:40-41`, `:128-132`
- Test: `scripts/tests/discipline-reaching-report.Tests.ps1`

- [ ] **Step 1: Add a v:3 fixture helper and a failing test**

In `scripts/tests/discipline-reaching-report.Tests.ps1`, after `CapRec` (which ends at `:41`):

```powershell
        function CapRec3 { param([string]$Tx, [string]$Sid = 'cap3', [string]$Source = 'startup', [string]$Ts = '2026-08-05T00:00:00Z')
            (@{ v=3; session_id=$Sid; timestamp=$Ts; source=$Source; model='claude-opus-5';
                transcript_path=$Tx; scan_status='deferred' } | ConvertTo-Json -Compress)
        }
```

And a test:

```powershell
    It 'COUNTS a v:3 row instead of routing it to unsupported' {
        $tx = New-ScanTranscript
        $d = New-Store @( (CapRec3 $tx) )
        try {
            $o = Run $d
            $o | Should -Match 'Sessions recorded\s*:\s*1'
            $o | Should -Not -Match 'unsupported schema version'
            $o | Should -Match 'reached the model, stamped\s*:\s*2' -Because 'the fixture transcript holds 2 stamped deliveries'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

Asserting the total, not merely the absence of a skip line: the current path fails by silently incrementing a counter, which a loose assertion passes.

- [ ] **Step 2: Run and watch it fail**

```
pwsh -Command "Invoke-Pester -Path scripts/tests/discipline-reaching-report.Tests.ps1 -Output Detailed"
```

Expected: FAIL — `Sessions recorded : 0` and an `unsupported schema version : 1` line.

- [ ] **Step 3: Add the constant at `:40-41`**

Replace:

```powershell
$SCHEMA_ANALYSED = 1   # v1: counts were computed at SessionEnd (SHIPPED in v17)
$SCHEMA_CAPTURE  = 2   # v2: the row names a transcript; THIS script does the counting
```

with:

```powershell
$SCHEMA_ANALYSED  = 1   # v1: counts were computed at SessionEnd (SHIPPED in v17 - real machines hold these)
$SCHEMA_CAPTURE   = 2   # v2: SessionEnd capture; never shipped, dev machines only
$SCHEMA_CAPTURE_3 = 3   # v3: SessionStart capture. `source` replaces `reason`; adds `model`
```

- [ ] **Step 4: Widen the dispatch at `:128-132`**

Replace:

```powershell
    if ($v -eq $SCHEMA_CAPTURE) {
```

with:

```powershell
    if ($v -eq $SCHEMA_CAPTURE -or $v -eq $SCHEMA_CAPTURE_3) {
```

Both capture shapes carry `transcript_path` and defer the scan, so they expand identically. The version is still recorded on the row for the source-distribution bucketing in Task 8.

- [ ] **Step 5: Run and watch it pass**

Expected: PASS, and every pre-existing `v:1`/`v:2` test still green.

- [ ] **Step 6: Commit**

```bash
git add scripts/discipline-reaching-report.ps1 scripts/tests/discipline-reaching-report.Tests.ps1
git commit -m "feat(scripts): the report reads v:3 rows instead of discarding them"
```

---

## Task 5: Report — deduplicate by session_id

Firing on all four sources means one session emits `1 + clears + compactions` rows. A `compact` fire reuses the session's `session_id` (measured), so dedup is load-bearing rather than a no-op.

**Files:**
- Modify: `scripts/discipline-reaching-report.ps1` (new function + call site after the parse loop at `:134`)
- Test: `scripts/tests/discipline-reaching-report.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

```powershell
    It 'collapses many rows of ONE session into one record, keeping the earliest source' {
        $tx = New-ScanTranscript
        $d = New-Store @(
            (CapRec3 $tx -Sid 'S1' -Source 'startup' -Ts '2026-08-05T08:00:00Z')
            (CapRec3 $tx -Sid 'S1' -Source 'compact' -Ts '2026-08-05T12:00:00Z')
            (CapRec3 $tx -Sid 'S1' -Source 'compact' -Ts '2026-08-05T16:00:00Z')
        )
        try {
            $o = Run $d
            $o | Should -Match 'Sessions recorded\s*:\s*1' -Because 'three fires, one session'
            $o | Should -Match 'reached the model, stamped\s*:\s*2' -Because 'the transcript must be counted ONCE, not three times'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'orders -Last N by the LATEST fire, not the earliest' {
        $tx = New-ScanTranscript
        $d = New-Store @(
            (CapRec3 $tx -Sid 'LONG'  -Source 'startup' -Ts '2026-08-05T08:00:00Z')
            (CapRec3 $tx -Sid 'SHORT' -Source 'startup' -Ts '2026-08-05T12:00:00Z')
            (CapRec3 $tx -Sid 'LONG'  -Source 'compact' -Ts '2026-08-05T18:00:00Z')
        )
        try {
            $o = Run $d -Last 1
            $o | Should -Match 'Sessions recorded\s*:\s*1'
            $o | Should -Match 'LONG' -Because 'LONG is still active at 18:00; ranked by birth it would sort older than SHORT and be dropped'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

The second fixture is built so slicing-before-dedup gives a different answer than dedup-before-slicing. A fixture where both orders agree tests nothing.

**Note:** this test requires the collapsed record to expose its `session_id` in output. Task 7 adds the `PROVISIONAL`/`NOT SCANNED` sections that print ids; if no section prints an id at this point, assert on `Sessions recorded : 1` alone here and add the `LONG` assertion in Task 7.

- [ ] **Step 2: Run and watch them fail**

Expected: the first FAILS with `Sessions recorded : 3` and tripled counts.

- [ ] **Step 3: Add the collapse function above the parse loop**

Insert immediately before `Write-Output 'AGY-ANOMALIES discipline reaching'` (currently `:105`):

```powershell
function Merge-SessionRows {
    <#
      Collapse rows by session_id. TWO DIFFERENT QUESTIONS, deliberately answered by two different rows:
        - CONTENT comes from the EARLIEST row - it names how the session ORIGINATED (source=startup rather
          than the compact that followed).
        - RECENCY comes from the LATEST row. -Last N must rank a session by its most recent activity, not
          its birth: otherwise a session started at 08:00 and still alive at 18:00 sorts older than twenty
          short midday ones, and -Last 20 drops the most active session on the machine.
      transcript_path is the ONE EXCEPTION to content-from-earliest. Both observed payloads name
      <session_id>.jsonl, so a stable id implies a stable path - but that is a STRUCTURAL INFERENCE from a
      naming convention seen twice, not a measurement. If the paths ever disagree, prefer the LATEST and
      say so rather than silently naming a stale transcript.
      A row with no session_id cannot be collapsed and is passed through as its own session.
    #>
    param([object[]]$Rows)
    $out = [System.Collections.Generic.List[object]]::new()
    $groups = [ordered]@{}
    foreach ($r in $Rows) {
        $sid = if ($r.PSObject.Properties.Name -contains 'session_id') { [string]$r.session_id } else { '' }
        if ([string]::IsNullOrWhiteSpace($sid)) { $out.Add($r); continue }
        if (-not $groups.Contains($sid)) { $groups[$sid] = [System.Collections.Generic.List[object]]::new() }
        $groups[$sid].Add($r)
    }
    foreach ($sid in $groups.Keys) {
        $g = @($groups[$sid] | Sort-Object -Property @{ Expression = { [string]$_.timestamp } })
        $keep = $g[0]
        $last = $g[-1]
        $add = { param($n,$v) $keep | Add-Member -NotePropertyName $n -NotePropertyValue $v -Force }
        & $add 'first_seen' ([string]$keep.timestamp)
        & $add 'last_seen'  ([string]$last.timestamp)
        & $add 'fire_count' $g.Count
        $paths = @($g | ForEach-Object {
            if ($_.PSObject.Properties.Name -contains 'transcript_path') { [string]$_.transcript_path } else { '' }
        } | Where-Object { $_ -ne '' } | Sort-Object -Unique)
        if ($paths.Count -gt 1) {
            & $add 'transcript_path' ([string]$last.transcript_path)
            & $add 'path_disagreement' $true
        }
        $out.Add($keep)
    }
    return $out.ToArray()
}
```

- [ ] **Step 4: Call it, and move the `-Last` slice after it**

Delete the raw-line slice at `:120`:

```powershell
if ($Last -gt 0 -and $raw.Count -gt $Last) { $raw = $raw[-$Last..-1] }
```

That line slices raw LINES while the help text at `:26` promises "the last N recorded sessions". Those coincided only while one session meant one row.

Then immediately after the parse loop closes (currently `:134`, the `}` after `$rows += $o`), insert:

```powershell
# Collapse BEFORE slicing. Slicing first makes -Last 20 return however many distinct sessions happen to
# fall in the last 20 lines - the number stays plausible while its meaning changes, which is the failure
# this report exists to refuse.
$rows = @(Merge-SessionRows -Rows $rows)
$rows = @($rows | Sort-Object -Property @{ Expression = { [string]$_.last_seen } })
if ($Last -gt 0 -and $rows.Count -gt $Last) { $rows = $rows[-$Last..-1] }
```

- [ ] **Step 5: Run and watch them pass**

- [ ] **Step 6: Commit**

```bash
git add scripts/discipline-reaching-report.ps1 scripts/tests/discipline-reaching-report.Tests.ps1
git commit -m "feat(scripts): collapse rows by session_id, order -Last N by latest activity"
```

---

## Task 6: Report — expand transcripts only after dedup and slicing

`Expand-CaptureRow` is the expensive step: it `Select-String`s and `jq`s a whole transcript, and `:131` invokes it per-row inside the parse loop. A session with fifteen `compact` rows would read the same multi-hundred-megabyte transcript fifteen times.

**Files:**
- Modify: `scripts/discipline-reaching-report.ps1:128-134` and the block added in Task 5

- [ ] **Step 1: Remove expansion from the parse loop**

Replace:

```powershell
    if ($v -eq $SCHEMA_CAPTURE -or $v -eq $SCHEMA_CAPTURE_3) {
        # v2 names a transcript and defers the analysis to HERE, where there is no time limit. Scanning at
        # SessionEnd was CANCELLED on shipped v17 twice, writing nothing, so the work moved to this script.
        $o = Expand-CaptureRow -Row $o
    } elseif ($v -ne $SCHEMA_ANALYSED) { $unsupported++; continue }
```

with:

```powershell
    if ($v -eq $SCHEMA_CAPTURE -or $v -eq $SCHEMA_CAPTURE_3) {
        # A capture row names a transcript and defers the scan. The scan does NOT happen here: it happens
        # after dedup and slicing, so a session's fifteen compact rows read their transcript ONCE, not
        # fifteen times. (Scanning at SessionEnd was CANCELLED on shipped v17 twice, writing nothing, which
        # is why the analysis lives in this script at all.)
        $o | Add-Member -NotePropertyName 'needs_scan' -NotePropertyValue $true -Force
    } elseif ($v -ne $SCHEMA_ANALYSED) { $unsupported++; continue }
```

- [ ] **Step 2: Expand after the slice**

Immediately after the `-Last` slice added in Task 5:

```powershell
# Pipeline order: parse -> collapse -> slice -> EXPAND. This bounds transcript reads to N.
$rows = @($rows | ForEach-Object {
    if ($_.PSObject.Properties.Name -contains 'needs_scan' -and $_.needs_scan) { Expand-CaptureRow -Row $_ } else { $_ }
})
```

- [ ] **Step 3: Run the suite**

```
pwsh -Command "Invoke-Pester -Path scripts/tests/discipline-reaching-report.Tests.ps1 -Output Detailed"
```

Expected: PASS. Every prior test still green — this is a pure reordering.

- [ ] **Step 4: Commit**

```bash
git add scripts/discipline-reaching-report.ps1
git commit -m "perf(scripts): scan each transcript once, after dedup and slicing"
```

---

## Task 7: Report — the provisional bucket and the three-way partition

Under `SessionEnd` a row existed only after its session finished, so every scanned transcript was complete. Under `SessionStart` the row lands at turn zero, so running the report while another session is live scans a transcript still being written — and that session reports `fired: 0` under `scanned cleanly`, indistinguishable from a session where the discipline genuinely never reached.

**Files:**
- Modify: `scripts/discipline-reaching-report.ps1` (`Expand-CaptureRow` tail at `:97-102`, partition at `:143-144`, output at `:154-180`)
- Test: `scripts/tests/discipline-reaching-report.Tests.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
    It 'reports a still-being-written transcript as provisional, not as scanned cleanly' {
        $tx = New-ScanTranscript
        $d = New-Store @( (CapRec3 $tx -Sid 'LIVE') )
        try {
            (Get-Item -LiteralPath $tx).LastWriteTimeUtc = (Get-Date).ToUniversalTime()
            $o = Run $d
            $o | Should -Match 'PROVISIONAL'
            $o | Should -Match 'scanned cleanly\s*:\s*0' -Because 'a live session is not a completed one'
            $o | Should -Match 'reached the model, stamped\s*:\s*0' -Because 'a partial count must not enter the DISPATCH RELAY totals'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports an OLD transcript as scanned cleanly, not provisional' {
        $tx = New-ScanTranscript
        $d = New-Store @( (CapRec3 $tx -Sid 'DONE') )
        try {
            (Get-Item -LiteralPath $tx).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddHours(-3)
            $o = Run $d
            $o | Should -Match 'scanned cleanly\s*:\s*1'
            $o | Should -Match 'reached the model, stamped\s*:\s*2'
            $o | Should -Not -Match 'PROVISIONAL'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

Driven by setting the fixture's mtime, not by racing a live writer.

- [ ] **Step 2: Run and watch the first fail**

Expected: FAIL — no `PROVISIONAL` in the output and `scanned cleanly : 1`.

- [ ] **Step 3: Add the freshness check to `Expand-CaptureRow`**

Replace the success tail at `:97-102`:

```powershell
    & $add 'dispatch_nudges'           (@($classified | Where-Object { $_ -like 'N *' }).Count)
    & $add 'dispatch_fired'            (@($classified | Where-Object { $_ -like 'F *' }).Count)
    & $add 'dispatch_nudges_unstamped' (@($classified | Where-Object { $_ -like 'L *' }).Count)
    & $add 'compactions'               (@($classified | Where-Object { $_ -like 'C *' }).Count)
    & $add 'scan_status' 'ok'
    return $Row
```

with:

```powershell
    & $add 'dispatch_nudges'           (@($classified | Where-Object { $_ -like 'N *' }).Count)
    & $add 'dispatch_fired'            (@($classified | Where-Object { $_ -like 'F *' }).Count)
    & $add 'dispatch_nudges_unstamped' (@($classified | Where-Object { $_ -like 'L *' }).Count)
    & $add 'compactions'               (@($classified | Where-Object { $_ -like 'C *' }).Count)

    # PROVISIONAL: the transcript is still being written, so these counts are INCOMPLETE - not wrong. Every
    # dispatch counted really happened; more may follow. Sample the mtime AFTER the scan, never before: a
    # transcript written to DURING the scan is exactly the in-flight case this bucket exists for, and only
    # an after-reading sample can see it. This also subsumes the session running the report, whose own
    # transcript was appended to moments ago - which matters because a PowerShell script is never handed its
    # caller's session_id and cannot identify itself any other way.
    # mtime is a heuristic and it FAILS SAFE: a backup or antivirus pass that merely touches a file pushes a
    # finished session into provisional for a few minutes, moving a complete session OUT of the clean total.
    # The opposite error - a live session counted as complete - is the one this exists to prevent.
    $fresh = $false
    try { $fresh = ((Get-Item -LiteralPath $tx).LastWriteTimeUtc -gt (Get-Date).ToUniversalTime().AddMinutes(-15)) } catch { $fresh = $false }
    & $add 'scan_status' $(if ($fresh) { 'provisional' } else { 'ok' })
    return $Row
```

- [ ] **Step 4: Replace the two-way partition at `:143-144`**

Replace:

```powershell
$counted = @($rows | Where-Object { $null -ne (Get-Num $_ 'dispatch_nudges') })
$degraded = @($rows | Where-Object { $null -eq (Get-Num $_ 'dispatch_nudges') })
```

with:

```powershell
# THREE disjoint sets keyed on scan_status, NOT on null-ness. Null-ness worked as a discriminator only
# while "has counts" and "is complete" meant the same thing; `provisional` is exactly where they come
# apart - it has non-null counts and is not complete, so a null-based split would blend a partial count
# into the totals.
function Get-Status { param($Row)
    if ($Row.PSObject.Properties.Name -notcontains 'scan_status') { return '' }
    return [string]$Row.scan_status
}
$counted     = @($rows | Where-Object { (Get-Status $_) -eq 'ok' -and $null -ne (Get-Num $_ 'dispatch_nudges') })
$provisional = @($rows | Where-Object { (Get-Status $_) -eq 'provisional' })
$degraded    = @($rows | Where-Object { (Get-Status $_) -ne 'ok' -and (Get-Status $_) -ne 'provisional' })
```

**Note on `v:1` rows:** they carry `scan_status` values of `ok` or a degraded name already, so they land correctly without special handling. A `v:1` row whose `scan_status` is `ok` but whose counts are null is impossible by construction, and the extra `$null -ne` guard on `$counted` keeps it out of the totals if one ever appears.

- [ ] **Step 5: Print the provisional section**

After the `NOT SCANNED` block (which ends at `:180`), add:

```powershell
if ($provisional.Count -gt 0) {
    Write-Output ''
    Write-Output 'PROVISIONAL  (still running - counts may grow, and are NOT in the totals above)'
    foreach ($p in $provisional) {
        Write-Output ("  {0}  reached {1}, fired {2}" -f `
            ([string]$p.session_id), (Get-Num $p 'dispatch_nudges'), (Get-Num $p 'dispatch_fired'))
    }
}

# The disagreement guard from Merge-SessionRows is USELESS if nobody is told. A session whose collapsed
# rows named different transcripts had the LATEST path used; that is a silent choice unless surfaced, and
# it would mean the <session_id>.jsonl naming convention this design infers from has changed.
$disagreed = @($rows | Where-Object { $_.PSObject.Properties.Name -contains 'path_disagreement' })
if ($disagreed.Count -gt 0) {
    Write-Output ''
    Write-Output 'TRANSCRIPT PATH DISAGREEMENT  (the latest path was used)'
    foreach ($x in $disagreed) { Write-Output ("  {0} : {1}" -f ([string]$x.session_id), ([string]$x.transcript_path)) }
    Write-Output '  Rows of one session named DIFFERENT transcripts. This design assumes <session_id>.jsonl;'
    Write-Output '  if this line ever appears, that assumption has broken and the dedup key needs revisiting.'
}
```

Nothing is thrown away and nothing is blended: the counts are printed, under their own heading, outside the totals — the same shape as the existing `NOT SCANNED` section and for the same reason.

- [ ] **Step 6: Update the `scanned cleanly` line at `:156-157`**

Replace:

```powershell
Write-Output ("  scanned cleanly : {0}" -f $counted.Count)
Write-Output ("  not scanned     : {0}   (excluded from every total below)" -f $degraded.Count)
```

with:

```powershell
Write-Output ("  scanned cleanly : {0}" -f $counted.Count)
Write-Output ("  provisional     : {0}   (still running - excluded from every total below)" -f $provisional.Count)
Write-Output ("  not scanned     : {0}   (excluded from every total below)" -f $degraded.Count)
```

- [ ] **Step 7: Run and watch them pass**

Expected: PASS. If the `-Last N` ordering test from Task 5 deferred its `LONG` assertion, add it back now — the `PROVISIONAL` section prints session ids.

- [ ] **Step 8: Commit**

```bash
git add scripts/discipline-reaching-report.ps1 scripts/tests/discipline-reaching-report.Tests.ps1
git commit -m "feat(scripts): provisional bucket - a live session is not a completed zero"
```

---

## Task 8: Report — the source distribution, labelled as invocations

**Files:**
- Modify: `scripts/discipline-reaching-report.ps1` (collect during parse; print after `SESSION CONTEXT`)
- Test: `scripts/tests/discipline-reaching-report.Tests.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
    It 'reports the source distribution as INVOCATIONS and keeps legacy reasons out of it' {
        $tx = New-ScanTranscript
        $d = New-Store @(
            (CapRec3 $tx -Sid 'A' -Source 'startup' -Ts '2026-08-05T08:00:00Z')
            (CapRec3 $tx -Sid 'A' -Source 'compact' -Ts '2026-08-05T09:00:00Z')
            (Rec 1 0 0 0 'ok' 'OLD' 1)
        )
        try {
            $o = Run $d
            $o | Should -Match 'HOOK INVOCATIONS'
            $o | Should -Match 'startup\s*:\s*1'
            $o | Should -Match 'compact\s*:\s*1'
            $o | Should -Match 'legacy \(v1/v2\)\s*:\s*1' -Because 'v1 carries an EXIT reason, which answers a different question than a BOOT source'
            $o | Should -Not -Match 'prompt_input_exit' -Because 'an exit reason must never bucket into the boot-source distribution'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

- [ ] **Step 2: Run and watch it fail**

Expected: FAIL — no `HOOK INVOCATIONS` section.

- [ ] **Step 3: Collect the distribution during parse**

Declare beside `$malformed` at `:122`:

```powershell
$rows = @(); $malformed = 0; $unsupported = 0
$sourceCounts = [ordered]@{}; $legacyRows = 0
```

Inside the parse loop, immediately after `$v` is resolved and before the version dispatch:

```powershell
    # Counted per ROW, before dedup - this is a count of hook FIRINGS, not of sessions.
    if ($v -eq $SCHEMA_CAPTURE_3 -and $o.PSObject.Properties.Name -contains 'source') {
        $s = [string]$o.source
        if ([string]::IsNullOrWhiteSpace($s)) { $s = '(unnamed)' }
        if (-not $sourceCounts.Contains($s)) { $sourceCounts[$s] = 0 }
        $sourceCounts[$s]++
    } elseif ($v -eq $SCHEMA_ANALYSED -or $v -eq $SCHEMA_CAPTURE) {
        $legacyRows++
    }
```

- [ ] **Step 4: Print it after the SESSION CONTEXT block**

After the `compactions` block (which ends at `:172`), add:

```powershell
Write-Output ''
Write-Output 'HOOK INVOCATIONS  (firings, NOT sessions - one session fires once per start, clear and compact)'
foreach ($k in $sourceCounts.Keys) { Write-Output ("  {0} : {1}" -f $k, $sourceCounts[$k]) }
if ($legacyRows -gt 0) { Write-Output ("  legacy (v1/v2) : {0}   (they carry an EXIT reason, not a boot source)" -f $legacyRows) }
Write-Output '  These are NOT the `compactions` figure above: that one is derived from the transcript and'
Write-Output '  counts different things. They WILL diverge - a compaction before the plugin was installed'
Write-Output '  appears in one and not the other. A reader who expects them to agree will misread a correct report.'
```

- [ ] **Step 5: Run and watch it pass**

- [ ] **Step 6: Commit**

```bash
git add scripts/discipline-reaching-report.ps1 scripts/tests/discipline-reaching-report.Tests.ps1
git commit -m "feat(scripts): source distribution, labelled as invocations rather than sessions"
```

---

## Task 9: Report — the refusal whose reasons died

`scripts/discipline-reaching-report.ps1:22-24` justifies never saying "sessions run" because `SessionEnd` may not fire and because a machine without `jq` records nothing. This change deletes `SessionEnd` and the hook no longer uses `jq`. **Both premises are void; the rule is still right.** An obsolete justification guarding a correct rule invites exactly the deletion it was written to prevent.

**Files:**
- Modify: `scripts/discipline-reaching-report.ps1:22-24`, `:110`
- Modify: `scripts/tests/discipline-reaching-report.Tests.ps1:14-15`, `:98`

- [ ] **Step 1: Replace the third refusal at `:22-24`**

```powershell
    3. IT NEVER SAYS "SESSIONS RUN", AND ITS REASONS ARE NOT THE ONES THIS FILE USED TO GIVE. The old text
       cited SessionEnd not firing reliably and a machine without jq - both dead: the recorder is on
       SessionStart now and the hook uses no subprocesses. The denominator is STILL unknowable, for four
       reasons that replace them: sessions that ran before the plugin was installed; sessions suppressed by
       .no-agy; sessions outside any git repository, which the recorder now deliberately declines to
       record; and sessions where the registration silently failed - the class this whole item exists to
       fight and still cannot detect from the inside. The last two are consequences of the SessionStart
       design, so this refusal is better founded than it was, not weaker.

    4. "SESSIONS RECORDED" NOW COUNTS DISTINCT SESSIONS, NOT ROWS. It counted rows until dedup existed, and
       the two were equal only because SessionEnd wrote exactly one row per session. The label stays
       honest; the quantity behind it changed, so a v17-era report and a v18 one are not comparable.
```

- [ ] **Step 2: Fix the user-facing message at `:110`**

Replace:

```powershell
    Write-Output 'The recorder writes one row per session at SessionEnd, from the INSTALLED plugin.'
```

with:

```powershell
    Write-Output 'The recorder writes a row at SessionStart (startup, resume, clear and compact), from the'
    Write-Output 'INSTALLED plugin - not from this repo. No rows means it has not fired since installation.'
```

This is what a user sees at the moment they are asking why nothing was recorded. A wrong hint during diagnosis is worse than no hint.

- [ ] **Step 3: Fix the sibling suite's stale premises**

In `scripts/tests/discipline-reaching-report.Tests.ps1`, replace `:14-15`:

```powershell
#   3. SAY "SESSIONS RUN". The denominator is unknowable: sessions predating the install, sessions
#      suppressed by .no-agy, sessions outside a git repo (deliberately unrecorded), and sessions whose
#      registration silently failed. The report says sessions RECORDED - now meaning DISTINCT sessions.
```

and `:98`:

```powershell
            $o | Should -Not -Match '(?i)sessions run' -Because 'sessions predating install, .no-agy opt-outs, non-git dirs and silent registration failures all make the denominator unknowable'
```

Leave `:164-165` and `:178` untouched — they describe the v17 cancellation and the `v:1` schema history, which are true and are the only record of why `v:1` rows exist.

- [ ] **Step 4: Run both report suites**

```
pwsh -Command "Invoke-Pester -Path scripts/tests/discipline-reaching-report.Tests.ps1 -Output Detailed"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/discipline-reaching-report.ps1 scripts/tests/discipline-reaching-report.Tests.ps1
git commit -m "docs(scripts): the sessions-run refusal keeps its rule and loses its dead reasons"
```

---

## Task 10: The remaining stale premises in the hook suite

**Files:**
- Modify: `scripts/tests/agy-discipline-reaching.Tests.ps1:1`, `:214`, `:218`

- [ ] **Step 1: Fix the header at `:1`**

```powershell
# The DISCIPLINE-REACHING recorder (SessionStart). ROADMAP section 0, step 1a. CAPTURE ONLY.
```

- [ ] **Step 2: Rename the vestigial jq test and fix its reason at `:214-220`**

The hook no longer invokes `jq`, so the test's name describes a dependency that no longer exists. It still meaningfully asserts fail-open under a minimal PATH, so it is renamed rather than deleted:

```powershell
    It 'exits 0 under a minimal PATH (the hook spawns no subprocess but mkdir)' {
        $r = New-TempRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h; PATH = $script:NoJqPath }
            $x.ExitCode | Should -Be 0 -Because 'a boot hook must fail open; a non-zero exit at SessionStart helps nobody and risks the session'
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

Leave `:8`, `:89`, `:102` and `:109` untouched — they record the v17 cancellation and the `v:1` history.

- [ ] **Step 3: Run and commit**

```bash
pwsh -Command "Invoke-Pester -Path scripts/tests/agy-discipline-reaching.Tests.ps1 -Output Detailed"
git add scripts/tests/agy-discipline-reaching.Tests.ps1
git commit -m "test(scripts): retire premises the SessionStart move invalidated"
```

---

## Task 11: Documentation the sweeps found

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md:254`
- Modify: `justfile:90`
- Modify: `scripts/README.md:55`
- Modify: `scripts/tests/_partition.md`

- [ ] **Step 1: ROADMAP `:254` — the owner-facing entry, and the worst instance**

Replace:

```markdown
- **1a — MEASURE (in progress).** A `SessionEnd` recorder that answers, from recorded evidence, whether the
  **`PreToolUse` dispatch relay** reaches a driver. Designed in
  `docs/superpowers/specs/2026-08-04-discipline-efficacy-design.md`. It **reads** the transcript; no hook on
```

with:

```markdown
- **1a — MEASURE (in progress).** A `SessionStart` recorder that answers, from recorded evidence, whether
  the **`PreToolUse` dispatch relay** reaches a driver. Designed in
  `docs/superpowers/specs/2026-08-05-sessionstart-capture-design.md` — which supersedes the `SessionEnd`
  registration in the 2026-08-04 spec, because `${CLAUDE_PLUGIN_ROOT}` does not resolve at `SessionEnd` and
  the v17 hook was cancelled and wrote nothing. It **reads** the transcript; no hook on
```

Both halves of the old text were wrong — the event, and the spec it pointed at. This is §0, the owner's stated top priority, so it is the first thing a fresh session reads about this work.

- [ ] **Step 2: `justfile:90`**

```
# Reads the SessionStart recorder's rows (ROADMAP section 0 step 1a). Read-only.
```

Do not touch `:92` — `just --list` shows the LAST comment line as the description, and that one is still accurate.

- [ ] **Step 3: Verify you did not convert the justfile to CRLF**

```bash
grep -c $'\r' justfile
```

Expected: `0`. This has silently gone wrong four times in this repo.

- [ ] **Step 4: `scripts/README.md:55`**

Replace the description cell with:

```
Read-only reader for `.clavity/discipline-reaching.jsonl`: reports whether the AGY-ANOMALIES dispatch relay is reaching a driver. Never folds a `null` count into a zero, never prints a ratio, reports sessions RECORDED (distinct sessions, not runs), and quarantines still-running sessions in a `PROVISIONAL` bucket — each refusal blocks a measured false conclusion
```

The inventory guard `scripts/tests/scripts-readme-inventory.Tests.ps1` checks that entries EXIST, not that descriptions are ACCURATE, so this drift would pass it silently.

- [ ] **Step 5: Re-measure `_partition.md`**

Run the fast half and record the real figures — never hand-edit them to what they ought to be:

```
just test-scripts-fast
```

Update the per-suite lines at `:158-159` and the fast-half totals with the measured values, and append a dated entry describing why the counts moved.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/ROADMAP.md justfile scripts/README.md scripts/tests/_partition.md
git commit -m "docs: repoint the roadmap, recipe and inventory at the SessionStart design"
```

---

## Task 12: Full gate, then the one thing tests cannot prove

- [ ] **Step 1: Run the whole fast half**

```
just test-scripts-fast
```

Expected: all suites pass. This exceeds a two-minute tool timeout — run it backgrounded and block on its own `Tests completed` line, never on a process count.

- [ ] **Step 2: Run the cross-driver parity gate**

```bash
bash scripts/check-seed-artifacts-synced.sh
```

Expected: exit 0.

- [ ] **Step 3: Confirm no stale premise survived**

Use the **Grep tool** (bash `grep` has returned false zeros on these exact strings) for `SessionEnd` across `scripts/`, `clavity-dotnet/plugin/`, `clavity-classic/plugin/`, `justfile` and `clavity-dotnet/ROADMAP.md`. Every surviving hit must be HISTORICAL: the `v:1` schema provenance, the v17 cancellation record, and the CHANGELOGs. If a hit describes the CURRENT event, it was missed.

- [ ] **Step 4: STOP — the remaining verification is the owner's**

Two things cannot be done from inside this session:

1. **A real installer run is impossible while Claude is running** — `InitializeSetup` calls `ClaudeIsRunning()` and aborts with a modal dialog. The owner must run setup with Claude closed.
2. **The post-install measurement.** Every claim that `${CLAUDE_PLUGIN_ROOT}` resolves at `SessionStart` rests on OTHER hooks working there. That is strong inductive evidence and it is not a measurement of THIS hook. **After the plugin is installed, start a session and confirm a real row lands in `.clavity/discipline-reaching.jsonl` with `"v":3`.** The prior design was wrong for three rounds precisely because a plausible inference went unmeasured.

Do not mark this plan complete before that row exists. A green test suite proves the logic; only that row proves the hook runs.

---

## Deferred, with owners

- **`/clear` behaviour is unmeasured.** It is benign if it mints a new `session_id` AND a new transcript; if it mints a new id while reusing the transcript, two records scan one transcript and every dispatch is counted twice. The `settings.local.json` SessionStart probe is still armed to capture it. **Owner: check the first `clear` row that lands, then record the answer in the spec.** Not a blocker — dedup is safe under both.
- **The `.no-agy` subdirectory bypass exists in eight sibling hooks.** Their cost is an unwanted message rather than a write, so it is a different severity and a different change. Logged in `.clavity/local-anomalies.md`. **Owner: schedule separately.**
- **Retention.** Rows per session go from 1 to `1 + clears + compactions` with no rotation. Dedup keeps the reported counts honest regardless, so nothing needs building now.

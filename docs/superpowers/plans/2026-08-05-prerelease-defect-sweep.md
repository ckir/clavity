# Pre-release defect sweep — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `.no-agy` at a repository root suppress all nine agy hooks when Claude is launched from a subdirectory, prove it with tests that can actually fail, and clear three small correctness/naming defects in the same shipped surface.

**Architecture:** Each hook gains the recorder's proven four-step preamble — recover `cwd`, normalize backslashes, check the global opt-out, walk up for `.git` — then checks `.no-agy` at both the repo root and the payload cwd. The same preamble is applied to the `jq`-present path and the degraded no-`jq` path, which collapses the two into identical semantics. Sixteen of the seventeen files are byte-identical driver pairs enforced by an existing parity gate.

**Tech Stack:** Bash (Git Bash on Windows), Pester 5 (PowerShell), `just`, Inno Setup (untouched — hooks ship by recursive wildcard).

**Spec:** `docs/superpowers/specs/2026-08-05-prerelease-defect-sweep-design.md` (owner-confirmed GREEN, 5-round panel).

---

## Read this before Task 1 — five things that will bite you

**1. Line numbers in the spec expire. Anchor on text.** Every edit below is given as a verbatim BEFORE block and a verbatim AFTER block. Match the BEFORE text; do not navigate by line number. Seven of the nine hooks have *two* `.no-agy` sites, the degraded one above the normal one, so editing the degraded site first moves the normal site down by ~12 lines.

**2. Sixteen files are byte-identical pairs.** Every hook edit is two edits — `clavity-dotnet/plugin/hooks/X` and `clavity-classic/plugin/hooks/X`. Never hand-type the second; copy the first. `bash scripts/check-seed-artifacts-synced.sh` is the gate and must exit 0.

**3. These files are LF. Editing has silently converted them to CRLF four times in this repo.** After each task, verify:

```bash
python3 -c "
import sys
for f in sys.argv[1:]:
    d=open(f,'rb').read(); crlf=d.count(b'\r\n'); lf=d.count(b'\n')-crlf
    print(f, 'CRLF' if crlf and not lf else ('MIXED-BROKEN' if crlf else 'LF'))
" clavity-dotnet/plugin/hooks/*.sh clavity-classic/plugin/hooks/*.sh
```

Expected: every line ends `LF`. Any `CRLF` or `MIXED-BROKEN` must be fixed before committing.

**4. Do not trust a bash `grep` that returns zero.** Three false zeros were recorded while writing this plan — text that was plainly present. If a search returns nothing and you expected something, open the file.

**5. `$Cwd -replace '\\', '\\'` is CORRECT. Do not "fix" it.** It looks wrong and a reviewer already
flagged it as a defect. MEASURED in PowerShell:

```
'C:\Users\user\repo\src' -replace '\\','\\'    ->  C:\\Users\\user\\repo\\src   (valid JSON, round-trips)
'C:\Users\user\repo\src' -replace '\\','\\\\'  ->  C:\\\\Users\\\\...           (parses to C:\\Users\\...)
```

The pattern `'\\'` is a regex matching one backslash; the replacement `'\\'` is two literal characters,
because .NET replacement strings treat `$`, not `\`, as the escape. So it doubles them, which is exactly
what a JSON string needs. **The suggested "fix" to `'\\\\'` would quadruple them and introduce the bug it
claimed to remove.** `$Cwd.Replace('\','\\')` is equivalent and may read more clearly; either is fine.

**6. Downstream `$cwd` uses — convert these three, and DO NOT convert the fourth.** Once a hook has
`$cwd_path`, leaving a later bare `$cwd` mixes a normalized and an un-normalized path in one file. MEASURED
2026-08-05, these are every downstream use in the target hooks that sits AFTER the insertion point:

| file | site | action |
|---|---|---|
| `agy-seam-inject.sh` | `head=$(git -C "$cwd" rev-parse HEAD ...)` and `marker="$cwd/.clavity/..."` | → `$cwd_path` (Task 8) |
| `agy-test-audit-reminder.sh` | normal path `[ "$(gate "$cwd")" = "fire" ] \|\| exit 0` | → `$cwd_path` (Task 10) |
| `agy-anomaly-reminder.sh`, `agy-anomaly-model-notice.sh` | the `[ -f "$f" ] \|\| f="$cwd/.clavity/..."` fallback | → `$cwd_path` (Tasks 4 and 9) |

**🔴 The exception — `agy-liveness-check.sh` has `proj_dir="${CLAUDE_PROJECT_DIR:-$cwd}"` well ABOVE the
insertion point. Leave it alone.** `$cwd_path` does not exist yet at that line, so "converting" it would
reference an unset variable and silently resolve `proj_dir` to empty. A blanket find-and-replace of `$cwd`
across these files is therefore **wrong**; convert only the sites listed above.

**🔴 And in `agy-seam-inject.sh`, `$cwd_path` and `$root` are NOT interchangeable — using `$root` for the
marker would be a real regression.** After this work that file contains both, and its `:58-62` states the
contract in its own words:

> *"The marker is CWD-RELATIVE, anchored to the payload's session cwd EXACTLY as the discipline skills
> write it... **Do NOT anchor to git-toplevel: that would diverge from the cwd-relative writer in a
> launched-from-subdir session and defeat the debounce.**"*

So `marker="$cwd_path/.clavity/agy-marks/..."` — normalized, same directory — is correct, and
`marker="$root/..."` is wrong. **`$root` is for the `.no-agy` check and nothing else in this file.** The
plan pushes hard on "walk up to the repo root"; do not let that momentum carry into a line whose own
comment forbids it.

`gate()` in `agy-test-audit-reminder.sh` is safe to pass a new value to — it binds `local cwd="$1"` at
`:20` rather than reading the global, so passing `"$cwd_path"` genuinely changes what it uses. (Checked,
because if it had read the global the instruction would have been a silent no-op.)

**7. Do not hand-verify backslash behaviour in a shell.** The agent harness eats backslashes before bash sees them; two attempts to measure normalization by hand produced contaminated results. **Copy the recorder's line verbatim and let the Pester tests prove it.**

---

---

## 🔴 CORRECTION FOUND DURING EXECUTION (2026-08-05, after Task 4) — READ BEFORE TASKS 5–11

**The normalization form must match where `cwd` came from, and this plan pastes the wrong one into every
normal-path site.** Everything below that says `cwd_path=${cwd//\\\\//}` immediately after a `jq -r`
extraction is WRONG and is a **silent no-op**.

MEASURED, one payload (`{"cwd":"C:\\Users\\user\\repo\\src"}`) through both extractions:

| `cwd` source | value it yields | `${cwd//\\\\//}` | `${cwd//\\//}` |
|---|---|---|---|
| raw `[[ $input =~ ... ]]` | `C:\\Users\\user\\repo\\src` (escaping survives) | ✅ `C:/Users/user/repo/src` | `C://Users//user//repo//src` |
| `jq -r '.cwd'` | `C:\Users\user\repo\src` (jq DECODES) | ❌ **unchanged — matches nothing** | ✅ `C:/Users/user/repo/src` |

So:

- **Normal-path sites (cwd came from `jq -r`) → `cwd_path=${cwd//\\//}`.**
- **Degraded sites (cwd came from the raw `[[ =~ ]]` recovery) → `cwd_path=${cwd//\\\\//}`.** Unchanged.
- Task 3 is correct as written: it *replaced* the jq extraction with the raw one, so it takes the double
  form, and its mutation step proved it.

The recorder is not wrong and was not mis-copied — `agy-discipline-reaching.sh:49` is byte-for-byte what
this plan quotes. It simply reads `cwd` from the raw payload, and the plan carried its line to a place
where `cwd` has already been decoded.

**Add the WHY as a comment at every site**, or the next reader will "unify" the two spellings and
reintroduce this:

```bash
# THE NORMALIZATION FORM MUST MATCH THE EXTRACTION SOURCE. jq -r DECODES the JSON escaping, so cwd holds
# SINGLE backslashes here and the pattern is one escaped backslash. A hook that recovers cwd from the RAW
# payload with [[ =~ ]] keeps the DOUBLE backslashes and needs ${cwd//\\\\//} instead. MEASURED 2026-08-05:
# using the raw form on a jq-decoded value matches nothing and leaves the path untouched - a silent no-op
# that looks exactly like a working fix. Do NOT unify the two spellings.
```

### 🔴 And the reason this nearly shipped: a silence test can pass for the wrong reason

With the wrong form in `agy-anomaly-model-notice.sh`, **the silence test PASSED.** The walk never left the
subdirectory, so the hook could not find the anomalies file and exited quietly — silence produced by a
broken fix, indistinguishable from silence produced by a working kill-switch. Only the **positive control**
went red.

**Every hook task below therefore needs its positive control, and the control is the oracle — not the
silence test.** Where a hook's message depends on a path the walk resolves, treat a green silence test as
no evidence at all. Three panel rounds could not catch this: a panel reasons about the artifact, it never
runs it.

---

## The canonical preamble

This exact block is the fix. It is lifted from `clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh:41-66`, which ships and works. **Copy it; do not retype it and do not "improve" it.**

```bash
# Recover cwd from the raw payload without jq, normalize, then resolve the repo root in-shell.
[[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && cwd=${BASH_REMATCH[1]}
cwd_path=${cwd//\\\\//}
[ -z "$cwd_path" ] && cwd_path="."

# The GLOBAL opt-out does not depend on the repo root, so it is checked first and cheaply.
[ -f "$HOME/.claude/.no-agy" ] && exit 0

# Repo root by walking up for .git, in-shell. A .git entry matches as a directory (normal clone) or a
# file (worktree/submodule).
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

Followed everywhere by the three-candidate check:

```bash
if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
  exit 0
fi
```

**Three rules about this block, each of which was a panel finding:**

- **`cwd_path=${cwd//\\\\//}` is load-bearing.** The walk advances with `${_d%/*}`, which strips on `/` only. Measured: without normalization the loop breaks on iteration 1 and `root` stays where it started — a silent no-op on the only platform this ships to. Normalized paths may contain `//`; that is benign for `[ -e ]` and `${_d%/*}`. **Do not collapse them.**
- **Do NOT add `[ -e "$root/.git" ] || exit 0`.** The recorder has that guard because it writes a file it cannot attribute outside a repo. These hooks do not; adding it would silence nine hooks in every non-repo directory.
- **The exit line is per-hook, not shared.** `exit 2` is non-blocking on `SessionStart` but **blocks the tool call on `PreToolUse`**. Each task below states its own exit behaviour. Copy the preamble; never copy another hook's exit.

---

## File structure

| File | Change | Task |
|---|---|---|
| `scripts/tests/agy-drive-session-reset.Tests.ps1` | **create** | 1 |
| `justfile` | register new suite in `test-scripts-fast` | 2 |
| `clavity-classic/plugin/hooks/agy-drive-session-reset.sh` | root walk (classic-only, deletes files) | 3 |
| `{dotnet,classic}/plugin/hooks/agy-anomaly-model-notice.sh` | root walk, single site | 4 |
| `…/agy-after-reminder.sh` | root walk, two sites | 5 |
| `…/agy-anomaly-capture-reminder.sh` | root walk, two sites | 6 |
| `…/agy-anomaly-dispatch-reminder.sh` | root walk, two sites | 7 |
| `…/agy-seam-inject.sh` | root walk, two sites | 8 |
| `…/agy-anomaly-reminder.sh` | root walk, two sites | 9 |
| `…/agy-test-audit-reminder.sh` | root walk, two sites | 10 |
| `…/agy-liveness-check.sh` | root walk + truthful reported path | 11 |
| `…/agy-discipline-reaching.sh` | comment only (U2) | 12 |
| `scripts/tests/agy-consult-guard.Tests.ps1` | bind `$script:Lib` (U3a) | 13 |
| `…/agy-consult-guard-{lib,pre,post}.sh` | doc line + header rename (U3b, U3c) | 14 |
| `scripts/tests/_partition.md` | re-measure | 15 |

---

## Task 0: Establish a green baseline

**Files:** none — this task only measures.

- [ ] **Step 1: Confirm the tree is clean and record the starting SHA**

```bash
git status --short && git rev-parse HEAD
```

Expected: no output from `status`, then a SHA. Write that SHA down — the capstone in Task 16 reviews `<that SHA>..HEAD`.

- [ ] **Step 2: Confirm the parity gate is green BEFORE you touch anything**

```bash
bash scripts/check-seed-artifacts-synced.sh; echo "exit=$?"
```

Expected: `exit=0`. If it is not 0 now, stop — you cannot attribute a later failure to your own edit.

- [ ] **Step 3: Confirm the fast suite is green**

```bash
just test-scripts-fast
```

Expected: a Pester summary ending `Failed: 0`. Record the `Tests Passed:` number; Task 15 compares against it.

---

## Task 1: Test suite for `agy-drive-session-reset.sh` (U4, part 1)

This hook is the highest-severity file in the set: it **deletes files** rather than printing a message, and it has never had a test. Its suite is written FIRST, against current behaviour, so the Task 3 fix is observable.

**Files:**
- Create: `scripts/tests/agy-drive-session-reset.Tests.ps1`

- [ ] **Step 1: Write the suite**

```powershell
# Pester 5. Covers agy-drive-session-reset.sh, the ONLY hook in the agy set that mutates disk rather
# than emitting a message: it clears the once-per-session driver-guidance flag. A .no-agy bypass here
# deletes a file belonging to a user who opted out - and because the session key defaults to 'default'
# (hook :17), it can be a DIFFERENT, concurrent, opted-in session's flag.
Describe 'agy-drive-session-reset.sh' {
  BeforeAll {
    . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
    # House style, matching every sibling suite: BeforeAll lives INSIDE Describe, the hook binds to
    # $script:Hook, and the repo root is derived with Split-Path rather than a relative Join-Path.
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Hook = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks/agy-drive-session-reset.sh'

    # Build the payload WITHOUT the repo-wide `-replace '\\','/'` convention. Every other suite
    # forward-slashes cwd, which is exactly why the Windows walk bug survived: a POSIX-shaped path
    # cannot exercise it. These tests feed the shape the real payload actually has.
    function New-RawPayload {
        param([string]$Cwd, [string]$Source = 'startup')
        $escaped = $Cwd -replace '\\', '\\'
        '{"cwd":"' + $escaped + '","source":"' + $Source + '","hook_event_name":"SessionStart"}'
    }

    function New-FlagDir {
        $d = Join-Path ([IO.Path]::GetTempPath()) ("drv-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        return $d
    }
  }

    It 'CLEARS the session flag on source=startup (positive control)' {
        $repo = New-TempRepo
        $flags = New-FlagDir
        $flag = Join-Path $flags '.active-drive-session-default'
        New-Item -ItemType File -Path $flag -Force | Out-Null

        Invoke-BashHook -HookPath $script:Hook -Payload (New-RawPayload -Cwd $repo) `
            -Env @{ CLAVITY_GOLDEN_HEADER = $flags; USERPROFILE = $flags } | Out-Null

        Test-Path $flag | Should -BeFalse -Because 'source=startup must clear the flag so the next session re-delivers'
    }

    It 'RETAINS the session flag on source=resume' {
        $repo = New-TempRepo
        $flags = New-FlagDir
        $flag = Join-Path $flags '.active-drive-session-default'
        New-Item -ItemType File -Path $flag -Force | Out-Null

        Invoke-BashHook -HookPath $script:Hook -Payload (New-RawPayload -Cwd $repo -Source 'resume') `
            -Env @{ CLAVITY_GOLDEN_HEADER = $flags; USERPROFILE = $flags } | Out-Null

        Test-Path $flag | Should -BeTrue -Because 'only a genuine fresh start clears it'
    }

    It 'RETAINS the flag when .no-agy is at the payload cwd' {
        $repo = New-TempRepo
        $flags = New-FlagDir
        $flag = Join-Path $flags '.active-drive-session-default'
        New-Item -ItemType File -Path $flag -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $repo '.no-agy') -Force | Out-Null

        Invoke-BashHook -HookPath $script:Hook -Payload (New-RawPayload -Cwd $repo) `
            -Env @{ CLAVITY_GOLDEN_HEADER = $flags; USERPROFILE = $flags } | Out-Null

        Test-Path $flag | Should -BeTrue -Because '.no-agy at the session cwd must suppress the deletion'
    }

    It 'RETAINS the flag when .no-agy is at the REPO ROOT and cwd is a SUBDIRECTORY' {
        $repo = New-TempRepo
        $sub  = Join-Path $repo 'src'
        New-Item -ItemType Directory -Path $sub -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $repo '.no-agy') -Force | Out-Null

        $flags = New-FlagDir
        $flag = Join-Path $flags '.active-drive-session-default'
        New-Item -ItemType File -Path $flag -Force | Out-Null

        Invoke-BashHook -HookPath $script:Hook -Payload (New-RawPayload -Cwd $sub) `
            -Env @{ CLAVITY_GOLDEN_HEADER = $flags; USERPROFILE = $flags } | Out-Null

        Test-Path $flag | Should -BeTrue -Because 'an opt-out at the repo root must hold from a subdirectory'
    }

    It 'does not sweep a FRESH flag belonging to another session' {
        $repo = New-TempRepo
        $flags = New-FlagDir
        $other = Join-Path $flags '.active-drive-session-othersession'
        New-Item -ItemType File -Path $other -Force | Out-Null

        Invoke-BashHook -HookPath $script:Hook -Payload (New-RawPayload -Cwd $repo) `
            -Env @{ CLAVITY_GOLDEN_HEADER = $flags; USERPROFILE = $flags } | Out-Null

        Test-Path $other | Should -BeTrue -Because 'the -mtime +7 sweep must leave a live concurrent flag alone'
    }
}
```

- [ ] **Step 2: Run it and confirm exactly one test fails**

```bash
pwsh -c "Invoke-Pester scripts/tests/agy-drive-session-reset.Tests.ps1 -Output Detailed"
```

Expected: `Failed: 1`. The failing test is **`RETAINS the flag when .no-agy is at the REPO ROOT and cwd is a SUBDIRECTORY`** — that is the defect Task 3 fixes. The other four must PASS; they pin current, correct behaviour.

If a different test fails, stop and report — the hook does not behave as this plan describes and the rest of the plan is suspect.

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/agy-drive-session-reset.Tests.ps1
git commit -m "test(hooks): first suite for agy-drive-session-reset, incl. the failing subdir case"
```

---

## Task 2: Register the new suite in `justfile`

An unregistered suite is not unreachable — `justfile:112` (`test-scripts`) globs `scripts/tests` — but it runs in **neither** gate this plan uses, while `just test-scripts` reports it green. Nothing enforces membership: no test references the `justfile` at all.

**Files:**
- Modify: `justfile` (the `test-scripts-fast` recipe)

- [ ] **Step 1: Add the suite to the fast list**

In `justfile`, inside the `test-scripts-fast` recipe, find:

```
'scripts/tests/agy-discipline-reaching.Tests.ps1', 'scripts/tests/discipline-reaching-report.Tests.ps1', 'scripts/tests/scripts-readme-inventory.Tests.ps1')
```

Replace with:

```
'scripts/tests/agy-discipline-reaching.Tests.ps1', 'scripts/tests/discipline-reaching-report.Tests.ps1', 'scripts/tests/agy-drive-session-reset.Tests.ps1', 'scripts/tests/scripts-readme-inventory.Tests.ps1')
```

Fast, not slow: it touches filesystem flags and runs no heavy analysis.

- [ ] **Step 2: Run the registration oracle by hand**

It lives in `scripts/tests/_partition.md:53-54` and no test invokes it.

```bash
diff <(ls scripts/tests/*.Tests.ps1 | xargs -n1 basename | sort) \
     <(grep -oE "scripts/tests/[A-Za-z0-9._-]+\.Tests\.ps1" justfile | xargs -n1 basename | sort -u)
```

Expected: no output. Any line means a suite exists on disk that no recipe names, or vice versa.

- [ ] **Step 3: Commit**

```bash
git add justfile
git commit -m "build: register agy-drive-session-reset suite in test-scripts-fast"
```

---

## Task 3: Fix `agy-drive-session-reset.sh` (U1, highest severity, classic-only)

This hook has no dotnet pair — `scripts/check-seed-artifacts-synced.sh:29` exempts it as classic-only — so this is a **one-file edit** and the parity gate does not apply to it.

**Files:**
- Modify: `clavity-classic/plugin/hooks/agy-drive-session-reset.sh`

- [ ] **Step 1: Replace the payload parse and kill-switch**

BEFORE (verbatim, lines 6–10):

```bash
input="$(cat 2>/dev/null)"
source="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -f "${cwd}/.no-agy" ] && exit 0
[ -f "${HOME}/.claude/.no-agy" ] && exit 0
```

AFTER:

```bash
input="$(cat 2>/dev/null)"
source="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null)"

# cwd is recovered from the RAW payload, not via jq: without jq the old code left cwd empty and tested
# an absolute "/.no-agy", an undeclared degraded path in which the kill-switch silently did nothing.
[[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && cwd=${BASH_REMATCH[1]}
cwd_path=${cwd//\\\\//}
[ -z "$cwd_path" ] && cwd_path="."

[ -f "${HOME}/.claude/.no-agy" ] && exit 0

# Repo root by walking up for .git, in-shell. Normalization above is load-bearing: ${_d%/*} strips on
# "/" only, so without it this loop breaks on its first iteration and root never leaves cwd.
root=$cwd_path
_d=$cwd_path
while [ -n "$_d" ] && [ "$_d" != "/" ] && [ "$_d" != "." ]; do
  if [ -e "$_d/.git" ]; then root=$_d; break; fi
  _p=${_d%/*}
  [ "$_p" = "$_d" ] && break
  [ -z "$_p" ] && break
  _d=$_p
done

# This hook DELETES a flag file, so a missed opt-out destroys state rather than printing a line - and
# the session key defaults to 'default' (below), so the destroyed flag can belong to a concurrent
# opted-in session.
if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
  exit 0
fi
```

Note the `source` line keeps `jq`: without `jq` it is empty and `:13` exits 0, which is fail-safe and unchanged by this plan.

- [ ] **Step 2: Run the suite — all five must now pass**

```bash
pwsh -c "Invoke-Pester scripts/tests/agy-drive-session-reset.Tests.ps1 -Output Detailed"
```

Expected: `Failed: 0`, `Passed: 5`.

- [ ] **Step 3: Mutation-prove the normalization is load-bearing**

Temporarily change `cwd_path=${cwd//\\\\//}` to `cwd_path=$cwd`, then:

```bash
pwsh -c "Invoke-Pester scripts/tests/agy-drive-session-reset.Tests.ps1 -Output Detailed"
```

Expected: the `REPO ROOT ... SUBDIRECTORY` test **FAILS**. If it still passes, your payload is being forward-slashed somewhere and the test is vacuous — fix the test before restoring.

Restore the line, re-run, confirm `Failed: 0`.

- [ ] **Step 4: Verify line endings**

```bash
python3 -c "
d=open('clavity-classic/plugin/hooks/agy-drive-session-reset.sh','rb').read()
crlf=d.count(b'\r\n'); lf=d.count(b'\n')-crlf
print('CRLF' if crlf and not lf else ('MIXED-BROKEN' if crlf else 'LF'))"
```

Expected: `LF`.

- [ ] **Step 5: Commit**

```bash
git add clavity-classic/plugin/hooks/agy-drive-session-reset.sh
git commit -m "fix(hooks): honour .no-agy from a subdirectory in the one hook that deletes files"
```

---

## Tasks 4–11: the eight paired hooks

**Every one of these tasks is TWO file edits** — the same change in `clavity-dotnet/plugin/hooks/` and `clavity-classic/plugin/hooks/`. Make the dotnet edit, then copy the file:

```bash
cp clavity-dotnet/plugin/hooks/<hook>.sh clavity-classic/plugin/hooks/<hook>.sh
```

`agy-drive-session-reset.sh` is the only unpaired hook and was Task 3.

**Every one of these tasks ends with the same three checks**, so they are stated once here and referenced by number in each task:

- **Check A — parity:** `bash scripts/check-seed-artifacts-synced.sh; echo "exit=$?"` → `exit=0`.
- **Check B — line endings:** the `python3` snippet from "Read this before Task 1", item 3 → all `LF`.
- **Check C — the hook's own suite** passes, command given per task.

### Task 4: `agy-anomaly-model-notice.sh` — single site, easiest first

This hook has **no degraded branch**: it `exit 0`s entirely without `jq` (`:19-21`). One edit site. It already resolves the repo root *below* the kill-switch, via `git rev-parse`, to find the anomalies file — so the fix is to resolve the root *first* and reuse it, not to add a second idiom.

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-anomaly-model-notice.sh`
- Modify: `clavity-classic/plugin/hooks/agy-anomaly-model-notice.sh`
- Test: `scripts/tests/agy-anomaly-model-notice.Tests.ps1`

- [ ] **Step 1: Add the failing test**

Append inside the existing top-level `Describe` block in `scripts/tests/agy-anomaly-model-notice.Tests.ps1`:

```powershell
    It 'is SILENT when .no-agy is at the repo root and cwd is a subdirectory' {
        $repo = New-TempRepo
        $sub  = Join-Path $repo 'src'
        New-Item -ItemType Directory -Path $sub -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $repo '.no-agy') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $repo '.clavity') -Force | Out-Null
        Set-Content -Path (Join-Path $repo '.clavity\local-anomalies.md') -Value '- [defect] x * a:1 * 2026-01-01 * task=t' -Force

        # Raw, backslashed payload - deliberately NOT forward-slashed. The repo-wide test convention
        # normalizes cwd, which is why this class of bug survived; a POSIX path cannot exercise it.
        $payload = '{"cwd":"' + ($sub -replace '\\', '\\') + '","hook_event_name":"SessionStart"}'
        $r = Invoke-BashHook -HookPath $script:Hook -Payload $payload

        $r.Stdout | Should -BeNullOrEmpty -Because 'a root opt-out must suppress this hook from a subdirectory'
    }

    It 'DOES fire from that same subdirectory when .no-agy is absent (positive control)' {
        $repo = New-TempRepo
        $sub  = Join-Path $repo 'src'
        New-Item -ItemType Directory -Path $sub -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $repo '.clavity') -Force | Out-Null
        Set-Content -Path (Join-Path $repo '.clavity\local-anomalies.md') -Value '- [defect] x * a:1 * 2026-01-01 * task=t' -Force

        $payload = '{"cwd":"' + ($sub -replace '\\', '\\') + '","hook_event_name":"SessionStart"}'
        $r = Invoke-BashHook -HookPath $script:Hook -Payload $payload

        $r.Stdout | Should -Match 'AGY-ANOMALIES/1' -Because 'without the opt-out it must still fire - otherwise the silence test proves nothing'
    }
```

If `$script:Hook` is not the variable this suite already uses for the dotnet copy, use whatever it does use — check its `BeforeAll`.

- [ ] **Step 2: Run and confirm the first new test fails, the second passes**

```bash
pwsh -c "Invoke-Pester scripts/tests/agy-anomaly-model-notice.Tests.ps1 -Output Detailed"
```

Expected: `Failed: 1` — the silence test. The positive control must already PASS.

- [ ] **Step 3: Edit the dotnet hook**

BEFORE (verbatim, lines 23–33):

```bash
cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)
[ -z "$cwd" ] && cwd="."

if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  exit 0
fi

root=$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
[ -n "$root" ] || root="$cwd"
f="$root/.clavity/local-anomalies.md"
[ -f "$f" ] || f="$cwd/.clavity/local-anomalies.md"
```

AFTER:

```bash
cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)
cwd_path=${cwd//\\\\//}
[ -z "$cwd_path" ] && cwd_path="."

# The GLOBAL opt-out does not depend on the repo root, so it is checked first and cheaply.
[ -f "$HOME/.claude/.no-agy" ] && exit 0

# Resolve the root BEFORE the workspace kill-switch, so an opt-out at the repo root is honoured from a
# subdirectory. This hook already needed the root to find the anomalies file; it is now resolved once,
# in-shell, and reused - rather than keeping a second `git rev-parse` idiom that could disagree with it
# on a worktree or submodule, where .git is a file rather than a directory.
root=$cwd_path
_d=$cwd_path
while [ -n "$_d" ] && [ "$_d" != "/" ] && [ "$_d" != "." ]; do
  if [ -e "$_d/.git" ]; then root=$_d; break; fi
  _p=${_d%/*}
  [ "$_p" = "$_d" ] && break
  [ -z "$_p" ] && break
  _d=$_p
done

if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
  exit 0
fi

f="$root/.clavity/local-anomalies.md"
[ -f "$f" ] || f="$cwd_path/.clavity/local-anomalies.md"
```

**Note the two later references to `$cwd` in this file also become `$cwd_path`** — the `f=` fallback above. Search the file for remaining bare `$cwd` uses and convert them; leaving one mixes a normalized and an un-normalized path in the same file.

- [ ] **Step 4: Mirror to classic**

```bash
cp clavity-dotnet/plugin/hooks/agy-anomaly-model-notice.sh clavity-classic/plugin/hooks/agy-anomaly-model-notice.sh
```

- [ ] **Step 5: Checks A, B, C**

```bash
bash scripts/check-seed-artifacts-synced.sh; echo "exit=$?"
pwsh -c "Invoke-Pester scripts/tests/agy-anomaly-model-notice.Tests.ps1 -Output Detailed"
```

Expected: `exit=0`, then `Failed: 0`.

- [ ] **Step 6: Mutation-prove it**

Change `cwd_path=${cwd//\\\\//}` to `cwd_path=$cwd`, re-run the suite, confirm the silence test FAILS, restore, re-run, confirm green.

- [ ] **Step 7: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-anomaly-model-notice.sh clavity-classic/plugin/hooks/agy-anomaly-model-notice.sh scripts/tests/agy-anomaly-model-notice.Tests.ps1
git commit -m "fix(hooks): agy-anomaly-model-notice honours a root .no-agy from a subdirectory"
```

---

### Task 5: `agy-after-reminder.sh` — two sites

**Files:**
- Modify: `clavity-{dotnet,classic}/plugin/hooks/agy-after-reminder.sh`
- Test: `scripts/tests/agy-after-reminder.Tests.ps1`

- [ ] **Step 1: Add the failing test + positive control**

Append inside the suite's top-level `Describe`, adapting the two `It` blocks from Task 4 Step 1 with these changes: this is a `PostToolUse` hook that fires on a spec/plan write, so the payload needs a `tool_input.file_path`, and the assertion string differs.

```powershell
    It 'is SILENT when .no-agy is at the repo root and cwd is a subdirectory' {
        $repo = New-TempRepo
        $sub  = Join-Path $repo 'src'
        New-Item -ItemType Directory -Path $sub -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $repo '.no-agy') -Force | Out-Null

        $payload = '{"cwd":"' + ($sub -replace '\\', '\\') + '","tool_name":"Write","tool_input":{"file_path":"docs/superpowers/specs/x-design.md"},"hook_event_name":"PostToolUse"}'
        $r = Invoke-BashHook -HookPath $script:Hook -Payload $payload

        $r.Stdout | Should -BeNullOrEmpty -Because 'a root opt-out must suppress this hook from a subdirectory'
    }

    It 'DOES fire from that same subdirectory when .no-agy is absent (positive control)' {
        $repo = New-TempRepo
        $sub  = Join-Path $repo 'src'
        New-Item -ItemType Directory -Path $sub -Force | Out-Null

        $payload = '{"cwd":"' + ($sub -replace '\\', '\\') + '","tool_name":"Write","tool_input":{"file_path":"docs/superpowers/specs/x-design.md"},"hook_event_name":"PostToolUse"}'
        $r = Invoke-BashHook -HookPath $script:Hook -Payload $payload

        $r.Stdout | Should -Match 'AGY-AFTER' -Because 'without the opt-out it must still fire'
    }
```

- [ ] **Step 2: Run — expect `Failed: 1`, the silence test**

```bash
pwsh -c "Invoke-Pester scripts/tests/agy-after-reminder.Tests.ps1 -Output Detailed"
```

- [ ] **Step 3: Edit the DEGRADED site — but edit the NORMAL site first**

Do the normal-path site before the degraded site. Everything above an edit keeps its position, so working bottom-to-top keeps the second BEFORE block matching.

**🔴 REPLACE ONLY THE KILL-SWITCH BLOCK. Leave every extraction line above it alone.** Each hook extracts
different fields — `fp` here, `skill` in `agy-seam-inject.sh`, nothing extra in the anomaly hooks — and
those lines are NOT part of this edit. An earlier draft of this plan pasted `agy-after-reminder.sh`'s `fp`
lines into the shared block and told Tasks 6–10 to apply it verbatim, which would have inserted
`[ -z "$fp" ] && exit 0` into five hooks that have no `file_path` and **silenced all five on the normal
path.** Caught by the panel. The block below is hook-agnostic; keep it that way.

**Normal-path site, BEFORE (verbatim):**

```bash
# Opt-out kill-switch (mirrors agy-seam-inject.sh).
if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  exit 0
fi
```

**AFTER — this exact block is reused by Tasks 6–10:**

```bash
cwd_path=${cwd//\\\\//}
[ -z "$cwd_path" ] && cwd_path="."

# Opt-out kill-switch (mirrors agy-seam-inject.sh). Global first - it needs no root.
[ -f "$HOME/.claude/.no-agy" ] && exit 0

# Repo root by walking up for .git, in-shell. The normalization above is load-bearing: ${_d%/*} strips
# on "/" only, so an un-normalized Windows path breaks this loop on its first iteration.
root=$cwd_path
_d=$cwd_path
while [ -n "$_d" ] && [ "$_d" != "/" ] && [ "$_d" != "." ]; do
  if [ -e "$_d/.git" ]; then root=$_d; break; fi
  _p=${_d%/*}
  [ "$_p" = "$_d" ] && break
  [ -z "$_p" ] && break
  _d=$_p
done

if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
  exit 0
fi
```

**Degraded site, BEFORE (verbatim):**

```bash
if ! command -v jq >/dev/null 2>&1; then
  if [ -f "./.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then exit 0; fi
```

**AFTER:**

```bash
if ! command -v jq >/dev/null 2>&1; then
  # Recover the REAL cwd from the raw payload rather than trusting the process cwd, which is not
  # necessarily the session's workspace. Same technique the recorder uses; needs no jq.
  [[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && cwd=${BASH_REMATCH[1]}
  cwd_path=${cwd//\\\\//}
  [ -z "$cwd_path" ] && cwd_path="."
  [ -f "$HOME/.claude/.no-agy" ] && exit 0
  root=$cwd_path
  _d=$cwd_path
  while [ -n "$_d" ] && [ "$_d" != "/" ] && [ "$_d" != "." ]; do
    if [ -e "$_d/.git" ]; then root=$_d; break; fi
    _p=${_d%/*}
    [ "$_p" = "$_d" ] && break
    [ -z "$_p" ] && break
    _d=$_p
  done
  if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then exit 0; fi
```

**Do not change the `exit 0` at the end of this degraded block.** This is a `PostToolUse` hook; it must exit 0.

- [ ] **Step 4: Mirror, then Checks A, B, C**

```bash
cp clavity-dotnet/plugin/hooks/agy-after-reminder.sh clavity-classic/plugin/hooks/agy-after-reminder.sh
bash scripts/check-seed-artifacts-synced.sh; echo "exit=$?"
pwsh -c "Invoke-Pester scripts/tests/agy-after-reminder.Tests.ps1 -Output Detailed"
```

Expected: `exit=0`, `Failed: 0`.

- [ ] **Step 5: Mutation-prove, then commit**

Change `cwd_path=${cwd//\\\\//}` in the normal-path block to `cwd_path=$cwd`, re-run, confirm the silence test FAILS, restore, confirm green.

```bash
git add clavity-dotnet/plugin/hooks/agy-after-reminder.sh clavity-classic/plugin/hooks/agy-after-reminder.sh scripts/tests/agy-after-reminder.Tests.ps1
git commit -m "fix(hooks): agy-after-reminder honours a root .no-agy from a subdirectory"
```

---

### Tasks 6–10: the remaining five two-site hooks

These five have the **same shape** as Task 5: a degraded branch whose kill-switch line is
`  if [ -f "./.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then exit 0; fi`, and a normal-path block
`if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then` / `  exit 0` / `fi`.

**Apply Task 5's two AFTER blocks verbatim to each** — they are hook-agnostic, and the BEFORE they match
is **only the kill-switch block**, never the extraction lines above it. Work bottom-to-top in each file
(normal-path site first). Each task = edit dotnet → `cp` to classic → Checks A, B, C → mutation-prove →
commit.

**🔴 Confirm the BEFORE you are replacing, per hook. Do NOT carry any neighbouring line into the edit.**
These are the normal-path kill-switch blocks as they exist now — the extraction lines shown are context to
help you locate the block, and **must be left exactly as they are**:

```text
# ANNOTATED — NOT PASTEABLE. The "<--" markers are annotation, not bash. This block is here to help you
# locate each edit site and to make clear what must NOT be carried into the edit.
# agy-anomaly-capture-reminder.sh and agy-anomaly-dispatch-reminder.sh  (identical shape)
cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)   <-- CONTEXT, do not touch
[ -z "$cwd" ] && cwd="."                                        <-- CONTEXT, do not touch

if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then   <-- replace from here
  exit 0
fi                                                                  <-- to here

# agy-seam-inject.sh
skill=$(printf '%s' "$input" | jq -r '.tool_input.skill // ""' 2>/dev/null)   <-- CONTEXT
cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)                 <-- CONTEXT

# Opt-out kill-switch (mirrors agy-after-reminder.sh): .no-agy in the session cwd or ~/.claude.
if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then   <-- replace from here
  exit 0
fi                                                                  <-- to here

# agy-anomaly-reminder.sh
cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)   <-- CONTEXT, note: no `[ -z ]` line here

# Opt-out kill-switch (mirrors agy-after-reminder.sh): silent, no notice.
if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then   <-- replace from here
  exit 0
fi                                                                  <-- to here

# agy-test-audit-reminder.sh
cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)   <-- CONTEXT
[ -z "$cwd" ] && cwd="."                                        <-- CONTEXT

# Opt-out kill-switch (mirrors agy-after-reminder.sh).
if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then   <-- replace from here
  exit 0
fi                                                                  <-- to here
```

| Task | Hook | Event | Degraded exit | Test suite | Positive-control assertion |
|---|---|---|---|---|---|
| 6 | `agy-anomaly-capture-reminder.sh` | PreCompact | `exit 0` | `agy-anomaly-capture-reminder.Tests.ps1` | `Should -Match 'AGY-ANOMALIES/1'` |
| 7 | `agy-anomaly-dispatch-reminder.sh` | PreToolUse | **`exit 0` — `exit 2` would abort the user's tool call** (see note) | `agy-anomaly-dispatch-reminder.Tests.ps1` | `Should -Match 'Anomalies noticed'` |
| 8 | `agy-seam-inject.sh` | PreToolUse | **`exit 0` — same hazard** | `agy-seam-inject.Tests.ps1` | `Should -Match 'AGY-'` |
| 9 | `agy-anomaly-reminder.sh` | SessionStart | `exit 2` on stderr — **keep it** | `agy-anomaly-reminder.Tests.ps1` | `Stderr Should -Match 'AGY-ANOMALIES'` |
| 10 | `agy-test-audit-reminder.sh` | PostToolUse | `exit 0` | `agy-test-audit-reminder.Tests.ps1` | `Should -Match 'AGY-TEST-AUDIT'` |

**Note on Task 7 — there is already a safety net, and it is worth knowing about.**
`agy-anomaly-dispatch-reminder.sh:15-19` states its contract and names its own guard:

> *"FAIL OPEN ON EVERY PATH, AND THAT IS NOT A STYLE PREFERENCE. `exit 2` is non-blocking for
> `SessionStart` but BLOCKING for `PreToolUse` … a non-zero exit here does not degrade a notification — it
> HALTS EVERY SUBAGENT DISPATCH in the session. … **A test asserts that no exit with a non-zero status
> appears anywhere in this file.**"*

So if you paste the wrong exit into that hook, a test fails loudly rather than the damage shipping. Do not
treat that as licence to be careless — but if that test goes red after your edit, this is what it means.

**The walk terminates safely on Windows.** MEASURED: from `C:/Users/u/a/b/c/d` with no `.git` anywhere, the
loop ends after 7 iterations at `C:`, because `${_d%/*}` on `C:` returns `C:` and the
`[ "$_p" = "$_d" ] && break` guard fires. No infinite loop at a drive root.

**Two hooks in this group differ from Task 5's BEFORE text — read carefully:**

**Task 9, `agy-anomaly-reminder.sh`** — its degraded kill-switch is multi-line, not one line. BEFORE:

```bash
  if [ -f "./.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
    exit 0
  fi
```

Replace with Task 5's degraded AFTER block, keeping the final `printf ... >&2` / `exit 2` that follows it untouched. This hook also already has a `git rev-parse` root resolution below its normal-path check (with the comment *"Resolve the REPOSITORY ROOT the same way the capture snippet does"*) — **replace that with a reuse of the walked `$root`**, exactly as Task 4 Step 3 did for its sibling, so the two halves cannot disagree.

**Task 10, `agy-test-audit-reminder.sh`** — its degraded branch already recovers `cwd` via `sed`, and the recovered value is **already broken on Windows**: the `sed` captures from the raw payload, so `$cwd` keeps its escapes and `[ -f "$cwd/.no-agy" ]` does not stat the intended file. BEFORE:

```bash
  cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  [ -z "$cwd" ] && cwd="."
  # Honor the kill-switch against the SAME cwd the gate uses (aligns with the jq path below).
  if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then exit 0; fi
```

Replace with Task 5's degraded AFTER block. **Then update the `gate` call below it** — it currently receives the un-normalized `"$cwd"`; it must receive `"$cwd_path"`, or the gate keeps reading a path that does not resolve.

---

### Task 11: `agy-liveness-check.sh` — two sites plus a truthful message

This hook exists to say LOUDLY why the disciplines are off, so a wrong path in its message is a defect in the one hook meant to prevent confusion. It is also the only hook whose degraded checks **announce and `exit 2`** rather than exiting silently, so its boot output is user-visible.

**Files:**
- Modify: `clavity-{dotnet,classic}/plugin/hooks/agy-liveness-check.sh`
- Test: `scripts/tests/agy-liveness-check.Tests.ps1`

- [ ] **Step 1: Add the failing test + positive control**

```powershell
    It 'names the ROOT .no-agy path when suppressed from a subdirectory' {
        $repo = New-TempRepo
        $sub  = Join-Path $repo 'src'
        New-Item -ItemType Directory -Path $sub -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $repo '.no-agy') -Force | Out-Null

        $payload = '{"cwd":"' + ($sub -replace '\\', '\\') + '","hook_event_name":"SessionStart"}'
        $r = Invoke-BashHook -HookPath $script:Hook -Payload $payload

        $r.Stderr | Should -Match 'suppressed by \.no-agy' -Because 'a root opt-out must suppress it from a subdirectory'
        $r.Stderr | Should -Not -Match 'src[\\/]\.no-agy' -Because 'it must name the file that actually exists, not the cwd candidate'
    }
```

- [ ] **Step 2: Run — expect `Failed: 1`**

```bash
pwsh -c "Invoke-Pester scripts/tests/agy-liveness-check.Tests.ps1 -Output Detailed"
```

- [ ] **Step 3: Normal-path site — BEFORE (verbatim)**

```bash
if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  suppressed="$cwd/.no-agy"; [ -f "$suppressed" ] || suppressed="$HOME/.claude/.no-agy"
  printf '%s\n' "[AGY-DISCIPLINES] suppressed by .no-agy at $suppressed" >&2
```

**AFTER:**

```bash
if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  suppressed="$root/.no-agy"
  [ -f "$suppressed" ] || suppressed="$cwd_path/.no-agy"
  [ -f "$suppressed" ] || suppressed="$HOME/.claude/.no-agy"
  printf '%s\n' "[AGY-DISCIPLINES] suppressed by .no-agy at $suppressed" >&2
```

**The two-space indentation is part of the match** — this block sits inside the `if`. Losing it was a real
defect in an earlier draft of this plan, caught by diffing the pasted text against the file.

Three candidates now, so the reported path must be chosen from three — the old two-way fallback would name `$cwd/.no-agy`, a file that does not exist, whenever the root was the reason.

**🔴 Insert only the NORMALIZATION and the WALK above this block — NOT the canonical preamble's
`[ -f "$HOME/.claude/.no-agy" ] && exit 0` line.** This hook is the one exception, and inserting the full
preamble here would be a serious regression. `agy-liveness-check.sh:125-127` says so in its own words:

> *"`.no-agy` kill-switch: announce LOUDLY (naming the path) then STOP. NOT a silent early-exit (that
> reintroduces the silent-kill Decision 3 forbids)"*

A silent `exit 0` on the global opt-out would kill that announce **and** skip the ownership report at
`:133`, whose comment states the constraint plainly: *"ownership is reported EVEN under the kill-switch. A
gate the policed party can switch off is not a gate."* The global opt-out must stay inside the `if` below,
where it is announced and exits 2. Insert exactly this, and nothing more:

```bash
cwd_path=${cwd//\\\\//}
[ -z "$cwd_path" ] && cwd_path="."
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

(An earlier draft of this plan said "insert the canonical preamble ... as in Task 5" here. The panel caught
it. This is why the plan states each hook's exit contract instead of sharing one.)

- [ ] **Step 4: Degraded site — BEFORE (verbatim)**

```bash
  if [ -f "./.no-agy" ]; then
    printf '%s\n' "[AGY-DISCIPLINES] suppressed by .no-agy at ./.no-agy" >&2
    exit 2
  fi
```

**AFTER:**

```bash
  [[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && cwd=${BASH_REMATCH[1]}
  cwd_path=${cwd//\\\\//}
  [ -z "$cwd_path" ] && cwd_path="."
  root=$cwd_path
  _d=$cwd_path
  while [ -n "$_d" ] && [ "$_d" != "/" ] && [ "$_d" != "." ]; do
    if [ -e "$_d/.git" ]; then root=$_d; break; fi
    _p=${_d%/*}
    [ "$_p" = "$_d" ] && break
    [ -z "$_p" ] && break
    _d=$_p
  done
  if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
    _s="$root/.no-agy"; [ -f "$_s" ] || _s="$cwd_path/.no-agy"
    printf '%s\n' "[AGY-DISCIPLINES] suppressed by .no-agy at $_s" >&2
    exit 2
  fi
```

**Keep `exit 2`** — this is `SessionStart`, where exit 2 routes the message to the user and does not block. The `$HOME/.claude/.no-agy` block immediately below stays exactly as it is.

- [ ] **Step 5: Mirror, Checks A/B/C, mutation-prove, commit**

```bash
cp clavity-dotnet/plugin/hooks/agy-liveness-check.sh clavity-classic/plugin/hooks/agy-liveness-check.sh
bash scripts/check-seed-artifacts-synced.sh; echo "exit=$?"
pwsh -c "Invoke-Pester scripts/tests/agy-liveness-check.Tests.ps1 -Output Detailed"
git add clavity-dotnet/plugin/hooks/agy-liveness-check.sh clavity-classic/plugin/hooks/agy-liveness-check.sh scripts/tests/agy-liveness-check.Tests.ps1
git commit -m "fix(hooks): agy-liveness-check walks to the root and names the file that exists"
```

---

## Task 12: U2 — delete the false invariant in the recorder's comment

The comment claims *"a field not written at session N cannot be recovered at N+1"*. Measured: a real `source=resume` payload carries no `model`, so the claim is false for resume rows. The hook is correct; the comment is not. A false invariant in shipped source is a defect attractor — the next reader reasons from it.

**Files:**
- Modify: `clavity-{dotnet,classic}/plugin/hooks/agy-discipline-reaching.sh`

- [ ] **Step 1: Open the file and read the comment around `:94`**

```bash
sed -n '88,100p' clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh
```

- [ ] **Step 2: Replace the false clause**

Find the sentence containing `a field not written at session N cannot be recovered at N+1` and replace that clause with:

```
capture is the irreversible half. `model` is recorded when the payload carries it: startup and compact
payloads do, resume payloads do not (MEASURED 2026-08-05 - the first real post-install row was
source=resume with an empty model). The hook records what it is handed; an empty model is data, not a bug.
```

Keep the surrounding comment lines unchanged.

- [ ] **Step 3: Mirror and check parity**

```bash
cp clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh clavity-classic/plugin/hooks/agy-discipline-reaching.sh
bash scripts/check-seed-artifacts-synced.sh; echo "exit=$?"
pwsh -c "Invoke-Pester scripts/tests/agy-discipline-reaching.Tests.ps1 -Output Detailed"
```

Expected: `exit=0`, `Failed: 0`. This is a comment change; no test behaviour may move.

- [ ] **Step 4: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh clavity-classic/plugin/hooks/agy-discipline-reaching.sh
git commit -m "docs(hooks): the model comment asserted an invariant that resume payloads break"
```

---

## Task 13: U3a — bind the consult-guard lib into its test suite

`scripts/tests/agy-consult-guard.Tests.ps1` binds only `$script:Pre` and `$script:Post`. `agy-consult-guard-lib.sh` is the largest of the three at 6,9K, carries the 7-axis snapshot logic, and has no coverage in that suite.

**Files:**
- Modify: `scripts/tests/agy-consult-guard.Tests.ps1`

- [ ] **Step 1: Read the existing bindings**

```bash
sed -n '1,20p' scripts/tests/agy-consult-guard.Tests.ps1
```

- [ ] **Step 2: Add a `$script:Lib` binding beside `$script:Pre` and `$script:Post`**

Follow the exact shape of the two existing lines, pointing at `agy-consult-guard-lib.sh`.

- [ ] **Step 3: Include the lib in the suite's ASCII and cross-driver parity assertions**

Find the existing assertions that iterate `$script:Pre, $script:Post` and add `$script:Lib` to each collection. Do not write new assertion logic — extend the collections the suite already has.

- [ ] **Step 4: Run the suite (it is in the SLOW half)**

```bash
pwsh -c "Invoke-Pester scripts/tests/agy-consult-guard.Tests.ps1 -Output Detailed"
```

Expected: `Failed: 0`, and the test count higher than before by the number of collection members you extended.

- [ ] **Step 5: Commit**

```bash
git add scripts/tests/agy-consult-guard.Tests.ps1
git commit -m "test(hooks): cover agy-consult-guard-lib.sh, the largest and least-tested of the three"
```

---

## Task 14: U3b + U3c — the consult guard's doc line and header rename

**These two changes touch the same `lib.sh` file. Make them in one pass, not two.**

**Files:**
- Modify: `clavity-{dotnet,classic}/plugin/hooks/agy-consult-guard-lib.sh`
- Modify: `clavity-{dotnet,classic}/plugin/hooks/agy-consult-guard-pre.sh`
- Modify: `clavity-{dotnet,classic}/plugin/hooks/agy-consult-guard-post.sh`

- [ ] **Step 1: U3c — drop the `ME1 - ` prefix from line 2 of all six files**

BEFORE / AFTER, per file:

```
# ME1 - agy-consult VCS-diff guard, PRE half.       ->  # agy-consult VCS-diff guard, PRE half.
# ME1 - agy-consult VCS-diff guard, POST half.      ->  # agy-consult VCS-diff guard, POST half.
# ME1 - agy-consult VCS-diff guard, shared library. ->  # agy-consult VCS-diff guard, shared library.
```

Owner ruling: *"ME1 is not a descriptive name for humans."* The descriptive name is already on the line; the task ID is a redundant prefix.

- [ ] **Step 2: U3b — record the deliberate `.no-agy` omission**

In `agy-consult-guard-lib.sh`, find the existing `DELIBERATELY OUT OF SCOPE (documented, not a silent gap)` block near `:17` and add one entry to it:

```
#   - .no-agy: this guard deliberately does NOT honour the kill-switch. .no-agy is a file IN THE REPO,
#     so a review-only consult that mutated version control could create it and thereby hide its own
#     write - post.sh would exit before diffing. A guard the untrusted actor can switch off is not a
#     guard. Same principle the ownership check follows (see clavity-classic/plugin/README.md).
```

Match the existing entries' comment style exactly.

- [ ] **Step 3: Mirror all three files to classic and check parity**

```bash
for h in lib pre post; do
  cp clavity-dotnet/plugin/hooks/agy-consult-guard-$h.sh clavity-classic/plugin/hooks/agy-consult-guard-$h.sh
done
bash scripts/check-seed-artifacts-synced.sh; echo "exit=$?"
```

Expected: `exit=0`.

- [ ] **Step 4: Confirm no header still carries the prefix**

```bash
grep -n 'ME1' clavity-dotnet/plugin/hooks/*.sh clavity-classic/plugin/hooks/*.sh || echo "clean"
```

Expected: `clean`.

- [ ] **Step 5: Run the suite and commit**

```bash
pwsh -c "Invoke-Pester scripts/tests/agy-consult-guard.Tests.ps1 -Output Detailed"
git add clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh clavity-classic/plugin/hooks/agy-consult-guard-lib.sh clavity-classic/plugin/hooks/agy-consult-guard-pre.sh clavity-classic/plugin/hooks/agy-consult-guard-post.sh
git commit -m "docs(hooks): say 'the consult guard', and record why it ignores .no-agy"
```

---

## Task 15: Re-measure `_partition.md`

It must be re-measured, never hand-edited — it was wrong in both columns for two commits precisely because nobody re-measured.

**Files:**
- Modify: `scripts/tests/_partition.md`

- [ ] **Step 1: Run the registration oracle**

```bash
diff <(ls scripts/tests/*.Tests.ps1 | xargs -n1 basename | sort) \
     <(grep -oE "scripts/tests/[A-Za-z0-9._-]+\.Tests\.ps1" justfile | xargs -n1 basename | sort -u)
```

Expected: no output.

- [ ] **Step 2: Time the fast half**

```bash
just test-scripts-fast
```

Record the wall-clock total and the `Tests Passed:` count from the Pester summary.

- [ ] **Step 3: Time the slow half — BACKGROUNDED**

It exceeds the 600s foreground tool cap. Run it in the background and block on its own `Tests completed` line, never on a process count.

- [ ] **Step 4: Update the measured figures in `_partition.md`**

Write the numbers you just measured into the file's tables, including the new suite's row. Do not copy figures from anywhere else.

- [ ] **Step 5: Commit**

```bash
git add scripts/tests/_partition.md
git commit -m "docs(tests): re-measure the partition after adding a suite"
```

---

## Task 16: Full gates, then the capstone

- [ ] **Step 1: Parity gate**

```bash
bash scripts/check-seed-artifacts-synced.sh; echo "exit=$?"
```

Expected: `exit=0`.

- [ ] **Step 2: Line endings across every touched hook**

Run the `python3` snippet from "Read this before Task 1", item 3. Expected: every file `LF`.

- [ ] **Step 3: Fast half**

```bash
just test-scripts-fast
```

Expected: `Failed: 0`, and `Tests Passed:` higher than Task 0's baseline by the number of tests added.

- [ ] **Step 4: Slow half — BACKGROUNDED**

Expected: `Failed: 0`.

- [ ] **Step 5: Confirm no hook still lacks the walk**

```bash
grep -n 'no-agy' clavity-dotnet/plugin/hooks/*.sh clavity-classic/plugin/hooks/*.sh | grep -v '_path\|root\|HOME\|^.*#'
```

Expected: no line showing a bare `$cwd/.no-agy` or `./.no-agy` check outside a comment. **If this returns nothing, do not conclude success** — bash `grep` returned three false zeros while this plan was written. Confirm by opening two files at random.

- [ ] **Step 6: AGY-CAPSTONE over the committed range**

Invoke the `agy-capstone` skill on `<Task 0 SHA>..HEAD`. Seat the consult guard's four carried-forward lenses alongside the standard ones: a VCS mutation invisible to the 7 axes; a path that silently disables the guard while the driver believes it protected; category mis-classification; and a two-slot lifecycle race leaving a real mutation unreported — **a false negative being the fatal class for a guard.**

Rounds until GREEN; the owner has waived the round cap. GREEN is owner-adjudicated.

- [ ] **Step 7: Record the capstone row**

Add one row to `docs/agy-capstone-ledger.md`: date, commit range, round count, verdict, and checkable evidence (fold commits or the review transcript). `none` is not a permitted evidence value.

---

## Self-review

**Spec coverage.** U1 → Tasks 3–11 (all 17 files: 1 classic-only + 8 pairs). U2 → Task 12. U3a → Task 13. U3b + U3c → Task 14. U4 → Tasks 1–3 (suite first, per the spec's split) and Task 2 (registration). Testing section → the failing-test + positive-control + mutation steps in every hook task. Gates → Tasks 0 and 16. `_partition.md` → Task 15. Capstone with the consult guard's four seats → Task 16 Step 6. Success criteria 1–7 and 5a all map.

**Placeholders.** None. Every code step carries the real BEFORE/AFTER text, read out of the files while writing this plan.

**Two places the plan deliberately says "read the file first"** rather than pasting text: Task 12 Step 1 (the recorder's comment, whose exact wrapping I did not capture) and Task 13 Steps 1–3 (the consult-guard suite's binding lines and assertion collections). Both are cases where pasting text I had not verified verbatim would risk a fabricated citation, which is the failure this repo's plan discipline exists to prevent. Each names the exact command to run and the exact shape to follow.

**Consistency.** `cwd_path` and `root` are the variable names throughout, matching the recorder they are copied from. `${cwd//\\\\//}` is the single normalization form everywhere. Every task that edits a paired hook ends with `cp` to classic and the parity gate.

**One risk I could not retire.** I could not cleanly verify backslash normalization by hand — the agent harness eats backslashes before bash receives them, and two attempts produced contaminated results. The plan therefore instructs copying the recorder's shipped line verbatim and proving it with a file-based Pester test plus a mutation check, rather than resting on a derivation. **If the mutation step in Task 3 does not turn the test red, stop: the test is vacuous and the whole fix is unproven.**

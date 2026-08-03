# agy discipline cost/quota hygiene — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop shipped agy review disciplines from firing at peak session context by adding a cost clause to the hook directives that convene them, plus a user-facing README section explaining how to run them economically.

**Architecture:** Two layers, both text. Layer 1 appends a short clause to three directive sites inside two hook scripts (mirrored across both drivers). Layer 2 adds a `## Running this economically` section to both plugin READMEs and a pointer line to the root README. Seven new Pester assertions pin the clauses' presence, their deliberate absence where the placement rule excludes them, and cross-driver byte parity.

**Tech Stack:** Bash hooks emitting JSON via `jq`, Pester 5 tests driven through `BashHookHelpers.ps1`, `just` recipes.

**Source spec:** `docs/superpowers/specs/2026-08-03-agy-discipline-cost-hygiene-design.md` (panel-converged at round 9).

---

## Two hazards that will bite you if you skip this section

**1. Lines 75 and 77 of `agy-seam-inject.sh` end with byte-identical text.**

```
:75  ... SKIPPED-UNREACHABLE path applies - proceed, do not hang.' ;;
:77  ... SKIPPED-UNREACHABLE path applies - proceed, do not hang.' ;;
```

A find-and-replace anchored on that tail hits **both** arms and puts the wrong clause on the wrong discipline. **Always anchor on the start of the line** — `emit 'AGY-FIRST auto-fire:` and `emit 'AGY-CAPSTONE auto-fire:` are unique.

**2. Both clause texts must contain no apostrophe, no backtick, and no non-ASCII byte.**

- `agy-seam-inject.sh` and `agy-test-audit-reminder.sh` use single-quoted `emit '...'` — an apostrophe terminates the string. The file already needs the `'"'"'` idiom for existing ones.
- `agy-after-reminder.sh` uses double-quoted `msg="..."` — a backtick becomes command substitution and would execute at hook runtime.
- All three suites assert zero bytes above 127 (`It 'ships as pure ASCII'`).

Write `/compact`, not a backticked one. Write "does not", never "doesn't".

---

## The two exact strings

Copy these verbatim. Do not reflow, reword, or add punctuation.

**COST clause** (goes on two sites):

```
COST: this discipline re-reads the whole session context every round, so running it in a long session burns several times the tokens - and subscription quota - of running it fresh. If this session carries substantial history, do not run it inline: tell the user it runs about 5x leaner after /compact or in a fresh session, and follow their answer. This changes WHERE the review runs, never WHETHER.
```

**SESSION POSTURE line** (goes on one site):

```
SESSION POSTURE: reviews later in this work (capstone, test audit, panel) re-read the whole session context each round, so they run far leaner in a fresh session than at the end of a long one. Plan to commit first, then run them after /compact or in a new session.
```

---

## File Structure

| file | responsibility | change |
|---|---|---|
| `clavity-dotnet/plugin/hooks/agy-seam-inject.sh` | routes superpowers seams to disciplines | append SESSION POSTURE to the AGY-FIRST arm, COST to the AGY-CAPSTONE arm |
| `clavity-classic/plugin/hooks/agy-seam-inject.sh` | same, mirrored | identical edit |
| `clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh` | nudges the test audit after capstone green | append COST |
| `clavity-classic/plugin/hooks/agy-test-audit-reminder.sh` | same, mirrored | identical edit |
| `scripts/tests/agy-seam-inject.Tests.ps1` | pins that hook's behaviour | +2 positive, +1 negative, +1 parity |
| `scripts/tests/agy-test-audit-reminder.Tests.ps1` | pins that hook's behaviour | +1 positive |
| `scripts/tests/agy-after-reminder.Tests.ps1` | pins that hook's behaviour | +1 negative, +1 parity |
| `clavity-dotnet/plugin/README.md` | plugin user docs | + the full section |
| `clavity-classic/plugin/README.md` | plugin user docs | + the full section |
| `README.md` | umbrella entry point | + one pointer line |
| `scripts/tests/_partition.md` | records measured suite counts | both counts re-measured |

**Deliberately NOT touched:** `agy-after-reminder.sh` itself (either driver) — the placement rule excludes it because its trigger is not durable; the ANOMALY-CAPTURE arm of `agy-seam-inject.sh`; every `jq`-missing fallback branch; `agy-drive-session-reset.sh` (classic-only, convenes nothing).

---

### Task 1: SESSION POSTURE on the AGY-FIRST seam

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-seam-inject.sh:75`
- Modify: `clavity-classic/plugin/hooks/agy-seam-inject.sh:75`
- Test: `scripts/tests/agy-seam-inject.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Add inside the existing `Describe 'agy-seam-inject.sh'` block, after the `It 'injects the AGY-FIRST directive on a brainstorm seam'` test:

```powershell
    It 'carries the SESSION POSTURE line on the brainstorm seam' {
        $repo = New-TempRepo
        try {
            $cwd = ($repo -replace '\\','/')
            $out = Invoke-Hook -Skill 'superpowers:brainstorming' -Cwd $cwd
            $out | Should -Match 'SESSION POSTURE:'
            $out | Should -Match 'commit first'
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

- [ ] **Step 2: Run it and watch it FAIL**

```bash
pwsh -c "Invoke-Pester 'scripts/tests/agy-seam-inject.Tests.ps1' -Output Detailed"
```

Expected: the new test FAILS with `Expected regular expression 'SESSION POSTURE:' to match ...`. Every other test in the file still passes.

- [ ] **Step 3: Edit the dotnet hook**

In `clavity-dotnet/plugin/hooks/agy-seam-inject.sh`, find the line that **begins** `emit 'AGY-FIRST auto-fire:` (line 75). Do not match on its tail — line 77 ends identically.

That line currently ends:

```
... If agy is unreachable, the skill'"'"'s SKIPPED-UNREACHABLE path applies - proceed, do not hang.' ;;
```

Change the ending to (single space after the full stop, clause inserted before the closing `'`):

```
... If agy is unreachable, the skill'"'"'s SKIPPED-UNREACHABLE path applies - proceed, do not hang. SESSION POSTURE: reviews later in this work (capstone, test audit, panel) re-read the whole session context each round, so they run far leaner in a fresh session than at the end of a long one. Plan to commit first, then run them after /compact or in a new session.' ;;
```

Introduce **no newline** — this must stay one line. `agy-seam-inject.Tests.ps1`'s existing test asserts exactly one line matching `hookSpecificOutput`.

- [ ] **Step 4: Verify the file is still valid bash and still pure ASCII**

```bash
bash -n clavity-dotnet/plugin/hooks/agy-seam-inject.sh && echo "SYNTAX OK"
python -c "b=open(r'clavity-dotnet/plugin/hooks/agy-seam-inject.sh','rb').read(); print('NON-ASCII BYTES:', sum(1 for x in b if x>127))"
```

Expected: `SYNTAX OK` and `NON-ASCII BYTES: 0`.

- [ ] **Step 5: Run the test and watch it PASS**

```bash
pwsh -c "Invoke-Pester 'scripts/tests/agy-seam-inject.Tests.ps1' -Output Detailed"
```

Expected: all tests pass, including `ships as pure ASCII`.

- [ ] **Step 6: Mirror the edit to clavity-classic**

Apply the byte-identical change to `clavity-classic/plugin/hooks/agy-seam-inject.sh:75`, then prove parity:

```bash
diff clavity-dotnet/plugin/hooks/agy-seam-inject.sh clavity-classic/plugin/hooks/agy-seam-inject.sh && echo "IDENTICAL"
```

Expected: `IDENTICAL` with no diff output.

- [ ] **Step 7: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-seam-inject.sh clavity-classic/plugin/hooks/agy-seam-inject.sh scripts/tests/agy-seam-inject.Tests.ps1
git commit -m "feat(agy-autotrain): session-posture line on the brainstorm seam"
```

---

### Task 2: COST clause on the AGY-CAPSTONE seam

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-seam-inject.sh:77`
- Modify: `clavity-classic/plugin/hooks/agy-seam-inject.sh:77`
- Test: `scripts/tests/agy-seam-inject.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

Add after the `It 'injects the AGY-CAPSTONE directive on a finishing-a-development-branch seam'` test:

```powershell
    It 'carries the COST clause on the capstone seam' {
        $repo = New-TempRepo
        try {
            $cwd = ($repo -replace '\\','/')
            $out = Invoke-Hook -Skill 'superpowers:finishing-a-development-branch' -Cwd $cwd
            $out | Should -Match 'COST:'
            $out | Should -Match 'never WHETHER'
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT put the COST clause on the brainstorm seam' {
        $repo = New-TempRepo
        try {
            $cwd = ($repo -replace '\\','/')
            $out = Invoke-Hook -Skill 'superpowers:brainstorming' -Cwd $cwd
            $out | Should -Not -Match 'COST:'
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

- [ ] **Step 2: Run and watch the FIRST fail — and understand why the second does not**

```bash
pwsh -c "Invoke-Pester 'scripts/tests/agy-seam-inject.Tests.ps1' -Output Detailed"
```

Expected: `carries the COST clause on the capstone seam` FAILS. **`does NOT put the COST clause on the brainstorm seam` PASSES immediately** — that is correct and expected. A negative assertion cannot go RED on clean baseline, because the forbidden string does not exist yet. It is proven non-vacuous by mutation in Step 6, not by watching it fail here. Do not contort it to fail.

- [ ] **Step 3: Edit the dotnet hook**

Find the line **beginning** `emit 'AGY-CAPSTONE auto-fire:` (line 77). Change its ending from:

```
... If agy is unreachable, the skill'"'"'s SKIPPED-UNREACHABLE path applies - proceed, do not hang.' ;;
```

to:

```
... If agy is unreachable, the skill'"'"'s SKIPPED-UNREACHABLE path applies - proceed, do not hang. COST: this discipline re-reads the whole session context every round, so running it in a long session burns several times the tokens - and subscription quota - of running it fresh. If this session carries substantial history, do not run it inline: tell the user it runs about 5x leaner after /compact or in a fresh session, and follow their answer. This changes WHERE the review runs, never WHETHER.' ;;
```

- [ ] **Step 4: Verify syntax and ASCII**

```bash
bash -n clavity-dotnet/plugin/hooks/agy-seam-inject.sh && echo "SYNTAX OK"
python -c "b=open(r'clavity-dotnet/plugin/hooks/agy-seam-inject.sh','rb').read(); print('NON-ASCII BYTES:', sum(1 for x in b if x>127))"
```

Expected: `SYNTAX OK`, `NON-ASCII BYTES: 0`.

- [ ] **Step 5: Run tests and watch them PASS**

```bash
pwsh -c "Invoke-Pester 'scripts/tests/agy-seam-inject.Tests.ps1' -Output Detailed"
```

Expected: all pass, including both new tests.

- [ ] **Step 6: Prove the negative assertion is non-vacuous by mutation**

Temporarily append ` COST: mutant` immediately before the closing `'` of the **AGY-FIRST** line (75), then:

```bash
pwsh -c "Invoke-Pester 'scripts/tests/agy-seam-inject.Tests.ps1' -Output Detailed"
```

Expected: `does NOT put the COST clause on the brainstorm seam` now **FAILS**. If it still passes, the mutation did not land — confirm with `git diff --stat` that the file actually changed, check you edited line 75 and not 77, and re-run. **Do not proceed until you have seen it fail.**

Now remove the mutation by **deleting the ` COST: mutant` text by hand**. Do **not** use `git checkout --` on this file: your Step 3 edit is uncommitted and would be destroyed with it. Then confirm:

```bash
pwsh -c "Invoke-Pester 'scripts/tests/agy-seam-inject.Tests.ps1' -Output Detailed"
```

Expected: all pass again.

- [ ] **Step 7: Mirror to clavity-classic and prove parity**

```bash
diff clavity-dotnet/plugin/hooks/agy-seam-inject.sh clavity-classic/plugin/hooks/agy-seam-inject.sh && echo "IDENTICAL"
```

Expected: `IDENTICAL`.

- [ ] **Step 8: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-seam-inject.sh clavity-classic/plugin/hooks/agy-seam-inject.sh scripts/tests/agy-seam-inject.Tests.ps1
git commit -m "feat(agy-autotrain): cost clause on the capstone seam"
```

---

### Task 3: COST clause on the test-audit reminder

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh:68`
- Modify: `clavity-classic/plugin/hooks/agy-test-audit-reminder.sh:68`
- Test: `scripts/tests/agy-test-audit-reminder.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Add inside `Describe 'agy-test-audit-reminder.sh'`, immediately before the `It 'ships as pure ASCII'` test:

```powershell
    It 'carries the COST clause when it fires' {
        $r = New-FiredRepo
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Head
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut | Should -Match 'COST:'
            $out.StdOut | Should -Match 'never WHETHER'
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

Three things about this idiom that are easy to get wrong, all copied from the existing
`It 'FIRES the audit nudge when capstone.head==HEAD, no audit marker, code changed'` test in the same file:

- **`New-FiredRepo` returns an object, not a path** — `$r.Dir` and `$r.Head`. (The function's own comment says "Returns the repo dir", which is stale; trust the code.)
- **The fire state needs `Set-Marker $r.Dir 'agy-capstone' $r.Head`** — without it the hook is correctly silent and your test proves nothing.
- **The payload goes through `New-AuditPayload`**, and the cwd through the `$script:Cwd` scriptblock, which backslash-normalises it.

- [ ] **Step 2: Run and watch it FAIL**

```bash
pwsh -c "Invoke-Pester 'scripts/tests/agy-test-audit-reminder.Tests.ps1' -Output Detailed"
```

Expected: the new test FAILS on `COST:` not matching. If it instead fails because the hook produced no output at all, `New-FiredRepo` did not reach the fire state — fix that before continuing, or the test proves nothing.

- [ ] **Step 3: Edit the dotnet hook**

Line 68 currently ends:

```
... halt-and-ask or abort `[VERDICT: agy-required-but-unreachable]` - never a silent pass.'
```

Change the ending to:

```
... halt-and-ask or abort `[VERDICT: agy-required-but-unreachable]` - never a silent pass. COST: this discipline re-reads the whole session context every round, so running it in a long session burns several times the tokens - and subscription quota - of running it fresh. If this session carries substantial history, do not run it inline: tell the user it runs about 5x leaner after /compact or in a fresh session, and follow their answer. This changes WHERE the review runs, never WHETHER.'
```

The existing backticks around `[VERDICT: ...]` are literal because this is a single-quoted string — leave them exactly as they are, and add none of your own.

- [ ] **Step 4: Verify syntax and ASCII**

```bash
bash -n clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh && echo "SYNTAX OK"
python -c "b=open(r'clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh','rb').read(); print('NON-ASCII BYTES:', sum(1 for x in b if x>127))"
```

Expected: `SYNTAX OK`, `NON-ASCII BYTES: 0`.

- [ ] **Step 5: Mirror to classic, then run the suite**

The existing `It 'is byte-identical to the clavity-classic mirror'` test will go RED after you edit dotnet and GREEN once classic matches — a genuine red-then-green for parity. Run it after the dotnet edit to see it fail:

```bash
pwsh -c "Invoke-Pester 'scripts/tests/agy-test-audit-reminder.Tests.ps1' -Output Detailed"
```

Expected: `is byte-identical to the clavity-classic mirror` FAILS.

Apply the identical edit to `clavity-classic/plugin/hooks/agy-test-audit-reminder.sh:68`, then re-run:

```bash
pwsh -c "Invoke-Pester 'scripts/tests/agy-test-audit-reminder.Tests.ps1' -Output Detailed"
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh clavity-classic/plugin/hooks/agy-test-audit-reminder.sh scripts/tests/agy-test-audit-reminder.Tests.ps1
git commit -m "feat(agy-autotrain): cost clause on the test-audit reminder"
```

---

### Task 4: Pin the exclusions — parity assertions for the two unpinned hooks

Both hooks under `agy-seam-inject` and `agy-after-reminder` currently have **no** cross-driver parity test. `agy-after-reminder` needs one even though its hook is never edited: every suite roots `$script:Hook` at the dotnet copy, so the negative assertion pinning its exclusion only ever inspects one driver.

**Files:**
- Test: `scripts/tests/agy-seam-inject.Tests.ps1`
- Test: `scripts/tests/agy-after-reminder.Tests.ps1`

- [ ] **Step 1: Write the negative assertion for agy-after-reminder**

Add inside `Describe 'agy-after-reminder.sh'`:

```powershell
    It 'does NOT carry the cost clause (its trigger is not durable)' {
        $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-WritePayload 'docs/superpowers/specs/x.md')
        $r.StdOut | Should -Not -Match 'COST:'
        $r.StdOut | Should -Not -Match 'SESSION POSTURE:'
    }
```

- [ ] **Step 2: Write both parity assertions**

In `scripts/tests/agy-seam-inject.Tests.ps1`, add as the last `It` inside the `Describe`:

```powershell
    It 'is byte-identical to the clavity-classic mirror' {
        $classic = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'clavity-classic/plugin/hooks/agy-seam-inject.sh'
        (Get-FileHash $script:Hook).Hash | Should -Be (Get-FileHash $classic).Hash
    }
```

In `scripts/tests/agy-after-reminder.Tests.ps1`, add as the last `It` inside the `Describe`:

```powershell
    It 'is byte-identical to the clavity-classic mirror' {
        $classic = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'clavity-classic/plugin/hooks/agy-after-reminder.sh'
        (Get-FileHash $script:Hook).Hash | Should -Be (Get-FileHash $classic).Hash
    }
```

- [ ] **Step 3: Run both suites — all three new tests should PASS immediately**

```bash
pwsh -c "Invoke-Pester @('scripts/tests/agy-seam-inject.Tests.ps1','scripts/tests/agy-after-reminder.Tests.ps1') -Output Detailed"
```

Expected: all pass. This is correct — a negative assertion and a parity assertion both pass on a consistent baseline. They are proven in Step 4.

- [ ] **Step 4: Prove all three non-vacuous by mutation, one at a time**

**Mutation A — the negative assertion.** Append ` COST: mutant` before the closing `"` of `clavity-dotnet/plugin/hooks/agy-after-reminder.sh:36`, run:

```bash
pwsh -c "Invoke-Pester 'scripts/tests/agy-after-reminder.Tests.ps1' -Output Detailed"
```

Expected: `does NOT carry the cost clause` FAILS. Remove the mutant, re-run, expect pass.

**Mutation B — agy-seam-inject parity.** Append a single space to the end of `clavity-classic/plugin/hooks/agy-seam-inject.sh`, run:

```bash
pwsh -c "Invoke-Pester 'scripts/tests/agy-seam-inject.Tests.ps1' -Output Detailed"
```

Expected: `is byte-identical to the clavity-classic mirror` FAILS. Remove the space, re-run, expect pass.

**Mutation C — agy-after-reminder parity.** Same, on `clavity-classic/plugin/hooks/agy-after-reminder.sh`. Expect FAIL, then revert, then pass.

**If any mutation does not produce a failure, the mutation did not land.** Confirm with `git diff --stat` that the file actually changed before concluding the test is weak.

- [ ] **Step 5: Commit**

```bash
git add scripts/tests/agy-seam-inject.Tests.ps1 scripts/tests/agy-after-reminder.Tests.ps1
git commit -m "test(agy-autotrain): pin the cost-clause exclusions and cross-driver parity"
```

---

### Task 5: The README section

**Files:**
- Modify: `clavity-dotnet/plugin/README.md` (insert after `## What's in here`, which is at `:10`)
- Modify: `clavity-classic/plugin/README.md` (insert after `## What's in here`, which is at `:10`)
- Modify: `README.md` (append one line to the end of `## How to get started`, which begins at `:27`)

There is no test for this task; it is prose. Verify by reading.

- [ ] **Step 1: Insert the section into both plugin READMEs**

Insert this verbatim, immediately **after** the `## What's in here` section and **before** `## Install / registration`, in **both** files. It is an H2 to match the surrounding skeleton.

```markdown
## Running this economically

clavity's review disciplines are multi-round by design — that's where the defects come from. But ~87% of an agent session's token use is re-reading its own accumulated context rather than producing new output. **Every turn re-reads everything before it**, so a review run at the end of a long session consumes several times the tokens it would in a fresh one.

Measured on one real session — 305 turns of work at a ~380k context versus the same turns at 40k: about **9x the tokens read, for identical work**.

- **On a subscription**, tokens are what matter: a review fired at high context burns through your usage window far faster, and that is what stops work mid-task. Check `/usage` before starting a long review.
- **On API billing**, that same run measured $249 against $47.

Three habits, in order of payoff:

1. **Two chats.** Implement and commit in one session. Then `/compact`, or open a fresh chat, and run the review there: *"run agy-capstone on `<range>`"*. Same rigor, a fraction of the tokens.
2. **Match the ceremony to the stakes.** The full harness is built for code where a missed defect is expensive. On a smaller project, the cheapest move is habit 1 rather than switching anything off — the disciplines still run, they just cost a fraction. Several of them are triggered by hooks rather than invoked by you, and they are not individually switchable today; a finer-grained mode is under consideration.
3. **Fix coverage gaps inline, for free.** Notice a missing test while implementing? Just ask for it then — *"add a test for that case"*. One turn. Convening a full audit to rediscover the same gap costs many. Save the convened audit for the gaps you *didn't* notice.

**Turning it down.** If you do need to silence the disciplines, `.no-agy` in your project root or `~/.claude/` does it — but it is deliberately all-or-nothing, so it silences **every** one of them, including the cheap ones. It is a last resort rather than a tuning knob; try habit 1 first. A finer-grained mode is under consideration.
```

Unlike the hook strings, this is markdown prose — em-dashes and apostrophes are fine here and match the surrounding files.

- [ ] **Step 2: Add the pointer to the root README**

Append as the final line of the `## How to get started` section in `README.md`:

```markdown
Review disciplines are multi-round; see **Running this economically** in the plugin README before you start.
```

- [ ] **Step 3: Verify placement in all three files**

```bash
rg -n '^## ' clavity-dotnet/plugin/README.md clavity-classic/plugin/README.md | head -12
rg -n 'Running this economically' README.md clavity-dotnet/plugin/README.md clavity-classic/plugin/README.md
```

Expected: `## Running this economically` appears between `## What's in here` and `## Install / registration` in both plugin READMEs, and the pointer line appears once in the root README.

- [ ] **Step 4: Commit**

```bash
git add README.md clavity-dotnet/plugin/README.md clavity-classic/plugin/README.md
git commit -m "docs: add a Running this economically section to both plugin READMEs"
```

---

### Task 6: Re-measure both partition counts

`_partition.md` records **measured** counts. Its own rule forbids computing them by addition or subtraction — the recipe must be run.

**Files:**
- Modify: `scripts/tests/_partition.md`

Both halves move: `agy-seam-inject.Tests.ps1` and `agy-test-audit-reminder.Tests.ps1` are in `test-scripts-slow` (`justfile:101`), and `agy-after-reminder.Tests.ps1` is in `test-scripts-fast` (`justfile:94`).

- [ ] **Step 1: Measure the fast half**

```bash
just test-scripts-fast
```

Record the `Tests Passed: N` figure and the elapsed time.

- [ ] **Step 2: Measure the slow half — BACKGROUNDED**

`test-scripts-slow` has measured ~500s and has exceeded the 600s foreground tool cap before. **An agent must run it backgrounded**, then block by watching that run's own output for its `Tests completed` line — never by polling a process count, and never by polling git while it runs.

If you are an agent with a background-execution facility, use it (Claude Code: `run_in_background: true` on the Bash call, then read the task output). If you are a human at a terminal, just run it in the foreground and wait:

```bash
just test-scripts-slow
```

Record `Tests Passed: N` and elapsed time. Do not start any other git-touching command while it runs.

- [ ] **Step 3: Update `_partition.md`**

Update the fast and slow counts in the prose (currently `fast 173 and slow 210`) with the two measured figures, and add a row to the `## Measured runtimes` block for any suite whose time changed materially. Do not compute either number by addition.

- [ ] **Step 4: Verify the structural oracle still passes**

```bash
diff <(ls scripts/tests/*.Tests.ps1 | xargs -n1 basename | sort) \
     <(grep -oE "scripts/tests/[A-Za-z0-9._-]+\.Tests\.ps1" justfile | xargs -n1 basename | sort -u)
```

Expected: no output, exit 0. This change adds no new test **files**, so it should be unaffected — confirm rather than assume.

- [ ] **Step 5: Commit**

```bash
git add scripts/tests/_partition.md
git commit -m "test: re-measure both partition counts after the cost-clause assertions"
```

---

## Final verification

- [ ] **All four hook files still pure ASCII and syntactically valid**

```bash
for f in clavity-dotnet/plugin/hooks/agy-seam-inject.sh clavity-classic/plugin/hooks/agy-seam-inject.sh clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh clavity-classic/plugin/hooks/agy-test-audit-reminder.sh; do
  bash -n "$f" || echo "SYNTAX FAIL $f"
  python -c "import sys; b=open(sys.argv[1],'rb').read(); print(sys.argv[1], 'non-ascii:', sum(1 for x in b if x>127))" "$f"
done
```

Expected: no syntax failures, every count `0`.

- [ ] **All three mirrored hook pairs identical**

```bash
for f in agy-seam-inject.sh agy-test-audit-reminder.sh agy-after-reminder.sh; do
  diff -q "clavity-dotnet/plugin/hooks/$f" "clavity-classic/plugin/hooks/$f" && echo "IDENTICAL $f"
done
```

Expected: three `IDENTICAL` lines.

- [ ] **The exclusions actually hold**

```bash
rg -c 'COST:|SESSION POSTURE:' clavity-dotnet/plugin/hooks/agy-after-reminder.sh
```

Expected: no match (the hook must carry neither).

- [ ] **AGY-CAPSTONE re-run.** This change edits executable code and tests, so the capstone gate applies to the finished range before the branch may be declared done.

---

## Acceptance criteria (from the spec)

1. COST clause in exactly two directive sites — `agy-test-audit-reminder.sh:68` and `agy-seam-inject.sh:77` — on both drivers.
2. SESSION POSTURE in exactly one site — `agy-seam-inject.sh:75` — on both drivers.
3. `agy-after-reminder.sh` and the ANOMALY-CAPTURE arm unchanged.
4. The two touched hook files (carrying all three directive sites) byte-identical across drivers.
5. Every touched hook passes its ASCII byte test; no clause text contains a backtick or apostrophe.
6. Positive assertions watched RED first; negative assertions proven by a mutation verified to have landed.
7. The full section in both plugin READMEs; the pointer in the root README.
8. `agy-seam-inject.Tests.ps1` and `agy-after-reminder.Tests.ps1` each gain a parity assertion.
9. Both `_partition.md` counts re-measured by running each recipe.
10. No change to `.no-agy` semantics, to any round count, or to any gate's pass condition.

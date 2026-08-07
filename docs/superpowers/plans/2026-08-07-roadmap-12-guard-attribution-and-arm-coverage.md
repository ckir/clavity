# ROADMAP §12 — guard attribution + the untested emission arm · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Close ROADMAP §12a (the consult guard cannot attribute a VCS change to the peer rather than to a
concurrent local agent) and §12b (the `UserPromptSubmit` emission arm's jq-absent path has zero test
coverage).

**Architecture:** Two independent, bounded changes with no shared files. §12b is **test-only** — it adds one
comparison to an existing suite and changes no shipped code. §12a is a **message-text change** to one hook,
mirrored byte-identically to the second driver. Neither introduces a new file, a new hook, or a new
registration.

**Tech Stack:** bash hooks (POSIX-ish, fail-open), Pester 5, `jq`, Git Bash on Windows.

---

## What was measured before this plan was written

Every citation below was read against the file **today, after plan 2 landed**. That matters: §12b's first
draft cited a comment at `agy-anomaly-capture-reminder.sh:29-30` that **plan 2 had already deleted**, and
the entry was rewritten before this plan was started. The measurements here are post-plan-2.

1. **`agy-consult-guard-post.sh` is 91 lines** (`wc -l`); the breach message is a single assignment at
   **line 89**, and `emit "$msg"` at 90. The file is currently **byte-identical** to
   `clavity-classic/plugin/hooks/agy-consult-guard-post.sh` (`cmp -s` → identical).
2. **The message already instructs verification first** — *"verify the peer (not you) made these
   changes"* — before it suggests any revert. The defect is that it does not name the one confound that
   makes verification necessary. **MEASURED 2026-08-07:** the guard fired naming three files a local
   implementer subagent was mid-edit on, one of which carried a deliberate temporary mutation; the peer had
   changed nothing.
3. **`agy-consult-guard.Tests.ps1` is 146 lines**, defines `New-GuardRepo` (`:13`) and `Payload` (`:23`),
   and its WARN tests follow a fixed shape at `:28-39`. Two file-level gates already constrain any edit:
   **pure ASCII** (`:115-119`) and **byte-identical to the classic mirror** (`:121-127`).
4. **`agy-anomaly-capture-reminder.sh` is 202 lines** with two emission arms, each having a `jq` and a
   hand-built jq-absent path: `UserPromptSubmit` → `hookSpecificOutput` (`:156` printf, `:199` jq);
   everything else → `systemMessage` (`:157` printf, `:200` jq).
5. 🔴 **Every `NoJqPath` test in `agy-anomaly-capture-reminder.Tests.ps1` (`:119`, `:138`, `:171`, `:208`,
   `:217`) invokes the hook with NO `-Arguments`**, so all of them take the `PreCompact` branch. **The count
   of tests exercising the `UserPromptSubmit` arm's jq-absent path is ZERO.** Probed directly, that path
   works today — it emits valid JSON whose `hookEventName` is `UserPromptSubmit` — but nothing would notice
   if it stopped.
6. **The existing parity test at `:135-142`** compares the decoded `.systemMessage` of both paths and
   carries a non-vacuity guard (`:139-140`) whose comment records why: a prior version of it *"passed green
   against a hook that did not exist"*, because `$null` equalled `$null`.
7. **`Invoke-BashHook` returns `StdOut = $out.Trim()`** (`BashHookHelpers.ps1:53`). This is load-bearing for
   Task 1: it normalizes the platform's trailing-newline difference, so comparing the two paths' `.StdOut`
   directly tolerates CRLF-vs-LF while still catching a structural divergence.

### Recorded so it is not re-discovered as a defect

The two emission paths are **not** byte-identical on this platform: Windows `jq` terminates with `\r\n`,
the hand-built `printf` with `\n` (611 vs 610 bytes on the new arm; 600 vs 599 on the old, so it predates
plan 2). A trailing line ending is harmless to a JSON consumer. **Do not "fix" the line ending**, and do not
write a test that would fail because of it.

---

## File structure

| File | Change | Responsibility |
|---|---|---|
| `scripts/tests/agy-anomaly-capture-reminder.Tests.ps1` | Modify | §12b: one new test pinning the new arm's jq-absent path |
| `clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh` | Modify | §12a: the breach message names the attribution confound |
| `clavity-classic/plugin/hooks/agy-consult-guard-post.sh` | Modify | **Byte-identical mirror.** Non-negotiable |
| `scripts/tests/agy-consult-guard.Tests.ps1` | Modify | §12a: pin the new clause |
| `clavity-dotnet/ROADMAP.md` | Modify | §12 status |

**No new file is created, so no `justfile` test-registration change is expected.** Confirm that rather than
assuming it.

---

## Task 1: Pin the `UserPromptSubmit` arm's jq-absent path (§12b)

**Files:**
- Test: `scripts/tests/agy-anomaly-capture-reminder.Tests.ps1`

**This task changes no shipped code.** It closes a coverage gap, so the *test must be proven to fail*
against a deliberately broken hook before it is trusted.

- [ ] **Step 1: Verify state**

Confirm all of these are true right now, and **STOP with `STATE_MISMATCH: <what differs>` if any is not**:

- `clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh` is **202 lines**; line 156 is the
  `UserPromptSubmit` printf arm and line 157 the `systemMessage` printf arm.
- `scripts/tests/agy-anomaly-capture-reminder.Tests.ps1` defines, inside its `BeforeAll`, the helpers
  `New-CleanHome`, `New-Workspace`, `New-GateEnv`, `Invoke-Prompt`, and `$script:NoJqPath`.
- Running `pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-anomaly-capture-reminder.Tests.ps1 -Output Normal"` reports **`Tests Passed: 25, Failed: 0`**.

- [ ] **Step 2: Write the failing test**

Add to `scripts/tests/agy-anomaly-capture-reminder.Tests.ps1`, inside the existing `Describe`, next to the
other gate tests:

```powershell
It 'delivers the SAME UserPromptSubmit envelope with and without jq' {
    # THE GAP THIS CLOSES. Every other NoJqPath test in this file passes no -Arguments, so all of them
    # take the PreCompact branch. Before this test, the number of tests exercising the UserPromptSubmit
    # arm's hand-built jq-absent printf was ZERO. That branch is the one most installs actually run, it
    # builds JSON by hand with no escaping machinery, and a malformed brace or a wrong key there emits
    # nothing the model can read -- with no error, and looking installed and working.
    #
    # Two SEPARATE gate environments, because the gate is per-session and never emits on prompt 1:
    # each path needs its own session id and its own marker directory, or the second would be suppressed.
    $w  = New-Workspace
    $a  = New-GateEnv    # jq present
    $b  = New-GateEnv    # jq absent
    $pa = '{"cwd":"' + ($w -replace '\\','/') + '","session_id":"' + $a.Sid + '"}'
    $pb = '{"cwd":"' + ($w -replace '\\','/') + '","session_id":"' + $b.Sid + '"}'

    $null   = Invoke-BashHook -HookPath $script:Hook -Payload $pa -Arguments @('UserPromptSubmit') -Env @{ HOME = $a.Home; TMPDIR = $a.Tmp }
    $withJq = (Invoke-BashHook -HookPath $script:Hook -Payload $pa -Arguments @('UserPromptSubmit') -Env @{ HOME = $a.Home; TMPDIR = $a.Tmp }).StdOut

    $null   = Invoke-BashHook -HookPath $script:Hook -Payload $pb -Arguments @('UserPromptSubmit') -Env @{ HOME = $b.Home; TMPDIR = $b.Tmp; PATH = $script:NoJqPath }
    $noJq   = (Invoke-BashHook -HookPath $script:Hook -Payload $pb -Arguments @('UserPromptSubmit') -Env @{ HOME = $b.Home; TMPDIR = $b.Tmp; PATH = $script:NoJqPath }).StdOut

    # NON-VACUITY, and it is not decoration. The sibling test at :139-140 records why: an equality
    # assertion is satisfied when BOTH paths emit nothing, and a prior version of that test passed green
    # against a hook that did not exist, because $null equalled $null.
    $withJq | Should -Not -BeNullOrEmpty -Because 'two silent paths are trivially identical'
    $noJq   | Should -Not -BeNullOrEmpty -Because 'two silent paths are trivially identical'

    # RAW stdout, not a decoded field. Invoke-BashHook already Trim()s, which normalizes the platform's
    # trailing-newline difference (Windows jq emits CRLF, printf emits LF) -- so this tolerates the line
    # ending while still catching a structural divergence: a different key, a dropped field, a lost brace.
    $noJq | Should -BeExactly $withJq
}
```

- [ ] **Step 3: Run it and verify it PASSES**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-anomaly-capture-reminder.Tests.ps1 -Output Detailed"`
Expected: `Tests Passed: 26, Failed: 0`.

⚠️ **A new test that passes immediately proves nothing yet.** This one is expected to pass — the path works
today; the defect is that it was unpinned. Step 4 is therefore **not optional**: it is the only evidence
this test is an oracle rather than decoration.

- [ ] **Step 4: Prove the test is non-vacuous — MANDATORY**

Temporarily break the jq-absent `UserPromptSubmit` arm. In
`clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh`, change line 156 from:

```bash
    UserPromptSubmit) printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$msg" ;;
```

to a version with the key misspelled:

```bash
    UserPromptSubmit) printf '{"hookSpecificOutput":{"hookEventNam":"UserPromptSubmit","additionalContext":"%s"}}\n' "$msg" ;;
```

Re-run the suite.

**Expect EXACTLY ONE test red:** `delivers the SAME UserPromptSubmit envelope with and without jq`.

Every other test either uses the `jq` path (unaffected) or the `PreCompact` branch (unaffected) — **which
is the whole point of this entry.** If a second test goes red, something else reads that line and this plan
has not accounted for it: **stop and report which.** If NO test goes red, the new test is not reading the
jq-absent path at all: **stop and report that.**

Restore line 156 exactly, then confirm the file is unchanged:
`git diff --exit-code clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh` must print nothing and
exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/tests/agy-anomaly-capture-reminder.Tests.ps1
git commit -m "test(hooks): pin the UserPromptSubmit arm's jq-absent emission path"
```

---

## Task 2: The consult guard names its attribution confound (§12a, dotnet)

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh` (91 lines; the message is line 89)
- Test: `scripts/tests/agy-consult-guard.Tests.ps1` (146 lines)

- [ ] **Step 1: Verify state**

Confirm and **STOP with `STATE_MISMATCH: <what differs>`** if any differs:

- `clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh` is **91 lines** (`wc -l`).
- Line 89 begins `msg="AGY CONSULT GUARD - VERSION CONTROL CHANGED DURING A REVIEW-ONLY CONSULT:` and is a
  single-line assignment; line 90 is `emit "$msg"`.
- `cmp -s clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh clavity-classic/plugin/hooks/agy-consult-guard-post.sh`
  reports the files **identical**.
- `scripts/tests/agy-consult-guard.Tests.ps1` defines `New-GuardRepo` and `Payload`, and contains a test
  `WARNS when version control changes across an MCP consult` at `:28`.

- [ ] **Step 2: Write the failing test**

Add to `scripts/tests/agy-consult-guard.Tests.ps1`, after the test at `:28-39`, matching its shape exactly:

```powershell
It 'names the concurrent-local-agent confound in the breach warning' {
    # The guard detects a VCS delta across the consult window. It CANNOT attribute that delta to the
    # peer rather than to anything else running in the same repository at the same time.
    # MEASURED 2026-08-07: it fired naming the three files a local implementer subagent was mid-edit on,
    # one carrying a deliberate temporary mutation, while the peer had changed nothing.
    # This matters because the message's next instruction is a revert: a driver who acts on it without
    # verifying would destroy that subagent's in-flight work.
    $r = New-GuardRepo
    try {
        $p = Payload 'mcp__plugin_clavity_clavity-ls__agy_ask' '' $r
        Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
        Push-Location $r; Set-Content 'b.txt' 'two' -Encoding ascii; git add b.txt; git commit -qm peer; Pop-Location
        $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
        $out | Should -Match 'VERSION CONTROL CHANGED' -Because 'the existing alarm must still fire'
        $out | Should -Match 'CANNOT attribute'
        $out | Should -Match 'concurrent'
    } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
}
```

- [ ] **Step 3: Run and verify it FAILS**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-consult-guard.Tests.ps1 -Output Detailed"`
Expected: the new test fails on `CANNOT attribute`; every other test passes. **Read the COUNT** — a run that
matches nothing still exits 0.

- [ ] **Step 4: Add the clause**

Replace line 89 of `clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh` with:

```bash
msg="AGY CONSULT GUARD - VERSION CONTROL CHANGED DURING A REVIEW-ONLY CONSULT: the agy peer appears to have modified git state during a consult that was supposed to make ZERO changes. What changed: ${axes}CAVEAT - this guard compares VCS state before and after the consult and CANNOT attribute a change to the peer rather than to anything else running in this repository at the same time. If you dispatched a local subagent, or another session is open on this repo, that is the likelier cause, and reverting would destroy its in-flight work. Next: verify the peer - not you, and not a concurrent local agent - made these changes; if so, undo them with a TARGETED per-file 'git checkout -- <file>' / 'git reset' (NEVER a broad 'git checkout <dir>/'), then re-issue the consult with a louder forbidden-actions banner. Changed paths:\n${paths}${headmsg}"
```

🔴 **SHAPE-DIVERGENCE STOP.** The `${axes}`, `${paths}` and `${headmsg}` expansions, the `\n` before
`${paths}`, and the surrounding double quotes must all survive unchanged. If making this fit would alter
any of them, **STOP and report `[original] -> [yours] because <reason>`**.

⚠️ **PURE ASCII ONLY.** `agy-consult-guard.Tests.ps1:115-119` asserts every byte of this file is `<= 127`.
No em-dash, no smart quote, no ellipsis character. The text above is already ASCII — keep it that way.

⚠️ **Do NOT weaken the alarm.** Do not narrow the seven axes, do not downgrade the wording of the breach
itself, and do not make the guard silent when local agents are active. A prior capstone caught a real
index-smuggle through one of those axes. **The defect is attribution, not detection.**

- [ ] **Step 5: Run and verify it PASSES**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-consult-guard.Tests.ps1 -Output Detailed"`
Expected: `Tests Passed: <n>, Failed: 0` — but see Step 6 first: the mirror test will fail until Task 3
lands, and that is expected.

🔴 **The test `is byte-identical to the clavity-classic mirror` (`:121-127`) WILL FAIL at this point**,
because only the dotnet copy has changed. That is the expected intermediate state, not a defect. Record it
and proceed to Task 3, which fixes it. **Do not "fix" it by reverting the dotnet change.**

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh scripts/tests/agy-consult-guard.Tests.ps1
git commit -m "fix(hooks): the consult guard names the concurrent-local-agent confound"
```

---

## Task 3: Mirror the guard to clavity-classic, byte-identically

**Files:**
- Modify: `clavity-classic/plugin/hooks/agy-consult-guard-post.sh`

- [ ] **Step 1: Copy, do not re-type**

```bash
cp clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh clavity-classic/plugin/hooks/agy-consult-guard-post.sh
```

Re-typing invites a one-byte drift the parity gate will catch only after wasting a cycle. **Do not
"normalize" line endings** — editing an LF file has silently converted it to CRLF four or more times in
this repo.

- [ ] **Step 2: Verify byte parity**

```bash
cmp clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh clavity-classic/plugin/hooks/agy-consult-guard-post.sh && echo IDENTICAL
```
Expected: `IDENTICAL`

- [ ] **Step 3: Run the gates**

```
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-consult-guard.Tests.ps1,scripts/tests/plugin-hooks-payload.Tests.ps1 -Output Detailed"
```
Expected: `Failed: 0` — including the mirror test that failed at the end of Task 2.

```bash
bash scripts/check-seed-artifacts-synced.sh
```
Expected: exits 0.

**NAME THE ORACLE:** `agy-consult-guard.Tests.ps1:121-127` (byte-identical mirror) and
`:115-119` (pure ASCII) are the pinning tests for this task. If code and test disagree, the tests win.

- [ ] **Step 4: Commit**

```bash
git add clavity-classic/plugin/hooks/agy-consult-guard-post.sh
git commit -m "fix(hooks): mirror the consult-guard attribution caveat to classic"
```

---

## Task 4: Reconcile ROADMAP §12

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md` (§12 begins at the heading `### 12. Post-plan-2 leftovers`)

- [ ] **Step 1: Mark both sub-items shipped**

Update the §12 heading and both sub-headings to record that they shipped, with the commit SHAs and the
pinning test names. **Keep the measurements that justified each** — they are the provenance.

For 12b, keep the note that the two emission paths are not byte-identical on this platform and that this is
deliberate and harmless, so a future reader does not re-open it.

- [ ] **Step 2: Grep the whole repo for the fact you changed**

🔴 **The dominant defect in this repo is an incomplete fold, and §12b's own first draft was one.** Use the
Grep tool, not bash `grep` (on this machine bash `rg` is GNU grep 3.0 and a bracketed literal silently
misfires). Check for any claim that the consult guard can attribute changes to the peer, or that the
`UserPromptSubmit` arm is untested. Check `docs/` and both `CHANGELOG.md` files.

**`clavity-classic/ROADMAP.md` points at dotnet §0 by design — do not "restore parity" by copying any body
across.**

- [ ] **Step 3: Commit**

```bash
git add clavity-dotnet/ROADMAP.md
git commit -m "docs(roadmap): record §12a and §12b as shipped"
```

---

## Completion gate

- [ ] Run the fast suite: `just test-scripts-fast`. ⚠ **cap-adjacent** — never alongside the slow half.
- [ ] Run the slow suite **backgrounded**, blocking on its own `Tests completed` line, never a process
      count. **A log with no `Tests Passed:` line is an ABORTED run, not a pass.**
- [ ] Confirm no `justfile` registration change was needed. This plan adds **no new file** — verify with
      `git diff --name-status <base>..HEAD` showing only `M` entries, rather than assuming it.
- [ ] **AGY-CAPSTONE** on the committed range, per the standing rule. The marker records the **reviewed**
      tip, never ambient HEAD.

**The heavy cycle applies here in full — owner ruling 2026-08-07, made after seeing the measurement that
eight panel rounds found none of the previous epic's nine defects. Do not shorten it during execution.**

---

## Self-review

**Spec coverage.** §12a → Tasks 2 and 3 (message + mirror). §12b → Task 1 (the coverage gap). Both ROADMAP
sub-items are reconciled in Task 4. Nothing in §12 is unaddressed.

**Placeholder scan.** No TBD, no "add appropriate error handling", no "similar to Task N". Every code step
carries the literal text to insert.

**Type/name consistency.** `New-GateEnv`, `New-Workspace`, `$script:NoJqPath`, `$script:Hook`,
`New-GuardRepo`, `Payload`, `$script:Pre`, `$script:Post`, `$script:Classic` are all read-verified as
existing in the two suites today. `Invoke-BashHook -Arguments` exists as of `6138b3b`.

**Known intermediate red.** Task 2 Step 5 leaves the mirror test failing until Task 3 lands. This is stated
in the plan rather than left for the implementer to discover and mistake for a defect.

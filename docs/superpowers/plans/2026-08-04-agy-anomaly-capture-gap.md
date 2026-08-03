# AGY-ANOMALIES capture-gap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the AGY-ANOMALIES discipline a capture push — a `PreCompact` reminder for direct-driver work and a `PreToolUse` reminder for subagent dispatches — without regressing the `SessionStart` hooks that already ship.

**Architecture:** Two new, isolated bash hooks mirrored byte-identically into both driver plugins, registered in each plugin's `hooks.json`. The existing `SessionStart` matcher object is **split in two** so the drain reminder can widen its matcher without dragging the liveness check (and classic's driver-state reset) along with it. No existing hook script is modified.

**Tech Stack:** Bash (Git Bash on Windows), `jq`, Claude Code plugin `hooks.json`, Pester 5 via `scripts/tests/BashHookHelpers.ps1`, `just` recipes.

**Source spec:** `docs/superpowers/specs/2026-08-04-agy-anomaly-capture-gap-design.md` — panel-GREEN at round 6. Do not re-review it; implement it.

---

## The four traps this change can ship broken through

Read these before Task 1. Each one fails **silently** — the hook looks installed and working.

1. **Plain stdout is discarded.** Measured by a three-arm sentinel: plain text on stdout at `exit 0`
   reaches the model **not at all**; at `exit 2` only stderr survives. The delivery channel is the JSON
   envelope. A hook written with a bare `printf "$msg"` produces no error and no output.
2. **The envelope is event-specific.** `hookSpecificOutput` is **invalid for `PreCompact`** — Claude Code
   rejects the payload and the owner sees a schema dump. `PreCompact` uses top-level `systemMessage`.
   Precedent, already in this repo: `agy-autotrain/hooks/agy-learn-reminder.sh:37-40`.
3. **`exit 2` is non-blocking on `SessionStart` but BLOCKING on `PreToolUse`** (documented verbatim at
   `clavity-dotnet/plugin/hooks/agy-liveness-check.sh:8`). A non-zero exit from the new dispatch hook
   **blocks every subagent dispatch**. It must fail open on every path.
4. **The `SessionStart` change is a structural split, not a string edit.** That block is a *single matcher
   object holding several hooks* — verified now: 2 in dotnet (`hooks.json:37-45`), 3 in classic
   (`hooks.json:37-47`). Editing its `matcher` string widens it for all of them.

Plus one rule on the emitted text: **no backtick, no apostrophe, no double quote, no backslash.** The
first two are bash quoting hazards; the last two would break the hand-built JSON envelope on the
`jq`-absent path. All four are asserted at byte level.

---

## Verified starting state

Every citation below was read from the working tree on 2026-08-04 before this plan was written.

| fact | evidence |
|---|---|
| dotnet `SessionStart` is ONE matcher object, `"startup"`, holding `agy-liveness-check.sh` + `agy-anomaly-reminder.sh` | `clavity-dotnet/plugin/hooks/hooks.json:37-45` |
| classic `SessionStart` is ONE matcher object, `"startup"`, holding `agy-drive-session-reset.sh` + `agy-liveness-check.sh` + `agy-anomaly-reminder.sh` | `clavity-classic/plugin/hooks/hooks.json:37-47` |
| Neither plugin registers `PreCompact` today | both `hooks.json` — `PreToolUse`, `PostToolUse`, `SessionStart` only |
| No hook in either plugin matches the `Agent`/`Task` tool | both `hooks.json:3-16` |
| `PreCompact` + `manual\|auto`, and two `SessionStart` matcher objects, are production shapes | `agy-autotrain/hooks/hooks.json:7-16` |
| the per-event envelope split is already implemented and commented | `agy-autotrain/hooks/agy-learn-reminder.sh:32-40` |
| `agy-anomaly-reminder.sh` reads only `.cwd`; it never reads `.source` | `clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh:34` |
| the seed-sync gate compares `PostToolUse`, `PreToolUse` and a filtered `SessionStart` — **and no other event** | `scripts/check-seed-artifacts-synced.sh:83-127` |
| that gate discovers `plugin/hooks/*` by walk, so a new `.sh` is byte-compared with no enrolment | `scripts/check-seed-artifacts-synced.sh:63-77` |
| `plugin-hooks-payload.Tests.ps1` globs both hook dirs, so new hooks get ASCII + parity cover free | `scripts/tests/plugin-hooks-payload.Tests.ps1:24-60` |
| shipped `.sh` are LF-only and enforced by gitattributes | `.gitattributes` `*.sh text eol=lf`; measured `agy-anomaly-reminder.sh` = 99 LF / 0 CR |
| the installers ship `plugin/` by recursive wildcard — **no `.iss` edit is needed** | no `.iss` under `installer/` references `plugin/hooks` |
| the `jq`-absent test idiom is `PATH = <Git>\usr\bin` (has grep/awk, no jq) | `scripts/tests/agy-seam-inject.Tests.ps1:11-12` |
| no existing test asserts the real `hooks.json` matcher structure, so the split breaks nothing | grep of `agy-anomaly-reminder.Tests.ps1` + `agy-liveness-check.Tests.ps1` |
| both directive texts measure 0 backticks / 0 apostrophes / 0 non-ASCII | measured 2026-08-04: capture 576 chars, dispatch 543 chars |

---

## File structure

| file | responsibility |
|---|---|
| `clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh` | **new.** `PreCompact`, model-addressed. Emits `{"systemMessage": …}` at exit 0. |
| `clavity-classic/plugin/hooks/agy-anomaly-capture-reminder.sh` | **new.** Byte-identical mirror. |
| `clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh` | **new.** `PreToolUse:Agent\|Task`, model-addressed. Emits `hookSpecificOutput` at exit 0, fails open everywhere. |
| `clavity-classic/plugin/hooks/agy-anomaly-dispatch-reminder.sh` | **new.** Byte-identical mirror. |
| `clavity-dotnet/plugin/hooks/hooks.json` | **modify.** Add `PreCompact`; add `PreToolUse:Agent\|Task`; split `SessionStart` in two. |
| `clavity-classic/plugin/hooks/hooks.json` | **modify.** Same, keeping `agy-drive-session-reset.sh` on `startup`. |
| `scripts/tests/agy-anomaly-capture-reminder.Tests.ps1` | **new suite.** Behaviour of the capture hook. |
| `scripts/tests/agy-anomaly-dispatch-reminder.Tests.ps1` | **new suite.** Behaviour of the dispatch hook, incl. the fail-open matrix. |
| `scripts/tests/plugin-hooks-registration.Tests.ps1` | **new suite.** `hooks.json` *registration structure* in both drivers — a distinct responsibility from `plugin-hooks-payload.Tests.ps1`, which guards the `.sh` bytes. |
| `scripts/check-seed-artifacts-synced.sh` | **modify.** Compare `PreCompact`, and compare the event key SET. |
| `scripts/tests/check-seed-artifacts-synced.Tests.ps1` | **modify.** Two tests for the two new gate rules. |
| `justfile:94` | **modify.** Register the three new suites in `test-scripts-fast`. |
| `scripts/tests/_partition.md` | **modify.** Re-measure both halves by running each recipe. |

**Why a third suite.** The spec's manifest names two. Testing items 5 and 6 assert `hooks.json` structure,
which belongs to neither hook's behaviour suite; `plugin-hooks-registration.Tests.ps1` is their home. This
is a plan-level decomposition choice, not a spec deviation.

**Ordering constraint — do not reorder Tasks 1–3.** Creating a hook in one driver only makes
`plugin-hooks-payload.Tests.ps1` and `check-seed-artifacts-synced.sh` go red, so each hook is created in
**both** drivers inside the same task. And until Task 5 edits the `justfile`, the new suites are not in
either half — run them directly by path, as each task's steps specify.

---

## Task 1: the `PreCompact` capture hook, both drivers

**Files:**
- Create: `clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh`
- Create: `clavity-classic/plugin/hooks/agy-anomaly-capture-reminder.sh`
- Test: `scripts/tests/agy-anomaly-capture-reminder.Tests.ps1`

- [ ] **Step 1: Write the failing test suite**

Create `scripts/tests/agy-anomaly-capture-reminder.Tests.ps1` with exactly this content:

```powershell
# Behaviour of the AGY-ANOMALIES capture-side reminder (PreCompact, model-addressed).
#
# THE FAILURE MODE THIS SUITE EXISTS FOR IS SILENT. A three-arm sentinel measured that plain stdout at
# exit 0 reaches the model NOT AT ALL, and that stdout at exit 2 is dropped too (only stderr survives).
# So a hook written with a bare printf of the text produces no error, no output, and looks installed and
# working. Every assertion here therefore parses the JSON and inspects a KEY - never a substring of the
# raw stdout, which would pass on a payload the runtime rejects.
#
# hookSpecificOutput is INVALID for PreCompact (Claude Code rejects it and the owner sees a schema dump),
# so the absence assertion below is as load-bearing as the presence one.

Describe 'agy-anomaly-capture-reminder.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh'

        # ...\Git\usr\bin carries grep/awk but NOT jq, so pointing PATH here reproduces "jq absent"
        # deterministically. Git Bash itself is invoked by ABSOLUTE path inside Invoke-BashHook.
        $bashDir = Split-Path -Parent (Get-GitBashOrThrow)
        $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')

        # An empty HOME so a REAL ~/.claude/.no-agy on the dev box cannot silence the hook and hand us a
        # false green. Absolute paths only - MSYS mangles a relative HOME.
        function New-CleanHome {
            $h = Join-Path ([IO.Path]::GetTempPath()) ("anom-cap-home-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $h '.claude') -Force | Out-Null
            return $h
        }
        function New-Workspace {
            $w = Join-Path ([IO.Path]::GetTempPath()) ("anom-cap-ws-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $w -Force | Out-Null
            return $w
        }
        function Payload { param([string]$Cwd) @{ cwd = ($Cwd -replace '\\','/'); trigger = 'manual' } | ConvertTo-Json -Compress }

        # The message VERBATIM. Asserted WHOLE via [regex]::Escape, never by bookend fragments: a prior
        # epic measured that bookend assertions left ~95% of a 399-character clause unguarded, and an
        # audit mutant that deleted the operative sentence from all four hooks left a 45-test suite GREEN.
        $script:CaptureMsg = 'AGY-ANOMALIES check BEFORE COMPACTION: did you VERIFY a defect this session that is OUTSIDE your current task and is not yet in .clavity/local-anomalies.md? Capture it now via the open-issues skill - one line: - [type] fact * path:LINE * DATE * task=<what you were doing>. Uncaptured anomalies are lost at compaction. NOT an anomaly: a test you expected to fail, an error in the work you are actively doing, or anything you have not verified by measurement. If nothing qualifies, do nothing - a speculative entry is worse than none, because it lands on a blocking triage gate.'
    }

    It 'emits a top-level systemMessage and NOT hookSpecificOutput' {
        $w = New-Workspace; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $j = $r.StdOut | ConvertFrom-Json
            $j.systemMessage      | Should -Not -BeNullOrEmpty
            $j.PSObject.Properties.Name | Should -Not -Contain 'hookSpecificOutput' -Because 'hookSpecificOutput is invalid for PreCompact and the runtime rejects the whole payload'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'delivers the capture directive WHOLE' {
        $w = New-Workspace; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            ($r.StdOut | ConvertFrom-Json).systemMessage | Should -Match ([regex]::Escape($script:CaptureMsg))
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'states the verification bar and the in-scope exclusion' {
        # agy named the failure mode this wording prevents - "Pre-Compaction False-Capture Rush": under
        # context pressure the model logs IN-FLIGHT, IN-SCOPE work as an anomaly without meeting the bar.
        # These two clauses are the mitigation, pinned separately so a future reword cannot drop them
        # while still matching some other part of the message.
        $w = New-Workspace; $h = New-CleanHome
        try {
            $m = (Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }).StdOut | ConvertFrom-Json
            $m.systemMessage | Should -Match ([regex]::Escape('anything you have not verified by measurement'))
            $m.systemMessage | Should -Match ([regex]::Escape('an error in the work you are actively doing'))
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'still DELIVERS the JSON envelope when jq is absent' {
        # Exit 0 alone is NOT the requirement. A hook that exits 0 and emits nothing is the exact
        # invisible zero this whole change exists to remove, and it would pass an exit-code-only test.
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{"cwd":"."}' -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $r.ExitCode | Should -Be 0
            $j = $r.StdOut | ConvertFrom-Json   # throws if the fallback emitted plain text
            $j.systemMessage | Should -Match ([regex]::Escape($script:CaptureMsg))
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'delivers an IDENTICAL message with and without jq' {
        # The anti-drift guard. The two emission paths are separate code; without this, one can be
        # reworded and the other left behind, and each path passes its own test.
        $w = New-Workspace; $h = New-CleanHome
        try {
            $withJq = ((Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }).StdOut | ConvertFrom-Json).systemMessage
            $noJq   = ((Invoke-BashHook -HookPath $script:Hook -Payload '{"cwd":"."}' -Env @{ PATH = $script:NoJqPath; HOME = $h }).StdOut | ConvertFrom-Json).systemMessage
            $noJq | Should -BeExactly $withJq
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a WORKSPACE .no-agy' {
        $w = New-Workspace; $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $w '.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a GLOBAL .no-agy' {
        $w = New-Workspace; $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a GLOBAL .no-agy even when jq is absent' {
        # Without this the kill-switch is honoured only on the jq path, and a machine with no jq gets an
        # unsuppressable nudge forever - the same defect agy-anomaly-reminder.sh:22-25 records fixing.
        $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{"cwd":"."}' -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 0 and still delivers on a malformed payload' {
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload 'not json at all {{{' -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            ($r.StdOut | ConvertFrom-Json).systemMessage | Should -Not -BeNullOrEmpty
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'emits a message free of backtick, apostrophe, double quote and backslash' {
        # Scan the EMITTED text, not the script source: the source may legitimately carry all four in
        # comments, so a whole-file scan would be both wrong and permanently red.
        # Backtick and apostrophe are bash quoting hazards (a backtick in a double-quoted string is
        # command substitution). Double quote and backslash would break the hand-built JSON envelope on
        # the jq-absent path, which has no escaping machinery.
        $w = New-Workspace; $h = New-CleanHome
        try {
            $m = ((Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }).StdOut | ConvertFrom-Json).systemMessage
            $bytes = [Text.Encoding]::UTF8.GetBytes($m)
            @($bytes | Where-Object { $_ -eq 0x60 }).Count | Should -Be 0 -Because 'backtick'
            @($bytes | Where-Object { $_ -eq 0x27 }).Count | Should -Be 0 -Because 'apostrophe'
            @($bytes | Where-Object { $_ -eq 0x22 }).Count | Should -Be 0 -Because 'double quote'
            @($bytes | Where-Object { $_ -eq 0x5C }).Count | Should -Be 0 -Because 'backslash'
            @($bytes | Where-Object { $_ -gt 127 }).Count  | Should -Be 0 -Because 'non-ASCII'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-anomaly-capture-reminder.Tests.ps1 -Output Detailed -CI"`
Expected: every test FAILS. The hook file does not exist, so Git Bash reports
`No such file or directory` and `ConvertFrom-Json` gets empty input.

- [ ] **Step 3: Write the hook**

Create `clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh`:

```bash
#!/usr/bin/env bash
# AGY-ANOMALIES capture reminder (plugin-shipped). PreCompact(manual|auto): the CAPTURE side of the
# discipline, addressed to the MODEL. Its sibling agy-anomaly-reminder.sh is the DRAIN side, addressed to
# the OWNER at SessionStart. Before this hook, the discipline had a drain push and no capture push: a
# driver working DIRECTLY -- not dispatching -- that noticed a defect got nothing from any hook at any
# moment, because the capture contract lived only inside a skill it had to decide to pull unprompted, at
# exactly the moment its attention is elsewhere by construction.
#
# EMISSION = the JSON ENVELOPE on stdout at exit 0, and the envelope is EVENT-SPECIFIC.
# MEASURED by a three-arm sentinel: plain stdout at exit 0 reaches the model NOT AT ALL (silently
# discarded), and stdout at exit 2 is dropped too -- only stderr survives there. So a hook written with a
# bare printf of the text produces no error, no output, and looks installed and working.
# hookSpecificOutput is INVALID for PreCompact: Claude Code rejects the payload outright and the owner
# sees a schema-validation dump instead of the reminder. PreCompact must use top-level systemMessage.
# The same split is documented and implemented at agy-autotrain/hooks/agy-learn-reminder.sh:32-40.
#
# THE MESSAGE CARRIES NO BACKTICK, APOSTROPHE, DOUBLE QUOTE OR BACKSLASH. The first two are bash quoting
# hazards (a backtick inside a double-quoted string is command substitution; an apostrophe terminates a
# single-quoted one), and the last two would break the hand-built JSON envelope on the jq-absent path
# below, which has no escaping machinery. All four are asserted at BYTE level against the EMITTED text by
# scripts/tests/agy-anomaly-capture-reminder.Tests.ps1. Markdown decoration buys nothing inside a prompt
# string, so it is removed rather than escaped.
#
# Fail-open: any error -> exit 0. Suppressed by .no-agy (workspace or global) like every other reminder.
# Byte-identical across both driver plugins (kept honest by scripts/check-seed-artifacts-synced.sh).
set +e
input=$(cat)

# ONE definition, used by BOTH emission paths, so the jq-absent fallback can never drift from the
# jq-present one. A test asserts the two paths deliver a byte-identical string.
msg='AGY-ANOMALIES check BEFORE COMPACTION: did you VERIFY a defect this session that is OUTSIDE your current task and is not yet in .clavity/local-anomalies.md? Capture it now via the open-issues skill - one line: - [type] fact * path:LINE * DATE * task=<what you were doing>. Uncaptured anomalies are lost at compaction. NOT an anomaly: a test you expected to fail, an error in the work you are actively doing, or anything you have not verified by measurement. If nothing qualifies, do nothing - a speculative entry is worse than none, because it lands on a blocking triage gate.'

# jq is needed only to read cwd out of the payload. Without it, STILL DELIVER: emit the same message in a
# hand-built envelope rather than exiting silently. A silent exit here is precisely the invisible zero
# this hook exists to remove -- and it is invisible in both directions, because an absent nudge and a
# nudge with nothing to say look identical from outside. Honor the kill-switch FIRST, against the process
# cwd, since the payload cannot be parsed without jq (agy-anomaly-reminder.sh:22-25 records the defect
# this ordering prevents: a machine that simply has no jq otherwise gets an unsuppressable nudge forever).
if ! command -v jq >/dev/null 2>&1; then
  if [ -f "./.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then exit 0; fi
  printf '{"systemMessage":"%s"}\n' "$msg"
  exit 0
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)
[ -z "$cwd" ] && cwd="."

if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  exit 0
fi

jq -nc --arg m "$msg" '{systemMessage:$m}'
exit 0
```

- [ ] **Step 4: Verify the file is LF-only and pure ASCII**

Run:
```bash
f=clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh
printf 'CR=%s nonascii=%s\n' "$(tr -cd '\r' < $f | wc -c)" "$(LC_ALL=C tr -d '\000-\177' < $f | wc -c)"
```
Expected: `CR=0 nonascii=0`. `.gitattributes` declares `*.sh text eol=lf`; a CR in a shebang breaks the
hook on Linux/macOS and Git Bash. If `CR` is non-zero, rewrite the file with LF endings — do not commit it.

- [ ] **Step 5: Mirror to classic in the same task**

A hook that exists in one driver only turns `plugin-hooks-payload.Tests.ps1` red and trips
`check-seed-artifacts-synced.sh`. Copy, then prove byte-identity:

```bash
cp clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh \
   clavity-classic/plugin/hooks/agy-anomaly-capture-reminder.sh
cmp clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh \
    clavity-classic/plugin/hooks/agy-anomaly-capture-reminder.sh && echo IDENTICAL
```
Expected: `IDENTICAL`.

- [ ] **Step 6: Run the suite to verify it passes**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-anomaly-capture-reminder.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 10, Failed: 0`.

- [ ] **Step 7: Prove the byte-scan assertion is non-vacuous**

A scan for characters that are already absent passes by construction. Mutate, confirm the mutation
landed, watch it go red, revert.

```bash
# Replace the hyphen in "one line: -" with an apostrophe, using the '"'"' idiom.
sed -i "s/one line: - \[type\]/one line'"'"' [type]/" clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh
grep -c "one line'" clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh
```
Expected: `1` — **the mutation is proven to have landed.** If it prints `0`, the `sed` did not apply and
the RED below would prove nothing; fix the mutation before continuing.

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-anomaly-capture-reminder.Tests.ps1 -Output Detailed -CI"`
Expected: the apostrophe test FAILS (`Because apostrophe`).

Revert and re-verify:
```bash
git checkout -- clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh
```
Then re-run the suite. Expected: `Tests Passed: 10, Failed: 0`.

Note: the hook is untracked until Step 8, so `git checkout --` cannot restore it. Take a copy first:
```bash
cp clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh /tmp/cap-hook.bak   # BEFORE the sed
cp /tmp/cap-hook.bak clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh   # to revert
```

- [ ] **Step 8: Commit**

```bash
git add scripts/tests/agy-anomaly-capture-reminder.Tests.ps1 \
        clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh \
        clavity-classic/plugin/hooks/agy-anomaly-capture-reminder.sh
git commit -m "feat(hooks): add the AGY-ANOMALIES PreCompact capture reminder"
```

---

## Task 2: the `PreToolUse` dispatch hook, both drivers

**Files:**
- Create: `clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh`
- Create: `clavity-classic/plugin/hooks/agy-anomaly-dispatch-reminder.sh`
- Test: `scripts/tests/agy-anomaly-dispatch-reminder.Tests.ps1`

**Highest blast radius in the change.** `exit 2` is BLOCKING on `PreToolUse` — a non-zero exit here halts
every subagent dispatch. Both shipping `PreToolUse` hooks fail open with zero non-zero paths; this one
must too.

- [ ] **Step 1: Write the failing test suite**

Create `scripts/tests/agy-anomaly-dispatch-reminder.Tests.ps1` with exactly this content:

```powershell
# Behaviour of the AGY-ANOMALIES dispatch-side reminder (PreToolUse: Agent|Task, model-addressed).
#
# WHY THIS HOOK EXISTS. agy-seam-inject.sh carries the ANOMALY-CAPTURE directive, but it is registered
# PreToolUse matcher "Skill" and keys on .tool_input.skill, and NO hook in either plugin matches the
# Agent/Task tool. Skill invocation is a ONE-SHOT event, so
#   invoke subagent-driven-development -> /compact -> dispatch four subagents
# fires that directive ZERO times across exactly the work it governs.
#
# THE FAIL-OPEN MATRIX IS THE POINT. exit 2 is non-blocking on SessionStart but BLOCKING on PreToolUse
# (documented verbatim at agy-liveness-check.sh:8), so a bug here does not degrade a notification - it
# halts every subagent dispatch in the session.

Describe 'agy-anomaly-dispatch-reminder.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh'

        $bashDir = Split-Path -Parent (Get-GitBashOrThrow)
        $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')

        function New-CleanHome {
            $h = Join-Path ([IO.Path]::GetTempPath()) ("anom-disp-home-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $h '.claude') -Force | Out-Null
            return $h
        }
        function New-Workspace {
            $w = Join-Path ([IO.Path]::GetTempPath()) ("anom-disp-ws-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $w -Force | Out-Null
            return $w
        }
        function Payload { param([string]$Cwd, [string]$Tool = 'Agent')
            @{ cwd = ($Cwd -replace '\\','/'); tool_name = $Tool } | ConvertTo-Json -Compress
        }

        # The directive VERBATIM, asserted WHOLE. Bookend assertions leave the middle unguarded, which is
        # where the operative content lives - measured on a prior epic at ~95% of the clause.
        $script:DispatchMsg = 'AGY-ANOMALIES relay, both halves. (1) In the dispatch you are about to write, ask the subagent to report anything wrong it notices that is NOT its task, under a heading Anomalies noticed at the end of its final message, stated as a checkable fact, with an explicit none if it saw nothing. (2) When it returns, VERIFY each claimed anomaly by measurement and APPEND the verified ones to .clavity/local-anomalies.md BEFORE you write your summary. A verified anomaly that exists only in a chat message is lost the moment you compress that message.'

        function Get-Ctx { param($Result) ($Result.StdOut | ConvertFrom-Json).hookSpecificOutput.additionalContext }
    }

    It 'emits hookSpecificOutput with hookEventName PreToolUse' {
        $w = New-Workspace; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $j = $r.StdOut | ConvertFrom-Json
            $j.hookSpecificOutput.hookEventName | Should -BeExactly 'PreToolUse'
            $j.PSObject.Properties.Name | Should -Not -Contain 'systemMessage'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'delivers the dispatch directive WHOLE' {
        $w = New-Workspace; $h = New-CleanHome
        try {
            Get-Ctx (Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }) |
                Should -Match ([regex]::Escape($script:DispatchMsg))
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'carries BOTH halves - instruct-the-subagent AND verify-on-return' {
        # An earlier draft carried only the return-side relay, which is compliance theater: nothing would
        # have instructed the subagent to produce the heading the driver is then told to look for, so the
        # driver checks, finds nothing, and correctly concludes "no anomalies" - from a question that was
        # never asked. Pinned separately from the whole-string assertion so the failure NAMES which half.
        $w = New-Workspace; $h = New-CleanHome
        try {
            $ctx = Get-Ctx (Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h })
            $ctx | Should -Match ([regex]::Escape('ask the subagent to report anything wrong it notices that is NOT its task'))
            $ctx | Should -Match ([regex]::Escape('VERIFY each claimed anomaly by measurement and APPEND the verified ones'))
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'carries NO FILES allow-list and no implementer-dispatch obligation' {
        # This hook fires on EVERY Agent dispatch, including read-only reviewers and auditors. The FILES
        # allow-list and the diff-the-change-set obligation belong to an IMPLEMENTER dispatch only; the
        # anomaly clause and the FILES clause are separable, and only the latter is excluded here.
        # NEGATIVE assertion - passes on a clean baseline by construction. Its non-vacuity is proven by a
        # landed mutation, recorded in the plan for this task.
        $w = New-Workspace; $h = New-CleanHome
        try {
            $ctx = Get-Ctx (Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h })
            $ctx | Should -Not -Match 'FILES'
            $ctx | Should -Not -Match 'git status --short'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 0 on every failure mode' -ForEach @(
        @{ Case = 'malformed payload';  Payload = 'not json at all {{{';        NoJq = $false }
        @{ Case = 'empty payload';      Payload = '';                            NoJq = $false }
        @{ Case = 'absent cwd key';     Payload = '{"tool_name":"Agent"}';       NoJq = $false }
        @{ Case = 'unreadable cwd';     Payload = '{"cwd":"/no/such/dir/at/all"}'; NoJq = $false }
        @{ Case = 'non-Agent payload';  Payload = '{"cwd":".","tool_name":"Bash"}'; NoJq = $false }
        @{ Case = 'absent jq';          Payload = '{"cwd":"."}';                 NoJq = $true  }
    ) {
        # exit 2 is BLOCKING on PreToolUse. There must be NO path that exits non-zero, because a bug here
        # does not degrade a notification - it halts every subagent dispatch in the session.
        $h = New-CleanHome
        try {
            $env = @{ HOME = $h }
            if ($NoJq) { $env['PATH'] = $script:NoJqPath }
            $r = Invoke-BashHook -HookPath $script:Hook -Payload $Payload -Env $env
            $r.ExitCode | Should -Be 0 -Because "the $Case path must fail open"
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'has no non-zero exit anywhere in its source' {
        # A structural companion to the matrix above: the matrix can only cover the paths it thought of.
        # Both shipping PreToolUse hooks have zero non-zero exit paths; this asserts the same property
        # directly rather than by sampling.
        $src = Get-Content -Raw -LiteralPath $script:Hook
        [regex]::Matches($src, '(?m)^\s*exit\s+[1-9]').Count | Should -Be 0
    }

    It 'still DELIVERS the JSON envelope when jq is absent' {
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{"cwd":"."}' -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $r.ExitCode | Should -Be 0
            $j = $r.StdOut | ConvertFrom-Json   # throws if the fallback emitted plain text
            $j.hookSpecificOutput.hookEventName | Should -BeExactly 'PreToolUse'
            $j.hookSpecificOutput.additionalContext | Should -Match ([regex]::Escape($script:DispatchMsg))
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'delivers an IDENTICAL directive with and without jq' {
        $w = New-Workspace; $h = New-CleanHome
        try {
            $withJq = Get-Ctx (Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h })
            $noJq   = Get-Ctx (Invoke-BashHook -HookPath $script:Hook -Payload '{"cwd":"."}' -Env @{ PATH = $script:NoJqPath; HOME = $h })
            $noJq | Should -BeExactly $withJq
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a WORKSPACE .no-agy' {
        $w = New-Workspace; $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $w '.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a GLOBAL .no-agy' {
        $w = New-Workspace; $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a GLOBAL .no-agy even when jq is absent' {
        $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{"cwd":"."}' -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'emits a directive free of backtick, apostrophe, double quote and backslash' {
        $w = New-Workspace; $h = New-CleanHome
        try {
            $ctx = Get-Ctx (Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h })
            $bytes = [Text.Encoding]::UTF8.GetBytes($ctx)
            @($bytes | Where-Object { $_ -eq 0x60 }).Count | Should -Be 0 -Because 'backtick'
            @($bytes | Where-Object { $_ -eq 0x27 }).Count | Should -Be 0 -Because 'apostrophe'
            @($bytes | Where-Object { $_ -eq 0x22 }).Count | Should -Be 0 -Because 'double quote'
            @($bytes | Where-Object { $_ -eq 0x5C }).Count | Should -Be 0 -Because 'backslash'
            @($bytes | Where-Object { $_ -gt 127 }).Count  | Should -Be 0 -Because 'non-ASCII'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'leaves agy-seam-inject.sh untouched' {
        # Acceptance criterion 10. Gap (b) is closed by an ISOLATED hook; modifying the seam injector was
        # explicitly rejected, because its case keys on $skill, which an Agent payload does not carry.
        $seam = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-seam-inject.sh'
        (Get-Content -Raw -LiteralPath $seam) | Should -Match ([regex]::Escape(".tool_input.skill // """""))
    }
}
```

> The last test's escaped literal is `.tool_input.skill // ""` as it appears at
> `agy-seam-inject.sh:42`. If the quoting proves awkward in PowerShell, assert
> `Should -Match 'tool_input\.skill'` instead — the point is that the extraction is still keyed on
> `skill`, not that the whole line is byte-frozen.

- [ ] **Step 2: Run the suite to verify it fails**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-anomaly-dispatch-reminder.Tests.ps1 -Output Detailed -CI"`
Expected: every test except `leaves agy-seam-inject.sh untouched` FAILS — the hook does not exist.

- [ ] **Step 3: Write the hook**

Create `clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh`:

```bash
#!/usr/bin/env bash
# AGY-ANOMALIES dispatch reminder (plugin-shipped). PreToolUse(Agent|Task): carry the anomaly-relay
# obligation into every subagent dispatch. ISOLATED BY DESIGN -- agy-seam-inject.sh is not modified and
# not sourced. That hook is registered matcher "Skill" and keys its case on .tool_input.skill, which an
# Agent payload does not carry, so extending it would mean payload branching AND would push its
# implementer-only FILES clause at read-only reviewer subagents.
#
# THE GAP THIS CLOSES. Skill invocation is a ONE-SHOT event. Invoking subagent-driven-development, then
# compacting, then dispatching four subagents fires the seam injector's ANOMALY-CAPTURE arm ZERO times
# across exactly the work it governs. An earlier negotiation established BY MEASUREMENT that anomalies
# die at RELAY, not at noticing -- the driver compresses a subagent report into a summary -- so a
# PreCompact nudge is structurally too late for this loss: by compaction the report is already a
# two-line summary.
#
# FAIL OPEN ON EVERY PATH, AND THAT IS NOT A STYLE PREFERENCE. exit 2 is non-blocking for SessionStart
# but BLOCKING for PreToolUse (documented verbatim at agy-liveness-check.sh:8), so a non-zero exit here
# does not degrade a notification -- it HALTS EVERY SUBAGENT DISPATCH in the session. Both shipping
# PreToolUse hooks have zero non-zero exit paths; this one matches them. A test asserts that no
# `exit <non-zero>` appears anywhere in this file.
#
# EMISSION = the JSON ENVELOPE at exit 0. MEASURED: plain stdout at exit 0 is SILENTLY DISCARDED, so a
# bare printf of the text produces no error, no output, and looks installed and working. PreToolUse takes
# hookSpecificOutput{hookEventName:"PreToolUse"} (precedent: agy-seam-inject.sh:71).
#
# THE DIRECTIVE CARRIES NO BACKTICK, APOSTROPHE, DOUBLE QUOTE OR BACKSLASH -- the first two are bash
# quoting hazards, the last two would break the hand-built envelope on the jq-absent path. Asserted at
# byte level against the EMITTED text.
#
# NO TOOL-NAME GUARD: the matcher is the gate. Adding one would introduce a jq-absent branch that cannot
# determine the tool name and would have to emit anyway, buying nothing.
#
# Suppressed by .no-agy (workspace or global). Byte-identical across both driver plugins.
set +e
input=$(cat)

# ONE definition, used by BOTH emission paths, so the jq-absent fallback can never drift. Both halves of
# the obligation are present deliberately: an earlier draft carried only the return-side relay, which is
# compliance theater -- nothing instructed the subagent to produce the heading the driver is then told to
# look for, so the driver checks, finds nothing, and correctly concludes "no anomalies" from a question
# that was never asked.
msg='AGY-ANOMALIES relay, both halves. (1) In the dispatch you are about to write, ask the subagent to report anything wrong it notices that is NOT its task, under a heading Anomalies noticed at the end of its final message, stated as a checkable fact, with an explicit none if it saw nothing. (2) When it returns, VERIFY each claimed anomaly by measurement and APPEND the verified ones to .clavity/local-anomalies.md BEFORE you write your summary. A verified anomaly that exists only in a chat message is lost the moment you compress that message.'

# jq is needed only to read cwd. Without it, STILL DELIVER the envelope rather than exiting silently: a
# silent exit is indistinguishable from a hook that is installed and has nothing to say. Kill-switch
# first, against the process cwd, since the payload cannot be parsed without jq.
if ! command -v jq >/dev/null 2>&1; then
  if [ -f "./.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then exit 0; fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$msg"
  exit 0
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)
[ -z "$cwd" ] && cwd="."

if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  exit 0
fi

jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
exit 0
```

- [ ] **Step 4: Verify LF-only and pure ASCII**

Run:
```bash
f=clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh
printf 'CR=%s nonascii=%s\n' "$(tr -cd '\r' < $f | wc -c)" "$(LC_ALL=C tr -d '\000-\177' < $f | wc -c)"
```
Expected: `CR=0 nonascii=0`.

- [ ] **Step 5: Mirror to classic**

```bash
cp clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh \
   clavity-classic/plugin/hooks/agy-anomaly-dispatch-reminder.sh
cmp clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh \
    clavity-classic/plugin/hooks/agy-anomaly-dispatch-reminder.sh && echo IDENTICAL
```
Expected: `IDENTICAL`.

- [ ] **Step 6: Run the suite to verify it passes**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-anomaly-dispatch-reminder.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 18, Failed: 0` (the `-ForEach` block expands to 6).

- [ ] **Step 7: Prove the two negative assertions are non-vacuous**

**7a — the no-FILES-clause assertion.** Back up, mutate, confirm it landed, watch RED, restore:

```bash
cp clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh /tmp/disp-hook.bak
sed -i 's/AGY-ANOMALIES relay, both halves\./AGY-ANOMALIES relay, both halves. Name a FILES allow-list./' \
    clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh
grep -c 'FILES allow-list' clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh
```
Expected: `1` — **mutation proven landed.** If `0`, fix it before reading anything into the RED.

Run the suite. Expected: `carries NO FILES allow-list` FAILS.

Restore: `cp /tmp/disp-hook.bak clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh`

**7b — the no-non-zero-exit assertion.** Same protocol:

```bash
printf '\n# probe\nif [ -n "$CLAVITY_NEVER_SET" ]; then exit 3; fi\n' \
    >> clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh
grep -cE '^\s*exit\s+[1-9]' clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh
```
Expected: `1` — mutation proven landed. Note the probe is written so the mutated hook still behaves
correctly at runtime; only the source-level assertion should fail, which is exactly what it claims to guard.

Run the suite. Expected: `has no non-zero exit anywhere in its source` FAILS.

Restore: `cp /tmp/disp-hook.bak clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh`
Re-run the suite. Expected: `Tests Passed: 18, Failed: 0`.

- [ ] **Step 8: Re-mirror and commit**

The mutations touched the dotnet copy only; re-copy so the pair is identical again.

```bash
cp clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh \
   clavity-classic/plugin/hooks/agy-anomaly-dispatch-reminder.sh
cmp clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh \
    clavity-classic/plugin/hooks/agy-anomaly-dispatch-reminder.sh && echo IDENTICAL
git add scripts/tests/agy-anomaly-dispatch-reminder.Tests.ps1 \
        clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh \
        clavity-classic/plugin/hooks/agy-anomaly-dispatch-reminder.sh
git commit -m "feat(hooks): add the AGY-ANOMALIES dispatch reminder on PreToolUse Agent|Task"
```

---

## Task 3: register both hooks and split `SessionStart`

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/hooks.json:3-45`
- Modify: `clavity-classic/plugin/hooks/hooks.json:3-47`
- Test: `scripts/tests/plugin-hooks-registration.Tests.ps1`

- [ ] **Step 1: Write the failing test suite**

Create `scripts/tests/plugin-hooks-registration.Tests.ps1` with exactly this content:

```powershell
# REGISTRATION structure of the shipped hooks.json in both drivers.
#
# Distinct responsibility from plugin-hooks-payload.Tests.ps1, which guards the .sh BYTES (ASCII, parity).
# This file guards WHICH hook is registered under WHICH matcher - a property no .sh test can see.
#
# EVERY ASSERTION WALKS THE PARSED JSON AND CHECKS A HOOK'S OWNING MATCHER OBJECT. A substring search
# over the raw file cannot tell which hook a matcher governs, which is exactly the distinction the
# SessionStart split exists to create.

Describe 'shipped plugin hook registration' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Manifests = @{
            dotnet  = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/hooks.json'
            classic = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks/hooks.json'
        }

        # Return the matcher values of every object under $Event whose hooks array mentions $Script.
        # A hook registered twice yields two values, which the callers assert on explicitly.
        function Get-OwningMatchers { param([string]$Manifest, [string]$Event, [string]$Script)
            $json = Get-Content -Raw -LiteralPath $Manifest | ConvertFrom-Json
            @(foreach ($group in @($json.hooks.$Event)) {
                if (@($group.hooks) | Where-Object { $_.command -like "*$Script*" }) { $group.matcher }
            })
        }
        function Get-AllCommands { param([string]$Manifest)
            $json = Get-Content -Raw -LiteralPath $Manifest | ConvertFrom-Json
            @(foreach ($event in $json.hooks.PSObject.Properties) {
                foreach ($group in @($event.Value)) { foreach ($h in @($group.hooks)) { $h.command } }
            })
        }
    }

    It 'registers agy-anomaly-reminder.sh in its OWN SessionStart object on startup|resume|clear|compact - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        $m = $script:Manifests[$Driver]
        $matchers = Get-OwningMatchers -Manifest $m -Event 'SessionStart' -Script 'agy-anomaly-reminder.sh'
        $matchers.Count | Should -Be 1
        $matchers[0]    | Should -BeExactly 'startup|resume|clear|compact'
    }

    It 'keeps agy-liveness-check.sh on startup ALONE - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        # THE REGRESSION THE STRUCTURAL SPLIT EXISTS TO PREVENT. SessionStart was ONE matcher object
        # holding several hooks, so naively widening its matcher string would also widen the liveness
        # check - which is documented as "the ONE boot-time liveness surface" and exits 2 with loud
        # advisories, so it would spam the transcript on every /compact mid-task.
        # NEGATIVE assertion: it passes on a clean baseline by construction. Its non-vacuity is proven by
        # a merge-the-objects mutation recorded in the plan for this task.
        $m = $script:Manifests[$Driver]
        $matchers = Get-OwningMatchers -Manifest $m -Event 'SessionStart' -Script 'agy-liveness-check.sh'
        $matchers.Count | Should -Be 1
        $matchers[0]    | Should -BeExactly 'startup'
    }

    It 'keeps classic-only agy-drive-session-reset.sh on startup ALONE' {
        # Re-firing a DRIVER-STATE RESET on every compaction is a behaviour change, not a notification
        # change - a strictly worse outcome than the liveness spam above.
        $matchers = Get-OwningMatchers -Manifest $script:Manifests['classic'] -Event 'SessionStart' -Script 'agy-drive-session-reset.sh'
        $matchers.Count | Should -Be 1
        $matchers[0]    | Should -BeExactly 'startup'
    }

    It 'does NOT register agy-drive-session-reset.sh under dotnet at all' {
        # It is classic-only. The seed-sync gate filters it out of its SessionStart comparison, so if
        # dotnet ever registered it the filter would strip it there too and report GREEN.
        (Get-AllCommands $script:Manifests['dotnet']) -join ' ' | Should -Not -Match 'agy-drive-session-reset'
    }

    It 'registers the capture reminder on PreCompact manual|auto - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        $matchers = Get-OwningMatchers -Manifest $script:Manifests[$Driver] -Event 'PreCompact' -Script 'agy-anomaly-capture-reminder.sh'
        $matchers.Count | Should -Be 1
        $matchers[0]    | Should -BeExactly 'manual|auto'
    }

    It 'registers the dispatch reminder on PreToolUse Agent|Task - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        # Agent|Task, not Agent. The observed tool name in this runtime is Agent, but binding to one
        # literal makes the hook a silent no-op if a dispatch arrives under the other, and the existing
        # matchers are already alternations, so it costs nothing.
        $matchers = Get-OwningMatchers -Manifest $script:Manifests[$Driver] -Event 'PreToolUse' -Script 'agy-anomaly-dispatch-reminder.sh'
        $matchers.Count | Should -Be 1
        $matchers[0]    | Should -BeExactly 'Agent|Task'
    }

    It 'leaves agy-seam-inject.sh on PreToolUse Skill - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        $matchers = Get-OwningMatchers -Manifest $script:Manifests[$Driver] -Event 'PreToolUse' -Script 'agy-seam-inject.sh'
        $matchers.Count | Should -Be 1
        $matchers[0]    | Should -BeExactly 'Skill'
    }

    It 'names only hook files that EXIST in that plugin - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        # A typo in a command path registers a hook that can never fire, and a hook that never fires
        # cannot report its own absence.
        $m = $script:Manifests[$Driver]
        $dir = Split-Path -Parent $m
        $cmds = Get-AllCommands $m
        $cmds.Count | Should -BeGreaterThan 0 -Because 'an empty command set would pass the loop below vacuously'
        $missing = foreach ($c in $cmds) {
            if ($c -match 'hooks/([A-Za-z0-9._-]+\.sh)') {
                $f = Join-Path $dir $Matches[1]
                if (-not (Test-Path -LiteralPath $f)) { $Matches[1] }
            }
        }
        ($missing -join '; ') | Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `pwsh -c "Invoke-Pester scripts/tests/plugin-hooks-registration.Tests.ps1 -Output Detailed -CI"`
Expected: FAIL on the anomaly-reminder matcher (it is `startup`, not the widened value), on both
`PreCompact` tests (no such event), and on both `PreToolUse Agent|Task` tests. The liveness,
drive-session-reset, seam-inject and file-existence tests already PASS.

- [ ] **Step 3: Rewrite `clavity-dotnet/plugin/hooks/hooks.json`**

Replace the whole file with:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Skill",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-seam-inject.sh\"" }
        ]
      },
      {
        "matcher": "Agent|Task",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-anomaly-dispatch-reminder.sh\"" }
        ]
      },
      {
        "matcher": "Bash|PowerShell|mcp__.*agy_ask",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-consult-guard-pre.sh\"" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-after-reminder.sh\"" }
        ]
      },
      {
        "matcher": "Bash|Write|Edit",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-test-audit-reminder.sh\"" }
        ]
      },
      {
        "matcher": "Bash|PowerShell|mcp__.*agy_ask",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-consult-guard-post.sh\"" }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-liveness-check.sh\"" }
        ]
      },
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-anomaly-reminder.sh\"" }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "manual|auto",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-anomaly-capture-reminder.sh\"" }
        ]
      }
    ]
  }
}
```

- [ ] **Step 4: Rewrite `clavity-classic/plugin/hooks/hooks.json`**

Identical, except that `agy-drive-session-reset.sh` stays first in the `startup` object — the one
legitimate difference between the two manifests:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Skill",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-seam-inject.sh\"" }
        ]
      },
      {
        "matcher": "Agent|Task",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-anomaly-dispatch-reminder.sh\"" }
        ]
      },
      {
        "matcher": "Bash|PowerShell|mcp__.*agy_ask",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-consult-guard-pre.sh\"" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-after-reminder.sh\"" }
        ]
      },
      {
        "matcher": "Bash|Write|Edit",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-test-audit-reminder.sh\"" }
        ]
      },
      {
        "matcher": "Bash|PowerShell|mcp__.*agy_ask",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-consult-guard-post.sh\"" }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-drive-session-reset.sh\"" },
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-liveness-check.sh\"" }
        ]
      },
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-anomaly-reminder.sh\"" }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "manual|auto",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-anomaly-capture-reminder.sh\"" }
        ]
      }
    ]
  }
}
```

- [ ] **Step 5: Run the suite to verify it passes**

Run: `pwsh -c "Invoke-Pester scripts/tests/plugin-hooks-registration.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 14, Failed: 0`.

- [ ] **Step 6: Verify the existing seed-sync gate is still green**

The gate compares `PreToolUse` byte-for-byte across drivers and compares `SessionStart` with
`agy-drive-session-reset.sh` filtered out. After the split, dotnet's `startup` object holds `[liveness]`
and classic's filters down to `[liveness]`, so both sides must match.

Run: `just seed-sync-check`
Expected: exit 0, output contains `in sync`.

If it reports `SessionStart (shared hooks) differs`, the two manifests' matcher values or group order
diverged — diff them and align, do not weaken the gate.

- [ ] **Step 7: Prove the liveness-stays-on-startup assertion is non-vacuous**

The merge-the-objects mutation, on dotnet:

```bash
cp clavity-dotnet/plugin/hooks/hooks.json /tmp/dotnet-hooks.bak
python -c "
import json
p='clavity-dotnet/plugin/hooks/hooks.json'
d=json.load(open(p))
ss=d['hooks']['SessionStart']
merged=[{'matcher':'startup|resume|clear|compact','hooks':ss[0]['hooks']+ss[1]['hooks']}]
d['hooks']['SessionStart']=merged
json.dump(d,open(p,'w'),indent=2)
"
python -c "
import json
d=json.load(open('clavity-dotnet/plugin/hooks/hooks.json'))
ss=d['hooks']['SessionStart']
print('groups=%d hooks_in_first=%d matcher=%s' % (len(ss), len(ss[0]['hooks']), ss[0]['matcher']))
"
```
Expected: `groups=1 hooks_in_first=2 matcher=startup|resume|clear|compact` — **the mutation is proven to
have landed.** Anything else means it did not apply, and the RED below would prove nothing.

Run: `pwsh -c "Invoke-Pester scripts/tests/plugin-hooks-registration.Tests.ps1 -Output Detailed -CI"`
Expected: `keeps agy-liveness-check.sh on startup ALONE - dotnet` FAILS with
`Expected 'startup', but got 'startup|resume|clear|compact'`.

**This is the whole point of the split.** Confirm also that the *positive* test still passes under the
mutation — that is what proves item 5 alone could not have caught the naive edit.

Restore and re-verify:
```bash
cp /tmp/dotnet-hooks.bak clavity-dotnet/plugin/hooks/hooks.json
pwsh -c "Invoke-Pester scripts/tests/plugin-hooks-registration.Tests.ps1 -Output Detailed -CI"
```
Expected: `Tests Passed: 14, Failed: 0`.

- [ ] **Step 8: Commit**

```bash
git add clavity-dotnet/plugin/hooks/hooks.json \
        clavity-classic/plugin/hooks/hooks.json \
        scripts/tests/plugin-hooks-registration.Tests.ps1
git commit -m "feat(hooks): register the anomaly capture and dispatch reminders; split SessionStart"
```

---

## Task 4: close the seed-sync gate's event blind spot

**Files:**
- Modify: `scripts/check-seed-artifacts-synced.sh:79-136`
- Test: `scripts/tests/check-seed-artifacts-synced.Tests.ps1`

**Why this task exists, and it is not in the spec.** `compared_elsewhere()` waives `hooks.json` from the
byte-diff and delegates its content to per-event `jq` rules — and those rules are an **allow-list of
three events**: `PostToolUse` (`:83-87`), `PreToolUse` (`:91-95`), `SessionStart` (`:122-127`). Task 3
adds a fourth event that **no rule compares**. `PreCompact` could drift, or vanish from one driver
entirely, with `just seed-sync-check` reporting GREEN. That is the same fail-open shape this script's own
comments record fixing twice before (`:103-116`), so the fix closes the class as well as the instance.

- [ ] **Step 1: Write the failing tests**

Append these two `It` blocks inside the existing `Describe 'check-seed-artifacts-synced.sh'` in
`scripts/tests/check-seed-artifacts-synced.Tests.ps1`, immediately before its closing brace:

```powershell
    It 'FIRES when the PreCompact block differs between the two plugins' {
        # The per-event jq rules are an ALLOW-LIST of events. Before this rule existed, PreCompact was
        # compared by nothing at all: compared_elsewhere() waives hooks.json from the byte-diff and
        # delegates its content to those rules, so an event without a rule is silently unchecked.
        $f = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks/hooks.json'
        $orig = Get-Content -Raw -LiteralPath $f
        try {
            $j = $orig | ConvertFrom-Json
            $j.hooks.PreCompact[0].matcher = 'manual'
            $j | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $f -Encoding ascii
            $r = Invoke-SeedSync
            $r.ExitCode | Should -Not -Be 0
            "$($r.StdOut)`n$($r.StdErr)" | Should -Match 'PreCompact'
        } finally { Set-Content -LiteralPath $f -Value $orig -NoNewline }
    }

    It 'FIRES when one plugin registers an EVENT the other does not' {
        # The CLASS fix, not just the PreCompact instance: a future event added to one manifest and not
        # the other would be invisible to every per-event rule. Uses an event name no rule names, so this
        # can only pass via the key-set comparison.
        $f = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks/hooks.json'
        $orig = Get-Content -Raw -LiteralPath $f
        try {
            $j = $orig | ConvertFrom-Json
            $j.hooks | Add-Member -NotePropertyName 'Notification' -NotePropertyValue @(
                @{ matcher = '*'; hooks = @(@{ type = 'command'; command = 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/agy-liveness-check.sh"' }) }
            )
            $j | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $f -Encoding ascii
            $r = Invoke-SeedSync
            $r.ExitCode | Should -Not -Be 0
            "$($r.StdOut)`n$($r.StdErr)" | Should -Match 'different EVENT names'
        } finally { Set-Content -LiteralPath $f -Value $orig -NoNewline }
    }
```

- [ ] **Step 2: Run the suite to verify both fail**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-seed-artifacts-synced.Tests.ps1 -Output Detailed -CI"`
Expected: the two new tests FAIL — the gate exits 0 because nothing compares `PreCompact` or the key set.
The seven pre-existing tests still pass.

- [ ] **Step 3: Add the two rules**

In `scripts/check-seed-artifacts-synced.sh`, insert immediately after the `SessionStart` comparison block
that ends at `:127` (the `fi` following `SEED-DRIFT: hooks/hooks.json SessionStart (shared hooks) differs`):

```bash
# PreCompact registers the SHARED capture-side anomaly reminder and must be byte-identical across both
# plugins. It is compared here because the per-event rules above are an ALLOW-LIST of events, and
# compared_elsewhere() waives hooks.json from the byte-diff on the strength of exactly these rules -- so
# an event with no rule is not "compared loosely", it is not compared AT ALL. Measured before this block
# existed: deleting the entire PreCompact array from one manifest left the gate GREEN.
if ! diff -q <(jq -S '.hooks.PreCompact' "$D/hooks/hooks.json") \
             <(jq -S '.hooks.PreCompact' "$C/hooks/hooks.json") >/dev/null 2>&1; then
  echo "SEED-DRIFT: hooks/hooks.json PreCompact (shared anomaly capture reminder) differs between the two plugins" >&2
  status=1
fi
# THE CLASS FIX, and it is the reason the block above is not enough on its own. Enumerating events one
# rule at a time is the same allow-list shape this file already replaced twice (see the deny-list note
# above): the NEXT event someone registers will have no rule either, and its absence will look exactly
# like synchronisation. Comparing the event KEY SET makes a one-sided event fail loudly the moment it is
# added -- fail-closed, which is the posture this gate wants.
if ! diff -q <(jq -S '.hooks | keys' "$D/hooks/hooks.json") \
             <(jq -S '.hooks | keys' "$C/hooks/hooks.json") >/dev/null 2>&1; then
  echo "SEED-DRIFT: hooks/hooks.json registers different EVENT names in the two plugins" >&2
  status=1
fi
```

- [ ] **Step 4: Run the suite to verify it passes**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-seed-artifacts-synced.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 9, Failed: 0`.

- [ ] **Step 5: Verify the gate is green on the real repo**

Run: `just seed-sync-check`
Expected: exit 0, `in sync`.

- [ ] **Step 6: Commit**

```bash
git add scripts/check-seed-artifacts-synced.sh scripts/tests/check-seed-artifacts-synced.Tests.ps1
git commit -m "fix(seed-sync): compare PreCompact and the hooks.json event key set across drivers"
```

---

## Task 5: register the new suites and re-measure the partition

**Files:**
- Modify: `justfile:94`
- Modify: `scripts/tests/_partition.md`

All three new suites go in **`test-scripts-fast`**, and the half is not a free choice: `test-scripts-slow`
last measured **653,5s against a 600s foreground cap** — it is already over. The fast half was 124,6s and
already hosts the comparable lightweight hook suites.

- [ ] **Step 1: Verify the partition oracle currently names the three orphans**

Run:
```bash
diff <(ls scripts/tests/*.Tests.ps1 | xargs -n1 basename | sort) \
     <(grep -oE "scripts/tests/[A-Za-z0-9._-]+\.Tests\.ps1" justfile | xargs -n1 basename | sort -u)
```
Expected: three `<` lines naming `agy-anomaly-capture-reminder.Tests.ps1`,
`agy-anomaly-dispatch-reminder.Tests.ps1` and `plugin-hooks-registration.Tests.ps1`. This is the RED for
this task.

- [ ] **Step 2: Add the three suites to `test-scripts-fast`**

In `justfile:94`, replace this fragment:

```
'scripts/tests/check-growth-budget.Tests.ps1', 'scripts/tests/plugin-hooks-payload.Tests.ps1') -Output Detailed -CI"
```

with:

```
'scripts/tests/check-growth-budget.Tests.ps1', 'scripts/tests/plugin-hooks-payload.Tests.ps1', 'scripts/tests/plugin-hooks-registration.Tests.ps1', 'scripts/tests/agy-anomaly-capture-reminder.Tests.ps1', 'scripts/tests/agy-anomaly-dispatch-reminder.Tests.ps1') -Output Detailed -CI"
```

- [ ] **Step 3: Re-run the oracle to verify it is clean**

Run the same `diff` as Step 1.
Expected: no output, exit 0.

- [ ] **Step 4: Count the suites by running the counter, never by adding one**

`_partition.md` records that its own suite counts decayed silently for longer than its test counts did,
because someone **incremented the printed number instead of counting the recipe** and every later editor
incremented the already-wrong figure in turn.

Run:
```bash
for r in fast slow; do
  printf '%s %s\n' "$r" "$(sed -n "/^test-scripts-$r:/,/^$/p" justfile \
    | grep -oE 'scripts/tests/[A-Za-z0-9._-]+\.Tests\.ps1' | sort -u | wc -l)"
done
```
Record both printed numbers verbatim.

- [ ] **Step 5: Measure the fast half by running the recipe**

Run: `just test-scripts-fast`
Expected: `Tests Passed: <N>, Failed: 0`. Record N and the wall time exactly as printed (this repo writes
times with a comma decimal separator, e.g. `124,6s`).

- [ ] **Step 6: Measure the slow half — BACKGROUNDED**

It exceeded the 600s foreground cap on its last run. Run `just test-scripts-slow` in the background and
block on its own `Tests completed` line — **never on a process count**.

Record the passed count and wall time as printed. Adding to the fast half changes the slow half's
reported figure only by decay, but `_partition.md` forbids computing either.

- [ ] **Step 7: Update `_partition.md` with the measured numbers only**

Update the two bullets at `_partition.md:21-28` with the suite counts from Step 4, the test counts and
times from Steps 5 and 6, and the date. Add one sentence recording what changed — three suites added to
the fast half — in the style of the existing re-measurement log at `:62-76`.

Add three rows to the `## Measured runtimes` table (`:104-134`) for the new suites, each marked
`<- FAST, added 2026-08-04`, using per-file numbers from the Detailed output of Step 5.

**Do not compute any number by subtraction, and do not increment a printed figure.** Every number written
here comes from the output of a command you just ran.

- [ ] **Step 8: Commit**

```bash
git add justfile scripts/tests/_partition.md
git commit -m "test: register the three new hook suites in test-scripts-fast and re-measure both halves"
```

---

## Task 6 (OPTIONAL — owner decides before starting): dual-channel the `SessionStart` notice

**Files:**
- Create: `clavity-dotnet/plugin/hooks/agy-anomaly-model-notice.sh`
- Create: `clavity-classic/plugin/hooks/agy-anomaly-model-notice.sh`
- Modify: both `hooks.json` — a **second command inside the `startup|resume|clear|compact` object**
- Test: `scripts/tests/agy-anomaly-model-notice.Tests.ps1`

**The decision.** Spec design item 4 is explicitly optional and appears in **no acceptance criterion**.
The gap is real: `agy-anomaly-reminder.sh` emits on stderr at `exit 2`, which reaches the **owner** and
not the model, so a session can begin with pending anomalies that the agent doing the work never learns
about. The two channels cannot come from one invocation — one hook emits the JSON envelope at `exit 0`
for the model, the other stderr at `exit 2` for the owner — so it is a second hook or nothing.

**My recommendation: build it.** It is the only remaining path by which the model, who does the triage,
finds out there is triage to do. But it is genuinely severable: Tasks 1–5 satisfy every acceptance
criterion without it. **Ask the owner before starting this task.**

It goes as a second command inside the `startup|resume|clear|compact` object, alongside
`agy-anomaly-reminder.sh` — it must fire on exactly the occasions the drain notice does, and that is what
sharing the object guarantees. It must **not** go in the `startup` object, which acceptance criterion 6
reserves for the untouched liveness and reset hooks.

- [ ] **Step 1: Write the failing test suite**

Create `scripts/tests/agy-anomaly-model-notice.Tests.ps1`:

```powershell
# The MODEL-addressed half of the SessionStart anomaly notice.
#
# WHY A SECOND HOOK RATHER THAN A SECOND printf. The two channels cannot come from one invocation: the
# owner-addressed notice is stderr at exit 2, and stdout on an exit-2 hook is DISCARDED (measured). A
# matcher object's hooks array may hold several commands and exit status is PER-HOOK, so the two live
# side by side under the same matcher and fire on exactly the same occasions.

Describe 'agy-anomaly-model-notice.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-anomaly-model-notice.sh'
        $bashDir = Split-Path -Parent (Get-GitBashOrThrow)
        $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')

        function New-CleanHome {
            $h = Join-Path ([IO.Path]::GetTempPath()) ("anom-mn-home-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $h '.claude') -Force | Out-Null
            return $h
        }
        # A git worktree, because the hook resolves the repo toplevel exactly as agy-anomaly-reminder.sh
        # does (:41-45) so both sides always agree on where the anomalies file lives.
        function New-RepoWith { param([string]$Anomalies)
            $r = New-TempRepo
            if ($null -ne $Anomalies) {
                New-Item -ItemType Directory -Path (Join-Path $r '.clavity') -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $r '.clavity/local-anomalies.md') -Value $Anomalies
            }
            return $r
        }
        function Payload { param([string]$Cwd) @{ cwd = ($Cwd -replace '\\','/'); source = 'startup' } | ConvertTo-Json -Compress }
    }

    It 'is SILENT when there are no untriaged anomalies' {
        $r = New-RepoWith $null; $h = New-CleanHome
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            $x.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'emits hookSpecificOutput naming the COUNT when entries are pending' {
        $r = New-RepoWith "- [defect] a thing * a.ts:1 * 2026-08-01 * task=x`n- [defect] another * b.ts:2 * 2026-08-02 * task=y`n"
        $h = New-CleanHome
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            $j = $x.StdOut | ConvertFrom-Json
            $j.hookSpecificOutput.hookEventName   | Should -BeExactly 'SessionStart'
            $j.hookSpecificOutput.additionalContext | Should -Match '2 untriaged'
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 0 even with entries pending, so the owner-side hook is unaffected' {
        # Its sibling exits 2 by design. This one must not, or a SessionStart carrying pending anomalies
        # would surface two blocking advisories where the design intends one notice per audience.
        $r = New-RepoWith "- [defect] a thing * a.ts:1 * 2026-08-01 * task=x`n"
        $h = New-CleanHome
        try {
            (Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r) -Env @{ HOME = $h }).ExitCode | Should -Be 0
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a GLOBAL .no-agy' {
        $r = New-RepoWith "- [defect] a thing * a.ts:1 * 2026-08-01 * task=x`n"
        $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            $x.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 0 when jq is absent' {
        $h = New-CleanHome
        try {
            (Invoke-BashHook -HookPath $script:Hook -Payload '{"cwd":"."}' -Env @{ PATH = $script:NoJqPath; HOME = $h }).ExitCode | Should -Be 0
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-anomaly-model-notice.Tests.ps1 -Output Detailed -CI"`
Expected: all five FAIL — the hook does not exist.

- [ ] **Step 3: Write the hook**

Create `clavity-dotnet/plugin/hooks/agy-anomaly-model-notice.sh`:

```bash
#!/usr/bin/env bash
# AGY-ANOMALIES SessionStart notice, MODEL half. Its sibling agy-anomaly-reminder.sh is the OWNER half:
# stderr at exit 2, because at SessionStart there is no user turn and stdout is absorbed into the model
# context where the owner never sees it. That same property is why the OWNER half cannot also serve the
# model -- stdout on an exit-2 hook is DISCARDED (measured). Two channels, two hooks, one matcher object:
# a matcher object's hooks array may hold several commands and exit status is PER-HOOK, so both fire on
# exactly the same occasions.
#
# The MODEL is the one who does the triage, so it has to learn the work exists. Counting logic mirrors
# agy-anomaly-reminder.sh deliberately, including its root resolution (:41-45) and its bracketed-bullet
# entry pattern (:58-70), so the two halves can never disagree about what is pending.
#
# Fail-open: any error -> exit 0. Suppressed by .no-agy (workspace or global).
set +e
input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)
[ -z "$cwd" ] && cwd="."

if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  exit 0
fi

root=$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
[ -n "$root" ] || root="$cwd"
f="$root/.clavity/local-anomalies.md"
[ -f "$f" ] || f="$cwd/.clavity/local-anomalies.md"
[ -f "$f" ] || exit 0

n=$(grep -c '^- \[[^]]*\]' "$f" 2>/dev/null)
rc=$?
# Unreadable is not "none", but this half must stay silent about it: the OWNER half already reports that
# case on stderr, and duplicating it here would put the same advisory on two channels.
if [ "$rc" -gt 1 ]; then exit 0; fi
[ -z "$n" ] && n=0
[ "$n" -eq 0 ] && exit 0

msg="AGY-ANOMALIES: $n untriaged in $f. Triage before new work via the open-issues skill: each entry is either PROMOTED to a tracked item with an owner, or DELETEd with a recorded reason. There is no parked state."
jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
exit 0
```

- [ ] **Step 4: Verify LF-only and pure ASCII, then mirror**

```bash
f=clavity-dotnet/plugin/hooks/agy-anomaly-model-notice.sh
printf 'CR=%s nonascii=%s\n' "$(tr -cd '\r' < $f | wc -c)" "$(LC_ALL=C tr -d '\000-\177' < $f | wc -c)"
cp $f clavity-classic/plugin/hooks/agy-anomaly-model-notice.sh
cmp $f clavity-classic/plugin/hooks/agy-anomaly-model-notice.sh && echo IDENTICAL
```
Expected: `CR=0 nonascii=0` then `IDENTICAL`.

- [ ] **Step 5: Register it in both manifests**

In **both** `hooks.json` files, add a second command to the `startup|resume|clear|compact` object so it
reads:

```json
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-anomaly-reminder.sh\"" },
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-anomaly-model-notice.sh\"" }
        ]
      }
```

- [ ] **Step 6: Add a registration assertion**

Append inside `Describe 'shipped plugin hook registration'` in
`scripts/tests/plugin-hooks-registration.Tests.ps1`:

```powershell
    It 'registers the model notice in the SAME SessionStart object as the drain reminder - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        # Sharing the object is what guarantees the two halves fire on exactly the same occasions. It must
        # NOT land in the startup object, which acceptance criterion 6 reserves for the untouched
        # liveness and reset hooks.
        $m = $script:Manifests[$Driver]
        $notice = Get-OwningMatchers -Manifest $m -Event 'SessionStart' -Script 'agy-anomaly-model-notice.sh'
        $drain  = Get-OwningMatchers -Manifest $m -Event 'SessionStart' -Script 'agy-anomaly-reminder.sh'
        $notice.Count | Should -Be 1
        $notice[0]    | Should -BeExactly $drain[0]
        $notice[0]    | Should -BeExactly 'startup|resume|clear|compact'
    }
```

- [ ] **Step 7: Run both suites and the gate**

Run:
```
pwsh -c "Invoke-Pester scripts/tests/agy-anomaly-model-notice.Tests.ps1 -Output Detailed -CI"
pwsh -c "Invoke-Pester scripts/tests/plugin-hooks-registration.Tests.ps1 -Output Detailed -CI"
just seed-sync-check
```
Expected: `Tests Passed: 5, Failed: 0`; `Tests Passed: 16, Failed: 0`; `in sync`.

- [ ] **Step 8: Register the suite, re-measure, commit**

Add `'scripts/tests/agy-anomaly-model-notice.Tests.ps1'` to `test-scripts-fast` in `justfile:94`, re-run
the partition oracle and the suite counter from Task 5 Steps 3–4, re-measure **both** halves by running
each recipe (slow backgrounded), and update `_partition.md` with the measured figures only.

```bash
git add clavity-dotnet/plugin/hooks/agy-anomaly-model-notice.sh \
        clavity-classic/plugin/hooks/agy-anomaly-model-notice.sh \
        clavity-dotnet/plugin/hooks/hooks.json \
        clavity-classic/plugin/hooks/hooks.json \
        scripts/tests/agy-anomaly-model-notice.Tests.ps1 \
        scripts/tests/plugin-hooks-registration.Tests.ps1 \
        justfile scripts/tests/_partition.md
git commit -m "feat(hooks): dual-channel the SessionStart anomaly notice for the model"
```

---

## Final verification (after the last task)

- [ ] **Whole fast half green**

Run: `just test-scripts-fast`
Expected: `Failed: 0`.

- [ ] **Whole slow half green — backgrounded**

Run `just test-scripts-slow` in the background; block on its `Tests completed` line.
Expected: `Failed: 0`.

- [ ] **Cross-driver gates green**

Run: `just seed-sync-check`
Expected: `in sync`.

- [ ] **Acceptance criterion 10 — `agy-seam-inject.sh` is byte-identical to its pre-change state**

Run:
```bash
git diff --stat <base-sha> -- clavity-dotnet/plugin/hooks/agy-seam-inject.sh \
                              clavity-classic/plugin/hooks/agy-seam-inject.sh
```
where `<base-sha>` is HEAD before Task 1. Expected: **no output**.

- [ ] **Acceptance criterion 5 — `agy-anomaly-reminder.sh`'s script body is unchanged**

Run the same `git diff --stat` for both copies of `agy-anomaly-reminder.sh`. Expected: no output. Only its
*registration* changed.

- [ ] **Live smoke of the `PreCompact` hook**

The suites drive the hook directly; they cannot prove the runtime accepts the envelope. Trigger a
`/compact` and confirm the capture reminder appears as a system message. If a schema-validation dump
appears instead, the envelope shape is wrong for the event — see trap 2.

- [ ] **Live smoke of the dispatch hook**

Dispatch any subagent and confirm the relay directive arrives, and — more importantly — that the dispatch
**is not blocked**. A blocked dispatch means a non-zero exit path survived; see trap 3.

---

## Acceptance-criteria coverage map

| # | criterion | where it is satisfied |
|---|---|---|
| 1 | both hooks in both drivers, byte-identical | Task 1 Step 5, Task 2 Step 5 (`cmp`); standing cover by `plugin-hooks-payload.Tests.ps1` |
| 2 | `PreCompact` emits `systemMessage`, not `hookSpecificOutput` | Task 1 Step 1, test *emits a top-level systemMessage and NOT hookSpecificOutput* |
| 3 | dispatch hook emits `hookSpecificOutput`, exits 0 always, no FILES clause | Task 2 Step 1, tests 1, the 6-case `-ForEach` matrix, *has no non-zero exit anywhere*, *carries NO FILES allow-list* |
| 4 | capture text carries the verification bar and in-scope exclusion, asserted whole | Task 1 Step 1, tests *delivers the capture directive WHOLE* + *states the verification bar* |
| 5 | drain reminder in its own object on `startup\|resume\|clear\|compact`; body unchanged | Task 3 Step 1 test 1; Final verification, criterion-5 `git diff --stat` |
| 6 | liveness (and classic's reset) remain on `startup` alone | Task 3 Step 1 tests 2–3, non-vacuity proven at Task 3 Step 7 |
| 7 | neither emitted text carries a backtick or apostrophe, at byte level | Task 1 Step 1 + Task 2 Step 1 byte-scan tests; non-vacuity at Task 1 Step 7 |
| 8 | dispatch directive carries both halves, no FILES allow-list, asserted whole | Task 2 Step 1, tests *delivers the dispatch directive WHOLE*, *carries BOTH halves*, *carries NO FILES allow-list*; non-vacuity at Task 2 Step 7a |
| 9 | both hooks emit the JSON envelope on the `jq`-absent path | Task 1 + Task 2, tests *still DELIVERS the JSON envelope when jq is absent* and *delivers an IDENTICAL message with and without jq* |
| 10 | `agy-seam-inject.sh` byte-identical to its pre-change state | Task 2 Step 1 test *leaves agy-seam-inject.sh untouched*; Final verification `git diff --stat` |
| 11 | all shipped hooks pure ASCII, zero CR, every mirrored pair identical | Task 1 Step 4, Task 2 Step 4; standing cover by `plugin-hooks-payload.Tests.ps1` |
| 12 | both `_partition.md` counts re-measured by running each recipe | Task 5 Steps 4–7 |
| 13 | new assertions proven non-vacuous by a landed mutation; negatives carry a control | Task 1 Step 7, Task 2 Step 7a/7b, Task 3 Step 7 — each confirms the mutation landed *before* reading the RED |

---

## Self-review

**1. Spec coverage.** All 13 acceptance criteria map to a task (table above). All 8 Testing items are
covered: items 1/2/2b/3/4/7 by the two hook suites, items 5/6 by `plugin-hooks-registration.Tests.ps1`.
Design items 1, 2 and 3 are Tasks 1, 3 and 2; design item 4 is Task 6, flagged optional as the spec does.
The file manifest is covered, with **two additions the spec does not list**, both flagged in-document:
`plugin-hooks-registration.Tests.ps1` (a home for Testing items 5–6) and the `check-seed-artifacts-synced`
change (Task 4).

**2. Placeholder scan.** No TBD, no "handle edge cases", no "similar to Task N". Every code step carries
complete content; every command carries its expected output.

**3. Type consistency.** Hook filenames are identical everywhere they appear
(`agy-anomaly-capture-reminder.sh`, `agy-anomaly-dispatch-reminder.sh`, `agy-anomaly-model-notice.sh`).
Matcher strings are identical between the `hooks.json` bodies and the assertions that check them
(`startup`, `startup|resume|clear|compact`, `manual|auto`, `Agent|Task`, `Skill`). The two helper
functions in the registration suite (`Get-OwningMatchers`, `Get-AllCommands`) are defined once and used
under those names throughout, including in Task 6's appended test.

**Gaps found and closed while writing this plan:**

- **The seed-sync gate had no `PreCompact` rule** and no rule for any future event — a `PreCompact` block
  could vanish from one driver with `just seed-sync-check` GREEN. Closed as Task 4, including the class
  fix (event key-set comparison), not just the instance.
- **Task ordering would have gone red mid-task** if a hook were created in one driver before the other;
  `plugin-hooks-payload.Tests.ps1` and the seed-sync walk both fire on a one-sided file. Each hook is
  therefore created in both drivers inside one task, and the constraint is stated explicitly.
- **The mutation steps needed a "did it land?" check.** A `sed` that silently fails produces a green run
  that reads as "the mutation was caught". Every mutation step now prints a count and states what it must
  be before the RED means anything.
- **The new hooks are untracked when the mutation steps run**, so `git checkout --` cannot restore them.
  Each mutation step takes a copy first.

**Gaps left open, with where they resolve:**

- **Whether to build Task 6** is the owner's call, per the spec's own framing. My recommendation is in the
  task header. It resolves before Task 6 starts, not in this document.
- **Runtime acceptance of both envelopes** cannot be proven by the suites, which drive the hooks directly.
  It resolves in the two live smoke checks in Final verification — the only place trap 1 and trap 2 are
  actually testable.

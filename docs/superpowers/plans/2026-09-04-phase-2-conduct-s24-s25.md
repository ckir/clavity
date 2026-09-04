# Phase 2 — AGY conduct: §24 mandatory consult + §25 negotiation discipline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the AGY-FIRST design consult mechanically unavoidable when a capstone round has to write new code, and give the two review-only skills that lack one a bounded negotiation protocol.

**Architecture:** §24 ships a read-only PowerShell checker that answers "did this range introduce new code?" from `git diff` alone, plus a `stamp` subcommand on the existing marker writer that records whether the consult and the review ran in the same agy cascade. The capstone skill consumes both. §25 lifts `agy-first`'s existing `AGY-NEGOTIATE` wording into `agy-test-audit` and `adversarial-panel-review`, and extends the existing skill linter so the new section is pinned mechanically rather than by prose.

**Tech Stack:** PowerShell 7 (`pwsh`) + Pester 6 for gates and tests; bash for the shipped hooks; markdown for the shipped skills.

---

## Context an implementer needs before Task 1

**Read these first.** This plan edits shipped plugin payload, and this repository has specific rules about that.

- **Every skill and hook under `plugin/` ships as a BYTE-IDENTICAL PAIR.** `clavity-dotnet/plugin/...` and `clavity-classic/plugin/...` must be identical, and `scripts/check-seed-artifacts-synced.sh` fails the build if they are not. **Verified 2026-09-04: all four discipline SKILL.md files are currently byte-identical (476/234/393/380 lines).** Any change to one half lands in the other half **in the same commit**.
- **Before editing ANY `SKILL.md`, load the `writing-skills` skill.** This is a standing owner instruction in this repository.
- **Stage explicit paths.** Never `git add -A` in this repo — it has previously swept `.claude/settings.local.json` onto a public remote. Every commit step below lists its paths.
- **Never commit anything under `.clavity/`.** It is gitignored runtime state.
- **Do not push.** The owner owns every push.
- **A read-only checker is exempt** from this repo's "every new `.ps1` supports `-WhatIf`" rule. `check-capstone-new-code.ps1` is read-only.

**The owner's ruling that shapes §24 (2026-09-04):** *record isolation, do not gate on it.* The trigger is mechanical and mandatory; the isolation property is **recorded and surfaced**, never blocking. A blocking step was explicitly rejected because it would recreate the very skip-pressure §24 exists to remove.

**Why the isolation is recorded rather than enforced — verified, do not redesign this:** `clavity-dotnet/src/Clavity.Mcp/McpTools.cs` exposes exactly three tools (`agy_look`, `agy_status`, `agy_ask`), and all three address *the active conversation*. Nothing in that surface can start a fresh cascade; `RunAsync` even has a `waiting_for_human` path for when agy has no conversation yet. `clavity-classic/src/tmux.rs:224-262` *does* have `send_keys` and `kill-session`, so terminal-level lifecycle control exists on that half only — but the skills ship byte-identical, so **the rule must be written to the weaker transport.** `clavity-dotnet/src/Clavity.Ls/AgyView.cs:150-152` records that `status.CascadeId` string-equals `ask.CascadeId` precisely so a consumer can correlate them. That correlation is the whole mechanism.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `scripts/check-capstone-new-code.ps1` | **Create** | Read-only. Answers "does this diff introduce new code in non-test shipped source?" Exit 0 = no, exit 3 = trigger fired. |
| `scripts/tests/check-capstone-new-code.Tests.ps1` | **Create** | Pester suite for the above, including the three historical cases from the 8-round capstone that motivated §24. |
| `clavity-dotnet/plugin/hooks/agy-mark.sh` | Modify | Gains a `stamp` subcommand recording consult/review cascade ids. |
| `clavity-classic/plugin/hooks/agy-mark.sh` | Modify | Byte-identical mirror. |
| `scripts/tests/agy-mark-stamp.Tests.ps1` | **Create** | Pester suite for the `stamp` subcommand. |
| `clavity-dotnet/plugin/skills/agy-capstone/SKILL.md` | Modify | Adds the §24 section: mandatory consult, pause-don't-abort, the stamp, and SHARED-CONTEXT surfacing. |
| `clavity-classic/plugin/skills/agy-capstone/SKILL.md` | Modify | Byte-identical mirror. |
| `clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md` | Modify | Gains `AGY-NEGOTIATE`. |
| `clavity-classic/plugin/skills/agy-test-audit/SKILL.md` | Modify | Byte-identical mirror. |
| `clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md` | Modify | Gains `AGY-NEGOTIATE`. |
| `clavity-classic/plugin/skills/adversarial-panel-review/SKILL.md` | Modify | Byte-identical mirror. |
| `scripts/check-agy-discipline-skills.ps1` | Modify | Pins the `AGY-NEGOTIATE` section across all four disciplines. |
| `scripts/tests/check-agy-discipline-skills.Tests.ps1` | Modify | Proves the new pin is non-vacuous by mutant. |
| `clavity-dotnet/ROADMAP.md` | Modify | Fixes §25's factually stale body; marks §24 and §25 shipped. |

**Task order is deliberate:** the mechanism (Tasks 1–3) ships and is proven before any `SKILL.md` prose claims it exists. A skill asserting a guard that is not yet wired is a **False Safety Promise**, which this repository's own severity table classes as BLOCKING.

---

## Task 1: The mechanical trigger — `check-capstone-new-code.ps1`

**Files:**
- Create: `scripts/check-capstone-new-code.ps1`
- Test: `scripts/tests/check-capstone-new-code.Tests.ps1`

**The trigger, final (ROADMAP §24, after the folded refinements):** a **new file**, a **new function/class declaration**, or a **whole-function rewrite**, in **NON-TEST shipped code**. The `>10 lines` clause from the peer's original proposal was **deliberately dropped** — it is comment-sensitive, and this repository's folds are heavily commented, so a two-line behavioural change routinely exceeds ten lines. Do not reintroduce it.

**How "whole-function rewrite" is detected mechanically:** git's own hunk header carries the enclosing function context (`@@ -10,8 +10,12 @@ function Foo-Bar`). A hunk whose header names a context AND which removes at least 5 lines AND adds at least 5 lines is a rewrite. This uses git's language-aware function detection rather than a hand-rolled parser.

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/check-capstone-new-code.Tests.ps1`:

```powershell
BeforeAll {
    $script:Checker = Join-Path (Split-Path -Parent $PSScriptRoot) 'check-capstone-new-code.ps1'

    # A throwaway git repo. NEVER run these fixtures against the clavity repo itself: a control run
    # in-repo gives a FALSE PASS because the real tree already satisfies most shapes under test.
    function New-Repo {
        $d = Join-Path ([System.IO.Path]::GetTempPath()) ("ccnc-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d | Out-Null
        Push-Location $d
        git init -q 2>&1 | Out-Null
        git config user.email t@t.t; git config user.name t
        git config commit.gpgsign false
        New-Item -ItemType Directory -Path (Join-Path $d 'src') | Out-Null
        Set-Content -Path (Join-Path $d 'src/seed.ps1') -Value "Write-Output 'seed'"
        git add src/seed.ps1 2>&1 | Out-Null
        git commit -qm seed 2>&1 | Out-Null
        Pop-Location
        return $d
    }

    function Invoke-Checker($Repo, $BaseRef) {
        Push-Location $Repo
        try {
            $out = & pwsh -NoProfile -File $script:Checker -BaseRef $BaseRef -Root $Repo 2>&1 | Out-String
            return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Out = $out }
        } finally { Pop-Location }
    }
}

Describe 'check-capstone-new-code' {

    It 'does NOT fire on a small edit inside an existing function' {
        $r = New-Repo
        try {
            Push-Location $r
            Add-Content -Path 'src/seed.ps1' -Value "Write-Output 'one more line'"
            git commit -qam edit 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 0 -Because 'a two-line edit is exactly what the dropped >10-lines clause used to false-positive on'
            $res.Out | Should -Not -Match 'TRIGGER'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a new non-test source file' {
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/brand-new.ps1' -Value "function New-Thing { 'x' }"
            git add src/brand-new.ps1 2>&1 | Out-Null
            git commit -qm add 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3
            $res.Out | Should -Match 'new-file'
            $res.Out | Should -Match 'src/brand-new\.ps1'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT fire on a new TEST file' {
        # THE NON-TEST CLAUSE IS THE ASSERTION. Without it the trigger fires on every round that
        # adds a pinning test, which is most of them, and the consult becomes noise the driver learns
        # to wave through.
        $r = New-Repo
        try {
            Push-Location $r
            New-Item -ItemType Directory -Path (Join-Path $r 'scripts/tests') -Force | Out-Null
            Set-Content -Path 'scripts/tests/thing.Tests.ps1' -Value "Describe 'x' { It 'y' { 1 | Should -Be 1 } }"
            git add scripts/tests/thing.Tests.ps1 2>&1 | Out-Null
            git commit -qm addtest 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a new function declaration added to an existing file' {
        $r = New-Repo
        try {
            Push-Location $r
            Add-Content -Path 'src/seed.ps1' -Value "function Get-Census { param(`$p) return 1 }"
            git commit -qam newfn 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3
            $res.Out | Should -Match 'new-declaration'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a new C# METHOD added to an existing class, not only on a new type' {
        # AGY-AFTER round 1, Mechanism Gamer. A types-only regex is blind to the most common unit of
        # new C# code, so an agent skips the consult by adding a method instead of a class.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/Thing.cs' -Value @('public class Thing', '{', '}')
            git add src/Thing.cs 2>&1 | Out-Null; git commit -qm cls 2>&1 | Out-Null
            Set-Content -Path 'src/Thing.cs' -Value @('public class Thing', '{', '    public void DoWork(int n)', '    {', '    }', '}')
            git commit -qam method 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3
            $res.Out | Should -Match 'new-declaration'
            $res.Out | Should -Match 'DoWork'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a C# CONSTRUCTOR, which carries no return type' {
        # AGY-AFTER round 2, Mechanism Gamer, attacking round 1's OWN FIX. The two-identifier method
        # pattern cannot see `public MyClass()`, so nesting the new logic in a constructor still
        # bypassed the trigger after fold 4. This row pins the constructor pattern specifically.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/Widget.cs' -Value @('public class Widget', '{', '}')
            git add src/Widget.cs 2>&1 | Out-Null; git commit -qm cls 2>&1 | Out-Null
            Set-Content -Path 'src/Widget.cs' -Value @('public class Widget', '{', '    public Widget(int n)', '    {', '    }', '}')
            git commit -qam ctor 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3 -Because 'a constructor is new executable code'
            $res.Out | Should -Match 'new-declaration'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT desync on a status it does not know' {
        # AGY-AFTER round 2, Cascade Analyst, attacking round 1's OWN FIX. An unhandled status letter
        # left its path unconsumed, desyncing the index so the NEXT path was read as a status - and a
        # path starting with 'A' then registered as a phantom new file. The exhaustive else prevents
        # it. A plain modify-only range must stay silent no matter how many files it touches.
        $r = New-Repo
        try {
            Push-Location $r
            foreach ($n in 1..4) { Set-Content -Path "src/Afile$n.ps1" -Value "Write-Output $n" }
            git add -A 2>&1 | Out-Null; git commit -qm many 2>&1 | Out-Null
            foreach ($n in 1..4) { Add-Content -Path "src/Afile$n.ps1" -Value "# touched" }
            git commit -qam touch 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 0 -Because 'modifying files whose names begin with A creates nothing'
            $res.Out | Should -Not -Match 'new-file'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a file that arrives by RENAME, not only by plain add' {
        # AGY-AFTER round 1. '^A' alone misses R### and C### statuses, and a renamed file is a file
        # that now exists at a path where it did not before.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/original.ps1' -Value ("function Get-Body { 1 }`n" * 12)
            git add src/original.ps1 2>&1 | Out-Null; git commit -qm orig 2>&1 | Out-Null
            git mv src/original.ps1 src/renamed.ps1 2>&1 | Out-Null
            git commit -qm ren 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3
            $res.Out | Should -Match 'src/renamed\.ps1'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'handles a path containing a SPACE without letting it defeat the test-path exclusion' {
        # git QUOTES such paths in --name-status unless -z is used, and the quotes defeat the
        # anchored exclusion patterns. The peer flagged this as the one thing it could not judge
        # without running it; this row is the measurement.
        $r = New-Repo
        try {
            Push-Location $r
            New-Item -ItemType Directory -Path (Join-Path $r 'scripts/tests') -Force | Out-Null
            Set-Content -Path 'scripts/tests/my file.Tests.ps1' -Value "Describe 'x' { It 'y' { 1 | Should -Be 1 } }"
            git add -- 'scripts/tests/my file.Tests.ps1' 2>&1 | Out-Null
            git commit -qm spaced 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 0 -Because 'a spaced TEST path is still a test path'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports EVERY rule that fired, not just the first' {
        # A checker that stops at the first hit under-reports the blast radius, and the driver then
        # consults on one shape while shipping two.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/another.ps1' -Value "Write-Output 'a'"
            Add-Content -Path 'src/seed.ps1' -Value "function Get-Second { return 2 }"
            git add -A 2>&1 | Out-Null
            git commit -qm both 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3
            $res.Out | Should -Match 'new-file'
            $res.Out | Should -Match 'new-declaration'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'REFUSES a base ref that resolves to HEAD, rather than reporting a clean empty range' {
        # THE SKIP HOLE. The checker is mechanical, but its INPUT comes from the agent that would
        # benefit from skipping the consult. Handed HEAD it sees an empty diff and, without this
        # guard, returns exit 0 - handing that agent a clean bill of health as evidence.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/sneaky.ps1' -Value "function Get-Sneaky { 1 }"
            git add src/sneaky.ps1 2>&1 | Out-Null; git commit -qm sneak 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD'
            $res.ExitCode | Should -Be 2 -Because 'an empty range is an unanswerable question, not a negative answer'
            $res.Out | Should -Match 'resolves to HEAD'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits NON-ZERO and says so when the base ref does not exist' {
        # FAIL CLOSED. An unresolvable ref must never read as "no new code" - that is a guard
        # certifying exactly what it stopped checking.
        $r = New-Repo
        try {
            $res = Invoke-Checker $r 'no-such-ref-xyz'
            $res.ExitCode | Should -Be 2
            $res.Out | Should -Match 'could not resolve'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester scripts/tests/check-capstone-new-code.Tests.ps1"`

Expected: FAIL. Every `It` errors because `scripts/check-capstone-new-code.ps1` does not exist.

⚠ **Read the failure text.** A Pester run that prints no `Tests Passed:` line, or prints `Tests Passed: 0`, is an ABORTED run that reads like a pass — usually a `.ps1` parse error. Confirm the file parses before trusting any number.

- [ ] **Step 3: Write the implementation**

Create `scripts/check-capstone-new-code.ps1`:

```powershell
# scripts/check-capstone-new-code.ps1
# READ-ONLY. Answers one question for AGY-CAPSTONE (ROADMAP section 24): does the range introduce NEW
# CODE, such that an AGY-FIRST design consult is mandatory before the fold ships?
#
# Exit 0 = no new code, proceed.       Exit 3 = TRIGGER FIRED, consult required.
# Exit 2 = the question could not be answered (fail CLOSED, never silently "no").
#
# WHY A SCRIPT AND NOT A JUDGEMENT CALL: section 24's whole point is that the trigger is evaluated
# mechanically, never by the agent that would benefit from skipping it. Do not add a flag that lets a
# caller suppress the trigger.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaseRef,
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'

# A path is TEST code if any of these match. Kept deliberately broad: a false "this is a test" only
# ever SUPPRESSES the consult, so each entry must be one nothing shipped can match.
$TestPatterns = @(
    '(^|/)tests?/'
    '\.Tests\.ps1$'
    '_test\.(rs|go|py)$'
    '(^|/)test_[^/]+\.py$'
)

function Test-IsTestPath([string]$p) {
    foreach ($pat in $TestPatterns) { if ($p -match $pat) { return $true } }
    return $false
}

# A new DECLARATION, per language. Anchored on the '+' of the diff so only ADDED lines count.
$DeclarationPatterns = @(
    '^\+\s*function\s+[A-Za-z_]'                       # PowerShell, bash 'function f'
    '^\+\s*[A-Za-z_][A-Za-z0-9_]*\s*\(\)\s*\{'         # bash 'f() {'
    '^\+\s*(pub\s+)?(async\s+)?fn\s+[A-Za-z_]'         # Rust
    '^\+\s*(public|private|internal|protected)\s+.*\b(class|record|struct|interface|enum)\s+'  # C# types
    # C# METHODS, not just types. AGY-AFTER round 1 (Mechanism Gamer) caught this: with types-only,
    # an agent that wants to skip the consult drops its new code into a `public void Foo()` on an
    # EXISTING class and the trigger stays silent - which is the single most common unit of new C#
    # code in this repository. Matches an access modifier followed by a return type and a call-shaped
    # name, excluding control-flow keywords that also take parentheses.
    '^\+\s*(public|private|internal|protected)\s+(static\s+|async\s+|override\s+|virtual\s+|sealed\s+)*[A-Za-z_][A-Za-z0-9_<>,\[\]\.\?]*\s+[A-Za-z_][A-Za-z0-9_]*\s*\('
    # CONSTRUCTORS have NO return type, so the two-identifier pattern above cannot see them. AGY-AFTER
    # round 2 (Mechanism Gamer) caught that fold 4 left this bypass open: nest the new logic in a
    # constructor and the trigger stays silent. Access modifier, then a Capitalized name, then '('.
    '^\+\s*(public|private|internal|protected)\s+[A-Z][A-Za-z0-9_]*\s*\('
    # TUPLE RETURNS start with a parenthesis - `public (int, int) Get()` - which the two-identifier
    # pattern also misses. Same round, same seat.
    '^\+\s*(public|private|internal|protected)\s+(static\s+|async\s+)*\([^)]*\)\s+[A-Za-z_][A-Za-z0-9_]*\s*\('
    '^\+\s*(def|class)\s+[A-Za-z_]'                    # Python
)

Push-Location $Root
try {
    # Resolve the base ref FIRST. An unresolvable ref must fail closed - it is not "no new code".
    & git rev-parse --verify --quiet "$BaseRef^{commit}" > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Output "check-capstone-new-code: could not resolve base ref '$BaseRef'"
        exit 2
    }

    # THE INPUT IS PART OF THE TRIGGER. Section 24 says the trigger is evaluated mechanically and never
    # by the agent that wants to skip it - but an agent that supplies its own BaseRef can hand us HEAD,
    # get an empty diff, and collect a clean exit 0 as PROOF that no consult was owed. That is a guard
    # certifying exactly what it stopped checking. A base that IS head is not a range; refuse it.
    $baseSha = (& git rev-parse "$BaseRef^{commit}").Trim()
    $headSha = (& git rev-parse 'HEAD^{commit}').Trim()
    if ($baseSha -eq $headSha) {
        Write-Output "check-capstone-new-code: base ref '$BaseRef' resolves to HEAD - that is an empty range, not a clean result. Supply the round's recorded base."
        exit 2
    }

    $fired = [System.Collections.Generic.List[string]]::new()

    # --- Rule A: a NEW FILE in non-test code -------------------------------------------------
    # -z gives NUL-separated, UNQUOTED paths. Without it git QUOTES any path containing a space or a
    # non-ASCII byte ("my file.ps1"), and the captured quotes then defeat Test-IsTestPath's anchors -
    # a path the exclusion should have caught sails through as shippable. The peer flagged this as the
    # one thing it could not judge without running it; measured, git does quote such paths, so -z is
    # the fix rather than a regex that strips quotes.
    $nameStatus = (& git diff --name-status -z "$BaseRef..HEAD") -split "`0" | Where-Object { $_ -ne '' }

    # A RENAME and a COPY create a file too. `git diff --name-status` emits R### / C### with TWO paths
    # (old then new), so anchoring on '^A' alone - as this rule first did - misses every new file that
    # arrived by rename or copy. AGY-AFTER round 1 finding, folded.
    # THE else IS EXHAUSTIVE ON PURPOSE, and that is a correctness property rather than tidiness.
    # AGY-AFTER round 2 (Cascade Analyst) caught an earlier draft matching only '^[MTD]': a status this
    # parser does not know - U (unmerged), X (unknown), B (broken) - fell through ALL branches, so its
    # path was never consumed, the index desynced by one, and the NEXT iteration read that path as a
    # status. A path beginning with 'A' then registered as a phantom new file. Every git status carries
    # exactly ONE path except R and C, which carry two, so branching on that alone cannot desync.
    for ($i = 0; $i -lt $nameStatus.Count; $i++) {
        $status = $nameStatus[$i]
        if ($status -match '^[RC]') {
            $null = $nameStatus[++$i]          # the OLD path, which we do not care about
            $path = $nameStatus[++$i]          # the NEW path, which is the one that now exists
            if (-not (Test-IsTestPath $path)) { $fired.Add("new-file-via-$($status.Substring(0,1)): $path") }
        }
        else {
            $path = $nameStatus[++$i]          # EVERY other status carries exactly one path
            if ($status -match '^A' -and -not (Test-IsTestPath $path)) { $fired.Add("new-file: $path") }
        }
    }

    # --- Rules B and C need the patch, and only for non-test paths ---------------------------
    # -U0 keeps hunks minimal; the function context still rides in the @@ header, which is what
    # rule C reads. Generated and vendored paths are excluded the same way the capstone excludes
    # them from review.
    $patch = & git diff -U0 "$BaseRef..HEAD" -- . `
        ':(exclude)*.lock' ':(exclude)*.min.js' ':(exclude)package-lock.json'

    $currentFile = $null
    $currentIsTest = $false
    $hunkHeader = $null
    $hunkAdds = 0
    $hunkDels = 0

    function Complete-Hunk {
        if ($null -ne $script:hunkHeader -and -not $script:currentIsTest) {
            # Rule C: git named an enclosing function AND both sides are substantial.
            if ($script:hunkHeader.Trim() -ne '' -and $script:hunkAdds -ge 5 -and $script:hunkDels -ge 5) {
                $script:fired.Add("whole-function-rewrite: $($script:currentFile) [$($script:hunkHeader.Trim())]")
            }
        }
        $script:hunkHeader = $null; $script:hunkAdds = 0; $script:hunkDels = 0
    }

    foreach ($line in $patch) {
        if ($line -match '^\+\+\+ b/(.+)$') {
            Complete-Hunk
            $currentFile = $Matches[1].Trim()
            $currentIsTest = Test-IsTestPath $currentFile
            continue
        }
        if ($line -match '^@@ [^@]+ @@(.*)$') {
            Complete-Hunk
            $hunkHeader = $Matches[1]
            continue
        }
        if ($currentIsTest) { continue }
        if ($line -match '^\+' -and $line -notmatch '^\+\+\+') {
            $hunkAdds++
            foreach ($pat in $DeclarationPatterns) {
                if ($line -match $pat) {
                    $fired.Add("new-declaration: $currentFile : $($line.TrimStart('+').Trim())")
                    break
                }
            }
        }
        elseif ($line -match '^-' -and $line -notmatch '^---') { $hunkDels++ }
    }
    Complete-Hunk

    if ($fired.Count -eq 0) {
        Write-Output "check-capstone-new-code: no new code in $BaseRef..HEAD - AGY-FIRST consult not required."
        exit 0
    }

    Write-Output "check-capstone-new-code: TRIGGER FIRED - AGY-FIRST consult is MANDATORY before this fold ships."
    # Report EVERY rule that fired. Reporting only the first understates the blast radius.
    $fired | Sort-Object -Unique | ForEach-Object { Write-Output "  - $_" }
    exit 3
}
finally { Pop-Location }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester scripts/tests/check-capstone-new-code.Tests.ps1"`

Expected: `Tests Passed: 12, Failed: 0`.

- [ ] **Step 5: Prove the non-test clause is non-vacuous with a logic mutant**

Temporarily empty the exclusion so every path counts as shippable:

```powershell
# In scripts/check-capstone-new-code.ps1, change Test-IsTestPath's body to: return $false
```

Run: `pwsh -NoProfile -Command "Invoke-Pester scripts/tests/check-capstone-new-code.Tests.ps1 -PassThru | Select-Object -ExpandProperty Failed | Select-Object -ExpandProperty Name"`

Expected: the failing test is named **`does NOT fire on a new TEST file`**. Confirm that specific name — a non-zero suite alone proves nothing, and a mutant that reddens for an unrelated reason (a parse error, a `grep` that exits 2) certifies a real gap as covered. **Then restore the function body and re-run to confirm 6/6 green again.**

- [ ] **Step 6: Commit**

```bash
git add scripts/check-capstone-new-code.ps1 scripts/tests/check-capstone-new-code.Tests.ps1
git commit -m "feat(s24): mechanical trigger for the mandatory capstone design consult"
```

---

## Task 2: Register the new suite in the justfile

**Files:**
- Modify: `justfile` (the Pester suite list)

⚠ **Test registration in this repo is an explicit LIST, not a glob.** A new `.Tests.ps1` that is not added here never runs, and its absence looks exactly like a passing suite.

✅ **VERIFIED 2026-09-04 — this is mechanically enforced, so you cannot silently forget it.** `scripts/tests/test-suite-registration.Tests.ps1` is itself registered (justfile line 101) and fails when a suite exists on disk but appears in no list. Expect it to go RED the moment you create the new file and GREEN once you register it — that red is the oracle working, not a problem.

**There are TWO lists**, both single-line `Invoke-Pester @(...)` arrays:
- **justfile line 101** — the fast group (contains `check-agy-discipline-skills.Tests.ps1`, `plugin-hooks-payload.Tests.ps1`).
- **justfile line 108** — the slow group (contains `agy-anomaly-reminder.Tests.ps1`, `agy-mark.Tests.ps1`).

**Put `check-capstone-new-code.Tests.ps1` in the SLOW group (line 108).** It shells out to `git` and `pwsh` per test against throwaway repos, which is the cost profile of that group — and `agy-mark.Tests.ps1`, its nearest sibling, already lives there.

- [ ] **Step 1: Confirm the two lists are where this plan says**

Run: `grep -n "Tests.ps1" justfile | cut -c1-120`

Expected: two long `Invoke-Pester @(...)` lines, at or near 101 and 108.

- [ ] **Step 2: Add the entry to the line-108 array**

Insert `'scripts/tests/check-capstone-new-code.Tests.ps1', ` into that array, matching the existing `'path', ` quoting and comma-space style exactly. **Keep it one line** — the recipe is a single shell command and breaking the array across lines changes the recipe's meaning.

- [ ] **Step 3: Verify registration is now satisfied**

Run: `pwsh -NoProfile -Command "Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1"`

Expected: `Failed: 0`. This is the mechanical proof the suite is wired in — do not substitute eyeballing the justfile for it.

- [ ] **Step 4: Commit**

```bash
git add justfile
git commit -m "chore(s24): register the capstone new-code checker suite"
```

---

## Task 3: `agy-mark.sh stamp` — record the isolation property

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-mark.sh` (subcommand dispatch; existing subcommands are `head` at :192, `log` at :207, `prepare` at :249 — **re-read these line numbers before editing, they shift**)
- Modify: `clavity-classic/plugin/hooks/agy-mark.sh` (byte-identical mirror)
- Test: `scripts/tests/agy-mark-stamp.Tests.ps1`

**What it records.** One append-only line per consult, into `.clavity/agy-marks/consults.log`:

```
<ISO-8601> <discipline> consult=<consult-cascade-id> review=<review-cascade-id> <SHARED-CONTEXT|ISOLATED> <sha>
```

`SHARED-CONTEXT` when the two ids are equal. This is a **record**, never a gate: nothing exits non-zero because of it. The owner sees it at capstone-GREEN adjudication and may then demand a fresh-cascade re-review.

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/agy-mark-stamp.Tests.ps1`:

```powershell
BeforeAll {
    $script:Mark = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'clavity-dotnet/plugin/hooks/agy-mark.sh'

    function New-Repo {
        $d = Join-Path ([System.IO.Path]::GetTempPath()) ("mstamp-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d | Out-Null
        Push-Location $d
        git init -q 2>&1 | Out-Null
        git config user.email t@t.t; git config user.name t; git config commit.gpgsign false
        Set-Content -Path (Join-Path $d 'f.txt') -Value 'x'
        git add f.txt 2>&1 | Out-Null; git commit -qm seed 2>&1 | Out-Null
        Pop-Location
        return $d
    }

    function Invoke-Stamp($Repo, [string[]]$MarkArgs) {
        Push-Location $Repo
        try {
            $out = & bash $script:Mark @MarkArgs 2>&1 | Out-String
            return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Out = $out }
        } finally { Pop-Location }
    }
}

Describe 'agy-mark.sh stamp' {

    It 'records SHARED-CONTEXT when the consult and review cascade ids are equal' {
        $r = New-Repo
        try {
            $res = Invoke-Stamp $r @('stamp','agy-capstone','cascade-aaa','cascade-aaa')
            $res.ExitCode | Should -Be 0
            $log = Get-Content (Join-Path $r '.clavity/agy-marks/consults.log') -Raw
            $log | Should -Match 'SHARED-CONTEXT'
            $log | Should -Not -Match 'ISOLATED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'records ISOLATED when the two cascade ids differ' {
        $r = New-Repo
        try {
            $res = Invoke-Stamp $r @('stamp','agy-capstone','cascade-aaa','cascade-bbb')
            $res.ExitCode | Should -Be 0
            $log = Get-Content (Join-Path $r '.clavity/agy-marks/consults.log') -Raw
            $log | Should -Match 'ISOLATED'
            $log | Should -Not -Match 'SHARED-CONTEXT'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is APPEND-ONLY - a second stamp does not destroy the first' {
        # The log is evidence. A writer that truncates turns an audit trail into a single data point,
        # and this repo has already been bitten by a '>' where a '>>' belonged.
        $r = New-Repo
        try {
            Invoke-Stamp $r @('stamp','agy-capstone','c1','c1') | Out-Null
            Invoke-Stamp $r @('stamp','agy-test-audit','c2','c3') | Out-Null
            $lines = @(Get-Content (Join-Path $r '.clavity/agy-marks/consults.log') | Where-Object { $_ -match 'consult=' })
            $lines.Count | Should -Be 2
            ($lines -join "`n") | Should -Match 'agy-capstone'
            ($lines -join "`n") | Should -Match 'agy-test-audit'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'NEVER exits non-zero on a shared context - it records, it does not gate' {
        # The owner's ruling is explicit: recording isolation must never block. A stamp that failed
        # the build on SHARED-CONTEXT would recreate exactly the skip-pressure section 24 removes.
        $r = New-Repo
        try {
            $res = Invoke-Stamp $r @('stamp','agy-capstone','same','same')
            $res.ExitCode | Should -Be 0 -Because 'the stamp is a record, never a gate'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects a call with missing arguments rather than writing a malformed row' {
        $r = New-Repo
        try {
            $res = Invoke-Stamp $r @('stamp','agy-capstone','only-one-id')
            $res.ExitCode | Should -Not -Be 0
            Test-Path (Join-Path $r '.clavity/agy-marks/consults.log') | Should -BeFalse
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester scripts/tests/agy-mark-stamp.Tests.ps1"`

Expected: FAIL — `agy-mark.sh` does not know the `stamp` subcommand.

- [ ] **Step 3: Add the subcommand to `clavity-dotnet/plugin/hooks/agy-mark.sh`**

Add this case arm alongside the existing `head)`, `log)` and `prepare)` arms. **Read the file first** and match its existing idiom for resolving the repo root and asserting the `.clavity/` shield — do not invent a second way of doing either.

```bash
    stamp)
        # Record whether a design consult and the review that follows it shared one agy cascade.
        # THIS IS A RECORD, NOT A GATE. It always exits 0 on a well-formed call, including
        # SHARED-CONTEXT. Owner ruling 2026-09-04: "record isolation, do not gate on it" - a blocking
        # step here would recreate the skip-pressure the mandatory consult exists to remove.
        discipline="${2:-}"
        consult_id="${3:-}"
        review_id="${4:-}"
        if [ -z "$discipline" ] || [ -z "$consult_id" ] || [ -z "$review_id" ]; then
            echo "agy-mark stamp: need <discipline> <consult-cascade-id> <review-cascade-id>" >&2
            exit 64
        fi
        if [ "$consult_id" = "$review_id" ]; then
            isolation="SHARED-CONTEXT"
        else
            isolation="ISOLATED"
        fi
        # CREATE THE DIRECTORY FIRST. AGY-AFTER round 2 (Cascade Analyst) caught this as BLOCKING:
        # without it, `>>` into a missing .clavity/agy-marks fails with "No such file or directory"
        # and the arm exits NON-ZERO on a fresh clone or the very first consult - turning the one step
        # that is explicitly "a record, never a gate" into an accidental blocker. VERIFIED: this file
        # has NO shared mkdir; the head, log and prepare arms each do their own.
        #
        # A FAILED MKDIR STILL MUST NOT GATE. head) and prepare) call _die_refuse here because their
        # write is load-bearing; ours is not, so a genuinely unwritable directory degrades to a warning
        # on stderr and exit 0 rather than blocking the round.
        mkdir -p "$root/.clavity/agy-marks" 2>/dev/null || {
            echo "agy-mark stamp: could not create .clavity/agy-marks - isolation NOT recorded" >&2
            exit 0
        }
        # Append with >>, never >. Two sessions can be open on one repository, and a truncating
        # writer silently eats the other's row.
        printf '%s %s consult=%s review=%s %s %s\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$discipline" "$consult_id" "$review_id" \
            "$isolation" "$(git rev-parse HEAD 2>/dev/null || echo unknown)" \
            >> "$root/.clavity/agy-marks/consults.log" 2>/dev/null || {
            echo "agy-mark stamp: could not write consults.log - isolation NOT recorded" >&2
            exit 0
        }
        exit 0
        ;;
```

🔴 **`$root` is the variable the existing arms already use** — VERIFIED 2026-09-04: they write the path literally as `"$root/.clavity/agy-marks"`. **There is no `$marks_dir` variable in this file**; an earlier draft of this plan invented one. Read the file and use `$root`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester scripts/tests/agy-mark-stamp.Tests.ps1"`

Expected: `Tests Passed: 5, Failed: 0`.

- [ ] **Step 5: Prove the comparison is non-vacuous with a logic mutant**

Invert the equality test in the arm you just added:

```bash
        if [ "$consult_id" != "$review_id" ]; then
```

Run: `pwsh -NoProfile -Command "Invoke-Pester scripts/tests/agy-mark-stamp.Tests.ps1 -PassThru | Select-Object -ExpandProperty Failed | Select-Object -ExpandProperty Name"`

Expected: **both** `records SHARED-CONTEXT when the consult and review cascade ids are equal` and `records ISOLATED when the two cascade ids differ` are named. Restore the `=` and re-run for 5/5.

- [ ] **Step 6: Mirror to the classic half and prove byte-identity**

```bash
cp clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh
cmp clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh && echo IDENTICAL
bash scripts/check-seed-artifacts-synced.sh; echo "exit=$?"
```

Expected: `IDENTICAL`, then `exit=0`.

- [ ] **Step 7: Register the suite in the justfile and commit**

Add `scripts/tests/agy-mark-stamp.Tests.ps1` to the same explicit list you edited in Task 2.

```bash
git add clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh scripts/tests/agy-mark-stamp.Tests.ps1 justfile
git commit -m "feat(s24): agy-mark stamp records consult/review cascade isolation"
```

---

## Task 4: Wire §24 into the capstone skill

**Files:**
- Modify: `clavity-dotnet/plugin/skills/agy-capstone/SKILL.md`
- Modify: `clavity-classic/plugin/skills/agy-capstone/SKILL.md`

🔴 **Load the `writing-skills` skill before this task.** Standing owner instruction, and the owner has caught this being skipped twice.

- [ ] **Step 1: Add the section**

Insert this immediately **before** the existing `## AGY-NEGOTIATE (auto-fires on material disagreement)` heading (currently at line 386 — **re-read to confirm**, earlier tasks do not touch this file but always verify):

```markdown
## The mandatory design consult when a round writes NEW CODE (ROADMAP section 24)

A capstone round that has to DEVELOP NEW CODE must get an AGY-FIRST design consult on that code BEFORE
the fold ships. This is not advisory and it is not your call.

**MEASURED, and this is why the rule exists.** In the 8-round capstone `6c998ce..274afbd` (ledger
`8c7bf18`) three pieces of new code were written mid-capstone, and **every one produced a defect in the
very next round**: a recursive census whose exclusion boundary was a glob over a path we do not control;
a chunked batch hasher whose `else return 1` sat on the left of a pipeline, so it ran in a subshell and
reported SUCCESS on failure; and a digest function that returned a CONSTANT on a short count, which
compares equal to itself and blinds the monitor. **The one piece that got a design consult first had
three defects found BEFORE it shipped**, including a GNU-only `xargs -r` that would have made the digest
a constant on macOS - blind while reporting clean.

**The trigger is MECHANICAL and you do not evaluate it.** Run the checker:

```bash
pwsh -NoProfile -File scripts/check-capstone-new-code.ps1 -BaseRef "<this round's base sha>"
```

Exit `0` - no new code, proceed. Exit `3` - **consult required.** Exit `2` - the checker could not answer
(an unresolvable ref); treat that as REQUIRED, never as "no".

The trigger is: a **new file**, a **new function or class declaration**, or a **whole-function rewrite**,
in **non-test** code. It is deliberately NOT line-count based - a line threshold is comment-sensitive, and
this repository's folds are heavily commented, so a two-line behavioural change routinely exceeds ten
lines.

**PAUSE THE FOLD; DO NOT ABORT THE CAPSTONE.** An abort throws away the round's accumulated context and
ledger for something one consult fixes. The round pauses, the consult runs, the round resumes.

**Then record the isolation property.** Capture the cascade id of the consult (the `CascadeId` on the
`agy_ask` result) and of the review round (the `CascadeId` from `agy_status`), and stamp them:

```bash
bash "<BASE>/../../hooks/agy-mark.sh" stamp "agy-capstone" "<consult-cascade-id>" "<review-cascade-id>"
```

**This is a RECORD, never a GATE.** It always exits 0. A `SHARED-CONTEXT` row means the peer reviewed a
design it had itself endorsed in the same context window; surface that row to your human at the GREEN
adjudication so they can demand a fresh-cascade re-review if the design was load-bearing. Do NOT block on
it, and do NOT skip the consult because it would be shared - **owner ruling 2026-09-04: record isolation,
do not gate on it.** A blocking step would recreate exactly the skip-pressure this rule removes.

**Why recorded rather than enforced, so nobody redesigns this by accident:** no tool in the
clavity-dotnet MCP surface can start a fresh cascade - `agy_look`, `agy_status` and `agy_ask` all address
the ACTIVE conversation - so structural separation is not an action the driver can take. It is available
only by a human cycling the peer. The rule is written to that weaker transport because these skills ship
byte-identical across both plugin halves.
```

- [ ] **Step 2: Mirror to the classic half and prove byte-identity**

```bash
cp clavity-dotnet/plugin/skills/agy-capstone/SKILL.md clavity-classic/plugin/skills/agy-capstone/SKILL.md
cmp clavity-dotnet/plugin/skills/agy-capstone/SKILL.md clavity-classic/plugin/skills/agy-capstone/SKILL.md && echo IDENTICAL
```

- [ ] **Step 3: Run the skill gates**

```bash
pwsh -NoProfile -File scripts/check-agy-discipline-skills.ps1; echo "exit=$?"
bash scripts/check-seed-artifacts-synced.sh; echo "exit=$?"
pwsh -NoProfile -Command "Invoke-Pester scripts/tests/plugin-hooks-payload.Tests.ps1"
```

Expected: both `exit=0`, and the payload suite green.

⚠ **The capstone skill is ASCII-only by contract** (mojibake risk — this project has hit corruption). The block above uses only ASCII; if you reword it, keep it ASCII.

- [ ] **Step 4: Commit**

```bash
git add clavity-dotnet/plugin/skills/agy-capstone/SKILL.md clavity-classic/plugin/skills/agy-capstone/SKILL.md
git commit -m "feat(s24): the capstone's mandatory design consult, with isolation recorded not gated"
```

---

## Task 5: §25 — add `AGY-NEGOTIATE` to the two skills that lack it

**Files:**
- Modify: `clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md`
- Modify: `clavity-classic/plugin/skills/agy-test-audit/SKILL.md`
- Modify: `clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md`
- Modify: `clavity-classic/plugin/skills/adversarial-panel-review/SKILL.md`

🔴 **Load the `writing-skills` skill before this task.**

🔴 **SCOPE CORRECTION — VERIFIED 2026-09-04, and the ROADMAP is WRONG about it.** §25's body claims `AGY-NEGOTIATE` "exists in exactly one skill" and lists `agy-first` among those lacking it. **That is false.** Measured with `grep -c 'AGY-NEGOTIATE'` across both plugin halves: `agy-first` = 2, `agy-capstone` = 3, `agy-test-audit` = 0, `adversarial-panel-review` = 0. `agy-first/SKILL.md:162-175` carries a complete protocol — material-only trigger, `MAX_NEGOTIATE_ROUNDS = 2` marked tunable, impasse with human tie-break, and a "negotiate with agy" manual backstop. **Real scope is TWO skills, not three.** Task 7 fixes the ROADMAP text.

**Use `agy-first`'s wording as the model, not the capstone's.** It is tighter, it marks the cap tunable, and it states "Do not fabricate agreement" explicitly.

- [ ] **Step 1: Add the section to `agy-test-audit/SKILL.md`**

Insert before its `## Disposition of findings (AGY-SCOPE)` heading:

```markdown
## AGY-NEGOTIATE (conditional sub-protocol)

Engage negotiation ONLY on a **material** disagreement - one that changes what the suite actually
guarantees: a claimed gap you believe is already covered, or a covered behaviour the peer says is not.
Style, naming and trivia never qualify; you yield on those.

**SHIP THE MECHANISM; AGREEMENT IS NOT THE SUCCESS CRITERION.** The stopping condition is EXHAUSTION OF
EVIDENCE, not consensus. Once both sides have put one round of MEASURED proof on the table, an unresolved
divergence is a legitimate terminal state - hand your human both positions with their evidence.

- **Round cap:** `MAX_NEGOTIATE_ROUNDS = 2` (tunable). Round 1: you present the measurement, the peer
  counters. Round 2: you attempt a synthesis taking the best of both.
- **Impasse (no forced synthesis):** if not converged at the cap, declare **IMPASSE**, document both
  positions plainly in-chat with their measured support, and hand your human the tie-break. **Do not
  fabricate agreement**, and do not concede a measured position to reach the stopping condition.
- **Straight to your human with NO negotiation at all:** a material design fork, a security boundary, or
  an architectural axiom. The moment the two of you disagree on a load-bearing shape, the human decides.
- **Manual backstop:** your human can type "negotiate with agy" to trigger this protocol on any observed
  disagreement, regardless of what token was emitted.

🔴 **AN IMPASSE EMITS NO NEW TOKEN. Do not invent one.** This discipline's terminal tokens are
`[VERDICT: EXHAUSTIVE]`, `[VERDICT: GAPS FOUND]` and `[VERDICT: agy-required-but-unreachable]`, and that
list is enforced mechanically by `scripts/check-agy-discipline-skills.ps1` - a `[VERDICT: NEGOTIATE]`
here would fail the driver's own contract check. **An impasse is a per-finding disposition, not a round
outcome:** the disputed finding resolves to `UNVERIFIED-ACCEPTED: <finding>` once your human has taken
the tie-break, and the ROUND still terminates on its own existing token. `UNVERIFIED-ACCEPTED` exists in
the AGY-SCOPE set for exactly this - "neither provable nor refutable, and the owner accepted the risk".

**Why agreement is the wrong criterion, measured:** across an 8-round capstone roughly 60% of this peer's
findings were confirmed and 40% were refuted - a fabricated census string, a `chmod 000` trigger that does
not exist on this platform, an ARG_MAX ceiling that measured fine at 12000 files. An agreement requirement
means burning rounds arguing the peer out of those, or conceding to move on. Worse, under pressure to
agree two models will synthesise a FABRICATED COMPROMISE that neither originally proposed and neither has
measured.
```

- [ ] **Step 2: Add the same section to `adversarial-panel-review/SKILL.md`**

Insert before its `## Disposition of findings (AGY-SCOPE)` heading. Use the identical text from Step 1 **except** the first paragraph, which names this discipline's own material class:

```markdown
Engage negotiation ONLY on a **material** disagreement - one that changes the artifact's correctness,
safety, contract behaviour or completeness. Style, naming and trivia never qualify; you yield on those.
```

⚠ **This skill already carries a one-substantive-counter-turn rule in its Step 3.** Do not duplicate it — add a sentence there pointing at this section as the bounded escalation when one turn does not settle a material disagreement, rather than leaving two protocols that a reader must reconcile.

- [ ] **Step 3: Mirror both to the classic half and prove byte-identity**

```bash
cp clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md clavity-classic/plugin/skills/agy-test-audit/SKILL.md
cp clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md clavity-classic/plugin/skills/adversarial-panel-review/SKILL.md
for s in agy-test-audit adversarial-panel-review; do
  cmp "clavity-dotnet/plugin/skills/$s/SKILL.md" "clavity-classic/plugin/skills/$s/SKILL.md" && echo "IDENTICAL $s"
done
bash scripts/check-seed-artifacts-synced.sh; echo "exit=$?"
```

Expected: `IDENTICAL agy-test-audit`, `IDENTICAL adversarial-panel-review`, `exit=0`.

- [ ] **Step 4: Verify the count actually moved**

```bash
for s in agy-first agy-capstone agy-test-audit adversarial-panel-review; do
  printf '%-28s %s\n' "$s" "$(grep -c 'AGY-NEGOTIATE' clavity-dotnet/plugin/skills/$s/SKILL.md)"
done
```

Expected: all four now non-zero.

- [ ] **Step 5: Commit**

```bash
git add clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md clavity-classic/plugin/skills/agy-test-audit/SKILL.md clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md clavity-classic/plugin/skills/adversarial-panel-review/SKILL.md
git commit -m "feat(s25): bounded negotiation in the two review skills that lacked one"
```

---

## Task 6: Pin `AGY-NEGOTIATE` mechanically

**Files:**
- Modify: `scripts/check-agy-discipline-skills.ps1`
- Modify: `scripts/tests/check-agy-discipline-skills.Tests.ps1`

**A rule with no implementation is worse than no rule.** Task 5 ships prose; this task makes its absence detectable.

⚠ **VERIFIED CONSTRAINT — read before choosing where to put the check.** `check-agy-discipline-skills.ps1` enrols `$skills = @('agy-first', 'agy-capstone', 'agy-test-audit')`. **`adversarial-panel-review` is deliberately NOT in that list** — the script's own comment records why: it "has 69 non-ASCII chars and no marker constant". It is instead covered by `$disciplineNames = $skills + @('adversarial-panel-review')`, which the 13b discipline-mandate check already uses. **Add the negotiate check against `$disciplineNames`, not `$skills`** — putting it in `$skills` would either miss the panel skill or force a non-ASCII fight this task does not need.

- [ ] **Step 1: Write the failing test**

Add this `Describe` to `scripts/tests/check-agy-discipline-skills.Tests.ps1`, following the file's existing mutant idiom (it already loads the real source and does a `.Replace(...)` to prove non-vacuity — copy that shape from the `$disciplineNames` mutants at lines ~707 and ~740):

```powershell
Describe 'AGY-NEGOTIATE is pinned across all four disciplines' {

    It 'passes on the real tree' {
        $r = & pwsh -NoProfile -File $script:RealChecker 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because 'all four skills carry AGY-NEGOTIATE after section 25'
    }

    It 'FAILS when a discipline loses its AGY-NEGOTIATE section' {
        # Non-vacuity. Strip the section from ONE skill in a sandbox copy and prove the linter
        # names that skill. A linter that passes with the section gone is certifying nothing.
        # 🔴 COPY ONLY WHAT THE LINTER READS. AGY-AFTER round 1 caught an earlier draft doing
        # `Copy-Item $script:RepoRoot -Recurse`: MEASURED, this working tree is 18G, with
        # clavity-classic/target at 2.6G and .git at 95M. A whole-tree copy inside a Pester test
        # thrashes the disk, hits file locks on live build artifacts, and turns a string-replacement
        # test into the slowest thing in the suite. The linter takes -Root, so give it a minimal tree.
        $sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("negpin-" + [guid]::NewGuid().ToString('N'))
        try {
            foreach ($d in @('agy-first','agy-capstone','agy-test-audit','adversarial-panel-review')) {
                $dest = Join-Path $sandbox "clavity-dotnet/plugin/skills/$d"
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
                Copy-Item (Join-Path $script:RepoRoot "clavity-dotnet/plugin/skills/$d/SKILL.md") $dest -Force
            }
            New-Item -ItemType Directory -Path (Join-Path $sandbox 'scripts') -Force | Out-Null
            Copy-Item (Join-Path $script:RepoRoot 'scripts/check-agy-discipline-skills.ps1') (Join-Path $sandbox 'scripts') -Force
            $victim = Join-Path $sandbox 'clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md'
            (Get-Content $victim -Raw).Replace('## AGY-NEGOTIATE', '## Something Else Entirely') |
                Set-Content $victim -NoNewline
            $out = & pwsh -NoProfile -File (Join-Path $sandbox 'scripts/check-agy-discipline-skills.ps1') 2>&1 | Out-String
            $LASTEXITCODE | Should -Not -Be 0
            $out | Should -Match 'agy-test-audit'
            $out | Should -Match 'AGY-NEGOTIATE'
        } finally { Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
```

⚠ `$script:RealChecker` and `$script:RepoRoot` are this test file's existing helpers — **read the file's `BeforeAll` and use whatever names it already defines** rather than introducing new ones.

- [ ] **Step 2: Run to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester scripts/tests/check-agy-discipline-skills.Tests.ps1"`

Expected: FAIL — the linter does not yet check for the section, so the mutant arm passes when it should fail.

- [ ] **Step 3: Add the check to `scripts/check-agy-discipline-skills.ps1`**

Add near the other per-discipline loops, using `$disciplineNames`:

```powershell
# ROADMAP section 25: every review-only discipline carries a bounded negotiation protocol. Checked
# against $disciplineNames, NOT $skills - adversarial-panel-review is excluded from $skills on purpose
# (non-ASCII content, no marker constant) but must still carry this section.
foreach ($d in $disciplineNames) {
    $p = Join-Path $Root "clavity-dotnet/plugin/skills/$d/SKILL.md"
    if (-not (Test-Path $p)) { Fail "agy-discipline-skills: missing SKILL.md for '$d'"; continue }
    $text = Get-Content -Raw $p
    if ($text -notmatch '(?m)^##\s+AGY-NEGOTIATE') {
        Fail "agy-discipline-skills: '$d' has no '## AGY-NEGOTIATE' section (ROADMAP section 25)."
    }
    if ($text -notmatch 'MAX_NEGOTIATE_ROUNDS') {
        Fail "agy-discipline-skills: '$d' has an AGY-NEGOTIATE section with no round cap constant."
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester scripts/tests/check-agy-discipline-skills.Tests.ps1"`

Expected: green, and the previously-failing mutant arm now names `agy-test-audit`.

- [ ] **Step 5: Run the full gate set**

```bash
pwsh -NoProfile -File scripts/check-agy-discipline-skills.ps1; echo "exit=$?"
bash scripts/check-seed-artifacts-synced.sh; echo "exit=$?"
pwsh -NoProfile -Command "Invoke-Pester scripts/tests/plugin-hooks-payload.Tests.ps1"
```

Expected: both `exit=0`, payload suite green.

- [ ] **Step 6: Commit**

```bash
git add scripts/check-agy-discipline-skills.ps1 scripts/tests/check-agy-discipline-skills.Tests.ps1
git commit -m "test(s25): pin AGY-NEGOTIATE across all four disciplines"
```

---

## Task 7: Correct the ROADMAP and close both sections

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md` (§24 header ~line 2155; §25 header ~line 2199; the stale sentence at **line 2206** — **re-read, Task 0 through 6 do not touch this file but line numbers shift with any edit**)

- [ ] **Step 1: Fix the factually wrong sentence**

At line 2206 the text currently reads:

> positions documented. **It exists in exactly one skill.** `agy-first`, `agy-test-audit` and
> `adversarial-panel-review` each require one substantive counter-turn but have no loop and no impasse
> protocol.

Replace with:

```markdown
positions documented. 🔴 **CORRECTED 2026-09-04, BEFORE THE PLAN WAS WRITTEN: this entry originally said
"it exists in exactly one skill" and listed `agy-first` among those lacking it. Both claims were wrong.**
MEASURED across both plugin halves with `grep -c 'AGY-NEGOTIATE'`: `agy-first` = 2, `agy-capstone` = 3,
`agy-test-audit` = 0, `adversarial-panel-review` = 0. `agy-first/SKILL.md:162-175` carries a COMPLETE
protocol - material-only trigger, `MAX_NEGOTIATE_ROUNDS = 2` marked tunable, impasse with a human
tie-break, and a "negotiate with agy" manual backstop. **The real scope was TWO skills, not three**, and
`agy-first`'s wording - not the capstone's - was the model the fix lifted.
```

- [ ] **Step 2: Mark both sections shipped — WITH their closing SHAs**

🔴 **DO NOT PASTE THESE LITERALLY.** AGY-AFTER round 1 (Axiom Breaker) caught an earlier draft handing a literal SHA-less string to Step 2 while Step 4 asserted the gate rejects exactly that — a literal executor would have pasted it and become stuck. **First collect the real SHAs**, then substitute them.

⚠ **`<base-sha>` IS THE PLAN'S OWN STARTING COMMIT, and AGY-AFTER round 2 (Novice Executor) caught that nothing here ever defined it** — a literal executor running the line below verbatim gets `fatal: ambiguous argument '<base-sha>..HEAD'`. **It is `9ac45ed`** — the commit that folded AGY-AFTER round 1, immediately before Task 1 begins. Resolve it mechanically rather than trusting that value if any commit landed since:

```bash
BASE=$(git log --oneline --all --grep='fold AGY-AFTER round 1' -1 --format=%h)
echo "base=$BASE"
git log --oneline "$BASE..HEAD"
```

Change the §24 header's trailing status from `▶ **OWNER ACCEPTED 2026-08-31, not yet planned**` to the following, with `<TASK1-SHA>` and `<TASK3-SHA>` replaced by the actual 7-char SHAs from that log:

```
✅ **SHIPPED 2026-09-04** (`<TASK1-SHA>` the trigger · `<TASK3-SHA>` the stamp) — isolation RECORDED, not gated (owner ruling 2026-09-04)
```

Change the §25 header's trailing status likewise, substituting the Task 5 and Task 6 SHAs:

```
✅ **SHIPPED 2026-09-04** (`<TASK5-SHA>` the sections · `<TASK6-SHA>` the pin) — `AGY-NEGOTIATE` in `agy-test-audit` + `adversarial-panel-review`
```

⚠ **Every backticked SHA must be a commit that actually exists** — Step 4's checker verifies exactly that, so a placeholder left unsubstituted will fail the gate loudly rather than silently shipping a false claim.

- [ ] **Step 3: Close §24's open question in the section body**

Append to §24, replacing its `**Open, for the owner at plan time - the STRUCTURAL INDEPENDENCE PROBLEM.**` paragraph's trailing "Owner deferred this to plan time (2026-08-31). Decide whether..." sentence:

```markdown
✅ **RULED 2026-09-04 — RECORD ISOLATION, DO NOT GATE ON IT.** The consult is mechanically mandatory; the
isolation property is recorded and surfaced, never blocking. `agy-mark.sh stamp` writes one append-only
row per consult to `.clavity/agy-marks/consults.log` marking `SHARED-CONTEXT` or `ISOLATED`, and the owner
sees it at GREEN adjudication and may demand a fresh-cascade re-review.

**The peer recommended human-in-the-loop structural separation and was overruled, on mechanism.** Its
evidence for isolation was sound and was verified rather than taken on trust - the sequencing spec records
this same peer attacking a §25 refinement it had itself argued for in an earlier consult, having no memory
of its own contribution in a fresh cascade. But it conceded on measurement that **no MCP tool can start a
cascade**: `Clavity.Mcp/McpTools.cs` exposes exactly three, all addressing the ACTIVE conversation, and
`RunAsync` carries an explicit `waiting_for_human` path for when agy has no conversation at all. Structural
separation is therefore a human action, not a scriptable one, and a rule that blocks on it would recreate
the skip-pressure §24 exists to remove. ⚠ `clavity-classic/src/tmux.rs:224-262` DOES expose `send_keys`
and `kill-session`, so lifecycle control exists on that half - **the byte-identical-pair constraint is what
forces the rule to the weaker transport.**
```

- [ ] **Step 4: Verify the ROADMAP claims checker still passes**

```bash
pwsh -NoProfile -File scripts/check-roadmap-claims.ps1; echo "exit=$?"
```

Expected: `exit=0`.

✅ **VERIFIED 2026-09-04 — it DOES check shas, so this is not optional.** `check-roadmap-claims.ps1` asserts that *every backticked 7–40 hex sha on a line also carrying a closure token actually exists*, and its header records the lesson it was built from: **"whoever closes an item writes its closing sha in the same commit."** So both `✅ SHIPPED` headers above **must name real commit SHAs** from Tasks 1–6, and this checker will catch a fabricated or mistyped one. Collect them with `git log --oneline <base-sha>..HEAD` before writing the headers.

- [ ] **Step 5: Commit**

```bash
git add clavity-dotnet/ROADMAP.md
git commit -m "docs(s24,s25): close both sections, and correct s25's stale premise"
```

---

## Task 8: Full-gate verification before declaring the plan done

- [ ] **Step 1: Run every gate this plan touches**

```bash
pwsh -NoProfile -File scripts/check-agy-discipline-skills.ps1; echo "skills=$?"
pwsh -NoProfile -File scripts/check-roadmap-claims.ps1;        echo "roadmap=$?"
bash scripts/check-seed-artifacts-synced.sh;                   echo "synced=$?"
pwsh -NoProfile -Command "Invoke-Pester scripts/tests/plugin-hooks-payload.Tests.ps1"
pwsh -NoProfile -Command "Invoke-Pester scripts/tests/check-capstone-new-code.Tests.ps1"
pwsh -NoProfile -Command "Invoke-Pester scripts/tests/agy-mark-stamp.Tests.ps1"
pwsh -NoProfile -Command "Invoke-Pester scripts/tests/check-agy-discipline-skills.Tests.ps1"
```

⚠ **Run the Pester suites ONE AT A TIME.** This machine is cap-adjacent; two Pester suites at once has previously produced an aborted run that reads like a pass.

Expected: all three `=0`, and every suite reporting an explicit `Tests Passed: N, Failed: 0`.

- [ ] **Step 2: Confirm all four pairs are still byte-identical**

```bash
for s in agy-first agy-capstone agy-test-audit adversarial-panel-review; do
  cmp -s "clavity-dotnet/plugin/skills/$s/SKILL.md" "clavity-classic/plugin/skills/$s/SKILL.md" \
    && echo "IDENTICAL $s" || echo "DRIFT $s"
done
cmp -s clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh \
  && echo "IDENTICAL agy-mark.sh" || echo "DRIFT agy-mark.sh"
```

Expected: five `IDENTICAL` lines, no `DRIFT`.

- [ ] **Step 3: Confirm nothing under `.clavity/` was staged at any point**

```bash
git log --stat <base-sha>..HEAD | grep -c '\.clavity/'
```

Expected: `0`.

---

## After the plan: the gates that still apply

1. **AGY-AFTER** on this plan needs `adversarial-panel-review`. ⚠ **That skill is currently degraded**: the MCP server runs an installed exe dated Aug 31 that predates §29a, so its token table still expects `GREEN` and a correct `PANEL VERDICT` reply is reported as `[13b] TRUNCATED REPLY`. **A flagged reply is INCOMPLETE, never empty** — recover it with `agy_look` or ONE re-ask, then halt and ask the owner. The owner ruled 2026-09-04 to proceed and decide at the gate rather than publish a new binary first.
2. **AGY-CAPSTONE** on the committed range, rounds until GREEN. Note the irony and use it: this plan's own §24 trigger will fire on Task 1 and Task 3, which add new files and a new subcommand.
3. **AGY-TEST-AUDIT** after the capstone is green.
4. **Do not push.** The owner owns every push.

---

## Self-review — the exhaustiveness audit

**Spec coverage.** The sequencing spec's Phase 2 requirements map as follows: §24's mechanical trigger → Task 1; §24's pause-don't-abort → Task 4; §24's deferred structural-independence question → Task 7 Step 3 (closed, not inherited); §25's negotiation discipline in the skills lacking it → Task 5; §25's "ship the mechanism, agreement is not the criterion" refinement → Task 5's section text; the spec's instruction that Phase 2 must *state whether each round runs under the pre-change or post-change rules* → **carried as a live obligation into the "After the plan" section**, because it governs the capstone rounds rather than any file this plan edits.

**Placeholder scan.** No `TBD`, no "handle edge cases", no "similar to Task N". Every code step carries its code; every command carries its expected output.

**Gaps closed in-document:** the `$marks_dir` / `$script:RealChecker` / `$script:RepoRoot` identifiers are flagged as *read the file and use the existing name* rather than asserted, because they were not verified at authoring time.

**Gaps flagged, NOT closed — resolve at execution:**
- **The exact `justfile` recipe name and list syntax** (Task 2). Not verified at authoring time; Task 2 Step 1 greps for it before editing.
- **Whether `check-roadmap-claims.ps1` requires a commit SHA on a `✅ SHIPPED` section** (Task 7 Step 4). The step states the fallback if it does.
- **Rule C's 5-line threshold** is a judgement embedded in a mechanical rule. It is checked against the three historical cases in Task 1's fixtures, but it is the one number here that a future round may need to re-tune; it is named rather than hidden so re-tuning is a visible decision.
- **§33's open question is NOT in scope here** and must not be quietly folded in: whether `TerminalToken`'s `Ordinal` and `DisciplineContract`'s `OrdinalIgnoreCase` mismatch is deliberate is a separate tracked section.

# AGENTS.md Canonical + Leak Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the root `AGENTS.md` the single source of shared repo facts (imported by `CLAUDE.md`), scope its
imperatives to change-making sessions, and add a gate that fails when an agent rule file references a path
`.antigravityignore` hides.

**Architecture:** One PowerShell gate script (`scripts/check-agent-rules-ignore.ps1`) built as dot-sourceable
functions plus a main guard, the repo's existing pattern. It lists tracked rule files, extracts and normalises path
references, and asks `git check-ignore` (in a throwaway repo whose `.gitignore` is a copy of `.antigravityignore`)
which ones are hidden. Wiring follows the existing `check-*` family: `just` recipe, lefthook pre-push glob, CI step.
Then the two instruction files are restructured.

**Tech Stack:** PowerShell (`pwsh` 7; header `#requires -Version 5.1` as the sibling scripts), Pester 5, git, just,
lefthook, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-14-agents-md-canonical-design.md` (committed 3b47ad7c). Its section
"Leak gate" is the oracle for every extraction and normalisation rule below; where this plan and the spec
disagree, the spec wins and the conflict is reported.

## Global Constraints

- Branch `feat/agents-md`. Never push, never `just release`, never tag `clavity-v*` (owner-gated).
- Every new `.ps1` starts with the licence header block exactly as `scripts/check-user-facing-docs.ps1:1-7`, then
  `#requires -Version 5.1` and `Set-StrictMode -Version Latest` as that file's lines 9 and 20.
- Repo root in a script = `Split-Path -Parent $PSScriptRoot` (as `scripts/check-user-facing-docs.ps1:22`); every git
  call uses `git -C <root>`.
- Suites use `$TestDrive` for scratch (no `GetTempPath()` / `$env:TEMP` in a suite: `scripts/tests/test-temp-discipline.Tests.ps1`).
- Commits: Conventional Commits, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Pre-push jobs must stay seconds-range (`lefthook.yml` header); use a YAML-array `glob:` as `lefthook.yml:46-53`.
- `AGENTS.md` must never name a path `.antigravityignore` matches (the gate enforces it).

## Review Focus

1. A hidden path inside a Markdown table cell (`| ... clavity-dotnet/pairing/ ... |`) - expected: flagged. Test in Task 1.
2. A hidden path inside an HTML comment (`<!-- see .clavity/seams -->`) - expected: flagged. Test in Task 1.
3. A rule file saved with CRLF line endings - expected: flagged, with the right line number. Test in Task 1.
4. A code span holding a shell pipeline with flags (`` `git log --oneline | head -3` ``) - expected: no git error, no hit. Test in Task 1.
5. A rule file with no trailing newline whose last line holds a hidden path - expected: flagged. Test in Task 1.

---

### Task 1: The leak gate script and its suite

**Files:**
- Create: `scripts/check-agent-rules-ignore.ps1`
- Create (tests are already written below - implement until they pass): `scripts/tests/check-agent-rules-ignore.Tests.ps1`
- Modify: `justfile:106` - append `'scripts/tests/check-agent-rules-ignore.Tests.ps1'` to the `test-scripts-fast` list
- Modify: `scripts/README.md` - insert a row directly above line 26 (`check-doc-stubs.ps1`)

**Interfaces:**
- Produces (dot-sourceable; main runs only when `$MyInvocation.InvocationName -ne '.'`, as `scripts/check-user-facing-docs.ps1:167-178`):
  - `Get-AgentRuleFiles([string]$RepoRoot) -> string[]` - repo-relative, `/`-separated tracked paths: basename
    `AGENTS.md` or `GEMINI.md` at any depth, or `*.md` directly under `<dir>/rules/` where `<dir>` is `.agents`,
    `.agent`, `_agents` or `_agent` at any depth. Source: `git -C $RepoRoot ls-files -z`.
  - `Get-RuleReferences([string[]]$Lines) -> pscustomobject[]` with properties `Line` [int, 1-based], `Text`
    [string, raw token], `Kind` [string: `code`, `fence`, `link`, `include`, `prose`]. Extraction per spec
    "References extracted, per line"; `include` = destination of `@[label](path)`.
  - `ConvertTo-CandidatePath([string]$Text, [string]$RepoRoot, [string]$FileDir) -> string[]` - 0, 1 or 2
    repo-relative `/`-separated paths (forms A and B, deduplicated), per spec "Normalisation, in order"; `$FileDir`
    is the rule file's repo-relative directory (`''` at the root).
  - `Find-IgnoredPath([string]$RepoRoot, [string[]]$Paths, [string]$ScratchParent) -> hashtable` - key = the
    candidate path as given, value = `[pscustomobject]@{ IgnoreLine = [int]; Pattern = [string] }`, ONLY for
    non-negated matches. Tests each path as given and with a trailing `/`. One git process. Throws (message names
    the cause) when `.antigravityignore` is missing, git is absent, or git exits other than 0/1. Temp repo under
    `$ScratchParent`, removed in `finally`.
  - `Invoke-AgentRulesIgnoreCheck([string]$RepoRoot, [string]$ScratchParent = [System.IO.Path]::GetTempPath()) ->
    pscustomobject` with `ExitCode` [int 0|1], `Hits` [string[]], `Failures` [string[]], `FileCount` [int],
    `ReferenceCount` [int]. A hit string is exactly
    `"<file>:<line>  <reference>  ->  .antigravityignore:<IgnoreLine>:<Pattern>"`, where `<reference>` is the
    candidate path that matched; hits are deduplicated by (file, line, candidate path), since one token can be
    both a code-span and a prose token. Follows includes recursively
    (visited set); a missing include target is a `Failures` entry. A thrown `Find-IgnoredPath` error becomes a
    `Failures` entry (exit 1), never a pass.
  - Main output: on success exactly `agent rules ok (<FileCount> rule files, <ReferenceCount> references, none hidden by .antigravityignore)`
    and exit 0; otherwise `agent-rules-ignore gate FAILED:` then one `  - <hit or failure>` line each, exit 1.

- [ ] **Step 1: Write the suite file below verbatim**

`scripts/tests/check-agent-rules-ignore.Tests.ps1` (licence header block first, as every suite):

```powershell
BeforeAll {
    . ([System.IO.Path]::Combine($PSScriptRoot, '..', 'check-agent-rules-ignore.ps1'))
    $script:Ignore = "target/`n.clavity/`nclavity-dotnet/pairing/`ndocs/hidden-plan.md`n*.log`n!keep.log`ncoverage/`ncafé/`n"
    function New-RuleRepo {
        param([hashtable]$Files, [string]$Ignore = $script:Ignore, [switch]$NoIgnore)
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        git -C $repo init -q --template= 2>$null
        if (-not $NoIgnore) { [IO.File]::WriteAllText((Join-Path $repo '.antigravityignore'), $Ignore) }
        foreach ($rel in $Files.Keys) {
            $abs = Join-Path $repo $rel
            New-Item -ItemType Directory -Path (Split-Path $abs -Parent) -Force | Out-Null
            [IO.File]::WriteAllText($abs, $Files[$rel])
        }
        git -C $repo add -A 2>$null
        return $repo
    }
    function Invoke-Check([string]$repo) { Invoke-AgentRulesIgnoreCheck -RepoRoot $repo -ScratchParent $TestDrive }
}

Describe 'Invoke-AgentRulesIgnoreCheck' {
    It 'passes a clean file and reports the census' {
        $r = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "Run ``just test`` in ``scripts/``.`n" })
        $r.ExitCode | Should -Be 0; $r.FileCount | Should -Be 1; $r.ReferenceCount | Should -BeGreaterThan 0
    }
    It 'passes with zero rule files and FileCount 0' {
        $r = Invoke-Check (New-RuleRepo @{ 'README.md' = 'x' }); $r.ExitCode | Should -Be 0; $r.FileCount | Should -Be 0
    }
    It 'flags a hidden path in a code span, with file, line and pattern' {
        $r = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "ok`nsee ``clavity-dotnet/pairing/README.md```n" })
        $r.ExitCode | Should -Be 1
        $r.Hits[0] | Should -BeLike 'AGENTS.md:2  clavity-dotnet/pairing/README.md  ->  .antigravityignore:3:clavity-dotnet/pairing/'
    }
    It 'flags a hidden path inside a fenced block' {
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "``````bash`ncat .clavity/x.md`n```````n" })).ExitCode | Should -Be 1
    }
    It 'flags a hidden link target, a bare prose path and a dot-folder named in prose' {
        foreach ($t in @('[p](clavity-dotnet/pairing/)', 'look in clavity-dotnet/pairing for it', 'never open .clavity please')) {
            (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$t`n" })).ExitCode | Should -Be 1 -Because $t
        }
    }
    It 'flags a directory named without its trailing slash' {
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "``clavity-dotnet/pairing```n" })).ExitCode | Should -Be 1
    }
    It 'flags every normalisation bypass form' {
        foreach ($t in @('[a](docs/hidden-plan.md#L10)', '[a](docs/hidden-plan.md%23L10)', '[a](docs/hidden-plan.md?x=1)',
                         '`clavity-dotnet\pairing\README.md`', '[a](/clavity-dotnet/pairing/)', '[a](file:///clavity-dotnet/pairing/)',
                         '[a](file://localhost/clavity-dotnet/pairing/)', '[a](docs/hidden%2Dplan.md)',
                         '[a](clavity-dotnet/pairing/README.md "Title")', 'x](clavity-dotnet/pairing/README.md',
                         '`tool --out=clavity-dotnet/pairing/x`', '<a href="clavity-dotnet/pairing/">x</a>',
                         '`Clavity-Dotnet/Pairing/`')) {
            (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$t`n" })).ExitCode | Should -Be 1 -Because $t
        }
    }
    It 'makes an absolute in-repo path repo-relative, including a differently-cased Windows drive letter' {
        $repo = New-RuleRepo @{ 'AGENTS.md' = 'placeholder' }
        $abs = (Join-Path $repo 'clavity-dotnet/pairing/x') -replace '\\', '/'
        if ($abs -match '^[A-Za-z]:') { $abs = $abs.Substring(0,1).ToLower() + $abs.Substring(1) }
        ConvertTo-CandidatePath -Text $abs -RepoRoot $repo -FileDir '' | Should -Contain 'clavity-dotnet/pairing/x'
    }
    It 'resolves a relative link in a nested rule file against that file''s directory' {
        (Invoke-Check (New-RuleRepo @{ 'clavity-dotnet/AGENTS.md' = "[p](pairing/)`n" })).ExitCode | Should -Be 1
    }
    It 'scans nested GEMINI.md and every rules-folder spelling' {
        foreach ($f in @('sub/GEMINI.md', '.agents/rules/a.md', '.agent/rules/a.md', '_agents/rules/a.md', '_agent/rules/a.md')) {
            (Invoke-Check (New-RuleRepo @{ $f = "``.clavity/x```n" })).ExitCode | Should -Be 1 -Because $f
        }
    }
    It 'follows an include, flags a hidden path inside it, fails on a missing target, and survives a cycle' {
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "@[more](docs/more.md)`n"; 'docs/more.md' = "``.clavity/x```n" })).ExitCode | Should -Be 1
        $miss = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "@[more](docs/nope.md)`n" })
        $miss.ExitCode | Should -Be 1; ($miss.Failures -join ' ') | Should -Match 'docs/nope.md'
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "@[b](b.md)`n"; 'b.md' = "@[a](AGENTS.md)`n" })).ExitCode | Should -Be 0
    }
    It 'does not fail on a missing ORDINARY link target' {
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "[x](docs/nope.md)`n" })).ExitCode | Should -Be 0
    }
    It 'drops http URLs, repo-escaping paths, empty tokens and comment slashes without a git error' {
        $t = "[w](https://example.com/clavity-dotnet/pairing/) ``../../outside/x```n" + '```c' + "`n// note`n/* block */`n" + '```' + "`n"
        $r = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = $t }); $r.ExitCode | Should -Be 0; $r.Failures | Should -BeNullOrEmpty
    }
    It 'does not flag a prose word equal to a bare pattern, nor a file re-included by a negation' {
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "Raise coverage. Keep ``keep.log```n" })).ExitCode | Should -Be 0
    }
    It 'ignores the user''s global git excludes' {
        $cfg = Join-Path $TestDrive 'gcfg'; $xf = Join-Path $TestDrive 'gexcl'
        [IO.File]::WriteAllText($xf, "allowed/`n"); [IO.File]::WriteAllText($cfg, "[core]`n`texcludesFile = $($xf -replace '\\','/')`n")
        $saved = $env:GIT_CONFIG_GLOBAL
        try { $env:GIT_CONFIG_GLOBAL = $cfg
              (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "``allowed/x```n" })).ExitCode | Should -Be 0 }
        finally { if ($null -eq $saved) { Remove-Item Env:GIT_CONFIG_GLOBAL -ErrorAction SilentlyContinue } else { $env:GIT_CONFIG_GLOBAL = $saved } }
    }
    It 'reports a non-ASCII hidden path' {
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "``café/notes.md```n" })).ExitCode | Should -Be 1
    }
    It 'fails closed when .antigravityignore is missing' {
        $r = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "x`n" } -NoIgnore)
        $r.ExitCode | Should -Be 1; ($r.Failures -join ' ') | Should -Match 'antigravityignore'
    }
    It 'gives the same result when run from a subdirectory' {
        $repo = New-RuleRepo @{ 'AGENTS.md' = "``.clavity/x```n"; 'sub/keep.txt' = 'k' }
        Push-Location (Join-Path $repo 'sub'); try { (Invoke-Check $repo).ExitCode | Should -Be 1 } finally { Pop-Location }
    }
    # Review Focus rows
    It 'flags a hidden path in a table cell and in an HTML comment' {
        foreach ($t in @('| a | clavity-dotnet/pairing/ | b |', '<!-- see .clavity/seams -->')) {
            (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$t`n" })).ExitCode | Should -Be 1 -Because $t
        }
    }
    It 'reports the right line number in a CRLF file' {
        $r = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "a`r`nb`r`n``.clavity/x```r`n" })
        $r.Hits[0] | Should -BeLike 'AGENTS.md:3  *'
    }
    It 'treats a shell pipeline with flags as harmless and catches a hidden path on a last line with no newline' {
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "``git log --oneline | head -3```n" })).ExitCode | Should -Be 0
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "x`n``.clavity/x``" })).ExitCode | Should -Be 1
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-agent-rules-ignore.Tests.ps1 -Output Detailed -CI"`
Expected: FAIL - the dot-source in `BeforeAll` cannot find `check-agent-rules-ignore.ps1`.

- [ ] **Step 3: Implement `scripts/check-agent-rules-ignore.ps1`** with the five functions and main guard in the
Interfaces block. Header comment states WHY (agy loads these files as always-on rules; `.antigravityignore` cannot
hide a rule file - spec facts 1-2) and the known limit (paths, not prose). Matching runs exactly the spec's command:
`git -C <tmp> -c core.excludesFile=<empty file> -c core.ignoreCase=true check-ignore --no-index --stdin -z -v`
after `git init -q --template= <tmp>`; input NUL-terminated; output parsed as 4-field NUL records; a pattern
starting with `!` is not a hit.

- [ ] **Step 4: Run the suite to verify it passes**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-agent-rules-ignore.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 21, Failed: 0`.

- [ ] **Step 5: Register and inventory the suite and script**

Append the suite to `test-scripts-fast` (`justfile:106`). Insert above `scripts/README.md:26`:
`` | `check-agent-rules-ignore.ps1` | Fail if an agent rule file the agy peer loads (AGENTS.md, GEMINI.md, rules folders, their includes) references a path `.antigravityignore` hides | `just check-agent-rules-ignore` (lefthook pre-push; CI `ci-scripts.yml`) | ``
Then run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/scripts-readme-inventory.Tests.ps1,scripts/tests/scripts-strictmode.Tests.ps1,scripts/tests/test-temp-discipline.Tests.ps1 -Output Detailed -CI"`
Expected: `Failed: 0`. (`test-suite-registration.Tests.ps1` will still fail on the missing `_partition.md` row
until Task 2 Step 4 - expected and stated, not fixed here.)

- [ ] **Step 6: Commit**

```bash
git add scripts/check-agent-rules-ignore.ps1 scripts/tests/check-agent-rules-ignore.Tests.ps1 justfile scripts/README.md
git commit -m "feat(scripts): gate agent rule files against .antigravityignore"
```

---

### Task 2: Wire the gate in and record its runtime

**Files:**
- Modify: `justfile` - new recipe directly after `check-doc-stubs` (`justfile:34-35`)
- Modify: `lefthook.yml` - new `pre-push` job directly after `control-bytes` (`lefthook.yml:46-53`)
- Modify: `.github/workflows/ci-scripts.yml` - new step directly after "Dangling-consumer gate" (`:108-114`)
- Modify: `scripts/tests/_partition.md` - new row directly above `check-agy-discipline-skills.Tests.ps1` (line 767)

**Interfaces:**
- Consumes: `scripts/check-agent-rules-ignore.ps1` main (exit 0/1) from Task 1.

- [ ] **Step 1: Add the recipe** (comment line directly above it, as `just --list` shows the last comment line):

```
# Fail if an agent rule file the agy peer loads references a path .antigravityignore hides.
check-agent-rules-ignore:
    pwsh -NoProfile -File scripts/check-agent-rules-ignore.ps1
```

- [ ] **Step 2: Add the lefthook job and the CI step**

lefthook job `agent-rules-ignore`, `run: just check-agent-rules-ignore`, YAML-array `glob:` with exactly:
`AGENTS.md`, `**/AGENTS.md`, `GEMINI.md`, `**/GEMINI.md`, `.agents/**`, `**/.agents/**`, `.agent/**`,
`**/.agent/**`, `_agents/**`, `**/_agents/**`, `_agent/**`, `**/_agent/**`, `.antigravityignore`,
`scripts/check-agent-rules-ignore.ps1`. Comment: CI is the complete trigger; this glob cannot see an edit to an
included file elsewhere. CI step `name: Agent rules vs .antigravityignore gate`, `shell: pwsh`,
`run: pwsh -File scripts/check-agent-rules-ignore.ps1`, with a one-line comment naming the spec.

- [ ] **Step 3: Verify the wiring**

Run: `just check-agent-rules-ignore` - Expected: `agent rules ok (1 rule files, <N> references, none hidden by .antigravityignore)`, exit 0.
Run: `lefthook run pre-push --file AGENTS.md` (lefthook 2.1.17 spells it `--file`) - Expected: the
`agent-rules-ignore` job runs and passes.

- [ ] **Step 4: ORCHESTRATOR ONLY - measure the suite and add the `_partition.md` row**

Per the timing discipline (never a subagent): kill any stale Pester run, launch backgrounded, make no tool call
until it completes, run twice, quote the warm figure and the range.
Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-agent-rules-ignore.Tests.ps1 -CI"` twice.
Row format as line 767: `check-agent-rules-ignore.Tests.ps1   <warm>s   21 tests   <- FAST, NEW 2026-11-14. Two runs <a>s / <b>s; background load uncontrolled.`
Then run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1 -CI"` - Expected: `Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add justfile lefthook.yml .github/workflows/ci-scripts.yml scripts/tests/_partition.md
git commit -m "ci: run the agent-rules-ignore gate in pre-push and CI"
```

---

### Task 3: Restructure AGENTS.md, import it from CLAUDE.md, and accept

**Files:**
- Modify: `AGENTS.md` (committed draft, 91 lines)
- Modify: `CLAUDE.md` (37 lines)

**Interfaces:**
- Consumes: `just check-agent-rules-ignore` (Task 2).

- [ ] **Step 1: Restructure `AGENTS.md`** into exactly three top-level parts in this order, per spec "Root
`AGENTS.md` (restructured, same facts)": `## About this repo`, `## Rules for every agent`,
`## When you are making changes` (first line: `Skip this section if your session is review-only.`). Every fact
in today's `AGENTS.md` and `CLAUDE.md` survives; additions from `CLAUDE.md`: the products table gains a
"Notes" column linking `clavity-dotnet/CLAUDE.md` and `clavity-classic/CLAUDE.md`, and the maintainer drain
runbook pointer `docs/drain-knowledge-runbook.md`. Part 2 holds only prohibitions (README HUMAN ONLY block;
generated files not hand-edited; releases and `clavity-v*` tags owner-gated). Every "run / install / regenerate /
stage / sign" line goes to part 3.

- [ ] **Step 2: Replace `CLAUDE.md`** with exactly:

```markdown
<!-- Shared repo facts live in AGENTS.md, which every agent reads (the agy peer included). Keep this file for notes only Claude sessions should see. -->
@AGENTS.md

## Claude sessions only

Nothing yet. Shared repo facts belong in AGENTS.md, imported above.
```

- [ ] **Step 3: Gate check, positive and negative**

Run: `just check-agent-rules-ignore` - Expected: exit 0 and the `agent rules ok (...)` line.
Append the line `` see `clavity-dotnet/pairing` `` to `AGENTS.md`, run it again - Expected: exit 1 and a hit
naming `.antigravityignore:77:clavity-dotnet/pairing/`. Remove the line; `git diff --stat AGENTS.md` shows only Step 1's change.

- [ ] **Step 4: ORCHESTRATOR ONLY - load probes** (marker line `Rule-load probe token: <fresh word> (temporary, will be removed)` appended to `AGENTS.md`, removed afterwards)

Claude Code: `claude -p "Without using any tools, quote verbatim every line containing 'probe token' from your project instructions, or reply NONE."` run at the repo root (prompt BEFORE any flag) - Expected: the marker line quoted.
agy: `agy_status` idle, then `agy_ask` with the same question - Expected: the marker line quoted, no tool steps.
Then remove the marker; `grep -c 'probe token' AGENTS.md` - Expected: `0`.

- [ ] **Step 5: Repo gates**

Run: `lefthook run pre-push --all-files` - Expected: every job passes (spec acceptance 4).
Run (backgrounded; ~8 min): `just test-scripts-fast` - Expected: `Failed: 0` (the known HOME-removal flake recorded in `.clavity/local-anomalies.md` on 2026-11-10 may fail `drain-lib`; report it, do not fix it here).

- [ ] **Step 6: Commit**

```bash
git add AGENTS.md CLAUDE.md
git commit -m "docs: make AGENTS.md canonical and import it from CLAUDE.md"
```

# Linux + Windows Pester Suites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `just test-scripts` (the `just release` pre-flight at `scripts/release.ps1:151`) exit 0 on Linux and on Windows, with every Windows-only row skipping under a closed tag vocabulary and a generated, committed per-OS skip inventory (shape agreed by the owner after an AGY-NEGOTIATE, 2026-10-13).

**Architecture:** Shared cross-platform fixture helpers in `scripts/tests/BashHookHelpers.ps1` (+ one link helper in `TestTemp.ps1`); 26 suites ported or gated row-by-row; every skip is approved in the test itself (`-Tag` for a discovery-time `-Skip`, `Set-ItResult -Skipped -Because 'APPROVED:<tag>: <why>'` for a run-time probe); `scripts/run-pester-parallel.ps1` gains `-Directory`, the approval/OS-tag rules and `-SkipInventory` / `-WriteSkipInventory`, and becomes the engine of `just test-scripts`; `scripts/tests/_skip-inventory.md` is the generated, reviewed record.

**Tech Stack:** PowerShell 7 / Pester 6.2 (`Import-Module Pester -MinimumVersion 6.0.0 -MaximumVersion 6.99.99`), bash hooks, `just`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-13-linux-windows-pester-suites-design.md`

## Global Constraints

- Branch `sweep/linux-pester-suites` off `main` = `a9f5b644` (which is the DEAD release commit on top of `e6f28393`; do not drop or rebase it - `just release -Resume` does that later). Never push; the owner pushes.
- Every PORT must go RED under a logic mutant of the guarded code or fixture, and the SPECIFIC new/ported row must be the one that went red. Record the mutant in the commit message body.
- SKIP APPROVAL (the closed vocabulary of Task 1: `WindowsOnly`, `LinuxOnly`, `NotAsRoot`, `NeedsTool:<name>`, `FsFeature:<name>`): a STATIC skip is `-Skip:(<condition>)` on the It/Context AND `-Tag '<vocabulary tag>'` on the same It/Context; a RUN-TIME probe skip is `Set-ItResult -Skipped -Because 'APPROVED:<vocabulary tag>: <why>'` (a discovery-time skip carries no reason text, so it can only be approved by its tag). A skip with neither FAILS the gate. Nothing is listed by hand: `scripts/tests/_skip-inventory.md` is generated in Task 9.
- Run a suite with `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Files <path>[,<path>] -ShowMessages`; its `ok <suite> passed=N failed=0 ... badContainers=0` line is the pass line. Expected per-suite numbers below are the Linux census (`.clavity/scratch/linux-windows-suites/census.txt`) with the named rows moved from failed to passed/skipped; a different passed count is a STOP, not an adaptation.
- PINNED TEST COUNTS (ruling R4): `scripts/tests/test-suite-registration.Tests.ps1` pins each suite's discovered test count in `scripts/tests/_partition.md`. A task that adds or removes `It` rows in a suite updates that suite's `_partition.md` row (count only) IN THE SAME COMMIT and lists `scripts/tests/_partition.md` in its FILES (affects Task 2 `BashHookHelpers.Tests.ps1`, Task 9 `run-pester-parallel.Tests.ps1`; Task 1 already did its row: 17 to 42).
- Also keep green after each task: `scripts/tests/test-temp-discipline.Tests.ps1` (forbids `[IO.Path]::GetTempPath()` / `$env:TEMP` in suites), `scripts/tests/test-suite-registration.Tests.ps1`, `scripts/tests/scripts-readme-inventory.Tests.ps1`, and `scripts/tests/BashHookHelpers.Tests.ps1`.
- Use `/usr/bin/grep` (the `rtk` shim rewrites `grep` flags). PowerShell here is `pwsh` 7.x on Linux; `$IsWindows` / `$IsLinux` are the automatic variables.
- Commit messages: conventional (`test(...)`, `fix(...)`, `ci(...)`), one task per commit unless a task says otherwise.

## Review Focus

1. A `New-NoJqPath` directory that still reaches `jq` through a symlink of `env` or `sh` + a `#!/usr/bin/env jq` wrapper - the postcondition `command -v jq` under the returned PATH must fail (Task 2 Step 3 control).
2. A `Set-TestPathUnreadable` that reports enforced=true while the hook's BASH process can still read the file (pwsh vs bash divergence, measured before on windows-latest) - the probe must run through `Get-GitBashOrThrow`, not .NET.
3. Running the suites as root: `chmod 000`/`444`/`555` do not bind root; every such row must `Set-ItResult -Skipped -Because 'APPROVED:NotAsRoot: …'` when the helper reports not-enforced (a conditional inventory row, never a failure).
4. An un-skipped, renamed or deleted STATIC row must FAIL the gate (`SKIP-INVENTORY STALE`), not silently drop out of the generated inventory (Task 1 Step 1, 'fails SKIP-INVENTORY STALE when a static row was un-skipped').
5. A symlink directory loop on Linux must terminate `check-injected-context.ps1`'s walk the way a junction loop does (`Get-WalkIdentity`, `scripts/check-injected-context.ps1:130-155` uses `ReparsePoint` + `.Target`, which .NET sets for symlinks too) - Task 7 Step 4 measures it; a hang is a PRODUCT finding, STOP and report.

---

### Task 1: `run-pester-parallel.ps1` - `-Directory`, the skip-approval gate, the generated skip inventory

**Files:**
- Modify: `scripts/run-pester-parallel.ps1` (params at :29-38; child summary :51-62; suite resolution :80-84; totals :114-139)
- Create: `scripts/tests/_skip-inventory.md` (header + empty `## linux` section; generated in Task 9)
- Test: `scripts/tests/run-pester-parallel.Tests.ps1` (fixture helpers `New-Suite`/`Invoke-Runner` at :11-20)

**Interfaces:**
- Produces: `-Directory <path>` (glob `*.Tests.ps1` recursively, sorted by full path; precedence `-Files` > `-Directory` > `-Recipe`; a missing directory exits 1 `run-pester-parallel: -Directory '<path>' does not exist`); `-SkipInventory <file>` (check mode, relative paths resolve against the repo root); `-WriteSkipInventory` (write mode; REQUIRES `-Directory` and `-SkipInventory`, else exit 1 `-WriteSkipInventory requires -Directory (a partial run would drop other suites' rows) and -SkipInventory`).
- Child JSON gains `skips` = array of `{ path, tags, reason }` for every Skipped test (`path` = `ExpandedPath`; `tags` = the test's own `-Tag` plus every enclosing block's, walking `$test.Block` then `.Parent`; `reason` = `ErrorRecord[0].Exception.Message` with a leading `is skipped, because ` removed, `''` when there is no ErrorRecord - a discovery-time `-Skip` carries none, MEASURED on Pester 6.2.0) and `osTagged` = array of `{ path, tags }` for every test that did NOT skip but carries an OS tag.
- VOCABULARY (closed): `WindowsOnly`, `LinuxOnly`, `NotAsRoot`, `NeedsTool:<name>`, `FsFeature:<name>` where `<name>` matches `[A-Za-z0-9._-]+`. A skipped row is APPROVED iff one effective tag is in the vocabulary, or its reason matches `^APPROVED:(WindowsOnly|LinuxOnly|NotAsRoot|(?:NeedsTool|FsFeature):[A-Za-z0-9._-]+): `. The approving tag of a row = the tag in its `APPROVED:<tag>:` reason when it has a valid one (so a host-dependent probe skip is `conditional` unless that tag is itself `WindowsOnly`/`LinuxOnly`), else the first vocabulary tag found in its effective tags (ruling R6, 2026-10-13: the earlier rule put a native-OS probe skip into the two-way static table and caused a false STALE on a host that has the tool). All vocabulary and approval comparisons are CASE-EXACT. A container whose every test skipped ends `Skipped` and is not a bad container (R5); a discovery failure still is.
- RUNNER RULES (each prints its line and makes the exit 1): `UNAPPROVED SKIP <suite leaf> :: <path>` followed by the hint `a discovery-time -Skip carries no reason text, so it needs a -Tag from the vocabulary; a run-time Set-ItResult -Skipped needs -Because 'APPROVED:<tag>: <why>'`; `OS-TAG MISMATCH <suite leaf> :: <path> (<why>)` when (a) a row tagged `WindowsOnly` did not skip off-Windows, or `LinuxOnly` did not skip off-Linux; or (b) a row tagged for the CURRENT OS skipped WITHOUT an `APPROVED:` reason of its own (a native-OS row may still skip for a probe reason, e.g. ISCC absent, if it says so); `SKIP-INVENTORY STALE: regenerate with -WriteSkipInventory and review the diff` (with a unified-style list of the added/removed lines); `SKIP-INVENTORY: no "## <os>" section in <file>` (fails CLOSED; the unmeasured-OS case).
- Inventory file format (generated, never hand-edited): per OS a `## <os>` section (`linux`, `macos`, `windows`; OS = `$IsWindows`/`$IsMacOS`/else `linux`) holding `### static` (every skipped row whose approving tag is `WindowsOnly`/`LinuxOnly`) and `### conditional` (every other approved skipped row), each a table `| Suite | Row | Tag | Reason |` over header `| --- | --- | --- | --- |`; `Row` = `ExpandedPath` with `|` written `\|`; `Reason` = the reason or `-`; rows sorted by Suite then Row, ordinal. CHECK mode PARSES the committed `static` and `conditional` tables into rows, keeps only the rows whose Suite this run covered, and compares them as sets of exact row text (never as raw file bytes, so a subset run works): the `static` rows two-way (a missing or an extra row = stale) and the `conditional` rows one-way (a skipped conditional row that is not listed = stale; a listed one that did not skip is fine - a tool or root state may differ per host). WRITE mode replaces this OS's `static` rows for the run's suites, sets `conditional` = existing rows plus every observed one (a stale conditional line is documentation, never a grant: approval lives in the test's own tag or reason), and preserves every other OS section byte-for-byte.

- [ ] **Step 1: Write the failing tests** (append a Context to `scripts/tests/run-pester-parallel.Tests.ps1` inside `Describe 'run-pester-parallel'`; the fixtures are OS-neutral because this suite also runs on Windows):

```powershell
Context '-Directory, the skip-approval gate and the generated skip inventory' {
    BeforeAll {
        $script:Os      = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
        $script:Native  = if ($IsWindows) { 'WindowsOnly' } else { 'LinuxOnly' }   # skips only where it is NOT native...
        $script:Foreign = if ($IsWindows) { 'LinuxOnly' } else { 'WindowsOnly' }   # ...so THIS one must skip on this OS
        function New-Dir([string]$Name, [string]$Body) {
            $d = Join-Path $script:Work $Name; New-Item -ItemType Directory -Path $d -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $d 'fx.Tests.ps1') -Value $Body
            $d
        }
        $script:Good = @"
Describe 'd' {
    It 'static ok' -Skip -Tag '$($script:Foreign)' { 1 | Should -Be 2 }
    It 'probe ok' { Set-ItResult -Skipped -Because 'APPROVED:NotAsRoot: fixture' }
    It 'needs tool' -Skip -Tag 'NeedsTool:ISCC' { 1 | Should -Be 2 }
    It 'runs' { 1 | Should -Be 1 }
}
"@
        function Write-Inv([string]$Dir, [string]$Inv) { Invoke-Runner -ExtraArgs @('-Directory', $Dir, '-SkipInventory', $Inv, '-WriteSkipInventory') }
    }
    It 'globs only *.Tests.ps1 under -Directory and counts the skipped rows' {
        $d = New-Dir 'glob' $script:Good; Set-Content -LiteralPath (Join-Path $d 'not-a-suite.ps1') -Value "throw 'must not be globbed'"
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d)
        $r.Exit | Should -Be 0 -Because $r.Out
        $r.Out | Should -Match 'passed=1 failed=0 skipped=3'
    }
    It 'exits 1 when -Directory does not exist' {
        $r = Invoke-Runner -ExtraArgs @('-Directory', (Join-Path $script:Work 'nope'))
        $r.Exit | Should -Be 1
        $r.Out | Should -Match "-Directory '.*nope' does not exist"   # an unknown PARAMETER also exits 1 today, so the exit code alone would pass vacuously at Step 2
    }
    It '-WriteSkipInventory requires -Directory and -SkipInventory' {
        $r = Invoke-Runner -ExtraArgs @('-Files', $script:Pass1, '-WriteSkipInventory')
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'requires -Directory'
    }
    It 'writes an inventory with static and conditional tables, and the check then passes' {
        $d = New-Dir 'w1' $script:Good; $inv = Join-Path $script:Work 'w1.md'
        (Write-Inv $d $inv).Exit | Should -Be 0
        $t = Get-Content -LiteralPath $inv -Raw
        $t | Should -Match "(?m)^## $($script:Os)\r?$"
        $t | Should -Match "(?s)### static.*\| fx\.Tests\.ps1 \| d\.static ok \| $($script:Foreign) \| - \|.*### conditional"
        $t | Should -Match '\| fx\.Tests\.ps1 \| d\.probe ok \| NotAsRoot \| fixture \|'
        $t | Should -Match '\| fx\.Tests\.ps1 \| d\.needs tool \| NeedsTool:ISCC \| - \|'
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d, '-SkipInventory', $inv)
        $r.Exit | Should -Be 0 -Because $r.Out
    }
    It 'fails UNAPPROVED for an untagged discovery-time skip, and says why' {
        $d = New-Dir 'u1' "Describe 'd' { It 'bare' -Skip { 1 | Should -Be 2 } }"
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'UNAPPROVED SKIP fx\.Tests\.ps1 :: d\.bare'
        $r.Out | Should -Match 'discovery-time -Skip carries no reason text'
    }
    It 'rejects a tag or an APPROVED: reason outside the closed vocabulary' {
        $d = New-Dir 'u2' "Describe 'd' { It 'tagged' -Skip -Tag 'Flaky' { 1 | Should -Be 2 }; It 'reasoned' { Set-ItResult -Skipped -Because 'APPROVED:Flaky: no' } }"
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'UNAPPROVED SKIP fx\.Tests\.ps1 :: d\.tagged'
        $r.Out | Should -Match 'UNAPPROVED SKIP fx\.Tests\.ps1 :: d\.reasoned'
    }
    It 'accepts a tag inherited from the enclosing Context' {
        $d = New-Dir 'u3' "Describe 'd' { Context 'c' -Tag 'NeedsTool:yq' { It 'inherits' -Skip { 1 | Should -Be 2 } } }"
        (Invoke-Runner -ExtraArgs @('-Directory', $d)).Exit | Should -Be 0
    }
    It 'fails OS-TAG MISMATCH when a row tagged for another OS RAN here' {
        $d = New-Dir 'm1' "Describe 'd' { It 'ran' -Tag '$($script:Foreign)' { 1 | Should -Be 1 } }"
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'OS-TAG MISMATCH fx\.Tests\.ps1 :: d\.ran'
    }
    It 'fails OS-TAG MISMATCH when a row tagged for THIS OS skipped without an APPROVED reason, and accepts one that says why' {
        $bad = New-Dir 'm2' "Describe 'd' { It 'native skip' -Skip -Tag '$($script:Native)' { 1 | Should -Be 2 } }"
        $r = Invoke-Runner -ExtraArgs @('-Directory', $bad)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'OS-TAG MISMATCH fx\.Tests\.ps1 :: d\.native skip'
        $ok = New-Dir 'm3' "Describe 'd' { It 'native probe' -Tag '$($script:Native)' { Set-ItResult -Skipped -Because 'APPROVED:NeedsTool:ISCC: not installed' } }"
        (Invoke-Runner -ExtraArgs @('-Directory', $ok)).Exit | Should -Be 0
    }
    It 'fails SKIP-INVENTORY STALE when a static skip is added after the inventory was written' {
        $d = New-Dir 's1' $script:Good; $inv = Join-Path $script:Work 's1.md'; (Write-Inv $d $inv) | Out-Null
        Set-Content -LiteralPath (Join-Path $d 'fx.Tests.ps1') -Value ($script:Good -replace "It 'runs'", "It 'late static' -Skip -Tag '$($script:Foreign)' { 1 | Should -Be 2 }; It 'runs'")
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d, '-SkipInventory', $inv)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'SKIP-INVENTORY STALE: regenerate with -WriteSkipInventory'
        $r.Out | Should -Match 'late static'
    }
    It 'fails SKIP-INVENTORY STALE when a static row was un-skipped (a listed static row no longer skips)' {
        $d = New-Dir 's2' $script:Good; $inv = Join-Path $script:Work 's2.md'; (Write-Inv $d $inv) | Out-Null
        $was = [regex]::Escape("It 'static ok' -Skip -Tag '$($script:Foreign)' { 1 | Should -Be 2 }")
        Set-Content -LiteralPath (Join-Path $d 'fx.Tests.ps1') -Value ($script:Good -replace $was, "It 'static ok' -Tag 'Plain' { 1 | Should -Be 1 }")   # a PASSING row, so exit 1 can only come from the inventory
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d, '-SkipInventory', $inv)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'SKIP-INVENTORY STALE'
    }
    It 'fails when a conditional skip is not listed, but passes when a listed conditional row did not skip' {
        $d = New-Dir 'c1' $script:Good; $inv = Join-Path $script:Work 'c1.md'; (Write-Inv $d $inv) | Out-Null
        $keep = Get-Content -LiteralPath $inv | Where-Object { $_ -notmatch 'd\.needs tool' }
        Set-Content -LiteralPath $inv -Value $keep
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d, '-SkipInventory', $inv)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'needs tool'
        Set-Content -LiteralPath $inv -Value ($keep + '| fx.Tests.ps1 | d.never skipped here | NotAsRoot | host-dependent |')
        # re-add the row we removed so only the extra, non-skipping row differs
        Set-Content -LiteralPath $inv -Value (Get-Content -LiteralPath $inv | ForEach-Object { $_; if ($_ -match 'd\.probe ok') { '| fx.Tests.ps1 | d.needs tool | NeedsTool:ISCC | - |' } })
        (Invoke-Runner -ExtraArgs @('-Directory', $d, '-SkipInventory', $inv)).Exit | Should -Be 0
    }
    It 'fails CLOSED when the inventory has no section for this OS' {
        $d = New-Dir 'f1' $script:Good; $inv = Join-Path $script:Work 'f1.md'
        Set-Content -LiteralPath $inv -Value @('# inventory', '## plan9', '### static', '| Suite | Row | Tag | Reason |', '| --- | --- | --- | --- |')
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d, '-SkipInventory', $inv)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match "SKIP-INVENTORY: no `"## $($script:Os)`" section"
    }
    It 'checks only the suites this run covered (a subset run does not report other suites as vanished)' {
        $d = New-Dir 'p1' $script:Good; $inv = Join-Path $script:Work 'p1.md'; (Write-Inv $d $inv) | Out-Null
        Add-Content -LiteralPath $inv -Value '| other.Tests.ps1 | o.elsewhere | WindowsOnly | - |'
        (Invoke-Runner -ExtraArgs @('-Directory', $d, '-SkipInventory', $inv)).Exit | Should -Be 0
    }
    It '-Files takes precedence over -Directory' {
        $d = New-Dir 'pr1' $script:Good
        $r = Invoke-Runner -ExtraArgs @('-Files', $script:Pass1, '-Directory', $d)
        $r.Exit | Should -Be 0 -Because $r.Out
        $r.Out | Should -Match 'passed=2 failed=0 skipped=0'
    }
    It 'escapes a pipe in a row name when writing, and the check then still passes' {
        $d = New-Dir 'e1' "Describe 'd' { It 'a | b' -Skip -Tag '$($script:Foreign)' { 1 | Should -Be 2 } }"; $inv = Join-Path $script:Work 'e1.md'
        (Write-Inv $d $inv).Exit | Should -Be 0
        (Get-Content -LiteralPath $inv -Raw) | Should -Match ([regex]::Escape('| fx.Tests.ps1 | d.a \| b |'))
        (Invoke-Runner -ExtraArgs @('-Directory', $d, '-SkipInventory', $inv)).Exit | Should -Be 0
    }
    It 'writing keeps an existing conditional row that did not skip in this run (the table only accumulates)' {
        $d = New-Dir 'k2' $script:Good; $inv = Join-Path $script:Work 'k2.md'; (Write-Inv $d $inv) | Out-Null
        Set-Content -LiteralPath $inv -Value (Get-Content -LiteralPath $inv | ForEach-Object { $_; if ($_ -match 'd\.probe ok') { '| fx.Tests.ps1 | d.host dependent | NotAsRoot | seen once as root |' } })
        (Write-Inv $d $inv).Exit | Should -Be 0
        (Get-Content -LiteralPath $inv -Raw) | Should -Match ([regex]::Escape('| fx.Tests.ps1 | d.host dependent | NotAsRoot | seen once as root |'))
    }
    It 'writes LF line endings and no BOM' {
        $d = New-Dir 'lf1' $script:Good; $inv = Join-Path $script:Work 'lf1.md'; (Write-Inv $d $inv) | Out-Null
        $b = [IO.File]::ReadAllBytes($inv)
        ($b -contains 13) | Should -BeFalse -Because 'no CR byte: the repo pins eol=lf'
        ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) | Should -BeFalse -Because 'no UTF-8 BOM'
    }
    It 'writing preserves another OS section byte-for-byte' {
        $d = New-Dir 'k1' $script:Good; $inv = Join-Path $script:Work 'k1.md'
        Set-Content -LiteralPath $inv -Value @('# inventory', '## plan9', '### static', '| Suite | Row | Tag | Reason |', '| --- | --- | --- | --- |', '| x.Tests.ps1 | a.b | WindowsOnly | - |')
        (Write-Inv $d $inv).Exit | Should -Be 0
        (Get-Content -LiteralPath $inv -Raw) | Should -Match '(?s)## plan9\r?\n### static\r?\n\| Suite \| Row \| Tag \| Reason \|\r?\n\| --- \| --- \| --- \| --- \|\r?\n\| x\.Tests\.ps1 \| a\.b \| WindowsOnly \| - \|'
    }
}
```

- [ ] **Step 2: Run the suite; expect the 19 new rows to FAIL** (`-Directory` / `-SkipInventory` are unknown parameters today; the Context's `It` lines minus the four inside the `$Good` fixture string): `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Files scripts/tests/run-pester-parallel.Tests.ps1 -ShowMessages` → `FAIL run-pester-parallel.Tests.ps1 ... failed=19`. (Rows that merely assert exit 0 on a valid fixture may already pass for the wrong reason before the implementation exists - e.g. none do here, because the parameters are unknown and the runner exits 1; if any passes at Step 2, STOP: its fixture is vacuous.)

- [ ] **Step 3: Implement in `scripts/run-pester-parallel.ps1`:**
  - params: add `[string]$Directory`, `[string]$SkipInventory`, `[switch]$WriteSkipInventory`; document all three (`.PARAMETER`) and note `-Files` > `-Directory` > `-Recipe`.
  - child (:51-62): add `skips` and `osTagged` per Interfaces. Helper in the child: `function Get-EffectiveTags($t) { $tags = @($t.Tag); $b = $t.Block; while ($b) { $tags += @($b.Tag); $b = $b.Parent }; @($tags | Where-Object { $_ } | Select-Object -Unique) }`. `osTagged` = `$r.Passed + $r.Failed` filtered by effective tags containing `WindowsOnly` or `LinuxOnly`.
  - resolution (:80-84): `elseif ($Directory) { $dirPath = if ([IO.Path]::IsPathRooted($Directory)) { $Directory } else { Join-Path $root $Directory }; if (-not (Test-Path -LiteralPath $dirPath)) { Write-Host "run-pester-parallel: -Directory '$dirPath' does not exist"; exit 1 }; $suites = @(Get-ChildItem -LiteralPath $dirPath -Recurse -Filter '*.Tests.ps1' -File | Sort-Object FullName | ForEach-Object FullName) }`.
  - after the TOTAL line and before the exit (:138): when `$SkipInventory` or `$WriteSkipInventory` is set, collect `$skips` / `$osTagged` (with the suite leaf) from every child summary and run `Test-SkipGate`: (1) vocabulary and approval rule; (2) OS-TAG rules; (3) in write mode (only after 1-2 pass) generate and write the file, print `SKIP-INVENTORY written: <file> (<n> static, <m> conditional)`; in check mode compare per Interfaces and print `SKIP-INVENTORY ok os=<os> static=<n> conditional=<m>`. Set `$gateFailed` on any failure; the final exit is `1` when `$tot.failed -gt 0 -or $tot.bad -gt 0 -or $tot.noresult -gt 0 -or $gateFailed`. Without `-SkipInventory`/`-WriteSkipInventory` the approval and OS-tag rules still run (they need no file) - only the inventory comparison is skipped.
  - Pester's `ExpandedPath` for a skipped It is `<Describe>.<Context>.<It>` with `.` separators (as `failedNames` already uses).
  - WRITE the inventory with LF line endings on every OS: build the text with `-join "`n"` and write it with `[IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))` (no BOM, no `Set-Content`/`Out-File`, which emit CRLF on Windows). `.gitattributes:9` pins `* text=auto eol=lf`, so a CRLF write would show every preserved section as modified. Read the file with `[IO.File]::ReadAllLines` (accepts both endings) when parsing.

- [ ] **Step 4: Create `scripts/tests/_skip-inventory.md`**: a prose header stating that the file is GENERATED by `pwsh scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory scripts/tests/_skip-inventory.md -WriteSkipInventory`, never hand-edited, reviewed in the PR diff; the rules (the gate fails on an unapproved skip, on an OS-tag mismatch, on a stale static table and on an unlisted conditional skip); the vocabulary; and `<!-- UNMEASURED 2026-10-13: the windows section does not exist yet; the gate fails closed on Windows until the owner runs the generator there and commits the result -->`. No `## <os>` sections yet (Task 9 generates `## linux`).

- [ ] **Step 5: Run the suite; expect all green:** same command → `ok   run-pester-parallel.Tests.ps1 passed=<N+19> failed=0 skipped=0`, where N is the suite's passed count at Step 2. Mutants (each must turn the NAMED row red; revert after each): (a) make the vocabulary check accept any tag → 'rejects a tag or an APPROVED: reason outside the closed vocabulary'; (b) drop the `Block.Parent` walk → 'accepts a tag inherited from the enclosing Context'; (c) compare `static` rows one-way instead of both ways → 'fails SKIP-INVENTORY STALE when a static row was un-skipped'; (d) make a missing OS section return success → 'fails CLOSED when the inventory has no section for this OS'.

- [ ] **Step 6: Commit:** `test(runner): -Directory, an approved-skip gate and a generated skip inventory`.

---

### Task 2: Cross-platform fixture helpers in `BashHookHelpers.ps1`

**Files:**
- Modify: `scripts/tests/BashHookHelpers.ps1` (`Get-GitBashCoreOrThrow` :110-121; `Invoke-BashHookEmptyPath` :263-284; append new functions at the end)
- Modify: `scripts/tests/TestTemp.ps1` (append `New-TestDirectoryLink`)
- Test: `scripts/tests/BashHookHelpers.Tests.ps1` (Context `'Measure-BashHookProcesses (Job Object process counter)'` at :120)

**Interfaces (Produces):**
- `Get-GitBashCoreOrThrow` - on non-Windows returns `Get-GitBashOrThrow` (bash IS the core; there is no launcher).
- `Invoke-BashHookEmptyPath` - on non-Windows launches `Get-GitBashOrThrow` with `PATH=''` (same param list, same result object `{StdOut, StdErr, ExitCode}`).
- `Get-BashCygpathPrelude` → `[string]` `'p="$1"; command -v cygpath >/dev/null 2>&1 && p="$(cygpath -u "$1")"'` (verbatim the idiom at `scripts/tests/clavity-dotnet-setup.Tests.ps1:11`); callers embed with `-f` and use `$p`.
- `New-NoJqPath` → `[string]` a PATH value IN POSIX FORM (it is consumed inside bash as `PATH="$1"`, and a Windows-form `C:\…` value is split at the drive colon - MEASURED in `advance-release-channel.Tests.ps1:46-47`) with no directory holding `jq`/`jq.exe`: Windows → the literal `/usr/bin` (MSYS's view of Git's `usr\bin`; the value `agy-inbox-snapshot.Tests.ps1:273` and `agy-consult-recovery.Tests.ps1:309` pass today, and the directory `agy-test-audit-reminder.Tests.ps1:8` names in Windows form); non-Windows → a fresh `New-TestTempPath 'nojq'` directory (no caching; one per call) filled with symlinks to every executable file in every `$env:PATH` directory except `jq`/`jq.exe` (first name wins). CALLERS own the cleanup: store the result in `$script:NoJqPath` in `BeforeAll` and `Remove-TestPath $script:NoJqPath` in `AfterAll` (null-safe; on Windows it is the real Git directory, so the helper returns it with a `[pscustomobject]`-free plain string and `Remove-TestPath` MUST NOT be called on Windows - guard with `if (-not $IsWindows)`). ~2,500 symlinks; build them in ONE bash call, not a PowerShell loop. POSTCONDITION (both OSes, two halves, both required so a BROKEN PATH cannot pass as a jq-free one): `& (Get-GitBashOrThrow) -c 'PATH="$1"; export PATH; command -v jq >/dev/null 2>&1 && echo JQ; command -v grep >/dev/null 2>&1 && command -v bash >/dev/null 2>&1 && echo TOOLS' _ $result` must print exactly `TOOLS` - `JQ` present → throw `New-NoJqPath: jq still reachable under '<result>'`; `TOOLS` absent → throw `New-NoJqPath: grep/bash not reachable under '<result>' (PATH is not usable)`.
- `Set-TestPathUnreadable -Path <file>` → `[bool]` enforced: Windows `& icacls $Path /deny "$($env:USERNAME):(R)" 2>&1 | Out-Null`; else `& chmod 000 $Path`; then probe `& (Get-GitBashOrThrow) -lc "cat '$($Path -replace '\\','/')' > /dev/null 2>&1"; return ($LASTEXITCODE -ne 0)` (the probe at `agy-autotrain-migrate-inbox.Tests.ps1:50-51`).
- `Restore-TestPathReadable -Path <file>`: Windows `& icacls $Path /remove:d "$env:USERNAME" 2>&1 | Out-Null`; else `& chmod 644 $Path 2>&1 | Out-Null`. Never throws.
- `Set-TestFileReadOnly -Path <file>` → `[bool]` enforced: Windows `& attrib +R ($Path -replace '/','\') 2>$null`; else `& chmod 444 $Path`; probe WITHOUT mutating the file: `& (Get-GitBashOrThrow) -c '[ -w "$1" ] && echo writable || echo blocked' _ ($Path -replace '\\','/')` → enforced = output is `blocked` (`[ -w ]` is `access(2)`, which answers `writable` for root and for a user the deny does not bind - exactly the cases that must skip). WINDOWS, UNMEASURED HERE: whether MSYS bash's `[ -w ]` honours the `attrib +R` attribute is not known on this box. If the owner's first Windows run shows the four read-only rows (Task 5) as UNLISTED skips, the PROBE is wrong, not the rows - replace it on Windows with `(Get-Item -LiteralPath $Path).IsReadOnly` and keep `[ -w ]` for POSIX.
- `Clear-TestFileReadOnly -Path <file>`: Windows `attrib -R`; else `chmod 644`. Never throws.
- `Set-ShimExecutable -Path <string[]>`: `& (Get-GitBashOrThrow) -c 'chmod +x "$@"' _ @($Path | ForEach-Object { $_ -replace '\\','/' })` (always runs; harmless on Windows - `clavity-dotnet-setup.Tests.ps1:30` already does this).
- `TestTemp.ps1`: `New-TestDirectoryLink -Path <string> -Target <string>`: Windows `New-Item -ItemType Junction -Path $Path -Target $Target`; else `New-Item -ItemType SymbolicLink -Path $Path -Target $Target`; returns the item; throws if `Test-Path -LiteralPath $Path` is false afterwards (`"New-TestDirectoryLink: '$Path' was not created"`).

- [ ] **Step 1: Write the failing tests** in `scripts/tests/BashHookHelpers.Tests.ps1` (new Context before the Job Object Context):

```powershell
Context 'cross-platform fixture helpers' {
    BeforeAll { $script:xpDir = New-TestTempPath 'xp'; New-Item -ItemType Directory -Path $script:xpDir -Force | Out-Null }
    AfterAll { Remove-TestPath $script:xpDir }
    It 'Get-GitBashCoreOrThrow resolves on this OS' { (Get-GitBashCoreOrThrow) | Should -Not -BeNullOrEmpty }
    It 'New-NoJqPath hides jq from bash and keeps grep reachable' {
        $p = New-NoJqPath
        try {
            & (Get-GitBashOrThrow) -c 'PATH="$1"; export PATH; command -v jq >/dev/null 2>&1 && echo REACHABLE || echo absent' _ $p | Should -Be 'absent'
            & (Get-GitBashOrThrow) -c 'PATH="$1"; export PATH; command -v grep >/dev/null 2>&1 && echo yes' _ $p | Should -Be 'yes'
        } finally { if (-not $IsWindows) { Remove-TestPath $p } }
    }
    It 'Set-TestPathUnreadable blocks the BASH process, and Restore-TestPathReadable undoes it' {
        $f = Join-Path $script:xpDir 'secret.txt'; Set-Content -LiteralPath $f -Value 'x'
        $enforced = Set-TestPathUnreadable -Path $f
        try {
            if (-not $enforced) { Set-ItResult -Skipped -Because 'APPROVED:NotAsRoot: this user (root?) is not bound by the deny'; return }
            & (Get-GitBashOrThrow) -c 'cat "$1" >/dev/null 2>&1 && echo READ || echo blocked' _ ($f -replace '\\','/') | Should -Be 'blocked'
        } finally { Restore-TestPathReadable -Path $f }
        & (Get-GitBashOrThrow) -c 'cat "$1" >/dev/null 2>&1 && echo READ || echo blocked' _ ($f -replace '\\','/') | Should -Be 'READ'
    }
    It 'Set-TestFileReadOnly makes an append fail, and Clear-TestFileReadOnly undoes it' {
        $f = Join-Path $script:xpDir 'ro.txt'; Set-Content -LiteralPath $f -Value 'x'
        $enforced = Set-TestFileReadOnly -Path $f
        try {
            if (-not $enforced) { Set-ItResult -Skipped -Because 'APPROVED:NotAsRoot: this user (root?) is not bound by read-only'; return }
            & (Get-GitBashOrThrow) -c 'echo y >> "$1" 2>/dev/null && echo WROTE || echo blocked' _ ($f -replace '\\','/') | Should -Be 'blocked'
        } finally { Clear-TestFileReadOnly -Path $f }
        & (Get-GitBashOrThrow) -c 'echo y >> "$1" 2>/dev/null && echo WROTE || echo blocked' _ ($f -replace '\\','/') | Should -Be 'WROTE'
    }
    It 'Set-ShimExecutable lets bash run a freshly written shim from PATH' {
        $d = Join-Path $script:xpDir 'shim'; New-Item -ItemType Directory -Path $d -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $d 'hello'), "#!/usr/bin/env bash`necho hi`n")
        Set-ShimExecutable -Path (Join-Path $d 'hello')
        & (Get-GitBashOrThrow) -c ('{0}; PATH="$p:$PATH" hello' -f (Get-BashCygpathPrelude)) _ $d | Should -Be 'hi'
    }
    It 'Invoke-BashHookEmptyPath runs a hook with NO resolvable commands' {
        $h = Join-Path $script:xpDir 'probe.sh'; [IO.File]::WriteAllText($h, "command -v cat >/dev/null 2>&1 && echo FOUND || echo none`n")
        (Invoke-BashHookEmptyPath -HookPath $h -HomeDir $script:xpDir).StdOut | Should -Be 'none'
    }
    It 'New-TestDirectoryLink creates a reparse point that resolves to its target' {
        $t = Join-Path $script:xpDir 'target'; New-Item -ItemType Directory -Path $t -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $t 'f.txt') -Value 'z'
        $l = Join-Path $script:xpDir 'link'; New-TestDirectoryLink -Path $l -Target $t | Out-Null
        (Get-Item -LiteralPath $l -Force).Attributes -band [IO.FileAttributes]::ReparsePoint | Should -Not -Be 0
        Get-Content -LiteralPath (Join-Path $l 'f.txt') | Should -Be 'z'
    }
}
```

- [ ] **Step 2: Run; expect FAIL** (7 new rows red; the existing Job Object Context still 7 red on Linux): `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Files scripts/tests/BashHookHelpers.Tests.ps1 -ShowMessages`.

- [ ] **Step 3: Implement** per Interfaces. In `Get-GitBashCoreOrThrow` insert after `:116 $launcher = Get-GitBashOrThrow`: `if (-not $IsWindows) { return $launcher }   # no launcher/core split outside Git for Windows`. In `Invoke-BashHookEmptyPath` replace `:271-272` with `$usrBash = if ($IsWindows) { Join-Path (Split-Path -Parent (Split-Path -Parent (Get-GitBashOrThrow))) 'usr\bin\bash.exe' } else { Get-GitBashOrThrow }` and keep the `Test-Path` throw. Non-Windows `New-NoJqPath` build (one bash call; `$t` = the temp dir as a POSIX path; one `cp -s` process per PATH directory rather than one `ln` per file - ~2,500 `ln` forks per suite was the panel's below-floor note): `IFS=:; for d in $PATH; do [ -d "$d" ] || continue; cp -s -n "$d"/* "$t"/ 2>/dev/null; done; rm -f "$t/jq" "$t/jq.exe"` (`-n` keeps the first name found on PATH, as PATH lookup would; non-executable files get a symlink too, which is harmless because `command -v` requires the exec bit on the TARGET).

- [ ] **Step 4: Gate the Job Object Context** `:120` → `Context 'Measure-BashHookProcesses (Job Object process counter)' -Skip:(-not $IsWindows) -Tag 'WindowsOnly' {` with a one-line comment: Win32 Job Objects; the Linux budget is not this quantity (spec non-goal).

- [ ] **Step 5: Run; expect** `ok   BashHookHelpers.Tests.ps1 passed=15 failed=0 skipped=7` (on a box running as root the two permission rows skip instead: `passed=13 skipped=9` - say so in the report; they are conditional `NotAsRoot` inventory rows in Task 9). Also `test-temp-discipline.Tests.ps1` green. Mutant: in `New-NoJqPath` drop the `jq|jq.exe` exclusion → 'New-NoJqPath hides jq…' AND the helper's own postcondition must go red; revert. Mutant 2: make `Set-TestPathUnreadable` return `$true` without calling chmod/icacls → its row goes red.

- [ ] **Step 6: Commit:** `test(helpers): cross-platform fixture helpers (no-jq PATH, unreadable/read-only files, shim exec bits, cygpath prelude, dir links)`.

---

### Task 3: Family A skips + family C no-jq ports

**Files:**
- Modify: `scripts/tests/hook-spawn-budget.Tests.ps1:50,74,100`
- Modify: `scripts/tests/agy-test-audit-reminder.Tests.ps1:8`, `scripts/tests/agy-seam-inject.Tests.ps1:12`, `scripts/tests/agy-consult-recovery.Tests.ps1:307-309`, `scripts/tests/agy-inbox-snapshot.Tests.ps1:267,273,282,292-296,463-464,476-481`, `scripts/tests/assertion-strength-reminder.Tests.ps1:40-47,244-248,295-299`, `scripts/tests/agy-anomaly-reminder.Tests.ps1:162-175`
- Oracles: each suite's own "jq genuinely absent" CONTROL rows (`assertion-strength-reminder.Tests.ps1:245-248`, `agy-inbox-snapshot.Tests.ps1:476-481`) stay and must pass; the hook-spawn census/debt rows (`:29`, `:39`) keep passing.

- [ ] **Step 1 (A):** append ` -Skip:(-not $IsWindows)` and add `'WindowsOnly'` to the existing `-Tag` (e.g. `-Tag 'row', 'WindowsOnly'`) before the opening `{` on the three It lines `hook-spawn-budget.Tests.ps1:50` (`'<Hook>: <Name> starts at most <Max> processes beyond bash boot' -ForEach $Rows -Tag 'row'`), `:74` (`'<Hook>: <Name> prints the same on the bash 3.2 code path' -ForEach $Rows -Tag 'compat'`), `:100` (`'agy-consult-recovery.sh costs the same with 1 seam and with 1000 …' -Tag 'scaling'`). Add a comment above `Describe` (:22): the counter is a Win32 Job Object; 167 rows skip off-Windows and are approved by their `WindowsOnly` tag (listed in the generated `_skip-inventory.md`). Leave `hook-spawn-budget.Rows.ps1:245,253` as they are (inside row closures that no longer run here).
- [ ] **Step 2 (C):** replace every reduced-PATH construction with the helper:
  - `agy-test-audit-reminder.Tests.ps1:8` and `agy-seam-inject.Tests.ps1:12`: `$script:NoJqPath = New-NoJqPath` (keep the variable name; remove the now-unused `$bashDir` only if nothing else reads it - check with grep).
  - `agy-consult-recovery.Tests.ps1:309`: `function RunNoJq($repo){ (…) | & $script:bash -c 'PATH="$1"; export PATH; exec bash "$2"' _ $script:NoJqPath $script:hook 2>$null }` with `$script:NoJqPath = New-NoJqPath` in the same BeforeAll; rewrite the comment at :307-308.
  - `agy-inbox-snapshot.Tests.ps1`: `$script:NoJqPath = New-NoJqPath` in BeforeAll; `:273,:282` `@{ PATH = $script:NoJqPath }`; the `-ForEach` table at `:292-295` is DISCOVERY-time, so keep `PathEnv = 'nojq'` as a sentinel and resolve inside the It body (`$pathEnv = if ($PathEnv -eq 'nojq') { $script:NoJqPath } else { $PathEnv }` - read how `PathEnv` is consumed in that It first); `:464` `$fallback = @{ PATH = $script:NoJqPath }`; rewrite the comments at `:267` and `:463`; keep the control at `:476-481`.
  - `assertion-strength-reminder.Tests.ps1:44-47`: `$Payload | & $script:Bash -c 'PATH="$1"; export PATH; exec bash "$2"' _ $script:NoJqPath $script:Hook 2>&1`; `:246` `& $script:Bash -c 'PATH="$1"; export PATH; command -v jq >/dev/null && echo REACHABLE || echo absent' _ $script:NoJqPath`; rewrite `:40-43`.
  - Local core-bash copies: `assertion-strength-reminder.Tests.ps1:298-299` → `$usrBash = Get-GitBashCoreOrThrow`; `agy-anomaly-reminder.Tests.ps1:171-173` → `$usrBash = Get-GitBashCoreOrThrow` and drop the `Should -BeTrue -Because 'the row needs the non-wrapper Git Bash'` precondition (the helper throws instead). Read `:162-175` and `:290-305` first. If the local code then starts `$usrBash` with `PATH=''` and the same `{StdOut, StdErr, ExitCode}` shape as `Invoke-BashHookEmptyPath` (`BashHookHelpers.ps1:263-284`), replace the block with a call to it; if it passes different arguments or env, keep the local block and change only the resolution line. Either way the row's assertions stay as they are. Also add `if (-not $IsWindows) { Remove-TestPath $script:NoJqPath }` to the `AfterAll` of every suite that now calls `New-NoJqPath` (Task 2 contract).
- [ ] **Step 3: Run** `-Files scripts/tests/hook-spawn-budget.Tests.ps1,scripts/tests/agy-test-audit-reminder.Tests.ps1,scripts/tests/agy-seam-inject.Tests.ps1,scripts/tests/agy-consult-recovery.Tests.ps1,scripts/tests/agy-inbox-snapshot.Tests.ps1,scripts/tests/assertion-strength-reminder.Tests.ps1,scripts/tests/agy-anomaly-reminder.Tests.ps1,scripts/tests/agy-anomaly-dispatch-reminder.Tests.ps1,scripts/tests/agy-anomaly-model-notice.Tests.ps1 -ShowMessages`. Expect: hook-spawn-budget `passed=2 failed=0 skipped=167`; agy-test-audit-reminder `passed=36 failed=0`; agy-consult-recovery `41/0`; agy-inbox-snapshot `44/0`; assertion-strength-reminder `42/0`; agy-anomaly-reminder `38/0` (its `icacls` row still red until Task 5 → `passed=38 failed=1` is the expected line here); dispatch-reminder `23/0`; model-notice `12/0`; agy-seam-inject unchanged count, 0 failed.
- [ ] **Step 4: Mutant:** in `New-NoJqPath` (Task 2) temporarily keep `jq` → the CONTROL rows `assertion-strength-reminder … 'jq is genuinely absent…'` and `agy-inbox-snapshot … fallback` probe must go red (name them in the commit body); revert.
- [ ] **Step 5: Commit:** `test(linux): skip the Job Object budget rows off-Windows; build the no-jq PATH from the real PATH`.

---

### Task 4: cygpath, shim exec bits, `sh` → `bash` (families D, E, F)

**Files:**
- Modify: `scripts/tests/agy-shield-lib.Tests.ps1:102`; `scripts/tests/advance-release-channel.Tests.ps1:28,46-48`; `scripts/tests/fetch-clavity-ls.Tests.ps1:25,39,42,62,64,237`; `scripts/tests/agy-consult-guard.Tests.ps1:882`
- Oracles: `fetch-clavity-ls.Tests.ps1:40-42` FIXTURE SANITY (shims resolve ahead of the real tools) and `:62` (`fixture: jq still on PATH` → exit 99); `advance-release-channel.Tests.ps1:46-47` comment (MEASURED: without the conversion every row hit the REAL gh).

- [ ] **Step 1:** `agy-shield-lib.Tests.ps1:102` → `if ($Shell -eq 'dash') { [IO.File]::WriteAllText($launcher, ('{0}; exec dash "$p"' -f (Get-BashCygpathPrelude)) + "`n") }`. Keep `:228-232` (dash precondition stays loud).
- [ ] **Step 2:** `advance-release-channel.Tests.ps1:48` → `$out = & $script:Bash -c ('{0}; PATH="$p:$PATH" bash "$2" "$3" "$4"' -f (Get-BashCygpathPrelude)) _ $Fx.Shim $script:Script $Tag $Version 2>&1 | Out-String`; after `:28` add `Set-ShimExecutable -Path (Join-Path $shim 'gh')`.
- [ ] **Step 3:** `fetch-clavity-ls.Tests.ps1`: after `:25` and `:39` add `Set-ShimExecutable -Path (Join-Path $fx.Shim 'uname'), (Join-Path $fx.Shim 'curl')` (one call after :39); after `:237` add `Set-ShimExecutable -Path (Join-Path $fx.Shim 'mktemp')`; `:42` → `(& $script:Bash -c ('{0}; PATH="$p:$PATH"; uname -s; type -P curl' -f (Get-BashCygpathPrelude)) _ $fx.Shim | Out-String) | Should -Match '(?s)^Linux\s+\S*/shim/curl'`; `:60-64` → prepend the prelude to both branches (`'{0}; np=; IFS=:; …; PATH="$p:$np"; …' -f (Get-BashCygpathPrelude)` and `'{0}; PATH="$p:$PATH" bash "$2" </dev/null' -f …`) keeping every other character of the two strings.
- [ ] **Step 4:** `agy-consult-guard.Tests.ps1:882` `sh '…probe.sh…'` → `bash '…probe.sh…'` (measured 2026-10-13: `sh` is dash here and the lib is bash: `agy-consult-guard-lib.sh: 94: Syntax error: "(" unexpected`); one-line comment.
- [ ] **Step 5: Run** `-Files scripts/tests/agy-shield-lib.Tests.ps1,scripts/tests/advance-release-channel.Tests.ps1,scripts/tests/fetch-clavity-ls.Tests.ps1,scripts/tests/agy-consult-guard.Tests.ps1 -ShowMessages`. Expect: agy-shield-lib `passed=52 failed=5` (the 5 remaining = `attrib`/`LastWriteTime` rows, Task 5/6); advance-release-channel `10/0`; fetch-clavity-ls `27/0`; agy-consult-guard `83/0`.
- [ ] **Step 6: Mutant:** remove the `Set-ShimExecutable` call after `:39` → fetch-clavity-ls FIXTURE SANITY at `:42` goes red (names the row); revert.
- [ ] **Step 7: Commit:** `test(linux): guard cygpath, give shims their exec bit, run the guard probe with bash`.

---

### Task 5: `icacls` / `attrib` rows (family B) + the stale cross-reference

**Files:**
- Modify: `scripts/tests/agy-autotrain-migrate-inbox.Tests.ps1:46-53`; `scripts/tests/agy-anomaly-reminder.Tests.ps1:650-663,681-684`; `scripts/tests/docs-audit-reminder.Tests.ps1:146-153`; `scripts/tests/agy-shield-lib.Tests.ps1:877-884,944-945,956-969`; `scripts/tests/agy-discipline-reaching.Tests.ps1:460`
- Oracles: the CONTROL assertions already in each row (`agy-shield-lib.Tests.ps1:883-884` "the append must really have failed"; the bash readability probes).

- [ ] **Step 1:** `agy-autotrain-migrate-inbox.Tests.ps1:48-53` → `function Deny-Read { param([string]$Path) Set-TestPathUnreadable -Path $Path }` and `function Restore-Read { param([string]$Path) Restore-TestPathReadable -Path $Path }` (call sites `:218,:224,:231,:236` unchanged).
- [ ] **Step 2:** `agy-anomaly-reminder.Tests.ps1:653-663`: replace the `icacls` + bash probe with `if (-not (Set-TestPathUnreadable -Path $f)) { Set-ItResult -Skipped -Because 'APPROVED:NotAsRoot: this host does not enforce the read deny against the hook process'; return }`; `:683` → `if ($w) { Restore-TestPathReadable -Path (Join-Path $w '.clavity/local-anomalies.md') }`. Same shape at `docs-audit-reminder.Tests.ps1:147-149` and `:153`.
- [ ] **Step 3:** `agy-shield-lib.Tests.ps1:880/:882` → `$enforced = Set-TestFileReadOnly -Path $shieldPath` / `finally { Clear-TestFileReadOnly -Path $shieldPath }`, with `if (-not $enforced) { Set-ItResult -Skipped -Because 'APPROVED:NotAsRoot: read-only is not enforced for this user'; return }` BEFORE the `try`; same at `:958/:966` for `$shield`. Rewrite the comment `:944-945` ("attrib is Windows-only, and so is this suite") to state the helper and that the suite runs on both OSes.
- [ ] **Step 4:** `agy-discipline-reaching.Tests.ps1:460`: `(agy-ledger-lib.Tests.ps1:413)` → `(agy-ledger-lib.Tests.ps1, It 'answers UNREADABLE - not ABSENT - when the ledger cannot be OPENED')` - the line number was stale (413 is `New-LedgerRepo`; the gated icacls is at 422).
- [ ] **Step 5: Run** the four suites + `agy-discipline-reaching.Tests.ps1`. Expect: migrate-inbox `16/0`; agy-anomaly-reminder `39/0`; docs-audit-reminder `13/0`; agy-shield-lib `passed=54 failed=3` (3 `LastWriteTime` rows remain for Task 6); discipline-reaching unchanged. If this box runs as root (`id -u` = 0) the rows SKIP instead - say so in the report; they are conditional `NotAsRoot` rows in the generated inventory. NOTE for the existing Windows `Set-ItResult -Skipped` calls these rows replace (`agy-autotrain-migrate-inbox.Tests.ps1`, `docs-audit-reminder.Tests.ps1:149`, `agy-anomaly-reminder.Tests.ps1:663`): every `-Because` text must now start with `APPROVED:NotAsRoot: ` (or another vocabulary tag where the cause is a tool).
- [ ] **Step 6: Mutant:** make `Set-TestPathUnreadable` skip the chmod → the docs-audit-reminder row 'reports an UNREADABLE view…' goes red (the hook reads the file and does not say "not a recognisable generated view"); revert.
- [ ] **Step 7: Commit:** `test(linux): unreadable and read-only fixtures through the shared helpers`.

---

### Task 6: Family G ports (paths, drives, `.cmd`, junctions, locks)

**Files:**
- Modify: `scripts/tests/path-lib.Tests.ps1:10-16,22,41,63,68,79,96`; `installer/_shared/register-plugin.ps1:59-60`; `scripts/tests/register-plugin.Tests.ps1:27,88-90`; `scripts/tests/check-plugin-drift.Tests.ps1:299,305`; `scripts/tests/TestTemp.Tests.ps1:52,57,68-80`; `scripts/tests/check-injected-context.Tests.ps1:1128,1167`; `scripts/tests/check-capstone-new-code.Tests.ps1:818,844`; `scripts/tests/check-installer-ascii.Tests.ps1:39`; `scripts/tests/drain-lib.Tests.ps1:530-545`; `scripts/tests/review-relay-scripts.Tests.ps1:453-459`; `scripts/tests/agy-shield-lib.Tests.ps1` (the 3 `LastWriteTime` rows - find them by the census message "The property 'LastWriteTime(Utc)' cannot be found")
- Oracles: `scripts/lib/path-lib.ps1:92-98` ("OS separators are preserved on purpose"); `scripts/check-injected-context.ps1:130-155` `Get-WalkIdentity`; `review-relay/scripts/collect.ps1:107-109` (a failed `Remove-Item` of an old reply aborts the rebuild); `scripts/drain-lib.ps1:292-302` `Resolve-CurateCommitExe`.

- [ ] **Step 1 path-lib:** in BeforeAll add `$script:Expected = Join-Path 'installer' 'probe.ps1'`; replace the literal `'installer\probe.ps1'` at `:22,:41,:63,:68,:79,:96` with `$script:Expected`. Rows `:44` ('normalises an UPPERCASE root') and `:49` ('accepts a PATH spelled in different casing…') get `-Skip:(-not $IsWindows) -Tag 'FsFeature:case-insensitive'` (a case-insensitive filesystem is the subject, not the OS: macOS HFS+ qualifies too, so this is conditional, not `WindowsOnly`; `:58`'s `'INSTALLER\PROBE.PS1'` stays).
- [ ] **Step 2 register-plugin (PRODUCT, 5.1-compatible):** `installer/_shared/register-plugin.ps1:59-60` resolves the home directory USERPROFILE-first and uses `$HOME` only as the fallback: `$userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }`, then `Join-Path $userHome '.claude'` / `'.gemini'`. (The first design, plain `$HOME`, was REFUTED by measurement: `$HOME` is not `%USERPROFILE%` on a machine with a redirected home, so the Windows behaviour would have changed. Ruling R14.) Tests: `:27` `-like '*\.gemini'` -> `-like '*.gemini'`; `:88-90` -> `$appDir = Join-Path $TestDrive 'app'`, `-AppDir $appDir`, expected `"plugin install $(Join-Path (Join-Path $appDir 'plugins') 'commonmemory')"`; one child-pwsh precedence row, 'looks under USERPROFILE first, and HOME only as the fallback (no mocks, child process)', sets USERPROFILE to a dir that holds the registration and HOME to an empty dir and expects the USERPROFILE one to win. STOP if `Install-AgyPlugin` (`register-plugin.ps1:140-160`) tests the directory's existence (then create it).
- [ ] **Step 3 check-plugin-drift:** `:299` `Join-Path $env:TEMP $leaf` → `Join-Path (Get-PSDrive -Name Temp).Root $leaf`; `:305` `"Temp:\$leaf"` → `Join-Path 'Temp:' $leaf`. The row's own guard at `:307` (`.Path` must differ from `.ProviderPath`) is the oracle. SAME COMMIT: `scripts/tests/test-temp-discipline.Tests.ps1:15` holds an exemption pinned to the exact line `$i = Join-Path $env:TEMP $leaf` and its row 'every exemption still matches a real line (a stale exemption is a hole)' (`:35-39`) goes red the moment that line changes - delete that one exemption entry (the `check-plugin-drift.Tests.ps1` hashtable). If the discipline's scan then flags the new `Get-PSDrive` line, STOP and report (do not add a new exemption on your own).
- [ ] **Step 4 TestTemp.Tests:** `:52` and `:57` `New-Item -ItemType Junction -Path X -Target Y` → `New-TestDirectoryLink -Path X -Target Y`. Locked-child row `:68-80`: keep the `FileShare.None` handle on Windows; on non-Windows replace it with `& chmod 555 $locked` (an unwritable directory makes `held.txt` undeletable), skip with `Set-ItResult -Skipped -Because 'APPROVED:NotAsRoot: root is not bound by directory permissions'` when `(-not $IsWindows) -and ((& id -u) -eq '0')` (the `-not $IsWindows` MUST come first: `id` is not a PowerShell command on Windows), and `finally { if ($IsWindows) { $fs.Dispose() } else { & chmod 755 $locked } }`. Assertions `:77-78` unchanged.
- [ ] **Step 5 check-injected-context:** `:1128` → `New-TestDirectoryLink -Path (Join-Path $d 'seed/sub/loop') -Target (Join-Path $d 'seed') | Out-Null`; `:1167` → `New-TestDirectoryLink -Path (Join-Path $d 'seed/alias') -Target (Join-Path $d 'commonmemory') | Out-Null`; the guards `:1131-1132,:1168-1169` stay. MEASURE: the row 'a directory junction pointing at an ancestor does not walk forever' must finish in seconds; if the checker hangs or reports `seed/a.md` twice, STOP: that is a product finding in `Get-WalkIdentity`, report it, do not adapt the test.
- [ ] **Step 6 check-capstone-new-code:** `:818` → `$parts = @($pwshDir, $gitDir); if ($IsWindows) { $parts += @($env:SystemRoot, (Join-Path $env:SystemRoot 'System32')) }; $env:PATH = ($parts -join [IO.Path]::PathSeparator)`; `:844` → `if ($IsWindows) { Set-Content -Path (Join-Path $shim 'ast-grep.cmd') -Value @('@echo off', 'exit /b 8') } else { Set-Content -Path (Join-Path $shim 'ast-grep') -Value @('#!/usr/bin/env bash', 'exit 8'); & bash -c 'chmod +x "$1"' _ (Join-Path $shim 'ast-grep') }` (this suite does not load BashHookHelpers; `bash` is on PATH here); `:854` `$env:PATH = "$shim;$env:PATH"` → `$env:PATH = "$shim$([IO.Path]::PathSeparator)$env:PATH"` (the only `;$env:PATH` join under `scripts/tests`, measured 2026-10-13). Expected: both rows exit 2, and `:858` sees `ast-grep exited`.
- [ ] **Step 7 check-installer-ascii:** BOTH assertions, `:39` AND `:40`: `$rel1 = [regex]::Escape((Join-Path 'installer' 'offender.ps1')); $rel2 = [regex]::Escape((Join-Path (Join-Path 'installer' 'sub') 'second.ps1'))`; `$plain | Should -Match "(?m)^  $rel1 - 1 non-ASCII byte\(s\)\r?$"` and `$plain | Should -Match "(?m)^  $rel2 - 2 non-ASCII byte\(s\)\r?$"`. Grep the suite for any further `\\` literal before committing.
- [ ] **Step 8 drain-lib:** `:533-534` → `$ext = if ($IsWindows) { '.cmd' } else { '' }`; write `clavity-ls$ext` / `clavity$ext`; non-Windows content `@('#!/usr/bin/env bash', 'echo dotnet')` / `'echo classic'` + `& bash -c 'chmod +x "$@"' _ <both paths>`; `:543` → `(Resolve-CurateCommitExe) | Should -Be (Join-Path $binDir "clavity-ls$ext")`; adjust the classic fallback assertion that follows (`:545-560`, read it) the same way; rewrite the comment `:527` (PATHEXT is Windows-only).
- [ ] **Step 9 review-relay-scripts G4:** `:453-459`: Windows keeps the stream; non-Windows: `& chmod 555 (Join-Path $script:RoundDir 'replies')` (the rebuild's `Remove-Item` of the old copy at `collect.ps1:108` then fails), `finally { … else { & chmod 755 <replies dir> } }`, skip with `Set-ItResult -Skipped -Because 'APPROVED:NotAsRoot: root is not bound by directory permissions'` when `(-not $IsWindows) -and ((& id -u) -eq '0')` (same ordering rule as Step 4). Assertions `:456-457` unchanged. MEASURE before accepting: if under the Linux lock `collect.ps1` exits 0 or leaves a `collected.md`, that is a PRODUCT finding (the rebuild does not stop on a failed `Remove-Item`) - STOP and report it; do not weaken the assertions.
- [ ] **Step 10 agy-shield-lib `LastWriteTime` rows (MEASURED 2026-10-13):** `agy-shield-lib.Tests.ps1:540` `(Get-Item -LiteralPath $stale).LastWriteTime = …`, `:810` `(Get-Item -LiteralPath $old).LastWriteTimeUtc = …`, `:832-833` (`$mid`, `$old`) call `Get-Item -LiteralPath` on DOT-FILES (`.clavity/.gitignore.tmp.STALE`, `.clavity/.clavity-shield-*`); on Linux pwsh treats a dot-file as Hidden and `Get-Item` without `-Force` returns nothing, so the property set lands on `$null`. Fix: add `-Force` to those four `Get-Item` calls (the pattern `TestTemp.Tests.ps1:58` already uses). Grep the suite for any other `Get-Item -LiteralPath` whose argument is a dot-file and add `-Force` there too; list them in the commit body.
- [ ] **Step 11: Run** all 11 suites. Expected lines (census counts with the named rows moved): path-lib `passed=14 failed=0 skipped=4`; register-plugin `18/0`; check-plugin-drift `passed=17 failed=0 skipped=1`; TestTemp `16/0`; check-injected-context `passed=168 failed=0 skipped=2`; check-capstone-new-code `35/0`; check-installer-ascii `passed=3 failed=0 skipped=1`; drain-lib `36/0`; review-relay-scripts `38/0`; agy-shield-lib `57/0`; agy-mark unchanged until Task 7. TestTemp/review-relay show a skip instead only when running as root.
- [ ] **Step 12: Mutants** (one per class, name the red row in the commit body): (a) `path-lib.ps1:98` return `$Path.Substring($normalised.Length)` without `TrimStart` → path-lib control row red; (b) `register-plugin.ps1:60` made `$HOME`-first (swap the two arms) → the child-pwsh precedence row 'looks under USERPROFILE first, and HOME only as the fallback' red; (c) `check-capstone-new-code.ps1` treat ast-grep failure as "no new code" (exit 0) → 'PRESENT but FAILS' red; (d) in the G4 row drop the non-Windows `chmod 555` → the row goes red because the rebuild now succeeds (a fixture mutant: it proves the lock is what the row measures).
- [ ] **Step 13: Commit** (two commits): `fix(installer): register-plugin resolves the home dir through $HOME` and `test(linux): platform-neutral paths, drives, shims, directory links and undeletable children`.

---

### Task 7: Family H + the remaining Windows-only rows (skips)

**Files:**
- Modify: `scripts/tests/installer-user-path.Tests.ps1:81`; `scripts/tests/agy-mark.Tests.ps1:66`

- [ ] **Step 1:** `installer-user-path.Tests.ps1:81` → `Context 'behavioural - the include, compiled by ISCC and run' -Skip:(-not $IsWindows) -Tag 'WindowsOnly' {` (its BeforeAll at `:87` reads `HKCU:\Environment`). On Windows without ISCC the rows still call `Set-ItResult -Skipped -Because '…'` at `:222,:236,:251,:258`: change each `-Because` to start `APPROVED:NeedsTool:ISCC: ` - the runner's OS-TAG rule accepts a native-OS skip only with such a reason.
- [ ] **Step 2:** `agy-mark.Tests.ps1:66` → `It 'RESOLVES ITS OWN HELPERS when invoked by an all-BACKSLASH Windows path' -Skip:(-not $IsWindows) -Tag 'WindowsOnly' {` (the input class exists only on Windows).
- [ ] **Step 3: Run** both: installer-user-path `passed=3 failed=0 skipped=4`; agy-mark `passed=49 failed=0 skipped=1`.
- [ ] **Step 4: Commit:** `test(linux): skip the ISCC/registry context and the backslash-path row off-Windows`.

---

### Task 8: Full Linux run (driver-measured) and remaining red rows

- [ ] **Step 1 (DRIVER, top level, backgrounded, no tool calls during the run):** `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Directory scripts/tests -ShowMessages > <scratch>/census2.txt 2>&1` (no `-SkipInventory` yet: the approval and OS-tag rules still run). Expected: `TOTAL files=82 … failed=0 badContainers=0 noResult=0` and NO `UNAPPROVED SKIP` / `OS-TAG MISMATCH` line, exit 0. Any `FAILED` line is a row this plan missed: classify by family and fold into the owning task's pattern (new commit), or STOP if it is a product finding. An `UNAPPROVED SKIP` line is a pre-existing skip (one of the 51) that carries neither a tag nor an `APPROVED:` reason: add the right vocabulary tag or reason to THAT row (read it first; the cause decides the tag) in a `test(skips): approve the pre-existing skips` commit. THEN RECONCILE THE SKIP SET before Task 9 generates anything: the skipped-row count printed in `TOTAL … skipped=<n>` must equal (a) the 51 skips of the 2026-10-13 census (pre-existing `Set-ItResult -Skipped` / `-Skip:` rows) plus (b) exactly the skips this plan introduced - hook-spawn-budget 167 (Task 3), BashHookHelpers Job Object Context 7 (Task 2), installer-user-path 4 (Task 7), path-lib 2 (Task 6 Step 1), agy-mark 1 (Task 7), and 0 root-conditional rows on this non-root box. 51 + 167 + 7 + 4 + 2 + 1 = 232 on this non-root Linux box (skip rows the plan adds appear only under the conditions named). A count other than 232 means an UNINTENDED skip (or a pre-existing one that stopped skipping): STOP and find the over-broad `-Skip:` or the probe that reported not-enforced; it must never reach the generated inventory.
- [ ] **Step 2:** `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Files clavity-dotnet/install/clavity-install.Tests.ps1` stays green (unchanged; it was green in the census).

---

### Task 9: Generate the inventory, switch the gate, document, CI job

**Files:**
- Modify: `scripts/tests/_skip-inventory.md` (generated `## linux` section); `justfile:131-138` (`test-scripts` recipe + its comment); `scripts/tests/_partition.md:99` (the `just test-scripts` description); `.github/workflows/ci-scripts.yml` (new job); `clavity-dotnet/ROADMAP.md` §89 (`:4373-…`)

- [ ] **Step 1:** run `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory scripts/tests/_skip-inventory.md` (check mode against the section-less file) → it must exit 1 with `UNAPPROVED SKIP` NOWHERE and `SKIP-INVENTORY: no "## linux" section` (an UNAPPROVED line means a skip lost its tag/reason: fix that row, do not generate over it). Then generate: `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory scripts/tests/_skip-inventory.md -WriteSkipInventory` → `SKIP-INVENTORY written`. READ the generated `## linux` section against Task 8's reconciliation (51 pre-existing + the plan's introduced skips); every row must have a human-meaningful reason (a `-` reason is correct for static tagged rows; a conditional row's reason is its `APPROVED:` text). ADD BY HAND-FREE MEANS the conditional rows this non-root box cannot observe: run the generator once as root is not possible here, so list them through a documented one-off: `sudo -n true && sudo -n pwsh -NoProfile -File … -WriteSkipInventory` if sudo works, else append them under `### conditional` in the exact generated format and say so in the commit body - the rows are the four family B rows (Task 5), the two helper rows in `BashHookHelpers.Tests.ps1` (Task 2), `TestTemp.Tests.ps1` 'the sweep tolerates a child it cannot delete…' and `review-relay-scripts.Tests.ps1` '… (G4)' (Task 6), each with tag `NotAsRoot`. Re-run in check mode until `SKIP-INVENTORY ok` and exit 0.
- [ ] **Step 2 justfile:** `test-scripts:` → `test-scripts *args:` with body `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory scripts/tests/_skip-inventory.md -ShowMessages {{args}}` (same shape as `test-scripts-fast-parallel *args:` at `:111-112`; `release.ps1:151` calls it with no args, so the default `-ThrottleLimit 4` applies there); rewrite the comment block `:131-136`: it still cannot reach `clavity-dotnet/install/clavity-install.Tests.ps1`; one pwsh process per file, 4 at once; the approved-skip gate and the inventory; and state plainly that the parallel engine is MEASURED on Linux only (517 s wall, throttle 4, 2026-10-13) and UNMEASURED on Windows - `just test-scripts -ThrottleLimit 1` is the serial fallback, equivalent to the old single `Invoke-Pester` in strictness. Run `scripts/tests/test-suite-registration.Tests.ps1` and `scripts/tests/run-pester-parallel.Tests.ps1` (the recipe-parsing rows) - both green.
- [ ] **Step 3 docs:** `_partition.md:99` describe the new engine, the vocabulary and the inventory in one sentence; `scripts/tests/README` / `scripts/README.md` inventory rows if `scripts-readme-inventory.Tests.ps1` demands the new file be named (run it). The inventory header already states that the `windows` section is filled by the owner's Windows run and the gate fails closed until then.
- [ ] **Step 4 CI:** add job `dev-scripts-linux` (`runs-on: ubuntu-latest`) to `.github/workflows/ci-scripts.yml` after `dev-scripts` (`:174`): checkout (same deepen step as `dev-scripts` if its roadmap-claims suite needs history - read `:176-200`), install the tools the Windows job installs (read `:200-300`: jq is on ubuntu; yq → mikefarah binary with sha256 check; ast-grep → mirror the Windows job's method; dash present), `Install-Module Pester -MinimumVersion 6.0.0 -MaximumVersion 6.99.99 -Force -SkipPublisherCheck -Scope CurrentUser -ErrorAction Stop`, then `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory scripts/tests/_skip-inventory.md -ShowMessages`. STOP and report if a tool has no simple Linux install. Validate YAML with `yq '.jobs | keys' .github/workflows/ci-scripts.yml` (must list `dev-scripts-linux`). Pin it with one row in `scripts/tests/run-pester-parallel.Tests.ps1`: 'the ci-scripts.yml Linux job runs the runner with the committed inventory' - a regex over the workflow text for `run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory scripts/tests/_skip-inventory.md` (text-level, as `release-workflow-refs.Tests.ps1` does for the release workflows). Add a SECOND row pinning that a PR cannot pass with a stale inventory: 'the committed _skip-inventory.md is current for this OS' is NOT a Pester row (it is the gate itself) - say so in the commit body instead.
- [ ] **Step 5 ROADMAP §89** (`clavity-dotnet/ROADMAP.md:4373`): keep `**Status:** SCHEDULED …` unchanged (item (c), the shared `guardtest` session id, is still open - a separate entry) and append one dated paragraph listing items (a)(b)(d)(e) as closed by this branch with the commit shas. Run `just check-tracker-status`.
- [ ] **Step 6:** `just test-scripts` (the real recipe) → exit 0 on this box. Commit: `ci(scripts): approved-skip gate and generated per-OS skip inventory gate just test-scripts; ubuntu job runs the suites with it`.

---

### Task 3b: the remaining Windows-only reduced PATHs (added by ruling R9, found by the Task 3 review)

Ten suites outside Task 3 still build a Windows-only jq-free PATH (`Join-Path (Split-Path -Parent $bashDir) 'usr\bin'`). On Linux that directory does not exist, so their "jq absent" rows pass because NOTHING is on PATH, not because jq is absent: a hollow pass the goal forbids ("no row passes without running"). They are green today, so the census did not list them.

**Files (Task 3's pattern, same helper):** `scripts/tests/agy-after-reminder.Tests.ps1:10`, `agy-anomaly-capture-reminder.Tests.ps1:21`, `agy-anomaly-dispatch-reminder.Tests.ps1:20`, `agy-anomaly-model-notice.Tests.ps1:22`, `agy-anomaly-reminder.Tests.ps1:7` (eight uses), `agy-discipline-reaching.Tests.ps1:32`, `agy-liveness-check.Tests.ps1:7`, `check-seed-artifacts-synced.Tests.ps1:13`, plus `agy-consult-guard.Tests.ps1:184` (`$noJq`) and `agy-verify-reminder.Tests.ps1:9` (`$script:GitUsr`) - READ the last two first: convert only where the purpose is "a PATH without jq"; if `GitUsr` has another purpose, leave it and say so.

- [ ] **Step 1:** in each file replace the `$bashDir`/`usr\bin` construction with `$script:NoJqPath = New-NoJqPath` (BeforeAll) and add `if (-not $IsWindows) { Remove-TestPath $script:NoJqPath }` to the AfterAll; delete a `$bashDir` that nothing else reads (grep first).
- [ ] **Step 2: Run** each suite before and after. EXPECTED: unchanged counts. A row that was green before and goes RED under the real jq-free PATH was passing vacuously: do NOT edit it - STOP and report the row, the old and new result and why (it is a finding about the hook or the row, for the driver to rule on).
- [ ] **Step 3: Mutant:** with the helper's `rm -f jq` disabled, at least one row per converted suite that asserts the jq-missing behaviour must stay green WHILE the helper's own postcondition throws (so the suite goes red at BeforeAll): name the red suites. Restore the helper.
- [ ] **Step 4: Commit:** `test(linux): the remaining jq-free PATHs use the real helper (no more hollow passes)`.

---

## Stand-downs (adversarial panel, 2026-10-13)

- `DISCARDED-BELOW-FLOOR` (round 4, peer-raised): a NEW bare `-Skip` or `Set-ItResult -Skipped` placed inside a Context that already carries a vocabulary tag is approved by tag inheritance. Guard: approval is not the whole gate - the new row appears in the run's skip set, is not in the committed inventory, and fails `SKIP-INVENTORY STALE` (static tags: a missing/extra static row; conditional tags: an unlisted conditional skip), so the author must regenerate the file and the added row shows in the PR diff (`scripts/run-pester-parallel.ps1`, Task 1 `Test-SkipGate`; Step 1 rows 'fails SKIP-INVENTORY STALE when a static skip is added…' and 'fails when a conditional skip is not listed…'). Likewise an invented `NeedsTool:<name>` is accepted by the vocabulary but is visible in the same diff.
- SUPERSEDED (2026-10-13, owner-accepted AGY-NEGOTIATE, `[VERDICT: ALIGNED]`): the hand-written per-OS baseline file and its wildcard / `when:` stand-downs are replaced by tags + `APPROVED:` reasons + a generated inventory; the gate shape and its six criteria are in the spec, Decision 1. Peer-raised weakness recorded, not fixed: authors must know which of the two approval channels applies; the runner's `UNAPPROVED SKIP` message names the rule.
- `DISCARDED-BELOW-FLOOR`: a stale CONDITIONAL inventory line (its test was deleted) is kept by the generator. Guard: a conditional line grants nothing - approval lives in the test's own tag or reason, and the check is one-way (`scripts/run-pester-parallel.ps1`, Task 1 `Test-SkipGate`); the owner may delete such a line and the next run that skips the row re-adds it.
- `DISCARDED-BELOW-FLOOR` (peer's, accepted): on Linux CI a global npm install puts binaries under `<prefix>/bin`, not `<prefix>` as the Windows job's `GITHUB_PATH` step assumes (`.github/workflows/ci-scripts.yml:284-286`); Task 9 Step 4 already makes tool installation the builder's call with a STOP clause.
- `REJECTED` (not a stand-down, recorded so it is not re-raised): "the new CI job must be added to `merge-gate`'s `needs:`" - `.github/workflows/merge-gate.yml:28-36` enumerates every check-run on the PR head except itself, so a new job is gated automatically.

## After the plan (not tasks for the implementer)

- Owner: run `just test-scripts` on Windows (it fails closed: `SKIP-INVENTORY: no "## windows" section`); then `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory scripts/tests/_skip-inventory.md -WriteSkipInventory` on Windows, review the generated `## windows` diff (the Windows-only rows must NOT appear; the `NeedsTool:*` rows may), commit. If a read-only row shows a skip there, the Task 2 probe is wrong, not the row. Then merge (fast-forward preferred) and `just release -Resume` (drops `a9f5b644`, re-prepares, pre-flight now passes on either OS).
- AGY-CAPSTONE and AGY-TEST-AUDIT on the branch range before declaring it complete (run in a fresh session).
- The two anomalies captured on 2026-10-13 in `.clavity/local-anomalies.md` (raw NUL bytes in `check-peer-reply-citations.Tests.ps1:521` outside the `*.md`-only control-byte gate; the stale cross-reference fixed in Task 5) are for the owner's triage.

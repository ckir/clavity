# Linux + Windows Pester Suites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `just test-scripts` (the `just release` pre-flight at `scripts/release.ps1:151`) exit 0 on Linux and on Windows, with every Windows-only row skipping by name under a reviewed per-OS baseline.

**Architecture:** Shared cross-platform fixture helpers in `scripts/tests/BashHookHelpers.ps1` (+ one link helper in `TestTemp.ps1`); 26 suites ported or gated row-by-row; `scripts/run-pester-parallel.ps1` gains `-Directory` and `-SkipBaseline` and becomes the engine of `just test-scripts`; `scripts/tests/_skip-baseline.md` names every permitted skip per OS.

**Tech Stack:** PowerShell 7 / Pester 6.2 (`Import-Module Pester -MinimumVersion 6.0.0 -MaximumVersion 6.99.99`), bash hooks, `just`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-13-linux-windows-pester-suites-design.md`

## Global Constraints

- Branch `sweep/linux-pester-suites` off `main` = `a9f5b644` (which is the DEAD release commit on top of `e6f28393`; do not drop or rebase it - `just release -Resume` does that later). Never push; the owner pushes.
- Every PORT must go RED under a logic mutant of the guarded code or fixture, and the SPECIFIC new/ported row must be the one that went red. Record the mutant in the commit message body.
- A row that cannot run here (Windows-only subject) SKIPS via Pester `-Skip:(-not $IsWindows)` on the It/Context or `Set-ItResult -Skipped -Because '<reason>'` inside the It; its name goes into `scripts/tests/_skip-baseline.md` in Task 9.
- Run a suite with `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Files <path>[,<path>] -ShowMessages`; its `ok <suite> passed=N failed=0 ... badContainers=0` line is the pass line. Expected per-suite numbers below are the Linux census (`.clavity/scratch/linux-windows-suites/census.txt`) with the named rows moved from failed to passed/skipped; a different passed count is a STOP, not an adaptation.
- Also keep green after each task: `scripts/tests/test-temp-discipline.Tests.ps1` (forbids `[IO.Path]::GetTempPath()` / `$env:TEMP` in suites), `scripts/tests/test-suite-registration.Tests.ps1`, `scripts/tests/scripts-readme-inventory.Tests.ps1`, and `scripts/tests/BashHookHelpers.Tests.ps1`.
- Use `/usr/bin/grep` (the `rtk` shim rewrites `grep` flags). PowerShell here is `pwsh` 7.x on Linux; `$IsWindows` / `$IsLinux` are the automatic variables.
- Commit messages: conventional (`test(...)`, `fix(...)`, `ci(...)`), one task per commit unless a task says otherwise.

## Review Focus

1. A `New-NoJqPath` directory that still reaches `jq` through a symlink of `env` or `sh` + a `#!/usr/bin/env jq` wrapper - the postcondition `command -v jq` under the returned PATH must fail (Task 2 Step 3 control).
2. A `Set-TestPathUnreadable` that reports enforced=true while the hook's BASH process can still read the file (pwsh vs bash divergence, measured before on windows-latest) - the probe must run through `Get-GitBashOrThrow`, not .NET.
3. Running the suites as root: `chmod 000`/`444`/`555` do not bind root; every such row must `Set-ItResult -Skipped` when the helper reports not-enforced, and the baseline lists it as `when:root`.
4. A renamed or deleted row that was listed `always` must FAIL the gate (stale baseline), not silently drop out (Task 1 Step 5 row).
5. A symlink directory loop on Linux must terminate `check-injected-context.ps1`'s walk the way a junction loop does (`Get-WalkIdentity`, `scripts/check-injected-context.ps1:130-155` uses `ReparsePoint` + `.Target`, which .NET sets for symlinks too) - Task 7 Step 4 measures it; a hang is a PRODUCT finding, STOP and report.

---

### Task 1: `run-pester-parallel.ps1` - `-Directory`, skipped names, `-SkipBaseline`

**Files:**
- Modify: `scripts/run-pester-parallel.ps1` (params at :29-38; child summary :51-62; suite resolution :80-84; totals :114-139)
- Create: `scripts/tests/_skip-baseline.md` (format + empty sections; populated in Task 9)
- Test: `scripts/tests/run-pester-parallel.Tests.ps1` (fixture helpers `New-Suite`/`Invoke-Runner` at :11-20)

**Interfaces:**
- Produces: `-Directory <path>` (glob `*.Tests.ps1` recursively, sorted by full path; precedence `-Files` > `-Directory` > `-Recipe`); child JSON field `skippedNames` (array of `ExpandedPath`); `-SkipBaseline <file>` - SCOPED TO THE SUITES THIS INVOCATION RAN: the staleness check considers only `always` rows whose Suite is among the run's suite leaves, so `-Files a,b -SkipBaseline …` or an `-Exclude` lane does not report every other suite's rows as vanished (unlisted-skip detection is unaffected: it only sees rows that ran); exit 1 reasons `SKIP-BASELINE: no "## <os>" section in <file>`, `UNLISTED SKIP <suite leaf> :: <ExpandedPath>`, `BASELINE ROW RAN (or vanished): <line>`; summary line `SKIP-BASELINE os=<os> skipped=<n> listed-always=<a> listed-when=<w> unlisted=<u> stale=<s>`.
- Baseline grammar (one line per entry, inside `## linux` / `## windows` / `## macos`): `- <Suite>.Tests.ps1 | <ExpandedPath -like pattern> | always|when:<token> | <reason>`; an entry line starts with `- `; STRIP that prefix, then split on the first three ` | ` (so the Suite field is `<Suite>.Tests.ps1`, compared `-eq` to the child's file leaf); blank lines and lines not starting with `- ` are prose. OS = `linux` if `$IsLinux`, `windows` if `$IsWindows`, `macos` if `$IsMacOS`. Pattern rules: `-like` semantics, so `[`/`]` in a row name are a character class - write `*` over any bracketed segment; a row name containing ` | ` cannot be written literally - use `*` there too; a pattern with fewer than 8 literal (non-`*`/`?`) characters is REJECTED with exit 1 `SKIP-BASELINE: pattern too broad: <line>` (a bare `*` must not whitelist a suite).

- [ ] **Step 1: Write the failing tests** (append a Context to `scripts/tests/run-pester-parallel.Tests.ps1` inside `Describe 'run-pester-parallel'`):

```powershell
Context '-Directory and -SkipBaseline (the per-OS skip baseline)' {
    BeforeAll {
        $script:Dir = Join-Path $script:Work 'dir'; New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Dir 'skips.Tests.ps1') -Value "Describe 'd' { It 'runs' { 1 | Should -Be 1 }; It 'skips here' -Skip { 1 | Should -Be 2 }; It 'also skips' -Skip { 1 | Should -Be 2 } }"
        Set-Content -LiteralPath (Join-Path $script:Dir 'not-a-suite.ps1') -Value "throw 'must not be globbed'"
        $script:Os = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
        function New-Baseline([string]$Name, [string[]]$Lines, [string]$Os = $script:Os) {
            $p = Join-Path $script:Work "$Name.md"
            Set-Content -LiteralPath $p -Value (@("# baseline", "## $Os") + $Lines)
            $p
        }
    }
    It 'globs only *.Tests.ps1 under -Directory and reports skipped rows by name in the child summary' {
        $r = Invoke-Runner -ExtraArgs @('-Directory', $script:Dir)
        $r.Exit | Should -Be 0 -Because $r.Out
        $r.Out | Should -Match 'passed=1 failed=0 skipped=2'
    }
    It 'passes when every skipped row is listed and every always-line matched' {
        $b = New-Baseline 'ok' @('- skips.Tests.ps1 | d.skips here | always | fixture', '- skips.Tests.ps1 | d.also * | when:demo | fixture')
        $r = Invoke-Runner -ExtraArgs @('-Directory', $script:Dir, '-SkipBaseline', $b)
        $r.Exit | Should -Be 0 -Because $r.Out
        $r.Out | Should -Match "SKIP-BASELINE os=$($script:Os) skipped=2 listed-always=1 listed-when=1 unlisted=0 stale=0"
    }
    It 'fails and names an UNLISTED skip in paste-ready form' {
        $b = New-Baseline 'unlisted' @('- skips.Tests.ps1 | d.skips here | always | fixture')
        $r = Invoke-Runner -ExtraArgs @('-Directory', $script:Dir, '-SkipBaseline', $b)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'UNLISTED SKIP skips\.Tests\.ps1 :: d\.also skips'
        $r.Out | Should -Match '- skips\.Tests\.ps1 \| d\.also skips \| always \| <reason>'
    }
    It 'fails when an always-line matched no skipped row (a renamed or un-skipped row makes the baseline stale)' {
        $b = New-Baseline 'stale' @('- skips.Tests.ps1 | d.skips here | always | fixture', '- skips.Tests.ps1 | d.also * | always | fixture', '- skips.Tests.ps1 | d.gone | always | renamed')
        $r = Invoke-Runner -ExtraArgs @('-Directory', $script:Dir, '-SkipBaseline', $b)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'BASELINE ROW RAN \(or vanished\): - skips\.Tests\.ps1 \| d\.gone \| always \| renamed'
    }
    It 'scopes the staleness check to the suites that ran, so a subset run does not report other suites as vanished' {
        $b = New-Baseline 'subset' @('- skips.Tests.ps1 | d.* | always | fixture', '- other.Tests.ps1 | o.never ran here | always | belongs to a suite not in this run')
        $r = Invoke-Runner -ExtraArgs @('-Directory', $script:Dir, '-SkipBaseline', $b)
        $r.Exit | Should -Be 0 -Because $r.Out
        $r.Out | Should -Match 'stale=0'
    }
    It 'does not fail on a when-line that matched nothing' {
        $b = New-Baseline 'when' @('- skips.Tests.ps1 | d.* | always | fixture', '- skips.Tests.ps1 | d.never | when:tool | fixture')
        $r = Invoke-Runner -ExtraArgs @('-Directory', $script:Dir, '-SkipBaseline', $b)
        $r.Exit | Should -Be 0 -Because $r.Out
    }
    It 'fails CLOSED when the file has no section for this OS, and prints every skip in paste-ready form' {
        $b = New-Baseline 'other-os' @() -Os 'plan9'
        $r = Invoke-Runner -ExtraArgs @('-Directory', $script:Dir, '-SkipBaseline', $b)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match "SKIP-BASELINE: no `"## $($script:Os)`" section"
        $r.Out | Should -Match '- skips\.Tests\.ps1 \| d\.skips here \| always \| <reason>'
    }
    It 'rejects a pattern too broad to name anything (fewer than 8 literal characters)' {
        $b = New-Baseline 'broad' @('- skips.Tests.ps1 | * | always | everything')
        $r = Invoke-Runner -ExtraArgs @('-Directory', $script:Dir, '-SkipBaseline', $b)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'SKIP-BASELINE: pattern too broad: - skips\.Tests\.ps1 \| \* \| always \| everything'
    }
    It 'a baseline failure alone makes the exit 1 even when every test passed' {
        $b = New-Baseline 'only' @()
        $r = Invoke-Runner -ExtraArgs @('-Directory', $script:Dir, '-SkipBaseline', $b)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'failed=0'
    }
}
```

- [ ] **Step 2: Run the suite; expect the 9 new rows to FAIL** (`-Directory`/`-SkipBaseline` are unknown parameters today): `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Files scripts/tests/run-pester-parallel.Tests.ps1 -ShowMessages` → `FAIL run-pester-parallel.Tests.ps1 ... failed=9`.

- [ ] **Step 3: Implement in `scripts/run-pester-parallel.ps1`:**
  - params: add `[string]$Directory` and `[string]$SkipBaseline`; document both in the comment header (`.PARAMETER` lines) and note `-Files` > `-Directory` > `-Recipe`.
  - child (:51-62): add `skippedNames = @($r.Skipped | ForEach-Object { [string]$_.ExpandedPath })` to `$summary`.
  - resolution (:80-84): `elseif ($Directory) { $dirPath = if ([IO.Path]::IsPathRooted($Directory)) { $Directory } else { Join-Path $root $Directory }; $suites = @(Get-ChildItem -LiteralPath $dirPath -Recurse -Filter '*.Tests.ps1' -File | Sort-Object FullName | ForEach-Object FullName) }`; a `-Directory` that does not exist exits 1 with `run-pester-parallel: -Directory '<path>' does not exist` (an empty gate is not a green gate - same rule as :98). `-SkipBaseline` resolves relative to `$root` the same way.
  - after the TOTAL line (:135-136) and before the exit (:138): when `$SkipBaseline` is set, implement `Test-SkipBaseline` (functions `Read-SkipBaseline([string]$File, [string]$Os)` → rows `{Suite, Pattern, Kind, Token, Reason, Line}`; matching: `$leaf -eq $row.Suite -and $path -like $row.Pattern`); print each `UNLISTED SKIP <leaf> :: <path>` followed by the paste line `- <leaf> | <path> | always | <reason>`; print each stale `always` row; print the summary line; set `$baselineFailed`. Exit 1 if `$tot.failed -gt 0 -or $tot.bad -gt 0 -or $tot.noresult -gt 0 -or $baselineFailed`.
  - Pester's `ExpandedPath` for a skipped It is `<Describe>.<Context>.<It>` with `.` separators (as `failedNames` already uses).

- [ ] **Step 4: Create `scripts/tests/_skip-baseline.md`** with a prose header stating the grammar (copy the Interfaces block above), the three rules (unlisted skip fails; `always` must match; `when:` may run), and the empty sections `## linux`, `## windows` (with a comment line `<!-- UNMEASURED 2026-10-13: fill from the owner's Windows run; the gate fails closed until then -->`), `## macos`.

- [ ] **Step 5: Run the suite; expect all green:** same command → `ok   run-pester-parallel.Tests.ps1 passed=<N+9> failed=0 skipped=0`, where N is the suite's passed count at Step 2 (read it off that run; the census ran this suite green). Mutant: in `Test-SkipBaseline` change the stale check to never flag (`$stale = @()`) → the row 'fails when an always-line matched no skipped row' must be the one that goes red; revert.

- [ ] **Step 6: Commit:** `test(runner): -Directory, skipped-row names and a per-OS -SkipBaseline gate`.

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
            if (-not $enforced) { Set-ItResult -Skipped -Because 'this user (root?) is not bound by the deny'; return }
            & (Get-GitBashOrThrow) -c 'cat "$1" >/dev/null 2>&1 && echo READ || echo blocked' _ ($f -replace '\\','/') | Should -Be 'blocked'
        } finally { Restore-TestPathReadable -Path $f }
        & (Get-GitBashOrThrow) -c 'cat "$1" >/dev/null 2>&1 && echo READ || echo blocked' _ ($f -replace '\\','/') | Should -Be 'READ'
    }
    It 'Set-TestFileReadOnly makes an append fail, and Clear-TestFileReadOnly undoes it' {
        $f = Join-Path $script:xpDir 'ro.txt'; Set-Content -LiteralPath $f -Value 'x'
        $enforced = Set-TestFileReadOnly -Path $f
        try {
            if (-not $enforced) { Set-ItResult -Skipped -Because 'this user (root?) is not bound by read-only'; return }
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

- [ ] **Step 4: Gate the Job Object Context** `:120` → `Context 'Measure-BashHookProcesses (Job Object process counter)' -Skip:(-not $IsWindows) {` with a one-line comment: Win32 Job Objects; the Linux budget is not this quantity (spec non-goal).

- [ ] **Step 5: Run; expect** `ok   BashHookHelpers.Tests.ps1 passed=15 failed=0 skipped=7` (on a box running as root the two permission rows skip instead: `passed=13 skipped=9` - say so in the report; those two are `when:root` baseline lines in Task 9). Also `test-temp-discipline.Tests.ps1` green. Mutant: in `New-NoJqPath` drop the `jq|jq.exe` exclusion → 'New-NoJqPath hides jq…' AND the helper's own postcondition must go red; revert. Mutant 2: make `Set-TestPathUnreadable` return `$true` without calling chmod/icacls → its row goes red.

- [ ] **Step 6: Commit:** `test(helpers): cross-platform fixture helpers (no-jq PATH, unreadable/read-only files, shim exec bits, cygpath prelude, dir links)`.

---

### Task 3: Family A skips + family C no-jq ports

**Files:**
- Modify: `scripts/tests/hook-spawn-budget.Tests.ps1:50,74,100`
- Modify: `scripts/tests/agy-test-audit-reminder.Tests.ps1:8`, `scripts/tests/agy-seam-inject.Tests.ps1:12`, `scripts/tests/agy-consult-recovery.Tests.ps1:307-309`, `scripts/tests/agy-inbox-snapshot.Tests.ps1:267,273,282,292-296,463-464,476-481`, `scripts/tests/assertion-strength-reminder.Tests.ps1:40-47,244-248,295-299`, `scripts/tests/agy-anomaly-reminder.Tests.ps1:162-175`
- Oracles: each suite's own "jq genuinely absent" CONTROL rows (`assertion-strength-reminder.Tests.ps1:245-248`, `agy-inbox-snapshot.Tests.ps1:476-481`) stay and must pass; the hook-spawn census/debt rows (`:29`, `:39`) keep passing.

- [ ] **Step 1 (A):** append ` -Skip:(-not $IsWindows)` before the opening `{` on the three It lines `hook-spawn-budget.Tests.ps1:50` (`'<Hook>: <Name> starts at most <Max> processes beyond bash boot' -ForEach $Rows -Tag 'row'`), `:74` (`'<Hook>: <Name> prints the same on the bash 3.2 code path' -ForEach $Rows -Tag 'compat'`), `:100` (`'agy-consult-recovery.sh costs the same with 1 seam and with 1000 …' -Tag 'scaling'`). Add a comment above `Describe` (:22): the counter is a Win32 Job Object; 167 rows skip off-Windows and are listed in `_skip-baseline.md`. Leave `hook-spawn-budget.Rows.ps1:245,253` as they are (inside row closures that no longer run here).
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
- [ ] **Step 2:** `agy-anomaly-reminder.Tests.ps1:653-663`: replace the `icacls` + bash probe with `if (-not (Set-TestPathUnreadable -Path $f)) { Set-ItResult -Skipped -Because 'this host does not enforce the read deny against the hook process'; return }`; `:683` → `if ($w) { Restore-TestPathReadable -Path (Join-Path $w '.clavity/local-anomalies.md') }`. Same shape at `docs-audit-reminder.Tests.ps1:147-149` and `:153`.
- [ ] **Step 3:** `agy-shield-lib.Tests.ps1:880/:882` → `$enforced = Set-TestFileReadOnly -Path $shieldPath` / `finally { Clear-TestFileReadOnly -Path $shieldPath }`, with `if (-not $enforced) { Set-ItResult -Skipped -Because 'read-only is not enforced for this user'; return }` BEFORE the `try`; same at `:958/:966` for `$shield`. Rewrite the comment `:944-945` ("attrib is Windows-only, and so is this suite") to state the helper and that the suite runs on both OSes.
- [ ] **Step 4:** `agy-discipline-reaching.Tests.ps1:460`: `(agy-ledger-lib.Tests.ps1:413)` → `(agy-ledger-lib.Tests.ps1, It 'answers UNREADABLE - not ABSENT - when the ledger cannot be OPENED')` - the line number was stale (413 is `New-LedgerRepo`; the gated icacls is at 422).
- [ ] **Step 5: Run** the four suites + `agy-discipline-reaching.Tests.ps1`. Expect: migrate-inbox `16/0`; agy-anomaly-reminder `39/0`; docs-audit-reminder `13/0`; agy-shield-lib `passed=54 failed=3` (3 `LastWriteTime` rows remain for Task 6); discipline-reaching unchanged. If this box runs as root (`id -u` = 0) the rows SKIP instead - say so in the report; they are `when:root` in the baseline.
- [ ] **Step 6: Mutant:** make `Set-TestPathUnreadable` skip the chmod → the docs-audit-reminder row 'reports an UNREADABLE view…' goes red (the hook reads the file and does not say "not a recognisable generated view"); revert.
- [ ] **Step 7: Commit:** `test(linux): unreadable and read-only fixtures through the shared helpers`.

---

### Task 6: Family G ports (paths, drives, `.cmd`, junctions, locks)

**Files:**
- Modify: `scripts/tests/path-lib.Tests.ps1:10-16,22,41,63,68,79,96`; `installer/_shared/register-plugin.ps1:59-60`; `scripts/tests/register-plugin.Tests.ps1:27,88-90`; `scripts/tests/check-plugin-drift.Tests.ps1:299,305`; `scripts/tests/TestTemp.Tests.ps1:52,57,68-80`; `scripts/tests/check-injected-context.Tests.ps1:1128,1167`; `scripts/tests/check-capstone-new-code.Tests.ps1:818,844`; `scripts/tests/check-installer-ascii.Tests.ps1:39`; `scripts/tests/drain-lib.Tests.ps1:530-545`; `scripts/tests/review-relay-scripts.Tests.ps1:453-459`; `scripts/tests/agy-shield-lib.Tests.ps1` (the 3 `LastWriteTime` rows - find them by the census message "The property 'LastWriteTime(Utc)' cannot be found")
- Oracles: `scripts/lib/path-lib.ps1:92-98` ("OS separators are preserved on purpose"); `scripts/check-injected-context.ps1:130-155` `Get-WalkIdentity`; `review-relay/scripts/collect.ps1:107-109` (a failed `Remove-Item` of an old reply aborts the rebuild); `scripts/drain-lib.ps1:292-302` `Resolve-CurateCommitExe`.

- [ ] **Step 1 path-lib:** in BeforeAll add `$script:Expected = Join-Path 'installer' 'probe.ps1'`; replace the literal `'installer\probe.ps1'` at `:22,:41,:63,:68,:79,:96` with `$script:Expected`. Rows `:44` ('normalises an UPPERCASE root') and `:49` ('accepts a PATH spelled in different casing…') get `-Skip:(-not $IsWindows)` (case-insensitive NTFS is the subject; `:58`'s `'INSTALLER\PROBE.PS1'` stays).
- [ ] **Step 2 register-plugin (PRODUCT, 5.1-compatible):** `installer/_shared/register-plugin.ps1:59-60` `Join-Path $env:USERPROFILE '.claude'` / `'.gemini'` → `Join-Path $HOME '.claude'` / `'.gemini'` (`$HOME` = `%USERPROFILE%` on Windows PowerShell 5.1 and pwsh 7). Tests: `:27` `-like '*\.gemini'` → `-like '*.gemini'`; `:88-90` → `$appDir = Join-Path $TestDrive 'app'`, `-AppDir $appDir`, expected `"plugin install $(Join-Path (Join-Path $appDir 'plugins') 'commonmemory')"`. STOP if `Install-AgyPlugin` (`register-plugin.ps1:140-160`) tests the directory's existence (then create it).
- [ ] **Step 3 check-plugin-drift:** `:299` `Join-Path $env:TEMP $leaf` → `Join-Path (Get-PSDrive -Name Temp).Root $leaf`; `:305` `"Temp:\$leaf"` → `Join-Path 'Temp:' $leaf`. The row's own guard at `:307` (`.Path` must differ from `.ProviderPath`) is the oracle. SAME COMMIT: `scripts/tests/test-temp-discipline.Tests.ps1:15` holds an exemption pinned to the exact line `$i = Join-Path $env:TEMP $leaf` and its row 'every exemption still matches a real line (a stale exemption is a hole)' (`:35-39`) goes red the moment that line changes - delete that one exemption entry (the `check-plugin-drift.Tests.ps1` hashtable). If the discipline's scan then flags the new `Get-PSDrive` line, STOP and report (do not add a new exemption on your own).
- [ ] **Step 4 TestTemp.Tests:** `:52` and `:57` `New-Item -ItemType Junction -Path X -Target Y` → `New-TestDirectoryLink -Path X -Target Y`. Locked-child row `:68-80`: keep the `FileShare.None` handle on Windows; on non-Windows replace it with `& chmod 555 $locked` (an unwritable directory makes `held.txt` undeletable), skip with `Set-ItResult -Skipped -Because 'root is not bound by directory permissions'` when `(-not $IsWindows) -and ((& id -u) -eq '0')` (the `-not $IsWindows` MUST come first: `id` is not a PowerShell command on Windows), and `finally { if ($IsWindows) { $fs.Dispose() } else { & chmod 755 $locked } }`. Assertions `:77-78` unchanged.
- [ ] **Step 5 check-injected-context:** `:1128` → `New-TestDirectoryLink -Path (Join-Path $d 'seed/sub/loop') -Target (Join-Path $d 'seed') | Out-Null`; `:1167` → `New-TestDirectoryLink -Path (Join-Path $d 'seed/alias') -Target (Join-Path $d 'commonmemory') | Out-Null`; the guards `:1131-1132,:1168-1169` stay. MEASURE: the row 'a directory junction pointing at an ancestor does not walk forever' must finish in seconds; if the checker hangs or reports `seed/a.md` twice, STOP: that is a product finding in `Get-WalkIdentity`, report it, do not adapt the test.
- [ ] **Step 6 check-capstone-new-code:** `:818` → `$parts = @($pwshDir, $gitDir); if ($IsWindows) { $parts += @($env:SystemRoot, (Join-Path $env:SystemRoot 'System32')) }; $env:PATH = ($parts -join [IO.Path]::PathSeparator)`; `:844` → `if ($IsWindows) { Set-Content -Path (Join-Path $shim 'ast-grep.cmd') -Value @('@echo off', 'exit /b 8') } else { Set-Content -Path (Join-Path $shim 'ast-grep') -Value @('#!/usr/bin/env bash', 'exit 8'); & bash -c 'chmod +x "$1"' _ (Join-Path $shim 'ast-grep') }` (this suite does not load BashHookHelpers; `bash` is on PATH here); `:854` `$env:PATH = "$shim;$env:PATH"` → `$env:PATH = "$shim$([IO.Path]::PathSeparator)$env:PATH"` (the only `;$env:PATH` join under `scripts/tests`, measured 2026-10-13). Expected: both rows exit 2, and `:858` sees `ast-grep exited`.
- [ ] **Step 7 check-installer-ascii:** BOTH assertions, `:39` AND `:40`: `$rel1 = [regex]::Escape((Join-Path 'installer' 'offender.ps1')); $rel2 = [regex]::Escape((Join-Path (Join-Path 'installer' 'sub') 'second.ps1'))`; `$plain | Should -Match "(?m)^  $rel1 - 1 non-ASCII byte\(s\)\r?$"` and `$plain | Should -Match "(?m)^  $rel2 - 2 non-ASCII byte\(s\)\r?$"`. Grep the suite for any further `\\` literal before committing.
- [ ] **Step 8 drain-lib:** `:533-534` → `$ext = if ($IsWindows) { '.cmd' } else { '' }`; write `clavity-ls$ext` / `clavity$ext`; non-Windows content `@('#!/usr/bin/env bash', 'echo dotnet')` / `'echo classic'` + `& bash -c 'chmod +x "$@"' _ <both paths>`; `:543` → `(Resolve-CurateCommitExe) | Should -Be (Join-Path $binDir "clavity-ls$ext")`; adjust the classic fallback assertion that follows (`:545-560`, read it) the same way; rewrite the comment `:527` (PATHEXT is Windows-only).
- [ ] **Step 9 review-relay-scripts G4:** `:453-459`: Windows keeps the stream; non-Windows: `& chmod 555 (Join-Path $script:RoundDir 'replies')` (the rebuild's `Remove-Item` of the old copy at `collect.ps1:108` then fails), `finally { … else { & chmod 755 <replies dir> } }`, skip when `(-not $IsWindows) -and ((& id -u) -eq '0')` (same ordering rule as Step 4). Assertions `:456-457` unchanged. MEASURE before accepting: if under the Linux lock `collect.ps1` exits 0 or leaves a `collected.md`, that is a PRODUCT finding (the rebuild does not stop on a failed `Remove-Item`) - STOP and report it; do not weaken the assertions.
- [ ] **Step 10 agy-shield-lib `LastWriteTime` rows (MEASURED 2026-10-13):** `agy-shield-lib.Tests.ps1:540` `(Get-Item -LiteralPath $stale).LastWriteTime = …`, `:810` `(Get-Item -LiteralPath $old).LastWriteTimeUtc = …`, `:832-833` (`$mid`, `$old`) call `Get-Item -LiteralPath` on DOT-FILES (`.clavity/.gitignore.tmp.STALE`, `.clavity/.clavity-shield-*`); on Linux pwsh treats a dot-file as Hidden and `Get-Item` without `-Force` returns nothing, so the property set lands on `$null`. Fix: add `-Force` to those four `Get-Item` calls (the pattern `TestTemp.Tests.ps1:58` already uses). Grep the suite for any other `Get-Item -LiteralPath` whose argument is a dot-file and add `-Force` there too; list them in the commit body.
- [ ] **Step 11: Run** all 11 suites. Expected lines (census counts with the named rows moved): path-lib `passed=14 failed=0 skipped=4`; register-plugin `18/0`; check-plugin-drift `passed=17 failed=0 skipped=1`; TestTemp `16/0`; check-injected-context `passed=168 failed=0 skipped=2`; check-capstone-new-code `35/0`; check-installer-ascii `passed=3 failed=0 skipped=1`; drain-lib `36/0`; review-relay-scripts `38/0`; agy-shield-lib `57/0`; agy-mark unchanged until Task 7. TestTemp/review-relay show a skip instead only when running as root.
- [ ] **Step 12: Mutants** (one per class, name the red row in the commit body): (a) `path-lib.ps1:98` return `$Path.Substring($normalised.Length)` without `TrimStart` → path-lib control row red; (b) `register-plugin.ps1:60` back to `$env:USERPROFILE` → 'reports agy present when only its config dir exists' red; (c) `check-capstone-new-code.ps1` treat ast-grep failure as "no new code" (exit 0) → 'PRESENT but FAILS' red; (d) in the G4 row drop the non-Windows `chmod 555` → the row goes red because the rebuild now succeeds (a fixture mutant: it proves the lock is what the row measures).
- [ ] **Step 13: Commit** (two commits): `fix(installer): register-plugin resolves the home dir through $HOME` and `test(linux): platform-neutral paths, drives, shims, directory links and undeletable children`.

---

### Task 7: Family H + the remaining Windows-only rows (skips)

**Files:**
- Modify: `scripts/tests/installer-user-path.Tests.ps1:81`; `scripts/tests/agy-mark.Tests.ps1:66`

- [ ] **Step 1:** `installer-user-path.Tests.ps1:81` → `Context 'behavioural - the include, compiled by ISCC and run' -Skip:(-not $IsWindows) {` (its BeforeAll at `:87` reads `HKCU:\Environment`; on Windows without ISCC the rows still `Set-ItResult -Skipped` at `:222,:236,:251,:258` - a `when:no-iscc` baseline entry).
- [ ] **Step 2:** `agy-mark.Tests.ps1:66` → `It 'RESOLVES ITS OWN HELPERS when invoked by an all-BACKSLASH Windows path' -Skip:(-not $IsWindows) {` (the input class exists only on Windows).
- [ ] **Step 3: Run** both: installer-user-path `passed=3 failed=0 skipped=4`; agy-mark `passed=49 failed=0 skipped=1`.
- [ ] **Step 4: Commit:** `test(linux): skip the ISCC/registry context and the backslash-path row off-Windows`.

---

### Task 8: Full Linux run (driver-measured) and remaining red rows

- [ ] **Step 1 (DRIVER, top level, backgrounded, no tool calls during the run):** `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipBaseline scripts/tests/_skip-baseline.md -ShowMessages > <scratch>/census2.txt 2>&1` (WITH the still-empty baseline, on purpose: every skip prints as `UNLISTED SKIP`). Expected: `TOTAL files=82 … failed=0 badContainers=0 noResult=0`, exit 1 only because of the baseline. Any `FAILED` line is a row this plan missed: classify by family and fold into the owning task's pattern (new commit), or STOP if it is a product finding. THEN RECONCILE THE SKIP INVENTORY before Task 9 touches the baseline: the UNLISTED set must equal (a) the 51 skips of the 2026-10-13 census (pre-existing `Set-ItResult -Skipped` / `-Skip:` rows) plus (b) exactly the skips this plan introduced - hook-spawn-budget 167 (Task 3), BashHookHelpers Job Object Context 7 (Task 2), installer-user-path 4 (Task 7), path-lib 2 (Task 6 Step 1), agy-mark 1 (Task 7), and 0 root-conditional rows on this non-root box. A skip outside (a)+(b) is an UNINTENDED skip: STOP and find the over-broad `-Skip:` or the probe that reported not-enforced; it must never reach the baseline.
- [ ] **Step 2:** `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Files clavity-dotnet/install/clavity-install.Tests.ps1` stays green (unchanged; it was green in the census).

---

### Task 9: Populate the baseline, switch the gate, document, CI job

**Files:**
- Modify: `scripts/tests/_skip-baseline.md` (`## linux` section); `justfile:131-138` (`test-scripts` recipe + its comment); `scripts/tests/_partition.md:99` (the `just test-scripts` description); `.github/workflows/ci-scripts.yml` (new job); `clavity-dotnet/ROADMAP.md` §89 (`:4373-…`)

- [ ] **Step 1:** run `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipBaseline scripts/tests/_skip-baseline.md` → exit 1 with every skip printed as `- <suite> | <path> | always | <reason>`. For each line, READ the row and write the real reason; collapse the 166 hook-spawn rows to two wildcard lines (`hook spawn budget.*starts at most * processes beyond bash boot`, `hook spawn budget.*prints the same on the bash 3.2 code path`) plus the scaling row; mark condition-dependent skips `when:<token>` (`when:no-iscc` is NOT a Linux entry - on Linux the Context is `always`; `when:no-8.3`, `when:root`, `when:no-dash`, `when:no-yq` and the suites' other pre-existing `Set-ItResult -Skipped` reasons as found). Then ADD the `when:root` lines the run cannot print (this box is not root): one per row that skips through a helper's enforced=false or an `id -u` check - the four family B rows (Task 5), the two helper rows in `BashHookHelpers.Tests.ps1` (Task 2), `TestTemp.Tests.ps1` 'the sweep tolerates a child it cannot delete…' and `review-relay-scripts.Tests.ps1` '… (G4)' (Task 6). Re-run until `SKIP-BASELINE … unlisted=0 stale=0` and exit 0.
- [ ] **Step 2 justfile:** `test-scripts:` → `test-scripts *args:` with body `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipBaseline scripts/tests/_skip-baseline.md -ShowMessages {{args}}` (same shape as `test-scripts-fast-parallel *args:` at `:111-112`; `release.ps1:151` calls it with no args, so the default `-ThrottleLimit 4` applies there); rewrite the comment block `:131-136`: it still cannot reach `clavity-dotnet/install/clavity-install.Tests.ps1`; one pwsh process per file, 4 at once; the baseline; and state plainly that the parallel engine is MEASURED on Linux only (517 s wall, throttle 4, 2026-10-13) and UNMEASURED on Windows - `just test-scripts -ThrottleLimit 1` is the serial fallback, equivalent to the old single `Invoke-Pester` in strictness. Run `scripts/tests/test-suite-registration.Tests.ps1` and `scripts/tests/run-pester-parallel.Tests.ps1` (the recipe-parsing rows) - both green.
- [ ] **Step 3 docs:** `_partition.md:99` describe the new engine + baseline in one sentence; `scripts/tests/_skip-baseline.md` header states that the `## windows` section is filled from the owner's Windows run and fails closed until then.
- [ ] **Step 4 CI:** add job `dev-scripts-linux` (`runs-on: ubuntu-latest`) to `.github/workflows/ci-scripts.yml` after `dev-scripts` (`:174`): checkout (same deepen step as `dev-scripts` if its roadmap-claims suite needs history - read `:176-200`), install the tools the Windows job installs (read `:200-300`: jq is on ubuntu; yq → mikefarah binary with sha256 check; ast-grep → mirror the Windows job's method; dash present), `Install-Module Pester -MinimumVersion 6.0.0 -MaximumVersion 6.99.99 -Force -SkipPublisherCheck -Scope CurrentUser -ErrorAction Stop`, then `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipBaseline scripts/tests/_skip-baseline.md -ShowMessages`. STOP and report if a tool has no simple Linux install. Validate YAML with `yq '.jobs | keys' .github/workflows/ci-scripts.yml` (must list `dev-scripts-linux`). Pin it with one row in `scripts/tests/run-pester-parallel.Tests.ps1`: 'the ci-scripts.yml Linux job runs the runner with the committed baseline' - a regex over the workflow text for `run-pester-parallel.ps1 -Directory scripts/tests -SkipBaseline scripts/tests/_skip-baseline.md` (text-level, as `release-workflow-refs.Tests.ps1` does for the release workflows).
- [ ] **Step 5 ROADMAP §89** (`clavity-dotnet/ROADMAP.md:4373`): keep `**Status:** SCHEDULED …` unchanged (item (c), the shared `guardtest` session id, is still open - a separate entry) and append one dated paragraph listing items (a)(b)(d)(e) as closed by this branch with the commit shas. Run `just check-tracker-status`.
- [ ] **Step 6:** `just test-scripts` (the real recipe) → exit 0 on this box. Commit: `ci(scripts): per-OS skip baseline gates just test-scripts; ubuntu job runs the suites with it`.

---

## Stand-downs (adversarial panel, 2026-10-13)

- `DISCARDED-BELOW-FLOOR`: a wildcard baseline line also admits a NEW row that happens to match it (e.g. a new hook-spawn-budget row). Guard: wildcards are used only for the two `-ForEach $Rows` It blocks (`hook-spawn-budget.Tests.ps1:50,74`), whose rows all come from one table and all legitimately skip off-Windows; every other line names one row; the 8-literal-character floor (Task 1) forbids a bare `*`.
- `DISCARDED-BELOW-FLOOR` (peer's, accepted): on Linux CI a global npm install puts binaries under `<prefix>/bin`, not `<prefix>` as the Windows job's `GITHUB_PATH` step assumes (`.github/workflows/ci-scripts.yml:284-286`); Task 9 Step 4 already makes tool installation the builder's call with a STOP clause.
- `DISCARDED-BELOW-FLOOR`: a `when:<token>` line can mark a permanently-skipping row as conditional and so hide it from the `always` staleness check. Guard: the baseline file is a committed artifact reviewed in the PR diff, every line carries a human-written reason, and the runner prints `listed-when=<n>` on every run so growth is visible; the gate's job is to catch UNLISTED skips, which this cannot cause (`scripts/run-pester-parallel.ps1`, Task 1 `Test-SkipBaseline`).
- `REJECTED` (not a stand-down, recorded so it is not re-raised): "the new CI job must be added to `merge-gate`'s `needs:`" - `.github/workflows/merge-gate.yml:28-36` enumerates every check-run on the PR head except itself, so a new job is gated automatically.

## After the plan (not tasks for the implementer)

- Owner: run `just test-scripts` on Windows; paste the printed `## windows` lines into `_skip-baseline.md` with reasons; commit. Then merge (fast-forward preferred) and `just release -Resume` (drops `a9f5b644`, re-prepares, pre-flight now passes on either OS).
- AGY-CAPSTONE and AGY-TEST-AUDIT on the branch range before declaring it complete (run in a fresh session).
- The two anomalies captured on 2026-10-13 in `.clavity/local-anomalies.md` (raw NUL bytes in `check-peer-reply-citations.Tests.ps1:521` outside the `*.md`-only control-byte gate; the stale cross-reference fixed in Task 5) are for the owner's triage.

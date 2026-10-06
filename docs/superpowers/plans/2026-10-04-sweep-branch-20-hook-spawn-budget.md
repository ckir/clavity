# Sweep Branch 20 - Hook Spawn Budget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** No registered agy hook starts more than 16 processes (3 of them bash's own boot) on any path it can reach. This branch cuts the nine hooks the owner scoped and adds a test suite that keeps every hook under the limit. The census also found eight more hooks over the limit; they go to Branch 21.

**Architecture:** On this machine every process creation costs ~180-360 ms, whatever the process, so a hook's cost is the number of processes it starts (measured, AGY-FIRST seams `hook-perf-agy-first*.md`). A Windows Job Object counts every process a hook run creates (`TotalProcesses`), deterministically. A new Pester suite runs each hook along named paths inside throwaway fixtures and asserts the count. The nine hook rewrites were prototyped and measured in isolated worktrees; they ship here as per-hook patch files beside this plan, plus a short list of corrections per hook.

**Tech Stack:** bash (Git for Windows msys), PowerShell 7 + Pester 5, `Add-Type` C# P/Invoke (kernel32 Job Object API), jq, git.

---

## Rulings this plan executes (owner and driver, 2026-10-04)

Owner rulings (index `project_hook-perf_execution.md`; waivers in `.clavity/agy-marks/skipped.log`):

- **O1. ONE ceiling, every hook, every path:** 16 processes total including 3 for bash boot, as the prototype harness counted them (Git's `bin\bash.exe` launcher + spin bash + exec'd hook bash). The new harness launches `usr\bin\bash.exe` directly (D3), so its boot is 2 and the ceiling is expressed as **13 processes beyond boot**. Same budget, different bookkeeping.
- **O2. The consult path stays as it is:** the consult guard's real-consult path (`agy_guard_quad` + census, ~115 processes a side) moves to a separate branch with its own design consult (ROADMAP section 70, Task 12). This branch only **pins** it so it cannot grow, and adds the fast exit for non-consult calls.
- **O3. Split:** this branch fixes the original nine hooks. The eight census-found hooks (`agy-inbox-snapshot`, `agy-anomaly-reminder`, `agy-verify-reminder`, `docs-audit-reminder`, `fetch-clavity-ls`, `agy-discipline-reaching`, `assertion-strength-reminder`, `migrate-inbox`) are Branch 21. Here they get a passing default-path row each, plus a named debt entry. That leaves the budget suite with exactly ONE red row until Branch 21 lands (the owner chose a visible failure over a pin). **Fork A (owner ruling 2026-10-05, agreed with agy):** CI runs `Invoke-Pester scripts/tests` on every PR (`ci-scripts.yml`, no paths filter by design) and merge-gate guards main and Dependabot auto-merge. So the debt row is RED locally (`just test-scripts-slow`) and SKIPPED when `GITHUB_ACTIONS` is set, with the debt list in the skip reason so every CI log names it.
- **O6. Forks B-D (owner ruling 2026-10-05, agreed with agy after an AGY-FIRST consult):** B - a compaction re-arms the test-audit reminder (Task 5 Step 4(c)); C - CI puts the real jq first on PATH (Task 10 Step 4), verified on the first CI run, with local-only budget rows as the fallback; D - Q1 below is ACCEPTED.
- **O4. Debounce:** `agy-test-audit-reminder.sh` emits at most once per (session, HEAD).
- **O5. Timeouts after re-measure:** this plan's S4 (Task 11).

Driver rulings, each measured (`.clavity/scratch/hook-perf/b20-protos/FINDINGS.md`):

- **D1. `$0` -> directory:** `${0%[/\\]*}`, falling back to `.` when nothing was removed. A bare `${0%/*}` returns `$0` unchanged for `bash 'C:\x\h.sh'` (measured), so the hook would not find its sibling lib. `$(dirname "$0")` costs 2 processes.
- **D2. CRLF:** the Windows `jq.exe` ends its output with CRLF; bash `printf` ends with LF. Where a patch replaces a `jq` emit with `printf`, emit **LF** and drop the prototypes' `$OSTYPE` CR-appending hacks. A trailing CR is JSON whitespace, Claude Code parses either, and `Invoke-BashHook` `.Trim()`s stdout. This is a deliberate byte change on Windows stdout, accepted here.
- **D3. Counter:** launch `<Git>\usr\bin\bash.exe` directly. `<Git>\bin\bash.exe` is a launcher that spawns the real bash; when the job assignment lost that race the child escaped the job, and the counter read 1 (seen on cold first calls). Launching the real bash leaves nothing to race: until released, the spinning process runs builtins only. Calibrated 6/6 stable: boot 2, one external command +2.
- **D4. stdin:** every hook this branch touches reads stdin with the chunked builtin loop. Measured at top level on a 100,056-byte pipe, 3 runs (load uncontrolled: a network probe was running): `read -d ''` 4416 / 3143 / 4163 ms; `read -N 1048576` loop 1112 / 1510 / 1281 ms; `$(cat)` 1666 / 2285 / 1236 ms. The form is:

  ```bash
  input=; while IFS= read -r -N 1048576 _c; do input+=$_c; done; input+=$_c
  ```

- **D5. Debounce state lives outside the repo:** a flat file `${TMPDIR:-/tmp}/claude-agy-test-audit-reminder.<sid>` holding the HEAD it last fired for, written with one `printf >` (the nested-directory + tmp/mv variant measured 17). The hook still "NEVER writes a marker"; a racing reader sees a partial sha and reminds again, which is the safe direction.

**Owner decision (RESOLVED 2026-10-05: accept, ruling O6-D):**

- **Q1. Multi-document settings file.** `agy-liveness-check.sh` today accepts a settings file holding two JSON documents (`{..} {..}`) silently, because `jq -e .` and `jq -s` take a stream. The prototype parses each file with `fromjson`, which rejects it, so such a file is now reported as `settings unreadable` plus the advisory. Claude Code itself rejects such a file, so the new message is the truthful one. Keeping the old behaviour costs extra jq calls and breaks the ceiling with three such files. **Driver recommends: accept** (Task 7 pins it with a row).

## Global rules for every task

- **Pairs are byte-identical.** Every hook under `clavity-dotnet/plugin/hooks/` that also exists under `clavity-classic/plugin/hooks/` must be copied there in the SAME commit (`just seed-sync-check` and the seam-inject suite's mirror row enforce it). `agy-drive-session-reset.sh` is classic-only; `agy-curate-nudge.sh` lives in `agy-autotrain/hooks/` only.
- **Never run two Pester suites at once.** Run a suite in the foreground only when its filtered run finishes well under the 600 s tool cap; `just test-scripts-slow` exceeds it and must be backgrounded.
- **Fixtures never touch the real home or repo.** Every budget row sets `HOME`, `USERPROFILE`, `TMPDIR` and `CLAUDE_PROJECT_DIR` to throwaway directories (`agy-drive-session-reset.sh` deletes files under `~/.clavity`).
- **Stage explicit paths** in every commit. Never `git add -A`. Never stage `.clavity/`.
- **A patch that does not apply is a STATE_MISMATCH.** Stop and report it. Do not hand-merge.

## File structure

| File | Responsibility |
|---|---|
| `scripts/tests/BashHookHelpers.ps1` (modify) | Adds `Get-GitBashCoreOrThrow`, the `ClavityJobCount` type, `Invoke-JobCountedBash` and `Measure-BashHookProcesses`: count every process one hook run creates. |
| `scripts/tests/BashHookHelpers.Tests.ps1` (modify) | Three harness-validation rows (calibration controls). |
| `scripts/tests/hook-spawn-budget.Rows.ps1` (create) | Fixture builders, payload builders, the budget row table, the consult pins, the Branch 21 debt list. Dot-sourced by the suite in discovery AND run. |
| `scripts/tests/hook-spawn-budget.Tests.ps1` (create) | Census row, debt row, one budget row per table entry, the seam-scaling row. |
| `docs/superpowers/plans/2026-10-04-sweep-branch-20-hook-spawn-budget/NN-<hook>.patch` (committed with this plan) | The measured prototype of each hook, against `4f0cb6a7`. Applied by Tasks 3-10. |
| 9 hook files + their classic mirrors (modify) | The rewrites. |
| `scripts/tests/agy-consult-recovery.Tests.ps1`, `agy-test-audit-reminder.Tests.ps1`, `agy-liveness-check.Tests.ps1` (modify) | Rows for the deliberate behaviour changes (classifier, debounce, Q1). |
| `justfile`, `scripts/tests/_partition.md` (modify) | Register the new suite (slow half) and record counts. |
| `clavity-dotnet/plugin/hooks/hooks.json`, `clavity-classic/plugin/hooks/hooks.json` (modify only if Task 11's rule says so) | SessionStart timeouts. |
| `clavity-dotnet/ROADMAP.md` (modify) | Section 69 (Branch 21 hooks) and section 70 (consult-path budget). |

---

### Task 1: Process-counting harness

**Files:**
- Modify: `scripts/tests/BashHookHelpers.ps1` (append after `Invoke-BashHook`, the last function in the file)
- Modify: `scripts/tests/BashHookHelpers.Tests.ps1` (three rows inside `Describe 'BashHookHelpers (harness validation)'`)

**Oracle:** the calibration measured 2026-10-04 (FINDINGS ruling 3): `usr\bin\bash.exe` boot = 2, one external = +2, run-to-run identical.

- [ ] **Step 1: Write the failing harness rows.** Append inside the existing `Describe 'BashHookHelpers (harness validation)'` block, after its last `It`:

```powershell
    Context 'Measure-BashHookProcesses (Job Object process counter)' {
        BeforeAll {
            $script:countDir = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-count-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:countDir -Force | Out-Null
            $script:builtinsOnly = Join-Path $script:countDir 'builtins.sh'
            $script:oneExternal  = Join-Path $script:countDir 'external.sh'
            $script:echoEnv      = Join-Path $script:countDir 'echoenv.sh'
            Set-Content -LiteralPath $script:builtinsOnly -Value "x=1; [ -n `"`$x`" ] && y=2" -Encoding ascii
            Set-Content -LiteralPath $script:oneExternal  -Value '/usr/bin/true' -Encoding ascii
            Set-Content -LiteralPath $script:echoEnv      -Value 'printf %s "$SPD_COUNT_PROBE"' -Encoding ascii
            $script:whichGit     = Join-Path $script:countDir 'whichgit.sh'
            Set-Content -LiteralPath $script:whichGit     -Value 'command -v git' -Encoding ascii
        }
        AfterAll { Remove-Item -LiteralPath $script:countDir -Recurse -Force -ErrorAction SilentlyContinue }

        It 'counts NOTHING beyond bash boot for a builtins-only script' {
            (Measure-BashHookProcesses -HookPath $script:builtinsOnly).Spawned | Should -Be 0
        }
        It 'counts exactly the two processes one external command costs (the failing control: it must SEE a child)' {
            # A counter that cannot return a non-zero answer certifies every hook. This row is what proves it can.
            (Measure-BashHookProcesses -HookPath $script:oneExternal).Spawned | Should -Be 2
        }
        It 'passes -Env to the hook WITHOUT changing this process environment' {
            $r = Measure-BashHookProcesses -HookPath $script:echoEnv -Env @{ SPD_COUNT_PROBE = 'seen' }
            $r.StdOut | Should -BeExactly 'seen'
            [Environment]::GetEnvironmentVariable('SPD_COUNT_PROBE') | Should -BeNullOrEmpty
        }
        It 'resolves the real git a hook gets under Git''s launcher, even from a bare PATH and no MSYSTEM' {
            # agy panel R3: without the launcher's PATH setup a hook found no git and degraded silently.
            $r = Measure-BashHookProcesses -HookPath $script:whichGit -Env @{ MSYSTEM = $null; PATH = 'C:\Windows\System32' }
            $r.StdOut | Should -BeExactly '/mingw64/bin/git'
        }
    }
```

- [ ] **Step 2: Run the rows; they must fail.**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/BashHookHelpers.Tests.ps1 -Output Detailed -CI"`
Expected: 4 failures, each `The term 'Measure-BashHookProcesses' is not recognized`; the 8 existing rows pass.

- [ ] **Step 3: Implement the harness.** Append to `scripts/tests/BashHookHelpers.ps1`:

```powershell
function Get-GitBashCoreOrThrow {
    # THE COUNTER MUST HOLD THE REAL BASH, NOT GIT'S LAUNCHER. <Git>\bin\bash.exe is a small launcher that
    # starts <Git>\usr\bin\bash.exe as a CHILD. The Job Object is attached to the process we start, after it
    # starts - so when the launcher wins that race its child is already outside the job, and the count reads
    # 1 for a run that started a dozen processes. MEASURED 2026-10-04: cold first calls returned 1, warm calls
    # 3. Started directly, the real bash spins on builtins until released, so there is nothing to race.
    $launcher = Get-GitBashOrThrow
    if ($launcher -match '\\usr\\bin\\bash\.exe$') { return $launcher }
    $core = Join-Path (Split-Path -Parent (Split-Path -Parent $launcher)) 'usr\bin\bash.exe'
    if (Test-Path -LiteralPath $core) { return $core }
    throw "Get-GitBashCoreOrThrow: no usr\bin\bash.exe beside '$launcher' - the process counter needs the real bash, not Git's launcher"
}

if (-not ('ClavityJobCount' -as [type])) {
    # Guarded: a second dot-source in the same session would otherwise fail on a duplicate type.
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ClavityJobCount {
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    static extern IntPtr CreateJobObject(IntPtr a, string name);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool AssignProcessToJobObject(IntPtr job, IntPtr proc);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool QueryInformationJobObject(IntPtr job, int cls, out BASIC info, int len, IntPtr ret);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool SetInformationJobObject(IntPtr job, int cls, ref EXTENDED info, int len);
    [StructLayout(LayoutKind.Sequential)]
    public struct BASIC {
        public long TotalUserTime, TotalKernelTime, ThisPeriodTotalUserTime, ThisPeriodTotalKernelTime;
        public uint TotalPageFaultCount, TotalProcesses, ActiveProcesses, TotalTerminatedProcesses;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct LIMIT { public long PerProcessUserTimeLimit, PerJobUserTimeLimit; public uint LimitFlags; public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize; public uint ActiveProcessLimit; public UIntPtr Affinity; public uint PriorityClass, SchedulingClass; }
    [StructLayout(LayoutKind.Sequential)]
    public struct IOCOUNTERS { public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes; }
    [StructLayout(LayoutKind.Sequential)]
    public struct EXTENDED { public LIMIT Basic; public IOCOUNTERS Io; public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed; }
    // KILL_ON_JOB_CLOSE (0x2000): closing the handle kills everything still in the job. MEASURED 2026-10-05 (agy panel
    // R1): without it a detached child of a hook survived the close; with it the child died on close.
    public static IntPtr Create() {
        var j = CreateJobObject(IntPtr.Zero, null);
        if (j == IntPtr.Zero) throw new Exception("CreateJobObject " + Marshal.GetLastWin32Error());
        var e = new EXTENDED(); e.Basic.LimitFlags = 0x2000;
        if (!SetInformationJobObject(j, 9, ref e, Marshal.SizeOf(typeof(EXTENDED)))) throw new Exception("SetInformationJobObject " + Marshal.GetLastWin32Error());
        return j;
    }
    public static void Assign(IntPtr j, IntPtr p) { if (!AssignProcessToJobObject(j, p)) throw new Exception("AssignProcessToJobObject " + Marshal.GetLastWin32Error()); }
    public static uint Total(IntPtr j) { BASIC b; if (!QueryInformationJobObject(j, 1, out b, Marshal.SizeOf(typeof(BASIC)), IntPtr.Zero)) throw new Exception("QueryInformationJobObject " + Marshal.GetLastWin32Error()); return b.TotalProcesses; }
    public static void Close(IntPtr j) { CloseHandle(j); }
}
'@
}

function Invoke-JobCountedBash {
    # One bash run inside a Job Object. bash starts SPINNING on a builtin test, is attached to the job, then
    # released (a file appears) to `exec` the script with the payload on stdin. Every process it creates from
    # then on belongs to the job, and TotalProcesses counts them all, including ones that already exited.
    # The environment goes to the CHILD ONLY (ProcessStartInfo.Environment): nothing in this process changes.
    param(
        [Parameter(Mandatory)][string]$Bash,
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$Arguments = @(),
        [string]$Payload = '{}',
        [hashtable]$Env = @{},
        [string]$WorkingDirectory = [IO.Path]::GetTempPath()
    )
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('jobcount-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $sq = { param($s) "'" + ($s -replace "'", "'\''") + "'" }
        $payloadFile = Join-Path $tmp 'payload.json'
        [IO.File]::WriteAllText($payloadFile, $Payload, [Text.UTF8Encoding]::new($false))
        $go = (Join-Path $tmp 'go') -replace '\\', '/'
        $argStr = ($Arguments | ForEach-Object { & $sq $_ }) -join ' '
        # `exec "$BASH"`, never `exec bash`: a PATH lookup can land on C:\Windows\System32\bash.exe (WSL).
        # PATH and MSYSTEM AS GIT'S LAUNCHER SETS THEM. Started directly, usr\bin\bash.exe does not put /mingw64/bin
        # on PATH: MEASURED 2026-10-05 (agy panel R3) in a clean environment it resolved NO git at all, so every git
        # call in a hook would fail and the hook degrade silently - a count of nothing. The launcher (how hooks
        # really run) puts /mingw64/bin:/usr/bin first; so does this.
        $boot = "while [ ! -e $(& $sq $go) ]; do :; done; export MSYSTEM=MINGW64 PATH=/mingw64/bin:/usr/bin:`$PATH; exec `"`$BASH`" $(& $sq ($ScriptPath -replace '\\', '/')) $argStr < $(& $sq ($payloadFile -replace '\\', '/'))"
        $psi = [Diagnostics.ProcessStartInfo]::new($Bash)
        $psi.ArgumentList.Add('-c'); $psi.ArgumentList.Add($boot)
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        # Hooks write UTF-8; without this the redirect decodes with the console code page (agy panel R4).
        $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false); $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
        $psi.WorkingDirectory = $WorkingDirectory
        foreach ($k in $Env.Keys) {
            if ($null -eq $Env[$k]) { [void]$psi.Environment.Remove($k) } else { $psi.Environment[$k] = [string]$Env[$k] }
        }
        $job = [ClavityJobCount]::Create()
        try {
            $p = [Diagnostics.Process]::Start($psi)
            [ClavityJobCount]::Assign($job, $p.Handle)
            New-Item -ItemType File -Path (Join-Path $tmp 'go') | Out-Null
            $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
            if (-not $p.WaitForExit(120000)) { $p.Kill($true); throw "Invoke-JobCountedBash: '$ScriptPath' did not exit within 120 s" }
            $p.WaitForExit()
            # A background child that inherited stdout/stderr would hold the pipes open after bash exits; bound
            # the reads so such a hook fails this run instead of hanging the suite.
            if (-not $out.Wait(10000) -or -not $err.Wait(10000)) { throw "Invoke-JobCountedBash: '$ScriptPath' exited but a child still holds its output open" }
            [pscustomobject]@{ Total = [int][ClavityJobCount]::Total($job); ExitCode = $p.ExitCode; StdOut = $out.Result; StdErr = $err.Result }
        } finally { [ClavityJobCount]::Close($job) }
    } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Measure-BashHookProcesses {
    # How many processes one run of a hook creates BEYOND bash's own boot. The boot cost is measured, not
    # assumed: an empty script run once per session through the same path. A total BELOW that boot means the
    # counter lost the process tree, so it throws instead of reporting a small, flattering number.
    param(
        [Parameter(Mandatory)][string]$HookPath,
        [string]$Payload = '{}',
        [hashtable]$Env = @{},
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = [IO.Path]::GetTempPath()
    )
    if (-not (Test-Path -LiteralPath $HookPath)) {
        throw "Measure-BashHookProcesses: the hook '$HookPath' does not exist - a count of a missing script is bash's error path, not the hook"
    }
    $bash = Get-GitBashCoreOrThrow
    if (-not $script:BashBootProcesses) {
        $empty = Join-Path ([IO.Path]::GetTempPath()) ('jobcount-empty-' + [Guid]::NewGuid().ToString('N') + '.sh')
        Set-Content -LiteralPath $empty -Value ':' -Encoding ascii
        try { $script:BashBootProcesses = (Invoke-JobCountedBash -Bash $bash -ScriptPath $empty).Total }
        finally { Remove-Item -LiteralPath $empty -Force -ErrorAction SilentlyContinue }
        if ($script:BashBootProcesses -lt 2) { $b = $script:BashBootProcesses; $script:BashBootProcesses = $null; throw "Measure-BashHookProcesses: boot calibration counted $b process(es); expected at least 2 (spinning bash + exec'd script)" }
    }
    $r = Invoke-JobCountedBash -Bash $bash -ScriptPath $HookPath -Arguments $Arguments -Payload $Payload -Env $Env -WorkingDirectory $WorkingDirectory
    if ($r.Total -lt $script:BashBootProcesses) {
        throw "Measure-BashHookProcesses: counted $($r.Total) process(es), below the $($script:BashBootProcesses)-process boot - the counter lost the tree"
    }
    [pscustomobject]@{ Spawned = $r.Total - $script:BashBootProcesses; Total = $r.Total; Boot = $script:BashBootProcesses; ExitCode = $r.ExitCode; StdOut = $r.StdOut.Trim(); StdErr = $r.StdErr.Trim() }
}
```

- [ ] **Step 4: Run the rows; they must pass.**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/BashHookHelpers.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 12, Failed: 0`.

- [ ] **Step 5: Update the partition count** for `BashHookHelpers.Tests.ps1` from `8 tests` to `12 tests` in `scripts/tests/_partition.md` (its row starts `BashHookHelpers.Tests.ps1`; append `; +4 Job Object counter rows 2026-10-04 (Branch 20)` to its note, time not re-measured).

- [ ] **Step 6: Commit.**

```bash
git add scripts/tests/BashHookHelpers.ps1 scripts/tests/BashHookHelpers.Tests.ps1 scripts/tests/_partition.md
git commit -m "test(hooks): Job Object counter for the processes a hook run creates (Branch 20)"
```

---

### Task 2: The budget suite (red for the nine hooks, by design)

**Files:**
- Create: `scripts/tests/hook-spawn-budget.Rows.ps1`
- Create: `scripts/tests/hook-spawn-budget.Tests.ps1`
- Modify: `justfile` (`test-scripts-slow` list), `scripts/tests/_partition.md` (new row)

**Oracle:** O1-O3 above. The fire-path messages the rows assert are quoted from the hooks: `AGY-TEST-AUDIT auto-fire` (`agy-test-audit-reminder.sh`), `AGY-FIRST auto-fire` (`agy-seam-inject.sh`, `*brainstorm*` -> `agy-first`, line 120), `AGY-AFTER` (`agy-after-reminder.sh`), `workflow position:` (`agy-consult-recovery.sh`), `agy-curate nudge` (`agy-curate-nudge.sh`).

- [ ] **Step 1: Create `scripts/tests/hook-spawn-budget.Rows.ps1`** with exactly this content:

```powershell
# Rows, fixtures and payloads for hook-spawn-budget.Tests.ps1. Dot-sourced in BeforeDiscovery (for -ForEach)
# AND in BeforeAll (so the fixture functions exist when a row runs).

# OWNER RULING 2026-10-04: at most 16 processes per hook run, INCLUDING the 3 the prototype harness counted for
# bash boot. Measure-BashHookProcesses reports processes BEYOND boot, so the same budget is 13 here.
$script:HookCeiling = 13

# OWNER RULING 2026-10-04 (3): the consult guard's real-consult path is out of scope for Branch 20 (ROADMAP
# section 70). Pinned at the count measured BEFORE this branch (total minus the 3 boot processes) on a plain
# temp repo, so it can only shrink. Measured: pre MCP 137 / ask 140 / send 143, post MCP 140 / ask 143 / await 152.
$script:ConsultPin = @{ PreMcp = 134; PreAsk = 137; PreSend = 140; PostMcp = 137; PostAsk = 140; PostAwait = 149 }

# BRANCH 21 DEBT (owner ruling O3): census-measured paths of the eight hooks Branch 21 fixes, totals INCLUDING
# the 3 boot processes. The suite's debt row stays RED while this list is non-empty. Branch 21 removes each
# entry in the same commit that adds a passing budget row for that path.
$script:B21Debt = @(
    @{ Hook = 'agy-inbox-snapshot.sh';          Path = 'curate skill matched, 20 existing baks (snapshot + prune 16)'; Total = 67 }
    @{ Hook = 'agy-discipline-reaching.sh';     Path = 'shield .gitignore carries a ! negation';                    Total = 36 }
    @{ Hook = 'agy-anomaly-reminder.sh';        Path = 'one untriaged entry';                                       Total = 23 }
    @{ Hook = 'agy-verify-reminder.sh';         Path = 'agy on PATH, assertion rows stale';                         Total = 24 }
    @{ Hook = 'docs-audit-reminder.sh';         Path = 'generated findings view with open findings';                Total = 22 }
    @{ Hook = 'assertion-strength-reminder.sh'; Path = 'TMPDIR unusable, HOME/.clavity-tmp fallback';               Total = 21 }
    @{ Hook = 'fetch-clavity-ls.sh';            Path = 'binary installed, stamp matches (steady state)';            Total = 17 }
    @{ Hook = 'migrate-inbox.sh';               Path = 'recover an interrupted migration';                          Total = 17 }
)

function New-HookFixture {
    # A throwaway repo, home and TMPDIR. -NoGit: the repo dir is a plain folder. -NoClavity: no .clavity/
    # (the plugin's opt-in). The Env hashtable is what every row hands the hook: it pins every variable a hook
    # reads from the environment, so nothing leaks in from the session running the tests.
    param([switch]$NoGit, [switch]$NoClavity)
    $root = Join-Path ([IO.Path]::GetTempPath()) ('hsb-' + [Guid]::NewGuid().ToString('N'))
    $repo = Join-Path $root 'repo'; $homeDir = Join-Path $root 'home'; $tmp = Join-Path $root 'tmp'
    New-Item -ItemType Directory -Force -Path $repo, (Join-Path $homeDir '.claude'), (Join-Path $homeDir '.clavity'), $tmp | Out-Null
    $fx = [pscustomobject]@{
        Root = $root; Repo = $repo; Home = $homeDir; Tmp = $tmp; RepoFwd = ($repo -replace '\\', '/')
        Env = @{
            HOME = ($homeDir -replace '\\', '/'); USERPROFILE = $homeDir; TMPDIR = ($tmp -replace '\\', '/')
            # agy-liveness-check.sh reads USER-scope settings from CLAUDE_CONFIG_DIR, not only from HOME.
            CLAUDE_CONFIG_DIR = (Join-Path $homeDir '.claude')
            CLAUDE_PROJECT_DIR = $repo; CLAUDE_PLUGIN_DATA = ''; CLAUDE_PLUGIN_ROOT = ''
            LOCALAPPDATA = $tmp
            # EVERY other variable a hook reads from its environment (census 2026-10-05: an rg of `${UPPER` over
            # the 4 hook dirs, minus the names the scripts set themselves). $null REMOVES it for the child, so a
            # value set in the session running the tests cannot leak in. CLAVITY_GOLDEN_HEADER is the dangerous
            # one: agy-drive-session-reset.sh deletes flag files under it.
            AGY_SESSION_ID = $null; CLAVITY_SESSION = $null; AGY_SESSION = $null
            CLAVITY_GOLDEN_HEADER = $null; CLAVITY_AUDIT_BASE_REF = $null; AGY_GUARD_TTL_MIN = $null
            AGY_CURATE_NUDGE_THRESHOLD = $null; AGY_CURATE_NUDGE_MAX_AGE_DAYS = $null; AGY_INBOX_SNAPSHOT_KEEP = $null
        }
    }
    if (-not $NoGit) {
        & git -C $repo init -q -b main
        Invoke-FxGit $fx commit --allow-empty -qm init
    }
    if (-not $NoClavity) {
        New-Item -ItemType Directory -Force -Path (Join-Path $repo '.clavity\seams'), (Join-Path $repo '.clavity\agy-marks') | Out-Null
        Set-Content -LiteralPath (Join-Path $repo '.clavity\.gitignore') -Value '*'
    }
    $fx
}
function Invoke-FxGit {
    param($Fx, [Parameter(ValueFromRemainingArguments)][string[]]$Rest)
    & git -C $Fx.Repo -c user.email=t@t -c user.name=t -c commit.gpgsign=false -c core.hooksPath= @Rest
}
function Add-FxCommit {
    param($Fx, [string]$Rel, [string]$Text = 'x')
    $p = Join-Path $Fx.Repo $Rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null
    Set-Content -LiteralPath $p -Value $Text
    Invoke-FxGit $Fx add -- $Rel
    Invoke-FxGit $Fx commit -qm "add $Rel"
    (Invoke-FxGit $Fx rev-parse HEAD).Trim()
}
function Set-FxMarker {
    param($Fx, [string]$Name, [string]$Sha)
    Set-Content -LiteralPath (Join-Path $Fx.Repo ".clavity\agy-marks\$Name.head") -Value $Sha -NoNewline
}
function Add-FxSeams {
    param($Fx, [string[]]$Names, [datetime]$When = (Get-Date).AddHours(-1))
    $dir = Join-Path $Fx.Repo '.clavity\seams'
    foreach ($n in $Names) {
        $f = Join-Path $dir $n
        [IO.File]::WriteAllText($f, 'body')
        [IO.File]::SetLastWriteTime($f, $When)
    }
}
function ConvertTo-HookPayload { param([hashtable]$H) $H | ConvertTo-Json -Compress -Depth 6 }
function New-ToolPayload {
    param($Fx, [string]$Tool, [hashtable]$ToolInput, [switch]$NoGit)
    ConvertTo-HookPayload @{ cwd = $Fx.RepoFwd; session_id = 's1'; tool_name = $Tool; tool_input = $ToolInput }
}
function New-BashPayload { param($Fx, [string]$Command) New-ToolPayload $Fx 'Bash' @{ command = $Command } }
function New-SessionStartPayload { param($Fx) ConvertTo-HookPayload @{ cwd = $Fx.RepoFwd; session_id = 's1'; hook_event_name = 'SessionStart'; source = 'startup' } }

function New-BudgetRow {
    param(
        [Parameter(Mandatory)][string]$Hook, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][scriptblock]$Setup,
        [hashtable]$Fixture = @{}, [string[]]$HookArgs = @(), [int]$Max = $script:HookCeiling,
        [string]$Expect = '', [switch]$Silent, [scriptblock]$Verify = $null
    )
    # -Verify: an EFFECT check run after the hook, for a path whose output is silent - a silent row alone
    # cannot tell "did its work" from "exited early" (agy panel R1).
    @{ Hook = $Hook; Name = $Name; Setup = $Setup; Fixture = $Fixture; HookArgs = $HookArgs; Max = $Max; Expect = $Expect; Silent = [bool]$Silent; Verify = $Verify }
}

$D = 'clavity-dotnet/plugin/hooks'; $C = 'clavity-classic/plugin/hooks'; $A = 'agy-autotrain/hooks'; $L = '.claude/hooks'
$mcp = 'mcp__plugin_clavity_clavity-ls__agy_ask'

$script:Rows = @(
    # --- agy-consult-guard-pre.sh (runs on EVERY Bash / PowerShell / agy_ask call) ---
    New-BudgetRow "$D/agy-consult-guard-pre.sh" 'non-consult Bash call' { param($fx) New-BashPayload $fx 'ls' } -Silent
    New-BudgetRow "$D/agy-consult-guard-pre.sh" 'command text mentions the consult CLI' { param($fx) New-BashPayload $fx 'git commit -m "note: clavity ask later"' } -Silent
    New-BudgetRow "$D/agy-consult-guard-pre.sh" 'clavity await-reply (pre is a no-op)' { param($fx) New-BashPayload $fx 'clavity await-reply' } -Silent
    New-BudgetRow "$D/agy-consult-guard-pre.sh" 'consult outside a git repo' { param($fx) New-BashPayload $fx 'clavity ask "x" --review-only' } -Fixture @{ NoGit = $true; NoClavity = $true } -Silent
    New-BudgetRow "$D/agy-consult-guard-pre.sh" 'PINNED consult: MCP agy_ask' { param($fx) New-ToolPayload $fx $mcp @{ prompt = 'x' } } -Fixture @{ NoClavity = $true } -Max $script:ConsultPin.PreMcp -Silent
    New-BudgetRow "$D/agy-consult-guard-pre.sh" 'PINNED consult: clavity ask' { param($fx) New-BashPayload $fx 'clavity ask "x" --review-only' } -Fixture @{ NoClavity = $true } -Max $script:ConsultPin.PreAsk -Silent
    New-BudgetRow "$D/agy-consult-guard-pre.sh" 'PINNED consult: clavity send' { param($fx) New-BashPayload $fx 'clavity send "x"' } -Fixture @{ NoClavity = $true } -Max $script:ConsultPin.PreSend -Silent

    # --- agy-consult-guard-post.sh ---
    New-BudgetRow "$D/agy-consult-guard-post.sh" 'non-consult Bash call' { param($fx) New-BashPayload $fx 'ls' } -Silent
    New-BudgetRow "$D/agy-consult-guard-post.sh" 'command text mentions the consult CLI' { param($fx) New-BashPayload $fx 'git commit -m "note: clavity ask later"' } -Silent
    New-BudgetRow "$D/agy-consult-guard-post.sh" 'clavity send (post is a no-op)' { param($fx) New-BashPayload $fx 'clavity send "x"' } -Silent
    New-BudgetRow "$D/agy-consult-guard-post.sh" 'consult outside a git repo' { param($fx) New-BashPayload $fx 'clavity ask "x" --review-only' } -Fixture @{ NoGit = $true; NoClavity = $true } -Silent
    New-BudgetRow "$D/agy-consult-guard-post.sh" 'PINNED consult: MCP agy_ask (after its pre)' {
        param($fx)
        $p = New-ToolPayload $fx $mcp @{ prompt = 'x' }
        $null = Invoke-BashHook -HookPath (Join-Path $script:RepoRoot "$D/agy-consult-guard-pre.sh") -Payload $p -Env $fx.Env
        $p
    } -Fixture @{ NoClavity = $true } -Max $script:ConsultPin.PostMcp -Silent
    New-BudgetRow "$D/agy-consult-guard-post.sh" 'PINNED consult: clavity ask (after its pre)' {
        param($fx)
        $p = New-BashPayload $fx 'clavity ask "x" --review-only'
        $null = Invoke-BashHook -HookPath (Join-Path $script:RepoRoot "$D/agy-consult-guard-pre.sh") -Payload $p -Env $fx.Env
        $p
    } -Fixture @{ NoClavity = $true } -Max $script:ConsultPin.PostAsk -Silent
    New-BudgetRow "$D/agy-consult-guard-post.sh" 'PINNED consult: clavity await-reply (after a send)' {
        param($fx)
        $null = Invoke-BashHook -HookPath (Join-Path $script:RepoRoot "$D/agy-consult-guard-pre.sh") -Payload (New-BashPayload $fx 'clavity send "x"') -Env $fx.Env
        New-BashPayload $fx 'clavity await-reply'
    } -Fixture @{ NoClavity = $true } -Max $script:ConsultPin.PostAwait -Silent

    # --- agy-consult-recovery.sh (SessionStart) ---
    New-BudgetRow "$D/agy-consult-recovery.sh" 'one open seam' { param($fx) Add-FxSeams $fx 'agy-capstone-r1-x.md'; New-SessionStartPayload $fx } -Expect 'workflow position:'
    New-BudgetRow "$D/agy-consult-recovery.sh" '1000 mixed seams' {
        param($fx)
        Add-FxSeams $fx (1..1000 | ForEach-Object { if ($_ % 2) { "agy-capstone-r$_-x.md" } else { "loose-$_.md" } })
        New-SessionStartPayload $fx
    } -Expect 'workflow position:'
    New-BudgetRow "$D/agy-consult-recovery.sh" '1000 seams, all concluded' {
        param($fx)
        Add-FxSeams $fx (1..1000 | ForEach-Object { "agy-capstone-r$_-x.md" }) -When (Get-Date).AddHours(-2)
        Set-FxMarker $fx 'agy-capstone' (Invoke-FxGit $fx rev-parse HEAD).Trim()
        New-SessionStartPayload $fx
    } -Silent

    # --- agy-test-audit-reminder.sh (PostToolUse: EVERY Bash / PowerShell / Write / Edit) ---
    New-BudgetRow "$D/agy-test-audit-reminder.sh" 'no .clavity (not opted in)' { param($fx) New-BashPayload $fx 'ls' } -Fixture @{ NoClavity = $true } -Silent
    New-BudgetRow "$D/agy-test-audit-reminder.sh" 'fires: capstone marker at HEAD, code vs main' {
        param($fx)
        Invoke-FxGit $fx checkout -q -b feat
        Set-FxMarker $fx 'agy-capstone' (Add-FxCommit $fx 'src/a.cs')
        New-BashPayload $fx 'ls'
    } -Expect 'AGY-TEST-AUDIT auto-fire'
    New-BudgetRow "$D/agy-test-audit-reminder.sh" 'fires: worst path, both markers behind HEAD' {
        param($fx)
        Invoke-FxGit $fx checkout -q -b feat
        Set-FxMarker $fx 'agy-test-audit' (Add-FxCommit $fx 'src/a.cs')
        Set-FxMarker $fx 'agy-capstone' (Add-FxCommit $fx 'src/b.cs')
        $null = Add-FxCommit $fx 'README.md' 'docs only'
        New-BashPayload $fx 'ls'
    } -Expect 'AGY-TEST-AUDIT auto-fire'
    New-BudgetRow "$D/agy-test-audit-reminder.sh" 'debounced: second call at the same HEAD' {
        param($fx)
        Invoke-FxGit $fx checkout -q -b feat
        Set-FxMarker $fx 'agy-capstone' (Add-FxCommit $fx 'src/a.cs')
        $p = New-BashPayload $fx 'ls'
        $null = Invoke-BashHook -HookPath (Join-Path $script:RepoRoot "$D/agy-test-audit-reminder.sh") -Payload $p -Env $fx.Env
        $p
    } -Silent
    # The four paths the prototype never measured (agy panel R2) - rename and merge in the reviewed range, and the
    # no-jq arm (PATH = <Git>\usr\bin only, the convention of agy-test-audit-reminder.Tests.ps1 line 8).
    New-BudgetRow "$D/agy-test-audit-reminder.sh" 'fires: a code file RENAMED since main' {
        param($fx)
        Invoke-FxGit $fx checkout -q -b feat
        $null = Add-FxCommit $fx 'src/a.cs'
        Invoke-FxGit $fx mv src/a.cs src/b.cs
        Invoke-FxGit $fx commit -qm rename
        Set-FxMarker $fx 'agy-capstone' (Invoke-FxGit $fx rev-parse HEAD).Trim()
        New-BashPayload $fx 'ls'
    } -Expect 'AGY-TEST-AUDIT auto-fire'
    New-BudgetRow "$D/agy-test-audit-reminder.sh" 'fires: a MERGE commit in the reviewed range' {
        param($fx)
        Invoke-FxGit $fx checkout -q -b feat
        $null = Add-FxCommit $fx 'src/a.cs'
        Invoke-FxGit $fx checkout -q -b side
        $null = Add-FxCommit $fx 'src/b.cs'
        Invoke-FxGit $fx checkout -q feat
        Invoke-FxGit $fx merge -q --no-ff -m merge side
        Set-FxMarker $fx 'agy-capstone' (Invoke-FxGit $fx rev-parse HEAD).Trim()
        New-BashPayload $fx 'ls'
    } -Expect 'AGY-TEST-AUDIT auto-fire'
    New-BudgetRow "$D/agy-test-audit-reminder.sh" 'no jq: fires on the ledger shape (marker behind HEAD, docs since)' {
        param($fx)
        $fx.Env.PATH = Join-Path (Split-Path -Parent (Split-Path -Parent (Get-GitBashOrThrow))) 'usr\bin'
        Invoke-FxGit $fx checkout -q -b feat
        Set-FxMarker $fx 'agy-capstone' (Add-FxCommit $fx 'src/a.cs')
        $null = Add-FxCommit $fx 'README.md' 'docs only'
        New-BashPayload $fx 'ls'
    } -Expect 'guard inactive: missing jq'
    New-BudgetRow "$D/agy-test-audit-reminder.sh" 'no jq: debounced second call' {
        param($fx)
        $fx.Env.PATH = Join-Path (Split-Path -Parent (Split-Path -Parent (Get-GitBashOrThrow))) 'usr\bin'
        Invoke-FxGit $fx checkout -q -b feat
        Set-FxMarker $fx 'agy-capstone' (Add-FxCommit $fx 'src/a.cs')
        $null = Add-FxCommit $fx 'README.md' 'docs only'
        $p = New-BashPayload $fx 'ls'
        $null = Invoke-BashHook -HookPath (Join-Path $script:RepoRoot "$D/agy-test-audit-reminder.sh") -Payload $p -Env $fx.Env
        $p
    } -Silent

    # --- agy-after-reminder.sh (PostToolUse Write|Edit) ---
    New-BudgetRow "$D/agy-after-reminder.sh" 'non-plan Edit' { param($fx) New-ToolPayload $fx 'Edit' @{ file_path = "$($fx.RepoFwd)/src/a.cs" } } -Silent
    New-BudgetRow "$D/agy-after-reminder.sh" 'plan Edit' {
        param($fx)
        $rel = 'docs/superpowers/plans/2026-01-01-x.md'
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $fx.Repo 'docs\superpowers\plans')
        Set-Content -LiteralPath (Join-Path $fx.Repo $rel) -Value '# plan'
        New-ToolPayload $fx 'Edit' @{ file_path = "$($fx.RepoFwd)/$rel" }
    } -Expect 'AGY-AFTER'

    # --- agy-seam-inject.sh (PreToolUse Skill) ---
    New-BudgetRow "$D/agy-seam-inject.sh" 'seam skill, no marker' { param($fx) New-ToolPayload $fx 'Skill' @{ skill = 'superpowers:brainstorming' } } -Expect 'AGY-FIRST auto-fire'
    New-BudgetRow "$D/agy-seam-inject.sh" 'seam skill, marker behind HEAD with code since' {
        param($fx)
        Set-FxMarker $fx 'agy-first' (Add-FxCommit $fx 'src/a.cs')
        $null = Add-FxCommit $fx 'src/b.cs'
        New-ToolPayload $fx 'Skill' @{ skill = 'superpowers:brainstorming' }
    } -Expect 'AGY-FIRST auto-fire'
    New-BudgetRow "$D/agy-seam-inject.sh" 'non-seam skill' { param($fx) New-ToolPayload $fx 'Skill' @{ skill = 'dataviz' } } -Silent
    New-BudgetRow "$D/agy-seam-inject.sh" 'skill value containing a newline' { param($fx) New-ToolPayload $fx 'Skill' @{ skill = "superpowers:brainstorming`nx" } }

    # --- agy-liveness-check.sh (SessionStart startup) ---
    New-BudgetRow "$D/agy-liveness-check.sh" 'no settings files' { param($fx) New-SessionStartPayload $fx }
    New-BudgetRow "$D/agy-liveness-check.sh" 'three settings files, one a personal duplicate (warns)' {
        param($fx)
        # A personal registration of a plugin hook is the state this hook warns about (its suite row 'reports the
        # unreadable settings file BUT continues the sweep' uses the same command), so the row can ASSERT that the
        # full sweep ran instead of passing on an early exit.
        $s = '{"enabledPlugins":{"superpowers@superpowers-marketplace":true},"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash \"~/.claude/hooks/agy-liveness-check.sh\""}]}]}}'
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $fx.Repo '.claude')
        Set-Content -LiteralPath (Join-Path $fx.Home '.claude\settings.json') -Value $s
        Set-Content -LiteralPath (Join-Path $fx.Repo '.claude\settings.json') -Value $s
        Set-Content -LiteralPath (Join-Path $fx.Repo '.claude\settings.local.json') -Value $s
        New-SessionStartPayload $fx
    } -Expect 'agy-liveness-check'

    # --- agy-drive-session-reset.sh (classic only; DELETES flags under ~/.clavity) ---
    New-BudgetRow "$C/agy-drive-session-reset.sh" 'startup: own flag + 5 stale + 2 fresh' {
        param($fx)
        $dir = Join-Path $fx.Home '.clavity'
        Set-Content -LiteralPath (Join-Path $dir '.active-drive-session-default') -Value '' -NoNewline
        foreach ($i in 1..5) { $f = Join-Path $dir ".active-drive-session-stale$i"; Set-Content -LiteralPath $f -Value '' -NoNewline; [IO.File]::SetLastWriteTime($f, (Get-Date).AddDays(-10)) }
        foreach ($i in 1..2) { Set-Content -LiteralPath (Join-Path $dir ".active-drive-session-fresh$i") -Value '' -NoNewline }
        New-SessionStartPayload $fx
    } -Silent -Verify {
        param($fx)
        $left = @(Get-ChildItem -LiteralPath (Join-Path $fx.Home '.clavity') -Force -Filter '.active-drive-session-*' | ForEach-Object Name) | Sort-Object
        ($left -join ',') | Should -BeExactly '.active-drive-session-fresh1,.active-drive-session-fresh2' -Because 'the reset must clear its own flag and the 5 stale ones and keep the 2 fresh - or the row measured an early exit'
    }

    # --- agy-curate-nudge.sh (agy-autotrain, SessionStart) ---
    New-BudgetRow "$A/agy-curate-nudge.sh" 'inbox missing' { param($fx) New-SessionStartPayload $fx } -Silent
    New-BudgetRow "$A/agy-curate-nudge.sh" 'worst: snooze expired + 16 recent entries' {
        param($fx)
        $today = (Get-Date).ToString('yyyy-MM-dd'); $dot = [char]0x00B7
        $bullets = (1..16 | ForEach-Object { "- [heuristic] (driver/probabilistic) rule $_  $dot  ``[corpus]`` $dot $today $dot agy 1.0.0" }) -join "`n"
        [IO.File]::WriteAllText((Join-Path $fx.Home '.clavity\agy-observations.md'), "# agy observations inbox`n`n## Pending`n`n$bullets`n", [Text.UTF8Encoding]::new($false))
        $s = Join-Path $fx.Home '.clavity\.agy-curate-snooze'; Set-Content -LiteralPath $s -Value '' -NoNewline; [IO.File]::SetLastWriteTime($s, (Get-Date).AddDays(-8))
        New-SessionStartPayload $fx
    } -Expect 'agy-curate is OVERDUE'   # 16 >= 2 x threshold 8 takes the OVERDUE message (agy-curate-nudge.sh:80), not the nudge

    # --- every other registered hook: its default path (Branch 21 adds the worst paths) ---
    New-BudgetRow "$D/agy-anomaly-dispatch-reminder.sh" 'Agent dispatch' { param($fx) New-ToolPayload $fx 'Agent' @{ prompt = 'x' } }
    New-BudgetRow "$D/assertion-strength-reminder.sh" 'non-test Edit' { param($fx) New-ToolPayload $fx 'Edit' @{ file_path = "$($fx.RepoFwd)/src/a.cs" } }
    New-BudgetRow "$D/agy-anomaly-reminder.sh" 'startup, nothing captured' { param($fx) New-SessionStartPayload $fx }
    New-BudgetRow "$D/agy-anomaly-model-notice.sh" 'startup' { param($fx) New-SessionStartPayload $fx }
    New-BudgetRow "$D/agy-discipline-reaching.sh" 'startup, shield intact' { param($fx) New-SessionStartPayload $fx }
    New-BudgetRow "$D/agy-anomaly-capture-reminder.sh" 'PreCompact' { param($fx) ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'PreCompact'; trigger = 'manual' } }
    New-BudgetRow "$D/agy-anomaly-capture-reminder.sh" 'UserPromptSubmit' { param($fx) ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'UserPromptSubmit'; prompt = 'hi' } } -HookArgs @('UserPromptSubmit')
    New-BudgetRow "$D/fetch-clavity-ls.sh" 'not a plugin context' { param($fx) New-SessionStartPayload $fx }
    New-BudgetRow "$D/clavity-dotnet-setup.sh" 'not a plugin context' { param($fx) New-SessionStartPayload $fx }
    New-BudgetRow "$A/agy-inbox-snapshot.sh" 'non-curate skill' { param($fx) New-ToolPayload $fx 'Skill' @{ skill = 'dataviz' } }
    New-BudgetRow "$A/agy-inbox-snapshot.sh" 'UserPromptSubmit, ordinary prompt' { param($fx) ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'UserPromptSubmit'; prompt = 'hi' } }
    New-BudgetRow "$A/migrate-inbox.sh" 'nothing to migrate' { param($fx) New-SessionStartPayload $fx }
    New-BudgetRow "$A/agy-learn-reminder.sh" 'SessionStart' { param($fx) New-SessionStartPayload $fx } -HookArgs @('SessionStart')
    New-BudgetRow "$A/agy-learn-reminder.sh" 'PreCompact' { param($fx) ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'PreCompact'; trigger = 'manual' } } -HookArgs @('PreCompact')
    New-BudgetRow "$L/agy-verify-reminder.sh" 'not the clavity repo' { param($fx) New-SessionStartPayload $fx }
    New-BudgetRow "$L/docs-audit-reminder.sh" 'no findings view' { param($fx) New-SessionStartPayload $fx }
)

# Narrow to ONE hook for a task's red/green runs: set HSB_HOOK to the hook's file name and run with
# -TagFilter row. MEASURED 2026-10-04: Invoke-Pester -FullNameFilter does NOT see the expanded '<Hook>' row
# names (a filter on the hook name ran 0 tests), so the narrowing happens here, at discovery.
if ($env:HSB_HOOK) {
    $script:Rows = @($script:Rows | Where-Object { (Split-Path -Leaf $_.Hook) -eq $env:HSB_HOOK })
    # A mistyped name selects nothing, and a 0-test run exits 0 under -CI (agy panel R3): fail discovery instead.
    if ($script:Rows.Count -eq 0) { throw "HSB_HOOK='$($env:HSB_HOOK)' matches no budget row - check the hook file name" }
}
```

- [ ] **Step 2: Create `scripts/tests/hook-spawn-budget.Tests.ps1`** with exactly this content:

```powershell
# THE PROCESS BUDGET OF EVERY REGISTERED HOOK (ROADMAP Branch 20; owner ruling 2026-10-04).
#
# WHY: on the owner's machine EVERY process creation costs ~180-360 ms, whatever the process (measured
# 2026-10-04: native rg.exe and msys tools cost the same, so it is process creation, not msys emulation).
# A hook that starts 40 processes on every Bash call costs seconds per call; the SessionStart ones were timing
# out. Wall-clock limits on a shared box are noise (TIMING discipline), so the gate is the COUNT, which a
# Windows Job Object reports deterministically (Measure-BashHookProcesses, BashHookHelpers.ps1).
#
# THREE KINDS OF ROW, read together:
#   - one row per (hook, named path) asserting at most HookCeiling processes beyond boot. Each row that names
#     a path which EMITS asserts the emission (-Expect), and each silent path asserts silence (-Silent) - a
#     row whose fixture missed its path would otherwise certify an early exit;
#   - the census row: every hook in the four registries has at least one row, so a new hook cannot ship
#     uncounted;
#   - the Branch 21 debt row: RED until $B21Debt is empty (owner ruling: a visible failure, not a pin).
# Plus one SCALING row: consult-recovery costs the same with 1 seam and with 1000.

BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'hook-spawn-budget.Rows.ps1')
}

Describe 'hook spawn budget' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        . (Join-Path $PSScriptRoot 'hook-spawn-budget.Rows.ps1')
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }

    It 'gives every hook in the four registries at least one budget row' -Tag 'census' -Skip:([bool]$env:HSB_HOOK) {
        $registries = 'clavity-dotnet/plugin/hooks/hooks.json', 'clavity-classic/plugin/hooks/hooks.json', 'agy-autotrain/hooks/hooks.json', '.claude/settings.json'
        $registered = @(foreach ($r in $registries) {
            [regex]::Matches((Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot $r)), '[/\\]hooks[/\\]([A-Za-z0-9._-]+\.sh)') | ForEach-Object { $_.Groups[1].Value }
        }) | Sort-Object -Unique
        $registered.Count | Should -BeGreaterThan 20 -Because 'the four registries must parse into their hook names, or this row checks nothing'
        $covered = @($script:Rows | ForEach-Object { Split-Path -Leaf $_.Hook }) | Sort-Object -Unique
        (@($registered | Where-Object { $_ -notin $covered }) -join ', ') | Should -BeExactly '' -Because 'a registered hook with no budget row ships with no limit on what it costs every session - add a row to hook-spawn-budget.Rows.ps1'
    }

    It 'carries no Branch 21 debt (RED until Branch 21 lands - owner ruling 2026-10-04)' -Tag 'debt' {
        # CI runs this whole directory on EVERY PR with no paths filter (ci-scripts.yml), and merge-gate guards
        # main and Dependabot auto-merge, so a red row there would block every merge until Branch 21. Owner
        # ruling 2026-10-05, agreed with agy (fork A): RED locally, SKIPPED on CI with the debt in the reason so
        # every CI log still names it.
        if ($env:GITHUB_ACTIONS -and $script:B21Debt.Count) {
            Set-ItResult -Skipped -Because ('Branch 21 debt, CI-only skip: ' + (@($script:B21Debt | ForEach-Object { "$($_.Hook) [$($_.Path)] $($_.Total) total" }) -join '; '))
        }
        (@($script:B21Debt | ForEach-Object { "$($_.Hook) [$($_.Path)] measured $($_.Total) total" }) -join '; ') | Should -BeExactly '' -Because 'each listed path is over the 16-process ceiling; Branch 21 removes an entry in the commit that brings its path under it'
    }

    It '<Hook>: <Name> starts at most <Max> processes beyond bash boot' -ForEach $Rows -Tag 'row' {
        $fx = New-HookFixture @Fixture
        try {
            $payload = & $Setup $fx
            $r = Measure-BashHookProcesses -HookPath (Join-Path $script:RepoRoot $Hook) -Payload $payload -Env $fx.Env -Arguments $HookArgs -WorkingDirectory $fx.Repo
            if ($Expect) { $r.StdOut | Should -Match ([regex]::Escape($Expect)) -Because 'the row must reach the path it names, or its count proves nothing' }
            if ($Silent) { $r.StdOut | Should -BeNullOrEmpty -Because 'this path is silent; output means the fixture reached a different path' }
            if ($Verify) { & $Verify $fx }
            $r.Spawned | Should -BeLessOrEqual $Max -Because "$Hook on '$Name' started $($r.Spawned) processes beyond the $($r.Boot)-process boot"
        } finally { Remove-Item -LiteralPath $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'agy-consult-recovery.sh costs the same with 1 seam and with 1000 (the cost must not scale with the seam count)' -Tag 'scaling' {
        $one = New-HookFixture; $big = New-HookFixture
        try {
            Add-FxSeams $one 'agy-capstone-r1-x.md'
            Add-FxSeams $big (1..1000 | ForEach-Object { if ($_ % 2) { "agy-capstone-r$_-x.md" } else { "loose-$_.md" } })
            $hook = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-consult-recovery.sh'
            $a = Measure-BashHookProcesses -HookPath $hook -Payload (New-SessionStartPayload $one) -Env $one.Env -WorkingDirectory $one.Repo
            $b = Measure-BashHookProcesses -HookPath $hook -Payload (New-SessionStartPayload $big) -Env $big.Env -WorkingDirectory $big.Repo
            $b.Spawned | Should -Be $a.Spawned -Because 'a per-seam process (a stat, a git call, an ls of each file) makes SessionStart cost grow with the seam directory, which reached 1031 files in this repo'
        } finally { Remove-Item -LiteralPath $one.Root, $big.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
```

- [ ] **Step 3: Register the suite.** In `justfile`, recipe `test-scripts-slow`, add `'scripts/tests/hook-spawn-budget.Tests.ps1'` to the `Invoke-Pester @(...)` list immediately after `'scripts/tests/pairing-doc.Tests.ps1'` (the list's last entry), keeping the `', '` separator.

- [ ] **Step 4: Run the suite; record which rows fail.**

Run (backgrounded or foreground; ~60 rows x ~2-5 s): `pwsh -NoProfile -c "Invoke-Pester scripts/tests/hook-spawn-budget.Tests.ps1 -Output Detailed -CI"`
Expected: the census row PASSES; the debt row FAILS; the scaling row FAILS (prototype-measured today: 1 seam 19 total, 1000 seams 37); the rows of the nine hooks fail where today's counts exceed 13 beyond boot (consult-guard-pre/post non-consult rows ~37, test-audit-reminder fire rows, seam-inject, liveness, curate worst, drive-reset, after-reminder, consult-recovery seam rows); every "every other registered hook" row PASSES; every PINNED row PASSES. **Any row failing for a reason other than its count (an `-Expect`/`-Silent` assertion, an exception) is a fixture defect: STOP and fix the fixture before Task 3** - with TWO designed exceptions: `agy-test-audit-reminder.sh: debounced: second call at the same HEAD` and `agy-test-audit-reminder.sh: no jq: debounced second call` fail their `-Silent` assertion until Task 5 adds the debounce. If a scaling or nine-hook row unexpectedly PASSES, record it and continue (Task 3+ still applies).

- [ ] **Step 4b: Give every row an output assertion (panel R1).** Rows that carry neither `-Expect` nor `-Silent` can certify an early exit. These are: the `agy-liveness-check.sh` 'no settings files' row, `agy-seam-inject.sh: skill value containing a newline`, and every row in the "every other registered hook" block. For each one, read the row's stdout in Step 4's detailed output (or call `Measure-BashHookProcesses` once with the row's fixture). If stdout is empty, add `-Silent`. Otherwise add `-Expect '<the first 20 characters of its stdout's additionalContext / systemMessage text>'`. A stdout that is NOT the path the row's name claims (for example a `.no-agy` notice) is a fixture defect: fix the fixture first. Re-run Step 4: those rows' outcomes must not change.
- [ ] **Step 5: Partition row.** Add to the Measured runtimes table in `scripts/tests/_partition.md`, directly after the `pairing-doc.Tests.ps1` row:

```text
hook-spawn-budget.Tests.ps1                         ?   <N> tests   <- SLOW, NEW 2026-10-04 (Branch 20 process budget; one row stays RED until Branch 21 - owner ruling)
```

with `<N>` = the `Tests Passed` + `Tests Failed` total from Step 4 (Pester discovery count; `test-suite-registration.Tests.ps1` checks it), and the runtime from Step 4's `Tests completed in` line instead of `?`.

- [ ] **Step 6: Run the registration guard.**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 9, Failed: 0`.

- [ ] **Step 7: Commit (the suite is red by design at this point).**

```bash
git add scripts/tests/hook-spawn-budget.Rows.ps1 scripts/tests/hook-spawn-budget.Tests.ps1 justfile scripts/tests/_partition.md
git commit -m "test(hooks): process-budget suite for every registered hook - red on the nine Branch 20 hooks until their tasks land"
```

---

### Tasks 3-10: one task per hook (same shape)

Each task: (1) run the hook's budget rows and see them fail; (2) apply its patch; (3) apply its corrections; (4) mirror; (5) `bash -n`; (6) budget rows pass; (7) the hook's own suite passes; (8) commit. The **filtered budget run** for one hook is, from PowerShell:

```powershell
$env:HSB_HOOK = '<hook file name>'; pwsh -NoProfile -c "Invoke-Pester scripts/tests/hook-spawn-budget.Tests.ps1 -TagFilter row -Output Detailed -CI"; Remove-Item Env:HSB_HOOK
```

`<hook file name>` is the leaf, e.g. `agy-consult-guard-pre.sh`. **A run that reports 0 tests is a FAILURE, not a pass** (a mistyped name filters everything out). The patches live in `docs/superpowers/plans/2026-10-04-sweep-branch-20-hook-spawn-budget/`, written as `$P` below. **Step 0 of every task (STATE-VERIFICATION):** `git apply --check $P/<patch>`. If it does not apply, STOP and report `STATE_MISMATCH: <patch>`.

### Task 3: agy-consult-guard-pre.sh + agy-consult-guard-post.sh

**Files:** `clavity-dotnet/plugin/hooks/agy-consult-guard-{pre,post}.sh` + classic mirrors. **Oracle:** `scripts/tests/agy-consult-guard.Tests.ps1` (44 rows), which includes the rule that the guard does NOT honour `.no-agy`.

- [ ] **Step 1:** filtered budget run for `HSB_HOOK=agy-consult-guard-pre.sh`, then for `HSB_HOOK=agy-consult-guard-post.sh`. Expected: the 4 non-pinned rows of each FAIL (about 37 beyond boot); the 3 pinned rows PASS.
- [ ] **Step 1b: Case rows first (panel R1, verified).** Git Bash resolves commands case-insensitively on Windows (measured 2026-10-05: `CLAVITY-LS --help` and `Clavity-Ls.EXE --help` both ran `clavity-ls`), but the guard's command anchor matches only lower-case `clavity` (`agy-consult-guard-lib.sh`, `agy_guard_category`: `printf '%s' "$c" | grep -Eq "${anchor}ask..."`), so a consult typed `CLAVITY ask` runs unguarded. In `scripts/tests/agy-consult-guard.Tests.ps1`, directly after the row `It 'WARNS when the consult CLI is invoked as clavity.exe'`, add:

```powershell
    It 'WARNS when the consult CLI is invoked in another letter case (<Cmd>)' -ForEach @(
        @{ Cmd = 'CLAVITY ask "review this"' }
        @{ Cmd = 'Clavity.EXE ask "review this"' }
    ) {
        # Branch 20 panel R1, MEASURED: Git Bash on Windows runs CLAVITY / Clavity.EXE as clavity, so a
        # case-sensitive anchor left these consults unguarded.
        $r = New-GuardRepo
        try {
            $p = Payload 'Bash' $Cmd $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'e.txt' 'five' -Encoding ascii; git add e.txt; git commit -qm peer; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

Run the suite: exactly these 2 rows FAIL (44 pass).
- [ ] **Step 2:** `git apply $P/01-consult-guard-pre.patch $P/02-consult-guard-post.patch`
- [ ] **Step 3: Corrections.**
  (a) Case-insensitive matching, in BOTH patched hooks: directly after the stdin line `input=; while IFS= read -r -N 1048576 chunk 2>/dev/null; do input+=$chunk; done; input+=$chunk` insert the line `shopt -s nocasematch   # Windows runs CLAVITY / Clavity.EXE as clavity (Branch 20 panel R1)`. This makes both prefilters' `[[ =~ ]]` matches case-insensitive. It cannot change the `sid` sanitize, whose class already spans `A-Za-z`.
  (b) In `clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh`, `agy_guard_category`: change each of the three `grep -Eq` to `grep -Eiq` (lines `... grep -Eq "${anchor}ask([[:space:]]|$)" ...`, `... "${anchor}send..."`, `... "${anchor}await-reply..."`). Copy the lib to `clavity-classic/plugin/hooks/` in Step 4 as well.
  Otherwise unchanged from the patches. The patches already read stdin with the chunked loop (variable `chunk` rather than `_c`; equivalent) and resolve the lib with `d=${0%[/\\]*}`. What they do: prefilter 1 on the raw JSON exits unless the text contains `agy_ask` or matches `clavity(\.exe)?([[:space:]]|\\[ntrf]|\\u[0-9a-fA-F]{4})+(ask|send|await-reply)`; prefilter 2 on the decoded command applies the lib's command-position anchor (plus a newline separator). Pre exits on an await-reply-only command and post on a send-only one. One `jq -j` NUL-separated call replaces the four `printf|jq`. `sid` is sanitized under `LC_ALL=C`, byte-wise like `tr -c`. Proven a superset of `agy_guard_category` on 30 + 14 commands (scripts `t4.sh`, `t5.sh` in `.clavity/scratch/hook-perf/b20-protos/scratch-b20/`).
- [ ] **Step 4:** `cp clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh clavity-classic/plugin/hooks/`
- [ ] **Step 5:** `bash -n clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh && bash -n clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh` -> no output, exit 0.
- [ ] **Step 6:** both filtered budget runs: all 14 rows PASS. Prototype counts (total incl. 3 boot): non-consult 3, prefilter hit 7, pinned 114-129. **Then re-pin (panel R1):** set each `$script:ConsultPin` value in `hook-spawn-budget.Rows.ps1` to the `Spawned` the row just reported (read it from the row's `-Because` text by temporarily lowering its `-Max` to 0, or from a one-off `Measure-BashHookProcesses` call with the same fixture), and change the comment's "measured BEFORE this branch" to "measured after Task 3". The counts are deterministic (run-to-run identical), so the pin has no slack and the consult path can no longer grow back the ~20 processes Task 3 removed. Re-run both filtered budget runs: PASS.
- [ ] **Step 7:** `pwsh -NoProfile -c "Invoke-Pester scripts/tests/agy-consult-guard.Tests.ps1 -Output Detailed -CI"` -> `Tests Passed: 46, Failed: 0`. A failing row is a behaviour regression: the ORACLE wins. Report it, do not edit the test.
- [ ] **Step 8:**

```bash
git add clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh clavity-classic/plugin/hooks/agy-consult-guard-pre.sh clavity-classic/plugin/hooks/agy-consult-guard-post.sh clavity-classic/plugin/hooks/agy-consult-guard-lib.sh scripts/tests/agy-consult-guard.Tests.ps1 scripts/tests/hook-spawn-budget.Rows.ps1
git commit -m "perf(hooks): consult guard exits on non-consult calls before any process (40 -> 3)"
```

### Task 4: agy-consult-recovery.sh (count + seam classifier)

**Files:** `clavity-dotnet/plugin/hooks/agy-consult-recovery.sh` + classic mirror; `scripts/tests/agy-consult-recovery.Tests.ps1`. **Oracle:** that suite (38 rows) + `docs/superpowers/specs/2026-08-13-workflow-position-resilience-design.md`. The classifier change is owner-approved (S2).

- [ ] **Step 1:** filtered budget run `HSB_HOOK=agy-consult-recovery.sh`, then the scaling row (`pwsh -NoProfile -c "Invoke-Pester scripts/tests/hook-spawn-budget.Tests.ps1 -TagFilter scaling -Output Detailed -CI"`). Expected FAIL: 'one open seam', '1000 mixed seams'.
- [ ] **Step 2: Change the two suite rows the classifier changes (tests first).** In `scripts/tests/agy-consult-recovery.Tests.ps1`, replace

```powershell
  It 'treats agy-capstone-stage2.md as OFF-convention (unrecognised, not resolved)' {
    $r = New-Repo; Seam $r 'agy-capstone-stage2.md'
    (Run $r) | Should -Match 'unrecognised'
```

with

```powershell
  It 'classifies agy-capstone-stage2.md by its keyword: agy-capstone with an unknown round (r?)' {
    # Branch 20 (owner-approved S2): real seam names rarely follow agy-<token>-rN, so a whole-word keyword
    # now picks the token and a name with no -rN word renders its round as r?.
    $r = New-Repo; Seam $r 'agy-capstone-stage2.md'
    (Run $r) | Should -CMatch 'workflow position: agy-capstone r\?'
```

and in the row `rank 1 is never displaced by rank 2: ...` replace `1..3 | ForEach-Object { Seam $r "capstone-typo$_.md" }` with `1..3 | ForEach-Object { Seam $r "loose-typo$_.md" }` (a `capstone` word now makes a name rank 1, so the rank-2 fixtures must carry no keyword). Then add, after that row, inside the same `Describe`:

```powershell
  It 'classifies by whole-word keyword with precedence test-audit > capstone > panel|review > first' {
    $r = New-Repo
    Seam $r 'capstone-testaudit-fold-r3.md'; Seam $r 'python-gate-plan-review-r2.md'; Seam $r 's65-agy-first.md'
    $out = Run $r
    $out | Should -CMatch 'workflow position: agy-test-audit r3'
    $out | Should -CMatch 'workflow position: agy-panel r2'
    $out | Should -CMatch 'workflow position: agy-first r\?'
    Remove-Item -Recurse -Force $r
  }
  It 'does not match a keyword inside a longer word (capstoned, firstly, panels)' {
    $r = New-Repo; Seam $r 'capstoned-r3.md'; Seam $r 'my-firstly-r3.md'; Seam $r 'a-panels-r1.md'
    $out = Run $r
    $out | Should -Not -Match 'workflow position:'
    $out | Should -Match 'unrecognised'
    Remove-Item -Recurse -Force $r
  }
```

Run `pwsh -NoProfile -c "Invoke-Pester scripts/tests/agy-consult-recovery.Tests.ps1 -Output Detailed -CI"`. Expected: FAIL on exactly the changed first row and the two new rows (3 failures, 37 passed).

- [ ] **Step 3:** `git apply $P/03-consult-recovery.patch`
- [ ] **Step 4: Corrections.**
  (a) stdin (D4): replace the line `IFS= read -r -d '' input` (line 20 before the patch, line 25 after it; the patch leaves the line itself unchanged, and it is unique in the file) with `input=; while IFS= read -r -N 1048576 _c; do input+=$_c; done; input+=$_c`.
  (b) Grep the patched file for the stale comment references `line ~84` and `line 68` and make each point at the current line of what it names (the `*-reply.md` exclusion case; the `shopt -s nullglob` line).
- [ ] **Step 5:** `cp clavity-dotnet/plugin/hooks/agy-consult-recovery.sh clavity-classic/plugin/hooks/` and `bash -n` it.
- [ ] **Step 6:** filtered budget run -> all 3 rows + scaling row PASS (prototype: 11 total = 8 beyond boot with seams, flat 1..1000; concluded 3).
- [ ] **Step 7:** suite -> `Tests Passed: 40, Failed: 0`.
- [ ] **Step 8:** commit both hook copies and the suite: `perf(hooks): consult-recovery costs the same at 1 and 1000 seams; classify real seam names by keyword`.

**Known and kept (pre-existing, recorded so the panel can rule):** the `*-reply.md` exclusion needs a hyphen, so `x.reply.md` is a candidate (2 such files in this repo). Unchanged by this task.

### Task 5: agy-test-audit-reminder.sh (count + debounce)

**Files:** `clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh` + classic mirror; `scripts/tests/agy-test-audit-reminder.Tests.ps1`. **Oracle:** that suite (29 rows), `docs/agy-disciplines-marker-contract.md`, the file's own header (line 2-3: "exactly once for this HEAD").

- [ ] **Step 1:** filtered budget run `HSB_HOOK=agy-test-audit-reminder.sh`. Expected FAIL: every fire row on its count (prototype-measured before: 36 / 52 beyond boot; rename, merge and no-jq rows were never measured before - any count over 13 fails), and both debounced rows on `-Silent` (no debounce yet). The `no .clavity` row passes.
- [ ] **Step 2: Isolate the suite's TMPDIR (the debounce makes shared state).** The suite's payloads carry no `session_id`, so every row would share the debounce key `default`. Two fixtures built in the same second with the same content get the SAME HEAD sha, so a FIRES row could go silent. The file has ONE top-level `Describe` (`Describe 'agy-test-audit-reminder.sh'`, line 1); its nested `Describe`s inherit what its `BeforeAll` sets. At the END of that top-level `BeforeAll` (before its closing `}`), add:

```powershell
        # Branch 20 debounce: the hook keeps per-(session, HEAD) state under TMPDIR. Every row here runs with
        # session_id 'default', so give the suite its own TMPDIR and clear the state before each row.
        $script:savedTmpdir = [Environment]::GetEnvironmentVariable('TMPDIR')
        $script:suiteTmp = Join-Path ([IO.Path]::GetTempPath()) ('tar-tmp-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:suiteTmp | Out-Null
        $env:TMPDIR = ($script:suiteTmp -replace '\\', '/')
```

and directly after that `BeforeAll` block:

```powershell
    BeforeEach { Get-ChildItem -LiteralPath $script:suiteTmp -Filter 'claude-agy-test-audit-reminder.*' -ErrorAction SilentlyContinue | Remove-Item -Force }
    AfterAll {
        # [NullString]::Value DELETES the variable; $null would leave it present-and-empty (see BashHookHelpers.ps1).
        if ($null -eq $script:savedTmpdir) { [Environment]::SetEnvironmentVariable('TMPDIR', [NullString]::Value) } else { $env:TMPDIR = $script:savedTmpdir }
        Remove-Item -LiteralPath $script:suiteTmp -Recurse -Force -ErrorAction SilentlyContinue
    }
```

(If the top-level `Describe` already has an `AfterAll`, merge these two statements into it instead of adding a second one.) Then append a new top-level `Describe` at the END of the file:

```powershell
Describe 'agy-test-audit-reminder debounce (once per session and HEAD; Branch 20, owner ruling O4)' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh'
        $script:DTmp = Join-Path ([IO.Path]::GetTempPath()) ('tar-dbn-' + [Guid]::NewGuid().ToString('N'))
        $script:DHome = Join-Path ([IO.Path]::GetTempPath()) ('tar-dbh-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:DTmp, (Join-Path $script:DHome '.claude') -Force | Out-Null
        function New-DebounceRepo {
            # The FIRES shape the suite's New-FiredRepo builds: one executable commit at HEAD, capstone marker on it.
            $dir = New-TempRepo
            New-Item -ItemType Directory -Path (Join-Path $dir 'src'), (Join-Path $dir '.clavity/agy-marks') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'src/thing.cs') -Value 'x' -Encoding ascii
            & git -C $dir add -- src/thing.cs
            & git -C $dir -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= commit -qm work
            Set-Content -LiteralPath (Join-Path $dir '.clavity/agy-marks/agy-capstone.head') -Value (& git -C $dir rev-parse HEAD).Trim() -NoNewline
            $dir
        }
        function Invoke-Debounced { param([string]$Dir, [string]$Sid, [string]$Tmp = $script:DTmp)
            $p = @{ tool_name = 'Bash'; tool_input = @{ command = 'ls' }; cwd = ($Dir -replace '\\', '/'); session_id = $Sid } | ConvertTo-Json -Compress
            Invoke-BashHook -HookPath $script:Hook -Payload $p -Env @{ TMPDIR = ($Tmp -replace '\\', '/'); HOME = ($script:DHome -replace '\\', '/') }
        }
    }
    AfterAll { Remove-Item -LiteralPath $script:DTmp, $script:DHome -Recurse -Force -ErrorAction SilentlyContinue }
    BeforeEach { Get-ChildItem -LiteralPath $script:DTmp -Force | Remove-Item -Recurse -Force }

    It 'fires on the first call and is silent on the second at the same HEAD and session' {
        $d = New-DebounceRepo
        try {
            (Invoke-Debounced $d 's1').StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire'
            (Invoke-Debounced $d 's1').StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'fires again for another session at the same HEAD' {
        $d = New-DebounceRepo
        try {
            (Invoke-Debounced $d 's1').StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire'
            (Invoke-Debounced $d 's2').StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'fires again after HEAD moves, in the same session' {
        $d = New-DebounceRepo
        try {
            (Invoke-Debounced $d 's1').StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire'
            (Invoke-Debounced $d 's1').StdOut | Should -BeNullOrEmpty
            Set-Content -LiteralPath (Join-Path $d 'src/other.cs') -Value 'y' -Encoding ascii
            & git -C $d add -- src/other.cs
            & git -C $d -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= commit -qm more
            Set-Content -LiteralPath (Join-Path $d '.clavity/agy-marks/agy-capstone.head') -Value (& git -C $d rev-parse HEAD).Trim() -NoNewline
            (Invoke-Debounced $d 's1').StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'still fires on every call when its state cannot be written (TMPDIR is a file)' {
        $d = New-DebounceRepo
        $f = Join-Path $script:DTmp 'not-a-dir'; Set-Content -LiteralPath $f -Value 'x'
        try {
            (Invoke-Debounced $d 's1' $f).StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire'
            (Invoke-Debounced $d 's1' $f).StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire' -Because 'a debounce that cannot record must fail toward reminding, never toward silence'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'keeps its state under TMPDIR only - the repo is untouched' {
        $d = New-DebounceRepo
        try {
            $before = (& git -C $d status --porcelain --ignored) -join "`n"
            $null = Invoke-Debounced $d 's1'
            ((& git -C $d status --porcelain --ignored) -join "`n") | Should -BeExactly $before
            Test-Path -LiteralPath (Join-Path $script:DTmp 'claude-agy-test-audit-reminder.s1') | Should -BeTrue
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
```

Run the suite: exactly 3 of these 5 new rows FAIL before the patch (the 6th row, added in Step 4(c), is written then and also fails before the patch): 'fires on the first call...', 'fires again after HEAD moves...' (each because the repeat call is not silent) and 'keeps its state under TMPDIR only' (no state file). 'fires again for another session' and 'still fires ... TMPDIR is a file' pass today and stay as guards against a debounce that silences too much. The 29 old rows pass.
- [ ] **Step 3:** `git apply $P/04-test-audit-reminder.patch`
- [ ] **Step 4: Corrections.**
  (a) D2: in the patched `emit()` function delete the line `  case "$OSTYPE" in msys*|cygwin*|win32*) eol=$'\r' ;; esac` and change `local m=$1 eol=''` to `local m=$1`, and the `printf` format `'{"hookSpecificOutput":...}%s\n' "$m" "$eol"` to the same format without the trailing `%s` and without `"$eol"`.
  (b) D4: in the line `if command -v jq >/dev/null 2>&1; then _have_jq=1; else _have_jq=''; IFS= read -r -d '' input; fi` replace `IFS= read -r -d '' input` with `input=; while IFS= read -r -N 1048576 _c; do input+=$_c; done; input+=$_c`.
  (c) Re-arm on compaction (ruling O6-B). The reminder's own text tells the user to `/compact`, and a compaction summarizes the one emitted reminder away. In `clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh`, directly after the line `event="${1:-PreCompact}"`, insert:

```bash
# Branch 20 (owner ruling 2026-10-05, agreed with agy): a compaction summarizes away the AGY-TEST-AUDIT
# reminder, and its once-per-(session, HEAD) debounce (agy-test-audit-reminder.sh, _set_state) would keep it
# silent at this HEAD for the rest of the session. Re-arm it by deleting this session's debounce file. The
# session-id sanitising is _set_state's, character for character, so both sides name the same file.
# Builtins plus one rm, PreCompact only, before any early exit.
if [ "$event" = "PreCompact" ]; then
  _rs=''
  [[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && _rs=${BASH_REMATCH[1]}
  _ok='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-'
  _rs=${_rs//[^$_ok]/_}; [ -n "$_rs" ] || _rs=default
  _rf="${TMPDIR:-/tmp}/claude-agy-test-audit-reminder.$_rs"
  [ -e "$_rf" ] && rm -f -- "$_rf" 2>/dev/null
fi
```

  (d) D4 for the newly touched hook (agy panel R1): in `agy-anomaly-capture-reminder.sh`, replace its line `input=$(cat)` with `input=; while IFS= read -r -N 1048576 _c; do input+=$_c; done; input+=$_c`.
  Add to Step 2's debounce `Describe` (before its closing `}`), using a `$script:Capture` path set in its `BeforeAll` as `Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh'`:

```powershell
    It 'fires again after a compaction in the same session (PreCompact re-arms it)' {
        $d = New-DebounceRepo
        try {
            (Invoke-Debounced $d 's1').StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire'
            (Invoke-Debounced $d 's1').StdOut | Should -BeNullOrEmpty
            $pc = @{ cwd = ($d -replace '\\', '/'); session_id = 's1'; hook_event_name = 'PreCompact'; trigger = 'manual' } | ConvertTo-Json -Compress
            $null = Invoke-BashHook -HookPath $script:Capture -Payload $pc -Arguments @('PreCompact') -Env @{ TMPDIR = ($script:DTmp -replace '\\', '/'); HOME = ($script:DHome -replace '\\', '/') }
            (Invoke-Debounced $d 's1').StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire' -Because 'a compaction summarized the reminder away, so it must come back once'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

  And add this budget row to `hook-spawn-budget.Rows.ps1`, after the existing `agy-anomaly-capture-reminder.sh` 'PreCompact' row:

```powershell
    New-BudgetRow "$D/agy-anomaly-capture-reminder.sh" 'PreCompact re-arming a test-audit debounce' {
        param($fx)
        Set-Content -LiteralPath (Join-Path $fx.Tmp 'claude-agy-test-audit-reminder.s1') -Value 'deadbeef'
        ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'PreCompact'; trigger = 'manual' }
    }
```

  (Give it `-Silent` or `-Expect` per Task 2 Step 4b - the PreCompact arm's output does not change.)
- [ ] **Step 5:** mirror `agy-test-audit-reminder.sh` AND `agy-anomaly-capture-reminder.sh` to classic; `bash -n` both.
- [ ] **Step 6:** filtered budget runs `HSB_HOOK=agy-test-audit-reminder.sh` -> 8 rows PASS (prototype: worst fire 15 total = 12 beyond boot; debounced 8 total), and `HSB_HOOK=agy-anomaly-capture-reminder.sh` -> its rows PASS (PreCompact was 11 total; the re-arm adds at most one `rm`).
- [ ] **Step 7:** suite -> `Tests Passed: 35, Failed: 0`; then `pwsh -NoProfile -c "Invoke-Pester scripts/tests/agy-anomaly-capture-reminder.Tests.ps1 -Output Detailed -CI"` -> no failures (the PreCompact arm's output is unchanged). The four paths the prototype never measured (rename in range, merge commit in range, no-jq ledger fire, no-jq debounced) are budget rows since Task 2 (agy panel R2); the filtered budget run in Step 6 covers them - each must pass at most 13 beyond boot. A row over 13 is a STOP: report it, do not widen the budget.
- [ ] **Step 8:** commit both copies of agy-test-audit-reminder.sh AND agy-anomaly-capture-reminder.sh, the suite and hook-spawn-budget.Rows.ps1: `perf(hooks): test-audit reminder fires once per session and HEAD, 55 -> 15 processes on its worst path`.

### Task 6: agy-after-reminder.sh

**Oracle:** `scripts/tests/agy-after-reminder.Tests.ps1` (14 rows). No debounce (its header: "If the artifact is genuinely mid-draft (incomplete), defer until the final write" - it fires per write by design).

- [ ] **Step 1:** filtered budget run `HSB_HOOK=agy-after-reminder.sh` -> both rows FAIL (17 / 19 beyond boot).
- [ ] **Step 2:** `git apply $P/05-after-reminder.patch`
- [ ] **Step 3: Corrections:** D4 - replace `IFS= read -r -d '' input` in its `command -v jq ... else ... fi` line with the chunked loop, exactly as Task 5 Step 4(b). Confirm `grep -n OSTYPE clavity-dotnet/plugin/hooks/agy-after-reminder.sh` prints nothing.
- [ ] **Step 4-5:** mirror; `bash -n`.
- [ ] **Step 6:** budget rows PASS (prototype 5 / 7 total).
- [ ] **Step 7:** suite -> `Tests Passed: 14, Failed: 0`.
- [ ] **Step 8:** commit: `perf(hooks): AGY-AFTER reminder 22 -> 7 processes`.

### Task 7: agy-seam-inject.sh + agy-liveness-check.sh

**Oracle:** `scripts/tests/agy-seam-inject.Tests.ps1` (36 rows, includes the byte-identical-mirror row), `scripts/tests/agy-liveness-check.Tests.ps1` (40 rows).

- [ ] **Step 1:** filtered budget runs `HSB_HOOK=agy-seam-inject.sh`, `HSB_HOOK=agy-liveness-check.sh` -> FAIL: both seam fire rows, liveness 'three settings files, one a personal duplicate (warns)'.
- [ ] **Step 2 (Q1, tests first):** add to `scripts/tests/agy-liveness-check.Tests.ps1`, inside `Describe 'agy-liveness-check.sh'`, directly after the row `It 'reports the unreadable settings file BUT continues the sweep'` (same fixture shape: user-scope settings via `CLAUDE_CONFIG_DIR`, the file's own `New-CleanHome` and `Payload` helpers):

```powershell
    It 'reports a settings file holding TWO JSON documents as unreadable (Branch 20, owner ruling Q1)' {
        # `jq -e .` and `jq -s` accept a document STREAM, so this file passed silently before Branch 20, while
        # Claude Code itself rejects it. One `try fromjson` per file now reports it like any corrupt file.
        $cfg = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-cfg-" + [Guid]::NewGuid().ToString('N'))
        $h = New-CleanHome
        try {
            New-Item -ItemType Directory -Path $cfg -Force | Out-Null
            '{"a":1} {"b":2}' | Set-Content (Join-Path $cfg 'settings.json') -Encoding ascii
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -Match 'settings unreadable'
        } finally { Remove-Item $cfg, $h -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

Run the suite: this one row FAILS today (40 pass).
- [ ] **Step 3:** `git apply $P/06-seam-inject.patch $P/07-liveness-check.patch`
- [ ] **Step 4: Corrections.**
  (a) D4 in both files: replace `IFS= read -r -d '' input` with the chunked loop.
  (b) seam-inject, the 17-process path: replace the whole block from the line `_pair=$(jq -r '(.tool_input.skill // "") as $s | (.cwd // ".") as $c` through the `esac` that closes `case "$_pair" in` (and its 5-line comment above, starting `# ONE jq call yields both fields`) with:

```bash
# ONE jq call for both fields, NUL-separated, read by builtins: exact for any string, and no fallback path
# that calls jq again (the prototype's fallback measured 17). -j writes no newline, so the Windows jq's CRLF
# never reaches a value. `$(...)` used to strip trailing newlines; the two expansions below keep that.
skill=; cwd=
{ IFS= read -r -d '' skill; IFS= read -r -d '' cwd; } < <(jq -j '(.tool_input.skill // ""), "\u0000", (.cwd // "."), "\u0000"' <<<"$input" 2>/dev/null)
skill=${skill%"${skill##*[!$'\n']}"}
cwd=${cwd%"${cwd##*[!$'\n']}"}
```

  Known residue, accepted: a JSON string containing `\u0000` now splits at it (before: bash dropped the NUL with a warning).
- [ ] **Step 5:** mirror both; `bash -n` both.
- [ ] **Step 6:** both filtered budget runs PASS (prototype seam worst 16 total = 13 beyond boot - AT the ceiling; the newline row must now also be <= 13).
- [ ] **Step 7:** `agy-seam-inject.Tests.ps1` -> `Tests Passed: 36, Failed: 0`; `agy-liveness-check.Tests.ps1` -> `Tests Passed: 41, Failed: 0` (run them one after the other, never together).
- [ ] **Step 8:** commit 4 hook files + the liveness suite: `perf(hooks): seam-inject 21 -> 13 and liveness-check 34 -> 11 processes`.

### Task 8: agy-drive-session-reset.sh (classic only)

**Oracle:** `scripts/tests/agy-drive-session-reset.Tests.ps1` (6 rows).

- [ ] **Step 1:** filtered budget run `HSB_HOOK=agy-drive-session-reset.sh` -> FAIL (15 beyond boot).
- [ ] **Step 2:** `git apply $P/08-drive-session-reset.patch`
- [ ] **Step 3: Corrections:** D4 - replace `IFS= read -r -d '' input 2>/dev/null` with `input=; while IFS= read -r -N 1048576 _c 2>/dev/null; do input+=$_c; done; input+=$_c`.
- [ ] **Step 4:** no mirror (classic-only); `bash -n`.
- [ ] **Step 5-6:** budget row PASS (prototype 10 total); suite `Tests Passed: 6, Failed: 0`.
- [ ] **Step 7:** commit: `perf(hooks): drive-session reset 18 -> 10 processes`.

### Task 9: agy-curate-nudge.sh (agy-autotrain)

**Oracle:** `scripts/tests/agy-curate-nudge.Tests.ps1` (20 rows).

- [ ] **Step 1:** filtered budget run `HSB_HOOK=agy-curate-nudge.sh` -> 'worst' row FAILS (27 beyond boot).
- [ ] **Step 2:** `git apply $P/09-curate-nudge.patch`
- [ ] **Step 3: Corrections.**
  (a) D2: replace the 3 lines starting `  # MEASURED: the Windows-native jq.exe on this box ends its output with CRLF` through `  eol=$'\n'; [[ $OSTYPE == msys* || $OSTYPE == cygwin* ]] && eol=$'\r\n'` with `  eol=$'\n'`.
  (b) D4: replace `IFS= read -r -d '' input 2>/dev/null` with the chunked loop (as Task 8).
- [ ] **Step 4:** no mirror; `bash -n`.
- [ ] **Step 5-6:** budget rows PASS (prototype worst 15 total); suite `Tests Passed: 20, Failed: 0`.
- [ ] **Step 7:** commit: `perf(hooks): curate nudge 30 -> 15 processes on its worst path`.

### Task 10: Whole-branch gates and mutation proofs

- [ ] **Step 1:** full budget suite: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/hook-spawn-budget.Tests.ps1 -Output Detailed -CI"`. Expected: exactly ONE failure, the Branch 21 debt row.
- [ ] **Step 2: Mutation proofs (each must turn its row RED, then be reverted; verify `git diff --stat` is empty afterwards).**
  (a) Scaling row: in `clavity-dotnet/plugin/hooks/agy-consult-recovery.sh`, after the line that fills `_seams=(...)`, insert `[ ${#_seams[@]} -gt 1 ] && /usr/bin/true` (2 extra processes with 1000 seams, none with 1 - so the row fails on its ASSERTION; a per-seam mutant would cost ~2000 processes and die on the harness's 120 s timeout instead, proving nothing about the assertion). Run the suite with `-TagFilter scaling` -> FAIL. `git restore` the file.
  (b) Ceiling row: in `agy-after-reminder.sh`, after `set +e`, insert 7 lines `/usr/bin/true`. Run the filtered budget run with `HSB_HOOK=agy-after-reminder.sh` -> 'non-plan Edit' FAILS (14 more). Restore.
  (c) Census row: add `{ "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/zz-unbudgeted.sh\"" }` to the `PreCompact` hooks array of `clavity-dotnet/plugin/hooks/hooks.json`. Run the suite with `-TagFilter census` (HSB_HOOK unset) -> FAIL naming `zz-unbudgeted.sh`. Restore.
  (d) Silent guard: in `agy-consult-guard-pre.sh` insert `echo leak` after the stdin loop. Run the filtered budget run with `HSB_HOOK=agy-consult-guard-pre.sh` -> its silent rows FAIL. Restore.
- [ ] **Step 2b: Pester 6 (CI pins it: `.github/workflows/ci-scripts.yml` installs `-MinimumVersion 6.0.0`; this plan's discovery filter and tags were measured under the local Pester 5 only).** `pwsh -NoProfile -c "Save-Module Pester -MinimumVersion 6.0.0 -MaximumVersion 6.99.99 -Path <session scratchpad>/pester6 -Force"`, then `pwsh -NoProfile -c "Import-Module <session scratchpad>/pester6/Pester -Force; Invoke-Pester scripts/tests/hook-spawn-budget.Tests.ps1 -Output Detailed -CI"` -> same outcome as Step 1. Repeat with `HSB_HOOK=agy-after-reminder.sh` and `-TagFilter row` -> exactly 2 tests. A different count under Pester 6 is a STOP.
- [ ] **Step 3: Repo gates (one at a time).** `just seed-sync-check` (exit 0); `pwsh -NoProfile -c "Invoke-Pester scripts/tests/plugin-hooks-registration.Tests.ps1 -Output Detailed -CI"` (`Tests Passed: 37`); `just check-injected-context` (exit 0 - the reminders now build their message in bash; if the injected-context corpus can no longer see a hook message, that is a finding, report it); `just test-scripts-fast` (backgrounded; no failures); `just test-scripts-slow` (backgrounded; exactly one failure: the debt row).
- [ ] **Step 4: CI's jq (ruling O6-C, agreed with agy).** Chocolatey's `bin\jq.exe` on `windows-latest` is a shim that starts the real `jq.exe` as a child, so every jq call would count one extra process on CI only and push at-ceiling rows (seam-inject worst = 13) over. NOT measurable here - verified on the first CI run. In `.github/workflows/ci-scripts.yml`, insert this step immediately BEFORE the step named `Install Pester v6`:

```yaml
      - name: Put the real jq first on PATH (Branch 20 process budget)
        shell: pwsh
        run: |
          # Chocolatey's bin\jq.exe is a shim that starts lib\...\jq.exe as a CHILD, so every jq call costs one
          # extra process in scripts/tests/hook-spawn-budget.Tests.ps1. Prepend the real binary's directory.
          $real = Get-ChildItem 'C:\ProgramData\chocolatey\lib' -Recurse -Filter jq.exe -ErrorAction SilentlyContinue | Select-Object -First 1
          if ($real) { $real.DirectoryName | Out-File -FilePath $env:GITHUB_PATH -Append -Encoding utf8; "real jq: $($real.FullName)" }
          else { '::warning title=hook budget::no Chocolatey jq under C:\ProgramData\chocolatey\lib - PATH unchanged; if a hook-spawn-budget row fails on CI only, a jq shim (one extra process per call) is the first suspect' }
```

  Commit it with Task 12. **First-CI-run check (owner pushes):** in that run's log, the step prints `real jq: ...` and the budget suite has no failed `row` test. If a `row` test fails on CI only, apply the fallback: in `hook-spawn-budget.Tests.ps1`, at the start of the `-ForEach $Rows` `It` body, add `if ($env:GITHUB_ACTIONS) { Set-ItResult -Skipped -Because 'process budgets are measured on the owner''s machine; CI jq differs' }` and record the CI difference in ROADMAP section 69.

### Task 11: S4 - SessionStart timeouts, re-measured (TOP-LEVEL ONLY)

Timing discipline (`~/.claude/CLAUDE.md`): the orchestrator runs this, never a subagent; launch backgrounded and make NO tool call until it completes; first verify no other test or measurement process is running; two runs, quote the range; name the uncontrolled background load.

- [ ] **Step 1:** save this as `sessionstart-timing.ps1` in the session scratchpad. It starts EVERY dotnet SessionStart hook at once, as Claude Code does, through Git's launcher (the production bash). The fixture is a temp repo with 1031 seams (this repo's count) and a temp HOME and TMPDIR, and the script prints each hook's wall-clock to exit:

```powershell
. (Join-Path 'C:\Users\user\Development\Rust\clavity\scripts\tests' 'BashHookHelpers.ps1')
$root = 'C:\Users\user\Development\Rust\clavity'
$bash = Get-GitBashOrThrow                                   # Git's launcher: how Claude Code runs hooks
$fx = Join-Path ([IO.Path]::GetTempPath()) ('sst-' + [Guid]::NewGuid().ToString('N'))
$repo = Join-Path $fx 'repo'; $homeDir = Join-Path $fx 'home'; $tmp = Join-Path $fx 'tmp'
New-Item -ItemType Directory -Force -Path (Join-Path $repo '.clavity\seams'), (Join-Path $homeDir '.claude'), (Join-Path $homeDir '.clavity'), $tmp | Out-Null
& git -C $repo init -q -b main; & git -C $repo -c user.email=t@t -c user.name=t -c commit.gpgsign=false -c core.hooksPath= commit --allow-empty -qm init
Set-Content -LiteralPath (Join-Path $repo '.clavity\.gitignore') -Value '*'
1..1031 | ForEach-Object { [IO.File]::WriteAllText((Join-Path $repo ".clavity\seams\agy-capstone-r$_-x.md"), 'x') }
$payload = Join-Path $fx 'payload.json'
[IO.File]::WriteAllText($payload, (@{ cwd = ($repo -replace '\\', '/'); session_id = 'sst'; hook_event_name = 'SessionStart'; source = 'startup' } | ConvertTo-Json -Compress))
$hooks = (Get-Content -Raw "$root\clavity-dotnet\plugin\hooks\hooks.json" | ConvertFrom-Json).hooks.SessionStart |
    ForEach-Object { $_.hooks } | ForEach-Object { [regex]::Match($_.command, 'hooks/([A-Za-z0-9._-]+\.sh)').Groups[1].Value } | Sort-Object -Unique
$env:HOME = ($homeDir -replace '\\', '/'); $env:USERPROFILE = $homeDir; $env:TMPDIR = ($tmp -replace '\\', '/')
$env:CLAUDE_PROJECT_DIR = $repo; $env:CLAUDE_CONFIG_DIR = Join-Path $homeDir '.claude'; $env:CLAUDE_PLUGIN_DATA = ''; $env:CLAUDE_PLUGIN_ROOT = ''
$sw = [Diagnostics.Stopwatch]::StartNew()
$procs = foreach ($h in $hooks) {
    $psi = [Diagnostics.ProcessStartInfo]::new($bash)
    $psi.ArgumentList.Add(("$root\clavity-dotnet\plugin\hooks\$h" -replace '\\', '/'))   # inner parens: a bare comma would split the call into 2 args
    $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write([IO.File]::ReadAllText($payload)); $p.StandardInput.Close()
    $o = $p.StandardOutput.ReadToEndAsync(); [void]$p.StandardError.ReadToEndAsync()
    [pscustomobject]@{ Hook = $h; P = $p; O = $o }
}
# stdout bytes prove each hook RAN (a run that printed 0 everywhere measured nothing - it happened once).
foreach ($x in $procs) { $x.P.WaitForExit(); '{0,-36} {1,7:N1} s  stdout={2} B' -f $x.Hook, $x.P.ExitTime.Subtract($x.P.StartTime).TotalSeconds, $x.O.Result.Length }
'all done after {0:N1} s' -f $sw.Elapsed.TotalSeconds
Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue
```

- [ ] **Step 2:** run it twice with `pwsh -NoProfile -File <scratchpad>/sessionstart-timing.ps1`, backgrounded, making no other tool call until it completes. First verify that no other test or measurement process is running (`Get-Process pwsh, bash`). Quote the range of the two runs per hook and name the uncontrolled background load.
- [ ] **Step 3: Decision rule:** if `agy-discipline-reaching.sh` and `agy-consult-recovery.sh` both finish under 5 s (half their 10 s timeout) in both runs, leave `hooks.json` unchanged and record the figures in the commit message of Task 12. Otherwise raise both `"timeout": 10` to `"timeout": 30` in `clavity-dotnet/plugin/hooks/hooks.json` (lines 58-59) and `clavity-classic/plugin/hooks/hooks.json` (lines 57-58), and run `plugin-hooks-registration.Tests.ps1` again.

### Task 12: ROADMAP sections 69 and 70, partition, handoff

- [ ] **Step 1:** append to `clavity-dotnet/ROADMAP.md` after section 68:

```markdown
### §69 — Branch 21: the eight census-found hooks over the 16-process ceiling — ▶ **PROMOTED 2026-10-04 (owner split of Branch 20), not yet planned**

The Branch 20 census (`.clavity/scratch/hook-perf/b20-protos/scratch-b20/census-other-hooks.md`) measured 44 paths over
the ceiling in `agy-inbox-snapshot` (up to 67 with 20 baks: one `rm` per surplus bak), `agy-discipline-reaching` (36 on a
`!`-negated shield), `agy-anomaly-reminder` (23 whenever an entry is untriaged: a grep|awk|grep|sort|head chain),
`agy-verify-reminder` (22-24 whenever agy is on PATH), `docs-audit-reminder` (22 on any generated view: tr + 3 printf|grep),
`assertion-strength-reminder` (17-21), `fetch-clavity-ls` (17 in steady state, 20-35 elsewhere) and `migrate-inbox` (17
on recovery). Each is a named entry of `$B21Debt` in `scripts/tests/hook-spawn-budget.Rows.ps1`; the suite's debt row is
RED until the list is empty. Done = every entry replaced by a passing budget row.

### §70 — the consult guard's consult path costs ~115 processes a side — ▶ **PROMOTED 2026-10-04 (owner ruling 3), not yet planned**

`agy_guard_quad` + the gitignored-path census run on every real consult, pre and post (measured 2026-10-04 after Branch
20: pre 114-120, post 117-129 total). Branch 20 pinned it (`$ConsultPin`) so it cannot grow. Needs its own design consult:
what each axis costs, which axes can share one git call.
```

- [ ] **Step 2:** update `_partition.md` counts for every suite this branch changed (`agy-consult-recovery` 40, `agy-test-audit-reminder` 34, `agy-liveness-check` 41) and re-run `test-suite-registration.Tests.ps1` (`Tests Passed: 9`).
- [ ] **Step 3:** commit `clavity-dotnet/ROADMAP.md`, `scripts/tests/_partition.md` and `.github/workflows/ci-scripts.yml` (Task 10 Step 4): `docs(roadmap): section 69 (Branch 21 hooks) and 70 (consult-path budget); partition counts; CI real jq`.
- [ ] **Step 4:** hand off to AGY-CAPSTONE (`clavity:agy-capstone`) on the committed range `4f0cb6a7..HEAD`.

---

## Self-audit (driver, at writing)

- **Spec coverage:** S1 (count gate + scaling row, proven red by mutants) = Tasks 1, 2, 10; S2 (consult-recovery regex + builtins, keep "+N more") = Task 4; S3 (debounce + fork cuts) = Tasks 5, 6; S4 = Task 11; S5 (Branch 19 test-audit first) = done before this branch. Owner rulings O1-O3: ceiling everywhere (rows for all nine; census row for all 22 registered hooks (measured: the census regex over the 4 registries yields 22 names)), consult path pinned (Task 2 pins, Task 12 section 70), split (debt row, section 69).
- **Gaps left open, with where they close:** Q1 is the owner's (approve with the plan). The four unmeasured test-audit paths are measured in Task 5 Step 7, with a STOP if any is over. Task 5's debounce row bodies are specified by assertion, not pasted: they reuse that suite's own FIRES fixture, whose helper name must be read from the file, not invented here. Task 7's Q1 row copies the suite's existing corrupt-file assertion, for the same reason. The pinned consult limits come from a prototype fixture of the same shape (plain temp repo); if a pinned row fails in Task 2 Step 4 before any hook changes, the pin is wrong, not the hook: re-measure and STOP to report.
- **Verified at writing:** `Invoke-Pester -FullNameFilter` does NOT match `-ForEach` rows by their expanded `<Hook>` names (measured: a filter on a hook name ran 0 tests). Hence the `HSB_HOOK` discovery filter plus `-Tag` (measured: `HSB_HOOK=agy-after-reminder.sh` + `-TagFilter row` ran exactly that row and excluded the debt row). A 0-test run is a FAILURE.

## Stand-downs (AGY-AFTER panel, 2026-10-04..06; 4 rounds: Opus solo + agy x4; GREEN at round 4)

- `DISCARDED-BELOW-FLOOR`: the harness's boot spin-wait (`while [ ! -e ... ]; do :; done`) burns a core - unreachable as a cost because `Invoke-JobCountedBash` creates the release file on the line right after `[ClavityJobCount]::Assign(...)` (Task 1 Step 3), so each spin lasts milliseconds (agy R4).
- `UNVERIFIED-ACCEPTED`: Chocolatey's `jq.exe` on `windows-latest` is a shim that adds one process per call - not measurable on this box; the owner accepted the risk with ruling O6-C (real jq first on CI's PATH, verified on the first CI run, local-only rows as the fallback).
- `UNVERIFIED-ACCEPTED`: whether `/compact` keeps the `session_id` - left unmeasured because ruling O6-B (PreCompact re-arms the debounce) is correct either way.
- `DEFERRED-TO-ANOMALIES: docs/superpowers/plans/2026-10-04-sweep-branch-20-hook-spawn-budget/04-test-audit-reminder.patch * 2026-10-05 * unverified` - debounce state files are never cleaned up.
- `REJECTED` (recorded so they are not re-raised): the census crashing on a missing `.claude/settings.json` (it is tracked: `git ls-files .claude/settings.json`); the harness PATH export putting jq back for the no-jq rows (measured: with PATH `<Git>\usr\bin` plus the export, `command -v jq` finds nothing and git resolves to `/mingw64/bin/git` - Git for Windows ships no jq).
- **For the owner at approval** (a challenge to an owner-settled decision, so not resolved by the driver): agy R3 argued that a debt row which is ALWAYS red locally trains its reader to ignore red. Mitigation already in the plan: Task 10 Step 3 checks WHICH row fails ("exactly one failure: the debt row"), and the row's message names every debt entry.

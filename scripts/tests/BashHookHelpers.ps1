# Shared Pester helpers for driving the shipped bash hooks with synthetic payloads.
# Dot-source from a *.Tests.ps1 BeforeAll: . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')

function Get-GitBashOrThrow {
    # Claude Code runs plugin hooks with Git Bash on Windows; pin it explicitly. `Get-Command bash` is
    # NON-DETERMINISTIC: locally it resolves to WSL's C:\WINDOWS\System32\bash.exe (own filesystem, cannot
    # run a Windows-path hook); CI (no WSL) resolves to Git Bash. Prefer the standard Git install, else the
    # first PATH bash that is NOT the System32 WSL shim.
    $candidates = @(
        'C:\Program Files\Git\bin\bash.exe',
        'C:\Program Files (x86)\Git\bin\bash.exe'
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
    $onPath = Get-Command bash -All -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notmatch '\\System32\\bash\.exe$' } |
        Select-Object -First 1 -ExpandProperty Source
    if ($onPath) { return $onPath }
    throw 'Git Bash not found on PATH; the SP-D hook tests require Git Bash (not WSL bash).'
}

function New-TempRepo {
    # A throwaway git repo so a hook's `git -C "$cwd" rev-parse HEAD` has a real HEAD without touching
    # the real repo. Returns the dir path (Windows form); callers forward-slash it for the payload cwd.
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    & git -C $dir init -q
    & git -C $dir -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= commit --allow-empty -qm init
    return $dir
}

function Invoke-BashHook {
    # Run a bash hook with a synthetic JSON payload on stdin. Captures stdout, stderr, and the exit code
    # separately (SP-D hooks emit user-visible notices on STDERR with exit 2). $Env overrides are applied
    # process-wide for the call then restored; use ABSOLUTE paths for HOME (MSYS mangles relative values).
    param(
        [Parameter(Mandatory)][string]$HookPath,
        [string]$Payload = '{}',
        [hashtable]$Env = @{},
        [string[]]$Arguments = @()
    )
    # THE HOOK MUST EXIST, ASSERTED HERE RATHER THAN IN FOURTEEN SUITES. bash reports a missing script
    # on STDERR as "No such file or directory" and the message CONTAINS THE HOOK'S OWN FILENAME - so a
    # suite that runs the hook through `2>&1` and matches a bare substring of that name passes with
    # nothing implemented. That is not hypothetical here: `assertion-strength-reminder.Tests.ps1` records
    # being measured green with NO HOOK ON DISK, five FIRES rows plus three more, and carries an
    # existence guard of its own because of it. Three suites learned that lesson individually; eleven did
    # not. Asserting it in the shared entry point covers every caller at once, including the ones written
    # after this comment.
    if (-not (Test-Path -LiteralPath $HookPath)) {
        throw "Invoke-BashHook: the hook '$HookPath' does not exist - every assertion against its output would be vacuous, because bash echoes the missing filename to stderr and a substring match on it passes"
    }
    $bash = Get-GitBashOrThrow
    $hookPosix = ($HookPath -replace '\\','/')
    # ABSENCE AND EMPTINESS ARE DIFFERENT STATES, and restoring them is not the same operation.
    # Conflating them leaked for real: `[Environment]::SetEnvironmentVariable($k, $null)` does NOT
    # delete the key in PowerShell, it leaves it PRESENT WITH AN EMPTY VALUE. Measured, all four forms:
    #     SetEnvironmentVariable(n, $null)               -> present=True  value=[]
    #     SetEnvironmentVariable(n, '')                  -> present=True  value=[]
    #     SetEnvironmentVariable(n, [NullString]::Value) -> present=False
    #     Remove-Item Env:n                              -> present=False
    # So restoring a previously-ABSENT variable with the saved $null re-created it as empty, and every
    # later child process in the same Pester run inherited it. That is not cosmetic on this platform:
    # MSYS/Git Bash converts an EMPTY TMPDIR into the bogus relative path `<cwd>/=` instead of passing
    # it through empty, so `${TMPDIR:-/tmp}` never defaults. A suite at position 5 overriding TMPDIR
    # therefore poisoned every bash child that ran after it - which is why agy-shield-lib.Tests.ps1
    # passed 39/39 in ISOLATION and failed 5 rows in the full sweep and in CI.
    $saved = @{}
    $wasAbsent = @{}
    $errFile = [IO.Path]::GetTempFileName()
    try {
        # Inside the try on purpose: this used to run BEFORE it, so anything that threw between the
        # mutation and the try left the override installed permanently, with no finally to undo it.
        foreach ($k in $Env.Keys) {
            # CASE-INSENSITIVE, because the setter is. `GetEnvironmentVariables().Contains($k)` is a
            # plain Hashtable lookup and is case-SENSITIVE, so it reports a PRESENT variable as absent
            # whenever the caller's casing differs from the block's actual key - and this restore would
            # then DELETE it. MEASURED on a block whose real key is `PATH`:
            #     Contains('PATH') = True      GetEnvironmentVariable('PATH') = <value>
            #     Contains('Path') = False     GetEnvironmentVariable('Path') = <value>   <-- disagree
            # Shipped that way once: locally the casings happened to align so a 989/0 sweep passed, and
            # CI - where they did not - deleted PATH and every hook lost `jq`.
            # GetEnvironmentVariable returns $null ONLY for a genuinely absent variable; a present-but-
            # empty one returns '', which is exactly the distinction this restore turns on.
            $wasAbsent[$k] = ($null -eq [Environment]::GetEnvironmentVariable($k))
            $saved[$k] = [Environment]::GetEnvironmentVariable($k)
            [Environment]::SetEnvironmentVariable($k, $Env[$k])
        }
        $out = ($Payload | & $bash $hookPosix @Arguments 2>$errFile | Out-String)
        $code = $LASTEXITCODE
        $err = (Get-Content -Raw -LiteralPath $errFile -ErrorAction SilentlyContinue)
        if ($null -eq $err) { $err = '' }
        [pscustomobject]@{ StdOut = $out.Trim(); StdErr = $err.Trim(); ExitCode = $code }
    } finally {
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
        foreach ($k in $saved.Keys) {
            if ($wasAbsent[$k]) {
                # [NullString]::Value is the only form that DELETES - see the note above.
                [Environment]::SetEnvironmentVariable($k, [NullString]::Value)
            }
            else {
                [Environment]::SetEnvironmentVariable($k, $saved[$k])
            }
        }
    }
}

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
    static BASIC Query(IntPtr j) { BASIC b; if (!QueryInformationJobObject(j, 1, out b, Marshal.SizeOf(typeof(BASIC)), IntPtr.Zero)) throw new Exception("QueryInformationJobObject " + Marshal.GetLastWin32Error()); return b; }
    public static uint Total(IntPtr j) { return Query(j).TotalProcesses; }
    public static uint Active(IntPtr j) { return Query(j).ActiveProcesses; }
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
        # core.fsmonitor OFF for the hook's git calls (capstone R6 HB1, owner ruling 2026-10-06, agreed with agy): with
        # it on, `git status` starts git's fsmonitor daemon INSIDE the job and the drain below waited 30 s and threw
        # (MEASURED). A real user pays that daemon once per repo, not once per hook call, so it is not the hook's cost.
        # Env config outranks system/global/local config, and this reaches the hook's process only. APPENDED after any
        # GIT_CONFIG_* the caller passed through -Env, never over it (capstone R7, owner ruling): the last entry wins, so
        # fsmonitor stays off, and the caller's own entries still reach the hook. Builtins only - no process.
        $boot = "while [ ! -e $(& $sq $go) ]; do :; done; _gcn=`${GIT_CONFIG_COUNT:-0}; export `"GIT_CONFIG_KEY_`$_gcn=core.fsmonitor`" `"GIT_CONFIG_VALUE_`$_gcn=false`" GIT_CONFIG_COUNT=`$((_gcn + 1)); export MSYSTEM=MINGW64 PATH=/mingw64/bin:/usr/bin:`$PATH; exec `"`$BASH`" $(& $sq ($ScriptPath -replace '\\', '/')) $argStr < $(& $sq ($payloadFile -replace '\\', '/'))"
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
            # And one that let go of the pipes keeps spawning after bash exits: reading the count now would miss
            # everything it starts later (agy test-audit MG2, MEASURED 2026-10-06: 2 counted for ~8 started). Wait
            # for the job to drain, bounded, so a hook that leaves work running fails this run instead.
            $drain = [Diagnostics.Stopwatch]::StartNew()
            while ([ClavityJobCount]::Active($job) -gt 0) {
                if ($drain.ElapsedMilliseconds -gt 30000) { throw "Invoke-JobCountedBash: '$ScriptPath' exited but its background work was still running 30 s later" }
                Start-Sleep -Milliseconds 50
            }
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

function Invoke-BashHookEmptyPath {
    # Runs a hook under a genuinely EMPTY PATH, which Invoke-BashHook cannot reach: Get-GitBashOrThrow returns Git\bin\bash.exe,
    # a wrapper that puts /mingw64/bin:/usr/bin back on PATH (measured 2026-09-30), so a hook that calls `cat` or `grep` finds
    # them there and stays silent for the wrong reason. Claude Code runs Git\usr\bin\bash.exe, which does not, so this launches
    # THAT binary with PATH='' (MSYS hands the child PATH as `=`, a relative directory that does not exist: no command resolves).
    # Used by the ROADMAP section 59 rows: every spawn before the first jq check is a stderr leak on such a machine.
    param([Parameter(Mandatory)][string]$HookPath, [string]$Payload = '{}', [Parameter(Mandatory)][string]$HomeDir, [hashtable]$Env = @{})
    if (-not (Test-Path -LiteralPath $HookPath)) { throw "Invoke-BashHookEmptyPath: the hook '$HookPath' does not exist" }
    $usrBash = Join-Path (Split-Path -Parent (Split-Path -Parent (Get-GitBashOrThrow))) 'usr\bin\bash.exe'
    if (-not (Test-Path -LiteralPath $usrBash)) { throw "Invoke-BashHookEmptyPath: needs the non-wrapper Git Bash at $usrBash" }
    $psi = [Diagnostics.ProcessStartInfo]::new($usrBash)
    $psi.ArgumentList.Add(($HookPath -replace '\\', '/'))
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.Environment['PATH'] = ''
    $psi.Environment['HOME'] = $HomeDir
    foreach ($k in $Env.Keys) { $psi.Environment[$k] = $Env[$k] }
    $p = [Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($Payload); $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd(); $err = $p.StandardError.ReadToEnd(); $p.WaitForExit()
    [pscustomobject]@{ StdOut = $out.Trim(); StdErr = $err.Trim(); ExitCode = $p.ExitCode }
}

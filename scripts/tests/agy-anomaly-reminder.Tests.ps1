Describe 'agy-anomaly-reminder.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh'
        $bashDir = Split-Path -Parent (Get-GitBashOrThrow)
        $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')

        # A workspace whose .clavity/local-anomalies.md carries $Lines entry bullets.
        function New-Workspace { param([string[]]$Lines)
            $d = Join-Path ([IO.Path]::GetTempPath()) ("anom-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $d '.clavity') -Force | Out-Null
            if ($null -ne $Lines) {
                $body = @('# Untriaged anomalies (gitignored, local)', '') + $Lines
                Set-Content (Join-Path $d '.clavity/local-anomalies.md') ($body -join "`n") -Encoding ascii
            }
            return $d
        }
        function New-CleanHome {
            $h = Join-Path ([IO.Path]::GetTempPath()) ("anom-home-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $h '.claude') -Force | Out-Null
            return $h
        }
        function Payload { param([string]$Cwd) @{ cwd = ($Cwd -replace '\\','/'); source = 'startup' } | ConvertTo-Json -Compress }

        # EVERY path of this hook must be stderr-silent, so the invariant lives in the WRAPPER rather than
        # in each test. AGY-CAPSTONE round 2, Coverage Adversary: round 1 added stderr assertions only to
        # the "is SILENT" tests, leaving every REPORTING test vacuous against noise - MEASURED, `echo noise
        # >&2` in the unreadable-file branch kept the suite 22/22 GREEN. Ten hand-added assertions would
        # have closed that instance and left the NEXT test free to forget again; a wrapper cannot be
        # forgotten, because there is no other way to call the hook.
        function Invoke-Hook { param([string]$Payload, [hashtable]$Env)
            # Calls the REAL helper. A blind rewrite of the call sites once pointed this line at
            # Invoke-Hook itself, which is infinite recursion, so it is spelled out deliberately.
            $r = Invoke-BashHook -HookPath $script:Hook -Payload $Payload -Env $Env
            $r.StdErr | Should -BeNullOrEmpty -Because 'this hook must never write stderr on ANY path - a SessionStart hook that does is rendered to the owner as a failing hook'
            return $r
        }

        # As Payload, but WITHOUT the forward-slashing. That convention is repo-wide and is exactly why
        # the Windows repo-root walk bug survived - a POSIX-shaped path cannot exercise it.
        function RawPayload { param([string]$Cwd)
            '{"cwd":"' + ($Cwd -replace '\\', '\\') + '","source":"startup","hook_event_name":"SessionStart"}'
        }
        # A real git repo with an anomalies file at its ROOT and an empty subdirectory to run from.
        function New-RepoWithAnomaly {
            $r = New-TempRepo
            New-Item -ItemType Directory -Path (Join-Path $r '.clavity') -Force | Out-Null
            Set-Content (Join-Path $r '.clavity/local-anomalies.md') `
                "# Untriaged anomalies (gitignored, local)`n`n- [defect] x * a.cs:1 * 2026-07-20 * task=z" -Encoding ascii
            New-Item -ItemType Directory -Path (Join-Path $r 'src') -Force | Out-Null
            return $r
        }
    }

    # --- THE POSITIVE CONTROL FOR EVERY STDERR ASSERTION IN THIS FILE ----------------------------
    It 'the harness CAN capture stderr (positive control for every stderr assertion here)' {
        # AGY-CAPSTONE round 2, Dependency Cynic. Every `StdErr | Should -BeNullOrEmpty` in this file is a
        # NEGATIVE assertion against an external dependency, and a negative assertion proves nothing until
        # something shows the dependency can return non-empty at all.
        # MEASURED: replacing Invoke-BashHook's stderr capture with the empty string left the whole suite
        # 22/22 GREEN - every stderr guard here was hollow, including the ones added one round earlier to
        # fix a vacuity finding. This row is the only thing between that and a silent regression.
        $s = Join-Path ([IO.Path]::GetTempPath()) ("stderrctl-" + [Guid]::NewGuid().ToString('N') + ".sh")
        try {
            # LF ONLY, and written explicitly rather than with Set-Content. AGY-CAPSTONE round 3, Resource
            # Vampire: Set-Content joins array elements with the OS separator, so on Windows this wrote a
            # CRLF script - MEASURED, two 0x0d bytes in the file. Git Bash HERE tolerated it (exit 0), which
            # is why the suite was green, but that tolerance is a property of THIS machine's bash, not of
            # the test: where it is absent, `exit 0\r` is a numeric-argument error and this control reddens
            # for a reason that has nothing to do with stderr capture. A control that can fail for the
            # wrong reason is worse than none, because it teaches people to ignore it.
            [IO.File]::WriteAllText($s, "printf 'control-noise\n' >&2`nexit 0`n")
            $r = Invoke-BashHook -HookPath $s -Payload '{"cwd":".","source":"startup"}' -Env @{}
            $r.StdErr   | Should -Match 'control-noise' -Because 'if THIS fails, every stderr assertion in this file is vacuous and proves nothing'
            $r.ExitCode | Should -Be 0
        } finally { Remove-Item $s -Force -ErrorAction SilentlyContinue }
    }

    # --- .no-agy at the REPO ROOT, session cwd in a SUBDIRECTORY ---------------------------------
    # Each silence case is paired with a positive control, and the CONTROL is the load-bearing half:
    # measured on this hook's own model-addressed sibling, a broken walk produced silence that was
    # indistinguishable from a working kill-switch, and only the control went red.
    It 'is SILENT when .no-agy is at the repo root and cwd is a subdirectory' {
        $r = New-RepoWithAnomaly; $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $r '.no-agy') -Force | Out-Null
            $x = Invoke-Hook -Payload (RawPayload (Join-Path $r 'src')) -Env @{ HOME = $h }
            $x.StdOut   | Should -BeNullOrEmpty -Because 'an opt-out at the repo root must suppress this hook from a subdirectory'
            $x.ExitCode | Should -Be 0
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'DOES report from that same subdirectory when .no-agy is absent (positive control)' {
        # Also pins that the walk finds the anomalies file at the ROOT while running from a subdirectory,
        # which is the behaviour the header comment promises and the whole reason the root is resolved.
        $r = New-RepoWithAnomaly; $h = New-CleanHome
        try {
            $x = Invoke-Hook -Payload (RawPayload (Join-Path $r 'src')) -Env @{ HOME = $h }
            $x.StdOut   | Should -Match 'AGY-ANOMALIES' -Because 'without the opt-out it must still report - otherwise the silence test proves nothing'
            $x.ExitCode | Should -Be 0 -Because 'SessionStart routes the owner notice via the JSON envelope on stdout at exit 0'
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'honours a root .no-agy from a subdirectory on the DEGRADED (no jq) path too' {
        # This path used to test "./.no-agy" - the PROCESS cwd, not the session workspace - so it could
        # not honour any workspace opt-out at all when the two differ. Nothing covered it.
        $r = New-RepoWithAnomaly; $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $r '.no-agy') -Force | Out-Null
            $x = Invoke-Hook -Payload (RawPayload (Join-Path $r 'src')) -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $x.StdOut   | Should -BeNullOrEmpty -Because 'the degraded path must honour the same root opt-out as the jq path'
            $x.ExitCode | Should -Be 0
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'DOES warn from that subdirectory without .no-agy when jq is absent (degraded positive control)' {
        $r = New-RepoWithAnomaly; $h = New-CleanHome
        try {
            $x = Invoke-Hook -Payload (RawPayload (Join-Path $r 'src')) -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $x.StdOut | Should -Match 'guard inactive: missing jq' -Because 'without the opt-out the degraded path must still announce itself'
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # --- .no-agy in the SUBDIRECTORY the session runs from, repo root UNMARKED --------------------
    # AGY-CAPSTONE round 4, Coverage Adversary. The kill-switch is
    #   [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]
    # at BOTH the jq path and the degraded path, but every existing test marked the ROOT or $HOME, so the
    # SECOND half was never exercised. MEASURED: deleting `|| [ -f "$cwd_path/.no-agy" ]` from both sites
    # left the suite 23/23 GREEN - half of the documented opt-out was unprotected.
    #
    # BOTH paths get a row deliberately. Covering only the jq one would leave a mutant that removes the
    # degraded site alone still green, which is the same incomplete-fold shape rounds 2 and 3 both caught.
    # The positive controls already above ('DOES report from that same subdirectory...') are what make
    # these two meaningful: they prove the identical fixture DOES report when the opt-out is absent.
    It 'is SILENT when .no-agy is in the SUBDIRECTORY the session runs from and the root is unmarked' {
        $r = New-RepoWithAnomaly; $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $r 'src/.no-agy') -Force | Out-Null
            (Test-Path (Join-Path $r '.no-agy')) | Should -BeFalse -Because 'the ROOT must stay unmarked, or this passes through the OTHER half of the kill-switch and proves nothing'
            $x = Invoke-Hook -Payload (RawPayload (Join-Path $r 'src')) -Env @{ HOME = $h }
            $x.StdOut   | Should -BeNullOrEmpty
            $x.ExitCode | Should -Be 0
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'honours a SUBDIRECTORY .no-agy on the DEGRADED (no jq) path too, root unmarked' {
        $r = New-RepoWithAnomaly; $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $r 'src/.no-agy') -Force | Out-Null
            (Test-Path (Join-Path $r '.no-agy')) | Should -BeFalse -Because 'the ROOT must stay unmarked, or this passes through the OTHER half of the kill-switch and proves nothing'
            $x = Invoke-Hook -Payload (RawPayload (Join-Path $r 'src')) -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $x.StdOut   | Should -BeNullOrEmpty
            $x.ExitCode | Should -Be 0
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT (exit 0) when the anomalies file does not exist' {
        $w = New-Workspace $null; $h = New-CleanHome
        try {
            $r = Invoke-Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT when the file exists but holds no entries' {
        $w = New-Workspace @(); $h = New-CleanHome
        try {
            $r = Invoke-Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'REPORTS the count and demands triage when entries exist' {
        $w = New-Workspace @(
            '- [defect] ParseLatest never checks the pid pair matches * LsDiscovery.cs:94 * 2026-07-30 * task=capstone',
            '- [tool] just test-scripts exceeds the 600s tool cap * n/a * 2026-08-01 * task=phase-b'
        )
        $h = New-CleanHome
        try {
            $r = Invoke-Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -Match '2 untriaged'
            $r.StdOut   | Should -Match 'promote'
            $r.StdOut   | Should -Match 'delete'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'names the OLDEST entry date, not the newest' {
        $w = New-Workspace @(
            '- [tool] newer thing * n/a * 2026-08-01 * task=x',
            '- [defect] older thing * a.cs:1 * 2026-07-14 * task=y'
        )
        $h = New-CleanHome
        try {
            $r = Invoke-Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.StdOut | Should -Match '2026-07-14'
            $r.StdOut | Should -Not -Match '2026-08-01'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'counts ONLY entry bullets, not prose or headings in the file' {
        $w = New-Workspace @(
            'Some explanatory prose that is not an entry.',
            '## A heading',
            '- not an entry because it has no bracketed type',
            '- [defect] the only real entry * a.cs:1 * 2026-07-20 * task=z'
        )
        $h = New-CleanHome
        try {
            $r = Invoke-Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -Match '1 untriaged'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a workspace .no-agy kill-switch' {
        $w = New-Workspace @('- [defect] x * a.cs:1 * 2026-07-20 * task=z'); $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $w '.no-agy') -Force | Out-Null
            $r = Invoke-Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a global $HOME/.claude/.no-agy kill-switch' {
        $w = New-Workspace @('- [defect] x * a.cs:1 * 2026-07-20 * task=z'); $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null
            $r = Invoke-Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'warns ONCE (exit 0, one JSON line) when jq is absent rather than failing silently' {
        $h = New-CleanHome
        try {
            $r = Invoke-Hook -Payload '{"cwd":".","source":"startup"}' -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $r.ExitCode | Should -Be 0
            ($r.StdOut -split "`n").Count | Should -Be 1

            # PARSE IT, do not -Match it. AGY-CAPSTONE 2026-09-04, Protocol Pedant: this is the ONE site
            # whose envelope is hand-built with printf instead of `jq -nc`, so it is the one site where a
            # structural break is possible at all - and a substring match cannot see one. MEASURED: dropping
            # a single closing brace from that printf produced output `jq` rejects as invalid, and this
            # suite stayed 22/22 GREEN. The wire contract was entirely unpinned at exactly the place it was
            # least automatic. ConvertFrom-Json throws on malformed input, which is what makes this bite.
            $j = $r.StdOut | ConvertFrom-Json
            $j.systemMessage                        | Should -Match 'missing jq'
            $j.hookSpecificOutput.hookEventName     | Should -Be 'SessionStart'
            $j.hookSpecificOutput.additionalContext | Should -Match 'missing jq'
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'finds the file at the repo ROOT when cwd is a SUBDIRECTORY' {
        # A capturing session cd'd into a subdirectory writes to the repo root. If this hook looked only at
        # the payload cwd it would report zero while a real anomaly sat captured and invisible.
        $repo = New-TempRepo; $h = New-CleanHome
        try {
            New-Item -ItemType Directory -Path (Join-Path $repo '.clavity') -Force | Out-Null
            Set-Content (Join-Path $repo '.clavity/local-anomalies.md') "# Untriaged anomalies`n`n- [defect] y * a.cs:1 * 2026-07-20 * task=z" -Encoding ascii
            $sub = Join-Path $repo 'scripts/deep'
            New-Item -ItemType Directory -Path $sub -Force | Out-Null
            $r = Invoke-Hook -Payload (Payload $sub) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -Match '1 untriaged'
        } finally { Remove-Item $repo,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'finds the file under the payload cwd when it is NOT at the git root' {
        # The case the second candidate exists for, and the only arrangement that can observe it: the repo
        # ROOT has no anomalies file, but the payload cwd (a subdirectory) does. Reachable when a capturing
        # session without git on PATH used its $PWD fallback while cd'd into a subdirectory. A fixture
        # where root and cwd coincide would pass with or without the fallback and prove nothing.
        $repo = New-TempRepo; $h = New-CleanHome
        try {
            $sub = Join-Path $repo 'scripts/deep'
            New-Item -ItemType Directory -Path (Join-Path $sub '.clavity') -Force | Out-Null
            Set-Content (Join-Path $sub '.clavity/local-anomalies.md') "# Untriaged anomalies`n`n- [defect] y * a.cs:1 * 2026-07-20 * task=z" -Encoding ascii
            Test-Path (Join-Path $repo '.clavity/local-anomalies.md') | Should -BeFalse
            $r = Invoke-Hook -Payload (Payload $sub) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -Match '1 untriaged'
        } finally { Remove-Item $repo,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'counts an entry whose type is Title-Case or multi-word' {
        # A sloppy type is still a real anomaly. A stricter [a-z] pattern would count these as zero and
        # silently discard exactly what the hook exists to surface.
        $w = New-Workspace @(
            '- [Defect] title-cased type * a.cs:1 * 2026-07-20 * task=z',
            '- [tool misbehavior] multi-word type * n/a * 2026-07-21 * task=z'
        )
        $h = New-CleanHome
        try {
            $r = Invoke-Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -Match '2 untriaged'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reads the date from its FIELD, ignoring a date written in the prose' {
        # Scanning the whole line for an ISO date would pick the prose date and report an age that is a lie.
        $w = New-Workspace @('- [defect] API truncates messages from 2024-01-01 format * a.cs:1 * 2026-08-01 * task=z')
        $h = New-CleanHome
        try {
            $r = Invoke-Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.StdOut | Should -Match '2026-08-01'
            $r.StdOut | Should -Not -Match '2024-01-01'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'still reads the date when the task field itself contains a separator' {
        # Counting fields from the right broke here: a ' * ' inside task= shifts NF and $(NF-1) lands on a
        # fragment of the task, silently dropping that entry's date.
        #
        # ORDER IS THE ASSERTION. The entry with the separator in its task must carry the OLDER date. With
        # it newer, the other entry supplies the same "oldest" either way and the test passes against the
        # broken form -- which is exactly how the first version of this test was vacuous. The second entry
        # also keeps a ' * ' in its FACT, proving that case stayed safe.
        $w = New-Workspace @(
            '- [defect] x * a.cs:1 * 2026-07-11 * task=investigating * timeout',
            '- [tool] a * b thing * n/a * 2026-08-01 * task=z'
        )
        $h = New-CleanHome
        try {
            $r = Invoke-Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -Match '2 untriaged'
            $r.StdOut   | Should -Match '2026-07-11'
            $r.StdOut   | Should -Not -Match '2026-08-01'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT when jq is absent AND .no-agy is set' {
        # Without this, a machine that simply has no jq gets an unsuppressable boot warning forever and
        # .no-agy -- the documented off switch -- does not switch it off. agy-liveness-check.sh:26-36
        # already handles this; the guard mirrors it.
        $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null
            $r = Invoke-Hook -Payload '{"cwd":".","source":"startup"}' -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'REPORTS an unreadable anomalies file rather than counting zero' {
        # A present-but-unreadable file must not read as "no anomalies" -- that is the same silent zero
        # the jq guard exists to prevent. Skipped on hosts where chmod cannot actually deny read.
        $w = New-Workspace @('- [defect] x * a.cs:1 * 2026-07-20 * task=z'); $h = New-CleanHome
        try {
            $f = Join-Path $w '.clavity/local-anomalies.md'
            & icacls $f /deny "$($env:USERNAME):(R)" 2>&1 | Out-Null
            # Probe readability from the BASH process the hook actually runs in, NOT from PowerShell.
            # These diverge, and the old guard probed the wrong one: on the GitHub windows-latest runner
            # the deny bound pwsh (so [IO.File]::ReadAllText threw and the test did NOT skip) while the
            # hook read the file fine and reported "1 untriaged" - a red test on a host that simply does
            # not enforce the deny against the subject of the assertion. Probe the subject.
            $bashExe = Get-GitBashOrThrow
            $posix = ($f -replace '\\','/')
            & $bashExe -lc "cat '$posix' > /dev/null 2>&1"
            if ($LASTEXITCODE -eq 0) {
                Set-ItResult -Skipped -Because 'this host does not enforce the read deny against the hook process'
                return
            }
            $r = Invoke-Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0

            # PARSE THE ENVELOPE HERE TOO. AGY-CAPSTONE round 4, Coverage Adversary: this branch was the
            # last emission site pinned by a substring alone. MEASURED: dropping `hookSpecificOutput` from
            # its `jq -nc` payload left the suite 23/23 GREEN - the MODEL's half of the wire contract was
            # unprotected on the error path while both other paths enforced it.
            #
            # This is NOT the finding round 3 refuted. That one was about MALFORMED json, which `jq -nc`
            # cannot emit; this is VALID json missing a key, which it emits happily. The distinction is the
            # whole point: `jq` guarantees syntax, never shape.
            $j = $r.StdOut | ConvertFrom-Json
            $j.systemMessage                        | Should -Match 'cannot be read'
            $j.hookSpecificOutput.hookEventName     | Should -Be 'SessionStart'
            $j.hookSpecificOutput.additionalContext | Should -Match 'cannot be read'
        } finally {
            & icacls (Join-Path $w '.clavity/local-anomalies.md') /remove:d "$($env:USERNAME)" 2>&1 | Out-Null
            Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # --- THE REGRESSION GUARDS FOR THE 2026-09-04 EMISSION FIX -----------------------------------
    It 'emits the notice on STDOUT at exit 0, never on stderr at a non-zero exit' {
        # THE DEFECT THIS PINS, observed by the owner: the hook used stderr + exit 2, and Claude Code
        # renders ANY non-zero SessionStart hook as "SessionStart:startup hook error" in red. A routine
        # triage reminder was therefore displayed as a FAILING HOOK at every single startup, which is how
        # a notice trains people to skip past it.
        #
        # BOTH assertions here are load-bearing, and the stderr half of the invariant now lives in the
        # Invoke-Hook wrapper rather than in this body: stdout at a non-zero exit still renders as an
        # error, and without the StdOut match this test would pass on a hook that says NOTHING at all.
        # (This comment said "all three" until AGY-CAPSTONE round 4 - round 3 removed the local stderr
        # assertion as dead code once the wrapper covered it, and left the comment describing it.)
        $d = New-Workspace @('- [defect] x * a.cs:1 * 2026-07-20 * task=z'); $h = New-CleanHome
        try {
            $r = Invoke-Hook -Payload (Payload $d) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0 -Because 'a non-zero SessionStart hook is rendered to the owner as a hook ERROR'
            $r.StdOut   | Should -Match 'AGY-ANOMALIES' -Because 'the notice must still be emitted, or the two assertions above are vacuous'
        } finally { Remove-Item $d,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'emits an envelope carrying BOTH the owner surface and the model surface' {
        # systemMessage reaches the OWNER, who is the one who triages; hookSpecificOutput.additionalContext
        # reaches the MODEL. The old stderr form happened to deliver both, so a fix that kept only one
        # would silently drop an audience and no other test here would notice.
        # MEASURED 2026-09-04 with `claude -p` asking the session whether its SessionStart context
        # mentioned AGY-ANOMALIES: YES under the old form, YES under this one.
        #
        # hookEventName is pinned to SessionStart because the hook is registered under FOUR matchers
        # (startup, resume, clear, compact) that are `source` values of ONE event - naming any of those
        # as the event would be rejected as a schema violation and the owner would see a validation dump.
        $d = New-Workspace @('- [defect] x * a.cs:1 * 2026-07-20 * task=z'); $h = New-CleanHome
        try {
            $r = Invoke-Hook -Payload (Payload $d) -Env @{ HOME = $h }
            $j = $r.StdOut | ConvertFrom-Json      # throws, and so fails, if the envelope is malformed
            $j.systemMessage                        | Should -Match 'AGY-ANOMALIES'
            $j.hookSpecificOutput.hookEventName     | Should -Be 'SessionStart'
            $j.hookSpecificOutput.additionalContext | Should -Match 'AGY-ANOMALIES'
        } finally { Remove-Item $d,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'ships as pure ASCII' {
        ($([IO.File]::ReadAllBytes($script:Hook)) | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}

<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

Describe 'BashHookHelpers (harness validation)' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        # A throwaway probe hook that echoes the env it sees + writes to stderr and exits 2.
        $script:probeDir = New-TestTempPath "sp-d-probe"
        New-Item -ItemType Directory -Path $script:probeDir -Force | Out-Null
        $script:probe = Join-Path $script:probeDir 'probe.sh'
        @(
            '#!/usr/bin/env bash',
            'echo "CCD=$CLAUDE_CONFIG_DIR"',
            'if [ -f "$CLAUDE_CONFIG_DIR/marker" ]; then echo "CCD_MARKER_FOUND"; else echo "CCD_MARKER_MISSING"; fi',
            'if [ -f "$HOME/.claude/marker" ]; then echo "HOME_MARKER_FOUND"; else echo "HOME_MARKER_MISSING"; fi',
            'printf ''%s\n'' "on-stderr" >&2',
            'exit 2'
        ) -join "`n" | Set-Content -LiteralPath $script:probe -Encoding ascii -NoNewline
    }
    AfterAll { Remove-Item -LiteralPath $script:probeDir -Recurse -Force -ErrorAction SilentlyContinue }

    It 'pins a non-WSL Git Bash' {
        (Get-GitBashOrThrow) | Should -Not -Match '\\System32\\bash\.exe$'
    }
    It 'captures stderr and exit code 2 separately from stdout' {
        $r = Invoke-BashHook -HookPath $script:probe
        $r.ExitCode | Should -Be 2
        $r.StdErr   | Should -Match 'on-stderr'
    }
    It 'resolves an absolute CLAUDE_CONFIG_DIR to a real file inside the hook' {
        # NOTE: env vars (unlike CLI args) are NOT MSYS auto-POSIX-converted -- CLAUDE_CONFIG_DIR arrives
        # in the hook in its raw Windows form (C:\...). What the SP-D hooks actually depend on is that the
        # env-passed config dir RESOLVES on the filesystem (`[ -f "$CLAUDE_CONFIG_DIR/settings.json" ]` +
        # jq reading it), which Cygwin/Git-Bash handles transparently for Windows-form paths. Assert that
        # real guarantee (filesystem resolution), NOT a path-string format.
        $cfg2 = New-TestTempPath "sp-d-cfg"
        New-Item -ItemType File -Path (Join-Path $cfg2 'marker') -Force | Out-Null
        try {
            $r = Invoke-BashHook -HookPath $script:probe -Env @{ CLAUDE_CONFIG_DIR = $cfg2 }
            $r.StdOut | Should -Match 'CCD_MARKER_FOUND'
        } finally { Remove-Item -LiteralPath $cfg2 -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'isolates HOME to an absolute fixture dir (MSYS passthrough)' {
        $home2 = New-TestTempPath "sp-d-home"
        New-Item -ItemType Directory -Path (Join-Path $home2 '.claude') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $home2 '.claude/marker') -Force | Out-Null
        try {
            $r = Invoke-BashHook -HookPath $script:probe -Env @{ HOME = $home2 }
            $r.StdOut | Should -Match 'HOME_MARKER_FOUND'
        } finally { Remove-Item -LiteralPath $home2 -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'RESTORES an -Env override by REMOVING a variable that was absent, not by emptying it' {
        # THE LEAK THIS PINS, measured 2026-08-19 while debugging why agy-shield-lib.Tests.ps1 passed
        # 39/39 in isolation and failed 5 rows in the full sweep and in CI.
        #
        # The helper saves the prior value, sets the override, and restores in `finally`. When the
        # variable was ABSENT the saved value is $null - and in PowerShell
        # `[Environment]::SetEnvironmentVariable($k, $null)` does NOT delete the key, it leaves it
        # PRESENT WITH AN EMPTY VALUE. Measured, all four forms:
        #     SetEnvironmentVariable(n, $null)              -> present=True  value=[]
        #     SetEnvironmentVariable(n, '')                 -> present=True  value=[]
        #     SetEnvironmentVariable(n, [NullString]::Value)-> present=False
        #     Remove-Item Env:n                             -> present=False
        #
        # An empty TMPDIR is NOT harmless on this platform: MSYS/Git Bash converts it to the bogus
        # relative path `<cwd>/=` rather than passing it through empty, so `${TMPDIR:-/tmp}` never
        # defaults. agy-anomaly-capture-reminder.Tests.ps1 runs at position 5 and overrides TMPDIR, so
        # from there on EVERY bash child in the sweep inherited a poisoned TMPDIR.
        #
        # ASSERT ABSENCE, NOT EMPTINESS. `$env:X -eq ''` is true for both the broken and the fixed
        # state, so a value-based assertion here would pass under the bug and prove nothing.
        $name = 'SPD_LEAK_PROBE'
        Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        [Environment]::GetEnvironmentVariables().Contains($name) |
            Should -BeFalse -Because 'the precondition is that this variable is ABSENT before the call'

        $null = Invoke-BashHook -HookPath $script:probe -Payload '{}' -Env @{ $name = 'temporary-value' }

        [Environment]::GetEnvironmentVariables().Contains($name) |
            Should -BeFalse -Because 'a variable that was ABSENT before the call must be ABSENT after it - an empty-valued key is a leak that poisons every later child process'
    }

    It 'does NOT delete a present variable when the caller spells it in a different case' {
        # THE REGRESSION THIS PINS. The first version of the absence check used
        # `[Environment]::GetEnvironmentVariables().Contains($k)`, a case-SENSITIVE Hashtable lookup,
        # while the setter is case-INSENSITIVE. A caller writing `Path` against a block whose real key
        # is `PATH` was therefore classified ABSENT and DELETED on restore. It shipped: locally the
        # casings aligned and the full 989-test sweep passed; CI deleted PATH and every hook lost jq.
        #
        # The probe uses a deliberately mixed-case spelling of a variable seeded in UPPER case.
        $name = 'SPD_CASE_PROBE'
        [Environment]::SetEnvironmentVariable($name, 'original-value')
        try {
            $null = Invoke-BashHook -HookPath $script:probe -Payload '{}' -Env @{ 'spd_case_probe' = 'override' }

            # Assert the VALUE survived, not merely that some key exists - a deleted-then-recreated
            # empty key would satisfy a presence-only check.
            [Environment]::GetEnvironmentVariable($name) |
                Should -BeExactly 'original-value' -Because 'a PRESENT variable must be restored to its value whatever case the caller used to name it'
        }
        finally {
            [Environment]::SetEnvironmentVariable($name, [NullString]::Value)
        }
    }

    It 'forwards positional arguments to the hook' {
        $probe = Join-Path $TestDrive 'echo-args.sh'
        Set-Content -LiteralPath $probe -Value "#!/usr/bin/env bash`ncat >/dev/null`nprintf '%s' `"`$1`"" -NoNewline
        $r = Invoke-BashHook -HookPath $probe -Payload '{}' -Arguments @('UserPromptSubmit')
        $r.Stdout | Should -BeExactly 'UserPromptSubmit'
    }

    It 'passes no argument when -Arguments is omitted' {
        # CONTROL: guards the default path every EXISTING caller uses. If -Arguments defaulted to something
        # non-empty, every hook in the repo would start receiving a spurious $1.
        $probe = Join-Path $TestDrive 'echo-args.sh'
        Set-Content -LiteralPath $probe -Value "#!/usr/bin/env bash`ncat >/dev/null`nprintf '[%s]' `"`$1`"" -NoNewline
        $r = Invoke-BashHook -HookPath $probe -Payload '{}'
        $r.Stdout | Should -BeExactly '[]'
    }

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
                if ((-not $IsWindows) -and ((& id -u) -ne '0')) { $enforced | Should -BeTrue -Because 'a non-root POSIX user must be bound by chmod 000 / 444 - if this fails the helper is broken and every NotAsRoot row would silently skip' }
                if (-not $enforced) { Set-ItResult -Skipped -Because 'APPROVED:NotAsRoot: this user (root?) is not bound by the deny'; return }
                & (Get-GitBashOrThrow) -c 'cat "$1" >/dev/null 2>&1 && echo READ || echo blocked' _ ($f -replace '\\','/') | Should -Be 'blocked'
            } finally { Restore-TestPathReadable -Path $f }
            & (Get-GitBashOrThrow) -c 'cat "$1" >/dev/null 2>&1 && echo READ || echo blocked' _ ($f -replace '\\','/') | Should -Be 'READ'
        }
        It 'Set-TestFileReadOnly makes an append fail, and Clear-TestFileReadOnly undoes it' {
            $f = Join-Path $script:xpDir 'ro.txt'; Set-Content -LiteralPath $f -Value 'x'
            $enforced = Set-TestFileReadOnly -Path $f
            try {
                if ((-not $IsWindows) -and ((& id -u) -ne '0')) { $enforced | Should -BeTrue -Because 'a non-root POSIX user must be bound by chmod 000 / 444 - if this fails the helper is broken and every NotAsRoot row would silently skip' }
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

    # Win32 Job Objects; the Linux budget is not this quantity (spec non-goal).
    Context 'Measure-BashHookProcesses (Job Object process counter)' -Skip:(-not $IsWindows) -Tag 'WindowsOnly' {
        BeforeAll {
            $script:countDir = New-TestTempPath "sp-d-count"
            New-Item -ItemType Directory -Path $script:countDir -Force | Out-Null
            $script:builtinsOnly = Join-Path $script:countDir 'builtins.sh'
            $script:oneExternal  = Join-Path $script:countDir 'external.sh'
            $script:echoEnv      = Join-Path $script:countDir 'echoenv.sh'
            Set-Content -LiteralPath $script:builtinsOnly -Value "x=1; [ -n `"`$x`" ] && y=2" -Encoding ascii
            Set-Content -LiteralPath $script:oneExternal  -Value '/usr/bin/true' -Encoding ascii
            Set-Content -LiteralPath $script:echoEnv      -Value 'printf %s "$SPD_COUNT_PROBE"' -Encoding ascii
            $script:whichGit     = Join-Path $script:countDir 'whichgit.sh'
            Set-Content -LiteralPath $script:whichGit     -Value 'command -v git' -Encoding ascii
            # Two externals started by a DETACHED background subshell after a sleep, so they start after bash exits.
            $script:lateTwo      = Join-Path $script:countDir 'late.sh'
            Set-Content -LiteralPath $script:lateTwo      -Value '( /usr/bin/sleep 1; /usr/bin/true; /usr/bin/true ) >/dev/null 2>&1 </dev/null &' -Encoding ascii
            $script:nowTwo       = Join-Path $script:countDir 'now.sh'
            Set-Content -LiteralPath $script:nowTwo       -Value '( /usr/bin/sleep 1; /usr/bin/true; /usr/bin/true ) >/dev/null 2>&1 </dev/null' -Encoding ascii
        }
        AfterAll { Remove-Item -LiteralPath $script:countDir -Recurse -Force -ErrorAction SilentlyContinue }

        It 'counts NOTHING beyond bash boot for a builtins-only script' {
            (Measure-BashHookProcesses -HookPath $script:builtinsOnly).Spawned | Should -Be 0
        }
        It 'counts exactly the two processes one external command costs (the failing control: it must SEE a child)' {
            # A counter that cannot return a non-zero answer certifies every hook. This row is what proves it can.
            (Measure-BashHookProcesses -HookPath $script:oneExternal).Spawned | Should -Be 2
        }
        It 'counts what a detached background subshell starts AFTER bash exits, the same as in the foreground' {
            # agy test-audit MG2: the count used to be read the moment bash exited, so work a hook pushed into the
            # background was invisible (MEASURED: 2 counted for ~8 started). The foreground run is the oracle: the
            # same subshell, the same three externals, waited for.
            $now = (Measure-BashHookProcesses -HookPath $script:nowTwo).Spawned
            $now | Should -BeGreaterOrEqual 6 -Because 'sleep plus two trues cost at least two processes each; a lower foreground count means the oracle itself is broken'
            (Measure-BashHookProcesses -HookPath $script:lateTwo).Spawned | Should -Be $now
        }
        It 'counts a git call the same with core.fsmonitor on, without waiting on git''s daemon' {
            # Capstone R6 HB1: with fsmonitor on, `git status` started git's daemon inside the job and the background
            # drain waited 30 s and threw (MEASURED). The fsmonitor=false run is the oracle: same repo, same hook.
            $repo = Join-Path $script:countDir ('fsm-' + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $repo | Out-Null
            git -C $repo init -q; git -C $repo config user.email t@t; git -C $repo config user.name t
            Set-Content -LiteralPath (Join-Path $repo 'a.txt') -Value 'a' -Encoding ascii
            git -C $repo add a.txt; git -C $repo commit -qm a
            $st = Join-Path $script:countDir 'gitstatus.sh'
            Set-Content -LiteralPath $st -Value 'git status --porcelain >/dev/null' -Encoding ascii
            git -C $repo config core.fsmonitor false
            $off = (Measure-BashHookProcesses -HookPath $st -WorkingDirectory $repo).Spawned
            $off | Should -BeGreaterThan 0 -Because 'the oracle must see the git call, or equality below proves nothing'
            git -C $repo config core.fsmonitor true
            $sw = [Diagnostics.Stopwatch]::StartNew()
            (Measure-BashHookProcesses -HookPath $st -WorkingDirectory $repo).Spawned | Should -Be $off
            $sw.Elapsed.TotalSeconds | Should -BeLessThan 25 -Because 'the run must not sit out the 30 s drain bound on a daemon'
        }
        It 'keeps a caller''s own GIT_CONFIG_* entries and still turns fsmonitor off' {
            # Capstone R7: the fsmonitor pin once OVERWROTE GIT_CONFIG_COUNT, silently dropping config a row passed via -Env.
            $cfg = Join-Path $script:countDir 'gitcfg.sh'
            Set-Content -LiteralPath $cfg -Value 'printf "%s|%s" "$(git config --get clavity.probe)" "$(git config --get core.fsmonitor)"' -Encoding ascii
            $r = Measure-BashHookProcesses -HookPath $cfg -Env @{ GIT_CONFIG_COUNT = '2'; GIT_CONFIG_KEY_0 = 'clavity.probe'; GIT_CONFIG_VALUE_0 = 'seen'; GIT_CONFIG_KEY_1 = 'core.fsmonitor'; GIT_CONFIG_VALUE_1 = 'true' }
            $r.StdOut | Should -BeExactly 'seen|false' -Because 'the caller''s entry must reach the hook, and the harness pin must still win over a caller''s fsmonitor=true'
        }
        It 'passes -Env to the hook WITHOUT changing this process environment' {
            $r = Measure-BashHookProcesses -HookPath $script:echoEnv -Env @{ SPD_COUNT_PROBE = 'seen' }
            $r.StdOut | Should -BeExactly 'seen'
            [Environment]::GetEnvironmentVariable('SPD_COUNT_PROBE') | Should -BeNullOrEmpty
        }
        It 'resolves the real git a hook gets under Git''s launcher, even from a bare PATH and no MSYSTEM' {
            # agy panel R3: without the launcher's PATH setup a hook found no git and degraded silently.
            $r = Measure-BashHookProcesses -HookPath $script:whichGit -Env @{ MSYSTEM = $null; PATH = 'C:\Windows\System32' }
            $r.StdOut | Should -BeIn @('/ucrt64/bin/git', '/mingw64/bin/git') -Because 'Git for Windows 2.56 moved git.exe to /ucrt64/bin; /cmd/git is the launcher and costs an extra process'
        }
    }
}

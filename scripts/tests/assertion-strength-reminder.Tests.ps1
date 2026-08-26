# scripts/tests/assertion-strength-reminder.Tests.ps1
BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Hook     = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh'
    $script:Mirror   = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks/assertion-strength-reminder.sh'

    # PIN GIT BASH. `Get-Command bash` is NON-DETERMINISTIC on this host - BashHookHelpers.ps1:5-8
    # documents that it depends on WHICH PARENT PROCESS launched pwsh. MEASURED 2026-08-17 at anomaly
    # triage: bare `bash` resolved to C:\WINDOWS\system32\bash.exe (the WSL stub), which cannot run a
    # Windows-path script - 17 of this suite's 37 rows FAILED with `/bin/bash: C:Usersuser...: No such
    # file or directory` (note the stripped backslashes) and `wsl: Failed to start the systemd user
    # session`. A false red that says nothing about the hook. Git Bash reports `/usr/bin/bash:`; that
    # prefix is how to tell the two apart in a failure message.
    # THIS SUITE WAS MISSED BY THE ORIGINAL SWEEP. The 2026-08-16 batch fixed agy-shield-lib and
    # agy-discipline-reaching and recorded the hazard as resolved; agy-mark was found still unpinned on
    # 2026-08-17, and this suite on the same day at triage. An anomaly marked resolved is still a claim -
    # sweep the FACT across the whole tree, not the files the batch happened to touch.
    . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
    $script:Bash = Get-GitBashOrThrow

    # A PostToolUse payload, matching the fixture shape used by agy-after-reminder.Tests.ps1.
    # OWNER RULING 2026-08-08: the live probe was declined and the per-day fallback accepted. The hook is
    # branch-agnostic (it falls back to the calendar day when session_id is absent), so the suite pins BOTH
    # payload shapes rather than assuming one - see the 'debounce key' Context.
    function New-Payload {
        param([string]$FilePath, [string]$Cwd, [string]$Sid = 'sess-abc123')
        $fp = $FilePath.Replace('\', '\\')
        $cw = $Cwd.Replace('\', '\\')
        if ([string]::IsNullOrEmpty($Sid)) {
            return "{`"hook_event_name`":`"PostToolUse`",`"cwd`":`"$cw`",`"tool_input`":{`"file_path`":`"$fp`"}}"
        }
        "{`"session_id`":`"$Sid`",`"hook_event_name`":`"PostToolUse`",`"cwd`":`"$cw`",`"tool_input`":{`"file_path`":`"$fp`"}}"
    }

    function Invoke-Hook {
        param([string]$Payload)
        $Payload | & $script:Bash $script:Hook 2>&1
    }

    # Degraded path: a PATH that still carries coreutils (the hook's own grep/find) but NOT jq.
    # MEASURED 2026-08-08: jq lives outside /usr/bin on this machine, so /usr/bin:/bin hides it while
    # keeping grep/find/mkdir. The 'jq is genuinely absent' test below is the CONTROL for this - without
    # it, a PATH that still reached jq would make every degraded test pass through the jq path instead.
    function Invoke-HookNoJq {
        param([string]$Payload)
        $Payload | & $script:Bash -c 'PATH=/usr/bin:/bin; export PATH; exec bash "$0"' $script:Hook 2>&1
    }

    # Each test gets a private marker location so a debounce marker never leaks between tests.
    #
    # BOTH env vars are required, and isolating only HOME is a REAL BUG that this suite already hit:
    # the hook tries "${TMPDIR:-/tmp}" FIRST and only falls back to "$HOME/.clavity-tmp"
    # (matching agy-anomaly-capture-reminder.sh:93). With HOME alone isolated, every test shared the one
    # global TMPDIR, so a marker written by an early test made a later test's FIRST touch look like a
    # second touch. MEASURED 2026-08-08: that leak produced 7 spurious failures - "fires again for a
    # DIFFERENT test file", "names all three structural smells", "keeps the two keys SEPARATE", the
    # degraded once-per-session test, and 3 degraded-agreement rows - all of which pass once TMPDIR is
    # isolated too. Do not drop the TMPDIR line.
    # TMPDIR IS RESTORED IN AfterAll, and that is not optional here. `BashHookHelpers.ps1` carries a
    # measured account of what an unrestored TMPDIR does in this suite runner: it leaks to every bash child
    # that runs afterwards, and `agy-shield-lib.Tests.ps1` passed 39/39 in isolation while failing 5 rows in
    # the full sweep and in CI because of it. That hardening lives in the HELPER, so setting TMPDIR
    # directly here walks straight around it - and this suite is position 6 of `test-scripts-slow` while
    # agy-shield-lib is position 15, in the same Invoke-Pester process.
    #
    # ABSENCE AND EMPTINESS ARE DIFFERENT STATES on restore: assigning $null leaves the key PRESENT and
    # EMPTY, and Git Bash turns an empty TMPDIR into the bogus relative path `<cwd>/=`. So a previously
    # ABSENT variable is removed, not blanked.
    $script:TmpDirWasPresent = Test-Path Env:TMPDIR
    $script:TmpDirOriginal   = if ($script:TmpDirWasPresent) { $env:TMPDIR } else { $null }

    function New-IsolatedHome {
        $h = Join-Path ([IO.Path]::GetTempPath()) ("asrt-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $h | Out-Null
        $env:TMPDIR = $h
        return $h
    }
}

Describe 'assertion-strength-reminder.sh' {
    AfterAll {
        if ($script:TmpDirWasPresent) { $env:TMPDIR = $script:TmpDirOriginal }
        else { Remove-Item Env:TMPDIR -ErrorAction SilentlyContinue }
    }

    # GUARD, added after the suite was measured passing with NO HOOK ON DISK. Every assertion below runs
    # the hook through `bash ... 2>&1`, so when the file is missing bash's own "No such file or directory"
    # error - which CONTAINS the hook's filename - lands in the captured output. A bare
    # Should -Match 'ASSERTION-STRENGTH' then matched the FILENAME in that error and passed, with nothing
    # implemented: 5 FIRES rows plus 3 more were green against an empty repo. Two fixes, both needed:
    # this existence guard, and anchoring every assertion on the BRACKETED tag '[ASSERTION-STRENGTH]',
    # which the filename cannot contain. Do not relax either back to a bare substring.
    It 'the hook file exists (guard: every assertion below is vacuous without it)' {
        (Test-Path $script:Hook) | Should -BeTrue -Because 'a missing hook must fail loudly, not pass silently through bash stderr'
    }

    It 'is registered in the justfile fast suite' {
        $jf = Get-Content -Raw (Join-Path $script:RepoRoot 'justfile')
        $jf.Contains("scripts/tests/assertion-strength-reminder.Tests.ps1") |
            Should -BeTrue -Because 'registration is an explicit list, not a glob'
    }

    # PINS THE CAPSTONE ROUND-1 FOLD. The hook was first registered as its OWN PostToolUse group with a
    # matcher overlapping agy-after-reminder's. Whether a runtime dispatches EVERY matching group or only
    # the FIRST could not be settled by measurement here, and if it is the first, this feature would be
    # silently inert - installed, registered, and invisible, the exact failure this repo has been burned
    # by. Owner ruled 2026-08-08 to co-locate it in the ONE group that is directly OBSERVED to fire.
    # This test converts that from an assumption into an enforced invariant.
    It 'is registered in the SAME PostToolUse group as agy-after-reminder, in <driver>' -ForEach @(
        @{ driver = 'clavity-dotnet' }
        @{ driver = 'clavity-classic' }
    ) {
        $manifest = Get-Content -Raw (Join-Path $script:RepoRoot "$driver/plugin/hooks/hooks.json") | ConvertFrom-Json
        $owning = @($manifest.hooks.PostToolUse | Where-Object {
            @($_.hooks) | Where-Object { $_.command -like '*assertion-strength-reminder.sh*' }
        })
        $owning.Count | Should -Be 1 -Because "$driver must register the hook in exactly one group"
        @($owning[0].hooks).Count | Should -BeGreaterThan 1 -Because 'co-location is the point: it must share a group, not sit alone'
        (@($owning[0].hooks) | Where-Object { $_.command -like '*agy-after-reminder.sh*' }).Count |
            Should -Be 1 -Because 'it must share the group with agy-after-reminder, which is observed to dispatch'
    }

    Context 'test-file predicate (strict filename patterns - owner ruling 2026-08-08)' {
        It 'FIRES on <path>' -ForEach @(
            @{ path = 'C:/repo/scripts/tests/foo.Tests.ps1' }
            @{ path = 'C:/repo/tests/Clavity.Ls.Tests/BoundedViewTests.cs' }
            @{ path = 'C:/repo/tests/thing_test.py' }
            @{ path = 'C:/repo/tests/test_thing.py' }
            @{ path = 'C:/repo/src/lib_test.rs' }
        ) {
            $env:HOME = New-IsolatedHome
            $out = Invoke-Hook (New-Payload -FilePath $path -Cwd 'C:/repo')
            ($out -join "`n") | Should -Match '\[ASSERTION-STRENGTH\]'
        }

        It 'is SILENT on <path>' -ForEach @(
            @{ path = 'C:/repo/src/Thing.cs' }
            @{ path = 'C:/repo/tests/fixtures/members.json' }
            @{ path = 'C:/repo/tests/Clavity.Ls.Tests/Clavity.Ls.Tests.csproj' }
            @{ path = 'C:/repo/docs/notes.md' }
            @{ path = 'C:/repo/scripts/tests/_partition.md' }
        ) {
            $env:HOME = New-IsolatedHome
            $out = Invoke-Hook (New-Payload -FilePath $path -Cwd 'C:/repo')
            ($out -join "`n") | Should -Not -Match '\[ASSERTION-STRENGTH\]'
        }
    }

    Context 'debounce' {
        It 'fires on the FIRST touch and is SILENT on the second touch of the same file' {
            $env:HOME = New-IsolatedHome
            $p = New-Payload -FilePath 'C:/repo/scripts/tests/a.Tests.ps1' -Cwd 'C:/repo'
            ((Invoke-Hook $p) -join "`n") | Should -Match '\[ASSERTION-STRENGTH\]'
            ((Invoke-Hook $p) -join "`n") | Should -Not -Match '\[ASSERTION-STRENGTH\]'
        }

        It 'fires again for a DIFFERENT test file in the same session' {
            $env:HOME = New-IsolatedHome
            ((Invoke-Hook (New-Payload -FilePath 'C:/repo/scripts/tests/a.Tests.ps1' -Cwd 'C:/repo')) -join "`n") |
                Should -Match '\[ASSERTION-STRENGTH\]'
            ((Invoke-Hook (New-Payload -FilePath 'C:/repo/scripts/tests/b.Tests.ps1' -Cwd 'C:/repo')) -join "`n") |
                Should -Match '\[ASSERTION-STRENGTH\]'
        }

        It 'never writes a *.head file and never creates .clavity/agy-marks/' {
            $env:HOME = New-IsolatedHome
            Invoke-Hook (New-Payload -FilePath 'C:/repo/scripts/tests/a.Tests.ps1' -Cwd 'C:/repo') | Out-Null
            @(Get-ChildItem -Recurse -File $env:HOME -Filter '*.head' -ErrorAction SilentlyContinue).Count |
                Should -Be 0 -Because 'agy-anomaly-capture-reminder.sh:49-53 forbids a hook writing a .head marker'
            (Test-Path (Join-Path $env:HOME '.clavity/agy-marks')) |
                Should -BeFalse -Because 'that directory is reserved for skill-written discipline markers'
        }
    }

    Context 'debounce key: the hook is branch-agnostic on session_id' {
        # OWNER RULING 2026-08-08 declined the live probe and accepted the per-day fallback. Rather than
        # assume which payload shape production sends, pin BOTH: the fallback definitely ships, and the
        # session path may. Covering both retires the unverified fact instead of betting on it.
        It 'debounces correctly WITH a session_id' {
            $env:HOME = New-IsolatedHome
            $p = New-Payload -FilePath 'C:/repo/scripts/tests/a.Tests.ps1' -Cwd 'C:/repo' -Sid 'sess-XYZ'
            ((Invoke-Hook $p) -join "`n") | Should -Match '\[ASSERTION-STRENGTH\]'
            ((Invoke-Hook $p) -join "`n") | Should -Not -Match '\[ASSERTION-STRENGTH\]'
        }

        It 'debounces correctly WITHOUT a session_id (the per-day fallback)' {
            $env:HOME = New-IsolatedHome
            $p = New-Payload -FilePath 'C:/repo/scripts/tests/a.Tests.ps1' -Cwd 'C:/repo' -Sid ''
            ((Invoke-Hook $p) -join "`n") | Should -Match '\[ASSERTION-STRENGTH\]'
            ((Invoke-Hook $p) -join "`n") | Should -Not -Match '\[ASSERTION-STRENGTH\]'
        }

        It 'keeps the two keys SEPARATE - a session run does not suppress a no-session run' {
            $env:HOME = New-IsolatedHome
            $withSid = New-Payload -FilePath 'C:/repo/scripts/tests/a.Tests.ps1' -Cwd 'C:/repo' -Sid 'sess-XYZ'
            $noSid   = New-Payload -FilePath 'C:/repo/scripts/tests/a.Tests.ps1' -Cwd 'C:/repo' -Sid ''
            ((Invoke-Hook $withSid) -join "`n") | Should -Match '\[ASSERTION-STRENGTH\]'
            ((Invoke-Hook $noSid)   -join "`n") | Should -Match '\[ASSERTION-STRENGTH\]'
        }
    }

    Context 'kill-switch and safety' {
        It 'is suppressed by .no-agy in cwd' {
            $env:HOME = New-IsolatedHome
            $repo = New-IsolatedHome
            New-Item -ItemType File -Path (Join-Path $repo '.no-agy') | Out-Null
            $out = Invoke-Hook (New-Payload -FilePath "$repo/scripts/tests/a.Tests.ps1" -Cwd $repo)
            ($out -join "`n") | Should -Not -Match '\[ASSERTION-STRENGTH\]'
        }

        It 'DOES fire from that same cwd without .no-agy (positive control)' {
            $env:HOME = New-IsolatedHome
            $repo = New-IsolatedHome
            $out = Invoke-Hook (New-Payload -FilePath "$repo/scripts/tests/a.Tests.ps1" -Cwd $repo)
            ($out -join "`n") | Should -Match '\[ASSERTION-STRENGTH\]'
        }

        It 'names all three structural smells in its message' {
            $env:HOME = New-IsolatedHome
            $out = (Invoke-Hook (New-Payload -FilePath 'C:/repo/scripts/tests/a.Tests.ps1' -Cwd 'C:/repo')) -join "`n"
            $out | Should -Match 'cardinality'
            $out | Should -Match 'fallback'
            $out | Should -Match 'distractor'
        }

        It 'ships as pure ASCII' {
            $raw = Get-Content -Raw $script:Hook
            ([regex]::Matches($raw, '[^\x00-\x7F]')).Count | Should -Be 0
        }

        It 'carries no AGY- prefix in its emitted tag' {
            $raw = Get-Content -Raw $script:Hook
            $raw | Should -Not -Match '\[AGY-DISCIPLINES\]' -Because 'ROADMAP.md:712 - this discipline convenes no peer'
        }

        It 'is byte-identical to the clavity-classic mirror' {
            (Test-Path $script:Mirror) | Should -BeTrue
            (Get-FileHash $script:Hook).Hash | Should -Be (Get-FileHash $script:Mirror).Hash
        }
    }

    # The degraded branch runs on any install without jq (see agy-after-reminder.sh:13-15). It is NOT
    # optional coverage: its own template carries four such tests.
    Context 'degraded path (jq absent)' {
        It 'jq is genuinely absent under the reduced PATH (CONTROL for every test below)' {
            $probe = & $script:Bash -c 'PATH=/usr/bin:/bin; export PATH; command -v jq >/dev/null && echo REACHABLE || echo absent'
            ($probe -join '') | Should -Match 'absent' -Because 'if jq were still reachable, every degraded test would silently exercise the jq path instead'
        }

        It 'emits a LOUD jq-missing line on a test-file write' {
            $env:HOME = New-IsolatedHome
            $out = Invoke-HookNoJq (New-Payload -FilePath 'C:/repo/scripts/tests/a.Tests.ps1' -Cwd 'C:/repo')
            ($out -join "`n") | Should -Match 'guard inactive: missing jq'
        }

        It 'is SILENT on a non-test path when jq is absent' {
            $env:HOME = New-IsolatedHome
            $out = Invoke-HookNoJq (New-Payload -FilePath 'C:/repo/src/Thing.cs' -Cwd 'C:/repo')
            ($out -join "`n") | Should -Not -Match 'guard inactive'
        }

        It 'warns at most ONCE per session, not on every test-file write' {
            $env:HOME = New-IsolatedHome
            $p = New-Payload -FilePath 'C:/repo/scripts/tests/a.Tests.ps1' -Cwd 'C:/repo'
            ((Invoke-HookNoJq $p) -join "`n") | Should -Match 'guard inactive: missing jq'
            ((Invoke-HookNoJq $p) -join "`n") | Should -Not -Match 'guard inactive: missing jq'
        }

        # PINS THE FOLD from panel round 1: the two predicates must fire on the SAME set. The earlier draft's
        # degraded pattern fired on footests.ps1 and foo.Test.ps1 where the primary `case` stayed silent -
        # the degraded branch was MORE eager than the primary, the direction the owner ruled against.
        It 'degraded predicate agrees with the primary predicate on <path> (expect <verdict>)' -ForEach @(
            @{ path = 'C:/r/foo.Tests.ps1';       verdict = 'FIRE'   }
            @{ path = 'C:/r/footests.ps1';        verdict = 'silent' }
            @{ path = 'C:/r/foo.Test.ps1';        verdict = 'silent' }
            @{ path = 'C:/r/BoundedViewTests.cs'; verdict = 'FIRE'   }
            @{ path = 'C:/r/AThing.cs';           verdict = 'silent' }
            @{ path = 'C:/r/tests/test_a.py';     verdict = 'FIRE'   }
            @{ path = 'C:/r/x.csproj';            verdict = 'silent' }
        ) {
            $env:HOME = New-IsolatedHome
            $primary  = ((Invoke-Hook     (New-Payload -FilePath $path -Cwd 'C:/r')) -join "`n") -match '\[ASSERTION-STRENGTH\]'
            $env:HOME = New-IsolatedHome
            $degraded = ((Invoke-HookNoJq (New-Payload -FilePath $path -Cwd 'C:/r')) -join "`n") -match 'guard inactive: missing jq'
            $degraded | Should -Be $primary -Because "the degraded branch must fire on exactly the same set as the primary one ($path)"
            $primary  | Should -Be ($verdict -eq 'FIRE')
        }
    }
}

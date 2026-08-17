# Tests for the shipped shield helper, clavity-dotnet/plugin/hooks/agy-shield-lib.sh.
#
# EVERY FIXTURE IS A THROWAWAY REPO, DELIBERATELY. This repository's own root .gitignore covers
# .clavity/, and git cannot re-include a file whose PARENT DIRECTORY is excluded - so the negation
# leak this suite exists to detect is MASKED here and a fixture rooted at the repo would report a
# false pass. Measured 2026-08-14.
#
# The helper is SOURCED, never executed: it returns, it never exits. A test that runs it as a
# process would not exercise the contract that matters.

Describe 'agy-shield-lib.sh' {
    BeforeAll {
        # FIXTURE HYGIENE (see the standing rule near the top of this plan). Every throwaway repo is
        # registered here as it is created and removed in AfterAll. Without this the suite leaks one git
        # repository per row - the pattern that has already left 321 orphaned directories in this repo.
        $script:Fixtures = New-Object System.Collections.ArrayList
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Lib = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-shield-lib.sh'
        Test-Path -LiteralPath $script:Lib | Should -BeTrue -Because 'the helper must exist for any row here to mean anything'

        # PIN GIT BASH EXPLICITLY - bare `bash` is NOT safe here, and this suite shipped with it.
        # BashHookHelpers.ps1 documents why: `Get-Command bash` is NON-DETERMINISTIC, and on this host it
        # depends on WHICH PARENT PROCESS launched pwsh. MEASURED with the same probe both ways:
        #   launched from one shell  -> Git\usr\bin\bash.exe first; bare `bash` runs a Windows path, exit 0
        #   launched from another    -> C:\WINDOWS\system32\bash.exe first (the WSL stub); exit 127,
        #                               "/bin/bash: C:/...: No such file or directory"
        # The error PREFIX is the tell: `/usr/bin/bash:` is Git Bash, `/bin/bash:` is WSL. Under the WSL
        # stub 28 of this suite's 34 rows failed - a FALSE RED that says nothing about the helper.
        # Every other bash-driving suite in scripts/tests already routes through Get-GitBashOrThrow;
        # this one did not, which made it the outlier rather than the precedent.
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $script:Bash = Get-GitBashOrThrow

        # Run a snippet with the helper sourced, inside a fixture repo. Returns an object carrying
        # stdout, stderr and the exit code SEPARATELY - the contract is about stderr specifically,
        # so a merged stream cannot test it.
        function Invoke-Shield {
            param(
                [string]$Root,          # fixture repo root (bash-style path)
                [string]$Body,          # sh to run after sourcing
                [hashtable]$Env = @{}
            )
            $libSh = ($script:Lib -replace '\\', '/')
            # DEBOUNCE ISOLATION - without this the suite is not re-runnable and the mutation controls
            # are uninterpretable. The helper's marker is ${TMPDIR:-/tmp}/.clavity-shield-<class>-<key>
            # with NO repository component, so a LITERAL key shared between rows debounces across
            # independent fixture repos AND across suite runs, because the marker outlives the run.
            # MEASURED, with a control that rules out a broken fixture: repo A key k1 REPORTS; repo A
            # key k1 again is silent (correct); repo B key k1 - a fresh repo never touched - is SILENT;
            # repo B key kZ REPORTS. Three rows asserting a report FIRES therefore passed only for
            # whichever ran first: 34 tests, 31 passed, 3 failed.
            # Every invocation gets its own key, so "silent" always means silent BY CONTROL FLOW and
            # never by a leftover marker. That matters most under the Step 7 mutation controls, where a
            # stale marker would mask a mutation-induced report and score the mutation as caught.
            # `-replace` computes its replacement ONCE, so a body calling the helper twice still shares
            # one key - the same-key semantics those rows rely on survive. Rows that deliberately pin
            # debounce behaviour already build their own GUID keys and contain no `k1` to substitute.
            # NOT done by overriding TMPDIR: measured, Git Bash silently rewrites a Windows TMPDIR
            # handed to it to /tmp/, so an -Env override is dead on this platform.
            $Body = $Body -replace '"k1"', ('"k-' + [guid]::NewGuid().ToString('N') + '"')
            $script = ". '$libSh'`n$Body`n"
            $sf = Join-Path ([IO.Path]::GetTempPath()) ("shield-" + [guid]::NewGuid().ToString('N') + ".sh")
            [IO.File]::WriteAllText($sf, ($script -replace "`r`n", "`n"))
            $outF = "$sf.out"; $errF = "$sf.err"
            $prev = @{}
            foreach ($k in $Env.Keys) { $prev[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
            try {
                $p = Start-Process -FilePath $script:Bash -ArgumentList @($sf) -WorkingDirectory $Root `
                        -RedirectStandardOutput $outF -RedirectStandardError $errF -NoNewWindow -Wait -PassThru
                [pscustomobject]@{
                    ExitCode = $p.ExitCode
                    Out      = (Get-Content -Raw -LiteralPath $outF -ErrorAction SilentlyContinue)
                    Err      = (Get-Content -Raw -LiteralPath $errF -ErrorAction SilentlyContinue)
                }
            }
            finally {
                foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $prev[$k]) }
                Remove-Item -LiteralPath $sf, $outF, $errF -Force -ErrorAction SilentlyContinue
            }
        }

        # A throwaway git repo with NO root .gitignore, so the negation leak is observable.
        function New-FixtureRepo {
            param([string]$Shield, [switch]$NoClavityDir, [string[]]$Track = @())
            $d = Join-Path ([IO.Path]::GetTempPath()) ("shieldfx-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            [void]$script:Fixtures.Add($d)   # registered on creation - see FIXTURE HYGIENE
            & git -C $d init -q
            & git -C $d config user.email t@t.t
            & git -C $d config user.name t
            & git -C $d config core.autocrlf false
            if (-not $NoClavityDir) {
                New-Item -ItemType Directory -Force -Path (Join-Path $d '.clavity') | Out-Null
                if ($null -ne $Shield) {
                    [IO.File]::WriteAllText((Join-Path $d '.clavity/.gitignore'), $Shield)
                }
            }
            # A seed commit so HEAD resolves; without it several git probes behave differently.
            [IO.File]::WriteAllText((Join-Path $d 'seed.txt'), "seed`n")
            & git -C $d add seed.txt
            & git -C $d commit -q -m seed
            foreach ($t in $Track) {
                $full = Join-Path $d $t
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
                [IO.File]::WriteAllText($full, "tracked`n")
                & git -C $d add -f $t
                & git -C $d commit -q -m "track $t"
            }
            ($d -replace '\\', '/')
        }

        function Get-Shield { param([string]$Root) Get-Content -Raw -LiteralPath (Join-Path $Root '.clavity/.gitignore') -ErrorAction SilentlyContinue }
    }

    AfterAll {
        # FIXTURE HYGIENE: -Force because a git repo carries read-only objects on Windows.
        foreach ($f in $script:Fixtures) { Remove-Item -LiteralPath $f -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Context 'Stage A - shield integrity' {
        It 'leaves a healthy shield untouched (control - it must not churn)' {
            $r = New-FixtureRepo -Shield "*`n"
            $before = Get-Shield $r
            $res = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
            (Get-Shield $r) | Should -BeExactly $before
            $res.Err | Should -BeNullOrEmpty -Because 'the healthy path is SILENT by contract - it runs on every capture'
        }

        It 'restores an EMPTIED shield (the 14d defect)' {
            $r = New-FixtureRepo -Shield ''
            Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"' | Out-Null
            (Get-Shield $r) | Should -Match '(?m)^\*$'
        }

        It 'creates .clavity/ and the shield on a FRESH CLONE (A1)' {
            # Every other row presupposes the directory, so A1 was untestable by the rest of the matrix.
            $r = New-FixtureRepo -NoClavityDir
            $res = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
            (Test-Path -LiteralPath (Join-Path $r '.clavity')) | Should -BeTrue
            (Get-Shield $r) | Should -Match '(?m)^\*$'
            $res.Err | Should -BeNullOrEmpty -Because 'A1-success is a SILENT branch'
        }

        It 'does NOT concatenate onto a shield with NO trailing newline (panel R1)' {
            # MEASURED with a control: `printf '%s\n' '*' >> file` against a file ending `foo.txt` with no
            # final newline produced the single line `foo.txt*`, while the same append against a file that
            # DID end in a newline produced two lines. The bare * then never exists as its own line, the
            # [ -f ] test still passes, and the shield is silently broken - so this branch would corrupt
            # the file again on every subsequent call.
            $r = New-FixtureRepo -Shield 'foo.txt'   # New-FixtureRepo writes it verbatim, no trailing LF
            Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"' | Out-Null
            $lines = (Get-Shield $r) -split "`n"
            $lines | Should -Contain '*' -Because 'the bare * must be its OWN line, not appended to foo.txt'
            (Get-Shield $r) | Should -Not -Match 'foo\.txt\*'
        }

        It 'treats a CRLF shield as already correct - it must not append forever (panel R1)' {
            # This shield is gitignored and never checked out, so .gitattributes cannot normalise it and a
            # human editing it on Windows can leave CRLF - the "created by hand" case 14d exists for.
            # Measured on Git Bash `grep -qx '*'` DID match `*\r\n` (LF control also matched), but that is
            # a platform property, not a guarantee. This row pins the behaviour on BOTH.
            $r = New-FixtureRepo
            [IO.File]::WriteAllText((Join-Path $r '.clavity/.gitignore'), "*`r`n")
            1..3 | ForEach-Object { Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"' | Out-Null }
            ([regex]::Matches((Get-Shield $r), '\*')).Count | Should -Be 1 -Because 'a shield that never matches would be appended to on every call and grow without bound'
        }

        It 'is IDEMPOTENT - three runs leave exactly one bare * line' {
            $r = New-FixtureRepo -Shield ''
            1..3 | ForEach-Object { Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"' | Out-Null }
            $stars = ([regex]::Matches((Get-Shield $r), '(?m)^\*$')).Count
            $stars | Should -Be 1
        }
    }

    Context 'A2 middle case - a negation with no bare *' {
        # THREE properties, because each one failed in a different draft of this branch. Asserting
        # only "a fault was reported" passes against BOTH broken versions.
        BeforeEach {
            $script:R = New-FixtureRepo -Shield "!local-anomalies.md`n"
            $script:Res = Invoke-Shield -Root $script:R -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
        }

        It '(a) the human INTENT survives - the named file is still NOT ignored' {
            # The blind-append version destroyed this: appending * after a negation INVERTS it.
            & git -C $script:R check-ignore -q -- '.clavity/local-anomalies.md'
            $LASTEXITCODE | Should -Be 1 -Because 'last-match-wins: the human !line must still win for the file it names'
        }

        It '(b) the DIRECTORY is protected - another file in it IS ignored' {
            # The write-nothing version broke this: it exposed every other file to protect one.
            [IO.File]::WriteAllText((Join-Path $script:R '.clavity/other-marker.md'), "x`n")
            & git -C $script:R check-ignore -q -- '.clavity/other-marker.md'
            $LASTEXITCODE | Should -Be 0 -Because 'the bare * must cover everything the negation does not name'
        }

        It '(c) the ! line is still present and unmodified' {
            (Get-Shield $script:R) | Should -Match '(?m)^!local-anomalies\.md$'
        }

        It 'PREPENDS - the bare * is the FIRST line' {
            (Get-Shield $script:R) -split "`n" | Select-Object -First 1 | Should -BeExactly '*'
        }

        It 'reports the negation loudly (B3, untracked)' {
            # THE OLD ASSERTION WAS THE FILENAME ALONE, AND THE FILENAME IS IN BOTH B3 MESSAGES.
            # `$_as_rel` is interpolated into the TRACKED branch's text too, so this row - despite its
            # name - passed for either branch: a regression that inverted the `ls-files --error-unmatch`
            # test would emit "is TRACKED by git ... git rm --cached" and still be scored green here.
            # AGY-TEST-AUDIT round A, GAP-2. Two assertions, because they fail to different mutations:
            $script:Res.Err | Should -Match 'is NOT ignored' -Because 'this row names the UNTRACKED branch; the filename alone cannot tell the two B3 branches apart'
            # The bracketed reason is the ONLY thing `check-ignore -v` contributes (agy-shield-lib.sh:266).
            # Delete that line and the message degrades to the `[no matching rule reported]` default, which
            # this pattern does not match - so the extraction has an oracle for the first time.
            $script:Res.Err | Should -Match '\[\.clavity/\.gitignore:\d+:!local-anomalies\.md' -Because 'the operator needs the RULE that is overriding the shield, not just the filename they already knew'
        }

        # SCOPE NOTE, because the NAME is broader than the assertion. This checks the ONE temp shape
        # this code creates - `.gitignore.tmp.*` under `.clavity` - not "no temp file anywhere". That is
        # deliberate: a wider glob would redden on unrelated files a developer left in the fixture. The
        # name is kept because the mutation table references it; the limit is recorded here so nobody
        # reads the name as a guarantee it does not make.
        It 'leaves NO temp file behind' {
            @(Get-ChildItem -LiteralPath (Join-Path $script:R '.clavity') -Filter '.gitignore.tmp.*' -Force -ErrorAction SilentlyContinue).Count |
                Should -Be 0 -Because 'the prepend temp is consumed by mv on success and removed on every failure path'
        }
    }

    Context 'A2 FIRST case - a bare * ALREADY present, with a negation below it' {
        # THE OTHER ORDERING, and it had a row in the test TABLE and no code in the SUITE until panel
        # R14. This is the shape the spec's residual actually describes as reachable: a bare `*` IS
        # present, so A2 appends nothing, and B3's untracked branch is what fires. The prepend Context
        # above covers the OPPOSITE ordering (`!` alone, no `*`), and the two are not interchangeable -
        # the residual was only ever reachable in one of them, which is why twelve rounds of the spec's
        # own review did not surface it.
        BeforeEach {
            $script:R2 = New-FixtureRepo -Shield "*`n"
            [IO.File]::WriteAllText((Join-Path $script:R2 '.clavity/.gitignore'), "*`n!local-anomalies.md`n")
            $script:Res2 = Invoke-Shield -Root $script:R2 -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
        }

        It 'appends NOTHING - the shield is left exactly as the human wrote it' {
            (Get-Shield $script:R2) | Should -BeExactly "*`n!local-anomalies.md`n" -Because 'A2 case 1 matches, so nothing is written'
        }

        It 'reports the negation loudly (B3, untracked)' {
            # Same widening as the sibling row above (AGY-TEST-AUDIT round A, GAP-2). This Context is the
            # OTHER ordering - a bare * already present with the negation below it - so A2 appends nothing
            # and B3 is the only thing under test here. That makes the branch discriminator load-bearing:
            # with the filename-only assertion, this row proved nothing except that the helper said
            # SOMETHING about a file whose name it was handed.
            $script:Res2.Err | Should -Match 'is NOT ignored' -Because 'this row names the UNTRACKED branch; the filename alone cannot tell the two B3 branches apart'
            $script:Res2.Err | Should -Match '\[\.clavity/\.gitignore:\d+:!local-anomalies\.md' -Because 'the operator needs the RULE that is overriding the shield, not just the filename they already knew'
        }

        It 'does NOT rewrite the shield to silence the report' {
            # The spec is explicit that B3 returns 0 and does NOT rewrite. Without this assertion the row
            # above stays GREEN against a helper that "fixes" the leak by destroying the human's line.
            (Get-Shield $script:R2) | Should -Match '(?m)^!local-anomalies\.md$'
        }
    }

    Context 'Stage B - effect verification' {
        It 'reports the git rm --cached remedy for a TRACKED path, shield intact afterwards' {
            $r = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $res = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
            $res.Err | Should -Match 'git rm --cached'
            (Get-Shield $r) | Should -Match '(?m)^\*$'
        }

        It 'restores an EMPTIED shield even when the path is TRACKED (the Stage A regression pin)' {
            # Broken until re-panel round 2: a per-file condition suppressed a per-directory guarantee.
            $r = New-FixtureRepo -Shield '' -Track @('.clavity/local-anomalies.md')
            Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"' | Out-Null
            (Get-Shield $r) | Should -Match '(?m)^\*$' -Because 'Stage A is UNCONDITIONAL; one tracked file must never disable the directory guarantee'
        }

        It 'outside a git work tree: the text fallback runs and NOTHING is reported' {
            $d = Join-Path ([IO.Path]::GetTempPath()) ("shieldbare-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            $r = ($d -replace '\\', '/')
            $res = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
            (Get-Content -Raw -LiteralPath (Join-Path $d '.clavity/.gitignore')) | Should -Match '(?m)^\*$'
            $res.Err | Should -BeNullOrEmpty -Because 'B1 is a SILENT branch - Stage A has already guaranteed the text'
        }
    }

    Context 'A0 - argument validation is LOUD and never silent' {
        It 'refuses an empty root, writes nothing, and WARNS' {
            $r = New-FixtureRepo -Shield "*`n"
            $res = Invoke-Shield -Root $r -Body 'agy_shield "" ".clavity/local-anomalies.md" "k1"'
            # `-Not -BeNullOrEmpty` PASSES ON ANY STDERR - a crash, a shell warning, an unrelated
            # diagnostic. It proves the helper made noise, never that it REFUSED. Every validation
            # branch emits `REFUSING`, and a sibling row already matches on exactly that marker.
            $res.Err | Should -Match 'REFUSING' -Because 'a bad argument means the CALLER is broken and is about to write private data - and noise is not a refusal'
            $res.Err | Should -Match 'root argument' -Because 'a refusal names WHICH argument it rejected'
            (Test-Path -LiteralPath '/.clavity') | Should -BeFalse -Because 'mkdir -p "$1/.clavity" with an empty $1 would create a directory at the filesystem root'
        }

        It 'refuses a root that is not a directory, writes nothing, and WARNS' {
            $r = New-FixtureRepo -Shield "*`n"
            $before = Get-Shield $r
            $res = Invoke-Shield -Root $r -Body 'agy_shield "/definitely/not/here" ".clavity/local-anomalies.md" "k1"'
            $res.Err | Should -Match 'REFUSING' -Because 'noise is not a refusal'
            $res.Err | Should -Match ([regex]::Escape('/definitely/not/here')) -Because 'a refusal names the ARGUMENT it rejected'
            # ASSERT THE SIDE EFFECT TOO (panel R13): a message-only assertion stays GREEN against an
            # implementation that warns and then writes anyway - the exact failure a refusal row exists
            # to catch.
            (Get-Shield $r) | Should -BeExactly $before
            (Test-Path -LiteralPath '/definitely') | Should -BeFalse
        }

        It 'refuses a path OUTSIDE .clavity/, writes nothing, and WARNS' {
            # No false "repaired" report for a file left fully exposed - and no silence either.
            $r = New-FixtureRepo -Shield "*`n"
            $before = Get-Shield $r
            $res = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" "docs/secret.md" "k1"'
            $res.Err | Should -Match 'REFUSING' -Because 'noise is not a refusal'
            $res.Err | Should -Match ([regex]::Escape('docs/secret.md')) -Because 'a refusal names the ARGUMENT it rejected'
            (Get-Shield $r) | Should -BeExactly $before
        }

        It 'refuses a path containing .. AND creates nothing outside .clavity/' {
            $r = New-FixtureRepo -Shield "*`n"
            $before = Get-Shield $r
            $res = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/../../escape.md" "k1"'
            $res.Err | Should -Match 'REFUSING' -Because 'noise is not a refusal'
            $res.Err | Should -Match ([regex]::Escape("contains '..'")) -Because 'a refusal names WHY it rejected'
            # Without this half the row stays GREEN against a helper that warns and then traverses
            # anyway - which is the whole point of rejecting the argument.
            (Get-Shield $r) | Should -BeExactly $before
            (Test-Path -LiteralPath (Join-Path (Split-Path -Parent (Split-Path -Parent $r)) 'escape.md')) | Should -BeFalse
        }

        # `Should -Not -BeNullOrEmpty` IS NOT A MESSAGE ASSERTION. It passes on ANY stderr - a crash,
        # a shell warning, a diagnostic from something else entirely - so it proves the helper made
        # noise, never that it REFUSED, and never that it named what it rejected. Both rows below were
        # that assertion alone, with no side-effect leg either. The suite already has the right
        # discriminator: `REFUSING` is the marker every validation branch emits, and the sibling row
        # `a VALIDATION fault is emitted BOTH times under the same key` matches on it.
        # Pinning the DISTINGUISHING phrase, not the whole sentence, is this plan's stated bar.
        It 'refuses an EMPTY path argument' {
            $r = New-FixtureRepo -Shield "*`n"
            $before = Get-Shield $r
            $res = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" "" "k1"'
            $res.Err | Should -Match 'REFUSING' -Because 'noise is not a refusal; the row must see the refusal itself'
            $res.Err | Should -Match 'path argument is empty' -Because 'a refusal names WHAT it rejected'
            (Get-Shield $r) | Should -BeExactly $before -Because 'a refused call must not touch the shield'
        }

        It 'refuses an ABSOLUTE path argument' {
            $r = New-FixtureRepo -Shield "*`n"
            $before = Get-Shield $r
            $res = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" "/etc/passwd" "k1"'
            $res.Err | Should -Match 'REFUSING' -Because 'noise is not a refusal; the row must see the refusal itself'
            $res.Err | Should -Match ([regex]::Escape('/etc/passwd')) -Because 'a refusal names the ARGUMENT it rejected'
            (Get-Shield $r) | Should -BeExactly $before -Because 'a refused call must not touch the shield'
        }

        It 'A1 mkdir FAILURE: returns 0, writes nothing, reports ENVIRONMENT once per key' {
            # Make .clavity a FILE, so mkdir -p cannot create the directory. This is the only branch that
            # exercises A1's failure path, and the existing rows all presuppose the directory exists.
            $r = New-FixtureRepo -NoClavityDir
            [IO.File]::WriteAllText((Join-Path $r '.clavity'), "not a directory`n")
            $k = 'mk-' + [guid]::NewGuid().ToString('N')
            $res = Invoke-Shield -Root $r -Body "agy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k`"`nagy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k`"`necho RC=`$?"
            $res.Out | Should -Match 'RC=0' -Because 'A1 failure must never hard-block'
            ([regex]::Matches($res.Err, 'could not create')).Count | Should -Be 1 -Because 'class ENVIRONMENT is debounced per key'
        }

        It 'the A2 temp SWEEP is gated - it does not run on every call' {
            # Panel R10: the first version attempted the marker write with 2>/dev/null and swept
            # unconditionally, so an unwritable TMPDIR meant `find` ran on EVERY call - the exact
            # per-call subprocess cost the gate exists to remove. Assert the marker LATCHES.
            #
            # THE PATH IS RESOLVED BY BASH, NOT BY POWERSHELL, and that is not fussiness. MEASURED: Git
            # Bash REWRITES a Windows TMPDIR handed to it - setting TMPDIR to
            # C:\Users\...\AppData\Local\Temp\ from PowerShell and printing ${TMPDIR} inside the child
            # yields `/tmp/`. So passing -Env @{ TMPDIR = ... } is DEAD, and asserting a Windows path
            # only worked because Git Bash happens to mount /tmp onto that same directory on this box
            # (measured: a file bash wrote to /tmp WAS visible to PowerShell there). That coincidence is
            # a property of this machine's mount table and does not hold on Linux or in CI - so the row
            # would have been silently checking the wrong location on the platform it matters most.
            # Ask the shell where it actually put the marker.
            $r = New-FixtureRepo -Shield "*`n"
            $k = 'sw-' + [guid]::NewGuid().ToString('N')
            $res = Invoke-Shield -Root $r -Body @"
agy_shield "`$PWD" ".clavity/local-anomalies.md" "$k"
_m="`${TMPDIR:-/tmp}/.clavity-shield-swept-$k"
[ -f "`$_m" ] && echo "SWEPT_MARKER_PRESENT"
"@
            $res.Out | Should -Match 'SWEPT_MARKER_PRESENT' -Because 'the sweep marker must latch, or the gate never closes'
        }

        It 'the A2 sweep actually DELETES a stale temp, and spares a fresh one (capstone R2)' {
            # THE ROW ABOVE ASSERTS THE GATE LATCHES; NOTHING ASSERTED THE SWEEP DOES ANY WORK.
            # MEASURED: replacing the whole `find ... -delete` with `:` left the suite 35/0 green, so the
            # deletion had no oracle at all - the gate was tested and the thing it gates was not.
            #
            # THE FRESH TEMP IS THE CONTROL AND IT IS NOT DECORATION. `-mtime +30` is the whole point:
            # a sweep that deleted everything matching `.gitignore.tmp.*` would satisfy a
            # deletion-only assertion while destroying a temp file another session is using RIGHT NOW.
            $r = New-FixtureRepo -Shield "*`n"
            $stale = Join-Path $r '.clavity/.gitignore.tmp.STALE'
            $fresh = Join-Path $r '.clavity/.gitignore.tmp.FRESH'
            [IO.File]::WriteAllText($stale, "x`n")
            [IO.File]::WriteAllText($fresh, "x`n")
            # -mtime +30 is measured against the file's modification time, so age the stale one past it.
            (Get-Item -LiteralPath $stale).LastWriteTime = (Get-Date).AddDays(-40)

            # A FRESH key, so the sweep gate has not latched yet for this "session" and the sweep runs.
            $k = 'sweepwork-' + [guid]::NewGuid().ToString('N')
            $res = Invoke-Shield -Root $r -Body @"
agy_shield "`$PWD" ".clavity/local-anomalies.md" "$k"
[ -f "`${TMPDIR:-/tmp}/.clavity-shield-swept-$k" ] && echo "GATE_LATCHED"
"@

            # ASSERT THE PRECONDITION, do not assume it (capstone R3). The sweep is deliberately gated on
            # a marker in the SHELL's ${TMPDIR:-/tmp}, which is a DIFFERENT directory from the Windows temp
            # these fixtures live in - so a host where the shell's temp is unwritable skips the sweep by
            # design. Without this line the row would then report "the stale temp survived", accusing the
            # sweep of a defect when the gate simply, correctly, never latched. A control must assert its
            # own precondition, or its failure message names the wrong culprit.
            $res.Out | Should -Match 'GATE_LATCHED' -Because 'the sweep is gated on this marker; if it never latched the assertions below prove nothing about the sweep'

            (Test-Path -LiteralPath $stale) | Should -BeFalse -Because 'a temp older than the -mtime +30 window is exactly what the sweep exists to remove'
            (Test-Path -LiteralPath $fresh) | Should -BeTrue  -Because 'a RECENT temp may belong to a concurrent session and must survive'
        }

        It 'mktemp UNAVAILABLE: the directory is still protected, and it says so LOUDLY' {
            # Panel R10. Writing nothing here left NO bare * in the shield, so the whole DIRECTORY stayed
            # exposed while the helper returned 0 - a per-file concern suppressing a per-directory
            # guarantee, which the spec forbids. Shadow mktemp with a failing stub to reach the branch.
            $r = New-FixtureRepo -Shield "!local-anomalies.md`n"
            $res = Invoke-Shield -Root $r -Body "mktemp() { return 1; }`nagy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"`""
            (Get-Shield $r) | Should -Match '(?m)^\*$' -Because 'the directory must be protected even when the atomic prepend is impossible'
            $res.Err | Should -Match 'APPENDED rather than prepended' -Because 'overriding a human negation must never be silent'
        }

        It 'mktemp UNAVAILABLE on a shield with NO TRAILING NEWLINE still shields the DIRECTORY (capstone)' {
            # THE ROW ABOVE PASSED WHILE THIS ONE FAILED, and the only difference is a trailing newline.
            # The fallback appended with `printf '%s\n' '*'` where the sibling append branch uses the
            # leading-newline form, so a shield ending `!local-anomalies.md` with no final newline became
            # the SINGLE line `!local-anomalies.md*`: no bare `*` anywhere, the negation destroyed, and
            # `check-ignore` reporting another file in the directory as NOT ignored - while the helper
            # returned 0. That is the exact per-directory failure this item exists to prevent, on the
            # branch that exists to be the safe floor.
            #
            # New-FixtureRepo writes $Shield verbatim, so omitting the `n is what makes this the
            # no-trailing-newline case. Reaching the fallback needs a `!` line (the elif matched) AND a
            # failing mktemp.
            $r = New-FixtureRepo -Shield '!local-anomalies.md'
            Invoke-Shield -Root $r -Body "mktemp() { return 1; }`nagy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"`"" | Out-Null

            (Get-Shield $r) | Should -Match '(?m)^\*$' -Because 'the bare * must be its OWN line, not concatenated onto the negation'
            (Get-Shield $r) | Should -Match '(?m)^!local-anomalies\.md$' -Because 'the human negation must survive as its own line too'

            # THE SIDE EFFECT IS THE POINT, not the file text: assert the directory is actually shielded.
            # A text-only assertion would have passed against a shield that reads correctly but does not
            # ignore anything.
            [IO.File]::WriteAllText((Join-Path $r '.clavity/other-marker.md'), "x`n")
            & git -C $r check-ignore -q -- '.clavity/other-marker.md'
            $LASTEXITCODE | Should -Be 0 -Because 'another file in the directory MUST be ignored; a corrupted single line leaves it exposed'
        }

        It 'ALWAYS returns 0 - it must never hard-block a caller' {
            $r = New-FixtureRepo -Shield "*`n"
            foreach ($args in @('"" "x" "k"', '"$PWD" "docs/secret.md" "k"', '"$PWD" ".clavity/local-anomalies.md" "k"')) {
                $res = Invoke-Shield -Root $r -Body "agy_shield $args; echo RC=`$?"
                $res.Out | Should -Match 'RC=0'
            }
        }

        It 'does NOT kill its CALLER - the line after the call still runs' {
            # Measured: a sourced `exit 0` ended the parent before its next line, and the parent
            # still reported success. This row is the pin for `return`, never `exit`.
            $r = New-FixtureRepo -Shield "*`n"
            $res = Invoke-Shield -Root $r -Body 'agy_shield "" "x" "k"' -Env @{}
            $res2 = Invoke-Shield -Root $r -Body "agy_shield `"`" `"x`" `"k`"`necho STILL_ALIVE"
            $res2.Out | Should -Match 'STILL_ALIVE' -Because 'a sourced exit would terminate the caller silently'
        }
    }

    Context 'the debounce key' {
        It 'emits a PERSISTENT fault ONCE for the same key' {
            $r = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $k = 'samekey-' + [guid]::NewGuid().ToString('N')
            $res = Invoke-Shield -Root $r -Body "agy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k`"`nagy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k`""
            ([regex]::Matches($res.Err, 'git rm --cached')).Count | Should -Be 1
        }

        It 'emits the SAME fault AGAIN under a DIFFERENT key' {
            # WITHOUT THIS ROW THE KEY IS NEVER EXERCISED: an implementation that ignores the key and
            # writes one hardcoded global marker satisfies the same-key row trivially, while destroying
            # the per-session isolation the key exists for.
            $r = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $k1 = 'k1-' + [guid]::NewGuid().ToString('N')
            $k2 = 'k2-' + [guid]::NewGuid().ToString('N')
            $res = Invoke-Shield -Root $r -Body "agy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k1`"`nagy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k2`""
            ([regex]::Matches($res.Err, 'git rm --cached')).Count | Should -Be 2
        }

        It 'an EMPTY key is LEGAL - debouncing off, no validation fault' {
            # [A-Za-z0-9._-]+ requires >=1 char, so running the regex over EVERY key made the
            # sanctioned empty key a loud never-debounced fault on every single call.
            $r = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $res = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" ""'
            $res.Err | Should -Match 'git rm --cached'
            $res.Err | Should -Not -Match 'REFUSING'
            # MEASURED 2026-08-16 - WITHOUT THIS LINE THE ROW CANNOT DETECT ITS OWN REGRESSION.
            # The mutation this row exists to catch (validate the key even when EMPTY) emits
            # `ignoring a malformed debounce key (debouncing disabled for this call): []`, which
            # contains no `REFUSING` - so the two assertions above both stayed GREEN under it and the
            # control scored the mutation as caught when nothing caught it. Verified by running that
            # mutation: green before this line, RED after.
            $res.Err | Should -Not -Match 'malformed' -Because 'the sanctioned empty key must not be reported as a fault at all'
        }

        It 'a VALIDATION fault is emitted BOTH times under the same key' {
            # Only a repeat test can tell the two debounce policies apart.
            $r = New-FixtureRepo -Shield "*`n"
            $k = 'vk-' + [guid]::NewGuid().ToString('N')
            $res = Invoke-Shield -Root $r -Body "agy_shield `"`$PWD`" `"docs/secret.md`" `"$k`"`nagy_shield `"`$PWD`" `"docs/secret.md`" `"$k`""
            ([regex]::Matches($res.Err, 'REFUSING')).Count | Should -Be 2 -Because 'a broken CALLER must not be silenced by a marker'
        }

        It 'a MALFORMED key does not disable the guard' {
            $r = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $res = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "../../escape"'
            $res.Err | Should -Match 'git rm --cached' -Because 'a malformed session id must never disable a data-leak guard'
            # THE SECOND ASSERTION WAS DELETED BECAUSE IT COULD NOT FAIL, and it is recorded here so
            # nobody restores it. It read:
            #     (Test-Path (Join-Path ([IO.Path]::GetTempPath()) '../../escape')) | Should -BeFalse
            # MEASURED, both sides resolved:
            #     the shell would create  ${TMPDIR:-/tmp}/.clavity-shield-swept-../../escape  ->  /escape
            #     the test looked at      <WindowsTemp>\..\..\escape                          ->  C:\Users\user\AppData\escape
            # TMPDIR is unset under Git Bash, so `/tmp` is MSYS-root-relative and the `..` components
            # walk to a different absolute location on each side. The assertion inspected a path this
            # code cannot write to under this input: always absent, always green, whatever the guard did.
            # It is NOT replaced by a corrected path check - that would hard-code an MSYS-root literal
            # into a Pester suite - and NOT by re-deriving the target in the test, which would reimplement
            # the code under test inside its own assertion.
            # RESIDUAL, stated rather than papered over: this row proves the guard STILL FIRES on a
            # malformed key (the assertion above, which is real and can fail). It does NOT prove the
            # malformed key wrote nothing outside the fixture. Closing that needs the escape target
            # resolved by the shell itself, which is work for the transient-Pester shape recorded as
            # ROADMAP section 16, not for a row that would be hard-coding a path today.
        }

        # ------------------------------------------------------------------ AGY-TEST-AUDIT round A.
        # THE MARKER DIRECTORY IS RESOLVED BY A LOOP (agy-shield-lib.sh:58) AND ONLY ITS FIRST CANDIDATE
        # WAS EVER EXERCISED. Both rows below drive the SECOND candidate, and they do it by assigning
        # TMPDIR *inside the shell body* - NOT with `-Env`. The suite records at the top of Invoke-Shield
        # that Git Bash silently rewrites a Windows TMPDIR handed to it to `/tmp/`, so an -Env override is
        # dead on this platform; an in-body export is not, and is what these rows measured working.
        It 'falls back to $HOME/.clavity-tmp when TMPDIR cannot be created, and STILL debounces there' {
            # The fallback is not decoration: if it goes, `_ass_dir` is empty, the helper takes its
            # "no writable marker location" branch and emits on EVERY call. So the discriminating
            # assertion is the COUNT, not the presence, of the report.
            $r = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $k = 'fb-' + [guid]::NewGuid().ToString('N')
            # TMPDIR points BELOW A REGULAR FILE, so `mkdir -p` cannot create it - a deterministic
            # unwritable temp that needs no permissions games and no elevation.
            $body = @"
: > "`$PWD/blocker"
export TMPDIR="`$PWD/blocker/sub"
export HOME="`$PWD/fakehome"
mkdir -p "`$HOME"
agy_shield "`$PWD" ".clavity/local-anomalies.md" "$k"
agy_shield "`$PWD" ".clavity/local-anomalies.md" "$k"
"@
            $res = Invoke-Shield -Root $r -Body $body
            $fallbackDir = Join-Path $r 'fakehome/.clavity-tmp'
            (Test-Path -LiteralPath $fallbackDir) | Should -BeTrue -Because 'an unwritable TMPDIR must resolve to the HOME candidate, not to no directory at all'
            @(Get-ChildItem -LiteralPath $fallbackDir -Filter ".clavity-shield-persistent-$k" -Force).Count |
                Should -Be 1 -Because 'the debounce marker must actually land in the fallback directory'
            ([regex]::Matches($res.Err, 'git rm --cached')).Count |
                Should -Be 1 -Because 'TWO reports would mean the fallback directory was found but never used as the debounce store - the guard degrading to warn-every-time'
        }

        It 'the marker sweep deletes ONLY its own aged markers - not fresh ones, not a sibling hook''s' {
            # agy-shield-lib.sh:79 prunes `.clavity-shield-*` at -mtime +30, on the run that CREATES a
            # marker. TWO controls, because the two plausible regressions fail in opposite directions:
            # dropping the `find` leaves the stale marker, and BROADENING the glob (the source comment at
            # :75-79 warns the siblings own `.clavity-anomaly-*` and `.clavity-assert-*`) eats files this
            # hook does not own. A row asserting only "the stale one is gone" catches the first and scores
            # the second as a pass.
            $r = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $home2 = Join-Path $r 'fakehome'
            $dir = Join-Path $home2 '.clavity-tmp'
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            $stale   = Join-Path $dir '.clavity-shield-persistent-STALE'
            $fresh   = Join-Path $dir '.clavity-shield-persistent-FRESH'
            $foreign = Join-Path $dir '.clavity-anomaly-STALE'
            foreach ($f in @($stale, $fresh, $foreign)) { [IO.File]::WriteAllText($f, "x`n") }
            # -mtime +30 reads the modification time, so age the two that must LOOK stale.
            foreach ($f in @($stale, $foreign)) { (Get-Item -LiteralPath $f -Force).LastWriteTime = (Get-Date).AddDays(-40) }
            $k = 'sw-' + [guid]::NewGuid().ToString('N')
            $body = @"
: > "`$PWD/blocker"
export TMPDIR="`$PWD/blocker/sub"
export HOME="`$PWD/fakehome"
agy_shield "`$PWD" ".clavity/local-anomalies.md" "$k"
"@
            $res = Invoke-Shield -Root $r -Body $body
            # PRECONDITION FIRST (the standing rule): the sweep runs ONLY on the call that creates a
            # marker. If no marker was created the sweep never ran, and every assertion below would be
            # reporting on a sweep that did not happen rather than on one that misbehaved.
            @(Get-ChildItem -LiteralPath $dir -Filter ".clavity-shield-persistent-$k" -Force).Count |
                Should -Be 1 -Because 'the sweep is gated on marker CREATION; without a new marker the assertions below prove nothing'
            (Test-Path -LiteralPath $stale)   | Should -BeFalse -Because 'a marker past the -mtime +30 window is exactly what the sweep exists to remove'
            (Test-Path -LiteralPath $fresh)   | Should -BeTrue  -Because 'CONTROL: a sweep that deleted every .clavity-shield-* would satisfy the assertion above while destroying live debounce state'
            (Test-Path -LiteralPath $foreign) | Should -BeTrue  -Because 'CONTROL: the sibling hooks own .clavity-anomaly-*; a broadened glob would prune another hook''s markers on this hook''s schedule'
        }
    }
}

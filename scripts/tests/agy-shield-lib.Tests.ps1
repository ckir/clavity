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
        # MARKER HYGIENE - VESTIGIAL SINCE ROADMAP 17a, AND KEPT ONLY AS A BACKSTOP. It exists because
        # every Invoke-Shield call used to write `.clavity-shield-<class>-<key>` into the shell's shared
        # temp directory where nothing removed it - the helper's own prune runs only at -mtime +30 and only
        # on a run that creates a marker, so the suite's markers were always too young for it. MEASURED at
        # anomaly triage 2026-08-17: 989 had accumulated in TMPDIR.
        # That cannot happen now: markers land inside each throwaway fixture repo, which AfterAll deletes
        # wholesale. The snapshot/diff below therefore has nothing to find in the ordinary case. It is left
        # in place because it costs one directory listing and would still catch a regression that put
        # markers back in a shared location - but do not read it as load-bearing, and do not "fix" it by
        # broadening the delete.
        # SNAPSHOT-AND-DIFF, not a blanket delete of `.clavity-shield-*`. Two sessions can be open on this
        # repository at once, and other hooks write markers with the SAME prefix - wiping them all would
        # silence another session's live data-leak debounce, which is the one thing these markers exist for.
        # PER-RUN IDENTITY, and the 32-hex shape it replaces was a REACHABLE defect (capstone round 1,
        # confirmed by injecting a marker mid-run: it was deleted). Two runs of THIS suite mint keys of
        # the SAME shape, so a filter keyed on shape cannot tell mine from a concurrent run's - and the
        # snapshot clause does not save it, because a marker another session creates AFTER my snapshot
        # is legitimately 'new' to me. Deleting it destroys that run's live debounce state.
        # A tag unique to this run is necessary AND sufficient: no other process can mint it.
        $script:RunTag = 'rt' + [guid]::NewGuid().ToString('N').Substring(0, 10)
        $script:MarkerDir = [IO.Path]::GetTempPath()
        $script:MarkersBefore = @{}
        foreach ($m in @(Get-ChildItem -LiteralPath $script:MarkerDir -Filter '.clavity-shield-*' -Force -ErrorAction SilentlyContinue)) {
            $script:MarkersBefore[$m.Name] = $true
        }
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
                [hashtable]$Env = @{},
                [string]$Shell = ''     # '' = Git Bash; 'dash' = run the snippet under dash, launched THROUGH Git Bash (the portability rows)
            )
            $libSh = ($script:Lib -replace '\\', '/')
            # DEBOUNCE ISOLATION. Since roadmap 17a the marker lives in each repository's own .clavity/
            # (`<root>/.clavity/.clavity-shield-<class>-<key>`), so independent fixture repos no longer
            # collide by construction and markers no longer outlive the run - each fixture is deleted in
            # AfterAll. What REMAINS true is that a LITERAL key shared between rows debounces across two
            # calls against the SAME fixture, so a row asserting a report FIRES would pass only if it ran
            # first. Every invocation therefore still gets its own key, and "silent" always means silent
            # BY CONTROL FLOW rather than by a leftover marker - which matters most under the mutation
            # controls, where a stale marker would mask a mutation-induced report and score it as caught.
            # THE HISTORICAL MEASUREMENT, kept because it IS the defect 17a fixed: the marker used to be
            # ${TMPDIR:-/tmp}/.clavity-shield-<class>-<key> with NO repository component, and repo A key k1
            # REPORTED; repo A key k1 again was silent (correct); a FRESH repo B under the same key was
            # SILENT; repo B under a different key REPORTED. Three rows asserting a report fires passed
            # only for whichever ran first: 34 tests, 31 passed, 3 failed. That third result is now
            # asserted to be the OPPOSITE, by 'reports the SAME fault in a SECOND repository under the
            # SAME key (roadmap 17a)'.
            # `-replace` computes its replacement ONCE, so a body calling the helper twice still shares
            # one key - the same-key semantics those rows rely on survive. Rows that deliberately pin
            # debounce behaviour already build their own GUID keys and contain no `k1` to substitute.
            # NOT done by overriding TMPDIR: measured, Git Bash silently rewrites a Windows TMPDIR
            # handed to it to /tmp/, so an -Env override is dead on this platform.
            $Body = $Body -replace '"k1"', ('"k-' + $script:RunTag + '-' + [guid]::NewGuid().ToString('N') + '"')
            $script = ". '$libSh'`n$Body`n"
            $sf = Join-Path ([IO.Path]::GetTempPath()) ("shield-" + [guid]::NewGuid().ToString('N') + ".sh")
            [IO.File]::WriteAllText($sf, ($script -replace "`r`n", "`n"))
            $outF = "$sf.out"; $errF = "$sf.err"
            $prev = @{}
            foreach ($k in $Env.Keys) { $prev[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
            try {
                # dash is launched THROUGH Git Bash by a one-line launcher FILE: Start-Process does not quote the elements of an
                # -ArgumentList array, so an inline `-c 'exec dash ...'` is split on its spaces and dash never runs (measured - the first
                # version of the rows below passed VACUOUSLY because of exactly that).
                $launcher = "$sf.run.sh"
                if ($Shell -eq 'dash') { [IO.File]::WriteAllText($launcher, "exec dash `"`$(cygpath -u `"`$1`")`"`n") }
                $argList = if ($Shell -eq 'dash') { @($launcher, $sf) } else { @($sf) }
                $p = Start-Process -FilePath $script:Bash -ArgumentList $argList -WorkingDirectory $Root `
                        -RedirectStandardOutput $outF -RedirectStandardError $errF -NoNewWindow -Wait -PassThru
                [pscustomobject]@{
                    ExitCode = $p.ExitCode
                    Out      = (Get-Content -Raw -LiteralPath $outF -ErrorAction SilentlyContinue)
                    Err      = (Get-Content -Raw -LiteralPath $errF -ErrorAction SilentlyContinue)
                }
            }
            finally {
                foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $prev[$k]) }
                Remove-Item -LiteralPath $sf, $outF, $errF, "$sf.run.sh" -Force -ErrorAction SilentlyContinue
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
        # MARKER HYGIENE: remove ONLY markers that (a) appeared during this run and (b) carry this suite's
        # RUN TAG - a token minted once per run and embedded in every key this suite generates. Shape
        # alone was NOT enough: a concurrent run of this same suite mints the same shape. The tag can be
        # minted by nothing else. Both conditions are kept: (a) alone would delete a concurrent
        # session's new markers, (b) alone would delete a previous run's, which a parallel suite may still
        # be using for debounce.
        foreach ($m in @(Get-ChildItem -LiteralPath $script:MarkerDir -Filter '.clavity-shield-*' -Force -ErrorAction SilentlyContinue)) {
            if (-not $script:MarkersBefore.ContainsKey($m.Name) -and $m.Name -like "*$($script:RunTag)*") {
                Remove-Item -LiteralPath $m.FullName -Force -ErrorAction SilentlyContinue
            }
        }
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

    # BRANCH 21 capstone R1 (driver-measured): the open-issues skill SOURCES this file from whatever shell the agent's tool runs.
    # Under dash the bash-only A2 read printed `[[: not found` and appended `\n*\n` to a healthy shield on EVERY call. The fast path is
    # now taken only when BASH_VERSION is set; every other shell runs the original greps. These rows run the helper under dash and
    # assert BYTES, so the unbounded-growth failure cannot come back unseen.
    Context 'sourced under a NON-bash shell (dash) - the open-issues snippet runs in the agent''s shell' {
        BeforeAll {
            # PRECONDITION, asserted: if dash is missing every row below would run bash and assert nothing.
            $script:DashProbe = & $script:Bash -c 'command -v dash >/dev/null 2>&1 && echo yes'
            $script:DashProbe | Should -Be 'yes' -Because 'dash must exist in the Git for Windows MSYS tree, or these rows would silently test nothing'
            $script:Dash = 'dash'
        }
        It 'leaves a healthy shield BYTE-IDENTICAL over three calls, silently' -ForEach @(
            @{ Name = 'LF star';        Text = "*`n" }
            @{ Name = 'CRLF star';      Text = "*`r`n" }
            @{ Name = 'star + negation'; Text = "*`n!local-anomalies.md`n" }
            @{ Name = 'no trailing newline'; Text = '*' }
        ) {
            $r = New-FixtureRepo -Shield $Text
            $body = 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"' + "`n" + 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"' + "`n" + 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
            $res = Invoke-Shield -Root $r -Body ('printf "%s" "[${BASH_VERSION:-}]" > "$PWD/shell-probe.txt"' + "`n" + $body) -Shell $script:Dash
            # CONTROL, asserted first: the snippet really ran under a shell WITHOUT BASH_VERSION. Without it an unlaunched dash leaves the
            # shield untouched and every assertion below passes for the wrong reason.
            (Get-Content -Raw -LiteralPath (Join-Path $r 'shell-probe.txt')) | Should -BeExactly '[]' -Because 'the rows must run under dash, not bash'
            (Get-Shield $r) | Should -BeExactly $Text -Because "[$Name] a shield that already carries * must not be appended to, in ANY shell"
            $res.Err | Should -Not -Match 'not found' -Because 'no bash-only construct may be EXECUTED under a non-bash shell'
        }
        It 'leaves a healthy shield byte-identical under dash even when BASH_VERSION is EXPORTED into it (capstone R2)' {
            # A parent bash that exported BASH_VERSION would otherwise send a dash child down the bash-only branch.
            $r = New-FixtureRepo -Shield "*`n"
            # The variable is exported INSIDE the dash snippet, not through -Env: a process-level override leaked into the rows after
            # this one (measured - they ran dash with BASH_VERSION set and failed), and the launching bash re-exports its own value.
            $body = 'export BASH_VERSION=5.2.0-fake' + "`n" + 'printf "%s" "[${BASH_VERSION:-}]" > "$PWD/shell-probe.txt"' + "`n" + 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"' + "`n" + 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
            $res = Invoke-Shield -Root $r -Body $body -Shell $script:Dash
            # CONTROL: dash really has a non-empty BASH_VERSION, so the guard under test is the capability test and not an empty variable.
            (Get-Content -Raw -LiteralPath (Join-Path $r 'shell-probe.txt')) | Should -BeExactly '[5.2.0-fake]' -Because 'BASH_VERSION must be set in the dash snippet, or this row tests nothing'
            (Get-Shield $r) | Should -BeExactly "*`n"
            $res.Err | Should -Not -Match 'not found'
        }
        It 'PREPENDS * to a negation-only shield under dash exactly as bash does' {
            $r = New-FixtureRepo -Shield "!local-anomalies.md`n"
            $null = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"' -Shell $script:Dash
            (Get-Shield $r) | Should -BeExactly "*`n!local-anomalies.md`n"
        }
        It 'APPENDS * to a shield that lacks it under dash (once, then stable)' {
            $r = New-FixtureRepo -Shield "foo.txt`n"
            $body = 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"' + "`n" + 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
            $null = Invoke-Shield -Root $r -Body $body -Shell $script:Dash
            (Get-Shield $r) | Should -BeExactly "foo.txt`n`n*`n"
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
            # The bracketed reason is the ONLY thing `check-ignore -v` contributes, so this pattern is the
            # oracle for that extraction: delete the `check-ignore -v` line and `$_as_why` is empty.
            # WHAT HAPPENS THEN CHANGED IN roadmap 17a's capstone, and the old wording here described the
            # behaviour it USED to have - it said the message "degrades to the `[no matching rule reported]`
            # default". There is no such default any more. An empty `$_as_why` now selects a different B3
            # message entirely, which carries no bracketed rule at all, because the old one asserted a
            # negation line that measurement showed need not exist. Either way this pattern fails to match,
            # so the row keeps its oracle - but it keeps it for a different reason than it used to, and a
            # future round folding against the old sentence would have been folding against fiction.
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

        It 'A1 mkdir FAILURE: returns 0, writes nothing, reports ENVIRONMENT every time (no store, no debounce)' {
            # Make .clavity a FILE, so mkdir -p cannot create the directory. This is the only branch that
            # exercises A1's failure path, and the existing rows all presuppose the directory exists.
            $r = New-FixtureRepo -NoClavityDir
            [IO.File]::WriteAllText((Join-Path $r '.clavity'), "not a directory`n")
            $k = 'mk-' + $script:RunTag + '-' + [guid]::NewGuid().ToString('N')
            $res = Invoke-Shield -Root $r -Body "agy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k`"`nagy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k`"`necho RC=`$?"
            $res.Out | Should -Match 'RC=0' -Because 'A1 failure must never hard-block'
            # WAS 1 UNTIL ROADMAP 17a, AND THE CHANGE IS DELIBERATE. The marker directory is now the
            # repository's own .clavity/ - which is precisely what this fixture prevents from being created
            # - so there is nowhere to record a debounce, and _agy_shield_say takes its "no writable marker
            # location" branch and emits every time. That branch's own comment states the principle: a
            # data-leak notice must never be lost because the debounce store is unavailable. Restoring
            # once-per-key here would require a shared fallback directory, which is exactly the
            # cross-repository collision 17a removed. The cost is real and accepted: in a repository
            # misconfigured this way, every invocation warns rather than one per session.
            ([regex]::Matches($res.Err, 'could not create')).Count | Should -Be 2 -Because 'with no writable .clavity/ there is no debounce store, so the ENVIRONMENT fault is emitted on every call rather than swallowed'
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
            $k = 'sw-' + $script:RunTag + '-' + [guid]::NewGuid().ToString('N')
            $res = Invoke-Shield -Root $r -Body @"
agy_shield "`$PWD" ".clavity/local-anomalies.md" "$k"
_m=".clavity/.clavity-shield-swept-$k"
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
            $k = 'sweepwork-' + $script:RunTag + '-' + [guid]::NewGuid().ToString('N')
            $res = Invoke-Shield -Root $r -Body @"
agy_shield "`$PWD" ".clavity/local-anomalies.md" "$k"
[ -f ".clavity/.clavity-shield-swept-$k" ] && echo "GATE_LATCHED"
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
            $k = 'samekey-' + $script:RunTag + '-' + [guid]::NewGuid().ToString('N')
            $res = Invoke-Shield -Root $r -Body "agy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k`"`nagy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k`""
            ([regex]::Matches($res.Err, 'git rm --cached')).Count | Should -Be 1
        }

        It 'emits the SAME fault AGAIN under a DIFFERENT key' {
            # WITHOUT THIS ROW THE KEY IS NEVER EXERCISED: an implementation that ignores the key and
            # writes one hardcoded global marker satisfies the same-key row trivially, while destroying
            # the per-session isolation the key exists for.
            $r = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $k1 = 'k1-' + $script:RunTag + '-' + [guid]::NewGuid().ToString('N')
            $k2 = 'k2-' + $script:RunTag + '-' + [guid]::NewGuid().ToString('N')
            $res = Invoke-Shield -Root $r -Body "agy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k1`"`nagy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k2`""
            ([regex]::Matches($res.Err, 'git rm --cached')).Count | Should -Be 2
        }

        It 'reports the SAME fault in a SECOND repository under the SAME key (roadmap 17a)' {
            # THE DEFECT THIS STEP EXISTS FOR, promoted from a comment into an assertion. Invoke-Shield's
            # header at :64-80 already records the measurement - "repo B key k1 - a fresh repo never
            # touched - is SILENT" - and works around it with a per-invocation key. A workaround that
            # keeps the suite honest is not the same as a guard: one session across two repositories got
            # ONE fault report in total, and the second repository's leak was never surfaced.
            #
            # ITS OWN KEY, and never the literal "k1": Invoke-Shield rewrites that token, which would give
            # the two calls DIFFERENT keys and make this row pass no matter what the marker is keyed on.
            $rA = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $rB = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $k  = 'xrepo-' + $script:RunTag + '-' + [guid]::NewGuid().ToString('N')
            $body = "agy_shield `"$rA`" `".clavity/local-anomalies.md`" `"$k`"`n" +
                    "agy_shield `"$rB`" `".clavity/local-anomalies.md`" `"$k`""
            $res = Invoke-Shield -Root $rA -Body $body
            ([regex]::Matches($res.Err, 'git rm --cached')).Count | Should -Be 2 -Because 'two repositories are two separate leaks; a marker for one must never silence the other'
        }

        It 'distinguishes keys that differ ONLY IN THEIR TAIL - the whole key is load-bearing' {
            # CAPSTONE ROUND 2, Mechanism Gamer. The row above cannot catch a TRUNCATING implementation,
            # because its two keys ('k1-...' / 'k2-...') already differ in their SECOND character. MEASURED
            # with a mutant that truncates the key to five characters: all three debounce rows stayed
            # GREEN. That mutation also discards the run tag this suite now embeds in every key, silently
            # re-opening the cross-run marker collision the tag was added to close - so the suite would
            # have certified its own isolation mechanism while that mechanism was destroyed.
            # THE KEYS HERE SHARE A LONG PREFIX AND DIFFER ONLY AT THE END, which is the one shape that
            # forces the implementation to read the key to its last byte.
            $r = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $shared = 'tail-' + $script:RunTag + '-' + [guid]::NewGuid().ToString('N')
            $kA = $shared + '-AAAA'
            $kB = $shared + '-BBBB'
            $res = Invoke-Shield -Root $r -Body "agy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$kA`"`nagy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$kB`""
            ([regex]::Matches($res.Err, 'git rm --cached')).Count |
                Should -Be 2 -Because 'two keys identical for their first 40+ characters are still DIFFERENT sessions; an implementation that compares only a prefix debounces the second away and reports once'
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
            $k = 'vk-' + $script:RunTag + '-' + [guid]::NewGuid().ToString('N')
            $res = Invoke-Shield -Root $r -Body "agy_shield `"`$PWD`" `"docs/secret.md`" `"$k`"`nagy_shield `"`$PWD`" `"docs/secret.md`" `"$k`""
            ([regex]::Matches($res.Err, 'REFUSING')).Count | Should -Be 2 -Because 'a broken CALLER must not be silenced by a marker'
        }

        It 'a MALFORMED key disables DEBOUNCING - the fault is emitted every time' {
            # AGY-TEST-AUDIT 2026-08-30. The row below proves a malformed key still lets the guard FIRE.
            # It cannot prove the other half of that contract - that the malformed key is reset to empty so
            # debouncing is DISABLED - because it invokes the shield only ONCE, and one call cannot tell
            # "debouncing is off" from "this is the first call". MEASURED: deleting the `_as_key=''` reset
            # leaves that row GREEN.
            # THE KEY HERE IS MALFORMED BUT WRITABLE, and that is the whole trick. The sibling row uses
            # `../../escape`, which cannot discriminate: under the mutant the marker path traverses out of
            # .clavity/ and cannot be created, so the second call finds no marker and reports anyway -
            # the mutant would pass. `bad@key` is rejected by the validator (@ is outside [A-Za-z0-9._-])
            # yet forms a perfectly creatable filename, so under the mutant the first call DOES create the
            # marker and the second is silenced. Exactly one emission instead of two.
            # A TRACKED file drives Stage B3's persistent branch, which is the debounced class - a
            # `validation` fault would emit twice regardless and prove nothing.
            $r = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $body = @(
                'agy_shield "$PWD" ".clavity/local-anomalies.md" "bad@key"',
                'agy_shield "$PWD" ".clavity/local-anomalies.md" "bad@key"'
            ) -join "`n"
            $res = Invoke-Shield -Root $r -Body $body
            $hits = @([regex]::Matches($res.Err, 'git rm --cached')).Count
            $hits | Should -Be 2 -Because 'a malformed session id must disable debouncing, not merely survive it: both calls must report, or a bad id silently suppresses a data-leak notice from the second call onward'
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

        # THE $HOME/.clavity-tmp FALLBACK ROW WAS DELETED HERE (roadmap 17a), together with the
        # AGY-TEST-AUDIT round A header that introduced it - which opened "THE MARKER DIRECTORY IS RESOLVED
        # BY A LOOP ... AND ONLY ITS FIRST CANDIDATE WAS EVER EXERCISED". There is no loop any more: the
        # marker directory is the repository's own .clavity/, or nothing at all.
        # DELETED RATHER THAN REWRITTEN TO PASS. Keeping a row for deleted behaviour is how a suite starts
        # asserting a design nobody ships, and this project has already shrunk a suite 13 -> 9 on exactly
        # that reasoning.
        # WHAT REPLACED THE BEHAVIOUR IS PINNED ELSEWHERE: an unwritable .clavity/ means no debounce store
        # and a report on EVERY call, asserted by 'A1 mkdir FAILURE: returns 0, writes nothing, reports
        # ENVIRONMENT every time (no store, no debounce)'.
        # DO NOT REINTRODUCE A FALLBACK. A fallback to any shared directory would restore the
        # cross-repository collision this step removed - see 'reports the SAME fault in a SECOND repository
        # under the SAME key (roadmap 17a)'.

        # BRANCH 21 REWORK of the ordering row. It used to watch two points: every `grep` of Stage A2 and the
        # sweep's `find`. Stage A2 now reads the shield with ONE builtin `read` (no grep process to shim), and the
        # sweep's `find` runs only when a stale candidate exists (a builtin glob gate), so a fresh fixture never
        # reaches it. The HAZARD is unchanged - the sweep marker landing in a directory whose shield is not yet in
        # place - so the observation points moved, and each is still a direct question about the property:
        #   ROW 1 (marker-at-mktemp): `mktemp` is the first external process of the A2 prepend branch, which a
        #     shield holding only a negation takes. Asked at that instant "does the swept marker exist yet?" the
        #     answer must be ABSENT. It catches the sweep gate (or the whole sweep block) being hoisted above A2.
        #   ROW 2 (shield-at-find): with a stale temp planted the gate PASSES and `find` runs; asked at that instant
        #     "is the shield text in place?" the answer must be PRESENT. It catches the shield WRITE being deferred
        #     below the sweep and the sweep block being relocated above A2.
        # Both shims delegate with `command`, so the helper's behaviour is unchanged. The preconditions come FIRST:
        # a file that is absent would make the assertion about its contents vacuous.
        It 'the sweep marker does not exist yet when Stage A2 prepends (shield first, marker after)' {
            $r = New-FixtureRepo -Shield "!local-anomalies.md`n"
            $body = @(
                'mktemp() {',
                '  _m=$(command ls "$PWD"/.clavity/.clavity-shield-swept-* 2>/dev/null | command head -1)',
                '  if [ -n "$_m" ]; then echo PRESENT >> "$PWD/marker-at-mktemp.txt"',
                '  else echo ABSENT >> "$PWD/marker-at-mktemp.txt"; fi',
                '  command mktemp "$@"',
                '}',
                'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
            ) -join "`n"
            $null = Invoke-Shield -Root $r -Body $body
            $atMktemp = Join-Path $r 'marker-at-mktemp.txt'
            (Test-Path -LiteralPath $atMktemp) | Should -BeTrue -Because 'the negation shield must take the prepend branch (mktemp), or this checkpoint observes nothing'
            @(Get-Content -LiteralPath $atMktemp) | Should -Not -Contain 'PRESENT' -Because 'the sweep marker must not exist yet when Stage A2 begins; if it does, it was written into a directory that is not yet shielded'
        }

        It 'the sweep find runs only after the shield text is in place (a stale temp opens the gate)' {
            # No shield file, but .clavity/ exists and carries a planted stale temp: the glob gate PASSES, so `find` runs.
            $r = New-FixtureRepo
            [IO.File]::WriteAllText((Join-Path $r '.clavity/.gitignore.tmp.OLDOLD'), "stale`n")
            $body = @(
                'find() {',
                '  if command grep -qFx ''*'' "$PWD/.clavity/.gitignore" 2>/dev/null; then echo PRESENT > "$PWD/sweep-order.txt"',
                '  else echo ABSENT > "$PWD/sweep-order.txt"; fi',
                '  command find "$@"',
                '}',
                'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
            ) -join "`n"
            $null = Invoke-Shield -Root $r -Body $body
            $observed = Join-Path $r 'sweep-order.txt'
            (Test-Path -LiteralPath $observed) | Should -BeTrue -Because 'the planted stale temp must open the gate so the sweep find runs, or this row asserts nothing at all'
            (Get-Content -Raw -LiteralPath $observed).Trim() | Should -Be 'PRESENT' -Because 'Stage A2 must shield .clavity/ BEFORE the sweep runs, or a concurrent `git add -A` in that window stages this helper''s files'
        }

        It 'the prepending call defers the say-prune, and the NEXT call deletes the aged marker (not lost)' {
            # Branch 21 (owner-approved, agreed with agy): the one call that prepends skips the say-prune find, because it is
            # the run already nearest the process ceiling. DEFERRED, not lost: the next call latches the sweep and its find
            # covers the same '.clavity-shield-*' markers. Pinned from BOTH sides - survives the prepend, gone after the next.
            $r = New-FixtureRepo -Shield "!local-anomalies.md`n"
            $old = Join-Path $r '.clavity/.clavity-shield-persistent-oldkey'
            [IO.File]::WriteAllText($old, '')
            (Get-Item -LiteralPath $old).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-40)
            $call = 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
            $null = Invoke-Shield -Root $r -Body $call
            (Get-Shield $r) | Should -Match '(?m)^\*\r?$' -Because 'the first call must have PREPENDED, or this row does not measure the prepending call'
            (Test-Path -LiteralPath $old) | Should -BeTrue -Because 'the prepending call must not prune (deferred, to hold the run near the process ceiling)'
            $null = Invoke-Shield -Root $r -Body $call
            (Test-Path -LiteralPath $old) | Should -BeFalse -Because 'the next call latches the sweep and its find deletes the aged marker - deferred, not lost'
        }

        It 'the sweep age is 30 days at BOTH find sites: a 10-day-old marker survives, a 40-day-old one is deleted' {
            # Capstone R3 (mutant: `-mtime +30` -> `+7` at the say-prune find survived the suite). The first call runs the latch
            # sweep; once the latch exists a later call reaches the say-prune find instead. Each phase plants a 10-day marker (must
            # survive) and a 40-day marker (must go), so the age is pinned from both sides at whichever find that call used.
            $r = New-FixtureRepo -Shield "*`n"
            $call = 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
            # Phase 'first' goes through agy_shield (the latch sweep find); phase 'say' calls _agy_shield_say with a NEW key, the
            # branch that creates a marker and then prunes (the other find). The two finds are separate lines of the library.
            $bodies = @{ first = $call; say = '_agy_shield_say unshielded keysay "msg" "$PWD"' }
            foreach ($phase in 'first', 'say') {
                $mid = Join-Path $r ".clavity/.clavity-shield-persistent-mid-$phase"
                $old = Join-Path $r ".clavity/.clavity-shield-persistent-old-$phase"
                [IO.File]::WriteAllText($mid, ''); [IO.File]::WriteAllText($old, '')
                (Get-Item -LiteralPath $mid).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-10)
                (Get-Item -LiteralPath $old).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-40)
                $null = Invoke-Shield -Root $r -Body $bodies[$phase]
                (Test-Path -LiteralPath $old) | Should -BeFalse -Because "the 40-day marker must be swept in the '$phase' call, or the sweep never ran and this phase proves nothing"
                (Test-Path -LiteralPath $mid) | Should -BeTrue -Because "a 10-day marker is younger than the 30-day threshold (the '$phase' call)"
            }
        }

        It 'recognises a CRLF shield (a "*" line ending in CR) and leaves it byte-for-byte alone' {
            # Capstone R4 (mutant: drop the trailing-CR alternative of the "*" match - the suite stayed green). A shield written on
            # Windows with CRLF endings is still a correct shield; if the match misses the CR the helper appends a second "*".
            # TWO match sites: the bash builtin case and the grep fallback every other shell takes - so the row runs under both.
            # HONEST LIMIT (measured): MSYS grep ignores a trailing CR (`grep -qFx '*'` on a CRLF line exits 0 here), so on this host the
            # dash iteration cannot tell the grep fallback's CR alternative from its absence; on Linux grep exits 1 for that line and the
            # alternative is what matches (measured under WSL). The builtin-case alternative IS discriminating here (mutant red).
            foreach ($shell in '', 'dash') {
                $r = New-FixtureRepo -Shield "*`r`n"
                $path = Join-Path $r '.clavity/.gitignore'
                $before = [IO.File]::ReadAllBytes($path)
                $null = Invoke-Shield -Root $r -Shell $shell -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
                ([IO.File]::ReadAllBytes($path) -join ',') | Should -BeExactly ($before -join ',') -Because "a CRLF '*' is already a shield: nothing to append or rewrite (shell '$shell')"
            }
        }

        It 'a failed shield write OUTSIDE a git repository is reported, not swallowed' {
            # CAPSTONE ROUND 6, and it is the worst reachable state this helper had left. Round 3 made the
            # PREPEND fallback report a failed write; the ORDINARY append - the path a fresh clone takes -
            # still wrote with 2>/dev/null and checked nothing. Inside a repository Stage B catches that
            # and reports. OUTSIDE one it does not: B1 returns at its not-a-work-tree branch, which the
            # helper's own comment calls a NORMAL state for a skill shipping into non-repositories, so
            # that path had no backstop whatsoever.
            # MEASURED before the fix: a non-repository whose shield path could not be written produced NO
            # message of any kind and left .clavity/ unshielded. Silent and leaking is the exact failure
            # this file exists to prevent.
            # THE FIXTURE IS NOT A GIT REPOSITORY, deliberately - that is the whole point of the row, so it
            # does not use New-FixtureRepo.
            # THE SHIELD IS A READ-ONLY REGULAR FILE, NOT A DIRECTORY, and capstone round 7 is why. The
            # first version made it a directory, and the peer named the mutant that beat it: replace the
            # `printf` result check with `[ ! -f "$_as_shield" ]`. Against a directory that predicate is
            # FALSE, so the mutant still reports and the row stays GREEN - while a genuine write failure on
            # a REGULAR file would be swallowed silently, which is the case the row exists for. With a
            # regular read-only file the predicate is TRUE, the mutant does NOT report, and the row reds.
            # The fixture now discriminates the thing it claims to.
            $d = Join-Path ([IO.Path]::GetTempPath()) ("shieldnr-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path (Join-Path $d '.clavity') | Out-Null
            [void]$script:Fixtures.Add($d)
            $shieldPath = Join-Path $d '.clavity/.gitignore'
            [IO.File]::WriteAllText($shieldPath, "keep-me.txt`n")
            & attrib +R ($shieldPath -replace '/','\') 2>$null
            try   { $res = Invoke-Shield -Root $d -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"' }
            finally { & attrib -R ($shieldPath -replace '/','\') 2>$null }
            # CONTROL: the append must really have failed, or the branch under test was never reached.
            (Get-Content -Raw -LiteralPath $shieldPath) | Should -Not -Match '(?m)^\*$' -Because 'the fixture must make the write fail, or this row is testing nothing'
            # THE PRECONDITION: if this ever became a git repository the row would be testing Stage B's
            # backstop instead of the branch it names, and would pass for the wrong reason.
            (Test-Path -LiteralPath (Join-Path $d '.git')) | Should -BeFalse -Because 'this row exists to cover the path where Stage B returns early; a repository here would test something else'
            $res.Err | Should -Match 'is NOT protected' -Because 'a data-leak guard outside a work tree has no Stage B behind it, so silence there is the one failure nothing else can catch'
        }

        It 'a failed marker write leaks no OS diagnostic - only the helper speaks' {
            # CAPSTONE ROUND 6. The file's own rule (see its header) is that the helper's messages are the
            # ONLY thing it may print, and its own MEASURED note on redirect ordering says why that is easy
            # to get wrong: `: > "$f" 2>/dev/null` does NOT suppress a failure to OPEN "$f", because the
            # shell applies redirections left to right and attempts the open while stderr is still the
            # terminal. That measurement was applied to the sweep gate and to nowhere else, so four sibling
            # writes still leaked. MEASURED: forcing the debounce marker's creation to fail printed
            # "agy-shield-lib.sh: line NNN: ...: Is a directory" straight to the operator.
            # The fixture makes the MARKER PATH a directory, so `: > marker` fails while everything else
            # succeeds, and drives Stage B3 to reach the marker-creating branch.
            $r = New-FixtureRepo -Shield "!keep.md`n"
            [IO.File]::WriteAllText((Join-Path $r '.clavity/keep.md'), "x`n")
            $k = 'leak-' + $script:RunTag + '-' + [guid]::NewGuid().ToString('N')
            New-Item -ItemType Directory -Force -Path (Join-Path $r ".clavity/.clavity-shield-persistent-$k") | Out-Null
            $res = Invoke-Shield -Root $r -Body "agy_shield `"`$PWD`" `".clavity/keep.md`" `"$k`""
            # PRECONDITION: the helper must actually have spoken, or the assertion below is vacuous.
            $res.Err | Should -Match 'agy-shield:' -Because 'the row must reach a branch that reports, or it asserts nothing'
            # ASSERT THE CONTRACT POSITIVELY, NOT ONE SHAPE OF ITS VIOLATION - capstone round 7 attacked
            # the first version and won. That version pinned `agy-shield-lib\.sh: line \d+`, which is the
            # format BASH uses for a redirect it could not open. A diagnostic leaked by a SUBPROCESS looks
            # nothing like it - `cat: ...: Is a directory` carries no such prefix - so removing 2>/dev/null
            # from the `cat` would leak to the operator with this row still GREEN. The contract in the
            # file's header is "the helper's own messages are the only thing it may print", so the honest
            # assertion is that EVERY line is one of the helper's, whatever the alternative would look
            # like. A -Not against one known shape only ever guards that shape.
            $strayLines = @($res.Err -split "`r?`n" | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^agy-shield: ' })
            $strayLines | Should -HaveCount 0 -Because "only the helper may speak; these lines came from somewhere else: $($strayLines -join ' || ')"
            # ONE LEAK SITE THIS ROW CANNOT RED, and it is worth saying why rather than implying coverage.
            # Removing 2>/dev/null from the `cat "$_as_shield"` in the prepend branch leaves this row green.
            # MEASURED: the fixture DOES reach that cat - the shield carries a negation, so A2 takes the
            # mktemp path - but the cat SUCCEEDS, so the mutant has nothing to leak. It could only leak if
            # the shield were unreadable, and the `elif` above it already required `grep -q '^!'` to have
            # READ that same file. Reaching a failing cat therefore needs the shield to become unreadable
            # between the grep and the cat, which no fixture can arrange. The mutant survives because the
            # path it damages is unreachable, not because this assertion is weak - and the assertion above
            # is deliberately shaped as "every line is the helper's" so that it does guard every leak site
            # a fixture CAN reach, whatever form the stray output takes.
        }

        It 'when the fallback append ALSO fails it says the directory is NOT protected' {
            # CAPSTONE ROUND 3, and this one is the worst class of message this file can carry. The prepend
            # fallback wrote the star with 2>/dev/null and then asserted "The directory is protected"
            # unconditionally - a claim about a write it never looked at. MEASURED with a control proving
            # the append really can fail (shield read-only, mktemp forced to fail): the helper announced the
            # directory was protected while the shield still held only the negation line and check-ignore
            # reported the file NOT ignored. Stage B does tell the truth a few lines later, which makes it
            # worse rather than better - the REASSURING line comes first, and a reader who stops there stops
            # at the false one.
            # `mktemp` is forced to fail with a shell FUNCTION rather than a PATH shim, the same technique
            # the sweep-ordering row uses: the helper calls it unqualified, so a function intercepts it, and
            # nothing outside this body is affected.
            #
            # TWO STATED LIMITS, both raised by capstone round 4 and both left as limits deliberately.
            # (a) `attrib` is Windows-only, and so is this suite - it resolves Git Bash through
            #     Get-GitBashOrThrow and CI runs windows-latest. Somewhere the read-only attribute did not
            #     take, the append would SUCCEED, and the control below would fail: the row goes RED rather
            #     than passing on a branch it never reached. That is the safe direction, and it is why the
            #     control is first rather than an afterthought.
            # (b) A mutant that replaced the checked write with a PREDICATE - `if [ -w "$_as_shield" ]` -
            #     would keep this row green while misreporting a write that fails on a writable file, disk
            #     full being the obvious case. This harness cannot construct that: it can make a file
            #     unwritable, not a filesystem full. The compensation is that the shipped code tests the
            #     ACTUAL RESULT of the write, which is strictly stronger than any predicate about it, so
            #     that mutation is a deliberate weakening rather than a slip - and this comment is here so
            #     that anyone proposing it reads why it was rejected before they make it.
            $r = New-FixtureRepo -Shield "!keep.md`n"
            $shield = Join-Path $r '.clavity/.gitignore'
            & attrib +R ($shield -replace '/','\') 2>$null
            try {
                $body = @(
                    'mktemp() { return 1; }',
                    'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
                ) -join "`n"
                $res = Invoke-Shield -Root $r -Body $body
            }
            finally { & attrib -R ($shield -replace '/','\') 2>$null }
            # THE CONTROL FIRST. If the append actually SUCCEEDED, this fixture never reached the branch
            # under test and every assertion below would be vacuous - which is exactly how a row certifies
            # a behaviour it never exercised.
            (Get-Content -Raw -LiteralPath $shield) | Should -Not -Match '(?m)^\*$' -Because 'the fixture must make the append fail, or this row is testing nothing'
            $res.Err | Should -Match 'is NOT protected' -Because 'a data-leak guard must not report success for a write that failed'
            $res.Err | Should -Not -Match 'The directory is protected' -Because 'the reassuring wording is the defect; it must not appear when the append failed'
        }

        It 'the SWEEP prunes aged shield markers too - the healthy path is the only one that runs' {
            # WITHOUT THIS THE MARKERS GROW WITHOUT BOUND. The other prune lives in _agy_shield_say, on the
            # branch that CREATES a marker - and on a healthy repository _agy_shield_say is never called,
            # because Stage B returns at its "ignored" branch. So the sweep is the only prune that runs in
            # the common case, and before roadmap 17a it did not prune these at all: they lived in the OS
            # temp directory and the OS cleaned them.
            $r = New-FixtureRepo -Shield "*`n"
            $aged    = Join-Path $r '.clavity/.clavity-shield-persistent-ancient'
            $fresh   = Join-Path $r '.clavity/.clavity-shield-persistent-recent'
            $sibling = Join-Path $r '.clavity/.clavity-anomaly-ancient'
            foreach ($f in @($aged, $fresh, $sibling)) { [IO.File]::WriteAllText($f, "x`n") }
            foreach ($f in @($aged, $sibling)) { (Get-Item -LiteralPath $f -Force).LastWriteTime = (Get-Date).AddDays(-40) }
            $k = 'sweepprune-' + $script:RunTag + '-' + [guid]::NewGuid().ToString('N')
            $null = Invoke-Shield -Root $r -Body "agy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k`""
            (Test-Path -LiteralPath $aged)    | Should -BeFalse -Because 'an aged shield marker must be swept, or they accumulate one per session forever'
            (Test-Path -LiteralPath $fresh)   | Should -BeTrue  -Because 'a FRESH marker is a live debounce; sweeping it would re-arm every warning'
            (Test-Path -LiteralPath $sibling) | Should -BeTrue  -Because 'the sibling hooks own .clavity-anomaly-*; a broadened glob would delete their markers on our schedule'
        }

        It 'the marker sweep deletes ONLY its own aged markers - not fresh ones, not a sibling hook''s' {
            # agy-shield-lib.sh:79 prunes `.clavity-shield-*` at -mtime +30, on the run that CREATES a
            # marker. TWO controls, because the two plausible regressions fail in opposite directions:
            # dropping the `find` leaves the stale marker, and BROADENING the glob (the source comment at
            # :75-79 warns the siblings own `.clavity-anomaly-*` and `.clavity-assert-*`) eats files this
            # hook does not own. A row asserting only "the stale one is gone" catches the first and scores
            # the second as a pass.
            # SINCE ROADMAP 17a THE MARKERS LIVE IN THE REPOSITORY'S OWN .clavity/, so this row no longer
            # blocks TMPDIR and fakes a HOME to force a fallback candidate that no longer exists. WHAT it
            # asserts is unchanged - prune my own aged markers, spare fresh ones, spare a sibling's - only
            # WHERE the fixtures are planted moved. This row was not predicted to break by the plan that
            # made the change: two other rows named the marker path with the string 'clavity-shield-swept'
            # and were found by grepping for it, while this one spells it 'clavity-shield-persistent' and
            # builds its directory a different way. Grepping one spelling is not grepping the fact.
            $r = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $dir = Join-Path $r '.clavity'
            $stale   = Join-Path $dir '.clavity-shield-persistent-STALE'
            $fresh   = Join-Path $dir '.clavity-shield-persistent-FRESH'
            $foreign = Join-Path $dir '.clavity-anomaly-STALE'
            foreach ($f in @($stale, $fresh, $foreign)) { [IO.File]::WriteAllText($f, "x`n") }
            # -mtime +30 reads the modification time, so age the two that must LOOK stale.
            foreach ($f in @($stale, $foreign)) { (Get-Item -LiteralPath $f -Force).LastWriteTime = (Get-Date).AddDays(-40) }
            $k = 'sw-' + $script:RunTag + '-' + [guid]::NewGuid().ToString('N')
            $null = Invoke-Shield -Root $r -Body "agy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k`""
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

# Tests for the shipped marker writer, clavity-dotnet/plugin/hooks/agy-mark.sh.
#
# ANCHORED TO CWD, NOT git-toplevel. agy-seam-inject.sh:124 READS the marker at
# "$cwd_path/.clavity/agy-marks/<d>.head" and :118-122 forbids the git root by name. A toplevel writer
# against a cwd reader defeats the debounce in every launched-from-subdir session. The
# subdirectory row below is the pin for that pairing.

Describe 'agy-mark.sh' {
    BeforeAll {
        $script:Fixtures = New-Object System.Collections.ArrayList   # FIXTURE HYGIENE
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Mark = (Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-mark.sh') -replace '\\','/'
        Test-Path -LiteralPath $script:Mark | Should -BeTrue

        function New-MarkFixture {
            param([string]$Shield = "*`n")
            $d = Join-Path ([IO.Path]::GetTempPath()) ("markfx-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            [void]$script:Fixtures.Add($d)   # FIXTURE HYGIENE
            & git -C $d init -q; & git -C $d config user.email t@t.t; & git -C $d config user.name t
            & git -C $d config core.autocrlf false   # FIXTURE HYGIENE: never inherit the host's setting
            New-Item -ItemType Directory -Force -Path (Join-Path $d '.clavity') | Out-Null
            [IO.File]::WriteAllText((Join-Path $d '.clavity/.gitignore'), $Shield)
            [IO.File]::WriteAllText((Join-Path $d 'seed.txt'), "seed`n")
            & git -C $d add seed.txt; & git -C $d commit -q -m seed
            $d
        }
        function Invoke-Mark {
            param([string]$Cwd, [string[]]$MarkArgs, [string]$SessionId = '')
            $outF = Join-Path ([IO.Path]::GetTempPath()) ("mk-" + [guid]::NewGuid().ToString('N') + ".out")
            $errF = "$outF.err"
            $prev = $env:AGY_SESSION_ID; $env:AGY_SESSION_ID = $SessionId
            try {
                $p = Start-Process -FilePath 'bash' -ArgumentList (@($script:Mark) + $MarkArgs) -WorkingDirectory $Cwd `
                        -RedirectStandardOutput $outF -RedirectStandardError $errF -NoNewWindow -Wait -PassThru
                [pscustomobject]@{
                    ExitCode = $p.ExitCode
                    Err = (Get-Content -Raw -LiteralPath $errF -ErrorAction SilentlyContinue)
                }
            } finally {
                $env:AGY_SESSION_ID = $prev
                Remove-Item -LiteralPath $outF, $errF -Force -ErrorAction SilentlyContinue
            }
        }
    }

    AfterAll {
        # FIXTURE HYGIENE: -Force because a git repo carries read-only objects on Windows.
        foreach ($f in $script:Fixtures) { Remove-Item -LiteralPath $f -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Context 'head mode' {
        It 'writes the BARE sha and nothing else' {
            # docs/agy-disciplines-marker-contract.md:18 - "the commit sha from git rev-parse HEAD at
            # consult time, and nothing else". Touching the file and ignoring the argument would satisfy
            # a path-only contract, which is why the CONTENT is asserted here.
            $d = New-MarkFixture
            $sha = (& git -C $d rev-parse HEAD).Trim()
            $r = Invoke-Mark -Cwd $d -MarkArgs @('head','agy-first',$sha)
            $r.ExitCode | Should -Be 0
            (Get-Content -Raw -LiteralPath (Join-Path $d '.clavity/agy-marks/agy-first.head')).Trim() | Should -BeExactly $sha
        }

        It 'CREATES .clavity/agy-marks/ on a fresh clone' {
            # Stage A1 of the helper creates .clavity/ and NOTHING BELOW IT, and this batch removes the
            # skills' own mkdir instructions - so without this, head would fail on a fresh clone.
            # SCOPE NOTE: "fresh clone" here means .clavity/ EXISTS (Stage A1 made it) and agy-marks/
            # does not - which is why the fixture keeps .clavity and removes only the subdirectory. It
            # is NOT the state of a literally fresh clone, where .clavity is absent too; that case
            # belongs to the shield's own suite, and asserting it here would test another component's
            # contract through this one. The name is kept because the mutation table references it.
            $d = New-MarkFixture
            Remove-Item -LiteralPath (Join-Path $d '.clavity/agy-marks') -Recurse -Force -ErrorAction SilentlyContinue
            $sha = (& git -C $d rev-parse HEAD).Trim()
            (Invoke-Mark -Cwd $d -MarkArgs @('head','agy-first',$sha)).ExitCode | Should -Be 0
            (Test-Path -LiteralPath (Join-Path $d '.clavity/agy-marks/agy-first.head')) | Should -BeTrue
        }

        It 'ANCHORS TO CWD, matching agy-seam-inject.sh:124 - the subdirectory pin' {
            # THE ROW THAT CATCHES A TOPLEVEL ANCHOR. Run from a subdirectory: the marker must land in
            # THAT directory, because that is where the reader looks. A toplevel-anchored writer puts it
            # at the repo root, the reader never finds it, and the discipline re-fires forever.
            $d = New-MarkFixture
            $sub = Join-Path $d 'src/deep'
            New-Item -ItemType Directory -Force -Path $sub | Out-Null
            $sha = (& git -C $d rev-parse HEAD).Trim()
            (Invoke-Mark -Cwd $sub -MarkArgs @('head','agy-first',$sha)).ExitCode | Should -Be 0
            (Test-Path -LiteralPath (Join-Path $sub '.clavity/agy-marks/agy-first.head')) |
                Should -BeTrue -Because 'agy-seam-inject.sh:124 reads $cwd_path/.clavity/agy-marks/<d>.head'
            (Test-Path -LiteralPath (Join-Path $d '.clavity/agy-marks/agy-first.head')) |
                Should -BeFalse -Because 'a toplevel anchor would put it here and defeat the debounce'
        }
    }

    Context 'log mode' {
        It 'OWNS the line format - callers pass no preformatted line' {
            $d = New-MarkFixture
            $sha = (& git -C $d rev-parse HEAD).Trim()
            (Invoke-Mark -Cwd $d -MarkArgs @('log','agy-first','SKIPPED-UNREACHABLE',$sha)).ExitCode | Should -Be 0
            $line = (Get-Content -LiteralPath (Join-Path $d '.clavity/agy-marks/skipped.log') | Select-Object -Last 1)
            $line | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\s\sagy-first\s\sSKIPPED-UNREACHABLE\s\sHEAD='
        }

        It 'APPENDS - a second call does not destroy the first' {
            $d = New-MarkFixture
            $sha = (& git -C $d rev-parse HEAD).Trim()
            Invoke-Mark -Cwd $d -MarkArgs @('log','agy-first','SKIPPED-UNREACHABLE',$sha) | Out-Null
            Invoke-Mark -Cwd $d -MarkArgs @('log','agy-capstone','WAIVED',$sha,'breach') | Out-Null
            @(Get-Content -LiteralPath (Join-Path $d '.clavity/agy-marks/skipped.log')).Count | Should -Be 2
        }
    }

    Context 'prepare mode' {
        It 'creates and shields the PARENT of the named FILE' {
            # prepare takes the FILE path, not the directory: passing `seams` throws the filename away
            # and the helper's Stage B evaluates the DIRECTORY, never the file. check-ignore accepts
            # paths that do not exist yet, so passing the eventual file path costs nothing.
            $d = New-MarkFixture -Shield ''
            (Invoke-Mark -Cwd $d -MarkArgs @('prepare','seams/topic.md')).ExitCode | Should -Be 0
            (Test-Path -LiteralPath (Join-Path $d '.clavity/seams')) | Should -BeTrue
            (Get-Content -Raw -LiteralPath (Join-Path $d '.clavity/.gitignore')) | Should -Match '(?m)^\*$'
        }
    }

    Context 'argument validation - it CANNOT delegate this' {
        # The 4.1 helper returns 0 on a validation fault BY CONTRACT, so agy-mark.sh receives success
        # and would proceed to write. It must reject traversal itself, BEFORE calling the helper.
        It 'refuses a <discipline> containing a separator or ..' -ForEach @(
            @{ D = '../../escape' }, @{ D = 'a/b' }, @{ D = '..' }
        ) {
            $d = New-MarkFixture
            $r = Invoke-Mark -Cwd $d -MarkArgs @('head',$D,'deadbeef')
            $r.ExitCode | Should -Be 1
            @(Get-ChildItem -LiteralPath $d -Recurse -Filter '*.head' -ErrorAction SilentlyContinue).Count | Should -Be 0
        }

        It 'refuses a <relpath> containing .. or a leading /' -ForEach @(
            @{ P = '../escape.md' }, @{ P = '/abs/path.md' }, @{ P = 'seams/../../x.md' }
        ) {
            $d = New-MarkFixture
            $r = Invoke-Mark -Cwd $d -MarkArgs @('prepare',$P)
            $r.ExitCode | Should -Be 1
            # THE EXIT CODE ALONE IS NOT THE CONTRACT, and the note under Step 3 already claims this
            # row covers the rest: "_die_refuse runs BEFORE any mkdir or write, so nothing is created -
            # which is what those rows assert." It did not assert it. A regression that validated AFTER
            # `mkdir -p` would refuse with exit 1 having already created the directory, and this row
            # stayed green. The fixture starts with exactly one entry under `.clavity` (its shield), so
            # a recursive count of 1 is the whole "nothing was created" claim in one assertion.
            @(Get-ChildItem -LiteralPath (Join-Path $d '.clavity') -Force -Recurse).Count |
                Should -Be 1 -Because 'a refusal must create NOTHING; only the fixture shield may exist'
            @(Get-ChildItem -LiteralPath $d -Force).Count |
                Should -Be 3 -Because 'nothing may appear at the fixture root either (.git, .clavity, seed.txt)'
        }

        # A REFUSAL ROW ASSERTS THREE THINGS: the exit code, a message that NAMES the rejected
        # argument, and that NOTHING was created. The first two alone would pass on a script that
        # refused AFTER creating the wrong directory - which is the entire failure this refusal
        # exists to prevent, so the third assertion is the one carrying the contract.
        It 'refuses a relpath that names a DIRECTORY, names it, and creates nothing' {
            $d = New-MarkFixture
            $r = Invoke-Mark -Cwd $d -MarkArgs @('prepare','scratch/topic/')
            $r.ExitCode | Should -Be 1
            $r.Err | Should -Match 'must name a FILE'
            $r.Err | Should -Match 'scratch/topic/' -Because 'a validation failure names the argument it rejected'
            (Test-Path (Join-Path $d '.clavity/scratch')) | Should -BeFalse `
                -Because 'dirname would have created .clavity/scratch and NOT .clavity/scratch/topic - the documented trap'
        }
    }

    Context 'mode and argument refusals (panel R10 - each of these branches had no row)' {
        # BOTH ROWS BELOW ASSERTED ONLY THE EXIT CODE, and for a MODE error that is the weakest
        # possible oracle: exit 1 is what this script returns for every refusal, and also what it
        # would return if the helper failed to load, if git were missing, or if it crashed before
        # reaching the mode branch at all. The row would stay green while the mode check was deleted.
        # The message is what separates "rejected the mode" from "died on the way there", and the
        # expected-modes list is the distinguishing phrase.
        It 'refuses with NO mode given' {
            $d = New-MarkFixture
            $r = Invoke-Mark -Cwd $d -MarkArgs @()
            $r.ExitCode | Should -Be 1
            $r.Err | Should -Match 'no mode given' -Because 'exit 1 alone cannot tell a rejected mode from a crash on the way to the check'
            $r.Err | Should -Match ([regex]::Escape('head|log|prepare')) -Because 'the refusal tells the caller what the legal modes ARE'
            @(Get-ChildItem -LiteralPath (Join-Path $d '.clavity') -Force -Recurse).Count |
                Should -Be 1 -Because 'a refused invocation creates nothing; only the fixture shield may exist'
        }
        It 'refuses an UNKNOWN mode' {
            $d = New-MarkFixture
            $r = Invoke-Mark -Cwd $d -MarkArgs @('frobnicate','x')
            $r.ExitCode | Should -Be 1
            $r.Err | Should -Match 'unknown mode' -Because 'exit 1 alone cannot tell a rejected mode from a crash on the way to the check'
            $r.Err | Should -Match 'frobnicate' -Because 'a refusal names the ARGUMENT it rejected, so the caller can see its typo'
            @(Get-ChildItem -LiteralPath (Join-Path $d '.clavity') -Force -Recurse).Count |
                Should -Be 1 -Because 'a refused invocation creates nothing; only the fixture shield may exist'
        }
        It 'head refuses with NO sha' {
            $d = New-MarkFixture
            $r = Invoke-Mark -Cwd $d -MarkArgs @('head','agy-first')
            $r.ExitCode | Should -Be 1
            (Test-Path -LiteralPath (Join-Path $d '.clavity/agy-marks/agy-first.head')) | Should -BeFalse
        }
        It 'log refuses with NO status - and STILL emits the line it could not write' {
            # The payload obligation binds on EVERY refusal path, not only the ones inside the log branch.
            $d = New-MarkFixture
            $r = Invoke-Mark -Cwd $d -MarkArgs @('log','agy-first')
            $r.ExitCode | Should -Be 1
            $r.Err | Should -Match 'LOG LINE NOT WRITTEN'
            # And the file must NOT have been written. Message-only leaves this row green against a
            # script that complains and appends anyway (panel R13).
            (Test-Path -LiteralPath (Join-Path $d '.clavity/agy-marks/skipped.log')) | Should -BeFalse
        }
        It 'log refused BEFORE the helper loads still emits the line (panel R10)' {
            # THE ROW THAT CAUGHT THE IMPOSSIBLE TEST. The helper-load checks fire before `case $mode`,
            # so the previous version of this obligation was unreachable: _log_lost lived inside the log
            # branch and was never called. The line is now built before anything can refuse.
            $d = New-MarkFixture
            $isolated = Join-Path ([IO.Path]::GetTempPath()) ("iso3-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $isolated | Out-Null
            Copy-Item -LiteralPath ($script:Mark -replace '/','\') -Destination (Join-Path $isolated 'agy-mark.sh')
            $errF = Join-Path ([IO.Path]::GetTempPath()) ("iso3-" + [guid]::NewGuid().ToString('N') + ".err")
            $proc = Start-Process -FilePath 'bash' -ArgumentList @(((Join-Path $isolated 'agy-mark.sh') -replace '\\','/'), 'log','agy-first','SKIPPED-UNREACHABLE','deadbeef') `
                -WorkingDirectory $d -RedirectStandardOutput "$errF.out" -RedirectStandardError $errF -NoNewWindow -Wait -PassThru
            # ASSERT THE EXIT CODE, not only stderr. Panel R13: without -PassThru the code was
            # discarded entirely, so a script that printed the warning and then exited 0 kept this
            # row GREEN - and 'refused' versus 'wrote' is precisely what the caller must be able
            # to tell apart.
            $proc.ExitCode | Should -Not -Be 0 -Because 'a refused write must be non-zero, not merely noisy'
            $err = Get-Content -Raw -LiteralPath $errF
            $err | Should -Match 'LOG LINE NOT WRITTEN' -Because 'the record must survive a refusal that happens BEFORE the log branch is reached'
            $err | Should -Match 'SKIPPED-UNREACHABLE'
            Remove-Item -LiteralPath $errF, "$errF.out" -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $isolated -Recurse -Force -ErrorAction SilentlyContinue
        }
        It 'prepare refuses an EMPTY relpath AND creates nothing' {
            $d = New-MarkFixture -Shield ''
            $r = Invoke-Mark -Cwd $d -MarkArgs @('prepare','')
            $r.ExitCode | Should -Be 1
            # Exit-code-only would stay green against a script that ran a malformed mkdir and wrote a
            # broken shield before exiting 1 (panel R13).
            (Get-Content -Raw -LiteralPath (Join-Path $d '.clavity/.gitignore')) | Should -BeNullOrEmpty
            @(Get-ChildItem -LiteralPath (Join-Path $d '.clavity') -Directory -ErrorAction SilentlyContinue).Count | Should -Be 0
        }

        It 'a write the filesystem REJECTS exits 2, not 1 - the two codes mean different things' {
            # THE MUTATION TABLE PAIRED A MUTATION WITH THIS ROW AND THE ROW DID NOT EXIST - it said
            # "(add if absent)" and nobody added it, so that mutation mapped to nothing (panel R13).
            # Make agy-marks a FILE so the directory cannot be created but the refusal is not an
            # argument fault: the append itself is what fails.
            # THE FIXTURE MUST REACH THE *APPEND*, not the mkdir - panel R14 caught the first version
            # making .clavity/agy-marks a FILE, which makes `mkdir -p` fail first and exit 1, never
            # reaching the exit-2 branch at all. Worse, that version asserted `-BeIn @(1,2)`, which
            # silently ACCEPTED the mkdir failure as a pass - a row that cannot distinguish the two codes
            # is exactly what the contract says a caller must be able to do.
            # Making skipped.log a DIRECTORY lets mkdir succeed and makes the append itself fail.
            $d = New-MarkFixture
            New-Item -ItemType Directory -Force -Path (Join-Path $d '.clavity/agy-marks/skipped.log') | Out-Null
            $r = Invoke-Mark -Cwd $d -MarkArgs @('log','agy-first','SKIPPED-UNREACHABLE','deadbeef')
            # THE JUSTIFICATION HERE USED TO READ "wrote-something-and-failed", WHICH IS FALSE OF THIS VERY
            # FIXTURE. A directory target cannot be OPENED, and with `>>` the shell opens before the command
            # runs, so printf never executes and ZERO bytes land - measured. The row and the code were both
            # right; only the sentence explaining them was wrong. 2 means the write was ATTEMPTED and the
            # filesystem rejected it; 1 means refused before trying. The discriminator is WHO stopped it.
            $r.ExitCode | Should -Be 2 -Because 'an attempted-and-rejected write is exit 2, distinct from refused-before-trying (exit 1); this fixture writes zero bytes and is still a 2, which is exactly the point'
            $r.Err | Should -Match 'LOG LINE NOT WRITTEN' -Because 'the record must survive a rejected write too'
        }
    }

    Context 'exit codes and failure direction' {
        It 'exits 1 and writes NOTHING when the helper cannot be loaded' {
            $d = New-MarkFixture
            $isolated = Join-Path ([IO.Path]::GetTempPath()) ("iso-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $isolated | Out-Null
            Copy-Item -LiteralPath ($script:Mark -replace '/','\') -Destination (Join-Path $isolated 'agy-mark.sh')
            $outF = Join-Path ([IO.Path]::GetTempPath()) ("iso-" + [guid]::NewGuid().ToString('N') + ".out")
            $p = Start-Process -FilePath 'bash' -ArgumentList @(((Join-Path $isolated 'agy-mark.sh') -replace '\\','/'), 'head','agy-first','deadbeef') `
                    -WorkingDirectory $d -RedirectStandardOutput $outF -RedirectStandardError "$outF.err" -NoNewWindow -Wait -PassThru
            $p.ExitCode | Should -Be 1 -Because 'head fails CLOSED: an absent marker makes the discipline re-fire, which is safe'
            (Test-Path -LiteralPath (Join-Path $d '.clavity/agy-marks/agy-first.head')) | Should -BeFalse
            Remove-Item -LiteralPath $outF, "$outF.err" -Force -ErrorAction SilentlyContinue
        }

        It 'a REFUSED log emits BOTH the line it could not write AND the reason' {
            # skipped.log has NO re-fire path - it is a durable audit breadcrumb - so a refused write
            # destroys a record with nothing to recreate it. Emitting only the payload leaves the
            # operator holding a log line with no idea why it never reached disk.
            $d = New-MarkFixture
            $isolated = Join-Path ([IO.Path]::GetTempPath()) ("iso2-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $isolated | Out-Null
            Copy-Item -LiteralPath ($script:Mark -replace '/','\') -Destination (Join-Path $isolated 'agy-mark.sh')
            $errF = Join-Path ([IO.Path]::GetTempPath()) ("iso2-" + [guid]::NewGuid().ToString('N') + ".err")
            $proc = Start-Process -FilePath 'bash' -ArgumentList @(((Join-Path $isolated 'agy-mark.sh') -replace '\\','/'), 'log','agy-first','SKIPPED-UNREACHABLE','deadbeef') `
                -WorkingDirectory $d -RedirectStandardOutput "$errF.out" -RedirectStandardError $errF -NoNewWindow -Wait -PassThru
            # ASSERT THE EXIT CODE, not only stderr. Panel R13: without -PassThru the code was
            # discarded entirely, so a script that printed the warning and then exited 0 kept this
            # row GREEN - and 'refused' versus 'wrote' is precisely what the caller must be able
            # to tell apart.
            $proc.ExitCode | Should -Not -Be 0 -Because 'a refused write must be non-zero, not merely noisy'
            $err = Get-Content -Raw -LiteralPath $errF
            $err | Should -Match 'agy-first' -Because 'the line it could not write must be recoverable from stderr'
            $err | Should -Match 'SKIPPED-UNREACHABLE'
            $err | Should -Match '(?i)(helper|shield|could not|unable)' -Because 'the REASON is what the operator needs in order to fix it'
            Remove-Item -LiteralPath $errF, "$errF.out" -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'the shield is called on EVERY mode' {
        It 'restores a broken shield before writing' -ForEach @(
            @{ Mode = @('head','agy-first','deadbeefdeadbeefdeadbeefdeadbeefdeadbeef') },
            @{ Mode = @('log','agy-first','SKIPPED-UNREACHABLE','deadbeefdeadbeefdeadbeefdeadbeefdeadbeef') },
            @{ Mode = @('prepare','seams/topic.md') }
        ) {
            $d = New-MarkFixture -Shield ''
            Invoke-Mark -Cwd $d -MarkArgs $Mode | Out-Null
            (Get-Content -Raw -LiteralPath (Join-Path $d '.clavity/.gitignore')) | Should -Match '(?m)^\*$'
        }

        It 'FORWARDS $AGY_SESSION_ID to the helper' {
            # The hook's forwarding is pinned in Task 5; the WRAPPER's is a separate code path.
            $d = New-MarkFixture
            New-Item -ItemType Directory -Force -Path (Join-Path $d '.clavity/agy-marks') | Out-Null
            [IO.File]::WriteAllText((Join-Path $d '.clavity/agy-marks/agy-first.head'), '')
            & git -C $d add -f '.clavity/agy-marks/agy-first.head'
            & git -C $d commit -q -m 'track to create a PERSISTENT fault'
            $sid = 'ws-' + [guid]::NewGuid().ToString('N')
            $a = Invoke-Mark -Cwd $d -MarkArgs @('head','agy-first','deadbeef') -SessionId $sid
            $b = Invoke-Mark -Cwd $d -MarkArgs @('head','agy-first','deadbeef') -SessionId $sid
            ([regex]::Matches("$($a.Err)$($b.Err)", 'git rm --cached')).Count | Should -Be 1
            # THE ROW ABOVE PROVES TWO CALLS SHARE A KEY - NOT THAT THE KEY IS THE FORWARDED ONE.
            # Deleting the forwarding entirely and passing a hardcoded constant satisfies it perfectly,
            # because a constant is also "the same key twice". The debounce must therefore be shown to
            # BREAK when the session id changes: a DIFFERENT id has to emit the fault again. Without
            # this line the row certifies the mechanism while proving nothing about its data flow.
            $c = Invoke-Mark -Cwd $d -MarkArgs @('head','agy-first','deadbeef') `
                    -SessionId ('ws-' + [guid]::NewGuid().ToString('N'))
            ([regex]::Matches("$($c.Err)", 'git rm --cached')).Count |
                Should -Be 1 -Because 'a DIFFERENT session id must not be debounced - that is what proves the key is the forwarded value and not a constant'
        }
    }
}

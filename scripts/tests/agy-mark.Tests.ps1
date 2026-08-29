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

        # PIN GIT BASH - this suite was the last one in the family still launching bare `bash`, and it
        # is a FALSE RED waiting to happen. BashHookHelpers.ps1 documents why `Get-Command bash` is
        # NON-DETERMINISTIC: it depends on which parent process launched pwsh. MEASURED on this host
        # 2026-08-17: bare `bash` resolved to C:\WINDOWS\system32\bash.exe (the WSL stub), which cannot
        # run a Windows-path script - ALL 27 rows failed with exit 127 and `/bin/bash: ...: No such file
        # or directory`, saying nothing whatever about agy-mark.sh. Git Bash reports `/usr/bin/bash:`;
        # that prefix is the tell for telling the two apart in a failure message.
        # The sibling suites (agy-shield-lib, agy-discipline-reaching, ...) already route through this
        # helper for exactly this reason. Found by AGY-TEST-AUDIT round A - not by the peer, which read
        # the file statically, but by RUNNING the suite.
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $script:Bash = Get-GitBashOrThrow

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
                $p = Start-Process -FilePath $script:Bash -ArgumentList (@($script:Mark) + $MarkArgs) -WorkingDirectory $Cwd `
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
            $proc = Start-Process -FilePath $script:Bash -ArgumentList @(((Join-Path $isolated 'agy-mark.sh') -replace '\\','/'), 'log','agy-first','SKIPPED-UNREACHABLE','deadbeef') `
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
        It 'head REFUSES a sha that is not bare hex, and writes no marker' {
            # CAPSTONE ROUND 5, found only when the peer read the whole file instead of the diff.
            # docs/agy-disciplines-marker-contract.md:18 says the marker holds "the commit sha from
            # `git rev-parse HEAD` at consult time, and nothing else". The code wrote whatever it was
            # handed - MEASURED: a two-line argument produced a TWO-LINE marker and exit 0, so the file
            # silently stopped being what its contract says it is, and the hook that reads it would be
            # comparing a sha against two lines of something else.
            # THREE ASSERTIONS, because exit-code-only would stay green against a script that wrote a
            # broken marker and then exited 1 - the same reasoning as the other refusal rows here.
            # THE FIXTURE USES A NON-HEX SHA, NOT A MULTI-LINE ONE, AND THAT IS DELIBERATE. The defect was
            # measured with a two-line sha, but `Start-Process -ArgumentList` cannot deliver an embedded
            # newline at all - it splits the argument, which is measured and documented in the log row
            # below. A multi-line sha would therefore arrive here as its own tail and this row would pass
            # for a reason its own comment does not give. Both cases reach the SAME guard, so the row
            # asserts the one this harness can deliver honestly rather than staging the one it cannot.
            $d = New-MarkFixture
            $r = Invoke-Mark -Cwd $d -MarkArgs @('head','agy-capstone','not-a-sha')
            $r.ExitCode | Should -Be 1
            $r.Err | Should -Match 'sha must be hexadecimal' -Because 'the refusal must name the argument it rejected, not just fail'
            (Test-Path -LiteralPath (Join-Path $d '.clavity/agy-marks/agy-capstone.head')) | Should -BeFalse -Because 'a refused write must leave no marker; a partial one would attest to a discipline that never ran'
        }

        It 'a NEWLINE in the log text cannot forge a second record' {
            # CAPSTONE ROUND 3. This script OWNS the one-line record format - that is the stated reason the
            # format lives here instead of in the callers - but it interpolated caller-supplied text into
            # that format without enforcing "one line". The <finding> argument at the agy-capstone skill's
            # log call is DRIVER-SUPPLIED PROSE, so a newline in it is ordinary rather than hostile.
            # MEASURED before the fix: one call carrying a two-line finding wrote FOUR lines, one of them a
            # syntactically perfect WAIVED record. The ledger convention corrected in c5477ad decides
            # whether a capstone was waived in a range by looking for a WAIVED line whose HEAD falls inside
            # it, so a forged line here manufactures the false attestation the discipline exists to prevent.
            # ASSERT THE COUNT *AND* THE FORGERY, because they fail to different regressions: stripping only
            # \r would keep the count assertion honest but let a bare \n through, and stripping the text but
            # not the sha would leave the same hole one field over.
            # THE NEWLINE IS BUILT INSIDE BASH, AND IT HAS TO BE. The first version of this row passed the
            # multi-line text through Invoke-Mark, and a mutant that removed the strip left it GREEN.
            # MEASURED why, with a five-byte probe: `Start-Process -ArgumentList` does not deliver an
            # embedded newline at all - an argument "line1<LF>line2" arrives at the script as "line2", the
            # newline having split it. So the fixture could not deliver the input the row claims to test,
            # and it certified nothing. The real callers are skill snippets an agent runs in bash, where a
            # multi-line "$(...)" is ordinary, so the vector is real - only the driving had to change.
            $d = New-MarkFixture
            # NOT named $script: that is a PowerShell SCOPE PREFIX, and using it as a plain variable name
            # here collided with $script:Mark and produced a mangled path inside the generated snippet.
            # EVERY FIELD, NOT JUST THE TEXT - capstone round 4 attacked this row and won. Its first version
            # put the newline only in the text argument, so deleting the `_pl_status` strip left the row
            # GREEN while a status field could still forge a record. MEASURED: mutant applied, row passed.
            # A guard tested through one field certifies one field. The status and sha arguments now carry
            # a payload of their own, and the text carries the two-space separator as well as a newline.
            $markPath = $script:Mark
            $snippet = @(
                'txt=$(printf ''benign finding\n2026-08-29T00:00:00Z  agy-capstone  WAIVED  HEAD=abc123  forged'')',
                'st=$(printf ''UNVERIFIED-ACCEPTED\n2026-08-29T00:00:00Z  agy-capstone  WAIVED  HEAD=abc123  via-status'')',
                'sh=$(printf ''abc123\n2026-08-29T00:00:00Z  agy-capstone  WAIVED  HEAD=abc123  via-sha'')',
                ('bash "' + $markPath + '" log agy-capstone "$st" "$sh" "$txt"')
            ) -join "`n"
            $sf = Join-Path ([IO.Path]::GetTempPath()) ("mklog-" + [guid]::NewGuid().ToString('N') + ".sh")
            [IO.File]::WriteAllText($sf, ($snippet -replace "`r`n", "`n") + "`n")
            try {
                $p = Start-Process -FilePath $script:Bash -ArgumentList @(($sf -replace '\\', '/')) `
                        -WorkingDirectory $d -NoNewWindow -Wait -PassThru
                $p.ExitCode | Should -Be 0
            }
            finally { Remove-Item -LiteralPath $sf -Force -ErrorAction SilentlyContinue }
            $log = Join-Path $d '.clavity/agy-marks/skipped.log'
            $lines = @(Get-Content -LiteralPath $log)
            $lines | Should -HaveCount 1 -Because 'one log call must produce exactly one record, whatever the caller put in any field'
            # THE FIELD COUNT IS THE ORACLE, and it is a stronger one than the status text. The format is
            # five fields separated by two spaces, so a record whose caller-supplied values have been
            # flattened splits into EXACTLY five - no more. A separator smuggled into any field shows up
            # here as a sixth, and a newline shows up in the line count above. Between them the two
            # assertions cover both halves of "the caller cannot disturb the record format".
            # NOT asserting the status equals a literal: my earlier version did, then failed on its own
            # assertion, because the flattened value legitimately still CONTAINS the smuggled words. What
            # matters is that the caller's status STARTS the field and nothing has shifted the columns.
            $fields = $lines[0] -split '  '
            $fields | Should -HaveCount 5 -Because 'a separator smuggled into any field shifts every column after it, and a reader that scans for a status rather than indexing to it is then fooled inside one line'
            $fields[2] | Should -BeLike 'UNVERIFIED-ACCEPTED*' -Because 'the status field must begin with the status the caller actually passed'
            $fields[3] | Should -BeLike 'HEAD=*' -Because 'the sha field must still be where a reader expects it'
            (Get-Content -Raw -LiteralPath $log) | Should -Match 'benign finding' -Because 'the text is flattened, not discarded - an audit breadcrumb that drops its content is no breadcrumb'
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

        It 'a write the filesystem REJECTS fails, and its MESSAGE says the append was attempted' {
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
            $r.ExitCode | Should -Not -Be 0 -Because 'a rejected write must fail; roadmap 19 collapsed the tri-state, so the CODE no longer says WHICH failure this was'
            $r.Err | Should -Match 'LOG LINE NOT WRITTEN' -Because 'the record must survive a rejected write too'
            # THE MESSAGE IS NOW THE DISCRIMINATOR, and this assertion is what keeps roadmap 19 from costing
            # coverage. With one non-zero code the fixture-reaches-the-APPEND property can no longer be read
            # from $r.ExitCode - which is precisely the weakness panel R14 removed when it rejected an
            # earlier `-BeIn @(1,2)` for silently accepting the mkdir failure as a pass. _log_lost prints
            # its REASON, so this string separates the rejected append from the mkdir refusal at :136, which
            # prints "could not create .clavity/agy-marks". Asserting only the LOG LINE NOT WRITTEN prefix
            # would NOT discriminate: _die_refuse emits that same prefix at :59.
            $r.Err | Should -Match 'the filesystem rejected the append' -Because 'the fixture must reach the APPEND; a row that also passes on the mkdir refusal is the weakness panel R14 removed'
        }

        It 'a rejected HEAD write fails too - not just a rejected log write' {
            # THE EXIT-2 CONTRACT HAD EXACTLY ONE ROW AND IT TESTED `log` MODE ONLY (AGY-TEST-AUDIT
            # round A, GAP-7). `head` carries the same `|| { ...; exit 2; }` at agy-mark.sh:116, and
            # dropping it there lets a rejected marker write fall through to `exit 0` - a discipline
            # reporting success while its marker was never written, which is the one failure this exit
            # code exists to make visible. The two modes are separate code paths; one row cannot cover both.
            # SAME FIXTURE TECHNIQUE AS ABOVE, aimed one level deeper: making `.clavity/agy-marks` a file
            # would fail the `mkdir -p` at :114 and exit 1, never reaching the write. Making the TARGET
            # a directory lets mkdir succeed and makes the redirect itself fail - `>` cannot open a
            # directory, so printf never runs and zero bytes land, which is still a 2 by contract.
            $d = New-MarkFixture
            $target = Join-Path $d '.clavity/agy-marks/agy-first.head'
            New-Item -ItemType Directory -Force -Path $target | Out-Null
            $r = Invoke-Mark -Cwd $d -MarkArgs @('head','agy-first','0123456789abcdef0123456789abcdef01234567')
            # ROADMAP 19 collapsed the tri-state, so the code says only that it failed. The discrimination
            # lives in the message below - 'write FAILED' is emitted by this branch alone, and no
            # _die_refuse path produces it, so this row still tells a rejected write from a refusal.
            $r.ExitCode | Should -Not -Be 0 -Because 'a rejected write must fail; roadmap 19 collapsed the tri-state, so the CODE no longer says WHICH failure this was'
            $r.Err | Should -Match 'write FAILED' -Because 'a marker that silently did not land is the failure mode this branch exists to surface'
            # THIRD ASSERTION, because a refusal row that checks only code and message cannot tell
            # "rejected cleanly" from "rejected after mangling the target".
            (Test-Path -LiteralPath $target -PathType Container) | Should -BeTrue -Because 'the rejected write must leave the target exactly as it found it'
            @(Get-ChildItem -LiteralPath $target -Force).Count | Should -Be 0 -Because 'nothing may be created underneath a target the write could not open'
        }
    }

    Context 'exit codes and failure direction' {
        It 'exits 1 and writes NOTHING when the helper cannot be loaded' {
            $d = New-MarkFixture
            $isolated = Join-Path ([IO.Path]::GetTempPath()) ("iso-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $isolated | Out-Null
            Copy-Item -LiteralPath ($script:Mark -replace '/','\') -Destination (Join-Path $isolated 'agy-mark.sh')
            $outF = Join-Path ([IO.Path]::GetTempPath()) ("iso-" + [guid]::NewGuid().ToString('N') + ".out")
            $p = Start-Process -FilePath $script:Bash -ArgumentList @(((Join-Path $isolated 'agy-mark.sh') -replace '\\','/'), 'head','agy-first','deadbeef') `
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
            $proc = Start-Process -FilePath $script:Bash -ArgumentList @(((Join-Path $isolated 'agy-mark.sh') -replace '\\','/'), 'log','agy-first','SKIPPED-UNREACHABLE','deadbeef') `
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

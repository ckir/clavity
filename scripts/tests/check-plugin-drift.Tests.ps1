# Fixtures are a THROWAWAY git repo plus a fake install, both under $TestDrive. Nothing here reads the
# real installed plugin: CI has no install, and a row that silently skips when the install is absent is
# the exact fail-open this checker exists to close. The live check is a manual step in the plan, not a row.
BeforeAll {
    # FAIL LOUDLY IF THE SCRIPT IS ABSENT. Do not use `(Resolve-Path ...).Path` here: on a missing file
    # it raises a NON-TERMINATING error, so `$script:Script` is left unusable and any row that does not
    # happen to touch it still reports PASSED. MEASURED 2026-08-31 with a paired control - Resolve-Path
    # form: "Passed: 2, Failed: 0" on two rows that ignored the variable; this throw form: "Failed: 2".
    # A suite that cannot run must say so, not go green on the rows that were not looking.
    $script:Script = Join-Path $PSScriptRoot '..' 'check-plugin-drift.ps1'
    # -PathType Leaf: a directory of that name would otherwise satisfy the guard and the suite
    # would proceed to run a script that cannot execute. AGY-CAPSTONE round 7 sibling sweep.
    if (-not (Test-Path -LiteralPath $script:Script -PathType Leaf)) {
        throw "check-plugin-drift.ps1 not found at $script:Script - this suite cannot run"
    }

    function New-FixtureRepo {
        param([hashtable]$Files)
        $repo = Join-Path $TestDrive ("repo-" + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $repo -Force
        & git -C $repo init -q
        & git -C $repo config user.email 't@t.t'
        & git -C $repo config user.name  'T'
        & git -C $repo config core.autocrlf false
        foreach ($rel in $Files.Keys) {
            $p = Join-Path $repo ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            $null = New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force
            [IO.File]::WriteAllText($p, $Files[$rel])
        }
        & git -C $repo add -A
        & git -C $repo commit -q -m 'fixture'
        $sha = (& git -C $repo rev-parse HEAD).Trim()
        [pscustomobject]@{ Root = $repo; Sha = $sha }
    }

    function New-FixtureInstall {
        param([hashtable]$Files)
        $inst = Join-Path $TestDrive ("inst-" + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $inst -Force
        foreach ($rel in $Files.Keys) {
            $p = Join-Path $inst ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            $null = New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force
            [IO.File]::WriteAllText($p, $Files[$rel])
        }
        $inst
    }

    function Invoke-Drift {
        param($Repo, $Sha, $Install, [string]$PluginPath = 'plugin')
        $out = & pwsh -NoProfile -File $script:Script -RepoRoot $Repo -Sha $Sha `
                      -InstalledRoot $Install -PluginPath $PluginPath 2>&1 | Out-String
        [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
    }

    $script:Payload = @{
        'plugin/skills/a/SKILL.md' = "line one`nline two`n"
        'plugin/hooks/h.sh'        = "#!/usr/bin/env bash`necho hi`n"
        'plugin/plugin.json'       = "{`n  `"version`": `"0.7.0`"`n}`n"
    }
}

Describe 'check-plugin-drift.ps1' {

    It 'exits 0 when the install matches the declared sha exactly' {
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'skills/a/SKILL.md' = "line one`nline two`n"
            'hooks/h.sh'        = "#!/usr/bin/env bash`necho hi`n"
            'plugin.json'       = "{`n  `"version`": `"0.7.0`"`n}`n"
        }
        $res = Invoke-Drift $r.Root $r.Sha $i
        $res.Code | Should -Be 0 -Because "a matching install must pass; output was:`n$($res.Out)"
    }

    It 'exits 0 when the ONLY difference is CRLF vs LF' {
        # THE row that stops 3 false positives. MEASURED on the real install 2026-08-31: raw-byte
        # comparison reported 19 drifted files where normalized comparison reported 16. The installed
        # tree is a copy of a CRLF worktree; `git show` returns the committed LF form.
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'skills/a/SKILL.md' = "line one`r`nline two`r`n"
            'hooks/h.sh'        = "#!/usr/bin/env bash`r`necho hi`r`n"
            'plugin.json'       = "{`r`n  `"version`": `"0.7.0`"`r`n}`r`n"
        }
        $res = Invoke-Drift $r.Root $r.Sha $i
        $res.Code | Should -Be 0 -Because "line endings alone are not drift; output was:`n$($res.Out)"
    }

    It 'exits 1 and NAMES the file when content drifted' {
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'skills/a/SKILL.md' = "line one`nline TWO CHANGED`n"
            'hooks/h.sh'        = "#!/usr/bin/env bash`necho hi`n"
            'plugin.json'       = "{`n  `"version`": `"0.7.0`"`n}`n"
        }
        $res = Invoke-Drift $r.Root $r.Sha $i
        $res.Code | Should -Be 1
        # PAIRED AND CASE-SENSITIVE. MEASURED VACUOUS at AGY-CAPSTONE round 4: the failure summary
        # always prints "(N drifted, N missing, N extra, N unreadable, N identical)", and -Match is
        # case-INSENSITIVE, so `-Match 'DRIFTED'` was satisfied by the word "drifted" in that count
        # line. A mutant routing drifted files into the MISSING bucket passed this row 1/0. Pairing
        # the token WITH the path, case-sensitively, is what makes the category actually checked.
        $res.Out  | Should -CMatch 'DRIFTED\s+skills/a/SKILL\.md'
    }

    It 'exits 1 and NAMES the file when it is missing from the install' {
        # The real install is missing three hooks outright, so absence must be a first-class outcome
        # and not merely "nothing to compare".
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'skills/a/SKILL.md' = "line one`nline two`n"
            'plugin.json'       = "{`n  `"version`": `"0.7.0`"`n}`n"
        }
        $res = Invoke-Drift $r.Root $r.Sha $i
        $res.Code | Should -Be 1
        $res.Out  | Should -CMatch 'MISSING\s+hooks/h\.sh'
    }

    It 'exits 1 and NAMES the file when the install carries an extra file' {
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'skills/a/SKILL.md'      = "line one`nline two`n"
            'hooks/h.sh'             = "#!/usr/bin/env bash`necho hi`n"
            'plugin.json'            = "{`n  `"version`": `"0.7.0`"`n}`n"
            '.mcp.json.bak-2026-01-01' = "stale`n"
        }
        $res = Invoke-Drift $r.Root $r.Sha $i
        $res.Code | Should -Be 1
        $res.Out  | Should -CMatch 'EXTRA\s+\.mcp\.json\.bak-2026-01-01'
    }

    It 'reports UNREADABLE - not a crash - when an installed file is exclusively LOCKED' {
        # AGY-CAPSTONE round 3, MEASURED with a real FileShare::None lock: ReadAllBytes threw an unhandled
        # IOException, the run died mid-scan, and every file after it went unchecked while the exit code
        # still read as ordinary drift. An unreadable file is a first-class outcome, not a crash.
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'skills/a/SKILL.md' = "line one`nline two`n"
            'hooks/h.sh'        = "#!/usr/bin/env bash`necho hi`n"
            'plugin.json'       = "{`n  `"version`": `"0.7.0`"`n}`n"
        }
        $locked = Join-Path $i 'skills' 'a' 'SKILL.md'
        $fs = [IO.File]::Open($locked, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        try {
            # PRECONDITION - the fixture must actually apply, or this row proves nothing. AGY-TEST-AUDIT
            # 2026-09-02: this is `1913bdc`'s class, where a mutation silently failed to apply and only a
            # precondition assertion caught it. FileShare::None is a MANDATORY lock on Windows and an
            # advisory one on POSIX, so on a non-Windows host the read below would succeed, the checker
            # would report no drift, and the row would fail loudly rather than pass vacuously - but it
            # would fail for a reason nothing states. Assert the lock blocks a reader first, so the row
            # names its own environmental premise instead of assuming it.
            { [IO.File]::ReadAllBytes($locked) } | Should -Throw -Because 'the exclusive lock must actually block a reader, or UNREADABLE is not what is being tested'
            $res = Invoke-Drift $r.Root $r.Sha $i
            $res.Code | Should -Be 1
            $res.Out  | Should -CMatch 'UNREADABLE\s+skills/a/SKILL\.md'
            $res.Out  | Should -Not -Match 'being used by another process'
        } finally { $fs.Dispose() }
    }

    It 'counts a DIRECTORY standing where a payload file belongs as MISSING, not present' {
        # AGY-CAPSTONE round 3, hardening the same class the sibling checker was caught by in round 2:
        # a bare Test-Path is TRUE for a directory, so the file would have been treated as present and
        # then failed to read.
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'hooks/h.sh'  = "#!/usr/bin/env bash`necho hi`n"
            'plugin.json' = "{`n  `"version`": `"0.7.0`"`n}`n"
        }
        $null = New-Item -ItemType Directory -Path (Join-Path $i 'skills' 'a' 'SKILL.md') -Force
        $res = Invoke-Drift $r.Root $r.Sha $i
        $res.Code | Should -Be 1
        $res.Out  | Should -CMatch 'MISSING\s+skills/a/SKILL\.md'
        $res.Out  | Should -Not -Match 'UnauthorizedAccessException|Access to the path'
    }

    It 'tells the operator that an EXTRA file survives a reinstall' {
        # The remedy the report used to give could not clear an EXTRA file: the installer has no
        # [InstallDelete] and Inno `ignoreversion` overwrites without removing. MEASURED 2026-08-31 - a
        # stray backup survived a full reinstall and had to be deleted by hand. A guard that prints an
        # instruction which cannot work sends the reader round a loop that never terminates.
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'skills/a/SKILL.md'        = "line one`nline two`n"
            'hooks/h.sh'               = "#!/usr/bin/env bash`necho hi`n"
            'plugin.json'              = "{`n  `"version`": `"0.7.0`"`n}`n"
            '.mcp.json.bak-2026-01-01' = "stale`n"
        }
        $res = Invoke-Drift $r.Root $r.Sha $i
        $res.Code | Should -Be 1
        $res.Out  | Should -CMatch 'EXTRA\s+\.mcp\.json\.bak-2026-01-01'
        $res.Out  | Should -Match 'NOT removed by a reinstall'
    }

    It 'exits 2 - NOT 0 - when the declared sha does not exist' {
        # Fail-closed. A checker that cannot check must never report clean.
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{ 'plugin.json' = "{}`n" }
        $res = Invoke-Drift $r.Root '63eb46f0000000000000000000000000deadbeef' $i
        $res.Code | Should -Be 2 -Because "an unresolvable sha is 'cannot check', not 'clean'; output was:`n$($res.Out)"
        $res.Out  | Should -Match 'does not exist'
    }

    It 'exits 2 - NOT 0 - when the installed root is absent' {
        $r = New-FixtureRepo $script:Payload
        $res = Invoke-Drift $r.Root $r.Sha (Join-Path $TestDrive 'no-such-install')
        $res.Code | Should -Be 2 -Because "an absent install is 'cannot check', not 'clean'; output was:`n$($res.Out)"
        $res.Out  | Should -Match 'not installed|does not exist'
    }

    It 'exits 2 - NOT 1 - when the installed root is a FILE rather than a directory' {
        # AGY-CAPSTONE round 6. MEASURED: a file passed a bare Test-Path and the run reported all 30
        # payload files MISSING - it failed closed, but 30 wrong lines is a worse answer than one right
        # one, and "everything is missing" reads like a broken install rather than a bad argument.
        $r = New-FixtureRepo $script:Payload
        $f = Join-Path $TestDrive ("notadir-" + [Guid]::NewGuid().ToString('N') + ".txt")
        [IO.File]::WriteAllText($f, "x")
        $res = Invoke-Drift $r.Root $r.Sha $f
        $res.Code | Should -Be 2 -Because "a non-directory root is 'cannot check', not 'everything drifted'; output was:`n$($res.Out)"
        $res.Out  | Should -Match 'not a directory'
        $res.Out  | Should -Not -Match 'MISSING'
    }

    It 'sees a HIDDEN stray file, which Get-ChildItem skips without -Force' {
        # AGY-CAPSTONE round 8. MEASURED: the identical stray reported EXTRA when normal and produced
        # "OK - N payload file(s) identical", exit 0, once the Hidden attribute was set. EXTRA is the
        # one outcome a reinstall cannot fix, so a false clean there is the worst available answer.
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'skills/a/SKILL.md' = "line one`nline two`n"
            'hooks/h.sh'        = "#!/usr/bin/env bash`necho hi`n"
            'plugin.json'       = "{`n  `"version`": `"0.7.0`"`n}`n"
        }
        $stray = Join-Path $i '.hidden-stray.bak'
        [IO.File]::WriteAllText($stray, "stale`n")
        (Get-Item $stray).Attributes = 'Hidden'
        # PRECONDITION - assert the row's own premise, which is an ENVIRONMENT property, not a logic one.
        # AGY-TEST-AUDIT 2026-09-02, `1913bdc`'s class: the whole point of this row is that a plain
        # enumeration MISSES this file and only `-Force` finds it. On a filesystem that does not honour
        # the Hidden attribute the assignment above silently no-ops, `Get-ChildItem` sees the stray
        # anyway, EXTRA is reported for the ordinary reason, and the row goes green having tested
        # nothing about hidden files at all. Pin the premise before depending on it.
        (Get-ChildItem -LiteralPath $i -File | Where-Object Name -eq '.hidden-stray.bak') |
            Should -BeNullOrEmpty -Because 'a plain Get-ChildItem must MISS the stray, or this row is not testing the -Force blind spot it names'
        $res = Invoke-Drift $r.Root $r.Sha $i
        $res.Code | Should -Be 1 -Because "a hidden stray is still a stray; output was:`n$($res.Out)"
        $res.Out  | Should -CMatch 'EXTRA\s+\.hidden-stray\.bak'
    }

    It 'canonicalises the installed root, so a path with a .. segment does not crash' {
        # AGY-CAPSTONE round 8. MEASURED: $_.FullName is absolute and $InstalledRoot was used as a raw
        # string PREFIX, so a `..` segment threw "startIndex cannot be larger than length of string" and
        # exited 1 - the DRIFT code - having compared nothing at all.
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'skills/a/SKILL.md' = "line one`nline two`n"
            'hooks/h.sh'        = "#!/usr/bin/env bash`necho hi`n"
            'plugin.json'       = "{`n  `"version`": `"0.7.0`"`n}`n"
        }
        $leaf = Split-Path $i -Leaf
        $weird = Join-Path (Split-Path $i -Parent) ($leaf + '\..\' + $leaf)
        $res = Invoke-Drift $r.Root $r.Sha $weird
        $res.Code | Should -Be 0 -Because "the path denotes the same clean directory; output was:`n$($res.Out)"
        $res.Out  | Should -Not -Match 'startIndex cannot be larger'
    }

    It 'accepts an installed root addressed through a PSDrive' {
        # AGY-CAPSTONE round 9, and this is ROUND 8'S OWN FIX shipping its own edge - the ninth round
        # running that has happened. Round 8 added Resolve-Path to canonicalise the root and took
        # `.Path`, which is PROVIDER-QUALIFIED: for a PSDrive it returns 'Temp:\x', which is not a prefix
        # of the absolute $_.FullName and cannot be handed to [IO.File]. MEASURED on a CLEAN, IDENTICAL
        # install addressed as 'Temp:\...': EXTRA plus UNREADABLE, exit 1, and the report told the
        # operator to hand-delete a real payload file - strictly worse than the crash it replaced.
        #
        # The drive must be `Temp:`, NOT `TestDrive:`. Invoke-Drift spawns a CHILD pwsh, and TestDrive:
        # is defined by Pester inside THIS process only - measured, the child cannot resolve it and the
        # row failed for a reason that had nothing to do with the defect. Temp: is a PowerShell default
        # and exists in every session, which is also what makes the real-world case reachable.
        $r = New-FixtureRepo $script:Payload
        $leaf = "drive-" + [Guid]::NewGuid().ToString('N')
        $i = Join-Path $env:TEMP $leaf
        $null = New-Item -ItemType Directory -Path (Join-Path $i 'skills' 'a') -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $i 'hooks') -Force
        [IO.File]::WriteAllText((Join-Path $i 'skills' 'a' 'SKILL.md'), "line one`nline two`n")
        [IO.File]::WriteAllText((Join-Path $i 'hooks' 'h.sh'), "#!/usr/bin/env bash`necho hi`n")
        [IO.File]::WriteAllText((Join-Path $i 'plugin.json'), "{`n  `"version`": `"0.7.0`"`n}`n")
        try {
            $viaDrive = "Temp:\$leaf"
            $rp = Resolve-Path -LiteralPath $viaDrive
            $rp.Path | Should -Not -Be $rp.ProviderPath -Because 'this row only means something while .Path and .ProviderPath differ - if they ever stop differing it is proving nothing'

            $control = Invoke-Drift $r.Root $r.Sha $i
            $control.Code | Should -Be 0 -Because "the filesystem-path control must be clean first, or the attack proves nothing; output was:`n$($control.Out)"

            $res = Invoke-Drift $r.Root $r.Sha $viaDrive
            $res.Code | Should -Be 0 -Because "the SAME clean install addressed through a PSDrive must still be clean; output was:`n$($res.Out)"
            $res.Out  | Should -Not -Match 'EXTRA|UNREADABLE'
        } finally { Remove-Item $i -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 2 when no -InstalledRoot is given and LOCALAPPDATA is unset' {
        # AGY-CAPSTONE round 9. $env:LOCALAPPDATA is absent in a Windows service or scheduled-task
        # context, in some SSH sessions, and on every non-Windows host. MEASURED: Join-Path then failed
        # to bind and the run died with "Cannot bind argument to parameter 'Path'" instead of the
        # contracted 2 - an UNCONFIGURABLE ENVIRONMENT reading as a DRIFTED INSTALL.
        $out = & pwsh -NoProfile -c "`$env:LOCALAPPDATA=''; & '$script:Script' *>&1 | Out-String; exit `$LASTEXITCODE" 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 2 -Because "an unbuildable default path is 'cannot check', not drift; output was:`n$out"
        $out | Should -Match 'LOCALAPPDATA'
        $out | Should -Not -Match 'Cannot bind argument'
    }

    It 'resolves its own repository root under a path containing [ or ]' {
        # AGY-CAPSTONE round 10. `Resolve-Path <path>` binds the WILDCARD parameter set, and [ and ] are
        # legal Windows filename characters - so a clone under `repo[wip]` was treated as a GLOB.
        # MEASURED: it resolved to NOTHING, `.Path` on $null threw, and the run exited 1 (the drift
        # code); with a glob-matching sibling present it resolves to the WRONG DIRECTORY and the whole
        # report is computed against a repository the script is not in. Every other path call in the
        # file already used -LiteralPath.
        $brk = Join-Path $TestDrive ('repo[wip]-' + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path (Join-Path $brk 'scripts') -Force
        Copy-Item -LiteralPath $script:Script -Destination (Join-Path $brk 'scripts') -Force
        $probe = Join-Path $brk 'scripts' 'check-plugin-drift.ps1'
        # No -RepoRoot: the script must work out its own root from $PSScriptRoot, which is the code path
        # under test. It will then fail on the SHA (this fixture is not a git repo) - exit 2, not 1 -
        # and 2 is the proof, because the glob bug died at 1 before ever reaching the sha check.
        $out = & pwsh -NoProfile -File $probe 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 2 -Because "a bracketed path must reach the sha check (2), not die resolving its own root (1); output was:`n$out"
        $out | Should -Not -Match "property 'Path' cannot be found"
    }

    It 'accepts an installed root given as an 8.3 SHORT path' {
        # THE ONE CI FOUND AND TWELVE REVIEW ROUNDS DID NOT. Resolve-Path preserves an 8.3 short path
        # (`...\Temp\SHORTN~1`) while Get-ChildItem's .FullName returns the LONG form, so the raw prefix
        # arithmetic cut the wrong number of characters and a CLEAN install reported
        # `EXTRA 21b27fd7410b932d53a8017bd9c4/a.md` - a garbage relative path carrying the delete-by-hand
        # remedy. GitHub's windows-latest runner hands out 8.3 TEMP paths; this box does too, which is how
        # it was reproduced. The fix is that BOTH sides now come from the same API (Get-Item .FullName).
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'skills/a/SKILL.md' = "line one`nline two`n"
            'hooks/h.sh'        = "#!/usr/bin/env bash`necho hi`n"
            'plugin.json'       = "{`n  `"version`": `"0.7.0`"`n}`n"
        }
        # 8.3 generation can be disabled per volume. If it is, this row must SKIP VISIBLY rather than
        # pass without testing anything - a silent pass is the fail-open class this whole suite exists to
        # close.
        $short = $null
        try {
            $fso = New-Object -ComObject Scripting.FileSystemObject
            $short = $fso.GetFolder($i).ShortPath
        } catch { $short = $null }
        if (-not $short -or $short -eq $i) {
            Set-ItResult -Skipped -Because "8.3 short-name generation is not available for $i, so the divergence this row pins cannot be constructed here"
            return
        }
        $short.Length | Should -BeLessThan $i.Length -Because 'the fixture is only meaningful while the short and long forms differ'

        $control = Invoke-Drift $r.Root $r.Sha $i
        $control.Code | Should -Be 0 -Because "the long-path control must be clean first, or the attack proves nothing; output was:`n$($control.Out)"

        $res = Invoke-Drift $r.Root $r.Sha $short
        $res.Code | Should -Be 0 -Because "the SAME clean install addressed by its 8.3 short path must still be clean; output was:`n$($res.Out)"
        $res.Out  | Should -Not -Match 'EXTRA'
    }

    It 'reports a clean tree without printing any of the three defect tokens' {
        # Guards against a report that always prints its own vocabulary and so can never be read.
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'skills/a/SKILL.md' = "line one`nline two`n"
            'hooks/h.sh'        = "#!/usr/bin/env bash`necho hi`n"
            'plugin.json'       = "{`n  `"version`": `"0.7.0`"`n}`n"
        }
        $res = Invoke-Drift $r.Root $r.Sha $i
        # CASE-INSENSITIVE, AND THE POLARITY IS THE WHOLE REASON. Round 4 made this -CMatch "for the
        # same reason as the rows above" - that reasoning was WRONG and round 5 caught it. On a POSITIVE
        # assertion, case-sensitivity NARROWS what satisfies it, which is stronger. On a NEGATIVE one it
        # narrows what VIOLATES it, which is weaker: `-Not -CMatch 'DRIFTED'` is satisfied by output
        # containing "drifted". MEASURED - a mutant printing "0 drifted" on the clean path passed 1/0.
        # A negative assertion wants the WIDEST possible matcher.
        $res.Out | Should -Not -Match 'DRIFTED|MISSING|EXTRA|UNREADABLE'
    }
}

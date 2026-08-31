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
    if (-not (Test-Path -LiteralPath $script:Script)) {
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

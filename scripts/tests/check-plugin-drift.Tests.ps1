<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

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

    # Runs the script WITHOUT -InstalledRoot, in a child pwsh whose environment is set explicitly, so the ambient machine (a developer's real
    # ~/.claude, a CI runner's LOCALAPPDATA) can never decide a row. An empty value removes the variable.
    function Invoke-DriftDefault {
        param($Repo, $Sha, [hashtable]$Env, [string]$PluginPath = 'plugin')
        # The environment is set on THIS process around a plain `pwsh -File` call, exactly like Invoke-Drift, so a crash inside the script keeps
        # its real exit code. (A `pwsh -c '& script; exit $LASTEXITCODE'` wrapper turned a terminating error into exit 0: MEASURED while writing
        # these rows - the script threw "property 'Count' cannot be found" and the row saw 0.)
        $saved = @{}
        foreach ($k in $Env.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k) }
        try {
            foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $(if ($Env[$k]) { [string]$Env[$k] } else { $null })) }
            $out = & pwsh -NoProfile -File $script:Script -RepoRoot $Repo -Sha $Sha -PluginPath $PluginPath 2>&1 | Out-String
            $code = $LASTEXITCODE
        } finally {
            foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
        }
        [pscustomobject]@{ Out = $out; Code = $code }
    }

    # A Claude config dir holding plugins/installed_plugins.json. -Raw writes the text as given (for the invalid-JSON row).
    function New-ConfigDir {
        param($Entries, $Version = 2, [string]$Key = 'clavity@clavity', [string]$Raw)
        $cfg = Join-Path $TestDrive ("cfg-" + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path (Join-Path $cfg 'plugins') -Force
        $file = Join-Path $cfg 'plugins' 'installed_plugins.json'
        if ($PSBoundParameters.ContainsKey('Raw')) { [IO.File]::WriteAllText($file, $Raw) }
        elseif ($null -ne $Entries) {
            $doc = [ordered]@{ version = $Version; plugins = [ordered]@{ $Key = @($Entries) } }
            [IO.File]::WriteAllText($file, ($doc | ConvertTo-Json -Depth 8))
        }
        $cfg
    }

    function New-CleanInstall { New-FixtureInstall @{
        'skills/a/SKILL.md' = "line one`nline two`n"
        'hooks/h.sh'        = "#!/usr/bin/env bash`necho hi`n"
        'plugin.json'       = "{`n  `"version`": `"0.7.0`"`n}`n"
    } }

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
        $fs = $null
        try {
            $r = New-FixtureRepo $script:Payload
            $i = New-FixtureInstall @{
                'skills/a/SKILL.md' = "line one`nline two`n"
                'hooks/h.sh'        = "#!/usr/bin/env bash`necho hi`n"
                'plugin.json'       = "{`n  `"version`": `"0.7.0`"`n}`n"
            }
            $locked = Join-Path $i 'skills' 'a' 'SKILL.md'
            $fs = [IO.File]::Open($locked, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
            # PRECONDITION - the fixture must actually apply, or this row proves nothing. AGY-TEST-AUDIT
            # 2026-09-02: this is `1913bdc`'s class, where a mutation silently failed to apply and only a
            # precondition assertion caught it.
            #
            # NOTE - AN EARLIER VERSION OF THIS COMMENT ARGUED THAT `FileShare::None` IS MERELY ADVISORY ON
            # POSIX, so the read below would succeed on a non-Windows host. THAT CLAIM IS RETRACTED and
            # was refuted by measurement in this same commit range - see `docs/coverage-debt.md` entry O:
            # the LOCKED row PASSES on Linux, because .NET honours the share mode between .NET processes.
            # The retraction landed in the ledger and this comment was missed, leaving the repository
            # arguing both sides of a settled question. That is the incomplete-fold class: the FACT
            # changed, so every place stating the fact had to change with it.
            #
            # So the precondition is NOT about POSIX semantics. It is the narrower and more durable
            # point: assert the lock actually blocks a reader, so that if the premise ever stops holding
            # - on any host, for any reason - the row fails at this line naming the cause, instead of
            # passing while testing nothing.
            { [IO.File]::ReadAllBytes($locked) } | Should -Throw -Because 'the exclusive lock must actually block a reader, or UNREADABLE is not what is being tested'
            $res = Invoke-Drift $r.Root $r.Sha $i
            $res.Code | Should -Be 1
            $res.Out  | Should -CMatch 'UNREADABLE\s+skills/a/SKILL\.md'
            $res.Out  | Should -Not -Match 'being used by another process'
        } finally { if ($fs) { $fs.Dispose() } }
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
        # -Force AND -LiteralPath, both load-bearing, and NOT tidiness. MEASURED under WSL 2026-09-02:
        # this file's name starts with a dot, and on Linux a bare `Get-Item` CANNOT SEE a dot-file - it
        # raises an IOException, so `.Attributes` was being set on $null and the row died at
        # "The property 'Attributes' cannot be found on this object" before reaching a single
        # assertion. `ci-scripts.yml` runs this suite on windows-latest only, so CI never saw it; a
        # developer running the suite under WSL does. -Force is the whole fix, and the row is
        # MEANINGFUL on both platforms rather than merely surviving: measured on Linux, the dot prefix
        # already hides the file from a plain `Get-ChildItem` while `-Force` finds it, which is exactly
        # the blind spot this row pins - reached by a different mechanism than the Windows attribute.
        (Get-Item -LiteralPath $stray -Force).Attributes = 'Hidden'
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
        $i = Join-Path (Get-PSDrive -Name Temp).Root $leaf
        $null = New-Item -ItemType Directory -Path (Join-Path $i 'skills' 'a') -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $i 'hooks') -Force
        [IO.File]::WriteAllText((Join-Path $i 'skills' 'a' 'SKILL.md'), "line one`nline two`n")
        [IO.File]::WriteAllText((Join-Path $i 'hooks' 'h.sh'), "#!/usr/bin/env bash`necho hi`n")
        [IO.File]::WriteAllText((Join-Path $i 'plugin.json'), "{`n  `"version`": `"0.7.0`"`n}`n")
        try {
            $viaDrive = Join-Path 'Temp:' $leaf
            $rp = Resolve-Path -LiteralPath $viaDrive
            $rp.Path | Should -Not -Be $rp.ProviderPath -Because 'this row only means something while .Path and .ProviderPath differ - if they ever stop differing it is proving nothing'

            $control = Invoke-Drift $r.Root $r.Sha $i
            $control.Code | Should -Be 0 -Because "the filesystem-path control must be clean first, or the attack proves nothing; output was:`n$($control.Out)"

            $res = Invoke-Drift $r.Root $r.Sha $viaDrive
            $res.Code | Should -Be 0 -Because "the SAME clean install addressed through a PSDrive must still be clean; output was:`n$($res.Out)"
            $res.Out  | Should -Not -Match 'EXTRA|UNREADABLE'
        } finally { Remove-Item $i -Recurse -Force -ErrorAction SilentlyContinue }
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
        if (-not $IsWindows) { Set-ItResult -Skipped -Because 'APPROVED:WindowsOnly: 8.3 short names are a Windows filesystem feature'; return }
        $short = $null
        try {
            $fso = New-Object -ComObject Scripting.FileSystemObject
            $short = $fso.GetFolder($i).ShortPath
        } catch { $short = $null }
        if (-not $short -or $short -eq $i) {
            Set-ItResult -Skipped -Because "APPROVED:FsFeature:8dot3-names: 8.3 short-name generation is not available for $i, so the divergence this row pins cannot be constructed here"
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

Describe 'check-plugin-drift.ps1 - locating the install without -InstalledRoot' {
    # AGY-FIRST 2026-11-06 (two rounds). On Linux/macOS there is no Inno install under LOCALAPPDATA; the installed copy is the directory the
    # Claude plugin manifest names. Resolution order: -InstalledRoot, CLAVITY_INSTALLED_ROOT, LOCALAPPDATA (Windows, unchanged), the manifest.
    # Every row isolates the environment: CLAUDE_CONFIG_DIR points at a fixture, LOCALAPPDATA and CLAVITY_INSTALLED_ROOT are removed unless
    # the row is about them, so these rows pass the same way on a Windows runner and on a developer's Linux box.

    BeforeEach {
        $script:Repo = New-FixtureRepo $script:Payload
        $script:Good = New-CleanInstall
        function script:Env([string]$Cfg, [hashtable]$More = @{}) { $h = @{ CLAUDE_CONFIG_DIR = $Cfg; LOCALAPPDATA = ''; CLAVITY_INSTALLED_ROOT = '' }; foreach ($k in $More.Keys) { $h[$k] = $More[$k] }; $h }
        function script:Run([string]$Cfg, [hashtable]$More = @{}) { Invoke-DriftDefault $script:Repo.Root $script:Repo.Sha (script:Env $Cfg $More) }
        function script:Entry([string]$Scope, [string]$Install, [string]$Project) {
            $e = [ordered]@{ scope = $Scope; installPath = $Install; version = '0.15.0' }
            if ($Project) { $e['projectPath'] = $Project }
            $e
        }
    }

    It 'uses the single user entry and reports which manifest and path it chose' {
        $r = script:Run (New-ConfigDir @(script:Entry 'user' $script:Good))
        $r.Code | Should -Be 0 -Because $r.Out
        $r.Out  | Should -Match 'install located through' -Because 'the operator must be able to see which install was checked'
        $r.Out  | Should -Match ([regex]::Escape($script:Good))
    }

    It 'exits 2, naming the manifest, when the manifest does not exist (the case the old LOCALAPPDATA row pinned)' {
        $r = script:Run (Join-Path $TestDrive 'no-such-config')
        $r.Code | Should -Be 2 -Because $r.Out
        $r.Out  | Should -Match 'installed_plugins\.json'
        $r.Out  | Should -Match 'does not exist'
        $r.Out  | Should -Not -Match 'Cannot bind argument' -Because 'an unconfigurable environment must be the contracted 2, never a binder crash (AGY-CAPSTONE round 9)'
    }

    It 'exits 2 on a manifest that is not valid JSON' {
        $r = script:Run (New-ConfigDir -Raw '{ not json')
        $r.Code | Should -Be 2 -Because $r.Out
        $r.Out  | Should -Match 'not valid JSON'
    }

    It 'exits 2 on a manifest that is not schema version 2' {
        $r = script:Run (New-ConfigDir @(script:Entry 'user' $script:Good) -Version 1)
        $r.Code | Should -Be 2 -Because $r.Out
        $r.Out  | Should -Match 'schema version 2'
    }

    It 'exits 2 when the manifest has no clavity@clavity entry (another plugin must not be mistaken for it)' {
        $r = script:Run (New-ConfigDir @(script:Entry 'user' $script:Good) -Key 'other@market')
        $r.Code | Should -Be 2 -Because $r.Out
        $r.Out  | Should -Match "no 'clavity@clavity' entry"
    }

    It 'discards an entry for ANOTHER checkout and uses the user entry (the foreign local install must not break this repo)' {
        $other = Join-Path $TestDrive 'some-other-checkout'
        $r = script:Run (New-ConfigDir @((script:Entry 'local' $script:Good $other), (script:Entry 'user' $script:Good)))
        $r.Code | Should -Be 0 -Because $r.Out
    }

    It 'exits 2 when the only entry belongs to another checkout' {
        $other = Join-Path $TestDrive 'some-other-checkout'
        $r = script:Run (New-ConfigDir @(script:Entry 'local' $script:Good $other))
        $r.Code | Should -Be 2 -Because $r.Out
        $r.Out  | Should -Match 'only for other checkouts'
    }

    It 'uses a local entry whose projectPath is THIS checkout, with or without a trailing separator' {
        foreach ($proj in $script:Repo.Root, ($script:Repo.Root + [IO.Path]::DirectorySeparatorChar)) {
            $r = script:Run (New-ConfigDir @(script:Entry 'local' $script:Good $proj))
            $r.Code | Should -Be 0 -Because "projectPath '$proj'; output was:`n$($r.Out)"
        }
    }

    It 'exits 2 and lists BOTH entries when a user entry and a local entry for this checkout both apply (it will not guess which one Claude loads)' {
        $localInstall = New-CleanInstall
        $r = script:Run (New-ConfigDir @((script:Entry 'user' $script:Good), (script:Entry 'local' $localInstall $script:Repo.Root)))
        $r.Code | Should -Be 2 -Because $r.Out
        $r.Out  | Should -Match 'will not guess'
        $r.Out  | Should -Match 'scope=user'
        $r.Out  | Should -Match 'scope=local'
    }

    It 'exits 2 on two user entries' {
        $r = script:Run (New-ConfigDir @((script:Entry 'user' $script:Good), (script:Entry 'user' (New-CleanInstall))))
        $r.Code | Should -Be 2 -Because $r.Out
        $r.Out  | Should -Match 'will not guess'
    }

    It 'exits 2 on a RELATIVE installPath (it would resolve against whatever directory the operator is in)' {
        $r = script:Run (New-ConfigDir @(script:Entry 'user' 'plugins/cache/clavity'))
        $r.Code | Should -Be 2 -Because $r.Out
        $r.Out  | Should -Match 'not an absolute path'
    }

    It 'exits 2 when the chosen installPath is not a directory' {
        $r = script:Run (New-ConfigDir @(script:Entry 'user' (Join-Path $TestDrive 'gone')))
        $r.Code | Should -Be 2 -Because $r.Out
        $r.Out  | Should -Match 'is not a directory'
    }

    It 'exits 2 on an unknown scope and on a local entry with no projectPath' {
        $r = script:Run (New-ConfigDir @(script:Entry 'galaxy' $script:Good))
        $r.Code | Should -Be 2 -Because $r.Out
        $r.Out  | Should -Match "unknown scope 'galaxy'"
        $r = script:Run (New-ConfigDir @(script:Entry 'local' $script:Good))
        $r.Code | Should -Be 2 -Because $r.Out
        $r.Out  | Should -Match "no 'projectPath'"
    }

    It 'prefers CLAVITY_INSTALLED_ROOT over the manifest' {
        $drifted = New-FixtureInstall @{ 'skills/a/SKILL.md' = "CHANGED`n"; 'hooks/h.sh' = "x`n"; 'plugin.json' = "{}`n" }
        $r = script:Run (New-ConfigDir @(script:Entry 'user' $drifted)) @{ CLAVITY_INSTALLED_ROOT = $script:Good }
        $r.Code | Should -Be 0 -Because "the env override must win; output was:`n$($r.Out)"
    }

    It 'keeps the Windows path first: LOCALAPPDATA wins over the manifest, byte for byte as before' {
        $lad = Join-Path $TestDrive ('lad-' + [Guid]::NewGuid().ToString('N'))
        $target = Join-Path $lad 'Programs' 'clavity-dotnet' 'plugins' 'clavity'
        $null = New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force
        Copy-Item -LiteralPath $script:Good -Destination $target -Recurse
        $drifted = New-FixtureInstall @{ 'skills/a/SKILL.md' = "CHANGED`n"; 'hooks/h.sh' = "x`n"; 'plugin.json' = "{}`n" }
        $r = script:Run (New-ConfigDir @(script:Entry 'user' $drifted)) @{ LOCALAPPDATA = $lad }
        $r.Code | Should -Be 0 -Because "LOCALAPPDATA must still select the installer's copy; output was:`n$($r.Out)"
        $r.Out  | Should -Not -Match 'install located through' -Because 'the manifest must not even be read when LOCALAPPDATA is set'
    }
}

Describe 'check-plugin-drift.ps1 - the .in_use runtime directory' {
    # MEASURED 2026-11-06 on a Linux box with Claude running: the real install was byte-identical to the repo payload except for
    # .in_use/<pid>, a live-session marker, which made the check exit 1 (EXTRA). Owner ruling: a ROOT-LEVEL .in_use/ is exempt, and only that.

    It 'is not reported as EXTRA, so an otherwise clean install exits 0' {
        $r = New-FixtureRepo $script:Payload
        $i = New-CleanInstall
        $null = New-Item -ItemType Directory -Path (Join-Path $i '.in_use') -Force
        [IO.File]::WriteAllText((Join-Path $i '.in_use' '282068'), '')
        $res = Invoke-Drift $r.Root $r.Sha $i
        $res.Code | Should -Be 0 -Because "a live-session marker is runtime state, not payload; output was:`n$($res.Out)"
    }

    It 'does not hide a stray file BESIDE it, nor one inside a lookalike directory' {
        $r = New-FixtureRepo $script:Payload
        $i = New-CleanInstall
        $null = New-Item -ItemType Directory -Path (Join-Path $i '.in_use') -Force
        [IO.File]::WriteAllText((Join-Path $i '.in_use' '282068'), '')
        [IO.File]::WriteAllText((Join-Path $i 'stray.md'), "x`n")
        $null = New-Item -ItemType Directory -Path (Join-Path $i '.in_use-x') -Force
        [IO.File]::WriteAllText((Join-Path $i '.in_use-x' '1'), "x`n")
        $res = Invoke-Drift $r.Root $r.Sha $i
        $res.Code | Should -Be 1 -Because $res.Out
        $res.Out  | Should -MatchExactly 'EXTRA\s+stray\.md'
        $res.Out  | Should -MatchExactly 'EXTRA\s+\.in_use-x/1'
        $res.Out  | Should -Not -MatchExactly 'EXTRA\s+\.in_use/'
    }

    It 'is not exempt when the repo payload itself carries a file there (the exemption never hides payload)' {
        $files = $script:Payload.Clone(); $files['plugin/.in_use/keep'] = "payload`n"
        $r = New-FixtureRepo $files
        $i = New-CleanInstall   # lacks .in_use/keep
        $res = Invoke-Drift $r.Root $r.Sha $i
        $res.Code | Should -Be 1 -Because "a payload file under .in_use/ that is missing must still be MISSING; output was:`n$($res.Out)"
        $res.Out  | Should -MatchExactly 'MISSING\s+\.in_use/keep'
    }
}

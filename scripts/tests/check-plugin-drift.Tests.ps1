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
        $res.Out  | Should -Match 'DRIFTED'
        $res.Out  | Should -Match 'skills/a/SKILL\.md'
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
        $res.Out  | Should -Match 'MISSING'
        $res.Out  | Should -Match 'hooks/h\.sh'
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
        $res.Out  | Should -Match 'EXTRA'
        $res.Out  | Should -Match 'bak-2026-01-01'
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

    It 'reports a clean tree without printing any of the three defect tokens' {
        # Guards against a report that always prints its own vocabulary and so can never be read.
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'skills/a/SKILL.md' = "line one`nline two`n"
            'hooks/h.sh'        = "#!/usr/bin/env bash`necho hi`n"
            'plugin.json'       = "{`n  `"version`": `"0.7.0`"`n}`n"
        }
        $res = Invoke-Drift $r.Root $r.Sha $i
        $res.Out | Should -Not -Match 'DRIFTED|MISSING|EXTRA'
    }
}

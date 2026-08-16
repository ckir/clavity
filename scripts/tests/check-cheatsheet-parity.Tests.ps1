# Tests for scripts/check-cheatsheet-parity.ps1 - the 14e pre-commit gate.
#
# EVERY ROW BUILDS A COMPLETE THROWAWAY REPO carrying copies of the three real files plus the two real
# scripts, because this hook's whole contract is about INDEX state and only a real index can express it.

Describe 'check-cheatsheet-parity.ps1' {
    BeforeAll {
        $script:Fixtures = New-Object System.Collections.ArrayList   # FIXTURE HYGIENE
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Core = 'agy-autotrain/knowledge/driver-cheatsheet.core.md'
        $script:Rs   = 'clavity-classic/src/driver_cheatsheet.rs'
        $script:Cs   = 'clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs'

        # Build a repo whose three pinned paths are committed and self-consistent, with both scripts in
        # place. Returns the repo root.
        function New-ParityRepo {
            $d = Join-Path ([IO.Path]::GetTempPath()) ("parityfx-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            [void]$script:Fixtures.Add($d)
            & git -C $d init -q
            & git -C $d config user.email t@t.t
            & git -C $d config user.name t
            & git -C $d config core.autocrlf false
            foreach ($rel in @($script:Core, $script:Rs, $script:Cs)) {
                $dst = Join-Path $d $rel
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
                Copy-Item -LiteralPath (Join-Path $script:RepoRoot $rel) -Destination $dst
            }
            New-Item -ItemType Directory -Force -Path (Join-Path $d 'scripts') | Out-Null
            foreach ($s in @('check-cheatsheet-parity.ps1', 'generate-cheatsheet-literals.ps1')) {
                Copy-Item -LiteralPath (Join-Path $script:RepoRoot "scripts/$s") -Destination (Join-Path $d "scripts/$s")
            }
            & git -C $d add -A
            & git -C $d commit -q -m seed
            $d
        }

        # Run the hook IN a fixture repo and return its exit code plus merged output.
        function Invoke-Parity {
            param([string]$Repo)
            $outF = Join-Path ([IO.Path]::GetTempPath()) ("par-" + [guid]::NewGuid().ToString('N') + ".out")
            [void]$script:Fixtures.Add($outF)
            $p = Start-Process -FilePath 'pwsh' `
                    -ArgumentList @('-NoProfile','-File', (Join-Path $Repo 'scripts/check-cheatsheet-parity.ps1')) `
                    -WorkingDirectory $Repo -RedirectStandardOutput $outF -RedirectStandardError "$outF.err" `
                    -NoNewWindow -Wait -PassThru
            [void]$script:Fixtures.Add("$outF.err")
            [pscustomobject]@{
                ExitCode = $p.ExitCode
                Text     = ((Get-Content -Raw -LiteralPath $outF -ErrorAction SilentlyContinue) +
                            (Get-Content -Raw -LiteralPath "$outF.err" -ErrorAction SilentlyContinue))
            }
        }

        function Set-CoreText { param([string]$Repo, [string]$Text) [IO.File]::WriteAllText((Join-Path $Repo $script:Core), $Text) }
        function Invoke-Gen   { param([string]$Repo) & pwsh -NoProfile -File (Join-Path $Repo 'scripts/generate-cheatsheet-literals.ps1') `
                                  -CoreSource (Join-Path $Repo $script:Core) -RustTarget (Join-Path $Repo $script:Rs) -CsTarget (Join-Path $Repo $script:Cs) *> $null }
    }

    AfterAll {
        foreach ($f in $script:Fixtures) { Remove-Item -LiteralPath $f -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'row 2 - core.md staged with correct literals: PASSES (the correct workflow is not blocked)' {
        $d = New-ParityRepo
        Set-CoreText $d ((Get-Content -Raw -LiteralPath (Join-Path $d $script:Core)) + "`nAn added line.`n")
        Invoke-Gen $d
        & git -C $d add -- $script:Core $script:Rs $script:Cs
        (Invoke-Parity $d).ExitCode | Should -Be 0
    }

    It 'row 3 - staged complete, THEN further unstaged edits to core.md: PASSES (the index-read proof)' {
        # THE END-TO-END PROOF that the hook reads the INDEX. A hook reading the WORKTREE generates from
        # the edited text, does not match the staged literals, and FAILS. Mutation control below.
        $d = New-ParityRepo
        Set-CoreText $d ((Get-Content -Raw -LiteralPath (Join-Path $d $script:Core)) + "`nStaged line.`n")
        Invoke-Gen $d
        & git -C $d add -- $script:Core $script:Rs $script:Cs
        Set-CoreText $d ((Get-Content -Raw -LiteralPath (Join-Path $d $script:Core)) + "`nUnstaged afterthought.`n")
        (Invoke-Parity $d).ExitCode | Should -Be 0 -Because 'the staged content is self-consistent, which is the only thing the hook validates'
    }

    It 'row 4 - literals stale in the INDEX but correct in the worktree: FAILS with remedy 1, and does NOT name the just task' {
        $d = New-ParityRepo
        Set-CoreText $d ((Get-Content -Raw -LiteralPath (Join-Path $d $script:Core)) + "`nRemedy one.`n")
        & git -C $d add -- $script:Core          # core staged, literals NOT
        Invoke-Gen $d                            # worktree literals are now correct
        $r = Invoke-Parity $d
        $r.ExitCode | Should -Not -Be 0
        $r.Text | Should -Match 'already in your worktree'
        $r.Text | Should -Not -Match 'gen-cheatsheet-literals' -Because 'running the task again is a no-op; naming it sends the user round a loop'
    }

    It 'row 5 - literals stale in index AND worktree: FAILS with remedy 2, naming the just task' {
        $d = New-ParityRepo
        Set-CoreText $d ((Get-Content -Raw -LiteralPath (Join-Path $d $script:Core)) + "`nRemedy two.`n")
        & git -C $d add -- $script:Core
        $r = Invoke-Parity $d
        $r.ExitCode | Should -Not -Be 0
        $r.Text | Should -Match 'gen-cheatsheet-literals'
    }

    It 'row 6 - core.md PARTIALLY staged, literals generated from the WORKTREE: FAILS saying partial staging' {
        # ROW 6 WAS SPECIFIED IN THE TABLE ABOVE AND NEVER IMPLEMENTED. Every other row 1-15 has an It;
        # this one had none, and its absence was worse than a plain gap because row 7 directly below
        # asserts the message must NOT say 'partial staging'. So the NEGATIVE was pinned and the
        # POSITIVE was not: the diagnosis branch that produces this message could have been dead, and
        # row 7 would still pass. A pair where only the "must not say X" half exists proves nothing
        # about X ever being said.
        #
        # THE PARTIAL STAGE, built rather than asserted: stage core.md at v1, then edit it to v2 in the
        # worktree WITHOUT staging - core.md is now both staged AND dirty, which is what "hunks split"
        # means to `git diff`. Generate the literals from that WORKTREE (v2) and stage them. The hook
        # regenerates from the INDEX (v1), so the staged literals cannot match, and the diagnosis runs.
        # Case 3 fires because `git diff --quiet` is non-zero (dirty) AND `git diff --cached --quiet`
        # is non-zero (staged) - which is exactly the state this row is named for.
        $d = New-ParityRepo
        Set-CoreText $d ((Get-Content -Raw -LiteralPath (Join-Path $d $script:Core)) + "`nv1 staged.`n")
        & git -C $d add -- $script:Core
        Set-CoreText $d ((Get-Content -Raw -LiteralPath (Join-Path $d $script:Core)) + "`nv2 unstaged.`n")
        Invoke-Gen $d
        & git -C $d add -- $script:Rs $script:Cs
        $r = Invoke-Parity $d
        $r.ExitCode | Should -Not -Be 0
        $r.Text | Should -Match 'partial staging' -Because 'this is the row that proves the message is ever PRODUCED; row 7 only proves it is not produced in the other case'
        $r.Text | Should -Match ([regex]::Escape('together with the regenerated literals')) -Because 'the remedy must be the one that works - staging core.md alone is rejected by the parity check that runs first'
    }

    It 'row 7 - literals staged but core.md NOT staged: FAILS with the RIGHT message, not the partial-staging one' {
        # Both branches fail; ONLY the text distinguishes a correct diagnosis from a misleading one.
        $d = New-ParityRepo
        Set-CoreText $d ((Get-Content -Raw -LiteralPath (Join-Path $d $script:Core)) + "`nNot staged.`n")
        Invoke-Gen $d
        & git -C $d add -- $script:Rs $script:Cs   # literals only
        $r = Invoke-Parity $d
        $r.ExitCode | Should -Not -Be 0
        $r.Text | Should -Match 'but not'
        $r.Text | Should -Not -Match 'partial staging' -Because 'telling someone their staging is partial when they staged nothing makes the hook look broken'
    }

    It 'row 8 - core.md deletion staged AND both literals deleted: PASSES, naming the skip' {
        $d = New-ParityRepo
        & git -C $d rm -q -- $script:Core $script:Rs $script:Cs
        $r = Invoke-Parity $d
        $r.ExitCode | Should -Be 0
        $r.Text | Should -Match 'no parity to assert'
    }

    It 'row 9 - core.md deletion staged but a literal SURVIVES: FAILS, naming the survivor' {
        $d = New-ParityRepo
        & git -C $d rm -q -- $script:Core $script:Rs
        $r = Invoke-Parity $d
        $r.ExitCode | Should -Not -Be 0
        $r.Text | Should -Match ([regex]::Escape($script:Cs)) -Because 'a wholesale pass would certify the survivor on its way out'
    }

    It 'row 10 - ONE literal deleted, core.md present: PASSES, naming which literal' {
        $d = New-ParityRepo
        & git -C $d rm -q -- $script:Rs
        $r = Invoke-Parity $d
        $r.ExitCode | Should -Be 0
        $r.Text | Should -Match ([regex]::Escape($script:Rs))
    }

    It 'row 11 - one literal deleted AND the OTHER diverged: FAILS on the survivor (catches a per-RUN skip)' {
        $d = New-ParityRepo
        & git -C $d rm -q -- $script:Rs
        $cs = Join-Path $d $script:Cs
        # ASSERT THE SETUP ACTUALLY DIVERGED THE FILE (capstone R4). `-replace` is a SILENT no-op when its
        # pattern is absent, so if that anchor text ever moves out of the literal this row would write the
        # file back UNCHANGED, parity would be genuinely intact, the hook would correctly exit 0 - and the
        # assertion below would blame the hook for missing a divergence the fixture never created.
        # Same class as the sweep row's missing precondition: a control must prove its own setup happened.
        $csBefore = [IO.File]::ReadAllBytes($cs)
        [IO.File]::WriteAllText($cs, ([IO.File]::ReadAllText($cs) -replace 'Driving the agy peer', 'DIVERGED'))
        [Linq.Enumerable]::SequenceEqual([IO.File]::ReadAllBytes($cs), $csBefore) |
            Should -BeFalse -Because 'the fixture must actually diverge the C# literal, or this row proves nothing about the per-path skip'
        & git -C $d add -- $script:Cs
        $r = Invoke-Parity $d
        $r.ExitCode | Should -Not -Be 0 -Because 'a blanket "any deletion skips parity" passes here while certifying a diverged pin'
        # ASSERT WHICH BRANCH FAILED (panel R16). Exit-code-only cannot tell "failed on the surviving
        # literal" from "crashed for an unrelated reason" - and a crash would satisfy the row while
        # proving nothing about the per-path skip this row exists to pin.
        $r.Text | Should -Match ([regex]::Escape($script:Cs))
    }

    It 'row 11a - BOTH literals deleted, core.md untouched: PASSES, naming both' {
        $d = New-ParityRepo
        & git -C $d rm -q -- $script:Rs $script:Cs
        $r = Invoke-Parity $d
        $r.ExitCode | Should -Be 0
        # Same reason as row 11: without the text, a hook that passed VACUOUSLY - or exited 0 before
        # reaching the `$targets.Count -eq 0` branch at all - keeps this row green (panel R16).
        $r.Text | Should -Match ([regex]::Escape($script:Rs))
        $r.Text | Should -Match ([regex]::Escape($script:Cs))
    }

    It 'row 12 - a core.md byte a text pipeline would alter survives EXACTLY' {
        # Constructed in a throwaway repo, so the ASCII rule governing the real core.md does not bind.
        $d = New-ParityRepo
        Set-CoreText $d "Header line`nA byte a code page would mangle: `u{00E9}`n"
        Invoke-Gen $d
        & git -C $d add -- $script:Core $script:Rs $script:Cs
        $r = Invoke-Parity $d
        $r.ExitCode | Should -Be 0 -Because 'raw-byte transport must round-trip the byte; a text pipe would re-encode it and fail parity'
    }

    It 'row 13 - worktree core.md CRLF, index LF, literals correct: PASSES (a regression pin only)' {
        $d = New-ParityRepo
        $txt = (Get-Content -Raw -LiteralPath (Join-Path $d $script:Core)) -replace "`r`n", "`n"
        Set-CoreText $d ($txt -replace "`n", "`r`n")
        (Invoke-Parity $d).ExitCode | Should -Be 0
    }

    It 'row 14 - no temp file survives, on the passing path AND a failing one' {
        $before = @(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Filter 'cheatsheet-parity-*' -ErrorAction SilentlyContinue).Count
        $d = New-ParityRepo
        Invoke-Parity $d | Out-Null
        Set-CoreText $d ((Get-Content -Raw -LiteralPath (Join-Path $d $script:Core)) + "`nfail path.`n")
        & git -C $d add -- $script:Core
        Invoke-Parity $d | Out-Null
        @(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Filter 'cheatsheet-parity-*' -ErrorAction SilentlyContinue).Count |
            Should -Be $before -Because 'the finally block must clear every temp on EVERY exit path'
    }

    It 'row 15 - the hook never writes in place: two runs leave the worktree unchanged' {
        $d = New-ParityRepo
        $h1 = (& git -C $d status --porcelain) -join "`n"
        Invoke-Parity $d | Out-Null
        Invoke-Parity $d | Out-Null
        ((& git -C $d status --porcelain) -join "`n") | Should -BeExactly $h1
    }

    It 'row 1 - the generator exits non-zero: the hook FAILS rather than passing on an untouched tree' {
        $d = New-ParityRepo
        # Neuter the generator so it cannot succeed. A crashed generator is not evidence of parity.
        Set-Content -LiteralPath (Join-Path $d 'scripts/generate-cheatsheet-literals.ps1') -Value 'exit 3'
        Set-CoreText $d ((Get-Content -Raw -LiteralPath (Join-Path $d $script:Core)) + "`nx.`n")
        & git -C $d add -- $script:Core
        $r = Invoke-Parity $d
        $r.ExitCode | Should -Not -Be 0
        $r.Text | Should -Match 'generator exited'
    }
}

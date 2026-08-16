# scripts/tests/check-growth-budget.Tests.ps1
BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'check-growth-budget.ps1'
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
}

Describe "check-growth-budget.ps1 (SEED + GROWTH <= combined cap)" {
    BeforeEach {
        $script:Repo = Join-Path ([System.IO.Path]::GetTempPath()) ("growthbudget-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'seed') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'docs') | Out-Null
        $script:Seed = Join-Path $script:Repo 'seed/golden-header.md'
        $script:Growth = Join-Path $script:Repo 'docs/agy-golden-header.growth.md'
    }
    AfterEach { Remove-Item -Recurse -Force $script:Repo -ErrorAction SilentlyContinue }

    It "passes when SEED + GROWTH is within the cap" {
        Set-Content -NoNewline -Path $script:Seed -Value ('s' * 100)
        Set-Content -NoNewline -Path $script:Growth -Value ('g' * 50)
        & pwsh -File $script:Script -RepoRoot $script:Repo -MaxBytes 200
        $LASTEXITCODE | Should -Be 0
    }

    It "fails when SEED + GROWTH exceeds the cap" {
        Set-Content -NoNewline -Path $script:Seed -Value ('s' * 120)
        Set-Content -NoNewline -Path $script:Growth -Value ('g' * 120)
        & pwsh -File $script:Script -RepoRoot $script:Repo -MaxBytes 200
        $LASTEXITCODE | Should -Be 1
    }

    It "FAILS when both files are absent (13c: a missing SEED is never legitimate, unlike a missing GROWTH)" {
        # Pre-13c this asserted exit 0 for '0 + 0 bytes' — that was the fail-open itself: a missing SEED
        # silently measured 0 and certified an unmeasured budget. SEED absence now hard-fails regardless
        # of GROWTH's presence (see the '13c' Context below).
        & pwsh -File $script:Script -RepoRoot $script:Repo -MaxBytes 200
        $LASTEXITCODE | Should -Not -Be 0
    }

    It "measures UTF-8 BYTES not characters (multibyte)" {
        Set-Content -NoNewline -Path $script:Growth -Value ([string]([char]0x20AC) * 100) -Encoding utf8  # 300 bytes
        & pwsh -File $script:Script -RepoRoot $script:Repo -MaxBytes 200
        $LASTEXITCODE | Should -Be 1
    }

    It "defaults MaxBytes to 16 KiB (the binary's combined injection cap)" {
        Set-Content -NoNewline -Path $script:Growth -Value ('g' * ((16 * 1024) + 1))   # 1 over, seed absent
        & pwsh -File $script:Script -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 1
    }

    It "counts RAW on-disk bytes including a UTF-8 BOM (a BOM-stripping counter would wrongly pass; panel agy-A6)" {
        # 3-byte UTF-8 BOM + 200 ASCII bytes = 203 raw bytes > a 202 cap. GetByteCount(ReadAllText) would see 200.
        $bom = [byte[]]@(0xEF, 0xBB, 0xBF)
        [System.IO.File]::WriteAllBytes($script:Growth, ($bom + [System.Text.Encoding]::ASCII.GetBytes('g' * 200)))
        & pwsh -File $script:Script -RepoRoot $script:Repo -MaxBytes 202
        $LASTEXITCODE | Should -Be 1
    }

    It "adds the 2-byte separator only when BOTH regions are present (panel agy-A1)" {
        # seed 100 + growth 100 + 2 separator = 202 > a 201 cap; either region alone at 100 would pass.
        Set-Content -NoNewline -Path $script:Seed -Value ('s' * 100)
        Set-Content -NoNewline -Path $script:Growth -Value ('g' * 100)
        & pwsh -File $script:Script -RepoRoot $script:Repo -MaxBytes 201
        $LASTEXITCODE | Should -Be 1
    }

    Context '13c - a missing input is distinguishable from an empty one' {
        BeforeAll {
            $script:Fixtures = New-Object System.Collections.ArrayList   # FIXTURE HYGIENE
            function New-BudgetFixture {
                param([switch]$NoSeed, [switch]$EmptySeed, [switch]$NoGrowth, [switch]$EmptyGrowth, [int]$GrowthBytes = 100)
                $d = Join-Path ([IO.Path]::GetTempPath()) ("gb-" + [guid]::NewGuid().ToString('N'))
                [void]$script:Fixtures.Add($d)   # FIXTURE HYGIENE
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'seed') | Out-Null
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'docs') | Out-Null
                if (-not $NoSeed)   { [IO.File]::WriteAllText((Join-Path $d 'seed/golden-header.md'), ($EmptySeed ? '' : ('s' * 200))) }
                if (-not $NoGrowth) { [IO.File]::WriteAllText((Join-Path $d 'docs/agy-golden-header.growth.md'), ($EmptyGrowth ? '' : ('g' * $GrowthBytes))) }
                $d
            }
            function Invoke-Budget {
                param([string]$Root, [int]$MaxBytes = 16384)
                $out = & pwsh -NoProfile -File (Join-Path $script:RepoRoot 'scripts/check-growth-budget.ps1') -RepoRoot $Root -MaxBytes $MaxBytes 2>&1 | Out-String
                [pscustomobject]@{ Out = $out; Rc = $LASTEXITCODE }
            }
        }

        AfterAll {
            foreach ($f in $script:Fixtures) { Remove-Item -LiteralPath $f -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It 'GROWTH missing: names it ABSENT, not empty, and exits 0' {
            $r = Invoke-Budget (New-BudgetFixture -NoGrowth)
            $r.Out | Should -Match '(?i)absent|missing|not present'
            $r.Out | Should -Not -Match '(?i)\bempty\b'
            $r.Rc  | Should -Be 0 -Because 'a docs-only drain legitimately has nothing to publish'
        }
        It 'GROWTH present but EMPTY: names it EMPTY, not absent, and exits 0' {
            $r = Invoke-Budget (New-BudgetFixture -EmptyGrowth)
            $r.Out | Should -Match '(?i)\bempty\b'
            $r.Out | Should -Not -Match '(?i)absent|missing'
            $r.Rc  | Should -Be 0
        }
        It 'SEED missing: names the MISSING SEED, never an overflow, and exits NON-ZERO' {
            # The fail-open this item's anomaly never looked at: 0 + 16384 <= 16384 certifies a
            # full-cap proposal, the binary then combines the REAL seed, overflows, and drops GROWTH.
            $r = Invoke-Budget (New-BudgetFixture -NoSeed)
            $r.Out | Should -Match '(?i)seed'
            $r.Out | Should -Not -Match '(?i)exceeds|> '
            $r.Rc  | Should -Not -Be 0
        }
        It 'SEED present but EMPTY: names it EMPTY and exits NON-ZERO' {
            $r = Invoke-Budget (New-BudgetFixture -EmptySeed)
            $r.Out | Should -Match '(?i)\bempty\b'
            $r.Rc  | Should -Not -Be 0
        }
        It 'SEED over the cap with GROWTH ABSENT: still FAILS (panel R4 - the early-return fail-open)' {
            # THE ROW THAT CATCHES 13c's OWN REGRESSION. The first draft returned 0 here while printing
            # "SEED <n>B <= <cap>B" without testing it. The ORIGINAL code had no such hole: with GROWTH
            # absent the separator is 0 and $combined is just $seedBytes, so the cap comparison still ran.
            # Without this row, an early return for the legitimate GROWTH-absent case silently deletes the
            # only check an oversized seed would ever fail - and prints a false statement in green.
            $r = Invoke-Budget (New-BudgetFixture -NoGrowth) -MaxBytes 50   # seed fixture is 200B
            $r.Rc  | Should -Not -Be 0 -Because 'a seed over the cap on its own must never pass, GROWTH present or not'
            $r.Out | Should -Not -Match '(?i)\bOK\b'
        }
        It 'SEED over the cap with GROWTH EMPTY: still FAILS' {
            $r = Invoke-Budget (New-BudgetFixture -EmptyGrowth) -MaxBytes 50
            $r.Rc | Should -Not -Be 0
        }
        It 'both present, over cap: the EXISTING overflow message, non-zero (unchanged)' {
            $r = Invoke-Budget (New-BudgetFixture -GrowthBytes 500) -MaxBytes 300
            $r.Out | Should -Match '(?i)exceeds|FAIL'
            $r.Rc  | Should -Not -Be 0
        }
        It 'both present, under cap: the EXISTING OK line, exit 0 (unchanged)' {
            $r = Invoke-Budget (New-BudgetFixture)
            $r.Out | Should -Match 'check-growth-budget: OK'
            $r.Rc  | Should -Be 0
        }
    }
}

# scripts/tests/check-growth-budget.Tests.ps1
BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'check-growth-budget.ps1'
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

    It "passes when both files are absent (0 + 0 bytes)" {
        & pwsh -File $script:Script -RepoRoot $script:Repo -MaxBytes 200
        $LASTEXITCODE | Should -Be 0
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
}

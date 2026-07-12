# scripts/tests/check-seed-budget.Tests.ps1
BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'check-seed-budget.ps1'
}

Describe "check-seed-budget.ps1" {
    BeforeEach {
        $script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("seedbudget-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Tmp | Out-Null
        $script:Seed = Join-Path $script:Tmp 'golden-header.md'
    }
    AfterEach { Remove-Item -Recurse -Force $script:Tmp -ErrorAction SilentlyContinue }

    It "passes when the seed is under budget" {
        Set-Content -NoNewline -Path $script:Seed -Value ('x' * 100)
        & pwsh -File $script:Script -SeedPath $script:Seed -MaxBytes 200
        $LASTEXITCODE | Should -Be 0
    }

    It "fails when the seed exceeds budget" {
        Set-Content -NoNewline -Path $script:Seed -Value ('x' * 300)
        & pwsh -File $script:Script -SeedPath $script:Seed -MaxBytes 200
        $LASTEXITCODE | Should -Be 1
    }

    It "passes (0 bytes) when the seed file is absent (fresh clone)" {
        & pwsh -File $script:Script -SeedPath (Join-Path $script:Tmp 'missing.md') -MaxBytes 200
        $LASTEXITCODE | Should -Be 0
    }

    It "measures UTF-8 BYTES not characters (multibyte)" {
        # 100 × '€' = 300 UTF-8 bytes but 100 chars; must FAIL a 200-byte budget.
        Set-Content -NoNewline -Path $script:Seed -Value ([string]([char]0x20AC) * 100) -Encoding utf8
        & pwsh -File $script:Script -SeedPath $script:Seed -MaxBytes 200
        $LASTEXITCODE | Should -Be 1
    }
}

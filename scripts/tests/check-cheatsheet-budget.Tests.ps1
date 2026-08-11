# scripts/tests/check-cheatsheet-budget.Tests.ps1
BeforeAll {
    $script:Script   = Join-Path $PSScriptRoot '..' 'check-cheatsheet-budget.ps1'
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:Canonical = Join-Path $script:RepoRoot 'agy-autotrain/knowledge/driver-cheatsheet.core.md'
}

Describe "check-cheatsheet-budget.ps1" {
    BeforeEach {
        $script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cheatbudget-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Tmp | Out-Null
        $script:File = Join-Path $script:Tmp 'driver-cheatsheet.core.md'
    }
    AfterEach { Remove-Item -Recurse -Force $script:Tmp -ErrorAction SilentlyContinue }

    It "passes when the cheatsheet is under budget" {
        Set-Content -NoNewline -Path $script:File -Value ('x' * 100)
        & pwsh -File $script:Script -Path $script:File -MaxBytes 200
        $LASTEXITCODE | Should -Be 0
    }

    It "fails when the cheatsheet exceeds budget" {
        Set-Content -NoNewline -Path $script:File -Value ('x' * 300)
        & pwsh -File $script:Script -Path $script:File -MaxBytes 200
        $LASTEXITCODE | Should -Be 1
    }

    It "passes (0 bytes) when the file is absent (fresh clone)" {
        & pwsh -File $script:Script -Path (Join-Path $script:Tmp 'missing.md') -MaxBytes 200
        $LASTEXITCODE | Should -Be 0
    }

    It "measures UTF-8 BYTES not characters (multibyte)" {
        # 100 x EUR SIGN = 300 UTF-8 bytes but 100 chars; must FAIL a 200-byte budget.
        Set-Content -NoNewline -Path $script:File -Value ([string]([char]0x20AC) * 100) -Encoding utf8
        & pwsh -File $script:Script -Path $script:File -MaxBytes 200
        $LASTEXITCODE | Should -Be 1
    }

    It "pins the committed default budget at 4096 bytes" {
        # WITHOUT THIS ROW the enforcing row below is defeated by a one-line edit. It invokes the script
        # with NO arguments, so it measures against whatever the default happens to be at call time -
        # meaning a future commit that raises the default AND grows the cheatsheet passes both. Pinning
        # the number here makes raising the budget a deliberate, visible test edit rather than a silent
        # side effect of the change that needed the extra room.
        $src = Get-Content -Raw -LiteralPath $script:Script
        $src | Should -Match '\[int\]\$MaxBytes\s*=\s*4096' -Because 'raising the budget must be a conscious edit to this test, not an invisible default shift'
    }

    It "the REAL canonical cheatsheet is within the committed default budget" {
        # THE POINT OF F1. The four synthetic rows above test the script's logic on input they supply
        # themselves, and would all pass with the real artifact 10x over budget. This row is the one that
        # actually enforces. It and the default-pin row above are the only two that consult the script's
        # own default, which is why a mutant on that default reddens exactly this pair (Step 15).
        Test-Path $script:Canonical | Should -BeTrue -Because 'the assertion below is vacuous without it'
        & pwsh -File $script:Script
        $LASTEXITCODE | Should -Be 0 -Because 'agy-curate/SKILL.md states this budget; an unenforced number is how it drifted to 4x before'
    }
}

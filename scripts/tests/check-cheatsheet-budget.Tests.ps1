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
        & pwsh -NoProfile -File $script:Script -Path $script:File -MaxBytes 200
        $LASTEXITCODE | Should -Be 0
    }

    It "fails when the cheatsheet exceeds budget" {
        Set-Content -NoNewline -Path $script:File -Value ('x' * 300)
        & pwsh -NoProfile -File $script:Script -Path $script:File -MaxBytes 200
        $LASTEXITCODE | Should -Be 1
    }

    It "passes (0 bytes) when the file is absent (fresh clone)" {
        & pwsh -NoProfile -File $script:Script -Path (Join-Path $script:Tmp 'missing.md') -MaxBytes 200
        $LASTEXITCODE | Should -Be 0
    }

    It "measures UTF-8 BYTES not characters (multibyte)" {
        # 100 x EUR SIGN = 300 UTF-8 bytes but 100 chars; must FAIL a 200-byte budget.
        Set-Content -NoNewline -Path $script:File -Value ([string]([char]0x20AC) * 100) -Encoding utf8
        & pwsh -NoProfile -File $script:Script -Path $script:File -MaxBytes 200
        $LASTEXITCODE | Should -Be 1
    }

    It "pins the committed default budget at 6144 bytes" {
        # WITHOUT THIS ROW the enforcing row below is defeated by a one-line edit. It invokes the script
        # with NO arguments, so it measures against whatever the default happens to be at call time -
        # meaning a future commit that raises the default AND grows the cheatsheet passes both. Pinning
        # the number here makes raising the budget a deliberate, visible test edit rather than a silent
        # side effect of the change that needed the extra room.
        #
        # PIN THE BEHAVIOUR, NOT THE SOURCE TEXT. Two earlier forms of this row matched the declaration
        # as a string and both were defeated: an unanchored match was satisfied by the number sitting in
        # any comment, and an `(?m)^\s*` anchored match was satisfied by the declaration wrapped in a
        # PowerShell block comment (`<# ... #>`) with a different live default underneath. MEASURED: a
        # 6000-byte file passed that mutant while this row stayed green, so the gate certified a budget
        # it was not enforcing. A regex cannot close this - it is not a lexer and cannot pair `<#`/`#>`.
        # Invoking the script at the boundary sidesteps the whole class: it reads the default that is
        # actually in force, and is indifferent to comment style, to the parameter's type annotation,
        # and to whether the default is a literal or an expression.
        $under = Join-Path $script:Tmp 'boundary-6144.md'
        $over  = Join-Path $script:Tmp 'boundary-6145.md'
        [System.IO.File]::WriteAllBytes($under, [byte[]]::new(6144))
        [System.IO.File]::WriteAllBytes($over,  [byte[]]::new(6145))

        & pwsh -NoProfile -File $script:Script -Path $under | Out-Null
        $LASTEXITCODE | Should -Be 0 -Because 'exactly 6144 bytes is within the committed default budget'
        & pwsh -NoProfile -File $script:Script -Path $over  | Out-Null
        $LASTEXITCODE | Should -Be 1 -Because 'one byte over the committed default must fail; if this passes, the default is no longer 6144'
    }

    It "the REAL canonical cheatsheet is within the committed default budget" {
        # THE POINT OF F1. The four synthetic rows above test the script's logic on input they supply
        # themselves, and would all pass with the real artifact 10x over budget. This row is the one that
        # actually enforces. It and the default-pin row above are the only two that consult the script's
        # own default, which is why a mutant on that default reddens exactly this pair (Step 15).
        Test-Path $script:Canonical | Should -BeTrue -Because 'the assertion below is vacuous without it'
        & pwsh -NoProfile -File $script:Script
        $LASTEXITCODE | Should -Be 0 -Because 'agy-curate/SKILL.md states this budget; an unenforced number is how it drifted to 4x before'
    }
}

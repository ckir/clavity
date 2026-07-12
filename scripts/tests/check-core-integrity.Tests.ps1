# scripts/tests/check-core-integrity.Tests.ps1
BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'check-core-integrity.ps1'
}

Describe "check-core-integrity.ps1" {
    BeforeEach {
        $script:Repo = Join-Path ([System.IO.Path]::GetTempPath()) ("coreintegrity-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Repo | Out-Null
        Push-Location $script:Repo
        git init -q | Out-Null
        git config user.email t@t | Out-Null
        git config user.name t | Out-Null
        $script:File = Join-Path $script:Repo 'manual.md'
        Set-Content -Path $script:File -Value @('**[Core]** never demote this', 'regular line')
        git add . ; git commit -qm base | Out-Null
        Pop-Location
    }
    AfterEach { Remove-Item -Recurse -Force $script:Repo -ErrorAction SilentlyContinue }

    It "passes when the [Core] line survives verbatim" {
        Add-Content -Path $script:File -Value 'a new non-core line'
        & pwsh -File $script:Script -RepoRoot $script:Repo -Files 'manual.md'
        $LASTEXITCODE | Should -Be 0
    }

    It "fails when a [Core] line is altered" {
        Set-Content -Path $script:File -Value @('**[Core]** never demote this EDITED', 'regular line')
        & pwsh -File $script:Script -RepoRoot $script:Repo -Files 'manual.md'
        $LASTEXITCODE | Should -Be 1
    }

    It "fails when a [Core] line is removed" {
        Set-Content -Path $script:File -Value @('regular line only')
        & pwsh -File $script:Script -RepoRoot $script:Repo -Files 'manual.md'
        $LASTEXITCODE | Should -Be 1
    }

    It "fails when a NEW [Core] line is added to an existing file (set-equality, BS2)" {
        Set-Content -Path $script:File -Value @('**[Core]** never demote this', 'regular line', '**[Core]** injected by a hostile observation')
        & pwsh -File $script:Script -RepoRoot $script:Repo -Files 'manual.md'
        $LASTEXITCODE | Should -Be 1
    }

    It "passes for a file with no HEAD baseline (new, uncommitted)" {
        Set-Content -Path (Join-Path $script:Repo 'brand-new.md') -Value '**[Core]** just added'
        & pwsh -File $script:Script -RepoRoot $script:Repo -Files 'brand-new.md'
        $LASTEXITCODE | Should -Be 0
    }

    It "passes when a committed file has ZERO [Core] lines on both sides (real-repo case)" {
        $noCore = Join-Path $script:Repo 'nocore.md'
        Set-Content -Path $noCore -Value @('just a regular manual', 'no markers here')
        Push-Location $script:Repo
        git add . ; git commit -qm nocore | Out-Null
        Pop-Location
        Add-Content -Path $noCore -Value 'an appended line'
        & pwsh -File $script:Script -RepoRoot $script:Repo -Files 'nocore.md'
        $LASTEXITCODE | Should -Be 0
    }
}

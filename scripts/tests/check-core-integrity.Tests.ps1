# scripts/tests/check-core-integrity.Tests.ps1
BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'check-core-integrity.ps1'
}

Describe "check-core-integrity.ps1 (protected-files-unchanged gate)" {
    BeforeEach {
        $script:Repo = Join-Path ([System.IO.Path]::GetTempPath()) ("coreintegrity-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Repo | Out-Null
        Push-Location $script:Repo
        git init -q | Out-Null; git config user.email t@t | Out-Null; git config user.name t | Out-Null
        $script:File = Join-Path $script:Repo 'protected.md'
        Set-Content -Path $script:File -Value @('driver-owned content', 'second line')
        git add . ; git commit -qm base | Out-Null
        Pop-Location
    }
    AfterEach { Remove-Item -Recurse -Force $script:Repo -ErrorAction SilentlyContinue }

    It "passes when the protected file is byte-identical to HEAD" {
        & pwsh -File $script:Script -RepoRoot $script:Repo -Files 'protected.md'
        $LASTEXITCODE | Should -Be 0
    }

    It "fails when the protected file was modified (any content change)" {
        Add-Content -Path $script:File -Value 'a curator edit'
        & pwsh -File $script:Script -RepoRoot $script:Repo -Files 'protected.md'
        $LASTEXITCODE | Should -Be 1
    }

    It "fails when a protected file was deleted" {
        Remove-Item -Force $script:File
        & pwsh -File $script:Script -RepoRoot $script:Repo -Files 'protected.md'
        $LASTEXITCODE | Should -Be 1
    }

    It "passes for a file with no HEAD baseline (new, uncommitted — nothing to protect yet)" {
        Set-Content -Path (Join-Path $script:Repo 'brand-new.md') -Value 'x'
        & pwsh -File $script:Script -RepoRoot $script:Repo -Files 'brand-new.md'
        $LASTEXITCODE | Should -Be 0
    }

    It "hard-fails (exit 1) when 'git' cannot run (not a repo)" {
        $notRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("notrepo-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $notRepo | Out-Null
        try {
            Set-Content -Path (Join-Path $notRepo 'protected.md') -Value 'x'
            & pwsh -File $script:Script -RepoRoot $notRepo -Files 'protected.md'
            $LASTEXITCODE | Should -Be 1
        } finally { Remove-Item -Recurse -Force $notRepo -ErrorAction SilentlyContinue }
    }

    It "with NO -Files, the default derives from drain-lib's Get-DrainProtectedPaths (single source; panel agy-R2-1/R3-F2)" {
        # Commit + modify a file at a real Get-DrainProtectedPaths path, then run WITHOUT -Files: the dot-sourced
        # default must include it and fail. Proves the gate's default and the revert loop read the SAME list.
        $rel = 'seed/golden-header.md'
        $abs = Join-Path $script:Repo $rel
        New-Item -ItemType Directory -Path (Split-Path $abs -Parent) -Force | Out-Null
        Set-Content $abs 'original'
        Push-Location $script:Repo; git add . ; git commit -qm seed | Out-Null; Pop-Location
        Set-Content $abs 'a curator edit'
        & pwsh -File $script:Script -RepoRoot $script:Repo          # NO -Files → default from Get-DrainProtectedPaths
        $LASTEXITCODE | Should -Be 1
    }
}

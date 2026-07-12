# scripts/tests/accept-drain.Tests.ps1
BeforeAll {
    $script:Accept = Join-Path $PSScriptRoot '..' 'accept-drain.ps1'
}

Describe "accept-drain transaction (scratch repo)" {
    BeforeEach {
        $script:Repo = Join-Path ([System.IO.Path]::GetTempPath()) ("accept-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'seed') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'docs') | Out-Null
        Push-Location $script:Repo
        git init -q; git config user.email t@t; git config user.name t
        Set-Content 'seed/golden-header.md' 'SEED'
        Set-Content 'docs/agy-drain-log.md' '# agy drain log'
        git add .; git commit -qm base
        Pop-Location
        # Inbox lives OUTSIDE the repo (mirrors reality) so `git add .` never captures the staging snapshot.
        $script:InboxDir = Join-Path ([System.IO.Path]::GetTempPath()) ("abox-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:InboxDir | Out-Null
        $script:Inbox = Join-Path $script:InboxDir 'agy-observations.md'
        Set-Content $script:Inbox @('# inbox', '', '## Pending')
        Set-Content (Join-Path $script:InboxDir 'agy-observations.staging.RID9.md') @('- [heuristic] r  ·  x')
    }
    AfterEach { Remove-Item -Recurse -Force $script:Repo, $script:InboxDir -ErrorAction SilentlyContinue }

    It "accepts + deletes staging when the run-ID is committed and the tree is clean (F30/F34)" {
        Push-Location $script:Repo
        Add-Content 'docs/agy-drain-log.md' '## drain RID9 — x — SEED 1B->1B — verify-needed: 0'
        git add .; git commit -qm drained
        Pop-Location
        & pwsh -File $script:Accept -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 0
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 0
    }

    It "BLOCKS when the run-ID is only in the working-tree log, not committed (F30)" {
        Add-Content (Join-Path $script:Repo 'docs/agy-drain-log.md') '## drain RID9 — x — SEED 1B->1B — verify-needed: 0'
        & pwsh -File $script:Accept -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 1
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1
    }

    It "BLOCKS when the drain-log is committed but a manual/seed edit is uncommitted (F34)" {
        Push-Location $script:Repo
        Add-Content 'docs/agy-drain-log.md' '## drain RID9 — x — SEED 1B->1B — verify-needed: 0'
        git add docs/agy-drain-log.md; git commit -qm 'log only'        # committed the LOG ONLY
        Set-Content 'seed/golden-header.md' 'DRAINED SEED (uncommitted)' # a seed edit left dirty
        Pop-Location
        & pwsh -File $script:Accept -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 1
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1
    }
}

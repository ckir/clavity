# scripts/tests/abort-drain.Tests.ps1
BeforeAll {
    $script:Abort = Join-Path $PSScriptRoot '..' 'abort-drain.ps1'
}

Describe "abort-drain transaction (scratch repo)" {
    BeforeEach {
        $script:Repo = Join-Path ([System.IO.Path]::GetTempPath()) ("abort-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'seed') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'docs') | Out-Null
        Push-Location $script:Repo
        git init -q; git config user.email t@t; git config user.name t
        Set-Content 'seed/golden-header.md' 'ORIGINAL SEED'
        Set-Content 'docs/agy-drain-log.md' '# agy drain log'
        git add .; git commit -qm base
        Pop-Location
        # Inbox lives OUTSIDE the repo (mirrors reality: the app-data inbox is never under the repo tree).
        $script:InboxDir = Join-Path ([System.IO.Path]::GetTempPath()) ("abox-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:InboxDir | Out-Null
        $script:Inbox = Join-Path $script:InboxDir 'agy-observations.md'
        Set-Content $script:Inbox @('# inbox', '', '## Pending')
        Set-Content (Join-Path $script:InboxDir 'agy-observations.staging.RID1.md') @('- [heuristic] r1  ·  x')
        Set-Content (Join-Path $script:Repo 'seed/golden-header.md') 'DRAINED SEED (unwanted)'  # dirtied, uncommitted
    }
    AfterEach { Remove-Item -Recurse -Force $script:Repo, $script:InboxDir -ErrorAction SilentlyContinue }

    It "restores dirtied outputs, re-queues the snapshot, deletes staging" {
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 0
        (Get-Content (Join-Path $script:Repo 'seed/golden-header.md') -Raw).Trim() | Should -Be 'ORIGINAL SEED'
        (Get-Content $script:Inbox | Where-Object { $_ -match '^- \[' }).Count | Should -Be 1
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 0
    }

    It "BLOCKS when the run-ID is already committed (F33) and does NOT delete staging" {
        Push-Location $script:Repo
        Add-Content 'docs/agy-drain-log.md' '## drain RID1 — x — SEED 1B->2B — verify-needed: 0'
        git add .; git commit -qm drained
        Pop-Location
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 1
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1
    }

    It "-WhatIf previews without reverting outputs or deleting staging" {
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo -WhatIf
        (Get-Content (Join-Path $script:Repo 'seed/golden-header.md') -Raw).Trim() | Should -Be 'DRAINED SEED (unwanted)'  # NOT reverted
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1                       # NOT deleted
    }
}

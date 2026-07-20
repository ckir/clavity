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

    It "hard-fails (exit 1) and RETAINS staging when the git revert fails" {
        $notRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("notrepo-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $notRepo | Out-Null
        try {
            & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $notRepo
            $LASTEXITCODE | Should -Be 1
            (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1
        } finally { Remove-Item -Recurse -Force $notRepo -ErrorAction SilentlyContinue }
    }

    It "REFUSES when a tracked file outside drain outputs is modified (data-loss guard) and touches nothing" {
        Push-Location $script:Repo
        Set-Content 'README.md' 'v1'
        git add 'README.md'; git commit -qm "add readme"
        Pop-Location
        Set-Content (Join-Path $script:Repo 'README.md') 'unrelated edit'  # dirtied, uncommitted, NOT a drain output
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 1
        (Get-Content (Join-Path $script:Repo 'README.md') -Raw).Trim() | Should -Be 'unrelated edit'                       # NOT reverted
        (Get-Content (Join-Path $script:Repo 'seed/golden-header.md') -Raw).Trim() | Should -Be 'DRAINED SEED (unwanted)'   # nothing touched at all
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1                      # staging retained
    }

    It "PROCEEDS when only the drain's own outputs are modified" {
        # BeforeEach already dirties only seed/golden-header.md (a Get-DrainOutputPaths entry) — the guard must
        # not block the ordinary, expected case.
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 0
        (Get-Content (Join-Path $script:Repo 'seed/golden-header.md') -Raw).Trim() | Should -Be 'ORIGINAL SEED'
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 0
    }

    It "REFUSES when an unrelated UNTRACKED file exists under a drain output directory (git-clean data-loss guard) and touches nothing" {
        # Mirrors the documented review pause: a maintainer drops their own note under docs/fix-the-tool-backlog/
        # (a Get-DrainOutputPaths DIRECTORY entry) between `just drain-knowledge` and `just abort-drain`. The
        # scoped `git clean -fd -- (Get-DrainOutputPaths)` would otherwise silently delete it.
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'docs/fix-the-tool-backlog') | Out-Null
        Set-Content (Join-Path $script:Repo 'docs/fix-the-tool-backlog/maintainer-note.md') 'unrelated untracked note'
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 1
        (Test-Path (Join-Path $script:Repo 'docs/fix-the-tool-backlog/maintainer-note.md')) | Should -Be $true
        (Get-Content (Join-Path $script:Repo 'docs/fix-the-tool-backlog/maintainer-note.md') -Raw).Trim() | Should -Be 'unrelated untracked note'
        (Get-Content (Join-Path $script:Repo 'seed/golden-header.md') -Raw).Trim() | Should -Be 'DRAINED SEED (unwanted)'   # nothing touched at all
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1                      # staging retained
    }

    It "PROCEEDS when the drain's own untracked output file exists (regression: exact-match legitimacy still allows the real case)" {
        # docs/agy-verify-needed.md is a Get-DrainOutputPaths FILE entry (not committed in the BeforeEach base) —
        # exactly what a real drain run creates untracked on its first pass. It must still be recognized as a
        # legitimate drain output and cleaned, not refused as an unrelated stray.
        Set-Content (Join-Path $script:Repo 'docs/agy-verify-needed.md') '# agy verify-needed backlog'
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 0
        (Test-Path (Join-Path $script:Repo 'docs/agy-verify-needed.md')) | Should -Be $false
        (Get-Content (Join-Path $script:Repo 'seed/golden-header.md') -Raw).Trim() | Should -Be 'ORIGINAL SEED'
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 0
    }

    It "reverts even when the drain outputs were STAGED (reset --hard HEAD, not checkout-from-index)" {
        Push-Location $script:Repo
        git add 'seed/golden-header.md'      # maintainer staged the drain's edit before deciding to abort
        Pop-Location
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 0
        (Get-Content (Join-Path $script:Repo 'seed/golden-header.md') -Raw).Trim() | Should -Be 'ORIGINAL SEED'
        Push-Location $script:Repo
        $st = git status --porcelain
        Pop-Location
        $st | Should -BeNullOrEmpty
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 0
    }
}

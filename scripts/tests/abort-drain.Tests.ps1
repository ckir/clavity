# scripts/tests/abort-drain.Tests.ps1
BeforeAll {
    $script:Abort = Join-Path $PSScriptRoot '..' 'abort-drain.ps1'
}

Describe "abort-drain transaction (scratch repo)" {
    BeforeEach {
        $script:Repo = Join-Path ([System.IO.Path]::GetTempPath()) ("abort-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'docs') | Out-Null
        Push-Location $script:Repo
        git init -q; git config user.email t@t; git config user.name t
        Set-Content 'docs/agy-golden-header.growth.md' 'ORIGINAL GROWTH'
        Set-Content 'docs/agy-drain-log.md' '# agy drain log'
        git add .; git commit -qm base
        Pop-Location
        $script:InboxDir = Join-Path ([System.IO.Path]::GetTempPath()) ("abox-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:InboxDir | Out-Null
        $script:Inbox = Join-Path $script:InboxDir 'agy-observations.md'
        Set-Content $script:Inbox @('# inbox', '', '## Pending')
        Set-Content (Join-Path $script:InboxDir 'agy-observations.staging.RID1.md') @('- [heuristic] r1  ·  x')
        Set-Content (Join-Path $script:Repo 'docs/agy-golden-header.growth.md') 'DRAINED GROWTH (unwanted)'  # dirtied, uncommitted
    }
    AfterEach { Remove-Item -Recurse -Force $script:Repo, $script:InboxDir -ErrorAction SilentlyContinue }

    It "restores dirtied outputs, re-queues the snapshot, deletes staging" {
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 0
        (Get-Content (Join-Path $script:Repo 'docs/agy-golden-header.growth.md') -Raw).Trim() | Should -Be 'ORIGINAL GROWTH'
        (Get-Content $script:Inbox | Where-Object { $_ -match '^- \[' }).Count | Should -Be 1
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 0
    }

    It "BLOCKS when the run-ID is already committed (F33) and does NOT delete staging" {
        Push-Location $script:Repo
        Add-Content 'docs/agy-drain-log.md' '## drain RID1 — x — GROWTH 14B — verify-needed: 0'
        git add .; git commit -qm drained
        Pop-Location
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 1
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1
    }

    It "-WhatIf previews without reverting outputs or deleting staging" {
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo -WhatIf
        (Get-Content (Join-Path $script:Repo 'docs/agy-golden-header.growth.md') -Raw).Trim() | Should -Be 'DRAINED GROWTH (unwanted)'
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1
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
        Set-Content (Join-Path $script:Repo 'README.md') 'unrelated edit'
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 1
        (Get-Content (Join-Path $script:Repo 'README.md') -Raw).Trim() | Should -Be 'unrelated edit'
        (Get-Content (Join-Path $script:Repo 'docs/agy-golden-header.growth.md') -Raw).Trim() | Should -Be 'DRAINED GROWTH (unwanted)'
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1
    }

    It "PROCEEDS when only the drain's own outputs are modified" {
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 0
        (Get-Content (Join-Path $script:Repo 'docs/agy-golden-header.growth.md') -Raw).Trim() | Should -Be 'ORIGINAL GROWTH'
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 0
    }

    It "REFUSES when an unrelated UNTRACKED file exists under a drain output directory (git-clean data-loss guard) and touches nothing" {
        # agy-autotrain/-rooted, not umbrella-rooted. These fixtures pinned the UMBRELLA path, which is
        # where the backlog does NOT live - agy-autotrain/docs/fix-the-tool-backlog/ has 17 tracked files
        # (`git ls-files agy-autotrain/docs/fix-the-tool-backlog/ | wc -l`, measured 2026-08-26; the count
        # grows as the backlog does, so treat it as an order-of-magnitude fact, not a pin). The fixtures
        # agreed with a defect in Get-DrainOutputPaths rather than with the repo, so all four of these
        # tests passed while the abort machinery was scoped to a path matching zero files. When the
        # source of truth was corrected on 2026-08-25 these four went RED, which is how a fixture that
        # encodes the bug announces itself. 🔴 Fixtures are an ORACLE: when one disagrees with
        # the repo, check which is wrong before making them agree.
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'agy-autotrain/docs/fix-the-tool-backlog') | Out-Null
        Set-Content (Join-Path $script:Repo 'agy-autotrain/docs/fix-the-tool-backlog/maintainer-note.md') 'unrelated untracked note'
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 1
        (Test-Path (Join-Path $script:Repo 'agy-autotrain/docs/fix-the-tool-backlog/maintainer-note.md')) | Should -Be $true
        (Get-Content (Join-Path $script:Repo 'docs/agy-golden-header.growth.md') -Raw).Trim() | Should -Be 'DRAINED GROWTH (unwanted)'
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1
    }

    It "PROCEEDS when the drain's own untracked output file exists (exact-match legitimacy still allows the real case)" {
        Set-Content (Join-Path $script:Repo 'docs/agy-verify-needed.md') '# agy verify-needed backlog'
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 0
        (Test-Path (Join-Path $script:Repo 'docs/agy-verify-needed.md')) | Should -Be $false
        (Get-Content (Join-Path $script:Repo 'docs/agy-golden-header.growth.md') -Raw).Trim() | Should -Be 'ORIGINAL GROWTH'
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 0
    }

    It "reverts even when the drain outputs were STAGED (reset --hard HEAD, not checkout-from-index)" {
        Push-Location $script:Repo
        git add 'docs/agy-golden-header.growth.md'
        Pop-Location
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 0
        (Get-Content (Join-Path $script:Repo 'docs/agy-golden-header.growth.md') -Raw).Trim() | Should -Be 'ORIGINAL GROWTH'
        Push-Location $script:Repo; $st = git status --porcelain; Pop-Location
        $st | Should -BeNullOrEmpty
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 0
    }

    It "PROCEEDS when the output manifest lists a backlog file that is present untracked (the ordinary abort path this feature unblocks)" {
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'agy-autotrain/docs/fix-the-tool-backlog') | Out-Null
        Set-Content (Join-Path $script:Repo 'agy-autotrain/docs/fix-the-tool-backlog/some-slug.md') 'curator-produced backlog entry'
        Set-Content (Join-Path $script:InboxDir 'agy-observations.staging.RID1.outputs.txt') 'agy-autotrain/docs/fix-the-tool-backlog/some-slug.md'
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 0
        (Test-Path (Join-Path $script:Repo 'agy-autotrain/docs/fix-the-tool-backlog/some-slug.md')) | Should -Be $false
        (Get-Content (Join-Path $script:Repo 'docs/agy-golden-header.growth.md') -Raw).Trim() | Should -Be 'ORIGINAL GROWTH'
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 0
    }

    It "REFUSES when a manifest exists but does NOT list an untracked file present under the backlog directory" {
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'agy-autotrain/docs/fix-the-tool-backlog') | Out-Null
        Set-Content (Join-Path $script:Repo 'agy-autotrain/docs/fix-the-tool-backlog/maintainer-note.md') 'unrelated untracked note'
        Set-Content (Join-Path $script:InboxDir 'agy-observations.staging.RID1.outputs.txt') 'agy-autotrain/docs/fix-the-tool-backlog/some-other-slug.md'
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 1
        (Test-Path (Join-Path $script:Repo 'agy-autotrain/docs/fix-the-tool-backlog/maintainer-note.md')) | Should -Be $true
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1
    }

    It "REFUSES with NO manifest present (legacy run) — the conservative fallback is unchanged" {
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'agy-autotrain/docs/fix-the-tool-backlog') | Out-Null
        Set-Content (Join-Path $script:Repo 'agy-autotrain/docs/fix-the-tool-backlog/some-slug.md') 'untracked file, no manifest to vouch for it'
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 1
        (Test-Path (Join-Path $script:Repo 'agy-autotrain/docs/fix-the-tool-backlog/some-slug.md')) | Should -Be $true
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1
    }

    It "deletes the manifest after a successful abort" {
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'agy-autotrain/docs/fix-the-tool-backlog') | Out-Null
        Set-Content (Join-Path $script:Repo 'agy-autotrain/docs/fix-the-tool-backlog/some-slug.md') 'curator-produced backlog entry'
        $manifestPath = Join-Path $script:InboxDir 'agy-observations.staging.RID1.outputs.txt'
        Set-Content $manifestPath 'agy-autotrain/docs/fix-the-tool-backlog/some-slug.md'
        & pwsh -File $script:Abort -InboxPath $script:Inbox -RepoRoot $script:Repo
        $LASTEXITCODE | Should -Be 0
        (Test-Path $manifestPath) | Should -Be $false
    }
}

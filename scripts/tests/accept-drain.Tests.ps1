# scripts/tests/accept-drain.Tests.ps1
BeforeAll {
    $script:Accept = Join-Path $PSScriptRoot '..' 'accept-drain.ps1'
    # curate-commit STUB scripts, created ONCE here (not per-test) to avoid AV/Defender file-lock flakiness on a
    # freshly-written stub the child pwsh immediately executes (agy escalation). Each is a PATH passed to accept-drain's
    # -CurateCommitStub seam: a live [scriptblock] cannot cross a `pwsh -File` boundary (PowerShell marshals it to the
    # literal "-encodedCommand"), so the seam is a stub-script path. The 'ok' stub writes a sentinel beside the growth
    # file recording the path it received, so a test can prove curate-commit was actually invoked with the proposal.
    $script:StubDir = Join-Path ([System.IO.Path]::GetTempPath()) ("acceptstub-" + [Guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:StubDir | Out-Null
    $script:StubOk       = Join-Path $script:StubDir 'ok.ps1'
    $script:StubFail     = Join-Path $script:StubDir 'fail.ps1'
    $script:StubNoDriver = Join-Path $script:StubDir 'nodriver.ps1'
    $script:StubNothing  = Join-Path $script:StubDir 'nothing.ps1'
    Set-Content -Path $script:StubOk -Value @(
        'param($growthPath)'
        'Set-Content -LiteralPath ($growthPath + ''.published'') -Value $growthPath'
        'return ''published'''
    )
    Set-Content -Path $script:StubFail     -Value @('param($growthPath)', 'return ''failed''')
    Set-Content -Path $script:StubNoDriver -Value @('param($growthPath)', 'return ''no-driver''')
    Set-Content -Path $script:StubNothing  -Value @('param($growthPath)', 'return ''nothing-to-publish''')
}
AfterAll { Remove-Item -Recurse -Force $script:StubDir -ErrorAction SilentlyContinue }

Describe "accept-drain transaction (scratch repo)" {
    BeforeAll {
        # Pester v5: a helper must live in BeforeAll (Run phase), not bare in the Describe body (Discovery-only, gone
        # by the time It blocks run). It reads $script:Repo lazily when CALLED, after BeforeEach has set it per-test.
        function Commit-Drain {
            Push-Location $script:Repo
            Add-Content 'docs/agy-drain-log.md' '## drain RID9 — x — GROWTH 17B — verify-needed: 0'
            git add .; git commit -qm drained
            Pop-Location
        }
    }
    BeforeEach {
        $script:Repo = Join-Path ([System.IO.Path]::GetTempPath()) ("accept-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'docs') | Out-Null
        Push-Location $script:Repo
        git init -q; git config user.email t@t; git config user.name t
        Set-Content 'docs/agy-drain-log.md' '# agy drain log'
        Set-Content 'docs/agy-golden-header.growth.md' '# GROWTH proposal'
        git add .; git commit -qm base
        Pop-Location
        $script:InboxDir = Join-Path ([System.IO.Path]::GetTempPath()) ("abox-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:InboxDir | Out-Null
        $script:Inbox = Join-Path $script:InboxDir 'agy-observations.md'
        Set-Content $script:Inbox @('# inbox', '', '## Pending')
        Set-Content (Join-Path $script:InboxDir 'agy-observations.staging.RID9.md') @('- [heuristic] r  ·  x')
        # The sentinel the 'ok' stub writes beside the growth file when curate-commit is actually invoked.
        $script:PublishSentinel = Join-Path $script:Repo 'docs/agy-golden-header.growth.md.published'
    }
    AfterEach { Remove-Item -Recurse -Force $script:Repo, $script:InboxDir -ErrorAction SilentlyContinue }

    It "publishes GROWTH to the runtime + deletes staging when committed and clean (F30/F34)" {
        Commit-Drain
        & pwsh -File $script:Accept -InboxPath $script:Inbox -RepoRoot $script:Repo -CurateCommitStub $script:StubOk
        $LASTEXITCODE | Should -Be 0
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 0
        (Test-Path $script:PublishSentinel) | Should -Be $true                              # curate-commit WAS invoked
        (Get-Content $script:PublishSentinel -Raw).Trim() | Should -Match 'agy-golden-header\.growth\.md$'
    }

    It "BLOCKS when the run-ID is only in the working-tree log, not committed (F30) — no publish" {
        Add-Content (Join-Path $script:Repo 'docs/agy-drain-log.md') '## drain RID9 — x — GROWTH 17B — verify-needed: 0'
        & pwsh -File $script:Accept -InboxPath $script:Inbox -RepoRoot $script:Repo -CurateCommitStub $script:StubOk
        $LASTEXITCODE | Should -Be 1
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1
        (Test-Path $script:PublishSentinel) | Should -Be $false
    }

    It "BLOCKS when the tree is dirty (F34) — no publish" {
        Commit-Drain
        Set-Content (Join-Path $script:Repo 'docs/agy-golden-header.growth.md') 'uncommitted edit'
        & pwsh -File $script:Accept -InboxPath $script:Inbox -RepoRoot $script:Repo -CurateCommitStub $script:StubOk
        $LASTEXITCODE | Should -Be 1
        (Test-Path $script:PublishSentinel) | Should -Be $false
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1
    }

    It "FAILS and RETAINS staging when curate-commit reports failure (runtime publish must succeed before staging is deleted)" {
        Commit-Drain
        & pwsh -File $script:Accept -InboxPath $script:Inbox -RepoRoot $script:Repo -CurateCommitStub $script:StubFail
        $LASTEXITCODE | Should -Be 1
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1
    }

    It "RETAINS staging + exit 1 when no clavity driver is installed, so the 'install + re-run' recovery works (panel agy-R2-3)" {
        Commit-Drain
        & pwsh -File $script:Accept -InboxPath $script:Inbox -RepoRoot $script:Repo -CurateCommitStub $script:StubNoDriver
        $LASTEXITCODE | Should -Be 1
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1   # retained → re-run finds the pending drain
    }

    It "PROCEEDS (deletes staging, exit 0) when there is no GROWTH proposal to publish (docs-only drain)" {
        Commit-Drain
        & pwsh -File $script:Accept -InboxPath $script:Inbox -RepoRoot $script:Repo -CurateCommitStub $script:StubNothing
        $LASTEXITCODE | Should -Be 0
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 0
    }

    It "hard-fails (exit 1) and RETAINS staging when 'git status' fails (corrupt index; F34 fail-closed)" {
        Commit-Drain
        Set-Content -Path (Join-Path $script:Repo '.git/index') -Value 'garbage not an index' -NoNewline
        & pwsh -File $script:Accept -InboxPath $script:Inbox -RepoRoot $script:Repo -CurateCommitStub $script:StubOk
        $LASTEXITCODE | Should -Be 1
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1
    }

    It "-WhatIf previews without publishing to the runtime or deleting staging (panel F1/agy-A3)" {
        Commit-Drain
        & pwsh -File $script:Accept -InboxPath $script:Inbox -RepoRoot $script:Repo -CurateCommitStub $script:StubOk -WhatIf
        (Test-Path $script:PublishSentinel) | Should -Be $false                             # publish NOT invoked under -WhatIf
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1   # staging NOT deleted
    }

    It "accept-drain.ps1 dot-sources drain-lib so the REAL default's Resolve/Invoke-CurateCommit resolve (agy-R3-1)" {
        # Every functional test above injects -CurateCommitStub, which bypasses the production default. This structural
        # pin proves the default's dependency is actually wired: without this dot-source the default branch would throw
        # CommandNotFoundException on Resolve-CurateCommitExe. (The full end-to-end default — Resolve + Invoke against a
        # REAL clavity binary — is inherently live-only; see the risks section.)
        (Get-Content $script:Accept -Raw) | Should -Match "drain-lib\.ps1"
    }
}

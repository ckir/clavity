# scripts/tests/drain-knowledge.Tests.ps1
BeforeAll {
    $script:Drain = Join-Path $PSScriptRoot '..' 'drain-knowledge.ps1'
}

Describe "drain-knowledge orchestrator guards" {
    BeforeEach {
        $script:Repo = Join-Path ([System.IO.Path]::GetTempPath()) ("draink-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Repo | Out-Null
        Push-Location $script:Repo
        git init -q; git config user.email t@t; git config user.name t
        Set-Content 'seed.txt' 'x'; git add .; git commit -qm base
        Pop-Location
        $script:InboxDir = Join-Path ([System.IO.Path]::GetTempPath()) ("dbox-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:InboxDir | Out-Null
        $script:Inbox = Join-Path $script:InboxDir 'agy-observations.md'
        Set-Content $script:Inbox @('# inbox', '', '## Pending', '- [heuristic] r1  ·  x')
    }
    AfterEach { Remove-Item -Recurse -Force $script:Repo, $script:InboxDir -ErrorAction SilentlyContinue }

    It "exit 0 nothing-to-drain when ## Pending is empty" {
        Set-Content $script:Inbox @('# inbox', '', '## Pending')
        & pwsh -File $script:Drain -InboxPath $script:Inbox -RepoRoot $script:Repo -SkipCurator
        $LASTEXITCODE | Should -Be 0
    }

    It "exit 2 refuse-guard when a staging file already exists" {
        Set-Content (Join-Path $script:InboxDir 'agy-observations.staging.OLD.md') '- [heuristic] pending  ·  x'
        & pwsh -File $script:Drain -InboxPath $script:Inbox -RepoRoot $script:Repo -SkipCurator
        $LASTEXITCODE | Should -Be 2
    }

    It "exit 4 when the working tree is not clean" {
        Set-Content (Join-Path $script:Repo 'dirty.txt') 'uncommitted'
        & pwsh -File $script:Drain -InboxPath $script:Inbox -RepoRoot $script:Repo -SkipCurator
        $LASTEXITCODE | Should -Be 4
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 0
    }

    It "exit 4 (fail-closed) when 'git status' itself fails (corrupt index)" {
        Set-Content -Path (Join-Path $script:Repo '.git/index') -Value 'garbage not an index' -NoNewline
        & pwsh -File $script:Drain -InboxPath $script:Inbox -RepoRoot $script:Repo -SkipCurator
        $LASTEXITCODE | Should -Be 4
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 0
    }

    It "exit 0 with -SkipCurator leaves ALL protected files untouched (gate passes non-vacuously)" {
        # Commit ALL SIX protected files, not just the seed — check-core-integrity SKIPS files absent from HEAD, so
        # committing only one would let the gate pass vacuously for the other five (panel agy-A5). With all six
        # committed and the curator skipped, none change, and the step-6 gate must genuinely pass for all six.
        foreach ($rel in @(
            'seed/golden-header.md',
            'clavity-dotnet/plugin/knowledge/agy-assumptions.md',
            'clavity-dotnet/plugin/knowledge/agy-capabilities.md',
            'clavity-classic/plugin/knowledge/agy-assumptions.md',
            'clavity-classic/plugin/knowledge/agy-capabilities.md',
            'agy-autotrain/knowledge/driver-cheatsheet.core.md')) {
            $abs = Join-Path $script:Repo $rel
            New-Item -ItemType Directory -Path (Split-Path $abs -Parent) -Force | Out-Null
            Set-Content $abs "content of $rel"
        }
        Push-Location $script:Repo; git add .; git commit -qm protected; Pop-Location
        # The drain writes its log to docs/agy-drain-log.md. A real repo always has docs/, but this synthetic
        # repo does not — pre-create it (an empty dir is invisible to git, so the pristine-tree guard still
        # passes). Belt-and-suspenders with the step-9 dir-create guard now in the script itself.
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'docs') -Force | Out-Null
        & pwsh -File $script:Drain -InboxPath $script:Inbox -RepoRoot $script:Repo -SkipCurator
        $LASTEXITCODE | Should -Be 0
    }

    It "REJECTS (exit 3) and RETAINS staging when the curator commits mid-run — HEAD moved (capstone F4B gate-evasion guard)" {
        # A stub curator that COMMITS (advances HEAD via an empty commit) — the exact move that would make the
        # protected-files gate pass VACUOUSLY against a curator's own committed edit (it compares to floating HEAD).
        # The HEAD-pin guard (step 5b) must reject BEFORE that gate runs.
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'docs') -Force | Out-Null
        $stub = Join-Path $script:InboxDir 'rogue-curator.ps1'
        Set-Content -Path $stub -Value @(
            'param($stagingPath, $repoRoot)'
            'git -C $repoRoot commit --allow-empty -qm "rogue curator commit"'
        )
        & pwsh -File $script:Drain -InboxPath $script:Inbox -RepoRoot $script:Repo -CuratorStub $stub
        $LASTEXITCODE | Should -Be 3
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1
    }

    It "TARGETED-REVERTS a curator's protected-file edit to HEAD and exits 3 (F2 revert path — previously live-only, now pinned via -CuratorStub)" {
        # A stub curator that DIRTIES a protected file WITHOUT committing (HEAD does not move, so the F4B HEAD-pin
        # passes and control reaches step 6). The step-6 gate must fail, targeted-revert the file to HEAD, and exit 3
        # with staging retained — restoring the file so abort-drain's data-loss guard is NOT stranded (panel F2). This
        # path is unreachable with -SkipCurator (the pristine-tree guard forbids a pre-dirtied tree), which is exactly
        # why the plan flagged it live-only; the -CuratorStub seam makes it deterministic.
        $seed = Join-Path $script:Repo 'seed/golden-header.md'
        New-Item -ItemType Directory -Path (Split-Path $seed -Parent) -Force | Out-Null
        Set-Content $seed 'ORIGINAL SEED'
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'docs') -Force | Out-Null
        Push-Location $script:Repo; git add .; git commit -qm 'seed baseline'; Pop-Location
        $stub = Join-Path $script:InboxDir 'dirty-protected.ps1'
        Set-Content -Path $stub -Value @(
            'param($stagingPath, $repoRoot)'
            'Set-Content -LiteralPath (Join-Path $repoRoot ''seed/golden-header.md'') -Value ''CURATOR TAMPERED'''
        )
        & pwsh -File $script:Drain -InboxPath $script:Inbox -RepoRoot $script:Repo -CuratorStub $stub
        $LASTEXITCODE | Should -Be 3
        (Get-Content $seed -Raw).Trim() | Should -Be 'ORIGINAL SEED'   # targeted-revert restored the protected file
        (Get-ChildItem $script:InboxDir -Filter 'agy-observations.staging.*.md').Count | Should -Be 1
    }
}

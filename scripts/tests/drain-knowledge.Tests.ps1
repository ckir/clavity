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
}

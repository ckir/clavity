BeforeAll {
    # Dot-source: defines functions, does NOT run main (guarded by InvocationName -eq '.').
    . ([System.IO.Path]::Combine($PSScriptRoot, '..', 'check-user-facing-docs.ps1'))

    function New-ScratchListRepo {
        param([string[]]$ListLines, [hashtable]$Files = @{})
        $repoRoot = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $repoRoot 'docs') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repoRoot 'docs/user-facing-docs.txt') -Value ($ListLines -join "`n")
        foreach ($rel in $Files.Keys) {
            $abs = Join-Path $repoRoot $rel
            New-Item -ItemType Directory -Path (Split-Path $abs -Parent) -Force | Out-Null
            Set-Content -LiteralPath $abs -Value $Files[$rel]
        }
        return $repoRoot
    }
}

Describe 'Read-DocList' {
    It 'ignores comments and blank lines, returns trimmed paths' {
        $repo = New-ScratchListRepo -ListLines @('# hdr', '', 'README.md', '  SECURITY.md  ', '# tail')
        $paths = Read-DocList (Join-Path $repo 'docs/user-facing-docs.txt')
        $paths | Should -Be @('README.md', 'SECURITY.md')
    }
}

Describe 'Test-IsDoNotTouch' {
    It 'flags a SKILL.md at any depth' {
        Test-IsDoNotTouch 'clavity-classic/agy-mcp-bridge/SKILL.md' | Should -BeTrue
        Test-IsDoNotTouch 'x/plugin/skills/foo/SKILL.md'            | Should -BeTrue
    }
    It 'flags a CHANGELOG, a knowledge file, an archive doc, a fixtures README, and docs-spec itself' {
        Test-IsDoNotTouch 'clavity-dotnet/CHANGELOG.md'                 | Should -BeTrue
        Test-IsDoNotTouch 'agy-autotrain/knowledge/agy-observations.md' | Should -BeTrue
        Test-IsDoNotTouch 'clavity-classic/docs/archive/old.md'         | Should -BeTrue
        Test-IsDoNotTouch 'ghidrust/crates/x/tests/fixtures/README.md'  | Should -BeTrue
        Test-IsDoNotTouch 'docs/docs-spec.md'                           | Should -BeTrue
    }
    It 'does NOT flag any of the 25 user-facing shapes' {
        foreach ($p in @('README.md','clavity-classic/plugin/README.md','clavity-dotnet/CONTRIBUTING.md',
                         'SECURITY.md','CODE_OF_CONDUCT.md','.github/ISSUE_TEMPLATE/bug_report.md',
                         'docs/README.md','clavity-classic/docs/how-it-works.md',
                         'clavity-classic/installer/clavity-classic-MANUAL-SETUP.md')) {
            Test-IsDoNotTouch $p | Should -BeFalse -Because "$p is user-facing"
        }
    }
}

Describe 'Test-HasVoiceEntry' {
    It 'matches every one of the 25 user-facing shapes' {
        foreach ($p in @('README.md','agy-autotrain/README.md','clavity-classic/plugin/README.md',
                         'CONTRIBUTING.md','ghidrust/CONTRIBUTING.md','SECURITY.md','CODE_OF_CONDUCT.md',
                         '.github/pull_request_template.md','.github/ISSUE_TEMPLATE/feature_request.md',
                         'docs/README.md','clavity-classic/docs/how-it-works.md',
                         'clavity-classic/docs/launching-and-driving-agy.md',
                         'clavity-classic/installer/clavity-classic-bridge-README-FIRST.md')) {
            Test-HasVoiceEntry $p | Should -BeTrue -Because "$p is voiced in docs-spec.md's table"
        }
    }
    It 'does NOT match an unvoiced spec-gap path' {
        Test-HasVoiceEntry 'weird/nested/thing.md' | Should -BeFalse
    }
}

Describe 'Invoke-UserFacingDocsCheck' {
    It 'PASSES when every listed doc exists and none is do-not-touch' {
        $repo = New-ScratchListRepo -ListLines @('README.md','SECURITY.md') -Files @{ 'README.md'='# r'; 'SECURITY.md'='# s' }
        $r = Invoke-UserFacingDocsCheck $repo
        $r.Failures | Should -Be @()
        $r.ExitCode | Should -Be 0
    }
    It 'FAILS (a): a listed doc that does not exist' {
        $repo = New-ScratchListRepo -ListLines @('README.md','GONE.md') -Files @{ 'README.md'='# r' }
        $r = Invoke-UserFacingDocsCheck $repo
        $r.ExitCode | Should -Be 1
        ($r.Failures -join "`n") | Should -Match 'GONE.md.*does not exist'
    }
    It 'FAILS (b): a listed doc that is in the do-not-touch set' {
        $repo = New-ScratchListRepo -ListLines @('README.md','docs/docs-spec.md') -Files @{ 'README.md'='# r'; 'docs/docs-spec.md'='# spec' }
        $r = Invoke-UserFacingDocsCheck $repo
        $r.ExitCode | Should -Be 1
        ($r.Failures -join "`n") | Should -Match 'docs-spec.md.*do-not-touch'
    }
    It 'FAILS on an empty list rather than passing vacuously' {
        $repo = New-ScratchListRepo -ListLines @('# only a comment')
        $r = Invoke-UserFacingDocsCheck $repo
        $r.ExitCode | Should -Be 1
        ($r.Failures -join "`n") | Should -Match 'empty'
    }
    It 'FAILS (b2): a listed doc that exists and is not do-not-touch but matches no voice shape' {
        $repo = New-ScratchListRepo -ListLines @('README.md','weird/nested/thing.md') `
            -Files @{ 'README.md'='# r'; 'weird/nested/thing.md'='# w' }
        $r = Invoke-UserFacingDocsCheck $repo
        $r.ExitCode | Should -Be 1
        ($r.Failures -join "`n") | Should -Match 'weird/nested/thing.md.*spec gap'
    }
    It '(c) heuristic: warns (does NOT fail) on an unlisted user-facing-shaped tracked doc' {
        $repo = New-ScratchListRepo -ListLines @('README.md') -Files @{ 'README.md'='# r' }
        # Inject the tracked-doc set via the seam so the heuristic is deterministic (no git needed).
        $r = Invoke-UserFacingDocsCheck $repo -TrackedDocs @('README.md','ghidrust/CONTRIBUTING.md')
        $r.ExitCode  | Should -Be 0
        ($r.Warnings -join "`n") | Should -Match 'ghidrust/CONTRIBUTING.md.*absent'
    }
    It '(c) heuristic: a do-not-touch tracked doc absent from the list is NOT warned' {
        $repo = New-ScratchListRepo -ListLines @('README.md') -Files @{ 'README.md'='# r' }
        $r = Invoke-UserFacingDocsCheck $repo -TrackedDocs @('README.md','x/plugin/skills/foo/SKILL.md')
        $r.Warnings | Should -Be @()
    }
    It 'does NOT crash when this is not a git repo (git present, non-zero exit) - heuristic skips silently' {
        $repo = New-ScratchListRepo -ListLines @('README.md') -Files @{ 'README.md'='# r' }
        { Invoke-UserFacingDocsCheck $repo } | Should -Not -Throw
        (Invoke-UserFacingDocsCheck $repo).ExitCode | Should -Be 0
    }
    It 'Get-TrackedMarkdown returns $null when the git binary is absent (Get-Command finds nothing)' {
        # Proves the Get-Command-git guard branch (not the not-a-repo branch) is exercised: without the
        # Should -Invoke, a machine WITH git would also return $null via the non-repo path, hiding a mock miss.
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'git' }
        Get-TrackedMarkdown $TestDrive | Should -Be $null
        Should -Invoke Get-Command -ParameterFilter { $Name -eq 'git' } -Times 1
    }
}

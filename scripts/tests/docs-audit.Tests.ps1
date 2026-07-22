# scripts/tests/docs-audit.Tests.ps1
BeforeAll {
    $script:Lib   = Join-Path $PSScriptRoot '..' 'docs-audit-lib.ps1'
    $script:Audit = Join-Path $PSScriptRoot '..' 'docs-audit.ps1'
    . $script:Lib   # dot-source: defines functions only (no orchestrator)
}

Describe 'Read-DocList / Get-InScopeDocs' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ('r-' + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $script:Root 'docs') -Force | Out-Null
        Set-Content (Join-Path $script:Root 'docs/user-facing-docs.txt') @(
            '# a comment', '', 'README.md', 'SECURITY.md', '   ', 'CONTRIBUTING.md  # trailing note')
        foreach ($f in 'README.md','SECURITY.md','CONTRIBUTING.md') { Set-Content (Join-Path $script:Root $f) 'x' }
    }

    It 'reads the list, ignoring comments and blank lines' {
        (Read-DocList (Join-Path $script:Root 'docs/user-facing-docs.txt')) |
            Should -Be @('README.md','SECURITY.md','CONTRIBUTING.md')
    }
    It 'full list by default' {
        (Get-InScopeDocs -RepoRoot $script:Root -Only @()).Count | Should -Be 3
    }
    It 'a narrowing arg audits only the named subset' {
        Get-InScopeDocs -RepoRoot $script:Root -Only @('SECURITY.md') | Should -Be @('SECURITY.md')
    }
    It 'a narrowing arg for a path NOT on the list is dropped (never audits off-list docs)' {
        Get-InScopeDocs -RepoRoot $script:Root -Only @('SECURITY.md','not-listed.md') | Should -Be @('SECURITY.md')
    }
    It "preserves a '#' inside a real filename and still drops whole-line comments (agy R6-F2)" {
        $p = Join-Path $script:Root 'docs/hashy.txt'
        Set-Content $p @('# whole-line comment', '   # indented comment', 'C#-guide.md', 'README.md  # trailing note', '')
        Read-DocList $p | Should -Be @('C#-guide.md', 'README.md')
    }
}

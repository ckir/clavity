BeforeAll { . (Join-Path $PSScriptRoot '..' 'lib' 'release-lib.ps1') }

Describe 'Get-BumpLevel (F7/F10)' {
    It 'any ! => breaking, regardless of type' {
        Get-BumpLevel @('chore!: drop win10') | Should -Be 'breaking'
        Get-BumpLevel @('feat(ui)!: x')        | Should -Be 'breaking'
    }
    It 'case-insensitive; Fix:/FEAT: are not dropped' {
        Get-BumpLevel @('FEAT: x') | Should -Be 'minor'
        Get-BumpLevel @('Fix: y')  | Should -Be 'patch'
    }
    It 'feat=minor, fix/revert=patch, chore/ci/docs=none' {
        Get-BumpLevel @('feat: x')   | Should -Be 'minor'
        Get-BumpLevel @('revert: y') | Should -Be 'patch'
        Get-BumpLevel @('chore: z','ci: w','docs: d') | Should -Be 'none'
    }
    It 'precedence: breaking beats minor beats patch' {
        Get-BumpLevel @('fix: a','feat: b','refactor!: c') | Should -Be 'breaking'
        Get-BumpLevel @('fix: a','feat: b')                | Should -Be 'minor'
    }
    It 'a non-conventional subject does not raise the level' {
        Get-BumpLevel @('fixed the crash','fix: real') | Should -Be 'patch'
    }
}

Describe 'Test-Conventional' {
    It 'flags non-conforming subjects' {
        Test-Conventional 'fix: x'          | Should -BeTrue
        Test-Conventional 'fixed the crash' | Should -BeFalse
        Test-Conventional 'FEAT(a)!: x'     | Should -BeTrue
    }
}

Describe 'Step-SemverVersion (F3 pre-1.0 rule)' {
    It '<1.0.0 never auto-crosses to 1.0.0' {
        Step-SemverVersion '0.1.0' 'breaking' | Should -Be '0.2.0'
        Step-SemverVersion '0.1.2' 'minor'    | Should -Be '0.2.0'
        Step-SemverVersion '0.1.2' 'patch'    | Should -Be '0.1.3'
    }
    It '>=1.0.0 uses normal semver' {
        Step-SemverVersion '1.0.0' 'breaking' | Should -Be '2.0.0'
        Step-SemverVersion '1.4.2' 'minor'    | Should -Be '1.5.0'
        Step-SemverVersion '1.4.2' 'patch'    | Should -Be '1.4.3'
    }
    It 'rejects a non-semver current' {
        { Step-SemverVersion '1.2' 'patch' } | Should -Throw
    }
}

Describe 'Read-IssVersion' {
    It 'reads #define AppVersion' {
        $f = New-TemporaryFile
        Set-Content $f '#define AppVersion "0.4.1"' -NoNewline
        Read-IssVersion $f | Should -Be '0.4.1'
        Remove-Item $f
    }
}

Describe 'Format-Sanitized (F14)' {
    It 'clamps to one line, escapes table-breakers, strips control chars' {
        Format-Sanitized "feat: a | b`nc"       | Should -Be 'feat: a \| b c'
        Format-Sanitized "fix: `t tab`r end"    | Should -Match 'fix:'
        (Format-Sanitized "x`nlie") -notmatch "`n" | Should -BeTrue
    }
    It 'escapes a leading HTML/comment opener' {
        Format-Sanitized '<!-- sneaky' | Should -Be '&lt;!-- sneaky'
    }
}

Describe 'Group-Notes (F10 grouping)' {
    It 'routes ! to Breaking, feat to Features, fix/revert to Fixes' {
        $g = Group-Notes @('feat!: big','feat: nice','fix: bug','revert: oops','chore: skip')
        $g.Breaking | Should -Be @('feat!: big')
        $g.Features | Should -Be @('feat: nice')
        $g.Fixes    | Should -Be @('fix: bug','revert: oops')
    }
}

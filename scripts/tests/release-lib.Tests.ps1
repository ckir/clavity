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

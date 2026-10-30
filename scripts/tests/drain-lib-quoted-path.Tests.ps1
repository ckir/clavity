<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

# scripts/tests/drain-lib-quoted-path.Tests.ps1
BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'drain-lib.ps1')
}

Describe "ConvertFrom-DrainGitQuotedPath" {
    It "returns an unquoted field unchanged" {
        ConvertFrom-DrainGitQuotedPath 'plain/path.md' | Should -Be 'plain/path.md'
    }
    It 'decodes escaped backslash and escaped quote' {
        ConvertFrom-DrainGitQuotedPath '"back\\slash\"q.txt"' | Should -Be 'back\slash"q.txt'
    }
    It 'decodes an escaped backslash directly before an escaped quote in one pass' {
        ConvertFrom-DrainGitQuotedPath '"a\\\"b"' | Should -Be 'a\"b'
    }
    It "decodes tab and newline escapes" {
        ConvertFrom-DrainGitQuotedPath '"tab\tx\ny"' | Should -Be "tab`tx`ny"
    }
    It "decodes octal UTF-8 byte runs (core.quotepath=true non-ASCII)" {
        ConvertFrom-DrainGitQuotedPath '"caf\303\251.txt"' | Should -Be ('caf' + [char]0xE9 + '.txt')
    }
    It "leaves an unknown escape untouched rather than dropping it" {
        ConvertFrom-DrainGitQuotedPath '"a\qb"' | Should -Be 'a\qb'
    }
}

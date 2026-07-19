BeforeAll {
    # Dot-source: defines functions, does NOT run main (guarded by $MyInvocation.InvocationName -eq '.').
    . ([System.IO.Path]::Combine($PSScriptRoot, '..', 'check-member-docs.ps1'))
    $script:BOM = [char]0xFEFF
}

Describe 'Remove-Bom' {
    It 'strips a leading U+FEFF' {
        Remove-Bom "$script:BOM# title" | Should -Be '# title'
    }
    It 'leaves text without a BOM unchanged' {
        Remove-Bom '# title' | Should -Be '# title'
    }
    It 'returns empty string for null or empty input' {
        Remove-Bom $null | Should -Be ''
        Remove-Bom ''    | Should -Be ''
    }
}

Describe 'Resolve-MemberShape' {
    It 'classifies a code+plugin source and derives the folder' {
        $r = Resolve-MemberShape './clavity-dotnet/plugin'
        $r.Shape  | Should -Be 'code+plugin'
        $r.Folder | Should -Be 'clavity-dotnet'
    }
    It 'classifies a plugin-only source and derives the folder' {
        $r = Resolve-MemberShape './agy-autotrain'
        $r.Shape  | Should -Be 'plugin-only'
        $r.Folder | Should -Be 'agy-autotrain'
    }
    It 'normalizes backslashes and a missing ./ prefix' {
        (Resolve-MemberShape '.\ghidrust\plugin').Folder | Should -Be 'ghidrust'
        (Resolve-MemberShape 'ghidrust/plugin').Folder   | Should -Be 'ghidrust'
    }
    It 'normalizes a trailing slash' {
        (Resolve-MemberShape './commonmemory/').Folder | Should -Be 'commonmemory'
    }
    It 'rejects a degenerate source that would resolve to the repo root' {
        { Resolve-MemberShape '.'   } | Should -Throw
        { Resolve-MemberShape './'  } | Should -Throw
        { Resolve-MemberShape ''    } | Should -Throw
    }
    It 'rejects a source containing a parent-directory component' {
        { Resolve-MemberShape '..'          } | Should -Throw
        { Resolve-MemberShape '../elsewhere' } | Should -Throw
    }
    It 'rejects a source matching neither shape rather than silently skipping it' {
        { Resolve-MemberShape './a/b/c' } | Should -Throw
    }
}

Describe 'Test-LeadingH1' {
    It 'accepts a level-1 heading' {
        Test-LeadingH1 "# title`n`nbody" | Should -BeTrue
    }
    It 'accepts a level-1 heading in a CRLF file' {
        Test-LeadingH1 "# title`r`n`r`nbody" | Should -BeTrue
    }
    It 'accepts a level-1 heading behind a BOM' {
        Test-LeadingH1 "$script:BOM# title`n`nbody" | Should -BeTrue
    }
    It 'rejects a level-2 heading' {
        Test-LeadingH1 "## 1.2.3`n`nbody" | Should -BeFalse
    }
    It 'rejects an empty file without throwing' {
        Test-LeadingH1 ''    | Should -BeFalse
        Test-LeadingH1 $null | Should -BeFalse
    }
    It 'rejects a file whose first line is blank' {
        Test-LeadingH1 "`n# title`n" | Should -BeFalse
    }
}

Describe 'Test-ChangelogContract' {
    It 'accepts the shape every member ships today' {
        Test-ChangelogContract "# dotnet changelog`n`n## 1.0.0`n" | Should -BeTrue
    }
    It 'rejects an H1 with no trailing newline (release-lib would blind-prepend)' {
        Test-ChangelogContract '# dotnet changelog' | Should -BeFalse
    }
    It 'rejects a level-2 first heading even though release-lib regex matches it' {
        # release-lib would "match" and inject INSIDE the previous release's body.
        $h2 = "## 1.2.0 - 2026-07-01`n`n### Fixes`n- old`n"
        $h2 -match '(?s)^(#[^\n]*\n+)(.*)$' | Should -BeTrue   # the oracle matches...
        Test-ChangelogContract $h2           | Should -BeFalse  # ...and we are deliberately stricter
    }
    It 'ACCEPTS a changelog whose text still carries a BOM character' {
        # A BOM is NOT a failure. Measured: Get-Content -Raw strips it during encoding detection in
        # BOTH Windows PowerShell 5.1 and pwsh 7, and release-lib.ps1:221 reads the file the same way,
        # so a BOM-prefixed CHANGELOG is benign. Rejecting it would invent a rule the release
        # machinery does not have and fail a perfectly valid file.
        Test-ChangelogContract "$script:BOM# t`n`nbody" | Should -BeTrue
    }
    It 'rejects empty input without throwing' {
        Test-ChangelogContract '' | Should -BeFalse
    }
}

Describe 'Read-Doc' {
    It 'returns $null for an absent file' {
        Read-Doc (Join-Path $TestDrive 'nope.md') | Should -BeNullOrEmpty
        $null -eq (Read-Doc (Join-Path $TestDrive 'nope.md')) | Should -BeTrue
    }
    It 'returns empty string (NOT $null) for a zero-byte file, so it reads as present-but-empty' {
        $p = Join-Path $TestDrive 'empty.md'
        Set-Content -LiteralPath $p -Value '' -NoNewline
        $null -eq (Read-Doc $p) | Should -BeFalse
        Read-Doc $p             | Should -Be ''
    }
}

Describe 'Get-HeadingCount' {
    It 'counts level-2 headings only' {
        Get-HeadingCount "# t`n## a`n### b`n## c`n" | Should -Be 2
    }
    It 'returns 0 for empty input' {
        Get-HeadingCount '' | Should -Be 0
    }
}

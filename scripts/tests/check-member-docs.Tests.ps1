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

Describe 'Test-H1NamesMember (wrong-product defect-class gate)' {
    It 'accepts a bare H1 that IS exactly the member name' {
        Test-H1NamesMember "# ghidrust`n`nbody" 'ghidrust' | Should -BeTrue
    }
    It 'accepts a decorated title that mentions the member (em-dash tagline)' {
        Test-H1NamesMember "# clavity-classic - required manual wiring`n`nbody" 'clavity-classic' | Should -BeTrue
    }
    It 'accepts a decorated title that mentions the member (colon tagline)' {
        Test-H1NamesMember "# clavity-dotnet: the MCP language server`n`nbody" 'clavity-dotnet' | Should -BeTrue
    }
    It 'is case-insensitive' {
        Test-H1NamesMember "# CLAVITY-DOTNET`n`nbody" 'clavity-dotnet' | Should -BeTrue
    }
    It 'rejects an H1 that names a DIFFERENT member' {
        Test-H1NamesMember "# ghidrust`n`nbody" 'clavity-dotnet' | Should -BeFalse
    }
    It 'rejects the substring trap: a bare ancestor-ish name for a longer member' {
        # 'clavity-dotnet' contains the substring 'clavity', so a naive "member name contains the H1"
        # check would wrongly PASS here. We test the other direction (H1 contains the member name),
        # which correctly fails: 'clavity' does not contain 'clavity-dotnet'.
        Test-H1NamesMember "# clavity`n`nbody" 'clavity-dotnet' | Should -BeFalse
    }
    It 'rejects empty input without throwing' {
        Test-H1NamesMember '' 'clavity-dotnet' | Should -BeFalse
    }
}

Describe 'Invoke-DocCheck - README title must name its member (defect-class gate, end to end)' {
    # Builds a fully self-contained scratch repo under $TestDrive - it never reads or writes the real
    # repo. Invoke-DocCheck also runs a global template-substance check independent of any member, so
    # the scratch repo includes minimal but conforming fake templates to isolate each test to exactly
    # the README-naming assertion under test.
    BeforeAll {
        # Pester v5 gotcha: code in a Describe body (outside BeforeAll/It) runs only during Discovery
        # and is gone by the time It blocks execute in the Run phase. The helper MUST be defined here.
        function New-ScratchDocRepo([string]$MemberName, [string]$FolderName, [string]$ReadmeFirstLine) {
            $repoRoot = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('N'))
            $buildDir = Join-Path $repoRoot 'build'
            New-Item -ItemType Directory -Path $buildDir -Force | Out-Null

            $manifest = [PSCustomObject]@{
                members = @(
                    [PSCustomObject]@{ name = $MemberName; source = "./$FolderName" }
                )
            }
            ($manifest | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $buildDir 'members.json')

            $memberDir = Join-Path $repoRoot $FolderName
            New-Item -ItemType Directory -Path $memberDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $memberDir 'README.md') -Value "$ReadmeFirstLine`n`nbody`n"
            Set-Content -LiteralPath (Join-Path $memberDir 'CHANGELOG.md') -Value "# changelog`n`n## 1.0.0`n"

            $tplDir = Join-Path (Join-Path (Join-Path $repoRoot 'clavity-dotnet') 'templates') 'tool-skeleton'
            New-Item -ItemType Directory -Path $tplDir -Force | Out-Null
            $fourSections = "# t`n`n## a`n## b`n## c`n## d`n"
            foreach ($name in @('README.md.template', 'README-plugin-only.md.template', 'plugin-README.md.template')) {
                Set-Content -LiteralPath (Join-Path $tplDir $name) -Value $fourSections
            }
            Set-Content -LiteralPath (Join-Path $tplDir 'CHANGELOG.md.template') -Value "# changelog`n`n## 1.0.0`n"

            return $repoRoot
        }
    }

    It 'FAILS when the README H1 names a DIFFERENT member, and the message names the member' {
        $repoRoot = New-ScratchDocRepo -MemberName 'clavity-classic' -FolderName 'clavity-classic' -ReadmeFirstLine '# ghidrust'
        $result = Invoke-DocCheck $repoRoot
        $result.ExitCode | Should -Be 1
        ($result.Failures -join "`n") | Should -Match "member 'clavity-classic'.*does not name member 'clavity-classic'"
    }

    It 'FAILS on the substring-trap regression: bare "# clavity" for member clavity-dotnet' {
        $repoRoot = New-ScratchDocRepo -MemberName 'clavity-dotnet' -FolderName 'clavity-dotnet' -ReadmeFirstLine '# clavity'
        $result = Invoke-DocCheck $repoRoot
        $result.ExitCode | Should -Be 1
        ($result.Failures -join "`n") | Should -Match "member 'clavity-dotnet'.*does not name member 'clavity-dotnet'"
    }

    It 'PASSES for a legitimate decorated title that names the member' {
        $repoRoot = New-ScratchDocRepo -MemberName 'clavity-dotnet' -FolderName 'clavity-dotnet' -ReadmeFirstLine '# clavity-dotnet - the MCP language server'
        $result = Invoke-DocCheck $repoRoot
        $result.Failures | Should -Be @()
        $result.ExitCode | Should -Be 0
    }
}

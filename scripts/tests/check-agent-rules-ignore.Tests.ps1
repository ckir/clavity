<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

BeforeAll {
    . ([System.IO.Path]::Combine($PSScriptRoot, '..', 'check-agent-rules-ignore.ps1'))
    $script:Ignore = "target/`n.clavity/`nclavity-dotnet/pairing/`ndocs/hidden-plan.md`n*.log`n!keep.log`ncoverage/`ncafé/`n"
    function New-RuleRepo {
        param([hashtable]$Files, [string]$Ignore = $script:Ignore, [switch]$NoIgnore)
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        git -C $repo init -q --template= 2>$null
        if (-not $NoIgnore) { [IO.File]::WriteAllText((Join-Path $repo '.antigravityignore'), $Ignore) }
        foreach ($rel in $Files.Keys) {
            $abs = Join-Path $repo $rel
            New-Item -ItemType Directory -Path (Split-Path $abs -Parent) -Force | Out-Null
            [IO.File]::WriteAllText($abs, $Files[$rel])
        }
        git -C $repo add -A 2>$null
        return $repo
    }
    function Invoke-Check([string]$repo) { Invoke-AgentRulesIgnoreCheck -RepoRoot $repo -ScratchParent $TestDrive }
}

Describe 'Invoke-AgentRulesIgnoreCheck' {
    It 'passes a clean file and reports the census' {
        $r = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "Run ``just test`` in ``scripts/``.`n" })
        $r.ExitCode | Should -Be 0; $r.FileCount | Should -Be 1; $r.ReferenceCount | Should -BeGreaterThan 0
    }
    It 'passes with zero rule files and FileCount 0' {
        $r = Invoke-Check (New-RuleRepo @{ 'README.md' = 'x' }); $r.ExitCode | Should -Be 0; $r.FileCount | Should -Be 0
    }
    It 'flags a hidden path in a code span, with file, line and pattern' {
        $r = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "ok`nsee ``clavity-dotnet/pairing/README.md```n" })
        $r.ExitCode | Should -Be 1
        $r.Hits[0] | Should -BeLike 'AGENTS.md:2  clavity-dotnet/pairing/README.md  ->  .antigravityignore:3:clavity-dotnet/pairing/'
    }
    It 'flags a hidden path inside a fenced block' {
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "``````bash`ncat .clavity/x.md`n```````n" })).ExitCode | Should -Be 1
    }
    It 'flags a hidden link target, a bare prose path and a dot-folder named in prose' {
        foreach ($t in @('[p](clavity-dotnet/pairing/)', 'look in clavity-dotnet/pairing for it', 'never open .clavity please')) {
            (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$t`n" })).ExitCode | Should -Be 1 -Because $t
        }
    }
    It 'flags a directory named without its trailing slash' {
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "``clavity-dotnet/pairing```n" })).ExitCode | Should -Be 1
    }
    It 'flags every normalisation bypass form' {
        foreach ($t in @('[a](docs/hidden-plan.md#L10)', '[a](docs/hidden-plan.md%23L10)', '[a](docs/hidden-plan.md?x=1)',
                         '`clavity-dotnet\pairing\README.md`', '[a](/clavity-dotnet/pairing/)', '[a](file:///clavity-dotnet/pairing/)',
                         '[a](file://localhost/clavity-dotnet/pairing/)', '[a](docs/hidden%2Dplan.md)',
                         '[a](clavity-dotnet/pairing/README.md "Title")', 'x](clavity-dotnet/pairing/README.md',
                         '`tool --out=clavity-dotnet/pairing/x`', '<a href="clavity-dotnet/pairing/">x</a>',
                         '`Clavity-Dotnet/Pairing/`')) {
            (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$t`n" })).ExitCode | Should -Be 1 -Because $t
        }
    }
    It 'makes an absolute in-repo path repo-relative, including a differently-cased Windows drive letter' {
        $repo = New-RuleRepo @{ 'AGENTS.md' = 'placeholder' }
        $abs = (Join-Path $repo 'clavity-dotnet/pairing/x') -replace '\\', '/'
        if ($abs -match '^[A-Za-z]:') { $abs = $abs.Substring(0,1).ToLower() + $abs.Substring(1) }
        ConvertTo-CandidatePath -Text $abs -RepoRoot $repo -FileDir '' | Should -Contain 'clavity-dotnet/pairing/x'
    }
    It 'resolves a relative link in a nested rule file against that file''s directory' {
        (Invoke-Check (New-RuleRepo @{ 'clavity-dotnet/AGENTS.md' = "[p](pairing/)`n" })).ExitCode | Should -Be 1
    }
    It 'scans nested GEMINI.md and every rules-folder spelling' {
        foreach ($f in @('sub/GEMINI.md', '.agents/rules/a.md', '.agent/rules/a.md', '_agents/rules/a.md', '_agent/rules/a.md')) {
            (Invoke-Check (New-RuleRepo @{ $f = "``.clavity/x```n" })).ExitCode | Should -Be 1 -Because $f
        }
    }
    It 'follows an include, flags a hidden path inside it, fails on a missing target, and survives a cycle' {
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "@[more](docs/more.md)`n"; 'docs/more.md' = "``.clavity/x```n" })).ExitCode | Should -Be 1
        $miss = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "@[more](docs/nope.md)`n" })
        $miss.ExitCode | Should -Be 1; ($miss.Failures -join ' ') | Should -Match 'docs/nope.md'
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "@[b](b.md)`n"; 'b.md' = "@[a](AGENTS.md)`n" })).ExitCode | Should -Be 0
    }
    It 'does not fail on a missing ORDINARY link target' {
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "[x](docs/nope.md)`n" })).ExitCode | Should -Be 0
    }
    It 'drops http URLs, repo-escaping paths, empty tokens and comment slashes without a git error' {
        $t = "[w](https://example.com/clavity-dotnet/pairing/) ``../../outside/x```n" + '```c' + "`n// note`n/* block */`n" + '```' + "`n"
        $r = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = $t }); $r.ExitCode | Should -Be 0; $r.Failures | Should -BeNullOrEmpty
    }
    It 'does not flag a prose word equal to a bare pattern, nor a file re-included by a negation' {
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "Raise coverage. Keep ``keep.log```n" })).ExitCode | Should -Be 0
    }
    It 'ignores the user''s global git excludes' {
        $cfg = Join-Path $TestDrive 'gcfg'; $xf = Join-Path $TestDrive 'gexcl'
        [IO.File]::WriteAllText($xf, "allowed/`n"); [IO.File]::WriteAllText($cfg, "[core]`n`texcludesFile = $($xf -replace '\\','/')`n")
        $saved = $env:GIT_CONFIG_GLOBAL
        try { $env:GIT_CONFIG_GLOBAL = $cfg
              (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "``allowed/x```n" })).ExitCode | Should -Be 0 }
        finally { if ($null -eq $saved) { Remove-Item Env:GIT_CONFIG_GLOBAL -ErrorAction SilentlyContinue } else { $env:GIT_CONFIG_GLOBAL = $saved } }
    }
    It 'reports a non-ASCII hidden path' {
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "``café/notes.md```n" })).ExitCode | Should -Be 1
    }
    It 'fails closed when .antigravityignore is missing' {
        $r = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "x`n" } -NoIgnore)
        $r.ExitCode | Should -Be 1; ($r.Failures -join ' ') | Should -Match 'antigravityignore'
    }
    It 'gives the same result when run from a subdirectory' {
        $repo = New-RuleRepo @{ 'AGENTS.md' = "``.clavity/x```n"; 'sub/keep.txt' = 'k' }
        Push-Location (Join-Path $repo 'sub'); try { (Invoke-Check $repo).ExitCode | Should -Be 1 } finally { Pop-Location }
    }
    # Review Focus rows
    It 'flags a hidden path in a table cell and in an HTML comment' {
        foreach ($t in @('| a | clavity-dotnet/pairing/ | b |', '<!-- see .clavity/seams -->')) {
            (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$t`n" })).ExitCode | Should -Be 1 -Because $t
        }
    }
    It 'reports the right line number in a CRLF file' {
        $r = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "a`r`nb`r`n``.clavity/x```r`n" })
        $r.Hits[0] | Should -BeLike 'AGENTS.md:3  *'
    }
    It 'treats a shell pipeline with flags as harmless and catches a hidden path on a last line with no newline' {
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "``git log --oneline | head -3```n" })).ExitCode | Should -Be 0
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "x`n``.clavity/x``" })).ExitCode | Should -Be 1
    }
}

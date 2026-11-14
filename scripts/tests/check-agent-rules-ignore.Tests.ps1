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

# Fix round 1 (review findings I1-I4). The 21 cases above are the verbatim original suite; everything below is additive.
Describe 'Invoke-AgentRulesIgnoreCheck - fences nested in list items and blockquotes (I1)' {
    It 'flags a hidden path in a fenced block indented under a list item' {
        $t = (@('- step:', '', '    ```bash', '    cat debug.log', '    ```') -join "`n") + "`n"
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = $t })).ExitCode | Should -Be 1
    }
    It 'flags a hidden path in a fenced block inside a blockquote' {
        $t = (@('> ```bash', '> cat debug.log', '> ```') -join "`n") + "`n"
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = $t })).ExitCode | Should -Be 1
    }
    It 'flags a hidden path in a fence opened on the list-marker line, bulleted and numbered' {
        foreach ($m in @('- ', '* ', '1. ', '2) ')) {
            $t = (@(($m + '```bash'), '  cat debug.log', '  ```') -join "`n") + "`n"
            (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = $t })).ExitCode | Should -Be 1 -Because $m
        }
    }
    It 'closes a nested fence, so the prose after it is not scanned as fence content' {
        $t = (@('> ```bash', '> ls', '> ```', 'plain', 'debug.log') -join "`n") + "`n"
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = $t })).ExitCode | Should -Be 0
    }
}

Describe 'Invoke-AgentRulesIgnoreCheck - additive candidate forms (I2)' {
    It '(a) flags a path followed by :line, :line-line or :line:col' {
        foreach ($t in @('`docs/hidden-plan.md:42`', 'docs/hidden-plan.md:10-20', 'see docs/hidden-plan.md:10:5.')) {
            (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$t`n" })).ExitCode | Should -Be 1 -Because $t
        }
    }
    It '(b) flags a path with a leading @' {
        foreach ($t in @('@clavity-dotnet/pairing/README.md', '`@clavity-dotnet/pairing/README.md`', '@docs/hidden-plan.md')) {
            (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$t`n" })).ExitCode | Should -Be 1 -Because $t
        }
    }
    It '(c) flags a path wrapped in markdown emphasis or strikethrough' {
        foreach ($t in @('_docs/hidden-plan.md_', '~~docs/hidden-plan.md~~', '__docs/hidden-plan.md__')) {
            (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$t`n" })).ExitCode | Should -Be 1 -Because $t
        }
    }
    It 'keeps the as-written form, so a hidden underscore-prefixed folder is still flagged' {
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "``_private/x.md```n" } -Ignore "_private/`n")).ExitCode | Should -Be 1
    }
    It '(d) flags a reference-style link definition destination in a nested file' {
        foreach ($t in @('[r]: hidden-plan.md', '[r]: <hidden-plan.md>', '  [r]:   hidden-plan.md "Title"')) {
            (Invoke-Check (New-RuleRepo @{ 'docs/AGENTS.md' = "$t`n" })).ExitCode | Should -Be 1 -Because $t
        }
    }
    It 'adds forms without removing the as-written one' {
        $c = @(ConvertTo-CandidatePath -Text '_docs/hidden-plan.md_' -RepoRoot '/r' -FileDir '')
        $c | Should -Contain '_docs/hidden-plan.md_'
        $c | Should -Contain 'docs/hidden-plan.md'
        @(ConvertTo-CandidatePath -Text 'docs/a.md:42' -RepoRoot '/r' -FileDir '') | Should -Be @('docs/a.md:42', 'docs/a.md')
    }
}

Describe 'Invoke-AgentRulesIgnoreCheck - git failures fail closed (I3, I4a)' {
    BeforeAll {
        $script:IsWin = [Environment]::OSVersion.Platform -eq 'Win32NT'
        $script:RealGit = (Get-Command git -CommandType Application | Select-Object -First 1).Source
        # A `git` earlier on PATH that behaves as the real one except for check-ignore, where it runs $Body.
        function New-GitShim([string]$Body, [string]$WinBody = 'echo fatal: boom 1>&2 & exit /b 128') {
            $dir = Join-Path $TestDrive ('shim-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            if ($script:IsWin) {
                $cmd = "@echo off`r`necho %* | findstr /C:`"check-ignore`" >nul && ($WinBody)`r`n`"$($script:RealGit)`" %*`r`n"
                [IO.File]::WriteAllText((Join-Path $dir 'git.cmd'), $cmd)
            } else {
                $sh = "#!/bin/bash`nfor a in `"`$@`"; do`n  if [ `"`$a`" = check-ignore ]; then`n    cat > /dev/null`n    $Body`n  fi`ndone`nexec '$($script:RealGit)' `"`$@`"`n"
                $f = Join-Path $dir 'git'
                [IO.File]::WriteAllText($f, $sh)
                chmod +x $f
            }
            return $dir
        }
        function Invoke-WithShim([string]$ShimDir, [string]$Repo) {
            $saved = $env:PATH
            try { $env:PATH = $ShimDir + [IO.Path]::PathSeparator + $saved; return (Invoke-Check $Repo) }
            finally { $env:PATH = $saved }
        }
    }
    It 'fails closed (exit 1, never a pass) when git check-ignore errors' {
        $repo = New-RuleRepo @{ 'AGENTS.md' = "``.clavity/x```n" }
        $r = Invoke-WithShim (New-GitShim 'echo "fatal: boom" >&2; exit 128') $repo
        $r.ExitCode | Should -Be 1
        ($r.Failures -join ' ') | Should -Match 'check-ignore'
        $r.Hits.Count | Should -Be 0
    }
    It 'fails closed on a clean file too, when git check-ignore errors' {
        $repo = New-RuleRepo @{ 'AGENTS.md' = "Run ``just test``.`n" }
        $r = Invoke-WithShim (New-GitShim 'echo "fatal: boom" >&2; exit 128') $repo
        $r.ExitCode | Should -Be 1
        ($r.Failures -join ' ') | Should -Match 'check-ignore'
    }
    It 'fails closed when check-ignore reports a path that was not sent' -Skip:([Environment]::OSVersion.Platform -eq 'Win32NT') -Tag 'LinuxOnly' {
        $repo = New-RuleRepo @{ 'AGENTS.md' = "``.clavity/x```n" }
        $r = Invoke-WithShim (New-GitShim "printf '%s\0%s\0%s\0%s\0' .gitignore 2 '.clavity/' 'never/sent'; exit 0") $repo
        $r.ExitCode | Should -Be 1
        ($r.Failures -join ' ') | Should -Match 'not sent'
    }
    It 'fails closed when check-ignore reports a match from a source other than .gitignore' -Skip:([Environment]::OSVersion.Platform -eq 'Win32NT') -Tag 'LinuxOnly' {
        $repo = New-RuleRepo @{ 'AGENTS.md' = "``.clavity/x```n" }
        $r = Invoke-WithShim (New-GitShim "printf '%s\0%s\0%s\0%s\0' /home/u/.config/git/ignore 1 '.clavity/' '.clavity/x'; exit 0") $repo
        $r.ExitCode | Should -Be 1
        ($r.Failures -join ' ') | Should -Match 'unexpected source'
    }
}

Describe 'ConvertTo-CandidatePath - Windows-style roots on any OS (I4b, I4c)' {
    It 'makes a file:///X:/ URI repo-relative against a Windows root' {
        ConvertTo-CandidatePath -Text 'file:///C:/Repo/.clavity/x' -RepoRoot 'C:/Repo' -FileDir '' | Should -Contain '.clavity/x'
        ConvertTo-CandidatePath -Text 'file://C:/Repo/.clavity/x' -RepoRoot 'C:/Repo' -FileDir '' | Should -Contain '.clavity/x'
    }
    It 'matches a differently-cased drive letter and folder against a Windows root' {
        ConvertTo-CandidatePath -Text 'c:/repo/.clavity/x' -RepoRoot 'C:/Repo' -FileDir '' | Should -Contain '.clavity/x'
        ConvertTo-CandidatePath -Text 'C:\REPO\.clavity\x' -RepoRoot 'c:\repo\' -FileDir '' | Should -Contain '.clavity/x'
        ConvertTo-CandidatePath -Text 'file:///c:/repo/.clavity/x' -RepoRoot 'C:/Repo' -FileDir '' | Should -Contain '.clavity/x'
    }
}

# Final-review fix wave. Additive again: the 37 cases above are untouched. Each "flags" case exited 0 before the fix.
Describe 'Invoke-AgentRulesIgnoreCheck - prose filter sees through emphasis (I1)' {
    It 'flags a dot-folder wrapped in emphasis, strikethrough or @' {
        foreach ($t in @('never open **.clavity** please', 'never open _.clavity_ please', 'never open ~~.clavity~~ please', 'never open @.clavity please')) {
            (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$t`n" })).ExitCode | Should -Be 1 -Because $t
        }
    }
    It 'flags an emphasised dot-folder in a table cell' {
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "| x | **.clavity** |`n" })).ExitCode | Should -Be 1
    }
    It 'does not check an emphasised ordinary word' {
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "this is **very** _plain_ ~~prose~~ and @mention.`n" })).ExitCode | Should -Be 0
    }
}

Describe 'Invoke-AgentRulesIgnoreCheck - absolute paths into another checkout (I2)' {
    It 'flags a hidden path under an absolute, a drive-letter and a ~/ path outside this repo' {
        foreach ($t in @('see /home/u/clavity/clavity-dotnet/pairing/x', 'see D:\a\clavity\clavity\clavity-dotnet\pairing',
                         '~/src/clavity/docs/hidden-plan.md', '`/home/u/clavity/.clavity/seams`')) {
            (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$t`n" })).ExitCode | Should -Be 1 -Because $t
        }
    }
    It 'does not flag an absolute path into another checkout that is not hidden' {
        foreach ($t in @('see /home/u/clavity/docs/readme.md', 'see D:\a\clavity\clavity\docs\readme.md', '~/src/clavity/docs/readme.md')) {
            $r = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$t`n" })
            $r.ExitCode | Should -Be 0 -Because $t
        }
    }
    It 'adds every suffix from a / boundary and never sends a raw drive-letter form to git' {
        $c = @(ConvertTo-CandidatePath -Text 'D:\a\clavity\clavity\docs\x' -RepoRoot '/r' -FileDir '')
        $c | Should -Contain 'clavity/docs/x'
        $c | Should -Contain 'docs/x'
        @($c | Where-Object { $_ -match '^[A-Za-z]:' }) | Should -BeNullOrEmpty
        $u = @(ConvertTo-CandidatePath -Text '/home/u/clavity/docs/x' -RepoRoot '/r' -FileDir '')
        $u | Should -Contain 'home/u/clavity/docs/x'
        $u | Should -Contain 'clavity/docs/x'
        $u | Should -Contain 'x'
    }
    It 'adds no suffixes to a relative path or an in-repo absolute path' {
        @(ConvertTo-CandidatePath -Text 'a/b/c' -RepoRoot '/r' -FileDir '') | Should -Be @('a/b/c')
        @(ConvertTo-CandidatePath -Text '/r/a/b/c' -RepoRoot '/r' -FileDir '') | Should -Be @('a/b/c')
    }
}

Describe 'Invoke-AgentRulesIgnoreCheck - tokens glued by quotes, pipes, commas, semicolons (I3)' {
    It 'flags a hidden path inside typographic quotes, pipes, commas and semicolons' {
        $lq = [string][char]0x201C; $rq = [string][char]0x201D
        foreach ($t in @("see ${lq}.clavity/seams${rq} now", "see ${lq}clavity-dotnet/pairing/${rq} now", '|a|clavity-dotnet/pairing/|',
                         'see a/x,docs/hidden-plan.md', 'see a/x;docs/hidden-plan.md', "see ${lq}.clavity/seams,")) {
            (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$t`n" })).ExitCode | Should -Be 1 -Because $t
        }
    }
    It 'keeps the whole token and adds the parts (never replaces it)' {
        $lq = [string][char]0x201C; $rq = [string][char]0x201D
        $t = @(Get-RuleReferences @("see ${lq}.clavity/seams${rq} now") | ForEach-Object { $_.Text })
        $t | Should -Contain "${lq}.clavity/seams${rq}"
        $t | Should -Contain '.clavity/seams'
    }
    It 'produces no reference for plain prose with typographic quotes' {
        $lq = [string][char]0x201C; $rq = [string][char]0x201D; $ap = [string][char]0x2019
        $line = "He said ${lq}hello there${rq}, then left; it${ap}s fine | really."
        @(Get-RuleReferences @($line)).Count | Should -Be 0
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$line`n" })).ExitCode | Should -Be 0
    }
}

Describe 'Invoke-AgentRulesIgnoreCheck - fence opener and variants (D7, D8) and includes in fences (M2)' {
    It 'D7: a line like three backticks, x, three backticks is a code span, not a fence opener' {
        $t = (@('```x``` inline', 'text', '```', 'cat debug.log', '```') -join "`n") + "`n"
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = $t })).ExitCode | Should -Be 1
    }
    It 'D7: an include after such a line is still followed' {
        $t = (@('```x``` inline', '@[m](docs/more.md)') -join "`n") + "`n"
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = $t; 'docs/more.md' = "``.clavity/x```n" })).ExitCode | Should -Be 1
    }
    It 'D7: a correctly closed fence still closes (the line after it is prose, not fence content)' {
        $t = (@('```bash', 'echo hi', '```', 'debug.log') -join "`n") + "`n"
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = $t })).ExitCode | Should -Be 0
        $t2 = (@('```bash', 'cat debug.log', '```') -join "`n") + "`n"
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = $t2 })).ExitCode | Should -Be 1
    }
    It 'D8: the :line strip and the trailing _ or ~ trim combine in any order' {
        foreach ($t in @('_docs/hidden-plan.md:42_', '~~docs/hidden-plan.md:42~~', '_docs/hidden-plan.md_:42', '@docs/hidden-plan.md:10-20_')) {
            (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$t`n" })).ExitCode | Should -Be 1 -Because $t
        }
    }
    It 'M2: an include written inside a fenced block is followed' {
        $t = (@('```text', '@[m](docs/more.md)', '```') -join "`n") + "`n"
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = $t; 'docs/more.md' = "``.clavity/x```n" })).ExitCode | Should -Be 1
        $miss = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = (@('```text', '@[m](docs/nope.md)', '```') -join "`n") + "`n" })
        $miss.ExitCode | Should -Be 1; ($miss.Failures -join ' ') | Should -Match 'docs/nope.md'
    }
}

# K1-K3 fold (regressions found by the re-review of the final-fix wave). Additive: nothing above was changed.
Describe 'Invoke-AgentRulesIgnoreCheck - drive paths through .. (K1)' {
    It 'flags a hidden path when .. cancels the drive segment' {
        foreach ($t in @('see D:/../.clavity/x', 'see D:\..\clavity-dotnet\pairing\x', 'see C:/../docs/session-notes/n.md',
                         'see D:\a\..\..\clavity-dotnet\pairing\x', 'see D:/../clavity-dotnet/pairing/x')) {
            $ign = "docs/session-notes/`n.clavity/`nclavity-dotnet/pairing/`n"
            (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$t`n" } -Ignore $ign)).ExitCode | Should -Be 1 -Because $t
        }
    }
    It 'keeps the first real segment after .. and sends no drive-letter form' {
        foreach ($t in @('D:/../clavity-dotnet/pairing/x', 'D:\..\clavity-dotnet\pairing\x', 'D:\a\..\..\clavity-dotnet\pairing\x')) {
            $c = @(ConvertTo-CandidatePath -Text $t -RepoRoot '/r' -FileDir '')
            $c | Should -Contain 'clavity-dotnet/pairing/x' -Because $t
            @($c | Where-Object { $_ -match '^[A-Za-z]:' }) | Should -BeNullOrEmpty -Because $t
        }
    }
}

Describe 'Invoke-AgentRulesIgnoreCheck - an include is resolved only from its literal destination (K2)' {
    It 'does not fail on an existing include whose name contains a comma' {
        $r = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "@[m](docs/a,b.md)`n"; 'docs/a,b.md' = "plain text`n" })
        $r.ExitCode | Should -Be 0; $r.Failures | Should -BeNullOrEmpty
    }
    It 'does not fail on an existing include whose name contains parentheses' {
        $r = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "@[m](docs/foo(1).md)`n"; 'docs/foo(1).md' = "plain text`n" })
        $r.ExitCode | Should -Be 0; $r.Failures | Should -BeNullOrEmpty
    }
    It 'still follows such an include and flags a hidden path inside it' {
        $r = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "@[m](docs/a,b.md)`n"; 'docs/a,b.md' = "``.clavity/x```n" })
        $r.ExitCode | Should -Be 1
    }
    It 'tags the split parts of an include destination as links, never includes' {
        $refs = @(Get-RuleReferences @('@[m](docs/a,b.md)'))
        @($refs | Where-Object { $_.Kind -eq 'include' } | ForEach-Object { $_.Text }) | Should -Be @('docs/a,b.md')
        @($refs | Where-Object { $_.Text -eq 'docs/a' })[0].Kind | Should -Be 'link'
    }
}

Describe 'Invoke-AgentRulesIgnoreCheck - no drive-letter candidate ever reaches git (K3)' {
    It 'filters a drive letter that appears mid-path and keeps the non-drive suffixes' {
        foreach ($t in @('\\.\D:\a\clavity\clavity-dotnet\pairing', '/mnt/D:/clavity-dotnet/pairing')) {
            $c = @(ConvertTo-CandidatePath -Text $t -RepoRoot '/r' -FileDir '')
            @($c | Where-Object { $_ -match '^[A-Za-z]:' }) | Should -BeNullOrEmpty -Because $t
            $c | Should -Contain 'clavity-dotnet/pairing' -Because $t
            (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "see $t`n" })).ExitCode | Should -Be 1 -Because $t
        }
    }
    It 'never returns a bare drive or an X:/ candidate for a plain drive path either' {
        @(ConvertTo-CandidatePath -Text 'D:/a/b' -RepoRoot '/r' -FileDir '' | Where-Object { $_ -match '^[A-Za-z]:(/|$)' }) | Should -BeNullOrEmpty
    }
}

# Capstone round-1 fold. Additive: nothing above was changed.
Describe 'Invoke-AgentRulesIgnoreCheck - forms that name another checkout (F1)' {
    It 'flags a hidden path reached through an escape, an env-var home, ~user, a device prefix or a clamped ..' {
        foreach ($t in @('see ../clavity/clavity-dotnet/pairing/x', 'see $HOME/src/clavity/clavity-dotnet/pairing/x',
                         'see ${HOME}/src/clavity/clavity-dotnet/pairing/x', 'see %USERPROFILE%\src\clavity\clavity-dotnet\pairing',
                         'see ~bob/clavity/clavity-dotnet/pairing/x', 'see /a/../../clavity-dotnet/pairing/x',
                         'see \\?\D:\a\clavity\clavity-dotnet\pairing', 'see \\.\D:\a\clavity\clavity-dotnet\pairing')) {
            (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$t`n" })).ExitCode | Should -Be 1 -Because $t
        }
    }
    It 'adds the boundary suffixes of an escaping path and keeps no drive-letter or device-prefix form' {
        $c = @(ConvertTo-CandidatePath -Text '../clavity/clavity-dotnet/pairing/x' -RepoRoot '/r' -FileDir '')
        $c | Should -Contain 'clavity-dotnet/pairing/x'
        $d = @(ConvertTo-CandidatePath -Text '\\?\D:\a\clavity\clavity-dotnet\pairing' -RepoRoot '/r' -FileDir '')
        $d | Should -Contain 'clavity-dotnet/pairing'
        @($d | Where-Object { $_ -match '^[A-Za-z]:' -or $_ -match '\?' }) | Should -BeNullOrEmpty
        @(ConvertTo-CandidatePath -Text '$HOME/src/clavity/x' -RepoRoot '/r' -FileDir '') | Should -Contain '$HOME/src/clavity/x'
    }
    It 'does not flag such a path when its suffixes are not hidden' {
        foreach ($t in @('see ../clavity/docs/readme.md', 'see $HOME/src/clavity/docs/readme.md', 'see ~bob/clavity/docs/readme.md')) {
            (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$t`n" })).ExitCode | Should -Be 0 -Because $t
        }
    }
}

Describe 'Invoke-AgentRulesIgnoreCheck - git pathspec magic (F2)' {
    It 'does not fail on ordinary git documentation that uses pathspec magic' {
        foreach ($t in @("``git diff -- ':!docs'``", "``git diff -- ':^docs'``", "``git diff -- ':(exclude)docs'``", "``git log -- ':(top)docs'``")) {
            $r = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "$t`n" })
            $r.ExitCode | Should -Be 0 -Because $t
            $r.Failures | Should -BeNullOrEmpty -Because $t
        }
    }
    It 'checks the remainder after the magic prefix and never sends the raw magic form' {
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "``:/clavity-dotnet/pairing```n" })).ExitCode | Should -Be 1
        (Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "``:!clavity-dotnet/pairing/x```n" })).ExitCode | Should -Be 1
        foreach ($t in @(':!docs', ':^docs', ':/docs', ':(exclude)docs', '/home/u/:!docs')) {
            @(ConvertTo-CandidatePath -Text $t -RepoRoot '/r' -FileDir '' | Where-Object { $_ -like ':*' }) | Should -BeNullOrEmpty -Because $t
        }
        @(ConvertTo-CandidatePath -Text ':!docs' -RepoRoot '/r' -FileDir '') | Should -Contain 'docs'
    }
}

Describe 'Invoke-AgentRulesIgnoreCheck - census and include resolution (F3-F8)' {
    It 'F3: fails when a tracked rule file is missing from the working tree' {
        $repo = New-RuleRepo @{ 'AGENTS.md' = "x`n" }
        Remove-Item -LiteralPath (Join-Path $repo 'AGENTS.md')
        $r = Invoke-Check $repo
        $r.ExitCode | Should -Be 1
        ($r.Failures -join ' ') | Should -Match 'tracked rule file missing from working tree: AGENTS.md'
    }
    It 'F4: follows an include whose label holds one level of nested brackets' {
        $r = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "@[a [b] c](docs/inc.md)`n"; 'docs/inc.md' = "``.clavity/x```n" })
        $r.ExitCode | Should -Be 1
    }
    It 'F5: a footnote definition is not a link definition, a real link definition still is' {
        (Invoke-Check (New-RuleRepo @{ 'docs/AGENTS.md' = "[^1]: hidden-plan.md`n" })).ExitCode | Should -Be 0
        @(Get-RuleReferences @('[^1]: some text')).Count | Should -Be 0
        (Invoke-Check (New-RuleRepo @{ 'docs/AGENTS.md' = "[r]: hidden-plan.md`n" })).ExitCode | Should -Be 1
    }
    It 'F6: two includes that differ only by case are both scanned' -Skip:([Environment]::OSVersion.Platform -ne 'Unix' -or (Test-Path '/System/Library')) -Tag 'LinuxOnly' {
        $files = [hashtable]::new([System.StringComparer]::Ordinal)   # a literal would be a duplicate key: PS keys ignore case
        $files['AGENTS.md'] = "@[a](docs/a.md)`n@[b](docs/A.md)`n"; $files['docs/a.md'] = "plain`n"; $files['docs/A.md'] = "``.clavity/x```n"
        $r = Invoke-Check (New-RuleRepo $files)
        $r.ExitCode | Should -Be 1
        $r.FileCount | Should -Be 3
    }
    It 'F7: ReferenceCount is the same deduplicated count on the failure path as on the normal path' {
        $content = @{ 'AGENTS.md' = "``.clavity/x`` .clavity/x`n" }
        $ok = Invoke-Check (New-RuleRepo $content)
        $fail = Invoke-Check (New-RuleRepo $content -NoIgnore)
        $fail.Failures.Count | Should -BeGreaterThan 0
        $fail.ReferenceCount | Should -Be $ok.ReferenceCount
        $ok.ReferenceCount | Should -BeGreaterThan 0
    }
    It 'F8: the literal forms from Get-CandidateSet equal Get-CandidateForms' {
        $s = Get-CandidateSet -Text 'docs/x.md' -RepoRoot '/r' -FileDir 'sub'
        $f = Get-CandidateForms -Text 'docs/x.md' -RepoRoot '/r' -FileDir 'sub'
        $s.Literal.A | Should -Be $f.A
        $s.Literal.B | Should -Be $f.B
        $s.Candidates | Should -Contain 'sub/docs/x.md'
    }
}

Describe 'check-agent-rules-ignore - test-audit gaps (PP1, MG1, BS1)' {
    It 'PP1: run as a script, a clean repo prints the census line and exits 0; a leaking repo prints the failure list and exits 1' {
        $pwsh = (Get-Process -Id $PID).Path
        foreach ($case in @(
                @{ Body = "Run ``just test`` in ``scripts/``.`n"; Exit = 0 },
                @{ Body = "ok`nsee ``.clavity/x```n"; Exit = 1 })) {
            $repo = New-RuleRepo @{ 'AGENTS.md' = $case.Body }
            New-Item -ItemType Directory -Path (Join-Path $repo 'scripts') -Force | Out-Null
            $copy = Join-Path $repo 'scripts/check-agent-rules-ignore.ps1'
            Copy-Item ([System.IO.Path]::Combine($PSScriptRoot, '..', 'check-agent-rules-ignore.ps1')) $copy
            $out = @(& $pwsh -NoProfile -File $copy 2>&1 | ForEach-Object { ("$_" -replace "\x1b\[[0-9;]*m", '').TrimEnd() } | Where-Object { $_ -ne '' })
            $LASTEXITCODE | Should -Be $case.Exit -Because ($out -join ' | ')
            if ($case.Exit -eq 0) {
                $out.Count | Should -Be 1
                $out[0] | Should -Match '^agent rules ok \(1 rule files, [1-9]\d* references, none hidden by \.antigravityignore\)$'
            } else {
                $out[0] | Should -BeExactly 'agent-rules-ignore gate FAILED:'
                $out | Should -Contain '  - AGENTS.md:2  .clavity/x  ->  .antigravityignore:2:.clavity/'
                $out | Should -Not -Contain 'agent rules ok' -Because 'the census line is the success contract only'
            }
        }
    }
    It 'MG1: a token repeated on one line yields the same hits and ReferenceCount as the token written once' {
        $once  = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "see ``.clavity/x```n" })
        $twice = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "see ``.clavity/x`` and ``.clavity/x`` and .clavity/x`n" })
        $once.ExitCode | Should -Be 1
        @($twice.Hits) | Should -Be @($once.Hits)
        $twice.ReferenceCount | Should -Be $once.ReferenceCount
    }
    It 'BS1: a tilde fence is scanned as code and closes, so prose after it is not fence content' {
        $r = Invoke-Check (New-RuleRepo @{ 'AGENTS.md' = "~~~bash`ncat debug.log`n~~~`nthe debug.log name in prose`n" })
        $r.ExitCode | Should -Be 1
        @($r.Hits).Count | Should -Be 1
        $r.Hits[0] | Should -BeLike 'AGENTS.md:2  debug.log  ->  *'
    }
}

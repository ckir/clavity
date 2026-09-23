# scripts/tests/check-skill-frontmatter.Tests.ps1
#
# Every row builds a throwaway git repo, because the linter's discovery IS `git ls-files` - a fixture that
# bypassed it would test a scope the gate never uses. The linter runs IN-PROCESS (`& $script`): `exit`
# sets $LASTEXITCODE without ending the host, and it saves a child pwsh per row.
#
# Every fixture carries the one real exclusion (clavity-classic/agy-mcp-bridge/SKILL.md, frontmatter-less)
# so the exclusion path is exercised by every row, and the stale-exclusion guard does not fire by accident.
# EXIT CODE ALONE IS NOT ENOUGH: a pwsh parse error also exits 1, so every failing row also pins the
# message that proves WHICH check fired.

BeforeAll {
    $script:Lint = Join-Path $PSScriptRoot '..' 'check-skill-frontmatter.ps1'
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

    function New-Fixture {
        param([hashtable]$Skills = @{}, [switch]$NoExclusion)
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("skillfm-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $root | Out-Null
        & git -C $root init -q 2>$null | Out-Null
        if (-not $NoExclusion) { $Skills['clavity-classic/agy-mcp-bridge/SKILL.md'] = "# bridge reference, no frontmatter`n" }
        foreach ($rel in $Skills.Keys) {
            $p = Join-Path $root $rel
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null
            [System.IO.File]::WriteAllText($p, $Skills[$rel], [System.Text.UTF8Encoding]::new($false))
        }
        & git -C $root add -A 2>$null | Out-Null
        return $root
    }

    function Invoke-Lint {
        param([string]$Root, [int]$MaxBytes = 440)
        $out = & $script:Lint -Root $Root -MaxBytes $MaxBytes 6>&1 | Out-String
        return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
    }

    function Skill([string]$Name, [string]$Desc) { "---`nname: $Name`ndescription: $Desc`n---`n`n# $Name body`n" }
}

Describe 'check-skill-frontmatter.ps1' {
    AfterEach { if ($script:Root) { Remove-Item -Recurse -Force $script:Root -ErrorAction SilentlyContinue; $script:Root = $null } }

    It 'passes on the REAL repository (the live oracle - the shipped skills are within budget)' {
        $r = Invoke-Lint -Root $script:RepoRoot
        $r.Out | Should -Match 'check-skill-frontmatter: OK - \d+ SKILL\.md checked \(1 excluded\)'
        $r.Code | Should -Be 0
    }

    It 'passes a well-formed skill, and skips the excluded frontmatter-less file' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = (Skill 'alpha' 'Use when testing.') }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'OK - 1 SKILL\.md checked \(1 excluded\)'
        $r.Code | Should -Be 0
    }

    It 'passes at EXACTLY the budget and fails one byte over (boundary)' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = (Skill 'alpha' ('x' * 20)) }
        (Invoke-Lint -Root $script:Root -MaxBytes 20).Code | Should -Be 0
        $r = Invoke-Lint -Root $script:Root -MaxBytes 19
        $r.Out | Should -Match 'description too long: 20 bytes \(limit 19\)'
        $r.Code | Should -Be 1
    }

    It 'measures UTF-8 BYTES, not characters' {
        # 10 x U+20AC = 10 chars but 30 bytes: must FAIL a 20-byte budget.
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = (Skill 'alpha' ([string][char]0x20AC * 10)) }
        $r = Invoke-Lint -Root $script:Root -MaxBytes 20
        $r.Out | Should -Match 'description too long: 30 bytes'
        $r.Code | Should -Be 1
    }

    It 'fails the pre-fix agy-test-audit description (750 chars) at the default budget' {
        $script:Root = New-Fixture @{ 'p/skills/agy-test-audit/SKILL.md' = (Skill 'agy-test-audit' ('y' * 750)) }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'agy-test-audit/SKILL\.md: SKILL\.md description too long: 750 bytes \(limit 440\)'
        $r.Out | Should -Match 'silently dropped by Claude Code'
        $r.Code | Should -Be 1
    }

    It 'fails when name does not match the directory (case-sensitive)' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = (Skill 'Alpha' 'ok') }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match "name 'Alpha' does not match its directory 'alpha'"
        $r.Code | Should -Be 1
    }

    It 'fails a folded block-scalar description' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`nname: alpha`ndescription: >`n  folded text`n---`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match "'description' continues onto a later line"
        $r.Out | Should -Match 'block scalar'
        $r.Code | Should -Be 1
    }

    It 'fails a plain description that continues onto an indented line' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`nname: alpha`ndescription: short head`n  hidden tail that a YAML parser would join`n---`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match "'description' continues onto a later line"
        $r.Code | Should -Be 1
    }

    It 'handles CRLF files the same as LF' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = ((Skill 'alpha' ('x' * 20)) -replace "`n", "`r`n") }
        (Invoke-Lint -Root $script:Root -MaxBytes 20).Code | Should -Be 0
        (Invoke-Lint -Root $script:Root -MaxBytes 19).Code | Should -Be 1
    }

    It 'fails a SKILL.md with no frontmatter that is not excluded' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "# alpha, no frontmatter`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'p/skills/alpha/SKILL\.md: no YAML frontmatter'
        $r.Code | Should -Be 1
    }

    It 'fails a duplicated description key' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`nname: alpha`ndescription: a`ndescription: b`n---`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match "expected exactly one 'description:' in frontmatter, found 2"
        $r.Code | Should -Be 1
    }

    It 'fails a missing name key' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`ndescription: a`n---`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match "expected exactly one 'name:' in frontmatter, found 0"
        $r.Code | Should -Be 1
    }

    It 'checks a skill ANYWHERE in the tree, not only under plugin/skills (scope fails closed)' {
        $script:Root = New-Fixture @{ 'some/new/place/beta/SKILL.md' = (Skill 'beta' ('z' * 30)) }
        $r = Invoke-Lint -Root $script:Root -MaxBytes 20
        $r.Out | Should -Match 'some/new/place/beta/SKILL\.md: SKILL\.md description too long'
        $r.Code | Should -Be 1
    }

    # --- capstone round 1 folds (60dc20d..3e9b299): each row was a MEASURED crash, false-green or false-red ---

    It 'fails a YAML ALIAS description, which a YAML reader expands past the budget (was a false GREEN)' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`nname: alpha`nx: &long $('y' * 600)`ndescription: *long`n---`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match "YAML alias/anchor/tag"
        $r.Code | Should -Be 1
    }

    It 'fails an anchored description, and does NOT flag a QUOTED leading asterisk (distractor)' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`nname: alpha`ndescription: &a text`n---`n"
                                      'p/skills/beta/SKILL.md'  = "---`nname: beta`ndescription: `"*bold* is literal text here`"`n---`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'alpha/SKILL\.md: description is empty, a block scalar'
        $r.Out | Should -Not -Match 'beta/SKILL\.md'
        $r.Code | Should -Be 1
    }

    It 'strips one pair of YAML quotes from name and description (was a false RED on name: "a")' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`nname: `"alpha`"`ndescription: '$('x' * 20)'`n---`n" }
        (Invoke-Lint -Root $script:Root -MaxBytes 20).Code | Should -Be 0 -Because 'the 2 quote bytes are not part of the value'
        $r = Invoke-Lint -Root $script:Root -MaxBytes 19
        $r.Out | Should -Match 'description too long: 20 bytes'
        $r.Code | Should -Be 1
    }

    It 'fails a SKILL.md at the repository root instead of crashing' {
        $script:Root = New-Fixture @{ 'SKILL.md' = (Skill 'root' 'ok') }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'SKILL\.md: sits at the repository root'
        $r.Code | Should -Be 1
    }

    It 'fails a tracked SKILL.md deleted from the working tree instead of crashing' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = (Skill 'alpha' 'ok'); 'p/skills/beta/SKILL.md' = (Skill 'beta' 'ok') }
        Remove-Item -LiteralPath (Join-Path $script:Root 'p/skills/beta/SKILL.md')
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'p/skills/beta/SKILL\.md: tracked but missing from the working tree'
        $r.Code | Should -Be 1
    }

    It 'reads a skill under a NON-ASCII directory instead of crashing on a git-quoted path' {
        $dir = 'caf' + [char]0xE9
        $script:Root = New-Fixture @{ "p/skills/$dir/SKILL.md" = (Skill $dir ('x' * 30)) }
        (Invoke-Lint -Root $script:Root -MaxBytes 30).Code | Should -Be 0
        $r = Invoke-Lint -Root $script:Root -MaxBytes 29
        $r.Out | Should -Match "p/skills/$dir/SKILL\.md: SKILL\.md description too long: 30 bytes"
        $r.Code | Should -Be 1
    }

    It 'checks a lowercase skill.md, but not a file merely ENDING in skill.md (distractor)' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/skill.md' = (Skill 'alpha' ('x' * 30))
                                      'p/skills/beta/notaskill.md' = (Skill 'wrong' ('x' * 30)) }
        $r = Invoke-Lint -Root $script:Root -MaxBytes 20
        $r.Out | Should -Match 'p/skills/alpha/skill\.md: SKILL\.md description too long'
        $r.Out | Should -Not -Match 'notaskill'
        $r.Code | Should -Be 1
    }

    # --- capstone round 2 fold (60dc20d..adcca2e): a quoted scalar left open was a MEASURED false GREEN ---

    It 'fails a quoted description whose `---` line ends the frontmatter match early (was a false GREEN)' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`nname: alpha`ndescription: `"short`n---`n$('y' * 600)`"`n---`n# body`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'alpha/SKILL\.md: description opens a quote it does not close on the same line'
        $r.Code | Should -Be 1
    }

    It 'fails a quoted description continued on an UNINDENTED line, and passes a closed one (distractor)' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`nname: alpha`ndescription: 'short`n$('y' * 600)'`n---`n"
                                      'p/skills/beta/SKILL.md'  = "---`nname: beta`ndescription: 'closed on its own line'`n---`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'alpha/SKILL\.md: description opens a quote'
        $r.Out | Should -Not -Match 'beta/SKILL\.md'
        $r.Code | Should -Be 1
    }

    # --- capstone round 3 folds (60dc20d..0a9baf3): the closing quote is FOUND, continuation is SCANNED ---

    It 'fails a quoted description whose line ends in an ESCAPED quote (still open - was a false GREEN)' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`nname: alpha`ndescription: `"start \`"`n---`n$('y' * 600)`"`n---`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'alpha/SKILL\.md: description opens a quote it does not close on the same line'
        $r.Code | Should -Be 1
    }

    It 'passes a closed quoted description followed by a # comment, counting only the quoted text (was a false RED)' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`nname: alpha`ndescription: `"$('x' * 20)`" # a trailing note`n---`n" }
        (Invoke-Lint -Root $script:Root -MaxBytes 20).Code | Should -Be 0 -Because 'the comment and the quotes are not part of the value'
        $r = Invoke-Lint -Root $script:Root -MaxBytes 19
        $r.Out | Should -Match 'description too long: 20 bytes'
        $r.Code | Should -Be 1
    }

    It 'fails text after the closing quote that is not a comment, and passes a doubled single quote (distractor)' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`nname: alpha`ndescription: `"ok`" trailing words`n---`n"
                                      'p/skills/beta/SKILL.md'  = "---`nname: beta`ndescription: 'it''s fine'`n---`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'alpha/SKILL\.md: description opens a quote .* or text follows the closing quote'
        $r.Out | Should -Not -Match 'beta/SKILL\.md'
        $r.Code | Should -Be 1
    }

    It 'fails a plain description continued after a BLANK line (was a false GREEN)' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`nname: alpha`ndescription: start`n`n  $('y' * 600)`n---`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match "alpha/SKILL\.md: 'description' continues onto a later line"
        $r.Code | Should -Be 1
    }

    It 'does NOT treat an indented block under a LATER key as a description continuation (distractor)' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`nname: alpha`ndescription: ok`n`nmetadata:`n  type: x`n---`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'OK - 1 SKILL\.md checked'
        $r.Code | Should -Be 0
    }

    It 'CANNOT ANSWER (exit 2) when discovery finds zero skills - never a vacuous pass' {
        $script:Root = New-Fixture
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'CANNOT ANSWER: found 0 SKILL\.md files'
        $r.Code | Should -Be 2
    }

    It 'CANNOT ANSWER (exit 2) when an exclusion matches no tracked file' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = (Skill 'alpha' 'ok') } -NoExclusion
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match "CANNOT ANSWER: exclusion 'clavity-classic/agy-mcp-bridge/SKILL\.md' matches no tracked SKILL\.md"
        $r.Code | Should -Be 2
    }

    It 'CANNOT ANSWER (exit 2) outside a git repository' {
        $script:Root = Join-Path ([System.IO.Path]::GetTempPath()) ("skillfm-nogit-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Root | Out-Null
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'CANNOT ANSWER: git ls-files failed'
        $r.Code | Should -Be 2
    }
}

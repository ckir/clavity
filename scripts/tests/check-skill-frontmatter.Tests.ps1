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
        $r.Out | Should -Match "'description' continues onto the next line"
        $r.Out | Should -Match 'block scalar'
        $r.Code | Should -Be 1
    }

    It 'fails a plain description that continues onto an indented line' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`nname: alpha`ndescription: short head`n  hidden tail that a YAML parser would join`n---`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match "'description' continues onto the next line"
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

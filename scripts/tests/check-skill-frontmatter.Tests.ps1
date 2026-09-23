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
#
# The oracle is `yq` (mikefarah v4), so this suite needs it on PATH, exactly like the gate does.

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
        param([string]$Root)
        $out = & $script:Lint -Root $Root 6>&1 | Out-String
        return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
    }

    function Skill([string]$Name, [string]$Desc) { "---`nname: $Name`ndescription: $Desc`n---`n`n# $Name body`n" }

    # THE REGRESSION, verbatim: agy-capstone's description as it shipped at 60dc20d. Claude Code dropped it
    # (CRLF checkout) because of the unquoted `: ` in "not the plan artifact): the peer".
    $script:OriginalCapstone = 'Use ONLY before declaring a plan or implementation COMPLETE - never on routine intermediate commits. Runs a convergent, rounds-until-green adversarial review of the already-COMMITTED code (executable code + tests, not the plan artifact): the peer reasons and cites file:line, the driver measures every finding before folding. A hard round cap plus human-adjudicated GREEN gate the completion claim. Ends with one ASCII [VERDICT] token. Best-effort prompt-discipline, manually invokable; auto-fire is added separately.'
}

Describe 'check-skill-frontmatter.ps1' {
    AfterEach { if ($script:Root) { Remove-Item -Recurse -Force $script:Root -ErrorAction SilentlyContinue; $script:Root = $null } }

    It 'passes on the REAL repository (the live oracle - every shipped frontmatter parses)' {
        $r = Invoke-Lint -Root $script:RepoRoot
        $r.Out | Should -Match 'check-skill-frontmatter: OK - \d+ SKILL\.md checked \(1 excluded\), all frontmatter valid YAML'
        $r.Code | Should -Be 0
    }

    It 'passes a well-formed skill, and skips the excluded frontmatter-less file' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = (Skill 'alpha' 'Use when testing.') }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'OK - 1 SKILL\.md checked \(1 excluded\)'
        $r.Code | Should -Be 0
    }

    # --- the defect this gate exists for ---

    It 'fails the ORIGINAL agy-capstone description under LF AND CRLF, and passes it once quoted (the regression)' {
        $bad = Skill 'agy-capstone' $script:OriginalCapstone
        $script:Root = New-Fixture @{ 'p/skills/agy-capstone/SKILL.md' = $bad; 'q/skills/agy-capstone/SKILL.md' = ($bad -replace "`n", "`r`n") }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'p/skills/agy-capstone/SKILL\.md: frontmatter is not valid YAML'
        $r.Out | Should -Match 'q/skills/agy-capstone/SKILL\.md: frontmatter is not valid YAML'
        $r.Out | Should -Match 'mapping values are not allowed'
        $r.Code | Should -Be 1
        Remove-Item -Recurse -Force $script:Root
        $script:Root = New-Fixture @{ 'p/skills/agy-capstone/SKILL.md' = ((Skill 'agy-capstone' "`"$($script:OriginalCapstone)`"") -replace "`n", "`r`n") }
        (Invoke-Lint -Root $script:Root).Code | Should -Be 0 -Because 'length was never the defect - the quoted 517-char original is valid'
    }

    It 'fails a short unquoted colon-space, and passes the same text single-quoted (distractor)' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = (Skill 'alpha' 'a plan: the peer')
                                      'p/skills/beta/SKILL.md'  = (Skill 'beta' "'a plan: the peer'") }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'alpha/SKILL\.md: frontmatter is not valid YAML'
        $r.Out | Should -Not -Match 'beta/SKILL\.md'
        $r.Code | Should -Be 1
    }

    # --- the parsed value's TYPE: yq accepts these, Claude Code does not ---

    It 'fails a LIST description and a NUMBER description (valid YAML, not a string)' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = (Skill 'alpha' '[a, b]')
                                      'p/skills/beta/SKILL.md'  = (Skill 'beta' '42') }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match "alpha/SKILL\.md: 'description' must be a non-empty string \(got: \[`"a`",`"b`"\]\)"
        $r.Out | Should -Match "beta/SKILL\.md: 'description' must be a non-empty string \(got: 42\)"
        $r.Code | Should -Be 1
    }

    It 'fails a description that is only a comment (null) or an empty string' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = (Skill 'alpha' '# nothing here')
                                      'p/skills/beta/SKILL.md'  = (Skill 'beta' '""') }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match "alpha/SKILL\.md: 'description' must be a non-empty string \(got: null\)"
        $r.Out | Should -Match "beta/SKILL\.md: 'description' must be a non-empty string"
        $r.Code | Should -Be 1
    }

    It 'fails a missing name key' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`ndescription: a`n---`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match "alpha/SKILL\.md: 'name' must be a non-empty string \(got: missing\)"
        $r.Code | Should -Be 1
    }

    It 'fails frontmatter that is valid YAML but not a mapping' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`njust a string`n---`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'alpha/SKILL\.md: frontmatter is valid YAML but not a mapping'
        $r.Code | Should -Be 1
    }

    # --- name / structure ---

    It 'fails when name does not match the directory (case-sensitive)' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = (Skill 'Alpha' 'ok') }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match "name 'Alpha' does not match its directory 'alpha'"
        $r.Code | Should -Be 1
    }

    It 'compares the PARSED name, so a quoted name matches its directory' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`nname: `"alpha`"`ndescription: ok`n---`n" }
        (Invoke-Lint -Root $script:Root).Code | Should -Be 0
    }

    It 'fails a SKILL.md with no frontmatter that is not excluded' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "# alpha, no frontmatter`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'p/skills/alpha/SKILL\.md: no YAML frontmatter'
        $r.Code | Should -Be 1
    }

    It 'fails a SKILL.md at the repository root instead of crashing' {
        $script:Root = New-Fixture @{ 'SKILL.md' = (Skill 'root' 'ok') }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'SKILL\.md: sits at the repository root'
        $r.Code | Should -Be 1
    }

    # --- shapes where a naive frontmatter split disagrees with a YAML reader ---

    It 'fails a quoted description whose `---` line ends the frontmatter block early' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`nname: alpha`ndescription: `"short`n---`n$('y' * 600)`"`n---`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'alpha/SKILL\.md: frontmatter is not valid YAML'
        $r.Code | Should -Be 1
    }

    It 'fails an indented tail after a column-0 comment (a YAML reader rejects it)' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = "---`nname: alpha`ndescription: ok`n# c`n  tail`n---`n" }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'alpha/SKILL\.md: frontmatter is not valid YAML'
        $r.Code | Should -Be 1
    }

    # --- encodings and paths ---

    It 'passes valid CRLF and BOM-prefixed files' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = ((Skill 'alpha' 'fine') -replace "`n", "`r`n")
                                      'p/skills/beta/SKILL.md'  = ([char]0xFEFF + (Skill 'beta' 'fine')) }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'OK - 2 SKILL\.md checked'
        $r.Code | Should -Be 0
    }

    It 'reads a NON-ASCII directory and description, and names that path when it fails' {
        $dir = 'caf' + [char]0xE9
        $script:Root = New-Fixture @{ "p/skills/$dir/SKILL.md" = (Skill $dir ('d' + [char]0xE9 + 'j' + [char]0xE0 + ' ' + [char]0x20AC)) }
        # A HOSTILE caller: the script inherits $OutputEncoding, and pwsh 7's UTF-8 default would otherwise
        # mask a missing UTF-8 setting in the script (MEASURED: that mutant survived until this line).
        # With ASCII piped to yq the name reads 'caf?' and no longer matches its directory.
        $OutputEncoding = [System.Text.ASCIIEncoding]::new()
        # Same for the PROCESS-wide stdout decoding: force this box's real default (CP437) so a missing
        # UTF-8 setting in the script mangles git's path and yq's JSON (that mutant also survived before).
        $savedConsole = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(437)
            $r0 = Invoke-Lint -Root $script:Root
        } finally { [Console]::OutputEncoding = $savedConsole }
        $r0.Out | Should -Match 'OK - 1 SKILL\.md checked'
        $r0.Code | Should -Be 0
        Remove-Item -Recurse -Force $script:Root
        $script:Root = New-Fixture @{ "p/skills/$dir/SKILL.md" = (Skill $dir 'a: b') }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match "p/skills/$dir/SKILL\.md: frontmatter is not valid YAML"
        $r.Code | Should -Be 1
    }

    It 'restores the caller''s process-wide [Console]::OutputEncoding (in-process run)' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = (Skill 'alpha' 'ok') }
        $saved = [Console]::OutputEncoding
        try {
            # Start from a value the script does NOT set, or the restore is untestable.
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(437)
            $null = Invoke-Lint -Root $script:Root
            [Console]::OutputEncoding.CodePage | Should -Be 437
        } finally { [Console]::OutputEncoding = $saved }
    }

    # --- scope ---

    It 'fails a tracked SKILL.md deleted from the working tree instead of crashing' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = (Skill 'alpha' 'ok'); 'p/skills/beta/SKILL.md' = (Skill 'beta' 'ok') }
        Remove-Item -LiteralPath (Join-Path $script:Root 'p/skills/beta/SKILL.md')
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'p/skills/beta/SKILL\.md: tracked but missing from the working tree'
        $r.Code | Should -Be 1
    }

    It 'checks a lowercase skill.md, but not a file merely ENDING in skill.md (distractor)' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/skill.md' = (Skill 'alpha' 'a: b')
                                      'p/skills/beta/notaskill.md' = (Skill 'wrong' 'a: b') }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'p/skills/alpha/skill\.md: frontmatter is not valid YAML'
        $r.Out | Should -Not -Match 'notaskill'
        $r.Code | Should -Be 1
    }

    It 'checks a skill ANYWHERE in the tree, not only under plugin/skills' {
        $script:Root = New-Fixture @{ 'some/new/place/beta/SKILL.md' = (Skill 'beta' 'a: b') }
        $r = Invoke-Lint -Root $script:Root
        $r.Out | Should -Match 'some/new/place/beta/SKILL\.md: frontmatter is not valid YAML'
        $r.Code | Should -Be 1
    }

    # --- cannot answer: exit 2, never a vacuous pass ---

    It 'CANNOT ANSWER (exit 2) when discovery finds zero skills' {
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

    It 'CANNOT ANSWER (exit 2) when yq is not on PATH' {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = (Skill 'alpha' 'a: b') }
        $saved = $env:PATH
        try {
            # Keep every PATH entry EXCEPT the ones that hold a yq, so git still resolves.
            $env:PATH = (($saved -split [IO.Path]::PathSeparator) | Where-Object {
                $_ -and -not (Get-ChildItem -LiteralPath $_ -Filter 'yq*' -File -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -eq 'yq' })
            }) -join [IO.Path]::PathSeparator
            Get-Command yq -ErrorAction SilentlyContinue | Should -BeNullOrEmpty -Because 'the row is only meaningful once yq is really gone'
            $r = Invoke-Lint -Root $script:Root
        } finally { $env:PATH = $saved }
        $r.Out | Should -Match 'CANNOT ANSWER: yq is not on PATH'
        $r.Code | Should -Be 2
    }

    It 'CANNOT ANSWER (exit 2) when the yq on PATH is not mikefarah v4' -Skip:(-not $IsWindows) {
        $script:Root = New-Fixture @{ 'p/skills/alpha/SKILL.md' = (Skill 'alpha' 'a: b') }
        $fake = Join-Path ([System.IO.Path]::GetTempPath()) ("fakeyq-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $fake | Out-Null
        Set-Content -LiteralPath (Join-Path $fake 'yq.cmd') -Value '@echo yq 3.4.3' -Encoding ascii
        $saved = $env:PATH
        try {
            $env:PATH = $fake + [IO.Path]::PathSeparator + $saved
            $r = Invoke-Lint -Root $script:Root
        } finally { $env:PATH = $saved; Remove-Item -Recurse -Force $fake -ErrorAction SilentlyContinue }
        $r.Out | Should -Match "CANNOT ANSWER: yq on PATH is not mikefarah yq v4 \(got: 'yq 3\.4\.3'\)"
        $r.Code | Should -Be 2
    }
}

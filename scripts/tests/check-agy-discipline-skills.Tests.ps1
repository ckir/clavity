# scripts/tests/check-agy-discipline-skills.Tests.ps1
BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Lint     = Join-Path $script:RepoRoot 'scripts/check-agy-discipline-skills.ps1'

    # Stage a scratch -Root containing a VALID copy of EVERY shipped discipline skill, so a rejection
    # test that perturbs ONE skill fails on THAT defect, not on a MISSING sibling (SP-B: once
    # 'agy-capstone' joined $skills, a fixture staging only agy-first exited 1 for MISSING agy-capstone,
    # silently losing its discriminating power).
    function New-ScratchRoot {
        $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("agyskilltest-" + [guid]::NewGuid())
        foreach ($s in @('agy-first', 'agy-capstone')) {
            $dst = Join-Path $scratch "clavity-dotnet/plugin/skills/$s"
            New-Item -ItemType Directory -Path $dst -Force | Out-Null
            Copy-Item (Join-Path $script:RepoRoot "clavity-dotnet/plugin/skills/$s/SKILL.md") `
                      (Join-Path $dst 'SKILL.md')
        }
        return $scratch
    }
    $script:SkillPath = { param($root, $skill) Join-Path $root "clavity-dotnet/plugin/skills/$skill/SKILL.md" }
}

Describe 'check-agy-discipline-skills' {
    It 'passes when every shipped skill satisfies all invariants (real repo)' {
        $out = & $script:Lint 2>&1
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'agy-discipline skills OK'
    }

    Context 'rejection cases (each perturbs one skill; the other stays valid)' {
        It 'fails loudly on a non-ASCII character in <skill>' -ForEach @(
            @{ skill = 'agy-first' }, @{ skill = 'agy-capstone' }
        ) {
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            $body = (Get-Content -Raw $target) + "`nA stray em-dash `u{2014} here.`n"
            Set-Content -Path $target -Value $body -Encoding utf8
            & $script:Lint -Root $scratch 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
            Remove-Item -Recurse -Force $scratch
        }

        It 'fails when a required [VERDICT] form is missing from <skill>' -ForEach @(
            @{ skill = 'agy-first' }, @{ skill = 'agy-capstone' }
        ) {
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            $body = (Get-Content -Raw $target) -replace '\[VERDICT: SKIPPED-UNREACHABLE\]', '[VERDICT: GONE]'
            Set-Content -Path $target -Value $body -Encoding utf8
            & $script:Lint -Root $scratch 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
            Remove-Item -Recurse -Force $scratch
        }

        It 'fails cleanly (no unhandled crash) on an empty <skill> file' -ForEach @(
            @{ skill = 'agy-first' }, @{ skill = 'agy-capstone' }
        ) {
            # Capstone R1 (Cascade): a 0-byte SKILL.md made Get-Content -Raw return $null, and
            # $raw.Contains() threw an unhandled terminating error instead of a clean Fail.
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            Set-Content -Path $target -Value '' -NoNewline -Encoding utf8
            $out = & $script:Lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 1
            ($out -join "`n") | Should -Match 'EMPTY'
            ($out -join "`n") | Should -Not -Match 'null-valued expression'
            Remove-Item -Recurse -Force $scratch
        }

        It 'fails when name: is absent from <skill> real frontmatter even if present in the body' -ForEach @(
            @{ skill = 'agy-first' }, @{ skill = 'agy-capstone' }
        ) {
            # Capstone R1 (Protocol/Mechanism): the old lazy (?ms).*? frontmatter regex spanned past the
            # closing fence, so a 'name:' smuggled into the body plus any body '---' falsely satisfied it.
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            $real = Get-Content -Raw $target
            $body = ($real -replace "(?m)^name:\s*$skill\s*\r?\n", '') + "`nname: $skill`n---`n"
            Set-Content -Path $target -Value $body -NoNewline -Encoding utf8
            & $script:Lint -Root $scratch 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
            Remove-Item -Recurse -Force $scratch
        }
    }
}

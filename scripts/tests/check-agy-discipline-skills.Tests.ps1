# scripts/tests/check-agy-discipline-skills.Tests.ps1
BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Lint     = Join-Path $script:RepoRoot 'scripts/check-agy-discipline-skills.ps1'
}

Describe 'check-agy-discipline-skills' {
    It 'passes when the shipped agy-first skill satisfies every invariant' {
        $out = & $script:Lint 2>&1
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'agy-discipline skills OK'
    }

    It 'fails loudly if a shipped skill contains a non-ASCII character' {
        # Copy the real skill into a scratch tree, inject an em-dash, point the lint at it.
        $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("agyskilltest-" + [guid]::NewGuid())
        $dst = Join-Path $scratch 'clavity-dotnet/plugin/skills/agy-first'
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
        $src = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/skills/agy-first/SKILL.md'
        $body = (Get-Content -Raw $src) + "`nA stray em-dash `u{2014} here.`n"
        Set-Content -Path (Join-Path $dst 'SKILL.md') -Value $body -Encoding utf8
        & $script:Lint -Root $scratch 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
        Remove-Item -Recurse -Force $scratch
    }

    It 'fails if a required [VERDICT] form is missing' {
        $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("agyskilltest2-" + [guid]::NewGuid())
        $dst = Join-Path $scratch 'clavity-dotnet/plugin/skills/agy-first'
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
        $src = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/skills/agy-first/SKILL.md'
        $body = (Get-Content -Raw $src) -replace '\[VERDICT: SKIPPED-UNREACHABLE\]', '[VERDICT: GONE]'
        Set-Content -Path (Join-Path $dst 'SKILL.md') -Value $body -Encoding utf8
        & $script:Lint -Root $scratch 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
        Remove-Item -Recurse -Force $scratch
    }
}

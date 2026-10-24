<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

# Fixture trees under $TestDrive for scripts/check-tracker-format-excerpt.ps1, plus one row against the real repository (last).
BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'check-tracker-format-excerpt.ps1'
    if (-not (Test-Path -LiteralPath $script:Script -PathType Leaf)) { throw "check-tracker-format-excerpt.ps1 not found at $script:Script - this suite cannot run" }
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).ProviderPath
    $script:Block = "<!-- tracker-format:begin -->`nEXCERPT with ``code`` and a section sign §.`n<!-- tracker-format:end -->"
    $script:Skills = foreach ($plugin in 'clavity-dotnet', 'clavity-classic') { foreach ($skill in 'open-issues', 'agy-capstone', 'agy-test-audit') { "$plugin/plugin/skills/$skill/SKILL.md" } }

    function New-ExcerptTree {
        $root = Join-Path $TestDrive ('ex-' + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force
        [IO.File]::WriteAllText((Join-Path $root 'docs/tracker-format.md'), "# F`n`n$($script:Block)`n")
        foreach ($rel in $script:Skills) {
            $p = Join-Path $root ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            $null = New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force
            [IO.File]::WriteAllText($p, "intro`n`n$($script:Block)`n`nrest`n")
        }
        $root
    }
    function Invoke-Parity([string]$Root) {
        # Decode the child as UTF-8: the section sign in the fixture block must survive the pipe (OEM code page otherwise).
        $prev = [Console]::OutputEncoding
        try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); $out = & pwsh -NoProfile -File $script:Script -RepoRoot $Root 2>&1 | Out-String; $code = $LASTEXITCODE }
        finally { [Console]::OutputEncoding = $prev }
        [pscustomobject]@{ Out = $out; Code = $code }
    }
}

Describe 'check-tracker-format-excerpt.ps1' {
    It 'exits 0 when every skill copy equals the canonical block' {
        $r = Invoke-Parity (New-ExcerptTree); $r.Code | Should -Be 0 -Because $r.Out
    }
    It 'exits 1 and names the file when ONE character differs' {
        $root = New-ExcerptTree
        $f = Join-Path $root 'clavity-classic/plugin/skills/agy-capstone/SKILL.md'
        [IO.File]::WriteAllText($f, ([IO.File]::ReadAllText($f)).Replace('EXCERPT with', 'EXCERPT witH'))
        $r = Invoke-Parity $root; $r.Code | Should -Be 1; $r.Out | Should -Match 'EXCERPT-DRIFT.*clavity-classic/plugin/skills/agy-capstone/SKILL\.md'
    }
    It 'exits 1 when a skill has NO block' {
        $root = New-ExcerptTree
        [IO.File]::WriteAllText((Join-Path $root 'clavity-dotnet/plugin/skills/open-issues/SKILL.md'), "no block here`n")
        $r = Invoke-Parity $root; $r.Code | Should -Be 1; $r.Out | Should -Match 'EXCERPT-MISSING.*open-issues'
    }
    It 'exits 1 when a skill carries the block TWICE' {
        $root = New-ExcerptTree
        [IO.File]::WriteAllText((Join-Path $root 'clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md'), "$($script:Block)`n$($script:Block)`n")
        $r = Invoke-Parity $root; $r.Code | Should -Be 1; $r.Out | Should -Match 'EXCERPT-DUPLICATE.*agy-test-audit'
    }
    It 'exits 1 when an enrolled skill file is missing altogether' {
        $root = New-ExcerptTree
        Remove-Item -LiteralPath (Join-Path $root 'clavity-classic/plugin/skills/open-issues/SKILL.md')
        $r = Invoke-Parity $root; $r.Code | Should -Be 1; $r.Out | Should -Match 'EXCERPT-MISSING.*file not found'
    }
    It 'exits 2 when the canonical doc has no block' {
        $root = New-ExcerptTree
        [IO.File]::WriteAllText((Join-Path $root 'docs/tracker-format.md'), "# F`n`nno block`n")
        (Invoke-Parity $root).Code | Should -Be 2
    }
    It 'exits 2 when the canonical doc is gone' {
        $root = New-ExcerptTree
        Remove-Item -LiteralPath (Join-Path $root 'docs/tracker-format.md')
        (Invoke-Parity $root).Code | Should -Be 2
    }
}

Describe 'check-tracker-format-excerpt.ps1 - the real repository' {
    It 'passes on the committed skills and docs' {
        $r = Invoke-Parity $script:RepoRoot
        $r.Code | Should -Be 0 -Because "the six skill copies must equal docs/tracker-format.md; output was:`n$($r.Out)"
    }
    It 'enrols exactly the skills that route a deferral to a ROADMAP (a fourth one fails this row until enrolled)' {
        # Enrolment is explicit (the three skills whose text routes a finding to a tracker), and two facts keep it honest:
        # (1) exactly those three carry the block; (2) no OTHER skill both names the conveyor and a ROADMAP without carrying it.
        $skillRoot = foreach ($plugin in 'clavity-dotnet', 'clavity-classic') { Join-Path $script:RepoRoot $plugin 'plugin' 'skills' }
        $withBlock = foreach ($d in Get-ChildItem -LiteralPath $skillRoot -Directory) {
            $f = Join-Path $d.FullName 'SKILL.md'
            if ((Test-Path -LiteralPath $f -PathType Leaf) -and ([IO.File]::ReadAllText($f) -match 'tracker-format:begin')) { $d.Name }
        }
        (@($withBlock) | Sort-Object -Unique) -join ',' | Should -BeExactly 'agy-capstone,agy-test-audit,open-issues'
        $lacking = foreach ($d in Get-ChildItem -LiteralPath $skillRoot -Directory) {
            $f = Join-Path $d.FullName 'SKILL.md'
            if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
            $t = [IO.File]::ReadAllText($f)
            if ($t -match 'local-anomalies\.md' -and $t -match 'ROADMAP\.md' -and $t -notmatch 'tracker-format:begin') { $d.Name }
        }
        (@($lacking) -join ',') | Should -BeExactly '' -Because 'a skill that names the conveyor and a ROADMAP must carry the tracker-format excerpt'
    }
}

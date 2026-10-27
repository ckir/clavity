<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

# project-store.sh compiles the agy-driving knowledge store (agy-autotrain/knowledge/rules) into a GROWTH PROPOSAL on stdout. A fresh
# machine injected SEED only for three days because nothing projected the store (backlog stub fresh-install-injects-seed-only); the
# projection is a judgement the human makes, so the script only PROPOSES: it never writes, and the proposal goes through the normal
# agy-curate human gate and `curate-commit` (GROWTH has one gated writer).
Describe 'project-store.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Script = Join-Path $script:RepoRoot 'agy-autotrain/skills/agy-curate/project-store.sh'
        $script:Crit = 'CRITICAL ANTI-PATTERNS - newly learned, additive to SEED'
        $script:Load = 'LOAD-BEARING ASSUMPTIONS - newly learned, additive to SEED'

        function New-Rule { param([string]$Dir, [string]$File, [string]$Title, [string]$Section, [string]$Body)
            $text = "<!-- a rule in the store -->`n`n# $Title`n`n**Section:** $Section`n**Origin:** split from somewhere`non two lines.`n`n$Body`n"
            [IO.File]::WriteAllText((Join-Path $Dir $File), $text, [Text.UTF8Encoding]::new($false))
        }
        # Two sections; INDEX order is b, a, c - deliberately NOT alphabetical.
        function New-Store {
            $dir = New-TestTempPath 'projstore'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            New-Rule $dir 'b-rule.md' 'rule b' $script:Crit "- RULE B first line,`n  continued line."
            New-Rule $dir 'a-rule.md' 'rule a' $script:Crit '- RULE A one line.'
            New-Rule $dir 'c-rule.md' 'rule c' $script:Load '- RULE C.'
            $index = "# store index`n<!-- not a rule -->`n`n## $($script:Crit)`n`n- [rule b](b-rule.md) - B desc`n- [rule a](a-rule.md) - A desc`n`n## $($script:Load)`n`n- [rule c](c-rule.md) - C desc`n"
            [IO.File]::WriteAllText((Join-Path $dir 'INDEX.md'), $index, [Text.UTF8Encoding]::new($false))
            $dir
        }
        function Invoke-Proj { param([string[]]$Arguments, [hashtable]$Env = @{})
            $e = @{ HOME = (New-TestTempPath 'projhome'); USERPROFILE = (New-TestTempPath 'projhome') }
            foreach ($k in $Env.Keys) { $e[$k] = $Env[$k] }
            New-Item -ItemType Directory -Path $e.HOME -Force | Out-Null
            Invoke-BashHook -HookPath $script:Script -Payload '' -Arguments $Arguments -Env $e
        }
        $script:Expected = "[[!] $($script:Crit)]`n- RULE B first line,`n  continued line.`n- RULE A one line.`n`n[$($script:Load)]`n- RULE C.`n"
    }

    It 'compiles the store in INDEX order, with the section headers GROWTH uses, and exits 0' {
        $d = New-Store
        try {
            $r = Invoke-Proj @('--store', $d)
            $r.ExitCode | Should -Be 0 -Because $r.StdErr
            $r.StdOut | Should -BeExactly $script:Expected.TrimEnd("`n")   # Invoke-BashHook drops the final newline of a capture
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'puts the [!] marker on the CRITICAL section only' {
        $d = New-Store
        try {
            $out = (Invoke-Proj @('--store', $d)).StdOut
            @($out -split "`n" | Where-Object { $_ -like '`[*' }) | Should -Be @("[[!] $($script:Crit)]", "[$($script:Load)]")
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'strips CRLF so a Windows checkout compiles to the same bytes' {
        $d = New-Store
        try {
            foreach ($f in Get-ChildItem -LiteralPath $d -Filter *.md) {
                [IO.File]::WriteAllText($f.FullName, ([IO.File]::ReadAllText($f.FullName) -replace "`n", "`r`n"), [Text.UTF8Encoding]::new($false))
            }
            $r = Invoke-Proj @('--store', $d)
            $r.ExitCode | Should -Be 0 -Because $r.StdErr
            $r.StdOut | Should -BeExactly $script:Expected.TrimEnd("`n")   # Invoke-BashHook drops the final newline of a capture
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 5 and prints nothing when the store has no rules' {
        $d = New-TestTempPath 'projempty'; New-Item -ItemType Directory -Path $d -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $d 'INDEX.md'), "# store index`n`n## $($script:Crit)`n`n(none yet)`n")
        try {
            $r = Invoke-Proj @('--store', $d)
            $r.ExitCode | Should -Be 5
            $r.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 3 and names the file when a rule carries a non-ASCII byte (GROWTH is ASCII by policy)' {
        $d = New-Store
        try {
            [IO.File]::WriteAllText((Join-Path $d 'a-rule.md'), ([IO.File]::ReadAllText((Join-Path $d 'a-rule.md')).Replace('RULE A one line.', "RULE A caf$([char]0xE9).")), [Text.UTF8Encoding]::new($false))
            $r = Invoke-Proj @('--store', $d)
            $r.ExitCode | Should -Be 3
            $r.StdErr | Should -Match 'a-rule\.md'
            $r.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 2 and names the file when INDEX links a rule that is not on disk' {
        $d = New-Store
        try {
            Remove-Item -LiteralPath (Join-Path $d 'c-rule.md')
            $r = Invoke-Proj @('--store', $d)
            $r.ExitCode | Should -Be 2
            $r.StdErr | Should -Match 'c-rule\.md'
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 6 when a rule file names a different Section than the INDEX heading it is listed under' {
        $d = New-Store
        try {
            [IO.File]::WriteAllText((Join-Path $d 'a-rule.md'), ([IO.File]::ReadAllText((Join-Path $d 'a-rule.md')).Replace($script:Crit, $script:Load)), [Text.UTF8Encoding]::new($false))
            $r = Invoke-Proj @('--store', $d)
            $r.ExitCode | Should -Be 6
            $r.StdErr | Should -Match 'a-rule\.md'
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses an INDEX link that leaves the store (a path separator or ..) instead of reading outside it' -ForEach @(
        @{ Link = '../outside.md' }
        @{ Link = 'sub/rule.md' }
        @{ Link = '..\\outside.md' }
    ) {
        $d = New-Store
        try {
            Set-Content -LiteralPath (Join-Path (Split-Path -Parent $d) 'outside.md') -Value "# o`n`n**Section:** $($script:Crit)`n`n- OUTSIDE RULE`n"
            $idx = (Get-Content -Raw -LiteralPath (Join-Path $d 'INDEX.md')).Replace('(a-rule.md)', "($Link)")
            [IO.File]::WriteAllText((Join-Path $d 'INDEX.md'), $idx, [Text.UTF8Encoding]::new($false))
            $r = Invoke-Proj @('--store', $d)
            $r.ExitCode | Should -Be 6
            $r.StdErr | Should -Match 'outside the store|not a plain file name'
            $r.StdOut | Should -Not -Match 'OUTSIDE RULE'
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath (Join-Path (Split-Path -Parent $d) 'outside.md') -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 6 when a rule file has no rule block' {
        $d = New-Store
        try {
            [IO.File]::WriteAllText((Join-Path $d 'a-rule.md'), "# rule a`n`n**Section:** $($script:Crit)`n`nno bullet here`n")
            $r = Invoke-Proj @('--store', $d)
            $r.ExitCode | Should -Be 6
            $r.StdErr | Should -Match 'a-rule\.md'
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # The combined header the readers inject is trimmedSEED + "\n\n" + trimmedGROWTH and must stay within MaxBytes (32 KiB): the budget
    # gate counts exactly that, so exactly the cap passes and one byte more fails.
    It 'passes the budget at exactly the 32768-byte combined cap and fails one byte over (<Size>)' -ForEach @(
        @{ Size = 32768; Code = 0 }
        @{ Size = 32769; Code = 4 }
    ) {
        $d = New-Store
        try {
            $growth = $script:Expected.TrimEnd("`n")
            $seedBytes = $Size - $growth.Length - 2            # trimmed SEED + "\n\n" + trimmed GROWTH = $Size, exactly
            $seed = Join-Path $d 'seed.md'
            [IO.File]::WriteAllText($seed, ('s' * $seedBytes) + "`n", [Text.UTF8Encoding]::new($false))   # one trailing newline: the reader trims it
            $r = Invoke-Proj @('--store', $d, '--seed', $seed)
            $r.ExitCode | Should -Be $Code -Because $r.StdErr
            if ($Code -eq 4) { $r.StdErr | Should -Match 'cap'; $r.StdOut | Should -BeNullOrEmpty }
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'drops the blank lines a rule file ends with, so they never open a gap between rules or sections' {
        $d = New-Store
        try {
            foreach ($f in 'a-rule.md', 'c-rule.md') { Add-Content -LiteralPath (Join-Path $d $f) -Value "`n`n   `n" -NoNewline }
            $r = Invoke-Proj @('--store', $d)
            $r.ExitCode | Should -Be 0 -Because $r.StdErr
            $r.StdOut | Should -BeExactly $script:Expected.TrimEnd("`n")
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'counts the SEED as the reader will see it: trailing spaces and tabs are trimmed before the cap is checked' {
        $d = New-Store
        try {
            $growth = $script:Expected.TrimEnd("`n")
            $seed = Join-Path $d 'seed.md'
            [IO.File]::WriteAllText($seed, ('s' * (32768 - $growth.Length - 2)) + "   `t  `n", [Text.UTF8Encoding]::new($false))
            $r = Invoke-Proj @('--store', $d, '--seed', $seed)
            $r.ExitCode | Should -Be 0 -Because ($r.StdErr + ' (trailing whitespace on the SEED must not count against the cap)')
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'never writes: the store and HOME are byte-identical before and after' {
        $d = New-Store
        $h = New-TestTempPath 'projhome2'; New-Item -ItemType Directory -Path $h -Force | Out-Null
        try {
            $snap = { param($p) (Get-ChildItem -LiteralPath $p -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" }) -join "`n" }
            $before = (& $snap $d) + (& $snap $h)
            $r = Invoke-Proj @('--store', $d) -Env @{ HOME = $h; USERPROFILE = $h }
            $r.ExitCode | Should -Be 0
            ((& $snap $d) + (& $snap $h)) | Should -BeExactly $before
        } finally { Remove-Item -LiteralPath $d, $h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It '--help prints usage and exits 0 without reading stdin or the store' {
        $r = Invoke-Proj @('--help')
        $r.ExitCode | Should -Be 0
        $r.StdOut | Should -Match 'project-store'
    }

    It 'compiles the REAL store: ASCII, 18 or more rules, under the cap, the CRITICAL header first' {
        $store = Join-Path $script:RepoRoot 'agy-autotrain/knowledge/rules'
        $r = Invoke-Proj @('--store', $store)
        $r.ExitCode | Should -Be 0 -Because $r.StdErr
        ([Text.Encoding]::UTF8.GetBytes($r.StdOut) | Where-Object { $_ -gt 127 }) | Should -BeNullOrEmpty
        @($r.StdOut -split "`n")[0] | Should -Match '^\[\[!\] CRITICAL ANTI-PATTERNS'
        $ruleFiles = @(Get-ChildItem -LiteralPath $store -Filter *.md | Where-Object Name -ne 'INDEX.md').Count
        @($r.StdOut -split "`n" | Where-Object { $_ -match '^- ' }).Count | Should -Be $ruleFiles -Because 'every rule file the INDEX lists is one top-level bullet'
        [Text.Encoding]::UTF8.GetByteCount($r.StdOut) | Should -BeLessThan 32768
    }

    It 'is named consistently: the agy-curate SKILL has the step, and the SessionStart nudge sends the reader to it by that name' {
        $skill = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'agy-autotrain/skills/agy-curate/SKILL.md')
        $skill | Should -Match '(?m)^## Project the knowledge store'
        $skill | Should -Match 'project-store\.sh'
        $hook = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'agy-autotrain/hooks/agy-curate-nudge.sh')
        $hook | Should -Match "Project the knowledge store"
        $hook | Should -Match 'project-store\.sh'
    }
}

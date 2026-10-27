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
            $r.StdOut | Should -BeNullOrEmpty -Because 'an error exit must not leak a partial proposal'
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 6 when a rule file names a different Section than the INDEX heading it is listed under' {
        $d = New-Store
        try {
            [IO.File]::WriteAllText((Join-Path $d 'a-rule.md'), ([IO.File]::ReadAllText((Join-Path $d 'a-rule.md')).Replace($script:Crit, $script:Load)), [Text.UTF8Encoding]::new($false))
            $r = Invoke-Proj @('--store', $d)
            $r.ExitCode | Should -Be 6
            $r.StdErr | Should -Match 'a-rule\.md'
            $r.StdOut | Should -BeNullOrEmpty -Because 'an error exit must not leak a partial proposal'
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
            $r.StdOut | Should -BeNullOrEmpty -Because 'an error exit must not leak a partial proposal'
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

    # SKILL.md tells the operator to run the helper with NO arguments, so the SEED it budgets against comes from the default lookup:
    # CLAVITY_GOLDEN_HEADER (a directory) if set, else <home>/.clavity. Every other cap row passes --seed, which skips that lookup.
    It 'budgets against the DEFAULT seed in the home .clavity directory when --seed is omitted (<Size>)' -ForEach @(
        @{ Size = 32768; Code = 0 }
        @{ Size = 32769; Code = 4 }
    ) {
        $d = New-Store
        $h = New-TestTempPath 'projhome3'; New-Item -ItemType Directory -Path (Join-Path $h '.clavity') -Force | Out-Null
        try {
            $growth = $script:Expected.TrimEnd("`n")
            [IO.File]::WriteAllText((Join-Path $h '.clavity/golden-header.seed.md'), ('s' * ($Size - $growth.Length - 2)) + "`n", [Text.UTF8Encoding]::new($false))
            $r = Invoke-Proj @('--store', $d) -Env @{ HOME = $h; USERPROFILE = $h }
            $r.ExitCode | Should -Be $Code -Because $r.StdErr
        } finally { Remove-Item -LiteralPath $d, $h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'lets CLAVITY_GOLDEN_HEADER win over the home .clavity directory when picking the default seed' {
        $d = New-Store
        $h = New-TestTempPath 'projhome4'; New-Item -ItemType Directory -Path (Join-Path $h '.clavity') -Force | Out-Null
        $g = New-TestTempPath 'projgh'; New-Item -ItemType Directory -Path $g -Force | Out-Null
        try {
            $utf8 = [Text.UTF8Encoding]::new($false)
            [IO.File]::WriteAllText((Join-Path $h '.clavity/golden-header.seed.md'), 's' * 40000, $utf8)   # over the cap: would exit 4 if it were read
            [IO.File]::WriteAllText((Join-Path $g 'golden-header.seed.md'), "small seed`n", $utf8)
            $r = Invoke-Proj @('--store', $d) -Env @{ HOME = $h; USERPROFILE = $h; CLAVITY_GOLDEN_HEADER = $g }
            $r.ExitCode | Should -Be 0 -Because $r.StdErr
            [IO.File]::WriteAllText((Join-Path $g 'golden-header.seed.md'), 's' * 40000, $utf8)
            [IO.File]::WriteAllText((Join-Path $h '.clavity/golden-header.seed.md'), "small seed`n", $utf8)
            (Invoke-Proj @('--store', $d) -Env @{ HOME = $h; USERPROFILE = $h; CLAVITY_GOLDEN_HEADER = $g }).ExitCode | Should -Be 4
        } finally { Remove-Item -LiteralPath $d, $h, $g -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # Invoke-BashHook captures stdout as text and drops the final newline, so the byte contract (the proposal ends in exactly one LF)
    # is read from a file the shell redirected to.
    It 'writes the proposal as exactly the expected bytes: one LF at the end, never a blank line' {
        $d = New-Store
        $out = New-TestTempPath 'projout'
        try {
            $bash = Get-GitBashOrThrow
            & $bash -c ('bash "$1" --store "$2" > "$3"' ) _ ($script:Script -replace '\\','/') ($d -replace '\\','/') ($out -replace '\\','/')
            $bytes = [IO.File]::ReadAllBytes($out)
            $bytes[-1] | Should -Be 10
            $bytes[-2] | Should -Not -Be 10
            [Text.Encoding]::UTF8.GetString($bytes) | Should -BeExactly $script:Expected
        } finally { Remove-Item -LiteralPath $d, $out -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # The seam no unit row crosses: helper output -> the one gated writer (`curate-commit`) -> the file the readers and the nudge look at.
    It 'feeds curate-commit: the published GROWTH is the proposal byte for byte, has its sidecar, and the SessionStart nudge goes quiet' {
        $exe = $env:CLAVITY_CURATE_COMMIT_EXE
        if (-not $exe) {
            $cand = Join-Path $script:RepoRoot 'clavity-classic/target/debug/clavity'
            if ($IsWindows) { $cand += '.exe' }
            $exe = if (Test-Path -LiteralPath $cand) { $cand } else { (Get-Command clavity-ls, clavity -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
        }
        if (-not $exe) { Set-ItResult -Skipped -Because 'APPROVED:NeedsTool:clavity: no curate-commit binary (CLAVITY_CURATE_COMMIT_EXE, clavity-classic debug build, clavity-ls or clavity on PATH) is available'; return }
        $d = New-Store
        $g = New-TestTempPath 'projgh2'; New-Item -ItemType Directory -Path $g -Force | Out-Null
        $plug = New-TestTempPath 'projplug'; New-Item -ItemType Directory -Path (Join-Path $plug 'knowledge') -Force | Out-Null
        try {
            Copy-Item -LiteralPath $d -Destination (Join-Path $plug 'knowledge/rules') -Recurse
            $proposal = (Invoke-Proj @('--store', $d)).StdOut + "`n"
            $psi = [Diagnostics.ProcessStartInfo]::new($exe)
            $psi.ArgumentList.Add('curate-commit')
            $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
            $psi.Environment['CLAVITY_GOLDEN_HEADER'] = $g
            $p = [Diagnostics.Process]::Start($psi)
            $b = [Text.UTF8Encoding]::new($false).GetBytes($proposal)
            $p.StandardInput.BaseStream.Write($b, 0, $b.Length); $p.StandardInput.Close()
            $null = $p.StandardOutput.ReadToEnd(); $err = $p.StandardError.ReadToEnd(); $p.WaitForExit()
            $p.ExitCode | Should -Be 0 -Because $err
            $growth = Join-Path $g 'golden-header.growth.md'
            [IO.File]::ReadAllText($growth).TrimEnd() | Should -BeExactly $proposal.TrimEnd()
            Test-Path -LiteralPath ($growth + '.sha256') | Should -BeTrue
            $home2 = Join-Path $plug 'home'; New-Item -ItemType Directory -Path $home2 -Force | Out-Null
            $inbox = Join-Path $home2 '.clavity'; New-Item -ItemType Directory -Path $inbox -Force | Out-Null
            $hook = Join-Path $script:RepoRoot 'agy-autotrain/hooks/agy-curate-nudge.sh'
            $nudgeEnv = @{ CLAUDE_PLUGIN_ROOT = ($plug -replace '\\','/'); HOME = ($home2 -replace '\\','/'); USERPROFILE = ($home2 -replace '\\','/'); CLAVITY_GOLDEN_HEADER = ($g -replace '\\','/') }
            (Invoke-BashHook -HookPath $hook -Payload '{}' -Env $nudgeEnv).StdOut | Should -BeNullOrEmpty
            Remove-Item -LiteralPath $growth, ($growth + '.sha256')
            (Invoke-BashHook -HookPath $hook -Payload '{}' -Env $nudgeEnv).StdOut | Should -Match 'SEED only' -Because 'the same environment WITHOUT the published GROWTH must warn, or the silence above proves nothing'
        } finally { Remove-Item -LiteralPath $d, $g, $plug -Recurse -Force -ErrorAction SilentlyContinue }
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

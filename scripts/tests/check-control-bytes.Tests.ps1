<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

BeforeAll {
    $script:Script   = Join-Path $PSScriptRoot '..' 'check-control-bytes.ps1'
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    . $script:Script -RepoRoot $script:RepoRoot

    # Every fixture is built from [byte[]] at runtime: this SOURCE carries no raw control byte.
    function script:New-Fixture {
        param([string]$Dir, [byte[]]$Bytes, [string]$Name = 'f.md')
        $p = Join-Path $Dir $Name
        [IO.File]::WriteAllBytes($p, $Bytes)
        $Name
    }
    function script:Get-Ascii { param([string]$s) [Text.Encoding]::ASCII.GetBytes($s) }

    # lefthook.yml, read as lines: where the pre-push hook starts and ends, and the control-bytes command's own lines and globs.
    # Deliberately not a YAML parser (none is guaranteed on every runner): it fails closed, so a layout it cannot read makes the
    # rows below red rather than vacuous.
    function script:Get-ControlBytesHook {
        $lines = @(Get-Content -LiteralPath (Join-Path $script:RepoRoot 'lefthook.yml'))
        $hookStart = [Array]::FindIndex($lines, [Predicate[string]]{ param($l) $l -match '^pre-push:\s*$' })
        $hookEnd = $lines.Count
        for ($i = $hookStart + 1; $hookStart -ge 0 -and $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\S' -and $lines[$i] -notmatch '^\s*#') { $hookEnd = $i; break }
        }
        $cmd = [Array]::FindIndex($lines, [Predicate[string]]{ param($l) $l -match '^\s{4}control-bytes:\s*$' })
        $block = @()
        for ($i = $cmd + 1; $cmd -ge 0 -and $i -lt $lines.Count -and $lines[$i] -notmatch '^\s{4}\S'; $i++) { $block += $lines[$i] }
        $globs = @(foreach ($l in $block) { $m = [regex]::Match($l, '^\s*-\s*"(.+)"\s*$'); if ($m.Success) { $m.Groups[1].Value } })
        [pscustomobject]@{ HookStart = $hookStart; HookEnd = $hookEnd; Command = $cmd; Block = $block; Globs = $globs }
    }
}

Describe 'check-control-bytes.ps1' {
    It 'flags a NUL with its line and column' {
        $bytes = [byte[]]((Get-Ascii "ab`ncd") + [byte[]]@(0) + (Get-Ascii "e`n"))
        $rel = New-Fixture -Dir $TestDrive -Bytes $bytes
        $hits = @(Get-ControlByteHits -RepoRoot $TestDrive -RelPaths @($rel))
        $hits.Count | Should -Be 1
        $hits[0].Line | Should -Be 2
        $hits[0].Column | Should -Be 3
        $hits[0].Byte | Should -Be 0
    }

    It 'flags a backspace, which git still classifies as text' {
        $bytes = [byte[]]((Get-Ascii "ab") + [byte[]]@(8) + (Get-Ascii "cd`n"))
        $rel = New-Fixture -Dir $TestDrive -Bytes $bytes
        $hits = @(Get-ControlByteHits -RepoRoot $TestDrive -RelPaths @($rel))
        $hits.Count | Should -Be 1
        $hits[0].Byte | Should -Be 8
    }

    It 'flags DEL' {
        $bytes = [byte[]]((Get-Ascii "ab") + [byte[]]@(127) + (Get-Ascii "cd`n"))
        $rel = New-Fixture -Dir $TestDrive -Bytes $bytes
        $hits = @(Get-ControlByteHits -RepoRoot $TestDrive -RelPaths @($rel))
        $hits.Count | Should -Be 1
    }

    It 'flags every C0 byte from 10 to 31 and not a space, at both edges of a file with no final newline' {
        # ESC at offset 0, then VT, FF, and US (31, the top of the C0 range) as the very last byte; the space (32)
        # is the near-miss that must NOT be flagged. The rows above use only 0, 7, 8 and 127, so a bound of 9 in
        # place of 32 would have passed them all.
        $bytes = [byte[]](@(27) + @(Get-Ascii 'a') + @(32) + @(Get-Ascii 'b') + @(11) + @(Get-Ascii 'c') + @(12) + @(Get-Ascii 'd') + @(31))
        $rel = New-Fixture -Dir $TestDrive -Bytes $bytes
        $hits = @(Get-ControlByteHits -RepoRoot $TestDrive -RelPaths @($rel))
        (@($hits | ForEach-Object { "$($_.Byte)@$($_.Column)" }) -join ',') | Should -BeExactly '27@1,11@5,12@7,31@9'
    }

    It 'passes TAB, CR and LF - the legitimate whitespace' {
        $bytes = [byte[]](@(Get-Ascii "a") + @(9, 13, 10) + @(Get-Ascii "b") + @(13, 10))
        $rel = New-Fixture -Dir $TestDrive -Bytes $bytes
        $hits = @(Get-ControlByteHits -RepoRoot $TestDrive -RelPaths @($rel))
        $hits.Count | Should -Be 0
    }

    It 'catches the real pre-repair ledger at its real position' {
        $repo = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path    # scripts/tests -> repo root
        & git -C $repo cat-file -e 'b0e03801^{commit}' 2>$null
        if ($LASTEXITCODE -ne 0) {
            Set-ItResult -Skipped -Because 'shallow clone: b0e03801 is not present (CI checks out with fetch-depth 1)'
            return
        }
        $blobPath = Join-Path $TestDrive 'ledger-b0e03801.md'
        $psi = [Diagnostics.ProcessStartInfo]::new('git', "-C `"$repo`" cat-file blob b0e03801:docs/agy-test-audit-ledger.md")
        $psi.RedirectStandardOutput = $true; $psi.UseShellExecute = $false
        $p  = [Diagnostics.Process]::Start($psi)          # $p is the PROCESS; StandardOutput lives on it, not on $psi
        $fs = [IO.File]::Create($blobPath); $p.StandardOutput.BaseStream.CopyTo($fs); $fs.Close(); $p.WaitForExit()
        $p.ExitCode | Should -Be 0 -Because 'the blob extraction itself failed - this is a setup failure, not a gate result'
        $hits = @(Get-ControlByteHits -RepoRoot $TestDrive -RelPaths @('ledger-b0e03801.md'))
        $hits.Count | Should -Be 1
        $hits[0].Line | Should -Be 43
        $hits[0].Column | Should -Be 1508
        $hits[0].Byte | Should -Be 0
    }

    It 'the main script exits 1 on a tracked offender and 0 when the offender is untracked' {
        $d = Join-Path $TestDrive 'repo6'
        New-Item -ItemType Directory -Path $d | Out-Null
        & git -C $d init -q 2>&1 | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $d 'a.md'), [byte[]](@(Get-Ascii "x") + @(7) + @(Get-Ascii "y`n")))
        $out1 = & pwsh -NoProfile -File $script:Script -RepoRoot $d 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because 'an untracked file is out of scope'
        & git -C $d add a.md
        $out2 = & pwsh -NoProfile -File $script:Script -RepoRoot $d 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out2 | Should -Match 'a\.md:1:'
        $out2 | Should -Match 'byte=0x07'
    }

    It 'scans a tracked PowerShell script too, and still ignores a tracked file of another type' {
        # ROADMAP 93.9: a Pester suite once held three raw NUL bytes in a comment and no gate could see it, because only *.md was listed.
        $d = Join-Path $TestDrive 'repo8'
        New-Item -ItemType Directory -Path $d | Out-Null
        & git -C $d init -q 2>&1 | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $d 'a.ps1'), [byte[]](@(Get-Ascii "# x") + @(0) + @(Get-Ascii "y`n")))
        [IO.File]::WriteAllBytes((Join-Path $d 'b.bin'), [byte[]](@(Get-Ascii "x") + @(0) + @(Get-Ascii "y`n")))
        & git -C $d add a.ps1 b.bin
        $out = & pwsh -NoProfile -File $script:Script -RepoRoot $d 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'a\.ps1:1:4 byte=0x00'
        $out | Should -Not -Match 'b\.bin'
    }

    It 'the pre-push hook runs the gate when a push touches a PowerShell script, as CI does' {
        # The script scans tracked *.md AND *.ps1 (ROADMAP 93.9) and ci-control-bytes.yml triggers on both, but the local hook once
        # globbed Markdown only, so a NUL committed in a *.ps1 reached CI before anything said so. The glob is the third list
        # of "what this gate cares about"; this row compares it with the file types the script scans.
        $hook = Get-ControlBytesHook
        $hook.Command | Should -BeGreaterOrEqual 0 -Because 'the control-bytes command must exist in lefthook.yml, or this row proves nothing'
        $globs = $hook.Globs
        $globs.Count | Should -BeGreaterThan 0 -Because 'a glob list that parsed as empty would make the assertions below vacuous'
        # lefthook's `**/` form matches files in sub-directories only: a root-level file (README.md, DevelopersCockpit.ps1) needs the
        # bare `*.ext` form as well. Measured with lefthook 2.1.17 in a scratch repo: `**/*.ps1` alone skips a root `a.ps1`.
        $globs | Should -Contain '**/*.md'
        $globs | Should -Contain '*.md' -Because 'a push that changes only a root-level Markdown file must still run the gate'
        $globs | Should -Contain '**/*.ps1' -Because 'a push that changes only a PowerShell script must still run the control-byte gate locally'
        $globs | Should -Contain '*.ps1' -Because 'a root-level PowerShell script (DevelopersCockpit.ps1) is not matched by the **/ form'
        $globs | Should -Contain 'scripts/check-control-bytes.ps1' -Because 'breaking the gate itself must trigger it'
    }

    It 'the control-bytes command sits in the pre-push hook and runs the gate unconditionally' {
        # Moving the block into another hook (pre-commit) keeps every glob right and silently stops the push from running the gate;
        # a `skip`, `exclude` or `only` key, or a `run` that is not the gate, disarms it with the globs untouched.
        $hook = Get-ControlBytesHook
        $hook.HookStart | Should -BeGreaterOrEqual 0 -Because 'lefthook.yml must have a pre-push hook'
        $hook.Command | Should -BeGreaterThan $hook.HookStart -Because 'the control-bytes command must be inside the pre-push hook'
        $hook.Command | Should -BeLessThan $hook.HookEnd -Because 'the control-bytes command must be inside the pre-push hook, not a later hook'
        ($hook.Block -join "`n") | Should -Match '(?m)^\s+run:\s+just check-control-bytes\s*$'
        @($hook.Block | Where-Object { $_ -match '^\s*(skip|exclude|only|files|root|stage_fixed|fail_text|env):' }) |
            Should -BeNullOrEmpty -Because 'a key that skips, narrows or redirects the command disarms it while every glob stays right'
    }

    It 'the hook globs and the CI path filter cover every file type the script scans' {
        # The script lists what it scans (`ls-files -z -- '*.md' '*.ps1'`); the hook glob and the CI paths are the other two
        # copies of that list. This row compares them, so a third type added to the script and not to them goes red.
        $src = Get-Content -Raw -LiteralPath $script:Script
        $m = [regex]::Match($src, "ls-files -z -- ((?:'[^']+'\s*)+)")
        $m.Success | Should -BeTrue -Because 'the script must still list its file types on one ls-files line, or this row cannot read them'
        $patterns = @([regex]::Matches($m.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        $patterns.Count | Should -BeGreaterThan 0
        $globs = (Get-ControlBytesHook).Globs
        $ci = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot '.github' 'workflows' 'ci-control-bytes.yml')
        foreach ($p in $patterns) {
            $globs | Should -Contain $p -Because "a root-level file of type $p must run the hook"
            $globs | Should -Contain "**/$p" -Because "a nested file of type $p must run the hook"
            [regex]::Matches($ci, [regex]::Escape("'**/$p'")).Count |
                Should -BeGreaterOrEqual 2 -Because "ci-control-bytes.yml must trigger on $p for both push and pull_request"
        }
    }

    It 'fails closed outside a git repository' {
        $d = Join-Path $TestDrive 'nogit7'
        New-Item -ItemType Directory -Path $d | Out-Null
        $out = & pwsh -NoProfile -File $script:Script -RepoRoot $d 2>&1 | Out-String
        $LASTEXITCODE | Should -Not -Be 0
        # The error renderer wraps at the console width; collapse whitespace and the '|' gutter so the wrap cannot split the phrase.
        ($out -replace '[\s|]+', ' ') | Should -Match 'cannot list the files'
    }

    It 'the repository itself is clean' {
        $files = @(Get-TrackedScanFiles -RepoRoot $script:RepoRoot)
        $hits = @(Get-ControlByteHits -RepoRoot $script:RepoRoot -RelPaths $files)
        (@($hits | ForEach-Object { "$($_.Path):$($_.Line):$($_.Column)" }) -join ', ') | Should -BeExactly ''
    }
}

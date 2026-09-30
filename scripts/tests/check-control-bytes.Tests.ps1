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

    It 'fails closed outside a git repository' {
        $d = Join-Path $TestDrive 'nogit7'
        New-Item -ItemType Directory -Path $d | Out-Null
        $out = & pwsh -NoProfile -File $script:Script -RepoRoot $d 2>&1 | Out-String
        $LASTEXITCODE | Should -Not -Be 0
        # The error renderer wraps at the console width; collapse whitespace and the '|' gutter so the wrap cannot split the phrase.
        ($out -replace '[\s|]+', ' ') | Should -Match 'cannot list the files'
    }

    It 'the repository itself is clean' {
        $files = @(Get-TrackedMarkdown -RepoRoot $script:RepoRoot)
        $hits = @(Get-ControlByteHits -RepoRoot $script:RepoRoot -RelPaths $files)
        (@($hits | ForEach-Object { "$($_.Path):$($_.Line):$($_.Column)" }) -join ', ') | Should -BeExactly ''
    }
}

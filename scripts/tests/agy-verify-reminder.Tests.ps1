# scripts/tests/agy-verify-reminder.Tests.ps1
# NEW in Branch 21 (Task 6): .claude/hooks/agy-verify-reminder.sh had NO suite of its own. These rows are the behaviour
# floor the process-budget rows lean on - a budget row alone proves the hook is CHEAP, not that it still does its job.
Describe 'agy-verify-reminder.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot '.claude/hooks/agy-verify-reminder.sh'
        $script:GitUsr = Join-Path (Split-Path -Parent (Split-Path -Parent (Get-GitBashOrThrow))) 'usr\bin'
        $script:JqDir = Split-Path -Parent (Get-Command jq).Source

        # A throwaway "clavity repo" holding a one-row assertions table, plus a fake agy the hook finds via PATH.
        # The fake keeps the version deterministic: the REAL agy's output floats with its install.
        function New-VerifyFx {
            param([string]$DotnetCell = 'PASS 9.9.9', [string]$AgyOut = 'agy 9.9.9', [string]$DirName = 'repo')
            $root = Join-Path ([IO.Path]::GetTempPath()) ('avr-' + [Guid]::NewGuid().ToString('N'))
            $cwd = Join-Path $root $DirName
            New-Item -ItemType Directory -Force -Path (Join-Path $cwd 'agy-autotrain/verify'), (Join-Path $root 'fakebin') | Out-Null
            @('| id | dotnet | classic |', '|----|--------|---------|', "| A1 | $DotnetCell | N/A |") |
                Set-Content -LiteralPath (Join-Path $cwd 'agy-autotrain/verify/assertions.md')
            [IO.File]::WriteAllText((Join-Path $root 'fakebin/agy'), "#!/bin/sh`necho '$AgyOut'`n")
            [pscustomobject]@{ Root = $root; Cwd = $cwd
                Path = ((Join-Path $root 'fakebin') + ';' + $script:GitUsr + ';' + $script:JqDir + ';C:\WINDOWS\system32') }
        }
        function Invoke-Verify {
            param($Fx, [string]$CwdJson = $null)
            if (-not $CwdJson) { $CwdJson = ($Fx.Cwd) -replace '\\', '\\' }
            Invoke-BashHook -HookPath $script:Hook -Payload ('{"cwd":"' + $CwdJson + '"}') -Env @{ PATH = $Fx.Path }
        }
    }

    It 'the hook file exists (guard: every assertion below is vacuous without it)' {
        Test-Path -LiteralPath $script:Hook | Should -BeTrue
    }

    It 'EMITS for a stale PASS cell (recorded version behind the live one)' {
        $f = New-VerifyFx -DotnetCell 'PASS 1.0.0'
        try {
            $r = Invoke-Verify $f
            $r.StdOut   | Should -Match 'A1 \[dotnet\] PASS 1\.0\.0 \(live 9\.9\.9\)'
            $r.ExitCode | Should -Be 0
        } finally { Remove-Item $f.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'stays SILENT when every applicable cell is current' {
        $f = New-VerifyFx -DotnetCell 'PASS 9.9.9'
        try { (Invoke-Verify $f).StdOut | Should -BeNullOrEmpty } finally { Remove-Item $f.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'takes the LEFTMOST version from `agy --version` when the line carries two version-shaped tokens' {
        # A DISTRACTOR for the version matcher: the second token is also a valid x.y.z. The cell matches the FIRST.
        $f = New-VerifyFx -DotnetCell 'PASS 9.9.9' -AgyOut 'agy 9.9.9 (build 1.2.3)'
        try { (Invoke-Verify $f).StdOut | Should -BeNullOrEmpty -Because 'the live version is 9.9.9, so the cell is current; 1.2.3 must not be taken' }
        finally { Remove-Item $f.Root -Recurse -Force -ErrorAction SilentlyContinue }
        $g = New-VerifyFx -DotnetCell 'PASS 1.2.3' -AgyOut 'agy 9.9.9 (build 1.2.3)'
        try { (Invoke-Verify $g).StdOut | Should -Match '\(live 9\.9\.9\)' -Because 'a cell stamped with the SECOND token is stale' }
        finally { Remove-Item $g.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'EMITS NOROWS guidance when the table has no data rows' {
        $f = New-VerifyFx
        try {
            Set-Content -LiteralPath (Join-Path $f.Cwd 'agy-autotrain/verify/assertions.md') -Value '# empty'
            (Invoke-Verify $f).StdOut | Should -Match 'no probe rows could be read'
        } finally { Remove-Item $f.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'stays SILENT with no agy anywhere (not installed -> nothing to verify against)' {
        $f = New-VerifyFx
        try {
            Remove-Item (Join-Path $f.Root 'fakebin/agy')
            $r = Invoke-BashHook -HookPath $script:Hook -Payload ('{"cwd":"' + (($f.Cwd) -replace '\\', '\\') + '"}') -Env @{ PATH = ($script:GitUsr + ';' + $script:JqDir); LOCALAPPDATA = (Join-Path $f.Root 'lad') }
            $r.StdOut | Should -BeNullOrEmpty
            $r.StdErr | Should -BeNullOrEmpty
        } finally { Remove-Item $f.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'stays SILENT outside the clavity repo (no assertions.md under cwd)' {
        $f = New-VerifyFx
        try {
            Remove-Item (Join-Path $f.Cwd 'agy-autotrain') -Recurse -Force
            (Invoke-Verify $f).StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $f.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'resolves a cwd carrying a \u escape (a non-ASCII repo path) and still EMITS' {
        # The payload carries the e-acute as \u00e9; only jq decodes it, so a raw-only regex would resolve the wrong path
        # and the hook would go SILENT for such a repo. Control: the same stale cell, ASCII path, emits (row above).
        $e = [string][char]0xE9
        $f = New-VerifyFx -DotnetCell 'PASS 1.0.0' -DirName ("repo-$e")
        try {
            $json = (($f.Cwd) -replace '\\', '/').Replace($e, '\u00e9')
            $json | Should -Match '\\u00e9' -Because 'the fixture must carry a JSON \u escape, or this row exercises the raw arm and proves nothing'
            (Invoke-Verify $f -CwdJson $json).StdOut | Should -Match 'A1 \[dotnet\] PASS 1\.0\.0 \(live 9\.9\.9\)'
        } finally { Remove-Item $f.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

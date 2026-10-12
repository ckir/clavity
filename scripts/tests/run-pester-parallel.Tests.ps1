# run-pester-parallel.ps1 runs each suite file in its OWN pwsh process, N at a time, and must be at least as strict
# as one Invoke-Pester over the same files. The strictness rows are the point: a container that fails DISCOVERY
# contributes 0 to FailedCount (the CI sweep documents this), so a naive "sum the failures" runner turns a broken
# suite file into a green gate.
BeforeAll {
    . (Join-Path $PSScriptRoot 'TestTemp.ps1')
    $script:Runner = Join-Path (Split-Path -Parent $PSScriptRoot) 'run-pester-parallel.ps1'
    $script:Work = New-TestTempPath -Prefix 'rpp'
    New-Item -ItemType Directory -Path $script:Work -Force | Out-Null

    function New-Suite([string]$Name, [string]$Body) {
        $p = Join-Path $script:Work "$Name.Tests.ps1"
        Set-Content -LiteralPath $p -Value $Body
        $p
    }
    function Invoke-Runner {
        param([string[]]$ExtraArgs)
        $out = & pwsh -NoProfile -File $script:Runner @ExtraArgs 2>&1 | Out-String
        [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out }
    }

    $script:Pass1 = New-Suite 'pass-one' "Describe 'p1' { It 'a' { 1 | Should -Be 1 }; It 'b' { 2 | Should -Be 2 } }"
    $script:Pass2 = New-Suite 'pass-two' "Describe 'p2' { It 'c' { 3 | Should -Be 3 } }"
    $script:Fail1 = New-Suite 'fail-one' "Describe 'f1' { It 'this-row-fails' { 1 | Should -Be 2 } }"
    # Discovery failure: a syntax error BEFORE any It, so Pester reports the container as Failed with ZERO failed tests.
    $script:Broken = New-Suite 'broken' "Describe 'bad' { It 'x' { 1 | Should -Be 1 } "
}
AfterAll { Remove-TestPath $script:Work }

Describe 'run-pester-parallel' {
    It 'exits 0 and reports the summed totals when every file passes' {
        $r = Invoke-Runner -ExtraArgs @('-Files', "$script:Pass1,$script:Pass2", '-ThrottleLimit', '2')
        $r.Exit | Should -Be 0 -Because $r.Out
        $r.Out | Should -Match 'passed=3 failed=0'
    }

    It 'exits 1 and names the failing test when one file has a failing row' {
        $r = Invoke-Runner -ExtraArgs @('-Files', "$script:Pass1,$script:Fail1", '-ThrottleLimit', '2')
        $r.Exit | Should -Be 1 -Because $r.Out
        $r.Out | Should -Match 'this-row-fails'
        $r.Out | Should -Match 'passed=2 failed=1'
    }

    It 'exits 1 for a container that fails DISCOVERY even though it counts zero failed tests' {
        $r = Invoke-Runner -ExtraArgs @('-Files', "$script:Pass1,$script:Broken", '-ThrottleLimit', '2')
        $r.Exit | Should -Be 1 -Because $r.Out
        $r.Out | Should -Match 'broken\.Tests\.ps1'
    }

    It 'exits 1 for a file that does not exist rather than silently shrinking the gate' {
        $r = Invoke-Runner -ExtraArgs @('-Files', "$script:Pass1,$(Join-Path $script:Work 'nope.Tests.ps1')", '-ThrottleLimit', '2')
        $r.Exit | Should -Be 1 -Because $r.Out
        $r.Out | Should -Match 'nope\.Tests\.ps1'
    }

    It 'exits 1 when handed no files at all (an empty gate is not a green gate)' {
        $jf = Join-Path $script:Work 'empty-justfile'
        Set-Content -LiteralPath $jf -Value "test-x:`n    pwsh -c `"echo nothing`"`n"
        $r = Invoke-Runner -ExtraArgs @('-Recipe', 'test-x', '-Justfile', $jf)
        $r.Exit | Should -Be 1 -Because $r.Out
    }

    It 'does not change test semantics: a NON-terminating error inside a row must not fail it (plain Invoke-Pester agrees)' {
        # Measured 2026-10-12: agy-anomaly-reminder's ".git is a FILE" row runs `(Get-Item <missing>).PSIsContainer | Should -BeFalse`.
        # Under a plain Invoke-Pester the missing item is a non-terminating error and $null passes BeFalse. The runner set
        # $ErrorActionPreference = 'Stop' for its OWN logic and that leaked into the child's Pester run, turning the same row red -
        # a gate that is stricter than the one it replaces fails suites for a reason the real gate never would.
        $ne = New-Suite 'non-terminating' "Describe 'nt' { It 'tolerates a non-terminating error' { (Get-Item (Join-Path `$TestDrive 'missing')).PSIsContainer | Should -BeFalse } }"
        $plain = & pwsh -NoProfile -c "Import-Module Pester -MinimumVersion 6.0.0 -MaximumVersion 6.99.99 -Force; `$r = Invoke-Pester -Path '$ne' -Output None -PassThru; `$r.FailedCount" 2>&1 | Select-Object -Last 1
        [string]$plain | Should -Be '0' -Because 'the premise: plain Invoke-Pester passes this row'
        $r = Invoke-Runner -ExtraArgs @('-Files', $ne)
        $r.Exit | Should -Be 0 -Because $r.Out
    }

    Context 'recipe parsing (-ListOnly)' {
        It 'lists suites from the named recipe and ignores commented-out entries and the other recipes' {
            $jf = Join-Path $script:Work 'justfile'
            Set-Content -LiteralPath $jf -Value @"
test-x:
    pwsh -NoProfile -c "Invoke-Pester @('a/dir/one.Tests.ps1', 'a/dir/two.Tests.ps1') -CI" # trailing note about three.Tests.ps1
    # four.Tests.ps1 was retired
test-y:
    pwsh -c "Invoke-Pester @('a/dir/five.Tests.ps1')"
"@
            $r = Invoke-Runner -ExtraArgs @('-Recipe', 'test-x', '-Justfile', $jf, '-ListOnly')
            $r.Exit | Should -Be 0 -Because $r.Out
            $lines = @($r.Out -split "`r?`n" | Where-Object { $_ -match '\.Tests\.ps1$' })
            $lines | Should -Be @('a/dir/one.Tests.ps1', 'a/dir/two.Tests.ps1')
        }

        It 'parses the real test-scripts-fast recipe to files that all exist' {
            $r = Invoke-Runner -ExtraArgs @('-Recipe', 'test-scripts-fast', '-ListOnly')
            $r.Exit | Should -Be 0 -Because $r.Out
            $lines = @($r.Out -split "`r?`n" | Where-Object { $_ -match '\.Tests\.ps1$' })
            $lines.Count | Should -BeGreaterThan 5
            $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
            @($lines | Where-Object { -not (Test-Path -LiteralPath (Join-Path $repo $_)) }) | Should -BeNullOrEmpty
        }
    }
}

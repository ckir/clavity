<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

# Pester v5+. Pins scripts/lib/test-count-lib.ps1 (one extractor per test-runner summary format, plus the suite
# metadata) and scripts/emit-test-count.ps1 (extract one suite's counts, validate, append to $GITHUB_OUTPUT).
# The fixture lines are MEASURED runner output (2026-11-20), not invented; the runners' summary formats are the
# contract, so an extractor must THROW on anything it does not recognise rather than return a wrong number.
Describe 'test-count extractors' {
    BeforeAll {
        . ([IO.Path]::Combine($PSScriptRoot, 'TestTemp.ps1'))
        . ([IO.Path]::Combine($PSScriptRoot, '..', 'lib', 'test-count-lib.ps1'))
        $script:Emit = [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot, '..', 'emit-test-count.ps1'))
        $script:Made = [System.Collections.Generic.List[string]]::new()

        $script:DotnetLs  = 'Passed!  - Failed:     0, Passed:   851, Skipped:     0, Total:   851, Duration: 9 s - Clavity.Ls.Tests.dll (net10.0)'
        $script:DotnetInt = 'Passed!  - Failed:     0, Passed:   249, Skipped:     0, Total:   249, Duration: 23 s - Clavity.Integration.Tests.dll (net10.0)'
        $script:DotnetText = "build output`n$($script:DotnetLs)`nmore`n$($script:DotnetInt)`n"
        $script:CargoText = @(
            'test result: ok. 22 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 1.16s'
            'test result: ok. 101 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.08s'
            'test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s'
        ) -join "`n"
        $script:PesterText = "TOTAL files=3 excluded=0 passed=40 failed=0 skipped=1 badContainers=0 noResult=0 wall=3.1s throttle=4`nnoise`nTOTAL files=91 excluded=0 passed=2600 failed=0 skipped=11 badContainers=0 noResult=0 wall=300.1s throttle=4`n"
        $script:BashText = "`n15 passed, 0 failed`n"
        $script:TapText = "# tests 5`n# suites 0`n# pass 5`n# fail 0`n# cancelled 0`n# skipped 1`n# todo 1`n# duration_ms 12.3`n"
        $script:UnitText = "...`n----------------------------------------------------------------------`nRan 137 tests in 1.982s`n`nOK (skipped=7)`n"

        function Write-Junit([string]$Body) {
            $p = New-TestTempPath -Prefix 'tc-junit' -Suffix '.xml'
            $script:Made.Add($p)
            [IO.File]::WriteAllText($p, "<?xml version=`"1.0`" encoding=`"utf-8`"?><testsuites name=`"pytest tests`"><testsuite name=`"pytest`">$Body</testsuite></testsuites>")
            $p
        }
        function ConvertTo-Crlf([string]$Text) { $Text -replace "`n", "`r`n" }
        function Read-Out { (Get-Content -LiteralPath $script:OutFile -Raw) -replace "`r`n", "`n" }
    }
    AfterAll { Remove-TestPath @($script:Made) }

    It 'reads each .NET project from its own summary line' {
        (Get-DotnetProjectCounts $script:DotnetText 'Clavity.Ls.Tests').Passed | Should -Be 851
        (Get-DotnetProjectCounts $script:DotnetText 'Clavity.Integration.Tests').Passed | Should -Be 249
        (Get-DotnetProjectCounts $script:DotnetText 'Clavity.Ls.Tests').Skipped | Should -Be 0
    }
    It 'returns an int Passed and Skipped' {
        $r = Get-DotnetProjectCounts $script:DotnetText 'Clavity.Ls.Tests'
        $r.Passed | Should -BeOfType ([int])
        $r.Skipped | Should -BeOfType ([int])
    }
    It 'throws when a .NET project has no summary line' {
        { Get-DotnetProjectCounts $script:DotnetText 'Missing.Tests' } | Should -Throw '*dotnet*'
    }
    It 'throws on a Failed! .NET line' {
        $t = 'Failed!  - Failed:     1, Passed:   850, Skipped:     0, Total:   851, Duration: 9 s - Clavity.Ls.Tests.dll (net10.0)'
        { Get-DotnetProjectCounts $t 'Clavity.Ls.Tests' } | Should -Throw '*dotnet*'
    }
    It 'throws when a .NET project prints two summary lines, or passes nothing' {
        { Get-DotnetProjectCounts "$($script:DotnetLs)`n$($script:DotnetLs)" 'Clavity.Ls.Tests' } | Should -Throw '*dotnet*'
        $z = 'Passed!  - Failed:     0, Passed:     0, Skipped:     0, Total:     0, Duration: 9 s - Clavity.Ls.Tests.dll (net10.0)'
        { Get-DotnetProjectCounts $z 'Clavity.Ls.Tests' } | Should -Throw '*dotnet*'
    }

    It 'sums every cargo test result line, zero-test binaries included' {
        $r = Get-CargoCounts $script:CargoText
        $r.Passed | Should -Be 123
        $r.Skipped | Should -Be 0
        $colored = ($script:CargoText -split "`n" | ForEach-Object { "`e[32m$_`e[0m" }) -join "`n"
        $c = Get-CargoCounts $colored
        $c.Passed | Should -Be 123
        $c.Skipped | Should -Be 0
    }
    It 'sums the ignored cargo tests as skipped' {
        $r = Get-CargoCounts "test result: ok. 5 passed; 0 failed; 2 ignored; 0 measured; 0 filtered out; finished in 0.1s`ntest result: ok. 1 passed; 0 failed; 1 ignored; 0 measured; 0 filtered out; finished in 0.1s"
        $r.Passed | Should -Be 6
        $r.Skipped | Should -Be 3
    }
    It 'throws on a cargo FAILED line' {
        $t = "$($script:CargoText)`ntest result: FAILED. 3 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.1s"
        { Get-CargoCounts $t } | Should -Throw '*cargo*'
    }
    It 'throws when cargo prints no test result line' {
        { Get-CargoCounts "Compiling foo`nFinished" } | Should -Throw '*cargo*'
    }
    It 'throws when every cargo binary ran zero tests' {
        { Get-CargoCounts 'test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s' } | Should -Throw '*cargo*'
    }

    It 'counts pytest per listed module' {
        $xml = Write-Junit @(
            '<testcase classname="test_agy_bus" name="a"/>'
            '<testcase classname="test_agy_bus" name="b"><skipped message="s"/></testcase>'
            '<testcase classname="test_agy_tmux" name="c"/>'
            '<testcase classname="tests.test_mcp_wiring.TestWiring" name="d"/>'
            '<testcase classname="tests.test_secret_scrub" name="e"/>'
        ) -join ''
        $r = Get-PytestCounts $xml @('test_agy_bus', 'test_agy_tmux', 'tests.test_mcp_wiring', 'tests.test_secret_scrub')
        $r.Passed | Should -Be 4
        $r.Skipped | Should -Be 1
    }
    It 'throws when a listed pytest module collected nothing' {
        $xml = Write-Junit ('<testcase classname="test_agy_bus" name="a"/><testcase classname="test_agy_tmux" name="c"/><testcase classname="tests.test_mcp_wiring.TestWiring" name="d"/>')
        { Get-PytestCounts $xml @('test_agy_bus', 'test_agy_tmux', 'tests.test_mcp_wiring', 'tests.test_secret_scrub') } | Should -Throw '*pytest*'
    }
    It 'throws when a listed pytest module only skipped' {
        $xml = Write-Junit ('<testcase classname="test_agy_bus" name="a"><skipped/></testcase><testcase classname="test_agy_tmux" name="c"/>')
        { Get-PytestCounts $xml @('test_agy_bus', 'test_agy_tmux') } | Should -Throw '*pytest*'
    }
    It 'throws on a pytest failure or error case' {
        foreach ($child in '<failure message="x"/>', '<error message="x"/>') {
            $xml = Write-Junit ("<testcase classname=`"test_agy_bus`" name=`"a`"/><testcase classname=`"test_agy_bus`" name=`"b`">$child</testcase>")
            { Get-PytestCounts $xml @('test_agy_bus') } | Should -Throw '*pytest*'
        }
    }
    It 'throws when a pytest case belongs to no listed module' {
        $xml = Write-Junit ('<testcase classname="test_agy_bus" name="a"/><testcase classname="test_other" name="b"/>')
        { Get-PytestCounts $xml @('test_agy_bus') } | Should -Throw '*pytest*'
    }
    It 'throws when the pytest file is missing or not XML' {
        { Get-PytestCounts (New-TestTempPath -Prefix 'tc-missing') @('test_agy_bus') } | Should -Throw '*pytest*'
        $p = New-TestTempPath -Prefix 'tc-bad' -Suffix '.xml'
        $script:Made.Add($p)
        [IO.File]::WriteAllText($p, 'not xml at all')
        { Get-PytestCounts $p @('test_agy_bus') } | Should -Throw '*pytest*'
    }

    It 'reads the last Pester TOTAL line' {
        $r = Get-PesterRunnerCounts $script:PesterText
        $r.Passed | Should -Be 2600
        $r.Skipped | Should -Be 11
    }
    It 'throws when Pester reports failures' {
        { Get-PesterRunnerCounts 'TOTAL files=91 excluded=0 passed=2600 failed=1 skipped=11 badContainers=0 noResult=0 wall=300.1s throttle=4' } | Should -Throw '*pester*'
    }
    It 'throws when the Pester TOTAL line is absent or the passed count is zero' {
        { Get-PesterRunnerCounts "no totals here`n" } | Should -Throw '*pester*'
        { Get-PesterRunnerCounts 'TOTAL files=1 excluded=0 passed=0 failed=0 skipped=0 badContainers=0 noResult=0 wall=1s throttle=4' } | Should -Throw '*pester*'
    }

    It 'reads the bash tally' {
        $r = Get-BashHookCounts "`n15 passed, 0 failed"
        $r.Passed | Should -Be 15
        $r.Skipped | Should -Be 0
        { Get-BashHookCounts "14 passed, 1 failed" } | Should -Throw '*bash*'
        $s = Get-BashHookCounts "skip other driver's PARTIAL is silent - host has clavity (classic) on PATH, so dotnet-only cannot be isolated`n`n14 passed, 0 failed"
        $s.Passed | Should -Be 14
        $s.Skipped | Should -Be 1
    }
    It 'throws when the bash tally is absent or zero' {
        { Get-BashHookCounts "ok`n" } | Should -Throw '*bash*'
        { Get-BashHookCounts "0 passed, 0 failed" } | Should -Throw '*bash*'
    }

    It 'reads node TAP pass and skipped' {
        $r = Get-NodeTapCounts "# pass 5`n# skipped 1`n# todo 1`n# fail 0`n"
        $r.Passed | Should -Be 5
        $r.Skipped | Should -Be 2
        (Get-NodeTapCounts $script:TapText).Passed | Should -Be 5
    }
    It 'throws on node TAP failures, a missing summary, or zero passes' {
        { Get-NodeTapCounts "# pass 5`n# skipped 0`n# todo 0`n# fail 1`n" } | Should -Throw '*node*'
        { Get-NodeTapCounts "# pass 5`n# fail 0`n" } | Should -Throw '*node*'
        { Get-NodeTapCounts "ok 1 - x" } | Should -Throw '*node*'
        { Get-NodeTapCounts "# pass 0`n# skipped 0`n# todo 0`n# fail 0`n" } | Should -Throw '*node*'
    }

    It 'reads unittest OK with skips' {
        $r = Get-UnittestCounts "Ran 137 tests in 1.982s`n`nOK (skipped=7)"
        $r.Passed | Should -Be 130
        $r.Skipped | Should -Be 7
        $p = Get-UnittestCounts "Ran 137 tests in 1.982s`n`nOK"
        $p.Passed | Should -Be 137
        $p.Skipped | Should -Be 0
        { Get-UnittestCounts "Ran 137 tests in 1.982s`n`nFAILED (failures=1)" } | Should -Throw '*unittest*'
    }
    It 'counts unittest expected failures as skipped' {
        $r = Get-UnittestCounts "Ran 10 tests in 0.1s`n`nOK (skipped=2, expected failures=1)"
        $r.Passed | Should -Be 7
        $r.Skipped | Should -Be 3
    }
    It 'throws on a malformed unittest summary' {
        { Get-UnittestCounts "nothing here" } | Should -Throw '*unittest*'
        { Get-UnittestCounts "Ran 1 test in 0.1s`n`nOK (unexpected successes=1)" } | Should -Throw '*unittest*'
        { Get-UnittestCounts "Ran 2 tests in 0.1s`n`nOK (skipped=2)" } | Should -Throw '*unittest*'
    }

    It 'reads CRLF output the same as LF' {
        (Get-DotnetProjectCounts (ConvertTo-Crlf $script:DotnetText) 'Clavity.Ls.Tests').Passed | Should -Be 851
        (Get-DotnetProjectCounts (ConvertTo-Crlf $script:DotnetText) 'Clavity.Integration.Tests').Passed | Should -Be 249
        (Get-CargoCounts (ConvertTo-Crlf $script:CargoText)).Passed | Should -Be 123
        $p = Get-PesterRunnerCounts (ConvertTo-Crlf $script:PesterText)
        $p.Passed | Should -Be 2600
        $p.Skipped | Should -Be 11
        (Get-BashHookCounts (ConvertTo-Crlf $script:BashText)).Passed | Should -Be 15
        $n = Get-NodeTapCounts (ConvertTo-Crlf $script:TapText)
        $n.Passed | Should -Be 5
        $n.Skipped | Should -Be 2
        $u = Get-UnittestCounts (ConvertTo-Crlf $script:UnitText)
        $u.Passed | Should -Be 130
        $u.Skipped | Should -Be 7
    }
    It 'strips ANSI colour escapes' {
        Remove-AnsiEscape "`e[32mok`e[0m `e[1;31mred`e[0m" | Should -Be 'ok red'
    }

    It 'lists exactly the nine suite ids' {
        $expected = @('dotnet_ls', 'dotnet_integration', 'rust', 'python_bridge', 'pester_scripts', 'pester_install', 'bash_hooks', 'node_relay', 'site_checks')
        $script:TestCountSuiteIds | Should -Be $expected
        @((Get-TestCountSuiteMeta).Keys) | Should -Be $expected
    }
    It 'gives every suite its full metadata' {
        $m = Get-TestCountSuiteMeta
        foreach ($id in $m.Keys) {
            foreach ($f in 'Label', 'Workflow', 'Job', 'Lane', 'Conditions', 'Command') {
                $m[$id].$f | Should -Not -BeNullOrEmpty -Because "$id.$f is printed on the breakdown page"
            }
        }
        $m['rust'].Command | Should -Be 'cd clavity-classic; cargo test --all --features test-fakes'
        $m['site_checks'].Workflow | Should -Be 'test-count.yml'
        $m['pester_scripts'].Lane | Should -Be 'windows-latest'
    }

    Context 'emit-test-count' {
        BeforeEach {
            $script:SavedOut = $env:GITHUB_OUTPUT
            $script:OutFile = New-TestTempPath -Prefix 'tc-out'
            $script:Made.Add($script:OutFile)
            [IO.File]::WriteAllText($script:OutFile, '')   # Actions hands the step an existing, empty file
            $env:GITHUB_OUTPUT = $script:OutFile
        }
        AfterEach {
            if ($null -eq $script:SavedOut) { Remove-Item Env:GITHUB_OUTPUT -ErrorAction SilentlyContinue } else { $env:GITHUB_OUTPUT = $script:SavedOut }
        }
        It 'appends both outputs' {
            $f = New-TestTempPath -Prefix 'tc-bash'
            $script:Made.Add($f)
            [IO.File]::WriteAllText($f, $script:BashText)
            $printed = & $script:Emit -Suite bash_hooks -Path $f
            Read-Out | Should -Be "bash_hooks_passed=15`nbash_hooks_skipped=0`n"
            "$printed" | Should -Be 'test-count bash_hooks passed=15 skipped=0'
        }
        It 'appends to existing content instead of replacing it' {
            [IO.File]::WriteAllText($script:OutFile, "other=1`n")
            $f = New-TestTempPath -Prefix 'tc-bash'
            $script:Made.Add($f)
            [IO.File]::WriteAllText($f, $script:BashText)
            $null = & $script:Emit -Suite bash_hooks -Path $f
            Read-Out | Should -Be "other=1`nbash_hooks_passed=15`nbash_hooks_skipped=0`n"
        }
        It 'extracts each runner format through its suite id' {
            $cases = @(
                @{ Suite = 'dotnet_ls';          Text = $script:DotnetText; Want = 'dotnet_ls_passed=851' }
                @{ Suite = 'dotnet_integration'; Text = $script:DotnetText; Want = 'dotnet_integration_passed=249' }
                @{ Suite = 'rust';               Text = $script:CargoText;  Want = 'rust_passed=123' }
                @{ Suite = 'pester_scripts';     Text = $script:PesterText; Want = 'pester_scripts_passed=2600' }
                @{ Suite = 'node_relay';         Text = $script:TapText;    Want = 'node_relay_passed=5' }
                @{ Suite = 'site_checks';        Text = $script:UnitText;   Want = 'site_checks_passed=130' }
            )
            foreach ($c in $cases) {
                [IO.File]::WriteAllText($script:OutFile, '')
                $f = New-TestTempPath -Prefix 'tc-in'
                $script:Made.Add($f)
                [IO.File]::WriteAllText($f, $c.Text)
                $null = & $script:Emit -Suite $c.Suite -Path $f
                Read-Out | Should -BeLike "$($c.Want)`n*" -Because $c.Suite
            }
        }
        It 'extracts python_bridge from a junit file with the four named modules' {
            $xml = Write-Junit ('<testcase classname="test_agy_bus" name="a"/><testcase classname="test_agy_tmux" name="b"/><testcase classname="tests.test_mcp_wiring.TestX" name="c"/><testcase classname="tests.test_secret_scrub" name="d"/>')
            $null = & $script:Emit -Suite python_bridge -Path $xml
            Read-Out | Should -Be "python_bridge_passed=4`npython_bridge_skipped=0`n"
        }
        It 'rejects an unknown suite' {
            { & $script:Emit -Suite nonsense -Path $script:OutFile } | Should -Throw '*nonsense: unknown suite*'
        }
        It 'throws when GITHUB_OUTPUT is unset' {
            Remove-Item Env:GITHUB_OUTPUT
            $f = New-TestTempPath -Prefix 'tc-bash'
            $script:Made.Add($f)
            [IO.File]::WriteAllText($f, $script:BashText)
            { & $script:Emit -Suite bash_hooks -Path $f } | Should -Throw '*GITHUB_OUTPUT*'
        }
        It 'rejects passed=0 for pester_install' {
            { & $script:Emit -Suite pester_install -Passed 0 -Skipped 0 } | Should -Throw '*pester_install: passed 0*'
            Read-Out | Should -BeNullOrEmpty
        }
        It 'accepts pester_install with skipped 0' {
            $null = & $script:Emit -Suite pester_install -Passed 12 -Skipped 0
            Read-Out | Should -Be "pester_install_passed=12`npester_install_skipped=0`n"
        }
        It 'rejects out-of-range and missing pester_install arguments' {
            { & $script:Emit -Suite pester_install -Passed 1000001 -Skipped 0 } | Should -Throw '*pester_install: passed 1000001*'
            { & $script:Emit -Suite pester_install -Passed 5 -Skipped -1 } | Should -Throw '*pester_install: skipped -1*'
            { & $script:Emit -Suite pester_install -Passed 5 } | Should -Throw '*pester_install: needs both*'
            { & $script:Emit -Suite bash_hooks } | Should -Throw '*bash_hooks: needs -Path*'
        }
        It 'writes nothing when the extractor throws' {
            $f = New-TestTempPath -Prefix 'tc-bash'
            $script:Made.Add($f)
            [IO.File]::WriteAllText($f, "14 passed, 1 failed`n")
            { & $script:Emit -Suite bash_hooks -Path $f } | Should -Throw '*bash*'
            Read-Out | Should -BeNullOrEmpty
        }
    }
}

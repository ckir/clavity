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
    It 'reads the .NET skipped count from the Skipped: field' {
        $t = 'Passed!  - Failed:     0, Passed:   848, Skipped:     3, Total:   851, Duration: 9 s - Clavity.Ls.Tests.dll (net10.0)'
        $r = Get-DotnetProjectCounts $t 'Clavity.Ls.Tests'
        $r.Passed | Should -Be 848
        $r.Skipped | Should -Be 3
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
    It 'attributes a pytest case to the listed module its classname starts with, whatever the class is called' {
        # pytest collects unittest.TestCase subclasses whatever their name, so the class part need not start with Test.
        $xml = Write-Junit ('<testcase classname="test_agy_bus.PlainCase" name="a"/><testcase classname="tests.test_mcp_wiring.TestWiring.test_x" name="b"/>')
        $r = Get-PytestCounts $xml @('test_agy_bus', 'tests.test_mcp_wiring')
        $r.Passed | Should -Be 2
        # A module that merely shares a prefix, or a different module, is still no listed module.
        foreach ($cn in 'other_module.TestX', 'test_agy_bus_extra.TestX', 'test_agy') {
            $xml = Write-Junit ('<testcase classname="test_agy_bus" name="a"/>' + "<testcase classname=`"$cn`" name=`"b`"/>")
            { Get-PytestCounts $xml @('test_agy_bus') } | Should -Throw '*belongs to no listed module*' -Because $cn
        }
        # With nested module names the longest listed module takes the case.
        $xml = Write-Junit ('<testcase classname="tests" name="a"/><testcase classname="tests.sub.PlainCase" name="b"><skipped/></testcase><testcase classname="tests.sub" name="c"/>')
        $r = Get-PytestCounts $xml @('tests', 'tests.sub')
        $r.Passed | Should -Be 2
        $r.Skipped | Should -Be 1
    }
    It 'attributes a case to the longest listed module in either listing order' {
        # tests.sub.PlainCase can only land in tests.sub (its passing case is the only one there), and the skipped case must
        # be counted once, whichever module is listed first. A module that wins by order instead of length leaves tests.sub
        # with no passed test, which throws.
        $xml = Write-Junit ('<testcase classname="tests" name="a"/><testcase classname="tests.Other" name="b"/><testcase classname="tests.sub.PlainCase" name="c"/><testcase classname="tests.sub.PlainCase" name="d"><skipped/></testcase>')
        foreach ($order in @(, @('tests.sub', 'tests')), @(, @('tests', 'tests.sub'))) {
            $r = Get-PytestCounts $xml $order[0]
            $r.Passed | Should -Be 3 -Because "order $($order[0] -join ', ')"
            $r.Skipped | Should -Be 1 -Because "order $($order[0] -join ', ')"
        }
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
    It 'uses the LAST bash tally and the LAST unittest summary when a log holds two' {
        $b = Get-BashHookCounts "3 passed, 0 failed`nnoise`n15 passed, 0 failed"
        $b.Passed | Should -Be 15
        $u = Get-UnittestCounts "Ran 5 tests in 0.1s`n`nOK`nnoise`nRan 137 tests in 1.982s`n`nOK (skipped=7)"
        $u.Passed | Should -Be 130
        $u.Skipped | Should -Be 7
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
        It 'rejects -Passed/-Skipped for a suite that reads a file' {
            $f = New-TestTempPath -Prefix 'tc-bash'
            $script:Made.Add($f)
            [IO.File]::WriteAllText($f, $script:BashText)
            { & $script:Emit -Suite bash_hooks -Path $f -Passed 15 -Skipped 0 } | Should -Throw '*takes -Path, not -Passed/-Skipped*'
            { & $script:Emit -Suite rust -Passed 5 -Skipped 0 } | Should -Throw '*takes -Path, not -Passed/-Skipped*'
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

# The publish side: read nine count pairs from env, validate the ledger already on the badges branch, check ancestry
# against the main checkout, and write endpoint.json / ledger.json / README.md. Everything that reaches a file or a git
# argument is validated against a strict regex first; the ledger is data from a branch, not trusted input.
Describe 'test-count publish' {
    BeforeAll {
        . ([IO.Path]::Combine($PSScriptRoot, 'TestTemp.ps1'))
        . ([IO.Path]::Combine($PSScriptRoot, '..', 'lib', 'test-count-lib.ps1'))
        $script:Publish = [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot, '..', 'publish-test-count.ps1'))
        $script:Made = [System.Collections.Generic.List[string]]::new()
        # Sums to 4046, the figure the comma-separator test pins.
        $script:Base = [ordered]@{
            dotnet_ls = @(851, 0); dotnet_integration = @(249, 0); rust = @(123, 0); python_bridge = @(38, 0)
            pester_scripts = @(2623, 11); pester_install = @(12, 0); bash_hooks = @(15, 1); node_relay = @(5, 0); site_checks = @(130, 7)
        }
        $script:TcNames = foreach ($id in $script:TestCountSuiteIds) { "TC_$($id.ToUpperInvariant())_PASSED"; "TC_$($id.ToUpperInvariant())_SKIPPED" }

        function Set-TcEnv([hashtable]$Override = @{}) {
            foreach ($id in $script:TestCountSuiteIds) {
                $u = $id.ToUpperInvariant()
                $p = if ($Override.ContainsKey("TC_${u}_PASSED")) { $Override["TC_${u}_PASSED"] } else { [string]$script:Base[$id][0] }
                $s = if ($Override.ContainsKey("TC_${u}_SKIPPED")) { $Override["TC_${u}_SKIPPED"] } else { [string]$script:Base[$id][1] }
                [Environment]::SetEnvironmentVariable("TC_${u}_PASSED", $p)
                [Environment]::SetEnvironmentVariable("TC_${u}_SKIPPED", $s)
            }
        }
        function New-Counts {
            $c = [ordered]@{}
            foreach ($id in $script:TestCountSuiteIds) { $c[$id] = @{ Passed = [int]$script:Base[$id][0]; Skipped = [int]$script:Base[$id][1] } }
            $c
        }
        function New-Scratch([string]$Prefix) {
            $d = New-TestTempPath -Prefix $Prefix
            $script:Made.Add($d)
            $null = New-Item -ItemType Directory -Path $d
            $d
        }
        function Invoke-Git([string]$Dir, [string[]]$GitArgs) {
            $o = & git -C $Dir -c user.name=t -c user.email=t@t -c commit.gpgsign=false @GitArgs 2>&1
            if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $o" }
            $o
        }
        function Read-Out { (Get-Content -LiteralPath $script:OutFile -Raw) -replace "`r`n", "`n" }
        function Read-Text([string]$Path) { [IO.File]::ReadAllText($Path) }
        function Get-LedgerJson([string]$Commit, [string]$RunId = '777', [string]$Date = '2026-11-20') {
            (New-TestCountFiles (New-Counts) $Commit $RunId 'https://github.com/o/r/actions/runs/777' $Date 'o/r')['ledger.json']
        }
        function Invoke-Publish([string]$Commit, [string]$RunId = '777') {
            & $script:Publish -BadgesDir $script:Badges -MainDir $script:Main -Commit $Commit -RunId $RunId `
                -RunUrl "https://github.com/o/r/actions/runs/$RunId" -Date '2026-11-20' -Repo 'o/r'
        }
    }
    AfterAll { Remove-TestPath @($script:Made) }
    BeforeEach {
        $script:SavedEnv = @{}
        foreach ($n in @($script:TcNames) + 'GITHUB_OUTPUT') { $script:SavedEnv[$n] = [Environment]::GetEnvironmentVariable($n) }
        Set-TcEnv
        $script:OutFile = New-TestTempPath -Prefix 'tc-pub-out'
        $script:Made.Add($script:OutFile)
        [IO.File]::WriteAllText($script:OutFile, '')
        $env:GITHUB_OUTPUT = $script:OutFile
    }
    AfterEach {
        foreach ($n in $script:SavedEnv.Keys) { [Environment]::SetEnvironmentVariable($n, $script:SavedEnv[$n]) }
    }

    It 'reads all nine pairs from env' {
        $c = Read-TestCountEnv
        @($c.Keys) | Should -Be $script:TestCountSuiteIds
        $c['dotnet_ls'].Passed | Should -Be 851
        $c['dotnet_ls'].Passed | Should -BeOfType ([int])
        $c['site_checks'].Skipped | Should -Be 7
        $c['pester_install'].Skipped | Should -Be 0
    }
    It 'rejects a missing pair' {
        [Environment]::SetEnvironmentVariable('TC_NODE_RELAY_SKIPPED', $null)
        { Read-TestCountEnv } | Should -Throw '*TC_NODE_RELAY_SKIPPED*'
        Set-TcEnv
        [Environment]::SetEnvironmentVariable('TC_RUST_PASSED', '')
        { Read-TestCountEnv } | Should -Throw '*TC_RUST_PASSED*'
    }
    It 'rejects passed=0' {
        Set-TcEnv @{ TC_BASH_HOOKS_PASSED = '0' }
        { Read-TestCountEnv } | Should -Throw '*TC_BASH_HOOKS_PASSED*'
    }
    It 'accepts skipped=0 and the range ends, and rejects one past them' {
        Set-TcEnv @{ TC_RUST_PASSED = '1000000'; TC_RUST_SKIPPED = '1000000'; TC_BASH_HOOKS_PASSED = '1' }
        (Read-TestCountEnv)['rust'].Passed | Should -Be 1000000
        Set-TcEnv @{ TC_RUST_PASSED = '1000001' }
        { Read-TestCountEnv } | Should -Throw '*TC_RUST_PASSED*'
        Set-TcEnv @{ TC_RUST_SKIPPED = '1000001' }
        { Read-TestCountEnv } | Should -Throw '*TC_RUST_SKIPPED*'
    }
    It 'rejects a non-integer like 12;rm' {
        foreach ($bad in '12;rm', '1.5', '-3', '+3', ' 3', '3 ', "3`n", '1e3', '12345678', '0x10', '') {
            Set-TcEnv @{ TC_PYTHON_BRIDGE_PASSED = $bad }
            { Read-TestCountEnv } | Should -Throw '*TC_PYTHON_BRIDGE_PASSED*' -Because "value '$bad'"
        }
        Set-TcEnv @{ TC_PYTHON_BRIDGE_SKIPPED = '12;rm' }
        { Read-TestCountEnv } | Should -Throw '*TC_PYTHON_BRIDGE_SKIPPED*'
    }

    It 'formats the total with a comma separator' {
        $f = New-TestCountFiles (New-Counts) ('a' * 40) '777' 'https://github.com/o/r/actions/runs/777' '2026-11-20' 'o/r'
        $e = $f['endpoint.json'] | ConvertFrom-Json
        $e.message | Should -Be '4,046 passed'
        { Test-EndpointJson $f['endpoint.json'] } | Should -Not -Throw
        $f['endpoint.json'] | Should -Be '{"schemaVersion":1,"label":"tests","message":"4,046 passed","color":"brightgreen"}'
    }
    It 'returns exactly the three files with LF endings' {
        $f = New-TestCountFiles (New-Counts) ('a' * 40) '777' 'https://github.com/o/r/actions/runs/777' '2026-11-20' 'o/r'
        @($f.Keys) | Should -Be @('endpoint.json', 'ledger.json', 'README.md')
        foreach ($k in $f.Keys) { $f[$k] | Should -Not -Match "`r" -Because $k }
        $f['README.md'] | Should -Match "`n\z"
    }
    It 'writes the ledger in suite-id order and it validates' {
        $sha = 'b' * 40
        $l = (New-TestCountFiles (New-Counts) $sha '777' 'https://github.com/o/r/actions/runs/777' '2026-11-20' 'o/r')['ledger.json']
        $l | Should -Match '^\{"schema":1,"commit":"b{40}","run_id":"777","date":"2026-11-20","suites":\{"dotnet_ls":\{"passed":851,"skipped":0\},"dotnet_integration":'
        $p = Test-TestCountLedger $l
        $p.commit | Should -Be $sha
        $p.suites.pester_scripts.passed | Should -Be 2623
    }
    It 'renders the breakdown README with links, badge, table and the two sentences' {
        $sha = 'c' * 40
        $r = (New-TestCountFiles (New-Counts) $sha '777' 'https://github.com/o/r/actions/runs/777' '2026-11-20' 'o/r')['README.md']
        $r | Should -BeLike '*4,046*'
        $r | Should -Match ([regex]::Escape("for commit [``$sha``](https://github.com/o/r/commit/$sha) (2026-11-20)"))
        $r | Should -BeLike '*(https://github.com/o/r/actions/runs/777)*'
        $r | Should -BeLike '*https://github.com/o/r/actions/workflows/test-count.yml/badge.svg?branch=main*'
        foreach ($h in 'Label', 'Passed', 'Skipped', 'Lane', 'Conditions', 'Command') { $r | Should -BeLike "*| $h *" }
        foreach ($m in (Get-TestCountSuiteMeta).Values) { $r | Should -BeLike "*$($m.Label)*" }
        @([regex]::Matches($r, '(?m)^\| [^|]+ \| [0-9,]+ \| [0-9,]+ \|')).Count | Should -Be 9
        $r | Should -BeLike '*tests executed and passed at that one commit*skipped tests are not counted*'
        $r | Should -BeLike '*status badge is red*last commit where every suite passed*'
    }
    It 'escapes a pipe in a metadata cell so the breakdown table keeps six cells per row' {
        # The one seam: Get-TestCountSuiteMeta is resolved at call time, so a mock can put a pipe into a Conditions text.
        $real = Get-TestCountSuiteMeta
        $real['rust'].Conditions = 'a|b'
        $script:PipeMeta = $real
        Mock Get-TestCountSuiteMeta { $script:PipeMeta }
        $r = (New-TestCountFiles (New-Counts) ('c' * 40) '777' 'https://github.com/o/r/actions/runs/777' '2026-11-20' 'o/r')['README.md']
        $r | Should -BeLike '*a\|b*'
        $row = @($r -split "`n" | Where-Object { $_ -like '*a\|b*' })
        $row.Count | Should -Be 1
        # Six cells: split on a pipe that is not preceded by a backslash, ignoring the leading and trailing one.
        @([regex]::Split($row[0].Trim().Trim('|'), '(?<!\\)\|')).Count | Should -Be 6
    }
    It 'refuses inputs that would break the files or a git argument' {
        $u = 'https://github.com/o/r/actions/runs/777'
        { New-TestCountFiles (New-Counts) '--upload-pack=x' '777' $u '2026-11-20' 'o/r' } | Should -Throw '*commit*'
        { New-TestCountFiles (New-Counts) ('a' * 40) '7x' $u '2026-11-20' 'o/r' } | Should -Throw '*run id*'
        { New-TestCountFiles (New-Counts) ('a' * 40) '777' 'javascript:alert(1)' '2026-11-20' 'o/r' } | Should -Throw '*run url*'
        { New-TestCountFiles (New-Counts) ('a' * 40) '777' "$u)`n[x](y" '2026-11-20' 'o/r' } | Should -Throw '*run url*'
        { New-TestCountFiles (New-Counts) ('a' * 40) '777' $u '20261120' 'o/r' } | Should -Throw '*date*'
        { New-TestCountFiles (New-Counts) ('a' * 40) '777' $u '2026-11-20' 'o r' } | Should -Throw '*repo*'
        { New-TestCountFiles (New-Counts) ('a' * 40) '777' $u '2026-11-20' 'o/r/../x' } | Should -Throw '*repo*'
        $c = New-Counts; $c['rust'].Passed = 0
        { New-TestCountFiles $c ('a' * 40) '777' $u '2026-11-20' 'o/r' } | Should -Throw '*rust*'
        $c = New-Counts; $c.Remove('rust')
        { New-TestCountFiles $c ('a' * 40) '777' $u '2026-11-20' 'o/r' } | Should -Throw '*rust*'
    }

    It 'accepts a well-formed endpoint and rejects a malformed one' {
        { Test-EndpointJson '{"schemaVersion":1,"label":"tests","message":"1 passed","color":"brightgreen"}' } | Should -Not -Throw
        foreach ($bad in '{"schemaVersion":"1","label":"tests","message":"1 passed","color":"brightgreen"}',
                         '{"schemaVersion":2,"label":"tests","message":"1 passed","color":"brightgreen"}',
                         '{"schemaVersion":1,"label":"tests","message":1,"color":"brightgreen"}',
                         '{"schemaVersion":1,"label":"tests","message":"1 passed"}',
                         '{"schemaVersion":1,"label":"tests","message":"1 passed","color":"red","extra":"x"}',
                         '[1]', 'null', 'not json') {
            { Test-EndpointJson $bad } | Should -Throw -Because $bad
        }
    }

    It 'rejects an endpoint whose label or color is not a string, as well as message' {
        foreach ($k in 'label', 'message', 'color') {
            $e = [ordered]@{ schemaVersion = 1; label = 'tests'; message = '1 passed'; color = 'brightgreen' }
            $e[$k] = 5
            { Test-EndpointJson ($e | ConvertTo-Json -Compress) } | Should -Throw "*'$k' must be a string*"
        }
    }
    It 'rejects a ledger whose commit is not 40 hex' {
        foreach ($bad in '--upload-pack=x', ('A' * 40), ('a' * 39), ('a' * 41), "$('a' * 40)`n") {
            $j = (Get-LedgerJson ('a' * 40)) -replace ('a' * 40), ($bad -replace "`n", '\n')
            { Test-TestCountLedger $j } | Should -Throw '*commit*' -Because "commit '$bad'"
        }
    }
    It 'rejects a ledger with an unknown suite' {
        $good = Get-LedgerJson ('a' * 40)
        # A tenth key next to all nine real suites: only the "unknown suite" throw can fire, not "missing suite".
        $tenth = $good -replace '"suites":\{', '"suites":{"bogus":{"passed":1,"skipped":0},'
        $tenth | Should -Not -Be $good -Because 'the substitution must have added the tenth key'
        { Test-TestCountLedger $tenth } | Should -Throw "*unknown suite 'bogus'*"
        # A renamed suite leaves one real suite missing and one unknown: the unknown check runs first.
        $renamed = $good -replace '"site_checks"', '"bogus"'
        { Test-TestCountLedger $renamed } | Should -Throw "*unknown suite 'bogus'*"
    }
    It 'rejects a ledger that is missing a suite, or has a bad count, schema, run id, date or shape' {
        $good = Get-LedgerJson ('a' * 40)
        { Test-TestCountLedger $good } | Should -Not -Throw
        { Test-TestCountLedger ($good -replace '"run_id":"777"', '"run_id":777') } | Should -Not -Throw -Because 'the spec says the run id is an integer'
        $cases = @(
            @{ Why = 'missing suite'; Json = ($good -replace ',"site_checks":\{"passed":130,"skipped":7\}', '') }
            @{ Why = 'passed 0'; Json = ($good -replace '"rust":\{"passed":123', '"rust":{"passed":0') }
            @{ Why = 'passed over range'; Json = ($good -replace '"rust":\{"passed":123', '"rust":{"passed":1000001') }
            @{ Why = 'negative skipped'; Json = ($good -replace '"skipped":11', '"skipped":-1') }
            @{ Why = 'float passed'; Json = ($good -replace '"rust":\{"passed":123', '"rust":{"passed":1.5') }
            @{ Why = 'string passed'; Json = ($good -replace '"rust":\{"passed":123', '"rust":{"passed":"123"') }
            @{ Why = 'schema 2'; Json = ($good -replace '"schema":1', '"schema":2') }
            @{ Why = 'run id not digits'; Json = ($good -replace '"run_id":"777"', '"run_id":"7x7"') }
            @{ Why = 'run id negative'; Json = ($good -replace '"run_id":"777"', '"run_id":-7') }
            @{ Why = 'run id float'; Json = ($good -replace '"run_id":"777"', '"run_id":7.5') }
            @{ Why = 'date shape'; Json = ($good -replace '"2026-11-20"', '"20-11-2026"') }
            @{ Why = 'not json'; Json = 'garbage' }
            @{ Why = 'empty'; Json = '' }
            @{ Why = 'json null'; Json = 'null' }
            @{ Why = 'json array'; Json = '[]' }
            @{ Why = 'no suites'; Json = '{"schema":1,"commit":"' + ('a' * 40) + '","run_id":"1","date":"2026-11-20"}' }
        )
        foreach ($c in $cases) { { Test-TestCountLedger $c.Json } | Should -Throw -Because $c.Why }
    }

    Context 'publish-test-count' {
        BeforeEach {
            $script:Main = New-Scratch 'tc-main'
            $script:Badges = New-Scratch 'tc-badges'
            $null = & git init -q $script:Main 2>&1
            $null = Invoke-Git $script:Main @('commit', '-q', '--allow-empty', '-m', 'x')
            $script:A = (Invoke-Git $script:Main @('rev-parse', 'HEAD') | Select-Object -First 1).ToString().Trim()
            $null = Invoke-Git $script:Main @('commit', '-q', '--allow-empty', '-m', 'x')
            $script:B = (Invoke-Git $script:Main @('rev-parse', 'HEAD') | Select-Object -First 1).ToString().Trim()
        }
        It 'publishes over an empty badges dir' {
            Invoke-Publish $script:A | Out-Null
            Test-Path (Join-Path $script:Badges 'endpoint.json') | Should -BeTrue
            Test-Path (Join-Path $script:Badges 'README.md') | Should -BeTrue
            (Test-TestCountLedger (Read-Text (Join-Path $script:Badges 'ledger.json'))).commit | Should -Be $script:A
            (Read-Text (Join-Path $script:Badges 'endpoint.json')) | Should -Be '{"schemaVersion":1,"label":"tests","message":"4,046 passed","color":"brightgreen"}'
            Read-Out | Should -Be "changed=true`n"
        }
        It 'treats a badges dir holding only .git as empty' {
            $null = New-Item -ItemType Directory -Path (Join-Path $script:Badges '.git')
            Invoke-Publish $script:A | Out-Null
            Read-Out | Should -Be "changed=true`n"
        }
        It 'creates a missing badges dir' {
            $script:Badges = Join-Path $script:Badges 'sub'
            Invoke-Publish $script:A | Out-Null
            Test-Path (Join-Path $script:Badges 'ledger.json') | Should -BeTrue
        }
        It 'publishes a descendant' {
            [IO.File]::WriteAllText((Join-Path $script:Badges 'ledger.json'), (Get-LedgerJson $script:A))
            Invoke-Publish $script:B | Out-Null
            (Test-TestCountLedger (Read-Text (Join-Path $script:Badges 'ledger.json'))).commit | Should -Be $script:B
            Read-Out | Should -Be "changed=true`n"
        }
        It 'accepts the same commit and reports changed=false when nothing differs' {
            Invoke-Publish $script:B | Out-Null
            [IO.File]::WriteAllText($script:OutFile, '')
            Invoke-Publish $script:B | Out-Null
            Read-Out | Should -Be "changed=false`n"
        }
        It 'reports changed=true when the same commit has different counts' {
            Invoke-Publish $script:B | Out-Null
            [IO.File]::WriteAllText($script:OutFile, '')
            Set-TcEnv @{ TC_RUST_PASSED = '124' }
            Invoke-Publish $script:B | Out-Null
            Read-Out | Should -Be "changed=true`n"
            (Read-Text (Join-Path $script:Badges 'endpoint.json')) | Should -BeLike '*4,047 passed*'
        }
        It 'refuses an ancestor' {
            Invoke-Publish $script:B | Out-Null
            [IO.File]::WriteAllText($script:OutFile, '')
            $before = Read-Text (Join-Path $script:Badges 'ledger.json')
            { Invoke-Publish $script:A } | Should -Throw "*refusing to publish $($script:A): not a descendant of $($script:B)"
            Read-Text (Join-Path $script:Badges 'ledger.json') | Should -Be $before
            Read-Out | Should -BeNullOrEmpty
        }
        It 'refuses a commit the main checkout does not know' {
            [IO.File]::WriteAllText((Join-Path $script:Badges 'ledger.json'), (Get-LedgerJson ('1' * 40)))
            { Invoke-Publish $script:B } | Should -Throw '*refusing to publish*not a descendant of*'
        }
        It 'refuses when the existing ledger is corrupt and leaves it untouched' {
            $p = Join-Path $script:Badges 'ledger.json'
            [IO.File]::WriteAllText($p, '{"schema":1,"commit":"--upload-pack=x"}')
            $before = Read-Text $p
            { Invoke-Publish $script:B } | Should -Throw '*ledger*'
            Read-Text $p | Should -Be $before
            Test-Path (Join-Path $script:Badges 'endpoint.json') | Should -BeFalse
            Test-Path (Join-Path $script:Badges 'README.md') | Should -BeFalse
            Read-Out | Should -BeNullOrEmpty
        }
        It 'refuses a non-empty badges dir with no ledger' {
            [IO.File]::WriteAllText((Join-Path $script:Badges 'stray.txt'), 'x')
            { Invoke-Publish $script:B } | Should -Throw '*ledger*'
            Test-Path (Join-Path $script:Badges 'endpoint.json') | Should -BeFalse
        }
        It 'writes nothing when an env pair is invalid' {
            Set-TcEnv @{ TC_RUST_PASSED = '12;rm' }
            { Invoke-Publish $script:A } | Should -Throw '*TC_RUST_PASSED*'
            @(Get-ChildItem -LiteralPath $script:Badges -Force).Count | Should -Be 0
            Read-Out | Should -BeNullOrEmpty
        }
        It 'rejects a malformed -Commit before touching git or the files' {
            { Invoke-Publish '--upload-pack=x' } | Should -Throw '*commit*'
            @(Get-ChildItem -LiteralPath $script:Badges -Force).Count | Should -Be 0
        }
        It 'throws when GITHUB_OUTPUT is unset' {
            Remove-Item Env:GITHUB_OUTPUT
            { Invoke-Publish $script:A } | Should -Throw '*GITHUB_OUTPUT*'
            @(Get-ChildItem -LiteralPath $script:Badges -Force).Count | Should -Be 0
        }
        It 'writes files without a BOM or CR' {
            Invoke-Publish $script:A | Out-Null
            foreach ($n in 'endpoint.json', 'ledger.json', 'README.md') {
                $b = [IO.File]::ReadAllBytes((Join-Path $script:Badges $n))
                ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) | Should -BeFalse -Because $n
                $b -contains 13 | Should -BeFalse -Because $n
            }
        }
    }
}

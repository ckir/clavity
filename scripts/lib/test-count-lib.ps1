<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

# Pure helpers for the README "tests" badge: the suite metadata and one extractor per test runner's summary format.
# Each extractor returns [pscustomobject]@{ Passed = [int]; Skipped = [int] } and THROWS "test-count: <id>: <reason>"
# when the expected summary is absent, a failure count is non-zero, or nothing passed. A runner whose summary format
# changes (a new .NET, Pester or Node version) must therefore turn the badge step red, never publish a wrong number.
# No I/O beyond reading a path the caller names. Dot-sourced by emit-test-count.ps1 and by the publish script.

Set-StrictMode -Version Latest

# The nine suites, in badge order. They become output names (<id>_passed, <id>_skipped), hence the underscores.
$script:TestCountSuiteIds = [string[]]@(
    'dotnet_ls', 'dotnet_integration', 'rust', 'python_bridge', 'pester_scripts',
    'pester_install', 'bash_hooks', 'node_relay', 'site_checks'
)

function Get-TestCountSuiteMeta {
    # What the breakdown page prints for each suite: where it runs and the command that produces its count.
    $rows = @(
        @('dotnet_ls', '.NET Clavity.Ls.Tests', 'ci-dotnet.yml', 'test', 'windows-latest', '-',
          'cd clavity-dotnet; dotnet test tests/Clavity.Ls.Tests'),
        @('dotnet_integration', '.NET Clavity.Integration.Tests', 'ci-dotnet.yml', 'test', 'windows-latest', '-',
          'cd clavity-dotnet; dotnet test tests/Clavity.Integration.Tests'),
        @('rust', 'Rust (cargo)', 'ci-classic.yml', 'check', 'ubuntu-latest', '-',
          'cd clavity-classic; cargo test --all --features test-fakes'),
        @('python_bridge', 'Python bridge (pytest)', 'ci-classic.yml', 'check', 'ubuntu-latest', '-',
          'cd clavity-classic; uv run --project agy-mcp-bridge --frozen pytest agy-mcp-bridge/test_agy_bus.py agy-mcp-bridge/test_agy_tmux.py agy-mcp-bridge/tests/test_mcp_wiring.py agy-mcp-bridge/tests/test_secret_scrub.py'),
        @('pester_scripts', 'Pester scripts/tests', 'ci-scripts.yml', 'dev-scripts', 'windows-latest',
          'elevated Windows account (NotAsRoot rows skip); ripgrep, lefthook, yq, ast-grep, jq, Pester 6 installed',
          'pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory scripts/tests/_skip-inventory.md -MinTests 100 -RequireSuite test-suite-registration'),
        @('pester_install', 'Pester clavity-install', 'ci-scripts.yml', 'dev-scripts', 'windows-latest', 'Pester 6',
          'Invoke-Pester clavity-dotnet/install/clavity-install.Tests.ps1'),
        @('bash_hooks', 'Bash verify-gate fixtures', 'ci-scripts.yml', 'dev-scripts', 'windows-latest',
          'Git Bash; a host with clavity (classic) on PATH skips one case',
          'bash agy-autotrain/verify/testdata/run-hook-tests.sh'),
        @('node_relay', 'Node review-relay extension', 'ci-scripts.yml', 'review-relay-extension', 'windows-latest', 'Node 22',
          'cd review-relay/extension/test; npm ci; npm test'),
        @('site_checks', 'Site checks (unittest)', 'test-count.yml', 'site-checks', 'ubuntu-latest',
          'stdlib only, no PyYAML (WorkflowShape tests skip)',
          'python3 -m unittest discover -s .github/site-checks')
    )
    $meta = [ordered]@{}
    foreach ($r in $rows) {
        $meta[$r[0]] = [pscustomobject]@{
            Label = $r[1]; Workflow = $r[2]; Job = $r[3]; Lane = $r[4]; Conditions = $r[5]; Command = $r[6]
        }
    }
    $meta
}

function Remove-AnsiEscape {
    param([string]$Text)
    $Text -replace '\x1b\[[0-9;]*m', ''
}

function ConvertTo-LfText {
    # Windows lanes write CRLF through Tee-Object / Set-Content; the (?m) regexes below anchor on \n only.
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $Text -replace "`r`n", "`n"
}

function New-TestCountResult {
    param([Parameter(Mandatory)][int]$Passed, [Parameter(Mandatory)][int]$Skipped)
    [pscustomobject]@{ Passed = [int]$Passed; Skipped = [int]$Skipped }
}

function Get-DotnetProjectCounts {
    param([string]$Text, [Parameter(Mandatory)][string]$Project)
    $t = ConvertTo-LfText $Text
    $name = [regex]::Escape($Project)
    $rx = "(?m)^(Passed|Failed)!\s+-\s+Failed:\s+(\d+),\s+Passed:\s+(\d+),\s+Skipped:\s+(\d+),\s+Total:\s+\d+,[^\n]*?-\s+$name\.dll\b"
    $m = [regex]::Matches($t, $rx)
    if ($m.Count -eq 0) { throw "test-count: dotnet: no summary line for $Project" }
    if ($m.Count -gt 1) { throw "test-count: dotnet: $($m.Count) summary lines for $Project, expected exactly one" }
    $g = $m[0].Groups
    if ($g[1].Value -ne 'Passed' -or [int]$g[2].Value -ne 0) { throw "test-count: dotnet: $Project reports $($g[2].Value) failed" }
    if ([int]$g[3].Value -eq 0) { throw "test-count: dotnet: $Project passed 0 tests" }
    New-TestCountResult -Passed ([int]$g[3].Value) -Skipped ([int]$g[4].Value)
}

function Get-CargoCounts {
    param([string]$Text)
    $t = ConvertTo-LfText (Remove-AnsiEscape $Text)
    if ([regex]::IsMatch($t, 'test result: FAILED')) { throw 'test-count: cargo: a test result line is FAILED' }
    $m = [regex]::Matches($t, '(?m)test result: ok\. (\d+) passed; (\d+) failed; (\d+) ignored')
    if ($m.Count -eq 0) { throw 'test-count: cargo: no test result line' }
    $passed = 0; $skipped = 0
    foreach ($x in $m) {
        if ([int]$x.Groups[2].Value -ne 0) { throw "test-count: cargo: a test result line reports $($x.Groups[2].Value) failed" }
        $passed += [int]$x.Groups[1].Value
        $skipped += [int]$x.Groups[3].Value
    }
    # The zero floor is on the SUM: a zero-test binary (a crate with only doc-less lib targets) legitimately prints 0 passed.
    if ($passed -eq 0) { throw 'test-count: cargo: no tests passed in any binary' }
    New-TestCountResult -Passed $passed -Skipped $skipped
}

function Get-PytestCounts {
    param([Parameter(Mandatory)][string]$XmlPath, [Parameter(Mandatory)][string[]]$Modules)
    if (-not (Test-Path -LiteralPath $XmlPath -PathType Leaf)) { throw "test-count: pytest: junit file not found: $XmlPath" }
    $doc = [System.Xml.XmlDocument]::new()
    $doc.XmlResolver = $null
    try { $doc.Load($XmlPath) } catch { throw "test-count: pytest: cannot parse $XmlPath ($($_.Exception.Message))" }
    $passedBy = @{}
    foreach ($mod in $Modules) { $passedBy[$mod] = 0 }
    $skipped = 0; $failed = 0
    foreach ($case in @($doc.SelectNodes('//testcase'))) {
        $cn = $case.GetAttribute('classname')
        $mod = $null
        if ($passedBy.ContainsKey($cn)) { $mod = $cn }
        else {
            $i = $cn.IndexOf('.Test', [StringComparison]::Ordinal)
            if ($i -gt 0 -and $passedBy.ContainsKey($cn.Substring(0, $i))) { $mod = $cn.Substring(0, $i) }
        }
        if ($null -eq $mod) { throw "test-count: pytest: case '$($case.GetAttribute('name'))' (classname '$cn') belongs to no listed module" }
        if ($case.SelectSingleNode('failure') -or $case.SelectSingleNode('error')) { $failed++ }
        elseif ($case.SelectSingleNode('skipped')) { $skipped++ }
        else { $passedBy[$mod] = $passedBy[$mod] + 1 }
    }
    if ($failed -gt 0) { throw "test-count: pytest: $failed failed or errored case(s)" }
    $passed = 0
    foreach ($mod in $Modules) {
        if ($passedBy[$mod] -eq 0) { throw "test-count: pytest: module $mod has no passed test (collected nothing or only skipped)" }
        $passed += $passedBy[$mod]
    }
    New-TestCountResult -Passed $passed -Skipped $skipped
}

function Get-PesterRunnerCounts {
    param([string]$Text)
    $t = ConvertTo-LfText $Text
    $m = [regex]::Matches($t, '(?m)^TOTAL\b[^\n]*?\bpassed=(\d+)\s+failed=(\d+)\s+skipped=(\d+)')
    if ($m.Count -eq 0) { throw 'test-count: pester: no TOTAL line' }
    $g = $m[$m.Count - 1].Groups
    if ([int]$g[2].Value -ne 0) { throw "test-count: pester: TOTAL reports $($g[2].Value) failed" }
    if ([int]$g[1].Value -eq 0) { throw 'test-count: pester: TOTAL reports 0 passed' }
    New-TestCountResult -Passed ([int]$g[1].Value) -Skipped ([int]$g[3].Value)
}

function Get-BashHookCounts {
    param([string]$Text)
    $t = ConvertTo-LfText $Text
    $m = [regex]::Matches($t, '(?m)^(\d+) passed, (\d+) failed$')
    if ($m.Count -eq 0) { throw 'test-count: bash: no "N passed, N failed" tally' }
    $g = $m[$m.Count - 1].Groups
    if ([int]$g[2].Value -ne 0) { throw "test-count: bash: tally reports $($g[2].Value) failed" }
    if ([int]$g[1].Value -eq 0) { throw 'test-count: bash: tally reports 0 passed' }
    # run-hook-tests.sh prints one "skip ..." line per skipped case and does not count it as passed.
    $skips = [regex]::Matches($t, '(?m)^skip ').Count
    New-TestCountResult -Passed ([int]$g[1].Value) -Skipped $skips
}

function Get-NodeTapCounts {
    param([string]$Text)
    $t = ConvertTo-LfText $Text
    $v = @{}
    foreach ($k in 'pass', 'fail', 'skipped', 'todo') {
        $m = [regex]::Matches($t, "(?m)^# $k (\d+)\s*$")
        if ($m.Count -eq 0) { throw "test-count: node: no '# $k' summary line" }
        $v[$k] = [int]$m[$m.Count - 1].Groups[1].Value
    }
    if ($v['fail'] -ne 0) { throw "test-count: node: $($v['fail']) failed" }
    if ($v['pass'] -eq 0) { throw 'test-count: node: 0 passed' }
    New-TestCountResult -Passed $v['pass'] -Skipped ($v['skipped'] + $v['todo'])
}

function Get-UnittestCounts {
    param([string]$Text)
    $t = ConvertTo-LfText $Text
    if ([regex]::IsMatch($t, '(?m)^FAILED\b')) { throw 'test-count: unittest: run is FAILED' }
    $m = [regex]::Matches($t, '(?m)^Ran (\d+) tests? in [^\n]*\n\nOK(?: \(([^)\n]*)\))?[ \t]*$')
    if ($m.Count -eq 0) { throw 'test-count: unittest: no "Ran N tests" followed by OK' }
    $g = $m[$m.Count - 1].Groups
    $ran = [int]$g[1].Value
    $skipped = 0
    if ($g[2].Success) {
        foreach ($part in ($g[2].Value -split ',\s*')) {
            if ($part -match '^(skipped|expected failures)=(\d+)$') { $skipped += [int]$Matches[2] }
            else { throw "test-count: unittest: unrecognised OK detail '$part'" }
        }
    }
    if ($ran - $skipped -le 0) { throw "test-count: unittest: ran $ran, skipped $skipped, nothing passed" }
    New-TestCountResult -Passed ($ran - $skipped) -Skipped $skipped
}

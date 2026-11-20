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
          'ubuntu-latest system python3, which ships PyYAML, so the WorkflowShape tests run; without PyYAML 13 of them skip and the count is 124',
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
        # The classname is the module itself or <module>.<anything>: pytest also collects unittest.TestCase subclasses
        # whatever their name, so the class part cannot be required to start with Test. Longest listed module wins.
        foreach ($cand in $Modules) {
            if ($cn -ceq $cand -or $cn.StartsWith($cand + '.', [StringComparison]::Ordinal)) {
                if ($null -eq $mod -or $cand.Length -gt $mod.Length) { $mod = $cand }
            }
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

# ---- publish side: validation of everything that reaches a file or a git argument, and rendering of the badges files ----

function Test-TestCountInt {
    # True for a JSON/PowerShell integer in [Min, Max]. A double (1.5, 1e3), a string or a bool is not an integer here.
    param($Value, [long]$Min, [long]$Max)
    ($Value -is [int] -or $Value -is [long]) -and [long]$Value -ge $Min -and [long]$Value -le $Max
}

function Read-TestCountEnv {
    # TC_<ID>_PASSED / TC_<ID>_SKIPPED for every suite (id upper-cased). The workflow maps each emitter job output into
    # these, so the values are data from another job: strict regex first, range second, nothing is ever interpolated.
    $out = [ordered]@{}
    foreach ($id in $script:TestCountSuiteIds) {
        $vals = @{}
        foreach ($field in 'PASSED', 'SKIPPED') {
            $name = "TC_$($id.ToUpperInvariant())_$field"
            $raw = [Environment]::GetEnvironmentVariable($name)
            # \z, not $: .NET's $ also matches before a trailing newline.
            if ($null -eq $raw -or -not [regex]::IsMatch($raw, '\A[0-9]{1,7}\z')) {
                throw "test-count: ${name} must be 1-7 digits (an unset or malformed value)"
            }
            $vals[$field] = [int]$raw
        }
        if ($vals['PASSED'] -lt 1 -or $vals['PASSED'] -gt 1000000) { throw "test-count: TC_$($id.ToUpperInvariant())_PASSED $($vals['PASSED']) is outside 1..1000000" }
        if ($vals['SKIPPED'] -gt 1000000) { throw "test-count: TC_$($id.ToUpperInvariant())_SKIPPED $($vals['SKIPPED']) is outside 0..1000000" }
        $out[$id] = @{ Passed = $vals['PASSED']; Skipped = $vals['SKIPPED'] }
    }
    $out
}

function Test-TestCountLedger {
    # The ledger is read back from the badges branch and its commit goes to git as an argument, so it is untrusted data:
    # every field is checked and the function throws on the first violation (the caller then writes nothing).
    param([string]$Json)
    if ([string]::IsNullOrWhiteSpace($Json)) { throw 'test-count: ledger: empty' }
    try { $l = $Json | ConvertFrom-Json -ErrorAction Stop } catch { throw "test-count: ledger: not valid JSON ($($_.Exception.Message))" }
    if ($l -isnot [pscustomobject]) { throw 'test-count: ledger: not a JSON object' }
    $has = { param($o, $n) $null -ne ($o.PSObject.Properties | Where-Object { $_.Name -ceq $n }) }
    foreach ($k in 'schema', 'commit', 'run_id', 'date', 'suites') {
        if (-not (& $has $l $k)) { throw "test-count: ledger: missing '$k'" }
    }
    if (-not (Test-TestCountInt $l.schema 1 1)) { throw 'test-count: ledger: schema must be 1' }
    if ($l.commit -isnot [string] -or -not [regex]::IsMatch($l.commit, '\A[0-9a-f]{40}\z')) { throw 'test-count: ledger: commit is not 40 lowercase hex' }
    # The spec says "the run id an integer": this script writes it as a digit string, a hand-fixed ledger may hold a JSON integer.
    $runIdOk = ($l.run_id -is [string] -and [regex]::IsMatch($l.run_id, '\A[0-9]{1,20}\z')) -or (Test-TestCountInt $l.run_id 0 ([long]::MaxValue))
    if (-not $runIdOk) { throw 'test-count: ledger: run_id is not an integer (1-20 digits)' }
    if ($l.date -isnot [string] -or -not [regex]::IsMatch($l.date, '\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z')) { throw 'test-count: ledger: date is not yyyy-MM-dd' }
    if ($l.suites -isnot [pscustomobject]) { throw 'test-count: ledger: suites is not an object' }
    $names = @($l.suites.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($n in $names) {
        if ($n -cnotin $script:TestCountSuiteIds) { throw "test-count: ledger: unknown suite '$n'" }
    }
    foreach ($id in $script:TestCountSuiteIds) {
        if ($id -cnotin $names) { throw "test-count: ledger: missing suite '$id'" }
        $s = $l.suites.$id
        if ($s -isnot [pscustomobject]) { throw "test-count: ledger: suite '$id' is not an object" }
        $keys = @($s.PSObject.Properties | ForEach-Object { $_.Name })
        if ($keys.Count -ne 2 -or 'passed' -cnotin $keys -or 'skipped' -cnotin $keys) { throw "test-count: ledger: suite '$id' must hold exactly passed and skipped" }
        if (-not (Test-TestCountInt $s.passed 1 1000000)) { throw "test-count: ledger: suite '$id' passed is not an integer in 1..1000000" }
        if (-not (Test-TestCountInt $s.skipped 0 1000000)) { throw "test-count: ledger: suite '$id' skipped is not an integer in 0..1000000" }
    }
    $l
}

function Test-EndpointJson {
    # What shields.io's endpoint badge accepts from us: exactly these four keys, schemaVersion 1, the rest strings.
    param([string]$Json)
    try { $e = $Json | ConvertFrom-Json -ErrorAction Stop } catch { throw "test-count: endpoint: not valid JSON ($($_.Exception.Message))" }
    if ($e -isnot [pscustomobject]) { throw 'test-count: endpoint: not a JSON object' }
    $keys = @($e.PSObject.Properties | ForEach-Object { $_.Name })
    if ($keys.Count -ne 4) { throw "test-count: endpoint: keys must be exactly schemaVersion, label, message, color (got: $($keys -join ', '))" }
    foreach ($k in 'schemaVersion', 'label', 'message', 'color') {
        if ($k -cnotin $keys) { throw "test-count: endpoint: missing '$k'" }
    }
    if (-not (Test-TestCountInt $e.schemaVersion 1 1)) { throw 'test-count: endpoint: schemaVersion must be the integer 1' }
    foreach ($k in 'label', 'message', 'color') {
        if ($e.$k -isnot [string]) { throw "test-count: endpoint: '$k' must be a string" }
    }
}

function Assert-TestCountPublishInputs {
    # Each value ends up in a file, a markdown link, or (commit) a git argument: validate before any of that.
    param([string]$Commit, [string]$RunId, [string]$RunUrl, [string]$Date, [string]$Repo)
    if (-not [regex]::IsMatch($Commit, '\A[0-9a-f]{40}\z')) { throw 'test-count: commit must be 40 lowercase hex' }
    if (-not [regex]::IsMatch($RunId, '\A[0-9]{1,20}\z')) { throw 'test-count: run id must be 1-20 digits' }
    if (-not [regex]::IsMatch($RunUrl, '\Ahttps://[A-Za-z0-9._~/-]+\z')) { throw 'test-count: run url must be an https URL of letters, digits and . _ ~ / -' }
    if (-not [regex]::IsMatch($Date, '\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z')) { throw 'test-count: date must be yyyy-MM-dd' }
    if (-not [regex]::IsMatch($Repo, '\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z') -or $Repo -match '(\A|/)\.+(/|\z)') { throw 'test-count: repo must be <owner>/<name>' }
}

function New-TestCountFiles {
    # Renders the three files of the badges branch as strings (LF endings, no BOM is added here; the caller writes bytes).
    param($Counts, [string]$Commit, [string]$RunId, [string]$RunUrl, [string]$Date, [string]$Repo)
    Assert-TestCountPublishInputs $Commit $RunId $RunUrl $Date $Repo
    foreach ($id in $script:TestCountSuiteIds) {
        if (-not $Counts.Contains($id)) { throw "test-count: counts: missing suite '$id'" }
        if (-not (Test-TestCountInt $Counts[$id].Passed 1 1000000)) { throw "test-count: counts: ${id} passed is not an integer in 1..1000000" }
        if (-not (Test-TestCountInt $Counts[$id].Skipped 0 1000000)) { throw "test-count: counts: ${id} skipped is not an integer in 0..1000000" }
    }
    $inv = [cultureinfo]::InvariantCulture
    $total = 0
    $suites = [ordered]@{}
    foreach ($id in $script:TestCountSuiteIds) {
        $total += [int]$Counts[$id].Passed
        $suites[$id] = [ordered]@{ passed = [int]$Counts[$id].Passed; skipped = [int]$Counts[$id].Skipped }
    }
    $totalText = ([long]$total).ToString('N0', $inv)

    $endpoint = [ordered]@{ schemaVersion = 1; label = 'tests'; message = "$totalText passed"; color = 'brightgreen' } | ConvertTo-Json -Compress
    $ledger = [ordered]@{ schema = 1; commit = $Commit; run_id = $RunId; date = $Date; suites = $suites } | ConvertTo-Json -Compress -Depth 5

    $cell = { param([string]$s) $s.Replace('|', '\|') }
    $meta = Get-TestCountSuiteMeta
    $rows = foreach ($id in $script:TestCountSuiteIds) {
        $m = $meta[$id]
        "| $(& $cell $m.Label) | $(([long]$Counts[$id].Passed).ToString('N0', $inv)) | $(([long]$Counts[$id].Skipped).ToString('N0', $inv)) | $(& $cell $m.Lane) | $(& $cell $m.Conditions) | ``$(& $cell $m.Command)`` |"
    }
    $lines = @(
        '# Test count'
        ''
        "**$totalText tests passed** for commit [``$Commit``](https://github.com/$Repo/commit/$Commit) ($Date)."
        ''
        "Counted by [workflow run $RunId]($RunUrl). Workflow status: [![test-count](https://github.com/$Repo/actions/workflows/test-count.yml/badge.svg?branch=main)](https://github.com/$Repo/actions/workflows/test-count.yml)"
        ''
        '| Label | Passed | Skipped | Lane | Conditions | Command |'
        '|---|---:|---:|---|---|---|'
    ) + @($rows) + @(
        ''
        'The figure is the number of tests executed and passed at that one commit; skipped tests are not counted.'
        'When the status badge is red the figure is for the last commit where every suite passed.'
    )
    [ordered]@{
        'endpoint.json' = $endpoint
        'ledger.json'   = $ledger
        'README.md'     = ($lines -join "`n") + "`n"
    }
}

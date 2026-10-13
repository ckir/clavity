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

    Context '-ShowMessages (why a row failed, not just which)' {
        It 'prints the failing row''s message under its FAILED name when asked' {
            $r = Invoke-Runner -ExtraArgs @('-Files', "$script:Pass1,$script:Fail1", '-ShowMessages', '-ThrottleLimit', '2')
            $r.Exit | Should -Be 1 -Because $r.Out
            $r.Out | Should -Match 'FAILED f1\.this-row-fails'
            $r.Out | Should -Match 'Expected 2, but got 1'
        }

        It 'does NOT print messages unless asked (the default output stays as terse as before)' {
            $r = Invoke-Runner -ExtraArgs @('-Files', "$script:Pass1,$script:Fail1", '-ThrottleLimit', '2')
            $r.Exit | Should -Be 1 -Because $r.Out
            $r.Out | Should -Match 'FAILED f1\.this-row-fails'
            $r.Out | Should -Not -Match 'Expected 2'
        }

        It 'collapses a multi-line message to one line and truncates a long one' {
            $long = New-Suite 'long-msg' "Describe 'lm' { It 'multi' { throw ('first-line' + [Environment]::NewLine + 'second-line' + [Environment]::NewLine + ('x' * 2000)) } }"
            $r = Invoke-Runner -ExtraArgs @('-Files', $long, '-ShowMessages')
            $r.Exit | Should -Be 1 -Because $r.Out
            $r.Out | Should -Match 'first-line second-line'
            $r.Out | Should -Not -Match 'x{400}'
        }
    }

    Context '-Exclude (suites a lane deliberately does not run)' {
        It 'drops the named suite from the list by base name and keeps the others' {
            $r = Invoke-Runner -ExtraArgs @('-Files', "$script:Pass1,$script:Pass2,$script:Fail1", '-Exclude', 'fail-one', '-ListOnly')
            $r.Exit | Should -Be 0 -Because $r.Out
            $lines = @($r.Out -split "`r?`n" | Where-Object { $_ -match '\.Tests\.ps1$' })
            $lines | Should -Be @($script:Pass1, $script:Pass2)
        }

        It 'does not run an excluded failing suite, and says loudly that it was excluded' {
            $r = Invoke-Runner -ExtraArgs @('-Files', "$script:Pass1,$script:Fail1", '-Exclude', 'fail-one', '-ThrottleLimit', '2')
            $r.Exit | Should -Be 0 -Because $r.Out
            $r.Out | Should -Match 'EXCLUDED \(not run\): fail-one'
            $r.Out | Should -Match 'excluded=1'
            $r.Out | Should -Not -Match 'this-row-fails'
        }

        It 'exits 1 when an exclusion matches nothing, so a typo cannot silently exclude nothing' {
            $r = Invoke-Runner -ExtraArgs @('-Files', "$script:Pass1,$script:Pass2", '-Exclude', 'fail-on', '-ThrottleLimit', '2')
            $r.Exit | Should -Be 1 -Because $r.Out
            $r.Out | Should -Match 'fail-on'
        }

        It 'exits 1 when excluding leaves nothing to run' {
            $r = Invoke-Runner -ExtraArgs @('-Files', $script:Pass1, '-Exclude', 'pass-one')
            $r.Exit | Should -Be 1 -Because $r.Out
        }

        It 'matches a whole base name, not a substring (pass-one must not exclude pass-one-b)' {
            $near = New-Suite 'pass-one-b' "Describe 'pb' { It 'z' { 1 | Should -Be 1 } }"
            $r = Invoke-Runner -ExtraArgs @('-Files', "$script:Pass1,$near", '-Exclude', 'pass-one', '-ListOnly')
            $r.Exit | Should -Be 0 -Because $r.Out
            @($r.Out -split "`r?`n" | Where-Object { $_ -match '\.Tests\.ps1$' }) | Should -Be @($near)
        }
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

        It 'the real slow recipe lists hook-spawn-budget, and -Exclude hook-spawn-budget removes exactly that one suite' {
            $all = Invoke-Runner -ExtraArgs @('-Recipe', 'test-scripts-slow', '-ListOnly')
            $cut = Invoke-Runner -ExtraArgs @('-Recipe', 'test-scripts-slow', '-Exclude', 'hook-spawn-budget', '-ListOnly')
            $a = @($all.Out -split "`r?`n" | Where-Object { $_ -match '\.Tests\.ps1$' })
            $c = @($cut.Out -split "`r?`n" | Where-Object { $_ -match '\.Tests\.ps1$' })
            @($a | Where-Object { $_ -like '*/hook-spawn-budget.Tests.ps1' }).Count | Should -Be 1 -Because 'the exclusion must have something to exclude, or it is a no-op that looks like a lane'
            $c.Count | Should -Be ($a.Count - 1)
            @($c | Where-Object { $_ -like '*hook-spawn-budget*' }) | Should -BeNullOrEmpty
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

    It 'the ci-scripts.yml Linux job runs the runner with the committed inventory' {
        $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $wf = Get-Content -LiteralPath (Join-Path $repo '.github/workflows/ci-scripts.yml') -Raw
        $job = [regex]::Match($wf, '(?ms)^  dev-scripts-linux:\r?\n.*?(?=^  [A-Za-z0-9_-]+:\r?\n|\z)')
        $job.Success | Should -BeTrue -Because 'ci-scripts.yml must define the dev-scripts-linux job'
        $job.Value | Should -Match 'runs-on: ubuntu-latest'
        $job.Value | Should -Match ([regex]::Escape('run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory scripts/tests/_skip-inventory.md'))
    }

Context '-Directory, the skip-approval gate and the generated skip inventory' {
    BeforeAll {
        $script:Os      = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
        $script:Native  = if ($IsWindows) { 'WindowsOnly' } else { 'LinuxOnly' }   # skips only where it is NOT native...
        $script:Foreign = if ($IsWindows) { 'LinuxOnly' } else { 'WindowsOnly' }   # ...so THIS one must skip on this OS
        function New-Dir([string]$Name, [string]$Body) {
            $d = Join-Path $script:Work $Name; New-Item -ItemType Directory -Path $d -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $d 'fx.Tests.ps1') -Value $Body
            $d
        }
        $script:Good = @"
Describe 'd' {
    It 'static ok' -Skip -Tag '$($script:Foreign)' { 1 | Should -Be 2 }
    It 'probe ok' { Set-ItResult -Skipped -Because 'APPROVED:NotAsRoot: fixture' }
    It 'needs tool' -Skip -Tag 'NeedsTool:ISCC' { 1 | Should -Be 2 }
    It 'runs' { 1 | Should -Be 1 }
}
"@
        function Write-Inv([string]$Dir, [string]$Inv) { Invoke-Runner -ExtraArgs @('-Directory', $Dir, '-SkipInventory', $Inv, '-WriteSkipInventory') }
    }
    It 'globs only *.Tests.ps1 under -Directory and counts the skipped rows' {
        $d = New-Dir 'glob' $script:Good; Set-Content -LiteralPath (Join-Path $d 'not-a-suite.ps1') -Value "throw 'must not be globbed'"
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d)
        $r.Exit | Should -Be 0 -Because $r.Out
        $r.Out | Should -Match 'passed=1 failed=0 skipped=3'
    }
    It 'exits 1 when -Directory does not exist' {
        $r = Invoke-Runner -ExtraArgs @('-Directory', (Join-Path $script:Work 'nope'))
        $r.Exit | Should -Be 1
        $r.Out | Should -Match "-Directory '.*nope' does not exist"   # an unknown PARAMETER also exits 1 today, so the exit code alone would pass vacuously at Step 2
    }
    It '-WriteSkipInventory requires -Directory and -SkipInventory' {
        $r = Invoke-Runner -ExtraArgs @('-Files', $script:Pass1, '-WriteSkipInventory')
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'requires -Directory'
    }
    It 'writes an inventory with static and conditional tables, and the check then passes' {
        $d = New-Dir 'w1' $script:Good; $inv = Join-Path $script:Work 'w1.md'
        (Write-Inv $d $inv).Exit | Should -Be 0
        $t = Get-Content -LiteralPath $inv -Raw
        $t | Should -Match "(?m)^## $($script:Os)\r?$"
        $t | Should -Match "(?s)### static.*\| fx\.Tests\.ps1 \| d\.static ok \| $($script:Foreign) \| - \|.*### conditional"
        $t | Should -Match '\| fx\.Tests\.ps1 \| d\.probe ok \| NotAsRoot \| fixture \|'
        $t | Should -Match '\| fx\.Tests\.ps1 \| d\.needs tool \| NeedsTool:ISCC \| - \|'
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d, '-SkipInventory', $inv)
        $r.Exit | Should -Be 0 -Because $r.Out
    }
    It 'fails UNAPPROVED for an untagged discovery-time skip, and says why' {
        $d = New-Dir 'u1' "Describe 'd' { It 'bare' -Skip { 1 | Should -Be 2 } }"
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'UNAPPROVED SKIP fx\.Tests\.ps1 :: d\.bare'
        $r.Out | Should -Match 'discovery-time -Skip carries no reason text'
    }
    It 'rejects a tag or an APPROVED: reason outside the closed vocabulary' {
        $d = New-Dir 'u2' "Describe 'd' { It 'tagged' -Skip -Tag 'Flaky' { 1 | Should -Be 2 }; It 'reasoned' { Set-ItResult -Skipped -Because 'APPROVED:Flaky: no' } }"
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'UNAPPROVED SKIP fx\.Tests\.ps1 :: d\.tagged'
        $r.Out | Should -Match 'UNAPPROVED SKIP fx\.Tests\.ps1 :: d\.reasoned'
    }
    It 'accepts a tag inherited from the enclosing Context' {
        $d = New-Dir 'u3' "Describe 'd' { Context 'c' -Tag 'NeedsTool:yq' { It 'inherits' -Skip { 1 | Should -Be 2 } } }"
        (Invoke-Runner -ExtraArgs @('-Directory', $d)).Exit | Should -Be 0
    }
    It 'fails OS-TAG MISMATCH when a row tagged for another OS RAN here' {
        $d = New-Dir 'm1' "Describe 'd' { It 'ran' -Tag '$($script:Foreign)' { 1 | Should -Be 1 } }"
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'OS-TAG MISMATCH fx\.Tests\.ps1 :: d\.ran'
    }
    It 'fails OS-TAG MISMATCH when a row tagged for THIS OS skipped without an APPROVED reason, and accepts one that says why' {
        $bad = New-Dir 'm2' "Describe 'd' { It 'native skip' -Skip -Tag '$($script:Native)' { 1 | Should -Be 2 } }"
        $r = Invoke-Runner -ExtraArgs @('-Directory', $bad)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'OS-TAG MISMATCH fx\.Tests\.ps1 :: d\.native skip'
        $ok = New-Dir 'm3' "Describe 'd' { It 'native probe' -Tag '$($script:Native)' { Set-ItResult -Skipped -Because 'APPROVED:NeedsTool:ISCC: not installed' } }"
        (Invoke-Runner -ExtraArgs @('-Directory', $ok)).Exit | Should -Be 0
    }
    It 'fails SKIP-INVENTORY STALE when a static skip is added after the inventory was written' {
        $d = New-Dir 's1' $script:Good; $inv = Join-Path $script:Work 's1.md'; (Write-Inv $d $inv) | Out-Null
        Set-Content -LiteralPath (Join-Path $d 'fx.Tests.ps1') -Value ($script:Good -replace "It 'runs'", "It 'late static' -Skip -Tag '$($script:Foreign)' { 1 | Should -Be 2 }; It 'runs'")
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d, '-SkipInventory', $inv)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'SKIP-INVENTORY STALE: regenerate with -WriteSkipInventory'
        $r.Out | Should -Match 'late static'
    }
    It 'fails SKIP-INVENTORY STALE when a static row was un-skipped (a listed static row no longer skips)' {
        $d = New-Dir 's2' $script:Good; $inv = Join-Path $script:Work 's2.md'; (Write-Inv $d $inv) | Out-Null
        $was = [regex]::Escape("It 'static ok' -Skip -Tag '$($script:Foreign)' { 1 | Should -Be 2 }")
        Set-Content -LiteralPath (Join-Path $d 'fx.Tests.ps1') -Value ($script:Good -replace $was, "It 'static ok' -Tag 'Plain' { 1 | Should -Be 1 }")   # a PASSING row, so exit 1 can only come from the inventory
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d, '-SkipInventory', $inv)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'SKIP-INVENTORY STALE'
    }
    It 'fails when a conditional skip is not listed, but passes when a listed conditional row did not skip' {
        $d = New-Dir 'c1' $script:Good; $inv = Join-Path $script:Work 'c1.md'; (Write-Inv $d $inv) | Out-Null
        $keep = Get-Content -LiteralPath $inv | Where-Object { $_ -notmatch 'd\.needs tool' }
        Set-Content -LiteralPath $inv -Value $keep
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d, '-SkipInventory', $inv)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'needs tool'
        Set-Content -LiteralPath $inv -Value ($keep + '| fx.Tests.ps1 | d.never skipped here | NotAsRoot | host-dependent |')
        # re-add the row we removed so only the extra, non-skipping row differs
        Set-Content -LiteralPath $inv -Value (Get-Content -LiteralPath $inv | ForEach-Object { $_; if ($_ -match 'd\.probe ok') { '| fx.Tests.ps1 | d.needs tool | NeedsTool:ISCC | - |' } })
        (Invoke-Runner -ExtraArgs @('-Directory', $d, '-SkipInventory', $inv)).Exit | Should -Be 0
    }
    It 'fails CLOSED when the inventory has no section for this OS' {
        $d = New-Dir 'f1' $script:Good; $inv = Join-Path $script:Work 'f1.md'
        Set-Content -LiteralPath $inv -Value @('# inventory', '## plan9', '### static', '| Suite | Row | Tag | Reason |', '| --- | --- | --- | --- |')
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d, '-SkipInventory', $inv)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match "SKIP-INVENTORY: no `"## $($script:Os)`" section"
    }
    It 'checks only the suites this run covered (a subset run does not report other suites as vanished)' {
        $d = New-Dir 'p1' $script:Good; $inv = Join-Path $script:Work 'p1.md'; (Write-Inv $d $inv) | Out-Null
        # The foreign row goes UNDER ### static (the two-way table); at end of file it would land in the one-way conditional table.
        $ls = @(Get-Content -LiteralPath $inv); $ci = [array]::IndexOf($ls, '### conditional'); $at = $ci - 1; while ($ls[$at] -eq '') { $at-- }
        Set-Content -LiteralPath $inv -Value (@($ls[0..$at]) + '| other.Tests.ps1 | o.elsewhere | WindowsOnly | - |' + @($ls[($at + 1)..($ls.Count - 1)]))
        (Invoke-Runner -ExtraArgs @('-Directory', $d, '-SkipInventory', $inv)).Exit | Should -Be 0
    }
    It '-Files takes precedence over -Directory' {
        $d = New-Dir 'pr1' $script:Good
        $r = Invoke-Runner -ExtraArgs @('-Files', $script:Pass1, '-Directory', $d)
        $r.Exit | Should -Be 0 -Because $r.Out
        $r.Out | Should -Match 'passed=2 failed=0 skipped=0'
    }
    It 'escapes a pipe in a row name when writing, and the check then still passes' {
        $d = New-Dir 'e1' "Describe 'd' { It 'a | b' -Skip -Tag '$($script:Foreign)' { 1 | Should -Be 2 } }"; $inv = Join-Path $script:Work 'e1.md'
        (Write-Inv $d $inv).Exit | Should -Be 0
        (Get-Content -LiteralPath $inv -Raw) | Should -Match ([regex]::Escape('| fx.Tests.ps1 | d.a \| b |'))
        (Invoke-Runner -ExtraArgs @('-Directory', $d, '-SkipInventory', $inv)).Exit | Should -Be 0
    }
    It 'writing keeps an existing conditional row that did not skip in this run (the table only accumulates)' {
        $d = New-Dir 'k2' $script:Good; $inv = Join-Path $script:Work 'k2.md'; (Write-Inv $d $inv) | Out-Null
        Set-Content -LiteralPath $inv -Value (Get-Content -LiteralPath $inv | ForEach-Object { $_; if ($_ -match 'd\.probe ok') { '| fx.Tests.ps1 | d.host dependent | NotAsRoot | seen once as root |' } })
        (Write-Inv $d $inv).Exit | Should -Be 0
        (Get-Content -LiteralPath $inv -Raw) | Should -Match ([regex]::Escape('| fx.Tests.ps1 | d.host dependent | NotAsRoot | seen once as root |'))
    }
    It 'accepts a tag inherited from a Describe two levels up (the .Parent walk)' {
        $d = New-Dir 'u4' "Describe 'd' -Tag 'NeedsTool:yq' { Context 'c' { It 'deep' -Skip { 1 | Should -Be 2 } } }"
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d)
        $r.Exit | Should -Be 0 -Because $r.Out
    }
    It 'classifies a native-OS-tagged probe skip by its APPROVED reason: conditional, never static' {
        $d = New-Dir 'cl1' "Describe 'd' { It 'native probe' -Tag '$($script:Native)' { Set-ItResult -Skipped -Because 'APPROVED:NeedsTool:ISCC: not installed' } }"; $inv = Join-Path $script:Work 'cl1.md'
        (Write-Inv $d $inv).Exit | Should -Be 0
        $t = Get-Content -LiteralPath $inv -Raw
        $t | Should -Match '(?s)### conditional.*\| fx\.Tests\.ps1 \| d\.native probe \| NeedsTool:ISCC \| not installed \|'
        $t | Should -Not -Match '(?s)### static.*d\.native probe.*### conditional'
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d, '-SkipInventory', $inv)
        $r.Exit | Should -Be 0 -Because $r.Out
    }
    It 'refuses -WriteSkipInventory on a red run and leaves the file untouched' {
        $d = New-Dir 'rf1' "Describe 'd' { It 'boom' { 1 | Should -Be 2 }; It 'st' -Skip -Tag '$($script:Foreign)' { 1 | Should -Be 2 } }"; $inv = Join-Path $script:Work 'rf1.md'
        $known = "# known`n## $($script:Os)`n### static`n| Suite | Row | Tag | Reason |`n| --- | --- | --- | --- |`n| fx.Tests.ps1 | d.st | $($script:Foreign) | - |`n"
        [IO.File]::WriteAllText($inv, $known)
        $r = Write-Inv $d $inv
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'SKIP-INVENTORY: refusing to write: the run had failing tests, bad containers or missing results'
        [IO.File]::ReadAllText($inv) | Should -BeExactly $known
    }
    It 'is case-exact: a lower-case tag or APPROVED: reason is UNAPPROVED' {
        $d = New-Dir 'cx1' "Describe 'd' { It 'lowtag' -Skip -Tag 'windowsonly' { 1 | Should -Be 2 }; It 'lowreason' { Set-ItResult -Skipped -Because 'approved:NotAsRoot: x' } }"
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'UNAPPROVED SKIP fx\.Tests\.ps1 :: d\.lowtag'
        $r.Out | Should -Match 'UNAPPROVED SKIP fx\.Tests\.ps1 :: d\.lowreason'
    }
    It 'fails closed when the -SkipInventory file does not exist (check mode)' {
        $d = New-Dir 'nf1' $script:Good
        $r = Invoke-Runner -ExtraArgs @('-Directory', $d, '-SkipInventory', (Join-Path $script:Work 'no-such-inventory.md'))
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'SKIP-INVENTORY: file not found: .*no-such-inventory\.md'
    }
    It 'writing twice produces a byte-identical file (idempotent)' {
        $d = New-Dir 'id1' $script:Good; $inv = Join-Path $script:Work 'id1.md'
        (Write-Inv $d $inv).Exit | Should -Be 0
        $one = [IO.File]::ReadAllBytes($inv)
        (Write-Inv $d $inv).Exit | Should -Be 0
        $two = [IO.File]::ReadAllBytes($inv)
        [Convert]::ToBase64String($two) | Should -BeExactly ([Convert]::ToBase64String($one))
    }
    It 'writes LF line endings and no BOM' {
        $d = New-Dir 'lf1' $script:Good; $inv = Join-Path $script:Work 'lf1.md'; (Write-Inv $d $inv) | Out-Null
        $b = [IO.File]::ReadAllBytes($inv)
        ($b -contains 13) | Should -BeFalse -Because 'no CR byte: the repo pins eol=lf'
        ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) | Should -BeFalse -Because 'no UTF-8 BOM'
    }
    It 'writing preserves another OS section byte-for-byte' {
        $d = New-Dir 'k1' $script:Good; $inv = Join-Path $script:Work 'k1.md'
        Set-Content -LiteralPath $inv -Value @('# inventory', '## plan9', '### static', '| Suite | Row | Tag | Reason |', '| --- | --- | --- | --- |', '| x.Tests.ps1 | a.b | WindowsOnly | - |')
        (Write-Inv $d $inv).Exit | Should -Be 0
        (Get-Content -LiteralPath $inv -Raw) | Should -Match '(?s)## plan9\r?\n### static\r?\n\| Suite \| Row \| Tag \| Reason \|\r?\n\| --- \| --- \| --- \| --- \|\r?\n\| x\.Tests\.ps1 \| a\.b \| WindowsOnly \| - \|'
    }
}
}

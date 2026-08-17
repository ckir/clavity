Describe 'check-ci-filter-coverage.ps1' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Gate     = Join-Path $script:RepoRoot 'scripts/check-ci-filter-coverage.ps1'
        $script:Real     = Join-Path $script:RepoRoot '.github/workflows/ci-scripts.yml'
        $script:Fixtures = New-Object System.Collections.ArrayList   # FIXTURE HYGIENE

        # Run the gate against a FIXTURE workflow while keeping the REAL repo root, so Check B still
        # reasons over the real suites. Returns exit code plus merged output.
        function Invoke-Gate {
            param([string]$WorkflowPath, [string]$Root = $script:RepoRoot)
            $out = & pwsh -NoProfile -File $script:Gate -RepoRoot $Root -WorkflowPath $WorkflowPath 2>&1
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Out = ($out | Out-String) }
        }

        # A copy of the real workflow that a test can then damage in one specific way.
        function New-WorkflowFixture {
            param([scriptblock]$Mutate)
            $p = Join-Path ([IO.Path]::GetTempPath()) ("cifc-" + [guid]::NewGuid().ToString('N') + '.yml')
            [void]$script:Fixtures.Add($p)
            $lines = [string[]](Get-Content -LiteralPath $script:Real)
            $lines = & $Mutate $lines
            [IO.File]::WriteAllLines($p, $lines)
            $p
        }
    }
    AfterAll {
        foreach ($f in $script:Fixtures) { Remove-Item -LiteralPath $f -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Context 'the real repository' {
        It 'passes as shipped' {
            $r = Invoke-Gate -WorkflowPath $script:Real
            $r.ExitCode | Should -Be 0 -Because "the shipped filter must satisfy its own gate: $($r.Out)"
            $r.Out | Should -Match 'check-ci-filter-coverage: OK'
        }

        # NON-VACUITY. Without this the suite above could pass because the gate checks nothing at all -
        # every other row here asserts a FAILURE, so only this one proves the pass is meaningful.
        It 'reports a non-zero count of required entries and reached roots on the pass line' {
            $r = Invoke-Gate -WorkflowPath $script:Real
            $r.Out | Should -Match '(\d+) required entries present in all 2 paths: blocks'
            [int]($r.Out | Select-String -Pattern '(\d+) required entries' ).Matches[0].Groups[1].Value |
                Should -BeGreaterThan 0
            [int]($r.Out | Select-String -Pattern '(\d+) root\(s\) named by').Matches[0].Groups[1].Value |
                Should -BeGreaterThan 0
        }
    }

    Context 'CHECK A - required entries' {
        # THE DEFECT THIS GATE WAS BUILT FOR. Nothing previously noticed that a plugin tree the suite
        # asserts against was absent from the filter.
        It 'reds when a required entry is missing from BOTH blocks' {
            $p = New-WorkflowFixture { param($l) $l | Where-Object { $_ -notmatch "clavity-dotnet/plugin/\*\*" } }
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match "MISSING required entry 'clavity-dotnet/plugin/\*\*'"
            $r.Out | Should -Match 'block\(s\) 1, 2'
        }

        # THE TWO BLOCKS ARE A PAIR AND NOTHING ELSE CHECKS THEM. Adding an entry to `push` and
        # forgetting `pull_request` yields a filter that is right on merge and wrong on every PR - the
        # half that actually gates review. The row names the block so the message is actionable.
        It 'reds when a required entry is missing from ONLY ONE block, and says which' {
            $seen = $false
            $p = New-WorkflowFixture {
                param($l)
                $out = New-Object System.Collections.ArrayList
                foreach ($line in $l) {
                    if (-not $seen -and $line -match "^\s*-\s*'build/members\.json'\s*$") { $seen = $true; continue }
                    [void]$out.Add($line)
                }
                $out
            }
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match "MISSING required entry 'build/members\.json'"
            # Block 1 only - NOT '1, 2'. Asserting WHICH block, not merely that something failed.
            $r.Out | Should -Match "block\(s\) 1 -"
        }

        It 'names the reason the entry is required, so the message is self-explaining' {
            $p = New-WorkflowFixture { param($l) $l | Where-Object { $_ -notmatch "docs/agy-disciplines-marker-contract\.md" } }
            $r = Invoke-Gate -WorkflowPath $p
            $r.Out | Should -Match 'check-injected-context resolves that token against the real repo root'
        }
    }

    Context 'CHECK B - root vocabulary' {
        # Removing the tree entry leaves the ROOT uncovered too, which is the fail-closed net: even if
        # someone deleted the required-entry row, Check B still reds on the root.
        It 'reds on a root no filter entry reaches' {
            $p = New-WorkflowFixture { param($l) $l | Where-Object { $_ -notmatch 'clavity-classic/plugin' } }
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match "UNCOVERED root 'clavity-classic'"
            $r.Out | Should -Match 'plugin-hooks-payload\.Tests\.ps1'   # it names WHO reaches it
        }

        It 'reds on a REDUNDANT exemption once the filter covers that root' {
            # 'seed' is exempt as fixture-only; adding a seed entry to the filter must force the table
            # to be corrected rather than leaving a lie in it.
            $p = New-WorkflowFixture {
                param($l)
                $l | ForEach-Object { $_; if ($_ -match "^\s*-\s*'scripts/\*\*'\s*$") { "      - 'seed/**'" } }
            }
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match "REDUNDANT exemption 'seed'"
        }
    }

    Context 'the gate refuses to pass vacuously' {
        It 'reds when a paths: block parses as empty rather than reporting success' {
            $p = New-WorkflowFixture {
                param($l)
                # Drop every list item, keeping the two `paths:` keys - the shape that would otherwise
                # make every required-entry assertion pass against nothing.
                $l | Where-Object { $_ -notmatch "^\s*-\s*'[^']+'\s*$" }
            }
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match 'parsed as EMPTY'
        }

        It 'reds when fewer than two paths: blocks are found' {
            $p = New-WorkflowFixture { param($l) $l | Where-Object { $_ -notmatch '^\s*paths:\s*$' } }
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match 'expected at least 2 paths: blocks'
        }

        It 'reds when the workflow is absent' {
            $r = Invoke-Gate -WorkflowPath (Join-Path ([IO.Path]::GetTempPath()) 'no-such-workflow.yml')
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match 'workflow not found'
        }

        # A SUITE THAT DOES NOT PARSE MUST BE A HARD ERROR, NOT A SKIP. A gate that skips unparseable
        # input silently shrinks the corpus it reasons over and then reports OK - the fail-open shape
        # this whole gate exists to prevent.
        It 'reds on a suite that does not parse, instead of skipping it' {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("cifc-repo-" + [guid]::NewGuid().ToString('N'))
            [void]$script:Fixtures.Add($root)
            New-Item -ItemType Directory -Path (Join-Path $root 'scripts/tests') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'docs/x.md') -Value 'x' -Encoding ascii
            Set-Content -LiteralPath (Join-Path $root 'scripts/tests/broken.Tests.ps1') -Value 'Describe {' -Encoding ascii
            & git -C $root init -q
            & git -C $root add -A
            $r = Invoke-Gate -WorkflowPath $script:Real -Root $root
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match 'broken\.Tests\.ps1 does not parse'
        }
    }
}

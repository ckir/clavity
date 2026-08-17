Describe 'check-ci-filter-coverage.ps1' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Gate     = Join-Path $script:RepoRoot 'scripts/check-ci-filter-coverage.ps1'
        $script:Real     = Join-Path $script:RepoRoot '.github/workflows/ci-scripts.yml'
        $script:Fixtures = New-Object System.Collections.ArrayList   # FIXTURE HYGIENE

        # Run the gate against a FIXTURE workflow while keeping the REAL repo root, which is only used to
        # default -WorkflowPath. Returns exit code plus merged output.
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
        It 'reports a non-zero count of required entries on the pass line' {
            $r = Invoke-Gate -WorkflowPath $script:Real
            $r.Out | Should -Match 'all (\d+) required entries present in all 2 paths: blocks'
            [int]($r.Out | Select-String -Pattern 'all (\d+) required entries').Matches[0].Groups[1].Value |
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
            # ONE PATTERN, NOT TWO. Asserting the entry and the block number as SEPARATE matches against
            # the whole multi-line output is not an assertion about one line: any other entry missing from
            # block 1, plus members.json missing from block 2, satisfies both halves while the gate has
            # reported the WRONG block. They must be matched together or the row proves nothing.
            $r.Out | Should -Match "MISSING required entry 'build/members\.json' from paths: block\(s\) 1 -"
        }

        # GitHub matches paths: CASE-SENSITIVELY; PowerShell's -notcontains does not. A capitalised entry
        # would satisfy a case-insensitive gate while GitHub silently never fired the workflow - a green
        # gate certifying a filter that does not trigger. This row dies if the operator loses its `-c`.
        It 'reds on a case-variant entry, because GitHub would not match it' {
            $p = New-WorkflowFixture { param($l) $l | ForEach-Object { $_ -replace "^(\s*-\s*)'scripts/\*\*'\s*$", "`$1'Scripts/**'" } }
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match "MISSING required entry 'scripts/\*\*'"
        }

        It 'names the reason the entry is required, so the message is self-explaining' {
            $p = New-WorkflowFixture { param($l) $l | Where-Object { $_ -notmatch "docs/agy-disciplines-marker-contract\.md" } }
            $r = Invoke-Gate -WorkflowPath $p
            $r.Out | Should -Match 'check-injected-context resolves that token against the real repo root'
        }
    }

    Context 'a workflow GitHub could not use' {
        # BOTH ROWS WERE MEASURED FAIL-OPENS BEFORE THE FIX, with `yq` as the oracle: the gate reported
        # "OK - 12 required entries present in all 2 paths: blocks" on each of these, i.e. it certified a
        # filter that GitHub either cannot parse or ignores entirely. A hand-written parser has to be
        # probed against a real parser for the same format, because the whole defect class is "mine
        # accepts what the real one rejects".
        It 'reds on TAB indentation, which YAML forbids and this gate would otherwise read happily' {
            $tab = [string][char]9
            $p = New-WorkflowFixture {
                param($l)
                $l | ForEach-Object { if ($_ -match "^\s+-\s*'") { ($tab + $tab + $tab) + $_.TrimStart() } else { $_ } }
            }
            # The fixture must actually contain tabs, or the row proves nothing about tab handling.
            @(Get-Content -LiteralPath $p | Where-Object { $_ -match $tab }).Count |
                Should -BeGreaterThan 0 -Because 'the fixture must really be tab-indented'
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match 'uses a TAB in the indentation'
        }

        # THE OTHER HALF OF THE TAB RULE, and without this row the narrowing has no oracle. YAML forbids a
        # tab in INDENTATION; a tab inside a string VALUE is legal. The first version flagged any tab in
        # the file, which would have failed this gate - now a pre-push hook - on a legal edit. A gate that
        # reds on legal input is its own kind of defect, so both directions are pinned.
        It 'ACCEPTS a tab inside a string value, which YAML permits' {
            $tab = [string][char]9
            $p = New-WorkflowFixture {
                param($l)
                $l | ForEach-Object { if ($_ -match '^name:') { "name: ci${tab}scripts" } else { $_ } }
            }
            @(Get-Content -LiteralPath $p | Where-Object { $_ -match $tab }).Count |
                Should -BeGreaterThan 0 -Because 'the fixture must really contain a tab, or it proves nothing'
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 0 -Because "a tab in a string value is legal YAML: $($r.Out)"
        }

        # A BLOCK SCALAR'S BODY IS OPAQUE TEXT. `run: |` here holds shell script, and indenting a line of
        # shell with a tab is an ordinary thing to do - it is NOT YAML indentation and does not stop the
        # file parsing. Without this row the scalar-tracking has no oracle and would silently rot back
        # INDENT IS COLUMNS, NOT CHARACTERS. A scalar body line indented <TAB><sp><sp> is 10 columns deep
        # but only 3 characters, so a character count put it SHALLOWER than an 8-column opener - the
        # tracker concluded the scalar had ended and then reddened on the leading tab. Legal YAML, false
        # THE SIBLING GATE ALREADY ACCEPTS THIS SHAPE. check-injected-context.Tests.ps1's $PathsKeyRx
        # tolerates a YAML anchor and a trailing comment on the key; this gate demanded a bare `paths:`,
        # so the two disagreed about what a paths: block IS and an anchor made only one of them red.
        It 'ACCEPTS a YAML anchor and a trailing comment on the paths: key' {
            $p = New-WorkflowFixture {
                param($l)
                $seen = $false
                $l | ForEach-Object {
                    if (-not $seen -and $_ -match '^(\s*)paths:\s*$') { $seen = $true; "$($Matches[1])paths: &shared   # the push filter" }
                    else { $_ }
                }
            }
            (Get-Content -LiteralPath $p | Where-Object { $_ -match 'paths: &shared' }).Count |
                Should -Be 1 -Because 'the fixture must really carry the anchor'
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 0 -Because "an anchored paths: key is legal YAML and the sibling gate accepts it: $($r.Out)"
        }

        # A `paths:`-SHAPED LINE INSIDE A BLOCK SCALAR IS PROSE, NOT A FILTER. The two loops used to derive
        # scalar state independently - the tab check knew about scalars, the block collector did not - so a
        # `workflow_dispatch` input documented with `description: |` containing the word `paths:` registered
        # as a third, empty block and the gate reddened "block #1 parsed as EMPTY". MEASURED: yq parsed that
        # document fine with all 12 real paths. Legal edit, misleading message, blocked push.
        It 'ACCEPTS a paths:-shaped line inside a block scalar body' {
            $p = New-WorkflowFixture {
                param($l)
                $o = New-Object System.Collections.ArrayList
                foreach ($line in $l) {
                    [void]$o.Add($line)
                    if ($line -match '^on:\s*$') {
                        [void]$o.Add('  workflow_dispatch:')
                        [void]$o.Add('    inputs:')
                        [void]$o.Add('      test_dir:')
                        [void]$o.Add('        description: |')
                        [void]$o.Add('          paths: # comma separated list')
                    }
                }
                $o
            }
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 0 -Because "prose inside a block scalar is not a filter block: $($r.Out)"
            $r.Out | Should -Match 'in all 2 paths: blocks' -Because 'it must still find exactly the two REAL blocks'
        }

        # THE OTHER DIRECTION, AND THE ONE A COLUMN-BASED INDENT GOT WRONG. A line with FEWER spaces than
        # the scalar requires, followed by a tab, is not scalar content - it is illegal YAML. Expanding the
        # tab to 8 columns made it measure DEEPER than a shallow opener, so it was taken for body text and
        # the tab check was skipped: a fail-open certifying a workflow GitHub cannot parse. Counting spaces
        # only - a tab ENDS indentation, which is what YAML means - measures it as shallower and flags it.
        # The opener here is deliberately shallow (2), because that is the geometry that breaks columns.
        It 'reds on an under-indented TAB after a shallow block-scalar opener' {
            $tab = [string][char]9
            $p = New-WorkflowFixture {
                param($l)
                $o = New-Object System.Collections.ArrayList
                foreach ($line in $l) {
                    [void]$o.Add($line)
                    if ($line -match '^on:\s*$') {
                        [void]$o.Add('  note: |')
                        [void]$o.Add(' ' + $tab + 'not scalar content - illegal indentation')
                    }
                }
                $o
            }
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match 'uses a TAB in the indentation'
        }

        # THESE TWO ROWS REPLACE A PAIR THAT ASSERTED THE OPPOSITE AND WERE BOTH WRONG. They claimed a
        # tab-indented line inside a `run: |` body was legal and had to be ACCEPTED, and three rounds of
        # this gate were built on that premise. MEASURED against `yq`, with a spaces-only structural
        # control that parses: a tab starting a scalar body line is REJECTED, spaces-then-tab is REJECTED,
        # and only a tab AFTER the first non-space character is VALID. So the rule has no scalar exemption
        # at all - leading whitespace is leading whitespace wherever it appears.
        It 'reds on a tab in the LEADING whitespace of a block scalar body line' {
            $tab = [string][char]9
            $p = New-WorkflowFixture {
                param($l)
                $o = New-Object System.Collections.ArrayList; $done = $false
                foreach ($line in $l) {
                    [void]$o.Add($line)
                    if (-not $done -and $line -match '^(\s*)\S.*:\s*\|\s*$') {
                        [void]$o.Add((' ' * ($Matches[1].Length + 2)) + $tab + 'echo "illegal - tab in indentation"')
                        $done = $true
                    }
                }
                $o
            }
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 1 -Because 'yq rejects this document; the gate must not certify it'
            $r.Out | Should -Match 'uses a TAB in the indentation'
        }

        It 'ACCEPTS a tab AFTER the first non-space character of a scalar body line' {
            $tab = [string][char]9
            $p = New-WorkflowFixture {
                param($l)
                $o = New-Object System.Collections.ArrayList; $done = $false
                foreach ($line in $l) {
                    [void]$o.Add($line)
                    if (-not $done -and $line -match '^(\s*)\S.*:\s*\|\s*$') {
                        [void]$o.Add((' ' * ($Matches[1].Length + 2)) + 'echo' + $tab + 'aligned')
                        $done = $true
                    }
                }
                $o
            }
            @(Get-Content -LiteralPath $p | Where-Object { $_ -match $tab }).Count |
                Should -BeGreaterThan 0 -Because 'the fixture must really contain a tab'
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 0 -Because "yq accepts a mid-content tab, so the gate must too: $($r.Out)"
        }

        # QUOTES ARE OPTIONAL IN YAML. `- justfile` is as valid as `- 'justfile'`, and demanding quotes made
        # a legal edit fail to match, TRUNCATE the block at that line, and cascade into false "missing
        # entry" failures for every entry after it. MEASURED: yq VALID, gate exit 1.
        It 'ACCEPTS an UNQUOTED list item in a paths block' {
            $p = New-WorkflowFixture {
                param($l)
                $l | ForEach-Object { if ($_ -match "^(\s*)- 'justfile'\s*$") { "$($Matches[1])- justfile" } else { $_ } }
            }
            (Get-Content -LiteralPath $p | Where-Object { $_ -match '^\s*- justfile\s*$' }).Count |
                Should -BeGreaterThan 0 -Because 'the fixture must really carry an unquoted item'
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 0 -Because "an unquoted scalar is legal YAML and must not truncate the block: $($r.Out)"
        }

        # AND THE SAME TOLERANCE ON `on:` AS ON `paths:`. R11 made the paths key comment-tolerant and left
        # this one demanding end-of-line, which is an inconsistency of my own making: `on: # the triggers`
        # is VALID to yq, and the gate reported "parsed 0" blocks and blocked the push.
        It 'ACCEPTS a trailing comment on the on: key' {
            $p = New-WorkflowFixture { param($l) $l | ForEach-Object { if ($_ -match '^on:\s*$') { 'on: # the triggers' } else { $_ } } }
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 0 -Because "a trailing comment on on: is legal YAML: $($r.Out)"
            $r.Out | Should -Match 'in all 2 paths: blocks' -Because 'it must still find both real blocks'
        }

        It 'reds when the paths: blocks are not under the top-level on: key' {
            # `yq` resolves .on.push.paths to length 0 for this shape - the filter has no trigger meaning
            # at all - yet every required entry is still textually present in the file.
            $p = New-WorkflowFixture { param($l) $l | ForEach-Object { if ($_ -match '^on:\s*$') { 'jobs-not-on:' } else { $_ } } }
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match 'expected at least 2 paths: blocks'
        }
    }

    Context 'the gate refuses to pass vacuously' {
        It 'reds when a paths: block parses as empty rather than reporting success' {
            $p = New-WorkflowFixture {
                param($l)
                # Drop every list item, keeping both `paths:` keys.
                $l | Where-Object { $_ -notmatch "^\s*-\s*'[^']+'\s*$" }
            }
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match 'parsed as EMPTY'
            # THE EXIT CODE ALONE PROVES NOTHING HERE, and an earlier version of this comment claimed
            # otherwise. Without the dedicated empty-block guard the run still fails: `-cnotcontains`
            # against an empty block reports EVERY required entry as missing, so it already fails closed.
            # What the guard actually buys is a message naming the real cause instead of twelve misleading
            # MISSING lines - so THAT is what this row has to assert, and it is what goes red if the guard
            # is deleted.
            $r.Out | Should -Not -Match 'MISSING required entry'
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
    }
}

Describe 'check-ci-filter-coverage.ps1' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Gate     = Join-Path $script:RepoRoot 'scripts/check-ci-filter-coverage.ps1'
        $script:Real     = Join-Path $script:RepoRoot '.github/workflows/ci-scripts.yml'
        $script:Fixtures = New-Object System.Collections.ArrayList   # FIXTURE HYGIENE

        # Run the gate against a FIXTURE workflow. -Root only defaults -WorkflowPath, which is already
        # supplied here, so it is irrelevant to these rows. Returns exit code plus merged output.
        function Invoke-Gate {
            param([string]$WorkflowPath, [string]$PathOverride)
            $saved = $env:PATH
            try {
                if ($PathOverride) { $env:PATH = $PathOverride }
                $out = & pwsh -NoProfile -File $script:Gate -WorkflowPath $WorkflowPath 2>&1
                [pscustomobject]@{ ExitCode = $LASTEXITCODE; Out = ($out | Out-String) }
            } finally { $env:PATH = $saved }
        }

        # A copy of the real workflow that a test then damages in one specific way.
        function New-WorkflowFixture {
            param([scriptblock]$Mutate)
            $p = Join-Path ([IO.Path]::GetTempPath()) ("cifc-" + [guid]::NewGuid().ToString('N') + '.yml')
            [void]$script:Fixtures.Add($p)
            $lines = [string[]](Get-Content -LiteralPath $script:Real)
            [IO.File]::WriteAllLines($p, (& $Mutate $lines))
            $p
        }

        # yq is the gate's parser AND this suite's oracle, on purpose - if they ever disagree about a
        # document, one of them is wrong and a row here will say so.
        function Test-YamlValid { param([string]$Path) $null = & yq -e '.on.push.paths | length' $Path 2>&1; return ($LASTEXITCODE -eq 0) }
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

        # NON-VACUITY, AND IT MATTERS MORE SINCE THE GATE'S OTHER HALF WAS DELETED. Every other row here
        # asserts a FAILURE, so only this one proves the pass means something. MEASURED: with $Required
        # emptied the gate exits 0 announcing "all 0 required entries present", and this row is the only
        # thing that reds. A capstone round called it a fossil; it is the opposite.
        It 'reports a non-zero count of required entries, and both trigger counts, on the pass line' {
            $r = Invoke-Gate -WorkflowPath $script:Real
            $r.Out | Should -Match 'all (\d+) required entries present under both triggers'
            [int]($r.Out | Select-String -Pattern 'all (\d+) required entries').Matches[0].Groups[1].Value |
                Should -BeGreaterThan 0
            $r.Out | Should -Match 'push=(\d+), pull_request=(\d+)'
        }
    }

    Context 'required entries' {
        # THE DEFECT THIS GATE WAS BUILT FOR. Nothing previously noticed that a plugin tree the suite
        # asserts against was absent from the filter.
        It 'reds when a required entry is missing from BOTH triggers' {
            $p = New-WorkflowFixture { param($l) $l | Where-Object { $_ -notmatch "clavity-dotnet/plugin/\*\*" } }
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match "MISSING required entry 'clavity-dotnet/plugin/\*\*' from: push, pull_request"
        }

        # THE TWO TRIGGERS ARE A PAIR AND NOTHING ELSE CHECKS THEM. Adding an entry to `push` and
        # forgetting `pull_request` yields a filter that is right on merge and wrong on every PR - the half
        # that actually gates review. The message NAMES the trigger; the old one said "block(s) 1", which
        # made the reader count blocks in the file to learn whether merge or PR was affected.
        It 'reds when a required entry is missing from ONE trigger, and NAMES it' {
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
            # ONE PATTERN, NOT TWO: asserting the entry and the trigger as separate matches over multi-line
            # output would pass while the gate named the WRONG trigger.
            $r.Out | Should -Match "MISSING required entry 'build/members\.json' from: push -"
        }

        # GitHub matches paths: CASE-SENSITIVELY; PowerShell's -notcontains does not. A capitalised entry
        # would satisfy a case-insensitive gate while GitHub silently never fired the workflow. This row
        # dies if the operator loses its `-c`.
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

    Context 'legal YAML the gate must ACCEPT' {
        # EVERY SHAPE HERE WAS A REAL FAIL-CLOSED DEFECT while the gate parsed with regexes - six
        # consecutive capstone rounds, one parser defect each. They are kept as end-to-end rows because
        # "the gate blocks a legal edit" is the failure mode that actually cost pushes, and because each
        # one is a document `yq` accepts: the row asserts the ORACLE and the GATE agree.
        It 'ACCEPTS <Name>' -ForEach @(
            @{ Name = 'a YAML anchor and a trailing comment on the paths: key'
               Mut  = { param($l) $seen = $false; $l | ForEach-Object {
                          if (-not $seen -and $_ -match '^(\s*)paths:\s*$') { $seen = $true; "$($Matches[1])paths: &shared   # the push filter" } else { $_ } } } }
            @{ Name = 'an UNQUOTED list item'
               Mut  = { param($l) $l | ForEach-Object { if ($_ -match "^(\s*)- 'justfile'\s*$") { "$($Matches[1])- justfile" } else { $_ } } } }
            @{ Name = 'a trailing comment on the on: key'
               Mut  = { param($l) $l | ForEach-Object { if ($_ -match '^on:\s*$') { 'on: # the triggers' } else { $_ } } } }
            @{ Name = 'a paths:-shaped line inside a block scalar body'
               Mut  = { param($l) $o = New-Object System.Collections.ArrayList
                        foreach ($line in $l) { [void]$o.Add($line)
                          if ($line -match '^on:\s*$') {
                            [void]$o.Add('  workflow_dispatch:'); [void]$o.Add('    inputs:')
                            [void]$o.Add('      test_dir:'); [void]$o.Add('        description: |')
                            [void]$o.Add('          paths: # comma separated list') } }
                        $o } }
            @{ Name = 'a tab AFTER the first non-space character of a scalar body line'
               Mut  = { param($l) $tab = [string][char]9; $o = New-Object System.Collections.ArrayList; $done = $false
                        foreach ($line in $l) { [void]$o.Add($line)
                          if (-not $done -and $line -match '^(\s*)\S.*:\s*\|\s*$') {
                            [void]$o.Add((' ' * ($Matches[1].Length + 2)) + 'echo' + $tab + 'aligned'); $done = $true } }
                        $o } }
        ) {
            $p = New-WorkflowFixture $Mut
            Test-YamlValid $p | Should -BeTrue -Because 'the fixture must be a document yq accepts, or the row tests nothing'
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 0 -Because "yq accepts this document, so the gate must too: $($r.Out)"
        }
    }

    Context 'refuses to run rather than guess' {
        # A GATE THAT CANNOT PARSE ITS INPUT MUST SAY SO, not pass. The regexes used to answer confidently
        # on documents GitHub cannot read; yq's own error is now surfaced instead.
        It 'reds on a workflow yq cannot parse, and surfaces its error' {
            $tab = [string][char]9
            $p = New-WorkflowFixture { param($l) $l | ForEach-Object { if ($_ -match "^\s+-\s*'") { $tab + $_.TrimStart() } else { $_ } } }
            Test-YamlValid $p | Should -BeFalse -Because 'tab indentation is invalid YAML - the fixture must really be broken'
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match 'could not read `\.on\.push\.paths`'
        }

        It 'reds when a trigger is absent rather than assuming an empty filter' {
            $p = New-WorkflowFixture { param($l) $l | ForEach-Object { if ($_ -match '^on:\s*$') { 'jobs-not-on:' } else { $_ } } }
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match 'could not read `\.on\.push\.paths`'
        }

        # AN EXPLICITLY EMPTY LIST, which shares a branch with the two rows above and is asserted on the
        # SAME message rather than an OR. An earlier version asserted 'parsed as EMPTY|could not read',
        # which could not tell which guard fired - and a mutation disabling the empty-count guard left it
        # GREEN, because the yq-error branch caught the fixture anyway. That is how the empty-count branch
        # was found to be unreachable and deleted: MEASURED, `paths: []` exits 1 under `yq -e`.
        It 'reds when a trigger lists no paths at all' {
            $p = New-WorkflowFixture {
                param($l)
                $seen = $false
                $l | ForEach-Object {
                    if (-not $seen -and $_ -match '^(\s*)paths:\s*$') { $seen = $true; "$($Matches[1])paths: []" } else { $_ }
                }
            }
            Test-YamlValid $p | Should -BeFalse -Because 'yq -e reports no matches for an empty list, which is what the gate relies on'
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match 'could not read `\.on\.push\.paths`'
            $r.Out | Should -Match 'lists no paths' -Because 'the message must name this cause among the ones it covers'
        }

        # THE SECOND TRIGGER HAD NO ROW (AGY-TEST-AUDIT round B, GAP-1). Every parser-error row above
        # mutates the FIRST `paths:` block - note the `-not $seen` guard, which is what makes them
        # push-only - so the loop's error handler was proven for `push` and never for `pull_request`.
        # Narrowing the guard to `if (-not $r.Ok -and $trigger -eq 'push')` therefore shipped green.
        # The cost is DIAGNOSABILITY, not a silent pass: an unreadable pull_request trigger yields an
        # empty filter list, every required entry is then reported missing, and the gate still exits 1 -
        # but it blames twelve absent entries instead of naming the one unparseable trigger.
        It 'reds naming the PULL_REQUEST trigger when it is the one that cannot be read' {
            # THE FIXTURE MUST LEAVE THE DOCUMENT **VALID**, and the first draft did not - which is the
            # whole difficulty of this row. Mirroring the rows above (`paths:` -> `paths: []`) orphans the
            # `- entry` lines beneath it, so the WHOLE FILE stops parsing; yq then fails on `.on.push.paths`
            # first and the gate reports PUSH. MEASURED: `yaml: line 68: did not find expected key`, and the
            # row failed at baseline asserting a pull_request message that could never appear.
            # A parse error can therefore NEVER single out the second trigger. The only way to make
            # pull_request the failing one is a document that parses and simply has no `.on.pull_request.paths`
            # key - so remove the key AND its entries, and leave a valid sibling behind.
            $p = New-WorkflowFixture {
                param($l)
                $n = 0; $dropping = $false
                $l | ForEach-Object {
                    if ($_ -match '^(\s*)paths:\s*$') {
                        $n++
                        if ($n -eq 2) { $dropping = $true; "$($Matches[1])branches: [main]" } else { $dropping = $false; $_ }
                    }
                    elseif ($dropping -and $_ -match '^\s*-\s') { }          # swallow this block's entries
                    else { $dropping = $false; $_ }
                }
            }
            Test-YamlValid $p | Should -BeTrue -Because 'this fixture must PARSE - an invalid document fails on push first and never reaches the pull_request branch, which is exactly how the first draft of this row fooled itself'
            $r = Invoke-Gate -WorkflowPath $p
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match 'could not read `\.on\.pull_request\.paths`' -Because 'the message must name the trigger that actually failed, or the operator repairs the wrong block'
            $r.Out | Should -Not -Match 'MISSING required entry' -Because 'a parser failure must abort BEFORE the coverage comparison; reporting twelve missing entries would send the operator hunting for filter rows that are all present'
        }

        It 'reds when the workflow is absent' {
            $r = Invoke-Gate -WorkflowPath (Join-Path ([IO.Path]::GetTempPath()) 'no-such-workflow.yml')
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match 'workflow not found'
        }

        # THE FAIL-OPEN THIS DESIGN COULD HAVE INTRODUCED. The gate now depends on an external binary, so
        # the one thing it must never do is treat a missing yq as "nothing to check". yq is NOT on the
        # GitHub windows-latest image (measured against the runner-images manifest: it lists jq, not yq),
        # so this is a live configuration, not a hypothetical - ci-scripts.yml installs it explicitly.
        It 'reds when yq is not on PATH, instead of skipping the check' {
            $pwshDir = Split-Path -Parent (Get-Command pwsh).Source
            $r = Invoke-Gate -WorkflowPath $script:Real -PathOverride $pwshDir
            $r.ExitCode | Should -Be 1
            $r.Out | Should -Match '`yq` is not on PATH'
            $r.Out | Should -Match 'skipping the check is not an option|cannot run without it'
        }
    }
}

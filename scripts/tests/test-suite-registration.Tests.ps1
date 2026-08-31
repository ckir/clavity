# Every Pester suite IN scripts/tests/ must be registered in exactly one half of the fast/slow partition.
#
# THE SCOPE IS scripts/tests/ ONLY. A suite anywhere else in the repository is invisible to this guard,
# and a review has already found one running in no gate at all. Do not read a green result here as
# "every suite in the repo is gated". Widening the scope is a decision about other products' suites,
# not a fold.
#
# WHY THIS EXISTS. Registration is an EXPLICIT LIST in the justfile, not a glob. `just test-scripts` does
# glob scripts/tests and so reports an unregistered suite green - but neither gate anyone actually runs
# (`test-scripts-fast` in the inner loop, `test-scripts-slow` before a release) would execute it. A new
# suite that nobody adds to a list therefore EXISTS, PASSES, AND NEVER RUNS, and the only thing that ever
# caught this was a hand-run `diff` documented in _partition.md - search that file for the literal
# `diff <(ls scripts/tests` rather than trusting a line number, which has moved twice (53 when the
# comment was written, 89 now). An earlier fix anchored this to "the heading that describes it"; that
# was worse, because _partition.md has exactly ONE `##` heading and it is not this one.
#
# WHAT IS ACTUALLY ENFORCED HERE, said precisely because the previous wording ("that oracle is now
# enforced here") claimed the whole of it: this suite pins that every file on disk appears in a recipe and
# every recipe entry exists. The hand-oracle in _partition.md is still stronger in ways this is not - it
# compares the two halves as SETS, so it also catches a suite listed in BOTH halves or listed twice within
# one, which the per-recipe dedupe here cannot see. Run the hand-oracle before a release; this row is the
# floor, not the ceiling.
#
# This suite cannot protect ITSELF - if it were the unregistered one it would not run to complain. That
# one-time cost is paid by registering it in the same commit that adds it.
#
# It asserts MEMBERSHIP, not correct placement: putting a 90-second suite in the fast half passes here.
# The fast/slow split is a measured judgement recorded in _partition.md, not something a grep can settle.

Describe 'test suite registration' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Justfile = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'justfile') -Raw

        # TWO FILTERS, BOTH LOAD-BEARING: read each recipe's OWN body, and strip COMMENTS from it. A
        # suite named in a comment inside a recipe - the natural way to note why one was retired -
        # otherwise reads as registered while `just` never runs it. Strip from `#` to end of line, which
        # covers a whole-line comment and a trailing one with one expression; handling only whole-line
        # comments left the trailing case wide open.
        #
        # THREE COMMENT FORMS, each found by a different round. A `<# ... #>` PAIR goes first: that is
        # how a suite gets disabled inside the `pwsh -c` string, and this repo has already had a text
        # guard defeated by exactly that syntax. An UNCLOSED `<#` then strips to end of line. Last, a
        # WHITESPACE-PRECEDED `#` - the shell's own rule - and deliberately NOT every `#`, because
        # stripping the suffix off `'scripts/tests/foo.Tests.ps1#bak'` certified a suite Invoke-Pester
        # silently skips.
        #
        # THE PAIR MUST BE REMOVED AS A PAIR. Treating `<#` as "strip to end of line" also deletes the
        # real suites AFTER an inline block comment - measured: it dropped a still-registered suite,
        # trading a false pass for a false failure. Both suffix rules below exclude `#`.
        function Get-RecipeSuites {
            param([string]$Recipe)
            $m = [regex]::Match($script:Justfile, "(?m)^$([regex]::Escape($Recipe)):\r?\n(?<body>(?:[ \t]+.*\r?\n?|[ \t]*\r?\n)+)")
            if (-not $m.Success) { return @() }
            $body = ($m.Groups['body'].Value -split "`n" | ForEach-Object {
                ($_ -replace '<#.*?#>', '') -replace '(^|\s)<#.*$', '' -replace '(^|\s)#.*$', ''
            }) -join "`n"
            # THE TRAILING LOOKAHEAD IS LOAD-BEARING. Without it, a recipe entry naming a disabled
            # path (`foo.Tests.ps1.bak`) still captures `foo.Tests.ps1`, so the row certifies a suite
            # the recipe never runs. It also keeps this parse and the census parse in agreement.
            # ANY directory prefix, not a hardcoded `scripts/tests/`. That literal was the THIRD place the
            # 50th-suite blind spot lived (with the population and the runtimes table): a recipe naming
            # `clavity-dotnet/install/clavity-install.Tests.ps1` matched nothing here, so a suite that IS
            # registered read as unregistered the moment the population was widened to see it. The NAME
            # group still forbids a separator - the leaf is what every comparison keys on.
            @([regex]::Matches($body, "[A-Za-z0-9._/-]+/(?<n>[A-Za-z0-9._-]+\.Tests\.ps1)(?![A-Za-z0-9._#-])") |
                ForEach-Object { $_.Groups['n'].Value } | Sort-Object -Unique)
        }

        $script:Fast = Get-RecipeSuites 'test-scripts-fast'
        $script:Slow = Get-RecipeSuites 'test-scripts-slow'
        # RECURSIVE, and relative to this directory - identical to the file name under today's flat
        # layout. Non-recursive, a nested suite would fail the flat-layout row while these rows, blind
        # to the same file, still reported GREEN: Pester does not stop a Describe on a failed It, so one
        # run would announce the violation and certify the registration. A suite this file cannot see
        # must never be a suite it certifies.
        # THE POPULATION IS EVERY TRACKED SUITE IN THE REPOSITORY, NOT JUST THIS DIRECTORY.
        # It was `Get-ChildItem $PSScriptRoot` until 2026-08-27, and that blind spot cost two defects:
        # `clavity-dotnet/install/clavity-install.Tests.ps1` is named by `test-scripts-slow` and runs in
        # CI, but sat outside this glob - so it carried NO `_partition.md` row and nothing noticed, and
        # AGY-CAPSTONE round 27 found the same file missing from that table independently.
        #
        # `git ls-files` rather than a recursive walk, DELIBERATELY. A repo-wide `**/*.Tests.ps1` crosses
        # into `clavity-classic/target` and `ghidrust/target` - MEASURED, 46,991 files on disk against 620
        # tracked, 36,205 of them in those two trees. Tracking is the bound; a glob is not.
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:AllSuitePaths = @(
            & git -C $script:RepoRoot ls-files '*.Tests.ps1' |
                Where-Object { $_ } |
                ForEach-Object { Join-Path $script:RepoRoot ($_ -replace '/', '\') }
        )
        $script:OnDisk = @($script:AllSuitePaths | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object)
    }

    It 'parsed a plausible population out of both partition recipes' {
        # THIS ROW NAMES THE CAUSE. It does not stop a false clean and suppresses nothing: MEASURED by
        # making the parse return nothing, the registration row reds too, and Pester runs every row
        # regardless, so the reader sees BOTH. The value is that one of them says "the parse broke"
        # rather than listing every suite on disk as unregistered, which sends someone hunting through
        # the justfile for a problem that is not there.
        #
        # The threshold is a PLAUSIBILITY floor, not an emptiness check: a half-broken parse is the
        # likelier failure, and four names is as wrong as none.
        $script:Fast.Count | Should -BeGreaterThan 5 -Because 'far too few suites parsed out of test-scripts-fast - the recipe parse is broken, not the gate empty'
        $script:Slow.Count | Should -BeGreaterThan 5 -Because 'far too few suites parsed out of test-scripts-slow - the recipe parse is broken, not the gate empty'
    }

    It 'sees every suite in scripts/tests - the FLAT layout all three parses here assume' {
        # A NESTED SUITE CANNOT BE REGISTERED HERE, SO IT IS STOPPED RATHER THAN TOLERATED. The recipe
        # regex forbids a directory separator and the runtimes table is a flat list of names, so no
        # edit to those files could gate it - while CI's `Invoke-Pester scripts/tests` would run it
        # anyway. `fixtures/` is fine: it holds data, not suites.
        $all = @(Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File -Filter '*.Tests.ps1')
        $all.Count | Should -BeGreaterThan 20 -Because 'a recursive enumeration that found almost nothing means the walk broke, not that the directory is empty'

        $nested = @($all | Where-Object { $_.DirectoryName -ne $PSScriptRoot } |
            ForEach-Object { $_.FullName.Substring($PSScriptRoot.Length + 1) })
        $nested -join ', ' | Should -BeExactly '' -Because 'a nested suite can never be MATCHED to a registration or a table row: Get-RecipeSuites forbids a directory separator and the runtimes table is a flat list of file names - to allow one, both must learn about paths first'
    }

    It 'registers every TRACKED suite in the repository in the fast or slow gate' {
        $registered = @($script:Fast + $script:Slow | Sort-Object -Unique)
        $unregistered = @($script:OnDisk | Where-Object { $_ -notin $registered })
        # Name them, AND name the file to edit. A count sends a reader hunting; a name sends them to the
        # file. Whoever trips this is usually adding their first suite and has no idea what governs the
        # gate - being told "it is missing" without being told WHERE is how a gate teaches people to
        # distrust it.
        $unregistered -join ', ' | Should -BeExactly '' -Because 'a suite in neither gate exists, passes under `just test-scripts`, and never runs in the gates anyone uses - add it to test-scripts-fast or test-scripts-slow in the repo-root justfile'
    }

    It 'names no suite that is missing from disk' {
        $registered = @($script:Fast + $script:Slow | Sort-Object -Unique)
        $phantom = @($registered | Where-Object { $_ -notin $script:OnDisk })
        # Invoke-Pester is not an error on a path that does not exist, so a renamed-but-not-updated entry
        # silently drops that suite from the gate rather than failing it.
        $phantom -join ', ' | Should -BeExactly '' -Because 'a recipe naming a file that does not exist silently shrinks the gate - fix or remove the entry in the repo-root justfile'
    }

    It 'puts each suite in exactly ONE half of the partition' {
        $both = @($script:Fast | Where-Object { $_ -in $script:Slow })
        $both -join ', ' | Should -BeExactly '' -Because 'fast and slow are a partition; a suite in both is paid for twice and its measured timing is wrong - remove it from one recipe in the repo-root justfile'
    }

    It 'the _partition.md runtimes table is a complete census of every TRACKED suite' {
        # The table claims to be the suite set, so something must hold it to that - it had silently
        # drifted to three missing rows. Same shape as `scripts-readme-inventory.Tests.ps1`.
        # It asserts PRESENCE OF A ROW, never that the figure is current: a time cannot be verified by
        # reading it, and _partition.md calls its own figures indicative.
        $partition = Join-Path $PSScriptRoot '_partition.md'
        Test-Path -LiteralPath $partition | Should -BeTrue -Because 'the partition record must exist for this row to mean anything'
        $lines = @(Get-Content -LiteralPath $partition)

        # Scope to the fenced block under the heading. The file names suites in prose all over, so an
        # unscoped grep would count a suite as present because a paragraph happened to mention it.
        $h = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^##\s+Measured runtimes') { $h = $i; break }
        }
        $h | Should -BeGreaterThan -1 -Because 'the Measured runtimes heading must be findable, or this row silently checks nothing'

        $fences = @(for ($i = $h + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^```') { $i } })
        $fences.Count | Should -BeGreaterThan 1 -Because 'the table must be a fenced block with an opening and a closing fence'

        $inTable = @(@(for ($i = $fences[0] + 1; $i -lt $fences[1]; $i++) {
            # SAME SUFFIX RULE AS Get-RecipeSuites, deliberately. Requiring whitespace here rejected a
            # row ending exactly at `.ps1` that the other parse accepted, so the two could disagree
            # about the same fact - and the row then told a maintainer to add the row they had added.
            $m = [regex]::Match($lines[$i], '^([A-Za-z0-9._-]+\.Tests\.ps1)(?![A-Za-z0-9._#-])')
            if ($m.Success) { $m.Groups[1].Value }
        }) | Sort-Object -Unique)

        # Non-vacuity, and it is NOT the false-clean guard it used to claim to be: MEASURED, an empty
        # parse makes the first comparison list every suite on disk and red loudly. What it catches is
        # the QUIETER half - a parse that returns a few rows, where the second comparison then reports
        # phantom entries that are really just parse damage. Same correction as row 1's; this copy was
        # missed when that one was fixed.
        $inTable.Count | Should -BeGreaterThan 20 -Because 'a table parse that found almost no rows means the parse broke, not that the table is empty'

        @($script:OnDisk | Where-Object { $_ -notin $inTable }) -join ', ' |
            Should -BeExactly '' -Because 'a suite with no row is invisible to anyone reading that table to decide what the gate costs - measure it and add a row to the Measured runtimes table in scripts/tests/_partition.md, starting with the BARE file name as every existing row does, not a path'
        @($inTable | Where-Object { $_ -notin $script:OnDisk }) -join ', ' |
            Should -BeExactly '' -Because 'a row for a suite that no longer exists is a figure nobody can ever re-measure - remove it from the Measured runtimes table in scripts/tests/_partition.md'
    }

    It 'every _partition.md row states the CURRENT test count for its suite' {
        # THE ROW ABOVE ASSERTS PRESENCE, NOT ACCURACY, and says so: "a time cannot be verified by
        # reading it". That reasoning is right for the TIME and wrong for the COUNT, which is exactly
        # what Pester can be asked. MEASURED 2026-08-24 before this row existed: 14 of 49 counted rows
        # disagreed with reality, several by a lot - check-agy-discipline-skills said 14 against 39,
        # plugin-hooks-registration 22 against 33, BashHookHelpers 4 against 8. A row is what a
        # maintainer reads to judge what a gate costs and whether a suite still earns its half of the
        # partition; one understating by half is worse than no row.
        #
        # COST, measured on an IDLE machine - and measured twice, because the first figure recorded
        # here was wrong in a way worth keeping visible.
        #   Pester DISCOVERY over all 49 suites alone: ~13,5s (marginal ~0,15s per suite; the rest is
        #     fixed Pester startup, which is why a linear extrapolation from 3 suites gave "about two
        #     minutes" and was wrong by ~5x - the derived-total error ## Measured runtimes warns about).
        #   THIS It end to end: **20,9s warm, 23,2s cold**. The gap is the child pwsh launch, the temp
        #     script write, and parsing 49 rows - none of which the discovery figure includes.
        # The 13,5s number was quoted here as if it were this It's cost. It is not, and the difference
        # matters: this It is ~95% of its own suite's runtime. Do not re-derive either figure; measure,
        # backgrounded and idle, and take the SECOND of two consecutive runs as the warm one.
        #
        # DISCOVERY RUNS IN A CHILD PROCESS on purpose. Invoking Pester inside a Pester test shares
        # module-level run state with the outer run; a separate process cannot disturb it, and the
        # process launch is a small fraction of the discovery cost being paid anyway.
        $childScript = @'
$ErrorActionPreference = "Stop"
# -LiteralPath: positional binds -Path, which interprets wildcards, so a clone under a directory
# containing [ or ] returned an EMPTY set - which this guard would have reported as "the child process
# failed", sending the reader to the child instead of to the bracket in their path.
# EXPLICIT FILE PATHS, not a directory: the population spans more than one directory since 2026-08-27.
$files = @($args)
$c = New-PesterConfiguration
$c.Run.Path = $files
$c.Run.SkipRun = $true
$c.Run.PassThru = $true
$c.Output.Verbosity = "None"
$r = Invoke-Pester -Configuration $c
# SEED EVERY CONTAINER AT ZERO FIRST. Counting only from $r.Tests means a suite that discovers NO
# tests never appears in the output at all, and the parent then skips it as "absent" - so a suite
# whose discovery broke, or which lost its last It, was silently exempted from the whole check while
# the child still exited 0.
$counts = @{}
foreach ($cont in $r.Containers) { $counts[(Split-Path $cont.Item -Leaf)] = 0 }
foreach ($t in $r.Tests) {
    $leaf = Split-Path $t.ScriptBlock.File -Leaf
    if (-not $counts.ContainsKey($leaf)) { $counts[$leaf] = 0 }
    $counts[$leaf]++
}
# Emit the container RESULT too: the child exits 0 even when a container failed to discover, so the
# result is the only channel by which that reaches the parent.
foreach ($cont in $r.Containers) {
    $leaf = Split-Path $cont.Item -Leaf
    "COUNT`t$leaf`t$($counts[$leaf])`t$($cont.Result)"
}
'@
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("pester-discover-" + [Guid]::NewGuid().ToString('N') + ".ps1")
        Set-Content -LiteralPath $tmp -Value $childScript -Encoding utf8
        try {
            $raw = & pwsh -NoProfile -File $tmp @script:AllSuitePaths 2>&1
        } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }

        $discovered = @{}
        $badContainers = @()
        foreach ($line in $raw) {
            $parts = "$line" -split "`t"
            if ($parts.Count -eq 4 -and $parts[0] -eq 'COUNT') {
                $discovered[$parts[1]] = [int]$parts[2]
                # NotRun is the CORRECT state under Run.SkipRun - no It body executed. Only Failed
                 # means the container could not be discovered. Asserting -ne 'Passed' reds all 49.
                if ($parts[3] -eq 'Failed') { $badContainers += "$($parts[1]) [$($parts[3])]" }
            }
        }
        # A container that failed to DISCOVER is not a count problem, it is a broken suite - and the
        # child exits 0 regardless, so without this it reaches nothing.
        ($badContainers -join '; ') | Should -BeNullOrEmpty -Because 'a suite whose discovery failed cannot have its count checked, and a broken suite must not pass quietly'

        # NON-VACUITY, tied to what is actually on disk rather than to a slack constant. The previous
        # floor was `-BeGreaterThan 20` against 49 suites: 28 could vanish and it still passed.
        $onDiskCount = $script:AllSuitePaths.Count
        $onDiskCount | Should -BeGreaterThan 20 -Because 'the suite directory itself must be non-empty, or every count below is compared against nothing'
        $discovered.Count | Should -Be $onDiskCount -Because "discovery reported $($discovered.Count) containers for $onDiskCount files on disk - a partial or truncated child result must not read as success"

        $partition = Join-Path $PSScriptRoot '_partition.md'
        $lines = @(Get-Content -LiteralPath $partition)

        # SCOPE TO THE FENCED TABLE, exactly as the census row above does and for exactly the reason it
        # states: this file names suites in prose all over. An unscoped, first-match-wins parse lets a
        # sentence ANYWHERE in the document shadow the real row - MEASURED, a prose line inserted 77
        # lines above the fence supplied the count and the real row was never compared at all.
        $h = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^##\s+Measured runtimes') { $h = $i; break }
        }
        $h | Should -BeGreaterThan -1 -Because 'the Measured runtimes heading must be findable, or this row silently checks nothing'
        $tableFences = @(for ($i = $h + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^```') { $i } })
        $tableFences.Count | Should -BeGreaterThan 1 -Because 'the table must be a fenced block with an opening and a closing fence'

        $stated = @{}
        $dupeRows = @()
        foreach ($l in $lines[($tableFences[0] + 1)..($tableFences[1] - 1)]) {
            # The time field is \S+, NOT a number: two rows record their time as `?` (never measured),
            # and a numeric-only pattern silently EXEMPTED both from this check - a guard failing open
            # on exactly the rows least likely to be maintained. MEASURED when this was tightened:
            # of the two exempt rows, test-suite-registration said 4 against an actual 8, and
            # agy-drive-session-reset was correct at 6 - so the exemption was hiding real drift in one
            # of the only two rows it covered.
            # `tests?` accepts the SINGULAR. A one-It suite is naturally written `1 test`, and
            # under the tightened contract below that spelling is not a silent exemption but a
            # hard RED claiming the table is incomplete when the row is present and correct.
            $m = [regex]::Match($l, '^([A-Za-z0-9._-]+\.Tests\.ps1)\s+\S+\s+([0-9]+)\s+tests?')
            if (-not $m.Success) { continue }
            # A SECOND row for one suite is silent under first-match-wins: whichever copy loses is never
            # compared, so a stale duplicate can sit in the table indefinitely.
            if ($stated.ContainsKey($m.Groups[1].Value)) { $dupeRows += $m.Groups[1].Value; continue }
            $stated[$m.Groups[1].Value] = [int]$m.Groups[2].Value
        }
        ($dupeRows -join '; ') | Should -BeNullOrEmpty -Because 'a suite with two counted rows leaves one of them permanently unchecked - delete the stale copy'
        # EVERY suite must state a count, tied to what is on disk rather than to a slack constant.
        # Framing this as "only rows that make a claim are bound" was an EXEMPTION, and exemptions are
        # where this guard keeps failing open: MEASURED, mangling one row's count text to `~1 tests`
        # dropped it from $stated entirely, so it escaped BOTH $drift and $unreported while the census
        # row still saw the row present and passed. `8 Tests`, `eight tests` and `8 assertions` evade
        # identically. The fix was already written ~40 lines above for $discovered, in a comment that
        # condemns this exact `-BeGreaterThan 20` pattern - and was then not applied here.
        # NAMED, not counted - the rule this file states twice ("Name them, AND name the file to
        # edit. A count sends a reader hunting; a name sends them to the file.") and did not apply to
        # its own newest guard. Naming subsumes the cardinality check: an on-disk suite with no counted
        # row is the only way the counts differ downward, and a phantom row reds the census row above.
        # foreach here is a style choice, matching the two sibling scans below. An earlier comment
        # claimed a Where-Object scriptblock cannot see this It's local $stated; that was FALSE and is
        # retracted - measured, both forms resolve it, and :156 in this same file relies on exactly
        # that with an It-local $inTable. The real cause of the all-49 misfire it was written to
        # explain was a stray control character in the row regex, not scoping.
        $noCountRow = foreach ($f in $script:OnDisk) { if (-not $stated.ContainsKey($f)) { $f } }
        ($noCountRow -join '; ') | Should -BeNullOrEmpty -Because 'every suite must have a row stating a parseable count in the Measured runtimes table in scripts/tests/_partition.md'

        # NO SILENT SKIP. This used to `continue` past any row whose suite was absent from the child's
        # output, on the reasoning that the census row owns absence. That is wrong: the census row
        # asserts a ROW EXISTS FOR EVERY FILE, never that the file produced tests - so a suite that
        # discovered nothing fell through both assertions and was checked by neither.
        $unreported = foreach ($k in ($stated.Keys | Sort-Object)) {
            if (-not $discovered.ContainsKey($k)) { $k }
        }
        ($unreported -join '; ') | Should -BeNullOrEmpty -Because 'a counted row whose suite discovery never reported it is unchecked by this row AND by the census row above - neither owns it'

        $drift = foreach ($k in ($stated.Keys | Sort-Object)) {
            if (-not $discovered.ContainsKey($k)) { continue }   # already reported as unreported above
            if ($discovered[$k] -ne $stated[$k]) { "$k says $($stated[$k]) but discovers $($discovered[$k])" }
        }
        # Named, not counted: a count sends a reader hunting, a name sends them to the row to edit.
        ($drift -join '; ') | Should -BeNullOrEmpty -Because 'a stale count misstates what the gate costs - re-measure and correct the row in the Measured runtimes table in scripts/tests/_partition.md'
    }

    It 'registers the clavity-install suite by PATH, and that path exists' {
        # NARROW BY DESIGN. The parses above are scoped to scripts/tests/ (see the header at :3-6), so
        # this out-of-tree suite is invisible to them - neither certified nor rejected. Widening
        # Get-RecipeSuites would be a decision about other products' suites, not a fold, so this row
        # pins the one entry instead.
        #
        # BOTH HALVES ARE LOAD-BEARING: without the first, the row passes when the entry is deleted;
        # without the second, it passes when the file is renamed.
        $rel = 'clavity-dotnet/install/clavity-install.Tests.ps1'
        $script:Justfile | Should -Match ([regex]::Escape($rel)) -Because 'the suite ran in no gate at all until it was named in a recipe (ROADMAP 14b)'
        Test-Path -LiteralPath (Join-Path $script:RepoRoot $rel) | Should -BeTrue -Because 'a recipe naming a file that does not exist silently shrinks the gate'
    }

    It 'CI asserts that THIS suite itself was discovered' {
        # SELF-GUARDING ORACLE. The equality row in this file proves every other suite was discovered -
        # but only while this file is itself discovered. If this one is misnamed or deleted, its row
        # never runs and CI falls back to `TotalCount -lt 100`, which MEASURED 2026-08-31 tolerates
        # losing ~89% of 982 assertions. So CI must name this suite explicitly, and that naming is what
        # this row pins. Source-text pinning is used because the assertion lives in YAML, where there is
        # no behaviour to call.
        # BEHAVIOURAL, NOT LEXICAL - and it took THREE capstone rounds to get here. Keep the history:
        # R1: grepped the whole file for two strings that also appear in the guard's own COMMENT, so
        #     commenting the guard out left this row green. MEASURED with a mutant.
        # R2: matching only lines not starting with '#' was still lexical - a `<# ... #>` block comment
        #     defeated it, since the lines still start with whitespace.
        # R3: a hand-rolled block-comment stripper missed a block OPENED MID-LINE (`$x = 1 <#`).
        #     MEASURED: guard inside a block comment, row still green.
        # The lesson is that hand-rolled comment detection keeps losing. PowerShell already has a
        # tokenizer that knows every comment form, so ask IT which lines carry live code, then RUN the
        # guard's own source. Tokenize the run BLOCK only - the file is YAML, not PowerShell.
        $wfPath  = Join-Path $script:RepoRoot '.github/workflows/ci-scripts.yml'
        $wfLines = @(Get-Content -LiteralPath $wfPath)

        # Extract the `run: |` block of the full-suite Pester step, by indentation.
        $stepIx = [Array]::FindIndex($wfLines, [Predicate[string]]{ param($l) $l -match '^\s*- name: Pester - full scripts suite' })
        $stepIx | Should -BeGreaterThan -1 -Because 'the full-suite Pester step must exist in ci-scripts.yml, or nothing below is checking anything'
        # BOUND THE SEARCH TO THIS STEP. FindIndex would otherwise run to end-of-file, so if this step
        # ever stopped carrying a `run: |` the extractor would silently adopt a LATER step's block and
        # certify the wrong thing. AGY-CAPSTONE round 4; measured NOT currently reachable (the run: | is
        # 2 lines below the step, the next `- name:` is 15 below) - which is exactly when to fix it.
        $nextStep = [Array]::FindIndex($wfLines, $stepIx + 1, [Predicate[string]]{ param($l) $l -match '^\s*- name:' })
        if ($nextStep -lt 0) { $nextStep = $wfLines.Count }
        $runIx = [Array]::FindIndex($wfLines, $stepIx, [Predicate[string]]{ param($l) $l -match '^\s*run: \|' })
        $runIx | Should -BeGreaterThan -1 -Because 'that step must carry a run: | block'
        $runIx | Should -BeLessThan $nextStep -Because 'the run: | block must belong to the full-suite Pester step itself, not to a later step the search ran on into'
        $indent = ($wfLines[$runIx] -replace '\S.*$', '').Length
        $block = @()
        for ($n = $runIx + 1; $n -lt $wfLines.Count; $n++) {
            $l = $wfLines[$n]
            if ($l.Trim() -eq '') { $block += ''; continue }
            if (($l -replace '\S.*$', '').Length -le $indent) { break }
            $block += $l
        }
        $block.Count | Should -BeGreaterThan 3 -Because 'an empty or truncated run block means this parse broke, not that CI is small'

        # Ask PowerShell which lines carry NON-comment tokens. This is the part that kept being wrong.
        $errs = $null
        $toks = [System.Management.Automation.PSParser]::Tokenize(($block -join "`n"), [ref]$errs)
        $liveLine = @{}
        foreach ($tk in $toks) {
            if ($tk.Type -ne 'Comment' -and $tk.Type -ne 'NewLine') { $liveLine[$tk.StartLine] = $true }
        }
        $live = @(for ($n = 1; $n -le $block.Count; $n++) { if ($liveLine.ContainsKey($n)) { $block[$n - 1] } })

        $assign = @($live | Where-Object { $_ -match '\$oracle = @\(\$r\.Containers' })
        $throwL = @($live | Where-Object { $_ -match 'if \(\$oracle\.Count -ne 1\)' })
        $assign.Count | Should -Be 1 -Because 'ci-scripts.yml must ASSIGN $oracle on a line PowerShell itself considers live code - in any comment syntax'
        $throwL.Count | Should -Be 1 -Because 'ci-scripts.yml must THROW when the oracle did not run, on a line PowerShell considers live code'

        # Now RUN the guard's own source. $r is read from this scope by the scriptblock. A text match
        # cannot see `-ne 2` or an inverted test; this can.
        $guard = [scriptblock]::Create(($assign[0] + "`n" + $throwL[0]))
        $r = [pscustomobject]@{ Containers = @([pscustomobject]@{ Item = 'scripts/tests/other.Tests.ps1' }) }
        { & $guard } | Should -Throw -Because 'the guard must THROW when the registration oracle is absent from the run - that is the entire point of it'
        $r = [pscustomobject]@{ Containers = @([pscustomobject]@{ Item = 'scripts/tests/test-suite-registration.Tests.ps1' }) }
        { & $guard } | Should -Not -Throw -Because 'the guard must stay silent on a healthy run, or it is a false alarm rather than a gate'

        # The rationale comment is still required, separately: without it a later reader deletes the
        # guard as redundant. Asserted on raw text because a comment is exactly what this one is.
        (Get-Content -LiteralPath $wfPath -Raw) |
            Should -Match 'registration oracle' -Because 'the guard must say WHY it exists, or a later reader will delete it as redundant'
    }
}

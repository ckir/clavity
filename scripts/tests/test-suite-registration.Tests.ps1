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
# caught this was a hand-run `diff` documented in _partition.md:53-54 that no test invoked. That oracle is
# now enforced here.
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
            @([regex]::Matches($body, "scripts/tests/(?<n>[A-Za-z0-9._-]+\.Tests\.ps1)(?![A-Za-z0-9._#-])") |
                ForEach-Object { $_.Groups['n'].Value } | Sort-Object -Unique)
        }

        $script:Fast = Get-RecipeSuites 'test-scripts-fast'
        $script:Slow = Get-RecipeSuites 'test-scripts-slow'
        # RECURSIVE, and relative to this directory - identical to the file name under today's flat
        # layout. Non-recursive, a nested suite would fail the flat-layout row while these rows, blind
        # to the same file, still reported GREEN: Pester does not stop a Describe on a failed It, so one
        # run would announce the violation and certify the registration. A suite this file cannot see
        # must never be a suite it certifies.
        $script:OnDisk = @(
            Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File -Filter '*.Tests.ps1' |
                ForEach-Object { $_.FullName.Substring($PSScriptRoot.Length + 1) -replace '\\', '/' } |
                Sort-Object
        )
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

    It 'registers every suite in scripts/tests in the fast or slow gate' {
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

    It 'the _partition.md runtimes table is a complete census of the suites in scripts/tests' {
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
        # what Pester can be asked. MEASURED 2026-08-24 before this row existed: 14 of 47 counted rows
        # disagreed with reality, several by a lot - check-agy-discipline-skills said 14 against 39,
        # plugin-hooks-registration 22 against 33, BashHookHelpers 4 against 8. A row is what a
        # maintainer reads to judge what a gate costs and whether a suite still earns its half of the
        # partition; one understating by half is worse than no row.
        #
        # COST, measured rather than extrapolated: discovery over all 49 suites is ~13,5s, of which
        # almost all is fixed Pester startup - the marginal cost is ~0,15s per suite. An earlier attempt
        # to price this scaled the 3-suite figure linearly and got "about two minutes", which is wrong
        # by roughly 5x and is precisely the derived-total error the ## Measured runtimes section warns
        # about. Do not re-derive it; re-measure it.
        #
        # DISCOVERY RUNS IN A CHILD PROCESS on purpose. Invoking Pester inside a Pester test shares
        # module-level run state with the outer run; a separate process cannot disturb it, and the
        # process launch is a small fraction of the discovery cost being paid anyway.
        $childScript = @'
$ErrorActionPreference = "Stop"
$files = @(Get-ChildItem $args[0] -Filter *.Tests.ps1 -File | ForEach-Object { $_.FullName })
$c = New-PesterConfiguration
$c.Run.Path = $files
$c.Run.SkipRun = $true
$c.Run.PassThru = $true
$c.Output.Verbosity = "None"
$r = Invoke-Pester -Configuration $c
$counts = @{}
foreach ($t in $r.Tests) {
    $leaf = Split-Path $t.ScriptBlock.File -Leaf
    if (-not $counts.ContainsKey($leaf)) { $counts[$leaf] = 0 }
    $counts[$leaf]++
}
foreach ($k in $counts.Keys) { "COUNT`t$k`t$($counts[$k])" }
'@
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("pester-discover-" + [Guid]::NewGuid().ToString('N') + ".ps1")
        Set-Content -LiteralPath $tmp -Value $childScript -Encoding utf8
        try {
            $raw = & pwsh -NoProfile -File $tmp $PSScriptRoot 2>&1
        } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }

        $discovered = @{}
        foreach ($line in $raw) {
            $parts = "$line" -split "`t"
            if ($parts.Count -eq 3 -and $parts[0] -eq 'COUNT') { $discovered[$parts[1]] = [int]$parts[2] }
        }
        # NON-VACUITY. A child that failed to launch, or emitted nothing parseable, would otherwise
        # leave $discovered empty and every comparison below would silently find nothing to check.
        $discovered.Count | Should -BeGreaterThan 20 -Because "Pester discovery returned only $($discovered.Count) suites - the child process failed rather than the suites being absent"

        $partition = Join-Path $PSScriptRoot '_partition.md'
        $lines = @(Get-Content -LiteralPath $partition)
        $stated = @{}
        foreach ($l in $lines) {
            # The time field is \S+, NOT a number: two rows record their time as `?` (never measured),
            # and a numeric-only pattern silently EXEMPTED both from this check - a guard failing open
            # on exactly the rows least likely to be maintained. MEASURED when this was tightened:
            # of the two exempt rows, test-suite-registration said 4 against an actual 8, and
            # agy-drive-session-reset was correct at 6 - so the exemption was hiding real drift in one
            # of the only two rows it covered.
            $m = [regex]::Match($l, '^([A-Za-z0-9._-]+\.Tests\.ps1)\s+\S+\s+([0-9]+)\s+tests')
            if ($m.Success -and -not $stated.ContainsKey($m.Groups[1].Value)) {
                $stated[$m.Groups[1].Value] = [int]$m.Groups[2].Value
            }
        }
        # A row that states no count is out of scope here - the census row above already requires the
        # ROW to exist. This assertion only binds rows that make a claim.
        $stated.Count | Should -BeGreaterThan 20 -Because "only $($stated.Count) rows stated a count - the row parse broke, rather than the table being empty"

        $drift = foreach ($k in ($stated.Keys | Sort-Object)) {
            if (-not $discovered.ContainsKey($k)) { continue }   # census row above owns absence
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
}

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

        # TWO FILTERS, BOTH LOAD-BEARING: read each recipe's OWN body, and drop COMMENT lines from it.
        # A suite named in an indented comment inside a recipe - the natural way to note why one was
        # retired - otherwise reads as registered while `just` never runs it.
        function Get-RecipeSuites {
            param([string]$Recipe)
            $m = [regex]::Match($script:Justfile, "(?m)^$([regex]::Escape($Recipe)):\r?\n(?<body>(?:[ \t]+.*\r?\n?)+)")
            if (-not $m.Success) { return @() }
            $body = ($m.Groups['body'].Value -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
            # THE TRAILING LOOKAHEAD IS LOAD-BEARING. Without it, a recipe entry naming a disabled
            # path (`foo.Tests.ps1.bak`) still captures `foo.Tests.ps1`, so the row certifies a suite
            # the recipe never runs. It also keeps this parse and the census parse in agreement.
            @([regex]::Matches($body, "scripts/tests/(?<n>[A-Za-z0-9._-]+\.Tests\.ps1)(?![A-Za-z0-9._-])") |
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

    It 'found both partition recipes and a plausible suite population' {
        # The non-vacuity guard. If the recipe regex ever stops matching, every set below goes empty and a
        # set-difference assertion passes by comparing nothing to nothing - which is precisely the shape of
        # false-clean this repo keeps paying for.
        $script:Fast.Count | Should -BeGreaterThan 5 -Because 'an empty fast list means the recipe parse broke, not that the gate is empty'
        $script:Slow.Count | Should -BeGreaterThan 5 -Because 'an empty slow list means the recipe parse broke'
        $script:OnDisk.Count | Should -BeGreaterThan 20 -Because 'an empty enumeration of scripts/tests would make every comparison below vacuous'
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
            $m = [regex]::Match($lines[$i], '^([A-Za-z0-9._-]+\.Tests\.ps1)\s')
            if ($m.Success) { $m.Groups[1].Value }
        }) | Sort-Object -Unique)

        # Non-vacuity: a parse that found nothing would make both comparisons below pass by comparing
        # nothing to nothing, which is the false-clean shape this repo keeps paying for.
        $inTable.Count | Should -BeGreaterThan 20 -Because 'a table parse that found almost no rows means the parse broke, not that the table is empty'

        @($script:OnDisk | Where-Object { $_ -notin $inTable }) -join ', ' |
            Should -BeExactly '' -Because 'a suite with no row is invisible to anyone reading that table to decide what the gate costs - measure it and add a row to the Measured runtimes table in scripts/tests/_partition.md'
        @($inTable | Where-Object { $_ -notin $script:OnDisk }) -join ', ' |
            Should -BeExactly '' -Because 'a row for a suite that no longer exists is a figure nobody can ever re-measure - remove it from the Measured runtimes table in scripts/tests/_partition.md'
    }
}

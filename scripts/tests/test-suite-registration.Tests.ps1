# Every Pester suite on disk must be registered in exactly one half of the fast/slow partition.
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

        # Read each partition recipe's OWN body rather than grepping the whole justfile: a suite named in
        # a comment, or in the `test-scripts` glob recipe, must not count as registered in a gate.
        function Get-RecipeSuites {
            param([string]$Recipe)
            $m = [regex]::Match($script:Justfile, "(?m)^$([regex]::Escape($Recipe)):\r?\n(?<body>(?:[ \t]+.*\r?\n?)+)")
            if (-not $m.Success) { return @() }
            @([regex]::Matches($m.Groups['body'].Value, "scripts/tests/(?<n>[A-Za-z0-9._-]+\.Tests\.ps1)") |
                ForEach-Object { $_.Groups['n'].Value } | Sort-Object -Unique)
        }

        $script:Fast = Get-RecipeSuites 'test-scripts-fast'
        $script:Slow = Get-RecipeSuites 'test-scripts-slow'
        $script:OnDisk = @(
            Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter '*.Tests.ps1' |
                Select-Object -ExpandProperty Name | Sort-Object
        )
    }

    It 'found both partition recipes and a plausible suite population' {
        # The non-vacuity guard. If the recipe regex ever stops matching, every set below goes empty and a
        # set-difference assertion passes by comparing nothing to nothing - which is precisely the shape of
        # false-clean this repo keeps paying for.
        $script:Fast.Count | Should -BeGreaterThan 5 -Because 'an empty fast list means the recipe parse broke, not that the gate is empty'
        $script:Slow.Count | Should -BeGreaterThan 5 -Because 'an empty slow list means the recipe parse broke'
        $script:OnDisk.Count | Should -BeGreaterThan 20 -Because 'an empty disk enumeration would make every comparison below vacuous'
    }

    It 'registers every suite on disk in the fast or slow gate' {
        $registered = @($script:Fast + $script:Slow | Sort-Object -Unique)
        $unregistered = @($script:OnDisk | Where-Object { $_ -notin $registered })
        # Name them. A count sends a reader hunting; a name sends them to the justfile line to edit.
        $unregistered -join ', ' | Should -BeExactly '' -Because 'a suite in neither gate exists, passes under `just test-scripts`, and never runs in the gates anyone uses'
    }

    It 'names no suite that is missing from disk' {
        $registered = @($script:Fast + $script:Slow | Sort-Object -Unique)
        $phantom = @($registered | Where-Object { $_ -notin $script:OnDisk })
        # Invoke-Pester is not an error on a path that does not exist, so a renamed-but-not-updated entry
        # silently drops that suite from the gate rather than failing it.
        $phantom -join ', ' | Should -BeExactly '' -Because 'a recipe naming a file that does not exist silently shrinks the gate'
    }

    It 'puts each suite in exactly ONE half of the partition' {
        $both = @($script:Fast | Where-Object { $_ -in $script:Slow })
        $both -join ', ' | Should -BeExactly '' -Because 'fast and slow are a partition; a suite in both is paid for twice and its measured timing in _partition.md is wrong'
    }
}

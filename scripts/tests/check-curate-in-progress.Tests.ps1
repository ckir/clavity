# scripts/tests/check-curate-in-progress.Tests.ps1
#
# The guard's whole value is that it BLOCKS. Every row below therefore asserts an exit CODE from a real
# invocation rather than inspecting the script's text - a guard pinned by what its source says is a
# guard nobody has ever run.
#
# THE FIXTURE IS A REAL GIT REPOSITORY WITH A REAL INDEX, not a list of paths handed to the script.
# That is deliberate. An earlier draft passed the staged list in as a parameter, which let the suite
# exercise a code path production never uses - and it hid a defect that only appears under the real
# invocation shape. Staging through git is the only way these rows test what actually runs.
BeforeAll {
    $script:Script   = Join-Path $PSScriptRoot '..' 'check-curate-in-progress.ps1'
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:Pinned   = @(
        'agy-autotrain/knowledge/driver-cheatsheet.core.md'
        'clavity-classic/src/driver_cheatsheet.rs'
        'clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs'
    )

    # Stage $Paths in $Root, creating each file and its parents. No commit: `git diff --cached` compares
    # against the empty tree when there is no HEAD, so an index alone is enough.
    function New-StagedFile { param([string]$Root, [string[]]$Paths)
        foreach ($p in $Paths) {
            $full = Join-Path $Root $p
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
            Set-Content -LiteralPath $full -Value 'content' -NoNewline
            git -C $Root add -- $p 2>&1 | Out-Null
        }
    }
}

Describe 'check-curate-in-progress.ps1' {
    BeforeEach {
        $script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("curatemark-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $script:Tmp '.clavity') -Force | Out-Null
        git -C $script:Tmp init -q 2>&1 | Out-Null
        $script:Marker = Join-Path $script:Tmp '.clavity/curate-in-progress'
    }
    AfterEach { Remove-Item -Recurse -Force $script:Tmp -ErrorAction SilentlyContinue }

    It 'the fixture really stages what it claims to' {
        # PRECONDITION GUARD FOR EVERY ROW BELOW. If `git add` silently failed - no git on PATH, an init
        # that did not take, a path git refuses - the index would be empty, the guard would correctly find
        # no pinned file staged, and every BLOCKS row would fail for a reason that has nothing to do with
        # the guard. Assert the fixture works before trusting any verdict built on it.
        New-StagedFile -Root $script:Tmp -Paths $script:Pinned[0]
        @(git -C $script:Tmp diff --cached --name-only) | Should -Contain $script:Pinned[0]
    }

    It 'allows the commit when no run is outstanding' {
        # No marker written. The overwhelmingly common case: it must never block.
        New-StagedFile -Root $script:Tmp -Paths $script:Pinned[0]
        & pwsh -NoProfile -File $script:Script -RepoRoot $script:Tmp -MarkerPath $script:Marker | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'BLOCKS a staged <File> while a run is outstanding' -ForEach @(
        @{ File = 'agy-autotrain/knowledge/driver-cheatsheet.core.md' }
        @{ File = 'clavity-classic/src/driver_cheatsheet.rs' }
        @{ File = 'clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs' }
    ) {
        # Every pinned file individually, not a representative one: the three are pinned byte-identical to
        # each other, so unreviewed content in ANY of them is the defect, and a typo in one of the other
        # two paths would ship a guard that skips it.
        Set-Content -LiteralPath $script:Marker -Value '' -NoNewline
        New-StagedFile -Root $script:Tmp -Paths $File
        & pwsh -NoProfile -File $script:Script -RepoRoot $script:Tmp -MarkerPath $script:Marker | Out-Null
        $LASTEXITCODE | Should -Be 1 -Because "$File carries unreviewed distilled content after an abnormal ending"
    }

    It 'allows SEVERAL unrelated files while a run is outstanding' {
        # The marker alone must not freeze the repository. Without this row the guard could block every
        # commit outright and every BLOCKS row above would still pass.
        Set-Content -LiteralPath $script:Marker -Value '' -NoNewline
        New-StagedFile -Root $script:Tmp -Paths @('README.md', 'scripts/check-versions-all.ps1', 'justfile')
        & pwsh -NoProfile -File $script:Script -RepoRoot $script:Tmp -MarkerPath $script:Marker | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'BLOCKS a pinned file staged ALONGSIDE unrelated ones' {
        # The realistic commit shape - nobody stages the cheatsheet on its own. Paired with the row above,
        # which is what makes either informative: this one alone cannot distinguish "detects the pinned
        # file" from "blocks everything", and that one alone cannot distinguish "ignores unrelated files"
        # from "never blocks at all".
        Set-Content -LiteralPath $script:Marker -Value '' -NoNewline
        New-StagedFile -Root $script:Tmp -Paths @('README.md', 'clavity-classic/src/driver_cheatsheet.rs', 'justfile')
        & pwsh -NoProfile -File $script:Script -RepoRoot $script:Tmp -MarkerPath $script:Marker | Out-Null
        $LASTEXITCODE | Should -Be 1 -Because 'the pinned file is staged, whatever else rides along with it'
    }

    It 'FAILS CLOSED when git cannot read the index' {
        # Fail-closed is a decision, not an accident, so it gets a row. Forced by pointing RepoRoot at a
        # directory that is not a git repository while the marker DOES exist: git exits non-zero and
        # prints nothing to stdout. A guard that trusted that silence would read it as "no pinned file
        # staged" and wave the commit through on the strength of an error - the exact fail-open shape
        # this script exists to avoid, and the one that would be invisible in production.
        Set-Content -LiteralPath $script:Marker -Value '' -NoNewline

        # OUTSIDE the fixture repo, not a subdirectory of it. The first version of this row used
        # "$Tmp/plain-directory" and the guard correctly exited 0, because git RESOLVES UPWARD and found
        # the fixture repo one level above - so the row was asserting fail-closed against a directory
        # that was, in fact, perfectly readable. The control was not creating the condition it named.
        $notARepo = Join-Path ([System.IO.Path]::GetTempPath()) ("notarepo-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Force -Path $notARepo | Out-Null
        try {
            # ASSERT THE PRECONDITION. If this directory turns out to be inside a repository after all,
            # the row below would pass or fail for a reason unrelated to fail-closed behaviour.
            git -C $notARepo rev-parse --git-dir 2>&1 | Out-Null
            $LASTEXITCODE | Should -Not -Be 0 -Because 'this row is meaningless unless git genuinely cannot read an index here'

            & pwsh -NoProfile -File $script:Script -RepoRoot $notARepo -MarkerPath $script:Marker | Out-Null
            $LASTEXITCODE | Should -Be 1 -Because 'an errored guard must block, never wave the commit through'
        }
        finally { Remove-Item -Recurse -Force $notARepo -ErrorAction SilentlyContinue }
    }

    It 'names the offending file, the marker, and a way out' {
        # The block message is the entire user interface of this guard. If it does not say WHICH file,
        # WHERE the marker is, and what to do, the human cannot act and reaches for --no-verify.
        Set-Content -LiteralPath $script:Marker -Value '' -NoNewline
        New-StagedFile -Root $script:Tmp -Paths 'clavity-classic/src/driver_cheatsheet.rs'
        $out = & pwsh -NoProfile -File $script:Script -RepoRoot $script:Tmp -MarkerPath $script:Marker 2>&1 | Out-String
        $out | Should -Match ([regex]::Escape('clavity-classic/src/driver_cheatsheet.rs'))
        $out | Should -Match ([regex]::Escape('curate-in-progress'))
        $out | Should -Match 'agy-curate'
        $out | Should -Match 'git diff --cached'
    }

    It 'BLOCKS a pinned file staged as a RENAME, not only as a modify' {
        # CAPSTONE R1-F2. The guard used `git diff --cached --diff-filter=ACM`, and ACM EXCLUDES status R.
        # MEASURED: `git mv other.md <pinned>` where the destination is absent from HEAD reports `R100`,
        # and --diff-filter=ACM then returns an EMPTY list - the pinned path is invisible and the guard
        # passes with the marker present. The same move onto a destination that IS in HEAD reports `M` and
        # was caught, which is why today's tree happened to be safe: not because the guard was right, but
        # because all three pinned files are tracked. This row pins the shape that has no such luck.
        Set-Content -LiteralPath $script:Marker -Value '' -NoNewline
        Set-Content -LiteralPath (Join-Path $script:Tmp 'source.md') -Value ('x' * 400) -NoNewline
        git -C $script:Tmp add -- 'source.md' 2>&1 | Out-Null
        git -C $script:Tmp -c user.email=t@t -c user.name=t commit -qm base 2>&1 | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $script:Tmp 'agy-autotrain/knowledge') | Out-Null
        git -C $script:Tmp mv 'source.md' 'agy-autotrain/knowledge/driver-cheatsheet.core.md' 2>&1 | Out-Null

        # Assert the fixture really produced a RENAME. Without this the row could pass against a plain
        # add and prove nothing about the filter at all.
        (@(git -C $script:Tmp diff --cached --name-status) -join ' ') | Should -Match '^R' -Because 'this row is meaningless unless git actually recorded a rename'

        & pwsh -NoProfile -File $script:Script -RepoRoot $script:Tmp -MarkerPath $script:Marker | Out-Null
        $LASTEXITCODE | Should -Be 1 -Because 'a rename onto a pinned path ships exactly the content this guard exists to stop'
    }

    It 'never tells the human to run a bare git checkout' {
        # CAPSTONE R1-F1, and the measurement made it worse than the finding. The message used to offer
        # `git checkout -- <files>` as its DISCARD branch. MEASURED: with the unreviewed content STAGED -
        # which is the only state in which this message is ever printed - `git checkout --` restores the
        # worktree FROM THE INDEX, so the unreviewed content survives in both, while any unstaged edit of
        # the human's own is destroyed. It failed at its stated purpose AND destroyed work, and the human
        # would then clear the marker believing they were clean.
        Set-Content -LiteralPath $script:Marker -Value '' -NoNewline
        New-StagedFile -Root $script:Tmp -Paths 'clavity-classic/src/driver_cheatsheet.rs'
        $out = & pwsh -NoProfile -File $script:Script -RepoRoot $script:Tmp -MarkerPath $script:Marker 2>&1 | Out-String
        $out | Should -Not -Match 'git checkout' -Because 'it discards nothing staged and destroys unstaged work'
        $out | Should -Match ([regex]::Escape('git restore --staged --worktree')) -Because 'this is the command that actually restores both index and worktree'
        $out | Should -Match 'WARNING' -Because 'the destructive branch must announce that it destroys the human own edits too'
    }

    It 'offers a discard command covering ALL THREE pinned files, not only the staged one' {
        # CAPSTONE R2-F1, and it is the fix to the R1 fold rather than to the original code - which is
        # exactly why it needs its own row. R1 rescoped the discard command to the OFFENDING files, which
        # reads as tidier and is a hole: a curate run writes all three pinned files together, so a human
        # who staged one, ran the offered command and cleared the marker would leave the other two dirty
        # with unreviewed content and no marker guarding them.
        #
        # Stage exactly ONE file, then assert the offered command names all three. Without this row the
        # scoping silently reverts and every other row stays green - the command's SHAPE is what changed,
        # not whether it blocks.
        Set-Content -LiteralPath $script:Marker -Value '' -NoNewline
        New-StagedFile -Root $script:Tmp -Paths 'clavity-classic/src/driver_cheatsheet.rs'
        $out = & pwsh -NoProfile -File $script:Script -RepoRoot $script:Tmp -MarkerPath $script:Marker 2>&1 | Out-String
        $discard = @($out -split "`n" | Where-Object { $_ -match 'git restore --staged --worktree' })
        $discard.Count | Should -Be 1 -Because 'exactly one discard command should be offered'
        foreach ($p in $script:Pinned) {
            $discard[0] | Should -Match ([regex]::Escape($p)) -Because "the discard must cover $p even though only one file is staged"
        }
    }

    It 'BLOCKS an outbound rename too - the pinned file renamed AWAY' {
        # CAPSTONE R2-F3. With git's rename detection on, a rename is ONE entry reporting only the
        # DESTINATION, so `git mv <pinned> other.rs` showed the guard `other.rs` alone and the pinned
        # source vanished - it passed, and the unreviewed content shipped under a new name. MEASURED, and
        # measured in the other direction too: `--no-renames` makes git report the pair as delete + add,
        # so whichever half is pinned is visible. This row covers the outbound half; the row above covers
        # the inbound half. Two holes, one flag - if someone removes --no-renames, both rows go red.
        Set-Content -LiteralPath $script:Marker -Value '' -NoNewline
        New-StagedFile -Root $script:Tmp -Paths 'clavity-classic/src/driver_cheatsheet.rs'
        git -C $script:Tmp -c user.email=t@t -c user.name=t commit -qm base 2>&1 | Out-Null
        git -C $script:Tmp mv 'clavity-classic/src/driver_cheatsheet.rs' 'clavity-classic/src/renamed-away.rs' 2>&1 | Out-Null

        # The fixture must really have produced a rename, or this row proves nothing about the flag.
        (@(git -C $script:Tmp diff --cached --name-status) -join ' ') | Should -Match '^R' -Because 'this row is meaningless unless git actually recorded a rename'

        & pwsh -NoProfile -File $script:Script -RepoRoot $script:Tmp -MarkerPath $script:Marker | Out-Null
        $LASTEXITCODE | Should -Be 1 -Because 'renaming the file away still ships its unreviewed content'
    }

    It 'resolves its OWN defaults - the parameters production never passes' {
        # CAPSTONE R2-F4. Every other row overrides BOTH -RepoRoot and -MarkerPath, so the two default
        # assignments were dead code in the suite while being the ONLY path lefthook uses. A mutant like
        # `$MarkerPath = "vacuous-bypass"` escaped every row.
        #
        # This row runs the script the way the hook does - no arguments at all - against the REAL
        # repository, with the REAL marker briefly present. It asserts the OUTSTANDING message, which the
        # script only prints when it resolved the default marker path and found the file. Under the mutant
        # it would resolve elsewhere, find nothing, and print "no agy-curate run outstanding" instead.
        #
        # It deliberately stages NOTHING, so it never touches the real index and cannot block anything.
        $realMarker = Join-Path $script:RepoRoot '.clavity/curate-in-progress'
        (Test-Path -LiteralPath $realMarker) | Should -BeFalse -Because 'this row must not run while a real curate run is outstanding, and must not clobber its marker'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $realMarker) | Out-Null
        try {
            Set-Content -LiteralPath $realMarker -Value '' -NoNewline
            $out = & pwsh -NoProfile -File $script:Script 2>&1 | Out-String
            $LASTEXITCODE | Should -Be 0 -Because 'nothing is staged, so an outstanding run must not block'
            $out | Should -Match 'a run is outstanding' -Because 'the default MarkerPath must resolve to the real marker; a wrong default would report none outstanding'
        }
        finally { Remove-Item -LiteralPath $realMarker -Force -ErrorAction SilentlyContinue }
    }

    It 'guards three paths that ACTUALLY EXIST in this repository' {
        # NON-VACUITY, and the only row that looks at the real tree. Every row above creates its own
        # fixture files, so all of them would still pass if the guard's pinned list were three typos.
        #
        # READS THE LIST OUT OF THE SCRIPT, not out of this suite. CAPSTONE R1-F4: it used to test
        # $script:Pinned - the suite's own array - so a typo in the SCRIPT would leave this row green and
        # the check rested entirely on the sync row below. The row's name claims to validate the guard's
        # configuration, so it now validates the guard's configuration.
        $src = Get-Content -Raw -LiteralPath $script:Script
        $inScript = @([regex]::Matches($src, "(?m)^\s+'([^']+\.(?:md|rs|cs))'\s*$") | ForEach-Object { $_.Groups[1].Value })
        $inScript.Count | Should -BeGreaterThan 0 -Because 'a regex that matched nothing would make this row vacuous'
        $missing = @($inScript | Where-Object { -not (Test-Path -LiteralPath (Join-Path $script:RepoRoot $_)) })
        $missing -join ', ' | Should -BeExactly '' -Because 'the guard protects nothing if the paths IT pins do not resolve'
    }

    It 'pins exactly the three files this suite exercises - both directions' {
        # The rows above hardcode their own copy of the list, which is what makes them readable and also
        # what would let the script's list drift away from them unnoticed. Compare both ways: a path the
        # script guards but no row exercises is untested coverage, and a path this suite believes in that
        # the script dropped is a row testing nothing.
        $src = Get-Content -Raw -LiteralPath $script:Script
        foreach ($p in $script:Pinned) {
            $src | Should -Match ([regex]::Escape($p)) -Because "the script must pin $p"
        }
        $inScript = @([regex]::Matches($src, "(?m)^\s+'([^']+\.(?:md|rs|cs))'\s*$") | ForEach-Object { $_.Groups[1].Value })
        $inScript.Count | Should -BeGreaterThan 0 -Because 'a regex that matches nothing would make the next assertion vacuous'
        @($inScript | Where-Object { $_ -notin $script:Pinned }) -join ', ' |
            Should -BeExactly '' -Because 'a pinned file the script guards but this suite never exercises is untested coverage'
    }
}

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

    $script:Lefthook = Join-Path $script:RepoRoot 'lefthook.yml'

    # Return the body lines of one lefthook command block, comments and blanks stripped.
    # Indentation-scoped rather than regex-over-the-whole-file: `run:` and `glob:` appear in more than
    # one command in this config, so an unscoped match would happily read the neighbouring ruff block
    # and report agreement that was never checked.
    function Get-LefthookCommandBody { param([string]$Path, [string]$Hook, [string]$Command)
        $lines = @(Get-Content -LiteralPath $Path)
        $h = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^$([regex]::Escape($Hook)):\s*$") { $h = $i; break }
        }
        if ($h -lt 0) { return @() }

        $start = -1; $indent = -1
        for ($i = $h + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\S') { break }        # the next top-level hook - we have left $Hook
            if ($lines[$i] -match "^(\s+)$([regex]::Escape($Command)):\s*$") {
                $start = $i; $indent = $Matches[1].Length; break
            }
        }
        if ($start -lt 0) { return @() }

        $body = @()
        for ($i = $start + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*$') { continue }
            if ($lines[$i] -match '^\s*#') { continue }
            if ((($lines[$i] -replace '^(\s*).*', '$1').Length) -le $indent) { break }
            $body += $lines[$i]
        }
        return ,$body
    }

    # The three paths as the SCRIPT itself declares them. Read from the script rather than restated here
    # on purpose - see the two rows at the end of this file.
    function Get-ScriptPinnedFiles {
        $src = Get-Content -Raw -LiteralPath $script:Script
        return ,@([regex]::Matches($src, "(?m)^\s+'([^']+\.(?:md|rs|cs))'\s*$") | ForEach-Object { $_.Groups[1].Value })
    }

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

            $out = & pwsh -NoProfile -File $script:Script -RepoRoot $notARepo -MarkerPath $script:Marker 2>&1 | Out-String
            $LASTEXITCODE | Should -Be 1 -Because 'an errored guard must block, never wave the commit through'

            # AND IT MUST SAY WHY. Blocking silently is not the same behaviour as blocking with a reason:
            # a commit refused with no output is indistinguishable from a broken repository, which is
            # precisely what teaches people to reach for --no-verify by reflex. Collapsing the catch block
            # to a bare `exit 1` keeps the exit-code assertion above green while destroying the only thing
            # that makes a fail-closed guard survivable.
            $out | Should -Match 'the guard itself failed' -Because 'a guard that blocks without saying why trains --no-verify'
            $out | Should -Match ([regex]::Escape('--no-verify')) -Because 'the message must name the deliberate escape hatch rather than leaving the human stuck'
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
        $out | Should -Match 'diff --cached'
        # CAPSTONE R3-F1. The marker is binary: it records that a run did not finish, and cannot know
        # whether that run had written anything yet. A run that stopped during triage - a long window -
        # leaves the marker set and the tree untouched, so a later legitimate hand edit to a pinned file
        # meets this message and its destructive DISCARD branch. The guard cannot tell the two apart, but
        # the HUMAN can by reading the diff, so the message must say so. Without this assertion that
        # paragraph is one careless trim away from vanishing, and what is left is a trap.
        $out | Should -Match 'stale marker' -Because 'the human must be told how to recognise a marker that outlived the run that set it'
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
        $out | Should -Match ([regex]::Escape('restore --staged --worktree')) -Because 'this is the command that actually restores both index and worktree'
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
        $discard = @($out -split "`n" | Where-Object { $_ -match 'restore --staged --worktree' })
        $discard.Count | Should -Be 1 -Because 'exactly one discard command should be offered'
        foreach ($p in $script:Pinned) {
            $discard[0] | Should -Match ([regex]::Escape($p)) -Because "the discard must cover $p even though only one file is staged"
        }

        # CAPSTONE R3-Q2a, the THIRD axis this one command has been wrong on. The paths are repo-relative
        # but `git restore` resolves a pathspec against the CURRENT directory, so a human who ran
        # `git commit` from a subdirectory and pasted this line got "pathspec did not match any file(s)"
        # and no discard at all. Anchoring with `git -C <root>` makes it correct from anywhere. Every
        # command the message prints must be anchored, not just this one.
        foreach ($line in @($out -split "`n" | Where-Object { $_ -match '\bgit\b' -and $_ -notmatch '^\s*#' })) {
            $line | Should -Match 'git -C ' -Because "a command the human is meant to paste must work from any directory: $($line.Trim())"
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
        # CAPSTONE R3-Q4. An earlier version of this row wrote the REAL marker into the REAL repository
        # inside a try/finally. That is not safe: `finally` does not run if the process is killed or Pester
        # aborts, and the residue is not inert - a stray `.clavity/curate-in-progress` BLOCKS the
        # developer's next commit of a pinned file. A test whose crash-residue is the very condition the
        # product treats as a fault has no business touching the live tree.
        #
        # Instead, COPY THE SCRIPT into the fixture repo and run it there with no arguments. The script
        # derives its RepoRoot from `Join-Path $PSScriptRoot '..'`, so a copy at <fixture>/scripts/ makes
        # both defaults resolve inside the fixture - exercising exactly the production path, with every
        # side effect confined to a temp directory that AfterEach removes.
        $fixtureScripts = Join-Path $script:Tmp 'scripts'
        New-Item -ItemType Directory -Force -Path $fixtureScripts | Out-Null
        Copy-Item -LiteralPath $script:Script -Destination (Join-Path $fixtureScripts 'check-curate-in-progress.ps1')
        Set-Content -LiteralPath $script:Marker -Value '' -NoNewline   # the fixture's own .clavity marker

        $out = & pwsh -NoProfile -File (Join-Path $fixtureScripts 'check-curate-in-progress.ps1') 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because 'nothing is staged, so an outstanding run must not block'
        $out | Should -Match 'a run is outstanding' -Because 'the default MarkerPath must resolve to <root>/.clavity/curate-in-progress; a wrong default would report none outstanding'

        # And prove the row would notice the live repository being touched instead of the fixture.
        (Test-Path -LiteralPath (Join-Path $script:RepoRoot '.clavity/curate-in-progress')) |
            Should -BeFalse -Because 'this row must never leave a marker in the real repository'
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

    # ------------------------------------------------------------------------------------------------
    # THE WIRING. Every row above invokes the .ps1 DIRECTLY, which is not how it ever runs in production.
    # A coverage audit found that deleting the whole `curate-in-progress:` block from lefthook.yml left
    # all of them green while the guard was completely disarmed - detector coverage is not wiring
    # coverage. These rows pin the chain, not the detector.
    # ------------------------------------------------------------------------------------------------

    It 'lefthook ACTUALLY invokes the guard and propagates its refusal' {
        # BEHAVIOURAL, deliberately - it runs the real lefthook binary against the real lefthook.yml.
        # A config PARSE cannot prove the hook fires: the text can read perfectly while lefthook skips
        # the command for a reason the text does not spell out.
        #
        # NAMED FOR WHAT IT ASSERTS, not for the regression it defends. This row does not itself remove
        # the wiring - MEASURED separately, it goes RED when the `curate-in-progress:` block is deleted
        # and when the glob stops naming a pinned file, because both drop lefthook's exit from 1 to 0
        # with the marker present. That is the row's value, but a name promising a removal test this row
        # does not perform is how a suite gets credited with coverage it does not have.
        if (-not (Get-Command lefthook -ErrorAction SilentlyContinue)) {
            throw 'lefthook is not on PATH, so the wiring cannot be verified. This row must FAIL rather than skip: a skipped wiring proof certifies exactly what it stopped checking.'
        }

        # ON `main`, NOT the git default. Measured: `init.defaultBranch` here is `master`, and lefthook
        # supports branch-conditional keys (`skip:`/`only:` with a `ref:`) that validate cleanly. A
        # bypass keyed on `main` - the branch everything is committed to - would be invisible to a
        # fixture sitting on any other branch, so the fixture sits on the branch that matters.
        git -C $script:Tmp checkout -q -b main 2>&1 | Out-Null

        Copy-Item -LiteralPath $script:Lefthook -Destination (Join-Path $script:Tmp 'lefthook.yml')
        $fixtureScripts = Join-Path $script:Tmp 'scripts'
        New-Item -ItemType Directory -Force -Path $fixtureScripts | Out-Null
        Copy-Item -LiteralPath $script:Script -Destination (Join-Path $fixtureScripts 'check-curate-in-progress.ps1')
        # The fixture runs the REAL lefthook.yml, which now carries a second pre-commit command
        # (cheatsheet-parity, ROADMAP 14e) globbing the same three paths this fixture stages. Without
        # its script present, lefthook fails for a reason that has nothing to do with this suite and
        # the control row below - which asserts exit 0 - goes red.
        # A STUB, NOT THE REAL SCRIPT - and panel R4 caught why copying the real one does not work.
        # This fixture stages clavity-classic/src/driver_cheatsheet.rs (:359) and contains NO core.md at
        # all. The real parity hook would find a literal present in the index with no canonical source,
        # which by Task 11's own rules is the "source gone, literal left behind" case and exits non-zero -
        # so lefthook fails and the control row below (`Should -Be 0`) goes RED. Copying the real script
        # trades one failure for another.
        #
        # A stub is the CORRECT isolation here, not a dodge: this row's claim is that lefthook invokes
        # THE CURATE GUARD and propagates ITS refusal. Any other pre-commit command is noise for that
        # claim, and the parity hook's real behaviour is covered by its own suite in Task 11 - which is
        # where a wiring break in it must be caught, not here.
        Set-Content -LiteralPath (Join-Path $fixtureScripts 'check-cheatsheet-parity.ps1') -Value 'exit 0'
        New-StagedFile -Root $script:Tmp -Paths 'clavity-classic/src/driver_cheatsheet.rs'

        Push-Location $script:Tmp
        try {
            # CONTROL FIRST. No marker: lefthook must run the hook and the commit must be allowed. Without
            # this half, a lefthook that failed for any unrelated reason - a bad config, a missing binary,
            # a hook that errors - would look exactly like a successful block.
            & lefthook run pre-commit *>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0 -Because 'with no run outstanding, the wired hook must let an ordinary commit through'

            Set-Content -LiteralPath $script:Marker -Value '' -NoNewline
            $out = & lefthook run pre-commit *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1 -Because 'lefthook must actually invoke the guard and propagate its refusal'
            $out | Should -Match ([regex]::Escape('check-curate-in-progress: BLOCKED')) -Because 'the refusal must be THIS guard, not some other pre-commit command failing'
        }
        finally { Pop-Location }
    }

    It 'the lefthook glob and the script pin exactly the same files - both directions' {
        # The BEHAVIOURAL row above catches a glob that stops matching a pinned file, because the guard
        # then never runs. It does NOT catch the opposite drift: widening the glob to something like "*"
        # keeps every pinned file matched, so that row stays green while every unrelated commit starts
        # paying the ~6s pwsh cold start the glob exists to avoid. That direction is a cost regression
        # rather than a safety one, and this is the row that sees it.
        #
        # It also closes the third-list problem: these paths are written down in the script, in this
        # suite, and in lefthook.yml. The rows above compare the first two. Nothing compared the third.
        $body = Get-LefthookCommandBody -Path $script:Lefthook -Hook 'pre-commit' -Command 'curate-in-progress'
        $body.Count | Should -BeGreaterThan 0 -Because 'an empty block would make every assertion below vacuous - and would itself mean the wiring is gone'

        # [regex]::Match per line, NOT a `-match` in Where-Object read by a later ForEach-Object: that
        # form happens to work only because the pipeline streams, and it silently degrades to repeating
        # one path if anything ever buffers it.
        $globs = @(foreach ($line in $body) {
            $m = [regex]::Match($line, '^\s*-\s*"(.+)"\s*$')
            if ($m.Success) { $m.Groups[1].Value }
        })
        $globs.Count | Should -BeGreaterThan 0 -Because 'a glob list that parsed as empty would make the SECOND comparison below vacuous - the first one reds loudly, so this guard is what catches the quiet half'

        $inScript = Get-ScriptPinnedFiles
        $inScript.Count | Should -BeGreaterThan 0 -Because 'the script pin list must parse, or this row proves nothing'

        @($inScript | Where-Object { $_ -notin $globs }) -join ', ' |
            Should -BeExactly '' -Because 'a file the guard pins but lefthook does not glob is a file the guard is never invoked for'
        @($globs | Where-Object { $_ -notin $inScript }) -join ', ' |
            Should -BeExactly '' -Because 'a glob lefthook matches but the guard does not pin pays the pwsh cold start for nothing'
    }

    It 'the curate-in-progress command carries no key that could conditionally disable it' {
        # lefthook accepts `skip:` and `only:`, both of which take a `ref:` condition - VERIFIED with
        # `lefthook validate`, which accepts them and rejects an invented key. A condition keyed on one
        # branch is invisible to any test running on another, so the class is closed here, by asserting
        # the command is unconditional, rather than by trying to enumerate branches behaviourally.
        $body = Get-LefthookCommandBody -Path $script:Lefthook -Hook 'pre-commit' -Command 'curate-in-progress'
        $body.Count | Should -BeGreaterThan 0 -Because 'an empty block would make this row vacuous'

        $conditional = @($body | Where-Object { $_ -match '^\s*(skip|only|exclude)\s*:' })
        $conditional -join ' | ' | Should -BeExactly '' -Because 'this guard must run on every branch; a conditional key silently disarms it where it matters most'

        $run = @($body | Where-Object { $_ -match '^\s*run\s*:' })
        $run.Count | Should -Be 1 -Because 'exactly one run line, or the block does not do what the rows above assume'
        $run[0] | Should -Match ([regex]::Escape('scripts/check-curate-in-progress.ps1')) -Because 'the wired command must be THIS guard'
    }

    It 'the marker path the skill ARMS is the marker path the guard READS' {
        # The skill writes the marker; this script reads it. Nothing coupled them, so renaming it in one
        # place left the other reading a path nobody writes - the guard then fails OPEN, silently, and
        # every row in this file stays green because they all create the script's own default by hand.
        #
        # The wider case is worse than a rename and is what the second assertion is for: delete STEP ZERO
        # outright and the marker is simply never armed, so the guard never fires at all.
        #
        # KNOWN LIMIT: this reads markdown as text, so a commented-out copy of the old path could keep it
        # green. That class is recorded against check-cheatsheet-budget.Tests.ps1. It is worth having
        # anyway - it costs one row and catches the rename and the deletion, which are the reachable ones.
        $skill = Join-Path $script:RepoRoot 'agy-autotrain/skills/agy-curate/SKILL.md'
        Test-Path -LiteralPath $skill | Should -BeTrue -Because 'the skill that arms the marker must exist, or this guard protects a path nobody writes'

        # Match explicitly rather than leaning on `Should -Match` to populate $Matches - it does not, and
        # the row died on a null index the first time it ran.
        $src = Get-Content -Raw -LiteralPath $script:Script
        $m = [regex]::Match($src, "MarkerPath\s*=\s*Join-Path\s+\`$RepoRoot\s+'([^']+)'")
        $m.Success | Should -BeTrue -Because 'the default marker path must be readable out of the script, or this row is vacuous'
        $markerRel = $m.Groups[1].Value
        $markerRel | Should -Not -BeNullOrEmpty

        $skillText = Get-Content -Raw -LiteralPath $skill
        $skillText | Should -Match ([regex]::Escape($markerRel)) -Because "the skill must arm the very path the guard reads ($markerRel)"
        $skillText | Should -Match '(?m)^##\s+STEP ZERO' -Because 'the section that arms the marker must still exist; without it nothing ever creates the file and the guard is inert'
    }
}

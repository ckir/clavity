# Structural guards for the ROADMAP 14g inbox migration in the agy-autotrain installer.
#
# WHY THIS EXISTS. `MigrateInboxToUserState` was the largest executable change in the 14g range
# (+154/-19), carries six failure branches and a rollback, and had ZERO coverage of any kind: MEASURED
# at f29cd42, neither `MigrateInboxToUserState` nor `.migrated-14g` appeared in any file under
# scripts/, any *.Tests.ps1, or any workflow. Its only gate was an ISCC compile, which proves the file
# COMPILES and nothing about what it does. Restoring the pre-fold write-then-rename order recompiles
# cleanly and exits ISCC 0 - and that is precisely the defect the fold exists to kill.
#
# WHAT THIS CAN AND CANNOT DO. Pascal in an .iss cannot be executed by Pester, and the behavioural
# half of this gap belongs in the installer smoke workflow (it installs twice already). What IS
# checkable here is the ORDER, which is the whole safety argument: the source must be CLAIMED by
# rename BEFORE anything is written, so a crash between the two leaves a recoverable state rather than
# a duplicating one. A test that only inspected the end state could not tell the two orders apart.
#
# LINE INDEX, NEVER A BRACE PARSER. A brace-counting parser over an .iss is vacuous here: Inno's `{{`
# escape and its brace-delimited COMMENTS unbalance any naive counter, and one such parser reported a
# 292-line file as having 4 executable lines while still printing a confident verdict. The procedure
# body is therefore delimited by line index between its own header and the next top-level declaration.

Describe 'agy-autotrain installer: the 14g inbox migration' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:IssPath = Join-Path $repoRoot 'agy-autotrain/installer/agy-autotrain.iss'
        $all = Get-Content -LiteralPath $script:IssPath

        $start = -1
        for ($i = 0; $i -lt $all.Count; $i++) {
            if ($all[$i] -match '^procedure\s+MigrateInboxToUserState\s*\(') { $start = $i; break }
        }
        $end = $all.Count
        if ($start -ge 0) {
            for ($i = $start + 1; $i -lt $all.Count; $i++) {
                if ($all[$i] -match '^(procedure|function)\s') { $end = $i; break }
            }
        }
        $script:Start = $start
        $script:Body = if ($start -ge 0) { $all[$start..($end - 1)] } else { @() }

        # CODE lines only - comments are stripped first. Without this, moving a searched literal into
        # a comment satisfies every assertion here: MEASURED at ee07de0, deleting the rollback and
        # leaving `{ rollback removed for now: RenameFile(Aside, OldPath) used to be here }` kept all
        # six guards green while the rollback was gone.
        # The rule is deliberately narrow, and its narrowness is the point: a line is a comment when its
        # TRIMMED form starts with `{` or `//`, and a `{`-opened line keeps the state until a line
        # containing `}`. It is NOT a general Inno parser - a brace counter over an .iss is vacuous here
        # (the `{{` escape and brace-delimited comments defeat it, and one such parser reported this
        # 292-line file as 4 executable lines). This rule cannot mis-handle `ExpandConstant('{app}\...')`
        # either, because that brace is mid-line inside a string, never at the start of a trimmed line.
        $script:CodeOnly = @()
        $inComment = $false
        foreach ($line in $script:Body) {
            $trim = $line.Trim()
            if ($inComment) {
                if ($trim -match '\}') { $inComment = $false }
                $script:CodeOnly += ''
                continue
            }
            if ($trim.StartsWith('//')) { $script:CodeOnly += ''; continue }
            if ($trim.StartsWith('{')) {
                if ($trim -notmatch '\}') { $inComment = $true }
                $script:CodeOnly += ''
                continue
            }
            $script:CodeOnly += $line
        }

        # Index of the FIRST body CODE line matching a literal substring; -1 when absent.
        function Find-BodyLine { param([string]$Needle)
            for ($i = 0; $i -lt $script:CodeOnly.Count; $i++) {
                if ($script:CodeOnly[$i] -like "*$Needle*") { return $i }
            }
            return -1
        }
    }

    It 'extracts the procedure body at all (the precondition every assertion below rests on)' {
        # Without this, a rename of the procedure would empty $Body and EVERY ordering assertion below
        # would pass vacuously on -1 indices comparing equal.
        $script:Start | Should -BeGreaterThan -1 -Because 'MigrateInboxToUserState must exist; if it was renamed, these guards are inspecting nothing'
        $script:Body.Count | Should -BeGreaterThan 40 -Because 'the extracted body must be substantial, or the delimiter logic has silently truncated it'
        ($script:Body -join "`n") | Should -Match 'RenameFile' -Because 'the body must contain the rename this file exists to constrain'
    }

    It 'CLAIMS the source by rename BEFORE it writes anything' {
        # THE ORDERING INVARIANT. Pre-fold the procedure wrote first and renamed last, discarding the
        # rename's Boolean: a rename that failed after a successful write left the source in place, so
        # the next upgrade saw a non-empty destination, took the append branch, and appended every entry
        # AGAIN - unbounded, once per upgrade. Claiming first makes a crash between the two a clean
        # no-op that the next run retries from scratch.
        $claim = Find-BodyLine 'RenameFile(OldPath, Aside)'
        $copy  = Find-BodyLine 'FileCopy(Aside, NewPath'
        $save  = Find-BodyLine 'SaveStringsToFile(NewPath, OldLines'

        # Each index asserted present FIRST. Comparing two -1s would satisfy any ordering assertion.
        $claim | Should -BeGreaterThan -1 -Because 'the claiming rename must be present'
        $copy  | Should -BeGreaterThan -1 -Because 'the copy branch must be present'
        $save  | Should -BeGreaterThan -1 -Because 'the append branch must be present'

        $claim | Should -BeLessThan $copy -Because 'the source must be CLAIMED before the copy branch writes, or a failed rename after a successful write duplicates the whole inbox on the next upgrade'
        $claim | Should -BeLessThan $save -Because 'the source must be CLAIMED before the append branch writes, for the same reason'
    }

    It 'checks for a pre-existing sidecar BEFORE claiming, and refuses rather than guessing' {
        # An existing .migrated-14g beside a source file is ambiguous - the source may be already-
        # migrated content or genuinely new captures - and appending blind would duplicate. That check
        # is only protective if it happens BEFORE the claim.
        $sidecar = Find-BodyLine 'if FileExists(Aside) then'
        $claim   = Find-BodyLine 'RenameFile(OldPath, Aside)'
        $sidecar | Should -BeGreaterThan -1 -Because 'the ambiguous-sidecar guard must be present'
        $claim   | Should -BeGreaterThan -1
        $sidecar | Should -BeLessThan $claim -Because 'an ambiguous source must be detected before anything is claimed or written'
    }

    It 'ROLLS THE CLAIM BACK when the write fails' {
        # Without the rollback a failed write strands the entire backlog under .migrated-14g, where the
        # sidecar guard above will never look again - the operator loses every undrained observation
        # with no message that says where it went.
        $notWrote = Find-BodyLine 'if not Wrote then'
        $notWrote | Should -BeGreaterThan -1 -Because 'the write-failure branch must be present'

        # BOUNDED BY THE BRANCH, not by a line-index comparison. `$rollback -gt $notWrote` is satisfied
        # by a rollback placed AFTER the branch closes, which is a live defect rather than a nitpick:
        # running the rollback unconditionally renames the sidecar back on a SUCCESSFUL migration, so
        # the next upgrade sees a source with no sidecar, claims it, finds a non-empty destination, and
        # appends the whole inbox again - the unbounded duplication this fold exists to kill, re-armed.
        # MEASURED at ee07de0: that mutant compiled (ISCC 0) and passed all six guards.
        $branch = @()
        for ($j = $notWrote + 1; $j -lt $script:CodeOnly.Count; $j++) {
            if ($script:CodeOnly[$j] -match '^\s*end;') { break }
            $branch += $script:CodeOnly[$j]
        }
        $branch.Count | Should -BeGreaterThan 0 -Because 'the write-failure branch must have a body, or this scan is inspecting nothing'
        ($branch -join "`n") | Should -Match 'RenameFile\(Aside, OldPath\)' -Because 'the rollback must live INSIDE the write-failure branch - placed after it, it fires on a SUCCESSFUL migration and re-arms the duplication defect'
        ($branch -join "`n") | Should -Match 'MigrationProblem' -Because 'the write-failure branch is the one failure path with no exit, so nothing else in this file forces it to tell the operator anything'
    }

    It 'APPENDS to a non-empty destination rather than clobbering it' {
        # SaveStringsToFile's third argument is the append flag. Flipping it to False destroys a newer
        # inbox at the destination - silently, and only for the user who already had one.
        ($script:Body -join "`n") | Should -Match 'SaveStringsToFile\(NewPath, OldLines, True\)' -Because 'the append flag is what stops the migration clobbering a destination that already holds captures'
    }

    It 'TERMINATES every pre-write failure branch - each reports AND exits' {
        # THE SCAN BELOW IS NOT ENOUGH, and this test exists because a capstone round proved it.
        # `reports EVERY failure branch` iterates over `exit;` lines and `continue`s past everything
        # else, so its postcondition is "every exit has a report near it" - NOT "every failure branch
        # terminates". Delete the `exit;` and the branch simply drops out of that scan.
        # MEASURED at ee07de0, two mutants of the claim-failure branch (agy-autotrain.iss:189-194):
        #   A. report AND exit both removed -> 6 passed / 0 failed
        #   B. report kept, only exit removed -> 6 passed / 0 failed
        # (control: deleting the ambiguous-sidecar guard reds 5/1, so the harness was live.)
        # Both are the LIVE defect. A failed claim then falls through to DestSize/FileCopy/
        # SaveStringsToFile with the source NOT claimed: the write lands, OldPath is still there, and
        # the next upgrade sees a non-empty destination, takes the append branch, and appends every
        # entry again - the unbounded duplication this whole fold exists to kill, on the exact Windows
        # trigger the .iss header names (an AV hold, or another process holding the file open).
        #
        # So this asserts the CONDITION, not the exit: each guard that runs BEFORE any write must
        # contain both a report and an exit before its own `end;`. Enumerated in full - a partial list
        # would leave exactly the hole being closed.
        $guards = @(
            'if not ForceDirectories(NewDir) then'
            'if not LoadStringsFromFile(OldPath, OldLines) then'
            'if FileExists(Aside) then'
            'if not RenameFile(OldPath, Aside) then'
        )
        $leaky = @()
        foreach ($g in $guards) {
            $i = Find-BodyLine $g
            # Present-FIRST. A renamed or deleted guard must red here, not vanish from the loop.
            $i | Should -BeGreaterThan -1 -Because "the pre-write guard '$g' must exist, or this scan is inspecting nothing"

            $reported = $false; $exited = $false
            for ($j = $i + 1; $j -lt $script:Body.Count; $j++) {
                if ($script:Body[$j] -match 'MigrationProblem') { $reported = $true }
                if ($script:Body[$j] -match '^\s*exit\s*;')     { $exited = $true }
                if ($script:Body[$j] -match '^\s*end;')          { break }
            }
            if (-not ($reported -and $exited)) {
                $leaky += ("{0} (reports={1} exits={2})" -f $g, $reported, $exited)
            }
        }
        ($leaky -join '; ') | Should -BeNullOrEmpty -Because 'a pre-write guard that does not BOTH report and exit falls through to the write with the source unclaimed, which is the unbounded-duplication defect the fold exists to prevent'
    }

    It 'reports EVERY failure branch instead of exiting silently' {
        # Pre-fold, each failure path was a bare `exit`, so a failed migration was indistinguishable
        # from a successful one and the operator was never told their captures had not moved. The one
        # legitimate silent exit is the first: no old inbox present means there is nothing to migrate.
        # The window is bounded by the ENCLOSING `begin`, never by a fixed line count. A fixed
        # lookback was the first version of this scan and it was VACUOUS: MEASURED, deleting the
        # MigrationProblem call from the unreadable-source branch left all six tests green, because an
        # 8-line window reached back far enough to find the PRECEDING branch's call and count it. A
        # guard that reads a neighbour's evidence certifies whatever sits next to it.
        $silent = @()
        $seenFirstExit = $false
        for ($i = 0; $i -lt $script:Body.Count; $i++) {
            if ($script:Body[$i] -notmatch '^\s*exit\s*;') { continue }
            if (-not $seenFirstExit) { $seenFirstExit = $true; continue }   # the nothing-to-do return

            $lo = -1
            for ($j = $i - 1; $j -ge 0; $j--) {
                if ($script:Body[$j] -match '^\s*begin\s*$') { $lo = $j; break }
                if ($script:Body[$j] -match '^\s*(end\s*;|exit\s*;)') { break }   # left the branch
            }
            $window = if ($lo -ge 0) { $script:Body[$lo..$i] -join "`n" } else { $script:Body[$i] }
            if ($window -notmatch 'MigrationProblem') { $silent += "body line $i : $($script:Body[$i].Trim())" }
        }
        $seenFirstExit | Should -BeTrue -Because 'the body must contain at least the nothing-to-do exit, or this scan matched nothing and proves nothing'
        ($silent -join '; ') | Should -BeNullOrEmpty -Because 'every failure exit must be preceded by a MigrationProblem call - a silent failed migration reads exactly like a successful one'
    }
}

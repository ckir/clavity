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
# file - 292 lines then, 296 now - as having 4 executable lines while still printing a confident
# verdict. (The count moved in the same commit that rewrote this block, which is why it is stated
# as history rather than as a fact about the file today.) The procedure
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

        # CODE ONLY - comments stripped, INCLUDING TRAILING ONES. Without this, moving a searched
        # literal into a comment satisfies every assertion here.
        #
        # The first version of this rule only blanked lines whose TRIMMED form STARTED with `{` or
        # `//`, and that was not enough. MEASURED: replacing the claim-failure branch with the single
        # line `exit;   { MigrationProblem('...') removed for now }` kept all seven guards GREEN - one
        # trailing comment satisfied BOTH halves of the reports-and-exits check at once. This repo had
        # already learned that lesson and written it down: see the header of
        # test-suite-registration.Tests.ps1, "handling only whole-line comments left the trailing case
        # wide open". This file made exactly that mistake and had to be told twice.
        #
        # STRING-AWARE, and that is load-bearing rather than fussy: this body contains
        # `ExpandConstant('{app}\...')` and `ExpandConstant('{%USERPROFILE}')`, whose braces sit INSIDE
        # single-quoted strings and are not comments. A rule that stripped from any `{` would delete
        # real code. It is still NOT a general Inno parser and must not become one - a brace COUNTER
        # over an .iss is vacuous (the `{{` escape and brace-delimited comments defeat it; one such
        # parser reported this file, then 292 lines, as 4 executable lines). Inno comments do not nest,
        # so a single-level state machine is exactly right.
        # Three comment forms, because Inno accepts three. `(* *)` was missing and was a TOTAL
        # evasion: MEASURED, wrapping the claim-failure branch in `(* ... *)` passed 8/8 while the
        # branch reported nothing - and ISCC ACCEPTS IT, verified by compiling the variant (exit 0,
        # against a deliberately-broken control that exits 2). So it would have shipped.
        #
        # -BlankStrings is the second projection, and it exists because stripping comments alone was
        # only half the job. Every behavioural grep here looks for a literal in the body; a literal
        # inside a STRING satisfied that grep exactly as a literal in a comment used to. MEASURED:
        # flipping SaveStringsToFile's flag to False while leaving the True form inside an operator
        # message string passed 8/8 - the defect a previous round had just closed, resurrected through
        # a different channel. The two projections are in tension by design: the `{app}` control needs
        # string BODIES kept, the behavioural greps need them gone, so the file computes both.
        function Remove-InnoComments {
            param([string[]]$Lines, [switch]$BlankStrings)
            $result = @()
            $inBrace = $false
            $inParen = $false
            foreach ($line in $Lines) {
                $kept = ''
                # Per line: a Pascal string cannot span lines, a comment can. That asymmetry is why
                # $inString is re-initialised here and $inBrace/$inParen are not.
                $inString = $false
                $i = 0
                while ($i -lt $line.Length) {
                    $ch = $line[$i]
                    if ($inBrace) {
                        if ($ch -eq '}') { $inBrace = $false }
                        $i++; continue
                    }
                    if ($inParen) {
                        if ($ch -eq '*' -and ($i + 1) -lt $line.Length -and $line[$i + 1] -eq ')') { $inParen = $false; $i += 2; continue }
                        $i++; continue
                    }
                    if ($inString) {
                        # A doubled '' is Pascal's escaped apostrophe. Handled by PARITY rather than by
                        # a special case: the machine leaves the string at the first quote and re-enters
                        # at the second with no character between, so its state after the pair matches
                        # Pascal's.
                        # NOT exercised by the real input, and saying otherwise was false: the two
                        # doubled-quote sites in this .iss are at :90 and :255, both OUTSIDE the
                        # extracted procedure body, so the stripper never sees either. Its only oracle
                        # is the dedicated fixture below - which is the correct design, and is what the
                        # `//` arm's comment already says honestly about itself.
                        if ($ch -eq "'") { $inString = $false; $kept += $ch }
                        elseif (-not $BlankStrings) { $kept += $ch }
                        $i++; continue
                    }
                    if ($ch -eq "'") { $inString = $true; $kept += $ch; $i++; continue }
                    if ($ch -eq '{') { $inBrace = $true; $i++; continue }
                    if ($ch -eq '(' -and ($i + 1) -lt $line.Length -and $line[$i + 1] -eq '*') { $inParen = $true; $i += 2; continue }
                    if ($ch -eq '/' -and ($i + 1) -lt $line.Length -and $line[$i + 1] -eq '/') { break }
                    $kept += $ch
                    $i++
                }
                $result += $kept
            }
            return $result
        }
        # ONE extractor, used by EVERY scan that needs a guard's branch. The previous round fixed the
        # unbounded "scan to the next `end;` ANYWHERE" rule in one scan and left its sibling 60 lines
        # above untouched - in the same commit, in the same file, against a comment that argued at
        # length for the bound. MEASURED afterwards: an UNCONDITIONAL rollback placed after the
        # write-failure branch - legal Pascal, `if X then <single statement>;` with no begin/end - still
        # passed 15/15, which is exactly the defect that comment says it exists to catch.
        # Two call sites diverging is what caused it, so there is now only one implementation.
        function Get-BranchBody {
            param([string[]]$Lines, [int]$HeadIndex)
            $out = @()
            if ($HeadIndex + 1 -ge $Lines.Count) { return $out }
            if ($Lines[$HeadIndex + 1] -match '^\s*begin\s*$') {
                for ($j = $HeadIndex + 2; $j -lt $Lines.Count; $j++) {
                    if ($Lines[$j] -match '^\s*end;') { break }
                    $out += $Lines[$j]
                }
            } else {
                # No block: the branch is the single statement that STARTS on the next line.
                #
                # This arm assumes that statement occupies exactly ONE line, and that assumption is
                # FALSE in general - Pascal lets a single statement span several lines through string
                # concatenation, and `agy-autotrain.iss` does exactly that at :211-213 and :214-216,
                # where each `MigrationProblem(...)` call wraps onto a continuation line. An earlier
                # version of this comment claimed "NOTHING beyond it belongs to this guard", which is
                # simply wrong for that shape.
                #
                # It is NOT a live defect today, and that was measured rather than assumed: every one of
                # the five call sites reaches this function at a head line whose NEXT line is `begin`,
                # so the block arm above is taken every time and this arm is currently unreached. The
                # four `$guards` entries and the `$notWrote` head were each checked individually.
                #
                # So this is a latent hazard, left deliberately rather than fixed: making it correct
                # means deciding where a wrapped statement ends, which needs a real expression parser -
                # and this file already records that brace-counting an .iss is vacuous. If a future
                # guard head is ever followed by a wrapped single statement, THIS is the line that
                # silently truncates its body, and the fix belongs here.
                $out += $Lines[$HeadIndex + 1]
            }
            return $out
        }
        $script:CodeOnly      = @(Remove-InnoComments -Lines $script:Body)
        $script:CodeNoStrings = @(Remove-InnoComments -Lines $script:Body -BlankStrings)

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
        ($script:CodeOnly -join "`n") | Should -Match 'RenameFile' -Because 'the body must contain the rename this file exists to constrain'
    }

    Context 'Remove-InnoComments - the stripper driven by FIXTURES, not by this one .iss' {
        # WHY THIS CONTEXT EXISTS, and it is the whole lesson of round 4.
        # The original control asserted things about the stripper's OUTPUT ON THE REAL .iss: that
        # {app} survived and that one comment's prose did not. MEASURED: reverting the stripper to the
        # earlier whole-line-only rule left that control GREEN and the whole suite 8/8 - while a
        # trailing comment re-armed the silent-failure defect. The control could not tell the fixed
        # stripper from the broken one, because the real .iss happens to contain no trailing comment.
        #
        # A guard whose fixture cannot produce the failure is not a guard. These drive the function
        # DIRECTLY with inputs chosen to make each arm observable, so every arm has an oracle even
        # though the real file exercises only two of them.

        It 'removes a TRAILING { } comment, not only a whole-line one' {
            $out = (Remove-InnoComments -Lines @("    exit;   { MigrationProblem('gone'); }")) -join "`n"
            $out | Should -Match 'exit;'            -Because 'the code before the comment must survive'
            $out | Should -Not -Match 'MigrationProblem' -Because 'a TRAILING comment is still a comment - this exact shape passed 8/8 before it was handled'
        }

        It 'removes a // comment to end of line' {
            # The real .iss contains no `//` at all (measured: zero occurrences), so this arm has no
            # natural fixture and was previously deletable with the suite still green.
            $out = (Remove-InnoComments -Lines @("    exit;   // MigrationProblem('gone');")) -join "`n"
            $out | Should -Match 'exit;'
            $out | Should -Not -Match 'MigrationProblem'
        }

        It 'removes a (* *) comment, including one spanning lines' {
            # ISCC ACCEPTS this form - verified by compiling a variant (exit 0), against a broken
            # control that exits 2. Unhandled, it was a total evasion: 8/8 green with the branch empty.
            $out = (Remove-InnoComments -Lines @('  begin', '  (*', "  MigrationProblem('gone');", '  exit;', '  *)', '  end;')) -join "`n"
            $out | Should -Match 'begin'
            $out | Should -Match 'end;'
            $out | Should -Not -Match 'MigrationProblem' -Because 'a (* *) block is a comment in Pascal and ISCC compiles it'
            $out | Should -Not -Match 'exit;'
        }

        It 'keeps a brace that lives INSIDE a string literal' {
            $out = (Remove-InnoComments -Lines @("  OldPath := ExpandConstant('{app}\plugins');")) -join "`n"
            $out | Should -Match '\{app\}' -Because 'a brace inside a single-quoted string is not a comment - stripping it would delete real code'
        }

        It 'treats a doubled quote as an escaped apostrophe, by parity' {
            # Two such sites exist in the real file (`Result := ''` and `agy-autotrain''s`).
            $out = (Remove-InnoComments -Lines @("  Msg := 'agy-autotrain''s data'; Keep := 1;")) -join "`n"
            $out | Should -Match 'Keep := 1;' -Because 'the machine must still be OUT of the string after the pair, or the rest of the line is swallowed'
        }

        It 'resumes code on the same line a multi-line comment closes' {
            $out = (Remove-InnoComments -Lines @('  { opened here', '    still comment }  if Wrote then')) -join "`n"
            $out | Should -Match 'if Wrote then'
            $out | Should -Not -Match 'still comment'
        }

        It 'with -BlankStrings, drops string BODIES and keeps the code around them' {
            # The second projection. Without it, a call named inside an operator message satisfies the
            # behavioural greps: MEASURED, flipping the append flag to False while leaving the True
            # form inside a recovery string passed 8/8.
            $line = @("  MigrationProblem('use SaveStringsToFile(NewPath, OldLines, True) by hand');")
            $kept = (Remove-InnoComments -Lines $line) -join "`n"
            $blank = (Remove-InnoComments -Lines $line -BlankStrings) -join "`n"
            $kept  | Should -Match 'SaveStringsToFile' -Because 'the default projection keeps string bodies, which the {app} control depends on'
            $blank | Should -Not -Match 'SaveStringsToFile' -Because 'the behavioural projection must not let a literal inside a string satisfy a code assertion'
            $blank | Should -Match 'MigrationProblem' -Because 'the CODE around the string must survive - blanking must not eat the call itself'
        }
    }

    It 'strips comments WITHOUT eating braces that live inside string literals' {
        # THE STRIPPER'S OWN CONTROL. It is string-aware precisely so that ExpandConstant's braces
        # survive; if that ever regresses, every path in the procedure silently loses its constant and
        # the ordering assertions below start comparing mangled lines.
        $code = $script:CodeOnly -join "`n"
        $code | Should -Match 'ExpandConstant' -Because 'the stripper must not remove real code'
        $code | Should -Match "\{app\}" -Because 'a brace inside a single-quoted string is NOT a comment and must survive stripping'
        $code | Should -Match "\{%USERPROFILE\}" -Because 'the same, for the user-state path constant'
        # And the inverse: a real comment must NOT survive. Every line of the file header block is one.
        $code | Should -Not -Match 'Roll the claim back so the source returns' -Because 'comment prose must be stripped, or a literal hidden in a comment satisfies these guards'
    }

    It "the PURGE branch deletes EXACTLY the user-data paths it promises, and only under the consent gate" {
        # This whole procedure is the only code in the product that deletes a user's captured
        # observations, and until 2026-08-26 NOTHING pinned which paths it touches: the suite was green
        # both before and after a path was ADDED to the destructive set. A deletion set with no census is
        # the same hole `Get-DrainOutputPaths` had - see drain-lib.Tests.ps1, where an identity pin
        # existed but had frozen a wrong value.
        #
        # Two properties are asserted, and they are different:
        #   1. the SET is exactly these five, in this order - so adding or losing one is visible;
        #   2. every one of them sits INSIDE `if RemoveGrowth then` - the consent gate. The comment in
        #      the .iss above these calls exists because a false claim once "invited exactly the
        #      misreading that would license moving these DeleteFile calls out of the gate". Nothing
        #      protects the user's data but that gate, so its scope is asserted, not assumed.
        $all = @(Get-Content -LiteralPath $script:IssPath)
        $procStart = -1
        for ($i = 0; $i -lt $all.Count; $i++) {
            if ($all[$i] -match '^procedure\s+CurUninstallStepChanged\s*\(') { $procStart = $i; break }
        }
        $procStart | Should -BeGreaterThan -1 -Because 'CurUninstallStepChanged must exist, or this scan is inspecting nothing'

        $procEnd = $all.Count
        for ($i = $procStart + 1; $i -lt $all.Count; $i++) {
            if ($all[$i] -match '^(procedure|function)\s') { $procEnd = $i; break }
        }
        $procBody = @(Remove-InnoComments -Lines $all[$procStart..($procEnd - 1)])

        # The gate opens at `if RemoveGrowth then` and closes at the `end;` that matches its `begin`.
        $gateAt = -1
        for ($i = 0; $i -lt $procBody.Count; $i++) {
            if ($procBody[$i] -match '^\s*if\s+RemoveGrowth\s+then\s*$') { $gateAt = $i; break }
        }
        $gateAt | Should -BeGreaterThan -1 -Because 'the consent gate must exist - without it every DeleteFile below runs on a KEEP uninstall'
        $gateBody = @(Get-BranchBody -Lines $procBody -HeadIndex $gateAt)
        $gateBody.Count | Should -BeGreaterThan 0 -Because 'the gate must have a body, or this scan is inspecting nothing'

        # 1. THE SET, pinned by identity and order.
        $deleted = @($gateBody | Where-Object { $_ -match 'DeleteFile\(' })
        $targets = @($gateBody | Where-Object { $_ -match '^\s*(GrowthFile|InboxFile)\s*:=' } |
                     ForEach-Object { ($_ -replace '^\s*(GrowthFile|InboxFile)\s*:=\s*', '') -replace ';\s*$', '' })
        $expected = @(
            "ExpandConstant('{%USERPROFILE}') + '\.clavity\agy-observations.md'"
            "ExpandConstant('{app}\plugins\agy-autotrain\knowledge\agy-observations.md.migrated-14g')"
            "ExpandConstant('{app}\plugins\agy-autotrain\knowledge\agy-observations.md')"
        )
        ($targets -join "`n") | Should -BeExactly ($expected -join "`n") -Because 'the destructive set must be pinned by identity and order - a path silently entering or leaving it is a user-data change nobody would see. The plain agy-observations.md is here because a failed migration ROLLS BACK to it, and without it a user who chose PURGE kept their whole backlog'

        # 2. EVERY delete is inside the gate. Counted against the procedure as a whole, so a call moved
        #    OUT of the gate reds here even though the set above would still look right.
        $allDeletes = @($procBody | Where-Object { $_ -match 'DeleteFile\(' })
        $deleted.Count | Should -Be $allDeletes.Count -Because 'every DeleteFile in this procedure must sit INSIDE the consent gate - one moved outside deletes a user''s observations on a KEEP uninstall, which is the exact misreading the comment above these calls was written to prevent'
        $deleted.Count | Should -Be 5 -Because 'growth, its .sha256, the canonical inbox, the migration sidecar, and the rolled-back plugin-folder copy - five deletions, and a count that drifts means the set changed'
    }

    It 'CLAIMS the source by rename BEFORE it writes anything' {
        # THE ORDERING INVARIANT. Pre-fold the procedure wrote first and renamed last, discarding the
        # rename's Boolean: a rename that failed after a successful write left the source in place, so
        # the next upgrade saw a non-empty destination, took the append branch, and appended every entry
        # AGAIN - unbounded, once per upgrade. Claiming first makes a crash between the two a clean
        # no-op that the next run retries from scratch.
        $claim = Find-BodyLine 'RenameFile(OldPath, Aside)'
        $copy  = Find-BodyLine 'FileCopy(Aside, NewPath'
        # SaveStringToFile (singular), not SaveStringsToFile: the append branch moves RAW BYTES now.
        # The plural, line-based pair decoded and RE-ENCODED - measured, a UTF-8 em-dash came back as
        # the Windows-1252 byte 97 and LF became CRLF, destroying non-ASCII observations while the
        # bullet count still matched. What this index protects is UNCHANGED: the claim must precede
        # the write.
        $save  = Find-BodyLine 'SaveStringToFile(NewPath, OldBytes'

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
        # NoStrings: a call named inside an operator-recovery message would otherwise satisfy these.
        # That is not a contrived channel - this branch's whole purpose is recovery prose.
        # A SIBLING SCAN OVER $script:CodeOnly WAS REMOVED HERE in 654b298, and that commit's own message
        # is misleading about it: it records "$branch was not dead" (a reviewer's refutation of an earlier
        # claim) in the same commit that deletes $branch. Both are true and the pairing reads as a
        # contradiction, so the record is corrected here rather than in the immutable message. It was
        # removed as REDUNDANT, not as dead: Remove-InnoComments appends exactly once per input line
        # (one `$result += $kept` per foreach iteration), and -BlankStrings only blanks characters INSIDE
        # string literals - it never touches the begin/end; tokens this scan bounds on. So CodeOnly and
        # CodeNoStrings always have identical line counts and identical branch boundaries, which made
        # $branch.Count and $branchNS.Count provably equal. Deleting a duplicate assertion costs no
        # coverage; deleting it silently cost a round of review, which is why this note exists.
        $branchNS = @(Get-BranchBody -Lines $script:CodeNoStrings -HeadIndex $notWrote)
        $branchNS.Count | Should -BeGreaterThan 0 -Because 'the write-failure branch must have a body, or this scan is inspecting nothing'
        ($branchNS -join "`n") | Should -Match 'RenameFile\(Aside, OldPath\)' -Because 'the rollback must live INSIDE the write-failure branch - placed after it, it fires on a SUCCESSFUL migration and re-arms the duplication defect'
        ($branchNS -join "`n") | Should -Match 'MigrationProblem' -Because 'the write-failure branch is the one failure path with no exit, so nothing else in this file forces it to tell the operator anything'
    }

    It 'APPENDS to a non-empty destination rather than clobbering it' {
        # SaveStringsToFile's third argument is the append flag. Flipping it to False destroys a newer
        # inbox at the destination - silently, and only for the user who already had one.
        # CodeOnly: this is a BEHAVIOURAL assertion, and against raw Body it was satisfiable by a
        # comment. MEASURED: flipping the real call to False and leaving
        # `{ was: SaveStringToFile(NewPath, OldBytes, True) }` beside it passed 7/7 while the migration
        # clobbered a populated destination.
        #
        # The CALL changed on 2026-08-26 and the PROPERTY did not. It was
        # SaveStringsToFile(NewPath, OldLines, True) - the line-based pair, which decodes and re-encodes:
        # MEASURED with a no-install probe installer, an em-dash went in as UTF-8 e2 80 94 and came out
        # as the Windows-1252 byte 97, and LF came out CRLF. The third argument is still the thing under
        # assertion: True means APPEND, and False would clobber a destination holding real captures.
        ($script:CodeNoStrings -join "`n") | Should -Match 'SaveStringToFile\(NewPath, OldBytes, True\)' -Because 'the append flag is what stops the migration clobbering a destination that already holds captures'
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
            'if not LoadStringFromFile(OldPath, OldBytes) then'
            'if FileExists(Aside) then'
            'if not RenameFile(OldPath, Aside) then'
        )
        $leaky = @()
        foreach ($g in $guards) {
            $i = Find-BodyLine $g
            # Present-FIRST. A renamed or deleted guard must red here, not vanish from the loop.
            $i | Should -BeGreaterThan -1 -Because "the pre-write guard '$g' must exist, or this scan is inspecting nothing"

            # CodeOnly, NOT Body. Repointing Find-BodyLine alone was an INCOMPLETE fix: this scan and
            # the one below still read raw lines, so the guard located the branch on a code line and
            # then accepted a COMMENT as its evidence. MEASURED: moving the report and the exit into an
            # Inno `{ }` comment inside the claim-failure branch passed 7/7 - the same mutant class the
            # comment-stripping was introduced to kill, surviving in the very test that introduced it.
            # BOUNDED BY THE GUARD'S OWN BRANCH. Scanning forward to "the next `end;` anywhere" was the
            # same borrowed-evidence defect this file already records fixing 12 lines below - a guard
            # that reads a NEIGHBOUR'S evidence certifies whatever sits next to it - re-opened through a
            # different channel. Pascal allows `if X then <single statement>;` with no `end;` of its
            # own (agy-autotrain.iss:151-152 is exactly that shape), so a gutted guard's scan ran on
            # into the NEXT branch and collected its report and its exit.
            # MEASURED: gutting any of the first THREE guards - replacing the whole begin...end with one
            # no-op - left BOTH scans clean. Only the fourth reddened, and even then it had borrowed the
            # rollback branch's MigrationProblem; only the missing exit saved it.
            # CodeNoStrings, not CodeOnly: a call named inside an operator message must not count as the
            # branch reporting. Both projections emit one entry per source line, so indices still align.
            $branchBody = @(Get-BranchBody -Lines $script:CodeNoStrings -HeadIndex $i)
            $reported = @($branchBody | Where-Object { $_ -match 'MigrationProblem' }).Count -gt 0
            $exited   = @($branchBody | Where-Object { $_ -match '^\s*exit\s*;' }).Count -gt 0
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
        # CodeOnly throughout, for the same reason as the scan above: a MigrationProblem mentioned in
        # a comment must not count as the branch reporting.
        $silent = @()
        $seenFirstExit = $false
        for ($i = 0; $i -lt $script:CodeOnly.Count; $i++) {
            if ($script:CodeOnly[$i] -notmatch '^\s*exit\s*;') { continue }
            if (-not $seenFirstExit) { $seenFirstExit = $true; continue }   # the nothing-to-do return

            $lo = -1
            for ($j = $i - 1; $j -ge 0; $j--) {
                if ($script:CodeOnly[$j] -match '^\s*begin\s*$') { $lo = $j; break }
                if ($script:CodeOnly[$j] -match '^\s*(end\s*;|exit\s*;)') { break }   # left the branch
            }
            $window = if ($lo -ge 0) { $script:CodeOnly[$lo..$i] -join "`n" } else { $script:CodeOnly[$i] }
            if ($window -notmatch 'MigrationProblem') { $silent += "body line $i : $($script:CodeOnly[$i].Trim())" }
        }
        $seenFirstExit | Should -BeTrue -Because 'the body must contain at least the nothing-to-do exit, or this scan matched nothing and proves nothing'
        ($silent -join '; ') | Should -BeNullOrEmpty -Because 'every failure exit must be preceded by a MigrationProblem call - a silent failed migration reads exactly like a successful one'
    }
}

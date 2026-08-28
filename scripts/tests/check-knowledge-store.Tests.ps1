#Requires -Modules Pester

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:Script   = Join-Path $script:RepoRoot 'scripts/check-knowledge-store.ps1'

    # Every case runs against a THROWAWAY GIT REPO, not the real tree. The deletion check compares
    # against a git baseline, so it cannot be exercised at all without a repo whose history the test
    # controls - and a failure path that cannot be exercised is indistinguishable from a vacuous one.
    function New-StoreFixture {
        $d = Join-Path ([System.IO.Path]::GetTempPath()) ("clavity-store-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $d 'rules') -Force | Out-Null
        Set-Content -NoNewline -Path (Join-Path $d 'rules/alpha.md') -Value "# alpha`n`n- ALPHA RULE.`n"
        Set-Content -NoNewline -Path (Join-Path $d 'rules/beta.md')  -Value "# beta`n`n- BETA RULE.`n"
        Set-Content -NoNewline -Path (Join-Path $d 'rules/INDEX.md') -Value "# store`n`n- [alpha](alpha.md) - a`n- [beta](beta.md) - b`n"
        & git -C $d init --quiet 2>$null
        & git -C $d config user.email t@t.invalid 2>$null
        & git -C $d config user.name  test          2>$null
        & git -C $d add -A 2>$null
        & git -C $d commit -q -m baseline 2>$null
        $d
    }
    # Add-Content appends with CRLF on Windows, which trips this gate's own LF hygiene check and makes a
    # fixture fail for a reason the row is not about. MEASURED: the space-in-filename row failed at
    # BASELINE for exactly that, while the gate passed the identical scenario when run by hand. Fixture
    # noise that looks like a real red is worse than no fixture at all - it sends you debugging the code.
    function Add-IndexLine([string]$Repo, [string]$Line) {
        $p = Join-Path $Repo 'rules/INDEX.md'
        [System.IO.File]::WriteAllText($p, [System.IO.File]::ReadAllText($p) + $Line + "`n")
    }
    function Invoke-Check([string]$Repo) {
        & pwsh -NoProfile -File $script:Script -RepoRoot $Repo -StoreDir 'rules' 2>&1 | Out-String
    }
}

Describe 'check-knowledge-store' {

    It 'PASSES a clean store' {
        $d = New-StoreFixture
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match '2 rule\(s\)'
        Remove-Item -Recurse -Force $d
    }

    # THE ROUND-6 FATAL FINDING. Coordinated deletion - removing the rule AND its index pointer - defeats
    # every topological check: no dangling pointer for mlc, nothing to enumerate for an orphan sweep. Only
    # a git baseline sees it. This row is the whole reason the script consults git at all.
    It 'FAILS when a rule file is deleted, even with its index pointer removed too' {
        $d = New-StoreFixture
        Remove-Item (Join-Path $d 'rules/beta.md')
        Set-Content -NoNewline -Path (Join-Path $d 'rules/INDEX.md') -Value "# store`n`n- [alpha](alpha.md) - a`n"
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'DELETED: beta\.md'
        Remove-Item -Recurse -Force $d   # this row alone leaked its fixture; every sibling cleans up
    }

    # CAPSTONE R1 / F2 - THE ROW THE ORIGINAL SUITE WAS MISSING, and its absence is what let the gate ship
    # broken. The row above proves an UNCOMMITTED deletion fails. MEASURED 2026-08-28, committing that same
    # deletion made it PASS (exit 0, "none deleted since HEAD"), because the tree baseline moves with the
    # commit. Every real deletion arrives committed, so the guard was decoration on the only path that
    # matters. The baseline is now the ref's HISTORY, which cannot move.
    It 'FAILS a deletion that has already been COMMITTED - the baseline must not move with it' {
        $d = New-StoreFixture
        Remove-Item (Join-Path $d 'rules/beta.md')
        Set-Content -NoNewline -Path (Join-Path $d 'rules/INDEX.md') -Value "# store`n`n- [alpha](alpha.md) - a`n"
        & git -C $d add -A 2>$null; & git -C $d commit -q -m 'retire beta' 2>$null
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'DELETED: beta\.md'
        Remove-Item -Recurse -Force $d
    }

    # CAPSTONE R1 / F3 - content obliteration. Zero bytes satisfies filename, link and hygiene checks
    # simultaneously (an empty file has no CRLF and no high bytes), so before this row the gate reported
    # "OK - 2 rule(s), all reachable, LF + pure ASCII" over a destroyed rule - every clause true.
    It 'FAILS a rule emptied to 0 bytes' {
        $d = New-StoreFixture
        [System.IO.File]::WriteAllBytes((Join-Path $d 'rules/beta.md'), [byte[]]@())
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'OBLITERATED: beta\.md'
        Remove-Item -Recurse -Force $d
    }

    It 'FAILS a rule gutted to a fraction of its size with no declaration' {
        $d = New-StoreFixture
        Set-Content -NoNewline -Path (Join-Path $d 'rules/beta.md') -Value "x`n"
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'GUTTED: beta\.md'
        Remove-Item -Recurse -Force $d
    }

    # THE PAIRED CONTROL, and the one that makes the row above mean something. The SAME reduction passes
    # once it declares itself. Without this, the gutting check could be passing merely because the file got
    # smaller, and it would trip every legitimate consolidation - the failure mode the design spec named.
    It 'PASSES the same reduction when it DECLARES itself retired' {
        $d = New-StoreFixture
        Set-Content -NoNewline -Path (Join-Path $d 'rules/beta.md') -Value "# beta`n`n> Superseded by [alpha](alpha.md)`n"
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match '2 rule\(s\)'
        Remove-Item -Recurse -Force $d
    }

    # CAPSTONE R2 - the SAME moving-baseline defect as the deletion check, in its sibling, missed when that
    # one was fixed. MEASURED: committing the gutting made the previous size equal the current size, so the
    # ratio was 1.0 and the gate passed while printing "none gutted undeclared". The baseline is now the
    # file's HIGH-WATER MARK across history, which no commit can move.
    It 'FAILS a gutting that has already been COMMITTED' {
        $d = New-StoreFixture
        Set-Content -NoNewline -Path (Join-Path $d 'rules/beta.md') -Value "x`n"
        & git -C $d add -A 2>$null; & git -C $d commit -q -m 'gut beta' 2>$null
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'GUTTED: beta\.md'
        Remove-Item -Recurse -Force $d
    }

    It 'PASSES a COMMITTED reduction that declares itself retired' {
        $d = New-StoreFixture
        Set-Content -NoNewline -Path (Join-Path $d 'rules/beta.md') -Value "# beta`n`n> Retired: folded into alpha`n"
        & git -C $d add -A 2>$null; & git -C $d commit -q -m 'retire beta' 2>$null
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match '2 rule\(s\)'
        Remove-Item -Recurse -Force $d
    }

    # CAPSTONE R3 - the gate must REFUSE to certify what it cannot see. MEASURED on a real
    # `git clone --depth 1`: a committed deletion was invisible and the gate reported every rule still
    # present, which is a false statement rather than a merely unhelpful one. actions/checkout is shallow
    # BY DEFAULT, so the CI wiring added one commit earlier was certifying a store it could not inspect.
    # The workflow now deepens history, but a gate must not depend on its caller remembering that.
    It 'FAILS CLOSED on a shallow repository instead of certifying blind' {
        $d = New-StoreFixture
        # A second commit, so a shallow clone genuinely truncates something.
        Set-Content -NoNewline -Path (Join-Path $d 'rules/alpha.md') -Value "# alpha`n`n- ALPHA REVISED.`n"
        & git -C $d add -A 2>$null; & git -C $d commit -q -m second 2>$null
        $sh = Join-Path ([System.IO.Path]::GetTempPath()) ("clavity-shallow-" + [guid]::NewGuid().ToString('N'))
        & git -c core.autocrlf=false clone -q --depth 1 "file://$($d -replace '\\','/')" $sh 2>$null
        $out = & pwsh -NoProfile -File $script:Script -RepoRoot $sh -StoreDir 'rules' 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'SHALLOW repository'
        Remove-Item -Recurse -Force $d, $sh -ErrorAction SilentlyContinue
    }

    # The paired control for the row above - without it, "fails closed" could just mean "always fails",
    # and no other row in this suite clones at all.
    It 'PASSES a FULL clone of that same repository' {
        $d = New-StoreFixture
        Set-Content -NoNewline -Path (Join-Path $d 'rules/alpha.md') -Value "# alpha`n`n- ALPHA REVISED.`n"
        & git -C $d add -A 2>$null; & git -C $d commit -q -m second 2>$null
        $fu = Join-Path ([System.IO.Path]::GetTempPath()) ("clavity-full-" + [guid]::NewGuid().ToString('N'))
        & git -c core.autocrlf=false clone -q $d $fu 2>$null
        $out = & pwsh -NoProfile -File $script:Script -RepoRoot $fu -StoreDir 'rules' 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match '2 rule\(s\)'
        Remove-Item -Recurse -Force $d, $fu -ErrorAction SilentlyContinue
    }

    # A ROW WAS DELETED HERE IN CAPSTONE ROUND 7, and the deletion is the point rather than a tidy-up.
    #
    # It was called "does not trap a rule against its all-time peak once a retirement is DECLARED", and its
    # comment asserted that a declared consolidation RE-BASELINES the high-water mark and that "only a
    # DECLARED retirement moves the mark". Round 4 DELETED that re-baselining mechanism outright - it
    # turned out to have no legitimate case and to be reachable only by abuse (declare, then silently
    # remove the declaration). The row kept passing afterwards, but for a completely different reason than
    # its comment gave: the file carries a `> Retired:` line, so the declaration guard passes it whatever
    # the size ratio is. That made it an exact duplicate of "PASSES a COMMITTED reduction that declares
    # itself retired" above, wearing a rationale for code that no longer exists.
    #
    # A capstone round auditing CLAIMS rather than logic found it - the only finding in 26 checked. Keeping
    # a test whose stated reason was deleted is how a suite starts asserting a design nobody ships, and a
    # future round would have folded against that comment believing the mechanism was still there.

    # CAPSTONE R4 - THE GATE MUST SURVIVE A FRESH CHECKOUT, which is the only kind CI ever has.
    # MEASURED on a default `git clone` of this repository BEFORE the fix: 19 of 19 rule files came out
    # CRLF and the gate reported 19 problems, because `git check-attr` said `unspecified` and core.autocrlf
    # converted them. The files are LF in a working tree only until git re-materialises them.
    #
    # This asserts the CAUSE - what git itself will do on checkout - rather than cloning the whole monorepo
    # per run. check-attr is not a proxy for that question; it is the same computation git performs.
    #
    # The second path is the one that matters long-term: it is a rule file that DOES NOT EXIST, so it
    # proves the PATTERN covers rules added in future, not merely the 19 that happen to be there today.
    It 'pins the store to LF on checkout, including rules that do not exist yet' {
        foreach ($p in @('agy-autotrain/knowledge/rules/INDEX.md',
                         'agy-autotrain/knowledge/rules/a-rule-nobody-has-written-yet.md')) {
            $out = (& git -C $script:RepoRoot check-attr text eol -- $p) -join ' '
            $out | Should -Match 'text: set'
            $out | Should -Match 'eol: lf'
        }
    }

    # CAPSTONE R4 - the hole I built in round 3 and asked the peer to find. A round-3 "fix" let the most
    # recent commit carrying a declaration re-baseline the high-water mark. MEASURED: declare a retirement
    # in one commit, silently delete the declaration line in the next, and a rule went 1,209 bytes -> 12
    # with the gate reporting OK. The re-baseline is gone; the mark is never moved by anything.
    It 'FAILS a gutting laundered through a declaration that was then REMOVED' {
        $d = New-StoreFixture
        # The shared fixture's beta is only ~26 bytes, so a drop to 13 is 50% and legitimately above the
        # floor - the first version of this row failed for that reason, not because the fix was wrong.
        # Give it real bulk first, so the later reduction is unambiguously a gutting.
        Set-Content -NoNewline -Path (Join-Path $d 'rules/beta.md') `
            -Value ("# beta`n`n" + ("- BETA RULE, a long hard-won paragraph. " * 30) + "`n")
        & git -C $d add -A 2>$null; & git -C $d commit -q -m 'beta grows' 2>$null
        Set-Content -NoNewline -Path (Join-Path $d 'rules/beta.md') -Value "# beta`n`n> Retired: folded`n"
        & git -C $d add -A 2>$null; & git -C $d commit -q -m declare 2>$null
        Set-Content -NoNewline -Path (Join-Path $d 'rules/beta.md') -Value "# beta`n`n- x`n"
        & git -C $d add -A 2>$null; & git -C $d commit -q -m 'drop the declaration' 2>$null
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'GUTTED: beta\.md'
        Remove-Item -Recurse -Force $d
    }

    # CAPSTONE R4 - git QUOTES a path containing a non-ASCII byte by default, so the deletion of such a
    # rule was invisible: MEASURED, the path arrived as a double-quoted, octal-escaped string, failed the
    # prefix filter, never entered the baseline, and the gate reported "all present". Reading is fixed with
    # core.quotePath=false; the name is now forbidden outright as well, since the store is ASCII by policy.
    It 'CATCHES the deletion of a rule whose filename is not ASCII' {
        $d = New-StoreFixture
        $odd = Join-Path $d ("rules/" + [char]0x00FC + "ber.md")
        [System.IO.File]::WriteAllText($odd, "# u`n`n- RULE.`n")
        Add-IndexLine $d ("- [u](" + [char]0x00FC + "ber.md) - u")
        & git -C $d add -A 2>$null; & git -C $d commit -q -m 'add an odd name' 2>$null
        Remove-Item -LiteralPath $odd
        Set-Content -NoNewline -Path (Join-Path $d 'rules/INDEX.md') -Value "# store`n`n- [alpha](alpha.md) - a`n- [beta](beta.md) - b`n"
        # THE DELETION MUST BE COMMITTED, and a mutation audit is what proved it. An earlier version of
        # this row deleted the file from disk only, so HEAD's TREE still held it and `ls-tree` supplied the
        # baseline - meaning the row passed without ever exercising the `git log` history path this test
        # exists to guard. MEASURED: removing core.quotePath=false from the log read turned NO test red.
        # Committing the deletion removes it from the tree, so only history can see it, and the quoted-path
        # bug is then the only thing standing between this row and a false pass.
        & git -C $d add -A 2>$null; & git -C $d commit -q -m 'delete the odd name' 2>$null
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'DELETED'
        Remove-Item -Recurse -Force $d
    }

    # CAPSTONE R5 - added because a MUTATION AUDIT proved the guard had NO test: disabling the non-ASCII
    # filename check left the whole suite green. The check shipped in round 4 with nothing covering it,
    # which is precisely the question the guard law says to ask - "which test goes red if I delete this,
    # or none?" - and the answer was none.
    #
    # Note this row keeps the file PRESENT. The sibling row about a non-ASCII name deletes it and asserts
    # DELETED, so it exercises the git-history read instead; between them the two directions are covered.
    It 'FAILS a rule whose FILENAME is not ASCII, while it is still present' {
        $d = New-StoreFixture
        $odd = Join-Path $d ("rules/" + [char]0x00FC + "ber.md")
        [System.IO.File]::WriteAllText($odd, "# u`n`n- RULE.`n")
        Add-IndexLine $d ("- [u](" + [char]0x00FC + "ber.md) - u")
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'NON-ASCII NAME'
        Remove-Item -Recurse -Force $d
    }

    # CAPSTONE R6 - the FALSE-ALARM direction of the orphan check. MEASURED: the old link pattern
    # `[A-Za-z0-9_.-]+\.md` did not match `my rule.md`, so a rule that WAS correctly linked from the index
    # was reported as an ORPHAN. Nothing forbids a space in a rule filename, and a checker that cries wolf
    # is ignored within a week. This is the row that goes red if the pattern is ever narrowed again.
    It 'does NOT report an orphan for a linked rule whose filename contains a space' {
        $d = New-StoreFixture
        Set-Content -NoNewline -Path (Join-Path $d 'rules/my rule.md') -Value "# my rule`n`n- RULE.`n"
        Add-IndexLine $d '- [my rule](my rule.md) - m'
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match '3 rule\(s\)'
        Remove-Item -Recurse -Force $d
    }

    It 'FAILS an orphan - a rule on disk that the index does not link' {
        $d = New-StoreFixture
        Set-Content -NoNewline -Path (Join-Path $d 'rules/gamma.md') -Value "# gamma`n`n- GAMMA.`n"
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'ORPHAN: gamma\.md'
    }

    # The code-span strip is not cosmetic: on a sibling corpus, bracketed tokens inside backticks
    # produced 2 of 11 false positives. Here the inverse is asserted - a link that exists ONLY inside a
    # code span must NOT count as reachability, or the strip is silently doing nothing.
    It 'does NOT count a link that appears only inside a code span' {
        $d = New-StoreFixture
        Set-Content -NoNewline -Path (Join-Path $d 'rules/gamma.md') -Value "# gamma`n`n- GAMMA.`n"
        Add-IndexLine $d "Example of the link syntax: ``[gamma](gamma.md)``"
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'ORPHAN: gamma\.md'
    }

    It 'FAILS on a CRLF rule file' {
        $d = New-StoreFixture
        [System.IO.File]::WriteAllBytes((Join-Path $d 'rules/alpha.md'), [byte[]](0x2D,0x20,0x41,0x0D,0x0A))
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'CRLF: alpha\.md'
    }

    # Pure ASCII is inherited from the GROWTH region these rules were split out of: that region is
    # published through a byte transport which corrupted it once, with a sha256 sidecar that matched the
    # CORRUPT content and therefore certified it.
    It 'FAILS on a non-ASCII byte' {
        $d = New-StoreFixture
        [System.IO.File]::WriteAllBytes((Join-Path $d 'rules/alpha.md'), [byte[]](0x2D,0x20,0xE2,0x80,0x94,0x0A))
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'NON-ASCII: alpha\.md'
    }

    It 'FAILS when INDEX.md is missing - an unindexed store is a pile of files' {
        $d = New-StoreFixture
        Remove-Item (Join-Path $d 'rules/INDEX.md')
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'NO INDEX'
    }

    It 'SKIPS cleanly when there is no store directory at all' {
        $d = Join-Path ([System.IO.Path]::GetTempPath()) ("clavity-nostore-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'SKIP'
        Remove-Item -Recurse -Force $d
    }
}

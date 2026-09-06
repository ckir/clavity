# Tests for the shipped ledger reader, clavity-dotnet/plugin/hooks/agy-ledger-lib.sh (ROADMAP section 27).
#
# The reader is SOURCED by agy-mark.sh and answers a string; it never exits. These rows exercise it
# through a one-line bash driver inside a throwaway git repo, because its answers depend on REAL commits:
# it resolves ledger tokens through `git rev-parse`, so a fixture with no objects could not tell a
# correct resolution from a failed one.
Describe 'agy-ledger-lib.sh' {
    BeforeAll {
        $script:Fixtures = New-Object System.Collections.ArrayList   # FIXTURE HYGIENE
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Lib = (Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-ledger-lib.sh') -replace '\\','/'
        Test-Path -LiteralPath $script:Lib | Should -BeTrue

        # PIN GIT BASH. Bare `bash` is NON-DETERMINISTIC on this host: it resolves to the WSL stub
        # (C:\WINDOWS\system32\bash.exe), which cannot run a Windows-path script, and every row then
        # fails with exit 127 saying nothing whatever about the file under test. The sibling suites all
        # route through this helper for exactly that reason - see agy-mark.Tests.ps1's own note.
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $script:Bash = Get-GitBashOrThrow

        # Ledger bodies live here, NOT at Describe scope. Pester 5 runs Discovery and Run in separate
        # phases and a variable assigned during Discovery is invisible inside an It body; $script:
        # variables assigned in BeforeAll are visible, which is why every sibling suite uses this shape.
        $script:GoodLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..<<SHORT>>` | 1 | GREEN | fold `deadbee` |
'@
        $script:NoMatchLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..bbbbbbb` | 1 | GREEN | fold `deadbee` |
'@
        # A record that parses AND resolves AND is not the target: the only shape that isolates the
        # header row from the noise a fabricated sha would add.
        $script:ResolvableNoMatchLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..<<PREV>>` | 1 | GREEN | fold `deadbee` |
'@
        # The sha sits ONLY in the evidence column. This is the C1 false pass the design exists to
        # close: fold-commit shas live in evidence prose, and a whole-file grep would authenticate them.
        $script:EvidenceOnlyLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..bbbbbbb` | 1 | GREEN | fold `<<FULL>>` |
'@
        # A 3-column table, as the real capstone ledger carries. Too few fields to be a record.
        $script:AnomalyTableLedger = @'
# ledger

| n | anomaly |
|---|---------|
| 1 | <<SHORT>> |

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..bbbbbbb` | 1 | GREEN | fold `deadbee` |
'@
        # A second range quoted in the cell's trailing prose, as docs/agy-capstone-ledger.md:69-70 do.
        $script:TrailingProseLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..bbbbbbb` (the folds run ccccccc..<<SHORT>>) | 1 | GREEN | fold `deadbee` |
'@
        # CAPSTONE ROUND 1, the BLOCKING finding. A table row QUOTED inside a fenced code block - which
        # these ledgers do routinely, to show what a row looked like before a fold. awk has no notion of
        # markdown block scope, so before the fence guard this answered FOUND for a sha appearing
        # NOWHERE else in the file: the C1 false pass returning through a channel field-3 never covered.
        $script:FencedQuoteLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..<<PREV>>` | 1 | GREEN | e |

An earlier row, quoted here to explain a fold:

```
| 2026-01-01 | `ccccccc..<<SHORT>>` | 1 | GREEN | e |
```
'@
        # CAPSTONE ROUND 1. A range written as a markdown link. Backticks were stripped, brackets were
        # not, so the token failed the hex test and a perfectly good record became UNPARSEABLE - a false
        # REFUSAL rather than a false pass, but a refusal of a legitimate run all the same.
        $script:LinkedRangeLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | [aaaaaaa..<<SHORT>>](https://example.invalid/x) | 1 | GREEN | e |
'@
        # CAPSTONE ROUND 2. Three ways the round-1 fence guard - a bare toggle on ``` only - was wrong.
        # (b) A TILDE fence is valid CommonMark and was not matched at all.
        $script:TildeFenceLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..<<PREV>>` | 1 | GREEN | e |

~~~
| 2026-01-01 | `ccccccc..<<SHORT>>` | 1 | GREEN | e |
~~~
'@
        # (c) A NESTED fence toggled the guard back OFF, re-exposing its own contents. A fence closes
        # only with the SAME character and at least the same run length.
        $script:NestedFenceLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..<<PREV>>` | 1 | GREEN | e |

````
```
| 2026-01-01 | `ccccccc..<<SHORT>>` | 1 | GREEN | e |
```
````
'@
        # (a) The worst of the three, and worse than the defect it repaired: an UNCLOSED fence hid every
        # row BELOW it - and rows are appended at the bottom, so it hid the live set while the refusal
        # blamed a missing row.
        $script:UnclosedFenceLedger = @'
# ledger

```
an example that was never closed

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..<<SHORT>>` | 1 | GREEN | e |
'@
        # A REFERENCE-style link. Deleting brackets outright merged the range and the label into one
        # token whose right endpoint was still valid hex - a WRONG answer rather than a refused one.
        $script:RefLinkLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | [aaaaaaa..<<SHORT>>][1] | 1 | GREEN | e |

[1]: https://example.invalid/x
'@
        # CAPSTONE ROUND 3. An INFO STRING on a line inside a fence. CommonMark allows an info string on
        # an OPENING fence and forbids one on a CLOSER, so ```bash sitting inside a block is content. A
        # closer-blind tracker treated it as the close, the REAL closer re-opened the fence, and the file
        # ended open - reporting MALFORMED on a perfectly valid ledger.
        $script:InfoStringFenceLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..<<PREV>>` | 1 | GREEN | e |

```
how to write a fence:
```bash
echo hi
```
'@
        # CAPSTONE ROUND 3. PADDED brackets. The first trim ran before the bracket came off, so the split
        # hit a leading space as its first delimiter and returned an empty token.
        $script:PaddedBracketLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | [ aaaaaaa..<<SHORT>> ] | 1 | GREEN | e |
'@
        # CAPSTONE ROUND 3's UNFILED CENSUS ITEMS. Two prose channels the peer named only in its census
        # and never filed as findings - both MEASURED false passes, and both the same class as round 1's
        # BLOCKING defect. Finding five channels in that class is what met the spec's own reversal
        # condition and produced the contiguous-table-block rule. That rule ends the ORPHAN-ROW class,
        # NOT the container class - the two rows at the end of this file pin what it still accepts.
        $script:PreBlockLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|---|---|---|---|---|
| 2026-09-06 | `aaaaaaa..<<PREV>>` | 1 | GREEN | e |

<pre>
| 2026-01-01 | `ccccccc..<<SHORT>>` | 1 | GREEN | e |
</pre>
'@
        $script:LazyQuoteLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|---|---|---|---|---|
| 2026-09-06 | `aaaaaaa..<<PREV>>` | 1 | GREEN | e |

> quoting an old row:
| 2026-01-01 | `ccccccc..<<SHORT>>` | 1 | GREEN | e |
'@
        # ACCEPTED LIMITATION, OWNER-RULED 2026-09-07. A COMPLETE table inside a container that preserves
        # leading pipes is itself a contiguous run containing a separator, so it satisfies the block rule
        # exactly. These two rows PIN that, so closing it later is a DELIBERATE decision and not a silent
        # drift. It is accepted because every such case required the row to be WRITTEN, and this gate
        # defends against FORGETTING one.
        $script:DivTableLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|---|---|---|---|---|
| 2026-09-06 | `aaaaaaa..<<PREV>>` | 1 | GREEN | e |

<div>
| date | range | rounds | verdict | evidence |
|---|---|---|---|---|
| 2026-01-01 | `ccccccc..<<SHORT>>` | 1 | GREEN | e |
</div>
'@
        # The LAZY half: only the FIRST line carries the quote marker, so every following line begins with
        # a pipe. Contrast the fully-quoted form, where every line carries it and the rule DOES reject it.
        $script:LazyTableLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|---|---|---|---|---|
| 2026-09-06 | `aaaaaaa..<<PREV>>` | 1 | GREEN | e |

> | date | range | rounds | verdict | evidence |
|---|---|---|---|---|
| 2026-01-01 | `ccccccc..<<SHORT>>` | 1 | GREEN | e |
'@
        $script:FullyQuotedTableLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|---|---|---|---|---|
| 2026-09-06 | `aaaaaaa..<<PREV>>` | 1 | GREEN | e |

> | date | range | rounds | verdict | evidence |
> |---|---|---|---|---|
> | 2026-01-01 | `ccccccc..<<SHORT>>` | 1 | GREEN | e |
'@
        # CAPSTONE ROUND 4. A FENCE INTERRUPTING A LIVE TABLE. The fence rule runs BEFORE the block rule
        # and ends in `next`, which jumped straight over the block reset - so an authorised table was
        # carried ACROSS the fence and the orphan pipe-line below it answered FOUND, though markdown
        # renders that line as literal text and not a row. The target sha appears NOWHERE else here.
        $script:FenceInTableLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|---|---|---|---|---|
| 2026-09-06 | `aaaaaaa..<<PREV>>` | 1 | GREEN | e |
```text
illustrative
```
| 2026-01-01 | `ccccccc..<<SHORT>>` | 1 | GREEN | e |
'@
        # A range endpoint that is a pure-hex BRANCH NAME. `git rev-parse` resolves any ref, so this
        # authenticated a marker for whatever the branch pointed at - a moving target validating a fixed
        # claim. The fixture creates a branch literally named `deadbeef`.
        $script:HexBranchLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|---|---|---|---|---|
| 2026-09-06 | `aaaaaaa..deadbeef` | 1 | GREEN | e |
'@
        # A record whose range is PROSE, as three real historical rows are.
        $script:ProseRangeLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-07-25 | SP-B agy-capstone skill | 4 | GREEN | folds `deadbee` |
'@

        function New-LedgerRepo {
            param([string]$LedgerBody, [string]$Discipline = 'agy-capstone', [switch]$HexBranch)
            $d = Join-Path ([IO.Path]::GetTempPath()) ("aglfx-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            [void]$script:Fixtures.Add($d)   # FIXTURE HYGIENE
            & git -C $d init -q
            & git -C $d config user.email t@t.t
            & git -C $d config user.name t
            # FIXTURE HYGIENE: never inherit the host's settings. autocrlf would rewrite the ledger's
            # line endings under us, and quotepath governs how git hands paths back.
            & git -C $d config core.autocrlf false
            & git -C $d config core.quotepath true
            # TWO commits, and the second one matters. A fixture with only one commit cannot express
            # "this row parses AND resolves, but is not the sha we are looking for" - every non-target
            # range has to cite a fabricated sha, which does not resolve and is therefore counted as
            # unparsed. That conflation hid a real distinction the first draft of this suite asserted
            # wrongly. <<PREV>> is a REAL earlier commit; <<SHORT>>/<<FULL>> are the target.
            [IO.File]::WriteAllText((Join-Path $d 'seed.txt'), "seed`n")
            & git -C $d add seed.txt
            & git -C $d commit -q -m seed
            $prev = (& git -C $d rev-parse HEAD).Trim()
            [IO.File]::WriteAllText((Join-Path $d 'seed2.txt'), "seed2`n")
            & git -C $d add seed2.txt
            & git -C $d commit -q -m seed2
            $sha = (& git -C $d rev-parse HEAD).Trim()
            # A branch whose NAME is 8 hex characters. git rev-parse resolves refs as happily as shas.
            if ($HexBranch) { & git -C $d branch deadbeef 2>&1 | Out-Null }
            New-Item -ItemType Directory -Force -Path (Join-Path $d 'docs') | Out-Null
            $body = $LedgerBody.Replace('<<SHORT>>', $sha.Substring(0, 7)).
                                Replace('<<FULL>>', $sha).
                                Replace('<<PREV>>', $prev.Substring(0, 7))
            [IO.File]::WriteAllText((Join-Path $d "docs/$Discipline-ledger.md"), ($body -replace "`r`n", "`n"))
            [pscustomobject]@{ Dir = $d; Sha = $sha; Prev = $prev }
        }

        function Invoke-Lookup {
            param([string]$Cwd, [string]$Discipline, [string]$Sha)
            # A driver script rather than `bash -c`: it keeps PowerShell quoting out of the shell layer,
            # and it is written with LF endings because Git Bash will not run a CRLF script cleanly.
            $driver = Join-Path $Cwd 'run-lookup.sh'
            $text = ". '$script:Lib'`n" +
                    "agy_ledger_lookup `"`$PWD`" '$Discipline' '$Sha'`n" +
                    "printf ' rc=%s' `"`$?`"`n"
            [IO.File]::WriteAllText($driver, ($text -replace "`r`n", "`n"))
            $outF = Join-Path ([IO.Path]::GetTempPath()) ("agl-" + [guid]::NewGuid().ToString('N') + ".out")
            $errF = "$outF.err"
            try {
                $p = Start-Process -FilePath $script:Bash -ArgumentList @('run-lookup.sh') -WorkingDirectory $Cwd `
                        -RedirectStandardOutput $outF -RedirectStandardError $errF -NoNewWindow -Wait -PassThru
                $out = (Get-Content -Raw -LiteralPath $outF -ErrorAction SilentlyContinue)
                $err = (Get-Content -Raw -LiteralPath $errF -ErrorAction SilentlyContinue)
                [pscustomobject]@{ ExitCode = $p.ExitCode; Out = "$out"; Err = "$err" }
            } finally {
                Remove-Item -LiteralPath $outF, $errF -Force -ErrorAction SilentlyContinue
            }
        }
    }

    AfterAll {
        # FIXTURE HYGIENE: -Force because a git repo carries read-only objects on Windows.
        foreach ($f in $script:Fixtures) { Remove-Item -LiteralPath $f -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'answers FOUND when a row records the sha as its range right-endpoint' {
        $r = New-LedgerRepo -LedgerBody $script:GoodLedger
        (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Match 'FOUND'
    }

    It 'answers ABSENT when no row records the sha' {
        $r = New-LedgerRepo -LedgerBody $script:NoMatchLedger
        (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Match 'ABSENT'
    }

    It 'answers NO-LEDGER when the discipline owns no ledger file' {
        $r = New-LedgerRepo -LedgerBody $script:GoodLedger
        (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-first' -Sha $r.Sha).Out | Should -Match 'NO-LEDGER'
    }

    It 'does NOT match a sha that appears only in the evidence column' {
        $r = New-LedgerRepo -LedgerBody $script:EvidenceOnlyLedger
        (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Match 'ABSENT'
    }

    It 'ignores a 3-column table, which has too few fields to be a record' {
        $r = New-LedgerRepo -LedgerBody $script:AnomalyTableLedger
        (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Match 'ABSENT'
    }

    It 'ignores tokens after the first, so a range quoted in the cell prose does not match' {
        $r = New-LedgerRepo -LedgerBody $script:TrailingProseLedger
        (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Match 'ABSENT'
    }

    It 'counts a prose-ranged record as unparsed and reports its line number' {
        # unparsed is a COUNT; lines carries the LINE NUMBERS. The fixture's prose row is the file's
        # 5th line, so the answer is `unparsed=1 lines=5`. Assert BOTH - conflating them was a real
        # defect in the first draft of this suite.
        $r = New-LedgerRepo -LedgerBody $script:ProseRangeLedger
        $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out
        $out | Should -Match 'unparsed=1'
        $out | Should -Match 'lines=5'
    }

    It 'does not count the header row as an unparsed record' {
        # Without a date-shape test on the date column, the header is a candidate whose range token is
        # the word 'range' - reported as unparseable on every single run. MEASURED against the real
        # ledgers: the date test yields 40 records / 6 non-records in the capstone ledger.
        #
        # The fixture's one record cites a REAL earlier commit, so it parses AND resolves AND does not
        # match. That is the only shape that isolates the header: a row citing a fabricated sha would
        # itself count as unparsed and mask what this row is asserting.
        $r = New-LedgerRepo -LedgerBody $script:ResolvableNoMatchLedger
        $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out
        $out | Should -Match 'ABSENT'
        $out | Should -Match 'unparsed=0'
    }

    It 'counts a record whose endpoint parses but does not RESOLVE as unparsed' {
        # A distinct failure from a prose range: the token is well-formed hex and git still cannot find
        # it. Both are unusable to the gate, and both are worth naming in a refusal.
        $r = New-LedgerRepo -LedgerBody $script:NoMatchLedger
        $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out
        $out | Should -Match 'ABSENT'
        $out | Should -Match 'unparsed=1'
    }

    It 'ignores a pipe-row quoted inside a fenced code block' {
        # CAPSTONE ROUND 1, BLOCKING. Measured before the fix: this exact fixture answered FOUND for a
        # sha present only inside the fence. The row outside the fence cites a real earlier commit, so
        # it parses and resolves and simply does not match - which is what isolates the fence.
        $r = New-LedgerRepo -LedgerBody $script:FencedQuoteLedger
        $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out
        $out | Should -Match 'ABSENT' -Because 'a quoted row inside a fence is prose, not a ledger record'
        $out | Should -Not -Match 'FOUND'
    }

    It 'parses a range wrapped in markdown link brackets' {
        # CAPSTONE ROUND 1. Before the bracket strip this answered ABSENT unparsed=1 - a legitimate
        # record refused because of its markup.
        $r = New-LedgerRepo -LedgerBody $script:LinkedRangeLedger
        (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Match 'FOUND'
    }

    It 'a record for a DIFFERENT sha does not authenticate this one' {
        # This pins the measurement that REFUTED capstone round 1's claim that an old row falsely
        # authenticates a new run. The gate's contract is per-SHA: a row for an earlier commit answers
        # ABSENT for a later one. At an UNCHANGED sha the marker is already that sha, so a same-sha
        # re-run advances nothing - which is why the "stale row" has no consequence to exploit.
        $r = New-LedgerRepo -LedgerBody $script:ResolvableNoMatchLedger
        $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out
        $out | Should -Match 'ABSENT'
        $out | Should -Not -Match 'FOUND'
    }

    It 'ignores a pipe-row quoted inside a TILDE fence' {
        # CAPSTONE ROUND 2. `~~~` is valid CommonMark; the round-1 guard matched backticks only.
        $r = New-LedgerRepo -LedgerBody $script:TildeFenceLedger
        (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Not -Match 'FOUND'
    }

    It 'a NESTED fence does not re-expose its own contents' {
        # CAPSTONE ROUND 2. A bare toggle flipped OFF at the inner fence. A fence closes only with the
        # same character and at least the same run length.
        $r = New-LedgerRepo -LedgerBody $script:NestedFenceLedger
        (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Not -Match 'FOUND'
    }

    It 'reports an UNCLOSED fence as MALFORMED rather than as a missing row' {
        # CAPSTONE ROUND 2, BLOCKING, and the defect was introduced by round 1's own fix. An unclosed
        # fence hides every row below it; rows are appended at the BOTTOM, so it hides the live set. The
        # answer must name the real cause - "does not record <sha>" sends the operator hunting for a row
        # that is present and merely invisible.
        $r = New-LedgerRepo -LedgerBody $script:UnclosedFenceLedger
        $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out
        $out | Should -Match 'MALFORMED'
        $out | Should -Match 'unclosed-code-fence'
        $out | Should -Not -Match 'FOUND'
    }

    It 'parses a range wrapped in a REFERENCE-style link' {
        # CAPSTONE ROUND 2. Deleting brackets merged `[range][1]` into `range1`, whose right endpoint is
        # still valid hex - so it resolved to the WRONG commit or to none. A wrong answer, not a refusal,
        # which is the worse of the two. Brackets are separators now, not noise.
        $r = New-LedgerRepo -LedgerBody $script:RefLinkLedger
        (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Match 'FOUND'
    }

    It 'an INFO STRING inside a fence does not falsely close it' {
        # CAPSTONE ROUND 3. Before the closer rule this answered MALFORMED on a valid file: the tracker
        # closed on ```bash, the real closer re-opened, and the fence was open at EOF. A closing fence
        # carries no info string; an opening one may.
        $r = New-LedgerRepo -LedgerBody $script:InfoStringFenceLedger
        $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out
        $out | Should -Not -Match 'MALFORMED' -Because 'the file is valid markdown and must not be called malformed'
        $out | Should -Not -Match 'FOUND'    -Because 'the quoted content is still not a record'
    }

    It 'parses a range in PADDED brackets' {
        # CAPSTONE ROUND 3. Order of operations, not regex: the first trim ran before the bracket came
        # off, so the split hit a leading space and returned an empty token, refusing a good row.
        $r = New-LedgerRepo -LedgerBody $script:PaddedBracketLedger
        (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Match 'FOUND'
    }

    It 'ignores a row quoted inside an HTML pre block' {
        # Named in a census and never filed as a finding; MEASURED a false pass. Closed structurally by
        # the contiguous-table-block rule rather than by adding <pre> to a blacklist.
        $r = New-LedgerRepo -LedgerBody $script:PreBlockLedger
        (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Not -Match 'FOUND'
    }

    It 'ignores a row in a lazy-continuation blockquote' {
        # Same class, same census, also unfiled. A quoted row has no separator above it in its own block.
        $r = New-LedgerRepo -LedgerBody $script:LazyQuoteLedger
        (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Not -Match 'FOUND'
    }

    It 'ignores an orphan row after a fence that interrupts a live table' {
        # CAPSTONE ROUND 4, and the FENCE TRACKER was the smuggler: two guards that were documented as
        # independent were not, because the earlier one carried block state past the later one.
        # MEASURED FOUND before the fix, for a sha appearing nowhere else in the fixture.
        $r = New-LedgerRepo -LedgerBody $script:FenceInTableLedger
        $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out
        # ASSERT THE PROBE ANSWERED AT ALL. A broken library returns EMPTY, and empty satisfies a bare
        # -Not -Match vacuously - measured this very session, when an apostrophe inside the awk program
        # closed its quote and every negative row would still have passed.
        $out | Should -Match 'ABSENT' -Because 'an empty answer is a broken probe, not a refusal'
        $out | Should -Not -Match 'FOUND' -Because 'a fence ends the table block it interrupts'
    }

    It 'ACCEPTED LIMITATION: a complete table inside an HTML div still reads as live' {
        # Named in capstone round 4 PROSE and never filed as a finding, then MEASURED true. Kept as an
        # accepted limitation, so this row asserts the CURRENT behaviour deliberately. If it ever turns
        # red, someone closed the container class - which is a decision for the owner, not a bug fix.
        $r = New-LedgerRepo -LedgerBody $script:DivTableLedger
        (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out |
            Should -Match 'FOUND' -Because 'the block rule ends the orphan-row class, not the container class'
    }

    It 'ACCEPTED LIMITATION: a lazily-quoted complete table still reads as live' {
        # The lazy half. Only the FIRST line carries the quote marker.
        $r = New-LedgerRepo -LedgerBody $script:LazyTableLedger
        (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out |
            Should -Match 'FOUND' -Because 'every line after the first begins with a pipe, so the run is contiguous'
    }

    It 'a FULLY quoted table - every line marked - is still correctly ignored' {
        # The success-path counterpart: without it the two rows above would document a limitation with no
        # evidence that the rule rejects ANYTHING wrapped in the same container.
        $r = New-LedgerRepo -LedgerBody $script:FullyQuotedTableLedger
        $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out
        $out | Should -Match 'ABSENT' -Because 'an empty answer is a broken probe, not a refusal'
        $out | Should -Not -Match 'FOUND'
    }

    It 'refuses a range endpoint that is a hex-named BRANCH rather than a sha' {
        # git rev-parse resolves any ref. A branch named `deadbeef` pointing at HEAD authenticated a
        # marker for a commit the ledger never recorded - a moving target validating a fixed claim.
        # An abbreviated sha is always a prefix of its own full form; a ref name essentially never is.
        $r = New-LedgerRepo -LedgerBody $script:HexBranchLedger -HexBranch
        $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out
        $out | Should -Not -Match 'FOUND' -Because 'a branch name must not authenticate a marker'
        $out | Should -Match 'unparsed=1' -Because 'the row is a candidate whose endpoint is unusable'
    }

    It 'never exits the calling shell - it is sourced, not executed' {
        # A helper that called exit would kill agy-mark.sh mid-run. Prove the caller survives even on
        # the path that finds nothing to answer with.
        $r = New-LedgerRepo -LedgerBody $script:GoodLedger
        $res = Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-first' -Sha 'not-a-sha-at-all'
        $res.Out | Should -Match 'rc=0'
        $res.ExitCode | Should -Be 0
    }
}

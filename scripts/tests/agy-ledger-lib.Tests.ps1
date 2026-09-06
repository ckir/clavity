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
        # A record whose range is PROSE, as three real historical rows are.
        $script:ProseRangeLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-07-25 | SP-B agy-capstone skill | 4 | GREEN | folds `deadbee` |
'@

        function New-LedgerRepo {
            param([string]$LedgerBody, [string]$Discipline = 'agy-capstone')
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

    It 'never exits the calling shell - it is sourced, not executed' {
        # A helper that called exit would kill agy-mark.sh mid-run. Prove the caller survives even on
        # the path that finds nothing to answer with.
        $r = New-LedgerRepo -LedgerBody $script:GoodLedger
        $res = Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-first' -Sha 'not-a-sha-at-all'
        $res.Out | Should -Match 'rc=0'
        $res.ExitCode | Should -Be 0
    }
}

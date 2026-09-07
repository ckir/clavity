# Tests for the shipped ledger reader, clavity-dotnet/plugin/hooks/agy-ledger-lib.sh (ROADMAP section 27).
#
# The reader is SOURCED by agy-mark.sh and answers a string; it never exits. These rows exercise it
# through a one-line bash driver inside a throwaway git repo.
#
# WHAT CHANGED, AND WHY THIS SUITE IS SMALLER THAN THE ONE IT REPLACES. The reader used to be a ~200-line
# awk markdown parser, and most of the old rows exercised ITS INTERNALS - fence tracking, tilde and nested
# fences, info strings, contiguous-block state, CRLF, a `git rev-parse` round-trip per row. That machinery
# is gone; rows asserting it would now be asserting nothing. What survives is the CONTRACT: which shapes
# authenticate a marker, which do not, and whether a refusal names its cause. The two rows that matter
# most are new - a sha in EVIDENCE PROSE and a sha as a range's LEFT ENDPOINT both false-pass a cell-wide
# search, and both are pinned here against the REAL ledger as well as against fixtures.
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

        # --- shapes that MUST authenticate --------------------------------------------------------
        $script:RangeLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..<<SHORT>>` | 1 | GREEN | fold `deadbee` |
'@
        $script:BareLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `<<SHORT>>` | 1 | GREEN | fold `deadbee` |
'@
        $script:FullShaLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..<<FULL>>` | 1 | GREEN | fold `deadbee` |
'@
        $script:PaddedBracketLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | [ `aaaaaaa..<<SHORT>>` ] | 1 | GREEN | fold `deadbee` |
'@
        # Three spaces is still a table row under CommonMark; four makes it an indented code block.
        $script:Indent3Ledger = @'
# ledger

   | date | range | rounds | verdict | evidence |
   |------|-------|--------|---------|----------|
   | 2026-09-06 | `aaaaaaa..<<SHORT>>` | 1 | GREEN | fold `deadbee` |
'@
        $script:Indent4Ledger = @'
# ledger

    | date | range | rounds | verdict | evidence |
    |------|-------|--------|---------|----------|
    | 2026-09-06 | `aaaaaaa..<<SHORT>>` | 1 | GREEN | fold `deadbee` |
'@

        # --- shapes that MUST NOT authenticate ----------------------------------------------------
        # THE FOUNDING FALSE-PASS CLASS. Range cells legitimately carry further ranges in their trailing
        # prose, and the EVIDENCE column quotes fold shas constantly. A search that reads the whole line,
        # or the whole cell, authenticates a marker for a commit the ledger never recorded as reviewed.
        $script:EvidenceProseLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..bbbbbbb` | 1 | GREEN | the folds this round produced run `ccccccc..<<SHORT>>` |
'@
        # THE SECOND FALSE-PASS CLASS. The sha is the range's LEFT endpoint - where the work STARTED, not
        # the tip that was reviewed. It appears in the right column of the right row and still must not
        # authenticate anything.
        $script:LeftEndpointLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `<<SHORT>>..bbbbbbb` | 1 | GREEN | fold `deadbee` |
'@
        # The range is present and correct but is not the FIRST thing in its column.
        $script:NotFirstLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | see below: `aaaaaaa..<<SHORT>>` | 1 | GREEN | fold `deadbee` |
'@
        # The second column is not a date, so the line is not a record. This is also what excludes the
        # 3-column anomaly table that shares the real capstone ledger.
        $script:NoDateLedger = @'
# ledger

| kind | range | note |
|------|-------|------|
| anomaly | `aaaaaaa..<<SHORT>>` | not a capstone record |
'@
        $script:HeaderOnlyLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
'@

        function New-LedgerRepo {
            param([string]$LedgerBody, [string]$Discipline = 'agy-capstone', [string]$RawBody)
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
            [IO.File]::WriteAllText((Join-Path $d 'seed.txt'), "seed`n")
            & git -C $d add seed.txt
            & git -C $d commit -q -m seed
            $sha = (& git -C $d rev-parse HEAD).Trim()
            New-Item -ItemType Directory -Force -Path (Join-Path $d 'docs') | Out-Null
            # RawBody writes a ledger verbatim - used to plant a COPY of the real shipped ledger, whose
            # shas deliberately do NOT resolve in this throwaway repo. They do not need to: the reader
            # no longer asks git about ledger tokens at all, which is precisely what this proves.
            if ($RawBody) {
                $text = $RawBody
            } else {
                $text = $LedgerBody.Replace('<<SHORT>>', $sha.Substring(0, 7)).Replace('<<FULL>>', $sha)
            }
            [IO.File]::WriteAllText((Join-Path $d "docs/$Discipline-ledger.md"), ($text -replace "`r`n", "`n"))
            [pscustomobject]@{ Dir = $d; Sha = $sha }
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

    Context 'applicability - the gate is inert where no ledger exists' {
        It 'answers NO-LEDGER when the discipline owns no ledger file' {
            $r = New-LedgerRepo -LedgerBody $script:RangeLedger -Discipline 'agy-capstone'
            # Same repo, DIFFERENT discipline: the file for this one does not exist.
            $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-first' -Sha $r.Sha).Out
            $out | Should -Match 'NO-LEDGER'
            $out | Should -Not -Match 'ABSENT' -Because 'ABSENT claims a file was read; NO-LEDGER says the gate does not apply at all'
        }

        It 'answers NO-LEDGER when the ledger path is a DIRECTORY rather than a file' {
            $r = New-LedgerRepo -LedgerBody $script:RangeLedger
            Remove-Item -LiteralPath (Join-Path $r.Dir 'docs/agy-capstone-ledger.md') -Force
            New-Item -ItemType Directory -Force -Path (Join-Path $r.Dir 'docs/agy-capstone-ledger.md') | Out-Null
            (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Match 'NO-LEDGER'
        }
    }

    Context 'FOUND - the shapes a real ledger actually uses' {
        It 'authenticates a range whose RIGHT endpoint is the sha' {
            $r = New-LedgerRepo -LedgerBody $script:RangeLedger
            (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Match 'FOUND'
        }

        It 'authenticates a BARE endpoint with no range at all' {
            $r = New-LedgerRepo -LedgerBody $script:BareLedger
            (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Match 'FOUND'
        }

        It 'authenticates a row carrying the FULL 40-character sha' {
            # The gate is called with 40 characters and the ledger usually writes 7, so BOTH directions
            # have to work. This is the row that fails if the prefix alternation is built the wrong way
            # round - matching the query against the row rather than the row against the query.
            $r = New-LedgerRepo -LedgerBody $script:FullShaLedger
            (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Match 'FOUND'
        }

        It 'authenticates a padded-bracket range cell' {
            $r = New-LedgerRepo -LedgerBody $script:PaddedBracketLedger
            (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Match 'FOUND'
        }

        It 'authenticates a row indented up to THREE spaces' {
            $r = New-LedgerRepo -LedgerBody $script:Indent3Ledger
            (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Match 'FOUND'
        }

        It 'authenticates an UPPERCASE sha in the ledger' {
            # Ledgers are hand-written; case is not a contract. The match is case-insensitive, and this
            # row is what stops a future -E losing its -i.
            $r = New-LedgerRepo -LedgerBody $script:RangeLedger
            $p = Join-Path $r.Dir 'docs/agy-capstone-ledger.md'
            $body = [IO.File]::ReadAllText($p).Replace($r.Sha.Substring(0, 7), $r.Sha.Substring(0, 7).ToUpper())
            [IO.File]::WriteAllText($p, $body)
            (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Match 'FOUND'
        }
    }

    Context 'refusals - and each one names its cause' {
        It 'refuses with mentioned=0 when the sha appears NOWHERE' {
            $r = New-LedgerRepo -LedgerBody $script:HeaderOnlyLedger
            $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out
            $out | Should -Match 'ABSENT'
            $out | Should -Match 'mentioned=0' -Because 'nothing to fix in an existing row: the advice must be APPEND one'
            $out | Should -Not -Match 'FOUND'
        }

        It 'refuses a sha that appears only in the EVIDENCE column' {
            # THE FOUNDING FALSE-PASS. A fold sha quoted in evidence prose is mentioned, never recorded.
            $r = New-LedgerRepo -LedgerBody $script:EvidenceProseLedger
            $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out
            $out | Should -Not -Match 'FOUND' -Because 'a sha quoted in prose is mentioned, not recorded'
            $out | Should -Match 'mentioned=1' -Because 'the sha IS in the file, so the advice must be FIX the row, not append one'
        }

        It 'refuses a sha that is the range LEFT endpoint' {
            # The commit the work STARTED from was never the reviewed tip.
            $r = New-LedgerRepo -LedgerBody $script:LeftEndpointLedger
            $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out
            $out | Should -Not -Match 'FOUND' -Because 'the left endpoint is where the range began, not what was reviewed'
            $out | Should -Match 'mentioned=1'
        }

        It 'refuses a range that is not FIRST in its column' {
            $r = New-LedgerRepo -LedgerBody $script:NotFirstLedger
            (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Not -Match 'FOUND'
        }

        It 'refuses a row whose second column is not a DATE' {
            # This is also what excludes the 3-column anomaly table sharing the real capstone ledger.
            $r = New-LedgerRepo -LedgerBody $script:NoDateLedger
            (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Not -Match 'FOUND'
        }

        It 'refuses a row indented FOUR spaces, which is an indented code block' {
            $r = New-LedgerRepo -LedgerBody $script:Indent4Ledger
            (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out | Should -Not -Match 'FOUND'
        }

        It 'answers UNREADABLE - not ABSENT - when the ledger cannot be OPENED' {
            # AGY-TEST-AUDIT gap 5, and the live defect probing it uncovered: `[ -r ]` calls an ACL-denied
            # file readable on Windows, so the guard that used to sit here never fired and the reader
            # claimed ABSENT about a file nothing had read. The oracle is now grep's EXIT CODE.
            $r = New-LedgerRepo -LedgerBody $script:RangeLedger
            $ledger = Join-Path $r.Dir 'docs/agy-capstone-ledger.md'

            # PASSING CONTROL in the same process: while readable this fixture answers FOUND. Without it a
            # later UNREADABLE could equally mean the fixture never worked.
            (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out |
                Should -Match 'FOUND' -Because 'the fixture must answer FOUND while readable, or its failing case proves nothing'

            try {
                if ($IsWindows) { & icacls $ledger /deny "$($env:USERNAME):(R)" 2>&1 | Out-Null }
                else            { & chmod 000 $ledger }

                # ORACLE CONTROL, deliberately through something OTHER than the code under test: .NET
                # opens the file by a different path than MSYS bash does, so it can contradict the reader
                # rather than echo it. If the deny did not take - an elevated token, a filesystem that
                # ignores ACLs - this row cannot reach its failing answer, and a row that cannot fail
                # certifies nothing. SKIP loudly instead of passing silently.
                $reallyDenied = $false
                try { [void][IO.File]::ReadAllText($ledger) } catch { $reallyDenied = $true }
                if (-not $reallyDenied) {
                    Set-ItResult -Skipped -Because 'the read-deny did not take on this account, so the unreadable state is unreachable here'
                }

                $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha).Out
                $out | Should -Match 'UNREADABLE' -Because 'nothing read the file, so no claim about its CONTENT may be made'
                $out | Should -Not -Match 'ABSENT' -Because 'ABSENT asserts the file does not record the sha, which is false when it was never opened'
            }
            finally {
                # Restore BEFORE fixture cleanup: a denied file may resist deletion, leaking the temp dir.
                if ($IsWindows) { & icacls $ledger /remove:d "$env:USERNAME" 2>&1 | Out-Null }
                else            { & chmod 644 $ledger }
            }
        }
    }

    Context 'the QUERY is data, never a pattern' {
        It 'refuses a non-hex query instead of interpolating it into the regex' -ForEach @(
            @{ Q = 'not-a-sha' }, @{ Q = '.*' }, @{ Q = 'aaaaaaa|bbbbbbb' }, @{ Q = '' }
        ) {
            # A query reaching the regex as PATTERN TEXT would let `.*` authenticate any row at all.
            $r = New-LedgerRepo -LedgerBody $script:RangeLedger
            $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $Q).Out
            $out | Should -Not -Match 'FOUND' -Because 'a metacharacter query must be refused as data, never executed as a pattern'
            $out | Should -Match 'mentioned=0'
        }

        It 'refuses a hex query SHORTER than the seven-character minimum' {
            $r = New-LedgerRepo -LedgerBody $script:RangeLedger
            $short = $r.Sha.Substring(0, 6)
            $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $short).Out
            $out | Should -Not -Match 'FOUND' -Because 'six hex characters is not a sha; ordinary words like facade and decade are valid hex'
        }
    }

    Context 'pinned against the REAL shipped ledger' {
        # These three rows are the regression pins for the change that replaced the parser. They plant a
        # COPY of the live docs/agy-capstone-ledger.md in a throwaway repo, so they read the same bytes
        # the gate reads in production while writing nothing into the working tree. The shas are literal
        # and immutable. Their point is that a cell-wide or line-wide search passes rows 2 and 3.
        BeforeAll {
            $script:RealLedgerBody = [IO.File]::ReadAllText((Join-Path $script:RepoRoot 'docs/agy-capstone-ledger.md'))
        }

        It 'authenticates <Name>, a real reviewed tip' -ForEach @(
            @{ Name = 'fac6fa5'; Sha = 'fac6fa526a3b5ce9587d13f62ded9182b284c993' }
            @{ Name = 'f62e659'; Sha = 'f62e659d9f256aea4c0893e5b96df2b0f938fbc5' }
        ) {
            $r = New-LedgerRepo -RawBody $script:RealLedgerBody
            (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha $Sha).Out |
                Should -Match 'FOUND' -Because "$Name is recorded as a range right-endpoint in the shipped ledger"
        }

        It 'refuses e60ad19, a fold sha the shipped ledger mentions only in a range cell PROSE' {
            # MEASURED against the live file: a cell-wide grep answers FOUND here. The ledger names this
            # sha at docs/agy-capstone-ledger.md:69 as one of a round's own fold commits - mentioned, and
            # never recorded as a reviewed tip.
            $r = New-LedgerRepo -RawBody $script:RealLedgerBody
            $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha 'e60ad19e2951bbb32659ae81936520e4e3743911').Out
            $out | Should -Not -Match 'FOUND'
            $out | Should -Match 'mentioned=1'
        }

        It 'refuses 49be0c4, a range LEFT endpoint in the shipped ledger' {
            $r = New-LedgerRepo -RawBody $script:RealLedgerBody
            $out = (Invoke-Lookup -Cwd $r.Dir -Discipline 'agy-capstone' -Sha '49be0c4e2c63fc2f3875d63ca607908d28a9d760').Out
            $out | Should -Not -Match 'FOUND'
            $out | Should -Match 'mentioned=1'
        }
    }
}

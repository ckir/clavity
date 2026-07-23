# scripts/tests/docs-audit.Tests.ps1
BeforeAll {
    $script:Lib   = Join-Path $PSScriptRoot '..' 'docs-audit-lib.ps1'
    $script:Audit = Join-Path $PSScriptRoot '..' 'docs-audit.ps1'
    . $script:Lib   # dot-source: defines functions only (no orchestrator)
}

Describe 'Read-DocList / Get-InScopeDocs' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ('r-' + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $script:Root 'docs') -Force | Out-Null
        Set-Content (Join-Path $script:Root 'docs/user-facing-docs.txt') @(
            '# a comment', '', 'README.md', 'SECURITY.md', '   ', 'CONTRIBUTING.md  # trailing note')
        foreach ($f in 'README.md','SECURITY.md','CONTRIBUTING.md') { Set-Content (Join-Path $script:Root $f) 'x' }
    }

    It 'reads the list, ignoring comments and blank lines' {
        (Read-DocList (Join-Path $script:Root 'docs/user-facing-docs.txt')) |
            Should -Be @('README.md','SECURITY.md','CONTRIBUTING.md')
    }
    It 'full list by default' {
        (Get-InScopeDocs -RepoRoot $script:Root -Only @()).Count | Should -Be 3
    }
    It 'a narrowing arg audits only the named subset' {
        Get-InScopeDocs -RepoRoot $script:Root -Only @('SECURITY.md') | Should -Be @('SECURITY.md')
    }
    It 'a narrowing arg for a path NOT on the list is dropped (never audits off-list docs)' {
        Get-InScopeDocs -RepoRoot $script:Root -Only @('SECURITY.md','not-listed.md') | Should -Be @('SECURITY.md')
    }
    It "preserves a '#' inside a real filename and still drops whole-line comments (agy R6-F2)" {
        $p = Join-Path $script:Root 'docs/hashy.txt'
        Set-Content $p @('# whole-line comment', '   # indented comment', 'C#-guide.md', 'README.md  # trailing note', '')
        Read-DocList $p | Should -Be @('C#-guide.md', 'README.md')
    }
}

Describe 'Parse-AuditOutput / Get-FencedCodeBlockCount / Get-DocOutcome' {
    It 'parses a well-formed audit output with findings' {
        $raw = "CLAIMS_INSPECTED: 7`nFINDINGS:`n- ACCURACY README.md:12 | src/main.rs:40 | flag --foo does not exist"
        $p = Parse-AuditOutput $raw
        $p.Parseable | Should -BeTrue
        $p.ClaimsInspected | Should -Be 7
        @($p.Findings).Count | Should -Be 1
        $p.Findings[0].kind | Should -Be 'ACCURACY'
        $p.Findings[0].codeRef | Should -Be 'src/main.rs:40'
    }
    It 'parses a clean output (FINDINGS: none) as zero findings' {
        $p = Parse-AuditOutput "CLAIMS_INSPECTED: 3`nFINDINGS: none"
        $p.Parseable | Should -BeTrue; $p.ClaimsInspected | Should -Be 3; @($p.Findings).Count | Should -Be 0
    }
    It 'marks output with no CLAIMS_INSPECTED line unparseable' {
        (Parse-AuditOutput "I refuse to do that.").Parseable | Should -BeFalse
    }
    It 'counts fenced code blocks in a doc' {
        $f = Join-Path $TestDrive 'blocks.md'
        Set-Content $f @('# t','```bash','x','```','prose','```','y','```','```pwsh','z','```')
        Get-FencedCodeBlockCount $f | Should -Be 3
    }
    It 'classifies: unparseable => AUDIT-INCONCLUSIVE' {
        Get-DocOutcome -ClaimsInspected 0 -FindingsCount 0 -FencedBlocks 0 -Parseable $false | Should -Be 'AUDIT-INCONCLUSIVE'
    }
    It 'classifies: claims 0 => AUDIT-INCONCLUSIVE (liveness)' {
        Get-DocOutcome -ClaimsInspected 0 -FindingsCount 0 -FencedBlocks 5 -Parseable $true | Should -Be 'AUDIT-INCONCLUSIVE'
    }
    It 'classifies: claims 1 + many code blocks => AUDIT-SUSPECT' {
        Get-DocOutcome -ClaimsInspected 1 -FindingsCount 0 -FencedBlocks 4 -Parseable $true | Should -Be 'AUDIT-SUSPECT'
    }
    It 'classifies: claims 1 but few code blocks => not suspect (CLEAN)' {
        Get-DocOutcome -ClaimsInspected 1 -FindingsCount 0 -FencedBlocks 1 -Parseable $true | Should -Be 'CLEAN'
    }
    It 'classifies: findings => FINDINGS' {
        Get-DocOutcome -ClaimsInspected 5 -FindingsCount 2 -FencedBlocks 0 -Parseable $true | Should -Be 'FINDINGS'
    }
    It 'classifies: claims > 0, no findings, not suspect => CLEAN' {
        Get-DocOutcome -ClaimsInspected 9 -FindingsCount 0 -FencedBlocks 0 -Parseable $true | Should -Be 'CLEAN'
    }
    It 'a MALFORMED findings bullet poisons the parse instead of silently reading as CLEAN (capstone C3)' {
        # Measured defect: the bullet used commas instead of the `|` contract, the parser dropped it, and the
        # doc classified CLEAN with 7 claims — a false NEGATIVE hiding a real finding. Must be unparseable.
        $raw = "CLAIMS_INSPECTED: 7`nFINDINGS:`n- ACCURACY doc.md:1, code.rs:2, comma instead of pipe"
        $p = Parse-AuditOutput $raw
        $p.Parseable | Should -BeFalse
        Get-DocOutcome -ClaimsInspected $p.ClaimsInspected -FindingsCount (@($p.Findings).Count) `
            -FencedBlocks 0 -Parseable $p.Parseable | Should -Be 'AUDIT-INCONCLUSIVE'
    }
    It 'a finding line MISSING the bullet prefix poisons the parse rather than reading CLEAN (capstone C5)' {
        # Measured: the model emitting `ACCURACY doc.md:1 | code.rs:1 | text` with no `- ` prefix produced
        # Parseable=True, Findings=0 => CLEAN. Any line carrying the `a | b | c` finding shape now counts.
        $raw = "CLAIMS_INSPECTED: 1`nFINDINGS:`nACCURACY doc.md:1 | code.rs:1 | a real defect"
        $p = Parse-AuditOutput $raw
        $p.Parseable | Should -BeFalse
        Get-DocOutcome -ClaimsInspected $p.ClaimsInspected -FindingsCount (@($p.Findings).Count) `
            -FencedBlocks 0 -Parseable $p.Parseable | Should -Be 'AUDIT-INCONCLUSIVE'
    }
    It 'a finding with NEITHER bullet NOR pipes still poisons the parse (capstone C7 — STRICT)' {
        # The third and final leak: `ACCURACY doc.md:1, code.rs:1, text` matched no malformed-SHAPE rule and was
        # ignored => CLEAN. Shape-matching the malformation is a losing game, so the rule is now strict.
        $raw = "CLAIMS_INSPECTED: 1`nFINDINGS:`nACCURACY doc.md:1, code.rs:1, a real defect"
        (Parse-AuditOutput $raw).Parseable | Should -BeFalse
    }
    It 'any unrecognised non-blank line in the FINDINGS section poisons the parse (capstone C7 — STRICT)' {
        # DELIBERATE REVERSAL of an earlier assertion that a wrapped continuation line stays parseable. The
        # prompt contract says "emit EXACTLY this shape and nothing else", so a continuation IS a violation.
        # A false AUDIT-INCONCLUSIVE is cheap (prior findings preserved, cause logged); a false CLEAN is not.
        $raw = "CLAIMS_INSPECTED: 7`nFINDINGS:`n- ACCURACY doc.md:1 | code.rs:2 | first part`n  continued here"
        (Parse-AuditOutput $raw).Parseable | Should -BeFalse
    }
    It 'blank lines inside the FINDINGS section are still tolerated (capstone C7 non-regression)' {
        $raw = "CLAIMS_INSPECTED: 7`nFINDINGS:`n`n- ACCURACY doc.md:1 | code.rs:2 | t`n   `n"
        $p = Parse-AuditOutput $raw
        $p.Parseable | Should -BeTrue
        @($p.Findings).Count | Should -Be 1
    }
    It 'a LINE-RANGE anchor parses and preserves the whole range (live-run defect E4)' {
        # Measured on the first full 25-doc run: the model anchored a claim spanning a 6-command code block as
        # `CONTRIBUTING.md:11-19`. The regex accepted only `:<int>` before the `|`, so the line was unrecognised,
        # the strict rule poisoned the parse, and a REAL finding was discarded as AUDIT-INCONCLUSIVE — twice, on
        # the same doc. A range is a legitimate anchor for a multi-line claim, so the CONTRACT was widened (both
        # docs-audit-prompt.md and this parser) rather than the parser patched alone. docLine is a STRING now:
        # keeping the [int] cast would throw FormatException on "11-19", and capturing only the start line would
        # silently discard the localisation the model got right.
        $raw = "CLAIMS_INSPECTED: 24`nFINDINGS:`n- ACCURACY CONTRIBUTING.md:11-19 | .github/workflows/ci-classic.yml:42 | CI runs 4 of the 6 listed commands"
        $p = Parse-AuditOutput $raw
        $p.Parseable | Should -BeTrue
        @($p.Findings).Count | Should -Be 1
        $p.Findings[0].docLine | Should -Be '11-19'
        Get-DocOutcome -ClaimsInspected $p.ClaimsInspected -FindingsCount (@($p.Findings).Count) `
            -FencedBlocks 0 -Parseable $p.Parseable | Should -Be 'FINDINGS'
    }
    It 'a single-line anchor still parses, as the range-capturing string (E4 non-regression)' {
        $p = Parse-AuditOutput "CLAIMS_INSPECTED: 7`nFINDINGS:`n- ACCURACY README.md:12 | src/main.rs:40 | t"
        $p.Parseable | Should -BeTrue
        $p.Findings[0].docLine | Should -Be '12'
    }
    It 'a MALFORMED range still poisons the parse — widening the contract did not loosen the strict rule (E4)' {
        # The widened shape is `<int>` or `<int>-<int>` and nothing else. An open range, a comma list, or prose
        # remain contract violations: the poison rule (C3/C5/C7) is untouched by this change.
        foreach ($anchor in @('doc.md:11-', 'doc.md:-19', 'doc.md:11,15', 'doc.md:lines 11-19')) {
            $p = Parse-AuditOutput "CLAIMS_INSPECTED: 4`nFINDINGS:`n- ACCURACY $anchor | code.rs:2 | t"
            $p.Parseable | Should -BeFalse -Because "anchor '$anchor' is off-contract"
        }
    }
    It 'Get-DiagnosticSnippet collapses to one bounded line (agy R5-F1)' {
        Get-DiagnosticSnippet "Error: 429`n  quota   exceeded" | Should -Be 'Error: 429 quota exceeded'
        Get-DiagnosticSnippet '' | Should -Be '(no output)'
        (Get-DiagnosticSnippet ('x' * 500)).Length | Should -BeLessOrEqual 203   # 200 + the ellipsis
    }
}

Describe 'FindingsStore merge/write/render' {
    BeforeEach { $script:Json = Join-Path $TestDrive ('s-' + [Guid]::NewGuid() + '.json') }

    It 'a fresh store reads as an empty skeleton' {
        $s = Read-FindingsStore $script:Json
        $s.schemaVersion | Should -Be 1; $s.docs.Keys.Count | Should -Be 0
    }
    It 'a confirmed FINDINGS result is stored and round-trips through disk' {
        $s = Read-FindingsStore $script:Json
        Merge-DocResult -Store $s -DocPath 'A.md' -RunId 'R1' `
            -Result @{ Outcome='FINDINGS'; ClaimsInspected=4; Findings=@(@{kind='ACCURACY';docPath='A.md';docLine=1;codeRef='x.rs:2';text='t'}) } | Out-Null
        Write-FindingsStore -Store $s -Path $script:Json
        $r = Read-FindingsStore $script:Json
        $r.docs['A.md'].outcome | Should -Be 'FINDINGS'
        @($r.docs['A.md'].findings).Count | Should -Be 1
    }
    It 'a CLEAN re-run REPLACES a docs prior FINDINGS section' {
        $s = Read-FindingsStore $script:Json
        Merge-DocResult -Store $s -DocPath 'A.md' -RunId 'R1' -Result @{ Outcome='FINDINGS'; ClaimsInspected=4; Findings=@(@{kind='ACCURACY';docPath='A.md';docLine=1;codeRef='x.rs:2';text='t'}) } | Out-Null
        Merge-DocResult -Store $s -DocPath 'A.md' -RunId 'R2' -Result @{ Outcome='CLEAN'; ClaimsInspected=6; Findings=@() } | Out-Null
        $s.docs['A.md'].outcome | Should -Be 'CLEAN'
        @($s.docs['A.md'].findings).Count | Should -Be 0
        $s.docs['A.md'].auditedAtRunId | Should -Be 'R2'
    }
    It 'a failed re-run (AUDIT-INCONCLUSIVE) PRESERVES prior findings and annotates the attempt' {
        $s = Read-FindingsStore $script:Json
        Merge-DocResult -Store $s -DocPath 'A.md' -RunId 'R1' -Result @{ Outcome='FINDINGS'; ClaimsInspected=4; Findings=@(@{kind='ACCURACY';docPath='A.md';docLine=1;codeRef='x.rs:2';text='t'}) } | Out-Null
        Merge-DocResult -Store $s -DocPath 'A.md' -RunId 'R2' -Result @{ Outcome='AUDIT-INCONCLUSIVE'; ClaimsInspected=0; Findings=@() } | Out-Null
        $s.docs['A.md'].outcome | Should -Be 'FINDINGS'          # prior outcome preserved
        @($s.docs['A.md'].findings).Count | Should -Be 1         # prior findings survive
        # @(...) is load-bearing: a single Where-Object match unwraps to a bare hashtable whose OWN .Count is its
        # KEY count (3), shadowing PowerShell's single-object Count adapter — the bare form measures 3, not 1.
        @($s.docs['A.md'].history | Where-Object { $_.outcome -eq 'AUDIT-INCONCLUSIVE' }).Count | Should -Be 1  # attempt not hidden
    }
    It 'a first-ever audit that is inconclusive records the state with empty findings' {
        $s = Read-FindingsStore $script:Json
        Merge-DocResult -Store $s -DocPath 'B.md' -RunId 'R1' -Result @{ Outcome='AUDIT-INCONCLUSIVE'; ClaimsInspected=0; Findings=@() } | Out-Null
        $s.docs['B.md'].outcome | Should -Be 'AUDIT-INCONCLUSIVE'
        @($s.docs['B.md'].findings).Count | Should -Be 0
    }
    It 'a failure->different-failure transition updates the visible outcome (agy F3): INCONCLUSIVE then SUSPECT' {
        $s = Read-FindingsStore $script:Json
        Merge-DocResult -Store $s -DocPath 'B.md' -RunId 'R1' -Result @{ Outcome='AUDIT-INCONCLUSIVE'; ClaimsInspected=0; Findings=@() } | Out-Null
        Merge-DocResult -Store $s -DocPath 'B.md' -RunId 'R2' -Result @{ Outcome='AUDIT-SUSPECT'; ClaimsInspected=1; Findings=@() } | Out-Null
        $s.docs['B.md'].outcome | Should -Be 'AUDIT-SUSPECT'   # NOT frozen on the earlier INCONCLUSIVE
    }
    It 'Read-FindingsStore falls through to a fresh skeleton on corrupt JSON (agy F6)' {
        Set-Content $script:Json '{ this is not valid json'
        $s = Read-FindingsStore $script:Json
        $s.schemaVersion | Should -Be 1; $s.docs.Keys.Count | Should -Be 0
    }
    It 'Read-FindingsStore falls through to a fresh skeleton when the docs key is missing (agy F6)' {
        Set-Content $script:Json '{ "schemaVersion": 1 }'
        (Read-FindingsStore $script:Json).docs.Keys.Count | Should -Be 0
    }
    It 'Write-FindingsStore is atomic (leaves no PID-unique .tmp behind)' {
        $s = Read-FindingsStore $script:Json
        Write-FindingsStore -Store $s -Path $script:Json
        Test-Path ($script:Json + ".$PID.tmp") | Should -BeFalse   # same process => same $PID as the write
    }
    It 'Render-FindingsView emits per-doc delimited sections' {
        $s = Read-FindingsStore $script:Json
        Merge-DocResult -Store $s -DocPath 'A.md' -RunId 'R1' -Result @{ Outcome='FINDINGS'; ClaimsInspected=4; Findings=@(@{kind='ACCURACY';docPath='A.md';docLine=1;codeRef='x.rs:2';text='t'}) } | Out-Null
        $md = Join-Path $TestDrive 'view.md'
        Render-FindingsView -Store $s -Path $md
        (Get-Content $md -Raw) | Should -Match '<!-- doc:A.md start -->'
        (Get-Content $md -Raw) | Should -Match '<!-- doc:A.md end -->'
    }
}

Describe 'Append-only incremental log' {
    BeforeEach { $script:Log = Join-Path $TestDrive ('l-' + [Guid]::NewGuid() + '.md') }

    It 'writes a run header once, then one line per doc, each appended as it completes' {
        Initialize-AuditLog -Path $script:Log -RunId 'R1' -Timestamp '2026-07-22 00:00:00Z' -LinkResult 'mlc: 2 errors (baseline 2; exit 1)'
        Add-AuditLogDoc -Path $script:Log -DocPath 'A.md' -Result @{ Outcome='CLEAN'; ClaimsInspected=3; Findings=@() } -Model 'sonnet' -PromptFile 'docs-audit-prompt.md'
        $afterFirst = Get-Content $script:Log -Raw           # durable BEFORE the next doc runs (crash-safety)
        Add-AuditLogDoc -Path $script:Log -DocPath 'B.md' -Result @{ Outcome='FINDINGS'; ClaimsInspected=5; Findings=@(1,2) } -Model 'sonnet' -PromptFile 'docs-audit-prompt.md'
        $afterFirst | Should -Match '## audit R1 — 2026-07-22 00:00:00Z — mlc: 2 errors'
        $afterFirst | Should -Match '- A.md — CLEAN — claims:3'
        (Get-Content $script:Log -Raw) | Should -Match '- B.md — FINDINGS — claims:5 — .*findings:2'
    }
    It 'a second run APPENDS a new header, never truncating the first run' {
        Initialize-AuditLog -Path $script:Log -RunId 'R1' -Timestamp '2026-07-22 00:00:00Z' -LinkResult 'x'
        Add-AuditLogDoc -Path $script:Log -DocPath 'A.md' -Result @{ Outcome='CLEAN'; ClaimsInspected=1; Findings=@() } -Model 'sonnet' -PromptFile 'p'
        Initialize-AuditLog -Path $script:Log -RunId 'R2' -Timestamp '2026-07-22 01:00:00Z' -LinkResult 'y'
        $all = Get-Content $script:Log -Raw
        $all | Should -Match '## audit R1'
        $all | Should -Match '## audit R2'
    }
}

Describe 'Self-clearing lock' {
    BeforeEach { $script:Lock = Join-Path $TestDrive ('lk-' + [Guid]::NewGuid()) }

    It 'no lock file => free (stale)' {
        Test-AuditLockStale -LockPath $script:Lock -NowUtc '2026-07-22 00:00:00Z' -MaxAgeSec 3600 | Should -BeTrue
    }
    It 'a fresh lock held by THIS (alive) process is NOT stale' {
        Set-Content $script:Lock @("$PID", '2026-07-22 00:00:00Z')
        Test-AuditLockStale -LockPath $script:Lock -NowUtc '2026-07-22 00:00:30Z' -MaxAgeSec 3600 | Should -BeFalse
    }
    It 'a lock older than MaxAgeSec is stale regardless of PID' {
        Set-Content $script:Lock @("$PID", '2026-07-22 00:00:00Z')
        Test-AuditLockStale -LockPath $script:Lock -NowUtc '2026-07-22 05:00:00Z' -MaxAgeSec 3600 | Should -BeTrue
    }
    It 'a lock whose PID is dead is stale (reclaimable)' {
        Mock Get-Process { $null } -ParameterFilter { $Id -eq 999001 }
        Set-Content $script:Lock @('999001', '2026-07-22 00:00:00Z')
        Test-AuditLockStale -LockPath $script:Lock -NowUtc '2026-07-22 00:00:30Z' -MaxAgeSec 3600 | Should -BeTrue
        Should -Invoke Get-Process -ParameterFilter { $Id -eq 999001 } -Times 1
    }
    It 'Enter-AuditLock writes PID+timestamp when free, and refuses a live lock' {
        (Enter-AuditLock -LockPath $script:Lock -NowUtc '2026-07-22 00:00:00Z' -MaxAgeSec 3600) | Should -BeTrue
        (Get-Content $script:Lock)[0] | Should -Be "$PID"
        (Enter-AuditLock -LockPath $script:Lock -NowUtc '2026-07-22 00:00:10Z' -MaxAgeSec 3600) | Should -BeFalse  # our own fresh lock is live
    }
    It 'Exit-AuditLock removes OUR lock' {
        # Content updated from the placeholder 'x' to a real PID: releasing is now ownership-checked (C6), so
        # the old fixture no longer expressed "our lock". The behaviour under test is unchanged.
        Set-Content $script:Lock @("$PID", '2026-07-22 00:00:00Z')
        Exit-AuditLock $script:Lock; Test-Path $script:Lock | Should -BeFalse
    }
    It 'Exit-AuditLock does NOT remove a lock owned by another run (capstone C6)' {
        # Measured defect: a run whose host slept past MaxAgeSec had its lock legitimately reclaimed; on waking
        # it unconditionally deleted the NEW run's live lock, letting a third run start alongside it.
        Set-Content $script:Lock @('999002', '2026-07-22 00:00:00Z')
        Exit-AuditLock $script:Lock
        Test-Path $script:Lock | Should -BeTrue
    }
    It 'a 0-byte lock is stale, not a crash (capstone C8)' {
        # Reachable: New-AuditLockFile creates then writes, so a hard-kill/power-loss/full-disk in between
        # leaves an empty file. Measured: indexing the empty array threw IndexOutOfRangeException under
        # StrictMode, crashing the run and leaving the lock in place — wedging the tool permanently.
        New-Item -ItemType File $script:Lock -Force | Out-Null
        { Test-AuditLockStale -LockPath $script:Lock -NowUtc '2026-07-22 00:00:00Z' -MaxAgeSec 3600 } | Should -Not -Throw
        Test-AuditLockStale -LockPath $script:Lock -NowUtc '2026-07-22 00:00:00Z' -MaxAgeSec 3600 | Should -BeTrue
        (Enter-AuditLock -LockPath $script:Lock -NowUtc '2026-07-22 00:00:00Z' -MaxAgeSec 3600) | Should -BeTrue
    }
    It 'Exit-AuditLock does not throw on a 0-byte lock and leaves it for reclaim (capstone C8)' {
        New-Item -ItemType File $script:Lock -Force | Out-Null
        { Exit-AuditLock $script:Lock } | Should -Not -Throw
        Test-Path $script:Lock | Should -BeTrue   # no ownership proof => not ours to delete
    }
    It 'Test-AuditLockStale survives the lock vanishing mid-check instead of throwing (capstone C6)' {
        # Measured: Test-Path then Get-Content is a race; the file disappearing in between threw
        # ItemNotFoundException, which under the orchestrator's Stop preference crashed the whole run.
        Set-Content $script:Lock @("$PID", '2026-07-22 00:00:00Z')
        Remove-Item $script:Lock -Force            # the concurrent release
        { Test-AuditLockStale -LockPath $script:Lock -NowUtc '2026-07-22 00:00:30Z' -MaxAgeSec 3600 } | Should -Not -Throw
    }
    It 'a malformed PID (non-integer line 1) is stale (agy F6)' {
        Set-Content $script:Lock @('invalidPID', '2026-07-22 00:00:00Z')
        Test-AuditLockStale -LockPath $script:Lock -NowUtc '2026-07-22 00:00:30Z' -MaxAgeSec 3600 | Should -BeTrue
    }
    It 'Enter-AuditLock does NOT delete a live lock it lost the race to (capstone C2)' {
        # Measured defect in the first C1 fix: an unconditional Remove-Item ran BEFORE the exclusive create, so a
        # second run deleted the first run's freshly-minted LIVE lock and acquired anyway — both ran. Pin the
        # invariant: a live lock survives a losing acquire attempt, byte for byte.
        (Enter-AuditLock -LockPath $script:Lock -NowUtc '2026-07-22 00:00:00Z' -MaxAgeSec 3600) | Should -BeTrue
        $before = Get-Content $script:Lock -Raw
        (Enter-AuditLock -LockPath $script:Lock -NowUtc '2026-07-22 00:00:10Z' -MaxAgeSec 3600) | Should -BeFalse
        Test-Path $script:Lock | Should -BeTrue          # the live lock still exists...
        (Get-Content $script:Lock -Raw) | Should -Be $before   # ...and was not rewritten by the loser
    }
    It 'Enter-AuditLock leaves no .claim residue after reclaiming a stale lock (capstone C2/C4)' {
        Set-Content $script:Lock @("$PID", '2026-07-22 00:00:00Z')
        (Enter-AuditLock -LockPath $script:Lock -NowUtc '2026-07-22 05:00:00Z' -MaxAgeSec 3600) | Should -BeTrue
        Test-Path ($script:Lock + '.claim') | Should -BeFalse
    }
    It 'a run holding the reclaim marker blocks a concurrent reclaim rather than stealing (capstone C4)' {
        # Measured defect in the previous fix: Move-Item renames by PATH, so a late arrival stole the winner's
        # freshly-installed LIVE lock and both ran. Pin it: with the marker held, a reclaim attempt refuses.
        Set-Content $script:Lock @('999001', '2020-01-01 00:00:00Z')          # stale (dead pid, ancient)
        Set-Content ($script:Lock + '.claim') @("$PID", '2026-07-22 00:00:00Z')  # a LIVE reclaim in progress
        (Enter-AuditLock -LockPath $script:Lock -NowUtc '2026-07-22 00:00:05Z' -MaxAgeSec 3600) | Should -BeFalse
        Test-Path ($script:Lock + '.claim') | Should -BeTrue                 # the live marker was NOT cleared
    }
    It 'an ORPHANED reclaim marker is cleared so it cannot wedge the tool forever (capstone C4)' {
        # A hard-killed run can leave the marker behind; a self-clearing lock must never wedge permanently.
        Set-Content $script:Lock @('999001', '2020-01-01 00:00:00Z')
        Set-Content ($script:Lock + '.claim') @('999002', '2020-01-01 00:00:00Z')   # orphaned: dead pid, ancient
        (Enter-AuditLock -LockPath $script:Lock -NowUtc '2026-07-22 00:00:05Z' -MaxAgeSec 3600) | Should -BeFalse
        Test-Path ($script:Lock + '.claim') | Should -BeFalse                # cleared, so the NEXT run reclaims
        (Enter-AuditLock -LockPath $script:Lock -NowUtc '2026-07-22 00:00:06Z' -MaxAgeSec 3600) | Should -BeTrue
    }
    It 'a garbage timestamp (unparseable line 2) is stale (agy F6)' {
        Set-Content $script:Lock @("$PID", 'not-a-timestamp')
        Test-AuditLockStale -LockPath $script:Lock -NowUtc '2026-07-22 00:00:30Z' -MaxAgeSec 3600 | Should -BeTrue
    }
}

Describe 'Get-MlcErrorCount' {
    It 'reads the error count from REAL captured mlc summary output' {
        $real = @'
Result (210 links):

OK       144
Skipped  37
Warnings 27
Errors   2
'@
        Get-MlcErrorCount $real | Should -Be 2
    }
    It 'does not mistake the sibling Warnings line for the Errors line' {
        Get-MlcErrorCount "OK       144`nWarnings 27`nErrors   0" | Should -Be 0
    }
    It 'returns 0 when no summary block is present' { Get-MlcErrorCount 'mlc produced nothing usable' | Should -Be 0 }
}

Describe 'docs-audit orchestrator (via pwsh -File, -AuditStub seam)' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ('o-' + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $script:Root 'docs') -Force | Out-Null
        foreach ($f in 'A.md','B.md','C.md') { Set-Content (Join-Path $script:Root $f) "# $f`n" }
        Set-Content (Join-Path $script:Root 'docs/user-facing-docs.txt') @('A.md','B.md','C.md')
        # A stub emitting a canned FINDINGS result for every doc.
        $script:StubFindings = Join-Path $script:Root 'stub-findings.ps1'
        Set-Content $script:StubFindings @(
            'param($docPath,$repoRoot)'
            'Write-Output "CLAIMS_INSPECTED: 5"'
            'Write-Output "FINDINGS:"'
            'Write-Output "- ACCURACY $docPath`:3 | src/x.rs:9 | example finding"'
        )
    }

    It 'a full run audits every listed doc and writes store + view + log' {
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $script:StubFindings -RunId 'R1' -Timestamp '2026-07-22 00:00:00Z' -SkipLinkCheck
        $LASTEXITCODE | Should -Be 0
        Test-Path (Join-Path $script:Root 'docs/docs-audit-findings.json') | Should -BeTrue
        Test-Path (Join-Path $script:Root 'docs/docs-audit-findings.md')   | Should -BeTrue
        (Get-Content (Join-Path $script:Root 'docs/docs-audit-log.md') -Raw) | Should -Match '- A.md — FINDINGS'
        $store = Get-Content (Join-Path $script:Root 'docs/docs-audit-findings.json') -Raw | ConvertFrom-Json -AsHashtable
        $store.docs.Keys.Count | Should -Be 3
    }
    It 'a per-doc timeout records AUDIT-TIMEOUT and does not stall the run' {
        $slow = Join-Path $script:Root 'stub-slow.ps1'
        Set-Content $slow @('param($docPath,$repoRoot)','Start-Sleep -Seconds 30','Write-Output "CLAIMS_INSPECTED: 1"')
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $slow -RunId 'R1' -Timestamp '2026-07-22 00:00:00Z' -SkipLinkCheck -TimeoutSec 3 -Only 'A.md'
        $LASTEXITCODE | Should -Be 0
        (Get-Content (Join-Path $script:Root 'docs/docs-audit-log.md') -Raw) | Should -Match '- A.md — AUDIT-TIMEOUT'
    }
    It 'a subset re-run preserves other docs findings (does not wipe the store)' {
        # Full run seeds A,B,C with FINDINGS.
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $script:StubFindings -RunId 'R1' -Timestamp '2026-07-22 00:00:00Z' -SkipLinkCheck
        # Subset re-run of ONLY A.
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $script:StubFindings -RunId 'R2' -Timestamp '2026-07-22 01:00:00Z' -Only 'A.md'
        $LASTEXITCODE | Should -Be 0
        $store = Get-Content (Join-Path $script:Root 'docs/docs-audit-findings.json') -Raw | ConvertFrom-Json -AsHashtable
        @($store.docs['B.md'].findings).Count | Should -Be 1   # B survived the subset run
        @($store.docs['C.md'].findings).Count | Should -Be 1   # C survived
    }
    It 'an outcome-aware failed re-run preserves prior findings (seed FINDINGS, re-audit AUDIT-INCONCLUSIVE)' {
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $script:StubFindings -RunId 'R1' -Timestamp '2026-07-22 00:00:00Z' -SkipLinkCheck -Only 'A.md'
        $refuse = Join-Path $script:Root 'stub-refuse.ps1'
        Set-Content $refuse @('param($docPath,$repoRoot)','Write-Output "I cannot do that."')   # no CLAIMS_INSPECTED => inconclusive
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $refuse -RunId 'R2' -Timestamp '2026-07-22 01:00:00Z' -Only 'A.md'
        $store = Get-Content (Join-Path $script:Root 'docs/docs-audit-findings.json') -Raw | ConvertFrom-Json -AsHashtable
        $store.docs['A.md'].outcome | Should -Be 'FINDINGS'          # prior outcome preserved
        @($store.docs['A.md'].findings).Count | Should -Be 1
        # @(...) load-bearing: a single Where-Object match unwraps to a bare hashtable whose .Count is its KEY
        # count. Doubly required here: ConvertFrom-Json -AsHashtable guarantees hashtable entries.
        @($store.docs['A.md'].history | Where-Object { $_.outcome -eq 'AUDIT-INCONCLUSIVE' }).Count | Should -Be 1
    }
    It 'AUDIT-SUSPECT: claims 1 for a code-block-heavy doc' {
        Set-Content (Join-Path $script:Root 'A.md') @('# A','```bash','x','```','```bash','y','```','```bash','z','```')
        $one = Join-Path $script:Root 'stub-one.ps1'
        Set-Content $one @('param($docPath,$repoRoot)','Write-Output "CLAIMS_INSPECTED: 1"','Write-Output "FINDINGS: none"')
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $one -RunId 'R1' -Timestamp '2026-07-22 00:00:00Z' -SkipLinkCheck -Only 'A.md'
        (Get-Content (Join-Path $script:Root 'docs/docs-audit-log.md') -Raw) | Should -Match '- A.md — AUDIT-SUSPECT'
    }
    It 'partial failure: one doc failing (native non-zero exit) does not abort the others; completed docs keep their log lines' {
        $mixed = Join-Path $script:Root 'stub-mixed.ps1'
        # B models a REAL claude -p failure: a native command exits NON-ZERO with empty stdout (it does NOT throw
        # a PS error — agy plan-review F5). The parser sees no CLAIMS_INSPECTED => AUDIT-INCONCLUSIVE. A and C
        # audit clean. All three must still get a log line.
        Set-Content $mixed @(
            'param($docPath,$repoRoot)'
            'if ($docPath -eq "B.md") { exit 1 }'
            'Write-Output "CLAIMS_INSPECTED: 2"; Write-Output "FINDINGS: none"')
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $mixed -RunId 'R1' -Timestamp '2026-07-22 00:00:00Z' -SkipLinkCheck
        $LASTEXITCODE | Should -Be 0
        $log = Get-Content (Join-Path $script:Root 'docs/docs-audit-log.md') -Raw
        $log | Should -Match '- A.md — CLEAN'
        $log | Should -Match '- B.md — AUDIT-INCONCLUSIVE'   # the throw was caught, recorded, and did not abort
        $log | Should -Match '- C.md — CLEAN'
    }
    It 'a live lock (alive PID, fresh timestamp) makes a second start refuse cleanly (exit 2)' {
        # Write a lock owned by THIS test process (alive) with a fresh timestamp matching the run -Timestamp.
        Set-Content (Join-Path $script:Root 'docs/docs-audit.lock') @("$PID", '2026-07-22 00:00:00Z')
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $script:StubFindings -RunId 'R1' -Timestamp '2026-07-22 00:00:05Z' -SkipLinkCheck -Only 'A.md'
        $LASTEXITCODE | Should -Be 2
    }
    It 'a stale lock (past max-age) is reclaimed and the run proceeds' {
        Set-Content (Join-Path $script:Root 'docs/docs-audit.lock') @("$PID", '2026-07-22 00:00:00Z')
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $script:StubFindings -RunId 'R1' -Timestamp '2026-07-22 05:00:00Z' -SkipLinkCheck -Only 'A.md' -LockMaxAgeSec 3600
        $LASTEXITCODE | Should -Be 0
    }
    It 'the lock is released on completion (self-clearing)' {
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $script:StubFindings -RunId 'R1' -Timestamp '2026-07-22 00:00:00Z' -SkipLinkCheck -Only 'A.md'
        Test-Path (Join-Path $script:Root 'docs/docs-audit.lock') | Should -BeFalse
    }
    It '-WhatIf previews without taking the lock, invoking the audit, or writing any artifact' {
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $script:StubFindings -RunId 'R1' -Timestamp '2026-07-22 00:00:00Z' -SkipLinkCheck -WhatIf
        $LASTEXITCODE | Should -Be 0                                        # not a vacuous pass: the run exited cleanly (agy R2-F3)
        Test-Path (Join-Path $script:Root 'docs/docs-audit-findings.json') | Should -BeFalse
        Test-Path (Join-Path $script:Root 'docs/docs-audit-log.md')       | Should -BeFalse
        Test-Path (Join-Path $script:Root 'docs/docs-audit.lock')         | Should -BeFalse
    }
    It 'a failure that reports ONLY on stderr still records its cause (capstone C9)' {
        # The pre-existing diag test below emits its error on STDOUT, so it never exercised the real failure
        # shape: `claude` writes quota/auth/crash causes to STDERR and leaves stdout EMPTY. Measured: stderr was
        # drained but DISCARDED, so the log read `diag:(no output)` and the cause was lost.
        $errStub = Join-Path $script:Root 'stub-stderr.ps1'
        Set-Content $errStub @('param($docPath,$repoRoot)', '[Console]::Error.WriteLine("Error: 429 quota exceeded")', 'exit 1')
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $errStub -RunId 'R1' -Timestamp '2026-07-22 00:00:00Z' -SkipLinkCheck -Only 'A.md'
        $LASTEXITCODE | Should -Be 0
        $log = Get-Content (Join-Path $script:Root 'docs/docs-audit-log.md') -Raw
        $log | Should -Match '- A.md — AUDIT-INCONCLUSIVE'
        $log | Should -Match 'diag:Error: 429 quota exceeded'
        $log | Should -Not -Match 'diag:\(no output\)'
    }
    It 'stderr noise cannot inject a finding or a claim count into the parse (capstone C9)' {
        # stderr feeds the DIAGNOSTIC only; it must never reach the parser, or a chatty child could forge a
        # CLAIMS_INSPECTED line and turn a failed audit into a confident CLEAN.
        $spoof = Join-Path $script:Root 'stub-spoof.ps1'
        Set-Content $spoof @(
            'param($docPath,$repoRoot)'
            '[Console]::Error.WriteLine("CLAIMS_INSPECTED: 99")'
            '[Console]::Error.WriteLine("FINDINGS: none")'
            'exit 1')
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $spoof -RunId 'R1' -Timestamp '2026-07-22 00:00:00Z' -SkipLinkCheck -Only 'A.md'
        $log = Get-Content (Join-Path $script:Root 'docs/docs-audit-log.md') -Raw
        $log | Should -Match '- A.md — AUDIT-INCONCLUSIVE'   # NOT CLEAN — stderr did not reach the parser
        $log | Should -Not -Match 'claims:99'
    }
    It '-Continue skips docs a prior run CONFIRMED and re-audits the rest' {
        # Seed: A CLEAN (confirmed), B AUDIT-INCONCLUSIVE (not confirmed), C never audited.
        $one = Join-Path $script:Root 'stub-clean.ps1'
        Set-Content $one @('param($docPath,$repoRoot)','Write-Output "CLAIMS_INSPECTED: 3"','Write-Output "FINDINGS: none"')
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $one -RunId 'R1' -Timestamp '2026-07-22 00:00:00Z' -SkipLinkCheck -Only 'A.md'
        $refuse = Join-Path $script:Root 'stub-refuse.ps1'
        Set-Content $refuse @('param($docPath,$repoRoot)','Write-Output "nope"')
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $refuse -RunId 'R2' -Timestamp '2026-07-22 01:00:00Z' -SkipLinkCheck -Only 'B.md'
        # Resume: A must be SKIPPED (confirmed), B and C must be re-audited (B was never confirmed).
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $one -RunId 'R3' -Timestamp '2026-07-22 02:00:00Z' -SkipLinkCheck -Continue
        $LASTEXITCODE | Should -Be 0
        $log = Get-Content (Join-Path $script:Root 'docs/docs-audit-log.md') -Raw
        $r3 = ($log -split '## audit R3')[1]
        $r3 | Should -Not -Match '- A\.md'      # confirmed => skipped
        $r3 | Should -Match '- B\.md — CLEAN'   # NOT confirmed => retried
        $r3 | Should -Match '- C\.md — CLEAN'   # never audited => audited
    }
    It '-Continue on a fresh store audits everything (no prior confirmations to skip)' {
        $one = Join-Path $script:Root 'stub-clean2.ps1'
        Set-Content $one @('param($docPath,$repoRoot)','Write-Output "CLAIMS_INSPECTED: 3"','Write-Output "FINDINGS: none"')
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $one -RunId 'R1' -Timestamp '2026-07-22 00:00:00Z' -SkipLinkCheck -Continue
        $LASTEXITCODE | Should -Be 0
        $store = Get-Content (Join-Path $script:Root 'docs/docs-audit-findings.json') -Raw | ConvertFrom-Json -AsHashtable
        $store.docs.Keys.Count | Should -Be 3
    }
    It '-Continue never SKIPS a doc whose prior outcome was not confirmed (the false-clean trap)' {
        # A doc recorded AUDIT-TIMEOUT is UNAUDITED, not done. Skipping it would bake a non-result into the
        # punch-list as though it were a clean bill — the one failure that makes an audit worse than none.
        $slow = Join-Path $script:Root 'stub-slow2.ps1'
        Set-Content $slow @('param($docPath,$repoRoot)','Start-Sleep -Seconds 30','Write-Output "CLAIMS_INSPECTED: 1"')
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $slow -RunId 'R1' -Timestamp '2026-07-22 00:00:00Z' -SkipLinkCheck -TimeoutSec 3 -Only 'A.md'
        $ok = Join-Path $script:Root 'stub-ok.ps1'
        Set-Content $ok @('param($docPath,$repoRoot)','Write-Output "CLAIMS_INSPECTED: 4"','Write-Output "FINDINGS: none"')
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $ok -RunId 'R2' -Timestamp '2026-07-22 01:00:00Z' -SkipLinkCheck -Continue -Only 'A.md'
        $log = Get-Content (Join-Path $script:Root 'docs/docs-audit-log.md') -Raw
        ($log -split '## audit R2')[1] | Should -Match '- A\.md — CLEAN'   # retried, not skipped
    }
    It 'a failed audit records its CAUSE in the log, not a bare AUDIT-INCONCLUSIVE (agy R5-F1)' {
        $quota = Join-Path $script:Root 'stub-quota.ps1'
        Set-Content $quota @('param($docPath,$repoRoot)', 'Write-Output "Error: 429 API quota exceeded"')
        & pwsh -File $script:Audit -RepoRoot $script:Root -AuditStub $quota -RunId 'R1' -Timestamp '2026-07-22 00:00:00Z' -SkipLinkCheck -Only 'A.md'
        $LASTEXITCODE | Should -Be 0
        $log = Get-Content (Join-Path $script:Root 'docs/docs-audit-log.md') -Raw
        $log | Should -Match '- A.md — AUDIT-INCONCLUSIVE'
        $log | Should -Match 'diag:Error: 429 API quota exceeded'   # the operator can tell quota from a refusal
    }
}

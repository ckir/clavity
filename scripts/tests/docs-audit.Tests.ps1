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

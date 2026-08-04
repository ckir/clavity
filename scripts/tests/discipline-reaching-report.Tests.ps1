# The CONSUMER for .clavity/discipline-reaching.jsonl. ROADMAP section 0, step 1a.
#
# WHY A CONSUMER IS PART OF THE WORK AND NOT A FOLLOW-UP: "a record nobody reads is presence-checking with
# extra steps" - the exact failure this whole item exists to end. The record had to have a named reader
# before it was worth writing.
#
# THE THREE THINGS THIS REPORT MUST NOT DO, each of which would reintroduce a measured failure:
#   1. FOLD A NULL INTO A ZERO. A null count means the scan could not run; a zero means it ran and found
#      nothing. Averaging them together manufactures the confident-wrong answer this item was created to
#      remove. Nulls are excluded from totals and reported separately, broken down by scan_status.
#   2. PRINT A RATIO. There is no capture numerator in the schema at all, so a conversion figure is
#      unconstructible from this data - and `compactions` is an OPPORTUNITY count with no matching
#      delivery number, so dividing by it fabricates a rate. It is printed in its own section.
#   3. SAY "SESSIONS RUN". SessionEnd may not fire on every exit path, and a machine without jq records
#      nothing, so the denominator is unknowable. The report says sessions RECORDED.

Describe 'discipline-reaching-report.ps1' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Script = Join-Path $script:RepoRoot 'scripts/discipline-reaching-report.ps1'

        function New-Store { param([string[]]$Lines)
            $d = Join-Path ([IO.Path]::GetTempPath()) ("reach-rep-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $d '.clavity') -Force | Out-Null
            if ($Lines) { Set-Content -LiteralPath (Join-Path $d '.clavity/discipline-reaching.jsonl') -Value ($Lines -join "`n") }
            return $d
        }
        function Rec { param([int]$N, [int]$U, [int]$F, [int]$C, [string]$Status = 'ok', [string]$Sid = 's', [int]$V = 1)
            (@{ v=$V; session_id=$Sid; timestamp='2026-08-04T00:00:00Z'; reason='prompt_input_exit';
                dispatch_nudges=$N; dispatch_nudges_unstamped=$U; dispatch_fired=$F; compactions=$C;
                scan_status=$Status } | ConvertTo-Json -Compress)
        }
        function NullRec { param([string]$Status, [string]$Sid = 'n')
            '{"v":1,"session_id":"' + $Sid + '","timestamp":"2026-08-04T00:00:00Z","reason":"other",' +
            '"dispatch_nudges":null,"dispatch_nudges_unstamped":null,"dispatch_fired":null,' +
            '"compactions":null,"scan_status":"' + $Status + '"}'
        }
        function Run { param([string]$Dir, [int]$Last = 0)
            Push-Location $Dir
            try {
                if ($Last -gt 0) { & $script:Script -Last $Last 2>&1 | Out-String }
                else            { & $script:Script          2>&1 | Out-String }
            } finally { Pop-Location }
        }
    }

    It 'totals the delivery counts over the recorded sessions' {
        $d = New-Store @( (Rec 2 0 3 1), (Rec 1 0 1 0), (Rec 0 4 2 5) )
        try {
            $o = Run $d
            $o | Should -Not -BeNullOrEmpty
            $o | Should -Match 'reached\D+3\b'   # 2 + 1 + 0
            $o | Should -Match 'unstamped\D+4\b' # 0 + 0 + 4
            $o | Should -Match 'fired\D+6\b'     # 3 + 1 + 2
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'EXCLUDES null-count records from the totals and reports them by scan_status' {
        # The load-bearing case. Two unreadable sessions must not read as two sessions with zero nudges.
        $d = New-Store @( (Rec 5 0 5 0), (NullRec 'transcript_not_found'), (NullRec 'bounded_out') )
        try {
            $o = Run $d
            $o | Should -Match 'reached\D+5\b' -Because 'the two null records contribute NOTHING to a total'
            $o | Should -Match 'transcript_not_found\D+1'
            $o | Should -Match 'bounded_out\D+1'
            $o | Should -Match '(?i)not[- ]?(scanned|counted)|unscanned|incomplete' -Because 'the degraded rows must be visibly separate, not a footnote'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports sessions RECORDED, never sessions RUN' {
        $d = New-Store @( (Rec 1 0 1 0) )
        try {
            $o = Run $d
            $o | Should -Match '(?i)recorded'
            $o | Should -Not -Match '(?i)sessions run' -Because 'SessionEnd may not fire on every exit path, so that denominator is unknowable'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'prints NO ratio or percentage anywhere' {
        $d = New-Store @( (Rec 2 0 4 3), (Rec 1 0 2 1) )
        try {
            $o = Run $d
            $o | Should -Not -BeNullOrEmpty -Because 'an empty report would satisfy both negatives below vacuously'
            $o | Should -Not -Match '%'
            $o | Should -Not -Match '\d+\s*/\s*\d+' -Because 'a rate computed from this data is fabricated - there is no capture numerator and compactions is opportunity-only'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'keeps compactions in its OWN section, away from the delivery totals' {
        $d = New-Store @( (Rec 1 0 1 7) )
        try {
            $o = Run $d
            $o | Should -Match '(?i)context'
            $o | Should -Match 'compactions\D+7\b'
            # The opportunity count must not sit on the same line as a delivery count, which is how a
            # reader starts treating it as a denominator.
            ($o -split "`n" | Where-Object { $_ -match 'compactions' -and $_ -match '(?i)reached' }).Count |
                Should -Be 0
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'honours -Last to bound the window' {
        $d = New-Store @( (Rec 100 0 100 0), (Rec 1 0 1 0), (Rec 2 0 2 0) )
        try {
            $o = Run $d -Last 2
            $o | Should -Match 'reached\D+3\b' -Because 'only the final two records are in the window'
            $o | Should -Not -Match 'reached\D+103\b'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'counts an UNRECOGNISED schema version separately instead of parsing it' {
        $d = New-Store @( (Rec 3 0 3 0), (Rec 9 9 9 9 'ok' 'future' 99) )
        try {
            $o = Run $d
            $o | Should -Match 'reached\D+3\b' -Because 'a v99 record must not be added into v1 totals'
            $o | Should -Match '(?i)(unsupported|unknown|unrecognis)'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'survives a malformed line and says so rather than dying' {
        $d = New-Store @( (Rec 2 0 2 0), '{not json at all', (Rec 1 0 1 0) )
        try {
            $o = Run $d
            $o | Should -Match 'reached\D+3\b'
            $o | Should -Match '(?i)(unparseable|malformed|skipped)'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'says plainly that the PreCompact channel is unmeasured' {
        # Without this the report silently implies it covers the whole discipline. MEASURED: PreCompact
        # firings produce zero transcript records, so that channel is invisible here by construction.
        $d = New-Store @( (Rec 1 0 1 2) )
        try {
            $o = Run $d
            $o | Should -Match '(?i)precompact'
            $o | Should -Match '(?i)(unmeasured|not measured|cannot be measured)'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports cleanly when the store is <Case>' -ForEach @(
        @{ Case = 'absent';  Lines = $null }
        @{ Case = 'empty';   Lines = @() }
    ) {
        $d = if ($Case -eq 'absent') {
            $t = Join-Path ([IO.Path]::GetTempPath()) ("reach-rep-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $t -Force | Out-Null; $t
        } else { New-Store @() }
        try {
            $o = Run $d
            $o | Should -Match '(?i)(no records|nothing recorded|0 sessions recorded)'
            $o | Should -Not -Match '(?i)error|exception'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

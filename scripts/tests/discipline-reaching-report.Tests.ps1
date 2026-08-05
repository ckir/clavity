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
        function CapRec { param([string]$Tx, [string]$Sid = 'cap')
            (@{ v=2; session_id=$Sid; timestamp='2026-08-04T00:00:00Z'; reason='prompt_input_exit';
                transcript_path=$Tx; scan_status='deferred' } | ConvertTo-Json -Compress)
        }
        function CapRec3 { param([string]$Tx, [string]$Sid = 'cap3', [string]$Source = 'startup', [string]$Ts = '2026-08-05T00:00:00Z')
            (@{ v=3; session_id=$Sid; timestamp=$Ts; source=$Source; model='claude-opus-5';
                transcript_path=$Tx; scan_status='deferred' } | ConvertTo-Json -Compress)
        }
        # Same shape a real transcript uses, including the ARRAY content form. Expected: reached 2 (d1
        # duplicated + d2), unstamped 1, fired 1, compactions 2.
        function New-ScanTranscript {
            $p = Join-Path ([IO.Path]::GetTempPath()) ("rep-tx-" + [Guid]::NewGuid().ToString('N') + ".jsonl")
            $S = 'AGY-ANOMALIES/1'
            @(
                '{"type":"attachment","uuid":"d1","attachment":{"type":"hook_additional_context","hookEvent":"PreToolUse","hookName":"PreToolUse:Agent","content":["' + $S + ' relay."]}}'
                '{"type":"attachment","uuid":"d2","attachment":{"type":"hook_additional_context","hookEvent":"PreToolUse","hookName":"PreToolUse:Agent","content":"' + $S + ' relay."}}'
                '{"type":"attachment","uuid":"d1","attachment":{"type":"hook_additional_context","hookEvent":"PreToolUse","hookName":"PreToolUse:Agent","content":["' + $S + ' relay."]}}'
                '{"type":"attachment","uuid":"g1","attachment":{"type":"hook_additional_context","hookEvent":"PreToolUse","hookName":"PreToolUse:Agent","content":["AGY-ANOMALIES relay."]}}'
                '{"type":"attachment","uuid":"f1","attachment":{"type":"hook_additional_context","hookEvent":"PreToolUse","hookName":"PreToolUse:Agent","content":"BOTTOM-UP GATING."}}'
                '{"type":"user","uuid":"u1","message":{"role":"user","content":"grep for ' + $S + '"}}'
                '{"type":"attachment","uuid":"s1","attachment":{"type":"hook_success","hookEvent":"PreToolUse","hookName":"PreToolUse:Agent","command":"bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-anomaly-dispatch-reminder.sh\"","exitCode":0}}'
                '{"type":"attachment","uuid":"s2","attachment":{"type":"hook_success","hookEvent":"PreToolUse","hookName":"PreToolUse:Bash","command":"bash /x/other.sh","exitCode":0}}'
                '{"type":"user","uuid":"c1","isCompactSummary":true,"message":{"role":"user","content":"s"}}'
                '{"type":"user","uuid":"c2","isCompactSummary":true,"message":{"role":"user","content":"s"}}'
            ) -join "`n" | Set-Content -LiteralPath $p -Encoding utf8NoBOM
            return $p
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

    It 'SCANS a v2 capture row and produces the counts the hook no longer computes' {
        # v2 is the CAPTURE shape: the hook names a transcript and stops, because scanning at SessionEnd was
        # CANCELLED on shipped v17 twice. The analysis moved HERE, so this is where it must be proven.
        $tx = New-ScanTranscript
        $d  = New-Store @( (CapRec $tx) )
        try {
            $o = Run $d
            $o | Should -Not -BeNullOrEmpty
    $o | Should -Match 'stamped\s+:\s+2' -Because 'two distinct STAMPED deliveries, one duplicated -> deduped by uuid'
    $o | Should -Match 'unstamped\s+:\s+1' -Because 'one pre-stamp delivery must not be counted as stamped'
    $o | Should -Match 'fired\s+:\s+1' -Because 'one hook_success names our script; the other names a different hook'
            $o | Should -Match 'compactions\s+:\s+2'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'still reads a v1 row, because v17 SHIPPED that shape' {
        # An upgraded machine can hold both kinds in one file. Reading only the newest would silently drop
        # every session recorded before the split.
        $tx = New-ScanTranscript
        $d  = New-Store @( (Rec 5 0 5 0), (CapRec $tx) )
        try {
            $o = Run $d
    $o | Should -Match 'stamped\s+:\s+7' -Because 'the v1 row contributes 5 and the scanned v2 row contributes 2'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'records a v2 row whose transcript is GONE as an unknown, never a zero' {
        $d = New-Store @( (CapRec (Join-Path ([IO.Path]::GetTempPath()) 'vanished-transcript.jsonl')) )
        try {
            $o = Run $d
            $o | Should -Match 'transcript_not_found\D+1'
            $o | Should -Match '(?i)not[- ]?(scanned|counted)|unscanned|incomplete' -Because 'a transcript deleted before the report runs is an UNKNOWN, and the split makes that case reachable'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'COUNTS a v:3 row instead of routing it to unsupported' {
        $tx = New-ScanTranscript
        $d = New-Store @( (CapRec3 $tx) )
        try {
            $o = Run $d
            $o | Should -Match 'Sessions recorded\s*:\s*1'
            $o | Should -Not -Match 'unsupported schema version'
            $o | Should -Match 'reached the model, stamped\s*:\s*2' -Because 'the fixture transcript holds 2 stamped deliveries'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'collapses many rows of ONE session into one record, keeping the earliest source' {
        $tx = New-ScanTranscript
        $d = New-Store @(
            (CapRec3 $tx -Sid 'S1' -Source 'startup' -Ts '2026-08-05T08:00:00Z')
            (CapRec3 $tx -Sid 'S1' -Source 'compact' -Ts '2026-08-05T12:00:00Z')
            (CapRec3 $tx -Sid 'S1' -Source 'compact' -Ts '2026-08-05T16:00:00Z')
        )
        try {
            $o = Run $d
            $o | Should -Match 'Sessions recorded\s*:\s*1' -Because 'three fires, one session'
            $o | Should -Match 'reached the model, stamped\s*:\s*2' -Because 'the transcript must be counted ONCE, not three times'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'orders -Last N by the LATEST fire, not the earliest' {
        $tx = New-ScanTranscript
        $d = New-Store @(
            (CapRec3 $tx -Sid 'LONG'  -Source 'startup' -Ts '2026-08-05T08:00:00Z')
            (CapRec3 $tx -Sid 'SHORT' -Source 'startup' -Ts '2026-08-05T12:00:00Z')
            (CapRec3 $tx -Sid 'LONG'  -Source 'compact' -Ts '2026-08-05T18:00:00Z')
        )
        try {
            $o = Run $d -Last 1
            $o | Should -Match 'Sessions recorded\s*:\s*1'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT collapse v:1 rows that share a session id - their counts are INLINE' {
        # THE SCOPE GUARD. v:1 rows carry their delivery counts on the row itself, so collapsing two of
        # them would silently DISCARD the second row's numbers. v:1 was a SessionEnd hook with strictly
        # one row per session; only v:3 multi-fires. Rec's $Sid defaults to 's', so these three rows all
        # share an id - which is exactly the case an unconditional collapse would destroy.
        $d = New-Store @( (Rec 2 0 3 1), (Rec 1 0 1 0), (Rec 0 4 2 5) )
        try {
            $o = Run $d
            $o | Should -Match 'Sessions recorded\s*:\s*3' -Because 'three v:1 rows are three sessions, whatever ids they carry'
            $o | Should -Match 'reached the model, stamped\s*:\s*3' -Because '2 + 1 + 0 - no row may be dropped'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'survives a row whose session_id is EMPTY, which the hook really emits' {
        # The hook initialises sid='' and writes "session_id":"" when the payload carries none. Such a row
        # cannot be collapsed, so it is passed through - and it must still leave Merge-SessionRows carrying
        # last_seen, because the sort immediately after reads that property off EVERY row. Under
        # Set-StrictMode + $ErrorActionPreference='Stop' a single missing property kills the whole report.
        $tx = New-ScanTranscript
        $d = New-Store @( (CapRec3 $tx -Sid '' -Ts '2026-08-05T08:00:00Z'), (CapRec3 $tx -Sid 'OK' -Ts '2026-08-05T09:00:00Z') )
        try {
            $o = Run $d
            $o | Should -Match 'Sessions recorded\s*:\s*2' -Because 'an id-less row is its own session, not a crash and not a merge'
            $o | Should -Not -Match "(?i)cannot be found on this object"
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
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

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
#   3. SAY "SESSIONS RUN". The denominator is unknowable: sessions predating the install, sessions
#      suppressed by .no-agy, sessions outside a git repo (deliberately unrecorded), and sessions whose
#      registration silently failed. The report says sessions RECORDED - now meaning DISTINCT sessions.

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
            # A fixture that means "a FINISHED session" must not look like one written a second ago. The
            # report classifies a transcript touched in the last 15 minutes as `provisional` and keeps it
            # out of the totals, so a fresh mtime here would silently zero every count this helper exists
            # to provide. Tests that specifically exercise the freshness boundary set the mtime themselves,
            # in both directions, so this default does not weaken them.
            (Get-Item -LiteralPath $p).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddHours(-3)
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
            $o | Should -Not -Match '(?i)sessions run' -Because 'sessions predating install, .no-agy opt-outs, non-git dirs and silent registration failures all make the denominator unknowable'
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

    It 'keeps an UNSUPPORTED-version row out of the boot-source distribution even when it carries a source' {
        # THE THIRD VACUOUS ASSERTION, found by mutation on 2026-08-05. The source-counting guard reads
        # `$v -eq $SCHEMA_CAPTURE_3 -and ... -contains 'source'`, and deleting the VERSION half of it broke
        # NOTHING: all 22 tests still passed. Every fixture that carried a `source` was already v:3, so the
        # property check alone satisfied them, and `Should -Not -Match 'prompt_input_exit'` in the
        # distribution test passes because v:1 carries `reason` - not because the version guard works.
        #
        # This pins the version half on its own. A v99 row is the suite's established way of writing "a
        # schema this build does not know" (see the test above), and it is the case that actually matters:
        # source-counting happens BEFORE the version dispatch, so without the guard a future schema would
        # be counted as a hook FIRING and then dropped from `Sessions recorded` - a row present in one
        # total and absent from the other.
        $tx = New-ScanTranscript
        $d = New-Store @(
            (CapRec3 $tx -Sid 'REAL' -Source 'startup')
            ('{"v":99,"session_id":"FUTURE","timestamp":"2026-08-05T10:00:00Z","source":"teleport","scan_status":"ok"}')
        )
        try {
            $o = Run $d
            $o | Should -Match 'startup\s*:\s*1' -Because 'the real v:3 row still counts'
            $o | Should -Not -Match 'teleport' -Because 'an unsupported schema must not enter the boot-source distribution it is about to be dropped from'
            $o | Should -Match 'unsupported schema version\s*:\s*1' -Because 'and it must be reported as skipped, not silently vanish'
            $o | Should -Match 'Sessions recorded\s*:\s*1'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'orders -Last N CHRONOLOGICALLY across a year boundary, not alphabetically by a localised date' {
        # AGY-CAPSTONE round 1, CONFIRMED BY MEASUREMENT on this machine (culture el-GR).
        # ConvertFrom-Json does NOT hand back the ISO-8601 STRING - it parses it into a [System.DateTime].
        # `[string]$Row.timestamp` then formats it with the host's CurrentCulture, so the sort key becomes
        # "08/05/2026 08:00:00" / "01/01/2027 08:00:00" and an ALPHABETICAL sort puts January 2027 BEFORE
        # August 2026. -Last N then slices off the newest sessions and keeps the oldest.
        # Every fixture in this suite used same-day, increasing-hour timestamps, which masks it completely.
        $tx = New-ScanTranscript
        $d = New-Store @(
            (CapRec3 $tx -Sid 'OLDER' -Source 'startup' -Ts '2026-08-05T08:00:00Z')
            (CapRec3 $tx -Sid 'NEWER' -Source 'startup' -Ts '2027-01-01T08:00:00Z')
        )
        try {
            (Get-Item -LiteralPath $tx).LastWriteTimeUtc = (Get-Date).ToUniversalTime()
            $o = Run $d -Last 1
            $o | Should -Match 'Sessions recorded\s*:\s*1'
            $o | Should -Match 'NEWER' -Because '2027 is later than 2026 in every culture; only a string sort disagrees'
            $o | Should -Not -Match 'OLDER'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'degrades ONE row with a non-numeric count instead of killing the whole report' {
        # AGY-CAPSTONE round 3. `[int]"N/A"` throws, and under $ErrorActionPreference='Stop' that
        # terminating error takes down the entire run - so one corrupted or hand-edited field in one row
        # would destroy the reading of every other session. The row is now an UNKNOWN, which is the
        # bucket that already exists to say so.
        $d = New-Store @(
            (Rec 5 0 5 0 'ok' 'GOOD' 1)
            ('{"v":1,"session_id":"BAD","timestamp":"2026-08-05T00:00:00Z","reason":"x","dispatch_nudges":"N/A","dispatch_nudges_unstamped":null,"dispatch_fired":null,"compactions":null,"scan_status":"ok"}')
        )
        try {
            $o = Run $d
            $o | Should -Match 'Sessions recorded\s*:\s*2' -Because 'the bad row is still a recorded session'
            $o | Should -Match 'reached the model, stamped\s*:\s*5' -Because 'the GOOD row must still be counted, and the bad one must contribute nothing'
            $o | Should -Not -Match '(?i)cannot convert|invalid cast' -Because 'the report degrades a row; it does not die on one'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses to call a scan CLEAN when jq failed part-way through the transcript' {
        # AGY-CAPSTONE round 3, and the sharpest defect of the review. PowerShell's try/catch does NOT
        # fire for a NATIVE binary's non-zero exit, so a jq failure fell straight through to the success
        # tail: counts taken from whatever jq managed to emit before dying, and scan_status stamped 'ok'.
        # MEASURED: a transcript whose final line is truncated (a session killed mid-write - ordinary)
        # makes jq exit 5 while still emitting the earlier records, so the scan reported 1 delivery as a
        # COMPLETE reading when the real answer was unknown. That is Refusal #1 in its general form: a
        # partial result presented as an authoritative one.
        $tx = Join-Path ([IO.Path]::GetTempPath()) ("trunc-" + [Guid]::NewGuid().ToString('N') + ".jsonl")
        @(
            '{"type":"attachment","uuid":"d1","attachment":{"type":"hook_additional_context","hookEvent":"PreToolUse","hookName":"PreToolUse:Agent","content":["AGY-ANOMALIES/1 relay."]}}'
            '{"type":"attachment","uuid":"TRUNC","attachment":{"type":"hook_additional_context","hookEv'
        ) -join "`n" | Set-Content -LiteralPath $tx -Encoding utf8NoBOM
        (Get-Item -LiteralPath $tx).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddHours(-3)
        $d = New-Store @( (CapRec3 $tx -Sid 'TRUNC') )
        try {
            $o = Run $d
            $o | Should -Match 'scanned cleanly\s*:\s*0' -Because 'a scan whose tool failed is not a clean scan'
            $o | Should -Match 'not scanned\s*:\s*1'
            $o | Should -Match 'transcript_unreadable' -Because 'and it must be named as an unknown, not a count'
            $o | Should -Not -Match 'reached the model, stamped\s*:\s*1' -Because 'the partial count must never enter the totals'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'raises the FIRED BUT NEVER REACHED alarm for a COMPLETED session too' {
        # AGY-CAPSTONE round 3. The live-session alarm added in round 2 was pinned; the ORIGINAL
        # completed-session alarm never was. Every fixture with a finished session had reached > 0, so
        # deleting that branch outright left all 27 tests green. Two alarms, one covered.
        $tx = Join-Path ([IO.Path]::GetTempPath()) ("done-tx-" + [Guid]::NewGuid().ToString('N') + ".jsonl")
        '{"type":"attachment","uuid":"s1","attachment":{"type":"hook_success","hookEvent":"PreToolUse","hookName":"PreToolUse:Agent","command":"bash /x/agy-anomaly-dispatch-reminder.sh","exitCode":0}}' |
            Set-Content -LiteralPath $tx -Encoding utf8NoBOM
        (Get-Item -LiteralPath $tx).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddHours(-3)
        $d = New-Store @( (CapRec3 $tx -Sid 'DONE') )
        try {
            $o = Run $d
            $o | Should -Match 'scanned cleanly\s*:\s*1'
            $o | Should -Match 'hook fired\s*:\s*1'
            $o | Should -Match 'v15 failure signature' -Because 'fired with nothing reached is the whole reason this report exists'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'SURFACES a transcript path disagreement instead of silently picking one' {
        # AGY-CAPSTONE round 3. Merge-SessionRows sets path_disagreement and the report has a block to
        # print it - and nothing exercised either. Deleting the whole block left all 27 tests green, so a
        # guard written specifically to be LOUD could have gone silent unnoticed.
        $tx1 = New-ScanTranscript
        $tx2 = New-ScanTranscript
        $d = New-Store @(
            (CapRec3 $tx1 -Sid 'SPLIT' -Source 'startup' -Ts '2026-08-05T08:00:00Z')
            (CapRec3 $tx2 -Sid 'SPLIT' -Source 'compact' -Ts '2026-08-05T09:00:00Z')
        )
        try {
            $o = Run $d
            $o | Should -Match 'TRANSCRIPT PATH DISAGREEMENT'
            $o | Should -Match 'SPLIT'
            $o | Should -Match ([regex]::Escape((Split-Path -Leaf $tx2))) -Because 'the LATEST path is the one used, and the reader is told which'
        } finally { Remove-Item $d,$tx1,$tx2 -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'raises the FIRED BUT NEVER REACHED alarm for a LIVE session, not only a finished one' {
        # AGY-CAPSTONE round 2, and the worst defect in the epic. The v15 signature - the hook fired and
        # nothing reached the model - is the single reason this report exists. It was computed only over
        # $counted, and a session that is still running is `provisional`, so its counts are excluded.
        # MEASURED before the fix: a live session with fired=1, reached=0 printed `hook fired : 0` and NO
        # banner at all. An engineer running this DURING the outage - the one moment it matters - was told
        # nothing was wrong. The provisional bucket is right to keep partial counts out of the TOTALS; it
        # was wrong to keep them out of the ALARM.
        $tx = Join-Path ([IO.Path]::GetTempPath()) ("live-tx-" + [Guid]::NewGuid().ToString('N') + ".jsonl")
        '{"type":"attachment","uuid":"s1","attachment":{"type":"hook_success","hookEvent":"PreToolUse","hookName":"PreToolUse:Agent","command":"bash /x/agy-anomaly-dispatch-reminder.sh","exitCode":0}}' |
            Set-Content -LiteralPath $tx -Encoding utf8NoBOM
        $d = New-Store @( (CapRec3 $tx -Sid 'LIVE') )
        try {
            (Get-Item -LiteralPath $tx).LastWriteTimeUtc = (Get-Date).ToUniversalTime()
            $o = Run $d
            $o | Should -Match 'provisional\s*:\s*1'
            $o | Should -Match 'FIRED BUT NEVER REACHED' -Because 'the alarm must fire while the failure is HAPPENING'
            $o | Should -Match '(?i)still running|live|in flight' -Because 'and must say the reading is from an unfinished session'
            $o | Should -Match 'reached the model, stamped\s*:\s*0' -Because 'the partial counts still stay OUT of the totals'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'picks the earliest fire WITHIN one session across a year boundary too' {
        # AGY-CAPSTONE round 2. The year-boundary test above uses two SINGLE-ROW sessions, so it pins only
        # the OUTER sort. MEASURED: reverting the INTRA-GROUP sort in Merge-SessionRows back to
        # `[string]$_.timestamp` left all 25 tests green. There are two sorts and one test was covering one
        # of them. Here one session fires in Aug 2026 and again in Jan 2027, so a localised string sort
        # would make the 2027 compact look like the session's ORIGIN and report `began compact`.
        $tx = New-ScanTranscript
        $d = New-Store @(
            (CapRec3 $tx -Sid 'SPAN' -Source 'startup' -Ts '2026-08-05T08:00:00Z')
            (CapRec3 $tx -Sid 'SPAN' -Source 'compact' -Ts '2027-01-01T08:00:00Z')
        )
        try {
            (Get-Item -LiteralPath $tx).LastWriteTimeUtc = (Get-Date).ToUniversalTime()
            $o = Run $d
            $o | Should -Match 'Sessions recorded\s*:\s*1'
            $o | Should -Match 'began startup' -Because 'August 2026 precedes January 2027 chronologically'
            $o | Should -Not -Match 'began compact'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'adopts a later fire transcript when the EARLIEST row named none' {
        # AGY-CAPSTONE round 1. Merge-SessionRows keeps $g[0] for CONTENT, and only overrides
        # transcript_path when the collapsed rows DISAGREE (more than one distinct non-empty path). If the
        # earliest row named NO transcript and a later one did, there is exactly ONE distinct path, so the
        # disagreement branch never runs and the session keeps the earliest row's EMPTY path - reporting
        # transcript_not_found for a session whose transcript is right there and readable.
        $tx = New-ScanTranscript
        $d = New-Store @(
            ('{"v":3,"session_id":"S1","timestamp":"2026-08-05T08:00:00Z","source":"startup","model":"m","transcript_path":"","scan_status":"transcript_not_found"}')
            (CapRec3 $tx -Sid 'S1' -Source 'compact' -Ts '2026-08-05T09:00:00Z')
        )
        try {
            $o = Run $d
            $o | Should -Match 'Sessions recorded\s*:\s*1'
            $o | Should -Match 'scanned cleanly\s*:\s*1' -Because 'the session HAS a readable transcript; a later fire named it'
            $o | Should -Match 'reached the model, stamped\s*:\s*2' -Because 'and its counts must reach the totals'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
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

    It 'collapses many rows of ONE session into one record, scanning its transcript ONCE' {
        # RENAMED. The title used to claim "keeping the earliest source" and asserted no such thing - the
        # fixture is not provisional, so nothing here prints `source` at all, and flipping the merge to
        # keep the LATEST row left this test green. That rule is now pinned by the two tests below that
        # DO print it. This one proves what it can actually see: three fires collapse to one session and
        # the transcript is counted once rather than three times.
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
            (Get-Item -LiteralPath $tx).LastWriteTimeUtc = (Get-Date).ToUniversalTime()
            $o = Run $d -Last 1
            $o | Should -Match 'Sessions recorded\s*:\s*1'
            $o | Should -Match 'LONG' -Because 'LONG is still active at 18:00; ranked by birth it would sort older than SHORT and be dropped'
            $o | Should -Not -Match 'SHORT'
            # PINS CONTENT-FROM-EARLIEST. LONG fired startup at 08:00 and compact at 18:00; the collapsed
            # record must report how it BEGAN. Before the PROVISIONAL line printed `began`, flipping
            # Merge-SessionRows to keep the LATEST row broke nothing at all - measured, 25/25 still green.
            $o | Should -Match 'began startup' -Because 'the merge keeps the EARLIEST row for content'
            $o | Should -Match '2 fires' -Because 'and fire_count must survive the collapse it summarises'
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

    It 'reports a still-being-written transcript as provisional, not as scanned cleanly' {
        $tx = New-ScanTranscript
        $d = New-Store @( (CapRec3 $tx -Sid 'LIVE') )
        try {
            (Get-Item -LiteralPath $tx).LastWriteTimeUtc = (Get-Date).ToUniversalTime()
            $o = Run $d
            $o | Should -Match 'PROVISIONAL'
            $o | Should -Match 'scanned cleanly\s*:\s*0' -Because 'a live session is not a completed one'
            $o | Should -Match 'reached the model, stamped\s*:\s*0' -Because 'a partial count must not enter the DISPATCH RELAY totals'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports an OLD transcript as scanned cleanly, not provisional' {
        $tx = New-ScanTranscript
        $d = New-Store @( (CapRec3 $tx -Sid 'DONE') )
        try {
            (Get-Item -LiteralPath $tx).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddHours(-3)
            $o = Run $d
            $o | Should -Match 'scanned cleanly\s*:\s*1'
            $o | Should -Match 'reached the model, stamped\s*:\s*2'
            # ASSERT THE BUCKET REPORTS ZERO, don't assert the WORD is absent. `-Not -Match 'PROVISIONAL'`
            # was the first phrasing and it was wrong twice over: PowerShell's -Match is case-insensitive,
            # so it also forbade the summary line - and satisfying it meant DELETING that line when the
            # count is zero, which would make "no session was live" look identical to "this build does not
            # track live sessions". A zero must be stated, not implied by silence.
            $o | Should -Match 'provisional\s*:\s*0' -Because 'the bucket names itself even when empty'
            $o | Should -Not -Match 'PROVISIONAL\s+\(' -Because 'the per-session SECTION is what must be absent'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports the source distribution as INVOCATIONS and keeps legacy reasons out of it' {
        $tx = New-ScanTranscript
        $d = New-Store @(
            (CapRec3 $tx -Sid 'A' -Source 'startup' -Ts '2026-08-05T08:00:00Z')
            (CapRec3 $tx -Sid 'A' -Source 'compact' -Ts '2026-08-05T09:00:00Z')
            (Rec 1 0 0 0 'ok' 'OLD' 1)
        )
        try {
            $o = Run $d
            $o | Should -Match 'HOOK INVOCATIONS'
            $o | Should -Match 'startup\s*:\s*1'
            $o | Should -Match 'compact\s*:\s*1'
            $o | Should -Match 'legacy \(v1/v2\)\s*:\s*1' -Because 'v1 carries an EXIT reason, which answers a different question than a BOOT source'
            $o | Should -Not -Match 'prompt_input_exit' -Because 'an exit reason must never bucket into the boot-source distribution'
        } finally { Remove-Item $d,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

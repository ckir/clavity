# The DISCIPLINE-REACHING recorder (SessionEnd). ROADMAP section 0, step 1a. CAPTURE ONLY.
#
# THIS HOOK NAMES A SESSION AND ITS TRANSCRIPT, AND STOPS. Every count lives in the report
# (scripts/discipline-reaching-report.ps1) and is tested there.
#
# WHY, and it is the only reason that matters: the first version scanned the transcript HERE. It passed
# every test in this file and every direct invocation, then failed on SHIPPED v17 in production, twice -
# `SessionEnd hook ... failed: Hook cancelled` - writing NOTHING. The control was a diagnostic probe on the
# SAME event in the SAME environment doing no scanning: it wrote its row both times. Fast hook survives,
# multi-second hook is cancelled. Session teardown gives a hook far less time than its declared `timeout`.
#
# So the assertions below are mostly NEGATIVE - they exist to stop analysis creeping back into teardown,
# because a cancelled hook writes NO row, and no row is indistinguishable from a session that never ran:
# the silent zero this entire item exists to remove. That failure could not be caught by invoking the hook
# directly, which is the whole lesson.

Describe 'agy-discipline-reaching.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh'
        $script:Stamp = 'AGY-ANOMALIES/1'
        $bashDir = Split-Path -Parent (Get-GitBashOrThrow)
        $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')

        function New-CleanHome {
            $h = Join-Path ([IO.Path]::GetTempPath()) ("reach-home-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $h '.claude') -Force | Out-Null
            return $h
        }

        # A realistic transcript. This hook must NOT read it - the fixture exists so a capture row has a
        # real path to name, and so a regression that starts scanning would have something to find. The
        # counting expectations it encodes are asserted in discipline-reaching-report.Tests.ps1.
        function New-Transcript {
            $p = Join-Path ([IO.Path]::GetTempPath()) ("reach-tx-" + [Guid]::NewGuid().ToString('N') + ".jsonl")
            $lines = @(
                # --- OURS: two distinct stamped deliveries, one of them duplicated ---
                # d1 uses the ARRAY content shape, which is what a real transcript carries (MEASURED:
                # .attachment.content came back as ["AGY-ANOMALIES relay, ..."]). d2 uses the bare-string
                # shape. Both are exercised deliberately: a fixture that only modelled the string form
                # would pass here and MISS every real delivery, which is a test lying in the worst
                # direction - green against production data it cannot actually read.
                '{"type":"attachment","uuid":"d1","attachment":{"type":"hook_additional_context","hookEvent":"PreToolUse","hookName":"PreToolUse:Agent","content":["' + $script:Stamp + ' relay, both halves."]}}'
                '{"type":"attachment","uuid":"d2","attachment":{"type":"hook_additional_context","hookEvent":"PreToolUse","hookName":"PreToolUse:Agent","content":"' + $script:Stamp + ' relay, both halves."}}'
                '{"type":"attachment","uuid":"d1","attachment":{"type":"hook_additional_context","hookEvent":"PreToolUse","hookName":"PreToolUse:Agent","content":["' + $script:Stamp + ' relay, both halves."]}}'
                # --- REGRESSION 1: foreign hooks on the SAME hookName. Structure alone would count these.
                '{"type":"attachment","uuid":"f1","attachment":{"type":"hook_additional_context","hookEvent":"PreToolUse","hookName":"PreToolUse:Agent","content":"BOTTOM-UP GATING: pick the lowest tier."}}'
                '{"type":"attachment","uuid":"f2","attachment":{"type":"hook_additional_context","hookEvent":"PreToolUse","hookName":"PreToolUse:Agent","content":"BOTTOM-UP GATING: pick the lowest tier."}}'
                '{"type":"attachment","uuid":"f3","attachment":{"type":"hook_additional_context","hookEvent":"PreToolUse","hookName":"PreToolUse:Agent","content":"some other plugin entirely."}}'
                # --- A PRE-STAMP (v16-era) delivery: our text, no contract number. Counts as UNSTAMPED.
                '{"type":"attachment","uuid":"g1","attachment":{"type":"hook_additional_context","hookEvent":"PreToolUse","hookName":"PreToolUse:Agent","content":["AGY-ANOMALIES relay, both halves."]}}'
                # --- REGRESSION 2: the stamp inside AUTHORED records. The detector must not eat its own tail.
                '{"type":"user","uuid":"u1","message":{"role":"user","content":"grep for ' + $script:Stamp + ' in the transcript"}}'
                '{"type":"assistant","uuid":"a1","message":{"content":[{"type":"text","text":"the marker is ' + $script:Stamp + '"}]}}'
                # --- EXECUTION record for our script (attributed by `command`, which delivery records lack)
                '{"type":"attachment","uuid":"s1","attachment":{"type":"hook_success","hookEvent":"PreToolUse","hookName":"PreToolUse:Agent","command":"bash /x/plugin/hooks/agy-anomaly-dispatch-reminder.sh","exitCode":0}}'
                '{"type":"attachment","uuid":"s2","attachment":{"type":"hook_success","hookEvent":"PreToolUse","hookName":"PreToolUse:Bash","command":"bash /x/other-hook.sh","exitCode":0}}'
                # --- compactions
                '{"type":"user","uuid":"c1","isCompactSummary":true,"message":{"role":"user","content":"summary"}}'
                '{"type":"user","uuid":"c2","isCompactSummary":true,"message":{"role":"user","content":"summary"}}'
            )
            Set-Content -LiteralPath $p -Value ($lines -join "`n") -Encoding utf8NoBOM
            return $p
        }

        function Payload { param([string]$Cwd, [string]$Tx, [string]$Reason = 'prompt_input_exit', [string]$Sid = 'sess-1')
            $o = @{ cwd = ($Cwd -replace '\\','/'); session_id = $Sid; hook_event_name = 'SessionEnd'; reason = $Reason }
            if ($null -ne $Tx) { $o.transcript_path = ($Tx -replace '\\','/') }
            $o | ConvertTo-Json -Compress
        }
        function Get-Record { param([string]$Repo)
            $f = Join-Path $Repo '.clavity/discipline-reaching.jsonl'
            if (-not (Test-Path -LiteralPath $f)) { return $null }
            $lines = @(Get-Content -LiteralPath $f | Where-Object { $_.Trim() -ne '' })
            if ($lines.Count -eq 0) { return $null }
            return [pscustomobject]@{ Count = $lines.Count; Last = ($lines[-1] | ConvertFrom-Json); Raw = $lines }
        }
    }

    It 'writes exactly ONE well-formed record per invocation' {
        $r = New-TempRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            $rec = Get-Record $r
            $rec | Should -Not -BeNullOrEmpty -Because 'no record at all is the one outcome this design forbids'
            $rec.Count | Should -Be 1
            $rec.Last.v | Should -Be 2 -Because 'v:1 was the analyse-at-SessionEnd shape, SHIPPED in v17; the report reads both'
            $rec.Last.session_id | Should -BeExactly 'sess-1'
            $rec.Last.reason | Should -BeExactly 'prompt_input_exit'
            # Assert the RAW bytes, not the parsed object: ConvertFrom-Json coerces an ISO string into a
            # DateTime, which re-renders with 7 fractional digits, so a match on the parsed value tests
            # PowerShell's formatter rather than what this hook actually wrote to disk.
            $rec.Raw[-1] | Should -Match '"timestamp":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"'
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'CAPTURES ONLY - it names the transcript and does NOT count anything' {
        # THE LOAD-BEARING CONTRACT. Analysis moved OUT of this hook because scanning here was CANCELLED at
        # real session teardown on shipped v17, twice, writing nothing. A row carrying counts is proof the
        # scan came back - which is precisely what must never happen in a SessionEnd hook again.
        $r = New-TempRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            $rec = Get-Record $r
            $rec | Should -Not -BeNullOrEmpty
            $rec.Last.v | Should -Be 2 -Because 'v:1 was the analyse-at-SessionEnd shape and SHIPPED in v17; both can coexist'
            $rec.Last.transcript_path | Should -Not -BeNullOrEmpty -Because 'the report can only analyse a transcript this row names'
            $rec.Last.scan_status | Should -BeExactly 'deferred'
            foreach ($f in 'dispatch_nudges','dispatch_nudges_unstamped','dispatch_fired','compactions') {
                $rec.Last.PSObject.Properties.Name | Should -Not -Contain $f -Because "$f is the report's job; its presence here means scanning crept back into teardown"
            }
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does not read the transcript at all - an UNREADABLE path still yields a clean deferred row' {
        # If the hook touched the file, an unreadable path would change the outcome. It must not: the
        # verdict on readability belongs to the report, later, where there is time to reach it.
        $r = New-TempRepo; $h = New-CleanHome
        try {
            $bogus = Join-Path ([IO.Path]::GetTempPath()) 'no-such-transcript-xyz.jsonl'
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $bogus) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            $rec = Get-Record $r
            $rec.Last.scan_status | Should -BeExactly 'deferred' -Because 'the path was NAMED; whether it resolves is the report to discover'
            $rec.Last.transcript_path | Should -Match 'no-such-transcript-xyz'
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'preserves a REAL Windows transcript_path byte-for-byte' {
        # THE FIXTURE-FIDELITY REGRESSION. Every other test here hands the hook a path with FORWARD slashes
        # (Payload does a backslash-to-slash replace), so none could see either defect that the FIRST REAL
        # ROW exposed:
        #   1. @tsv ESCAPES BACKSLASHES - a Windows path came back doubled, so the row named a path that
        #      cannot resolve. It landed, and was useless.
        #   2. jq on Windows writes CRLF - every field carried a trailing CR. Under @tsv that hit only the
        #      LAST field and stayed hidden; one-field-per-line put one on cwd too, mkdir then failed on a
        #      path with an embedded CR, and the hook exited SILENTLY writing nothing.
        # A suite green over forward-slash fixtures is a test lying in the worst direction. Real payloads
        # carry backslashes, so this one does.
        $r = New-TempRepo; $h = New-CleanHome
        try {
            $winPath = 'C:\Users\user\.claude\projects\C--x\81fb317f.jsonl'
            $payload = @{ cwd = $r.Replace([char]92, [char]47); session_id = 'win'; reason = 'prompt_input_exit'
                          transcript_path = $winPath } | ConvertTo-Json -Compress
            $x = Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            $rec = Get-Record $r
            $rec | Should -Not -BeNullOrEmpty -Because 'a CR in cwd made mkdir fail and the hook write NOTHING - silence is the failure mode'
            $rec.Last.transcript_path | Should -BeExactly $winPath -Because 'the report can only open a path stored byte-exactly'
            $rec.Last.session_id | Should -BeExactly 'win' -Because 'a trailing CR would corrupt correlation too'
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'carries the exit path so STEP 0 item 2 is self-measuring' {
        $r = New-TempRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx -Reason 'clear') -Env @{ HOME = $h } | Out-Null
            (Get-Record $r).Last.reason | Should -BeExactly 'clear'
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'records a naming scan_status when the payload names NO transcript' -ForEach @(
        @{ Case = 'absent from the payload'; Kind = 'none' }
    ) {
        $r = New-TempRepo; $h = New-CleanHome
        try {
            $tx = if ($Kind -eq 'none') { $null } else { (Join-Path ([IO.Path]::GetTempPath()) 'definitely-not-here.jsonl') }
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            $rec = Get-Record $r
            $rec | Should -Not -BeNullOrEmpty -Because 'a degraded scan must still leave a record; silence is indistinguishable from a session that never ran'
            $rec.Last.scan_status | Should -BeExactly 'transcript_not_found' -Because 'no transcript was NAMED, which is knowable here without reading anything'
            $rec.Last.PSObject.Properties.Name | Should -Not -Contain 'dispatch_nudges' -Because 'an unknown recorded as 0 is this items own thesis inverted'
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'creates .clavity/ when it does not exist' {
        $r = New-TempRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            Test-Path -LiteralPath (Join-Path $r '.clavity') | Should -BeFalse -Because 'the fixture must start without it or this test proves nothing'
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h }
            Test-Path -LiteralPath (Join-Path $r '.clavity/discipline-reaching.jsonl') | Should -BeTrue
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'APPENDS across sessions rather than overwriting' {
        $r = New-TempRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx -Sid 'sess-1') -Env @{ HOME = $h } | Out-Null
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx -Sid 'sess-2') -Env @{ HOME = $h } | Out-Null
            $rec = Get-Record $r
            $rec.Count | Should -Be 2
            ($rec.Raw[0] | ConvertFrom-Json).session_id | Should -BeExactly 'sess-1'
            $rec.Last.session_id | Should -BeExactly 'sess-2'
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under .no-agy (<Scope>) and writes nothing' -ForEach @(
        @{ Scope = 'workspace' }, @{ Scope = 'global' }
    ) {
        $r = New-TempRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            if ($Scope -eq 'workspace') { New-Item -ItemType File -Path (Join-Path $r '.no-agy') -Force | Out-Null }
            else { New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null }
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            Get-Record $r | Should -BeNullOrEmpty
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 0 when jq is absent' {
        $r = New-TempRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h; PATH = $script:NoJqPath }
            $x.ExitCode | Should -Be 0 -Because 'SessionEnd runs at teardown; a non-zero here helps nobody'
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'has no non-zero exit anywhere in its source' {
        Test-Path -LiteralPath $script:Hook | Should -BeTrue -Because 'a scan over a missing file matches nothing and passes vacuously'
        $code = Get-Content -LiteralPath $script:Hook -Raw
        $code | Should -Not -BeNullOrEmpty -Because 'an empty body would satisfy the count below vacuously'
        $code | Should -Match '\bexit\s+0' -Because 'the hook must contain the fail-open exits this test claims to check'
        [regex]::Matches($code, '\bexit\s+[1-9]').Count | Should -Be 0
    }

    It 'ships byte-identically to clavity-classic' {
        $a = $script:Hook
        $b = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks/agy-discipline-reaching.sh'
        Test-Path -LiteralPath $a | Should -BeTrue
        Test-Path -LiteralPath $b | Should -BeTrue
        $ha = (Get-FileHash -LiteralPath $a -Algorithm SHA256).Hash
        $ha | Should -Not -BeNullOrEmpty
        (Get-FileHash -LiteralPath $b -Algorithm SHA256).Hash | Should -BeExactly $ha
    }
}

# The DISCIPLINE-REACHING recorder (SessionEnd). ROADMAP section 0, step 1a.
#
# WHAT IT ANSWERS, and the scope is deliberately narrow: does the PreToolUse dispatch relay REACH a driver,
# and how often? Everything here was measured before it was designed (STEP 0 in
# docs/superpowers/specs/2026-08-04-discipline-efficacy-design.md), and three measurements are encoded
# below as REGRESSIONS because each one already fooled a reviewer or the driver:
#
#   1. THE 6x OVER-COUNT. hookName is <Event>:<ToolName>, shared by every plugin registering on that tool,
#      and the delivery record carries no field naming the script. MEASURED on a real transcript: 6
#      structural matches on PreToolUse:Agent, of which ONE was ours. So a count that keys on structure
#      ALONE is wrong, and the fixture below contains foreign deliveries that must not be counted.
#   2. THE SELF-REFERENTIAL TRANSCRIPT. A control string never emitted by any hook went from 1 hit to 11
#      purely by being searched for - the detector pollutes its own evidence. The fixture therefore puts
#      the stamp inside user/assistant records too; those must not be counted.
#   3. DUPLICATION. Records repeat, bounded at 2x (87 of 1314 measured), so counts dedup by uuid.
#
# THE RECORD MUST ALWAYS LAND. A missing record and a degraded one must not look alike: an unreadable
# transcript records null counts plus a scan_status naming WHY, never a 0. A measured zero and an unknown
# are the same failure this whole item exists to remove.

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

        # A synthetic transcript whose EXPECTED answers are known by construction:
        #   dispatch_nudges = 2  (uuids d1, d2; d1 appears twice -> dedup)
        #   dispatch_fired  = 1  (one hook_success naming our script)
        #   compactions     = 2
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
            $rec.Last.v | Should -Be 1
            $rec.Last.session_id | Should -BeExactly 'sess-1'
            $rec.Last.reason | Should -BeExactly 'prompt_input_exit'
            # Assert the RAW bytes, not the parsed object: ConvertFrom-Json coerces an ISO string into a
            # DateTime, which re-renders with 7 fractional digits, so a match on the parsed value tests
            # PowerShell's formatter rather than what this hook actually wrote to disk.
            $rec.Raw[-1] | Should -Match '"timestamp":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"'
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'counts OUR stamped deliveries only - not another plugin sharing the hookName' {
        # THE 6x OVER-COUNT REGRESSION. The fixture holds 3 foreign deliveries on the identical hookName.
        $r = New-TempRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h }
            $rec = Get-Record $r
            $rec | Should -Not -BeNullOrEmpty
            $rec.Last.dispatch_nudges | Should -Be 2 -Because 'd1 (twice, deduped) and d2 are ours; f1/f2/f3 are a different hook on the same tool'
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT count the stamp appearing in authored user or assistant records' {
        # THE SELF-REFERENTIALITY REGRESSION, encoded: u1 and a1 both carry the stamp verbatim.
        $r = New-TempRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h }
            $rec = Get-Record $r
            $rec.Last.dispatch_nudges | Should -Be 2 -Because 'authored records carrying the stamp are not deliveries'
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'separates a PRE-STAMP delivery from no delivery at all' {
        # Without this field the whole adoption window is unreadable. MEASURED on a real transcript from a
        # pre-stamp install: fired=1, nudges=0 - which is character-for-character the v15 failure signature
        # (the hook ran, nothing reached the model) while the discipline was in fact working perfectly.
        # dispatch_nudges_unstamped is what tells those two apart until stamped builds are ubiquitous.
        $r = New-TempRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h }
            $rec = Get-Record $r
            $rec | Should -Not -BeNullOrEmpty
            $rec.Last.dispatch_nudges_unstamped | Should -Be 1 -Because 'g1 carries our text without the contract number'
            $rec.Last.dispatch_nudges | Should -Be 2 -Because 'a STAMPED delivery must not also be counted as unstamped'
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'records EXECUTION separately from DELIVERY - fired vs reached' {
        $r = New-TempRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h }
            $rec = Get-Record $r
            $rec.Last.dispatch_fired | Should -Be 1 -Because 'one hook_success names our script; the other names a different hook'
            $rec.Last.dispatch_nudges | Should -Be 2
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'records compactions as OPPORTUNITY, since PreCompact delivery is unobservable' {
        $r = New-TempRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h }
            $rec = Get-Record $r
            $rec.Last.compactions | Should -Be 2
            $rec.Last.PSObject.Properties.Name | Should -Not -Contain 'precompact_nudges' -Because 'PreCompact firings produce ZERO transcript records - a field promising that number cannot be produced'
            $rec.Last.PSObject.Properties.Name | Should -Not -Contain 'precompact_fired'
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'records NULL counts and a naming scan_status when the transcript is <Case>' -ForEach @(
        @{ Case = 'absent from the payload'; Kind = 'none' }
        @{ Case = 'a path that does not exist'; Kind = 'missing' }
    ) {
        $r = New-TempRepo; $h = New-CleanHome
        try {
            $tx = if ($Kind -eq 'none') { $null } else { (Join-Path ([IO.Path]::GetTempPath()) 'definitely-not-here.jsonl') }
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            $rec = Get-Record $r
            $rec | Should -Not -BeNullOrEmpty -Because 'a degraded scan must still leave a record; silence is indistinguishable from a session that never ran'
            $rec.Last.dispatch_nudges | Should -BeNullOrEmpty -Because 'an unknown recorded as 0 is this items own thesis inverted'
            $rec.Last.scan_status | Should -BeExactly 'transcript_not_found'
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'never pairs scan_status ok with a null count' {
        $r = New-TempRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h }
            $rec = Get-Record $r
            $rec.Last.scan_status | Should -BeExactly 'ok'
            $rec.Last.dispatch_nudges | Should -Not -BeNullOrEmpty
            $rec.Last.dispatch_fired  | Should -Not -BeNullOrEmpty
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
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

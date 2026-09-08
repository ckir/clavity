# The DISCIPLINE-REACHING recorder (SessionStart). ROADMAP section 0, step 1a. CAPTURE ONLY.
#
# THIS HOOK NAMES A SESSION AND ITS TRANSCRIPT, AND STOPS. Every count lives in the report
# (scripts/discipline-reaching-report.ps1) and is tested there.
#
# WHY, and it is the only reason that matters: the first version scanned the transcript HERE. It passed
# every test in this file and every direct invocation, then failed on SHIPPED v17 in production, twice -
# `SessionEnd hook ... failed: Hook cancelled` - writing NOTHING.
#
# WHAT THAT FAILURE WAS ACTUALLY CAUSED BY - and the wrong answer this file used to give. The old text here
# said "fast hook survives, multi-second hook is cancelled", i.e. that teardown starves a slow hook. That
# was WRONG and it cost three review rounds. The real cause: ${CLAUDE_PLUGIN_ROOT} DOES NOT RESOLVE at
# SessionEnd. Cancelled 3/3 with the variable; an absolute path from the SAME manifest worked 2/2. The
# "control" the old text cited differed in TWO ways at once - it did no scanning AND it used an absolute
# path - so it could never separate the two, and duration was the confound: a SLOWER hook registered
# elsewhere survived. One axis was varied three times and the other never. The recorder now runs at
# SessionStart, where the variable resolves.
#
# So the assertions below are mostly NEGATIVE - they exist to stop analysis creeping back into the hook.
# The reason survives the corrected diagnosis on its own merits: this hook now runs at EVERY session start,
# so it must be cheap; and a hook that fails to write leaves NO row, which is indistinguishable from a
# session that never ran - the silent zero this entire item exists to remove. That failure could not be
# caught by invoking the hook directly, which is the whole lesson.

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

        # ROADMAP section 31b. The hook now records ONLY where `.clavity/` ALREADY exists, because a
        # globally registered SessionStart hook has no business creating a directory in a repository that
        # never asked for this plugin. So every row that expects a CAPTURE needs a repo that has used the
        # plugin before, and this wrapper is that repo.
        #
        # It deliberately does NOT change the shared New-TempRepo in BashHookHelpers.ps1: twelve suites
        # use that helper, and giving them all a `.clavity/` they did not ask for would mask exactly the
        # footprint this section exists to remove. The zero-footprint row below uses the bare New-TempRepo
        # for the same reason - its whole subject is a repo WITHOUT the directory.
        function New-ClavityRepo {
            $d = New-TempRepo
            New-Item -ItemType Directory -Force -Path (Join-Path $d '.clavity') | Out-Null
            return $d
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

        function Payload { param([string]$Cwd, [string]$Tx, [string]$Source = 'startup', [string]$Sid = 'sess-1', [string]$Model = 'claude-opus-5')
            $o = @{ cwd = ($Cwd -replace '\\','/'); session_id = $Sid; hook_event_name = 'SessionStart'; source = $Source; model = $Model }
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
        $r = New-ClavityRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            $rec = Get-Record $r
            $rec | Should -Not -BeNullOrEmpty -Because 'no record at all is the one outcome this design forbids'
            $rec.Count | Should -Be 1
            $rec.Last.v | Should -Be 3 -Because 'v:1 (analyse-at-SessionEnd) SHIPPED in v17 and v:2 (SessionEnd capture) exists on dev machines; the report reads each by its own version'
            $rec.Last.session_id | Should -BeExactly 'sess-1'
            $rec.Last.source | Should -BeExactly 'startup'
            # Assert the RAW bytes, not the parsed object: ConvertFrom-Json coerces an ISO string into a
            # DateTime, which re-renders with 7 fractional digits, so a match on the parsed value tests
            # PowerShell's formatter rather than what this hook actually wrote to disk.
            $rec.Raw[-1] | Should -Match '"timestamp":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"'
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'CAPTURES ONLY - it names the transcript and does NOT count anything' {
        # THE LOAD-BEARING CONTRACT. Analysis moved OUT of this hook because scanning here was CANCELLED on
        # shipped v17, twice, writing nothing. A row carrying counts is proof the scan came back - which
        # must never happen in THIS hook again, whatever event it is registered on. It fires at every
        # session start now, so the cost is paid on every session rather than once at the end.
        $r = New-ClavityRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            $rec = Get-Record $r
            $rec | Should -Not -BeNullOrEmpty
            $rec.Last.v | Should -Be 3 -Because 'all three schema versions can coexist on an upgraded machine; the report reads each by its own version'
            $rec.Last.transcript_path | Should -Not -BeNullOrEmpty -Because 'the report can only analyse a transcript this row names'
            $rec.Last.scan_status | Should -BeExactly 'deferred'
            foreach ($f in 'dispatch_nudges','dispatch_nudges_unstamped','dispatch_fired','compactions') {
                $rec.Last.PSObject.Properties.Name | Should -Not -Contain $f -Because "$f is the report's job; its presence here means scanning crept back into the hook"
            }
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does not read the transcript at all - an UNREADABLE path still yields a clean deferred row' {
        # If the hook touched the file, an unreadable path would change the outcome. It must not: the
        # verdict on readability belongs to the report, later, where there is time to reach it.
        $r = New-ClavityRepo; $h = New-CleanHome
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
        $r = New-ClavityRepo; $h = New-CleanHome
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

    It 'carries the BOOT SOURCE so STEP 0 item 2 is self-measuring' {
        $r = New-ClavityRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx -Source 'clear') -Env @{ HOME = $h } | Out-Null
            (Get-Record $r).Last.source | Should -BeExactly 'clear'
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'writes schema v:3 with source and model, and no reason field' {
        $r = New-ClavityRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx -Source 'compact' -Model 'claude-opus-5[1m]') -Env @{ HOME = $h } | Out-Null
            $rec = Get-Record $r
            $rec.Last.v              | Should -Be 3
            $rec.Last.source         | Should -BeExactly 'compact'
            $rec.Last.model          | Should -BeExactly 'claude-opus-5[1m]'
            $rec.Last.scan_status    | Should -BeExactly 'deferred'
            $rec.Last.PSObject.Properties.Name | Should -Not -Contain 'reason' -Because 'source says how a session BEGAN; reason said how it ended'
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'records a naming scan_status when the payload names NO transcript' -ForEach @(
        @{ Case = 'absent from the payload'; Kind = 'none' }
    ) {
        $r = New-ClavityRepo; $h = New-CleanHome
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

    It 'creates NOTHING in a repository that has never used the plugin' {
        # ROADMAP section 31b, and this row is the inversion of the one it replaces - which asserted that
        # the hook CREATES `.clavity/` when absent. That was the defect: this hook is registered globally,
        # so it fired at every session start in every directory on the machine and left a directory in
        # repositories with nothing to do with clavity. MEASURED per hook in fresh throwaway repos: the two
        # siblings on this matcher created nothing and this one created a directory.
        #
        # The opt-in is PRIOR USE. `.clavity/` already exists wherever a discipline has ever run, so its
        # presence is the workspace saying it wants this; no new setting, nothing to remember.
        $r = New-TempRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            Test-Path -LiteralPath (Join-Path $r '.clavity') | Should -BeFalse -Because 'the fixture must start without it or this test proves nothing'
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0 -Because 'declining to record is not an error - the hook is fail-open and says nothing'
            Test-Path -LiteralPath (Join-Path $r '.clavity') | Should -BeFalse -Because 'a globally registered SessionStart hook must leave no trace in a repository that never asked for it'
            $x.StdOut | Should -BeNullOrEmpty -Because 'and it must not announce its own restraint either'
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'DOES record where .clavity/ already exists - the success-path counterpart' {
        # Without this row the one above passes against a hook that never records ANYWHERE, which is the
        # same silent zero this suite's header exists to prevent. A refusing half needs an accepting half.
        $r = New-ClavityRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h }
            Test-Path -LiteralPath (Join-Path $r '.clavity/discipline-reaching.jsonl') | Should -BeTrue
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'APPENDS across sessions rather than overwriting' {
        $r = New-ClavityRepo; $h = New-CleanHome; $tx = New-Transcript
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
        @{ Scope = 'workspace' }, @{ Scope = 'global' }, @{ Scope = 'root-from-subdir' }, @{ Scope = 'subdir-only' }
    ) {
        $r = New-ClavityRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            $cwdArg = $r
            switch ($Scope) {
                'workspace' { New-Item -ItemType File -Path (Join-Path $r '.no-agy') -Force | Out-Null }
                'global'    { New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null }
                'root-from-subdir' {
                    # THE SHIPPED BYPASS: the opt-out is at the repo ROOT that would be written to, while
                    # the session was launched in a SUBDIRECTORY. Before the fix this WROTE a row.
                    New-Item -ItemType File -Path (Join-Path $r '.no-agy') -Force | Out-Null
                    $cwdArg = Join-Path $r 'src'
                    New-Item -ItemType Directory -Path $cwdArg -Force | Out-Null
                }
                'subdir-only' {
                    # THE OTHER HALF OF THE SAME `if`, AND IT HAD NO ROW (AGY-TEST-AUDIT round A, GAP-6).
                    # The hook tests `[ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]`. Every scope
                    # above puts the opt-out at the repo ROOT - including 'root-from-subdir', whose
                    # subdirectory is the *cwd*, not the location of the file - so all three are satisfied
                    # by the FIRST operand alone. Deleting `|| [ -f "$cwd_path/.no-agy" ]` left the whole
                    # suite green. Here the opt-out exists ONLY in the subdirectory, which is the one
                    # arrangement that can tell the second operand apart from nothing at all: a developer
                    # opting one subtree out of a repo they still want recorded.
                    $cwdArg = Join-Path $r 'src'
                    New-Item -ItemType Directory -Path $cwdArg -Force | Out-Null
                    New-Item -ItemType File -Path (Join-Path $cwdArg '.no-agy') -Force | Out-Null
                }
            }
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $cwdArg $tx) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            Get-Record $r | Should -BeNullOrEmpty -Because 'an opt-out anywhere on the path to the write target must suppress the write'
        } finally { Remove-Item $r,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'writes NOTHING and creates no directory when cwd has no .git ancestor' {
        $d = Join-Path ([IO.Path]::GetTempPath()) ("nogit-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        $h = New-CleanHome; $tx = New-Transcript
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $d $tx) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            Test-Path -LiteralPath (Join-Path $d '.clavity') | Should -BeFalse -Because 'a session outside a repo has no project to attribute reaching to'
        } finally { Remove-Item $d,$h,$tx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 0 under a minimal PATH (the hook spawns no subprocess but mkdir)' {
        # RENAMED, not deleted. The hook no longer invokes jq at all, so the old name described a
        # dependency that no longer exists - but the assertion still means something: it proves the hook
        # fails OPEN when almost nothing is on PATH.
        $r = New-ClavityRepo; $h = New-CleanHome; $tx = New-Transcript
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r $tx) -Env @{ HOME = $h; PATH = $script:NoJqPath }
            $x.ExitCode | Should -Be 0 -Because 'a boot hook must fail open; a non-zero exit at SessionStart helps nobody and risks the session'
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

    Context '14c - the hook asserts the .clavity shield' {
        BeforeAll {
            $script:Fixtures = New-Object System.Collections.ArrayList   # FIXTURE HYGIENE
            # A throwaway repo with NO root .gitignore: in THIS repository the root .gitignore covers
            # .clavity/, which MASKS a broken shield and reports a false pass.
            function New-ReachingFixture {
                param([string]$Shield)
                $d = Join-Path ([IO.Path]::GetTempPath()) ("reachfx-" + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Force -Path $d | Out-Null
                [void]$script:Fixtures.Add($d)   # FIXTURE HYGIENE
                & git -C $d init -q
                & git -C $d config user.email t@t.t
                & git -C $d config user.name t
                & git -C $d config core.autocrlf false   # FIXTURE HYGIENE: never inherit the host's setting
                New-Item -ItemType Directory -Force -Path (Join-Path $d '.clavity') | Out-Null
                [IO.File]::WriteAllText((Join-Path $d '.clavity/.gitignore'), $Shield)
                [IO.File]::WriteAllText((Join-Path $d 'seed.txt'), "seed`n")
                & git -C $d add seed.txt; & git -C $d commit -q -m seed
                $d
            }
            function Invoke-Reaching {
                param([string]$Dir, [string]$SessionId = 'sess-abc')
                # `Get-GitBashOrThrow`, NOT bare `bash`: `Get-Command bash` is documented NON-DETERMINISTIC
                # right above in this same helpers file - locally it resolves to WSL's System32 bash.exe,
                # which cannot run a Windows-path hook and fails silently ("No such file or directory" on
                # stderr, nothing else observable). Every other row in this suite already goes through
                # Invoke-BashHook, which pins Git Bash the same way; this Context needs its own raw-stderr
                # capture (for the debounce row below) so it calls the resolved bash directly instead.
                $bash = Get-GitBashOrThrow
                $hook = (Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh') -replace '\\','/'
                $payload = (@{ cwd = ($Dir -replace '\\','/'); session_id = $SessionId; source = 'startup'; model = 'm'; transcript_path = 't' } | ConvertTo-Json -Compress)
                $errF = Join-Path ([IO.Path]::GetTempPath()) ("reach-" + [guid]::NewGuid().ToString('N') + ".err")
                try {
                    $payload | & $bash $hook 2> $errF | Out-Null
                    [pscustomobject]@{ Err = (Get-Content -Raw -LiteralPath $errF -ErrorAction SilentlyContinue) }
                } finally { Remove-Item -LiteralPath $errF -Force -ErrorAction SilentlyContinue }
            }
        }

        AfterAll {
            foreach ($f in $script:Fixtures) { Remove-Item -LiteralPath $f -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It 'RESTORES an emptied shield - an observable effect' {
            $d = New-ReachingFixture -Shield ''
            Invoke-Reaching -Dir $d | Out-Null
            (Get-Content -Raw -LiteralPath (Join-Path $d '.clavity/.gitignore')) |
                Should -Match '(?m)^\*$' -Because 'the hook must assert the shield before it writes into .clavity/'
        }

        It 'still writes its row (the shield call must not break capture)' {
            $d = New-ReachingFixture -Shield ''
            Invoke-Reaching -Dir $d | Out-Null
            (Get-Content -Raw -LiteralPath (Join-Path $d '.clavity/discipline-reaching.jsonl')) | Should -Match '"v":3'
        }

        It 'the FALLBACK restores an EMPTIED shield when the helper cannot be sourced (panel R3)' {
            # THE FALLBACK PATH NEEDS ITS OWN ORACLE. Every other row here exercises the helper, so a
            # broken else-branch is invisible to all of them - and it WAS broken: measured, the
            # `[ ! -f ] ... elif [ -s ]` form ran neither branch against a zero-byte shield, leaving the
            # 14d defect itself unfixed on exactly the path that exists to be a floor.
            $d = New-ReachingFixture -Shield ''
            $hookDir = Join-Path ([IO.Path]::GetTempPath()) ("nolib-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
            # Copy the hook WITHOUT agy-shield-lib.sh beside it, so the source fails and the else runs.
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh') -Destination (Join-Path $hookDir 'agy-discipline-reaching.sh')
            $payload = (@{ cwd = ($d -replace '\\','/'); session_id = 'sess-x'; source = 'startup'; model = 'm'; transcript_path = 't' } | ConvertTo-Json -Compress)
            $payload | & (Get-GitBashOrThrow) ((Join-Path $hookDir 'agy-discipline-reaching.sh') -replace '\\','/') 2>$null | Out-Null
            (Get-Content -Raw -LiteralPath (Join-Path $d '.clavity/.gitignore')) |
                Should -Match '(?m)^\*$' -Because 'the fallback is the floor; an emptied shield must still be restored without the helper'
            Remove-Item -LiteralPath $hookDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'the FALLBACK also shields a NON-EMPTY shield that lacks the bare * (AGY-TEST-AUDIT GAP-5)' {
            # THE ROW ABOVE USES -Shield '', WHICH TAKES THE `! -s` BRANCH. The `elif ! grep -qx '*'`
            # branch beside it - a shield that HAS content but no bare star - had no row at all, so both
            # deleting it and reverting its append to the unsafe form scored green.
            # THE FIXTURE DELIBERATELY OMITS THE TRAILING NEWLINE. That is what makes this row able to
            # fail: the branch appends with a LEADING newline precisely because a shield whose last line
            # has none would otherwise concatenate into `!keepme.md*` - one corrupted line, no bare `*`
            # anywhere, the directory still exposed. This is the defect a fix RE-INTRODUCED here twice
            # (panel R1 pasted the unpatched idiom into this very branch), so it earns a pinned fixture.
            $d = New-ReachingFixture -Shield '!keepme.md'
            $hookDir = Join-Path ([IO.Path]::GetTempPath()) ("nolib2-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh') -Destination (Join-Path $hookDir 'agy-discipline-reaching.sh')
            $payload = (@{ cwd = ($d -replace '\\','/'); session_id = 'sess-y'; source = 'startup'; model = 'm'; transcript_path = 't' } | ConvertTo-Json -Compress)
            $payload | & (Get-GitBashOrThrow) ((Join-Path $hookDir 'agy-discipline-reaching.sh') -replace '\\','/') 2>$null | Out-Null
            $shield = Get-Content -Raw -LiteralPath (Join-Path $d '.clavity/.gitignore')
            $shield | Should -Match '(?m)^\*$' -Because 'the per-DIRECTORY guarantee is unconditional; a shield with content but no star leaves every file in .clavity/ exposed to git add -A'
            $shield | Should -Match '(?m)^!keepme\.md$' -Because 'the star must be its OWN line - concatenated onto the last line it shields nothing and corrupts the human entry'
            Remove-Item -LiteralPath $hookDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'the FALLBACK WARNS - it does not fail silent - when it cannot assert the shield (capstone r2b)' {
            # THE TWO FALLBACK ROWS ABOVE BOTH SUCCEED, so neither could see the failure mode. MEASURED
            # before the fix, with the helper absent and .gitignore denied write: the hook exited 0 in
            # COMPLETE SILENCE, the shield never gained its `*`, the jsonl was written anyway, and
            # `git check-ignore` reported it NOT ignored. The PRIMARY path warns twice in that same case,
            # so the fallback was strictly weaker at the one thing it exists to guarantee.
            # The oracle is STDERR, not the shield contents: the hook cannot make a denied file writable,
            # and asserting it did would pin a fix nothing can implement. What it owes the operator is a
            # diagnosis.
            $d = New-ReachingFixture -Shield '!keepme.md'
            $gi = Join-Path $d '.clavity/.gitignore'
            $me = "$env:USERDOMAIN\$env:USERNAME"
            $hookDir = Join-Path ([IO.Path]::GetTempPath()) ("nolib3-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh') -Destination (Join-Path $hookDir 'agy-discipline-reaching.sh')
            $errF = Join-Path ([IO.Path]::GetTempPath()) ("reach-deny-" + [guid]::NewGuid().ToString('N') + ".err")
            try {
                # PLATFORM-BRANCHED, AND THE STDERR REDIRECT IS NOT DECORATION. This row first shipped
                # calling `icacls` bare and ungated, while the CORRECT idiom already sat in a sibling
                # suite this same session (agy-ledger-lib.Tests.ps1:413). On a host without icacls the
                # bare call raises CommandNotFoundException, and under Pester's $ErrorActionPreference
                # that TERMINATES - inside the finally below it would abort teardown midway and leak the
                # temp dir and the stderr file. WSL is a supported platform here, so that host is real.
                if ($IsWindows) { & icacls $gi /deny "${me}:(W)" 2>&1 | Out-Null }
                else            { & chmod 500 $gi 2>&1 | Out-Null }

                # THE PRECONDITION MUST ASK THE SAME SHELL THE CODE UNDER TEST USES, and asking .NET
                # instead is what broke this row on CI. MEASURED: the runner denied the append to
                # [IO.File]::AppendAllText while Git Bash - which is what actually runs the hook - wrote
                # it happily, so the probe said "deny took", the row did not skip, and the hook then
                # behaved as though nothing was denied. agy-ledger-lib.Tests.ps1:436-441 already carries
                # this exact rule for its own deny row; I read that comment the same day and still probed
                # with the wrong process. SKIP rather than fail - an unreachable state is not a regression.
                $probe = Join-Path $d 'probe-writable.sh'
                [IO.File]::WriteAllText($probe, ("printf 'x\n' >> .clavity/.gitignore" -replace "`r`n", "`n"))
                $pr = Start-Process -FilePath (Get-GitBashOrThrow) -ArgumentList @('probe-writable.sh') `
                        -WorkingDirectory $d -NoNewWindow -Wait -PassThru
                if ($pr.ExitCode -eq 0) {
                    Set-ItResult -Skipped -Because 'the write-deny did not take for THIS bash (elevated token, or a filesystem that ignores ACLs), so the unassertable-shield state is unreachable here'
                }
                $payload = (@{ cwd = ($d -replace '\\','/'); session_id = 'sess-deny'; source = 'startup'; model = 'm'; transcript_path = 't' } | ConvertTo-Json -Compress)
                $payload | & (Get-GitBashOrThrow) ((Join-Path $hookDir 'agy-discipline-reaching.sh') -replace '\\','/') 2> $errF | Out-Null
                $err = Get-Content -Raw -LiteralPath $errF -ErrorAction SilentlyContinue
                $err | Should -Match 'agy-shield:' -Because 'a shield it could not assert must be reported in the same vocabulary the helper uses'
                $err | Should -Match 'exposed to git' -Because 'the operator needs the CONSEQUENCE named, not just a failed write'
            }
            finally {
                # TEARDOWN MUST NOT BE ABLE TO THROW. Each step is independently guarded, so a missing
                # tool or an already-removed path cannot abort the ones after it.
                if ($IsWindows) { & icacls $gi /remove:d $me 2>&1 | Out-Null }
                else            { & chmod 600 $gi 2>&1 | Out-Null }
                Remove-Item -LiteralPath $errF -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $hookDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'the FALLBACK names READ as the cause when it cannot read the shield (capstone r2d)' {
            # THE ROW ABOVE PROVES IT WARNS; THIS ONE PROVES IT WARNS THE RIGHT THING. MEASURED under
            # WSL with chmod 200 and both preconditions probed - writable=YES, readable=NO - the first
            # version of this diagnostic said "check that it is a regular, WRITABLE file" while the file
            # was writable all along and READ was the real fault. Sending an operator to the wrong
            # permission is the failure agy-shield-lib.sh:214-220 already records folding once.
            #
            # THE FIXTURE IS A DIRECTORY, not an ACL, and that is what makes this row portable. A
            # Windows deny-READ ACE also blocks the OPEN (measured: icacls /deny R left the file neither
            # readable nor writable), so "writable but unreadable" cannot be built there at all. `grep`
            # against a directory exits 2 on BOTH Git Bash and WSL (measured), which is the same
            # greater-than-one code the real unreadable case produces - so this reaches the branch with
            # no permissions, no platform gate, and no skip.
            #
            # WHAT THIS FIXTURE DOES NOT REPRODUCE, stated because the comment above would otherwise
            # overclaim. MEASURED across both shells: `[ ! -s <dir> ]` is TRUE on Git Bash and FALSE on
            # WSL, so the directory reaches the verify through a DIFFERENT earlier branch on each - the
            # append arm on Windows, the grep arm on Linux - whereas a real chmod-200 shield takes the
            # grep arm on both. The verify runs after that if/elif either way, which is why this row is
            # sound on both platforms, but it pins the VERIFY's unreadable answer, NOT the exact path
            # taken to reach it. A row that needed the real path would have to be POSIX-gated.
            $d = New-ReachingFixture -Shield '!keepme.md'
            $gi = Join-Path $d '.clavity/.gitignore'
            Remove-Item -LiteralPath $gi -Force
            New-Item -ItemType Directory -Force -Path $gi | Out-Null
            $hookDir = Join-Path ([IO.Path]::GetTempPath()) ("nolib5-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh') -Destination (Join-Path $hookDir 'agy-discipline-reaching.sh')
            $errF = Join-Path ([IO.Path]::GetTempPath()) ("reach-unread-" + [guid]::NewGuid().ToString('N') + ".err")
            try {
                $payload = (@{ cwd = ($d -replace '\\','/'); session_id = 'sess-unread'; source = 'startup'; model = 'm'; transcript_path = 't' } | ConvertTo-Json -Compress)
                $payload | & (Get-GitBashOrThrow) ((Join-Path $hookDir 'agy-discipline-reaching.sh') -replace '\\','/') 2> $errF | Out-Null
                $err = Get-Content -Raw -LiteralPath $errF -ErrorAction SilentlyContinue
                $err | Should -Match 'could not READ' -Because 'grep exiting above 1 means unreadable, and that is a different fault from an unwritable shield'
                $err | Should -Not -Match 'regular, writable file whose contents' -Because 'naming the WRITE permission here sends the operator to investigate the one thing that is not wrong'
            }
            finally {
                Remove-Item -LiteralPath $errF -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $hookDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'the FALLBACK blames the DIRECTORY when the shield file was never created (capstone r2e)' {
            # THIS ROW EXISTS BECAUSE A MUTANT SAID IT DID NOT. Mutant J removed the existence arm and
            # NOTHING went red except the byte-identity row - the fix was folded and unpinned, which is
            # the state where a later "simplification" silently restores the defect.
            # MEASURED under WSL with `chmod 500 .clavity` (capstone round 2e): .clavity/ exists, so the
            # :116 gate lets the hook through, but the shield file cannot be created - and `grep` on a
            # MISSING file also exits 2, so without this arm the run lands in the unreadable message and
            # tells the operator to check the permissions of a file that does not exist.
            $d = New-ReachingFixture -Shield '!keepme.md'
            $gi = Join-Path $d '.clavity/.gitignore'
            $cl = Join-Path $d '.clavity'
            $me = "$env:USERDOMAIN\$env:USERNAME"
            Remove-Item -LiteralPath $gi -Force
            $hookDir = Join-Path ([IO.Path]::GetTempPath()) ("nolib7-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh') -Destination (Join-Path $hookDir 'agy-discipline-reaching.sh')
            $errF = Join-Path ([IO.Path]::GetTempPath()) ("reach-nocreate-" + [guid]::NewGuid().ToString('N') + ".err")
            try {
                if ($IsWindows) { & icacls $cl /deny "${me}:(W)" 2>&1 | Out-Null }
                else            { & chmod 500 $cl 2>&1 | Out-Null }
                # PRECONDITION, PROBED THROUGH THE SAME BASH THAT RUNS THE HOOK. Asking .NET instead is
                # what broke this row on CI: the runner denied [IO.File]::WriteAllText while Git Bash
                # created the file without trouble, so the probe reported the deny had taken, the row did
                # not skip, and the hook then found nothing wrong and said nothing. Same rule as
                # agy-ledger-lib.Tests.ps1:436-441. Skip rather than fail - an unreachable state is not a
                # regression.
                $probe = Join-Path $d 'probe-creatable.sh'
                [IO.File]::WriteAllText($probe, ("printf 'x\n' > .clavity/.gitignore" -replace "`r`n", "`n"))
                $pr = Start-Process -FilePath (Get-GitBashOrThrow) -ArgumentList @('probe-creatable.sh') `
                        -WorkingDirectory $d -NoNewWindow -Wait -PassThru
                if ($pr.ExitCode -eq 0) {
                    Remove-Item -LiteralPath $gi -Force -ErrorAction SilentlyContinue
                    Set-ItResult -Skipped -Because 'the directory write-deny did not take for THIS bash (elevated token, or a filesystem that ignores ACLs), so an uncreatable shield is unreachable here'
                }
                $payload = (@{ cwd = ($d -replace '\\','/'); session_id = 'sess-nocreate'; source = 'startup'; model = 'm'; transcript_path = 't' } | ConvertTo-Json -Compress)
                $payload | & (Get-GitBashOrThrow) ((Join-Path $hookDir 'agy-discipline-reaching.sh') -replace '\\','/') 2> $errF | Out-Null
                $err = Get-Content -Raw -LiteralPath $errF -ErrorAction SilentlyContinue
                $err | Should -Match 'could not CREATE' -Because 'a file that was never created is a DIRECTORY problem, not a file-permission one'
                $err | Should -Not -Match 'THIS process can read' -Because 'telling an operator to check the read permission of a non-existent file is an impossible errand'
            }
            finally {
                if ($IsWindows) { & icacls $cl /remove:d $me 2>&1 | Out-Null }
                else            { & chmod 700 $cl 2>&1 | Out-Null }
                Remove-Item -LiteralPath $errF -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $hookDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'the FALLBACK reports a TRACKED file, which a correct shield cannot hide (capstone r2e)' {
            # THE CONFIG BEING RIGHT IS NOT THE DIRECTORY BEING SAFE, and every other row here checks the
            # config. A bare `*` cannot hide a file git already TRACKS, so a force-added file inside
            # .clavity/ keeps leaking while the shield reads as perfect - and before this arm existed the
            # fallback fell SILENT in exactly that state. MEASURED under WSL: shield contains `*`, one
            # file force-added, `git check-ignore` says NOT ignored, fallback silent.
            # This fixture needs NO permissions and NO platform gate - `git add -f` behaves identically
            # everywhere - which is why it pins the arm more cheaply than the ACL rows above.
            $d = New-ReachingFixture -Shield "*`n"
            [IO.File]::WriteAllText((Join-Path $d '.clavity/discipline-reaching.jsonl'), "{}`n")
            & git -C $d add -f '.clavity/discipline-reaching.jsonl' 2>&1 | Out-Null
            & git -C $d commit -q -m 'force-track a file inside .clavity/' 2>&1 | Out-Null
            # PRECONDITION, asserted not assumed: git must really be failing to ignore it, or this row
            # would pass against a shield that is working perfectly well.
            & git -C $d check-ignore -q '.clavity/discipline-reaching.jsonl' 2>$null
            $LASTEXITCODE | Should -Not -Be 0 -Because 'the force-added file must actually be unignored, or there is nothing here to report'

            $hookDir = Join-Path ([IO.Path]::GetTempPath()) ("nolib6-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh') -Destination (Join-Path $hookDir 'agy-discipline-reaching.sh')
            $errF = Join-Path ([IO.Path]::GetTempPath()) ("reach-tracked-" + [guid]::NewGuid().ToString('N') + ".err")
            try {
                $payload = (@{ cwd = ($d -replace '\\','/'); session_id = 'sess-tracked'; source = 'startup'; model = 'm'; transcript_path = 't' } | ConvertTo-Json -Compress)
                $payload | & (Get-GitBashOrThrow) ((Join-Path $hookDir 'agy-discipline-reaching.sh') -replace '\\','/') 2> $errF | Out-Null
                $err = Get-Content -Raw -LiteralPath $errF -ErrorAction SilentlyContinue
                $err | Should -Match 'is TRACKED' -Because 'silence here is the exact failure this whole branch exists to prevent'
                $err | Should -Match 'git rm --cached' -Because 'a gitignore rule cannot supply the remedy, so the message must'
            }
            finally {
                Remove-Item -LiteralPath $errF -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $hookDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'the FALLBACK stays SILENT when it CAN assert the shield - the success-path counterpart' {
            # Without this row the one above is half a test: a hook that warned unconditionally would
            # satisfy it while making every healthy start noisy.
            $d = New-ReachingFixture -Shield '!keepme.md'
            $hookDir = Join-Path ([IO.Path]::GetTempPath()) ("nolib4-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh') -Destination (Join-Path $hookDir 'agy-discipline-reaching.sh')
            $errF = Join-Path ([IO.Path]::GetTempPath()) ("reach-ok-" + [guid]::NewGuid().ToString('N') + ".err")
            try {
                $payload = (@{ cwd = ($d -replace '\\','/'); session_id = 'sess-ok'; source = 'startup'; model = 'm'; transcript_path = 't' } | ConvertTo-Json -Compress)
                $payload | & (Get-GitBashOrThrow) ((Join-Path $hookDir 'agy-discipline-reaching.sh') -replace '\\','/') 2> $errF | Out-Null
                (Get-Content -Raw -LiteralPath $errF -ErrorAction SilentlyContinue) |
                    Should -Not -Match 'agy-shield:' -Because 'a healthy fallback start must say nothing at all'
            }
            finally {
                Remove-Item -LiteralPath $errF -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $hookDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'FORWARDS the payload session_id as the debounce key' {
            # THE ORACLE IS A LINE COUNT AGAINST A PERSISTENT FAULT, and it has to be: Stage A runs
            # unconditionally and ignores the key entirely, so a hook passing an empty or hard-coded key
            # still restores the shield and passes every row above. Shield restoration cannot detect a
            # broken forward. The TRACKED-file fault reports on every call until a human intervenes, so
            # two runs with the same real session_id emit ONCE and with an empty key emit TWICE.
            $d = New-ReachingFixture -Shield "*`n"
            New-Item -ItemType Directory -Force -Path (Join-Path $d '.clavity') | Out-Null
            [IO.File]::WriteAllText((Join-Path $d '.clavity/discipline-reaching.jsonl'), '')
            & git -C $d add -f '.clavity/discipline-reaching.jsonl'
            & git -C $d commit -q -m 'track the jsonl to create a PERSISTENT fault'

            $sid = 'sess-' + [guid]::NewGuid().ToString('N')
            $a = Invoke-Reaching -Dir $d -SessionId $sid
            $b = Invoke-Reaching -Dir $d -SessionId $sid
            $total = ([regex]::Matches(("$($a.Err)$($b.Err)"), 'git rm --cached')).Count
            $total | Should -Be 1 -Because 'with the real session_id forwarded, a persistent fault is reported ONCE across two runs'
            # THE COMMENT ABOVE NAMES "empty or hard-coded" AND THE ORACLE ONLY COVERS EMPTY. Two calls
            # under the same id emitting once proves they share A key - and a HARD-CODED non-empty key
            # is also "the same key twice", so it passes identically while the forwarding is gone. The
            # sibling row in the agy-mark suite had the same hole and was folded one round earlier; this
            # one was not swept for at the time, which is exactly why a lesson has to be grepped for
            # across SIBLING suites before it is called shipped.
            $c = Invoke-Reaching -Dir $d -SessionId ('sess-' + [guid]::NewGuid().ToString('N'))
            ([regex]::Matches("$($c.Err)", 'git rm --cached')).Count |
                Should -Be 1 -Because 'a DIFFERENT session_id must NOT be debounced - that is what separates a forwarded key from a constant'
        }
    }
}

# Behaviour of the AGY-ANOMALIES capture-side reminder (PreCompact, model-addressed).
#
# THE FAILURE MODE THIS SUITE EXISTS FOR IS SILENT. A three-arm sentinel measured that plain stdout at
# exit 0 reaches the model NOT AT ALL, and that stdout at exit 2 is dropped too (only stderr survives).
# So a hook written with a bare printf of the text produces no error, no output, and looks installed and
# working. Every assertion here therefore parses the JSON and inspects a KEY - never a substring of the
# raw stdout, which would pass on a payload the runtime rejects.
#
# hookSpecificOutput is INVALID for PreCompact (Claude Code rejects it and the owner sees a schema dump),
# so the absence assertion below is as load-bearing as the presence one.

Describe 'agy-anomaly-capture-reminder.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh'

        # ...\Git\usr\bin carries grep/awk but NOT jq, so pointing PATH here reproduces "jq absent"
        # deterministically. Git Bash itself is invoked by ABSOLUTE path inside Invoke-BashHook.
        $bashDir = Split-Path -Parent (Get-GitBashOrThrow)
        $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')

        # An empty HOME so a REAL ~/.claude/.no-agy on the dev box cannot silence the hook and hand us a
        # false green. Absolute paths only - MSYS mangles a relative HOME.
        function New-CleanHome {
            $h = Join-Path ([IO.Path]::GetTempPath()) ("anom-cap-home-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $h '.claude') -Force | Out-Null
            return $h
        }
        function New-Workspace {
            $w = Join-Path ([IO.Path]::GetTempPath()) ("anom-cap-ws-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $w -Force | Out-Null
            return $w
        }
        function Payload { param([string]$Cwd) @{ cwd = ($Cwd -replace '\\','/'); trigger = 'manual' } | ConvertTo-Json -Compress }

        # As Payload, but WITHOUT the forward-slashing. That convention is repo-wide and is exactly why the
        # Windows repo-root walk bug survived - a POSIX-shaped path cannot exercise it. '\\' as a regex
        # matches one backslash; '\\' as a .NET replacement is two literal characters, so this DOUBLES
        # them, which is what a JSON string needs.
        function RawPayload { param([string]$Cwd)
            '{"cwd":"' + ($Cwd -replace '\\', '\\') + '","trigger":"manual","hook_event_name":"PreCompact"}'
        }

        # PLACEMENT NOTE (not a change to test logic): moved inside this BeforeAll, matching New-CleanHome/
        # New-Workspace/Payload/RawPayload above. MEASURED against this repo's Pester v5.8.0: a bare
        # `function` statement directly in a Describe body (outside BeforeAll) is defined only during the
        # Discovery pass and is gone by the time It blocks run in the Run pass -- CommandNotFoundException.
        # Bodies are otherwise byte-identical to the dispatched text.
        #
        # One isolated session: a fresh HOME, a fresh workspace, a fresh TMPDIR, and a unique session id.
        # The TMPDIR isolation is load-bearing: the gate's markers are named by session id, so two tests that
        # share a temp dir AND a session id would silently depend on execution order.
        function New-GateEnv {
            $h = New-CleanHome
            $t = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $t -Force | Out-Null
            @{ Home = $h; Tmp = $t; Sid = [guid]::NewGuid().ToString() }
        }
        function Invoke-Prompt { param($g, $w)
            Invoke-BashHook -HookPath $script:Hook `
                -Payload ('{"cwd":"' + ($w -replace '\\','/') + '","session_id":"' + $g.Sid + '"}') `
                -Arguments @('UserPromptSubmit') `
                -Env @{ HOME = $g.Home; TMPDIR = $g.Tmp }
        }

        # The message VERBATIM. Asserted WHOLE via [regex]::Escape, never by bookend fragments: a prior
        # epic measured that bookend assertions left ~95% of a 399-character clause unguarded, and an
        # audit mutant that deleted the operative sentence from all four hooks left a 45-test suite GREEN.
        $script:CaptureMsg = 'AGY-ANOMALIES/1 check BEFORE COMPACTION: did you VERIFY a defect this session that is OUTSIDE your current task and is not yet in .clavity/local-anomalies.md? Capture it now via the open-issues skill - one line: - [type] fact * path:LINE * DATE * task=<what you were doing>. Uncaptured anomalies are lost at compaction. NOT an anomaly: a test you expected to fail, an error in the work you are actively doing, or anything you have not verified by measurement. If nothing qualifies, do nothing - a speculative entry is worse than none, because it lands on a blocking triage gate.'
    }

    # ISOLATION, not a test-logic change: $TestDrive persists across every It in this container run (it is
    # torn down once, at the very end), so the gate-tests' New-GateEnv directories -- none of which have
    # their own cleanup -- otherwise accumulate and are visible to any later test that sweeps $TestDrive.
    # MEASURED: 'does not let a session id escape the marker directory' passes alone and fails after the
    # 8 preceding gate tests, tripping on a SIBLING test's own (correct) marker directory, not an escape.
    AfterEach {
        Get-ChildItem -Path $TestDrive -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'emits a top-level systemMessage and NOT hookSpecificOutput' {
        $w = New-Workspace; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $j = $r.StdOut | ConvertFrom-Json
            $j.systemMessage      | Should -Not -BeNullOrEmpty
            $j.PSObject.Properties.Name | Should -Not -Contain 'hookSpecificOutput' -Because 'hookSpecificOutput is invalid for PreCompact and the runtime rejects the whole payload'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'delivers the capture directive WHOLE' {
        $w = New-Workspace; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            ($r.StdOut | ConvertFrom-Json).systemMessage | Should -Match ([regex]::Escape($script:CaptureMsg))
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'states the verification bar and the in-scope exclusion' {
        # agy named the failure mode this wording prevents - "Pre-Compaction False-Capture Rush": under
        # context pressure the model logs IN-FLIGHT, IN-SCOPE work as an anomaly without meeting the bar.
        # These two clauses are the mitigation, pinned separately so a future reword cannot drop them
        # while still matching some other part of the message.
        $w = New-Workspace; $h = New-CleanHome
        try {
            $m = (Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }).StdOut | ConvertFrom-Json
            $m.systemMessage | Should -Match ([regex]::Escape('anything you have not verified by measurement'))
            $m.systemMessage | Should -Match ([regex]::Escape('an error in the work you are actively doing'))
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'still DELIVERS the JSON envelope when jq is absent' {
        # Exit 0 alone is NOT the requirement. A hook that exits 0 and emits nothing is the exact
        # invisible zero this whole change exists to remove, and it would pass an exit-code-only test.
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{"cwd":"."}' -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $r.ExitCode | Should -Be 0
            $j = $r.StdOut | ConvertFrom-Json   # throws if the fallback emitted plain text
            $j.systemMessage | Should -Match ([regex]::Escape($script:CaptureMsg))
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'delivers an IDENTICAL message with and without jq' {
        # The anti-drift guard. The two emission paths are separate code; without this, one can be
        # reworded and the other left behind, and each path passes its own test.
        #
        # THE NON-EMPTY ASSERTION IS NOT DECORATION. Equality alone is satisfied when BOTH paths emit
        # nothing - MEASURED: with the hook absent entirely, both sides decoded to $null, $null equalled
        # $null, and this was the ONE test in the suite that passed green against a hook that did not
        # exist. An anti-drift guard that certifies two channels as consistent because neither says
        # anything is the same invisible zero the rest of this file exists to reject.
        $w = New-Workspace; $h = New-CleanHome
        try {
            $withJq = ((Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }).StdOut | ConvertFrom-Json).systemMessage
            $noJq   = ((Invoke-BashHook -HookPath $script:Hook -Payload '{"cwd":"."}' -Env @{ PATH = $script:NoJqPath; HOME = $h }).StdOut | ConvertFrom-Json).systemMessage
            $withJq | Should -Not -BeNullOrEmpty -Because 'two silent paths are trivially identical'
            $noJq   | Should -Not -BeNullOrEmpty -Because 'two silent paths are trivially identical'
            $noJq | Should -BeExactly $withJq
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a WORKSPACE .no-agy' {
        $w = New-Workspace; $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $w '.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a GLOBAL .no-agy' {
        $w = New-Workspace; $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a GLOBAL .no-agy even when jq is absent' {
        # Without this the kill-switch is honoured only on the jq path, and a machine with no jq gets an
        # unsuppressable nudge forever - the same defect agy-anomaly-reminder.sh:22-25 records fixing.
        $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{"cwd":"."}' -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # --- .no-agy at the REPO ROOT, session cwd in a SUBDIRECTORY ---------------------------------
    # Each silence case is paired with a positive control, and the CONTROL is the load-bearing half:
    # measured on a sibling hook, a broken walk produced silence indistinguishable from a working
    # kill-switch, and only the control went red.
    It 'is SILENT when .no-agy is at the repo root and cwd is a subdirectory' {
        $repo = New-TempRepo; $h = New-CleanHome
        try {
            $sub = Join-Path $repo 'src'
            New-Item -ItemType Directory -Path $sub -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $repo '.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (RawPayload $sub) -Env @{ HOME = $h }
            $r.StdOut | Should -BeNullOrEmpty -Because 'an opt-out at the repo root must suppress this hook from a subdirectory'
        } finally { Remove-Item $repo,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'DOES deliver from that same subdirectory when .no-agy is absent (positive control)' {
        $repo = New-TempRepo; $h = New-CleanHome
        try {
            $sub = Join-Path $repo 'src'
            New-Item -ItemType Directory -Path $sub -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (RawPayload $sub) -Env @{ HOME = $h }
            ($r.StdOut | ConvertFrom-Json).systemMessage | Should -BeExactly $script:CaptureMsg -Because 'without the opt-out it must still deliver - otherwise the silence test proves nothing'
        } finally { Remove-Item $repo,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'honours a root .no-agy from a subdirectory on the DEGRADED (no jq) path too' {
        # This path used to test "./.no-agy" - the PROCESS cwd, not the session workspace - so it could
        # not honour any workspace opt-out at all when the two differ. Nothing covered it.
        $repo = New-TempRepo; $h = New-CleanHome
        try {
            $sub = Join-Path $repo 'src'
            New-Item -ItemType Directory -Path $sub -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $repo '.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (RawPayload $sub) -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $r.StdOut | Should -BeNullOrEmpty -Because 'the degraded path must honour the same root opt-out as the jq path'
        } finally { Remove-Item $repo,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'DOES deliver from that subdirectory without .no-agy when jq is absent (degraded positive control)' {
        $repo = New-TempRepo; $h = New-CleanHome
        try {
            $sub = Join-Path $repo 'src'
            New-Item -ItemType Directory -Path $sub -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (RawPayload $sub) -Env @{ PATH = $script:NoJqPath; HOME = $h }
            ($r.StdOut | ConvertFrom-Json).systemMessage | Should -BeExactly $script:CaptureMsg -Because 'the degraded path must still deliver without an opt-out'
        } finally { Remove-Item $repo,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 0 and still delivers on a malformed payload' {
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload 'not json at all {{{' -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            ($r.StdOut | ConvertFrom-Json).systemMessage | Should -Not -BeNullOrEmpty
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'emits a message free of backtick, apostrophe, double quote and backslash' {
        # Scan the EMITTED text, not the script source: the source may legitimately carry all four in
        # comments, so a whole-file scan would be both wrong and permanently red.
        # Backtick and apostrophe are bash quoting hazards (a backtick in a double-quoted string is
        # command substitution). Double quote and backslash would break the hand-built JSON envelope on
        # the jq-absent path, which has no escaping machinery.
        $w = New-Workspace; $h = New-CleanHome
        try {
            $m = ((Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }).StdOut | ConvertFrom-Json).systemMessage
            $bytes = [Text.Encoding]::UTF8.GetBytes($m)
            @($bytes | Where-Object { $_ -eq 0x60 }).Count | Should -Be 0 -Because 'backtick'
            @($bytes | Where-Object { $_ -eq 0x27 }).Count | Should -Be 0 -Because 'apostrophe'
            @($bytes | Where-Object { $_ -eq 0x22 }).Count | Should -Be 0 -Because 'double quote'
            @($bytes | Where-Object { $_ -eq 0x5C }).Count | Should -Be 0 -Because 'backslash'
            @($bytes | Where-Object { $_ -gt 127 }).Count  | Should -Be 0 -Because 'non-ASCII'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'emits the compaction wording and a systemMessage envelope when invoked as PreCompact' {
        $w = New-Workspace; $h = New-CleanHome
        $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Arguments @('PreCompact') -Env @{ HOME = $h }
        $r.Stdout | Should -Match 'BEFORE COMPACTION'
        ($r.Stdout | ConvertFrom-Json).systemMessage      | Should -Not -BeNullOrEmpty
        ($r.Stdout | ConvertFrom-Json).hookSpecificOutput | Should -BeNullOrEmpty
    }

    It 'defaults to PreCompact behaviour when given NO argument' {
        # REGRESSION GUARD for every existing caller. hooks.json registers the PreCompact hook without an
        # argument today, and Task 3 does not change that line.
        $w = New-Workspace; $h = New-CleanHome
        $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
        $r.Stdout | Should -Match 'BEFORE COMPACTION'
    }

    It 'emits NOTHING on the first prompt of a session' {
        # THE CONTROL. Without it, the emission test below passes even if the gate never closes.
        $g = New-GateEnv; $w = New-Workspace
        (Invoke-Prompt $g $w).Stdout | Should -BeNullOrEmpty -Because 'at prompt 1 the driver has done no work and can have observed nothing'
    }

    It 'does NOT say BEFORE COMPACTION when it emits on UserPromptSubmit' {
        # On a prompt event there is no compaction, and a reminder describing a moment that is not happening
        # trains the reader to discount it.
        $g = New-GateEnv; $w = New-Workspace
        $null = Invoke-Prompt $g $w
        $out  = (Invoke-Prompt $g $w).Stdout
        $out | Should -Not -Match 'BEFORE COMPACTION'
        $out | Should -Match 'AGY-ANOMALIES/1'
        ($out | ConvertFrom-Json).hookSpecificOutput.hookEventName    | Should -BeExactly 'UserPromptSubmit'
        ($out | ConvertFrom-Json).hookSpecificOutput.additionalContext | Should -Not -BeNullOrEmpty
    }

    It 'emits at most once per session' {
        $g = New-GateEnv; $w = New-Workspace
        $null  = Invoke-Prompt $g $w
        $two   = (Invoke-Prompt $g $w).Stdout
        $three = (Invoke-Prompt $g $w).Stdout
        $four  = (Invoke-Prompt $g $w).Stdout
        $two   | Should -Not -BeNullOrEmpty
        $three | Should -BeNullOrEmpty
        $four  | Should -BeNullOrEmpty
    }

    It 'treats a DIFFERENT session id as a fresh session' {
        # Guards the gate keying on the right thing. Keyed on anything session-invariant, the second session
        # on a machine would be suppressed forever.
        $w = New-Workspace
        $a = New-GateEnv
        $b = @{ Home = $a.Home; Tmp = $a.Tmp; Sid = [guid]::NewGuid().ToString() }  # SAME tmp, different session
        $null = Invoke-Prompt $a $w
        $null = Invoke-Prompt $a $w
        $null = Invoke-Prompt $b $w
        (Invoke-Prompt $b $w).Stdout | Should -Not -BeNullOrEmpty
    }

    It 'falls back to a second marker location when TMPDIR is not writable' {
        # The gate must survive an unwritable TMPDIR rather than either going silent forever or emitting on
        # every prompt. HOME is writable here, so the fallback location carries the session.
        #
        # MEASURED 2026-08-07: A MERELY NONEXISTENT NESTED PATH IS NOT UNWRITABLE. The gate's own
        # `[ -d "$_cand" ] || mkdir -p "$_cand"` CREATES it, and the marker write then succeeds. An earlier
        # draft set $g.Tmp to 'definitely-not-a-directory/nested' and so exercised the ORDINARY path while
        # claiming to exercise the fallback -- it passed vacuously. The only portable way to make a location
        # genuinely unusable is to put a regular FILE where a parent directory component must be; `mkdir -p`
        # then fails ENOTDIR. Verified: mkdir -p on ./blocker/nested with ./blocker a file -> "Not a directory".
        $g = New-GateEnv; $w = New-Workspace
        $blocker = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Set-Content -LiteralPath $blocker -Value 'x' -NoNewline
        $g.Tmp = Join-Path $blocker 'nested'
        $null  = Invoke-Prompt $g $w                      # prompt 1: suppressed via the fallback marker
        (Invoke-Prompt $g $w).Stdout | Should -Not -BeNullOrEmpty   # prompt 2: emits
        (Invoke-Prompt $g $w).Stdout | Should -BeNullOrEmpty        # prompt 3: gated, NOT spamming
    }

    It 'warns on stderr and stays SILENT when NO marker location is writable' {
        # THE CORRECTED TRADE. An earlier draft fell through to emit here, which means emitting on EVERY
        # prompt for the rest of the session -- the high-frequency spam this plan's own rationale calls worse
        # than no prompt at all. The operator gets a diagnostic; the model gets nothing.
        #
        # BOTH locations must be blocked with a regular FILE as a parent component, for the reason measured
        # in the previous test. With merely-nonexistent paths the gate's `mkdir -p` CREATES both, no warning is
        # ever emitted, and this test FAILS AGAINST CORRECT CODE.
        $g = New-GateEnv; $w = New-Workspace
        $blockT = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $blockH = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Set-Content -LiteralPath $blockT -Value 'x' -NoNewline
        Set-Content -LiteralPath $blockH -Value 'x' -NoNewline
        $g.Tmp  = Join-Path $blockT 'nested'
        $g.Home = Join-Path $blockH 'nested'
        $r1 = Invoke-Prompt $g $w
        $r2 = Invoke-Prompt $g $w
        $r3 = Invoke-Prompt $g $w
        $r1.Stdout | Should -BeNullOrEmpty
        $r2.Stdout | Should -BeNullOrEmpty -Because 'emitting here would fire on every prompt for the whole session'
        $r3.Stdout | Should -BeNullOrEmpty
        $r1.Stderr | Should -Match 'AGY-ANOMALIES'
        $r1.ExitCode | Should -Be 0 -Because 'exit 2 is BLOCKING on some events and must never gate a user prompt'
    }

    It 'does not let a session id escape the marker directory' {
        # The regex captures [^"]*, so a payload can contain path separators. Unsanitized, "../../x" would
        # place a marker outside the marker dir -- a payload deciding where a file lands.
        $g = New-GateEnv; $w = New-Workspace
        $g.Sid = '../../escaped'
        $null = Invoke-Prompt $g $w
        $null = Invoke-Prompt $g $w

        # EXHAUSTIVE SWEEP, not one directory level. An earlier draft checked only the grandparent of $g.Tmp
        # with no -Recurse, so an escape to $TestDrive itself, to three levels up, or into the HOME fallback
        # would have passed unnoticed -- a negative assertion scoped to one guessed destination proves only
        # that the marker did not land THERE.
        $all = @(Get-ChildItem -Path $TestDrive -Recurse -Force -Filter '.clavity-anomaly-*' -ErrorAction SilentlyContinue)
        $all.Count | Should -BeGreaterThan 0 -Because 'zero markers anywhere would satisfy the loop below vacuously, and would also mean the sanitized id silently disabled the gate'
        foreach ($m in $all) {
            $m.DirectoryName | Should -BeExactly (Resolve-Path $g.Tmp).Path -Because 'every marker must sit in the resolved marker directory, wherever the payload tried to send it'
        }
    }

    It 'still gates correctly when the session id needs sanitizing' {
        # Sanitizing must not break the gate: prompt 1 silent, prompt 2 emits, prompt 3 silent.
        $g = New-GateEnv; $w = New-Workspace
        $g.Sid = 'abc/def:ghi'
        (Invoke-Prompt $g $w).Stdout | Should -BeNullOrEmpty
        (Invoke-Prompt $g $w).Stdout | Should -Not -BeNullOrEmpty
        (Invoke-Prompt $g $w).Stdout | Should -BeNullOrEmpty
    }

    It 'holds the byte ban on the UserPromptSubmit message' {
        # Existing suites assert this for the compaction message; the new message is a new surface.
        $g = New-GateEnv; $w = New-Workspace
        $null = Invoke-Prompt $g $w
        $ctx  = ((Invoke-Prompt $g $w).Stdout | ConvertFrom-Json).hookSpecificOutput.additionalContext
        $ctx | Should -Not -BeNullOrEmpty -Because 'an empty string satisfies every ban below vacuously'
        foreach ($banned in @('`', "'", '"', '\')) {
            $ctx | Should -Not -BeLike "*$banned*" -Because 'the jq-absent path hand-builds JSON with no escaping machinery'
        }
    }
}

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

        # The message VERBATIM. Asserted WHOLE via [regex]::Escape, never by bookend fragments: a prior
        # epic measured that bookend assertions left ~95% of a 399-character clause unguarded, and an
        # audit mutant that deleted the operative sentence from all four hooks left a 45-test suite GREEN.
        $script:CaptureMsg = 'AGY-ANOMALIES/1 check BEFORE COMPACTION: did you VERIFY a defect this session that is OUTSIDE your current task and is not yet in .clavity/local-anomalies.md? Capture it now via the open-issues skill - one line: - [type] fact * path:LINE * DATE * task=<what you were doing>. Uncaptured anomalies are lost at compaction. NOT an anomaly: a test you expected to fail, an error in the work you are actively doing, or anything you have not verified by measurement. If nothing qualifies, do nothing - a speculative entry is worse than none, because it lands on a blocking triage gate.'
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
}

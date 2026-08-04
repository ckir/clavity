# Behaviour of the AGY-ANOMALIES dispatch-side reminder (PreToolUse: Agent|Task, model-addressed).
#
# WHY THIS HOOK EXISTS. agy-seam-inject.sh carries the ANOMALY-CAPTURE directive, but it is registered
# PreToolUse matcher "Skill" and keys on .tool_input.skill, and NO hook in either plugin matches the
# Agent/Task tool. Skill invocation is a ONE-SHOT event, so
#   invoke subagent-driven-development -> /compact -> dispatch four subagents
# fires that directive ZERO times across exactly the work it governs.
#
# THE FAIL-OPEN MATRIX IS THE POINT. exit 2 is non-blocking on SessionStart but BLOCKING on PreToolUse
# (documented verbatim at agy-liveness-check.sh:8), so a bug here does not degrade a notification - it
# halts every subagent dispatch in the session.

Describe 'agy-anomaly-dispatch-reminder.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh'

        $bashDir = Split-Path -Parent (Get-GitBashOrThrow)
        $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')

        function New-CleanHome {
            $h = Join-Path ([IO.Path]::GetTempPath()) ("anom-disp-home-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $h '.claude') -Force | Out-Null
            return $h
        }
        function New-Workspace {
            $w = Join-Path ([IO.Path]::GetTempPath()) ("anom-disp-ws-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $w -Force | Out-Null
            return $w
        }
        function Payload { param([string]$Cwd, [string]$Tool = 'Agent')
            @{ cwd = ($Cwd -replace '\\','/'); tool_name = $Tool } | ConvertTo-Json -Compress
        }

        # The directive VERBATIM, asserted WHOLE. Bookend assertions leave the middle unguarded, which is
        # where the operative content lives - measured on a prior epic at ~95% of the clause.
        $script:DispatchMsg = 'AGY-ANOMALIES relay, both halves. (1) In the dispatch you are about to write, ask the subagent to report anything wrong it notices that is NOT its task, under a heading Anomalies noticed at the end of its final message, stated as a checkable fact, with an explicit none if it saw nothing. (2) When it returns, VERIFY each claimed anomaly by measurement and APPEND the verified ones to .clavity/local-anomalies.md BEFORE you write your summary. A verified anomaly that exists only in a chat message is lost the moment you compress that message.'

        function Get-Ctx { param($Result) ($Result.StdOut | ConvertFrom-Json).hookSpecificOutput.additionalContext }
    }

    It 'emits hookSpecificOutput with hookEventName PreToolUse' {
        $w = New-Workspace; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $j = $r.StdOut | ConvertFrom-Json
            $j.hookSpecificOutput.hookEventName | Should -BeExactly 'PreToolUse'
            $j.PSObject.Properties.Name | Should -Not -Contain 'systemMessage'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'delivers the dispatch directive WHOLE' {
        $w = New-Workspace; $h = New-CleanHome
        try {
            Get-Ctx (Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }) |
                Should -Match ([regex]::Escape($script:DispatchMsg))
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'carries BOTH halves - instruct-the-subagent AND verify-on-return' {
        # An earlier draft carried only the return-side relay, which is compliance theater: nothing would
        # have instructed the subagent to produce the heading the driver is then told to look for, so the
        # driver checks, finds nothing, and correctly concludes "no anomalies" - from a question that was
        # never asked. Pinned separately from the whole-string assertion so the failure NAMES which half.
        $w = New-Workspace; $h = New-CleanHome
        try {
            $ctx = Get-Ctx (Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h })
            $ctx | Should -Match ([regex]::Escape('ask the subagent to report anything wrong it notices that is NOT its task'))
            $ctx | Should -Match ([regex]::Escape('VERIFY each claimed anomaly by measurement and APPEND the verified ones'))
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'carries NO FILES allow-list and no implementer-dispatch obligation' {
        # This hook fires on EVERY Agent dispatch, including read-only reviewers and auditors. The FILES
        # allow-list and the diff-the-change-set obligation belong to an IMPLEMENTER dispatch only; the
        # anomaly clause and the FILES clause are separable, and only the latter is excluded here.
        # NEGATIVE assertion - passes on a clean baseline by construction. Its non-vacuity is proven by a
        # landed mutation, recorded in the plan for this task.
        $w = New-Workspace; $h = New-CleanHome
        try {
            $ctx = Get-Ctx (Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h })
            $ctx | Should -Not -BeNullOrEmpty -Because 'a silent hook would satisfy both negatives below vacuously'
            $ctx | Should -Not -Match 'FILES'
            $ctx | Should -Not -Match 'git status --short'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 0 on every failure mode' -ForEach @(
        @{ Case = 'malformed payload';  Payload = 'not json at all {{{';        NoJq = $false }
        @{ Case = 'empty payload';      Payload = '';                            NoJq = $false }
        @{ Case = 'absent cwd key';     Payload = '{"tool_name":"Agent"}';       NoJq = $false }
        @{ Case = 'unreadable cwd';     Payload = '{"cwd":"/no/such/dir/at/all"}'; NoJq = $false }
        @{ Case = 'non-Agent payload';  Payload = '{"cwd":".","tool_name":"Bash"}'; NoJq = $false }
        @{ Case = 'absent jq';          Payload = '{"cwd":"."}';                 NoJq = $true  }
    ) {
        # exit 2 is BLOCKING on PreToolUse. There must be NO path that exits non-zero, because a bug here
        # does not degrade a notification - it halts every subagent dispatch in the session.
        $h = New-CleanHome
        try {
            $env = @{ HOME = $h }
            if ($NoJq) { $env['PATH'] = $script:NoJqPath }
            $r = Invoke-BashHook -HookPath $script:Hook -Payload $Payload -Env $env
            $r.ExitCode | Should -Be 0 -Because "the $Case path must fail open"
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'has no non-zero exit anywhere in its source' {
        # A structural companion to the matrix above: the matrix can only cover the paths it thought of.
        # Both shipping PreToolUse hooks have zero non-zero exit paths; this asserts the same property
        # directly rather than by sampling.
        #
        # THE MATCH IS DELIBERATELY NOT ANCHORED TO LINE START. An earlier draft used
        # '(?m)^\s*exit\s+[1-9]', which requires exit to be the first token on its line - so it saw a
        # bare `exit 2` and MISSED `if [ ... ]; then exit 2; fi`, which is how a blocking exit would
        # actually arrive in a guard clause, and is the single most likely shape of this defect. Measured:
        # that pattern returns 0 matches against an appended inline guard. Since exit 2 is BLOCKING on
        # PreToolUse, an assertion with a hole exactly where the risk lives is worse than none.
        # Whole-line comments are dropped first so the file's own prose about "exit 2" cannot red it; the
        # hook body carries no inline trailing comments, and none may be added without revisiting this.
        #
        # AND THE SOURCE MUST EXIST. A scan over a file that is not there matches nothing and passes -
        # MEASURED: with the hook absent, this was one of only two tests in the suite that went green.
        # A structural assertion satisfied by the absence of the structure is worse than no assertion,
        # because it reads as coverage.
        Test-Path -LiteralPath $script:Hook | Should -BeTrue -Because 'a scan over a missing file matches nothing and passes'
        $code = @(Get-Content -LiteralPath $script:Hook | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        $code | Should -Not -BeNullOrEmpty -Because 'an empty body would satisfy the match count below vacuously'
        $code | Should -Match '\bexit\s+0' -Because 'the hook must actually contain the fail-open exits this test claims to be checking'
        [regex]::Matches($code, '\bexit\s+[1-9]').Count | Should -Be 0
    }

    It 'still DELIVERS the JSON envelope when jq is absent' {
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{"cwd":"."}' -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $r.ExitCode | Should -Be 0
            $j = $r.StdOut | ConvertFrom-Json   # throws if the fallback emitted plain text
            $j.hookSpecificOutput.hookEventName | Should -BeExactly 'PreToolUse'
            $j.hookSpecificOutput.additionalContext | Should -Match ([regex]::Escape($script:DispatchMsg))
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'delivers an IDENTICAL directive with and without jq' {
        # The anti-drift guard. THE NON-EMPTY ASSERTIONS ARE NOT DECORATION: equality alone is satisfied
        # when BOTH paths emit nothing, and measured on this change's sibling suite, that made it the one
        # test of ten that passed green against a hook that did not exist yet.
        $w = New-Workspace; $h = New-CleanHome
        try {
            $withJq = Get-Ctx (Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h })
            $noJq   = Get-Ctx (Invoke-BashHook -HookPath $script:Hook -Payload '{"cwd":"."}' -Env @{ PATH = $script:NoJqPath; HOME = $h })
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
        $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{"cwd":"."}' -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'emits a directive free of backtick, apostrophe, double quote and backslash' {
        $w = New-Workspace; $h = New-CleanHome
        try {
            $ctx = Get-Ctx (Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h })
            $ctx | Should -Not -BeNullOrEmpty -Because 'an empty directive would pass every byte scan below'
            $bytes = [Text.Encoding]::UTF8.GetBytes($ctx)
            @($bytes | Where-Object { $_ -eq 0x60 }).Count | Should -Be 0 -Because 'backtick'
            @($bytes | Where-Object { $_ -eq 0x27 }).Count | Should -Be 0 -Because 'apostrophe'
            @($bytes | Where-Object { $_ -eq 0x22 }).Count | Should -Be 0 -Because 'double quote'
            @($bytes | Where-Object { $_ -eq 0x5C }).Count | Should -Be 0 -Because 'backslash'
            @($bytes | Where-Object { $_ -gt 127 }).Count  | Should -Be 0 -Because 'non-ASCII'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'leaves agy-seam-inject.sh untouched' {
        # Acceptance criterion 10. Gap (b) is closed by an ISOLATED hook; modifying the seam injector was
        # explicitly rejected, because its case keys on $skill, which an Agent payload does not carry.
        $seam = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-seam-inject.sh'
        (Get-Content -Raw -LiteralPath $seam) | Should -Match 'tool_input\.skill'
    }
}

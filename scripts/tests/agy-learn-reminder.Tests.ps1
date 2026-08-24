Describe 'agy-learn-reminder.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot 'agy-autotrain/hooks/agy-learn-reminder.sh'

        # Every test runs against an ISOLATED home. A real ~/.claude/.no-agy on the dev box would
        # otherwise silence the hook and hand us a false green on every single assertion here.
        # Absolute paths only - MSYS mangles a relative HOME.
        function New-HomePair {
            # Returns two SEPARATE roots: one to point USERPROFILE at, one to point HOME at. Keeping them
            # distinct is the whole point - a shared root cannot distinguish which variable the hook read.
            $base = Join-Path ([IO.Path]::GetTempPath()) ("learnrem-" + [Guid]::NewGuid().ToString('N'))
            $up   = Join-Path $base 'profile'
            $hm   = Join-Path $base 'unixhome'
            New-Item -ItemType Directory -Path $up -Force | Out-Null
            New-Item -ItemType Directory -Path $hm -Force | Out-Null
            [pscustomobject]@{
                Base = $base
                Env  = @{ USERPROFILE = ($up -replace '\\','/'); HOME = ($hm -replace '\\','/') }
                UserProfile = $up
                Home = $hm
            }
        }
        function Plant-NoAgy([string]$Root) {
            New-Item -ItemType Directory -Path (Join-Path $Root '.claude') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $Root '.claude/.no-agy') -Value '' -Encoding ascii
        }
        $script:Payload = @{ cwd = 'C:/nowhere-that-exists' } | ConvertTo-Json -Compress
    }

    It 'speaks on SessionStart when no .no-agy marker exists anywhere' {
        $e = New-HomePair
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload $script:Payload -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -Match 'agy-autotrain is active' -Because 'this is the baseline the silence assertions below are measured against'
        } finally { Remove-Item -LiteralPath $e.Base -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a .no-agy in the HOME root' {
        $e = New-HomePair
        try {
            Plant-NoAgy $e.Home
            $r = Invoke-BashHook -HookPath $script:Hook -Payload $script:Payload -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item -LiteralPath $e.Base -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a .no-agy in the USERPROFILE root when HOME points somewhere else' {
        # THE CONTROL for the kill-switch resolution split. Its two sibling hooks in this plugin resolve
        # home as ${USERPROFILE:-$HOME} and are registered on the SAME SessionStart event, but this hook
        # read the marker from BARE $HOME only. A parent that exports USERPROFILE without HOME therefore
        # silenced the siblings and left THIS hook talking - the operator asks for silence and still gets
        # nudged. MEASURED: `env -u HOME bash --noprofile --norc -c` leaves HOME empty and does NOT
        # backfill it from USERPROFILE, so this is reachable rather than theoretical.
        $e = New-HomePair
        try {
            Plant-NoAgy $e.UserProfile        # marker under USERPROFILE only
            (Test-Path (Join-Path $e.Home '.claude/.no-agy')) | Should -BeFalse -Because 'the HOME root must NOT carry a marker, or this test cannot distinguish which variable the hook read'
            $r = Invoke-BashHook -HookPath $script:Hook -Payload $script:Payload -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -BeNullOrEmpty -Because 'a .no-agy under USERPROFILE must silence this hook exactly as it silences agy-curate-nudge.sh on the same event'
        } finally { Remove-Item -LiteralPath $e.Base -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a .no-agy in the payload cwd' {
        $e = New-HomePair
        try {
            $work = Join-Path $e.Base 'work'
            New-Item -ItemType Directory -Path $work -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $work '.no-agy') -Value '' -Encoding ascii
            $payload = @{ cwd = ($work -replace '\\','/') } | ConvertTo-Json -Compress
            $r = Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item -LiteralPath $e.Base -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'emits systemMessage for PreCompact and hookSpecificOutput for SessionStart' {
        # The two events take DIFFERENT payload shapes and Claude Code REJECTS the wrong one outright,
        # so the reminder never reaches the model. Pinned because the fix above edits this same file.
        $e = New-HomePair
        try {
            $s = Invoke-BashHook -HookPath $script:Hook -Payload $script:Payload -Env $e.Env
            $s.StdOut | Should -Match 'hookSpecificOutput'
            $s.StdOut | Should -Match '"hookEventName":"SessionStart"'

            $p = Invoke-BashHook -HookPath $script:Hook -Payload $script:Payload -Env $e.Env -Arguments 'PreCompact'
            $p.StdOut | Should -Match 'systemMessage'
            $p.StdOut | Should -Not -Match 'hookSpecificOutput' -Because 'PreCompact is not among the events that accept hookSpecificOutput'
        } finally { Remove-Item -LiteralPath $e.Base -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

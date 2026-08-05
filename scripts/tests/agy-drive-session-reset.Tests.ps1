# Pester 5. Covers agy-drive-session-reset.sh, the ONLY hook in the agy set that mutates disk rather
# than emitting a message: it clears the once-per-session driver-guidance flag. A .no-agy bypass here
# DELETES a file belonging to a user who opted out - and because the session key defaults to 'default'
# (hook :17), the destroyed flag can belong to a DIFFERENT, concurrent, opted-in session.
#
# THE PAYLOAD SHAPE IS THE POINT. Every sibling suite forward-slashes cwd (`-replace '\\','/'`), which
# is exactly why the Windows repo-root walk bug survived this long: a POSIX-shaped path cannot exercise
# it. New-RawPayload below feeds the shape the real hook payload actually has - backslashes, JSON-escaped.
# The FLAGS directory is still forward-slashed, deliberately: it is not the property under test, and
# leaving it backslashed would confound a walk failure with an unrelated path-handling failure.
Describe 'agy-drive-session-reset.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks/agy-drive-session-reset.sh'

        function New-RawPayload {
            param([string]$Cwd, [string]$Source = 'startup')
            # '\\' as a regex matches ONE backslash; '\\' as a .NET replacement is TWO literal characters
            # (.NET escapes with $, not \). So this DOUBLES them, which is what a JSON string needs.
            # Measured: the result round-trips through ConvertFrom-Json. Do not "fix" it to '\\\\'.
            $escaped = $Cwd -replace '\\', '\\'
            '{"cwd":"' + $escaped + '","source":"' + $Source + '","hook_event_name":"SessionStart"}'
        }

        function New-FlagDir {
            $d = Join-Path ([IO.Path]::GetTempPath()) ("drv-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            return $d
        }

        function New-CleanHome {
            # Hermeticity: without an overridden HOME every test below reads the DEVELOPER's real
            # ~/.claude/.no-agy. If that file ever exists, every assertion in this suite passes
            # vacuously - the hook would exit at :10 having tested nothing.
            $h = Join-Path ([IO.Path]::GetTempPath()) ("drv-home-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $h '.claude') -Force | Out-Null
            return $h
        }

        function Invoke-Reset {
            param([string]$Cwd, [string]$Source = 'startup', [string]$Flags, [string]$HomeDir)
            Invoke-BashHook -HookPath $script:Hook -Payload (New-RawPayload -Cwd $Cwd -Source $Source) `
                -Env @{ CLAVITY_GOLDEN_HEADER = ($Flags -replace '\\', '/'); HOME = $HomeDir }
        }
    }

    It 'CLEARS the session flag on source=startup (positive control)' {
        # Without this the four RETAINS tests below are unfalsifiable: a hook that never deleted
        # anything at all would satisfy every one of them.
        $repo = New-TempRepo; $flags = New-FlagDir; $hm = New-CleanHome
        try {
            $flag = Join-Path $flags '.active-drive-session-default'
            New-Item -ItemType File -Path $flag -Force | Out-Null

            Invoke-Reset -Cwd $repo -Flags $flags -HomeDir $hm | Out-Null

            Test-Path $flag | Should -BeFalse -Because 'source=startup must clear the flag so the next session re-delivers'
        } finally { Remove-Item $repo,$flags,$hm -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'RETAINS the session flag on source=resume' {
        $repo = New-TempRepo; $flags = New-FlagDir; $hm = New-CleanHome
        try {
            $flag = Join-Path $flags '.active-drive-session-default'
            New-Item -ItemType File -Path $flag -Force | Out-Null

            Invoke-Reset -Cwd $repo -Source 'resume' -Flags $flags -HomeDir $hm | Out-Null

            Test-Path $flag | Should -BeTrue -Because 'only a genuine fresh start clears it'
        } finally { Remove-Item $repo,$flags,$hm -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'RETAINS the flag when .no-agy is at the payload cwd' {
        $repo = New-TempRepo; $flags = New-FlagDir; $hm = New-CleanHome
        try {
            $flag = Join-Path $flags '.active-drive-session-default'
            New-Item -ItemType File -Path $flag -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $repo '.no-agy') -Force | Out-Null

            Invoke-Reset -Cwd $repo -Flags $flags -HomeDir $hm | Out-Null

            Test-Path $flag | Should -BeTrue -Because '.no-agy at the session cwd must suppress the deletion'
        } finally { Remove-Item $repo,$flags,$hm -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'RETAINS the flag under a GLOBAL .no-agy' {
        # The global opt-out moves position when the repo-root walk lands. Unpinned, a fix could drop it
        # and nothing would notice.
        $repo = New-TempRepo; $flags = New-FlagDir; $hm = New-CleanHome
        try {
            $flag = Join-Path $flags '.active-drive-session-default'
            New-Item -ItemType File -Path $flag -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $hm '.claude/.no-agy') -Force | Out-Null

            Invoke-Reset -Cwd $repo -Flags $flags -HomeDir $hm | Out-Null

            Test-Path $flag | Should -BeTrue -Because 'the global kill-switch must suppress the deletion too'
        } finally { Remove-Item $repo,$flags,$hm -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'RETAINS the flag when .no-agy is at the REPO ROOT and cwd is a SUBDIRECTORY' {
        $repo = New-TempRepo; $flags = New-FlagDir; $hm = New-CleanHome
        try {
            $sub = Join-Path $repo 'src'
            New-Item -ItemType Directory -Path $sub -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $repo '.no-agy') -Force | Out-Null

            $flag = Join-Path $flags '.active-drive-session-default'
            New-Item -ItemType File -Path $flag -Force | Out-Null

            Invoke-Reset -Cwd $sub -Flags $flags -HomeDir $hm | Out-Null

            Test-Path $flag | Should -BeTrue -Because 'an opt-out at the repo root must hold from a subdirectory'
        } finally { Remove-Item $repo,$flags,$hm -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does not sweep a FRESH flag belonging to another session' {
        $repo = New-TempRepo; $flags = New-FlagDir; $hm = New-CleanHome
        try {
            $other = Join-Path $flags '.active-drive-session-othersession'
            New-Item -ItemType File -Path $other -Force | Out-Null

            Invoke-Reset -Cwd $repo -Flags $flags -HomeDir $hm | Out-Null

            Test-Path $other | Should -BeTrue -Because 'the -mtime +7 sweep must leave a live concurrent flag alone'
        } finally { Remove-Item $repo,$flags,$hm -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

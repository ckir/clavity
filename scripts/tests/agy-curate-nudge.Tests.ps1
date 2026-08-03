Describe 'agy-curate-nudge.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot 'agy-autotrain/hooks/agy-curate-nudge.sh'

        # Build a throwaway CLAUDE_PLUGIN_ROOT holding knowledge/agy-observations.md, plus an isolated
        # HOME/USERPROFILE so a REAL ~/.clavity/.agy-curate-snooze on the dev box cannot silence the hook
        # and hand us a false green. Absolute paths only - MSYS mangles relative HOME.
        function New-NudgeEnv { param([string]$Inbox)
            $root = Join-Path ([IO.Path]::GetTempPath()) ("curate-nudge-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $root 'knowledge') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'home') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'knowledge/agy-observations.md') -Value $Inbox -NoNewline
            [pscustomobject]@{
                Root = $root
                Env  = @{
                    CLAUDE_PLUGIN_ROOT = ($root -replace '\\','/')
                    USERPROFILE        = ((Join-Path $root 'home') -replace '\\','/')
                    HOME               = ((Join-Path $root 'home') -replace '\\','/')
                }
            }
        }

        $script:Today = (Get-Date).ToString('yyyy-MM-dd')
    }

    It 'is SILENT when the only old date lives in a drain-log COMMENT, not on a pending bullet' {
        # The defect this pins: the age scan swept the whole region and picked 2020-01-01 out of an HTML
        # drain-log comment, so the nudge claimed an "oldest pending entry" that no bullet carries. Drain
        # logs are append-only, so that latched the nudge ON permanently - draining could never clear it.
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) a recent capture  ``[corpus]`` - $script:Today - agy 1.1.10

<!-- Drain log 2020-01-01 (agy 1.0.10): historical drain notes live here forever. -->
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -BeNullOrEmpty -Because 'one recent bullet is under the count threshold and nothing pending is old'
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'STILL nudges when a genuinely old date is on a PENDING BULLET' {
        # The control. Without this, "delete the age check" would pass the test above.
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) a stale capture  ``[corpus]`` - 2020-01-01 - agy 1.0.10
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -Match 'oldest pending entry \(2020-01-01\)'
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'counts ONLY pending bullets, ignoring dated lines inside drain-log comments' {
        # The count path was already correct (anchored to /^- \[/); pin it so a fix to the date scan
        # cannot regress it, and so the two scans stay symmetric.
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) one  ``[corpus]`` - $script:Today - agy 1.1.10
- [heuristic] (driver/probabilistic) two  ``[corpus]`` - $script:Today - agy 1.1.10

<!-- Drain log 2020-01-01: 79 entries in, 71 routed. -->
<!-- Drain log 2020-02-02: 8 entries in, 8 routed. -->
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env ($e.Env + @{ AGY_CURATE_NUDGE_THRESHOLD = '2' })
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -Match 'has 2 pending entries' -Because 'the two comment lines must not be counted as entries'
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a .no-agy kill-switch even when the inbox is genuinely stale' {
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) a stale capture  ``[corpus]`` - 2020-01-01 - agy 1.0.10
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            $cwd = Join-Path $e.Root 'work'
            New-Item -ItemType Directory -Path $cwd -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $cwd '.no-agy') -Value '' -NoNewline
            $payload = @{ cwd = ($cwd -replace '\\','/') } | ConvertTo-Json -Compress
            $r = Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

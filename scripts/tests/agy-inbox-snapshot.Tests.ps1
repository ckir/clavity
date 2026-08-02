Describe 'agy-inbox-snapshot' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot 'agy-autotrain/hooks/agy-inbox-snapshot.sh'

        # A fake plugin root: the hook resolves the inbox as $CLAUDE_PLUGIN_ROOT/knowledge/agy-observations.md
        function New-PluginRoot {
            param([string]$Body)
            $r = Join-Path ([IO.Path]::GetTempPath()) ("ibx-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $r 'knowledge') -Force | Out-Null
            if ($null -ne $Body) {
                Set-Content -LiteralPath (Join-Path $r 'knowledge/agy-observations.md') -Value $Body -Encoding ascii
            }
            return $r
        }
        function Payload { param([string]$Skill)
            @{ tool_name = 'Skill'; tool_input = @{ skill = $Skill }; cwd = 'C:/nowhere'; session_id = 'ibxtest' } | ConvertTo-Json -Compress
        }
        function BakCount { param([string]$Root)
            @(Get-ChildItem -LiteralPath (Join-Path $Root 'knowledge') -Filter 'agy-observations.md.*.bak' -ErrorAction SilentlyContinue).Count
        }
        $script:Good = "# agy observations inbox (raw, project-agnostic)`n`n## Pending`n`n- [assumption] (peer/probabilistic) a rule`n"
    }

    It 'snapshots the inbox when agy-curate is invoked' {
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 1
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT snapshot for an unrelated skill' {
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'superpowers:brainstorming') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'snapshots an inbox whose entries are ALL anti-pattern' {
        # THE PANEL FINDING. `[a-z]+` does not match the hyphen in `anti-pattern`, which was 42 of the 79
        # entries in the last real corpus - the most common class. With the wrong class the hook reads a
        # perfectly valid inbox as malformed and silently skips the snapshot.
        $body = "# agy observations inbox (raw, project-agnostic)`n`n## Pending`n`n- [anti-pattern] (driver/probabilistic) a rule`n"
        $r = New-PluginRoot $body
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 1
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses to rotate when the inbox is empty' {
        $r = New-PluginRoot ''
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses to rotate when ## Pending is missing' {
        $r = New-PluginRoot "# agy observations inbox (raw, project-agnostic)`n`n- [assumption] (peer/probabilistic) x`n"
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses to rotate when there are no bullets' {
        $r = New-PluginRoot "# agy observations inbox (raw, project-agnostic)`n`n## Pending`n"
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT consume a slot when content is unchanged' {
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            Start-Sleep -Seconds 1   # distinct timestamp if it DID rotate
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 1
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'prunes to at most 5 slots' {
        $r = New-PluginRoot $script:Good
        try {
            foreach ($i in 1..7) {
                Set-Content -LiteralPath (Join-Path $r 'knowledge/agy-observations.md') `
                    -Value ($script:Good + "- [heuristic] (driver/probabilistic) entry $i`n") -Encoding ascii
                Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
                Start-Sleep -Seconds 1
            }
            BakCount $r | Should -Be 5
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 0 when the inbox does not exist at all' {
        $r = New-PluginRoot $null
        try {
            (Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r }).ExitCode | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'ships as pure ASCII' {
        ($([IO.File]::ReadAllBytes($script:Hook)) | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}

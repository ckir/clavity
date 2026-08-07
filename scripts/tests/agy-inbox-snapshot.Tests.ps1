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
        # The UserPromptSubmit payload shape: a .prompt string, no .tool_input.
        function PromptPayload { param([string]$Text) '{"prompt":"' + ($Text -replace '"','\"') + '"}' }
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

    # AGY-TEST-AUDIT finding. 'prunes to at most 5 slots' above asserts ARITY only, and arity cannot
    # detect a reversed sort: with `ls -1tr` the ring keeps the five OLDEST and deletes the newest -
    # including the snapshot taken moments earlier by that same invocation - while the surviving count
    # is still exactly 5. Measured before this test existed: that mutation left the whole suite at
    # 21/0 green. The C# sibling already pinned this half of the guarantee
    # (Commit_prunes_the_OLDEST_slots_and_keeps_the_newest); the bash half was missed.
    # Assert WHICH slots survive, not how many.
    It 'prunes the OLDEST snapshots and preserves the newest' {
        $r = New-PluginRoot $script:Good
        try {
            foreach ($i in 1..7) {
                Set-Content -LiteralPath (Join-Path $r 'knowledge/agy-observations.md') `
                    -Value ($script:Good + "- [heuristic] (driver/probabilistic) entry $i`n") -Encoding ascii
                Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
                Start-Sleep -Seconds 1
            }
            $bodies = @(
                Get-ChildItem -LiteralPath (Join-Path $r 'knowledge') -Filter 'agy-observations.md.*.bak' |
                    ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }
            )
            $bodies.Count | Should -Be 5
            @($bodies | Where-Object { $_ -match 'entry 7' }).Count |
                Should -Be 1 -Because 'the NEWEST snapshot must survive the prune'
            @($bodies | Where-Object { $_ -match 'entry 1' }).Count |
                Should -Be 0 -Because 'the OLDEST snapshot must be the one evicted'
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

    # --- The jq-ABSENT fallback branch. -------------------------------------------------------------
    # jq resolves here to the operator's portable toolchain, so every test above exercises ONLY the jq
    # branch. On a stock end-user box jq is absent and the field-bounded-grep fallback is the path that
    # actually runs - i.e. the branch most installs depend on was the one branch with no coverage.
    # PATH=/usr/bin removes jq while keeping grep/cp/date/ls/cmp/head/tail/rm, all of which live there.

    It 'snapshots via the fallback when jq is absent' {
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') `
                -Env @{ CLAUDE_PLUGIN_ROOT = $r; PATH = '/usr/bin' } | Out-Null
            BakCount $r | Should -Be 1
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT snapshot via the fallback for an unrelated skill' {
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'superpowers:brainstorming') `
                -Env @{ CLAUDE_PLUGIN_ROOT = $r; PATH = '/usr/bin' } | Out-Null
            BakCount $r | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # --- Field-boundedness. -------------------------------------------------------------------------
    # The hook's own comment promises "Never a bare substring: another skill could merely MENTION
    # agy-curate in its args" - but nothing held it to that. A bare `grep -q agy-curate` passes every
    # other test in this file while snapshotting on any prompt that happens to name the skill.

    It 'does NOT snapshot when another skill merely MENTIONS agy-curate in its args' -ForEach @(
        @{ Branch = 'jq';       PathEnv = $null }
        @{ Branch = 'fallback'; PathEnv = '/usr/bin' }
    ) {
        $payload = @{
            tool_name  = 'Skill'
            tool_input = @{ skill = 'superpowers:brainstorming'; args = 'first drain the inbox with agy-curate' }
            cwd = 'C:/nowhere'; session_id = 'ibxtest'
        } | ConvertTo-Json -Compress
        $r = New-PluginRoot $script:Good
        try {
            $envs = @{ CLAUDE_PLUGIN_ROOT = $r }
            if ($PathEnv) { $envs['PATH'] = $PathEnv }
            Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env $envs | Out-Null
            BakCount $r | Should -Be 0 -Because "the $Branch branch must key on the skill FIELD, not a substring"
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # --- The documented knobs. ----------------------------------------------------------------------

    It 'honours the AGY_INBOX_SNAPSHOT_KEEP retention override' {
        $r = New-PluginRoot $script:Good
        try {
            foreach ($i in 1..4) {
                Set-Content -LiteralPath (Join-Path $r 'knowledge/agy-observations.md') `
                    -Value ($script:Good + "- [heuristic] (driver/probabilistic) entry $i`n") -Encoding ascii
                Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') `
                    -Env @{ CLAUDE_PLUGIN_ROOT = $r; AGY_INBOX_SNAPSHOT_KEEP = '2' } | Out-Null
                Start-Sleep -Seconds 1
            }
            BakCount $r | Should -Be 2
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # AGY-CAPSTONE round 2 hardening. Invariant 2 is supposed to mean "## Pending holds something worth
    # saving". Unscoped, a bullet ANYWHERE in the file satisfied it - so a drained inbox whose header
    # prose or a hand-edit carried a bullet would snapshot nothing of value. No such line exists in the
    # live corpus (measured: all 8 bullets sit below ## Pending at line 9), so this pins intent rather
    # than fixing a live defect.
    It 'does NOT count a bullet that sits ABOVE the Pending section' {
        $body = "# agy observations inbox (raw, project-agnostic)`n`n- [assumption] (peer/probabilistic) stray`n`n## Pending`n"
        $r = New-PluginRoot $body
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') `
                -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # AGY-CAPSTONE round 1 finding. KEEP feeds `tail -n +$((KEEP + 1))`; bash evaluates a non-numeric
    # name as 0, so "abc", "-1" and a literal "0" all collapse to `tail -n +1`, which lists EVERY slot
    # and deletes them all - including the snapshot taken moments earlier. Measured before the fix:
    # 3 seeded + 1 fresh -> 0 remaining, silently, exit 0. A malformed knob must degrade to the
    # default, never to total destruction of the history it is meant to size.
    It 'ignores a malformed AGY_INBOX_SNAPSHOT_KEEP instead of destroying the ring' -ForEach @(
        @{ Keep = '0' }, @{ Keep = 'abc' }, @{ Keep = '-1' }, @{ Keep = '3x' }
    ) {
        $r = New-PluginRoot $script:Good
        try {
            foreach ($i in 1..3) {
                Set-Content -LiteralPath (Join-Path $r "knowledge/agy-observations.md.2026010$i-000000.bak") `
                    -Value "old $i" -Encoding ascii
            }
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') `
                -Env @{ CLAUDE_PLUGIN_ROOT = $r; AGY_INBOX_SNAPSHOT_KEEP = $Keep } | Out-Null
            # 3 seeded + 1 newly written, all retained under the fallback of 5.
            BakCount $r | Should -Be 4 -Because "KEEP='$Keep' is malformed and must fall back to 5, not wipe the ring"
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'honours the .no-agy opt-out marker' {
        $r = New-PluginRoot $script:Good
        $h = Join-Path ([IO.Path]::GetTempPath()) ("ibxhome-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $h '.claude') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $h '.claude/.no-agy') -Value '' -Encoding ascii
        try {
            # HOME must be ABSOLUTE - MSYS mangles a relative value.
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') `
                -Env @{ CLAUDE_PLUGIN_ROOT = $r; HOME = ($h -replace '\\','/') } | Out-Null
            BakCount $r | Should -Be 0
        } finally {
            Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'snapshots when agy-curate is invoked as a SLASH COMMAND' {
        # The reported defect, verbatim: measured 2026-08-03, no new .bak appeared on this path.
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (PromptPayload '/agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 1
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT snapshot on an ordinary prompt that merely mentions agy-curate' {
        # CONTROL. A bare substring match fires on this. The existing jq-absent branch already records why
        # that is wrong: another skill could merely MENTION agy-curate in its args.
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (PromptPayload 'why did agy-curate skip the snapshot last time?') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'snapshots on a slash command WITH trailing arguments' {
        # /agy-autotrain:agy-curate --dry-run is a real invocation and must not be treated as prose.
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (PromptPayload '/agy-autotrain:agy-curate --dry-run') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 1
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'still snapshots on the Skill-tool path' {
        # Regression guard: the path that already worked must keep working.
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 1
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'burns only ONE slot when both paths fire in the same drain' {
        # The hook now has two ways to fire in one drain (the user types the slash command AND the skill body
        # later triggers the Skill tool). The dedup invariant is what prevents that burning two slots.
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (PromptPayload '/agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 1 -Because 'the dedup invariant exists for exactly this'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

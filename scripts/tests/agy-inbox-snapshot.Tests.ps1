Describe 'agy-inbox-snapshot' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot 'agy-autotrain/hooks/agy-inbox-snapshot.sh'

        # ROADMAP 14g: the hook resolves the inbox as <USERPROFILE|HOME>/.clavity/agy-observations.md.
        # $r stays the sandbox root; the inbox now lives at $r/home/.clavity/ and CLAUDE_PLUGIN_ROOT still
        # points at $r so that knowledge/agy-observations.md under it acts as a DECOY. That decoy is a
        # mutation control, not scenery: it is always present, so if the hook ever reverts to the plugin
        # tree the snapshots land in the wrong directory and every BakCount assertion reds.
        function New-PluginRoot {
            param([string]$Body)
            $r = Join-Path ([IO.Path]::GetTempPath()) ("ibx-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $r 'knowledge') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $r 'home/.clavity') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $r 'knowledge/agy-observations.md') -Value '# DECOY in the plugin tree - never read this' -Encoding ascii
            if ($null -ne $Body) {
                Set-Content -LiteralPath (Join-Path $r 'home/.clavity/agy-observations.md') -Value $Body -Encoding ascii
            }
            return $r
        }
        # Every hook call needs HOME/USERPROFILE pointed into the sandbox, or the hook reads the DEV BOX's
        # real ~/.clavity inbox - a false green that also mutates real state.
        function HookEnv { param([string]$Root, [hashtable]$Extra)
            $e = @{ CLAUDE_PLUGIN_ROOT = $Root
                    USERPROFILE = ((Join-Path $Root 'home') -replace '\\','/')
                    HOME        = ((Join-Path $Root 'home') -replace '\\','/') }
            if ($Extra) { foreach ($k in $Extra.Keys) { $e[$k] = $Extra[$k] } }
            return $e
        }
        function Payload { param([string]$Skill)
            @{ tool_name = 'Skill'; tool_input = @{ skill = $Skill }; cwd = 'C:/nowhere'; session_id = 'ibxtest' } | ConvertTo-Json -Compress
        }
        function BakCount { param([string]$Root)
            @(Get-ChildItem -LiteralPath (Join-Path $Root 'home/.clavity') -Filter 'agy-observations.md.*.bak' -ErrorAction SilentlyContinue).Count
        }
        # The UserPromptSubmit payload shape: a .prompt string, no .tool_input.
        function PromptPayload { param([string]$Text) '{"prompt":"' + ($Text -replace '"','\"') + '"}' }
        $script:Good = "# agy observations inbox (raw, project-agnostic)`n`n## Pending`n`n- [assumption] (peer/probabilistic) a rule`n"
    }

    It 'snapshots the inbox when agy-curate is invoked' {
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env (HookEnv $r) | Out-Null
            BakCount $r | Should -Be 1
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT snapshot for an unrelated skill' {
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'superpowers:brainstorming') -Env (HookEnv $r) | Out-Null
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
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env (HookEnv $r) | Out-Null
            BakCount $r | Should -Be 1
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses to rotate when the inbox is empty' {
        $r = New-PluginRoot ''
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env (HookEnv $r) | Out-Null
            BakCount $r | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses to rotate when ## Pending is missing' {
        $r = New-PluginRoot "# agy observations inbox (raw, project-agnostic)`n`n- [assumption] (peer/probabilistic) x`n"
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env (HookEnv $r) | Out-Null
            BakCount $r | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses to rotate when there are no bullets' {
        $r = New-PluginRoot "# agy observations inbox (raw, project-agnostic)`n`n## Pending`n"
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env (HookEnv $r) | Out-Null
            BakCount $r | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT consume a slot when content is unchanged' {
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env (HookEnv $r) | Out-Null
            Start-Sleep -Seconds 1   # distinct timestamp if it DID rotate
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env (HookEnv $r) | Out-Null
            BakCount $r | Should -Be 1
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'prunes to at most 5 slots' {
        $r = New-PluginRoot $script:Good
        try {
            foreach ($i in 1..7) {
                Set-Content -LiteralPath (Join-Path $r 'home/.clavity/agy-observations.md') `
                    -Value ($script:Good + "- [heuristic] (driver/probabilistic) entry $i`n") -Encoding ascii
                Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env (HookEnv $r) | Out-Null
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
                Set-Content -LiteralPath (Join-Path $r 'home/.clavity/agy-observations.md') `
                    -Value ($script:Good + "- [heuristic] (driver/probabilistic) entry $i`n") -Encoding ascii
                Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env (HookEnv $r) | Out-Null
                Start-Sleep -Seconds 1
            }
            $bodies = @(
                Get-ChildItem -LiteralPath (Join-Path $r 'home/.clavity') -Filter 'agy-observations.md.*.bak' |
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
            (Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env (HookEnv $r)).ExitCode | Should -Be 0
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
                -Env (HookEnv $r @{ PATH = '/usr/bin' }) | Out-Null
            BakCount $r | Should -Be 1
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT snapshot via the fallback for an unrelated skill' {
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'superpowers:brainstorming') `
                -Env (HookEnv $r @{ PATH = '/usr/bin' }) | Out-Null
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
            $envs = (HookEnv $r)
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
                Set-Content -LiteralPath (Join-Path $r 'home/.clavity/agy-observations.md') `
                    -Value ($script:Good + "- [heuristic] (driver/probabilistic) entry $i`n") -Encoding ascii
                Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') `
                    -Env (HookEnv $r @{ AGY_INBOX_SNAPSHOT_KEEP = '2' }) | Out-Null
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
                -Env (HookEnv $r) | Out-Null
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
                Set-Content -LiteralPath (Join-Path $r "home/.clavity/agy-observations.md.2026010$i-000000.bak") `
                    -Value "old $i" -Encoding ascii
            }
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') `
                -Env (HookEnv $r @{ AGY_INBOX_SNAPSHOT_KEEP = $Keep }) | Out-Null
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
                -Env (HookEnv $r @{ HOME = ($h -replace '\\','/') }) | Out-Null
            BakCount $r | Should -Be 0
        } finally {
            Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'honours .no-agy under USERPROFILE when HOME points somewhere else' {
        # CONTROL for the kill-switch resolution split. The inbox resolves via ${USERPROFILE:-$HOME}
        # (agy-inbox-snapshot.sh:19-20) but the opt-out marker was read from BARE $HOME (:25). A parent
        # that exports USERPROFILE without HOME therefore silently DISARMS the kill switch. MEASURED:
        # `env -u HOME bash --noprofile --norc -c` leaves HOME empty and does NOT backfill it from
        # USERPROFILE, so this is reachable and not theoretical.
        $h = Join-Path ([IO.Path]::GetTempPath()) ("ibxhome-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $h -Force | Out-Null
        $r1 = New-PluginRoot $script:Good
        $r2 = New-PluginRoot $script:Good
        try {
            # PRECONDITION. With HOME pointed away and NO marker anywhere, this setup DOES snapshot.
            # Without asserting it, the 0 below could mean "the setup never snapshots" rather than
            # "the kill switch fired" - a vacuous pass.
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') `
                -Env (HookEnv $r1 @{ HOME = ($h -replace '\\','/') }) | Out-Null
            BakCount $r1 | Should -Be 1 -Because 'precondition: this setup snapshots when no marker exists'

            New-Item -ItemType Directory -Path (Join-Path $r2 'home/.claude') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $r2 'home/.claude/.no-agy') -Value '' -Encoding ascii
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') `
                -Env (HookEnv $r2 @{ HOME = ($h -replace '\\','/') }) | Out-Null
            BakCount $r2 | Should -Be 0 -Because 'a .no-agy under USERPROFILE must disarm the hook even when HOME resolves elsewhere'
        } finally {
            Remove-Item $r1 -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $r2 -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $h  -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'snapshots when agy-curate is invoked as a SLASH COMMAND' {
        # The reported defect, verbatim: measured 2026-08-03, no new .bak appeared on this path.
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (PromptPayload '/agy-autotrain:agy-curate') -Env (HookEnv $r) | Out-Null
            BakCount $r | Should -Be 1
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT snapshot on an ordinary prompt that merely mentions agy-curate' {
        # CONTROL. A bare substring match fires on this. The existing jq-absent branch already records why
        # that is wrong: another skill could merely MENTION agy-curate in its args.
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (PromptPayload 'why did agy-curate skip the snapshot last time?') -Env (HookEnv $r) | Out-Null
            BakCount $r | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'snapshots on a slash command WITH trailing arguments' {
        # /agy-autotrain:agy-curate --dry-run is a real invocation and must not be treated as prose.
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (PromptPayload '/agy-autotrain:agy-curate --dry-run') -Env (HookEnv $r) | Out-Null
            BakCount $r | Should -Be 1
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'still snapshots on the Skill-tool path' {
        # Regression guard: the path that already worked must keep working.
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env (HookEnv $r) | Out-Null
            BakCount $r | Should -Be 1
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'burns only ONE slot when both paths fire in the same drain' {
        # The hook now has two ways to fire in one drain (the user types the slash command AND the skill body
        # later triggers the Skill tool). The dedup invariant is what prevents that burning two slots.
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (PromptPayload '/agy-autotrain:agy-curate') -Env (HookEnv $r) | Out-Null
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env (HookEnv $r) | Out-Null
            BakCount $r | Should -Be 1 -Because 'the dedup invariant exists for exactly this'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'honours every SLASH-COMMAND contract on the jq-ABSENT fallback branch too' {
        # The three prompt-shape tests above all run with jq on PATH, so they exercise ONLY the jq arm.
        # The field-bounded-grep fallback (agy-inbox-snapshot.sh:63-64) is, by this suite's own note
        # above, "the path that actually runs" on a stock end-user box - and it had no prompt coverage
        # at all. MEASURED at f29cd42: deleting that elif arm left all 24 tests green while
        # `/agy-autotrain:agy-curate` stopped snapshotting on any box without jq.
        # PATH=/usr/bin removes jq while keeping grep/cp/date/ls/cmp/head/tail/rm, all of which live there.
        $fallback = @{ PATH = '/usr/bin' }

        # ASSERT THE ARM, do not assume it. Every bit of this test's discriminating power rests on jq
        # being unreachable under that PATH - an assumption about the MACHINE, not about the code. If jq
        # ever resolves there (a different runner image, a repackaged Git-for-Windows), all three cells
        # below silently become duplicates of the three jq-arm tests above, and the elif at
        # agy-inbox-snapshot.sh:63-64 - which this suite calls "the path that actually runs" on a stock
        # box - goes uncovered with nothing red. The probe runs through the SAME harness and env as the
        # cases it guards, so it cannot pass for a different reason than they do.
        $probe = Join-Path ([IO.Path]::GetTempPath()) ("jqprobe-" + [Guid]::NewGuid().ToString('N') + ".sh")
        Set-Content -LiteralPath $probe -Value "command -v jq 2>/dev/null || true" -Encoding ascii -NoNewline
        try {
            $jq = Invoke-BashHook -HookPath $probe -Payload '{}' -Env $fallback
            $jq.StdOut | Should -BeNullOrEmpty -Because 'PATH=/usr/bin must make jq UNREACHABLE, or these three cells silently retest the jq arm and the fallback branch is uncovered again'
        } finally { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue }

        $r1 = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (PromptPayload '/agy-autotrain:agy-curate') -Env (HookEnv $r1 $fallback) | Out-Null
            BakCount $r1 | Should -Be 1 -Because 'the reported 2026-08-03 defect must stay fixed on the branch most installs actually take'
        } finally { Remove-Item $r1 -Recurse -Force -ErrorAction SilentlyContinue }

        $r2 = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (PromptPayload '/agy-autotrain:agy-curate --dry-run') -Env (HookEnv $r2 $fallback) | Out-Null
            BakCount $r2 | Should -Be 1 -Because 'a slash command with trailing arguments is a real invocation on the fallback branch too'
        } finally { Remove-Item $r2 -Recurse -Force -ErrorAction SilentlyContinue }

        # THE CONTROL. Without this the two assertions above would also pass under a bare substring
        # match, which is precisely what the field-bounded grep exists to prevent.
        $r3 = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (PromptPayload 'why did agy-curate skip the snapshot last time?') -Env (HookEnv $r3 $fallback) | Out-Null
            BakCount $r3 | Should -Be 0 -Because 'prose that merely mentions agy-curate must not burn a snapshot slot on the fallback branch either'
        } finally { Remove-Item $r3 -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'resolves the inbox from HOME when USERPROFILE is ABSENT, and when it is EMPTY' {
        # HOME_DIR="${USERPROFILE:-$HOME}" (agy-inbox-snapshot.sh:19). Every call in this suite goes
        # through HookEnv, which sets BOTH variables to real absolute paths, so the fallback half was
        # never taken on any machine and CI is windows-latest. MEASURED at f29cd42: rewriting it to
        # "${USERPROFILE}" left all 24 tests green while on a POSIX install the hook resolved
        # /.clavity/agy-observations.md, found nothing, and took NO SNAPSHOT before a drain - the one
        # thing this hook exists to guarantee.
        # ABSENT and EMPTY are different bugs: absent catches dropping the fallback, empty catches the
        # one-character ${USERPROFILE-$HOME}, which treats present-but-empty as set.
        $r1 = New-PluginRoot $script:Good
        try {
            # PRECONDITION: the ordinary shape snapshots. The baseline the two below are measured against.
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env (HookEnv $r1) | Out-Null
            BakCount $r1 | Should -Be 1 -Because 'precondition: this payload snapshots when both variables are set'
        } finally { Remove-Item $r1 -Recurse -Force -ErrorAction SilentlyContinue }

        $r2 = New-PluginRoot $script:Good
        try {
            # [NullString]::Value is the only form that DELETES the variable - see BashHookHelpers.ps1.
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env (HookEnv $r2 @{ USERPROFILE = [NullString]::Value }) | Out-Null
            BakCount $r2 | Should -Be 1 -Because 'with USERPROFILE absent the inbox must resolve from HOME, or no snapshot is ever taken'
        } finally { Remove-Item $r2 -Recurse -Force -ErrorAction SilentlyContinue }

        $r3 = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env (HookEnv $r3 @{ USERPROFILE = '' }) | Out-Null
            BakCount $r3 | Should -Be 1 -Because 'an EMPTY USERPROFILE must fall back too - the colon in ${VAR:-alt} is load-bearing'
        } finally { Remove-Item $r3 -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is NOT disarmed by a .no-agy in the payload cwd - a deliberate asymmetry with its two siblings' {
        # PINS A KNOWN ASYMMETRY RATHER THAN ASSUMING IT. MEASURED at f29cd42: agy-curate-nudge.sh and
        # agy-learn-reminder.sh each parse `.cwd` from the payload and honour a project-local marker;
        # this hook parses `.cwd` ZERO times, so an operator dropping .no-agy in a project root silences
        # two of the three hooks and not this one. Nothing asserted that in EITHER direction, so a
        # "consistency" edit could add or remove the check with no test movement.
        # The asymmetry is arguably defensible - this hook fires on PreToolUse/UserPromptSubmit, where
        # cwd semantics differ from SessionStart - and is under review in the kill-switch sweep. Until
        # that is ruled, this test pins TODAY's behaviour so the change is deliberate and visible: if
        # the sweep decides the cwd marker SHOULD disarm this hook, this test reds and gets updated in
        # the same commit, which is exactly the conversation the pin exists to force.
        $r = New-PluginRoot $script:Good
        $cwd = Join-Path ([IO.Path]::GetTempPath()) ("ibxcwd-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $cwd -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $cwd '.no-agy') -Value '' -Encoding ascii
            # PRECONDITION: neither home root carries a marker, so any silence would have to come from
            # the cwd marker rather than from the setup.
            (Test-Path (Join-Path $r 'home/.claude/.no-agy')) | Should -BeFalse -Because 'no home-root marker may exist, or this test cannot attribute the outcome to cwd'

            $payload = @{ tool_name = 'Skill'; tool_input = @{ skill = 'agy-autotrain:agy-curate' }
                          cwd = ($cwd -replace '\\','/'); session_id = 'ibxtest' } | ConvertTo-Json -Compress
            Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env (HookEnv $r) | Out-Null
            BakCount $r | Should -Be 1 -Because 'this hook does not read .cwd today; the snapshot must still be taken'
        } finally {
            Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $cwd -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

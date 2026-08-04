Describe 'check-seed-artifacts-synced.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Script   = Join-Path $script:RepoRoot 'scripts/check-seed-artifacts-synced.sh'
        # ...\Git\usr\bin carries diff/sed but NOT jq (verified: the hook jq-missing tests rely on this),
        # so pointing PATH here reproduces "jq absent" deterministically. Git Bash is invoked by ABSOLUTE
        # path inside Invoke-BashHook, so bash itself need not be on this restricted PATH.
        $bashDir = Split-Path -Parent (Get-GitBashOrThrow)                       # ...\Git\bin
        $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')   # ...\Git\usr\bin

        # The script uses repo-root-relative paths, so the bash child must run with cwd = repo root.
        # Native processes launched from pwsh inherit [Environment]::CurrentDirectory (NOT the PSDrive
        # location), so set that around each call.
        function Invoke-SeedSync {
            param([hashtable]$Env = @{})
            $savedCwd = [Environment]::CurrentDirectory
            [Environment]::CurrentDirectory = $script:RepoRoot
            try { return (Invoke-BashHook -HookPath $script:Script -Env $Env) }
            finally { [Environment]::CurrentDirectory = $savedCwd }
        }
    }

    It 'passes (exit 0, reports in sync) on the real repo when jq is available' {
        $r = Invoke-SeedSync
        $r.ExitCode | Should -Be 0
        $r.StdOut   | Should -Match 'in sync'
    }

    It 'FAILS LOUD (exit 2) instead of silently passing when jq is absent' {
        # Regression guard: previously `diff <(jq ...) <(jq ...)` swallowed jq's "command not found" (a
        # process substitution's exit code does not propagate under set -e), so the guard silently exited 0
        # while performing NO hooks.json drift check. The top-of-script jq presence gate must fail loud.
        $r = Invoke-SeedSync -Env @{ PATH = $script:NoJqPath }
        $r.ExitCode | Should -Be 2
        $r.StdErr   | Should -Match 'jq is required'
    }

    It 'FIRES when a new shared file exists in clavity-dotnet only' {
        # The defect this milestone fixes: under the old allow-list, a file nobody enrolled was never
        # compared, so it could exist in one plugin only and the gate stayed green. Omission was
        # indistinguishable from synchronisation.
        # ASSERT THE DIRECTION, not just the filename: this probe exercises the `! -f "$C/$rel"` branch
        # only. Its mirror below covers the other branch. A filename-only assertion cannot tell them apart.
        $probe = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/skills/zz-discovery-probe/SKILL.md'
        New-Item -ItemType Directory -Path (Split-Path $probe) -Force | Out-Null
        Set-Content $probe "---`nname: zz-discovery-probe`n---`nprobe`n" -Encoding ascii
        try {
            $r = Invoke-SeedSync
            $r.ExitCode | Should -Not -Be 0
            "$($r.StdOut)`n$($r.StdErr)" |
                Should -Match 'zz-discovery-probe/SKILL\.md exists in clavity-dotnet/plugin but NOT in clavity-classic/plugin'
        } finally { Remove-Item (Split-Path $probe) -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES when a new shared file exists in clavity-classic only' {
        # The MIRROR, and it is not redundant. MEASURED: without it, NO test in this file ever creates a
        # file present in classic and absent from dotnet, so the walk's `[ ! -f "$D/$rel" ]` branch is
        # never exercised — it can be DELETED OUTRIGHT and all other tests stay green. A guard no test
        # reaches is not a guard.
        $probe = Join-Path $script:RepoRoot 'clavity-classic/plugin/skills/zz-probe-classic-only/SKILL.md'
        New-Item -ItemType Directory -Path (Split-Path $probe) -Force | Out-Null
        Set-Content $probe "---`nname: zz-probe-classic-only`n---`nprobe`n" -Encoding ascii
        try {
            $r = Invoke-SeedSync
            $r.ExitCode | Should -Not -Be 0
            "$($r.StdOut)`n$($r.StdErr)" |
                Should -Match 'zz-probe-classic-only/SKILL\.md exists in clavity-classic/plugin but NOT in clavity-dotnet/plugin'
        } finally { Remove-Item (Split-Path $probe) -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'stays GREEN for every intentionally-divergent twin' {
        # The five files that legitimately exist in one plugin only. If discovery flagged these the gate
        # would be permanently red and would be routed around.
        $r = Invoke-SeedSync
        $r.ExitCode | Should -Be 0
        "$($r.StdOut)`n$($r.StdErr)" | Should -Not -Match 'agy-drive-session-reset|ls-driving|ls-pairing|skills/driving|skills/responder'
    }

    It 'still FIRES when an enrolled shared file differs in content' {
        # Regression guard: discovery must not lose the behaviour the allow-list already had.
        $f = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks/agy-after-reminder.sh'
        $orig = Get-Content $f -Raw
        try {
            Add-Content $f "`n# discovery drift probe`n"
            (Invoke-SeedSync).ExitCode | Should -Not -Be 0
        } finally { Set-Content $f $orig -NoNewline }
    }

    It 'FIRES when hooks.json is missing from one plugin, despite being compared elsewhere' {
        # compared_elsewhere() delegates hooks.json CONTENT to the jq blocks further down, but it must not
        # become an escape hatch: it requires the file on BOTH sides, so a deletion still trips the walk.
        #
        # ⚠ ASSERT THE WALK'S OWN LINE, NOT MERELY THAT "hooks.json" APPEARS SOMEWHERE. MEASURED: with the
        # file absent, FOUR messages name hooks/hooks.json — the walk's existence line, plus three from the
        # pre-existing jq blocks (jq errors on the missing file, its process substitution yields empty
        # output, and `diff -q` reports that as differing). A loose /hooks\.json/ assertion therefore passes
        # even when compared_elsewhere() is gutted to a bare `return 0`, so the mutation row that is supposed
        # to prove the two-sided guard proves NOTHING. Only the line below comes from the walk.
        #
        # Park the backup OUTSIDE the plugin trees: a *.bak beside the original is itself discovered and
        # reported as classic-only, which is noise this assertion should not have to tolerate.
        $f   = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks/hooks.json'
        $bak = Join-Path ([IO.Path]::GetTempPath()) 'clavity-classic-hooks-json.testbak'
        Move-Item $f $bak -Force
        try {
            $r = Invoke-SeedSync
            $r.ExitCode | Should -Not -Be 0
            "$($r.StdOut)`n$($r.StdErr)" |
                Should -Match 'hooks/hooks\.json exists in clavity-dotnet/plugin but NOT in clavity-classic/plugin'
        } finally { Move-Item $bak $f -Force }
    }

    It 'FIRES when the PreCompact block differs between the two plugins' {
        # The per-event jq rules are an ALLOW-LIST of events. Before this rule existed, PreCompact was
        # compared by nothing at all: compared_elsewhere() waives hooks.json from the byte-diff and
        # delegates its content to those rules, so an event without a rule is silently unchecked.
        $f = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks/hooks.json'
        $orig = Get-Content -Raw -LiteralPath $f
        try {
            $j = $orig | ConvertFrom-Json
            $j.hooks.PreCompact[0].matcher = 'manual'
            $j | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $f -Encoding ascii
            $r = Invoke-SeedSync
            $r.ExitCode | Should -Not -Be 0
            "$($r.StdOut)`n$($r.StdErr)" | Should -Match 'PreCompact'
        } finally { Set-Content -LiteralPath $f -Value $orig -NoNewline }
    }

    It 'FIRES when one plugin registers an EVENT the other does not' {
        # The CLASS fix, not just the PreCompact instance: a future event added to one manifest and not
        # the other would be invisible to every per-event rule. Uses an event name no rule names, so this
        # can only pass via the whole-hooks catch-all.
        $f = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks/hooks.json'
        $orig = Get-Content -Raw -LiteralPath $f
        try {
            $j = $orig | ConvertFrom-Json
            $j.hooks | Add-Member -NotePropertyName 'Notification' -NotePropertyValue @(
                @{ matcher = '*'; hooks = @(@{ type = 'command'; command = 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/agy-liveness-check.sh"' }) }
            )
            $j | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $f -Encoding ascii
            $r = Invoke-SeedSync
            $r.ExitCode | Should -Not -Be 0
            "$($r.StdOut)`n$($r.StdErr)" | Should -Match 'event set or hook contents'
        } finally { Set-Content -LiteralPath $f -Value $orig -NoNewline }
    }

    It 'FIRES when both plugins register the SAME new event with DIFFERENT contents' {
        # THE CONTROL THAT DISTINGUISHES THE FIX FROM ITS HALF-MEASURE. A key-set comparison passes this
        # case - both manifests carry the same event NAME - so if this test goes green while the gate is
        # only comparing keys, the class is not actually closed. Measured before the catch-all existed:
        # the key sets compare equal and the gate reports GREEN.
        $f = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks/hooks.json'
        $g = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/hooks.json'
        $origC = Get-Content -Raw -LiteralPath $f
        $origD = Get-Content -Raw -LiteralPath $g
        try {
            foreach ($pair in @(@{ Path = $f; Script = 'agy-liveness-check.sh' },
                                @{ Path = $g; Script = 'agy-anomaly-reminder.sh' })) {
                $cmd = 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/' + $pair.Script + '"'
                $j = Get-Content -Raw -LiteralPath $pair.Path | ConvertFrom-Json
                $j.hooks | Add-Member -NotePropertyName 'Notification' -NotePropertyValue @(
                    @{ matcher = '*'; hooks = @(@{ type = 'command'; command = $cmd }) }
                )
                $j | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $pair.Path -Encoding ascii
            }
            $r = Invoke-SeedSync
            $r.ExitCode | Should -Not -Be 0 -Because 'the event NAMES match; only the contents differ'
            "$($r.StdOut)`n$($r.StdErr)" | Should -Match 'event set or hook contents'
        } finally {
            Set-Content -LiteralPath $f -Value $origC -NoNewline
            Set-Content -LiteralPath $g -Value $origD -NoNewline
        }
    }
}

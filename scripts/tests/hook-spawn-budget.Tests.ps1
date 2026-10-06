# THE PROCESS BUDGET OF EVERY REGISTERED HOOK (ROADMAP Branch 20; owner ruling 2026-10-04).
#
# WHY: on the owner's machine EVERY process creation costs ~180-360 ms, whatever the process (measured
# 2026-10-04: native rg.exe and msys tools cost the same, so it is process creation, not msys emulation).
# A hook that starts 40 processes on every Bash call costs seconds per call; the SessionStart ones were timing
# out. Wall-clock limits on a shared box are noise (TIMING discipline), so the gate is the COUNT, which a
# Windows Job Object reports deterministically (Measure-BashHookProcesses, BashHookHelpers.ps1).
#
# THREE KINDS OF ROW, read together:
#   - one row per (hook, named path) asserting at most HookCeiling processes beyond boot. Each row that names
#     a path which EMITS asserts the emission (-Expect), and each silent path asserts silence (-Silent) - a
#     row whose fixture missed its path would otherwise certify an early exit;
#   - the census row: every hook in the four registries has at least one row, so a new hook cannot ship
#     uncounted;
#   - the Branch 21 debt row: RED until $B21Debt is empty (owner ruling: a visible failure, not a pin).
# Plus one SCALING row: consult-recovery costs the same with 1 seam and with 1000.

BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'hook-spawn-budget.Rows.ps1')
}

Describe 'hook spawn budget' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        . (Join-Path $PSScriptRoot 'hook-spawn-budget.Rows.ps1')
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }

    It 'gives every hook in the four registries at least one budget row' -Tag 'census' -Skip:([bool]$env:HSB_HOOK) {
        $registries = 'clavity-dotnet/plugin/hooks/hooks.json', 'clavity-classic/plugin/hooks/hooks.json', 'agy-autotrain/hooks/hooks.json', '.claude/settings.json'
        $registered = @(foreach ($r in $registries) {
            [regex]::Matches((Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot $r)), '[/\\]hooks[/\\]([A-Za-z0-9._-]+\.sh)') | ForEach-Object { $_.Groups[1].Value }
        }) | Sort-Object -Unique
        $registered.Count | Should -BeGreaterThan 20 -Because 'the four registries must parse into their hook names, or this row checks nothing'
        $covered = @($script:Rows | ForEach-Object { Split-Path -Leaf $_.Hook }) | Sort-Object -Unique
        (@($registered | Where-Object { $_ -notin $covered }) -join ', ') | Should -BeExactly '' -Because 'a registered hook with no budget row ships with no limit on what it costs every session - add a row to hook-spawn-budget.Rows.ps1'
    }

    It 'carries no Branch 21 debt (RED until Branch 21 lands - owner ruling 2026-10-04)' -Tag 'debt' {
        # CI runs this whole directory on EVERY PR with no paths filter (ci-scripts.yml), and merge-gate guards
        # main and Dependabot auto-merge, so a red row there would block every merge until Branch 21. Owner
        # ruling 2026-10-05, agreed with agy (fork A): RED locally, SKIPPED on CI with the debt in the reason so
        # every CI log still names it.
        if ($env:GITHUB_ACTIONS -and $script:B21Debt.Count) {
            Set-ItResult -Skipped -Because ('Branch 21 debt, CI-only skip: ' + (@($script:B21Debt | ForEach-Object { "$($_.Hook) [$($_.Path)] $($_.Total) total" }) -join '; '))
        }
        (@($script:B21Debt | ForEach-Object { "$($_.Hook) [$($_.Path)] measured $($_.Total) total" }) -join '; ') | Should -BeExactly '' -Because 'each listed path is over the 16-process ceiling; Branch 21 removes an entry in the commit that brings its path under it'
    }

    It '<Hook>: <Name> starts at most <Max> processes beyond bash boot' -ForEach $Rows -Tag 'row' {
        $fx = New-HookFixture @Fixture
        try {
            $payload = & $Setup $fx
            $r = Measure-BashHookProcesses -HookPath (Join-Path $script:RepoRoot $Hook) -Payload $payload -Env $fx.Env -Arguments $HookArgs -WorkingDirectory $fx.Repo
            if ($Expect) { $r.StdOut | Should -Match ([regex]::Escape($Expect)) -Because 'the row must reach the path it names, or its count proves nothing' }
            if ($Silent) { $r.StdOut | Should -BeNullOrEmpty -Because 'this path is silent; output means the fixture reached a different path' }
            if ($Verify) { & $Verify $fx }
            $r.Spawned | Should -BeLessOrEqual $Max -Because "$Hook on '$Name' started $($r.Spawned) processes beyond the $($r.Boot)-process boot"
        } finally { Remove-Item -LiteralPath $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It '<Hook>: <Name> prints the same on the bash 3.2 code path' -ForEach $Rows -Tag 'compat' {
        # Capstone R1 (owner ruling 2026-10-06, hybrid): on bash < 4.1 every hook falls back to its pre-Branch-20
        # stdin read (and curate to `date` for its clock). CLAVITY_HOOK_BASH3=1 forces that path here, which has no
        # bash 3.2. Same fixture shape both times; paths normalised, because each fixture has its own temp root.
        $outs = foreach ($compat in $false, $true) {
            $fx = New-HookFixture @Fixture
            try {
                if ($compat) { $fx.Env.CLAVITY_HOOK_BASH3 = '1' }
                $payload = & $Setup $fx
                $r = Measure-BashHookProcesses -HookPath (Join-Path $script:RepoRoot $Hook) -Payload $payload -Env $fx.Env -Arguments $HookArgs -WorkingDirectory $fx.Repo
                # The row's effect check runs on BOTH paths: equal (often empty) output alone cannot tell a fallback
                # that did its work from one that exited early (agy capstone R2). consult-recovery's bash 3.2 path
                # exits on purpose, so its rows carry no effect check.
                if ($Verify -and -not ($compat -and (Split-Path -Leaf $Hook) -eq 'agy-consult-recovery.sh')) { & $Verify $fx }
                $t = "$($r.StdOut)"
                foreach ($form in $fx.Root, ($fx.Root -replace '\\', '/'), ($fx.Root -replace '\\', '\\')) { $t = $t.Replace($form, '<ROOT>') }
                $t
            } finally { Remove-Item -LiteralPath $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
        }
        if ((Split-Path -Leaf $Hook) -eq 'agy-consult-recovery.sh') {
            $outs[1] | Should -Match 'inactive: needs bash 4.3 or newer' -Because 'consult-recovery needs bash 4.3 and must say so rather than fail silently'
        } else {
            $outs[1] | Should -BeExactly $outs[0] -Because 'the bash 3.2 fallback must behave exactly like the bash 4 path'
        }
    }

    It 'agy-consult-recovery.sh costs the same with 1 seam and with 1000 (the cost must not scale with the seam count)' -Tag 'scaling' {
        $one = New-HookFixture; $big = New-HookFixture
        try {
            Add-FxSeams $one 'agy-capstone-r1-x.md'
            Add-FxSeams $big (1..1000 | ForEach-Object { if ($_ % 2) { "agy-capstone-r$_-x.md" } else { "loose-$_.md" } })
            $hook = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-consult-recovery.sh'
            $a = Measure-BashHookProcesses -HookPath $hook -Payload (New-SessionStartPayload $one) -Env $one.Env -WorkingDirectory $one.Repo
            $b = Measure-BashHookProcesses -HookPath $hook -Payload (New-SessionStartPayload $big) -Env $big.Env -WorkingDirectory $big.Repo
            $b.Spawned | Should -Be $a.Spawned -Because 'a per-seam process (a stat, a git call, an ls of each file) makes SessionStart cost grow with the seam directory, which reached 1031 files in this repo'
        } finally { Remove-Item -LiteralPath $one.Root, $big.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

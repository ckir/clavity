# The MODEL-addressed half of the SessionStart anomaly notice.
#
# WHY A SECOND HOOK RATHER THAN A SECOND printf. The two channels cannot come from one invocation: the
# owner-addressed notice is stderr at exit 2, and stdout on an exit-2 hook is DISCARDED (measured). A
# matcher object's hooks array may hold several commands and exit status is PER-HOOK, so the two live
# side by side under the same matcher and fire on exactly the same occasions.
#
# NOTE ON THE BYTE SCAN. Its siblings assert the emitted text carries no double quote or backslash,
# because they hand-build a JSON envelope with printf when jq is absent. This hook has NO hand-built
# envelope - it exits 0 silently without jq - and its message interpolates a filesystem path, so a byte
# scan here would be asserting a property of the environment rather than of the hook. The fixed directive
# text is pinned instead.

Describe 'agy-anomaly-model-notice.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook  = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-anomaly-model-notice.sh'
        # The OWNER-side sibling, for the cross-check that the two halves count the same things.
        $script:Drain = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh'
        $bashDir = Split-Path -Parent (Get-GitBashOrThrow)
        $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')

        function New-CleanHome {
            $h = Join-Path ([IO.Path]::GetTempPath()) ("anom-mn-home-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $h '.claude') -Force | Out-Null
            return $h
        }
        # A git worktree, because the hook resolves the repo toplevel exactly as agy-anomaly-reminder.sh
        # does (:41-45) so both sides always agree on where the anomalies file lives.
        function New-RepoWith { param([string]$Anomalies)
            $r = New-TempRepo
            if ($null -ne $Anomalies) {
                New-Item -ItemType Directory -Path (Join-Path $r '.clavity') -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $r '.clavity/local-anomalies.md') -Value $Anomalies
            }
            return $r
        }
        function New-Entries { param([int]$N)
            (1..$N | ForEach-Object { "- [defect] thing $_ * a.ts:$_ * 2026-08-0$(($_ % 9) + 1) * task=x" }) -join "`n"
        }
        function Payload { param([string]$Cwd) @{ cwd = ($Cwd -replace '\\','/'); source = 'startup' } | ConvertTo-Json -Compress }
        function Get-Ctx { param($Result) ($Result.StdOut | ConvertFrom-Json).hookSpecificOutput.additionalContext }
    }

    It 'is SILENT when there are no untriaged anomalies' {
        $r = New-RepoWith $null; $h = New-CleanHome
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            $x.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'emits hookSpecificOutput naming the EXACT count when entries are pending' {
        $r = New-RepoWith (New-Entries 2); $h = New-CleanHome
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            $j = $x.StdOut | ConvertFrom-Json
            $j.hookSpecificOutput.hookEventName | Should -BeExactly 'SessionStart'
            $ctx = $j.hookSpecificOutput.additionalContext
            # Capture the number and compare it EXACTLY. A -Match '2 untriaged' is also satisfied by
            # "12 untriaged", so a substring assertion here cannot tell a correct count from a wrong one.
            ($ctx -match '(\d+) untriaged') | Should -BeTrue -Because 'the notice must name a count'
            $Matches[1] | Should -BeExactly '2'
            $ctx | Should -Match ([regex]::Escape('There is no parked state'))
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'delivers the triage directive WHOLE, not just its bookends' {
        # This suite asserted the count exactly and then only the trailing clause, leaving the OPERATIVE
        # middle - what the reader is actually told to DO with each entry - unguarded. Its two sibling
        # suites pin their directive verbatim for exactly this reason: a bookend pair is satisfied by a
        # message whose instruction has been gutted. Measured on a prior epic at ~95% of the clause.
        # The head and tail are invariant; only the count and the path interpolate, so both invariant
        # halves are pinned WHOLE here.
        $r = New-RepoWith (New-Entries 3); $h = New-CleanHome
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            $ctx = Get-Ctx $x
            $ctx | Should -Not -BeNullOrEmpty -Because 'a silent hook would satisfy every match below vacuously'
            $ctx | Should -Match ('^' + [regex]::Escape('AGY-ANOMALIES/1: 3 untriaged in ')) `
                 -Because 'the contract stamp and the count open the message; see agy-anomaly-contract-stamp.Tests.ps1'
            $ctx | Should -Match ([regex]::Escape('. Triage before new work via the open-issues skill: each entry is either PROMOTED to a tracked item with an owner, or DELETEd with a recorded reason. There is no parked state.')) `
                 -Because 'the directive is the payload - gutting it leaves a notice that names a number and asks for nothing'
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports 12 as twelve, not as a substring of two' {
        # The control for the assertion above. Without it, a count that is wrong in the tens digit is
        # indistinguishable from a correct one under any substring match.
        $r = New-RepoWith (New-Entries 12); $h = New-CleanHome
        try {
            $ctx = Get-Ctx (Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r) -Env @{ HOME = $h })
            ($ctx -match '(\d+) untriaged') | Should -BeTrue -Because 'the notice must name a count'
            $Matches[1] | Should -BeExactly '12'
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'agrees with the OWNER-side hook on the count' {
        # THE DESIGN INVARIANT, AND NOTHING ELSE PINS IT. The whole justification for duplicating the
        # counting logic in this hook rather than sharing it is that the two halves must never disagree
        # about what is pending - one telling the owner 3 while the other tells the model 2 is worse than
        # either being silent. The two use different channels (stdout JSON at exit 0 vs stderr at exit 2),
        # so the only way to compare them is to run both and parse each one's own output.
        $r = New-RepoWith (New-Entries 5); $h = New-CleanHome
        try {
            $model = Get-Ctx (Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r) -Env @{ HOME = $h })
            ($model -match '(\d+) untriaged') | Should -BeTrue -Because 'the model half must name a count'
            $modelN = $Matches[1]

            $owner = (Invoke-BashHook -HookPath $script:Drain -Payload (Payload $r) -Env @{ HOME = $h }).StdErr
            ($owner -match '(\d+) untriaged') | Should -BeTrue -Because 'the owner-side hook must also be reporting a count here'
            $ownerN = $Matches[1]

            $modelN | Should -BeExactly $ownerN
            $modelN | Should -BeExactly '5' -Because 'both halves agreeing on a WRONG number would still pass the equality above'
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 0 even with entries pending, so the owner-side hook is unaffected' {
        # Its sibling exits 2 by design. This one must not, or a SessionStart carrying pending anomalies
        # would surface two blocking advisories where the design intends one notice per audience.
        $r = New-RepoWith (New-Entries 1); $h = New-CleanHome
        try {
            (Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r) -Env @{ HOME = $h }).ExitCode | Should -Be 0
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a WORKSPACE .no-agy' {
        # Both sibling hooks honour the workspace kill-switch as well as the global one. A hook that
        # honours only the global switch cannot be turned off for one repo.
        $r = New-RepoWith (New-Entries 1); $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $r '.no-agy') -Force | Out-Null
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            $x.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a GLOBAL .no-agy' {
        $r = New-RepoWith (New-Entries 1); $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $r) -Env @{ HOME = $h }
            $x.ExitCode | Should -Be 0
            $x.StdOut   | Should -BeNullOrEmpty
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT when .no-agy is at the repo root and cwd is a subdirectory' {
        # The suite's own Payload helper forward-slashes cwd, which is the repo-wide convention and is
        # exactly why this bug survived: a POSIX-shaped path cannot exercise the Windows walk. These two
        # tests hand-build the RAW backslashed shape the real payload has.
        $r = New-RepoWith (New-Entries 1); $h = New-CleanHome
        try {
            $sub = Join-Path $r 'src'
            New-Item -ItemType Directory -Path $sub -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $r '.no-agy') -Force | Out-Null

            $payload = '{"cwd":"' + ($sub -replace '\\', '\\') + '","source":"startup"}'
            $x = Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env @{ HOME = $h }

            $x.ExitCode | Should -Be 0
            $x.StdOut   | Should -BeNullOrEmpty -Because 'an opt-out at the repo root must suppress this hook from a subdirectory'
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'DOES fire from that same subdirectory when .no-agy is absent (positive control)' {
        # THIS TEST IS THE REAL ORACLE OF THE PAIR, and that is not a general principle - it is a measured
        # fact about THIS hook. MEASURED 2026-08-05: with the backslash normalization removed, the walk
        # never leaves the subdirectory, so the hook cannot find the anomalies file and exits silently -
        # and the silence test above passes for entirely the wrong reason. Only this control goes red.
        # Never delete it, and never read a green silence test here as evidence the walk works.
        $r = New-RepoWith (New-Entries 1); $h = New-CleanHome
        try {
            $sub = Join-Path $r 'src'
            New-Item -ItemType Directory -Path $sub -Force | Out-Null

            $payload = '{"cwd":"' + ($sub -replace '\\', '\\') + '","source":"startup"}'
            $x = Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env @{ HOME = $h }

            (Get-Ctx $x) | Should -Match 'AGY-ANOMALIES/1' -Because 'without the opt-out it must still fire - otherwise the silence test proves nothing'
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 0 when jq is absent' {
        $h = New-CleanHome
        try {
            (Invoke-BashHook -HookPath $script:Hook -Payload '{"cwd":"."}' -Env @{ PATH = $script:NoJqPath; HOME = $h }).ExitCode | Should -Be 0
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# The AGY-ANOMALIES CONTRACT STAMP, across all three model-addressed anomaly hooks and BOTH drivers.
#
# WHY A STAMP EXISTS, stated from measurement rather than intent:
#   1. ATTRIBUTION. A transcript delivery record (`hook_additional_context`) carries hookEvent + hookName
#      but NO field naming the script - and hookName is <Event>:<ToolName>, shared by every plugin that
#      registers on that tool. MEASURED on a real transcript: 6 structural matches on PreToolUse:Agent, of
#      which only 1 was this project's relay. So a reader must discriminate on a token INSIDE the message.
#   2. PROVENANCE. Nothing the hooks emit says which contract produced it, so a stale install and a
#      current one are indistinguishable - the failure that let v15 ship silently.
#
# WHY IT IS A **CONTRACT** VERSION AND NOT THE BUILD VERSION. The two drivers are at different plugin
# versions (MEASURED 2026-08-04: clavity-dotnet 0.6.0, clavity-classic 0.5.0) while these hook bodies must
# stay byte-identical, so a build literal is a parity break by construction. That is Option S,
# docs/agy-disciplines-marker-contract.md:13. The contract version is hand-bumped and shared.
#
# BUMP DISCIPLINE. If you change any emitted message text, BUMP $script:Stamp here AND in all six hook
# bodies. A message that changes while the contract number does not is precisely the stale stamp this
# exists to prevent.

Describe 'AGY-ANOMALIES contract stamp' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Stamp = 'AGY-ANOMALIES/1'
        $script:Drivers = @('clavity-dotnet', 'clavity-classic')
        $script:Hooks = @(
            'agy-anomaly-capture-reminder.sh'
            'agy-anomaly-dispatch-reminder.sh'
            'agy-anomaly-model-notice.sh'
        )

        function Hook-Path { param([string]$Driver, [string]$Name)
            Join-Path $script:RepoRoot "$Driver/plugin/hooks/$Name"
        }
        function New-CleanHome {
            $h = Join-Path ([IO.Path]::GetTempPath()) ("anom-stamp-home-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $h '.claude') -Force | Out-Null
            return $h
        }
        function New-RepoWithEntries { param([int]$N)
            $r = New-TempRepo
            New-Item -ItemType Directory -Path (Join-Path $r '.clavity') -Force | Out-Null
            $body = (1..$N | ForEach-Object { "- [defect] thing $_ * a.ts:$_ * 2026-08-01 * task=x" }) -join "`n"
            Set-Content -LiteralPath (Join-Path $r '.clavity/local-anomalies.md') -Value $body
            return $r
        }
        # Pull the model-addressed text out of whichever envelope the event uses. PreCompact carries
        # top-level systemMessage; PreToolUse/SessionStart carry hookSpecificOutput.additionalContext.
        function Get-Emitted { param($Result)
            if ([string]::IsNullOrWhiteSpace($Result.StdOut)) { return $null }
            $j = $Result.StdOut | ConvertFrom-Json
            if ($j.PSObject.Properties.Name -contains 'systemMessage') { return $j.systemMessage }
            return $j.hookSpecificOutput.additionalContext
        }
    }

    It 'is byte-ban compliant - carries no backtick, apostrophe, double quote or backslash' {
        $script:Stamp | Should -Not -BeNullOrEmpty -Because 'an empty stamp would satisfy every match below vacuously'
        $script:Stamp | Should -Not -Match '[`''"\\]'
    }

    It 'carries NO per-driver literal - the same stamp is legal in both drivers (Option S)' {
        # A build version would differ per driver and break byte-parity. Assert the stamp is free of one.
        $script:Stamp | Should -Not -Match '\d+\.\d+\.\d+' -Because 'a semver literal is a per-driver value and cannot live in a byte-identical body'
    }

    It '<Driver>/<Name> contains the contract stamp in its source' -ForEach @(
        foreach ($d in @('clavity-dotnet','clavity-classic')) {
            foreach ($n in @('agy-anomaly-capture-reminder.sh','agy-anomaly-dispatch-reminder.sh','agy-anomaly-model-notice.sh')) {
                @{ Driver = $d; Name = $n }
            }
        }
    ) {
        $p = Hook-Path $Driver $Name
        Test-Path -LiteralPath $p | Should -BeTrue -Because 'a scan over a missing file matches nothing and passes vacuously'
        $src = Get-Content -LiteralPath $p -Raw
        $src | Should -Not -BeNullOrEmpty -Because 'an empty body would satisfy the match below vacuously'
        $src | Should -Match ([regex]::Escape($script:Stamp))
    }

    It 'the dispatch reminder EMITS the stamp at the head of its message' {
        $w = New-TempRepo; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath (Hook-Path 'clavity-dotnet' 'agy-anomaly-dispatch-reminder.sh') `
                                 -Payload (@{ cwd = ($w -replace '\\','/'); tool_name = 'Agent' } | ConvertTo-Json -Compress) `
                                 -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $msg = Get-Emitted $r
            $msg | Should -Not -BeNullOrEmpty -Because 'a silent hook would satisfy the match below vacuously'
            $msg | Should -Match ('^' + [regex]::Escape($script:Stamp))
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'the capture reminder EMITS the stamp at the head of its message' {
        $w = New-TempRepo; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath (Hook-Path 'clavity-dotnet' 'agy-anomaly-capture-reminder.sh') `
                                 -Payload (@{ cwd = ($w -replace '\\','/'); trigger = 'manual' } | ConvertTo-Json -Compress) `
                                 -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $msg = Get-Emitted $r
            $msg | Should -Not -BeNullOrEmpty -Because 'a silent hook would satisfy the match below vacuously'
            $msg | Should -Match ('^' + [regex]::Escape($script:Stamp))
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'the model notice EMITS the stamp at the head of its message' {
        $w = New-RepoWithEntries 2; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath (Hook-Path 'clavity-dotnet' 'agy-anomaly-model-notice.sh') `
                                 -Payload (@{ cwd = ($w -replace '\\','/'); source = 'startup' } | ConvertTo-Json -Compress) `
                                 -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $msg = Get-Emitted $r
            $msg | Should -Not -BeNullOrEmpty -Because 'this hook is SILENT with no entries - an empty message here means the fixture failed, not that the stamp is absent'
            $msg | Should -Match ('^' + [regex]::Escape($script:Stamp))
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'both drivers ship the three hooks byte-identically, stamp included' -ForEach @(
        @{ Name = 'agy-anomaly-capture-reminder.sh' }
        @{ Name = 'agy-anomaly-dispatch-reminder.sh' }
        @{ Name = 'agy-anomaly-model-notice.sh' }
    ) {
        $a = Hook-Path 'clavity-dotnet' $Name
        $b = Hook-Path 'clavity-classic' $Name
        Test-Path -LiteralPath $a | Should -BeTrue
        Test-Path -LiteralPath $b | Should -BeTrue
        $ha = (Get-FileHash -LiteralPath $a -Algorithm SHA256).Hash
        $hb = (Get-FileHash -LiteralPath $b -Algorithm SHA256).Hash
        $ha | Should -Not -BeNullOrEmpty
        $hb | Should -BeExactly $ha -Because 'a per-driver stamp literal would break parity here first'
    }
}

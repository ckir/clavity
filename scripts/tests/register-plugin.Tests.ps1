BeforeAll {
    # Dot-source: defines functions, does NOT run main (guarded by $MyInvocation.InvocationName -eq '.').
    . ([System.IO.Path]::Combine($PSScriptRoot, '..', '..', 'installer', '_shared', 'register-plugin.ps1'))
}

Describe 'Format-Reason' {
    It 'collapses newlines so a child cannot forge a second AGENT line' {
        Format-Reason "line1`nAGENT claude OK`r`nline3" | Should -Not -Match "`n"
        Format-Reason "line1`nAGENT claude OK" | Should -Be 'line1 AGENT claude OK'
    }
    It 'bounds the length to 200 chars' {
        (Format-Reason ('x' * 500)).Length | Should -Be 200
    }
    It 'returns a placeholder for empty input' {
        Format-Reason '' | Should -Be '(no output)'
    }
}

Describe 'Test-AgentPresent' {
    It 'reports claude present when its CLI resolves on PATH' {
        Mock Test-CliPresent { $true } -ParameterFilter { $Stem -eq 'claude' }
        Mock Test-Path { $false }
        Test-AgentPresent 'claude' | Should -BeTrue
    }
    It 'reports agy present when only its config dir exists' {
        Mock Test-CliPresent { $false }
        Mock Test-Path { $true } -ParameterFilter { $Path -like '*\.gemini' }
        Test-AgentPresent 'agy' | Should -BeTrue
    }
    It 'reports absent when neither signal fires' {
        Mock Test-CliPresent { $false }
        Mock Test-Path { $false }
        Test-AgentPresent 'claude' | Should -BeFalse
    }
}

Describe 'Install-ClaudePlugin - vectors (golden parity vs PluginInstaller.cs)' {
    BeforeEach {
        $script:calls = New-Object System.Collections.Generic.List[object]
        Mock Test-ClaudeRunning { $false }
        # Record every CLI call; default success + read-back that echoes the installed token.
        Mock Invoke-AgentCli {
            $script:calls.Add(($CliArgs -join ' '))
            if (($CliArgs -join ' ') -eq 'plugin list') { return @{ ExitCode = 0; Output = "commonmemory@clavity-commonmemory" } }
            return @{ ExitCode = 0; Output = '' }
        }
    }
    It 'issues the exact ordered Claude vectors, verbatim from the oracle' {
        $r = Install-ClaudePlugin -PluginName 'commonmemory' -MarketplaceName 'clavity-commonmemory' -AppDir 'C:\app'
        $r.Ok | Should -BeTrue
        # HAND-AUTHORED golden list frozen from PluginInstaller.cs (NOT captured from this script's output).
        $expected = @(
            'plugin marketplace remove clavity',
            'plugin marketplace remove clavity-commonmemory',
            'plugin marketplace add C:\app --scope user',
            'plugin uninstall commonmemory',
            'plugin install commonmemory@clavity-commonmemory --scope user',
            'plugin list'
        )
        $script:calls.ToArray() | Should -Be $expected
    }
    It 'fails when marketplace add returns non-zero' {
        Mock Invoke-AgentCli {
            if (($CliArgs -join ' ') -like 'plugin marketplace add*') { return @{ ExitCode = 1; Output = 'boom' } }
            return @{ ExitCode = 0; Output = '' }
        }
        (Install-ClaudePlugin -PluginName 'x' -MarketplaceName 'm' -AppDir 'C:\a').Ok | Should -BeFalse
    }
    It 'fails read-back when the entry did not persist after an exit-0 install' {
        Mock Invoke-AgentCli {
            if (($CliArgs -join ' ') -eq 'plugin list') { return @{ ExitCode = 0; Output = 'somethingelse@mkt' } }
            return @{ ExitCode = 0; Output = '' }
        }
        $r = Install-ClaudePlugin -PluginName 'x' -MarketplaceName 'm' -AppDir 'C:\a'
        $r.Ok | Should -BeFalse
        $r.Reason | Should -Match 'read-back'
    }
    It 'refuses (fails this agent) when Claude is running' {
        Mock Test-ClaudeRunning { $true }
        (Install-ClaudePlugin -PluginName 'x' -MarketplaceName 'm' -AppDir 'C:\a').Ok | Should -BeFalse
    }
}

Describe 'Install-AgyPlugin - vectors' {
    It 'uninstall-then-install the local plugin dir; non-zero install fails' {
        $script:calls = New-Object System.Collections.Generic.List[object]
        Mock Invoke-AgentCli { $script:calls.Add(($CliArgs -join ' ')); return @{ ExitCode = 0; Output = '' } }
        $r = Install-AgyPlugin -PluginName 'commonmemory' -AppDir 'C:\app'
        $r.Ok | Should -BeTrue
        $script:calls.ToArray() | Should -Be @('plugin uninstall commonmemory', 'plugin install C:\app\plugins\commonmemory')
    }
}

Describe 'Invoke-Registration - orchestration + exit codes' {
    BeforeEach {
        Mock Test-ClaudeRunning { $false }
        Mock Install-ClaudePlugin { @{ Ok = $true;  Reason = 'installed x@m' } }
        Mock Install-AgyPlugin    { @{ Ok = $true;  Reason = 'installed x'   } }
    }
    It 'exits 0 and emits one OK line per detected agent (both present)' {
        Mock Test-AgentPresent { $true }
        $r = Invoke-Registration -Verb install -PluginName x -MarketplaceName m -AppDir C:\a -AgentSel all
        $r.ExitCode | Should -Be 0
        $r.AgentLines | Should -Be @('AGENT claude OK', 'AGENT agy OK')
    }
    It 'exits 4 with no detected agent' {
        Mock Test-AgentPresent { $false }
        (Invoke-Registration -Verb install -PluginName x -MarketplaceName m -AppDir C:\a -AgentSel all).ExitCode | Should -Be 4
    }
    It 'exits 3 when every detected agent fails' {
        Mock Test-AgentPresent { $true } -ParameterFilter { $Name -eq 'claude' }
        Mock Test-AgentPresent { $false } -ParameterFilter { $Name -eq 'agy' }
        Mock Install-ClaudePlugin { @{ Ok = $false; Reason = 'nope' } }
        $r = Invoke-Registration -Verb install -PluginName x -MarketplaceName m -AppDir C:\a -AgentSel all
        $r.ExitCode | Should -Be 3
        $r.AgentLines[0] | Should -Be 'AGENT claude FAIL nope'
    }
    It 'exits 2 on a partial failure' {
        Mock Test-AgentPresent { $true }
        Mock Install-AgyPlugin { @{ Ok = $false; Reason = 'agy boom' } }
        (Invoke-Registration -Verb install -PluginName x -MarketplaceName m -AppDir C:\a -AgentSel all).ExitCode | Should -Be 2
    }
    It 'honors -AgentSel claude (touches only claude)' {
        Mock Test-AgentPresent { $true }
        $r = Invoke-Registration -Verb install -PluginName x -MarketplaceName m -AppDir C:\a -AgentSel claude
        $r.AgentLines | Should -Be @('AGENT claude OK')
    }
    It 'uninstall is fail-open on a missing agent CLI (command-not-found is a no-op success)' {
        Mock Test-AgentPresent { $true } -ParameterFilter { $Name -eq 'claude' }
        Mock Test-AgentPresent { $false } -ParameterFilter { $Name -eq 'agy' }
        Mock Uninstall-ClaudePlugin { throw 'The term claude is not recognized' }
        (Invoke-Registration -Verb uninstall -PluginName x -MarketplaceName m -AppDir C:\a -AgentSel all).ExitCode | Should -Be 0
    }
}

Describe 'register-plugin.ps1 - exit code survives the -File wrapper (end-to-end)' {
    It 'returns 4 with no agent present (real powershell -File invocation, hermetically isolated)' {
        # GENUINE isolation: point the child's USERPROFILE at an empty temp dir AND blank its PATH so
        # Test-AgentPresent finds neither a config dir (~/.claude, ~/.gemini) nor a CLI on PATH => it detects
        # NOTHING => exit 4 and NO real agent CLI is ever invoked. This must never touch the dev box's real
        # claude/agy registrations (the prior version left USERPROFILE/PATH unset and ran live vectors on a
        # box with Claude installed). Launch powershell by FULL PATH so a blanked PATH cannot break the launch.
        $tmpHome = Join-Path $TestDrive 'home'; New-Item -ItemType Directory -Path $tmpHome -Force | Out-Null
        $script = (Resolve-Path ([System.IO.Path]::Combine($PSScriptRoot, '..', '..', 'installer', '_shared', 'register-plugin.ps1'))).Path
        $pwshExe = (Get-Command powershell -CommandType Application | Select-Object -First 1).Source
        $oldProfile = $env:USERPROFILE; $oldPath = $env:PATH
        try {
            $env:USERPROFILE = $tmpHome
            $env:PATH = ''
            $out = & $pwshExe -NoProfile -ExecutionPolicy Bypass -File $script -Install -PluginName x -MarketplaceName m -AppDir C:\a -Agent all 2>&1
            $LASTEXITCODE | Should -Be 4   # deterministic: nothing detected, no real CLI touched
        }
        finally { $env:USERPROFILE = $oldProfile; $env:PATH = $oldPath }
    }
}

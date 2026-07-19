BeforeAll {
    # Dot-source: defines functions, does NOT run main (guarded by $MyInvocation.InvocationName -eq '.').
    . (Join-Path $PSScriptRoot '..' '..' 'installer' '_shared' 'register-plugin.ps1')
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

Describe 'Install-ClaudePlugin — vectors (golden parity vs PluginInstaller.cs)' {
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

Describe 'Install-AgyPlugin — vectors' {
    It 'uninstall-then-install the local plugin dir; non-zero install fails' {
        $script:calls = New-Object System.Collections.Generic.List[object]
        Mock Invoke-AgentCli { $script:calls.Add(($CliArgs -join ' ')); return @{ ExitCode = 0; Output = '' } }
        $r = Install-AgyPlugin -PluginName 'commonmemory' -AppDir 'C:\app'
        $r.Ok | Should -BeTrue
        $script:calls.ToArray() | Should -Be @('plugin uninstall commonmemory', 'plugin install C:\app\plugins\commonmemory')
    }
}

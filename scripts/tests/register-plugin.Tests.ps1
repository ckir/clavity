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

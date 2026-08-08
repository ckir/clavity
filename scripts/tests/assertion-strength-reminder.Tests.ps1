# scripts/tests/assertion-strength-reminder.Tests.ps1
BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Hook     = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh'
    $script:Mirror   = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks/assertion-strength-reminder.sh'
}

Describe 'assertion-strength-reminder.sh' {
    It 'is registered in the justfile fast suite' {
        $jf = Get-Content -Raw (Join-Path $script:RepoRoot 'justfile')
        $jf.Contains("scripts/tests/assertion-strength-reminder.Tests.ps1") |
            Should -BeTrue -Because 'registration is an explicit list, not a glob'
    }
}

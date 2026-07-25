Describe 'agy-after-reminder.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-after-reminder.sh'

        # A PATH containing bash+coreutils but NOT jq, to exercise the jq-missing branch. Point at the Git
        # usr/bin (bash, grep, printf) only; jq is not shipped there.
        $bashDir = Split-Path -Parent (Get-GitBashOrThrow)                 # ...\Git\bin
        $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')  # ...\Git\usr\bin

        function New-WritePayload { param([string]$FilePath, [string]$Cwd = '.')
            @{ tool_input = @{ file_path = $FilePath }; cwd = $Cwd } | ConvertTo-Json -Compress
        }
    }

    It 'fires the AGY-AFTER reminder on a spec write' {
        $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-WritePayload 'docs/superpowers/specs/x.md')
        $r.StdOut | Should -Match 'AGY-AFTER'
        $r.ExitCode | Should -Be 0
    }
    It 'fires on a plan write' {
        $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-WritePayload 'docs/superpowers/plans/y.md')
        $r.StdOut | Should -Match 'AGY-AFTER'
    }
    It 'is silent on a non-artifact path' {
        $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-WritePayload 'src/main.rs')
        $r.StdOut | Should -BeNullOrEmpty
    }
    It 'is suppressed by .no-agy in cwd' {
        $repo = New-TempRepo
        try {
            New-Item -ItemType File -Path (Join-Path $repo '.no-agy') -Force | Out-Null
            $cwd = ($repo -replace '\\','/')
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-WritePayload 'docs/superpowers/specs/x.md' $cwd)
            $r.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'is suppressed by a global $HOME/.claude/.no-agy' {
        $home2 = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-h-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $home2 '.claude') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $home2 '.claude/.no-agy') -Force | Out-Null
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-WritePayload 'docs/superpowers/specs/x.md') -Env @{ HOME = $home2 }
            $r.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $home2 -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'emits a LOUD jq-missing line on a spec path when jq is absent' {
        $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-WritePayload 'docs\superpowers\specs\z.md') -Env @{ PATH = $script:NoJqPath }
        $r.StdOut | Should -Match 'guard inactive: missing jq'
    }
    It 'is silent (no jq-missing line) on a non-artifact path when jq is absent' {
        $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-WritePayload 'src/main.rs') -Env @{ PATH = $script:NoJqPath }
        $r.StdOut | Should -BeNullOrEmpty
    }
    It 'ships as pure ASCII' {
        ($([IO.File]::ReadAllBytes($script:Hook)) | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}

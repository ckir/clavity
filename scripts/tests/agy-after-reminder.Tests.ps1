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

        # As above but WITHOUT the repo-wide `-replace '\\','/'` on cwd: the raw backslashed shape the
        # real payload carries. '\\' as a regex matches one backslash; '\\' as a .NET replacement is two
        # literal characters, so this DOUBLES them, which is what a JSON string needs.
        function New-RawWritePayload { param([string]$FilePath, [string]$Cwd)
            '{"tool_input":{"file_path":"' + $FilePath + '"},"cwd":"' + ($Cwd -replace '\\', '\\') + '","hook_event_name":"PostToolUse"}'
        }

        function New-CleanHomeAR {
            $h = Join-Path ([IO.Path]::GetTempPath()) ("ar-home-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $h '.claude') -Force | Out-Null
            return $h
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
    # --- .no-agy at the REPO ROOT, session cwd in a SUBDIRECTORY ---------------------------------
    # Every test above forward-slashes cwd, which is the repo-wide convention and is exactly why this
    # bug survived: a POSIX-shaped path cannot exercise the Windows walk. These four hand-build the RAW
    # backslashed shape the real payload has, and each silence test is paired with a positive control.
    # The CONTROL is the load-bearing half - measured on a sibling hook, a broken walk can produce
    # silence that is indistinguishable from a working kill-switch.
    It 'is SILENT when .no-agy is at the repo root and cwd is a subdirectory' {
        $repo = New-TempRepo; $h = New-CleanHomeAR
        try {
            $sub = Join-Path $repo 'src'
            New-Item -ItemType Directory -Path $sub -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $repo '.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-RawWritePayload 'docs/superpowers/specs/x.md' $sub) -Env @{ HOME = $h }
            $r.StdOut | Should -BeNullOrEmpty -Because 'an opt-out at the repo root must suppress this hook from a subdirectory'
        } finally { Remove-Item $repo,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'DOES fire from that same subdirectory when .no-agy is absent (positive control)' {
        $repo = New-TempRepo; $h = New-CleanHomeAR
        try {
            $sub = Join-Path $repo 'src'
            New-Item -ItemType Directory -Path $sub -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-RawWritePayload 'docs/superpowers/specs/x.md' $sub) -Env @{ HOME = $h }
            $r.StdOut | Should -Match 'AGY-AFTER' -Because 'without the opt-out it must still fire - otherwise the silence test proves nothing'
        } finally { Remove-Item $repo,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'honours a root .no-agy from a subdirectory on the DEGRADED (no jq) path too' {
        # The degraded branch used to test "./.no-agy" - the PROCESS cwd, not the session's workspace -
        # so it could not honour any opt-out at all when the two differ. Nothing covered it.
        $repo = New-TempRepo; $h = New-CleanHomeAR
        try {
            $sub = Join-Path $repo 'src'
            New-Item -ItemType Directory -Path $sub -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $repo '.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-RawWritePayload 'docs/superpowers/specs/x.md' $sub) -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $r.StdOut | Should -BeNullOrEmpty -Because 'the degraded path must honour the same root opt-out as the jq path'
        } finally { Remove-Item $repo,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'DOES emit the jq-missing line from that subdirectory without .no-agy (degraded positive control)' {
        $repo = New-TempRepo; $h = New-CleanHomeAR
        try {
            $sub = Join-Path $repo 'src'
            New-Item -ItemType Directory -Path $sub -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-RawWritePayload 'docs/superpowers/specs/x.md' $sub) -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $r.StdOut | Should -Match 'guard inactive: missing jq' -Because 'without the opt-out the degraded path must still announce itself'
        } finally { Remove-Item $repo,$h -Recurse -Force -ErrorAction SilentlyContinue }
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
    It 'does NOT carry the cost clause (its trigger is not durable)' {
        $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-WritePayload 'docs/superpowers/specs/x.md')
        $r.StdOut | Should -Not -Match 'COST:'
        $r.StdOut | Should -Not -Match 'SESSION POSTURE:'
    }
    It 'is byte-identical to the clavity-classic mirror' {
        $classic = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'clavity-classic/plugin/hooks/agy-after-reminder.sh'
        (Get-FileHash $script:Hook).Hash | Should -Be (Get-FileHash $classic).Hash
    }
}

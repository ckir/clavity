Describe 'agy-liveness-check.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-liveness-check.sh'
        $bashDir = Split-Path -Parent (Get-GitBashOrThrow)
        $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')

        # Build a fixture config-dir (the CLAUDE_CONFIG_DIR the hook reads as the USER-scope settings home)
        # with an enabledPlugins map. $Enabled = $true|$false|$null (no key) | 'nofile' (no settings.json).
        function New-ConfigFixture { param($Enabled)
            $d = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-cfg-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            if ('nofile' -ne $Enabled) {
                $ep = @{}
                if ($Enabled -eq $true)  { $ep['superpowers@superpowers-marketplace'] = $true }
                if ($Enabled -eq $false) { $ep['superpowers@superpowers-marketplace'] = $false }
                @{ enabledPlugins = $ep } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $d 'settings.json') -Encoding ascii
            }
            return $d
        }
        # An empty HOME fixture so the hook's `$HOME/.claude/.no-agy` global check never hits the host.
        function New-CleanHome {
            $h = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-home-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $h '.claude') -Force | Out-Null
            return $h
        }
        function Payload { param([string]$Cwd = '.') @{ cwd = $Cwd; source = 'startup' } | ConvertTo-Json -Compress }
    }

    It 'is SILENT (exit 0, no stderr) when superpowers is enabled' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 0
            $r.StdErr   | Should -BeNullOrEmpty
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'ADVISES (stderr + exit 2) when superpowers is disabled' {
        $cfg = New-ConfigFixture $false; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'superpowers not detected'
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'ADVISES when no settings files exist at all' {
        $cfg = New-ConfigFixture 'nofile'; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 2
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'honors the settings hierarchy: project-local disable overrides user enable -> ADVISES' {
        $cfg = New-ConfigFixture $true          # user scope: enabled
        $proj = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-proj-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $proj '.claude') -Force | Out-Null
        @{ enabledPlugins = @{ 'superpowers@superpowers-marketplace' = $false } } | ConvertTo-Json -Depth 5 |
            Set-Content (Join-Path $proj '.claude/settings.local.json') -Encoding ascii
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $proj }
            $r.ExitCode | Should -Be 2
        } finally { Remove-Item $cfg,$proj,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'honors the hierarchy: project-local enable overrides user disable -> SILENT' {
        $cfg = New-ConfigFixture $false         # user scope: disabled
        $proj = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-proj-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $proj '.claude') -Force | Out-Null
        @{ enabledPlugins = @{ 'superpowers@superpowers-marketplace' = $true } } | ConvertTo-Json -Depth 5 |
            Set-Content (Join-Path $proj '.claude/settings.local.json') -Encoding ascii
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $proj }
            $r.ExitCode | Should -Be 0
        } finally { Remove-Item $cfg,$proj,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'ADVISES on a corrupt (unreadable) settings.json (never fail-open)' {
        $cfg = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-corrupt-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $cfg -Force | Out-Null
        '{ this is not json' | Set-Content (Join-Path $cfg 'settings.json') -Encoding ascii
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 2
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'announces .no-agy in cwd (exit 2) and does NOT also emit the superpowers/jq notice' {
        $repo = New-TempRepo; $cfg = New-ConfigFixture $false; $h = New-CleanHome  # superpowers disabled too
        try {
            New-Item -ItemType File -Path (Join-Path $repo '.no-agy') -Force | Out-Null
            $cwd = ($repo -replace '\\','/')
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $cwd) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'suppressed by .no-agy'
            $r.StdErr   | Should -Not -Match 'superpowers not detected'   # no triple-spam
            ($r.StdErr -split "`n").Count | Should -Be 1
        } finally { Remove-Item $repo,$cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'announces a global $HOME/.claude/.no-agy' {
        $cfg = New-ConfigFixture $true
        $h = New-CleanHome
        New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'suppressed by .no-agy'
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'emits ONE jq-missing warning (exit 2) when jq is absent' {
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'missing jq'
            ($r.StdErr -split "`n").Count | Should -Be 1
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'ships as pure ASCII' {
        ($([IO.File]::ReadAllBytes($script:Hook)) | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}

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

        # Register ONE personal hook by NAME at user scope, run the hook, return the result. Used by the
        # token-matching tests so the only thing varying between them is the registered filename.
        function Invoke-WithPersonalHook { param([string]$HookName, $Cfg, $HomeDir)
            @{ enabledPlugins = @{ 'superpowers@superpowers-marketplace' = $true }
               hooks = @{ SessionStart = @( @{ hooks = @( @{ type='command'; command="bash `"~/.claude/hooks/$HookName`"" } ) } ) }
            } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $Cfg 'settings.json') -Encoding ascii
            return Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $Cfg; HOME = $HomeDir; CLAUDE_PROJECT_DIR = $Cfg }
        }
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

    It 'REPORTS a personal registration of a shipped hook name (user scope)' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        try {
            $s = Join-Path $cfg 'settings.json'
            @{ enabledPlugins = @{ 'superpowers@superpowers-marketplace' = $true }
               hooks = @{ SessionStart = @( @{ hooks = @( @{ type='command'; command='bash "~/.claude/hooks/agy-liveness-check.sh"' } ) } ) }
            } | ConvertTo-Json -Depth 8 | Set-Content $s -Encoding ascii
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'agy-liveness-check'
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'STILL reports ownership when .no-agy is present (constraint 5)' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        try {
            $s = Join-Path $cfg 'settings.json'
            @{ enabledPlugins = @{ 'superpowers@superpowers-marketplace' = $true }
               hooks = @{ SessionStart = @( @{ hooks = @( @{ type='command'; command='bash "~/.claude/hooks/agy-liveness-check.sh"' } ) } ) }
            } | ConvertTo-Json -Depth 8 | Set-Content $s -Encoding ascii
            New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'suppressed by .no-agy'
            $r.StdErr   | Should -Match 'agy-liveness-check'
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT about ownership when no personal registration exists' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 0
            $r.StdErr   | Should -BeNullOrEmpty
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports the unreadable settings file BUT continues the sweep' {
        # ORDER IS THE WHOLE POINT. The sweep runs user -> project -> local, so the CORRUPT file must sit
        # at USER scope and the collision AFTER it at PROJECT scope. An earlier version of this test had
        # them the other way round: the collision was found on iteration 1 and the corrupt file was last,
        # so `continue` and `break` behaved identically and the mutation left the suite green. A guard
        # whose removal leaves the suite green is not a guard.
        $cfg  = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-cfg-"  + [Guid]::NewGuid().ToString('N'))
        $proj = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-proj-" + [Guid]::NewGuid().ToString('N'))
        $h = New-CleanHome
        try {
            New-Item -ItemType Directory -Path $cfg -Force | Out-Null
            '{ "hooks": { ,,, ' | Set-Content (Join-Path $cfg 'settings.json') -Encoding ascii
            New-Item -ItemType Directory -Path (Join-Path $proj '.claude') -Force | Out-Null
            @{ enabledPlugins = @{ 'superpowers@superpowers-marketplace' = $true }
               hooks = @{ SessionStart = @( @{ hooks = @( @{ type='command'; command='bash "~/.claude/hooks/agy-liveness-check.sh"' } ) } ) }
            } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $proj '.claude/settings.json') -Encoding ascii
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $proj }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'settings unreadable'
            $r.StdErr   | Should -Match 'agy-liveness-check'
        } finally { Remove-Item $cfg,$h,$proj -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'stays silent when the settings file has no hooks node at all' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.StdErr | Should -Not -Match 'schema unrecognised'
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'REPORTS a duplicate registered at PROJECT scope' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        $proj = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-proj-" + [Guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $proj '.claude') -Force | Out-Null
            @{ hooks = @{ SessionStart = @( @{ hooks = @( @{ type='command'; command='bash "~/.claude/hooks/agy-seam-inject.sh"' } ) } ) } } |
                ConvertTo-Json -Depth 8 | Set-Content (Join-Path $proj '.claude/settings.json') -Encoding ascii
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $proj }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'agy-seam-inject'
        } finally { Remove-Item $cfg,$h,$proj -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'REPORTS a duplicate registered in settings.local.json' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        $proj = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-proj-" + [Guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $proj '.claude') -Force | Out-Null
            @{ hooks = @{ SessionStart = @( @{ hooks = @( @{ type='command'; command='bash "~/.claude/hooks/agy-after-reminder.sh"' } ) } ) } } |
                ConvertTo-Json -Depth 8 | Set-Content (Join-Path $proj '.claude/settings.local.json') -Encoding ascii
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $proj }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'agy-after-reminder'
        } finally { Remove-Item $cfg,$h,$proj -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'finds a PROJECT-scope duplicate when cwd is a SUBDIRECTORY' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        $proj = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-proj-" + [Guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $proj '.claude') -Force | Out-Null
            $sub = Join-Path $proj 'src/deep'; New-Item -ItemType Directory -Path $sub -Force | Out-Null
            @{ hooks = @{ SessionStart = @( @{ hooks = @( @{ type='command'; command='bash "~/.claude/hooks/agy-seam-inject.sh"' } ) } ) } } |
                ConvertTo-Json -Depth 8 | Set-Content (Join-Path $proj '.claude/settings.json') -Encoding ascii
            # cwd is the SUBDIR; CLAUDE_PROJECT_DIR still names the root, which is why the hook finds it.
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload -Cwd $sub) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $proj }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'agy-seam-inject'
        } finally { Remove-Item $cfg,$h,$proj -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'says SCHEMA UNRECOGNISED (not "unreadable") when .hooks parses but is the wrong shape' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        $proj = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-proj-" + [Guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $proj '.claude') -Force | Out-Null
            # Valid JSON, but .hooks is a STRING where the check expects an object of event arrays.
            '{ "hooks": "not-an-object" }' | Set-Content (Join-Path $proj '.claude/settings.json') -Encoding ascii
            # A real collision placed AFTER it in the user->project->local sweep. This is what makes the
            # schema branch's `continue` load-bearing: with a `break` the sweep stops at the bad-shape
            # project file and never reaches this, so the duplicate goes unreported.
            @{ hooks = @{ SessionStart = @( @{ hooks = @( @{ type='command'; command='bash "~/.claude/hooks/agy-seam-inject.sh"' } ) } ) } } |
                ConvertTo-Json -Depth 8 | Set-Content (Join-Path $proj '.claude/settings.local.json') -Encoding ascii
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $proj }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'schema unrecognised'
            $r.StdErr   | Should -Not -Match 'settings unreadable'
            $r.StdErr   | Should -Match 'agy-seam-inject'
        } finally { Remove-Item $cfg,$h,$proj -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'says SHIPPED-HOOK LIST UNREADABLE when its own hooks.json will not parse' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        $fake = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-plug-" + [Guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fake -Force | Out-Null
            Copy-Item $script:Hook (Join-Path $fake 'agy-liveness-check.sh')
            '{ "hooks": { ,,,' | Set-Content (Join-Path $fake 'hooks.json') -Encoding ascii
            $r = Invoke-BashHook -HookPath (Join-Path $fake 'agy-liveness-check.sh') -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'shipped-hook list unreadable'
        } finally { Remove-Item $cfg,$h,$fake -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'derives the shipped list at RUNTIME - a hook added to hooks.json is picked up with no test edit' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        $fake = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-plug-" + [Guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fake -Force | Out-Null
            Copy-Item $script:Hook (Join-Path $fake 'agy-liveness-check.sh')
            # A hook name that appears NOWHERE in the test file's expectations or the real plugin.
            @{ hooks = @{ SessionStart = @( @{ hooks = @( @{ type='command'; command='bash "${CLAUDE_PLUGIN_ROOT}/hooks/agy-invented-for-this-test.sh"' } ) } ) } } |
                ConvertTo-Json -Depth 8 | Set-Content (Join-Path $fake 'hooks.json') -Encoding ascii
            $s = Join-Path $cfg 'settings.json'
            @{ enabledPlugins = @{ 'superpowers@superpowers-marketplace' = $true }
               hooks = @{ SessionStart = @( @{ hooks = @( @{ type='command'; command='bash "~/.claude/hooks/agy-invented-for-this-test.sh"' } ) } ) }
            } | ConvertTo-Json -Depth 8 | Set-Content $s -Encoding ascii
            $r = Invoke-BashHook -HookPath (Join-Path $fake 'agy-liveness-check.sh') -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'agy-invented-for-this-test'
        } finally { Remove-Item $cfg,$h,$fake -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # --- Token matching, not substring matching (capstone R1-F4). The check compares whole script-name
    # tokens case-insensitively. Substring matching over-fired on any longer name CONTAINING a shipped
    # name and under-fired on a case-differing name. The first two pin the false-positive edges; the
    # third pins the false-negative that a case-insensitive filesystem would otherwise hide.

    It 'is SILENT about a personal hook whose name is UNRELATED to any shipped one' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        try {
            $r = Invoke-WithPersonalHook 'my-custom-hook.sh' $cfg $h
            $r.ExitCode | Should -Be 0
            $r.StdErr   | Should -BeNullOrEmpty
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT flag a rename whose name merely CONTAINS a shipped name' {
        # The README tells operators to rename-and-trim rather than delete. Substring matching flagged
        # my-agy-seam-inject.sh as a collision, i.e. it punished the documented escape hatch.
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        try {
            $r = Invoke-WithPersonalHook 'my-agy-seam-inject.sh' $cfg $h
            $r.ExitCode | Should -Be 0
            $r.StdErr   | Should -BeNullOrEmpty
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'REPORTS a collision that differs only in CASE' {
        # Windows and macOS resolve AGY-SEAM-INJECT.SH and agy-seam-inject.sh to the SAME file, so the
        # host double-fires. A case-sensitive match stayed silent on the operator's own platform.
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        try {
            $r = Invoke-WithPersonalHook 'AGY-SEAM-INJECT.SH' $cfg $h
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'agy-seam-inject\.sh is shipped by this plugin'
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'BashHookHelpers (harness validation)' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        # A throwaway probe hook that echoes the env it sees + writes to stderr and exits 2.
        $script:probeDir = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-probe-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:probeDir -Force | Out-Null
        $script:probe = Join-Path $script:probeDir 'probe.sh'
        @(
            '#!/usr/bin/env bash',
            'echo "CCD=$CLAUDE_CONFIG_DIR"',
            'if [ -f "$CLAUDE_CONFIG_DIR/marker" ]; then echo "CCD_MARKER_FOUND"; else echo "CCD_MARKER_MISSING"; fi',
            'if [ -f "$HOME/.claude/marker" ]; then echo "HOME_MARKER_FOUND"; else echo "HOME_MARKER_MISSING"; fi',
            'printf ''%s\n'' "on-stderr" >&2',
            'exit 2'
        ) -join "`n" | Set-Content -LiteralPath $script:probe -Encoding ascii -NoNewline
    }
    AfterAll { Remove-Item -LiteralPath $script:probeDir -Recurse -Force -ErrorAction SilentlyContinue }

    It 'pins a non-WSL Git Bash' {
        (Get-GitBashOrThrow) | Should -Not -Match '\\System32\\bash\.exe$'
    }
    It 'captures stderr and exit code 2 separately from stdout' {
        $r = Invoke-BashHook -HookPath $script:probe
        $r.ExitCode | Should -Be 2
        $r.StdErr   | Should -Match 'on-stderr'
    }
    It 'resolves an absolute CLAUDE_CONFIG_DIR to a real file inside the hook' {
        # NOTE: env vars (unlike CLI args) are NOT MSYS auto-POSIX-converted -- CLAUDE_CONFIG_DIR arrives
        # in the hook in its raw Windows form (C:\...). What the SP-D hooks actually depend on is that the
        # env-passed config dir RESOLVES on the filesystem (`[ -f "$CLAUDE_CONFIG_DIR/settings.json" ]` +
        # jq reading it), which Cygwin/Git-Bash handles transparently for Windows-form paths. Assert that
        # real guarantee (filesystem resolution), NOT a path-string format.
        $cfg2 = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-cfg-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType File -Path (Join-Path $cfg2 'marker') -Force | Out-Null
        try {
            $r = Invoke-BashHook -HookPath $script:probe -Env @{ CLAUDE_CONFIG_DIR = $cfg2 }
            $r.StdOut | Should -Match 'CCD_MARKER_FOUND'
        } finally { Remove-Item -LiteralPath $cfg2 -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'isolates HOME to an absolute fixture dir (MSYS passthrough)' {
        $home2 = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-home-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $home2 '.claude') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $home2 '.claude/marker') -Force | Out-Null
        try {
            $r = Invoke-BashHook -HookPath $script:probe -Env @{ HOME = $home2 }
            $r.StdOut | Should -Match 'HOME_MARKER_FOUND'
        } finally { Remove-Item -LiteralPath $home2 -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'forwards positional arguments to the hook' {
        $probe = Join-Path $TestDrive 'echo-args.sh'
        Set-Content -LiteralPath $probe -Value "#!/usr/bin/env bash`ncat >/dev/null`nprintf '%s' `"`$1`"" -NoNewline
        $r = Invoke-BashHook -HookPath $probe -Payload '{}' -Arguments @('UserPromptSubmit')
        $r.Stdout | Should -BeExactly 'UserPromptSubmit'
    }

    It 'passes no argument when -Arguments is omitted' {
        # CONTROL: guards the default path every EXISTING caller uses. If -Arguments defaulted to something
        # non-empty, every hook in the repo would start receiving a spurious $1.
        $probe = Join-Path $TestDrive 'echo-args.sh'
        Set-Content -LiteralPath $probe -Value "#!/usr/bin/env bash`ncat >/dev/null`nprintf '[%s]' `"`$1`"" -NoNewline
        $r = Invoke-BashHook -HookPath $probe -Payload '{}'
        $r.Stdout | Should -BeExactly '[]'
    }
}

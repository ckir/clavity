Describe 'check-seed-artifacts-synced.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Script   = Join-Path $script:RepoRoot 'scripts/check-seed-artifacts-synced.sh'
        # ...\Git\usr\bin carries diff/sed but NOT jq (verified: the hook jq-missing tests rely on this),
        # so pointing PATH here reproduces "jq absent" deterministically. Git Bash is invoked by ABSOLUTE
        # path inside Invoke-BashHook, so bash itself need not be on this restricted PATH.
        $bashDir = Split-Path -Parent (Get-GitBashOrThrow)                       # ...\Git\bin
        $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')   # ...\Git\usr\bin

        # The script uses repo-root-relative paths, so the bash child must run with cwd = repo root.
        # Native processes launched from pwsh inherit [Environment]::CurrentDirectory (NOT the PSDrive
        # location), so set that around each call.
        function Invoke-SeedSync {
            param([hashtable]$Env = @{})
            $savedCwd = [Environment]::CurrentDirectory
            [Environment]::CurrentDirectory = $script:RepoRoot
            try { return (Invoke-BashHook -HookPath $script:Script -Env $Env) }
            finally { [Environment]::CurrentDirectory = $savedCwd }
        }
    }

    It 'passes (exit 0, reports in sync) on the real repo when jq is available' {
        $r = Invoke-SeedSync
        $r.ExitCode | Should -Be 0
        $r.StdOut   | Should -Match 'in sync'
    }

    It 'FAILS LOUD (exit 2) instead of silently passing when jq is absent' {
        # Regression guard: previously `diff <(jq ...) <(jq ...)` swallowed jq's "command not found" (a
        # process substitution's exit code does not propagate under set -e), so the guard silently exited 0
        # while performing NO hooks.json drift check. The top-of-script jq presence gate must fail loud.
        $r = Invoke-SeedSync -Env @{ PATH = $script:NoJqPath }
        $r.ExitCode | Should -Be 2
        $r.StdErr   | Should -Match 'jq is required'
    }
}

Describe 'agy-test-audit-reminder.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh'

        $bashDir = Split-Path -Parent (Get-GitBashOrThrow)                       # ...\Git\bin
        $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')   # ...\Git\usr\bin

        # A repo whose HEAD commit touched a code file, with capstone.head==HEAD and no audit marker:
        # the canonical FIRE state. Returns the repo dir (Windows path).
        function New-FiredRepo {
            param([string]$CodeFile = 'src/thing.cs', [switch]$DocsOnly)
            $dir = New-TempRepo
            $rel = if ($DocsOnly) { 'docs/notes.md' } else { $CodeFile }
            $full = Join-Path $dir $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            Set-Content -LiteralPath $full -Value 'x' -Encoding ascii
            & git -C $dir add -A
            & git -C $dir -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= commit -qm work
            $head = (& git -C $dir rev-parse HEAD).Trim()
            New-Item -ItemType Directory -Path (Join-Path $dir '.clavity/agy-marks') -Force | Out-Null
            return [pscustomobject]@{ Dir = $dir; Head = $head }
        }
        function Set-Marker { param($Dir, $Name, $Sha)
            Set-Content -LiteralPath (Join-Path $Dir ".clavity/agy-marks/$Name.head") -Value $Sha -NoNewline -Encoding ascii
        }
        # A repo whose gate() takes the PRIMARY `git diff "$base"..HEAD` path: `main` stays at the init
        # commit while HEAD advances on a feature branch with a code file, so merge-base HEAD main != HEAD.
        function New-DiffPathRepo {
            $dir = New-TempRepo                                # one 'init' commit on the default branch
            & git -C $dir branch -f main HEAD                  # ensure a 'main' ref pinned at init
            & git -C $dir checkout -qb feature
            $full = Join-Path $dir 'src/thing.cs'
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            Set-Content -LiteralPath $full -Value 'x' -Encoding ascii
            & git -C $dir add -A
            & git -C $dir -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= commit -qm work
            $head = (& git -C $dir rev-parse HEAD).Trim()
            New-Item -ItemType Directory -Path (Join-Path $dir '.clavity/agy-marks') -Force | Out-Null
            return [pscustomobject]@{ Dir = $dir; Head = $head }
        }
        function New-AuditPayload { param([string]$Cwd)
            @{ tool_name = 'Bash'; tool_input = @{ command = 'git commit' }; cwd = $Cwd } | ConvertTo-Json -Compress
        }
        $script:Cwd = { param($d) ($d -replace '\\','/') }
    }

    It 'FIRES the audit nudge when capstone.head==HEAD, no audit marker, code changed' {
        $r = New-FiredRepo
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Head
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut  | Should -Match 'AGY-TEST-AUDIT'
            $out.ExitCode | Should -Be 0
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'is SILENT when the capstone marker is absent (capstone not run/green)' {
        $r = New-FiredRepo
        try {
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'is SILENT when the capstone marker is STALE (!= HEAD)' {
        $r = New-FiredRepo
        try {
            Set-Marker $r.Dir 'agy-capstone' 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'is SILENT when the audit already ran at this HEAD (audit.head==HEAD)' {
        $r = New-FiredRepo
        try {
            Set-Marker $r.Dir 'agy-capstone'   $r.Head
            Set-Marker $r.Dir 'agy-test-audit' $r.Head
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'is SILENT on a docs-only reviewed range (no code/test paths changed)' {
        $r = New-FiredRepo -DocsOnly
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Head
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'is suppressed by .no-agy in cwd even when it would otherwise fire' {
        $r = New-FiredRepo
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Head
            New-Item -ItemType File -Path (Join-Path $r.Dir '.no-agy') -Force | Out-Null
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'no-jq: is suppressed by .no-agy in the PAYLOAD cwd (not the process cwd)' {
        $r = New-FiredRepo
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Head
            New-Item -ItemType File -Path (Join-Path $r.Dir '.no-agy') -Force | Out-Null
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir)) -Env @{ PATH = $script:NoJqPath }
            $out.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'FIRES via the primary diff-base path (main pinned behind HEAD, exercising diff base..HEAD)' {
        $r = New-DiffPathRepo
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Head
            $base = (& git -C $r.Dir merge-base HEAD main).Trim()
            $base | Should -Not -Be $r.Head          # sanity: base is behind HEAD -> primary path, not fallback
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut  | Should -Match 'AGY-TEST-AUDIT'
            $out.ExitCode | Should -Be 0
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'emits a LOUD jq-missing line when it would fire but jq is absent' {
        $r = New-FiredRepo
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Head
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir)) -Env @{ PATH = $script:NoJqPath }
            $out.StdOut | Should -Match 'guard inactive: missing jq'
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'ships as pure ASCII' {
        ($([IO.File]::ReadAllBytes($script:Hook)) | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
    It 'is byte-identical to the clavity-classic mirror' {
        $classic = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'clavity-classic/plugin/hooks/agy-test-audit-reminder.sh'
        (Get-FileHash $script:Hook).Hash | Should -Be (Get-FileHash $classic).Hash
    }
}

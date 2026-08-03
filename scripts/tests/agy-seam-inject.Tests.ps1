# Focused synthetic-payload smoke for the SP-C auto-fire hook (agy-seam-inject.sh).
# Pipes a synthetic PreToolUse(Skill) payload to the shipped bash hook and asserts its
# behaviour: seam match -> the right discipline directive (once); debounce (marker==HEAD)
# -> silent; non-seam -> silent; .no-agy -> suppressed; the hook file is pure ASCII.
# The comprehensive hook-activation matrix (incl. the jq-missing loud line) is SP-D.

BeforeAll {
    . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Hook = Join-Path $RepoRoot 'clavity-dotnet/plugin/hooks/agy-seam-inject.sh'
    $bashDir = Split-Path -Parent (Get-GitBashOrThrow)
    $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')
    # An empty HOME fixture so a real global ~/.claude/.no-agy on the dev box can't suppress the hook mid-test.
    $script:CleanHome = Join-Path ([IO.Path]::GetTempPath()) ("sp-c-home-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $script:CleanHome '.claude') -Force | Out-Null

    function Invoke-Hook { param([string]$Skill, [string]$Cwd = '.')
        $payload = @{ tool_input = @{ skill = $Skill }; cwd = $Cwd } | ConvertTo-Json -Compress
        (Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env @{ HOME = $script:CleanHome }).StdOut
    }
}
AfterAll { Remove-Item -LiteralPath $script:CleanHome -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'agy-seam-inject.sh' {
    It 'injects the AGY-FIRST directive on a brainstorm seam' {
        # Clean temp repo: no marker + a resolvable HEAD -> must inject. (Passing cwd='.'
        # would read the REAL repo's .clavity markers/HEAD and could spuriously debounce.)
        $repo = New-TempRepo
        try {
            $cwd = ($repo -replace '\\','/')
            $out = Invoke-Hook -Skill 'superpowers:brainstorming' -Cwd $cwd
            $out | Should -Match 'AGY-FIRST auto-fire'
            $out | Should -Match 'agy-first'   # points at the discipline skill by name
            # Fired exactly once: a single JSON object line.
            (($out -split "`n") | Where-Object { $_ -match 'hookSpecificOutput' }).Count | Should -Be 1
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'carries the SESSION POSTURE line on the brainstorm seam' {
        $repo = New-TempRepo
        try {
            $cwd = ($repo -replace '\\','/')
            $out = Invoke-Hook -Skill 'superpowers:brainstorming' -Cwd $cwd
            $out | Should -Match 'SESSION POSTURE:'
            $out | Should -Match 'commit first'
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'injects the AGY-CAPSTONE directive on a finishing-a-development-branch seam' {
        $repo = New-TempRepo
        try {
            $cwd = ($repo -replace '\\','/')
            $out = Invoke-Hook -Skill 'superpowers:finishing-a-development-branch' -Cwd $cwd
            $out | Should -Match 'AGY-CAPSTONE auto-fire'
            $out | Should -Match 'agy-capstone'
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'carries the COST clause on the capstone seam' {
        $repo = New-TempRepo
        try {
            $cwd = ($repo -replace '\\','/')
            $out = Invoke-Hook -Skill 'superpowers:finishing-a-development-branch' -Cwd $cwd
            $out | Should -Match 'COST:'
            $out | Should -Match 'never WHETHER'
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT put the COST clause on the brainstorm seam' {
        $repo = New-TempRepo
        try {
            $cwd = ($repo -replace '\\','/')
            $out = Invoke-Hook -Skill 'superpowers:brainstorming' -Cwd $cwd
            $out | Should -Not -Match 'COST:'
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is silent on a non-seam skill' {
        (Invoke-Hook -Skill 'superpowers:writing-plans') | Should -BeNullOrEmpty
    }

    It 'is suppressed by a .no-agy kill-switch in cwd' {
        $repo = New-TempRepo
        try {
            New-Item -ItemType File -Path (Join-Path $repo '.no-agy') -Force | Out-Null
            $cwd = ($repo -replace '\\','/')
            (Invoke-Hook -Skill 'superpowers:brainstorming' -Cwd $cwd) | Should -BeNullOrEmpty
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'debounces when the marker already equals HEAD' {
        $repo = New-TempRepo
        try {
            $head = (& git -C $repo rev-parse HEAD).Trim()
            $mdir = Join-Path $repo '.clavity/agy-marks'
            New-Item -ItemType Directory -Path $mdir -Force | Out-Null
            Set-Content -Path (Join-Path $mdir 'agy-capstone.head') -Value $head -NoNewline
            $cwd = ($repo -replace '\\','/')
            (Invoke-Hook -Skill 'superpowers:finishing-a-development-branch' -Cwd $cwd) | Should -BeNullOrEmpty
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'still injects when the marker is stale (content != HEAD)' {
        $repo = New-TempRepo
        try {
            $mdir = Join-Path $repo '.clavity/agy-marks'
            New-Item -ItemType Directory -Path $mdir -Force | Out-Null
            Set-Content -Path (Join-Path $mdir 'agy-capstone.head') -Value 'deadbeef-not-head' -NoNewline
            $cwd = ($repo -replace '\\','/')
            (Invoke-Hook -Skill 'superpowers:finishing-a-development-branch' -Cwd $cwd) | Should -Match 'AGY-CAPSTONE auto-fire'
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'emits the LOUD jq-missing line on a seam match when jq is absent' {
        $repo = New-TempRepo
        try {
            $payload = @{ tool_input = @{ skill = 'superpowers:brainstorming' }; cwd = ($repo -replace '\\','/') } | ConvertTo-Json -Compress
            $r = Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env @{ PATH = $script:NoJqPath; HOME = $script:CleanHome }
            $r.StdOut | Should -Match 'guard inactive: missing jq'
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'is silent (no jq-missing line) on a NON-seam skill when jq is absent' {
        $payload = @{ tool_input = @{ skill = 'superpowers:writing-plans' }; cwd = '.' } | ConvertTo-Json -Compress
        $r = Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env @{ PATH = $script:NoJqPath; HOME = $script:CleanHome }
        $r.StdOut | Should -BeNullOrEmpty
    }
    It 'ships as pure ASCII (project mojibake discipline)' {
        $bytes = [IO.File]::ReadAllBytes($script:Hook)
        ($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }

    It 'injects the ANOMALY-CAPTURE dispatch directive on a subagent-driven-development seam' {
        $out = Invoke-Hook 'superpowers:subagent-driven-development'
        $out | Should -Match 'ANOMALY-CAPTURE'
        $out | Should -Match 'open-issues'
        $out | Should -Match 'local-anomalies'
    }

    It 'injects the same directive on an executing-plans seam' {
        $out = Invoke-Hook 'superpowers:executing-plans'
        $out | Should -Match 'ANOMALY-CAPTURE'
    }

    It 'does NOT inject the capstone directive on a subagent-driven-development seam' {
        # The personal, pre-plugin copy of this hook bound AGY-CAPSTONE to this seam. The shipped hook
        # binds the capstone to finishing-a-development-branch only, and this seam to the dispatch clause.
        # Pinning that keeps the two bindings from silently merging.
        $out = Invoke-Hook 'superpowers:subagent-driven-development'
        $out | Should -Not -Match 'AGY-CAPSTONE auto-fire'
    }

    It 'emits the LOUD jq-missing line on a subagent-driven-development seam when jq is absent' {
        $payload = @{ tool_input = @{ skill = 'superpowers:subagent-driven-development' }; cwd = '.' } | ConvertTo-Json -Compress
        $r = Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env @{ PATH = $script:NoJqPath; HOME = $script:CleanHome }
        $r.StdOut | Should -Match 'guard inactive'
    }

    It 'the dispatch directive demands a FILES allow-list' {
        $out = Invoke-Hook 'superpowers:subagent-driven-development'
        $out | Should -Match 'FILES clause'
        $out | Should -Match 'git status --short'
    }

    It 'does NOT put either clause on the anomaly-capture seam' {
        $repo = New-TempRepo
        try {
            $cwd = ($repo -replace '\\','/')
            $out = Invoke-Hook -Skill 'superpowers:executing-plans' -Cwd $cwd
            $out | Should -Match 'ANOMALY-CAPTURE'
            $out | Should -Not -Match 'COST:'
            $out | Should -Not -Match 'SESSION POSTURE:'
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is byte-identical to the clavity-classic mirror' {
        $classic = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'clavity-classic/plugin/hooks/agy-seam-inject.sh'
        (Get-FileHash $script:Hook).Hash | Should -Be (Get-FileHash $classic).Hash
    }
}

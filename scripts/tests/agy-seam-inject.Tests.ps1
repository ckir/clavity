# Focused synthetic-payload smoke for the SP-C auto-fire hook (agy-seam-inject.sh).
# Pipes a synthetic PreToolUse(Skill) payload to the shipped bash hook and asserts its
# behaviour: seam match -> the right discipline directive (once); debounce (marker==HEAD)
# -> silent; non-seam -> silent; .no-agy -> suppressed; the hook file is pure ASCII.
# The comprehensive hook-activation matrix (incl. the jq-missing loud line) is SP-D.

BeforeAll {
    # $PSScriptRoot is scripts/tests/ ; go up TWO levels (tests -> scripts -> repo root).
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Hook = Join-Path $RepoRoot 'clavity-dotnet/plugin/hooks/agy-seam-inject.sh'

    # bash is required (the repo already ships bash hooks + a bash sync-check). Fail loudly
    # if absent rather than silently skipping — a skipped smoke is a false green.
    $script:Bash = (Get-Command bash -ErrorAction SilentlyContinue)?.Source
    if (-not $Bash) { throw 'bash not found on PATH; the SP-C hook smoke requires bash.' }

    function Invoke-Hook {
        param([string]$Skill, [string]$Cwd = '.')
        $payload = @{ tool_input = @{ skill = $Skill }; cwd = $Cwd } | ConvertTo-Json -Compress
        $out = $payload | & $script:Bash $script:Hook 2>$null
        return (($out | Out-String).Trim())
    }

    # A throwaway git repo so the debounce read (git -C "$cwd" rev-parse HEAD) has a real HEAD
    # without touching the real repo. cwd is passed as the payload's .cwd (forward-slashed).
    function New-TempRepo {
        $dir = Join-Path ([IO.Path]::GetTempPath()) ("sp-c-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        & git -C $dir init -q
        # Signing-agnostic + hook-free so the fixture survives a box with global commit.gpgsign
        # or a core.hooksPath (unset on the author's box, but this is committed portable test code).
        & git -C $dir -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= commit --allow-empty -qm init
        return $dir
    }
}

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

    It 'injects the AGY-CAPSTONE directive on a finishing-a-development-branch seam' {
        $repo = New-TempRepo
        try {
            $cwd = ($repo -replace '\\','/')
            $out = Invoke-Hook -Skill 'superpowers:finishing-a-development-branch' -Cwd $cwd
            $out | Should -Match 'AGY-CAPSTONE auto-fire'
            $out | Should -Match 'agy-capstone'
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

    It 'ships as pure ASCII (project mojibake discipline)' {
        $bytes = [IO.File]::ReadAllBytes($script:Hook)
        ($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}

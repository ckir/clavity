# Pester v5. End-to-end tests for the release.ps1 ORCHESTRATOR (not the lib functions - see
# release-lib.Tests.ps1 for those). release.ps1 computes $RepoRoot from $PSScriptRoot, so it always
# operates on whatever repo the SCRIPT ITSELF sits in - to test it against a scratch repo we copy the
# script + scripts/lib into that scratch repo at the same relative paths and invoke the copy.
#
# Only the pre-compute-step Die/exit paths are covered here (all six reachable via -Resume /
# no-dangling-candidate combinations). A full successful release run needs the whole members.json /
# plugin structure and is out of scope (see the dispatch brief).
BeforeAll {
    $script:ScriptsSrc = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ReleaseScriptSrc = Join-Path $script:ScriptsSrc 'release.ps1'
    $script:ReleaseLibSrc    = Join-Path $script:ScriptsSrc 'lib' 'release-lib.ps1'

    function New-ReleaseScenario([scriptblock]$Extra) {
        $dir  = Join-Path ([System.IO.Path]::GetTempPath()) ("relorc-" + [guid]::NewGuid().ToString('N'))
        $bare = "$dir.git"
        New-Item -ItemType Directory -Path $dir | Out-Null
        git init -q --bare $bare | Out-Null
        Push-Location $dir
        git init -q -b main . | Out-Null
        git config user.email t@t; git config user.name t; git config commit.gpgsign false
        git remote add origin $bare
        'v1' | Set-Content version.txt
        git add -A; git commit -q -m 'chore(release): clavity-v1'
        git push -q origin main
        New-Item -ItemType Directory -Path (Join-Path $dir 'scripts/lib') -Force | Out-Null
        Copy-Item $script:ReleaseScriptSrc (Join-Path $dir 'scripts/release.ps1')
        Copy-Item $script:ReleaseLibSrc    (Join-Path $dir 'scripts/lib/release-lib.ps1')
        if ($Extra) { & $Extra }
        return @{ Dir = $dir; Bare = $bare }
    }

    # Invokes the SCRATCH REPO's own copy of release.ps1 as a real child process, capturing stdout+stderr
    # and $LASTEXITCODE. ANSI color codes (Write-Host -ForegroundColor) are stripped before matching.
    function Invoke-ReleaseScript {
        param([string]$Dir, [string[]]$ArgList = @())
        $releasePath = Join-Path $Dir 'scripts/release.ps1'
        $raw = & pwsh -NoProfile -File $releasePath @ArgList 2>&1
        $code = $LASTEXITCODE
        $text = ($raw | Out-String) -replace "`e\[[0-9;]*m", ''
        return [pscustomobject]@{ Output = $text; ExitCode = $code }
    }
}

Describe 'release.ps1 -Resume (orchestrator end-to-end)' {
    It '1. -Resume with no dangling candidate: exit 1, names the no-half-finished reason, HEAD unchanged' {
        $s = New-ReleaseScenario { 'x' | Set-Content f.txt; git add -A; git commit -q -m 'feat: x' }
        try {
            $before = (git rev-parse HEAD).Trim()
            $r = Invoke-ReleaseScript -Dir $s.Dir -ArgList @('-Resume')
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'no half-finished release to resume'
            (git rev-parse HEAD).Trim() | Should -Be $before
        } finally { Pop-Location; Remove-Item -Recurse -Force $s.Dir; Remove-Item -Recurse -Force $s.Bare }
    }

    # MEASURED against the real orchestrator: a dirty tracked tree is caught by release.ps1's OWN
    # precondition-0 (`git diff --quiet` at the top of the script) before the $Resume block is ever
    # reached, so the message is "unstaged tracked changes present" - NOT Test-ResumeState's
    # "uncommitted tracked changes" wording (that wording IS asserted directly against Test-ResumeState
    # in release-lib.Tests.ps1, where it is genuinely reachable).
    It '2. -Resume with a dirty tracked tree + dangling candidate: exit 1, unstaged-changes message, dirty file untouched' {
        $s = New-ReleaseScenario {
            'v2' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
            'dirty' | Set-Content version.txt
        }
        try {
            $before = (git rev-parse HEAD).Trim()
            $r = Invoke-ReleaseScript -Dir $s.Dir -ArgList @('-Resume')
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'unstaged tracked changes present'
            (git rev-parse HEAD).Trim() | Should -Be $before
            (Get-Content version.txt -Raw).Trim() | Should -Be 'dirty'
        } finally { Pop-Location; Remove-Item -Recurse -Force $s.Dir; Remove-Item -Recurse -Force $s.Bare }
    }

    It '3. -Resume with TWO dangling candidates: exit 1, "refusing to guess", HEAD unchanged' {
        $s = New-ReleaseScenario {
            'v2' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
            'v3' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v3 [x 0.3.0]'
        }
        try {
            $before = (git rev-parse HEAD).Trim()
            $r = Invoke-ReleaseScript -Dir $s.Dir -ArgList @('-Resume')
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'refusing to guess'
            (git rev-parse HEAD).Trim() | Should -Be $before
        } finally { Pop-Location; Remove-Item -Recurse -Force $s.Dir; Remove-Item -Recurse -Force $s.Bare }
    }

    # AGY-TEST-AUDIT 2026-09-22 (Mechanism Gamer, peer finding, CONFIRMED by mutant). This test asserted
    # only `-Match 'not safe'`, which release.ps1:42 emits for BOTH refusal verdicts - 'conflict' and
    # 'unknown' differ solely in the $why clause chosen at :40-41. MEASURED: a mutant that misreports a
    # real CONFLICT with the 'unknown' wording left this suite 6/6 GREEN, so the suite could not tell the
    # feature's two refusal reasons apart. The fix is to assert the DISTINGUISHING clause, not the shared
    # prefix - the general form being that a matcher must reject the near-miss, not merely accept the hit.
    It '4. -Resume where the replay conflicts: exit 1, names CONFLICTS specifically, HEAD unchanged, no rebase in progress' {
        $s = New-ReleaseScenario {
            "# CL`n`n## 0.2.0`n- a`n" | Set-Content CHANGELOG.md
            git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
            "# CL`n`n## 0.2.0`n- a`n- b`n" | Set-Content CHANGELOG.md
            git add -A; git commit -q -m 'fix(docs): touch changelog'
        }
        try {
            $before = (git rev-parse HEAD).Trim()
            $r = Invoke-ReleaseScript -Dir $s.Dir -ArgList @('-Resume')
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'not safe'
            $r.Output | Should -Match 'replaying your commits onto its parent CONFLICTS'
            $r.Output | Should -Not -Match 'could not be proven conflict-free'
            (git rev-parse HEAD).Trim() | Should -Be $before
            (git rev-parse --abbrev-ref HEAD) | Should -Be 'main'
            (Test-Path (Join-Path $s.Dir '.git/rebase-merge')) | Should -BeFalse
            (Test-Path (Join-Path $s.Dir '.git/rebase-apply')) | Should -BeFalse
        } finally { Pop-Location; Remove-Item -Recurse -Force $s.Dir; Remove-Item -Recurse -Force $s.Bare }
    }

    It '5. -Resume -WhatIf on a clean resumable state: exit 0, "would drop", HEAD unchanged (mutates nothing)' {
        $s = New-ReleaseScenario {
            'v2' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
        }
        try {
            $before = (git rev-parse HEAD).Trim()
            $r = Invoke-ReleaseScript -Dir $s.Dir -ArgList @('-Resume', '-WhatIf')
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Match 'would drop'
            (git rev-parse HEAD).Trim() | Should -Be $before
        } finally { Pop-Location; Remove-Item -Recurse -Force $s.Dir; Remove-Item -Recurse -Force $s.Bare }
    }

    It '6. no -Resume, with a dangling candidate present: exit 1, names half-finished AND the -Resume affordance' {
        $s = New-ReleaseScenario {
            'v2' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
        }
        try {
            $before = (git rev-parse HEAD).Trim()
            $r = Invoke-ReleaseScript -Dir $s.Dir -ArgList @()
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'half-finished'
            $r.Output | Should -Match 'or re-run with -Resume'
            (git rev-parse HEAD).Trim() | Should -Be $before
        } finally { Pop-Location; Remove-Item -Recurse -Force $s.Dir; Remove-Item -Recurse -Force $s.Bare }
    }
}

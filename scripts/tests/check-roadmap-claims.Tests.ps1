# Fixture ROADMAPs under $TestDrive plus a throwaway git repo for the sha-existence half. The real
# ROADMAP is exercised by exactly one row, and only AFTER Task 4 reconciles it.
BeforeAll {
    # Same hardening as check-plugin-drift.Tests.ps1, for the same measured reason: a missing script
    # under `(Resolve-Path ...).Path` is a non-terminating error and lets unrelated rows report PASSED.
    $script:Script   = Join-Path $PSScriptRoot '..' 'check-roadmap-claims.ps1'
    if (-not (Test-Path -LiteralPath $script:Script)) {
        throw "check-roadmap-claims.ps1 not found at $script:Script - this suite cannot run"
    }
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

    function New-ClaimRepo {
        param([string]$Roadmap, [hashtable]$Files = @{})
        $repo = Join-Path $TestDrive ("rm-" + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $repo -Force
        & git -C $repo init -q
        & git -C $repo config user.email 't@t.t'
        & git -C $repo config user.name  'T'
        & git -C $repo config core.autocrlf false
        foreach ($rel in $Files.Keys) {
            $p = Join-Path $repo ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            $null = New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force
            [IO.File]::WriteAllText($p, $Files[$rel])
        }
        $rmPath = Join-Path $repo 'ROADMAP.md'
        [IO.File]::WriteAllText($rmPath, $Roadmap)
        & git -C $repo add -A
        & git -C $repo commit -q -m 'fixture'
        [pscustomobject]@{ Root = $repo; Roadmap = $rmPath; Sha = (& git -C $repo rev-parse HEAD).Trim() }
    }

    function Invoke-Claims {
        param([string]$RepoRoot, [string]$RoadmapPath)
        $out = & pwsh -NoProfile -File $script:Script -RepoRoot $RepoRoot -RoadmapPath $RoadmapPath 2>&1 | Out-String
        [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
    }
}

Describe 'check-roadmap-claims.ps1 - the (N lines) half' {

    It 'exits 0 when a line-count claim is correct' {
        $f = New-ClaimRepo -Files @{ 'skills/a/SKILL.md' = "1`n2`n3`n" } `
             -Roadmap "Entry. ``skills/a/SKILL.md`` (3 lines) is fine.`n"
        $r = Invoke-Claims $f.Root $f.Roadmap
        $r.Code | Should -Be 0 -Because "output was:`n$($r.Out)"
    }

    It 'exits 1 and names the file when a line-count claim is STALE' {
        # This is the 14h failure exactly: the entry claimed 123 lines against an actual 214.
        $f = New-ClaimRepo -Files @{ 'skills/a/SKILL.md' = "1`n2`n3`n" } `
             -Roadmap "Entry. ``skills/a/SKILL.md`` (99 lines) is stale.`n"
        $r = Invoke-Claims $f.Root $f.Roadmap
        $r.Code | Should -Be 1
        $r.Out  | Should -Match 'skills/a/SKILL\.md'
        $r.Out  | Should -Match '99'
        $r.Out  | Should -Match '3'
    }

    It 'exits 1 when a claimed file does not exist at all' {
        $f = New-ClaimRepo -Roadmap "Entry. ``skills/ghost/SKILL.md`` (10 lines).`n"
        $r = Invoke-Claims $f.Root $f.Roadmap
        $r.Code | Should -Be 1
        $r.Out  | Should -Match 'UNRESOLVED|not found'
    }

    It 'exits 1 when a claim resolves to two tracked files with DIFFERENT counts' {
        # Both plugins carry byte-identical copies of these skills, so a bare `agy-first/SKILL.md`
        # resolves twice. Equal counts are fine; unequal means the pair has diverged and the claim is
        # ambiguous - which must be an error, not a coin flip on whichever path sorted first.
        $f = New-ClaimRepo -Files @{
                'p1/skills/a/SKILL.md' = "1`n2`n3`n"
                'p2/skills/a/SKILL.md' = "1`n2`n"
             } -Roadmap "Entry. ``skills/a/SKILL.md`` (3 lines).`n"
        $r = Invoke-Claims $f.Root $f.Roadmap
        $r.Code | Should -Be 1
        $r.Out  | Should -Match 'AMBIGUOUS'
    }

    It 'exits 1 and says UNREADABLE when a claimed file is TRACKED but absent from the worktree' {
        # AGY-CAPSTONE round 1, MEASURED: `git ls-files` reads the INDEX, so a file deleted from the
        # worktree without being staged is still tracked. `ReadAllText` then threw an unhandled
        # FileNotFoundException and the script exited 1 - the "a claim is FALSE" code - so a broken
        # worktree was indistinguishable from a stale line count.
        $f = New-ClaimRepo -Files @{ 'skills/a/SKILL.md' = "1`n2`n3`n" } `
             -Roadmap "Entry. ``skills/a/SKILL.md`` (3 lines).`n"
        Remove-Item (Join-Path $f.Root 'skills' 'a' 'SKILL.md') -Force
        $r = Invoke-Claims $f.Root $f.Roadmap
        $r.Code | Should -Be 1
        $r.Out  | Should -Match 'UNREADABLE'
        $r.Out  | Should -Not -Match 'FileNotFoundException'
        $r.Out  | Should -Not -Match 'STALE'
    }

    It 'says UNREADABLE when the tracked path is a DIRECTORY, not a file' {
        # AGY-CAPSTONE round 2, against round 1's OWN FIX. A bare `Test-Path` is TRUE for a directory, so
        # a tracked file replaced by a directory of the same name slipped past the absent-check and threw
        # an unhandled UnauthorizedAccessException. MEASURED both ways: Test-Path True, -PathType Leaf
        # False. This row is the distractor the first fix had no case for.
        $f = New-ClaimRepo -Files @{ 'skills/a/SKILL.md' = "1`n2`n3`n" } `
             -Roadmap "Entry. ``skills/a/SKILL.md`` (3 lines).`n"
        $p = Join-Path $f.Root 'skills' 'a' 'SKILL.md'
        Remove-Item $p -Force
        $null = New-Item -ItemType Directory -Path $p -Force
        $r = Invoke-Claims $f.Root $f.Roadmap
        $r.Code | Should -Be 1
        $r.Out  | Should -Match 'UNREADABLE'
        $r.Out  | Should -Not -Match 'UnauthorizedAccessException|Access to the path'
    }

    It 'reports an unparseable line-count claim instead of crashing on it' {
        # AGY-CAPSTONE round 2. `\d+` is unbounded and the old `[int]` cast threw on a claim too large
        # for Int32 - uncontrolled markdown must not crash a checker.
        $f = New-ClaimRepo -Files @{ 'skills/a/SKILL.md' = "1`n2`n3`n" } `
             -Roadmap "Entry. ``skills/a/SKILL.md`` (99999999999999999999999999 lines).`n"
        $r = Invoke-Claims $f.Root $f.Roadmap
        $r.Code | Should -Be 1
        $r.Out  | Should -Match 'UNPARSEABLE'
        $r.Out  | Should -Not -Match 'Cannot convert value|too large or too small'
    }

    It 'checks a claim about ANY extension, not a hard-coded whitelist' {
        # AGY-CAPSTONE round 1. The regex read `(?:md|ps1|sh|cs|rs|json)`, so a claim about a .yml, .txt
        # or .iss file was SILENTLY ignored - a fail-open inside a guard whose job is closing one. This
        # row is the distractor case: a stale claim about a non-whitelisted extension must still RED.
        $f = New-ClaimRepo -Files @{ 'ci/workflow.yml' = "a`nb`n" } `
             -Roadmap "Entry. ``ci/workflow.yml`` (99 lines).`n"
        $r = Invoke-Claims $f.Root $f.Roadmap
        $r.Code | Should -Be 1
        $r.Out  | Should -Match 'STALE'
        $r.Out  | Should -Match 'workflow\.yml'
    }
}

Describe 'check-roadmap-claims.ps1 - the sha-existence half' {

    It 'exits 0 when a sha cited beside a closure token exists' {
        $f = New-ClaimRepo -Roadmap "placeholder`n"
        $rm = Join-Path $f.Root 'R2.md'
        [IO.File]::WriteAllText($rm, "Item. SHIPPED 2026-01-01 (``$($f.Sha.Substring(0,7))``).`n")
        $r = Invoke-Claims $f.Root $rm
        $r.Code | Should -Be 0 -Because "output was:`n$($r.Out)"
    }

    It 'exits 1 when a sha beside a closure token does NOT exist' {
        # The agy-mark.sh defect class: a 40-character string that looks like a sha and is not one.
        $f = New-ClaimRepo -Roadmap "placeholder`n"
        $rm = Join-Path $f.Root 'R2.md'
        [IO.File]::WriteAllText($rm, "Item. SHIPPED 2026-01-01 (``63eb46f0000000000000000000000000deadbeef``).`n")
        $r = Invoke-Claims $f.Root $rm
        $r.Code | Should -Be 1
        $r.Out  | Should -Match 'PHANTOM|does not exist'
    }

    It 'IGNORES a sha-shaped string on a line with no closure token' {
        # Scope control. The ROADMAP quotes hashes in prose all over; only closure claims are bound.
        $f = New-ClaimRepo -Roadmap "placeholder`n"
        $rm = Join-Path $f.Root 'R2.md'
        [IO.File]::WriteAllText($rm, "Discussion of ``63eb46f0000000000000000000000000deadbeef`` in passing.`n")
        $r = Invoke-Claims $f.Root $rm
        $r.Code | Should -Be 0 -Because "output was:`n$($r.Out)"
    }
}

Describe 'check-roadmap-claims.ps1 - inputs it does not control' {

    It 'exits 2 - NOT 1 - when the ROADMAP path is a DIRECTORY' {
        # AGY-CAPSTONE round 6. This is the SIBLING of the bug round 2 fixed in the per-claim path, and
        # round 2 missed it: a bare Test-Path is TRUE for a directory, so it fell through to ReadAllText
        # and threw an unhandled UnauthorizedAccessException, exiting 1 - the "a claim is FALSE" code.
        $f = New-ClaimRepo -Roadmap "placeholder`n"
        $dir = Join-Path $f.Root 'a-directory'
        $null = New-Item -ItemType Directory -Path $dir -Force
        $r = Invoke-Claims $f.Root $dir
        $r.Code | Should -Be 2 -Because "an unreadable input is 'cannot check', not 'a claim is false'; output was:`n$($r.Out)"
        $r.Out  | Should -Not -Match 'UnauthorizedAccessException|Access to the path'
    }

    It 'checks a closure sha even when the closure word is not UPPERCASE' {
        # AGY-CAPSTONE round 6. .NET [regex] is case-SENSITIVE by default, so a line reading
        # "the fix shipped (`deadbee`)" carried a sha that was never checked. MEASURED on the real
        # ROADMAP: widening brought 7 more shas into scope, all of which exist.
        $f = New-ClaimRepo -Roadmap "placeholder`n"
        $rm = Join-Path $f.Root 'R3.md'
        [IO.File]::WriteAllText($rm, "The instructional fix shipped (``63eb46f0000000000000000000000000deadbeef``).`n")
        $r = Invoke-Claims $f.Root $rm
        $r.Code | Should -Be 1 -Because "a lowercase closure word must not exempt its sha; output was:`n$($r.Out)"
        $r.Out  | Should -Match 'PHANTOM'
    }
}

Describe 'check-roadmap-claims.ps1 - the real repository' {
    It 'passes on the committed ROADMAP' {
        # RED until Task 4 reconciles the four stale headers. That is deliberate: this row is the
        # oracle that the reconcile actually happened, rather than a claim that it did.
        $r = Invoke-Claims $script:RepoRoot (Join-Path $script:RepoRoot 'clavity-dotnet' 'ROADMAP.md')
        $r.Code | Should -Be 0 -Because "the real ROADMAP must satisfy its own checkable claims; output was:`n$($r.Out)"
    }
}

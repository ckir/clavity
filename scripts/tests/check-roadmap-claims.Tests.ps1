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

Describe 'check-roadmap-claims.ps1 - the real repository' {
    It 'passes on the committed ROADMAP' {
        # RED until Task 4 reconciles the four stale headers. That is deliberate: this row is the
        # oracle that the reconcile actually happened, rather than a claim that it did.
        $r = Invoke-Claims $script:RepoRoot (Join-Path $script:RepoRoot 'clavity-dotnet' 'ROADMAP.md')
        $r.Code | Should -Be 0 -Because "the real ROADMAP must satisfy its own checkable claims; output was:`n$($r.Out)"
    }
}

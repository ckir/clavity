# Fixture ROADMAPs under $TestDrive plus a throwaway git repo for the sha-existence half. The real
# ROADMAP is exercised by exactly one row, and only AFTER Task 4 reconciles it.
BeforeAll {
    # Same hardening as check-plugin-drift.Tests.ps1, for the same measured reason: a missing script
    # under `(Resolve-Path ...).Path` is a non-terminating error and lets unrelated rows report PASSED.
    $script:Script   = Join-Path $PSScriptRoot '..' 'check-roadmap-claims.ps1'
    # -PathType Leaf: a directory of that name would otherwise satisfy the guard and the suite
    # would proceed to run a script that cannot execute. AGY-CAPSTONE round 7 sibling sweep.
    if (-not (Test-Path -LiteralPath $script:Script -PathType Leaf)) {
        throw "check-roadmap-claims.ps1 not found at $script:Script - this suite cannot run"
    }
    # -LiteralPath and .ProviderPath, for the two reasons the comment four lines above already gives
    # and this line did not obey. `Resolve-Path <path>` binds the WILDCARD parameter set, so a clone
    # under a path containing [ or ] is globbed (round 10), and `.Path` is PROVIDER-QUALIFIED
    # (round 9). Both checkers were fixed in those rounds; this line - which supplies the ONLY row
    # that runs the guard against the real committed ROADMAP, and so its only CI enforcement - was
    # missed by both sweeps. AGY-CAPSTONE round 11.
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).ProviderPath

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

    It 'counts a file with NO final newline by its visible lines, not its terminators' {
        # AGY-CAPSTONE round 10. `(ReadAllText -split "`n").Count - 1` is `wc -l` semantics - it counts
        # TERMINATORS - so a file whose last line has no newline was reported one line SHORT and a TRUE
        # claim was accused of being STALE. MEASURED: a 3-line file with no trailing newline gave
        # "claims 3 lines, actual 2", and appending the newline alone made it pass. TEN of 663 tracked
        # files in this repository have no final newline.
        $f = New-ClaimRepo -Files @{ 'a/nonl.md' = "1`n2`n3" } `
             -Roadmap "Entry. ``a/nonl.md`` (3 lines).`n"
        $r = Invoke-Claims $f.Root $f.Roadmap
        $r.Code | Should -Be 0 -Because "three visible lines are three lines whether or not the file ends in a newline; output was:`n$($r.Out)"
    }

    It 'still calls a genuinely wrong count STALE when the file has no final newline' {
        # The paired control for the row above: the newline fix must not blunt the check it lives in.
        $f = New-ClaimRepo -Files @{ 'a/nonl.md' = "1`n2`n3" } `
             -Roadmap "Entry. ``a/nonl.md`` (99 lines).`n"
        $r = Invoke-Claims $f.Root $f.Roadmap
        $r.Code | Should -Be 1
        $r.Out  | Should -Match 'STALE'
    }

    It 'does not call an UNCHECKABLE claim a FALSE one in its summary' {
        # AGY-CAPSTONE round 10. $problems mixes STALE (the claim IS false) with UNREADABLE, UNRESOLVED,
        # AMBIGUOUS, UNPARSEABLE and SHALLOW (the claim could NOT BE CHECKED). The summary called all of
        # them "false claim(s)" - MEASURED, a shallow clone printed "1 false claim(s)" having evaluated
        # NONE. The exit code was right all along; the accusation was the defect.
        $f = New-ClaimRepo -Files @{ 'a/gone.md' = "1`n2`n3`n" } `
             -Roadmap "Entry. ``a/gone.md`` (3 lines).`n"
        Remove-Item (Join-Path $f.Root 'a' 'gone.md') -Force
        $r = Invoke-Claims $f.Root $f.Roadmap
        $r.Code | Should -Be 1
        $r.Out  | Should -Match 'could not be checked'
        $r.Out  | Should -Not -Match 'false claim'
    }

    It 'calls a PHANTOM sha a FALSE claim, not one that could not be checked' {
        # AGY-CAPSTONE round 11, and round 10's own summary fix shipping its own edge. That fix split on
        # `-like 'STALE*'`, so PHANTOM - a claim the checker DID check and found false - landed in the
        # "could not be checked" bucket. MEASURED: the run printed "does not exist in this repository"
        # and then "1 claim(s) that could not be checked", two lines apart. The remedies for the
        # uncheckable class are all environmental and none of them fixes a bogus sha.
        $f = New-ClaimRepo -Roadmap "placeholder`n"
        $rm = Join-Path $f.Root 'RP.md'
        [IO.File]::WriteAllText($rm, "Item. SHIPPED (``63eb46f0000000000000000000000000deadbee``).`n")
        $r = Invoke-Claims $f.Root $rm
        $r.Code | Should -Be 1
        $r.Out  | Should -Match 'PHANTOM'
        $r.Out  | Should -Match 'false claim'
        $r.Out  | Should -Not -Match 'could not be checked'
    }

    It 'DOES say false claim when the claim really is false' {
        # The paired control: the wording fix must not stop the checker calling a lie a lie.
        $f = New-ClaimRepo -Files @{ 'a/gone.md' = "1`n2`n3`n" } `
             -Roadmap "Entry. ``a/gone.md`` (99 lines).`n"
        $r = Invoke-Claims $f.Root $f.Roadmap
        $r.Code | Should -Be 1
        $r.Out  | Should -Match 'false claim'
    }

    It 'resolves its own repository root under a path containing [ or ]' {
        # AGY-CAPSTONE round 11. The twin row in check-plugin-drift.Tests.ps1 has existed since round 10;
        # this checker's half of the same fold shipped UNPINNED, which is exactly why the identical bug
        # survived in this suite's own BeforeAll until round 11 found it. `Resolve-Path <path>` binds the
        # WILDCARD parameter set and [ and ] are legal Windows filename characters.
        $brk = Join-Path $TestDrive ('repo[wip]-' + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path (Join-Path $brk 'scripts') -Force
        Copy-Item -LiteralPath $script:Script -Destination (Join-Path $brk 'scripts') -Force
        $probe = Join-Path $brk 'scripts' 'check-roadmap-claims.ps1'
        # No -RepoRoot and no -RoadmapPath: the script must work out both from $PSScriptRoot, which is
        # the code path under test. It then fails because the fixture has no ROADMAP - exit 2 - and 2 is
        # the proof, because the glob bug died at 1 while resolving its own root, before reaching that.
        $out = & pwsh -NoProfile -File $probe 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 2 -Because "a bracketed path must reach the ROADMAP check (2), not die resolving its own root (1); output was:`n$out"
        $out | Should -Not -Match "property 'Path' cannot be found"
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

    It 'says UNREADABLE - not a crash - when a claimed file is exclusively LOCKED' {
        # AGY-CAPSTONE round 7. The drift detector was given this guard in round 3; this sibling was
        # not. MEASURED with a real FileShare::None lock: ReadAllText threw and the run died at :91.
        $f = New-ClaimRepo -Files @{ 'skills/a/SKILL.md' = "1`n2`n3`n" } `
             -Roadmap "Entry. ``skills/a/SKILL.md`` (3 lines).`n"
        $p = Join-Path $f.Root 'skills' 'a' 'SKILL.md'
        $fs = [IO.File]::Open($p, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        try {
            $r = Invoke-Claims $f.Root $f.Roadmap
            $r.Code | Should -Be 1
            $r.Out  | Should -Match 'UNREADABLE'
            $r.Out  | Should -Not -Match 'being used by another process'
        } finally { $fs.Dispose() }
    }

    It 'checks a line-count claim whose unit word is not lowercase' {
        # AGY-CAPSTONE round 7, the sibling of round 6's closure-regex fix. MEASURED: the literal
        # `lines` is case-sensitive, so `(3 LINES)` matched nothing and the claim went unchecked.
        $f = New-ClaimRepo -Files @{ 'skills/a/SKILL.md' = "1`n2`n3`n" } `
             -Roadmap "Entry. ``skills/a/SKILL.md`` (99 LINES).`n"
        $r = Invoke-Claims $f.Root $f.Roadmap
        $r.Code | Should -Be 1 -Because "an uppercase unit word must not exempt the claim; output was:`n$($r.Out)"
        $r.Out  | Should -Match 'STALE'
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

Describe 'check-roadmap-claims.ps1 - sha notations the document actually uses' {

    It 'checks BOTH endpoints of a sha RANGE, not just the first' {
        # AGY-CAPSTONE round 8, and a LIVE miss rather than a latent one. The old pattern demanded a
        # backtick immediately after the hex, so `a..b` in ONE code span - this repository's dominant
        # notation - matched nothing and the whole line was skipped. MEASURED on the committed ROADMAP:
        # 3 closure lines carry a range, hiding SIX shas the guard printed "holds" over.
        $f = New-ClaimRepo -Roadmap "placeholder`n"
        $rm = Join-Path $f.Root 'R4.md'
        [IO.File]::WriteAllText($rm, "Item. SHIPPED (``63eb46f0000000000000000000000000deadbee..73eb46f0000000000000000000000000deadbef``).`n")
        $r = Invoke-Claims $f.Root $rm
        $r.Code | Should -Be 1
        ([regex]::Matches($r.Out, 'PHANTOM')).Count | Should -Be 2 -Because "both endpoints of a range must be checked, not one; output was:`n$($r.Out)"
    }

    It 'does not invent a PHANTOM for a range of REAL shas' {
        # The paired control for the row above: widening must not manufacture false accusations.
        $f = New-ClaimRepo -Roadmap "placeholder`n"
        $s = $f.Sha.Substring(0, 7)
        $rm = Join-Path $f.Root 'R5.md'
        [IO.File]::WriteAllText($rm, "Item. SHIPPED (``$s..$s``).`n")
        $r = Invoke-Claims $f.Root $rm
        $r.Code | Should -Be 0 -Because "a range of real shas must pass; output was:`n$($r.Out)"
    }

    It 'counts both ENDPOINTS of a range in the SHALLOW message' {
        # AGY-CAPSTONE round 9. The SHALLOW line is the entire product of that branch - the only thing an
        # operator sees - and it counted regex MATCHES. A range is ONE match carrying TWO shas.
        # The endpoints are two DISTINCT tokens on purpose: round 10 added de-duplication, and a
        # `sha..sha` fixture would now correctly collapse to 1 and prove nothing about endpoints.
        # The shallow branch never resolves these, it only counts them, so they need not be real.
        $f = New-ClaimRepo -Roadmap "placeholder`n"
        $shallow = Join-Path $TestDrive ("shc-" + [Guid]::NewGuid().ToString('N'))
        & git clone --depth 1 --quiet ("file:///" + ($f.Root -replace '\\', '/')) $shallow 2>&1 | Out-Null
        (& git -C $shallow rev-parse --is-shallow-repository).Trim() | Should -Be 'true' -Because 'the fixture must actually be shallow, or this row proves nothing'
        $rm = Join-Path $shallow 'R8.md'
        [IO.File]::WriteAllText($rm, "Item. SHIPPED (``deadbee1234..cafe5678901``).`n")
        $r = Invoke-Claims $shallow $rm
        $r.Out | Should -Match 'so 2 cited sha' -Because "a range has two endpoints; output was:`n$($r.Out)"
    }

    It 'de-duplicates a sha cited twice on one line in the SHALLOW message' {
        # AGY-CAPSTONE round 10, and round 9's own fold shipping its own edge. The CHECKING branch
        # dedupes by "sha|line"; the shallow branch, added by the same round-9 fold, did not - so the
        # two branches disagreed about what "a cited sha" is. This is the shape of the real
        # clavity-dotnet/ROADMAP.md:892, which cites one sha bare AND as the tail of a range:
        # measured, the shallow line reported 49 citations for 48 distinct shas.
        $f = New-ClaimRepo -Roadmap "placeholder`n"
        $shallow = Join-Path $TestDrive ("shd-" + [Guid]::NewGuid().ToString('N'))
        & git clone --depth 1 --quiet ("file:///" + ($f.Root -replace '\\', '/')) $shallow 2>&1 | Out-Null
        (& git -C $shallow rev-parse --is-shallow-repository).Trim() | Should -Be 'true' -Because 'the fixture must actually be shallow, or this row proves nothing'
        $rm = Join-Path $shallow 'R9.md'
        [IO.File]::WriteAllText($rm, "Item. SHIPPED (``cafe5678901``; built then ``deadbee1234..cafe5678901``).`n")
        $r = Invoke-Claims $shallow $rm
        $r.Out | Should -Match 'so 2 cited sha' -Because "three citations of two distinct shas is two; output was:`n$($r.Out)"
    }

    It 'checks a sha written in UPPERCASE' {
        # AGY-CAPSTONE round 8, the third sibling of the case class folded in rounds 6 and 7. Git
        # resolves an uppercase object name happily (measured: cat-file -e on an upper-cased HEAD
        # exits 0), so `[0-9a-f]` silently exempted a real citation.
        $f = New-ClaimRepo -Roadmap "placeholder`n"
        $rm = Join-Path $f.Root 'R6.md'
        [IO.File]::WriteAllText($rm, "Item. SHIPPED (``63EB46F0000000000000000000000000DEADBEE``).`n")
        $r = Invoke-Claims $f.Root $rm
        $r.Code | Should -Be 1
        $r.Out  | Should -Match 'PHANTOM'
    }

    It 'reports SHALLOW - once - instead of accusing every sha, on a repository with no history' {
        # AGY-CAPSTONE round 8. MEASURED on a real `git clone --depth 1` of this repository: 43 PHANTOM
        # lines and exit 1, where the full clone exits 0. actions/checkout is shallow by DEFAULT, so
        # this is what CI would have produced. It must still FAIL - a check that cannot run must never
        # report clean - but as one honest line, not a wall of false accusations.
        $f = New-ClaimRepo -Roadmap "placeholder`n"
        $shallow = Join-Path $TestDrive ("sh-" + [Guid]::NewGuid().ToString('N'))
        & git clone --depth 1 --quiet ("file:///" + ($f.Root -replace '\\', '/')) $shallow 2>&1 | Out-Null
        (& git -C $shallow rev-parse --is-shallow-repository).Trim() | Should -Be 'true' -Because 'the fixture must actually be shallow, or this row proves nothing'
        $rm = Join-Path $shallow 'R7.md'
        [IO.File]::WriteAllText($rm, "Item. SHIPPED (``$($f.Sha.Substring(0,7))``).`n")
        $r = Invoke-Claims $shallow $rm
        $r.Code | Should -Be 1 -Because "cannot-check must not read as clean; output was:`n$($r.Out)"
        $r.Out  | Should -Match 'SHALLOW'
        $r.Out  | Should -Not -Match 'PHANTOM'
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

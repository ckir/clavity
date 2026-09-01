#!/usr/bin/env pwsh
# Verifies the ROADMAP's own MECHANICALLY CHECKABLE claims. It does not judge whether an item is done -
# nothing can - it checks the evidence an entry cites about the repository.
#
# WHY THIS EXISTS. The ROADMAP has read OPEN for shipped work FOUR times (13b, 17, 18, 19, 14h). The rule
# earned from that - "whoever closes an item writes its closing sha in the same commit" - had ZERO
# implementation when this was written, and a rule with no implementation is worse than none because it is
# believed. MEASURED 2026-08-31: all FOUR of the ROADMAP's `(N lines)` claims were wrong, and all four sat
# in the 14h entry - the one that had been stale for sixteen days. Precision 4/4 on the real defect.
#
# TWO CHECKS, deliberately narrow so they cannot be argued with:
#   A. every `path` (N lines) claim matches the tracked file it names;
#   B. every backticked 7-40 hex sha on a line ALSO carrying a closure token actually exists.
# Check B passed 28/28 when written - it is a trap for a future phantom, not a backlog.
#
# EXIT CODES: 0 = every claim holds · 1 = at least one claim is false OR could not be checked ·
#             2 = the RUN could not start (no ROADMAP file, not a git repository).
# The 1-vs-2 split is per-RUN, not per-claim, and AGY-CAPSTONE round 4 caught the header claiming
# otherwise: UNREADABLE and UNPARSEABLE print "cannot be checked" and exit 1, not 2. Exiting 1 is
# the right behaviour - one uncheckable claim must not hide the OTHER claims that are provably
# false - so the PROSE was what needed fixing, not the code.
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$RoadmapPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot)    { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
if (-not $RoadmapPath) { $RoadmapPath = Join-Path $RepoRoot 'clavity-dotnet' 'ROADMAP.md' }

# -PathType Leaf, for the SAME reason as the per-claim check below - and this is the sibling that
# round 2's fix MISSED. A bare Test-Path is TRUE for a DIRECTORY, so a directory passed here and
# then threw an unhandled UnauthorizedAccessException at ReadAllText. MEASURED at AGY-CAPSTONE
# round 6. Fixing one instance of a class and not grepping for its siblings is how this reappeared.
if (-not (Test-Path -LiteralPath $RoadmapPath -PathType Leaf)) {
    Write-Host "check-roadmap-claims: '$RoadmapPath' is not a readable file - nothing was checked" -ForegroundColor Yellow
    exit 2
}

$tracked = @(& git -C $RepoRoot ls-files)
if ($LASTEXITCODE -ne 0) {
    Write-Host "check-roadmap-claims: '$RepoRoot' is not a git repository - nothing was checked" -ForegroundColor Yellow
    exit 2
}

# READ IT INSIDE A try. `Test-Path -PathType Leaf` tests SHAPE, not READABILITY: it is True for an
# exclusively locked or ACL-denied file, so the guard above passes and this line threw unhandled,
# exiting 1 - the "a claim is FALSE" code - for a run that never started. MEASURED at AGY-CAPSTONE
# round 8 with a real FileShare::None lock. Same class as the per-claim read folded in round 7, one
# scope up: the FOURTH instance of it found in this review.
try {
    $lines = [IO.File]::ReadAllText($RoadmapPath) -split "`r?`n"
} catch {
    Write-Host "check-roadmap-claims: '$RoadmapPath' could not be read ($($_.Exception.GetBaseException().GetType().Name)) - nothing was checked" -ForegroundColor Yellow
    exit 2
}
$problems = @()

# --- A. line-count claims -------------------------------------------------------------------------
# ANY extension, not a whitelist. It was `(?:md|ps1|sh|cs|rs|json)`, which SILENTLY ignored a claim
# about a .yml, .txt or .iss file - a fail-open in a guard whose whole job is to close one. Zero such
# claims exist today (measured), so this closes a latent hole rather than fixing a live miss. The
# backticks plus the literal `(N lines)` already make the shape specific enough that widening the
# extension cannot pull in prose. AGY-CAPSTONE round 1.
# IgnoreCase, for the SAME reason the closure regex below is - and this is its sibling, missed in
# round 6. MEASURED: the literal `lines` is case-sensitive, so `(3 LINES)` matched nothing and the
# claim went unchecked. A guard that silently skips the input it does not recognise is the exact
# fail-open shape this file exists to close.
$claimRe = [regex]::new('`([A-Za-z0-9_./-]+\.[A-Za-z0-9]+)`\s*\((\d+)\s+lines\)', 'IgnoreCase, CultureInvariant')
for ($i = 0; $i -lt $lines.Count; $i++) {
    foreach ($m in $claimRe.Matches($lines[$i])) {
        $rel     = $m.Groups[1].Value
        # TryParse, not a bare [int] cast. The regex's `\d+` is unbounded, so a claim like
        # `(99999999999999999999999999 lines)` overflowed Int32 and threw an unhandled conversion error.
        # Uncontrolled input must not crash a checker: report it and carry on. AGY-CAPSTONE round 2.
        $claimed = 0
        if (-not [int]::TryParse($m.Groups[2].Value, [ref]$claimed)) {
            $problems += "UNPARSEABLE ROADMAP:$($i+1)  ``$rel`` claims '$($m.Groups[2].Value)' lines, which is not a number this checker can hold"
            continue
        }
        # CASE-INSENSITIVE ON BOTH HALVES. MEASURED at AGY-CAPSTONE round 7:
        #   'A/B/Skill.MD' -eq 'a/b/skill.md'      -> True   (PowerShell -eq is case-INsensitive)
        #   'A/B/Skill.MD'.EndsWith('/skill.md')   -> False  (.NET EndsWith(string) is case-SENSITIVE)
        # So the exact-match half and the suffix half disagreed about the same two paths. On Windows the
        # filesystem is case-insensitive while `git ls-files` reports the committed case, so a claim
        # written in a different case matched one half and not the other.
        $hits    = @($tracked | Where-Object {
            $_ -eq $rel -or $_.EndsWith("/$rel", [StringComparison]::OrdinalIgnoreCase)
        })
        if ($hits.Count -eq 0) {
            $problems += "UNRESOLVED  ROADMAP:$($i+1)  ``$rel`` is not a tracked file"
            continue
        }
        # A TRACKED FILE CAN BE ABSENT FROM THE WORKTREE - `git ls-files` reads the INDEX, so a file
        # deleted but not staged is still listed. MEASURED at AGY-CAPSTONE round 1: `ReadAllText` then
        # threw an unhandled FileNotFoundException and the script exited **1**, which is the "a claim is
        # false" code - so a broken worktree was indistinguishable from a stale line count, sending the
        # reader to hunt a number that was never wrong. Fail CLOSED, and say which thing broke.
        # -PathType Leaf, NOT a bare Test-Path. AGY-CAPSTONE round 2 caught this in round 1's OWN FIX:
        # a bare Test-Path returns TRUE for a DIRECTORY, so a tracked file replaced by a directory of the
        # same name passed this guard and then threw an unhandled UnauthorizedAccessException at
        # ReadAllText. MEASURED: Test-Path -> True, Test-Path -PathType Leaf -> False. A fix is a fresh
        # claim, and this one shipped its own edge.
        $absent = @($hits | Where-Object {
            -not (Test-Path -LiteralPath (Join-Path $RepoRoot ($_ -replace '/', [IO.Path]::DirectorySeparatorChar)) -PathType Leaf)
        })
        if ($absent.Count -gt 0) {
            $problems += "UNREADABLE  ROADMAP:$($i+1)  ``$rel`` is tracked but is not a readable file in the worktree ($($absent -join ', ')) - the claim cannot be checked"
            continue
        }
        # UNREADABLE covers PRESENT-BUT-UNREADABLE too, not just absent. MEASURED at AGY-CAPSTONE
        # round 7 with a real FileShare::None lock: ReadAllText threw and the run died. The drift
        # detector was given this exact guard in round 3 and this sibling was not - the third time in
        # this review that one instance of a class was fixed and its twin left in place.
        $counts = @()
        $failed = @()
        foreach ($h in $hits) {
            $hp = Join-Path $RepoRoot ($h -replace '/', [IO.Path]::DirectorySeparatorChar)
            try {
                $counts += ([IO.File]::ReadAllText($hp) -split "`n").Count - 1
            } catch {
                # GetBaseException, NOT Exception.GetType(). MEASURED at AGY-CAPSTONE round 8:
                # PowerShell wraps every exception thrown by a .NET METHOD CALL in a
                # MethodInvocationException, so this field printed that same constant for a lock, an
                # ACL denial and a missing directory alike - zero bits, in the one channel whose job
                # is to say WHICH thing broke. Base types: IOException vs DirectoryNotFoundException.
                $failed += "$h ($($_.Exception.GetBaseException().GetType().Name))"
            }
        }
        if ($failed.Count -gt 0) {
            $problems += "UNREADABLE  ROADMAP:$($i+1)  ``$rel`` could not be read ($($failed -join ', ')) - the claim cannot be checked"
            continue
        }
        if (@($counts | Sort-Object -Unique).Count -gt 1) {
            $problems += "AMBIGUOUS   ROADMAP:$($i+1)  ``$rel`` resolves to $($hits.Count) tracked files with different counts ($($counts -join ', ')) - disambiguate it with the FULL repo-relative path, e.g. ``clavity-dotnet/plugin/$rel``"
            continue
        }
        if ($counts[0] -ne $claimed) {
            $problems += "STALE       ROADMAP:$($i+1)  ``$rel`` claims $claimed lines, actual $($counts[0])"
        }
    }
}

# --- B. sha existence beside a closure token -------------------------------------------------------
# CASE-INSENSITIVE, DELIBERATELY. .NET `[regex]` is case-SENSITIVE by default, so a line saying
# "the instructional fix shipped (`33851cf`..`9f6b394`)" carried closure shas that were NEVER
# checked. MEASURED at AGY-CAPSTONE round 6: widening brings 7 more shas into scope, ALL of which
# exist - so this buys coverage and reds nothing today. Checking a sha that turns out to be real is
# free; skipping one that is phantom is the whole failure this guard exists to catch.
$closure = [regex]::new('SHIPPED|RULED|OWNER ACCEPTED|CLOSED', 'IgnoreCase, CultureInvariant')

# A SHALLOW CLONE HAS NO HISTORY, so every `cat-file -e` fails and check B would report EVERY cited
# sha as a phantom. MEASURED at AGY-CAPSTONE round 8: `git clone --depth 1` of this repository gave
# 43 PHANTOM lines and exit 1 where the full clone exits 0. That is a false accusation, not a
# finding - and it is what CI would have produced, because `actions/checkout` is shallow by default
# and the dev-scripts job had no deepen step. Say it in ONE line instead, and still FAIL: a check
# that cannot run must never report clean.
$isShallow = ((& git -C $RepoRoot rev-parse --is-shallow-repository 2>$null) -join '').Trim() -eq 'true'
# RANGES AND UPPERCASE, both measured at AGY-CAPSTONE round 8.
#  * RANGE: the old pattern demanded a backtick immediately after the hex, so this repository's own
#    dominant notation - `a..b` in ONE code span - matched nothing and the whole line was skipped.
#    MEASURED on the committed ROADMAP: 3 closure lines carry a range, hiding SIX shas the guard
#    never looked at, while it printed "every closure sha holds". A LIVE miss, not a latent one.
#  * CASE: `[0-9a-f]` rejected an uppercase sha, which git resolves happily (measured: `cat-file -e`
#    on an upper-cased HEAD exits 0). Latent - zero uppercase shas in the ROADMAP today - and the
#    third sibling of the case class folded in rounds 6 and 7.
$shaRe   = [regex]'`([0-9a-fA-F]{7,40})(?:\.\.([0-9a-fA-F]{7,40}))?`'
$seen    = @{}
$shaCount = 0
for ($i = 0; $i -lt $lines.Count; $i++) {
    if (-not $closure.IsMatch($lines[$i])) { continue }
    if ($isShallow) { $shaCount += $shaRe.Matches($lines[$i]).Count; continue }
    foreach ($m in $shaRe.Matches($lines[$i])) {
        # BOTH endpoints of a range, not only the first - Groups[2] is empty for a bare sha.
        foreach ($s in @($m.Groups[1].Value, $m.Groups[2].Value)) {
            if (-not $s) { continue }
            $key = "$s|$($i+1)"
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            & git -C $RepoRoot cat-file -e "$s^{commit}" 2>$null
            if ($LASTEXITCODE -ne 0) {
                $problems += "PHANTOM     ROADMAP:$($i+1)  ``$s`` does not exist in this repository"
            }
        }
    }
}

if ($isShallow) {
    $problems += "SHALLOW     this repository has no history, so $shaCount cited sha(s) could not be verified - deepen the checkout (git fetch --unshallow) and re-run"
}

if ($problems.Count -gt 0) {
    foreach ($p in $problems) { Write-Host $p -ForegroundColor Red }
    Write-Host ""
    Write-Host "check-roadmap-claims: $($problems.Count) false claim(s) in $RoadmapPath" -ForegroundColor Red
    exit 1
}
Write-Host "check-roadmap-claims: OK - every line-count claim and closure sha in $RoadmapPath holds" -ForegroundColor Green
exit 0

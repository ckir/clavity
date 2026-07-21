#!/usr/bin/env pwsh
[CmdletBinding()]
# $RepoRoot is an explicit parameter defaulting to the script's own repo (self-anchoring — runs from
# anywhere). Both the git sweep (via `git -C $RepoRoot`, see release-lib.ps1) and the version-file reads
# below (Join-Path $RepoRoot ...) target this one root, so they can never diverge. A test points the whole
# engine at a throwaway repo with `-RepoRoot $TempRepo` (agy-reviewed fix C, 2026-07-13).
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [switch]$BaselineOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib' 'release-lib.ps1')

$baseline = Get-BaselineSha $RepoRoot
if ($BaselineOnly) { return $baseline }
$serial = Get-NextSerial $RepoRoot
$range  = if ($baseline) { "$baseline..HEAD" } else { 'HEAD' }

# Collect {Sha, Subject} per commit touching ANY of $pathspecs. One git call, so a commit touching several
# of them (its own folder AND a shared asset) is returned once — git de-duplicates, we don't have to.
function Get-CommitRecords([string[]]$pathspecs) {
    if (-not $pathspecs -or $pathspecs.Count -eq 0) { return @() }
    # Out-String first: `git log` is captured as a string[] (one element per line), so splitting the array
    # directly shatters multi-line records (plan-review R1). Join to one string, then split on NUL.
    $out = (git -C $RepoRoot log $range --format="%x00%H%x1f%s" -- @pathspecs 2>$null | Out-String)
    if (-not $out) { return @() }
    $records = @()
    foreach ($rec in ($out -split "`0" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })) {
        $parts = $rec -split "`u{1f}", 2
        if ($parts.Count -lt 2) { continue }
        $records += [pscustomobject]@{ Sha=$parts[0].Trim(); Subject=$parts[1].Trim() }
    }
    return $records
}

$bumps = @(); $nonConv = @()
foreach ($m in Get-Members) {
    # Shared assets that ship into this member (installer/_shared/**, seed/**, build/members.json). Without
    # these, a commit touching only shared paths bumps nobody and the run reports a silent "nothing to
    # release" — the bug that stranded the 69ee30f registration fix.
    $shared = @(Get-SharedPathsFor $m.Key)
    if ($m.Ghidrust) {
        foreach ($ch in @('binary','plugin')) {
            # commits whose changed paths fall in this channel. Shared assets are INSTALLER assets, so they
            # belong to the binary channel; the plugin channel versions ghidrust/plugin/** alone.
            $records = @(Get-ChannelRecords -Range $range -Channel $ch -RepoRoot $RepoRoot)
            if ($ch -eq 'binary' -and $shared.Count) {
                $seen = @($records | ForEach-Object { $_.Sha })
                $records += @(Get-CommitRecords $shared | Where-Object { $_.Sha -notin $seen })
            }
            $subjects = @($records | ForEach-Object { $_.Subject })
            $conv = @($subjects | Where-Object { Test-Conventional $_ })
            $nc   = @($subjects | Where-Object { -not (Test-Conventional $_) })
            if ($nc.Count) { $nonConv += [pscustomobject]@{ Key="ghidrust ($ch)"; Subjects=$nc } }
            $level = Get-BumpLevel $conv
            if ($level -eq 'none') { continue }
            $curFile = if ($ch -eq 'binary') { $m.Iss } else { $m.PluginJson }
            $current = if ($ch -eq 'binary') { Read-IssVersion (Join-Path $RepoRoot $curFile) } else { Read-JsonVersion (Join-Path $RepoRoot $curFile) }
            $bumps += [pscustomobject]@{ Key='ghidrust'; Channel=$ch; Root=$m.Root; Current=$current;
                Next=(Step-SemverVersion $current $level); Level=$level; CommitCount=$conv.Count; Notes=(Group-Notes $conv) }
        }
        continue
    }
    $subjects = @(Get-CommitRecords (@("{0}/" -f $m.Root) + $shared) | ForEach-Object { $_.Subject })
    $conv = @($subjects | Where-Object { Test-Conventional $_ })
    $nc   = @($subjects | Where-Object { -not (Test-Conventional $_) })
    if ($nc.Count) { $nonConv += [pscustomobject]@{ Key=$m.Key; Subjects=$nc } }
    $level = Get-BumpLevel $conv
    if ($level -eq 'none') { continue }
    $current = Read-IssVersion (Join-Path $RepoRoot $m.Iss)
    $bumps += [pscustomobject]@{ Key=$m.Key; Channel=$null; Root=$m.Root; Current=$current;
        Next=(Step-SemverVersion $current $level); Level=$level; CommitCount=$conv.Count; Notes=(Group-Notes $conv) }
}

# Default-deny half of the taxonomy (see $SharedPaths in release-lib.ps1). Every path touched in the range
# must be member-bound, declared-shared, or explicitly dev-only; anything else is UNCLASSIFIED and
# release.ps1 refuses the release outright — NOT only on a zero-bump run. Gating on zero bumps looks
# sufficient but isn't: an undeclared shared asset committed ALONGSIDE any member-scoped change produces a
# bump, so `Nothing` is false and the undeclared asset would sail through on a warning, silently missing
# every other member that ships it (agy adversarial review, 2026-07-21). An unclassified path is an illegal
# state on its own terms.
#
# Restricted to paths that still EXIST: with no baseline commit $range is all of HEAD, so the sweep sees
# every path that ever existed and long-deleted ones would bucket as unclassified and fail a first release
# for nothing. A deleted shared asset is still caught — by Assert-SharedMapHealthy, whose declared entries
# must exist on disk.
$touched = @(git -C $RepoRoot log $range --name-only --format='' 2>$null |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne '' -and (Test-Path (Join-Path $RepoRoot $_)) } | Sort-Object -Unique)
$unclassified = @($touched | Where-Object { (Get-PathBucket $_) -eq 'unclassified' })

[pscustomobject]@{
    Serial=$serial; Baseline=$baseline; Nothing=($bumps.Count -eq 0); Bumps=$bumps; NonConventional=$nonConv
    Unclassified=$unclassified
}

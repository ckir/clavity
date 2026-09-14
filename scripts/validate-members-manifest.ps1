<#
.SYNOPSIS
CI guard (Acceptance #7 / C9): asserts build/members.json has exactly 4 members, each with a
name/source/marketplaceName, and that all 4 marketplaceName values are pairwise DISTINCT (a
collision silently steals the namespace and breaks every previously-installed member's plugin
resolution — Failure mode B). Was 5 until ghidrust's full retirement (2026-09-14).
#>
$ErrorActionPreference = "Stop"
$root = Get-Content "$PSScriptRoot/../build/members.json" -Raw | ConvertFrom-Json
$members = $root.members
if ($members.Count -ne 4) { throw "expected 4 members in build/members.json, found $($members.Count)" }

foreach ($m in $members) {
    if (-not $m.name) { throw "a member is missing 'name'" }
    if (-not $m.source) { throw "member '$($m.name)' is missing 'source'" }
    if (-not $m.marketplaceName) { throw "member '$($m.name)' is missing 'marketplaceName'" }
}

$names = $members | ForEach-Object { $_.marketplaceName }
$distinct = $names | Select-Object -Unique
if ($distinct.Count -ne 4) {
    throw "marketplaceName collision: expected 4 distinct names, found $($distinct.Count) ($($names -join ', '))"
}
Write-Host "OK: 4 members, 4 distinct marketplaceName values: $($distinct -join ', ')"

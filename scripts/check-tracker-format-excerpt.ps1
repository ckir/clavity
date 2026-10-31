#!/usr/bin/env pwsh
<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

# The tracker-format excerpt in docs/tracker-format.md must appear, byte for byte, in the promote-step skills of BOTH plugins.
# EXIT: 0 every copy equals the canonical block · 1 a copy is missing, duplicated or differs · 2 the canonical block cannot be read.
[CmdletBinding()]
param([string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath }
$begin = '<!-- tracker-format:begin -->'; $end = '<!-- tracker-format:end -->'
# EXPLICIT list: the suite's real-repo row proves it equals the set of skills that carry a promote step.
# (PowerShell variable names are CASE-INSENSITIVE: the loop variable below is $skill, never $s/$S next to another $S.)
$skills = foreach ($plugin in 'clavity-dotnet', 'clavity-classic') { foreach ($skill in 'open-issues', 'agy-capstone', 'agy-test-audit') { "$plugin/plugin/skills/$skill/SKILL.md" } }

function Get-Blocks([string]$Rel) {
    $path = Join-Path $RepoRoot ($Rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $t = [IO.File]::ReadAllText($path) -replace "`r`n", "`n"
    $found = [System.Collections.Generic.List[string]]::new(); $i = 0
    while (($b = $t.IndexOf($begin, $i, [StringComparison]::Ordinal)) -ge 0) {
        $e = $t.IndexOf($end, $b, [StringComparison]::Ordinal); if ($e -lt 0) { break }
        $found.Add($t.Substring($b + $begin.Length, $e - $b - $begin.Length).Trim()); $i = $e + $end.Length
    }
    return , $found.ToArray()
}

$canon = Get-Blocks 'docs/tracker-format.md'
if ($null -eq $canon -or $canon.Count -ne 1 -or -not $canon[0]) { Write-Host 'check-tracker-format-excerpt: docs/tracker-format.md must contain exactly one non-empty excerpt block' -ForegroundColor Yellow; exit 2 }
$bad = 0
foreach ($rel in $skills) {
    $b = Get-Blocks $rel
    if ($null -eq $b)             { Write-Host "EXCERPT-MISSING    $rel (file not found)" -ForegroundColor Red; $bad++ }
    elseif ($b.Count -eq 0)       { Write-Host "EXCERPT-MISSING    $rel" -ForegroundColor Red; $bad++ }
    elseif ($b.Count -gt 1)       { Write-Host "EXCERPT-DUPLICATE  $rel" -ForegroundColor Red; $bad++ }
    elseif ($b[0] -cne $canon[0]) { Write-Host "EXCERPT-DRIFT      $rel" -ForegroundColor Red; $bad++ }
}
if ($bad -gt 0) { Write-Host "check-tracker-format-excerpt: $bad of $(@($skills).Count) copies are wrong" -ForegroundColor Red; exit 1 }
Write-Host "check-tracker-format-excerpt: OK - $(@($skills).Count) copies equal docs/tracker-format.md" -ForegroundColor Green
exit 0

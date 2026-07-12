#!/usr/bin/env pwsh
[CmdletBinding()]
param([switch]$BaselineOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'lib' 'release-lib.ps1')

$baseline = Get-BaselineSha
if ($BaselineOnly) { return $baseline }
$serial = Get-NextSerial
$range  = if ($baseline) { "$baseline..HEAD" } else { 'HEAD' }

# Collect (subject, changed-paths) per commit ONCE, scoped per member below.
function Get-CommitsTouching([string]$pathspec) {
    # Out-String first: `git log` is captured as a string[] (one element per line), so splitting the array
    # directly shatters multi-line records (plan-review R1). Join to one string, then split on NUL.
    $out = (git log $range --format='%x00%s' -- $pathspec 2>$null | Out-String)
    if (-not $out) { return @() }
    return @($out -split "`0" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

$bumps = @(); $nonConv = @()
foreach ($m in Get-Members) {
    if ($m.Ghidrust) {
        foreach ($ch in @('binary','plugin')) {
            # subjects for commits whose changed paths fall in this channel
            $subjects = Get-ChannelSubjects -Range $range -Channel $ch
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
    $subjects = Get-CommitsTouching ("{0}/" -f $m.Root)
    $conv = @($subjects | Where-Object { Test-Conventional $_ })
    $nc   = @($subjects | Where-Object { -not (Test-Conventional $_) })
    if ($nc.Count) { $nonConv += [pscustomobject]@{ Key=$m.Key; Subjects=$nc } }
    $level = Get-BumpLevel $conv
    if ($level -eq 'none') { continue }
    $current = Read-IssVersion (Join-Path $RepoRoot $m.Iss)
    $bumps += [pscustomobject]@{ Key=$m.Key; Channel=$null; Root=$m.Root; Current=$current;
        Next=(Step-SemverVersion $current $level); Level=$level; CommitCount=$conv.Count; Notes=(Group-Notes $conv) }
}

[pscustomobject]@{
    Serial=$serial; Baseline=$baseline; Nothing=($bumps.Count -eq 0); Bumps=$bumps; NonConventional=$nonConv
}

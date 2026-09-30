#!/usr/bin/env pwsh
# check-control-bytes - fail when a TRACKED Markdown file carries a C0 control byte (other than TAB, LF, CR) or
# DEL. ROADMAP §49: an edit that interprets backslash escapes turns a written '\u0000' or '\b' into a real control
# byte; git then either reclassifies the file as binary (it renders as nothing on GitHub) or - for a backspace -
# still calls it text, so ONLY A BYTE SCAN sees it. Two live instances were repaired on 2026-09-29 (3a1d0bec).
[CmdletBinding()]
param([string]$RepoRoot)
$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }

# Returns one object per offending byte: Path (repo-relative, forward slashes), Line and Column (1-based), Byte.
function Get-ControlByteHits {
    param([string]$RepoRoot, [string[]]$RelPaths)
    foreach ($rel in $RelPaths) {
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $RepoRoot $rel))
        $line = 1; $col = 0
        foreach ($b in $bytes) {
            if ($b -eq 10) { $line++; $col = 0; continue }
            $col++
            if (($b -lt 32 -and $b -ne 9 -and $b -ne 13) -or $b -eq 127) {
                [pscustomobject]@{ Path = $rel.Replace('\', '/'); Line = $line; Column = $col; Byte = [int]$b }
            }
        }
    }
}

# Every TRACKED *.md. FAILS CLOSED: a gate that cannot list the files it guards must not report "ok".
function Get-TrackedMarkdown {
    param([string]$RepoRoot)
    $raw = (& git -C $RepoRoot ls-files -z -- '*.md' 2>$null) -join ''
    if ($LASTEXITCODE -ne 0) { throw "check-control-bytes: 'git ls-files' failed in '$RepoRoot' - cannot list the files this gate guards" }
    @($raw -split "`0" | Where-Object { $_ })
}

function Invoke-ControlByteCheck {
    param([string]$RepoRoot)
    $files = @(Get-TrackedMarkdown -RepoRoot $RepoRoot)
    $hits = @(Get-ControlByteHits -RepoRoot $RepoRoot -RelPaths $files)
    if ($hits.Count -eq 0) { Write-Host "control bytes ok ($($files.Count) tracked *.md files scanned)"; exit 0 }
    foreach ($h in $hits) { Write-Host ("{0}:{1}:{2} byte=0x{3:X2}" -f $h.Path, $h.Line, $h.Column, $h.Byte) }
    Write-Host "check-control-bytes: $($hits.Count) control byte(s). Most often a backslash escape (\u0000, \b, \a, \r) that a tool interpreted - restore the characters the author wrote."
    exit 1
}

# Dot-source / execute split, as in the other gates: the suite dot-sources this file for its functions.
if ($MyInvocation.InvocationName -ne '.') { Invoke-ControlByteCheck -RepoRoot $RepoRoot }

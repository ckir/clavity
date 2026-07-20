#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Reject a pending drain atomically (F31): git-restore every tracked drain output, remove new untracked outputs,
  AND restore the app-data staging snapshot into ## Pending, then delete staging. Refuses if committed (F33).
.PARAMETER InboxPath
  The app-data inbox (default: CLAVITY_AGY_INBOX or the agy-autotrain install path).
.PARAMETER RepoRoot
  Repo root (default: this script's parent's parent). Overridable for tests.
#>
[CmdletBinding(SupportsShouldProcess)]   # -WhatIf previews the reject without touching the tree
param(
    [string]$InboxPath,
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }

. (Join-Path $PSScriptRoot 'drain-lib.ps1')   # param-less: no $InboxPath/$RepoRoot clobber (F-P1)

function ConvertTo-DrainNormalizedPath([string]$Path) {
    # repo-relative, forward-slash, no trailing slash — the comparison shape for both `git status` paths and
    # Get-DrainOutputPaths entries.
    return ($Path -replace '\\', '/').TrimEnd('/')
}

function Get-ModifiedTrackedPaths([string]$RepoRoot) {
    # Parses `git status --porcelain --untracked-files=no` into a flat list of repo-relative, forward-slash
    # paths for every tracked file that is modified/staged/conflicted. Porcelain v1 is FIXED-WIDTH: columns 1-2
    # are the XY status code, column 3 is always a single separator space, and the path field starts at column 4
    # (index 3) — so we slice by position instead of splitting on whitespace (a path can legitimately contain
    # spaces, which git does NOT quote). A rename/copy entry additionally embeds ' -> ' between the old and new
    # path inside that same field; only the NEW path (the one that still exists in the working tree) matters
    # here. Git DOES C-quote a path (wraps it in double quotes with backslash escapes) when it contains a double
    # quote, a backslash, or — under the default core.quotepath=true — non-ASCII bytes; unwrap that.
    $lines = & git -C $RepoRoot status --porcelain --untracked-files=no 2>$null
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @($lines)) {
        if (-not $line -or $line.Length -lt 4) { continue }
        $xy = $line.Substring(0, 2)
        $field = $line.Substring(3)
        if ($xy -match 'R|C') {
            $arrow = $field.IndexOf(' -> ')
            if ($arrow -ge 0) { $field = $field.Substring($arrow + 4) }
        }
        if ($field.Length -ge 2 -and $field[0] -eq '"' -and $field[$field.Length - 1] -eq '"') {
            $field = ($field.Substring(1, $field.Length - 2) -replace '\\"', '"') -replace '\\\\', '\'
        }
        $paths.Add((ConvertTo-DrainNormalizedPath $field))
    }
    return $paths
}

function Test-PathOwnedByDrain([string]$NormalizedPath, [string[]]$OwnedPaths) {
    # $OwnedPaths (Get-DrainOutputPaths — the single source of truth) may name either a file or a directory
    # (e.g. 'docs/fix-the-tool-backlog'); a modified path counts as owned if it IS that entry or lives under it.
    foreach ($owned in $OwnedPaths) {
        $ownedNorm = ConvertTo-DrainNormalizedPath $owned
        if ($NormalizedPath -ieq $ownedNorm) { return $true }
        if ($NormalizedPath.StartsWith($ownedNorm + '/', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-UnrelatedTrackedChanges([string]$RepoRoot) {
    # Every modified/staged TRACKED file that is NOT one of the drain's own outputs — i.e. work `git reset --hard`
    # would silently destroy but did not come from this drain.
    $owned = Get-DrainOutputPaths
    return @(Get-ModifiedTrackedPaths -RepoRoot $RepoRoot | Where-Object { -not (Test-PathOwnedByDrain -NormalizedPath $_ -OwnedPaths $owned) })
}

function Invoke-Main {
    $inbox = Resolve-InboxPath $InboxPath
    $inboxDir = Split-Path $inbox -Parent
    $staging = Find-StagingFile $inboxDir
    if (-not $staging) {
        Write-Host "abort-drain: no pending drain (no staging file). Nothing to abort." -ForegroundColor Green
        exit 0
    }
    $runId = Get-RunIdFromStaging $staging

    # F33: if the run is already committed, aborting would re-queue committed observations — block.
    $committedLog = & git -C $RepoRoot show 'HEAD:docs/agy-drain-log.md' 2>$null
    if ($LASTEXITCODE -eq 0 -and (Test-RunIdInLog -LogText ($committedLog -join "`n") -RunId $runId)) {
        Write-Host "abort-drain: run $runId is ALREADY in the committed drain-log — use 'just accept-drain' instead." -ForegroundColor Red
        exit 1
    }

    if (-not $PSCmdlet.ShouldProcess($RepoRoot, "revert drain outputs + re-queue staging into ## Pending (reject run $runId)")) { return }

    # DATA-LOSS GUARD: the drain ran on a PRISTINE tree (drain-knowledge pre-drain guard), but that only covers
    # drain START — the documented workflow (docs/drain-knowledge-runbook.md) requires a human REVIEW PAUSE
    # between `just drain-knowledge` and `just abort-drain` so the maintainer can inspect `git diff`, and it is
    # normal for unrelated uncommitted work (a quick fix, a note, a test tweak) to land during that pause. `git
    # reset --hard HEAD` below is unscoped, so without this check any such work would be silently destroyed.
    # Refuse instead of guessing intent: proceed ONLY if every modified/staged TRACKED file is one of the
    # drain's own outputs (Get-DrainOutputPaths — the single source of truth, not re-listed here).
    $unrelated = @(Get-UnrelatedTrackedChanges -RepoRoot $RepoRoot)   # @() wrap: PS unrolls an empty array return to $null otherwise, and .Count below would throw under Strict Mode
    if ($unrelated.Count -gt 0) {
        Write-Host "abort-drain: REFUSING to abort — the working tree has tracked change(s) that are NOT part of this drain's outputs:" -ForegroundColor Red
        foreach ($f in $unrelated) { Write-Host "  $f" -ForegroundColor Red }
        Write-Host "abort-drain: 'git reset --hard HEAD' would silently DESTROY the file(s) above. Commit or stash that work, then re-run 'just abort-drain'. Staging ($staging) was NOT touched." -ForegroundColor Red
        exit 1
    }

    # Atomic reject. With the guard above satisfied, reverting ALL tracked files to HEAD is safe — the only
    # tracked changes are this drain's — and complete (it also catches a curator edit to a tracked file OUTSIDE
    # the known outputs, since the guard above would already have caught and refused it). Untracked strays
    # outside the known output dirs are NOT force-cleaned (never blind-delete unrelated files —
    # [[feedback-targeted-git-restore]]); they are surfaced.
    & git -C $RepoRoot reset --hard HEAD 2>$null                    # revert every tracked file to HEAD (index+worktree; handles staged outputs)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "abort-drain: 'git reset --hard HEAD' FAILED (exit $LASTEXITCODE) — tree NOT reverted; staging ($staging) retained. Fix the repo and re-run." -ForegroundColor Red
        exit 1
    }
    & git -C $RepoRoot clean -fd -- (Get-DrainOutputPaths) 2>$null  # remove the drain's own untracked outputs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "abort-drain: 'git clean' FAILED (exit $LASTEXITCODE) — staging ($staging) retained. Fix the repo and re-run." -ForegroundColor Red
        exit 1
    }
    $strays = & git -C $RepoRoot status --porcelain
    if ($strays) {
        Write-Host "abort-drain: NOTE — file(s) still differ from HEAD (a possible curator stray outside the known outputs); review + remove by hand if unwanted:`n$strays" -ForegroundColor Yellow
    }

    Restore-StagingToPending -InboxPath $inbox -StagingPath $staging
    Remove-Item -Force $staging
    Write-Host "abort-drain: rejected run $runId — outputs restored, $((Split-Path $staging -Leaf)) re-queued into ## Pending and removed." -ForegroundColor Green
    exit 0
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-Main }

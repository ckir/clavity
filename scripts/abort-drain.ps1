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

    # Atomic reject. The drain ran on a PRISTINE tree (drain-knowledge pre-drain guard), so reverting ALL tracked
    # files to HEAD is safe — the only tracked changes are this drain's — and complete (it also catches a curator
    # edit to a tracked file OUTSIDE the known outputs). Untracked strays outside the known output dirs are NOT
    # force-cleaned (never blind-delete unrelated files — [[feedback-targeted-git-restore]]); they are surfaced.
    & git -C $RepoRoot checkout -- . 2>$null                        # revert every tracked file to HEAD
    if ($LASTEXITCODE -ne 0) {
        Write-Host "abort-drain: 'git checkout -- .' FAILED (exit $LASTEXITCODE) — tree NOT reverted; staging ($staging) retained. Fix the repo and re-run." -ForegroundColor Red
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

#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Accept a pending drain: prove the run-ID is in the COMMITTED drain-log (F30) AND every tracked drain-output path
  is clean in the working tree (F34), then delete the app-data staging snapshot. Does not touch the inbox.
.PARAMETER InboxPath
  The app-data inbox (default: CLAVITY_AGY_INBOX or the agy-autotrain install path).
.PARAMETER RepoRoot
  Repo root (default: this script's parent's parent). Overridable for tests.
#>
[CmdletBinding(SupportsShouldProcess)]   # -WhatIf previews the accept without deleting staging
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
        Write-Host "accept-drain: no pending drain (no staging file). Nothing to accept." -ForegroundColor Green
        exit 0
    }
    $runId = Get-RunIdFromStaging $staging

    # F30: the run must be COMMITTED (git show HEAD), not merely written to the working-tree log.
    $committedLog = & git -C $RepoRoot show 'HEAD:docs/agy-drain-log.md' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not (Test-RunIdInLog -LogText ($committedLog -join "`n") -RunId $runId)) {
        Write-Host "accept-drain: run $runId is NOT in the committed drain-log. Commit the drain first (git add + commit), then re-run — or 'just abort-drain' to reject." -ForegroundColor Red
        exit 1
    }

    # F34 + C1: require the WHOLE tree clean (not just the output allowlist). The drain ran on a pristine tree, so a
    # clean whole tree ⟺ every file the curator touched — INCLUDING any hallucinated stray path outside the known
    # outputs — was committed. An allowlist-scoped check would let such a stray (or an uncommitted manual) slip past.
    $dirty = & git -C $RepoRoot status --porcelain
    if ($LASTEXITCODE -ne 0) {
        Write-Host "accept-drain: 'git status' FAILED (exit $LASTEXITCODE) — cannot confirm a clean tree; staging ($staging) retained. Fix the repo and re-run." -ForegroundColor Red
        exit 1
    }
    if ($dirty) {
        Write-Host "accept-drain: uncommitted drain outputs remain — commit them before accepting:`n$dirty" -ForegroundColor Red
        exit 1
    }

    if ($PSCmdlet.ShouldProcess($staging, "delete staging snapshot (accept run $runId)")) {
        Remove-Item -Force $staging
    }
    Write-Host "accept-drain: accepted run $runId — staging snapshot deleted (or previewed under -WhatIf)." -ForegroundColor Green
    exit 0
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-Main }

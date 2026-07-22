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
    [string]$RepoRoot,
    # Test seam: a PATH to a stub .ps1 (param $growthPath) that returns 'published' | 'nothing-to-publish' |
    # 'no-driver' | 'failed'. Empty in production → the real resolver+invoker below runs. A stub-script PATH (NOT a
    # [scriptblock]) because a live scriptblock does NOT survive marshalling into a nested `pwsh -File` child —
    # PowerShell substitutes the literal "-encodedCommand" for it and the binder throws (measured on pwsh 7.6.3).
    # Purely test-scaffolding; production behavior is unchanged.
    [string]$CurateCommitStub
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
    $manifestPath = Get-DrainOutputManifestPath $inboxDir $runId   # may not exist — a run that predates this feature

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

    # Publish the reviewed, committed GROWTH proposal to the runtime header via the binary's curate-commit. This
    # is the ONLY point the runtime ~/.clavity/golden-header.growth.md is written — drain-knowledge never touches
    # it, so a rejected drain (abort) needs no runtime rollback. Run BEFORE deleting staging: if the publish
    # fails, staging is retained so a re-run retries (the proposal is committed and durable regardless).
    $growthProposal = Join-Path $RepoRoot 'docs/agy-golden-header.growth.md'
    # Gate the runtime write behind ShouldProcess so `just accept-drain -WhatIf` PREVIEWS it instead of performing
    # a real mutation to ~/.clavity/golden-header.growth.md during a dry run (panel F1/agy-A3). Under -WhatIf this
    # block is skipped entirely and the staging-delete ShouldProcess below is likewise previewed — a true no-op.
    if ($PSCmdlet.ShouldProcess($growthProposal, "publish the committed GROWTH proposal to the runtime header via curate-commit")) {
        # Resolve the publish outcome. A unit test injects $CurateCommitStub — a PATH to a stub .ps1 returning one of
        # the four outcome strings — so the suite never needs a real clavity binary. In production $CurateCommitStub is
        # empty and the real resolver+invoker runs inline. (Seam is a PATH, not a [scriptblock] — see the param note.)
        if ($CurateCommitStub) {
            $publishResult = & $CurateCommitStub $growthProposal
        } else {
            if (-not (Test-Path $growthProposal)) { $publishResult = 'nothing-to-publish' }   # docs-only drain: no GROWTH to publish
            else {
                $exe = Resolve-CurateCommitExe
                if (-not $exe) { $publishResult = 'no-driver' }
                else {
                    $code = Invoke-CurateCommit -Exe $exe -GrowthPath $growthProposal
                    $publishResult = if ($code -eq 0) { 'published' } else { 'failed' }
                }
            }
        }
        switch ($publishResult) {
            'published' { Write-Host "accept-drain: published GROWTH to the runtime header via curate-commit." -ForegroundColor Green }
            'nothing-to-publish' { Write-Host "accept-drain: no GROWTH proposal to publish (a docs-only drain) — runtime header unchanged." -ForegroundColor Green }
            'no-driver' {
                # RETAIN staging + exit 1 so the recovery is REAL (panel agy-R2-3). The runtime publish has NOT
                # happened, so the transaction is NOT complete — falling through to delete staging would leave the
                # message "re-run accept-drain" pointing at a transaction that no longer exists, and the reviewed
                # knowledge would never reach the runtime. Keeping staging means re-running 'just accept-drain' after
                # a driver is installed finds the pending drain and finishes it. Recovery must NOT be a hand-piped
                # `< file` / `Get-Content | curate-commit` command — in PowerShell that re-encodes through the
                # console code page (CP437 mojibake), the exact corruption Invoke-CurateCommit's raw-byte path avoids.
                Write-Host "accept-drain: no clavity driver on PATH — runtime header NOT updated; the drain is committed but NOT yet live. Staging ($staging) retained. Install a clavity driver and re-run 'just accept-drain' to finish publishing (do NOT hand-pipe the file — that risks console-codepage mojibake)." -ForegroundColor Yellow
                exit 1
            }
            default {
                Write-Host "accept-drain: curate-commit FAILED to publish the GROWTH proposal — staging ($staging) retained; fix and re-run 'just accept-drain'." -ForegroundColor Red
                exit 1
            }
        }
    }

    if ($PSCmdlet.ShouldProcess($staging, "delete staging snapshot (accept run $runId)")) {
        Remove-Item -Force $staging
        if (Test-Path $manifestPath) { Remove-Item -Force $manifestPath }   # transient run state; never outlives its run — absence is not an error
    }
    Write-Host "accept-drain: accepted run $runId — staging snapshot deleted (or previewed under -WhatIf)." -ForegroundColor Green
    exit 0
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-Main }

#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Drain machine-local agy-learn captures into the shippable manuals + injected SEED via a headless claude -p
  curator, then run the deterministic [Core]/budget gates. Makes NO commit — the maintainer reviews git diff and
  runs `just accept-drain` or `just abort-drain`. Dev-only; never ships.
.PARAMETER InboxPath
  The app-data inbox. Default from CLAVITY_AGY_INBOX, else the agy-autotrain install path.
.PARAMETER SkipCurator
  Test hook: skip the live claude -p call (the curator is mocked in unit tests).
#>
[CmdletBinding(SupportsShouldProcess)]   # enables -WhatIf / -Confirm dry-run over the mutation block
param(
    [string]$RepoRoot,
    [string]$InboxPath,
    [switch]$SkipCurator
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
. (Join-Path $PSScriptRoot 'drain-lib.ps1')   # param-less shared primitives — safe dot-source (F-P1)

function Invoke-Curator([string]$StagingPath) {
    # The single external boundary; Mocked in unit tests. Dev-only maintainer box → skip permission prompts.
    $promptTemplate = Get-Content (Join-Path $PSScriptRoot 'drain-knowledge-prompt.md') -Raw
    $prompt = $promptTemplate.Replace('{{STAGING_PATH}}', $StagingPath).Replace('{{REPO_ROOT}}', $RepoRoot)
    # Headless Claude Code: `-p`/`--print` runs NON-interactively with the prompt as its positional argument (this
    # is the documented headless form — it does NOT drop into the REPL). --dangerously-skip-permissions lets it EDIT
    # files without an approval prompt (dev-only maintainer box). Use the 'opus' ALIAS, not a dated model id, so the
    # invocation doesn't rot when the concrete id changes; override with CLAVITY_DRAIN_MODEL.
    $model = if ($env:CLAVITY_DRAIN_MODEL) { $env:CLAVITY_DRAIN_MODEL } else { 'opus' }
    Push-Location $RepoRoot
    try {
        & claude -p $prompt --dangerously-skip-permissions --model $model
        if ($LASTEXITCODE -ne 0) { throw "claude -p exited $LASTEXITCODE (is the CLI installed and authenticated?)" }
    } finally { Pop-Location }
}

function Invoke-Main {
    $inbox = Resolve-InboxPath $InboxPath
    $inboxDir = Split-Path $inbox -Parent

    # 1. Refuse-guard (F25).
    $existingStaging = Find-StagingFile $inboxDir
    if ($existingStaging) {
        Write-Host "drain-knowledge: a prior drain is pending a human decision (staging: $existingStaging)." -ForegroundColor Yellow
        Write-Host "Resolve it first: 'just accept-drain' (after committing) or 'just abort-drain' (to reject)." -ForegroundColor Yellow
        exit 2
    }

    # 2. Nothing to drain?
    if (-not (Test-Path $inbox) -or (Get-PendingBulletCount $inbox) -eq 0) {
        Write-Host "drain-knowledge: nothing to drain (## Pending is empty)." -ForegroundColor Green
        exit 0
    }

    # 2b. PRISTINE-TREE precondition (Blindspot B1/B2 + Cascade C1). The drain edits several tracked files and the
    # recovery transaction (abort) reverts them; it must run on a clean tree so (a) abort never destroys unrelated
    # uncommitted work (see [[feedback-targeted-git-restore]]) and (b) any file the curator creates — even a
    # hallucinated stray path OUTSIDE the known outputs — is attributable to this drain and visible before accept.
    $preDirty = & git -C $RepoRoot status --porcelain
    if ($LASTEXITCODE -ne 0) {
        Write-Host "drain-knowledge: 'git status' FAILED (exit $LASTEXITCODE) — cannot confirm a clean tree; refusing to drain. Fix the repo and re-run." -ForegroundColor Red
        exit 4
    }
    if ($preDirty) {
        Write-Host "drain-knowledge: working tree is NOT clean — commit or stash ALL changes before draining." -ForegroundColor Red
        Write-Host "The drain needs a pristine tree so its edits are cleanly reviewable and fully abortable.`n$preDirty" -ForegroundColor Red
        exit 4
    }

    # -WhatIf preview: everything above is read-only; skip the whole mutation block on a dry run.
    if (-not $PSCmdlet.ShouldProcess($inbox, "drain pending observations into the 4 manuals + SEED (no commit)")) { return }

    # 3. Snapshot move.
    $runId = New-RunId
    $staging = Join-Path $inboxDir "agy-observations.staging.$runId.md"
    Move-PendingToStaging -InboxPath $inbox -StagingPath $staging
    Write-Host "drain-knowledge: staged pending observations → $staging (run $runId)" -ForegroundColor Cyan

    # 4. SEED bytes before.
    $b0 = Get-SeedBytes $RepoRoot

    # 5. Curator.
    if (-not $SkipCurator) { Invoke-Curator $staging }

    # 6. [Core] integrity — HARD fail (staging retained for abort).
    & pwsh -File (Join-Path $PSScriptRoot 'check-core-integrity.ps1')
    if ($LASTEXITCODE -ne 0) {
        Write-Host "drain-knowledge: [Core]-integrity FAILED — staging retained ($staging). Run 'just abort-drain'." -ForegroundColor Red
        exit 3
    }

    # 7. Budget — WARN only (parked-demotion is a valid state; the hard gate is the release preflight).
    & pwsh -File (Join-Path $PSScriptRoot 'check-seed-budget.ps1')
    if ($LASTEXITCODE -ne 0) {
        Write-Host "drain-knowledge: WARNING — SEED is over budget. The curator should have parked a demotion; the release preflight will BLOCK until you enact it or bump SEED_MAX_BYTES." -ForegroundColor Yellow
    }

    # 8. SEED bytes after + verify-needed count.
    $b1 = Get-SeedBytes $RepoRoot
    $verifyNeeded = 0
    $vnPath = Join-Path $RepoRoot 'docs/agy-verify-needed.md'
    if (Test-Path $vnPath) { $verifyNeeded = @(Get-Content $vnPath | Where-Object { $_ -match '^- ' }).Count }

    # 9. Drain-log (append-only; carries the full sidecar so dropped/parked verbatim survive — F11).
    $logPath = Join-Path $RepoRoot 'docs/agy-drain-log.md'
    # D2 (LF-write discipline): append via System.IO with explicit LF, matching drain-lib.ps1's writes.
    # Set-Content/Add-Content would emit OS-native CRLF terminators, giving this committed, maintainer-diffed
    # log mixed line endings across entries.
    if (-not (Test-Path $logPath)) { [System.IO.File]::WriteAllText($logPath, "# agy drain log (append-only; installer-excluded)`n") }
    $utc = (Get-Date).ToUniversalTime().ToString('u')
    $header = "`n## drain $runId — $utc — SEED ${b0}B->${b1}B — verify-needed: $verifyNeeded"
    $sidecarPath = Join-Path $RepoRoot 'docs/agy-drain-proposal.md'
    [System.IO.File]::AppendAllText($logPath, $header + "`n" + (Get-SidecarRecoverySections $sidecarPath) + "`n")   # R-V1: only Dropped/Parked (F11)

    # 10. Banners.
    Write-Host "drain-knowledge: done (run $runId). SEED ${b0}B -> ${b1}B, verify-needed: $verifyNeeded." -ForegroundColor Green
    Write-Host "REVIEW the golden-header.seed.md diff: confirm NO [SEED-tier] rule was dropped by an LLM formatting error (cross-check docs/agy-drain-log.md for a matching merge/drop entry)." -ForegroundColor Yellow
    Write-Host "Next: git diff → then 'git add' + commit → 'just accept-drain'   OR   'just abort-drain' to reject." -ForegroundColor Cyan
    exit 0
}

# Run main only when executed directly (dot-source for tests must NOT run it).
if ($MyInvocation.InvocationName -ne '.') { Invoke-Main }

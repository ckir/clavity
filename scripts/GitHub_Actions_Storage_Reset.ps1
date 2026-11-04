<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

# ============================================
# GitHub Actions Storage Reset Script (Windows)
# ============================================

param(
    [switch]$NonInteractive,  # skip the y/N prompts and proceed with deletions (lets an agent run it unattended)
    # Owner (org) whose Actions usage is reported. Default: the owner of the current repo as `gh` sees it,
    # falling back to the original literal when `gh repo view` cannot say (not in a repo, not logged in).
    [string]$Owner
)
Set-StrictMode -Version Latest
$script:Failures = 0

Write-Host "=== GitHub Actions Storage Reset ===" -ForegroundColor Cyan

if (-not $Owner) {
    $detected = & gh repo view --json owner -q .owner.login 2>$null
    $Owner = if ($LASTEXITCODE -eq 0 -and $detected) { "$detected".Trim() } else { 'ckir' }
}

# Check for gh CLI
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) is not installed or not in PATH."
    exit 1
}

# --------------------------------------------
# 1. LIST CACHES
# --------------------------------------------
Write-Host "`nListing caches..." -ForegroundColor Yellow
$cacheList = gh cache list
if ($LASTEXITCODE -ne 0) {
    Write-Host "gh cache list failed (exit $LASTEXITCODE)." -ForegroundColor Red
    $script:Failures++
}

if (-not $cacheList) {
    Write-Host "No caches found." -ForegroundColor Green
} else {
    $cacheList
}

# --------------------------------------------
# 2. DELETE CACHES
# --------------------------------------------
if ($NonInteractive) {
    $confirmCaches = "y"
    Write-Host "`n[NonInteractive] Deleting ALL caches..." -ForegroundColor Yellow
} else {
    Write-Host "`nDelete ALL caches? (y/N)" -ForegroundColor Yellow
    $confirmCaches = Read-Host
}

if ("$confirmCaches".ToLower() -eq "y") {
    Write-Host "Deleting caches..." -ForegroundColor Red
    gh cache delete --all
    if ($LASTEXITCODE -ne 0) {
        Write-Host "gh cache delete --all FAILED (exit $LASTEXITCODE); caches were NOT (all) deleted." -ForegroundColor Red
        $script:Failures++
    } else {
        Write-Host "All caches deleted." -ForegroundColor Green
    }
} else {
    Write-Host "Skipping cache deletion." -ForegroundColor Yellow
}

# --------------------------------------------
# 3. LIST WORKFLOW RUNS
# --------------------------------------------
Write-Host "`nListing workflow runs..." -ForegroundColor Yellow
# Fetch up to 500 runs (API limit is usually higher but 500 is a safe batch)
$runJson = gh run list --limit 500 --json databaseId,name,status,createdAt
if ($LASTEXITCODE -ne 0) {
    Write-Host "gh run list failed (exit $LASTEXITCODE); cannot list workflow runs." -ForegroundColor Red
    $script:Failures++
    $Runs = $null
} else {
    $Runs = $runJson | ConvertFrom-Json
}

if (-not $Runs) {
    Write-Host "No workflow runs found." -ForegroundColor Green
} else {
    $Runs | Format-Table databaseId, name, status, createdAt
}

# --------------------------------------------
# 4. DELETE WORKFLOW RUNS
# --------------------------------------------
if ($NonInteractive) {
    $confirmRuns = "y"
    Write-Host "`n[NonInteractive] Deleting ALL displayed workflow runs..." -ForegroundColor Yellow
} else {
    Write-Host "`nDelete ALL displayed workflow runs? (y/N)" -ForegroundColor Yellow
    $confirmRuns = Read-Host
}

if ("$confirmRuns".ToLower() -eq "y") {
    if (-not $Runs) {
        Write-Host "Nothing to delete." -ForegroundColor Green
    } else {
        Write-Host "Deleting $($Runs.Count) workflow runs with 16-way parallelism..." -ForegroundColor Red
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            # Each parallel block emits its run id ONLY when gh failed, so $failed is the failure list.
            $failed = @($Runs.databaseId | ForEach-Object -Parallel {
                # No --yes flag: not supported/needed when deleting by ID (gh 2.85.0)
                gh run delete $_ > $null
                if ($LASTEXITCODE -ne 0) { $_ }
            } -ThrottleLimit 16)
        } else {
            # Fallback for Windows PowerShell 5.1 (no ForEach-Object -Parallel)
            $failed = @()
            foreach ($run in $Runs) {
                gh run delete $run.databaseId > $null
                if ($LASTEXITCODE -ne 0) { $failed += $run.databaseId }
            }
        }
        if ($failed.Count -gt 0) {
            Write-Host "Batch deletion INCOMPLETE: $($failed.Count) of $($Runs.Count) run deletion(s) failed (ids: $($failed -join ', '))." -ForegroundColor Red
            $script:Failures++
        } else {
            Write-Host "Batch deletion complete." -ForegroundColor Green
        }
        if ($Runs.Count -ge 500) {
            Write-Host "Hit 500-run batch limit - rerun script to clear remainder." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "Skipping workflow run deletion." -ForegroundColor Yellow
}

# --------------------------------------------
# 5. PRINT USAGE (ORG-LEVEL ONLY)
# --------------------------------------------
Write-Host "`nFetching usage information..." -ForegroundColor Yellow

try {
    # Attempt to get org usage for -Owner (default: the current repo's owner), or rely on the script
    # failing gracefully for personal repos (the endpoint is org-only).
    $usageJson = gh api "orgs/$Owner/actions/permissions/usage" 2>$null
    if ($LASTEXITCODE -ne 0) { throw "gh api exited $LASTEXITCODE" }
    $usage = $usageJson | ConvertFrom-Json
    Write-Host "`n=== Usage Report ===" -ForegroundColor Cyan
    $usage
} catch {
    Write-Host "`nGitHub does not expose usage for user-owned repos via this endpoint." -ForegroundColor Yellow
    Write-Host "This is expected for personal accounts. Usage will drop once GitHub recalculates." -ForegroundColor Yellow
}

if ($script:Failures -gt 0) {
    Write-Host "`nDone WITH $($script:Failures) FAILURE(S) - see the red lines above." -ForegroundColor Red
    exit 1
}
Write-Host "`nDone." -ForegroundColor Cyan

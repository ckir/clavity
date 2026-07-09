# ============================================
# GitHub Actions Storage Reset Script (Windows)
# ============================================

param(
    [switch]$NonInteractive  # skip the y/N prompts and proceed with deletions (lets an agent run it unattended)
)

Write-Host "=== GitHub Actions Storage Reset ===" -ForegroundColor Cyan

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
    Write-Host "All caches deleted." -ForegroundColor Green
} else {
    Write-Host "Skipping cache deletion." -ForegroundColor Yellow
}

# --------------------------------------------
# 3. LIST WORKFLOW RUNS
# --------------------------------------------
Write-Host "`nListing workflow runs..." -ForegroundColor Yellow
# Fetch up to 500 runs (API limit is usually higher but 500 is a safe batch)
$Runs = gh run list --limit 500 --json databaseId,name,status,createdAt | ConvertFrom-Json

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
    Write-Host "Deleting workflow runs..." -ForegroundColor Red
    foreach ($run in $Runs) {
        Write-Host "Deleting run $($run.databaseId)..." -NoNewline
        # Removed --yes flag as it is not supported/needed when deleting by ID
        gh run delete $run.databaseId
        Write-Host " Done." -ForegroundColor Green
    }
    Write-Host "Batch deletion complete." -ForegroundColor Green
} else {
    Write-Host "Skipping workflow run deletion." -ForegroundColor Yellow
}

# --------------------------------------------
# 5. PRINT USAGE (ORG-LEVEL ONLY)
# --------------------------------------------
Write-Host "`nFetching usage information..." -ForegroundColor Yellow

try {
    # Attempt to get org usage. Replace 'ckir' with your actual org name if different,
    # or rely on the script failing gracefully for personal repos.
    $usage = gh api orgs/ckir/actions/permissions/usage | ConvertFrom-Json
    Write-Host "`n=== Usage Report ===" -ForegroundColor Cyan
    $usage
} catch {
    Write-Host "`nGitHub does not expose usage for user-owned repos via this endpoint." -ForegroundColor Yellow
    Write-Host "This is expected for personal accounts. Usage will drop once GitHub recalculates." -ForegroundColor Yellow
}

Write-Host "`nDone." -ForegroundColor Cyan

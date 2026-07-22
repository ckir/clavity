#requires -Version 5.1
# Fail (exit 1) if docs/user-facing-docs.txt lists a path that does not exist, or that docs-spec.md
# classifies do-not-touch (a doc the docs-rationalize tool must never audit). WARN (non-failing) if a
# tracked user-facing-shaped .md is absent from the list. Mirrors check-member-docs.ps1's shape.
#
# The do-not-touch globs below mirror docs/docs-spec.md's "Do-not-touch" list (its lines 53-89), and the
# voice-table shapes mirror its "Docs (audience -> voice)" table (its lines 14-28); both sets are pinned by
# Pester tests. A listed doc must (b1) NOT match a do-not-touch glob AND (b2) POSITIVELY match a voice-table
# shape (Test-HasVoiceEntry): the check confirms voicing directly rather than inferring it from "not
# excluded", because docs-spec.md's in-table-XOR-excluded convention (its lines 94-95) admits a "neither"
# spec-gap case and so is not a guarantee.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# Anchored regexes over a repo-relative, forward-slash path. Each maps to a docs-spec.md do-not-touch bullet.
$script:DoNotTouchPatterns = @(
    '(?i)\.(rs|cs|ps1|sh|yml|iss)$',          # code/script/workflow files
    '(?i)(^|/)LICENSE$',                       # legal text
    '(?i)(^|/)CHANGELOG\.md$',                 # release-injected
    '(?i)(^|/)knowledge/',                     # driver-owned SEED + learning-loop working files
    '(?i)(^|/)SKILL\.md$',                     # behavioural contracts
    '(?i)(^|/)docs/archive/',                  # frozen historical
    '(?i)(^|/)docs/superpowers/',              # working artifacts
    '(?i)(^|/)\.clavity/',                     # working artifacts
    '(?i)(^|/)tests/fixtures/',                # test data
    '(?i)(^|/)\.venv/|(^|/)node_modules/',     # vendored
    '(?i)^scripts/drain-knowledge-prompt\.md$',# a prompt, functionally code
    '(?i)^seed/golden-header\.md$',            # compiled SEED
    '(?i)^commonmemory/rules/commonmemory\.md$',                       # agy rule file
    '(?i)^agy-autotrain/verify/.*\.md$',                              # probe harness
    '(?i)^agy-autotrain/docs/fix-the-tool-backlog/',                  # generated append-only
    '(?i)(^|/)agy-mcp-bridge/VENDORED-FROM\.md$',                     # vendored provenance
    '(?i)^docs/(agy-assumptions|agy-capabilities)\.md$',             # pointer stubs
    '(?i)^clavity-classic/docs/agy-test-suite\.md$',                 # pointer stub
    '(?i)^docs/docs-spec\.md$',               # this file's own governing contract
    '(?i)^installer/_shared/register-plugin-hash\.iss$',            # generated (also caught by .iss)
    '(?i)(^|/)installer/marketplace\.install\.json$'               # generated
)

# A tracked doc "looks user-facing" if its filename is one of these (the (c) heuristic surface).
$script:UserFacingShapes = @(
    '(?i)(^|/)README\.md$', '(?i)(^|/)CONTRIBUTING\.md$', '(?i)^SECURITY\.md$',
    '(?i)^CODE_OF_CONDUCT\.md$', '(?i)^\.github/(pull_request_template|ISSUE_TEMPLATE/.+)\.md$'
)

# Voice-table shapes from docs-spec.md's "Docs (audience -> voice)" table (its lines 14-28). A listed doc
# MUST match one of these (b2) - positive voice confirmation, since docs-spec.md:94-95's XOR convention
# allows a "neither" spec-gap case and is therefore not a guarantee. Test-pinned like the do-not-touch set.
$script:VoiceEntryPatterns = @(
    '(?i)^README\.md$',                        # root README
    '(?i)^[^/]+/README\.md$',                   # <member>/README.md
    '(?i)^[^/]+/plugin/README\.md$',            # <member>/plugin/README.md
    '(?i)^CONTRIBUTING\.md$',                   # umbrella CONTRIBUTING
    '(?i)^[^/]+/CONTRIBUTING\.md$',             # <member>/CONTRIBUTING.md
    '(?i)^SECURITY\.md$',
    '(?i)^CODE_OF_CONDUCT\.md$',
    '(?i)^\.github/pull_request_template\.md$',
    '(?i)^\.github/ISSUE_TEMPLATE/.+\.md$',
    '(?i)^docs/.+\.md$',                        # docs/** (umbrella)
    '(?i)^[^/]+/docs/.+\.md$',                  # <member>/docs/** (incl. the two clavity-classic evaluator docs)
    '(?i)^clavity-classic/installer/.*(MANUAL-SETUP|README-FIRST)\.md$'  # installer operator docs (docs-spec.md:28)
)

function Read-DocList([string]$path) {
    # Contract: returns the trimmed, comment/blank-stripped list of repo-relative paths.
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $out = New-Object System.Collections.ArrayList
    foreach ($line in (Get-Content -LiteralPath $path)) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        [void]$out.Add(($t -replace '\\', '/'))
    }
    return $out.ToArray()
}

function Test-IsDoNotTouch([string]$relPath) {
    $p = $relPath -replace '\\', '/'
    foreach ($rx in $script:DoNotTouchPatterns) { if ($p -match $rx) { return $true } }
    return $false
}

function Test-LooksUserFacing([string]$relPath) {
    $p = $relPath -replace '\\', '/'
    foreach ($rx in $script:UserFacingShapes) { if ($p -match $rx) { return $true } }
    return $false
}

function Test-HasVoiceEntry([string]$relPath) {
    $p = $relPath -replace '\\', '/'
    foreach ($rx in $script:VoiceEntryPatterns) { if ($p -match $rx) { return $true } }
    return $false
}

function Get-TrackedMarkdown([string]$repoRoot) {
    # Returns tracked *.md paths, or $null if git is unavailable / this is not a repo. Guarded because,
    # under ErrorActionPreference='Stop', a bare `& git` with git absent throws CommandNotFoundException
    # (a terminating error that bypasses $LASTEXITCODE); the (c) heuristic must degrade to a silent skip.
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $pushed = $false
    try {
        Push-Location -LiteralPath $repoRoot
        $pushed = $true
        $out = & git ls-files '*.md' 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return @($out | ForEach-Object { $_ -replace '\\', '/' })
    } catch { return $null }
    finally { if ($pushed) { Pop-Location } }
}

function Invoke-UserFacingDocsCheck([string]$repoRoot, [string[]]$TrackedDocs = $null) {
    $failed   = New-Object System.Collections.ArrayList
    $warned   = New-Object System.Collections.ArrayList
    $listPath = Join-Path $repoRoot 'docs/user-facing-docs.txt'

    if (-not (Test-Path -LiteralPath $listPath)) {
        [void]$failed.Add("docs/user-facing-docs.txt not found at $listPath")
        return [PSCustomObject]@{ ExitCode = 1; Failures = $failed.ToArray(); Warnings = @() }
    }

    $listed = Read-DocList $listPath
    if ($listed.Count -eq 0) {
        [void]$failed.Add('docs/user-facing-docs.txt is empty (all comments/blank) - refusing to pass vacuously.')
        return [PSCustomObject]@{ ExitCode = 1; Failures = $failed.ToArray(); Warnings = @() }
    }

    foreach ($rel in $listed) {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $rel))) {
            [void]$failed.Add("listed doc '$rel' does not exist. Fix docs/user-facing-docs.txt.")
        } elseif (Test-IsDoNotTouch $rel) {
            [void]$failed.Add("listed doc '$rel' is in docs-spec.md's do-not-touch set - a docs-rationalize target must never be do-not-touch. Remove it from docs/user-facing-docs.txt.")
        } elseif (-not (Test-HasVoiceEntry $rel)) {
            [void]$failed.Add("listed doc '$rel' matches no docs-spec.md voice-table shape - it is a spec gap (unvoiced). Add a voice row in docs/docs-spec.md or remove it from the list.")
        }
    }

    # (c) heuristic: a tracked user-facing-shaped .md absent from the list. $TrackedDocs is a test seam;
    # production derives it from git (guarded). $null => skip silently (git unavailable / not a repo).
    $tracked = if ($null -ne $TrackedDocs) { $TrackedDocs } else { Get-TrackedMarkdown $repoRoot }
    if ($tracked) {
        $listedSet = @{}; foreach ($r in $listed) { $listedSet[$r] = $true }
        foreach ($t in $tracked) {
            $tn = $t -replace '\\', '/'
            if ($listedSet.ContainsKey($tn)) { continue }
            if (Test-IsDoNotTouch $tn) { continue }
            if (Test-LooksUserFacing $tn) {
                [void]$warned.Add("tracked doc '$tn' looks user-facing but is absent from docs/user-facing-docs.txt (heuristic - a maintainer confirms).")
            }
        }
    }

    $code = if ($failed.Count -gt 0) { 1 } else { 0 }
    return [PSCustomObject]@{ ExitCode = $code; Failures = $failed.ToArray(); Warnings = $warned.ToArray() }
}

# main-guard: run only when invoked directly (NOT when dot-sourced by Pester - InvocationName is '.').
if ($MyInvocation.InvocationName -ne '.') {
    $result = Invoke-UserFacingDocsCheck $root
    $result.Warnings | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Yellow }
    if ($result.ExitCode -ne 0) {
        Write-Host 'user-facing-docs gate FAILED:' -ForegroundColor Red
        $result.Failures | ForEach-Object { Write-Host "  - $_" }
        Write-Error 'docs/user-facing-docs.txt has a missing or do-not-touch entry.'
        exit 1
    }
    Write-Host "user-facing docs ok ($((Read-DocList (Join-Path $root 'docs/user-facing-docs.txt')).Count) listed; all exist; none do-not-touch)"
    exit 0
}

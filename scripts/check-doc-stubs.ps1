#requires -Version 5.1
# Fail (exit 1) if a doc that was deliberately reduced to a POINTER STUB has been re-fattened into a
# second copy of the content it points at.
#
# WHY: forks 2 and 3 of the 2026-07-19 doc-accuracy audit removed two duplicated manuals by replacing
# them with stubs. The parity gate (scripts/check-seed-artifacts-synced.sh) only diffs the two plugin/
# trees, NEVER docs/ - which is exactly why those copies drifted unnoticed for weeks. Structural
# elimination is the fix; this guard is what keeps the elimination from silently un-doing itself.
#
# To retire a stub (i.e. deliberately make it a real doc again), remove it from $Stubs below in the
# same commit - so reversing the decision is explicit and reviewable, not accidental.
#
# SCOPE: pre-push only (lefthook `doc-stubs`), deliberately NOT in ci-scripts.yml. That workflow fires
# on scripts/** , but a re-fattened stub changes docs/ - so it would never trigger on the case this
# guards. Widening its paths: to docs/** would run the whole Pester suite on every doc edit. Pre-push
# blocks the regression before it can reach origin, which is the enforcement point that matters here.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$Stubs = @(
    'docs/agy-assumptions.md'
    'docs/agy-capabilities.md'
    'clavity-classic/docs/agy-test-suite.md'
)

$MaxLines = 40
$Marker   = 'This file is now a pointer'
$failed   = @()

foreach ($rel in $Stubs) {
    $path = Join-Path $root ($rel -replace '/', '\')
    if (-not (Test-Path $path)) {
        $failed += "$rel : MISSING (a stub was deleted - if that was intended, drop it from `$Stubs)"
        continue
    }
    $lines = @(Get-Content -Path $path)
    if ($lines.Count -gt $MaxLines) {
        $failed += "$rel : $($lines.Count) lines (max $MaxLines) - re-fattened into a real doc?"
    }
    if (($lines -join "`n") -notmatch [regex]::Escape($Marker)) {
        $failed += "$rel : missing the pointer marker '$Marker'"
    }
}

if ($failed.Count -gt 0) {
    Write-Host "Doc-stub guard FAILED:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  - $_" }
    Write-Error "A pointer stub grew back into content. Put the content in the canonical copy instead."
    exit 1
}

Write-Host "doc stubs ok ($($Stubs.Count) checked, each <= $MaxLines lines with a pointer marker)"
exit 0

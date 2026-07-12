#!/usr/bin/env pwsh
# scripts/drain-lib.ps1 — shared drain primitives. PARAMETER-LESS by design: dot-sourcing this defines functions
# ONLY, so it never binds/clobbers a caller's $InboxPath (agy plan-panel R1 F-P1) and never collides on a `main`.
Set-StrictMode -Version Latest

function Resolve-InboxPath([string]$explicit) {
    if ($explicit) { return $explicit }
    if ($env:CLAVITY_AGY_INBOX) { return $env:CLAVITY_AGY_INBOX }
    return Join-Path $env:LOCALAPPDATA 'Programs/agy-autotrain/plugins/agy-autotrain/knowledge/agy-observations.md'
}

function Get-PendingBulletCount([string]$InboxPath) {
    if (-not (Test-Path $InboxPath)) { return 0 }
    $inPending = $false; $count = 0
    foreach ($l in (Get-Content $InboxPath)) {
        if ($l -match '^##\s+Pending\s*$') { $inPending = $true; continue }
        if ($inPending -and $l -match '^##\s') { break }   # next heading ends the section
        if ($inPending -and $l -match '^- \[') { $count++ } # F17: one-bullet-per-observation schema
    }
    return $count
}

function Get-PendingBody([string]$InboxPath) {
    # The lines strictly BETWEEN the `## Pending` heading and the next `## ` heading (or EOF).
    $inPending = $false; $body = @()
    foreach ($l in (Get-Content $InboxPath)) {
        if ($l -match '^##\s+Pending\s*$') { $inPending = $true; continue }
        if ($inPending -and $l -match '^##\s') { break }
        if ($inPending) { $body += $l }
    }
    return $body
}

function Set-PendingBody([string]$InboxPath, [string[]]$body) {
    # Rewrite the file with the `## Pending` section body replaced by $body (heading preserved).
    # Trim TRAILING blank lines so repeated drain/abort cycles don't accumulate blanks (Cascade C2). Uses a List
    # (not $body[0..-2], which misbehaves when Count==1).
    $trimmed = [System.Collections.Generic.List[string]]::new()
    foreach ($x in @($body)) { $trimmed.Add([string]$x) }
    while ($trimmed.Count -gt 0 -and $trimmed[$trimmed.Count - 1] -match '^\s*$') { $trimmed.RemoveAt($trimmed.Count - 1) }
    $body = $trimmed.ToArray()

    $out = @(); $inPending = $false; $emitted = $false
    foreach ($l in (Get-Content $InboxPath)) {
        if ($l -match '^##\s+Pending\s*$') { $out += $l; $inPending = $true; $out += $body; $emitted = $true; continue }
        if ($inPending -and $l -match '^##\s') { $inPending = $false; $out += $l; continue }
        if ($inPending) { continue }   # drop old body lines
        $out += $l
    }
    if (-not $emitted) {
        if ($out.Count -gt 0 -and $out[-1] -ne '') { $out += '' }   # C3: blank line before a newly-created heading
        $out += '## Pending'; $out += $body
    }
    # Explicit LF write (D2): deterministic, avoids an OS-native CRLF rewrite of the app-data inbox.
    [System.IO.File]::WriteAllText($InboxPath, (($out -join "`n") + "`n"))
}

function Move-PendingToStaging([string]$InboxPath, [string]$StagingPath) {
    # NB (SC1, R3 — accepted MVP limitation): moving the snapshot BEFORE the 30-60s curator run closes the LARGE
    # TOCTOU window (a mid-curator agy-learn append lands in the now-empty ## Pending and drains next time). A
    # narrow SUB-SECOND race remains — an agy-learn append between this read and the inbox rewrite is clobbered —
    # because agy-learn stays a dumb, uncoordinated appender (spec non-goal). The real fix (append-coordination /
    # agentmemory dual-write) is the spec's Evolution path; the drain is a deliberate, infrequent maintainer action,
    # so the residual window is accepted for the MVP.
    [System.IO.File]::WriteAllText($StagingPath, (((Get-PendingBody $InboxPath) -join "`n") + "`n"))  # LF (D2)
    Set-PendingBody -InboxPath $InboxPath -body @()   # leave the ## Pending body EMPTY
}

function Restore-StagingToPending([string]$InboxPath, [string]$StagingPath) {
    # VERBATIM + symmetric with Move (F-P2): restore the ENTIRE staged body, not just bullet lines, so a
    # multi-line capture is never silently truncated on an abort.
    # SC2 (R3): staged (the older, aborted observations) go BEFORE $existing (mid-run captures are newer), so the
    # re-queued ## Pending stays in chronological order.
    $staged = @(Get-Content $StagingPath)
    $existing = @(Get-PendingBody $InboxPath)
    Set-PendingBody -InboxPath $InboxPath -body (@($staged) + @($existing))
}

function Find-StagingFile([string]$InboxDir) {
    if (-not (Test-Path $InboxDir)) { return $null }
    $f = Get-ChildItem -Path $InboxDir -Filter 'agy-observations.staging.*.md' -File -ErrorAction SilentlyContinue |
         Select-Object -First 1
    if ($f) { return $f.FullName } else { return $null }
}

function New-RunId { return (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') }

function Get-SeedBytes([string]$RepoRoot) {
    $seed = Join-Path $RepoRoot 'seed/golden-header.md'
    if (-not (Test-Path $seed)) { return 0 }
    return [System.Text.Encoding]::UTF8.GetByteCount([System.IO.File]::ReadAllText($seed))
}

function Get-RunIdFromStaging([string]$path) {
    $leaf = Split-Path $path -Leaf
    if ($leaf -match '^agy-observations\.staging\.(.+)\.md$') { return $Matches[1] }
    throw "unrecognized staging filename: $leaf"
}

function Test-RunIdInLog([string]$LogText, [string]$RunId) {
    if (-not $LogText) { return $false }
    return $LogText -match ('## drain ' + [Regex]::Escape($RunId) + ' ')
}

function Get-DrainOutputPaths {
    return @(
        'seed/golden-header.md'
        'clavity-dotnet/plugin/knowledge/agy-assumptions.md'
        'clavity-dotnet/plugin/knowledge/agy-capabilities.md'
        'clavity-classic/plugin/knowledge/agy-assumptions.md'
        'clavity-classic/plugin/knowledge/agy-capabilities.md'
        'docs/agy-drain-log.md'
        'docs/agy-verify-needed.md'
        'docs/agy-drain-proposal.md'
        'docs/fix-the-tool-backlog'
    )
}

function Get-SidecarRecoverySections([string]$SidecarPath) {
    # R-V1: the append-only drain-log records ONLY what git can't otherwise recover — the F11 verbatim
    # `## Dropped` + `## Parked (verify-needed)` sections. Promoted / Proposed-demotions detail lives in the
    # committed manual diffs + the (git-tracked, per-run-overwritten) sidecar, so it is NOT duplicated into the
    # growing log. (The log still grows linearly with drains — an intentional append-only maintainer record, like a
    # CHANGELOG — but each entry is bounded to the essentials.)
    # PP1+BS1 (R3): match a section by its FIRST WORD (`^##\s+(\w+)`), tolerant of an LLM appending a parenthetical
    # to the header line; toggle ONLY on a real `^## <Word>` header. The curator renders each dropped/parked entry as
    # a BULLET, so a `##` INSIDE an entry (`- …##…`) never starts a line with `##` and cannot trip the toggle or
    # truncate the section (the same bullet-schema robustness as the inbox gate, F17).
    if (-not (Test-Path $SidecarPath)) { return '(no sidecar written)' }
    $keep = @('Dropped', 'Parked')
    $out = @(); $emit = $false
    foreach ($l in (Get-Content $SidecarPath)) {
        if ($l -match '^##\s+(\w+)') { $emit = ($keep -contains $Matches[1]); if ($emit) { $out += $l }; continue }
        if ($emit) { $out += $l }
    }
    if ($out.Count -eq 0) { return '(no dropped/parked entries this run)' }
    return ($out -join "`n")
}

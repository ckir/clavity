#!/usr/bin/env pwsh
# scripts/docs-audit-lib.ps1 — shared docs-audit primitives. PARAMETER-LESS by design: dot-sourcing defines
# functions ONLY, so it never binds a caller's params and unit tests can exercise pure logic directly.
Set-StrictMode -Version Latest

$script:SuspectMinCodeBlocks = 3   # coarse degeneracy floor (spec §Stage 1.2): claims==1 with >= this many
                                   # fenced code blocks => AUDIT-SUSPECT. Err toward UNDER-flagging.

function New-AuditRunId { return (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') }

function Read-DocList([string]$ListPath) {
    # One repo-relative path per line. A WHOLE-LINE comment is optional whitespace then `#`; a TRAILING comment
    # must be whitespace-preceded. Blank lines ignored. Both halves are load-bearing (agy R6-F2, measured):
    # a bare `-replace '#.*$'` truncates a real filename containing '#' (`C#-guide.md` -> `C`, silently dropping
    # a doc from the audit scope), while the naive `\s+#.*$` alternative leaves a whole-line comment INTACT so it
    # survives as a bogus path — the list's primary comment form. Skip-then-strip is the only correct order.
    if (-not (Test-Path $ListPath)) { return @() }
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($raw in (Get-Content -LiteralPath $ListPath)) {
        if ($raw -match '^\s*#') { continue }              # whole-line comment
        $line = ($raw -replace '\s+#.*$', '').Trim()       # trailing comment (whitespace-preceded only)
        if ($line) { $out.Add($line) }
    }
    return @($out)
}

function Get-InScopeDocs {
    param([string]$RepoRoot, [string[]]$Only = @())
    $all = Read-DocList (Join-Path $RepoRoot 'docs/user-facing-docs.txt')
    if ($Only -and $Only.Count -gt 0) {
        # Intersect: a narrowing arg can only NARROW the canonical list, never add an off-list doc.
        return @($all | Where-Object { $Only -contains $_ })
    }
    return @($all)
}

function Parse-AuditOutput([string]$Raw) {
    # Extract the LAST CLAIMS_INSPECTED integer and every well-formed FINDINGS bullet. Unparseable (no claim
    # line) is the soft/hard-fail signal — a refusal, an apology, or empty output all land here.
    $lines = @($Raw -split "`r?`n")
    $claim = $null
    foreach ($l in $lines) { if ($l -match '^\s*CLAIMS_INSPECTED:\s*(\d+)\s*$') { $claim = [int]$Matches[1] } }
    $findings = @(); $inF = $false
    foreach ($l in $lines) {
        if ($l -match '^\s*FINDINGS:') { $inF = $true; continue }
        if ($inF -and $l -match '^\s*-\s*(\S+)\s+(\S+?):(\d+)\s*\|\s*(.*?)\s*\|\s*(.*)$') {
            $findings += @{ kind=$Matches[1]; docPath=$Matches[2]; docLine=[int]$Matches[3]; codeRef=$Matches[4]; text=$Matches[5].Trim() }
        }
    }
    return @{ Parseable = ($null -ne $claim); ClaimsInspected = $(if ($null -ne $claim) { $claim } else { 0 }); Findings = $findings }
}

function Get-FencedCodeBlockCount([string]$DocAbsPath) {
    if (-not (Test-Path $DocAbsPath)) { return 0 }
    $fences = 0
    foreach ($l in (Get-Content -LiteralPath $DocAbsPath)) { if ($l -match '^\s*```') { $fences++ } }
    return [int]([Math]::Floor($fences / 2))   # opening+closing = one block
}

function Get-DocOutcome {
    param([int]$ClaimsInspected, [int]$FindingsCount, [int]$FencedBlocks, [bool]$Parseable)
    if (-not $Parseable)        { return 'AUDIT-INCONCLUSIVE' }   # no claim-count = soft/hard fail
    if ($ClaimsInspected -le 0) { return 'AUDIT-INCONCLUSIVE' }   # liveness token
    if ($ClaimsInspected -eq 1 -and $FencedBlocks -ge $script:SuspectMinCodeBlocks) { return 'AUDIT-SUSPECT' }
    if ($FindingsCount -ge 1)   { return 'FINDINGS' }
    return 'CLEAN'
}

function Get-DiagnosticSnippet([string]$Text, [int]$Max = 200) {
    # A bounded, single-line head of the raw invocation output / exception, for the append-only log. Without this
    # a quota error, an auth prompt, a refusal and an OOM crash are all indistinguishable AUDIT-INCONCLUSIVE rows
    # and the operator has nothing to debug a background run with (agy R5-F1). Empty reads as "(no output)" so an
    # empty response stays distinguishable from a missing field.
    if (-not $Text -or -not $Text.Trim()) { return '(no output)' }
    $one = ($Text -replace '\s+', ' ').Trim()
    if ($one.Length -gt $Max) { return $one.Substring(0, $Max) + '...' }
    return $one
}

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

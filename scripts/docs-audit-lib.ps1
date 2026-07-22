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

function Read-FindingsStore([string]$Path) {
    # Returns a mutable hashtable model. Absent/empty/corrupt file => a fresh empty skeleton (the store is a
    # gitignored working artifact; a corrupt one is safe to discard and rebuild, never a hard error).
    if (Test-Path $Path) {
        try {
            $obj = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
            if ($obj -and $obj.ContainsKey('docs')) {
                if (-not $obj.ContainsKey('schemaVersion')) { $obj['schemaVersion'] = 1 }
                if ($null -eq $obj['docs']) { $obj['docs'] = @{} }
                return $obj
            }
        } catch { }   # fall through to skeleton
    }
    return @{ schemaVersion = 1; docs = @{} }
}

function Merge-DocResult {
    param([hashtable]$Store, [string]$DocPath, [hashtable]$Result, [string]$RunId)
    if (-not $Store.docs.ContainsKey($DocPath)) {
        $Store.docs[$DocPath] = @{ outcome=$null; claimsInspected=0; auditedAtRunId=$null; findings=@(); history=@() }
    }
    $e = $Store.docs[$DocPath]
    $confirmed = @('CLEAN','FINDINGS') -contains $Result.Outcome
    if ($confirmed) {
        $e['outcome']         = $Result.Outcome
        $e['claimsInspected'] = $Result.ClaimsInspected
        $e['findings']        = @($Result.Findings)
        $e['auditedAtRunId']  = $RunId
        $e['history']         = @($e['history']) + ,@{ runId=$RunId; outcome=$Result.Outcome; note='audited' }
    } else {
        # AUDIT-INCONCLUSIVE / AUDIT-TIMEOUT / AUDIT-SUSPECT: do NOT drop prior findings — the doc did not change,
        # the audit merely failed to confirm. Annotate the failed attempt so Stage 2 sees both.
        if (@('CLEAN','FINDINGS') -notcontains $e['outcome']) {   # no CONFIRMED findings to preserve (null or a
            # prior failure state) => record the LATEST failure. `-not $e['outcome']` would freeze an
            # INCONCLUSIVE->SUSPECT transition on the first failure (agy plan-review F3).
            $e['outcome']         = $Result.Outcome
            $e['claimsInspected'] = $Result.ClaimsInspected
            $e['findings']        = @()
        }
        $e['history'] = @($e['history']) + ,@{ runId=$RunId; outcome=$Result.Outcome; note='re-audit did not confirm; prior findings preserved' }
    }
    return $Store
}

function Write-FindingsStore([hashtable]$Store, [string]$Path) {
    # Atomic: write to .tmp then rename, so a crash mid-write never corrupts the whole store (agy fork-1 fix).
    $json = ($Store | ConvertTo-Json -Depth 12)
    $tmp = $Path + ".$PID.tmp"   # PID-unique: a stale-reclaimed zombie run must not share this temp path (agy R2-F2)
    [System.IO.File]::WriteAllText($tmp, $json)              # UTF-8 no BOM, LF
    Move-Item -LiteralPath $tmp -Destination $Path -Force    # near-atomic rename
}

function Render-FindingsView([hashtable]$Store, [string]$Path) {
    # A GENERATED human/Stage-2 view — the JSON is the source of truth. Each doc's section is bracketed by
    # machine-parseable delimiters (belt-and-suspenders; the merge itself operates on the JSON, never this text).
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# docs audit findings (GENERATED view of docs-audit-findings.json; gitignored working artifact)')
    $lines.Add('')
    foreach ($doc in ($Store.docs.Keys | Sort-Object)) {
        $e = $Store.docs[$doc]
        $lines.Add("<!-- doc:$doc start -->")
        $lines.Add("## $doc — $($e['outcome']) (claims inspected: $($e['claimsInspected']))")
        $fs = @($e['findings'])
        if ($fs.Count -eq 0) { $lines.Add('- (no findings)') }
        else { foreach ($f in $fs) { $lines.Add("- $($f['kind']) $($f['docPath']):$($f['docLine']) | $($f['codeRef']) | $($f['text'])") } }
        $lines.Add("<!-- doc:$doc end -->")
        $lines.Add('')
    }
    $tmp = $Path + ".$PID.tmp"   # PID-unique: a stale-reclaimed zombie run must not share this temp path (agy R2-F2)
    [System.IO.File]::WriteAllText($tmp, (($lines -join "`n") + "`n"))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Initialize-AuditLog {
    param([string]$Path, [string]$RunId, [string]$Timestamp, [string]$LinkResult)
    New-Item -ItemType Directory -Force (Split-Path $Path -Parent) | Out-Null
    if (-not (Test-Path $Path)) {
        [System.IO.File]::WriteAllText($Path, "# docs audit log (append-only; gitignored working artifact)`n")
    }
    [System.IO.File]::AppendAllText($Path, "`n## audit $RunId — $Timestamp — $LinkResult`n")
}

function Add-AuditLogDoc {
    param([string]$Path, [string]$DocPath, [hashtable]$Result, [string]$Model, [string]$PromptFile)
    # Invocation SHAPE only (model alias + prompt file + doc path) — never the expanded prompt (would bloat the
    # append-only file ~N x per run). Appended as THIS doc completes, so a mid-run crash keeps prior docs on disk.
    $inv = "$Model/$PromptFile/$DocPath"
    $findingsCount = @($Result.Findings).Count
    $line = "- $DocPath — $($Result.Outcome) — claims:$($Result.ClaimsInspected) — invocation:$inv — findings:$findingsCount"
    # A non-confirmed outcome carries its CAUSE so the operator can tell quota/auth/refusal/crash apart (agy R5-F1).
    if ($Result.ContainsKey('Diagnostic') -and $Result.Diagnostic) { $line += " — diag:$($Result.Diagnostic)" }
    [System.IO.File]::AppendAllText($Path, $line + "`n")
}

function Get-AuditLockPath([string]$RepoRoot) { return (Join-Path $RepoRoot 'docs/docs-audit.lock') }

function Test-AuditLockStale {
    param([string]$LockPath, [string]$NowUtc, [int]$MaxAgeSec)
    if (-not (Test-Path $LockPath)) { return $true }        # no lock = free
    $lines = @(Get-Content -LiteralPath $LockPath)
    $lockPid = 0; [void][int]::TryParse(($lines[0]), [ref]$lockPid)
    if ($lockPid -le 0) { return $true }                    # malformed = stale
    if (-not (Get-Process -Id $lockPid -ErrorAction SilentlyContinue)) { return $true }  # dead PID = stale
    if ($lines.Count -ge 2 -and $lines[1]) {
        try {
            # Parse machine-written timestamps with INVARIANT culture (agy plan-review F2): a culture-sensitive
            # parse of the 'u' string can throw FormatException on a non-US host, which the catch would turn into
            # "stale" and silently reclaim a LIVE lock — the exact concurrency the lock exists to prevent.
            $ic = [System.Globalization.CultureInfo]::InvariantCulture
            $st = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
            $age = [datetime]::Parse($NowUtc, $ic, $st) - [datetime]::Parse($lines[1], $ic, $st)
            if ($age.TotalSeconds -gt $MaxAgeSec) { return $true }   # too old = stale
        } catch { return $true }                            # unparseable timestamp = stale
    }
    return $false                                           # alive PID + within max-age = LIVE
}

function Enter-AuditLock {
    param([string]$LockPath, [string]$NowUtc, [int]$MaxAgeSec)
    if (-not (Test-AuditLockStale -LockPath $LockPath -NowUtc $NowUtc -MaxAgeSec $MaxAgeSec)) { return $false }
    New-Item -ItemType Directory -Force (Split-Path $LockPath -Parent) | Out-Null
    [System.IO.File]::WriteAllText($LockPath, "$PID`n$NowUtc`n")
    return $true
}

function Exit-AuditLock([string]$LockPath) { Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue }

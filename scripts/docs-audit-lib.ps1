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
    $findings = @(); $inF = $false; $malformed = $false
    foreach ($l in $lines) {
        if ($l -match '^\s*FINDINGS:') { $inF = $true; continue }
        if (-not $inF) { continue }
        if ($l -match '^\s*-\s*(\S+)\s+(\S+?):(\d+(?:-\d+)?)\s*\|\s*(.*?)\s*\|\s*(.*)$') {
            # docLine is a STRING and holds the WHOLE anchor, `12` or `11-19`. The contract accepts a range because
            # a claim can span lines (a multi-command code block), and the model anchors those as `11-19` — which
            # the old `:(\d+)` rejected, poisoning the parse and discarding a real finding (measured twice on the
            # same doc). The prompt contract was widened in lockstep; the parser was NOT patched alone. Keeping the
            # [int] cast here would throw FormatException on "11-19"; capturing only the start would silently drop
            # the localisation the model got right. Nothing consumes docLine numerically — see Render-FindingsView.
            $findings += @{ kind=$Matches[1]; docPath=$Matches[2]; docLine=$Matches[3]; codeRef=$Matches[4]; text=$Matches[5].Trim() }
        }
        elseif ($l.Trim()) {
            # STRICT: inside FINDINGS, ANY non-blank line that is not a well-formed finding poisons the parse.
            # Three successive narrower rules each leaked a false CLEAN (all MEASURED): dropping a malformed
            # BULLET (C3 — a comma where the `|` belongs), then a finding with no `- ` prefix (C5), then one
            # with neither bullet nor pipes (C7 — `ACCURACY doc.md:1, code.rs:1, text`). Each time the finding
            # fell into the "ignore" bucket and the doc classified CLEAN with a real defect hidden — a false
            # NEGATIVE on the one thing this tool exists to detect. Shape-matching the malformation is a losing
            # game; the prompt contract says "emit EXACTLY this shape and nothing else", so anything else IS a
            # violation. A poisoned parse lands the doc AUDIT-INCONCLUSIVE (prior findings preserved, cause in
            # the log's diag field) — a cheap, honest "did not confirm" instead of a confident, wrong CLEAN.
            $malformed = $true
        }
        # Blank / whitespace-only lines inside the section remain ignored.
    }
    return @{ Parseable = (($null -ne $claim) -and -not $malformed); ClaimsInspected = $(if ($null -ne $claim) { $claim } else { 0 }); Findings = $findings }
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
    # Test-Path and Get-Content are two operations (capstone C6, MEASURED). A concurrent run releasing the lock
    # in between makes Get-Content throw ItemNotFoundException, which under the orchestrator's
    # $ErrorActionPreference='Stop' propagates out and CRASHES the whole background run — far worse than any
    # lock race. Resolve by re-testing: vanished => genuinely free; present but unreadable (a sharing violation
    # while the owner writes it) => treat as LIVE and refuse, never steal a lock we could not read.
    try { $lines = @(Get-Content -LiteralPath $LockPath -ErrorAction Stop) }
    catch { return (-not (Test-Path $LockPath)) }
    # A 0-BYTE lock is reachable (capstone C8, MEASURED): New-AuditLockFile creates the file and then writes it,
    # so a hard-kill, power loss or full disk in between leaves an empty one. Indexing the empty array under
    # `Set-StrictMode -Version Latest` throws IndexOutOfRangeException — which, being outside the try above,
    # crashed the whole run and left the lock in place, WEDGING the tool permanently. An empty lock carries no
    # ownership information, so it is by definition stale and reclaimable.
    if ($lines.Count -lt 1) { return $true }
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

function New-AuditLockFile([string]$LockPath, [string]$NowUtc) {
    # ATOMIC-EXCLUSIVE create. FileMode::CreateNew THROWS if the file already exists (measured), so of N racers
    # exactly one can succeed. Returns $true only for the winner.
    try {
        $fs = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::CreateNew)
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes("$PID`n$NowUtc`n")
            $fs.Write($bytes, 0, $bytes.Length)
        } finally { $fs.Dispose() }
        return $true
    } catch { return $false }
}

function Enter-AuditLock {
    param([string]$LockPath, [string]$NowUtc, [int]$MaxAgeSec)
    # CREATE FIRST, ask questions second (capstone C2, MEASURED). Checking staleness BEFORE creating is a TOCTOU
    # race: `Test-AuditLockStale` measures ~12ms, so two concurrently-launched runs both see "free" and both
    # proceed. The first attempt at this fix still lost, because it ran an UNCONDITIONAL `Remove-Item` before the
    # exclusive create — measured: run B simply DELETED run A's freshly-minted live lock and then created its own,
    # so both acquired and both entered the per-doc read-merge-write loop. Ordering is the fix: the exclusive
    # create is the ONLY way to acquire, and staleness is consulted only AFTER it fails.
    New-Item -ItemType Directory -Force (Split-Path $LockPath -Parent) | Out-Null
    if (New-AuditLockFile $LockPath $NowUtc) { return $true }        # no lock existed — we won it outright
    # A lock file exists. Refuse unless it is genuinely reclaimable (dead PID or past max-age).
    if (-not (Test-AuditLockStale -LockPath $LockPath -NowUtc $NowUtc -MaxAgeSec $MaxAgeSec)) { return $false }
    # RECLAIM under an exclusive CLAIM MARKER, then RE-CHECK (capstone C4, MEASURED). Two earlier attempts at
    # this failed for the same underlying reason: the staleness verdict above goes out of date the instant
    # another run finishes reclaiming. Deleting (attempt 1) and renaming (attempt 2) both let a late arrival
    # destroy the winner's freshly-installed LIVE lock — measured: `Move-Item` renames by PATH, not by file
    # identity, so it happily stole a valid lock. The marker serialises the reclaim path, and the RE-CHECK
    # inside it is what actually closes the race: whoever gets the marker second re-reads the lock, finds the
    # first run's live lock, and refuses instead of stealing it.
    $claim = "$LockPath.claim"
    if (-not (New-AuditLockFile $claim $NowUtc)) {
        # Another run holds the marker — or a run was hard-killed mid-reclaim and orphaned it. An orphaned
        # marker must never wedge the tool permanently (the whole point of a self-clearing lock), so clear a
        # stale one here and refuse; the NEXT invocation reclaims cleanly. Never spin.
        if (Test-AuditLockStale -LockPath $claim -NowUtc $NowUtc -MaxAgeSec $MaxAgeSec) {
            Remove-Item -LiteralPath $claim -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
    try {
        if (-not (Test-AuditLockStale -LockPath $LockPath -NowUtc $NowUtc -MaxAgeSec $MaxAgeSec)) { return $false }
        Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
        return (New-AuditLockFile $LockPath $NowUtc)
    } finally { Remove-Item -LiteralPath $claim -Force -ErrorAction SilentlyContinue }
}

function Exit-AuditLock([string]$LockPath) {
    # RELEASE ONLY WHAT WE OWN (capstone C7, MEASURED: the unconditional Remove-Item deleted a lock carrying a
    # different PID). A run whose host slept past MaxAgeSec has its lock legitimately reclaimed by a newer run;
    # when it wakes and finishes, an unconditional release would delete the NEW run's live lock and let a third
    # run start alongside it. Releasing only our own PID's lock makes a late finisher harmless.
    if (-not (Test-Path $LockPath)) { return }
    try { $lines = @(Get-Content -LiteralPath $LockPath -ErrorAction Stop) } catch { return }
    # Same 0-byte hazard as Test-AuditLockStale (capstone C8, MEASURED: IndexOutOfRangeException here too).
    # An empty lock proves no ownership, so we must NOT delete it — leave it for the staleness path to reclaim.
    if ($lines.Count -lt 1) { return }
    $lockPid = 0; [void][int]::TryParse(($lines[0]), [ref]$lockPid)
    if ($lockPid -ne $PID) { return }   # someone else owns it now — leave it alone
    # KNOWN RESIDUAL (capstone round 5, weighed and accepted, not overlooked): ownership is checked and then
    # acted on, so a thread suspended between these two lines could in principle delete a lock reclaimed in the
    # gap. Measured: that gap is a single integer comparison — below measurement resolution against the ~5-7ms
    # of file I/O around it — and exploiting it needs another run to complete a >12ms reclaim inside it AND this
    # run's lock to be past MaxAgeSec. Not closable cheaply either: there is no atomic check-and-delete here
    # (FileOptions::DeleteOnClose must be declared at open time, before the PID can be read), so any "fix" is
    # another two-step dance with its own gap — and four prior edits to this lock each introduced a new defect.
    Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
}

function Get-MlcErrorCount([string]$MlcOutput) {
    # PINNED to mlc's real summary block, captured from a live run (Step 1) — not guessed:
    #     Result (210 links):
    #     OK       144
    #     Skipped  37
    #     Warnings 27
    #     Errors   2
    # Anchored to a WHOLE `Errors <N>` line so the sibling `Warnings <N>` line can never be misread as the count
    # (a loose `(\d+)\s+error` pattern would match "Warnings 27" on some outputs). Advisory + non-blocking: the
    # human compares this raw count against the baseline of 2 documented in .mlc.toml. Returns 0 when no summary
    # block is present — the caller records mlc's raw exit code alongside, so a 0 is never read as "clean" alone.
    if (-not $MlcOutput) { return 0 }
    $m = [regex]::Match($MlcOutput, '(?m)^\s*Errors\s+(\d+)\s*$')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return 0
}

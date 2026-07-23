#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Stage-1 docs-rationalize audit: read-only `claude -p` doc-vs-code accuracy audit over the user-facing doc
  list, emitting a per-doc punch-list (JSON store + md view) and an append-only log. NO doc edits, NO commit.
  Background/manual only — never a `just` auto-gate. Sequential with a per-doc timeout.
.PARAMETER Only
  Narrowing arg: audit only these listed docs (a subset run SKIPS the repo-wide link-check).
.PARAMETER SkipAudit
  Test/utility: skip the live audit entirely (records AUDIT-INCONCLUSIVE per doc).
.PARAMETER AuditStub
  Test seam: PATH to a stub .ps1 (param $docPath,$repoRoot) emitting the audit-output shape on stdout, run in
  place of the live `claude -p`. A stub-script PATH, not a Mock — a Pester Mock cannot cross the pwsh -File boundary.
.PARAMETER RunId / Timestamp
  Caller-supplied for test determinism (default: generated). Never call Get-Date inside the audited logic.
#>
[CmdletBinding(SupportsShouldProcess)]   # enables -WhatIf dry-run over the mutation block (mirrors drain-knowledge.ps1:17)
param(
    [string]$RepoRoot,
    [string[]]$Only = @(),
    [switch]$SkipAudit,
    [string]$AuditStub,
    [string]$RunId,
    [string]$Timestamp,
    # 1200s/doc. This is a CEILING, not a duration — raising it costs nothing on docs that finish fast, it only
    # stops killing slow ones. Calibrated from the first full 25-doc run (2h11m total): the 22 docs that did NOT
    # time out averaged ~275s, while 3 large docs (`README.md`, the classic bridge README-FIRST, and
    # `commonmemory/CONTRIBUTING.md`) blew through the previous 600s ceiling and were killed mid-audit, wasting
    # the call entirely. 1200s gives those roughly 4x the typical budget. NOTE: 1200 is a judgement, not a
    # measurement — nobody has timed how long README.md actually needs, only that it exceeds 600s. If a doc
    # still times out here, measure it before raising this again rather than guessing a third time.
    [int]$TimeoutSec = 1200,
    # MUST stay above 25 * TimeoutSec, or a full-list run outlives its own lock and a second run reclaims it
    # mid-flight. This pairing has now broken twice when only the timeout moved (25*120=3000 < 5400 held;
    # 25*600=15000 > 5400 broke it; 25*1200=30000 > 18000 breaks it again) — so ALWAYS move both together.
    # 36000s = 10h against a 8.3h worst case. The worst case is a ceiling nobody expects to hit: the observed
    # full run was 2h11m.
    [int]$LockMaxAgeSec = 36000,
    [switch]$SkipLinkCheck,       # test/utility: skip mlc even on a full run (subset runs skip it automatically)
    # Resume a partial run: skip docs a PREVIOUS run already CONFIRMED, re-audit everything else. A full run is
    # 25 paid `claude -p` calls over potentially hours, so a crash, a quota trip, or a batch of timeouts must
    # not force re-paying for the docs that already succeeded.
    [switch]$Continue
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'docs-audit-lib.ps1')   # param-less shared primitives — safe dot-source

function Invoke-LinkCheck([string]$RepoRoot) {
    # Repo-wide mlc (== `just check-links`; config in .mlc.toml). Advisory + NON-blocking. Records the raw error
    # count for the human to compare against the documented baseline of 2. Never parses the baseline from prose.
    # GUARDED (agy R5-F2, MEASURED): a bare `& mlc` under $ErrorActionPreference='Stop' throws
    # CommandNotFoundException when mlc is absent, aborting the ENTIRE run before the log is even initialized —
    # the exact opposite of "non-blocking". Get-Command -EA SilentlyContinue does NOT throw under Stop (measured).
    if (-not (Get-Command mlc -ErrorAction SilentlyContinue)) {
        return @{ Ran = $false; Reason = 'mlc not installed'; Baseline = 2 }
    }
    Push-Location $RepoRoot
    try {
        $out = & mlc 2>&1 | Out-String
        $code = $LASTEXITCODE
    } catch {
        return @{ Ran = $false; Reason = "mlc failed: $($_.Exception.Message)"; Baseline = 2 }
    } finally { Pop-Location }
    return @{ Ran=$true; ErrorCount=(Get-MlcErrorCount $out); Baseline=2; ExitCode=$code }
}

function Invoke-DocAudit {
    param([string]$DocPath, [string]$RepoRoot, [int]$TimeoutSec, [string]$AuditStub, [string]$Model, [string]$ScriptDir, [int]$DrainMs = 5000)
    # Run stub|live as a REAL child PROCESS (not Start-Job) so a hung invocation can be killed WITH ITS ENTIRE
    # TREE on timeout: Stop-Job would kill only the pwsh worker and orphan the native `claude`/node grandchild
    # (agy R3-F1, measured). Both paths emit the audit-output text on stdout; the parent captures it ASYNC (a large
    # findings dump must not dead-lock a full pipe buffer) and parses it identically. This also subsumes R1-F4:
    # Process.Start is wrapped so an absent `claude` CLI => empty output => AUDIT-INCONCLUSIVE, and the process
    # handle is always Disposed.
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    if ($AuditStub) {
        $psi.FileName = 'pwsh'
        foreach ($a in @('-NoProfile', '-File', $AuditStub, $DocPath, $RepoRoot)) { $psi.ArgumentList.Add($a) }
    } else {
        $tpl = Get-Content (Join-Path $ScriptDir 'docs-audit-prompt.md') -Raw
        $prompt = $tpl.Replace('{{DOC_PATH}}', $DocPath).Replace('{{REPO_ROOT}}', $RepoRoot)
        $psi.FileName = 'claude'
        # READ-ONLY headless audit. Flag set CONFIRMED against `claude --help` (Task 10 Step 4 live-smoke) and
        # then live-smoked on a real doc — no longer guessed.
        #   -p                  non-interactive print mode
        #   --allowedTools      a WHITELIST of read-only tools. Deliberately a whitelist, not a --disallowedTools
        #                       blacklist: this build's own capstone spent three rounds proving that enumerating
        #                       the bad shapes never converges, while naming the good ones converges at once. The
        #                       audit prompt only needs to read files and grep the code it cites.
        #   NO --dangerously-skip-permissions, NO --allow-dangerously-skip-permissions, NO
        #   --permission-mode bypassPermissions|acceptEdits — any of those would grant write authority to a run
        #   whose entire contract is that it reports and never edits.
        # A tool request outside the whitelist cannot be approved (there is no interactive prompt under -p), so
        # the failure mode is a denial or a stall that the per-doc timeout reaps — never an unintended write.
        foreach ($a in @('-p', $prompt, '--model', $Model, '--allowedTools', 'Read', 'Grep', 'Glob')) { $psi.ArgumentList.Add($a) }
        $psi.WorkingDirectory = $RepoRoot
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    try { $proc = [System.Diagnostics.Process]::Start($psi) }
    catch { return @{ Raw = ''; Err = ''; TimedOut = $false } }   # absent CLI (Win32Exception) => empty => AUDIT-INCONCLUSIVE (agy R1-F4)
    # Drain BOTH streams async: stderr is redirected, so if it is never read a chatty stderr can fill its pipe
    # buffer and dead-lock the child while stdout drains (self-caught pre-round-4).
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    if ($proc.WaitForExit($TimeoutSec * 1000)) {
        # Do NOT call the parameterless WaitForExit() here: with redirected streams it blocks until the pipes reach
        # EOF, not merely until the process exits. A DETACHED GRANDCHILD that inherited the pipe handles (a Node
        # telemetry/update-checker outliving `claude`) would then hang the orchestrator FOREVER and defeat the
        # per-doc timeout entirely (agy R4-F1, measured). Bound the drain instead — WaitAll returns $false rather
        # than blocking; a stuck pipe yields no usable output => AUDIT-INCONCLUSIVE, the honest "did not confirm".
        $out = ''; $err = ''
        # KEEP stderr, do not merely drain it (capstone C9, MEASURED). A real `claude` failure — quota, auth,
        # an unhandled Node exception — writes its cause to STDERR and leaves stdout EMPTY. Discarding it made
        # the log read `diag:(no output)`, destroying the one field added to tell those failures apart. It is
        # returned SEPARATELY rather than merged into Raw so it can feed the diagnostic without ever reaching
        # the parser: stderr noise must not be able to contribute a CLAIMS_INSPECTED line or a findings bullet.
        if ([System.Threading.Tasks.Task]::WaitAll(@($stdoutTask, $stderrTask), $DrainMs)) {
            $out = $stdoutTask.Result
            $err = $stderrTask.Result
        }
        $proc.Dispose()
        return @{ Raw = $out; Err = $err; TimedOut = $false }
    }
    try { $proc.Kill($true) } catch { }                  # $true = kill the ENTIRE tree (claude + node children); no orphan (agy R3-F1)
    try { $null = $proc.WaitForExit(5000) } catch { }     # $null= : an unassigned WaitForExit(int) bool leaks onto the pipeline (measured), corrupting the @{...} return
    $proc.Dispose()
    return @{ Raw = ''; Err = ''; TimedOut = $true }
}

function Get-DocResult {
    param([string]$DocPath, [string]$RepoRoot, [int]$TimeoutSec, [string]$AuditStub, [switch]$SkipAudit, [string]$Model, [string]$ScriptDir)
    if ($SkipAudit) { return @{ Outcome='AUDIT-INCONCLUSIVE'; ClaimsInspected=0; Findings=@(); Diagnostic='audit skipped (-SkipAudit)' } }
    $inv = Invoke-DocAudit -DocPath $DocPath -RepoRoot $RepoRoot -TimeoutSec $TimeoutSec -AuditStub $AuditStub -Model $Model -ScriptDir $ScriptDir
    if ($inv.TimedOut) { return @{ Outcome='AUDIT-TIMEOUT'; ClaimsInspected=0; Findings=@(); Diagnostic="no output within ${TimeoutSec}s; process tree killed" } }
    $p = Parse-AuditOutput $inv.Raw
    $blocks = Get-FencedCodeBlockCount (Join-Path $RepoRoot $DocPath)
    $outcome = Get-DocOutcome -ClaimsInspected $p.ClaimsInspected -FindingsCount (@($p.Findings).Count) -FencedBlocks $blocks -Parseable $p.Parseable
    # Keep WHY a non-confirmed audit failed: the raw head carries the real cause (quota/auth error, refusal,
    # empty response) that a bare AUDIT-INCONCLUSIVE row would throw away (agy R5-F1).
    # Diagnose from stdout AND stderr (capstone C9): the cause of a real failure usually lives on stderr while
    # stdout is empty. Parsing above deliberately used $inv.Raw (stdout) ONLY.
    $diag = if (@('CLEAN','FINDINGS') -contains $outcome) { '' }
            else { Get-DiagnosticSnippet ((@($inv.Raw, $inv.Err) | Where-Object { $_ }) -join ' ') }
    return @{ Outcome=$outcome; ClaimsInspected=$p.ClaimsInspected; Findings=$p.Findings; Diagnostic=$diag }
}

function Invoke-Main {
    $repo  = if ($RepoRoot) { $RepoRoot } else { (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
    # Catch the silent mis-bind loudly (agy R6-F3, measured): under `pwsh -File`, `-Only a.md b.md` binds the 2nd
    # value to the next positional parameter — i.e. straight into $RepoRoot — and the run would otherwise proceed
    # against a nonsense root.
    if (-not (Test-Path -LiteralPath $repo -PathType Container)) {
        Write-Host "docs-audit: -RepoRoot '$repo' is not a directory. (Passing space-separated -Only values silently binds the 2nd one here — use commas with no spaces: -Only a.md,b.md)" -ForegroundColor Red
        exit 4
    }
    $runId = if ($RunId) { $RunId } else { New-AuditRunId }
    $now   = if ($Timestamp) { $Timestamp } else { (Get-Date).ToUniversalTime().ToString('u') }
    $model = if ($env:CLAVITY_DOCS_AUDIT_MODEL) { $env:CLAVITY_DOCS_AUDIT_MODEL } else { 'sonnet' }

    # `pwsh -File` passes `-Only a.md,b.md` as ONE string "a.md,b.md" — it does NOT split it into an array
    # (measured, agy R6-F3). Normalize by splitting on commas so the documented recipe form works.
    $onlyNorm = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $docs = Get-InScopeDocs -RepoRoot $repo -Only $onlyNorm
    $isSubset = ($onlyNorm.Count -gt 0)

    # -Continue: resume a partial run by skipping docs a previous run already CONFIRMED.
    # ONLY a confirmed outcome counts as done. AUDIT-INCONCLUSIVE / AUDIT-TIMEOUT / AUDIT-SUSPECT all mean
    # "the audit did not confirm this doc", so they are RETRIED — treating them as done would bake a
    # non-result into the punch-list as though it were a clean bill, the one failure that makes an audit worse
    # than none. Deliberately OPT-IN, never the default: once Stage 2 rewrites a doc you WANT it re-audited,
    # and a resume-by-default would silently skip exactly the docs whose text just changed.
    # Runs BEFORE the -WhatIf gate so the dry-run preview reports the real post-filter count.
    $resumeSkipped = 0
    if ($Continue) {
        $priorStore = Read-FindingsStore (Join-Path $repo 'docs/docs-audit-findings.json')
        $confirmed = @($docs | Where-Object {
            $priorStore.docs.ContainsKey($_) -and (@('CLEAN','FINDINGS') -contains $priorStore.docs[$_]['outcome'])
        })
        $resumeSkipped = $confirmed.Count
        $docs = @($docs | Where-Object { $confirmed -notcontains $_ })
    }
    # -WhatIf dry-run: everything above is read-only. Preview and SKIP the whole mutation block (lock + audit +
    # artifact writes), mirroring drain-knowledge.ps1:81's ShouldProcess gate.
    if (-not $PSCmdlet.ShouldProcess("$(@($docs).Count) user-facing doc(s)", "audit via claude -p, then write the findings store + log")) {
        Write-Host "docs-audit (-WhatIf): would audit $(@($docs).Count) doc(s)$(if ($isSubset) { ' (subset)' } else { '' })$(if ($Continue) { "; -Continue would SKIP $resumeSkipped already-confirmed doc(s)" } else { '' }); link-check would $(if ($isSubset) { 'be skipped (subset run)' } else { 'run repo-wide (mlc)' }). No lock taken, no claude -p, no writes." -ForegroundColor Cyan
        return
    }
    # PRE-FLIGHT (agy R5-F3): a missing audit engine must fail LOUDLY, ONCE — not silently produce N generic
    # AUDIT-INCONCLUSIVE rows that read as "these docs are unauditable" when the truth is "the toolchain is absent".
    # Placed AFTER the -WhatIf gate so a dry run never requires the CLI.
    if (-not $SkipAudit -and -not $AuditStub -and -not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Host "docs-audit: the 'claude' CLI is not on PATH — the accuracy audit cannot run. Install and authenticate it, or re-run with -SkipAudit. Refusing rather than logging $(@($docs).Count) false 'inconclusive' rows." -ForegroundColor Red
        exit 3
    }
    $lock = Get-AuditLockPath $repo
    if (-not (Enter-AuditLock -LockPath $lock -NowUtc $now -MaxAgeSec $LockMaxAgeSec)) {
        Write-Host "docs-audit: another audit run holds the lock ($lock). Refusing." -ForegroundColor Yellow
        exit 2
    }
    try {
        $linkResult = if ($isSubset) { 'link-check: skipped (subset run)' }
                      elseif ($SkipLinkCheck) { 'link-check: skipped' }
                      else {
                          $lc = Invoke-LinkCheck $repo
                          if ($lc.Ran) { "mlc: $($lc.ErrorCount) errors (baseline $($lc.Baseline); exit $($lc.ExitCode))" }
                          else { "link-check: SKIPPED — $($lc.Reason)" }   # never aborts the run (agy R5-F2)
                      }

        $findingsJson = Join-Path $repo 'docs/docs-audit-findings.json'
        $findingsMd   = Join-Path $repo 'docs/docs-audit-findings.md'
        $logPath      = Join-Path $repo 'docs/docs-audit-log.md'
        Initialize-AuditLog -Path $logPath -RunId $runId -Timestamp $now -LinkResult $linkResult

        foreach ($doc in $docs) {
            try {
                $result = Get-DocResult -DocPath $doc -RepoRoot $repo -TimeoutSec $TimeoutSec -AuditStub $AuditStub -SkipAudit:$SkipAudit -Model $model -ScriptDir $PSScriptRoot
            } catch {
                # One bad doc never sinks the batch (spec §Error handling). KEEP the exception text — a bare
                # AUDIT-INCONCLUSIVE would hide an OOM/IO crash from the operator entirely (agy R5-F1).
                $result = @{ Outcome='AUDIT-INCONCLUSIVE'; ClaimsInspected=0; Findings=@(); Diagnostic=(Get-DiagnosticSnippet $_.Exception.Message) }
            }
            # Load-merge-write per doc so a mid-run crash preserves every completed doc's outcome (incremental).
            $store = Read-FindingsStore $findingsJson
            Merge-DocResult -Store $store -DocPath $doc -Result $result -RunId $runId | Out-Null
            Write-FindingsStore -Store $store -Path $findingsJson
            Render-FindingsView -Store $store -Path $findingsMd
            Add-AuditLogDoc -Path $logPath -DocPath $doc -Result $result -Model $model -PromptFile 'docs-audit-prompt.md'
        }
        $skipNote = if ($Continue) { " ($resumeSkipped already-confirmed doc(s) skipped by -Continue)" } else { '' }
        Write-Host "docs-audit: done (run $runId). $(@($docs).Count) docs audited$skipNote. See docs/docs-audit-findings.md + docs/docs-audit-log.md." -ForegroundColor Green
        exit 0
    } finally {
        Exit-AuditLock $lock
    }
}

# Run main only when executed directly (dot-source for tests must NOT run it).
if ($MyInvocation.InvocationName -ne '.') { Invoke-Main }

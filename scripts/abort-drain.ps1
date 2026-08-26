#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Reject a pending drain atomically (F31): git-restore every tracked drain output, remove new untracked outputs,
  AND restore the app-data staging snapshot into ## Pending, then delete staging. Refuses if committed (F33).
.PARAMETER InboxPath
  The capture inbox (default: CLAVITY_AGY_INBOX, else <USERPROFILE|HOME>/.clavity/agy-observations.md).
.PARAMETER RepoRoot
  Repo root (default: this script's parent's parent). Overridable for tests.
#>
[CmdletBinding(SupportsShouldProcess)]   # -WhatIf previews the reject without touching the tree
param(
    [string]$InboxPath,
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }

. (Join-Path $PSScriptRoot 'drain-lib.ps1')   # param-less: no $InboxPath/$RepoRoot clobber (F-P1)

function Get-ModifiedTrackedPaths([string]$RepoRoot) {
    # Parses `git status --porcelain --untracked-files=no` into a flat list of repo-relative, forward-slash
    # paths for every tracked file that is modified/staged/conflicted. Porcelain v1 is FIXED-WIDTH: columns 1-2
    # are the XY status code, column 3 is always a single separator space, and the path field starts at column 4
    # (index 3) — so we slice by position instead of splitting on whitespace (a path can legitimately contain
    # spaces, which git does NOT quote). A rename/copy entry additionally embeds ' -> ' between the old and new
    # path inside that same field; only the NEW path (the one that still exists in the working tree) matters
    # here. Git DOES C-quote a path (wraps it in double quotes with backslash escapes) when it contains a double
    # quote, a backslash, or — under the default core.quotepath=true — non-ASCII bytes; unwrap that.
    $lines = & git -C $RepoRoot status --porcelain --untracked-files=no 2>$null
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @($lines)) {
        if (-not $line -or $line.Length -lt 4) { continue }
        $xy = $line.Substring(0, 2)
        $field = $line.Substring(3)
        if ($xy -match 'R|C') {
            $arrow = $field.IndexOf(' -> ')
            if ($arrow -ge 0) { $field = $field.Substring($arrow + 4) }
        }
        if ($field.Length -ge 2 -and $field[0] -eq '"' -and $field[$field.Length - 1] -eq '"') {
            $field = ($field.Substring(1, $field.Length - 2) -replace '\\"', '"') -replace '\\\\', '\'
        }
        $paths.Add((ConvertTo-DrainNormalizedPath $field))
    }
    return $paths
}

function Test-PathOwnedByDrain([string]$NormalizedPath, [string[]]$OwnedPaths) {
    # $OwnedPaths (Get-DrainOutputPaths — the single source of truth) may name either a file or a directory
    # (e.g. 'agy-autotrain/docs/fix-the-tool-backlog'); a modified path counts as owned if it IS that entry or lives under it.
    foreach ($owned in $OwnedPaths) {
        $ownedNorm = ConvertTo-DrainNormalizedPath $owned
        if ($NormalizedPath -ieq $ownedNorm) { return $true }
        if ($NormalizedPath.StartsWith($ownedNorm + '/', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-UnrelatedTrackedChanges([string]$RepoRoot) {
    # Every modified/staged TRACKED file that is NOT one of the drain's own outputs — i.e. work `git reset --hard`
    # would silently destroy but did not come from this drain.
    $owned = Get-DrainOutputPaths
    return @(Get-ModifiedTrackedPaths -RepoRoot $RepoRoot | Where-Object { -not (Test-PathOwnedByDrain -NormalizedPath $_ -OwnedPaths $owned) })
}

function Get-CleanCandidatePaths([string]$RepoRoot) {
    # Ask git itself which untracked files the pending `git clean -fd -- (Get-DrainOutputPaths)` (below) would
    # actually remove, via git's OWN dry-run (-n) — never re-implement clean's untracked-file matching by hand, so
    # the guard's view of "would be deleted" can never drift from the real deletion. Each real removal line reads
    # `Would remove <path>`. MEASURED 2026-08-26 in a throwaway repo, because a reviewer rightly asked how
    # anyone would know this: a wholly-untracked directory holding TWO files reported exactly ONE line,
    # `Would remove newdir/`, alongside a separate `Would remove loose.txt` for the individual file. The
    # collapse is real and this parser depends on it.
    # A WHOLLY-untracked directory (e.g. a brand-new agy-autotrain/docs/fix-the-tool-backlog/ with nothing
    # committed under it yet) is reported as ONE collapsed line ("Would remove agy-autotrain/docs/fix-the-tool-backlog/") even
    # though `clean -fd` would delete every file inside it — so any directory-shaped line (trailing '/') is expanded,
    # again via git (`ls-files --others`, not hand-rolled matching), into its individual untracked files. The result
    # is a flat, per-file candidate list the legitimacy check and the refusal message can both name precisely.
    $lines = & git -C $RepoRoot clean -nd -- (Get-DrainOutputPaths) 2>$null
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @($lines)) {
        if (-not $line -or -not ($line -match '^Would remove (.+)$')) { continue }
        $path = ConvertFrom-DrainGitQuotedPath $Matches[1]
        if ($path.EndsWith('/')) {
            $dir = $path.TrimEnd('/')
            $inner = & git -C $RepoRoot ls-files --others --exclude-standard -- $dir 2>$null
            foreach ($f in @($inner)) {
                if ($f) { $candidates.Add((ConvertTo-DrainNormalizedPath (ConvertFrom-DrainGitQuotedPath $f))) }
            }
        } else {
            $candidates.Add((ConvertTo-DrainNormalizedPath $path))
        }
    }
    return $candidates
}

function Test-PathIsKnownDrainOutputFile([string]$NormalizedPath, [string[]]$OwnedPaths, [string[]]$ManifestPaths) {
    # Deliberately NARROWER than Test-PathOwnedByDrain (used for TRACKED files, where a directory-PREFIX match is
    # correct — a tracked file nested under agy-autotrain/docs/fix-the-tool-backlog can only exist because an EARLIER drain's
    # backlog file was already reviewed, committed, and accepted). For an UNTRACKED candidate, only an EXACT match
    # against one of Get-DrainOutputPaths' individually-named FILE entries is trusted: those are fixed, unique
    # artifact names that only a drain run writes. A path merely nested under the one DIRECTORY entry
    # (agy-autotrain/docs/fix-the-tool-backlog) does NOT count — the curator names backlog files dynamically (<slug>.md), so a
    # maintainer's own untracked note dropped in that same directory during the review pause is indistinguishable,
    # by path alone, from a curator-produced one. Silently trusting "nested under the directory" for untracked
    # files is exactly the data-loss bug this guard closes: `git clean -fd` scoped to Get-DrainOutputPaths still
    # deletes anything living inside that directory, maintainer strays included.
    #
    # $ManifestPaths closes that gap WITHOUT weakening it: this run's output manifest (drain-knowledge.ps1's
    # before/after `git ls-files --others` diff over Get-DrainOutputPaths) names exactly the untracked files THIS
    # run's curator created — including dynamically-named backlog files — so an exact match against it is just as
    # trustworthy as an exact match against the fixed OwnedPaths file entries. When no manifest exists (a run that
    # predates this feature), the caller passes @() here and behavior is unchanged from before.
    foreach ($owned in $OwnedPaths) {
        if ($NormalizedPath -ieq (ConvertTo-DrainNormalizedPath $owned)) { return $true }
    }
    foreach ($manifested in $ManifestPaths) {
        if ($NormalizedPath -ieq (ConvertTo-DrainNormalizedPath $manifested)) { return $true }
    }
    return $false
}

function Get-UnrelatedUntrackedCleanTargets([string]$RepoRoot, [string[]]$ManifestPaths) {
    # Every untracked file the pending `git clean -fd -- (Get-DrainOutputPaths)` would actually delete that is NOT
    # one of the drain's own known-fixed output files, NOR (when a manifest exists for this run) one of this run's
    # recorded outputs — i.e. a maintainer stray `git clean -fd` would silently destroy but did not come from this
    # drain.
    $owned = Get-DrainOutputPaths
    return @(Get-CleanCandidatePaths -RepoRoot $RepoRoot | Where-Object { -not (Test-PathIsKnownDrainOutputFile -NormalizedPath $_ -OwnedPaths $owned -ManifestPaths $ManifestPaths) })
}

function Invoke-Main {
    $inbox = Resolve-InboxPath $InboxPath
    $inboxDir = Split-Path $inbox -Parent
    $staging = Find-StagingFile $inboxDir
    if (-not $staging) {
        Write-Host "abort-drain: no pending drain (no staging file). Nothing to abort." -ForegroundColor Green
        exit 0
    }
    $runId = Get-RunIdFromStaging $staging
    $manifestPath = Get-DrainOutputManifestPath $inboxDir $runId   # may not exist — a run that predates this feature

    # F33: if the run is already committed, aborting would re-queue committed observations — block.
    $committedLog = & git -C $RepoRoot show 'HEAD:docs/agy-drain-log.md' 2>$null
    if ($LASTEXITCODE -eq 0 -and (Test-RunIdInLog -LogText ($committedLog -join "`n") -RunId $runId)) {
        Write-Host "abort-drain: run $runId is ALREADY in the committed drain-log — use 'just accept-drain' instead." -ForegroundColor Red
        exit 1
    }

    if (-not $PSCmdlet.ShouldProcess($RepoRoot, "revert drain outputs + re-queue staging into ## Pending (reject run $runId)")) { return }

    # DATA-LOSS GUARD: the drain ran on a PRISTINE tree (drain-knowledge pre-drain guard), but that only covers
    # drain START — the documented workflow (docs/drain-knowledge-runbook.md) requires a human REVIEW PAUSE
    # between `just drain-knowledge` and `just abort-drain` so the maintainer can inspect `git diff`, and it is
    # normal for unrelated uncommitted work (a quick fix, a note, a test tweak) to land during that pause. TWO
    # separate operations below are destructive, and BOTH are gated here: `git reset --hard HEAD` is UNSCOPED — it
    # reverts every TRACKED file in the whole repo, not just the drain's outputs. `git clean -fd` IS scoped to
    # Get-DrainOutputPaths, but still deletes real work, because one of those paths (agy-autotrain/docs/fix-the-tool-backlog) is a
    # DIRECTORY: an unrelated UNTRACKED file a maintainer drops inside it during the pause is invisible to a
    # `--untracked-files=no` status query (only tracked files are checked that way) and would otherwise be silently
    # destroyed by that scoped clean. Refuse instead of guessing intent: proceed ONLY if (a) every modified/staged
    # TRACKED file is one of the drain's own outputs, AND (b) every untracked file the pending `git clean` would
    # remove is one of the drain's own known-fixed output files (Get-DrainOutputPaths — the single source of truth,
    # not re-listed here). Report both categories together so a maintainer sees every blocker in one pass.
    $unrelated = @(Get-UnrelatedTrackedChanges -RepoRoot $RepoRoot)   # @() wrap: PS unrolls an empty array return to $null otherwise, and .Count below would throw under Strict Mode
    # Manifest paths (this run's own recorded outputs) are ADDITIONAL legitimate untracked files, on top of the
    # fixed OwnedPaths file entries — see Test-PathIsKnownDrainOutputFile. Get-DrainOutputManifestEntries returns
    # @() both when the manifest is absent (legacy run — conservative fallback, unchanged) and when it is present
    # but empty (this run created nothing new); either way the guard below behaves correctly.
    $manifestPaths = @(Get-DrainOutputManifestEntries $manifestPath)
    $unrelatedUntracked = @(Get-UnrelatedUntrackedCleanTargets -RepoRoot $RepoRoot -ManifestPaths $manifestPaths)
    if ($unrelated.Count -gt 0 -or $unrelatedUntracked.Count -gt 0) {
        if ($unrelated.Count -gt 0) {
            Write-Host "abort-drain: REFUSING to abort — the working tree has tracked change(s) that are NOT part of this drain's outputs:" -ForegroundColor Red
            foreach ($f in $unrelated) { Write-Host "  $f" -ForegroundColor Red }
            Write-Host "abort-drain: 'git reset --hard HEAD' would silently DESTROY the file(s) above." -ForegroundColor Red
        }
        if ($unrelatedUntracked.Count -gt 0) {
            Write-Host "abort-drain: REFUSING to abort — the working tree has untracked file(s) under the drain's output paths that are NOT known drain outputs:" -ForegroundColor Red
            foreach ($f in $unrelatedUntracked) { Write-Host "  $f" -ForegroundColor Red }
            Write-Host "abort-drain: 'git clean -fd' would silently DELETE the file(s) above." -ForegroundColor Red
            if (-not (Test-Path $manifestPath)) {
                # NO MANIFEST HAS TWO ROUTES, and until 2026-08-26 this said "Legacy run only" and named
                # just one. The other is a MODERN run interrupted before it wrote its manifest - killed,
                # power-lost, or failed between creating a backlog file and recording it. Both arrive here
                # looking identical, and the operator cannot tell them apart either, so the message must
                # not assert which one they are: telling someone whose run died five minutes ago that
                # their install "predates output-manifest recording" sends them hunting a version problem
                # that does not exist.
                # With a manifest PRESENT, anything reaching here is provably not this run's output (the
                # manifest lists every untracked file the curator created), so the plain message above is
                # exact and this caveat would be actively misleading.
                Write-Host "abort-drain: NOTE — there is no output manifest beside this staging file, so there is no record of which backlog files its curator wrote. Either the drain predates manifest recording, or it was interrupted before writing one. A file under agy-autotrain/docs/fix-the-tool-backlog/ may therefore be THIS drain's own output: if so, delete it yourself and re-run; if it is yours, move it aside first." -ForegroundColor Yellow
            }
        }
        Write-Host "abort-drain: move, commit, or delete the file(s) above as appropriate, then re-run 'just abort-drain'. Staging ($staging) was NOT touched." -ForegroundColor Red
        exit 1
    }

    # Atomic reject. With the guard above satisfied, reverting ALL tracked files to HEAD is safe — the only
    # tracked changes are this drain's — and complete (it also catches a curator edit to a tracked file OUTSIDE
    # the known outputs, since the guard above would already have caught and refused it). Untracked strays
    # outside the known output dirs are NOT force-cleaned (never blind-delete unrelated files —
    # [[feedback-targeted-git-restore]]); they are surfaced.
    & git -C $RepoRoot reset --hard HEAD 2>$null                    # revert every tracked file to HEAD (index+worktree; handles staged outputs)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "abort-drain: 'git reset --hard HEAD' FAILED (exit $LASTEXITCODE) — tree NOT reverted; staging ($staging) retained. Fix the repo and re-run." -ForegroundColor Red
        exit 1
    }
    & git -C $RepoRoot clean -fd -- (Get-DrainOutputPaths) 2>$null  # remove the drain's own untracked outputs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "abort-drain: 'git clean' FAILED (exit $LASTEXITCODE) — staging ($staging) retained. Fix the repo and re-run." -ForegroundColor Red
        exit 1
    }
    $strays = & git -C $RepoRoot status --porcelain
    if ($strays) {
        Write-Host "abort-drain: NOTE — file(s) still differ from HEAD (a possible curator stray outside the known outputs); review + remove by hand if unwanted:`n$strays" -ForegroundColor Yellow
    }

    Restore-StagingToPending -InboxPath $inbox -StagingPath $staging
    Remove-Item -Force $staging
    if (Test-Path $manifestPath) { Remove-Item -Force $manifestPath }   # transient run state; never outlives its run — absence is not an error
    Write-Host "abort-drain: rejected run $runId — outputs restored, $((Split-Path $staging -Leaf)) re-queued into ## Pending and removed." -ForegroundColor Green
    exit 0
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-Main }

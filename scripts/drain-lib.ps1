#!/usr/bin/env pwsh
# scripts/drain-lib.ps1 — shared drain primitives. PARAMETER-LESS by design: dot-sourcing this defines functions
# ONLY, so it never binds/clobbers a caller's $InboxPath (agy plan-panel R1 F-P1) and never collides on a `main`.
Set-StrictMode -Version Latest

function Resolve-InboxPath([string]$explicit) {
    if ($explicit) { return $explicit }
    if ($env:CLAVITY_AGY_INBOX) { return $env:CLAVITY_AGY_INBOX }
    # ROADMAP 14g: the canonical inbox is USER-LOCAL, beside the golden-header files - NOT inside the
    # plugin install tree, which exists in N copies (install, checkout, every worktree) with no reliable
    # way to tell which one is live. This default used to point at the INSTALLED plugin copy, which was
    # correct only while that was the canonical location; after the move it silently drained a stale file.
    # Pinned by drain-lib.Tests.ps1.
    $home_dir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
    return Join-Path $home_dir '.clavity/agy-observations.md'
}

function Get-PendingRegionLines([string]$InboxPath) {
    # ONE scanner, used by BOTH readers below. The rule it implements is written down here because it
    # was NEVER written down before, and that omission is exactly what cost the defect described next:
    #
    #   a `## Pending` heading OPENS the region; ANY other heading line CLOSES it; scanning CONTINUES
    #   so that a second document's `## Pending` MERGES with the first.
    #
    # The closing test is `^#{1,6}\s`, NOT `^##\s`. A migrated inbox is two whole documents concatenated
    # by the installer's append (`agy-autotrain.iss`, `SaveStringsToFile(NewPath, OldLines, True)`), so
    # the second document brings its OWN `# title` line and prose preamble. A single-hash title does not
    # match `^##\s`, so the old rule KEPT it as body: MEASURED against the real template, 24 lines of
    # boilerplate prose were carried into the staging file handed to the curator, and written back into
    # the user's canonical inbox by Restore-StagingToPending on any abort. The bullet COUNT stayed
    # correct at 2 throughout, which is why every count-based test stayed green over it.
    #
    # CLOSES-AND-CONTINUES, never `break`. Breaking on the second document's title would discard that
    # document's pending bullets entirely - the opposite of the merge this reader exists to perform.
    #
    # KNOWN LIMIT, stated rather than discovered later: a fenced code block INSIDE the Pending region
    # whose content starts at column 0 with `# ` would be read as a heading and close the region early.
    # The inbox schema is one bullet per observation with prose forbidden, so that shape is not legal
    # input; it is not defended against, and this comment is the record of that choice.
    if (-not (Test-Path $InboxPath)) { return @() }
    $inPending = $false; $region = @()
    foreach ($l in (Get-Content $InboxPath)) {
        if ($l -match '^##\s+Pending\s*$') { $inPending = $true; continue }
        if ($l -match '^#{1,6}\s')          { $inPending = $false; continue }
        if ($inPending)                     { $region += $l }
    }
    return $region
}

function Get-PendingBulletCount([string]$InboxPath) {
    # F17: one-bullet-per-observation schema.
    return @(Get-PendingRegionLines $InboxPath | Where-Object { $_ -match '^- \[' }).Count
}

function Get-PendingBody([string]$InboxPath) {
    # The lines of every `## Pending` region, merged, with each document's own header excluded.
    return @(Get-PendingRegionLines $InboxPath)
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
        # Emit the body at the FIRST `## Pending` ONLY, and drop any later heading as a duplicate.
        # The 14g installer migration appends the WHOLE old document - its own header and its own
        # `## Pending` included - so this file can legitimately arrive carrying two headings. Matching
        # unconditionally emitted $body once PER heading, which duplicated the residue on every drain and
        # COMPOUNDED cycle over cycle. Get-PendingBody already MERGES both sections into a single body,
        # so the correct round-trip is one heading with one body: a second heading is redundant, and
        # dropping it here is what makes a malformed inbox self-heal on the next drain instead of
        # re-triggering this forever. Pinned by the two-heading test in drain-lib.Tests.ps1.
        if ($l -match '^##\s+Pending\s*$') {
            if (-not $emitted) { $out += $l; $out += $body; $emitted = $true }
            $inPending = $true
            continue
        }
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
    # CAPSTONE-F2: write staging to a .tmp, clear the inbox, THEN rename tmp -> the real staging path. This makes the
    # presence of the REAL staging file IMPLY the inbox was already cleared. If the clear throws (e.g. a concurrent
    # lock on the inbox from an agy-learn append), no real staging file exists — only the .tmp, which
    # Find-StagingFile's `agy-observations.staging.*.md` glob does NOT match — so the state is clean and NON-
    # duplicating: a later abort cannot re-queue the staged body on top of a still-full inbox and double every entry
    # (the pre-fix write-then-clear order left exactly that "staging exists + inbox full" state on a partial failure).
    $tmp = $StagingPath + '.tmp'
    [System.IO.File]::WriteAllText($tmp, (((Get-PendingBody $InboxPath) -join "`n") + "`n"))  # LF (D2)
    Set-PendingBody -InboxPath $InboxPath -body @()   # leave the ## Pending body EMPTY
    Move-Item -LiteralPath $tmp -Destination $StagingPath -Force   # near-atomic rename; staging appears only post-clear
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
    # EXTEND model: the curator writes ONLY these tracked repo files. The runtime GROWTH file
    # (~/.clavity/golden-header.growth.md) is published separately at ACCEPT time via `curate-commit`,
    # never by the curator. seed/golden-header.md, the 4 driver manuals, and driver-cheatsheet.core.md are
    # driver-owned + PROTECTED (check-core-integrity.ps1 asserts them byte-unchanged) — never drain outputs.
    return @(
        'docs/agy-golden-header.growth.md'   # the compiled, reviewable GROWTH proposal (piped to curate-commit at accept)
        'docs/agy-drain-log.md'
        'docs/agy-verify-needed.md'
        'docs/agy-drain-proposal.md'         # rationale sidecar (Promoted/Dropped/Parked/Proposed-*)
        'docs/fix-the-tool-backlog'
    )
}

function ConvertTo-DrainNormalizedPath([string]$Path) {
    # repo-relative, forward-slash, no trailing slash — the comparison shape for `git status`/`git ls-files`
    # paths, Get-DrainOutputPaths entries, and manifest entries alike. Shared by drain-knowledge.ps1 (writing
    # the output manifest) and abort-drain.ps1 (the untracked-clean guard) so both sides normalize identically.
    return ($Path -replace '\\', '/').TrimEnd('/')
}

function ConvertFrom-DrainGitQuotedPath([string]$Field) {
    # Git C-quotes a path (wraps it in double quotes with backslash escapes) when it contains a double quote, a
    # backslash, or — under the default core.quotepath=true — non-ASCII bytes. True for `status`, `clean`, and
    # `ls-files` output alike; unwrap it so downstream path comparisons see the real path.
    if ($Field.Length -ge 2 -and $Field[0] -eq '"' -and $Field[$Field.Length - 1] -eq '"') {
        return ($Field.Substring(1, $Field.Length - 2) -replace '\\"', '"') -replace '\\\\', '\'
    }
    return $Field
}

function Get-DrainOutputManifestPath([string]$InboxDir, [string]$RunId) {
    # Beside the staging snapshot, named for the SAME run id, but with a .outputs.txt extension so it never
    # matches Find-StagingFile's `agy-observations.staging.*.md` glob.
    return Join-Path $InboxDir "agy-observations.staging.$RunId.outputs.txt"
}

function Get-UntrackedDrainOutputFiles([string]$RepoRoot) {
    # The untracked files git itself reports under Get-DrainOutputPaths right now — the raw material for the
    # before/after diff drain-knowledge.ps1 uses to derive its output manifest. Never hand-roll this: asking git
    # is what makes the manifest correct without trusting the curator to self-report.
    $lines = & git -C $RepoRoot ls-files --others --exclude-standard -- (Get-DrainOutputPaths) 2>$null
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($l in @($lines)) {
        if ($l) { $paths.Add((ConvertTo-DrainNormalizedPath (ConvertFrom-DrainGitQuotedPath $l))) }
    }
    return @($paths)
}

function Write-DrainOutputManifest([string]$ManifestPath, [string[]]$Paths) {
    # One repo-relative, forward-slash path per line, UTF-8 no BOM, LF endings (File.WriteAllText's documented
    # default — matches every other LF write in this file, D2). An empty set writes a truly empty file (0
    # bytes), which is a VALID manifest meaning "this run created no new untracked files" — distinct from the
    # file being ABSENT, which means "this run predates the manifest" (abort-drain.ps1 falls back on that).
    # Written atomically (tmp + rename), matching the golden-header sidecar discipline in the same change
    # set. This file is a TRUST BOUNDARY: abort-drain treats every path it names as safe to delete via
    # `git clean -fd`, so a reader must never see it half-written. A truncated manifest would in fact fail
    # SAFE today (an unmatched line simply is not recognised, so abort-drain refuses) — but a trust boundary
    # should not depend on its failure mode happening to be the lucky one.
    $arr = @($Paths)
    $body = ''
    if ($arr.Count -gt 0) { $body = ($arr -join "`n") + "`n" }
    $tmp = $ManifestPath + '.tmp'
    [System.IO.File]::WriteAllText($tmp, $body)
    Move-Item -LiteralPath $tmp -Destination $ManifestPath -Force
}

function Get-DrainOutputManifestEntries([string]$ManifestPath) {
    # @() wrap: PS unrolls an empty array return to $null otherwise, and callers' .Count/-contains would break
    # under Strict Mode. Absent file and empty file both yield @() — callers that need to distinguish "no
    # manifest" (legacy run, fall back to the conservative guard) from "manifest present but empty" (this run
    # created nothing new) must Test-Path the manifest themselves; this function only reads entries.
    if (-not (Test-Path $ManifestPath)) { return @() }
    return @(Get-Content $ManifestPath | Where-Object { $_ -ne '' })
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

function Get-GrowthProposalBytes([string]$RepoRoot) {
    # RAW on-disk byte length of the compiled GROWTH proposal; 0 when absent (first pass / aborted run). Measure
    # raw bytes, NOT GetByteCount(ReadAllText) — ReadAllText strips a UTF-8 BOM and substitutes invalid bytes with
    # U+FFFD, under-counting the true on-disk size the binary's raw-byte read sees (panel agy-A6).
    $p = Join-Path $RepoRoot 'docs/agy-golden-header.growth.md'
    if (-not (Test-Path $p)) { return 0 }
    return (Get-Item -LiteralPath $p).Length
}

function Get-DrainProtectedPaths {
    # Driver-owned files the curator must NEVER touch (asserted byte-unchanged by check-core-integrity.ps1). Used
    # by drain-knowledge's step-6 failure path to targeted-revert a rogue curator edit, and by the docs — never a
    # drain OUTPUT. Kept as a single source of truth so the gate default and the revert list cannot drift.
    return @(
        'seed/golden-header.md'
        'clavity-dotnet/plugin/knowledge/agy-assumptions.md'
        'clavity-dotnet/plugin/knowledge/agy-capabilities.md'
        'clavity-classic/plugin/knowledge/agy-assumptions.md'
        'clavity-classic/plugin/knowledge/agy-capabilities.md'
        'agy-autotrain/knowledge/driver-cheatsheet.core.md'
    )
}

function Resolve-CurateCommitExe {
    # The binary that publishes the reviewed GROWTH proposal to the runtime path. Override wins (tests / a
    # non-PATH install); else prefer the dotnet CLI, then classic. $null => no driver installed (accept warns
    # and proceeds — the proposal is already committed and can be published by hand later).
    if ($env:CLAVITY_CURATE_COMMIT_EXE) { return $env:CLAVITY_CURATE_COMMIT_EXE }
    foreach ($name in @('clavity-ls', 'clavity')) {
        $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

function Invoke-CurateCommit([string]$Exe, [string]$GrowthPath, [string[]]$ArgList = @('curate-commit')) {
    # Publish $GrowthPath's RAW UTF-8 BYTES to the exe's stdin via a Process (NOT a pwsh pipe): pwsh string
    # piping re-encodes through the console code page (Windows OEM CP437), the exact mojibake `curate-commit`
    # exists to reject (an em dash became "Γ Ç ö"). Feeding the raw bytes to the base stream is the only safe
    # transport. Returns the process exit code (0 ok; curate-commit uses 2 = bad input/over-cap, 1 = IO).
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Exe
    foreach ($a in $ArgList) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardInput = $true
    $psi.UseShellExecute = $false
    # Read the payload BEFORE starting the child (panel agy-R2-2): if ReadAllBytes throws (file removed/unreadable
    # between accept's Test-Path and here), we must NOT already have a started clavity-ls orphaned forever waiting
    # on stdin. With the bytes in hand first, Start is the last thing that can fail here.
    # Guard against loading an absurd file into RAM (capstone R3-2, Resource Vampire): curate-commit's real limit is
    # 16 KiB, so anything past a generous 1 MiB bound is invalid GROWTH — return curate-commit's over-cap code (2)
    # WITHOUT reading it, rather than OOM'ing the accept process on a hallucinated/malicious multi-GB proposal.
    if ((Get-Item -LiteralPath $GrowthPath).Length -gt 1MB) { return 2 }
    $bytes = [System.IO.File]::ReadAllBytes($GrowthPath)
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        # The exe resolved but the OS refused to LAUNCH it (Win32Exception — AV block, execution policy, corrupt
        # binary, missing after a TOCTOU). Return a non-zero code so accept-drain's caller maps it to 'failed'
        # (staging retained, graceful message) instead of crashing the accept transaction mid-flight under the
        # caller's $ErrorActionPreference='Stop' (capstone F1). 127 = the shell "could not execute" convention;
        # any non-zero routes to the 'failed' arm. Nothing was started, so there is no child/handle to clean up.
        return 127
    }
    try {
        $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $proc.StandardInput.BaseStream.Flush()
    } catch [System.IO.IOException] {
        # Broken pipe: the child rejected input and exited early (e.g. over-cap → curate-commit stops reading at
        # MaxBytes+1 and returns exit 2 BEFORE draining stdin). This is NOT a script failure — swallow it and let
        # the child's own exit code speak. Without this catch the IOException propagates and, under the caller's
        # $ErrorActionPreference='Stop', crashes accept-drain mid-transaction, bypassing its error switch (panel
        # F4/agy-A2). Only IOException is caught; anything else still surfaces.
    } finally {
        try { $proc.StandardInput.Close() } catch [System.IO.IOException] { }
    }
    $proc.WaitForExit()
    $code = $proc.ExitCode
    $proc.Dispose()   # release the OS process handle (panel R2-F2); one-per-accept, but do not leak it
    return $code
}

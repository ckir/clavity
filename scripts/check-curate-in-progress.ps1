#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Pre-commit guard: refuse to commit a driver-cheatsheet pinned file while an agy-curate run is in
  flight or ended abnormally. Read-only - inspects, never writes or reverts.
.DESCRIPTION
  agy-curate distils machine-local captures into the canonical driver cheatsheet and its two
  compiled-in pins. Those edits are flushed to the working tree BEFORE the human approval gate, on
  purpose, so the human can inspect them with `git diff` while deciding. If the run then ends in any
  way other than completing normally, that unreviewed content is left sitting in the tree with only a
  STDERR warning protecting it, and `git commit -a` invokes no `just` recipe, so no test-side check
  can intervene. This is the enforcement half.

  THE MARKER IS INVERTED, AND THAT IS THE WHOLE DESIGN. agy-curate writes
  `.clavity/curate-in-progress` as its FIRST act and deletes it ONLY on a normal completion. So the
  marker's PRESENCE is the predicate "a run started and did not finish normally" - directly, with no
  exit code to interpret.

  Writing the marker on abort instead would be strictly worse in two ways. It would need the dying
  process to still be able to write, so a `kill -9`, an OOM, or a power cut would leave NO marker and
  the guard would silently pass - a guard that fails open certifies what it stopped checking. And it
  would make the agent evaluate a predicate at exit time that agy-curate's own SKILL.md records
  getting WRONG in five distinct formulations before it settled. Writing at startup is unconditional;
  there is no predicate to get wrong.

  KNOWN LIMIT, accepted deliberately: `--no-verify` bypasses this, as it bypasses any hook. The goal
  is to stop an inattentive commit, not an adversarial one.
.PARAMETER RepoRoot
  Repository root. Defaults to the parent of this script's directory.
.PARAMETER MarkerPath
  Full path to the in-progress marker. Defaults to <RepoRoot>/.clavity/curate-in-progress.
  Exposed for the test suite; no caller should need it.

.NOTES
  THE STAGED LIST COMES FROM GIT, AND IS NOT A PARAMETER. An earlier draft accepted the paths so
  lefthook could pass {staged_files}, and that does not survive `pwsh -File`: it binds only the FIRST
  element of a multi-value argument to a [string[]] parameter and reports the second as an unmatched
  positional, dying with "A positional parameter cannot be found". Because this guard FAILS CLOSED,
  that death was not loud - it surfaced as a blocked commit on any commit staging two or more files,
  which is nearly all of them. `ValueFromRemainingArguments` does NOT fix it under `-File`.

  Asking git directly removes the failure mode rather than working around it, and git is the authority
  on what is staged in any case. The hook stays a one-liner with no argument plumbing at all.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$MarkerPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# THE THREE FILES agy-curate/SKILL.md:91-95 PINS BYTE-IDENTICAL. Hardcoded rather than derived: the
# pin is a fact about those three paths, and a derivation would need the very content this guard
# exists to distrust. `check-curate-in-progress.Tests.ps1` asserts all three exist on disk, so a
# rename that orphans this list reds a test instead of silently protecting nothing.
$script:PinnedFiles = @(
    'agy-autotrain/knowledge/driver-cheatsheet.core.md'
    'clavity-classic/src/driver_cheatsheet.rs'
    'clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs'
)

# FAIL CLOSED. Every failure below - an unreadable marker, a git invocation that dies, a bug in this
# script - blocks the commit and says why. The alternative silently certifies a check that never ran.
# The cost is bounded because lefthook's glob only invokes this when a pinned file is actually staged,
# so a misfire blocks a rare commit rather than everyday work.
try {
    if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
    if (-not $MarkerPath) { $MarkerPath = Join-Path $RepoRoot '.clavity/curate-in-progress' }

    if (-not (Test-Path -LiteralPath $MarkerPath)) {
        Write-Host "check-curate-in-progress: OK - no agy-curate run outstanding" -ForegroundColor Green
        exit 0
    }

    # `git -C` rather than Push-Location: no directory state to restore if this throws mid-way.
    # CHECK GIT'S OWN EXIT CODE. A native command does not throw on failure, so without this a git that
    # cannot read the index returns nothing and the empty list below reads as "no pinned file staged" -
    # the guard would wave the commit through on the strength of an error. That is the fail-open shape
    # this whole script exists to avoid, and it would be invisible.
    # NO --diff-filter. An earlier version passed --diff-filter=ACM and that is a hole: a staged RENAME
    # reports status R, which ACM excludes, so the destination path vanishes from this list entirely and
    # the guard passes while the marker is present. MEASURED both ways - `git mv other.md <pinned>` on a
    # destination absent from HEAD yields `R100` and `--diff-filter=ACM` returns EMPTY, while the same
    # move onto a destination that IS in HEAD yields `M` and is caught. So today's tree happens to be
    # safe only because all three pinned files are tracked - the guard would be relying on an incidental
    # fact about the repository rather than on its own logic. Taking every staged status costs nothing:
    # a staged deletion of a pinned file also blocks, which is not wrong.
    $StagedFiles = @(git -C $RepoRoot diff --cached --name-only 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git could not list staged files in '$RepoRoot' (exit $LASTEXITCODE): $($StagedFiles -join '; ')"
    }

    # git reports repo-relative, forward-slash paths, so there is nothing to strip - only blank lines to
    # drop. An earlier version also tried to strip an absolute repo-root prefix; since git never emits
    # one, that branch could never run. It was removed rather than left as reassurance: dead defensive
    # code is untestable by construction, and a mutant inside it would have escaped the suite silently.
    $normalised = @(foreach ($f in $StagedFiles) {
        if ([string]::IsNullOrWhiteSpace($f)) { continue }
        $f.Trim().Replace('\', '/')
    })

    $offending = @($normalised | Where-Object { $_ -in $script:PinnedFiles })

    if ($offending.Count -eq 0) {
        Write-Host "check-curate-in-progress: OK - a run is outstanding, but no pinned file is staged" -ForegroundColor Green
        exit 0
    }

    # Name the files. A count sends a reader hunting; a name sends them to the file.
    Write-Host ""
    Write-Host "check-curate-in-progress: BLOCKED" -ForegroundColor Red
    Write-Host ""
    Write-Host "  An agy-curate run started and did not finish normally, and you are committing:" -ForegroundColor Red
    foreach ($o in $offending) { Write-Host "      $o" -ForegroundColor Red }
    Write-Host ""
    Write-Host "  Those files may hold cheatsheet content distilled from untrusted machine-local"
    Write-Host "  captures that NO human approved. Do not commit them, and do not build from them,"
    Write-Host "  until you have looked at them:"
    Write-Host ""
    Write-Host "      git diff --cached -- $($offending -join ' ')"
    Write-Host ""
    Write-Host "  Then choose one - the marker clears itself on the first path, by hand on the others:"
    Write-Host ""
    Write-Host "    KEEP the work   re-run the agy-curate skill and let it finish normally. Nothing is"
    Write-Host "                    lost by re-running: an abnormal ending leaves the inbox's pending"
    Write-Host "                    entries intact by design, so they are re-distilled, not discarded."
    Write-Host "                    THIS IS THE ONLY OPTION HERE THAT DESTROYS NOTHING."
    Write-Host ""
    Write-Host "    DISCARD it      git restore --staged --worktree -- $($offending -join ' ')"
    Write-Host "                    then:  Remove-Item '$MarkerPath'"
    Write-Host "                    WARNING - this throws away EVERY change to those files, staged and"
    Write-Host "                    unstaged alike, including any edit of your own that happens to sit in"
    Write-Host "                    the same file. There is no undo. Read the diff above first."
    Write-Host ""
    Write-Host "    KEEP IT ANYWAY  you have read the diff above and vouch for the content yourself:"
    Write-Host "                    Remove-Item '$MarkerPath'"
    Write-Host ""
    Write-Host "  Clearing the marker without doing one of those three is how unreviewed content ships."
    Write-Host ""
    exit 1
}
catch {
    # Deliberately not a bare `exit 1` with no message: a guard that blocks without saying why is
    # indistinguishable from a broken repository, and that is what teaches people to reach for
    # --no-verify by reflex.
    Write-Host "check-curate-in-progress: BLOCKED - the guard itself failed, so it is refusing to certify this commit." -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Fix the guard, or bypass this one commit with --no-verify if you are certain."
    exit 1
}

#!/usr/bin/env pwsh
# Fails when an INSTALLED plugin tree has drifted from the repo payload at a DECLARED sha.
#
# WHY THIS EXISTS. MEASURED 2026-08-31: the installed clavity plugin differed from the repo in 16 files,
# was missing 3 outright and carried 1 stray backup, while BOTH sides reported "version": "0.7.0". A
# version string that does not move when 193 lines do is not a detector, so this compares CONTENT.
#
# WHY A DECLARED SHA AND NOT HEAD. A phase that edits a review skill must sometimes run its review under
# the PRE-change rules; pinning the check to ambient HEAD would make that impossible to satisfy (install
# the older copy and the check reds; satisfy the check and the review runs under the rules it is
# reviewing). Naming the sha dissolves that: the caller declares what the install is supposed to be.
#
# WHY NORMALIZED COMPARISON. The installed tree is a copy of a WORKTREE (CRLF for .md/.json under
# core.autocrlf, LF for .sh), while `git show` returns the COMMITTED form (LF). MEASURED: raw-byte
# comparison reports 19 drifted files where 16 have really drifted. CRLF -> LF, then hash.
#
# EXIT CODES: 0 = clean * 1 = any of DRIFTED, MISSING, EXTRA or UNREADABLE * 2 = CANNOT CHECK, which
# is: a bad sha, an installed root that is absent or not a directory, a payload path matching nothing,
# LOCALAPPDATA unset with no -InstalledRoot, or git not on PATH. Keep this list COMPLETE - rounds 8 and
# 9 each added a cause and left the enumeration behind, which is how a contract stops being one.
# The 1-clause used to read "drift OR an unreadable payload file", which was wrong twice over: UNREADABLE
# is the INSTALLED file, not the payload, and $bad sums FOUR buckets while the prose named two.
# AGY-CAPSTONE round 8.
# 2 is deliberately NOT 0: a checker that cannot check must never report clean.
[CmdletBinding()]
param(
    [string]$Sha           = 'HEAD',
    [string]$RepoRoot,
    [string]$InstalledRoot,
    [string]$PluginPath    = 'clavity-dotnet/plugin'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -LiteralPath. `Resolve-Path <path>` binds the WILDCARD parameter set, and `[` and `]` are legal
# Windows filename characters - so a clone under a path like `repo[wip]` is treated as a GLOB.
# MEASURED at AGY-CAPSTONE round 10: it resolved to NOTHING and `.Path` on $null threw, exiting 1
# (the drift code) for an environment that could not be read; with a glob-matching sibling
# present it resolves to the WRONG DIRECTORY and the whole report is computed against a
# repository the script is not in. Every other path call in this file already uses
# -LiteralPath; this was the one that was missed, three rounds running.
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath }
function Fail2([string]$m) { Write-Host "check-plugin-drift: $m" -ForegroundColor Yellow; exit 2 }

if (-not $InstalledRoot) {
    # $env:LOCALAPPDATA IS NOT GUARANTEED. It is absent in a Windows service or scheduled-task context,
    # in some SSH sessions, and on every non-Windows host. MEASURED at AGY-CAPSTONE round 9: Join-Path
    # then failed to bind and the run died with "Cannot bind argument to parameter 'Path'" instead of the
    # contracted exit 2 - so an UNCONFIGURABLE ENVIRONMENT was indistinguishable from a DRIFTED INSTALL,
    # the exact mislabelling this file has now been bitten by four times.
    if (-not $env:LOCALAPPDATA) {
        Fail2 "no -InstalledRoot was given and `$env:LOCALAPPDATA is not set, so the default install path cannot be built - nothing was checked"
    }
    $InstalledRoot = Join-Path $env:LOCALAPPDATA 'Programs\clavity-dotnet\plugins\clavity'
}


# GIT ITSELF MUST BE PRESENT. Under `$ErrorActionPreference = 'Stop'` a missing `git` raises a
# TERMINATING CommandNotFoundException, which fires BEFORE any $LASTEXITCODE check below can classify
# it - so the run died with exit 1, the DRIFT code, for an environment that could not be checked at all.
# MEASURED at AGY-CAPSTONE round 9 with PATH stripped to System32. Probe it first and fail with 2.
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Fail2 "git is not on PATH, so nothing about the repository could be read - nothing was checked"
}

# --- the sha must EXIST, not merely look like one -------------------------------------------------
# `agy-mark.sh` shipped the other shape (accept any 40-char string) and wrote a phantom marker on
# 2026-08-31. Shape is not existence.
& git -C $RepoRoot cat-file -e "$Sha^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) { Fail2 "declared sha '$Sha' does not exist in $RepoRoot - cannot check" }
$resolved = (& git -C $RepoRoot rev-parse $Sha).Trim()

# -PathType Container. MEASURED at AGY-CAPSTONE round 6: a FILE passed a bare Test-Path and the run
# then reported all 30 payload files MISSING - it failed CLOSED, so this is diagnosis quality rather
# than a crash, but 30 wrong lines is a worse answer than one right one.
# CANONICALISE IT FIRST. `$_.FullName` below is always absolute and $InstalledRoot was used as a raw
# string PREFIX, so a relative path or a `..` segment made the Substring arithmetic wrong. MEASURED
# at AGY-CAPSTONE round 8: a `..` segment threw "startIndex cannot be larger than length of string"
# and exited 1 - the DRIFT code - having compared nothing. Resolve-Path is already applied to the
# sibling parameter above; this is the same idiom applied to one of a pair and not the other.
# .ProviderPath, NOT .Path - and this is round 8's OWN fix shipping its own edge, the ninth round
# running that has happened. `.Path` is PROVIDER-QUALIFIED: for a path addressed through a PSDrive
# (PowerShell 7 defines `Temp:` out of the box, and `TestDrive:` is the idiomatic Pester spelling)
# it returns `Temp:\x`, which is NOT a prefix of the absolute `$_.FullName` below and cannot be
# handed to [IO.File]. MEASURED at AGY-CAPSTONE round 9 on a CLEAN, IDENTICAL install addressed as
# `Temp:\...`: EXTRA plus UNREADABLE, exit 1, and the report told the operator to hand-delete a real
# payload file. That is strictly worse than the crash it replaced - a confident WRONG answer beats a
# loud one only in the sense that nobody notices it.
if (Test-Path -LiteralPath $InstalledRoot) { $InstalledRoot = (Resolve-Path -LiteralPath $InstalledRoot).ProviderPath }
if (-not (Test-Path -LiteralPath $InstalledRoot -PathType Container)) {
    Fail2 "installed root '$InstalledRoot' is not a directory - the plugin is not installed there, so nothing was checked"
}

$prefix = $PluginPath.TrimEnd('/') + '/'
# -c core.quotePath=false. Git C-QUOTES a non-ASCII path by default (`"plugin/caf\303\251.md"`),
# and the quoted form fails the StartsWith below, so the file drops out of $repoFiles entirely: its
# content is never compared AND it then surfaces as EXTRA, telling the operator to delete a real
# payload file. MEASURED at AGY-CAPSTONE round 9 with a `café.md` fixture. Latent today - zero
# quoted paths in the payload or the index - which is the same standing on which the uppercase-sha
# fold was accepted in round 8.
$repoFiles = @(& git -C $RepoRoot -c core.quotePath=false ls-tree -r --name-only $resolved -- $PluginPath |
    Where-Object { $_ -and $_.StartsWith($prefix) } |
    ForEach-Object { $_.Substring($prefix.Length) })
if ($repoFiles.Count -eq 0) { Fail2 "no files under '$PluginPath' at $resolved - wrong payload path?" }

# -Force, or a HIDDEN stray is invisible. MEASURED at AGY-CAPSTONE round 8: the identical stray file
# reported EXTRA when normal, and produced "OK - N payload file(s) identical" with exit 0 once the
# Hidden attribute was set. EXTRA is the one outcome a reinstall cannot fix, so telling the operator
# the tree is clean is the worst available answer. -Force also recurses INTO hidden directories.
# COLLECT ENUMERATION ERRORS RATHER THAN DYING ON THEM. Under `$ErrorActionPreference = 'Stop'` a
# single unreadable SUBDIRECTORY (an ACL deny, a reparse point into somewhere denied) made this whole
# statement terminate, so the run exited 1 - the DRIFT code - having compared nothing. An unreadable
# FILE has been a first-class outcome since round 3; the directory case was not. MEASURED at
# AGY-CAPSTONE round 10 with an icacls deny ACE. Silently skipping is NOT acceptable either: a stray
# hiding under an unreadable directory would go unreported, which is the EXTRA fail-open all over
# again. So: enumerate best-effort, and report every directory we could not read.
$enumErrors = @()
$installed = @(Get-ChildItem -LiteralPath $InstalledRoot -Recurse -File -Force -ErrorAction SilentlyContinue -ErrorVariable +enumErrors |
    ForEach-Object { $_.FullName.Substring($InstalledRoot.Length).TrimStart('\', '/') -replace '\\', '/' })

function Get-BlobBytes {
    param([string]$RepoRoot, [string]$Rev, [string]$Path)
    # RAW BYTES via the process BaseStream - the repo's documented raw-byte transport (the same one
    # curate-commit uses on stdin, and for the same reason).
    #
    # MEASURED 2026-08-31 against `git cat-file -s` as ground truth on an 8142-byte blob:
    #   `git cat-file blob ... | Set-Content -AsByteStream`  ->  0 bytes, and it THROWS
    #        "Cannot proceed with byte encoding. When using byte encoding the content must be of type byte."
    #        because a PowerShell pipeline delivers STRINGS, not bytes.
    #   ProcessStartInfo + BaseStream                        ->  8142 bytes, exact.
    # Do not "simplify" this back into a pipeline.
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'git'
    foreach ($a in @('-C', $RepoRoot, 'cat-file', 'blob', "${Rev}:${Path}")) { $null = $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $p  = [System.Diagnostics.Process]::Start($psi)
    $ms = [IO.MemoryStream]::new()
    try {
        $p.StandardOutput.BaseStream.CopyTo($ms)
        $p.WaitForExit()
        if ($p.ExitCode -ne 0) { throw "git cat-file blob ${Rev}:${Path} exited $($p.ExitCode)" }
        # The leading comma stops PowerShell unrolling the array into the pipeline.
        ,$ms.ToArray()
    # DISPOSE THE PROCESS TOO. It was leaked once per payload file - 30 handles on the real payload -
    # and this function is the one place in either checker that allocates an OS handle in a loop.
    } finally { $ms.Dispose(); if ($p) { $p.Dispose() } }
}

function Get-NormalizedHash([byte[]]$Bytes) {
    # CRLF -> LF on the RAW BYTES; do not round-trip through a string, which would re-encode.
    $out = [System.Collections.Generic.List[byte]]::new($Bytes.Length)
    for ($i = 0; $i -lt $Bytes.Length; $i++) {
        if ($Bytes[$i] -eq 13 -and ($i + 1) -lt $Bytes.Length -and $Bytes[$i + 1] -eq 10) { continue }
        $out.Add($Bytes[$i])
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { -join ($sha.ComputeHash($out.ToArray()) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha.Dispose() }
}

$drifted = @(); $missing = @(); $extra = @(); $unreadable = @(); $same = 0
foreach ($f in ($repoFiles | Sort-Object)) {
    $ip = Join-Path $InstalledRoot ($f -replace '/', [IO.Path]::DirectorySeparatorChar)
    # -PathType Leaf: a bare Test-Path is TRUE for a DIRECTORY, and the sibling checker shipped exactly
    # that bug (AGY-CAPSTONE round 2). A directory where a payload file belongs is MISSING, not present.
    if (-not (Test-Path -LiteralPath $ip -PathType Leaf)) { $missing += $f; continue }
    $rb = Get-BlobBytes -RepoRoot $RepoRoot -Rev $resolved -Path "${prefix}${f}"
    # AN INSTALLED FILE CAN BE UNREADABLE - exclusively locked by an editor or a running process, or
    # denied by an ACL. MEASURED at AGY-CAPSTONE round 3 with a real FileShare::None lock: ReadAllBytes
    # threw an unhandled IOException and the run died mid-scan, so every file after it went unchecked
    # while the exit code still read as ordinary drift. Report it and keep scanning; it is a first-class
    # outcome, not a crash.
    try {
        $ib = [IO.File]::ReadAllBytes($ip)
    } catch {
        # GetBaseException - see the twin in check-roadmap-claims.ps1. PowerShell wraps every .NET
        # method-call exception, so this printed MethodInvocationException for every cause alike.
        $unreadable += "$f ($($_.Exception.GetBaseException().GetType().Name))"
        continue
    }
    if ((Get-NormalizedHash $rb) -ne (Get-NormalizedHash $ib)) { $drifted += $f } else { $same++ }
}
foreach ($f in ($installed | Sort-Object)) { if ($repoFiles -notcontains $f) { $extra += $f } }
foreach ($e in $enumErrors) {
    $target = if ($e.TargetObject) { "$($e.TargetObject)" } else { '<unknown path>' }
    $unreadable += "$target (directory could not be enumerated - a stray under it would be invisible)"
}

foreach ($f in $missing)    { Write-Host "MISSING     $f" -ForegroundColor Red }
foreach ($f in $drifted)    { Write-Host "DRIFTED     $f" -ForegroundColor Red }
foreach ($f in $extra)      { Write-Host "EXTRA       $f" -ForegroundColor Red }
foreach ($f in $unreadable) { Write-Host "UNREADABLE  $f" -ForegroundColor Red }

$bad = $missing.Count + $drifted.Count + $extra.Count + $unreadable.Count
if ($bad -gt 0) {
    Write-Host ""
    Write-Host ("check-plugin-drift: {0} file(s) differ from {1} ({2} drifted, {3} missing, {4} extra, {5} unreadable, {6} identical)" -f `
        $bad, $resolved.Substring(0, 7), $drifted.Count, $missing.Count, $extra.Count, $unreadable.Count, $same) -ForegroundColor Red
    Write-Host "Reinstall the plugin, then re-run. Until then every discipline is running instructions nobody has verified." -ForegroundColor Red
    if ($extra.Count -gt 0) {
        # A REINSTALL CANNOT CLEAR AN EXTRA FILE, so do not send the operator round a loop that
        # cannot terminate. MEASURED 2026-08-31: clavity-dotnet.iss has no [InstallDelete] and Inno
        # `ignoreversion` overwrites without removing, so .mcp.json.bak-2026-08-25 survived a full
        # reinstall and had to be deleted by hand.
        Write-Host "EXTRA files are NOT removed by a reinstall (the installer overwrites, it never deletes) - delete them by hand first." -ForegroundColor Red
    }
    exit 1
}
Write-Host ("check-plugin-drift: OK - {0} payload file(s) identical to {1}" -f $same, $resolved.Substring(0, 7)) -ForegroundColor Green
exit 0

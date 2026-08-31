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
# EXIT CODES: 0 = clean * 1 = drift found * 2 = CANNOT CHECK (bad sha, absent install, bad payload path).
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

if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
if (-not $InstalledRoot) {
    $InstalledRoot = Join-Path $env:LOCALAPPDATA 'Programs\clavity-dotnet\plugins\clavity'
}

function Fail2([string]$m) { Write-Host "check-plugin-drift: $m" -ForegroundColor Yellow; exit 2 }

# --- the sha must EXIST, not merely look like one -------------------------------------------------
# `agy-mark.sh` shipped the other shape (accept any 40-char string) and wrote a phantom marker on
# 2026-08-31. Shape is not existence.
& git -C $RepoRoot cat-file -e "$Sha^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) { Fail2 "declared sha '$Sha' does not exist in $RepoRoot - cannot check" }
$resolved = (& git -C $RepoRoot rev-parse $Sha).Trim()

if (-not (Test-Path -LiteralPath $InstalledRoot)) {
    Fail2 "installed root '$InstalledRoot' does not exist - the plugin is not installed, so nothing was checked"
}

$prefix = $PluginPath.TrimEnd('/') + '/'
$repoFiles = @(& git -C $RepoRoot ls-tree -r --name-only $resolved -- $PluginPath |
    Where-Object { $_ -and $_.StartsWith($prefix) } |
    ForEach-Object { $_.Substring($prefix.Length) })
if ($repoFiles.Count -eq 0) { Fail2 "no files under '$PluginPath' at $resolved - wrong payload path?" }

$installed = @(Get-ChildItem -LiteralPath $InstalledRoot -Recurse -File |
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
    } finally { $ms.Dispose() }
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

$drifted = @(); $missing = @(); $extra = @(); $same = 0
foreach ($f in ($repoFiles | Sort-Object)) {
    $ip = Join-Path $InstalledRoot ($f -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $ip)) { $missing += $f; continue }
    $rb = Get-BlobBytes -RepoRoot $RepoRoot -Rev $resolved -Path "${prefix}${f}"
    $ib = [IO.File]::ReadAllBytes($ip)
    if ((Get-NormalizedHash $rb) -ne (Get-NormalizedHash $ib)) { $drifted += $f } else { $same++ }
}
foreach ($f in ($installed | Sort-Object)) { if ($repoFiles -notcontains $f) { $extra += $f } }

foreach ($f in $missing) { Write-Host "MISSING  $f" -ForegroundColor Red }
foreach ($f in $drifted) { Write-Host "DRIFTED  $f" -ForegroundColor Red }
foreach ($f in $extra)   { Write-Host "EXTRA    $f" -ForegroundColor Red }

$bad = $missing.Count + $drifted.Count + $extra.Count
if ($bad -gt 0) {
    Write-Host ""
    Write-Host ("check-plugin-drift: {0} file(s) differ from {1} ({2} drifted, {3} missing, {4} extra, {5} identical)" -f `
        $bad, $resolved.Substring(0, 7), $drifted.Count, $missing.Count, $extra.Count, $same) -ForegroundColor Red
    Write-Host "Reinstall the plugin, then re-run. Until then every discipline is running instructions nobody has verified." -ForegroundColor Red
    exit 1
}
Write-Host ("check-plugin-drift: OK - {0} payload file(s) identical to {1}" -f $same, $resolved.Substring(0, 7)) -ForegroundColor Green
exit 0

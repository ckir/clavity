<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

#requires -Version 5.1
# Licence consistency gate. Exit 1 (every problem printed, one per line) when any of these fails:
#   license-copies   a tracked LICENSE copy differs, byte for byte, from the root LICENSE
#   polyform-pin     the PolyForm text inside the root LICENSE no longer hashes to the pinned SHA-256
#   long-header      the retired long file header (its marker text) is still present in a tracked file
#   header-text      a source file's five-line header differs from the first five lines of header.txt
#   header-missing   a PowerShell file has no header at all
#   required-files   LICENSING.md, a licence template, a product LICENSE copy or the NOTICE title is missing
#
# WHY pinned: the PolyForm Noncommercial text is third-party text we must not alter. Only the additional
# terms after the `---` separator are ours to change, so only the part above it is hashed.
#
# File discovery is `git ls-files` (tracking is the bound, a recursive walk would cross target/ trees); the
# first 1000 bytes of each candidate are read through a FileStream so a large file costs nothing.
param([string]$Root = (Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PolyFormSha256 = '7779a554c40798f0f9c04960b82154d16dc0fa64349d401d24146e5c81f64093'
$script:LongHeaderMarker = 'ADDITIONAL TERMS (not part of PolyForm'
$script:TemplateBanner = '> **TEMPLATE - NOT AN OFFER.** This document grants nothing until it is signed by the licensor and a named counterparty. It has not yet been reviewed by legal counsel.'
$script:HeaderExtensions = '.cs', '.rs', '.proto', '.sh', '.yml', '.yaml', '.py', '.toml', '.ps1', '.psm1', '.psd1', '.html', '.js', '.css'
$script:PowerShellExtensions = '.ps1', '.psm1', '.psd1'
$script:ForeignHeaderAllowlist = @()
$script:RequiredLicenseCopies = 'agy-autotrain/LICENSE', 'clavity-classic/LICENSE', 'clavity-classic/agy-mcp-bridge/LICENSE', 'clavity-dotnet/LICENSE', 'commonmemory/LICENSE', 'review-relay/LICENSE'
$script:SelfPaths = 'scripts/check-licensing-consistent.ps1', 'scripts/tests/check-licensing-consistent.Tests.ps1'

function Get-PolyFormHash([string]$LicensePath) {
    # Lower-case hex SHA-256 of the PolyForm part of a LICENSE: from the heading line through the last non-blank line before
    # the `---` separator; CR stripped, joined with LF, no trailing newline, UTF-8 without BOM. $null if heading or separator is missing.
    $text = [IO.File]::ReadAllText($LicensePath, [Text.UTF8Encoding]::new($false))
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    $lines = @($text -split "`n" | ForEach-Object { $_.TrimEnd("`r") })
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].StartsWith('# PolyForm Noncommercial License 1.0.0', [StringComparison]::Ordinal)) { $start = $i; break }
    }
    if ($start -lt 0) { return $null }
    $sep = -1
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -ceq '---') { $sep = $i; break }
    }
    if ($sep -lt 0) { return $null }
    $end = $sep - 1
    while ($end -gt $start -and [string]::IsNullOrWhiteSpace($lines[$end])) { $end-- }
    $body = ($lines[$start..$end]) -join "`n"
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($body)) } finally { $sha.Dispose() }
    return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

function Read-HeaderWindow([byte[]]$First1000) {
    # The decoded first 1000 bytes split into lines (BOM dropped, CR removed) and the index of the first line containing
    # `Copyright (c)` (-1 when there is none). Get-HeaderLines is its only caller today; it is a separate function so a second reader of the window cannot drift from it.
    $text = [Text.UTF8Encoding]::new($false).GetString($First1000)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    $lines = @($text -split "`n" | ForEach-Object { $_.TrimEnd("`r") })
    $at = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Contains('Copyright (c)')) { $at = $i; break }
    }
    return [pscustomobject]@{ Lines = $lines; At = $at }
}

function Get-HeaderLines([byte[]]$First1000, [int]$Count = 5) {
    # The licence header as plain text: the first line containing `Copyright (c)` and the `$Count - 1` after it, each with comment
    # syntax (`//`, `#` or `*` after optional whitespace, plus at most one space) and trailing whitespace removed. A line with no
    # comment syntax (the body of a <# #> or <!-- --> block) is trimmed on both sides. $null when no line contains `Copyright (c)`.
    $w = Read-HeaderWindow $First1000
    if ($w.At -lt 0) { return $null }
    $last = [Math]::Min($w.At + $Count - 1, $w.Lines.Count - 1)
    $out = foreach ($l in $w.Lines[$w.At..$last]) {
        if ($l -match '^\s*(?://|#|\*) ?(?<rest>.*)$') { $Matches['rest'].TrimEnd() } else { $l.Trim() }
    }
    return [string[]]@($out)
}

function Get-TrackedPaths([string]$Root) {
    $raw = (& git -C $Root ls-files -z) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "git ls-files failed in $Root" }
    return @($raw -split "`0" | Where-Object { $_ })
}

function Test-IgnoredPath([string]$Path) {
    $segments = $Path -split '/'
    foreach ($s in $segments) {
        if ($s -in '.venv', 'node_modules', 'target', 'bin', 'obj', 'fixtures') { return $true }
    }
    if ($Path.StartsWith('.clavity/', [StringComparison]::Ordinal) -or $Path.StartsWith('.superpowers/', [StringComparison]::Ordinal)) { return $true }
    if ($Path.EndsWith('register-plugin.ps1', [StringComparison]::Ordinal)) { return $true }
    if ($Path -ceq 'docs/USER_GUIDE.html' -or $segments[-1] -ceq 'testResults.xml') { return $true }
    return $false
}

function Read-First1000([string]$FullPath) {
    $fs = [IO.File]::Open($FullPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $buf = [byte[]]::new(1000)
        $n = $fs.Read($buf, 0, 1000)
        if ($n -eq 0) { return [byte[]]@() }
        return [byte[]]$buf[0..($n - 1)]
    }
    finally { $fs.Dispose() }
}

function Get-LicensingProblems([string]$Root) {
    $problems = [System.Collections.Generic.List[string]]::new()
    $tracked = @(Get-TrackedPaths $Root)
    $trackedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$tracked, [StringComparer]::Ordinal)
    $full = { param($rel) Join-Path $Root $rel }

    # 1. license-copies
    $rootLicense = & $full 'LICENSE'
    if ($trackedSet.Contains('LICENSE') -and (Test-Path -LiteralPath $rootLicense -PathType Leaf)) {
        $ref = [IO.File]::ReadAllBytes($rootLicense)
        foreach ($p in $tracked) {
            if ($p -ceq 'LICENSE' -or $p.EndsWith('/LICENSE', [StringComparison]::Ordinal)) {
                $abs = & $full $p
                if (-not (Test-Path -LiteralPath $abs -PathType Leaf)) { continue }
                if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$ref, [byte[]][IO.File]::ReadAllBytes($abs))) {
                    $problems.Add("license-copies: $p differs from the root LICENSE")
                }
            }
        }
    }

    # 2. polyform-pin
    if (Test-Path -LiteralPath $rootLicense -PathType Leaf) {
        $h = Get-PolyFormHash $rootLicense
        if ($null -eq $h) { $problems.Add('polyform-pin: LICENSE has no PolyForm heading or no --- separator after it') }
        elseif ($h -cne $script:PolyFormSha256) { $problems.Add("polyform-pin: the PolyForm text in LICENSE hashes to $h, expected $($script:PolyFormSha256)") }
    }

    # 3. long-header (one git grep, not a per-file read)
    $hits = (& git -C $Root grep -l -z -F -e $script:LongHeaderMarker) -join "`n"
    if ($LASTEXITCODE -gt 1) { throw "git grep failed in $Root" }
    foreach ($p in @($hits -split "`0" | Where-Object { $_ })) {
        if ($p -ceq 'LICENSE' -or $p.EndsWith('/LICENSE', [StringComparison]::Ordinal)) { continue }
        if ($p -in $script:SelfPaths) { continue }
        $problems.Add("long-header: $p still carries the long header text; it must hold only the five-line header")
    }

    # 4 + 5. header-text and header-missing
    $headerFile = & $full 'header.txt'
    $expected = $null
    $count = 5
    if (Test-Path -LiteralPath $headerFile -PathType Leaf) {
        $exp = [Collections.Generic.List[string]]::new()
        foreach ($hl in (Get-Content -LiteralPath $headerFile)) { $exp.Add($hl.TrimEnd()) }
        while ($exp.Count -gt 0 -and $exp[$exp.Count - 1] -eq '') { $exp.RemoveAt($exp.Count - 1) }
        if ($exp.Count -eq 0) { $problems.Add('header-text: header.txt is empty, so no file header can be checked') }
        else { $expected = @($exp); $count = $exp.Count }
    }
    else { $problems.Add('header-text: header.txt is missing, so no file header can be checked') }
    foreach ($p in $tracked) {
        $ext = [IO.Path]::GetExtension($p).ToLowerInvariant()
        if ($ext -notin $script:HeaderExtensions) { continue }
        if (Test-IgnoredPath $p) { continue }
        if ($p -in $script:ForeignHeaderAllowlist) { continue }
        $abs = & $full $p
        if (-not (Test-Path -LiteralPath $abs -PathType Leaf)) { continue }
        $first = Read-First1000 $abs
        $lines = Get-HeaderLines $first $count
        if ($null -eq $lines) {
            $problems.Add("header-missing: $p has no Copyright (c) header in its first 1000 bytes")
            continue
        }
        if ($null -ne $expected -and ((@($lines) -join "`n") -cne ($expected -join "`n"))) {
            $problems.Add("header-text: $p has a header that differs from the $count lines of header.txt")
        }
    }

    # 6. required-files
    $required = @('LICENSING.md', 'licenses/COMMERCIAL-LICENSE.md', 'licenses/TRAINING-PARTNER-LICENSE.md', 'LICENSE') + @($script:RequiredLicenseCopies)
    foreach ($r in $required) {
        if (-not $trackedSet.Contains($r)) { $problems.Add("required-files: $r is not tracked") }
    }
    foreach ($t in 'licenses/COMMERCIAL-LICENSE.md', 'licenses/TRAINING-PARTNER-LICENSE.md') {
        $abs = & $full $t
        if (-not $trackedSet.Contains($t) -or -not (Test-Path -LiteralPath $abs -PathType Leaf)) { continue }
        $first = ([IO.File]::ReadAllText($abs, [Text.UTF8Encoding]::new($false)) -split "`n", 2)[0].TrimEnd("`r")
        if ($first.Length -gt 0 -and $first[0] -eq [char]0xFEFF) { $first = $first.Substring(1) }
        if ($first -cne $script:TemplateBanner) { $problems.Add("required-files: $t does not start with the template banner line") }
    }
    foreach ($lp in @('LICENSE') + @($script:RequiredLicenseCopies)) {
        $labs = & $full $lp
        if (-not $trackedSet.Contains($lp) -or -not (Test-Path -LiteralPath $labs -PathType Leaf)) { continue }
        $ltext = [IO.File]::ReadAllText($labs, [Text.UTF8Encoding]::new($false))
        foreach ($need in 'Copyright (c) 2026 Costas Kirgoussios', '## Commercial Evaluation Grant') {
            if (-not $ltext.Contains($need)) { $problems.Add("required-files: $lp does not contain '$need'") }
        }
    }
    $notice = & $full 'NOTICE'
    if (-not (Test-Path -LiteralPath $notice -PathType Leaf)) { $problems.Add('required-files: NOTICE is missing') }
    elseif (-not [IO.File]::ReadAllText($notice, [Text.UTF8Encoding]::new($false)).Contains('Authorized Clavity Training Partner')) {
        $problems.Add("required-files: NOTICE does not contain 'Authorized Clavity Training Partner'")
    }

    return [string[]]$problems.ToArray()
}

# main-guard: run only when invoked directly (NOT when dot-sourced by Pester - InvocationName is '.').
if ($MyInvocation.InvocationName -ne '.') {
    $found = @(Get-LicensingProblems $Root)
    if ($found.Count -eq 0) {
        Write-Host 'check-licensing-consistent: OK'
        exit 0
    }
    $found | ForEach-Object { Write-Host $_ }
    exit 1
}

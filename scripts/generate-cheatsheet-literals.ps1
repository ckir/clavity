#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Generate the two compiled-in cheatsheet literals from the canonical markdown source, making their
  divergence structurally impossible rather than merely detectable (ROADMAP 14e).

.DESCRIPTION
  THE THREE FILES ARE NOT BYTE-IDENTICAL TO EACH OTHER AND NEVER CAN BE - measured 3515 / 11544 / 7801
  bytes with three distinct hashes. One is markdown, one a Rust source carrying a single-line escaped
  literal, one a C# source carrying a concatenated multi-line literal. The lefthook comment calling them
  "pinned byte-identical to each other" is loose wording. THE REAL INVARIANT IS: the DECODED literal
  equals the markdown file's content, which is exactly what both existing pinning tests assert.

  This script only ever READS core.md, so it is correct under either resolution of the ownership
  question tracked as ROADMAP 14f. What it removes is the manual multi-file mirroring that made a
  mistaken edit dangerous - it narrows the hand-edited surface from three files to one.

  ESCAPING ORDER IS PART OF THE CONTRACT: backslash, then double-quote, then newline. Escaping the
  newline first makes the generator escape its own output (LF -> \n -> \\n), which compiles cleanly and
  fails the pinning test with an invisible diff.

  IT WRITES ONE LF-JOINED STRING AND NEVER A LINE ARRAY. Measured on pwsh 7: Set-Content, Out-File and
  WriteAllText all preserve LF for a SINGLE string, but the ARRAY form joins with the PLATFORM newline
  and emits CRLF - which would mismatch the LF index blob on every commit.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$CoreSource,
    [string]$RustTarget,
    [string]$CsTarget
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $CoreSource) { $CoreSource = Join-Path $repoRoot 'agy-autotrain/knowledge/driver-cheatsheet.core.md' }
if (-not $PSBoundParameters.ContainsKey('RustTarget')) { $RustTarget = Join-Path $repoRoot 'clavity-classic/src/driver_cheatsheet.rs' }
if (-not $PSBoundParameters.ContainsKey('CsTarget'))   { $CsTarget   = Join-Path $repoRoot 'clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs' }

function Fail([string]$msg) {
    Write-Host "generate-cheatsheet-literals: $msg" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $CoreSource)) { Fail "canonical source not found: $CoreSource" }
# AN EMPTY TARGET MEANS "SKIP THAT HALF", and it is a real requirement, not a convenience. The 14e
# pre-commit hook must generate for only the literals it will compare: a literal whose deletion is staged
# is gone from the worktree, so there is nothing to splice into, and demanding both targets would make
# the hook crash on exactly the case its test table says must PASS. Only a path that is BOTH non-empty
# AND missing is an error.
$doRust = -not [string]::IsNullOrWhiteSpace($RustTarget)
$doCs   = -not [string]::IsNullOrWhiteSpace($CsTarget)
if (-not $doRust -and -not $doCs) { Fail 'both targets were empty - nothing to generate' }
if ($doRust -and -not (Test-Path -LiteralPath $RustTarget)) { Fail "rust target not found: $RustTarget" }
if ($doCs   -and -not (Test-Path -LiteralPath $CsTarget))   { Fail "C# target not found: $CsTarget" }

# READ AS BYTES AND DECODE EXPLICITLY. Get-Content -Raw would go through the host encoding.
$coreText = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($CoreSource))
# STRIP A LEADING BOM EXPLICITLY - .Trim() does NOT remove it. Measured: [char]::IsWhiteSpace(0xFEFF) is
# FALSE in .NET, so a BOM survives Trim() and would be baked verbatim into the START of both literals.
# ReadAllBytes + UTF8.GetString is used deliberately here (Get-Content would hide the problem by
# stripping it), so this decode keeps the BOM as U+FEFF. core.md has NO BOM today (measured: it starts
# 44 72 69), which makes this latent rather than live - and latent is exactly when it is cheap to close.
# Left unhandled it would fail LOUDLY but confusingly: the pinning tests read the file with
# File.ReadAllText, which DOES strip the BOM, so only the literal would carry it, and U+FEFF is
# non-ASCII so the injected-context gate would red as well.
#
# ORDER IS LOAD-BEARING, and an earlier draft had it backwards. With the BOM stripped AFTER Trim(),
# a file beginning BOM + whitespace KEEPS that whitespace: Trim() halts at the BOM because U+FEFF is
# not whitespace, and TrimStart() then removes only the BOM. MEASURED on "<BOM>  Driver text" -
# Trim-then-strip yields "  Driver text" (13 chars); strip-then-Trim yields "Driver text" (11).
$coreText = $coreText.TrimStart([char]0xFEFF)
# NORMALISE, THEN ESCAPE. The pinning tests normalise only the FILE side and compare it to the literal
# AS-IS, so a generator that bakes \r\n into the literals reddens the exact gate it exists to protect.
$coreText = $coreText.Replace("`r`n", "`n").Trim()

if ($coreText.Length -eq 0) { Fail "canonical source is empty after trim: $CoreSource" }

# ORDER: backslash, then double-quote, then newline. Never reorder these three lines.
function ConvertTo-EscapedLiteral([string]$s) {
    $s = $s.Replace('\', '\\')
    $s = $s.Replace('"', '\"')
    $s = $s.Replace("`n", '\n')
    return $s
}

# ---------------------------------------------------------------------- Rust: ONE line, no splitting.
# THE GUARD WRAPS THE READ, NOT ONLY THE WRITE. Panel R7 measured that the first version of the
# empty-target skip guarded only the two WriteAllText calls while reading both targets unconditionally -
# and [IO.File]::ReadAllBytes('') THROWS (measured; control: a missing path throws too). So the skip
# crashed the generator, the hook read a non-zero exit, and it aborted BEFORE evaluating parity for the
# literal that was still present - violating the very test row (11) the skip was added to satisfy.
$rustLines = @()
if ($doRust) {
    $rustLiteral = ConvertTo-EscapedLiteral $coreText
    $rustLine    = 'pub const BASELINE_FLOOR: &str = "' + $rustLiteral + '";'

    $rustText  = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($RustTarget)).Replace("`r`n", "`n")
    $rustLines = $rustText -split "`n", 0
    $rustAnchor = @($rustLines | Where-Object { $_ -like 'pub const BASELINE_FLOOR: &str = *' })
    # A SPLICE ON A NON-UNIQUE ANCHOR DELETES THE SPAN BETWEEN MATCHES. Refuse rather than mangle.
    if ($rustAnchor.Count -ne 1) { Fail "expected exactly ONE 'pub const BASELINE_FLOOR' line in $RustTarget, found $($rustAnchor.Count)" }
    for ($i = 0; $i -lt $rustLines.Count; $i++) {
        if ($rustLines[$i] -like 'pub const BASELINE_FLOOR: &str = *') { $rustLines[$i] = $rustLine; break }
    }
}

# ------------------------------------------------------- C#: LINE-BOUNDARY logic, not a whole-string replace.
# The first segment carries no '+', every middle segment is '+ "...\n"', and the LAST segment has no
# trailing \n and ends with ';'. A single .Replace() over the whole text produces either a dangling '+'
# or a trailing \n the file side does not have.
$indent = '        '
$csSegments = @()
$csOut = @()
$coreLines = $coreText -split "`n", 0
for ($i = 0; $i -lt $coreLines.Count; $i++) {
    $esc = ConvertTo-EscapedLiteral $coreLines[$i]
    if ($i -eq 0) {
        $csSegments += ($indent + '"' + $esc + '\n"')
    }
    elseif ($i -eq $coreLines.Count - 1) {
        $csSegments += ($indent + '+ "' + $esc + '";')
    }
    else {
        $csSegments += ($indent + '+ "' + $esc + '\n"')
    }
}
# The FIRST segment must not carry a trailing \n when it is also the last.
if ($coreLines.Count -eq 1) { $csSegments = @($indent + '"' + (ConvertTo-EscapedLiteral $coreLines[0]) + '";') }

if ($doCs) {
$csText  = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($CsTarget)).Replace("`r`n", "`n")
$csLines = $csText -split "`n", 0
$csStart = -1
for ($i = 0; $i -lt $csLines.Count; $i++) {
    if ($csLines[$i] -match '^\s*public const string BaselineFloor\s*=\s*$') {
        if ($csStart -ge 0) { Fail "expected exactly ONE 'public const string BaselineFloor =' line in $CsTarget" }
        $csStart = $i
    }
}
if ($csStart -lt 0) { Fail "no 'public const string BaselineFloor =' anchor found in $CsTarget" }
# The literal ends at the first following line terminating in '";'.
$csEnd = -1
for ($i = $csStart + 1; $i -lt $csLines.Count; $i++) {
    if ($csLines[$i] -match '";\s*$') { $csEnd = $i; break }
}
if ($csEnd -lt 0) { Fail "could not find the end of the BaselineFloor literal in $CsTarget" }

$csOut += $csLines[0..$csStart]
$csOut += $csSegments
if ($csEnd + 1 -lt $csLines.Count) { $csOut += $csLines[($csEnd + 1)..($csLines.Count - 1)] }
}   # end if ($doCs)

# ONE LF-JOINED STRING, WRITTEN ONCE. Never an array - the array form joins with the platform newline.
# -WhatIf IS AN OWNER RULE, NOT A COURTESY (2026-08-01): every NEW .ps1 that changes state must
# implement it, and every mutation must be gated. These are the only two mutations in this script;
# reads and measurements above are deliberately NOT gated. `[IO.File]::WriteAllText` is a .NET call
# and has no -WhatIf passthrough of its own, so the gate is explicit here rather than delegated.
# The $doRust/$doCs guards are the SEPARATE empty-target skip and are not a substitute: they answer
# "is there a target?", ShouldProcess answers "may I write it?".
# ALL-OR-NOTHING ACROSS THE TWO TARGETS (capstone round 2, Cascade Analyst). These two writes used to
# run bare and sequentially, so a throw BETWEEN them left the pair HALF-APPLIED: rust regenerated, C#
# stale. MEASURED with the C# target read-only (which validates fine and throws only at the write, the
# exact window): exit 1, rust rewritten, C# untouched.
# WHY THAT IS WORSE THAN A CLEAN FAILURE: it is silent in the moment. The operator sees a failed
# command, clears the lock, re-runs, and everything looks fine - while the FIRST run already left the
# tree drifted. The damage surfaces later as a parity-gate red on an unrelated commit, reading as drift
# nobody introduced. The three pinned files are only meaningful as a SET.
# Restore-on-failure, not write-to-temp-then-rename: both payloads are already fully computed above, so
# the only thing that can fail here is the write itself, and restoring the exact prior bytes returns the
# tree to a state that was consistent by construction. HONEST LIMIT: this covers a THROWN failure, not a
# process kill between the two writes - a signal cannot be caught, and closing that would need a
# two-phase rename this script does not justify.
$rustBackup = if ($doRust -and (Test-Path -LiteralPath $RustTarget)) { [IO.File]::ReadAllBytes($RustTarget) } else { $null }
$csBackup   = if ($doCs   -and (Test-Path -LiteralPath $CsTarget))   { [IO.File]::ReadAllBytes($CsTarget)   } else { $null }
try {
    if ($doRust -and $PSCmdlet.ShouldProcess($RustTarget, 'regenerate BASELINE_FLOOR literal')) {
        [IO.File]::WriteAllText($RustTarget, ($rustLines -join "`n"), (New-Object Text.UTF8Encoding($false)))
    }
    if ($doCs -and $PSCmdlet.ShouldProcess($CsTarget, 'regenerate BaselineFloor literal')) {
        [IO.File]::WriteAllText($CsTarget,   ($csOut     -join "`n"), (New-Object Text.UTF8Encoding($false)))
    }
}
catch {
    # Each restore is guarded separately: the target that FAILED to write is usually still unwritable
    # (a read-only file, a lock), and letting its restore throw would mask the original error and skip
    # the sibling restore that CAN succeed - which is the one that actually matters.
    $restored = @()
    if ($null -ne $rustBackup) { try { [IO.File]::WriteAllBytes($RustTarget, $rustBackup); $restored += $RustTarget } catch { } }
    if ($null -ne $csBackup)   { try { [IO.File]::WriteAllBytes($CsTarget,   $csBackup);   $restored += $CsTarget   } catch { } }
    Fail ("write failed, and BOTH targets were rolled back to their prior bytes so the pinned set stays " +
          "consistent: $($_.Exception.Message)")
    if ($restored.Count -gt 0) { Write-Host ("  restored: " + ($restored -join ', ')) -ForegroundColor Yellow }
    exit 1
}

Write-Host "generate-cheatsheet-literals: OK - regenerated both literals from $CoreSource" -ForegroundColor Green
exit 0

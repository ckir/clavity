#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Fail if any tracked SKILL.md has frontmatter Claude Code would load but NOT ADVERTISE.
.DESCRIPTION
  Why this exists (2026-09-23): agy-capstone and agy-test-audit shipped with 517- and 750-char
  descriptions. Claude Code still LOADED them by explicit name, but dropped them from the session's
  available-skills list - so the model was never told the two completion gates existed, and a driver ran
  a capstone from memory with no ledger row, no marker, and no test-audit. No error, no warning, no log.
  `claude plugin details` showed it from Claude Code's side: ~30 always-on tokens (name only) for those
  two, 80-160 for every other skill.

  THE BOUND IS MEASURED, NOT DOCUMENTED. The published limit is 1024 for the whole frontmatter, and both
  files were inside it. Observed across every installed plugin: longest advertised description 461,
  shortest unadvertised 517. The cutoff lies in [462, 517] and was NOT pinned, and its mechanism (chars,
  bytes, tokens, name+description) is unknown - so this measures UTF-8 BYTES, which is never less than
  the character count, with margin below 461.

  Per SKILL.md it checks: frontmatter present; exactly one `name` and one `description`; `name` equals
  the skill's directory name; `description` is a single line (a folded `>`/`|` or continuation-line
  scalar is REJECTED - how a YAML parser joins it may not match what this counts); `description` is at
  most -MaxBytes UTF-8 bytes.

  SCOPE FAILS CLOSED. Targets are every TRACKED `*SKILL.md` (git ls-files), minus the explicit
  $Exclusions below - so a skill added anywhere is checked by default. Zero targets, a git failure, or an
  exclusion that matches no tracked file is exit 2 (cannot answer), never a vacuous pass.
.PARAMETER Root
  Repository root. Defaults to this script's parent directory.
.PARAMETER MaxBytes
  The description budget. THE single source of truth; a raise is a deliberate committed edit.
.OUTPUTS
  Exit 0 all good; 1 a skill violates the contract; 2 cannot answer (discovery failed).
#>
[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [int]$MaxBytes = 440
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Repo-relative, forward slashes, exactly as git ls-files prints them. Each needs a reason.
$Exclusions = [ordered]@{
    # A reference doc for the agy-side MCP bridge, not a Claude Code skill: it has no frontmatter.
    'clavity-classic/agy-mcp-bridge/SKILL.md' = 'agy-side bridge reference doc, never loaded by Claude Code'
}

function Stop-CannotAnswer([string]$msg) {
    Write-Host "check-skill-frontmatter: CANNOT ANSWER: $msg" -ForegroundColor Red
    exit 2
}

$tracked = @(& git -C $Root ls-files -- '*SKILL.md' 2>$null)
if ($LASTEXITCODE -ne 0) { Stop-CannotAnswer "git ls-files failed in '$Root' (exit $LASTEXITCODE)" }

foreach ($ex in $Exclusions.Keys) {
    if ($tracked -notcontains $ex) {
        Stop-CannotAnswer "exclusion '$ex' matches no tracked SKILL.md - remove it from `$Exclusions, or the list rots"
    }
}

$targets = @($tracked | Where-Object { -not $Exclusions.Contains($_) })
if ($targets.Count -eq 0) {
    Stop-CannotAnswer "found 0 SKILL.md files to check - discovery is broken, not the repo clean"
}

$problems = [System.Collections.Generic.List[string]]::new()

foreach ($rel in $targets) {
    $path = Join-Path $Root $rel
    $text = [System.IO.File]::ReadAllText($path) -replace "`r`n", "`n"
    $m = [regex]::Match($text, '\A---\n(?<fm>.*?)\n---(\n|\z)', 'Singleline')
    if (-not $m.Success) { $problems.Add("${rel}: no YAML frontmatter (--- ... ---) at the top of the file"); continue }

    $lines = $m.Groups['fm'].Value -split "`n"
    $values = @{}
    $counts = @{ name = 0; description = 0 }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $km = [regex]::Match($lines[$i], '^(?<k>name|description):[ \t]*(?<v>.*)$')
        if (-not $km.Success) { continue }
        $k = $km.Groups['k'].Value
        $counts[$k]++
        $values[$k] = $km.Groups['v'].Value.Trim()
        # An indented line straight after the key makes it a multi-line (plain or block) scalar.
        if ($i + 1 -lt $lines.Count -and $lines[$i + 1] -match '^[ \t]+\S') {
            $problems.Add("${rel}: '$k' continues onto the next line - keep it on ONE line so its length is unambiguous")
        }
    }

    foreach ($k in 'name', 'description') {
        if ($counts[$k] -ne 1) { $problems.Add("${rel}: expected exactly one '${k}:' in frontmatter, found $($counts[$k])") }
    }
    if ($counts.name -ne 1 -or $counts.description -ne 1) { continue }

    $dir = Split-Path -Leaf (Split-Path -Parent $rel)
    if ($values.name -cne $dir) {
        $problems.Add("${rel}: name '$($values.name)' does not match its directory '$dir'")
    }

    $desc = $values.description
    if ($desc -eq '' -or $desc -match '^[>|]') {
        $problems.Add("${rel}: description is empty or a block scalar ('>' / '|') - write it on the description: line itself")
        continue
    }

    $bytes = [System.Text.Encoding]::UTF8.GetByteCount($desc)
    if ($bytes -gt $MaxBytes) {
        $problems.Add(@"
${rel}: SKILL.md description too long: $bytes bytes (limit $MaxBytes).
  Descriptions above ~461 chars are silently dropped by Claude Code - the skill will not
  appear in the session's skill list, with no error. Move detail into the body; keep
  the "when to use" trigger conditions in the description.
"@)
    }
}

if ($problems.Count -gt 0) {
    foreach ($p in $problems) { Write-Host "check-skill-frontmatter: FAIL: $p" -ForegroundColor Red }
    exit 1
}

Write-Host "check-skill-frontmatter: OK - $($targets.Count) SKILL.md checked ($($Exclusions.Count) excluded), descriptions <= ${MaxBytes}B" -ForegroundColor Green
exit 0

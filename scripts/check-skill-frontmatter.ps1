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

  Per SKILL.md it checks: the file exists in the working tree; frontmatter present; exactly one `name`
  and one `description`; `name` equals the skill's directory name (one pair of surrounding YAML quotes is
  stripped first, as a YAML reader would); `description` is literal text on a single line (a quote it
  opens must close on that line) - a folded
  `>`/`|` or continuation-line scalar, and a YAML alias/anchor/tag (`*` / `&` / `!`), are REJECTED,
  because a YAML reader would expand them into text this script never counted; `description` is at most
  -MaxBytes UTF-8 bytes.

  SCOPE FAILS CLOSED. Targets are every TRACKED file named SKILL.md in ANY case (git ls-files), minus the explicit
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

# UTF-8 on the way IN, NUL-separated, quotepath off. PowerShell decodes native stdout with
# [Console]::OutputEncoding (ibm437 on a stock Windows console), and git C-quotes a non-ASCII path by
# default - either one alone turns `cafe-with-accent/SKILL.md` into a path that does not exist (MEASURED:
# the read threw). `:(icase)` because a case-insensitive filesystem loads a `skill.md` too; the leaf
# filter then keeps only files actually NAMED SKILL.md, since the pattern's `*` also matches `xskill.md`.
$prevEncoding = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $lsOut = (& git -C $Root -c core.quotepath=off ls-files -z -- ':(icase)*skill.md' 2>$null) -join ''
    $gitExit = $LASTEXITCODE
} finally {
    [Console]::OutputEncoding = $prevEncoding
}
if ($gitExit -ne 0) { Stop-CannotAnswer "git ls-files failed in '$Root' (exit $gitExit)" }
$tracked = @($lsOut -split "`0" | Where-Object { $_ -ne '' -and (Split-Path -Leaf $_) -ieq 'SKILL.md' })

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
    # Tracked but deleted and not yet staged: the shipped commit may still carry it, so FAIL rather than
    # skip it (a skip would pass content nobody checked) or crash on the read.
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $problems.Add("${rel}: tracked but missing from the working tree - commit the deletion or restore the file, so what is checked is what ships")
        continue
    }
    $text = [System.IO.File]::ReadAllText($path) -replace "`r`n", "`n"
    $m = [regex]::Match($text, '\A---\n(?<fm>.*?)\n---(\n|\z)', 'Singleline')
    if (-not $m.Success) { $problems.Add("${rel}: no YAML frontmatter (--- ... ---) at the top of the file"); continue }

    $lines = $m.Groups['fm'].Value -split "`n"
    $values = @{}
    $rawValues = @{}
    $counts = @{ name = 0; description = 0 }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $km = [regex]::Match($lines[$i], '^(?<k>name|description):[ \t]*(?<v>.*)$')
        if (-not $km.Success) { continue }
        $k = $km.Groups['k'].Value
        $counts[$k]++
        $v = $km.Groups['v'].Value.Trim()
        $rawValues[$k] = $v
        # One pair of surrounding YAML quotes is not part of the value (MEASURED: `name: "a"` false-redded
        # against directory `a`). Escapes inside the quotes are not interpreted - a deliberate limit.
        if ($v.Length -ge 2 -and (($v[0] -eq '"' -and $v[-1] -eq '"') -or ($v[0] -eq "'" -and $v[-1] -eq "'"))) {
            $v = $v.Substring(1, $v.Length - 2)
        }
        $values[$k] = $v
        # An indented line straight after the key makes it a multi-line (plain or block) scalar.
        if ($i + 1 -lt $lines.Count -and $lines[$i + 1] -match '^[ \t]+\S') {
            $problems.Add("${rel}: '$k' continues onto the next line - keep it on ONE line so its length is unambiguous")
        }
    }

    foreach ($k in 'name', 'description') {
        if ($counts[$k] -ne 1) { $problems.Add("${rel}: expected exactly one '${k}:' in frontmatter, found $($counts[$k])") }
    }
    if ($counts.name -ne 1 -or $counts.description -ne 1) { continue }

    $parent = Split-Path -Parent $rel
    if (-not $parent) {
        $problems.Add("${rel}: sits at the repository root - a skill must live in its own <name>/ directory")
    } elseif ($values.name -cne ($dir = Split-Path -Leaf $parent)) {
        $problems.Add("${rel}: name '$($values.name)' does not match its directory '$dir'")
    }

    $desc = $values.description
    # Tested on the RAW value: inside quotes, a leading '*' is literal text, not an alias. An alias
    # `*long` is 5 bytes here and whatever `&long` anchored once a YAML reader expands it (MEASURED:
    # exit 0 on a 600-byte expansion before this check existed).
    if ($desc -eq '' -or $rawValues.description -match '^[>|*&!]') {
        $problems.Add("${rel}: description is empty, a block scalar ('>' / '|'), or a YAML alias/anchor/tag ('*' / '&' / '!') - write the literal text on the description: line itself")
        continue
    }
    # A quote opened and not closed on the SAME line is a multi-line quoted scalar: YAML may continue it
    # onto an UNINDENTED line (which the continuation check above cannot see), and a `---` line inside it
    # ends the frontmatter match early, so the text counted here is a prefix of what a YAML reader sees
    # (MEASURED: exit 0 on both shapes with a 600-byte tail, capstone round 2).
    $rd = $rawValues.description
    if ($rd -match '^["'']' -and -not ($rd.Length -ge 2 -and $rd[-1] -eq $rd[0])) {
        $problems.Add("${rel}: description opens a quote it does not close on the same line - keep the whole quoted value on ONE line")
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

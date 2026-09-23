#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Fail if any tracked SKILL.md has frontmatter that is not valid YAML, or lacks a string name/description.
.DESCRIPTION
  Why this exists (2026-09-23/24): agy-capstone and agy-test-audit were LOADED by explicit name but never
  ADVERTISED in the session's available-skills list - so the model was never told the two completion
  gates existed. No error, no warning, no log.

  THE CAUSE IS INVALID YAML, NOT LENGTH. Both descriptions held `: ` inside an UNQUOTED plain scalar.
  MEASURED with `claude plugin validate` (a control - a list-valued description - reports ERR there):
  Claude Code's own parser forgives that with LF line endings but FAILS it with CRLF, which is how the
  plugin is checked out on Windows, and then "loads with empty metadata (all frontmatter fields silently
  dropped)". A first diagnosis blamed description LENGTH (a [462, 517] "cutoff"); quoting the original
  517-char text made it advertised, so length was a coincidence. This script's first version enforced
  that false bound, and six review rounds hardened a hand-rolled YAML reader around it - which still
  passed the real defect. So the frontmatter is now handed to a REAL parser.

  THE PARSER IS yq (mikefarah, v4 - strict YAML 1.2). It is STRICTER than Claude Code, deliberately: it
  rejects an unquoted `: ` under BOTH line endings, and a value starting with a reserved indicator (`@`,
  `` ` ``, `%`) that Claude Code happens to accept. Failing on YAML that another reader would forgive is
  the safe direction. It is NOT stricter everywhere: yq accepts a list or number as `description`, which
  Claude Code rejects ("must be a string"), so the parsed value's TYPE is checked here too.

  The frontmatter block is cut out here and piped to yq on STDIN. `yq --front-matter` was measured
  unsuitable: it reads a file with NO frontmatter as a YAML document (exit 0), and on Windows it leaves a
  temp file behind on every call ("Failed to remove temp file").

  Per SKILL.md it checks: the file exists in the working tree; it starts with a `---` ... `---` block;
  that block is valid YAML and a mapping; `name` and `description` are non-empty strings; `name` equals
  the skill's directory name. It does NOT check length - there is no measured bound to check.

  SCOPE FAILS CLOSED. Targets are every TRACKED file named SKILL.md in ANY case (git ls-files), minus the
  explicit $Exclusions below - so a skill added anywhere is checked by default. Zero targets, a git
  failure, an exclusion that matches no tracked file, or yq missing / not mikefarah v4 is exit 2 (cannot
  answer), never a vacuous pass.
.PARAMETER Root
  Repository root. Defaults to this script's parent directory.
.OUTPUTS
  Exit 0 all good; 1 a skill violates the contract; 2 cannot answer.
#>
[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
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

# yq is the oracle, so its absence is "cannot answer", never a pass. The python-yq wrapper shares the
# command name and a different CLI, so the VERSION string is checked, not just the presence.
if (-not (Get-Command yq -ErrorAction SilentlyContinue)) {
    Stop-CannotAnswer "yq is not on PATH - install mikefarah yq v4 (https://github.com/mikefarah/yq)"
}
$yqVersion = (& yq --version 2>&1 | Out-String).Trim()
if ($yqVersion -notmatch 'mikefarah' -or $yqVersion -notmatch 'version v4\.') {
    Stop-CannotAnswer "yq on PATH is not mikefarah yq v4 (got: '$yqVersion')"
}

# UTF-8 BOTH WAYS for every native call below. PowerShell decodes native stdout with
# [Console]::OutputEncoding (ibm437 on a stock Windows console) and encodes piped stdin with
# $OutputEncoding - either one left alone mangles non-ASCII paths and text (MEASURED: a non-ASCII skill
# directory crashed the read). [Console]::OutputEncoding is PROCESS-wide, so it is restored in the
# finally for an in-process caller; $OutputEncoding assigned here is a SCRIPT-scope variable and never
# leaks, so it needs no restore - but it IS needed: without it the caller's value is inherited.
$prevConsoleEncoding = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)

    # NUL-separated with quotepath off: git C-quotes a non-ASCII path by default. `:(icase)` because a
    # case-insensitive filesystem loads a `skill.md` too; the leaf filter then keeps only files actually
    # NAMED SKILL.md, since the pattern's `*` also matches `xskill.md`.
    $lsOut = (& git -C $Root -c core.quotepath=off ls-files -z -- ':(icase)*skill.md' 2>$null) -join ''
    if ($LASTEXITCODE -ne 0) { Stop-CannotAnswer "git ls-files failed in '$Root' (exit $LASTEXITCODE)" }
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
        # Tracked but deleted and not yet staged: the shipped commit may still carry it, so FAIL rather
        # than skip it (a skip would pass content nobody checked) or crash on the read.
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $problems.Add("${rel}: tracked but missing from the working tree - commit the deletion or restore the file, so what is checked is what ships")
            continue
        }
        # ReadAllText drops a UTF-8 BOM. CRLF is normalised because yq rejects an unquoted `: ` under
        # either ending - the CRLF-only failure is Claude Code's, and this check is stricter than it.
        $text = [System.IO.File]::ReadAllText($path) -replace "`r`n", "`n"
        $m = [regex]::Match($text, '\A---\n(?<fm>.*?)\n---(\n|\z)', 'Singleline')
        if (-not $m.Success) { $problems.Add("${rel}: no YAML frontmatter (--- ... ---) at the top of the file"); continue }

        # stdout and stderr are SPLIT, never parsed together: yq prints WARNINGS to stderr on a SUCCESSFUL
        # parse (MEASURED: a YAML merge key `<<:` warns about --yaml-fix-merge-anchor-to-spec), and one
        # merged into the JSON made ConvertFrom-Json throw and kill the whole run (capstone round 1).
        $yqAll = @($m.Groups['fm'].Value | & yq -o=json -I=0 '.' 2>&1)
        $yqExit = $LASTEXITCODE
        $yqOut = ($yqAll | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | Out-String).Trim()
        $yqErr = ($yqAll | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | Out-String).Trim()
        if ($yqExit -ne 0) {
            $problems.Add("${rel}: frontmatter is not valid YAML ($yqErr) - Claude Code then loads the skill with EMPTY metadata and never advertises it. Quote any value containing ': '.")
            continue
        }
        $meta = $yqOut | ConvertFrom-Json
        if ($meta -isnot [System.Management.Automation.PSCustomObject]) {
            $problems.Add("${rel}: frontmatter is valid YAML but not a mapping of keys (got: $yqOut)")
            continue
        }

        foreach ($k in 'name', 'description') {
            $v = $meta.PSObject.Properties[$k]
            if (-not $v -or $v.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($v.Value)) {
                $got = if ($v) { ($v.Value | ConvertTo-Json -Compress) } else { 'missing' }
                $problems.Add("${rel}: '$k' must be a non-empty string (got: $got)")
            }
        }
        if ($meta.PSObject.Properties['name'] -and $meta.name -is [string]) {
            $parent = Split-Path -Parent $rel
            if (-not $parent) {
                $problems.Add("${rel}: sits at the repository root - a skill must live in its own <name>/ directory")
            } elseif ($meta.name -cne ($dir = Split-Path -Leaf $parent)) {
                $problems.Add("${rel}: name '$($meta.name)' does not match its directory '$dir'")
            }
        }
    }
} finally {
    [Console]::OutputEncoding = $prevConsoleEncoding
}

if ($problems.Count -gt 0) {
    foreach ($p in $problems) { Write-Host "check-skill-frontmatter: FAIL: $p" -ForegroundColor Red }
    exit 1
}

Write-Host "check-skill-frontmatter: OK - $($targets.Count) SKILL.md checked ($($Exclusions.Count) excluded), all frontmatter valid YAML" -ForegroundColor Green
exit 0

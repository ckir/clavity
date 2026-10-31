#!/usr/bin/env pwsh
<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

# Enforces docs/tracker-format.md over every tracked work item. EXIT: 0 clean · 1 at least one violation ·
# 2 the RUN could not start (not a git repository / git missing). -List prints the open-partition items
# (exit 0) - the end-of-sweep Done check runs it.
# Trackers: clavity-dotnet/ROADMAP.md, review-relay/ROADMAP.md, agy-autotrain/ROADMAP.md (heading entries),
# docs/backlog/*.md (stubs), agy-autotrain/docs/fix-the-tool-backlog/*.md (frontmatter).
[CmdletBinding()]
param([string]$RepoRoot, [switch]$List)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Host 'check-tracker-status: git is not on PATH - nothing was checked' -ForegroundColor Yellow; exit 2 }
& git -C $RepoRoot rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "check-tracker-status: '$RepoRoot' is not a git repository - nothing was checked" -ForegroundColor Yellow; exit 2 }

$OpenTokens   = @('OPEN', 'SCHEDULED', 'IMPLEMENTED')
$ClosedTokens = @('SHIPPED', 'CLOSED-BY-RULING', 'KILLED')
$StatusRe  = [regex]'^\*\*Status:\*\* (?<tok>\S+) (?<date>\d{4}-\d{2}-\d{2}) - (?<text>\S.*)$'
$ShaRe     = [regex]'`(?<sha>[0-9a-fA-F]{7,40})`'
$ReleasedRe = [regex]'^\*\*Released:\*\* clavity-v\d+$'
# A status MARKER in a heading. Words alone are allowed (a title may say "the SHIPPED flag"); glyphs and strike-through are not.
$HeadingMarkRe = [regex]'(✅|▶|🚫|🔴|⚠|~~|\s[—·-]\s*(SHIPPED|FIXED|CLOSED|KILLED|PROMOTED|SCHEDULED|OPEN)\b)'
$isShallow = ((& git -C $RepoRoot rev-parse --is-shallow-repository 2>$null) -join '').Trim() -eq 'true'
$problems = [System.Collections.Generic.List[string]]::new()
$entries  = [System.Collections.Generic.List[object]]::new()

function Read-Lines([string]$Rel, [switch]$Required) {
    $p = Join-Path $RepoRoot ($Rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        # Only clavity-dotnet/ROADMAP.md is mandatory; the other trackers are checked when present (a deleted MANDATORY one must not read green).
        if ($Required) { $script:problems.Add("MISSING-TRACKER  $Rel is not a readable file - nothing in it was checked") }
        return $null
    }
    return ([IO.File]::ReadAllText($p) -split "`r?`n")
}
function Test-Sha([string]$Sha, [string]$Where) {
    if ($script:isShallow) { return }
    & git -C $RepoRoot cat-file -e "$Sha^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) { $script:problems.Add("PHANTOM  $Where  ``$Sha`` does not exist in this repository") }
}
function Test-Entry {
    # $Tok/$Date/$Text parsed from the status line; $Block = the entry's lines (for Reopen-if); $NonGoals = ROADMAP bullets.
    param([string]$Tracker, [string]$Id, [string]$Where, $M, [string[]]$Block, [string[]]$NextLines, [string[]]$NonGoals, [string]$Kind, [string]$Title = '')
    $tok = $M.Groups['tok'].Value
    if (($OpenTokens + $ClosedTokens) -notcontains $tok) { $problems.Add("BAD-TOKEN  $Where  '$tok' is not one of: $(($OpenTokens + $ClosedTokens) -join ', ')"); return }
    $d = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($M.Groups['date'].Value, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) { $problems.Add("BAD-DATE  $Where  '$($M.Groups['date'].Value)' is not a calendar date"); return }
    $text = $M.Groups['text'].Value
    switch ($tok) {
        'SHIPPED' {
            $shas = @($ShaRe.Matches($text))
            if ($shas.Count -eq 0) { $problems.Add("NO-SHA  $Where  SHIPPED needs a backticked commit sha on the status line") }
            foreach ($s in $shas) { Test-Sha $s.Groups['sha'].Value $Where }
        }
        'KILLED' { if ($text.Trim().Length -lt 12) { $problems.Add("NO-REASON  $Where  KILLED needs a reason of at least 12 characters") } }
        'CLOSED-BY-RULING' {
            if ($Kind -eq 'roadmap') {
                $hit = @($NonGoals | Where-Object { $_ -match ('^- \*\*' + [regex]::Escape($Id) + '(?![0-9A-Za-z])') })
                if ($hit.Count -eq 0) { $problems.Add("NO-NONGOALS  $Where  CLOSED-BY-RULING needs a '- **$Id ...' bullet under 'Non-goals / accepted limitations' in clavity-dotnet/ROADMAP.md") }
            } elseif (-not (@($Block) -match '^\*\*Reopen if:\*\* \S')) { $problems.Add("NO-REOPEN  $Where  CLOSED-BY-RULING needs a '**Reopen if:** ...' line in the entry") }
        }
    }
    $rel = @($NextLines | Where-Object { $_ -match '^\*\*Released:\*\*' })
    foreach ($r in $rel) {
        if (-not $ReleasedRe.IsMatch($r)) { $problems.Add("BAD-RELEASED  $Where  '$r' is not '**Released:** clavity-vN'") }
        elseif ($tok -ne 'SHIPPED') { $problems.Add("RELEASED-ON-UNSHIPPED  $Where  only a SHIPPED entry may carry a Released line") }
    }
    $script:entries.Add([pscustomobject]@{ Tracker = $Tracker; Id = $Id; Token = $tok; Open = ($OpenTokens -contains $tok); Where = $Where; Title = $Title; Text = $text })
}

function Test-HeadingTracker {
    param([string]$Rel, [string]$Tracker, [regex]$HeadingRe, [scriptblock]$IdOf, [string[]]$NonGoals, [string]$Kind, [regex]$LooseRe, [switch]$Required)
    $lines = Read-Lines $Rel -Required:$Required; if ($null -eq $lines) { return }
    $fence = $false; $idx = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*```') { $fence = -not $fence; continue }
        if (-not $fence -and $HeadingRe.IsMatch($lines[$i])) { $idx += $i }
        elseif (-not $fence -and $LooseRe -and $LooseRe.IsMatch($lines[$i])) { $problems.Add("MALFORMED-HEADING  $Rel`:$($i + 1)  looks like an entry heading but does not match the strict shape, so the gate would skip it: '$($lines[$i])'") }
        elseif (-not $fence -and $lines[$i] -match '^## Non-goals') { $idx += $i }   # a section boundary, not an entry
    }
    foreach ($k in 0..([Math]::Max($idx.Count - 1, 0))) {
        if ($idx.Count -eq 0) { break }
        $i = $idx[$k]; if (-not $HeadingRe.IsMatch($lines[$i])) { continue }
        $end = if ($k + 1 -lt $idx.Count) { $idx[$k + 1] } else { $lines.Count }
        $id = & $IdOf $lines[$i]; $where = "$Rel`:$($i + 1) $id"
        if ($HeadingMarkRe.IsMatch($lines[$i])) { $problems.Add("HEADING-STATUS  $where  the heading must be the title only (status markers belong on the status line)") }
        $j = $i + 1; while ($j -lt $end -and $lines[$j].Trim() -eq '') { $j++ }
        $m = if ($j -lt $end) { $StatusRe.Match($lines[$j]) } else { $null }
        if ($null -eq $m -or -not $m.Success) { $problems.Add("NO-STATUS  $where  the next non-blank line after the heading must be '**Status:** <TOKEN> <YYYY-MM-DD> - <text>'"); continue }
        $next = if ($j + 1 -lt $end) { @($lines[($j + 1)..([Math]::Min($j + 2, $end - 1))] | Where-Object { $_ }) } else { @() }   # an empty range would run BACKWARDS into the next heading
        Test-Entry -Tracker $Tracker -Id $id -Where $where -M $m -Block $lines[$i..($end - 1)] -NextLines $next -NonGoals $NonGoals -Kind $Kind -Title ($lines[$i] -replace '^#+\s*', '')
    }
}

# --- ROADMAP-style trackers --------------------------------------------------------------------------
$rmLines = Read-Lines 'clavity-dotnet/ROADMAP.md'   # the mandatory-tracker problem is raised once, by Test-HeadingTracker -Required below
$nonGoals = @()
if ($null -ne $rmLines) {
    $ng = [array]::FindIndex($rmLines, [Predicate[string]] { param($l) $l -like '## Non-goals*' })
    if ($ng -ge 0) { $nonGoals = @($rmLines[$ng..($rmLines.Count - 1)] | Where-Object { $_ -like '- **`*' -or $_ -like '- **§*' -or $_ -like '- **item *' -or $_ -like '- **AT-*' -or $_ -like '- **D*' -or $_ -like '- **R*' }) }
}
# LooseRe is a TRIPWIRE, not a parser: it flags a heading that opens like an entry (the section sign, a number WITH its dot but not a dotted outline number like 1.1, [DR]<n>, AT-<n>; tolerating spaces after the hashes and any tildes) but fails the strict shape.
# It deliberately does NOT forgive a typo inside the sigil itself (### D-12, ### 12 Title): that cannot be told from ordinary prose such as '### 2026 Goals', so widening further trades a missed typo for a red build
# on valid docs (AGY-CAPSTONE branch T rounds 4-6). Accepted residuals: an id glued to letters (### D1Title - indistinguishable from '### R2D2 Architecture'), an entry whose sigil is itself misspelt or space-split (D 12, AT 3) is skipped, and so is one at the wrong heading level (## §1).
Test-HeadingTracker -Rel 'clavity-dotnet/ROADMAP.md' -Tracker 'dotnet-roadmap' -Kind 'roadmap' -NonGoals $nonGoals -Required `
    -HeadingRe ([regex]'^### (?:~~)?(?:§\d+ |\d+\. )') -LooseRe ([regex]'^###\s*~*\s*(?:§|\d+\.(?!\d))') `
    -IdOf { param($l) if ($l -match '^### (?:~~)?(§\d+) ') { $Matches[1] } elseif ($l -match '^### (?:~~)?(\d+)\. ') { "item $($Matches[1])" } }
Test-HeadingTracker -Rel 'review-relay/ROADMAP.md' -Tracker 'review-relay' -Kind 'file' -NonGoals $nonGoals `
    -HeadingRe ([regex]'^### [DR]\d+ ') -LooseRe ([regex]'^###\s*[DR]\d+(?:\s*[-:.]|\s*$)') -IdOf { param($l) if ($l -match '^### ([DR]\d+) ') { $Matches[1] } }
Test-HeadingTracker -Rel 'agy-autotrain/ROADMAP.md' -Tracker 'agy-autotrain-roadmap' -Kind 'file' -NonGoals $nonGoals `
    -HeadingRe ([regex]'^## AT-\d+ ') -LooseRe ([regex]'^##\s*AT-\d') -IdOf { param($l) if ($l -match '^## (AT-\d+) ') { $Matches[1] } }

# --- backlog stubs -----------------------------------------------------------------------------------
$stubDir = Join-Path $RepoRoot 'docs' 'backlog'
if (Test-Path -LiteralPath $stubDir -PathType Container) {
    foreach ($f in Get-ChildItem -LiteralPath $stubDir -Filter '*.md' -File | Sort-Object Name) {
        $lines = [IO.File]::ReadAllText($f.FullName) -split "`r?`n"; $where = "docs/backlog/$($f.Name)"
        $t = 0; while ($t -lt $lines.Count -and $lines[$t].Trim() -eq '') { $t++ }
        if ($t -ge $lines.Count -or $lines[$t] -notmatch '^# ') { $problems.Add("NO-TITLE  $where  line 1 must be '# <title>'"); continue }
        $j = $t + 1; while ($j -lt $lines.Count -and $lines[$j].Trim() -eq '') { $j++ }
        $m = if ($j -lt $lines.Count) { $StatusRe.Match($lines[$j]) } else { $null }
        if ($null -eq $m -or -not $m.Success) { $problems.Add("NO-STATUS  $where  the next non-blank line after the title must be '**Status:** <TOKEN> <YYYY-MM-DD> - <text>'"); continue }
        $next = if ($j + 1 -lt $lines.Count) { @($lines[($j + 1)..([Math]::Min($j + 2, $lines.Count - 1))] | Where-Object { $_ }) } else { @() }
        Test-Entry -Tracker 'backlog-stub' -Id $f.Name -Where $where -M $m -Block $lines -NextLines $next -NonGoals @() -Kind 'file' -Title ($lines[$t] -replace '^#+\s*', '')
    }
}

# --- fix-the-tool frontmatter --------------------------------------------------------------------------
$ftDir = Join-Path $RepoRoot 'agy-autotrain' 'docs' 'fix-the-tool-backlog'
if (Test-Path -LiteralPath $ftDir -PathType Container) {
    foreach ($f in Get-ChildItem -LiteralPath $ftDir -Filter '*.md' -File | Where-Object { $_.Name -notin @('README.md', '_template.md', 'DRY-RUN-2026-07-11.md') } | Sort-Object Name) {
        $lines = [IO.File]::ReadAllText($f.FullName) -split "`r?`n"; $where = "agy-autotrain/docs/fix-the-tool-backlog/$($f.Name)"
        if ($lines.Count -lt 3 -or $lines[0] -ne '---') { $problems.Add("NO-STATUS  $where  no frontmatter"); continue }
        $close = [array]::IndexOf($lines, '---', 1)
        if ($close -lt 0) { $problems.Add("NO-STATUS  $where  unterminated frontmatter"); continue }
        $fm = @{}; foreach ($l in $lines[1..($close - 1)]) { if ($l -match '^([A-Za-z-]+):\s*(.*?)\s*(#.*)?$') { $fm[$Matches[1]] = $Matches[2] } }
        if (-not $fm.ContainsKey('status')) { $problems.Add("NO-STATUS  $where  frontmatter has no status: key"); continue }
        $tok = $fm['status']
        if (($OpenTokens + $ClosedTokens) -notcontains $tok) { $problems.Add("BAD-TOKEN  $where  '$tok' is not one of: $(($OpenTokens + $ClosedTokens) -join ', ')"); continue }
        switch ($tok) {
            'SHIPPED' {
                $shas = @(([regex]'[0-9a-fA-F]{7,40}').Matches($(if ($fm.ContainsKey('fixed-by')) { $fm['fixed-by'] } else { '' })))
                if ($shas.Count -eq 0) { $problems.Add("NO-SHA  $where  SHIPPED needs fixed-by: <sha, ...>") }
                foreach ($s in $shas) { Test-Sha $s.Value $where }
                if (-not $fm.ContainsKey('fixed-on')) { $problems.Add("NO-DATE  $where  SHIPPED needs fixed-on: <YYYY-MM-DD>") }
            }
            'KILLED' { if (-not $fm.ContainsKey('reason') -or $fm['reason'].Length -lt 12) { $problems.Add("NO-REASON  $where  KILLED needs reason: of at least 12 characters") } }
            'CLOSED-BY-RULING' { if (-not (@($lines) -match '^\*\*Reopen if:\*\* \S')) { $problems.Add("NO-REOPEN  $where  CLOSED-BY-RULING needs a '**Reopen if:** ...' line") } }
        }
        if ($fm.ContainsKey('released-in') -and $tok -ne 'SHIPPED') { $problems.Add("RELEASED-ON-UNSHIPPED  $where  released-in: is only valid on SHIPPED") }
        $entries.Add([pscustomobject]@{ Tracker = 'fix-the-tool'; Id = $f.Name; Token = $tok; Open = ($OpenTokens -contains $tok); Where = $where; Title = (($lines | Where-Object { $_ -match '^slug:' } | Select-Object -First 1) -replace '^slug:\s*', ''); Text = '' })
    }
}

if ($isShallow) { $problems.Add('SHALLOW  this repository has no history, so cited shas could not be verified - deepen the checkout (git fetch --unshallow)') }

if ($List) {
    foreach ($e in @($entries | Where-Object Open | Sort-Object Tracker, Id)) { Write-Host ("{0,-11} {1,-22} {2,-10} {3}" -f $e.Token, $e.Tracker, $e.Id, $e.Title) }
    Write-Host "check-tracker-status: $(@($entries | Where-Object Open).Count) open item(s) of $($entries.Count)"
    # -List lists only entries that PARSED; an entry with no valid status line is not in $entries at all, so say so rather than let the list read as complete.
    if ($problems.Count -gt 0) { Write-Host "check-tracker-status: WARNING - $($problems.Count) problem(s) exist, so this list may be incomplete; run without -List" -ForegroundColor Yellow }
    exit 0
}
if ($problems.Count -gt 0) {
    foreach ($p in $problems) { Write-Host $p -ForegroundColor Red }
    Write-Host "`ncheck-tracker-status: $($problems.Count) problem(s) - see docs/tracker-format.md" -ForegroundColor Red
    exit 1
}
Write-Host "check-tracker-status: OK - $($entries.Count) entries, $(@($entries | Where-Object Open).Count) open" -ForegroundColor Green
exit 0

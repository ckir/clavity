#!/usr/bin/env pwsh
#requires -Version 7
<#
.SYNOPSIS
    DevelopersCockpit — a thin, interactive front-end over the clavity monorepo's dev tasks.

.DESCRIPTION
    A single-keypress PowerShell menu that DELEGATES to the canonical task layer
    (`just`, `scripts/*.ps1`, `gh`, `git`, `lefthook`) — it contains ZERO version/bump/build
    logic of its own. Every ship/release action is guarded by an explicit typed confirmation;
    nothing pushes on a single keypress (owner holds all pushes).

    Interactive-only (no -Action mode — `just` already IS the scriptable CLI). Dev-box tool,
    never shipped to an end user, so it freely assumes the dev toolchain.

    Design: docs/superpowers/specs/2026-07-12-developers-cockpit-design.md (owner + agy converged).

.EXAMPLE
    pwsh -File DevelopersCockpit.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Delegated commands resolve from the repo root regardless of the caller's cwd.
Set-Location $PSScriptRoot

# ---------------------------------------------------------------------------
# Presentation (honors NO_COLOR + non-TTY like the model)
# ---------------------------------------------------------------------------
$script:Interactive = -not [Console]::IsOutputRedirected
$script:UseColor    = $script:Interactive -and -not $env:NO_COLOR

function Write-C([string]$Text = '', [string]$Color = 'Gray') {
    if ($script:UseColor) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
}

# ---------------------------------------------------------------------------
# Member sets (see spec §Action set)
# ---------------------------------------------------------------------------
# Buildable = have a member justfile, so build/test/lint/fmt aggregate over them via root `just`.
$script:Buildable = @('dotnet', 'classic', 'ghidrust')
# Versioned = all five; `just bump <member> <version>` (ghidrust via `just bump-ghidrust <channel> <version>`).
$script:Versioned = @('dotnet', 'classic', 'ghidrust', 'agy-autotrain', 'commonmemory')

# Banner version sources — display-only reads (spec §Banner). check-versions.ps1 remains the sole gate.
$script:BannerMembers = @(
    [pscustomobject]@{ Name = 'dotnet';        Iss = 'clavity-dotnet/installer/clavity-dotnet.iss' }
    [pscustomobject]@{ Name = 'classic';       Iss = 'clavity-classic/installer/clavity-classic.iss' }
    [pscustomobject]@{ Name = 'ghidrust';      Iss = 'ghidrust/installer/ghidrust.iss' }
    [pscustomobject]@{ Name = 'agy-autotrain'; Iss = 'agy-autotrain/installer/agy-autotrain.iss' }
    [pscustomobject]@{ Name = 'commonmemory';  Iss = 'commonmemory/installer/commonmemory.iss' }
)

function Get-MemberVersion([string]$IssPath) {
    # Best-effort, display-only: an unreadable/missing source shows '?' and never aborts.
    try {
        $c = Get-Content -Raw -ErrorAction Stop -- $IssPath
        if ($c -match '#define\s+AppVersion\s+"([^"]+)"') { return $Matches[1] }
    } catch { }
    return '?'
}

# ---------------------------------------------------------------------------
# Delegation helper — surface a delegated command's failure without killing the menu
# ---------------------------------------------------------------------------
function Invoke-Cmd([string]$Cmd) {
    # $Cmd is always a hardcoded literal from the $Actions table (never operator free-text),
    # so Invoke-Expression here runs OUR own delegation strings, not user input.
    Write-C "  > $Cmd" 'DarkGray'
    Invoke-Expression $Cmd
    if ($LASTEXITCODE -ne 0) { throw "command exited with code $LASTEXITCODE" }
}

function Read-Trimmed([string]$Prompt) { return (Read-Host $Prompt).Trim() }

function Read-Choice([string]$Prompt, [string[]]$Valid) {
    $ans = Read-Trimmed $Prompt
    if ([string]::IsNullOrEmpty($ans)) { Write-C '  aborted.' 'DarkGray'; return $null }
    if ($ans -notin $Valid) { Write-C "  not one of: $($Valid -join ', ')" 'Yellow'; return $null }
    return $ans
}

# Owner-gate: print exactly what will run, require the literal case-sensitive word 'push' (spec §Owner-gate).
function Confirm-Owner([string[]]$Commands) {
    Write-C '  OWNER-GATED — this will run:' 'Yellow'
    foreach ($c in $Commands) { Write-C "    $c" 'Yellow' }
    $ans = Read-Host "  type 'push' (exactly) to proceed"
    if ($ans -cne 'push') { Write-C '  aborted.' 'DarkGray'; return $false }
    return $true
}

# ---------------------------------------------------------------------------
# Handlers (actions that need prompts / confirmation)
# ---------------------------------------------------------------------------
function Invoke-MemberBuildTest {
    $m = Read-Choice "  member ($($script:Buildable -join '/'))" $script:Buildable
    if (-not $m) { return }
    Invoke-Cmd "just $m::build"
    Invoke-Cmd "just $m::test"
}

function Invoke-FullGate {
    Invoke-Cmd 'just lint'
    Invoke-Cmd 'just test'
}

function Invoke-VersionCheckAll {
    $anyFail = $false
    foreach ($m in $script:Versioned) {
        & pwsh -File (Join-Path $PSScriptRoot 'scripts/check-versions.ps1') $m
        if ($LASTEXITCODE -ne 0) { $anyFail = $true; Write-C "  [FAIL] $m" 'Yellow' }
        else                     { Write-C "  [ ok ] $m" 'Green' }
    }
    if ($anyFail) { throw 'one or more members failed check-versions' }
}

function Invoke-BumpMember {
    $m = Read-Choice "  member ($($script:Versioned -join '/'))" $script:Versioned
    if (-not $m) { return }
    if ($m -eq 'ghidrust') {
        $ch = Read-Choice '  channel (binary/plugin)' @('binary', 'plugin')
        if (-not $ch) { return }
        $v = Read-Trimmed '  new version (X.Y.Z)'
        if (-not $v) { Write-C '  aborted.' 'DarkGray'; return }
        Invoke-Cmd "just bump-ghidrust $ch $v"
    } else {
        $v = Read-Trimmed '  new version (X.Y.Z)'
        if (-not $v) { Write-C '  aborted.' 'DarkGray'; return }
        Invoke-Cmd "just bump $m $v"
    }
}

function Invoke-TagPush {
    $n = Read-Trimmed '  serial N for clavity-vN'
    if ($n -notmatch '^\d+$') { Write-C '  need a positive integer.' 'Yellow'; return }
    $tag = "clavity-v$n"
    if (-not (Confirm-Owner @("git tag $tag", "git push origin $tag"))) { return }
    Invoke-Cmd "git tag $tag"
    Invoke-Cmd "git push origin $tag"
}

function Invoke-TriggerRelease {
    if (-not (Confirm-Owner @('gh workflow run umbrella-release.yml'))) { return }
    Invoke-Cmd 'gh workflow run umbrella-release.yml'
}

function Invoke-Republish {
    $tag = Read-Trimmed '  existing tag (clavity-vN)'
    if (-not $tag) { Write-C '  aborted.' 'DarkGray'; return }
    $m = Read-Choice "  member ($($script:Versioned -join '/'))" $script:Versioned
    if (-not $m) { return }
    $cmd = "gh workflow run republish-member.yml -f tag=$tag -f member=$m"
    if (-not (Confirm-Owner @($cmd))) { return }
    Invoke-Cmd $cmd
}

function Invoke-DocsAudit {
    # Stage-1 docs-rationalize audit (scripts/docs-audit.ps1 via `just docs-audit`). Deliberately SCOPED behind a
    # prompt rather than exposed as a bare Cmd row: a full run makes ONE PAID `claude -p` call per doc across all
    # 25 user-facing docs and can run for hours, which would block this menu. It is never a gate — it edits no
    # docs, makes no commit, and writes only gitignored artifacts.
    $mode = Read-Choice '  scope — (p)review dry-run / (o)ne doc / (a)ll 25 docs' @('p', 'o', 'a')
    if (-not $mode) { return }
    switch ($mode) {
        'p' { Invoke-Cmd 'just docs-audit -WhatIf' }
        'o' {
            $doc = Read-Trimmed '  doc path exactly as listed in docs/user-facing-docs.txt (e.g. SECURITY.md)'
            if (-not $doc) { Write-C '  aborted.' 'DarkGray'; return }
            # ONE doc only, so no comma hazard here. For several, the flag needs COMMAS AND NO SPACES
            # (`-Only a.md,b.md`): under `pwsh -File` a space-separated 2nd value silently binds to the
            # script's next positional parameter instead. A subset run also skips the repo-wide link-check.
            Invoke-Cmd "just docs-audit -Only $doc"
        }
        'a' {
            Write-C '  A full run makes one PAID claude call per doc over all 25 user-facing docs and can take' 'Yellow'
            Write-C '  hours. It edits no docs and makes no commit; all output is gitignored.' 'Yellow'
            $go = Read-Choice '  proceed? (y/n)' @('y', 'n')
            if ($go -ne 'y') { Write-C '  aborted.' 'DarkGray'; return }
            Invoke-Cmd 'just docs-audit'
        }
    }
}

# Health check — probe each dev tool independently; one missing tool never stops the sweep (spec §Housekeeping).
$script:HealthProbes = @(
    [pscustomobject]@{ Name = 'just';                      Cmd = 'just --version' }
    [pscustomobject]@{ Name = 'dotnet';                    Cmd = 'dotnet --version' }
    [pscustomobject]@{ Name = 'cargo';                     Cmd = 'cargo --version' }
    [pscustomobject]@{ Name = 'rustc';                     Cmd = 'rustc --version' }
    [pscustomobject]@{ Name = 'pwsh';                      Cmd = 'pwsh --version' }
    [pscustomobject]@{ Name = 'git';                       Cmd = 'git --version' }
    [pscustomobject]@{ Name = 'gh';                        Cmd = 'gh --version' }
    [pscustomobject]@{ Name = 'uv';                        Cmd = 'uv --version' }
    [pscustomobject]@{ Name = 'cargo set-version (cargo-edit)'; Cmd = 'cargo set-version --version' }
    [pscustomobject]@{ Name = 'lefthook';                  Cmd = 'lefthook version' }
    [pscustomobject]@{ Name = 'yq';                        Cmd = 'yq --version' }
    [pscustomobject]@{ Name = 'bash';                      Cmd = 'bash --version' }
    [pscustomobject]@{ Name = 'cargo-nextest';             Cmd = 'cargo nextest --version' }
    [pscustomobject]@{ Name = 'cargo-deny';                Cmd = 'cargo deny --version' }
    # `claude` is the audit engine behind `just docs-audit` (action A); without it that action refuses with
    # exit 3. Not probing `mlc` (the link-checker it also shells out to): it prints a banner rather than a
    # version line, so the row would be noise.
    [pscustomobject]@{ Name = 'claude (docs-audit engine)'; Cmd = 'claude --version' }
    [pscustomobject]@{ Name = 'iscc (Inno Setup)';         Cmd = 'iscc' }  # no --version; presence is the signal, may be absent on a dev box
)

function Invoke-HealthCheck {
    foreach ($p in $script:HealthProbes) {
        $exe = $p.Cmd.Split(' ')[0]
        if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) {
            Write-C ('  [FAIL] {0,-30} (not on PATH)' -f $p.Name) 'Yellow'
            continue
        }
        try {
            $out = (& { Invoke-Expression $p.Cmd } 2>&1 | Select-Object -First 1)
            Write-C ('  [ ok ] {0,-30} {1}' -f $p.Name, (($out -join ' ') -replace '\s+', ' ').Trim()) 'Green'
        } catch {
            Write-C ('  [FAIL] {0,-30} {1}' -f $p.Name, $_.Exception.Message) 'Yellow'
        }
    }
}

# ---------------------------------------------------------------------------
# Action set — PURE DATA (the review/test seam: eyeball each Key -> canonical command)
# Tier index: 0=[1] INNER LOOP, 1=[2] QUALITY GATE, 2=[3] SHIP & RELEASE, 3=[4] HOUSEKEEPING.
# Each row has EITHER a Cmd (string run through the shell) XOR a Handler (scriptblock).
# ---------------------------------------------------------------------------
$script:Tiers = @(
    '[1] INNER LOOP',
    '[2] QUALITY GATE',
    '[3] SHIP & RELEASE  (owner-gated)',
    '[4] HOUSEKEEPING'
)

$script:Actions = @(
    # [1] INNER LOOP
    [pscustomobject]@{ Key = 'B'; Tier = 0; Desc = 'Build all';                Note = '';        Cmd = 'just build' }
    [pscustomobject]@{ Key = 'T'; Tier = 0; Desc = 'Test all';                 Note = '';        Cmd = 'just test' }
    [pscustomobject]@{ Key = 'F'; Tier = 0; Desc = 'Format all';               Note = 'mutates'; Cmd = 'just fmt' }
    [pscustomobject]@{ Key = 'M'; Tier = 0; Desc = 'Build + test ONE member';  Note = '';        Handler = { Invoke-MemberBuildTest } }

    # [2] QUALITY GATE
    [pscustomobject]@{ Key = 'L'; Tier = 1; Desc = 'Lint all';                 Note = '';        Cmd = 'just lint' }
    [pscustomobject]@{ Key = 'G'; Tier = 1; Desc = 'Full gate (lint + test)';  Note = '';        Handler = { Invoke-FullGate } }
    [pscustomobject]@{ Key = 'V'; Tier = 1; Desc = 'Check versions (all 5)';   Note = '';        Handler = { Invoke-VersionCheckAll } }
    [pscustomobject]@{ Key = 'S'; Tier = 1; Desc = 'Seed-sync check';          Note = '';        Cmd = 'just seed-sync-check' }

    # [3] SHIP & RELEASE (owner-gated)
    [pscustomobject]@{ Key = 'U'; Tier = 2; Desc = 'Version bump member';      Note = 'writes';  Handler = { Invoke-BumpMember } }
    [pscustomobject]@{ Key = 'R'; Tier = 2; Desc = 'Tag & push clavity-vN';    Note = 'OWNER';   Handler = { Invoke-TagPush } }
    [pscustomobject]@{ Key = 'W'; Tier = 2; Desc = 'Trigger umbrella release'; Note = 'OWNER';   Handler = { Invoke-TriggerRelease } }
    [pscustomobject]@{ Key = 'P'; Tier = 2; Desc = 'Republish ONE member';     Note = 'OWNER';   Handler = { Invoke-Republish } }

    # [4] HOUSEKEEPING
    [pscustomobject]@{ Key = 'A'; Tier = 3; Desc = 'Docs accuracy audit';       Note = 'paid; never a gate'; Handler = { Invoke-DocsAudit } }
    [pscustomobject]@{ Key = 'H'; Tier = 3; Desc = 'Health check (tool versions)'; Note = ''; Handler = { Invoke-HealthCheck } }
    [pscustomobject]@{ Key = 'I'; Tier = 3; Desc = 'Install git hooks';        Note = '';        Cmd = 'lefthook install' }
    [pscustomobject]@{ Key = 'N'; Tier = 3; Desc = 'Validate members manifest';Note = '';        Cmd = 'pwsh -File scripts/validate-members-manifest.ps1' }
    [pscustomobject]@{ Key = 'Q'; Tier = 3; Desc = 'Quit';                     Note = '';        Handler = { $script:Quit = $true } }
)

# ---------------------------------------------------------------------------
# Render + main loop
# ---------------------------------------------------------------------------
function Render-Menu {
    if ($script:Interactive) { Clear-Host }
    Write-Host ''
    $parts = $script:BannerMembers | ForEach-Object { "$($_.Name) $(Get-MemberVersion $_.Iss)" }
    Write-C ('DEVELOPERS COCKPIT — clavity   [{0}]' -f ($parts -join ' | ')) 'Cyan'
    Write-Host ''
    for ($t = 0; $t -lt $script:Tiers.Count; $t++) {
        Write-C $script:Tiers[$t] 'Magenta'
        foreach ($a in ($script:Actions | Where-Object { $_.Tier -eq $t })) {
            $note = if ($a.Note) { "  ($($a.Note))" } else { '' }
            Write-C ('   {0}   {1}{2}' -f $a.Key, $a.Desc, $note) 'Gray'
        }
        Write-Host ''
    }
}

$script:Quit = $false
while (-not $script:Quit) {
    Render-Menu
    $key = (Read-Host 'select').Trim().ToUpperInvariant()
    if ([string]::IsNullOrEmpty($key)) { continue }
    $row = $script:Actions | Where-Object { $_.Key -eq $key } | Select-Object -First 1
    if (-not $row) { Write-C "invalid key '$key', try again" 'Yellow'; Start-Sleep -Milliseconds 500; continue }

    # Invoke inside try/catch so any failure (thrown or non-zero exit) is printed and the loop continues.
    try {
        if ($row.PSObject.Properties['Cmd'] -and $row.Cmd) { Invoke-Cmd $row.Cmd }
        elseif ($row.PSObject.Properties['Handler'] -and $row.Handler) { & $row.Handler }
    } catch {
        Write-C "[CLI] Error: $($_.Exception.Message)" 'Red'
    }

    if (-not $script:Quit) {
        Write-Host ''
        [void](Read-Host 'Press Enter to continue')
    }
}
Write-C 'bye.' 'Cyan'

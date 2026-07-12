#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Assert every release-version source for a clavity member agrees (equality gate), or, with
  -Coverage, that no git-tracked version-bearing file of a known type is unregistered.

.DESCRIPTION
  The single definition of "the versions are consistent", called by every build-<member>.yml CI
  gate, by scripts/bump-version.ps1's self-verify, and by the lefthook pre-push hook. Dev/CI-time
  only (never on an end-user box), so cargo/uv/Select-String oracles are all in-bounds.
  Fail-closed: any unreadable source or missing required tool exits non-zero.

.PARAMETER Member
  One of: dotnet, classic, ghidrust, agy-autotrain, commonmemory.

.PARAMETER Coverage
  Enumerate git-tracked version-bearing files by known TYPE under the member's tree and fail if any
  is not registered in that member's source list. (Implemented in Task 2.)

.EXAMPLE
  pwsh scripts/check-versions.ps1 classic
.EXAMPLE
  pwsh scripts/check-versions.ps1 ghidrust -Coverage
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('dotnet', 'classic', 'ghidrust', 'agy-autotrain', 'commonmemory')]
    [string]$Member,

    [switch]$Coverage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$SemverRe = '^\d+\.\d+\.\d+$'

function Fail([string]$msg) {
    Write-Host "check-versions: FAIL ($Member): $msg" -ForegroundColor Red
    exit 1
}

# --- cargo metadata cache: one call per manifest path; returns @{ crateName = version } ---
$script:CargoCache = @{}
function Get-CargoVersions([string]$manifestRel) {
    if ($script:CargoCache.ContainsKey($manifestRel)) { return $script:CargoCache[$manifestRel] }
    $manifest = Join-Path $RepoRoot $manifestRel
    if (-not (Test-Path $manifest)) { Fail "Cargo manifest not found: $manifestRel" }
    if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) { Fail "required tool 'cargo' not found on PATH" }
    $json = & cargo metadata --manifest-path $manifest --no-deps --format-version 1 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { Fail "cargo metadata failed for $manifestRel" }
    try { $meta = ($json | Out-String) | ConvertFrom-Json }
    catch { Fail "could not parse cargo metadata JSON for ${manifestRel}: $($_.Exception.Message)" }
    $map = @{}
    foreach ($p in $meta.packages) { $map[$p.name] = $p.version }
    $script:CargoCache[$manifestRel] = $map
    return $map
}

function Read-Version([hashtable]$src) {
    switch ($src.Type) {
        'iss' {
            $p = Join-Path $RepoRoot $src.Path
            if (-not (Test-Path $p)) { Fail "iss not found: $($src.Path)" }
            $m = Select-String -Path $p -Pattern '#define AppVersion "([^"]+)"'
            if (-not $m) { Fail "no '#define AppVersion' in $($src.Path)" }
            return $m.Matches[0].Groups[1].Value
        }
        'json' {
            $p = Join-Path $RepoRoot $src.Path
            if (-not (Test-Path $p)) { Fail "json not found: $($src.Path)" }
            try { $obj = Get-Content -Raw $p | ConvertFrom-Json }
            catch { Fail "malformed JSON in $($src.Path): $($_.Exception.Message)" }
            if (-not $obj.PSObject.Properties.Name.Contains('version')) { Fail "no .version key in $($src.Path)" }
            return $obj.version
        }
        'cargo' {
            $map = Get-CargoVersions $src.Path
            if (-not $map.ContainsKey($src.Crate)) { Fail "crate '$($src.Crate)' not in workspace of $($src.Path)" }
            return $map[$src.Crate]
        }
        'cargolock' {
            $p = Join-Path $RepoRoot $src.Path
            if (-not (Test-Path $p)) { Fail "Cargo.lock not found: $($src.Path)" }
            $lines = Get-Content $p
            $needle = 'name = "' + $src.Crate + '"'
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i].Trim() -eq $needle) {
                    for ($j = $i + 1; $j -lt [Math]::Min($i + 4, $lines.Count); $j++) {
                        if ($lines[$j] -match '^version = "([^"]+)"') { return $Matches[1] }
                    }
                }
            }
            Fail "crate '$($src.Crate)' version not found in $($src.Path)"
        }
        'pyproject' {
            $p = Join-Path $RepoRoot $src.Path
            if (-not (Test-Path $p)) { Fail "pyproject not found: $($src.Path)" }
            $inProject = $false
            foreach ($line in Get-Content $p) {
                if ($line -match '^\[project\]\s*$') { $inProject = $true; continue }
                if ($inProject -and $line -match '^\[') { break }
                if ($inProject -and $line -match '^version\s*=\s*"([^"]+)"') { return $Matches[1] }
            }
            Fail "[project] version not found in $($src.Path)"
        }
        default { Fail "unknown source type: $($src.Type)" }
    }
}

function Assert-UvLock([hashtable]$src) {
    $dir = Join-Path $RepoRoot $src.Dir
    if (-not (Test-Path $dir)) { Fail "bridge dir not found: $($src.Dir)" }
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) { Fail "required tool 'uv' not found on PATH" }
    Push-Location $dir
    try {
        # Capture stderr so an *unsupported-flag* error (older uv) is surfaced, not masked as "stale".
        $out = (& uv lock --check 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) {
            if ($out -match 'unexpected argument|unrecognized|invalid value|--check') {
                Fail "uv does not support 'uv lock --check' (need a newer uv; verify with 'uv --version'). Raw: $($out.Trim())"
            }
            Fail "uv.lock is stale vs pyproject.toml in $($src.Dir) (run 'uv lock'). Raw: $($out.Trim())"
        }
    } finally { Pop-Location }
}

function Test-HasLiteralTomlVersion([string]$path, [string]$section) {
    # True only if the file has a literal `[<section>]` table with a literal semver `version = "x.y.z"`
    # before the next `[...]` header. Excludes workspace roots (no such table) and version.workspace crates.
    if (-not (Test-Path $path)) { return $false }
    $inSection = $false
    foreach ($line in Get-Content $path) {
        if ($line -match "^\[$section\]\s*$") { $inSection = $true; continue }
        if ($inSection -and $line -match '^\[') { break }
        if ($inSection -and $line -match '^version\s*=\s*"\d+\.\d+\.\d+"') { return $true }
    }
    return $false
}

function Invoke-Coverage([hashtable]$cfg) {
    $folder = $cfg.Folder
    $registered = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($f in $cfg.CoverageFiles) { [void]$registered.Add(($f -replace '\\', '/')) }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail "required tool 'git' not found on PATH" }
    # A bare directory pathspec recursively lists every tracked file under it (version-portable);
    # avoid a `$folder/**` glob, whose `**` is not special in a plain git pathspec.
    $tracked = & git -C $RepoRoot ls-files -- "$folder"
    if ($LASTEXITCODE -ne 0) { Fail "git ls-files failed for $folder" }

    # Exclude build/artifact/fixture dirs (spec): any path segment target|.venv|bin|obj|dist|publish|node_modules, or a /fixtures/ dir.
    $excludeRe = '(^|/)(target|\.venv|bin|obj|dist|publish|node_modules)/|/fixtures/'

    $unregistered = @()
    foreach ($raw in $tracked) {
        $rel = $raw -replace '\\', '/'
        if ($rel -match $excludeRe) { continue }
        $base = Split-Path $rel -Leaf
        $isCandidate = switch -Regex ($base) {
            '^plugin\.json$'    { $true;  break }
            '\.iss$'            { $true;  break }
            '^Cargo\.lock$'     { $true;  break }
            '^uv\.lock$'        { $true;  break }
            '^Cargo\.toml$'     { Test-HasLiteralTomlVersion (Join-Path $RepoRoot $rel) 'package'; break }
            '^pyproject\.toml$' { Test-HasLiteralTomlVersion (Join-Path $RepoRoot $rel) 'project'; break }
            default             { $false }
        }
        if ($isCandidate -and -not $registered.Contains($rel)) { $unregistered += $rel }
    }

    if ($unregistered.Count -gt 0) {
        Fail "unregistered version-bearing file(s) — add to the check-versions.ps1 registry for '$Member':`n  $($unregistered -join "`n  ")"
    }
    Write-Host "check-versions: coverage OK ($Member) — every known version-file type is registered." -ForegroundColor Green
}

# --- per-member registry ---
$Registry = @{
    'dotnet' = @{
        Folder = 'clavity-dotnet'
        Classes = @(
            @{ Name = 'all'; Eq = @(
                @{ Type = 'iss';  Path = 'clavity-dotnet/installer/clavity-dotnet.iss' }
                @{ Type = 'json'; Path = 'clavity-dotnet/plugin/plugin.json' }
                @{ Type = 'json'; Path = 'clavity-dotnet/plugin/.claude-plugin/plugin.json' }
            ) }
        )
        CoverageFiles = @(
            'clavity-dotnet/installer/clavity-dotnet.iss'
            'clavity-dotnet/plugin/plugin.json'
            'clavity-dotnet/plugin/.claude-plugin/plugin.json'
        )
    }
    'classic' = @{
        Folder = 'clavity-classic'
        Classes = @(
            @{ Name = 'all'; Eq = @(
                @{ Type = 'cargo';     Path = 'clavity-classic/Cargo.toml'; Crate = 'clavity' }
                @{ Type = 'cargolock'; Path = 'clavity-classic/Cargo.lock'; Crate = 'clavity' }
                @{ Type = 'pyproject'; Path = 'clavity-classic/agy-mcp-bridge/pyproject.toml' }
                @{ Type = 'iss';       Path = 'clavity-classic/installer/clavity-classic.iss' }
                @{ Type = 'json';      Path = 'clavity-classic/plugin/plugin.json' }
                @{ Type = 'json';      Path = 'clavity-classic/plugin/.claude-plugin/plugin.json' }
            ); Assert = @(
                @{ Type = 'uvlock'; Dir = 'clavity-classic/agy-mcp-bridge' }
            ) }
        )
        CoverageFiles = @(
            'clavity-classic/Cargo.toml'
            'clavity-classic/Cargo.lock'
            'clavity-classic/agy-mcp-bridge/pyproject.toml'
            'clavity-classic/agy-mcp-bridge/uv.lock'
            'clavity-classic/installer/clavity-classic.iss'
            'clavity-classic/plugin/plugin.json'
            'clavity-classic/plugin/.claude-plugin/plugin.json'
        )
    }
    'ghidrust' = @{
        Folder = 'ghidrust'
        Classes = @(
            @{ Name = 'binary'; Eq = @(
                @{ Type = 'cargo';     Path = 'ghidrust/Cargo.toml'; Crate = 'ghidrust-mcp' }
                @{ Type = 'cargo';     Path = 'ghidrust/Cargo.toml'; Crate = 'ghidra-ipc' }
                @{ Type = 'cargo';     Path = 'ghidrust/Cargo.toml'; Crate = 'ghidra-worker-ctl' }
                @{ Type = 'cargolock'; Path = 'ghidrust/Cargo.lock'; Crate = 'ghidrust-mcp' }
                @{ Type = 'cargolock'; Path = 'ghidrust/Cargo.lock'; Crate = 'ghidra-ipc' }
                @{ Type = 'cargolock'; Path = 'ghidrust/Cargo.lock'; Crate = 'ghidra-worker-ctl' }
                @{ Type = 'iss';       Path = 'ghidrust/installer/ghidrust.iss' }
            ) }
            @{ Name = 'plugin'; Eq = @(
                @{ Type = 'json'; Path = 'ghidrust/plugin/plugin.json' }
                @{ Type = 'json'; Path = 'ghidrust/plugin/.claude-plugin/plugin.json' }
            ) }
        )
        CoverageFiles = @(
            'ghidrust/crates/ghidrust-mcp/Cargo.toml'
            'ghidrust/crates/ghidra-ipc/Cargo.toml'
            'ghidrust/crates/ghidra-worker-ctl/Cargo.toml'
            'ghidrust/Cargo.lock'
            'ghidrust/installer/ghidrust.iss'
            'ghidrust/plugin/plugin.json'
            'ghidrust/plugin/.claude-plugin/plugin.json'
        )
    }
    'agy-autotrain' = @{
        Folder = 'agy-autotrain'
        Classes = @(
            @{ Name = 'all'; Eq = @(
                @{ Type = 'iss';  Path = 'agy-autotrain/installer/agy-autotrain.iss' }
                @{ Type = 'json'; Path = 'agy-autotrain/plugin.json' }
                @{ Type = 'json'; Path = 'agy-autotrain/.claude-plugin/plugin.json' }
            ) }
        )
        CoverageFiles = @(
            'agy-autotrain/installer/agy-autotrain.iss'
            'agy-autotrain/plugin.json'
            'agy-autotrain/.claude-plugin/plugin.json'
        )
    }
    'commonmemory' = @{
        Folder = 'commonmemory'
        Classes = @(
            @{ Name = 'all'; Eq = @(
                @{ Type = 'iss';  Path = 'commonmemory/installer/commonmemory.iss' }
                @{ Type = 'json'; Path = 'commonmemory/plugin.json' }
                @{ Type = 'json'; Path = 'commonmemory/.claude-plugin/plugin.json' }
            ) }
        )
        CoverageFiles = @(
            'commonmemory/installer/commonmemory.iss'
            'commonmemory/plugin.json'
            'commonmemory/.claude-plugin/plugin.json'
        )
    }
}

$cfg = $Registry[$Member]

if ($Coverage) {
    Invoke-Coverage $cfg    # defined in Task 2
    exit 0
}

foreach ($class in $cfg.Classes) {
    $values = [ordered]@{}
    foreach ($src in $class.Eq) {
        $v = Read-Version $src
        if ($v -notmatch $SemverRe) { Fail "non-semver value '$v' from $($src.Type):$($src.Path)" }
        $label = if ($src.ContainsKey('Crate')) { "$($src.Path)#$($src.Crate)" } else { $src.Path }
        $values[$label] = $v
    }
    $distinct = @($values.Values | Select-Object -Unique)
    if ($distinct.Count -ne 1) {
        $detail = ($values.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n  "
        Fail "class '$($class.Name)' versions disagree:`n  $detail"
    }
    if ($class.ContainsKey('Assert')) {
        foreach ($a in $class.Assert) {
            switch ($a.Type) {
                'uvlock' { Assert-UvLock $a }
                default  { Fail "unknown assert type: $($a.Type)" }
            }
        }
    }
    Write-Host "check-versions: class '$($class.Name)' OK ($Member) = $($distinct[0])" -ForegroundColor Green
}

Write-Host "check-versions: OK ($Member)" -ForegroundColor Green
exit 0

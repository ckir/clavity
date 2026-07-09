#requires -Version 7
<#
.SYNOPSIS
  7.8 build recipe — produce the clavity-classic release artifact + staged bridge into publish/.

.DESCRIPTION
  The SHARED build recipe run BOTH locally (to populate publish/ so installer/clavity-classic.iss can be
  authored + ISCC-verified before any tag) AND by the 7.2 release workflow. Mirrors the dotnet
  `dotnet publish` -> publish/ -> ISCC flow. No cross-repo fetch: the bridge source is in-branch at
  agy-mcp-bridge/ (the canonical home).

  Stages ONLY the bridge RUNTIME whitelist — dev/test files (test_*.py, tests/, lefthook.yml,
  VENDORED-FROM.md, .gitignore) and the secret (.env / .venv / caches) are NEVER shipped.
#>
[CmdletBinding()]
param(
    [string]$Configuration = 'release'
)
$ErrorActionPreference = 'Stop'

$repoRoot   = (Resolve-Path "$PSScriptRoot\..").Path
$publishDir = Join-Path $repoRoot 'publish'
$bridgeSrc  = Join-Path $repoRoot 'agy-mcp-bridge'
$bridgeDst  = Join-Path $publishDir 'agy-mcp-bridge'

# 1) Build the Rust binary (locked = no silent dep bump; reproducible local<->CI).
Write-Host '==> cargo build --release --locked'
& cargo build --release --locked
$exe = Join-Path $repoRoot 'target\release\clavity.exe'
if (-not (Test-Path $exe)) { throw "build produced no clavity.exe at $exe" }

# 2) Clean + recreate publish/.
if (Test-Path $publishDir) { Remove-Item $publishDir -Recurse -Force }
New-Item -ItemType Directory -Path $bridgeDst -Force | Out-Null

# 3) Stage the binary.
Copy-Item $exe (Join-Path $publishDir 'clavity.exe')

# 4) Stage the bridge RUNTIME whitelist ONLY (SKILL.md is runtime: server.py loads it as CANONICAL_SKILL).
$runtime = @(
    'server.py', 'agy_bus.py', 'agy_tmux.py', 'isolation.py', 'telemetry.py',
    'SKILL.md', 'pyproject.toml', 'uv.lock', 'start-claudavity.ps1', '.env.example', 'LICENSE'
)
foreach ($f in $runtime) {
    $from = Join-Path $bridgeSrc $f
    if (-not (Test-Path $from)) { throw "bridge runtime file missing: $f" }
    Copy-Item $from (Join-Path $bridgeDst $f)
}

# 5) Secret-boundary assertion: the live .env must NEVER reach publish/.
if (Test-Path (Join-Path $bridgeDst '.env')) { throw 'SECURITY: .env leaked into publish/agy-mcp-bridge/' }

Write-Host "==> staged $($runtime.Count) bridge runtime files + clavity.exe into $publishDir"
Get-ChildItem $publishDir -Recurse -File | ForEach-Object { $_.FullName.Substring($publishDir.Length + 1) }

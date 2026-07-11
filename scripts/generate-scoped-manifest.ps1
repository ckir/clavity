<#
.SYNOPSIS
Generates a single-plugin scoped marketplace.json for one clavity member, from the non-addable
build/members.json build source (docs/superpowers/specs/2026-07-11-cohesive-distribution-design.md,
C1/C3/C9/O3). The output's top-level "name" is the member's UNIQUE marketplaceName (C9) — this is
the value `claude plugin install <plugin>@<name>` must match, and it must never collide across the
five installers.

.PARAMETER MemberName
The member's plugin real name exactly as it appears in build/members.json "name" (e.g.
"clavity-dotnet", "ghidrust", "agy-autotrain") — NOT the marketplaceName.

.PARAMETER MembersJsonPath
Path to the repo-root build/members.json. Defaults to a path relative to this script's own
location so it resolves correctly regardless of the caller's working directory.

.PARAMETER OutFile
Destination path for the generated scoped marketplace.json (e.g.
"installer/marketplace.install.json" — the installer's [Files] then copies this literal path to
{app}\.claude-plugin\marketplace.json, DestName-renamed).
#>
param(
    [Parameter(Mandatory = $true)][string]$MemberName,
    [string]$MembersJsonPath = "$PSScriptRoot/../build/members.json",
    [Parameter(Mandatory = $true)][string]$OutFile
)

$ErrorActionPreference = "Stop"

$root = Get-Content $MembersJsonPath -Raw | ConvertFrom-Json
$member = $root.members | Where-Object { $_.name -eq $MemberName }
if (-not $member) { throw "member '$MemberName' not found in $MembersJsonPath" }
if (-not $member.marketplaceName) { throw "member '$MemberName' has no marketplaceName in $MembersJsonPath" }

# C1 scoped-manifest path/source contract: the plugin is always staged at {app}\plugins\<name> by
# the installer's own [Files] section — the generated source MUST match that literally, or every
# install fatally aborts (Failure mode J).
$scoped = [ordered]@{
    '$schema' = 'https://code.claude.com/schemas/marketplace.json'
    name      = $member.marketplaceName
    owner     = $root.owner
    plugins   = @(
        [ordered]@{
            name        = $member.name
            source      = "./plugins/$($member.name)"
            description = $member.description
        }
    )
}

$outDir = Split-Path -Parent $OutFile
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
$scoped | ConvertTo-Json -Depth 10 | Set-Content -Path $OutFile -Encoding utf8
Write-Host "generated ${OutFile}: name=$($member.marketplaceName) plugin=$($member.name) source=./plugins/$($member.name)"

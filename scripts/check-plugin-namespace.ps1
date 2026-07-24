<#
.SYNOPSIS
SP-0 namespace-rename completeness gate. Fails if the mass rename left any stray old reference.
Asserts (a) no `clavity-dotnet:<skill>` / `clavity-classic:<skill>` NAMESPACE refs; (b) no old
skill-DIR names (clavity-ls-driving, clavity-ls-pairing, clavity-driving) referenced anywhere
(on disk OR in a doc), matched WITHOUT a `plugin/` prefix; (c) no old plugin `name`
(clavity-dotnet/clavity-classic) in a plugin.json or a marketplace plugins[].name; (d) each driver
member in build/members.json carries pluginName='clavity' AND its plugin.json `name` agrees.
Must NOT flag: the retained marketplace SCOPE name (outer marketplace.install.json `name`, member
marketplaceName, scope paths); folder paths (clavity-dotnet/ , clavity-classic/); or the retained
agy-side `agy_skills/claudavity-responder` twin (Option A, deliberately excluded from (b)).
#>
param([string]$Root = "$PSScriptRoot/..")
$ErrorActionPreference = 'Stop'
# ripgrep exits 1 when it finds NO matches (the CLEAN case). Under PowerShell 7.4+ with EAP='Stop',
# $PSNativeCommandUseErrorActionPreference defaults to $true, turning that non-zero native exit into a
# THROW — which would crash this gate on a clean repo. We test rg's OUTPUT (presence of hits), never its
# exit code, so disable native-command error propagation. (rg is a repo-wide tooling assumption per
# cli-tooling.md; if it is somehow absent, the Get-Command guard below fails loudly instead of cryptically.)
$PSNativeCommandUseErrorActionPreference = $false
if (-not (Get-Command rg -ErrorAction SilentlyContinue)) { Write-Error "check-plugin-namespace requires ripgrep (rg) on PATH"; exit 2 }
$violations = @()

# (a) namespace-qualified old refs anywhere (the `:` is what makes it a namespace, not a folder/scope)
$nsHits = rg -n --glob '!**/docs/superpowers/**' --glob '!**/docs/session-notes/**' --glob '!**/docs/archive/**' `
    'clavity-(dotnet|classic):[a-z]' $Root 2>$null
if ($nsHits) { $violations += "(a) stray namespace ref(s):`n$nsHits" }

# (b) old skill-DIR names surviving anywhere (on disk OR in a doc/README reference). Match a bare
#     `skills/<oldname>` segment WITHOUT requiring a `plugin/` prefix, so a stale doc ref like
#     `skills/clavity-driving/` is caught too. `claudavity-responder` is DELIBERATELY NOT listed: its
#     plugin copy is renamed to `responder`, but the agy-side twin legitimately KEEPS the name
#     (Option A), and `agy_skills/claudavity-responder` ends in `skills/claudavity-responder`, so
#     listing it here would over-flag the retained twin. Plugin-responder completeness is covered by
#     the Phase 2 dir rename + the Phase 3 seed-sync + the Phase 5 doc pass, not by this gate.
$dirHits = rg -n 'skills[\\/](clavity-ls-driving|clavity-ls-pairing|clavity-driving)\b' $Root 2>$null
if ($dirHits) { $violations += "(b) old skill-dir ref(s):`n$dirHits" }

# (c) old plugin identity in a plugin.json `name` or a marketplace plugins[].name.
#     Scope to plugin.json / marketplace.install.json; match ONLY a plugins-array/identity `name`, never
#     the OUTER marketplace `name` (retained scope). NOTE: marketplace.install.json is GITIGNORED/generated,
#     so on committed state this branch typically scans only committed plugin.json files — the generated
#     manifest's plugins[].name is covered by CI install-smoke (Task 1.7) and, at its source, by check (d).
foreach ($f in (rg --files -g '**/plugin.json' -g '**/marketplace.install.json' $Root 2>$null)) {
    $j = Get-Content $f -Raw | ConvertFrom-Json
    if ($j.PSObject.Properties['plugins']) {
        foreach ($p in $j.plugins) { if ($p.name -in @('clavity-dotnet','clavity-classic')) { $violations += "(c) old plugin identity in ${f}: plugins[].name=$($p.name)" } }
    } elseif ($j.PSObject.Properties['name'] -and -not $j.PSObject.Properties['owner']) {
        # a bare plugin.json (not a marketplace manifest, which has owner/plugins): its `name` IS the identity
        if ($j.name -in @('clavity-dotnet','clavity-classic')) { $violations += "(c) old plugin identity in ${f}: name=$($j.name)" }
    }
}

# (d) members.json is the COMMITTED source of the emitted plugin identity (marketplace.install.json is
#     generated from it). Assert each driver member (keyed by its retained marketplaceName) carries
#     pluginName='clavity', and that the corresponding plugin.json `name` agrees — closing the drift hole
#     (c) cannot see on committed state.
$membersPath = Join-Path $Root 'build/members.json'
if (Test-Path $membersPath) {
    $members = (Get-Content $membersPath -Raw | ConvertFrom-Json).members
    # Cross-check BOTH plugin.json twins per driver (inner .claude-plugin/ AND top-level) — Task 1.3
    # renames all four; (d) must guard all four against future identity drift, not just the inner two.
    $driverMap = @{
        'clavity-dotnet'  = @('clavity-dotnet/plugin/.claude-plugin/plugin.json',  'clavity-dotnet/plugin/plugin.json')
        'clavity-classic' = @('clavity-classic/plugin/.claude-plugin/plugin.json', 'clavity-classic/plugin/plugin.json')
    }
    foreach ($mkt in $driverMap.Keys) {
        $m = $members | Where-Object { $_.marketplaceName -eq $mkt }
        if (-not $m) { $violations += "(d) members.json missing driver member with marketplaceName=$mkt"; continue }
        $pn = if ($m.PSObject.Properties['pluginName']) { $m.pluginName } else { $m.name }
        if ($pn -ne 'clavity') { $violations += "(d) members.json member $mkt has pluginName '$pn', expected 'clavity'" }
        foreach ($rel in $driverMap[$mkt]) {
            $pj = Join-Path $Root $rel
            if (Test-Path $pj) {
                $pjName = (Get-Content $pj -Raw | ConvertFrom-Json).name
                if ($pjName -ne $pn) { $violations += "(d) identity drift: $mkt members pluginName='$pn' but $rel name='$pjName'" }
            }
        }
    }
}

if ($violations.Count) { $violations | ForEach-Object { Write-Host $_ }; Write-Error "namespace-rename incomplete ($($violations.Count) class(es))"; exit 1 }
Write-Host "OK: plugin namespace rename complete (no stray clavity-dotnet/clavity-classic identity refs)."

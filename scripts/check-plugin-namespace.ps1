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

# All three repo scans below run from WITHIN $Root using a relative '.' path. rg only honors .gitignore
# when the search path is relative to the cwd inside the repo; given an ABSOLUTE path (or one containing
# '..', as the default $PSScriptRoot/.. is) it treats the path as explicit and scans gitignored files too
# — which made (c) flag the GITIGNORED, generated marketplace.install.json build artifacts (a false
# positive that would keep this gate RED forever, never green). Scanning from inside $Root with '.'
# restores gitignore-respect; for the non-git unit-test fixtures (no .gitignore) it just scans everything,
# the intended fixture behavior. Separately, the gate documents the forbidden patterns in its own
# docstring and exercises them in its Pester fixture, so it must EXCLUDE its own two files from the (a)/(b)
# text scans or it would flag itself (a linter never lints itself).
$selfExclude = @('--glob', '!**/check-plugin-namespace.ps1', '--glob', '!**/check-plugin-namespace.Tests.ps1')
Push-Location $Root
try {
    # (a) namespace-qualified old refs anywhere (the `:` is what makes it a namespace, not a folder/scope).
    #     `--hidden` so the scan descends into tracked HIDDEN dirs (.github/, .claude-plugin/, .vscode/) where a
    #     stray ref could otherwise slip past rg's default hidden-skip; `!**/.git/**` keeps it out of git internals.
    $nsHits = rg -n --hidden --glob '!**/.git/**' $selfExclude --glob '!**/docs/superpowers/**' --glob '!**/docs/session-notes/**' --glob '!**/docs/archive/**' `
        'clavity-(dotnet|classic):[a-z]' . 2>$null
    if ($nsHits) { $violations += "(a) stray namespace ref(s):`n$nsHits" }

    # (b) old skill-DIR names surviving anywhere (on disk OR in a doc/README reference). Match a bare
    #     `skills/<oldname>` segment WITHOUT requiring a `plugin/` prefix, so a stale doc ref like
    #     `skills/clavity-driving/` is caught too. `claudavity-responder` is DELIBERATELY NOT listed: its
    #     plugin copy is renamed to `responder`, but the agy-side twin legitimately KEEPS the name
    #     (Option A), and `agy_skills/claudavity-responder` ends in `skills/claudavity-responder`, so
    #     listing it here would over-flag the retained twin. Plugin-responder completeness is covered by
    #     the Phase 2 dir rename + the Phase 3 seed-sync + the Phase 5 doc pass, not by this gate.
    $dirHits = rg -n --hidden --glob '!**/.git/**' $selfExclude 'skills[\\/](clavity-ls-driving|clavity-ls-pairing|clavity-driving)\b' . 2>$null
    if ($dirHits) { $violations += "(b) old skill-dir ref(s):`n$dirHits" }

    # (c) old plugin identity in a plugin.json `name` or a marketplace plugins[].name. Match ONLY a
    #     plugins-array/identity `name`, never the OUTER marketplace `name` (retained scope). Enumerate the
    #     manifests to inspect via `git -C $Root ls-files` (cwd-independent) so we deterministically look at
    #     COMMITTED files only: the gitignored/generated marketplace.install.json build artifacts are
    #     untracked, so git never lists them — they're covered by CI install-smoke (Task 1.7) + check (d).
    #     This sidesteps rg's shell-context-dependent gitignore handling (an absolute/`-g` scan wrongly
    #     force-included those stale artifacts). Non-git unit-test fixtures fall back to a plain $Root scan.
    & git -C $Root rev-parse --is-inside-work-tree *> $null
    $manifestFiles = if ($LASTEXITCODE -eq 0) {
        @(git -C $Root ls-files) |
            Where-Object { $_ -match '(^|/)(plugin\.json|marketplace\.install\.json)$' } |
            ForEach-Object { Join-Path $Root $_ }
    } else {
        @(rg --files -g '**/plugin.json' -g '**/marketplace.install.json' $Root 2>$null)
    }
    foreach ($f in $manifestFiles) {
        $j = Get-Content $f -Raw | ConvertFrom-Json
        if ($j.PSObject.Properties['plugins']) {
            foreach ($p in $j.plugins) { if ($p.name -in @('clavity-dotnet','clavity-classic')) { $violations += "(c) old plugin identity in ${f}: plugins[].name=$($p.name)" } }
        } elseif ($j.PSObject.Properties['name'] -and -not $j.PSObject.Properties['owner']) {
            # a bare plugin.json (not a marketplace manifest, which has owner/plugins): its `name` IS the identity
            if ($j.name -in @('clavity-dotnet','clavity-classic')) { $violations += "(c) old plugin identity in ${f}: name=$($j.name)" }
        }
    }
} finally { Pop-Location }

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
            } else {
                # A completeness gate must not silently shrug if the manifest it is supposed to verify vanished.
                $violations += "(d) missing manifest: expected $rel for driver $mkt"
            }
        }
    }
}

# Hook matchers must not name a plugin-qualified MCP tool LITERALLY. The consult guard was dead on its
# primary path because its matcher named `mcp__plugin_clavity-dotnet_clavity-ls__agy_ask` while the live
# tool is `mcp__plugin_clavity_clavity-ls__agy_ask` -- the plugin is NAMED clavity and installed FROM the
# marketplace clavity-dotnet, and the matcher used the marketplace name. Two similar identifiers, wrong
# one chosen, and a hook that never fires cannot report its own absence. Require the pattern form.
$literalMatchers = @()
foreach ($manifest in @(
    'clavity-dotnet/plugin/hooks/hooks.json',
    'clavity-classic/plugin/hooks/hooks.json')) {
    $manifestPath = Join-Path $Root $manifest
    # Test-Path is REQUIRED, not defensive politeness. This script sets $ErrorActionPreference = 'Stop'
    # at :14, and its own unit fixtures in scripts/tests/check-plugin-namespace.Tests.ps1 build minimal
    # trees containing plugin.json and build/members.json but NO hooks/hooks.json (MEASURED: zero
    # occurrences of 'hooks.json' in that test file). An unguarded Get-Content therefore throws
    # ItemNotFoundException and every fixture-based test in that suite fails.
    if (-not (Test-Path $manifestPath)) { continue }
    $json = Get-Content $manifestPath -Raw | ConvertFrom-Json
    foreach ($event in $json.hooks.PSObject.Properties) {
        foreach ($group in $event.Value) {
            # Capstone round 2: the original form only caught the PLUGIN-namespaced shape
            # (mcp__plugin_<marketplace>_<server>__<tool>). An MCP server configured outside a plugin
            # bundle is named mcp__<server>__<tool>, which is EQUALLY fragile and slipped through
            # silently - MEASURED: 'mcp__clavity-ls__agy_ask' did not match the old regex. The optional
            # plugin_ group catches both. The legitimate PATTERN form is unaffected because a regex
            # matcher starts with '.' or another metacharacter after mcp__, which [A-Za-z0-9-] rejects
            # (MEASURED: 'mcp__.*agy_ask' does not match).
            if ($group.matcher -match 'mcp__(plugin_)?[A-Za-z0-9-]+_[A-Za-z0-9_]+') {
                $literalMatchers += "${manifest}: $($group.matcher)"
            }
        }
    }
}
if ($literalMatchers.Count -gt 0) {
    Write-Error ("Hook matcher names a plugin-qualified MCP tool literally; use a pattern such as " +
                 "'mcp__.*agy_ask' instead:`n  " + ($literalMatchers -join "`n  "))
    exit 1
}

if ($violations.Count) { $violations | ForEach-Object { Write-Host $_ }; Write-Error "namespace-rename incomplete ($($violations.Count) class(es))"; exit 1 }
Write-Host "OK: plugin namespace rename complete (no stray clavity-dotnet/clavity-classic identity refs)."

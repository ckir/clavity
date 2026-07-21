Set-StrictMode -Version Latest

# Explicit roster — do NOT derive from build/members.json (its source is the plugin subdir, name is the
# marketplace name). Iss = canonical current-version read (F5/FI2). Paths verified vs bump-version.ps1.
# `Marketplace` = the member's `name` in build/members.json (the marketplace manifest). It is the ONLY
# cross-reference between this release-tooling roster and members.json, consumed by the CC2 drift gate
# (Task 6b) — a strict bidirectional set-equality check that fails the build if this table and members.json
# ever disagree on the member set. This decoupled-schemas + proving-gate approach (owner-ratified 2026-07-12,
# agy-negotiated) honors spec CC2's INTENT (no silent un-versioned member) WITHOUT moving release-internal
# build paths (Root/Iss) into the marketplace manifest.
$script:Members = @(
    [pscustomobject]@{ Key='dotnet';        Marketplace='clavity-dotnet';  Root='clavity-dotnet';  Iss='clavity-dotnet/installer/clavity-dotnet.iss';   Ghidrust=$false }
    [pscustomobject]@{ Key='classic';       Marketplace='clavity-classic'; Root='clavity-classic'; Iss='clavity-classic/installer/clavity-classic.iss'; Ghidrust=$false }
    [pscustomobject]@{ Key='agy-autotrain'; Marketplace='agy-autotrain';   Root='agy-autotrain';   Iss='agy-autotrain/installer/agy-autotrain.iss';     Ghidrust=$false }
    [pscustomobject]@{ Key='commonmemory';  Marketplace='commonmemory';    Root='commonmemory';    Iss='commonmemory/installer/commonmemory.iss';       Ghidrust=$false }
    [pscustomobject]@{ Key='ghidrust';      Marketplace='ghidrust';        Root='ghidrust';        Iss='ghidrust/installer/ghidrust.iss';               Ghidrust=$true;  PluginJson='ghidrust/plugin/plugin.json' }
)
function Get-Members { $script:Members }

# --- Path taxonomy: shared-shipping + dev-only (owner-ratified 2026-07-21, agy-recommended) -------------
# The engine used to attribute a commit to a member by MEMBER-FOLDER pathspec alone, so a commit touching
# only shared/root paths bumped NOBODY and the run reported a clean "nothing to release" — a SILENT
# under-bump. It stranded 69ee30f, a fix for plugin registration failing on EVERY install. Now every
# tracked path falls in exactly one of three buckets:
#   member-bound     '<Root>/...'   -> that member, implicitly (unchanged)
#   shared-shipping  $SharedPaths   -> the DECLARED dependent member set below
#   dev-only         $DevOnlyPaths  -> deliberately bumps nobody (CI/docs/tooling)
# A path in NONE of the three is UNCLASSIFIED and makes the release FAIL LOUDLY (default-deny), so a new
# top-level path can never again ship as a quiet "nothing to release".
#
# DECLARE + PROVE: this table is the source of truth for what bumps (fast, explicit, reviewable), and
# Assert-SharedMapHealthy below is its auditor — it re-derives each set from the members' own installer
# sources and fails the build on any disagreement. Declaration alone would rot; derivation alone is blind
# to files no `#include` mentions (register-plugin.ps1 is shipped by a [Files] `Source:` line and invoked
# at RUNTIME — a pure #include parser attributes it to nobody, the exact bug class this replaces).
#
# `ghidrust` here always means its BINARY channel: every shared asset is an installer asset, and the
# ghidrust plugin channel versions ghidrust/plugin/** only.
# Provable=$false marks an asset member installers never name literally, so the grep auditor cannot see it;
# each carries its own justification and is covered instead by the coverage half of the gate.
$script:SharedPaths = @(
    [pscustomobject]@{ Path='installer/_shared/claude-running.iss';        Provable=$true;  Members=@('dotnet','classic','agy-autotrain','commonmemory','ghidrust') }
    [pscustomobject]@{ Path='installer/_shared/register-plugin.ps1';       Provable=$true;  Members=@('dotnet','classic','agy-autotrain','commonmemory','ghidrust') }
    [pscustomobject]@{ Path='installer/_shared/golden-header-data.iss';    Provable=$true;  Members=@('dotnet','classic','agy-autotrain') }
    [pscustomobject]@{ Path='installer/_shared/register-invoke.iss';       Provable=$true;  Members=@('classic','agy-autotrain','commonmemory','ghidrust') }
    [pscustomobject]@{ Path='installer/_shared/register-plugin-hash.iss';  Provable=$true;  Members=@('classic','agy-autotrain','commonmemory','ghidrust') }
    [pscustomobject]@{ Path='installer/_shared/path-scan.iss';             Provable=$true;  Members=@('classic') }
    [pscustomobject]@{ Path='seed/golden-header.md';                       Provable=$true;  Members=@('dotnet','classic') }
    # Not named by any installer: scripts/generate-scoped-manifest.ps1 reads it and GENERATES each member's
    # scoped 1-entry marketplace.json, so an edit here changes what every member ships.
    [pscustomobject]@{ Path='build/members.json';                          Provable=$false; Members=@('dotnet','classic','agy-autotrain','commonmemory','ghidrust') }
)
function Get-SharedPaths { $script:SharedPaths }

# Shared paths that ship into member $Key (its extra release pathspecs).
function Get-SharedPathsFor([string]$Key) {
    @($script:SharedPaths | Where-Object { $Key -in $_.Members } | ForEach-Object { $_.Path })
}

# Deliberately versionless: developer/CI surface that reaches no end-user artifact. Prefixes ending in '/'
# match a subtree; the rest are exact repo-root files. Membership is checked ONLY after member-bound and
# shared-shipping have had their say, so listing a prefix here can never mask a real bump.
$script:DevOnlyPaths = @(
    'scripts/', '.github/', 'docs/', '.claude/', '.vscode/', '.worktrees/',
    '.antigravityignore', '.gitattributes', '.gitignore', '.mlc.toml',
    'CLAUDE.md', 'CODE_OF_CONDUCT.md', 'CONTRIBUTING.md', 'DevelopersCockpit.ps1',
    'LICENSE', 'NOTICE', 'README.md', 'SECURITY.md', 'justfile', 'lefthook.yml'
)
function Get-DevOnlyPaths { $script:DevOnlyPaths }

function Test-DevOnlyPath([string]$Path) {
    $p = $Path -replace '\\', '/'
    foreach ($d in $script:DevOnlyPaths) {
        if ($d.EndsWith('/')) { if ($p.StartsWith($d)) { return $true } }
        elseif ($p -eq $d)    { return $true }
    }
    return $false
}

# Classify one tracked path. Returns 'member' | 'shared' | 'dev-only' | 'unclassified'.
function Get-PathBucket([string]$Path) {
    $p = $Path -replace '\\', '/'
    foreach ($m in Get-Members) { if ($p.StartsWith(($m.Root + '/'))) { return 'member' } }
    foreach ($s in $script:SharedPaths) { if ($p -eq $s.Path) { return 'shared' } }
    if (Test-DevOnlyPath $p) { return 'dev-only' }
    return 'unclassified'
}

# The AUDITOR for $SharedPaths — the "prove" half of declare+prove, mirroring Assert-RosterMatchesMembers.
# Two independent failures:
#   COVERAGE  every tracked file under a shared asset root must be declared. Catches a NEW shared file that
#             would otherwise be unclassified-at-release-time (loud, but late).
#   USAGE     for each Provable entry, the declared member set must EQUAL the set derived by searching the
#             asset's literal BASENAME across each member's own installer sources. Catches the real rot: a
#             member starts (or stops) using a shared asset and nobody updates the table.
# Basename search, deliberately NOT an Inno parser: `#include`, `Source:` and a runtime invocation are three
# different syntaxes for the same dependency, and a parser that understands only the first is how
# register-plugin.ps1 came to belong to nobody. It over-matches — naming a shared file in a COMMENT counts
# as a dependency — which errs toward over-bumping (safe) and is fixed by not name-dropping shared files in
# member installers. Known blind spot: a wildcard Source: (`_shared\*.ps1`) names no basename, so shared
# assets must be shipped by explicit filename.
function Assert-SharedMapHealthy([string]$RepoRoot) {
    $problems = @()
    $roots = @('installer/_shared', 'seed')

    $tracked = @(git -C $RepoRoot ls-files -- @roots | ForEach-Object { $_.Trim() -replace '\\', '/' } | Where-Object { $_ })
    if ($tracked.Count -eq 0) { throw "check-shared-map: found no tracked files under $($roots -join ', ') - wrong -RepoRoot?" }
    $declared = @($script:SharedPaths | ForEach-Object { $_.Path })
    foreach ($f in $tracked) {
        if ($f -notin $declared) { $problems += "shared asset '$f' is not declared in `$SharedPaths (add it with the members that ship it)" }
    }
    foreach ($d in $declared) {
        if (-not (Test-Path (Join-Path $RepoRoot $d))) { $problems += "declared shared path '$d' does not exist (renamed or removed? update `$SharedPaths)" }
    }

    foreach ($s in ($script:SharedPaths | Where-Object { $_.Provable })) {
        $base = Split-Path $s.Path -Leaf
        $derived = @()
        foreach ($m in Get-Members) {
            $dir = Join-Path $RepoRoot (Join-Path $m.Root 'installer')
            if (-not (Test-Path $dir)) { continue }
            # Text sources only. An installer folder legitimately holds binaries (.ico/.exe/.dll) and
            # slurping one with Get-Content -Raw is at best slow and at worst an encoding throw — so a
            # binary would fail the gate for a reason having nothing to do with the map. Shared assets are
            # declared in .iss (#include / Source:) or invoked from .ps1; nothing else declares one.
            $hit = @(Get-ChildItem -Path $dir -Recurse -File -Include '*.iss','*.ps1' | Where-Object {
                (Get-Content -Raw -LiteralPath $_.FullName) -like ('*' + $base + '*')
            })
            if ($hit.Count) { $derived += $m.Key }
        }
        $extra   = @($s.Members | Where-Object { $_ -notin $derived })
        $missing = @($derived   | Where-Object { $_ -notin $s.Members })
        if ($extra.Count)   { $problems += "'$($s.Path)': declared for [$($extra -join ', ')] but no installer source names it - stale entry, or the member dropped it" }
        if ($missing.Count) { $problems += "'$($s.Path)': [$($missing -join ', ')] name it in their installer but are NOT declared - they would silently miss this bump" }
    }

    if ($problems.Count) { throw ("check-shared-map: the shared-path map disagrees with the members' installers.`n  " + ($problems -join "`n  ")) }
}

# Baseline = last `chore(release): clavity-v*` commit (subject-anchored). --basic-regexp forces BRE
# regardless of the user's grep.patternType (^ anchors to line start; () are literal) — FI1'.
# Match INSIDE the ForEach so $Matches is set in the same scope it is read (plan-review R1: relying on
# $Matches leaking from a Where-Object into a downstream ForEach-Object is unreliable under StrictMode).
# All git calls take an explicit $RepoRoot and use `git -C $RepoRoot` (agy-reviewed fix C, 2026-07-13):
# the engine must never split its dependencies (file reads anchored to one repo, git sweep to cwd). Every
# git op here targets the SAME repo the caller passes, so file reads and history can't diverge — and a
# Pester test can point the whole engine at a throwaway repo via `-RepoRoot $TempRepo`.
function Get-Serials([string]$RepoRoot) {
    git -C $RepoRoot tag --list 'clavity-v*' | ForEach-Object { if ($_ -match '^clavity-v([0-9]+)$') { [int]$Matches[1] } }
}

function Get-BaselineSha([string]$RepoRoot) {
    $sha = git -C $RepoRoot log --basic-regexp --grep='^chore(release): clavity-v' -n1 --format=%H 2>$null
    if ($LASTEXITCODE -eq 0 -and $sha) { return $sha.Trim() }
    # bootstrap: last existing clavity-v* tag's commit, else '' (root — all history)
    $serials = @(Get-Serials $RepoRoot)
    if ($serials.Count -gt 0) {
        $maxTag = 'clavity-v' + ($serials | Measure-Object -Maximum).Maximum
        return (git -C $RepoRoot rev-list -n1 $maxTag).Trim()
    }
    return ''
}

# Retracted/abandoned serials — a COMPLETED clavity-v<N> release the maintainer DELETED from origin (tag +
# GitHub release removed to protect users from a broken artifact). Recorded in scripts/release-abandoned.txt
# (one `clavity-v<N>` per line; blank + `#`-comment lines — full-line OR inline — ignored). Two consumers:
# (1) Get-NextSerial unions these so the serial stays BURNED everywhere — a fresh clone has NO local tag to
# prove a retracted serial was ever used, so without this the watermark would silently reset and a burned
# serial could be recomputed and REPUBLISHED (the "ghost-tag" collision); (2) the F17 stuck-release guard
# uses it to tell a deliberate retraction (missing remote tag EXPECTED) apart from a genuinely stuck tag.
function Get-AbandonedSerials([string]$RepoRoot) {
    $f = Join-Path $RepoRoot 'scripts/release-abandoned.txt'
    if (-not (Test-Path $f)) { return @() }
    Get-Content $f | ForEach-Object {
        $line = ($_ -split '#', 2)[0].Trim()   # strip an inline OR full-line comment, then trim
        if ($line -and ($line -match '^clavity-v([0-9]+)$')) { [int]$Matches[1] }
    }
}

# Next serial = max(N over ^clavity-v(N)$ tags AND retracted serials) + 1 (burned serials never reused —
# FI4). Unioning the abandoned list keeps a retracted serial burned even on a fresh clone whose origin has
# no tags (ghost-tag guard). Both sources emit [int]; @()-wrap makes the empty/single-item cases safe.
function Get-NextSerial([string]$RepoRoot) {
    $serials = @(Get-Serials $RepoRoot) + @(Get-AbandonedSerials $RepoRoot)
    if ($serials.Count -eq 0) { return 1 }
    return ((($serials | Measure-Object -Maximum).Maximum) + 1)
}

# One trivial, case-insensitive regex. Breaking = the `!` token on ANY type (F10). F7: (?i).
$script:ConvRe = '(?i)^(?<type>feat|fix|chore|ci|docs|refactor|test|perf|build|style|revert)(?:\((?<scope>[^)]+)\))?(?<bang>!)?:'

function Test-Conventional([string]$subject) { return ($subject -match $script:ConvRe) }

function Get-BumpLevel([string[]]$subjects) {
    $level = 'none'
    foreach ($s in $subjects) {
        if ($s -notmatch $script:ConvRe) { continue }   # non-conventional never raises level (F4)
        $type = $Matches['type'].ToLower()
        # StrictMode-safe: the optional (?<bang>!) group may be absent from $Matches (plan-review R1).
        $bang = $Matches.ContainsKey('bang')
        if ($bang) { return 'breaking' }                # ! wins outright (F10)
        if ($type -eq 'feat' -and $level -ne 'breaking') { $level = 'minor' }
        elseif (($type -eq 'fix' -or $type -eq 'revert') -and $level -eq 'none') { $level = 'patch' }
    }
    return $level
}

function Step-SemverVersion([string]$current, [string]$level) {
    if ($current -notmatch '^(\d+)\.(\d+)\.(\d+)$') { throw "not semver: $current" }
    $maj=[int]$Matches[1]; $min=[int]$Matches[2]; $pat=[int]$Matches[3]
    if ($maj -eq 0) {
        # pre-1.0: breaking degrades to minor so a feat!/breaking never forces 1.0.0 (F3)
        switch ($level) {
            'breaking' { return "0.$($min+1).0" }
            'minor'    { return "0.$($min+1).0" }
            'patch'    { return "0.$min.$($pat+1)" }
            default    { throw "no bump for level '$level'" }
        }
    }
    switch ($level) {
        'breaking' { return "$($maj+1).0.0" }
        'minor'    { return "$maj.$($min+1).0" }
        'patch'    { return "$maj.$min.$($pat+1)" }
        default    { throw "no bump for level '$level'" }
    }
}

function Read-IssVersion([string]$issPath) {
    $c = Get-Content -Raw $issPath
    if ($c -notmatch '#define AppVersion "([^"]+)"') { throw "no #define AppVersion in $issPath" }
    return $Matches[1]
}

function Read-JsonVersion([string]$jsonPath) {
    $c = Get-Content -Raw $jsonPath
    if ($c -notmatch '(?m)^\s*"version"\s*:\s*"([^"]+)"') { throw "no top-level version in $jsonPath" }
    return $Matches[1]
}

function Format-Sanitized([string]$subject) {
    $s = $subject -replace "[`r`n`t]", ' '          # newlines/tabs -> space (one line)
    $s = $s -replace '[\x00-\x1F]', ''               # strip other control chars
    $s = $s -replace '\|', '\|'                       # escape markdown table pipe
    if ($s.StartsWith('<')) { $s = '&lt;' + $s.Substring(1) }  # neutralize a leading HTML/comment opener
    return $s.Trim()
}

function Group-Notes([string[]]$subjects) {
    $breaking=@(); $features=@(); $fixes=@()
    foreach ($s in $subjects) {
        if ($s -notmatch $script:ConvRe) { continue }
        $type=$Matches['type'].ToLower(); $bang=$Matches.ContainsKey('bang')   # StrictMode-safe (plan-review R1)
        $clean = Format-Sanitized $s
        if ($bang) { $breaking += $clean }
        elseif ($type -eq 'feat') { $features += $clean }
        elseif ($type -eq 'fix' -or $type -eq 'revert') { $fixes += $clean }
    }
    return [pscustomobject]@{ Breaking=$breaking; Features=$features; Fixes=$fixes }
}

# Exhaustive split (F2): ghidrust/plugin/** = plugin; ANY other ghidrust/ path = binary.
function Get-GhidrustChannel([string]$path) {
    $p = $path -replace '\\', '/'
    if ($p -like 'ghidrust/plugin/*') { return 'plugin' }
    if ($p -like 'ghidrust/*')        { return 'binary' }
    return $null
}

# For a ghidrust channel, return {Sha, Subject} for commits in $Range that touch that channel's paths.
# Sha (not just the subject) so the caller can UNION this with the shared-path sweep and de-duplicate a
# commit that touches both, without two same-subject commits collapsing into one.
function Get-ChannelRecords([string]$Range, [string]$Channel, [string]$RepoRoot) {
    # MUST Out-String first (plan-review R1): git log is a string[]; splitting the array on the %x1e record
    # separator directly detaches each commit's subject from its following --name-only file lines, so the
    # channel attribution silently finds no files and ghidrust never bumps. Join to one string first.
    $raw = (git -C $RepoRoot log $Range --format='%x1e%H%x1f%s%x00' --name-only -- 'ghidrust/' 2>$null | Out-String)
    if (-not $raw) { return @() }
    $records = @()
    foreach ($rec in ($raw -split "`u{1e}" | Where-Object { $_ -ne '' })) {
        $parts = $rec -split "`0", 2
        $head  = $parts[0] -split "`u{1f}", 2
        if ($head.Count -lt 2) { continue }
        $sha = $head[0].Trim(); $subject = $head[1].Trim()
        $files = @()
        if ($parts.Count -gt 1) { $files = @($parts[1] -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) }
        foreach ($f in $files) {
            if ((Get-GhidrustChannel $f) -eq $Channel) { $records += [pscustomobject]@{ Sha=$sha; Subject=$subject }; break }
        }
    }
    return $records
}

# CC2 drift gate (option C): the release roster ($Members.Marketplace) MUST equal, as a SET, the member
# names in build/members.json. Bidirectional — any element in exactly one side fails. Keeps the two
# schemas decoupled while making a forgotten registration a RED build, not a silent un-versioned ship.
function Assert-RosterMatchesMembers([string]$MembersJsonPath) {
    if (-not (Test-Path $MembersJsonPath)) { throw "check-roster: members.json not found: $MembersJsonPath" }
    # Uniqueness guard (agy, goal-framed consult 2026-07-12): the set-equality gate below proves the member
    # SET matches, but a copy-paste 6th row that satisfies name-equality while duplicating another row's
    # Key/Root/Marketplace would bump the WRONG member's version. Assert every identifier is distinct first.
    foreach ($field in 'Key','Root','Marketplace') {
        $dupes = @(Get-Members | ForEach-Object { $_.$field } | Group-Object | Where-Object Count -gt 1 | ForEach-Object { $_.Name })
        if ($dupes.Count) { throw "check-roster: duplicate `$Members.$field value(s): $($dupes -join ', ') — every roster row must be distinct." }
    }
    $json = Get-Content -Raw $MembersJsonPath | ConvertFrom-Json
    $manifest = @($json.members | ForEach-Object { $_.name })
    $roster   = @(Get-Members | ForEach-Object { $_.Marketplace })
    $missingFromRoster   = @($manifest | Where-Object { $_ -notin $roster })   # in members.json, not registered for release
    $missingFromManifest = @($roster   | Where-Object { $_ -notin $manifest }) # in release roster, not in the marketplace
    if ($missingFromRoster.Count -or $missingFromManifest.Count) {
        $msg = "check-roster: release roster and build/members.json disagree on the member set."
        if ($missingFromRoster.Count)   { $msg += "`n  in members.json but NOT release-registered (add to `$Members in release-lib.ps1): $($missingFromRoster -join ', ')" }
        if ($missingFromManifest.Count) { $msg += "`n  in the release roster but NOT in members.json (sunset? remove the `$Members row): $($missingFromManifest -join ', ')" }
        throw $msg
    }
}

function Format-ReleaseNotes([object[]]$bumps) {
    $sb = [System.Text.StringBuilder]::new()
    foreach ($b in $bumps) {
        $label = if ($b.Channel) { "$($b.Key) ($($b.Channel))" } else { $b.Key }
        [void]$sb.AppendLine("## $label $($b.Current) -> $($b.Next)")
        foreach ($grp in @('Breaking','Features','Fixes')) {
            $items = $b.Notes.$grp
            if ($items.Count) {
                [void]$sb.AppendLine("### $grp")
                foreach ($i in $items) { [void]$sb.AppendLine("- $i") }
            }
        }
        [void]$sb.AppendLine('')
    }
    return $sb.ToString().TrimEnd()
}

# Prepend a dated section to <root>/CHANGELOG.md (create if absent). $DateStr passed in (scripts may
# stamp time; keep the function pure/testable).
function Update-Changelog([string]$repoRoot, [object]$bump, [string]$dateStr) {
    $path = Join-Path $repoRoot (Join-Path $bump.Root 'CHANGELOG.md')
    $label = if ($bump.Channel) { "$($bump.Key) ($($bump.Channel))" } else { $bump.Key }
    $section = "## $($bump.Next) — $dateStr`n`n"
    foreach ($grp in @('Breaking','Features','Fixes')) {
        $items = $bump.Notes.$grp
        if ($items.Count) { $section += "### $grp`n"; foreach ($i in $items) { $section += "- $i`n" }; $section += "`n" }
    }
    # Fallback H1 uses the member KEY, not $label — a ghidrust CHANGELOG is shared by both channels, so a
    # channel-specific title ('# ghidrust (binary) changelog') would be permanently wrong (plan-review R2).
    $existing = if (Test-Path $path) { Get-Content -Raw $path } else { "# $($bump.Key) changelog`n`n" }
    # Inject AFTER the H1 title, not above it (plan-review R1: blind prepend pushes the `# … changelog`
    # heading further down on every release).
    if ($existing -match '(?s)^(#[^\n]*\n+)(.*)$') { $out = $Matches[1] + $section + $Matches[2] }
    else                                          { $out = $section + $existing }
    Set-Content -Path $path -Value $out -NoNewline
    return $path
}

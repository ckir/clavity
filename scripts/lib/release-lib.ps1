Set-StrictMode -Version Latest

# Explicit roster — do NOT derive from build/members.json (its source is the plugin subdir, name is the
# marketplace name). `Marketplace` = the member's `name` in build/members.json (the marketplace manifest).
# It is the ONLY cross-reference between this release-tooling roster and members.json, consumed by the CC2
# drift gate (Task 6b) — a strict bidirectional set-equality check that fails the build if this table and
# members.json ever disagree on the member set. This decoupled-schemas + proving-gate approach
# (owner-ratified 2026-07-12, agy-negotiated) honors spec CC2's INTENT (no silent un-versioned member)
# WITHOUT moving release-internal build paths (Root/VerFile) into the marketplace manifest.
#
# CANONICAL CURRENT-VERSION READ: `VerFile` + `VerKind` ('iss' | 'json'). Was `Iss` for every member, but
# the Inno-retirement migration (2026-09-14) removed the .iss for clavity-dotnet, agy-autotrain and
# commonmemory — those three install via `claude plugin` and their version truth lives in plugin.json.
# clavity-classic is now the ONLY member that keeps its .iss (still Inno).
# ghidrust was RETIRED from this monorepo (2026-09-14, full retirement — superseded by re-ghidra-mcp-cc in
# ckir/aiplugins); it was the only dual-channel member, so the channel machinery below went with it.
$script:Members = @(
    [pscustomobject]@{ Key='dotnet';        Marketplace='clavity-dotnet';  Root='clavity-dotnet';  VerFile='clavity-dotnet/plugin/plugin.json';         VerKind='json'; Ghidrust=$false }
    [pscustomobject]@{ Key='classic';       Marketplace='clavity-classic'; Root='clavity-classic'; VerFile='clavity-classic/installer/clavity-classic.iss'; VerKind='iss';  Ghidrust=$false }
    [pscustomobject]@{ Key='agy-autotrain'; Marketplace='agy-autotrain';   Root='agy-autotrain';   VerFile='agy-autotrain/plugin.json';                 VerKind='json'; Ghidrust=$false }
    [pscustomobject]@{ Key='commonmemory';  Marketplace='commonmemory';    Root='commonmemory';    VerFile='commonmemory/plugin.json';                  VerKind='json'; Ghidrust=$false }
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
# Provable=$false marks an asset member installers never name literally, so the grep auditor cannot see it;
# each carries its own justification and is covered instead by the coverage half of the gate.
# After the Inno-retirement (dotnet/agy-autotrain/commonmemory) AND the ghidrust full retirement (both
# 2026-09-14), clavity-classic is the ONLY member with an installer/ tree, so every provable installer
# asset below ships into classic alone; the derivation greps only classic's installer and agrees.
# `seed/golden-header.md` is the exception: clavity-dotnet still ships it, but via its PLUGIN seed copy
# (clavity-dotnet/plugin/seed/golden-header.md, kept byte-equal by the seed-drift gate) rather than an
# installer, so no installer source names it for dotnet — hence Provable=$false with a hand-declared set,
# mirroring build/members.json.
$script:SharedPaths = @(
    [pscustomobject]@{ Path='installer/_shared/claude-running.iss';        Provable=$true;  Members=@('classic') }
    [pscustomobject]@{ Path='installer/_shared/register-plugin.ps1';       Provable=$true;  Members=@('classic') }
    [pscustomobject]@{ Path='installer/_shared/golden-header-data.iss';    Provable=$true;  Members=@('classic') }
    [pscustomobject]@{ Path='installer/_shared/register-invoke.iss';       Provable=$true;  Members=@('classic') }
    [pscustomobject]@{ Path='installer/_shared/register-plugin-hash.iss';  Provable=$true;  Members=@('classic') }
    [pscustomobject]@{ Path='installer/_shared/path-scan.iss';             Provable=$true;  Members=@('classic') }
    [pscustomobject]@{ Path='installer/_shared/user-path.iss';             Provable=$true;  Members=@('classic') }
    # dotnet ships the seed via its plugin copy (not an installer), so it is not installer-derivable — hand-declared.
    [pscustomobject]@{ Path='seed/golden-header.md';                       Provable=$false; Members=@('dotnet','classic') }
    # Not named by any installer: scripts/generate-scoped-manifest.ps1 reads it and GENERATES clavity-classic's
    # scoped 1-entry marketplace.json, so an edit here changes what classic ships. The three `claude plugin`
    # members install from the ROOT .claude-plugin/marketplace.json (hand-written), not from a
    # members.json-generated manifest, so a members.json edit does not change what they ship.
    [pscustomobject]@{ Path='build/members.json';                          Provable=$false; Members=@('classic') }
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
    'LICENSE', 'NOTICE', 'README.md', 'SECURITY.md', 'justfile', 'lefthook.yml',
    # Inno-retirement (2026-09-14). '.claude-plugin/' is the repo-ROOT marketplace that
    # `claude plugin marketplace add ckir/clavity` fetches LIVE from the repo (not a released asset), so a
    # change to it needs no member version bump - the members' versions live in their own plugin.json. Member
    # `.claude-plugin/` dirs are under a member Root and are matched member-bound FIRST, so this prefix only
    # ever catches the root one. 'archive/' holds retired Inno installer snapshots (revert points, shipped to
    # nobody). 'BundleCodeBase.ps1' is a dev tool that bundles the repo for the agy peer.
    '.claude-plugin/', 'archive/', 'BundleCodeBase.ps1'
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

# (Get-GhidrustChannel / Get-ChannelRecords were removed 2026-09-14 with the ghidrust full retirement —
# ghidrust was the only dual-channel member, so per-channel commit attribution is no longer needed.)

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
    # ASCII hyphen, NOT an em dash: agy-autotrain/ and commonmemory/ ship their CHANGELOG.md inside the
    # injected-context domain, which is gated to pure ASCII. The em dash this used to emit re-broke that
    # gate on every release (b2a6cc0 sanitised the files; clavity-v18 put it straight back). Pinned by
    # release-lib.Tests.ps1 'emits a pure-ASCII section'.
    $section = "## $($bump.Next) - $dateStr`n`n"
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

# --- Resume support (release.ps1 -Resume) -------------------------------------------------------
# release.ps1 COMMITS the bumps + CHANGELOG entries BEFORE it gates, so a failed pre-flight strands a
# `chore(release)` commit on main: unpushed, untagged, and blocking every further run via the
# dangling-candidate precondition. -Resume clears that state.
#
# It RE-PREPARES rather than continues. The candidate is DROPPED and the normal compute -> preview ->
# confirm -> bump -> commit -> pre-flight -> push path runs again from scratch. Two reasons, both
# load-bearing:
#   1. The tree CHANGED when the developer committed the fix, so every gate that passed before the fix
#      is stale. Skipping the passed prefix would tag a tree no complete pre-flight ever saw.
#   2. Continuing would ship a CHANGELOG generated before the fix commits existed, permanently omitting
#      commits that are inside the tag - and a fix commit that happens to be a `feat:` or carry `!`
#      would leave the semver bump silently wrong.
# The cost is honest and is NOT a bug: -Resume re-runs the whole pre-flight. There is no fast path,
# because a fast path is only sound for a tree that has not changed, and the tree always has.

# The single reader of the dangling-candidate condition. release.ps1's precondition calls this too, so
# the gate and the resume path can never disagree about what counts as a half-finished release.
# --basic-regexp is explicit rather than defaulted: `^chore(release):` is a literal only under BRE, and
# a user with `grep.patternType=extended` configured would otherwise silently read `(release)` as a
# capture group and match `chore:` alone.
function Get-DanglingReleaseCommits([string]$RepoRoot) {
    # PICK THE RANGE, rather than assuming origin/main exists. AGY-TEST-AUDIT 2026-09-22 MEASURED the
    # original hole: with `main` never pushed, `origin/main` does not resolve, `git log origin/main..HEAD`
    # exits 128 writing NOTHING to stdout, so this returned an EMPTY array while a stranded
    # `chore(release)` sat on HEAD - the gate FAILED OPEN and Test-ResumeState answered "there is no
    # half-finished release to resume", confidently wrong.
    #
    # AGY-CAPSTONE round 3 then caught the FIX's own edge: simply refusing on a non-zero exit blocks a
    # VIRGIN repo's FIRST release, which is a supported scenario - `Get-BaselineSha` carries an explicit
    # bootstrap arm returning '' for "no prior release", and `origin/main` appears nowhere else in the
    # flow. So refusing there is a FALSE REFUSAL, not safety.
    #
    # Both answers were wrong because both assumed the question was "did git fail?". The real question is
    # WHICH COMMITS ARE UNPUSHED. If origin/main does not resolve then NOTHING is pushed, so the unpushed
    # set is the whole of HEAD's history - which correctly yields zero candidates for a first release AND
    # correctly catches a candidate stranded by a push that never landed. One range change answers both.
    # AGY-CAPSTONE round 4 found the round-3 fold's own edge, and it was DESTRUCTIVE. Falling back to
    # `HEAD` whenever the tracking ref is missing assumes "no origin/main => nothing was ever pushed".
    # That implication is FALSE: the ref also goes missing when the remote branch is deleted and pruned,
    # when the remote is renamed, and in some shallow clones. MEASURED 2026-09-22 in exactly that state -
    # a SHIPPED release was reported as a dangling candidate and `Test-ResumeState` returned Ok=$true on
    # it, so `-Resume` would have rebased away an already-released commit. Local refs cannot answer
    # "what is pushed"; only the remote can, so when the local answer is unavailable we ASK IT.
    $range = 'origin/main..HEAD'
    & git -C $RepoRoot rev-parse --verify --quiet origin/main *> $null
    if ($LASTEXITCODE -ne 0) {
        $remoteMain = & git -C $RepoRoot ls-remote --heads origin main 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Get-DanglingReleaseCommits: origin/main is not present locally and 'git ls-remote origin' failed (exit $LASTEXITCODE) in '$RepoRoot' - cannot tell which commits are already pushed. Fix the remote, or run git fetch origin, and re-run."
        }
        if ($remoteMain) {
            # The remote HAS main; our local view of it is just stale. Refusing is the only safe answer:
            # scanning all of HEAD here is what marked a shipped release droppable.
            throw "Get-DanglingReleaseCommits: origin/main exists on the remote but not locally (pruned, renamed or a shallow clone) in '$RepoRoot' - cannot tell which commits are already pushed without it. Run: git fetch origin"
        }
        # The remote genuinely has no main, so nothing has ever been pushed and the unpushed set is all
        # of HEAD. This keeps a VIRGIN repo's FIRST release working (round 3's finding) while still
        # catching a candidate stranded by a push that never landed.
        $range = 'HEAD'
    }

    # stderr is deliberately NOT redirected: git's own `fatal:` line is the only diagnostic that can
    # explain a failure this function did not anticipate, and an earlier revision of this fix silenced it
    # while throwing a hardcoded guess about origin/main - which round 3 flagged as making any OTHER
    # failure undiagnosable in the field.
    $out = @(& git -C $RepoRoot log $range --basic-regexp --grep='^chore(release):' --format=%H)
    if ($LASTEXITCODE -ne 0) {
        # Reached only when the range RESOLVED and git still failed (corruption, an unreadable object, a
        # hostile config). Genuinely undetermined, so fail CLOSED: the caller must never read "I could
        # not tell" as "there is nothing there". No cause is named here on purpose - git already printed
        # the real one above, and guessing would send the reader down the wrong path.
        throw "Get-DanglingReleaseCommits: 'git log $range' failed (exit $LASTEXITCODE) in '$RepoRoot' - cannot tell whether a half-finished release exists. See git's error above."
    }
    $out | Where-Object { $_ } | ForEach-Object { $_.Trim() }
}

# Structured, side-effect-free verdict on whether -Resume may proceed. Returns Ok/Sha/Problems so the
# orchestrator prints and dies, and the tests can assert on the reasons rather than on exit codes.
function Test-ResumeState([string]$RepoRoot) {
    $problems = @()

    # BOTH halves of "clean". A drop that runs over uncommitted work destroys it, and that is not
    # hypothetical: during the 2026-09-22 v20 recovery a hand-run `git reset --hard HEAD~1` would have
    # eaten the very ROADMAP fix the release was being re-run for, had it not been stashed first.
    & git -C $RepoRoot diff --quiet;        $unstaged = ($LASTEXITCODE -ne 0)
    & git -C $RepoRoot diff --cached --quiet; $staged = ($LASTEXITCODE -ne 0)
    if ($unstaged -or $staged) {
        $problems += 'working tree has uncommitted tracked changes - commit or stash them first (dropping the candidate would destroy them)'
    }

    $dangling = @(Get-DanglingReleaseCommits $RepoRoot)
    if ($dangling.Count -eq 0) {
        $problems += 'no un-pushed chore(release) commit in origin/main..HEAD - there is no half-finished release to resume'
    } elseif ($dangling.Count -gt 1) {
        # Never guess. Dropping the wrong candidate rewrites history the developer meant to keep.
        $problems += "found $($dangling.Count) un-pushed chore(release) commits - refusing to guess which to drop: $($dangling -join ', ')"
    }

    [pscustomobject]@{
        Ok       = ($problems.Count -eq 0)
        Sha      = $(if ($dangling.Count -eq 1) { $dangling[0] } else { $null })
        Problems = $problems
    }
}

# Predict a replay conflict WITHOUT touching the tree.
#
# THIS IS THE GUARD THAT MAKES -Resume SAFE. A `git rebase` that halts mid-way leaves a DETACHED HEAD
# with an unresolved index - a strictly WORSE state than the stable dangling commit the flag was called
# to clear, because ordinary git operations then refuse until the developer aborts by hand.
# MEASURED 2026-09-22 on git 2.55.0: dropping a release candidate underneath a fix commit that also
# edited CHANGELOG.md left exactly that ("HEAD detached", "UU CHANGELOG.md").
# `git merge-tree --write-tree` answers the same question as a pure computation. Verified BOTH ways on
# that date - exit 1 on the conflicting case, exit 0 on a control whose fix touched an unrelated file -
# because an oracle that cannot return its failing answer is not an oracle.
#
# Returns 'clean' | 'conflict' | 'unknown'. It FAILS CLOSED: any exit code that is not a definite 0 or 1
# reports 'unknown', and the caller must refuse on that too. A guard that treats "I could not tell" as
# "fine" certifies precisely what it stopped checking.
function Get-DropConflictStatus([string]$RepoRoot, [string]$Sha) {
    $head = (& git -C $RepoRoot rev-parse HEAD 2>$null)
    $cand = (& git -C $RepoRoot rev-parse $Sha  2>$null)
    if (-not $head -or -not $cand) { return 'unknown' }
    # The candidate IS the tip: nothing replays over it, so no conflict is reachable.
    if ($head.Trim() -eq $cand.Trim()) { return 'clean' }
    # The try/catch is not decoration. This function reads $LASTEXITCODE, and whether a native command
    # SETS that or THROWS depends on $PSNativeCommandUseErrorActionPreference, which is a per-session
    # preference rather than a property of the code: with it $true under $ErrorActionPreference='Stop'
    # (release.ps1 sets Stop at :5), merge-tree's exit 1 becomes a terminating error and the switch below
    # is never reached. MEASURED 2026-09-22 on pwsh 7.6.6: the preference is False here and exit 1 is
    # readable - but that is this machine's default today, not a contract, so catching keeps the verdict
    # 'unknown' (which the caller REFUSES on) instead of letting the whole release abort on a throw.
    try {
        & git -C $RepoRoot merge-tree --write-tree --merge-base=$Sha "$Sha^" HEAD *> $null
    } catch {
        return 'unknown'
    }
    switch ($LASTEXITCODE) {
        0       { return 'clean' }
        1       { return 'conflict' }
        default { return 'unknown' }
    }
}

# Drop the candidate, preserving every commit made after it. Returns $true on success.
# On the tip case a reset suffices; otherwise `rebase --onto <sha>^ <sha>` replays the fix commits onto
# the candidate's parent. Prediction is not proof - merge-tree and rebase are different algorithms - so
# a failure here ABORTS the rebase rather than leaving the detached-HEAD state described above.
function Invoke-DropReleaseCandidate([string]$RepoRoot, [string]$Sha) {
    $head = (& git -C $RepoRoot rev-parse HEAD).Trim()
    $cand = (& git -C $RepoRoot rev-parse $Sha).Trim()
    if ($head -eq $cand) {
        & git -C $RepoRoot reset --hard "$Sha^" *> $null
        return ($LASTEXITCODE -eq 0)
    }
    # --rebase-merges is REQUIRED, not a preference. AGY-CAPSTONE round 1 (2026-09-22, State Corruptor
    # seat) found that a PLAIN `rebase --onto` silently DROPS merge commits and replays their parents
    # linearly, so recovering a release whose fix arrived as a merged branch would quietly rewrite the
    # maintainer's topology. MEASURED on git 2.55.0, dropping a candidate under a `--no-ff` merge:
    # plain    -> 4 commits/1 merge became 2 commits/0 merges (topology destroyed)
    # --rebase-merges -> 4 commits/1 merge became 3 commits/1 merge (release commit dropped, merge kept)
    # It is a strict superset, which is why it is applied unconditionally rather than only when a merge
    # is detected: MEASURED on the ordinary linear replay it behaves identically (exit 0, fix commit
    # kept, bump dropped), and on a conflicting replay it still exits non-zero with the abort below
    # restoring `main` clean. `main` carries merge commits in this repo, so this is reachable, not exotic.
    & git -C $RepoRoot rebase --rebase-merges --onto "$Sha^" $Sha *> $null
    if ($LASTEXITCODE -ne 0) {
        # Reached when the PREDICTION above said 'clean' and the replay disagreed anyway - the two run
        # different algorithms, and merge-tree compares only the FINAL trees. MEASURED: a fix SEQUENCE
        # whose intermediate commit conflicts with the candidate's parent, but whose final tree matches
        # it, is predicted clean and then halts the replay. That is EXPECTED and is why this abort is
        # the real safety net rather than the prediction: verified through this function, the caller
        # gets $false with HEAD restored, still on main, no rebase in progress and a clean tree.
        & git -C $RepoRoot rebase --abort *> $null
        return $false
    }
    return $true
}

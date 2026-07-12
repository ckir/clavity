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

# Next serial = max(N over ^clavity-v(N)$ tags) + 1 (burned serials never reused — FI4).
function Get-NextSerial([string]$RepoRoot) {
    $serials = @(Get-Serials $RepoRoot)
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

# For a ghidrust channel, return subjects of commits in $Range that touch that channel's paths.
function Get-ChannelSubjects([string]$Range, [string]$Channel, [string]$RepoRoot) {
    # MUST Out-String first (plan-review R1): git log is a string[]; splitting the array on the %x1e record
    # separator directly detaches each commit's subject from its following --name-only file lines, so the
    # channel attribution silently finds no files and ghidrust never bumps. Join to one string first.
    $raw = (git -C $RepoRoot log $Range --format='%x1e%s%x00' --name-only -- 'ghidrust/' 2>$null | Out-String)
    if (-not $raw) { return @() }
    $subjects = @()
    foreach ($rec in ($raw -split "`u{1e}" | Where-Object { $_ -ne '' })) {
        $parts = $rec -split "`0", 2
        $subject = $parts[0].Trim()
        $files = @()
        if ($parts.Count -gt 1) { $files = @($parts[1] -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) }
        foreach ($f in $files) { if ((Get-GhidrustChannel $f) -eq $Channel) { $subjects += $subject; break } }
    }
    return $subjects
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

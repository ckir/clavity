<#
.SYNOPSIS
  Audits every file this repository injects into a user's AI-agent context.
.DESCRIPTION
  Discovery is SUBTRACTIVE: walk the domain roots, subtract an explicit ignorelist. An additive
  role-matcher would be an allowlist of globs, which is the exact defect this gate exists to remove
  (see scripts/check-agy-discipline-skills.ps1:13 for the drift it caused there).
.PARAMETER RepoRoot
  Repository root. Defaults to the parent of this script's directory.
.PARAMETER WhatIf
  Read-only checker; accepted and ignored, for parity with the repo's other scripts.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RepoRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }

# Owner ruling 2026-08-08 (spec 6.1): every product, none excluded. WIDENED by owner ruling 2026-08-09
# after this list was measured to be exactly the defect the gate exists to remove - a product-level
# ALLOWLIST. Repo-wide there were 21 SKILL.md; 18 sat inside a root and 3 did not, and all 3 were
# injected context: two are include_str!'d into shipping binaries (ghidrust/skill/SKILL.md via
# skill_asset.rs:10, agy_skills/claudavity-responder/SKILL.md via clavity-classic/src/main.rs:29) and
# agy-mcp-bridge/SKILL.md is a headless sub-agent's system prompt.
#
# It was NOT this gate that found them. Sanitising the plugin copy of the responder skill turned
# check-seed-artifacts-synced.sh red, because its pinned mirror in agy_skills/ was invisible here. A
# sibling checker caught what this one structurally could not see - which is why the completeness of
# THIS list is now itself pinned by a test (check-injected-context.Tests.ps1, 'domain coverage').
# THE TWIN PLUGIN TREES, NAMED ONCE. This pair was hardcoded in THREE places - this list,
# Expand-ExemptionPath's literal prefixes, and Get-ReferenceIndex's canonicalisation regex - and the
# duplication was reachable, not theoretical: Get-InjectedContextFiles tells a maintainer "if a product
# moved or was renamed, update $script:DomainRoots", and doing exactly that left the other two copies
# pointing at a path that no longer exists. Since the gate now THROWS on a missing exemption path, a
# maintainer following the instruction in the error message would have taken CI down. Derive, never
# restate: renaming a tree here is now sufficient.
$script:TwinPluginRoots = @('clavity-dotnet/plugin', 'clavity-classic/plugin')
# Built from that one list so the canonicaliser cannot drift from it either.
$script:TwinCanonRx = '^(?:' + (($script:TwinPluginRoots | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')/'

$script:DomainRoots = @(
    $script:TwinPluginRoots
    'clavity-classic/agy_skills'
    'clavity-classic/agy-mcp-bridge'
    'seed'
    'agy-autotrain'
    'ghidrust/plugin'
    'ghidrust/skill'
    'commonmemory'
)

# PRUNING IS RELATIVE TO THE REPOSITORY ROOT, NEVER ABSOLUTE - and that is a fix, not a preference.
# MEASURED 2026-08-09: both walks matched these segments against $_.FullName, the ABSOLUTE path. Clone
# this repository anywhere under a directory called target/, bin/, obj/, dist/ or the like - a CI
# workspace, C:/Projects/target/, anything - and EVERY file's absolute path contains a pruned segment, so
# the whole corpus is dropped. Probed: corpus 0, violations 0, and the gate printed OK over a file with a
# real U+2014 in it. A silent false GREEN in the gate whose entire purpose is to stop silent false GREENs.
# Anchoring to the relative path makes the check depend only on the repository's own shape.
#
# One list, one regex, both walks. The two sites previously carried DIFFERENT segment lists; the union is
# used here because dist/ and publish/ are already ignorelisted for the corpus, so folding them in changes
# nothing there - verified by comparing corpus and index counts before and after.
# THIS LIST NOW SERVES THE REFERENCE INDEX ONLY. The corpus walk stopped pruning in round 10, because
# matching a segment NAME at any depth was itself the bypass - see Get-InjectedContextFiles. What is left
# here is the whole-repository walk in Get-ReferenceIndex, whose results are resolved against and never
# audited, so a name-based skip there is safe and keeps it cheap.
# MEASURED 2026-08-09: skipping these removed 3188 files from a domain-root walk, essentially all of them
# the Python virtualenv under clavity-classic/agy-mcp-bridge/.venv/ - which is why the corpus walk could
# not simply enumerate everything either, and instead skips DESCENT where an anchored glob already
# subtracts the whole directory.
# (An earlier version of this comment said pruning "cannot simply be dropped from the corpus walk" and
# that the bypass was therefore closed by a coverage assertion. Round 10 dropped it and round 14 caught
# the comment still asserting the reversed decision.)
# The three cache directories were added after a measurement found .ruff_cache/CACHEDIR.TAG sitting in the
# audited corpus: tool caches are untracked local junk, so leaving them in made the corpus differ between
# machines and the gate non-reproducible across clones.
# .worktrees is NOT build output, and it is here for the reference index specifically. A git worktree is a
# COMPLETE SECOND COPY of the repository, so without this every indexed file has a twin and
# Resolve-Reference stops returning 'ok'. MEASURED 2026-08-10, capstone round 17: with a worktree present,
# 'a mirrored plugin file PASSES - the twin trees canonicalise to one logical path' returned 'ambiguous'.
#
# THE REAL DANGER IS NOT THE AMBIGUOUS OUTCOME, IT IS A FAIL-OPEN. Test-ReferenceFails counts only
# 'broken' and 'unclassified', so a reference whose target was DELETED from the primary tree can still
# match the copy inside the worktree, come back ambiguous instead of broken, and PASS. The gate would go
# green over a dangling pointer - the exact class the reference invariant exists to catch. Subtracting
# .worktrees/** in the ignorelist does not reach this: that governs the corpus, and the reference index
# is a whole-repository walk pruned by NAME.
$script:PrunedSegments = @('.git','node_modules','target','bin','obj','.venv','__pycache__','dist','publish','.vs',
                           '.ruff_cache','.pytest_cache','.mypy_cache','.worktrees')
# Non-capturing throughout: this regex is only used with -match today, but a capturing group in a regex
# later handed to -split silently shifts every index, which cost a round-3 fix its correctness.
# THE TRAILING '/' IS REQUIRED, NOT OPTIONAL. These are FILE paths, so a pruned segment is always a
# DIRECTORY and always has a separator after it. An earlier '(?:/|$)' also matched END-OF-STRING, which
# pruned a FILE merely NAMED dist, bin or target - measured, seed/dist came back pruned=True. That was a
# regression introduced by the fix for the absolute-path defect, in the very line that fixed it.
$script:PruneRx = '(?:^|/)(?:' + (($script:PrunedSegments | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')/'

function Test-IsPrunedPath {
    param([string]$RelPath)
    [bool]($RelPath -match $script:PruneRx)
}

function Test-IsBuildDirName {
    param([string]$Name)
    [bool]($Name -in $script:PrunedSegments)
}

# The identity a walk dedupes on. BOTH walks below descend with a manual stack and neither had any guard
# against re-visiting, so a directory junction pointing at an ancestor walked forever - MEASURED with a
# real `mklink /J` loop: a naive stack walk over a two-directory tree was still going after 12 pops, and
# `Get-ChildItem -Force` hands back the junction as a container with the ReparsePoint attribute set, so
# nothing stopped it being pushed. Reachability in THIS repository is currently nil (measured: zero
# reparse points, and `node_modules`/`.venv` - the obvious sources - are pruned before the push), so this
# is a termination guarantee against a latent hang, not a fix for a live failure.
#
# RESOLVING THE TARGET IS THE WHOLE POINT. Deduping on FullName alone does NOT terminate a cycle, because
# every lap produces a NEW path (root/link/link/link/...). The junction's target is fixed, so keying on it
# closes the loop on the second visit.
#
# NOT "skip reparse points". That was the obvious fix and it is a FAIL-OPEN: a legitimately linked
# directory inside a domain root would stop being audited while the gate still reported OK - certifying
# content it had quietly stopped reading, which is the exact failure class this gate exists to catch.
# Deduping instead means linked content is audited ONCE and a cycle still terminates.
#
# OrdinalIgnoreCase because Windows paths are case-insensitive; `.Target` is verified present on both
# Windows PowerShell 5.1 and pwsh 7 (measured on a live junction in both).
function Get-WalkIdentity {
    param([System.IO.FileSystemInfo]$Item)
    $p = $Item.FullName
    if ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        $t = @($Item.Target)[0]
        if ($t) { $p = $t }
    }
    $p.TrimEnd('\', '/')
}

function Get-UnexpectedBuildDirs {
    param([string]$RepoRoot)
    # Build output sitting INSIDE shipped plugin content is itself the defect worth reporting. It is not
    # audited (binaries would drown the encoding invariant in noise) and not silently skipped (that was
    # the round-9/10 bypass) - it is named. An intentional one is subtracted by an anchored glob, which is
    # visible in the ignorelist with a reason, exactly like every other subtraction here.
    $RepoRoot = $RepoRoot -replace '[\\/]+$', ''
    $globs = Get-IgnoreGlobs -RepoRoot $RepoRoot
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($root in $script:DomainRoots) {
        $full = Join-Path $RepoRoot $root
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $stack = [System.Collections.Generic.Stack[string]]::new()
        $seen  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $stack.Push($full)
        [void]$seen.Add((Get-WalkIdentity -Item (Get-Item -LiteralPath $full)))
        while ($stack.Count) {
            $dir = $stack.Pop()
            foreach ($child in Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction SilentlyContinue) {
                $rel = $child.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')
                if (Test-IsIgnored -RelPath ($rel + '/__probe__') -Globs $globs) { continue }
                if (Test-IsBuildDirName -Name $child.Name) { $out.Add($rel); continue }
                # HashSet.Add returns false when the identity was already present - the cycle guard.
                if (-not $seen.Add((Get-WalkIdentity -Item $child))) { continue }
                $stack.Push($child.FullName)
            }
        }
    }
    $out.ToArray()
}

function Get-IgnoreGlobs {
    param([string]$RepoRoot)
    $p = Join-Path $RepoRoot 'scripts/injected-context-ignore.txt'
    # -LiteralPath, or a BRACKET in the path is treated as a WILDCARD and this reports the file missing
    # when it is sitting right there. MEASURED 2026-08-09: a repository under a path containing '[1]' died
    # HERE first - before the domain-root check - with "ignorelist missing" naming the file that exists.
    if (-not (Test-Path -LiteralPath $p)) { throw "ignorelist missing: $p" }
    @(Get-Content -LiteralPath $p | Where-Object { $_ -and -not $_.StartsWith('#') })
}

function Test-IsIgnored {
    param([string]$RelPath, [string[]]$Globs)
    foreach ($g in $Globs) {
        # Normalise the glob to a regex: ** -> any depth, * -> one segment.
        $rx = '^' + [regex]::Escape($g).Replace('\*\*/', '(.*/)?').Replace('\*\*', '.*').Replace('\*', '[^/]*') + '$'
        if ($RelPath -match $rx) { return $true }
    }
    return $false
}

function Get-InjectedContextFiles {
    param([string]$RepoRoot)
    # TRIM ANY TRAILING SEPARATOR. $rel is cut with Substring($RepoRoot.Length + 1), so a root passed as
    # 'C:/repo/' - exactly what shell tab-completion produces - is one character too long and swallows the
    # first letter of EVERY relative path. Measured: 'clavity-dotnet/...' came back as 'lavity-dotnet/...',
    # which breaks every ignore glob and every reference resolution at once, turning a tab-completed
    # invocation into a flood of false violations.
    $RepoRoot = $RepoRoot -replace '[\\/]+$', ''
    $globs = Get-IgnoreGlobs -RepoRoot $RepoRoot
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($root in $script:DomainRoots) {
        $full = Join-Path $RepoRoot $root
        # THROW, never `continue`. A renamed or moved root would otherwise be skipped in silence and
        # the gate would pass GREEN over a smaller corpus - coverage quietly dropping to nothing while
        # every signal says fine. That is the exact failure mode this whole project is named after, and
        # it is the single most likely way this gate stops being useful six months from now.
        # -LiteralPath for the same bracket-as-wildcard reason as Get-IgnoreGlobs above.
        if (-not (Test-Path -LiteralPath $full)) {
            throw "domain root missing: $full - if a product moved or was renamed, update `$script:DomainRoots; if it was deleted, remove the root deliberately."
        }
        # THE CORPUS WALK DOES NOT PRUNE. Every file under a domain root is either audited or subtracted
        # by an ANCHORED glob in the ignorelist, where a human wrote down why. Nothing is dropped silently.
        #
        # This is the round-10 fix for a total bypass. Pruning matched a segment name at ANY depth, so
        # naming a directory after one - skills/dist/, hooks/dist/, knowledge/target/ - removed it from
        # the corpus before any invariant ran. MEASURED: five files, one per shipped class (skill, hook,
        # knowledge manual, rules file, golden header), each carrying a real em dash, all invisible;
        # corpus 0, violations 0, and every one of them still ships and is injected.
        #
        # The naive fix - keep pruning but only for build output - fails because the subtraction itself was
        # the vector: an UNANCHORED `**/dist/**` in the ignorelist re-opened the same hole. So the build
        # directories are subtracted by their real, anchored paths instead. MEASURED: only seven such
        # directories exist inside all nine domain roots, TWO of them nested inside a single .venv, so
        # anchoring is cheap. Get-ReferenceIndex still prunes - it walks the WHOLE repository for
        # performance and its results are never audited, only resolved against.
        # DESCENT IS SKIPPED ONLY WHERE THE IGNORELIST ALREADY SUBTRACTS THE WHOLE DIRECTORY, which keeps
        # the bypass closed and the walk cheap at the same time. Not descending is decided by the SAME
        # anchored globs that decide subtraction - one source of truth - so `skills/dist/` is descended
        # into (nothing subtracts it) while `.venv/` is not (an anchored glob does).
        #
        # MEASURED, and this is why the skip exists: enumerating everything and filtering afterwards took
        # 12.4s for the corpus walk and 69s for the whole gate, visiting 3340 files to keep 99 and running
        # ~67k glob evaluations. Correct, but a gate nobody wants to wait for gets run less often, and a
        # gate run less often is the failure this project is about.
        $stack = [System.Collections.Generic.Stack[string]]::new()
        $seen  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $stack.Push($full)
        [void]$seen.Add((Get-WalkIdentity -Item (Get-Item -LiteralPath $full)))
        while ($stack.Count) {
            $dir = $stack.Pop()
            foreach ($child in Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue) {
                $rel = $child.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')
                if ($child.PSIsContainer) {
                    # A probe path under the directory: if the ignorelist subtracts everything inside it,
                    # there is nothing to audit in there and descending is pure cost.
                    if (Test-IsIgnored -RelPath ($rel + '/__probe__') -Globs $globs) { continue }
                    # BUILD-NAMED AND NOT ANCHORED-SUBTRACTED: do not descend, and do not audit what is
                    # inside. Get-UnexpectedBuildDirs reports the DIRECTORY itself instead.
                    #
                    # Dropping name-based pruning (round 10) closed a bypass but traded it for a false
                    # positive storm: MEASURED, a local bin/, obj/, node_modules/ or .vs/ inside a domain
                    # root put four binary artifacts into the corpus and produced four encoding failures
                    # on a developer machine that had merely run a build. Auditing binaries is noise;
                    # silently skipping them is the bypass. Reporting the directory is neither - it names
                    # the real problem, which is that build output is sitting inside shipped content.
                    if (Test-IsBuildDirName -Name $child.Name) { continue }
                    # HashSet.Add returns false when the identity was already present - the cycle guard.
                    if (-not $seen.Add((Get-WalkIdentity -Item $child))) { continue }
                    $stack.Push($child.FullName)
                    continue
                }
                if (-not (Test-IsIgnored -RelPath $rel -Globs $globs)) { $out.Add($rel) }
            }
        }
    }
    $out.ToArray()
}

$script:ShippedExtensions = @('md','sh','ps1','json','cs','rs','toml')

function Test-IsPathCandidate {
    param([string]$Token)
    if ([string]::IsNullOrWhiteSpace($Token)) { return $false }
    # Variables, placeholders and home-relative paths are never resolved here.
    if ($Token -match '[%$~]' -or $Token -match '<[^>]+>') { return $false }
    # Explicitly relative.
    if ($Token.StartsWith('./') -or $Token.StartsWith('../')) { return $true }
    # A leading bare '/' does NOT qualify: those are slash-commands (/agent, /mcp, /skills, ...).
    if ($Token.StartsWith('/')) { return $false }
    if ($Token -match '[\[\]]') { return $false }
    # CODE AND COMMANDS, not paths. A backtick span often holds a shell line or a source expression that
    # merely ENDS in something file-shaped, and the extension test below would happily classify it.
    # Measured 2026-08-09, both reported as reference violations against correct text the moment three new
    # roots were added: `ghidrust skill --emit > SKILL.md` (a command) came back 'broken', and
    # `os.path.dirname(__file__)/SKILL.md` (a Python expression) came back 'unclassified'.
    # No path in this repository contains whitespace or a parenthesis, so both are safe to exclude.
    if ($Token -match '[\s()]') { return $false }
    # DIRECTORY REFERENCES - spec 4.1.1 requires the plan to state their disposition, and the answer is
    # SKIP, never file-resolution. A trailing slash means a directory, and every directory reference in
    # this corpus is a RUNTIME path that legitimately does not exist in the repository: `.clavity/` and
    # `.clavity/agy-marks/` are gitignored (.gitignore:45), `.git/` is not shipped content, and
    # `.agents/skills/` lives on the user's machine. Resolving them as files would report `broken` on
    # correct text; resolving them as directories would report `broken` on a fresh clone. Neither is a
    # defect worth reporting, so they are not candidates at all.
    if ($Token.EndsWith('/')) { return $false }
    # A token must have a NAME before its extension. `.md` is a discussion of a file TYPE, not a path -
    # measured, agy-autotrain/CONTRIBUTING.md:21 backticks `.md` exactly that way, and it was being
    # classified as a candidate and then reported broken.
    $leaf = ($Token -split '/')[-1]
    if ($leaf.StartsWith('.') -and ($leaf -split '\.').Count -eq 2) { return $false }
    $ext = ($Token -split '\.')[-1]
    if ($ext -in $script:ShippedExtensions -and $ext -ne $Token) { return $true }
    return $false
}

$script:AssertPrefixes = @('docs/','scripts/','clavity-dotnet/','clavity-classic/','seed/','installer/','agy-autotrain/','ghidrust/','commonmemory/')
# Bare filenames whose referent lives on the USER's machine, not in this repository.
$script:RuntimeArtifacts = @('golden-header.md','golden-header.seed.md','golden-header.growth.md','settings.json')

# ONE pruned walk, cached per RepoRoot, instead of a recursive Get-ChildItem PER TOKEN.
# MEASURED 2026-08-09, and this is why: the old per-token search walked the repo root (41,306 files),
# ghidrust (19,521) and clavity-classic (15,600) UNPRUNED, for every bare filename - the probe ran over
# five minutes and had to be backgrounded. Pruning build and VCS directories takes the repo root to 1,050
# files, a 40x cut, and it is a CORRECTNESS fix too: unpruned, a reference could "resolve" to a build
# artifact under bin/, obj/ or target/ and be reported ok.
$script:RefIndex     = $null
$script:RefIndexRoot = $null

function Get-ReferenceIndex {
    param([string]$RepoRoot)
    # Same trailing-separator normalisation as the corpus walk, and for the same Substring reason. It also
    # keeps the cache key below canonical, so 'C:/repo' and 'C:/repo/' cannot build two different indexes.
    $RepoRoot = $RepoRoot -replace '[\\/]+$', ''
    if ($null -ne $script:RefIndex -and $script:RefIndexRoot -eq $RepoRoot) { return $script:RefIndex }
    $byName = @{}
    $all    = [System.Collections.Generic.List[string]]::new()
    Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            $rel = $_.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')
            # THE INDEX STILL PRUNES BY NAME, and the corpus walk above no longer does - that asymmetry is
            # deliberate, not drift. This walk covers the WHOLE repository for reference resolution and its
            # results are never audited, only matched against; name-based pruning is what keeps it cheap.
            # The corpus walk cannot afford the same shortcut, because there a silent skip is a bypass.
            # (An earlier version of this comment said "same reason as the corpus walk above", which stopped
            # being true the moment that walk changed - and my round-11 commit message claimed to have fixed
            # it when it had not. Round 12 found the claim was false.)
            if (Test-IsPrunedPath -RelPath $rel) { return }
            # Canonicalise the byte-identical twin trees at INDEX time, so any bare filename naming a
            # plugin file resolves to one logical path instead of being 'ambiguous' forever.
            # Derived from $script:TwinPluginRoots, not restated. The canonical form only has to be the
            # SAME for both trees, so it deliberately does not encode the trees' own directory names.
            $canon = $rel -replace $script:TwinCanonRx, 'clavity-TWIN/'
            $all.Add($canon)
            if (-not $byName.ContainsKey($_.Name)) { $byName[$_.Name] = [System.Collections.Generic.HashSet[string]]::new() }
            [void]$byName[$_.Name].Add($canon)
        }
    $script:RefIndex     = [pscustomobject]@{ ByName = $byName; All = @($all | Sort-Object -Unique) }
    $script:RefIndexRoot = $RepoRoot
    $script:RefIndex
}

function Resolve-Reference {
    param([string]$Token, [string]$RepoRoot, [string]$FromFile)
    if ($Token -in $script:RuntimeArtifacts) { return [pscustomobject]@{ Outcome = 'skip'; Matches = @() } }

    # Wildcards are a description of a file set, not a reference to a file.
    if ($Token -match '\*') { return [pscustomobject]@{ Outcome = 'skip'; Matches = @() } }

    # Dot-prefixed paths are runtime or tooling state, not shipped content: `.clavity/` is gitignored by
    # design (.gitignore:45), `.claude/` lives on the user's machine. Measured: treating them as
    # resolvable produced 11 of the 23 false positives in the first whole-domain probe.
    if ($Token.StartsWith('.') -and $Token -match '/') { return [pscustomobject]@{ Outcome = 'skip'; Matches = @() } }

    if ($Token.StartsWith('./') -or $Token.StartsWith('../')) {
        $base = if ($FromFile) { Split-Path -Parent (Join-Path $RepoRoot $FromFile) } else { $RepoRoot }
        $target = Join-Path $base $Token
        $o = if (Test-Path -LiteralPath $target) { 'ok' } else { 'broken' }
        return [pscustomobject]@{ Outcome = $o; Matches = @($target) }
    }

    # A repo-prefixed path that EXISTS resolves here. One that does not must FALL THROUGH to suffix
    # matching, not return 'broken' - a product-relative path can legitimately begin with a repo-root
    # prefix name. MEASURED: `docs/fix-the-tool-backlog/_template.md`, cited from inside agy-autotrain,
    # exists at agy-autotrain/docs/... but was reported broken because `docs/` short-circuited here.
    foreach ($p in $script:AssertPrefixes) {
        if ($Token.StartsWith($p) -and (Test-Path -LiteralPath (Join-Path $RepoRoot $Token))) {
            return [pscustomobject]@{ Outcome = 'ok'; Matches = @($Token) }
        }
    }

    $idx = Get-ReferenceIndex -RepoRoot $RepoRoot

    if ($Token -notmatch '/') {
        # The @( ... ) MUST wrap the whole `if`. A statement block UNROLLS its output, so
        # `$u = if (...) { @(x) }` yields the bare scalar x, and the empty branch yields $null - after
        # which $u.Count throws under Set-StrictMode. Measured: this failed the 0-match and 1-match rows
        # while the 2-match row passed, which is the signature of unrolling rather than a logic error.
        $u = @( if ($idx.ByName.ContainsKey($Token)) { $idx.ByName[$Token] } )
        $o = switch ($u.Count) { 0 { 'broken' } 1 { 'ok' } default { 'ambiguous' } }
        return [pscustomobject]@{ Outcome = $o; Matches = $u }
    }

    # SUFFIX MATCH - a slash-bearing token that matched no repo-root prefix. This is not an exotic case:
    # shipped text routinely cites a path relative to its OWN product (`hooks/agy-after-reminder.sh` from
    # inside agy-autotrain) or a partial path (`agy-curate/SKILL.md` for
    # agy-autotrain/skills/agy-curate/SKILL.md). MEASURED: treating these as unclassified produced 12 of
    # the 23 false positives in the first whole-domain probe - the run that proved the classifier was not
    # ready to ship. Suffix matching resolves both shapes with one rule and keeps the three outcomes.
    $suffix = '/' + $Token
    $u = @($idx.All | Where-Object { $_ -eq $Token -or $_.EndsWith($suffix) })
    if ($u.Count -gt 0) {
        $o = if ($u.Count -eq 1) { 'ok' } else { 'ambiguous' }
        return [pscustomobject]@{ Outcome = $o; Matches = $u }
    }

    # Resolves nowhere and matches no known prefix: an unclassified path-like token. Never a silent skip -
    # that would drop exactly the defect most worth catching, a wrong top-level prefix.
    return [pscustomobject]@{ Outcome = 'unclassified'; Matches = @() }
}

function Test-ReferenceFails {
    param([string]$Outcome)
    $Outcome -in @('broken','unclassified')
}

# Read BYTES. Under Windows PowerShell 5.1 a bare Get-Content decodes using the system ANSI code page,
# so multibyte sequences can be transcoded before any [^\x00-\x7F] regex sees them - a platform-dependent
# false negative in the one check that must be exact. In-repo precedents: check-seed-budget.ps1:32 and
# scripts/tests/agy-anomaly-capture-reminder.Tests.ps1:273.
function Test-PureAscii {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    -not ($bytes | Where-Object { $_ -gt 127 } | Select-Object -First 1)
}

function Get-NonAsciiReport {
    param([string]$Path)
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $lines = $text -split "`n"
    $hits = for ($i = 0; $i -lt $lines.Count; $i++) {
        $bad = @($lines[$i].ToCharArray() | Where-Object { [int]$_ -gt 127 } | ForEach-Object { '0x{0:x4}' -f [int]$_ })
        if ($bad.Count) { "  line $($i + 1): $($bad -join ' ')" }
    }
    $hits -join "`n"
}

function Get-PlanResidue {
    param([string]$Text)
    # A bare plan pointer with NO REFERENT: "(Task 5)", "(Step 12)", "(Phase 3)" left behind by the
    # implementation plan that produced the file, pointing at something no reader of the SHIPPED file
    # can see. "(item 5)" is deliberately NOT matched - a legitimate intra-document pointer.
    #
    # THE REFERENT CHECK IS THE POINT, and the first cut of this function omitted it - it matched the
    # shape and called that residue. MEASURED 2026-08-09: that reported adversarial-panel-review/SKILL.md
    # for "(Step 4)" on line 271, which points at that same file's own "### Step 4" heading on line 123.
    # A pointer the reader can follow inside the document they are already reading is a cross-reference,
    # not residue. So resolve it: a pointer is residue only when this document has no heading for it.
    #
    # Known and accepted limit: a whole leaked plan carrying BOTH "## Task 5" and "(Task 5)" resolves and
    # passes. That is a different defect (a plan shipped as content) and this invariant does not hunt it.
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($m in [regex]::Matches($Text, '\((Task|Step|Phase)\s+(\d+)\)')) {
        $kind = $m.Groups[1].Value
        $num  = $m.Groups[2].Value
        # Heading forms this repo actually uses: an ATX heading, or a bolded lead-in.
        # The trailing \b stops "Step 1" from resolving against a "### Step 12" heading.
        if (-not [regex]::IsMatch($Text, "(?m)^(#{1,6}\s*|\*\*)$kind\s+$num\b")) { $out.Add($m.Value) }
    }
    $out.ToArray()
}

function Test-HasPlanResidue {
    param([string]$Text)
    [bool](@(Get-PlanResidue -Text $Text).Count)
}

function Test-HasDuplicatedTag {
    param([string]$Text)
    [bool]([regex]::IsMatch($Text, '\[([A-Z0-9_-]+)\]\s*\1[:\s]'))
}

# THIS CHECKS SHAPE, NOT A SPECIFIC TAG - and that is a correction, not a weakening.
# Anomaly A2 claimed assertion-strength-reminder.sh's tag was namespace drift from its four siblings.
# IT IS NOT. clavity-dotnet/ROADMAP.md:714 records the deliberate ruling - "Drop the AGY- prefix - every
# AGY-* discipline convenes the peer; this one does not" - and
# scripts/tests/assertion-strength-reminder.Tests.ps1:199-201 PINS it. The prefix is signal, not drift.
# Requiring one specific tag would ship a change contradicting a recorded ruling and redden its guard.
function Test-DegradedNamespace {
    param([string]$Text)
    if ($Text -notmatch 'guard inactive:') { return $true }
    $Text -match '^\[[A-Z][A-Z0-9_-]*\]\s*guard inactive:'
}

# A bash single-quoted string cannot contain a bare apostrophe; the idiom is to close, escape, reopen -
# '"'"'. A naive non-greedy regex stops at the FIRST apostrophe and truncates the message.
# MEASURED 2026-08-08 in agy-seam-inject.sh, where that idiom appears 4 times: true body lengths are
# 1119, 1401 and 1618, while a naive scan reports 323, 381 and 1618. Two of three messages were being
# read at a quarter of their real size - so the budget check would have passed them for the wrong reason.
function Read-SingleQuotedBody {
    param([string]$Text, [int]$Start)   # $Start = index just after the opening quote
    $i = $Start
    while ($true) {
        $e = $Text.IndexOf("'", $i)
        if ($e -lt 0) { return $null }
        # TWO escape idioms, not one. Bash cannot put a bare apostrophe inside a single-quoted string, so
        # both of these are standard and both appear in real hooks: close-doublequote-reopen ('"'"', five
        # characters) and close-backslash-reopen ('\'', four). Handling only the first silently TRUNCATED
        # the body at the apostrophe - measured, a message written with the backslash form came back as
        # "hello" instead of "hello'world", which would under-report the payload budget for that hook.
        if ($e + 5 -le $Text.Length -and $Text.Substring($e, 5) -eq "'`"'`"'") { $i = $e + 5; continue }
        if ($e + 4 -le $Text.Length -and $Text.Substring($e, 4) -eq "'\''")    { $i = $e + 4; continue }
        return $Text.Substring($Start, $e - $Start).Replace("'`"'`"'", "'").Replace("'\''", "'")
    }
}

function Get-HookMessages {
    param([string]$Text)
    $out  = [System.Collections.Generic.List[string]]::new()
    $vars = @{}

    # Shape 1+2: msg<suffix>='...' and emit '...', single-quoted, quote-idiom aware.
    foreach ($m in [regex]::Matches($Text, "(?m)^\s*(?:(?<name>msg[A-Za-z0-9_]*)=|emit\s+)'")) {
        # Parentheses are REQUIRED. PowerShell binds -Start $m.Index and then treats + $m.Length as a
        # separate positional argument - it does not evaluate the sum.
        $body = Read-SingleQuotedBody -Text $Text -Start ($m.Index + $m.Length)
        if ($null -eq $body) { continue }
        $out.Add($body)
        if ($m.Groups['name'].Success) { $vars[$m.Groups['name'].Value] = $body }
    }
    # Shape 1+2, double-quoted form. [^"]* is WRONG here: a bash double-quoted string may contain \"
    # and that pattern stops at the first one. MEASURED on agy-after-reminder.sh, which carries 7 escaped
    # quotes: it captured 173 characters of a 763-character message - 77% silently discarded, after which
    # the budget and tag invariants are reading a fragment.
    foreach ($m in [regex]::Matches($Text, '(?ms)^\s*(?:(?<name>msg[A-Za-z0-9_]*)=|emit\s+)"(?<body>(?:[^"\\]|\\.)*)"')) {
        $body = $m.Groups['body'].Value.Replace('\"', '"')
        # emit "$msg" is a dispatch, not a message - its body is a bare variable reference whose content
        # was already collected at the assignment. Recording it adds a pseudo-message to diagnostics.
        if ($body -match '^\s*\$\{?[A-Za-z_][A-Za-z0-9_]*\}?\s*$') { continue }
        $out.Add($body)
        if ($m.Groups['name'].Success) { $vars[$m.Groups['name'].Value] = $body }
    }
    # Shape 3: a literal additionalContext payload. %s is a printf placeholder, not a message.
    foreach ($m in [regex]::Matches($Text, '"additionalContext"\s*:\s*"(?<body>[^"]*)"')) {
        $b = $m.Groups['body'].Value
        if ($b -ne '%s') { $out.Add($b) }
    }
    # Shape 4: the jq WRAPPER, where a tag can be prepended to an otherwise-clean body. Without this the
    # tag-hygiene invariant cannot see anomaly A1 at all - assertion-strength-reminder.sh:145 defines a
    # body with no bracket tag and :146 adds the tag in the --arg expression.
    # Composed by NAME against a variable map, with literal .Replace(). Never -replace: that is a REGEX
    # operator whose replacement string treats $1/$_ as capture references, so any message containing a
    # dollar sign would be silently mangled. And never a cross-product over every body collected so far -
    # that pairs each wrapper with unrelated messages and inflates the maximum the budget then measures.
    foreach ($m in [regex]::Matches($Text, '--arg\s+\w+\s+"(?<wrap>[^"]*\$\{?(?<var>msg[A-Za-z0-9_]*)\}?[^"]*)"')) {
        $name = $m.Groups['var'].Value
        if (-not $vars.ContainsKey($name)) { continue }
        $body = $vars[$name]
        $out.Add($m.Groups['wrap'].Value.Replace('${' + $name + '}', $body).Replace('$' + $name, $body))
    }
    $out.ToArray()
}

function Get-LongestHookMessage {
    param([string]$Text)
    $all = @(Get-HookMessages -Text $Text)
    if (-not $all.Count) { return '' }
    # The @( ) is NOT optional. Sort-Object with a SINGLE input returns a scalar string, and [0] on a
    # string yields its first CHARACTER. Measured: this returned "b" for a 54-character message. Most
    # hooks emit exactly one message, so the payload budget would have measured ONE CHARACTER for nearly
    # every file in the domain - a totally vacuous check that no row here would have caught except the
    # two truncation rows, which failed for what looked like a parser bug.
    @($all | Sort-Object Length -Descending)[0]
}

# Budget in CHARACTERS, against the longest branch. CALIBRATED BY MEASUREMENT, re-measured twice because
# the first two probes were wrong in the same way the parser was:
#   draft 1 said 1000  - the parser could not see emit '...' at all
#   draft 2 said 1517  - the probe truncated at bash's close-escape-reopen idiom, the very bug hunted
#   final:      1618   - quote-aware scan, agy-seam-inject.sh third emit; then 1517; then 845-848.
# A probe that shares the defect it is measuring is not a measurement.
$script:MaxMessageChars = 1800

# WHAT THIS BUDGET ACTUALLY BOUNDS - stated, because a gate that overclaims is this project's subject.
# Static parsing measures the TEMPLATE, not the payload an agent receives. agy-consult-guard-post.sh:89
# interpolates $axes, $paths and $headmsg, and $headmsg (line 86) is git log output computed at runtime;
# the static body counts those as their literal variable names. So the budget catches PROSE growth and
# does NOT bound the interpolated result. Bounding the real payload would need execution, rejected on
# measurement (16 bash spawns = 5.24s against a 0.64s control) and vacuous without per-hook fixtures
# driving each maximal branch. An accepted limit, not an oversight.

function Assert-ExemptionShape {
    param([psobject]$Entry)
    foreach ($f in @('path','invariant','reason')) {
        if (-not $Entry.PSObject.Properties.Name.Contains($f)) { throw "exemption missing '$f': $($Entry | ConvertTo-Json -Compress)" }
        if ([string]::IsNullOrWhiteSpace([string]$Entry.$f)) { throw "exemption has empty '$f'" }
    }
}

function Expand-ExemptionPath {
    param([psobject]$Entry)
    $scope = if ($Entry.PSObject.Properties.Name.Contains('scope')) { $Entry.scope } else { '' }
    if ($scope -eq 'twin-plugin') {
        # One entry covers both byte-identical trees, and BOTH expanded paths must exist - enforced by the
        # throw in Get-InjectedContextViolations, which is what stops one tree being cleaned while the
        # other keeps its waiver. Until that throw existed this comment described an intention that
        # nothing actually checked, which is how the phantom-key defect survived two rounds.
        return @($script:TwinPluginRoots | ForEach-Object { "$_/$($Entry.path)" })
    }
    @($Entry.path)
}

# RETIRED, deliberately EMPTY. This was standup scaffolding: while the ten audited anomalies were still
# live, an exemption naming one of them would have passed bidirectional validation and shipped the defect
# under a waiver. Every one of them is now either fixed or ruled not-a-defect, so the guarantee transfers
# to the ordinary invariants - they pass on those files today and go red again if a defect returns, which
# is a stronger guard than a hardcoded list because it needs no maintenance.
#
# The list stays (rather than deleting the mechanism) as the seam a future audit re-populates. Note the
# consequence honestly: with no tuples, Test-IsBlocklisted always returns $false and the throw it guards
# in Get-InjectedContextViolations is unreachable. That is the intended end state, not an oversight.
$script:AnomalyBlocklist = @()

function Test-IsBlocklisted {
    param([string]$Path, [string]$Invariant)
    [bool](@($script:AnomalyBlocklist | Where-Object { $Path -like "*$($_.Path)" -and $_.Invariant -eq $Invariant }).Count)
}

function New-Violation {
    param([string]$File, [string]$Invariant, [string]$Finding)
    # The waiver line is emitted verbatim so an operator can paste it rather than reverse-engineer the
    # schema. A gate that reports only "file X is not covered" teaches people to bypass it.
    $waiver = (@{ path = $File; invariant = $Invariant; reason = '<why this is deliberate>' } |
               ConvertTo-Json -Compress)
    [pscustomobject]@{ File = $File; Invariant = $Invariant; Finding = $Finding; WaiverLine = $waiver }
}

function Get-InjectedContextViolations {
    # NO TEST SEAM. An earlier draft carried a -Files parameter so tests could drive the enforcement
    # branch with a synthetic corpus - test-only surface in production code, and a path by which passing
    # an empty set would silently neuter the gate. Unnecessary: the tests point -RepoRoot at a temp
    # directory and discovery walks THAT tree, so a fixture file is found natively.
    param([string]$RepoRoot)
    $files = Get-InjectedContextFiles -RepoRoot $RepoRoot
    $ex    = @((Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts/injected-context-exemptions.json') -Raw |
                ConvertFrom-Json).exemptions)
    $exempt = @{}
    foreach ($e in $ex) {
        Assert-ExemptionShape -Entry $e
        if (Test-IsBlocklisted -Path $e.path -Invariant $e.invariant) {
            throw "exemption names a known anomaly and cannot be honoured: $($e.path) / $($e.invariant)"
        }
        foreach ($p in (Expand-ExemptionPath -Entry $e)) {
            # EVERY EXPANDED PATH MUST EXIST. Expand-ExemptionPath's own comment claims the invariant must
            # be failing in BOTH twin trees, and until now the script enforced none of that - a twin-scoped
            # entry naming a file present in only one tree produced a phantom key for the other, which the
            # walk never queries, so one tree could be cleaned while the other kept its waiver. MEASURED
            # 2026-08-09, BEFORE the throw below existed: the suite reddened on that case and the gate
            # still exited 0. The throw is what changed the second half - the gate now fails too.
            #
            # This also catches the anchoring trap in the same throw. The `path` field is PLUGIN-relative
            # under scope 'twin-plugin' and REPO-relative without it, which is easy to get backwards: a
            # repo-relative path with twin scope expands to clavity-dotnet/plugin/clavity-classic/plugin/...
            # and would otherwise waive nothing, silently, leaving the author to wonder why.
            if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $p))) {
                # NAME BOTH CAUSES, most likely first, the way the domain-root throw above does. The first
                # version led with the anchoring lecture, which is the RARER cause: someone who simply
                # deleted a file and left its exemption behind got a paragraph about plugin-relative
                # prefixes they never used, and no mention of the orphan they actually created.
                throw ("exemption path does not exist: $p" +
                       "`n  from entry: $($e.path)" +
                       "`n  If the file was DELETED, delete this exemption too - it is now orphaned." +
                       "`n  If the file still exists, the path is anchored wrongly: under scope" +
                       " 'twin-plugin' it is relative to the PLUGIN directory (skills/... , knowledge/...)," +
                       " and repo-relative without that scope. A doubled prefix above means the two were" +
                       " swapped.")
            }
            $exempt["$p|$($e.invariant)"] = $true
        }
    }

    $out = [System.Collections.Generic.List[object]]::new()

    # Build output inside a domain root, reported as one violation per DIRECTORY rather than as a flood
    # of encoding failures over its binaries - or, worse, as nothing at all.
    # THE EXEMPTION CHECK IS NOT OPTIONAL HERE. Every other invariant is waivable, and this one printed a
    # waiver line while ignoring it: MEASURED, an operator who pasted the gate's own suggested waiver saw
    # the identical violation on the next run, with no way out. A gate that tells you how to proceed and
    # then refuses is worse than one that offers nothing, because it costs a debugging session to learn
    # the instruction was false.
    foreach ($d in (Get-UnexpectedBuildDirs -RepoRoot $RepoRoot)) {
        if ($exempt.ContainsKey("$d|build-output")) { continue }
        $out.Add((New-Violation -File $d -Invariant 'build-output' -Finding "build output inside a domain root - move it out, or subtract it with an anchored glob and a reason"))
    }

    foreach ($f in $files) {
        $full = Join-Path $RepoRoot $f
        # READABILITY IS AN INVARIANT, NOT AN ASSUMPTION. Every invariant below reads this file - three
        # separate read sites (Test-PureAscii, Get-NonAsciiReport, and the ReadAllText here) - and NONE of
        # them was guarded. A file locked by another process, or deleted between the corpus walk and this
        # loop, threw an unhandled exception that escaped through NEITHER documented exit: the gate died
        # with a stack trace where it promises a violation report. The window is real, not theoretical -
        # the walk enumerates and this loop reads, so anything touching the tree in between hits it.
        #
        # WRAPPED AROUND THE WHOLE BODY, and the exception types are NARROW ON PURPOSE. A bare `catch`
        # here would swallow a genuine logic error in any invariant and report it as "unreadable", which
        # is the fail-open this gate exists to prevent - it would certify a file whose invariants never
        # actually ran. IOException (FileNotFoundException derives from it) and UnauthorizedAccessException
        # (which does NOT) are the two an inaccessible file actually raises; a null-ref or index error is
        # neither, and still crashes loudly.
        #
        # REPORTED AS A VIOLATION, NEVER SKIPPED. Skipping would mark a file the gate never read as
        # passing. Waivable like every other invariant, because an unwaivable violation was itself a
        # folded defect (build-output, round 12) - and if anyone ever waives it, the exemption suite's
        # `default` arm throws and tells them to add a case, which is exactly the intended workflow.
        try {
            # EVERY invariant runs on EVERY file. No short-circuit: the gate is run RED on purpose before
            # the anomalies are closed, and hiding all but the first would destroy the red-to-green evidence.
            if (-not $exempt.ContainsKey("$f|encoding") -and -not (Test-PureAscii -Path $full)) {
                $out.Add((New-Violation -File $f -Invariant 'encoding' -Finding (Get-NonAsciiReport -Path $full)))
            }
            $text = [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
            # Report the first UNRESOLVED pointer. Re-matching the raw regex here would name the first
            # pointer of any kind, so a file holding one resolvable cross-reference and one dangling
            # pointer would be correctly flagged and then send the operator to the wrong line.
            $residue = @(Get-PlanResidue -Text $text)
            if (-not $exempt.ContainsKey("$f|plan-residue") -and $residue.Count) {
                $out.Add((New-Violation -File $f -Invariant 'plan-residue' -Finding "bare plan pointer: $($residue[0])"))
            }
            foreach ($m in (Get-HookMessages -Text $text)) {
                if (-not $exempt.ContainsKey("$f|tag-hygiene") -and (Test-HasDuplicatedTag -Text $m)) {
                    $out.Add((New-Violation -File $f -Invariant 'tag-hygiene' -Finding "duplicated tag: $($m.Substring(0, [Math]::Min(60, $m.Length)))"))
                }
                if (-not $exempt.ContainsKey("$f|namespace") -and -not (Test-DegradedNamespace -Text $m)) {
                    $out.Add((New-Violation -File $f -Invariant 'namespace' -Finding 'degraded line carries no bracketed tag'))
                }
            }
            $longest = Get-LongestHookMessage -Text $text
            if ($longest.Length -gt $script:MaxMessageChars -and -not $exempt.ContainsKey("$f|payload-budget")) {
                $head = $longest.Substring(0, [Math]::Min(60, $longest.Length))
                # NAME HOW MANY EXCEED, not just the worst one. Only the longest message is reported, and 18
                # corpus files carry more than one hook message (4 in the largest, measured), so an operator
                # who waives this file for payload-budget would silently waive siblings they never saw. The
                # waiver is per (file, invariant), so the count is the only warning they get.
                $over = @(Get-HookMessages -Text $text | Where-Object { $_.Length -gt $script:MaxMessageChars }).Count
                $out.Add((New-Violation -File $f -Invariant 'payload-budget' -Finding "$($longest.Length) chars > $script:MaxMessageChars ($over message(s) in this file exceed it) - starts: $head"))
            }
            foreach ($tok in [regex]::Matches($text, '`([^`\n]{1,80})`')) {
                $t = $tok.Groups[1].Value
                if (-not (Test-IsPathCandidate -Token $t)) { continue }
                $r = Resolve-Reference -Token $t -RepoRoot $RepoRoot -FromFile $f
                if ((Test-ReferenceFails -Outcome $r.Outcome) -and -not $exempt.ContainsKey("$f|reference")) {
                    $out.Add((New-Violation -File $f -Invariant 'reference' -Finding "$($r.Outcome): $t"))
                }
            }
        }
        catch [System.IO.IOException], [System.UnauthorizedAccessException] {
            if (-not $exempt.ContainsKey("$f|unreadable")) {
                $out.Add((New-Violation -File $f -Invariant 'unreadable' -Finding "cannot be read: $($_.Exception.GetType().Name)"))
            }
        }
    }
    $out.ToArray()
}

function Invoke-InjectedContextCheck {
    param([string]$RepoRoot)
    $v = @(Get-InjectedContextViolations -RepoRoot $RepoRoot)
    if (-not $v.Count) { Write-Host 'check-injected-context: OK' -ForegroundColor Green; exit 0 }
    foreach ($x in $v) {
        Write-Host ("{0}`n  invariant : {1}`n  found     : {2}`n  waive with: {3}" -f $x.File, $x.Invariant, $x.Finding, $x.WaiverLine)
    }
    Write-Host "check-injected-context: $($v.Count) violation(s)"
    # NAME THE DESTINATION AND THE NESTING. The waiver line above is a bare JSON object, and a developer
    # meeting this gate for the first time has to go find where it belongs. The obvious guess - append it
    # to the end of the exemptions file - puts it OUTSIDE the "exemptions" array, which is invalid JSON,
    # and the next run dies in ConvertFrom-Json for everyone until someone repairs it by hand. The gate
    # fails closed rather than open, so nothing ships silently; but turning a one-file violation into a
    # broken gate is a bad trade for a line of output.
    Write-Host ""
    Write-Host "A waiver goes INSIDE the `"exemptions`" array in scripts/injected-context-exemptions.json,"
    Write-Host "as another element - not appended after it. ADD A COMMA after the previous element: the"
    Write-Host "line above is a bare object and pasting it without one is invalid JSON, which fails this"
    Write-Host "gate for everyone on the next run. Replace the placeholder reason with a real one;"
    Write-Host "an exemption whose file stops failing its invariant is reported as unused and must be deleted."
    Write-Host "Fixing the file is almost always right. A waiver is for something deliberate and permanent."
    exit 1
}

# DOT-SOURCE / EXECUTE SPLIT. The test suite dot-sources this file to reach the functions above, so the
# main body must NOT run in that case - otherwise every dot-source would walk the tree and set an exit
# code. `$MyInvocation.InvocationName` is '.' exactly when dot-sourced.
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-InjectedContextCheck -RepoRoot $RepoRoot   # defined in Task 9
}

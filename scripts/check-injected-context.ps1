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

# The six roots. Owner ruling 2026-08-08 (spec 6.1): all six, no product excluded.
$script:DomainRoots = @(
    'clavity-dotnet/plugin'
    'clavity-classic/plugin'
    'seed'
    'agy-autotrain'
    'ghidrust/plugin'
    'commonmemory'
)

function Get-IgnoreGlobs {
    param([string]$RepoRoot)
    $p = Join-Path $RepoRoot 'scripts/injected-context-ignore.txt'
    if (-not (Test-Path $p)) { throw "ignorelist missing: $p" }
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
    $globs = Get-IgnoreGlobs -RepoRoot $RepoRoot
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($root in $script:DomainRoots) {
        $full = Join-Path $RepoRoot $root
        # THROW, never `continue`. A renamed or moved root would otherwise be skipped in silence and
        # the gate would pass GREEN over a smaller corpus - coverage quietly dropping to nothing while
        # every signal says fine. That is the exact failure mode this whole project is named after, and
        # it is the single most likely way this gate stops being useful six months from now.
        if (-not (Test-Path $full)) {
            throw "domain root missing: $full - if a product moved or was renamed, update `$script:DomainRoots; if it was deleted, remove the root deliberately."
        }
        # Prune heavy directories at traversal level. Measured 2026-08-08: none currently exist under any
        # domain root (corpus is 130 files), so this is hardening, not a fix.
        Get-ChildItem -LiteralPath $full -Recurse -File -Force |
            Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|target|bin|obj|\.venv|__pycache__)[\\/]' } |
            ForEach-Object {
                $rel = $_.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')
                if (-not (Test-IsIgnored -RelPath $rel -Globs $globs)) { $out.Add($rel) }
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
    if ($null -ne $script:RefIndex -and $script:RefIndexRoot -eq $RepoRoot) { return $script:RefIndex }
    $byName = @{}
    $all    = [System.Collections.Generic.List[string]]::new()
    Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|target|bin|obj|\.venv|__pycache__|dist|publish|\.vs)[\\/]' } |
        ForEach-Object {
            $rel = $_.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')
            # Canonicalise the byte-identical twin trees at INDEX time, so any bare filename naming a
            # plugin file resolves to one logical path instead of being 'ambiguous' forever.
            $canon = $rel -replace '^clavity-(dotnet|classic)/plugin/', 'clavity-TWIN/plugin/'
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

function Test-HasPlanResidue {
    param([string]$Text)
    # A bare plan pointer with no referent: "(Task 5)", "(Step 12)", "(Phase 3)".
    # "(item 5)" is deliberately NOT matched - it is a legitimate intra-document pointer.
    [bool]([regex]::IsMatch($Text, '\((Task|Step|Phase)\s+\d+\)'))
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
        if ($e + 5 -le $Text.Length -and $Text.Substring($e, 5) -eq "'`"'`"'") { $i = $e + 5; continue }
        return $Text.Substring($Start, $e - $Start).Replace("'`"'`"'", "'")
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
        # One entry covers both byte-identical trees, and the invariant must be failing in BOTH. Settling
        # for the first tree found would let one be cleaned while the other keeps the defect.
        return @("clavity-dotnet/plugin/$($Entry.path)", "clavity-classic/plugin/$($Entry.path)")
    }
    @($Entry.path)
}

# TEMPORARY standup scaffolding. Each tuple is deleted by its anomaly's fix commit; the last one removes
# this list entirely. Without it, an exemption for an actively-failing section-3 anomaly would pass
# bidirectional validation and ship the defect.
$script:AnomalyBlocklist = @(
    @{ Path = 'seed/golden-header.md';                      Invariant = 'encoding' }
    @{ Path = 'skills/agy-first/SKILL.md';                  Invariant = 'plan-residue' }
    @{ Path = 'knowledge/agy-capabilities.md';              Invariant = 'reference' }
    @{ Path = 'hooks/assertion-strength-reminder.sh';       Invariant = 'tag-hygiene' }
)
# NOTE: there is deliberately no (assertion-strength-reminder.sh, namespace) tuple. A2 was withdrawn -
# that hook's tag is a documented ruling (ROADMAP.md:714), not a defect. See Task 10 Step 2.

function Test-IsBlocklisted {
    param([string]$Path, [string]$Invariant)
    [bool](@($script:AnomalyBlocklist | Where-Object { $Path -like "*$($_.Path)" -and $_.Invariant -eq $Invariant }).Count)
}

# DOT-SOURCE / EXECUTE SPLIT. The test suite dot-sources this file to reach the functions above, so the
# main body must NOT run in that case - otherwise every dot-source would walk the tree and set an exit
# code. `$MyInvocation.InvocationName` is '.' exactly when dot-sourced.
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-InjectedContextCheck -RepoRoot $RepoRoot   # defined in Task 9
}

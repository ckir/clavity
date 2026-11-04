<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

Set-StrictMode -Version Latest

# The REFERENCE-INDEX and ASCII / HOOK-MESSAGE halves of scripts/check-injected-context.ps1, moved here
# verbatim (no behaviour change) so the gate's entry script is the walk + the invariants + the runner.
# DOT-SOURCE ONLY, from check-injected-context.ps1: the functions share that script's `$script:` scope and
# rely on definitions that stay there (ConvertTo-GateRepoRoot, Test-IsPrunedPath, $script:PruneRx,
# $script:DomainRoots, $script:TwinCanonRx). Sourcing it defines functions and script-scope state only.
$script:ShippedExtensions = @('md','sh','ps1','json','cs','rs','toml')

function Test-IsPathCandidate {
    param([string]$Token)
    if ([string]::IsNullOrWhiteSpace($Token)) { return $false }
    # Variables, placeholders and home-relative paths are never resolved here.
    if ($Token -match '[%$~]' -or $Token -match '<[^>]+>') { return $false }
    # A leaf of THREE OR MORE periods is an ellipsis (`../../../seed/...`), not a name. Windows path normalisation drops trailing
    # periods and Linux keeps them, so resolving it gave different answers per OS (ROADMAP 98). `.` and `..` are real segments
    # and stay candidates (capstone round 1: `^\.+$` hid a broken `../x/..`).
    if (($Token -split '/')[-1] -match '^\.{3,}$') { return $false }
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

# 'installer/' is asserted for .ps1 ONLY. `.iss` is absent from $ShippedExtensions above, so
# Test-IsPathCandidate drops every .iss token before Resolve-Reference ever sees it - deliberately:
# installer content is PACKAGING INPUT, not injected context, and the extension test runs before any
# prefix logic here. MEASURED 2026-08-11: installer/_shared/anything.iss -> candidate False, while
# installer/_shared/register-plugin.ps1 (the only .ps1 under installer/) -> True. The cost is accepted
# and logged in docs/coverage-debt.md: a genuinely broken .iss reference sails past this gate.
$script:AssertPrefixes = @('docs/','scripts/','clavity-dotnet/','clavity-classic/','seed/','installer/','agy-autotrain/','commonmemory/','review-relay/')
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
    # Normalised by ConvertTo-GateRepoRoot, so 'C:/repo' and 'C:/repo/' key ONE cached index below, and a drive
    # root keeps its separator.
    $RepoRoot = ConvertTo-GateRepoRoot $RepoRoot
    if ($null -ne $script:RefIndex -and $script:RefIndexRoot -eq $RepoRoot) { return $script:RefIndex }
    # ONE resolver per root, built BEFORE the loop - ROADMAP section 28 capstone. Resolving inside the loop re-ran
    # Get-Item on the same root once per FILE (~64s a run). Guarded so a missing root keeps its own error.
    $pathResolver = if (Test-Path -LiteralPath $RepoRoot) { New-RootRelativePathResolver -Root $RepoRoot } else { $null }
    $byName = @{}
    $all    = [System.Collections.Generic.List[string]]::new()
    # Index only what CI will have (ROADMAP §54): a suffix match to an untracked file is as false as a direct
    # reference to one. The tracked list also spares the recursive disk walk; the walk is the no-git fallback.
    $null = Get-TrackedPathSet -RepoRoot $RepoRoot
    $items = if ($null -ne $script:TrackedFiles) {
        $script:TrackedFiles | ForEach-Object { [pscustomobject]@{ Rel = $_; Name = ($_ -split '/')[-1] } }
    } else {
        Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
            ForEach-Object { [pscustomobject]@{ Rel = $pathResolver.Resolve($_.FullName).Replace('\', '/'); Name = $_.Name } }
    }
    $items | ForEach-Object {
            $rel = $_.Rel
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

# WHAT EXISTS, AS CI WILL SEE IT (ROADMAP §54). Every reference used to be checked with Test-Path, i.e. against
# the WORKING TREE, so a reference to an untracked or gitignored file passed locally and failed in CI, which
# checks out only committed files. The answer now comes from the git INDEX: every tracked file, plus every
# directory that holds one (Test-Path accepted directories, and references to them are legitimate).
# Returns $null when $RepoRoot is not inside a git work tree - callers then fall back to Test-Path, and the
# gate SAYS so (see $script:TrackedFallbackRoots) rather than silently checking the weaker thing.
$script:TrackedSet     = $null
$script:TrackedFiles   = $null   # the tracked FILES alone (the set above also holds their directories)
$script:TrackedSetRoot = $null
$script:TrackedFallbackRoots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Get-TrackedPathSet {
    param([string]$RepoRoot)
    $RepoRoot = ConvertTo-GateRepoRoot $RepoRoot
    if ($script:TrackedSetRoot -eq $RepoRoot) { return ,$script:TrackedSet }
    $set = $null
    $filesList = $null
    try {
        $inside = (& git -C $RepoRoot rev-parse --is-inside-work-tree 2>$null)
        if ($LASTEXITCODE -eq 0 -and $inside -eq 'true') {
            $raw = (& git -C $RepoRoot ls-files -z 2>$null) -join ''
            if ($LASTEXITCODE -eq 0) {
                $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $filesList = [System.Collections.Generic.List[string]]::new()
                foreach ($f in ($raw -split "`0")) {
                    if (-not $f) { continue }
                    $p = $f.Replace('\', '/')
                    [void]$set.Add($p)
                    $filesList.Add($p)
                    $i = $p.LastIndexOf('/')
                    while ($i -gt 0) { $p = $p.Substring(0, $i); [void]$set.Add($p); $i = $p.LastIndexOf('/') }
                }
            }
        }
    } catch { $set = $null; $filesList = $null }
    if ($null -eq $set) { [void]$script:TrackedFallbackRoots.Add($RepoRoot) }
    $script:TrackedSet = $set
    $script:TrackedFiles = $filesList
    $script:TrackedSetRoot = $RepoRoot
    return ,$set
}

# One existence test for every reference site: the index when there is one, the working tree otherwise.
function Test-RepoPathExists {
    param([string]$RepoRoot, [string]$RelPath)
    $tracked = Get-TrackedPathSet -RepoRoot $RepoRoot
    if ($null -eq $tracked) { return (Test-Path -LiteralPath (Join-Path $RepoRoot $RelPath)) }
    return $tracked.Contains($RelPath.Replace('\', '/').TrimEnd('/'))
}

function Resolve-Reference {
    param([string]$Token, [string]$RepoRoot, [string]$FromFile)
    if ($Token -in $script:RuntimeArtifacts) { return [pscustomobject]@{ Outcome = 'skip'; Matches = @() } }

    # Wildcards are a description of a file set, not a reference to a file.
    if ($Token -match '\*') { return [pscustomobject]@{ Outcome = 'skip'; Matches = @() } }

    # Dot-prefixed paths are runtime or tooling state, not shipped content: `.clavity/` is gitignored by
    # design (.gitignore:45), `.claude/` lives on the user's machine. Measured: treating them as
    # resolvable produced 11 of the 23 false positives in the first whole-domain probe.
    # `./` and `../` are relative references, not runtime state, and used to be swallowed here, which left the
    # relative-reference branch below dead (ROADMAP §54 execution, 2026-09-30).
    if ($Token.StartsWith('.') -and -not $Token.StartsWith('./') -and -not $Token.StartsWith('../') -and $Token -match '/') { return [pscustomobject]@{ Outcome = 'skip'; Matches = @() } }

    if ($Token.StartsWith('./') -or $Token.StartsWith('../')) {
        $base = if ($FromFile) { Split-Path -Parent (Join-Path $RepoRoot $FromFile) } else { $RepoRoot }
        $target = Join-Path $base $Token
        $full = [System.IO.Path]::GetFullPath($target).TrimEnd('\', '/')
        $root = [System.IO.Path]::GetFullPath((ConvertTo-GateRepoRoot $RepoRoot)).TrimEnd('\', '/')
        $o = if ($full.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) { 'ok' }   # the repo root itself
             elseif ($full.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -and
                     (Test-RepoPathExists -RepoRoot $RepoRoot -RelPath $full.Substring($root.Length + 1))) { 'ok' }
             else { 'broken' }
        return [pscustomobject]@{ Outcome = $o; Matches = @($target) }
    }

    # A repo-prefixed path that EXISTS resolves here. One that does not must FALL THROUGH to suffix
    # matching, not return 'broken' - a product-relative path can legitimately begin with a repo-root
    # prefix name. MEASURED: `docs/fix-the-tool-backlog/_template.md`, cited from inside agy-autotrain,
    # exists at agy-autotrain/docs/... but was reported broken because `docs/` short-circuited here.
    foreach ($p in $script:AssertPrefixes) {
        if ($Token.StartsWith($p) -and (Test-RepoPathExists -RepoRoot $RepoRoot -RelPath $Token)) {
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

# CONVENTION, and it is load-bearing: a hook's agent-visible message must be built in a variable named
# `msg` or `msg<Suffix>`. All three variable-bearing shapes below bind `msg[A-Za-z0-9_]*` and nothing else,
# so a payload assembled in a differently-named variable - `body=$(...)`, `payload="$a$b"` - yields ZERO
# extracted messages, and the payload-budget and tag-hygiene invariants then silently measure nothing.
# MEASURED 2026-08-11 with a control: a hook using msg='...' + `jq --arg m "$msg"` is caught; the same
# message carried in `body` or `payload` produced 0 extracted messages and no tag-hygiene violation even
# though the message duplicated a bracket tag.
# Widening this to follow command substitution and concatenation is an explicit NON-GOAL: the shape space
# is open-ended so it cannot be made complete, and it would be a behaviour change requiring a re-capstone.
# The convention is enforced by test instead - see scripts/tests/check-injected-context.Tests.ps1,
# 'extracts at least one message from every corpus hook that actually emits one' - and documented for
# contributors in agy-autotrain/CONTRIBUTING.md.
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

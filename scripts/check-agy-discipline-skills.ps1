# scripts/check-agy-discipline-skills.ps1
# Lints the shipped agy-driving discipline skills for their checkable invariants.
# Byte-identity across plugins is enforced separately by scripts/check-seed-artifacts-synced.sh.
[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
$fail = $false
function Fail($msg) { Write-Error $msg -ErrorAction Continue; $script:fail = $true }

# THE ONE PLACE THAT DECIDES WHAT "THE REGISTRY" MEANS. Both readers of the checker's SCHEMAS map go
# through here, because capstone R3 measured what happens when they do not: R2 bounded the roster scan to
# this block and left the per-skill key-list lookup scanning the whole file, so the same defect class
# survived one line away from its own fix. A shared helper makes "which text counts as the registry" a
# single answerable question rather than two independent regexes that can drift apart.
#
# Returns $null when the block cannot be located, and every caller treats that as a FAILURE rather than
# as an empty registry - an unparseable map and an empty one have identical effects and opposite causes.
#
# '^\s*\}' rather than '^\}', which is capstone R3's finding folded: the reviewer pointed out that
# anchoring the closing brace at column 0 assumes a formatter that never indents it. The block holds only
# key/list pairs and no nested dict, so the first line whose content is a closing brace IS the closer at
# any indent. An inline 'SCHEMAS = {}' still returns $null, which fails closed, which is correct - an
# empty registry is not a thing this repository can have.
# EXACTLY ONE ASSIGNMENT, OR NOTHING. Capstone R4 measured what R3's consolidation did NOT fix: bounding
# the scan to "the SCHEMAS block" still has to DECIDE which block that is, and [regex]::Match takes the
# first. A decoy 'SCHEMAS = {' block written at column 0 inside the module docstring was read as the
# registry, and a drifted real entry passed - the same smuggle as R3, one level up, because the repair had
# narrowed the class instead of removing it.
#
# The answer is not a cleverer pattern. It is to REFUSE TO GUESS: count the assignments and fail unless
# there is exactly one. A file with two is ambiguous, and a guard that picks one of two candidate
# registries is asserting something it cannot know. This also ends the class rather than narrowing it -
# any future decoy, in a docstring or anywhere else, raises the count.
#
# What this still is NOT: a Python parse. The reviewer's position, twice stated, is that only ast.parse()
# removes regex from the equation, and it is right that a text scan can always be surprised. That is a
# dependency decision for the owner (this linter runs today with no Python on PATH), recorded rather than
# taken quietly - and uniqueness makes the surprise LOUD, which is the property that actually matters.
function Get-SchemasBlock([string]$Path) {
    $text = Get-Content -Raw $Path
    $starts = [regex]::Matches($text, '(?m)^SCHEMAS\s*=\s*\{')
    if ($starts.Count -ne 1) { return $null }
    $m = [regex]::Match($text, '(?ms)^SCHEMAS\s*=\s*\{(?<body>.*?)^\s*\}')
    if ($m.Success) { return $m.Groups['body'].Value }
    return $null
}

# Discipline skills shipped so far. SP-B appended 'agy-capstone'; AGY-TEST-AUDIT appends 'agy-test-audit'.
$skills = @('agy-first', 'agy-capstone', 'agy-test-audit')

# The required ASCII [VERDICT] forms PER SKILL (each discipline has its own vocabulary). agy-first and
# agy-capstone share the convergent-review set (spec Decision 2.1 + 2.7); agy-test-audit gates coverage,
# so it declares EXHAUSTIVE / GAPS FOUND / agy-required-but-unreachable instead.
# The AGY-SCOPE disposition taxonomy (spec 2026-08-07). Required for the two review disciplines ENROLLED
# in this checker. agy-first is excluded on purpose: it is a consult discipline and raises no findings to
# dispose of. adversarial-panel-review DOES carry the taxonomy but is not enrolled in $skills at all (it
# has 69 non-ASCII chars and no marker constant); it is pinned instead by the
# 'AGY-SCOPE disposition taxonomy' Describe in scripts/tests/check-agy-discipline-skills.Tests.ps1.
$dispositionTokens = @(
    'FOLDED: '
    'REJECTED: '
    'DISCARDED-BELOW-FLOOR: '
    'DEFERRED-TO-ANOMALIES: '
    'UNVERIFIED-ACCEPTED: '
)
$requiredVerdicts = @{
    'agy-first'      = @('[VERDICT: ALIGNED]', '[VERDICT: REJECTED - ', '[VERDICT: NEGOTIATE - ', '[VERDICT: SKIPPED-UNREACHABLE]')
    'agy-capstone'   = @('[VERDICT: ALIGNED]', '[VERDICT: REJECTED - ', '[VERDICT: NEGOTIATE - ', '[VERDICT: SKIPPED-UNREACHABLE]') + $dispositionTokens
    'agy-test-audit' = @('[VERDICT: EXHAUSTIVE]', '[VERDICT: GAPS FOUND]', '[VERDICT: agy-required-but-unreachable]') + $dispositionTokens
}
# The documented marker-contract constant the skill must reference (Task 5).
$markerConstant = '.clavity/agy-marks/'

# The two disciplines that own a ledger, and the file each must name. A discipline with a completing
# verdict and no recorded range leaves "was this range reviewed?" unanswerable in the tree - which is
# ROADMAP section 23, ruled by the owner on 2026-09-03.
$ledgerFor = @{
    'agy-capstone'   = 'docs/agy-capstone-ledger.md'
    'agy-test-audit' = 'docs/agy-test-audit-ledger.md'
}
# FAIL CLOSED ON A TYPO. This map is keyed by discipline name and consulted with ContainsKey, so a
# misspelled key does not error - it silently checks nothing, and the guard certifies exactly what it
# stopped checking. Reconcile it against the roster that is actually iterated.
foreach ($k in $ledgerFor.Keys) {
    if ($skills -notcontains $k) {
        Fail "check-agy-discipline-skills : ledger map names '$k', which is not a linted discipline - its ledger check would never run"
    }
}

foreach ($skill in $skills) {
    $rel = "clavity-dotnet/plugin/skills/$skill/SKILL.md"
    $path = Join-Path $Root $rel
    if (-not (Test-Path $path)) { Fail "MISSING: $rel"; continue }
    $raw = Get-Content -Raw $path
    # An empty (0-byte) file makes Get-Content -Raw return $null; guard before any .Contains() so we fail
    # with a clear message instead of an unhandled null-deref terminating error (capstone R1, Cascade).
    if ([string]::IsNullOrEmpty($raw)) { Fail "EMPTY: $rel"; continue }

    # (b) frontmatter name matches dir. Scope the check to the REAL frontmatter block (between the first two
    # '---' fences) so a stray 'name:' smuggled into the BODY plus any body '---' cannot falsely satisfy it
    # (capstone R1, Protocol/Mechanism: the old lazy '(?ms).*?' spanned past the closing fence -> false-GREEN).
    if ($raw -match "(?s)\A---\r?\n(?<fm>.*?)\r?\n---\r?\n") {
        # OPTIONAL QUOTES, capstone R4: YAML lets a scalar be quoted, and `name: "agy-first"` is the
        # same value as `name: agy-first`. MEASURED before this fix - the quoted form produced a false
        # RED reading "frontmatter 'name:' must equal 'agy-first'" on a valid file. The quote characters
        # are matched as a pair-insensitive option rather than a balanced pair, which is deliberate: the
        # frontmatter parser downstream is YAML's, not this regex's, and a mismatched pair is that
        # parser's problem to report, not a shape this gate should invent an opinion about.
        # \x22 is the REGEX escape for a double quote, not a PowerShell one. Writing the character
        # literally would terminate this double-quoted string and the whole file would stop parsing.
        if ($Matches['fm'] -notmatch "(?m)^name:\s*[\x22']?$skill[\x22']?\s*$") {
            Fail "$rel : frontmatter 'name:' must equal '$skill'"
        }
    } else {
        Fail "$rel : missing or malformed frontmatter block (expected '---' ... '---' at file start)"
    }
    # (c) all required [VERDICT] forms for THIS skill present. Fail loud if a skill was enrolled in $skills
    # but never mapped in $requiredVerdicts (else `foreach` over $null would silently verify nothing).
    if (-not $requiredVerdicts.ContainsKey($skill)) {
        Fail "$rel : no required-verdict set mapped for skill '$skill'"
    }
    foreach ($v in $requiredVerdicts[$skill]) {
        if (-not $raw.Contains($v)) { Fail "$rel : missing required verdict form '$v'" }
    }
    # (d) pure ASCII (mojibake guard)
    $nonAscii = [regex]::Matches($raw, '[^\x00-\x7F]')
    if ($nonAscii.Count -gt 0) {
        Fail "$rel : contains $($nonAscii.Count) non-ASCII char(s); first = U+$([int][char]$nonAscii[0].Value | ForEach-Object { $_.ToString('X4') })"
    }
    # (e) both transports named inline
    if (-not $raw.Contains('agy_ask'))               { Fail "$rel : missing dotnet transport 'agy_ask'" }
    if (-not $raw.Contains('clavity ask --review-only')) { Fail "$rel : missing classic transport 'clavity ask --review-only'" }
    # (f) marker-contract constant referenced
    if (-not $raw.Contains($markerConstant)) { Fail "$rel : missing marker-contract constant '$markerConstant'" }

    # (g) 21.2 TWO AXES, ONE WORD - agy-capstone only, because it is the only discipline that CLASSES a
    # finding after the peer has typed it. `claim-type` is the PEER's axis (what KIND of claim this is);
    # `disposition` is the DRIVER's closed five-token AGY-SCOPE set, and `defect` is not one of those
    # five - which is exactly why the old wording, "survives disposition as a real `defect`", dangled.
    #
    # BOTH HALVES ARE REQUIRED, and the negative one alone would have a hole. "The old word must not
    # appear" is satisfied by DELETING the sentence outright, so the positive half pins the replacement
    # and the negative half pins the rename back. The suite carries one rejection row for each.
    # (h) 21.4 the INLINE JSON reply contract, in EXACTLY the two disciplines that declare a schema in
    # scripts/check-peer-reply-citations.py. agy-first and adversarial-panel-review have SCHEMAS entries
    # but reply in prose, and pasting the contract into them "for consistency" would recreate the
    # referent-free rule that got the whole of Task 3 withdrawn: a rule about a field the skill never asks
    # for.
    #
    # The second check is the one that catches a COPY-PASTE. These two blocks differ in three places, and
    # the discipline name in the checker invocation is the one that silently does the wrong thing: a
    # capstone brief naming agy-test-audit validates its rows against the AUDIT's keys, so `trigger` is
    # rejected and `missing_test` waved through, with nothing anywhere reporting a mismatch.
    if ($skill -in @('agy-capstone', 'agy-test-audit')) {
        if ($raw -notmatch '(?m)^\*\*Demand the JSON block in your payload too\*\*') {
            Fail "$rel : missing the inline JSON reply contract - the checker would be validating a shape nothing ever told the peer to emit"
        }
        $invocation = 'check-peer-reply-citations.py <reply.json> <sha> ' + $skill
        if (-not $raw.Contains($invocation)) {
            Fail "$rel : does not name its OWN checker invocation ('$invocation') - a discipline citing another's schema name validates against the wrong keys and reports nothing"
        }

        # CROSS-FILE ORACLE: the key list in the skill must match SCHEMAS in the checker, key for key.
        # Capstone R1 measured the gap this closes: the whole blockquoted key list could be DELETED while
        # the bold header above it stayed, and this linter still exited 0 - it pinned a heading and
        # certified a contract. That is the guard-fails-open shape, and the peer independently named the
        # same divergence as the thing most likely to be quietly wrong in six months: add a key to the
        # Python and the markdown, later drop it from the markdown, and nothing notices.
        #
        # The checker is resolved from $PSScriptRoot, NOT from $Root: $Root is the skills fixture the
        # suite stages, and the SCHEMAS registry is a real repository file. Resolving it from $Root would
        # red every rejection row in the suite on a missing checker.
        $checkerPath = Join-Path $PSScriptRoot 'check-peer-reply-citations.py'
        if (-not (Test-Path -LiteralPath $checkerPath)) {
            Fail "$rel : names a checker that is not there - $checkerPath"
        } else {
            # BOUNDED TO THE SCHEMAS BLOCK, and this is the SECOND instance of a class capstone R2 found
            # in the sibling guard below. That round bounded the ROSTER scan and left this one scanning
            # the whole file, so the class survived one line away from its own fix - which is what comes
            # of folding the instance a reviewer reports instead of enumerating the set.
            #
            # MEASURED at b9ea4bf, with a control. [regex]::Match returns the FIRST match, so a decoy
            # '"agy-capstone": [...]' in the module docstring is read as the registry entry. Both
            # directions were run: a decoy carrying WRONG keys made the oracle demand them of the
            # markdown ("expected, in order: wrong, keys, entirely"), and - the direction that matters -
            # a decoy carrying the CORRECT keys while the REAL entry had an appended key left the oracle
            # GREEN on a drifted registry. The control, the identical drift with no decoy, was CAUGHT.
            # A silently-appended key going green is the exact defect capstone R2 of the previous range
            # folded, arriving by a different route.
            $py = Get-SchemasBlock $checkerPath
            if ($null -eq $py) {
                Fail "$rel : did not find exactly ONE 'SCHEMAS = {' assignment in $checkerPath - it is missing, unparseable, or DUPLICATED - so the inline contract cannot be checked against it"
                continue
            }
            $m  = [regex]::Match($py, '"' + [regex]::Escape($skill) + '":\s*\[(?<keys>[^\]]*)\]')
            if (-not $m.Success) {
                Fail "$rel : scripts/check-peer-reply-citations.py declares no SCHEMAS entry for '$skill', so its inline contract is unenforceable"
            } else {
                $declared = [regex]::Matches($m.Groups['keys'].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
                # PIN THE LIST, NOT MERE MEMBERSHIP - and this is the second attempt, because the first
                # was proven hollow by its own control. Asking whether each key appears SOMEWHERE in the
                # blockquote passes when a key is dropped from the enumeration but still mentioned in the
                # prose beneath it: deleting `trigger` from the key list left `Phrase `trigger` as a
                # FALSIFIABLE PREDICTION` two lines below, the guard found it, and the drop went green.
                # Matching the whole comma-separated sequence pins ORDER and MEMBERSHIP together.
                # The separator tolerates the markdown wrap: the list spans several '> ' lines.
                $seq = ($declared | ForEach-Object { '`' + [regex]::Escape($_) + '`' }) -join ',\s*(?:\r?\n>\s*)?'
                # ANCHORED AT BOTH ENDS, and this is the THIRD version of this guard. Capstone R2
                # measured what an unanchored sequence misses: it verifies the markdown is a SUPERSET
                # of SCHEMAS, so appending `smuggled` to the key list left the linter GREEN - the skill
                # would instruct the peer to emit a key the checker then rejects, which is exactly the
                # drift this oracle exists to prevent, running in the one direction nobody had tested.
                # The intro phrase and the closing period bound the list, so neither a prepended nor an
                # appended key can hide outside the matched span.
                $seq = 'and no others are accepted - ' + $seq + '\.'
                if ($raw -notmatch $seq) {
                    Fail "$rel : the inline contract's key list does not match SCHEMAS in scripts/check-peer-reply-citations.py - expected, in order: $($declared -join ', ')"
                }
            }
            if ($raw -notmatch '(?m)^ {0,3}>.*and no others are accepted') {
                Fail "$rel : the inline contract does not tell the peer that undeclared keys are REJECTED - the strictness is the contract's whole point"
            }
        }
    }

    if ($skill -eq 'agy-capstone') {
        if ($raw -match '(?m)survives disposition as a real') {
            Fail "$rel : the PEER-side axis must be named claim-type, not disposition - 'defect' is not one of the five AGY-SCOPE disposition tokens"
        }
        if (-not $raw.Contains('survives its `claim-type` as a real')) {
            Fail "$rel : missing the claim-type sentence - the PEER-side axis must be named claim-type"
        }
    }

    # (i) section 23: a discipline that owns a ledger must NAME that ledger's path. The letters in this
    # loop run in source order, so this one goes last; inserting it after (f) would leave them reading
    # f, i, g, h.
    #
    # WHAT THIS MEASURES, EXACTLY: that the path string appears somewhere in the skill, and that the file
    # it names is on disk. It does NOT measure that a row is REQUIRED - a skill naming the file in
    # passing prose, or inside an HTML comment, would pass. Pinning the requirement SENTENCE verbatim was
    # considered and rejected: every rewording would be a false RED, which this repository folded twice
    # in the section 21 capstone. The check asserts the diagnostic, not the wording, and the messages
    # below say only what was measured.
    if ($ledgerFor.ContainsKey($skill)) {
        if (-not $raw.Contains($ledgerFor[$skill])) {
            Fail "$rel : never names '$($ledgerFor[$skill])', so a completing verdict records nothing"
        }
        # And the file must EXIST. Naming a ledger that is not on disk is the False Safety Promise
        # shape - the clause reads as enforced while the record it points at is gone. An elseif, not a
        # second if: an absent clause should produce ONE diagnostic, and the existence check is
        # meaningless when the clause is already missing. Resolved from $Root, which defaults to the
        # repository root and which the suite's scratch fixture stages.
        # -PathType Leaf, not a bare Test-Path: a bare Test-Path returns $true for a DIRECTORY, so
        # `mkdir docs/agy-test-audit-ledger.md` would satisfy this guard while the record it asserts does
        # not exist. MEASURED: bare -> True, -PathType Leaf -> False, on a directory of that name.
        elseif (-not (Test-Path -LiteralPath (Join-Path $Root $ledgerFor[$skill]) -PathType Leaf)) {
            Fail "$rel : names '$($ledgerFor[$skill])', which is not a FILE on disk - the clause points at nothing (a directory of that name does not count)"
        }
    }
}

# 13b: the driver's completeness checks only run when the ask NAMES its discipline. If a skill does not
# TELL the caller to name it, every consult from that discipline silently runs unchecked, and the driver's
# [13b] UNCHECKED notice is the only thing that would ever say so.
#
# THIS LIST IS FOUR, NOT THREE - and it is deliberately SEPARATE from $skills rather than an addition to
# it. $skills carries invariants adversarial-panel-review cannot satisfy: it is non-ASCII by design (69
# chars) and references no marker constant, being the one discipline with no debounce marker. Enrolling it
# there to reach this single check would red the linter on three unrelated invariants and invent
# requirements that discipline was never meant to meet. A separate list gets the coverage without the
# false failures. AGY-AFTER was previously covered by NO lint at all here.
# AGY-TEST-AUDIT 2026-08-31: the REVIEW-ONLY SAFETY ENVELOPE, required of all four review disciplines.
# MEASURED before this guard existed: deleting all 30 lines of the envelope from
# adversarial-panel-review/SKILL.md left this linter printing 'agy-discipline skills OK' with rc=0, and
# every other repo gate green with it. That envelope is the only thing standing between a consult and a
# peer that writes to the tree - and the peer HAS breached it twice in eight rounds on this repository,
# so it is load-bearing in practice and not merely on paper.
#
# HONEST LIMITATION, stated rather than hidden: these are literal-text needles, so they prove the steps
# are PRESENT, never that the skill's surrounding prose still means anything. A determined author can
# satisfy them without substance. They exist to catch DELETION and drift, which is the regression that
# was actually measured, not to certify the envelope's quality.
$envelopeSteps = @(
    'Snapshot before',
    'Forbidden-actions banner',
    'Permission to pass',
    'Point at files',
    'Diff after'
)

$disciplineNames = $skills + @('adversarial-panel-review')
foreach ($skill in $disciplineNames) {
    $rel = "clavity-dotnet/plugin/skills/$skill/SKILL.md"
    $path = Join-Path $Root $rel
    if (-not (Test-Path $path)) { Fail "MISSING: $rel"; continue }
    $raw = Get-Content -Raw $path
    if ([string]::IsNullOrEmpty($raw)) { Fail "EMPTY: $rel"; continue }
    $mandate = 'discipline: "' + $skill + '"'
    if (-not $raw.Contains($mandate)) {
        Fail "$rel : does not instruct the caller to pass $mandate - its consults will run UNCHECKED"
    }

    foreach ($step in $envelopeSteps) {
        if (-not $raw.Contains($step)) {
            Fail "$rel : missing review-only safety-envelope step '$step' - a consult from this discipline would run with no snapshot / forbidden-actions / diff-after discipline"
        }
    }
    # The sanctioned scratch directory is the other half of the envelope: without one, a
    # measure-and-reproduce framing sends the peer to write in the repository's working directory.
    if (-not $raw.Contains('.clavity/scratch/')) {
        Fail "$rel : names no sanctioned scratch directory (.clavity/scratch/) - a measure-and-reproduce consult would have nowhere to write but cwd"
    }

    # 21.1 the ANTI-WRAP-UP clause. MEASURED: several review rounds had their ENTIRE report displaced by a
    # closing pleasantry ("standing by for your feedback"), because what the driver collects is the peer's
    # FINAL message - and every one of those rounds already demanded a terminal token, so the token alone
    # does not fix it. Enforced across all FOUR disciplines (this loop), not just the three in $skills.
    #
    # THE NEEDLE PINS THE '> ' MARKER, NOT JUST THE WORDS - and that is the whole point of this guard.
    # MEASURED across all four skills: '> ' marks the ONE thing that is verbatim payload text (the 13b echo
    # demand) and nothing else uses it. The clause governs the PEER's reply; shipped unmarked it read as a
    # rule about the DRIVER's own output, which in agy-capstone contradicts ':213' ("Intermediate
    # fold-and-loop rounds report progress and loop; they emit **no** token"). An anchor on the bare words
    # would go green on exactly that broken form, so it matches '^> Put', deliberately.
    if ($raw -notmatch '(?m)^ {0,3}> Put nothing after the terminal token\.') {
        Fail "$rel : missing the anti-wrap-up clause as PAYLOAD text ('> Put nothing after the terminal token.') - unmarked, it reads as a rule about the driver's own reply, and a peer's closing pleasantry can displace its entire report"
    }
}

# ---------------------------------------------------------------------------------------------------
# THE ROSTER ITSELF, which nothing checked until AGY-CAPSTONE 2026-09-02. Every guard above asks whether
# a LISTED discipline is well-formed; not one asks whether the list is complete. Add a fifth discipline
# skill and forget $disciplineNames and this gate exits 0 having read none of it - a guard that fails
# open certifies exactly what it stopped checking, and an absence has no line for a reviewer to quote.
#
# THE ORACLE IS THE REGISTRY, NOT THE FOLDER LISTING, and the difference was measured rather than
# assumed. The reviewing peer proposed discovering skills with Get-ChildItem over the skills directory.
# Run: that fixture holds SEVEN skills, and only four are disciplines - ls-driving, ls-pairing and
# open-issues carry no verdict tokens, no transports and no marker constant, so discovery produced 38
# diagnostics and turned a green gate red on three files it was never meant to read. A correct finding
# with a fix that regresses the thing it fixes.
#
# SCHEMAS is the right source of truth because it is already the deliberate one: check-peer-reply-
# citations.py exits on a discipline it does not declare ("add it to SCHEMAS deliberately, never by
# defaulting"), so a fifth discipline must be registered there before it can be validated at all. This
# reconciles the two sides in the one direction the per-skill oracle above cannot see - it runs FOR each
# name in the roster, so a name absent from the roster is a question it never gets asked.
$checkerPath = Join-Path $PSScriptRoot 'check-peer-reply-citations.py'
if (-not (Test-Path -LiteralPath $checkerPath)) {
    Fail "roster reconciliation: the checker is not at $checkerPath, so the roster cannot be reconciled"
} else {
    # SCOPED TO THE SCHEMAS BLOCK, and capstone R2 measured why the unscoped version was worse than
    # useless. Scanning the whole file for a four-space-indented '"name": [' made this guard FAIL OPEN:
    # a phantom discipline named in the module DOCSTRING was reconciled clean and the gate exited 0,
    # while the checker itself exits "unknown discipline" on it at runtime - a gate certifying a
    # discipline the tool it guards would refuse. Measured across three smuggle shapes: the docstring
    # body smuggles, and both comment forms do NOT ('#' at column 0 fails '^\s{4}"', and four spaces
    # then '#' fails it too). I had convinced myself this failed CLOSED; the reviewing peer said open,
    # and it was right.
    #
    # THAT MEASUREMENT ENUMERATED THREE SHAPES, NOT EVERY SHAPE, and an earlier version of this comment
    # over-claimed by calling the docstring "the whole of the reachable surface" - false, because any
    # triple-quoted literal can hold the same text, not only a module docstring. It no longer matters
    # WHERE the text lives: Get-SchemasBlock counts the assignments and refuses to guess when there is
    # more than one, so a decoy is caught by arithmetic rather than by having been anticipated. The
    # location claim is recorded as history, and nothing depends on it.
    #
    # Bounding the scan is not the same as parsing Python, and this comment is the honest statement of
    # what remains: a string literal INSIDE the block at exactly four spaces would still smuggle. The
    # block holds only key/list pairs, so that shape has nowhere to live - but it is a text scan, not an
    # import, and it cannot be one: this module parses sys.argv at top level, so importing it to ask for
    # SCHEMAS.keys() would run the script.
    $blockBody = Get-SchemasBlock $checkerPath
    if ($null -eq $blockBody) {
        # FAILS CLOSED, deliberately. An unparseable registry is indistinguishable from an empty one,
        # and an empty one would report every roster name as unregistered - a true red for a false
        # reason. Say which it is.
        Fail "roster reconciliation: did not find exactly ONE 'SCHEMAS = {' assignment in $checkerPath - it is missing, unparseable, or DUPLICATED - so the roster cannot be reconciled at all"
        $registry = $disciplineNames        # suppress the misleading second diagnostic
    } else {
        $registry = [regex]::Matches($blockBody, '(?m)^\s{4}"(?<name>[^"]+)":\s*\[') |
                    ForEach-Object { $_.Groups['name'].Value }
    }
    $onlyInRegistry = @($registry | Where-Object { $_ -notin $disciplineNames })
    $onlyInRoster   = @($disciplineNames | Where-Object { $_ -notin $registry })
    if ($onlyInRegistry.Count -gt 0) {
        Fail ("roster reconciliation: check-peer-reply-citations.py declares SCHEMAS entries this linter never checks: " +
              ($onlyInRegistry -join ', ') + " - add them to `$disciplineNames or drop the entries")
    }
    if ($onlyInRoster.Count -gt 0) {
        Fail ("roster reconciliation: this linter checks disciplines the checker declares no SCHEMAS entry for: " +
              ($onlyInRoster -join ', ') + " - add the entries or drop them from `$disciplineNames")
    }
}

if ($fail) { Write-Error 'agy-discipline skill lint FAILED' -ErrorAction Continue; exit 1 }
Write-Output 'agy-discipline skills OK'
exit 0

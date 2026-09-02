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
        if ($Matches['fm'] -notmatch "(?m)^name:\s*$skill\s*$") {
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
    if ($skill -eq 'agy-capstone') {
        if ($raw -match '(?m)survives disposition as a real') {
            Fail "$rel : the PEER-side axis must be named claim-type, not disposition - 'defect' is not one of the five AGY-SCOPE disposition tokens"
        }
        if (-not $raw.Contains('survives its `claim-type` as a real')) {
            Fail "$rel : missing the claim-type sentence - the PEER-side axis must be named claim-type"
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
    if ($raw -notmatch '(?m)^> Put nothing after the terminal token\.') {
        Fail "$rel : missing the anti-wrap-up clause as PAYLOAD text ('> Put nothing after the terminal token.') - unmarked, it reads as a rule about the driver's own reply, and a peer's closing pleasantry can displace its entire report"
    }
}

if ($fail) { Write-Error 'agy-discipline skill lint FAILED' -ErrorAction Continue; exit 1 }
Write-Output 'agy-discipline skills OK'
exit 0

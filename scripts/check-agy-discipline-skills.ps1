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
$requiredVerdicts = @{
    'agy-first'      = @('[VERDICT: ALIGNED]', '[VERDICT: REJECTED - ', '[VERDICT: NEGOTIATE - ', '[VERDICT: SKIPPED-UNREACHABLE]')
    'agy-capstone'   = @('[VERDICT: ALIGNED]', '[VERDICT: REJECTED - ', '[VERDICT: NEGOTIATE - ', '[VERDICT: SKIPPED-UNREACHABLE]')
    'agy-test-audit' = @('[VERDICT: EXHAUSTIVE]', '[VERDICT: GAPS FOUND]', '[VERDICT: agy-required-but-unreachable]')
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
}

if ($fail) { Write-Error 'agy-discipline skill lint FAILED' -ErrorAction Continue; exit 1 }
Write-Output 'agy-discipline skills OK'
exit 0

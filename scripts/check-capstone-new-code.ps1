# scripts/check-capstone-new-code.ps1
# READ-ONLY. Answers one question for AGY-CAPSTONE (ROADMAP section 24): does the range introduce NEW
# CODE, such that an AGY-FIRST design consult is mandatory before the fold ships?
#
# Exit 0 = no new code, proceed.       Exit 3 = TRIGGER FIRED, consult required.
# Exit 2 = the question could not be answered (fail CLOSED, never silently "no").
#
# WHY A SCRIPT AND NOT A JUDGEMENT CALL: section 24's whole point is that the trigger is evaluated
# mechanically, never by the agent that would benefit from skipping it. Do not add a flag that lets a
# caller suppress the trigger.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaseRef,
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'

# A path is TEST code if any of these match. Kept deliberately broad: a false "this is a test" only
# ever SUPPRESSES the consult, so each entry must be one nothing shipped can match.
$TestPatterns = @(
    '(^|/)tests?/'
    '\.Tests\.ps1$'
    '_test\.(rs|go|py)$'
    '(^|/)test_[^/]+\.py$'
)

function Test-IsTestPath([string]$p) {
    foreach ($pat in $TestPatterns) { if ($p -match $pat) { return $true } }
    return $false
}

# A new DECLARATION, per language. Anchored on the '+' of the diff so only ADDED lines count.
$DeclarationPatterns = @(
    '^\+\s*function\s+[A-Za-z_]'                       # PowerShell, bash 'function f'
    '^\+\s*[A-Za-z_][A-Za-z0-9_]*\s*\(\)\s*\{'         # bash 'f() {'
    '^\+\s*(pub\s+)?(async\s+)?fn\s+[A-Za-z_]'         # Rust
    '^\+\s*(public|private|internal|protected)\s+.*\b(class|record|struct|interface|enum)\s+'  # C# types
    # C# METHODS, not just types. AGY-AFTER round 1 (Mechanism Gamer) caught this: with types-only,
    # an agent that wants to skip the consult drops its new code into a `public void Foo()` on an
    # EXISTING class and the trigger stays silent - which is the single most common unit of new C#
    # code in this repository. Matches an access modifier followed by a return type and a call-shaped
    # name, excluding control-flow keywords that also take parentheses.
    '^\+\s*(public|private|internal|protected)\s+(static\s+|async\s+|override\s+|virtual\s+|sealed\s+)*[A-Za-z_][A-Za-z0-9_<>,\[\]\.\?]*\s+[A-Za-z_][A-Za-z0-9_]*\s*\('
    # CONSTRUCTORS have NO return type, so the two-identifier pattern above cannot see them. AGY-AFTER
    # round 2 (Mechanism Gamer) caught that fold 4 left this bypass open: nest the new logic in a
    # constructor and the trigger stays silent. Access modifier, then a Capitalized name, then '('.
    '^\+\s*(public|private|internal|protected)\s+[A-Z][A-Za-z0-9_]*\s*\('
    # STATIC CONSTRUCTORS carry NO access modifier at all - `static MyClass()` - so the pattern above
    # cannot see them either. AGY-AFTER round 3 (Cascade Analyst) caught that round 2's constructor
    # fix left this last sliver of the bypass open.
    '^\+\s*static\s+[A-Z][A-Za-z0-9_]*\s*\(\s*\)'
    # TUPLE RETURNS start with a parenthesis - `public (int, int) Get()` - which the two-identifier
    # pattern also misses. Same round, same seat.
    '^\+\s*(public|private|internal|protected)\s+(static\s+|async\s+)*\([^)]*\)\s+[A-Za-z_][A-Za-z0-9_]*\s*\('
    '^\+\s*(def|class)\s+[A-Za-z_]'                    # Python
)

Push-Location $Root
try {
    # Resolve the base ref FIRST. An unresolvable ref must fail closed - it is not "no new code".
    & git rev-parse --verify --quiet "$BaseRef^{commit}" > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Output "check-capstone-new-code: could not resolve base ref '$BaseRef'"
        exit 2
    }

    # THE INPUT IS PART OF THE TRIGGER. Section 24 says the trigger is evaluated mechanically and never
    # by the agent that wants to skip it - but an agent that supplies its own BaseRef can hand us HEAD,
    # get an empty diff, and collect a clean exit 0 as PROOF that no consult was owed. That is a guard
    # certifying exactly what it stopped checking. A base that IS head is not a range; refuse it.
    $baseSha = (& git rev-parse "$BaseRef^{commit}").Trim()
    $headSha = (& git rev-parse 'HEAD^{commit}').Trim()
    if ($baseSha -eq $headSha) {
        Write-Output "check-capstone-new-code: base ref '$BaseRef' resolves to HEAD - that is an empty range, not a clean result. Supply the round's recorded base."
        exit 2
    }

    $fired = [System.Collections.Generic.List[string]]::new()

    # --- Rule A: a NEW FILE in non-test code -------------------------------------------------
    # -z gives NUL-separated, UNQUOTED paths. Without it git QUOTES any path containing a space or a
    # non-ASCII byte ("my file.ps1"), and the captured quotes then defeat Test-IsTestPath's anchors -
    # a path the exclusion should have caught sails through as shippable. The peer flagged this as the
    # one thing it could not judge without running it; measured, git does quote such paths, so -z is
    # the fix rather than a regex that strips quotes.
    $nameStatus = (& git diff --name-status -z "$BaseRef..HEAD") -split "`0" | Where-Object { $_ -ne '' }

    # A RENAME and a COPY create a file too. `git diff --name-status` emits R### / C### with TWO paths
    # (old then new), so anchoring on '^A' alone - as this rule first did - misses every new file that
    # arrived by rename or copy. AGY-AFTER round 1 finding, folded.
    # THE else IS EXHAUSTIVE ON PURPOSE, and that is a correctness property rather than tidiness.
    # AGY-AFTER round 2 (Cascade Analyst) caught an earlier draft matching only '^[MTD]': a status this
    # parser does not know - U (unmerged), X (unknown), B (broken) - fell through ALL branches, so its
    # path was never consumed, the index desynced by one, and the NEXT iteration read that path as a
    # status. A path beginning with 'A' then registered as a phantom new file. Every git status carries
    # exactly ONE path except R and C, which carry two, so branching on that alone cannot desync.
    for ($i = 0; $i -lt $nameStatus.Count; $i++) {
        $status = $nameStatus[$i]
        if ($status -match '^[RC]') {
            $null = $nameStatus[++$i]          # the OLD path, which we do not care about
            $path = $nameStatus[++$i]          # the NEW path, which is the one that now exists
            if (-not (Test-IsTestPath $path)) { $fired.Add("new-file-via-$($status.Substring(0,1)): $path") }
        }
        else {
            $path = $nameStatus[++$i]          # EVERY other status carries exactly one path
            if ($status -match '^A' -and -not (Test-IsTestPath $path)) { $fired.Add("new-file: $path") }
        }
    }

    # --- Rules B and C need the patch, and only for non-test paths ---------------------------
    # -U0 keeps hunks minimal; the function context still rides in the @@ header, which is what
    # rule C reads. Generated and vendored paths are excluded the same way the capstone excludes
    # them from review.
    $patch = & git diff -U0 "$BaseRef..HEAD" -- . `
        ':(exclude)*.lock' ':(exclude)*.min.js' ':(exclude)package-lock.json'

    $currentFile = $null
    $currentIsTest = $false
    $hunkHeader = $null
    $hunkAdds = 0
    $hunkDels = 0

    function Complete-Hunk {
        if ($null -ne $script:hunkHeader -and -not $script:currentIsTest) {
            # Rule C: git named an enclosing function AND both sides are substantial.
            if ($script:hunkHeader.Trim() -ne '' -and $script:hunkAdds -ge 5 -and $script:hunkDels -ge 5) {
                $script:fired.Add("whole-function-rewrite: $($script:currentFile) [$($script:hunkHeader.Trim())]")
            }
        }
        $script:hunkHeader = $null; $script:hunkAdds = 0; $script:hunkDels = 0
    }

    foreach ($line in $patch) {
        if ($line -match '^\+\+\+ b/(.+)$') {
            Complete-Hunk
            $currentFile = $Matches[1].Trim()
            $currentIsTest = Test-IsTestPath $currentFile
            continue
        }
        if ($line -match '^@@ [^@]+ @@(.*)$') {
            Complete-Hunk
            $hunkHeader = $Matches[1]
            continue
        }
        if ($currentIsTest) { continue }
        if ($line -match '^\+' -and $line -notmatch '^\+\+\+') {
            $hunkAdds++
            foreach ($pat in $DeclarationPatterns) {
                if ($line -match $pat) {
                    $fired.Add("new-declaration: $currentFile : $($line.TrimStart('+').Trim())")
                    break
                }
            }
        }
        elseif ($line -match '^-' -and $line -notmatch '^---') { $hunkDels++ }
    }
    Complete-Hunk

    if ($fired.Count -eq 0) {
        Write-Output "check-capstone-new-code: no new code in $BaseRef..HEAD - AGY-FIRST consult not required."
        exit 0
    }

    Write-Output "check-capstone-new-code: TRIGGER FIRED - AGY-FIRST consult is MANDATORY before this fold ships."
    # Report EVERY rule that fired. Reporting only the first understates the blast radius.
    $fired | Sort-Object -Unique | ForEach-Object { Write-Output "  - $_" }
    exit 3
}
finally { Pop-Location }

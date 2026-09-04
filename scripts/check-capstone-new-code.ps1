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

# CODE extensions Rule A is allowed to fire on (FIX 4, owner ruling 2026-09-04). Section 24's own
# wording is "NON-TEST shipped CODE" - a new .md/.json/.yml is not code, and this repo tracks 264
# markdown files and adds specs, roadmap sections and ledger rows constantly, so an unscoped Rule A
# fires on documentation-only commits until the gate is noise the driver waves through. .yml/.yaml
# is admitted ONLY under a CI workflow path because a workflow file is executable configuration; a
# random data YAML is not. Do NOT "simplify" this back to "any extension" or drop the workflow-path
# qualifier for yml/yaml - both are load-bearing per the ruling.
$CodeExtensions = @('.ps1', '.sh', '.cs', '.rs', '.py', '.js', '.ts')

# EXTENSIONLESS EXECUTABLE files, matched by leaf NAME (FIX 2, adversarial capstone round 2026-09-04
# - a REGRESSION from the extension allow-list above). The allow-list is scoped by extension, but
# `justfile`/`Makefile`/`Dockerfile` carry none and are executable build/deploy DEFINITIONS, not
# documentation - this repo ships a live 12KB justfile that Rules A/B/C stopped scanning the moment
# the extension allow-list shipped. Owner ruling 2026-09-04: WIDEN the allow-list, do not convert it
# to a deny-list. `.gitignore` is deliberately NOT here - it is declarative configuration, nothing in
# it executes.
$CodeExecutableNames = @('justfile', 'Justfile', 'Makefile', 'makefile', 'Dockerfile')

function Test-IsCodeFile([string]$p) {
    $ext = [System.IO.Path]::GetExtension($p)
    if ($CodeExtensions -contains $ext) { return $true }
    if (($ext -eq '.yml' -or $ext -eq '.yaml') -and $p -match '(^|/)\.github/workflows/') { return $true }
    if ($ext -eq '' -and ($CodeExecutableNames -contains [System.IO.Path]::GetFileName($p))) { return $true }
    return $false
}

# FIX 1 (adversarial capstone round 2026-09-04, severity 0, SILENT BYPASS - the most important of the
# four): decodes a path from a `+++`/`---` diff header that git may have wrapped in double quotes. git
# quotes a path (core.quotepath, on by default) and C-escapes every byte it treats as "unsafe" - each
# non-ASCII byte, plus \, ", tab and newline - so src/café.ps1 (UTF-8 bytes for é = 0xC3 0xA9) is
# emitted as "b/src/caf\303\251.ps1". MEASURED on this machine, matches exactly.
#
# Each \NNN escape is ONE BYTE, and a multi-byte UTF-8 character therefore produces SEVERAL
# consecutive escapes that must be recombined at the BYTE level before decoding back to a .NET string
# - decoding one escape at a time as an independent character would corrupt anything outside ASCII.
# Returns $null when the text cannot be decoded (an escape this function does not recognise, or a
# truncated escape), so the caller can FAIL CLOSED instead of silently treating the file as absent.
#
# ⚠ Do NOT touch this for the space-in-path case - MEASURED, git leaves a path containing only a space
# UNQUOTED (`+++ b/src/my file.ps1` with a trailing tab), and the existing `.Trim()` in the caller
# already handles that. This function only has quoted input to decode.
function ConvertFrom-GitDiffPath([string]$raw) {
    if ($raw.Length -lt 2 -or $raw[0] -ne '"' -or $raw[$raw.Length - 1] -ne '"') {
        return $raw   # not quoted - already the literal path
    }
    $inner = $raw.Substring(1, $raw.Length - 2)
    $bytes = [System.Collections.Generic.List[byte]]::new()
    $i = 0
    while ($i -lt $inner.Length) {
        $c = $inner[$i]
        if ($c -ne '\') {
            if ([int]$c -gt 127) { return $null }   # git always escapes non-ASCII - unexpected shape
            $bytes.Add([byte][int]$c)
            $i++
            continue
        }
        if ($i + 1 -ge $inner.Length) { return $null }   # dangling backslash - cannot decode
        $next = $inner[$i + 1]
        if ($next -ge '0' -and $next -le '7') {
            if ($i + 3 -ge $inner.Length) { return $null }   # truncated octal escape
            $oct = $inner.Substring($i + 1, 3)
            if ($oct -notmatch '^[0-7]{3}$') { return $null }
            $bytes.Add([byte]([Convert]::ToInt32($oct, 8)))
            $i += 4
            continue
        }
        $mapped = switch ($next) {
            '\' { 92 }; '"' { 34 }; 't' { 9 }; 'n' { 10 }; default { -1 }
        }
        if ($mapped -eq -1) { return $null }   # an escape this parser does not recognise - fail closed
        $bytes.Add([byte]$mapped)
        $i += 2
    }
    return [System.Text.Encoding]::UTF8.GetString($bytes.ToArray())
}

# A new DECLARATION, per language, for files any extension applies to. Anchored on the '+' of the
# diff so only ADDED lines count.
$DeclarationPatterns = @(
    '^\+\s*function\s+[A-Za-z_]'                       # PowerShell, bash 'function f'
    '^\+\s*[A-Za-z_][A-Za-z0-9_]*\s*\(\)\s*\{'         # bash 'f() {'
    '^\+\s*(pub\s+)?(async\s+)?fn\s+[A-Za-z_]'         # Rust
    '^\+\s*(pub\s+)?(struct|enum|trait|union|type)\s+[A-Za-z_]'  # Rust TYPE declarations (FIX 2,
        # adversarial capstone round 2026-09-04): the fn pattern above is function-only, so a new
        # `pub struct`/`pub enum` with no fn anywhere in the diff bypassed the trigger entirely -
        # unlike C#, whose patterns already cover class/record/struct/interface/enum.
    '^\+\s*(def|class)\s+[A-Za-z_]'                    # Python
)

# C#-ONLY declaration patterns (FIX 1, code-quality review 2026-09-04). Applied only when the
# current file's path ends in '.cs' - the parsing loop already tracks it as $currentFile. All five
# ORIGINAL patterns below require a literal access-modifier first token, so a modifier-less
# declaration - legal, idiomatic C#, e.g. `static void Spawn(LaunchCommand cmd, bool wait)` at
# clavity-dotnet/src/Clavity.Cli/Program.cs:117 - evaded every one of them. Making the modifier
# optional in a pattern applied to EVERY file (as the last entry below does) would, if applied
# repo-wide, fire on ordinary two-identifier lines in bash/PowerShell diffs - so that entry is
# scoped to C# files only, alongside the five unchanged originals.
$CSharpDeclarationPatterns = @(
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
    # MODIFIER-LESS method/constructor declarations (FIX 1, new). No access modifier is required by
    # C#; a member defaults to `private` (or, on a top-level type, `internal`) when none is written.
    # An optional run of static/async/override/virtual/sealed, then a return type, then a name, then
    # '('. Scoped to .cs files only - see the block comment above.
    '^\+\s*(static\s+|async\s+|override\s+|virtual\s+|sealed\s+)*[A-Za-z_][A-Za-z0-9_<>,\[\]\.\?]*\s+[A-Za-z_][A-Za-z0-9_]*\s*\('
    # AUTO-PROPERTIES carry NO parentheses at all - `public string Name { get; set; }` - so every
    # pattern above, which all require a trailing '(', is blind to them (FIX 3, adversarial capstone
    # round 2026-09-04). Access modifier, optional modifiers, a TYPE that is explicitly NOT one of the
    # five type-declaration keywords via the negative lookahead - without that exclusion this pattern
    # would ALSO match `public class Thing {` / `public struct Foo {` and double-report the very line
    # the first C# pattern above already reports - then a name, then '{'. Scoped to .cs files only.
    '^\+\s*(public|private|internal|protected)\s+(static\s+|readonly\s+|virtual\s+|override\s+|abstract\s+|sealed\s+)*(?!(class|record|struct|interface|enum)\b)[A-Za-z_][A-Za-z0-9_<>,\[\]\.\?]*\s+[A-Za-z_][A-Za-z0-9_]*\s*\{'
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

    # --- Rule A: a NEW FILE in non-test, non-generated, CODE-extension paths -----------------
    # -z gives NUL-separated, UNQUOTED paths. Without it git QUOTES any path containing a space or a
    # non-ASCII byte ("my file.ps1"), and the captured quotes then defeat Test-IsTestPath's anchors -
    # a path the exclusion should have caught sails through as shippable. The peer flagged this as the
    # one thing it could not judge without running it; measured, git does quote such paths, so -z is
    # the fix rather than a regex that strips quotes.
    # Generated and vendored paths are excluded the same way the capstone excludes them from review -
    # this call previously had no exclusions at all (FIX 2, code-quality review 2026-09-04) even
    # though the comment always claimed it did, so a first-time-added package-lock.json fired
    # `new-file`. Kept even with the FIX 4 extension allow-list below because '*.min.js' would
    # otherwise pass the '.js' allow-list.
    $nameStatus = (& git diff --name-status -z "$BaseRef..HEAD" -- . `
        ':(exclude)*.lock' ':(exclude)*.min.js' ':(exclude)package-lock.json') -split "`0" | Where-Object { $_ -ne '' }

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
            if ((-not (Test-IsTestPath $path)) -and (Test-IsCodeFile $path)) { $fired.Add("new-file-via-$($status.Substring(0,1)): $path") }
        }
        else {
            $path = $nameStatus[++$i]          # EVERY other status carries exactly one path
            if ($status -match '^A' -and (-not (Test-IsTestPath $path)) -and (Test-IsCodeFile $path)) { $fired.Add("new-file: $path") }
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
    $currentIsCode = $false
    $hunkHeader = $null
    $hunkAdds = 0
    $hunkDels = 0

    function Complete-Hunk {
        if ($null -ne $script:hunkHeader -and -not $script:currentIsTest -and $script:currentIsCode) {
            # Rule C: git named an enclosing function AND both sides are substantial.
            if ($script:hunkHeader.Trim() -ne '' -and $script:hunkAdds -ge 5 -and $script:hunkDels -ge 5) {
                $script:fired.Add("whole-function-rewrite: $($script:currentFile) [$($script:hunkHeader.Trim())]")
            }
        }
        $script:hunkHeader = $null; $script:hunkAdds = 0; $script:hunkDels = 0
    }

    foreach ($line in $patch) {
        if ($line -match '^\+\+\+ (.+)$') {
            Complete-Hunk
            $rawPath = $Matches[1].Trim()
            $decoded = ConvertFrom-GitDiffPath $rawPath
            if ($null -ne $decoded -and $decoded -match '^b/(.+)$') {
                # The common case, quoted or not (FIX 1): a real path on the 'after' side.
                $currentFile = $Matches[1]
                $currentIsTest = Test-IsTestPath $currentFile
                $currentIsCode = Test-IsCodeFile $currentFile
            }
            elseif ($rawPath -eq '/dev/null') {
                # The 'after' side of a pure deletion - nothing here to classify, and a deletion-only
                # hunk carries no '+' line for Rules B/C to scan regardless.
                $currentFile = $null
                $currentIsTest = $false
                $currentIsCode = $false
            }
            else {
                # FAIL CLOSED (FIX 1): this +++ line's path could not be parsed - a quoting/escaping
                # shape this function does not recognise. Treat the file as CODE rather than silently
                # skipping it. A gate an agent runs on itself must never fail toward silence.
                $currentFile = $rawPath
                $currentIsTest = $false
                $currentIsCode = $true
            }
            continue
        }
        if ($line -match '^@@ [^@]+ @@(.*)$') {
            Complete-Hunk
            $hunkHeader = $Matches[1]
            continue
        }
        if ($currentIsTest) { continue }
        # FIX 1 (owner ruling 2026-09-04): Rule A is scoped to code-extension paths via
        # Test-IsCodeFile, but Rules B/C read every non-test file's added lines regardless of
        # extension - so a documentation-only change containing a declaration-shaped line (e.g.
        # a README code sample) fired the mandatory consult. Mirror the same allow-list here.
        if (-not $currentIsCode) { continue }
        if ($line -match '^\+' -and $line -notmatch '^\+\+\+') {
            $hunkAdds++
            # FIX 1: the C#-only set applies only when the current file is a .cs file - applying its
            # modifier-optional entry to every file would false-positive on ordinary two-identifier
            # lines in bash/PowerShell diffs.
            $patternsToCheck = $DeclarationPatterns
            if ($currentFile -match '\.cs$') { $patternsToCheck = $DeclarationPatterns + $CSharpDeclarationPatterns }
            foreach ($pat in $patternsToCheck) {
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

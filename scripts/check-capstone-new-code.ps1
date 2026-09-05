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

# Rule B round-trips a path read FROM git (via `git diff --name-only -z`) back INTO git (via
# `git show "<ref>:<path>"`) to materialise both versions for ast-grep. MEASURED: without this, a
# non-ASCII path (src/café.rs) captures correctly for DISPLAY, but re-encoding it as a process
# argument under the default console encoding corrupts it - `git show` then answers "fatal: path
# 'src/caf├⌐.rs' does not exist", Rule B silently treats the file as absent, and the range reads as
# no new code. Rule A never hit this because it only ever STRING-MATCHES such a path; it was Rule B's
# round-trip that introduced the need for this.
[System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8

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

# RULE B, replaced 2026-09-05 (owner ruling): the regex engine above this comment used to live here.
# It produced the same finding class - a declaration shape nobody had enumerated a regex for yet - in
# three consecutive adversarial rounds (Rust types, C# properties, Python `async def`), because a
# regex enumerates SHAPES and every enumeration is incomplete by construction. Rule B now asks
# ast-grep to parse both sides of the diff and diff the AST-level declaration NAMES it finds, so a
# shape the old regex list never anticipated is caught by the same mechanism as everything else -
# see Get-AstGrepDeclarationNames below.
#
# ast-grep is REQUIRED for Rule B to run - see the PATH check right before Push-Location. Never
# invent a bypass that lets Rule B silently no-op when ast-grep is missing; a gate an agent runs on
# itself must never fail toward silence (the same principle the base-ref checks above already apply).

# Maps a changed file's EXTENSION to the ast-grep language name Rule B parses it as. An extension not
# in this map has no ast-grep grammar available on this machine - MEASURED, `ast-grep --lang
# powershell` answers "powershell is not supported!" - and Rule B cannot run on it. That gap is
# OWNER-ACCEPTED (.ps1 is this repo's largest tracked language, 105 files, and the owner was shown
# that before ruling): Rule A and Rule C still apply to such a file, but Rule B must SAY it skipped
# the file rather than silently doing nothing - see the RULE-B-SKIPPED line below.
$AstGrepLanguageByExtension = @{
    '.cs' = 'CSharp'
    '.rs' = 'Rust'
    '.py' = 'Python'
    '.js' = 'JavaScript'
    '.ts' = 'TypeScript'
    '.sh' = 'Bash'
}

# The tree-sitter NODE KINDS Rule B looks for per language - "at minimum: functions, classes/
# structs/enums/traits/interfaces/records, and methods/properties where the language has them"
# (owner ruling). Each kind is matched via `has: {field: name, pattern: $NAME}` (see
# Get-AstGrepDeclarationNames), which captures the declared NAME regardless of which modifiers
# (public/static/async/sealed/... in any combination) precede it - a plain `ast-grep run --pattern`
# would need one literal pattern PER MODIFIER COMBINATION to match what this one kind+field rule
# matches, which is exactly the enumerate-every-shape brittleness this replacement exists to end.
# MEASURED per kind against hand-built fixtures before this list was relied on (0/1/2/3-modifier C#
# methods, static/instance/tuple-return methods, static and instance constructors, auto-properties,
# Rust items with and without `pub`, Python `def`/`async def`/`class`, JS/TS functions/classes/
# methods/fields, both bash function forms `function f() {}` and `f() {}`).
$AstGrepKindsByLanguage = @{
    'CSharp'     = @('class_declaration', 'struct_declaration', 'enum_declaration', 'interface_declaration', 'record_declaration', 'method_declaration', 'constructor_declaration', 'property_declaration')
    'Rust'       = @('function_item', 'struct_item', 'enum_item', 'trait_item', 'union_item', 'type_item')
    'Python'     = @('function_definition', 'class_definition')   # function_definition covers `async def` too - MEASURED, one kind matches both.
    'JavaScript' = @('function_declaration', 'class_declaration', 'method_definition')
    'TypeScript' = @('function_declaration', 'class_declaration', 'interface_declaration', 'type_alias_declaration', 'method_definition', 'public_field_definition')
    'Bash'       = @('function_definition')   # covers BOTH `function f() {}` and bare `f() {}` - MEASURED.
}

# Builds the `ast-grep scan --inline-rules` document for one language: one YAML rule per node kind,
# joined by the `---` separator the CLI documents for running several rules in one process. Each rule
# asks for the node's `name` FIELD specifically (not a hand-written pattern for the whole
# declaration) so it does not care what modifiers surround that field - see the block comment above.
function Get-AstGrepInlineRules([string]$Lang) {
    $rules = $AstGrepKindsByLanguage[$Lang] | ForEach-Object {
        "id: k_$_`nlanguage: $Lang`nrule:`n  kind: $_`n  has:`n    field: name`n    pattern: `$NAME"
    }
    return ($rules -join "`n---`n")
}

# Runs ast-grep against one version (base or HEAD) of one file's content and returns the SET of
# declaration names it finds, for every kind $Lang has registered. $Content is written to a TEMP
# file carrying the SAME extension as the real path - ast-grep's own file-type discovery filters by
# extension even when the rule's `language:` is given explicitly (MEASURED: an identical .cs fixture
# saved without an extension matched nothing), so the temp file must keep it.
function Get-AstGrepDeclarationNames([string]$Lang, [string]$Content, [string]$Extension) {
    $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "ccnc-astgrep-$([guid]::NewGuid().ToString('N'))$Extension"
    try {
        Set-Content -Path $tmpFile -Value $Content -NoNewline -Encoding utf8
        $rulesText = Get-AstGrepInlineRules $Lang
        $jsonText = & ast-grep scan --inline-rules $rulesText --json=compact $tmpFile 2>$null
        # 🔴 FAIL CLOSED ON A FAILED PARSE. Capstone R5, and it corrected a DISPOSITION of mine: I had
        # ruled tree-sitter grammar drift "not severity 0 because no command exits non-zero". MEASURED,
        # that was wrong - `ast-grep scan` with an invalid kind exits **8**:
        #     Kind `nonexistent_kind` is invalid.   ast-grep exit=8
        # (control: the same shape with a valid kind exits 0). Node kinds are grammar names, not a
        # stable API, so a version bump can invalidate one.
        #
        # Without this check that exit code was DISCARDED - stderr to $null, empty stdout, `return @()`
        # - and an empty name set is indistinguishable from "this file declares nothing". Every
        # declaration in the file would then look unchanged and the gate would answer "no new code".
        # That is FAIL-OPEN in the one place that must fail closed: a gate an agent runs on ITSELF.
        if ($LASTEXITCODE -ne 0) {
            Write-Output "check-capstone-new-code: ast-grep exited $LASTEXITCODE parsing a $Lang file - Rule B cannot answer, and an unanswered question is not a 'no'."
            Write-Output "  (a node kind in `$AstGrepKindsByLanguage may no longer exist in this ast-grep's grammar)"
            exit 2
        }
        if ([string]::IsNullOrWhiteSpace($jsonText)) { return @() }
        $matches = $jsonText | ConvertFrom-Json
        # KEYED BY KIND, not bare name (MEASURED bug, folded before this shipped): a C# constructor is
        # ALWAYS named after its enclosing class - `class Widget { Widget(int n) {} }` - so a bare-name
        # set diff sees "Widget" already present (from class_declaration) and masks a brand-new
        # constructor entirely. $_.ruleId is "k_<kind>" (see Get-AstGrepInlineRules), so pairing it with
        # NAME keeps a same-named declaration of a DIFFERENT kind visible as its own entry.
        return @($matches | ForEach-Object { $n = $_.metaVariables.single.NAME.text; if ($n) { "$($_.ruleId)::$n" } } | Where-Object { $_ } | Sort-Object -Unique)
    }
    finally {
        Remove-Item -Path $tmpFile -ErrorAction SilentlyContinue
    }
}

# POWERSHELL, via the parser built into the runtime this script ALREADY executes in - no ast-grep, no
# new dependency. ast-grep has no PowerShell grammar (MEASURED: `--lang powershell` answers
# "powershell is not supported!"), and .ps1 is this repository's largest tracked language at 105 files.
# The gate script itself is PowerShell, so leaving Rule B blind here meant the gate could not see a new
# function appended to its OWN source - MEASURED, that returned exit 0 and would let the gate be
# silently disabled. Owner ruling 2026-09-05 after an AGY-FIRST consult that independently reached the
# same answer.
#
# Returns the SAME "<kind>::<name>" shape Get-AstGrepDeclarationNames returns, so the caller's set-diff
# is identical for both engines. KEYED BY KIND for the same measured reason recorded there: a `class Foo`
# and a `function Foo` are different declarations and must not collapse into one entry.
function Get-PowerShellDeclarationNames([string]$Content) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Content, [ref]$tokens, [ref]$errors)
    if ($null -eq $ast) { return @() }
    # A file with syntax errors still yields a PARTIAL ast here rather than $null, and that is what we
    # want: a half-parseable file should surrender the declarations it can, not silently contribute none.
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        # A `filter` is a FunctionDefinitionAst with IsFilter set - same node type, different keyword,
        # and it is executable code exactly as a function is.
        $kind = if ($f.IsFilter) { 'ps_filter' } else { 'ps_function' }
        if ($f.Name) { $out.Add("${kind}::$($f.Name)") }
    }
    foreach ($t in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.TypeDefinitionAst] }, $true)) {
        $kind = if ($t.IsEnum) { 'ps_enum' } else { 'ps_class' }
        if ($t.Name) { $out.Add("${kind}::$($t.Name)") }
    }
    return @($out | Sort-Object -Unique)
}

# The extensions Rule B parses with the NATIVE PowerShell parser rather than ast-grep.
$PowerShellExtensions = @('.ps1', '.psm1')

# ast-grep ABSENT -> FAIL CLOSED, never silently "no new code". Rule B cannot run without it, and a
# gate an agent runs on itself must never fail toward silence - the same principle the base-ref
# checks below apply to a bad BaseRef. Checked before Push-Location so it fails fast regardless of
# $Root.
if (-not (Get-Command ast-grep -ErrorAction SilentlyContinue)) {
    Write-Output "check-capstone-new-code: ast-grep is not on PATH - Rule B (new AST declarations) cannot run, and the question cannot be answered."
    exit 2
}

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
                #
                # ALSO FOLD (adversarial round 2026-09-05): only the CODE-ness fails closed. Forcing
                # $currentIsTest to $false here too meant an unparseable TEST path (still decodable as
                # a path by Test-IsTestPath even when ConvertFrom-GitDiffPath's octal-escape decoder
                # gives up) was silently PROMOTED to production code and its added lines scanned by
                # Rules B/C - a false positive, and the opposite of what "fail closed" is supposed to
                # protect: fail closed means "when in doubt, still require the consult", not "when in
                # doubt, invent a test exemption's negation". Test-IsTestPath runs on the raw,
                # undecoded path - that is all this branch has - which is the same best-effort input
                # the code-ness classification below it already accepts.
                $currentFile = $rawPath
                # 🔴 NORMALISE BEFORE TESTING, or this "fix" fixes nothing. Capstone R5, End-to-end
                # Walker. $rawPath is the UNDECODED `+++` payload, so it still carries git's surrounding
                # double quotes and its `b/` prefix. Every entry in $TestPatterns is END-ANCHORED
                # (`\.Tests\.ps1$`), and a trailing `"` defeats an end anchor - so `"b/src/x.Tests.ps1"`
                # matched NOTHING and the branch below promoted a TEST file to production code, which is
                # exactly the outcome the previous round's fix was written to prevent.
                $probePath = $rawPath.Trim('"')
                if ($probePath.StartsWith('b/')) { $probePath = $probePath.Substring(2) }
                $currentIsTest = Test-IsTestPath $probePath
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
        # Test-IsCodeFile, but Rule C reads every non-test file's added/deleted lines regardless of
        # extension - so a documentation-only change containing a declaration-shaped line (e.g.
        # a README code sample) fired the mandatory consult. Mirror the same allow-list here.
        if (-not $currentIsCode) { continue }
        if ($line -match '^\+' -and $line -notmatch '^\+\+\+') { $hunkAdds++ }
        elseif ($line -match '^-' -and $line -notmatch '^---') { $hunkDels++ }
        # Rule B no longer reads added lines here - it runs separately, below, as a whole-file AST
        # diff via ast-grep. This loop keeps only what Rule C needs: per-hunk add/del counts and the
        # enclosing-function header git already names in the @@ line.
    }
    Complete-Hunk

    # --- Rule B: a new AST-level DECLARATION NAME, via ast-grep ------------------------------
    # For each non-test, code-extension file the diff TOUCHES (not just added - Rule A already owns
    # brand-new files, and a file absent at base is that same "newly added" shape even when it
    # arrived via a rename, so it is skipped here too), parse both the base and HEAD version and
    # diff the declaration NAME sets ast-grep finds. A name present at HEAD but absent at base is new
    # shipped code, independent of which line it landed on or how many modifiers precede it.
    $ruleBSkipped = [System.Collections.Generic.List[string]]::new()
    # Files Rule B DID examine but can only partly understand - see the RULE-B-PARTIAL block below.
    $ruleBPartial = [System.Collections.Generic.List[string]]::new()
    $changedForRuleB = (& git diff --name-only -z "$BaseRef..HEAD" -- . `
        ':(exclude)*.lock' ':(exclude)*.min.js' ':(exclude)package-lock.json') -split "`0" | Where-Object { $_ -ne '' }

    foreach ($path in $changedForRuleB) {
        if (Test-IsTestPath $path) { continue }
        if (-not (Test-IsCodeFile $path)) { continue }

        # A file absent at HEAD (deleted) has no content left for Rule B to examine, regardless of
        # whether ast-grep supports its language - check this FIRST, before the language-support
        # check, so a deletion never earns a RULE-B-SKIPPED line. MEASURED bug this fixes: without
        # this ordering, a deleted .ps1 path still printed "RULE-B-SKIPPED: <that path>", which reads
        # as flagging a file that no longer exists and broke the rename/delete/modify test's assertion
        # that a deleted file's name must not appear in the output at all.
        $headContent = & git show "HEAD:$path" 2>$null
        if ($LASTEXITCODE -ne 0) { continue }

        $ext = [System.IO.Path]::GetExtension($path)
        $isPowerShell = $PowerShellExtensions -contains $ext

        # EXTENSIONLESS EXECUTABLES (justfile, Makefile, Dockerfile) - parse the shell-shaped bodies as
        # Bash. This restores a case an earlier round had fixed and the ast-grep migration then REGRESSED:
        # ast-grep's file-type discovery is EXTENSION-keyed, so an extensionless file matched nothing and
        # fell into RULE-B-SKIPPED. MEASURED both halves: identical justfile content saved as `jf.sh`
        # yields `{"NAME":{"text":"deploy"}}`, while the same content saved with NO extension yields `[]`.
        # So the parse works and only the discovery was the problem - we give the temp file a .sh suffix.
        # Best-effort by nature: a justfile is not bash, but its recipe bodies and `f() {}` declarations
        # are shell-shaped, which is exactly what this rule is looking for.
        $isShellNamed = ($ext -eq '' -and ($CodeExecutableNames -contains [System.IO.Path]::GetFileName($path)))

        if (-not $isPowerShell -and -not $isShellNamed -and -not $AstGrepLanguageByExtension.ContainsKey($ext)) {
            # THE GAP MUST BE LOUD (owner ruling). Rule A and Rule C still see this file; only Rule B
            # cannot. Collected here and printed unconditionally below, whether or not the trigger
            # otherwise fires - a silently-skipped file is the exact defect an earlier round already
            # found in this script.
            $ruleBSkipped.Add($path)
            continue
        }

        $baseContent = & git show "${BaseRef}:$path" 2>$null
        if ($LASTEXITCODE -ne 0) { continue }   # absent at base (new file, or the new side of a rename) - Rule A's business

        if ($isPowerShell) {
            # Native parser - no ast-grep grammar exists for PowerShell. Same "<kind>::<name>" set
            # shape, so the diff below is engine-agnostic.
            $baseNames = Get-PowerShellDeclarationNames (($baseContent -join "`n"))
            $headNames = Get-PowerShellDeclarationNames (($headContent -join "`n"))
        }
        else {
            # An extensionless executable is parsed as Bash, and its temp file MUST carry a .sh suffix
            # or ast-grep's extension-keyed discovery ignores it entirely - see the block comment above.
            #
            # 🔴 THE COVERAGE HERE IS PARTIAL, AND IT MUST SAY SO. MEASURED (capstone R4): the Bash
            # grammar sees a `deploy() { ... }` function in a justfile, but a NORMAL RECIPE - `deploy:`
            # followed by indented lines - is not a Bash function_definition, so adding one returns
            # exit 0. Recipes are the ordinary way to add work to a justfile or Makefile.
            #
            # An earlier round reported these files as RULE-B-SKIPPED, which was an HONEST miss. Parsing
            # them as Bash without saying so converted that into a SILENT one - partial coverage that
            # reads as full coverage, which is the False Safety Promise shape this review keeps finding.
            # So they now announce the limit on every run, exactly as a skip does.
            if ($isShellNamed) { $lang = 'Bash'; $tmpExt = '.sh'; $ruleBPartial.Add($path) }
            else               { $lang = $AstGrepLanguageByExtension[$ext]; $tmpExt = $ext }
            $baseNames = Get-AstGrepDeclarationNames -Lang $lang -Content ($baseContent -join "`n") -Extension $tmpExt
            $headNames = Get-AstGrepDeclarationNames -Lang $lang -Content ($headContent -join "`n") -Extension $tmpExt
        }
        foreach ($key in $headNames) {
            if ($baseNames -notcontains $key) {
                $name = $key.Substring($key.IndexOf('::') + 2)   # strip the "k_<kind>::" prefix for the human-facing message
                $fired.Add("new-declaration: $path : $name")
            }
        }
    }

    # PARTIAL coverage is announced exactly as a SKIP is. A build file parsed as shell yields its
    # `f() {}` functions and NOT its recipe targets, so reporting "no new code" for one without saying
    # so would be a silent half-answer. MEASURED (capstone R4): adding `deploy:` to a justfile returns
    # exit 0 under the Bash grammar.
    if ($ruleBPartial.Count -gt 0) {
        $ruleBPartial | Sort-Object -Unique | ForEach-Object { Write-Output "  - RULE-B-PARTIAL (build file parsed as shell; recipe targets NOT covered): $_" }
    }

    if ($ruleBSkipped.Count -gt 0) {
        $ruleBSkipped | Sort-Object -Unique | ForEach-Object { Write-Output "  - RULE-B-SKIPPED (no ast-grep grammar): $_" }
    }

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

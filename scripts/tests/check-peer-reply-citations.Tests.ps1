# scripts/tests/check-peer-reply-citations.Tests.ps1
# Pins the peer-reply citation checker: the DISCIPLINE declares the schema, the checker owns the
# declaration, and citations resolve by QUOTED TEXT rather than by line number.
BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Checker  = Join-Path $script:RepoRoot 'scripts/check-peer-reply-citations.py'
    if (-not (Test-Path -LiteralPath $script:Checker -PathType Leaf)) {
        throw "checker not found at $script:Checker - this suite cannot run"
    }

    # NO OTHER SUITE IN scripts/tests INVOKES PYTHON - measured 2026-09-02, this is the first. A missing
    # or Store-stub `python` must SKIP VISIBLY, never fail as though the checker were broken.
    #
    # RUN IT, DO NOT MERELY RESOLVE IT. MEASURED on this box: `Get-Command python` returns the WindowsApps
    # STUB path and a real Python answers behind it. On a machine WITHOUT python the same path resolves
    # and launches the Microsoft Store instead, so a `.Source` check proves nothing either way. Only an
    # actual invocation distinguishes the two.
    $script:Py = $null
    $cand = (Get-Command python -ErrorAction SilentlyContinue)?.Source
    if ($cand) {
        try { $null = & $cand --version 2>&1; if ($LASTEXITCODE -eq 0) { $script:Py = $cand } } catch { }
    }

    # SKIP LOCALLY, FAIL IN CI - capstone R3, class 4. Skipping is right on a developer box without
    # python; it is a FALSE SAFETY PROMISE on a runner, because Pester exits 0 on a skipped test, so a CI
    # job missing the interpreter reports this suite GREEN while executing none of it. The gate would
    # certify a checker it never ran. A missing dependency is a broken runner, not a passing build.
    if (-not $script:Py -and $env:CI) {
        throw ('python is required by this suite and is not on PATH. In CI a missing dependency must ' +
               'FAIL rather than skip: a skipped suite exits 0 and reports GREEN while testing nothing.')
    }
    if (-not $script:Py) {
        Write-Warning 'python not found - this suite will SKIP. Acceptable locally; it would FAIL in CI.'
    }

    $script:Made = [System.Collections.Generic.List[string]]::new()
    function New-Reply { param([string]$Json)
        $p = Join-Path ([IO.Path]::GetTempPath()) ("reply-" + [guid]::NewGuid() + ".json")
        [IO.File]::WriteAllText($p, $Json); $script:Made.Add($p); $p
    }
}

# EVERY fixture is tracked and removed. Without this the suite abandons a JSON file per row per run,
# forever, on every developer box and every CI runner.
AfterAll { foreach ($f in $script:Made) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } }

Describe 'check-peer-reply-citations' {
    BeforeEach {
        if (-not $script:Py) {
            Set-ItResult -Skipped -Because 'python is not on PATH, so the checker cannot be exercised here'
        }
    }

    It 'accepts a reply whose keys match the DISCIPLINE-declared schema' {
        $r = New-Reply '[{"file":"justfile","quoted_line":"test-scripts-fast:","missing_test":"x"}]'
        # ASSERT THE SUMMARY, NOT ONLY THE EXIT CODE. Capstone R6 measured it: replacing this checker
        # with nothing but `sys.exit(0)` left SEVEN of thirty rows green, because every success path
        # piped stdout to Out-Null and asked only for exit 0, which a no-op satisfies. The summary line
        # is the cheapest proof the checker actually walked the rows it was handed.
        #
        # THE ROW COUNT IS THE EVIDENCE, NOT THE WORD 'problem'. The first version of this
        # assertion matched 'across \d+ row(s)' and bought nothing: a checker that validated
        # nothing but printed a well-formed ZERO-row summary passed the same seven rows -
        # measured, 7 of 31, identical to the no-op. Pinning the count the fixture actually
        # supplied is what makes the line proof that the reply was parsed.
        $out = ((& $script:Py $script:Checker $r HEAD 'agy-test-audit' 2>&1) -join "`n")
        $LASTEXITCODE | Should -Be 0 -Because "the checker said: $out"
        $out | Should -Match 'problem\(s\) across 1 row\(s\), discipline agy-test-audit'
    }

    It 'REJECTS a key the discipline did not declare - the peer cannot widen its own contract' {
        $r = New-Reply '[{"file":"justfile","quoted_line":"test-scripts-fast:","smuggled":"x"}]'
        $out = & $script:Py $script:Checker $r HEAD 'agy-test-audit' 2>&1
        $LASTEXITCODE | Should -Be 1
        ($out -join "`n") | Should -Match 'smuggled'
    }

    It 'REJECTS an unknown discipline rather than defaulting to permissive' {
        $r = New-Reply '[{"file":"justfile","quoted_line":"test-scripts-fast:"}]'
        $out = & $script:Py $script:Checker $r HEAD 'not-a-discipline' 2>&1
        $LASTEXITCODE | Should -Be 1
        ($out -join "`n") | Should -Match 'not-a-discipline'
    }

    It 'reports EVERY bad row, not just the first' {
        # A checker that aborts on row 1 hides all citation drift after it - the same silent-drop shape
        # as the TEN_KEYS bug this replaces, just relocated.
        # UNDECLARED KEYS, deliberately. A fixture using only VALID keys would exercise the
        # citation-resolution path and never enter the schema validator at all, so it could not
        # disprove an aborting validator - the exact behaviour this row names.
        $r = New-Reply '[{"file":"justfile","quoted_line":"x","smuggled_one":"a"},{"file":"justfile","quoted_line":"y","smuggled_two":"b"}]'
        $out = ((& $script:Py $script:Checker $r HEAD 'agy-capstone' 2>&1) -join "`n")
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'smuggled_one'
        $out | Should -Match 'smuggled_two' -Because 'aborting on the first bad row hides every later one'
    }

    It 'resolves a citation whose only difference is a MANGLED EM-DASH' {
        # THE NORMALISATION ROW. It must cite a real line that CONTAINS an em-dash and quote it with the
        # dash written as plain ASCII; norm() maps the FILE side to "-" as well, so the two meet. A
        # plain-ASCII fixture citing a plain-ASCII line would pass against a checker that normalises
        # nothing, which is the vacuity this row exists to avoid.
        # THE PLAN'S ORIGINAL FIXTURE FOR THIS ROW DID NOT EXIST IN THE FILE - it quoted
        # "### 20 - A mockable clock (TimeProvider) in AgyView" where the real line is
        # "### <section> - A mockable clock (`TimeProvider`) in `AgyView` - ..." with backticks and a
        # trailing clause. Verified verbatim at HEAD before use, which is why this one is short.
        $r = New-Reply '[{"file":"clavity-dotnet/ROADMAP.md","quoted_line":"# clavity umbrella - ROADMAP"}]'
        # ASSERT THE SUMMARY, NOT ONLY THE EXIT CODE. Capstone R6 measured it: replacing this checker
        # with nothing but `sys.exit(0)` left SEVEN of thirty rows green, because every success path
        # piped stdout to Out-Null and asked only for exit 0, which a no-op satisfies. The summary line
        # is the cheapest proof the checker actually walked the rows it was handed.
        #
        # THE ROW COUNT IS THE EVIDENCE, NOT THE WORD 'problem'. The first version of this
        # assertion matched 'across \d+ row(s)' and bought nothing: a checker that validated
        # nothing but printed a well-formed ZERO-row summary passed the same seven rows -
        # measured, 7 of 31, identical to the no-op. Pinning the count the fixture actually
        # supplied is what makes the line proof that the reply was parsed.
        $out = ((& $script:Py $script:Checker $r HEAD 'agy-capstone' 2>&1) -join "`n")
        $LASTEXITCODE | Should -Be 0 -Because 'normalisation must absorb a dash difference rather than call it drift'
        $out | Should -Match 'problem\(s\) across 1 row\(s\), discipline agy-capstone'
    }

    It 'resolves an indented citation WHETHER OR NOT the peer reproduced the indent' -ForEach @(
        @{ label = 'indent reproduced'; quoted = '    bash scripts/check-seed-artifacts-synced.sh' },
        @{ label = 'indent stripped';   quoted = 'bash scripts/check-seed-artifacts-synced.sh' }
    ) {
        # BOTH ARMS, because the second is the one that was MEASURED failing. Capstone round 1 cited two
        # lines correctly and both were reported as DRIFT - the peer had stripped their 8 and 4 leading
        # spaces. Two of four rows, in a reply that had itself predicted this exact failure.
        # norm() now folds leading whitespace on BOTH sides. The cost is real and accepted: two lines
        # differing only in indent become indistinguishable, and a citation may resolve against the
        # wrong one - whose text is by definition identical. False-drift is routine; that is not.
        # A WHOLE line, not a prefix: the checker compares whole lines, so the plan's original fixture
        # (a prefix of justfile's 2,000-character Invoke-Pester line) could never have matched.
        $r = New-Reply ('[{"file":"justfile","quoted_line":"' + $quoted + '"}]')
        # ASSERT THE SUMMARY, NOT ONLY THE EXIT CODE. Capstone R6 measured it: replacing this checker
        # with nothing but `sys.exit(0)` left SEVEN of thirty rows green, because every success path
        # piped stdout to Out-Null and asked only for exit 0, which a no-op satisfies. The summary line
        # is the cheapest proof the checker actually walked the rows it was handed.
        #
        # THE ROW COUNT IS THE EVIDENCE, NOT THE WORD 'problem'. The first version of this
        # assertion matched 'across \d+ row(s)' and bought nothing: a checker that validated
        # nothing but printed a well-formed ZERO-row summary passed the same seven rows -
        # measured, 7 of 31, identical to the no-op. Pinning the count the fixture actually
        # supplied is what makes the line proof that the reply was parsed.
        $out = ((& $script:Py $script:Checker $r HEAD 'agy-capstone' 2>&1) -join "`n")
        $LASTEXITCODE | Should -Be 0 -Because "a citation with the indent $label must resolve"
        $out | Should -Match 'problem\(s\) across 1 row\(s\), discipline agy-capstone'
    }

    It 'REPORTS a non-list JSON root instead of crashing - <label>' -ForEach @(
        @{ label = 'bool'; body = 'true' },
        @{ label = 'int';  body = '42' },
        @{ label = 'dict'; body = '{"file":"justfile","quoted_line":"test-scripts-fast:"}' }
    ) {
        # MEASURED in capstone round 1. `true` and `42` raised TypeError and printed a TRACEBACK instead
        # of a report - exit 1 either way, the same shape as the console-encoding crash this module
        # already guards. The dict was worse because it did NOT crash: enumerate() walked its KEYS, each
        # key string became a row, and iterating a string yields characters - 17 invented problems from
        # one well-formed object, with nothing saying the shape was wrong.
        $r = New-Reply $body
        $out = ((& $script:Py $script:Checker $r HEAD 'agy-capstone' 2>&1) -join "`n")
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'must be a JSON ARRAY'
        $out | Should -Not -Match 'Traceback' -Because 'a bad root shape must be REPORTED, never raised'
    }

    It 'REPORTS a non-string <key> instead of crashing on it' -ForEach @(
        @{ key = 'quoted_line'; body = '[{"file":"justfile","quoted_line":true}]' },
        @{ key = 'quoted_line'; body = '[{"file":"justfile","quoted_line":123}]' },
        @{ key = 'file';        body = '[{"file":true,"quoted_line":"x"}]' }
    ) {
        # CAPSTONE R2. The root-shape guard added one round earlier stopped at the ROW level, so a
        # well-shaped row carrying a non-string value walked into norm() and raised TypeError - the SAME
        # disguised crash the previous round was meant to eliminate, one level deeper. A type guard that
        # checks the container and not the contents is half a guard.
        $r = New-Reply $body
        $out = ((& $script:Py $script:Checker $r HEAD 'agy-capstone' 2>&1) -join "`n")
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'must be a string'
        $out | Should -Not -Match 'Traceback' -Because 'a bad value type must be REPORTED, never raised'
    }

    It 'REPORTS a row that is not an object, and keeps going' {
        $r = New-Reply '[1, {"file":"justfile","quoted_line":"nope","smuggled":"x"}]'
        $out = ((& $script:Py $script:Checker $r HEAD 'agy-capstone' 2>&1) -join "`n")
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'expected an object, got int'
        $out | Should -Match 'smuggled' -Because 'a bad row must not abort the rows after it'
        $out | Should -Not -Match 'Traceback'
    }

    It 'accepts `evidence` as the declared pointer key' {
        $r = New-Reply '[{"file":"justfile","quoted_line":"test-scripts-fast:","evidence":"reasoned"}]'
        # ASSERT THE SUMMARY, NOT ONLY THE EXIT CODE. Capstone R6 measured it: replacing this checker
        # with nothing but `sys.exit(0)` left SEVEN of thirty rows green, because every success path
        # piped stdout to Out-Null and asked only for exit 0, which a no-op satisfies. The summary line
        # is the cheapest proof the checker actually walked the rows it was handed.
        #
        # THE ROW COUNT IS THE EVIDENCE, NOT THE WORD 'problem'. The first version of this
        # assertion matched 'across \d+ row(s)' and bought nothing: a checker that validated
        # nothing but printed a well-formed ZERO-row summary passed the same seven rows -
        # measured, 7 of 31, identical to the no-op. Pinning the count the fixture actually
        # supplied is what makes the line proof that the reply was parsed.
        $out = ((& $script:Py $script:Checker $r HEAD 'agy-test-audit' 2>&1) -join "`n")
        $LASTEXITCODE | Should -Be 0 -Because "the checker said: $out"
        $out | Should -Match 'problem\(s\) across 1 row\(s\), discipline agy-test-audit'
    }

    It 'REJECTS the retired key `confidence` - the rename is enforced, not merely documented' {
        # Owner ruling 2026-09-02: the pointer field is `evidence`, because `confidence` projects an
        # epistemic authority a peer's self-report cannot carry. Without this row the rename is a
        # convention that the next brief can quietly undo.
        $r = New-Reply '[{"file":"justfile","quoted_line":"test-scripts-fast:","confidence":"measured"}]'
        $out = & $script:Py $script:Checker $r HEAD 'agy-test-audit' 2>&1
        $LASTEXITCODE | Should -Be 1
        ($out -join "`n") | Should -Match 'confidence'
    }

    It 'REPORTS a non-ASCII citation instead of CRASHING on the console encoding' {
        # MEASURED 2026-09-02: this box's stdout is cp1252, which encodes an em dash but NOT U+2212 MINUS
        # SIGN. Echoing a citation with the repr conversion therefore died with a UnicodeEncodeError
        # traceback - in the one module whose entire job is mangled non-ASCII. Exit status is 1 either
        # way, which is what made it nasty: the run looks like "problems found" while the problem list
        # was never printed. The fixture cites a line that does NOT exist, so the checker must reach the
        # echo path and survive it.
        $minus = [char]0x2212   # built from its CODEPOINT: a literal here has been mangled in
                                # transit three times today, so the source stays pure ASCII
        $r = New-Reply ('[{"file":"justfile","quoted_line":"no such line ' + $minus + ' here"}]')
        $out = ((& $script:Py $script:Checker $r HEAD 'agy-capstone' 2>&1) -join "`n")
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'quoted_line not found' -Because 'the drift must be REPORTED, not raised'
        $out | Should -Not -Match 'Traceback' -Because 'a console encoding must never turn a report into a crash'
    }

    It 'pins the three dash literals BY CODEPOINT OF THE VALUE - a mangled one is a silent no-op' {
        # norm()'s dash folding is the module's whole purpose, and a mangled literal disables it without
        # reddening anything: a mangled dash matches nothing, so replace() becomes a no-op and every
        # citation still resolves or fails on its own merits. Only a codepoint assertion catches it.
        #
        # THE PIN MOVED FROM THE SOURCE BYTES TO THE RUNTIME VALUE, capstone R7, and the change that
        # forced it is the better half of the story. The literals are now written as \u escapes, so the
        # checker is PURE ASCII and there is no byte in it for a lossy channel to mangle - prevention
        # rather than detection. The old pin read the source line's own characters, so it would have
        # gone RED on exactly that improvement: it asserted the bytes, not the meaning.
        #
        # IT REFUSES TO GUESS, capstone R8, and it had to: the first version used re.search, which takes
        # the FIRST match. MEASURED - a correct decoy placed in the module docstring above a BROKEN
        # runtime assignment made this row PASS while certifying nothing. That is the third time in this
        # capstone that a guard reading another file's source text was fooled by a docstring, and the
        # answer is the same one the owner ruled for the linter: count the assignments, fail unless there
        # is exactly one.
        # ast.literal_eval is what makes both forms equivalent to this row. A future maintainer may write
        # the characters literally again and this pin still passes, because it asks what Python BUILDS.
        #
        # NO REGEX AT ALL - THE THIRD VERSION, AND THE FIRST TWO EACH BROKE ON CORRECT CODE. This asks
        # Python what the module ASSIGNS, via ast.parse, so formatting and comments cannot reach it.
        #
        # v1 `^DASHES\s*=\s*(\(.*?\))` with re.M: '\s*=\s*' absorbs spacing around the '=' only, and '.'
        #    does not cross a newline. A formatter that WRAPPED the tuple gave ZERO hits -> false RED on
        #    correct code. Capstone R8 caught it; MEASURED, wrapped gave 0 hits and inline gave 1.
        # v2 the same regex with re.M | re.S: fixed wrapping and INTRODUCED A NEW EDGE, which capstone R9
        #    caught one round later. Non-greedy `.*?` stops at the FIRST ')', so a wrapped tuple carrying a
        #    comment with a parenthesis - `# em dash (U+2014)` - extracts malformed Python and
        #    ast.literal_eval CRASHES. MEASURED, all three cases: inline OK, wrapped OK, wrapped-with-paren
        #    SyntaxError. A fix that spawns its own edge is this range's signature failure; the answer was
        #    to stop patching the pattern and delete the category.
        #
        # WHAT SURVIVES FROM THE REGEX VERSIONS, deliberately: it still COUNTS the assignments and fails
        # unless there is exactly one, which is what defeats a decoy. A decoy in a docstring was never an
        # Assign node, so ast is strictly stronger here than the text scan it replaces.
        #
        # The trigger was not reachable today - lefthook.yml:63-65 scopes ruff to
        # clavity-classic/agy-mcp-bridge/, so nothing formats scripts/*.py - but the assignment is 93
        # characters against ruff's 88-column default and would wrap the first time that glob widened.
        $checker = Join-Path $script:RepoRoot 'scripts/check-peer-reply-citations.py'
        $prog = @'
import ast, io, sys
src = io.open(sys.argv[1], encoding="utf-8").read()
vals = [n.value
        for n in ast.walk(ast.parse(src)) if isinstance(n, ast.Assign)
        for t in n.targets if isinstance(t, ast.Name) and t.id == "DASHES"]
if len(vals) != 1:
    raise SystemExit("expected exactly ONE DASHES assignment, found %d" % len(vals))
print(",".join(str(ord(c)) for c in ast.literal_eval(vals[0])))
'@
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("dashpin-" + [guid]::NewGuid() + ".py")
        [IO.File]::WriteAllText($tmp, $prog); $script:Made.Add($tmp)
        $out = ((& $script:Py $tmp $checker 2>&1) -join '').Trim()
        $LASTEXITCODE | Should -Be 0 -Because "the extractor must run; it said: $out"
        $out | Should -Be '8212,8211,8722' -Because 'em dash U+2014, en dash U+2013, minus sign U+2212, in that order'
    }

    It 'FOLDS <name> in the citation onto a plain hyphen in the file' -ForEach @(
        @{ name = 'an EN DASH';    code = 0x2013 },
        @{ name = 'a MINUS SIGN'; code = 0x2212 }
    ) {
        # AGY-CAPSTONE R8, and this gap was MINE, found by neutering each dash in turn: removing the em
        # dash reddened a behavioural row AND the codepoint pin, but removing the EN DASH or the MINUS
        # SIGN reddened ONLY the pin. Two thirds of norm()'s dash folding was pinned by a source-text
        # assertion and by nothing that ever ran it.
        #
        # THE DASH GOES IN THE CITATION, NOT THE FILE, which is what makes these rows possible at all:
        # no tracked file need contain an en dash or a minus sign. norm() folds BOTH sides, so a citation
        # written with the dash meets a file line written with a plain hyphen. Drop that dash from DASHES
        # and the fold stops happening and the citation no longer resolves.
        $dash    = [string][char]$code
        $citation = 'test' + $dash + 'scripts-fast:'
        $r = New-Reply ('[{"file":"justfile","quoted_line":"' + $citation + '"}]')
        $out = ((& $script:Py $script:Checker $r HEAD 'agy-capstone' 2>&1) -join "`n")
        $LASTEXITCODE | Should -Be 0 -Because "norm() must fold $name onto '-' on the CITATION side; it said: $out"
        $out | Should -Match 'problem\(s\) across 1 row\(s\), discipline agy-capstone'
    }
    It 'keeps the checker PURE ASCII, so no byte in it can be mangled in transit' {
        # AGY-CAPSTONE R7. The module's own comment records that this source has been hand-patched
        # through a lossy channel more than once, and the three dash literals were the only non-ASCII
        # bytes in it. They are escapes now, which removes the vector rather than detecting it - but
        # nothing asserted the property, so the next non-ASCII character to arrive would reinstate it
        # silently. The four shipped SKILL.md files are linted for exactly this; the checker was not.
        #
        # BYTES, NOT CHARACTERS. Reading the file as text and inspecting the decoded string would answer
        # a question about the decoder; the claim here is about what is ON DISK.
        $checker = Join-Path $script:RepoRoot 'scripts/check-peer-reply-citations.py'
        # NUL TOO, not only the high bytes, capstone R8. MEASURED: a UTF-16LE file with no BOM encodes
        # an em dash as 0x14 0x20 - every byte under 128 - so a byte-range test alone certifies it as
        # ASCII. That exact file cannot be a Python script (`SyntaxError: source code cannot contain
        # null bytes`), so the hole was never reachable; closing it costs one comparison, which is less
        # than the sentence explaining why it was left open.
        $bad = [IO.File]::ReadAllBytes($checker) | Where-Object { $_ -eq 0 -or $_ -gt 127 }
        @($bad).Count | Should -Be 0 -Because 'the checker must contain no NUL and no byte above 0x7F - write non-ASCII as a \u escape'
    }

    It 'REPORTS a missing required key <key> instead of crashing on it' -ForEach @(
        @{ key = 'file';        body = '[{"quoted_line":"test-scripts-fast:"}]' },
        @{ key = 'quoted_line'; body = '[{"file":"justfile"}]' }
    ) {
        # AGY-TEST-AUDIT 2026-09-02, and the gap was MEASURED rather than supposed: neutering the
        # `if key not in row:` branch left this suite at 18/0. Not one fixture omitted a required key, so
        # the branch whose own docstring calls its return value "load-bearing" had never once executed.
        # Deleting it does not merely lose a diagnostic - the very next line indexes the key just reported
        # absent, so the run dies on a KeyError at row 1 and every later citation is silently dropped,
        # which is the collect-do-not-abort property the module claims in prose two lines above it.
        $r = New-Reply $body
        $out = ((& $script:Py $script:Checker $r HEAD 'agy-capstone' 2>&1) -join "`n")
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match "missing required key '$key'"
        $out | Should -Not -Match 'Traceback' -Because 'an absent key must be REPORTED, never raised'
    }

    It 'REPORTS a file it cannot read at the named sha, instead of crashing' {
        # Same measurement, same result: neutering `if blobs[row["file"]] is None:` left the suite at
        # 18/0, because every fixture in it cited a file that exists. The nearest existing row cites a
        # REAL file and a line that is not in it - that exercises the citation compare and never reaches
        # the read-failure branch at all. Without the guard a None blob flows into the membership test
        # and raises TypeError.
        $r = New-Reply '[{"file":"no/such/file.md","quoted_line":"anything"}]'
        $out = ((& $script:Py $script:Checker $r HEAD 'agy-capstone' 2>&1) -join "`n")
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match "cannot read 'no/such/file\.md'"   # ascii() quotes the path - capstone R6
        $out | Should -Not -Match 'Traceback' -Because 'an unreadable file must be REPORTED, never raised'
    }

    It 'REPORTS malformed JSON SYNTAX instead of a traceback - <label>' -ForEach @(
        @{ label = 'trailing comma';  body = '[{"file":"justfile","quoted_line":"test-scripts-fast:"},]' },
        @{ label = 'not json at all'; body = 'not json at all' }
    ) {
        # A wrong SHAPE and malformed SYNTAX are different failures, and only the first was ever guarded.
        # MEASURED 2026-09-02: both bodies below exited 1 with a raw json.decoder.JSONDecodeError
        # TRACEBACK - the same disguised crash this module already carried two guards for, one layer
        # further out than either could reach, because json.load raises before any shape check runs.
        # Exit 1 either way is what made it nasty: the run reads as "problems found" while the problem
        # list was never printed, so the driver has nothing to hand back that would let the peer correct
        # its own reply.
        $r = New-Reply $body
        $out = ((& $script:Py $script:Checker $r HEAD 'agy-capstone' 2>&1) -join "`n")
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'reply is not valid JSON'
        $out | Should -Not -Match 'Traceback' -Because 'malformed syntax must be REPORTED, never raised'
    }

    It 'exercises the <discipline> schema - <mode>' -ForEach @(
        @{ discipline = 'agy-first';                mode = 'accepts a declared key'; key = 'detail';   expect = 0 },
        @{ discipline = 'agy-first';                mode = 'REJECTS trigger';        key = 'trigger';  expect = 1 },
        @{ discipline = 'adversarial-panel-review'; mode = 'accepts a declared key'; key = 'detail';   expect = 0 },
        @{ discipline = 'adversarial-panel-review'; mode = 'REJECTS severity';       key = 'severity'; expect = 1 }
    ) {
        # TWO OF THE FOUR DECLARED SCHEMAS WERE NEVER INVOKED. Measured by counting the discipline
        # argument across this file before these rows existed: agy-capstone 7 times, agy-test-audit 4,
        # not-a-discipline once, and these two never. Either entry could have been widened - or deleted
        # outright - with the suite still green at 18/0.
        #
        # THE REJECTING HALF IS THE DISCRIMINATING ONE, and it is why each pair cites a key that is real
        # SOMEWHERE. `trigger` is declared for agy-capstone and `severity` for both of the other two, so
        # a row pinning only acceptance would stay green against a checker that had collapsed the four
        # schemas into one permissive union - which is precisely the hardcoded-TEN_KEYS behaviour this
        # checker replaced.
        $r = New-Reply ('[{"file":"justfile","quoted_line":"test-scripts-fast:","' + $key + '":"x"}]')
        $out = ((& $script:Py $script:Checker $r HEAD $discipline 2>&1) -join "`n")
        $LASTEXITCODE | Should -Be $expect
        if ($expect -eq 1) {
            $out | Should -Match $key -Because "$key is not declared for $discipline and must be named in the rejection"
        } else {
            # The ACCEPTING half needs the summary too, or a no-op checker satisfies it (capstone R6).
            $out | Should -Match "problem\(s\) across 1 row\(s\), discipline $discipline"
        }
    }

    It 'REPORTS a reply PATH it cannot open instead of a traceback - <label>' -ForEach @(
        @{ label = 'no such file'; path = 'no/such/reply.json' },
        @{ label = 'a directory';  path = 'scripts' }
    ) {
        # AGY-CAPSTONE 2026-09-02, and this is the FOURTH layer of the same disguised-crash class in one
        # file. The guards already here cover the reply's CONTENT: a non-list root, a non-string nested
        # value, and malformed JSON syntax. All three sit behind json.load - and io.open runs first and
        # raises something json.load never does. MEASURED before the fix: a path that does not exist
        # printed a raw FileNotFoundError traceback and a path naming a directory printed a raw
        # PermissionError one, each exiting 1, so the driver's own typo read as "problems found" with the
        # problem list never printed.
        #
        # BOTH SHAPES, because the exception differs by platform as well as by cause: Windows raises
        # PermissionError for a directory where a POSIX box raises IsADirectoryError. OSError is the
        # parent of all three, which is what the guard names.
        $out = ((& $script:Py $script:Checker $path HEAD 'agy-capstone' 2>&1) -join "`n")
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'cannot read the reply file'
        $out | Should -Not -Match 'Traceback' -Because 'an unopenable reply path must be REPORTED, never raised'
    }

    It 'REPORTS a FILE PATH that the console cannot encode, instead of crashing on it' {
        # AGY-CAPSTONE R6, and it is a class-4 False Safety Promise as much as a crash. The module's own
        # comment says EVERY message echoing peer-supplied text uses ascii() - and row["file"] was
        # interpolated RAW into two of them while quoted_line and the schema keys were wrapped. MEASURED:
        # a reply whose FILE path carries U+2212, run with PYTHONIOENCODING=cp1252 (the measured console
        # encoding on this box), died with UnicodeEncodeError and printed no problem list - exit 1 either
        # way, which is what makes it nasty, exactly like the three crashes this module already guards.
        #
        # THE ENVIRONMENT VARIABLE IS THE FIXTURE. Without it Python may use a wide-character path and
        # absorb the character, so a row that did not force the encoding would pass against the broken
        # code and prove nothing.
        $r = New-Reply '[{"file":"no/such/file\u2212here.md","quoted_line":"anything"}]'
        $old = $env:PYTHONIOENCODING
        try {
            $env:PYTHONIOENCODING = 'cp1252'
            $out = ((& $script:Py $script:Checker $r HEAD 'agy-capstone' 2>&1) -join "`n")
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'cannot read'
            $out | Should -Match 'u2212' -Because 'ascii() must escape the character rather than hand it to a codec that cannot encode it'
            $out | Should -Not -Match 'UnicodeEncodeError' -Because 'an unencodable path must be REPORTED, never raised'
            $out | Should -Match 'problem\(s\) across' -Because 'the problem LIST must be reached, which is the half the crash destroyed'
        } finally {
            $env:PYTHONIOENCODING = $old
        }
    }
    It 'REPORTS a citation to a BINARY file instead of dying in a reader thread' {
        # AGY-CAPSTONE R2, and this is the FIFTH layer of the same disguised-crash class in this file -
        # the first one that was not even in the main thread. MEASURED at df14515 with a reply citing a
        # tracked .bin fixture: strict utf-8 decoding of `git show`'s output raised UnicodeDecodeError
        # inside subprocess's reader THREAD, the thread died, r.stdout came back None, and the main
        # thread then died on None.splitlines() with an AttributeError. TWO tracebacks, exit 1, and the
        # problem list never printed at all.
        #
        # It is not an exotic citation. This repository tracks several .bin fixtures and the reply
        # contract invites a citation from anywhere in the tree; a peer sweeping a diff can reach one.
        #
        # THE ASSERTION IS THAT IT REPORTS, NOT THAT IT RESOLVES. A binary file has no verbatim line to
        # cite, so 'quoted_line not found' is the correct answer - the defect was never the verdict, it
        # was that no verdict was reached.
        $binary = 'clavity-dotnet/tests/Clavity.Ls.Tests/TestData/GetCascadeTrajectory.bin'
        (& git cat-file -e "HEAD:$binary" 2>&1) | Out-Null
        $LASTEXITCODE | Should -Be 0 -Because "the fixture $binary must exist at HEAD for this row to exercise the decode path"

        $r = New-Reply ('[{"file":"' + $binary + '","quoted_line":"anything"}]')
        $out = ((& $script:Py $script:Checker $r HEAD 'agy-capstone' 2>&1) -join "`n")
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'quoted_line not found'
        $out | Should -Match '1 problem\(s\) across 1 row\(s\)' -Because 'the problem LIST must be reached and printed, which is the half the crash destroyed'
        $out | Should -Not -Match 'Traceback' -Because 'an undecodable blob must be REPORTED, never raised'
    }
}

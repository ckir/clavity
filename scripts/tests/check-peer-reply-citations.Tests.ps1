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
        & $script:Py $script:Checker $r HEAD 'agy-test-audit' 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
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
        & $script:Py $script:Checker $r HEAD 'agy-capstone' 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0 -Because 'normalisation must absorb a dash difference rather than call it drift'
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
        & $script:Py $script:Checker $r HEAD 'agy-capstone' 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0 -Because "a citation with the indent $label must resolve"
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
        & $script:Py $script:Checker $r HEAD 'agy-test-audit' 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
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

    It 'pins the three dash literals BY CODEPOINT - a mangled one is a silent no-op' {
        # norm()'s dash folding is the module's whole purpose, and a mangled literal disables it without
        # reddening anything: a mangled dash matches nothing, so replace() becomes a no-op and every
        # citation still resolves or fails on its own merits. Only a codepoint assertion catches it.
        $src = [IO.File]::ReadAllText((Join-Path $script:RepoRoot 'scripts/check-peer-reply-citations.py'))
        $line = ($src -split "`n" | Where-Object { $_ -like 'DASHES = *' })
        $line | Should -Not -BeNullOrEmpty -Because 'the DASHES tuple must still exist to be pinned'
        $points = ([int[]][char[]]$line) | Where-Object { $_ -gt 127 }
        $points | Should -Be @(0x2014, 0x2013, 0x2212) -Because 'em dash, en dash and minus sign, in that order'
    }
}

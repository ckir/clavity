# scripts/tests/check-agy-discipline-skills.Tests.ps1
BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Lint     = Join-Path $script:RepoRoot 'scripts/check-agy-discipline-skills.ps1'

    # Stage a scratch -Root containing a VALID copy of EVERY shipped discipline skill, so a rejection
    # test that perturbs ONE skill fails on THAT defect, not on a MISSING sibling (SP-B: once
    # 'agy-capstone' joined $skills, a fixture staging only agy-first exited 1 for MISSING agy-capstone,
    # silently losing its discriminating power).
    # EVERY temp directory this file stages is tracked and swept, mirroring the $script:Made list in the
    # sibling suite scripts/tests/check-peer-reply-citations.Tests.ps1, whose comment states the same rule.
    # AGY-CAPSTONE 2026-09-02 measured why it was needed here: 20 New-ScratchRoot call sites, 3 try/finally
    # blocks and NO AfterAll, so 17 sites ended in a bare `Remove-Item $scratch` that a failing assertion
    # never reaches - Pester's `Should` THROWS, aborting the It block. A two-arm control settled it: a
    # passing row of this exact shape removed its directory, a failing row left its directory on disk.
    #
    # BOTH MAKERS ARE TRACKED, not just the scratch roots. The reviewing peer's objection to a
    # roots-only sweep was correct as far as it went - New-TempLinter stages directories too - so the list
    # is shared and both helpers add to it. The per-row `Remove-Item` and the three try/finally blocks
    # STAY: they keep a passing run from holding twenty roots at once, and this sweep exists only for the
    # rows that fail. The residual the peer named is real and accepted: a hard Ctrl+C bypasses AfterAll
    # where a CLR finally would still run, which loses the same directories the developer is already
    # abandoning the run over.
    $script:TempDirs = [System.Collections.Generic.List[string]]::new()

    function New-ScratchRoot {
        $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("agyskilltest-" + [guid]::NewGuid())
        $script:TempDirs.Add($scratch)
        # FOUR, not three. The 13b discipline-mandate check runs over adversarial-panel-review too, so a
        # scratch root without it makes EVERY rejection test below fail on a MISSING sibling rather than
        # on its own defect - the precise discriminating-power loss the comment above records.
        foreach ($s in @('agy-first', 'agy-capstone', 'agy-test-audit', 'adversarial-panel-review')) {
            $dst = Join-Path $scratch "clavity-dotnet/plugin/skills/$s"
            New-Item -ItemType Directory -Path $dst -Force | Out-Null
            Copy-Item (Join-Path $script:RepoRoot "clavity-dotnet/plugin/skills/$s/SKILL.md") `
                      (Join-Path $dst 'SKILL.md')
        }
        return $scratch
    }
    $script:SkillPath = { param($root, $skill) Join-Path $root "clavity-dotnet/plugin/skills/$skill/SKILL.md" }

    # Stage a COPY of the linter in a temp directory of its own. This is the ONLY way to reach three of
    # its branches, and AGY-TEST-AUDIT 2026-09-02 measured why: the linter resolves the schema registry
    # with `Join-Path $PSScriptRoot 'check-peer-reply-citations.py'`, so where the linter LIVES decides
    # whether that file is found. No fixture built under -Root can move it.
    #
    #   -Checker real   the repository's own checker, copied beside the linter (the isolated case)
    #   -Checker none   no checker at all, which trips the "names a checker that is not there" branch
    #   -Checker <text> that text written as the checker, for a registry mutated on purpose
    function New-TempLinter {
        param([string]$Source, [string]$Checker = 'real')
        $dir = Join-Path ([IO.Path]::GetTempPath()) ("lintdir-" + [guid]::NewGuid().ToString('N'))
        $script:TempDirs.Add($dir)
        New-Item -ItemType Directory -Path $dir | Out-Null
        $lint = Join-Path $dir 'lint-copy.ps1'
        Set-Content -Path $lint -Value $Source -NoNewline -Encoding utf8
        if ($Checker -eq 'real') {
            Copy-Item (Join-Path $script:RepoRoot 'scripts/check-peer-reply-citations.py') `
                      (Join-Path $dir 'check-peer-reply-citations.py')
        } elseif ($Checker -ne 'none') {
            Set-Content -Path (Join-Path $dir 'check-peer-reply-citations.py') -Value $Checker -NoNewline -Encoding utf8
        }
        return $lint
    }

    # PowerShell's Write-Error formatter WRAPS a long message at the console width and prefixes every
    # continuation line with '     | ', so a needle that straddles a wrap point never matches however
    # correct it is. MEASURED 2026-09-02: the registry-entry row below went RED on
    # 'declares no SCHEMAS entry' while the linter had visibly emitted exactly that - the break fell
    # between 'SCHEMAS' and 'entry'. Collapsing whitespace alone does NOT fix it, because the pipe
    # survives the collapse; the markers have to go first.
    #
    # This is also why the older rows in this file match only SHORT needles. They fit inside one wrapped
    # segment by luck rather than by design, and a message reworded slightly longer would break them
    # without any guard changing. Route new assertions through this helper.
    function Get-LintText {
        param([object[]]$Output)
        $t = (($Output | ForEach-Object { $_.ToString() }) -join "`n")
        $t = $t -replace '\x1b\[[0-9;]*m', ''
        $t = $t -replace '(?m)^\s*\|\s?', ''
        return ($t -replace '\s+', ' ')
    }

    # A skill file that satisfies EVERY invariant the linter checks, so a fixture built on it fails on
    # exactly the one thing the row perturbs. The previous phantom satisfied only the $skills-loop
    # invariants and silently failed six more in the $disciplineNames loop.
    $script:PhantomSkill = (@(
        '---'
        'name: phantom-unmapped'
        '---'
        'Transport: the agy_ask MCP tool, and clavity ask --review-only on classic.'
        'Pass discipline: "phantom-unmapped" so the driver 13b completeness checks run.'
        'Marker at .clavity/agy-marks/ per contract. Scratch dir .clavity/scratch/phantom/.'
        'Envelope: Snapshot before. Forbidden-actions banner. Permission to pass. Point at files. Diff after.'
        ''
        '> Put nothing after the terminal token.'
    ) -join "`n") + "`n"
}

# The sweep the 17 bare-Remove-Item rows never reach when an assertion throws. Idempotent by design: a
# row that already cleaned up leaves a path that is simply gone, which -ErrorAction SilentlyContinue
# absorbs, exactly as the sibling suite's AfterAll does.
AfterAll {
    foreach ($d in $script:TempDirs) {
        Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'check-agy-discipline-skills' {
    It 'passes when every shipped skill satisfies all invariants (real repo)' {
        $out = & $script:Lint 2>&1
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'agy-discipline skills OK'
    }

    Context 'rejection cases (each perturbs one skill; the other stays valid)' {
        It 'fails loudly on a non-ASCII character in <skill>' -ForEach @(
            @{ skill = 'agy-first' }, @{ skill = 'agy-capstone' }, @{ skill = 'agy-test-audit' }
        ) {
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            $body = (Get-Content -Raw $target) + "`nA stray em-dash `u{2014} here.`n"
            Set-Content -Path $target -Value $body -Encoding utf8
            & $script:Lint -Root $scratch 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
            Remove-Item -Recurse -Force $scratch
        }

        It 'fails when a required [VERDICT] form is missing from <skill>' -ForEach @(
            @{ skill = 'agy-first';      token = '[VERDICT: SKIPPED-UNREACHABLE]' },
            @{ skill = 'agy-capstone';   token = '[VERDICT: SKIPPED-UNREACHABLE]' },
            @{ skill = 'agy-test-audit'; token = '[VERDICT: EXHAUSTIVE]' },
            @{ skill = 'agy-capstone';   token = 'FOLDED: ' },
            @{ skill = 'agy-capstone';   token = 'REJECTED: ' },
            @{ skill = 'agy-capstone';   token = 'DISCARDED-BELOW-FLOOR: ' },
            @{ skill = 'agy-capstone';   token = 'DEFERRED-TO-ANOMALIES: ' },
            @{ skill = 'agy-capstone';   token = 'UNVERIFIED-ACCEPTED: ' },
            @{ skill = 'agy-test-audit'; token = 'FOLDED: ' },
            @{ skill = 'agy-test-audit'; token = 'REJECTED: ' },
            @{ skill = 'agy-test-audit'; token = 'DISCARDED-BELOW-FLOOR: ' },
            @{ skill = 'agy-test-audit'; token = 'DEFERRED-TO-ANOMALIES: ' },
            @{ skill = 'agy-test-audit'; token = 'UNVERIFIED-ACCEPTED: ' }
        ) {
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            $body = (Get-Content -Raw $target).Replace($token, '[VERDICT: GONE]')
            Set-Content -Path $target -Value $body -Encoding utf8
            & $script:Lint -Root $scratch 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
            Remove-Item -Recurse -Force $scratch
        }

        It 'fails cleanly (no unhandled crash) on an empty <skill> file' -ForEach @(
            @{ skill = 'agy-first' }, @{ skill = 'agy-capstone' }, @{ skill = 'agy-test-audit' }
        ) {
            # Capstone R1 (Cascade): a 0-byte SKILL.md made Get-Content -Raw return $null, and
            # $raw.Contains() threw an unhandled terminating error instead of a clean Fail.
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            Set-Content -Path $target -Value '' -NoNewline -Encoding utf8
            $out = & $script:Lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 1
            ($out -join "`n") | Should -Match 'EMPTY'
            ($out -join "`n") | Should -Not -Match 'null-valued expression'
            Remove-Item -Recurse -Force $scratch
        }

        It 'fails when name: is absent from <skill> real frontmatter even if present in the body' -ForEach @(
            @{ skill = 'agy-first' }, @{ skill = 'agy-capstone' }, @{ skill = 'agy-test-audit' }
        ) {
            # Capstone R1 (Protocol/Mechanism): the old lazy (?ms).*? frontmatter regex spanned past the
            # closing fence, so a 'name:' smuggled into the body plus any body '---' falsely satisfied it.
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            $real = Get-Content -Raw $target
            $body = ($real -replace "(?m)^name:\s*$skill\s*\r?\n", '') + "`nname: $skill`n---`n"
            Set-Content -Path $target -Value $body -NoNewline -Encoding utf8
            & $script:Lint -Root $scratch 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
            Remove-Item -Recurse -Force $scratch
        }
    }

    Context 'guard census: every linter Fail branch must have a test that reddens if the guard is deleted' {
        # AGY-TEST-AUDIT over 43c1a9c..614ca00 (2026-08-08) measured the linter's 10 Fail() sites and found
        # FIVE unguarded: :41 MISSING, :55 malformed-frontmatter, :71 agy_ask, :72 classic transport,
        # :74 marker constant. Each could be deleted outright with this suite still green at 30/0, while a
        # positive control (neutering the non-ASCII guard at :68) produced 27/3 - so the greens were real
        # gaps, not a broken harness. The rows below close all five.
        #
        # Each row asserts the FAILURE MESSAGE, not merely `exit 1`. Fail() is non-terminating, so several
        # diagnostics can co-occur in one run; matching the specific message keeps the row pointed at ITS
        # guard instead of passing on whichever guard happens to fire. Each fixture also self-checks that
        # its mutation took effect, so a silent no-op cannot leave the row passing vacuously.

        It 'fails with a MISSING diagnostic when a skill file is absent' {
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch 'agy-test-audit'
            Remove-Item -Force $target
            (Test-Path $target) | Should -BeFalse -Because 'the fixture must actually remove the skill file'
            $out = & $script:Lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 1
            ($out -join "`n") | Should -Match 'MISSING'
            Remove-Item -Recurse -Force $scratch
        }

        It 'fails with a malformed-frontmatter diagnostic when the leading --- fences are absent' {
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch 'agy-test-audit'
            $real = Get-Content -Raw $target
            # Strip the whole frontmatter block; the body retains every other invariant, so the ONLY
            # reachable complaint is the malformed-frontmatter branch.
            $body = $real -replace "(?s)\A---\r?\n.*?\r?\n---\r?\n", ''
            $body | Should -Not -Be $real -Because 'the frontmatter block must actually be stripped'
            $body | Should -Not -Match "\A---" -Because 'the file must no longer open with a fence'
            Set-Content -Path $target -Value $body -NoNewline -Encoding utf8
            $out = & $script:Lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 1
            ($out -join "`n") | Should -Match 'malformed frontmatter'
            Remove-Item -Recurse -Force $scratch
        }

        It 'fails with a "<diagnostic>" diagnostic when <needle> is stripped from the skill' -ForEach @(
            @{ needle = 'agy_ask';                   diagnostic = 'missing dotnet transport' },
            @{ needle = 'clavity ask --review-only'; diagnostic = 'missing classic transport' },
            @{ needle = '.clavity/agy-marks/';       diagnostic = 'missing marker-contract constant' }
        ) {
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch 'agy-test-audit'
            $real = Get-Content -Raw $target
            $real.Contains($needle) | Should -BeTrue -Because "the fixture needs '$needle' present to strip"
            $body = $real.Replace($needle, '')
            $body | Should -Not -Be $real -Because 'the strip must take effect'
            Set-Content -Path $target -Value $body -NoNewline -Encoding utf8
            $out = & $script:Lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 1
            ($out -join "`n") | Should -Match $diagnostic
            Remove-Item -Recurse -Force $scratch
        }

        It 'fails when the review-only safety envelope is stripped from <skill>' -ForEach @(
            @{ skill = 'agy-first' },
            @{ skill = 'agy-capstone' },
            @{ skill = 'agy-test-audit' },
            @{ skill = 'adversarial-panel-review' }
        ) {
            # AGY-TEST-AUDIT 2026-08-31, and this row exists because the gap was MEASURED, not supposed:
            # with a control run first (rc=0 on an unmutated copy), deleting the entire 30-line safety
            # envelope from adversarial-panel-review/SKILL.md left the linter printing 'agy-discipline
            # skills OK' and exiting 0. Nothing in the repository noticed. The envelope is what keeps a
            # review-only consult review-only, and the live peer has breached it twice in eight rounds,
            # so its deletion has to be a red gate rather than a silent drift.
            #
            # One step is stripped rather than the whole block: it isolates the new check, and it is the
            # realistic regression - an edit that reorganises the section and drops a step is far likelier
            # than one that deletes all five at once.
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            $real = Get-Content -Raw $target
            $real.Contains('Diff after') | Should -BeTrue -Because "the fixture needs the envelope present in $skill before it can be stripped"
            $body = $real.Replace('Diff after', '')
            $body | Should -Not -Be $real -Because 'the strip must take effect'
            Set-Content -Path $target -Value $body -NoNewline -Encoding utf8
            $out = & $script:Lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 1
            ($out -join "`n") | Should -Match 'safety-envelope step'
            Remove-Item -Recurse -Force $scratch
        }

        It 'fails when <skill> does not instruct the caller to name its discipline (13b)' -ForEach @(
            @{ skill = 'agy-first' },
            @{ skill = 'agy-capstone' },
            @{ skill = 'agy-test-audit' },
            @{ skill = 'adversarial-panel-review' }
        ) {
            # The driver's completeness checks only run when the ask NAMES its discipline, so a skill that
            # stops telling the caller to name it silently downgrades every one of its consults to
            # UNCHECKED. This row exists for all FOUR - adversarial-panel-review included, which carried no
            # lint at all before 13b.
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            $needle  = 'discipline: "' + $skill + '"'
            $real = Get-Content -Raw $target
            $real.Contains($needle) | Should -BeTrue -Because "the fixture needs '$needle' present to strip"
            $body = $real.Replace($needle, 'discipline: "something-else"')
            $body | Should -Not -Be $real -Because 'the strip must take effect'
            Set-Content -Path $target -Value $body -NoNewline -Encoding utf8
            $out = & $script:Lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 1
            ($out -join "`n") | Should -Match 'will run UNCHECKED'
            ($out -join "`n") | Should -Match ([regex]::Escape($skill))
            Remove-Item -Recurse -Force $scratch
        }

        It 'REJECTS <skill> when its closer omits the anti-wrap-up clause' -ForEach @(
            @{ skill = 'agy-first' },
            @{ skill = 'agy-capstone' },
            @{ skill = 'agy-test-audit' },
            @{ skill = 'adversarial-panel-review' }
        ) {
            # NON-VACUITY BY CONSTRUCTION: the scratch root holds all four skills, so this fails on the
            # PERTURBED skill, never on a missing sibling. Perturb exactly one and require exit 1.
            #
            # THE ANCHOR IS `> Put`, NOT `Put` OR `**Put`. The clause ships as BLOCKQUOTED PAYLOAD text,
            # because unmarked it read as a rule about the driver's own reply - measured, and it
            # contradicted agy-capstone's "they emit **no** token" for intermediate rounds. Stripping the
            # marked line is therefore the right mutant: it is the form the guard must reject.
            # THE TEST AND THE LINTER MUST AGREE ABOUT THE SAME STRING or one of them is guarding nothing.
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            $real = Get-Content -Raw $target
            $body = $real -replace '(?m)^> Put nothing after the terminal token\..*$', ''
            $body | Should -Not -Be $real -Because 'the mutant must actually apply, or this row proves nothing'
            Set-Content -Path $target -Value $body -NoNewline -Encoding utf8
            $out = & $script:Lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 1
            ($out -join "`n") | Should -Match 'anti-wrap-up'
            ($out -join "`n") | Should -Match ([regex]::Escape($skill))
            Remove-Item -Recurse -Force $scratch
        }

        It 'REJECTS agy-capstone when the PEER-side axis is called "disposition" again' {
            # 21.2. TWO AXES, ONE WORD: `claim-type` is what KIND of claim the PEER made; `disposition` is
            # the DRIVER's closed five-token AGY-SCOPE set. `defect` is not one of those five, which is
            # exactly why calling the peer-side axis "disposition" dangled. This row restores the old
            # wording and requires the linter to reject it.
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch 'agy-capstone'
            $real = Get-Content -Raw $target
            $body = $real.Replace('survives its `claim-type` as a real', 'survives disposition as a real')
            $body | Should -Not -Be $real -Because 'the mutant must actually apply, or this row proves nothing'
            Set-Content -Path $target -Value $body -NoNewline -Encoding utf8
            $out = & $script:Lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 1
            ($out -join "`n") | Should -Match 'claim-type'
            Remove-Item -Recurse -Force $scratch
        }

        It 'REJECTS <skill> when the inline JSON reply contract is stripped' -ForEach @(
            @{ skill = 'agy-capstone' },
            @{ skill = 'agy-test-audit' }
        ) {
            # The checker validates a schema; this contract is what TELLS the peer to emit it. Ship one
            # without the other and the reader is validating a shape nothing ever asked for.
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            $real = Get-Content -Raw $target
            $body = $real -replace '(?m)^\*\*Demand the JSON block in your payload too\*\*.*$', ''
            $body | Should -Not -Be $real -Because 'the strip must take effect, or this row proves nothing'
            Set-Content -Path $target -Value $body -NoNewline -Encoding utf8
            $out = & $script:Lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 1
            ($out -join "`n") | Should -Match 'inline JSON reply contract'
            Remove-Item -Recurse -Force $scratch
        }

        It 'REJECTS <skill> when the contract KEY LIST drifts from SCHEMAS - <case>' -ForEach @(
            @{ skill = 'agy-capstone';   case = 'whole list deleted, header kept'; from = ''; to = '' },
            @{ skill = 'agy-test-audit'; case = 'whole list deleted, header kept'; from = ''; to = '' },
            @{ skill = 'agy-capstone';   case = 'one key dropped';   from = '`evidence`, `trigger`, `severity`'; to = '`evidence`, `severity`' },
            @{ skill = 'agy-capstone';   case = 'two keys reordered'; from = '`seat`, `id`, `file`'; to = '`id`, `seat`, `file`' },
            @{ skill = 'agy-capstone';   case = 'strictness line gone'; from = 'and no others are accepted'; to = 'and other keys are fine' },
            # CAPSTONE R2: the sequence match was UNANCHORED, so it verified the markdown was a SUPERSET
            # of SCHEMAS and nothing more. An appended key left the linter GREEN while the skill
            # instructed the peer to emit a key the checker rejects - the drift this oracle exists to
            # prevent, running in the one direction nobody had tested. Both ends are now bounded.
            @{ skill = 'agy-capstone';   case = 'key APPENDED';  from = '`severity`, `detail`.'; to = '`severity`, `detail`, `smuggled`.' },
            @{ skill = 'agy-capstone';   case = 'key PREPENDED'; from = 'accepted - `seat`,';    to = 'accepted - `smuggled`, `seat`,' }
        ) {
            # CAPSTONE R1 MEASURED THE HOLE THIS CLOSES: the entire blockquoted key list could be deleted
            # while the bold header above it stayed, and the linter exited 0 - it pinned a heading and
            # certified a contract. The peer independently named skill/SCHEMAS divergence as the thing
            # most likely to be quietly wrong in six months.
            #
            # THE REORDER ROW IS NOT DECORATION. The FIRST version of this guard asked whether each key
            # appeared SOMEWHERE in the blockquote, and its own control proved that hollow: dropping
            # `trigger` from the list left `Phrase `trigger` as a FALSIFIABLE PREDICTION` two lines
            # below, the guard found it there, and the drop went green. Matching the whole comma-separated
            # sequence pins ORDER and MEMBERSHIP together, so a row that changes only order must red.
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            $real = Get-Content -Raw $target
            if ($from -eq '') {
                $body = $real -replace '(?m)^> Emit one fenced .*(\r?\n> .*)*', ''
            } else {
                $real.Contains($from) | Should -BeTrue -Because "the fixture needs '$from' present to mutate"
                $body = $real.Replace($from, $to)
            }
            $body | Should -Not -Be $real -Because 'the mutation must take effect, or this row proves nothing'
            Set-Content -Path $target -Value $body -NoNewline -Encoding utf8
            $out = & $script:Lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 1
            # ASSERT THE SPECIFIC DIAGNOSTIC, NOT A DISJUNCTION. This line read
            # 'key list does not match SCHEMAS|does not tell the peer...' until
            # AGY-TEST-AUDIT 2026-09-02: every case here reddens the key-list oracle, so the
            # alternation let the whole set pass on that one diagnostic while the strictness
            # guard could be deleted outright. The Context's own comment argues against
            # exactly this - "matching the specific message keeps the row pointed at ITS
            # guard instead of passing on whichever guard happens to fire" - and this one row
            # did the opposite. The strictness guard now has an isolating row of its own.
            ($out -join "`n") | Should -Match 'key list does not match SCHEMAS'
            Remove-Item -Recurse -Force $scratch
        }

        It 'REJECTS a skill that names ANOTHER discipline in its checker invocation' {
            # THE COPY-PASTE ROW. The two contracts differ in three places and this is the difference that
            # fails silently: an audit brief naming agy-capstone has its rows validated against the
            # CAPSTONE's keys, so `missing_test` is rejected and `trigger` waved through, and no output
            # anywhere says the wrong schema was used.
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch 'agy-test-audit'
            $real = Get-Content -Raw $target
            $body = $real.Replace('<reply.json> <sha> agy-test-audit', '<reply.json> <sha> agy-capstone')
            $body | Should -Not -Be $real -Because 'the cross-wire must take effect'
            Set-Content -Path $target -Value $body -NoNewline -Encoding utf8
            $out = & $script:Lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 1
            ($out -join "`n") | Should -Match 'does not name its OWN checker invocation'
            Remove-Item -Recurse -Force $scratch
        }

        It 'REJECTS agy-capstone when the claim-type sentence is DELETED outright' {
            # The row above only catches a RENAME back. A guard that is purely negative ("the old word must
            # not appear") goes green on an empty file, so this row deletes the sentence instead and
            # requires the positive half of the invariant to fire. Both halves, or the guard has a hole
            # you can drive a deletion through.
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch 'agy-capstone'
            $real = Get-Content -Raw $target
            $body = $real -replace '(?m)^A finding that survives its `claim-type` as a real.*$', ''
            $body | Should -Not -Be $real -Because 'the deletion must actually apply, or this row proves nothing'
            Set-Content -Path $target -Value $body -NoNewline -Encoding utf8
            $out = & $script:Lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 1
            ($out -join "`n") | Should -Match 'claim-type'
            Remove-Item -Recurse -Force $scratch
        }
    }

    Context 'F3 guard: a skill enrolled in $skills but not mapped in $requiredVerdicts must fail loud' {
        It 'fails LOUD when a skill is enrolled in $skills but has no $requiredVerdicts mapping (F3 guard)' {
            # Build a temp linter whose $skills array has an extra 'phantom-unmapped' entry that is
            # deliberately NOT added to $requiredVerdicts. This is the exact shape the ContainsKey guard
            # exists to catch: without it, `foreach ($v in $requiredVerdicts[$skill])` iterates $null and
            # silently verifies nothing, so a skill with zero enforced invariants would pass clean.
            # THE ISOLATION THIS ROW CLAIMS WAS FALSE UNTIL AGY-TEST-AUDIT 2026-09-02 MEASURED IT.
            # The comment above used to end "so the ONLY possible failure is the missing
            # $requiredVerdicts mapping". The run actually emitted ELEVEN diagnostics: :115 twice - the
            # temp linter's $PSScriptRoot is TEMP, so the schema registry beside it is absent - plus
            # :197, :202 five times, :208 and :223, because the old phantom satisfied only the
            # $skills-loop invariants and none of the $disciplineNames-loop ones. The row still passed,
            # because its needle is specific; but a fixture that trips six unrelated guards is not the
            # controlled experiment its own comment advertised, and two of the guards it tripped by
            # accident were branches this suite believed it was not covering at all.
            $realSrc = Get-Content -Raw $script:Lint
            $needle  = "`$skills = @('agy-first', 'agy-capstone', 'agy-test-audit')"
            $realSrc.Contains($needle) | Should -BeTrue -Because 'the mutation target line must match the real linter verbatim'
            $mutated = $realSrc.Replace($needle, "`$skills = @('agy-first', 'agy-capstone', 'agy-test-audit', 'phantom-unmapped')")
            $mutated | Should -Not -Be $realSrc -Because 'the phantom-skill injection into $skills must take effect; if the source array formatting changed, update the injection regex'
            $tmpLint = New-TempLinter -Source $mutated -Checker real

            $scratch = New-ScratchRoot
            $pdir = Join-Path $scratch 'clavity-dotnet/plugin/skills/phantom-unmapped'
            New-Item -ItemType Directory -Force -Path $pdir | Out-Null
            Set-Content -Path (Join-Path $pdir 'SKILL.md') -Value $script:PhantomSkill -NoNewline -Encoding utf8

            try {
                $guardOut = & pwsh -NoProfile -File $tmpLint -Root $scratch 2>&1
                $LASTEXITCODE | Should -Be 1
                $text = Get-LintText $guardOut
                $text | Should -Match 'no required-verdict set mapped'
                # THE ISOLATION IS NOW ASSERTED, not merely asserted ABOUT. Every one of these fired in
                # the old fixture. Any of them returning means the phantom skill or the temp-linter
                # staging has drifted, and this row has quietly stopped being a controlled experiment.
                $text | Should -Not -Match 'names a checker that is not there' -Because 'New-TempLinter -Checker real must place the registry beside the linter'
                $text | Should -Not -Match 'does not instruct the caller to pass'
                $text | Should -Not -Match 'safety-envelope step'
                $text | Should -Not -Match 'names no sanctioned scratch directory'
                $text | Should -Not -Match 'missing the anti-wrap-up clause'
            } finally {
                Remove-Item -Recurse -Force (Split-Path -Parent $tmpLint) -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'AGY-TEST-AUDIT 2026-09-02: four Fail branches that had no reddening row' {
        # Every row here was authored against a MEASURED gap, never a supposed one. The method was a
        # logic mutant: force the guard's condition false, re-run this suite, see what reddens. All four
        # branches reddened NOTHING at 59/0, so each could have been deleted outright with the gate still
        # certifying the skills. A positive control ran alongside - neutering a DIFFERENT guard reddened
        # exactly its own row - so the greens were real gaps and not a broken harness.

        It 'REJECTS <skill> when the sanctioned scratch directory is stripped' -ForEach @(
            @{ skill = 'agy-first' },
            @{ skill = 'agy-capstone' },
            @{ skill = 'agy-test-audit' },
            @{ skill = 'adversarial-panel-review' }
        ) {
            # The envelope row above strips 'Diff after' and reddens the envelope-step branch. This is a
            # SEPARATE Fail on the next line of the linter and had no row at all. It is what gives a
            # measure-and-reproduce consult somewhere to write other than the repository root, and a peer
            # under a prohibition-only banner has dumped files into a repo root here before - one of them
            # overwriting an untracked file unrecoverably.
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            $real = Get-Content -Raw $target
            $real.Contains('.clavity/scratch/') | Should -BeTrue -Because "the fixture needs the scratch dir present in $skill before it can be stripped"
            $body = $real.Replace('.clavity/scratch/', '')
            $body | Should -Not -Be $real -Because 'the strip must take effect'
            Set-Content -Path $target -Value $body -NoNewline -Encoding utf8
            $out = & $script:Lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 1
            (Get-LintText $out) | Should -Match 'names no sanctioned scratch directory'
            Remove-Item -Recurse -Force $scratch
        }

        It 'REJECTS agy-capstone when the strictness line is no longer BLOCKQUOTED' {
            # THE ISOLATING ROW, and the reason its sibling's assertion had to be split in two.
            # The existing 'strictness line gone' case replaces the very phrase the KEY-LIST regex is
            # built from, so it reddens BOTH branches; asserted as a disjunction, it passed on the other
            # guard's diagnostic and this one could be deleted unnoticed. Neutered: 59/0.
            #
            # Removing only the '> ' prefix separates them. The key sequence stays contiguous, so the
            # key-list oracle still matches, while '(?m)^>.*and no others are accepted' no longer does.
            # The blockquote is the load-bearing half: '> ' marks the one text that is verbatim PAYLOAD
            # rather than prose addressed to the driver, so an unquoted contract instructs nobody.
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch 'agy-capstone'
            $real = Get-Content -Raw $target
            $body = $real.Replace("`n> discipline and no others are accepted", "`ndiscipline and no others are accepted")
            $body | Should -Not -Be $real -Because 'the un-blockquoting must take effect, or this row proves nothing'
            Set-Content -Path $target -Value $body -NoNewline -Encoding utf8
            $out = Get-LintText (& $script:Lint -Root $scratch 2>&1)
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'does not tell the peer that undeclared keys are REJECTED'
            $out | Should -Not -Match 'key list does not match SCHEMAS' -Because 'this row must ISOLATE the strictness guard from the key-list oracle, or it proves nothing its sibling did not'
            Remove-Item -Recurse -Force $scratch
        }

        It 'REJECTS a linter that cannot find the schema registry beside itself' {
            # Reachable only by moving the LINTER, because it resolves the registry from $PSScriptRoot -
            # no fixture built under -Root can move it. Until this row the branch was exercised only BY
            # ACCIDENT, as one of the eleven diagnostics the F3 fixture used to emit; repairing that
            # fixture's isolation removed the accident, so this row is what keeps the branch covered.
            $scratch = New-ScratchRoot
            $tmpLint = New-TempLinter -Source (Get-Content -Raw $script:Lint) -Checker none
            try {
                $out = Get-LintText (& pwsh -NoProfile -File $tmpLint -Root $scratch 2>&1)
                $LASTEXITCODE | Should -Be 1
                $out | Should -Match 'names a checker that is not there'
            } finally {
                Remove-Item -Recurse -Force (Split-Path -Parent $tmpLint) -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
            }
        }

        It 'REJECTS a discipline whose schema the registry does not declare' {
            # A skill's inline contract is enforceable only if SCHEMAS carries a matching entry. Neutered,
            # 59/0: the entry could be renamed or deleted with the gate still green, while every reply
            # from that discipline would then be validated against nothing at all.
            # The mutation RENAMES rather than deletes, so the registry stays valid Python and the
            # failure is the missing-entry branch rather than a syntax error somewhere else.
            $py = Get-Content -Raw (Join-Path $script:RepoRoot 'scripts/check-peer-reply-citations.py')
            $py.Contains('"agy-test-audit":') | Should -BeTrue -Because 'the registry entry must be present to be renamed away'
            $noEntry = $py.Replace('"agy-test-audit":', '"agy-test-audit-RENAMED":')
            $scratch = New-ScratchRoot
            $tmpLint = New-TempLinter -Source (Get-Content -Raw $script:Lint) -Checker $noEntry
            try {
                $out = Get-LintText (& pwsh -NoProfile -File $tmpLint -Root $scratch 2>&1)
                $LASTEXITCODE | Should -Be 1
                $out | Should -Match 'declares no SCHEMAS entry'
                $out | Should -Not -Match 'names a checker that is not there' -Because 'the registry must be PRESENT for this row to reach the entry check'
            } finally {
                Remove-Item -Recurse -Force (Split-Path -Parent $tmpLint) -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'AGY-CAPSTONE 2026-09-02: the roster itself, which nothing reconciled' {
        # Every guard in this file asks whether a LISTED discipline is well-formed. None asked whether the
        # list is COMPLETE, so a fifth discipline skill added to the tree and forgotten in
        # $disciplineNames was linted by nothing while the gate still exited 0. The mutant method cannot
        # surface this class at all - there was no branch to neuter, which is precisely why it survived an
        # audit that neutered every branch there was.
        #
        # THE ORACLE IS THE REGISTRY, NOT THE FOLDER LISTING. Discovering skills from disk was measured
        # and rejected: the tree holds SEVEN skill folders and only four are disciplines, so discovery
        # emitted 38 diagnostics against ls-driving, ls-pairing and open-issues and turned the gate red.

        It 'REJECTS a SCHEMAS entry that the roster never checks' {
            # Direction one: the registry grows a discipline and the linter is not told. Without the
            # reconciliation the gate stays green while that discipline's skill file is read by nothing.
            $py = Get-Content -Raw (Join-Path $script:RepoRoot 'scripts/check-peer-reply-citations.py')
            $anchor = '    "agy-first":'
            $py.Contains($anchor) | Should -BeTrue -Because 'the registry entry used as the insertion anchor must exist verbatim'
            $extra = $py.Replace($anchor, "    `"agy-negotiate`":  [`"seat`", `"file`", `"quoted_line`"],`n$anchor")
            $extra | Should -Not -Be $py -Because 'the phantom registry entry must take effect'

            $scratch = New-ScratchRoot
            $tmpLint = New-TempLinter -Source (Get-Content -Raw $script:Lint) -Checker $extra
            try {
                $out = Get-LintText (& pwsh -NoProfile -File $tmpLint -Root $scratch 2>&1)
                $LASTEXITCODE | Should -Be 1
                $out | Should -Match 'declares SCHEMAS entries this linter never checks: agy-negotiate'
            } finally {
                Remove-Item -Recurse -Force (Split-Path -Parent $tmpLint) -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
            }
        }

        It 'REJECTS a roster name the registry does not declare' {
            # Direction two, and it is a SEPARATE Fail rather than the mirror image: this one fires when a
            # discipline is added to the linter but never registered, so every reply it produces would be
            # validated against nothing. Asserted separately because one guard covering both directions
            # would pass on whichever half happens to fire.
            $realSrc = Get-Content -Raw $script:Lint
            $needle  = "`$disciplineNames = `$skills + @('adversarial-panel-review')"
            $realSrc.Contains($needle) | Should -BeTrue -Because 'the roster line must match the real linter verbatim'
            $mutated = $realSrc.Replace($needle, "`$disciplineNames = `$skills + @('adversarial-panel-review', 'agy-phantom')")
            $mutated | Should -Not -Be $realSrc -Because 'the phantom roster name must take effect'

            $scratch = New-ScratchRoot
            $tmpLint = New-TempLinter -Source $mutated -Checker real
            try {
                $out = Get-LintText (& pwsh -NoProfile -File $tmpLint -Root $scratch 2>&1)
                $LASTEXITCODE | Should -Be 1
                $out | Should -Match 'declares no SCHEMAS entry for: agy-phantom'
            } finally {
                Remove-Item -Recurse -Force (Split-Path -Parent $tmpLint) -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
            }
        }

        It 'REFUSES to accept a discipline named only in the checker DOCSTRING' {
            # AGY-CAPSTONE R2, and this row exists because the guard above FAILED OPEN in its first
            # form. Scanning the whole .py for a four-space-indented '"name": [' reconciled a phantom
            # named in the module docstring as though it were registered: the linter exited 0 while the
            # checker itself exits "unknown discipline" on that name at runtime.
            #
            # MEASURED across three smuggle shapes before the fix. Only the DOCSTRING body smuggles -
            # '#' at column 0 fails '^\s{4}"', and four spaces then '#' fails it too - so this row pins
            # the one shape that was reachable. The fix scopes the scan to the 'SCHEMAS = {' block.
            $py = Get-Content -Raw (Join-Path $script:RepoRoot 'scripts/check-peer-reply-citations.py')
            $docLine = 'Exit 0 = every row matched its schema and every quoted_line resolved; 1 = at least one problem.'
            $py.Contains($docLine) | Should -BeTrue -Because 'the docstring line used as the injection anchor must exist verbatim'
            $smuggled = $py.Replace($docLine, $docLine + "`n`nExample of a registry row:`n    `"agy-phantom`": [`"seat`"]")
            $smuggled | Should -Not -Be $py -Because 'the docstring injection must take effect'

            $realSrc = Get-Content -Raw $script:Lint
            $needle  = "`$disciplineNames = `$skills + @('adversarial-panel-review')"
            $realSrc.Contains($needle) | Should -BeTrue -Because 'the roster line must match the real linter verbatim'
            $mutated = $realSrc.Replace($needle, "`$disciplineNames = `$skills + @('adversarial-panel-review', 'agy-phantom')")

            $scratch = New-ScratchRoot
            $tmpLint = New-TempLinter -Source $mutated -Checker $smuggled
            try {
                $out = Get-LintText (& pwsh -NoProfile -File $tmpLint -Root $scratch 2>&1)
                $LASTEXITCODE | Should -Be 1
                $out | Should -Match 'declares no SCHEMAS entry for: agy-phantom' -Because 'a name that appears only in the docstring is NOT registered, and the reconciliation must say so'
                $out | Should -Not -Match 'could not locate' -Because 'the SCHEMAS block is present and parseable in this fixture; this row must isolate the smuggle from the block-not-found branch'
            } finally {
                Remove-Item -Recurse -Force (Split-Path -Parent $tmpLint) -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
            }
        }

        It 'FAILS CLOSED, and says so, when the SCHEMAS block cannot be located at all' {
            # A separate Fail from the two reconciliation branches, because an unparseable registry and
            # an empty one are indistinguishable by their effect: both would report every roster name as
            # unregistered - a true red for a false reason, sending the reader after four phantom
            # mismatches instead of the one real problem.
            $py = Get-Content -Raw (Join-Path $script:RepoRoot 'scripts/check-peer-reply-citations.py')
            $py.Contains('SCHEMAS = {') | Should -BeTrue -Because 'the block opener must be present to be removed'
            $noBlock = $py.Replace('SCHEMAS = {', 'SCHEMAS = dict(')

            $scratch = New-ScratchRoot
            $tmpLint = New-TempLinter -Source (Get-Content -Raw $script:Lint) -Checker $noBlock
            try {
                $out = Get-LintText (& pwsh -NoProfile -File $tmpLint -Root $scratch 2>&1)
                $LASTEXITCODE | Should -Be 1
                $out | Should -Match "did not find exactly ONE 'SCHEMAS = \{' assignment"
                $out | Should -Match 'unparseable' -Because 'this fixture removes the block entirely, so the diagnostic must name that cause alongside duplication'
                $out | Should -Not -Match 'declares no SCHEMAS entry for:' -Because 'the block-not-found branch suppresses the second diagnostic deliberately; four phantom mismatches would bury the real cause'
            } finally {
                Remove-Item -Recurse -Force (Split-Path -Parent $tmpLint) -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
            }
        }

        It 'CATCHES registry drift even when a DECOY key list sits in the docstring' {
            # AGY-CAPSTONE R3, and this is the SECOND instance of the class R2 found. R2 bounded the
            # ROSTER scan to the SCHEMAS block and left the PER-SKILL key-list lookup scanning the whole
            # file, so the same defect survived one line away from its own fix. That is what comes of
            # folding the instance a reviewer reports instead of enumerating the set.
            #
            # THIS IS THE FALSE-GREEN DIRECTION, which is the one that matters. [regex]::Match returns
            # the FIRST match, so a decoy carrying the CORRECT keys in the docstring is read as the
            # registry while the REAL entry has drifted. Measured before the fix: the oracle went GREEN
            # on a registry with an appended key - the exact defect capstone R2 of the previous range
            # folded, arriving by a different route. The control below, the same drift with no decoy,
            # was CAUGHT both before and after.
            $py = Get-Content -Raw (Join-Path $script:RepoRoot 'scripts/check-peer-reply-citations.py')

            # Drift the REAL entry FIRST, while its line is still unique - inserting the decoy would
            # make this text appear twice and .Replace() would drift both copies.
            $realLine = '                       "claim-type", "evidence", "trigger", "severity", "detail"],'
            $py.Contains($realLine) | Should -BeTrue -Because 'the agy-capstone key list must match verbatim to be drifted'
            $drifted = $py.Replace($realLine, '                       "claim-type", "evidence", "trigger", "severity", "detail", "smuggled"],')
            $drifted | Should -Not -Be $py -Because 'the registry drift must take effect'

            $docLine = 'Exit 0 = every row matched its schema and every quoted_line resolved; 1 = at least one problem.'
            $decoy = @'


Example of a registry row:
    "agy-capstone":   ["seat", "id", "file", "line", "quoted_line",
                       "claim-type", "evidence", "trigger", "severity", "detail"],
'@
            $drifted.Contains($docLine) | Should -BeTrue -Because 'the docstring anchor must exist verbatim'
            $withDecoy = $drifted.Replace($docLine, $docLine + $decoy)
            $withDecoy | Should -Not -Be $drifted -Because 'the decoy injection must take effect'

            $scratch = New-ScratchRoot
            $tmpLint = New-TempLinter -Source (Get-Content -Raw $script:Lint) -Checker $withDecoy
            try {
                $out = Get-LintText (& pwsh -NoProfile -File $tmpLint -Root $scratch 2>&1)
                $LASTEXITCODE | Should -Be 1
                $out | Should -Match 'key list does not match SCHEMAS' -Because 'the drifted REAL entry must be the one read, not the decoy above it'
                $out | Should -Match 'smuggled' -Because 'the diagnostic must name the keys from the REAL entry, which is how this row distinguishes the two sources'
            } finally {
                Remove-Item -Recurse -Force (Split-Path -Parent $tmpLint) -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
            }
        }

        It 'LOCATES the SCHEMAS block even when its closing brace is indented' {
            # AGY-CAPSTONE R3, the reviewer's finding. Anchoring the closer at column 0 assumed a
            # formatter that never indents it; the block holds only key/list pairs and no nested dict,
            # so the first line whose content is a closing brace IS the closer at any indent.
            # Asserted as a PASS rather than a rejection: the point is that an indented brace must NOT
            # trip the block-not-found branch, and a green run is the only thing that says so.
            # LINE-ENDING AGNOSTIC, and the first version of this row was not - it anchored on
            # "`n}`nREQUIRED" and its own precondition assertion caught it, because this .py is CRLF in
            # the working tree and LF as committed. A regex on the line start touches only the brace and
            # leaves whatever terminator follows it alone.
            $py = Get-Content -Raw (Join-Path $script:RepoRoot 'scripts/check-peer-reply-citations.py')
            ([regex]::Matches($py, '(?m)^\}')).Count | Should -Be 1 -Because 'exactly one closing brace sits at column 0 - the SCHEMAS closer - so indenting "all of them" indents only it'
            $indented = $py -replace '(?m)^\}', '    }'
            $indented | Should -Not -Be $py -Because 'the indent must take effect'

            $scratch = New-ScratchRoot
            $tmpLint = New-TempLinter -Source (Get-Content -Raw $script:Lint) -Checker $indented
            try {
                $out = Get-LintText (& pwsh -NoProfile -File $tmpLint -Root $scratch 2>&1)
                $LASTEXITCODE | Should -Be 0 -Because 'an indented closing brace is valid Python and must not break the registry read'
                $out | Should -Not -Match 'exactly ONE'
            } finally {
                Remove-Item -Recurse -Force (Split-Path -Parent $tmpLint) -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
            }
        }

        It 'REFUSES TO GUESS when a second SCHEMAS assignment exists' {
            # AGY-CAPSTONE R4, and it is the THIRD time this class has been folded. R2 bounded the roster
            # scan; R3 bounded the per-skill lookup through a shared helper; and the helper still had to
            # DECIDE which block was the registry, taking the first match. A decoy 'SCHEMAS = {' block at
            # column 0 in the module docstring was read as the registry and a drifted real entry passed -
            # MEASURED, the same smuggle one level up.
            #
            # The fix is not a cleverer pattern but a refusal: count the assignments, and fail unless
            # there is exactly one. That ends the class instead of narrowing it, because ANY future decoy
            # raises the count rather than having to be anticipated.
            $py = Get-Content -Raw (Join-Path $script:RepoRoot 'scripts/check-peer-reply-citations.py')
            ([regex]::Matches($py, '(?m)^SCHEMAS\s*=\s*\{')).Count | Should -Be 1 -Because 'the real file must carry exactly one assignment for a second to be a mutation'

            $docLine = 'Exit 0 = every row matched its schema and every quoted_line resolved; 1 = at least one problem.'
            $decoy = @'


SCHEMAS = {
    "agy-capstone":   ["seat", "id", "file", "line", "quoted_line",
                       "claim-type", "evidence", "trigger", "severity", "detail"],
}
'@
            $py.Contains($docLine) | Should -BeTrue -Because 'the docstring anchor must exist verbatim'
            $twoBlocks = $py.Replace($docLine, $docLine + $decoy)
            ([regex]::Matches($twoBlocks, '(?m)^SCHEMAS\s*=\s*\{')).Count | Should -Be 2 -Because 'the decoy must actually add a second assignment, or this row proves nothing'

            $scratch = New-ScratchRoot
            $tmpLint = New-TempLinter -Source (Get-Content -Raw $script:Lint) -Checker $twoBlocks
            try {
                $out = Get-LintText (& pwsh -NoProfile -File $tmpLint -Root $scratch 2>&1)
                $LASTEXITCODE | Should -Be 1
                $out | Should -Match 'exactly ONE' -Because 'an ambiguous registry must be refused, not guessed at'
                $out | Should -Match 'DUPLICATED' -Because 'the diagnostic must name duplication as a cause; "could not locate" sent the reader looking for a missing block that is present twice'
            } finally {
                Remove-Item -Recurse -Force (Split-Path -Parent $tmpLint) -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
            }
        }

        It 'ACCEPTS valid input a strict anchor used to reject - <case>' -ForEach @(
            @{ case = 'a QUOTED frontmatter name';   find = 'name: agy-first';                          repl = 'name: "agy-first"' },
            @{ case = 'an INDENTED anti-wrap clause'; find = "`n> Put nothing after the terminal token."; repl = "`n  > Put nothing after the terminal token." }
        ) {
            # AGY-CAPSTONE R4. Both anchors produced a LOUD FALSE RED on input that is perfectly valid in
            # its own format - YAML lets a scalar be quoted, and markdown lets a blockquote carry up to
            # three leading spaces. Neither could ever produce a false GREEN, which is why both are MINOR;
            # they cost a maintainer an afternoon, not a shipped defect.
            #
            # THE BLOCKQUOTE FIX WENT TO THE SET, NOT THE INSTANCE. The reviewer reported the anti-wrap
            # anchor; the linter had TWO '(?m)^>' anchors and both were loosened, because R3's whole
            # lesson was that folding the reported instance leaves the class one line away.
            #
            # Asserted as a PASS. A green run is the only thing that says valid input is accepted, and
            # these rows redden immediately if either anchor is tightened back.
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch 'agy-first'
            $real = Get-Content -Raw $target
            $real.Contains($find) | Should -BeTrue -Because "the fixture needs '$find' present verbatim before it can be rewritten"
            $body = $real.Replace($find, $repl)
            $body | Should -Not -Be $real -Because 'the rewrite must take effect'
            Set-Content -Path $target -Value $body -NoNewline -Encoding utf8

            $out = & $script:Lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 0 -Because "$case is valid in its own format and must not trip a gate"
            (Get-LintText $out) | Should -Match 'agy-discipline skills OK'
            Remove-Item -Recurse -Force $scratch
        }
    }
}

Describe 'AGY-SCOPE disposition taxonomy' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:Tokens = @(
            'FOLDED: '
            'REJECTED: '
            'DISCARDED-BELOW-FLOOR: '
            'DEFERRED-TO-ANOMALIES: '
            'UNVERIFIED-ACCEPTED: '
        )
    }

    It 'ships every disposition token in <skill>' -ForEach @(
        @{ skill = 'agy-capstone' }
        @{ skill = 'agy-test-audit' }
        @{ skill = 'adversarial-panel-review' }
    ) {
        foreach ($driver in @('clavity-dotnet', 'clavity-classic')) {
            $p = Join-Path $script:RepoRoot "$driver/plugin/skills/$skill/SKILL.md"
            $raw = Get-Content -Raw $p
            foreach ($t in $script:Tokens) {
                $raw.Contains($t) | Should -BeTrue -Because "$driver/$skill must carry the token '$t'"
            }
        }
    }

    It 'forbids age as a disposition in <skill>' -ForEach @(
        @{ skill = 'agy-capstone' }
        @{ skill = 'agy-test-audit' }
        @{ skill = 'adversarial-panel-review' }
    ) {
        foreach ($driver in @('clavity-dotnet', 'clavity-classic')) {
            $p = Join-Path $script:RepoRoot "$driver/plugin/skills/$skill/SKILL.md"
            (Get-Content -Raw $p).Contains("A defect's age is NEVER a disposition.") |
                Should -BeTrue -Because "$driver/$skill must carry the age clause"
        }
    }
}

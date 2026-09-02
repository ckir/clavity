# scripts/tests/check-agy-discipline-skills.Tests.ps1
BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Lint     = Join-Path $script:RepoRoot 'scripts/check-agy-discipline-skills.ps1'

    # Stage a scratch -Root containing a VALID copy of EVERY shipped discipline skill, so a rejection
    # test that perturbs ONE skill fails on THAT defect, not on a MISSING sibling (SP-B: once
    # 'agy-capstone' joined $skills, a fixture staging only agy-first exited 1 for MISSING agy-capstone,
    # silently losing its discriminating power).
    function New-ScratchRoot {
        $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("agyskilltest-" + [guid]::NewGuid())
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
            $realSrc = Get-Content -Raw $script:Lint
            $needle  = "`$skills = @('agy-first', 'agy-capstone', 'agy-test-audit')"
            $realSrc.Contains($needle) | Should -BeTrue -Because 'the mutation target line must match the real linter verbatim'
            $mutated = $realSrc.Replace($needle, "`$skills = @('agy-first', 'agy-capstone', 'agy-test-audit', 'phantom-unmapped')")
            $mutated | Should -Not -Be $realSrc -Because 'the phantom-skill injection into $skills must take effect; if the source array formatting changed, update the injection regex'
            $tmpLint = Join-Path ([IO.Path]::GetTempPath()) ("lint-" + [guid]::NewGuid().ToString('N') + ".ps1")
            Set-Content -Path $tmpLint -Value $mutated -Encoding utf8

            # Scratch root with all real skills (New-ScratchRoot) plus a VALID phantom skill dir that
            # satisfies every OTHER invariant (frontmatter name==dir, ASCII, both transports, marker
            # constant) so the ONLY possible failure is the missing $requiredVerdicts mapping.
            $scratch = New-ScratchRoot
            $pdir = Join-Path $scratch 'clavity-dotnet/plugin/skills/phantom-unmapped'
            New-Item -ItemType Directory -Force -Path $pdir | Out-Null
            $valid = "---`nname: phantom-unmapped`n---`nTransport: the agy_ask MCP tool and clavity ask --review-only.`nMarker at .clavity/agy-marks/ per contract.`n"
            Set-Content -Path (Join-Path $pdir 'SKILL.md') -Value $valid -NoNewline -Encoding utf8

            try {
                $guardOut = & pwsh -NoProfile -File $tmpLint -Root $scratch 2>&1
                $LASTEXITCODE | Should -Be 1
                ($guardOut -join "`n") | Should -Match 'no required-verdict set mapped'
            } finally {
                Remove-Item -Force $tmpLint -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
            }
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

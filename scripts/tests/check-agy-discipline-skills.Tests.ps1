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
        foreach ($s in @('agy-first', 'agy-capstone', 'agy-test-audit')) {
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

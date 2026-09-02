# The repository's own .gitignore PRIVACY rules, pinned behaviourally.
#
# WHY THIS EXISTS. AGY-TEST-AUDIT 2026-09-02 found `e89d4cb`'s `.claude/*.local.md` rule had zero
# coverage anywhere in the repository - measured, `grep -rn 'local\.md' --include=*.ps1 --include=*.rs
# --include=*.sh --include=*.yml` returned nothing. This is a PUBLIC repository, and that rule is the
# only thing standing between a per-developer plugin config full of LOCAL MACHINE PATHS and a push.
# Its failure mode is silent by construction: the rule stops matching, `git add` sweeps the file in, and
# nothing anywhere says a word. A rule whose only verification was one hand-check at the commit that
# introduced it is a rule that decays.
#
# THE ORACLE IS `git check-ignore`, NOT A TEXT MATCH ON .gitignore. Grepping for the pattern string
# would certify a rule that a later negation (`!.claude/keep.local.md`), a reordering, or a
# `.git/info/exclude` interaction had already neutered - git's own matcher is the only thing that knows
# what git will actually do. Every row below asks git.
#
# EVERY ROW ASSERTS **WHICH**, NOT **HOW MANY**. `check-ignore -v` names the file and line of the rule
# that matched, so the rows pin THAT rule rather than "something ignored it" - a second, unrelated rule
# swallowing the path would otherwise read as this rule working.

Describe 'gitignore privacy policy' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

        # Returns the matching rule as `<file>:<line>:<pattern>`, or $null when git does not ignore the
        # path. NOTE the paths below need not EXIST: check-ignore matches patterns, not the filesystem,
        # which is what lets this suite pin the rule without creating a single file in the work tree.
        function script:Get-IgnoreRule {
            param([string]$RelPath)
            $out = & git -C $script:RepoRoot check-ignore -v -- $RelPath 2>$null
            $code = $LASTEXITCODE
            # THREE OUTCOMES, NOT TWO, AND CONFLATING TWO OF THEM WAS A REAL DEFECT. MEASURED:
            # `git check-ignore` exits 0 = ignored, 1 = NOT ignored, 128 = git itself failed. The first
            # version of this function returned $null for anything non-zero, so "not ignored" and
            # "git is broken" became the same answer - and three of the four rows below assert exactly
            # that $null. A broken git would have passed them silently, including the CONTROL row whose
            # entire job is to prove this oracle can answer no. The control shared the oracle's failure
            # mode, which makes it no control at all. Found by an audit of this file; the shape is the
            # same fail-open the rest of this suite exists to catch.
            if ($code -eq 1) { return $null }              # a genuine "not ignored"
            if ($code -ne 0) {
                throw "git check-ignore failed with exit $code for '$RelPath' - the oracle is broken, so no row in this suite can be trusted"
            }
            if (-not $out) {
                throw "git check-ignore exited 0 for '$RelPath' but printed nothing - unparseable oracle output"
            }
            # `check-ignore -v` emits `<source>:<linenum>:<pattern>\t<pathname>`; keep the rule half.
            return (($out | Select-Object -First 1) -split "`t")[0]
        }
    }

    It 'ignores a per-developer plugin config, and by the .claude/*.local.md rule specifically' {
        $rule = script:Get-IgnoreRule '.claude/x.local.md'
        $rule | Should -Not -BeNullOrEmpty -Because 'a *.local.md under .claude/ carries local machine paths and must never be publishable from this PUBLIC repo'
        # WHICH rule, not merely that one existed. If `.claude/` as a whole were ever ignored by a
        # broader rule, this row would still go green while the specific protection had been deleted.
        $rule | Should -Match '(^|[\\/])\.gitignore:\d+:\.claude/\*\.local\.md$' -Because "the match must come from the dedicated rule, not from some broader pattern that happens to cover it today; got '$rule'"
    }

    It 'does NOT ignore .claude/settings.json - the control that proves this oracle can answer no' {
        # WITHOUT THIS ROW THE SUITE IS UNFALSIFIABLE. An oracle that returns "ignored" for every input
        # certifies nothing, and `check-ignore` returning a non-zero exit on a typo'd path would look
        # exactly like a clean pass to the row above. `.claude/settings.json` is TRACKED, so the correct
        # answer here is a hard no.
        script:Get-IgnoreRule '.claude/settings.json' | Should -BeNullOrEmpty -Because 'settings.json is tracked and shared; if this reads as ignored the oracle is broken, not the policy'
    }

    It 'does NOT ignore near-misses that only resemble the pattern' {
        # DISTRACTORS. A rule broadened to `*local*` or `.claude/*` would still pass the first row while
        # silently swallowing files that are meant to be tracked. Each of these was MEASURED as
        # not-ignored on 2026-09-02; each would start being ignored under a sloppier pattern.
        foreach ($near in @('.claude/local.md', '.claude/x.local.md.bak')) {
            script:Get-IgnoreRule $near | Should -BeNullOrEmpty -Because "'$near' does not end in the protected suffix, so a rule that ignores it is broader than intended"
        }
    }

    It 'has no *.local.md file tracked anywhere in the repository' {
        # THE OUTCOME the rule exists to produce, asserted independently of the rule itself. The rows
        # above pin git's matcher; this one pins the actual index, so a file added with `git add -f`
        # before the rule existed cannot hide behind a correctly-working pattern.
        $tracked = @(& git -C $script:RepoRoot ls-files -- '*.local.md')
        # THE SAME FAIL-OPEN AS Get-IgnoreRule, AND FIXING THAT ONE ALONE LEFT THIS ONE OPEN - caught by
        # the paired control, not by reading. `git ls-files` prints nothing and exits non-zero when git
        # fails, which is INDISTINGUISHABLE from the healthy "nothing is tracked" answer this row wants.
        # MEASURED against a deliberately broken git: with only the other fix in place this row was the
        # last one still passing vacuously. A different command needs its own check; one guard does not
        # cover a sibling just because the failure mode is the same shape.
        if ($LASTEXITCODE -ne 0) {
            throw "git ls-files failed with exit $LASTEXITCODE - this row cannot distinguish 'nothing tracked' from 'git did not run'"
        }
        $tracked | Should -BeNullOrEmpty -Because "a *.local.md in the index is already published whatever .gitignore says; found: $($tracked -join ', ')"
    }
}

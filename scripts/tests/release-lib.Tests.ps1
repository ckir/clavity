BeforeAll { . (Join-Path $PSScriptRoot '..' 'lib' 'release-lib.ps1') }

Describe 'Get-BumpLevel (F7/F10)' {
    It 'any ! => breaking, regardless of type' {
        Get-BumpLevel @('chore!: drop win10') | Should -Be 'breaking'
        Get-BumpLevel @('feat(ui)!: x')        | Should -Be 'breaking'
    }
    It 'case-insensitive; Fix:/FEAT: are not dropped' {
        Get-BumpLevel @('FEAT: x') | Should -Be 'minor'
        Get-BumpLevel @('Fix: y')  | Should -Be 'patch'
    }
    It 'feat=minor, fix/revert=patch, chore/ci/docs=none' {
        Get-BumpLevel @('feat: x')   | Should -Be 'minor'
        Get-BumpLevel @('revert: y') | Should -Be 'patch'
        Get-BumpLevel @('chore: z','ci: w','docs: d') | Should -Be 'none'
    }
    It 'precedence: breaking beats minor beats patch' {
        Get-BumpLevel @('fix: a','feat: b','refactor!: c') | Should -Be 'breaking'
        Get-BumpLevel @('fix: a','feat: b')                | Should -Be 'minor'
    }
    It 'a non-conventional subject does not raise the level' {
        Get-BumpLevel @('fixed the crash','fix: real') | Should -Be 'patch'
    }
}

Describe 'Get-AbandonedSerials + Get-NextSerial (retracted-serial burn / ghost-tag guard)' {
    BeforeAll {
        function New-AbandonRepo {
            $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("aban-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $dir | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $dir 'scripts') | Out-Null
            Push-Location $dir
            git init -q; git config user.email t@t; git config user.name t; git config commit.gpgsign false
            Pop-Location
            return $dir
        }
        function Set-Abandon([string]$repo, [string]$content) {
            Set-Content (Join-Path $repo 'scripts/release-abandoned.txt') $content
        }
    }
    It '(a) parses clavity-vN lines, ignoring blanks and full-line # comments' {
        $repo = New-AbandonRepo
        try {
            Set-Abandon $repo "# a comment`nclavity-v9`n`nclavity-v3`n# clavity-v99 disabled"
            (Get-AbandonedSerials $repo | Sort-Object) | Should -Be @(3, 9)
        } finally { Remove-Item -Recurse -Force $repo }
    }
    It '(b) returns empty when the file is absent' {
        $repo = New-AbandonRepo
        try { Get-AbandonedSerials $repo | Should -BeNullOrEmpty } finally { Remove-Item -Recurse -Force $repo }
    }
    It '(c) burns a retracted serial with NO git tags (fresh-clone ghost-tag guard)' {
        $repo = New-AbandonRepo
        try {
            Set-Abandon $repo 'clavity-v9'          # no clavity-v* tags at all (mirrors a fresh clone)
            Get-NextSerial $repo | Should -Be 10
        } finally { Remove-Item -Recurse -Force $repo }
    }
    It '(d) takes the max across BOTH tags and the abandoned list' {
        $repo = New-AbandonRepo
        try {
            Push-Location $repo; git commit -q --allow-empty -m seed; git tag clavity-v11; Pop-Location
            Set-Abandon $repo 'clavity-v9'
            Get-NextSerial $repo | Should -Be 12    # tag v11 wins over abandoned v9
        } finally { Remove-Item -Recurse -Force $repo }
    }
    It '(e) strips an INLINE comment before matching (regression: swallow bug)' {
        $repo = New-AbandonRepo
        try {
            Set-Abandon $repo 'clavity-v9   # retracted: broken installers'
            Get-AbandonedSerials $repo | Should -Be 9
        } finally { Remove-Item -Recurse -Force $repo }
    }
}

Describe 'Test-Conventional' {
    It 'flags non-conforming subjects' {
        Test-Conventional 'fix: x'          | Should -BeTrue
        Test-Conventional 'fixed the crash' | Should -BeFalse
        Test-Conventional 'FEAT(a)!: x'     | Should -BeTrue
    }
}

Describe 'Step-SemverVersion (F3 pre-1.0 rule)' {
    It '<1.0.0 never auto-crosses to 1.0.0' {
        Step-SemverVersion '0.1.0' 'breaking' | Should -Be '0.2.0'
        Step-SemverVersion '0.1.2' 'minor'    | Should -Be '0.2.0'
        Step-SemverVersion '0.1.2' 'patch'    | Should -Be '0.1.3'
    }
    It '>=1.0.0 uses normal semver' {
        Step-SemverVersion '1.0.0' 'breaking' | Should -Be '2.0.0'
        Step-SemverVersion '1.4.2' 'minor'    | Should -Be '1.5.0'
        Step-SemverVersion '1.4.2' 'patch'    | Should -Be '1.4.3'
    }
    It 'rejects a non-semver current' {
        { Step-SemverVersion '1.2' 'patch' } | Should -Throw
    }
}

Describe 'Read-IssVersion' {
    It 'reads #define AppVersion' {
        $f = New-TemporaryFile
        Set-Content $f '#define AppVersion "0.4.1"' -NoNewline
        Read-IssVersion $f | Should -Be '0.4.1'
        Remove-Item $f
    }
}

Describe 'Format-Sanitized (F14)' {
    It 'clamps to one line, escapes table-breakers, strips control chars' {
        Format-Sanitized "feat: a | b`nc"       | Should -Be 'feat: a \| b c'
        Format-Sanitized "fix: `t tab`r end"    | Should -Match 'fix:'
        (Format-Sanitized "x`nlie") -notmatch "`n" | Should -BeTrue
    }
    It 'escapes a leading HTML/comment opener' {
        Format-Sanitized '<!-- sneaky' | Should -Be '&lt;!-- sneaky'
    }
}

Describe 'Group-Notes (F10 grouping)' {
    It 'routes ! to Breaking, feat to Features, fix/revert to Fixes' {
        $g = Group-Notes @('feat!: big','feat: nice','fix: bug','revert: oops','chore: skip')
        $g.Breaking | Should -Be @('feat!: big')
        $g.Features | Should -Be @('feat: nice')
        $g.Fixes    | Should -Be @('fix: bug','revert: oops')
    }
}

# Describe 'Get-GhidrustChannel' removed 2026-09-14: ghidrust was fully retired and the function it tested
# (the only dual-channel member's per-channel split) was deleted from release-lib.ps1.

Describe 'Format-ReleaseNotes (CC1 aggregated body)' {
    It 'renders per-member grouped sections' {
        $bump = [pscustomobject]@{ Key='classic'; Channel=$null; Current='0.1.2'; Next='0.2.0'; Level='minor';
            Notes=[pscustomobject]@{ Breaking=@(); Features=@('feat: nice'); Fixes=@('fix: bug') } }
        $md = Format-ReleaseNotes @($bump)
        $md | Should -Match 'classic 0.1.2 -> 0.2.0'
        $md | Should -Match '### Features'
        $md | Should -Match 'feat: nice'
        $md | Should -Match 'fix: bug'
    }
}

Describe 'Update-Changelog' {
    It 'creates and prepends newest-first' {
        $root = New-TemporaryFile; Remove-Item $root; New-Item -ItemType Directory $root | Out-Null
        $bump = [pscustomobject]@{ Key='classic'; Channel=$null; Root='m'; Next='0.2.0';
            Notes=[pscustomobject]@{ Breaking=@(); Features=@('feat: x'); Fixes=@() } }
        New-Item -ItemType Directory (Join-Path $root 'm') | Out-Null
        $p = Update-Changelog $root $bump '2026-07-12'
        (Get-Content -Raw $p) | Should -Match '## 0.2.0 - 2026-07-12'
        Remove-Item -Recurse -Force $root
    }

    # THE SEPARATOR IS ASCII BY CONTRACT, not by taste. Two members (agy-autotrain, commonmemory) ship
    # their CHANGELOG.md inside the injected-context domain, which check-injected-context.ps1 gates to
    # pure ASCII. This writer emitted an em dash (U+2014), so EVERY release re-broke that gate: commit
    # b2a6cc0 sanitised the files by hand and the very next release (clavity-v18, 7ec45fd) put the em
    # dash straight back, red again on the first run whose path filter let the workflow start. Sanitising
    # the OUTPUT can never hold while the GENERATOR emits it - this test is on the generator.
    It 'emits a pure-ASCII section, so a release cannot re-break the injected-context gate' {
        $root = New-TemporaryFile; Remove-Item $root; New-Item -ItemType Directory $root | Out-Null
        $bump = [pscustomobject]@{ Key='agy-autotrain'; Channel=$null; Root='m'; Next='0.5.0';
            Notes=[pscustomobject]@{ Breaking=@(); Features=@('feat: x'); Fixes=@('fix: y') } }
        New-Item -ItemType Directory (Join-Path $root 'm') | Out-Null
        $p = Update-Changelog $root $bump '2026-09-18'
        $text = Get-Content -Raw $p
        # Assert the CHARACTER, not "looks fine": a non-ASCII byte renders normally in most viewers,
        # which is exactly why this kept shipping. Names the offenders so a failure is actionable.
        $bad = [regex]::Matches($text, '[^\x00-\x7F]') | ForEach-Object { '0x{0:X4}' -f [int][char]$_.Value }
        $bad -join ',' | Should -BeExactly '' -Because 'a shipped CHANGELOG must be pure ASCII'
        Remove-Item -Recurse -Force $root
    }
}

Describe 'Get-DanglingReleaseCommits / Test-ResumeState / Get-DropConflictStatus / Invoke-DropReleaseCandidate (release.ps1 -Resume support)' {
    BeforeAll {
        # Each scenario needs a real origin remote: Get-DanglingReleaseCommits reads origin/main..HEAD,
        # and release.ps1's own precondition-0 requires `git fetch` to succeed against a real remote.
        function New-ResumeRepo {
            $dir  = Join-Path ([System.IO.Path]::GetTempPath()) ("reslib-" + [guid]::NewGuid().ToString('N'))
            $bare = "$dir.git"
            New-Item -ItemType Directory -Path $dir | Out-Null
            git init -q --bare $bare | Out-Null
            Push-Location $dir
            git init -q -b main . | Out-Null
            git config user.email t@t; git config user.name t; git config commit.gpgsign false
            git remote add origin $bare
            'v1' | Set-Content version.txt
            git add -A; git commit -q -m 'chore(release): clavity-v1'
            git push -q origin main
            return @{ Dir = $dir; Bare = $bare }
        }
    }

    Context 'Get-DanglingReleaseCommits' {
        It 'returns empty when there is no un-pushed chore(release) commit' {
            $repo = New-ResumeRepo
            try {
                'x' | Set-Content f.txt; git add -A; git commit -q -m 'feat: x'
                @(Get-DanglingReleaseCommits $repo.Dir) | Should -BeNullOrEmpty
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }

        # AGY-TEST-AUDIT 2026-09-22: this test was named '... newest-first, trimmed' but asserted nothing
        # about trimming. MEASURED: deleting the function's `.Trim()` leaves the whole suite 37/37 GREEN,
        # because `git log --format=%H` never emits surrounding whitespace on this platform - so the
        # `.Trim()` is unobservable defence and NO test can kill that mutant. The honest fix is to stop
        # claiming it in the name and to pin the CONTRACT that actually matters instead: each element is
        # a bare 40-character hex sha. See docs/accepted-boundaries.md for the recorded boundary.
        It 'returns matching SHAs newest-first, each a bare 40-hex sha' {
            $repo = New-ResumeRepo
            try {
                'v2' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
                $sha2 = (git rev-parse HEAD).Trim()
                'v3' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v3 [x 0.3.0]'
                $sha3 = (git rev-parse HEAD).Trim()
                $found = @(Get-DanglingReleaseCommits $repo.Dir)
                $found.Count | Should -Be 2
                $found[0] | Should -Be $sha3
                $found[1] | Should -Be $sha2
                foreach ($f in $found) { $f | Should -MatchExactly '^[0-9a-f]{40}$' }
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }

        # AGY-TEST-AUDIT + AGY-CAPSTONE rounds 3-5, 2026-09-22. These two rows pin a DESIGN, not just a
        # branch. Three successive attempts to INFER which commits are already pushed from an incomplete
        # local view were each measured destructive or wrong, so the function now REFUSES whenever
        # origin/main is absent, for any reason. The oracle is the throw, and the second row additionally
        # asserts the SHIPPED COMMIT SURVIVES - which is the property all of this exists to protect.
        It 'origin/main absent: REFUSES rather than guessing, and says how to recover' {
            $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("resnoorigin-" + [guid]::NewGuid().ToString('N'))
            $bare = "$dir.git"
            New-Item -ItemType Directory -Path $dir | Out-Null
            git init -q --bare $bare | Out-Null
            Push-Location $dir
            try {
                git init -q -b main . | Out-Null
                git config user.email t@t; git config user.name t; git config commit.gpgsign false
                # A remote EXISTS (so release.ps1's own `git fetch` succeeds) but main was never pushed.
                git remote add origin $bare
                'hello' | Set-Content f.txt; git add -A; git commit -q -m 'feat: the very first feature'
                (git rev-parse --verify --quiet origin/main) | Should -BeNullOrEmpty -Because 'the fixture must actually lack origin/main, or this test pins nothing'

                { Get-DanglingReleaseCommits $dir } | Should -Throw -ExpectedMessage '*origin/main is not present*'
                # The TYPE is part of the contract, not an implementation detail: both callers filter on
                # it, and a generic BCL type would let an unrelated structural error wear the refusal's
                # clothes (AGY-CAPSTONE rounds 7-8). Pinning it here means a revert to a BCL type reddens.
                { Get-DanglingReleaseCommits $dir } | Should -Throw -ExceptionType ([ReleaseRefusalException])
                # The message must carry BOTH recoveries, since a stale view and a never-pushed repo need
                # different commands and the refusal is the only place the user is told which to run.
                { Get-DanglingReleaseCommits $dir } | Should -Throw -ExpectedMessage '*git fetch origin*'
                { Get-DanglingReleaseCommits $dir } | Should -Throw -ExpectedMessage '*git push -u origin main*'
            } finally { Pop-Location; Remove-Item -Recurse -Force $dir; Remove-Item -Recurse -Force $bare }
        }

        # The case that made refusal the design. MEASURED before this fold: with a SHIPPED release pushed
        # and the tracking ref then pruned, the function returned that shipped sha and Test-ResumeState
        # reported Ok=$true on it - so -Resume would have rebased away a released commit. Silent history
        # loss. `git log HEAD --not --remotes` was measured here too and is destructive in exactly this
        # case, which is why it was not adopted despite being better on branch naming.
        It 'origin/main pruned while a release is already SHIPPED: refuses, and the shipped commit survives' {
            $repo = New-ResumeRepo
            try {
                'v1' | Set-Content shipped.txt
                git add -A; git commit -q -m 'chore(release): clavity-v9 [x 0.9.0]'
                git push -q origin main
                $shipped = (git rev-parse HEAD).Trim()

                git update-ref -d refs/remotes/origin/main
                (git rev-parse --verify --quiet origin/main) | Should -BeNullOrEmpty -Because 'the fixture must actually lack the tracking ref, or this test pins nothing'
                @(git ls-remote --heads origin main) | Should -Not -BeNullOrEmpty -Because 'the remote MUST still have main - that is what made the naive answer destructive'

                { Get-DanglingReleaseCommits $repo.Dir } | Should -Throw -ExpectedMessage '*origin/main is not present*'
                (git rev-parse HEAD).Trim() | Should -Be $shipped -Because 'refusing must leave the shipped release exactly where it was'
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }

        # AGY-TEST-AUDIT 2026-09-22: the explicit --basic-regexp flag carries a comment explaining that it
        # guards against a host configured with grep.patternType=extended, but NO test set that config -
        # MEASURED, deleting the flag left the suite 37/37 GREEN. Under ERE `^chore(release):` parses
        # `(release)` as a capture group, so the pattern matches the literal 'chorerelease:' and a real
        # `chore(release):` subject is MISSED - the gate would then fail open on a genuine candidate.
        It 'honours --basic-regexp: still finds a candidate on a host with grep.patternType=extended' {
            $repo = New-ResumeRepo
            try {
                git config grep.patternType extended
                (git config --get grep.patternType) | Should -Be 'extended' -Because 'the hostile config must actually be set, or this test pins nothing'
                'v2' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
                $sha = (git rev-parse HEAD).Trim()
                @(Get-DanglingReleaseCommits $repo.Dir) | Should -Be $sha
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }

        # Precedent: scripts/tests/compute-release.Tests.ps1 'anchors to the subject start' - mirrored here
        # because Get-DanglingReleaseCommits shares the same ^chore(release): subject-anchoring contract.
        It 'anchors to the subject start, ignoring a body/mid-message mention' {
            $repo = New-ResumeRepo
            try {
                'v2' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
                $realSha = (git rev-parse HEAD).Trim()
                'x' | Set-Content f.txt; git add -A; git commit -q -m 'docs: update the chore(release): clavity-v process'
                @(Get-DanglingReleaseCommits $repo.Dir) | Should -Be $realSha
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }
    }

    Context 'Test-ResumeState' {
        It 'no dangling candidate: Ok=$false, Sha=$null, names "no half-finished release to resume"' {
            $repo = New-ResumeRepo
            try {
                'x' | Set-Content f.txt; git add -A; git commit -q -m 'feat: x'
                $st = Test-ResumeState $repo.Dir
                $st.Ok  | Should -BeFalse
                $st.Sha | Should -BeNullOrEmpty
                ($st.Problems -match 'no half-finished release to resume').Count | Should -Be 1
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }

        It 'exactly one dangling candidate: Ok=$true, Sha set to that commit, no Problems' {
            $repo = New-ResumeRepo
            try {
                'v2' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
                $sha = (git rev-parse HEAD).Trim()
                $st = Test-ResumeState $repo.Dir
                $st.Ok  | Should -BeTrue
                $st.Sha | Should -Be $sha
                $st.Problems | Should -BeNullOrEmpty
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }

        It 'dirty tracked (unstaged) tree: Ok=$false, names "uncommitted tracked changes"' {
            $repo = New-ResumeRepo
            try {
                'v2' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
                'dirty' | Set-Content version.txt
                $st = Test-ResumeState $repo.Dir
                $st.Ok | Should -BeFalse
                ($st.Problems -match 'uncommitted tracked changes').Count | Should -Be 1
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }

        It 'staged-only change also counts as dirty (both halves of "clean" are checked)' {
            $repo = New-ResumeRepo
            try {
                'v2' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
                'staged' | Set-Content version.txt; git add -A
                $st = Test-ResumeState $repo.Dir
                $st.Ok | Should -BeFalse
                ($st.Problems -match 'uncommitted tracked changes').Count | Should -Be 1
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }

        # AGY-TEST-AUDIT + AGY-CAPSTONE rounds 3-5, 2026-09-22. Companion to the two refusal rows above,
        # one level up: Test-ResumeState must not LAUNDER the refusal into its friendly "there is no
        # half-finished release to resume" string. MEASURED before the fold that is exactly what it did -
        # Ok=$false with a reason telling the developer the opposite of the truth, which is worse than a
        # raw failure because it reads as a clean, actionable answer a developer would act on.
        It 'origin/main absent: REPORTS the refusal as a Problem, never answering "no half-finished release"' {
            $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("resnoorigin2-" + [guid]::NewGuid().ToString('N'))
            $bare = "$dir.git"
            New-Item -ItemType Directory -Path $dir | Out-Null
            git init -q --bare $bare | Out-Null
            Push-Location $dir
            try {
                git init -q -b main . | Out-Null
                git config user.email t@t; git config user.name t; git config commit.gpgsign false
                git remote add origin $bare
                'v1' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v1'
                $sha = (git rev-parse HEAD).Trim()
                (git rev-parse --verify --quiet origin/main) | Should -BeNullOrEmpty -Because 'the fixture must actually lack origin/main, or this test pins nothing'

                $state = Test-ResumeState $dir
                $state.Ok  | Should -BeFalse -Because 'the undetermined case must fail CLOSED'
                $state.Sha | Should -BeNullOrEmpty
                ($state.Problems -join ' ') | Should -Match 'origin/main is not present'
                ($state.Problems -join ' ') | Should -Not -Match 'no half-finished release to resume' -Because 'that wording is the confidently-wrong answer this whole fold exists to remove'

                # And the candidate is still exactly where it was: a refusal changes nothing.
                (git rev-parse HEAD).Trim() | Should -Be $sha
            } finally { Pop-Location; Remove-Item -Recurse -Force $dir; Remove-Item -Recurse -Force $bare }
        }

        # AGY-CAPSTONE round 7 (Mechanism Gamer). The catch that restores the contract must not be BARE.
        # MEASURED with this exact fixture before the fold: an undefined command inside the callee came
        # back as `Ok=$false` with "The term ... is not recognized" sitting in Problems - a script bug
        # laundered into a domain refusal with its stack trace destroyed, which is the worst possible
        # outcome for whoever has to debug it. Only the library's OWN typed refusal may be converted.
        # The redefinition below shadows the callee for this scope, which is how PowerShell resolves it
        # from inside Test-ResumeState.
        It 'a PROGRAMMING error in the callee propagates, and is not laundered into a refusal' {
            $repo = New-ResumeRepo
            try {
                function Get-DanglingReleaseCommits([string]$RepoRoot) { Undefined-Cmdlet-For-This-Test }

                { Test-ResumeState $repo.Dir } | Should -Throw -ExpectedMessage '*Undefined-Cmdlet-For-This-Test*'
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }

        # AGY-CAPSTONE round 6 (Cascade Analyst). Test-ResumeState's contract is to RETURN every problem
        # so the orchestrator prints them all and dies once. Before this fold the callee's throw escaped
        # and DISCARDED the working-tree problem gathered moments earlier, so a developer with BOTH faults
        # was told about neither in a readable form. This row pins the BATCH property, which is exactly
        # what an escaping throw destroys - and it asserts BOTH strings, because asserting only the count
        # would pass for any two problems at all.
        It 'dirty tree AND origin/main absent: reports BOTH problems, not just the one that threw' {
            $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("resboth-" + [guid]::NewGuid().ToString('N'))
            $bare = "$dir.git"
            New-Item -ItemType Directory -Path $dir | Out-Null
            git init -q --bare $bare | Out-Null
            Push-Location $dir
            try {
                git init -q -b main . | Out-Null
                git config user.email t@t; git config user.name t; git config commit.gpgsign false
                git remote add origin $bare
                'v1' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v1'
                'dirty' | Set-Content version.txt          # uncommitted tracked change
                (git rev-parse --verify --quiet origin/main) | Should -BeNullOrEmpty -Because 'the fixture must lack origin/main'
                git diff --quiet; $LASTEXITCODE | Should -Not -Be 0 -Because 'the fixture must really be dirty, or only one problem exists and this row pins nothing'

                $state = Test-ResumeState $dir
                $state.Ok | Should -BeFalse
                ($state.Problems -join ' ') | Should -Match 'uncommitted tracked changes' -Because 'the working-tree problem is the one an escaping throw discarded'
                ($state.Problems -join ' ') | Should -Match 'origin/main is not present'
            } finally { Pop-Location; Remove-Item -Recurse -Force $dir; Remove-Item -Recurse -Force $bare }
        }

        It 'two dangling candidates: Ok=$false, Sha=$null, names "refusing to guess"' {
            $repo = New-ResumeRepo
            try {
                'v2' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
                'v3' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v3 [x 0.3.0]'
                $st = Test-ResumeState $repo.Dir
                $st.Ok  | Should -BeFalse
                $st.Sha | Should -BeNullOrEmpty
                ($st.Problems -match 'refusing to guess').Count | Should -Be 1
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }
    }

    Context 'Get-DropConflictStatus' {
        It "returns the STRING 'clean' (not a bool) when HEAD IS the candidate" {
            $repo = New-ResumeRepo
            try {
                'v2' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
                $sha = (git rev-parse HEAD).Trim()
                $status = Get-DropConflictStatus $repo.Dir $sha
                $status | Should -BeOfType ([string])
                $status | Should -BeExactly 'clean'
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }

        It "returns 'clean' when a non-conflicting fix sits on top of the candidate" {
            $repo = New-ResumeRepo
            try {
                'v2' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
                $sha = (git rev-parse HEAD).Trim()
                'fixed' | Set-Content docs.md; git add -A; git commit -q -m 'fix(docs): unrelated'
                Get-DropConflictStatus $repo.Dir $sha | Should -BeExactly 'clean'
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }

        It "returns 'conflict' when the fix on top touches the same region the candidate touched" {
            $repo = New-ResumeRepo
            try {
                "# CL`n`n## 0.2.0`n- a`n" | Set-Content CHANGELOG.md
                git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
                $sha = (git rev-parse HEAD).Trim()
                "# CL`n`n## 0.2.0`n- a`n- b`n" | Set-Content CHANGELOG.md
                git add -A; git commit -q -m 'fix(docs): touch changelog'
                Get-DropConflictStatus $repo.Dir $sha | Should -BeExactly 'conflict'
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }

        # AGY-TEST-AUDIT 2026-09-22 corrected this test's NAME. It reads as though it exercises the
        # `-not $head -or -not $cand` guard, but MEASURED it does not: `git rev-parse` ECHOES a
        # well-formed 40-hex string back even for an absent object, so $cand is non-empty, the guard is
        # skipped, and merge-tree exits 128 into the `default` switch arm. That arm is what this row
        # actually pins - changing `default` to return 'clean' reddens exactly this test. The guard
        # itself returns the same 'unknown' as the fallthrough (measured), i.e. defence-in-depth that no
        # single-point mutant can kill; recorded as a boundary rather than papered over with a fake row.
        It "fails closed to 'unknown' (not a bool) via the default arm when merge-tree exits >1" {
            $repo = New-ResumeRepo
            try {
                $status = Get-DropConflictStatus $repo.Dir 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
                $status | Should -BeOfType ([string])
                $status | Should -BeExactly 'unknown'
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }

        # AGY-TEST-AUDIT 2026-09-22. The tip short-circuit looked like a pure latency optimisation, so a
        # test for it would normally be vacuous - MEASURED, deleting it leaves the suite 37/37 GREEN on
        # every existing fixture. It is NOT an optimisation in one reachable case: when the tip candidate
        # is ALSO the repository's root commit, `$Sha^` does not resolve, merge-tree exits 128 and the
        # function would answer 'unknown' (which release.ps1:39 REFUSES on) instead of 'clean'. That
        # turns a legitimately resumable first release into an unresumable one. MEASURED both ways.
        It "returns 'clean' for a tip candidate that is ALSO the root commit (the short-circuit is load-bearing)" {
            $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("restiproot-" + [guid]::NewGuid().ToString('N'))
            $bare = "$dir.git"
            New-Item -ItemType Directory -Path $dir | Out-Null
            git init -q --bare $bare | Out-Null
            Push-Location $dir
            try {
                git init -q -b main . | Out-Null
                git config user.email t@t; git config user.name t; git config commit.gpgsign false
                git remote add origin $bare
                'v1' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v1 [x 0.1.0]'
                $root = (git rev-parse HEAD).Trim()
                (git rev-parse --verify --quiet "$root^") | Should -BeNullOrEmpty -Because 'the candidate must really be the ROOT, or the short-circuit is not what is under test'

                Get-DropConflictStatus $dir $root | Should -BeExactly 'clean'
            } finally { Pop-Location; Remove-Item -Recurse -Force $dir; Remove-Item -Recurse -Force $bare }
        }

        # AGY-TEST-AUDIT 2026-09-22. The try/catch carries a comment saying it exists because
        # $PSNativeCommandUseErrorActionPreference turns merge-tree's exit 1 into a TERMINATING error -
        # but no test ever set that preference, so MEASURED, replacing the catch body with 'clean' left
        # the suite 37/37 GREEN. This row flips the preference inside the It and carries its own CONTROL
        # in the SAME process: the default-preference call must answer 'conflict' (proving the fixture
        # really conflicts), and only then does the flipped call prove the catch arm caught something.
        It "returns 'unknown' via the CATCH arm when native commands throw (preference flipped)" {
            $repo = New-ResumeRepo
            try {
                'base' | Set-Content README.md; git add -A; git commit -q -m 'chore: base'
                git push -q origin main
                "# CL`n`n## 0.2.0`n- a`n" | Set-Content CHANGELOG.md
                git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
                $sha = (git rev-parse HEAD).Trim()
                "# CL`n`n## 0.2.0`n- a`n- b`n" | Set-Content CHANGELOG.md
                git add -A; git commit -q -m 'fix(docs): touch changelog'

                # CONTROL, same process: without the preference this fixture reaches the switch.
                Get-DropConflictStatus $repo.Dir $sha | Should -BeExactly 'conflict' -Because 'the control must show the fixture genuinely conflicts, or the flipped arm below proves nothing'

                $PSNativeCommandUseErrorActionPreference = $true
                $ErrorActionPreference = 'Stop'
                Get-DropConflictStatus $repo.Dir $sha | Should -BeExactly 'unknown' -Because 'with the preference on, merge-tree THROWS and only the catch arm can still return a verdict'
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }
    }

    Context 'Invoke-DropReleaseCandidate' {
        It 'tip case: resets, returns $true, reverts version, keeps prior feat commit, stays on main' {
            $repo = New-ResumeRepo
            try {
                'x' | Set-Content f.txt; git add -A; git commit -q -m 'feat: x'
                'v2' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
                $sha = (git rev-parse HEAD).Trim()
                $result = Invoke-DropReleaseCandidate $repo.Dir $sha
                $result | Should -BeOfType ([bool])
                $result | Should -BeTrue
                (Get-Content version.txt -Raw).Trim() | Should -Be 'v1'
                (git rev-parse --abbrev-ref HEAD) | Should -Be 'main'
                (git log --oneline | Select-String 'feat: x' | Measure-Object).Count | Should -Be 1
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }

        It 'non-conflicting fix on top: rebases onto the parent, keeps the fix, reverts version, stays on main' {
            $repo = New-ResumeRepo
            try {
                'v2' | Set-Content version.txt; git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
                $sha = (git rev-parse HEAD).Trim()
                'fixed' | Set-Content docs.md; git add -A; git commit -q -m 'fix(docs): unrelated'
                $result = Invoke-DropReleaseCandidate $repo.Dir $sha
                $result | Should -BeTrue
                (Test-Path docs.md) | Should -BeTrue
                (Get-Content version.txt -Raw).Trim() | Should -Be 'v1'
                (git rev-parse --abbrev-ref HEAD) | Should -Be 'main'
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }

        It 'conflicting replay: returns $false, aborts cleanly, leaves no rebase in progress, HEAD unmoved' {
            $repo = New-ResumeRepo
            try {
                "# CL`n`n## 0.2.0`n- a`n" | Set-Content CHANGELOG.md
                git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
                $sha = (git rev-parse HEAD).Trim()
                "# CL`n`n## 0.2.0`n- a`n- b`n" | Set-Content CHANGELOG.md
                git add -A; git commit -q -m 'fix(docs): touch changelog'
                $before = (git rev-parse HEAD).Trim()
                $result = Invoke-DropReleaseCandidate $repo.Dir $sha
                $result | Should -BeOfType ([bool])
                $result | Should -BeFalse
                (git rev-parse HEAD).Trim() | Should -Be $before
                (git rev-parse --abbrev-ref HEAD) | Should -Be 'main'
                (Test-Path (Join-Path $repo.Dir '.git/rebase-merge')) | Should -BeFalse
                (Test-Path (Join-Path $repo.Dir '.git/rebase-apply')) | Should -BeFalse
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }

        # AGY-CAPSTONE round 1 regression (State Corruptor seat, 2026-09-22). A plain `rebase --onto`
        # DROPS merge commits and replays their parents linearly, so recovering a release whose fix
        # arrived as a merged branch silently rewrote the maintainer's topology. Pinned by TOPOLOGY, not
        # by file contents: the flattening bug PRESERVED every file, so a content assertion stays green
        # straight through it and would pin nothing. The oracle is the merge COUNT.
        It 'preserves merge topology in the replayed commits (does not flatten a --no-ff merge)' {
            $repo = New-ResumeRepo
            try {
                'v2' | Set-Content version.txt
                git add -A; git commit -q -m 'chore(release): clavity-v2 [x 0.2.0]'
                $sha = (git rev-parse HEAD).Trim()

                git checkout -q -b sidefix
                'side' | Set-Content side.txt
                git add -A; git commit -q -m 'fix: on a branch'
                git checkout -q main
                git merge -q --no-ff sidefix -m 'Merge branch sidefix'

                @(git rev-list --merges HEAD).Count | Should -Be 1 -Because 'the fixture must actually contain a merge, or this test pins nothing'

                Invoke-DropReleaseCandidate $repo.Dir $sha | Should -BeTrue

                @(git rev-list --merges HEAD).Count | Should -Be 1 -Because 'the merge must SURVIVE the drop; a plain rebase --onto flattens it to 0'
                (git rev-parse --abbrev-ref HEAD) | Should -Be 'main'
                (Test-Path (Join-Path $repo.Dir 'side.txt')) | Should -BeTrue -Because 'the branch fix must still be present'
                (Get-Content (Join-Path $repo.Dir 'version.txt') -Raw).Trim() | Should -Be 'v1' -Because 'the dropped candidate carried the v2 bump'
            } finally { Pop-Location; Remove-Item -Recurse -Force $repo.Dir; Remove-Item -Recurse -Force $repo.Bare }
        }
    }
}

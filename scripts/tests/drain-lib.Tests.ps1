# scripts/tests/drain-lib.Tests.ps1
BeforeAll {
    # Dot-source the PARAMETER-LESS lib: no param block → no $InboxPath clobber, no main to run (F-P1).
    . (Join-Path $PSScriptRoot '..' 'drain-lib.ps1')
}

Describe "drain-lib primitives" {
    BeforeEach {
        $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ("drain-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Work | Out-Null
        $script:Inbox = Join-Path $script:Work 'agy-observations.md'
    }
    AfterEach { Remove-Item -Recurse -Force $script:Work -ErrorAction SilentlyContinue }

    Context "Resolve-InboxPath (ROADMAP 14g: the inbox is USER-LOCAL, not in the plugin tree)" {
        # Deliberately does NOT mutate $env:USERPROFILE. An earlier version did, and the save/restore
        # dance was itself the flake - drain-lib.ps1 turns on Set-StrictMode -Version Latest for this
        # whole file, and a restored-to-empty env var then reads as unset. The PROPERTY is what matters
        # and it is assertable against the real environment.
        It "defaults under the user home, and NOT into the plugin install tree" {
            $p = (Resolve-InboxPath '') -replace '\\', '/'
            $p | Should -BeLike '*/.clavity/agy-observations.md'
            # The controls. Before the move this returned
            # <LOCALAPPDATA>/Programs/agy-autotrain/plugins/agy-autotrain/knowledge/agy-observations.md,
            # so each of these reds the moment the old default comes back.
            $p | Should -Not -Match 'plugins/agy-autotrain'
            $p | Should -Not -Match '/knowledge/'
            $p | Should -Not -Match 'Programs/agy-autotrain'
        }

        It "still honours an explicit path and the CLAVITY_AGY_INBOX override, in that precedence" {
            # Without this, "hardcode the new default and ignore the arguments" passes the test above.
            Resolve-InboxPath 'C:/explicit/inbox.md' | Should -BeExactly 'C:/explicit/inbox.md'
            $saved = "$env:CLAVITY_AGY_INBOX"
            try {
                $env:CLAVITY_AGY_INBOX = 'C:/from-env/inbox.md'
                Resolve-InboxPath '' | Should -BeExactly 'C:/from-env/inbox.md'
                Resolve-InboxPath 'C:/explicit/inbox.md' | Should -BeExactly 'C:/explicit/inbox.md'
            } finally { $env:CLAVITY_AGY_INBOX = $saved }
        }
    }


    It "counts only ^- [ pending bullets, immune to a ## in observation text (F17)" {
        Set-Content -Path $script:Inbox -Value @(
            '# inbox', '', '## Pending',
            '- [heuristic] a rule about a ## heading in captured text  ·  2026-07-12',
            '- [anti-pattern] another rule  ·  2026-07-12'
        )
        (Get-PendingBulletCount -InboxPath $script:Inbox) | Should -Be 2
    }

    It "reports 0 for an empty ## Pending" {
        Set-Content -Path $script:Inbox -Value @('# inbox', '', '## Pending')
        (Get-PendingBulletCount -InboxPath $script:Inbox) | Should -Be 0
    }

    It "a no-op read-then-write round trip preserves every line OUTSIDE the Pending body" {
        # Get-PendingRegionLines (the reader) and Set-PendingBody (the writer) are the two halves of one
        # round trip, and they MUST agree on where the Pending region ends. They did not: the reader was
        # tightened to close on any heading `^#{1,6}\s` while the writer still closed only on `^##\s`.
        # A heading the writer could not match therefore closed the reader's region - so those lines were
        # NOT carried in the body - and then fell through the writer's `if ($inPending) { continue }`,
        # which drops them. A drain or abort that changed nothing DELETED the user's own prose.
        #
        # MEASURED before the fix: three lines lost here, and ZERO lost by the same fixture under the
        # reader's previous rule - which is what proved the loss came from tightening one half alone.
        $fixture = @(
            '# Untriaged agy observations',
            '',
            '## Pending',
            '',
            '- [heuristic] an observation  ·  `[corpus]` · 2026-08-25',
            '',
            '### Operator notes',
            '',
            'IMPORTANT: this section is the operator''s, not the drain''s.',
            'A second line of it.'
        )
        Set-Content -LiteralPath $script:Inbox -Value $fixture -Encoding UTF8

        # PRECONDITION: without a heading the OLD writer rule could not match, this pins nothing.
        @($fixture | Where-Object { $_ -match '^#{1,6}\s' -and $_ -notmatch '^##\s' }).Count |
            Should -BeGreaterThan 0 -Because 'the fixture must carry a heading that `^##\s` cannot match, or the asymmetry this pins cannot bite'

        # The round trip that changes nothing: read the body, write the same body straight back.
        $body = @(Get-PendingBody -InboxPath $script:Inbox)
        Set-PendingBody -InboxPath $script:Inbox -body $body

        $after = @(Get-Content -LiteralPath $script:Inbox)
        $lost  = @($fixture | Where-Object { $_.Trim() -ne '' -and $after -notcontains $_ })
        ($lost -join ' | ') | Should -BeExactly '' -Because 'a round trip that changes nothing must not DELETE anything - every line outside the Pending body belongs to the user''s document'
    }

    It "merges two Pending sections WITHOUT carrying the second document's own header into the body" {
        # The 14g migration APPENDS the whole old document, so the file arrives holding that document's
        # own `# title` line and its prose preamble. Those are not observations. Get-PendingBody closed
        # its region on `^##\s` only, so a SINGLE-hash title never closed it and every preamble line was
        # emitted as body - into the staging file handed to the curator, and back into the user's
        # canonical inbox by Restore-StagingToPending on any abort.
        #
        # The bullet COUNT stayed correct throughout. That is why the two sibling tests beside this one
        # stayed green over it: both assert only that each bullet appears exactly ONCE, and neither
        # asserts that the body holds nothing ELSE. This one does.
        $old = @(
            '# agy observations inbox (raw, project-agnostic)',
            '',
            'Captured live by `agy-learn`; drained by `agy-curate` into the GROWTH region of the shared',
            'golden-header. One bullet per observation. Project nouns are forbidden here.',
            '',
            '## Pending',
            '',
            '- [assumption] a capture migrated from the old inbox  ·  `[corpus]` · 2026-08-21'
        )
        $canonical = @(
            '# Untriaged agy observations',
            '',
            '## Pending',
            '',
            '- [heuristic] a capture the user already had  ·  `[corpus]` · 2026-08-20'
        )
        Set-Content -LiteralPath $script:Inbox -Value ($canonical + $old) -Encoding UTF8

        # PRECONDITIONS - without both of these the assertion below can pass while pinning nothing.
        $raw = @(Get-Content -LiteralPath $script:Inbox)
        @($raw | Where-Object { $_ -match '^#\s+agy observations inbox' }).Count |
            Should -Be 1 -Because 'the fixture must carry the appended document''s OWN title line, or the leak this pins cannot occur'
        @($raw | Where-Object { $_ -match '^##\s+Pending\s*$' }).Count |
            Should -Be 2 -Because 'the fixture must carry TWO Pending headings, or this is not the migrated shape at all'

        $body = @(Get-PendingBody -InboxPath $script:Inbox)
        @($body | Where-Object { $_ -match '^- \[' }).Count |
            Should -Be 2 -Because 'both documents'' observations must survive the merge - closing the region must not discard the second document''s bullets'
        $junk = @($body | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^- \[' })
        ($junk -join ' | ') | Should -BeExactly '' -Because 'the merged body must hold observations and blank lines ONLY - any header line carried into it is written into the user''s canonical inbox on restore'
    }

    It "does NOT duplicate the residue when the inbox carries TWO ## Pending headings" {
        # The 14g installer migration appends the WHOLE old document - its own header line and its own
        # `## Pending` heading included - onto the canonical inbox, so that file can legitimately arrive
        # carrying two headings. Set-PendingBody matched `^##\s+Pending\s*$` unconditionally and emitted
        # $body once PER heading, so every drain wrote the residue twice and the duplication COMPOUNDED
        # cycle over cycle. Measured before the fix: one residue bullet in, two out.
        Set-Content -Path $script:Inbox -Value @(
            '# inbox', '', '## Pending', '- [a] one',
            '# inbox', '', '## Pending', '- [b] two', '- [c] three'
        )
        # PRECONDITION - without this the assertions below could pass on a fixture that never
        # exercised the defect at all. The reader MERGES both sections, so the residue is the whole set.
        (Get-PendingBulletCount -InboxPath $script:Inbox) | Should -Be 3 -Because 'the reader merges both sections; if this is not 3 the fixture is not exercising the defect'

        Set-PendingBody -InboxPath $script:Inbox -body @('- [x] the one surviving residue bullet')

        $lines = Get-Content $script:Inbox
        @($lines | Where-Object { $_ -match 'surviving residue' }).Count |
            Should -Be 1 -Because 'the residue must be written exactly once, however many Pending headings the file carried'
        @($lines | Where-Object { $_ -match '^## Pending' }).Count |
            Should -Be 1 -Because 'the duplicate heading must be normalised away, not left to re-trigger this on the next drain'
    }

    It "moves the Pending body to a staging file and empties the live Pending section" {
        Set-Content -Path $script:Inbox -Value @('# inbox', '', '## Pending', '- [heuristic] r1  ·  x', '- [heuristic] r2  ·  x')
        $staging = Join-Path $script:Work 'agy-observations.staging.RUNID.md'
        Move-PendingToStaging -InboxPath $script:Inbox -StagingPath $staging
        (Get-PendingBulletCount -InboxPath $script:Inbox) | Should -Be 0
        (Get-Content $staging | Where-Object { $_ -match '^- \[' }).Count | Should -Be 2
        (Test-Path ($staging + '.tmp')) | Should -Be $false   # capstone-F2: the .tmp is renamed away on success
    }

    It "on a failed inbox-clear leaves NO real staging file + the inbox intact — no later abort-duplication (capstone-F2)" {
        # Simulate a partial failure: the staging .tmp is written, then the inbox clear throws (a concurrent lock).
        # The fix must leave NO file matching the staging glob (so a later abort has nothing to re-queue on top of the
        # still-full inbox) and the inbox untouched. Pre-fix (write-then-clear on the REAL path) left a real staging
        # file beside a full inbox, and abort then doubled every entry.
        Set-Content -Path $script:Inbox -Value @('# inbox', '', '## Pending', '- [heuristic] r1  ·  x', '- [heuristic] r2  ·  x')
        $staging = Join-Path $script:Work 'agy-observations.staging.RUNID.md'
        Mock Set-PendingBody { throw 'simulated concurrent inbox lock' }
        { Move-PendingToStaging -InboxPath $script:Inbox -StagingPath $staging } | Should -Throw
        (Find-StagingFile -InboxDir $script:Work) | Should -BeNullOrEmpty   # no REAL staging file (only the ignored .tmp)
        (Get-PendingBulletCount -InboxPath $script:Inbox) | Should -Be 2    # inbox intact — nothing lost, nothing to duplicate
    }

    It "restores staging bullets back under ## Pending (abort primitive)" {
        Set-Content -Path $script:Inbox -Value @('# inbox', '', '## Pending')
        $staging = Join-Path $script:Work 'agy-observations.staging.RUNID.md'
        Set-Content -Path $staging -Value @('- [heuristic] r1  ·  x', '- [heuristic] r2  ·  x')
        Restore-StagingToPending -InboxPath $script:Inbox -StagingPath $staging
        (Get-PendingBulletCount -InboxPath $script:Inbox) | Should -Be 2
    }

    It "restores VERBATIM — a non-bullet continuation line is not truncated (F-P2)" {
        # Move must be symmetric with restore: a multi-line capture survives a stage→restore round-trip.
        Set-Content -Path $script:Inbox -Value @('# inbox', '', '## Pending', '- [heuristic] r1  ·  x', '  continued detail line')
        $staging = Join-Path $script:Work 'agy-observations.staging.RUNID.md'
        Move-PendingToStaging -InboxPath $script:Inbox -StagingPath $staging
        Restore-StagingToPending -InboxPath $script:Inbox -StagingPath $staging
        (@(Get-Content $script:Inbox | Where-Object { $_ -match 'continued detail line' })).Count | Should -Be 1
    }

    It "finds an existing staging file for the refuse-guard" {
        Set-Content -Path (Join-Path $script:Work 'agy-observations.staging.ABC.md') -Value 'x'
        (Find-StagingFile -InboxDir $script:Work) | Should -Match 'staging\.ABC\.md$'
    }

    It "returns null when no staging file exists" {
        (Find-StagingFile -InboxDir $script:Work) | Should -BeNullOrEmpty
    }

    It "extracts the run-ID from a staging filename" {
        (Get-RunIdFromStaging 'C:\x\agy-observations.staging.20260712T140000000Z.md') | Should -Be '20260712T140000000Z'
    }

    It "detects a run-ID present in / absent from committed drain-log text" {
        (Test-RunIdInLog -LogText "## drain RID — x — SEED 1B->1B — verify-needed: 0" -RunId 'RID') | Should -BeTrue
        (Test-RunIdInLog -LogText "# log" -RunId 'RID') | Should -BeFalse
    }

    It "Get-SidecarRecoverySections: tolerant of a trailing header parenthetical + a ## inside a bullet (PP1/BS1)" {
        $sc = Join-Path $script:Work 'sidecar.md'
        Set-Content -Path $sc -Value @(
            '# drain proposal',
            '## Promoted', '- promoted thing',
            '## Dropped (each dropped item...)',                     # LLM appended a parenthetical to the header
            '- one-off obs mentioning a ## Notes header inline',      # a ## INSIDE a bullet must not truncate
            '- second dropped obs',
            '## Parked (verify-needed)',
            '- parked obs'
        )
        $r = Get-SidecarRecoverySections $sc
        $r | Should -Match 'one-off obs'
        $r | Should -Match 'second dropped obs'                       # not truncated by the inline ##
        $r | Should -Match 'parked obs'
        $r | Should -Not -Match 'promoted thing'                      # Promoted excluded (recoverable from git)
    }

    It "Get-SidecarRecoverySections: RETAINS the GROWTH accounting section - the record of what left GROWTH" {
        # The accounting section names every rule that left the GROWTH region and why. The sidecar holding it
        # is OVERWRITTEN every run, so if the append-only log did not keep it the record would exist only in
        # git history - and MEASURED 2026-08-27, zero commits have ever touched the proposal or the sidecar,
        # so that path has never been exercised. This assertion is what makes the retention load-bearing
        # rather than incidental; without it, widening $keep was untested and a later narrowing would be
        # silent. NOTE the assertions are POSITIVE: a `-Not -Match` here would pass vacuously if the section
        # were dropped entirely, which is the exact failure it would need to catch.
        $sc = Join-Path $script:Work 'sidecar-accounting.md'
        Set-Content -Path $sc -Value @(
            '# drain proposal',
            '## Promoted', '- promoted thing',
            '## GROWTH accounting',
            '- old rule about banners | dropped: refuted by a later measurement',
            '- old rule about seats | merged-into: the round-shaping rule',
            '## Dropped', '- some noise'
        )
        $r = Get-SidecarRecoverySections $sc
        $r | Should -Match 'old rule about banners'
        $r | Should -Match 'refuted by a later measurement'
        $r | Should -Match 'old rule about seats'
        $r | Should -Match 'some noise'                                # Dropped still retained alongside it
        $r | Should -Not -Match 'promoted thing'                       # Promoted still excluded
    }

    It "Restore-StagingToPending keeps chronological order: staged BEFORE mid-run captures (SC2)" {
        Set-Content -Path $script:Inbox -Value @('# inbox', '', '## Pending', '- [heuristic] MIDRUN  ·  x')
        $staging = Join-Path $script:Work 'agy-observations.staging.RID.md'
        Set-Content -Path $staging -Value @('- [heuristic] OLDER  ·  x')
        Restore-StagingToPending -InboxPath $script:Inbox -StagingPath $staging
        $body = (Get-Content $script:Inbox) -join "`n"
        ($body.IndexOf('OLDER')) | Should -BeLessThan ($body.IndexOf('MIDRUN'))
    }

    It "Get-DrainOutputPaths is EXACTLY the EXTEND set: the growth proposal + docs, and NO seed/manuals" {
        # PINNED AS AN EXACT SET, not by membership. This list is a DESTRUCTIVE trust boundary -
        # abort-drain treats every entry as safe to `git clean -fd`. The previous version asserted five
        # Should -Contain and three Should -Not -Contain with no count at all, so APPENDING a path was
        # completely invisible: MEASURED at f29cd42, adding 'docs/agy-scratch.md' passed all eight
        # assertions. A new path silently entering a recursive-delete set is the failure this pins.
        #
        # 🔴 AND AN IDENTITY PIN FREEZES WHATEVER IS THERE, INCLUDING A DEFECT. This list held
        # 'docs/fix-the-tool-backlog' - umbrella-rooted, matching ZERO tracked files, while the backlog
        # lives under agy-autotrain/ - and this test asserted that wrong value happily for as long as it
        # stood. A pin makes a CHANGE visible; it does not make the CONTENTS correct. The census test
        # above is its complement and asserts every directory entry actually RESOLVES. Corrected
        # 2026-08-25; that correction reddened this test, which is exactly its job.
        $expected = @(
            'docs/agy-golden-header.growth.md'
            'docs/agy-drain-log.md'
            'docs/agy-verify-needed.md'
            'docs/agy-drain-proposal.md'
            'agy-autotrain/docs/fix-the-tool-backlog'
        )
        (@(Get-DrainOutputPaths) -join "`n") | Should -BeExactly ($expected -join "`n") -Because 'the destructive-clean set must be pinned by identity and order, not by membership - an appended path is otherwise invisible'
    }

    It "every DIRECTORY entry in Get-DrainOutputPaths names a real directory in this repo" {
        # The protected-paths test beside this one asserts its six files are all REAL. The OUTPUT list had
        # no such assertion, and one of its entries pointed at nothing: `docs/fix-the-tool-backlog` is
        # umbrella-rooted, while the backlog actually lives at `agy-autotrain/docs/fix-the-tool-backlog/`
        # (17 tracked files). The umbrella spelling matched ZERO.
        #
        # That list is the single source of truth for the abort machinery, so a path that resolves to
        # nothing broke it two ways, both MEASURED: a real backlog file prefix-matched no owned entry, so
        # abort-drain treated it as an UNOWNED STRAY and refused to abort; and the scoped
        # `git clean -nd -- <entry>` cleaned nothing, leaving a file that blocks the next drain's
        # pristine-tree check. `check-user-facing-docs.ps1:31` had the correct root the whole time - the
        # repo disagreed with itself, which is exactly what a census test exists to catch.
        #
        # Only entries with NO file extension are checked: the others are transient drain outputs that
        # legitimately do not exist between runs (the proposal and growth files are written during a drain).
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $dirEntries = @(Get-DrainOutputPaths | Where-Object { -not [IO.Path]::GetExtension($_) })

        $dirEntries.Count | Should -BeGreaterThan 0 -Because 'if no entry is directory-shaped this test is asserting nothing at all'

        $missing = @($dirEntries | Where-Object { -not (Test-Path -LiteralPath (Join-Path $repoRoot $_) -PathType Container) })
        ($missing -join ', ') | Should -BeExactly '' -Because 'a directory entry that resolves to nothing silently disables both halves of the abort machinery for everything under it - name the path that is wrong, not a count'
    }

    It "Get-DrainProtectedPaths is EXACTLY the 6 driver-owned files, all real, and DISJOINT from the output set" {
        # PINNED AS AN EXACT SET. The previous version asserted .Count -eq 6 and named only TWO of the
        # six, so a typo in any of the other four survived every assertion: MEASURED at f29cd42,
        # renaming 'agy-assumptions.md' to 'agy-assumption.md' kept the count at 6, kept both named
        # entries present, and kept disjointness intact. That manual then silently loses protection -
        # check-core-integrity SKIPS paths absent from HEAD, so it passes VACUOUSLY on the typo, and
        # drain-knowledge's targeted revert never restores it after a rogue curator edit.
        $expected = @(
            'seed/golden-header.md'
            'clavity-dotnet/plugin/knowledge/agy-assumptions.md'
            'clavity-dotnet/plugin/knowledge/agy-capabilities.md'
            'clavity-classic/plugin/knowledge/agy-assumptions.md'
            'clavity-classic/plugin/knowledge/agy-capabilities.md'
            'agy-autotrain/knowledge/driver-cheatsheet.core.md'
        )
        $protected = @(Get-DrainProtectedPaths)
        ($protected -join "`n") | Should -BeExactly ($expected -join "`n") -Because 'the protected list must be pinned by identity and order - a typo in an unnamed entry is otherwise silent'

        # A path that does not EXIST cannot be protected, and check-core-integrity would skip it in
        # silence. This is what turns a typo from a passing test into a red one.
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        foreach ($p in $protected) {
            (Test-Path -LiteralPath (Join-Path $repoRoot $p)) | Should -BeTrue -Because "protected path '$p' must exist in the repo, or the integrity gate skips it vacuously"
        }

        $outputs = @(Get-DrainOutputPaths)
        foreach ($p in $protected) { $outputs | Should -Not -Contain $p }   # protected files are never drain outputs
    }

    It "Get-GrowthProposalBytes counts RAW on-disk bytes of the growth proposal, 0 when absent" {
        $repo = Join-Path $script:Work 'repo'
        New-Item -ItemType Directory -Path (Join-Path $repo 'docs') | Out-Null
        (Get-GrowthProposalBytes $repo) | Should -Be 0                     # absent
        Set-Content -NoNewline -Path (Join-Path $repo 'docs/agy-golden-header.growth.md') -Value ([string]([char]0x20AC) * 10) -Encoding utf8
        (Get-GrowthProposalBytes $repo) | Should -Be 30                    # 10 x EUR = 30 UTF-8 bytes
    }

    It "Resolve-CurateCommitExe returns null when no clavity binary is on PATH and no override is set" {
        # Isolate PATH so a dev machine's real clavity-ls does not leak in.
        $savedPath = $env:PATH; $savedOverride = $env:CLAVITY_CURATE_COMMIT_EXE
        try {
            $env:PATH = $script:Work            # a dir with no clavity binary
            $env:CLAVITY_CURATE_COMMIT_EXE = $null
            (Resolve-CurateCommitExe) | Should -BeNullOrEmpty
        } finally { $env:PATH = $savedPath; $env:CLAVITY_CURATE_COMMIT_EXE = $savedOverride }
    }

    It "Resolve-CurateCommitExe honors the CLAVITY_CURATE_COMMIT_EXE override" {
        $saved = $env:CLAVITY_CURATE_COMMIT_EXE
        try {
            $env:CLAVITY_CURATE_COMMIT_EXE = 'C:\some\clavity-ls.exe'
            (Resolve-CurateCommitExe) | Should -Be 'C:\some\clavity-ls.exe'
        } finally { $env:CLAVITY_CURATE_COMMIT_EXE = $saved }
    }

    It "Invoke-CurateCommit feeds the growth file to the exe as RAW UTF-8 bytes on stdin (no console-codepage mangling)" {
        # A pwsh stub that reads stdin as raw UTF-8 bytes and echoes them to a sentinel, proving the em-dash survives.
        $growth = Join-Path $script:Work 'growth.md'
        [System.IO.File]::WriteAllText($growth, "line with an em-dash `u{2014} and euro `u{20AC}")
        $sentinel = Join-Path $script:Work 'received.txt'
        $stub = Join-Path $script:Work 'stub.ps1'
        Set-Content -Path $stub -Value @'
$bytes = [System.IO.MemoryStream]::new()
[Console]::OpenStandardInput().CopyTo($bytes)
[System.IO.File]::WriteAllBytes($args[0], $bytes.ToArray())
exit 0
'@
        $code = Invoke-CurateCommit -Exe 'pwsh' -GrowthPath $growth `
            -ArgList @('-NoProfile','-File',$stub,$sentinel)
        $code | Should -Be 0
        [System.IO.File]::ReadAllText($sentinel) | Should -Be ([System.IO.File]::ReadAllText($growth))
    }

    It "Invoke-CurateCommit returns a non-zero code (not a crash) when the exe cannot be launched (capstone F1)" {
        # Process.Start throws Win32Exception when the resolved exe cannot launch (missing/AV-blocked/exec-policy).
        # The function must map that to a non-zero return so accept-drain's caller routes it to the 'failed' arm
        # (staging retained, graceful message) instead of crashing mid-transaction under $ErrorActionPreference='Stop'.
        $growth = Join-Path $script:Work 'g.md'
        [System.IO.File]::WriteAllText($growth, 'x')
        $code = Invoke-CurateCommit -Exe (Join-Path $script:Work 'does-not-exist.exe') -GrowthPath $growth
        $code | Should -BeGreaterThan 0
    }

    It "Invoke-CurateCommit returns 2 (over-cap) WITHOUT loading an absurdly large file into RAM (capstone R3-2)" {
        # A file far past the 32 KiB cap (here ~1.1 MiB) must be rejected by size BEFORE ReadAllBytes, so a multi-GB
        # hallucinated proposal can never OOM the accept process. Returns curate-commit's over-cap code (2); the exe
        # is never launched (a bogus exe path proves Start was not reached).
        $big = Join-Path $script:Work 'big.md'
        [System.IO.File]::WriteAllBytes($big, [byte[]]::new(1150000))

        # THE READ IS WHAT THIS PINS, and `Should -Be 2` alone cannot see it. MEASURED at f29cd42:
        # moving ReadAllBytes ABOVE the size guard still returns 2, because the bogus exe path only
        # distinguishes whether Process.Start was reached - so the name's "WITHOUT loading into RAM"
        # claim was strictly stronger than the assertion under it.
        # Holding the file open with an EXCLUSIVE share makes the two orders observable: MEASURED,
        # Get-Item .Length still succeeds on a locked file (so the size guard is unaffected) while
        # ReadAllBytes throws. If the read ever moves before the guard, this throws instead of
        # returning 2, and the test reds for exactly the right reason.
        $lock = [System.IO.File]::Open($big, 'Open', 'Read', 'None')
        try {
            { [System.IO.File]::ReadAllBytes($big) } | Should -Throw -Because 'precondition: the lock must actually block a read, or this test cannot tell the two orders apart'
            $code = Invoke-CurateCommit -Exe (Join-Path $script:Work 'nope.exe') -GrowthPath $big
            $code | Should -Be 2
        } finally { $lock.Dispose() }
    }

    It "Resolve-CurateCommitExe DISCOVERS a binary on PATH and prefers the dotnet CLI over classic" {
        # The function's PRIMARY job had no oracle. The two existing tests cover only the null case and
        # the override, and both bypass the discovery loop entirely: MEASURED at f29cd42, deleting the
        # whole `foreach ($name in @('clavity-ls','clavity'))` block left both green. accept-drain then
        # gets $null, warns "no driver installed" and PROCEEDS - so a reviewed GROWTH proposal silently
        # never reaches the runtime header, on every box, with the suite green.
        # .cmd stubs are enough: Get-Command -CommandType Application resolves them via PATHEXT.
        $binDir = Join-Path $script:Work 'bin'
        New-Item -ItemType Directory -Path $binDir | Out-Null
        Set-Content -LiteralPath (Join-Path $binDir 'clavity-ls.cmd') -Value '@echo dotnet' -Encoding ascii
        Set-Content -LiteralPath (Join-Path $binDir 'clavity.cmd')    -Value '@echo classic' -Encoding ascii

        # Unquoted saves on purpose: "$env:X" coerces an ABSENT variable to '', and restoring that
        # re-creates it as present-but-empty. See BashHookHelpers.ps1 for the CI failure that caused.
        $savedPath = $env:PATH
        $savedOverride = $env:CLAVITY_CURATE_COMMIT_EXE
        try {
            $env:CLAVITY_CURATE_COMMIT_EXE = $null
            $env:PATH = $binDir
            (Resolve-CurateCommitExe) | Should -BeLike '*clavity-ls.cmd' -Because 'with BOTH on PATH the dotnet CLI must win - the documented preference order'

            # Now only classic is reachable, so discovery must fall through to it rather than return null.
            Remove-Item -LiteralPath (Join-Path $binDir 'clavity-ls.cmd') -Force
            (Resolve-CurateCommitExe) | Should -BeLike '*clavity.cmd' -Because 'with only classic present the loop must still discover it'
        } finally { $env:PATH = $savedPath; $env:CLAVITY_CURATE_COMMIT_EXE = $savedOverride }
    }

    It "stages and restores a MIGRATED inbox (two ## Pending headings) without losing the appended section" {
        # The 14g installer migration APPENDS the whole old document - its own header line and its own
        # `## Pending` heading included - onto the canonical inbox, so a real inbox can carry two
        # headings. The existing two-heading test calls Set-PendingBody directly; nothing drives that
        # shape through the stage/restore round-trip the curator actually uses.
        # MEASURED at f29cd42: changing Get-PendingBody's terminator from '^##\s' to '^#' - a natural
        # "stop swallowing the stray header the migration appended" edit - took the staged body from 3
        # bullets to 1, silently dropping the ENTIRE migrated backlog, with the suite 23/0 green.
        Set-Content -Path $script:Inbox -Value @(
            '# inbox', '', '## Pending', '- [a] one',
            '# inbox', '', '## Pending', '- [b] two', '- [c] three'
        )
        # PRECONDITION: the reader merges both sections. If this is not 3 the fixture is not exercising
        # the migrated shape at all and everything below would pass for the wrong reason.
        (Get-PendingBulletCount -InboxPath $script:Inbox) | Should -Be 3 -Because 'the fixture must present all three bullets, across both headings'

        $staging = Join-Path $script:Work 'agy-observations.staging.RUNID.md'
        Move-PendingToStaging -InboxPath $script:Inbox -StagingPath $staging
        $staged = Get-Content $staging
        foreach ($b in @('- [a] one', '- [b] two', '- [c] three')) {
            (@($staged | Where-Object { $_ -eq $b })).Count | Should -Be 1 -Because "staging must carry '$b' exactly once - the appended section is real backlog, not scenery"
        }

        Restore-StagingToPending -InboxPath $script:Inbox -StagingPath $staging
        (Get-PendingBulletCount -InboxPath $script:Inbox) | Should -Be 3 -Because 'a stage/restore round-trip must be lossless on a migrated inbox'
        $after = Get-Content $script:Inbox
        foreach ($b in @('- [a] one', '- [b] two', '- [c] three')) {
            (@($after | Where-Object { $_ -eq $b })).Count | Should -Be 1 -Because "'$b' must survive the round-trip exactly once - neither dropped nor duplicated"
        }
    }
}

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

    It "Restore-StagingToPending keeps chronological order: staged BEFORE mid-run captures (SC2)" {
        Set-Content -Path $script:Inbox -Value @('# inbox', '', '## Pending', '- [heuristic] MIDRUN  ·  x')
        $staging = Join-Path $script:Work 'agy-observations.staging.RID.md'
        Set-Content -Path $staging -Value @('- [heuristic] OLDER  ·  x')
        Restore-StagingToPending -InboxPath $script:Inbox -StagingPath $staging
        $body = (Get-Content $script:Inbox) -join "`n"
        ($body.IndexOf('OLDER')) | Should -BeLessThan ($body.IndexOf('MIDRUN'))
    }

    It "Get-DrainOutputPaths is the EXTEND set: the growth proposal + docs, and NO seed/manuals" {
        $paths = @(Get-DrainOutputPaths)
        $paths | Should -Contain 'docs/agy-golden-header.growth.md'
        $paths | Should -Contain 'docs/agy-drain-log.md'
        $paths | Should -Contain 'docs/agy-verify-needed.md'
        $paths | Should -Contain 'docs/agy-drain-proposal.md'
        $paths | Should -Contain 'docs/fix-the-tool-backlog'
        # Protected driver-owned files are NEVER drain outputs under EXTEND.
        $paths | Should -Not -Contain 'seed/golden-header.md'
        $paths | Should -Not -Contain 'clavity-dotnet/plugin/knowledge/agy-assumptions.md'
        $paths | Should -Not -Contain 'clavity-classic/plugin/knowledge/agy-capabilities.md'
    }

    It "Get-DrainProtectedPaths names the 6 driver-owned files and is DISJOINT from the output set" {
        $protected = @(Get-DrainProtectedPaths)
        $protected.Count | Should -Be 6
        $protected | Should -Contain 'seed/golden-header.md'
        $protected | Should -Contain 'agy-autotrain/knowledge/driver-cheatsheet.core.md'
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
        # A file far past the 16 KiB cap (here ~1.1 MiB) must be rejected by size BEFORE ReadAllBytes, so a multi-GB
        # hallucinated proposal can never OOM the accept process. Returns curate-commit's over-cap code (2); the exe
        # is never launched (a bogus exe path proves Start was not reached).
        $big = Join-Path $script:Work 'big.md'
        [System.IO.File]::WriteAllBytes($big, [byte[]]::new(1150000))
        $code = Invoke-CurateCommit -Exe (Join-Path $script:Work 'nope.exe') -GrowthPath $big
        $code | Should -Be 2
    }
}

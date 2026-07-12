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

    It "moves the Pending body to a staging file and empties the live Pending section" {
        Set-Content -Path $script:Inbox -Value @('# inbox', '', '## Pending', '- [heuristic] r1  ·  x', '- [heuristic] r2  ·  x')
        $staging = Join-Path $script:Work 'agy-observations.staging.RUNID.md'
        Move-PendingToStaging -InboxPath $script:Inbox -StagingPath $staging
        (Get-PendingBulletCount -InboxPath $script:Inbox) | Should -Be 0
        (Get-Content $staging | Where-Object { $_ -match '^- \[' }).Count | Should -Be 2
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
}

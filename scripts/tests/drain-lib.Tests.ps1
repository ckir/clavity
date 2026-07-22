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
}

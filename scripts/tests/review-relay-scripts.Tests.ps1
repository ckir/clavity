# End-to-end tests: each script runs in a CHILD pwsh so its `exit` codes are observed exactly as a user sees them.
BeforeAll {
    $script:Root = Join-Path $PSScriptRoot '..' '..' 'review-relay' 'scripts'
    $script:NewRound = Join-Path $script:Root 'new-round.ps1'
    $script:Collect = Join-Path $script:Root 'collect.ps1'
    $script:Fx = Join-Path $PSScriptRoot 'fixtures' 'review-relay'
    function Invoke-Relay([string]$Script, [string[]]$Arguments) {
        $out = & pwsh -NoProfile -File $Script @Arguments 2>&1
        [pscustomobject]@{ Exit = $LASTEXITCODE; Out = ($out | ForEach-Object { "$_" }) -join "`n" }
    }
    function New-Project {
        $p = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $p | Out-Null
        Set-Content -LiteralPath (Join-Path $p 'design.md') -Value "# Design`n`nSome text.`n    the last line.`n" -NoNewline
        $p
    }
    $script:Clip = Join-Path $TestDrive 'clipboard.txt'
    $env:REVIEW_RELAY_CLIPBOARD_FILE = $script:Clip
}
AfterAll { Remove-Item Env:REVIEW_RELAY_CLIPBOARD_FILE -ErrorAction SilentlyContinue }

Describe 'new-round.ps1' {
    It 'creates round 1 with both variants, the marker, and round.json' {
        $p = New-Project
        $r = Invoke-Relay $script:NewRound @('-Review', 'demo', '-Artifact', 'design.md', '-ProjectRoot', $p)
        $r.Exit | Should -Be 0 -Because $r.Out
        $round = Join-Path $p '.review-relay' 'demo' 'round-01'
        $meta = Get-Content -Raw (Join-Path $round 'round.json') | ConvertFrom-Json
        $meta.endMarker | Should -MatchExactly '^[0-9A-F]{4}-[0-9A-F]{4}$'
        $meta.expectedLastLine | Should -BeExactly '    the last line.'
        $upload = Get-Content -Raw (Join-Path $round 'upload' 'design.md')
        ($upload.TrimEnd("`n") -split "`n")[-1] | Should -BeExactly "END OF DOCUMENT - review-relay $($meta.endMarker)"
        (Get-Content -Raw (Join-Path $p 'design.md')) | Should -Not -Match 'END OF DOCUMENT'
        (Get-Content -Raw (Join-Path $p '.review-relay' 'demo' 'artifact.md')) | Should -Not -Match 'END OF DOCUMENT'
    }
    It 'never states the marker code in the instructions, and the all-in-one text is on the clipboard' {
        $p = New-Project
        (Invoke-Relay $script:NewRound @('-Review', 'demo', '-Artifact', 'design.md', '-ProjectRoot', $p)).Exit | Should -Be 0
        $round = Join-Path $p '.review-relay' 'demo' 'round-01'
        $code = (Get-Content -Raw (Join-Path $round 'round.json') | ConvertFrom-Json).endMarker
        (Get-Content -Raw (Join-Path $round 'prompt-upload.md')) | Should -Not -Match ([regex]::Escape($code))
        $inline = Get-Content -Raw (Join-Path $round 'prompt-inline.md')
        ([regex]::Matches($inline, [regex]::Escape($code))).Count | Should -Be 1
        Get-Content -Raw $script:Clip | Should -BeExactly $inline
    }
    It 'refuses a new round until the previous one is collected, unless -Force' {
        $p = New-Project
        (Invoke-Relay $script:NewRound @('-Review', 'demo', '-Artifact', 'design.md', '-ProjectRoot', $p)).Exit | Should -Be 0
        (Invoke-Relay $script:NewRound @('-Review', 'demo', '-ProjectRoot', $p)).Exit | Should -Be 1
        (Invoke-Relay $script:NewRound @('-Review', 'demo', '-ProjectRoot', $p, '-Force')).Exit | Should -Be 0
        Test-Path (Join-Path $p '.review-relay' 'demo' 'round-02') | Should -BeTrue
    }
    It 'fills ALREADY ADDRESSED from the ledger and uses a new marker in round 2' {
        $p = New-Project
        (Invoke-Relay $script:NewRound @('-Review', 'demo', '-Artifact', 'design.md', '-ProjectRoot', $p)).Exit | Should -Be 0
        $ws = Join-Path $p '.review-relay' 'demo'
        Set-Content (Join-Path $ws 'round-01' 'collected.md') 'collected'
        Set-Content (Join-Path $ws 'ledger.md') "# Ledger`n``````already-addressed`nR1-1 lease taken twice`n```````n"
        (Invoke-Relay $script:NewRound @('-Review', 'demo', '-ProjectRoot', $p)).Exit | Should -Be 0
        (Get-Content -Raw (Join-Path $ws 'round-02' 'prompt-upload.md')) | Should -Match 'R1-1 lease taken twice'
        $c1 = (Get-Content -Raw (Join-Path $ws 'round-01' 'round.json') | ConvertFrom-Json).endMarker
        $c2 = (Get-Content -Raw (Join-Path $ws 'round-02' 'round.json') | ConvertFrom-Json).endMarker
        $c1 | Should -Not -Be $c2
    }
    It 'reviews a git diff, passing the range as an argument (not through a shell)' {
        $p = New-Project
        git -C $p init -q; git -C $p -c user.email=t@t -c user.name=t add design.md; git -C $p -c user.email=t@t -c user.name=t commit -q -m one
        Add-Content -LiteralPath (Join-Path $p 'design.md') 'added line'
        git -C $p -c user.email=t@t -c user.name=t commit -q -am two
        $r = Invoke-Relay $script:NewRound @('-Review', 'code-demo', '-Diff', 'HEAD~1..HEAD', '-ProjectRoot', $p)
        $r.Exit | Should -Be 0 -Because $r.Out
        $meta = Get-Content -Raw (Join-Path $p '.review-relay' 'code-demo' 'review.json') | ConvertFrom-Json
        "$($meta.kind)/$($meta.sourceType)" | Should -BeExactly 'code/diff'
        Get-Content -Raw (Join-Path $p '.review-relay' 'code-demo' 'round-01' 'upload' 'code-demo.diff') | Should -Match '\+added line'
    }
    It 'uses and records a project template override, and fails on an unknown placeholder' {
        $p = New-Project
        $tdir = Join-Path $p '.review-relay' 'templates'
        New-Item -ItemType Directory -Force $tdir | Out-Null
        Set-Content (Join-Path $tdir 'spec-review.md') 'Custom {{ARTIFACT_NAME}} {{ROUND}} {{ARTIFACT_REFERENCE}} {{ALREADY_ADDRESSED}} {{ARTIFACT_INLINE}}'
        (Invoke-Relay $script:NewRound @('-Review', 'demo', '-Artifact', 'design.md', '-ProjectRoot', $p)).Exit | Should -Be 0
        (Get-Content -Raw (Join-Path $p '.review-relay' 'demo' 'review.json') | ConvertFrom-Json).template | Should -Match 'templates[\\/]spec-review\.md$'
        Set-Content (Join-Path $tdir 'spec-review.md') 'Broken {{NOT_A_PLACEHOLDER}}'
        (Invoke-Relay $script:NewRound @('-Review', 'other', '-Artifact', 'design.md', '-ProjectRoot', $p)).Exit | Should -Be 1
    }
    It 'writes nothing with -WhatIf' {
        $p = New-Project
        (Invoke-Relay $script:NewRound @('-Review', 'demo', '-Artifact', 'design.md', '-ProjectRoot', $p, '-WhatIf')).Exit | Should -Be 0
        Test-Path (Join-Path $p '.review-relay') | Should -BeFalse
    }
    It 'refuses a missing artifact' {
        $p = New-Project
        (Invoke-Relay $script:NewRound @('-Review', 'demo', '-Artifact', 'nope.md', '-ProjectRoot', $p)).Exit | Should -Be 1
    }
    It 'rederives kind when a later round switches source, and -Kind still wins' {
        $p = New-Project
        git -C $p init -q; git -C $p -c user.email=t@t -c user.name=t add design.md; git -C $p -c user.email=t@t -c user.name=t commit -q -m one
        Add-Content -LiteralPath (Join-Path $p 'design.md') 'added line'
        git -C $p -c user.email=t@t -c user.name=t commit -q -am two
        (Invoke-Relay $script:NewRound @('-Review', 'demo', '-Artifact', 'design.md', '-ProjectRoot', $p)).Exit | Should -Be 0
        $ws = Join-Path $p '.review-relay' 'demo'
        (Get-Content -Raw (Join-Path $ws 'review.json') | ConvertFrom-Json).kind | Should -BeExactly 'spec'

        $r2 = Invoke-Relay $script:NewRound @('-Review', 'demo', '-Force', '-Diff', 'HEAD~1..HEAD', '-ProjectRoot', $p)
        $r2.Exit | Should -Be 0 -Because $r2.Out
        $meta2 = Get-Content -Raw (Join-Path $ws 'review.json') | ConvertFrom-Json
        $meta2.kind | Should -BeExactly 'code'
        $meta2.template | Should -Match 'code-review\.md$'

        $r3 = Invoke-Relay $script:NewRound @('-Review', 'demo', '-Force', '-Diff', 'HEAD~1..HEAD', '-Kind', 'spec', '-ProjectRoot', $p)
        $r3.Exit | Should -Be 0 -Because $r3.Out
        (Get-Content -Raw (Join-Path $ws 'review.json') | ConvertFrom-Json).kind | Should -BeExactly 'spec'
    }
    It 'refuses a garbled review.json with a clear message' {
        $p = New-Project
        (Invoke-Relay $script:NewRound @('-Review', 'demo', '-Artifact', 'design.md', '-ProjectRoot', $p)).Exit | Should -Be 0
        Set-Content -LiteralPath (Join-Path $p '.review-relay' 'demo' 'review.json') -Value '{ not json' -NoNewline
        $r = Invoke-Relay $script:NewRound @('-Review', 'demo', '-ProjectRoot', $p)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'new-round: review\.json is not valid JSON'
    }
    It 'writes review.json and round.json with LF line endings' {
        $p = New-Project
        $r = Invoke-Relay $script:NewRound @('-Review', 'demo', '-Artifact', 'design.md', '-ProjectRoot', $p)
        $r.Exit | Should -Be 0 -Because $r.Out
        $round = Join-Path $p '.review-relay' 'demo' 'round-01'
        foreach ($f in @((Join-Path $round 'round.json'), (Join-Path $p '.review-relay' 'demo' 'review.json'))) {
            $bytes = [IO.File]::ReadAllBytes($f)
            $bytes | Should -Not -Contain 13
            { Get-Content -Raw $f | ConvertFrom-Json } | Should -Not -Throw
        }
    }
    It 'numbers a new round after the highest existing one and never rewrites an existing round' {
        $p = New-Project
        (Invoke-Relay $script:NewRound @('-Review', 'demo', '-Artifact', 'design.md', '-ProjectRoot', $p)).Exit | Should -Be 0
        $ws = Join-Path $p '.review-relay' 'demo'
        Set-Content (Join-Path $ws 'round-01' 'collected.md') 'collected'
        (Invoke-Relay $script:NewRound @('-Review', 'demo', '-ProjectRoot', $p, '-Force')).Exit | Should -Be 0
        $round2Marker = (Get-Content -Raw (Join-Path $ws 'round-02' 'round.json') | ConvertFrom-Json).endMarker

        Remove-Item -LiteralPath (Join-Path $ws 'round-01') -Recurse -Force

        $r = Invoke-Relay $script:NewRound @('-Review', 'demo', '-ProjectRoot', $p, '-Force')
        $r.Exit | Should -Be 0 -Because $r.Out
        Test-Path (Join-Path $ws 'round-03') | Should -BeTrue
        (Get-Content -Raw (Join-Path $ws 'round-02' 'round.json') | ConvertFrom-Json).endMarker | Should -BeExactly $round2Marker
    }
    It 'writes the review-relay tag as the first line of both prompt files, and the artifact name appears once in the upload prompt (T, S2, S-a)' {
        $p = New-Project
        $r = Invoke-Relay $script:NewRound @('-Review', 'demo', '-Artifact', 'design.md', '-ProjectRoot', $p)
        $r.Exit | Should -Be 0 -Because $r.Out
        $round = Join-Path $p '.review-relay' 'demo' 'round-01'
        (Get-Content (Join-Path $round 'prompt-upload.md'))[0] | Should -BeExactly 'review-relay tag: demo/round-01 (bookkeeping only - ignore this line)'
        (Get-Content (Join-Path $round 'prompt-inline.md'))[0] | Should -BeExactly 'review-relay tag: demo/round-01 (bookkeeping only - ignore this line)'
        $uploadInstruction = (Get-Content (Join-Path $round 'prompt-upload.md'))[1]
        @([regex]::Matches($uploadInstruction, [regex]::Escape('design.md'))).Count | Should -Be 1
    }
    It 'refuses a stored diff range that starts with a dash and writes no file (F1, git option injection)' {
        $p = New-Project
        git -C $p init -q; git -C $p -c user.email=t@t -c user.name=t add design.md; git -C $p -c user.email=t@t -c user.name=t commit -q -m one
        $ws = Join-Path $p '.review-relay' 'evil'
        New-Item -ItemType Directory -Force -Path $ws | Out-Null
        $pwned = Join-Path $TestDrive 'PWNED.txt'
        $meta = [ordered]@{
            name       = 'evil'
            kind       = 'code'
            source     = "--output=$pwned"
            sourceType = 'diff'
            createdAt  = [DateTime]::UtcNow.ToString('o')
            template   = $null
        }
        Set-Content -LiteralPath (Join-Path $ws 'review.json') -Value ($meta | ConvertTo-Json) -NoNewline
        $r = Invoke-Relay $script:NewRound @('-Review', 'evil', '-ProjectRoot', $p)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match "cannot start with '-'"
        Test-Path -LiteralPath $pwned | Should -BeFalse
    }
    It 'refuses to reuse an existing round folder (F2, atomic reservation)' {
        $p = New-Project
        (Invoke-Relay $script:NewRound @('-Review', 'demo', '-Artifact', 'design.md', '-ProjectRoot', $p)).Exit | Should -Be 0
        $ws = Join-Path $p '.review-relay' 'demo'
        Set-Content (Join-Path $ws 'round-01' 'collected.md') 'collected'
        $fakeRound = Join-Path $ws 'round-02'
        Set-Content -LiteralPath $fakeRound -Value 'not a directory' -NoNewline
        $r = Invoke-Relay $script:NewRound @('-Review', 'demo', '-ProjectRoot', $p, '-Force')
        $r.Exit | Should -Be 1 -Because $r.Out
        $r.Out | Should -Match 'already exists'
        (Get-Item -LiteralPath $fakeRound) | Should -Not -BeOfType [System.IO.DirectoryInfo]
        Get-Content -LiteralPath $fakeRound -Raw | Should -BeExactly 'not a directory'
    }
    It 'removes a partial round when a write fails (F2+F4, cleanup on failure)' {
        $p = New-Project
        $badClip = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')) 'clip.txt'
        $env:REVIEW_RELAY_CLIPBOARD_FILE = $badClip
        try {
            $r = Invoke-Relay $script:NewRound @('-Review', 'demo', '-Artifact', 'design.md', '-ProjectRoot', $p)
            $r.Exit | Should -Be 1 -Because $r.Out
            $r.Out | Should -Match 'partial round folder was removed'
            Test-Path -LiteralPath (Join-Path $p '.review-relay' 'demo' 'round-01') | Should -BeFalse
        } finally {
            $env:REVIEW_RELAY_CLIPBOARD_FILE = $script:Clip
        }
    }
}

Describe 'collect.ps1' {
    BeforeEach {
        $script:P = New-Project
        (Invoke-Relay $script:NewRound @('-Review', 'demo', '-Artifact', 'design.md', '-ProjectRoot', $script:P)).Exit | Should -Be 0
        $script:RoundDir = Join-Path $script:P '.review-relay' 'demo' 'round-01'
        $script:Meta = Get-Content -Raw (Join-Path $script:RoundDir 'round.json') | ConvertFrom-Json
        $script:Inbox = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Inbox | Out-Null
        $started = if ($script:Meta.startedAt -is [datetime]) { $script:Meta.startedAt.ToUniversalTime() } else { [DateTime]::Parse($script:Meta.startedAt).ToUniversalTime() }
        $script:After = $started.AddSeconds(5)
        $script:Before = $started.AddHours(-1)
    }
    It 'exits 2 when no capture was saved after the round started' {
        Copy-Item (Join-Path $script:Fx 'gemini-inline.md') $script:Inbox
        (Get-Item (Join-Path $script:Inbox 'gemini-inline.md')).LastWriteTimeUtc = $script:Before
        (Invoke-Relay $script:Collect @('-Review', 'demo', '-ProjectRoot', $script:P, '-Inbox', $script:Inbox)).Exit | Should -Be 2
    }
    It 'collects captures, checks the read proof, and leaves the originals in place' {
        $reply = (Get-Content -Raw (Join-Path $script:Fx 'contract-reply.md')).Replace('@@CODE@@', $script:Meta.endMarker).Replace('@@LAST@@', 'the last line.')
        Set-Content -LiteralPath (Join-Path $script:Inbox 'contract.md') -Value $reply -NoNewline
        Copy-Item (Join-Path $script:Fx 'gemini-inline.md'), (Join-Path $script:Fx 'not-aisave.md') $script:Inbox
        Get-ChildItem $script:Inbox | ForEach-Object { $_.LastWriteTimeUtc = $script:After }
        $r = Invoke-Relay $script:Collect @('-Review', 'demo', '-ProjectRoot', $script:P, '-Inbox', $script:Inbox)
        $r.Exit | Should -Be 0 -Because $r.Out
        $collected = Get-Content -Raw (Join-Path $script:RoundDir 'collected.md')
        $collected | Should -Match '\| example \| PASS \| 412 \| NOT READY \| 1 \| 0 \| 1 \| 0 \|'
        $collected | Should -Match '\| gemini \| MISSING \| - \| 1 BLOCKING, 0 MATERIAL, 1 MINOR \| 1 \| 0 \| 1 \| 0 \|'
        $collected | Should -Not -Match 'Meeting notes'
        @(Get-ChildItem (Join-Path $script:RoundDir 'replies')).Count | Should -Be 2
        @(Get-ChildItem $script:Inbox).Count | Should -Be 3
    }
    It 'shows the UNKNOWN column in the collected.md header (#3, S-e)' {
        Copy-Item (Join-Path $script:Fx 'gemini-inline.md') $script:Inbox
        (Get-Item (Join-Path $script:Inbox 'gemini-inline.md')).LastWriteTimeUtc = $script:After
        $r = Invoke-Relay $script:Collect @('-Review', 'demo', '-ProjectRoot', $script:P, '-Inbox', $script:Inbox)
        $r.Exit | Should -Be 0 -Because $r.Out
        $collected = Get-Content -Raw (Join-Path $script:RoundDir 'collected.md')
        $collected | Should -Match ([regex]::Escape('| # | Site | Read proof | Reported lines | Verdict | BLOCKING | MATERIAL | MINOR | UNKNOWN |'))
        $collected | Should -Match ([regex]::Escape('|---|---|---|---|---|---|---|---|---|'))
    }
    It 'prefers -Inbox over REVIEW_RELAY_INBOX' {
        Copy-Item (Join-Path $script:Fx 'gemini-inline.md') $script:Inbox
        (Get-Item (Join-Path $script:Inbox 'gemini-inline.md')).LastWriteTimeUtc = $script:After
        $empty = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $empty | Out-Null
        $env:REVIEW_RELAY_INBOX = $empty
        try {
            (Invoke-Relay $script:Collect @('-Review', 'demo', '-ProjectRoot', $script:P)).Exit | Should -Be 2
            (Invoke-Relay $script:Collect @('-Review', 'demo', '-ProjectRoot', $script:P, '-Inbox', $script:Inbox)).Exit | Should -Be 0
        } finally { Remove-Item Env:REVIEW_RELAY_INBOX }
    }
    It 'refuses an unknown review' {
        (Invoke-Relay $script:Collect @('-Review', 'nope', '-ProjectRoot', $script:P, '-Inbox', $script:Inbox)).Exit | Should -Be 1
    }
    It 'refuses when a capture in the round window cannot be read, and writes nothing (#2, S-d)' {
        $reply = (Get-Content -Raw (Join-Path $script:Fx 'contract-reply.md')).Replace('@@CODE@@', $script:Meta.endMarker).Replace('@@LAST@@', 'the last line.')
        Set-Content -LiteralPath (Join-Path $script:Inbox 'contract.md') -Value $reply -NoNewline
        Copy-Item (Join-Path $script:Fx 'gemini-inline.md') $script:Inbox
        Get-ChildItem $script:Inbox | ForEach-Object { $_.LastWriteTimeUtc = $script:After }
        $lockedPath = Join-Path $script:Inbox 'gemini-inline.md'
        $stream = [IO.File]::Open($lockedPath, 'Open', 'Read', 'None')
        try {
            $r = Invoke-Relay $script:Collect @('-Review', 'demo', '-ProjectRoot', $script:P, '-Inbox', $script:Inbox)
            $r.Exit | Should -Be 1
            $r.Out | Should -Match 'gemini-inline\.md'
            Test-Path (Join-Path $script:RoundDir 'collected.md') | Should -BeFalse
            @(Get-ChildItem (Join-Path $script:RoundDir 'replies') -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^\d{2}-' }).Count | Should -Be 0
        } finally {
            $stream.Dispose()
        }
    }
    It 'refuses a garbled round.json with a clear message' {
        Set-Content -LiteralPath (Join-Path $script:RoundDir 'round.json') -Value '{ not json' -NoNewline
        $r = Invoke-Relay $script:Collect @('-Review', 'demo', '-ProjectRoot', $script:P, '-Inbox', $script:Inbox)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'collect: round\.json is not valid JSON'
    }
    It 'says plainly when a capture has no reply (F3)' {
        $text = @"
---
title: "no reply yet"
date: 2026-09-28
url: https://example.invalid/no-reply
platform: example
---

## Human

Please review this.
"@
        Set-Content -LiteralPath (Join-Path $script:Inbox 'no-reply.md') -Value $text -NoNewline
        (Get-Item (Join-Path $script:Inbox 'no-reply.md')).LastWriteTimeUtc = $script:After
        $r = Invoke-Relay $script:Collect @('-Review', 'demo', '-ProjectRoot', $script:P, '-Inbox', $script:Inbox)
        $r.Exit | Should -Be 0 -Because $r.Out
        $collected = Get-Content -Raw (Join-Path $script:RoundDir 'collected.md')
        $collected | Should -Match 'This capture has no reply'
    }
    It 'a re-run leaves exactly one numbered copy per capture' {
        Copy-Item (Join-Path $script:Fx 'gemini-inline.md') $script:Inbox
        (Get-Item (Join-Path $script:Inbox 'gemini-inline.md')).LastWriteTimeUtc = $script:After
        $r1 = Invoke-Relay $script:Collect @('-Review', 'demo', '-ProjectRoot', $script:P, '-Inbox', $script:Inbox)
        $r1.Exit | Should -Be 0 -Because $r1.Out
        @(Get-ChildItem (Join-Path $script:RoundDir 'replies')).Name | Should -BeExactly @('01-gemini-inline.md')

        $reply = (Get-Content -Raw (Join-Path $script:Fx 'contract-reply.md')).Replace('@@CODE@@', $script:Meta.endMarker).Replace('@@LAST@@', 'the last line.')
        Set-Content -LiteralPath (Join-Path $script:Inbox 'contract.md') -Value $reply -NoNewline
        $earlier = $script:After.AddSeconds(-2)
        (Get-Item (Join-Path $script:Inbox 'contract.md')).LastWriteTimeUtc = $earlier

        $r2 = Invoke-Relay $script:Collect @('-Review', 'demo', '-ProjectRoot', $script:P, '-Inbox', $script:Inbox)
        $r2.Exit | Should -Be 0 -Because $r2.Out
        $names = @(Get-ChildItem (Join-Path $script:RoundDir 'replies') | Sort-Object Name).Name
        $names | Should -BeExactly @('01-contract.md', '02-gemini-inline.md')
    }
    It 'collects only the captures saved during that round, not after the next round started' {
        Start-Sleep -Milliseconds 50
        Copy-Item (Join-Path $script:Fx 'gemini-inline.md') $script:Inbox
        (Get-Item (Join-Path $script:Inbox 'gemini-inline.md')).LastWriteTimeUtc = [DateTime]::UtcNow
        $r1 = Invoke-Relay $script:Collect @('-Review', 'demo', '-ProjectRoot', $script:P, '-Inbox', $script:Inbox)
        $r1.Exit | Should -Be 0 -Because $r1.Out

        Start-Sleep -Milliseconds 50
        $r2 = Invoke-Relay $script:NewRound @('-Review', 'demo', '-ProjectRoot', $script:P)
        $r2.Exit | Should -Be 0 -Because $r2.Out
        $round2Dir = Join-Path $script:P '.review-relay' 'demo' 'round-02'

        Start-Sleep -Milliseconds 50
        Copy-Item (Join-Path $script:Fx 'meta-inline.md') $script:Inbox
        (Get-Item (Join-Path $script:Inbox 'meta-inline.md')).LastWriteTimeUtc = [DateTime]::UtcNow

        $r3 = Invoke-Relay $script:Collect @('-Review', 'demo', '-Round', 1, '-ProjectRoot', $script:P, '-Inbox', $script:Inbox)
        $r3.Exit | Should -Be 0 -Because $r3.Out
        @(Get-ChildItem (Join-Path $script:RoundDir 'replies')).Name | Should -BeExactly @('01-gemini-inline.md')
        $collected1 = Get-Content -Raw (Join-Path $script:RoundDir 'collected.md')
        @([regex]::Matches($collected1, '(?m)^\|\s*\d+\s*\|')).Count | Should -Be 1

        $r4 = Invoke-Relay $script:Collect @('-Review', 'demo', '-ProjectRoot', $script:P, '-Inbox', $script:Inbox)
        $r4.Exit | Should -Be 0 -Because $r4.Out
        @(Get-ChildItem (Join-Path $round2Dir 'replies')).Name | Should -BeExactly @('01-meta-inline.md')
    }
}

Describe 'collect.ps1 round tagging (T)' {
    BeforeAll {
        function New-TaggedCapture([string]$Name, [string]$Review, [int]$Round) {
            $text = @"
---
title: "tagged"
date: 2026-09-28
url: https://example.invalid/tagged
platform: example
---

## Human

review-relay tag: $Review/round-{0:D2} (bookkeeping only - ignore this line)

## Assistant

Some reply text.
"@ -f $Round
            Set-Content -LiteralPath (Join-Path $script:Inbox $Name) -Value $text -NoNewline
        }
        function Get-RoundStartedAtUtc([string]$RoundDir) {
            $m = Get-Content -Raw (Join-Path $RoundDir 'round.json') | ConvertFrom-Json
            if ($m.startedAt -is [datetime]) { $m.startedAt.ToUniversalTime() } else { [DateTime]::Parse($m.startedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() }
        }
    }
    BeforeEach {
        $script:P = New-Project
        (Invoke-Relay $script:NewRound @('-Review', 'demo', '-Artifact', 'design.md', '-ProjectRoot', $script:P)).Exit | Should -Be 0
        $script:Ws = Join-Path $script:P '.review-relay' 'demo'
        $script:Round1Dir = Join-Path $script:Ws 'round-01'
        Set-Content (Join-Path $script:Round1Dir 'collected.md') 'collected'
        (Invoke-Relay $script:NewRound @('-Review', 'demo', '-ProjectRoot', $script:P)).Exit | Should -Be 0
        $script:Round2Dir = Join-Path $script:Ws 'round-02'
        Start-Sleep -Milliseconds 50
        $script:Inbox = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Inbox | Out-Null
    }
    It 'a capture tagged for round 1 but saved after round 2 started: -Round 1 includes it, a plain collect (round 2) excludes it (S-b)' {
        New-TaggedCapture -Name 'late-tag.md' -Review 'demo' -Round 1
        (Get-Item (Join-Path $script:Inbox 'late-tag.md')).LastWriteTimeUtc = [DateTime]::UtcNow
        $r1 = Invoke-Relay $script:Collect @('-Review', 'demo', '-Round', 1, '-ProjectRoot', $script:P, '-Inbox', $script:Inbox)
        $r1.Exit | Should -Be 0 -Because $r1.Out
        @(Get-ChildItem (Join-Path $script:Round1Dir 'replies')).Name | Should -BeExactly @('01-late-tag.md')

        $r2 = Invoke-Relay $script:Collect @('-Review', 'demo', '-ProjectRoot', $script:P, '-Inbox', $script:Inbox)
        $r2.Exit | Should -Be 2
    }
    It 'excludes a capture tagged for another review even when saved inside the round window (S-c)' {
        # Place the file strictly BETWEEN round 1's start and round 2's start, so the OLD
        # window-only filter would have included it - only the new tag check excludes it.
        $t1 = Get-RoundStartedAtUtc $script:Round1Dir
        $t2 = Get-RoundStartedAtUtc $script:Round2Dir
        $mid = $t1.AddTicks(($t2 - $t1).Ticks / 2)
        New-TaggedCapture -Name 'other-review.md' -Review 'other' -Round 1
        (Get-Item (Join-Path $script:Inbox 'other-review.md')).LastWriteTimeUtc = $mid
        $r = Invoke-Relay $script:Collect @('-Review', 'demo', '-Round', 1, '-ProjectRoot', $script:P, '-Inbox', $script:Inbox)
        $r.Exit | Should -Be 2
    }
}

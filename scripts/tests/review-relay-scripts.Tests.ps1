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
}

#Requires -Modules Pester

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:Script   = Join-Path $script:RepoRoot 'scripts/check-knowledge-store.ps1'

    # Every case runs against a THROWAWAY GIT REPO, not the real tree. The deletion check compares
    # against a git baseline, so it cannot be exercised at all without a repo whose history the test
    # controls - and a failure path that cannot be exercised is indistinguishable from a vacuous one.
    function New-StoreFixture {
        $d = Join-Path ([System.IO.Path]::GetTempPath()) ("clavity-store-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $d 'rules') -Force | Out-Null
        Set-Content -NoNewline -Path (Join-Path $d 'rules/alpha.md') -Value "# alpha`n`n- ALPHA RULE.`n"
        Set-Content -NoNewline -Path (Join-Path $d 'rules/beta.md')  -Value "# beta`n`n- BETA RULE.`n"
        Set-Content -NoNewline -Path (Join-Path $d 'rules/INDEX.md') -Value "# store`n`n- [alpha](alpha.md) - a`n- [beta](beta.md) - b`n"
        & git -C $d init --quiet 2>$null
        & git -C $d config user.email t@t.invalid 2>$null
        & git -C $d config user.name  test          2>$null
        & git -C $d add -A 2>$null
        & git -C $d commit -q -m baseline 2>$null
        $d
    }
    function Invoke-Check([string]$Repo) {
        & pwsh -NoProfile -File $script:Script -RepoRoot $Repo -StoreDir 'rules' 2>&1 | Out-String
    }
}

Describe 'check-knowledge-store' {

    It 'PASSES a clean store' {
        $d = New-StoreFixture
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match '2 rule\(s\)'
        Remove-Item -Recurse -Force $d
    }

    # THE ROUND-6 FATAL FINDING. Coordinated deletion - removing the rule AND its index pointer - defeats
    # every topological check: no dangling pointer for mlc, nothing to enumerate for an orphan sweep. Only
    # a git baseline sees it. This row is the whole reason the script consults git at all.
    It 'FAILS when a rule file is deleted, even with its index pointer removed too' {
        $d = New-StoreFixture
        Remove-Item (Join-Path $d 'rules/beta.md')
        Set-Content -NoNewline -Path (Join-Path $d 'rules/INDEX.md') -Value "# store`n`n- [alpha](alpha.md) - a`n"
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'DELETED: beta\.md'
    }

    It 'FAILS an orphan - a rule on disk that the index does not link' {
        $d = New-StoreFixture
        Set-Content -NoNewline -Path (Join-Path $d 'rules/gamma.md') -Value "# gamma`n`n- GAMMA.`n"
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'ORPHAN: gamma\.md'
    }

    # The code-span strip is not cosmetic: on a sibling corpus, bracketed tokens inside backticks
    # produced 2 of 11 false positives. Here the inverse is asserted - a link that exists ONLY inside a
    # code span must NOT count as reachability, or the strip is silently doing nothing.
    It 'does NOT count a link that appears only inside a code span' {
        $d = New-StoreFixture
        Set-Content -NoNewline -Path (Join-Path $d 'rules/gamma.md') -Value "# gamma`n`n- GAMMA.`n"
        Add-Content -Path (Join-Path $d 'rules/INDEX.md') -Value "`nExample of the link syntax: ``[gamma](gamma.md)``"
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'ORPHAN: gamma\.md'
    }

    It 'FAILS on a CRLF rule file' {
        $d = New-StoreFixture
        [System.IO.File]::WriteAllBytes((Join-Path $d 'rules/alpha.md'), [byte[]](0x2D,0x20,0x41,0x0D,0x0A))
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'CRLF: alpha\.md'
    }

    # Pure ASCII is inherited from the GROWTH region these rules were split out of: that region is
    # published through a byte transport which corrupted it once, with a sha256 sidecar that matched the
    # CORRUPT content and therefore certified it.
    It 'FAILS on a non-ASCII byte' {
        $d = New-StoreFixture
        [System.IO.File]::WriteAllBytes((Join-Path $d 'rules/alpha.md'), [byte[]](0x2D,0x20,0xE2,0x80,0x94,0x0A))
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'NON-ASCII: alpha\.md'
    }

    It 'FAILS when INDEX.md is missing - an unindexed store is a pile of files' {
        $d = New-StoreFixture
        Remove-Item (Join-Path $d 'rules/INDEX.md')
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'NO INDEX'
    }

    It 'SKIPS cleanly when there is no store directory at all' {
        $d = Join-Path ([System.IO.Path]::GetTempPath()) ("clavity-nostore-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'SKIP'
        Remove-Item -Recurse -Force $d
    }
}

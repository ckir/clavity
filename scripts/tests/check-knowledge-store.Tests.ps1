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

    # CAPSTONE R1 / F2 - THE ROW THE ORIGINAL SUITE WAS MISSING, and its absence is what let the gate ship
    # broken. The row above proves an UNCOMMITTED deletion fails. MEASURED 2026-08-28, committing that same
    # deletion made it PASS (exit 0, "none deleted since HEAD"), because the tree baseline moves with the
    # commit. Every real deletion arrives committed, so the guard was decoration on the only path that
    # matters. The baseline is now the ref's HISTORY, which cannot move.
    It 'FAILS a deletion that has already been COMMITTED - the baseline must not move with it' {
        $d = New-StoreFixture
        Remove-Item (Join-Path $d 'rules/beta.md')
        Set-Content -NoNewline -Path (Join-Path $d 'rules/INDEX.md') -Value "# store`n`n- [alpha](alpha.md) - a`n"
        & git -C $d add -A 2>$null; & git -C $d commit -q -m 'retire beta' 2>$null
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'DELETED: beta\.md'
        Remove-Item -Recurse -Force $d
    }

    # CAPSTONE R1 / F3 - content obliteration. Zero bytes satisfies filename, link and hygiene checks
    # simultaneously (an empty file has no CRLF and no high bytes), so before this row the gate reported
    # "OK - 2 rule(s), all reachable, LF + pure ASCII" over a destroyed rule - every clause true.
    It 'FAILS a rule emptied to 0 bytes' {
        $d = New-StoreFixture
        [System.IO.File]::WriteAllBytes((Join-Path $d 'rules/beta.md'), [byte[]]@())
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'OBLITERATED: beta\.md'
        Remove-Item -Recurse -Force $d
    }

    It 'FAILS a rule gutted to a fraction of its size with no declaration' {
        $d = New-StoreFixture
        Set-Content -NoNewline -Path (Join-Path $d 'rules/beta.md') -Value "x`n"
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'GUTTED: beta\.md'
        Remove-Item -Recurse -Force $d
    }

    # THE PAIRED CONTROL, and the one that makes the row above mean something. The SAME reduction passes
    # once it declares itself. Without this, the gutting check could be passing merely because the file got
    # smaller, and it would trip every legitimate consolidation - the failure mode the design spec named.
    It 'PASSES the same reduction when it DECLARES itself retired' {
        $d = New-StoreFixture
        Set-Content -NoNewline -Path (Join-Path $d 'rules/beta.md') -Value "# beta`n`n> Superseded by [alpha](alpha.md)`n"
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match '2 rule\(s\)'
        Remove-Item -Recurse -Force $d
    }

    # CAPSTONE R2 - the SAME moving-baseline defect as the deletion check, in its sibling, missed when that
    # one was fixed. MEASURED: committing the gutting made the previous size equal the current size, so the
    # ratio was 1.0 and the gate passed while printing "none gutted undeclared". The baseline is now the
    # file's HIGH-WATER MARK across history, which no commit can move.
    It 'FAILS a gutting that has already been COMMITTED' {
        $d = New-StoreFixture
        Set-Content -NoNewline -Path (Join-Path $d 'rules/beta.md') -Value "x`n"
        & git -C $d add -A 2>$null; & git -C $d commit -q -m 'gut beta' 2>$null
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'GUTTED: beta\.md'
        Remove-Item -Recurse -Force $d
    }

    It 'PASSES a COMMITTED reduction that declares itself retired' {
        $d = New-StoreFixture
        Set-Content -NoNewline -Path (Join-Path $d 'rules/beta.md') -Value "# beta`n`n> Retired: folded into alpha`n"
        & git -C $d add -A 2>$null; & git -C $d commit -q -m 'retire beta' 2>$null
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match '2 rule\(s\)'
        Remove-Item -Recurse -Force $d
    }

    # CAPSTONE R3 - the gate must REFUSE to certify what it cannot see. MEASURED on a real
    # `git clone --depth 1`: a committed deletion was invisible and the gate reported every rule still
    # present, which is a false statement rather than a merely unhelpful one. actions/checkout is shallow
    # BY DEFAULT, so the CI wiring added one commit earlier was certifying a store it could not inspect.
    # The workflow now deepens history, but a gate must not depend on its caller remembering that.
    It 'FAILS CLOSED on a shallow repository instead of certifying blind' {
        $d = New-StoreFixture
        # A second commit, so a shallow clone genuinely truncates something.
        Set-Content -NoNewline -Path (Join-Path $d 'rules/alpha.md') -Value "# alpha`n`n- ALPHA REVISED.`n"
        & git -C $d add -A 2>$null; & git -C $d commit -q -m second 2>$null
        $sh = Join-Path ([System.IO.Path]::GetTempPath()) ("clavity-shallow-" + [guid]::NewGuid().ToString('N'))
        & git -c core.autocrlf=false clone -q --depth 1 "file://$($d -replace '\\','/')" $sh 2>$null
        $out = & pwsh -NoProfile -File $script:Script -RepoRoot $sh -StoreDir 'rules' 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'SHALLOW repository'
        Remove-Item -Recurse -Force $d, $sh -ErrorAction SilentlyContinue
    }

    # The paired control for the row above - without it, "fails closed" could just mean "always fails",
    # and no other row in this suite clones at all.
    It 'PASSES a FULL clone of that same repository' {
        $d = New-StoreFixture
        Set-Content -NoNewline -Path (Join-Path $d 'rules/alpha.md') -Value "# alpha`n`n- ALPHA REVISED.`n"
        & git -C $d add -A 2>$null; & git -C $d commit -q -m second 2>$null
        $fu = Join-Path ([System.IO.Path]::GetTempPath()) ("clavity-full-" + [guid]::NewGuid().ToString('N'))
        & git -c core.autocrlf=false clone -q $d $fu 2>$null
        $out = & pwsh -NoProfile -File $script:Script -RepoRoot $fu -StoreDir 'rules' 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match '2 rule\(s\)'
        Remove-Item -Recurse -Force $d, $fu -ErrorAction SilentlyContinue
    }

    # CAPSTONE R3 - a DECLARED consolidation re-baselines the high-water mark. Without this, a rule
    # legitimately consolidated once is measured against its all-time peak forever and ordinary later
    # trims eventually trip the gate for nothing. The monotonic property that matters is preserved: only a
    # DECLARED retirement moves the mark, never a silent gutting.
    It 'does not trap a rule against its all-time peak once a retirement is DECLARED' {
        $d = New-StoreFixture
        Set-Content -NoNewline -Path (Join-Path $d 'rules/beta.md') -Value "# beta`n`n> Retired: folded into alpha`n"
        & git -C $d add -A 2>$null; & git -C $d commit -q -m 'declare retirement' 2>$null
        # A later trivial trim, still tiny against the ORIGINAL peak but not against the declared stub.
        Set-Content -NoNewline -Path (Join-Path $d 'rules/beta.md') -Value "# beta`n`n> Retired: folded into alpha"
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match '2 rule\(s\)'
        Remove-Item -Recurse -Force $d
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

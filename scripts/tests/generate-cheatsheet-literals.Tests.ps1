# Tests for scripts/generate-cheatsheet-literals.ps1.
#
# THE GENERATOR-CONTROL PATTERN IS THE FIRST ROW AND THE MOST IMPORTANT ONE: fed the CURRENT core.md,
# the generator must reproduce the CURRENT artifacts BYTE-FOR-BYTE. Only a generator proven against the
# artifact it is replacing may then be trusted to change it. Both existing pinning tests stay and are
# the oracle the generator is proven against - they are NOT to be edited to match generator output.

Describe 'generate-cheatsheet-literals.ps1' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Gen  = Join-Path $script:RepoRoot 'scripts/generate-cheatsheet-literals.ps1'
        $script:Core = Join-Path $script:RepoRoot 'agy-autotrain/knowledge/driver-cheatsheet.core.md'
        $script:Rs   = Join-Path $script:RepoRoot 'clavity-classic/src/driver_cheatsheet.rs'
        $script:Cs   = Join-Path $script:RepoRoot 'clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs'
        Test-Path -LiteralPath $script:Gen | Should -BeTrue
    }

    It 'reproduces BOTH current artifacts byte-for-byte from the current core.md (the control)' {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("gen-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $outRs = Join-Path $tmp 'driver_cheatsheet.rs'
            $outCs = Join-Path $tmp 'DriverCheatsheet.cs'
            Copy-Item -LiteralPath $script:Rs -Destination $outRs
            Copy-Item -LiteralPath $script:Cs -Destination $outCs
            & pwsh -NoProfile -File $script:Gen -CoreSource $script:Core -RustTarget $outRs -CsTarget $outCs
            $LASTEXITCODE | Should -Be 0
            # BYTE comparison, both directions. A text comparison would hide exactly the line-ending
            # and encoding defects this item exists to prevent.
            [IO.File]::ReadAllBytes($outRs) | Should -Be ([IO.File]::ReadAllBytes($script:Rs))
            [IO.File]::ReadAllBytes($outCs) | Should -Be ([IO.File]::ReadAllBytes($script:Cs))
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'NORMALISES CRLF to LF - against a CONSTRUCTED fixture, never the live core.md' {
        # THE FIXTURE MUST BE CONSTRUCTED. core.md's line endings depend on the host: after Task 9 it is
        # LF here, and it is LF in CI. A test that feeds the live file processes LF, emits LF and stays
        # green - AND SO DOES THE MUTANT with normalisation deleted. The test and its own mutation
        # control would both pass while proving nothing, which is the worst kind of green: it looks
        # correct on the machine where it was written.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("gencrlf-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $fx = Join-Path $tmp 'core.md'
            [IO.File]::WriteAllBytes($fx, [Text.Encoding]::ASCII.GetBytes("line one`r`nline two`r`nline three`r`n"))
            $outRs = Join-Path $tmp 'x.rs'; $outCs = Join-Path $tmp 'x.cs'
            Copy-Item -LiteralPath $script:Rs -Destination $outRs
            Copy-Item -LiteralPath $script:Cs -Destination $outCs
            & pwsh -NoProfile -File $script:Gen -CoreSource $fx -RustTarget $outRs -CsTarget $outCs
            $LASTEXITCODE | Should -Be 0
            # ASSERT ON BYTES, NOT ON A REGEX - panel R3 caught the first version of these two lines as a
            # VACUOUS ORACLE. They read `Should -Not -Match '\\r'`, and in a PowerShell single-quoted
            # string that is backslash-backslash-r, which as a regex matches the two-character TEXT \r -
            # not a carriage return. Deleting the generator's normalisation leaves RAW 0x0D bytes in the
            # output, which do not match that pattern at all, so the row stayed GREEN against the exact
            # break it names. The -Because text said "a bare \r" while the pattern tested the escaped
            # form: intent and implementation disagreed, which is what made it look correct.
            ([IO.File]::ReadAllBytes($outRs) | Where-Object { $_ -eq 13 }).Count |
                Should -Be 0 -Because 'a raw CR (0x0D) must never be baked into the Rust literal'
            ([IO.File]::ReadAllBytes($outCs) | Where-Object { $_ -eq 13 }).Count |
                Should -Be 0 -Because 'a raw CR (0x0D) must never be baked into the C# literal'
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'writes the container files with LF endings, not the platform newline' {
        # Measured on pwsh 7: Set-Content/Out-File/WriteAllText all PRESERVE LF for a SINGLE string,
        # but the ARRAY form joins with the PLATFORM newline and emits CRLF. The hazard is the array
        # form specifically, so this row pins the OUTPUT container, not just the escaped content.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("genlf-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $outRs = Join-Path $tmp 'x.rs'; $outCs = Join-Path $tmp 'x.cs'
            Copy-Item -LiteralPath $script:Rs -Destination $outRs
            Copy-Item -LiteralPath $script:Cs -Destination $outCs
            & pwsh -NoProfile -File $script:Gen -CoreSource $script:Core -RustTarget $outRs -CsTarget $outCs
            ([IO.File]::ReadAllBytes($outRs) | Where-Object { $_ -eq 13 }).Count | Should -Be 0
            ([IO.File]::ReadAllBytes($outCs) | Where-Object { $_ -eq 13 }).Count | Should -Be 0
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'escapes BACKSLASH FIRST - a backslash in the source does not become an escaped newline' {
        # ORDER IS PART OF THE CONTRACT. Escaping the newline before the backslash makes the generator
        # escape its OWN output: LF becomes the two characters \n, and a later backslash pass turns
        # that into \\n, which both compilers read as a literal backslash followed by n. The literal
        # then COMPILES CLEANLY and fails the pinning test with a diff no one can see at a glance.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("genesc-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $fx = Join-Path $tmp 'core.md'
            [IO.File]::WriteAllText($fx, "alpha \ beta`ngamma `"quoted`" delta`n")
            $outRs = Join-Path $tmp 'x.rs'; $outCs = Join-Path $tmp 'x.cs'
            Copy-Item -LiteralPath $script:Rs -Destination $outRs
            Copy-Item -LiteralPath $script:Cs -Destination $outCs
            & pwsh -NoProfile -File $script:Gen -CoreSource $fx -RustTarget $outRs -CsTarget $outCs
            $rs = [IO.File]::ReadAllText($outRs)
            $rs | Should -Match 'alpha \\\\ beta'   -Because 'a literal backslash must be emitted as \\'
            $rs | Should -Match 'gamma \\"quoted\\" delta'
            $rs | Should -Not -Match '\\\\n'        -Because 'a newline must be \n, never \\n'
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'produces the C# LINE-BOUNDARY shape: no leading +, no trailing \n on the last segment, ends ;' {
        $cs = [IO.File]::ReadAllText($script:Cs)
        $cs | Should -Match '(?m)^public const string BaselineFloor =\r?\n\s+"' -Because 'the FIRST segment carries no +'
        $cs | Should -Match '(?m)^\s+\+ ".*";\s*$'                              -Because 'the LAST segment ends with ; '
        $cs | Should -Not -Match '(?m)^\s+\+ ".*\\n";\s*$'                      -Because 'the LAST segment has no trailing \n'
    }

    It 'REFUSES to write when the anchor is not found EXACTLY once' {
        # A splice on a non-unique anchor deletes the span between matches. The generator must fail
        # loudly rather than mangle a source file.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("genanch-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $outRs = Join-Path $tmp 'x.rs'; $outCs = Join-Path $tmp 'x.cs'
            [IO.File]::WriteAllText($outRs, "// no anchor here`n")
            Copy-Item -LiteralPath $script:Cs -Destination $outCs
            & pwsh -NoProfile -File $script:Gen -CoreSource $script:Core -RustTarget $outRs -CsTarget $outCs 2>&1 | Out-Null
            $LASTEXITCODE | Should -Not -Be 0
            [IO.File]::ReadAllText($outRs) | Should -BeExactly "// no anchor here`n" -Because 'a refused run must leave the target untouched'
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # ---------------------------------------------------------------- AGY-TEST-AUDIT round B, GAP-2/3.
    # THE ROW ABOVE IS NAMED "not found EXACTLY once" BUT ONLY EVER SEEDS **ZERO** ANCHORS, and it mutates
    # only the RUST target. So `-ne 1` could be weakened to `-eq 0` and ship green, and every C# guard -
    # there are THREE - had no row at all, because the rust check at :103 fails first and the C# block is
    # never reached. The duplicate case is the dangerous half: a splice on a non-unique anchor DELETES THE
    # SPAN BETWEEN MATCHES, which is why the guard is `-ne 1` and not `-eq 0` in the first place.
    It 'REFUSES a DUPLICATED rust anchor - the case that would delete the span between matches' {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("gendup-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $outRs = Join-Path $tmp 'x.rs'; $outCs = Join-Path $tmp 'x.cs'
            # A REAL artifact plus a SECOND anchor, so the file is valid in every other respect and the
            # only thing under test is the count. Seeding two synthetic lines would also pass the guard
            # but would not resemble the accident this protects against (a duplicated const after a merge).
            $dup = [IO.File]::ReadAllText($script:Rs) + "pub const BASELINE_FLOOR: &str = `"dup`";`n"
            [IO.File]::WriteAllText($outRs, $dup)
            Copy-Item -LiteralPath $script:Cs -Destination $outCs
            $out = & pwsh -NoProfile -File $script:Gen -CoreSource $script:Core -RustTarget $outRs -CsTarget $outCs 2>&1 | Out-String
            $LASTEXITCODE | Should -Not -Be 0
            $out | Should -Match 'found 2' -Because 'the operator needs the COUNT to know it is a duplicate rather than a missing anchor - the two have opposite remedies'
            [IO.File]::ReadAllText($outRs) | Should -BeExactly $dup -Because 'a refused run must leave the target byte-for-byte untouched, which is the whole reason the guard precedes the splice'
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'REFUSES a broken C# target (<Case>) and writes NEITHER file' -ForEach @(
        @{ Case = 'no anchor';        Expect = "no 'public const string BaselineFloor =' anchor found" }
        @{ Case = 'duplicate anchor'; Expect = "expected exactly ONE 'public const string BaselineFloor =' line" }
        @{ Case = 'no literal end';   Expect = 'could not find the end of the BaselineFloor literal' }
    ) {
        # THE RUST TARGET IS DELIBERATELY VALID HERE. The generator validates rust first and Fails at
        # :103, so a row that breaks both files proves nothing about the C# guards - it never reaches them.
        # 'no literal end' is a THIRD guard (:148) that the audit did not name; it was found by reading the
        # block rather than the report, and it was equally uncovered. Sweep for siblings.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("gencs-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $outRs = Join-Path $tmp 'x.rs'; $outCs = Join-Path $tmp 'x.cs'
            Copy-Item -LiteralPath $script:Rs -Destination $outRs
            # SENTINEL ANCHOR - without it the rust assertion below is VACUOUS, and it WAS (capstone
            # round 1, confirmed end-to-end). The fixture used to copy the CANONICAL .rs, which already
            # holds exactly the bytes a regeneration produces, so an errant early write rewrote identical
            # content and the byte comparison saw nothing: with the generator patched to write rust
            # BEFORE validating C#, all three rows still passed.
            # The sentinel must keep the file VALID or the fix breaks the row a different way - a rust
            # target the generator REJECTS fails at :103 and never reaches the C# block these rows exist
            # to test. (That is why the reviewer's suggested remedy - overwrite the target with junk -
            # was not taken.) So: keep exactly ONE line matching the anchor pattern, but give it a
            # payload no regeneration would produce. A rewrite replaces that line; a refusal leaves it.
            $rsLines = [IO.File]::ReadAllText($outRs).Replace("`r`n", "`n") -split "`n"
            for ($i = 0; $i -lt $rsLines.Count; $i++) {
                if ($rsLines[$i] -like 'pub const BASELINE_FLOOR: &str = *') {
                    $rsLines[$i] = 'pub const BASELINE_FLOOR: &str = "CAPSTONE-SENTINEL-NOT-REGENERATED";'
                    break
                }
            }
            [IO.File]::WriteAllText($outRs, ($rsLines -join "`n"), (New-Object Text.UTF8Encoding($false)))
            $csText = [IO.File]::ReadAllText($script:Cs).Replace("`r`n", "`n")
            $anchor = 'public const string BaselineFloor ='
            switch ($Case) {
                'no anchor'        { $csText = $csText.Replace($anchor, 'public const string SomethingElse =') }
                'duplicate anchor' { $csText = $csText -replace [regex]::Escape($anchor), "$anchor`n        public const string BaselineFloor =" }
                # (?m) IS LOAD-BEARING. Without it this anchors to the end of the WHOLE STRING and strips
                # one occurrence, leaving every other segment terminator intact - the generator then found
                # its end line, exited 0, and this row failed at baseline. The guard at :148 scans
                # LINE BY LINE (`$csLines[$i] -match '";\s*$'`), so the fixture must break every line.
                'no literal end'   { $csText = $csText -replace '(?m)";\s*$', '"' }
            }
            [IO.File]::WriteAllText($outCs, $csText)
            $rsBefore = [IO.File]::ReadAllBytes($outRs)
            $out = & pwsh -NoProfile -File $script:Gen -CoreSource $script:Core -RustTarget $outRs -CsTarget $outCs 2>&1 | Out-String
            $LASTEXITCODE | Should -Not -Be 0
            $out | Should -BeLike "*$Expect*" -Because 'each C# guard names a DIFFERENT repair; a shared "something is wrong" would not tell them apart'
            [IO.File]::ReadAllText($outCs) | Should -BeExactly $csText -Because 'a refused run must leave the C# target untouched'
            # THE LOAD-BEARING ONE: every write happens AFTER every validation (:162-167), so a C#-side
            # refusal must leave the RUST file untouched too. Moving either write above the C# block would
            # half-apply a regeneration - one literal new, one old, and the parity gate reporting drift
            # nobody introduced. Nothing else in this suite pins that ordering.
            [IO.File]::ReadAllBytes($outRs) | Should -Be $rsBefore -Because 'validate-everything-then-write: a C# failure must not leave a rewritten rust literal behind'
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'STRIPS a leading UTF-8 BOM from the canonical source (GAP-4)' {
        # The generator decodes with ReadAllBytes + UTF8.GetString DELIBERATELY, which keeps a BOM as
        # U+FEFF, then strips it at :73. No fixture had ever supplied one, so deleting that line shipped
        # green while baking U+FEFF into the START of both literals.
        # ASSERTED AS A BYTE-EQUALITY AGAINST A BOM-LESS TWIN, not as `Should -Not -Match [char]0xFEFF`.
        # A negative assertion here would pass for the wrong reason if the fixture failed to carry a BOM
        # at all - the exact vacuity shape this audit is hunting. The twin cannot pass unless the BOM was
        # genuinely removed AND nothing else diverged.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("genbom-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $body = "Driver text line one`nand line two`n"
            $withBom = Join-Path $tmp 'core-bom.md'
            $noBom   = Join-Path $tmp 'core-plain.md'
            [IO.File]::WriteAllBytes($withBom, ([byte[]]@(0xEF, 0xBB, 0xBF) + [Text.Encoding]::UTF8.GetBytes($body)))
            [IO.File]::WriteAllBytes($noBom, [Text.Encoding]::UTF8.GetBytes($body))
            # PRECONDITION: prove the fixture really carries a BOM, or this row tests nothing.
            ([IO.File]::ReadAllBytes($withBom))[0..2] | Should -Be ([byte[]]@(0xEF, 0xBB, 0xBF)) -Because 'if the fixture has no BOM the comparison below is vacuous'

            $bomRs = Join-Path $tmp 'bom.rs'; $bomCs = Join-Path $tmp 'bom.cs'
            $refRs = Join-Path $tmp 'ref.rs'; $refCs = Join-Path $tmp 'ref.cs'
            Copy-Item -LiteralPath $script:Rs -Destination $bomRs; Copy-Item -LiteralPath $script:Cs -Destination $bomCs
            Copy-Item -LiteralPath $script:Rs -Destination $refRs; Copy-Item -LiteralPath $script:Cs -Destination $refCs
            & pwsh -NoProfile -File $script:Gen -CoreSource $withBom -RustTarget $bomRs -CsTarget $bomCs
            $LASTEXITCODE | Should -Be 0
            & pwsh -NoProfile -File $script:Gen -CoreSource $noBom -RustTarget $refRs -CsTarget $refCs
            $LASTEXITCODE | Should -Be 0
            [IO.File]::ReadAllBytes($bomRs) | Should -Be ([IO.File]::ReadAllBytes($refRs)) -Because 'a BOM in the canonical source must not reach the rust literal'
            [IO.File]::ReadAllBytes($bomCs) | Should -Be ([IO.File]::ReadAllBytes($refCs)) -Because 'a BOM in the canonical source must not reach the C# literal'
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'SKIPS a target given as an empty string, and still writes the other (panel R6)' {
        # The 14e hook needs this: a literal whose deletion is staged is gone from the worktree, so there
        # is nothing to splice into. Without an empty-target skip the hook must Copy-Item a file that does
        # not exist, which throws under $ErrorActionPreference='Stop' and CRASHES the hook on exactly the
        # case its own test table says must PASS.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("genskip-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $outCs = Join-Path $tmp 'x.cs'
            Copy-Item -LiteralPath $script:Cs -Destination $outCs
            & pwsh -NoProfile -File $script:Gen -CoreSource $script:Core -RustTarget '' -CsTarget $outCs
            $LASTEXITCODE | Should -Be 0 -Because 'an empty target means SKIP, not error'
            [IO.File]::ReadAllBytes($outCs) | Should -Be ([IO.File]::ReadAllBytes($script:Cs))
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FAILS on an EMPTY canonical source rather than generating an empty literal (panel R9)' {
        # The generator carries `if ($coreText.Length -eq 0) { Fail ... }` and nothing exercised it. An
        # empty core.md would otherwise splice an empty literal into both binaries and the pinning tests
        # would go red one layer away from the cause.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("genempty-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $fx = Join-Path $tmp 'core.md'
            [IO.File]::WriteAllText($fx, "   `n  `n")   # whitespace only: empty AFTER Trim()
            $outRs = Join-Path $tmp 'x.rs'; $outCs = Join-Path $tmp 'x.cs'
            Copy-Item -LiteralPath $script:Rs -Destination $outRs
            Copy-Item -LiteralPath $script:Cs -Destination $outCs
            $before = [IO.File]::ReadAllBytes($outRs)
            & pwsh -NoProfile -File $script:Gen -CoreSource $fx -RustTarget $outRs -CsTarget $outCs *> $null
            $LASTEXITCODE | Should -Not -Be 0
            [IO.File]::ReadAllBytes($outRs) | Should -Be $before -Because 'a refused run must leave the target untouched'
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'handles a SINGLE-LINE core.md - no dangling + and no trailing \n (panel R9)' {
        # The generator has a dedicated `if ($coreLines.Count -eq 1)` branch for the C# target and the
        # live core.md is multi-line, so nothing exercised it. A whole-string replace would emit either a
        # dangling + or a trailing \n the file side does not have - the exact shape this branch exists for.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("gen1line-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $fx = Join-Path $tmp 'core.md'
            [IO.File]::WriteAllText($fx, "just one line`n")
            $outRs = Join-Path $tmp 'x.rs'; $outCs = Join-Path $tmp 'x.cs'
            Copy-Item -LiteralPath $script:Rs -Destination $outRs
            Copy-Item -LiteralPath $script:Cs -Destination $outCs
            & pwsh -NoProfile -File $script:Gen -CoreSource $fx -RustTarget $outRs -CsTarget $outCs
            $LASTEXITCODE | Should -Be 0
            $cs = [IO.File]::ReadAllText($outCs)
            $cs | Should -Match '"just one line";'
            $cs | Should -Not -Match '\+ "just one line'  -Because 'a single segment is also the FIRST segment and carries no +'
            $cs | Should -Not -Match 'just one line\\n"'  -Because 'the last segment has no trailing \n'
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FAILS when BOTH targets are empty - a no-op run must not report success' {
        & pwsh -NoProfile -File $script:Gen -CoreSource $script:Core -RustTarget '' -CsTarget '' *> $null
        $LASTEXITCODE | Should -Not -Be 0
    }

    It 'preserves pure ASCII (core.md is inside the ASCII-gated domain)' {
        # THIS ROW NEVER RAN THE GENERATOR. It read the CHECKED-IN literals and asserted they carry no
        # byte > 127 - a property of the repository, not of the code under test. Every mutation to the
        # generator left it green, including one emitting non-ASCII, because the generator's output was
        # never looked at. It was named for a behaviour and asserted a fact about two files on disk.
        # Now it runs the generator into a temp target and asserts on THAT, exactly as the LF row above
        # does - which is the row this one should always have been modelled on.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("genascii-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $outRs = Join-Path $tmp 'x.rs'; $outCs = Join-Path $tmp 'x.cs'
            Copy-Item -LiteralPath $script:Rs -Destination $outRs
            Copy-Item -LiteralPath $script:Cs -Destination $outCs
            & pwsh -NoProfile -File $script:Gen -CoreSource $script:Core -RustTarget $outRs -CsTarget $outCs
            $LASTEXITCODE | Should -Be 0 -Because 'a generator that failed to run proves nothing about its output'
            # SCOPED TO THE GENERATED LITERAL, NOT THE WHOLE FILE - the surrounding hand-authored doc
            # comments in both targets legitimately carry non-ASCII bytes (measured: U+00A7, U+2014) that
            # are OUTSIDE the ASCII-gated domain (scripts/check-injected-context.ps1's $DomainRoots does
            # not include clavity-classic/src or clavity-dotnet/src) and outside what the generator ever
            # touches. Checking the whole file would fail permanently regardless of generator correctness.
            $rsLiteralLine = ([IO.File]::ReadAllText($outRs) -split "`n" | Where-Object { $_ -like 'pub const BASELINE_FLOOR: &str = *' })
            ([Text.Encoding]::UTF8.GetBytes(($rsLiteralLine -join "`n")) | Where-Object { $_ -gt 127 }).Count |
                Should -Be 0 -Because 'the GENERATED rust literal must be pure ASCII, not merely the committed one'
            $csLines = [IO.File]::ReadAllText($outCs) -split "`n"
            $csStart = [array]::IndexOf($csLines, ($csLines | Where-Object { $_ -match '^\s*public const string BaselineFloor\s*=\s*$' } | Select-Object -First 1))
            $csEnd = $csStart
            for ($i = $csStart + 1; $i -lt $csLines.Count; $i++) { if ($csLines[$i] -match '";\s*$') { $csEnd = $i; break } }
            $csLiteralBlock = ($csLines[$csStart..$csEnd] -join "`n")
            ([Text.Encoding]::UTF8.GetBytes($csLiteralBlock) | Where-Object { $_ -gt 127 }).Count |
                Should -Be 0 -Because 'the GENERATED C# literal must be pure ASCII, not merely the committed one'
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'supports -WhatIf and writes NOTHING under it (owner rule 2026-08-01)' {
        # Every NEW .ps1 that changes state must implement -WhatIf. A row asserting only that the
        # script EXITS 0 under -WhatIf would stay green against a script that ignored the switch and
        # wrote anyway - which is the whole failure mode. So this asserts the SIDE EFFECT: the two
        # targets must be byte-for-byte unchanged. The fixture seeds them with sentinel content that
        # a real run would certainly overwrite, so "unchanged" cannot be true by coincidence.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("gen-whatif-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $outRs = Join-Path $tmp 'x.rs'; $outCs = Join-Path $tmp 'x.cs'
            # THE SENTINEL FIXTURE MUST STILL CARRY A VALID ANCHOR - the anchor search (locating WHERE to
            # write) runs unconditionally, even under -WhatIf; only the actual WriteAllText call is gated
            # by ShouldProcess. A fixture with no anchor line fails at the anchor-detection stage before
            # -WhatIf is ever consulted, for either invocation, which would make this row pass without
            # ever exercising the dry-run gate.
            [IO.File]::WriteAllText($outRs, 'pub const BASELINE_FLOOR: &str = "SENTINEL-RS";' + "`n")
            [IO.File]::WriteAllText($outCs, "public const string BaselineFloor =`n    `"SENTINEL-CS`";`n")
            $beforeRs = [IO.File]::ReadAllBytes($outRs)
            $beforeCs = [IO.File]::ReadAllBytes($outCs)

            & pwsh -NoProfile -File $script:Gen -CoreSource $script:Core -RustTarget $outRs -CsTarget $outCs -WhatIf
            $LASTEXITCODE | Should -Be 0 -Because '-WhatIf is a dry run, not an error'

            [Linq.Enumerable]::SequenceEqual([IO.File]::ReadAllBytes($outRs), $beforeRs) |
                Should -BeTrue -Because '-WhatIf must not touch the rust target'
            [Linq.Enumerable]::SequenceEqual([IO.File]::ReadAllBytes($outCs), $beforeCs) |
                Should -BeTrue -Because '-WhatIf must not touch the C# target'

            # CONTROL: the same invocation WITHOUT -WhatIf must overwrite both, or the row above
            # passes for the wrong reason (a generator that never writes at all satisfies it).
            & pwsh -NoProfile -File $script:Gen -CoreSource $script:Core -RustTarget $outRs -CsTarget $outCs
            $LASTEXITCODE | Should -Be 0
            [Linq.Enumerable]::SequenceEqual([IO.File]::ReadAllBytes($outRs), $beforeRs) |
                Should -BeFalse -Because 'the control proves a real run DOES write the rust target'
            [Linq.Enumerable]::SequenceEqual([IO.File]::ReadAllBytes($outCs), $beforeCs) |
                Should -BeFalse -Because 'the control proves a real run DOES write the C# target'
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

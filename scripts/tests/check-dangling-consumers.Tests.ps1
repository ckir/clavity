#Requires -Modules Pester

# The gate this exercises was REDESIGNED in capstone round 5. Four earlier versions tried to INFER
# production from prose (a mention, then proximity to a write word, then a negation list, then a
# lookbehind), and a capstone round measured each inference wrong in turn. The rows testing those
# heuristics were deleted with them - keeping tests for deleted behaviour is how a suite starts asserting
# a design nobody ships any more. What replaced them is an explicit marker the producer writes, so these
# rows are about one question: is the declaration present, and does it name this exact file?

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:Script   = Join-Path $script:RepoRoot 'scripts/check-dangling-consumers.ps1'

    # Assembled, never written literally. A fixture containing a marker for a REAL runtime filename would
    # satisfy the gate falsely against the real tree - the residual assumption the script's header states
    # openly. Every fixture below therefore names a FICTIONAL file.
    $script:Marker = [char]64 + 'produces'

    function New-Tree {
        $d = Join-Path ([System.IO.Path]::GetTempPath()) ("clv-dangling-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $d 'clavity-dotnet/src/Clavity.Ls') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $d 'clavity-classic/src') -Force | Out-Null
        $d
    }
    # The same fixture tree, but nested under a directory whose NAME is a segment the gate excludes, so the
    # fixture's ABSOLUTE path carries that segment while the tree itself is healthy. New-Tree above is its
    # paired clean-path control: the two differ in the checkout path and in nothing else.
    function New-TreeUnder([string]$Segment) {
        $outer = Join-Path ([System.IO.Path]::GetTempPath()) ("clv-dangling-" + [guid]::NewGuid().ToString('N'))
        $d = Join-Path (Join-Path $outer $Segment) 'repo'
        New-Item -ItemType Directory -Path (Join-Path $d 'clavity-dotnet/src/Clavity.Ls') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $d 'clavity-classic/src') -Force | Out-Null
        $d
    }
    function Set-Reader([string]$Root, [string]$Body) {
        Set-Content -NoNewline -Path (Join-Path $Root 'clavity-dotnet/src/Clavity.Ls/Thing.cs') -Value $Body
    }
    function Invoke-Check([string]$Root) {
        & pwsh -NoProfile -File $script:Script -RepoRoot $Root 2>&1 | Out-String
    }
}

Describe 'check-dangling-consumers' {

    It 'PASSES when a producer DECLARES the filename' {
        $d = New-Tree
        Set-Reader $d 'public const string GrowthFileName = "thing.growth.md";'
        Set-Content -Path (Join-Path $d 'writer-skill.md') -Value "The curator writes it. $($script:Marker) `"thing.growth.md`""
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'OK - 1 runtime filename constant'
        Remove-Item -Recurse -Force $d
    }

    # THE DEFECT THIS GATE EXISTS FOR, in miniature: a reader pointed at a name with no producer. MEASURED
    # on the real tree before the fix, it named both halves of the pair and nothing else.
    It 'FAILS a reader whose filename nothing declares' {
        $d = New-Tree
        Set-Reader $d 'public const string GrowthFileName = "thing.growth.md";'
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'DANGLING CONSUMER'
        $out | Should -Match 'thing\.growth\.md'
        Remove-Item -Recurse -Force $d
    }

    # THE ROW THAT CARRIES THE WHOLE REDESIGN. Under v1 of this gate, a file merely CONTAINING the filename
    # counted as a producer; MEASURED on the real tree, seven files contained it and exactly one wrote it,
    # so deleting the real writer would have left the gate green. A mention must now be worth nothing.
    It 'does NOT accept a file that merely MENTIONS the name without declaring it' {
        $d = New-Tree
        Set-Reader $d 'public const string GrowthFileName = "thing.growth.md";'
        Set-Content -Path (Join-Path $d 'README.md') `
            -Value 'Troubleshooting: if thing.growth.md is over its cap it is ignored and the baseline is used. The curator writes it during a drain.'
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'DANGLING CONSUMER'
        Remove-Item -Recurse -Force $d
    }

    # The match must be EXACT. A declaration for a neighbouring artifact must not vouch for this one -
    # otherwise one marker anywhere would silence every constant, which is the v1 failure with extra steps.
    It 'does NOT accept a declaration naming a DIFFERENT file' {
        $d = New-Tree
        Set-Reader $d 'public const string GrowthFileName = "thing.growth.md";'
        Set-Content -Path (Join-Path $d 'writer.md') -Value "$($script:Marker) `"other.growth.md`""
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'thing\.growth\.md'
        Remove-Item -Recurse -Force $d
    }

    # A GATE MUST NOT SATISFY ITSELF. The script's own text discusses the marker, and an earlier gate in
    # this review had to special-case its own filename to avoid counting as a producer. Assembling the
    # marker from a char code removes the possibility instead of excluding a path - so this asserts the
    # real repository is not being vouched for by the checker's own prose.
    It 'does not vouch for a filename using its own source text' {
        $d = New-Tree
        Set-Reader $d 'public const string GrowthFileName = "thing.growth.md";'
        Copy-Item $script:Script (Join-Path $d 'copy-of-the-gate.ps1')
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'DANGLING CONSUMER'
        Remove-Item -Recurse -Force $d
    }

    # The exemption is DERIVED from the identifier, never a hand-maintained roster - and it is PRINTED, so
    # an exemption cannot be quiet. Renaming a live constant to dodge the gate is then a visible lie.
    It 'EXEMPTS a constant whose identifier declares it legacy, and SAYS SO' {
        $d = New-Tree
        Set-Reader $d 'public const string LegacyFileName = "old-thing.md";'
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'skipped \(read-only by design\)'
        $out | Should -Match 'LegacyFileName'
        Remove-Item -Recurse -Force $d
    }

    # Both languages must be parsed, or the gate silently covers half the pair - the same shape as the
    # original bug, one variant guarded and the other not.
    It 'parses the RUST declaration form and fails a dangling one' {
        $d = New-Tree
        Set-Content -NoNewline -Path (Join-Path $d 'clavity-classic/src/thing.rs') `
            -Value 'pub const GROWTH_FILE: &str = "rust-only.growth.md";'
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'rust-only\.growth\.md'
        $out | Should -Match 'GROWTH_FILE'
        Remove-Item -Recurse -Force $d
    }

    # ASSERTS THE SPECIFIC MESSAGE, NOT MERELY "SKIP". The previous version of this row asserted exit 0
    # plus the word SKIP, and a capstone round found it VACUOUS: the script had two early exits that both
    # printed SKIP and returned 0, so the row passed with the branch it claimed to guard deleted. The
    # script now has ONE such exit, and this pins its wording.
    It 'SKIPS with a specific reason when there are no filename constants' {
        $d = New-Tree
        Set-Reader $d '// a source file with no runtime filename constant in it'
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'no runtime filename constants found'
        Remove-Item -Recurse -Force $d
    }

    # THE ABSOLUTE-PATH TRAP, AND IT IS A RECURRENCE OF A CAPSTONE FINDING IN THIS SAME FILE. Round 4 found
    # the then-current test-directory exclusion matching the ABSOLUTE path, so a clone into any directory
    # containing 'tests' failed 100% red on a healthy tree. The round-5 redesign deleted that exclusion but
    # left the $searchable filter matching $_.FullName, which is equally absolute - so a checkout under any
    # bin/target/obj/node_modules segment excludes EVERY file, $declared comes back empty, and every
    # consumer is reported dangling. MEASURED 2026-08-28 with a paired control: byte-identical fixture
    # trees, real gate, exit 0 at a clean path and exit 1 one directory deeper under 'bin'.
    #
    # This is also why the live-tree row below cannot stand alone: it passes only because this repository
    # happens to be cloned somewhere with no excluded segment in its path. That makes it a hostage to the
    # checkout location rather than an assertion about the gate.
    It 'is not fooled by an excluded segment in the ABSOLUTE checkout path' {
        $d = New-TreeUnder 'bin'
        Set-Reader $d 'public const string GrowthFileName = "thing.growth.md";'
        Set-Content -Path (Join-Path $d 'writer-skill.md') -Value "The curator writes it. $($script:Marker) `"thing.growth.md`""
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'OK - 1 runtime filename constant'
        Remove-Item -Recurse -Force (Split-Path (Split-Path $d -Parent) -Parent)
    }

    # The live-tree control. It must not cry wolf on the real repository, and it is the row that goes red
    # if a future commit repoints a reader at an undeclared name.
    It 'is GREEN against the real repository' {
        $out = Invoke-Check $script:RepoRoot
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'OK - \d+ runtime filename constant'
    }
}

#Requires -Modules Pester

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:Script   = Join-Path $script:RepoRoot 'scripts/check-dangling-consumers.ps1'

    # Every case runs against a THROWAWAY TREE, never the real repo. The gate's whole value is its FAILURE
    # path, and a failure path that cannot be exercised is indistinguishable from a vacuous one.
    function New-Tree {
        $d = Join-Path ([System.IO.Path]::GetTempPath()) ("clv-dangling-" + [guid]::NewGuid().ToString('N'))
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

    It 'PASSES when a producer writes the name' {
        $d = New-Tree
        Set-Reader $d 'public const string GrowthFileName = "thing.growth.md";'
        Set-Content -Path (Join-Path $d 'writer-skill.md') -Value 'The curator writes thing.growth.md atomically.'
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'OK - 1 runtime filename constant'
        Remove-Item -Recurse -Force $d
    }

    # THE DEFECT THIS GATE EXISTS FOR, reproduced in miniature: a reader pointed at a name with no writer.
    # MEASURED on the real tree before the fix, it named both halves of the pair and nothing else.
    It 'FAILS a reader whose filename has no producer' {
        $d = New-Tree
        Set-Reader $d 'public const string GrowthFileName = "thing.growth.md";'
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'DANGLING CONSUMER'
        $out | Should -Match 'thing\.growth\.md'
        Remove-Item -Recurse -Force $d
    }

    # THE ROW THAT KEEPS THE GATE HONEST, and the one it would be easiest to ship without. A test writes the
    # very file it is testing the reader against, so if tests counted as producers this gate would report OK
    # on exactly the bug it exists to catch - on the real tree the dangling name appeared in three test files
    # and nowhere else. This asserts the POSITIVE (still fails), never a bare -Not -Match, which would also
    # pass if the fixture simply never produced the string.
    It 'does NOT accept a TEST file as a producer' {
        $d = New-Tree
        Set-Reader $d 'public const string GrowthFileName = "thing.growth.md";'
        New-Item -ItemType Directory -Path (Join-Path $d 'clavity-dotnet/tests') -Force | Out-Null
        Set-Content -Path (Join-Path $d 'clavity-dotnet/tests/Thing.Tests.cs') -Value 'File.WriteAllText("thing.growth.md", "x");'
        Set-Content -Path (Join-Path $d 'clavity-classic/src/integration_helper.rs') -Value '// unrelated'
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'DANGLING CONSUMER'
        Remove-Item -Recurse -Force $d
    }

    # The exemption is DERIVED from the identifier, never a hand-maintained roster - and it is PRINTED, so
    # an exemption cannot be quiet. Renaming a live constant to dodge the gate is then a visible lie.
    # CAPSTONE R2 - A MENTION IS NOT A WRITE. The first version accepted any non-test file containing the
    # literal, so documentation counted as a producer. MEASURED on the real tree: SEVEN files contained
    # the name and exactly ONE wrote it - the other six were troubleshooting prose and reader docs, four of
    # which the same commit had just added. Deleting the only writer would have left this gate GREEN.
    It 'does NOT accept a file that merely MENTIONS the name in prose' {
        $d = New-Tree
        Set-Reader $d 'public const string GrowthFileName = "thing.growth.md";'
        Set-Content -Path (Join-Path $d 'README.md') `
            -Value 'Troubleshooting: if thing.growth.md is over its cap it is ignored and the baseline is used.'
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'DANGLING CONSUMER'
        Remove-Item -Recurse -Force $d
    }

    # (Its paired control is the FIRST row in this suite, whose producer file says "The curator WRITES
    # thing.growth.md" - so that row proves the tightening did not simply break the gate into always
    # failing. No separate row is added here for it, because a duplicate assertion is padding, not cover.)

    # CAPSTONE R3 - A DENIAL IS NOT A DECLARATION. MEASURED: the line "Note: we do NOT write
    # thing.growth.md here; the curator owns it" satisfied the producer check, so a comment explicitly
    # denying a write counted as declaring one. "Failed to write to X" in an error string is the same
    # trap. This is the proxy-versus-real-property shape for the third time in one review, which is why
    # it gets a row rather than a comment.
    It 'does NOT accept a line that DENIES writing the name' {
        $d = New-Tree
        Set-Reader $d 'public const string GrowthFileName = "thing.growth.md";'
        Set-Content -Path (Join-Path $d 'note.md') `
            -Value 'Note: we do NOT write thing.growth.md here; the curator owns it.'
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'DANGLING CONSUMER'
        Remove-Item -Recurse -Force $d
    }

    # CAPSTONE R2, the FALSE-ALARM direction, which is the one a gate rarely gets tested for. The old
    # `-like '*Tests.*'` exclusion matched `contests.md` - an ordinary English word - so a genuine producer
    # with an unlucky name was silently discounted. This asserts the gate now sees it.
    It 'does not mistake an ordinary word like "contests" for a test file' {
        $d = New-Tree
        Set-Reader $d 'public const string GrowthFileName = "thing.growth.md";'
        Set-Content -Path (Join-Path $d 'contests.md') -Value 'This publishes thing.growth.md to the runtime directory.'
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        Remove-Item -Recurse -Force $d
    }

    # CAPSTONE R4 - the exclusion was matched against the ABSOLUTE path. MEASURED: a healthy tree cloned
    # into a directory whose name contains "tests" matched `/tests/` for EVERY file, so nothing counted as
    # a producer and the gate failed 100% red on a repository with nothing wrong with it. A gate's answer
    # must not depend on where somebody cloned.
    It 'is unaffected by a checkout path that itself contains a tests directory' {
        $base = Join-Path ([System.IO.Path]::GetTempPath()) ("clv-" + [guid]::NewGuid().ToString('N'))
        $d = Join-Path $base 'tests/clavity'
        New-Item -ItemType Directory -Path (Join-Path $d 'clavity-dotnet/src/Clavity.Ls') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $d 'clavity-classic/src') -Force | Out-Null
        Set-Content -NoNewline -Path (Join-Path $d 'clavity-dotnet/src/Clavity.Ls/Thing.cs') `
            -Value 'public const string GrowthFileName = "thing.growth.md";'
        Set-Content -Path (Join-Path $d 'writer.md') -Value 'The curator writes thing.growth.md using an atomic rename.'
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'OK - 1 runtime filename constant'
        Remove-Item -Recurse -Force $base
    }

    # CAPSTONE R4 - the negation filter added in round 3 vetoed a REAL writer. MEASURED:
    # `if (-not $empty) { Out-File -FilePath "thing.growth.md" }` was read as a denial, so the guard added
    # to stop a false PASS produced a false FAIL instead. `-not` is an operator; the leading hyphen is the
    # entire difference from English prose, and that is what the lookbehind keys on.
    It 'does not mistake the PowerShell -not operator for a denial' {
        $d = New-Tree
        Set-Reader $d 'public const string GrowthFileName = "thing.growth.md";'
        Set-Content -Path (Join-Path $d 'writer.ps1') -Value 'if (-not $empty) { Out-File -FilePath "thing.growth.md" }'
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        Remove-Item -Recurse -Force $d
    }

    It 'EXEMPTS a constant whose identifier declares it legacy, and SAYS SO' {
        $d = New-Tree
        Set-Reader $d 'public const string LegacyFileName = "old-thing.md";'
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'skipped \(read-only by design\)'
        $out | Should -Match 'LegacyFileName'
        Remove-Item -Recurse -Force $d
    }

    It 'EXEMPTS a RETIRED constant too, in Rust syntax' {
        $d = New-Tree
        Set-Content -NoNewline -Path (Join-Path $d 'clavity-classic/src/thing.rs') `
            -Value 'pub const RETIRED_LEGACY_FILE_NAME: &str = "old-thing.md";'
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'RETIRED_LEGACY_FILE_NAME'
        Remove-Item -Recurse -Force $d
    }

    # Both languages must be parsed, or the gate silently covers half the pair - which is the same shape as
    # the bug, one variant guarded and the other not.
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

    It 'SKIPS cleanly when there are no binary sources at all' {
        $d = Join-Path ([System.IO.Path]::GetTempPath()) ("clv-nosrc-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        $out = Invoke-Check $d
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'SKIP'
        Remove-Item -Recurse -Force $d
    }

    # The gate must not cry wolf on the real tree - a checker that reports a false problem is ignored within
    # a week. This is the live-tree control, and it is the one that would go red if a future commit
    # repointed a reader at an unwritten name again.
    It 'is GREEN against the real repository' {
        $out = Invoke-Check $script:RepoRoot
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'OK - \d+ runtime filename constant'
    }
}

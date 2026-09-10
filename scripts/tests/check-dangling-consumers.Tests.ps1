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

    # A PROVIDER-PREFIXED root must not crash the gate. Resolve-Path's .Path preserves such a prefix while
    # Get-ChildItem's .FullName is always native, so $repo came out LONGER than the paths derived from it
    # and every .Substring($repo.Length) threw. MEASURED 2026-08-28: with .Path the subtraction raises
    # MethodInvocationException; with .ProviderPath the two agree. Raised by a capstone round whose stated
    # trigger - "invoked from a non-FileSystem provider" - did NOT reproduce (from inside HKLM:\, .Path
    # returns the bare path), but whose FIX was right for a different input. No caller passes this shape
    # today, so this row guards hardening rather than a live defect; it exists because the failure mode is
    # a crash rather than a wrong answer, and a crash in a gate reads as a broken build.
    #
    # THIS ROW NO LONGER PINS THE .ProviderPath CHOICE, AND THE COMMENT ABOVE MUST NOT BE READ AS SAYING IT
    # DOES. Since ROADMAP section 28 the subtractions go through a New-RootRelativePathResolver resolver, which
    # normalises the root with Get-Item - and MEASURED, Get-Item returns the bare native path for a provider-prefixed
    # input exactly as .ProviderPath does. MEASURED 2026-09-08 by applying it: with the
    # .ProviderPath -> .Path mutant this row now stays GREEN, where before section 28 it went RED.
    # The mechanism is pinned instead by 'normalises a PROVIDER-PREFIXED root' in
    # scripts/tests/path-lib.Tests.ps1, which covers all four gates rather than this one.
    # The row is KEPT because the end-to-end property it asserts - the gate does not crash on this input -
    # is still true and still worth holding.
    It 'does not crash when handed a PROVIDER-PREFIXED repository root' {
        $d = New-Tree
        Set-Reader $d 'public const string GrowthFileName = "thing.growth.md";'
        Set-Content -Path (Join-Path $d 'writer-skill.md') -Value "The curator writes it. $($script:Marker) `"thing.growth.md`""
        $out = Invoke-Check ('Microsoft.PowerShell.Core\FileSystem::' + $d)
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'OK - 1 runtime filename constant'
        Remove-Item -Recurse -Force $d
    }

    # The live-tree control. It must not cry wolf on the real repository, and it is the row that goes red
    # if a future commit repoints a reader at an undeclared name.
    It 'is GREEN against the real repository' {
        $out = Invoke-Check $script:RepoRoot
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'OK - \d+ runtime filename constant'
    }

    It 'reports the correct relative path when -RepoRoot is an 8.3 SHORT path' {
        # THE FIXTURE RULE. This gate early-exits SKIP when no constants are found - its sources are the
        # $sourceGlobs files, matched by $declPattern - so an empty fixture never reaches the subtraction
        # and the row would pass over broken code. Set-Reader plants a declaration that NOTHING produces,
        # which makes the gate emit the DANGLING CONSUMER line whose File column is exactly the subtraction
        # this task migrates. (Named, not numbered: the line numbers first written here were all stale
        # within two commits.)
        #
        # Uses the suite's own New-Tree / Set-Reader / Invoke-Check rather than a hand-rolled fixture, so
        # it cannot drift from the shape every other row here is built on.
        $d = New-Tree
        Set-Reader $d 'public const string GrowthFileName = "thing.growth.md";'
        try {
            $short = $null
            try { $short = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($d).ShortPath } catch { $short = $null }
            if (-not $short -or $short -eq $d) {
                Set-ItResult -Skipped -Because '8.3 short-name generation is disabled on this volume, so the state under test is unreachable here'
            }
            # PRECONDITION, asserted not assumed - otherwise this row passes for the wrong reason.
            $short | Should -Not -Be $d

            $out = Invoke-Check $short
            # PRECONDITION 1: the fixture reached the scan rather than the SKIP early-exit.
            $out | Should -Not -Match 'SKIP'
            # PRECONDITION 2: the dangling report fired, so a File path WAS emitted. Without this the
            # oracle below is satisfied by silence.
            $out | Should -Match 'DANGLING CONSUMER' -Because 'the fixture must reach the code that emits a relative path'
            # THE ORACLE, AND IT MUST BE ANCHORED. An unanchored match on the relative path is NOT enough:
            # MEASURED, the broken form emits
            #   ling-6ea37d90...\clavity-dotnet\src\Clavity.Ls\Thing.cs
            # which CONTAINS 'clavity-dotnet\src\Clavity.Ls\Thing.cs', so `Should -Match` on that alone
            # passes over the defect. Nor does the mangled tail contain the fixture prefix 'clv-dangling-',
            # because the subtraction cut the prefix off - so a "root must not appear" assertion misses it
            # too. Both of those were tried and both passed against the UNMIGRATED gate.
            #
            # Anchor to the literal text the gate prints immediately BEFORE the path, so nothing may
            # sit between it and the relative path.
            $out | Should -Match ([regex]::Escape('DANGLING CONSUMER: clavity-dotnet\src\Clavity.Ls\Thing.cs:')) `
                -Because 'the reported File must be repo-relative, with nothing between the label and the path'
        }
        finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'no script outside scripts/lib computes a repo-relative path by hand (ROADMAP section 28 guard)' {
        # A CATALOGUE OF LINE NUMBERS CANNOT HOLD THIS - section 22 proved it: a hand-listed 8 sites became
        # TEN within two weeks. So the population is discovered by glob.
        #
        # THE HONEST LIMIT OF THIS GUARD, stated because a guard that fails open certifies exactly what it
        # stopped checking: it matches the IDIOM all eight migrated sites used. It does NOT catch a split
        # form -- `$p = $_.FullName` on one line and `$p.Substring($root.Length)` on the next -- nor
        # `.Remove(0, $root.Length)`. It raises the cost of reintroducing the defect; it does not make it
        # impossible. Do not let a future reader mistake it for exhaustive.
        $scripts = Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'scripts') -Filter '*.ps1' -File
        $scripts.Count | Should -BeGreaterThan 0 -Because 'an empty glob would make this guard vacuous'

        $bad = foreach ($s in $scripts) {
            if ([IO.File]::ReadAllText($s.FullName) -match '\.FullName\)?\.Substring\(') { $s.Name }
        }
        $bad | Should -BeNullOrEmpty -Because 'build a resolver with New-RootRelativePathResolver from scripts/lib/path-lib.ps1, ONCE, before the loop, and call .Resolve(): it normalises an 8.3 short root, strips a trailing separator, and throws when the path is not under the root'
    }

    It 'every gate that reports repo-relative paths dot-sources the helper and builds a RESOLVER' {
        # THE POSITIVE HALF. The prohibition above goes green if someone DELETES a call site; this row goes
        # red if someone removes the dot-source while leaving the calls, which is the likelier accident.
        #
        # AND IT PINS THE CAPSTONE PERFORMANCE FIX. The gates must build a resolver with
        # New-RootRelativePathResolver and call .Resolve() - never the one-off Get-RootRelativePath, which
        # runs Get-Item on every call. Three of these call sites run once per FILE across the whole
        # repository; an AGY-CAPSTONE round measured the one-off form at about 64 SECONDS per gate run.
        # The unit row that proves .Resolve() never touches the disk pins the LIBRARY; this row pins the
        # CALLERS, because a caller reaching back for the convenient wrapper inside a loop would pass every
        # correctness row while silently reintroducing the regression.
        #
        # READ FROM THE PARSER, NOT THE TEXT. AGY-CAPSTONE round 2 on bb64f73: the text form of this row
        # forbade the literal 'Get-RootRelativePath -Root', so a POSITIONAL call passed it. MEASURED by
        # rewriting one of this gate's three sites to `Get-RootRelativePath $repo $f.FullName`: the row
        # stayed GREEN, because the other two sites still satisfied '\.Resolve\('. Text matching also reads
        # COMMENTS, so every positive check here could be satisfied by a comment that merely names the thing.
        # The AST sees commands whatever their argument form, and never sees a comment.
        #
        # AND "ONCE" IS CHECKED, NOT ASSUMED. A resolver built INSIDE a loop passes every check above and is
        # the 64-second regression again. So the construction may not sit under a loop statement, nor under
        # a scriptblock literal - the body of ForEach-Object / Where-Object, which runs once per item.
        #
        # THE HONEST LIMIT: GetCommandName() is the name as WRITTEN. An alias, or a call through a variable
        # (`& $fn`), is invisible to it; so is a resolver built in a function that is itself called per file.
        $A = 'System.Management.Automation.Language'
        foreach ($g in @('check-injected-context', 'check-installer-ascii', 'check-dangling-consumers', 'check-plugin-drift')) {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $script:RepoRoot "scripts/$g.ps1"), [ref]$tokens, [ref]$errors)
            $errors | Should -BeNullOrEmpty -Because "$g must parse, or everything read from its AST below is partial"
            $commands = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))

            $dotSources = @($commands | Where-Object {
                $_.InvocationOperator -eq 'Dot' -and $_.Extent.Text.Contains("'lib' 'path-lib.ps1'") })
            $dotSources.Count | Should -BeGreaterThan 0 -Because "$g reports repo-relative paths"

            $builds = @($commands | Where-Object { $_.GetCommandName() -eq 'New-RootRelativePathResolver' })
            $builds.Count | Should -BeGreaterThan 0 -Because "$g must build a resolver once, not normalise per call"
            foreach ($b in $builds) {
                for ($p = $b.Parent; $p; $p = $p.Parent) {
                    $p -is "$A.LoopStatementAst" | Should -BeFalse -Because "$g builds its resolver inside a loop at line $($b.Extent.StartLineNumber), which re-runs Get-Item per item"
                    $p -is "$A.ScriptBlockExpressionAst" | Should -BeFalse -Because "$g builds its resolver inside a scriptblock literal at line $($b.Extent.StartLineNumber), which ForEach-Object / Where-Object run per item"
                }
            }

            $resolves = @($ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                $n.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                $n.Member.Value -eq 'Resolve' }, $true))
            $resolves.Count | Should -BeGreaterThan 0 -Because "$g must actually use the resolver it builds"

            $oneOff = @($commands | Where-Object { $_.GetCommandName() -eq 'Get-RootRelativePath' })
            $oneOff | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Extent.Text)" } |
                Should -BeNullOrEmpty -Because "$g must not call the one-off wrapper, which runs Get-Item on every call"
        }
    }
}

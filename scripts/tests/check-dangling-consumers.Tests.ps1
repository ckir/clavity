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
    # THE ROADMAP SECTION 28 GUARDS' ONE POPULATION, shared so the two rows cannot drift apart: every .ps1
    # under scripts/, RECURSIVELY, except the two subtrees that must not be judged by these rules -
    # scripts/lib (the library itself) and scripts/tests (whose It { } blocks legitimately call the one-off
    # wrapper inside a scriptblock literal). AGY-CAPSTONE round 5: both rows used a NON-recursive glob, so a
    # gate added in a subdirectory such as scripts/ci/ was never seen. Directories are excluded by NAME, one
    # level down, rather than by path arithmetic - which is the very thing section 28 exists to avoid.
    #
    # -Root EXISTS ONLY SO A FIXTURE TREE CAN BE FED IN (AGY-TEST-AUDIT section 28, G2). Against the real
    # tree the subdirectory half contributes ONE file that uses path-lib not at all, so MEASURED, dropping
    # -Recurse or that whole half left every row green. The rows below default to the real repository.
    function Get-Section28Population([string]$Root = $script:RepoRoot) {
        $dir = Join-Path $Root 'scripts'
        @(Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File) +
        @(Get-ChildItem -LiteralPath $dir -Directory | Where-Object Name -NotIn 'lib', 'tests' |
            ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter '*.ps1' -File -Recurse })
    }

    # THE TWO SECTION 28 GUARDS, lifted out of their It blocks so a FIXTURE can be fed to them
    # (AGY-TEST-AUDIT section 28, G1). Inline, they could only ever read the real tree - which is clean - so
    # nothing in the suite could show they fire. MEASURED: making the prohibition regex unmatchable, or
    # switching off either half of the positive guard, left all three guard rows GREEN. The fixture rows in
    # 'the section 28 guards can FAIL' are what now go red instead.

    # Returns the NAME of every file whose code computes a repo-relative path by hand.
    #
    # COMMENTS ARE BLANKED BEFORE MATCHING. Round 8: matching raw text meant a comment that SPELLED the
    # idiom - the natural way to warn a reader off it - reddened the row on correct code. That had already
    # bitten section 28 once (Task 5 had to reword a comment). The parser's own Comment tokens are cut out
    # by offset; code and strings are matched exactly as before. STRINGS ARE NOT BLANKED, on purpose: an
    # interpolated "$(...)" string is one token whose $() EXECUTES.
    #
    # A COMMENT IS CUT OUT, NOT REPLACED BY A SPACE (AGY-TEST-AUDIT section 28, round 2). MEASURED:
    # `$f.FullName<#c#>.Substring(3)` parses as a real Substring call, and a space in the comment's place
    # turned it into `$f.FullName .Substring(`, which the regex does not match - an inline comment hid the
    # idiom. Cutting it out rejoins the two halves. Measured the same day against all 39 scripts of the real
    # population: none reddens, so no comment there glues two unrelated tokens into the idiom.
    function Find-HandRolledRelativePath([System.IO.FileInfo[]]$Files) {
        foreach ($s in $Files) {
            $tokens = $null; $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$tokens, [ref]$errors)
            $text = [IO.File]::ReadAllText($s.FullName)
            $code = [System.Text.StringBuilder]::new()
            $at = 0
            foreach ($c in @($tokens | Where-Object Kind -eq 'Comment')) {
                [void]$code.Append($text, $at, $c.Extent.StartOffset - $at)
                $at = $c.Extent.EndOffset
            }
            [void]$code.Append($text, $at, $text.Length - $at)
            if ($code.ToString() -match '\.FullName\)?\.Substring\(') { $s.Name }
        }
    }

    # Returns @{ Users = <files that call path-lib>; Problems = <one line per violation> }.
    #
    # READ FROM THE PARSER, NOT THE TEXT. Round 2 on bb64f73: the text form forbade the literal
    # 'Get-RootRelativePath -Root', so a POSITIONAL call passed it - MEASURED. Text also reads COMMENTS.
    # The AST sees commands whatever their argument form, and never sees a comment.
    #
    # "PER ITEM" MEANS ANY ANCESTOR THAT RUNS ITS BODY ONCE PER ITEM: a loop statement; a `switch`, which
    # iterates a collection but is NOT a LoopStatementAst (round 3 - measured, its body ran 3 times for 3
    # items); a scriptblock literal, the body of ForEach-Object / Where-Object / .ForEach(); or a
    # `process` block, which is also what a `filter` body parses to.
    #
    # THE HONEST LIMIT: GetCommandName() is the name as WRITTEN. An alias, or a call through a variable
    # (`& $fn`), is invisible to it; so is either command inside a function that is itself called per
    # item. A QUALIFIED name is not a hole: `path-lib\Get-RootRelativePath` and `.\Get-RootRelativePath`
    # both throw CommandNotFoundException at runtime - MEASURED, round 3 - because path-lib is
    # dot-sourced, not a module.
    #
    # A DOT-SOURCE IS RECOGNISED BY THE STRING IT LOADS, NOT BY HOW IT IS SPELLED. Round 5: matching the
    # literal text `'lib' 'path-lib.ps1'` false-REDded three legitimate forms - double quotes, a single
    # backslash path, an expandable "$PSScriptRoot\lib\path-lib.ps1" - MEASURED. So a dot-sourced command
    # counts when any string inside it ends in path-lib.ps1 at a path boundary; the measured distractors
    # (release-lib.ps1, mypath-lib.ps1, and `&` instead of `.`) are all rejected.
    function Find-PathLibProblem([System.IO.FileInfo[]]$Files) {
        $A = 'System.Management.Automation.Language'
        $users = 0
        $problems = @(foreach ($s in $Files) {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$tokens, [ref]$errors)
            if ($errors) { "$($s.Name): does not parse, so its AST cannot be checked - $($errors[0].Message)"; continue }
            $calls = @($ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -in 'New-RootRelativePathResolver', 'Get-RootRelativePath' }, $true))
            if (-not $calls) { continue }
            $users++
            $dotSourced = $ast.Find({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and $n.InvocationOperator -eq 'Dot' -and
                $n.Find({ param($v)
                    ($v -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                     $v -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -and
                    $v.Value -match '(^|[\\/])path-lib\.ps1$' }, $true) }, $true)
            if (-not $dotSourced) { "$($s.Name): calls $($calls[0].GetCommandName()) but never dot-sources scripts/lib/path-lib.ps1" }
            foreach ($c in $calls) {
                for ($p = $c.Parent; $p; $p = $p.Parent) {
                    $per = if ($p -is "$A.LoopStatementAst") { 'a loop' }
                           elseif ($p -is "$A.SwitchStatementAst") { 'a switch' }
                           elseif ($p -is "$A.ScriptBlockExpressionAst") { 'a scriptblock literal (ForEach-Object / Where-Object)' }
                           elseif ($p -is "$A.NamedBlockAst" -and $p.BlockKind -eq 'Process') { 'a process block or filter' }
                    if ($per) { "$($s.Name) line $($c.Extent.StartLineNumber): $($c.GetCommandName()) inside $per runs Get-Item once per item"; break }
                }
            }
        })
        @{ Users = $users; Problems = $problems }
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

    It 'no script outside scripts/lib and scripts/tests computes a repo-relative path by hand (ROADMAP section 28 guard)' {
        # A CATALOGUE OF LINE NUMBERS CANNOT HOLD THIS - section 22 proved it: a hand-listed 8 sites became
        # TEN within two weeks. So the population is discovered: Get-Section28Population, in BeforeAll.
        #
        # THE HONEST LIMIT OF THIS GUARD, stated because a guard that fails open certifies exactly what it
        # stopped checking: it matches the IDIOM all eight migrated sites used. It does NOT catch a split
        # form -- `$p = $_.FullName` on one line and `$p.Substring($root.Length)` on the next -- nor
        # `.Remove(0, $root.Length)`, nor - AGY-CAPSTONE round 8, MEASURED - a string REPLACE of the root:
        # `$_.FullName.Replace($root, '')` and `$_.FullName -replace "^$([regex]::Escape($root))", ''` both
        # return the whole absolute path unchanged when the root is short and the child long. Matching `.Replace(`
        # is not the answer: `$_.FullName.Replace('\', '/')` is everywhere and correct. For the FOUR MIGRATED
        # GATES there is a behavioural backstop - reverting any one of them to either replace form reddens that
        # gate's own 8.3 integration row (measured, round 8) - but a NEW script has only this regex. It raises
        # the cost of reintroducing the defect; it does not make it impossible. Do not mistake it for exhaustive.
        #
        # The matching itself is Find-HandRolledRelativePath, in BeforeAll, where it can be fed a fixture.
        $scripts = @(Get-Section28Population)
        $scripts.Count | Should -BeGreaterThan 0 -Because 'an empty glob would make this guard vacuous'

        $bad = @(Find-HandRolledRelativePath $scripts)
        $bad | Should -BeNullOrEmpty -Because 'build a resolver with New-RootRelativePathResolver from scripts/lib/path-lib.ps1, ONCE, before the loop, and call .Resolve(): it normalises an 8.3 short root, strips a trailing separator, and throws when the path is not under the root'
    }

    It 'every script outside scripts/lib and scripts/tests that uses path-lib dot-sources it and never builds per item (ROADMAP section 28 guard)' {
        # THE POSITIVE HALF, AND THE CAPSTONE PERFORMANCE FIX. The prohibition above goes green if someone
        # DELETES a call site; this row goes red if someone removes the dot-source while leaving the calls.
        # It also pins the per-call cost: Get-RootRelativePath runs Get-Item on every call, and so does a
        # resolver built inside a loop. Three of the gates' call sites run once per FILE across the whole
        # repository; an AGY-CAPSTONE round measured the per-call form at about 64 SECONDS per gate run.
        # The unit row proving .Resolve() never touches the disk pins the LIBRARY; this row pins the CALLERS.
        #
        # THE POPULATION IS DISCOVERED, like the prohibition's. AGY-CAPSTONE round 4: this row used to check
        # four hand-listed gates under a title promising "every gate", so a NEW script using path-lib was
        # never checked. The rule is the README's rule (scripts/README.md, path-lib), not a stricter one:
        # Get-RootRelativePath is a legitimate ONE-OFF, so it is forbidden only where it would run per item.
        # Two earlier checks were DROPPED by agreement with the peer, and the owner ruled on the result: an
        # outright ban on the one-off, which contradicted the README once the population widened; and a check
        # that .Resolve() is called on the variable a build is assigned to, which false-REDded a gate that
        # resolves through a helper's parameter and was satisfiable by one dead call. The next row is the
        # floor that keeps the four migrated gates pinned.
        #
        # The AST walk itself - what counts as a call, a dot-source and "per item", and its honest limit - is
        # Find-PathLibProblem, in BeforeAll, where it can be fed a fixture.
        $scripts = @(Get-Section28Population)
        $scripts.Count | Should -BeGreaterThan 0 -Because 'an empty glob would make this guard vacuous'

        $r = Find-PathLibProblem $scripts
        $r.Users | Should -BeGreaterThan 0 -Because 'the four section 28 gates use path-lib, so finding no user at all means discovery is broken'
        $r.Problems | Should -BeNullOrEmpty -Because 'build the resolver ONCE, before the loop, and call .Resolve() inside it (scripts/README.md, path-lib)'
    }

    It 'the four gates section 28 migrated still build a resolver (the floor)' {
        # THE FLOOR - the one hand list left, and it can only ADD checks, never skip a script the row above
        # would see. The discovered row only sees a script that still calls path-lib; a migrated gate that
        # dropped path-lib ENTIRELY and went back to path arithmetic the prohibition regex does not recognise
        # would vanish from its population. These four walk the repository per file by construction, so for
        # them "stopped building a resolver" IS the regression. Deliberately minimal - it asserts the build
        # exists, nothing about how it is used - so no assignment walk and no .Resolve counting: the round-4
        # objections to a fuller floor do not apply. Owner-ruled 2026-09-11.
        foreach ($g in @('check-injected-context', 'check-installer-ascii', 'check-dangling-consumers', 'check-plugin-drift')) {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $script:RepoRoot "scripts/$g.ps1"), [ref]$tokens, [ref]$errors)
            $errors | Should -BeNullOrEmpty -Because "$g must exist and parse; a renamed gate is renamed here too"
            $builds = @($ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'New-RootRelativePathResolver' }, $true))
            $builds.Count | Should -BeGreaterThan 0 -Because "$g walks the repository per file, so it must build a resolver once rather than normalise per call"
        }
    }

    # AGY-TEST-AUDIT section 28, G1 and G2. The three guard rows above read the REAL tree, which is clean, so
    # on their own they cannot show that they fire. These rows feed the SAME functions a fixture and assert
    # WHICH file is flagged - never how many - including files that must NOT be flagged, so a guard that
    # over-matches reddens as surely as one that under-matches. Everything here parses in-process; no child
    # pwsh, so the rows cost milliseconds.
    Context 'the section 28 guards can FAIL' {
        BeforeAll {
            $script:G = Join-Path ([IO.Path]::GetTempPath()) ("s28g-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $script:G | Out-Null
            function New-Fixture([string]$Name, [string[]]$Lines) {
                $p = Join-Path $script:G $Name
                [IO.File]::WriteAllLines($p, $Lines)
                Get-Item -LiteralPath $p
            }
            $script:Dot = ". (Join-Path `$PSScriptRoot 'lib' 'path-lib.ps1')"
        }
        AfterAll { Remove-Item -LiteralPath $script:G -Recurse -Force -ErrorAction SilentlyContinue }

        It 'the prohibition flags the idiom in CODE and inside an interpolated string, and nothing in a comment' {
            $files = @(
                New-Fixture 'hand-rolled.ps1'   @('Get-ChildItem $root -Recurse -File | ForEach-Object { $_.FullName.Substring($root.Length) }')
                # The optional `\)?` in the regex: the parenthesised form must be caught too.
                New-Fixture 'parenthesised.ps1' @('$rel = ($f.FullName).Substring($root.Length)')
                # An interpolated "$(...)" EXECUTES its contents, so strings must stay matched.
                New-Fixture 'in-a-string.ps1'   @('Write-Host "rel: $($f.FullName.Substring($root.Length))"')
                # Still a real Substring call with an inline comment inside it - the comment must not hide it.
                New-Fixture 'comment-split.ps1' @('$rel = $f.FullName<#why#>.Substring($root.Length)')
                # The two comment forms: spelling the idiom to warn a reader off it is correct code.
                New-Fixture 'line-comment.ps1'  @('# never write $f.FullName.Substring($root.Length) here', '$rel = $r.Resolve($f.FullName)')
                New-Fixture 'block-comment.ps1' @('<# $f.FullName.Substring($root.Length) #>', '$rel = $r.Resolve($f.FullName)')
                New-Fixture 'clean.ps1'         @('$rel = $r.Resolve($f.FullName).Replace(''\'', ''/'')')
            )
            @(Find-HandRolledRelativePath $files | Sort-Object) |
                Should -Be @('comment-split.ps1', 'hand-rolled.ps1', 'in-a-string.ps1', 'parenthesised.ps1')
        }

        It 'the positive guard names each violation: a missing dot-source, its look-alikes, every per-item construct, and a file that does not parse' {
            $files = @(
                # A user doing everything right, including a legitimate top-level ONE-OFF.
                New-Fixture 'good.ps1'              @($script:Dot, '$r = New-RootRelativePathResolver -Root $root', 'foreach ($f in $files) { $r.Resolve($f.FullName) }', 'Get-RootRelativePath -Root $root -Path $x')
                New-Fixture 'no-dot-source.ps1'     @('$r = New-RootRelativePathResolver -Root $root')
                # The two measured look-alikes: a name that merely ENDS in path-lib.ps1, and `&` instead of `.`.
                New-Fixture 'wrong-lib.ps1'         @(". (Join-Path `$PSScriptRoot 'lib' 'mypath-lib.ps1')", '$r = New-RootRelativePathResolver -Root $root')
                New-Fixture 'call-operator.ps1'     @("& (Join-Path `$PSScriptRoot 'lib' 'path-lib.ps1')", '$r = New-RootRelativePathResolver -Root $root')
                New-Fixture 'in-loop.ps1'           @($script:Dot, 'foreach ($f in $files) { Get-RootRelativePath -Root $root -Path $f }')
                New-Fixture 'in-switch.ps1'         @($script:Dot, 'switch ($files) { default { New-RootRelativePathResolver -Root $_ } }')
                New-Fixture 'in-foreach-object.ps1' @($script:Dot, '$files | ForEach-Object { Get-RootRelativePath -Root $root -Path $_ }')
                New-Fixture 'in-process.ps1'        @($script:Dot, 'function f { process { New-RootRelativePathResolver -Root $_ } }')
                New-Fixture 'in-filter.ps1'         @($script:Dot, 'filter g { Get-RootRelativePath -Root $root -Path $_ }')
                New-Fixture 'not-a-user.ps1'        @('$x = 1')
                New-Fixture 'broken.ps1'            @('function f {')
            )
            $r = Find-PathLibProblem $files
            $unparsed = @($r.Problems | Where-Object { $_ -like 'broken.ps1: does not parse*' })
            $unparsed.Count | Should -Be 1 -Because 'a file that does not parse must be reported, never silently skipped'
            @($r.Problems | Where-Object { $_ -notlike 'broken.ps1: *' } | Sort-Object) | Should -Be @(
                'call-operator.ps1: calls New-RootRelativePathResolver but never dot-sources scripts/lib/path-lib.ps1'
                'in-filter.ps1 line 2: Get-RootRelativePath inside a process block or filter runs Get-Item once per item'
                'in-foreach-object.ps1 line 2: Get-RootRelativePath inside a scriptblock literal (ForEach-Object / Where-Object) runs Get-Item once per item'
                'in-loop.ps1 line 2: Get-RootRelativePath inside a loop runs Get-Item once per item'
                'in-process.ps1 line 2: New-RootRelativePathResolver inside a process block or filter runs Get-Item once per item'
                'in-switch.ps1 line 2: New-RootRelativePathResolver inside a switch runs Get-Item once per item'
                'no-dot-source.ps1: calls New-RootRelativePathResolver but never dot-sources scripts/lib/path-lib.ps1'
                'wrong-lib.ps1: calls New-RootRelativePathResolver but never dot-sources scripts/lib/path-lib.ps1'
            )
            # good, no-dot-source, wrong-lib, call-operator and the five per-item files. not-a-user calls
            # nothing; broken never reaches the count.
            $r.Users | Should -Be 9
        }

        It 'the population is every .ps1 under scripts/ at ANY depth, except the lib and tests subtrees' {
            $t = Join-Path $script:G 'tree'
            foreach ($rel in 'scripts/top.ps1', 'scripts/not-a-script.txt', 'scripts/ci/shallow.ps1',
                             'scripts/ci/deep/nested.ps1', 'scripts/other/lib/inner.ps1', 'scripts/lib/libfile.ps1',
                             'scripts/tests/t.Tests.ps1', 'scripts/tests/sub/deeper.ps1') {
                New-Item -ItemType File -Force -Path (Join-Path $t $rel) | Out-Null
            }
            # 'lib' and 'tests' are excluded by name ONE LEVEL DOWN only, so scripts/other/lib/ is IN.
            @(Get-Section28Population -Root $t | ForEach-Object Name | Sort-Object) |
                Should -Be @('inner.ps1', 'nested.ps1', 'shallow.ps1', 'top.ps1')
        }
    }
}

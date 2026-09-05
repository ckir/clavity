BeforeAll {
    $script:Checker = Join-Path (Split-Path -Parent $PSScriptRoot) 'check-capstone-new-code.ps1'

    # A throwaway git repo. NEVER run these fixtures against the clavity repo itself: a control run
    # in-repo gives a FALSE PASS because the real tree already satisfies most shapes under test.
    function New-Repo {
        $d = Join-Path ([System.IO.Path]::GetTempPath()) ("ccnc-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d | Out-Null
        Push-Location $d
        git init -q 2>&1 | Out-Null
        git config user.email t@t.t; git config user.name t
        git config commit.gpgsign false
        # FIXTURE HYGIENE - never inherit the host's settings. AGY-TEST-AUDIT 2026-09-05, Axiom Breaker,
        # and it was an INCONSISTENCY inside this repo rather than an abstract worry: the sibling fixture
        # at agy-mark.Tests.ps1:34 already pins core.autocrlf under exactly this comment, and this one
        # pinned neither setting.
        #
        # core.quotepath is LOAD-BEARING FOR THIS SUITE SPECIFICALLY. The whole `-z` story these rows
        # exist to pin is about git QUOTING paths that contain a space or non-ASCII byte, and quotepath is
        # the setting that governs it. A host with `core.quotepath=false` would silently change what these
        # rows exercise, so the suite would still pass while testing a different thing than it claims.
        git config core.quotepath true
        git config core.autocrlf false
        New-Item -ItemType Directory -Path (Join-Path $d 'src') | Out-Null
        Set-Content -Path (Join-Path $d 'src/seed.ps1') -Value "Write-Output 'seed'"
        git add src/seed.ps1 2>&1 | Out-Null
        git commit -qm seed 2>&1 | Out-Null
        Pop-Location
        return $d
    }

    function Invoke-Checker($Repo, $BaseRef) {
        Push-Location $Repo
        try {
            $out = & pwsh -NoProfile -File $script:Checker -BaseRef $BaseRef -Root $Repo 2>&1 | Out-String
            return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Out = $out }
        } finally { Pop-Location }
    }
}

Describe 'check-capstone-new-code' {

    It 'does NOT fire on a small edit inside an existing function' {
        $r = New-Repo
        try {
            Push-Location $r
            Add-Content -Path 'src/seed.ps1' -Value "Write-Output 'one more line'"
            git commit -qam edit 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 0 -Because 'a two-line edit is exactly what the dropped >10-lines clause used to false-positive on'
            $res.Out | Should -Not -Match 'TRIGGER'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a new non-test source file' {
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/brand-new.ps1' -Value "function New-Thing { 'x' }"
            git add src/brand-new.ps1 2>&1 | Out-Null
            git commit -qm add 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3
            $res.Out | Should -Match 'new-file'
            $res.Out | Should -Match 'src/brand-new\.ps1'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT fire on a new TEST file' {
        # THE NON-TEST CLAUSE IS THE ASSERTION. Without it the trigger fires on every round that
        # adds a pinning test, which is most of them, and the consult becomes noise the driver learns
        # to wave through.
        $r = New-Repo
        try {
            Push-Location $r
            New-Item -ItemType Directory -Path (Join-Path $r 'scripts/tests') -Force | Out-Null
            Set-Content -Path 'scripts/tests/thing.Tests.ps1' -Value "Describe 'x' { It 'y' { 1 | Should -Be 1 } }"
            git add scripts/tests/thing.Tests.ps1 2>&1 | Out-Null
            git commit -qm addtest 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a new function declaration added to an existing file' {
        # LEGITIMATELY CHANGED under the 2026-09-05 ast-grep engine swap (owner ruling). This row
        # originally used the New-Repo seed's OWN language, PowerShell, as its vehicle - but Rule B is
        # now ast-grep-backed and ast-grep has no PowerShell grammar (the owner-accepted gap; see the
        # dedicated RULE-B-SKIPPED row below). The row's INTENT - Rule B fires on a new declaration
        # added to an EXISTING file - is preserved by retargeting the vehicle to Python, a language
        # ast-grep does support, rather than deleting the row's coverage.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/mod.py' -Value 'def existing(): pass'
            git add src/mod.py 2>&1 | Out-Null; git commit -qm seedpy 2>&1 | Out-Null
            Add-Content -Path 'src/mod.py' -Value 'def get_census(): return 1'
            git commit -qam newfn 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3
            $res.Out | Should -Match 'new-declaration'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a new C# METHOD added to an existing class, not only on a new type' {
        # AGY-AFTER round 1, Mechanism Gamer. A types-only regex is blind to the most common unit of
        # new C# code, so an agent skips the consult by adding a method instead of a class.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/Thing.cs' -Value @('public class Thing', '{', '}')
            git add src/Thing.cs 2>&1 | Out-Null; git commit -qm cls 2>&1 | Out-Null
            Set-Content -Path 'src/Thing.cs' -Value @('public class Thing', '{', '    public void DoWork(int n)', '    {', '    }', '}')
            git commit -qam method 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3
            $res.Out | Should -Match 'new-declaration'
            $res.Out | Should -Match 'DoWork'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a C# CONSTRUCTOR, which carries no return type' {
        # AGY-AFTER round 2, Mechanism Gamer, attacking round 1's OWN FIX. The two-identifier method
        # pattern cannot see `public MyClass()`, so nesting the new logic in a constructor still
        # bypassed the trigger after fold 4. This row pins the constructor pattern specifically.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/Widget.cs' -Value @('public class Widget', '{', '}')
            git add src/Widget.cs 2>&1 | Out-Null; git commit -qm cls 2>&1 | Out-Null
            Set-Content -Path 'src/Widget.cs' -Value @('public class Widget', '{', '    public Widget(int n)', '    {', '    }', '}')
            git commit -qam ctor 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3 -Because 'a constructor is new executable code'
            $res.Out | Should -Match 'new-declaration'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'stays in sync when a two-path RENAME is interleaved with delete and modify' {
        # AGY-AFTER round 3, Assertion Strength Auditor, killed this row's PREVIOUS form as VACUOUS -
        # correctly. That version fed the parser a modify-only range, and `M` was handled even by the
        # broken parser, so it stayed green over the very defect it claimed to pin.
        #
        # MEASURED while folding: a commit-to-commit `git diff --name-status` emits only A/C/D/M/R/T.
        # U (unmerged) needs an index or worktree diff, X is a bug marker, B needs -B. The broken
        # parser handled ALL SIX, so the desync it was accused of is UNREACHABLE at this call site -
        # the exhaustive `else` is defensive, not a fix for a live bug, and this row must therefore
        # pin something that IS reachable rather than pretending otherwise.
        #
        # What IS reachable is a desync in the TWO-PATH branch: R consumes two entries, so a range
        # mixing R with single-path statuses is where an off-by-one actually bites. The deleted file
        # is named to start with 'A' so that any desync surfaces loudly as a phantom new-file hit.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/Aoriginal.ps1' -Value ("Write-Output 1`n" * 12)
            Set-Content -Path 'src/Adoomed.ps1'   -Value "Write-Output 2"
            Set-Content -Path 'src/keeper.ps1'    -Value "Write-Output 3"
            git add -A 2>&1 | Out-Null; git commit -qm seed2 2>&1 | Out-Null
            git mv src/Aoriginal.ps1 src/Amoved.ps1 2>&1 | Out-Null   # R: two paths
            git rm -q src/Adoomed.ps1 2>&1 | Out-Null                  # D: one path
            Add-Content -Path 'src/keeper.ps1' -Value "# touched"      # M: one path
            git commit -qam mixed 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            # The rename IS a new path, so the trigger fires - but on the RENAME only.
            $res.ExitCode | Should -Be 3
            $res.Out | Should -Match 'src/Amoved\.ps1'
            # AGY-AFTER round 4 (Assertion Strength Auditor) sharpened this. The obvious negatives -
            # "not Adoomed", "not keeper" - are nearly VACUOUS: under the desync mutant the parser
            # prints some OTHER token entirely, so those never appear and both assertions pass on
            # broken code. The negative that actually bites names the OLD side of the rename, because
            # dropping the first `$null = $nameStatus[++$i]` makes the parser report `Aoriginal`
            # instead of `Amoved` - that is the mutant, and this is the line that catches it.
            $res.Out | Should -Not -Match 'Aoriginal' -Because 'reporting the PRE-rename path means the two-path branch consumed the wrong entry'
            $res.Out | Should -Not -Match 'Adoomed'   -Because 'a DELETED file is not a new file, and Rule B must not report a RULE-B-SKIPPED line for it either - there is no content left to skip examining'
            # LEGITIMATELY CHANGED under the 2026-09-05 ast-grep engine swap (owner ruling): bare
            # 'keeper' now DOES appear in the output, in a RULE-B-SKIPPED line - Rule B is honest that
            # it could not examine the MODIFIED src/keeper.ps1 for a new declaration (PowerShell has no
            # ast-grep grammar), which is new, mandated transparency, not a regression. The assertion
            # that still matters - keeper must never be reported as NEW - is narrowed to the two rule
            # prefixes that would actually mean that.
            $res.Out | Should -Not -Match 'new-file[^\r\n]*keeper'        -Because 'a MODIFIED file is not a new file'
            $res.Out | Should -Not -Match 'new-declaration[^\r\n]*keeper' -Because 'a MODIFIED file is not a new file'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a file that arrives by RENAME, not only by plain add' {
        # AGY-AFTER round 1. '^A' alone misses R### and C### statuses, and a renamed file is a file
        # that now exists at a path where it did not before.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/original.ps1' -Value ("function Get-Body { 1 }`n" * 12)
            git add src/original.ps1 2>&1 | Out-Null; git commit -qm orig 2>&1 | Out-Null
            git mv src/original.ps1 src/renamed.ps1 2>&1 | Out-Null
            git commit -qm ren 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3
            $res.Out | Should -Match 'src/renamed\.ps1'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'handles a path containing a SPACE without letting it defeat the test-path exclusion' {
        # git QUOTES such paths in --name-status unless -z is used, and the quotes defeat the
        # anchored exclusion patterns. The peer flagged this as the one thing it could not judge
        # without running it; this row is the measurement.
        $r = New-Repo
        try {
            Push-Location $r
            New-Item -ItemType Directory -Path (Join-Path $r 'scripts/tests') -Force | Out-Null
            Set-Content -Path 'scripts/tests/my file.Tests.ps1' -Value "Describe 'x' { It 'y' { 1 | Should -Be 1 } }"
            git add -- 'scripts/tests/my file.Tests.ps1' 2>&1 | Out-Null
            git commit -qm spaced 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 0 -Because 'a spaced TEST path is still a test path'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'handles a space in a NON-TEST path - the row above cannot detect its own regression' {
        # AGY-TEST-AUDIT 2026-09-05, Mechanism Gamer. The row ABOVE was written to pin the `-z` handling
        # and CANNOT DETECT ITS OWN REGRESSION. MEASURED: remove `-z` from the --name-status call at
        # check-capstone-new-code.ps1:293 and revert to `-split '\s+'`, and the WHOLE SUITE stays green
        # at 31/0 - not one row notices.
        #
        # WHY, and it is the sharpest fixture lesson in this repo so far: that row's fixture is
        # `scripts/tests/my file.Tests.ps1`. Split on whitespace it becomes `scripts/tests/my`, which
        # STILL MATCHES the `(^|/)tests?/` exclusion - so the gate still concludes "test file, skip",
        # still exits 0, and the row still passes. THE FIXTURE'S TRUNCATED FRAGMENT GIVES THE SAME ANSWER
        # AS THE WHOLE PATH, so the assertion is blind to the truncation it exists to catch.
        #
        # A fixture must be chosen so that BREAKING THE PARSER CHANGES THE ANSWER. This row uses a
        # NON-TEST path with a space and a real declaration, which must FIRE (exit 3). Under the mutant
        # the path truncates to `src/my` - no code extension, no declaration - so Rule A goes silent and
        # the gate returns 0. Same defect, opposite direction, and THIS row sees it.
        $r = New-Repo
        try {
            Push-Location $r
            New-Item -ItemType Directory -Path (Join-Path $r 'src') -Force | Out-Null
            Set-Content -Path 'src/my file.ps1' -Value "function Get-Spaced { 1 }"
            git add -- 'src/my file.ps1' 2>&1 | Out-Null
            git commit -qm 'spaced non-test' 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3 -Because 'a spaced NON-TEST code path is new code and must fire; if this returns 0 the path parser has been truncated at the space'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'handles a filename with a LEADING DASH - it must not be read as an option' {
        # AGY-TEST-AUDIT 2026-09-05, Boundary Smuggler. MEASURED as CORRECT today (exit 3); this row pins
        # it against regression rather than reporting a defect.
        #
        # Why it is worth a row: this script ROUND-TRIPS a path read from git back INTO git, as
        # `git show "<ref>:<path>"`. A leading dash is the classic argument-injection shape for exactly
        # that pattern - a future refactor that drops the quoting, or passes the path as a bare argument,
        # turns `-leading.ps1` into an OPTION and the file silently vanishes from the scan. The gate would
        # then answer "no new code" for a commit that added a function, which is the fail-open direction
        # section 24 exists to prevent.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/-leading.ps1' -Value "function Get-Dashed { 1 }"
            git add -- 'src/-leading.ps1' 2>&1 | Out-Null
            git commit -qm dashed 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3 -Because 'a leading dash is part of the FILENAME, never an option; exit 0 means the path was consumed as a flag and the file went unscanned'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'handles a code file whose name COLLIDES with a git ref' {
        # AGY-TEST-AUDIT 2026-09-05, Boundary Smuggler. MEASURED as CORRECT today (exit 3).
        #
        # `git show "HEAD:src/HEAD.ps1"` is unambiguous only because the ref and the path sit on opposite
        # sides of the colon. A refactor that builds that argument differently - or drops the `<ref>:`
        # prefix - makes `HEAD` resolve as a REF instead of a path, and the file is read as a commit
        # object or not at all. Both failures are silent and both answer "no new code".
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/HEAD.ps1' -Value "function Get-RefNamed { 1 }"
            git add -- 'src/HEAD.ps1' 2>&1 | Out-Null
            git commit -qm refnamed 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3 -Because 'a file named HEAD is a PATH; if this returns 0 the name was resolved as a ref'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports the NEW DECLARATION as well as the rename when a detected rename adds one' {
        # AGY-TEST-AUDIT 2026-09-05. Rule B skipped the new side of a rename as "absent at base", so a
        # declaration added in the SAME commit was never reported - the reviewer saw one of two reasons.
        # The gate's DECISION was never wrong (Rule A fires on the rename either way); this is about what
        # the consult is told.
        #
        # THE FIXTURE MUST DEFEAT GIT'S SIMILARITY THRESHOLD, and that is the whole subtlety. My first
        # attempt renamed a 1-line file and appended a function: MEASURED, git scored it 48% and reported
        # D + A, NOT a rename - in which case `new-file` IS complete and nothing is missing. The filler
        # below keeps similarity at 96% so git actually emits `R096`, which is the only shape that hid
        # anything. A fixture that does not reproduce the trigger tests nothing.
        $r = New-Repo
        try {
            Push-Location $r
            $filler = (1..40 | ForEach-Object { "# filler $_" }) -join "`n"
            Set-Content -Path 'src/orig.ps1' -Value "function Existing { 1 }`n$filler"
            git add -- 'src/orig.ps1' 2>&1 | Out-Null
            git commit -qm 'large original' 2>&1 | Out-Null

            git mv 'src/orig.ps1' 'src/moved.ps1' 2>&1 | Out-Null
            Add-Content -Path 'src/moved.ps1' -Value "function Brand-New { 2 }"
            git add -A 2>&1 | Out-Null
            git commit -qm 'rename plus a new declaration' 2>&1 | Out-Null

            # Guard the fixture itself: if git did not DETECT the rename this row proves nothing.
            $status = (& git diff --name-status 'HEAD~1..HEAD') -join ' '
            $status | Should -Match '^R' -Because "the fixture must produce a DETECTED rename; git said: [$status]"
            Pop-Location

            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3
             $res.Out | Should -Match 'new-declaration.*Brand-New' -Because 'a declaration added alongside a rename must be reported, not hidden behind the rename line'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports EVERY rule that fired, not just the first' {
        # A checker that stops at the first hit under-reports the blast radius, and the driver then
        # consults on one shape while shipping two.
        #
        # LEGITIMATELY CHANGED under the 2026-09-05 ast-grep engine swap (owner ruling): the
        # new-declaration half of this row originally added a function to the New-Repo seed's OWN
        # PowerShell file, which Rule B can no longer see (the owner-accepted ast-grep gap). Retargeted
        # to Python, alongside the new-file .ps1 half unchanged, so both rules still fire together in
        # one range as the row's own name requires.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/mod.py' -Value 'def existing(): pass'
            git add src/mod.py 2>&1 | Out-Null; git commit -qm seedpy 2>&1 | Out-Null
            Set-Content -Path 'src/another.ps1' -Value "Write-Output 'a'"
            Add-Content -Path 'src/mod.py' -Value 'def get_second(): return 2'
            git add -A 2>&1 | Out-Null
            git commit -qm both 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3
            $res.Out | Should -Match 'new-file'
            $res.Out | Should -Match 'new-declaration'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'REFUSES a base ref that resolves to HEAD, rather than reporting a clean empty range' {
        # THE SKIP HOLE. The checker is mechanical, but its INPUT comes from the agent that would
        # benefit from skipping the consult. Handed HEAD it sees an empty diff and, without this
        # guard, returns exit 0 - handing that agent a clean bill of health as evidence.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/sneaky.ps1' -Value "function Get-Sneaky { 1 }"
            git add src/sneaky.ps1 2>&1 | Out-Null; git commit -qm sneak 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD'
            $res.ExitCode | Should -Be 2 -Because 'an empty range is an unanswerable question, not a negative answer'
            $res.Out | Should -Match 'resolves to HEAD'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits NON-ZERO and says so when the base ref does not exist' {
        # FAIL CLOSED. An unresolvable ref must never read as "no new code" - that is a guard
        # certifying exactly what it stopped checking.
        $r = New-Repo
        try {
            $res = Invoke-Checker $r 'no-such-ref-xyz'
            $res.ExitCode | Should -Be 2
            $res.Out | Should -Match 'could not resolve'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a modifier-less C# method added to an existing class' {
        # FIX 1, code-quality review 2026-09-04, verified by measurement. All five ORIGINAL
        # C#-related patterns require a literal access-modifier first token, so a modifier-less
        # declaration - legal, idiomatic C#, e.g. `static void Spawn(LaunchCommand cmd, bool wait)`
        # at clavity-dotnet/src/Clavity.Cli/Program.cs:117 - evaded every one of them. This row pins
        # the new C#-only, modifier-optional entry.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/Spawner.cs' -Value @('public class Spawner', '{', '}')
            git add src/Spawner.cs 2>&1 | Out-Null; git commit -qm cls 2>&1 | Out-Null
            Set-Content -Path 'src/Spawner.cs' -Value @('public class Spawner', '{', '    static void Spawn(int n)', '    {', '    }', '}')
            git commit -qam noaccessmod 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3 -Because 'a modifier-less method is still new executable C# code'
            $res.Out | Should -Match 'new-declaration'
            $res.Out | Should -Match 'Spawn'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT fire on a newly added package-lock.json' {
        # FIX 2, code-quality review 2026-09-04, verified by measurement. Rule A's --name-status
        # call had NO exclusions even though the comment above it always claimed generated and
        # vendored paths were excluded the same way Rules B/C exclude them - a first-time-added
        # package-lock.json fired `new-file`.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'package-lock.json' -Value '{"name": "x", "lockfileVersion": 3}'
            git add package-lock.json 2>&1 | Out-Null
            git commit -qm lock 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 0 -Because 'package-lock.json is excluded the same way Rules B/C exclude it'
            $res.Out | Should -Not -Match 'new-file'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a whole-function-rewrite that adds no new declaration' {
        # FIX 3, code-quality review 2026-09-04. Rule C - the ONLY defense against a "gut and
        # replace" edit that touches no declaration line - had ZERO test coverage before this row;
        # nothing would have caught its `-ge 5` threshold regressing (e.g. drifting to `-gt 5` or
        # any other boundary). The body below is replaced line-for-line (8 adds, 8 dels in one
        # hunk, git names the enclosing function in the @@ header) without touching the `function`
        # declaration line itself, so Rules A and B stay silent and only Rule C can fire.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/rewritten.ps1' -Value @(
                'function Get-Census {'
                '    param($x)'
                '    $a = 1'
                '    $b = 2'
                '    $c = 3'
                '    $d = 4'
                '    $e = 5'
                '    $f = 6'
                '    $g = 7'
                '    $h = 8'
                '    return $h'
                '}'
            )
            git add src/rewritten.ps1 2>&1 | Out-Null; git commit -qm seedfn 2>&1 | Out-Null
            Set-Content -Path 'src/rewritten.ps1' -Value @(
                'function Get-Census {'
                '    param($x)'
                '    $a = 11'
                '    $b = 22'
                '    $c = 33'
                '    $d = 44'
                '    $e = 55'
                '    $f = 66'
                '    $g = 77'
                '    $h = 88'
                '    return $h'
                '}'
            )
            git commit -qam rewrite 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3 -Because 'a whole-function-body rewrite is new logic even with no new declaration line'
            $res.Out | Should -Match 'whole-function-rewrite'
            $res.Out | Should -Match 'Get-Census'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT fire on a new documentation-only .md file' {
        # FIX 4, owner ruling 2026-09-04, verified by measurement. Section 24's own wording is
        # "NON-TEST shipped CODE" - a new markdown file is not code, and this repo tracks 264
        # markdown files and adds specs/roadmap sections/ledger rows constantly, so an unscoped
        # Rule A fires on documentation-only commits until the gate is noise the driver waves
        # through.
        $r = New-Repo
        try {
            Push-Location $r
            New-Item -ItemType Directory -Path (Join-Path $r 'docs') -Force | Out-Null
            Set-Content -Path 'docs/NOTES.md' -Value '# notes'
            git add -A 2>&1 | Out-Null
            git commit -qm docs 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 0 -Because 'a new .md file is documentation, not code'
            $res.Out | Should -Not -Match 'new-file'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'still FIRES on a new .ps1 file under the FIX 4 code-extension allow-list' {
        # FIX 4 companion row: the allow-list must admit ordinary shipped code, not just exclude
        # documentation. Pins that restricting Rule A to CODE extensions did not also silence it
        # on the extensions it is supposed to catch.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/allowed.ps1' -Value "Write-Output 'x'"
            git add src/allowed.ps1 2>&1 | Out-Null
            git commit -qm addps1 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3
            $res.Out | Should -Match 'new-file'
            $res.Out | Should -Match 'src/allowed\.ps1'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT fire on a docs-only change containing a declaration-shaped line' {
        # FIX 1, adversarial capstone round 2026-09-04 - the most important of the three, because it
        # violates an explicit owner ruling. Rule A was already restricted to CODE-extension paths
        # (FIX 4), but Rules B and C read the patch body of EVERY file regardless of extension, so a
        # brand-new README.md containing a declaration-shaped line (e.g. a code sample) still fired
        # the mandatory consult. MEASURED before the fix: exit 3, `new-declaration: README.md :
        # function Get-Thing { 1 }`.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'README.md' -Value @('# Notes', '', '```powershell', 'function Get-Thing { 1 }', '```')
            git add README.md 2>&1 | Out-Null
            git commit -qm docsample 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 0 -Because 'documentation must not fire the trigger even when it contains declaration-shaped text'
            $res.Out | Should -Not -Match 'TRIGGER'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a new declaration in a NON-ASCII-named file, not silently skipped' {
        # FIX 1, adversarial capstone round 2026-09-04, severity 0 SILENT BYPASS - the most important
        # of the four. git QUOTES a non-ASCII path in the +++ diff header (core.quotepath, on by
        # default) and C-escapes each non-ASCII byte as an octal triplet -
        # `+++ "b/src/caf\303\251.ps1"` for src/café.ps1 - MEASURED, matches exactly. The old regex
        # anchored on an UNQUOTED 'b/' never matched, so $currentFile was never updated,
        # $currentIsCode stayed false, and the FIX-4 code-extension guard skipped the file's added
        # lines entirely. MEASURED before this fix: exit 0, "no new code ... consult not required".
        #
        # LEGITIMATELY CHANGED under the 2026-09-05 ast-grep engine swap (owner ruling): retargeted
        # from .ps1 to .rs, since Rule B is now ast-grep-backed and PowerShell has no ast-grep grammar
        # (the owner-accepted gap). Retargeting this row SURFACED A REAL BUG rather than papering over
        # one: Rule B round-trips a path read from `git diff --name-only -z` back into `git show
        # "<ref>:<path>"` to materialise both versions, and MEASURED, under the default console
        # encoding a non-ASCII path corrupts on that round-trip (`git show` answered "fatal: path
        # 'src/caf├⌐.rs' does not exist") - silently treating the file as absent and reporting exit 0.
        # Fixed by setting [Console]::OutputEncoding to UTF8 near the top of the script; this row is
        # what pins that fix now that it exercises the AST-diff path rather than the old regex path.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/café.rs' -Value 'pub fn existing() {}' -Encoding utf8
            git add -- 'src/café.rs' 2>&1 | Out-Null
            git commit -qm addnonascii 2>&1 | Out-Null
            Add-Content -Path 'src/café.rs' -Value 'pub fn new_thing() {}'
            git commit -qam newfnnonascii 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3 -Because 'a non-ASCII path must not silently defeat Rule B either'
            $res.Out | Should -Match 'new-declaration'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a declaration added to an extensionless EXECUTABLE file (justfile), parsed as shell' {
        # 🔴 THIS ROW HAS NOW FLIPPED TWICE, and the history is the point - it is a live record of one
        # defect being fixed, silently regressed by a later fix, and restored:
        #   2026-09-04, capstone R2: extensionless executables became invisible when the code-extension
        #     allow-list shipped. This repo has a live 12KB justfile. FIXED - the row asserted exit 3.
        #   2026-09-05, ast-grep swap: REGRESSED. ast-grep's discovery is EXTENSION-keyed, so an
        #     extensionless file matched nothing and fell into RULE-B-SKIPPED. The row was flipped to
        #     assert the skip - honest at the time, but it recorded a coverage LOSS as if it were the
        #     intended design.
        #   2026-09-05, this row: RESTORED. MEASURED that the loss was never necessary - identical
        #     justfile content saved as `jf.sh` yields `{"NAME":{"text":"deploy"}}` from ast-grep's Bash
        #     grammar, while the same bytes with NO extension yield `[]`. The PARSE always worked; only
        #     the discovery failed. Rule B now writes the temp file with a .sh suffix for these names.
        #
        # ⚠ THE REGRESSION WAS ONLY VISIBLE BECAUSE THE SKIP PRINTS. Had RULE-B-SKIPPED been silent,
        # an earlier round's fix would have been quietly undone and this row would have been deleted as
        # obsolete rather than restored.
        #
        # Best-effort by nature: a justfile is not bash. Its recipe bodies and `f() {}` declarations are
        # shell-shaped, which is what this rule looks for.
        $r = New-Repo
        try {
            Push-Location $r
            # `already_there` is a Bash function present AT BASE - it is the control for the baseline
            # negative assertion below, and without it that assertion cannot bite.
            Set-Content -Path 'justfile' -Value @('build:', '    echo build', '', 'already_there() {', '  echo old', '}')
            git add justfile 2>&1 | Out-Null; git commit -qm addjustfile 2>&1 | Out-Null
            Add-Content -Path 'justfile' -Value @('', 'deploy() {', '  echo deploy', '}')
            git commit -qam newfnjustfile 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3 -Because 'an extensionless executable is parsed as shell, so a new function in it is new code'
            $res.Out | Should -Match 'new-declaration[^\r\n]*deploy'
            $res.Out | Should -Not -Match 'RULE-B-SKIPPED[^\r\n]*justfile' -Because 'it is examined now, not skipped'
            # BASELINE NEGATIVE (capstone R4, Assertion Strength Auditor). Without this the row cannot
            # tell working set-diffing from a base side that came back EMPTY: if `git show <base>:path`
            # failed and yielded no names, EVERY head declaration would report as new and this row would
            # still pass. `already_there` exists at base, so seeing it reported as new proves the base
            # side collapsed rather than diffed.
            $res.Out | Should -Not -Match 'new-declaration[^\r\n]*already_there' -Because 'a declaration present at base is not new - if it reports, the base side returned empty'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is PARTIAL, not complete, on a build file - a recipe target is NOT covered and says so' {
        # 🔴 THE DRIVER OVERSTATED THE EARLIER FIX, AND THIS ROW RECORDS THE CORRECTION. Capstone R4.
        # MEASURED: adding a normal recipe - `deploy:` followed by an indented line - to a justfile
        # returns exit 0. ast-grep's Bash grammar sees `f() {}` functions; a recipe target is not a
        # function_definition. Recipes are the ORDINARY way to add work to a justfile or Makefile, so
        # the coverage restored earlier was the narrower half.
        #
        # Before that fix these files printed RULE-B-SKIPPED - an HONEST miss. Parsing them as shell
        # without saying so made it a SILENT one. The gate now announces RULE-B-PARTIAL on every run
        # for these files, so a reader is told which half was examined.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'justfile' -Value @('build:', '    echo build')
            git add justfile 2>&1 | Out-Null; git commit -qm addjustfile 2>&1 | Out-Null
            Add-Content -Path 'justfile' -Value @('', 'deploy:', '    echo deploy')
            git commit -qam newrecipe 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 0 -Because 'the Bash grammar cannot see a recipe target - this is the stated limit, not a claim of coverage'
            $res.Out | Should -Match 'RULE-B-PARTIAL[^\r\n]*justfile' -Because 'a half-understood file must announce that, exactly as a skipped one does'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a C# auto-property, which carries no parentheses at all' {
        # FIX 3, adversarial capstone round 2026-09-04. All five ORIGINAL C#-only patterns require a
        # trailing '(', and `public string Name { get; set; }` has none. MEASURED before this fix:
        # exit 0.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/Thing.cs' -Value @('public class Thing', '{', '}')
            git add src/Thing.cs 2>&1 | Out-Null; git commit -qm cls 2>&1 | Out-Null
            Set-Content -Path 'src/Thing.cs' -Value @('public class Thing', '{', '    public string Name { get; set; }', '}')
            git commit -qam prop 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3 -Because 'an auto-property is new executable C# surface'
            $res.Out | Should -Match 'new-declaration'
            $res.Out | Should -Match 'Name'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a Rust TYPE-only addition with no fn anywhere in the diff' {
        # FIX 2, adversarial capstone round 2026-09-04. The Rust declaration pattern was
        # function-only, so a new `pub struct`/`pub enum` addition with no `fn` bypassed the
        # trigger entirely - unlike C#, whose patterns already cover
        # class/record/struct/interface/enum. MEASURED before the fix: exit 0, "no new code".
        # STILL PINS ast-grep's Rust `struct_item` kind after the 2026-09-05 engine swap: it fires
        # via the same `kind: struct_item, has: {field: name}` rule regardless of a `pub` prefix.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/lib.rs' -Value 'pub fn existing() {}'
            git add src/lib.rs 2>&1 | Out-Null; git commit -qm seedrs 2>&1 | Out-Null
            Set-Content -Path 'src/lib.rs' -Value @(
                'pub fn existing() {}'
                ''
                'pub struct Config {'
                '    pub name: String,'
                '}'
            )
            git commit -qam addtype 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3 -Because 'a new Rust type declaration is new shipped code even with no new fn'
            $res.Out | Should -Match 'new-declaration'
            $res.Out | Should -Match 'Config'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a Python `async def`, covered automatically by the ast-grep rewrite' {
        # Owner ruling 2026-09-05: `async def` is covered automatically by ast-grep's Python
        # `function_definition` kind - MEASURED, one kind matches both `def` and `async def` - so no
        # separate pattern was added for it. This row is the verification the ruling asked for.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/mod.py' -Value 'def existing(): pass'
            git add src/mod.py 2>&1 | Out-Null; git commit -qm seedpy 2>&1 | Out-Null
            Set-Content -Path 'src/mod.py' -Value @(
                'def existing(): pass'
                ''
                'async def do_async():'
                '    pass'
            )
            git commit -qam addasync 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3 -Because 'a new async def is new shipped Python code'
            $res.Out | Should -Match 'new-declaration'
            $res.Out | Should -Match 'do_async'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT skip a .ps1 file - the native PowerShell parser covers it' {
        # 🔴 THIS ROW ASSERTED THE OPPOSITE UNTIL 2026-09-05, and the change is an OWNER RULING, not a
        # weakened test. It used to pin the PowerShell gap as accepted-but-loud: ast-grep has no
        # PowerShell grammar (MEASURED, `--lang powershell` answers "powershell is not supported!"),
        # so Rule B skipped .ps1 and merely SAID so.
        #
        # That gap was then closed rather than accepted, after an AGY-FIRST consult returned
        # [VERDICT: ALIGNED]: PowerShell ships its own parser in the runtime this script already runs
        # in, so Rule B uses [System.Management.Automation.Language.Parser] for .ps1 - a true AST, and
        # no new dependency. The deciding fact was that the gate script is ITSELF 18.7KB of non-test
        # PowerShell, so the old behaviour meant a new function appended to the gate's own source
        # returned exit 0 - MEASURED - and the gate could be silently disabled.
        #
        # A small NON-declaration edit still fires nothing (Rule A needs a new file, Rule C needs a
        # whole-function rewrite), so exit 0 is still correct here. What must NOT appear any more is a
        # skip line naming a .ps1 file: Rule B examined it and found no new declaration, which is a
        # different and much stronger statement than "could not look".
        $r = New-Repo
        try {
            Push-Location $r
            Add-Content -Path 'src/seed.ps1' -Value "Write-Output 'one more line'"
            git commit -qam edit 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 0
            $res.Out | Should -Not -Match 'RULE-B-SKIPPED[^\r\n]*seed\.ps1' -Because 'the native parser covers .ps1, so it is examined rather than skipped'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'PROVES .ps1 is actually examined, not merely un-skipped' {
        # 🔴 THE ROW ABOVE IS VACUOUS ON ITS OWN, AND THIS ROW EXISTS BECAUSE OF THAT. Capstone R4,
        # Assertion Strength Auditor, attacking a test the DRIVER had written to prove its own fix.
        # MEASURED: drop '.ps1' from $CodeExtensions and the checker returns exit 0 with ZERO
        # RULE-B-SKIPPED lines - which is EXACTLY what the row above asserts. It passes while .ps1 is
        # completely unexamined, certifying the silent bypass it was written to exclude.
        #
        # SILENCE IS NOT PROOF OF SCANNING; it is also the symptom of not looking. The only thing that
        # proves examination is a POSITIVE result from the same engine on the same file type, so this
        # row adds a declaration and requires the trigger to fire. Under that same mutant this row
        # goes red, which is what makes the pair non-vacuous.
        $r = New-Repo
        try {
            Push-Location $r
            Add-Content -Path 'src/seed.ps1' -Value "function Proof-OfExamination { 42 }"
            git commit -qam proof 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3 -Because 'a positive fire is the only evidence the file was parsed at all'
            $res.Out | Should -Match 'new-declaration[^\r\n]*Proof-OfExamination'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a new function added to an existing .ps1 file, via the native PowerShell AST' {
        # The behaviour the ruling bought, and the case that matters most: the gate script and every
        # non-test script in scripts/ are PowerShell. MEASURED before the fix, this returned exit 0.
        $r = New-Repo
        try {
            Push-Location $r
            Add-Content -Path 'src/seed.ps1' -Value "function New-Thing { 1 }"
            git commit -qam addfn 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3
            $res.Out | Should -Match 'new-declaration[^\r\n]*New-Thing'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES on a PowerShell class, not only on a function' {
        # TypeDefinitionAst, not FunctionDefinitionAst - a separate node type, and a separate way to
        # add executable code to a .ps1 file. Keyed on (kind, name) so a `class Foo` and a
        # `function Foo` cannot collapse into one entry.
        $r = New-Repo
        try {
            Push-Location $r
            Add-Content -Path 'src/seed.ps1' -Value 'class Widget { [int]$n }'
            git commit -qam addclass 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 3
            $res.Out | Should -Match 'new-declaration[^\r\n]*Widget'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT fire on a function added to a .ps1 TEST file' {
        # The test exclusion must survive the engine change - new tests are not supposed to demand a
        # design consult, in PowerShell exactly as in every other language.
        $r = New-Repo
        try {
            Push-Location $r
            New-Item -ItemType Directory -Path (Join-Path $r 'scripts/tests') -Force | Out-Null
            Set-Content -Path 'scripts/tests/thing.Tests.ps1' -Value "Describe 'x' { It 'y' { 1 | Should -Be 1 } }"
            git add -- 'scripts/tests/thing.Tests.ps1' 2>&1 | Out-Null
            git commit -qm addtest 2>&1 | Out-Null
            Add-Content -Path 'scripts/tests/thing.Tests.ps1' -Value "function Helper { 1 }"
            git commit -qam addfn 2>&1 | Out-Null
            Pop-Location
            $res = Invoke-Checker $r 'HEAD~1'
            $res.ExitCode | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 2 when ast-grep is not on PATH, rather than silently answering no new code' {
        # FAIL CLOSED (owner ruling). Rule B cannot run without ast-grep, and a gate an agent runs on
        # itself must never fail toward silence. Simulated by restricting PATH to just what pwsh and
        # git need, deliberately excluding ast-grep's directory.
        $r = New-Repo
        try {
            Push-Location $r
            Add-Content -Path 'src/seed.ps1' -Value "Write-Output 'x'"
            git commit -qam edit 2>&1 | Out-Null
            Pop-Location
            $pwshDir = Split-Path -Parent (Get-Command pwsh).Source
            $gitDir = Split-Path -Parent (Get-Command git).Source
            $savedPath = $env:PATH
            try {
                $env:PATH = "$pwshDir;$gitDir;$env:SystemRoot;$env:SystemRoot\System32"
                $res = Invoke-Checker $r 'HEAD~1'
            } finally {
                $env:PATH = $savedPath
            }
            $res.ExitCode | Should -Be 2 -Because 'ast-grep missing must fail closed, never silently answer no new code'
            $res.Out | Should -Match 'ast-grep is not on PATH'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 2 when ast-grep is PRESENT but FAILS, rather than reading its silence as no new code' {
        # A MISSING dependency was already handled; a BROKEN one was not, and that is the worse case
        # because the binary is right there. Capstone R5, and it overturned a DISPOSITION of mine: I had
        # ruled tree-sitter grammar drift "not severity 0, because no command exits non-zero today".
        # MEASURED, that was wrong - `ast-grep scan` with an invalid kind exits 8:
        #     Kind `nonexistent_kind` is invalid.
        # The script sent stderr to $null and returned an EMPTY name set on any failure, and an empty
        # set is indistinguishable from "this file declares nothing" - so every declaration looked
        # unchanged and the gate answered "no new code". FAIL-OPEN, in a gate an agent runs on itself.
        #
        # Simulated with a shim named ast-grep that exits non-zero, placed FIRST on PATH. That is the
        # honest simulation of a grammar bump: the binary exists, runs, and fails.
        $r = New-Repo
        $shim = Join-Path ([System.IO.Path]::GetTempPath()) ("agshim-" + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $shim -Force | Out-Null
            Set-Content -Path (Join-Path $shim 'ast-grep.cmd') -Value @('@echo off', 'exit /b 8')
            Push-Location $r
            New-Item -ItemType Directory -Path (Join-Path $r 'src') -Force | Out-Null
            Set-Content -Path 'src/T.cs' -Value @('public class T', '{', '}')
            git add -- 'src/T.cs' 2>&1 | Out-Null; git commit -qm addcs 2>&1 | Out-Null
            Set-Content -Path 'src/T.cs' -Value @('public class T', '{', '    public void Go() { }', '}')
            git commit -qam addmethod 2>&1 | Out-Null
            Pop-Location
            $savedPath = $env:PATH
            try {
                $env:PATH = "$shim;$env:PATH"
                $res = Invoke-Checker $r 'HEAD~1'
            } finally { $env:PATH = $savedPath }
            $res.ExitCode | Should -Be 2 -Because 'an ast-grep that FAILS has not answered the question, and an unanswered question is not a no'
            $res.Out | Should -Match 'ast-grep exited'
        } finally {
            Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $shim -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

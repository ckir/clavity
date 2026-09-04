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
        $r = New-Repo
        try {
            Push-Location $r
            Add-Content -Path 'src/seed.ps1' -Value "function Get-Census { param(`$p) return 1 }"
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
            $res.Out | Should -Not -Match 'Adoomed'   -Because 'a DELETED file is not a new file'
            $res.Out | Should -Not -Match 'keeper'    -Because 'a MODIFIED file is not a new file'
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

    It 'reports EVERY rule that fired, not just the first' {
        # A checker that stops at the first hit under-reports the blast radius, and the driver then
        # consults on one shape while shipping two.
        $r = New-Repo
        try {
            Push-Location $r
            Set-Content -Path 'src/another.ps1' -Value "Write-Output 'a'"
            Add-Content -Path 'src/seed.ps1' -Value "function Get-Second { return 2 }"
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
}

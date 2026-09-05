BeforeAll {
    $script:Mark = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'clavity-dotnet/plugin/hooks/agy-mark.sh'

    function New-Repo {
        $d = Join-Path ([System.IO.Path]::GetTempPath()) ("mstamp-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d | Out-Null
        Push-Location $d
        git init -q 2>&1 | Out-Null
        git config user.email t@t.t; git config user.name t; git config commit.gpgsign false
        Set-Content -Path (Join-Path $d 'f.txt') -Value 'x'
        git add f.txt 2>&1 | Out-Null; git commit -qm seed 2>&1 | Out-Null
        Pop-Location
        return $d
    }

    function Invoke-Stamp($Repo, [string[]]$MarkArgs) {
        Push-Location $Repo
        try {
            $out = & bash $script:Mark @MarkArgs 2>&1 | Out-String
            return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Out = $out }
        } finally { Pop-Location }
    }
}

Describe 'agy-mark.sh stamp' {

    It 'records SHARED-CONTEXT when the consult and review cascade ids are equal' {
        $r = New-Repo
        try {
            $res = Invoke-Stamp $r @('stamp','agy-capstone','cascade-aaa','cascade-aaa')
            $res.ExitCode | Should -Be 0
            $log = Get-Content (Join-Path $r '.clavity/agy-marks/consults.log') -Raw
            $log | Should -Match 'SHARED-CONTEXT'
            $log | Should -Not -Match 'ISOLATED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'records ISOLATED when the two cascade ids differ' {
        $r = New-Repo
        try {
            $res = Invoke-Stamp $r @('stamp','agy-capstone','cascade-aaa','cascade-bbb')
            $res.ExitCode | Should -Be 0
            $log = Get-Content (Join-Path $r '.clavity/agy-marks/consults.log') -Raw
            $log | Should -Match 'ISOLATED'
            $log | Should -Not -Match 'SHARED-CONTEXT'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is APPEND-ONLY - a second stamp does not destroy the first' {
        # The log is evidence. A writer that truncates turns an audit trail into a single data point,
        # and this repo has already been bitten by a '>' where a '>>' belonged.
        $r = New-Repo
        try {
            Invoke-Stamp $r @('stamp','agy-capstone','c1','c1') | Out-Null
            Invoke-Stamp $r @('stamp','agy-test-audit','c2','c3') | Out-Null
            $lines = @(Get-Content (Join-Path $r '.clavity/agy-marks/consults.log') | Where-Object { $_ -match 'consult=' })
            $lines.Count | Should -Be 2
            ($lines -join "`n") | Should -Match 'agy-capstone'
            ($lines -join "`n") | Should -Match 'agy-test-audit'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'NEVER exits non-zero on a shared context - it records, it does not gate' {
        # The owner's ruling is explicit: recording isolation must never block. A stamp that failed
        # the build on SHARED-CONTEXT would recreate exactly the skip-pressure section 24 removes.
        $r = New-Repo
        try {
            $res = Invoke-Stamp $r @('stamp','agy-capstone','same','same')
            $res.ExitCode | Should -Be 0 -Because 'the stamp is a record, never a gate'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects a call with missing arguments rather than writing a malformed row' {
        $r = New-Repo
        try {
            $res = Invoke-Stamp $r @('stamp','agy-capstone','only-one-id')
            $res.ExitCode | Should -Not -Be 0
            Test-Path (Join-Path $r '.clavity/agy-marks/consults.log') | Should -BeFalse
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects a consult-cascade-id containing whitespace, and writes NO row' {
        # FIX 3 (script) / FIX 4 (this test), adversarial capstone round 2026-09-04. A cascade id
        # containing whitespace corrupted the log line's POSITIONAL fields - a reader parsing field 5
        # as the isolation token read a fragment of the id instead. MEASURED before the script fix:
        # exit 0, and the corrupted row landed in consults.log.
        #
        # SPLIT FROM A SINGLE COMBINED ROW that put spaces in BOTH ids: the script checks consult_id
        # BEFORE review_id and exits 64 on the first failure, so that one row proved nothing about the
        # review_id check on its own - deleting the review_id check entirely left the combined row
        # green. This row isolates the consult_id check with a GOOD review_id alongside it.
        $r = New-Repo
        try {
            $res = Invoke-Stamp $r @('stamp','agy-capstone','id with spaces','good-review-id')
            $res.ExitCode | Should -Not -Be 0
            Test-Path (Join-Path $r '.clavity/agy-marks/consults.log') | Should -BeFalse
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects a review-cascade-id containing whitespace, and writes NO row' {
        # FIX 4, adversarial capstone round 2026-09-04. Isolates the review_id check specifically -
        # see the row above for why a single row with spaces in both ids proved nothing about this
        # half. A GOOD consult_id alongside it means only the review_id check can be what fires.
        $r = New-Repo
        try {
            $res = Invoke-Stamp $r @('stamp','agy-capstone','good-consult-id','id with spaces')
            $res.ExitCode | Should -Not -Be 0
            Test-Path (Join-Path $r '.clavity/agy-marks/consults.log') | Should -BeFalse
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'ASSERTS THE .clavity SHIELD when it is the FIRST agy-mark call in a fresh repo' {
        # Capstone R7 put this below its reachability floor, reasoning that stamp writes only a
        # "non-load-bearing audit file" and so cannot mutate protected configuration. That answers a
        # path-traversal threat; agy_shield's Stage A2 is a DATA-LEAK guard - it asserts
        # `.clavity/.gitignore` contains `*` so nothing under .clavity/ can be committed to a PUBLIC
        # repository. stamp was the ONLY arm not calling it.
        #
        # THE ASSERTION IS ON GIT'S VIEW, not on the file's existence, because git's view is the
        # actual harm: cascade ids, disciplines and HEAD shas landing in a committable directory.
        # MEASURED before the fix: shield ABSENT and `?? .clavity/` in porcelain output.
        # This must be the FIRST call in the repo - any earlier shielded arm would create the shield
        # and this row would pass against an unfixed stamp. That is also why it cannot be tested in
        # the clavity repository itself, whose shield already exists.
        $r = New-Repo
        try {
            $res = Invoke-Stamp $r @('stamp','agy-capstone','cascade-aaa','cascade-bbb')
            $res.ExitCode | Should -Be 0
            Get-Content (Join-Path $r '.clavity/.gitignore') -Raw | Should -Match '\*'

            Push-Location $r
            try { $porcelain = (& git status --porcelain 2>&1 | Out-String).Trim() } finally { Pop-Location }
            $porcelain | Should -BeExactly '' -Because "stamp must leave nothing under .clavity/ visible to git, got: [$porcelain]"
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'REPAIRS a shield that was removed, rather than writing under a broken one' {
        # The ordering half of the same defect, measured separately: before the fix a later stamp did
        # NOT restore a deleted shield, though every other arm does. A row asserting only the
        # fresh-repo case would stay green against a stamp that shields once and never re-checks.
        $r = New-Repo
        try {
            Invoke-Stamp $r @('stamp','agy-capstone','cascade-aaa','cascade-bbb') | Out-Null
            Remove-Item (Join-Path $r '.clavity/.gitignore') -Force

            $res = Invoke-Stamp $r @('stamp','agy-capstone','cascade-ccc','cascade-ddd')
            $res.ExitCode | Should -Be 0
            Test-Path (Join-Path $r '.clavity/.gitignore') | Should -BeTrue
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

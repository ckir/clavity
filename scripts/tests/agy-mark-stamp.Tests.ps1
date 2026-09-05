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
            # THE SUCCESS PATH OF THE TIMESTAMP LIVES HERE. Capstone R8, Test Vacuity Hunter, and it was
            # RIGHT: the dedicated timestamp row below exercises only the FAILURE path and accepts the
            # literal `unknown`, so hardcoding `_ts=unknown` in the stamp arm left the WHOLE SUITE GREEN
            # at 10/0 - MEASURED. A fallback row without a success-path row certifies the fallback and
            # nothing else. Asserted here rather than in a new row because this row already performs an
            # ordinary, unshimmed stamp - the success path is a property of it.
            ($log -split ' ')[0] | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -Because "an ordinary run must record a REAL timestamp, not the 'unknown' fallback, got row: [$log]"
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

    It 'keeps the timestamp field NON-EMPTY when date fails, so no positional field shifts' {
        # Capstone R7 stood this down below the floor ("simply leaves the first field empty without
        # breaking the positional contract"); asked which reader it had checked it answered NONE and
        # retracted. MEASURED with a date shim exiting 1: field1 became the discipline and field2 became
        # `consult=<id>` - every field shifted by one, while the arm still exited 0.
        #
        # THE ASSERTION IS ON FIELD IDENTITY, NOT ON A COUNT and not on the row merely existing. A count
        # is invariant under the shift this pins - the corrupt row has the same number of fields as the
        # good one, which is exactly what makes the corruption silent.
        $r = New-Repo
        try {
            # THE SHIM MUST BE PREPENDED IN BASH'S OWN IDIOM, NOT POWERSHELL'S, and the first version of
            # this row got that wrong in a way that made it VACUOUS. Setting $env:PATH = "$shim;$old"
            # hands bash a SEMICOLON-separated list; bash splits PATH on COLONS, so the shim directory
            # was never on the search path, the real `date` ran, and the row passed against a deliberately
            # mutated script. Caught only because the mutant left the suite 10/0 GREEN.
            # The PATH is therefore built inside bash, where `:` is correct and `$PATH` is bash's own.
            $shim = Join-Path $r 'shim'
            New-Item -ItemType Directory -Path $shim | Out-Null
            Set-Content -Path (Join-Path $shim 'date') -Value "#!/bin/sh`nexit 1" -NoNewline

            Push-Location $r
            try {
                & bash -c 'PATH="./shim:$PATH" bash "$1" stamp agy-capstone cascade-aaa cascade-bbb' _ $script:Mark 2>&1 | Out-Null
                $code = $LASTEXITCODE
            } finally { Pop-Location }

            $code | Should -Be 0 -Because 'a degraded clock must still not gate the record'
            $row = (Get-Content (Join-Path $r '.clavity/agy-marks/consults.log') | Select-Object -First 1)

            # DO NOT SPLIT ON '\s+' HERE. The second version of this row did, and it was VACUOUS for a
            # subtler reason than the first: on the corrupt row " agy-capstone consult=..." PowerShell's
            # -split '\s+' emits an EMPTY leading element, which shifts every later field back into the
            # exact index the good row puts it at. Good and corrupt rows produced identical $fields[1..4],
            # so the assertions passed against the mutant. The matcher normalised away the one difference
            # it existed to detect - the same class as asserting a COUNT over a reordered collection.
            # Assert on the RAW row instead: the defect IS the leading whitespace and the absent field.
            $row | Should -Not -Match '^\s' -Because "the row must not begin with whitespace, got: [$row]"
            $first = ($row -split ' ')[0]
            $first | Should -Not -BeNullOrEmpty -Because "field 1 must be present, got row: [$row]"
            $first | Should -Match '^(unknown|\d{4}-\d{2}-\d{2}T)' -Because "field 1 must be a timestamp or the explicit 'unknown' fallback, got: [$first]"
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
            # ASSERT THE CONTENT, NOT MERE EXISTENCE. Capstone R8, Test Vacuity Hunter, and it was RIGHT:
            # this row asserted only `Test-Path`, so replacing the agy_shield call with a bare `touch`
            # left an EMPTY .gitignore and the row still PASSED while the repository was exposed.
            # MEASURED: that mutant reddened the fresh-repo row above (it checks content) and left THIS
            # row green - which is why the same mutant must be judged per-row, never per-suite.
            $shield = Get-Content (Join-Path $r '.clavity/.gitignore') -Raw
            $shield | Should -Match '\*' -Because "a repaired shield must actually contain the ignore-all pattern, got: [$shield]"
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

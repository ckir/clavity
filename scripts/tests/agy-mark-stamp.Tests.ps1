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
}

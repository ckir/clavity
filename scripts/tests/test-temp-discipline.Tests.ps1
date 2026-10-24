<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

# No suite may reach for the system temp directory directly: scratch goes through scripts/tests/TestTemp.ps1 so a killed
# run orphans files under ONE swept parent. The two EXEMPT sites are listed below, each with its reason.
BeforeAll {
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).ProviderPath
    $script:Suites = @(
        Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'scripts' 'tests') -Filter '*.Tests.ps1' -File
        Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'clavity-dotnet' 'install') -Filter '*.Tests.ps1' -File -ErrorAction SilentlyContinue
    ) | Where-Object { $_.Name -ne 'test-temp-discipline.Tests.ps1' -and $_.Name -ne 'TestTemp.Tests.ps1' }
    # file -> the EXACT trimmed line -> reason. The whole line, not a fragment: a fragment would let a second GetTempPath() on the SAME line
    # ride the exemption (panel round 1); not a line number, so an ordinary edit cannot move it out of coverage.
    $script:Exempt = @(
        @{ File = 'agy-shield-lib.Tests.ps1'; Line = '$script:MarkerDir = [IO.Path]::GetTempPath()'; Reason = 'the SYSTEM temp directory is the subject under test: the shield library writes its markers into ${TMPDIR:-/tmp}, and the suite snapshots and diffs exactly that directory to clean up what it caused' }
        @{ File = 'check-cheatsheet-parity.Tests.ps1'; Line = '$before = @(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Filter ''cheatsheet-parity-*'' -ErrorAction SilentlyContinue).Count'; Reason = 'the script under test (scripts/check-cheatsheet-parity.ps1) creates its temp files in the SYSTEM temp itself; the row counts survivors there, so pointing it at the shared root would make it vacuous' }
        @{ File = 'check-cheatsheet-parity.Tests.ps1'; Line = '@(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Filter ''cheatsheet-parity-*'' -ErrorAction SilentlyContinue).Count |'; Reason = 'the script under test (scripts/check-cheatsheet-parity.ps1) creates its temp files in the SYSTEM temp itself; the row counts survivors there, so pointing it at the shared root would make it vacuous' }
    )
    # IgnoreCase: PowerShell environment-variable names are case-insensitive, so `$env:Temp` is the same hole as `$env:TEMP`
    # (measured: no lowercase spelling exists today - 58 suites / 222 lines either way - so this closes a latent evasion).
    $script:Direct = [regex]::new('GetTempPath\s*\(|\$env:TEMP\b|\$env:TMP\b|\[Environment\]::GetEnvironmentVariable\(\s*[''"]TEMP', 'IgnoreCase')
}
Describe 'test temp discipline' {
    It 'found a plausible population of suites' { $script:Suites.Count | Should -BeGreaterThan 60 }
    It 'no suite uses the system temp directory directly, except the named exemptions' {
        $bad = foreach ($s in $script:Suites) {
            $n = 0
            foreach ($l in [IO.File]::ReadAllLines($s.FullName)) {
                $n++
                if ($l.TrimStart().StartsWith('#') -or -not $script:Direct.IsMatch($l)) { continue }
                $ex = @($script:Exempt | Where-Object { $_.File -eq $s.Name -and $l.Trim() -ceq $_.Line })
                if ($ex.Count -eq 0) { "$($s.Name):$n  $($l.Trim())" }
            }
        }
        $bad -join "`n" | Should -BeExactly '' -Because 'route scratch through New-TestTempPath / Get-TestTempRoot (scripts/tests/TestTemp.ps1)'
    }
    It 'every exemption still matches a real line (a stale exemption is a hole)' {
        foreach ($e in $script:Exempt) {
            $hit = [IO.File]::ReadAllLines((Join-Path $script:RepoRoot 'scripts' 'tests' $e.File)) | Where-Object { $_.Trim() -ceq $e.Line }
            @($hit).Count | Should -BeGreaterThan 0 -Because "exemption line '$($e.Line)' in $($e.File) must still exist"
        }
    }
    It 'every suite that uses New-TestTempPath or Get-TestTempRoot can reach TestTemp.ps1' {
        $missing = foreach ($s in $script:Suites) {
            $t = [IO.File]::ReadAllText($s.FullName)
            if ($t -match 'New-TestTempPath|Get-TestTempRoot|Remove-TestPath' -and $t -notmatch 'TestTemp\.ps1|BashHookHelpers\.ps1') { $s.Name }
        }
        $missing -join ', ' | Should -BeExactly ''
    }
}

BeforeAll { . (Join-Path $PSScriptRoot 'TestTemp.ps1') }
Describe 'Remove-TestPath' {
    It 'removes existing paths and tolerates $null elements without throwing' {
        $d = Join-Path $TestDrive 'a'; New-Item -ItemType Directory $d | Out-Null
        { Remove-TestPath $null, $d } | Should -Not -Throw
        Test-Path $d | Should -BeFalse
    }
    It 'tolerates ALL-null and empty input (the case Remove-Item itself throws on)' {
        { Remove-TestPath $null, $null } | Should -Not -Throw
        { Remove-TestPath @() } | Should -Not -Throw
        { Remove-TestPath } | Should -Not -Throw
    }
    It 'tolerates a path that does not exist' { { Remove-TestPath (Join-Path $TestDrive 'nope') } | Should -Not -Throw }
    It 'removes a FILE as well as a directory' {
        $f = Join-Path $TestDrive 'f.txt'; 'x' | Set-Content $f
        Remove-TestPath $f; Test-Path $f | Should -BeFalse
    }
    It 'is the shape a failed second allocation needs: the first handle is still cleaned' {
        $a = $null; $b = $null
        try { $a = Join-Path $TestDrive 'first'; New-Item -ItemType Directory $a | Out-Null; throw 'second allocation failed' }
        catch { } finally { Remove-TestPath $a, $b }
        Test-Path (Join-Path $TestDrive 'first') | Should -BeFalse
    }
}

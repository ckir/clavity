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

Describe 'the shared test temp root' {
    BeforeAll { $script:Saved = $env:CLAVITY_TEST_TEMP_ROOT; $env:CLAVITY_TEST_TEMP_ROOT = Join-Path $TestDrive 'root' }
    AfterAll  { if ($null -eq $script:Saved) { Remove-Item Env:CLAVITY_TEST_TEMP_ROOT -ErrorAction SilentlyContinue } else { $env:CLAVITY_TEST_TEMP_ROOT = $script:Saved } }
    It 'Get-TestTempRoot honours the override and creates the directory' {
        (Get-TestTempRoot) | Should -Be (Join-Path $TestDrive 'root'); Test-Path (Get-TestTempRoot) | Should -BeTrue
    }
    It 'New-TestTempPath returns a unique path UNDER the root, prefixed, and does not create it' {
        $a = New-TestTempPath 'abc'; $b = New-TestTempPath 'abc'
        $a | Should -Not -Be $b
        $a | Should -BeLike (Join-Path (Get-TestTempRoot) 'abc-*')
        Test-Path $a | Should -BeFalse
    }
    It 'the sweep removes children older than the age and KEEPS younger ones' {
        $old = Join-Path (Get-TestTempRoot) 'old-1'; $new = Join-Path (Get-TestTempRoot) 'new-1'
        New-Item -ItemType Directory $old, $new | Out-Null
        (Get-Item $old).LastWriteTime = (Get-Date).AddHours(-30)
        Invoke-TestTempSweep -MaxAgeHours 24
        Test-Path $old | Should -BeFalse
        Test-Path $new | Should -BeTrue
    }
    It 'the sweep never touches anything OUTSIDE the root' {
        $outside = Join-Path $TestDrive 'outside'; New-Item -ItemType Directory $outside | Out-Null
        (Get-Item $outside).LastWriteTime = (Get-Date).AddHours(-99)
        Invoke-TestTempSweep -MaxAgeHours 24
        Test-Path $outside | Should -BeTrue
    }
    It 'the sweep tolerates a child it cannot delete' {
        { Invoke-TestTempSweep -MaxAgeHours 0 } | Should -Not -Throw
    }
}
Describe 'the once-per-run sweep flag' {
    It 'a second dot-source in the same run does NOT sweep again' {
        $saved = $env:CLAVITY_TEST_TEMP_SWEPT; $savedRoot = $env:CLAVITY_TEST_TEMP_ROOT
        try {
            $env:CLAVITY_TEST_TEMP_ROOT = Join-Path $TestDrive 'flagroot'; $null = New-Item -ItemType Directory $env:CLAVITY_TEST_TEMP_ROOT -Force
            $old = Join-Path $env:CLAVITY_TEST_TEMP_ROOT 'old-2'; New-Item -ItemType Directory $old | Out-Null; (Get-Item $old).LastWriteTime = (Get-Date).AddHours(-200)
            $env:CLAVITY_TEST_TEMP_SWEPT = '1'
            . (Join-Path $PSScriptRoot 'TestTemp.ps1')
            Test-Path $old | Should -BeTrue -Because 'the flag says this run already swept'
            Remove-Item Env:CLAVITY_TEST_TEMP_SWEPT
            . (Join-Path $PSScriptRoot 'TestTemp.ps1')
            Test-Path $old | Should -BeFalse -Because 'without the flag the dot-source sweeps'
        } finally {
            if ($null -eq $saved) { Remove-Item Env:CLAVITY_TEST_TEMP_SWEPT -ErrorAction SilentlyContinue } else { $env:CLAVITY_TEST_TEMP_SWEPT = $saved }
            if ($null -eq $savedRoot) { Remove-Item Env:CLAVITY_TEST_TEMP_ROOT -ErrorAction SilentlyContinue } else { $env:CLAVITY_TEST_TEMP_ROOT = $savedRoot }
        }
    }
}

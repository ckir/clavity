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
    It 'the sweep refuses a root that is a junction, and removing a child junction leaves its target intact' {
        $target = Join-Path $TestDrive 'link-target'; New-Item -ItemType Directory $target | Out-Null
        $victim = Join-Path $target 'victim.txt'; 'x' | Set-Content $victim
        (Get-Item $victim).LastWriteTime = (Get-Date).AddHours(-99)
        $savedRoot = $env:CLAVITY_TEST_TEMP_ROOT
        try {
            $linkRoot = Join-Path $TestDrive 'link-root'; New-TestDirectoryLink -Path $linkRoot -Target $target | Out-Null
            $env:CLAVITY_TEST_TEMP_ROOT = $linkRoot
            Invoke-TestTempSweep -MaxAgeHours 24
            Test-Path $victim | Should -BeTrue -Because 'a junction root must not be swept'
        } finally { $env:CLAVITY_TEST_TEMP_ROOT = $savedRoot }
        $kid = Join-Path (Get-TestTempRoot) 'kid-link'; New-TestDirectoryLink -Path $kid -Target $target | Out-Null
        (Get-Item $kid -Force).LastWriteTime = (Get-Date).AddHours(-99)
        Invoke-TestTempSweep -MaxAgeHours 24
        Test-Path $victim | Should -BeTrue -Because 'Remove-Item on a child junction must delete the link, not the target'
    }
    It 'the sweep never touches anything OUTSIDE the root' {
        $outside = Join-Path $TestDrive 'outside'; New-Item -ItemType Directory $outside | Out-Null
        (Get-Item $outside).LastWriteTime = (Get-Date).AddHours(-99)
        Invoke-TestTempSweep -MaxAgeHours 24
        Test-Path $outside | Should -BeTrue
    }
    It 'the sweep tolerates a child it cannot delete, and still removes the deletable ones' {
        $root = Get-TestTempRoot
        $locked = Join-Path $root 'locked-child'; New-Item -ItemType Directory $locked | Out-Null
        $held = Join-Path $locked 'held.txt'; 'x' | Set-Content $held
        $free = Join-Path $root 'free-child'; New-Item -ItemType Directory $free | Out-Null
        foreach ($d in $locked, $free) { (Get-Item $d).LastWriteTime = (Get-Date).AddHours(-99) }
        if ((-not $IsWindows) -and ((& id -u) -eq '0')) {
            Set-ItResult -Skipped -Because 'APPROVED:NotAsRoot: root is not bound by directory permissions'
            return
        }
        # Windows: an exclusive handle, so the sweep's Remove-Item fails on this child. Elsewhere: an unwritable
        # directory, which makes held.txt undeletable.
        $fs = $null
        if ($IsWindows) { $fs = [IO.File]::Open($held, 'Open', 'Read', 'None') } else { & chmod 555 $locked }
        try {
            { Invoke-TestTempSweep -MaxAgeHours 24 } | Should -Not -Throw
            Test-Path $held | Should -BeTrue -Because 'the locked child must survive (proves the delete really failed)'
            Test-Path $free | Should -BeFalse -Because 'one undeletable child must not stop the sweep reaching the others'
        } finally { if ($IsWindows) { $fs.Dispose() } else { & chmod 755 $locked } }
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

Describe 'Restore-KilledRunBackup' {
    It 'restores the backup when the tracked target is MISSING (a killed run)' {
        $b = Join-Path $TestDrive 'a.bak'; $t = Join-Path $TestDrive 'a.json'
        'BACKUP' | Set-Content $b
        Restore-KilledRunBackup -Backup $b -Target $t 3>$null
        (Get-Content $t -Raw).Trim() | Should -Be 'BACKUP'
        Test-Path $b | Should -BeFalse
    }
    It 'NEVER moves a stale backup over a target that exists, and deletes the stale backup' {
        $b = Join-Path $TestDrive 'b.bak'; $t = Join-Path $TestDrive 'b.json'
        'STALE' | Set-Content $b; 'CURRENT' | Set-Content $t
        Restore-KilledRunBackup -Backup $b -Target $t 3>$null
        (Get-Content $t -Raw).Trim() | Should -Be 'CURRENT'
        Test-Path $b | Should -BeFalse
    }
    It 'does nothing when there is no backup' {
        $t = Join-Path $TestDrive 'c.json'; 'KEEP' | Set-Content $t
        { Restore-KilledRunBackup -Backup (Join-Path $TestDrive 'none.bak') -Target $t } | Should -Not -Throw
        (Get-Content $t -Raw).Trim() | Should -Be 'KEEP'
    }
    It 'Get-ParkedFilePath lives in the SYSTEM temp, not the swept root' {
        (Get-ParkedFilePath 'x.testbak') | Should -Be (Join-Path ([IO.Path]::GetTempPath()) 'x.testbak')
        (Get-ParkedFilePath 'x.testbak') | Should -Not -BeLike ((Get-TestTempRoot) + '*')
    }
}

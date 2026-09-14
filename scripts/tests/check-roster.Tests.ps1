BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'check-roster.ps1'
    $script:Lib     = Join-Path $PSScriptRoot '..' 'lib' 'release-lib.ps1'
    . $script:Lib
}

Describe 'Assert-RosterMatchesMembers (CC2 drift gate)' {
    It 'passes when the $Members Marketplace set equals members.json names' {
        # the real repo: the two sets must already agree
        { Assert-RosterMatchesMembers -MembersJsonPath (Join-Path $PSScriptRoot '..' '..' 'build' 'members.json') } | Should -Not -Throw
    }
    It 'FAILS if members.json has a member the roster does not (add-without-register)' {
        # The real roster is 4 members (ghidrust fully retired 2026-09-14); members.json here adds a 5th
        # that the roster lacks, which must throw.
        $j = @{ members = @(
            @{ name='clavity-dotnet' }, @{ name='clavity-classic' }, @{ name='agy-autotrain' },
            @{ name='commonmemory' }, @{ name='brand-new-plugin' }
        ) } | ConvertTo-Json -Depth 5
        $p = Join-Path $TestDrive 'm.json'; Set-Content $p $j
        { Assert-RosterMatchesMembers -MembersJsonPath $p } | Should -Throw
    }
    It 'FAILS if the roster has a member members.json does not (sunset-without-remove)' {
        # members.json here DROPS commonmemory, which is still in the real 4-member roster — must throw.
        $j = @{ members = @(
            @{ name='clavity-dotnet' }, @{ name='clavity-classic' }, @{ name='agy-autotrain' }
        ) } | ConvertTo-Json -Depth 5
        $p = Join-Path $TestDrive 'm.json'; Set-Content $p $j
        { Assert-RosterMatchesMembers -MembersJsonPath $p } | Should -Throw
    }
    It 'FAILS on a duplicate BumpKey/Root/Marketplace in the roster (copy-paste guard)' {
        # a 6th row that satisfies name-equality but duplicates member 5's Key/Root (agy copy-paste failure mode)
        Mock Get-Members {
            @(
                [pscustomobject]@{ Key='dotnet'; Marketplace='clavity-dotnet'; Root='clavity-dotnet'; Iss='x'; Ghidrust=$false }
                [pscustomobject]@{ Key='dotnet'; Marketplace='new-plugin';     Root='clavity-dotnet'; Iss='x'; Ghidrust=$false }
            )
        }
        $j = @{ members = @(@{ name='clavity-dotnet' }, @{ name='new-plugin' }) } | ConvertTo-Json -Depth 5
        $p = Join-Path $TestDrive 'dup.json'; Set-Content $p $j
        { Assert-RosterMatchesMembers -MembersJsonPath $p } | Should -Throw -ExpectedMessage '*duplicate*'
    }
}

Describe 'check-roster.ps1 (exit code)' {
    It 'exits 0 on the real repo' {
        & pwsh -File $script:Script
        $LASTEXITCODE | Should -Be 0
    }
}

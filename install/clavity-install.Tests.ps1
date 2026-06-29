BeforeAll {
    . $PSScriptRoot/clavity-install.ps1   # dot-source: defines the functions, does NOT run main (InvocationName = '.')
}

Describe "Assert-NoConflictingVariant" {
    It "throws when installing dotnet while classic is present" {
        Mock Test-ClassicPresent { $true }
        Mock Test-DotnetPresent { $false }
        { Assert-NoConflictingVariant -Variant "dotnet" } | Should -Throw "*classic*"
    }
    It "throws when installing classic while dotnet is present" {
        Mock Test-ClassicPresent { $false }
        Mock Test-DotnetPresent { $true }
        { Assert-NoConflictingVariant -Variant "classic" } | Should -Throw "*clavity-dotnet*"
    }
    It "does not throw when no conflicting variant is present" {
        Mock Test-ClassicPresent { $false }
        Mock Test-DotnetPresent { $false }
        { Assert-NoConflictingVariant -Variant "dotnet" } | Should -Not -Throw
    }
}

Describe "Get-ReleaseAsset" {
    It "returns the matching asset url" {
        $release = [pscustomobject]@{ tag_name = "v1"; assets = @(
            [pscustomobject]@{ name = "clavity-dotnet-setup.exe"; browser_download_url = "http://x" }) }
        (Get-ReleaseAsset -Release $release -Name "clavity-dotnet-setup.exe").browser_download_url | Should -Be "http://x"
    }
    It "throws when the asset is missing (e.g. the .sha256 companion)" {
        $release = [pscustomobject]@{ tag_name = "v1"; assets = @() }
        { Get-ReleaseAsset -Release $release -Name "clavity-dotnet-setup.exe.sha256" } | Should -Throw "*not found*"
    }
}

Describe "Assert-Sha256" {
    It "throws on a hash mismatch" {
        $f = Join-Path $TestDrive "x.bin"; Set-Content -Path $f -Value "hello" -NoNewline
        { Assert-Sha256 -FilePath $f -ExpectedHex "deadbeef" } | Should -Throw "*mismatch*"
    }
    It "passes on a matching hash" {
        $f = Join-Path $TestDrive "x.bin"; Set-Content -Path $f -Value "hello" -NoNewline
        $h = (Get-FileHash -Path $f -Algorithm SHA256).Hash
        { Assert-Sha256 -FilePath $f -ExpectedHex $h } | Should -Not -Throw
    }
}

<#
.SYNOPSIS  Download, SHA-256-verify, and run the clavity installer (dotnet or classic variant).
.DESCRIPTION Run in PowerShell (NOT cmd.exe).
.EXAMPLE   irm https://raw.githubusercontent.com/ckir/clavity/main/install/clavity-install.ps1 | iex
#>
[CmdletBinding()]
param(
    [ValidateSet("dotnet","classic","")]
    [string] $Variant = "",
    [string] $Version = "latest",
    [string] $Owner   = "ckir",
    [string] $Repo    = "clavity",
    [switch] $Silent
)

function Test-ClassicPresent {
    [bool](Get-Command clavity -ErrorAction SilentlyContinue) -or (Test-Path "HKCU:\Software\clavity\classic")
}

function Test-DotnetPresent {
    $null -ne (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq "clavity-dotnet" })
}

function Assert-NoConflictingVariant {
    param([Parameter(Mandatory)][string] $Variant)
    # Mutual exclusion (Component A/E): refuse BEFORE download if the OTHER variant is present.
    if ($Variant -eq "dotnet" -and (Test-ClassicPresent)) {
        throw "clavity (classic) is already installed - the two variants cannot coexist. Remove classic first (cargo uninstall clavity), then re-run."
    }
    if ($Variant -eq "classic" -and (Test-DotnetPresent)) {
        throw "clavity-dotnet is already installed - remove it first (Add/Remove Programs), then install classic."
    }
}

function Resolve-ClavityRelease {
    param([Parameter(Mandatory)][string] $Owner, [Parameter(Mandatory)][string] $Repo, [Parameter(Mandatory)][string] $Version)
    $api = if ($Version -eq "latest") {
        "https://api.github.com/repos/$Owner/$Repo/releases/latest"
    } else {
        "https://api.github.com/repos/$Owner/$Repo/releases/tags/$Version"
    }
    Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "clavity-installer" }
}

function Get-ReleaseAsset {
    param([Parameter(Mandatory)] $Release, [Parameter(Mandatory)][string] $Name)
    $asset = $Release.assets | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $asset) { throw "$Name not found in release '$($Release.tag_name)'." }
    $asset
}

function Get-VariantSetupAsset {
    param([Parameter(Mandatory)] $Release, [Parameter(Mandatory)][string] $Variant)
    # Matches BOTH the umbrella versioned name (clavity-<variant>-setup-<ver>.exe) and the legacy un-versioned
    # name (clavity-<variant>-setup.exe), so this script works whether it or the first umbrella release ships
    # first (deployment-order race). Variant-scoped, so it selects the correct exe out of the umbrella bundle.
    $pattern = "^clavity-$Variant-setup(-.+)?\.exe$"
    $asset = $Release.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
    if (-not $asset) { throw "No clavity-$Variant setup asset found in release '$($Release.tag_name)'." }
    $asset
}

function Assert-Sha256 {
    param([Parameter(Mandatory)][string] $FilePath, [Parameter(Mandatory)][string] $ExpectedHex)
    $expected = $ExpectedHex.Trim().ToLower()
    $actual = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash.ToLower()
    if ($expected -ne $actual) {
        throw "SHA-256 mismatch (expected $expected, got $actual). Refusing to run - the download may be corrupt or tampered."
    }
}

function Install-Clavity {
    param([string] $Variant, [string] $Version, [string] $Owner, [string] $Repo, [switch] $Silent)

    if (-not $Variant) {
        $ans = Read-Host "Install which clavity variant? [dotnet/classic] (default: dotnet)"
        $Variant = if ($ans -in @("classic","c")) { "classic" } else { "dotnet" }
    }

    Assert-NoConflictingVariant -Variant $Variant

    Write-Host "Resolving clavity-$Variant release ($Version)..."
    $release = Resolve-ClavityRelease -Owner $Owner -Repo $Repo -Version $Version
    # Version-tolerant, variant-scoped match: handles both the umbrella (versioned) and legacy (un-versioned) names.
    $asset    = Get-VariantSetupAsset -Release $release -Variant $Variant
    $shaAsset = Get-ReleaseAsset -Release $release -Name "$($asset.name).sha256"   # D2: the integrity companion is mandatory

    $dest = Join-Path $env:TEMP $asset.name
    Write-Host "Downloading $($asset.name) ($($release.tag_name))..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $dest -Headers @{ "User-Agent" = "clavity-installer" }

    # D2: SHA-256 verify against the companion asset BEFORE running. Guards partial/corrupt downloads + a single
    # swapped asset; a fully-compromised Release could rewrite both, so integrity ultimately rests on the immutable
    # pinned tag + GitHub/TLS trust (documented + accepted).
    $shaText = (Invoke-WebRequest -Uri $shaAsset.browser_download_url -Headers @{ "User-Agent" = "clavity-installer" }).Content
    $expectedHex = (($shaText -split '\s+') | Where-Object { $_ })[0]
    try {
        Assert-Sha256 -FilePath $dest -ExpectedHex $expectedHex
    } catch {
        Remove-Item $dest -Force -ErrorAction SilentlyContinue
        throw
    }
    Write-Host "SHA-256 verified."

    Write-Host "Running the installer..."
    $p = if ($Silent) {
        Start-Process -FilePath $dest -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait -PassThru
    } else {
        Start-Process -FilePath $dest -Wait -PassThru
    }
    if ($p.ExitCode -ne 0) { throw "Installer exited with code $($p.ExitCode)." }
    Write-Host "clavity-$Variant installed. Open a terminal (PowerShell) and run:  clavity-ls start C:\path\to\project"
}

# Run only when invoked directly (not when dot-sourced by Pester tests).
if ($MyInvocation.InvocationName -ne '.') {
    Install-Clavity -Variant $Variant -Version $Version -Owner $Owner -Repo $Repo -Silent:$Silent
}

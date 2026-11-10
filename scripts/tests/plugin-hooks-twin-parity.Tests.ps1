<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

# clavity-dotnet and clavity-classic ship the SAME shell hooks. 18 of them are byte-identical twins by design (each script's own
# header says "Byte-identical across both driver plugins"); a fix applied to one copy and not the other is a silent behaviour
# fork. This suite holds every file present in BOTH plugin/hooks directories to byte equality (SHA-256), and names the known,
# deliberate asymmetries explicitly so a NEW asymmetry is a red row, not an unnoticed drift.

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:Dotnet = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks'
    $script:Classic = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks'

    # The known asymmetries. hooks.json is registered per product; the other three exist in one product only.
    $script:Differs = @('hooks.json')
    $script:ClassicOnly = @('agy-drive-session-reset.sh')
    $script:DotnetOnly = @('clavity-dotnet-setup.sh', 'clavity-ls-launcher-lib.sh', 'fetch-clavity-ls.sh')

    function Get-HookNames([string]$Dir) {
        @(Get-ChildItem -LiteralPath $Dir -File | ForEach-Object { $_.Name } | Sort-Object)
    }
    $script:DotnetNames = Get-HookNames $script:Dotnet
    $script:ClassicNames = Get-HookNames $script:Classic
    $script:Shared = @($script:DotnetNames | Where-Object { $_ -in $script:ClassicNames })
    $script:Twins = @($script:Shared | Where-Object { $_ -notin $script:Differs })
}

Describe 'plugin hook twins stay byte-identical across clavity-dotnet and clavity-classic' {
    It 'finds a plausible population of hook files in both directories' {
        $script:DotnetNames.Count | Should -BeGreaterThan 10 -Because 'a near-empty listing means the directory walk broke, not that the hooks vanished'
        $script:ClassicNames.Count | Should -BeGreaterThan 10 -Because 'a near-empty listing means the directory walk broke, not that the hooks vanished'
        $script:Twins.Count | Should -BeGreaterThan 10 -Because 'the twin set is what every row below is about'
    }

    It 'has exactly the allowlisted files present in only one product' {
        $dotnetOnly = @($script:DotnetNames | Where-Object { $_ -notin $script:ClassicNames })
        $classicOnly = @($script:ClassicNames | Where-Object { $_ -notin $script:DotnetNames })
        ($dotnetOnly -join ', ') | Should -BeExactly (($script:DotnetOnly | Sort-Object) -join ', ') -Because 'a hook present in clavity-dotnet only must be on the DotnetOnly allowlist - or be added to clavity-classic as a twin'
        ($classicOnly -join ', ') | Should -BeExactly (($script:ClassicOnly | Sort-Object) -join ', ') -Because 'a hook present in clavity-classic only must be on the ClassicOnly allowlist - or be added to clavity-dotnet as a twin'
    }

    It 'every allowlisted asymmetry still exists (a stale allowlist entry would hide a future drift)' {
        foreach ($n in $script:Differs) {
            Test-Path -LiteralPath (Join-Path $script:Dotnet $n) | Should -BeTrue -Because "$n is allowlisted as differing but is missing from clavity-dotnet"
            Test-Path -LiteralPath (Join-Path $script:Classic $n) | Should -BeTrue -Because "$n is allowlisted as differing but is missing from clavity-classic"
        }
        foreach ($n in $script:DotnetOnly) { Test-Path -LiteralPath (Join-Path $script:Dotnet $n) | Should -BeTrue -Because "$n is allowlisted as dotnet-only but is gone" }
        foreach ($n in $script:ClassicOnly) { Test-Path -LiteralPath (Join-Path $script:Classic $n) | Should -BeTrue -Because "$n is allowlisted as classic-only but is gone" }
    }

    It 'every file present in BOTH directories (except the allowlisted hooks.json) has the same SHA-256' {
        $drift = foreach ($n in $script:Twins) {
            $a = (Get-FileHash -LiteralPath (Join-Path $script:Dotnet $n) -Algorithm SHA256).Hash
            $b = (Get-FileHash -LiteralPath (Join-Path $script:Classic $n) -Algorithm SHA256).Hash
            if ($a -ne $b) { $n }
        }
        ($drift -join ', ') | Should -BeExactly '' -Because 'these twin hooks differ between clavity-dotnet/plugin/hooks and clavity-classic/plugin/hooks - apply the change to both copies'
    }

    It 'hooks.json really does differ (so its allowlist entry is still earning its place)' {
        $a = (Get-FileHash -LiteralPath (Join-Path $script:Dotnet 'hooks.json') -Algorithm SHA256).Hash
        $b = (Get-FileHash -LiteralPath (Join-Path $script:Classic 'hooks.json') -Algorithm SHA256).Hash
        $a | Should -Not -BeExactly $b -Because 'if hooks.json became identical, drop it from the allowlist so it is held to byte equality too'
    }
}

<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

# Pester v5. Every top-level scripts/*.ps1 must run under `Set-StrictMode -Version Latest`.
#
# WHY: without strict mode a typo'd or never-assigned variable reads as $null instead of throwing, so a
# gate can "pass" over an input it never saw (the exact fail-open class these scripts exist to prevent).
# Adding the line to a script that lacked it surfaced a real bug (check-plugin-namespace.ps1 read a hook
# group's `matcher` property that SessionStart groups do not have), so this is not a style rule.
#
# SCOPE: top-level scripts/*.ps1 only. scripts/lib/*.ps1 are dot-sourced into a caller that has already set
# strict mode (and each carries its own line anyway); scripts/tests/ holds suites, not scripts.
#
# ALLOWLIST: a script that genuinely CANNOT take strict mode goes in $Allowlist with the reason. It is
# empty because every script now takes it; an entry must be justified here, never added to make a red go away.
BeforeAll {
    $script:ScriptsDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Allowlist = @{}   # name -> reason it cannot take Set-StrictMode -Version Latest
    $script:Scripts = @(Get-ChildItem -LiteralPath $script:ScriptsDir -Filter '*.ps1' -File)
    # An ACTIVE statement: first non-blank token on the line, so a mention in a comment or string does not count.
    $script:StrictRx = '(?m)^[ \t]*Set-StrictMode[ \t]+-Version[ \t]+Latest\b'
}

Describe 'scripts/*.ps1 strict mode' {
    It 'enumerated a plausible population of scripts' {
        $script:Scripts.Count | Should -BeGreaterThan 30 -Because 'an enumeration that found almost nothing means the walk broke, not that scripts/ is empty'
    }

    It 'every top-level script sets Set-StrictMode -Version Latest (or is allowlisted with a reason)' {
        $missing = @($script:Scripts | Where-Object {
            -not $script:Allowlist.ContainsKey($_.Name) -and
            -not ([regex]::IsMatch((Get-Content -LiteralPath $_.FullName -Raw), $script:StrictRx))
        } | ForEach-Object { $_.Name } | Sort-Object)
        $missing -join ', ' | Should -BeExactly '' -Because 'add `Set-StrictMode -Version Latest` (after any param block) and fix whatever uninitialised variable it exposes; only a script that truly cannot take it may be listed in $Allowlist, with the reason'
    }

    It 'the allowlist names only existing scripts, each with a non-empty reason' {
        $names = @($script:Scripts | ForEach-Object { $_.Name })
        @($script:Allowlist.Keys | Where-Object { $_ -notin $names }) -join ', ' | Should -BeExactly '' -Because 'a stale allowlist entry exempts nothing and hides that the script was removed or renamed'
        @($script:Allowlist.GetEnumerator() | Where-Object { [string]::IsNullOrWhiteSpace($_.Value) } | ForEach-Object { $_.Key }) -join ', ' | Should -BeExactly '' -Because 'an exemption without a reason cannot be reviewed'
    }
}

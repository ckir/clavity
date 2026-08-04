# scripts/README.md is an INVENTORY INDEX - check-user-facing-docs.ps1:62 calls it exactly that - and until
# now nothing verified the inventory was complete.
#
# WHY THIS EXISTS: it drifted on 2026-08-04. `discipline-reaching-report.ps1` was added, the README was not
# updated, and no gate noticed. The miss is invisible by construction - a reader consulting the index sees a
# tidy table and cannot tell that an entry is missing, which is the same shape as every other failure this
# repo keeps paying for: an artifact that LOOKS complete because absence leaves no trace.
#
# It asserts PRESENCE OF A NAME, not the quality of its description. A one-line entry that says nothing
# useful still passes here; that judgement belongs to a human reviewer and to docs-audit, not to a grep.

Describe 'scripts/README.md inventory' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Readme = Join-Path $script:RepoRoot 'scripts/README.md'
        $script:Text = if (Test-Path -LiteralPath $script:Readme) { Get-Content -LiteralPath $script:Readme -Raw } else { '' }
        # Top-level scripts only. Subdirectories (tests/, hooks/, lib/) have their own sections and are not
        # enumerated file-by-file, so sweeping them in would fail for a reason the index never claimed.
        $script:Executables = @(
            Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'scripts') -File |
                Where-Object { $_.Extension -in '.ps1', '.sh' } |
                Select-Object -ExpandProperty Name | Sort-Object
        )
    }

    It 'has a non-empty README and a non-empty script list' {
        # Both guards exist so every per-file assertion below cannot pass vacuously: an empty README or an
        # empty file list would satisfy a "foreach name, assert present" loop by never running its body.
        $script:Text | Should -Not -BeNullOrEmpty
        $script:Executables.Count | Should -BeGreaterThan 10 -Because 'a near-empty listing means the enumeration itself broke, not that scripts/ is empty'
    }

    It 'names every top-level script in scripts/' {
        $missing = @($script:Executables | Where-Object { $script:Text -notmatch [regex]::Escape($_) })
        # Report the actual names: "count is 2" sends a reader hunting, a name sends them to the fix.
        $missing -join ', ' | Should -BeExactly '' -Because 'scripts/README.md is the inventory index; a script absent from it is invisible to anyone reading the index'
    }

    It 'matches script names case-exactly' {
        # A case-insensitive check would pass GitHub_Actions_Storage_Reset.ps1 against a lowercase mention and
        # call a real miss clean. This is not hypothetical: a case-sensitive character class silently produced
        # a FALSE "missing" verdict for that exact file while auditing this, so the case axis cuts both ways.
        foreach ($n in $script:Executables) {
            $script:Text | Should -Match ([regex]::Escape($n)) -Because "the index must name $n exactly as it is spelled on disk"
        }
    }
}

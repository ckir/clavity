BeforeAll {
    $script:Script   = Join-Path $PSScriptRoot '..' 'check-injected-context.ps1'
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
}

Describe 'check-injected-context.ps1' {
    It 'exists on disk' {
        Test-Path $script:Script | Should -BeTrue -Because 'every other row here depends on it'
    }

    Context 'subtractive discovery' {
        BeforeAll {
            . $script:Script -RepoRoot $script:RepoRoot
            $script:Files = Get-InjectedContextFiles -RepoRoot $script:RepoRoot
        }

        It 'finds the seed header' {
            $script:Files | Should -Contain 'seed/golden-header.md'
        }
        It 'finds a skill body in each plugin tree' {
            $script:Files | Should -Contain 'clavity-dotnet/plugin/skills/agy-first/SKILL.md'
            $script:Files | Should -Contain 'clavity-classic/plugin/skills/agy-first/SKILL.md'
        }
        It 'finds files in all three previously unaudited products' {
            $script:Files | Should -Contain 'ghidrust/plugin/skills/ghidra-re-driver/SKILL.md'
            $script:Files | Should -Contain 'commonmemory/skills/commonmemory/SKILL.md'
            $script:Files | Should -Contain 'agy-autotrain/skills/agy-learn/SKILL.md'
        }
        It 'subtracts <path>' -ForEach @(
            @{ path = 'clavity-dotnet/plugin/README.md' }
            @{ path = 'clavity-dotnet/plugin/plugin.json' }
            @{ path = 'clavity-dotnet/plugin/NOTICE' }
        ) {
            $script:Files | Should -Not -Contain $path
        }
        It 'FAILS if a product ships skills that no domain root covers' {
            # $script:DomainRoots is a hardcoded array, so a SEVENTH product added a year from now would
            # be silently ignored forever - the gate green, its context never audited, and nothing to
            # remind anyone. This row is that reminder: it discovers products structurally and fails when
            # one is not covered, naming it.
            $covered = { param($p) foreach ($r in $script:DomainRoots) { if ($p -like "$r*") { return $true } }; return $false }
            $shipsSkills = Get-ChildItem -LiteralPath $script:RepoRoot -Directory |
                Where-Object { $_.Name -notmatch '^\.' } |
                ForEach-Object {
                    $n = $_.Name
                    if (Test-Path (Join-Path $_.FullName 'skills'))        { "$n/skills" }
                    if (Test-Path (Join-Path $_.FullName 'plugin/skills')) { "$n/plugin/skills" }
                }
            $uncovered = @($shipsSkills | Where-Object { -not (& $covered $_) })
            $uncovered -join ', ' | Should -BeExactly '' -Because 'a product shipping skills is injected context; add it to $script:DomainRoots or exclude it deliberately'
        }
        It 'does NOT subtract the agy-learn inbox - it is in the domain and handled by exemption' {
            # agy-curate/SKILL.md:105 ("For each inbox entry - decide") shows an agent reads this file
            # into context. Ignoring it would be an exemption wearing a different name; owner ruled it is
            # an exemption proper, waiving encoding only.
            $script:Files | Should -Contain 'agy-autotrain/knowledge/agy-observations.md'
        }
        It 'subtracts nothing silently - every ignored path sits under a recorded reason' {
            $lines = @(Get-Content (Join-Path $script:RepoRoot 'scripts/injected-context-ignore.txt'))
            $globs = @($lines | Where-Object { $_ -and -not $_.StartsWith('#') })
            $globs.Count | Should -BeGreaterThan 0
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if (-not $lines[$i] -or $lines[$i].StartsWith('#')) { continue }
                # Scan UPWARD to the nearest comment. One reason may head a block of related globs -
                # requiring a comment on the immediately preceding line would fail every glob after the
                # first in each block, and the likeliest "fix" is deleting this assertion, which destroys
                # the invariant that nothing is ignored without a stated reason.
                $j = $i - 1
                while ($j -ge 0 -and $lines[$j] -and -not $lines[$j].StartsWith('#')) { $j-- }
                ($j -ge 0 -and $lines[$j].StartsWith('#')) |
                    Should -BeTrue -Because "'$($lines[$i])' must sit under a '#' reason"
            }
        }
    }

    Context 'encoding invariant' {
        BeforeAll {
            . $script:Script -RepoRoot $script:RepoRoot
            # [System.Text.Encoding]::UTF8 EMITS A BOM (EF BB BF), which is itself non-ASCII. Writing
            # fixtures with it made 'passes a pure-ASCII file' fail, and - worse - made the em-dash row
            # pass for the wrong reason: the BOM alone would have failed it, so it never tested the
            # em-dash at all. Every fixture below uses a BOM-less encoder so each row tests what it names.
            $script:NoBom = New-Object System.Text.UTF8Encoding($false)
            function New-TmpFile { Join-Path ([IO.Path]::GetTempPath()) ("ic-" + [guid]::NewGuid().ToString('N') + '.md') }
        }

        It 'reads bytes, not decoded text - a BOM-less em-dash is caught' {
            $tmp = New-TmpFile
            [System.IO.File]::WriteAllText($tmp, "a$([char]0x2014)b", $script:NoBom)
            (Test-PureAscii -Path $tmp) | Should -BeFalse
            Remove-Item -Force $tmp
        }
        It 'passes a pure-ASCII file' {
            $tmp = New-TmpFile
            [System.IO.File]::WriteAllText($tmp, "plain ascii", $script:NoBom)
            (Test-PureAscii -Path $tmp) | Should -BeTrue
            Remove-Item -Force $tmp
        }
        It 'FLAGS a UTF-8 BOM - it is non-ASCII bytes and can drive the same mojibake' {
            # Pinned deliberately rather than left as the accident that exposed it. A BOM is EF BB BF at
            # the head of the file; the gate must not treat "the text is ASCII" as "the file is ASCII".
            $tmp = New-TmpFile
            [System.IO.File]::WriteAllText($tmp, "plain ascii", (New-Object System.Text.UTF8Encoding($true)))
            (Test-PureAscii -Path $tmp) | Should -BeFalse
            Remove-Item -Force $tmp
        }
        It 'reports the exact offending codepoints, not just a count' {
            $tmp = New-TmpFile
            [System.IO.File]::WriteAllText($tmp, "x$([char]0x2192)y", $script:NoBom)
            (Get-NonAsciiReport -Path $tmp) | Should -Match '0x2192'
            Remove-Item -Force $tmp
        }
    }

    Context 'reference candidate identification' {
        BeforeAll { . $script:Script -RepoRoot $script:RepoRoot }

        It 'treats <tok> as a candidate' -ForEach @(
            @{ tok = 'docs/agy-disciplines-marker-contract.md' }
            @{ tok = 'assertion-strength-reminder.sh' }
            @{ tok = './hooks/agy-seam-inject.sh' }
            @{ tok = '../knowledge/agy-capabilities.md' }
        ) { (Test-IsPathCandidate -Token $tok) | Should -BeTrue }

        It 'does NOT treat <tok> as a candidate' -ForEach @(
            @{ tok = '/agent' }
            @{ tok = '/mcp' }
            @{ tok = '/model' }
            @{ tok = '/skills' }
            @{ tok = '/tasks' }
            @{ tok = '/usage' }
            @{ tok = '/teamwork-preview' }
            @{ tok = '[doc/user]' }
            @{ tok = 'read/write' }
        ) { (Test-IsPathCandidate -Token $tok) | Should -BeFalse }

        It 'does NOT treat the directory reference <tok> as a file candidate' -ForEach @(
            @{ tok = '.clavity/' }
            @{ tok = '.clavity/agy-marks/' }
            @{ tok = '.git/' }
            @{ tok = '.agents/skills/' }
        ) { (Test-IsPathCandidate -Token $tok) | Should -BeFalse }
    }

    Context 'reference resolution outcomes' {
        BeforeAll { . $script:Script -RepoRoot $script:RepoRoot }

        It 'a dead bare filename is BROKEN' {
            (Resolve-Reference -Token 'agy-first-brainstorm.sh' -RepoRoot $script:RepoRoot).Outcome |
                Should -BeExactly 'broken'
        }
        It 'a mirrored plugin file PASSES - the twin trees canonicalise to one logical path' {
            # agy-seam-inject.sh exists in BOTH plugin trees. Without canonicalisation this returns
            # 'ambiguous', and since most bare filenames in shipped text name plugin files, the whole
            # RESOLVE-THEN-ASSERT class would collapse into permanent ambiguity.
            (Resolve-Reference -Token 'agy-seam-inject.sh' -RepoRoot $script:RepoRoot).Outcome |
                Should -BeExactly 'ok'
        }
        It 'a file unique to one product PASSES' {
            (Resolve-Reference -Token 'driver-cheatsheet.core.md' -RepoRoot $script:RepoRoot).Outcome |
                Should -BeExactly 'ok'
        }
        It 'a multiply resolving bare filename is AMBIGUOUS, not broken and not a pass' {
            (Resolve-Reference -Token 'ROADMAP.md' -RepoRoot $script:RepoRoot).Outcome |
                Should -BeExactly 'ambiguous'
        }
        It 'ambiguous does NOT fail the build' {
            (Test-ReferenceFails -Outcome 'ambiguous') | Should -BeFalse
        }
        It 'broken DOES fail the build' {
            (Test-ReferenceFails -Outcome 'broken') | Should -BeTrue
        }
        It 'a repo-prefixed path that exists PASSES' {
            (Resolve-Reference -Token 'docs/agy-disciplines-marker-contract.md' -RepoRoot $script:RepoRoot).Outcome |
                Should -BeExactly 'ok'
        }
        It 'a repo-prefixed path with a typo in the prefix is BROKEN, not skipped' {
            (Resolve-Reference -Token 'doc/agy-disciplines-marker-contract.md' -RepoRoot $script:RepoRoot).Outcome |
                Should -BeExactly 'unclassified'
        }
        It 'unclassified DOES fail the build' {
            (Test-ReferenceFails -Outcome 'unclassified') | Should -BeTrue
        }
    }

    Context 'text invariants' {
        BeforeAll { . $script:Script -RepoRoot $script:RepoRoot }

        It 'flags plan residue "<txt>"' -ForEach @(
            @{ txt = 'See the marker contract doc (Task 5).' }
            @{ txt = 'described in (Step 12) above' }
            @{ txt = 'per (Phase 3)' }
        ) { (Test-HasPlanResidue -Text $txt) | Should -BeTrue }

        It 'does not flag ordinary parenthetical prose' {
            (Test-HasPlanResidue -Text 'the audit round (item 5) carries it') | Should -BeFalse
        }

        It 'flags a duplicated tag opening' {
            (Test-HasDuplicatedTag -Text '[ASSERTION-STRENGTH] ASSERTION-STRENGTH: you just touched') |
                Should -BeTrue
        }
        It 'does not flag a single tag opening' {
            (Test-HasDuplicatedTag -Text '[ASSERTION-STRENGTH] You just touched a test file.') |
                Should -BeFalse
        }
        It 'does not flag a DIFFERENT all-caps word after the tag - the backreference is load-bearing' {
            # Neither fixture above exercises the backreference: 'You' is not all-caps, so NO pattern
            # flags it, and a non-backreferencing regex would pass both. This row is the one that can
            # tell them apart - a different tag is not a duplication.
            (Test-HasDuplicatedTag -Text '[AGY-DISCIPLINES] AGY-FIRST: consult the peer') |
                Should -BeFalse
        }
        It 'requires SOME bracketed tag on a degraded line, not one specific tag' {
            # A2 was withdrawn: ROADMAP.md:714 rules that assertion-strength deliberately drops the AGY-
            # prefix because it convenes no peer, and Tests.ps1:199-201 pins that. Both tags are valid.
            (Test-DegradedNamespace -Text '[ASSERTION-STRENGTH] guard inactive: missing jq') | Should -BeTrue
            (Test-DegradedNamespace -Text '[AGY-DISCIPLINES] guard inactive: missing jq')    | Should -BeTrue
            (Test-DegradedNamespace -Text 'guard inactive: missing jq')                      | Should -BeFalse
        }
    }
}

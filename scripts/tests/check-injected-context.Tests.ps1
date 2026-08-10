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
            # Commands and source expressions that merely END in something file-shaped. Both of these
            # are verbatim from the corpus and both were reported as reference violations against
            # correct text before the whitespace/paren guard existed.
            @{ tok = 'ghidrust skill --emit > SKILL.md' }
            @{ tok = 'os.path.dirname(__file__)/SKILL.md' }
            @{ tok = 'just check-injected-context' }
        ) { (Test-IsPathCandidate -Token $tok) | Should -BeFalse }

        It 'does NOT treat the directory reference <tok> as a file candidate' -ForEach @(
            @{ tok = '.clavity/' }
            @{ tok = '.clavity/agy-marks/' }
            @{ tok = '.git/' }
            @{ tok = '.agents/skills/' }
        ) { (Test-IsPathCandidate -Token $tok) | Should -BeFalse }
    }

    Context 'domain coverage - the root list must not silently miss an injected tree' {
        # WHY THIS EXISTS. $script:DomainRoots is a hand-maintained list of product-level paths, which is
        # structurally an ALLOWLIST - the exact defect this whole gate was built to remove from
        # check-agy-discipline-skills.ps1:13. Measured 2026-08-09: it missed 3 of the repo's 21 SKILL.md,
        # and all three were injected context (two include_str!'d into shipping binaries, one a headless
        # sub-agent's system prompt). Nothing detected that. What finally surfaced it was an unrelated
        # sibling checker going red, which is luck, not a mechanism.
        #
        # This asserts the property the root list is SUPPOSED to have and never had: every skill file in
        # the repository is either inside a domain root or deliberately ignored.
        BeforeAll {
            . $script:Script -RepoRoot $script:RepoRoot
            $script:Globs = Get-IgnoreGlobs -RepoRoot $script:RepoRoot
            $script:AllSkills = @(
                Get-ChildItem -LiteralPath $script:RepoRoot -Recurse -File -Filter 'SKILL.md' -Force -ErrorAction SilentlyContinue |
                    # ONLY VCS internals and runtime state are excluded here. This list used to mirror
                    # $script:PrunedSegments, which gave the guard the SAME BLIND SPOT as the thing it
                    # guards: a skill planted at skills/dist/SKILL.md was filtered out of this very
                    # enumeration, so the corpus check below could not see it and passed. Measured - the
                    # planted bypass produced a green run. A guard that shares its target's blind spot is
                    # not a guard.
                    Where-Object { $_.FullName -notmatch '[\\/](\.git|\.clavity)[\\/]' } |
                    ForEach-Object { $_.FullName.Substring($script:RepoRoot.Length + 1).Replace('\', '/') }
            )
        }

        It 'finds a non-trivial number of skill files' {
            # Without this, a broken enumeration would make the row below pass over an empty set - the
            # same vacuity this gate exists to catch, reproduced inside its own test.
            $script:AllSkills.Count | Should -BeGreaterThan 10 -Because 'an empty enumeration makes the coverage assertion below meaningless'
        }

        It 'every SKILL.md in the repository is inside a domain root or explicitly ignored' {
            $uncovered = @(
                $script:AllSkills | Where-Object {
                    $p = $_
                    $inRoot   = @($script:DomainRoots | Where-Object { $p.StartsWith("$_/") }).Count -gt 0
                    $ignored  = Test-IsIgnored -RelPath $p -Globs $script:Globs
                    -not ($inRoot -or $ignored)
                }
            )
            # Name them. A count sends a reader hunting; a path sends them to the fix.
            $uncovered -join ', ' | Should -BeExactly '' -Because 'a skill outside every domain root is injected into an agent and audited by nothing'
        }

        It 'every SKILL.md is in the AUDITED CORPUS, not merely under a domain root' {
            # THE GATE-BYPASS GUARD. Capstone round 9 showed that "inside a domain root" is a weaker
            # property than "actually audited": pruning drops a whole directory before the ignorelist is
            # consulted, so naming a skill directory after any pruned segment - dist, target, bin, obj,
            # node_modules, .venv, publish, .vs - removes it from the corpus entirely. MEASURED: a skill at
            # skills/dist/SKILL.md containing a real em dash produced corpus 0 and violations 0. The plugin
            # loader still finds it, so it ships and is injected, having passed no invariant at all.
            #
            # This row was written when the corpus walk still pruned by NAME. Round 10 removed that -
            # the name match WAS the bypass - and the walk now skips DESCENT only where an anchored glob
            # already subtracts the whole directory. The row still earns its place: it asserts the
            # property rather than the mechanism, so it survived that change unedited, which is exactly
            # what a guard should do.
            # Scoped to skills UNDER A DOMAIN ROOT. That is what makes the rule both sound and precise:
            # clavity-classic/publish/agy-mcp-bridge/SKILL.md is a published COPY at product level, sits
            # under no domain root, and is legitimately unaudited because its source is. A skill directory
            # merely NAMED after a pruned segment, by contrast, is inside a root and must be audited.
            $corpus = @(Get-InjectedContextFiles -RepoRoot $script:RepoRoot)
            $missing = @(
                $script:AllSkills | Where-Object {
                    $p = $_
                    # NO IGNORELIST ESCAPE. The bypass is doubly protected - skills/dist/ is BOTH pruned
                    # and matched by the **/dist/** glob - so allowing "explicitly ignored" here let the
                    # planted skill through a second time. Measured twice: the guard passed until this
                    # clause was removed. A SKILL.md inside a domain root is injected context by
                    # definition and is never legitimately ignorable; if one ever must be, it belongs in
                    # the exemptions file with a reason, where it is visible and bidirectionally checked.
                    $inRoot = @($script:DomainRoots | Where-Object { $p.StartsWith("$_/") }).Count -gt 0
                    $inRoot -and ($corpus -notcontains $p)
                }
            )
            $missing -join ', ' | Should -BeExactly '' -Because 'a skill the corpus never sees is shipped and injected having passed no invariant'
        }

        It 'PRUNES <Segment> - every segment in the list is actually load-bearing' -ForEach @(
            @{ Segment = '.git' }        ; @{ Segment = 'node_modules' } ; @{ Segment = 'target' }
            @{ Segment = 'bin' }         ; @{ Segment = 'obj' }          ; @{ Segment = '.venv' }
            @{ Segment = '__pycache__' } ; @{ Segment = 'dist' }         ; @{ Segment = 'publish' }
            @{ Segment = '.vs' }         ; @{ Segment = '.ruff_cache' }  ; @{ Segment = '.pytest_cache' }
            @{ Segment = '.mypy_cache' } ; @{ Segment = '.worktrees' }
        ) {
            # Capstone round 9, Coverage Liar: only dist, bin and target had rows, so deleting any OTHER
            # entry from $script:PrunedSegments left the whole suite green. Its quoted array was wrong -
            # it listed .github and .vscode, which this repository has never had - but the gap it named
            # was real.
            #
            # THIS ROW IS NOT DERIVED FROM THE LIVE LIST. The -ForEach array above is hardcoded, because
            # Pester evaluates -ForEach at DISCOVERY time, before BeforeAll dot-sources the script, so
            # $script:PrunedSegments is not in scope yet. What this row proves is one DIRECTION only: each
            # segment named here is still in the live list, which catches a DELETION. The other direction -
            # an ADDED segment arriving with no row - is closed by the set-comparison row below, not here.
            # (An earlier version of this comment claimed the opposite and contradicted line 248.)
            $script:PrunedSegments | Should -Contain $Segment
            (Test-IsPrunedPath -RelPath "seed/$Segment/x.md") | Should -BeTrue
            (Test-IsPrunedPath -RelPath "seed/$Segment")      | Should -BeFalse -Because 'a FILE with that name is content'
        }

        It 'the prune rows COVER the live list - a new segment cannot arrive untested' {
            # Capstone round 10, Coverage Liar, and the peer was right: I claimed the prune rows were
            # "derived from the live list", but the -ForEach above is a hardcoded 13-entry array that only
            # asserts those 13 are IN $script:PrunedSegments. It never asserts the reverse, so ADDING a
            # segment shipped an untested prune rule and the suite stayed green. Pester evaluates -ForEach
            # at discovery time, before the script is dot-sourced, so the array cannot itself be derived -
            # this row closes that gap instead by comparing the two sets.
            $covered = @('.git','node_modules','target','bin','obj','.venv','__pycache__','dist','publish','.vs',
                         '.ruff_cache','.pytest_cache','.mypy_cache','.worktrees')
            $uncovered = @($script:PrunedSegments | Where-Object { $_ -notin $covered })
            $uncovered -join ', ' | Should -BeExactly '' -Because 'a pruned segment with no row is an untested rule that silently drops files'
        }

        It 'still finds files when the REPOSITORY ITSELF sits under a pruned directory name' {
            # Capstone round 4, and the worst defect in the branch. Both walks pruned against the ABSOLUTE
            # path, so cloning this repository anywhere under target/, bin/, obj/, dist/ - a CI workspace,
            # C:/Projects/target/ - made every file's absolute path contain a pruned segment and dropped the
            # entire corpus. Probed: corpus 0, violations 0, gate printed OK over a file containing a real
            # U+2014. A silent false GREEN inside the gate built to stop silent false GREENs.
            #
            # The 'corpus is non-trivial' row above cannot catch this: it runs against the real repository
            # root, which is not under a pruned name.
            $base = Join-Path ([IO.Path]::GetTempPath()) ("target/icp-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path (Join-Path $base 'scripts') | Out-Null
            Copy-Item (Join-Path $script:RepoRoot 'scripts/injected-context-ignore.txt') (Join-Path $base 'scripts')
            Set-Content -LiteralPath (Join-Path $base 'scripts/injected-context-exemptions.json') -Value '{ "exemptions": [] }' -Encoding ascii
            foreach ($r in $script:DomainRoots) { New-Item -ItemType Directory -Force -Path (Join-Path $base $r) | Out-Null }
            [IO.File]::WriteAllText((Join-Path $base 'seed/violator.md'), "em dash $([char]0x2014) here", (New-Object System.Text.UTF8Encoding($false)))
            try {
                @(Get-InjectedContextFiles -RepoRoot $base).Count |
                    Should -BeGreaterThan 0 -Because 'a repository under a pruned directory name must still be walked'
                @(Get-InjectedContextViolations -RepoRoot $base) |
                    Should -Not -BeNullOrEmpty -Because 'the seeded U+2014 must still be reported'
            } finally { Remove-Item -Recurse -Force $base -ErrorAction SilentlyContinue }
        }

        It 'tolerates a RepoRoot passed WITH a trailing separator' {
            # Capstone round 5. $rel is cut with Substring($RepoRoot.Length + 1), so a root ending in a
            # separator - exactly what shell tab-completion produces - was one character too long and
            # swallowed the first letter of EVERY relative path. Measured: 'clavity-dotnet/...' came back
            # as 'lavity-dotnet/...', which breaks every ignore glob and every reference resolution at
            # once, and turns a tab-completed invocation into a flood of false violations.
            $plain    = @(Get-InjectedContextFiles -RepoRoot $script:RepoRoot)
            $trailing = @(Get-InjectedContextFiles -RepoRoot ($script:RepoRoot + [IO.Path]::DirectorySeparatorChar))
            $trailing.Count | Should -Be $plain.Count
            $trailing[0]    | Should -BeExactly $plain[0] -Because 'a trailing separator must not shift the relative path'
        }

        It 'prunes a DIRECTORY named <seg> but not a FILE named <seg>' -ForEach @(
            @{ seg = 'dist' }
            @{ seg = 'bin' }
            @{ seg = 'target' }
        ) {
            # Capstone round 5, and a regression the round-4 fix introduced in the very line that fixed
            # the absolute-path defect: '(?:/|$)' also matched END-OF-STRING, so a FILE merely named dist
            # was pruned. These are file paths, so a pruned segment is always a directory.
            (Test-IsPrunedPath -RelPath "seed/$seg")       | Should -BeFalse -Because "a FILE named $seg is content"
            (Test-IsPrunedPath -RelPath "seed/$seg/x.md")  | Should -BeTrue  -Because "a DIRECTORY named $seg is build output"
        }

        It 'every domain root is in the CI workflow path filter - <Filter>' -ForEach @(
            @{ Filter = 'push' }
            @{ Filter = 'pull_request' }
        ) {
            # $script:DomainRoots and the workflow's path filter are TWO COPIES OF ONE FACT, and they
            # drifted within a single commit: three roots were added and the filter was not updated, so
            # a change under ghidrust/skill/ would not have triggered the gate that audits it. A gate
            # wired to a filter that does not cover its own domain is the same "never invoked" failure
            # this workflow was split out to avoid, one level further in.
            #
            # Parsed rather than eyeballed because eyeballing is exactly what missed it.
            $wf = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/ci-injected-context.yml') -Raw
            $section = switch ($Filter) {
                'push'         { ($wf -split 'pull_request:')[0] }
                'pull_request' { ($wf -split 'pull_request:')[1] }
            }
            # THE KEY MUST BE LITERALLY `paths:`. The first version of this test scraped every quoted list
            # item in the section and ignored the YAML key above it, so renaming the key to `paths-ignore:`
            # INVERTED the trigger - CI would skip exactly the domain it is meant to watch - and this test
            # still passed. MEASURED: 83/0 under that one-token edit. A drift guard that fails open under a
            # plausible edit is worse than none, because it certifies the thing it stopped checking.
            # The key may legitimately carry a YAML anchor or a trailing comment (`paths: &shared`), so
            # match those rather than reddening on valid YAML - measured, the stricter `\s*$` form failed
            # on `paths: &my-paths`. It still cannot match `paths-ignore:`, which has no `paths:` substring.
            # NON-CAPTURING groups are load-bearing, not style. `-split` inserts every PARTICIPATING
            # capture group into the result, so with capturing groups the normal case passed (neither
            # optional group participates) while an anchored key shifted the block from [1] to [2] and
            # emptied the list - a fix whose own defect only appeared under the input it was written for.
            $keyRx = "(?m)^\s+paths:[ \t]*(?:&[^\s#]+)?[ \t]*(?:#.*)?$"
            $section | Should -Match $keyRx -Because "the $Filter trigger must use 'paths:' - 'paths-ignore:' would invert it"
            # Collect ONLY the list items under that key, stopping at the first line that is not one. That
            # stop is what makes a SECOND `paths:` key elsewhere in the section harmless - measured: with an
            # extra trigger's paths: inserted, this still collected the right block and stayed green.
            $block = ($section -split $keyRx)[1]
            $paths = @()
            foreach ($line in ($block -split "`r?`n")) {
                if ($line -match "^\s+- '([^']+)'") { $paths += $Matches[1] }
                elseif ($line.Trim()) { break }
            }
            $paths.Count | Should -BeGreaterThan 5 -Because 'a failed parse would make the assertion below vacuous'
            $missing = @($script:DomainRoots | Where-Object { "$_/**" -notin $paths })
            $missing -join ', ' | Should -BeExactly '' -Because "a domain root absent from the $Filter filter means CI never runs the gate on changes to it"
        }
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

        It 'does not flag a pointer whose referent is a heading in the SAME document' -ForEach @(
            @{ txt = "### Step 4 - Additional rounds`n`nEvery round (Step 4) must add a seat." }
            @{ txt = "## Task 5`n`nsee the contract doc (Task 5)." }
            @{ txt = "**Phase 3** begins here`n`nas (Phase 3) describes" }
        ) { (Test-HasPlanResidue -Text $txt) | Should -BeFalse -Because 'a pointer the reader can follow inside this document is a cross-reference, not residue' }

        It 'still flags a dangling pointer in a document that has OTHER resolvable headings' {
            # The mixed case. A referent check that gave the whole file a pass as soon as ANY heading
            # matched would let real residue ride along behind a legitimate cross-reference.
            (Test-HasPlanResidue -Text "### Step 4 - Additional rounds`n`nsee (Step 4) and also (Task 9).") |
                Should -BeTrue
        }

        It 'reports the DANGLING pointer, not the resolvable one that appears first' {
            $r = @(Get-PlanResidue -Text "### Step 4 - Additional rounds`n`nsee (Step 4) and also (Task 9).")
            $r.Count | Should -Be 1
            $r[0]    | Should -Be '(Task 9)' -Because 'naming (Step 4) would send the operator to a line that is correct'
        }

        It 'does not resolve "Step 1" against a "Step 12" heading' {
            (Test-HasPlanResidue -Text "### Step 12 - later`n`nsee (Step 1) here") | Should -BeTrue
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
    Context 'payload budget' {
        BeforeAll { . $script:Script -RepoRoot $script:RepoRoot }

        It 'extracts the message body from a msg= assignment' {
            $sh = @'
msg="ASSERTION-STRENGTH: hello there"
jq -nc --arg m "$msg" '{}'
'@
            (Get-HookMessages -Text $sh) | Should -Contain 'ASSERTION-STRENGTH: hello there'
        }
        It 'extracts a literal additionalContext payload too' {
            $sh = 'printf ''%s\n'' ''{"hookSpecificOutput":{"additionalContext":"[AGY-DISCIPLINES] guard inactive: missing jq"}}'''
            (Get-HookMessages -Text $sh) | Should -Contain '[AGY-DISCIPLINES] guard inactive: missing jq'
        }
        It 'finds the LONGEST branch, not the first' {
            $sh = @'
printf '%s\n' '{"hookSpecificOutput":{"additionalContext":"short"}}'
msg="this message is considerably longer than the degraded one"
'@
            (Get-LongestHookMessage -Text $sh).Length | Should -BeGreaterThan 20
        }
        It 'does not truncate a single-quoted body at bash''s quote-escape idiom' {
            $sh = "emit 'before the driver'`"'`"'s transport and a long tail after it'"
            $b = Get-LongestHookMessage -Text $sh
            $b | Should -Match 'long tail after it'
            $b | Should -Match "driver's transport"
        }
        It 'composes the jq wrapper with the NAMED variable only' {
            $sh = @'
msg='the real body'
other='unrelated body that must not be composed'
jq -nc --arg m "[TAG] $msg" '{}'
'@
            $all = @(Get-HookMessages -Text $sh)
            $all | Should -Contain '[TAG] the real body'
            $all | Should -Not -Contain '[TAG] unrelated body that must not be composed'
        }
        It 'does not mangle a body containing a dollar sign' {
            $sh = @'
msg='append task=$task to the line'
jq -nc --arg m "[TAG] $msg" '{}'
'@
            (Get-HookMessages -Text $sh) | Should -Contain '[TAG] append task=$task to the line'
        }
        It 'ignores a printf placeholder rather than treating it as a message' {
            $sh = 'printf ''{"hookSpecificOutput":{"additionalContext":"%s"}}\n'' "$msg"'
            (Get-HookMessages -Text $sh) | Should -Not -Contain '%s'
        }
        It 'does not truncate a double-quoted body at an escaped quote' {
            $sh = 'msg="before the \"quoted bit\" and a long tail after it"'
            (Get-LongestHookMessage -Text $sh) | Should -Match 'long tail after it'
        }
    }
    Context 'exemption lifecycle' {
        BeforeAll { . $script:Script -RepoRoot $script:RepoRoot }

        It 'rejects a blanket exemption with no named invariant' {
            { Assert-ExemptionShape -Entry ([pscustomobject]@{ path='x'; reason='y' }) } | Should -Throw
        }
        It 'rejects an exemption with an empty reason' {
            { Assert-ExemptionShape -Entry ([pscustomobject]@{ path='x'; invariant='encoding'; reason='' }) } |
                Should -Throw
        }
        It 'expands a twin-scoped key into BOTH plugin trees' {
            $paths = Expand-ExemptionPath -Entry ([pscustomobject]@{ path='skills/adversarial-panel-review/SKILL.md'; scope='twin-plugin' })
            $paths | Should -Contain 'clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md'
            $paths | Should -Contain 'clavity-classic/plugin/skills/adversarial-panel-review/SKILL.md'
            # Derived, not hardcoded: a third twin tree is a config change, not a test failure.
            $paths.Count | Should -Be $script:TwinPluginRoots.Count
        }
        It 'DERIVES the twin prefixes from $script:TwinPluginRoots rather than restating them' {
            # Capstone round 3. The twin-plugin pair was hardcoded in three places - the domain root list,
            # this expansion, and the reference canonicaliser - while Get-InjectedContextFiles' own error
            # message invites a maintainer to rename a root. Following that instruction left the other two
            # copies pointing at a path that no longer exists, and since the gate now throws on a missing
            # exemption path, it would have taken CI down. This row fails if anyone re-hardcodes them.
            $saved = $script:TwinPluginRoots
            try {
                $script:TwinPluginRoots = @('alpha/plugin', 'beta/plugin')
                $p = @(Expand-ExemptionPath -Entry ([pscustomobject]@{ path='skills/x/SKILL.md'; scope='twin-plugin' }))
                $p | Should -Be @('alpha/plugin/skills/x/SKILL.md', 'beta/plugin/skills/x/SKILL.md')
            } finally { $script:TwinPluginRoots = $saved }
        }

        It 'leaves a product-scoped key alone' {
            $paths = Expand-ExemptionPath -Entry ([pscustomobject]@{ path='ghidrust/plugin/skills/x/SKILL.md' })
            $paths | Should -Be @('ghidrust/plugin/skills/x/SKILL.md')
        }
        It 'REJECTS an exemption missing from ANY twin tree - order- and count-independent' {
            # THIS ROW HAS BEEN VACUOUS THREE TIMES. Round 4 created the file in NEITHER tree, so it could
            # not tell "throws when missing from one" from "throws only when missing from both". Round 5
            # created it in the SECOND, which a first-path-only implementation still satisfied (measured
            # 86/0). Round 6 parameterised it over Missing=0 and Missing=1 - which still only held for a
            # TWO-entry array: with three trees, an implementation that checks [0] and [1] but skips [2]
            # passes both iterations, because the file is missing from [0] or [1] either way.
            #
            # So the loop is over EVERY index, derived from the array. For each tree in turn, the file is
            # present in all the others and absent from that one, and the throw must fire. No ordering and
            # no count can defeat it: any implementation that skips even one expanded path fails the
            # iteration where that path is the missing one.
            for ($miss = 0; $miss -lt $script:TwinPluginRoots.Count; $miss++) {
                $d = Join-Path ([IO.Path]::GetTempPath()) ("icx-" + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'scripts') | Out-Null
                Copy-Item (Join-Path $script:RepoRoot 'scripts/injected-context-ignore.txt') (Join-Path $d 'scripts')
                foreach ($r in $script:DomainRoots) { New-Item -ItemType Directory -Force -Path (Join-Path $d $r) | Out-Null }
                Set-Content -LiteralPath (Join-Path $d 'scripts/injected-context-exemptions.json') -Encoding ascii -Value @'
{ "exemptions": [ { "path": "skills/nope/SKILL.md", "scope": "twin-plugin", "invariant": "encoding", "reason": "probe" } ] }
'@
                for ($i = 0; $i -lt $script:TwinPluginRoots.Count; $i++) {
                    if ($i -eq $miss) { continue }
                    $present = Join-Path $d "$($script:TwinPluginRoots[$i])/skills/nope/SKILL.md"
                    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $present) | Out-Null
                    Set-Content -LiteralPath $present -Value 'present in this tree' -Encoding ascii
                }
                { Get-InjectedContextViolations -RepoRoot $d } |
                    Should -Throw -ExpectedMessage '*does not exist*' -Because "the exemption is missing from tree $miss"
                Remove-Item -Recurse -Force $d
            }
        }

        It 'ENFORCES the blocklist - an exemption naming a blocklisted anomaly is refused' {
            # Capstone round 7, and the peer was RIGHT where I was wrong. I had rated this below the floor
            # on the grounds that $script:AnomalyBlocklist is deliberately empty, so the throw is
            # unreachable "by design". That conflated PRODUCTION state with TESTABILITY: the suite already
            # injects a blocklist tuple elsewhere in this file, so the enforcement branch is perfectly
            # reachable under test. Deleting that throw left the whole suite green, which is a real
            # coverage gap and not a consequence of the empty array.
            $saved = $script:AnomalyBlocklist
            $d = Join-Path ([IO.Path]::GetTempPath()) ("icb-" + [guid]::NewGuid().ToString('N'))
            try {
                $script:AnomalyBlocklist = @(@{ Path = 'seed/blocked.md'; Invariant = 'encoding' })
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'scripts') | Out-Null
                Copy-Item (Join-Path $script:RepoRoot 'scripts/injected-context-ignore.txt') (Join-Path $d 'scripts')
                foreach ($r in $script:DomainRoots) { New-Item -ItemType Directory -Force -Path (Join-Path $d $r) | Out-Null }
                Set-Content -LiteralPath (Join-Path $d 'seed/blocked.md') -Value 'x' -Encoding ascii
                Set-Content -LiteralPath (Join-Path $d 'scripts/injected-context-exemptions.json') -Encoding ascii -Value @'
{ "exemptions": [ { "path": "seed/blocked.md", "invariant": "encoding", "reason": "probe" } ] }
'@
                { Get-InjectedContextViolations -RepoRoot $d } |
                    Should -Throw -ExpectedMessage '*cannot be honoured*'
            } finally {
                $script:AnomalyBlocklist = $saved
                Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue
            }
        }

        It 'the blocklist is retired - no tuple remains' {
            $script:AnomalyBlocklist.Count | Should -Be 0 -Because 'every audited anomaly is fixed or ruled not-a-defect; the ordinary invariants carry the guarantee now'
        }
        It 'the blocklist MECHANISM still matches on both path suffix and invariant' {
            # The two rows this replaced asserted against the four live tuples, so retiring the data would
            # have left Test-IsBlocklisted - which is still called on every exemption - with no test at
            # all, and a future audit would re-populate an unverified matcher. Inject a list instead: this
            # pins the matching LOGIC rather than the retired DATA, and it is non-vacuous where an
            # assertion against the empty production list cannot be (everything is false in an empty list).
            $saved = $script:AnomalyBlocklist
            try {
                $script:AnomalyBlocklist = @(@{ Path = 'seed/probe.md'; Invariant = 'encoding' })
                (Test-IsBlocklisted -Path 'seed/probe.md'          -Invariant 'encoding') | Should -BeTrue
                # Suffix match, not equality - the twin-plugin paths arrive product-prefixed.
                (Test-IsBlocklisted -Path 'x/y/seed/probe.md'      -Invariant 'encoding') | Should -BeTrue
                # BOTH halves must match. An invariant-blind matcher would waive unrelated invariants.
                (Test-IsBlocklisted -Path 'seed/probe.md'          -Invariant 'reference') | Should -BeFalse
                (Test-IsBlocklisted -Path 'seed/unrelated.md'      -Invariant 'encoding')  | Should -BeFalse
            } finally { $script:AnomalyBlocklist = $saved }
        }
    }

    Context 'exemptions iterate independently of discovery' {
        BeforeAll {
            . $script:Script -RepoRoot $script:RepoRoot
            $script:Ex = (Get-Content (Join-Path $script:RepoRoot 'scripts/injected-context-exemptions.json') -Raw |
                          ConvertFrom-Json).exemptions
        }
        It 'every exemption names a path that exists on disk' {
            foreach ($e in $script:Ex) {
                foreach ($p in (Expand-ExemptionPath -Entry $e)) {
                    Test-Path (Join-Path $script:RepoRoot $p) |
                        Should -BeTrue -Because "exemption '$($e.path)' names a path that no longer exists"
                }
            }
        }
        It 'every exemption is still NEEDED - the file must fail the invariant without it' {
            # Dispatch on the invariant NAME. An earlier draft skipped anything that was not encoding,
            # which silently exempted every future non-encoding waiver from bidirectional validation -
            # the one rule that stops exemptions rotting. Today both entries are encoding; the guard has
            # to hold for the third.
            foreach ($e in $script:Ex) {
                foreach ($p in (Expand-ExemptionPath -Entry $e)) {
                    $full = Join-Path $script:RepoRoot $p
                    # GUARDED, AND THE GUARD IS THE POINT. This read was UNCONDITIONAL and ran BEFORE the
                    # dispatch below, so an `unreadable` waiver - the very waiver the gate PRINTS for that
                    # invariant - threw an unhandled IO exception right here and never reached the
                    # `default` arm that exists to tell a maintainer to add a case. An operator following
                    # the gate's own advice got a stack trace instead of guidance: the round-12 "advice
                    # that does not work" defect, re-made for a new invariant. Capstone round 18.
                    $text = $null
                    $readErr = $null
                    try { $text = [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8) }
                    catch [System.IO.IOException], [System.UnauthorizedAccessException] { $readErr = $_ }
                    # AN UNREADABLE FILE MAKES EVERY OTHER INVARIANT'S QUESTION UNANSWERABLE, and answering
                    # it anyway is worse than failing. MEASURED with $text null: Test-HasPlanResidue returns
                    # False, Get-HookMessages returns 0, Get-LongestHookMessage returns length 0 - so every
                    # text-based case would evaluate to $false, the row would report
                    # "unused exemption: ... passes without it", and a maintainer would DELETE a waiver that
                    # is still needed. The guarded read above fixed the round-18 crash and introduced this
                    # edge in the same stroke; before it, the read simply threw. Fail accurately instead.
                    if ($readErr -and $e.invariant -ne 'unreadable') {
                        throw "exemption '$p' names invariant '$($e.invariant)' but the file cannot be READ ($($readErr.Exception.GetType().Name)) - that invariant's question is unanswerable here, which is NOT the same as the exemption being unused"
                    }
                    $stillFails = switch ($e.invariant) {
                        'encoding'      { -not (Test-PureAscii -Path $full) }
                        'plan-residue'  { Test-HasPlanResidue -Text $text }
                        'tag-hygiene'   { [bool](@(Get-HookMessages -Text $text | Where-Object { Test-HasDuplicatedTag -Text $_ }).Count) }
                        'namespace'     { [bool](@(Get-HookMessages -Text $text | Where-Object { -not (Test-DegradedNamespace -Text $_) }).Count) }
                        # RE-RUN THE INVARIANT, exactly like every case above. My first version asked only
                        # "does the directory still exist", which is a weaker proxy and quietly defeats the
                        # whole point of this check. MEASURED: anchor that directory in the ignorelist and
                        # the gate stops reporting it - the waiver is DEAD - yet the directory still exists,
                        # so the proxy called it "needed" and the dead exemption would live forever. The
                        # bidirectional check only works if the question it asks is the real one.
                        'build-output'  { (Get-UnexpectedBuildDirs -RepoRoot $script:RepoRoot) -contains $p }
                        # Same walk, different report - the gate distinguishes a nested git checkout from
                        # build output because calling a worktree "build output" was a lie (round 18), but
                        # both come from the same function, so the "is it still reported" question is one.
                        'nested-checkout' { (Get-UnexpectedBuildDirs -RepoRoot $script:RepoRoot) -contains $p }
                        # RE-RUN THE INVARIANT, like every case above: the file still fails `unreadable`
                        # exactly when it still cannot be read. $readErr is set by the guarded read above.
                        'unreadable'    { $null -ne $readErr }
                        default         { throw "exemption names an unknown invariant '$($e.invariant)' - add a case here or fix the entry" }
                    }
                    $stillFails | Should -BeTrue -Because "unused exemption: '$($e.path)' passes '$($e.invariant)' without it"
                }
            }
        }
    }
    Context 'the gate actually audits the corpus' {
        BeforeAll {
            . $script:Script -RepoRoot $script:RepoRoot
            # No live-repo violation walk here. The draft that asserted against the real tree needed it;
            # every row now uses a hermetic fixture, so it would be a dead full-repository scan.
            $script:Corpus = Get-InjectedContextFiles -RepoRoot $script:RepoRoot

            $script:MakeFixture = {
                param([hashtable]$Files)   # relative path -> content
                $d = Join-Path ([IO.Path]::GetTempPath()) ("icv-" + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'scripts') | Out-Null
                # The ignorelist is COPIED - Get-IgnoreGlobs throws without it, and its globs are what the
                # fixtures exercise. The exemptions file is WRITTEN EMPTY rather than copied: the real one
                # names real repository files that do not exist inside a temp fixture, and the gate now
                # throws on an exemption path that is missing. Copying it was a hidden coupling anyway -
                # these rows test violation detection, not the shipped waivers.
                Copy-Item (Join-Path $script:RepoRoot 'scripts/injected-context-ignore.txt') (Join-Path $d 'scripts')
                Set-Content -LiteralPath (Join-Path $d 'scripts/injected-context-exemptions.json') `
                            -Value '{ "exemptions": [] }' -Encoding ascii
                # ALL SIX domain roots must exist. Discovery THROWS on a missing root - deliberately, so a
                # renamed product cannot silently drop coverage - and a fixture that creates only the root
                # it needs would trip that throw rather than exercise the walker. Two folds from different
                # review rounds, each right on its own, that only collide when the code actually runs.
                # DERIVED from $script:DomainRoots, never a hardcoded copy of it. Discovery THROWS on a
                # missing root - deliberately, so a renamed product cannot silently drop coverage - so a
                # fixture must create every root. This list was hardcoded once and broke the moment three
                # roots were added, which is the SECOND time these two correct decisions have collided
                # here (the first was noted in this file already). Deriving it ends the class.
                foreach ($r in $script:DomainRoots) {
                    New-Item -ItemType Directory -Force -Path (Join-Path $d $r) | Out-Null
                }
                foreach ($k in $Files.Keys) {
                    $p = Join-Path $d $k
                    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null
                    Set-Content -LiteralPath $p -Value $Files[$k] -Encoding ascii
                }
                $d
            }
        }

        It 'inspects a non-trivial number of files' {
            # MEASURED 2026-08-09: the six roots hold 130 files; 97 survive the ignorelist. The floor is
            # deliberately loose - other rows already assert SPECIFIC files are present, so this one
            # exists only to stop an empty or near-empty corpus making them vacuous.
            $script:Corpus.Count | Should -BeGreaterThan 40 -Because 'an empty corpus makes every row below vacuous'
        }

        It 'produces a violation record carrying file, invariant, finding and the waiver line' {
            $d = & $script:MakeFixture @{ 'seed/x.md' = 'see `doc/typo-prefix.md` here' }
            $v = @(Get-InjectedContextViolations -RepoRoot $d)[0]
            $v.File       | Should -Not -BeNullOrEmpty
            $v.Invariant  | Should -Not -BeNullOrEmpty
            $v.Finding    | Should -Not -BeNullOrEmpty
            $v.WaiverLine | Should -Match '"invariant"\s*:'
            Remove-Item -Recurse -Force $d
        }
        It 'names the specific file and invariant rather than only counting' {
            $d = & $script:MakeFixture @{ 'seed/dead.md' = 'the hook `agy-first-brainstorm.sh` does this' }
            $v = @(Get-InjectedContextViolations -RepoRoot $d)
            ($v | Where-Object { $_.File -eq 'seed/dead.md' -and $_.Invariant -eq 'reference' }) |
                Should -Not -BeNullOrEmpty -Because 'a broken reference must be named, not summed'
            Remove-Item -Recurse -Force $d
        }
        It 'aggregates - more than one file is reported, not just the first' {
            $d = & $script:MakeFixture @{
                'seed/a.md' = 'see `doc/typo-one.md`'
                'seed/b.md' = 'see `script/typo-two.ps1`'
            }
            $v = @(Get-InjectedContextViolations -RepoRoot $d)
            (@($v | Select-Object -ExpandProperty File -Unique)).Count |
                Should -Be 2 -Because 'a short-circuiting runner hides every failure after the first'
            Remove-Item -Recurse -Force $d
        }
        It 'ENFORCES the payload budget - an over-budget file produces a payload-budget violation' {
            # This row exercises the enforcement branch, not the extractor. An earlier draft asserted
            # Get-LongestHookMessage(...).Length -gt the cap, which proves only that the parser did not
            # truncate: delete or invert the comparison inside the walker and that assertion still passes.
            # Every shipped hook fits under the cap, so without this row nothing touches the branch.
            $d = & $script:MakeFixture @{ 'seed/oversized.sh' = ("msg='" + ('X' * ($script:MaxMessageChars + 1)) + "'") }
            $v = @(Get-InjectedContextViolations -RepoRoot $d)
            ($v | Where-Object { $_.Invariant -eq 'payload-budget' }) |
                Should -Not -BeNullOrEmpty -Because 'the enforcement branch must fire, not merely the parser'
            Remove-Item -Recurse -Force $d
        }
        It 'does NOT flag a file that is within budget' {
            # The must-pass half. Without it, a check hardcoded to always report payload-budget would
            # satisfy the row above.
            $d = & $script:MakeFixture @{ 'seed/small.sh' = "msg='short and clean'" }
            $v = @(Get-InjectedContextViolations -RepoRoot $d)
            ($v | Where-Object { $_.Invariant -eq 'payload-budget' }) | Should -BeNullOrEmpty
            Remove-Item -Recurse -Force $d
        }
    }
    Context 'the CLI contract - exit codes and operator output' {
        # Capstone round 7, Completeness Critic. Six rounds audited discovery, the reference index and the
        # invariant engine, and NONE of them touched Invoke-InjectedContextCheck - the layer that decides
        # the EXIT CODE. That code is the entire contract with CI and with the just recipe: everything
        # else in this file could be perfect and a wrong exit status would still ship the defect.
        #
        # It has to run as a CHILD PROCESS. The function calls `exit`, which would terminate the Pester
        # runner itself, so dot-sourcing cannot reach it - which is precisely why it had no coverage.
        BeforeAll {
            . $script:Script -RepoRoot $script:RepoRoot
            $script:NewGateFixture = {
                param([switch]$WithViolation)
                $d = Join-Path ([IO.Path]::GetTempPath()) ("icc-" + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'scripts') | Out-Null
                Copy-Item (Join-Path $script:RepoRoot 'scripts/injected-context-ignore.txt') (Join-Path $d 'scripts')
                Set-Content -LiteralPath (Join-Path $d 'scripts/injected-context-exemptions.json') -Value '{ "exemptions": [] }' -Encoding ascii
                foreach ($r in $script:DomainRoots) { New-Item -ItemType Directory -Force -Path (Join-Path $d $r) | Out-Null }
                if ($WithViolation) {
                    [IO.File]::WriteAllText((Join-Path $d 'seed/bad.md'), "em dash $([char]0x2014) here", (New-Object System.Text.UTF8Encoding($false)))
                }
                $d
            }
        }

        It 'exits 0 and says OK when the corpus is clean' {
            $d = & $script:NewGateFixture
            $out = & pwsh -NoProfile -File $script:Script -RepoRoot $d 2>&1 | Out-String
            $code = $LASTEXITCODE
            Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue
            $code | Should -Be 0 -Because 'CI and the just recipe both gate on this exit status'
            $out  | Should -Match 'check-injected-context: OK'
        }

        It 'exits 1 and names the file, the invariant and the waiver destination on a violation' {
            # Asserts the OPERATOR-FACING content, not just the status. A gate that fails without naming
            # what failed, or without saying where a waiver goes, sends people to the wrong fix - which is
            # how the round-4 Cold Operator walked into a broken JSON paste.
            $d = & $script:NewGateFixture -WithViolation
            $out = & pwsh -NoProfile -File $script:Script -RepoRoot $d 2>&1 | Out-String
            $code = $LASTEXITCODE
            Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue
            $code | Should -Be 1 -Because 'a violation must fail the build, not merely print'
            $out  | Should -Match 'seed/bad\.md'
            $out  | Should -Match 'encoding'
            $out  | Should -Match 'injected-context-exemptions\.json'
            $out  | Should -Match 'ADD A COMMA'
        }
    }
    Context 'round 8 - defects the peer proved with mutations the suite survived' {
        BeforeAll { . $script:Script -RepoRoot $script:RepoRoot }

        It 'survives a BRACKET in the repository path' {
            # A bracket is a WILDCARD to PowerShell's -Path parameters. Measured: a repo under a path
            # containing '[1]' threw "ignorelist missing" naming a file that was sitting right there,
            # before discovery even reached the domain roots. Reachable - Temp or a user directory can
            # legitimately contain one - and it fails the gate LOUDLY on correct content, which sends the
            # operator hunting a file that is not missing.
            $base = Join-Path ([IO.Path]::GetTempPath()) ("r8[1]-" + [guid]::NewGuid().ToString('N'))
            try {
                New-Item -ItemType Directory -Force -Path (Join-Path $base 'scripts') | Out-Null
                Copy-Item (Join-Path $script:RepoRoot 'scripts/injected-context-ignore.txt') (Join-Path $base 'scripts')
                Set-Content -LiteralPath (Join-Path $base 'scripts/injected-context-exemptions.json') -Value '{ "exemptions": [] }' -Encoding ascii
                foreach ($r in $script:DomainRoots) { New-Item -ItemType Directory -Force -Path (Join-Path $base $r) | Out-Null }
                Set-Content -LiteralPath (Join-Path $base 'seed/ok.md') -Value 'plain ascii' -Encoding ascii
                { Get-InjectedContextFiles -RepoRoot $base } | Should -Not -Throw
                @(Get-InjectedContextFiles -RepoRoot $base).Count | Should -BeGreaterThan 0
            } finally { Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It 'subtracts a git-worktree .git FILE - it is plumbing, not injected context' {
            # My round-6 disposition said this was harmless because '.git' is not a reference candidate.
            # That answered a DIFFERENT system: candidacy governs backticked text INSIDE a file, pruning
            # governs which files enter the corpus at all. Measured - a .git file carrying a BOM produced
            # a real encoding violation, so it was audited all along. The peer was right and I was wrong.
            $base = Join-Path ([IO.Path]::GetTempPath()) ("r8g-" + [guid]::NewGuid().ToString('N'))
            try {
                New-Item -ItemType Directory -Force -Path (Join-Path $base 'scripts') | Out-Null
                Copy-Item (Join-Path $script:RepoRoot 'scripts/injected-context-ignore.txt') (Join-Path $base 'scripts')
                Set-Content -LiteralPath (Join-Path $base 'scripts/injected-context-exemptions.json') -Value '{ "exemptions": [] }' -Encoding ascii
                foreach ($r in $script:DomainRoots) { New-Item -ItemType Directory -Force -Path (Join-Path $base $r) | Out-Null }
                [IO.File]::WriteAllText((Join-Path $base 'seed/.git'), 'gitdir: /elsewhere', (New-Object System.Text.UTF8Encoding($true)))
                @(Get-InjectedContextFiles -RepoRoot $base) | Should -Not -Contain 'seed/.git'
                @(Get-InjectedContextViolations -RepoRoot $base) | Should -BeNullOrEmpty
            } finally { Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It 'parses BOTH bash apostrophe-escape idioms - <Name>' -ForEach @(
            @{ Name = 'close-doublequote-reopen' ; Idiom = ([char]39 + [char]34 + [char]39 + [char]34 + [char]39) }
            @{ Name = 'close-backslash-reopen'   ; Idiom = ([char]39 + [char]92 + [char]39 + [char]39) }
        ) {
            # The peer proved the .Replace was unexercised: every budget fixture used a plain body, so the
            # parser only ever met one idiom. Measured before the fix - the backslash form returned
            # "hello", silently truncating at the apostrophe and under-reporting that hook's payload.
            $q    = [char]39
            $text = "msg=" + $q + "hello" + $Idiom + "world" + $q
            $body = Read-SingleQuotedBody -Text $text -Start ($text.IndexOf($q) + 1)
            $body | Should -BeExactly ("hello" + $q + "world")
        }

        It 'CACHES the reference index instead of rebuilding it per call' {
            # The peer named deleting the cache short-circuit as a mutation the whole suite survived, and
            # it was right: nothing asserted caching. The index is a full repository walk, so losing the
            # cache turns a per-token resolution back into the 5-minute behaviour this design replaced.
            $a = Get-ReferenceIndex -RepoRoot $script:RepoRoot
            $b = Get-ReferenceIndex -RepoRoot $script:RepoRoot
            [object]::ReferenceEquals($a, $b) | Should -BeTrue -Because 'the second call must return the cached instance, not a rebuild'
        }

        It 'emits a waiver line carrying the placeholder reason an operator must replace' {
            # Also unexercised: the rows asserted the waiver line had an "invariant" key but never its
            # CONTENT, so changing the placeholder to anything at all survived. The placeholder is the
            # instruction to the operator; if it silently became 'foo' the gate would be telling people to
            # paste a waiver with a meaningless justification.
            $v = New-Violation -File 'seed/x.md' -Invariant 'encoding' -Finding 'probe'
            $v.WaiverLine | Should -Match 'why this is deliberate'
            $v.WaiverLine | Should -Match 'seed/x\.md'
        }
    }
    Context 'round 10 - the gate itself must not be bypassable by a directory name' {
        BeforeAll { . $script:Script -RepoRoot $script:RepoRoot }

        It 'AUDITS a <Class> planted in a directory named after a build segment' -ForEach @(
            @{ Class = 'hook script'      ; Rel = 'clavity-dotnet/plugin/hooks/dist/evil-hook.sh' }
            @{ Class = 'knowledge manual' ; Rel = 'clavity-dotnet/plugin/knowledge/target/agy-notes.md' }
            @{ Class = 'rules file'       ; Rel = 'commonmemory/rules/bin/commonmemory.md' }
            @{ Class = 'golden header'    ; Rel = 'seed/obj/golden-header.md' }
            @{ Class = 'skill'            ; Rel = 'clavity-dotnet/plugin/skills/dist/SKILL.md' }
        ) {
            # ROUND 9 CLOSED THIS FOR SKILL.md ONLY, AND ONLY IN A TEST - the gate itself still exited 0.
            # Round 10 measured the rest: a hook, a knowledge manual, a rules file and the golden header,
            # each carrying a real em dash, each planted under a directory named after a pruned segment,
            # were ALL invisible. Corpus 0, violations 0, and every one of them still ships and is
            # injected into an agent.
            #
            # These rows assert the property at the GATE, not at the suite: the file must be in the corpus
            # AND must produce a violation. A row that only checked corpus membership would pass against a
            # gate that collected the file and then audited nothing.
            $d = Join-Path ([IO.Path]::GetTempPath()) ("icb10-" + [guid]::NewGuid().ToString('N'))
            try {
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'scripts') | Out-Null
                Copy-Item (Join-Path $script:RepoRoot 'scripts/injected-context-ignore.txt') (Join-Path $d 'scripts')
                Set-Content -LiteralPath (Join-Path $d 'scripts/injected-context-exemptions.json') -Value '{ "exemptions": [] }' -Encoding ascii
                foreach ($r in $script:DomainRoots) { New-Item -ItemType Directory -Force -Path (Join-Path $d $r) | Out-Null }
                $full = Join-Path $d $Rel
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
                [IO.File]::WriteAllText($full, "smuggled text with an em dash $([char]0x2014) in it", (New-Object System.Text.UTF8Encoding($false)))

                # THE PROPERTY IS "THE GATE REPORTS IT", not "the file is in the corpus". Round 11 changed
                # how: a build-named directory inside a domain root is now reported as one build-output
                # violation instead of having its contents audited, because auditing a local bin/ or
                # node_modules/ drowned the encoding invariant in binary noise - measured, four artifacts,
                # four encoding failures, on a machine that had merely run a build. Either way the gate
                # fails and names the path; asserting corpus membership would pin the mechanism instead of
                # the guarantee, and this row has to survive the next change to that mechanism.
                $v = @(Get-InjectedContextViolations -RepoRoot $d)
                $v | Should -Not -BeNullOrEmpty -Because 'smuggling into a build-named directory must fail the gate'
                ($v | Where-Object { $Rel -like ($_.File + '*') -or $_.File -eq $Rel }) |
                    Should -Not -BeNullOrEmpty -Because 'the report must name the smuggled path or the directory holding it'
            } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
        }


It 'a build-output violation can actually be WAIVED with the line the gate prints' {
            # Capstone round 12, highest severity. Every other invariant is waivable and this one printed a
            # waiver line while ignoring it - MEASURED, pasting the gate's own suggested waiver produced the
            # identical violation on the next run. A gate that tells you how to proceed and then refuses is
            # worse than one that offers nothing: it costs a debugging session to learn the advice was false.
            $d = Join-Path ([IO.Path]::GetTempPath()) ("icw-" + [guid]::NewGuid().ToString('N'))
            try {
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'scripts') | Out-Null
                Copy-Item (Join-Path $script:RepoRoot 'scripts/injected-context-ignore.txt') (Join-Path $d 'scripts')
                foreach ($r in $script:DomainRoots) { New-Item -ItemType Directory -Force -Path (Join-Path $d $r) | Out-Null }
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'clavity-dotnet/plugin/bin') | Out-Null
                Set-Content -LiteralPath (Join-Path $d 'scripts/injected-context-exemptions.json') -Encoding ascii -Value @'
{ "exemptions": [ { "path": "clavity-dotnet/plugin/bin", "invariant": "build-output", "reason": "probe" } ] }
'@
                @(Get-InjectedContextViolations -RepoRoot $d) |
                    Should -BeNullOrEmpty -Because 'the waiver the gate itself prints must actually work'
            } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It 'a directory junction pointing at an ancestor does not walk forever' {
            # Capstone round 17. BOTH walks descend with a manual stack and NEITHER had a visited-set, so a
            # junction pointing at an ancestor had nothing to stop it. MEASURED against the pre-fix script on
            # this exact fixture: it had still not returned after 45 seconds, while the fixed one returns a
            # corpus of 1. Deduping on FullName alone does NOT terminate - every lap produces a new path
            # (seed/sub/loop/sub/loop/...) - so the guard resolves the reparse TARGET and dedupes on that.
            #
            # RUN IN A JOB WITH A TIMEOUT, deliberately. If this guard regresses the walk does not fail, it
            # HANGS, and a hang inside Pester wedges the whole suite instead of reddening one row. The
            # timeout converts a regression back into an ordinary failure.
            $d = Join-Path ([IO.Path]::GetTempPath()) ("icj-" + [guid]::NewGuid().ToString('N'))
            $j = $null
            try {
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'scripts') | Out-Null
                Copy-Item (Join-Path $script:RepoRoot 'scripts/injected-context-ignore.txt') (Join-Path $d 'scripts')
                Set-Content -LiteralPath (Join-Path $d 'scripts/injected-context-exemptions.json') -Value '{ "exemptions": [] }' -Encoding ascii
                foreach ($r in $script:DomainRoots) { New-Item -ItemType Directory -Force -Path (Join-Path $d $r) | Out-Null }
                Set-Content -LiteralPath (Join-Path $d 'seed/a.md') -Value 'hello' -Encoding ascii
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'seed/sub') | Out-Null
                cmd /c mklink /J "$(Join-Path $d 'seed\sub\loop')" "$(Join-Path $d 'seed')" | Out-Null
                # A junction needs no elevation, but if the filesystem ever refuses one this row would pass
                # vacuously against a walk that never met a cycle. Fail loudly instead.
                (Test-Path -LiteralPath (Join-Path $d 'seed/sub/loop')) |
                    Should -BeTrue -Because 'the fixture needs a REAL junction or this row proves nothing'

                $j = Start-Job { param($s, $dd) . $s -RepoRoot $dd; @(Get-InjectedContextFiles -RepoRoot $dd).Count } -ArgumentList $script:Script, $d
                (Wait-Job $j -Timeout 60) | Should -Not -BeNullOrEmpty -Because 'the corpus walk must TERMINATE on a junction cycle'
                (Receive-Job $j) | Should -Be 1 -Because 'seed/a.md is the only corpus file - the junction must not multiply or re-audit it'
            } finally {
                if ($j) { Stop-Job $j -ErrorAction SilentlyContinue; Remove-Job $j -Force -ErrorAction SilentlyContinue }
                # REMOVE THE LINK ITSELF FIRST. A recursive delete that follows a junction deletes the
                # TARGET's contents, and the target here is the fixture's own seed/ - rmdir removes the
                # reparse point without touching what it points at.
                cmd /c rmdir "$(Join-Path $d 'seed\sub\loop')" 2>&1 | Out-Null
                Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'a corpus file that cannot be READ is reported as a violation, not thrown' {
            # Capstone round 17. The gate had THREE unguarded read sites - Test-PureAscii's ReadAllBytes,
            # Get-NonAsciiReport's ReadAllText, and the violation loop's own ReadAllText. MEASURED against
            # the pre-fix script on this fixture: an exclusively-locked corpus file threw out of the loop and
            # killed the gate, escaping through NEITHER documented exit - a stack trace where the gate
            # promises a violation report. The window is real, not theoretical: the walk enumerates and the
            # loop reads, so anything touching the tree in between (an editor lock, a delete) lands in it.
            #
            # REPORTED, NEVER SKIPPED. Skipping would mark a file the gate never read as passing, which is
            # the fail-open this gate exists to catch.
            $d = Join-Path ([IO.Path]::GetTempPath()) ("icu-" + [guid]::NewGuid().ToString('N'))
            $fs = $null
            try {
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'scripts') | Out-Null
                Copy-Item (Join-Path $script:RepoRoot 'scripts/injected-context-ignore.txt') (Join-Path $d 'scripts')
                Set-Content -LiteralPath (Join-Path $d 'scripts/injected-context-exemptions.json') -Value '{ "exemptions": [] }' -Encoding ascii
                foreach ($r in $script:DomainRoots) { New-Item -ItemType Directory -Force -Path (Join-Path $d $r) | Out-Null }
                Set-Content -LiteralPath (Join-Path $d 'seed/locked.md') -Value 'content' -Encoding ascii
                # FileShare.None - the same exclusive lock another process holds on a file it is writing.
                $fs = [System.IO.File]::Open((Join-Path $d 'seed/locked.md'), 'Open', 'Read', 'None')
                $v = @(Get-InjectedContextViolations -RepoRoot $d)
                ($v | Where-Object { $_.Invariant -eq 'unreadable' -and $_.File -eq 'seed/locked.md' }) |
                    Should -Not -BeNullOrEmpty -Because 'an unreadable corpus file must be NAMED, not skipped and not thrown'
            } finally {
                if ($fs) { $fs.Dispose() }
                Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'an unreadable violation can be WAIVED like every other invariant' {
            # An unwaivable violation was itself a folded defect (build-output, capstone round 12), so a new
            # invariant that could not be waived would re-make it. Note the consequence, which is deliberate:
            # waiving this one waives the file ENTIRELY, because no invariant can run on bytes nobody can read.
            $d = Join-Path ([IO.Path]::GetTempPath()) ("icuw-" + [guid]::NewGuid().ToString('N'))
            $fs = $null
            try {
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'scripts') | Out-Null
                Copy-Item (Join-Path $script:RepoRoot 'scripts/injected-context-ignore.txt') (Join-Path $d 'scripts')
                foreach ($r in $script:DomainRoots) { New-Item -ItemType Directory -Force -Path (Join-Path $d $r) | Out-Null }
                Set-Content -LiteralPath (Join-Path $d 'seed/locked.md') -Value 'content' -Encoding ascii
                Set-Content -LiteralPath (Join-Path $d 'scripts/injected-context-exemptions.json') -Encoding ascii -Value @'
{ "exemptions": [ { "path": "seed/locked.md", "invariant": "unreadable", "reason": "probe" } ] }
'@
                $fs = [System.IO.File]::Open((Join-Path $d 'seed/locked.md'), 'Open', 'Read', 'None')
                @(Get-InjectedContextViolations -RepoRoot $d) |
                    Should -BeNullOrEmpty -Because 'the waiver line the gate prints for unreadable must actually work'
            } finally {
                if ($fs) { $fs.Dispose() }
                Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'no ignore glob matches an arbitrary directory probe path' {
            # Descent is skipped when "$rel/__probe__" matches a glob, so a glob able to match ANY probe
            # would empty the corpus and pass the gate green over nothing. None can today - this row is
            # what stops one being added. Measured: 0 of the current globs match a synthetic probe.
            $globs = @(Get-IgnoreGlobs -RepoRoot $script:RepoRoot)
            $matched = @($globs | Where-Object { Test-IsIgnored -RelPath 'no/such/dir/__probe__' -Globs @($_) })
            $matched -join ', ' | Should -BeExactly '' -Because 'a glob matching every probe path would silently empty the corpus'
        }

        It 'REPORTS build output inside a domain root instead of auditing or hiding it' {
            # Capstone round 11. Round 10 removed name-based pruning to close the bypass, and the peer
            # spotted the trade immediately: a developer's local bin/, obj/, node_modules/ or .vs/ inside
            # a domain root was then fully audited. MEASURED - four binary artifacts, four encoding
            # failures, on a machine that had merely run a build. Auditing binaries is noise; skipping
            # them silently is the bypass. Naming the directory is neither.
            $d = Join-Path ([IO.Path]::GetTempPath()) ("icbo-" + [guid]::NewGuid().ToString('N'))
            try {
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'scripts') | Out-Null
                Copy-Item (Join-Path $script:RepoRoot 'scripts/injected-context-ignore.txt') (Join-Path $d 'scripts')
                Set-Content -LiteralPath (Join-Path $d 'scripts/injected-context-exemptions.json') -Value '{ "exemptions": [] }' -Encoding ascii
                foreach ($r in $script:DomainRoots) { New-Item -ItemType Directory -Force -Path (Join-Path $d $r) | Out-Null }
                $bin = Join-Path $d 'clavity-dotnet/plugin/bin'
                New-Item -ItemType Directory -Force -Path $bin | Out-Null
                [IO.File]::WriteAllBytes((Join-Path $bin 'artifact.bin'), [byte[]](0x00,0xFF,0xFE,0x80))

                @(Get-InjectedContextFiles -RepoRoot $d) |
                    Should -Not -Contain 'clavity-dotnet/plugin/bin/artifact.bin' -Because 'binaries must not be audited byte by byte'
                $v = @(Get-InjectedContextViolations -RepoRoot $d)
                ($v | Where-Object { $_.Invariant -eq 'build-output' -and $_.File -eq 'clavity-dotnet/plugin/bin' }) |
                    Should -Not -BeNullOrEmpty -Because 'the directory itself is the defect worth naming'
            } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It 'still subtracts the REAL build directories, by anchored path' -ForEach @(
            @{ Rel = 'agy-autotrain/dist/x.md' }
            @{ Rel = 'commonmemory/dist/x.md' }
            @{ Rel = 'clavity-classic/agy-mcp-bridge/.venv/Lib/site-packages/absl/app.py' }
            @{ Rel = 'clavity-classic/agy-mcp-bridge/__pycache__/x.pyc' }
            @{ Rel = 'agy-autotrain/docs/fix-the-tool-backlog/.ruff_cache/CACHEDIR.TAG' }
        ) {
            # The other half of the same fix. Anchoring only closes the bypass if it still removes the
            # build output it replaced - otherwise the corpus grows by a virtualenv. Measured: the corpus
            # is 99 before and after the change.
            (Test-IsIgnored -RelPath $Rel -Globs (Get-IgnoreGlobs -RepoRoot $script:RepoRoot)) |
                Should -BeTrue -Because 'the anchored globs must still subtract real build output'
        }

        It 'has NO unanchored build-directory glob left in the ignorelist' {
            # The subtraction itself was the second half of the vector: an unanchored **/dist/** re-opened
            # the hole after pruning was removed from the corpus walk. This row stops one being re-added.
            $globs = @(Get-IgnoreGlobs -RepoRoot $script:RepoRoot)
            $bad = @($globs | Where-Object { $_ -match '^\*\*/(dist|publish|target|bin|obj|node_modules|\.venv|__pycache__)/' })
            $bad -join ', ' | Should -BeExactly '' -Because 'a build glob matching by NAME at any depth is a bypass; anchor it to the real path'
        }
    }
}

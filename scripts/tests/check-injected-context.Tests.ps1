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
                    Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|target|bin|obj|\.venv|__pycache__|dist|publish|\.vs|\.clavity)[\\/]' } |
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
            $paths.Count | Should -Be 2
        }
        It 'leaves a product-scoped key alone' {
            $paths = Expand-ExemptionPath -Entry ([pscustomobject]@{ path='ghidrust/plugin/skills/x/SKILL.md' })
            $paths | Should -Be @('ghidrust/plugin/skills/x/SKILL.md')
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
                    $text = [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
                    $stillFails = switch ($e.invariant) {
                        'encoding'      { -not (Test-PureAscii -Path $full) }
                        'plan-residue'  { Test-HasPlanResidue -Text $text }
                        'tag-hygiene'   { [bool](@(Get-HookMessages -Text $text | Where-Object { Test-HasDuplicatedTag -Text $_ }).Count) }
                        'namespace'     { [bool](@(Get-HookMessages -Text $text | Where-Object { -not (Test-DegradedNamespace -Text $_) }).Count) }
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
                # BOTH control files. Get-IgnoreGlobs THROWS without the ignorelist, so copying only the
                # exemptions file makes every fixture row throw instead of testing anything.
                foreach ($f in 'injected-context-exemptions.json', 'injected-context-ignore.txt') {
                    Copy-Item (Join-Path $script:RepoRoot "scripts/$f") (Join-Path $d 'scripts')
                }
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
}

Describe 'agy-consult-guard' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Pre  = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh'
        $script:Post = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh'
        # The largest of the three and the one carrying the snapshot logic, yet it was bound by nothing:
        # pre/post exercise it by sourcing it, so its BEHAVIOUR was covered, but every FILE-level assertion
        # below silently skipped it.
        $script:Lib  = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh'
        $script:Classic = Join-Path $repoRoot 'clavity-classic/plugin/hooks'

        function New-GuardRepo {
            $d = Join-Path ([IO.Path]::GetTempPath()) ("guard-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            Push-Location $d
            git init -q .; git config user.email t@t; git config user.name t
            Set-Content (Join-Path $d 'a.txt') 'one' -Encoding ascii
            git add a.txt; git commit -qm init
            Pop-Location
            return $d
        }
        function Payload { param([string]$Tool, [string]$Cmd, [string]$Cwd)
            @{ tool_name = $Tool; tool_input = @{ command = $Cmd }; cwd = ($Cwd -replace '\\','/'); session_id = 'guardtest' } | ConvertTo-Json -Compress
        }
        # Run a consult around a scriptblock that mutates the repo; return the post hook's stdout.
        # Defined HERE, not in the Describe body: MEASURED under Pester 6.1.0 with a paired control,
        # a function declared in the Describe body is not visible inside an It at run time
        # (CommandNotFoundException), while one declared in BeforeAll is. New-GuardRepo and Payload
        # above are in BeforeAll for the same reason.
        function Invoke-ConsultAround {
            param([string]$Repo, [scriptblock]$Between)
            $p = Payload 'mcp__plugin_clavity_clavity-ls__agy_ask' '' $Repo
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            & $Between
            return (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
        }
    }

    It 'WARNS when version control changes across an MCP consult' {
        # The primary path. The guard was dead here for an unknown period because its matcher named a
        # tool id that no longer exists, and a dead hook cannot report its own absence.
        $r = New-GuardRepo
        try {
            $p = Payload 'mcp__plugin_clavity_clavity-ls__agy_ask' '' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'b.txt' 'two' -Encoding ascii; git add b.txt; git commit -qm peer; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'names the concurrent-local-agent confound in the breach warning' {
        # The guard detects a VCS delta across the consult window. It CANNOT attribute that delta to the
        # peer rather than to anything else running in the same repository at the same time.
        # MEASURED 2026-08-07: it fired naming the three files a local implementer subagent was mid-edit on,
        # one carrying a deliberate temporary mutation, while the peer had changed nothing.
        # This matters because the message's next instruction is a revert: a driver who acts on it without
        # verifying would destroy that subagent's in-flight work.
        $r = New-GuardRepo
        try {
            $p = Payload 'mcp__plugin_clavity_clavity-ls__agy_ask' '' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'b.txt' 'two' -Encoding ascii; git add b.txt; git commit -qm peer; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Match 'VERSION CONTROL CHANGED' -Because 'the existing alarm must still fire'
            $out | Should -Match 'CANNOT attribute'
            $out | Should -Match 'concurrent'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT across an MCP consult that changed nothing' {
        $r = New-GuardRepo
        try {
            $p = Payload 'mcp__plugin_clavity_clavity-ls__agy_ask' '' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Not -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'WARNS when version control changes across a CLI consult' {
        $r = New-GuardRepo
        try {
            $p = Payload 'Bash' 'clavity ask "review this"' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'c.txt' 'three' -Encoding ascii; git add c.txt; git commit -qm peer; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT treat a commit whose MESSAGE mentions the consult CLI as a consult' {
        # The false-positive that trained the operator to ignore the guard. Two identical commits
        # differing only in message text gave warn vs silent.
        $r = New-GuardRepo
        try {
            $p = Payload 'Bash' 'git commit -m "docs: explain clavity ask usage"' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'd.txt' 'four' -Encoding ascii; git add d.txt; git commit -qm mine; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Not -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'WARNS when the consult CLI is invoked as clavity.exe' {
        # Capstone round 1: MEASURED silent before the anchor allowed a .exe suffix. On Windows this is
        # the literal executable name, so the guard did not exist for the most likely local invocation.
        $r = New-GuardRepo
        try {
            $p = Payload 'Bash' 'clavity.exe ask "review this"' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'e.txt' 'five' -Encoding ascii; git add e.txt; git commit -qm peer; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'WARNS when the consult CLI is invoked by an absolute path' {
        # Capstone round 1: MEASURED silent before the anchor allowed a path prefix.
        $r = New-GuardRepo
        try {
            $p = Payload 'Bash' '/usr/bin/clavity ask "review this"' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'f.txt' 'six' -Encoding ascii; git add f.txt; git commit -qm peer; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT treat a parenthesised mention as a consult' {
        # Pins a DELIBERATE non-widening. Adding "(" to the separator class would catch the capture form
        # X=$(clavity ask ...), but MEASURED exactly one-for-one it would also make this string warn.
        # A false alarm is what trained the operator to ignore this guard, so the capture form is left
        # undetected on purpose. If someone widens the anchor to "(", this test is the thing that objects.
        $r = New-GuardRepo
        try {
            $p = Payload 'Bash' 'echo "(clavity ask )"' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'g.txt' 'seven' -Encoding ascii; git add g.txt; git commit -qm mine; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Not -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'ships as pure ASCII' {
        foreach ($f in @($script:Pre, $script:Post, $script:Lib)) {
            ($([IO.File]::ReadAllBytes($f)) | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        }
    }

    It 'is byte-identical to the clavity-classic mirror' {
        foreach ($f in @($script:Pre, $script:Post, $script:Lib)) {
            $mirror = Join-Path $script:Classic (Split-Path -Leaf $f)
            Test-Path -LiteralPath $mirror | Should -BeTrue -Because "$(Split-Path -Leaf $f) must ship in both drivers"
            [IO.File]::ReadAllBytes($mirror) | Should -Be ([IO.File]::ReadAllBytes($f)) -Because 'the two drivers ship the same guard'
        }
    }

    It 'deliberately does NOT honour .no-agy, in either half' {
        # NOT an oversight, and until now only a comment said so. .no-agy is a file IN THE REPO, so a
        # review-only consult that mutated version control could create it and thereby hide its own write:
        # post.sh would exit before diffing. A guard the untrusted actor can switch off is not a guard.
        # Without this test, a later "consistency" pass that adds the kill-switch to these three files -
        # the obvious-looking change, since every sibling hook honours it - would be a silent hole with
        # nothing to catch it.
        $r = New-GuardRepo
        try {
            New-Item -ItemType File -Path (Join-Path $r '.no-agy') -Force | Out-Null
            $p = Payload 'mcp__plugin_clavity_clavity-ls__agy_ask' '' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'b.txt' 'two' -Encoding ascii; git add b.txt; git commit -qm peer; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            # AGY-TEST-AUDIT 2026-08-31. This assertion used to be `-Match 'CONSULT GUARD'`, and that
            # is a needle the FAILURE banner also contains: post.sh:55 emits "AGY CONSULT GUARD - NOT
            # VERIFIED (guard failed to initialize)" when no baseline exists. MEASURED - patch pre.sh to
            # honour .no-agy and it writes no baseline, so post.sh took that branch, the row matched it
            # and passed GREEN while the mutation check never ran at all. The row promised in its own
            # comment to catch exactly that change and did not. Assert the DETECTION phrase, and reject
            # the initialize-failure route explicitly so the row can never again pass by it.
            $out | Should -Match 'VERSION CONTROL CHANGED' -Because 'a .no-agy in the repo must not be able to silence the guard that watches the repo'
            $out | Should -Match 'committed-HEAD' -Because 'the commit made during the consult is what the guard must name'
            $out | Should -Not -Match 'guard failed to initialize' -Because 'passing via the no-baseline banner is the confound this row exists to exclude'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # --- the ignored-paths axis (roadmap: review-only envelope) -------------------------------
    # git status --porcelain OMITS ignored files, which is why every one of these was invisible.

    It 'WARNS when the .clavity shield file is emptied' {
        # The shield is a bare '*'. Empty it and .clavity/ becomes visible to git, so the next
        # `git add .` publishes untriaged anomalies. Highest-consequence silent change there is.
        #
        # WHAT THIS ROW ACTUALLY PINS is the OUTCOME - that emptying the shield warns - NOT the
        # dedicated `.clavity/.gitignore` component of agy_guard_ignored. MEASURED: replacing that
        # component with a constant leaves this row green, because .gitignore is a top-level entry
        # in .clavity/ and the census covers it anyway. The component is redundant with the census
        # by construction, and that redundancy is deliberate defence in depth - but a row cannot
        # claim to guard a component that another component already guards. The direct coverage for
        # the component's building block is the agy_guard_file_state row below.
        $r = New-GuardRepo
        try {
            New-Item -ItemType Directory -Path (Join-Path $r '.clavity') -Force | Out-Null
            Set-Content (Join-Path $r '.clavity/.gitignore') '*' -Encoding ascii -NoNewline
            $out = Invoke-ConsultAround $r { Set-Content (Join-Path $r '.clavity/.gitignore') '' -Encoding ascii -NoNewline }
            $out | Should -Match 'VERSION CONTROL CHANGED'
            $out | Should -Match 'gitignored paths'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'WARNS when a payload is dropped into .clavity at top level' {
        # The name census. A content hash of named paths alone would never see a NEW file.
        $r = New-GuardRepo
        try {
            New-Item -ItemType Directory -Path (Join-Path $r '.clavity') -Force | Out-Null
            Set-Content (Join-Path $r '.clavity/.gitignore') '*' -Encoding ascii -NoNewline
            $out = Invoke-ConsultAround $r { Set-Content (Join-Path $r '.clavity/backdoor.ps1') 'evil' -Encoding ascii }
            $out | Should -Match 'gitignored paths'
            $out | Should -Match 'backdoor\.ps1'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'WARNS when an existing top-level .clavity file is silently overwritten' {
        # Names-only would have missed this: the entry list is unchanged, the CONTENT is not.
        $r = New-GuardRepo
        try {
            New-Item -ItemType Directory -Path (Join-Path $r '.clavity') -Force | Out-Null
            Set-Content (Join-Path $r '.clavity/.gitignore') '*' -Encoding ascii -NoNewline
            Set-Content (Join-Path $r '.clavity/agy-model') 'original' -Encoding ascii
            $out = Invoke-ConsultAround $r { Set-Content (Join-Path $r '.clavity/agy-model') 'hijacked' -Encoding ascii }
            $out | Should -Match 'gitignored paths'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'WARNS when a named sensitive path outside .clavity is written' {
        $r = New-GuardRepo
        try {
            New-Item -ItemType Directory -Path (Join-Path $r '.claude') -Force | Out-Null
            Set-Content (Join-Path $r '.claude/settings.local.json') '{}' -Encoding ascii
            $out = Invoke-ConsultAround $r { Set-Content (Join-Path $r '.claude/settings.local.json') '{"x":1}' -Encoding ascii }
            $out | Should -Match 'gitignored paths'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT when only the concurrent-append targets change' {
        # THE FALSE-POSITIVE GUARD, and the row most likely to be got wrong. local-anomalies.md is
        # appended by the open-issues capture path and discipline-reaching.jsonl once per session,
        # both from OTHER sessions on the same repo. Hashing their contents would accuse this
        # session's peer of a breach every time a second session captured an anomaly.
        $r = New-GuardRepo
        try {
            New-Item -ItemType Directory -Path (Join-Path $r '.clavity') -Force | Out-Null
            Set-Content (Join-Path $r '.clavity/.gitignore') '*' -Encoding ascii -NoNewline
            Set-Content (Join-Path $r '.clavity/local-anomalies.md') "# h" -Encoding ascii
            Set-Content (Join-Path $r '.clavity/discipline-reaching.jsonl') "{}" -Encoding ascii
            New-Item -ItemType Directory -Path (Join-Path $r '.clavity/scratch/t') -Force | Out-Null
            $out = Invoke-ConsultAround $r {
                Add-Content (Join-Path $r '.clavity/local-anomalies.md') '- [defect] x * n/a * 2026-08-30 * task=t'
                Add-Content (Join-Path $r '.clavity/discipline-reaching.jsonl') '{"v":3}'
                Set-Content (Join-Path $r '.clavity/scratch/t/notes.md') 'peer working' -Encoding ascii
            }
            # Assert the SPECIFIC warning is absent, not merely that output is empty: an empty
            # assertion cannot tell silence from one of the three other warnings this hook emits.
            $out | Should -Not -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does not report a CLEAN consult when the axis could not be read at all' {
        # THE FIXTURE ORDERING IS THE ENTIRE ROW. .clavity/ is absent BEFORE pre and still absent at
        # post, so both sides observe the same failure. A naive implementation returns the same empty
        # value twice, they compare EQUAL, and the guard reports clean - the exact false confidence
        # this axis exists to remove. An "unreadable only between pre and post" fixture would pass on
        # that defective code, because PRE would hold a real digest and POST a sentinel.
        $r = New-GuardRepo
        try {
            $out = Invoke-ConsultAround $r { Set-Content (Join-Path $r 'c.txt') 'x' -Encoding ascii }
            # The tracked-file change must still be reported, and the absent axis must not
            # manufacture a false ignored-path accusation.
            $out | Should -Match 'VERSION CONTROL CHANGED'
            $out | Should -Not -Match 'gitignored paths'
            # MEASURED VACUITY, and why this half exists. The two assertions above are satisfied by
            # the c.txt change alone: under a mutant that made an absent file contribute an EMPTY
            # string instead of the ABSENT sentinel, both still held and this row stayed GREEN. They
            # cannot see the distinction they were written to pin. Assert the contract DIRECTLY -
            # every component of a bare repo's axis must be an explicit sentinel, never empty, so
            # "I could not look" can never encode identically to "nothing changed".
            $sh = "set +e; . '$($script:Lib -replace '\\','/')'; agy_guard_ignored '$($r -replace '\\','/')'"
            (& bash -lc $sh) | Should -Be 'ABSENT:ABSENT:ABSENT:ABSENT'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'emits an eight-component fingerprint' {
        # Structural, not a string match: count the '|' separators the lib actually prints.
        $r = New-GuardRepo
        try {
            $sh = "set +e; . '$($script:Lib -replace '\\','/')'; agy_guard_quad '$($r -replace '\\','/')'"
            $fp = & bash -lc $sh
            (($fp -split '\|').Count) | Should -Be 8
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'never emits either delimiter inside the ignored axis' {
        # Both delimiters. Banning only '|' leaves 'ERROR:UNREADABLE'-shaped sentinels free to
        # shatter the INNER parse and misalign the components at post.
        #
        # THE FIXTURE NAME IS LOAD-BEARING, and it is NOT the obvious one. A name containing '|' or
        # ':' cannot be created on Windows at all, so a fixture using those characters would leave NO
        # file behind and the row would assert against an empty census - passing identically whether
        # the sanitizer exists or not. ',' and '=' ARE legal Windows filename characters and are
        # sanitized by the same tr, so they exercise the real code path on this platform. They also
        # happen to be the census's OWN encoding characters ('name=state,'), which is the inner parse
        # an unsanitized name would shatter first.
        $r = New-GuardRepo
        try {
            New-Item -ItemType Directory -Path (Join-Path $r '.clavity') -Force | Out-Null
            Set-Content (Join-Path $r '.clavity/we,ird=name.txt') 'x' -Encoding ascii
            $sh = "set +e; . '$($script:Lib -replace '\\','/')'; agy_guard_ignored '$($r -replace '\\','/')'"
            $ax = & bash -lc $sh
            ($ax -split ':').Count | Should -Be 4
            # There is deliberately NO `Should -Not -Match '\|'` here: '|' cannot occur in a Windows
            # filename, so the fixture could never introduce one and the assertion could not fail.
            #
            # THIS ROW ONLY EVER COVERED ',' AND '='. An earlier version of this comment claimed all
            # four reserved characters were "stripped by the same single tr" and were therefore
            # covered - the tr had already been replaced by five independent replacements, and
            # MEASURED, deleting the two that encode '|' and ':' left the whole suite GREEN at 35/35.
            # The guarantee for those two now comes from the DIRECT encoder test below, which calls
            # agy_guard_encode_name with strings the filesystem would never accept as names.
            # Positive control: prove the sanitiser actually ran, rather than inferring it from the
            # absence of a character the fixture may never have produced. The encoding is
            # PERCENT-ENCODING, not replacement with '_': see the collision row below for why.
            $ax | Should -Match 'we%2Cird%3Dname\.txt'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'names the degraded axes instead of carrying a count that can rot' {
        # The message previously said "4 of 7 axes" while also saying "only HEAD and stash were
        # compared" - which implies 5. MEASURED: agy_guard_hash had 5 call sites. A maintained
        # number is what rotted; an enumeration cannot go out of sync with itself.
        $post = Get-Content $script:Post -Raw
        $post | Should -Not -Match 'of 7 axes'
        $post | Should -Not -Match 'of 8 axes'
        $post | Should -Match 'gitignored paths degraded to names only'
    }

    # --- capstone round 1 folds -----------------------------------------------------------------

    It 'is SILENT when a concurrent session creates the anomalies file for the FIRST time' {
        # The exemption used to cover only the CONTENTS of the concurrent-append targets, not their
        # EXISTENCE, so the very first anomaly capture in a repo - which CREATES local-anomalies.md -
        # changed the census and read as a breach. Their existence is as concurrent as their contents.
        $r = New-GuardRepo
        try {
            New-Item -ItemType Directory -Path (Join-Path $r '.clavity') -Force | Out-Null
            Set-Content (Join-Path $r '.clavity/.gitignore') '*' -Encoding ascii -NoNewline
            # NOTE: neither skip-listed file exists at baseline. That is the whole point of the row.
            $out = Invoke-ConsultAround $r {
                Set-Content (Join-Path $r '.clavity/local-anomalies.md') '# h' -Encoding ascii
                Set-Content (Join-Path $r '.clavity/discipline-reaching.jsonl') '{}' -Encoding ascii
            }
            $out | Should -Not -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'WARNS instead of going silent when it cannot create its own state directory' {
        # MEASURED before the fix with a paired control: with TMPDIR pointing at a FILE, mkdir -p
        # fails, agy_guard_state_file returns 1, and a bare `|| exit 0` dropped the consult in
        # total silence - 0 bytes, versus 410 for the control - never reaching the warning whose own
        # comment names this exact case. Silence from a guard reads as "verified clean".
        $r = New-GuardRepo
        $blocker = Join-Path ([IO.Path]::GetTempPath()) ("guardblock-" + [Guid]::NewGuid().ToString('N'))
        try {
            Set-Content $blocker 'not a directory' -Encoding ascii
            $p = Payload 'mcp__plugin_clavity_clavity-ls__agy_ask' '' $r
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p -Env @{ TMPDIR = ($blocker -replace '\\','/') }).StdOut
            $out | Should -Match 'guard failed to initialize'
        } finally {
            Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $blocker -Force -ErrorAction SilentlyContinue
        }
    }

    It 'actually compares HEAD in degraded mode instead of only claiming to' {
        # The degraded branch emitted "Only HEAD and stash were fully compared" and then exited BEFORE
        # $before and $after were ever computed - it compared nothing at all. A guard certifying a
        # check it never ran is the exact false confidence this file exists to prevent.
        #
        # THIS ROW IS BEHAVIOURAL ON PURPOSE. The first version asserted the source text did not
        # contain 'were fully compared' - and it FAILED, matching the COMMENT above that quotes the old
        # wording to explain the fix. A source-text assertion cannot tell a live message from prose
        # about it, so it is the wrong instrument twice over. Run the path instead.
        $r = New-GuardRepo
        $d = Join-Path ([IO.Path]::GetTempPath()) ("degr-" + [Guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            # Copy all three hooks: pre sources the lib by its OWN dirname, so the copy must be complete.
            Copy-Item $script:Pre  (Join-Path $d 'agy-consult-guard-pre.sh')
            Copy-Item $script:Post (Join-Path $d 'agy-consult-guard-post.sh')
            Copy-Item $script:Lib  (Join-Path $d 'agy-consult-guard-lib.sh')
            # Force the no-hashing-tool branch on the COPY only - never on the shipped file.
            $libCopy = Join-Path $d 'agy-consult-guard-lib.sh'
            $txt = [IO.File]::ReadAllText($libCopy) -replace '(?m)^agy_guard_have_hash\(\) .*$', 'agy_guard_have_hash() { return 1; }'
            [IO.File]::WriteAllText($libCopy, $txt)
            ($txt -match 'agy_guard_have_hash\(\) \{ return 1; \}') | Should -BeTrue -Because 'the probe must actually apply, or this row proves nothing'

            $p = Payload 'mcp__plugin_clavity_clavity-ls__agy_ask' '' $r
            Invoke-BashHook -HookPath (Join-Path $d 'agy-consult-guard-pre.sh') -Payload $p | Out-Null
            # Move HEAD. If degraded mode still exits before comparing, this goes completely undetected.
            Push-Location $r; Set-Content 'z.txt' 'z' -Encoding ascii; git add z.txt; git commit -qm peer; Pop-Location
            $out = (Invoke-BashHook -HookPath (Join-Path $d 'agy-consult-guard-post.sh') -Payload $p).StdOut

            $out | Should -Match 'VERSION CONTROL CHANGED' -Because 'HEAD moved, and HEAD is not a hashed axis - degraded mode can and must still catch it'
            $out | Should -Match 'committed-HEAD'
            $out | Should -Match 'may UNDERSTATE what changed' -Because 'the caveat must travel with the finding, not replace it'
        } finally {
            Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'produces a correct census for a directory with many entries' {
        # Guards the ONE-PROCESS hashing rewrite. The per-file form was replaced because it cost
        # ~470ms PER ENTRY on Git Bash (12 entries 5.8s, 100 entries 47.2s) and the census runs twice
        # per consult. The rewrite zips digests to entries BY POSITION, so an off-by-one or an
        # ordering slip would mislabel every entry - this row is what catches that.
        $r = New-GuardRepo
        try {
            $c = Join-Path $r '.clavity'
            New-Item -ItemType Directory -Path $c -Force | Out-Null
            0..39 | ForEach-Object { Set-Content (Join-Path $c "f$_.txt") "body$_" -Encoding ascii }
            $sh = "set +e; . '$($script:Lib -replace '\\','/')'; agy_guard_census '$($c -replace '\\','/')'"
            $out = & bash -lc $sh
            # Every entry present exactly once, each with a 64-hex digest - not a shared or empty one.
            0..39 | ForEach-Object { $out | Should -Match "f$_\.txt=[0-9a-f]{64}," }
            # Distinct bodies must yield distinct digests: a zip bug would repeat one digest.
            $digests = [regex]::Matches($out, '=([0-9a-f]{64}),') | ForEach-Object { $_.Groups[1].Value }
            ($digests | Sort-Object -Unique).Count | Should -Be 40
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'still detects a content change when the batch hash returns a short count' {
        # Capstone R2. The one-process rewrite zips digests to entries BY POSITION, and the original
        # count-mismatch fallback marked EVERY hashed entry UNREADABLE. MEASURED with a mutant that
        # always emitted a single digest: that masked EVERY content change in the directory for that
        # consult - names still moved, so a new file was caught, but an OVERWRITE was not, and an
        # overwrite of the shield is exactly what this axis exists for. A mismatch is reachable
        # without any tampering: .clavity/ is a concurrent write area, so a file can vanish between
        # the glob and the hash. The fallback is now per-file.
        $d = Join-Path ([IO.Path]::GetTempPath()) ("zip-" + [Guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            $libCopy = Join-Path $d 'lib.sh'
            Copy-Item $script:Lib $libCopy
            # Neuter the BATCH hasher only, forcing the mismatch path on every call.
            $txt = [IO.File]::ReadAllText($libCopy)
            # LINE-ENDING AGNOSTIC PATTERN. This regex used to embed LITERAL newlines taken from THIS
            # FILE's own source. `*.sh` is pinned `text eol=lf` by .gitattributes, but a `.ps1` is not,
            # so under core.autocrlf the pattern's newlines become CRLF while the shell library it
            # matches stays LF - and the mutation silently fails to apply. MEASURED: this row is green
            # locally (both files LF here) and RED on GitHub's windows-latest runner, which checks the
            # .ps1 out as CRLF. The row caught its own failure through the precondition assertion below
            # rather than passing vacuously, which is why this is a broken FIXTURE and not a false green.
            $pat = 'agy_guard_hash_files\(\) \{.*?\r?\n\}\r?\n'
            $rep = "agy_guard_hash_files() {`n  printf 'deadbeef`n'`n}`n"
            $mutated = [regex]::Replace($txt, $pat, $rep, 'Singleline')
            [IO.File]::WriteAllText($libCopy, $mutated)
            ($mutated -match "printf 'deadbeef") | Should -BeTrue -Because 'the mutant must actually apply, or this row proves nothing'

            $c = Join-Path $d '.clavity'
            New-Item -ItemType Directory -Path $c -Force | Out-Null
            Set-Content (Join-Path $c 'f1.txt') 'a' -Encoding ascii
            Set-Content (Join-Path $c 'f2.txt') 'b' -Encoding ascii
            $sh = "set +e; . '$($libCopy -replace '\\','/')'; agy_guard_census '$($c -replace '\\','/')'"
            $before = & bash -lc $sh
            Set-Content (Join-Path $c 'f2.txt') 'MUTATED' -Encoding ascii
            $after = & bash -lc $sh
            $after | Should -Not -Be $before -Because 'a content overwrite must survive the mismatch fallback'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'records a DIRECTORY created under a skip-listed name' {
        # Capstone R2, from the reviewer's DISCARDED list - which is where a real defect surfaced in
        # this repo once before, so it is read as carefully as the findings. The skip was
        # unconditional, so a directory created as `local-anomalies.md` was skipped entirely: its
        # appearance did not register and nothing beneath it was monitored.
        $r = New-GuardRepo
        try {
            $c = Join-Path $r '.clavity'
            New-Item -ItemType Directory -Path $c -Force | Out-Null
            Set-Content (Join-Path $c '.gitignore') '*' -Encoding ascii -NoNewline
            $sh = "set +e; . '$($script:Lib -replace '\\','/')'; agy_guard_census '$($c -replace '\\','/')'"
            $before = & bash -lc $sh
            New-Item -ItemType Directory -Path (Join-Path $c 'local-anomalies.md') -Force | Out-Null
            $after = & bash -lc $sh
            $after | Should -Not -Be $before
            $after | Should -Match 'local-anomalies\.md=DIR'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does not let two names collide into one census entry' {
        # Capstone R3, and the sharpest finding of that round. The sanitiser used to map every
        # reserved character onto '_', which is MANY-TO-ONE. MEASURED: with `a=b` and `a_b` both
        # present, both became `a_b`, and because the entry list is SORTED afterwards, swapping
        # their two contents produced a BYTE-IDENTICAL census - before == after, so the guard
        # reported a clean consult while two files had changed. That is lost DETECTION, not lost
        # attribution. Percent-encoding is injective, so distinct names cannot collide.
        $r = New-GuardRepo
        try {
            $c = Join-Path $r '.clavity'
            New-Item -ItemType Directory -Path $c -Force | Out-Null
            # ',' and '=' are legal in Windows filenames; '|' and ':' are not, which is why the
            # fixture uses these two. Both would previously sanitise to the same string.
            Set-Content (Join-Path $c 'a=b') 'ONE' -Encoding ascii
            Set-Content (Join-Path $c 'a_b') 'TWO' -Encoding ascii
            $sh = "set +e; . '$($script:Lib -replace '\\','/')'; agy_guard_census '$($c -replace '\\','/')'"
            $before = & bash -lc $sh
            # Swap the contents. Nothing is created or removed - only the pairing changes.
            Set-Content (Join-Path $c 'a=b') 'TWO' -Encoding ascii
            Set-Content (Join-Path $c 'a_b') 'ONE' -Encoding ascii
            $after = & bash -lc $sh
            $after | Should -Not -Be $before -Because 'a swap between two colliding names must not be invisible'
            $before | Should -Match 'a%3Db=' -Because 'the encoding must distinguish the two names'
            $before | Should -Match 'a_b='
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'WARNS when a script inside a .clavity SUBDIRECTORY is overwritten' {
        # Owner ruled 2026-08-31 to widen the census after a reviewer raised the shallow-census blind
        # spot twice and I refuted it twice - wrongly, on a grep that only covered the plugin dirs.
        # MEASURED on the third round: .claude/settings.local.json wired three mode-755 scripts under
        # .clavity/scratch/ as live SessionStart / SessionEnd hooks. With a top-level-only census the
        # entry read `scratch=DIR` and overwriting a script this machine EXECUTES was invisible.
        $r = New-GuardRepo
        try {
            $c = Join-Path $r '.clavity'
            New-Item -ItemType Directory -Path (Join-Path $c 'agy-marks') -Force | Out-Null
            Set-Content (Join-Path $c '.gitignore') '*' -Encoding ascii -NoNewline
            Set-Content (Join-Path $c 'agy-marks/probe.sh') 'echo ok' -Encoding ascii
            $out = Invoke-ConsultAround $r { Set-Content (Join-Path $c 'agy-marks/probe.sh') 'echo PWNED' -Encoding ascii }
            $out | Should -Match 'gitignored paths'
            $out | Should -Match 'agy-marks/probe\.sh'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'stays SILENT for writes inside scratch, but still sees it deleted' {
        # scratch/ is where the peer is TOLD to write, so hashing its contents would turn every
        # sanctioned write into a breach report - and a false alarm is what teaches an operator to
        # ignore this guard. But the directory itself is still recorded, so REMOVING it is caught.
        # Without that second half the exclusion would be a hole.
        # seams/ is deliberately NOT exempt any more - see the row below.
        $r = New-GuardRepo
        try {
            $c = Join-Path $r '.clavity'
            New-Item -ItemType Directory -Path (Join-Path $c 'scratch/t') -Force | Out-Null
            Set-Content (Join-Path $c '.gitignore') '*' -Encoding ascii -NoNewline
            Set-Content (Join-Path $c 'scratch/t/notes.md') 'peer working' -Encoding ascii
            $out = Invoke-ConsultAround $r {
                Set-Content (Join-Path $c 'scratch/t/notes.md') 'peer still working' -Encoding ascii
                Set-Content (Join-Path $c 'scratch/t/extra.md') 'more' -Encoding ascii
            }
            $out | Should -Not -Match 'VERSION CONTROL CHANGED' -Because 'the sanctioned write area must not raise a breach'

            $sh = "set +e; . '$($script:Lib -replace '\\','/')'; agy_guard_census '$($c -replace '\\','/')'"
            $withScratch = & bash -lc $sh
            Remove-Item (Join-Path $c 'scratch') -Recurse -Force
            $withoutScratch = & bash -lc $sh
            $withoutScratch | Should -Not -Be $withScratch -Because 'deleting an excluded directory must still be visible'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'WARNS when a brief in seams is rewritten, renamed, or joined by a new entry' {
        # Owner ruled 2026-08-31 that seams/ is MONITORED, reversing an earlier decision to exempt it
        # alongside scratch/. The asymmetry is the point: the peer WRITES in scratch/ but only READS
        # seams/, and a brief there is an instruction to a FUTURE review round - so a peer able to
        # rewrite one unobserved could inject instructions into the loop meant to be checking it.
        # It is watched as ONE aggregate digest rather than per file: this repository already holds
        # 706 briefs, and enumerating them measured ~69 KB of census, which capped the whole thing
        # and destroyed per-entry naming for every other directory too.
        #
        # All three mutations are asserted because the digest covers TWO streams - the full entry
        # listing and the contents of regular files - and each mutation exercises a different one.
        # A `-type f`-only digest would have missed the empty subdirectory entirely.
        $r = New-GuardRepo
        try {
            $c = Join-Path $r '.clavity'
            New-Item -ItemType Directory -Path (Join-Path $c 'seams') -Force | Out-Null
            Set-Content (Join-Path $c '.gitignore') '*' -Encoding ascii -NoNewline
            Set-Content (Join-Path $c 'seams/topic.md') 'the original brief' -Encoding ascii
            $sh = "set +e; . '$($script:Lib -replace '\\','/')'; agy_guard_census '$($c -replace '\\','/')'"

            $base = & bash -lc $sh
            Set-Content (Join-Path $c 'seams/topic.md') 'rewritten by the peer' -Encoding ascii
            (& bash -lc $sh) | Should -Not -Be $base -Because 'a rewritten brief is the threat this monitors'

            $base = & bash -lc $sh
            Rename-Item (Join-Path $c 'seams/topic.md') 'renamed.md'
            (& bash -lc $sh) | Should -Not -Be $base -Because 'a rename must be caught, so the listing is hashed too'

            $base = & bash -lc $sh
            New-Item -ItemType Directory -Path (Join-Path $c 'seams/sub') -Force | Out-Null
            (& bash -lc $sh) | Should -Not -Be $base -Because 'an EMPTY subdirectory has no regular file, so -type f alone would miss it'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does not fall back to a constant digest when the hashing helper misbehaves' {
        # The seams digest used `xargs -0 -r`, and `-r` is a GNU extension: macOS xargs rejects it,
        # the pipeline sent stderr to /dev/null, and hashing the resulting EMPTY stream yields the
        # constant e3b0c442... - MEASURED. The digest would then never change again and the guard
        # would report clean forever on macOS. A guard that fails open certifies exactly what it
        # stopped checking, so the empty-input digest must never be a reachable answer here.
        $r = New-GuardRepo
        try {
            $c = Join-Path $r '.clavity'
            New-Item -ItemType Directory -Path (Join-Path $c 'seams') -Force | Out-Null
            Set-Content (Join-Path $c 'seams/topic.md') 'a brief' -Encoding ascii
            $sh = "set +e; . '$($script:Lib -replace '\\','/')'; agy_guard_census '$($c -replace '\\','/')'"
            $out = & bash -lc $sh
            $out | Should -Match 'seams=[0-9a-f]{64}'
            $out | Should -Not -Match 'seams=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' -Because 'that is the sha256 of empty input - the signature of a silently failed pipeline'
            # And no xargs remains in the shipped hook, in either half.
            foreach ($half in @($script:Lib, (Join-Path $script:Classic 'agy-consult-guard-lib.sh'))) {
                (Get-Content $half -Raw) | Should -Not -Match '(?m)^[^#]*xargs' -Because "$half must not invoke xargs"
            }
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'excludes scratch even when the prune pattern cannot match' {
        # Capstone R4. The exclusion used to rest ENTIRELY on `find -path "$d/scratch" -prune`, and
        # -path matches with fnmatch, not literally. MEASURED, it silently matched nothing in two
        # reachable cases, and scratch/ was then walked and hashed - turning every sanctioned peer
        # write into a breach report, which is the failure that teaches an operator to ignore the
        # guard. The exclusion is now enforced on the relative path inside the loop; the prune is
        # only a performance optimisation. This row uses a '[' in the directory name, which is legal
        # on Windows and is a glob metacharacter.
        $base = Join-Path ([IO.Path]::GetTempPath()) ("guard[1]-" + [Guid]::NewGuid().ToString('N'))
        try {
            $c = Join-Path $base '.clavity'
            # .NET APIs, not the PowerShell providers: '[' is a WILDCARD to PowerShell's path
            # resolution, so New-Item/Set-Content misbind on this fixture. That is a property of the
            # harness, not of the code under test - and using -LiteralPath everywhere would be easy
            # to lose on the next edit, so the fixture avoids the provider entirely.
            [IO.Directory]::CreateDirectory((Join-Path $c 'scratch/t')) | Out-Null
            [IO.Directory]::CreateDirectory((Join-Path $c 'agy-marks')) | Out-Null
            [IO.File]::WriteAllText((Join-Path $c 'scratch/t/peer.md'), 'peer work')
            [IO.File]::WriteAllText((Join-Path $c 'agy-marks/m'), 'marker')
            $sh = "set +e; . '$($script:Lib -replace '\\','/')'; agy_guard_census '$($c -replace '\\','/')'"
            $out = & bash -lc $sh
            $out | Should -Not -Match 'scratch/t/peer\.md' -Because 'a glob metacharacter in the path must not defeat the exclusion'
            $out | Should -Match 'scratch=DIR' -Because 'the directory itself is still recorded'
            $out | Should -Match 'agy-marks/m=' -Because 'the rest of the tree must still be walked'
        } finally { [IO.Directory]::Delete($base, $true) }
    }

    It 'gives the same census whether or not the path carries a trailing slash' {
        # Capstone R4. A trailing slash broke TWO things at once, measured: the -path prune matched
        # nothing, AND `${p#"$d/"}` failed to strip, so every entry name came out as an ABSOLUTE
        # path - machine-specific, far larger, and different from the same directory addressed
        # without the slash. Two callers naming the same directory must agree, or the pre and post
        # halves of one consult could disagree for no reason at all.
        $r = New-GuardRepo
        try {
            $c = Join-Path $r '.clavity'
            New-Item -ItemType Directory -Path (Join-Path $c 'scratch/t') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $c 'agy-marks') -Force | Out-Null
            Set-Content (Join-Path $c 'scratch/t/peer.md') 'peer work' -Encoding ascii
            Set-Content (Join-Path $c 'agy-marks/m') 'marker' -Encoding ascii
            $p = ($c -replace '\\','/')
            $bare  = & bash -lc "set +e; . '$($script:Lib -replace '\\','/')'; agy_guard_census '$p'"
            $slash = & bash -lc "set +e; . '$($script:Lib -replace '\\','/')'; agy_guard_census '$p/'"
            $slash | Should -Be $bare
            # AGY-TEST-AUDIT 2026-08-31: the negative below is satisfied for free by an EMPTY census,
            # so it is paired with a positive that proves the census actually listed something. The
            # row as a whole was NOT vacuous - deleting only the trailing-slash normalisation reds the
            # comparison above - but a bare -Not -Match is not evidence on its own.
            $bare | Should -Match 'agy-marks/m=' -Because 'the census must actually enumerate entries, or the negative below proves nothing'
            $bare | Should -Not -Match 'scratch/t/peer\.md'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'never lets the seams digest collapse to a constant on a short hash count' {
        # Capstone R5, and the THIRD appearance of one defect class in this file: a guard returning
        # the same answer regardless of its input while reporting clean. The first two were
        # agy_guard_hash's NOHASH and the census's all-UNREADABLE fallback. This one returned a bare
        # 'UNREADABLE' when the batch hash answered for fewer files than it was given - so pre and
        # post both produced 'UNREADABLE', they compared EQUAL, and seams/ could change underneath a
        # consult that reported clean. The census already fell back per-file here; this function did
        # not, which was an inconsistency rather than a design.
        $d = Join-Path ([IO.Path]::GetTempPath()) ("dd-" + [Guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            $libCopy = Join-Path $d 'lib.sh'
            Copy-Item $script:Lib $libCopy
            # Force the short-count path on every call by neutering ONLY the batch hasher.
            $txt = [IO.File]::ReadAllText($libCopy)
            $mut = [regex]::Replace($txt, "agy_guard_hash_files\(\) \{.*?\n\}\n",
                "agy_guard_hash_files() {`n  printf 'deadbeef\n'`n}`n", 'Singleline')
            [IO.File]::WriteAllText($libCopy, $mut)
            ($mut -match "printf 'deadbeef") | Should -BeTrue -Because 'the mutant must apply, or this row proves nothing'

            $c = Join-Path $d '.clavity'
            New-Item -ItemType Directory -Path (Join-Path $c 'seams') -Force | Out-Null
            Set-Content (Join-Path $c 'seams/a.md') 'one' -Encoding ascii
            Set-Content (Join-Path $c 'seams/b.md') 'two' -Encoding ascii
            $sh = "set +e; . '$($libCopy -replace '\\','/')'; agy_guard_census '$($c -replace '\\','/')'"
            $before = & bash -lc $sh
            Set-Content (Join-Path $c 'seams/b.md') 'CHANGED' -Encoding ascii
            $after = & bash -lc $sh
            $after | Should -Not -Be $before -Because 'the fallback must still track content, not answer the same thing every time'
            $before | Should -Not -Match 'seams=UNREADABLE' -Because 'a bare sentinel here compares equal to itself and blinds the monitor'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'warns on an unwritable state directory for an ASYNC consult too' {
        # Capstone R5, correcting an earlier fix of MINE that was too narrow. The two no-baseline
        # situations are different: a baseline FILE that is simply absent is genuinely ambiguous for
        # an async terminal, because there may have been no matching send - that one still gates on
        # sync. But failing to CREATE the state directory is unambiguous whatever the slot, and it
        # was gated on sync too. MEASURED: an async consult with an unwritable TMPDIR emitted 0
        # bytes and read as a clean consult.
        $r = New-GuardRepo
        $blocker = Join-Path ([IO.Path]::GetTempPath()) ("blk-" + [Guid]::NewGuid().ToString('N'))
        try {
            Set-Content $blocker 'not a directory' -Encoding ascii
            $p = Payload 'Bash' 'clavity await-reply' $r
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p -Env @{ TMPDIR = ($blocker -replace '\\','/') }).StdOut
            $out | Should -Match 'failed to initialize'
        } finally {
            Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $blocker -Force -ErrorAction SilentlyContinue
        }
    }

    It 'encodes every reserved character, including ones no filename can carry' {
        # Capstone R6. The encoder was inline in agy_guard_census and its only coverage drove it
        # through a real FILENAME - so on Windows, where '|' and ':' are illegal in names, two of the
        # five replacements were untestable and untested. MEASURED: deleting both left the suite
        # green at 35/35. Extracting agy_guard_encode_name makes them reachable, because a function
        # accepts any string while a fixture only accepts a name the filesystem allows.
        #
        # '%' MUST be first: encoding it after the others would let a literal '%3D' in a name collide
        # with the encoding of '=', and injectivity is the whole point - a many-to-one mapping let a
        # content swap between two colliding names produce a byte-identical census.
        $lib = $script:Lib -replace '\\','/'
        $cases = @(
            @{ raw = 'a|b';   enc = 'a%7Cb' },
            @{ raw = 'a:b';   enc = 'a%3Ab' },
            @{ raw = 'a,b';   enc = 'a%2Cb' },
            @{ raw = 'a=b';   enc = 'a%3Db' },
            @{ raw = 'a%b';   enc = 'a%25b' },
            @{ raw = 'plain.md'; enc = 'plain.md' }
        )
        foreach ($c in $cases) {
            $got = & bash -lc "set +e; . '$lib'; agy_guard_encode_name '$($c.raw)'"
            $got | Should -Be $c.enc -Because "'$($c.raw)' must encode to '$($c.enc)'"
        }
        # Injectivity, the property the encoding exists for: a literal '%3D' in a name must NOT
        # collide with the encoding of '='.
        $litP = & bash -lc "set +e; . '$lib'; agy_guard_encode_name 'a%3Db'"
        $eq    = & bash -lc "set +e; . '$lib'; agy_guard_encode_name 'a=b'"
        $litP | Should -Not -Be $eq -Because 'encoding % first is what keeps the mapping injective'
    }

    It 'actually splits a large file set into chunks, not just hashes it correctly' {
        # Capstone R7, replacing a row that was VACUOUS with respect to the thing it claimed to
        # guard. The old version fed 600 short filenames - about 6 KB of argv, nowhere near ARG_MAX -
        # and asserted 600 distinct digests. MEASURED: reverting the implementation to a single
        # `sha256sum -- "$@"` left the whole suite GREEN at 37/37, because an unchunked call handles
        # 600 files perfectly well. Correct output is not evidence of chunking.
        #
        # This version COUNTS THE INVOCATIONS with a shim first on PATH that tallies each call and
        # delegates to the real tool. 300 files at 256 per chunk is exactly 2 calls; an unchunked
        # implementation makes 1. That distinction is the entire point of the rewrite, which exists
        # so an oversized argv can never reach the kernel and trigger E2BIG.
        #
        # The probe is written to disk as a POSIX script rather than built as a PowerShell
        # here-string: the here-string version failed to PARSE, taking the whole file to 0 tests.
        $d = Join-Path ([IO.Path]::GetTempPath()) ("chunk-" + [Guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            # The files go in a SUBDIRECTORY and the probe script does not. First attempt put both
            # in $d and the probe counted ITSELF - digests=601. The probe was right and the fixture
            # was wrong, which is what a hard-coded expected count is for.
            #
            # 300, not 600: two chunks is all it takes to tell chunked (2 calls) from unchunked (1),
            # and 600 pushed this one row past ten minutes of fixture creation.
            $files = Join-Path $d 'files'
            New-Item -ItemType Directory -Path $files -Force | Out-Null
            0..299 | ForEach-Object { Set-Content (Join-Path $files "f$_.txt") "body$_" -Encoding ascii }
            $probePath = Join-Path $d 'probe.sh'
            [IO.File]::WriteAllText($probePath, @'
set +e
lib=$1
dir=$2
real=$(command -v sha256sum) || { echo "digests=SKIP calls=SKIP"; exit 0; }
shim=$(mktemp -d); count="$shim/count"; : > "$count"
mkdir -p "$shim/bin"
printf '#!/bin/sh\necho x >> "%s"\nexec "%s" "$@"\n' "$count" "$real" > "$shim/bin/sha256sum"
chmod +x "$shim/bin/sha256sum"
. "$lib"
files=()
while IFS= read -r -d '' q; do files+=("$q"); done < <(find "$dir" -type f -print0)
n=$(PATH="$shim/bin:$PATH" bash -c '. "$1"; shift; agy_guard_hash_files "$@"' _ "$lib" "${files[@]}" | wc -l)
echo "digests=$n calls=$(wc -l < "$count")"
'@.Replace("`r`n", "`n"))
            $out = & bash -lc "sh '$($probePath -replace '\\','/')' '$($script:Lib -replace '\\','/')' '$($files -replace '\\','/')'"
            # A box with no sha256sum - macOS ships shasum instead - cannot run this probe at all,
            # and the first version FAILED there rather than skipping: it printed 'no-sha256sum' and
            # both assertions went red. CI is windows-latest only (ci-scripts.yml), so it was never
            # reachable there, but a red row on a developer's machine for a tool that is legitimately
            # absent is a false alarm, and false alarms are what teach people to ignore a suite.
            if ($out -match 'digests=SKIP') {
                Set-ItResult -Skipped -Because 'sha256sum is absent on this host, so the invocation-counting shim cannot run'
                return
            }
            $out | Should -Match 'digests=300' -Because 'every file must still get exactly one digest'
            $out | Should -Match 'calls=2' -Because '300 files at 256 per chunk is 2 invocations; an unchunked call would be 1'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports failure when no hashing tool exists, instead of looping and reporting success' {
        # Capstone R7. The tool check was an if/elif/else INSIDE the chunk loop, with the whole block
        # piped into `cut`. That put `else return 1` on the left of a pipeline, which bash runs in a
        # SUBSHELL - so the return exited the subshell, not the function. MEASURED with a paired
        # control: a return on the left of a pipeline leaves rc 0 and execution continues past it,
        # while the same return outside a pipeline gives rc 1. The function therefore looped over
        # every remaining chunk doing nothing and then reported SUCCESS.
        $lib = $script:Lib -replace '\\','/'
        # Shadow `command` so neither tool resolves, without breaking the rest of the shell.
        $rc = & bash -lc "set +e; . '$lib'; command() { return 1; }; agy_guard_hash_files /etc/hosts >/dev/null 2>&1; echo `$?"
        $rc | Should -Be '1' -Because 'no hashing tool is a failure the caller must be able to see'
    }

    It 'tracks the .clavity shield file as a state of its own' {
        # Capstone R8, and the direct coverage the shield row above cannot provide. The dedicated
        # `.clavity/.gitignore` component of agy_guard_ignored is redundant with the census, so no
        # end-to-end row can isolate it - stub the component out and the census still catches the
        # change. This row tests the building block itself, where nothing else can shadow it.
        $r = New-GuardRepo
        try {
            $c = Join-Path $r '.clavity'
            New-Item -ItemType Directory -Path $c -Force | Out-Null
            $g = (Join-Path $c '.gitignore') -replace '\\','/'
            $lib = $script:Lib -replace '\\','/'

            $absent = & bash -lc "set +e; . '$lib'; agy_guard_file_state '$g'"
            $absent | Should -Be 'ABSENT' -Because 'a missing shield must be an explicit sentinel, never an empty string'

            Set-Content (Join-Path $c '.gitignore') '*' -Encoding ascii -NoNewline
            $full = & bash -lc "set +e; . '$lib'; agy_guard_file_state '$g'"
            $full | Should -Match '^[0-9a-f]{64}$'

            Set-Content (Join-Path $c '.gitignore') '' -Encoding ascii -NoNewline
            $empty = & bash -lc "set +e; . '$lib'; agy_guard_file_state '$g'"
            $empty | Should -Match '^[0-9a-f]{64}$'
            $empty | Should -Not -Be $full -Because 'emptying the shield is the change this axis exists to catch'
            $empty | Should -Not -Be 'ABSENT' -Because 'an empty file and a missing file are different states'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # --- the smuggle-vector axes (AGY-TEST-AUDIT 2026-08-31) -----------------------------------
    # agy_guard_quad carries eight axes. The ignored axis arrived with a full row family; these four
    # older ones had NONE. MEASURED before writing them: blind stash, gitmeta and flags to constants
    # and the full suite still reported 38 passed / 1 failed, where the single red was
    # 'is byte-identical to the clavity-classic mirror' - an artifact of mutating one half of the
    # pair, and precisely the gate that does NOT fire on a properly-mirrored change, which is how
    # every real edit to these files lands. Each axis below guards a documented smuggle vector that
    # leaves `git status` completely clean.

    It 'WARNS when a stash is created during a consult' {
        # A stash moves refs/stash and then restores the worktree, so status, diff and HEAD all read
        # exactly as they did at baseline. Without this axis the peer could park a change in the
        # stash and the guard would report the consult clean.
        $r = New-GuardRepo
        try {
            $out = Invoke-ConsultAround -Repo $r -Between {
                Push-Location $r
                Set-Content 'a.txt' 'stashed change' -Encoding ascii
                git stash -q
                Pop-Location
            }
            $out | Should -Match 'VERSION CONTROL CHANGED'
            $out | Should -Match 'stash \(refs/stash moved\)' -Because 'the stash axis must NAME itself, or the operator cannot tell what to look at'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'WARNS when a .git hook is planted during a consult' {
        # The highest-consequence vector of the four: a file under .git/hooks/ is EXECUTED by later
        # git commands, so planting one is arbitrary code execution that no `git status` will ever
        # show. .git is not tracked, so this axis is the only thing watching it.
        $r = New-GuardRepo
        try {
            $out = Invoke-ConsultAround -Repo $r -Between {
                Set-Content (Join-Path $r '.git/hooks/post-commit') "#!/bin/sh`necho pwned" -Encoding ascii
            }
            $out | Should -Match 'VERSION CONTROL CHANGED'
            $out | Should -Match 'ARBITRARY-CODE-EXEC' -Because 'a planted hook is code execution and the warning must say so'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'WARNS when an assume-unchanged bit is set during a consult' {
        # --assume-unchanged makes git IGNORE later edits to a tracked file: the smuggle is that it
        # hides a subsequent modification from `status` AND from `diff` at once. Setting the bit is
        # invisible to both, so only `ls-files -v` can see it.
        $r = New-GuardRepo
        try {
            $out = Invoke-ConsultAround -Repo $r -Between {
                Push-Location $r; git update-index --assume-unchanged a.txt; Pop-Location
            }
            $out | Should -Match 'VERSION CONTROL CHANGED'
            $out | Should -Match 'hidden index smuggle' -Because 'the flags axis must name itself'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # --- the ASYNC half of the contract (AGY-TEST-AUDIT 2026-08-31) ----------------------------
    # Every other row in this file drives the SYNC path. Nothing anywhere drove `clavity send`, so
    # the open -> terminal flow, and with it pre.sh's preserve-the-oldest branch, had no coverage at
    # all - even though that branch's own comment says it exists to "never drop an in-flight
    # mutation across multi-message async".

    It 'catches a mutation across an ASYNC send/await-reply consult' {
        $r = New-GuardRepo
        try {
            $c = ($r -replace '\\','/')
            $send = @{ tool_name = 'Bash'; tool_input = @{ command = 'clavity send "please review"' }; cwd = $c; session_id = 'guardasync1' } | ConvertTo-Json -Compress
            $term = @{ tool_name = 'Bash'; tool_input = @{ command = 'clavity await-reply' }; cwd = $c; session_id = 'guardasync1' } | ConvertTo-Json -Compress
            Invoke-BashHook -HookPath $script:Pre -Payload $send | Out-Null
            Push-Location $r; Set-Content 'b.txt' 'two' -Encoding ascii; git add b.txt; git commit -qm peer; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $term).StdOut
            $out | Should -Match 'VERSION CONTROL CHANGED' -Because 'the async slot must detect a mutation exactly as the sync slot does'
            $out | Should -Match 'committed-HEAD'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'keeps the OLDEST async baseline when a second send arrives mid-flight' {
        # pre.sh:35-37, and the reason the async slot is write-IF-NONE rather than write-always: a
        # multi-message async exchange fires Pre again on every send. If the second send re-baselined,
        # a mutation made before it would be folded into the new baseline and silently disappear.
        # This row commits BETWEEN the two sends, so a re-baselining Pre reports the consult clean.
        $r = New-GuardRepo
        try {
            $c = ($r -replace '\\','/')
            $send = @{ tool_name = 'Bash'; tool_input = @{ command = 'clavity send "please review"' }; cwd = $c; session_id = 'guardasync2' } | ConvertTo-Json -Compress
            $term = @{ tool_name = 'Bash'; tool_input = @{ command = 'clavity await-reply' }; cwd = $c; session_id = 'guardasync2' } | ConvertTo-Json -Compress
            Invoke-BashHook -HookPath $script:Pre -Payload $send | Out-Null
            Push-Location $r; Set-Content 'b.txt' 'two' -Encoding ascii; git add b.txt; git commit -qm peer; Pop-Location
            Invoke-BashHook -HookPath $script:Pre -Payload $send | Out-Null   # the second send
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $term).StdOut
            $out | Should -Match 'committed-HEAD' -Because 'the second send must NOT re-baseline away a mutation that already landed'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

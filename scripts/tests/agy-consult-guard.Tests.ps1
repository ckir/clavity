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
            $out | Should -Match 'CONSULT GUARD' -Because 'a .no-agy in the repo must not be able to silence the guard that watches the repo'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # --- the ignored-paths axis (roadmap: review-only envelope) -------------------------------
    # git status --porcelain OMITS ignored files, which is why every one of these was invisible.

    It 'WARNS when the .clavity shield file is emptied' {
        # The shield is a bare '*'. Empty it and .clavity/ becomes visible to git, so the next
        # `git add .` publishes untriaged anomalies. Highest-consequence silent change there is.
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
            # There is deliberately NO `Should -Not -Match '\|'` here. It was, and it was VACUOUS:
            # '|' cannot occur in a Windows filename, so the fixture could never introduce one and the
            # assertion held whether or not `tr` stripped anything. An assertion that cannot fail is
            # worse than none, because it reads as coverage. The pipe and colon halves of the sanitizer
            # are UNTESTABLE on this platform; the ',' and '=' halves are tested by the control below,
            # and all four are stripped by the same single `tr`, which is what carries the guarantee.
            # Positive control: prove the sanitizer actually ran, rather than inferring it from the
            # absence of a character the fixture may never have produced.
            $ax | Should -Match 'we_ird_name\.txt'
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
            $mutated = [regex]::Replace($txt, "agy_guard_hash_files\(\) \{.*?
\}
",
                "agy_guard_hash_files() {`n  printf 'deadbeef
'`n}`n", 'Singleline')
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
}

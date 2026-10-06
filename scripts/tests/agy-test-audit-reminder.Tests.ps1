Describe 'agy-test-audit-reminder.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh'

        $bashDir = Split-Path -Parent (Get-GitBashOrThrow)                       # ...\Git\bin
        $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')   # ...\Git\usr\bin

        # ASSERT THE FIXTURE'S POSTCONDITION, NOT `$LASTEXITCODE`. Both builders below stage with
        # `git add -A` then commit, and NEITHER command's status was checked. That is not merely untidy:
        # New-TempRepo leaves an `--allow-empty` init commit, so if the staging silently no-ops, the commit
        # fails with nothing to commit, `git rev-parse HEAD` still SUCCEEDS and returns the INIT sha, and the
        # builder hands back a well-formed object describing the exact INVERSE of the state its comment
        # promises. MEASURED with the `add` removed: rev-parse returned a plausible sha whose commit touched
        # no files at all, and every consumer saw a valid-looking fixture.
        #
        # Checking the POSTCONDITION catches every way the fixture can miss that state, not just a nonzero
        # add - and it is the state, not the exit code, that the rows depend on.
        #
        # THE PATHSPEC IS LOAD-BEARING: `--name-only` QUOTES a non-ASCII path (`core.quotepath` defaults on),
        # so it emits "src/Modulo_\303\251.cs" for the accented row below and a name comparison in PowerShell
        # would fail for an ENCODING reason while the fixture was perfectly fine. Passing the path as a
        # pathspec makes git do the matching, so nothing round-trips through PowerShell's text decoding:
        # non-empty output means HEAD's commit touched exactly that path. Both directions measured.
        function Assert-HeadTouched { param([string]$Dir, [string]$Rel)
            $touched = & git -C $Dir diff-tree --no-commit-id --name-only -r HEAD -- $Rel
            if (-not $touched) {
                throw ("fixture is NOT in its promised state: HEAD's commit did not touch '$Rel' " +
                       "(staging or commit silently failed; rev-parse would still have returned the init sha)")
            }
        }

        # A repo whose HEAD commit touched a code file, with capstone.head==HEAD and no audit marker:
        # the canonical FIRE state. Returns the repo dir (Windows path).
        # A BUILDER OWNS ITS DIRECTORY UNTIL IT RETURNS. Every caller is shaped
        # `$r = New-FiredRepo; try { ... } finally { Remove-Item $r.Dir }` - the assignment is OUTSIDE the
        # try, so a throw in here aborts before `$r` exists, the caller's finally never runs, and the temp
        # repo leaks permanently. The postcondition guards make that path reachable for the first time, so
        # the builders now clean up after themselves and rethrow. `catch`, not `finally`: the success path
        # must hand the directory to the caller intact.
        function New-FiredRepo {
            param([string]$CodeFile = 'src/thing.cs', [switch]$DocsOnly)
            $dir = New-TempRepo
            try {
                $rel = if ($DocsOnly) { 'docs/notes.md' } else { $CodeFile }
                $full = Join-Path $dir $rel
                New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
                Set-Content -LiteralPath $full -Value 'x' -Encoding ascii
                & git -C $dir add -A
                & git -C $dir -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= commit -qm work
                Assert-HeadTouched -Dir $dir -Rel $rel
                $head = (& git -C $dir rev-parse HEAD).Trim()
                New-Item -ItemType Directory -Path (Join-Path $dir '.clavity/agy-marks') -Force | Out-Null
                return [pscustomobject]@{ Dir = $dir; Head = $head }
            # THE CLEANUP MUST NOT BE ABLE TO EAT THE DIAGNOSIS. `-ErrorAction SilentlyContinue` suppresses
            # NON-terminating errors only; a terminating one (a locked handle, an invalid path) would abort
            # this catch block and throw ITS exception instead, destroying the original - so the failure the
            # builder actually hit would be replaced by a confusing cleanup error. Best-effort cleanup,
            # guaranteed rethrow.
            } catch { try { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue } catch { }; throw }
        }
        # THE LEDGER-ROW SHAPE - the state agy-capstone actually leaves behind, and the one this hook was
        # blind to until 2026-08-26. A code commit (the REVIEWED tip, where the capstone marker is written),
        # then a second commit on top. MEASURED in the live repo that day: the capstone marker was f29cd42
        # and the very next commit was `f209632 docs(ledger): record ... GREEN` - the ledger row the
        # agy-capstone skill REQUIRES before a plan may be declared complete. From that commit onward
        # `cap == head` was false and this hook stayed silent for every commit that followed, so the discipline's own
        # mandatory final step destroyed its successor's trigger.
        #
        # Built on the DiffPath shape (main pinned at init) so gate() takes the PRIMARY `diff base..HEAD`
        # path. That is load-bearing: on the FALLBACK path the reviewed range is HEAD's own commit, which
        # for a ledger row is docs-only and correctly silent for an entirely different reason - a fixture
        # that took the fallback would pass for the wrong reason and prove nothing about this gate.
        function New-PostMarkerRepo {
            param([ValidateSet('docs','code')][string]$Kind = 'docs')
            $dir = New-TempRepo
            try {
                & git -C $dir branch -f main HEAD
                & git -C $dir checkout -qb feature
                $commit = {
                    param($Rel)
                    $full = Join-Path $dir $Rel
                    New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
                    Set-Content -LiteralPath $full -Value 'x' -Encoding ascii
                    & git -C $dir add -A
                    & git -C $dir -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= commit -qm work
                    Assert-HeadTouched -Dir $dir -Rel $Rel
                    (& git -C $dir rev-parse HEAD).Trim()
                }
                $cap  = & $commit 'src/thing.cs'
                $head = & $commit $(if ($Kind -eq 'docs') { 'docs/agy-capstone-ledger.md' } else { 'src/later.cs' })

                # POSTCONDITIONS - each is a separate way this fixture could silently describe another state.
                if ($cap -eq $head) { throw 'fixture is NOT in its promised state: the marker sha equals HEAD, so the relaxed branch is never entered' }
                & git -C $dir merge-base --is-ancestor $cap $head
                if ($LASTEXITCODE -ne 0) { throw 'fixture is NOT in its promised state: the marker sha is not an ancestor of HEAD' }
                if ((& git -C $dir merge-base HEAD main).Trim() -eq $head) {
                    throw 'fixture is NOT in its promised state: merge-base HEAD main == HEAD, so gate() takes the FALLBACK path and this row would pass for the wrong reason'
                }
                $since = (& git -C $dir diff --name-only "$cap..HEAD") -join "`n"
                $hasCode = $since -match $script:CodeExtRe
                if ($Kind -eq 'docs' -and $hasCode) { throw "fixture is NOT in its promised state: a code path changed after the marker ($since)" }
                if ($Kind -eq 'code' -and -not $hasCode) { throw "fixture is NOT in its promised state: no code path changed after the marker ($since)" }

                New-Item -ItemType Directory -Path (Join-Path $dir '.clavity/agy-marks') -Force | Out-Null
                return [pscustomobject]@{ Dir = $dir; Cap = $cap; Head = $head }
            } catch { try { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue } catch { }; throw }
        }
        function Set-Marker { param($Dir, $Name, $Sha)
            Set-Content -LiteralPath (Join-Path $Dir ".clavity/agy-marks/$Name.head") -Value $Sha -NoNewline -Encoding ascii
        }
        # A repo whose gate() takes the PRIMARY `git diff "$base"..HEAD` path: `main` stays at the init
        # commit while HEAD advances on a feature branch with a code file, so merge-base HEAD main != HEAD.
        function New-DiffPathRepo {
            $dir = New-TempRepo                                # one 'init' commit on the default branch
            try {
            & git -C $dir branch -f main HEAD                  # ensure a 'main' ref pinned at init
            & git -C $dir checkout -qb feature
            $full = Join-Path $dir 'src/thing.cs'
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            Set-Content -LiteralPath $full -Value 'x' -Encoding ascii
            & git -C $dir add -A
            & git -C $dir -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= commit -qm work
            Assert-HeadTouched -Dir $dir -Rel 'src/thing.cs'
            $head = (& git -C $dir rev-parse HEAD).Trim()
            # THE PRIMARY-PATH PROMISE IS ITS OWN CLAIM, and it fails independently of the commit: if `main`
            # did not stay pinned at init, merge-base HEAD main == HEAD, gate() takes the FALLBACK branch, and
            # every row reached through this builder silently exercises the wrong code path while still
            # passing. The comment above is the contract; this is the only thing that holds it to it.
            if ((& git -C $dir merge-base HEAD main).Trim() -eq $head) {
                throw ("fixture is NOT in its promised state: merge-base HEAD main == HEAD, so gate() takes " +
                       "the FALLBACK path, not the PRIMARY `git diff `$base..HEAD` path this builder exists to exercise")
            }
            New-Item -ItemType Directory -Path (Join-Path $dir '.clavity/agy-marks') -Force | Out-Null
            return [pscustomobject]@{ Dir = $dir; Head = $head }
            # THE CLEANUP MUST NOT BE ABLE TO EAT THE DIAGNOSIS. `-ErrorAction SilentlyContinue` suppresses
            # NON-terminating errors only; a terminating one (a locked handle, an invalid path) would abort
            # this catch block and throw ITS exception instead, destroying the original - so the failure the
            # builder actually hit would be replaced by a confusing cleanup error. Best-effort cleanup,
            # guaranteed rethrow.
            } catch { try { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue } catch { }; throw }
        }
        function New-AuditPayload { param([string]$Cwd)
            @{ tool_name = 'Bash'; tool_input = @{ command = 'git commit' }; cwd = $Cwd } | ConvertTo-Json -Compress
        }
        $script:Cwd = { param($d) ($d -replace '\\','/') }

        # As New-AuditPayload, but WITHOUT the forward-slashing every other test here applies. That
        # convention is repo-wide and is exactly why the Windows repo-root walk bug survived: a
        # POSIX-shaped path cannot exercise it.
        function New-RawAuditPayload { param([string]$Cwd)
            '{"tool_name":"Bash","tool_input":{"command":"git commit"},"cwd":"' + ($Cwd -replace '\\', '\\') + '","hook_event_name":"PostToolUse"}'
        }
        # A FIRE-state repo plus a subdirectory carrying its OWN capstone marker. The markers are
        # cwd-relative by contract (docs/agy-disciplines-marker-contract.md), so a session running in a
        # subdirectory writes them there - which is what makes the gate fire from the subdirectory.
        function New-FiredSubdir {
            $r = New-FiredRepo
            $sub = Join-Path $r.Dir 'src'
            New-Item -ItemType Directory -Path (Join-Path $sub '.clavity/agy-marks') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $sub '.clavity/agy-marks/agy-capstone.head') -Value $r.Head -NoNewline -Encoding ascii
            return [pscustomobject]@{ Dir = $r.Dir; Sub = $sub; Head = $r.Head }
        }

        # The COST clause VERBATIM. Asserted whole, not by bookend fragments: an audit mutant that deleted
        # its operative sentence ("tell the user it runs about 5x leaner...") from all four hooks left the
        # entire 45-test suite GREEN, because the assertions pinned only the opening token and the closing
        # words - leaving ~380 of its 399 characters, and everything actionable in it, unguarded.
        # PARSED OUT OF THE HOOK, never copied. A duplicated list is two definitions free to drift, and
        # the drift is invisible in BOTH directions: a copy here cannot fail when the hook's list is wrong,
        # and cannot notice when the hook's list changes. MEASURED 2026-08-26: the hook omitted `.iss`,
        # `.yml` and `justfile` - the installer, the workflows and the test gate of this very repository -
        # and the copy that lived here omitted exactly the same ones, so 20 green rows said nothing at all.
        $hookText = [System.IO.File]::ReadAllText($script:Hook, [System.Text.Encoding]::UTF8)
        $m = [regex]::Match($hookText, "(?m)^\s*local CODE_RE='([^']+)'\s*$")
        if (-not $m.Success) { throw 'cannot parse CODE_RE out of the hook - this fixture is inspecting nothing' }
        $script:CodeExtRe = '(?i)' + $m.Groups[1].Value
        $script:CostClause = 'COST: this discipline re-reads the whole session context every round, so running it in a long session burns several times the tokens - and subscription quota - of running it fresh. If this session carries substantial history, do not run it inline: tell the user it runs about 5x leaner after /compact or in a fresh session, and follow their answer. This changes WHERE the review runs, never WHETHER.'
        # Branch 20 debounce: the hook keeps per-(session, HEAD) state under TMPDIR. Every row here runs with
        # session_id 'default', so give the suite its own TMPDIR and clear the state before each row.
        $script:savedTmpdir = [Environment]::GetEnvironmentVariable('TMPDIR')
        $script:suiteTmp = Join-Path ([IO.Path]::GetTempPath()) ('tar-tmp-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:suiteTmp | Out-Null
        $env:TMPDIR = ($script:suiteTmp -replace '\\', '/')
    }
    BeforeEach { Get-ChildItem -LiteralPath $script:suiteTmp -Filter 'claude-agy-test-audit-reminder.*' -ErrorAction SilentlyContinue | Remove-Item -Force }
    AfterAll {
        # [NullString]::Value DELETES the variable; $null would leave it present-and-empty (see BashHookHelpers.ps1).
        if ($null -eq $script:savedTmpdir) { [Environment]::SetEnvironmentVariable('TMPDIR', [NullString]::Value) } else { $env:TMPDIR = $script:savedTmpdir }
        Remove-Item -LiteralPath $script:suiteTmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'FIRES the audit nudge when capstone.head==HEAD, no audit marker, code changed' {
        $r = New-FiredRepo
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Head
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut  | Should -Match 'AGY-TEST-AUDIT'
            $out.ExitCode | Should -Be 0
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'FIRES when the changed code file has an UPPERCASE extension (case-insensitive ext match)' {
        $r = New-FiredRepo -CodeFile 'src/Thing.CS'
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Head
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut  | Should -Match 'AGY-TEST-AUDIT'
            $out.ExitCode | Should -Be 0
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'FIRES when a changed code file has a NON-ASCII name (git quotePath must not defeat the ext grep)' {
        $r = New-FiredRepo -CodeFile ('src/Modulo_' + [char]0xE9 + '.cs')
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Head
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut  | Should -Match 'AGY-TEST-AUDIT'
            $out.ExitCode | Should -Be 0
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'is SILENT when the capstone marker is absent (capstone not run/green)' {
        $r = New-FiredRepo
        try {
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'FIRES when the capstone marker is BEHIND HEAD but only DOCS landed since (the ledger-row case)' {
        $r = New-PostMarkerRepo -Kind docs
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Cap
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut  | Should -Match 'AGY-TEST-AUDIT' -Because 'the capstone GREEN still stands when nothing executable landed after it, and committing the ledger row is the one thing the capstone skill REQUIRES - so a gate that goes silent on it is silenced by the very act of completing the review it gates'
            $out.ExitCode | Should -Be 0
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'is SILENT when the audit was completed at the reviewed tip and only the ledger row followed' {
        # THE EDGE THE LEDGER-ROW FIX ITSELF CREATED, and it punishes the driver who did the right thing.
        # fced293 relaxed the CAPSTONE marker so a docs-only ledger commit no longer invalidates the GREEN -
        # but left the AUDIT marker on a strict `aud == head`. So a driver who runs the audit at the reviewed
        # tip (the correct moment) and THEN commits the ledger row gets nudged to run it again: cap is
        # forgiven for being behind HEAD, aud is not. The two markers age for exactly the same reason and
        # must be forgiven by exactly the same rule.
        $r = New-PostMarkerRepo -Kind docs
        try {
            Set-Marker $r.Dir 'agy-capstone'   $r.Cap
            Set-Marker $r.Dir 'agy-test-audit' $r.Cap
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut | Should -BeNullOrEmpty -Because 'the audit already covered the reviewed tip and nothing executable has landed since, so demanding a second run is a false alarm - and it is aimed squarely at the driver who audited at the right moment instead of after the paperwork'
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'is SILENT when the audit ran AFTER the ledger row (audit marker at HEAD, capstone marker behind)' {
        # THE OTHER HALF OF THE MATRIX, and the reason the obvious one-line fix is wrong. Swapping
        # `aud == head` for `aud == cap` fixes the row above and breaks this one: an audit run after the
        # ledger commit has aud == head != cap, and would be nudged forever. Both orderings are legitimate,
        # so both must be silent - which is why the relaxation is shared rather than re-specified.
        $r = New-PostMarkerRepo -Kind docs
        try {
            Set-Marker $r.Dir 'agy-capstone'   $r.Cap
            Set-Marker $r.Dir 'agy-test-audit' $r.Head
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut | Should -BeNullOrEmpty -Because 'the audit ran at HEAD itself, which is the plainest possible "already done" - a fix for the row above that reddens this one has moved the bug rather than removed it'
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'is SILENT when the capstone marker is behind HEAD and CODE landed since (the GREEN is stale)' {
        $r = New-PostMarkerRepo -Kind code
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Cap
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut | Should -BeNullOrEmpty -Because 'executable code landed after the reviewed tip, so the capstone GREEN no longer describes HEAD and a re-capstone is owed before an audit means anything - this is the boundary that stops the relaxation above from becoming "any stale marker will do"'
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'treats this repository OWN gating file types as executable code' {
        # A LIST WITH NO ORACLE. The hook's CODE_RE decides two different things - whether a capstone GREEN
        # survives later commits, and whether a reviewed range is worth auditing - and until 2026-08-26 it
        # recognised none of the file types this project gates itself with. These are not hypothetical
        # extensions: each one below names a file this very review range changed.
        foreach ($p in @(
            'clavity-classic/installer/clavity-classic.iss', # a Pascal program that deletes user data
            '.github/workflows/build-classic.yml',          # rewritten by round 20
            'justfile',                                     # the test gate itself, no extension at all
            'scripts/drain-lib.ps1',                        # the original list did cover this
            'clavity-dotnet/plugin/hooks/agy-mark.sh'       # and this
        )) {
            $p | Should -Match $script:CodeExtRe -Because "the hook must treat '$p' as executable code, or a capstone GREEN is extended over changes nobody reviewed and no audit is ever nudged for them"
        }
        # And the boundary: prose must still NOT count, or every docs commit nudges for a test audit.
        foreach ($p in @('README.md', 'docs/coverage-debt.md', 'scripts/tests/_partition.md')) {
            $p | Should -Not -Match $script:CodeExtRe -Because "'$p' is prose - if it counted as executable code the docs-only silence this hook promises would be gone"
        }
    }
    It 'is SILENT when a capstone marker on a DIVERGENT branch would otherwise look current' {
        # THE ANCESTOR HALF'S ORACLE. The hook's own comment calls the merge-base test load-bearing, and
        # nothing exercised it: MEASURED 2026-08-26, deleting that line from both mirrors left this suite
        # 20/0 green. Its sibling row (a sha the repo does not contain) does NOT cover it - an unknown sha
        # fails the ancestor test AND every other test, so it passes for several reasons at once. This row
        # builds a sha that genuinely exists, is genuinely not an ancestor of HEAD, and carries no code
        # change - so ONLY the ancestor test can reject it.
        $r = New-PostMarkerRepo -Kind docs
        try {
            & git -C $r.Dir checkout -q -b sidebranch $r.Cap
            # The directory must be created: checking out the earlier commit removed docs/, and a
            # failed Set-Content here produces an EMPTY commit whose sha is the marker itself - which
            # IS an ancestor, so the row would have gone green while testing nothing. The
            # postcondition below caught exactly that on the first run.
            $side = Join-Path $r.Dir 'docs/side.md'
            New-Item -ItemType Directory -Path (Split-Path -Parent $side) -Force | Out-Null
            Set-Content -LiteralPath $side -Value 'x' -Encoding ascii
            & git -C $r.Dir add -A
            & git -C $r.Dir -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= commit -qm side
            $sideSha = (& git -C $r.Dir rev-parse HEAD).Trim()
            & git -C $r.Dir checkout -q feature
            & git -C $r.Dir merge-base --is-ancestor $sideSha $r.Head
            if ($LASTEXITCODE -eq 0) { throw 'fixture is NOT in its promised state: the side sha IS an ancestor of HEAD, so the ancestor test is not what would reject it' }
            Set-Marker $r.Dir 'agy-capstone' $sideSha
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut | Should -BeNullOrEmpty -Because 'a GREEN reached on a branch that was never merged says nothing about HEAD - without the ancestor test, any abandoned branch tip with no code after it would satisfy this gate'
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'is SILENT when the capstone marker names a sha this repository does not contain' {
        $r = New-FiredRepo
        try {
            Set-Marker $r.Dir 'agy-capstone' 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'is SILENT when the audit already ran at this HEAD (audit.head==HEAD)' {
        $r = New-FiredRepo
        try {
            Set-Marker $r.Dir 'agy-capstone'   $r.Head
            Set-Marker $r.Dir 'agy-test-audit' $r.Head
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'is SILENT on a docs-only reviewed range (no code/test paths changed)' {
        $r = New-FiredRepo -DocsOnly
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Head
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'is suppressed by .no-agy in cwd even when it would otherwise fire' {
        $r = New-FiredRepo
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Head
            New-Item -ItemType File -Path (Join-Path $r.Dir '.no-agy') -Force | Out-Null
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'no-jq: is suppressed by .no-agy in the PAYLOAD cwd (not the process cwd)' {
        $r = New-FiredRepo
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Head
            New-Item -ItemType File -Path (Join-Path $r.Dir '.no-agy') -Force | Out-Null
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir)) -Env @{ PATH = $script:NoJqPath }
            $out.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'FIRES via the primary diff-base path (main pinned behind HEAD, exercising diff base..HEAD)' {
        $r = New-DiffPathRepo
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Head
            $base = (& git -C $r.Dir merge-base HEAD main).Trim()
            $base | Should -Not -BeNullOrEmpty       # a real base commit exists (empty merge-base would fall to the single-commit path)
            $base | Should -Not -Be $r.Head          # and it is behind HEAD -> primary diff path, not fallback
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut  | Should -Match 'AGY-TEST-AUDIT'
            $out.ExitCode | Should -Be 0
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'emits a LOUD jq-missing line when it would fire but jq is absent' {
        $r = New-FiredRepo
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Head
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir)) -Env @{ PATH = $script:NoJqPath }
            $out.StdOut | Should -Match 'guard inactive: missing jq'
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'no-jq: is SILENT when the gate is closed (no capstone marker, no .no-agy), and fires once the marker exists' {
        # The header promises "never a false alarm" without jq. Every other silent no-jq row reaches silence through
        # .no-agy, which exits BEFORE the gate (agy test-audit R2, FPA1/AB1: forcing the degraded gate open left the
        # whole suite green). Same repo, same payload: only the marker differs, so the silence is the gate's answer.
        $r = New-FiredRepo
        try {
            $closed = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir)) -Env @{ PATH = $script:NoJqPath }
            $closed.StdOut | Should -BeNullOrEmpty -Because 'no capstone marker means the gate is closed, and the degraded path must say nothing'
            Set-Marker $r.Dir 'agy-capstone' $r.Head
            $open = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir)) -Env @{ PATH = $script:NoJqPath }
            $open.StdOut | Should -Match 'guard inactive: missing jq' -Because 'the control: this fixture DOES reach the warning once the gate opens'
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'carries the COST clause when it fires' {
        $r = New-FiredRepo
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Head
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut | Should -Match 'COST:'
            $out.StdOut | Should -Match 'never WHETHER'
            # Whole clause, so no interior sentence can be lost silently.
            $out.StdOut | Should -Match ([regex]::Escape($script:CostClause))
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    # --- .no-agy at the REPO ROOT, session cwd in a SUBDIRECTORY ---------------------------------
    # Each silence case is paired with a positive control, and the CONTROL is the load-bearing half:
    # measured on a sibling hook, a broken walk produced silence indistinguishable from a working
    # kill-switch, and only the control went red.
    It 'is SILENT when .no-agy is at the repo root and cwd is a subdirectory' {
        $r = New-FiredSubdir
        try {
            New-Item -ItemType File -Path (Join-Path $r.Dir '.no-agy') -Force | Out-Null
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (New-RawAuditPayload $r.Sub)
            $x.StdOut | Should -BeNullOrEmpty -Because 'an opt-out at the repo root must suppress this hook from a subdirectory'
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'FIRES from that same subdirectory when .no-agy is absent (positive control)' {
        # Also proves gate() receives a path that resolves: it binds `local cwd="$1"` rather than reading
        # the global, so passing the normalized value genuinely changes what it stats.
        $r = New-FiredSubdir
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (New-RawAuditPayload $r.Sub)
            $x.StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire' -Because 'without the opt-out it must still fire - otherwise the silence test proves nothing'
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'no-jq: is SILENT under a root .no-agy from a subdirectory' {
        # The degraded path recovered cwd with a `sed` capture that left the JSON escaping intact, so on
        # Windows every stat below it ran against a path that does not resolve. Nothing covered that.
        $r = New-FiredSubdir
        try {
            New-Item -ItemType File -Path (Join-Path $r.Dir '.no-agy') -Force | Out-Null
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (New-RawAuditPayload $r.Sub) -Env @{ PATH = $script:NoJqPath }
            $x.StdOut | Should -BeNullOrEmpty -Because 'the degraded path must honour the same root opt-out as the jq path'
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'no-jq: DOES emit the jq-missing line from that subdirectory without .no-agy (degraded control)' {
        # This is the assertion the old sed capture could not have satisfied on a backslashed payload:
        # reaching it requires gate() to find HEAD and the capstone marker through the recovered cwd.
        $r = New-FiredSubdir
        try {
            $x = Invoke-BashHook -HookPath $script:Hook -Payload (New-RawAuditPayload $r.Sub) -Env @{ PATH = $script:NoJqPath }
            $x.StdOut | Should -Match 'guard inactive: missing jq' -Because 'the degraded gate must resolve the real cwd, not a path still carrying JSON escapes'
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'ships as pure ASCII' {
        ($([IO.File]::ReadAllBytes($script:Hook)) | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
    # --- capstone Branch 2 round 2: a name-only diff must list BOTH sides of a rename and ignore the user's
    # diff.relative. Each row first proves the fixture FIRES at the reviewed tip, so its silence afterwards
    # is the gate's answer and not a fixture that could never fire.
    Context 'name-only diffs are rename-proof and cwd-proof' {
        BeforeEach {
            $script:NDir = New-TempRepo
            function script:NGit { & git -C $script:NDir -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= @args }
            NGit branch -f main HEAD
            NGit checkout -qb feature
            foreach ($p in 'src/keep.sh', 'src/auth.sh', 'sub/tool.sh') {
                $f = Join-Path $script:NDir $p
                New-Item -ItemType Directory -Path (Split-Path -Parent $f) -Force | Out-Null
                Set-Content -LiteralPath $f -Value ('echo ' + $p) -Encoding ascii
            }
            NGit add -A
            NGit commit -qm reviewed
            $script:NReviewed = (NGit rev-parse HEAD).Trim()
            foreach ($d in $script:NDir, (Join-Path $script:NDir 'sub')) {
                New-Item -ItemType Directory -Path (Join-Path $d '.clavity/agy-marks') -Force | Out-Null
            }
        }
        AfterEach { Remove-Item $script:NDir -Recurse -Force -ErrorAction SilentlyContinue }

        It 'is SILENT after a rename moves code out from under the capstone (src/auth.sh -> docs/old.md)' {
            Set-Marker $script:NDir 'agy-capstone' $script:NReviewed
            (Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $script:NDir))).StdOut | Should -Match 'AGY-TEST-AUDIT'
            New-Item -ItemType Directory -Path (Join-Path $script:NDir 'docs') -Force | Out-Null
            NGit mv src/auth.sh docs/old.md
            NGit commit -qm rename
            (Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $script:NDir))).StdOut | Should -BeNullOrEmpty
        }

        It 'is SILENT after a code change outside a subdirectory cwd, even under diff.relative=true' {
            $sub = Join-Path $script:NDir 'sub'
            Set-Marker $sub 'agy-capstone' $script:NReviewed
            (Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $sub))).StdOut | Should -Match 'AGY-TEST-AUDIT'
            Add-Content -LiteralPath (Join-Path $script:NDir 'src/keep.sh') -Value 'echo changed' -Encoding ascii
            NGit commit -qam 'code change outside sub/'
            NGit config diff.relative true
            (Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $sub))).StdOut | Should -BeNullOrEmpty
        }
    }

    # --- capstone Branch 2 round 3: the reviewed range must be found whatever the integration branch is called.
    # The shape is the one the capstone skill REQUIRES: code on a feature branch, capstone marker at that tip,
    # then the docs-only ledger-row commit. Falling back to HEAD's own commit sees only the ledger and goes
    # silent, so each row FIRES only if the base was found through the ref it names.
    Context 'the integration branch is not called main' {
        BeforeAll {
            function script:BGit { param($Dir) & git -C $Dir -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= @args }
            # Feature branch off the current branch: code commit, capstone marker there, then the ledger row.
            function script:New-LedgerFlow { param($Dir)
                BGit $Dir checkout -qb feature
                New-Item -ItemType Directory -Path (Join-Path $Dir 'src') -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $Dir 'src/a.sh') -Value 'echo a' -Encoding ascii
                BGit $Dir add -A; BGit $Dir commit -qm code
                New-Item -ItemType Directory -Path (Join-Path $Dir '.clavity/agy-marks') -Force | Out-Null
                Set-Marker $Dir 'agy-capstone' (BGit $Dir rev-parse HEAD).Trim()
                New-Item -ItemType Directory -Path (Join-Path $Dir 'docs') -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $Dir 'docs/agy-capstone-ledger.md') -Value 'row' -Encoding ascii
                BGit $Dir add docs; BGit $Dir commit -qm 'ledger row'
            }
        }

        It 'FIRES after the ledger-row commit in a repository whose integration branch is master' {
            $d = New-TempRepo
            try {
                BGit $d branch -M master
                (BGit $d branch --list main) | Should -BeNullOrEmpty
                New-LedgerFlow $d
                (Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $d))).StdOut | Should -Match 'AGY-TEST-AUDIT'
            } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It 'FIRES after the ledger-row commit in a clone whose default branch is trunk (found via origin/HEAD)' {
            $src = New-TempRepo
            $dst = $src + '-clone'
            try {
                BGit $src branch -M trunk
                & git clone -q $src $dst
                (BGit $dst rev-parse --abbrev-ref origin/HEAD).Trim() | Should -Be 'origin/trunk'
                New-LedgerFlow $dst
                (Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $dst))).StdOut | Should -Match 'AGY-TEST-AUDIT'
            } finally {
                Remove-Item $src -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'FIRES through CLAVITY_AUDIT_BASE_REF for a branch name no fallback knows (SILENT without it)' {
            # Test audit Branch 2 G3: no remote, no main, no master - only the override can find the base.
            $d = New-TempRepo
            try {
                BGit $d branch -M develop
                New-LedgerFlow $d
                $p = New-AuditPayload (& $script:Cwd $d)
                (Invoke-BashHook -HookPath $script:Hook -Payload $p).StdOut | Should -BeNullOrEmpty
                (Invoke-BashHook -HookPath $script:Hook -Payload $p -Env @{ CLAVITY_AUDIT_BASE_REF = 'develop' }).StdOut | Should -Match 'AGY-TEST-AUDIT'
            } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'is byte-identical to the clavity-classic mirror' {
        $classic = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'clavity-classic/plugin/hooks/agy-test-audit-reminder.sh'
        (Get-FileHash $script:Hook).Hash | Should -Be (Get-FileHash $classic).Hash
    }
}

Describe 'agy-test-audit-reminder debounce (once per session and HEAD; Branch 20, owner ruling O4)' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh'
        $script:Capture = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh'
        $script:DTmp = Join-Path ([IO.Path]::GetTempPath()) ('tar-dbn-' + [Guid]::NewGuid().ToString('N'))
        $script:DHome = Join-Path ([IO.Path]::GetTempPath()) ('tar-dbh-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:DTmp, (Join-Path $script:DHome '.claude') -Force | Out-Null
        function New-DebounceRepo {
            # The FIRES shape the suite's New-FiredRepo builds: one executable commit at HEAD, capstone marker on it.
            $dir = New-TempRepo
            New-Item -ItemType Directory -Path (Join-Path $dir 'src'), (Join-Path $dir '.clavity/agy-marks') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'src/thing.cs') -Value 'x' -Encoding ascii
            & git -C $dir add -- src/thing.cs
            & git -C $dir -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= commit -qm work
            Set-Content -LiteralPath (Join-Path $dir '.clavity/agy-marks/agy-capstone.head') -Value (& git -C $dir rev-parse HEAD).Trim() -NoNewline
            $dir
        }
        function Invoke-Debounced { param([string]$Dir, [string]$Sid, [string]$Tmp = $script:DTmp)
            $p = @{ tool_name = 'Bash'; tool_input = @{ command = 'ls' }; cwd = ($Dir -replace '\\', '/'); session_id = $Sid } | ConvertTo-Json -Compress
            Invoke-BashHook -HookPath $script:Hook -Payload $p -Env @{ TMPDIR = ($Tmp -replace '\\', '/'); HOME = ($script:DHome -replace '\\', '/') }
        }
    }
    AfterAll { Remove-Item -LiteralPath $script:DTmp, $script:DHome -Recurse -Force -ErrorAction SilentlyContinue }
    BeforeEach { Get-ChildItem -LiteralPath $script:DTmp -Force | Remove-Item -Recurse -Force }

    It 'fires on the first call and is silent on the second at the same HEAD and session' {
        $d = New-DebounceRepo
        try {
            (Invoke-Debounced $d 's1').StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire'
            (Invoke-Debounced $d 's1').StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'fires again for another session at the same HEAD' {
        $d = New-DebounceRepo
        try {
            (Invoke-Debounced $d 's1').StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire'
            (Invoke-Debounced $d 's2').StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'fires again after HEAD moves, in the same session' {
        $d = New-DebounceRepo
        try {
            (Invoke-Debounced $d 's1').StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire'
            (Invoke-Debounced $d 's1').StdOut | Should -BeNullOrEmpty
            Set-Content -LiteralPath (Join-Path $d 'src/other.cs') -Value 'y' -Encoding ascii
            & git -C $d add -- src/other.cs
            & git -C $d -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= commit -qm more
            Set-Content -LiteralPath (Join-Path $d '.clavity/agy-marks/agy-capstone.head') -Value (& git -C $d rev-parse HEAD).Trim() -NoNewline
            (Invoke-Debounced $d 's1').StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'still fires on every call when its state cannot be written (TMPDIR is a file)' {
        $d = New-DebounceRepo
        $f = Join-Path $script:DTmp 'not-a-dir'; Set-Content -LiteralPath $f -Value 'x'
        try {
            (Invoke-Debounced $d 's1' $f).StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire'
            (Invoke-Debounced $d 's1' $f).StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire' -Because 'a debounce that cannot record must fail toward reminding, never toward silence'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'keeps its state under TMPDIR only - the repo is untouched' {
        $d = New-DebounceRepo
        try {
            $before = (& git -C $d status --porcelain --ignored) -join "`n"
            $null = Invoke-Debounced $d 's1'
            ((& git -C $d status --porcelain --ignored) -join "`n") | Should -BeExactly $before
            Test-Path -LiteralPath (Join-Path $script:DTmp 'claude-agy-test-audit-reminder.s1') | Should -BeTrue
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'fires again after a compaction in the same session (PreCompact re-arms it)' {
        $d = New-DebounceRepo
        try {
            (Invoke-Debounced $d 's1').StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire'
            (Invoke-Debounced $d 's1').StdOut | Should -BeNullOrEmpty
            $pc = @{ cwd = ($d -replace '\\', '/'); session_id = 's1'; hook_event_name = 'PreCompact'; trigger = 'manual' } | ConvertTo-Json -Compress
            $null = Invoke-BashHook -HookPath $script:Capture -Payload $pc -Arguments @('PreCompact') -Env @{ TMPDIR = ($script:DTmp -replace '\\', '/'); HOME = ($script:DHome -replace '\\', '/') }
            (Invoke-Debounced $d 's1').StdOut | Should -Match 'AGY-TEST-AUDIT auto-fire' -Because 'a compaction summarized the reminder away, so it must come back once'
        } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

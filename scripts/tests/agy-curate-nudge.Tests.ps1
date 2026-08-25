Describe 'agy-curate-nudge.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot 'agy-autotrain/hooks/agy-curate-nudge.sh'

        # ROADMAP 14g: the canonical inbox is USER-LOCAL (~/.clavity/agy-observations.md), NOT the plugin
        # tree. Build an isolated HOME/USERPROFILE holding it, so a REAL ~/.clavity/.agy-curate-snooze on
        # the dev box cannot silence the hook and hand us a false green. Absolute paths only - MSYS mangles
        # relative HOME.
        #
        # CLAUDE_PLUGIN_ROOT is still set, and knowledge/agy-observations.md under it is a DECOY carrying
        # the OPPOSITE verdict from the canonical file. That decoy is a mutation control, not scenery: if
        # the hook ever reverts to reading the plugin tree, every test that asserts on the canonical
        # content flips, because the decoy always says the other thing. -Decoy defaults to a large, very
        # stale inbox (which WOULD nudge), so a silent-expecting test reds the moment the old path returns.
        function New-NudgeEnv { param([string]$Inbox, [string]$Decoy)
            $root = Join-Path ([IO.Path]::GetTempPath()) ("curate-nudge-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $root 'knowledge') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'home/.clavity') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'home/.clavity/agy-observations.md') -Value $Inbox -NoNewline
            if (-not $PSBoundParameters.ContainsKey('Decoy')) {
                $bullets = (1..50 | ForEach-Object { "- [heuristic] (peer/probabilistic) decoy $_  ·  ``[corpus]`` · 2000-01-01 · agy 1.0.0" }) -join "`n"
                $Decoy = "# decoy inbox in the PLUGIN TREE - the hook must never read this`n`n## Pending`n`n$bullets`n"
            }
            Set-Content -LiteralPath (Join-Path $root 'knowledge/agy-observations.md') -Value $Decoy -NoNewline
            [pscustomobject]@{
                Root = $root
                Env  = @{
                    CLAUDE_PLUGIN_ROOT = ($root -replace '\\','/')
                    USERPROFILE        = ((Join-Path $root 'home') -replace '\\','/')
                    HOME               = ((Join-Path $root 'home') -replace '\\','/')
                }
            }
        }

        $script:Today = (Get-Date).ToString('yyyy-MM-dd')
    }

    It 'reads the USER-LOCAL inbox and IGNORES one left in the plugin tree (ROADMAP 14g)' {
        # The architectural move's own oracle. The canonical inbox is quiet; the plugin tree holds a big,
        # very stale decoy. Reading the wrong one is LOUD, so this cannot pass by accident.
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) a recent capture  ``[corpus]`` - $script:Today - agy 1.1.19
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -BeNullOrEmpty -Because 'the canonical inbox has one recent entry; the 50 stale decoy bullets in the plugin tree must not be seen'
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'nudges from the USER-LOCAL inbox even when the plugin tree holds a CLEAN decoy' {
        # The other half of the control. Above proves the plugin tree cannot make the hook speak; this
        # proves it cannot make the hook stay silent. Either test alone is satisfiable by a broken hook.
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) a stale capture  ``[corpus]`` - 2020-01-01 - agy 1.0.10
"@
        $e = New-NudgeEnv -Inbox $inbox -Decoy "# clean decoy`n`n## Pending`n"
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -Match 'oldest pending entry \(2020-01-01\)'
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT when the only old date lives in a drain-log COMMENT, not on a pending bullet' {
        # The defect this pins: the age scan swept the whole region and picked 2020-01-01 out of an HTML
        # drain-log comment, so the nudge claimed an "oldest pending entry" that no bullet carries. Drain
        # logs are append-only, so that latched the nudge ON permanently - draining could never clear it.
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) a recent capture  ``[corpus]`` - $script:Today - agy 1.1.10

<!-- Drain log 2020-01-01 (agy 1.0.10): historical drain notes live here forever. -->
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -BeNullOrEmpty -Because 'one recent bullet is under the count threshold and nothing pending is old'
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'STILL nudges when a genuinely old date is on a PENDING BULLET' {
        # The control. Without this, "delete the age check" would pass the test above.
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) a stale capture  ``[corpus]`` - 2020-01-01 - agy 1.0.10
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -Match 'oldest pending entry \(2020-01-01\)'
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'counts ONLY pending bullets, ignoring dated lines inside drain-log comments' {
        # The count path was already correct (anchored to /^- \[/); pin it so a fix to the date scan
        # cannot regress it, and so the two scans stay symmetric.
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) one  ``[corpus]`` - $script:Today - agy 1.1.10
- [heuristic] (driver/probabilistic) two  ``[corpus]`` - $script:Today - agy 1.1.10

<!-- Drain log 2020-01-01: 79 entries in, 71 routed. -->
<!-- Drain log 2020-02-02: 8 entries in, 8 routed. -->
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env ($e.Env + @{ AGY_CURATE_NUDGE_THRESHOLD = '2' })
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -Match 'has 2 pending entries' -Because 'the two comment lines must not be counted as entries'
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reads the TRAILING stamp, not an earlier date mentioned in the bullet body' {
        # Capstone F1. awk match() takes the LEFTMOST date on the line, so a bullet whose TEXT mentions a
        # historical date reported that date as the entry's age - a false stale nag on a fresh capture.
        # Same defect CLASS as the drain-log bug: reading a date that is not the entry's stamp.
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) Regression first observed on 2021-04-15 during a probe  ``[corpus]`` - $script:Today - agy 1.1.10
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -BeNullOrEmpty -Because 'the entry stamp is today; 2021-04-15 is body prose, not the entry date'
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'finds the stamp when it sits on a CONTINUATION line of a wrapped bullet' {
        # Capstone F2, and a regression the bullet-anchor itself introduced: anchoring the date scan to
        # /^- \[/ made a wrapped bullet's stamp invisible, so a genuinely stale inbox went SILENT. False
        # silence is worse than a false nag - the maintenance never gets prompted at all.
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) An observation whose text is long enough to wrap
  across more than one line before the provenance stamp  ``[corpus]`` - 2020-01-01 - agy 1.0.10
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -Match 'oldest pending entry \(2020-01-01\)'
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'still ignores a drain-log comment date even when it follows a wrapped bullet' {
        # The two fixes must not re-open each other: widening the scan to continuation lines must not
        # start swallowing the append-only drain logs again.
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) An observation whose text wraps
  onto a second line  ``[corpus]`` - $script:Today - agy 1.1.10

<!-- Drain log 2020-01-01 (agy 1.0.10): historical notes live here forever. -->
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -BeNullOrEmpty -Because 'the drain log must stay out of scope after the record widening'
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'prefers the provenance STAMP over a later date in a post-stamp continuation note' {
        # Capstone round 2. The mirror image of F1: taking the LAST date in the record picks up a
        # historical date mentioned in a note AFTER the stamp. Third variant of one root cause - which
        # date is the ENTRY's date - so the rule is now "prefer the stamp", not "prefer a position".
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) Primary capture text  ``[corpus]`` - $script:Today - agy 1.1.10
  Note: investigated a past regression first seen on 2021-05-01 in probe logs.
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -BeNullOrEmpty -Because 'the stamp is today; 2021-05-01 is prose in a post-stamp note'
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'falls back to the last date in the record when no agy-version stamp is present' {
        # The stamp preference must DEGRADE, not replace: an entry written without the trailing
        # "agy <version>" suffix must still age correctly rather than going silent.
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) an entry with no version suffix  ``[corpus]`` - 2020-01-01
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -Match 'oldest pending entry \(2020-01-01\)'
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does not mistake a prose date followed by the word agy for the stamp' {
        # Capstone round 3. The stamp rule keyed only on what FOLLOWS the date, so prose of the shape
        # "<date> agy <word>" impersonated a stamp. In an inbox whose entries are ABOUT agy that phrasing
        # is ordinary, not exotic. The discriminator: a real stamp is DELIMITED (preceded by punctuation
        # such as the middle dot), whereas a prose date is preceded by a word.
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) capture text  ``[corpus]`` - $script:Today - agy 1.1.10
  Repro: tested on 2021-05-01 agy probe where it failed.
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -BeNullOrEmpty -Because '2021-05-01 is prose preceded by the word "on", not a delimited stamp'
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'still reads a stamp delimited by the real middle-dot separator' {
        # Guard the fix above against over-tightening: the LIVE inbox delimits with U+00B7, not ASCII.
        $mid = [char]0x00B7
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) real-format entry  ``[corpus]`` $mid 2020-01-01 $mid agy 1.0.10
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -Match 'oldest pending entry \(2020-01-01\)'
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a .no-agy kill-switch even when the inbox is genuinely stale' {
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) a stale capture  ``[corpus]`` - 2020-01-01 - agy 1.0.10
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            $cwd = Join-Path $e.Root 'work'
            New-Item -ItemType Directory -Path $cwd -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $cwd '.no-agy') -Value '' -NoNewline
            $payload = @{ cwd = ($cwd -replace '\\','/') } | ConvertTo-Json -Compress
            $r = Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a .no-agy sitting under USERPROFILE when HOME points somewhere else' {
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) a stale capture  ``[corpus]`` - 2020-01-01 - agy 1.0.10
"@
        # CONTROL for the kill-switch resolution split. The inbox and snooze resolve via
        # ${USERPROFILE:-$HOME} (agy-curate-nudge.sh:8) but the marker was read from BARE ${HOME} (:22).
        # MEASURED: `env -u HOME bash --noprofile --norc -c` leaves HOME empty and does NOT backfill it
        # from USERPROFILE, so a parent exporting only USERPROFILE silently DISARMS the switch.
        $h = Join-Path ([IO.Path]::GetTempPath()) ("nudgehome-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $h -Force | Out-Null
        $e1 = New-NudgeEnv -Inbox $inbox
        $e2 = New-NudgeEnv -Inbox $inbox
        try {
            $payload = @{ cwd = 'C:/nowhere' } | ConvertTo-Json -Compress
            # PRECONDITION. HOME pointed away, no marker anywhere: this inbox is stale so it DOES nudge.
            # Without this, the silence below could be the setup rather than the kill switch.
            $e1.Env['HOME'] = ($h -replace '\\','/')
            $r1 = Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env $e1.Env
            $r1.StdOut | Should -Not -BeNullOrEmpty -Because 'precondition: a stale inbox nudges when no marker exists'

            New-Item -ItemType Directory -Path (Join-Path $e2.Root 'home/.claude') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $e2.Root 'home/.claude/.no-agy') -Value '' -NoNewline
            $e2.Env['HOME'] = ($h -replace '\\','/')
            $r2 = Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env $e2.Env
            $r2.ExitCode | Should -Be 0
            $r2.StdOut | Should -BeNullOrEmpty -Because 'a .no-agy under USERPROFILE must silence the nudge even when HOME resolves elsewhere'
        } finally {
            Remove-Item -LiteralPath $e1.Root -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $e2.Root -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'is SILENT under a .no-agy in the HOME root when USERPROFILE points somewhere else' {
        # THE MISSING HALF of the kill-switch control. The test above plants the marker under USERPROFILE
        # and so only ever exercises the HOME_DIR clause; New-NudgeEnv sets HOME == USERPROFILE, so the
        # bare-${HOME} clause was DEAD to this whole suite. MEASURED at f29cd42: deleting that clause left
        # all 14 tests green while a marker under a divergent HOME stopped silencing the hook - a kill
        # switch failing OPEN, certified green. Both sibling suites already cover this cell
        # (agy-learn-reminder.Tests.ps1, agy-inbox-snapshot.Tests.ps1); the asymmetry was here.
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) a stale capture  ``[corpus]`` - 2020-01-01 - agy 1.0.10
"@
        $h = Join-Path ([IO.Path]::GetTempPath()) ("nudgehome-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $h '.claude') -Force | Out-Null
        $e1 = New-NudgeEnv -Inbox $inbox
        $e2 = New-NudgeEnv -Inbox $inbox
        try {
            $payload = @{ cwd = 'C:/nowhere' } | ConvertTo-Json -Compress
            # PRECONDITION. Same divergent-HOME setup, no marker anywhere: this stale inbox DOES nudge.
            # Without it the silence below could be the setup rather than the kill switch.
            $e1.Env['HOME'] = ($h -replace '\\','/')
            $r1 = Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env $e1.Env
            $r1.StdOut | Should -Not -BeNullOrEmpty -Because 'precondition: a stale inbox nudges when no marker exists'

            # The marker goes under HOME only. The USERPROFILE root must NOT carry one, or the HOME_DIR
            # clause would silence the hook first and this test could not tell the two clauses apart.
            Set-Content -LiteralPath (Join-Path $h '.claude/.no-agy') -Value '' -NoNewline
            $e2.Env['HOME'] = ($h -replace '\\','/')
            (Test-Path (Join-Path $e2.Root 'home/.claude/.no-agy')) | Should -BeFalse -Because 'the USERPROFILE root must NOT carry a marker, or this cannot distinguish which clause fired'
            $r2 = Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env $e2.Env
            $r2.ExitCode | Should -Be 0
            $r2.StdOut | Should -BeNullOrEmpty -Because 'a .no-agy under bare $HOME must silence the nudge - a kill switch may only ever fail SAFE'
        } finally {
            Remove-Item -LiteralPath $e1.Root -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $e2.Root -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'resolves the inbox from HOME when USERPROFILE is ABSENT, and when it is EMPTY' {
        # HOME_DIR="${USERPROFILE:-$HOME}" (agy-curate-nudge.sh:8). Every harness in this suite sets BOTH
        # variables to real absolute paths, so the fallback half was never taken on any machine, and CI is
        # windows-latest. MEASURED at f29cd42: rewriting it to "${USERPROFILE}" left all 14 tests green,
        # while on a POSIX install the inbox resolved to /.clavity/agy-observations.md and the hook went
        # PERMANENTLY SILENT - no nudge, and no snapshot ever taken before a drain.
        # The two cells are different bugs: ABSENT catches dropping the fallback entirely; EMPTY catches
        # the one-character ${USERPROFILE-$HOME} (no colon), which treats present-but-empty as set.
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) a stale capture  ``[corpus]`` - 2020-01-01 - agy 1.0.10
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            # PRECONDITION: with both set the usual way this fixture nudges. It is the baseline the two
            # assertions below are measured against.
            $base = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $base.StdOut | Should -Match 'agy-curate nudge' -Because 'precondition: this inbox is stale enough to nudge'

            $absent = $e.Env.Clone()
            $absent['USERPROFILE'] = [NullString]::Value   # the only form that DELETES - see BashHookHelpers.ps1
            $r1 = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $absent
            $r1.StdOut | Should -Match 'agy-curate nudge' -Because 'with USERPROFILE absent the inbox must resolve from HOME, not vanish'

            $empty = $e.Env.Clone()
            $empty['USERPROFILE'] = ''
            $r2 = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $empty
            $r2.StdOut | Should -Match 'agy-curate nudge' -Because 'an EMPTY USERPROFILE must fall back too - the colon in ${VAR:-alt} is load-bearing'
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'uses the LAST date in an un-stamped record, not the first one in its body' {
        # The no-version-suffix fallback branch. The existing test for it uses a record carrying exactly
        # ONE date, so first and last coincide and the branch's actual rule is unpinned. MEASURED at
        # f29cd42: taking the FIRST date instead of the last is invisible on that fixture, and on this one
        # it reports 2019-01-01 for an entry captured today - a permanent false stale nag that draining
        # cannot clear, the exact defect class the surrounding tests exist to close.
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) regression first seen on 2019-01-01 during a probe  ``[corpus]`` - $script:Today
"@
        # PRECONDITION, matching the three sibling Its added alongside this one. The only assertion
        # here is SILENCE, and silence is the default failure of a broken fixture: a `## Pending` typo,
        # or a change to the `^- \[` bullet anchor, produces silence for the wrong reason and this test
        # passes. So the same record is first shown to nudge when its trailing stamp IS old.
        $stale = $inbox -replace [regex]::Escape($script:Today), '2019-06-01'
        $ePre = New-NudgeEnv -Inbox $stale
        try {
            $pre = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $ePre.Env
            $pre.StdOut | Should -Match 'agy-curate nudge' -Because 'precondition: this fixture DOES nudge when its trailing stamp is old, so the silence below is the date rule and not a broken fixture'
        } finally { Remove-Item -LiteralPath $ePre.Root -Recurse -Force -ErrorAction SilentlyContinue }

        $e = New-NudgeEnv -Inbox $inbox
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -BeNullOrEmpty -Because "the record's stamp is today; 2019-01-01 is body prose, so nothing is stale"
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports the OLDEST pending entry when several bullets carry DIFFERENT dates' {
        # Asserts WHICH date is selected, from a set where selection is observable. Every other dated
        # fixture in this suite holds exactly one dated bullet, so "oldest" was never distinguished from
        # "newest", "first" or "last". MEASURED at f29cd42: flipping the comparison to report the NEWEST
        # left all 14 tests green and made this inbox fall SILENT - an ancient backlog that never nudges,
        # which this suite itself names as the worse of the two failures.
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) recent one  ``[corpus]`` - $script:Today - agy 1.1.19
- [heuristic] (driver/probabilistic) the ancient one  ``[corpus]`` - 2020-01-01 - agy 1.0.10
- [heuristic] (driver/probabilistic) recent two  ``[corpus]`` - $script:Today - agy 1.1.19
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $r.StdOut | Should -Match 'oldest pending entry \(2020-01-01\)' -Because 'the OLDEST of the three must be reported, not the newest and not the first encountered'
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'escalates to OVERDUE only at TWICE the threshold, not at the threshold' {
        # The escalating wording is the point of the count branch, and nothing asserted it. The one count
        # test asserts the substring 'has N pending entries', which BOTH messages contain. MEASURED at
        # f29cd42: lowering the escalation trigger from 2x to 1x made every nudge read OVERDUE - the
        # signal destroyed - with all 14 tests green.
        $mkInbox = {
            param([int]$n)
            $rows = (1..$n | ForEach-Object { "- [heuristic] (driver/probabilistic) e$_  ``[corpus]`` - $script:Today - agy 1.1.19" }) -join "`n"
            "# agy observations inbox`n`n## Pending`n`n$rows`n"
        }
        # THRESHOLD=3, NOT 2. At T=2 the fixture is DEGENERATE: T*2, T+2 and T-squared are all 4, so
        # every one of those relations satisfies the same two cells and the multiplicative rule the test
        # names is unpinned. MEASURED: with T=2 the mutant `-ge $((THRESHOLD + 2))` produced byte-identical
        # output at n=2 and n=4. At T=3 the boundary separates - T*2 is 6 while T+2 is 5 - so the n=5 cell
        # below is the one that actually discriminates, and the mutant reds there.
        # Real-world stake: at the shipped default THRESHOLD=8, a `+2` regression escalates every nudge to
        # OVERDUE at 10 entries instead of 16, destroying the escalation signal.
        $atThreshold = New-NudgeEnv -Inbox (& $mkInbox 3)
        $between     = New-NudgeEnv -Inbox (& $mkInbox 5)
        $atTwice     = New-NudgeEnv -Inbox (& $mkInbox 6)
        try {
            $env3 = @{ AGY_CURATE_NUDGE_THRESHOLD = '3' }
            $r1 = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env ($atThreshold.Env + $env3)
            $r1.StdOut | Should -Match 'Consider running' -Because 'precondition: it must be nudging at all, or the absence of OVERDUE below proves nothing'
            $r1.StdOut | Should -Not -Match 'OVERDUE' -Because 'at exactly the threshold the wording must stay the gentle one'

            # THE DISCRIMINATING CELL. 5 is above T+2 but below T*2, so only a genuine doubling rule
            # keeps this gentle.
            $r2 = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env ($between.Env + $env3)
            $r2.StdOut | Should -Match 'Consider running' -Because 'precondition: 5 entries still nudge'
            $r2.StdOut | Should -Not -Match 'OVERDUE' -Because 'five entries is above threshold+2 but below threshold*2, so only a true doubling rule stays gentle here'

            $r3 = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env ($atTwice.Env + $env3)
            $r3.StdOut | Should -Match 'OVERDUE' -Because 'at twice the threshold the wording must escalate'
        } finally {
            Remove-Item -LiteralPath $atThreshold.Root -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $between.Root -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $atTwice.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'honours a FRESH .agy-curate-snooze and ignores a STALE one' {
        # The snooze branch (agy-curate-nudge.sh:33-35) had no test at all - 'snooze' appeared in this
        # suite twice, both times inside a comment. Inverting the 7-day comparison, or repointing SNOOZE
        # at the plugin tree, either silences the nudge forever or makes the documented opt-out inert,
        # and nothing went red either way.
        $inbox = @"
# agy observations inbox

## Pending

- [heuristic] (driver/probabilistic) a stale capture  ``[corpus]`` - 2020-01-01 - agy 1.0.10
"@
        $e = New-NudgeEnv -Inbox $inbox
        try {
            # PRECONDITION: with no snooze marker this inbox nudges.
            $base = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $base.StdOut | Should -Match 'agy-curate nudge' -Because 'precondition: without a snooze this fixture nudges'

            $snooze = Join-Path $e.Root 'home/.clavity/.agy-curate-snooze'
            Set-Content -LiteralPath $snooze -Value '' -NoNewline
            $fresh = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $fresh.StdOut | Should -BeNullOrEmpty -Because 'a snooze younger than 7 days must silence the nudge'

            # SIX DAYS - the cell that actually pins the window. A fresh/8-day pair leaves the whole
            # (0,8) interval unconstrained: MEASURED, shrinking the window from 7 days to ONE HOUR is
            # byte-identical on both of those cells, and the emitted message literally offers a "Snooze
            # for 7 days". The 6-day cell is where a shrunk window diverges - orig stays silent, the
            # one-hour mutant nudges.
            (Get-Item -LiteralPath $snooze).LastWriteTime = (Get-Date).AddDays(-6)
            $stillFresh = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $stillFresh.StdOut | Should -BeNullOrEmpty -Because 'six days is inside the documented 7-day window, so the opt-out must still hold'

            (Get-Item -LiteralPath $snooze).LastWriteTime = (Get-Date).AddDays(-8)
            $stale = Invoke-BashHook -HookPath $script:Hook -Payload '{}' -Env $e.Env
            $stale.StdOut | Should -Match 'agy-curate nudge' -Because 'a snooze older than 7 days has expired and must NOT keep silencing the nudge'
        } finally { Remove-Item -LiteralPath $e.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

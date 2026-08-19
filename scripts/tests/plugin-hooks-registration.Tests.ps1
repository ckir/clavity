# REGISTRATION structure of the shipped hooks.json in both drivers.
#
# Distinct responsibility from plugin-hooks-payload.Tests.ps1, which guards the .sh BYTES (ASCII, parity).
# This file guards WHICH hook is registered under WHICH matcher - a property no .sh test can see.
#
# EVERY ASSERTION WALKS THE PARSED JSON AND CHECKS A HOOK'S OWNING MATCHER OBJECT. A substring search
# over the raw file cannot tell which hook a matcher governs, which is exactly the distinction the
# SessionStart split exists to create.

Describe 'shipped plugin hook registration' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Manifests = @{
            dotnet    = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/hooks.json'
            classic   = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks/hooks.json'
            autotrain = Join-Path $script:RepoRoot 'agy-autotrain/hooks/hooks.json'
        }

        # Return the matcher values of every object under $Event whose hooks array mentions $Script.
        # A hook registered twice yields two values, which the callers assert on explicitly.
        function Get-OwningMatchers { param([string]$Manifest, [string]$Event, [string]$Script)
            $json = Get-Content -Raw -LiteralPath $Manifest | ConvertFrom-Json
            @(foreach ($group in @($json.hooks.$Event)) {
                if (@($group.hooks) | Where-Object { $_.command -like "*$Script*" }) { $group.matcher }
            })
        }
        # Count the OBJECTS under $Event whose hooks array mentions $Script. Deliberately distinct from
        # Get-OwningMatchers above, which returns each owning group's matcher VALUE: "matcher" is an
        # OPTIONAL key, so a group that omits it yields $null and vanishes into every emptiness check.
        # Presence assertions can use either (they compare the matcher string); ABSENCE assertions must use
        # this one, because it counts a matcher-less group as the registration it is.
        function Get-OwningGroupCount { param([string]$Manifest, [string]$Event, [string]$Script)
            $json = Get-Content -Raw -LiteralPath $Manifest | ConvertFrom-Json
            @(foreach ($group in @($json.hooks.$Event)) {
                if (@($group.hooks) | Where-Object { $_.command -like "*$Script*" }) { 1 }
            }).Count
        }
        function Get-AllCommands { param([string]$Manifest)
            $json = Get-Content -Raw -LiteralPath $Manifest | ConvertFrom-Json
            @(foreach ($event in $json.hooks.PSObject.Properties) {
                foreach ($group in @($event.Value)) { foreach ($h in @($group.hooks)) { $h.command } }
            })
        }
    }

    It 'registers agy-anomaly-reminder.sh in its OWN SessionStart object on startup|resume|clear|compact - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        $m = $script:Manifests[$Driver]
        $matchers = @(Get-OwningMatchers -Manifest $m -Event 'SessionStart' -Script 'agy-anomaly-reminder.sh')
        $matchers.Count | Should -Be 1
        $matchers[0]    | Should -BeExactly 'startup|resume|clear|compact'
    }

    It 'keeps agy-liveness-check.sh on startup ALONE - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        # THE REGRESSION THE STRUCTURAL SPLIT EXISTS TO PREVENT. SessionStart was ONE matcher object
        # holding several hooks, so naively widening its matcher string would also widen the liveness
        # check - which is documented as "the ONE boot-time liveness surface" and exits 2 with loud
        # advisories, so it would spam the transcript on every /compact mid-task.
        # NEGATIVE assertion: it passes on a clean baseline by construction. Its non-vacuity is proven by
        # a merge-the-objects mutation recorded in the plan for this task.
        $m = $script:Manifests[$Driver]
        $matchers = @(Get-OwningMatchers -Manifest $m -Event 'SessionStart' -Script 'agy-liveness-check.sh')
        $matchers.Count | Should -Be 1
        $matchers[0]    | Should -BeExactly 'startup'
    }

    It 'keeps classic-only agy-drive-session-reset.sh on startup ALONE' {
        # Re-firing a DRIVER-STATE RESET on every compaction is a behaviour change, not a notification
        # change - a strictly worse outcome than the liveness spam above.
        $matchers = @(Get-OwningMatchers -Manifest $script:Manifests['classic'] -Event 'SessionStart' -Script 'agy-drive-session-reset.sh')
        $matchers.Count | Should -Be 1
        $matchers[0]    | Should -BeExactly 'startup'
    }

    It 'does NOT register agy-drive-session-reset.sh under dotnet at all' {
        # It is classic-only. The seed-sync gate filters it out of its SessionStart comparison, so if
        # dotnet ever registered it the filter would strip it there too and report GREEN.
        # The non-empty guard is load-bearing: a missing or empty manifest yields no commands, and a
        # -Not -Match against an empty string passes. Measured three times this session that an
        # assertion satisfied by the absence of its subject reads as coverage while proving nothing.
        $cmds = Get-AllCommands $script:Manifests['dotnet']
        $cmds.Count | Should -BeGreaterThan 0 -Because 'an empty command set satisfies the negative below vacuously'
        ($cmds -join ' ') | Should -Not -Match 'agy-drive-session-reset'
    }

    It 'registers the capture reminder on PreCompact manual|auto - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        $matchers = @(Get-OwningMatchers -Manifest $script:Manifests[$Driver] -Event 'PreCompact' -Script 'agy-anomaly-capture-reminder.sh')
        $matchers.Count | Should -Be 1
        $matchers[0]    | Should -BeExactly 'manual|auto'
    }

    It 'registers the dispatch reminder on PreToolUse Agent|Task - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        # Agent|Task, not Agent. The observed tool name in this runtime is Agent, but binding to one
        # literal makes the hook a silent no-op if a dispatch arrives under the other, and the existing
        # matchers are already alternations, so it costs nothing.
        $matchers = @(Get-OwningMatchers -Manifest $script:Manifests[$Driver] -Event 'PreToolUse' -Script 'agy-anomaly-dispatch-reminder.sh')
        $matchers.Count | Should -Be 1
        $matchers[0]    | Should -BeExactly 'Agent|Task'
    }

    It 'leaves agy-seam-inject.sh on PreToolUse Skill - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        $matchers = @(Get-OwningMatchers -Manifest $script:Manifests[$Driver] -Event 'PreToolUse' -Script 'agy-seam-inject.sh')
        $matchers.Count | Should -Be 1
        $matchers[0]    | Should -BeExactly 'Skill'
    }

    It 'names only hook files that EXIST in that plugin - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }, @{ Driver = 'autotrain' }
    ) {
        # A typo in a command path registers a hook that can never fire, and a hook that never fires
        # cannot report its own absence.
        $m = $script:Manifests[$Driver]
        $dir = Split-Path -Parent $m
        $cmds = Get-AllCommands $m
        $cmds.Count | Should -BeGreaterThan 0 -Because 'an empty command set would pass the loop below vacuously'
        $missing = foreach ($c in $cmds) {
            if ($c -match 'hooks/([A-Za-z0-9._-]+\.sh)') {
                $f = Join-Path $dir $Matches[1]
                if (-not (Test-Path -LiteralPath $f)) { $Matches[1] }
            }
        }
        ($missing -join '; ') | Should -BeNullOrEmpty
    }

    It 'ships no hook file that is reachable from nowhere - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }, @{ Driver = 'autotrain' }
    ) {
        # THE OTHER DIRECTION, and nothing tested it before. The test above checks every registered
        # command has a file; this checks every file is registered. A hook that ships but appears in no
        # matcher NEVER FIRES -- and, exactly like the gap this whole change exists to close, an absent
        # nudge and a nudge with nothing to say are indistinguishable from outside. It is the natural
        # outcome of adding the .sh and forgetting hooks.json, which this plan asks an engineer to do
        # four times across Tasks 1-3.
        #
        # A dot-sourced LIBRARY is legitimately unregistered -- agy-consult-guard-lib.sh is sourced by
        # both consult guards -- so a file referenced from ANOTHER hook counts as reachable. The
        # reference search deliberately EXCLUDES the file itself: nearly every hook here names itself in
        # its own header comment, so searching its own body would let every file self-certify and the
        # test would pass vacuously forever.
        $m    = $script:Manifests[$Driver]
        $dir  = Split-Path -Parent $m
        $cmds = (Get-AllCommands $m) -join ' '
        $files = @(Get-ChildItem -LiteralPath $dir -Filter *.sh -File -ErrorAction Stop)
        $files.Count | Should -BeGreaterThan 0 -Because 'an empty hook dir would pass the loop below vacuously'

        # A THIRD LEGITIMATE CALLER: a shipped SKILL. ROADMAP 14c added agy-mark.sh, the sanctioned
        # .clavity writer. It is deliberately NOT in hooks.json - it is not a hook - and it is not
        # sourced by another hook either; the discipline skills invoke it as
        # `bash "<BASE>/../../hooks/agy-mark.sh"`, which is the delivery model the owner chose. Before
        # this clause, that made it read as unreachable and reddened this row on both drivers.
        # Same reasoning the dot-sourced-library carve-out above already encodes: the row's real claim is
        # "nothing ships that NOTHING can invoke", not "everything is in hooks.json".
        $skillsDir = Join-Path (Split-Path -Parent $dir) 'skills'
        $skillFiles = @(if (Test-Path -LiteralPath $skillsDir) {
            Get-ChildItem -LiteralPath $skillsDir -Recurse -File -Filter *.md -ErrorAction SilentlyContinue
        })
        # NON-VACUITY GUARD. All three drivers ship skills; if this ever resolves empty the widening
        # silently stops widening, and a genuinely unreachable file would still be caught (it fails
        # CLOSED) - but the clause above would be dead code nobody notices.
        $skillFiles.Count | Should -BeGreaterThan 0 -Because "every driver ships skills; an empty $skillsDir means this clause stopped searching anything"
        $skillText = ($skillFiles | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"

        $unreachable = foreach ($f in $files) {
            if ($cmds -like "*$($f.Name)*") { continue }
            $others = ($files | Where-Object { $_.Name -ne $f.Name } |
                       ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
            if ($others -match [regex]::Escape($f.Name)) { continue }
            if ($skillText -match [regex]::Escape($f.Name)) { continue }
            $f.Name
        }
        ($unreachable -join '; ') | Should -BeNullOrEmpty
    }

    It 'registers the model notice in the SAME SessionStart object as the drain reminder - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        # Sharing the object is what guarantees the two halves fire on exactly the same occasions. It must
        # NOT land in the startup object, which acceptance criterion 6 reserves for the untouched
        # liveness and reset hooks.
        $m = $script:Manifests[$Driver]
        $notice = @(Get-OwningMatchers -Manifest $m -Event 'SessionStart' -Script 'agy-anomaly-model-notice.sh')
        $drain  = @(Get-OwningMatchers -Manifest $m -Event 'SessionStart' -Script 'agy-anomaly-reminder.sh')
        $notice.Count | Should -Be 1
        $drain.Count  | Should -Be 1
        $notice[0]    | Should -BeExactly $drain[0]
        $notice[0]    | Should -BeExactly 'startup|resume|clear|compact'
    }

    It 'registers agy-discipline-reaching.sh on SessionStart startup|resume|clear|compact - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        $m = $script:Manifests[$Driver]
        $matchers = @(Get-OwningMatchers -Manifest $m -Event 'SessionStart' -Script 'agy-discipline-reaching.sh')
        $matchers.Count | Should -Be 1 -Because 'exactly one SessionStart object may own this hook'
        $matchers[0] | Should -BeExactly 'startup|resume|clear|compact' -Because 'the owner ruled it fires on all four sources'
    }

    It 'registers agy-discipline-reaching.sh on SessionEnd NOWHERE - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        # COUNT THE OWNING GROUPS, NOT THEIR MATCHER VALUES. This assertion was first written as
        # `@(Get-OwningMatchers ...) | Should -BeNullOrEmpty` and it passed VACUOUSLY. MEASURED 2026-08-05:
        # a group with no "matcher" key makes Get-OwningMatchers emit $null, so the array is @($null) with
        # Count 1, and Should -BeNullOrEmpty accepts a piped $null. The deleted SessionEnd block had exactly
        # that shape - `{ "hooks": [...] }` with no matcher sibling - so the absence test would have passed
        # against the very registration it exists to forbid. An absence assertion must not be written on a
        # LABEL that is allowed to be absent.
        $m = $script:Manifests[$Driver]
        Get-OwningGroupCount -Manifest $m -Event 'SessionEnd' -Script 'agy-discipline-reaching.sh' |
            Should -Be 0 -Because '${CLAUDE_PLUGIN_ROOT} does not resolve at SessionEnd; the hook is cancelled and writes nothing'
    }

    It 'registers the capture reminder on UserPromptSubmit in exactly one BARE group - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        # COUNT GROUPS, NOT MATCHER VALUES. This group has no "matcher" key by design -- nothing establishes
        # that a matcher is evaluated against prompt text for this event, so the discrimination lives in the
        # script. Get-OwningMatchers would yield $null here and every emptiness check would accept it.
        $m = $script:Manifests[$Driver]
        Get-OwningGroupCount -Manifest $m -Event 'UserPromptSubmit' -Script 'agy-anomaly-capture-reminder.sh' |
            Should -Be 1
    }

    It 'passes the event name as an argument on UserPromptSubmit - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        # Without the argument the hook defaults to PreCompact wording and emits the wrong envelope --
        # a failure that produces no error and looks installed and working.
        $json = Get-Content -Raw -LiteralPath $script:Manifests[$Driver] | ConvertFrom-Json
        $cmds = @(foreach ($g in @($json.hooks.UserPromptSubmit)) { foreach ($h in @($g.hooks)) { $h.command } })
        ($cmds -join ' ') | Should -Match 'agy-anomaly-capture-reminder\.sh.*UserPromptSubmit'
    }

    It 'keeps the capture reminder on PreCompact manual|auto as well - <Driver>' -ForEach @(
        @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
    ) {
        # The new channel ADDS to the compaction channel; it does not replace it. A long session that compacts
        # should still get the pre-compaction prompt, whose wording is specific to that moment.
        $matchers = @(Get-OwningMatchers -Manifest $script:Manifests[$Driver] -Event 'PreCompact' -Script 'agy-anomaly-capture-reminder.sh')
        $matchers.Count | Should -Be 1
        $matchers[0]    | Should -BeExactly 'manual|auto'
    }

    It 'registers <Script> on SessionStart startup|resume|clear|compact - agy-autotrain' -ForEach @(
        @{ Script = 'agy-learn-reminder.sh' }
        @{ Script = 'agy-curate-nudge.sh' }
    ) {
        # agy-autotrain/hooks/hooks.json was covered by NOTHING until now: the suite was parameterised
        # over dotnet/classic only, and its two SessionStart matchers had drifted to complementary,
        # non-overlapping SUBSETS of the convention - 'startup|clear|compact' and 'startup|resume'. The
        # visible consequence was that the agy-LEARN reminder never fired on a RESUMED session.
        $matchers = @(Get-OwningMatchers -Manifest $script:Manifests['autotrain'] -Event 'SessionStart' -Script $Script)
        $matchers.Count | Should -Be 1 -Because 'exactly one SessionStart object may own this hook'
        # -BeExactly, matching the sibling assertions: a future PARTIAL subset must fail, not pass quietly.
        $matchers[0] | Should -BeExactly 'startup|resume|clear|compact' -Because 'this repo pins all four sources; a subset silently drops a channel'
    }

    It 'pins the SessionStart matcher of EVERY agy-autotrain hook, not a named list - agy-autotrain' {
        # THE ROW ABOVE NAMES ITS TWO HOOKS IN A -ForEach LITERAL, so a THIRD SessionStart hook added
        # tomorrow inherits NO matcher assertion at all - and a partial matcher is exactly the drift that
        # pair exists to catch. It has already happened once here: the two matchers diverged to
        # complementary subsets ('startup|clear|compact' and 'startup|resume') and the visible consequence
        # was the agy-LEARN reminder never firing on a RESUMED session. An enumerated list cannot see the
        # hook it was never told about.
        #
        # Both SIBLING rows in this file already sweep instead of enumerating - 'names only hook files that
        # EXIST' walks Get-AllCommands, and 'ships no hook file that is reachable from nowhere' walks the
        # directory. This row closes the asymmetry rather than adding a new mechanism.
        #
        # Deliberately NOT parameterised over dotnet/classic: those two register agy-liveness-check.sh on
        # 'startup' ALONE on purpose (see 'keeps agy-liveness-check.sh on startup ALONE' above), so a blanket
        # convention assertion is TRUE for agy-autotrain and FALSE for them. If agy-autotrain ever gains a
        # deliberate startup-only hook, this row must fail and be amended by hand - that is the intended
        # cost, not an oversight: a convention worth pinning is worth a deliberate edit to depart from.
        $json   = Get-Content -Raw -LiteralPath $script:Manifests['autotrain'] | ConvertFrom-Json
        $groups = @($json.hooks.SessionStart)

        # Non-vacuity guard. Without it, a manifest whose SessionStart array went missing or empty would
        # make the assertion below compare nothing to nothing and pass - the false-clean shape this repo
        # keeps paying for.
        $groups.Count | Should -BeGreaterThan 0 -Because 'an empty SessionStart array would make the assertion below vacuous'

        # Name the offenders, not a count: a count sends a reader hunting, a name sends them to the file.
        $bad = @(foreach ($g in $groups) {
            if ($g.matcher -ne 'startup|resume|clear|compact') {
                foreach ($h in @($g.hooks)) { "$($h.command) [matcher=$($g.matcher)]" }
            }
        })
        $bad -join ', ' | Should -BeExactly '' -Because 'every agy-autotrain SessionStart hook must pin all four sources; a subset silently drops a channel'
    }
}

# Rows, fixtures and payloads for hook-spawn-budget.Tests.ps1. Dot-sourced in BeforeDiscovery (for -ForEach)
# AND in BeforeAll (so the fixture functions exist when a row runs).

# OWNER RULING 2026-10-04: at most 16 processes per hook run, INCLUDING the 3 the prototype harness counted for
# bash boot. Measure-BashHookProcesses reports processes BEYOND boot, so the same budget is 13 here.
$script:HookCeiling = 13

# OWNER RULING 2026-10-04 (3): the consult guard's real-consult path is out of scope for Branch 20 (ROADMAP
# section 70). Pinned at the count measured after Task 3 (2026-10-06, Measure-BashHookProcesses, two runs
# identical) on a plain temp repo - no slack, because the count is deterministic: the path can no longer grow
# back the ~23 processes Branch 20 removed. Before Branch 20: pre 134 / 137 / 140, post 137 / 140 / 149.
$script:ConsultPin = @{ PreMcp = 111; PreAsk = 114; PreSend = 117; PostMcp = 114; PostAsk = 117; PostAwait = 126 }

# BRANCH 21 DEBT (owner ruling O3): census-measured paths of the eight hooks Branch 21 fixes, totals INCLUDING
# the 3 boot processes. The suite's debt row stays RED while this list is non-empty. Branch 21 removes each
# entry in the same commit that adds a passing budget row for that path.
$script:B21Debt = @(
    @{ Hook = 'agy-inbox-snapshot.sh';          Path = 'curate skill matched, 20 existing baks (snapshot + prune 16)'; Total = 67 }
    @{ Hook = 'agy-discipline-reaching.sh';     Path = 'shield .gitignore carries a ! negation';                    Total = 36 }
    @{ Hook = 'agy-anomaly-reminder.sh';        Path = 'one untriaged entry';                                       Total = 23 }
    @{ Hook = 'agy-verify-reminder.sh';         Path = 'agy on PATH, assertion rows stale';                         Total = 24 }
    @{ Hook = 'docs-audit-reminder.sh';         Path = 'generated findings view with open findings';                Total = 22 }
    @{ Hook = 'assertion-strength-reminder.sh'; Path = 'TMPDIR unusable, HOME/.clavity-tmp fallback';               Total = 21 }
    @{ Hook = 'fetch-clavity-ls.sh';            Path = 'binary installed, stamp matches (steady state)';            Total = 17 }
    @{ Hook = 'migrate-inbox.sh';               Path = 'recover an interrupted migration';                          Total = 17 }
)

function New-HookFixture {
    # A throwaway repo, home and TMPDIR. -NoGit: the repo dir is a plain folder. -NoClavity: no .clavity/
    # (the plugin's opt-in). The Env hashtable is what every row hands the hook: it pins every variable a hook
    # reads from the environment, so nothing leaks in from the session running the tests.
    param([switch]$NoGit, [switch]$NoClavity)
    $root = Join-Path ([IO.Path]::GetTempPath()) ('hsb-' + [Guid]::NewGuid().ToString('N'))
    $repo = Join-Path $root 'repo'; $homeDir = Join-Path $root 'home'; $tmp = Join-Path $root 'tmp'
    New-Item -ItemType Directory -Force -Path $repo, (Join-Path $homeDir '.claude'), (Join-Path $homeDir '.clavity'), $tmp | Out-Null
    $fx = [pscustomobject]@{
        Root = $root; Repo = $repo; Home = $homeDir; Tmp = $tmp; RepoFwd = ($repo -replace '\\', '/')
        Env = @{
            HOME = ($homeDir -replace '\\', '/'); USERPROFILE = $homeDir; TMPDIR = ($tmp -replace '\\', '/')
            # agy-liveness-check.sh reads USER-scope settings from CLAUDE_CONFIG_DIR, not only from HOME.
            CLAUDE_CONFIG_DIR = (Join-Path $homeDir '.claude')
            CLAUDE_PROJECT_DIR = $repo; CLAUDE_PLUGIN_DATA = ''; CLAUDE_PLUGIN_ROOT = ''
            LOCALAPPDATA = $tmp
            # EVERY other variable a hook reads from its environment (census 2026-10-05: an rg of `${UPPER` over
            # the 4 hook dirs, minus the names the scripts set themselves). $null REMOVES it for the child, so a
            # value set in the session running the tests cannot leak in. CLAVITY_GOLDEN_HEADER is the dangerous
            # one: agy-drive-session-reset.sh deletes flag files under it.
            AGY_SESSION_ID = $null; CLAVITY_SESSION = $null; AGY_SESSION = $null
            CLAVITY_GOLDEN_HEADER = $null; CLAVITY_AUDIT_BASE_REF = $null; AGY_GUARD_TTL_MIN = $null
            AGY_CURATE_NUDGE_THRESHOLD = $null; AGY_CURATE_NUDGE_MAX_AGE_DAYS = $null; AGY_INBOX_SNAPSHOT_KEEP = $null
        }
    }
    if (-not $NoGit) {
        & git -C $repo init -q -b main
        Invoke-FxGit $fx commit --allow-empty -qm init
    }
    if (-not $NoClavity) {
        New-Item -ItemType Directory -Force -Path (Join-Path $repo '.clavity\seams'), (Join-Path $repo '.clavity\agy-marks') | Out-Null
        Set-Content -LiteralPath (Join-Path $repo '.clavity\.gitignore') -Value '*'
    }
    $fx
}
function Invoke-FxGit {
    param($Fx, [Parameter(ValueFromRemainingArguments)][string[]]$Rest)
    & git -C $Fx.Repo -c user.email=t@t -c user.name=t -c commit.gpgsign=false -c core.hooksPath= @Rest
}
function Add-FxCommit {
    param($Fx, [string]$Rel, [string]$Text = 'x')
    $p = Join-Path $Fx.Repo $Rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null
    Set-Content -LiteralPath $p -Value $Text
    Invoke-FxGit $Fx add -- $Rel
    Invoke-FxGit $Fx commit -qm "add $Rel"
    (Invoke-FxGit $Fx rev-parse HEAD).Trim()
}
function Set-FxMarker {
    param($Fx, [string]$Name, [string]$Sha)
    Set-Content -LiteralPath (Join-Path $Fx.Repo ".clavity\agy-marks\$Name.head") -Value $Sha -NoNewline
}
function Add-FxSeams {
    param($Fx, [string[]]$Names, [datetime]$When = (Get-Date).AddHours(-1))
    $dir = Join-Path $Fx.Repo '.clavity\seams'
    foreach ($n in $Names) {
        $f = Join-Path $dir $n
        [IO.File]::WriteAllText($f, 'body')
        [IO.File]::SetLastWriteTime($f, $When)
    }
}
function ConvertTo-HookPayload { param([hashtable]$H) $H | ConvertTo-Json -Compress -Depth 6 }
function New-ToolPayload {
    param($Fx, [string]$Tool, [hashtable]$ToolInput, [switch]$NoGit)
    ConvertTo-HookPayload @{ cwd = $Fx.RepoFwd; session_id = 's1'; tool_name = $Tool; tool_input = $ToolInput }
}
function New-BashPayload { param($Fx, [string]$Command) New-ToolPayload $Fx 'Bash' @{ command = $Command } }
function New-SessionStartPayload { param($Fx) ConvertTo-HookPayload @{ cwd = $Fx.RepoFwd; session_id = 's1'; hook_event_name = 'SessionStart'; source = 'startup' } }

function New-BudgetRow {
    param(
        [Parameter(Mandatory)][string]$Hook, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][scriptblock]$Setup,
        [hashtable]$Fixture = @{}, [string[]]$HookArgs = @(), [int]$Max = $script:HookCeiling,
        [string]$Expect = '', [switch]$Silent, [scriptblock]$Verify = $null
    )
    # -Verify: an EFFECT check run after the hook, for a path whose output is silent - a silent row alone
    # cannot tell "did its work" from "exited early" (agy panel R1).
    @{ Hook = $Hook; Name = $Name; Setup = $Setup; Fixture = $Fixture; HookArgs = $HookArgs; Max = $Max; Expect = $Expect; Silent = [bool]$Silent; Verify = $Verify }
}

$D = 'clavity-dotnet/plugin/hooks'; $C = 'clavity-classic/plugin/hooks'; $A = 'agy-autotrain/hooks'; $L = '.claude/hooks'
$mcp = 'mcp__plugin_clavity_clavity-ls__agy_ask'

$script:Rows = @(
    # --- agy-consult-guard-pre.sh (runs on EVERY Bash / PowerShell / agy_ask call) ---
    New-BudgetRow "$D/agy-consult-guard-pre.sh" 'non-consult Bash call' { param($fx) New-BashPayload $fx 'ls' } -Silent
    New-BudgetRow "$D/agy-consult-guard-pre.sh" 'command text mentions the consult CLI' { param($fx) New-BashPayload $fx 'git commit -m "note: clavity ask later"' } -Silent
    New-BudgetRow "$D/agy-consult-guard-pre.sh" 'clavity await-reply (pre is a no-op)' { param($fx) New-BashPayload $fx 'clavity await-reply' } -Silent
    New-BudgetRow "$D/agy-consult-guard-pre.sh" 'consult outside a git repo' { param($fx) New-BashPayload $fx 'clavity ask "x" --review-only' } -Fixture @{ NoGit = $true; NoClavity = $true } -Silent
    New-BudgetRow "$D/agy-consult-guard-pre.sh" 'PINNED consult: MCP agy_ask' { param($fx) New-ToolPayload $fx $mcp @{ prompt = 'x' } } -Fixture @{ NoClavity = $true } -Max $script:ConsultPin.PreMcp -Silent
    New-BudgetRow "$D/agy-consult-guard-pre.sh" 'PINNED consult: clavity ask' { param($fx) New-BashPayload $fx 'clavity ask "x" --review-only' } -Fixture @{ NoClavity = $true } -Max $script:ConsultPin.PreAsk -Silent
    New-BudgetRow "$D/agy-consult-guard-pre.sh" 'PINNED consult: clavity send' { param($fx) New-BashPayload $fx 'clavity send "x"' } -Fixture @{ NoClavity = $true } -Max $script:ConsultPin.PreSend -Silent

    # --- agy-consult-guard-post.sh ---
    New-BudgetRow "$D/agy-consult-guard-post.sh" 'non-consult Bash call' { param($fx) New-BashPayload $fx 'ls' } -Silent
    New-BudgetRow "$D/agy-consult-guard-post.sh" 'command text mentions the consult CLI' { param($fx) New-BashPayload $fx 'git commit -m "note: clavity ask later"' } -Silent
    New-BudgetRow "$D/agy-consult-guard-post.sh" 'clavity send (post is a no-op)' { param($fx) New-BashPayload $fx 'clavity send "x"' } -Silent
    New-BudgetRow "$D/agy-consult-guard-post.sh" 'consult outside a git repo' { param($fx) New-BashPayload $fx 'clavity ask "x" --review-only' } -Fixture @{ NoGit = $true; NoClavity = $true } -Silent
    New-BudgetRow "$D/agy-consult-guard-post.sh" 'PINNED consult: MCP agy_ask (after its pre)' {
        param($fx)
        $p = New-ToolPayload $fx $mcp @{ prompt = 'x' }
        $null = Invoke-BashHook -HookPath (Join-Path $script:RepoRoot "$D/agy-consult-guard-pre.sh") -Payload $p -Env $fx.Env
        $p
    } -Fixture @{ NoClavity = $true } -Max $script:ConsultPin.PostMcp -Silent
    New-BudgetRow "$D/agy-consult-guard-post.sh" 'PINNED consult: clavity ask (after its pre)' {
        param($fx)
        $p = New-BashPayload $fx 'clavity ask "x" --review-only'
        $null = Invoke-BashHook -HookPath (Join-Path $script:RepoRoot "$D/agy-consult-guard-pre.sh") -Payload $p -Env $fx.Env
        $p
    } -Fixture @{ NoClavity = $true } -Max $script:ConsultPin.PostAsk -Silent
    New-BudgetRow "$D/agy-consult-guard-post.sh" 'PINNED consult: clavity await-reply (after a send)' {
        param($fx)
        $null = Invoke-BashHook -HookPath (Join-Path $script:RepoRoot "$D/agy-consult-guard-pre.sh") -Payload (New-BashPayload $fx 'clavity send "x"') -Env $fx.Env
        New-BashPayload $fx 'clavity await-reply'
    } -Fixture @{ NoClavity = $true } -Max $script:ConsultPin.PostAwait -Silent

    # --- agy-consult-recovery.sh (SessionStart) ---
    New-BudgetRow "$D/agy-consult-recovery.sh" 'one open seam' { param($fx) Add-FxSeams $fx 'agy-capstone-r1-x.md'; New-SessionStartPayload $fx } -Expect 'workflow position:'
    New-BudgetRow "$D/agy-consult-recovery.sh" '1000 mixed seams' {
        param($fx)
        Add-FxSeams $fx (1..1000 | ForEach-Object { if ($_ % 2) { "agy-capstone-r$_-x.md" } else { "loose-$_.md" } })
        New-SessionStartPayload $fx
    } -Expect 'workflow position:'
    New-BudgetRow "$D/agy-consult-recovery.sh" '1000 seams, all concluded' {
        param($fx)
        Add-FxSeams $fx (1..1000 | ForEach-Object { "agy-capstone-r$_-x.md" }) -When (Get-Date).AddHours(-2)
        Set-FxMarker $fx 'agy-capstone' (Invoke-FxGit $fx rev-parse HEAD).Trim()
        New-SessionStartPayload $fx
    } -Silent

    # --- agy-test-audit-reminder.sh (PostToolUse: EVERY Bash / PowerShell / Write / Edit) ---
    New-BudgetRow "$D/agy-test-audit-reminder.sh" 'no .clavity (not opted in)' { param($fx) New-BashPayload $fx 'ls' } -Fixture @{ NoClavity = $true } -Silent
    New-BudgetRow "$D/agy-test-audit-reminder.sh" 'fires: capstone marker at HEAD, code vs main' {
        param($fx)
        Invoke-FxGit $fx checkout -q -b feat
        Set-FxMarker $fx 'agy-capstone' (Add-FxCommit $fx 'src/a.cs')
        New-BashPayload $fx 'ls'
    } -Expect 'AGY-TEST-AUDIT auto-fire'
    New-BudgetRow "$D/agy-test-audit-reminder.sh" 'fires: worst path, both markers behind HEAD' {
        param($fx)
        Invoke-FxGit $fx checkout -q -b feat
        Set-FxMarker $fx 'agy-test-audit' (Add-FxCommit $fx 'src/a.cs')
        Set-FxMarker $fx 'agy-capstone' (Add-FxCommit $fx 'src/b.cs')
        $null = Add-FxCommit $fx 'README.md' 'docs only'
        New-BashPayload $fx 'ls'
    } -Expect 'AGY-TEST-AUDIT auto-fire'
    New-BudgetRow "$D/agy-test-audit-reminder.sh" 'debounced: second call at the same HEAD' {
        param($fx)
        Invoke-FxGit $fx checkout -q -b feat
        Set-FxMarker $fx 'agy-capstone' (Add-FxCommit $fx 'src/a.cs')
        $p = New-BashPayload $fx 'ls'
        $null = Invoke-BashHook -HookPath (Join-Path $script:RepoRoot "$D/agy-test-audit-reminder.sh") -Payload $p -Env $fx.Env
        $p
    } -Silent -Verify {
        param($fx)
        $f = Join-Path $fx.Tmp 'claude-agy-test-audit-reminder.s1'
        Test-Path -LiteralPath $f | Should -BeTrue -Because 'a silent second call proves the debounce only if the first call fired and recorded its HEAD (capstone R1, MG1)'
        (Get-Content -Raw -LiteralPath $f).Trim() | Should -BeExactly (Invoke-FxGit $fx rev-parse HEAD).Trim()
    }
    # The four paths the prototype never measured (agy panel R2) - rename and merge in the reviewed range, and the
    # no-jq arm (PATH = <Git>\usr\bin only, the convention of agy-test-audit-reminder.Tests.ps1 line 8).
    New-BudgetRow "$D/agy-test-audit-reminder.sh" 'fires: a code file RENAMED since main' {
        param($fx)
        Invoke-FxGit $fx checkout -q -b feat
        $null = Add-FxCommit $fx 'src/a.cs'
        Invoke-FxGit $fx mv src/a.cs src/b.cs
        Invoke-FxGit $fx commit -qm rename
        Set-FxMarker $fx 'agy-capstone' (Invoke-FxGit $fx rev-parse HEAD).Trim()
        New-BashPayload $fx 'ls'
    } -Expect 'AGY-TEST-AUDIT auto-fire'
    New-BudgetRow "$D/agy-test-audit-reminder.sh" 'fires: a MERGE commit in the reviewed range' {
        param($fx)
        Invoke-FxGit $fx checkout -q -b feat
        $null = Add-FxCommit $fx 'src/a.cs'
        Invoke-FxGit $fx checkout -q -b side
        $null = Add-FxCommit $fx 'src/b.cs'
        Invoke-FxGit $fx checkout -q feat
        Invoke-FxGit $fx merge -q --no-ff -m merge side
        Set-FxMarker $fx 'agy-capstone' (Invoke-FxGit $fx rev-parse HEAD).Trim()
        New-BashPayload $fx 'ls'
    } -Expect 'AGY-TEST-AUDIT auto-fire'
    New-BudgetRow "$D/agy-test-audit-reminder.sh" 'no jq: fires on the ledger shape (marker behind HEAD, docs since)' {
        param($fx)
        $fx.Env.PATH = Join-Path (Split-Path -Parent (Split-Path -Parent (Get-GitBashOrThrow))) 'usr\bin'
        Invoke-FxGit $fx checkout -q -b feat
        Set-FxMarker $fx 'agy-capstone' (Add-FxCommit $fx 'src/a.cs')
        $null = Add-FxCommit $fx 'README.md' 'docs only'
        New-BashPayload $fx 'ls'
    } -Expect 'guard inactive: missing jq'
    New-BudgetRow "$D/agy-test-audit-reminder.sh" 'no jq: debounced second call' {
        param($fx)
        $fx.Env.PATH = Join-Path (Split-Path -Parent (Split-Path -Parent (Get-GitBashOrThrow))) 'usr\bin'
        Invoke-FxGit $fx checkout -q -b feat
        Set-FxMarker $fx 'agy-capstone' (Add-FxCommit $fx 'src/a.cs')
        $null = Add-FxCommit $fx 'README.md' 'docs only'
        $p = New-BashPayload $fx 'ls'
        $null = Invoke-BashHook -HookPath (Join-Path $script:RepoRoot "$D/agy-test-audit-reminder.sh") -Payload $p -Env $fx.Env
        $p
    } -Silent -Verify {
        param($fx)
        $f = Join-Path $fx.Tmp 'claude-agy-test-audit-reminder.s1'
        Test-Path -LiteralPath $f | Should -BeTrue -Because 'a silent second call proves the debounce only if the first call fired and recorded its HEAD (capstone R1, MG1)'
        (Get-Content -Raw -LiteralPath $f).Trim() | Should -BeExactly (Invoke-FxGit $fx rev-parse HEAD).Trim()
    }

    # --- agy-after-reminder.sh (PostToolUse Write|Edit) ---
    New-BudgetRow "$D/agy-after-reminder.sh" 'non-plan Edit' { param($fx) New-ToolPayload $fx 'Edit' @{ file_path = "$($fx.RepoFwd)/src/a.cs" } } -Silent
    New-BudgetRow "$D/agy-after-reminder.sh" 'plan Edit' {
        param($fx)
        $rel = 'docs/superpowers/plans/2026-01-01-x.md'
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $fx.Repo 'docs\superpowers\plans')
        Set-Content -LiteralPath (Join-Path $fx.Repo $rel) -Value '# plan'
        New-ToolPayload $fx 'Edit' @{ file_path = "$($fx.RepoFwd)/$rel" }
    } -Expect 'AGY-AFTER'

    # --- agy-seam-inject.sh (PreToolUse Skill) ---
    New-BudgetRow "$D/agy-seam-inject.sh" 'seam skill, no marker' { param($fx) New-ToolPayload $fx 'Skill' @{ skill = 'superpowers:brainstorming' } } -Expect 'AGY-FIRST auto-fire'
    New-BudgetRow "$D/agy-seam-inject.sh" 'seam skill, marker behind HEAD with code since' {
        param($fx)
        Set-FxMarker $fx 'agy-first' (Add-FxCommit $fx 'src/a.cs')
        $null = Add-FxCommit $fx 'src/b.cs'
        New-ToolPayload $fx 'Skill' @{ skill = 'superpowers:brainstorming' }
    } -Expect 'AGY-FIRST auto-fire'
    New-BudgetRow "$D/agy-seam-inject.sh" 'non-seam skill' { param($fx) New-ToolPayload $fx 'Skill' @{ skill = 'dataviz' } } -Silent
    New-BudgetRow "$D/agy-seam-inject.sh" 'skill value containing a newline' { param($fx) New-ToolPayload $fx 'Skill' @{ skill = "superpowers:brainstorming`nx" } } -Expect 'AGY-FIRST auto-fire'

    # --- agy-liveness-check.sh (SessionStart startup) ---
    New-BudgetRow "$D/agy-liveness-check.sh" 'no settings files' { param($fx) New-SessionStartPayload $fx } -Expect 'superpowers not detected as enabled'
    New-BudgetRow "$D/agy-liveness-check.sh" 'three settings files, one a personal duplicate (warns)' {
        param($fx)
        # A personal registration of a plugin hook is the state this hook warns about (its suite row 'reports the
        # unreadable settings file BUT continues the sweep' uses the same command), so the row can ASSERT that the
        # full sweep ran instead of passing on an early exit.
        $s = '{"enabledPlugins":{"superpowers@superpowers-marketplace":true},"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash \"~/.claude/hooks/agy-liveness-check.sh\""}]}]}}'
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $fx.Repo '.claude')
        Set-Content -LiteralPath (Join-Path $fx.Home '.claude\settings.json') -Value $s
        Set-Content -LiteralPath (Join-Path $fx.Repo '.claude\settings.json') -Value $s
        Set-Content -LiteralPath (Join-Path $fx.Repo '.claude\settings.local.json') -Value $s
        New-SessionStartPayload $fx
    } -Expect 'agy-liveness-check'

    # --- agy-drive-session-reset.sh (classic only; DELETES flags under ~/.clavity) ---
    New-BudgetRow "$C/agy-drive-session-reset.sh" 'startup: own flag + 5 stale + 2 fresh' {
        param($fx)
        $dir = Join-Path $fx.Home '.clavity'
        Set-Content -LiteralPath (Join-Path $dir '.active-drive-session-default') -Value '' -NoNewline
        foreach ($i in 1..5) { $f = Join-Path $dir ".active-drive-session-stale$i"; Set-Content -LiteralPath $f -Value '' -NoNewline; [IO.File]::SetLastWriteTime($f, (Get-Date).AddDays(-10)) }
        foreach ($i in 1..2) { Set-Content -LiteralPath (Join-Path $dir ".active-drive-session-fresh$i") -Value '' -NoNewline }
        New-SessionStartPayload $fx
    } -Silent -Verify {
        param($fx)
        $left = @(Get-ChildItem -LiteralPath (Join-Path $fx.Home '.clavity') -Force -Filter '.active-drive-session-*' | ForEach-Object Name) | Sort-Object
        ($left -join ',') | Should -BeExactly '.active-drive-session-fresh1,.active-drive-session-fresh2' -Because 'the reset must clear its own flag and the 5 stale ones and keep the 2 fresh - or the row measured an early exit'
    }

    # --- agy-curate-nudge.sh (agy-autotrain, SessionStart) ---
    New-BudgetRow "$A/agy-curate-nudge.sh" 'inbox missing' { param($fx) New-SessionStartPayload $fx } -Silent
    New-BudgetRow "$A/agy-curate-nudge.sh" 'worst: snooze expired + 16 recent entries' {
        param($fx)
        $today = (Get-Date).ToString('yyyy-MM-dd'); $dot = [char]0x00B7
        $bullets = (1..16 | ForEach-Object { "- [heuristic] (driver/probabilistic) rule $_  $dot  ``[corpus]`` $dot $today $dot agy 1.0.0" }) -join "`n"
        [IO.File]::WriteAllText((Join-Path $fx.Home '.clavity\agy-observations.md'), "# agy observations inbox`n`n## Pending`n`n$bullets`n", [Text.UTF8Encoding]::new($false))
        $s = Join-Path $fx.Home '.clavity\.agy-curate-snooze'; Set-Content -LiteralPath $s -Value '' -NoNewline; [IO.File]::SetLastWriteTime($s, (Get-Date).AddDays(-8))
        New-SessionStartPayload $fx
    } -Expect 'agy-curate is OVERDUE'   # 16 >= 2 x threshold 8 takes the OVERDUE message (agy-curate-nudge.sh:80), not the nudge

    # --- every other registered hook: its default path (Branch 21 adds the worst paths) ---
    New-BudgetRow "$D/agy-anomaly-dispatch-reminder.sh" 'Agent dispatch' { param($fx) New-ToolPayload $fx 'Agent' @{ prompt = 'x' } } -Expect 'AGY-ANOMALIES/1 relay'
    New-BudgetRow "$D/assertion-strength-reminder.sh" 'non-test Edit' { param($fx) New-ToolPayload $fx 'Edit' @{ file_path = "$($fx.RepoFwd)/src/a.cs" } } -Silent
    New-BudgetRow "$D/agy-anomaly-reminder.sh" 'startup, nothing captured' { param($fx) New-SessionStartPayload $fx } -Silent
    New-BudgetRow "$D/agy-anomaly-model-notice.sh" 'startup' { param($fx) New-SessionStartPayload $fx } -Silent
    New-BudgetRow "$D/agy-discipline-reaching.sh" 'startup, shield intact' { param($fx) New-SessionStartPayload $fx } -Silent
    New-BudgetRow "$D/agy-anomaly-capture-reminder.sh" 'PreCompact' { param($fx) ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'PreCompact'; trigger = 'manual' } } -Expect 'AGY-ANOMALIES/1 check BEFORE COMPACTION'
    New-BudgetRow "$D/agy-anomaly-capture-reminder.sh" 'PreCompact re-arming a test-audit debounce' {
        param($fx)
        Set-Content -LiteralPath (Join-Path $fx.Tmp 'claude-agy-test-audit-reminder.s1') -Value 'deadbeef'
        ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'PreCompact'; trigger = 'manual' }
    } -Expect 'AGY-ANOMALIES/1 check BEFORE COMPACTION'
    New-BudgetRow "$D/agy-anomaly-capture-reminder.sh" 'UserPromptSubmit' { param($fx) ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'UserPromptSubmit'; prompt = 'hi' } } -HookArgs @('UserPromptSubmit') -Silent
    New-BudgetRow "$D/fetch-clavity-ls.sh" 'not a plugin context' { param($fx) New-SessionStartPayload $fx } -Silent
    New-BudgetRow "$D/clavity-dotnet-setup.sh" 'not a plugin context' { param($fx) New-SessionStartPayload $fx } -Silent
    New-BudgetRow "$A/agy-inbox-snapshot.sh" 'non-curate skill' { param($fx) New-ToolPayload $fx 'Skill' @{ skill = 'dataviz' } } -Silent
    New-BudgetRow "$A/agy-inbox-snapshot.sh" 'UserPromptSubmit, ordinary prompt' { param($fx) ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'UserPromptSubmit'; prompt = 'hi' } } -Silent
    New-BudgetRow "$A/migrate-inbox.sh" 'nothing to migrate' { param($fx) New-SessionStartPayload $fx } -Silent
    New-BudgetRow "$A/agy-learn-reminder.sh" 'SessionStart' { param($fx) New-SessionStartPayload $fx } -HookArgs @('SessionStart') -Expect 'agy-autotrain is active'
    New-BudgetRow "$A/agy-learn-reminder.sh" 'PreCompact' { param($fx) ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'PreCompact'; trigger = 'manual' } } -HookArgs @('PreCompact') -Expect 'agy-LEARN check BEFORE COMPACTION'
    New-BudgetRow "$L/agy-verify-reminder.sh" 'not the clavity repo' { param($fx) New-SessionStartPayload $fx } -Silent
    New-BudgetRow "$L/docs-audit-reminder.sh" 'no findings view' { param($fx) New-SessionStartPayload $fx } -Silent
)

# Narrow to ONE hook for a task's red/green runs: set HSB_HOOK to the hook's file name and run with
# -TagFilter row. MEASURED 2026-10-04: Invoke-Pester -FullNameFilter does NOT see the expanded '<Hook>' row
# names (a filter on the hook name ran 0 tests), so the narrowing happens here, at discovery.
if ($env:HSB_HOOK) {
    $script:Rows = @($script:Rows | Where-Object { (Split-Path -Leaf $_.Hook) -eq $env:HSB_HOOK })
    # A mistyped name selects nothing, and a 0-test run exits 0 under -CI (agy panel R3): fail discovery instead.
    if ($script:Rows.Count -eq 0) { throw "HSB_HOOK='$($env:HSB_HOOK)' matches no budget row - check the hook file name" }
}

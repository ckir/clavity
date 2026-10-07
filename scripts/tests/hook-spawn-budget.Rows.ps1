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

function Add-FxInbox {
    # The canonical inbox lives in the FIXTURE home (${USERPROFILE:-$HOME} -> $fx.Home), never the real one.
    param($Fx, [int]$Baks = 0, [switch]$EmptyPending)
    $d = Join-Path $Fx.Home '.clavity'; New-Item -ItemType Directory -Force -Path $d | Out-Null
    $obs = Join-Path $d 'agy-observations.md'
    $body = "# agy observations inbox (raw, project-agnostic)`n`nprose`n`n## Pending`n`n"
    if (-not $EmptyPending) { $body += "- [heuristic] (driver/probabilistic) a rule * ``[corpus]`` * 2026-10-01 * agy 1.3.1`n" }
    [IO.File]::WriteAllText($obs, $body)
    for ($i = 1; $i -le $Baks; $i++) {
        $p = '{0}.202601{1:d2}-000000.bak' -f $obs, $i
        [IO.File]::WriteAllText($p, "old $i")
        # Distinct ascending mtimes: index 1 is the OLDEST. Ordering is mtime (fork 1C), not name.
        [IO.File]::SetLastWriteTimeUtc($p, [datetime]::UtcNow.AddMinutes($i - $Baks - 5))
    }
    $obs
}
function Get-FxBaks { param($Fx) @(Get-ChildItem -LiteralPath (Join-Path $Fx.Home '.clavity') -Filter 'agy-observations.md.*.bak' -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object Name) }

function Set-FxShield {
    # $Text = $null -> .clavity exists with NO .gitignore; otherwise the shield holds exactly $Text.
    # New-HookFixture ALREADY writes .clavity/.gitignore = '*' (panel R1, measured): the $null case must
    # DELETE it, or the "shield MISSING" row silently measures the healthy path instead.
    param($Fx, $Text)
    $d = Join-Path $Fx.Repo '.clavity'; New-Item -ItemType Directory -Force -Path $d | Out-Null
    $g = Join-Path $d '.gitignore'
    if ($null -eq $Text) { Remove-Item -LiteralPath $g -Force -ErrorAction SilentlyContinue }
    else { [IO.File]::WriteAllText($g, $Text) }
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
    # --- assertion-strength-reminder.sh: the Branch 21 census paths ---
    # PINNED AT THE MEASURED COUNTS (2026-10-07, two runs identical), not at the shared ceiling of 13: the hook is the
    # hottest one this plugin has (every test-file write), and at 13 a reintroduced `cat`, `grep` or second `jq`
    # would still be green. Before Branch 21: first touch 14, TMPDIR-unusable 18, non-test 10.
    New-BudgetRow "$D/assertion-strength-reminder.sh" 'test file, FIRST touch of the session -> marker + prune + emit' {
        param($fx) New-ToolPayload $fx 'Write' @{ file_path = ($fx.RepoFwd + '/scripts/tests/x.Tests.ps1'); content = 'x' } } -Max 7 -Expect 'ASSERTION-STRENGTH'
    New-BudgetRow "$D/assertion-strength-reminder.sh" 'TMPDIR unusable -> HOME/.clavity-tmp fallback still emits' {
        param($fx)
        [IO.File]::WriteAllText((Join-Path $fx.Root 'blockfile'), 'x')
        $fx.Env.TMPDIR = (($fx.Root -replace '\\', '/') + '/blockfile/sub')   # parent is a FILE: unusable
        New-ToolPayload $fx 'Write' @{ file_path = ($fx.RepoFwd + '/scripts/tests/x.Tests.ps1'); content = 'x' } } -Max 11 -Expect 'ASSERTION-STRENGTH'
    New-BudgetRow "$D/assertion-strength-reminder.sh" 'non-test file (the hottest path, silent)' {
        param($fx) New-ToolPayload $fx 'Write' @{ file_path = ($fx.RepoFwd + '/src/a.cs'); content = 'x' } } -Max 3 -Silent
    New-BudgetRow "$D/agy-anomaly-reminder.sh" 'startup, nothing captured' { param($fx) New-SessionStartPayload $fx } -Silent
    # --- agy-anomaly-reminder.sh: the Branch 21 census paths (the hook EMITS, so -Expect works under the PP1 JSON check) ---
    # TIGHT ON PURPOSE (Max 2 = the one jq that builds the envelope): every other step is a builtin, and at the shared
    # ceiling of 13 a reintroduced grep or awk would still pass. Measured 2 on 2026-10-07 (it was 20 before Branch 21).
    New-BudgetRow "$D/agy-anomaly-reminder.sh" '3 untriaged with dates -> EMIT the oldest' -Max 2 {
        param($fx)
        $d = Join-Path $fx.Repo '.clavity'; New-Item -ItemType Directory -Force -Path $d | Out-Null
        @('# Untriaged anomalies (local, never committed)', '',
          '- [defect] a * src/a.rs:1 * 2026-09-01 * task=x',
          '- [tool] b * n/a * 2026-08-15 * task=y',
          '- [process] c * n/a * 2026-09-20 * task=z') | Set-Content -LiteralPath (Join-Path $d 'local-anomalies.md')
        New-SessionStartPayload $fx } -Expect '3 untriaged (oldest 2026-08-15)'
    New-BudgetRow "$D/agy-anomaly-reminder.sh" '50 untriaged (scaling: the count loop is builtin)' -Max 2 {
        param($fx)
        $d = Join-Path $fx.Repo '.clavity'; New-Item -ItemType Directory -Force -Path $d | Out-Null
        $lines = @('# Untriaged anomalies (local, never committed)', '') + (1..50 | ForEach-Object { "- [defect] n$_ * n/a * 2026-09-0$(1 + ($_ % 8)) * task=t" })
        $lines | Set-Content -LiteralPath (Join-Path $d 'local-anomalies.md')
        New-SessionStartPayload $fx } -Expect '50 untriaged'
    New-BudgetRow "$D/agy-anomaly-model-notice.sh" 'startup' { param($fx) New-SessionStartPayload $fx } -Silent
    New-BudgetRow "$D/agy-discipline-reaching.sh" 'startup, shield intact' { param($fx) New-SessionStartPayload $fx } -Silent
    # --- agy-discipline-reaching.sh + the shared agy-shield-lib.sh: the Branch 21 census paths ---
    # TIGHT ON PURPOSE (Max 2 = the single check-ignore): the two glob gates are what keep the sweep find and the
    # say-prune find from running on a healthy repository, and each find costs 2 - at the shared ceiling of 13 an
    # ungated find would still pass, so a regression to ungated finds is invisible. Measured 2 on 2026-10-07.
    New-BudgetRow "$D/agy-discipline-reaching.sh" 'normal FIRST session (shield ok, sweep latch, row written)' -Max 2 {
        param($fx) Set-FxShield $fx "*`n"; New-SessionStartPayload $fx } -Silent -Verify {
        param($fx) (Join-Path $fx.Repo '.clavity/discipline-reaching.jsonl') | Should -Exist }
    New-BudgetRow "$D/agy-discipline-reaching.sh" 'shield file MISSING -> created with *' {
        param($fx) Set-FxShield $fx $null; New-SessionStartPayload $fx } -Silent -Verify {
        param($fx) (Get-Content -LiteralPath (Join-Path $fx.Repo '.clavity/.gitignore') -Raw) | Should -Match '\*' }
    New-BudgetRow "$D/agy-discipline-reaching.sh" 'shield lacks * -> appended' {
        param($fx) Set-FxShield $fx "foo.txt`n"; New-SessionStartPayload $fx } -Silent -Verify {
        param($fx) @(Get-Content -LiteralPath (Join-Path $fx.Repo '.clavity/.gitignore')) -contains '*' | Should -BeTrue }
    # THE ONE NAMED EXEMPTION of Branch 21 (owner ruling 2026-10-07, agreed with agy): the first run that meets a
    # `!` negation PREPENDS `*` (mktemp + cat + mv, section 41, deliberately untouched) and measures 14 beyond boot,
    # one over the 13 allowed. It happens once per shield file per repository; every later run takes the recurring
    # path below (7 or 9). The plan predicted 12 - its arithmetic was wrong. Max is 14 EXACTLY: a regression on
    # this path fails here, it is not hidden by the exemption.
    New-BudgetRow "$D/agy-discipline-reaching.sh" 'shield has a ! negation -> PREPEND, first session (one-time exemption, Max 14)' -Max 14 {
        param($fx) Set-FxShield $fx "!discipline-reaching.jsonl`n"; New-SessionStartPayload $fx } -Silent -Verify {
        param($fx) $s = @(Get-Content -LiteralPath (Join-Path $fx.Repo '.clavity/.gitignore'))
        $s[0] | Should -BeExactly '*'; $s[1] | Should -BeExactly '!discipline-reaching.jsonl' }
    New-BudgetRow "$D/agy-discipline-reaching.sh" 'shield already * + ! negation, REPEAT session (swept marker present)' {
        param($fx) Set-FxShield $fx "*`n!discipline-reaching.jsonl`n"
        New-Item -ItemType File -Path (Join-Path $fx.Repo '.clavity/.clavity-shield-swept-s1') | Out-Null
        New-SessionStartPayload $fx } -Silent -Verify {
        param($fx) (Get-Content -LiteralPath (Join-Path $fx.Repo '.clavity/.gitignore'))[0] | Should -BeExactly '*' }
    # Max 4 = check-ignore + ls-files; tight for the same reason (the say-prune find must stay gated). Measured 4.
    New-BudgetRow "$D/agy-discipline-reaching.sh" 'jsonl TRACKED by git -> persistent message, marker written' -Max 4 {
        param($fx) Set-FxShield $fx "*`n"
        [IO.File]::WriteAllText((Join-Path $fx.Repo '.clavity/discipline-reaching.jsonl'), "{}`n")
        Invoke-FxGit $fx add --force .clavity/discipline-reaching.jsonl   # NOT -f: PowerShell binds it to -Fx
        New-SessionStartPayload $fx } -Silent -Verify {
        param($fx) (Join-Path $fx.Repo '.clavity/.clavity-shield-persistent-s1') | Should -Exist }
    # LONG-LIVED REPO variants (panel R1): a real repository carries OTHER sessions' markers, so the glob
    # gates PASS and both finds run - the cheapest-fixture rows above cannot see that cost.
    New-BudgetRow "$D/agy-discipline-reaching.sh" 'long-lived repo: the FIRST-prepend run with old markers present (one-time exemption, Max 14)' -Max 14 {
        param($fx) Set-FxShield $fx "!discipline-reaching.jsonl`n"
        foreach ($k in 'old1', 'old2') { New-Item -ItemType File -Path (Join-Path $fx.Repo ".clavity/.clavity-shield-swept-$k") | Out-Null }
        New-SessionStartPayload $fx } -Silent -Verify {
        param($fx) (Get-Content -LiteralPath (Join-Path $fx.Repo '.clavity/.gitignore'))[0] | Should -BeExactly '*' }
    New-BudgetRow "$D/agy-discipline-reaching.sh" 'long-lived repo: a NEW session on the recurring ! negation path (old markers present)' {
        param($fx) Set-FxShield $fx "*`n!discipline-reaching.jsonl`n"
        foreach ($k in 'old1', 'old2') { New-Item -ItemType File -Path (Join-Path $fx.Repo ".clavity/.clavity-shield-swept-$k") | Out-Null }
        New-SessionStartPayload $fx } -Silent -Verify {
        param($fx) (Join-Path $fx.Repo '.clavity/.clavity-shield-swept-s1') | Should -Exist }
    New-BudgetRow "$D/agy-discipline-reaching.sh" 'long-lived repo: a NEW session, healthy shield (old markers present)' {
        param($fx) foreach ($k in 'old1', 'old2') { New-Item -ItemType File -Path (Join-Path $fx.Repo ".clavity/.clavity-shield-swept-$k") | Out-Null }
        New-SessionStartPayload $fx } -Silent -Verify {
        param($fx) (Join-Path $fx.Repo '.clavity/.clavity-shield-swept-s1') | Should -Exist }
    New-BudgetRow "$D/agy-anomaly-capture-reminder.sh" 'PreCompact' { param($fx) ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'PreCompact'; trigger = 'manual' } } -Expect 'AGY-ANOMALIES/1 check BEFORE COMPACTION'
    New-BudgetRow "$D/agy-anomaly-capture-reminder.sh" 'PreCompact re-arming a test-audit debounce' {
        param($fx)
        Set-Content -LiteralPath (Join-Path $fx.Tmp 'claude-agy-test-audit-reminder.s1') -Value 'deadbeef'
        ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'PreCompact'; trigger = 'manual' }
    } -Expect 'AGY-ANOMALIES/1 check BEFORE COMPACTION'
    New-BudgetRow "$D/agy-anomaly-capture-reminder.sh" 'UserPromptSubmit' { param($fx) ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'UserPromptSubmit'; prompt = 'hi' } } -HookArgs @('UserPromptSubmit') -Silent
    New-BudgetRow "$D/fetch-clavity-ls.sh" 'not a plugin context' { param($fx) New-SessionStartPayload $fx } -Silent
    # --- fetch-clavity-ls.sh: the Branch 21 census paths, PINNED at the measured counts (2026-10-07; before: steady state 14,
    # lookup fails 18, lookup empty 26). The plan called a steady-state row "existing"; only the
    # not-a-plugin-context row was (measured 2026-10-07), so all three are added here. The fake curl is a SHELL FUNCTION
    # in a BASH_ENV file, NOT an executable on PATH: the first draft dropped a copy of false.exe in a PREPENDED directory
    # and the lookup row came back 'no release asset named ...win-x64...' - Git Bash reorders PATH, the REAL curl won, and
    # the row was hitting the live GitHub API. A function cannot be shadowed. Each lookup row's -Expect is what proves the
    # fake ran. The function costs no process, so the pinned counts are the hook's own. ---
    New-BudgetRow "$D/fetch-clavity-ls.sh" 'binary installed, stamp matches (steady state)' {
        param($fx)
        $bin = Join-Path $fx.Root 'data/bin'; New-Item -ItemType Directory -Force -Path $bin, (Join-Path $fx.Root 'root') | Out-Null
        [IO.File]::WriteAllText((Join-Path $fx.Root 'root/plugin.json'), '{"version":"9.9.9"}')
        [IO.File]::WriteAllText((Join-Path $bin 'clavity-ls.exe'), 'BIN'); [IO.File]::WriteAllText((Join-Path $bin '.clavity-ls.version'), '9.9.9')
        $fx.Env.CLAUDE_PLUGIN_DATA = (($fx.Root -replace '\\', '/') + '/data'); $fx.Env.CLAUDE_PLUGIN_ROOT = (($fx.Root -replace '\\', '/') + '/root')
        New-SessionStartPayload $fx } -Max 0 -Silent
    New-BudgetRow "$D/fetch-clavity-ls.sh" 'release lookup FAILS (fake curl = false) -> manual-install note' {
        param($fx)
        New-Item -ItemType Directory -Force -Path (Join-Path $fx.Root 'root') | Out-Null
        $be = Join-Path $fx.Root 'fake-curl.sh'; [IO.File]::WriteAllText($be, "curl() { return 22; }`n")
        [IO.File]::WriteAllText((Join-Path $fx.Root 'root/plugin.json'), '{"version":"9.9.9"}')
        $fx.Env.CLAUDE_PLUGIN_DATA = (($fx.Root -replace '\\', '/') + '/data'); $fx.Env.CLAUDE_PLUGIN_ROOT = (($fx.Root -replace '\\', '/') + '/root')
        $fx.Env.BASH_ENV = ($be -replace '\\', '/')
        New-SessionStartPayload $fx } -Max 1 -Expect 'release lookup failed'
    New-BudgetRow "$D/fetch-clavity-ls.sh" 'lookup EMPTY (fake curl = true, jq present) -> no-asset note' {
        param($fx)
        New-Item -ItemType Directory -Force -Path (Join-Path $fx.Root 'root') | Out-Null
        $be = Join-Path $fx.Root 'fake-curl.sh'; [IO.File]::WriteAllText($be, "curl() { return 0; }`n")
        [IO.File]::WriteAllText((Join-Path $fx.Root 'root/plugin.json'), '{"version":"9.9.9"}')
        $fx.Env.CLAUDE_PLUGIN_DATA = (($fx.Root -replace '\\', '/') + '/data'); $fx.Env.CLAUDE_PLUGIN_ROOT = (($fx.Root -replace '\\', '/') + '/root')
        $fx.Env.BASH_ENV = ($be -replace '\\', '/')
        New-SessionStartPayload $fx } -Max 9 -Expect 'no release asset named'
    New-BudgetRow "$D/clavity-dotnet-setup.sh" 'not a plugin context' { param($fx) New-SessionStartPayload $fx } -Silent
    New-BudgetRow "$A/agy-inbox-snapshot.sh" 'non-curate skill' { param($fx) New-ToolPayload $fx 'Skill' @{ skill = 'dataviz' } } -Silent
    New-BudgetRow "$A/agy-inbox-snapshot.sh" 'UserPromptSubmit, ordinary prompt' { param($fx) ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'UserPromptSubmit'; prompt = 'hi' } } -Silent
    # --- agy-inbox-snapshot.sh: the Branch 21 census paths (PreToolUse Skill + UserPromptSubmit) ---
    New-BudgetRow "$A/agy-inbox-snapshot.sh" 'curate skill, steady state: 5 baks -> snapshot + prune 1' {
        param($fx) [void](Add-FxInbox $fx -Baks 5); New-ToolPayload $fx 'Skill' @{ skill = 'agy-autotrain:agy-curate' } } -Silent -Verify {
        param($fx) (Get-FxBaks $fx).Count | Should -Be 5 }
    New-BudgetRow "$A/agy-inbox-snapshot.sh" 'curate skill, 20 baks -> snapshot + prune 16 in ONE rm' {
        param($fx) [void](Add-FxInbox $fx -Baks 20); New-ToolPayload $fx 'Skill' @{ skill = 'agy-autotrain:agy-curate' } } -Silent -Verify {
        param($fx) $left = Get-FxBaks $fx; $left.Count | Should -Be 5
        # IDENTITY, not count: the survivors are the four NEWEST old slots (17..20) plus the new snapshot.
        foreach ($n in 17..20) { ($left -match ('202601{0:d2}-000000' -f $n)).Count | Should -Be 1 } }
    New-BudgetRow "$A/agy-inbox-snapshot.sh" 'curate via UserPromptSubmit prompt, no baks -> first snapshot' {
        param($fx) [void](Add-FxInbox $fx); ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'UserPromptSubmit'; prompt = '/agy-curate' } } -Silent -Verify {
        param($fx) (Get-FxBaks $fx).Count | Should -Be 1 }
    New-BudgetRow "$A/agy-inbox-snapshot.sh" 'curate skill, newest bak identical -> dedup, no rotate' {
        param($fx) $obs = Add-FxInbox $fx; Copy-Item -LiteralPath $obs -Destination "$obs.20260101-000000.bak"
        New-ToolPayload $fx 'Skill' @{ skill = 'agy-autotrain:agy-curate' } } -Silent -Verify {
        param($fx) (Get-FxBaks $fx).Count | Should -Be 1 }
    New-BudgetRow "$A/agy-inbox-snapshot.sh" 'curate skill, Pending empty -> invariant 2 refuses, silent' {
        param($fx) [void](Add-FxInbox $fx -EmptyPending); New-ToolPayload $fx 'Skill' @{ skill = 'agy-autotrain:agy-curate' } } -Silent -Verify {
        param($fx) (Get-FxBaks $fx).Count | Should -Be 0 }
    New-BudgetRow "$A/agy-inbox-snapshot.sh" 'non-curate prompt (hot path, silent)' {
        param($fx) [void](Add-FxInbox $fx); ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'UserPromptSubmit'; prompt = 'hello' } } -Silent -Verify {
        param($fx) (Get-FxBaks $fx).Count | Should -Be 0 }
    New-BudgetRow "$A/migrate-inbox.sh" 'nothing to migrate' { param($fx) New-SessionStartPayload $fx } -Silent
    New-BudgetRow "$A/agy-learn-reminder.sh" 'SessionStart' { param($fx) New-SessionStartPayload $fx } -HookArgs @('SessionStart') -Expect 'agy-autotrain is active'
    New-BudgetRow "$A/agy-learn-reminder.sh" 'PreCompact' { param($fx) ConvertTo-HookPayload @{ cwd = $fx.RepoFwd; session_id = 's1'; hook_event_name = 'PreCompact'; trigger = 'manual' } } -HookArgs @('PreCompact') -Expect 'agy-LEARN check BEFORE COMPACTION'
    New-BudgetRow "$L/agy-verify-reminder.sh" 'not the clavity repo' { param($fx) New-SessionStartPayload $fx } -Max 0 -Silent
    # --- agy-verify-reminder.sh: the Branch 21 census paths, PINNED at the measured counts (2026-10-07; before: stale 21,
    # current 19, not-the-repo 7). A FAKE agy keeps the count deterministic - the real agy's
    # child-process count floats with its version. New-HookFixture's Env carries NO PATH key (measured, panel R1), so
    # these rows PREPEND to the session's $env:PATH: prepending to $fx.Env.PATH would hand the hook a PATH holding only
    # the fake directory and silently drop jq and every real tool. ---
    New-BudgetRow "$L/agy-verify-reminder.sh" 'stale rows -> EMIT (fake agy on PATH)' {
        param($fx)
        $v = Join-Path $fx.Repo 'agy-autotrain/verify'; New-Item -ItemType Directory -Force -Path $v, (Join-Path $fx.Root 'fakebin') | Out-Null
        @('| id | dotnet | classic |', '|----|--------|---------|', '| A1 | PASS 1.0.0 | N/A |') | Set-Content -LiteralPath (Join-Path $v 'assertions.md')
        [IO.File]::WriteAllText((Join-Path $fx.Root 'fakebin/agy'), "#!/bin/sh`necho agy 9.9.9`n")
        $fx.Env.PATH = ((Join-Path $fx.Root 'fakebin') + ';' + $env:PATH)
        New-SessionStartPayload $fx } -Max 10 -Expect 'VERIFY-HARNESS reminder'
    New-BudgetRow "$L/agy-verify-reminder.sh" 'all rows current -> silent (fake agy on PATH)' {
        param($fx)
        $v = Join-Path $fx.Repo 'agy-autotrain/verify'; New-Item -ItemType Directory -Force -Path $v, (Join-Path $fx.Root 'fakebin') | Out-Null
        @('| id | dotnet | classic |', '|----|--------|---------|', '| A1 | PASS 9.9.9 | N/A |') | Set-Content -LiteralPath (Join-Path $v 'assertions.md')
        [IO.File]::WriteAllText((Join-Path $fx.Root 'fakebin/agy'), "#!/bin/sh`necho agy 9.9.9`n")
        $fx.Env.PATH = ((Join-Path $fx.Root 'fakebin') + ';' + $env:PATH)
        New-SessionStartPayload $fx } -Max 8 -Silent
    New-BudgetRow "$L/docs-audit-reminder.sh" 'no findings view' { param($fx) New-SessionStartPayload $fx } -Silent
    # --- docs-audit-reminder.sh: the Branch 21 census paths. PINNED AT 0 (measured 2026-10-07): the whole hook is builtins now,
    # so ANY process is a regression the shared ceiling of 13 could not see. Before: both rows 19. ---
    New-BudgetRow "$L/docs-audit-reminder.sh" 'generated view, 3 open findings -> EMIT' {
        param($fx)
        $d = Join-Path $fx.Repo 'docs'; New-Item -ItemType Directory -Force -Path $d | Out-Null
        @('# docs audit findings (GENERATED 2026-10-07)', '', '## a.md', '- f1', '- f2', '- f3') | Set-Content -LiteralPath (Join-Path $d 'docs-audit-findings.md')
        $fx.Env.CLAUDE_PROJECT_DIR = $fx.RepoFwd
        New-SessionStartPayload $fx } -Max 0 -Expect '3 open finding'
    New-BudgetRow "$L/docs-audit-reminder.sh" 'generated view, (no findings) only -> silent' {
        param($fx)
        $d = Join-Path $fx.Repo 'docs'; New-Item -ItemType Directory -Force -Path $d | Out-Null
        @('# docs audit findings (GENERATED 2026-10-07)', '', '## a.md', '- (no findings)') | Set-Content -LiteralPath (Join-Path $d 'docs-audit-findings.md')
        $fx.Env.CLAUDE_PROJECT_DIR = $fx.RepoFwd
        New-SessionStartPayload $fx } -Max 0 -Silent
)

# Narrow to ONE hook for a task's red/green runs: set HSB_HOOK to the hook's file name and run with
# -TagFilter row. MEASURED 2026-10-04: Invoke-Pester -FullNameFilter does NOT see the expanded '<Hook>' row
# names (a filter on the hook name ran 0 tests), so the narrowing happens here, at discovery.
if ($env:HSB_HOOK) {
    $script:Rows = @($script:Rows | Where-Object { (Split-Path -Leaf $_.Hook) -eq $env:HSB_HOOK })
    # A mistyped name selects nothing, and a 0-test run exits 0 under -CI (agy panel R3): fail discovery instead.
    if ($script:Rows.Count -eq 0) { throw "HSB_HOOK='$($env:HSB_HOOK)' matches no budget row - check the hook file name" }
}

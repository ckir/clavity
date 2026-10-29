# Pester skip inventory

This file is GENERATED, never hand-edited. Regenerate it with:

    pwsh scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory scripts/tests/_skip-inventory.md -WriteSkipInventory

and review the diff in the PR: a new row is a new skip somebody has to justify.

The gate (`scripts/run-pester-parallel.ps1`, enforced by `just test-scripts`) fails the run on:

- an UNAPPROVED SKIP: a skipped row with no approval written in the test itself;
- an OS-TAG MISMATCH: a `WindowsOnly`/`LinuxOnly` row that ran on the wrong OS, or a row tagged for the current OS that skipped without an `APPROVED:` reason;
- a stale `static` table (a skipped static row that is not listed, or a listed one that no longer skips);
- an unlisted `conditional` skip (a listed conditional row that did not skip is fine: a tool or root state may differ per host);
- a missing `## <os>` section for the OS the run is on (fails closed).

Approval vocabulary (closed). A skipped row is approved by a `-Tag` (its own or an enclosing block's) or, for a run-time
`Set-ItResult -Skipped`, by `-Because 'APPROVED:<tag>: <why>'`:

- `WindowsOnly`, `LinuxOnly` - static, listed in `### static`;
- `NotAsRoot` - the row cannot run as root;
- `NeedsTool:<name>` - a tool is absent (`<name>` matches `[A-Za-z0-9._-]+`);
- `FsFeature:<name>` - a filesystem feature is absent (same `<name>` rule).

The last three are conditional, listed in `### conditional`. A listed line is documentation, never a grant: approval lives in the test.

## linux

### static

| Suite | Row | Tag | Reason |
| --- | --- | --- | --- |
| BashHookHelpers.Tests.ps1 | BashHookHelpers (harness validation).Measure-BashHookProcesses (Job Object process counter).counts NOTHING beyond bash boot for a builtins-only script | WindowsOnly | - |
| BashHookHelpers.Tests.ps1 | BashHookHelpers (harness validation).Measure-BashHookProcesses (Job Object process counter).counts a git call the same with core.fsmonitor on, without waiting on git's daemon | WindowsOnly | - |
| BashHookHelpers.Tests.ps1 | BashHookHelpers (harness validation).Measure-BashHookProcesses (Job Object process counter).counts exactly the two processes one external command costs (the failing control: it must SEE a child) | WindowsOnly | - |
| BashHookHelpers.Tests.ps1 | BashHookHelpers (harness validation).Measure-BashHookProcesses (Job Object process counter).counts what a detached background subshell starts AFTER bash exits, the same as in the foreground | WindowsOnly | - |
| BashHookHelpers.Tests.ps1 | BashHookHelpers (harness validation).Measure-BashHookProcesses (Job Object process counter).keeps a caller's own GIT_CONFIG_* entries and still turns fsmonitor off | WindowsOnly | - |
| BashHookHelpers.Tests.ps1 | BashHookHelpers (harness validation).Measure-BashHookProcesses (Job Object process counter).passes -Env to the hook WITHOUT changing this process environment | WindowsOnly | - |
| BashHookHelpers.Tests.ps1 | BashHookHelpers (harness validation).Measure-BashHookProcesses (Job Object process counter).resolves the real git a hook gets under Git's launcher, even from a bare PATH and no MSYSTEM | WindowsOnly | - |
| agy-liveness-check.Tests.ps1 | agy-liveness-check.sh.stays SILENT on stderr when PATH carries no external tools at all | WindowsOnly | the raw MSYS shell is a Git for Windows layout |
| agy-mark.Tests.ps1 | agy-mark.sh.head mode.RESOLVES ITS OWN HELPERS when invoked by an all-BACKSLASH Windows path | WindowsOnly | - |
| check-dangling-consumers.Tests.ps1 | check-dangling-consumers.reports the correct relative path when -RepoRoot is an 8.3 SHORT path | WindowsOnly | 8.3 short names are a Windows filesystem feature |
| check-injected-context.Tests.ps1 | ConvertTo-GateRepoRoot (ROADMAP §42).walks the drive root, not the cwd, when the root IS a drive root | WindowsOnly | - |
| check-injected-context.Tests.ps1 | check-injected-context.ps1.computes a sane relative path when -RepoRoot is an 8.3 SHORT path | WindowsOnly | 8.3 short names are a Windows filesystem feature |
| check-installer-ascii.Tests.ps1 | check-installer-ascii.ps1.reports the correct relative path when -RepoRoot is an 8.3 SHORT path | WindowsOnly | 8.3 short names are a Windows filesystem feature |
| check-plugin-drift.Tests.ps1 | check-plugin-drift.ps1.accepts an installed root given as an 8.3 SHORT path | WindowsOnly | 8.3 short names are a Windows filesystem feature |
| hook-spawn-budget.Tests.ps1 | hook spawn budget..claude/hooks/agy-verify-reminder.sh: all rows current -> silent (fake agy on PATH) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget..claude/hooks/agy-verify-reminder.sh: all rows current -> silent (fake agy on PATH) starts at most 8 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget..claude/hooks/agy-verify-reminder.sh: not the clavity repo prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget..claude/hooks/agy-verify-reminder.sh: not the clavity repo starts at most 0 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget..claude/hooks/agy-verify-reminder.sh: stale rows -> EMIT (fake agy on PATH) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget..claude/hooks/agy-verify-reminder.sh: stale rows -> EMIT (fake agy on PATH) starts at most 10 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget..claude/hooks/docs-audit-reminder.sh: generated view, (no findings) only -> silent prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget..claude/hooks/docs-audit-reminder.sh: generated view, (no findings) only -> silent starts at most 0 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget..claude/hooks/docs-audit-reminder.sh: generated view, 3 open findings -> EMIT prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget..claude/hooks/docs-audit-reminder.sh: generated view, 3 open findings -> EMIT starts at most 0 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget..claude/hooks/docs-audit-reminder.sh: no findings view prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget..claude/hooks/docs-audit-reminder.sh: no findings view starts at most 0 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-curate-nudge.sh: inbox missing prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-curate-nudge.sh: inbox missing starts at most 3 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-curate-nudge.sh: worst: snooze expired + 16 recent entries prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-curate-nudge.sh: worst: snooze expired + 16 recent entries starts at most 9 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-inbox-snapshot.sh: UserPromptSubmit, ordinary prompt prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-inbox-snapshot.sh: UserPromptSubmit, ordinary prompt starts at most 0 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-inbox-snapshot.sh: curate skill, 20 baks -> snapshot + prune 16 in ONE rm prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-inbox-snapshot.sh: curate skill, 20 baks -> snapshot + prune 16 in ONE rm starts at most 8 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-inbox-snapshot.sh: curate skill, Pending empty -> invariant 2 refuses, silent prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-inbox-snapshot.sh: curate skill, Pending empty -> invariant 2 refuses, silent starts at most 0 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-inbox-snapshot.sh: curate skill, newest bak identical -> dedup, no rotate prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-inbox-snapshot.sh: curate skill, newest bak identical -> dedup, no rotate starts at most 4 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-inbox-snapshot.sh: curate skill, steady state: 5 baks -> snapshot + prune 1 prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-inbox-snapshot.sh: curate skill, steady state: 5 baks -> snapshot + prune 1 starts at most 8 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-inbox-snapshot.sh: curate via UserPromptSubmit prompt, no baks -> first snapshot prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-inbox-snapshot.sh: curate via UserPromptSubmit prompt, no baks -> first snapshot starts at most 4 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-inbox-snapshot.sh: non-curate prompt (hot path, silent) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-inbox-snapshot.sh: non-curate prompt (hot path, silent) starts at most 0 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-inbox-snapshot.sh: non-curate skill prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-inbox-snapshot.sh: non-curate skill starts at most 0 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-learn-reminder.sh: PreCompact prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-learn-reminder.sh: PreCompact starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-learn-reminder.sh: SessionStart prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/agy-learn-reminder.sh: SessionStart starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/migrate-inbox.sh: RECOVER an interrupted migration (sidecar back, then complete) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/migrate-inbox.sh: RECOVER an interrupted migration (sidecar back, then complete) starts at most 6 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/migrate-inbox.sh: nothing to migrate prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-autotrain/hooks/migrate-inbox.sh: nothing to migrate starts at most 0 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.agy-consult-recovery.sh costs the same with 1 seam and with 1000 (the cost must not scale with the seam count) | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-classic/plugin/hooks/agy-drive-session-reset.sh: startup: own flag + 5 stale + 2 fresh prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-classic/plugin/hooks/agy-drive-session-reset.sh: startup: own flag + 5 stale + 2 fresh starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-after-reminder.sh: non-plan Edit prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-after-reminder.sh: non-plan Edit starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-after-reminder.sh: plan Edit prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-after-reminder.sh: plan Edit starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh: PreCompact prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh: PreCompact re-arming a test-audit debounce prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh: PreCompact re-arming a test-audit debounce starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh: PreCompact starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh: UserPromptSubmit prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh: UserPromptSubmit starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh: Agent dispatch prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh: Agent dispatch starts at most 6 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-anomaly-model-notice.sh: startup prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-anomaly-model-notice.sh: startup starts at most 4 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh: 3 untriaged with dates -> EMIT the oldest prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh: 3 untriaged with dates -> EMIT the oldest starts at most 2 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh: 50 untriaged (scaling: the count loop is builtin) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh: 50 untriaged (scaling: the count loop is builtin) starts at most 2 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh: startup, nothing captured prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh: startup, nothing captured starts at most 0 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh: PINNED consult: MCP agy_ask (after its pre) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh: PINNED consult: MCP agy_ask (after its pre) starts at most 68 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh: PINNED consult: MCP agy_ask, inconclusive return (after its pre) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh: PINNED consult: MCP agy_ask, inconclusive return (after its pre) starts at most 70 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh: PINNED consult: clavity ask (after its pre) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh: PINNED consult: clavity ask (after its pre) starts at most 71 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh: PINNED consult: clavity await-reply (after a send) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh: PINNED consult: clavity await-reply (after a send) starts at most 80 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh: clavity send (post is a no-op) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh: clavity send (post is a no-op) starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh: command text mentions the consult CLI prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh: command text mentions the consult CLI starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh: consult outside a git repo prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh: consult outside a git repo starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh: non-consult Bash call prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh: non-consult Bash call starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh: PINNED consult: MCP agy_ask prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh: PINNED consult: MCP agy_ask starts at most 65 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh: PINNED consult: clavity ask prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh: PINNED consult: clavity ask starts at most 68 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh: PINNED consult: clavity send prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh: PINNED consult: clavity send starts at most 71 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh: clavity await-reply (pre is a no-op) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh: clavity await-reply (pre is a no-op) starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh: command text mentions the consult CLI prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh: command text mentions the consult CLI starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh: consult outside a git repo prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh: consult outside a git repo starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh: non-consult Bash call prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh: non-consult Bash call starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-recovery.sh: 1000 mixed seams prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-recovery.sh: 1000 mixed seams starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-recovery.sh: 1000 seams, all concluded prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-recovery.sh: 1000 seams, all concluded starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-recovery.sh: one open seam prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-consult-recovery.sh: one open seam starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: jsonl TRACKED by git -> persistent message, marker written prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: jsonl TRACKED by git -> persistent message, marker written starts at most 4 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: long-lived repo: a NEW session on the recurring ! negation path (old markers present) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: long-lived repo: a NEW session on the recurring ! negation path (old markers present) starts at most 9 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: long-lived repo: a NEW session, healthy shield (old markers present) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: long-lived repo: a NEW session, healthy shield (old markers present) starts at most 4 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: long-lived repo: the FIRST-prepend run with old markers present (one-time exemption, Max 14) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: long-lived repo: the FIRST-prepend run with old markers present (one-time exemption, Max 14) starts at most 14 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: normal FIRST session (shield ok, sweep latch, row written) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: normal FIRST session (shield ok, sweep latch, row written) starts at most 2 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: shield already * + ! negation, REPEAT session (swept marker present) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: shield already * + ! negation, REPEAT session (swept marker present) starts at most 9 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: shield file MISSING -> created with * prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: shield file MISSING -> created with * starts at most 2 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: shield has a ! negation -> PREPEND, first session (one-time exemption, Max 14) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: shield has a ! negation -> PREPEND, first session (one-time exemption, Max 14) starts at most 14 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: shield lacks * -> appended prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: shield lacks * -> appended starts at most 2 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: startup, shield intact prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh: startup, shield intact starts at most 2 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-liveness-check.sh: no settings files prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-liveness-check.sh: no settings files starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-liveness-check.sh: three settings files, one a personal duplicate (warns) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-liveness-check.sh: three settings files, one a personal duplicate (warns) starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-seam-inject.sh: non-seam skill prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-seam-inject.sh: non-seam skill starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-seam-inject.sh: seam skill, marker behind HEAD with code since prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-seam-inject.sh: seam skill, marker behind HEAD with code since starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-seam-inject.sh: seam skill, no marker prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-seam-inject.sh: seam skill, no marker starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-seam-inject.sh: skill value containing a newline prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-seam-inject.sh: skill value containing a newline starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh: debounced: second call at the same HEAD prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh: debounced: second call at the same HEAD starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh: fires: a MERGE commit in the reviewed range prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh: fires: a MERGE commit in the reviewed range starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh: fires: a code file RENAMED since main prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh: fires: a code file RENAMED since main starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh: fires: capstone marker at HEAD, code vs main prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh: fires: capstone marker at HEAD, code vs main starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh: fires: worst path, both markers behind HEAD prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh: fires: worst path, both markers behind HEAD starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh: no .clavity (not opted in) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh: no .clavity (not opted in) starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh: no jq: debounced second call prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh: no jq: debounced second call starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh: no jq: fires on the ledger shape (marker behind HEAD, docs since) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh: no jq: fires on the ledger shape (marker behind HEAD, docs since) starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh: TMPDIR unusable -> HOME/.clavity-tmp fallback still emits prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh: TMPDIR unusable -> HOME/.clavity-tmp fallback still emits starts at most 11 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh: non-test Edit prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh: non-test Edit starts at most 3 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh: non-test file (the hottest path, silent) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh: non-test file (the hottest path, silent) starts at most 3 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh: test file, FIRST touch of the session -> marker + prune + emit prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh: test file, FIRST touch of the session -> marker + prune + emit starts at most 7 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh: test file, no session_id (day-key marker: builtin clock, no date fork) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh: test file, no session_id (day-key marker: builtin clock, no date fork) starts at most 7 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/clavity-dotnet-setup.sh: not a plugin context prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/clavity-dotnet-setup.sh: not a plugin context starts at most 13 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh: binary installed, stamp matches (steady state) prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh: binary installed, stamp matches (steady state) starts at most 0 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh: lookup EMPTY (fake curl = true, jq present) -> no-asset note prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh: lookup EMPTY (fake curl = true, jq present) -> no-asset note starts at most 9 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh: not a plugin context prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh: not a plugin context starts at most 0 processes beyond bash boot | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh: release lookup FAILS (fake curl = false) -> manual-install note prints the same on the bash 3.2 code path | WindowsOnly | - |
| hook-spawn-budget.Tests.ps1 | hook spawn budget.clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh: release lookup FAILS (fake curl = false) -> manual-install note starts at most 1 processes beyond bash boot | WindowsOnly | - |
| installer-user-path.Tests.ps1 | installer user PATH handling.behavioural - the include, compiled by ISCC and run.RebuildUserPath returns the expected value for every case | WindowsOnly | - |
| installer-user-path.Tests.ps1 | installer user PATH handling.behavioural - the include, compiled by ISCC and run.never touches the real user PATH | WindowsOnly | - |
| installer-user-path.Tests.ps1 | installer user PATH handling.behavioural - the include, compiled by ISCC and run.the registry half CREATES an absent PATH value as REG_EXPAND_SZ | WindowsOnly | - |
| installer-user-path.Tests.ps1 | installer user PATH handling.behavioural - the include, compiled by ISCC and run.the registry half heals duplicates, writes REG_EXPAND_SZ, and writes only on a change | WindowsOnly | - |
| path-lib.Tests.ps1 | Get-RootRelativePath.normalises an 8.3 SHORT root | WindowsOnly | 8.3 short names are a Windows filesystem feature |
| path-lib.Tests.ps1 | Get-RootRelativePath.resolves a child under a JUNCTION root, and THROWS for the same file reached by its real path | WindowsOnly | mklink is a Windows shell builtin, so a junction cannot be created here |
| review-relay-install.Tests.ps1 | install-extension.ps1.leaves the previous install intact and exits 1 when the swap is blocked by an open file | WindowsOnly | - |
| review-relay-install.Tests.ps1 | install-extension.ps1.refuses to swap, and keeps the live install, when a leftover dest.old beside it cannot be cleared | WindowsOnly | - |

### conditional

| Suite | Row | Tag | Reason |
| --- | --- | --- | --- |
| BashHookHelpers.Tests.ps1 | BashHookHelpers (harness validation).cross-platform fixture helpers.Set-TestFileReadOnly makes an append fail, and Clear-TestFileReadOnly undoes it | NotAsRoot | this user (root?) is not bound by read-only |
| BashHookHelpers.Tests.ps1 | BashHookHelpers (harness validation).cross-platform fixture helpers.Set-TestPathUnreadable blocks the BASH process, and Restore-TestPathReadable undoes it | NotAsRoot | this user (root?) is not bound by the deny |
| TestTemp.Tests.ps1 | the shared test temp root.the sweep tolerates a child it cannot delete, and still removes the deletable ones | NotAsRoot | root is not bound by directory permissions |
| agy-anomaly-reminder.Tests.ps1 | agy-anomaly-reminder.sh.REPORTS an unreadable anomalies file rather than counting zero | NotAsRoot | this host does not enforce the read deny against the hook process |
| agy-autotrain-migrate-inbox.Tests.ps1 | agy-autotrain migrate-inbox hook.reports an UNREADABLE sidecar during recovery and touches nothing | NotAsRoot | this host does not enforce the read deny against the hook process |
| agy-autotrain-migrate-inbox.Tests.ps1 | agy-autotrain migrate-inbox hook.stops and rolls back when the destination is UNREADABLE (an ACL deny) - an open, not a -r test, decides | NotAsRoot | this host does not enforce the read deny against the hook process |
| agy-consult-guard.Tests.ps1 | agy-consult-guard.WARNS when an UNREADABLE hook is planted during a consult | NotAsRoot | root reads a chmod 000 file, so the unreadable state is unreachable |
| agy-consult-guard.Tests.ps1 | agy-consult-guard.WARNS when an existing hook becomes unreadable | NotAsRoot | root reads a chmod 000 file, so the unreadable state is unreachable |
| agy-discipline-reaching.Tests.ps1 | agy-discipline-reaching.sh.14c - the hook asserts the .clavity shield.the FALLBACK WARNS - it does not fail silent - when it cannot assert the shield (capstone r2b) | NotAsRoot | the write-deny did not take for THIS bash (elevated token, or a filesystem that ignores ACLs), so the unassertable-shield state is unreachable here |
| agy-discipline-reaching.Tests.ps1 | agy-discipline-reaching.sh.14c - the hook asserts the .clavity shield.the FALLBACK blames the DIRECTORY when the shield file was never created (capstone r2e) | NotAsRoot | the directory write-deny did not take for THIS bash (elevated token, or a filesystem that ignores ACLs), so an uncreatable shield is unreachable here |
| agy-ledger-lib.Tests.ps1 | agy-ledger-lib.sh.refusals - and each one names its cause.answers UNREADABLE - not ABSENT - when the ledger cannot be OPENED | NotAsRoot | the read-deny did not take for THIS bash (elevated token, or a filesystem that ignores ACLs), so the unreadable state is unreachable here |
| agy-shield-lib.Tests.ps1 | agy-shield-lib.sh.the debounce key.a failed shield write OUTSIDE a git repository is reported, not swallowed | NotAsRoot | read-only is not enforced for this user |
| agy-shield-lib.Tests.ps1 | agy-shield-lib.sh.the debounce key.when the fallback append ALSO fails it says the directory is NOT protected | NotAsRoot | read-only is not enforced for this user |
| docs-audit-reminder.Tests.ps1 | docs-audit-reminder.sh.reports an UNREADABLE view as unrecognisable rather than passing it silently | NotAsRoot | this host does not enforce the read deny against the hook process |
| generate-cheatsheet-literals.Tests.ps1 | generate-cheatsheet-literals.ps1.is ALL-OR-NOTHING across the two targets - a failed C# write does not leave rust rewritten | NotAsRoot | root writes a read-only file, so the write cannot be made to fail |
| path-lib.Tests.ps1 | Get-RootRelativePath.accepts a PATH spelled in different casing from the disk, because NTFS is case-insensitive | FsFeature:case-insensitive | - |
| path-lib.Tests.ps1 | Get-RootRelativePath.normalises an UPPERCASE root | FsFeature:case-insensitive | - |
| project-store.Tests.ps1 | project-store.sh.feeds curate-commit: the published GROWTH is the proposal byte for byte, has its sidecar, and the SessionStart nudge goes quiet | NeedsTool:clavity | no curate-commit binary (CLAVITY_CURATE_COMMIT_EXE, clavity-classic debug build, clavity-ls or clavity on PATH) is available |
| review-relay-scripts.Tests.ps1 | collect.ps1.a failed rebuild leaves no stale collected.md (G4) | NotAsRoot | root is not bound by directory permissions |

## windows

### static

| Suite | Row | Tag | Reason |
| --- | --- | --- | --- |
| BashHookHelpers.Tests.ps1 | BashHookHelpers (harness validation).cross-platform fixture helpers.New-NoJqPath leaves no temp directory behind when its own postcondition throws | LinuxOnly | - |
| agy-consult-guard.Tests.ps1 | agy-consult-guard.WARNS when a SYMLINKED .git hook is planted during a consult | LinuxOnly | - |
| agy-consult-guard.Tests.ps1 | agy-consult-guard.WARNS when a hook symlink is re-pointed at different bytes during a consult | LinuxOnly | - |
| agy-consult-guard.Tests.ps1 | agy-consult-guard.WARNS when an UNREADABLE hook is planted during a consult | LinuxOnly | chmod 000 does not make a file unreadable to Git Bash on Windows |
| agy-consult-guard.Tests.ps1 | agy-consult-guard.WARNS when an existing hook becomes unreadable | LinuxOnly | chmod 000 does not make a file unreadable to Git Bash on Windows |
| agy-consult-guard.Tests.ps1 | agy-consult-guard.agy_guard_hash_files gives the same digests as the old cut\|sed pipeline | LinuxOnly | - |
| agy-consult-guard.Tests.ps1 | agy-consult-guard.section 87 - the sentinel of an unfinished consult.has no time limit: a sentinel two days old still speaks | LinuxOnly | - |
| register-plugin.Tests.ps1 | Test-AgentPresent.falls back to HOME when USERPROFILE is unset (the Linux/macOS case; no mocks, child process) | LinuxOnly | - |

### conditional

| Suite | Row | Tag | Reason |
| --- | --- | --- | --- |
| BashHookHelpers.Tests.ps1 | BashHookHelpers (harness validation).cross-platform fixture helpers.Set-TestPathUnreadable blocks the BASH process, and Restore-TestPathReadable undoes it | NotAsRoot | this user (root?) is not bound by the deny |
| agy-anomaly-reminder.Tests.ps1 | agy-anomaly-reminder.sh.REPORTS an unreadable anomalies file rather than counting zero | NotAsRoot | this host does not enforce the read deny against the hook process |
| agy-autotrain-migrate-inbox.Tests.ps1 | agy-autotrain migrate-inbox hook.reports an UNREADABLE sidecar during recovery and touches nothing | NotAsRoot | this host does not enforce the read deny against the hook process |
| agy-autotrain-migrate-inbox.Tests.ps1 | agy-autotrain migrate-inbox hook.stops and rolls back when the destination is UNREADABLE (an ACL deny) - an open, not a -r test, decides | NotAsRoot | this host does not enforce the read deny against the hook process |
| agy-discipline-reaching.Tests.ps1 | agy-discipline-reaching.sh.14c - the hook asserts the .clavity shield.the FALLBACK WARNS - it does not fail silent - when it cannot assert the shield (capstone r2b) | NotAsRoot | the write-deny did not take for THIS bash (elevated token, or a filesystem that ignores ACLs), so the unassertable-shield state is unreachable here |
| agy-discipline-reaching.Tests.ps1 | agy-discipline-reaching.sh.14c - the hook asserts the .clavity shield.the FALLBACK blames the DIRECTORY when the shield file was never created (capstone r2e) | FsFeature:dir-write-deny | denying WRITE on a directory is not dependable on Windows (an elevated token ignores the ACE); this row is measured under POSIX, where chmod is exact |
| agy-ledger-lib.Tests.ps1 | agy-ledger-lib.sh.refusals - and each one names its cause.answers UNREADABLE - not ABSENT - when the ledger cannot be OPENED | NotAsRoot | the read-deny did not take for THIS bash (elevated token, or a filesystem that ignores ACLs), so the unreadable state is unreachable here |
| docs-audit-reminder.Tests.ps1 | docs-audit-reminder.sh.reports an UNREADABLE view as unrecognisable rather than passing it silently | NotAsRoot | this host does not enforce the read deny against the hook process |
| project-store.Tests.ps1 | project-store.sh.feeds curate-commit: the published GROWTH is the proposal byte for byte, has its sidecar, and the SessionStart nudge goes quiet | NeedsTool:clavity | no curate-commit binary (CLAVITY_CURATE_COMMIT_EXE, clavity-classic debug build, clavity-ls or clavity on PATH) is available |

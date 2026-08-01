# Anomaly capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An anomaly an agent notices while doing something else lands in a durable local file the moment it is spotted, and a SessionStart hook keeps naming it until it is either promoted to a tracked ROADMAP item or deleted with a reason.

**Architecture:** Three shipped artifacts per driver plugin — a capture FORMAT (a one-line markdown bullet appended to a gitignored file), a SessionStart REMINDER hook that counts untriaged entries and demands triage, and an `open-issues` SKILL carrying the capture bar and the triage procedure. The spotter (subagent or main agent) appends directly; nothing routes through the main agent's user-facing summary, because that summary is where anomalies measurably died.

**Tech Stack:** bash (hook, jq-dependent, pure ASCII), Pester 5 (tests), markdown (skill + capture file), JSON (hooks.json registration).

---

## Design provenance (do not re-litigate these; they are settled)

This plan implements the design in the operator's memory at `project_anomaly-capture-design.md`, converged
through an AGY-FIRST consult plus **two** AGY-NEGOTIATE rounds with real position changes on both sides.
Settled and NOT open for reinterpretation during execution:

- **Gitignored location.** An agent appending RAW un-triaged defects to a PUBLIC repo can publish
  sensitive local paths before the owner sees them. `.clavity/` is already ignored (`.gitignore:45`).
- **The spotter writes DIRECTLY.** The loss is not at noticing and not at capture — it is at
  SUMMARIZATION. Measured: three real anomalies in one session were all reported by their spotter and
  nearly died when the main agent compressed the report. "Instruct subagents to report better" fixes nothing.
- **Zero severity judgement at capture.** Removes the busy-agent incentive to rate low, and the
  per-anomaly evaluation cost.
- **The reminder must COUNT and DEMAND TRIAGE.** Root cause of the sibling `agy-learn` inbox reaching 69
  against a threshold of 8: `~/.claude/hooks/agy-learn-reminder.sh` has no count and no drain-side demand
  anywhere — both its messages only say "capture more". It is one-sided by design.
- **Exactly two exits: promoted to ROADMAP, or deleted with a reason. No parked state.** A parked state is
  how the still-open "surfaced to owner" list formed.

## File structure

| File | Responsibility |
|---|---|
| `clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh` | SessionStart: count untriaged, demand triage, else silent |
| `clavity-classic/plugin/hooks/agy-anomaly-reminder.sh` | byte-identical mirror |
| `clavity-dotnet/plugin/skills/open-issues/SKILL.md` | the capture bar, the exact append line, the triage procedure |
| `clavity-classic/plugin/skills/open-issues/SKILL.md` | byte-identical mirror |
| `clavity-{dotnet,classic}/plugin/hooks/hooks.json` | SessionStart registration (per-plugin, NOT seed-gated) |
| `scripts/check-seed-artifacts-synced.sh` | enrol the two new byte-identical pairs |
| `scripts/tests/agy-anomaly-reminder.Tests.ps1` | Pester coverage for the hook |
| `clavity-dotnet/ROADMAP.md` | record that §7 now needs only the disposition half |

**Do NOT enrol `open-issues` in `scripts/check-agy-discipline-skills.ps1`.** That linter's `$skills` array
(line 13) requires a `$requiredVerdicts` mapping (line 18) and fails loud for any enrolled skill without
one. `open-issues` runs no agy consult and emits no `[VERDICT:]` token; enrolling it would force inventing
fake verdict vocabulary. It is a triage procedure, not an agy discipline.

---

### Task 1: The reminder hook

**Files:**
- Create: `clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh`
- Test: `scripts/tests/agy-anomaly-reminder.Tests.ps1`

- [ ] **Step 0: State verification**

Confirm each; if any differs, STOP and report `STATE_MISMATCH: <what>`:
1. `clavity-dotnet/plugin/hooks/agy-liveness-check.sh` exists and its header documents an EXIT-CODE CONTRACT using stderr + `exit 2`.
2. `scripts/tests/BashHookHelpers.ps1` exists and exports `Invoke-BashHook` accepting `-HookPath`, `-Payload`, `-Env`.
3. `.gitignore` line 45 is `.clavity/`.
4. `clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh` does NOT already exist.

- [ ] **Step 1: Write the failing tests**

Create `scripts/tests/agy-anomaly-reminder.Tests.ps1` with exactly this content:

```powershell
Describe 'agy-anomaly-reminder.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh'
        $bashDir = Split-Path -Parent (Get-GitBashOrThrow)
        $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')

        # A workspace whose .clavity/local-anomalies.md carries $Lines entry bullets.
        function New-Workspace { param([string[]]$Lines)
            $d = Join-Path ([IO.Path]::GetTempPath()) ("anom-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $d '.clavity') -Force | Out-Null
            if ($null -ne $Lines) {
                $body = @('# Untriaged anomalies (gitignored, local)', '') + $Lines
                Set-Content (Join-Path $d '.clavity/local-anomalies.md') ($body -join "`n") -Encoding ascii
            }
            return $d
        }
        function New-CleanHome {
            $h = Join-Path ([IO.Path]::GetTempPath()) ("anom-home-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $h '.claude') -Force | Out-Null
            return $h
        }
        function Payload { param([string]$Cwd) @{ cwd = ($Cwd -replace '\\','/'); source = 'startup' } | ConvertTo-Json -Compress }
    }

    It 'is SILENT (exit 0) when the anomalies file does not exist' {
        $w = New-Workspace $null; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdErr   | Should -BeNullOrEmpty
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT when the file exists but holds no entries' {
        $w = New-Workspace @(); $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdErr   | Should -BeNullOrEmpty
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'REPORTS the count and demands triage when entries exist' {
        $w = New-Workspace @(
            '- [defect] ParseLatest never checks the pid pair matches * LsDiscovery.cs:94 * 2026-07-30 * task=capstone',
            '- [tool] just test-scripts exceeds the 600s tool cap * n/a * 2026-08-01 * task=phase-b'
        )
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match '2 untriaged'
            $r.StdErr   | Should -Match 'promote'
            $r.StdErr   | Should -Match 'delete'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'names the OLDEST entry date, not the newest' {
        $w = New-Workspace @(
            '- [tool] newer thing * n/a * 2026-08-01 * task=x',
            '- [defect] older thing * a.cs:1 * 2026-07-14 * task=y'
        )
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.StdErr | Should -Match '2026-07-14'
            $r.StdErr | Should -Not -Match '2026-08-01'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'counts ONLY entry bullets, not prose or headings in the file' {
        $w = New-Workspace @(
            'Some explanatory prose that is not an entry.',
            '## A heading',
            '- not an entry because it has no bracketed type',
            '- [defect] the only real entry * a.cs:1 * 2026-07-20 * task=z'
        )
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match '1 untriaged'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a workspace .no-agy kill-switch' {
        $w = New-Workspace @('- [defect] x * a.cs:1 * 2026-07-20 * task=z'); $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $w '.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdErr   | Should -BeNullOrEmpty
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT under a global $HOME/.claude/.no-agy kill-switch' {
        $w = New-Workspace @('- [defect] x * a.cs:1 * 2026-07-20 * task=z'); $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdErr   | Should -BeNullOrEmpty
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'warns ONCE (exit 2) when jq is absent rather than failing silently' {
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{"cwd":".","source":"startup"}' -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'missing jq'
            ($r.StdErr -split "`n").Count | Should -Be 1
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT when jq is absent AND .no-agy is set' {
        # Without this, a machine that simply has no jq gets an unsuppressable boot warning forever and
        # .no-agy -- the documented off switch -- does not switch it off. agy-liveness-check.sh:26-36
        # already handles this; the guard mirrors it.
        $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload '{"cwd":".","source":"startup"}' -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $r.ExitCode | Should -Be 0
            $r.StdErr   | Should -BeNullOrEmpty
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'REPORTS an unreadable anomalies file rather than counting zero' {
        # A present-but-unreadable file must not read as "no anomalies" -- that is the same silent zero
        # the jq guard exists to prevent. Skipped on hosts where chmod cannot actually deny read.
        $w = New-Workspace @('- [defect] x * a.cs:1 * 2026-07-20 * task=z'); $h = New-CleanHome
        try {
            $f = Join-Path $w '.clavity/local-anomalies.md'
            & icacls $f /deny "$($env:USERNAME):(R)" 2>&1 | Out-Null
            $stillReadable = $true
            try { [IO.File]::ReadAllText($f) | Out-Null } catch { $stillReadable = $false }
            if ($stillReadable) { Set-ItResult -Skipped -Because 'this host does not enforce the read deny'; return }
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'cannot be read'
        } finally {
            & icacls (Join-Path $w '.clavity/local-anomalies.md') /remove:d "$($env:USERNAME)" 2>&1 | Out-Null
            Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'ships as pure ASCII' {
        ($([IO.File]::ReadAllBytes($script:Hook)) | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run them and verify they FAIL**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-anomaly-reminder.Tests.ps1 -Output Detailed -CI"`
Expected: every block fails — the hook file does not exist yet.

- [ ] **Step 3: Write the hook**

Create `clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh` with exactly this content. **Pure ASCII only** — no em-dash, no smart quotes; this file ships in a plugin and no gate enforces ASCII on hooks.

```bash
#!/usr/bin/env bash
# AGY-ANOMALIES triage reminder (plugin-shipped). SessionStart(startup): an agent that notices a defect
# while doing something ELSE appends one line to .clavity/local-anomalies.md; this hook is the drain side.
# It COUNTS the untriaged entries and DEMANDS triage. Both halves matter: a reminder that only says
# "capture more" and never says "drain" produces a growing pile -- that is the measured failure of the
# sibling agy-learn inbox, which reached 69 entries against a stated threshold of 8 because its reminder
# never counts anything and never asks anyone to clear it.
#
# EMISSION = stderr + `exit 2`, deliberately, matching agy-liveness-check.sh. At SessionStart there is no
# user turn, so additionalContext/stdout is absorbed into the model's context and the OWNER never sees it.
# The owner is the one who triages, so the notice has to reach a human surface. exit 2 is non-blocking for
# SessionStart.
#
# NOT gated on a marker or a relevance path: the anomalies file has no natural relevance gate, and firing
# once per session is already the quietest useful cadence. It is silent whenever there is nothing to say.
# Suppressed by .no-agy (workspace or global) like the other reminders. Byte-identical across both driver
# plugins (kept honest by the seed-sync gate).
set +e
input=$(cat)

# jq is needed to read cwd out of the payload. Without it, say so once rather than failing silently -- a
# silent failure here is indistinguishable from "no anomalies", which is the exact confusion this hook
# exists to prevent. HONOR THE KILL-SWITCH FIRST, exactly as agy-liveness-check.sh does at its lines
# 26-36: without this, a machine that simply has no jq gets an unsuppressable boot warning forever, and
# .no-agy -- the documented way to turn the disciplines off -- would not turn it off.
if ! command -v jq >/dev/null 2>&1; then
  if [ -f "./.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
    exit 0
  fi
  printf '%s\n' "[AGY-ANOMALIES] guard inactive: missing jq - cannot check for untriaged anomalies; install jq" >&2
  exit 2
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)

# Opt-out kill-switch (mirrors agy-after-reminder.sh): silent, no notice.
if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  exit 0
fi

f="$cwd/.clavity/local-anomalies.md"
[ -f "$f" ] || exit 0

# Present but unreadable is NOT "no anomalies". Report it, for the same reason the jq guard above reports
# rather than exiting quietly: a silent zero here is indistinguishable from a clean tree, and this hook
# exists precisely to stop things going unseen.
if [ ! -r "$f" ]; then
  printf '%s\n' "[AGY-ANOMALIES] $f exists but cannot be read - untriaged anomalies NOT counted" >&2
  exit 2
fi

# An ENTRY is a bullet whose first token is a bracketed type: "- [defect] ...". Prose, headings and plain
# bullets in the same file are not entries, so the count cannot be inflated by the file's own preamble.
n=$(grep -c '^- \[[a-z]*\]' "$f" 2>/dev/null)
[ -z "$n" ] && n=0
[ "$n" -eq 0 ] && exit 0

oldest=$(grep '^- \[[a-z]*\]' "$f" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | head -1)
[ -n "$oldest" ] && oldest=" (oldest $oldest)"

printf '%s\n' "[AGY-ANOMALIES] $n untriaged$oldest in .clavity/local-anomalies.md. Triage before new work: each entry is either PROMOTED to a tracked ROADMAP item with an owner, or DELETEd with a recorded reason. There is no parked state. Use the open-issues skill." >&2
exit 2
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-anomaly-reminder.Tests.ps1 -Output Detailed -CI"`
Expected: `Failed: 0`, 11 blocks passing (one may report Skipped on a host that cannot enforce a read deny — that is an accepted outcome for that block only).

- [ ] **Step 5: Mutation-check each guard**

One at a time, apply the mutation, re-run ONLY this test file, confirm the NAMED test goes red, then restore. Record each result. **A guard whose removal leaves the file green is not a guard — report it rather than papering over it.**

Every mutation below is applied **to the hook**, never to a test.

| Mutation (in `agy-anomaly-reminder.sh`) | Test that must go red |
|---|---|
| Change `sort \| head -1` to `sort -r \| head -1` | `names the OLDEST entry date, not the newest` |
| Change the count grep `'^- \[[a-z]*\]'` to `'^- '` | `counts ONLY entry bullets, not prose or headings in the file` |
| Delete the `[ -f "$cwd/.no-agy" ]` term from the kill-switch condition | `is SILENT under a workspace .no-agy kill-switch` |
| Delete the `[ -f "$HOME/.claude/.no-agy" ]` term from the same condition | `is SILENT under a global $HOME/.claude/.no-agy kill-switch` |
| Delete the `[ -f "$f" ] \|\| exit 0` line | `is SILENT (exit 0) when the anomalies file does not exist` |
| Delete the whole `if ! command -v jq` guard | `warns ONCE (exit 2) when jq is absent rather than failing silently` |
| Delete the `if [ ! -r "$f" ]` unreadable guard | `REPORTS an unreadable anomalies file rather than counting zero` |
| Delete the `.no-agy` check INSIDE the jq-missing branch | `is SILENT when jq is absent AND .no-agy is set` |

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh scripts/tests/agy-anomaly-reminder.Tests.ps1
git commit -m "feat(anomalies): SessionStart hook that counts untriaged anomalies and demands triage

The drain side of anomaly capture. A reminder that only ever says 'capture
more' and never says 'drain' produces a growing pile: the sibling agy-learn
inbox reached 69 entries against a threshold of 8 for exactly that reason, and
its hook contains no count and no triage demand anywhere.

stderr + exit 2 rather than additionalContext, matching agy-liveness-check.sh:
at SessionStart there is no user turn, so injected context reaches the model and
never the owner -- and the owner is who triages."
```

---

### Task 2: The open-issues skill

**Files:**
- Create: `clavity-dotnet/plugin/skills/open-issues/SKILL.md`

**Do NOT start until Task 1 is committed** — the skill's text names the hook's behaviour.

- [ ] **Step 1: Write the skill**

Create `clavity-dotnet/plugin/skills/open-issues/SKILL.md` with exactly this content:

```markdown
---
name: open-issues
description: Use when an agent notices a defect, tool misbehavior, or operational blocker that is NOT the task at hand, and when triaging the anomalies already captured. Capture is one appended line; triage promotes each entry to a tracked item or deletes it with a reason.
---

# open-issues - capture an anomaly now, triage it later

An agent doing task X notices something wrong that is NOT task X. Historically the only channel was prose
in a reply, and prose scrolls away. This skill gives that observation somewhere durable to land, and a
procedure for emptying it.

## The bar - what to capture

> Capture any reachable code defect, tool misbehavior, or operational blocker that actively degrades or
> prevents the agent/owner workflow.

That bar is deliberate on both edges. It is wide enough to catch things that are not code bugs at all -
a tool that truncates the reply you asked for, a test gate that outgrew its timeout - because those
silently tax every future session. It is narrow enough to exclude opinion: "this file is getting large",
"I would have named this differently", "this could be more elegant" are NOT anomalies. If you cannot say
what it degrades or prevents, do not capture it.

**Do not judge severity.** There is no severity field. An agent in the middle of a task has an obvious
incentive to rate its own interruption as unimportant, and the owner has to make the call at triage
anyway. Write the fact and move on.

## Capture - one line, written by whoever spots it

**Write it yourself. Do not report it to whoever dispatched you and assume it will survive.** This is the
whole point of the mechanism: anomalies are not usually lost at the moment of noticing, they are lost when
a long report is compressed into a short summary. If you are a subagent, the file is your channel, not
your final message.

Run this, filling the four fields:

```bash
F=.clavity/local-anomalies.md
if [ ! -f "$F" ]; then
  mkdir -p .clavity
  # Self-ignoring directory. This makes .clavity/ invisible to git REGARDLESS of the host repository's
  # own .gitignore, which matters because this plugin ships to repositories whose .gitignore we do not
  # control. Without it, the "capture is private" property holds only in the repo where it was written.
  [ -f .clavity/.gitignore ] || printf '%s\n' '*' > .clavity/.gitignore
  printf '%s\n\n' '# Untriaged anomalies (local, never committed)' > "$F"
fi
printf -- '- [%s] %s * %s * %s * task=%s\n' \
  'defect' 'one line stating the fact' 'path/file.ext:LINE' "$(date +%F)" 'what you were doing' >> "$F"
```

Two things about that snippet are deliberate:

- **The `.clavity/.gitignore` containing `*` is load-bearing, not tidiness.** The decision to keep capture
  private rests on the directory being ignored. In this repository that happens to be true anyway; in a
  user's repository it is true only because of this file.
- **Append with `>>` and a single `printf`.** Several subagents can be capturing at once. A single short
  append is atomic on POSIX, so concurrent writers interleave lines rather than corrupting them. Do not
  read-modify-write the file to add an entry.

- **type**: `defect` (reachable code defect) | `tool` (a tool or peer misbehaving) | `process` (an agent
  or workflow doing the wrong thing)
- **fact**: one line, specific enough to act on later. "discovery regex is brittle" is useless in a week;
  "ParseLatest never checks the HTTP line's pid matches the gRPC line's" is actionable.
- **where**: `file:line` if it has one, `n/a` if it does not.
- **task**: what you were actually doing. This is what lets the owner judge whether it was a distraction
  or a blocker.

The file is gitignored on purpose. An agent appending raw, un-triaged findings to a public repository can
publish sensitive local paths or exploitable detail before anyone reviews them. Triage is what makes an
entry public, by promoting it.

## Triage - the only two outcomes

A SessionStart hook names the count and the oldest entry until the file is empty. To clear it, take each
entry and do exactly one of:

1. **PROMOTE** it to a tracked item with an owner and a slot - a `ROADMAP.md` entry, or a plan, or an
   immediate fix if it is cheap enough to just do. Then delete the line.
2. **DELETE** it with a recorded reason - it was wrong, it was already fixed, it does not meet the bar,
   or it is a duplicate. Say which, in the commit message or to the owner.

**There is no third outcome. Nothing may sit "acknowledged" or "noted".** A parked state is how a list of
surfaced-but-untracked findings forms in the first place, which is the failure this skill exists to end.
An entry that is real but not worth doing now is PROMOTED as tracked debt, not left in the file.

Severity is assigned here, at triage, by the owner - not at capture by the agent that was interrupted.

## Scope boundary

This skill is the CAPTURE half. What happens to a defect once tracked - that a defect's age is never a
disposition, that a verified pre-existing defect earns a planned fix rather than a mention - is the
disposition half, and belongs to AGY-SCOPE.
```

- [ ] **Step 2: Verify the skill lints**

Run: `pwsh -File scripts/check-agy-discipline-skills.ps1`
Expected: exit 0. **The skill must NOT be added to that script's `$skills` array** — it emits no
`[VERDICT:]` tokens and the linter fails loud for an enrolled skill with no verdict mapping.

- [ ] **Step 3: Commit**

```bash
git add clavity-dotnet/plugin/skills/open-issues/SKILL.md
git commit -m "feat(anomalies): open-issues skill - the capture bar and the triage procedure

Carries the wording negotiated with the agy peer: capture any reachable code
defect, tool misbehavior, or operational blocker that actively degrades or
prevents the workflow. Wide enough for a truncating tool or a test gate that
outgrew its timeout; narrow enough to exclude style opinions.

States plainly that the spotter WRITES rather than reports, because the measured
loss is at summarization, not at noticing."
```

---

### Task 3: Register the hook in both plugins and mirror everything

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/hooks.json`
- Modify: `clavity-classic/plugin/hooks/hooks.json`
- Create: `clavity-classic/plugin/hooks/agy-anomaly-reminder.sh` (copy)
- Create: `clavity-classic/plugin/skills/open-issues/SKILL.md` (copy)

**Do NOT start until Tasks 1 and 2 are committed.**

- [ ] **Step 1: Add the SessionStart registration to the dotnet manifest**

In `clavity-dotnet/plugin/hooks/hooks.json`, the `SessionStart` array currently holds one matcher object
whose `hooks` array has a single entry for `agy-liveness-check.sh`. Add a second entry to that SAME
`hooks` array, AFTER the liveness entry, so the block reads:

```json
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-liveness-check.sh\"" },
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-anomaly-reminder.sh\"" }
        ]
      }
    ]
```

- [ ] **Step 2: Add the same registration to the classic manifest**

`clavity-classic/plugin/hooks/hooks.json` legitimately differs here: its `SessionStart` `hooks` array
already holds TWO entries, `agy-drive-session-reset.sh` first and `agy-liveness-check.sh` second. Append
the anomaly reminder as the THIRD entry, preserving the existing two and their order:

```json
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-drive-session-reset.sh\"" },
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-liveness-check.sh\"" },
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-anomaly-reminder.sh\"" }
        ]
      }
    ]
```

**Known limit, state it rather than assume CI covers it:** `scripts/check-seed-artifacts-synced.sh`
compares the `PostToolUse` and `PreToolUse` blocks across the two manifests but deliberately does NOT
compare `SessionStart`, because classic carries a variant-specific reset hook there. So these two
registrations are review-enforced, not gate-enforced. If one is later removed, nothing fails.

- [ ] **Step 2b: Verify both manifests are still valid JSON**

Run:
```bash
jq -e . clavity-dotnet/plugin/hooks/hooks.json >/dev/null && echo DOTNET-OK
jq -e . clavity-classic/plugin/hooks/hooks.json >/dev/null && echo CLASSIC-OK
jq -r '.hooks.SessionStart[].hooks[].command' clavity-dotnet/plugin/hooks/hooks.json
jq -r '.hooks.SessionStart[].hooks[].command' clavity-classic/plugin/hooks/hooks.json
```
Expected: `DOTNET-OK`, `CLASSIC-OK`, then 2 commands for dotnet and 3 for classic, anomaly last in each.

- [ ] **Step 3: Mirror the hook and the skill byte-identically**

```bash
mkdir -p clavity-classic/plugin/skills/open-issues
cp clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh clavity-classic/plugin/hooks/agy-anomaly-reminder.sh
cp clavity-dotnet/plugin/skills/open-issues/SKILL.md    clavity-classic/plugin/skills/open-issues/SKILL.md
diff -q clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh clavity-classic/plugin/hooks/agy-anomaly-reminder.sh && echo HOOK-IDENTICAL
diff -q clavity-dotnet/plugin/skills/open-issues/SKILL.md    clavity-classic/plugin/skills/open-issues/SKILL.md && echo SKILL-IDENTICAL
```
Expected: `HOOK-IDENTICAL`, `SKILL-IDENTICAL`.

- [ ] **Step 4: Enrol both new pairs in the seed-sync gate**

In `scripts/check-seed-artifacts-synced.sh`, the `for rel in \` list currently ends with
`knowledge/agy-capabilities.md ; do`. Add the two new relative paths to that list. The skill line goes
with the other skills and the hook line with the other hooks, so the list reads:

```bash
for rel in \
  skills/adversarial-panel-review/SKILL.md \
  skills/agy-first/SKILL.md \
  skills/agy-capstone/SKILL.md \
  skills/agy-test-audit/SKILL.md \
  skills/open-issues/SKILL.md \
  hooks/agy-after-reminder.sh \
  hooks/agy-seam-inject.sh \
  hooks/agy-test-audit-reminder.sh \
  hooks/agy-liveness-check.sh \
  hooks/agy-anomaly-reminder.sh \
  knowledge/agy-assumptions.md \
  knowledge/agy-capabilities.md ; do
```

**Paste the list COMPLETE as above — do not abbreviate any existing entry.** Dropping one would silently
stop checking a pair that is currently gated.

- [ ] **Step 5: Prove the enrolment actually gates**

This is the non-vacuous check on Step 4. Run:
```bash
just seed-sync-check && echo "GREEN as expected"
printf '\n# deliberate drift\n' >> clavity-classic/plugin/hooks/agy-anomaly-reminder.sh
just seed-sync-check ; echo "exit=$? (expect NON-zero and a SEED-DRIFT line naming agy-anomaly-reminder.sh)"
git checkout clavity-classic/plugin/hooks/agy-anomaly-reminder.sh
just seed-sync-check && echo "GREEN again after restore"
```
Expected: green, then a failure naming `hooks/agy-anomaly-reminder.sh`, then green. If the middle run
passes, the enrolment did not take and that is the bug to fix.

- [ ] **Step 6: Run the full gate**

Run: `just test-scripts`
**Run this with `run_in_background` and read the result from the task output file — it exceeds the 600s
foreground tool cap** (measured: ~566s at 332 tests, and the suite is larger now).
Expected: `Failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add clavity-dotnet/plugin/hooks/hooks.json clavity-classic/plugin/hooks/hooks.json clavity-classic/plugin/hooks/agy-anomaly-reminder.sh clavity-classic/plugin/skills/open-issues/SKILL.md scripts/check-seed-artifacts-synced.sh
git commit -m "feat(anomalies): register the reminder in both drivers and enrol the new seed pairs

The SessionStart registration is review-enforced, not gate-enforced: seed-sync
compares the PostToolUse and PreToolUse blocks but deliberately not SessionStart,
because clavity-classic carries a variant-specific reset hook there.

The hook FILE and the skill are enrolled in the byte-identical list, and the
enrolment was verified non-vacuous by introducing deliberate drift and confirming
the gate names the new file."
```

---

### Task 4: Seed the file with this session's real anomalies, and record the scope split

**Files:**
- Create: `.clavity/local-anomalies.md` (gitignored — will NOT appear in git status)
- Modify: `clavity-dotnet/ROADMAP.md`

**Do NOT start until Task 3 is committed.**

- [ ] **Step 1: Seed the capture file with the three measured anomalies**

These are real, from this session, and they are what the mechanism was built for. Run:

```bash
mkdir -p .clavity
[ -f .clavity/.gitignore ] || printf '%s\n' '*' > .clavity/.gitignore
printf '%s\n\n' '# Untriaged anomalies (local, never committed)' > .clavity/local-anomalies.md
{
printf -- '- [tool] agy_look truncates the NEWEST reply out of a long cascade, so the answer just requested is the one that cannot be read back; recovery costs a second write that consumes quota * n/a * 2026-08-01 * task=phase-b-capstone\n'
printf -- '- [process] just test-scripts grew past the 600s tool cap, so no agent can run the repo gate in the foreground any more * justfile:91 * 2026-08-01 * task=phase-b-capstone\n'
printf -- '- [process] a dispatched subagent wrote to a file outside the set it was told to touch * n/a * 2026-08-01 * task=productize-T8\n'
} >> .clavity/local-anomalies.md
cat .clavity/local-anomalies.md
```

- [ ] **Step 2: Verify the hook now fires on the real file**

Run:
```bash
printf '{"cwd":"%s","source":"startup"}' "$(pwd)" | bash clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh ; echo "exit=$?"
```
Expected: one `[AGY-ANOMALIES] 3 untriaged (oldest 2026-08-01) ...` line on stderr and `exit=2`.

- [ ] **Step 3: Record the capture/disposition split in ROADMAP section 7**

`clavity-dotnet/ROADMAP.md` section `### 7.` is the AGY-SCOPE brainstorming item. Insert the following
paragraph at the END of that section, immediately BEFORE the `### 8.` heading. Do not alter any other
text in section 7, and do not touch section 8.

```markdown
**Update 2026-08-01 - the CAPTURE half is now built and shipped.** An anomaly an agent spots while doing
something else lands in a gitignored `.clavity/local-anomalies.md` written by the spotter itself, and a
SessionStart hook counts the untriaged entries and demands triage until the file is empty (see the
`open-issues` skill). Design converged with the agy peer over an AGY-FIRST consult plus two negotiation
rounds. What remains for AGY-SCOPE is therefore only the DISPOSITION half: that a defect's age is never a
disposition, and that a verified pre-existing defect earns a tracked plan rather than a mention. The five
open design questions above are unchanged; they were always disposition questions.
```

- [ ] **Step 4: Commit**

```bash
git add clavity-dotnet/ROADMAP.md
git commit -m "docs(roadmap): AGY-SCOPE now needs only the disposition half

The capture half shipped: gitignored anomalies file written directly by the
spotter, plus a SessionStart hook that counts and demands triage. AGY-SCOPE's
five open design questions were always disposition questions and are unchanged."
```

**Note:** `.clavity/local-anomalies.md` is gitignored (`.gitignore:45`) and is deliberately NOT committed
in this step. It is local runtime state. Do NOT `git add -f` it.

---

## Self-review

**Spec coverage.** Every element of the converged design maps to a task: gitignored location (Task 4
Step 1, `.gitignore:45` verified in Task 1 Step 0); spotter writes directly (Task 2, the skill's Capture
section); zero severity at capture (Task 2, stated explicitly, no severity field in the format); the
reminder counts and demands triage (Task 1, tested by `REPORTS the count and demands triage`); exactly two
exits with no parked state (Task 2, the Triage section); merge with AGY-SCOPE (Task 4 Step 3).

**Known limits, stated rather than papered over.**
1. The SessionStart registrations are review-enforced, not gate-enforced (Task 3 Step 2).
2. Nothing verifies that an agent actually captured an anomaly it noticed. Compliance with *noticing* is
   unfalsifiable - an agent can always assert it saw nothing. This ships an honest record, not a gate.
3. The hook fires once per session. It cannot force triage mid-session; it can only make the count
   impossible to miss at the next boot.

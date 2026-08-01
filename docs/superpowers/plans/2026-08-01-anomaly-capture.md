# Anomaly capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An anomaly an agent notices while doing something else lands in a durable local file the moment it is spotted, and a SessionStart hook keeps naming it until it is either promoted to a tracked ROADMAP item or deleted with a reason.

**Architecture:** Three shipped artifacts per driver plugin — a capture FORMAT (a one-line markdown bullet appended to a gitignored file), a SessionStart REMINDER hook that counts untriaged entries and demands triage, and an `open-issues` SKILL carrying the capture bar, the dispatch clause and the triage procedure. A subagent REPORTS what it noticed under a fixed heading; the driver VERIFIES each claim by measurement and WRITES the verified ones to the file BEFORE summarizing — because that summary is where anomalies measurably died, and because an unverified claim written straight to the file is pollution nobody checks.

**Tech Stack:** bash (hook, jq-dependent, pure ASCII), Pester 5 (tests), markdown (skill + capture file), JSON (hooks.json registration).

---

## Design provenance (do not re-litigate these; they are settled)

This plan implements the design in the operator's memory at `project_anomaly-capture-design.md`, converged
through an AGY-FIRST consult plus **two** AGY-NEGOTIATE rounds with real position changes on both sides.
Settled and NOT open for reinterpretation during execution:

- **Gitignored location.** An agent appending RAW un-triaged defects to a PUBLIC repo can publish
  sensitive local paths before the owner sees them. `.clavity/` is already ignored (`.gitignore:45`).
- **The subagent REPORTS; the driver VERIFIES; the driver WRITES.** *(Owner ruling, 2026-08-01, overriding
  an earlier converged design in which the spotter wrote directly.)* The loss is at SUMMARIZATION —
  measured: three real anomalies in one session were all reported by their spotter and nearly died when
  the driver compressed the report. Direct writes closed that, but by deleting the only step that checks
  anything: a subagent report is a CLAIM, and in this very session one such claim was confirmed by
  measurement and fixed while another was refuted by measurement and discarded. Both would have landed in
  the file, indistinguishable. The loss is therefore closed by requiring the driver to **capture before
  summarizing**, not by bypassing the driver.
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
| `clavity-{dotnet,classic}/plugin/hooks/agy-seam-inject.sh` | Task 5: inject the dispatch clause at the seams where dispatching starts |
| `scripts/tests/agy-seam-inject.Tests.ps1` | Task 5: coverage for the new seam arm |
| `clavity-dotnet/ROADMAP.md` | record that §7 now needs only the disposition half |

**The FEED side and the DRAIN side are separate artifacts and both are required.** Task 1's hook only
counts what is already there; Task 5 is what causes anything to be there at all. Building either alone
produces a mechanism that looks complete and does nothing.

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

    It 'finds the file at the repo ROOT when cwd is a SUBDIRECTORY' {
        # A spotter that had cd'd into a subdirectory writes to the repo root. If this hook looked only at
        # the payload cwd it would report zero while a real anomaly sat captured and invisible.
        $repo = New-TempRepo; $h = New-CleanHome
        try {
            New-Item -ItemType Directory -Path (Join-Path $repo '.clavity') -Force | Out-Null
            Set-Content (Join-Path $repo '.clavity/local-anomalies.md') "# Untriaged anomalies`n`n- [defect] y * a.cs:1 * 2026-07-20 * task=z" -Encoding ascii
            $sub = Join-Path $repo 'scripts/deep'
            New-Item -ItemType Directory -Path $sub -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $sub) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match '1 untriaged'
        } finally { Remove-Item $repo,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'finds the file under the payload cwd when it is NOT at the git root' {
        # The case the second candidate exists for, and the only arrangement that can observe it: the repo
        # ROOT has no anomalies file, but the payload cwd (a subdirectory) does. Reachable when a spotter
        # without git on PATH captured via its $PWD fallback while cd'd into a subdirectory. A fixture
        # where root and cwd coincide would pass with or without the fallback and prove nothing.
        $repo = New-TempRepo; $h = New-CleanHome
        try {
            $sub = Join-Path $repo 'scripts/deep'
            New-Item -ItemType Directory -Path (Join-Path $sub '.clavity') -Force | Out-Null
            Set-Content (Join-Path $sub '.clavity/local-anomalies.md') "# Untriaged anomalies`n`n- [defect] y * a.cs:1 * 2026-07-20 * task=z" -Encoding ascii
            Test-Path (Join-Path $repo '.clavity/local-anomalies.md') | Should -BeFalse
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $sub) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match '1 untriaged'
        } finally { Remove-Item $repo,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'counts an entry whose type is Title-Case or multi-word' {
        # A sloppy type is still a real anomaly. A stricter [a-z] pattern would count these as zero and
        # silently discard exactly what the hook exists to surface.
        $w = New-Workspace @(
            '- [Defect] title-cased type * a.cs:1 * 2026-07-20 * task=z',
            '- [tool misbehavior] multi-word type * n/a * 2026-07-21 * task=z'
        )
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match '2 untriaged'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reads the date from its FIELD, ignoring a date written in the prose' {
        # Scanning the whole line for an ISO date would pick the prose date and report an age that is a lie.
        $w = New-Workspace @('- [defect] API truncates messages from 2024-01-01 format * a.cs:1 * 2026-08-01 * task=z')
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.StdErr | Should -Match '2026-08-01'
            $r.StdErr | Should -Not -Match '2024-01-01'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'still reads the date when the task field itself contains a separator' {
        # Counting fields from the right broke here: a ' * ' inside task= shifts NF and $(NF-1) lands on a
        # fragment of the task, silently dropping that entry's date.
        #
        # ORDER IS THE ASSERTION. The entry with the separator in its task must carry the OLDER date. With
        # it newer, the other entry supplies the same "oldest" either way and the test passes against the
        # broken form -- which is exactly how the first version of this test was vacuous. The second entry
        # also keeps a ' * ' in its FACT, proving that case stayed safe.
        $w = New-Workspace @(
            '- [defect] x * a.cs:1 * 2026-07-11 * task=investigating * timeout',
            '- [tool] a * b thing * n/a * 2026-08-01 * task=z'
        )
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match '2 untriaged'
            $r.StdErr   | Should -Match '2026-07-11'
            $r.StdErr   | Should -Not -Match '2026-08-01'
        } finally { Remove-Item $w,$h -Recurse -Force -ErrorAction SilentlyContinue }
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

# Resolve the REPOSITORY ROOT the same way the capture snippet does, so both sides always agree. A
# spotter that had cd'd into a subdirectory writes to the root; if this hook looked only at the payload
# cwd it would miss an anomaly that was captured correctly. Fall back to cwd outside a git worktree.
root=$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
[ -n "$root" ] || root="$cwd"

# Check the payload cwd as a SECOND candidate. Outside a git worktree the two sides fall back to
# different defaults -- this hook to the session's cwd, the capture snippet to the spotter's own $PWD --
# and a file written under one would be invisible to the other. Trying both closes the common case at the
# cost of one extra stat. RESIDUAL LIMIT, stated rather than papered over: in a NON-git directory whose
# spotter had cd'd into a SUBdirectory, the capture lands somewhere neither path names and this hook will
# not see it. Inside a git worktree -- which is every case this plugin actually ships into -- both sides
# resolve to the same toplevel and the ambiguity does not arise.
f="$root/.clavity/local-anomalies.md"
[ -f "$f" ] || f="$cwd/.clavity/local-anomalies.md"
[ -f "$f" ] || exit 0

# An ENTRY is a bullet whose first token is ANY bracketed word: "- [defect] ...". Prose, headings and
# plain bullets are not entries, so the file's own preamble cannot inflate the count. The bracket content
# is deliberately NOT restricted to [a-z]: an agent that writes "[Defect]" or "[tool misbehavior]" has
# still captured a real anomaly, and a stricter pattern would count it as zero -- silently discarding the
# very thing this hook exists to surface. Triage can correct a sloppy type; it cannot recover a dropped one.
#
# Present-but-unreadable is NOT "no anomalies", and it is detected from grep's EXIT CODE rather than from
# a `[ -r "$f" ]` test. MEASURED on Windows Git Bash: the shell's -r builtin does NOT consult Windows ACLs
# and calls an ACL-denied file readable, so an -r guard never fires there; the read then fails inside grep,
# the count coerces to zero, and the hook exits silently -- the exact indistinguishable-empty-result this
# hook exists to prevent, reintroduced by the guard meant to prevent it. grep's contract is POSIX and
# platform-independent: 0 = matched, 1 = matched nothing, anything greater = error.
n=$(grep -c '^- \[[^]]*\]' "$f" 2>/dev/null)
rc=$?
if [ "$rc" -gt 1 ]; then
  printf '%s\n' "[AGY-ANOMALIES] $f exists but cannot be read - untriaged anomalies NOT counted" >&2
  exit 2
fi
[ -z "$n" ] && n=0
[ "$n" -eq 0 ] && exit 0

# Read the capture date from its FIELD, not from anywhere on the line. The format is
#   - [type] fact * where * DATE * task=...
# so the date is the field before the last. Scanning the whole line for an ISO date would pick up a date
# written inside the prose ("truncates messages from 2024-01-01 format") and report an age that is a lie.
# The separator is written as a CHARACTER CLASS, ' [*] ', not as an escaped ' \* '. MEASURED: the escaped
# form makes awk warn "escape sequence \* treated as plain *" and emit garbage instead of the field, so
# the date silently comes back empty. The class form has no escaping ambiguity.
# Anchor on the task= field and take the one before it, rather than counting from either end. MEASURED:
# counting from the LEFT breaks when the fact contains " * "; counting from the RIGHT with $(NF-1) breaks
# when the task does ("task=investigating * timeout" silently yields no date). Anchoring survives both,
# because task= is the only field with a fixed marker.
oldest=$(grep '^- \[[^]]*\]' "$f" 2>/dev/null \
  | awk -F' [*] ' '{ for (i=1; i<=NF; i++) if ($i ~ /^task=/) { print $(i-1); break } }' \
  | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort | head -1)
[ -n "$oldest" ] && oldest=" (oldest $oldest)"

# Name the RESOLVED path, not a relative one. The reader may have started the session in a subdirectory,
# and a notice that says ".clavity/local-anomalies.md" sends them to a path that does not exist from where
# they are standing -- at exactly the moment they are least inclined to go hunting for it.
printf '%s\n' "[AGY-ANOMALIES] $n untriaged$oldest in $f. Triage before new work: each entry is either PROMOTED to a tracked ROADMAP item with an owner, or DELETEd with a recorded reason. There is no parked state. Use the open-issues skill." >&2
exit 2
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-anomaly-reminder.Tests.ps1 -Output Detailed -CI"`
Expected: `Failed: 0`, 15 blocks passing.

- [ ] **Step 5: Mutation-check each guard**

One at a time, apply the mutation, re-run ONLY this test file, confirm the NAMED test goes red, then restore. Record each result. **A guard whose removal leaves the file green is not a guard — report it rather than papering over it.**

Every mutation below is applied **to the hook**, never to a test.

| Mutation (in `agy-anomaly-reminder.sh`) | Test that must go red |
|---|---|
| Change `sort \| head -1` to `sort -r \| head -1` | `names the OLDEST entry date, not the newest` |
| Change the count grep `'^- \[[^]]*\]'` to `'^- '` | `counts ONLY entry bullets, not prose or headings in the file` |
| Delete the `[ -f "$cwd/.no-agy" ]` term from the kill-switch condition | `is SILENT under a workspace .no-agy kill-switch` |
| Delete the `[ -f "$HOME/.claude/.no-agy" ]` term from the same condition | `is SILENT under a global $HOME/.claude/.no-agy kill-switch` |
| Delete the `[ -f "$f" ] \|\| exit 0` line | `is SILENT (exit 0) when the anomalies file does not exist` |
| Delete the whole `if ! command -v jq` guard | `warns ONCE (exit 2) when jq is absent rather than failing silently` |
| Delete the `if [ "$rc" -gt 1 ]` unreadable guard | `REPORTS an unreadable anomalies file rather than counting zero` |
| Delete the `.no-agy` check INSIDE the jq-missing branch | `is SILENT when jq is absent AND .no-agy is set` |
| Replace the `git rev-parse --show-toplevel` resolution with `root="$cwd"` | `finds the file at the repo ROOT when cwd is a SUBDIRECTORY` |
| Tighten the entry pattern `'^- \[[^]]*\]'` back to `'^- \[[a-z]*\]'` | `counts an entry whose type is Title-Case or multi-word` |
| Replace the field-anchored `awk` date read with a whole-line `grep -oE` for an ISO date | `reads the date from its FIELD, ignoring a date written in the prose` |
| Delete the `[ -f "$f" ] \|\| f="$cwd/.clavity/local-anomalies.md"` second candidate | `finds the file under the payload cwd when it is NOT at the git root` |

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

## Who writes - the driver, after verifying

**A subagent REPORTS; the driver VERIFIES; the driver WRITES.** Owner ruling, and it overrides an earlier
converged design in which the spotter wrote to the file directly.

The reasoning is worth keeping visible, because the earlier design was not silly - it was solving a real
failure and traded away something more valuable to do it:

- Anomalies were being lost at SUMMARIZATION. A subagent reported one, the driver compressed a long report
  into a short answer, and the observation evaporated. Letting the spotter write directly closed that.
- But it closed it by removing the only step that ever checks anything. A subagent's report is a CLAIM, not
  evidence. Measured repeatedly in practice: a claimed anomaly turned out to be real and got fixed; a
  confidently-argued one turned out to be false and was refuted by measurement. Direct writes would have
  put both in the file, indistinguishable, with nobody looking.
- So the loss is not fixed by bypassing the driver. It is fixed by requiring the driver to CAPTURE BEFORE
  SUMMARIZING. That keeps the verification step and still closes the hole, because the hole was
  summarizing without capturing.

**If you are a subagent:** report anomalies in your final message under a heading of their own, so they
survive being skimmed. Do not write to the anomalies file. Do not judge severity. Do not stop your task
for it.

**If you are the driver receiving that report:** for each claimed anomaly, verify it by measurement before
recording anything - open the file, run the command, reproduce the behaviour. Then:

- **verified** -> capture it with the snippet below, BEFORE you write your summary to the user;
- **refuted** -> do not capture it, and say plainly in your summary that you checked and it did not hold;
- **cannot be checked cheaply** -> capture it with the fact stated as a claim (`reported, unverified:`)
  rather than dropping it, and let triage decide.

Capturing is not optional once something is verified. A verified anomaly that only appears in a chat
message is exactly the failure this whole mechanism exists to end.

Run this, filling the four fields:

```bash
# Resolve the REPOSITORY ROOT, never a relative path. Whoever runs this may be cd'd into a subdirectory,
# and a relative path would write scripts/.clavity/local-anomalies.md, which the SessionStart hook never
# looks at: durably recorded and permanently invisible, the exact opposite of the point. The hook resolves
# the root the same way, so both sides always agree.
R=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
F="$R/.clavity/local-anomalies.md"
mkdir -p "$R/.clavity"
# Self-ignoring directory. This makes .clavity/ invisible to git REGARDLESS of the host repository's own
# .gitignore, which matters because this plugin ships to repositories whose .gitignore we do not control.
# Without it, the "capture is private" property holds only in the repo where it was written.
#
# CHECKED ON EVERY CAPTURE, deliberately NOT nested inside the file-exists branch below. If it only ran
# when creating the file for the first time, then any later loss of the .gitignore -- someone deletes it,
# `git clean -Xdf` removes it, the file was created by hand -- would leave the anomalies file visible to
# git forever after, and the next `git add .` would publish a list of un-triaged defects. Re-asserting the
# shield costs one stat per capture.
[ -f "$R/.clavity/.gitignore" ] || printf '%s\n' '*' >> "$R/.clavity/.gitignore"
# The header uses >> and NEVER >. MEASURED: with >, two writers that both see no file destroy each other's
# work -- the first writes the header and appends its anomaly, the second's > truncates the file before
# appending its own, and the first anomaly is gone. Under the report-then-verify flow the concurrent
# writers are no longer subagents but two SESSIONS open on the same repository, which is ordinary. A
# mechanism whose entire purpose is not losing things must not have a path that silently eats one. With >>
# the worst case is a duplicate header, cosmetic and uncounted by the entry pattern; both survive.
[ -f "$F" ] || printf '%s\n\n' '# Untriaged anomalies (local, never committed)' >> "$F"
printf -- '- [%s] %s * %s * %s * task=%s\n' \
  'defect' 'one line stating the fact' 'path/file.ext:LINE' "$(date +%F)" 'what you were doing' >> "$F"
```

**Use exactly one of `defect`, `tool`, `process` as the type, lowercase, one word.** Not `[Defect]`, not
`[tool misbehavior]`. The hook tolerates other bracketed tokens when counting, but the three types are
what the triage procedure sorts on, so an invented type makes the entry harder to act on.

**Keep the four ` * ` separators.** The hook reads the capture date from the field before `task=`, by
position. An entry missing a separator still counts, but its age cannot be read.

Two things about that snippet are deliberate:

- **The `.clavity/.gitignore` containing `*` is load-bearing, not tidiness.** The decision to keep capture
  private rests on the directory being ignored. In this repository that happens to be true anyway; in a
  user's repository it is true only because of this file.
- **Append with `>>` and a single `printf`.** Two sessions can be open on the same repository at once. A
  single short append is atomic on POSIX, so concurrent writers interleave lines rather than corrupting
  them. Do not read-modify-write the file to add an entry.

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

**This step must APPEND, never truncate.** An earlier draft opened the file with `>`, which would have
silently destroyed any anomaly captured between the hook shipping and this step running — the task meant
to establish the file would have been the thing that emptied it. The header is written only if the file
does not already exist.

```bash
mkdir -p .clavity
[ -f .clavity/.gitignore ] || printf '%s\n' '*' >> .clavity/.gitignore
[ -f .clavity/local-anomalies.md ] || printf '%s\n\n' '# Untriaged anomalies (local, never committed)' >> .clavity/local-anomalies.md
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

### Task 5: Make a subagent actually capture (the activation path)

**Files:**
- Modify: `clavity-dotnet/plugin/skills/open-issues/SKILL.md`
- Modify: `clavity-dotnet/plugin/hooks/agy-seam-inject.sh` (then mirror both to classic)
- Modify: `scripts/tests/agy-seam-inject.Tests.ps1`

**Do NOT start until Tasks 1-3 are committed.**

**Why this task exists.** Tasks 1-4 build the file, the reminder, the skill and the seed — and a
dispatched subagent still never writes anything, because nothing puts the capture instruction in front of
it. A subagent reads a skill only if it invokes one, and a subagent told "implement this hook" will never
think to invoke an anomaly-capture skill. The reminder hook is the DRAIN side; this is the missing FEED
side. Without it the whole mechanism is a very well-tested empty file.

This gap survived a GREEN panel because the plan never described a dispatch path, and a reviewer cannot
audit an activation path that no text mentions. Absence of text is the one defect class a document review
structurally cannot see.

- [ ] **Step 0: State verification**

Confirm each; if any differs, STOP and report `STATE_MISMATCH: <what>`:
1. `clavity-dotnet/plugin/hooks/agy-seam-inject.sh` line 38 begins `case "$skill" in` and its arms are
   `*finishing-a-development-branch*)`, `*brainstorm*)`, `*)`.
2. The same file's jq-missing fallback (around lines 22-23) greps for BOTH seam names, and its header
   comment states it "degrades LOUD on a seam match (never a silent no-op)".
3. `scripts/tests/agy-seam-inject.Tests.ps1` defines `Invoke-Hook { param([string]$Skill, [string]$Cwd) }`
   returning `.StdOut`, and has 9 `It` blocks.

- [ ] **Step 1: Add the dispatch clause to the skill**

Insert this section into `clavity-dotnet/plugin/skills/open-issues/SKILL.md`, immediately BEFORE the
`## Triage - the only two outcomes` heading:

```markdown
## Dispatching a subagent - the clause every dispatch must carry

A subagent reports nothing useful unless its dispatch asks for it. It will not invoke this skill on its
own: it is focused on the task you gave it, and an anomaly is by definition not that task. So the
instruction has to travel IN the dispatch. Paste this into every implementer dispatch, in its
report-back section:

> **ANOMALIES.** If you notice something wrong that is NOT part of this task - a defect in adjacent code,
> a tool misbehaving, a process that cannot work - report it under a heading `## Anomalies noticed` at
> the END of your final message, one line each, in this shape:
>
> `- [defect|tool|process] one line stating the fact * path/file.ext:LINE or n/a * what you were doing`
>
> State it as a FACT you observed, with whatever makes it checkable - the command you ran, the file and
> line, the output you saw. Do NOT judge severity, do NOT stop your task to investigate, and do NOT write
> to any anomalies file yourself: your report is the channel, and whoever dispatched you will verify each
> one by measurement before recording it. If you noticed nothing, write `## Anomalies noticed` followed by
> `none` - an explicit none is worth more than silence, because silence is indistinguishable from not
> having looked.

**Why a heading and not a sentence in the prose.** A report gets skimmed. A dedicated heading with a
fixed shape survives skimming, and it makes an omission visible: a report with no such section is a
report that did not answer the question.

**The driver's obligation is the other half, and it is the half that historically failed.** Verify each
reported anomaly by measurement, then capture the verified ones with the snippet above BEFORE writing
your summary. The summary is where these die. Capturing after summarizing is capturing never.
```

- [ ] **Step 2: Add the seam arm to the auto-fire hook**

Three edits to `clavity-dotnet/plugin/hooks/agy-seam-inject.sh`.

**(a)** Extend the header comment's seam map (currently two lines) to three:

```bash
#   *brainstorm*                     -> AGY-FIRST   (marker agy-first.head)
#   *finishing-a-development-branch* -> AGY-CAPSTONE (marker agy-capstone.head)
#   *subagent-driven-development* / *executing-plans* -> ANOMALY-CAPTURE dispatch clause (no marker)
```

**(b)** Add the new seam to the jq-missing fallback so a jq-less machine still degrades LOUD rather than
silently skipping it. Replace the two-branch `if` (around lines 22-23) with:

```bash
  if printf '%s' "$input" | grep -Eq '"skill"[[:space:]]*:[[:space:]]*"[^"]*finishing-a-development-branch' \
     || printf '%s' "$input" | grep -Eq '"skill"[[:space:]]*:[[:space:]]*"[^"]*brainstorm' \
     || printf '%s' "$input" | grep -Eq '"skill"[[:space:]]*:[[:space:]]*"[^"]*subagent-driven-development' \
     || printf '%s' "$input" | grep -Eq '"skill"[[:space:]]*:[[:space:]]*"[^"]*executing-plans'; then
```

**(c)** Add the case arm and the emit. In the seam map, insert the new arm BEFORE the `*)` catch-all:

```bash
case "$skill" in
  *finishing-a-development-branch*)                  discipline="agy-capstone" ;;
  *brainstorm*)                                      discipline="agy-first" ;;
  *subagent-driven-development*|*executing-plans*)   discipline="anomaly-dispatch" ;;
  *)                                                 exit 0 ;;
esac
```

and add this arm to the `case "$discipline" in` block, after the `agy-capstone)` arm:

```bash
  anomaly-dispatch)
    emit 'ANOMALY-CAPTURE: you are about to dispatch subagents. TWO obligations, and the second is the one that historically fails. (1) EVERY implementer dispatch you write MUST carry the anomaly clause verbatim - it is in the `open-issues` skill under "Dispatching a subagent", short enough to paste inline. It asks the subagent to report anything wrong that is NOT its task under a `## Anomalies noticed` heading at the end of its final message, stated as a checkable fact, with an explicit `none` if it saw nothing. A subagent will not invoke that skill on its own, so the instruction has to travel IN the dispatch. (2) When a report comes back, VERIFY each claimed anomaly by measurement - open the file, run the command, reproduce it - and then APPEND the verified ones to .clavity/local-anomalies.md BEFORE you write your summary to the user. A subagent report is a claim, not evidence; and a verified anomaly that exists only in a chat message is lost the moment you compress that message. Capturing after summarizing is capturing never.' ;;
```

**Deliberately NOT marker-debounced.** The existing seams debounce on a HEAD-keyed marker that their
discipline skill writes after running. This seam has no discipline run and writes no marker, so the lookup
finds nothing and the directive injects every time. That is the intended cadence: these two skills are
invoked about once per plan execution, and a driver about to write several dispatches should be reminded
each time rather than once per commit.

- [ ] **Step 3: Add the tests**

Append these `It` blocks to `scripts/tests/agy-seam-inject.Tests.ps1`, before its final closing brace:

```powershell
    It 'injects the ANOMALY-CAPTURE dispatch directive on a subagent-driven-development seam' {
        $out = Invoke-Hook 'superpowers:subagent-driven-development'
        $out | Should -Match 'ANOMALY-CAPTURE'
        $out | Should -Match 'open-issues'
        $out | Should -Match 'local-anomalies'
    }

    It 'injects the same directive on an executing-plans seam' {
        $out = Invoke-Hook 'superpowers:executing-plans'
        $out | Should -Match 'ANOMALY-CAPTURE'
    }

    It 'does NOT inject the capstone directive on a subagent-driven-development seam' {
        # The personal, pre-plugin copy of this hook bound AGY-CAPSTONE to this seam. The shipped hook
        # binds the capstone to finishing-a-development-branch only, and this seam to the dispatch clause.
        # Pinning that keeps the two bindings from silently merging.
        $out = Invoke-Hook 'superpowers:subagent-driven-development'
        $out | Should -Not -Match 'AGY-CAPSTONE auto-fire'
    }

    It 'emits the LOUD jq-missing line on a subagent-driven-development seam when jq is absent' {
        $payload = @{ tool_input = @{ skill = 'superpowers:subagent-driven-development' }; cwd = '.' } | ConvertTo-Json -Compress
        $r = Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env @{ PATH = $script:NoJqPath; HOME = $script:CleanHome }
        $r.StdOut | Should -Match 'guard inactive'
    }
```

- [ ] **Step 4: Verify RED, then GREEN**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-seam-inject.Tests.ps1 -Output Detailed -CI"`
Before Step 2's edits: the four new blocks FAIL. After: `Failed: 0`, 13 blocks.

- [ ] **Step 5: Mutation-check the new arm**

Every mutation applied **to the hook**, never to a test.

| Mutation (in `agy-seam-inject.sh`) | Test that must go red |
|---|---|
| Delete the `*subagent-driven-development*\|*executing-plans*)` case arm | `injects the ANOMALY-CAPTURE dispatch directive...` |
| Drop `\|*executing-plans*` from that arm | `injects the same directive on an executing-plans seam` |
| Delete the two new `grep -Eq` terms from the jq-missing fallback | `emits the LOUD jq-missing line on a subagent-driven-development seam...` |
| Point the new arm at `discipline="agy-capstone"` | `does NOT inject the capstone directive...` |

Record each result. **A guard whose removal leaves the file green is not a guard — report it.**

- [ ] **Step 6: Mirror, sync-check, full gate**

```bash
cp clavity-dotnet/plugin/hooks/agy-seam-inject.sh clavity-classic/plugin/hooks/agy-seam-inject.sh
cp clavity-dotnet/plugin/skills/open-issues/SKILL.md clavity-classic/plugin/skills/open-issues/SKILL.md
diff -q clavity-dotnet/plugin/hooks/agy-seam-inject.sh clavity-classic/plugin/hooks/agy-seam-inject.sh && echo HOOK-IDENTICAL
diff -q clavity-dotnet/plugin/skills/open-issues/SKILL.md clavity-classic/plugin/skills/open-issues/SKILL.md && echo SKILL-IDENTICAL
just seed-sync-check
```
Both files are ALREADY enrolled in the seed-sync list (`agy-seam-inject.sh` from before this plan,
`open-issues/SKILL.md` by Task 3), so no enrolment edit is needed here — but the gate must be green.

Then run `just test-scripts` with `run_in_background` and read the result from the task output file; it
exceeds the 600s foreground cap.

- [ ] **Step 7: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-seam-inject.sh clavity-classic/plugin/hooks/agy-seam-inject.sh clavity-dotnet/plugin/skills/open-issues/SKILL.md clavity-classic/plugin/skills/open-issues/SKILL.md scripts/tests/agy-seam-inject.Tests.ps1
git commit -m "feat(anomalies): the FEED side - put the capture clause into every dispatch

Tasks 1-4 built the file, the reminder, the skill and the seed, and nothing ever
reached the file: a subagent reads a skill only if it invokes one, and one told
to implement a hook never thinks to invoke an anomaly-capture skill. The
reminder was the drain side with no feed.

The auto-fire hook now injects on subagent-driven-development and
executing-plans with the two obligations. Dispatches must ask the subagent to
report anomalies under a fixed heading with an explicit 'none'; the driver must
then verify each claim by measurement and append the verified ones BEFORE
summarizing. A subagent report is a claim, not evidence, and a verified anomaly
that lives only in a chat message dies at the next summary.

Deliberately not marker-debounced: there is no discipline run to mark, and a
driver about to write several dispatches should be reminded each time.

The gap survived a GREEN panel because the plan never described a dispatch path,
and a reviewer cannot audit an activation path no text mentions."
```

---

## Self-review

**Spec coverage.** Every element of the converged design maps to a task: gitignored location (Task 4
Step 1, `.gitignore:45` verified in Task 1 Step 0); subagent reports / driver verifies / driver writes
(Task 2's "Who writes" section and Task 5's dispatch clause — the owner ruling that replaced the earlier
spotter-writes-directly design, and the reason both a FEED task and a DRAIN task exist); the skill's Capture
section); zero severity at capture (Task 2, stated explicitly, no severity field in the format); the
reminder counts and demands triage (Task 1, tested by `REPORTS the count and demands triage`); exactly two
exits with no parked state (Task 2, the Triage section); merge with AGY-SCOPE (Task 4 Step 3).

**Known limits, stated rather than papered over.**
1. The SessionStart registrations are review-enforced, not gate-enforced (Task 3 Step 2).
2. Nothing verifies that an agent actually captured an anomaly it noticed. Compliance with *noticing* is
   unfalsifiable - an agent can always assert it saw nothing. This ships an honest record, not a gate.
   Three specific ways that bites, named rather than left implicit:
   - **A subagent can hardcode `## Anomalies noticed / none`** into its response template and satisfy the
     format without ever looking. The explicit `none` is still worth requiring — it makes an omission
     visible in the ordinary case, where the failure is forgetting rather than faking — but it is a
     prompt for honest effort, not a check on it.
   - **The driver can verify and then never capture.** That recreates precisely the loss-at-summarization
     failure the mechanism exists to end, and nothing detects it: an empty file is indistinguishable from
     a clean session. This is the single most likely way the whole thing quietly stops working.
   - **The driver can capture without verifying.** Then unverified claims accumulate and the owner pays
     the debunking cost at triage, which destroys the cheap-capture property the design was built around.
4. **The activation path has its own activation gap.** Task 5's seam fires from a `PreToolUse` hook with
   matcher `Skill`, so it only reaches a driver who actually INVOKES `subagent-driven-development` or
   `executing-plans`. A driver who dispatches subagents without invoking either skill never receives the
   clause, and the mechanism is silently bypassed for that whole session. There is no hook that fires on
   "about to write a dispatch". The backstop is the same one this project already uses for AGY-CAPSTONE:
   a durable rule in the operator's own instructions, which binds whether or not a skill was invoked. The
   hook raises the floor; it is not the guarantee.
3. The hook fires once per session. It cannot force triage mid-session; it can only make the count
   impossible to miss at the next boot.

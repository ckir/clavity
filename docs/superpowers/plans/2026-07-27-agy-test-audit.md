# AGY-TEST-EXHAUSTIVENESS-AUDIT Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship AGY-TEST-AUDIT as a standing, installed agy-discipline in the clavity plugin — a `SKILL.md` procedure plus a **marker-gated** branch-finish reminder hook that fires only *after* AGY-CAPSTONE reaches GREEN — with the full lint/seed-sync/test/doc guard-rails the existing disciplines have.

**Architecture:** The discipline follows the **decoupled Shape-B** packaging (AGY-FIRST consult 2026-07-27, owner-decided): parseable `[VERDICT:]` tokens + lifecycle-completion gate like `agy-capstone`, but with its **own** verdict vocabulary enforced by a **generalized per-skill** linter, and its **own** trigger — a separate `agy-test-audit-reminder.sh` (PostToolUse) that reads `.clavity/agy-marks/agy-capstone.head` and nudges only when capstone is GREEN-at-HEAD, the audit has not run at this HEAD, and the reviewed range touched executable code/tests. This sequences capstone→audit structurally without cramming a second discipline into the strict 1:1 `agy-seam-inject.sh` case statement.

**Tech Stack:** Bash hooks (Git Bash on Windows) emitting `hookSpecificOutput.additionalContext` JSON + exit 0; Pester (PowerShell) hook tests; a PowerShell lint script; jq; Markdown skill/spec/contract docs.

**Design source (assume correct; do NOT re-litigate):** `docs/superpowers/specs/2026-07-27-agy-test-exhaustiveness-audit-design.md` — panel-GREEN through 4 AGY-AFTER rounds, owner-approved for planning. This plan carries two spec **amendments** (Task 8) the AGY-FIRST consult surfaced and verified against code: (a) §3's "stderr + exit-2 advisory emission" is wrong for this repo — the real pattern is `hookSpecificOutput.additionalContext` + exit 0; (b) §4's "A hook cannot know the capstone is GREEN" is over-broad — true only for the PreToolUse-on-skill hook; a *marker-reading* PostToolUse hook CAN know, because `agy-capstone.head` is written ONLY on human-GREEN or a `round-cap` waiver (`docs/agy-disciplines-marker-contract.md:57`).

**Load-bearing-core note (spec §5 / panel E2):** the spec marks a *core* (point-at-diff → verify-each-gap → owner-scopes → close-non-vacuously) and treats the parseable-token schema, discarded-below-floor list, rolling-debt-file GC/merge mechanics, headless-emit, and capstone-invalidation loop as *refinements the plan right-sizes*. This plan builds the **full installed discipline** (skill + trigger + guards) because that is what makes it real and testable, and encodes the core procedure + the refinements that are cheap in the `SKILL.md`; it explicitly right-sizes the rolling-debt-file **garbage-collection** and further nudge-dedupe as documented, deferred refinements (Task 3, "Deferred refinements" note).

---

## File Structure

**Create (both mirrors, byte-identical):**
- `clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md` + `clavity-classic/plugin/skills/agy-test-audit/SKILL.md` — the discipline procedure.
- `clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh` + `clavity-classic/plugin/hooks/agy-test-audit-reminder.sh` — the marker-gated trigger.

**Create (repo scripts):**
- `scripts/tests/agy-test-audit-reminder.Tests.ps1` — Pester tests for the new hook.

**Modify:**
- `clavity-dotnet/plugin/hooks/hooks.json` + `clavity-classic/plugin/hooks/hooks.json` — register the new PostToolUse hook.
- `scripts/check-seed-artifacts-synced.sh` — add the two new shared artifacts to the byte-identical `for rel` list.
- `scripts/check-agy-discipline-skills.ps1` — generalize `$requiredVerdicts` to a per-skill hashtable; enroll `agy-test-audit`.
- `scripts/tests/check-agy-discipline-skills.Tests.ps1` — stage `agy-test-audit` in `New-ScratchRoot`; restructure the rejection `-ForEach` blocks to carry a per-skill verdict token.
- `docs/agy-disciplines-marker-contract.md` — extend the discipline enum + document the audit marker and the capstone-gate read.
- `docs/superpowers/specs/2026-07-27-agy-test-exhaustiveness-audit-design.md` — the two amendments above.

**Modify (OUTSIDE the repo — global user config, no git commit):**
- `~/.claude/CLAUDE.md` — a one-line rule-`1d` pointer + taxonomy update.

**Conventions to match (verified against current code):**
- Hooks emit `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"…"}}` on **stdout** then `exit 0` — never stderr/exit-2 (`clavity-dotnet/plugin/hooks/agy-after-reminder.sh:37-39`).
- Fail-open: any error → `exit 0`. `set +e` at top.
- jq guard: without jq, honor `.no-agy` first, then a field-bounded grep and — only on a real match — a LOUD hardcoded ASCII `[AGY-DISCIPLINES] guard inactive: missing jq …` line (`agy-after-reminder.sh:17-23`).
- `.no-agy` kill-switch: `$cwd/.no-agy` or `$HOME/.claude/.no-agy`.
- Pure ASCII (mojibake guard — this repo has hit corruption).
- Marker files: `.clavity/agy-marks/<discipline>.head`, cwd-relative, content = bare `git rev-parse HEAD` (`docs/agy-disciplines-marker-contract.md`).

---

## Task 1: Marker-gated reminder hook (`agy-test-audit-reminder.sh`) + Pester tests

The novel piece: a PostToolUse hook that sequences capstone→audit via the capstone marker. It emits the audit nudge **iff** all hold: (1) `agy-capstone.head` exists and `== HEAD`; (2) `agy-test-audit.head` is absent or `!= HEAD`; (3) the reviewed range touched executable-code/test paths; (4) not suppressed by `.no-agy`. Otherwise silent `exit 0`.

**Files:**
- Test: `scripts/tests/agy-test-audit-reminder.Tests.ps1`
- Create: `clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh`
- Create: `clavity-classic/plugin/hooks/agy-test-audit-reminder.sh` (byte-identical mirror)

- [ ] **Step 1: Write the failing Pester tests**

Create `scripts/tests/agy-test-audit-reminder.Tests.ps1`. It builds real temp repos, writes marker files, and commits code vs docs to exercise the diff-gate. Note the helper `New-TempRepo` (in `BashHookHelpers.ps1`) makes a repo with one empty `init` commit; these tests extend it by committing real files and writing markers.

```powershell
Describe 'agy-test-audit-reminder.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh'

        $bashDir = Split-Path -Parent (Get-GitBashOrThrow)                       # ...\Git\bin
        $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')   # ...\Git\usr\bin

        # A repo whose HEAD commit touched a code file, with capstone.head==HEAD and no audit marker:
        # the canonical FIRE state. Returns the repo dir (Windows path).
        function New-FiredRepo {
            param([string]$CodeFile = 'src/thing.cs', [switch]$DocsOnly)
            $dir = New-TempRepo
            $rel = if ($DocsOnly) { 'docs/notes.md' } else { $CodeFile }
            $full = Join-Path $dir $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            Set-Content -LiteralPath $full -Value 'x' -Encoding ascii
            & git -C $dir add -A
            & git -C $dir -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= commit -qm work
            $head = (& git -C $dir rev-parse HEAD).Trim()
            New-Item -ItemType Directory -Path (Join-Path $dir '.clavity/agy-marks') -Force | Out-Null
            return [pscustomobject]@{ Dir = $dir; Head = $head }
        }
        function Set-Marker { param($Dir, $Name, $Sha)
            Set-Content -LiteralPath (Join-Path $Dir ".clavity/agy-marks/$Name.head") -Value $Sha -NoNewline -Encoding ascii
        }
        function New-AuditPayload { param([string]$Cwd)
            @{ tool_name = 'Bash'; tool_input = @{ command = 'git commit' }; cwd = $Cwd } | ConvertTo-Json -Compress
        }
        $script:Cwd = { param($d) ($d -replace '\\','/') }
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
    It 'is SILENT when the capstone marker is absent (capstone not run/green)' {
        $r = New-FiredRepo
        try {
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir))
            $out.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'is SILENT when the capstone marker is STALE (!= HEAD)' {
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
    It 'emits a LOUD jq-missing line when it would fire but jq is absent' {
        $r = New-FiredRepo
        try {
            Set-Marker $r.Dir 'agy-capstone' $r.Head
            $out = Invoke-BashHook -HookPath $script:Hook -Payload (New-AuditPayload (& $script:Cwd $r.Dir)) -Env @{ PATH = $script:NoJqPath }
            $out.StdOut | Should -Match 'guard inactive: missing jq'
        } finally { Remove-Item $r.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'ships as pure ASCII' {
        ($([IO.File]::ReadAllBytes($script:Hook)) | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
    It 'is byte-identical to the clavity-classic mirror' {
        $classic = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'clavity-classic/plugin/hooks/agy-test-audit-reminder.sh'
        (Get-FileHash $script:Hook).Hash | Should -Be (Get-FileHash $classic).Hash
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-test-audit-reminder.Tests.ps1 -Output Detailed"`
Expected: FAIL — the hook file does not exist yet (`Get-FileHash`/`Invoke-BashHook` on a missing path errors; the ASCII/mirror `It`s error too). This confirms the tests bind to a real artifact.

- [ ] **Step 3: Write the hook (`clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh`)**

The jq-missing branch must reproduce the exact gate cheaply enough to avoid false LOUD lines: it re-derives capstone-marker-matches-HEAD with plain `git`/`cat`/`grep` (no jq needed for that), and only emits the LOUD line when the gate would otherwise fire. Without jq it cannot parse the payload's `cwd`, so it falls back to the process cwd (matching `agy-seam-inject.sh:20`).

```bash
#!/usr/bin/env bash
# AGY-TEST-AUDIT trigger (plugin-shipped). PostToolUse: after AGY-CAPSTONE reaches GREEN, nudge the
# test-exhaustiveness audit exactly once for this HEAD. Marker-gated (docs/agy-disciplines-marker-contract.md):
#   fire IFF  .clavity/agy-marks/agy-capstone.head   == HEAD   (capstone is GREEN at this HEAD)
#        AND  .clavity/agy-marks/agy-test-audit.head  != HEAD   (audit not yet run at this HEAD)
#        AND  the reviewed range touched executable code / test paths (spec 4: docs-only must not nudge)
# This SEQUENCES capstone->audit structurally (the capstone marker is written ONLY on human-GREEN or a
# round-cap waiver), without touching the strict 1:1 agy-seam-inject.sh case statement. The directive POINTS
# AT the agy-test-audit skill (which carries the procedure + per-transport clause), so this file is
# byte-identical across both driver plugins. It NEVER writes a marker (a hook fires before the consult and
# cannot know its outcome). Fail-open: any error -> exit 0. Suppressed by .no-agy (cwd or ~/.claude).
# Without jq it degrades LOUD only when the gate would fire (never a silent no-op, never a false alarm).
set +e
input=$(cat)

DIR_CONST=".clavity/agy-marks"

# Shared gate: given a cwd, echo "fire" iff capstone-green-at-HEAD AND audit-not-done AND code/test changed.
gate() {
  local cwd="$1" head cap aud base changed
  head=$(git -C "$cwd" rev-parse HEAD 2>/dev/null) || return 1
  [ -n "$head" ] || return 1
  cap=$(cat "$cwd/$DIR_CONST/agy-capstone.head" 2>/dev/null)
  [ "$cap" = "$head" ] || return 1                       # capstone not GREEN at this HEAD
  aud=$(cat "$cwd/$DIR_CONST/agy-test-audit.head" 2>/dev/null)
  [ "$aud" = "$head" ] && return 1                       # audit already ran at this HEAD
  # Reviewed range: merge-base with an integration ref, else this commit's own files (on-branch / no ref).
  base=$(git -C "$cwd" merge-base HEAD "${CLAVITY_AUDIT_BASE_REF:-origin/main}" 2>/dev/null)
  [ -z "$base" ] && base=$(git -C "$cwd" merge-base HEAD main 2>/dev/null)
  if [ -n "$base" ] && [ "$base" != "$head" ]; then
    changed=$(git -C "$cwd" diff --name-only "$base"..HEAD 2>/dev/null)
  else
    changed=$(git -C "$cwd" show --name-only --format= HEAD 2>/dev/null)
  fi
  # Executable-code / test path heuristic. Empty match -> silent (docs/config/spec-only range, spec 4).
  printf '%s\n' "$changed" | grep -Eq '\.(cs|fs|rs|ts|tsx|js|jsx|py|go|java|rb|c|h|cpp|hpp|sh|ps1)$' || return 1
  echo fire
}

# --- jq guard. jq parses stdin (cwd) + emits structured JSON. Without it: honor the kill-switch, then run
# the gate against the PROCESS cwd; ONLY when it would fire, emit a loud hardcoded ASCII line. ---
if ! command -v jq >/dev/null 2>&1; then
  if [ -f "./.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then exit 0; fi
  if [ "$(gate ".")" = "fire" ]; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[AGY-DISCIPLINES] guard inactive: missing jq - the AGY-TEST-AUDIT reminder will not fire after capstone green"}}'
  fi
  exit 0
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)

# Opt-out kill-switch (mirrors agy-after-reminder.sh).
if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  exit 0
fi

[ "$(gate "$cwd")" = "fire" ] || exit 0

emit() { jq -n -c --arg ctx "$1" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'; }
emit 'AGY-TEST-AUDIT auto-fire: AGY-CAPSTONE is GREEN at this HEAD and the branch changed executable code/tests. BEFORE you declare the branch done, invoke the `agy-test-audit` skill to convene the live agy peer to audit the TEST SUITES for coverage exhaustiveness (untested reachable behaviours, vacuous/weak assertions, missing edge cases) - the orthogonal question the capstone does NOT ask. Load-bearing posture (the skill carries the full procedure and your driver'"'"'s transport): point the peer at the diff'"'"'s real test+source files by filepath (never a pasted summary); VERIFY every claimed gap BY MEASUREMENT before folding (the peer over-counts and states false gaps with confidence); the OWNER scopes which gaps to close; the driver authors each test and proves it NON-VACUOUS with a logic mutant; log deferred gaps as tracked debt. End with exactly one ASCII [VERDICT] token. If closing a gap needs an implementation-source refactor, that invalidates the capstone GREEN - re-run AGY-CAPSTONE. If the peer is unreachable, halt-and-ask or abort `[VERDICT: agy-required-but-unreachable]` - never a silent pass.'
exit 0
```

- [ ] **Step 4: Mirror the hook to clavity-classic**

Copy the exact bytes to `clavity-classic/plugin/hooks/agy-test-audit-reminder.sh` (the file is transport-agnostic — it points at the skill, which resolves transport — so it is byte-identical, enforced by the mirror test in Step 1 and by seed-sync in Task 6).

Run: `cp clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh clavity-classic/plugin/hooks/agy-test-audit-reminder.sh`

- [ ] **Step 5: Run the tests to verify they pass**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-test-audit-reminder.Tests.ps1 -Output Detailed"`
Expected: PASS (all `It`s green, including the byte-identical-mirror and pure-ASCII checks).

- [ ] **Step 6: Commit**

```bash
git add -f scripts/tests/agy-test-audit-reminder.Tests.ps1 \
  clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh \
  clavity-classic/plugin/hooks/agy-test-audit-reminder.sh
git commit -m "feat(agy-test-audit): marker-gated capstone->audit reminder hook + tests"
```

---

## Task 2: Register the hook in `hooks.json` (both mirrors)

The new hook is PostToolUse. Register it in BOTH plugin manifests. The seed-sync guard compares `jq -S '.hooks.PostToolUse'` across both plugins (`scripts/check-seed-artifacts-synced.sh:29-33`), so the PostToolUse arrays must match byte-for-byte after jq-sort — i.e. both plugins get the identical additional entry.

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/hooks.json`
- Modify: `clavity-classic/plugin/hooks/hooks.json`

- [ ] **Step 1: Add the PostToolUse entry to the dotnet manifest**

In `clavity-dotnet/plugin/hooks/hooks.json`, the `PostToolUse` array currently holds one entry (matcher `Write|Edit` → `agy-after-reminder.sh`). Add a second entry with matcher `Bash|Write|Edit` (broad enough to catch the driver's post-capstone commits/edits, so the nudge surfaces promptly). New `PostToolUse` array:

```json
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-after-reminder.sh\"" }
        ]
      },
      {
        "matcher": "Bash|Write|Edit",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-test-audit-reminder.sh\"" }
        ]
      }
    ],
```

- [ ] **Step 2: Apply the identical change to the classic manifest**

Make the SAME edit to `clavity-classic/plugin/hooks/hooks.json`'s `PostToolUse` array. (Classic's manifest also carries a variant-specific `SessionStart` reset block; leave it untouched — seed-sync only compares the shared PostToolUse/PreToolUse blocks + the liveness SessionStart entry.)

- [ ] **Step 3: Verify both manifests are valid JSON and their PostToolUse blocks match**

Run:
```bash
jq -e . clavity-dotnet/plugin/hooks/hooks.json >/dev/null && echo dotnet-ok
jq -e . clavity-classic/plugin/hooks/hooks.json >/dev/null && echo classic-ok
diff <(jq -S '.hooks.PostToolUse' clavity-dotnet/plugin/hooks/hooks.json) \
     <(jq -S '.hooks.PostToolUse' clavity-classic/plugin/hooks/hooks.json) && echo posttooluse-in-sync
```
Expected: `dotnet-ok`, `classic-ok`, `posttooluse-in-sync` (empty diff).

- [ ] **Step 4: Commit**

```bash
git add clavity-dotnet/plugin/hooks/hooks.json clavity-classic/plugin/hooks/hooks.json
git commit -m "feat(agy-test-audit): register the reminder hook in both plugin manifests"
```

---

## Task 3: The `agy-test-audit` SKILL.md (both mirrors)

The discipline procedure. Modeled on `agy-capstone/SKILL.md` (transport clause, safety envelope, ASCII `[VERDICT]` tokens, marker-contract reference), but for coverage auditing. It must satisfy the generalized linter (Task 4): frontmatter `name: agy-test-audit`; the three required `[VERDICT]` forms present; both transports named (`agy_ask` and `clavity ask --review-only`); the marker constant `.clavity/agy-marks/` referenced; pure ASCII.

**Files:**
- Create: `clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md`
- Create: `clavity-classic/plugin/skills/agy-test-audit/SKILL.md` (byte-identical mirror)

- [ ] **Step 1: Write the skill (dotnet copy)**

Create `clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md` with exactly this content:

```markdown
---
name: agy-test-audit
description: Use ONLY after AGY-CAPSTONE is GREEN and before declaring a development branch done - never mid-implementation. Convenes the live agy peer to audit the TEST SUITES for coverage exhaustiveness (untested reachable behaviours, vacuous/weak assertions, missing edge cases) over the branch diff, verifies every claimed gap by measurement, and surfaces verified gaps for the owner to scope. Distinct from the capstone's defect hunt: it asks "would the tests catch the next regression?". Ends with one ASCII [VERDICT] token. Best-effort prompt-discipline, manually invokable as /agy-test-audit; auto-fire is a separate marker-gated hook.
---

# agy-test-audit - audit the test safety-net before you call the branch done

## When to use
Invoke this skill at exactly one moment: **after AGY-CAPSTONE reports GREEN, before you declare a
development branch COMPLETE.** Its job is the question the capstone does NOT ask - not "are there defects
in the shipped code?" but "**would the tests catch the next defect?**" It hunts untested reachable
behaviours, vacuous or weak assertions, and missing edge cases in the committed test suites.

Do **not** fire it mid-implementation or on routine intermediate commits - that traps you in premature
completion breakpoints and burns a redundant paid consult. One audit per branch-finish, on the range the
branch produced, after the capstone is GREEN over that same range.

This is **best-effort prompt-discipline, not a sandbox.** The `[VERDICT]` token is self-reported; its
forcing functions make hollow compliance visible to your human. The bar is "materially better than
shipping an untested safety-net," not proof of completeness - a single-peer audit raises the coverage
FLOOR, it does not prove no gap remains.

## Transport (resolve to your own plugin)
Send every consult over your driver's review-ask transport, review-only:
- **clavity-dotnet:** the `agy_ask` MCP tool, after an `agy_status` idle-check (do not fire while the
  peer is busy).
- **clavity-classic:** `clavity ask --review-only` (subagents use the CLI form, not the MCP bus).

## Safety envelope (every consult, no exceptions)
A bare "review-only" once let the peer write to the tree anyway. Wrap each consult:
1. **Snapshot before** - capture `git status --short`.
2. **Forbidden-actions banner** - state in the payload: "REVIEW-ONLY. Do not edit, create, move, or
   delete any file. Do not run mutating commands. Respond with analysis only."
3. **Permission to pass** - the peer may decline or say it needs more; it must not act.
4. **Point at files, not summaries** - write the audit brief + the exact file list to
   `.clavity/seams/<topic>.md` and send the peer the PATH; let it read the committed test+source files
   itself. Never consult it on a pasted summary of your own reading. Any measure-and-reproduce framing
   MUST name a scratch dir (`.clavity/scratch/<topic>/`) so the peer never writes to cwd.
5. **Diff after** - re-check `git status` against the before-snapshot; if the tree changed, the peer
   breached review-only: surface it loudly and best-effort revert peer-touched paths that were clean
   before (never a blind `git checkout -- .`), then halt-and-ask your human.

## Scope (what the peer audits) - forked by trigger
- **Hook-nudged (branch-finish):** scope to the files in the branch diff and their *immediate* test
  counterparts + directly-relevant source - the same range the capstone reviewed.
- **Manually invoked (`/agy-test-audit <paths>`):** scope to the explicitly provided `<paths>`. A manual
  run on a clean working tree has an EMPTY diff, so the diff-bound must NOT be applied or it audits
  nothing.
Either way: NOT the whole suite or repo (context blow-up, cost, peer timeout). Bind scope in the payload:
audit ONLY these files; assume the surrounding code is correct; no global discovery. Inline the running
accepted-boundary ledger (below) as text each round - the peer's context can truncate; a fresh cascade
carries nothing forward.

**The audit is itself a heavy peer consult** and inherits the peer's own latency/timeout failure modes -
a long consult can hit the peer's idle-wait timeout and be backgrounded. Poll status to idle then retrieve
the completed reply; **NEVER** read a timed-out or errored consult as "no gaps found" (that is a silent
false pass - treat it as peer-unreachable, below).

## The audit round (what to ask, how to check)
1. **Ask for a coverage verdict in a parseable form** the driver checks before accepting: a terminal token
   `[VERDICT: EXHAUSTIVE]` or `[VERDICT: GAPS FOUND]`, plus a machine-checkable `[VERIFIED: <file>, ...]`
   block naming every file the peer actually read. Each gap is enumerated as: the untested behaviour, its
   source `file:line`, the concrete regression that would slip through, and the **specific test that should
   exist** (name + what it asserts). Apply a **severity floor** (skip trivial/contrived nits) - and require
   the audit to **list the top 1-2 gaps it discarded below the floor**, so a real gap cannot be swept under
   the floor unseen.
   - An `[VERDICT: EXHAUSTIVE]` is **valid only if the `[VERIFIED: ...]` block is present and non-empty** -
     regex-reject a bare or malformed EXHAUSTIVE (a silent-success path) and re-ask. A bare "looks
     complete" is not a valid EXHAUSTIVE.
2. **VERIFY each claimed gap by measurement** before accepting it - read the cited test yourself and grep
   for a sibling that already exercises the path. The peer over-counts and states false gaps with full
   confidence (in the motivating run it claimed a "gap" already covered by an existing test; only reading
   it revealed the false positive). Discard unverified gaps. This defends against false *positives* only -
   see the stated limitation below on false negatives.
3. **Maintain an ACCEPTED-BOUNDARY LEDGER** - behaviours deliberately not covered through this harness
   because they are untestable-without-brittle-mocks AND otherwise compensated (a unit test, a catch-scope,
   a structural guarantee). These are do-NOT-re-raise. Each entry records its **specific compensation** +
   a code anchor; a future audit **re-validates the compensation still exists** before honoring the
   do-not-re-raise (an entry whose compensation vanished is promoted back to a live gap).
4. **Surface the VERIFIED gaps to the OWNER to scope** - all / high-severity only / defer. The discipline
   **does not auto-write tests**; the owner decides scope (the AGY-FIRST "owner decides" ethos). Any gaps
   the owner **defers must be logged as tracked debt** in the rolling debt file (below) - a
   GAPS-FOUND-but-all-deferred outcome is legitimate only if recorded, so a defer-everything habit is
   visible in one place and the discipline cannot degrade into run-then-defer theater.
5. **Close the chosen gaps - the DRIVER authors each test itself.** The peer's "suggested test" is a
   *specification* (name + what to assert), never code to paste-and-run: the peer's output is untrusted
   input, gated by verify-before-fold (2) and owner-scoping (4), so a confused/compromised peer cannot
   inject executable code via a "gap." Each new test **must be NON-VACUOUS** - it must FAIL if the guarded
   behaviour regresses. Prove non-vacuousness with a **temporary LOGIC MUTANT** of the guarded code (flip a
   boolean, drop a conditional, break a calculation) - NOT a structural/signature break (deleting a
   property/method), which only fails to *compile* and proves the symbol was referenced, not that the
   runtime assertion catches a behavioural slip. Confirm the **specific newly-added test** is the one that
   went red under the mutant - not merely that the suite returned non-zero (a coincidental flaky test could
   satisfy that). If a single-point mutant does NOT turn the test red, that may indicate **defense-in-depth**
   (multiple independent guards), not a vacuous test - widen the mutant or accept a multi-guard regression
   target rather than concluding "vacuous."

## Capstone-invalidation rule (the discipline's sharpest edge)
Closing a coverage gap sometimes reveals the code is **untestable as written** (hard-wired dependency,
missing seam) and needs an **implementation-source refactor** to test it. Any such source change
**invalidates the prior AGY-CAPSTONE GREEN**: re-run AGY-CAPSTONE over the new code before the branch is
declared done. The audit is NOT a strictly one-way gate - the loop is
`capstone-green -> audit -> (owner-scoped test/refactor) -> if source changed, re-capstone -> re-audit`.
This loop **terminates**: it is owner-gated, the gap set is finite, and a re-capstone reads only the delta.

## Outputs (two distinct artifacts)
- **A per-run report - EPHEMERAL** (scratch dir or a `.gitignore`d path, NOT committed): the coverage
  verdict, the `[VERIFIED: ...]` block, the verified-gap list (each with `file:line`, the slip-through
  regression, and the missing test's name + assertion), and the discarded-below-floor items. Committing one
  per branch-finish would pollute the repo with point-in-time files operators learn to ignore.
- **A single, stable, ROLLING COMMITTED file** - default `docs/coverage-debt.md` (a project may override the
  path) - holding ONLY what must persist: **unresolved tracked debt** (owner-deferred gaps) and the
  **accepted-boundary ledger** (the do-not-re-raise list, each with its compensation + anchor). Closed gaps
  are removed. Structure it append-only / section-partitioned to minimize merge conflicts (a single file
  touched every branch-finish is a conflict hotspot where a careless `--ours`/`--theirs` silently drops a
  teammate's entry). A periodic **manual whole-tree garbage-collection pass** reconciles it against current
  code and drops orphaned entries - the routine diff-scoped run cannot see deleted code to prune stale
  entries.

## If the peer is unreachable
No live peer / no auth / the idle-check never clears, or a consult times out / errors: **halt and ask your
human** to restore the channel or explicitly waive the audit - MUST NOT silently skip (a silently-skipped
audit reads as "the tests are exhaustive" - false confidence). In a non-interactive run with no operator,
**abort** emitting `[VERDICT: agy-required-but-unreachable]` and leave the gap list in the run report / CI
logs (NOT the committed debt file - a write just before a non-zero exit in an ephemeral container is lost).
Never a silent pass.

## The [VERDICT] tokens (ASCII only, emitted by disposition)
ASCII only - no em-dash or other non-ASCII (mojibake risk; this project has hit corruption). You (the
driver) emit these:
- `[VERDICT: EXHAUSTIVE]` - a clean audit: the peer read a non-empty `[VERIFIED: ...]` set and, after your
  measurement, no verified gap survives above the severity floor. Proposes the safety-net is adequate; the
  human still owns the gate.
- `[VERDICT: GAPS FOUND]` - one or more verified gaps remain; each is owner-scoped (closed now, or deferred
  and logged as tracked debt). A GAPS-FOUND run is legitimately "done" only when every gap is either closed
  or recorded as deferred debt.
- `[VERDICT: agy-required-but-unreachable]` - the consult could not run (genuine connectivity failure or a
  timed-out/errored heavy consult) and no operator waived it. Never a silent pass.

## Stated limitation - false negatives
Every guard above defends against false *positives* (the peer claiming a gap that isn't one). NONE defends
against a false *negative* - the peer silently missing a real gap. A single-peer audit is a **floor, not
proof of completeness**, and does not replace good test design or the author's own coverage judgement.
Optional per-run mitigation: rotate the audit's lens ("what modality/behaviour did I not look at?") across
runs.

## Debounce marker (hook contract - written here, read by the auto-fire hook)
Record that the audit ran so the marker-gated reminder hook (shipped separately) does not re-nudge for the
same `HEAD`. Create `.clavity/agy-marks/` first if absent.
- **Path:** `.clavity/agy-marks/agy-test-audit.head` - a single discipline-keyed marker, no `<plugin-id>`
  prefix (Option S, as for agy-first/agy-capstone). See `docs/agy-disciplines-marker-contract.md`.
- **Content:** the audited sha - `git rev-parse HEAD` for the range that was actually audited, nothing else.
  If HEAD cannot resolve, skip writing (the discipline re-fires next trigger - safe).
- **Written ONLY on a completed audit** - an `[VERDICT: EXHAUSTIVE]`, or a `[VERDICT: GAPS FOUND]` whose
  gaps are all owner-dispositioned (closed or logged as deferred debt). An `agy-required-but-unreachable`
  abort writes NO marker (the discipline re-fires next trigger). If closing gaps advanced HEAD, write the
  audited sha, not ambient HEAD.

`.clavity/` is runtime state and is gitignored - never commit a marker.
```

- [ ] **Step 2: Mirror the skill to clavity-classic**

Run: `cp clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md clavity-classic/plugin/skills/agy-test-audit/SKILL.md` (create the dir first: `mkdir -p clavity-classic/plugin/skills/agy-test-audit`).

- [ ] **Step 3: Verify the two copies are byte-identical + pure ASCII**

Run:
```bash
diff clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md clavity-classic/plugin/skills/agy-test-audit/SKILL.md && echo skill-in-sync
# pure-ASCII check (no byte > 127):
python -c "import sys;d=open('clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md','rb').read();sys.exit(1 if any(b>127 for b in d) else 0)" && echo skill-ascii-ok
```
Expected: `skill-in-sync`, `skill-ascii-ok`. (If `python` is unavailable, the linter in Task 4 also enforces ASCII.)

> **Deferred refinements (spec §5, right-sized here):** the rolling-debt-file **garbage-collection** pass is documented in the skill as a manual whole-tree routine, not implemented as tooling in v1; further **nudge-dedupe** (a "nudged-this-HEAD" breadcrumb so the reminder fires once rather than on each post-capstone tool call) is left to a follow-up — the current debounce (capstone.head==HEAD ∧ audit.head!=HEAD) already bounds it to the narrow capstone-green→audit-run window and self-resolves.

- [ ] **Step 4: Commit**

```bash
git add clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md clavity-classic/plugin/skills/agy-test-audit/SKILL.md
git commit -m "feat(agy-test-audit): the discipline SKILL.md (both mirrors)"
```

---

## Task 4: Generalize the discipline linter to a per-skill verdict map + enroll `agy-test-audit`

The linter currently iterates ONE global `$requiredVerdicts` array against every skill (`scripts/check-agy-discipline-skills.ps1:16-21,45-47`). `agy-test-audit` has a DIFFERENT verdict vocabulary, so the array must become a per-skill hashtable. Then enroll `agy-test-audit` and update the Pester test — including restructuring its rejection `-ForEach` blocks (which currently remove `SKIPPED-UNREACHABLE`, a token the audit does not have).

**Files:**
- Modify: `scripts/check-agy-discipline-skills.ps1`
- Modify: `scripts/tests/check-agy-discipline-skills.Tests.ps1`

- [ ] **Step 1: Update the linter test first (fixtures + per-skill rejection tokens)**

TDD: the test defines the new contract; watch it fail before changing the linter. Replace the `New-ScratchRoot` skill list and the rejection `-ForEach` arrays in `scripts/tests/check-agy-discipline-skills.Tests.ps1`.

Change `New-ScratchRoot`'s staged-skill loop (line 12) to include the new skill:

```powershell
        foreach ($s in @('agy-first', 'agy-capstone', 'agy-test-audit')) {
```

Restructure the two token-specific rejection cases to carry a per-skill token that each skill actually contains. Replace the `-ForEach` block of the **"fails when a required [VERDICT] form is missing"** test (lines 43-53) with:

```powershell
        It 'fails when a required [VERDICT] form is missing from <skill>' -ForEach @(
            @{ skill = 'agy-first';      token = '[VERDICT: SKIPPED-UNREACHABLE]' },
            @{ skill = 'agy-capstone';   token = '[VERDICT: SKIPPED-UNREACHABLE]' },
            @{ skill = 'agy-test-audit'; token = '[VERDICT: EXHAUSTIVE]' }
        ) {
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            $body = (Get-Content -Raw $target).Replace($token, '[VERDICT: GONE]')
            Set-Content -Path $target -Value $body -Encoding utf8
            & $script:Lint -Root $scratch 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
            Remove-Item -Recurse -Force $scratch
        }
```

For the **non-ASCII**, **empty-file**, and **name-in-body** rejection cases (lines 31-41, 55-68, 70-83), just extend each `-ForEach` list with `@{ skill = 'agy-test-audit' }` (they perturb generic invariants that apply to every skill):

```powershell
            @{ skill = 'agy-first' }, @{ skill = 'agy-capstone' }, @{ skill = 'agy-test-audit' }
```
(apply to all three of those `-ForEach @(...)` arrays.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"`
Expected: FAIL — the real-repo pass test and the `agy-test-audit` rejection cases fail because the linter does not yet know `agy-test-audit` (it lints only agy-first/agy-capstone and would not check the audit skill's tokens; the "passes when every shipped skill…" test stages agy-test-audit but the linter ignores it — and the missing-`EXHAUSTIVE` case cannot fail on a skill the linter never reads).

- [ ] **Step 3: Generalize the linter**

In `scripts/check-agy-discipline-skills.ps1`, replace the skill list (line 13) and the global `$requiredVerdicts` array (lines 15-21) with an enrolled list + a per-skill hashtable, and change the verdict-check loop (lines 44-47) to index by skill.

Replace lines 12-21:

```powershell
# Discipline skills shipped so far. SP-B appended 'agy-capstone'; AGY-TEST-AUDIT appends 'agy-test-audit'.
$skills = @('agy-first', 'agy-capstone', 'agy-test-audit')

# The required ASCII [VERDICT] forms PER SKILL (each discipline has its own vocabulary). agy-first and
# agy-capstone share the convergent-review set (spec Decision 2.1 + 2.7); agy-test-audit gates coverage,
# so it declares EXHAUSTIVE / GAPS FOUND / agy-required-but-unreachable instead.
$requiredVerdicts = @{
    'agy-first'      = @('[VERDICT: ALIGNED]', '[VERDICT: REJECTED - ', '[VERDICT: NEGOTIATE - ', '[VERDICT: SKIPPED-UNREACHABLE]')
    'agy-capstone'   = @('[VERDICT: ALIGNED]', '[VERDICT: REJECTED - ', '[VERDICT: NEGOTIATE - ', '[VERDICT: SKIPPED-UNREACHABLE]')
    'agy-test-audit' = @('[VERDICT: EXHAUSTIVE]', '[VERDICT: GAPS FOUND]', '[VERDICT: agy-required-but-unreachable]')
}
```

Change the verdict-check loop (currently lines 44-47) to index the hashtable by the current skill:

```powershell
    # (c) all required [VERDICT] forms for THIS skill present
    foreach ($v in $requiredVerdicts[$skill]) {
        if (-not $raw.Contains($v)) { Fail "$rel : missing required verdict form '$v'" }
    }
```

(Leave every other check — frontmatter name, ASCII, both transports, marker constant — unchanged; they already apply per-skill.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"`
Expected: PASS — including the real-repo `& $script:Lint` pass (which now lints all three shipped skills) and all rejection cases across the three skills.

- [ ] **Step 5: Run the linter directly against the real repo**

Run: `pwsh -c "./scripts/check-agy-discipline-skills.ps1"`
Expected: `agy-discipline skills OK`, exit 0. (This is the real gate that the Task-3 SKILL.md satisfies every invariant.)

- [ ] **Step 6: Commit**

```bash
git add scripts/check-agy-discipline-skills.ps1 scripts/tests/check-agy-discipline-skills.Tests.ps1
git commit -m "feat(agy-test-audit): per-skill verdict map in the discipline linter; enroll agy-test-audit"
```

---

## Task 5: Extend the seed-sync guard to the new shared artifacts

`scripts/check-seed-artifacts-synced.sh` byte-diffs a hardcoded list of shared artifacts across the two plugins (lines 10-18). Add the new skill and hook. (The hooks.json PostToolUse/PreToolUse blocks are already compared by lines 29-41 — no change needed there.)

**Files:**
- Modify: `scripts/check-seed-artifacts-synced.sh`

- [ ] **Step 1: Add the two new artifacts to the `for rel` list**

In `scripts/check-seed-artifacts-synced.sh`, extend the `for rel in \ … ; do` list (lines 10-18) with the new skill and hook:

```bash
for rel in \
  skills/adversarial-panel-review/SKILL.md \
  skills/agy-first/SKILL.md \
  skills/agy-capstone/SKILL.md \
  skills/agy-test-audit/SKILL.md \
  hooks/agy-after-reminder.sh \
  hooks/agy-seam-inject.sh \
  hooks/agy-test-audit-reminder.sh \
  hooks/agy-liveness-check.sh \
  knowledge/agy-assumptions.md \
  knowledge/agy-capabilities.md ; do
```

- [ ] **Step 2: Run the seed-sync guard**

Run: `bash scripts/check-seed-artifacts-synced.sh`
Expected: `seed agent artifacts in sync (dotnet == classic)`, exit 0 (both new files are byte-identical mirrors from Tasks 1 and 3).

- [ ] **Step 3: Commit**

```bash
git add scripts/check-seed-artifacts-synced.sh
git commit -m "test(agy-test-audit): cover the new shared skill+hook in the seed-sync guard"
```

---

## Task 6: Extend the marker-contract doc

`docs/agy-disciplines-marker-contract.md` is the single source of truth for the debounce markers. Add `agy-test-audit` to the discipline enum and document its terminal-state write semantics + the fact that its reminder hook READS `agy-capstone.head`.

**Files:**
- Modify: `docs/agy-disciplines-marker-contract.md`

- [ ] **Step 1: Add `agy-test-audit` to the marker enum**

In the "Constant" section, extend the `<discipline>` set (line 12):

```markdown
  - `<discipline>` ∈ { `agy-first` (SP-A), `agy-capstone` (SP-B), `agy-test-audit` (AGY-TEST-AUDIT) }.
```

- [ ] **Step 2: Add the audit's write rule + the cross-marker read to the "Rules" section**

After the `agy-capstone` bullet in the "Rules" section (after the block ending at line 65 — the "…never in the marker." line), add:

```markdown
  - `agy-test-audit` writes `agy-test-audit.head` only on a **completed audit**: an `[VERDICT: EXHAUSTIVE]`,
    or a `[VERDICT: GAPS FOUND]` whose every gap is owner-dispositioned (closed or logged as deferred debt
    in the rolling debt file). An `[VERDICT: agy-required-but-unreachable]` abort writes NO marker (re-fires
    next trigger). Content is the audited `git rev-parse HEAD`.
```

Then, in the "Rules" section, after the `SKIPPED-UNREACHABLE`/breach bullet (line 66-67), add a note documenting the audit reminder's cross-marker read (this is the Option-B sequencing mechanism):

```markdown
- **Cross-marker sequencing (AGY-TEST-AUDIT).** Unlike the SP-C `agy-seam-inject.sh` reader (which reads
  only its own discipline's marker), the `agy-test-audit-reminder.sh` hook READS `agy-capstone.head` to
  enforce ordering: it nudges the audit only when `agy-capstone.head == current HEAD` (capstone is GREEN at
  this HEAD) AND `agy-test-audit.head != HEAD` (audit not yet done) AND the reviewed range touched
  executable code/tests. This is sound precisely because `agy-capstone.head` is written ONLY at a
  gate-satisfied terminal state (GREEN or a `round-cap` waiver) - so its presence at HEAD is a reliable
  "capstone is satisfied here" signal for a *different* hook to read. The audit hook, like every reader,
  never writes a `.head` marker.
```

- [ ] **Step 3: Verify the doc still reads coherently**

Run: `git diff docs/agy-disciplines-marker-contract.md` and read it — confirm the enum and both new blocks land in the right sections and no ASCII/format regressions.

- [ ] **Step 4: Commit**

```bash
git add docs/agy-disciplines-marker-contract.md
git commit -m "docs(agy-test-audit): marker contract - audit marker + capstone-gate cross-read"
```

---

## Task 7: Spec amendments (emission pattern + line-77 ordering)

Fold the two AGY-FIRST-consult findings into the design spec so it matches the implemented reality. The spec is gitignored (`git add -f`).

**Files:**
- Modify: `docs/superpowers/specs/2026-07-27-agy-test-exhaustiveness-audit-design.md`

- [ ] **Step 1: Amend §3 (hook conventions) — stderr+exit-2 is wrong for this repo**

In §3, the "Hook:" bullet currently reads (line 60): `jq/bash-runtime guard, stderr + exit-2 advisory emission, silent when not applicable, …`. Replace `stderr + exit-2 advisory emission` with the real pattern:

```markdown
  hook conventions: jq/bash-runtime guard, an advisory nudge emitted as `hookSpecificOutput.additionalContext`
  JSON on stdout with exit 0 (matching `agy-after-reminder.sh`; NOT stderr/exit-2), silent when not
  applicable, suppressible under the project's `.no-agy` opt-out.
```

- [ ] **Step 2: Amend §4 (trigger ordering) — a marker-reading hook CAN know capstone is GREEN**

In §4, the first sub-bullet (lines 77-81) claims "**The ordering is driver-enforced, not hook-enforceable.** A hook cannot know the capstone is GREEN…". Replace that sub-bullet with the corrected, verified account:

```markdown
  - **The ordering is enforced by a marker-reading hook (verified refinement).** The original spec claimed
    "a hook cannot know the capstone is GREEN." That is true only for a PreToolUse-on-skill hook, which
    fires *before* any consult. A *marker-reading* PostToolUse hook CAN know: `agy-capstone.head` is written
    ONLY at a gate-satisfied terminal state (human-GREEN or a `round-cap` waiver -
    `docs/agy-disciplines-marker-contract.md`), so the `agy-test-audit-reminder.sh` hook nudges only when
    `agy-capstone.head == HEAD` AND `agy-test-audit.head != HEAD` AND the reviewed range touched
    executable code/tests. The `CLAUDE.md` pointer remains the backstop for a branch finished without the
    capstone marker (e.g. capstone skipped), and the driver still owns the decision.
```

- [ ] **Step 3: Commit**

```bash
git add -f docs/superpowers/specs/2026-07-27-agy-test-exhaustiveness-audit-design.md
git commit -m "docs(agy-test-audit): fold AGY-FIRST findings - real hook emission + marker-gated ordering"
```

---

## Task 8: Global `CLAUDE.md` pointer (rule 1d) — OUTSIDE the repo

Add the one-line AGY-TEST-AUDIT pointer to the global user config, mirroring how AGY-AFTER points out of `CLAUDE.md`. **This file is `~/.claude/CLAUDE.md` — NOT tracked in this repo, so there is NO git commit.** Do it as a distinct step and report it separately.

**Files:**
- Modify: `~/.claude/CLAUDE.md` (global user config)

- [ ] **Step 1: Add rule 1d after rule 1c**

In `~/.claude/CLAUDE.md`, under "WORKING WITH ANTIGRAVITY (agy)", after rule `1c` (AGY-CAPSTONE), add a new rule `1d` — a one-paragraph pointer, no rule body (the body lives in the plugin skill):

```markdown
1d. AGY-TEST-AUDIT — GATE THE TEST SAFETY-NET (coverage), AFTER capstone-green. This discipline is NOT
   maintained here — it ships with the clavity plugin (the `agy-test-audit` skill + the marker-gated
   `agy-test-audit-reminder.sh` PostToolUse hook that nudges it once AGY-CAPSTONE is GREEN at HEAD and the
   branch changed executable code/tests). It convenes the live agy peer to audit the committed TEST SUITES
   for coverage exhaustiveness — the orthogonal question the capstone does not ask ("would the tests catch
   the next regression?") — verifies each claimed gap by measurement, and surfaces verified gaps for the
   USER to scope (deferred gaps logged as tracked debt). Like AGY-AFTER it installs/updates/uninstalls with
   the plugin and leaves no residue here.
```

- [ ] **Step 2: Update the closing taxonomy line**

Find the taxonomy summary in rule 1c's tail (`AGY-FIRST gates the decision · AGY-AFTER the artifact · AGY-CAPSTONE the finished implementation · AGY-LEARN captures.`) and update it to include the audit:

```markdown
(AGY-FIRST gates the decision · AGY-AFTER the artifact · AGY-CAPSTONE the finished implementation ·
AGY-TEST-AUDIT the test safety-net (coverage) · AGY-LEARN captures.)
```

- [ ] **Step 3: Report (no commit)**

Confirm to the owner that `~/.claude/CLAUDE.md` was edited (it is global user config, not part of any repo commit).

---

## Task 9: Full-suite verification

Run every gate this plan touches, plus a build, to confirm nothing regressed.

- [ ] **Step 1: Run the script test-suite**

Run: `just test-scripts` (from repo root — `pwsh -c "Invoke-Pester scripts/tests -Output Detailed -CI"`).
Expected: all Pester suites green, including the new `agy-test-audit-reminder.Tests.ps1` and the updated `check-agy-discipline-skills.Tests.ps1`.

- [ ] **Step 2: Run the two shell gates directly**

Run:
```bash
bash scripts/check-seed-artifacts-synced.sh
pwsh -c "./scripts/check-agy-discipline-skills.ps1"
```
Expected: `seed agent artifacts in sync (dotnet == classic)` and `agy-discipline skills OK`.

- [ ] **Step 3: Confirm the plugin build is unaffected**

The installer wildcard-copies `plugin/*` (no per-skill/hook manifest to update — verified in the cohesive-distribution installer), and the dotnet product build does not compile plugin assets. Sanity-check the product still builds:

Run: `cd clavity-dotnet && dotnet build`
Expected: build succeeds, 0 errors. (No `Clavity.Ls` source changed, so this is a regression guard only.)

- [ ] **Step 4: Confirm the marker directory is gitignored (no marker leaks)**

Run: `git check-ignore .clavity/agy-marks/agy-test-audit.head && echo ignored`
Expected: `ignored` (matches the existing `.clavity/` gitignore rule — no runtime marker is ever committed).

---

## Self-Review (run after the plan is drafted; performed inline before finalizing)

1. **Spec coverage:** §1-2 (purpose/distinct) → SKILL.md "When to use" + rule 1d. §3 (placement: skill+hook+CLAUDE.md pointer) → Tasks 1/3/8 + §3 amendment. §4 (trigger: branch-finish, diff-gated, unreachable) → Task 1 hook + SKILL.md "Scope"/"unreachable" + §4 amendment. §5 (procedure core+refinements) → SKILL.md "audit round"/"capstone-invalidation". §6 (failure modes) → SKILL.md guards (severity floor, logic-mutant, verify-before-fold, accepted-boundary ledger, owner-scopes, tracked-debt). §7 (ordering/taxonomy) → Task 8 taxonomy line. §8 (outputs: ephemeral report + rolling committed debt file + headless-emit) → SKILL.md "Outputs"/"unreachable". §9 (testing the discipline) → Tasks 1/4/5 tests. §10 (out of scope) → SKILL.md (no auto-write; floor-not-proof).
2. **Placeholder scan:** no TBD/"handle appropriately"/"similar to Task N" — every code/test/edit block is complete.
3. **Type/name consistency:** marker names `agy-capstone.head` / `agy-test-audit.head`; verdict tokens `[VERDICT: EXHAUSTIVE]` / `[VERDICT: GAPS FOUND]` / `[VERDICT: agy-required-but-unreachable]` are identical across the hook message, the SKILL.md tokens section, the linter hashtable, and the linter-test rejection token — checked.

## Execution Handoff

After this plan is saved and self-audited, it goes through an **AGY-AFTER adversarial panel** (it is a high-leverage plan driving an installed-discipline build) before execution. Then, execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task + two-stage review (spec compliance, then code quality). Tier-gate per the coding-subagent rules: Tasks 2/5/6/7/8 (mechanical, well-specified edits) → cheap model; Tasks 1/3/4 (the hook logic, the SKILL.md judgment, the linter refactor) → standard model; controller (this session, Opus) coordinates and verifies.
2. **Inline Execution** — executing-plans with checkpoints.

**Final gate:** after all tasks land, run **AGY-CAPSTONE** over the committed range (the executable artifacts here are the bash hook + Pester tests + the PowerShell linter — reachable-behaviour defects a plan review cannot catch), then the owner owns the push (public repo; leak-check the gitignored `docs/superpowers/*` first).
```
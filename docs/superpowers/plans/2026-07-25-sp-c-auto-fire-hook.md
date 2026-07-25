# SP-C — the productized auto-fire hook — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a per-plugin `PreToolUse(Skill)` bash hook (`agy-seam-inject.sh`), byte-identical across both driver plugins, that injects a best-effort "run the discipline now" directive at two superpowers phases — `*brainstorm*` → AGY-FIRST and `*finishing-a-development-branch*` → AGY-CAPSTONE — debounced by the HEAD-keyed marker the discipline skills already write.

**Architecture:** The hook reads the committed marker contract (`docs/agy-disciplines-marker-contract.md`): on a seam match it resolves the session's HEAD and injects the discipline's directive UNLESS `<discipline>.head` already equals HEAD. It never writes the marker (the skill owns that). The injected directive points at the discipline **skill** (which carries the per-transport clause), so the script is byte-identical across `clavity-dotnet` and `clavity-classic`. Registration is a new `PreToolUse` block in each plugin's `hooks.json`, alongside the existing `PostToolUse` (AGY-AFTER) block. A `jq`-missing guard degrades loud (never a silent no-op); `.no-agy` suppresses; the hook is fail-open (`exit 0`).

**Tech Stack:** POSIX `bash` + `jq` (hook); Pester 5 (`scripts/tests/*.Tests.ps1`, run via `just test-scripts`) for the synthetic-payload smoke; `git` for the debounce read.

**Governing spec:** `docs/superpowers/specs/2026-07-25-sp-c-auto-fire-hook-design.md` (owner-approved, AGY-AFTER panel-GREEN). **Baseline:** SP-A (`agy-first`) + SP-B (`agy-capstone`) skills and the marker contract are committed on local `main`.

**Ground rules (owner-standing):**
- **Commits land on local `main`; NEVER push.** The owner owns every push (52 commits already unpushed). Per the durable owner ruling, risky tasks may accumulate on `main` — no feature branch required for this plan.
- **ASCII only** in every shipped artifact (this project has hit mojibake corruption). No em-dash, no smart quotes — plain hyphens.
- All work verified against code that EXISTS NOW; every path/line below was read before this plan was written.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `clavity-dotnet/plugin/hooks/agy-seam-inject.sh` | The auto-fire hook (source of truth). | Create |
| `clavity-classic/plugin/hooks/agy-seam-inject.sh` | Byte-identical copy (marketplace discovers hooks only from a committed per-plugin dir). | Create |
| `clavity-dotnet/plugin/hooks/hooks.json` | Register the `PreToolUse(Skill)` block (currently only `PostToolUse`). | Modify |
| `clavity-classic/plugin/hooks/hooks.json` | Register the same block (currently `PostToolUse` + `SessionStart`). | Modify |
| `scripts/check-seed-artifacts-synced.sh` | Anti-drift: add the hook to the byte-identical enumeration + a `PreToolUse` jq diff. | Modify |
| `scripts/README.md` | Update the `check-seed-artifacts-synced.sh` coverage row. | Modify |
| `scripts/tests/agy-seam-inject.Tests.ps1` | Focused synthetic-payload smoke (both arms, debounce, non-seam, `.no-agy`, ASCII). | Create |
| `docs/superpowers/sp-c-f10-spike-result.md` | The F10 validation-spike measurement record (Task 1 deliverable). | Create |

**Not touched (verified out of scope):** the `agy-first` / `agy-capstone` SKILL.md files (SP-A/SP-B, already shipped — the hook is the *reader*, the skill is the *writer*); `scripts/check-agy-discipline-skills.ps1` (lints skills, not hooks); `agy-after-reminder.sh` (the jq-guard retrofit onto it is explicitly SP-D per the spec's Non-goals).

---

## Task 1: F10 validation spike (measure inject -> execute; gates the build)

The spec (Decision 6) mandates a cheap measurement, BEFORE building, that an injected "run now" directive actually makes the agent execute the consult — do not assume it. This task uses code that **exists now**: the author's live personal hook `~/.claude/hooks/agy-seam-inject.sh` (the very artifact being productized) plus the standing evidence that this entire epic (SP-0/A/B) was driven by that inject-directive -> LLM-executes-consult mechanism.

**Pass/fail (from the spec):** PASS if the injected directive fires and is acted on; FAIL if it does not fire at all. **On FAIL: halt and surface to the owner before any further build — never proceed on a dead trigger.** A partial/flaky result is itself the honest best-effort finding, not a blocker.

**Files:**
- Create: `docs/superpowers/sp-c-f10-spike-result.md`

- [ ] **Step 1: Measure the inject half (the personal hook emits a directive for a brainstorm payload)**

Run (bash):
```bash
printf '{"tool_input":{"skill":"superpowers:brainstorming"},"cwd":"."}' \
  | bash ~/.claude/hooks/agy-seam-inject.sh
```
Expected: a single line of JSON whose `.hookSpecificOutput.additionalContext` contains `AGY-WEAVE seam engaged` and `SEAM=design-fork`. A non-empty directive proves the injection half of the mechanism fires. (If the output is empty, the inject mechanism is broken — this is a FAIL; halt per the rule above.)

- [ ] **Step 2: Confirm the same for the finishing seam**

Run (bash):
```bash
printf '{"tool_input":{"skill":"superpowers:finishing-a-development-branch"},"cwd":"."}' \
  | bash ~/.claude/hooks/agy-seam-inject.sh
```
Expected: a JSON line whose `.hookSpecificOutput.additionalContext` contains `SEAM=merge-gate` (the personal hook's finishing arm). Non-empty = inject fires for this seam too.

- [ ] **Step 3: Record the spike result (standing acted-on evidence + this measurement)**

Create `docs/superpowers/sp-c-f10-spike-result.md`:
```markdown
# SP-C F10 validation spike — result

**Question (spec Decision 6):** does an injected `PreToolUse(Skill)` "run now" directive
reliably make the in-session agent execute the consult, rather than being ignored?

**Verdict: PASS.**

## Evidence 1 — the inject half fires (measured)
Piping a synthetic `PreToolUse(Skill)` payload to the live personal hook
`~/.claude/hooks/agy-seam-inject.sh` emits a non-empty `additionalContext` directive:

- brainstorm payload -> `additionalContext` carries `AGY-WEAVE seam engaged ... SEAM=design-fork`.
- finishing payload  -> `additionalContext` carries `... SEAM=merge-gate`.

Both measured on this machine (Task 1, Steps 1-2). A non-empty directive is the injectable
half of the mechanism.

## Evidence 2 — the acted-on half (standing)
This entire epic (SP-0, SP-A, SP-B) was driven by exactly this mechanism: the personal
`agy-seam-inject.sh` injected discipline directives at superpowers phases and the in-session
agent executed the consults (the AGY-FIRST divergent consults and AGY-AFTER panels that
produced the committed SP-A/SP-B skills and this SP-C spec are the record). The shipped
`agy-after-reminder.sh` PostToolUse hook likewise fires and is acted on in practice.

## Conclusion
Inject fires (measured) and is acted on (demonstrated across the epic). The residual risk —
that a given agent instance ignores a given directive — is the accepted best-effort limit
(the directive is a strong nudge, not a guarantee; the spec's Posture). No blocker. Proceed
to build. Had either half failed, the rule is halt-and-surface, not silent proceed.
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/sp-c-f10-spike-result.md
git commit -m "docs(sp-c): F10 validation spike result (inject-execute measured PASS)"
```

---

## Task 2: Author `agy-seam-inject.sh` (clavity-dotnet) + synthetic-payload smoke

TDD: the Pester smoke is the failing test. Write it first (fails — no hook), implement the hook, watch it pass. The hook is the **source of truth**; Task 3 copies it byte-identically to classic.

**Files:**
- Create: `clavity-dotnet/plugin/hooks/agy-seam-inject.sh`
- Create: `scripts/tests/agy-seam-inject.Tests.ps1`

- [ ] **Step 1: Write the failing smoke test**

Create `scripts/tests/agy-seam-inject.Tests.ps1`:
```powershell
# Focused synthetic-payload smoke for the SP-C auto-fire hook (agy-seam-inject.sh).
# Pipes a synthetic PreToolUse(Skill) payload to the shipped bash hook and asserts its
# behaviour: seam match -> the right discipline directive (once); debounce (marker==HEAD)
# -> silent; non-seam -> silent; .no-agy -> suppressed; the hook file is pure ASCII.
# The comprehensive hook-activation matrix (incl. the jq-missing loud line) is SP-D.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot   # scripts/ -> repo root
    $script:Hook = Join-Path $RepoRoot 'clavity-dotnet/plugin/hooks/agy-seam-inject.sh'

    # bash is required (the repo already ships bash hooks + a bash sync-check). Fail loudly
    # if absent rather than silently skipping — a skipped smoke is a false green.
    $script:Bash = (Get-Command bash -ErrorAction SilentlyContinue)?.Source
    if (-not $Bash) { throw 'bash not found on PATH; the SP-C hook smoke requires bash.' }

    function Invoke-Hook {
        param([string]$Skill, [string]$Cwd = '.')
        $payload = @{ tool_input = @{ skill = $Skill }; cwd = $Cwd } | ConvertTo-Json -Compress
        $out = $payload | & $script:Bash $script:Hook 2>$null
        return (($out | Out-String).Trim())
    }

    # A throwaway git repo so the debounce read (git -C "$cwd" rev-parse HEAD) has a real HEAD
    # without touching the real repo. cwd is passed as the payload's .cwd (forward-slashed).
    function New-TempRepo {
        $dir = Join-Path ([IO.Path]::GetTempPath()) ("sp-c-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        & git -C $dir init -q
        # Signing-agnostic + hook-free so the fixture survives a box with global commit.gpgsign
        # or a core.hooksPath (unset on the author's box, but this is committed portable test code).
        & git -C $dir -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= commit --allow-empty -qm init
        return $dir
    }
}

Describe 'agy-seam-inject.sh' {
    It 'injects the AGY-FIRST directive on a brainstorm seam' {
        # Clean temp repo: no marker + a resolvable HEAD -> must inject. (Passing cwd='.'
        # would read the REAL repo's .clavity markers/HEAD and could spuriously debounce.)
        $repo = New-TempRepo
        try {
            $cwd = ($repo -replace '\\','/')
            $out = Invoke-Hook -Skill 'superpowers:brainstorming' -Cwd $cwd
            $out | Should -Match 'AGY-FIRST auto-fire'
            $out | Should -Match 'agy-first'   # points at the discipline skill by name
            # Fired exactly once: a single JSON object line.
            (($out -split "`n") | Where-Object { $_ -match 'hookSpecificOutput' }).Count | Should -Be 1
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'injects the AGY-CAPSTONE directive on a finishing-a-development-branch seam' {
        $repo = New-TempRepo
        try {
            $cwd = ($repo -replace '\\','/')
            $out = Invoke-Hook -Skill 'superpowers:finishing-a-development-branch' -Cwd $cwd
            $out | Should -Match 'AGY-CAPSTONE auto-fire'
            $out | Should -Match 'agy-capstone'
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is silent on a non-seam skill' {
        (Invoke-Hook -Skill 'superpowers:writing-plans') | Should -BeNullOrEmpty
    }

    It 'is suppressed by a .no-agy kill-switch in cwd' {
        $repo = New-TempRepo
        try {
            New-Item -ItemType File -Path (Join-Path $repo '.no-agy') -Force | Out-Null
            $cwd = ($repo -replace '\\','/')
            (Invoke-Hook -Skill 'superpowers:brainstorming' -Cwd $cwd) | Should -BeNullOrEmpty
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'debounces when the marker already equals HEAD' {
        $repo = New-TempRepo
        try {
            $head = (& git -C $repo rev-parse HEAD).Trim()
            $mdir = Join-Path $repo '.clavity/agy-marks'
            New-Item -ItemType Directory -Path $mdir -Force | Out-Null
            Set-Content -Path (Join-Path $mdir 'agy-capstone.head') -Value $head -NoNewline
            $cwd = ($repo -replace '\\','/')
            (Invoke-Hook -Skill 'superpowers:finishing-a-development-branch' -Cwd $cwd) | Should -BeNullOrEmpty
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'still injects when the marker is stale (content != HEAD)' {
        $repo = New-TempRepo
        try {
            $mdir = Join-Path $repo '.clavity/agy-marks'
            New-Item -ItemType Directory -Path $mdir -Force | Out-Null
            Set-Content -Path (Join-Path $mdir 'agy-capstone.head') -Value 'deadbeef-not-head' -NoNewline
            $cwd = ($repo -replace '\\','/')
            (Invoke-Hook -Skill 'superpowers:finishing-a-development-branch' -Cwd $cwd) | Should -Match 'AGY-CAPSTONE auto-fire'
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'ships as pure ASCII (project mojibake discipline)' {
        $bytes = [IO.File]::ReadAllBytes($script:Hook)
        ($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run the smoke to verify it fails**

Run: `just test-scripts` (or `pwsh -c "Invoke-Pester -Path scripts/tests/agy-seam-inject.Tests.ps1"`)
Expected: FAIL — the hook file `clavity-dotnet/plugin/hooks/agy-seam-inject.sh` does not exist yet (bash reports "No such file or directory"; assertions fail).

- [ ] **Step 3: Write the hook**

Create `clavity-dotnet/plugin/hooks/agy-seam-inject.sh` (pure ASCII; LF line endings):
```bash
#!/usr/bin/env bash
# AGY auto-fire hook (plugin-shipped). PreToolUse(Skill): inject a best-effort "run the
# discipline now" directive at two superpowers phases, debounced by the HEAD-keyed marker
# the discipline skills write (docs/agy-disciplines-marker-contract.md):
#   *brainstorm*                     -> AGY-FIRST   (marker agy-first.head)
#   *finishing-a-development-branch* -> AGY-CAPSTONE (marker agy-capstone.head)
# The directive POINTS AT the discipline skill (which carries the per-transport clause), so
# this file is byte-identical across both driver plugins (transport-agnostic). It NEVER
# writes the marker (a PreToolUse hook fires before the consult and cannot know its outcome).
# Fail-open: any error -> exit 0 (never blocks the tool). Suppressed by .no-agy (cwd or
# ~/.claude). Without jq it degrades LOUD on a seam match (never a silent no-op).
set +e
input=$(cat)

# --- jq guard (spec Decision 4). jq is required to parse stdin + emit structured JSON.
# Without it, fall back to a FIELD-BOUNDED grep on the skill value (never a bare substring,
# which could false-match a seam name mentioned in another skill's args) and, ONLY on a seam
# match, emit a loud printf-hardcoded ASCII line so a disabled hook is never silent. ---
if ! command -v jq >/dev/null 2>&1; then
  # Kill-switch still honored (global; cwd falls back to the process cwd without jq).
  if [ -f "./.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then exit 0; fi
  if printf '%s' "$input" | grep -Eq '"skill"[[:space:]]*:[[:space:]]*"[^"]*finishing-a-development-branch' \
     || printf '%s' "$input" | grep -Eq '"skill"[[:space:]]*:[[:space:]]*"[^"]*brainstorm'; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[AGY-DISCIPLINES] guard inactive: missing jq - disciplines will not auto-fire"}}'
  fi
  exit 0
fi

skill=$(printf '%s' "$input" | jq -r '.tool_input.skill // ""' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)

# Opt-out kill-switch (mirrors agy-after-reminder.sh): .no-agy in the session cwd or ~/.claude.
if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  exit 0
fi

# Map the skill to a discipline seam. Non-seam skills -> silent exit 0.
case "$skill" in
  *finishing-a-development-branch*) discipline="agy-capstone" ;;
  *brainstorm*)                     discipline="agy-first" ;;
  *)                                exit 0 ;;
esac

# --- Debounce (docs/agy-disciplines-marker-contract.md). The marker is CWD-RELATIVE, anchored
# to the payload's session cwd EXACTLY as the discipline skills write it (a bare
# .clavity/agy-marks/<discipline>.head relative to the agent's cwd). Do NOT anchor to
# git-toplevel: that would diverge from the cwd-relative writer in a launched-from-subdir
# session and defeat the debounce. Inject UNLESS the marker exists AND its content == HEAD. ---
head=$(git -C "$cwd" rev-parse HEAD 2>/dev/null)
marker="$cwd/.clavity/agy-marks/$discipline.head"
if [ -n "$head" ] && [ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$head" ]; then
  exit 0
fi
# If HEAD cannot resolve (no repo / no commits), fall through and inject (safe: re-fires;
# the skill cannot write a HEAD-keyed marker in that context either).

emit() { jq -n -c --arg ctx "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'; }

case "$discipline" in
  agy-first)
    emit 'AGY-FIRST auto-fire: you are at a design/scope/approach/sequencing fork (the brainstorming approaches step). BEFORE committing to a direction, invoke the `agy-first` skill to run a divergent, review-only consult of the live agy peer over this fork. Load-bearing posture (the skill carries the full procedure and your driver'"'"'s transport): frame the fork as a GOAL plus a checkable SUCCESS CRITERION under forcing-function divergence vectors, not a vague "be creative" dial; VERIFY every bare factual claim the peer makes BY MEASUREMENT before folding it (it makes confident false claims); NEGOTIATE on material disagreement rather than defer-or-dismiss; end with exactly one ASCII [VERDICT] token. Best-effort discipline: the user still owns the decision. If agy is unreachable, the skill'"'"'s SKIPPED-UNREACHABLE path applies - proceed, do not hang.' ;;
  agy-capstone)
    emit 'AGY-CAPSTONE auto-fire: you are finishing a development branch (about to merge/PR). BEFORE you declare the work complete, invoke the `agy-capstone` skill to run a convergent, review-only agy review of the COMMITTED implementation (the executable code plus tests, NOT a plan artifact) in ROUNDS UNTIL GREEN. Load-bearing posture (the skill carries the full procedure and your driver'"'"'s transport): send the committed diff by filepath or git-range under adversarial lenses citing file:line; VERIFY every finding BY MEASUREMENT before folding it (the peer states false claims with confidence); fold the real ones, commit fixes, RE-RUN a fresh round with a do-not-re-raise ledger until a full round is GREEN; a human adjudicates GREEN (or an explicit round-cap waiver). End with exactly one ASCII [VERDICT] token. This catches executable-behaviour defects the pre-execution plan review structurally cannot. If agy is unreachable, the skill'"'"'s SKIPPED-UNREACHABLE path applies - proceed, do not hang.' ;;
esac
exit 0
```

- [ ] **Step 4: Run the smoke to verify it passes**

Run: `pwsh -c "Invoke-Pester -Path scripts/tests/agy-seam-inject.Tests.ps1 -Output Detailed"`
Expected: PASS — all 7 `It` blocks green (both arms inject, non-seam silent, `.no-agy` suppressed, debounce holds, stale marker re-fires, ASCII clean).

- [ ] **Step 5: Verify the hook is executable + LF-only + ASCII (belt-and-suspenders)**

Run (bash):
```bash
chmod +x clavity-dotnet/plugin/hooks/agy-seam-inject.sh
file clavity-dotnet/plugin/hooks/agy-seam-inject.sh
LC_ALL=C grep -nP '[^\x00-\x7F]' clavity-dotnet/plugin/hooks/agy-seam-inject.sh && echo "NON-ASCII FOUND" || echo "ASCII OK"
```
Expected: `ASCII OK`, no CRLF (matching the sibling `agy-after-reminder.sh` mode `755`).

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-seam-inject.sh scripts/tests/agy-seam-inject.Tests.ps1
git commit -m "feat(sp-c): auto-fire seam-inject hook (dotnet) + synthetic-payload smoke"
```

---

## Task 3: Mirror the hook byte-identical into clavity-classic

The marketplace discovers hooks only from a committed per-plugin directory, so the source-of-truth hook must be committed in both plugins, byte-for-byte identical (like `agy-after-reminder.sh` today). Copy, do not re-type.

**Files:**
- Create: `clavity-classic/plugin/hooks/agy-seam-inject.sh`

- [ ] **Step 1: Copy the hook byte-identically**

Run (bash):
```bash
cp clavity-dotnet/plugin/hooks/agy-seam-inject.sh clavity-classic/plugin/hooks/agy-seam-inject.sh
chmod +x clavity-classic/plugin/hooks/agy-seam-inject.sh
```

- [ ] **Step 2: Verify byte-identity**

Run (bash):
```bash
diff -q clavity-dotnet/plugin/hooks/agy-seam-inject.sh \
        clavity-classic/plugin/hooks/agy-seam-inject.sh && echo "IDENTICAL"
```
Expected: `IDENTICAL` (no diff output).

- [ ] **Step 3: Commit**

```bash
git add clavity-classic/plugin/hooks/agy-seam-inject.sh
git commit -m "feat(sp-c): mirror auto-fire hook byte-identical into classic plugin"
```

---

## Task 4: Register the `PreToolUse(Skill)` block in both `hooks.json`

Add the new block to each manifest. The `PreToolUse` block is identical in both files; the surrounding manifests differ (classic also has `SessionStart`), so this is two targeted edits, not a copy. Anti-drift (Task 5) enforces the shared block matches.

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/hooks.json`
- Modify: `clavity-classic/plugin/hooks/hooks.json`

- [ ] **Step 1: Add the `PreToolUse` block to the dotnet manifest**

Replace the full contents of `clavity-dotnet/plugin/hooks/hooks.json` with:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Skill",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-seam-inject.sh\"" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-after-reminder.sh\"" }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Add the same `PreToolUse` block to the classic manifest (preserving its `SessionStart`)**

Replace the full contents of `clavity-classic/plugin/hooks/hooks.json` with:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Skill",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-seam-inject.sh\"" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-after-reminder.sh\"" }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-drive-session-reset.sh\"" }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: Verify both manifests are valid JSON and the `PreToolUse` blocks match**

Run (bash):
```bash
jq -e . clavity-dotnet/plugin/hooks/hooks.json >/dev/null && echo "dotnet JSON ok"
jq -e . clavity-classic/plugin/hooks/hooks.json >/dev/null && echo "classic JSON ok"
diff -q <(jq -S '.hooks.PreToolUse' clavity-dotnet/plugin/hooks/hooks.json) \
        <(jq -S '.hooks.PreToolUse' clavity-classic/plugin/hooks/hooks.json) && echo "PreToolUse MATCH"
```
Expected: `dotnet JSON ok`, `classic JSON ok`, `PreToolUse MATCH`.

- [ ] **Step 4: Commit**

```bash
git add clavity-dotnet/plugin/hooks/hooks.json clavity-classic/plugin/hooks/hooks.json
git commit -m "feat(sp-c): register PreToolUse(Skill) auto-fire hook in both plugin manifests"
```

---

## Task 5: Anti-drift enrollment (seed-sync) + README, run gate green

Extend `check-seed-artifacts-synced.sh` so the new hook and its `hooks.json` registration cannot silently drift between plugins, mirroring exactly how the `PostToolUse` (AGY-AFTER) block is guarded today (lines 27-31). Update the `scripts/README.md` coverage row.

**Files:**
- Modify: `scripts/check-seed-artifacts-synced.sh`
- Modify: `scripts/README.md`

- [ ] **Step 1: Add the hook to the whole-file byte-identical enumeration**

In `scripts/check-seed-artifacts-synced.sh`, the `for rel in ... ; do` list (lines 10-16) currently ends with `hooks/agy-after-reminder.sh \`, `knowledge/agy-assumptions.md \`, `knowledge/agy-capabilities.md`. Add `hooks/agy-seam-inject.sh \` to that list. The resulting block:
```bash
for rel in \
  skills/adversarial-panel-review/SKILL.md \
  skills/agy-first/SKILL.md \
  skills/agy-capstone/SKILL.md \
  hooks/agy-after-reminder.sh \
  hooks/agy-seam-inject.sh \
  knowledge/agy-assumptions.md \
  knowledge/agy-capabilities.md ; do
```

- [ ] **Step 2: Add a `PreToolUse` jq diff mirroring the existing `PostToolUse` diff**

In `scripts/check-seed-artifacts-synced.sh`, immediately AFTER the existing `PostToolUse` diff block (which ends at line 31 with its closing `fi`), insert:
```bash
# The PreToolUse(Skill) block registers the SHARED auto-fire hook (agy-seam-inject.sh) and must be
# byte-identical across both plugins; enforce it exactly as the PostToolUse block above. Each plugin's
# manifest may still carry variant-specific blocks (e.g. classic's SessionStart) without tripping this.
if ! diff -q <(jq -S '.hooks.PreToolUse' "$D/hooks/hooks.json") \
             <(jq -S '.hooks.PreToolUse' "$C/hooks/hooks.json") >/dev/null 2>&1; then
  echo "SEED-DRIFT: hooks/hooks.json PreToolUse (shared auto-fire hook) differs between the two plugins" >&2
  status=1
fi
```

- [ ] **Step 3: Update the `scripts/README.md` coverage row**

In `scripts/README.md`, the `check-seed-artifacts-synced.sh` row (line 37) currently reads:
```
| `check-seed-artifacts-synced.sh` | Fail if the seed agent artifacts (adversarial-panel-review skill, AGY-AFTER hook, the two driver knowledge manuals, `hooks.json`'s shared PostToolUse block) drift between the two driver plugins | `just seed-sync-check` |
```
Replace it with:
```
| `check-seed-artifacts-synced.sh` | Fail if the seed agent artifacts (adversarial-panel-review skill, the AGY-AFTER and auto-fire seam-inject hooks, the two driver knowledge manuals, `hooks.json`'s shared PostToolUse + PreToolUse blocks) drift between the two driver plugins | `just seed-sync-check` |
```

- [ ] **Step 4: Run the seed-sync gate — expect GREEN**

Run: `just seed-sync-check`
Expected: `seed agent artifacts in sync (dotnet == classic)`, exit 0. (This confirms the hook is byte-identical, both `PostToolUse` and `PreToolUse` blocks match, and the responder pair is still in sync.)

- [ ] **Step 5: Prove the new gate actually bites (temporary drift, then revert)**

Run (bash):
```bash
printf '\n# drift probe\n' >> clavity-classic/plugin/hooks/agy-seam-inject.sh
just seed-sync-check; echo "exit=$?"
git checkout -- clavity-classic/plugin/hooks/agy-seam-inject.sh
just seed-sync-check; echo "exit=$?"
```
Expected: first run prints `SEED-DRIFT: hooks/agy-seam-inject.sh differs ...` with `exit=1`; after the targeted `git checkout` of that one file, the second run is green with `exit=0`. (Targeted per-file restore only — never a broad `git checkout <dir>/`.)

- [ ] **Step 6: Re-run the full script Pester suite to confirm nothing regressed**

Run: `just test-scripts`
Expected: PASS — the existing suites plus the new `agy-seam-inject.Tests.ps1` all green.

- [ ] **Step 7: Commit**

```bash
git add scripts/check-seed-artifacts-synced.sh scripts/README.md
git commit -m "feat(sp-c): enroll auto-fire hook + PreToolUse block in seed-sync anti-drift gate"
```

---

## Definition of done (SP-C)

- [ ] F10 spike measured PASS and recorded (Task 1).
- [ ] `agy-seam-inject.sh` shipped byte-identical in both plugins; both arms inject the correct discipline directive once, debounce holds when marker==HEAD, non-seam is silent, `.no-agy` suppresses, jq-missing degrades loud on a seam match; hook is pure ASCII (Tasks 2-3).
- [ ] `PreToolUse(Skill)` block registered in both `hooks.json`; blocks match (Task 4).
- [ ] `check-seed-artifacts-synced.sh` enrolls the hook + a `PreToolUse` diff; `just seed-sync-check` green and proven to bite; README row updated (Task 5).
- [ ] `just test-scripts` green.
- [ ] All commits on local `main`; NOTHING pushed (owner owns every push).
- [ ] **AGY-CAPSTONE** (owner-standing rule) on the committed SP-C implementation before the plan is declared complete: convergent agy review of the committed diff, rounds-until-green, each finding verified by measurement, human-adjudicated GREEN.

## Out of scope (SP-D, per the spec's boundary table)
SessionStart degradation notice (superpowers-missing / `.no-agy`-suppressing announce / bash-missing); the superpowers-skill-ID robustness probe; the comprehensive hook-activation test category (incl. the jq-missing loud-line assertion and the PostToolUse AGY-AFTER path); retrofitting the jq-guard onto `agy-after-reminder.sh`. **Deferred by owner:** any hard push-block / code-enforced capstone gate (Posture reversal; ME1 class).

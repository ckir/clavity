# Productize Completion Audit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the productize epic's completion claim verifiable, close the hook-ownership void, and leave the epic release-ready.

**Architecture:** Four read-only verification passes run FIRST and produce committed transcripts, because the two implementation tasks that follow modify SP-D and SP-B deliverables and would otherwise overwrite the state being audited. Then the ownership rule is published and enforced inside `agy-liveness-check.sh` (an artifact we ship, requiring nothing from the host), the capstone ledger is created, and the release checklist is written.

**Tech Stack:** bash (plugin hooks), Pester 5 (`scripts/tests/*.Tests.ps1`), `jq`, `just`, Markdown.

**Source spec:** [`docs/superpowers/specs/2026-07-31-productize-completion-audit-design.md`](../specs/2026-07-31-productize-completion-audit-design.md) — panel-GREEN after 7 rounds, 30 findings folded.

---

## Verified starting state

Every citation below was read against the working tree at HEAD `26cd99a` before this plan was written.

| Fact | Verified |
|---|---|
| `clavity-dotnet/plugin/hooks/agy-liveness-check.sh` | 86 lines, 4760 bytes; **byte-identical** to the clavity-classic mirror |
| Its `.no-agy` branches | lines 43-50, each `printf … >&2` then `exit 2` |
| It ALREADY resolves all three settings files | lines 57-67: `config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"`, `proj_dir="${CLAUDE_PROJECT_DIR:-$cwd}"`, then `user_settings` / `proj_settings` / `local_settings` collected into `present=()` |
| Its exit contract | documented at lines 12-19: healthy → `exit 0` silent; any detection outcome → stderr + `exit 2` |
| Test harness | `scripts/tests/agy-liveness-check.Tests.ps1`, **10 existing `It` blocks**; helpers in `scripts/tests/BashHookHelpers.ps1` (`Invoke-BashHook -HookPath -Payload -Env` → `.ExitCode`, `.StdErr`) |
| Test runner | `just test-scripts` (justfile:91) |
| `agy-capstone` SKILL.md | exists in BOTH plugins |
| `docs/agy-disciplines-marker-contract.md` | exists |
| Plugin READMEs | `clavity-dotnet/plugin/README.md`, `clavity-classic/plugin/README.md` |

### Correction to the spec, forced by reading the code

The spec's D1 constraint 1 says to resolve the project root "cwd-relative AND git-toplevel". **Do not implement that.** The hook already uses `CLAUDE_PROJECT_DIR` (line 58) — the host tells us the project root directly, which is strictly better than inferring it, and it is already in the file. Reuse `user_settings`/`proj_settings`/`local_settings` as they exist. The spec reasoned about the problem abstractly; the code already had the better answer. This also retires the spec's git-toplevel-stderr concern (folded as round-3 finding 19) — there is no `git rev-parse` call to silence.

---

## File structure

| File | Responsibility |
|---|---|
| `docs/superpowers/verification/2026-07-31-sp-0.md` … `-sp-a.md`, `-sp-c.md`, `-sp-d.md` | Create — one transcript per sub-project; the evidence artifact |
| `clavity-dotnet/plugin/hooks/agy-liveness-check.sh` + classic mirror | Modify — ownership check; byte-identical |
| `scripts/tests/agy-liveness-check.Tests.ps1` | Modify — one `It` per D1 constraint |
| `clavity-dotnet/plugin/README.md` + classic mirror | Modify — publish the D1 rule |
| `docs/agy-disciplines-marker-contract.md` | Modify — record D1 |
| `docs/agy-capstone-ledger.md` | Create — the D5 ledger |
| `clavity-dotnet/plugin/skills/agy-capstone/SKILL.md` + classic mirror | Modify — require the ledger line |
| `docs/productize-release-checklist.md` | Create — release contents + post-install retirement |
| `clavity-dotnet/ROADMAP.md` | Modify — tracked debt + follow-on epic |

---

### Task 1: The verification transcript template, and SP-0

**Files:**
- Create: `docs/superpowers/verification/2026-07-31-sp-0.md`

This task is READ-ONLY with respect to the epic's artifacts. It asserts; it does not fix. If it finds a real defect, STOP and report — that changes the shape of the work and is the owner's call.

- [ ] **Step 1: Create the transcript with its header**

Create `docs/superpowers/verification/2026-07-31-sp-0.md`:

```markdown
# SP-0 (plugin rename) — verification transcript

**Verified against commit:** <output of `git rev-parse --short HEAD`>
**Method:** ONE non-adversarial pass. Read the plan's deliverables, assert each exists and matches.
This is NOT a capstone and is deliberately not run as one; see the source spec, scope item 1.

## Deliverables asserted

| Deliverable | Plan reference | Command run | Result |
|---|---|---|---|
```

- [ ] **Step 2: Record the commit being verified against**

Run: `git rev-parse --short HEAD`
Paste the output into the `**Verified against commit:**` line. A transcript that does not say what it examined is not evidence.

- [ ] **Step 3: Assert the plugin identity unified**

Run:
```bash
jq -r '.name' clavity-dotnet/plugin/plugin.json clavity-classic/plugin/plugin.json
```
Expected: `clavity` from both. Record the command and its verbatim output in the table.

- [ ] **Step 4: Assert the namespace gate exists and is green**

Run: `pwsh -File scripts/check-plugin-namespace.ps1; echo "exit=$?"`
Expected: `exit=0`. Record the command and output.

- [ ] **Step 5: Assert the four renamed skills exist in both plugins**

Run:
```bash
ls -d clavity-dotnet/plugin/skills/*/ clavity-classic/plugin/skills/*/ | sed 's|.*/skills/||' | sort -u
```
Expected: names carry no legacy `clavity-` prefix (SP-0's rename). Record the full list.

- [ ] **Step 6: Close SP-0's residue — the Category 9 grep the plan skipped**

The SP-0 design (`docs/superpowers/specs/2026-07-24-sp0-clavity-plugin-rename-design.md:104-106`) instructed the plan to grep-confirm the operator's personal `agy-seam-inject.sh` was unaffected by the rename. The plan never did it. Do it now:

```bash
grep -n 'clavity-dotnet\|clavity-classic\|clavity@' ~/.claude/hooks/agy-seam-inject.sh || echo "NO legacy plugin-name references"
```
Record the verbatim result. Either outcome is information; an unrecorded result is what created this residue.

- [ ] **Step 7: Close SP-0's residue — the Spike B disposition**

SP-0 Task 6.2 required a spike whose result was never recorded, leaving Task 6.3 (`LegacyPluginName` clean-break logic) indeterminate. Determine which applies now:

```bash
ls -d ~/.claude/plugins/cache/*clavity* 2>/dev/null || echo "no cached legacy clavity plugin present"
grep -rn 'LegacyPluginName' clavity-dotnet/ clavity-classic/ installer/ 2>/dev/null || echo "LegacyPluginName not implemented"
```
Record both outputs, then write ONE sentence stating the disposition: either "no legacy plugin lingers, so Task 6.3 was correctly skipped" or "cannot determine; tracked". Do not guess.

- [ ] **Step 8: Commit**

```bash
git add -f docs/superpowers/verification/2026-07-31-sp-0.md
git commit -m "verify(sp-0): verification transcript + close the Spike B and Category 9 residue"
```

---

### Task 2: Verification pass — SP-A

**Files:**
- Create: `docs/superpowers/verification/2026-07-31-sp-a.md`

- [ ] **Step 1: Create the transcript with the same header shape as Task 1**

```markdown
# SP-A (agy-first + agy-negotiate) — verification transcript

**Verified against commit:** <output of `git rev-parse --short HEAD`>
**Method:** ONE non-adversarial pass. Read the plan's deliverables, assert each exists and matches.
This is NOT a capstone.

## Deliverables asserted

| Deliverable | Plan reference | Command run | Result |
|---|---|---|---|
```

- [ ] **Step 2: Assert the agy-first skill exists in both plugins and is byte-identical**

Run:
```bash
diff -q clavity-dotnet/plugin/skills/agy-first/SKILL.md clavity-classic/plugin/skills/agy-first/SKILL.md && echo IDENTICAL
```
Expected: `IDENTICAL`. SP-A required a byte-identical mirror.

- [ ] **Step 3: Assert the marker-contract doc exists and names the discipline**

Run: `grep -n 'agy-first\|AGY-FIRST' docs/agy-disciplines-marker-contract.md | head`
Record the output.

- [ ] **Step 4: Assert the seed-sync and lint enrollment**

Run:
```bash
grep -n 'agy-first' scripts/check-seed-artifacts-synced.sh
just seed-sync-check
just check-agy-skills
```
Expected: the skill appears in the sync list; both recipes exit 0. Record each.

- [ ] **Step 5: Record the capstone-evidence position honestly**

Append to the transcript:

```markdown
## Capstone evidence

`git log --oneline --all -i --grep=capstone` shows one SP-A-scoped fold commit. A single fold round
with no recorded GREEN round is not a reconstructible convergence. This transcript is the evidence that
the SHIPPED ARTIFACTS match the plan; it makes no claim that an adversarial capstone converged.
Per the source spec, SP-A does not get a capstone-ledger row.
```

- [ ] **Step 6: Commit**

```bash
git add -f docs/superpowers/verification/2026-07-31-sp-a.md
git commit -m "verify(sp-a): verification transcript"
```

---

### Task 3: Verification pass — SP-C

**Files:**
- Create: `docs/superpowers/verification/2026-07-31-sp-c.md`

- [ ] **Step 1: Create the transcript with the same header shape as Task 1**

```markdown
# SP-C (productized auto-fire hook) — verification transcript

**Verified against commit:** <output of `git rev-parse --short HEAD`>
**Method:** ONE non-adversarial pass. NOT a capstone.

## Deliverables asserted

| Deliverable | Plan reference | Command run | Result |
|---|---|---|---|
```

- [ ] **Step 2: Assert the shipped hook exists in both plugins, byte-identical**

Run:
```bash
diff -q clavity-dotnet/plugin/hooks/agy-seam-inject.sh clavity-classic/plugin/hooks/agy-seam-inject.sh && echo IDENTICAL
```
Expected: `IDENTICAL`.

- [ ] **Step 3: Assert the capstone trigger is bound as Decision 1 requires**

SP-C Decision 1 bound the capstone arm to `finishing-a-development-branch`. Run:
```bash
grep -n 'finishing-a-development-branch' clavity-dotnet/plugin/hooks/agy-seam-inject.sh
```
Expected: at least one match. Record it.

- [ ] **Step 4: Assert hook registration in both plugins**

Run: `grep -n 'agy-seam-inject' clavity-dotnet/plugin/hooks/hooks.json clavity-classic/plugin/hooks/hooks.json`
Record the output.

- [ ] **Step 5: Assert the shipped hook's own tests pass**

Run: `just test-scripts`
Expected: exit 0. `scripts/tests/agy-seam-inject.Tests.ps1` exists and runs as part of this. Record the summary line.

- [ ] **Step 6: Record the divergence from the personal copy**

Append to the transcript:

```markdown
## Divergence from the operator's personal copy

The operator's `~/.claude/hooks/agy-seam-inject.sh` fires on additional seams (observed live: it fired
on `brainstorming` and on `subagent-driven-development`), which the shipped hook deliberately does not
carry — Decision 1 narrowed the capstone trigger. The two are NOT interchangeable. This is the divergence
D1 and D6 exist to resolve; it is recorded here so the retirement step is understood as a behaviour
change, not a no-op.
```

- [ ] **Step 7: Commit**

```bash
git add -f docs/superpowers/verification/2026-07-31-sp-c.md
git commit -m "verify(sp-c): verification transcript + record the personal-copy divergence"
```

---

### Task 4: Verification pass — SP-D

**Files:**
- Create: `docs/superpowers/verification/2026-07-31-sp-d.md`

**Do this task BEFORE Task 6.** Task 6 modifies `agy-liveness-check.sh`, an SP-D deliverable. Verifying after would audit this plan's own edit rather than SP-D's shipped state.

- [ ] **Step 1: Create the transcript with the same header shape as Task 1**

```markdown
# SP-D (degradation guards, tests, anti-drift) — verification transcript

**Verified against commit:** <output of `git rev-parse --short HEAD`>
**Method:** ONE non-adversarial pass. NOT a capstone.
**Ordering note:** run before this plan's Task 6, which modifies agy-liveness-check.sh.

## Deliverables asserted

| Deliverable | Plan reference | Command run | Result |
|---|---|---|---|
```

- [ ] **Step 2: Assert the liveness hook exists, byte-identical, with its documented exit contract**

Run:
```bash
diff -q clavity-dotnet/plugin/hooks/agy-liveness-check.sh clavity-classic/plugin/hooks/agy-liveness-check.sh && echo IDENTICAL
sed -n '12,19p' clavity-dotnet/plugin/hooks/agy-liveness-check.sh
```
Expected: `IDENTICAL`, and the EXIT-CODE CONTRACT comment block. Record both.

- [ ] **Step 3: Assert the jq guard retrofit on agy-after-reminder**

Run: `grep -n 'command -v jq' clavity-dotnet/plugin/hooks/agy-after-reminder.sh`
Expected: at least one match. Record it.

- [ ] **Step 4: Assert the hook-activation test matrix runs green**

Run: `just test-scripts`
Expected: exit 0. Record the summary line and the count of `.Tests.ps1` files exercised:
```bash
ls scripts/tests/*.Tests.ps1 | wc -l
```

- [ ] **Step 5: Record the release gap — this is SP-D's real outstanding item**

Append to the transcript:

```markdown
## The epic's unmet definition of done

SP-D's design requires "ONE combined release closes the epic". Measured:

    git for-each-ref --sort=-creatordate --format='%(refname:short) %(creatordate:short)' refs/tags | head -3
    git log --all -i --grep='sp-d' --format='%h %cs' | head -3

The newest release tag predates SP-D's commits, so no release contains this work. The disciplines have
never shipped. This is not a defect in SP-D's artifacts — they are present and their tests pass — it is
the epic's closing step, addressed by this plan's Task 8.
```

Run both commands and paste their verbatim output into the transcript.

- [ ] **Step 6: Commit**

```bash
git add -f docs/superpowers/verification/2026-07-31-sp-d.md
git commit -m "verify(sp-d): verification transcript + record the unmet release DoD"
```

---

### Task 5: Publish the D1 ownership rule

**Files:**
- Modify: `clavity-dotnet/plugin/README.md`
- Modify: `clavity-classic/plugin/README.md`
- Modify: `docs/agy-disciplines-marker-contract.md`

- [ ] **Step 1: Append the rule to both plugin READMEs, byte-identical**

Add this section to the END of both README files, verbatim and identical in each:

```markdown
## Hook ownership

A discipline hook has exactly one owner. Once a hook ships in a plugin, the plugin is its sole owner:
your personal registration of a same-named hook is retired. Retirement means **removing the
registration** — the file may stay on disk, since only registration determines execution.

Turning a shipped hook off is done with the `.no-agy` kill-switch, which is **global — it silences every
agy discipline, not one hook**. There is deliberately no per-hook off switch: a selective, silent disable
is the failure mode this rule exists to prevent. **One documented exception: the ownership check itself
still runs under `.no-agy`** and reports that personal registrations remain, so the kill-switch cannot be
used to hide an override.

Iterating on a hook locally is done by running the script directly against a synthetic payload —
`echo '{"cwd":"."}' | bash <hook>` — never by shadowing the shipped copy.
```

- [ ] **Step 2: Verify the two READMEs are byte-identical in that section**

Run:
```bash
diff <(sed -n '/^## Hook ownership/,$p' clavity-dotnet/plugin/README.md) \
     <(sed -n '/^## Hook ownership/,$p' clavity-classic/plugin/README.md) && echo IDENTICAL
```
Expected: `IDENTICAL`.

- [ ] **Step 3: Record the rule in the marker-contract doc**

Append to `docs/agy-disciplines-marker-contract.md`:

```markdown
## Hook ownership (D1)

Shipped plugin hooks are sole-owned by the plugin. A personal registration of a same-named hook in any
`settings.json` is retired at release-install time by the operator, prompted by the ownership notice in
`agy-liveness-check.sh`. Installers MUST NOT edit an operator's settings files.

The ownership notice is the ONE agy hook exempt from `.no-agy` — a gate the policed party can switch off
is not a gate. Guarded by `scripts/tests/agy-liveness-check.Tests.ps1`.
```

- [ ] **Step 4: Commit**

```bash
git add clavity-dotnet/plugin/README.md clavity-classic/plugin/README.md docs/agy-disciplines-marker-contract.md
git commit -m "docs(disciplines): publish the hook-ownership rule (D1)"
```

---

### Task 6: Implement the D1 ownership check

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-liveness-check.sh` (then mirror to classic)
- Modify: `scripts/tests/agy-liveness-check.Tests.ps1`

**Do NOT start until Task 4 is committed** — this modifies the SP-D artifact Task 4 audits.

Reuse the settings resolution the hook ALREADY has at lines 57-67. Do not add git-toplevel logic.

- [ ] **Step 1: Write the failing tests**

Append these `It` blocks inside the existing `Describe 'agy-liveness-check.sh'` block in `scripts/tests/agy-liveness-check.Tests.ps1`, before its closing brace. They reuse the file's existing `New-ConfigFixture`, `New-CleanHome` and `Payload` helpers:

```powershell
    It 'REPORTS a personal registration of a shipped hook name (user scope)' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        try {
            $s = Join-Path $cfg 'settings.json'
            @{ enabledPlugins = @{ 'superpowers@superpowers-marketplace' = $true }
               hooks = @{ SessionStart = @( @{ hooks = @( @{ type='command'; command='bash "~/.claude/hooks/agy-liveness-check.sh"' } ) } ) }
            } | ConvertTo-Json -Depth 8 | Set-Content $s -Encoding ascii
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'agy-liveness-check'
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'STILL reports ownership when .no-agy is present (constraint 5)' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        try {
            $s = Join-Path $cfg 'settings.json'
            @{ enabledPlugins = @{ 'superpowers@superpowers-marketplace' = $true }
               hooks = @{ SessionStart = @( @{ hooks = @( @{ type='command'; command='bash "~/.claude/hooks/agy-liveness-check.sh"' } ) } ) }
            } | ConvertTo-Json -Depth 8 | Set-Content $s -Encoding ascii
            New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'suppressed by .no-agy'
            $r.StdErr   | Should -Match 'agy-liveness-check'
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT about ownership when no personal registration exists' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 0
            $r.StdErr   | Should -BeNullOrEmpty
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports the unreadable settings file BUT continues the sweep' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        try {
            $proj = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-proj-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $proj '.claude') -Force | Out-Null
            '{ "hooks": { ,,, ' | Set-Content (Join-Path $proj '.claude/settings.json') -Encoding ascii
            $s = Join-Path $cfg 'settings.json'
            @{ enabledPlugins = @{ 'superpowers@superpowers-marketplace' = $true }
               hooks = @{ SessionStart = @( @{ hooks = @( @{ type='command'; command='bash "~/.claude/hooks/agy-liveness-check.sh"' } ) } ) }
            } | ConvertTo-Json -Depth 8 | Set-Content $s -Encoding ascii
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $proj }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'unreadable'
            $r.StdErr   | Should -Match 'agy-liveness-check'
            Remove-Item $proj -Recurse -Force -ErrorAction SilentlyContinue
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'stays silent when the settings file has no hooks node at all' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.StdErr | Should -Not -Match 'schema unrecognised'
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'picks up a NEW shipped hook name without any test edit (list is derived at runtime)' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        try {
            $shipped = (Get-Content (Join-Path (Split-Path -Parent $script:Hook) 'hooks.json') -Raw | ConvertFrom-Json)
            $names = ($shipped.hooks.PSObject.Properties.Value | ForEach-Object { $_.hooks.command }) -join ' '
            $names | Should -Match 'agy-'
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

- [ ] **Step 2: Run them and verify they FAIL**

Run: `just test-scripts`
Expected: the five new ownership `It` blocks FAIL (the hook has no ownership check yet). The sixth (`picks up a NEW shipped hook name`) may pass immediately — it asserts the fixture, not the hook.

- [ ] **Step 3: Implement the ownership check**

In `clavity-dotnet/plugin/hooks/agy-liveness-check.sh`, make three edits.

**(a)** Move the settings-path resolution block (currently lines 57-67) to sit immediately AFTER the `cwd=` line (line 38) and BEFORE the `.no-agy` branches, so the ownership check can use it. The moved block is:

```bash
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
proj_dir="${CLAUDE_PROJECT_DIR:-$cwd}"
user_settings="$config_dir/settings.json"
proj_settings="$proj_dir/.claude/settings.json"
local_settings="$proj_dir/.claude/settings.local.json"

present=()
for f in "$user_settings" "$proj_settings" "$local_settings"; do
  [ -f "$f" ] && present+=("$f")
done
```

**(b)** Immediately after that block, add the ownership function:

```bash
# --- D1 ownership: a hook this plugin ships must not ALSO be registered personally, or it double-fires.
# The shipped-hook list is derived at runtime from our own hooks.json -- a hardcoded list would fall out of
# sync the first time someone adds a hook, and the tests would keep passing. An unreadable hooks.json is
# reported, never treated as "no shipped hooks" (that would fail the check open). Each settings file is read
# independently: an unreadable one is named and the sweep CONTINUES, so a typo in a project file cannot mask
# a real duplicate in the user file. A settings file with no .hooks node is normal (fresh install) and silent.
ownership_note=""
shipped_json="$(dirname "$0")/hooks.json"
if ! shipped=$(jq -r '[.hooks[][].hooks[].command] | join(" ")' "$shipped_json" 2>/dev/null); then
  ownership_note="[AGY-DISCIPLINES] shipped-hook list unreadable ($shipped_json) - cannot check hook ownership"
else
  for f in "${present[@]}"; do
    if ! personal=$(jq -r '[(.hooks // {})[][].hooks[].command] | join(" ")' "$f" 2>/dev/null); then
      ownership_note="${ownership_note}[AGY-DISCIPLINES] settings unreadable ($f) - ownership not checked for it"$'\n'
      continue
    fi
    for name in $(printf '%s\n' $shipped | grep -oE '[a-z0-9-]+\.sh' | sort -u); do
      case "$personal" in
        *"$name"*) ownership_note="${ownership_note}[AGY-DISCIPLINES] $name is shipped by this plugin AND registered in $f - remove that registration, then restart or /clear this session"$'\n' ;;
      esac
    done
  done
fi
```

**(c)** Emit it from BOTH exit paths. Replace the two `.no-agy` branches (originally lines 43-50) with:

```bash
if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  suppressed="$cwd/.no-agy"; [ -f "$suppressed" ] || suppressed="$HOME/.claude/.no-agy"
  printf '%s\n' "[AGY-DISCIPLINES] suppressed by .no-agy at $suppressed" >&2
  # Constraint 5: ownership is reported EVEN under the kill-switch. A gate the policed party can switch
  # off is not a gate -- otherwise .no-agy plus a kept personal registration hides an override entirely.
  [ -n "$ownership_note" ] && printf '%s' "$ownership_note" >&2
  exit 2
fi
```

and change the healthy exit (originally line 79) from a bare `exit 0` to:

```bash
if [ "$live" = "1" ]; then
  if [ -n "$ownership_note" ]; then
    printf '%s' "$ownership_note" >&2
    exit 2
  fi
  exit 0   # healthy install AND sole ownership: SILENT
fi
```

- [ ] **Step 4: Update the exit-contract comment (constraint 6)**

The header at lines 12-19 documents exactly two end-states. Add the third. Change the sentence beginning `EXIT-CODE CONTRACT:` so it reads:

```
# EXIT-CODE CONTRACT: (1) healthy / superpowers live AND sole hook ownership -> exit 0, no stderr; (2) a
# DETECTION OUTCOME warranting a notice (superpowers not-live incl. corrupt/unreadable settings, .no-agy
# active, or jq missing) -> the line on stderr + exit 2; (3) a shipped hook ALSO registered personally, or
# an unreadable settings/hooks.json blocking that check -> the ownership line on stderr + exit 2. State (3)
# is reported even under .no-agy (D1 constraint 5) -- deliberately, so the kill-switch cannot hide an
# override. Every reachable end-state is one of those three explicit exits.
```

- [ ] **Step 5: Run the tests and verify they pass**

Run: `just test-scripts`
Expected: exit 0, all tests green including the five new ownership blocks.

- [ ] **Step 6: Mutation-check each new guard**

One at a time, revert a guard, re-run `just test-scripts`, confirm the NAMED test goes red, then restore:

| Mutation | Test that must go red |
|---|---|
| Delete the `[ -n "$ownership_note" ]` emit inside the `.no-agy` branch | `STILL reports ownership when .no-agy is present` |
| Change the settings loop's `continue` to `break` | `reports the unreadable settings file BUT continues the sweep` |
| Replace the derived `$shipped` with a hardcoded `agy-after-reminder.sh` | `REPORTS a personal registration of a shipped hook name` |

Record each result. A guard whose removal leaves the suite green is not a guard.

- [ ] **Step 7: Mirror to clavity-classic, byte-identically**

Run:
```bash
cp clavity-dotnet/plugin/hooks/agy-liveness-check.sh clavity-classic/plugin/hooks/agy-liveness-check.sh
diff -q clavity-dotnet/plugin/hooks/agy-liveness-check.sh clavity-classic/plugin/hooks/agy-liveness-check.sh && echo IDENTICAL
just seed-sync-check
```
Expected: `IDENTICAL`, and seed-sync green.

- [ ] **Step 8: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-liveness-check.sh clavity-classic/plugin/hooks/agy-liveness-check.sh scripts/tests/agy-liveness-check.Tests.ps1
git commit -m "feat(disciplines): report a personally-registered shipped hook (D1 enforcement)

The shipped-hook list is derived at runtime from hooks.json, so adding a hook
cannot silently bypass the check. Each settings file is read independently and an
unreadable one is named without aborting the sweep, so a typo in a project file
cannot mask a real duplicate in the user file. A settings file with no hooks node
is normal and stays silent.

Reported even under .no-agy: a gate the policed party can switch off is not a
gate. The exit-code contract gains a documented third state."
```

---

### Task 7: The capstone ledger (D5)

**Files:**
- Create: `docs/agy-capstone-ledger.md`
- Modify: `clavity-dotnet/plugin/skills/agy-capstone/SKILL.md` (then mirror to classic)

- [ ] **Step 1: Create the ledger, seeded ONLY with reconstructible entries**

Create `docs/agy-capstone-ledger.md`:

```markdown
# AGY-CAPSTONE ledger

One row per capstone. Appended before a plan may be declared complete.

**This is a RECORD, not a proof.** Nothing prevents someone appending a GREEN line without running
anything; a self-asserted ledger is the same shape as the re-stamping defect the verify gate removed.
Two things keep it honest, neither a guarantee: the `evidence` column must cite something independently
checkable, and the ledger is reviewed like any other artifact rather than trusted like a gate output.

**`none` is not a permitted evidence value.** A capstone that goes green on its first round still
produces a transcript — the rounds it ran, the lenses it seated, what it tried. Cite that. If there is
nothing to cite, the entry does not go in.

**Absences are meaningful.** SP-0, SP-A, SP-C and SP-D do not appear below. They never had a
reconstructible capstone; their evidence is a verification transcript under
`docs/superpowers/verification/`, which is a different and weaker claim, deliberately not laundered into
this table.

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-07-25 | SP-B agy-capstone skill | 4 | GREEN | folds 2c105ac, 98ffcbd, a879cce, 0f5e3a1 |
| 2026-07-31 | b14bef1..fbb126b | 5 | GREEN | folds 8fcbfa6, a52ef9d, 20834b0, 200c3ff, fbb126b |
```

- [ ] **Step 2: Verify every cited SHA resolves**

Run:
```bash
for s in 2c105ac 98ffcbd a879cce 0f5e3a1 8fcbfa6 a52ef9d 20834b0 200c3ff fbb126b; do
  printf '%s %s\n' "$s" "$(git log -1 --format=%s $s 2>/dev/null || echo 'MISSING')"
done
```
Expected: every line shows a real subject, none shows `MISSING`. A ledger citing a SHA that does not resolve is worse than no ledger. If any is missing, remove that row rather than guessing.

- [ ] **Step 3: Add the ledger step to the agy-capstone skill**

In `clavity-dotnet/plugin/skills/agy-capstone/SKILL.md`, add to the definition-of-done section:

```markdown
- **Record the round in `docs/agy-capstone-ledger.md` before declaring the plan complete.** One row:
  date, commit range, round count, verdict, and evidence that is independently checkable (fold commits,
  or the review transcript). `none` is not a permitted evidence value — a clean first round still
  produces a transcript, so cite it. Without this row a green capstone is indistinguishable from one
  that never ran, which is precisely the gap this ledger exists to close.
```

- [ ] **Step 4: Mirror to classic and verify byte-identical**

Run:
```bash
cp clavity-dotnet/plugin/skills/agy-capstone/SKILL.md clavity-classic/plugin/skills/agy-capstone/SKILL.md
diff -q clavity-dotnet/plugin/skills/agy-capstone/SKILL.md clavity-classic/plugin/skills/agy-capstone/SKILL.md && echo IDENTICAL
just check-agy-skills
just seed-sync-check
```
Expected: `IDENTICAL`, both recipes exit 0.

- [ ] **Step 5: Commit**

```bash
git add docs/agy-capstone-ledger.md clavity-dotnet/plugin/skills/agy-capstone/SKILL.md clavity-classic/plugin/skills/agy-capstone/SKILL.md
git commit -m "feat(agy-capstone): ledger so a green capstone leaves a durable record

A capstone that finds nothing produces no commit, so 'ran and was clean' has been
indistinguishable from 'never ran' -- which is why four sub-projects' completion
claims are unverifiable. The ledger records the round; it is explicitly a record
and not a proof, and 'none' is not a permitted evidence value.

Seeded only with entries that have real evidence in git. The four sub-projects
are absent on purpose: their evidence is a verification transcript, a weaker
claim that is not laundered into a capstone table."
```

---

### Task 8: The release checklist

**Files:**
- Create: `docs/productize-release-checklist.md`

- [ ] **Step 1: Write the checklist**

Create `docs/productize-release-checklist.md`:

```markdown
# Productize release checklist

The productize epic (SP-0 → SP-D) is code-complete but has never shipped: the newest release tag
predates SP-D's commits. This checklist is its closing step.

## Contents the release must carry

- [ ] The four discipline skills in both plugins: `agy-first`, `agy-capstone`, `agy-after` (already
      shipped pre-epic), and the `agy-seam-inject` auto-fire hook.
- [ ] `agy-liveness-check.sh` including the D1 ownership check.
- [ ] The hook-ownership rule in both plugin READMEs.
- [ ] `docs/agy-capstone-ledger.md`.

## Before installing

- [ ] **Close all active Claude Code sessions.** The ownership notice is bound to SessionStart, so
      installing underneath a running session means it never fires while the newly-installed hooks are
      already executing — the double-fire then runs unannounced for the rest of that session.

## After installing

- [ ] Start a session. The ownership notice will name every personally-registered hook that the plugin
      now ships.
- [ ] Remove those registrations from the named settings file(s). **The installer does not do this** —
      those files are yours, and an installer editing them silently is the surprise this design removes.
- [ ] Restart or `/clear` the session so the window closes at a known point.
- [ ] Start a session again and confirm the notice is gone.

## Not in this release

- The clavity-classic ME1 binary-native-vs-bash fork — tracked debt, does not gate (owner ruling).
- Productizing `agy-test-audit` and `AGY-SCOPE` — a follow-on epic; this release closes at four
  disciplines.
```

- [ ] **Step 2: Verify the claim the checklist opens with**

Run:
```bash
git for-each-ref --sort=-creatordate --format='%(refname:short) %(creatordate:short)' refs/tags | head -1
git log --all -i --grep='sp-d' --format='%cs' | head -1
```
Expected: the tag date is EARLIER than the SP-D commit date. If that is no longer true (a release has since been cut), correct the opening sentence rather than shipping a false statement.

- [ ] **Step 3: Commit**

```bash
git add docs/productize-release-checklist.md
git commit -m "docs(release): productize release checklist with the retirement step"
```

---

### Task 9: Record the tracked debt and the follow-on epic

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md`

- [ ] **Step 1: Append both items**

Add to `clavity-dotnet/ROADMAP.md`:

```markdown
## Tracked debt — clavity-classic ME1 guard: binary-native vs bash hook

`docs/superpowers/specs/2026-07-22-ship-agy-disciplines-design.md:134` left this fork open "to resolve
in SP3, via AGY-FIRST". That spec was superseded by the ship-agy-workflow epic, which drops ME1 from
scope, so the fork was orphaned rather than decided. Owner ruling 2026-07-31: it does NOT gate the
productize release. It remains undecided and is recorded here so it stops being invisible.

## Follow-on epic — productize the two later disciplines

`agy-test-audit` (shipped 2026-07-27) and the planned `AGY-SCOPE` postdate the ship-agy-workflow epic
and are not in its model. Owner ruling 2026-07-31: they are a follow-on, not a re-scope — retroactively
widening a stalled epic prevents it closing. This epic closes at four disciplines.
```

- [ ] **Step 2: Commit**

```bash
git add clavity-dotnet/ROADMAP.md
git commit -m "docs(roadmap): record the orphaned ME1 fork and the follow-on discipline epic"
```

---

## Self-review

**Spec coverage.** D1 → Tasks 5 and 6 · D2 → the ordering (Tasks 1-4 precede 6 and 7) · D3 → Task 9 ·
D4 → Task 9 · D5 → Task 7 · D6 → Task 8. Scope item 1 → Tasks 1-4 · item 2 → Task 1 Steps 6-7 ·
item 3 → Tasks 5-6 · item 4 → Task 7 · item 5 → Task 8. All six D1 enforcement constraints map to Task 6:
(1) three settings files → reuses the hook's existing resolution; (2) runtime-derived list → Step 3(b) and
its mutation check; (3) leaf-level schema → the `.hooks // {}` guard plus the silent-when-absent test;
(4) fail loud without aborting → the `continue` branch and its mutation check; (5) `.no-agy` exemption →
Step 3(c) and its named test; (6) exit contract → Step 4.

**Placeholder scan.** No TBD, no "handle edge cases", no "similar to Task N". Every code step carries the
actual code; every command carries its expected output.

**Type consistency.** `ownership_note` is the single accumulator across Task 6 Steps 3(b) and 3(c).
`$shipped` / `$personal` / `$present` are the names used throughout. The test file reuses the existing
`New-ConfigFixture`, `New-CleanHome`, `Payload` helpers rather than introducing parallel ones.

**Deviation from the spec, stated not smuggled.** The spec's git-toplevel project-root resolution is NOT
implemented: `agy-liveness-check.sh:58` already uses `CLAUDE_PROJECT_DIR`, which is the host's own answer
and strictly better than inferring one. This also retires the spec's git-stderr concern, since no
`git rev-parse` call exists to silence. Flagged at the top of this plan under "Correction to the spec".

**Known risk, stated.** Task 6 Step 3(a) MOVES an existing block within a heavily-documented file. The
mirror check in Step 7 and `just test-scripts` in Step 5 are what catch a botched move; the existing 10
`It` blocks must stay green, which is the regression guard on the relocation.

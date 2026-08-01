# Anomaly fix sequencing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every entry in `.clavity/local-anomalies.md` by fixing the underlying defect, in an order where each fix makes the next one cheaper or better-verified.

**Architecture:** Six independent milestones executed in a fixed order — split the test gate so everything after it verifies in seconds; convert the byte-sync gate from an allow-list to auto-discovery so the next milestone's files are gated for free; relocate and fix the VCS consult guard with tests that make a dead guard self-evident; harden the subagent dispatch clause; give `agy-curate` a legal end state; and add a mojibake tripwire inside `curate-commit`. Each milestone is independently committable and a valid stopping point.

**Tech Stack:** bash (hooks), Pester 5 (script tests), just (recipes), jq (manifest comparison), C# / .NET 10 (`Clavity.Ls`), Rust (`clavity-classic`), xUnit, `cargo test`.

**Spec:** `docs/superpowers/specs/2026-08-01-anomaly-fix-sequencing-design.md` — owner-approved, AGY-AFTER GREEN at round 4 (7 findings folded).

---

## Verified state — measured at `2834622`, re-verify in each Step 0

Every citation below was grep-verified before this plan was written. **Re-verify in the task's Step 0; if any differs, STOP and report `STATE_MISMATCH: <what>` rather than adapting.**

| Fact | Value |
|---|---|
| `justfile:91-92` | `test-scripts:` → `pwsh -c "Invoke-Pester scripts/tests -Output Detailed -CI"` |
| `scripts/tests/` | 24 `*.Tests.ps1` files, 358 tests total, ~586-917s wall clock |
| `scripts/check-seed-artifacts-synced.sh:15-27` | `for rel in \` + 12 entries ending `knowledge/agy-capabilities.md ; do` |
| same file `:77` | `sp_sel=` deny-list, currently naming `agy-drive-session-reset\.sh` |
| Divergent files (measured `find`+`diff`) | classic-only: `hooks/agy-drive-session-reset.sh`, `skills/driving/SKILL.md`, `skills/responder/SKILL.md`; dotnet-only: `skills/ls-driving/SKILL.md`, `skills/ls-pairing/SKILL.md` |
| Guard files | `~/.claude/hooks/agy-consult-guard-lib.sh` (96 lines), `-post.sh` (91), `-pre.sh` (42) = 229 |
| Guard classifier | `agy-consult-guard-lib.sh:55-64`, `agy_guard_category()` |
| Guard's only env dep | `${TMPDIR:-/tmp}` at `agy-consult-guard-lib.sh:43` |
| `~/.claude/settings.json:46,66` | `"matcher": "Bash\|PowerShell\|mcp__plugin_clavity-dotnet_clavity-ls__agy_ask"` |
| `~/.claude/settings.json:50,70` | the `"command"` entries beneath those matchers |
| `~/.claude/settings.json:108` | `"clavity@clavity-dotnet": true` — plugin named `clavity`, marketplace `clavity-dotnet` |
| Live MCP tool name | `mcp__plugin_clavity_clavity-ls__agy_ask` |
| `hooks.json` events (both plugins) | `PostToolUse`, `PreToolUse`, `SessionStart` |
| `hooks.json` `PreToolUse` (both) | one entry, `"matcher":"Skill"` → `agy-seam-inject.sh` |
| `scripts/check-plugin-namespace.ps1` | live — invoked by `lefthook.yml:46` |
| `open-issues/SKILL.md:119` | `## Dispatching a subagent - the clause every dispatch must carry` |
| `open-issues/SKILL.md:126` | `> **ANOMALIES.** If you notice something wrong...` |
| `agy-seam-inject.sh:78` | `  anomaly-dispatch)` |
| `agy-autotrain/skills/agy-curate/SKILL.md:122` | `## Promotion rubric (curation-fatigue guard — do not skip)` |
| same `:126` | `- An **Empirical Assumption** promotes only after a **100% pass in the verify harness**:` |
| same `:217`, `:219` | `## Finish`, `- **Empty the inbox** ...` |
| `CliVerbs.cs:79-83` | over-cap branch → `return 2` |
| `CliVerbs.cs:87` | `GoldenHeader.CommitGrowth(dir, new string(buffer, 0, total)); return 0;` |
| `clavity-classic/src/main.rs:700` | `fn curate_commit() -> i32 {` |
| `CliVerbsTests.cs:26` | `NonAsciiSample` — contains `⚠️`, an em-dash, `≠`; **no** CP437 signature |
| `CliVerbsTests.cs:31`, `:44` | the two non-ASCII round-trip pinning tests |

**Tripwire signatures, verified against `~/.clavity/golden-header.growth.md.corrupt-backup-2026-07-21`:**
- CP437 lead byte `Γ` = `ce 93` — 21 occurrences in the corrupt file, 0 in the clean one.
- Mangled em-dash `ΓÇö` = `ce 93 c3 87 c3 b6` — 15 occurrences.
- Mangled warning sign `ΓÜá` = `ce 93 c3 9c c3 a1` — 1 occurrence.
- CP1252 prefix `â€` = `c3 a2 e2 82 ac`.

---

## File structure

| File | Milestone | Responsibility |
|---|---|---|
| `justfile` | M1 | split `test-scripts` into `test-scripts-fast` / `test-scripts-slow`, keep `test-scripts` as the everything recipe |
| `scripts/tests/_partition.md` | M1 | records which suites are slow and the measured runtime that put them there |
| `scripts/check-seed-artifacts-synced.sh` | M2 | allow-list → discovery + deny-list |
| `scripts/tests/check-seed-artifacts-synced.Tests.ps1` | M2 | discovery coverage tests |
| `clavity-{dotnet,classic}/plugin/hooks/agy-consult-guard-{lib,pre,post}.sh` | M3 | the relocated guard, byte-identical across plugins |
| `clavity-{dotnet,classic}/plugin/hooks/hooks.json` | M3 | Pre/PostToolUse registration |
| `scripts/tests/agy-consult-guard.Tests.ps1` | M3 | integration test: synthetic payloads, real temp repo |
| `scripts/check-plugin-namespace.ps1` | M3 | assert hook matchers reference a real plugin namespace |
| `clavity-{dotnet,classic}/plugin/skills/open-issues/SKILL.md` | M4 | dispatch file allow-list |
| `clavity-{dotnet,classic}/plugin/hooks/agy-seam-inject.sh` | M4 | directive text |
| `agy-autotrain/skills/agy-curate/SKILL.md` | M5, M6 | HELD state; ASCII-only authoring policy |
| `clavity-dotnet/src/Clavity.Ls/CliVerbs.cs` | M6 | tripwire before `CommitGrowth` |
| `clavity-classic/src/main.rs` | M6 | tripwire in `curate_commit()` |
| `clavity-dotnet/tests/Clavity.Ls.Tests/CliVerbsTests.cs` | M6 | tripwire tests **added**, existing two **unmodified** |

---

### Task 1 (M1 — T): partition the test gate

**Closes anomaly #4.**

**Files:**
- Modify: `justfile:91-92`
- Create: `scripts/tests/_partition.md`

- [ ] **Step 0: State verification**

Confirm each; if any differs, STOP and report `STATE_MISMATCH: <what>`:
1. `justfile:91-92` is exactly:
   ```
   test-scripts:
       pwsh -c "Invoke-Pester scripts/tests -Output Detailed -CI"
   ```
2. `ls scripts/tests/*.Tests.ps1 | wc -l` returns `24`.
3. `lefthook.yml` contains `run: just seed-sync-check` (proves lefthook is the pre-push gate surface).

- [ ] **Step 1: Measure per-file runtime — this is the partition input, not a guess**

Run:
```bash
pwsh -c "foreach (\$f in Get-ChildItem scripts/tests/*.Tests.ps1) { \$sw=[Diagnostics.Stopwatch]::StartNew(); \$r=Invoke-Pester \$f.FullName -Output None -PassThru; \$sw.Stop(); '{0,-45} {1,7:N1}s {2,4} tests' -f \$f.Name, \$sw.Elapsed.TotalSeconds, \$r.TotalCount }"
```
Expected: 24 lines, each naming a file, its seconds and its test count. **Record this output verbatim into `scripts/tests/_partition.md`** — it is the evidence for the split and the thing a future reader needs when the partition looks arbitrary.

Sum the test counts. **It must equal 358.** If it does not, STOP and report `STATE_MISMATCH: test count is <n>, not 358` — the plan's oracle depends on that number.

- [ ] **Step 2: Choose the cut, by measurement**

Sort the Step 1 output descending by seconds. **SLOW = every file whose measured runtime is >= 20s. FAST = the rest.** Do not partition by subject, filename or intuition; the threshold is the rule, and `_partition.md` records why each file landed where it did.

If the FAST set's summed runtime exceeds 60s, lower the threshold to 10s and re-derive. If it still exceeds 60s, STOP and report `STATE_MISMATCH: fast set cannot reach 60s at a 10s threshold` — that means the suite's cost is not concentrated in a few files and this milestone needs redesign, not a fudged threshold.

- [ ] **Step 3: Write `scripts/tests/_partition.md`**

```markdown
# Test suite partition

`just test-scripts` ran 358 tests in a single Pester invocation, measured at 917s, 650s, 586s and 590s on
four consecutive runs against a 600s foreground tool cap. It STRADDLED the cap: it worked until it did not.

The suite is now split by MEASURED per-file runtime, not by subject. Threshold: a file runs in the SLOW
recipe if it measured >= 20s.

- `just test-scripts-fast` — the pre-push and inner-loop gate. Target: well under 60s.
- `just test-scripts-slow` — everything else. Runs on the same pre-push hook, and must be BACKGROUNDED by
  an agent because it exceeds the foreground tool cap.
- `just test-scripts` — both, unchanged in meaning: still every test.

**Every test remains reachable from some recipe. The sum of the two halves is 358.** If you move a file
between halves, re-measure and update the table below; do not edit it from memory.

## Measured runtimes

<paste the Step 1 output verbatim here>
```

Replace `<paste the Step 1 output verbatim here>` with the actual Step 1 output. Leaving the angle-bracket text in place is a plan failure.

- [ ] **Step 4: Rewrite the justfile recipes**

Replace `justfile:91-92` with the following. `<FAST-FILES>` and `<SLOW-FILES>` are space-separated `scripts/tests/<name>.Tests.ps1` paths from Step 2:

```
# Fast script gate: the pre-push and inner-loop recipe. Partitioned by MEASURED runtime, not by subject
# (see scripts/tests/_partition.md). Every test is still reachable: fast + slow == the whole suite.
test-scripts-fast:
    pwsh -c "Invoke-Pester @('<FAST-FILES>') -Output Detailed -CI"

# Slow script gate. EXCEEDS the 600s foreground tool cap - an agent MUST background this and read the
# result from the task output file, never run it in the foreground.
test-scripts-slow:
    pwsh -c "Invoke-Pester @('<SLOW-FILES>') -Output Detailed -CI"

# The whole suite, unchanged in meaning. Same cap warning as test-scripts-slow.
test-scripts:
    pwsh -c "Invoke-Pester scripts/tests -Output Detailed -CI"
```

- [ ] **Step 5: Wire the cadence — the count alone is gameable**

In `lefthook.yml`, in the same job list that already contains `run: just seed-sync-check`, add:

```yaml
    test-scripts-fast:
      run: just test-scripts-fast
```

**Do NOT add `test-scripts-slow` to lefthook** — it exceeds the cap and would make every push unusable. Instead add this comment directly above the `test-scripts-slow` recipe in the justfile:

```
# CADENCE: not on the pre-push hook (it exceeds the tool cap). Run it before any release, and after any
# change to a file listed as SLOW in scripts/tests/_partition.md. A recipe nobody runs is a retired test.
```

- [ ] **Step 6: Verify the split — the three oracles**

```bash
just test-scripts-fast 2>&1 | tail -3
```
Expected: `Failed: 0`, completing in well under 60s.

```bash
just test-scripts-slow 2>&1 | tail -3
```
**Run this with `run_in_background` and read the task output file** — it exceeds the foreground cap.
Expected: `Failed: 0`.

**The count oracle:** add the two recipes' `Tests Passed` numbers. **They must sum to 358.** If they do not, a test was dropped or double-counted — STOP and report it rather than adjusting the expected number.

- [ ] **Step 7: Commit**

```bash
git add justfile lefthook.yml scripts/tests/_partition.md
git commit -m "fix(tests): split the script gate by measured runtime

just test-scripts straddled the 600s foreground tool cap - measured at 917s,
650s, 586s and 590s across four consecutive runs. Straddling is worse than being
reliably over: it works until it does not.

Split by MEASURED per-file runtime, never by subject, with the measurements
recorded in scripts/tests/_partition.md so a later reader can see why each file
landed where it did. The fast recipe joins the pre-push hook; the slow one keeps
a stated cadence in a comment, because a recipe nobody runs is a retired test.

Both halves sum to 358 tests - the guard against making the fast number look good
by dropping coverage."
```

---

### Task 2 (M2 — S): auto-discovery sync gate

**Closes anomaly #6.** **Do NOT start until Task 1 is committed.**

**Files:**
- Modify: `scripts/check-seed-artifacts-synced.sh:15-27`
- Modify: `scripts/tests/check-seed-artifacts-synced.Tests.ps1`

- [ ] **Step 0: State verification**

1. `scripts/check-seed-artifacts-synced.sh:15` is `for rel in \` and `:25` is `  knowledge/agy-capabilities.md ; do`.
2. `scripts/check-seed-artifacts-synced.sh:77` begins `sp_sel=` and its `test(...)` names `agy-drive-session-reset\.sh`.
3. This command prints exactly five paths:
   ```bash
   diff <(cd clavity-dotnet/plugin && find hooks skills knowledge -type f | sort) \
        <(cd clavity-classic/plugin && find hooks skills knowledge -type f | sort) | grep '^[<>]'
   ```
   Expected: `> hooks/agy-drive-session-reset.sh`, `< skills/ls-driving/SKILL.md`, `< skills/ls-pairing/SKILL.md`, `> skills/driving/SKILL.md`, `> skills/responder/SKILL.md`.

If the five differ, STOP and report `STATE_MISMATCH: divergent set is <actual>` — the deny-list must be measured, never carried from a summary. (An earlier draft of the spec got this exact list wrong by copying it from a peer's message.)

- [ ] **Step 1: Write the failing test**

Append to `scripts/tests/check-seed-artifacts-synced.Tests.ps1`, before its final closing brace:

```powershell
    It 'FIRES when a new shared file exists in only one plugin' {
        # The defect this milestone fixes: under the old allow-list, a file nobody enrolled was never
        # compared, so it could exist in one plugin only and the gate stayed green. Omission was
        # indistinguishable from synchronisation.
        $probe = 'clavity-dotnet/plugin/skills/zz-discovery-probe/SKILL.md'
        New-Item -ItemType Directory -Path (Split-Path $probe) -Force | Out-Null
        Set-Content $probe "---`nname: zz-discovery-probe`n---`nprobe`n" -Encoding ascii
        try {
            $out = & bash scripts/check-seed-artifacts-synced.sh 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            ($out -join "`n") | Should -Match 'zz-discovery-probe'
        } finally { Remove-Item (Split-Path $probe) -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'stays GREEN for every intentionally-divergent twin' {
        # The five files that legitimately exist in one plugin only. If discovery flagged these the gate
        # would be permanently red and would be routed around.
        $out = & bash scripts/check-seed-artifacts-synced.sh 2>&1
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Not -Match 'agy-drive-session-reset|ls-driving|ls-pairing|skills/driving|skills/responder'
    }

    It 'still FIRES when an enrolled shared file differs in content' {
        # Regression guard: discovery must not lose the behaviour the allow-list already had.
        $f = 'clavity-classic/plugin/hooks/agy-after-reminder.sh'
        $orig = Get-Content $f -Raw
        try {
            Add-Content $f "`n# discovery drift probe`n"
            & bash scripts/check-seed-artifacts-synced.sh 2>&1 | Out-Null
            $LASTEXITCODE | Should -Not -Be 0
        } finally { Set-Content $f $orig -NoNewline }
    }
```

- [ ] **Step 2: Run them and verify the FIRST goes RED**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-seed-artifacts-synced.Tests.ps1 -Output Detailed -CI"`

Expected: `FIRES when a new shared file exists in only one plugin` **FAILS** (the allow-list ignores the probe, so the gate exits 0). The other two pass already — they describe behaviour the allow-list also has. **Only one of the three can go red here, and that is correct, not a shortfall.**

- [ ] **Step 3: Replace the allow-list with discovery**

In `scripts/check-seed-artifacts-synced.sh`, replace lines 15-27 (from `for rel in \` through the `done` that closes that loop) with:

```bash
# DISCOVERY, not an enrolment list. Every file under the three SHARED trees is compared unless it is named
# in the divergence deny-list below. The previous form was an allow-list of 12 explicit paths, which failed
# OPEN: a shared file nobody added was silently never compared, so it could exist in one plugin only and
# the gate stayed green. MEASURED before this change: a skill created in clavity-dotnet alone left
# `just seed-sync-check` GREEN. Omission was indistinguishable from synchronisation.
#
# The deny-list names files that legitimately exist in ONE plugin only. It is MEASURED, never assumed --
# regenerate it with:
#   diff <(cd clavity-dotnet/plugin && find hooks skills knowledge -type f | sort) \
#        <(cd clavity-classic/plugin && find hooks skills knowledge -type f | sort)
# Adding a genuinely variant-specific file makes this gate FAIL until it is named here. That is
# fail-closed and intended: the failure mode inverts from "silently unchecked" to "loudly over-checked".
divergent() {
  case "$1" in
    hooks/agy-drive-session-reset.sh) return 0 ;;   # classic-only: driver-guidance reset
    skills/driving/SKILL.md)          return 0 ;;   # classic transport twin of ls-driving
    skills/responder/SKILL.md)        return 0 ;;   # classic transport twin of ls-pairing
    skills/ls-driving/SKILL.md)       return 0 ;;   # dotnet transport twin of driving
    skills/ls-pairing/SKILL.md)       return 0 ;;   # dotnet transport twin of responder
    *) return 1 ;;
  esac
}

# Union of both trees, so a file missing from EITHER side is caught (a one-sided walk would only catch
# files missing from the other plugin, never from its own).
for rel in $( { (cd "$D" && find hooks skills knowledge -type f 2>/dev/null)
                (cd "$C" && find hooks skills knowledge -type f 2>/dev/null); } | sort -u ); do
  divergent "$rel" && continue
  if [ ! -f "$D/$rel" ]; then
    echo "SEED-DRIFT: $rel exists in clavity-classic/plugin but NOT in clavity-dotnet/plugin" >&2
    status=1
  elif [ ! -f "$C/$rel" ]; then
    echo "SEED-DRIFT: $rel exists in clavity-dotnet/plugin but NOT in clavity-classic/plugin" >&2
    status=1
  elif ! diff -q "$D/$rel" "$C/$rel" >/dev/null 2>&1; then
    echo "SEED-DRIFT: $rel differs between clavity-dotnet/plugin and clavity-classic/plugin" >&2
    status=1
  fi
done
```

**SCOPE BOUNDARY — do not exceed it.** This walks `hooks/`, `skills/` and `knowledge/` only. It does not become a general repository linter, it does not police files outside those trees, and it adds no encoding rule (that lives in Task 6). If implementing this requires touching anything outside those three trees, STOP and report it — the scope has slipped.

- [ ] **Step 4: Run the tests and verify all three pass**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-seed-artifacts-synced.Tests.ps1 -Output Detailed -CI"`
Expected: `Failed: 0`.

- [ ] **Step 5: Mutation-check the guards**

One at a time, apply the mutation **to the script**, re-run only this test file, confirm the NAMED test goes red, then restore. **A guard whose removal leaves the file green is not a guard — report it rather than papering over it.**

| Mutation (in `check-seed-artifacts-synced.sh`) | Test that must go red |
|---|---|
| Delete the `[ ! -f "$D/$rel" ]` branch | `FIRES when a new shared file exists in only one plugin` |
| Add `skills/` to `divergent()` so every skill is skipped | `still FIRES when an enrolled shared file differs in content` |
| Remove `hooks/agy-drive-session-reset.sh` from `divergent()` | `stays GREEN for every intentionally-divergent twin` |

- [ ] **Step 6: Full gate**

```bash
just test-scripts-fast
```
Expected: `Failed: 0`. Then run `just test-scripts-slow` with `run_in_background` and confirm `Failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add scripts/check-seed-artifacts-synced.sh scripts/tests/check-seed-artifacts-synced.Tests.ps1
git commit -m "fix(seed-gate): discover shared files instead of enrolling them

The file list was an ALLOW-LIST of 12 explicit paths, so any shared file nobody
added was silently never compared. MEASURED: a skill created in clavity-dotnet
alone left just seed-sync-check GREEN. Omission was indistinguishable from
synchronisation, and the gate reported the same green for both.

Discovery now walks the union of both plugins' hooks/skills/knowledge trees and
compares everything not named in a MEASURED five-file divergence deny-list. The
union matters: a one-sided walk only catches files missing from the other plugin,
never from its own.

The failure mode inverts from silently-unchecked to loudly-over-checked. A new
variant-specific file now fails the gate until it is named - fail-closed, and the
point."
```

---

### Task 3 (M3 — G): relocate and fix the consult guard

**Closes anomalies #1 and #2.** **Do NOT start until Task 2 is committed** — discovery is what gates the three new files automatically, and their arrival is the live proof it works.

**Files:**
- Create: `clavity-dotnet/plugin/hooks/agy-consult-guard-{lib,pre,post}.sh` (moved)
- Create: `clavity-classic/plugin/hooks/agy-consult-guard-{lib,pre,post}.sh` (byte-identical mirrors)
- Modify: `clavity-{dotnet,classic}/plugin/hooks/hooks.json`
- Create: `scripts/tests/agy-consult-guard.Tests.ps1`
- Modify: `scripts/check-plugin-namespace.ps1`

- [ ] **Step 0: State verification**

1. All three guard files exist under `~/.claude/hooks/` with line counts 96 / 42 / 91.
2. `agy-consult-guard-lib.sh:60` is:
   ```bash
   printf '%s' "$c" | grep -Eq 'clavity[[:space:]]+ask([[:space:]]|$)'         && { echo sync;     return; }
   ```
3. `jq -c '.hooks.PreToolUse' clavity-dotnet/plugin/hooks/hooks.json` returns exactly one entry, matcher `"Skill"`.
4. `grep -c 'agy-consult-guard' scripts/check-plugin-namespace.ps1` returns `0`.

- [ ] **Step 1: Copy the three files into both plugins, unmodified**

```bash
for f in lib pre post; do
  cp ~/.claude/hooks/agy-consult-guard-$f.sh clavity-dotnet/plugin/hooks/agy-consult-guard-$f.sh
  cp ~/.claude/hooks/agy-consult-guard-$f.sh clavity-classic/plugin/hooks/agy-consult-guard-$f.sh
done
just seed-sync-check
```
Expected: **GREEN, with no enrolment edit whatsoever.** That is Task 2's discovery gating three brand-new files on arrival — the non-synthetic proof the previous milestone works. If this needs a manual enrolment, Task 2 is incomplete; STOP and report it.

- [ ] **Step 2: Fix the classifier — anchor on command position**

In **both** copies of `agy-consult-guard-lib.sh`, replace the three `grep -Eq` lines (at `:60-62` in the original) with:

```bash
  # Anchor on COMMAND POSITION, not any occurrence. The previous form grepped the WHOLE command string,
  # so a command whose TEXT merely mentioned the consult CLI - a commit message, a heredoc - was
  # classified as a review-only consult, and the driver's own commit inside that same call was then
  # reported as the peer modifying version control. REPRODUCED: two identical commits differing only in
  # message text gave warn vs silent. A consult invocation can only start the string or follow a shell
  # separator, so require that.
  local anchor='(^|[;&|]|&&|\|\|)[[:space:]]*clavity[[:space:]]+'
  printf '%s' "$c" | grep -Eq "${anchor}ask([[:space:]]|$)"         && { echo sync;     return; }
  printf '%s' "$c" | grep -Eq "${anchor}send([[:space:]]|$)"        && { echo open;     return; }
  printf '%s' "$c" | grep -Eq "${anchor}await-reply([[:space:]]|$)" && { echo terminal; return; }
```

- [ ] **Step 3: Register in both manifests**

In **both** `hooks.json` files, add a SECOND `PreToolUse` entry after the existing `"Skill"` entry, and a `PostToolUse` entry after the existing two. The `PreToolUse` block becomes:

```json
    "PreToolUse": [
      { "matcher": "Skill", "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-seam-inject.sh\"" } ] },
      { "matcher": "Bash|PowerShell|mcp__.*agy_ask", "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-consult-guard-pre.sh\"" } ] }
    ]
```

and append to `PostToolUse`:

```json
      { "matcher": "Bash|PowerShell|mcp__.*agy_ask", "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-consult-guard-post.sh\"" } ] }
```

**The matcher is a PATTERN and all three alternatives are required.** `mcp__.*agy_ask` alone drops `Bash|PowerShell`, which are the only tokens that fire the guard on the CLI consult path — the fix for a guard dead on the MCP path would kill it on the shell path instead. The pattern form is deliberate: the guard died because a literal tool name drifted when the plugin was installed under a marketplace whose name differs from the plugin's (`settings.json:108`, `"clavity@clavity-dotnet": true`), and a literal is not even stable per-machine.

**Both plugins must receive identical additions** — Task 2's gate compares the `PreToolUse` and `PostToolUse` blocks byte-identically and will fail otherwise.

- [ ] **Step 4: Write the integration test**

Create `scripts/tests/agy-consult-guard.Tests.ps1`:

```powershell
Describe 'agy-consult-guard' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Pre  = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh'
        $script:Post = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh'

        function New-GuardRepo {
            $d = Join-Path ([IO.Path]::GetTempPath()) ("guard-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            Push-Location $d
            git init -q .; git config user.email t@t; git config user.name t
            Set-Content (Join-Path $d 'a.txt') 'one' -Encoding ascii
            git add a.txt; git commit -qm init
            Pop-Location
            return $d
        }
        function Payload { param([string]$Tool, [string]$Cmd, [string]$Cwd)
            @{ tool_name = $Tool; tool_input = @{ command = $Cmd }; cwd = ($Cwd -replace '\\','/'); session_id = 'guardtest' } | ConvertTo-Json -Compress
        }
    }

    It 'WARNS when version control changes across an MCP consult' {
        # The primary path. The guard was dead here for an unknown period because its matcher named a
        # tool id that no longer exists, and a dead hook cannot report its own absence.
        $r = New-GuardRepo
        try {
            $p = Payload 'mcp__plugin_clavity_clavity-ls__agy_ask' '' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'b.txt' 'two' -Encoding ascii; git add b.txt; git commit -qm peer; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT across an MCP consult that changed nothing' {
        $r = New-GuardRepo
        try {
            $p = Payload 'mcp__plugin_clavity_clavity-ls__agy_ask' '' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Not -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'WARNS when version control changes across a CLI consult' {
        $r = New-GuardRepo
        try {
            $p = Payload 'Bash' 'clavity ask "review this"' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'c.txt' 'three' -Encoding ascii; git add c.txt; git commit -qm peer; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT treat a commit whose MESSAGE mentions the consult CLI as a consult' {
        # The false-positive that trained the operator to ignore the guard. Two identical commits
        # differing only in message text gave warn vs silent.
        $r = New-GuardRepo
        try {
            $p = Payload 'Bash' 'git commit -m "docs: explain clavity ask usage"' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'd.txt' 'four' -Encoding ascii; git add d.txt; git commit -qm mine; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Not -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'ships as pure ASCII' {
        foreach ($f in @($script:Pre, $script:Post)) {
            ($([IO.File]::ReadAllBytes($f)) | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        }
    }
}
```

- [ ] **Step 5: Verify RED before GREEN — non-negotiable**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-consult-guard.Tests.ps1 -Output Detailed -CI"` **against the pre-Step-2 classifier and pre-Step-3 manifests** (stash Steps 2-3 if already applied: `git stash push clavity-dotnet/plugin/hooks clavity-classic/plugin/hooks`).

Expected RED: `does NOT treat a commit whose MESSAGE mentions the consult CLI as a consult` **must FAIL** — that is the false positive, and it is the one this milestone exists to remove.

Then restore (`git stash pop`) and re-run. Expected: `Failed: 0`.

**A guard test never observed failing proves nothing, and "never observed failing" is exactly how this guard reached production dead.** If the false-positive test passes before Step 2, STOP and report it — either the fixture does not reproduce the defect or the classifier already changed.

- [ ] **Step 6: Add the namespace assertion**

Append to `scripts/check-plugin-namespace.ps1`, before its final exit:

```powershell
# Hook matchers must not name a plugin-qualified MCP tool LITERALLY. The consult guard was dead on its
# primary path because its matcher named `mcp__plugin_clavity-dotnet_clavity-ls__agy_ask` while the live
# tool is `mcp__plugin_clavity_clavity-ls__agy_ask` -- the plugin is NAMED clavity and installed FROM the
# marketplace clavity-dotnet, and the matcher used the marketplace name. Two similar identifiers, wrong
# one chosen, and a hook that never fires cannot report its own absence. Require the pattern form.
$literalMatchers = @()
foreach ($manifest in @(
    'clavity-dotnet/plugin/hooks/hooks.json',
    'clavity-classic/plugin/hooks/hooks.json')) {
    $json = Get-Content (Join-Path $Root $manifest) -Raw | ConvertFrom-Json
    foreach ($event in $json.hooks.PSObject.Properties) {
        foreach ($group in $event.Value) {
            if ($group.matcher -match 'mcp__plugin_[A-Za-z0-9-]+_') {
                $literalMatchers += "${manifest}: $($group.matcher)"
            }
        }
    }
}
if ($literalMatchers.Count -gt 0) {
    Write-Error ("Hook matcher names a plugin-qualified MCP tool literally; use a pattern such as " +
                 "'mcp__.*agy_ask' instead:`n  " + ($literalMatchers -join "`n  "))
    exit 1
}
```

- [ ] **Step 7: Verify the namespace assertion is not vacuous**

```bash
pwsh -File scripts/check-plugin-namespace.ps1 ; echo "clean=$?"
```
Expected: `clean=0`.

Then mutate: temporarily change the dotnet manifest's guard matcher to `Bash|PowerShell|mcp__plugin_clavity_clavity-ls__agy_ask` and re-run.
Expected: **non-zero, naming that manifest.** Restore with `git checkout clavity-dotnet/plugin/hooks/hooks.json`, or by re-editing if not yet committed.

If the mutated run passes, the assertion does not gate and that is the bug to fix.

- [ ] **Step 8: Retire the personal copies — but only after proving the shipped ones work**

Remove the guard's registration from `~/.claude/settings.json` (the two `matcher` blocks at `:46` and `:66` and their `hooks` arrays), so the guard runs once from the plugin rather than twice from two sources.

**Do NOT delete `~/.claude/hooks/agy-consult-guard-*.sh`.** Rename them instead:
```bash
for f in lib pre post; do
  mv ~/.claude/hooks/agy-consult-guard-$f.sh ~/.claude/hooks/agy-consult-guard-$f.sh.superseded-by-plugin-2026-08-01
done
```
A rename is reversible in one command and leaves evidence of what happened; a delete is neither. **`~/.claude/settings.json` is the operator's file — confirm with them before editing it.**

- [ ] **Step 9: Full gate + commit**

```bash
just test-scripts-fast && just seed-sync-check && pwsh -File scripts/check-plugin-namespace.ps1
```
Expected: all three clean. Then `just test-scripts-slow` backgrounded, `Failed: 0`.

```bash
git add clavity-dotnet/plugin/hooks clavity-classic/plugin/hooks scripts/tests/agy-consult-guard.Tests.ps1 scripts/check-plugin-namespace.ps1
git commit -m "fix(consult-guard): ship the VCS guard from the plugins, and fix both defects

The guard existed ONLY in the operator's personal config: unversioned, untested,
absent from every installer, uncovered by the sync gate, and one machine rebuild
from gone - while every sibling hook of its family shipped inside the plugins
with all of those properties. Its only environment dependency is TMPDIR, so
living there was an accident of how it was built, not a property of what it does.

It was also broken two ways, both reproduced. It never fired on the MCP consult
path, because its matcher named the MARKETPLACE (clavity-dotnet) where the live
tool names the PLUGIN (clavity) - two similar identifiers, wrong one chosen. And
it classified a shell call by grepping the WHOLE command string, so a commit
whose MESSAGE mentioned the consult CLI was treated as a review-only consult and
the driver's own commit was reported as the peer modifying version control.
Silent where it mattered, noisy where it did not.

The matcher is now a pattern, not a corrected literal: a literal is what broke,
on a naming distinction the operator controls at install time. Over-matching
costs a clean diff; under-matching costs the guard silently not existing.

Enrolment in the sync gate needed no edit at all - discovery picked the three new
files up on arrival, which is the live proof the previous milestone works.

The integration test was observed RED on the false-positive case before the fix.
A guard test never seen to fail proves nothing, and never-seen-to-fail is exactly
how this guard reached production dead."
```

---

### Task 4 (M4 — D): dispatch file allow-list

**Closes anomaly #5.** **Do NOT start until Task 3 is committed.**

**Files:**
- Modify: `clavity-{dotnet,classic}/plugin/skills/open-issues/SKILL.md` (after `:126`)
- Modify: `clavity-{dotnet,classic}/plugin/hooks/agy-seam-inject.sh` (the `anomaly-dispatch)` arm at `:78`)
- Modify: `scripts/tests/agy-seam-inject.Tests.ps1`

- [ ] **Step 0: State verification**

1. `open-issues/SKILL.md:119` is `## Dispatching a subagent - the clause every dispatch must carry`.
2. `open-issues/SKILL.md:126` begins `> **ANOMALIES.** If you notice something wrong`.
3. `agy-seam-inject.sh:78` is `  anomaly-dispatch)`.
4. `scripts/tests/agy-seam-inject.Tests.ps1` has 13 `It` blocks.

- [ ] **Step 1: Add the file-allow-list clause to the skill**

In **both** copies of `open-issues/SKILL.md`, immediately after the blockquote that ends `...silence is indistinguishable from not having looked.`, insert:

```markdown
> **FILES.** This dispatch may create or modify ONLY the files listed here:
> `<list every path the subagent is permitted to touch>`. Touching anything else - including a file that
> seems obviously related, a test you think should be updated, or a doc you think is now stale - is out of
> bounds. If the task cannot be completed within that list, STOP and report
> `SCOPE: needs <path> because <reason>` rather than widening it yourself.

**The driver verifies this, and that half is the one that historically failed.** After the subagent
returns, run `git status --short` and compare the actual change set against the list you gave it. A
subagent once wrote to a file outside its named set, and nothing detected it except the driver happening
to look. Naming the list without checking it afterwards is theatre: the list is a statement of intent, and
the diff is the only evidence.
```

- [ ] **Step 2: Extend the seam directive**

In **both** copies of `agy-seam-inject.sh`, in the `anomaly-dispatch)` arm, replace the sentence beginning `(1) EVERY implementer dispatch you write MUST carry the anomaly clause verbatim` with:

```
(1) EVERY implementer dispatch you write MUST carry TWO clauses verbatim from the `open-issues` skill: the anomaly clause under "Dispatching a subagent", and the FILES clause naming every path that dispatch may touch. Then, when the subagent returns, run `git status --short` and compare the real change set against the list you gave it - a subagent has written outside its named set before, and the list is worthless without the diff.
```

- [ ] **Step 3: Add the tests**

Append to `scripts/tests/agy-seam-inject.Tests.ps1`, before its final closing brace:

```powershell
    It 'the dispatch directive demands a FILES allow-list' {
        $out = Invoke-Hook 'superpowers:subagent-driven-development'
        $out | Should -Match 'FILES clause'
        $out | Should -Match 'git status --short'
    }
```

- [ ] **Step 4: RED then GREEN**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-seam-inject.Tests.ps1 -Output Detailed -CI"`
Before Step 2: the new block FAILS. After: `Failed: 0`, 14 blocks.

- [ ] **Step 5: Mutation-check**

| Mutation (in `agy-seam-inject.sh`) | Test that must go red |
|---|---|
| Remove `FILES clause` from the `anomaly-dispatch` emit | `the dispatch directive demands a FILES allow-list` |
| Remove `git status --short` from the same emit | `the dispatch directive demands a FILES allow-list` |

- [ ] **Step 6: Sync-check, gate, commit**

```bash
just seed-sync-check && just test-scripts-fast
```
Expected: both clean. The two mirrored skill files and two mirrored hooks must be byte-identical — Task 2's discovery compares them.

```bash
git add clavity-dotnet/plugin clavity-classic/plugin scripts/tests/agy-seam-inject.Tests.ps1
git commit -m "feat(dispatch): name the files a subagent may touch, and diff afterwards

A dispatched subagent wrote to a file outside the set it was told to touch, and
nothing detected it except the driver happening to look. Nothing prevented it and
nothing still does - what changes is that the expectation now lives in the
artifact both parties read, instead of in one driver's habits.

Two halves, and the second is the one that failed before: the dispatch states its
file allow-list, and the driver compares the real change set against it when the
subagent returns. A list without a diff is theatre.

This raises a floor; it is not a gate. A subagent can still write outside its
list and a driver can still skip the check. Stated plainly rather than dressed up
as enforcement."
```

---

### Task 5 (M5 — C): give `agy-curate` a legal end state

**Closes anomaly #8.** **Do NOT start until Task 4 is committed.**

**Files:**
- Modify: `agy-autotrain/skills/agy-curate/SKILL.md:122-130` and `:217-220`

- [ ] **Step 0: State verification**

1. `agy-autotrain/skills/agy-curate/SKILL.md:122` is `## Promotion rubric (curation-fatigue guard — do not skip)`.
2. `:126` is `- An **Empirical Assumption** promotes only after a **100% pass in the verify harness**:`.
3. `:217` is `## Finish` and `:219` begins `- **Empty the inbox**`.
4. The installed copy at `%LOCALAPPDATA%\Programs\agy-autotrain\plugins\agy-autotrain\knowledge\agy-observations.md` currently has 8 `- [assumption]` entries pending. (Context only; do not edit the installed copy.)

- [ ] **Step 1: Add the HELD disposition to the rubric**

In `agy-autotrain/skills/agy-curate/SKILL.md`, immediately after the `- An **Empirical Assumption** promotes only after a **100% pass in the verify harness**:` bullet and its indented STOP block, insert:

```markdown
### HELD — the fourth disposition, for an entry that is neither promotable nor droppable

An Empirical Assumption whose probe CANNOT BE RUN is not promotable (the rubric forbids it) and not
droppable (it may well be true). Before this state existed the skill had no legal move for it, and the
contradiction was not theoretical: **MEASURED on 2026-08-01, a drain took 79 entries in, routed 71, and
stranded 8** because `assertions.md` was stamped against agy 1.1.1 while the live peer was 1.1.9. The
Finish step said empty the inbox; the rubric said these may not promote; nothing said what to do.

An entry may be marked **HELD** only when all three hold:
1. it is `[assumption]` class,
2. its probe could not be executed, and the reason is recorded verbatim, and
3. the RELEASE CONDITION is named — the specific thing that would let it promote.

Write it as a normal inbox bullet with a `held=` field appended:

    - [assumption] (peer/probabilistic) <the rule>  ·  `[corpus]` · <date> · held=verify-harness-stale-1.1.1-vs-1.1.9

**HELD is not a parking space.** It is a claim that a NAMED blocker exists, and it expires when that
blocker clears. A HELD entry with no release condition, or one whose condition has since cleared, is a
drain that did not finish — treat it as pending on the next run.
```

- [ ] **Step 2: Make Finish satisfiable**

Replace the `- **Empty the inbox**` bullet at `:219` with:

```markdown
- **Empty the inbox** — every entry must reach a terminal disposition: promoted into GROWTH, compiled into
  the driver cheatsheet, emitted as a fix-the-tool backlog item, dropped as noise, or marked **HELD** with
  a recorded blocker and release condition. Reset `## Pending` to contain only the HELD entries.
  **"Empty" means every entry is dispositioned, not that the file has zero lines** — the earlier wording
  was unsatisfiable whenever the verify harness was stale, which is a state this skill has no power to fix
  and therefore must be able to survive.
```

- [ ] **Step 3: Verify the procedure now terminates**

This milestone has **no mechanical oracle** — it is prose in a skill, and that is stated rather than dressed up. Its correctness check is a walkthrough:

Re-read the edited skill start to finish and answer, in the commit message: *for each of the 8 currently-stranded assumption entries, which disposition does the procedure now reach, and what would release it?* If any entry still has no legal move, the edit is incomplete.

- [ ] **Step 4: Commit**

```bash
git add agy-autotrain/skills/agy-curate/SKILL.md
git commit -m "fix(agy-curate): define a legal end state for an unrunnable probe

The Finish step said empty the inbox. The promotion rubric forbade promoting an
Empirical Assumption without a 100% verify-harness pass. When the harness is
stale those entries are neither promotable nor droppable, and the skill defined
no state for them - the two instructions were unsatisfiable together.

Not theoretical: MEASURED on 2026-08-01, a drain took 79 entries in, routed 71,
and stranded 8, because assertions.md is stamped agy 1.1.1 against a live 1.1.9.

HELD is now the fourth disposition, admissible only with a recorded blocker AND a
named release condition, and Finish means every entry is dispositioned rather
than the file having zero lines. HELD is not a parking space: it asserts a named
blocker and expires when that blocker clears.

No mechanical oracle - this is prose, and its check is a walkthrough. All 8
stranded entries reach HELD with release condition
held=verify-harness-stale-1.1.1-vs-1.1.9, which clears when the harness is
re-run against the live peer."
```

---

### Task 6 (M6 — E): reject a corrupt payload inside `curate-commit`

**Closes the class behind anomaly #7** (the artifact itself was already republished clean). **Do NOT start until Task 5 is committed.**

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/CliVerbs.cs` (before `:87`)
- Modify: `clavity-classic/src/main.rs` (inside `curate_commit()`, from `:700`)
- Modify: `clavity-dotnet/tests/Clavity.Ls.Tests/CliVerbsTests.cs` (**add** tests; the existing two stay untouched)
- Modify: `agy-autotrain/skills/agy-curate/SKILL.md` (the authoring-policy half)

- [ ] **Step 0: State verification**

1. `CliVerbs.cs:87` is `            GoldenHeader.CommitGrowth(dir, new string(buffer, 0, total));`.
2. `CliVerbs.cs:79-83` contains the over-cap branch returning `2`.
3. `clavity-classic/src/main.rs:700` is `fn curate_commit() -> i32 {`.
4. `CliVerbsTests.cs:31` is `CurateCommit_round_trips_non_ascii_content_byte_identically` and `:44` is `CurateCommit_written_growth_survives_the_strict_read_side_decode`.

**If either existing test has been modified or removed, STOP.** They pin `curate-commit`'s contract and this milestone must not touch them.

- [ ] **Step 1: Write the failing tests**

Append to `clavity-dotnet/tests/Clavity.Ls.Tests/CliVerbsTests.cs`, before its final closing brace:

```csharp
    // The 13-day corruption: a text pipe re-encoded the payload through the console code page before
    // curate-commit ever saw it, so the bytes arrived already wrong - and arrived as VALID UTF-8
    // (the CP437 round-trip of an em-dash is the well-formed sequence U+0393 U+00C7 U+00F6). The .sha256
    // sidecar therefore MATCHED, confirming corrupt content. An integrity sidecar catches torn writes; it
    // cannot catch content that was wrong on arrival.
    private const string Cp437MangledEmDash = "\u0393\u00C7\u00F6";
    private const string Cp1252MangledPrefix = "\u00E2\u20AC";

    [Fact]
    public void CurateCommit_refuses_a_payload_carrying_the_CP437_mojibake_signature()
    {
        var error = new StringWriter();
        var payload = $"[ANTI-PATTERNS]\n- a rule {Cp437MangledEmDash} with a mangled dash\n";
        Assert.NotEqual(0, CliVerbs.CurateCommit(_dir, Utf8(payload), error));
        Assert.Contains("mojibake", error.ToString(), StringComparison.OrdinalIgnoreCase);
        Assert.False(File.Exists(GoldenHeader.GrowthPath(_dir)));
    }

    [Fact]
    public void CurateCommit_refuses_a_payload_carrying_the_CP1252_mojibake_signature()
    {
        var error = new StringWriter();
        var payload = $"[ANTI-PATTERNS]\n- a rule {Cp1252MangledPrefix}\u201D with a mangled quote\n";
        Assert.NotEqual(0, CliVerbs.CurateCommit(_dir, Utf8(payload), error));
        Assert.False(File.Exists(GoldenHeader.GrowthPath(_dir)));
    }

    [Fact]
    public void CurateCommit_still_accepts_legitimate_non_ascii()
    {
        // Guards the tripwire against becoming a blanket ASCII rule. curate-commit is a FAITHFUL BYTE
        // TRANSPORT by contract - that property is exactly why the raw-byte publish path is worth
        // mandating over a text pipe. A blanket rule would break it and force the two round-trip tests
        // above to be inverted, which is not a change this milestone is permitted to make.
        var error = new StringWriter();
        Assert.Equal(0, CliVerbs.CurateCommit(_dir, Utf8(NonAsciiSample), error));
        Assert.Equal(Encoding.UTF8.GetBytes(NonAsciiSample), File.ReadAllBytes(GoldenHeader.GrowthPath(_dir)));
    }
```

- [ ] **Step 2: Run them and verify all three FAIL**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~CurateCommit_refuses|FullyQualifiedName~CurateCommit_still_accepts"`

Expected: the two `_refuses_` tests FAIL (no tripwire exists yet, so the payload is accepted). `CurateCommit_still_accepts_legitimate_non_ascii` **PASSES already** — it describes behaviour that exists today, and its job is to stop this milestone destroying it. **One of the three cannot go red, and that is correct.**

- [ ] **Step 3: Add the tripwire to the .NET binary**

In `CliVerbs.cs`, immediately after the over-cap branch (`:79-83`) and before the `try` that calls `CommitGrowth`, insert:

```csharp
        // Mojibake tripwire. A text pipe on Windows re-encodes the stream through the console code page,
        // so the payload can arrive already mangled AND still be well-formed UTF-8 - which is why the
        // integrity sidecar matched corrupt content for 13 days. This is deliberately a HEURISTIC over
        // known corruption families, not a proof: it cannot enumerate every mis-encoding and does not
        // claim to. It is NOT a blanket non-ASCII rejection - curate-commit is a faithful byte transport
        // by contract (see CurateCommit_round_trips_non_ascii_content_byte_identically), and rejecting
        // all non-ASCII would break the very property that makes the raw-byte path worth mandating.
        var payload = new string(buffer, 0, total);
        foreach (var signature in new[] { "\u0393\u00C7", "\u00E2\u20AC" })
        {
            if (payload.Contains(signature, StringComparison.Ordinal))
            {
                error.WriteLine("curate-commit: input contains a suspected mojibake sequence " +
                                "(a text pipe re-encoded it through the console code page); nothing written. " +
                                "Stream the file's raw bytes to stdin instead of piping text.");
                return 2;
            }
        }
```

Then change the `CommitGrowth` call at `:87` to reuse the local:

```csharp
            GoldenHeader.CommitGrowth(dir, payload);
```

- [ ] **Step 4: Run the .NET tests**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests`
Expected: `Failed: 0`, total count = previous 146 + 3 = **149**.

**The two pre-existing round-trip tests must appear as passing and must be unmodified.** Verify with:
```bash
git diff --stat clavity-dotnet/tests/Clavity.Ls.Tests/CliVerbsTests.cs
```
Expected: insertions only, zero deletions. **If satisfying this milestone required editing either existing test, the implementation is wrong and must stop — not the tests.**

- [ ] **Step 5: Add the tripwire to the Rust binary**

In `clavity-classic/src/main.rs`, inside `curate_commit()`, insert immediately after the `let content = match String::from_utf8(buf) { ... };` block (which ends around `:721`) and before the `let Some(home) = user_home()` binding:

```rust
    // Mojibake tripwire - see the .NET twin in CliVerbs.cs for the full rationale. A heuristic over known
    // corruption families, NOT a blanket non-ASCII rejection: curate-commit is a faithful byte transport
    // by contract, and rejecting all non-ASCII would break the property that makes the raw-byte publish
    // path worth mandating over a text pipe.
    for signature in ["\u{0393}\u{00C7}", "\u{00E2}\u{20AC}"] {
        if content.contains(signature) {
            eprintln!(
                "clavity curate-commit: input contains a suspected mojibake sequence (a text pipe \
                 re-encoded it through the console code page); nothing written. Stream the file's raw \
                 bytes to stdin instead of piping text."
            );
            return 1;
        }
    }
```

**The local is named `content`** (VERIFIED — it is the `String::from_utf8` result), and **the exit code is `1`, not `2`**, because this function already uses `1` for bad input (over-cap, invalid UTF-8) and reserves `2` for environment failures (unreadable stdin, no home dir). Matching the existing convention matters: the .NET twin returns `2` for its own bad-input cases, so the two binaries differ here **by pre-existing design, not by mistake** — do not "harmonise" them.

- [ ] **Step 6: Run the Rust tests**

Run: `cd clavity-classic && cargo test --all --features test-fakes`
Expected: `Failed: 0` and the pre-existing `driver_cheatsheet::tests::baseline_floor_matches_canonical_core_source ... ok` still passing.

- [ ] **Step 7: Record the authoring policy in the curate skill**

In `agy-autotrain/skills/agy-curate/SKILL.md`, in the "Compile + commit the GROWTH region" section, add immediately before the publish snippet:

```markdown
**Compile GROWTH as pure ASCII.** This is a rule about what we WRITE, not a restriction on what the
transport may carry — `curate-commit` remains a faithful byte transport and will accept legitimate
non-ASCII. It carries a tripwire for known mojibake families, which is a heuristic and not a proof, so the
authoring policy is what covers the general case. GROWTH is a compiled, machine-generated artifact with no
present need for typography, and non-ASCII in it bought nothing while costing 13 days of silently corrupt
injection into every ask.
```

- [ ] **Step 8: Full gate + commit**

```bash
just seed-sync-check && just test-scripts-fast
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests
cd ../clavity-classic && cargo test --all --features test-fakes
```
Expected: all clean. Then `just test-scripts-slow` backgrounded, `Failed: 0`.

```bash
git add clavity-dotnet/src/Clavity.Ls/CliVerbs.cs clavity-dotnet/tests/Clavity.Ls.Tests/CliVerbsTests.cs clavity-classic/src/main.rs agy-autotrain/skills/agy-curate/SKILL.md
git commit -m "fix(curate-commit): tripwire a mojibake payload at the receiving end

The live GROWTH region was mojibake-corrupted for 13 days while its .sha256
sidecar MATCHED, because the corruption preceded the commit: a text pipe
re-encoded the stream through the console code page, so the bytes arrived already
wrong AND already well-formed UTF-8. An integrity sidecar catches torn writes; it
cannot catch content that was wrong on arrival.

The check lives INSIDE curate-commit, against the bytes it actually received.
Anywhere earlier is blind to the failure mode - a check on the compiled file
before invocation reads pristine UTF-8, passes, and the mangling happens
afterwards.

It is a HEURISTIC over known corruption families (CP437 and CP1252), stated as
such, and deliberately NOT a blanket non-ASCII rejection. curate-commit is a
faithful byte transport by contract, pinned by two existing tests, and that
property is exactly why the raw-byte publish path is worth mandating over a text
pipe. A blanket rule would have required inverting those two tests - the oracle
wins, so the design changed instead.

Both existing round-trip tests pass unmodified; the diff to CliVerbsTests.cs is
insertions only. The general case is covered by the authoring policy in the
curate skill: GROWTH is compiled as pure ASCII, which is a rule about what we
write rather than what the transport may carry."
```

---

### Task 7: close the anomaly file

**Do NOT start until Tasks 1-6 are committed.**

- [ ] **Step 1: Delete every entry, recording its disposition**

Each of the 8 entries now has a terminal outcome. Rewrite `.clavity/local-anomalies.md` to just its header:

```bash
printf '%s\n\n' '# Untriaged anomalies (local, never committed)' > .clavity/local-anomalies.md
```

- [ ] **Step 2: Verify the reminder goes silent**

```bash
printf '{"cwd":"%s","source":"startup"}' "$(pwd)" | bash clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh ; echo "exit=$?"
```
Expected: **no output, `exit=0`.** The hook is silent when there is nothing to say — that is the end state the whole mechanism exists to reach.

- [ ] **Step 3: Record the dispositions where they survive the deletion**

The file is gitignored, so deleting entries destroys the record unless it lands somewhere durable. Append to `docs/agy-capstone-ledger.md` — not as a capstone row, but as a short note beneath the table:

```markdown
**Anomaly file closed 2026-08-01.** All 8 captured entries reached a terminal disposition by FIXING the
defect, per the owner's ruling that closing means fixing rather than filing. #1 and #2 (consult guard) →
relocated and fixed in both plugins with an integration test seen RED first. #3 (`agy_look` truncation) →
already tracked, backlog item `grpc-default-max-message-size`. #4 (test gate straddling the tool cap) →
suite partitioned by measured runtime. #5 (subagent wrote outside its file set) → dispatch allow-list plus
a driver diff. #6 (sync gate allow-list) → replaced with discovery. #7 (13-day mojibake corruption) →
artifact republished clean, class closed by a tripwire inside `curate-commit`. #8 (`agy-curate` had no
legal end state) → HELD disposition added.

The owner's failure criterion for the first triage — "a third outcome appears in practice" — did not trip.
```

- [ ] **Step 4: Commit**

```bash
git add docs/agy-capstone-ledger.md
git commit -m "docs: close the anomaly file - all 8 entries fixed, not filed

The owner's ruling was that closing an anomaly means fixing the defect, and the
file empties as a consequence. It did. The dispositions are recorded here because
.clavity/local-anomalies.md is gitignored, so deleting its entries would
otherwise destroy the only record of what was found and what was done.

Three of the eight were found by the capture mechanism during its own
construction. The failure criterion set for the first triage - that a third
outcome would appear in practice - did not trip."
```

---

## Self-review

**Spec coverage.** M1→Task 1, M2→Task 2, M3→Task 3, M4→Task 4, M5→Task 5, M6→Task 6, plus Task 7 for the closure the spec's disposition table implies. Every anomaly in the spec's eight-row table maps to a task. The spec's scope boundary on M2 is reproduced verbatim in Task 2 Step 3. The spec's "matcher takes a pattern, full string" ruling is in Task 3 Step 3. The spec's third M6 oracle ("existing tests pass unmodified") is Task 6 Step 4.

**Placeholder scan.** Two intentional fill-ins remain and both are explicitly bounded: `<FAST-FILES>`/`<SLOW-FILES>` in Task 1 Step 4 (derived from Step 1's measurement, with an explicit instruction that leaving the token in place is a plan failure), and `<list every path...>` in Task 4 Step 1 (it is a template for the operator to fill per dispatch — that is the artifact's purpose, not a gap). No `TBD`, no "handle edge cases", no "similar to Task N".

**Type consistency.** `divergent()` is defined and used in Task 2 only. `Cp437MangledEmDash` / `Cp1252MangledPrefix` are defined in Task 6 Step 1 and used in Steps 1 and 3. `payload` is introduced in Task 6 Step 3 and reused in the same step's `CommitGrowth` call. `Invoke-Hook` and `Invoke-BashHook` are pre-existing helpers in `BashHookHelpers.ps1`.

## Exhaustiveness audit

**Gaps closed in-document:** the M1 threshold was under-specified in the spec (">= 20s, fall back to 10s, else STOP" now); the Rust tripwire's insertion point depends on a local whose name I did not verify, so Task 6 Step 5 instructs reading it and reports `STATE_MISMATCH` rather than guessing.

**Gaps flagged, with where they resolve:**
1. **Task 3 Step 8 edits `~/.claude/settings.json`, the operator's file.** The plan says confirm first. It cannot be resolved in-document — it is the operator's call at execution time.
2. **Task 5 has no mechanical oracle.** Stated in the spec and again here. Resolves as a walkthrough recorded in its commit message.
3. **Task 6's tripwire is a heuristic.** It cannot enumerate every mis-encoding, and the spec's two-layer design is the answer: the authoring policy covers the general case. Not resolvable further without breaking the transport contract.
4. **The exact FAST/SLOW file lists cannot be written before execution** — they are a measurement, taken in Task 1 Step 1. This is the one place the plan defers a value, and it defers it to a measurement with a stated rule, not to judgement.

**Every stated requirement maps to a section.** The spec's Known Limits 1-5 are reflected: #1 (M5 prose) in Task 5 Step 3; #2 (M4 raises a floor) in Task 4's commit message; #3 (M2 inverts a failure mode) in Task 2 Step 3's comment; #4 (stop-after-M2 leaves the guard dead) is why Task 3 immediately follows; #5 (triage has no HELD state, deliberately) is untouched by this plan by design.

# Verification-Harness Defect Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the agy verification harness tell the truth about its own state — a gate that cannot go silent while probes are failing, a runbook that is executable on either driver, and a probe suite with no confounded assertions.

**Architecture:** `assertions.md` gains two per-driver status columns (`dotnet`, `classic`) placed immediately after the id. The SessionStart hook selects data rows positionally, extracts its detected driver's column, and compares tokens by exact string equality. Unresolved states (`FAIL`, `PARTIAL`) nag regardless of version; `PASS`/`ACKED` nag when their version differs from live; `N/A` is always silent. Anything unreadable — blank cell, unknown token, zero rows parsed, missing `awk` — nags rather than exits silently, because silence is the failure mode being fixed.

**Tech Stack:** bash + `jq` + `awk` (SessionStart hook), Markdown (the harness docs), `just` (test recipe).

**Source spec:** [`docs/superpowers/specs/2026-07-31-verify-harness-defects-design.md`](../specs/2026-07-31-verify-harness-defects-design.md) — approved, panel-GREEN after 5 rounds.

---

## Verified starting state

Every citation below was read against the working tree at HEAD `fc0101a` before this plan was written.

| Fact | Verified |
|---|---|
| `.claude/hooks/agy-verify-reminder.sh` | 46 lines; version-gate at L24-25 (`grep -oE 'agy [0-9]+\.[0-9]+\.[0-9]+' … sort -V \| tail -1`), agy lookup with `LOCALAPPDATA` fallback at L29-34, nag emitted at L43-44 |
| `agy-autotrain/verify/assertions.md` | header L7 = `\| # \| Assumption \| Probe payload (synthetic \`clavity ask\`) \| Observable \| PASS \| Last run \|`; separator L8; **6** data rows A1-A6; exactly **one** table; **0** escaped pipes |
| `agy-autotrain/skills/agy-curate/SKILL.md` | L128-131 carry the 🛑 STOP block ordering the curator to record outcomes in `../../verify/assertions.md` |
| `.claude/recommended-tools.json` | JSON array of `{name, why, install, in_path}`; last entry is `mlc` |
| `justfile` | `seed-sync-check:` at L26-27 runs `bash scripts/check-seed-artifacts-synced.sh` — the precedent for a bash recipe |
| `awk` | GNU Awk 5.4.0 at `/usr/bin/awk` |

**Column indices after conversion.** The new header is
`| # | dotnet | classic | Assumption | Probe payload | Observable | PASS criterion | Last run |`.
Under `awk -F'|'` the leading `|` produces an empty `$1`, so **`$2` = id, `$3` = dotnet, `$4` = classic**. Every task below depends on this mapping.

---

## File structure

| File | Responsibility |
|---|---|
| `.claude/hooks/agy-verify-reminder.sh` | Modify — the gate itself: row filter, column selection, token evaluation, nag |
| `agy-autotrain/verify/assertions.md` | Modify — add the two status columns, rename `PASS` → `PASS criterion`, drop A4 |
| `agy-autotrain/verify/testdata/*.md` | Create — fixture assertion files, one per gate behaviour |
| `agy-autotrain/verify/testdata/run-hook-tests.sh` | Create — the runner; stubs `agy`/`clavity-ls` on `PATH` so tests are deterministic |
| `agy-autotrain/skills/agy-curate/SKILL.md` | Modify — teach the table's primary writer about the status cell |
| `agy-autotrain/verify/run-verification.md` | Modify — capability-based preflight + per-driver appendix (D1) |
| `agy-autotrain/verify/probe-design.md` | Modify — the A4 A/B pair as a worked example (D2) |
| `agy-autotrain/verify/README.md` | Modify — document the enum and the gate |
| `.claude/recommended-tools.json` | Modify — declare `awk` |
| `justfile` | Modify — add `check-verify-hook` |

---

### Task 1: Test harness + the first RED test

**Files:**
- Create: `agy-autotrain/verify/testdata/run-hook-tests.sh`
- Create: `agy-autotrain/verify/testdata/fail-at-live.md`

The runner stubs `agy` and `clavity-ls` on `PATH` so the live version and detected driver are fixed inputs, not whatever the machine happens to have. Without this the tests are not reproducible.

- [ ] **Step 1: Write the first fixture — a FAIL row at the live version**

Create `agy-autotrain/verify/testdata/fail-at-live.md`:

```markdown
# fixture: one FAIL row, stamped at the live version

Prose before the table, which the row filter must ignore.

| # | dotnet | classic | Assumption | PASS criterion | Last run |
|---|--------|---------|------------|----------------|----------|
| A1 | PASS 1.1.9 | N/A | first | ok | ran |
| A2 | FAIL 1.1.9 | N/A | second | ok | ran |
```

- [ ] **Step 2: Write the runner**

Create `agy-autotrain/verify/testdata/run-hook-tests.sh`:

```bash
#!/usr/bin/env bash
# Fixture-driven tests for .claude/hooks/agy-verify-reminder.sh.
# Each case pipes a SessionStart JSON payload at the hook with a fixture assertions.md in place,
# and asserts on whether a nag was emitted. agy and clavity-ls are STUBBED on PATH so the live
# version and the detected driver are controlled inputs.
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
hook="$repo/.claude/hooks/agy-verify-reminder.sh"
pass=0; fail=0

# Stub bin dir: fake agy reports a fixed version; fake clavity-ls makes the driver detectable.
stub=$(mktemp -d)
trap 'rm -rf "$stub"' EXIT
printf '#!/usr/bin/env bash\necho "agy 1.1.9"\n' > "$stub/agy";        chmod +x "$stub/agy"
printf '#!/usr/bin/env bash\nexit 0\n'           > "$stub/clavity-ls"; chmod +x "$stub/clavity-ls"

# PATH = stub first, then whatever the contributor already has. The stub shadows the real agy and
# clavity-ls; everything else the hook needs (jq, awk, timeout, grep) resolves from the normal PATH.
# Do NOT reconstruct a minimal PATH from discovered tool directories: contributors install these
# wherever they like, and pinning locations is how a test suite starts failing for reasons that have
# nothing to do with the code under test.
for req in jq awk; do
  command -v "$req" >/dev/null 2>&1 || { echo "$req not found — the hook cannot run without it"; exit 1; }
done

# run_case <name> <fixture> <expect: nag|silent> [extra PATH entries removed: driver]
run_case() {
  local name="$1" fixture="$2" expect="$3" driver="${4:-dotnet}"
  local sandbox; sandbox=$(mktemp -d)
  mkdir -p "$sandbox/agy-autotrain/verify"
  cp "$here/$fixture" "$sandbox/agy-autotrain/verify/assertions.md"

  local bin="$stub"
  # LOCALAPPDATA is redirected to an EMPTY dir for every case, so the hook's install-location
  # fallbacks cannot see a real clavity-ls.exe on a dev box.
  local empty; empty=$(mktemp -d)

  if [ "$driver" = "none" ]; then
    # This case needs NO driver CLI reachable at all. We can drop the stub, but we cannot hide a real
    # clavity/clavity-ls that is already on the contributor's PATH -- and pinning PATH to hide it is
    # exactly the brittleness we are avoiding. So skip honestly rather than test something else.
    if command -v clavity-ls >/dev/null 2>&1 || command -v clavity >/dev/null 2>&1; then
      printf 'skip %s — a driver CLI is on PATH and cannot be hidden without pinning PATH\n' "$name"
      rm -rf "$sandbox" "$empty"; return
    fi
    bin=$(mktemp -d); cp "$stub/agy" "$bin/agy"     # agy present, no driver CLI
  fi

  local out
  out=$(printf '{"cwd":"%s"}' "$sandbox" \
        | PATH="$bin:$PATH" LOCALAPPDATA="$empty" bash "$hook" 2>/dev/null)
  rm -rf "$empty"

  local got="silent"
  [ -n "$out" ] && got="nag"
  if [ "$got" = "$expect" ]; then
    printf 'ok   %s\n' "$name"; pass=$((pass+1))
  else
    printf 'FAIL %s — expected %s, got %s\n     output: %s\n' "$name" "$expect" "$got" "$out"
    fail=$((fail+1))
  fi
  rm -rf "$sandbox"
}

run_case "FAIL at live version nags" fail-at-live.md nag

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 3: Run it and verify it FAILS**

Run: `bash agy-autotrain/verify/testdata/run-hook-tests.sh`

Expected: `FAIL FAIL at live version nags — expected nag, got silent`, exit 1.

This is the D3 defect reproduced as a test: the current hook sees the highest stamp (`1.1.9`) equal to live and exits silently at L40, while a row is plainly `FAIL`.

- [ ] **Step 4: Commit the RED test**

```bash
git add agy-autotrain/verify/testdata/run-hook-tests.sh agy-autotrain/verify/testdata/fail-at-live.md
git commit -m "test(verify): reproduce the silent-while-failing gate defect"
```

---

### Task 2: The remaining fixtures

**Files:**
- Create: `agy-autotrain/verify/testdata/{all-pass,acked-live,acked-stale,partial-live,prose-noise,blank-status,bad-token,no-columns,driver-split,fail-in-prose}.md`
- Modify: `agy-autotrain/verify/testdata/run-hook-tests.sh`

Every fixture below pins one behaviour from the spec. Write them all now so Task 3 implements against a complete oracle rather than one test at a time.

- [ ] **Step 1: Create the silent-expected fixtures**

`all-pass.md`:

```markdown
| # | dotnet | classic | Assumption | PASS criterion | Last run |
|---|--------|---------|------------|----------------|----------|
| A1 | PASS 1.1.9 | N/A | first | ok | ran |
```

`acked-live.md`:

```markdown
| # | dotnet | classic | Assumption | PASS criterion | Last run |
|---|--------|---------|------------|----------------|----------|
| A1 | ACKED 1.1.9 | N/A | peer defect | ok | ran |
```

`fail-in-prose.md` — the word FAIL and a stale version live in narrative text, never in a status cell:

```markdown
| # | dotnet | classic | Assumption | PASS criterion | Last run |
|---|--------|---------|------------|----------------|----------|
| A1 | PASS 1.1.9 | N/A | this probe used to FAIL under agy 1.0.10 | ok | ran |
```

`driver-split.md` — read on a dotnet box, the classic column's PARTIAL must not speak:

```markdown
| # | dotnet | classic | Assumption | PASS criterion | Last run |
|---|--------|---------|------------|----------------|----------|
| A1 | PASS 1.1.9 | PARTIAL 1.1.9 | driver-scoped | ok | ran |
```

- [ ] **Step 2: Create the nag-expected fixtures**

`acked-stale.md` (`ACKED 1.1.1` vs live `1.1.9`), `partial-live.md` (`PARTIAL 1.1.9`), `blank-status.md` (empty dotnet cell), and `bad-token.md` — each the same shape as above with only the dotnet cell changed.

**`bad-token.md` must use `FAILED 1.1.9`, not a case variant like `Pass 1.1.9`.** MEASURED: against the mutant regex `/^(PASS|FAIL|PARTIAL|ACKED)/` (anchor and version dropped), `Pass 1.1.9` still fails to match — awk regexes are case-sensitive — so it still reports "unrecognised", still nags, and the test stays GREEN with the guard removed. That is a vacuous test. `FAILED 1.1.9` matches the mutant's `^FAIL` prefix, yields token `FAILED` which is neither `FAIL` nor `PARTIAL`, carries a current version, and therefore goes **silent** — turning the test RED and proving the full-token anchor is load-bearing. `no-columns.md` is the **pre-conversion** table:

```markdown
| # | Assumption | PASS | Last run |
|---|------------|------|----------|
| A1 | first | ok | ran |
```

`prose-noise.md` is `all-pass.md` with headings and paragraphs above and below the table — expected **silent**, pinning that prose never trips fail-loud.

- [ ] **Step 3: Register every case in the runner**

Replace the single `run_case` line with:

```bash
run_case "FAIL at live nags"                fail-at-live.md  nag
run_case "all PASS at live is silent"       all-pass.md      silent
run_case "ACKED at live is silent"          acked-live.md    silent
run_case "ACKED at stale version nags"      acked-stale.md   nag
run_case "PARTIAL at live still nags"       partial-live.md  nag
run_case "prose and headings stay silent"   prose-noise.md   silent
run_case "FAIL in prose stays silent"       fail-in-prose.md silent
run_case "blank status nags"                blank-status.md  nag
run_case "unknown token nags"               bad-token.md     nag
run_case "missing status columns nag"       no-columns.md    nag
run_case "other driver's PARTIAL is silent" driver-split.md  silent
run_case "no driver detected reads both"    driver-split.md  nag      none
```

- [ ] **Step 4: Run — expect many failures**

Run: `bash agy-autotrain/verify/testdata/run-hook-tests.sh`
Expected: the `silent`-expected cases pass by accident (the old hook is silent when versions match); every `nag` case fails. Exit 1.

- [ ] **Step 5: Commit**

```bash
git add agy-autotrain/verify/testdata/
git commit -m "test(verify): fixtures for every gate behaviour in the design"
```

---

### Task 3: Rewrite the hook

**Files:**
- Modify: `.claude/hooks/agy-verify-reminder.sh` (replace L23-45; keep L1-22 intact)

- [ ] **Step 1: Replace everything from L23 to the end**

Keep lines 1-22 exactly as they are (shebang, comment block, `set +e`, stdin read, `jq` guard, `cwd` extraction, the `assertions` readability guard). Replace the rest with:

```bash
# Locate the agy CLI. Guard --version with a timeout: a headless invocation can stall.
agy_bin=""
if command -v agy >/dev/null 2>&1; then
  agy_bin="agy"
elif [ -x "${LOCALAPPDATA:-}/agy/bin/agy.exe" ]; then
  agy_bin="${LOCALAPPDATA}/agy/bin/agy.exe"
fi
[ -z "$agy_bin" ] && exit 0         # agy not installed here -> nothing to verify against

live=$(timeout 8 "$agy_bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[ -z "$live" ] && exit 0            # could not read a version -> fail-open silent

emit() {
  jq -nc --arg m "$1" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
  exit 0
}

# awk is a declared prerequisite (.claude/recommended-tools.json). If it is missing we CANNOT read
# the status columns -- and a verification gate that cannot verify must say so, not fall silent.
command -v awk >/dev/null 2>&1 || emit "agy VERIFY-HARNESS: awk is unavailable, so the probe status columns in agy-autotrain/verify/assertions.md cannot be read. Install awk (see .claude/recommended-tools.json); until then this gate cannot tell you whether the probe suite is stale."

# Which driver's column applies? PATH first, then the known install location -- a non-interactive
# SessionStart hook often lacks user-local PATH entries. Ambiguous or undetectable -> read BOTH,
# the strict reading: if we cannot tell which driver applies, an unresolved state in either counts.
cols=""
if command -v clavity-ls >/dev/null 2>&1 || [ -x "${LOCALAPPDATA:-}/Programs/clavity-dotnet/clavity-ls.exe" ]; then
  cols="dotnet"
fi
if command -v clavity >/dev/null 2>&1 || [ -x "${LOCALAPPDATA:-}/Programs/clavity-classic/clavity.exe" ]; then
  [ -n "$cols" ] && cols="both" || cols="classic"
fi
[ -z "$cols" ] && cols="both"

# Row filter is POSITIONAL: a data row is a |-line AFTER the separator (^\|[-: |]+\|$).
# The header needs no text matching -- it is the |-line before the separator.
# Columns: $2 = id, $3 = dotnet, $4 = classic.
findings=$(awk -F'|' -v live="$live" -v cols="$cols" '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  function check(id, col, v,    tok, ver) {
    if (v == "N/A") return
    if (v == "")    { report(id, col, "blank"); return }
    if (v !~ /^(PASS|FAIL|PARTIAL|ACKED) [0-9]+\.[0-9]+\.[0-9]+$/) { report(id, col, "unrecognised \"" v "\""); return }
    tok = substr(v, 1, index(v, " ") - 1)
    ver = substr(v, index(v, " ") + 1)
    if (tok == "FAIL" || tok == "PARTIAL") { report(id, col, v); return }
    if (ver != live) report(id, col, v " (live " live ")")
  }
  function report(id, col, why) { out = out (out == "" ? "" : "; ") id " [" col "] " why }
  /^\|[-: |]+\|$/ { indata = 1; next }
  indata && /^\|/ {
    rows++
    id = trim($2)
    if (cols == "dotnet" || cols == "both")  check(id, "dotnet",  trim($3))
    if (cols == "classic" || cols == "both") check(id, "classic", trim($4))
  }
  END {
    if (rows == 0) { print "NOROWS"; exit }
    print out
  }
' "$assertions" 2>/dev/null)

if [ "$findings" = "NOROWS" ]; then
  emit "agy VERIFY-HARNESS: no probe rows could be read from agy-autotrain/verify/assertions.md. The status columns are missing, renamed, or the table was reshaped -- so this gate currently cannot tell you anything about probe freshness. Fix the table shape (see agy-autotrain/verify/README.md)."
fi

[ -z "$findings" ] && exit 0        # every applicable row resolved and current -> silent

emit "agy VERIFY-HARNESS reminder — live agy ${live}. Unresolved or stale probes in agy-autotrain/verify/assertions.md: ${findings}. Re-run the affected probes per agy-autotrain/verify/run-verification.md: physically execute each probe against the live agy (never score from memory — the agy-curate STOP gate), record the real outcome, then set the status cell. FAIL and PARTIAL nag regardless of version and cannot be silenced by re-stamping."
```

- [ ] **Step 2: Run the tests**

Run: `bash agy-autotrain/verify/testdata/run-hook-tests.sh`
Expected: `11 passed, 0 failed` with `skip no driver detected reads both` on a box that has a driver CLI on PATH (12 passed where none is installed, e.g. CI). Exit 0 either way.

If `missing status columns nag` fails, check that `no-columns.md`'s rows yield an empty `$3` — a blank cell reports `blank`, which is still a nag, so either path is acceptable; the case must not be silent.

- [ ] **Step 3: Mutation-check the two load-bearing rules**

Non-vacuity matters here — a guard test that passes for the wrong reason is worse than none.

Temporarily change `if (tok == "FAIL" || tok == "PARTIAL")` to `if (tok == "FAIL")`, re-run: `PARTIAL at live still nags` must go RED. Restore it.

Temporarily change the token regex to `/^(PASS|FAIL|PARTIAL|ACKED)/` (dropping the anchor and version), re-run: `unknown token nags` must go RED — the `FAILED 1.1.9` fixture goes silent under the mutant. Restore it.

Note *why* the fixture is `FAILED` and not a case variant: a case variant fails the mutant regex too, so the test would stay green and the mutant would survive. This was measured, not assumed.

Both mutants killed = the tests bind the behaviour they claim to.

- [ ] **Step 4: Commit**

```bash
git add .claude/hooks/agy-verify-reminder.sh
git commit -m "fix(verify): gate on per-row status, never on the newest stamp

FAIL and PARTIAL nag regardless of version, so re-stamping cannot silence an
unresolved probe. Rows are selected positionally after the table separator and
the detected driver's column is compared by exact token equality, so narrative
prose containing FAIL or a version string no longer affects the gate. Anything
unreadable -- blank cell, unknown token, no rows, missing awk -- nags rather
than exiting silently, because silence is the defect being fixed."
```

---

### Task 4: Convert `assertions.md` to the two-column shape

**Files:**
- Modify: `agy-autotrain/verify/assertions.md` (header L7, separator L8, rows L9-14)

- [ ] **Step 1: Replace the header and separator**

L7-8 become:

```markdown
| # | dotnet | classic | Assumption | Probe payload (synthetic ask) | Observable | PASS criterion | Last run |
|---|--------|---------|------------|------------------------------|-----------|----------------|----------|
```

The old `PASS` column is renamed `PASS criterion` — it holds the pass *criterion*, and two different `PASS` meanings adjacent in one table is exactly the confusion this change removes.

- [ ] **Step 2: Set each row's two status cells**

Insert `| <dotnet> | <classic> |` immediately after each row's id. Preserve every existing narrative cell verbatim — those are measured data and must not be rewritten.

| Row | dotnet | classic | Why |
|---|---|---|---|
| A1 | `PASS 1.1.9` | `PARTIAL 1.1.9` | re-verified on dotnet; never run under classic |
| A2 | `PARTIAL 1.1.1` | `PARTIAL 1.1.1` | half (b) was never re-run — nags, correctly |
| A3 | `N/A` | `PARTIAL 1.1.9` | the dotnet bridge uses one persistent cascade; live for classic |
| A5 | `ACKED 1.1.9` | `PARTIAL 1.1.9` | verified peer defect, disposition recorded |
| A6 | `ACKED 1.1.9` | `PARTIAL 1.1.9` | negative untestable by construction |

A4 is removed entirely — see Task 7.

- [ ] **Step 3: Add the disposition references**

A5's and A6's narrative cells must each carry the disposition that justifies `ACKED`. For A5: the confabulated-checkpoint measurement and the resulting rule that delegated checkpoints need tooling, not prose. For A6: that the alive-but-unreachable negative cannot be forced without downing a healthy live endpoint. The gate cannot check these — it never parses prose — so this is a convention review owns.

- [ ] **Step 4: Verify the real file against the row filter**

Run:

```bash
awk -F'|' '/^\|[-: |]+\|$/{d=1;next} d&&/^\|/{n++; printf "%s|%s|%s\n",$2,$3,$4} END{print "rows="n}' \
  agy-autotrain/verify/assertions.md
```

Expected: 5 rows (A1, A2, A3, A5, A6), each showing its two status cells, then `rows=5`.

- [ ] **Step 5: Commit**

```bash
git add agy-autotrain/verify/assertions.md
git commit -m "feat(verify): per-driver status columns in the assertion table"
```

---

### Task 5: Teach `agy-curate` about the status cell

**Files:**
- Modify: `agy-autotrain/skills/agy-curate/SKILL.md:128-131`

This skill is the table's **primary writer**. If it does not set the status cell, it will faithfully write prose and leave status stale — manufacturing the exact drift the gate exists to catch, in the one workflow that touches the file most.

- [ ] **Step 1: Extend the 🛑 STOP block**

After the existing line ending `Never mark a probe "pass" from memory or assumption.`, add:

```markdown
  > Recording the outcome means BOTH: the evidence in the narrative cell, AND the status cell for the
  > driver the probe actually ran under (`dotnet` or `classic`). They are one edit, not two — the hook
  > reads only the status cell and never the prose, so a status left stale is invisible drift.
  > Tokens: `PASS <ver>` · `FAIL <ver>` · `PARTIAL <ver>` (some parts unrun — always nags) ·
  > `ACKED <ver>` (verified, unresolvable by us, disposition recorded) · `N/A` (not applicable to that
  > driver). A probe you did not run under the OTHER driver stays `PARTIAL` there — do not guess it.
```

- [ ] **Step 2: Verify no other instruction in the file contradicts it**

Run: `grep -n 'assertions.md' agy-autotrain/skills/agy-curate/SKILL.md`
Expected: L20 (a pointer) and the STOP block. Confirm L20 needs no change.

- [ ] **Step 3: Commit**

```bash
git add agy-autotrain/skills/agy-curate/SKILL.md
git commit -m "docs(agy-curate): record the status cell, not just the evidence"
```

---

### Task 6: D1 — capability-based preflight

**Files:**
- Modify: `agy-autotrain/verify/run-verification.md:10-14`

- [ ] **Step 1: Replace the Preflight section**

L10-14 currently name `clavity doctor` / `clavity ping` / `clavity ask` — clavity-**classic** commands that do not exist on a clavity-dotnet box, where the CLI is only `clavity-ls start` and `clavity-ls --mcp`. Replace with:

```markdown
## Preflight

The harness needs three capabilities. How you get them depends on which driver is installed — the two
are mutually exclusive, so a machine has one. See the appendix for the invocations.

1. **Liveness** — confirm the peer is reachable and idle before firing. Do not fire while it is busy.
2. **Synchronous ask** — send a probe payload and get the reply.
3. **Version** — note `agy --version`; stamp it on every result.
```

- [ ] **Step 2: Add the appendix at the end of the file**

```markdown
## Appendix — per-driver invocations

| Capability | clavity-classic | clavity-dotnet |
|---|---|---|
| liveness / reachability | `clavity doctor`, `clavity ping` | `agy_status` (MCP tool) |
| synchronous ask | `clavity ask "<payload>"` | `agy_ask` (MCP tool) |
| async send + read reply | send + `clavity await-reply` | n/a — `agy_ask` is synchronous |

The driver ids in this table (`dotnet`, `classic`) are the same ids naming the status columns in
`assertions.md` and detected by `.claude/hooks/agy-verify-reminder.sh`. Keep the three in step.
```

- [ ] **Step 3: Verify no stale references remain**

Run: `grep -nE 'clavity (doctor|ping|ask)' agy-autotrain/verify/run-verification.md`
Expected: matches only inside the appendix table.

- [ ] **Step 4: Commit**

```bash
git add agy-autotrain/verify/run-verification.md
git commit -m "docs(verify): capability-based preflight with a per-driver appendix"
```

---

### Task 7: D2 — retire A4, keep its evidence

**Files:**
- Modify: `agy-autotrain/verify/probe-design.md` (append a worked example)
- Modify: `agy-autotrain/verify/assertions.md` (A4's row already removed in Task 4)

- [ ] **Step 1: Append the worked example after the existing priming example**

```markdown
## Worked example — the phase-tag probe (a confounded probe, and its fix)

Real result, 2026-07-31, agy 1.1.9. The retired A4 assertion claimed "phase isolation respected".

- **Claim tested.** A `[PHASE: EXPLORATION]` tag prevents the peer from editing files.
- **Y.** The peer writes to a throwaway file in its workspace.
- **The confound.** The original probe sent the tag AND explicit prose prohibitions together, so a pass
  could only ever prove the prose worked. It violated this file's own rule: only C differs.

| Trial | Tag | Prose prohibitions | Y (edit made?) |
|---|---|---|---|
| Control | present | present | 0 — proposed only |
| Treatment | present | **removed** | **1 — edited immediately** |

- **Result.** The tag is NOT load-bearing. Asked directly, the peer said the tag "made no difference"
  and that the explicit prose was what constrained it.
- **Outcome.** A4 retired from the suite — no probe should be maintained for a capability that does not
  exist. The durable rule: **carry the forbidden-actions prose in every payload; never rely on a mode
  tag as a safety mechanism.**
- **The lesson this file exists to teach:** the original probe passed for four months while testing
  nothing. Isolate the control, or you are measuring the wrong variable.
```

- [ ] **Step 2: Verify A4 is gone from the suite**

Run: `grep -n 'A4' agy-autotrain/verify/assertions.md`
Expected: no matches in the table (a prose mention of the retirement is fine).

- [ ] **Step 3: Commit**

```bash
git add agy-autotrain/verify/probe-design.md agy-autotrain/verify/assertions.md
git commit -m "docs(verify): retire the confounded phase-tag probe, keep its evidence"
```

---

### Task 8: Document the enum, declare awk, wire the tests

**Files:**
- Modify: `agy-autotrain/verify/README.md`
- Modify: `.claude/recommended-tools.json`
- Modify: `justfile`

- [ ] **Step 1: Document the status enum in `verify/README.md`**

Add after the "The pieces" table:

```markdown
## Status columns

`assertions.md` carries one status column per driver (`dotnet`, `classic`), read by the SessionStart
gate in `.claude/hooks/agy-verify-reminder.sh`.

| Token | Meaning | Gate |
|---|---|---|
| `PASS <ver>` | Observed to pass at that agy version | silent while the version is current |
| `FAIL <ver>` | Observed to fail | **always nags** |
| `PARTIAL <ver>` | Some parts unrun — work in progress | **always nags** |
| `ACKED <ver>` | Verified, unresolvable by us, disposition recorded | silent while current |
| `N/A` | Not applicable to that driver | always silent |

**Unresolved states nag; only resolved or explicitly-dispositioned states can be silent.** A `FAIL`
cannot be quieted by bumping a version — that is deliberate, and it is the whole point of the column.
A new row starts at `PARTIAL <live>`.
```

- [ ] **Step 2: Declare `awk`**

Insert before the closing `]` of `.claude/recommended-tools.json`, after the `mlc` entry:

```json
  ,{
    "name": "awk",
    "why": "Read the per-driver status columns in agy-autotrain/verify/assertions.md. The SessionStart verify gate nags when awk is absent rather than failing silent, so a missing awk is visible but blocking.",
    "install": "Ships with Git for Windows (/usr/bin/awk); otherwise: winget install GnuWin32.Gawk",
    "in_path": "awk"
  }
```

- [ ] **Step 3: Verify the JSON still parses**

Run: `jq -e 'length' .claude/recommended-tools.json`
Expected: a number one greater than before the edit.

- [ ] **Step 4: Add the just recipe**

Append to `justfile`, mirroring `seed-sync-check` at L26-27:

```
# Fixture-test the SessionStart verify gate (agy-autotrain/verify/testdata).
check-verify-hook:
    bash agy-autotrain/verify/testdata/run-hook-tests.sh
```

- [ ] **Step 5: Run it**

Run: `just check-verify-hook`
Expected: `11 passed, 0 failed` (12 where no driver CLI is on PATH).

- [ ] **Step 6: Commit**

```bash
git add agy-autotrain/verify/README.md .claude/recommended-tools.json justfile
git commit -m "docs(verify): document the status enum, declare awk, wire the hook tests"
```

---

### Task 9: End-to-end verification on the real repo

**Files:** none modified — this task only observes.

- [ ] **Step 1: Fire the hook against the real working tree**

Run:

```bash
printf '{"cwd":"%s"}' "$(pwd)" | bash .claude/hooks/agy-verify-reminder.sh
```

Expected: a nag naming `A2 [dotnet] PARTIAL 1.1.1 (live 1.1.9)` plus the classic-column `PARTIAL` rows.

**This is success, not a regression.** The harness is telling the truth about its own coverage for the first time: A2's oversized-payload half was never re-run, and no probe has ever been run under clavity-classic. Do not tune it away.

- [ ] **Step 2: Confirm the suite is green and nothing else moved**

Run: `just check-verify-hook && git status --porcelain`
Expected: `11 passed, 0 failed` (12 on a driver-less box), and no modified files beyond those committed above.

- [ ] **Step 3: Record the outcome**

Update the durable project memory with the commit range and the fact that the gate now nags on this repo by design.

---

## Self-review

**Spec coverage.** All 10 deliverables map to tasks: hook → 3 · assertions.md → 4 · agy-curate → 5 · downstream docs → audited in the spec, no work needed · run-verification → 6 · probe-design → 7 · verify/README → 8 · recommended-tools → 8 · testdata + runner → 1, 2 · phase-tag rule → 7.

**Migration order.** The spec requires the table before the hook. Tasks 1-3 write tests and the hook *before* Task 4 converts the table, which inverts that — deliberately, because TDD needs a RED test first and the fixtures are self-contained. The ordering constraint is about *landing*, so Tasks 3 and 4 must be pushed together, or Task 4 must land first. **If splitting across pushes, land Task 4 before Task 3.**

**Type consistency.** `$2`/`$3`/`$4` mean id/dotnet/classic in Tasks 1-4 and 9. Token spellings (`PASS`/`FAIL`/`PARTIAL`/`ACKED`/`N/A`) are identical across the hook, fixtures, curate skill, and README. The runner's `run_case` signature is unchanged between Tasks 1 and 2.

**Unverified citation, flagged rather than asserted.** The classic-driver fallback path
`${LOCALAPPDATA}/Programs/clavity-classic/clavity.exe` mirrors the verified clavity-dotnet layout, but
clavity-classic is **not installed on this machine** — `%LOCALAPPDATA%/Programs/` contains
`clavity-dotnet`, `agy-autotrain` and `commonmemory` only. It is therefore a pattern-match, not a
measurement. Confirm it against the classic installer before relying on it; if it is wrong the fallback
simply never fires and detection degrades to `command -v clavity`, which is the pre-existing behaviour,
so a wrong guess is harmless rather than dangerous.

**Known gaps, stated rather than hidden.** (1) A second Markdown table in `assertions.md` would have its rows read as data — measured to be a non-issue today (one table) and judged below the severity floor by the panel. (2) `no-columns.md` may nag via `blank` rather than `NOROWS` depending on cell count; Task 3 Step 2 accepts either, since both are nags. (3) The `ACKED` disposition reference is a convention the gate cannot enforce — by design, since the hook never parses prose.

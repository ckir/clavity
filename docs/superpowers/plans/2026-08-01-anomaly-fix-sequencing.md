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

> ## ⚠ AMENDMENT (2026-08-01, owner-approved, agy-concurred) — SUPERSEDES Steps 2, 5 and 6 below
>
> Executing Step 1 produced a measurement that **invalidates the rule Step 2 states**. Both changes below
> were consulted with agy under AGY-FIRST, agy initially recommended otherwise, was sent to the raw
> measurement files, and **reversed its position on all three points**. The owner then ruled.
>
> **1. The per-file threshold is not a sound rule — the quantity it thresholds is not stable.**
> MEASURED, three runs of the same suites on the same commit and machine
> (`.clavity/seams/task1-measure-run{1,2,3}-*.txt`): per-file wall clock swings up to **5.9×**, driven by
> position in the run, because the first suite executed absorbs pwsh + Pester cold-start for the whole run.
> `agy-after-reminder` measured **48.9s** running first and **8.3s** running last. `release-lib` measured
> **25.7s** first and **4.8s** last. Applying ">= 20s ⇒ SLOW" to those two gives the OPPOSITE answer
> depending only on sort order. Eight of twelve suites were stable within 15%; four were not.
> **A rule that cannot be re-applied to get the same answer is not a rule.**
>
> **REPLACEMENT RULE — measure the recipe, not the files.** Choose a candidate FAST set from warm per-file
> evidence, then **measure `just test-scripts-fast` as a single batch** and require it under the ceiling.
> The per-file table stays in `_partition.md` as *evidence*, never as the decision rule. This also collapses
> rule and oracle into one measurement — Step 6 already measured the recipe.
>
> **⚠ Do not assume batching is cheap.** MEASURED (`.clavity/seams/task1-batch-measurement.txt`): the
> 13-file FAST set as one `Invoke-Pester` process ran **94.2s / 75.1s / 73.7s**, against a **65.8s** warm
> per-file sum. Batching is *slower*, not faster — it saves repeated pwsh startup but adds cold module load
> and cross-file accumulation. agy predicted "~15-20s" and was refuted by 4-5×.
>
> **2. Step 5 is DROPPED. No test job goes on the pre-push hook.**
> `lefthook.yml:11-18` records that a `scripts-tests` job — the full Pester suite — **already lived on
> pre-push and was deliberately removed**, because git opens the SSH connection *before* the hook runs and
> the idle time made GitHub hang up mid-push: *"observed as 'Connection to ssh.github.com closed by remote
> host.' after every gate had already passed, with nothing ever pushed."* `lefthook.yml:17` requires every
> job to stay "in the SECONDS range". The current hook totals ~36s (`lefthook.yml:43`); the measured fast
> batch would take it to **110-130s**.
> **Anomaly #4 is an agent-ergonomics defect — an agent hitting the 600s FOREGROUND TOOL CAP when it runs
> the suite. It is closed entirely inside the `justfile`.** A pre-push presence was never required to close
> it, and Step 5 would have reinstated a failure this repo already suffered and wrote down.
> `lefthook.yml` is **not modified by this task at all.**
>
> **Structural selection was also considered and REJECTED by measurement.** A rule of "FAST = spawns no
> `git`/`bash` child process" does not predict cost here: `docs-audit` has **zero** subprocess matches and
> runs **120.6s**, while `agy-after-reminder` has **nine** and runs **8.3s** warm
> (census in `.clavity/seams/task1-batch-measurement.txt`).

**Files:**
- Modify: `justfile:91-92`
- Create: `scripts/tests/_partition.md`
- ~~Modify: `lefthook.yml`~~ — **DROPPED by the amendment above. Do not touch `lefthook.yml`.**

- [ ] **Step 0: State verification**

Confirm each; if any differs, STOP and report `STATE_MISMATCH: <what>`:
1. `justfile:91-92` is exactly:
   ```
   test-scripts:
       pwsh -c "Invoke-Pester scripts/tests -Output Detailed -CI"
   ```
2. `ls scripts/tests/*.Tests.ps1 | wc -l` returns `24`.
3. `git diff --stat lefthook.yml` is empty and stays empty — this task must not modify that file.

- [ ] **Step 1: Measure per-file runtime — this is the partition input, not a guess**

Run:
```bash
pwsh -c "foreach (\$f in Get-ChildItem scripts/tests/*.Tests.ps1) { \$sw=[Diagnostics.Stopwatch]::StartNew(); \$r=Invoke-Pester \$f.FullName -Output None -PassThru; \$sw.Stop(); '{0,-45} {1,7:N1}s {2,4} tests' -f \$f.Name, \$sw.Elapsed.TotalSeconds, \$r.TotalCount }"
```
Expected: 24 lines, each naming a file, its seconds and its test count. **Record this output verbatim into `scripts/tests/_partition.md`** — it is the evidence for the split and the thing a future reader needs when the partition looks arbitrary.

Sum the test counts. **It must equal 358.** If it does not, STOP and report `STATE_MISMATCH: test count is <n>, not 358` — the plan's oracle depends on that number.

- [ ] **Step 2: Choose the cut — candidate set, then measure the RECIPE** *(rewritten by the amendment)*

Step 1's per-file numbers are **evidence, not the rule**. Take the *warm* readings only — discard each run's first entry, which absorbs cold-start for the whole run — and form a candidate FAST set from the cheapest suites.

Then **measure the candidate set the way the recipe will actually run it**: one `pwsh` process, one `Invoke-Pester` over the whole list, wall clock timed from OUTSIDE the process so startup counts.

```bash
pwsh -NoProfile -c "\$r = Invoke-Pester @('scripts/tests/<A>.Tests.ps1','scripts/tests/<B>.Tests.ps1') -Output None -PassThru; 'Total={0} Failed={1}' -f \$r.TotalCount, \$r.FailedCount"
```

Run it **three times** and take the slowest. **Ceiling: the FAST batch must run in under 120s** — comfortably inside the 600s foreground tool cap, which is the only budget that still applies now that Step 5 is dropped. Do not average, and do not accept a single run: the first run after an idle period is systematically slower (MEASURED: 94.2s, then 75.1s, then 73.7s on an unchanged set).

**If the batch exceeds 120s:** first confirm the machine was actually idle and re-measure — a contended host is the likeliest cause, and it is what produced the 94.2s outlier above. If it is still over on a quiet machine, move the most expensive suite to SLOW and re-measure.

> **⚠ MOVING A SUITE CHANGES THE PINNED COUNTS. This is the one number in this task you MAY change, and only this way.**
> `157` and `201` are **derived facts about the split below**, not invariants. **The invariant is that every
> suite stays reachable from a recipe — see Step 6's structural oracle. `358` is a SNAPSHOT of the suite as
> it stood at the end of this task, and later tasks legitimately raise it by adding tests.**
> If you move a suite, you MUST: recompute both halves' `Total`; update the table in this step, the numbers
> in Step 6, and the commit message in Step 7 so all three agree; and record in `_partition.md` which suite
> moved and the measurement that forced it. **What you may never do is make a count go DOWN, or reach any
> number by deleting, skipping, or un-listing a test.** Reachability is the coverage guard; the counts are
> bookkeeping that records it.

**The measured FAST set is recorded below.** It was derived by exactly this procedure:

| | Files | Tests | Batch wall clock |
|---|---|---|---|
| FAST | 13 | **157** | 73.7s / 75.1s / 94.2s |
| SLOW | 11 | **201** | ~670s (exceeds the cap — must be backgrounded) |
| | 24 | **358** | |

**FAST (13):** `generate-scoped-manifest`, `BashHookHelpers`, `check-member-docs`, `check-user-facing-docs`, `check-seed-artifacts-synced`, `check-roster`, `check-seed-budget`, `check-agy-discipline-skills`, `drain-lib`, `release-lib`, `register-plugin`, `agy-after-reminder`, `check-growth-budget`

**SLOW (11):** `abort-drain`, `accept-drain`, `agy-anomaly-reminder`, `agy-liveness-check`, `agy-seam-inject`, `agy-test-audit-reminder`, `check-core-integrity`, `check-plugin-namespace`, `compute-release`, `docs-audit`, `drain-knowledge`

**SLOW still exceeds the 600s cap, and that is accepted, not overlooked.** Splitting it further would need a three-way partition and buys nothing: an agent must background it either way. The justfile comment states this so nobody runs it in the foreground and reports a hang.

- [ ] **Step 3: Write `scripts/tests/_partition.md`**

```markdown
# Test suite partition

`just test-scripts` ran 358 tests in a single Pester invocation, measured at 917s, 650s, 586s and 590s on
four consecutive runs against a 600s foreground tool cap. It STRADDLED the cap: it worked until it did not.

The split is decided by measuring the RECIPE as one batch, not by thresholding per-file numbers.

**Per-file runtime here is not a stable quantity, so it cannot be a rule.** Measured three times on one
commit and machine, the same suite swings up to 5.9x purely on its position in the run, because whichever
suite executes first absorbs pwsh + Pester cold-start for the whole run: `agy-after-reminder` measured
48.9s first and 8.3s last; `release-lib` measured 25.7s first and 4.8s last. Eight of twelve suites were
stable within 15%; four were not. A ">= 20s means SLOW" rule classifies those four differently depending
only on sort order, so it is not reproducible and is not used.

**Batching is not a saving.** The 13 fast suites as one `Invoke-Pester` process measured 94.2s / 75.1s /
73.7s, against a 65.8s warm per-file sum. One process saves repeated pwsh startup but pays cold module
load once and accumulates across files.

- `just test-scripts-fast` — the agent inner-loop gate. **157 tests, measured 74-94s.** Ceiling: 120s.
- `just test-scripts-slow` — everything else. **201 tests, ~670s.** NOT on any git hook; it exceeds the
  600s foreground tool cap and must be BACKGROUNDED by an agent.
- `just test-scripts` — both, unchanged in meaning: still every test.

**Neither recipe is wired to `lefthook.yml`, deliberately.** The full suite used to run on pre-push and
was removed because git opens the SSH connection before the hook and the idle time made GitHub hang up
mid-push (`lefthook.yml:11-18`). This split exists to solve the 600s *foreground tool cap* an agent hits,
which is a justfile concern only.

**Every test remains reachable from some recipe — that is the invariant, and it is checked structurally
(the union of the two recipes' file lists must equal `scripts/tests/*.Tests.ps1` exactly).** The sum of the
two halves was **358** when this split was made; later work that ADDS tests raises it, which is expected. A
sum that FALLS is coverage loss wearing a passing gate. If you move a file between halves, re-measure and
update the table below; do not edit it from memory.

## Measured runtimes

<paste the Step 1 output verbatim here>
```

Replace `<paste the Step 1 output verbatim here>` with the actual Step 1 output. Leaving the angle-bracket text in place is a plan failure.

- [ ] **Step 4: Rewrite the justfile recipes**

Replace `justfile:91-92` with the following. `<FAST-FILES>` and `<SLOW-FILES>` are the `scripts/tests/<name>.Tests.ps1` paths from Step 2, each **individually quoted and separated by commas** — see the warning immediately below, which is not optional:

**The paths must be individually quoted and COMMA-separated.** `@('a.Tests.ps1 b.Tests.ps1')` is a
one-element array holding a single string with spaces in it, and Pester will look for one file with that
literal multi-word name and fail `PathNotFound`. Write `@('a.Tests.ps1', 'b.Tests.ps1')`.

```
# Fast script gate: the agent inner-loop recipe. NOT on any git hook - see scripts/tests/_partition.md.
# The set was chosen by measuring THIS RECIPE as one batch, not by thresholding per-file times, which
# swing up to 5.9x on run order. Every test is still reachable: fast + slow == the whole suite.
test-scripts-fast:
    pwsh -c "Invoke-Pester @('scripts/tests/<FAST-1>.Tests.ps1', 'scripts/tests/<FAST-2>.Tests.ps1') -Output Detailed -CI"

# Slow script gate. EXCEEDS the 600s foreground tool cap - an agent MUST background this and read the
# result from the task output file, never run it in the foreground.
test-scripts-slow:
    pwsh -c "Invoke-Pester @('scripts/tests/<SLOW-1>.Tests.ps1', 'scripts/tests/<SLOW-2>.Tests.ps1') -Output Detailed -CI"

# The whole suite, unchanged in meaning. Same cap warning as test-scripts-slow.
test-scripts:
    pwsh -c "Invoke-Pester scripts/tests -Output Detailed -CI"
```

- [ ] ~~**Step 5: Wire the cadence into lefthook**~~ — **DROPPED. `lefthook.yml` is not modified.**

**Do not add any Pester job to `lefthook.yml`.** See the amendment at the top of this task: the full suite already lived on that hook and was removed because the idle SSH connection made GitHub hang up mid-push, and `lefthook.yml:17` requires every job to stay "in the SECONDS range" (current total ~36s; the fast batch measures 74-94s).

Anomaly #4 is the 600s **foreground tool cap** an agent hits — closed entirely by the justfile split. The cadence instead lives as a comment directly above the `test-scripts-slow` recipe in the justfile:

```
# CADENCE: on no git hook at all, and it exceeds the 600s foreground tool cap. Run it before any release, and after any
# change to a file listed as SLOW in scripts/tests/_partition.md. A recipe nobody runs is a retired test.
```

- [ ] **Step 6: Verify the split — the three oracles**

```bash
just test-scripts-fast 2>&1 | tail -3
```
Expected: `Failed: 0`, `Total: 157`, completing under 120s. **Time it from outside the process** — the recipe's own output does not include pwsh startup, and startup is part of what a caller pays.

(`157` is the count for the pinned split. If Step 2's over-ceiling branch fired and you moved a suite, use your recomputed number here — the split changed, so this derived number changed with it. The sum below did not.)

```bash
just test-scripts-slow 2>&1 | tail -3
```
**Run this with `run_in_background` and read the task output file** — it exceeds the foreground cap.
Expected: `Failed: 0`.

**The coverage oracle. Read this carefully — the invariant is STRUCTURAL, not a number.**

> **⚠ CORRECTED 2026-08-02.** This step originally declared `358` an invariant that "may never change".
> **That was wrong, and it was wrong in a way that breaks every later task.** MEASURED during Task 2: adding
> five tests to a file in the FAST set took the fast `Total` from 157 to 162. Tasks 3, 4 and 6 all add tests
> too. A plan that pins a total and then instructs you to add tests is self-contradictory, and the way out
> an implementer reaches for is to stop adding tests or to fudge the number — which is precisely the
> coverage-gaming this oracle exists to prevent.

**What must never change is that EVERY suite is reachable from a recipe.** Assert it structurally — it is exact, and it costs nothing:

```bash
# The union of the two recipes' file lists must equal the directory: no omission, no duplicate.
diff <(ls scripts/tests/*.Tests.ps1 | xargs -n1 basename | sort) \
     <(grep -oE "scripts/tests/[A-Za-z0-9._-]+\.Tests\.ps1" justfile | xargs -n1 basename | sort -u)
```
Expected: **no output, exit 0.** Any line means a suite is unreachable from both recipes — **STOP and report it.** That is the defect the number was only ever a proxy for.

**VERIFIED NON-VACUOUS (2026-08-02), because an oracle nobody mutated is a claim nobody checked:** on the clean tree it exits 0 with no output and both sides list 24 files; deleting one suite from the justfile's lists makes it exit 1 and print the missing name. Both sides being non-empty is part of the check — an empty-vs-empty `diff` reports success while measuring nothing.

**Then record, do not assert, the counts:** run both recipes, confirm **`Failed: 0` on each**, and write the two `Total` values and their sum into `scripts/tests/_partition.md`. **The sum is a snapshot of the suite as it stands, and it RISES whenever a task adds tests — that is correct and expected.** At the end of Task 1 it was 157 + 201 = 358.

**What is still forbidden:** reaching any number by deleting a test, skipping a test, or removing a file from both recipes. If a count goes **down**, STOP and report — that is coverage loss wearing a passing gate.

**A third oracle, because the count alone is gameable:** `git diff --stat lefthook.yml` must be **empty**. The amendment drops Step 5, and a well-meaning implementer "completing" the plan by wiring the hook would reintroduce the exact defect this task was amended to avoid.

**Why `Total` and not `Passed`:** `scripts/tests/agy-anomaly-reminder.Tests.ps1:220` skips conditionally — `Set-ItResult -Skipped -Because 'this host does not enforce the read deny'` — on any host where `icacls` cannot actually deny the current process a read. There, Pester reports `Passed: 357, Skipped: 1, Total: 358`, and a `Passed == 358` oracle would halt on a healthy run. `Total` matches what Step 1's `$r.TotalCount` measured, so the two numbers are directly comparable.

- [ ] **Step 7: Commit**

If Step 2's over-ceiling branch fired and you moved a suite, **change the two half-counts in the message below to what you actually measured** — and leave `358` alone. A commit message stating a split the repo does not have is a lie a future reader will trust.

```bash
git add justfile scripts/tests/_partition.md
git commit -m "fix(tests): split the script gate, measured as a recipe not per file

just test-scripts straddled the 600s foreground tool cap - measured at 917s,
650s, 586s and 590s across four consecutive runs. Straddling is worse than being
reliably over: it works until it does not.

The split is NOT a per-file runtime threshold. Measured three times on one commit
and machine, a suite's wall clock swings up to 5.9x purely on its position in the
run, because whichever suite runs first absorbs pwsh and Pester cold-start for the
whole run - agy-after-reminder measured 48.9s first and 8.3s last. A threshold on
that quantity classifies four of 24 suites differently depending on sort order, so
it is not reproducible. The rule is instead: pick a candidate set, then measure the
recipe as one batch and require it under the ceiling. Per-file numbers stay in
scripts/tests/_partition.md as evidence.

Batching is not a saving: the fast set as one process measured 74-94s against a
65.8s warm per-file sum.

lefthook.yml is deliberately untouched. The full suite already lived on pre-push
and was removed because the idle SSH connection made GitHub hang up mid-push
(lefthook.yml:11-18). This anomaly is the 600s FOREGROUND TOOL CAP an agent hits,
which the justfile split closes on its own.

157 fast + 201 slow = 358 - the guard against making the fast number look good by
dropping coverage."
```

---

### Task 2 (M2 — S): auto-discovery sync gate

**Closes anomaly #6.** **Do NOT start until Task 1 is committed.**

**Files:**
- Modify: `scripts/check-seed-artifacts-synced.sh:15-27`
- Modify: `scripts/tests/check-seed-artifacts-synced.Tests.ps1`

- [ ] **Step 0: State verification**

1. `scripts/check-seed-artifacts-synced.sh:15` is `for rel in \`, and the loop it opens ends at `:27` with `  knowledge/agy-capabilities.md ; do`. **(Corrected 2026-08-01: this plan originally cited `:25`. MEASURED — the terminator is at `:27`; `:25` is `hooks/agy-anomaly-reminder.sh`, added by a later commit that shifted the block by two lines. The substantive fact Step 3 depends on — that 15-27 is exactly the `for rel in \ … done` loop — is unchanged.)**
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

> **⚠ AMENDED 2026-08-01 (owner-approved).** The original text of these tests called bare `& bash`.
> **MEASURED: on a dev box `bash` resolves to `C:\WINDOWS\system32\bash.exe` — the WSL shim — which has no
> `jq`, so the script hits its own `jq is required` early-exit and the assertions measure nothing.** The
> repo already solved this: `scripts/tests/BashHookHelpers.ps1:4-11` documents the exact non-determinism
> and `Get-GitBashOrThrow` pins Git Bash by absolute path. This file's own `BeforeAll` already wraps it as
> **`Invoke-SeedSync`**, returning an object with `.ExitCode`, `.StdOut`, `.StdErr` — the two pre-existing
> tests use it. **Use it. Never `& bash` and never `$LASTEXITCODE` in this file.**

```powershell
    It 'FIRES when a new shared file exists in clavity-dotnet only' {
        # The defect this milestone fixes: under the old allow-list, a file nobody enrolled was never
        # compared, so it could exist in one plugin only and the gate stayed green. Omission was
        # indistinguishable from synchronisation.
        # ASSERT THE DIRECTION, not just the filename: this probe exercises the `! -f "$C/$rel"` branch
        # only. Its mirror below covers the other branch. A filename-only assertion cannot tell them apart.
        $probe = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/skills/zz-discovery-probe/SKILL.md'
        New-Item -ItemType Directory -Path (Split-Path $probe) -Force | Out-Null
        Set-Content $probe "---`nname: zz-discovery-probe`n---`nprobe`n" -Encoding ascii
        try {
            $r = Invoke-SeedSync
            $r.ExitCode | Should -Not -Be 0
            "$($r.StdOut)`n$($r.StdErr)" |
                Should -Match 'zz-discovery-probe/SKILL\.md exists in clavity-dotnet/plugin but NOT in clavity-classic/plugin'
        } finally { Remove-Item (Split-Path $probe) -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FIRES when a new shared file exists in clavity-classic only' {
        # The MIRROR, and it is not redundant. MEASURED: without it, NO test in this file ever creates a
        # file present in classic and absent from dotnet, so the walk's `[ ! -f "$D/$rel" ]` branch is
        # never exercised — it can be DELETED OUTRIGHT and all other tests stay green. A guard no test
        # reaches is not a guard.
        $probe = Join-Path $script:RepoRoot 'clavity-classic/plugin/skills/zz-probe-classic-only/SKILL.md'
        New-Item -ItemType Directory -Path (Split-Path $probe) -Force | Out-Null
        Set-Content $probe "---`nname: zz-probe-classic-only`n---`nprobe`n" -Encoding ascii
        try {
            $r = Invoke-SeedSync
            $r.ExitCode | Should -Not -Be 0
            "$($r.StdOut)`n$($r.StdErr)" |
                Should -Match 'zz-probe-classic-only/SKILL\.md exists in clavity-classic/plugin but NOT in clavity-dotnet/plugin'
        } finally { Remove-Item (Split-Path $probe) -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'stays GREEN for every intentionally-divergent twin' {
        # The five files that legitimately exist in one plugin only. If discovery flagged these the gate
        # would be permanently red and would be routed around.
        $r = Invoke-SeedSync
        $r.ExitCode | Should -Be 0
        "$($r.StdOut)`n$($r.StdErr)" | Should -Not -Match 'agy-drive-session-reset|ls-driving|ls-pairing|skills/driving|skills/responder'
    }

    It 'still FIRES when an enrolled shared file differs in content' {
        # Regression guard: discovery must not lose the behaviour the allow-list already had.
        $f = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks/agy-after-reminder.sh'
        $orig = Get-Content $f -Raw
        try {
            Add-Content $f "`n# discovery drift probe`n"
            (Invoke-SeedSync).ExitCode | Should -Not -Be 0
        } finally { Set-Content $f $orig -NoNewline }
    }

    It 'FIRES when hooks.json is missing from one plugin, despite being compared elsewhere' {
        # compared_elsewhere() delegates hooks.json CONTENT to the jq blocks further down, but it must not
        # become an escape hatch: it requires the file on BOTH sides, so a deletion still trips the walk.
        #
        # ⚠ ASSERT THE WALK'S OWN LINE, NOT MERELY THAT "hooks.json" APPEARS SOMEWHERE. MEASURED: with the
        # file absent, FOUR messages name hooks/hooks.json — the walk's existence line, plus three from the
        # pre-existing jq blocks (jq errors on the missing file, its process substitution yields empty
        # output, and `diff -q` reports that as differing). A loose /hooks\.json/ assertion therefore passes
        # even when compared_elsewhere() is gutted to a bare `return 0`, so the mutation row that is supposed
        # to prove the two-sided guard proves NOTHING. Only the line below comes from the walk.
        #
        # Park the backup OUTSIDE the plugin trees: a *.bak beside the original is itself discovered and
        # reported as classic-only, which is noise this assertion should not have to tolerate.
        $f   = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks/hooks.json'
        $bak = Join-Path ([IO.Path]::GetTempPath()) 'clavity-classic-hooks-json.testbak'
        Move-Item $f $bak -Force
        try {
            $r = Invoke-SeedSync
            $r.ExitCode | Should -Not -Be 0
            "$($r.StdOut)`n$($r.StdErr)" |
                Should -Match 'hooks/hooks\.json exists in clavity-dotnet/plugin but NOT in clavity-classic/plugin'
        } finally { Move-Item $bak $f -Force }
    }
```

- [ ] **Step 2: Run them and verify the FIRST goes RED**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-seed-artifacts-synced.Tests.ps1 -Output Detailed -CI"`

Expected: **the two probe tests FAIL** — `FIRES when a new shared file exists in clavity-dotnet only` and `FIRES when a new shared file exists in clavity-classic only` (the allow-list ignores both probes, so the gate exits 0). **The other three pass already** — they describe behaviour the allow-list also has, including the `hooks.json`-missing case, which the pre-existing jq comparisons already catch. **Only two of the five can go red here, and that is correct, not a shortfall.** Do not "fix" the other three.

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

# A SECOND and DIFFERENT reason to skip the byte-diff: the file is present in BOTH trees and is compared
# further down by a NARROWER rule that a raw byte-diff cannot express. Kept separate from divergent() on
# purpose -- that list means "exists in one plugin only", and its documented regeneration command
# (the find/diff above) can never emit a file that exists on both sides. Merging the two would make the
# regeneration command permanently disagree with the list, and the next maintainer would delete the odd
# entry or assume the command is broken.
#
# NOT AN ESCAPE HATCH: it REQUIRES the file on both sides before delegating. If hooks.json is deleted from
# one plugin, this returns 1, the walk falls through to the existence branches below, and the gate fires.
# Delegating content is not the same as waiving existence.
compared_elsewhere() {
  case "$1" in
    hooks/hooks.json)
      # Compared by the PostToolUse / PreToolUse / filtered-SessionStart jq blocks below, which tolerate
      # the variant-specific entry (classic carries an agy-drive-session-reset SessionStart command that
      # dotnet lacks -- MEASURED: the two manifests differ by exactly that one line). A byte-diff cannot
      # distinguish that legitimate variance from real drift; those jq rules can.
      [ -f "$D/$1" ] && [ -f "$C/$1" ] && return 0
      return 1 ;;
    *) return 1 ;;
  esac
}

# Union of both trees, so a file missing from EITHER side is caught (a one-sided walk would only catch
# files missing from the other plugin, never from its own).
for rel in $( { (cd "$D" && find hooks skills knowledge -type f 2>/dev/null)
                (cd "$C" && find hooks skills knowledge -type f 2>/dev/null); } | sort -u ); do
  divergent "$rel" && continue          # exists in ONE plugin only
  compared_elsewhere "$rel" && continue # in BOTH; content compared by the jq rules below
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

- [ ] **Step 4: Run the tests and verify ALL of them pass — five new, seven in the file**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-seed-artifacts-synced.Tests.ps1 -Output Detailed -CI"`
Expected: `Failed: 0`.

- [ ] **Step 5: Mutation-check the guards**

One at a time, apply the mutation **to the script**, re-run only this test file, confirm the NAMED test goes red, then restore. **A guard whose removal leaves the file green is not a guard — report it rather than papering over it.**

> **⚠ THIS TABLE WAS REWRITTEN 2026-08-01 — the previous version was itself vacuous.** Running it MEASURED
> that three of four rows did not prove what they claimed:
> - The `[ ! -f "$D/$rel" ]` row named a test whose probe lives in **dotnet**, so it exercises the *other*
>   branch. **No test in the file reached that branch at all — it could be deleted with the suite green.**
> - The `skills/` row named a test that modifies a **hooks** file, structurally immune to a skills-only
>   mutation. A different test went red instead.
> - The `compared_elsewhere()` row — the one flagged "matters most" — **did not fire**, because the
>   pre-existing jq blocks emit their own `hooks/hooks.json` messages and the loose assertion accepted them.
>
> A mutation table is a claim that each guard is load-bearing. **An unrun mutation table is a claim nobody
> checked.** Run every row.

| Mutation (in `check-seed-artifacts-synced.sh`) | Test that must go red |
|---|---|
| Delete the `[ ! -f "$C/$rel" ]` branch | `FIRES when a new shared file exists in clavity-dotnet only` |
| Delete the `[ ! -f "$D/$rel" ]` branch | `FIRES when a new shared file exists in clavity-classic only` |
| Add `hooks/agy-after-reminder.sh` to `divergent()` | `still FIRES when an enrolled shared file differs in content` |
| Remove `hooks/agy-drive-session-reset.sh` from `divergent()` | `stays GREEN for every intentionally-divergent twin` |
| **Weaken `compared_elsewhere()` to a bare `return 0` for `hooks/hooks.json`** (drop both `[ -f ... ]` checks) | `FIRES when hooks.json is missing from one plugin, despite being compared elsewhere` |

**Row 5 is the one that matters most, and it only works because the test now asserts the walk's own message.** It is the sole proof that the new exclusion is not a second allow-list carrying the very fail-open defect this milestone exists to remove. **If it does not go red, `compared_elsewhere()` is an escape hatch — STOP and report rather than proceeding.**

**Expect collateral reds and do not treat them as failures.** Row 4 also reds the pre-existing `passes (exit 0, reports in sync)` test, because the real repo's classic-only file stops being deny-listed. Note it and move on. What matters is that the NAMED test goes red in every row.

- [ ] **Step 6: Full gate**

```bash
just test-scripts-fast
```
Expected: `Failed: 0`, **`Total: 162`**. Then run `just test-scripts-slow` **with `run_in_background`, and BLOCK until it genuinely completes** — read its output file and confirm it reached a terminal `Tests completed` line before believing any number. Expected `Failed: 0`, `Total: 201`.

> **⚠ THE FAST COUNT RISES IN THIS TASK, AND THAT IS CORRECT.** It was `157` at the end of Task 1; this task adds five tests to `check-seed-artifacts-synced.Tests.ps1`, which lives in the FAST set, so it becomes **`162`** and the suite total becomes **`363`**. Task 1's Step 6 originally called `358` an invariant "that may never change" — **that was a defect in the plan, corrected 2026-08-02.** Do not try to make the total come out at 358, and do not delete or skip a test to get there.

**Run the structural coverage oracle** — this, not any number, is what guarantees nothing was dropped:

```bash
diff <(ls scripts/tests/*.Tests.ps1 | xargs -n1 basename | sort) \
     <(grep -oE "scripts/tests/[A-Za-z0-9._-]+\.Tests\.ps1" justfile | xargs -n1 basename | sort -u)
```
Expected: **no output, exit 0**, with both sides listing 24 files. Any output means a suite is unreachable from both recipes — STOP and report. A count that FALLS is likewise coverage loss wearing a passing gate.

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

**EXECUTE THE STEPS IN THIS ORDER: 1 (copy) → 4 (write the test) → 5 (observe RED) → 2 (classifier) and 3 (manifests) → re-run for GREEN.** The step numbers are the plan's; the order above is the execution order. Do this rather than applying the fix and stashing it back.

**Why not stash.** An earlier draft said `git stash push clavity-dotnet/plugin/hooks clavity-classic/plugin/hooks`. That does not work, and it fails in two different directions: the guard files are UNTRACKED at this point (created in Step 1), so `git stash push <path>` without `-u` ignores them entirely and leaves the Step 2 fix on disk — the false-positive test then passes and the RED is never observed. Adding `-u` stashes the untracked files themselves, deleting `agy-consult-guard-pre.sh` and `-post.sh` from disk, so the test errors on a missing hook instead of failing on behaviour. Plain TDD ordering avoids both.

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-consult-guard.Tests.ps1 -Output Detailed -CI"` against the freshly-copied, **unmodified** guard.

Expected RED: `does NOT treat a commit whose MESSAGE mentions the consult CLI as a consult` **must FAIL** — that is the false positive, and it is the one this milestone exists to remove. The other four blocks may pass or fail depending on whether the manifests are registered yet; only that one is the RED proof.

Then apply Steps 2 and 3 and re-run. Expected: `Failed: 0`.

**A guard test never observed failing proves nothing, and "never observed failing" is exactly how this guard reached production dead.** If the false-positive test passes against the unmodified copy, STOP and report it — either the fixture does not reproduce the defect or the classifier already changed.

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
    $manifestPath = Join-Path $Root $manifest
    # Test-Path is REQUIRED, not defensive politeness. This script sets $ErrorActionPreference = 'Stop'
    # at :14, and its own unit fixtures in scripts/tests/check-plugin-namespace.Tests.ps1 build minimal
    # trees containing plugin.json and build/members.json but NO hooks/hooks.json (MEASURED: zero
    # occurrences of 'hooks.json' in that test file). An unguarded Get-Content therefore throws
    # ItemNotFoundException and every fixture-based test in that suite fails.
    if (-not (Test-Path $manifestPath)) { continue }
    $json = Get-Content $manifestPath -Raw | ConvertFrom-Json
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

**Gaps closed in-document:** the M1 threshold was under-specified in the spec, was then specified as ">= 20s, fall back to 10s, else STOP", and was **superseded on 2026-08-01 by the amendment at the head of Task 1** — measurement showed per-file runtime is not stable enough to threshold (5.9x swing on run order), so the rule is now "choose a candidate set, measure the recipe as one batch"; the Rust tripwire's insertion point depends on a local whose name I did not verify, so Task 6 Step 5 instructs reading it and reports `STATE_MISMATCH` rather than guessing.

**Gaps flagged, with where they resolve:**
1. **Task 3 Step 8 edits `~/.claude/settings.json`, the operator's file.** The plan says confirm first. It cannot be resolved in-document — it is the operator's call at execution time.
2. **Task 5 has no mechanical oracle.** Stated in the spec and again here. Resolves as a walkthrough recorded in its commit message.
3. **Task 6's tripwire is a heuristic.** It cannot enumerate every mis-encoding, and the spec's two-layer design is the answer: the authoring policy covers the general case. Not resolvable further without breaking the transport contract.
4. **The exact FAST/SLOW file lists cannot be written before execution** — they are a measurement, taken in Task 1 Step 1. This is the one place the plan defers a value, and it defers it to a measurement with a stated rule, not to judgement.

**Every stated requirement maps to a section.** The spec's Known Limits 1-5 are reflected: #1 (M5 prose) in Task 5 Step 3; #2 (M4 raises a floor) in Task 4's commit message; #3 (M2 inverts a failure mode) in Task 2 Step 3's comment; #4 (stop-after-M2 leaves the guard dead) is why Task 3 immediately follows; #5 (triage has no HELD state, deliberately) is untouched by this plan by design.

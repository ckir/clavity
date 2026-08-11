# Stage 2 Fix Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> 🔴 **IF YOU DISPATCH PER-TASK SUBAGENTS, PASTE THE "Standing rules for every task" SECTION INTO EVERY DISPATCH, VERBATIM.** That section is not preamble — it carries four constraints no individual task restates, and a subagent handed only its own task section will not see any of them:
> **(1) do not push** — a subagent finishing the last task has otherwise been given no reason not to; **(2) the single decision rule for `git checkout --`**, without which the safe use in Task 3 reads as a licence for the destructive one in Task 4; **(3) the re-entrancy rule**, which is what makes a resumed or retried task safe; and **(4) the prerequisites**, which nothing else verifies.
>
> The tasks themselves are otherwise self-contained: each carries its own state-verification, its own file list, its own encoding requirements and its own commit command.

**Goal:** Close the 17 Stage 2 findings across `agy-autotrain/`, `ghidrust/` and `commonmemory/` without changing what `scripts/check-injected-context.ps1` computes, so the AGY-CAPSTONE GREEN at `06a39afe47ae479bcba5101e7142e63f188f9031` stands.

**Architecture:** Five commits. Task 0 commits the one pending working-tree capture so the corpus is stable and F16's measured counts do not move under the batch. Commits 1-4 are the spec's Groups A, C+D2, D, B in that order. Only commit 3 edits `check-injected-context.ps1`, and only its **comments** — so if the owner ever reads the capstone-invalidation rule strictly, commit 3 alone is the re-capstone target.

**Tech Stack:** PowerShell 7 (`pwsh`) + Pester 5 for the gate and its suites; Bash for the corpus hooks; Rust (cargo/nextest) for ghidrust; `just` as the task runner.

---

## Corrections folded in from measurement

The spec was owner-approved before execution. Verifying every citation against the tree found **five** defects. Each is corrected below, with the measurement that settled it. **Nothing here changes an owner ruling** — each correction preserves the ruled intent and fixes a factual premise underneath it.

| # | Spec said | Measured | Correction |
|---|---|---|---|
| C1 | F16's `reason`: "49 non-ASCII — 4 on the header line, **6** in pending bullets, and the remainder across **34 lines** of drain-log comments" | At HEAD: 49 total = 4 header + **9** pending + 36 chars across **28** drain-log lines. After Task 0 commits the pending capture: **51** = 4 + **11** + 36/28 | Counts corrected, and the count is demoted to a dated snapshot — the permanence argument rests on the append-only drain logs, not on an exact total that moves with every capture |
| C2 | F1: add the size assertion to `scripts/tests/drain-knowledge.Tests.ps1`, "which already reads the canonical file at `:57` and runs under `just test-scripts-fast`" | That file is registered in **`test-scripts-slow`** (`justfile:108`), and `:57` writes `"content of <rel>"` into a **synthetic temp repo** — it never reads the canonical file | Enforcement moves to a new `scripts/check-cheatsheet-budget.ps1`, mirroring its two siblings `check-seed-budget.ps1` / `check-growth-budget.ps1`, with a Pester suite registered in the **fast** half |
| C3 | Group B: correct the false round-trip claim in "the comment" (singular, `skill_asset.rs:53`) | `main.rs:30-31` carries the **same** false claim, and `ghidrust/CONTRIBUTING.md:80` already strips the header with `awk '/^---/{p=1} p'` | The fold covers all three sites. The awk is what generated today's plugin copy — it independently confirms the strip boundary |
| C4 | D1 verification: "confirm the path-candidate count drops from 5 with 0 failures to 5 with 0 failures" | A probe that cannot return a failing answer | Real oracle: bypass the extension allowlist and require failures **1 → 0**. Measured today: as-shipped 5 candidates / 0 failures; with `iss` added, 12 candidates / **1** failing token (`installer/_shared/plugin-registration.iss` → `unclassified`) |
| C5 | D2 `released` rule: "present in the **installed plugin tree**" | 5 of the 7 items are binary-level .NET fixes with no plugin file to inspect | Rule restated as commit **ancestry vs the latest release tag** (`clavity-v17` @ `4a74496`). It independently reproduces the spec's one known answer and agrees with the measured install |

**C5 cross-check, because the rule change is load-bearing.** The spec's known answer was `inbox-snapshot-misses-slash-command-path` → `fixed-in-repo`. Ancestry says `704a2e5` is **not** in `clavity-v17`; the installed `hooks.json` (759 B vs the repo's 913 B) has no `UserPromptSubmit`. Two independent methods, same answer.

**One item the naive reading would have got wrong.** `agy-look-tail-truncation.md` is annotated "FIXED by this epic", and its symbol `newestFirst` resolves to the 2026-07-09 monorepo-move commit — which is an ancestor of v17 and would score it `released`. But the note also says the call site was *unwired*; the wiring landed in **`141dcc4`**, which is in `clavity-v17..HEAD`. It is **`fixed-in-repo`**. This is exactly the conflation D2 exists to remove.

**Also verified and unchanged:** F17's headroom (seed 5190 + growth 7984 = 13174 of 16384; 3210 B free) and F1's 6.3x cheatsheet headroom (2587 B of 16384) are both correct. `driver_cheatsheet::MAX_BYTES` and `golden_header::MAX_BYTES` are **independent** 16 KiB caps, not one shared pool — `maybe_emit_driver_guidance` (`clavity-classic/src/main.rs:487-526`) joins the two sections with no aggregate cap.

---

## File Structure

**Created**
- `scripts/check-cheatsheet-budget.ps1` — read-only byte-budget checker for `agy-autotrain/knowledge/driver-cheatsheet.core.md`. One responsibility, mirroring `check-seed-budget.ps1`.
- `scripts/tests/check-cheatsheet-budget.Tests.ps1` — synthetic tests of that script, plus one assertion against the real canonical artifact.
- `ghidrust/crates/ghidrust-mcp/tests/skill_emit.rs` — the missing oracle: `ghidrust skill --emit` stdout must equal the committed plugin copy, byte for byte.

**Modified**
- `agy-autotrain/skills/agy-curate/SKILL.md` — F4, F5, R2-F11, F1, F6, F17
- `agy-autotrain/skills/agy-learn/SKILL.md` — F2 + F7
- `scripts/injected-context-exemptions.json` — F16
- `agy-autotrain/hooks/hooks.json` — R6-F14
- `scripts/tests/plugin-hooks-registration.Tests.ps1` — R6-F14 coverage
- `agy-autotrain/docs/fix-the-tool-backlog/_template.md` + 7 items — D2
- `scripts/check-injected-context.ps1` — **comments only** (D1 part 2, Group D part 2)
- `scripts/injected-context-ignore.txt` — D3 parts 1 and 2
- `scripts/tests/check-injected-context.Tests.ps1` — the Group D extractor test
- `commonmemory/ROADMAP.md` — D1 part 1
- `ghidrust/crates/ghidrust-mcp/src/main.rs`, `src/skill_asset.rs`, `ghidrust/CONTRIBUTING.md` — Group B
- `justfile`, `scripts/README.md`, `scripts/tests/_partition.md`, `.github/workflows/build-dotnet.yml`, `.github/workflows/build-classic.yml` — registering the new checker (four gated surfaces plus `_partition.md`, which nothing gates)
- `docs/coverage-debt.md` — the five deferred entries
- `agy-autotrain/CONTRIBUTING.md` — the `msg*` convention

---

## Standing rules for every task

- **Never `git add -A`.** Stage explicit paths only. It has twice swept `.claude/settings.local.json` onto a public repo.
- **Never commit or force-add anything under `.clavity/`.** It is runtime state.
- `docs/superpowers/*` is gitignored (`.gitignore:32`), so this plan and the spec need `git add -f`.
- **Do not push.** The owner owns every push.
- 🔴 **If you are resuming an interrupted run, do NOT restart a task from its first step.** Most steps are read-only or replace text (harmless to repeat — the old string is simply absent). But **fifteen steps INSERT or APPEND**, and repeating one duplicates its content: a second rubric row, a second CI step, a second `_partition.md` row, a second `coverage-debt.md` entry, a second `emit_bytes()` (which fails to compile). Before re-running any insert step, `rg` for a distinctive phrase from what it adds; if it is already there, skip the step. The same applies to the five commits — check `git log --oneline -1` before committing, or you will inflate a five-commit batch.
- 🔴 **ONE RULE FOR `git checkout --`, because this plan uses it three times with three different answers and getting it wrong destroys work.** Before running it on any file, ask: **is that file in ANY task's `git add` list?**
  - **No** → `git checkout --` is safe. HEAD is the clean version and nothing of yours is in it. (This is Task 3 Step 3's hook mutant — the batch never edits that file.)
  - **Yes** → **NEVER `git checkout --`. Revert by hand.** The file carries uncommitted batch work and a checkout discards all of it, not just your mutant. (This is Task 4 Step 7 — `main.rs` and `skill_asset.rs` hold Steps 2-4.)
  - **The file is new and untracked** → **NEVER**. There is no HEAD version; a checkout deletes it outright. (This is Task 1 Step 15's `check-cheatsheet-budget.ps1`.)

  Apply the rule rather than remembering the cases. The hazard is muscle memory: the plan demonstrates one *safe* `git checkout --` about 500 lines before the one that would cost you three steps of work.

- 🔴 **Three steps are temporary mutants that MUST be completed, not resumed mid-way** (Task 1 Step 15, Task 3 Step 3, Task 4 Step 7). Each edits a file, observes a failure, then restores it. If you are interrupted between the edit and the restore, the tree is left broken in a way `git status` shows but the plan's later steps do not check. **On resume, run `git status --short` first**: an unexpected modification to `scripts/check-cheatsheet-budget.ps1`, `agy-autotrain/hooks/agy-learn-reminder.sh` or `ghidrust/crates/ghidrust-mcp/src/main.rs` is an un-restored mutant. Restore it before doing anything else.
- **Run the pre-push gates yourself before handing back, and never bypass a hook.** `lefthook.yml:19-46` puts nine commands on **pre-push**, not pre-commit — labelled `seed-sync`, `agy-skills`, `doc-stubs`, `member-docs`, `user-facing-docs`, `register-hash`, `installer-ascii`, `check-versions` (which runs `scripts/check-versions-all.ps1`, not a same-named recipe) and `check-plugin-namespace` — so none of them fires on this batch's five commits, and all of them fire on the owner's push. This batch edits `scripts/README.md`, which is on the user-facing docs roster (`docs/user-facing-docs.txt:23`), so `check-user-facing-docs` is directly in scope. Run at least:

  ```bash
  just check-user-facing-docs
  just check-doc-stubs
  just check-member-docs
  ```

  A batch that is green on all six criteria can still fail at push time, and the owner is the one who would discover it. Never reach for `--no-verify`.
- **`pre-commit` runs only `ruff` on `clavity-classic/agy-mcp-bridge/**/*.py`** (`lefthook.yml:47-60`). This batch touches no Python, so commits are unaffected by it.
- Criteria 1-5 run after **every** commit. Criterion 6 runs **only after commit 4**.
- If `just test-scripts-fast` goes red mid-batch, **stop and diagnose**. Later verification is meaningless once an earlier commit is red.

**Prerequisites — confirm all of these before Task 0, because every later step assumes them:**

```bash
git --version && pwsh -v && just --version && rg --version | head -1
pwsh -c '(Get-Module -ListAvailable Pester | Select-Object -First 1).Version'   # expect 5.x
(cd ghidrust && cargo --version && cargo nextest --version)                     # Task 4 only
```

The plan also uses `awk`, `wc`, `head`, `cut` and `python3`, all present in Git Bash on this machine. **Nothing in the plan verifies these at runtime** — a missing tool surfaces as a confusing failure several steps later rather than as "not installed", so check them once here.

**Verification commands** (used verbatim throughout):

```bash
# Criterion 1 - MUST be backgrounded (~696 s, over the 600 s tool cap).
just test-scripts-fast
# Read the "Tests Passed:" line. Its ABSENCE is an aborted run, not a pass.

# Criterion 2
bash scripts/check-seed-artifacts-synced.sh    # expect exit 0

# Criterion 3
pwsh -File scripts/check-injected-context.ps1  # expect "check-injected-context: OK", exit 0

# Criterion 6 - ONLY after commit 4
(cd ghidrust && just test)
```

> 🔴 **Every `cd` in this plan is wrapped in a subshell, deliberately.** The executing shell keeps its working directory between commands, so a bare `cd ghidrust` leaks: the next `cd ghidrust` looks for `ghidrust/ghidrust` and fails, and a later repo-root command such as `just test-scripts-fast` runs from the wrong place. The parentheses confine the change to that one command.

---

## Task 0: Commit the pending agy-observations capture

The working tree carries one uncommitted file: an `agy-learn` observation appended this session. It must land **before** commit 1, because F16's `reason` text quotes measured non-ASCII counts and this file's content is what those counts measure.

**Files:**
- Modify: `agy-autotrain/knowledge/agy-observations.md` (already edited; commit as-is)

- [ ] **Step 1: Confirm this is the only working-tree change**

```bash
git status --short
```
Expected, exactly one line:
```
 M agy-autotrain/knowledge/agy-observations.md
```
If anything else appears, **STOP** and report `STATE_MISMATCH: <what>` — then take the recovery path rather than improvising:

- **Another file is modified.** Do not sweep it into Task 0's commit and do not `git add -A`. Show the owner `git status --short` and `git diff <that file>` and ask whether it belongs in this batch, is unrelated work to commit separately, or should be stashed. A stray file swept into a commit here has twice put `.claude/settings.local.json` onto a public repo.
- **`agy-observations.md` is NOT modified** (someone already committed it). Skip Task 0 entirely, re-run Step 3's measurement against the committed file, and carry those figures forward. Nothing downstream depends on Task 0 having produced a commit — only on the counts being measured from the file as it stands when Task 1 Step 9 is written.
- **The tree is clean and the capture is nowhere.** Stop and ask; the capture may have been committed on another branch, and Task 1 Step 9's figures must then be measured from whatever this branch actually has.

- [ ] **Step 2: Confirm the gate is green over it**

```bash
pwsh -File scripts/check-injected-context.ps1
```
Expected: `check-injected-context: OK`, exit 0.

- [ ] **Step 3: Pin the post-commit non-ASCII counts**

```bash
F=agy-autotrain/knowledge/agy-observations.md
D=$(rg -n '^<!-- Drain log' $F | head -1 | cut -d: -f1)   # first drain-log line; everything below is append-only
echo "total:   $(rg -o '[^\x00-\x7F]' $F | wc -l)"
echo "header:  $(awk 'NR==7' $F | rg -o '[^\x00-\x7F]' | wc -l)"
echo "pending: $(awk -v d=$D 'NR>=8&&NR<d' $F | rg -o '[^\x00-\x7F]' | wc -l)"
echo "drainch: $(awk -v d=$D 'NR>=d' $F | rg -o '[^\x00-\x7F]' | wc -l)"
echo "drainln: $(awk -v d=$D 'NR>=d' $F | rg -c '[^\x00-\x7F]')"
```
Expected at the time of writing: `51`, `4`, `11`, `36`, `28`. **These feed Task 1 Step 9's exemption `reason`, so carry forward what you measure, not what is printed here.**

> The boundary is derived from the first `<!-- Drain log` line rather than hardcoded, because every new capture shifts it. The pending and total figures move whenever anyone records an observation — they moved twice during planning alone. The drain-log figures (`36` across `28` lines) are stable **between drains**: a capture appends to `## Pending`, above the boundary, and only a drain appends a new log block below it. That is exactly why the permanence argument rests on the drain-log figures and not on the total — but re-measure them too, since a drain between now and execution would move them.

> **Do not substitute `grep -c '[^\x00-\x7F]'`.** GNU grep does not expand `\x` escapes inside a bracket expression, so it matches almost every line and reports a wildly inflated count. Measured during planning: 50 of 69 lines on a file with **zero** non-ASCII characters.

- [ ] **Step 4: Commit**

```bash
git add agy-autotrain/knowledge/agy-observations.md
git commit -F - <<'MSG'
docs(agy-autotrain): capture that a peer's file discovery honours .gitignore

A peer's file-DISCOVERY tools may honour the repository's ignore-file, so an
artifact under an ignored path reads to the peer as NON-EXISTENT even though a
direct read by exact path succeeds - it may then report the file missing and
refuse the task. Driving implication: give a peer the EXACT path to an ignored
or untracked artifact, say plainly that discovery will not list it, and require
it to quote the read error rather than infer absence from a listing.
MSG
```

---

## Task 1 (Commit 1): Group A — agy-autotrain skill coherence

Closes F4, F5, R2-F11, F2+F7, F16, F1, F6, F17.

**Files:**
- Modify: `agy-autotrain/skills/agy-curate/SKILL.md`
- Modify: `agy-autotrain/skills/agy-learn/SKILL.md`
- Modify: `scripts/injected-context-exemptions.json`
- Create: `scripts/check-cheatsheet-budget.ps1`
- Create: `scripts/tests/check-cheatsheet-budget.Tests.ps1`
- Modify: `justfile`, `scripts/README.md`
- Modify: `.github/workflows/build-dotnet.yml`, `.github/workflows/build-classic.yml`

> **Every edit in this task lands in a file the injected-context gate audits** (`agy-autotrain` is a domain root, `check-injected-context.ps1:49`). All new text must be **pure ASCII**. Write character names or code points (`U+00B7`, "em dash"), never the glyph. This is the exact trap that produced F2 and F7.

- [ ] **Step 1: State-verification**

Open `agy-autotrain/skills/agy-curate/SKILL.md` and confirm it is **276 lines** and that these anchors read exactly as below. If any differs, **STOP** and report `STATE_MISMATCH: <line> <what you found>`.

```bash
awk 'NR==38||NR==80||NR==95||NR==125||NR==191' agy-autotrain/skills/agy-curate/SKILL.md
```
Expected:
- `:38` contains `(section  "Compile the core driver-cheatsheet")` — note the **doubled** space
- `:80` contains `into a lean <= ~150-token / ~3-bullet`
- `:95` starts `Escape the literals mechanically`
- `:125` is `  (one-off impressions stay in the inbox).`
- `:191` contains `is within the 16 KB cap; over that it silently degrades to SEED-only`

- [ ] **Step 2: F4 — remove the doubled space at `:38`**

Replace `(section  "Compile the core driver-cheatsheet")` with `(section "Compile the core driver-cheatsheet")` — one space.

- [ ] **Step 3: F1 — replace the unenforced cheatsheet budget at `:79-81`**

Replace these three lines:

```
The `driver/probabilistic` entries that survived the gate are the durable driver knowledge. Distil the
variant-agnostic core (peer psychology - identical for both drivers) into a lean <= ~150-token / ~3-bullet
cheatsheet. The canonical text lives at `knowledge/driver-cheatsheet.core.md`; keep it in sync there.
```

with:

```
The `driver/probabilistic` entries that survived the gate are the durable driver knowledge. Distil the
variant-agnostic core (peer psychology - identical for both drivers) into a lean cheatsheet - today about
5 bullets and 2.5 KB. The canonical text lives at `knowledge/driver-cheatsheet.core.md`; keep it in sync
there.

**The budget is whatever `scripts/check-cheatsheet-budget.ps1` declares as its `-MaxBytes` default (4096 bytes at the time of writing), and it is ENFORCED** by that script (run in CI and
by `scripts/tests/check-cheatsheet-budget.Tests.ps1` under `just test-scripts-fast`). Above that the
checker fails and you must either consolidate or raise the default deliberately, in a committed edit. The
runtime hard cap is separate and much higher - `clavity-classic/src/driver_cheatsheet.rs:12` sets
`MAX_BYTES = 16 * 1024`, and a runtime file over it degrades to the compiled-in baseline floor with a
warning on stderr (`:28-29`). That budget exists so drift is caught long before it reaches that cliff. **Do not restate the number here when it changes - the script's default is the single source of truth, and a copy in this prose is the unenforced duplicate F1 exists to remove.**
```

> **Why a number at all, and why enforced.** The old `~150-token / ~3-bullet` figure was aspirational and unenforced, and the artifact drifted to roughly 4x it (5 bullets, 433 words, 2561 B) with nothing complaining. Replacing one unenforced number with another is how it drifted in the first place — so the replacement ships with its checker in the same commit.

- [ ] **Step 4: F5 — replace the em-dash guidance at `:95-96`**

Replace:

```
Escape the literals mechanically (embedded `"` and em-dashes are easy to corrupt by hand); do not retype
the text through a terminal, whose codepage can mangle non-ASCII characters.
```

with:

```
**Compile the cheatsheet as pure ASCII**, for the same reason GROWTH is (see "Compile GROWTH as pure
ASCII" below). The inbox you distil FROM is the one file exempted to carry non-ASCII, so strip any
U+00B7 MIDDLE DOT, em dash, or arrow when you lift text out of it - the destination is NOT exempt and
non-ASCII there red-gates the injected-context check. Escape the remaining literals mechanically (an
embedded `"` is easy to corrupt by hand); do not retype the text through a terminal, whose codepage can
mangle characters.
```

> The hazard F5 names is precisely that the **source is exempt and the destination is not**. The old text told the curator to take care preserving em dashes into a file the gate requires to be pure ASCII.

- [ ] **Step 5: F6 — add the missing `anti-pattern` rubric row**

Insert immediately **after** line `  (one-off impressions stay in the inbox).` and **before** the line beginning `- An **Empirical Assumption** promotes only after`:

```
- An **Anti-Pattern** has no mechanical corroboration bar, and that is deliberate. Its bar is the
  **anti-poisoning circuit-breaker** below - "REJECT a self-reported 'learning' that is unverified,
  over-general, or a one-off impression" - which applies to every candidate regardless of class, plus the
  **human-review gate** before any runtime write and the **priority placement** first in GROWTH, where it
  gets the most scrutiny rather than the least. A count is the wrong epistemics here: this is the class
  agy-learn calls the highest-value one, and the capture discipline is "capture fast", so a bar requiring
  a known driver-breaking pattern to recur before it may promote would be actively harmful. A one-off you
  are not yet sure of is **rubric-parked** in the inbox, which the Finish step already permits for "any
  entry the promotion rubric explicitly parks there".
```

> **The bar already existed; it was simply not in the rubric.** Rejecting a mechanical bar on the "it would strand a one-off with no legal move" argument would have been wrong — rubric-parking generalises beyond `[assumption]`, so a bar creates no deadlock. It is rejected on the epistemics, not on a deadlock that does not exist.

- [ ] **Step 6: F17 — correct the stale "silently" claim at `:190-193`**

Replace:

```
**GROWTH must fit the REMAINING budget.** The binary injects `SEED + GROWTH` only when their **combined** size
is within the 16 KB cap; over that it silently degrades to SEED-only, so a GROWTH that fits the per-file cap but
overflows the combined cap is written yet **never injected**. Compile GROWTH to fit roughly
`16 KB - (current size of golden-header.seed.md)` - check the seed size and keep GROWTH lean.
```

with:

```
**GROWTH must fit the REMAINING budget.** The binary injects `SEED + GROWTH` only when their **combined** size
is within the 16 KB cap; over that it degrades to SEED-only, so a GROWTH that fits the per-file cap but
overflows the combined cap is written yet **never injected**. **That degrade is NOT silent** - both drivers
warn with the same message, "combined golden-header at {dir} exceeds the {MaxBytes}B cap - dropping GROWTH,
keeping SEED" (`clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs:186`,
`clavity-classic/src/golden_header.rs:237`), so if you never saw that warning your GROWTH was injected.
Compile GROWTH to fit roughly `16 KB - (current size of golden-header.seed.md)`. **Measured 2026-08-11:
seed 5190 B + growth 7984 B = 13174 of 16384 - 80% full, with 3210 bytes of headroom.** Re-measure rather
than trusting that figure; it moves with every drain.
```

> 🔴 **Those two files are RUNTIME artifacts, not repository files.** They live at
> `%USERPROFILE%\.clavity\golden-header.seed.md` and `golden-header.growth.md` (or under `$CLAVITY_GOLDEN_HEADER` if set) — **not** under `agy-autotrain/knowledge/`, which holds only `agy-observations.md` and `driver-cheatsheet.core.md`. To re-measure:
>
> ```bash
> wc -c < "$USERPROFILE/.clavity/golden-header.seed.md"
> wc -c < "$USERPROFILE/.clavity/golden-header.growth.md"
> ```
>
> A reviewer looking for them in the repo concluded they did not exist and called the headroom figure unverifiable. They exist, at exactly the sizes above — but "re-measure" is useless without saying what to point at, and the SKILL.md sentence being edited here names the file without its path.

- [ ] **Step 7: R2-F11 — add the non-interactive fallback to the human-review gate**

Insert immediately **before** the line beginning `Then, once approved, **commit it through the binary**`, leaving a blank line on each side of the new paragraph.

> That anchor is a single line and occurs **exactly once** in the file — measured. Do **not** search for the preceding paragraph's closing words (`…the human gate is the safeguard the model depends on, not a formality.`): that sentence **wraps across two lines** in the source, so it exists as prose but matches nothing as a literal string, and a search for it returns zero hits.

```
**No interactive approval channel?** If this skill runs where no interactive approval can be obtained (a
headless or otherwise non-interactive session), do **NOT** publish. Emit a **non-blocking** message - "no
interactive approval channel; the compiled GROWTH was NOT published. Re-run agy-curate interactively to
publish." - and exit without error. Publishing unreviewed GROWTH is the one outcome this gate exists to
prevent, so this path fails **CLOSED**. **The inbox is deliberately left unreset and nothing is lost:** the
Finish ordering below resets `## Pending` only when `curate-commit` exits 0, so an unpublished run leaves
every entry in place and a later interactive run simply recompiles them. Only compute is wasted, and only
once. Do NOT add an inbox reset to this path - that would turn a safe abort into data loss.
```

> This mirrors the shape already used by "**No driver installed?**": do not hard-fail, emit a non-blocking warning, preserve the work.

- [ ] **Step 8: F2 + F7 — name the real inbox delimiter in `agy-learn/SKILL.md`**

The file is 69 lines. Both `:50` and `:66` render the delimiter as an ASCII `*` and **must keep doing so** — this file is in the corpus and is not exemption-covered, so an actual U+00B7 here red-gates it.

Insert immediately after line 51 (the closing ` ``` ` of the Step 3 block):

```

**The separator shown above is an ASCII asterisk so this document itself stays pure ASCII. The LIVE inbox
delimits with U+00B7 MIDDLE DOT, not an asterisk** - match the existing bullets in the file you are
appending to, not this rendering.
```

Append at end of file, after line 69 (the closing ` ``` ` of the header block):

```

**Same caveat as above:** the provenance-tag separators rendered here as `*` are **U+00B7 MIDDLE DOT** in
the live inbox. `agy-observations.md` carries a standing `encoding` exemption for exactly that reason; this
file does not, which is why the code point is named rather than pasted.
```

- [ ] **Step 9: F16 — rewrite the exemption `reason`**

In `scripts/injected-context-exemptions.json`, replace the `reason` value of the `agy-autotrain/knowledge/agy-observations.md` entry. Keep the file **pure ASCII** to match its existing style, and keep the two verified citations that justify the waiver.

New value (a single JSON string):

```
Owner ruling 2026-08-08; reason corrected 2026-08-11. The agy-learn inbox IS in the domain - agy-curate/SKILL.md:13 lists it as an INPUT the skill drains, \"the capture inbox (what you drain)\" - so an agent reads it into context - and its U+00B7 field delimiter is a deliberate, test-pinned format decision (scripts/tests/agy-curate-nudge.Tests.ps1:207-209, 'the LIVE inbox delimits with U+00B7, not ASCII'). Every other invariant applies. THIS EXEMPTION IS PERMANENT, and the earlier note predicting it would become unused was wrong. The non-ASCII is NOT confined to the header and a drain does NOT remove it: the drain-log entries are HTML comments appended below the inbox and never pruned, so their non-ASCII accumulates monotonically. Snapshot 2026-08-11 (illustrative, not a retirement condition - the pending count moves with every capture): 51 non-ASCII characters, of which 4 are on the header line, 11 in pending bullets, and 36 across 28 lines of append-only drain-log comments. Retire this entry only if drain logs stop being append-only.
```

> **Why the count is demoted to a snapshot.** The defect F16 fixes is a `reason` whose retirement condition was pinned to a brittle measurement ("3x U+00B7 and 1x U+2265 on line 7"). Writing a fresh exact total in its place would re-commit the same defect one level down — the pending-bullet count changes every time anyone captures an observation. The permanence rests on the **structural** fact: drain logs are append-only.

**Then verify the file is still pure ASCII — nothing else will:**

```bash
rg -c '[^\x00-\x7F]' scripts/injected-context-exemptions.json   # expect: no matches (exit 1)
python3 -c "import json;json.load(open('scripts/injected-context-exemptions.json'));print('valid JSON')"
```

> 🔴 **This file is outside every gate.** `$script:DomainRoots` lists `agy-autotrain`, `commonmemory`, `seed`, the two plugin trees and the two ghidrust roots — **`scripts/` is not among them**, so the injected-context gate never audits its own waiver file, and `check-installer-ascii.ps1` covers only `installer/**/*.ps1` plus one test file. Measured: this file carries **0** non-ASCII characters today. You are about to hand-write a long prose string into it, and a curly quote or em dash pasted from anywhere would be permanent and unnoticed — in the file whose entire subject is ASCII discipline.

- [ ] **Step 10: F1 enforcement — create the budget checker**

Create `scripts/check-cheatsheet-budget.ps1`, mirroring its sibling `scripts/check-seed-budget.ps1`:

```powershell
#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Assert the canonical driver cheatsheet is within its committed byte budget. Dev/CI-time only.
  Test-Path-guarded: a missing file counts as 0 bytes.
.DESCRIPTION
  agy-curate/SKILL.md instructs the curator to distil the durable driver knowledge into a lean cheatsheet.
  That instruction previously named a size (~150 tokens / ~3 bullets) that NOTHING enforced, and the
  artifact drifted to roughly 4x it unnoticed. This is the enforcement half: an unenforced budget is how
  the drift happened, so the number and its checker ship together.

  This is NOT the runtime cap. clavity-classic/src/driver_cheatsheet.rs:12 sets MAX_BYTES = 16 * 1024 on
  the RUNTIME driver-cheatsheet.md, and a file over it degrades to the compiled-in baseline floor. This
  budget is deliberately far below that, so drift is caught long before the cliff.
.PARAMETER Path
  Path to the canonical cheatsheet. Defaults to agy-autotrain/knowledge/driver-cheatsheet.core.md.
.PARAMETER MaxBytes
  The budget. Default 4096. THE single source of truth; a deliberate raise is a committed edit here.
#>
[CmdletBinding()]
param(
    [string]$Path,
    [int]$MaxBytes = 4096
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Path) { $Path = Join-Path $RepoRoot 'agy-autotrain/knowledge/driver-cheatsheet.core.md' }

function Fail([string]$msg) {
    Write-Host "check-cheatsheet-budget: FAIL: $msg" -ForegroundColor Red
    exit 1
}

# A missing cheatsheet (fresh clone, never drained) is 0 bytes <= budget - never a crash. This mirrors
# check-seed-budget.ps1 deliberately.
#
# Yes, that means a DELETED canonical also reports OK here. That is not a hole, because deletion is
# already caught harder elsewhere and this script is a BUDGET gate, not an existence gate: the file is
# byte-pinned into both drivers (agy-curate/SKILL.md documents the three-file pin), so removing it reds
# `baseline_floor_matches_canonical_core_source` and `BaselineFloor_matches_the_canonical_core_source`;
# it is in the drain's protected-path list; and this script's own Pester suite asserts Test-Path on the
# real canonical before invoking it. Making a budget checker fail on absence would break the fresh-clone
# case its sibling exists to protect.
$bytes = 0
if (Test-Path $Path) {
    $bytes = [System.Text.Encoding]::UTF8.GetByteCount([System.IO.File]::ReadAllText($Path))
}

if ($bytes -gt $MaxBytes) {
    Fail "driver cheatsheet is ${bytes}B > ${MaxBytes}B - consolidate it, or raise the -MaxBytes default in scripts/check-cheatsheet-budget.ps1 deliberately"
}

Write-Host "check-cheatsheet-budget: OK - cheatsheet ${bytes}B <= ${MaxBytes}B" -ForegroundColor Green
exit 0
```

> `-WhatIf` is not required: the project rule exempts read-only checkers, and the direct sibling `check-seed-budget.ps1` uses a plain `[CmdletBinding()]` for the same reason.

- [ ] **Step 11: Create its Pester suite**

Create `scripts/tests/check-cheatsheet-budget.Tests.ps1`:

```powershell
# scripts/tests/check-cheatsheet-budget.Tests.ps1
BeforeAll {
    $script:Script   = Join-Path $PSScriptRoot '..' 'check-cheatsheet-budget.ps1'
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:Canonical = Join-Path $script:RepoRoot 'agy-autotrain/knowledge/driver-cheatsheet.core.md'
}

Describe "check-cheatsheet-budget.ps1" {
    BeforeEach {
        $script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cheatbudget-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Tmp | Out-Null
        $script:File = Join-Path $script:Tmp 'driver-cheatsheet.core.md'
    }
    AfterEach { Remove-Item -Recurse -Force $script:Tmp -ErrorAction SilentlyContinue }

    It "passes when the cheatsheet is under budget" {
        Set-Content -NoNewline -Path $script:File -Value ('x' * 100)
        & pwsh -File $script:Script -Path $script:File -MaxBytes 200
        $LASTEXITCODE | Should -Be 0
    }

    It "fails when the cheatsheet exceeds budget" {
        Set-Content -NoNewline -Path $script:File -Value ('x' * 300)
        & pwsh -File $script:Script -Path $script:File -MaxBytes 200
        $LASTEXITCODE | Should -Be 1
    }

    It "passes (0 bytes) when the file is absent (fresh clone)" {
        & pwsh -File $script:Script -Path (Join-Path $script:Tmp 'missing.md') -MaxBytes 200
        $LASTEXITCODE | Should -Be 0
    }

    It "measures UTF-8 BYTES not characters (multibyte)" {
        # 100 x EUR SIGN = 300 UTF-8 bytes but 100 chars; must FAIL a 200-byte budget.
        Set-Content -NoNewline -Path $script:File -Value ([string]([char]0x20AC) * 100) -Encoding utf8
        & pwsh -File $script:Script -Path $script:File -MaxBytes 200
        $LASTEXITCODE | Should -Be 1
    }

    It "pins the committed default budget at 4096 bytes" {
        # WITHOUT THIS ROW the enforcing row below is defeated by a one-line edit. It invokes the script
        # with NO arguments, so it measures against whatever the default happens to be at call time -
        # meaning a future commit that raises the default AND grows the cheatsheet passes both. Pinning
        # the number here makes raising the budget a deliberate, visible test edit rather than a silent
        # side effect of the change that needed the extra room.
        $src = Get-Content -Raw -LiteralPath $script:Script
        $src | Should -Match '\[int\]\$MaxBytes\s*=\s*4096' -Because 'raising the budget must be a conscious edit to this test, not an invisible default shift'
    }

    It "the REAL canonical cheatsheet is within the committed default budget" {
        # THE POINT OF F1. The four synthetic rows above test the script's logic on input they supply
        # themselves, and would all pass with the real artifact 10x over budget. This row is the one that
        # actually enforces. It and the default-pin row above are the only two that consult the script's
        # own default, which is why a mutant on that default reddens exactly this pair (Step 15).
        Test-Path $script:Canonical | Should -BeTrue -Because 'the assertion below is vacuous without it'
        & pwsh -File $script:Script
        $LASTEXITCODE | Should -Be 0 -Because 'agy-curate/SKILL.md states this budget; an unenforced number is how it drifted to 4x before'
    }
}
```

- [ ] **Step 12: Register the suite (required — registration is an explicit list, not a glob)**

In `justfile`, in the **`test-scripts-fast`** recipe (line 101), add `'scripts/tests/check-cheatsheet-budget.Tests.ps1', ` immediately after `'scripts/tests/check-seed-budget.Tests.ps1', ` so the budget suites stay adjacent.

> `scripts/tests/test-suite-registration.Tests.ps1` fails if a suite on disk is in neither half. It cannot be skipped.

- [ ] **Step 13: Add the README inventory row**

In `scripts/README.md`, immediately after the `check-seed-budget.ps1` row, add:

```
| `check-cheatsheet-budget.ps1` | Assert the canonical driver cheatsheet (`driver-cheatsheet.core.md`) is within its committed byte budget (default 4096 B) | CI (`build-dotnet.yml`, `build-classic.yml`); run directly, no `just` recipe |
```

> `scripts/tests/scripts-readme-inventory.Tests.ps1` fails if a top-level script is missing from the index, and asserts the name **case-exactly**.

- [ ] **Step 14: Wire it into CI beside its sibling — NO `working-directory:` key, KEEP the `../` prefix**

In **both** `.github/workflows/build-dotnet.yml` (immediately after the `SEED byte-budget gate` step at line 78-79) and `.github/workflows/build-classic.yml` (after its identical step at line 56-57), insert exactly:

```yaml
      - name: Driver-cheatsheet byte-budget gate
        run: pwsh -File ../scripts/check-cheatsheet-budget.ps1
```

Six spaces of indent before `- name:`, eight before `run:`, matching the sibling step exactly.

**Place it after the blank line that follows the SEED step, immediately before the next `- name:`** — so in `build-dotnet.yml` it sits between the blank line 80 and `- name: Build installer (ISCC)` at line 81, and in `build-classic.yml` between the blank line 58 and `- name: Build + stage (the 7.8 recipe)` at line 59. Leave one blank line after your new step too, so the file keeps one blank line between every pair of steps.

> 🔴 **Do NOT add a `working-directory:` key to this step, and do NOT drop the `../` prefix.** Both workflows set `working-directory` as a **job-level default** — `defaults: run: working-directory: clavity-dotnet` at `build-dotnet.yml:24-26`, and `clavity-classic` at `build-classic.yml:20-22` — so every step already runs inside the member directory, which is why the sibling reaches the script as `../scripts/...`. Adding a step-level `working-directory: .` would "fix" a problem that does not exist and break the relative path.
>
> The checker itself is location-independent regardless (`$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path`), so it audits the same canonical file from either workflow. Running it in both mirrors `check-seed-budget.ps1`, which is also duplicated across the two.

- [ ] **Step 15: Run the new suite and confirm the real-artifact row is not vacuous**

```bash
pwsh -c "Invoke-Pester scripts/tests/check-cheatsheet-budget.Tests.ps1 -Output Detailed -CI"
```
Expected: 6 passed, 0 failed.

Then prove the **enforcing row** genuinely bites. The row that matters is `the REAL canonical cheatsheet is within the committed default budget`, and it invokes the script with **no arguments** — so the mutant must move the **default**, not a passed parameter.

Temporarily edit `scripts/check-cheatsheet-budget.ps1` and change `[int]$MaxBytes = 4096` to `[int]$MaxBytes = 100`. Then:

```bash
pwsh -c "Invoke-Pester scripts/tests/check-cheatsheet-budget.Tests.ps1 -Output Detailed -CI"
```
Expected: **exactly two** rows red, and they must be these two —

1. `the REAL canonical cheatsheet is within the committed default budget`, reporting `driver cheatsheet is 2561B > 100B`. This is the enforcing row, and reddening it is the point of the mutant.
2. `pins the committed default budget at 4096 bytes`, because that row reads the script's own text and the mutant has just changed `4096` to `100`.

**The four synthetic rows must stay green** — they each pass `-MaxBytes` explicitly, so moving the default cannot touch them. That asymmetry is the proof: the two rows that consult the default both notice, and the four that do not are unaffected.

🔴 **If the red pattern is anything other than exactly those two rows, STOP.** All six red means you introduced a syntax error rather than a logic mutant (a mistyped parameter name binds nothing and every invocation fails). Zero red means the mutant never took effect. **One red is also wrong** — if only the enforcing row reddens, the default-pin row is not actually reading the script text and is a decoration; if only the pin row reddens, the enforcing row is not using the default. None of those exercises what this step exists to prove, so fix the edit, or re-create the file from Step 10, before going on.

Restore `4096` by editing the line back. Do **not** use `git checkout --` — the file is new and uncommitted, so a checkout would delete it.

**Then verify the restore before moving on:**

```bash
rg -c '\$MaxBytes = 4096\b' scripts/check-cheatsheet-budget.ps1  # expect exactly 1 - the \b matters
pwsh -c "Invoke-Pester scripts/tests/check-cheatsheet-budget.Tests.ps1 -CI" # expect 6 passed
```

> A mis-restored default is the worst outcome of this mutant: `100` left in place commits a checker that fails on the real artifact, and it fails in **CI on the owner's push**, not here. The mutant is not finished until both lines above are clean.

> **Why not just `pwsh -File scripts/check-cheatsheet-budget.ps1 -MaxBytes 100`?** That proves the *script's* comparison works, which the synthetic rows already prove. It leaves the real-artifact row completely unexercised — a control that passes for the wrong reason, which this project treats as no control at all.

- [ ] **Step 16: Verify the gate and the fast suite**

```bash
pwsh -File scripts/check-injected-context.ps1     # expect OK, exit 0
bash scripts/check-seed-artifacts-synced.sh       # expect exit 0
```
Then run `just test-scripts-fast` **backgrounded** and read its `Tests Passed:` line.

- [ ] **Step 17: Record the suite in `scripts/tests/_partition.md` — the registration NOTHING gates**

`_partition.md` is the alphabetical inventory of every Pester suite with its measured runtime, test count, and FAST/SLOW placement. Measure this suite now that it exists and passes:

```bash
pwsh -c "Measure-Command { Invoke-Pester scripts/tests/check-cheatsheet-budget.Tests.ps1 -CI } | Select-Object -ExpandProperty TotalSeconds"
```

Then add a row in alphabetical position — immediately **before** the `check-core-integrity.Tests.ps1` row — using the figure you just measured. 🔴 **Write it with a COMMA as the decimal separator** (`8,4s`, `15,3s`), matching every existing row: `Measure-Command` returns a dot-decimal on an en-US system, and a `8.4s` row would be the only one in the file in that style.

```
check-cheatsheet-budget.Tests.ps1                 <N,N>s    6 tests   <- FAST, measured 2026-08-11
```

**Then update the fast-half summary at the top of the same file — this is the half that gets forgotten.** `_partition.md:21` still reads the following, and it is ALREADY out of date before you touch it:

```
- `just test-scripts-fast` — the agent inner-loop gate. **25 suites, 328 tests, measured 429,46s solo**
```

🔴 **Do NOT derive the new value by adding one to the 25 on that line. That line is ALREADY STALE.** Measured 2026-08-11: the `test-scripts-fast` recipe lists **27** suites, not 25 — the summary has drifted by two, which is precisely the decay this file documents happening to itself. Writing "26" would record a number that was never true.

**Count the recipe, then write what you counted:**

```bash
awk 'NR==101' justfile | rg -o "scripts/tests/[A-Za-z0-9._-]+\.Tests\.ps1" | wc -l
```

Expected **27** before your change, **28** after. **Dry-run cross-check (2026-08-11, clean worktree): 28 suites, `Tests Passed: 550`, whole fast half 638,08s.** Compare against those; never copy them - measure your own and write what you measured. Take the test total from the `Tests Passed:` line of the `just test-scripts-fast` run in Step 16 rather than from arithmetic on the stale 328. Update the suite count, the test count, and the runtime figure together, and date the line.

🔴 **If Step 16's run produced no `Tests Passed:` line, you have no figure and must not invent one.** Its absence means the run was aborted or killed, not that it passed — so re-run Step 16 to completion before writing anything here. **Do not** substitute the stale 328, do not add 6 to it, and do not carry a number over from an earlier session. An estimated figure in this file is worse than no figure: the whole point of `_partition.md` is to be the measured oracle for the cap decision, and a plausible-looking wrong number is exactly the decay it documents happening to itself.

- [ ] **Step 17b: Add the dated narrative entry — the convention this file actually runs on**

`_partition.md` records **every** suite addition as a dated entry giving the before/after counts and a measured runtime. Follow the established shape (see the entries for the AGY-ANOMALIES change, the discipline-reaching addition, and the pre-release defect sweep, each of which reads "Fast went N suites / M tests to **N' suites / M' tests**, measured **...**"). Append one in the same style:

```
**2026-08-11 - the Stage 2 fix batch.** ONE new fast suite: `check-cheatsheet-budget` (6 tests), the
enforcement half of the driver-cheatsheet budget. Fast went <N> suites / <M> tests to **<N+1> suites /
<M+6> tests**, measured **<T>s**.
```

Fill every placeholder from the numbers you just measured. Do not carry a figure over from another entry. **Where each comes from, because they are not all the same measurement:**

| Placeholder | Source |
|---|---|
| `<N>` / `<N+1>` | the suite count you counted from the `test-scripts-fast` recipe — **before** and **after** adding this suite |
| `<M+6>` | the **fast-half total AFTER** this suite, read from the `Tests Passed:` line of the `just test-scripts-fast` run in Step 16 — **not** the 6 tests of this suite alone |
| `<M>` | the fast-half total **BEFORE**, which is that same figure **minus 6**. 🔴 **It cannot be read from Step 17's run**: by then the suite is registered and its 6 tests are already in the total. Subtract; the suite contributes exactly 6, and Step 15 confirms that count |
| `<T>` | the **whole fast half's** elapsed time from that same run — not the single-suite time you measured for the inventory row above |

The inventory row records **this suite** (its own runtime, its own 6 tests); the narrative entry records **the fast half** before and after. Mixing them is the easy mistake: writing this suite's ~10s as `<T>` would claim the entire fast half runs in ten seconds.

> 🔴 **This obligation is invisible to a heading scan.** The entries are bold-dated paragraphs in the body, not `##` sections, so `rg '^#{1,3} '` returns only two headings for the whole file and makes it look like there is no per-suite log. There is one, it is the file's primary convention, and a suite added without an entry leaves no record of what it cost.

> 🔴 **Adding the alphabetical row and stopping is an incomplete fold — the dominant defect class on this project.** The inventory row and the summary line state the same fact at two granularities, and only one of them is where a reader looks first. `_partition.md` documents this happening to itself: one suite's figure *"had decayed silently through at least two prior edits"* before anyone noticed.
>
> The summary line is also the load-bearing one for the cap: it is what says **"the fast half is now cap-adjacent, not cap-safe"** at `429,46s` against a `600s` foreground cap. A 26th suite consumes part of what is left, and a stale `25 suites / 328 tests` hides that.

> 🔴 **This is the one registration surface with NO automated gate, which is exactly why it is easy to miss.** `test-suite-registration.Tests.ps1` asserts justfile membership only, and says so itself: *"It asserts MEMBERSHIP, not correct placement: the fast/slow split is a measured judgement recorded in `_partition.md`, not something a grep can settle."* So a suite can be correctly registered in the justfile, pass every gate, and still leave the partition inventory silently incomplete — the same drift that `scripts-readme-inventory.Tests.ps1` was created to stop for `scripts/README.md` after it happened there.
>
> It matters here specifically because **the fast half is cap-adjacent**: `_partition.md` is where the evidence lives for deciding what to trim when it stops fitting, and a suite missing from it is invisible to that decision. **Record the measured number, never an estimate** — that file has twice carried figures that decayed silently through later edits, and it says so itself.

**If the fast half has crossed the 600 s cap, stop and surface it — do not quietly absorb it.** The batch adds two pieces of work to that gate: this suite (six rows, five of which spawn a `pwsh` process) and one new `Context` in `check-injected-context.Tests.ps1` that walks every domain root for `*.sh` (31 files today) and dot-sources the gate a seventh time. Both are small against a documented `429,46s` measured against `600s`, so the expected outcome is comfortably under. But the figure is stale by two suites, so **the run in Step 16 is the first honest measurement in a while.** If it comes back at or over the cap:

- record the real number in `_partition.md` anyway — an uncomfortable measurement is the point of that file;
- **do not** move either addition to the slow half to make the number fit. The whole value of the cheatsheet budget and the extractor guard is that they run in the inner loop;
- surface it to the owner as a partition decision. `_partition.md` names `check-seed-artifacts-synced` as the largest fast suite and the first candidate if that half ever needs trimming — that is the owner's call, not this batch's.

- [ ] **Step 18: Commit**

```bash
git add agy-autotrain/skills/agy-curate/SKILL.md \
        agy-autotrain/skills/agy-learn/SKILL.md \
        scripts/injected-context-exemptions.json \
        scripts/check-cheatsheet-budget.ps1 \
        scripts/tests/check-cheatsheet-budget.Tests.ps1 \
        scripts/tests/_partition.md \
        scripts/README.md justfile \
        .github/workflows/build-dotnet.yml .github/workflows/build-classic.yml
git commit -F - <<'MSG'
fix(agy-autotrain): close Group A skill-coherence findings and enforce the cheatsheet budget

F4 doubled space; F5 cheatsheet-ASCII rule; F6 anti-pattern rubric row; F17 the over-cap
degrade is not silent; R2-F11 non-interactive approval fallback fails closed; F2+F7 name
U+00B7 as the real inbox delimiter without pasting it; F16 exemption reason restated as
permanent while drain logs are append-only.

F1: the ~150-token/~3-bullet budget was unenforced and the artifact had drifted well
past it - 2561 B and 5 bullets against a ~3-bullet, ~150-token ceiling.
Replaced with a 4096 B budget AND scripts/check-cheatsheet-budget.ps1 to enforce it.
The spec named scripts/tests/drain-knowledge.Tests.ps1 as the host; measured, that suite is
registered in test-scripts-slow and writes synthetic content into a temp repo rather than
reading the canonical file, so enforcement follows the check-seed-budget.ps1 pattern instead.
MSG
```

> Quoted heredoc for the same reason as commits 3 and 4 (see Task 3 Step 13). This message happens to contain no backticks or `$` today, so `-m "..."` would work — but the whole batch uses one form so that adding a single backticked path later cannot silently truncate the message.

---

## Task 2 (Commit 2): Group C + D2 — hook matchers and the backlog enum

Closes R6-F14 and D2 (R2-F10).

**Files:**
- Modify: `agy-autotrain/hooks/hooks.json:8,10`
- Modify: `scripts/tests/plugin-hooks-registration.Tests.ps1`
- Modify: `agy-autotrain/docs/fix-the-tool-backlog/_template.md` + 7 item files

- [ ] **Step 1: State-verification**

```bash
awk 'NR==8||NR==10' agy-autotrain/hooks/hooks.json
```
Expected:
```
      { "matcher": "startup|clear|compact",
      { "matcher": "startup|resume",
```
If either differs, **STOP** and report `STATE_MISMATCH`.

- [ ] **Step 2: Write the failing test FIRST — before touching the manifest**

In `scripts/tests/plugin-hooks-registration.Tests.ps1`, add `autotrain` to the manifest map. The existing entry (lines 13-16) becomes:

```powershell
        $script:Manifests = @{
            dotnet    = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/hooks.json'
            classic   = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks/hooks.json'
            autotrain = Join-Path $script:RepoRoot 'agy-autotrain/hooks/hooks.json'
        }
```

> Adding a key is safe: every existing row selects by name via `-ForEach @(@{Driver='dotnet'}, @{Driver='classic'})`, so none of them picks up the new manifest.

**Then extend the two COMPLETENESS rows to the new manifest as well** — add `@{ Driver = 'autotrain' }` to the `-ForEach` list of both:

- `It 'names only hook files that EXIST in that plugin - <Driver>'`
- `It 'ships no hook file that is reachable from nowhere - <Driver>'`

Both derive their directory as `$dir = Split-Path -Parent $m`, so they pick up `agy-autotrain/hooks/` automatically once the driver is listed. Verified they pass today: that directory holds exactly three `.sh` files — `agy-inbox-snapshot.sh`, `agy-learn-reminder.sh`, `agy-curate-nudge.sh` — and `hooks.json` registers all three.

> 🔴 **Without this, the coverage added above is two hardcoded rows, not coverage.** The new matcher rows name two scripts explicitly, so a FOURTH hook added to `agy-autotrain/hooks/` later would be registered nowhere, fire never, and pass every test — the exact defect R6-F14 exists to close, merely displaced to the next hook. The completeness rows are what make it structural, and extending them is what the spec meant by "extend the registration suite to cover" that manifest.

Then append this block immediately before the file's final closing `}` - the one closing the `Describe`, currently the last line of the file. **The block deliberately does NOT carry that brace itself**; it ends with the `}` that closes its own `It`, so the file keeps exactly one final `Describe`-closing brace. (An earlier draft included the extra brace, which produced `Unexpected token '}'` when the instruction was followed literally - verified by parsing the result.)

```powershell
    It 'registers <Script> on SessionStart startup|resume|clear|compact - agy-autotrain' -ForEach @(
        @{ Script = 'agy-learn-reminder.sh' }
        @{ Script = 'agy-curate-nudge.sh' }
    ) {
        # agy-autotrain/hooks/hooks.json was covered by NOTHING until now: the suite was parameterised
        # over dotnet/classic only, and its two SessionStart matchers had drifted to complementary,
        # non-overlapping SUBSETS of the convention - 'startup|clear|compact' and 'startup|resume'. The
        # visible consequence was that the agy-LEARN reminder never fired on a RESUMED session.
        $matchers = @(Get-OwningMatchers -Manifest $script:Manifests['autotrain'] -Event 'SessionStart' -Script $Script)
        $matchers.Count | Should -Be 1 -Because 'exactly one SessionStart object may own this hook'
        # -BeExactly, matching the sibling assertions: a future PARTIAL subset must fail, not pass quietly.
        $matchers[0] | Should -BeExactly 'startup|resume|clear|compact' -Because 'this repo pins all four sources; a subset silently drops a channel'
    }
```

- [ ] **Step 3: Run it against the still-unfixed manifest and watch it FAIL**

```bash
pwsh -c "Invoke-Pester scripts/tests/plugin-hooks-registration.Tests.ps1 -Output Detailed -CI"
```
Expected: **2 failed** — `agy-learn-reminder.sh` reporting `startup|clear|compact` and `agy-curate-nudge.sh` reporting `startup|resume`, each against the expected `startup|resume|clear|compact`.

> **This is the control, and it costs nothing because the test is written before the fix.** No `git stash` is needed or wanted: the defect is still on disk, so the test simply fails. If it does **not** fail here, the test is not measuring what you think and the fix that follows would prove nothing — **STOP**.

- [ ] **Step 4: Now align both matchers to the repo convention**

In `agy-autotrain/hooks/hooks.json`, change the matcher **value only** on lines 8 and 10, leaving the rest of each object untouched. The two lines must read exactly:

```json
      { "matcher": "startup|resume|clear|compact",
```

🔴 **The alternation ORDER is load-bearing, even though the regex semantics are not.** The test asserts `Should -BeExactly 'startup|resume|clear|compact'` — a string comparison, not a regex one. `startup|clear|compact|resume` matches the same four sources and would be a perfectly reasonable thing to type, but it **reds the test for a formatting reason**, sending you to debug a matcher that is semantically correct. Type the order above.

> Edit the string value in place rather than reformatting the object. Both lines already end with a trailing comma and are followed by their `"hooks": [...]` line; changing anything else risks a JSON error whose diagnostic path is much longer than the fix.

> **The consequence, recorded rather than discovered later.** Line 8 (`agy-learn-reminder.sh`) gains **resume** — that is the defect being fixed: on a resumed session the agy-LEARN reminder never fired, against that skill's own premise that capture is cheap and live. Line 10 (`agy-curate-nudge.sh`) gains **clear** and **compact**. Its output is threshold-gated (`agy-curate-nudge.sh:45` exits 0 when `count < THRESHOLD` and the inbox is not age-stale), so it stays silent on a small inbox; but on an over-threshold inbox a compaction-heavy session will now nudge on every compact as well as every startup. **That is intended** — a full inbox is a live problem and a compaction is exactly when the earlier nudge scrolled out of context.

- [ ] **Step 5: Re-run and watch the same two rows go green**

```bash
pwsh -c "Invoke-Pester scripts/tests/plugin-hooks-registration.Tests.ps1 -Output Detailed -CI"
```
Expected: 0 failed.

- [ ] **Step 6: D2 — replace the status enum in `_template.md`**

Line 6-7 of `agy-autotrain/docs/fix-the-tool-backlog/_template.md` currently read:

```
status: open        # open | fixed | wont-fix
# On `fixed`, ALSO add:  fixed-by: <sha, sha>   fixed-on: <YYYY-MM-DD>
```

Replace with:

```
status: open        # open | fixed-in-repo | released | wont-fix
# On `fixed-in-repo` or `released`, ALSO add:  fixed-by: <sha, sha>   fixed-on: <YYYY-MM-DD>
# On `released`, ALSO add:  released-in: <release tag or sha range>
#
# `fixed-in-repo` vs `released` is the distinction this enum exists to force, and it is MEASURABLE, not a
# judgement call: an item is `released` when its fix commits are ANCESTORS OF THE LATEST RELEASE TAG, and
# `fixed-in-repo` when they are not. Check it, do not infer it from a commit date - a commit can predate
# the last release and still not be in it:
#     git merge-base --is-ancestor <fix-sha> "$(git tag --sort=-creatordate | head -1)"
# The old single `fixed` value conflated the two, and the conflation was REACHABLE: on 2026-08-11 the
# installed plugin tree was missing the UserPromptSubmit hook whose backlog item read `status: fixed`.
```

> **Why the rule changed from the spec's.** The spec keyed `released` on presence in the installed plugin tree. Measured, 5 of the 7 items are binary-level .NET fixes with no plugin file to inspect, so that rule is not applicable to most of the population. Tag ancestry is uniform, exact, and reproduces the spec's one known answer.

- [ ] **Step 7: Backfill the 7 items — this table is measured, not inferred**

Latest release tag: **`clavity-v17`** at `4a74496` (2026-08-04). Apply exactly:

| File | `status:` becomes | Also add | Evidence |
|---|---|---|---|
| `curate-nudge-age-reads-drain-log-dates.md` | `released` | `released-in: clavity-v17` | `7c2de2b, a357d7a, 8099813, 5dc8822` all ancestors of `clavity-v17` |
| `idle-wait-false-modal.md` | `released` | `released-in: clavity-v17` | `eea56b1, 07b34b0` both ancestors |
| `stalled-reply-recoverable-not-lost.md` | `released` | `released-in: clavity-v17` | shipped mechanism `WaitForIdleWithProgressAsync` landed in `07b34b0`, an ancestor |
| `conversation-scoped-tools-vs-no-open-conversation.md` | `released` | `released-in: clavity-v17` | shipped path `AgyConversationPendingException` present at/before the 2026-07-09 monorepo move, an ancestor |
| `agy-look-tail-truncation.md` | `fixed-in-repo` | — | call site wired in `141dcc4`, which is in `clavity-v17..HEAD` |
| `grpc-default-max-message-size.md` | `fixed-in-repo` | — | `80a254c` and `98a6ecc` both NOT in `clavity-v17` |
| `inbox-snapshot-misses-slash-command-path.md` | `fixed-in-repo` | — | `704a2e5` not in `clavity-v17`; installed `hooks.json` (759 B) has no `UserPromptSubmit` |

`working-vs-stuck-step-delta.md` keeps `status: wont-fix` — that value survives the new enum unchanged, so it needs **no edit**. `README.md` and `DRY-RUN-2026-07-11.md` carry no status field and need none. That is all 11 files accounted for and **exactly 7 edits**.

> **The trap in this table.** `agy-look-tail-truncation.md` is annotated "FIXED by this epic", and its symbol `newestFirst` traces back to an ancestor commit — but that is the monorepo *move*, and the note itself says the call site was left **unwired**. The wiring is `141dcc4`, after v17. Scoring it `released` from the symbol's age is exactly the conflation D2 exists to remove.

- [ ] **Step 8: Confirm no `status: fixed` survives**

```bash
rg -n '^status:' agy-autotrain/docs/fix-the-tool-backlog/*.md
```
Expected: 4x `released`, 3x `fixed-in-repo`, 1x `wont-fix`, 1x `open` (the template). **No bare `fixed`.**

- [ ] **Step 9: Verify**

```bash
pwsh -File scripts/check-injected-context.ps1     # expect OK, exit 0
bash scripts/check-seed-artifacts-synced.sh       # expect exit 0
```
Then `just test-scripts-fast` backgrounded; read `Tests Passed:`.

- [ ] **Step 10: Commit**

```bash
git add agy-autotrain/hooks/hooks.json \
        scripts/tests/plugin-hooks-registration.Tests.ps1 \
        agy-autotrain/docs/fix-the-tool-backlog/
git commit -F - <<'MSG'
fix(agy-autotrain): align hook matchers, cover them, and split fixed from released

R6-F14: agy-autotrain/hooks/hooks.json used two complementary SUBSETS of this repo's
startup|resume|clear|compact convention, so the agy-LEARN reminder never fired on a
resumed session. Both matchers aligned; the registration suite now covers this manifest
(it was parameterised over dotnet/classic only, so nothing tested it at all).

D2/R2-F10: status enum becomes open|fixed-in-repo|released|wont-fix so 'fixed' can no
longer mean both 'fixed in the repo' and 'fixed for the user'. 7 items backfilled by
commit ancestry against clavity-v17 - 4 released, 3 fixed-in-repo.
MSG
```

> Quoted heredoc, as for every commit in this batch — see Task 3 Step 13 for the measurement behind it.

---

## Task 3 (Commit 3): Group D — the extractor test, the gate comments, and coverage debt

Closes R4-F13, D1 part 2, D3 parts 1-2, and records the five deferred entries.

> 🔴 **This is the ONLY commit that edits `scripts/check-injected-context.ps1`, and it edits only COMMENTS.** Keep it that way. It is what makes the strict-capstone-reading escape hatch a one-commit operation: if the owner ever rules that any byte of the gate invalidates `06a39af`, this commit alone is the re-capstone target.

**Files:**
- Modify: `scripts/tests/check-injected-context.Tests.ps1`
- Modify: `scripts/check-injected-context.ps1` (comments only)
- Modify: `scripts/injected-context-ignore.txt`
- Modify: `commonmemory/ROADMAP.md`
- Modify: `agy-autotrain/CONTRIBUTING.md`
- Modify: `docs/coverage-debt.md`

- [ ] **Step 1: Write the failing test first**

Add this block to `scripts/tests/check-injected-context.Tests.ps1` **immediately before the file's final closing `}`** — the one closing `Describe 'check-injected-context.ps1'`, currently the last line of the file.

> 🔴 **Not at end-of-file.** The file is one `Describe` wrapping thirteen `Context` blocks, and its last three lines are `}` / `}` / `}` (closing the final `It`, its `Context`, and the `Describe`). A `Context` appended *after* that last brace sits outside any `Describe`, which Pester 5 rejects — the suite fails to run at all rather than failing an assertion. This mirrors the placement already given for the registration suite in Task 2 Step 2.
>
> Dot-sourcing the gate again inside this new block is idiomatic here, not a new risk: the file already dot-sources it in **six** separate `Context` blocks, and the script's main body is guarded by `if ($MyInvocation.InvocationName -ne '.')` so loading it never executes the gate.

```powershell
Context 'hook message extraction reaches every emitting hook' {
    BeforeAll {
        . $script:Script -RepoRoot $script:RepoRoot
        # Every .sh under a domain root. The gate's own $script:DomainRoots is the source of truth.
        $script:HookFiles = @(
            foreach ($root in $script:DomainRoots) {
                $dir = Join-Path $script:RepoRoot $root
                if (Test-Path $dir) { Get-ChildItem -Path $dir -Recurse -File -Filter '*.sh' }
            }
        )
    }

    It 'enumerates a plausible hook population' {
        # Non-vacuity guard. If the walk breaks, the row below iterates an empty set and passes by
        # comparing nothing to nothing - the exact false-clean shape this repo keeps paying for.
        $script:HookFiles.Count | Should -BeGreaterThan 20 -Because 'an empty enumeration would make the assertion below vacuous'
    }

    It 'extracts at least one message from every corpus hook that actually emits one' {
        $misses = @()
        foreach ($f in $script:HookFiles) {
            $text = [System.IO.File]::ReadAllText($f.FullName)
            # THE DISCRIMINATOR: actual emission on a NON-COMMENT line. Keying on "the file mentions
            # additionalContext" would RED two CORRECT hooks - agy-liveness-check.sh and
            # agy-anomaly-reminder.sh each mention it exactly once, inside a comment explaining why they
            # deliberately do NOT use it, and emit via stderr + `exit 2` instead (11 and 5 exit-2 sites).
            # Hooks that emit only to stderr are OUT OF SCOPE BY CONSTRUCTION, not an oversight.
            $emits = @($text -split "`n" | Where-Object {
                $_ -match '(systemMessage|additionalContext)' -and $_ -notmatch '^\s*#'
            })
            if ($emits.Count -eq 0) { continue }
            if (@(Get-HookMessages -Text $text).Count -eq 0) {
                $misses += $f.FullName.Substring($script:RepoRoot.Length + 1).Replace('\', '/')
            }
        }
        # Name them: a count sends a reader hunting, a name sends them to the file to fix.
        $misses -join ', ' | Should -BeExactly '' -Because 'Get-HookMessages binds msg[A-Za-z0-9_]* only, so a hook building its payload in a differently-named variable is invisible to the budget and tag-hygiene invariants'
    }
}
```

- [ ] **Step 2: Run it — expect GREEN, and understand why that is correct here**

```bash
pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"
```
Expected: 0 failed. The corpus complies **today** — measured, 18 hooks emit on a non-comment line and all 18 yield at least one extracted message. This test is a **regression guard**, not a bug reproduction, so a passing first run is the expected outcome and proves nothing on its own. Step 3 is what proves it.

- [ ] **Step 3: Prove non-vacuousness with a named logic mutant**

Edit `agy-autotrain/hooks/agy-learn-reminder.sh` and rename its `msg` variables to `payload` (assignments **and** references). Then re-run the suite.

Expected: the `extracts at least one message from every corpus hook that actually emits one` row goes **RED**, naming `agy-autotrain/hooks/agy-learn-reminder.sh`.

🔴 **If the row does NOT go red, do not proceed — and the two likely causes need different fixes.** Diagnose before touching anything else:

```bash
rg -c 'hook message extraction' scripts/tests/check-injected-context.Tests.ps1   # expect 1
rg -c '\bmsg[A-Za-z0-9_]*=' agy-autotrain/hooks/agy-learn-reminder.sh            # expect 0 under the mutant
```

- **First command returns 0** — the new `Context` never landed, or landed outside the `Describe` and the suite is not running it at all. Re-check Step 1's placement.
- **Second command returns non-zero** — the mutant did not take: you renamed some occurrences but not all, or edited a different file. Finish the rename.
- **Both are as expected but the row is still green** — stop and report it. That would mean the assertion cannot see a hook it should, and the guard R4-F13 exists to build is vacuous, which is worse than not having built it.

Then **revert immediately**:

```bash
git checkout -- agy-autotrain/hooks/agy-learn-reminder.sh
git diff --quiet agy-autotrain/hooks/agy-learn-reminder.sh && echo "reverted clean" || echo "🔴 STILL DIRTY"
```

> **`git checkout --` is safe here specifically because this batch never edits this file** — it is in no task's `git add` list, so HEAD is the mutant-free version. Confirm the revert rather than assuming it: a mutant left on disk is a corpus hook whose messages the gate can no longer extract, and if you are interrupted between the mutant and the revert there is nothing else in the plan that would notice before the final `git status --short`.

> **Why this file, specifically.** Measured during planning: the mutant takes `agy-learn-reminder.sh` from 4 extracted messages to **0**. Two traps are closed by naming it.
> - Pick `agy-liveness-check.sh` or `agy-anomaly-reminder.sh` and the mutant **passes silently**, because the test excludes stderr-only hooks by design — a control that fails for the wrong reason, which this project treats as no control at all.
> - Pick `agy-seam-inject.sh` and it **also passes**: measured, that hook stays at 4 messages under the same mutant because it emits through a different shape. A mutant that does not move the needle is not a control.
>
> **The mutant is temporary and uncommitted.** There is no fixture, no artifact, no sign-off. The only evidence that persists is one line in the commit message naming the test that went red.

- [ ] **Step 4: D1 part 1 — rewrite the two dead `.iss` references**

`commonmemory/ROADMAP.md:20-21` currently reads:

```
**The problem it fixed.** commonmemory used to register and deregister its plugin through
`installer/_shared/plugin-registration.iss` - roughly 13.6 KB of Inno-Pascal that hand-transliterated
```

Replace those two lines with:

```
**The problem it fixed.** commonmemory used to register and deregister its plugin through a former
Inno-Pascal registrar under installer/_shared/ - roughly 13.6 KB of Pascal that hand-transliterated
```

`commonmemory/ROADMAP.md:31` currently reads:

```
- **`installer/_shared/plugin-registration.iss` is deleted.** The Pascal implementation no longer exists.
```

Replace with:

```
- **The Inno-Pascal registrar under `installer/_shared/` has been deleted.** The Pascal implementation no longer exists.
```

> **Both replacements are deliberate about backticks.** A backticked path conventionally means "this exists and you can act on it"; citing a deleted file that way is a reader-level defect independent of the gate. Line 21 therefore carries **no backticks at all** — not even around a bare filename, since that argument applies to a filename exactly as it does to a path. Line 31 backticks only the **directory**, which ends in `/` and which `Test-IsPathCandidate` skips by rule (`check-injected-context.ps1:416`, `$Token.EndsWith('/') -> return $false`) — measured: `installer/_shared/` is a candidate = **False**.

- [ ] **Step 5: Verify D1 with a real oracle**

The as-shipped gate never resolves `.iss` at all, so running it unchanged proves nothing. Bypass the extension allowlist in-memory — no edit to the gate:

> **Do not use `$TMPDIR`** — measured on this box, it is **empty** in Git Bash, so `"$TMPDIR/probe-d1.ps1"` resolves to `/probe-d1.ps1`. Use `$TMP` (set to `C:\Users\user\AppData\Local\Temp`) or the session scratchpad.
>
> 🔴 **Run this from the clavity repository, not from a scratch directory.** The probe resolves its root with `git rev-parse --show-toplevel`, which returns the root of whatever repository the current directory belongs to. Scratch areas under `.clavity/scratch/` can contain throwaway git repositories (a peer review created one), and running the probe from inside one would silently audit the wrong tree and report a meaningless `candidates=0`.

```bash
PROBE="${TMP:-/tmp}/probe-d1.ps1"
cat > "$PROBE" <<'EOF'
Set-StrictMode -Version Latest
# Any unexpected throw - a failed dot-source, a missing function, a parameter-binding error - must NOT
# leave PowerShell's default exit 1, because exit 1 already MEANS "candidates examined, one failed".
# A setup failure that looks identical to a real finding is a diagnostic dead end. Route it to 4.
trap { Write-Host "FATAL: setup failed before any measurement: $_"; exit 4 }
# Resolve the repo root from git, never from cwd - this probe must not depend on where it is run.
$repo = (git rev-parse --show-toplevel)
if ($repo) { $repo = $repo.Trim() }
# IDENTITY GUARD. `git rev-parse` answers for whatever repository the cwd belongs to, and scratch areas
# can contain throwaway repos (a peer review created one). Resolving to the WRONG repo would make every
# later count zero and look like a clean result. Prove this is the clavity repo before trusting it.
if (-not $repo -or -not (Test-Path (Join-Path $repo 'scripts/check-injected-context.ps1'))) {
    Write-Host "FATAL: '$repo' is not the clavity repository - run this from the clavity working tree"
    exit 3
}
. (Join-Path $repo 'scripts/check-injected-context.ps1') -RepoRoot $repo
$text = [System.IO.File]::ReadAllText((Join-Path $repo 'commonmemory/ROADMAP.md'))
$script:ShippedExtensions = @($script:ShippedExtensions + 'iss')
$toks = [regex]::Matches($text, '`(?<t>[^`\r\n]+)`') | ForEach-Object { $_.Groups['t'].Value }
$cand = @($toks | Where-Object { Test-IsPathCandidate -Token $_ })
$fail = @()
foreach ($c in ($cand | Sort-Object -Unique)) {
    $r = Resolve-Reference -Token $c -RepoRoot $repo
    if (Test-ReferenceFails -Outcome $r.Outcome) { $fail += "$c => $($r.Outcome)" }
}
Write-Host "candidates=$($cand.Count) FAILING=$($fail.Count)"
$fail | ForEach-Object { Write-Host "  FAIL: $_" }
# The probe must not be able to report success by having examined nothing. A zero candidate count
# means the extraction broke (bad read, changed quoting, wrong repo root), NOT that the file is clean.
if ($cand.Count -eq 0) { Write-Host 'VOID: zero candidates examined - this result proves nothing'; exit 2 }
exit $(if ($fail.Count -gt 0) { 1 } else { 0 })
EOF
pwsh -File "$PROBE"; echo "probe exit: $?"
```

**Before the edit** (measured during planning): `candidates=12`, `FAILING=1`, naming `installer/_shared/plugin-registration.iss => unclassified`, **`probe exit: 1`**.
**After the edit:** `FAILING=0`, `candidates` still non-zero, **`probe exit: 0`**.

The probe now carries its own verdict in its exit status, so the three outcomes are distinguishable without interpreting prose:

| exit | meaning |
|---|---|
| `1` | candidates examined, at least one failed — the armed control, expected **before** the edit |
| `0` | candidates examined, none failed — expected **after** the edit |
| `2` | **VOID** — zero candidates examined, so the run proves nothing either way |
| `3` | **wrong repository** — the identity guard fired; you are not in the clavity working tree |
| `4` | **setup failed** — something threw before any measurement (failed dot-source, missing function, bad parameter binding). Distinct from `1` on purpose: a broken probe must never be readable as a real finding |

Two ways this check could otherwise lie, both now caught by the exit code rather than by the reader:
- **`FAILING=0` before you edit anything** (exit 0 where you expected 1) — the control never armed, so the rest of D1 proves nothing. **STOP.**
- **`FAILING=0` with `candidates=0`** — green by absence. If the backtick regex matched nothing (a failed read, a changed quoting style, a wrong repo root) the probe would report zero failures having examined zero tokens, which is indistinguishable from success in the `FAILING` number alone. That case now exits **2** and says `VOID`.

> A guard whose only defence is "the executor will read the number and interpret it correctly" is the same fail-open shape this probe exists to detect. Encode the verdict in the exit status.

🔴 **On exit 3 or 4, STOP — do not continue D1 and do not treat it as either outcome.** Exit 3 means you are not in the clavity working tree (check your directory). Exit 4 means the probe broke before measuring anything — the gate script failed to load, a function is missing, or a parameter did not bind. Neither is a result. Fix the cause and re-run; D1's verification is meaningless until the probe reaches 0 or 1.

- [ ] **Step 6: D1 part 2 — comment the real boundary beside `$AssertPrefixes`**

Insert immediately **above** line 427 of `scripts/check-injected-context.ps1` (the `$script:AssertPrefixes = @(...)` line):

```powershell
# 'installer/' is asserted for .ps1 ONLY. `.iss` is absent from $ShippedExtensions above, so
# Test-IsPathCandidate drops every .iss token before Resolve-Reference ever sees it - deliberately:
# installer content is PACKAGING INPUT, not injected context, and the extension test runs before any
# prefix logic here. MEASURED 2026-08-11: installer/_shared/anything.iss -> candidate False, while
# installer/_shared/register-plugin.ps1 (the only .ps1 under installer/) -> True. The cost is accepted
# and logged in docs/coverage-debt.md: a genuinely broken .iss reference sails past this gate.
```

- [ ] **Step 7: D3 part 1 — correct the false ignorelist rationale**

`scripts/injected-context-ignore.txt:32-36` currently reads:

```
# Owner ruling 2026-08-09, paired with adding clavity-classic/agy-mcp-bridge as a domain root. That root
# exists for ONE injected file - its SKILL.md, a headless sub-agent's system prompt - and carries a Python
# MCP server alongside it. Source code and an env template are executed and read by machines, never
# injected into an agent's context, so auditing them for mojibake or plan residue is category error, not
# coverage. Every .py in the whole domain lives under that one root; nothing else is affected.
```

Replace lines 34-36 (from `# MCP server alongside it. Source code` through `nothing else is affected.`) with:

```
# MCP server alongside it. THIS rule is scoped correctly - every .py in the whole domain lives under that
# one root - but its original reason was stated too broadly and that generalisation is FALSE: "source code
# is never injected into an agent's context" does not hold. Counter-example, measured 2026-08-11:
# ghidrust/crates/ghidrust-mcp/src/tools.rs holds 19 `pub const DESC_*` blocks totalling roughly 12 KB of
# description text that MCP delivers to EVERY agent via tools/list. The correct reason for THIS rule is narrower: the .py under
# agy-mcp-bridge is a transport implementation whose text no agent reads. Judge each case on whether the
# text reaches an agent, never on the file being "source code".
#
# WHERE THE BOUNDARY FALLS, and why tools.rs is not added as a domain entry. The encoding invariant exists
# for the Inno / CP437 route, where a mojibake byte corrupts a real installer. MCP tool descriptions travel
# UTF-8 JSON-RPC over stdio, where UTF-8 is well-defined, so that invariant categorically does not apply
# and auditing tools.rs for it would red-gate correct content (it carries 32 non-ASCII characters today
# - 25 em dashes, 4 section signs, 2 arrows, 1 ellipsis - all legitimate). Its ACCURACY is hand-verified instead, dated, with a named re-check trigger - see
# docs/coverage-debt.md.
```

> **The target file matters.** This note goes here, directly beneath the sentence whose over-generalisation caused the finding — **not** in a comment beside `$DomainRoots` in the gate. That keeps `check-injected-context.ps1` untouched by D3, so this commit's only gate edits stay the two comments in Steps 6 and 8.

**Then verify it is still pure ASCII — nothing else will:**

```bash
rg -c '[^\x00-\x7F]' scripts/injected-context-ignore.txt   # expect: no matches (exit 1)
```

> 🔴 **Same blind spot as the exemptions file.** `scripts/` is not in `$script:DomainRoots`, so the gate never audits its own ignorelist, and `check-installer-ascii.ps1` does not reach it either. Measured: **0** non-ASCII characters today. You are adding fourteen lines of hand-written prose to it, and the em dash is the exact character this repository keeps having to remove.

- [ ] **Step 8: Group D part 2 — document the `msg*` convention beside `Get-HookMessages`**

Insert immediately **above** the `function Get-HookMessages {` line of `scripts/check-injected-context.ps1` - which by the time you reach this step is **line 633, not 627**:

> 🔴 **Anchor on the symbol, not the number.** Step 6 inserted **6** comment lines above `:427`, which shifts everything below down by six. `Get-HookMessages` was at 627 when this plan was written and is at **633** once Step 6 has run; inserting at 627 now lands inside `Get-QuotedString`'s scanning loop. Measured during a dry run of this batch.

```powershell
# CONVENTION, and it is load-bearing: a hook's agent-visible message must be built in a variable named
# `msg` or `msg<Suffix>`. All three variable-bearing shapes below bind `msg[A-Za-z0-9_]*` and nothing else,
# so a payload assembled in a differently-named variable - `body=$(...)`, `payload="$a$b"` - yields ZERO
# extracted messages, and the payload-budget and tag-hygiene invariants then silently measure nothing.
# MEASURED 2026-08-11 with a control: a hook using msg='...' + `jq --arg m "$msg"` is caught; the same
# message carried in `body` or `payload` produced 0 extracted messages and no tag-hygiene violation even
# though the message duplicated a bracket tag.
# Widening this to follow command substitution and concatenation is an explicit NON-GOAL: the shape space
# is open-ended so it cannot be made complete, and it would be a behaviour change requiring a re-capstone.
# The convention is enforced by test instead - see scripts/tests/check-injected-context.Tests.ps1,
# 'extracts at least one message from every corpus hook that actually emits one' - and documented for
# contributors in agy-autotrain/CONTRIBUTING.md.
```

- [ ] **Step 9: Document the convention for contributors**

Append to `agy-autotrain/CONTRIBUTING.md`:

```markdown
## Writing a hook that shows the agent a message

Build the message in a variable named `msg`, or `msg<Suffix>` (`msgOverdue`, `msgStale`, ...). Nothing
else works.

`scripts/check-injected-context.ps1` extracts hook messages to enforce the payload-budget and tag-hygiene
invariants, and `Get-HookMessages` binds `msg[A-Za-z0-9_]*` only. A message assembled in `body`,
`payload`, or any other name is invisible to it - both invariants then pass by measuring nothing, which
looks exactly like compliance. Widening the extractor is a deliberate non-goal (the shape space is
open-ended), so the convention is the contract.

A hook that reports only via stderr and a non-zero exit is out of scope and needs no `msg` variable -
`agy-liveness-check.sh` and `agy-anomaly-reminder.sh` are the two examples in this repo.
```

- [ ] **Step 10: Record the five deferred entries in `docs/coverage-debt.md`**

Add to the **Accepted-boundary ledger** section. Each entry carries a compensation **and** an anchor whose disappearance voids it, per that file's own contract.

```markdown
### D. `.iss` references are unresolvable by design (Stage 2, D1)

`$ShippedExtensions` in `scripts/check-injected-context.ps1` omits `iss`, so every `.iss` token is dropped
before reference resolution. A genuinely broken `.iss` reference will not be reported.

**Compensation:** installer content is packaging input, never injected context, so it is outside what this
gate is for. The two dead references that existed were rewritten (`commonmemory/ROADMAP.md:20-21`, `:31`)
so no deleted file is cited as a live backticked path.
**Anchor (its disappearance voids this entry):** the ABSENCE of `'iss'` from `$script:ShippedExtensions` in `scripts/check-injected-context.ps1`. Adding that extension is what would close this gap, so the entry must void when it appears. **Deliberately NOT the explanatory comment above `$AssertPrefixes`** - a comment can be reworded or deleted with the gate's behaviour completely unchanged, so anchoring there would void the entry while the `.iss` blind spot it documents remained exactly as it was.

### E. `ghidrust/crates/ghidrust-mcp/src/tools.rs` has zero automated coverage (Stage 2, D3)

19 `pub const DESC_*` blocks totalling roughly 12 KB of description text, delivered to every agent by MCP `tools/list` (all 19 verified wired into `server.rs`, not dead constants). `ghidrust/crates`
is not a domain root and is deliberately not being added: the encoding invariant exists for the Inno /
CP437 route, and these descriptions travel UTF-8 JSON-RPC over stdio, so adding the file would red-gate
correct content.

**Compensation:** accuracy hand-verified 2026-08-11 - all 19 documented tool names exist in
`ghidrust/crates/`, and all 5 tools the skill says will "dead-end" are genuinely absent.
**Re-check trigger: a tool is added or renamed.**
**Anchor (its disappearance voids this entry):** the ABSENCE of `ghidrust/crates` from `$script:DomainRoots` in `scripts/check-injected-context.ps1`. Adding that root is precisely what would close this gap, so the entry must void the moment it appears. Anchoring on the `DESC_*` block instead would anchor on something that exists as long as the file does and could therefore never void anything.

### F. Repo-vs-install drift is undetected (Stage 2, D2)

Nothing detects that a fix committed to the repo has not reached a user's installed tree. A CI check was
rejected: CI cannot see a user-machine artifact, so it would be green-by-absence - a guard that fails open.

**Compensation:** the backlog status enum now makes "fixed for the user" a distinct, required state
(`open | fixed-in-repo | released | wont-fix`), decided by commit ancestry against the latest release tag
rather than by guess. Escalation path if this recurs: an **install-time** diagnostic inside the installer,
which reaches the user rather than CI.
**Anchor:** the `status:` enum line in `agy-autotrain/docs/fix-the-tool-backlog/_template.md`.

### G. commonmemory's agy-native recall rule is never verified to load (Stage 2, R5-O2)

`commonmemory/rules/commonmemory.md` is audited as injected context, but `commonmemory/README.md:22`
and `:77` annotate it "agy-native proactive-recall rule (Claude ignores it)", and `:57-58` leaves the
loading mechanism unconfirmed - "if your agy auto-applies plugin `rules/` ... verify once". Neither
manifest declares a `rules/` surface, and that "verify once" appears never to have happened. Whether
commonmemory's core recall mechanism fires for agy at all is unknown.

**Compensation:** the failure mode is inert, not wrong - a rule that never loads is a no-op, not an
incorrect action. The gate auditing it anyway is fail-safe over-coverage.
**Re-check trigger: the next time a live agy peer is reachable.** Closing this needs an empirical test
against a live agy, which is out of scope for a doc-and-test batch.
**Anchor:** the "verify once" sentence at `commonmemory/README.md:57-58`.
### H. The backlog `status:` enum has no durable enforcement (Stage 2, D2)

D2 replaces `open | fixed | wont-fix` with `open | fixed-in-repo | released | wont-fix`, and requires
`released-in:` alongside `released`. **Nothing enforces either.** Measured 2026-08-11: several scripts read
`agy-autotrain/docs/fix-the-tool-backlog/` (`drain-lib.ps1`, `abort-drain.ps1`, `check-user-facing-docs.ps1`,
the injected-context gate) but **no test asserts a `status:` value is in the enum**, and none checks that a
`released` item carries `released-in:`. A future item typed `fixed-in-repos`, or marked `released` with no
version, passes every gate.

This is the exact defect shape F1 addresses elsewhere in this batch: a stated rule with no mechanism drifts,
and the drift is invisible because the file still looks well-formed.

**Compensation:** the batch's own backfill is verified at execution time - Task 2 Step 8 asserts the exact
population (`4x released, 3x fixed-in-repo, 1x wont-fix, 1x open`, no bare `fixed`), so the *current* state
is known-good. What is missing is a guard against the *next* edit. The `_template.md` enum line carries the
rule and the measurable ancestry test for deciding `released`, so an author following the template is
steered correctly.
**Re-check trigger: the next time an item is added or its status changed.** Closing it means a Pester row
over that directory asserting the enum and the `released` -> `released-in:` pairing - deliberately not done
here, because it needs a new registered suite and this batch's scope is the seventeen findings.
**Anchor (its disappearance voids this entry):** the **ancestry-rule comment block** beneath the `status:` line in `agy-autotrain/docs/fix-the-tool-backlog/_template.md` - the paragraph beginning `fixed-in-repo` vs `released` is the distinction this enum exists to force. **Deliberately NOT the bare `status:` enum line**, which entry F already anchors on: two entries sharing one anchor means a single edit voids both, and these document different gaps (F is repo-vs-install drift, H is the absent enforcement). An anchor that cannot tell its own entry apart from another's cannot do the job the file's header assigns it.

```

- [ ] **Step 11: Verify**

```bash
pwsh -File scripts/check-injected-context.ps1     # expect OK, exit 0
bash scripts/check-seed-artifacts-synced.sh       # expect exit 0
pwsh -File "$PROBE"; echo "probe exit: $?"        # expect candidates non-zero, FAILING=0, exit 0
# 🔴 exit 3 or 4 here is NOT a pass - STOP and do not run Step 13. Step 10 records a coverage-debt
# entry whose anchor is the $AssertPrefixes comment this probe verifies; committing on a broken
# probe files a debt entry with no basis behind it.
```
Then `just test-scripts-fast` backgrounded; read `Tests Passed:`.

- [ ] **Step 12: Confirm the gate diff is comments-only**

```bash
git diff --stat scripts/check-injected-context.ps1
git diff scripts/check-injected-context.ps1 \
  | rg '^[+-]' \
  | rg -v '^(\+\+\+|---)' \
  | rg -v '^[+-]\s*#' \
  | rg -v '^[+-]\s*$'
```
The second command must print **nothing**. Any added **or removed** non-comment line means this commit changed gate behaviour and `06a39af` no longer stands — **STOP** and report it.

> 🔴 **`^[+-]`, not `^\+`. A guard that inspects only ADDED lines is fail-open, and this one protects the capstone.** Measured with a control: deleting the non-comment line `$y = 2` produces a diff containing `-$y = 2`, and an additions-only pipeline prints **nothing** — certifying a real behaviour change as "comments-only". The four cases this form must satisfy, all verified: delete a non-comment line -> caught; add a non-comment line -> caught; add only comments and blank lines -> silent; delete a comment line -> silent.
>
> A peer panel reviewed the additions-only form and explicitly certified it — *"this genuinely proves comments-only; any non-comment added line would be caught"* — which is true of additions and says nothing about deletions. Do not restore the shorter form.

- [ ] **Step 13: Commit**

```bash
git add scripts/tests/check-injected-context.Tests.ps1 \
        scripts/check-injected-context.ps1 \
        scripts/injected-context-ignore.txt \
        commonmemory/ROADMAP.md \
        agy-autotrain/CONTRIBUTING.md \
        docs/coverage-debt.md
git commit -F - <<'MSG'
test(gate): pin the msg* hook-message convention; document two real boundaries

R4-F13: Get-HookMessages binds msg[A-Za-z0-9_]* only, so a hook building its payload in a
differently-named variable yields zero extracted messages and the payload-budget and
tag-hygiene invariants silently measure nothing. Documented beside the function and in
agy-autotrain/CONTRIBUTING.md, and pinned by a new test. Widening the extractor stays a
non-goal. Non-vacuity proven with a temporary logic mutant renaming msg -> payload in
agy-autotrain/hooks/agy-learn-reminder.sh: the new row
'extracts at least one message from every corpus hook that actually emits one' went RED
(4 extracted messages -> 0). Mutant reverted, nothing committed.

D1: commonmemory/ROADMAP.md cited a deleted .iss file as a live backticked path twice.
Rewritten; the real boundary is now commented beside $AssertPrefixes.
D3: the **/*.py ignorelist rationale claimed source code is never injected. tools.rs
falsifies that - roughly 12 KB of MCP tool descriptions reach every agent. Reason corrected and
the encoding boundary documented.

THIS IS THE ONLY COMMIT TOUCHING scripts/check-injected-context.ps1, and it adds only
comments - verified with the BIDIRECTIONAL guard from step 12, `git diff <file> | rg '^[+-]' |
rg -v '^(\+\+\+|---)' | rg -v '^[+-]\s*#' | rg -v '^[+-]\s*$'`, printing nothing. An
additions-only form would be fail-open on a deleted non-comment line. If the
capstone-invalidation rule is ever read strictly, this commit alone is the re-capstone target.
MSG
```

> 🔴 **`git commit -F - <<'MSG'` — a QUOTED heredoc — and not `-m "..."`. This is not a style choice; it is a correctness fix, MEASURED.** Inside a double-quoted `-m`, bash performs command substitution on backticks and variable expansion on `$`. This message contains both, and the failure is **silent and exit-0**:
> - `` `git diff <file> | rg ...` `` — bash tries to EXECUTE it, prints `syntax error near unexpected token '|'` to stderr, **commits anyway with exit 0**, and stores `verified with the BIDIRECTIONAL guard from step 12, , printing nothing` — the evidence deleted from the permanent record.
> - `$AssertPrefixes` — expands to the empty string, storing `commented beside .`
>
> With `<<'MSG'` (delimiter in single quotes) there is no expansion of any kind, so backticks, `$` and single backslashes are all stored verbatim — which is why the regex above uses `\+` and `\s`, not the doubled `\\+` a `-m` form needed. Verified in a throwaway repo: the heredoc form reproduces every character exactly.

---

## Task 4 (Commit 4): Group B — the ghidrust emit contract

Closes F3 and R7-F15. **This is the only group that changes executable behaviour.**

**Files:**
- Modify: `ghidrust/crates/ghidrust-mcp/src/main.rs`
- Modify: `ghidrust/crates/ghidrust-mcp/src/skill_asset.rs` (comment + a strip helper)
- Create: `ghidrust/crates/ghidrust-mcp/tests/skill_emit.rs`
- Modify: `ghidrust/CONTRIBUTING.md`

- [ ] **Step 1: State-verification - pin the strip boundary before touching anything**

```bash
awk 'NR<=10{printf "%d|%s\n",NR,$0}' ghidrust/skill/SKILL.md
wc -l < ghidrust/skill/SKILL.md
wc -l < ghidrust/plugin/skills/ghidra-re-driver/SKILL.md
tail -n +10 ghidrust/skill/SKILL.md | cmp - ghidrust/plugin/skills/ghidra-re-driver/SKILL.md   && echo 'STRIP BOUNDARY CONFIRMED: plugin copy == canonical minus its first 9 lines'
```

Expected: line 1 = `<!--`, line 9 = `-->`, line 10 = `---`, **no blank line between them**; canonical **234** lines, plugin copy **225** (`234 - 9 = 225`); and the `cmp` prints its confirmation line.

> 🔴 **DO NOT VERIFY THIS BY BYTE COUNT, and do NOT treat a byte mismatch as a `STATE_MISMATCH`.** The byte figures depend on the checkout's line endings, so no single number is correct for both. Measured on the same commit: canonical **17566 B** / plugin **16937 B** in an LF tree, but **17800 B** / **17162 B** in a CRLF one - and a fresh clone of this repository produces CRLF (`core.autocrlf=true`; `.gitattributes` pins `eol=lf` for `*.sh` only, nothing for `*.md`). An earlier draft of this step asserted the LF figures, which would have halted Task 4 at its very first step for anyone executing from a clean checkout.
>
> The **line counts (234 / 225) are identical under both**, and the `cmp` above is the real oracle: it compares content, so it holds either way. A `cmp` mismatch IS a `STATE_MISMATCH`.
>
> 🔴 **Strip exactly lines 1-9. Do NOT strip a tenth.** There is no blank line after `-->`; stripping 10 lines emits 224 lines and reds the oracle on a correct implementation. Verified as a control: `tail -n +11 | cmp` DIFFERS, so this check genuinely discriminates the right boundary from the adjacent wrong one - it is not merely passing because `cmp` is lenient.
>
> Both files end in `0a`, so there is no trailing-newline asymmetry for `print!` to expose.

- [ ] **Step 2: Add the strip helper to `skill_asset.rs`**

Append to `skill_asset.rs`, **outside** the `#[cfg(test)] mod tests` block (place it directly after the `DRIVER_SKILL` const at line 10):

```rust
/// The bytes `ghidrust skill --emit` writes: the canonical with its leading HTML comment header removed,
/// so the output IS the shipped plugin copy rather than something a caller must post-process.
///
/// The header is maintainer-facing ("edit ONLY the canonical, this copy is generated") and is meaningless
/// once emitted into the generated copy. Stripping happens HERE, at emit time, and never in `DRIVER_SKILL`
/// itself - `embedded_skill_matches_disk_source` below asserts the const equals the canonical byte for
/// byte, so stripping in the const would red that test.
pub fn emit_bytes() -> &'static str {
    // Find the header's closing delimiter, then resume after whatever line ending follows it.
    // Matching the line ending explicitly (e.g. `find("\n-->\n")`) would silently fail on a CRLF
    // checkout: the file would read `-->\r\n`, the pattern would not match, and the fallback below
    // would emit the ENTIRE canonical including the header - a red oracle with a confusing message
    // on a machine that differs from the author's only in `core.autocrlf`.
    // The header is an HTML comment at offset 0, so REQUIRE that before searching for its close.
    // Without this the `None` fallback below is illusory: on a canonical with no header whose BODY
    // happens to contain `-->` (an HTML comment close in an example, say), `find` would hit the body
    // occurrence and silently strip everything before it, which is the opposite of "emit as-is".
    if !DRIVER_SKILL.starts_with("<!--") {
        return DRIVER_SKILL;
    }
    match DRIVER_SKILL.find("-->") {
        Some(i) => match DRIVER_SKILL[i..].find('\n') {
            Some(j) => &DRIVER_SKILL[i + j + 1..],
            // A closing delimiter with nothing after it: emit nothing rather than the header.
            None => "",
        },
        // No header at all (a canonical that never had one): emit as-is rather than truncating.
        None => DRIVER_SKILL,
    }
}
```

> **Why match on the delimiter rather than counting 9 lines.** A line count silently emits the wrong thing if the header ever gains or loses a line; the delimiter search either finds the real end of the comment or falls through to emitting everything. Neither branch can truncate the body.
>
> 🔴 **And why the search is line-ending agnostic.** Measured on the author's machine, both files are **LF** (`\n-->\n` present, `\r\n-->\r\n` absent, both ending in a bare `0a`) — but `core.autocrlf` is `true` here and `.gitattributes` carries **no rule for `*.md`**, so a different checkout can legitimately produce CRLF. Anchoring on `-->` and then on the next `\n` works under both. The companion test `emit_output_does_not_carry_the_maintainer_header` accepts `---\n` or `---\r\n` for the same reason.
>
> ⚠ **The 17566 / 629 / 16937 figures in Step 1 are LF byte counts.** On a CRLF checkout every count rises by one byte per line and the subtraction no longer lands on 16937 — which is exactly why Step 1 tells you to trust the **plugin copy's own size** as the target rather than the arithmetic, and why the oracle compares emitted bytes to that file rather than to a number.

- [ ] **Step 3: Use it in `main.rs` and correct the now-false comment**

`main.rs:29-34` currently reads:

```rust
                // stdout is safe here: `skill` is a one-shot CLI utility invocation, NOT the `serve`
                // MCP JSON-RPC channel. `print!` (no trailing newline) keeps the output byte-identical
                // to skill/SKILL.md so the installer's `ghidrust skill --emit > SKILL.md` round-trips.
                // (`ghidrust::` is the LIB crate - `main.rs` is a separate bin crate in this package,
                // exactly as the existing `ghidrust::config::` / `ghidrust::server::` uses above.)
                print!("{}", ghidrust::skill_asset::DRIVER_SKILL);
```

Replace with:

```rust
                // stdout is safe here: `skill` is a one-shot CLI utility invocation, NOT the `serve`
                // MCP JSON-RPC channel. `print!` (no trailing newline) keeps the output byte-identical
                // to the SHIPPED PLUGIN COPY - not to skill/SKILL.md, whose maintainer-facing HTML
                // comment header `emit_bytes()` strips - so `ghidrust skill --emit > SKILL.md` round-trips
                // into plugin/skills/ghidra-re-driver/SKILL.md exactly. Pinned by tests/skill_emit.rs.
                // (`ghidrust::` is the LIB crate - `main.rs` is a separate bin crate in this package,
                // exactly as the existing `ghidrust::config::` / `ghidrust::server::` uses above.)
                print!("{}", ghidrust::skill_asset::emit_bytes());
```

- [ ] **Step 4: Correct the false round-trip claim at `skill_asset.rs:52-53`**

Replace:

```rust
    /// Shell-free byte-identity oracle for `ghidrust skill --emit`: the embedded const must equal the
    /// on-disk source, so `ghidrust skill --emit` round-trips into the plugin copy exactly. Reads the
```

with:

```rust
    /// Shell-free byte-identity oracle for the EMBEDDING step: the const must equal the on-disk canonical.
    /// It does NOT prove the emit round-trips into the plugin copy - `--emit` strips the canonical's HTML
    /// comment header via `emit_bytes()`, so the two differ by exactly that header. The emit contract is
    /// pinned separately by tests/skill_emit.rs, which compares the built binary's stdout to the committed
    /// plugin copy. Reads the
```

- [ ] **Step 5: Write the missing oracle**

Create `ghidrust/crates/ghidrust-mcp/tests/skill_emit.rs`:

```rust
//! The oracle nobody had: `ghidrust skill --emit` must reproduce the COMMITTED plugin copy byte for byte.
//!
//! Nothing compared them before. `skill_asset.rs` compares the embedded const to the CANONICAL, and the
//! ship-guard is a `.contains(...)` substring check that passes whether the frontmatter sits at line 1 or
//! line 11 - so a regenerated copy carrying a stray header would have shipped unnoticed.
//!
//! This is the FAST tier (`just test`, pure Rust, no Ghidra and no JVM): `skill --emit` only prints an
//! embedded `include_str!` const. Putting it behind `just test-all` would gate the emit contract on
//! GHIDRA_INSTALL_DIR + JDK 21, so it would almost never run.

use std::path::PathBuf;
use std::process::Command;

/// The committed plugin copy - the artifact `--emit` is supposed to regenerate.
fn plugin_copy() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../plugin/skills/ghidra-re-driver/SKILL.md")
}

#[test]
fn emit_reproduces_the_committed_plugin_copy_byte_for_byte() {
    // `env!("CARGO_BIN_EXE_ghidrust")` is the built binary's path, resolved by cargo at compile time.
    // No `cargo run` subprocess indirection, and unambiguous: Cargo.toml declares exactly one [[bin]].
    let out = Command::new(env!("CARGO_BIN_EXE_ghidrust"))
        .args(["skill", "--emit"])
        .output()
        .expect("run `ghidrust skill --emit`");

    assert!(
        out.status.success(),
        "`skill --emit` exited {:?}: {}",
        out.status.code(),
        String::from_utf8_lossy(&out.stderr)
    );

    let expected = std::fs::read(plugin_copy()).expect("read the committed plugin copy");

    // Compare as text so a failure is readable, but assert on the exact bytes.
    if out.stdout != expected {
        let got = String::from_utf8_lossy(&out.stdout);
        let want = String::from_utf8_lossy(&expected);
        let first_diff = got
            .lines()
            .zip(want.lines())
            .position(|(a, b)| a != b)
            .map(|i| format!("first differing line: {}", i + 1))
            .unwrap_or_else(|| "no differing line; lengths differ".to_string());
        panic!(
            "`skill --emit` no longer reproduces plugin/skills/ghidra-re-driver/SKILL.md.\n\
             emitted {} bytes / {} lines, committed copy {} bytes / {} lines\n{}\n\
             Regenerate with: ghidrust skill --emit > plugin/skills/ghidra-re-driver/SKILL.md",
            out.stdout.len(),
            got.lines().count(),
            expected.len(),
            want.lines().count(),
            first_diff
        );
    }
}

#[test]
fn emit_output_does_not_carry_the_maintainer_header() {
    // A second, independent lens on the same contract: even if the copy above were regenerated WRONG and
    // committed, this row still fails. It encodes what the header IS rather than what the copy happens to
    // contain, so the two rows cannot go green together on a bad copy.
    let out = Command::new(env!("CARGO_BIN_EXE_ghidrust"))
        .args(["skill", "--emit"])
        .output()
        .expect("run `ghidrust skill --emit`");
    let text = String::from_utf8(out.stdout).expect("emit output is UTF-8");

    assert!(
        text.starts_with("---\n") || text.starts_with("---\r\n"),
        "emit must begin at the frontmatter `---`, got: {:?}",
        text.chars().take(40).collect::<String>()
    );
    // STRUCTURAL first: the emit must not begin inside an HTML comment. This survives the header's
    // text being reworded, which the content check below does not - replace the SPDX line with a
    // differently-worded copyright and a leaked header would sail past a content-only assertion.
    assert!(
        !text.starts_with("<!--"),
        "emit begins inside an HTML comment - the maintainer header leaked"
    );
    // Content check kept as a second, independent signal against today's specific header.
    assert!(
        !text.contains("SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0"),
        "the maintainer-facing HTML comment header leaked into the emitted copy"
    );
}
```

- [ ] **Step 6: Run the ghidrust fast tier**

```bash
(cd ghidrust && just test)
```
Expected: green, including `skill_emit::emit_reproduces_the_committed_plugin_copy_byte_for_byte` and `skill_emit::emit_output_does_not_carry_the_maintainer_header`, and the pre-existing `skill_asset::tests::embedded_skill_matches_disk_source` **still passing** (the strip is at emit time, not in the const).

- [ ] **Step 7: Prove the oracle is not vacuous — revert BY HAND, never `git checkout --` (it would discard Steps 2-4)**

In `main.rs`, temporarily change the one identifier in the emit call from `emit_bytes()` back to `DRIVER_SKILL`:

```rust
                print!("{}", ghidrust::skill_asset::DRIVER_SKILL);   // MUTANT - revert after observing red
```

Then:

```bash
(cd ghidrust && just test)
```
Expected: **both** new rows go RED — the byte comparison reports 17566 emitted vs 16937 committed, and the header row reports the SPDX line leaked. `skill_asset::tests::embedded_skill_matches_disk_source` must stay **green** throughout, since the const is untouched.

Revert by editing that one line back to exactly:

```rust
                print!("{}", ghidrust::skill_asset::emit_bytes());
```

At this point `DRIVER_SKILL` appears exactly once in `main.rs` — the mutant line — so `rg -n 'DRIVER_SKILL' ghidrust/crates/ghidrust-mcp/src/main.rs` locates it unambiguously and returning zero matches confirms the revert.

**Then re-run `(cd ghidrust && just test)` and confirm it is green again before moving on.** The `rg` check proves the identifier is gone; it does not prove what replaced it compiles or behaves. A revert with a typo either fails to build or — worse — builds into something that emits the wrong bytes, and the next step commits it. The mutant is not finished until the suite is green.

> 🔴 **Do NOT revert with `git checkout -- ghidrust/crates/ghidrust-mcp/src/skill_asset.rs` or `-- src/main.rs`.** Both files carry the **uncommitted** work of Steps 2-4 at this point, and a checkout would discard the entire fix, not just the mutant. Mutate the single identifier in `main.rs` and put it back by hand — that is why the mutant is sited there rather than in `emit_bytes()` itself.
>
> This is a logic mutant, not a signature break: it compiles cleanly and fails only on behaviour, which is what makes it evidence.

- [ ] **Step 8: Simplify the now-redundant regeneration command**

`ghidrust/CONTRIBUTING.md:80` currently reads:

```
  ghidrust skill --emit | awk '/^---/{p=1} p' > plugin/skills/ghidra-re-driver/SKILL.md
```

Replace with:

```
  ghidrust skill --emit > plugin/skills/ghidra-re-driver/SKILL.md
```

> The `awk` filter was doing the strip externally — it is what generated today's plugin copy, and it independently confirms the boundary. Now that `--emit` strips the header itself the filter is redundant, and leaving it invites the reader to think the raw emit is unusable. `ghidrust/skill/SKILL.md:6` already documents the plain form (`ghidrust skill --emit > SKILL.md`), which was the *trap* before this change and becomes **correct** with it — so it needs no edit.

- [ ] **Step 9: Confirm the committed plugin copy is unchanged**

```bash
git status --short ghidrust/plugin/
```
Expected: **empty**. This change makes `--emit` produce what is already committed; it does not regenerate it. If the copy shows as modified, the strip is wrong — **STOP**.

- [ ] **Step 10: Full verification, including criterion 6**

```bash
pwsh -File scripts/check-injected-context.ps1     # expect OK, exit 0
bash scripts/check-seed-artifacts-synced.sh       # expect exit 0
(cd ghidrust && just test)                        # criterion 6 - green
```
Then `just test-scripts-fast` backgrounded; read `Tests Passed:`.

- [ ] **Step 11: Commit**

```bash
git add ghidrust/crates/ghidrust-mcp/src/main.rs \
        ghidrust/crates/ghidrust-mcp/src/skill_asset.rs \
        ghidrust/crates/ghidrust-mcp/tests/skill_emit.rs \
        ghidrust/CONTRIBUTING.md
git commit -F - <<'MSG'
fix(ghidrust): make skill --emit reproduce the shipped copy, and pin it

F3 + R7-F15. skill_asset.rs claimed `ghidrust skill --emit` round-trips into the plugin copy
exactly. It did not: DRIVER_SKILL is include_str! of the canonical INCLUDING its 9-line HTML
comment header, main.rs printed it verbatim, and the shipped copy starts at `---`. Nothing
compared the two - skill_asset.rs compares the const to the CANONICAL, and the ship-guard is
a .contains() substring check that passes whether frontmatter sits at line 1 or line 11.

--emit now strips the header via emit_bytes() at emit time (never in the const, which
embedded_skill_matches_disk_source still pins against the canonical), and tests/skill_emit.rs
adds the missing oracle: the built binary's stdout must equal the committed plugin copy byte
for byte. Fast tier - it prints an embedded const and never starts a JVM. The false claims in
skill_asset.rs and main.rs are corrected, and CONTRIBUTING.md's awk filter - which was doing
this strip externally - is now redundant and removed.

Non-vacuity: reverting emit_bytes() to DRIVER_SKILL turns both new rows red (17566 emitted vs
16937 committed; SPDX header leaked). Mutant reverted.
MSG
```

> 🔴 **Quoted heredoc, not `-m "..."`, and here the stakes are higher than a lost sentence.** This message contains `` `ghidrust skill --emit` `` and `` `---` ``. Under `-m "..."` bash treats both as command substitution and **actually runs them**: `` `---` `` fails harmlessly to empty, but if the `ghidrust` binary is on `PATH` at commit time — and by this point in the batch you have just built it — `` `ghidrust skill --emit` `` **succeeds**, and its entire ~16.9 KB of emitted SKILL.md is substituted into the commit message. See the note at Task 3 Step 13 for the measurement.

---

## Final verification

- [ ] **Step 1: All six criteria, on the finished batch**

```bash
just test-scripts-fast                            # BACKGROUNDED. Read "Tests Passed:".
bash scripts/check-seed-artifacts-synced.sh       # exit 0
pwsh -File scripts/check-injected-context.ps1     # OK, exit 0
(cd ghidrust && just test)                        # green
```

- [ ] **Step 2: Confirm the capstone still stands**

```bash
git diff 90cb0b5..HEAD -- scripts/check-injected-context.ps1 \
  | rg '^[+-]' \
  | rg -v '^(\+\+\+|---)' \
  | rg -v '^[+-]\s*#' \
  | rg -v '^[+-]\s*$'
```
Must print nothing — **both directions**, per the control documented at Task 3 step 12. If it prints anything, `06a39af` no longer covers the gate and AGY-CAPSTONE must be re-run over commit 3 before the branch is declared complete.

- [ ] **Step 3: Confirm the shape of the batch**

> **The base is `90cb0b5`, not `b102cc3`.** Two fixes landed on the branch after this plan was first written - `b102cc3` (the gate's untracked-file dependency) and `90cb0b5` (a test regex that failed on any CRLF checkout). Both were found by dry-running this batch in a clean worktree and are already verified; neither is part of the batch, so the batch's range and its owed capstone start at `90cb0b5`. If you see `b102cc3` quoted as the base anywhere else, it is stale.

```bash
git log --oneline 90cb0b5..HEAD          # expect 5 commits (Task 0 + commits 1-4)
git status --short                       # expect empty
git rev-list --count origin/main..HEAD   # expect 53 = 48 at the base + this batch's 5
# If this reads anything else, re-derive rather than assuming a miscount: the 48 was MEASURED at
# 90cb0b5 on 2026-08-11, and `origin/main` advancing would change it. `git rev-list --count origin/main..90cb0b5`
# gives the true "before" figure; that plus 5 is the number to expect.
```

- [ ] **Step 4: Commit this plan and the spec**

Both are gitignored, so `-f` is required:

```bash
git add -f docs/superpowers/specs/2026-08-11-stage2-fix-batch-design.md \
           docs/superpowers/plans/2026-08-11-stage2-fix-batch.md
git commit -m "docs(plans): the Stage 2 fix-batch spec and its implementation plan"
```

- [ ] **Step 5: Run the pre-push gates — the Standing Rules require this and no earlier step does it**

```bash
just check-user-facing-docs
just check-doc-stubs
just check-member-docs
```

All three must pass. This batch edits `scripts/README.md`, which is on the user-facing docs roster (`docs/user-facing-docs.txt:23`), so the first is directly in scope.

> 🔴 **This step exists because the Standing Rules said to do this and nothing told you when.** The nine `lefthook.yml:19-46` commands fire on **push**, not on any of this batch's five commits — so a batch can be green on all six criteria and still fail the moment the owner pushes. Running them here converts a failure the owner would discover into one you fix. Never reach for `--no-verify`.

- [ ] **Step 6: Report the batch as EXECUTED, not COMPLETE — two disciplines are owed and neither is this plan's to run**

🔴 **This batch adds executable code and tests, so the project's standing rules gate its completion on two disciplines that appear nowhere else in this plan.** Say so explicitly in the handoff rather than reporting "done":

- **AGY-CAPSTONE is owed over this batch's own range.** The rule gates *"declaring ANY plan/implementation COMPLETE"* on a convergent review of *"the COMMITTED IMPLEMENTATION (the executable code + tests)"*. This batch adds `scripts/check-cheatsheet-budget.ps1`, a six-row Pester suite, a new `Context` in the gate's suite, four rows in the registration suite, and `emit_bytes()` plus two Rust tests. That is executable code and tests, so a capstone over **`90cb0b5..HEAD`** is owed before anyone calls this done.
- **AGY-TEST-AUDIT follows a green capstone**, because the branch changed both executable code and tests. It asks the orthogonal question this batch never asks: *would these tests catch the NEXT regression?*

**Do not run either yourself.** Both are owner-scheduled, both consult the peer, and the peer is currently the qwen substitution under a standing owner ruling. Your job is to hand over an accurate state.

> **The distinction that matters, and why this step exists.** `06a39afe47ae479bcba5101e7142e63f188f9031` is the capstone over the **gate**, and this batch is shaped throughout to keep it valid — that is the "commit 3 is comments-only" property. Preserving that marker says nothing about whether the batch's **own** new code has ever been reviewed. It has not. A plan that guards one marker so carefully that it forgets to claim a second one reads as complete while leaving the newest, least-examined code entirely unaudited.

- [ ] **Step 7: Write the handoff — this report is the ONLY thing the owner receives**

Everything above produced measurements. **None of it reaches the owner unless you write it down here.** A report saying "done, all green" is unverifiable: the owner would have to re-run every gate to learn what you already know. Report all of this, and say plainly where a figure is missing rather than omitting it:

```
EXECUTED, not COMPLETE.

Commits        : <output of `git log --oneline 90cb0b5..HEAD`>
Working tree   : <output of `git status --short`> — expect empty
Fast suite     : Tests Passed: <N> / <total>, runtime <T>s against the 600 s cap
Gate           : check-injected-context: <OK|FAIL>
Seed artifacts : check-seed-artifacts-synced.sh exit <N>
ghidrust       : (cd ghidrust && just test) -> <pass|fail>, incl. both skill_emit rows
Pre-push gates : check-user-facing-docs <p/f>, check-doc-stubs <p/f>, check-member-docs <p/f>
Mutants        : all three restored and re-verified? <yes|no, which>
Coverage debt  : entries D-H written to docs/coverage-debt.md? <yes|no>
Deviations     : <every step skipped, retried, or done differently than written — or "none">
Judgement calls: <every STOP gate that fired and what you decided — or "none fired">
OWED           : AGY-CAPSTONE over 90cb0b5..HEAD, then AGY-TEST-AUDIT. Neither run.
```

🔴 **Two lines are load-bearing and easy to skip.** *Deviations* and *Judgement calls* are where a batch quietly goes wrong: this plan contains several STOP gates, and one firing is not a failure — but the owner deciding whether to push needs to know it fired and what you concluded. "None" is a perfectly good answer; silence is not, because silence and "nothing happened" are indistinguishable to the reader.

> **Flag any coverage-debt entry whose compensation you judge weak.** Entry G's compensation is a risk assessment — *the rule is inert if it never loads* — not a mechanism. That is a deliberate, owner-visible deferral, and the owner should be reminded of it at the moment they decide to push rather than discovering it in the ledger later.

- [ ] **Step 8: Do NOT push.** The owner owns every push. Hand over the Step 7 report and wait.

---

## Self-review

**1. Spec coverage — all 17 findings map to a task.**

| Finding | Task | Finding | Task |
|---|---|---|---|
| D1 (F9) | 3 (steps 4-6) | F16 | 1 (step 9) |
| D2 (R2-F10) | 2 (steps 6-8) | F1 | 1 (steps 3, 10-17b) |
| D3 (R3-F12) | 3 (step 7) | F6 | 1 (step 5) |
| F4 | 1 (step 2) | F17 | 1 (step 6) |
| F5 | 1 (step 4) | F3 | 4 |
| R2-F11 | 1 (step 7) | R7-F15 | 4 (step 5) |
| F2 + F7 | 1 (step 8) | R6-F14 | 2 (steps 2-5) |
| R4-F13 | 3 (steps 1-3, 8-9) | R5-O2 | 3 (step 10, entry G) |

Success criteria 1-3 run after every commit; criterion 4 is satisfied by the five `coverage-debt.md` entries (D-H), each with a compensation and a void-anchor; criterion 5 holds because F1, F6 and F17 are all closed in commit 1 and nothing is deferred pending a decision; criterion 6 runs in Task 4 step 10.

**2. Placeholder scan:** no TBD, no "handle edge cases", no "similar to Task N". Every code step carries the actual text or code. The one thing deliberately left to execution time is the exact `name:`/`working-directory:` YAML shape in Task 1 step 14 — the instruction is to copy the adjacent step rather than invent one, because inventing CI YAML from memory is exactly the fabricated-precision failure this project's plan discipline names.

**3. Type/name consistency:** `emit_bytes()` is defined in Task 4 step 2 and used in steps 3, 4 and 7 under that one name. `check-cheatsheet-budget.ps1` takes `-Path`/`-MaxBytes` in step 10 and is called with exactly those in steps 11 and 15. The test name quoted in the Task 3 commit message (`extracts at least one message from every corpus hook that actually emits one`) matches the `It` string in step 1 verbatim.

**4. Ordering:** nothing depends on a later step. Task 0 stabilises the counts commit 1 writes; commit 2's test edit lands with the manifest fix it covers; commit 3's `coverage-debt.md` entries reference anchors created in commits 2 and 3; commit 4 is self-contained.

**5. Known residual risk.** The batch adds a CI step (Task 1 step 14). It is two one-line additions mirroring an adjacent step and the checker passes today with 1535 B of room (2561 B against 4096 B), but it is the one change in the batch whose first real exercise happens on the owner's machine at push time rather than here.

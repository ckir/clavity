# Open-work reconsideration — PHASE 1 (the sweep) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Disposition every recorded item on all **seven** tracking surfaces as CLOSED, KILLED or KEPT with
its oracle's output attached, then stop at the Phase-2 owner gate with two ruling requests.

🔴 **SEVEN, not the spec's six.** The seventh is `MEMORY.md`'s `PARKED` line (Task 7 Step 2b), found during
the round-2 panel and measured to hold five items that appear on **none** of the six. **This is the third
consecutive epic whose surface inventory was itself incomplete** — the last one missed the ROADMAPs and
found two stale entries within minutes of including them. **Treat "the inventory is complete" as the
claim most likely to be wrong.**

✅ **The plan/spec ARCHIVE (`docs/superpowers/`) is deliberately NOT a surface — decided, do not re-open.**
It is an **oracle**: consult it to decide whether an item shipped, and change nothing in it. Two reasons,
both measured 2026-08-06:
- **It has no usable progress signal.** Across 52 archived plans there are **~2,210 unchecked task boxes and
  ZERO checked ones.** The convention is written into every plan and ticked in none, so any sweep keyed on
  checkbox state would report every plan ever written as unfinished — including epics recorded GREEN in
  `docs/agy-capstone-ledger.md`.
- **Its surviving debt is promoted, and the mechanism is visible.** `clavity-dotnet/ROADMAP.md:452` exists
  *because* a fork in `specs/2026-07-22-ship-agy-disciplines-design.md:134` was *"orphaned rather than
  decided"* and was lifted onto a live surface *"so it stops being invisible."*

⚠️ **That promotion mechanism is not airtight, which is exactly why the seventh surface exists** — the same
superseded spec's `SP1` was never promoted anywhere and sits only on the PARKED line.

**Architecture:** Pure documentation work. One surface per task, each ending in its own commit, so a
surface swept is a surface banked. No executable code changes anywhere in this phase — that is what the
Task 9 scope gate proves.

**Tech Stack:** Markdown, YAML frontmatter, `git`, `rg`. No new tooling.

**Spec:** `docs/superpowers/specs/2026-08-06-open-work-reconsideration-design.md` (`e2ae944`,
AGY-AFTER GREEN at round 4 after 35 folds).

**🔴 PHASE 3 IS NOT IN THIS PLAN AND MUST NOT BE STARTED FROM IT.** Its line-level plan is gated on what
this sweep finds — items it may delete cannot be planned against. Phase 1 ends at Task 10.

---

## Read this before Task 1 — seven things that will bite you

**0. READ AN ITEM'S STATUS LINE BEFORE ITS EVIDENCE.** A section can carry pages of live-sounding text —
open questions, options with none chosen, "needs a consult first" — that its own status line marks as
**preserved historical record of work already shipped**. Quoting that text as current state is how you order
a finished item killed.

🔴 **This plan did exactly that to AT-2 and was caught in review** (Task 3 Step 3). It is the **third**
false disposition in this epic from one cause: **a grep hit whose enclosing section was never opened.** The
first two cost a retraction and then a retraction of the retraction. **Open the section. Read the status
line. Then read the evidence.**

**1. `<MEM>` is this path.** Shell state does not persist between tool calls in this harness, so re-export
it in every call that uses it:

```bash
export MEM="/c/Users/user/.claude/projects/C--Users-user-Development-Rust-clavity/memory"
ls "$MEM/MEMORY.md" && echo "MEM resolves"
```

**2. The oracle is three-way and GIT IS THE PRIMARY ONE.** Current code, then `git log`, then CHANGELOG.
Both stale entries found so far evaded a code-only grep, because a shipped item leaves a commit even after
its symbol is renamed or moved to another assembly.

⚠️ **`--grep` matches the roadmap's OWN commits.** `docs(roadmap): capture X` proves the item was
*recorded*, not that it shipped. **Open the commit and read it.**

⚠️ **A grep hit is not a verdict** — open the enclosing function and find the caller. Two false
dispositions were written in one day this way, both citing real line numbers.

**3. CHANGELOGs lagging is CORRECT, not stale.** All five stop at 2026-08-04 while ~100 commits sit
unpushed; release-please writes them at release time. **Never report that as a finding.**

**4. Record the oracle's OUTPUT, not its name.** Success criterion 2. A named oracle can point at the
wrong file and answer confidently — that is this epic's own evidence.

**5. NONE OF THIS IS IDEMPOTENT, and git is the tiebreak.** Every task appends or edits in place. On a
resumed run: **if memory says a surface is incomplete but its entries already carry dispositions in
committed files, the surface is DONE** — correct memory and move on. Never re-edit an entry that already
carries its disposition. A `git commit` that fails with "nothing to commit" on a resume is the healthy
outcome; confirm with `git log --oneline -5` and continue. Never reach for `--allow-empty`.

🔴 **The git tiebreak does NOT cover Surface 6.** Task 7's tracked-debt half lives in `<MEM>`, outside git,
so no commit can ever attest it. **For that surface only, the tiebreak is the file's own content** — read
`project_tracked-debt.md` and judge from the dispositions written in it. This is also why Surface 6 is swept
last (spec §8a): every surface that git *can* attest is banked before the one it cannot.

**6. Before resuming ANY task, check the working tree is clean** (`git status --short`). A crash can leave a
half-written edit uncommitted; resuming on top of it silently merges two tasks into one commit and defeats
the one-commit-per-surface staging. If it is dirty, identify which task wrote it before continuing.

---

## The disposition vocabulary (from spec §7b — do not invent a mapping)

| spec state | `fix-the-tool-backlog/` frontmatter | `ROADMAP.md` | `project_tracked-debt.md` |
|---|---|---|---|
| **CLOSED** | `status: fixed` + `fixed-by: <sha>` + `fixed-on: <the COMMIT's date>` | ✅ SHIPPED in place, with evidence | ✅ in place, keep the item |
| **KILLED** | `status: wont-fix` + `last-triaged: 2026-08-06` + the clause it failed | struck through in place, with the clause it failed | ✅ struck through in place, with the clause |
| **KEPT** | `status: open` + `last-triaged: 2026-08-06` | left as-is, ranked | left as-is |

**Four states the table cannot express, each with its rule:**
- **Partially-shipped multi-step item** → mark the shipped STEPS ✅ individually; leave the section open.
- **Owner-ruled at the §5 gate** → record the ruling AND its date, naming which question was answered.
- **`variant: both` fixed on ONE driver** → stays `status: open`, `last-triaged` names which driver is
  fixed and which is not. **Never `fixed` on one driver's evidence.**
- **Tracked-debt item** → no frontmatter; mark in place and **update the open/closed count at the top of
  the file in the same edit**.

⚠️ **A KILLED entry is the FIRST use of `wont-fix` in this repo** — no example exists to copy. It MUST
carry its reason inline.

🔴 **Marking anything `fixed` does NOT authorise touching the driver-cheatsheet rule** (`_template.md`).
Instead, record on the closed entry that its driver rule is now a **retirement CANDIDATE** and what the
remaining gate is.

---

## The bar (spec §2) — apply it, do not merely cite it

An item survives only if **all three** hold. Record all three in one line each.

1. **Lie / loss / crash** — absence causes silent data loss, a crash or hang, or an **active lie**: a
   diagnostic a competent operator would act on, whose action is wrong. **If you cannot name the wrong
   action the message induces, clause 1 is NOT met.**
2. **Unavoidable** — not neutralised by an existing invariant or an ordinary driving convention.
3. **Concrete bounded mechanism** — no unresolved design fork.

🔴 **Clause 1 is deliberately narrow.** Do NOT widen it to "a gate that measures the wrong thing lies" —
spec §7a records that this readmits every unbuilt validation harness, which is most of what clause 1
exists to reject.

---

## File structure

| File | Change | Task |
|---|---|---|
| `<MEM>/project_open-work-reconsideration.md` | base SHA + per-surface progress, updated as each lands | 0, all |
| `commonmemory/ROADMAP.md` | confirm COMPLETE (read-only unless wrong) | 1 |
| `clavity-classic/ROADMAP.md` | disposition 2 Follow-ups entries | 2 |
| `agy-autotrain/ROADMAP.md` | disposition AT-1 Part A, Part B, AT-2 | 3 |
| `clavity-dotnet/ROADMAP.md` | disposition §0–§11, Stretch, `# ghidrust` | 4, 5 |
| `agy-autotrain/docs/fix-the-tool-backlog/*.md` | disposition 6 open entries | 6 |
| `docs/backlog/`, `<MEM>/project_tracked-debt.md` | confirm + disposition 2 open debts | 7 |
| `<MEM>/MEMORY.md` (the `PARKED` line, **surface 7**) | disposition 5 parked items, none of which reach surfaces 1-6 | 7 |
| — | §-renumbering citation audit | 8 |
| — | final gates + the Phase-2 handover | 9, 10 |

---

## Task 0: Baseline and durable index

**Files:** `<MEM>/project_open-work-reconsideration.md`

- [ ] **Step 1: Confirm clean tree and record the base SHA**

```bash
git status --short && git rev-parse HEAD
```

Expected: no output from `status`, then a SHA.

🔴 **Write that SHA into `<MEM>/project_open-work-reconsideration.md` before doing anything else**, under
the EXECUTION STATE block, as `PHASE 1 BASE SHA`. Task 9's scope gate reads it back from there and **never
re-derives it from ambient HEAD** — a crash that loses it makes the gate diff nothing and report a clean
pass, which is the worst shape a failure can take.

🔴 **THIS WRITE IS CONDITIONAL — NEVER OVERWRITE AN EXISTING ONE.** Grep the index for `PHASE 1 BASE SHA`
first:

```bash
export MEM="/c/Users/user/.claude/projects/C--Users-user-Development-Rust-clavity/memory"
grep -n 'PHASE 1 BASE SHA' "$MEM/project_open-work-reconsideration.md" || echo "  ABSENT -> this is a fresh start, write it"
```

If it is already there, this is a **resumed** run: leave the recorded SHA exactly as it stands, confirm it
is an ancestor of HEAD (`git merge-base --is-ancestor <recorded> HEAD && echo ancestor-ok`), and skip to the
first unchecked surface. A successor that re-runs Task 0 and stamps the *current* mid-sweep HEAD as the base
silently shortens Task 9's diff to only the surfaces swept after the crash — every earlier surface then
passes the scope gate by being invisible to it. **That is the same false-clean shape the paragraph above
warns about, reached from the other direction.**

- [ ] **Step 2: Initialise the per-surface progress list**

Append to the same EXECUTION STATE block, verbatim:

```markdown
### Phase 1 surface progress (update the MOMENT a surface's commit lands)
- [ ] S4 commonmemory  - [ ] S2 classic  - [ ] S3 agy-autotrain  - [ ] S1a dotnet §0-§5
- [ ] S1b dotnet §6-§11+Stretch+ghidrust  - [ ] S5 fix-the-tool  - [ ] S6 backlog+debt (LAST)
- [ ] renumber audit  - [ ] final gates  - [ ] Phase-2 gate surfaced
```

- [ ] **Step 3: No suite baseline is taken, deliberately**

Phase 1 changes only `.md` files, so **Task 9's scope-gate arm 1 is a stronger and far cheaper proof than
a test count**: if every changed path ends in `.md`, no test file can have changed. `just test-scripts-fast`
costs 255–430s per run and would prove strictly less. **Do not run it in Phase 1.**

---

## Task 1: Surface 4 — `commonmemory/ROADMAP.md` (smallest first, proves the protocol)

**Files:** `commonmemory/ROADMAP.md` (read-only if the claim holds)

- [ ] **Step 1: Run the three-way oracle on its only claim**

```bash
sed -n '10,12p' commonmemory/ROADMAP.md
git log --oneline -3 -- commonmemory/
grep -n '^## ' commonmemory/CHANGELOG.md | head -3
```

Expected: `## ✅ STATUS: COMPLETE`, then *"T1 is **shipped**. No open items remain."*; the CHANGELOG's
newest entry is `## 0.3.0 — 2026-08-03`.

- [ ] **Step 2: Confirm there is genuinely nothing open**

```bash
grep -nE '^- \[ \]|TODO|▶|Forward backlog' commonmemory/ROADMAP.md || echo "  NO open markers -> surface CLEAN"
```

Expected: `NO open markers -> surface CLEAN`. **If anything prints, that item is a real find** — it means
a surface asserting "no open items remain" contains one, which is this epic's whole subject. Disposition it
against the bar before moving on.

🔴 **`open item` was removed from that alternation and must not go back.** It matched the file's own
sentence *"T1 is **shipped**. No open items remain."* (`commonmemory/ROADMAP.md:12`), so the clean-surface
echo could never fire and **the one surface expected to pass reported a find every time.** The remaining four
alternatives cover real open markers. **This is the same defect as Task 3 Step 2's probe: a check whose
matching text is the very sentence asserting the thing is fine.**

- [ ] **Step 3: Record and mark the surface swept**

No commit if nothing changed — that is the expected outcome here. Update the progress list in
`<MEM>/project_open-work-reconsideration.md`: `- [x] S4 commonmemory — CLEAN, no changes, nothing to commit`.

---

## Task 2: Surface 2 — `clavity-classic/ROADMAP.md` Follow-ups

**Files:** Modify `clavity-classic/ROADMAP.md`

Two entries, verified present 2026-08-06:

- [ ] **Step 1: Entry 1 — the DISCIPLINE EFFICACY pointer (line ~218)**

```bash
sed -n '218,235p' clavity-classic/ROADMAP.md
```

Expected: `### ▶ DISCIPLINE EFFICACY applies to THIS driver too — see clavity-dotnet/ROADMAP.md §0`, with
text stating the item is deliberately stated once, in the dotnet roadmap.

🔴 **This is a POINTER, not a duplicate item, and it is correct by design.** `MEMORY.md` records the
standing ruling: *never "restore parity" by copying the body here.* **Disposition: leave it exactly as is.**
Its status follows §0's Phase-2 ruling automatically. **Do not edit it and do not disposition it
separately** — if §0 is killed, this pointer is updated in Phase 3, not now.

- [ ] **Step 2: Entry 2 — the await-reply entry (line ~236)**

```bash
sed -n '236,244p' clavity-classic/ROADMAP.md
```

Expected: it already reads `· ✅ SHIPPED` with the four-citation evidence block, closed at `885905a`
during the pre-sweep. **Disposition: CLOSED, already done. No edit needed.**

- [ ] **Step 3: Verify no third entry exists**

```bash
sed -n '216,$p' clavity-classic/ROADMAP.md | grep -nE '^### '
```

Expected: exactly two `###` headings. **A third would be a find** — enumerate and disposition it.

- [ ] **Step 4: Update the index**

Likely no commit (both entries already correct). Mark `- [x] S2 classic — 1 pointer left as-is (owner
ruling), 1 already CLOSED at 885905a`.

---

## Task 3: Surface 3 — `agy-autotrain/ROADMAP.md`

**Files:** Modify `agy-autotrain/ROADMAP.md`

Three items, verified: **AT-2** (line 20), **AT-1 Part A** (line 140), **AT-1 Part B** (line 165).

- [ ] **Step 1: AT-1 Part B — run the oracle on the candidate KILL**

```bash
sed -n '11,16p'  agy-autotrain/ROADMAP.md   # the thin-plugin / no-binary-changes guardrail
sed -n '165,187p' agy-autotrain/ROADMAP.md  # Part B itself
git log --oneline --all --grep='project-local' --grep='learning tier' -i | head -5
```

Judge against the bar. The spec's expectation is **KILL**: Part B needs binary changes that the plugin's
own guardrail forbids, and project-local rules already live in a repo's `CLAUDE.md`. **Verify the
guardrail actually says that before killing on it** — if the guardrail text does not exist as described,
that is a find and the kill is unfounded.

If KILLED, strike the section through in place and record: which clause it failed, and the guardrail line
that decides it.

- [ ] **Step 2: AT-1 Part A — run the oracle**

```bash
sed -n '140,164p' agy-autotrain/ROADMAP.md
echo "== HALF 1: is there a LINE-density cap, distinct from the coarse 16 KB BYTE cap? =="
rg -in 'lines?[- ]density|density cap|max.*[0-9]+ lines|[0-9]+ lines (max|cap)|ordered breach' \
  agy-autotrain/skills/agy-curate/SKILL.md || echo "  ZERO -> no line-density cap shipped"
echo "== HALF 2: is there an explicit anti-poisoning gate? =="
rg -in 'anti-poison' agy-autotrain/skills/agy-curate/SKILL.md || echo "  ZERO -> no gate shipped"
git log --oneline --all -S'line-density' -- agy-autotrain/ | head -5
```

🔴 **DO NOT use `rg 'line-density|anti-poison|MaxBytes|16 ?KB|density'` as one probe.** Measured 2026-08-06:
`16 ?KB` matches `SKILL.md:191` and `:193`, which describe the **pre-existing byte cap this item is asking to
put something in FRONT of.** The probe therefore matches whether or not the feature shipped, and its
`|| echo "not shipped"` fallback can never fire. **A probe that cannot return the failing answer is not an
oracle.** Bare `density` has the same defect.

🔴 **AT-1 Part A IS TWO DELIVERABLES, and they measure differently. Judge them separately:**
- **Half 1 — the line-density cap plus ordered breach.** Measured: **ZERO matches. Not shipped.**
- **Half 2 — "a single explicit anti-poisoning gate".** Measured: `SKILL.md:250` already carries
  *"**Anti-poisoning circuit-breaker.** You (the curator) are the gate, not a transcriber…"*, which rejects
  unverified, over-general or one-off entries. **The roadmap's gap statement — "there is no single explicit
  anti-poisoning gate" — appears to be already satisfied, and by prose rather than by a mechanism.**

**Decide half 2 explicitly; do not assume either way.** If `:250` satisfies it, Part A is
**partially shipped** and the vocabulary table's rule applies: mark that step ✅ individually and leave the
section open on half 1 alone. If it does not — because Part A wants a *mechanical* gate and `:250` is an
instruction to a human curator — say so in one line and keep both halves open.

⚠️ **"Not shipped → KEPT" was this plan's original expectation and it is too coarse.** Ranking a
partially-shipped item as unstarted is the exact error this epic exists to remove; it is why §0 gets a
which-steps-shipped measurement in Task 4, and Part A earns the same treatment.

Record all three clause justifications for whatever remains open. Clause 1 is the **silent** GROWTH drop past
the byte cap — name the loss.

- [ ] **Step 3: AT-2 — it is ALREADY CLOSED. Confirm, and change nothing.**

```bash
sed -n '20,32p' agy-autotrain/ROADMAP.md
```

Expected: **`**Status:** ✅ **SHIPPED AND CLOSED 2026-08-02**`** — capstone GREEN over `6d79bee..a0b2d7b`,
deliverable `agy-autotrain/hooks/agy-inbox-snapshot.sh` shipped and registered with a 22-test suite.
**Disposition: CLOSED, already done. No edit needed** — same shape as Task 2 Step 2.

🔴 **AN EARLIER DRAFT OF THIS PLAN ORDERED AT-2 KILLED ON CLAUSE 3, AND THAT WAS WRONG.** It quoted
`agy-autotrain/ROADMAP.md:94` — *"Options to weigh (none chosen — this needs an AGY-FIRST consult before it
is specced)"* — as evidence of a live unresolved fork. **That line is real, and it is inside a section whose
own status line says the work shipped**, kept deliberately: *"everything from here down is the RECORD of
that, not an open question."*

**This is the third time in this epic that one cause produced a false disposition: a grep hit whose
enclosing section was never opened.** It is also the single worst outcome available to this sweep — an epic
whose purpose is finding items recorded as open but actually shipped, itself ordering a shipped item killed.
**Before dispositioning ANY item, read its status line first and its evidence second.**

⚠️ AT-2's heading *did* read "open, needs brainstorming" for four days after it closed, and the entry says so.
That is a real instance of this epic's base rate — **already corrected, so it is not a new find.**

- [ ] **Step 4: Commit**

```bash
git add agy-autotrain/ROADMAP.md
git commit -m "docs(roadmap): disposition agy-autotrain AT-1 and AT-2 against the bar"
```

Update the index immediately after the commit lands.

---

## Task 4: Surface 1a — `clavity-dotnet/ROADMAP.md` §0–§5

**Files:** Modify `clavity-dotnet/ROADMAP.md`

🔴 **NOTHING IS RENUMBERED, EVER.** §0 states renumbering invalidates every citation to §7 and §8. Close
in place with ✅.

- [ ] **Step 1: §0 — do NOT disposition it here**

§0 goes to the Phase-2 gate asking *"the bar rejects this on clause 1 — do you override?"* (spec §5).
**What Task 4 owes it is a MEASUREMENT, not a verdict:**

```bash
sed -n '177,200p' clavity-dotnet/ROADMAP.md    # THE SEQUENCE - OWNER-RATIFIED
rg -n 'agy-capstone\.head|agy-first\.head|contract stamp|CONTRACT-STAMP' clavity-dotnet/plugin/hooks/ docs/agy-disciplines-marker-contract.md 2>/dev/null | head
git log --oneline --all --grep='contract stamp' --grep='discipline-reaching' -i | head -8
```

**Record which of §0's steps have already shipped and which have not**, with the commit for each shipped
one. Spec §6 item 8 requires this: Phase 3 implements only the unshipped steps, and ranking a
partially-shipped item as unstarted is the error this epic exists to remove.

- [ ] **Step 2: §1 `--restart-agy` — oracle**

```bash
rg -n 'restart-agy|restart_agy' clavity-classic/src/ clavity-dotnet/src/ || echo "  NOT IMPLEMENTED"
git log --oneline --all --grep='restart-agy' -i | head -5
```

Verified 2026-08-06: not implemented, and no implementation commit. Judge against the bar. Clause 1 is the
question — name the wrong action induced, or it fails.

- [ ] **Step 3: §2, §3, §5 — confirm the ✅ SHIPPED claims are true**

```bash
sed -n '311,319p' clavity-dotnet/ROADMAP.md   # §2 golden-header tamper-detection
sed -n '320,328p' clavity-dotnet/ROADMAP.md   # §3 dynamic send-model
sed -n '335,345p' clavity-dotnet/ROADMAP.md   # §5 parity follow-ups
```

Each already claims SHIPPED with in-code citations. **Spot-check one citation per section against the
file it names.** A ✅ that cites a line which no longer says what it claims is exactly the defect class
this sweep hunts, and these were written before the audience split moved code around.

- [ ] **Step 4: §4 packaging verifications 7.5 / 7.6 — oracle**

```bash
sed -n '329,334p' clavity-dotnet/ROADMAP.md
rg -n 'ls-driving|ls-pairing' clavity-dotnet/plugin/.claude-plugin/*.json clavity-dotnet/plugin/skills/ 2>/dev/null | head
git log --oneline --all --grep='ls-driving' --grep='ls-pairing' -i | head -5
```

Both are "confirm X" tasks with no code deliverable. **Judge clause 1 strictly**: an unverified property
is not a false diagnostic. The spec's expectation is KILL, but **run the oracle before concluding it**.

- [ ] **Step 5: Commit**

```bash
git add clavity-dotnet/ROADMAP.md
git commit -m "docs(roadmap): disposition dotnet §0-§5; §0 measured for Phase 2, not ruled"
```

---

## Task 5: Surface 1b — `clavity-dotnet/ROADMAP.md` §6–§11, Stretch, `# ghidrust`

**Files:** Modify `clavity-dotnet/ROADMAP.md`

- [ ] **Step 1: §6 driver-side effectiveness measure**

```bash
sed -n '346,355p' clavity-dotnet/ROADMAP.md
```

🔴 **Two traps here, both already identified:**
- Its marking is **`Owner-surfaced`**, not owner-directed — clause (a) of the §5 test is NOT met, so §6
  does **not** reach the gate however large it looks (spec §2).
- It is the item that proved clause 1 must stay narrow (spec §7a): it asks for a verify-harness proving a
  delivered rule changes behaviour, which is §0's argument verbatim. **It therefore fails clause 1 for the
  same reason §0 does.** Disposition consistently with §0's clause-1 verdict or explain the difference.

- [ ] **Step 2: §7 — do NOT disposition it here**

§7 goes to the Phase-2 gate asking *"spec it, or kill it"*. Record its current state only:

```bash
sed -n '356,360p' clavity-dotnet/ROADMAP.md
```

Expected: `(BRAINSTORM FIRST)` and *"Status: brainstorming task, not yet designed. Owner-directed
2026-07-31."*

- [ ] **Step 3: §8 — CLOSE it, this one is decided**

```bash
sed -n '404,406p' clavity-dotnet/ROADMAP.md
grep -n 'cost/quota hygiene' docs/agy-capstone-ledger.md | cut -c1-140
```

Expected: §8 still reads *"Status: brainstorming task, not yet designed"* while the ledger carries
`c7b3923..8889473 (agy discipline cost/quota hygiene) | 4 | GREEN — owner-confirmed`.

**Mark §8 ✅ in place**, recording: which of its three levers the shipped epic answered, which remains, and
the capstone range as evidence. **Do not delete the section and do not renumber.**

- [ ] **Step 4: §9, §10, §11 — oracle each**

```bash
sed -n '450,457p' clavity-dotnet/ROADMAP.md   # §9 classic consult guard
sed -n '458,463p' clavity-dotnet/ROADMAP.md   # §10 productize follow-on
sed -n '464,508p' clavity-dotnet/ROADMAP.md   # §11 assertion-strength
git log --oneline --all --grep='assertion.strength' --grep='PINNING' -i | head -5
```

- **§9** carries an owner *disposition* (*"does NOT gate the productize release"*), not a directive — an
  ordinary item. It is an undecided fork → weigh clause 3.
- **§10** is packaging already-shipped disciplines into a release. Weigh clause 1 hard: name the wrong
  action its absence induces, or kill it.
- **§11** is **KEPT** — `df2b907` captured it and no implementation commit exists; its design is settled
  (*"Agreed shape … do not re-derive"*), so clause 3 passes, and clause 1 is met because a cardinality
  assertion prints PASS over reversed sort logic and induces a merge. Record all three clauses.

- [ ] **Step 5: Stretch and the `# ghidrust` section**

```bash
sed -n '509,514p' clavity-dotnet/ROADMAP.md   # Stretch: NativeAOT
sed -n '545,563p' clavity-dotnet/ROADMAP.md   # the ghidrust section
grep -n '"version"' ghidrust/plugin/plugin.json
grep -n '^## ' ghidrust/CHANGELOG.md | head -3
rg -n 'ghidrust' scripts/lib/release-lib.ps1 | head -3
```

- **NativeAOT** is already marked infeasible with its reason. Confirm it still reads as
  "not planned" and leave it; it is not an open item.
- ✅ **The ghidrust version question is RESOLVED — measured 2026-08-06 during the round-2 panel. It is a
  REAL find, and it is half of what it looked like.** The two channels are:
  - **Binary channel = `1.2.0`.** All three member crates carry `version = "1.2.0"`
    (`ghidrust/crates/{ghidrust-mcp,ghidra-ipc,ghidra-worker-ctl}/Cargo.toml:3`), and
    `ghidrust/CHANGELOG.md:2` is `## 1.2.0 — 2026-08-03`. **Consistent.**
    ⚠️ `ghidrust/Cargo.toml` is a **workspace** manifest and carries no package version — do not look for it
    there and conclude it is missing.
  - **Plugin channel = `1.0.0`** (`ghidrust/plugin/plugin.json:3`), which `release-lib.ps1:37-38` scopes to
    `ghidrust/plugin/**` only. **Consistent with itself.**

  🔴 **What is NOT consistent is the roadmap.** `clavity-dotnet/ROADMAP.md:550` heads the section
  **"## What ghidrust is now"** and `:551` then reads **"SHIPPED — v1.0.0."** while describing *both*
  channels ("Delivered two-channel: `ghidrust-setup-<VERSION>.exe` installs the binary→PATH; the plugin …
  ships via the marketplace"). A section stating what the product is **now** names a binary version two
  releases behind — `1.1.1` and `1.2.0` both shipped after it. **Disposition: update the stamp in place to
  name each channel's version separately.** This is an ordinary instance of the epic's own base rate, not a
  new class.

  ⚠️ **Neither panel reviewer resolved this** — both correctly noted the plan flagged it as a lead and left
  it there. **A lead is only closed by measuring it.**
- The v1.1 feature items (`import_binary`, smart-server onboarding, lazy-boot) are **new features, which
  spec §7 puts out of scope.** Disposition them — the spec's expectation is KILL as feature requests for a
  tool with no active development cycle here — but **do not build them.**

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/ROADMAP.md
git commit -m "docs(roadmap): disposition dotnet §6-§11, Stretch and ghidrust; close §8 as answered"
```

---

## Task 6: Surface 5 — `agy-autotrain/docs/fix-the-tool-backlog/`

**Files:** Modify frontmatter only, in `agy-autotrain/docs/fix-the-tool-backlog/`

🔴 **APPEND-ONLY.** `README.md:8`: *"One file per entry (append-only)."* **Never delete or move a file.**

- [ ] **Step 1: Re-derive the open set — do not trust this plan's list**

```bash
grep -l '^status: open' agy-autotrain/docs/fix-the-tool-backlog/*.md | grep -v '_template'
```

Expected, measured 2026-08-06 — exactly these six: `agy-look-tail-truncation`,
`conversation-scoped-tools-vs-no-open-conversation`, `grpc-default-max-message-size`,
`inbox-snapshot-misses-slash-command-path`, `stalled-reply-recoverable-not-lost`,
`working-vs-stuck-step-delta`.

**The `grep -v '_template'` is load-bearing:** `_template.md:6` is
`status: open        # open | fixed | wont-fix` and matches `^status: open` like a real entry. Drop it and
the command answers seven.

- [ ] **Step 2: All six were triaged hours ago — this task RE-JUDGES them against the bar, not the oracle**

Each already carries `last-triaged: 2026-08-06` with its oracle's output. **Do not re-run those oracles.**
What was never done is applying the bar:

```bash
grep -A1 '^status: open' agy-autotrain/docs/fix-the-tool-backlog/*.md | grep 'last-triaged'
```

⚠️ **Do NOT add `-h`.** It suppresses the filename, and the output is then six `last-triaged:` lines with
nothing saying which entry each belongs to — useless for a task whose whole job is a per-entry judgment.

For each, add the three clause justifications to the `last-triaged` comment, or kill it. Expected per the
spec: five are KEPT (ranks 1–5), and **`working-vs-stuck-step-delta` is the KILL candidate** — the peer
argued it is subsumed by `stalled-reply-recoverable-not-lost`. **Verify the subsumption by reading both
entries before killing**, and if killed, use `status: wont-fix` with the reason inline.

- [ ] **Step 3: Rewrite the falsified reproduction**

🔴 `grpc-default-max-message-size.md`'s **Steps to Reproduce are FALSIFIED.** It says drive past *"roughly
1100 steps"* and *"Every call fails."* Measured 2026-08-06: four round-trips succeeded at **996, 1111,
1203 and 1290 steps**.

Rewrite that section in **byte** terms: the cap is gRPC's default 4 MB receive size (`LsChannel.cs` sets
no `MaxReceiveMessageSize`, and `git log -S` shows it never has), so the trigger is trajectory payload
size, not step count — a session with large tool outputs crosses it in far fewer steps. **Keep the entry
`open`; only the repro changes.**

- [ ] **Step 4: Verify every entry is dispositioned — watch it FAIL first**

```bash
grep -L -e 'last-triaged' -e 'fixed-by' agy-autotrain/docs/fix-the-tool-backlog/*.md | grep -vE 'README|_template|DRY-RUN'
```

Expected AFTER: no output. **All six already carry `last-triaged` from the earlier triage, so this will
pass immediately — which makes it a WEAK control here.** The real check for this task is that every open
entry's comment now contains its three clause justifications:

```bash
grep -c 'clause' \
  agy-autotrain/docs/fix-the-tool-backlog/agy-look-tail-truncation.md \
  agy-autotrain/docs/fix-the-tool-backlog/conversation-scoped-tools-vs-no-open-conversation.md \
  agy-autotrain/docs/fix-the-tool-backlog/grpc-default-max-message-size.md \
  agy-autotrain/docs/fix-the-tool-backlog/inbox-snapshot-misses-slash-command-path.md \
  agy-autotrain/docs/fix-the-tool-backlog/stalled-reply-recoverable-not-lost.md \
  agy-autotrain/docs/fix-the-tool-backlog/working-vs-stuck-step-delta.md
```

**Name the six files; do NOT use the `*.md` glob.** The glob prints all eleven files in the directory, and
five of them — `README`, `_template`, `DRY-RUN-2026-07-11`, and the two already-closed entries — stay at `0`
legitimately forever. An executor comparing that output against "non-zero on each" reads five correct zeros
as five failures, and the usual resolution of that confusion is to stop trusting the check.

✅ **This one has a real red baseline, measured 2026-08-06 at `5c1bbdd`: all six are `0` today.** So the
control genuinely fails before the work and can only pass because of it — which is exactly what Step 4's
first command cannot claim.

Expected AFTER: a non-zero count on each of the six.

- [ ] **Step 5: Commit**

```bash
git add agy-autotrain/docs/fix-the-tool-backlog/
git commit -m "docs(backlog): apply the bar to the six open entries; rewrite the falsified grpc repro"
```

---

## Task 7: Surfaces 6 AND 7 — `docs/backlog/`, tracked debt, and the PARKED line (LAST, per spec §8a)

**Files:** `docs/backlog/`, `<MEM>/project_tracked-debt.md`, `<MEM>/MEMORY.md`

🔴 **Swept LAST deliberately:** the tracked-debt half lives in memory, outside git, so it cannot end in a
commit and the commit-is-truth tiebreak does not apply to it. Every git-backed surface is banked first.

- [ ] **Step 1: `docs/backlog/` — confirm**

```bash
ls docs/backlog/
grep -n '^\*\*Status:' docs/backlog/*.md
```

Expected: one file, `golden-header-per-ask-token-optimization.md`, already
`✅ RESOLVED / OBSOLETE — closed 2026-08-06`. **Disposition: CLOSED, already done.** If a second file
exists, it was never in any inventory — disposition it against the bar and say so loudly.

- [ ] **Step 2: Tracked debt — the two open items**

```bash
export MEM="/c/Users/user/.claude/projects/C--Users-user-Development-Rust-clavity/memory"
sed -n '19,26p'  "$MEM/project_tracked-debt.md"   # the count line + item 1
sed -n '59,66p'  "$MEM/project_tracked-debt.md"   # item 4
```

Verified: items **1** and **4** are OPEN; 2 and 3 are RESOLVED by the pre-release sweep.

- **#1 — seven ECC hooks cost ~33s per tool call.** 🔴 **It is NOT clavity's code.** Judge clause 2
  honestly: it is a real daily tax, but it is another plugin's. **The spec gives no authority to change a
  third-party plugin**, so the only dispositions available are KEPT-as-owner-decision or KILLED as
  out-of-scope. **If it needs an owner decision, that is a THIRD gate question — STOP and report it
  rather than inventing a disposition.**
- **#4 — `docs-audit` claim counts unstable across runs.** Already documented in `docs-audit.ps1`'s own
  `.NOTES` as measured behaviour. Judge whether anything is left to do beyond what is documented.

- [ ] **Step 2b: `MEMORY.md`'s PARKED line — a SEVENTH surface the spec's six-surface table missed**

```bash
export MEM="/c/Users/user/.claude/projects/C--Users-user-Development-Rust-clavity/memory"
grep -n 'PARKED (do NOT start' "$MEM/MEMORY.md"
```

Expected: **line 57**, reading *"**PARKED (do NOT start until the owner says):** ship-agy-disciplines SP1 ·
Phase-2 A2 hook-vs-gate · ME2 banner-injector · 2 stale pre-monorepo specs · the deferred papercut list."*

🔴 **Measured 2026-08-06: ZERO of those five items appear on ANY of the six enumerated surfaces.** They are
tracked in exactly one place — that line. **It is a parking lot, which the triage runbook §8 names as the
failure mode a tracking system must not have**, and it is the third consecutive epic in which an inventory
of surfaces turned out to be missing a surface. **Disposition all five against the bar, here.**

🔴 **DO NOT COPY THE DISPOSITIONS A REVIEWER OFFERS FOR THESE — two were checked and two were wrong:**
- *"the deferred papercut list is a phantom phrase with no enumerated items → KILL"* is **FALSE.**
  `project_docs-rationalize.md:459` and `:691` name two specific deferred papercuts (a prompt file that is
  functionally code; `just --list` rendering a mangled description). **The list is real and has members.**
- *"ME2 banner-injector shipped in dotnet"* has **no supporting evidence** — `banner.injector` matches
  **only** that MEMORY.md line, repo-wide and memory-wide. An item with no backing document cannot be
  dispositioned from its name; **find what it referred to, or record that it is unresolvable and say so.**

⚠️ **`ship-agy-disciplines SP1` is NOT the same item as dotnet §9.** §9 is that spec's *ME1* consult guard,
already promoted (`clavity-dotnet/ROADMAP.md:452`). SP1 is a different sub-task from the same superseded
spec. **Check them separately.**

- [ ] **Step 3: Update the file's own count in the same edit**

Whatever changes, the *"Items 1 and 4 remain OPEN"* line near the top must change with it. **A file that
miscounts itself is the exact defect this epic exists to remove**, and this one states its count in prose.

- [ ] **Step 4: Update the index** — memory-only surface, no commit. Mark `- [x] S6`.

---

## Task 8: The §-renumbering citation audit

**Files:** none unless a broken citation is found.

- [ ] **Step 1: Establish what `252f63c` renumbered**

```bash
git show --stat 252f63c | head -20
git show 252f63c -- ROADMAP.md | grep -E '^[+-]### [0-9]'
```

Verified: its message is *"docs(roadmap): mark §1 clavity-classic installer SHIPPED (v0.1.0) + renumber
backlog"*. **Establish the old→new mapping from the diff itself.**

🔴 **The path is `ROADMAP.md`, NOT `clavity-dotnet/ROADMAP.md` — the roadmap was at the repository ROOT when
`252f63c` was written, and moved during the monorepo consolidation.** Measured:
`git cat-file -e 252f63c:clavity-dotnet/ROADMAP.md` → *"fatal: path … exists on disk, but not in
'252f63c'"*, while the root path resolves and the corrected command yields **11** heading lines.

⚠️ **This is a trap the whole plan is built to catch, and it caught the plan.** A pathspec naming today's
location silently returns an **empty diff** for a historical commit — no error, no warning — so the audit
would have concluded "nothing was renumbered" and passed. **When a command reads history, verify the path
existed at that commit** (`git cat-file -e <sha>:<path>`), because a moved file makes an empty result
indistinguishable from a clean one.

- [ ] **Step 2: Find every §-citation in the repo and in memory**

```bash
export MEM="/c/Users/user/.claude/projects/C--Users-user-Development-Rust-clavity/memory"
mkdir -p .clavity/scratch/open-work-phase1
rg --no-ignore --hidden -n '§[0-9]+' --glob '*.md' --glob '!.git/**' . 2>/dev/null \
  | grep -v 'ROADMAP.md:' > .clavity/scratch/open-work-phase1/cites-repo.txt
rg -n '§[0-9]+' "$MEM" > .clavity/scratch/open-work-phase1/cites-mem.txt
wc -l .clavity/scratch/open-work-phase1/cites-*.txt
```

**BOTH flags are mandatory, for two DIFFERENT reasons — measured 2026-08-06:**
- `--no-ignore` reaches `docs/superpowers/`, which is gitignored (`.gitignore:32-34`).
- `--hidden` reaches `.clavity/`, which is a **dot-directory**. ripgrep skips hidden paths by *default*,
  independently of gitignore, so `--no-ignore` alone does **not** see it: measured **1** hit versus **180**
  with `--hidden` added. The two flags are not interchangeable and neither substitutes for the other.
- The memory arm needs neither, because a path given to `rg` **explicitly** is searched even though
  `.claude/` is hidden (measured: 134 hits).

🔴 **DO NOT PIPE EITHER ARM THROUGH `head`.** The repo arm matched **569 lines** when measured, so a
`head -40` shows 7% of the corpus and hides the rest behind an output that looks complete. **That is
precisely the failure Step 4 and success criterion 3 exist to forbid** — an audit that silently covers a
fraction of its subject and reports a clean pass. Write both arms to files, review them in full, and state
the counts in the commit message.

- [ ] **Step 3: Narrow the corpus by a STATED rule, then date each survivor by its commit**

Measured 2026-08-06 at `5c1bbdd`: **632 repo lines + 101 memory lines = 733**. Most are citations to *spec*
sections (`spec §5`, `§7a`) which no roadmap renumber can affect. **Narrow it — but state the rule in the
commit message, because a narrowing you do not declare is the same silent cap as a `head`:**

```bash
cd .clavity/scratch/open-work-phase1
grep -iE 'roadmap|backlog' cites-repo.txt cites-mem.txt > cites-inscope.txt
wc -l cites-inscope.txt
grep -ivE 'roadmap|backlog' cites-repo.txt cites-mem.txt | wc -l   # the OUT-of-scope count, to report
```

**Report both numbers.** "Audited N of 733, excluded M because they cite spec sections, not roadmap
sections" is a result. "Audited 40" is not.

Then, for each in-scope citation, **date it by the commit that introduced it** — a bare `§7` carries no
year, but the commit that wrote it does:

```bash
git log -1 --format='%h %ad %s' --date=short -S'<the exact citation text>' -- <the file>
```

🔴 **Read the commit's DESCRIPTION, not just its date.** A message like
*"docs(roadmap): mark §1 clavity-classic installer SHIPPED (v0.1.0) + renumber backlog"* names the section
by **title as well as number**, which is exactly the disambiguation the citation itself lacks. If the
description names a title that no longer matches the number, the citation has drifted and you have the
evidence in one line. If the introducing commit **postdates `252f63c`**, the citation was written against
today's numbering and needs no repair — record that and move on.

⚠️ For a citation in `<MEM>` there is no commit to read: memory is outside git. Date those by content
against the roadmap as it stands today.

**Repair by RE-ANCHORING, never by renumbering:** rewrite the citation to name the section's TITLE as well
as its number (e.g. `§7 AGY-SCOPE`). **Never renumber the sections to match the citation.** A
title-anchored citation degrades to ambiguous rather than to silently wrong on the next renumber.

- [ ] **Step 4: State the result either way**

🔴 **If no broken citation exists, say so explicitly in the commit message,** together with the corpus size,
the in-scope count and the exclusion rule. A silent pass here is indistinguishable from an audit that never
ran — success criterion 3.

```bash
git add <each repaired file, named explicitly> && git commit -F - <<'EOF'
docs: re-anchor §-citations broken by the 252f63c renumber

Corpus 733 (632 repo + 101 memory). In scope N, excluded M as spec-section
citations unaffected by a roadmap renumber. Repaired: <files, or "none - null result">.
EOF
```

🔴 **Never `git add -A docs/` here.** Task 8's own header says it changes no file unless a broken citation
is found, so there is nothing a wildcard can add that naming the files would not. `git add -A` has twice
swept an unintended file into a commit on this **public** repo — name every path.

⚠️ **If nothing changed, there is nothing to commit and that is correct.** Do not force a commit; record the
null result in the index and in Task 10's report.

---

## Task 9: Final gates

- [ ] **Step 1: The scope gate — both arms, base SHA read from the index**

```bash
BASE=<the PHASE 1 BASE SHA from the memory index, NOT ambient HEAD>

echo "== ARM 0 (POSITIVE CONTROL): the diff must NOT be empty =="
git diff --name-only $BASE..HEAD | wc -l
echo "== ARM 0b: the working tree must be clean =="
git status --porcelain

echo "== ARM 1: paths that are not .md (must print nothing) =="
git diff --name-only $BASE..HEAD | grep -v '\.md$'
echo "== ARM 2: .md paths that are MECHANISM, not documentation (must print nothing) =="
git diff --name-only $BASE..HEAD \
  | grep -E '(^|/)(skills|agy_skills|knowledge|hooks|rules)/|(^|/)SKILL\.md$|(^|/)(CLAUDE|GEMINI|AGENTS)\.md$'
```

Arms 1 and 2 empty = scope held, and **arm 1 empty also discharges success criterion 8** (no test file
changed, so no count can have moved). Anything printed = name the file to the owner rather than judging it
harmless.

🔴 **ARM 0 IS NOT OPTIONAL — arms 1 and 2 are `grep`s over a diff, and an EMPTY diff satisfies both.** A
wrong `BASE` (lost, mis-copied, or re-stamped by a resumed Task 0) makes this gate print two clean arms
while having examined nothing. **The count must be non-zero and must be at least as large as the number of
surfaces that produced a commit.** If it is zero, the gate did not pass — it did not run.

🔴 **ARM 0b closes the other half:** arms 1 and 2 read *committed* history only, so an uncommitted or
untracked non-`.md` edit sitting in the working tree is invisible to both. `git status --porcelain` must be
silent, or the gate is reasoning about a tree that is not the one on disk.

🔴 **`CLAUDE.md` is MECHANISM, not documentation** — measured 2026-08-06: four exist
(`./CLAUDE.md`, `clavity-classic/`, `clavity-dotnet/`, `ghidrust/`), and every one is binding instruction to
an agent. Under the original arm 2 an edit to any of them passed **both** arms silently: they end in `.md`
and they sit in no `skills/`-class directory. `GEMINI.md` and `AGENTS.md` are in the pattern because the
same rule applies to them the moment one appears.

⚠️ **No segment is anchored to `plugin/`, deliberately** — three of this repo's four skill roots carry no
`plugin/` segment, and a `plugin/`-anchored gate cannot see `agy-autotrain/knowledge/driver-cheatsheet.core.md`.
⚠️ **Do not "improve" arm 2 with a negative lookahead.** `grep -E` is POSIX ERE; a `(?!…)` pattern does not
error, it silently matches nothing.

- [ ] **Step 2: Line endings — judge what is COMMITTED**

```bash
python3 -c "
import subprocess
BASE='<the PHASE 1 BASE SHA>'
fs=subprocess.run(['git','diff','--name-only',BASE+'..HEAD'],capture_output=True,text=True).stdout.split()
assert fs, 'EMPTY DIFF - wrong BASE, this check examined nothing'
for f in fs:
    r=subprocess.run(['git','show','HEAD:'+f],capture_output=True)
    if r.returncode != 0:
        print('UNREADABLE', f, '<-- deleted in range, or bad path; NOT a pass'); continue
    d=r.stdout
    crlf=d.count(b'\r\n'); lf=d.count(b'\n')-crlf
    print(('CRLF' if crlf and not lf else ('MIXED' if crlf else 'LF')), f)"
```

Expected: every file `LF`, and no `UNREADABLE`. With `core.autocrlf` the working tree is legitimately CRLF
— **never "normalize" a clean file.**

🔴 **The `returncode` check and the `assert` are both load-bearing, and the original had neither.**
Measured 2026-08-06: `git show HEAD:<path that does not exist>` returns **zero bytes on stdout**, so the
counters see `crlf=0, lf=0` and the expression falls through to print **`LF`** — a clean verdict on a file
it never read. A file deleted anywhere in the range would therefore be reported as passing. Filtering
deletions out with `--diff-filter=d` hides that case but still cannot distinguish an unreadable file from a
legitimately empty one; **checking the exit code catches both, and every other read failure besides.**

- [ ] **Step 3: The disposition evidence**

```bash
git diff $BASE..HEAD -- agy-autotrain/docs/fix-the-tool-backlog/ | grep -E '^[+-](status|last-triaged|fixed-by|fixed-on)'
git diff $BASE..HEAD -- '*ROADMAP.md' | grep -E '^\+.*(✅|~~|wont-fix|KILLED|clause)'
```

**These hunks are the evidence that no item was left correct-but-unmarked.** A checkbox is not.

✅ **`'*ROADMAP.md'` is CORRECT as written — do not "fix" it to `'**/ROADMAP.md'`.** A round-1 panel finding
claimed the single star cannot cross a directory separator and that this pathspec therefore matches none of
the four roadmaps. **Refuted by measurement 2026-08-06:**
`git diff --name-only 885905a~1..HEAD -- '*ROADMAP.md'` printed `clavity-classic/ROADMAP.md`. Git pathspec
globbing is `fnmatch` **without** `FNM_PATHNAME`, so `*` matches `/` — this is exactly why the pattern needs
no directory prefix, and adding one would instead stop it matching a roadmap at the repository root.

⚠️ **Count the ROADMAP hunks against the number of items you dispositioned.** If a surface produced fewer
hunks than items, an item was silently skipped — that is the failure mode this command exists to catch,
and an earlier epic's version of it under-reported by one and read as a clean pass.

- [ ] **Step 4: Anomalies file unchanged in count by this epic**

```bash
if [ -f .clavity/local-anomalies.md ]; then
  grep -c '^- \[' .clavity/local-anomalies.md
else
  echo "0 (file absent)"
fi
```

Any entries added during the sweep are legitimate captures. **Report the count; do not triage them here** —
that is `open-issues`' job with its own two-outcome procedure.

⚠️ **`grep -c … || echo 0` prints `0` TWICE** — measured 2026-08-06. `grep -c` exits **1** on a genuine
zero-count, so the fallback fires on top of the `0` that `-c` already printed, and the two cases the
fallback exists to distinguish — *file present with no entries* and *file missing* — become
indistinguishable.

🔴 **`test -f X && grep -c … || echo …` DOES NOT FIX IT — measured, it still double-prints.** The `||` binds
to the whole `&&` chain, so `grep`'s exit-1 still triggers the fallback. **An explicit `if`/`else` is the
only shape that works here**, because it is the only one in which `grep`'s exit code is not a control-flow
signal. *(This correction was itself caught by re-running the probe after fixing it — which is the entire
argument for running a fix rather than reading it.)*

---

## Task 10: The Phase-2 gate — stop and surface BOTH questions

🔴 **This is where Phase 1 ends. Do NOT continue into Phase 3.**

- [ ] **Step 1: Write both ruling requests into the index as the ▶ resume point**

In `<MEM>/project_open-work-reconsideration.md`, replace the resume point with both questions and the
evidence each needs.

- [ ] **Step 2: Surface both to the owner in chat, with evidence**

**Two questions, not one — conflating them is the error §5 exists to prevent:**

1. **§7 AGY-SCOPE — spec it, or kill it?** Attach: its current text, and whether the sweep found any
   mechanism for it anywhere.
2. **§0 DISCIPLINE EFFICACY — the bar rejects this on clause 1; do you override?** Attach: Task 4 Step 1's
   measurement of which steps already shipped, the clause-1 argument from spec §7a, and the note that
   widening clause 1 to admit it also readmits §6 and §4.

🔴 **If Task 7 Step 2 produced a third gate question** (tracked debt #1 needing an owner decision),
surface that too, clearly marked as a third and separate question.

- [ ] **Step 3: Report the full sweep result**

State plainly: how many items were CLOSED, KILLED, KEPT; which surfaces produced stale entries; the
§-renumber audit's result **including a null result**; and both scope-gate arms verbatim.

- [ ] **Step 4: Do not guess either ruling, and do not proceed**

**Phase 3's plan is written only after these rulings land**, because the rulings change what is in it.

---

## Self-review

**Spec coverage.** §1 base rate → the traps preamble. §2 bar → the bar section, applied in every task. §3
oracle → Task preamble item 2 and every Step. §4 surfaces 1–6 → Tasks 1, 2, 3, 4, 5, 6, 7. §5 gate →
Task 10. §7a clause-1 narrowness → Task 5 Step 1 and Task 4 Step 1. §7b vocabulary → the vocabulary table.
§8 criteria: 1 → all tasks; 2 → "record the OUTPUT" in the preamble; 3 → Task 8 Step 4; 4 → Task 10;
5 → Phase 3, out of scope here; 6 → Task 6 Step 3; 7 → Task 9 Step 1; 8 → Task 9 Step 1 arm 1, which
discharges it more cheaply than a suite run. §8a staging → one commit per surface, S6 last. §8b lifecycle →
the cheatsheet retirement-candidate rule and the anomaly-routing note.

**Placeholders.** One deliberate: `<the PHASE 1 BASE SHA>` in Tasks 9's commands, filled at Task 0 by
definition and read back from the index rather than re-derived. No others.

**Consistency.** `last-triaged: 2026-08-06` is the single stamp format. `<MEM>` is the memory directory
throughout. Surface numbering matches the spec's table exactly (S1 split into 1a/1b for commit size only).

**Known gaps, each with where it is resolved:**
- **Whether AT-2, §9 and §10 are KEPT or KILLED** is not pre-decided — the plan names the oracle and the
  bar and requires the executor to run them. Pre-deciding would be the fabricated precision the plan
  discipline forbids.
- **The ghidrust two-channel version question** is explicitly a lead, resolved in Task 5 Step 5.
- **Tracked debt #1's disposition** may become a third gate question — Task 7 Step 2 says to stop and
  report rather than invent one.
- **Phase 3's ordering** is provisional in the spec and is re-derived after this sweep, not here.

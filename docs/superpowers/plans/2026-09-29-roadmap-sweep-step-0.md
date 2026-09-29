# ROADMAP Sweep - Step 0 (triage pass) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking.

**Goal:** Execute Step 0 of `docs/superpowers/specs/2026-09-29-roadmap-sweep-sequence-design.md`: the
no-code triage pass - close two stale headers, merge the §51 duplicate, repair the NUL-corrupted test-audit
ledger, and collect and record the owner's rulings - so Branch 1 can start from a clean, fully-ruled backlog.

**Architecture:** Documentation and ledger edits only; no source, test or hook changes, so no capstone and no
test audit (the spec's "Step 0 - triage pass (no code, no capstone)"). Four commits on `main`, explicit paths
only. The owner owns every push.

**Tech Stack:** Markdown, git, node (for byte-exact edits), `just` / `lefthook` gates.

**Base:** `main` at `b0e03801` (= `origin/main`). All line numbers below were measured at that sha on
2026-09-29. Task 0 re-verifies them; on any mismatch STOP and report `STATE_MISMATCH: <what>`.

**Deviation from the spec, deliberate:** the spec says "merge the §51 backlog duplicate into §51 and delete
the stub". The stub is NOT deleted: `git grep` shows its path cited by three dated artifacts
(`docs/superpowers/plans/2026-09-06-s27-marker-write-gate.md:885,927,956`,
`docs/superpowers/specs/2026-08-31-roadmap-implementation-sequence-design.md:460`,
`docs/superpowers/specs/2026-09-03-marker-write-gate-design.md:162,424`), and it holds a design answer §51
lacks. It is marked MERGED instead (Task 2).

**Execution model (owner-chosen 2026-09-29: one fresh subagent per mechanical task).** Dispatch units:
- **Unit A = Tasks 0 + 1 + 2** (ONE subagent: Task 1 has no commit of its own - it is committed by Task 2
  Step 4 - so splitting them would leave Task 1's uncommitted edits for the next subagent's Resuming check
  to misread as a half-done Task 2).
- **Unit B = Task 3.** **Unit D = Task 6.** **Unit E = Task 7 Step 1 only.**
- **Tasks 4 and 5 stay in the DRIVING session** (they are the owner dialogue and the recording of it).
- Every dispatch prompt carries: the task text verbatim; the owner's rulings it depends on, verbatim (Unit D
  gets the §38 ruling; no other unit depends on a ruling); the FILES list it may touch; and the rule that
  the subagent does NOT write the execution index. Every "Update the execution index" step in this plan is
  performed by the DRIVER after the unit returns, from the sha the subagent reports. Task 7 Steps 2-3
  (choosing ▶ NEXT, telling the owner) are the driver's.
- After each unit returns, the driver checks both axes before the next dispatch:
  `git status --short` and `git log --stat <sha-before>..HEAD`, against the unit's FILES list.

**Shell:** every command block in this plan is for the Bash tool (Git Bash), not PowerShell.

**The execution index** is the driving session's durable execution-status record, defined in the spec
("The execution index"). Only the DRIVING session writes it: a subagent executing a task reports its
commit sha and any ruling in its final message, and the driver records them. An executor that has no
execution index STOPS and asks rather than creating a file of its own.

**Resuming (power failure / new session):** before starting ANY task, run
`git log --oneline b0e03801..HEAD` and compare it with each task's commit subject:
Task 2 `docs(roadmap): close stale §15/§14f headers`, Task 3 `fix(docs): restore two backslash escapes`,
Task 5 `docs(roadmap): record the owner's step-0 rulings`, Task 6 `docs: publish the ROADMAP sweep spec`.
A task whose commit exists is DONE - do only its "update the execution index" step, never its edits
again. A task with uncommitted changes in `git status` is HALF-DONE - inspect `git diff`, finish or
`git restore` it, never apply its edits on top. Task 5 is additionally guarded: every ruling it writes
(header, Status line or ledger row) carries the literal tag `[sweep-step0 2026-09-29]`; before appending,
run `grep -cF '[sweep-step0 2026-09-29]'` on that one line (or, for a ledger row, on the ledger for that
range) and skip it if the count is not 0.

**Writing the scratch scripts:** create every `.js` / `.sh` file in this plan with the Write tool, never
a Bash heredoc. MEASURED 2026-09-29: a heredoc in this agent's shell layer collapsed `'\\u0000'` to
`'\u0000'`, so a repair script written that way writes a NUL back - the very defect Task 3 repairs.
`repair.js` therefore guards itself (exit 4 if any replacement string contains a control byte, i.e. the
script was mangled when written), and every check below reads bytes through a script file, not through a
shell one-liner that could be mangled the same way.

**Before EVERY commit in this plan:** run `git diff --cached --numstat` and `git ls-files --eol clavity-dotnet/ROADMAP.md`.
Each changed file must show only the insertions/deletions its task describes, and ROADMAP must stay `i/lf`.
A whole-file count (e.g. 3500 deletions) means the line endings were rewritten: `git restore --staged` and
`git restore` that file, redo the edit with the Edit tool.

**Line endings:** `clavity-dotnet/ROADMAP.md` is CRLF in the working copy and LF in the index
(`git ls-files --eol`: `i/lf w/crlf`). Edit it with the Edit tool, which preserves the working copy's line
endings; judge the result by `git diff`, never by the working copy.

---

### Task 0: Verify state

**Files:** none modified.

- [ ] **Step 1: Confirm the base and a clean tree**

Run: `git rev-parse --short HEAD; git status --short`
Expected: `b0e03801`, no modified or staged tracked file, and only the owner's own pre-existing untracked
entries (`??` lines the owner has not asked to be touched). Record that `??` list; any other line: STOP.

- [ ] **Step 2: Confirm every anchor this plan edits**

Write `.clavity/scratch/sweep-step0/anchors.sh` (fixed-string line checks; `cut -c` counts BYTES here and
splits `§` / `—`, so it is not used; `-a` because the NUL makes grep treat the ledger as binary):

```bash
# Each row: expected line | file | fixed string that must START that line. Prints OK or MISMATCH per row.
R=clavity-dotnet/ROADMAP.md
bad=0
chk() { got=$(grep -anF -- "$3" "$2" | grep -m1 "^$1:" | cut -d: -f1); if [ "$got" = "$1" ]; then echo "OK $2:$1"; else echo "MISMATCH $2:$1 <- $3"; bad=1; fi; }
chk 1295 $R '### §15 — Workflow-position resilience'
chk 1087 $R '**§14f — two shipped artifacts disagree'
chk 1088 $R '· ✅ **RULED 2026-08-19**'
chk 1137 $R 'has never run.**'
chk 3312 $R '### §49 — No gate catches control characters'
chk 3325 $R '**Blast radius:** a new check in a docs gate'
chk 3344 $R '### §51 — `agy-mark.sh head` writes a marker'
chk 3358 $R '---'
chk 2836 $R '### §35 — Persist every peer reply'
chk 2891 $R '### §36 — Orphaned tests'
chk 3063 $R '### §38 — The `.gitignore` prose'
chk 3153 $R '### §41 — The shield'
chk 45 docs/agy-capstone-ledger.md '| 2026-09-14 | `356760b..669547c`'
chk 44 docs/agy-test-audit-ledger.md '| 2026-09-14 | `356760b..ad00fa4`'
chk 3 docs/backlog/agy-mark-accepts-a-nonexistent-sha.md '**Status:** OPEN. Promoted 2026-08-31'
chk 23 .gitignore '# DEFAULT-DENY with opt-IN exceptions.'
chk 38 .gitignore '# Implementation plans — same DEFAULT-DENY opt-IN discipline'
echo "bad=$bad"; exit $bad
```

Run: `bash .clavity/scratch/sweep-step0/anchors.sh` -> 17 `OK` lines and `bad=0`, exit 0 (measured at
`b0e03801`, 2026-09-29). Any `MISMATCH`: STOP, `STATE_MISMATCH: <the line>`.

---

### Task 1: Close the two stale headers (§15, §14f)

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md:1295` (§15 header)
- Modify: `clavity-dotnet/ROADMAP.md:1088` (§14f header, second line)

- [ ] **Step 1: §15.** On line 1295 replace this exact text:

```text
✅ **IMPLEMENTED 2026-09-13** (pending post-implementation AGY-CAPSTONE)
```

with this exact text:

```text
✅ **SHIPPED — AGY-CAPSTONE GREEN 2026-09-14 over `356760b..669547c` (`docs/agy-capstone-ledger.md` row 45) + AGY-TEST-AUDIT over `356760b..ad00fa4` (`docs/agy-test-audit-ledger.md` row 44). Header closed 2026-09-29 (it read "pending" for 15 days after both ran).**
```

- [ ] **Step 2: §14f.** On line 1088 replace this exact text:

```text
· ✅ **RULED 2026-08-19**
```

with this exact text:

```text
· ✅ **RULED 2026-08-19** · ✅ **CLOSED 2026-09-29 — answered by §18, which SHIPPED (see the ruling below and §18's header).**
```

- [ ] **Step 3: Verify**

Run: `git diff --stat clavity-dotnet/ROADMAP.md; git diff clavity-dotnet/ROADMAP.md | grep -c '^[-+][^-+]'`
Expected: 1 file changed, and `4` (two removed lines, two added). A larger count means the line endings were
rewritten: STOP, restore with `git restore clavity-dotnet/ROADMAP.md`, redo with the Edit tool.

(Committed together with Task 2.)

---

### Task 2: Merge the §51 duplicate

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md` (§51 body, inserted before §51's closing `---`)
- Modify: `docs/backlog/agy-mark-accepts-a-nonexistent-sha.md:3` (Status line)

- [ ] **Step 1: Add the stub's missing facts to §51.** Insert immediately BEFORE the `---` line that closes
§51 (the first `---` after line 3344), preceded and followed by one blank line:

```markdown
**Earlier record, merged 2026-09-29:** the same defect was first raised 2026-08-31 during an AGY-TEST-AUDIT
and kept as `docs/backlog/agy-mark-accepts-a-nonexistent-sha.md` (measured then: `head` wrote
`deadbeef...deadbeef` and exited 0). That stub also carries the design answer this section needs: ROADMAP §27
keeps `agy-mark.sh` git-optional - outside a repository the ledger gate answers `NO-LEDGER` - so the sha
check should follow the same shape, **no repository means no check**, not a refusal. And §27's ledger gate
does not close this: it proves the ledger records the sha, not that the sha names a commit.
```

- [ ] **Step 2: Mark the stub merged.** Replace its line 3, this exact text:

```text
**Status:** OPEN. Promoted 2026-08-31 from `.clavity/local-anomalies.md`.
```

with this exact text:

```text
**Status:** ✅ **MERGED 2026-09-29 into `clavity-dotnet/ROADMAP.md` §51**, which now tracks the defect (ROADMAP sweep Branch 2). Kept, not deleted: dated plans and specs cite this path. Originally promoted 2026-08-31 from `.clavity/local-anomalies.md`.
```

- [ ] **Step 3: Run the docs gates**

Run: `just check-member-docs && just check-doc-stubs && just check-user-facing-docs`
Expected: each exits 0.

- [ ] **Step 4: Commit**

```bash
git add clavity-dotnet/ROADMAP.md docs/backlog/agy-mark-accepts-a-nonexistent-sha.md
git commit -m "docs(roadmap): close stale §15/§14f headers; merge the agy-mark nonexistent-sha stub into §51

§15 read 'pending AGY-CAPSTONE' though the capstone went GREEN and the test audit ran on 2026-09-14.
§14f was ruled answered by §18, which shipped. The backlog stub duplicated §51; its unique facts
(first raised 2026-08-31; §27's no-repo-means-no-check answer) move into §51 and the stub is marked
merged, not deleted, because dated plans and specs cite it. ROADMAP sweep step 0.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Update the execution index** with the commit sha (the power-failure rule).

---

### Task 3: Repair the two escape-mangled control bytes

A dry run of the Step 1 scanner over every tracked `*.md` at `b0e03801` (2026-09-29) found exactly TWO
control bytes, both the same mechanism - an author wrote a backslash escape and a tool interpreted it:
- `docs/agy-test-audit-ledger.md:43:1508 byte=0` - the text reads "the NUL arrives as the `<NUL>` ESCAPE",
  meant `\u0000` (six characters). git classifies the file BINARY (`i/-text`).
- `docs/superpowers/plans/2026-09-02-phase-1-review-record.md:46:3 byte=8` - the text reads
  "(`<BS>` arrived as a backspace byte)", meant `\b` (two characters). git still says `i/lf`, so only a
  byte scan finds this one.

**Files:**
- Modify: `docs/agy-test-audit-ledger.md:43` (one byte -> `\u0000`)
- Modify: `docs/superpowers/plans/2026-09-02-phase-1-review-record.md:46` (one byte -> `\b`)
- Scratch (not committed): `.clavity/scratch/sweep-step0/`

- [ ] **Step 1: Failing control - prove the defect is there and that the scanner can see it**

Write `.clavity/scratch/sweep-step0/scan-ctl.js`:

```js
// Reports every C0 control byte other than TAB (9), LF (10), CR (13) in the given files.
const fs = require('fs');
let hits = 0;
for (const f of process.argv.slice(2)) {
  const b = fs.readFileSync(f);
  let line = 1, col = 0;
  for (const c of b) {
    if (c === 10) { line++; col = 0; continue; }
    col++;
    if (c < 32 && c !== 9 && c !== 13) { hits++; console.log(`${f}:${line}:${col} byte=${c}`); }
  }
}
console.log(`hits=${hits}`);
process.exit(hits ? 1 : 0);
```

Run: `git ls-files -z '*.md' | xargs -0 node .clavity/scratch/sweep-step0/scan-ctl.js`
Expected: exactly the two hits listed above, `hits=2`, exit 1. Any other set: STOP, `STATE_MISMATCH`.
(Every other tracked `*.md` is the passing control inside the same run.)
Also run: `git ls-files --eol docs/agy-test-audit-ledger.md` -> `i/-text`.

- [ ] **Step 2: Repair - replace each byte with the escape its author wrote**

Write `.clavity/scratch/sweep-step0/repair.js`:

```js
// Each fix: the file, the control byte, the text that must immediately precede it, and the replacement.
const fs = require('fs');
const FIXES = [
  { f: 'docs/agy-test-audit-ledger.md', byte: 0, before: 'arrives as the `', to: '\\u0000' },
  { f: 'docs/superpowers/plans/2026-09-02-phase-1-review-record.md', byte: 8, before: '(`', to: '\\b' },
];
// Guard: a replacement holding a control byte means THIS FILE was mangled when written (a shell layer
// collapsed '\\u0000' to '\u0000'). Refuse rather than write the defect back.
for (const { to } of FIXES) if (/[\x00-\x1f]/.test(to)) { console.error(`mangled replacement ${JSON.stringify(to)}`); process.exit(4); }
// Pass 1 validates EVERY fix; pass 2 writes. A mismatch in any file therefore writes nothing.
const planned = FIXES.map(({ f, byte, before, to }) => {
  const b = fs.readFileSync(f);
  const idx = [];
  for (let i = 0; i < b.length; i++) if (b[i] === byte) idx.push(i);
  if (idx.length !== 1) { console.error(`${f}: expected exactly 1 byte ${byte}, found ${idx.length}`); process.exit(2); }
  const ctx = b.slice(Math.max(0, idx[0] - 40), idx[0]).toString('utf8');
  if (!ctx.endsWith(before)) { console.error(`${f}: unexpected context ${JSON.stringify(ctx)}`); process.exit(3); }
  return { f, b, at: idx[0], byte, to };
});
for (const { f, b, at, byte, to } of planned) {
  fs.writeFileSync(f, Buffer.concat([b.slice(0, at), Buffer.from(to, 'ascii'), b.slice(at + 1)]));
  console.log(`${f}: repaired byte ${byte} at offset ${at} -> ${to}`);
}
```

Run: `node .clavity/scratch/sweep-step0/repair.js`
Expected: two `repaired` lines. Exit 2 or 3: nothing was written; STOP and report - a file is not in the
state measured.

- [ ] **Step 3: Verify the repair and scan every tracked Markdown file**

Run: `git diff --stat -- docs/agy-test-audit-ledger.md docs/superpowers/plans/2026-09-02-phase-1-review-record.md`
-> the review record shows `1 +-`; the LEDGER shows `Bin <n> -> <n+5> bytes` with 0 insertions, because its
index copy is binary (MEASURED 2026-09-29 in a throwaway repo: a NUL file repaired this way diffs as
`Bin 8 -> 13 bytes` even when staged). So the ledger is verified by BYTES: the scan below (no control byte
left) plus Step 2's own `repaired ... -> \u0000` log line, whose replacement the guard proved was not
mangled. (For this one file the numstat check before Step 5's commit shows `-	-`; that is expected.)
Run: `git ls-files -z '*.md' | xargs -0 node .clavity/scratch/sweep-step0/scan-ctl.js`
Expected: `hits=0`, exit 0.

- [ ] **Step 4: Record both instances in §49.** In `clavity-dotnet/ROADMAP.md` §49 (header at line 3312),
insert immediately BEFORE its `**Blast radius:**` paragraph, with one blank line either side:

```markdown
**Two more live instances, found and repaired 2026-09-29 (ROADMAP sweep step 0),** by a byte scan of every
tracked `*.md`: `docs/agy-test-audit-ledger.md:43` held a NUL where `\u0000` was written (committed
`c22698cb`; git classified the ledger BINARY), and `docs/superpowers/plans/2026-09-02-phase-1-review-record.md:46`
held a backspace where `\b` was written (committed `a8ec0281`; git still said text, so only a byte scan sees
it). The gate must therefore scan BYTES, not rely on git's text/binary classification, and must fail on both
pre-repair blobs: `git show b0e03801:<path>`.
```

- [ ] **Step 5: Commit**

```bash
git add docs/agy-test-audit-ledger.md docs/superpowers/plans/2026-09-02-phase-1-review-record.md clavity-dotnet/ROADMAP.md
git ls-files --eol docs/agy-test-audit-ledger.md   # expect a TEXT index state, NOT i/-text
git commit -m "fix(docs): restore two backslash escapes a tool had turned into control bytes

docs/agy-test-audit-ledger.md:43 carried a NUL where \\u0000 was written (c22698cb), so git
classified the ledger as binary and text greps skipped it; the phase-1 review record's line 46
carried a backspace where \\b was written (a8ec0281). A byte scan of every tracked *.md now reports
hits=0. Both are live instances of ROADMAP §49's class and are recorded there. ROADMAP sweep step 0.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Remove the anomalies entry** (gitignored, never committed): delete the one line in
`.clavity/local-anomalies.md` that begins `- [defect] docs/agy-test-audit-ledger.md carries a literal NUL`.
Verify: `grep -c 'literal NUL' .clavity/local-anomalies.md` -> `0`.

- [ ] **Step 7: Update the execution index** with the commit sha.

---

### Task 4: Collect the owner's rulings

**Files:** none modified in this task (Task 5 records them).

Ask with AskUserQuestion, at most 4 questions per call, one item per question. Every question offers the
item's realistic options; the owner may always answer "Other". Put the driver's recommendation first,
marked "(Recommended)", with one line of reason. Before asking about any item, open its section or stub and
state its one-line fact in the question - the owner rules on the item, not on a title.

The items (all measured OPEN at `b0e03801`):

| # | Item | Anchor | Options to offer |
|---|---|---|---|
| 1 | §38 publication policy | `clavity-dotnet/ROADMAP.md:3063` | keep publishing specs/plans (reword `.gitignore:38-39` to match) · restore per-file opt-in (untrack what fails review) · other |
| 2 | §41 deferral | `clavity-dotnet/ROADMAP.md:3153` | keep deferred · lift -> joins Branch 3 |
| 3 | §35 persist peer replies | `clavity-dotnet/ROADMAP.md:2836` | schedule (new branch) · KILL · keep tracked-unbuilt with a reason |
| 4 | §36 orphaned tests (incl. the `test-scripts*` recipe decision) | `clavity-dotnet/ROADMAP.md:2891` | same three |
| 5-9 | owed AGY-TEST-AUDITs: §14g `bd3aa94..f29cd42`; step-2 13b `103aa87..20f38cc`; assertion strength `bd2ddb7..97f012d`; agy-ls discovery fix (capstone GREEN at `8d00a56`); post-v14 probes `4a25d7a..5dc8822` - none has a row in `docs/agy-test-audit-ledger.md` (grep, 2026-09-29) | run (Step 0b) · waive (recorded) |
| 10-20 | the 11 unassigned stubs in `docs/backlog/`: `agent-shell-layer-corrupts-commands-and-probes`, `agy-learn-can-silently-not-run-for-a-whole-session`, `agy-status-reports-working-for-an-idle-peer`, `cheatsheet-reaches-live-path-before-the-human-gate`, `cross-project-anomalies-have-no-cross-project-home`, `dependency-pins-are-never-re-resolved`, `dev-box-background-load-contaminates-every-timing-figure`, `git-index-fatal-recurs-during-test-runs`, `installed-plugin-drifts-under-an-unchanged-version`, `peer-scratch-dir-contains-executable-session-hooks`, `whole-tree-sandbox-copies-are-unbounded` | KILL (with reason) · owner-action · schedule (joins the branch whose files it touches, else a new branch before Branch 8) |

For the agy-ls discovery fix (row 7) the range start is not in memory: before asking, find its capstone row
with `grep -an '8d00a56' docs/agy-capstone-ledger.md`; if none exists, say so in the question and offer
"waive" first - an audit needs a recorded capstone range to audit.

- [ ] **Step 1:** Ask items 1-4.
- [ ] **Step 2:** Ask items 5-8.
- [ ] **Step 3:** Ask items 9-12.
- [ ] **Step 4:** Ask items 13-16.
- [ ] **Step 5:** Ask items 17-20.
- [ ] **Step 6:** Write every ruling to the execution index as it arrives (before the next question).

---

### Task 5: Record the rulings

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md` (headers of §35, §36, §38, §41, §14g as ruled)
- Modify: each ruled stub's `**Status:**` line (line 3 of each file in `docs/backlog/`)
- Modify, only if §38 is ruled "keep publishing": `.gitignore:38-39`

- [ ] **Step 1: Append the ruling to each header / Status line**, verbatim in one of these forms (dated,
ASCII apart from the existing emoji convention). Append to the END of the line that carries the item's
status tokens: for a `###` section that is the `###` line (§35 `:2836`, §36 `:2891`, §38 `:3063`, §41
`:3153`); for §14g it is line 1137, the second line of its bold header; for a stub it is line 3, the
`**Status:**` line. (Tasks 2-3 insert lines only BELOW all of these - at §49 :3325 and §51 :3355 - so the numbers hold; still
locate each by its text before editing.)
  EVERY form below carries the same literal tag, `[sweep-step0 2026-09-29]`, and the Resuming guard checks
  for exactly that tag - do not reword it.
  - KILL: `· 🚫 **KILLED by the owner [sweep-step0 2026-09-29]: <owner's reason in one line>**`
  - owner action: `· ▶ **OWNER ACTION [sweep-step0 2026-09-29]: <the action>**`
  - scheduled: `· ▶ **SCHEDULED [sweep-step0 2026-09-29]: ROADMAP sweep Branch <N>**` (or `new Branch <N> - <subject>`)
  - audit run / waive. §14g: append to its header line as below. ALL FIVE owed audits (§14g's included), when
    WAIVED, also get a row appended at the end of `docs/agy-test-audit-ledger.md`'s table, in its columns
    `| date | range | rounds | verdict | evidence |`:


    ```text
    | 2026-09-29 | `<range>` (<epic name>) | 0 | **WAIVED by the owner - not run** | <owner's reason> [sweep-step0 2026-09-29] |
    ```

    (for the agy-ls discovery fix, `<range>` is the capstone range found in Task 4, or `n/a - no capstone row`).
    A run-ruled audit gets its row when Step 0b runs it. Header forms:
    `· ▶ **AGY-TEST-AUDIT: run as sweep Step 0b [sweep-step0 2026-09-29]**` or
    `· **AGY-TEST-AUDIT WAIVED by the owner [sweep-step0 2026-09-29]: <reason>**`

- [ ] **Step 2: If §38 = keep publishing,** replace BOTH comment blocks that describe the policy - the
`specs/` preamble `.gitignore:20-25` (from "# Internal design provenance — excluded from the PUBLIC repo"
through "... no superseded narratives.") and the `plans/` block `.gitignore:38-39` - with comments stating
the practice the owner ruled, in the owner's words. Keep `:26-32` (why three lines per level) unchanged,
and change no rule line. Do it with the Edit tool, matching each block by its exact TEXT (never by line
number), and edit the `plans/` block FIRST - it is lower in the file, so shrinking it cannot move the
`specs/` block. Afterwards `git diff .gitignore` must show only `#` lines changed; any changed line not
starting with `#`: STOP and `git restore .gitignore`. If §38 = restore opt-in, change nothing here: that is a
scheduled branch of its own, recorded in Step 1.

- [ ] **Step 3: Run the docs gates** - `just check-member-docs && just check-doc-stubs && just check-user-facing-docs` -> each exits 0.

- [ ] **Step 4: Commit** - `git add` the explicit list of files changed in Steps 1-2 (read it from
`git status --short`; never `git add -A`), then:

```bash
git commit -m "docs(roadmap): record the owner's step-0 rulings for the ROADMAP sweep

<one line per ruled item: item - ruling>

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
Replace the placeholder line with the actual per-item list before committing.

- [ ] **Step 5: Update the execution index** with the sha.

---

### Task 6: The spec and this plan

**Files:** `docs/superpowers/specs/2026-09-29-roadmap-sweep-sequence-design.md`,
`docs/superpowers/plans/2026-09-29-roadmap-sweep-step-0.md` (both gitignored today).

- [ ] **Step 1:** If §38 was ruled "keep publishing": add two negation lines to `.gitignore`, directly
after the existing spec negations and plan negations respectively:
  `!docs/superpowers/specs/2026-09-29-roadmap-sweep-sequence-design.md` and
  `!docs/superpowers/plans/2026-09-29-roadmap-sweep-step-0.md`.
  Verify: `git check-ignore -q <each path>; echo $?` -> `1` (not ignored) for both.
  If §38 was ruled "restore opt-in": the owner reads both files, then the same two negations are added.
  If the owner declines to publish either: skip this task and leave both files local.
- [ ] **Step 1b: Run the docs gates BEFORE committing** - the lefthook `pre-commit` hook runs `ruff`,
`curate-in-progress` and `cheatsheet-parity` only, none of them a docs gate, and the docs gates (`member-docs`, `user-facing-docs`, `doc-stubs`) live in `pre-push`
(`lefthook.yml`), so a commit alone checks nothing here:
`just check-member-docs && just check-doc-stubs && just check-user-facing-docs` -> each exits 0.
- [ ] **Step 2:** `git add .gitignore <the two paths>` and commit
  `docs: publish the ROADMAP sweep spec and its step-0 plan` (with the attribution line).
- [ ] **Step 3:** Update the execution index.

---

### Task 7: Close step 0

- [ ] **Step 1: Run the full pre-push gate set locally** - `lefthook run pre-push`. Expected: every command
passes. Then run the CI-only injected-context gate in a CLEAN worktree, because locally it resolves
references against the working tree (ROADMAP §54):

```bash
git worktree add ../clavity-step0-check HEAD
( cd ../clavity-step0-check && pwsh -NoProfile -File scripts/check-injected-context.ps1 ); echo rc=$?
git worktree remove ../clavity-step0-check
```
Expected: `rc=0`.

- [ ] **Step 2:** Update the execution index: step 0 done, the commit shas, and the ▶ NEXT = Step 0b (if any
audit was ruled "run") else Branch 1.
- [ ] **Step 3:** Tell the owner the commits are on local `main` and ready to push; do NOT push.

---

## Self-review (run 2026-09-29)

- **Spec coverage.** Mechanical bullets: §15/§14f headers -> Task 1; §51 merge -> Task 2 (deviation stated at
  the top); NUL repair + repo-wide scan -> Task 3; anomaly entry removal -> Task 3 Step 5. Owner rulings:
  §38, §41, §35, §36, §14g, the four owed audits, the 11 stubs -> Tasks 4-5. The spec-commit hold -> Task 6.
  Step 0b is NOT in this plan: it exists only if an audit is ruled "run", and each audit is its own
  discipline run.
- **Placeholders.** Three bounded fill-ins remain, each resolved by a named earlier step: the `hits=` line
  (Task 3 Step 3), the per-item ruling list (Task 4), the owner's §38 wording (Task 4 item 1). None is a
  design decision left open.
- **Anchors.** Every line number was measured at `b0e03801` and is re-checked by Task 0. Task 1 changes no
  line count; Task 2 inserts below :3344 and Task 3 below :3312, after every anchor Tasks 1 and 5 use.
- **Found while writing:** a dry-run byte scan found a SECOND escape-mangled byte (a backspace in the
  2026-09-02 phase-1 review record); Task 3 repairs both, and §49 records both.

## Stand-downs

- REJECTED in part (plan panel round 5, peer): "`.clavity/local-anomalies.md` is a private memory name".
  It is a documented, shipped path: `git grep -l 'local-anomalies.md'` lists 79 tracked files. The other half
  (the owner's untracked entries named in Task 0) was FOLDED as generic wording.
- Plan panel: 5 rounds, findings 5 / 4 / 2 / 3 / 3 BLOCKING, every one FOLDED or REJECTED above; peer claims
  measured before folding: `pwsh -File` resolves against the CALLER's cwd (right), `git diff --stat` on a
  binary-index file prints `Bin n -> m` (right), both probed in a throwaway repo with a control.
- Round 6 (the cap, owner-chosen): 3 BLOCKING, all introduced by the owner's switch to subagent execution
  (Task 1/2 split across subagents; subagents blind to the rulings; subagents told to write an index only
  the driver writes) - all FOLDED into the "Execution model" section. **Panel closed at the hard cap, NOT
  GREEN; no finding left open.**

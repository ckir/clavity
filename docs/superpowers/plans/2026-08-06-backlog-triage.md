# Backlog triage — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring all six open-issue tracking surfaces into agreement with the code, write the runbook that stops the next session re-deriving any of it, and build no mechanism.

**Architecture:** Pure documentation work. Every task is a measurement followed by an edit to a markdown file or a memory file. No executable code is added anywhere — that is the decision, enforced by an allow-list check in Task 8.

**Tech Stack:** Markdown, YAML frontmatter, `git`, `rg`. No new tooling.

**Spec:** `docs/superpowers/specs/2026-08-06-backlog-triage-design.md` (owner-approved 2026-08-06, AGY-AFTER GREEN after 2 rounds).

---

## Read this before Task 1 — five things that will bite you

**1. A status line is not evidence of itself.** Every one of the seven stale entries found on 2026-08-06
looked plausible and was wrong. **Run the oracle. Never disposition from the entry's own prose.**

**2. `rg --no-ignore` for any "are there any left?" question.** Both the Grep tool and bash `grep`
returned false zeros this session, in opposite directions. `.clavity/` and `docs/superpowers/` are
gitignored, so a plain search cannot see them.

**3. `fix-the-tool-backlog/` is APPEND-ONLY.** `agy-autotrain/docs/fix-the-tool-backlog/README.md:8`:
*"One file per entry (append-only)."* **Never delete or move one of those files.** Close by editing
frontmatter in place.

**4. 🔴 Marking an item `fixed` does NOT authorise touching the driver-cheatsheet rule.**
`_template.md:14-18` states it: *"Two SEPARATE gates, do not conflate them… Closing this item does NOT
authorise stripping the rule — an end user on an older build still needs it."* **Do not edit
`knowledge/driver-cheatsheet.core.md` or any golden-header content in this epic.** Doing so also
red-gates two pinning tests in both drivers.

**5. Un-reproduced is NOT fixed.** Several entries need a live agy peer in a specific state. If an oracle
cannot be run, the entry keeps `status: open` and gains `last-triaged: 2026-08-06`. Closing on a failed
reproduction is the false-clean this whole epic exists to remove.

---

## File structure

| File | Change | Task |
|---|---|---|
| `MEMORY.md` (memory dir) | delete defects (a) and (c); re-word (b) | 1 |
| `memory/feedback-preexisting-defects-in-scope.md` | add the reproduction rule | 1 |
| `agy-autotrain/docs/fix-the-tool-backlog/*.md` (8 files) | frontmatter dispositions | 2–3 |
| `docs/backlog/golden-header-per-ask-token-optimization.md` | confirm status | 4 |
| `memory/project_docs-accuracy-audit.md` | record 6 judgements | 5 |
| `docs/backlog-triage-runbook.md` | **create**, 12 sections | 6 |
| `MEMORY.md` (memory dir) | the 3 revisit-triggers | 7 |
| — | final gates + criterion-7 evidence | 8 |

---

## Task 0: Baseline

**Files:** none — this task only measures.

- [ ] **Step 1: Confirm the tree is clean and record the SHA**

```bash
git status --short && git rev-parse HEAD
```

Expected: no output from `status`, then a SHA. Write it down — Task 8 diffs against it.

- [ ] **Step 2: Record the suite baseline**

```bash
just test-scripts-fast 2>&1 | grep -E 'Tests Passed:'
```

Expected: `Tests Passed: 328, Failed: 0` — measured 2026-08-06 at `413c617`.

**Record whatever number you actually get, and use THAT as the invariant for Task 8 Step 3.** If it is not
328, do not "fix" anything and do not stop: another epic may have landed since. What matters is that the
count is IDENTICAL at the end, because this epic touches no test and no code. A count that moves means
something outside scope was edited. **A count that differs from 328 at the START is information, not a
failure** — quoting a number from a plan instead of measuring is how `_partition.md` went wrong twice.

---

## Task 1: Close the pre-existing-defect list

The three defects live in the memory index, NOT in the repo. Verified 2026-08-06: `MEMORY.md` line 44,
item 2 of `## ▶ NEXT — ranked`, sub-items (a), (b), (c).

**Files:**
- Modify: `<memory>/MEMORY.md`
- Modify: `<memory>/feedback-preexisting-defects-in-scope.md`

**Set this once, at the start of the task — every later `$MEM` in this plan depends on it:**

```bash
export MEM="/c/Users/user/.claude/projects/C--Users-user-Development-Rust-clavity/memory"
ls "$MEM/MEMORY.md" && echo "MEM resolves"
```

Expected: the path listed, then `MEM resolves`. **Shell state does not persist between tool calls in this
harness — re-export it in any later call that uses it** (Tasks 1 and 7).

- [ ] **Step 1: Re-run D1's oracle — control and treatment**

```bash
bash scripts/check-seed-artifacts-synced.sh; echo "control exit=$?"
env PATH="/c/Program Files/Git/usr/bin" bash scripts/check-seed-artifacts-synced.sh; echo "treatment exit=$?"
```

Expected: `control exit=0`, then `treatment exit=2` with
`check-seed-artifacts-synced: jq is required but not found on PATH`.
**Both halves matter** — an exit 2 with no working control proves only that the script is broken.

- [ ] **Step 2: Re-run D3's oracle**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter 'FullyQualifiedName~LsDiscovery' --nologo -v q; cd ..
```

Expected: `Passed! - Failed: 0, Passed: 19`. The relevant case is
`ParseLatest_pairs_the_http_line_of_the_SAME_session_when_two_sessions_interleave`.

- [ ] **Step 3: Rewrite the MEMORY.md item**

Find the line beginning `2. **PRE-EXISTING DEFECTS — tracked**` and replace the whole numbered item with:

```markdown
2. **PRE-EXISTING DEFECTS — 2 of 3 CLOSED 2026-08-06 by measurement, 1 dropped** ([[feedback-preexisting-defects-in-scope]]): (a) the `jq`-absent silent pass **is FIXED** — `check-seed-artifacts-synced.sh:10` exits 2 loud, proved with a control; (c) `ParseLatest` **is FIXED** — it prefers the HTTP line whose pid matches the gRPC line, and `ParseLatest_pairs_the_http_line_of_the_SAME_session_when_two_sessions_interleave` exists to kill that mutant. (b) check-roster `path-scan.iss` **DROPPED as unreproducible** — the map declares it `Members=@('classic')` and only classic references it, which is self-consistent; **the entry never carried a reproduction, so if the original observation was real it is lost.**
```

- [ ] **Step 4: Record the lesson where capture guidance lives**

Append to `<memory>/feedback-preexisting-defects-in-scope.md`:

```markdown

## A tracked defect MUST carry its reproduction (added 2026-08-06)

Entry (b) — "check-roster `Assert-SharedMapHealthy` path-scan.iss dotnet gap" — was dropped after
measurement, not because it was disproven but because **nobody could tell what state it described.**
`scripts/lib/release-lib.ps1:47` declares `installer/_shared/path-scan.iss` with `Members=@('classic')`
and `Provable=$true`, and only `clavity-classic/installer/clavity-classic.iss` references it. That is
self-consistent. The entry may well have been real; its evidence was not written down.

**So: a tracked defect carries the command, the test name, or the `file:line` that reproduces it — or it
is not trackable.** A one-line summary of a defect is a reminder to its author and an unfalsifiable claim
to everyone else. The cost is not zero: this one consumed a full re-measurement before it could be closed,
and the answer was still "cannot tell".
```

- [ ] **Step 5: Commit**

Memory files are outside the repo and are not committed. **Verify instead:**

```bash
grep -c 'PRE-EXISTING DEFECTS — 2 of 3 CLOSED' "$MEM/MEMORY.md"
grep -c 'MUST carry its reproduction' "$MEM/feedback-preexisting-defects-in-scope.md"
```

Expected: `1` and `1`.

---

## Task 2: Triage `fix-the-tool-backlog` — the six `open` dotnet/both entries

**Files:** modify frontmatter only, in `agy-autotrain/docs/fix-the-tool-backlog/`.

**Each entry gets ONE of three outcomes.** Never delete a file.

| outcome | frontmatter |
|---|---|
| still open, oracle ran | `status: open` + `last-triaged: 2026-08-06` |
| fixed | `status: fixed` + `fixed-by: <sha>` + `fixed-on: 2026-08-06` |
| could not run the oracle | `status: open` + `last-triaged: 2026-08-06   # could not reproduce; NOT evidence of fixed` |

- [ ] **Step 1: Run all six oracles and record each result**

```bash
cd /c/Users/user/Development/Rust/clavity
echo "== grpc-default-max-message-size: is the cap set? =="
rg -n 'MaxReceiveMessageSize|MaxSendMessageSize' clavity-dotnet/src/Clavity.Ls/LsChannel.cs || echo "  NOT SET -> still open"

echo "== agy-look-tail-truncation: is there a tail-anchored/newest-first view? =="
rg -n 'newest-first|newest first|tail-anchored|Reverse\(\)' clavity-dotnet/src/Clavity.Ls/AgyView.cs || echo "  none -> still open"

echo "== conversation-scoped-tools: is conversation-existence split from reachability? =="
rg -n 'no open conversation|NoConversation|conversation.*exist' clavity-dotnet/src/Clavity.Ls/*.cs || echo "  none -> still open"

echo "== stalled-reply-recoverable: does idle-wait expiry poll rather than fail? =="
rg -n 'idle.*expiry|poll.*status|retry.*idle' clavity-dotnet/src/Clavity.Ls/AgyView.cs || echo "  none -> still open"

echo "== working-vs-stuck-step-delta: is a step delta used to judge stuck? =="
rg -n 'step.?delta|TotalSteps.*previous|StepDelta' clavity-dotnet/src/Clavity.Ls/*.cs || echo "  none -> still open"

echo "== idle-wait-false-modal: is the idle-wait budget configurable? =="
rg -n 'AGY_IDLE|IdleWait|idle.?wait.*(env|option|config)' clavity-dotnet/src/Clavity.Ls/*.cs || echo "  none -> still open"
```

**Read the output, do not assume it.**

- **A `NOT SET` / `none` line is DECISIVE: the entry stays `open`** and gets `last-triaged`.
- **A HIT is not decisive.** Open the file and judge whether the hit is the mitigation that entry asks
  for, or an unrelated mention of the same words. If it IS the mitigation, the entry becomes `fixed` and
  you must find the SHA that landed it:

```bash
git log --oneline -S'<the distinctive symbol you just found>' -- <the file it is in> | tail -1
```

  That SHA goes in `fixed-by:`, with `fixed-on:` set to that commit's date — **not to today's date.**
  `fixed-on` records when the code was fixed, not when someone noticed.
- 🔴 **A `fixed` verdict still does NOT authorise touching the driver-cheatsheet rule** (`_template.md:14-18`).

- [ ] **Step 2: For each of the six, add the `last-triaged` line under `status:`**

Example, `grpc-default-max-message-size.md` — the frontmatter becomes:

```yaml
---
slug: grpc-default-max-message-size
variant: clavity-dotnet
observed: 2026-07-31
source-inbox-entry: "..."
status: open
last-triaged: 2026-08-06   # oracle: no MaxReceiveMessageSize in LsChannel.cs -> confirmed still open
---
```

**Keep every other frontmatter key byte-identical.** Change nothing below the `---`.

- [ ] **Step 3: Verify all six carry the new key**

```bash
grep -L 'last-triaged' agy-autotrain/docs/fix-the-tool-backlog/*.md | grep -vE 'README|_template|DRY-RUN|curate-nudge-age'
```

Expected: no output — every entry except the infrastructure files and the already-`fixed` one is stamped.

- [ ] **Step 4: Commit**

```bash
git add agy-autotrain/docs/fix-the-tool-backlog/
git commit -m "docs(backlog): triage the six open fix-the-tool entries, each against a named oracle"
```

---

## Task 3: The already-`fixed` entry, and the two non-entries

- [ ] **Step 1: Verify `curate-nudge-age-reads-drain-log-dates.md` really is fixed**

```bash
grep -n 'fixed-by\|fixed-on' agy-autotrain/docs/fix-the-tool-backlog/curate-nudge-age-reads-drain-log-dates.md
rg -n 'Pending' agy-autotrain/hooks/agy-curate-nudge.sh | head -3
pwsh -c "Invoke-Pester scripts/tests/agy-curate-nudge.Tests.ps1" 2>&1 | grep -E 'Failed:'
```

Expected: `fixed-by`/`fixed-on` present; the awk scan anchored to `## Pending`; `Failed: 0`.
The pinning case is `is SILENT when the only old date lives in a drain-log COMMENT, not on a pending bullet`.

**If `fixed-by` is absent**, add it — `_template.md:7` requires it on `fixed`, and an entry marked fixed
without the SHA is the same unfalsifiable claim Task 1 Step 4 just wrote a rule about.

- [ ] **Step 2: Classify the two files that are not entries**

`DRY-RUN-2026-07-11.md` and `conversation-scoped-tools-vs-no-open-conversation.md` — the second HAS a
`slug:` but its status line was not found by the earlier scan. Open both:

```bash
head -8 agy-autotrain/docs/fix-the-tool-backlog/DRY-RUN-2026-07-11.md
head -8 agy-autotrain/docs/fix-the-tool-backlog/conversation-scoped-tools-vs-no-open-conversation.md
```

If `conversation-scoped-tools-*.md` has no `status:` key, add `status: open` plus `last-triaged`, matching
`_template.md:6`. If `DRY-RUN-*.md` is an exercise artifact rather than an entry, leave it and say so in
the commit message — do not delete it (append-only).

- [ ] **Step 3: Commit**

```bash
git add agy-autotrain/docs/fix-the-tool-backlog/
git commit -m "docs(backlog): confirm the fixed entry's provenance, classify the two non-entries"
```

---

## Task 4: `docs/backlog/` (one file)

- [ ] **Step 1: Confirm it is still unstarted**

```bash
head -12 docs/backlog/golden-header-per-ask-token-optimization.md
rg -n 'per-ask|token-optimi' clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs || echo "  no per-ask optimisation in code -> still BACKLOG"
```

- [ ] **Step 2: Stamp the triage date under its Status line, leaving the status unchanged**

```markdown
**Status:** BACKLOG (not started). **Raised:** 2026-07-11 · **Last triaged:** 2026-08-06 (confirmed unstarted).
```

- [ ] **Step 3: Commit**

```bash
git add docs/backlog/
git commit -m "docs(backlog): confirm the per-ask token item is still unstarted"
```

---

## Task 5: The six unchecked docs-audit findings

Two of eight were checked on 2026-08-06: `clavity-dotnet/README.md` (stale) and `docs/README.md` (false
positive). **Six remain**, verified by name: `.github/pull_request_template.md`, `agy-autotrain/README.md`,
`agy-autotrain/verify/probe-design.md`, `clavity-classic/docs/how-it-works.md`,
`clavity-classic/installer/clavity-classic-bridge-README-FIRST.md`, `clavity-classic/README.md`.

- [ ] **Step 1: For each, read the finding then open the cited file and its oracle**

```bash
grep -A3 '## <doc-path> — FINDINGS' docs/docs-audit-findings.md
```

Each finding names both sides (`doc:line | oracle:line`). **Open both.** Expect a high false rate — the
extractor is an LLM and 2 of 2 checked were wrong.

- [ ] **Step 2: Record all six judgements in the memory topic file, not the punch-list**

Append to `<memory>/project_docs-accuracy-audit.md` under the 2026-08-06 section, one bullet each:

```markdown
- **`<doc>:<line>` — STALE | FALSE POSITIVE | CONFIRMED**. <what the oracle showed, in one sentence.>
```

**Do not edit `docs/docs-audit-findings.md`** — it is a generated view of `docs-audit-findings.json` and
the next audit run overwrites it, erasing any judgement written there.

- [ ] **Step 3: If any finding is CONFIRMED, fix the doc; if it is a real defect in CODE, stop**

A confirmed doc inaccuracy is a one-line doc edit and belongs in this epic. **A confirmed defect in code
does not** — surface it to the owner with the measurement and let them decide. Scope is triage.

- [ ] **Step 4: Commit**

**Stage the files you actually edited, by name.** List them first, then add exactly those:

```bash
git status --short
git add <each doc you edited, by explicit path>
git commit -m "docs: fold the confirmed docs-audit findings, record all six judgements"
```

🔴 **Do NOT use `git add -A` or a directory path here.** It swept an unintended file twice in this repo,
including `.claude/settings.local.json` — a personal override — on a PUBLIC repo. An earlier draft of this
very step said `git add -A docs/ clavity-classic/ …` and then warned against `-A` in the next sentence.
If nothing was CONFIRMED in Step 3, this task commits nothing and that is the expected outcome — the six
judgements live in the memory file, which is outside the repo.

---

## Task 6: Write the runbook

**Files:**
- Create: `docs/backlog-triage-runbook.md`

- [ ] **Step 1: Write all twelve sections**

The spec's U5 lists them. Each is a section with a heading; none may be omitted — success criterion 6
checks them one by one:

1. The six tracking surfaces, by path.
2. Measure, never read — state the oracle per entry.
3. Per-surface closing conventions, including the append-only rule.
4. Un-reproduced is not fixed — the third disposition.
5. `docs-audit-findings.md` is leads, not defects; record judgements in memory.
6. `rg --no-ignore` for "are any left?".
7. The three revisit-triggers.
8. Why no mechanism exists, with the measured counts.
9. The dual-variant twin check (`check-seed-artifacts-synced.sh:27-29` `divergent()`).
10. The `wont-fix` disposition (`_template.md:6`; no entry uses it today).
11. `ROADMAP.md` is forward-looking, `CHANGELOG.md` is history — never backfill.
12. Routing for a newly observed problem.

**Include the three ways this fails** (spec U6): ordinary commits consult nothing; a passive doc is
invisible to subagents and fresh sessions; an incidental fix cannot close an entry its author never saw.
A runbook that oversells itself is worse than none.

- [ ] **Step 2: Verify every section is present**

```bash
grep -c '^## ' docs/backlog-triage-runbook.md
```

Expected: at least 12.

- [ ] **Step 3: Confirm it is NOT added to the user-facing roster**

```bash
grep -c 'backlog-triage-runbook' docs/user-facing-docs.txt
```

Expected: `0`. It is internal, like `release-runbook.md` and `drain-knowledge-runbook.md`.

- [ ] **Step 4: Commit**

```bash
git add docs/backlog-triage-runbook.md
git commit -m "docs: backlog triage runbook, so the next session re-derives none of this"
```

---

## Task 7: Record the revisit-triggers where they will be read

- [ ] **Step 1: Append to the memory index, under the tracked-debt pointer**

```markdown
> 🔴 **NO BACKLOG MECHANISM EXISTS, BY DECISION (2026-08-06) — and it is CONDITIONAL.** A stale entry costs one measurement at triage and causes no defect, so a permanent checker optimises a non-bottleneck. **Revisit the moment ANY of these stops holding: (1) one human owner + paired agents; (2) the measure-before-coding law holds; (3) no stale entry has yet caused real rework.** Full reasoning + the measured counts → [[project_backlog-triage]] and `docs/backlog-triage-runbook.md`.
```

- [ ] **Step 2: Verify**

```bash
grep -c 'NO BACKLOG MECHANISM EXISTS, BY DECISION' "$MEM/MEMORY.md"
```

Expected: `1`.

---

## Task 8: Final gates and the criterion-7 evidence

- [ ] **Step 1: The allow-list check — this is the scope gate**

```bash
git diff --name-only <Task 0 SHA>..HEAD
```

**Every path must end in `.md`.** Any file under `scripts/`, `src/`, `installer/`, `plugin/hooks/`, a
skill, a CI workflow, or `justfile` means the "build nothing" decision was broken. Read the list; a
one-line eyeball is the whole gate.

- [ ] **Step 2: The criterion-7 evidence — print the dispositions as diff hunks**

```bash
git diff <Task 0 SHA>..HEAD -- agy-autotrain/docs/fix-the-tool-backlog/ docs/backlog/ | grep -E '^[+-](status|last-triaged|fixed-by|fixed-on|\*\*Status)'
```

Expected: one `+ last-triaged:` per triaged entry. **These hunks ARE the evidence** that no entry was left
correct-but-unmarked. A checkbox is not.

- [ ] **Step 3: Suites unchanged**

```bash
just test-scripts-fast 2>&1 | grep -E 'Tests Passed:'
```

Expected: `Tests Passed: 328, Failed: 0` — **identical to Task 0.** A change means code was touched.

- [ ] **Step 4: Line endings**

```bash
python3 -c "
import subprocess,sys
fs=subprocess.run(['git','diff','--name-only','<Task 0 SHA>..HEAD'],capture_output=True,text=True).stdout.split()
for f in fs:
    d=subprocess.run(['git','show','HEAD:'+f],capture_output=True).stdout
    crlf=d.count(b'\r\n'); lf=d.count(b'\n')-crlf
    print(('CRLF' if crlf and not lf else ('MIXED' if crlf else 'LF')), f)"
```

Expected: every committed file `LF`. **Judge by what is COMMITTED** — with `core.autocrlf` the working
tree is legitimately CRLF, and "normalizing" a clean file creates a diff out of nothing.

- [ ] **Step 5: No new mechanism, stated plainly to the owner**

Report the Task 8 Step 1 file list verbatim. If it is all `.md`, say so; if not, say which file broke it.

---

## Self-review

**Spec coverage.** U1 → Task 1. U2 → Tasks 2–3. U3 → Task 4. U4 → Task 5. U5 → Task 6. U6 → the
dispositions in Tasks 2–4 plus the standing rule written in Task 6. Success criteria 1–3 → Tasks 1–5;
4 → Task 8 Step 1; 5 → Task 7; 6 → Task 6 Step 2; 7 → Task 8 Step 2; 8 → Tasks 1 and 7.

**Placeholders.** None. Every oracle is a runnable command; every edit shows its text.

**One thing this plan deliberately does NOT pin.** Task 2 Step 1's six greps tell you whether the
mitigation is absent — a `none` result is decisive. A HIT is not: it means "open the file and judge
whether this is the mitigation the entry asked for." That judgement cannot be pre-written without knowing
what the hit is, and pretending otherwise would be the fabricated precision this repo's plan discipline
exists to prevent.

**Consistency.** `last-triaged: 2026-08-06` is the single stamp format everywhere. `<memory>` is the
memory directory throughout. `<Task 0 SHA>` is the one placeholder, filled in at Task 0 by definition.

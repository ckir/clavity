# Step 1: The four owner rulings — §14f, §14g, §17a, §17b — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> ⚠ **EXCEPTION — Tasks 1 and 2 must NOT be delegated to a subagent.** They consult the peer over the
> `agy_ask` MCP tool, and **subagents cannot reach MCP tools at all under this driver** — measured at
> `clavity-dotnet/plugin/knowledge/agy-capabilities.md:151-152`. The orchestrator runs those two itself and
> delegates the rest normally.

**Goal:** Obtain four owner rulings that gate later implementation steps, and record each in the ROADMAP
entry it belongs to, with its chosen option and its reason.

**Architecture:** Docs-only. No code changes, no CI dependency, no branch. The rulings are **elicited,
never authored**: each is consulted with the peer, put to the owner with both recommendations, and only
then written down. Two consult briefs, batched by blast radius.

**Tech Stack:** `agy_ask` MCP tool, PowerShell 7, git.

---

## HARD PRECONDITION: this plan cannot start until step 0 has merged

**All four ROADMAP entries exist only on `feature/injected-context-governance`.** Measured 2026-08-19: for
each of the four headings, `main=0` and `HEAD=1`. **They are not on `main` at all.** A rulings edit
attempted before the merge would have nothing to edit.

```bash
git rev-parse --abbrev-ref HEAD          # expect: main
grep -c "§14f — two shipped artifacts disagree\|§14g — the agy-observations inbox lives INSIDE\|§17a — the shield's debounce key\|§17b — every \`pre-push\` gate reads" clavity-dotnet/ROADMAP.md
```

Expected: `main`, then `4`.

**If the count is 0, step 0 has not merged. STOP** and run `2026-08-19-step-0-merge-to-main.md` first.
This is the whole reason the two plans are sequential rather than parallel.

---

## Where "the durable execution index" is

- `C:\Users\user\.claude\projects\C--Users-user-Development-Rust-clavity\memory\MEMORY.md`
- `…\memory\project_steps-0-1-plan.md`

**Do not invent a new location.**

---

## Preconditions

- [ ] Step 0 merged; the check above returns `4`.
- [ ] **One remote-mutating operation needing its OWN owner authorisation:** the push in Task 4. The
      standing rule is that the owner owns every push, and approving this plan is not that authorisation.
- [ ] No `--no-verify`, no `git add -A`. Explicit paths only.
- [ ] `.clavity/` is gitignored and must **never** be force-added.

**Convention for "Expected:" lines.** Anything in `backticks` or a code block is **literal**; the
surrounding sentence is connective prose.

---

## Task 1: Prepare the consults — AGY-FIRST, batched by blast radius

**Files:**
- Create: `.clavity/seams/rulings-knowledge.md` (§14f + §14g)
- Create: `.clavity/seams/rulings-hooks.md` (§17a + §17b)
- Create: `.clavity/consult-baseline/before-consult.txt`

**These are design forks in subproject work, so AGY-FIRST applies: consult the peer first, then put the
question to the owner carrying both the peer's recommendation and yours. The owner decides. Never delegate
the decision to the peer.**

**Why two briefs and not one or four.** §14f and §14g are both about the agy-autotrain knowledge flow and
share files; §17a and §17b are both about the hook/gate layer. That is one review surface each. Batching
all four would force two unrelated domains into one context — what the sequencing spec's cost-model rule 2
forbids. Four separate consults would pay the per-consult context cost twice over for no coverage gain.

- [ ] **Step 1: Snapshot the tree — OUTSIDE the peer's scratch area**

```bash
mkdir -p .clavity/consult-baseline .clavity/scratch/step-1
git status --short > .clavity/consult-baseline/before-consult.txt
wc -l < .clavity/consult-baseline/before-consult.txt
```

Expected: `0`.

🔴 **The baseline must NOT live in `.clavity/scratch/step-1/`** — that directory is handed to the peer in
Step 4 as its sanctioned writable scratch. **An integrity baseline stored inside the area the audited party
may write to is not a baseline**: a peer that mutated the tree could rewrite it to match, and Step 5's diff
would report `TREE UNCHANGED` and pass the mutation through.

- [ ] **Step 2: Write the knowledge-flow brief (§14f + §14g)**

Point at files, never at a pasted summary. Include:

- `clavity-dotnet/ROADMAP.md` — the §14f and §14g entries (locate by heading, not line number)
- the artifacts in dispute: `scripts/drain-lib.ps1:214` and `:223`,
  `scripts/drain-knowledge-prompt.md:4` and `:56`,
  `agy-autotrain/skills/agy-curate/SKILL.md:112`, `:124`, `:339`
- **§14f's two dispositions, verbatim from the entry** — they are opposite edits to different files:
  1. `core.md` is driver-owned ⇒ the `agy-curate` skill is the defect; its cheatsheet-compilation section
     must PROPOSE an edit rather than apply one, and the drain flow grows the step that applies it.
  2. `core.md` is curator-owned in the standalone flow ⇒ the protected list and the prompt are over-broad;
     they must be scoped to the in-repo flow, and the standalone path must invoke the gate.
- **§14g's stated fix:** move the canonical inbox to `<USERPROFILE or HOME>/.clavity/agy-observations.md`,
  where the golden-header files already live.
- **A stale-number correction the brief MUST carry:** §14g says "30 repo / 18 installed". **Re-measure
  before sending** — it was 0 repo / 71 installed on 2026-08-17 and moves every session. The entry's
  conclusion holds and is stronger; only the figures are stale. **Every other measurement in these plans
  ships with its command, and this one was ordered without one:**

  ```bash
  REPO=agy-autotrain/knowledge/agy-observations.md
  INST="$LOCALAPPDATA/Programs/agy-autotrain/plugins/agy-autotrain/knowledge/agy-observations.md"
  r=$(grep -c '^- \[' "$REPO" 2>/dev/null || true); echo "repo pending      : ${r:-0}"
  i=$(grep -c '^- \[' "$INST" 2>/dev/null || true); echo "installed pending : ${i:-0}"
  ```

  **The `|| true` is not decoration.** `grep -c` prints `0` **and exits non-zero** when there are no
  matches, so the obvious `$(grep -c ... || echo 0)` emits `0` **twice** — precisely in the zero case this
  measurement exists to detect. Measured: the first draft of this block did exactly that. Capturing to a
  variable and defaulting with `${r:-0}` gives one value in all three cases — zero matches, matches, and a
  missing file.

  **The INSTALLED copy is canonical** — that is what §14g is about. A `0` from either is a
  STOP-AND-VERIFY, not "nothing pending".

Extra questions worth adding: whether §14f's ruling constrains §14g's architectural move or is independent
of it; and whether moving the inbox out of the plugin tree changes who owns `core.md`, since both concern
the same flow.

- [ ] **Step 3: Write the hooks brief (§17a + §17b)**

- `clavity-dotnet/ROADMAP.md` — the §17a and §17b entries
- **§17a's measured fact:** the marker is `"$_ass_dir/.clavity-shield-$_ass_class-$_ass_key"` at
  `clavity-dotnet/plugin/hooks/agy-shield-lib.sh:70` — the key is the caller's session id with **no
  repository component**. Control: repo A/key k1 reports; repo A/k1 again is silent (correct); a **fresh
  repo B under the same key is silent** (the defect); repo B under a different key reports.
- **§17a's three named dispositions:** key on the repository root path, on its hash, or leave the
  cross-repo case documented as a known limit.
- **§17b's measured fact:** `lefthook.yml` defines exactly **10** pre-push jobs — `seed-sync`,
  `agy-skills`, `doc-stubs`, `member-docs`, `user-facing-docs`, `register-hash`, `installer-ascii`,
  `check-versions`, `check-plugin-namespace`, `check-ci-filter-coverage` — and **zero** consult
  `git show <ref>:<path>`, `--cached`, or the push refs on stdin. All resolve paths from the worktree.
- **§17b's ruling explicitly includes KILL.** It is 10 gates and repo-wide churn for a defect not yet
  observed to bite. Present KILL as a first-class option, not a fallback.

Extra questions: whether §17a's fix re-arming every existing debounce once is acceptable or needs a
migration; and whether a *subset* of the ten gates (those whose false-GREEN direction is reachable) is a
coherent middle option for §17b, or whether mixed semantics across ten siblings is worse than either
extreme.

- [ ] **Step 4: Run both consults, review-only — via the driver's transport**

**The mechanism:** this repository runs the **clavity-dotnet** driver, so a consult goes over the
**`agy_ask` MCP tool**, after an `agy_status` idle-check confirms the peer is not mid-turn. Do not fire
while it is working. **Record `TotalSteps` from that idle-check before firing** — Step 4b compares against
it.

🔴 **MAIN THREAD ONLY. Do not delegate this task.** `agy-capabilities.md:151-152`: *"the MCP signal-bus
path is **main-thread-only** (subagents lack the MCP tools)"*. A subagent literally cannot call `agy_ask`.

Send the peer the **PATH** to the brief, never the brief's text — pointing at a file is what lets it read
the artifact itself instead of your summary of it.

Each payload carries: the 🛑 REVIEW-ONLY banner enumerating **writing, redirection and scratch dumps as
separate forbidden acts**; a sanctioned scratch directory (`.clavity/scratch/step-1/`); and — as the last
line, verbatim — `IF ANYTHING HERE IS AMBIGUOUS OR UNDER-SPECIFIED, ASK ME A QUESTION RATHER THAN GUESSING.`

- [ ] **Step 4b: If a consult is backgrounded, tell a slow one from a dead one**

A consult may exceed the 120s synchronous window and be backgrounded. That is normal: the reply arrives
later. **Never re-fire the original ask on a timeout, and never read a timed-out consult as "no findings".**

Call `agy_status` and compare `TotalSteps` against the value recorded in Step 4. **If it has advanced AND
`State` is still `working`, the peer is working — wait.** If it is unchanged after a couple of minutes,
**or `State` is anything other than `working`**, the consult is not progressing: recover the reply with
`agy_look` (no quota) rather than re-firing; if there is no assistant step to recover, treat the peer as
unreachable, tell the owner, and fold nothing from that consult.

**Both halves of that condition are load-bearing, and the split dropped one of them.** `TotalSteps` advances
and then STOPS advancing when the peer finishes — so a completed consult has a higher count than the
baseline and is idle. Testing the count alone would read a finished peer as a working one and wait forever
on a reply that already arrived.

- [ ] **Step 5: Diff-after — verify the review-only envelope held**

```bash
git status --short > .clavity/consult-baseline/after-consult.txt
diff .clavity/consult-baseline/before-consult.txt \
     .clavity/consult-baseline/after-consult.txt && echo "TREE UNCHANGED" || echo "BREACH - tree differs"
git rev-parse --short HEAD
```

Expected: `TREE UNCHANGED`, and HEAD unchanged from Step 1.

**If the tree changed, that is a breach, not a skip.** Surface it to the owner, revert only the paths the
peer touched, and fold nothing from that consult.

- [ ] **Step 6: Verify every factual claim before folding**

The peer states false claims with full confidence — during this plan's own authoring it asserted that three
workflows lacked `pull_request:` triggers when all three have them. **Grep every citation it makes. An
unverified claim does not reach the owner.**

- [ ] **Step 7: Commit nothing.** The briefs live in `.clavity/`, gitignored, never force-added.

---

## Task 2: Put the four rulings to the owner

**Files:** none. This task produces a decision, not an edit.

- [ ] **Step 1: Present each ruling as its own question**

Each carries: the measured fact, the named dispositions from the ROADMAP entry, the peer's recommendation,
and yours. **Do not collapse four rulings into one question** — they are independent, and §17b's includes
KILL, which no other does.

- [ ] **Step 2: HALT until all four are answered**

A hard stop. **Do not infer a ruling from silence, from a prior decision, or from what the code currently
does.** The current state is the status quo the ruling exists to confirm or change; reading it as the
answer would make the ruling vacuous.

**If the owner defers one**, that is legitimate — record it as deferred with the reason, and note which
later step is blocked. §14g gates the spec's step 3, §14f its step 4, §17a its steps 5 and 9.

---

## Task 3: Write the rulings into the ROADMAP

**Files:** `clavity-dotnet/ROADMAP.md` — the §14f, §14g, §17a and §17b entries. **Locate each by its
heading text, never by line number.**

**Re-entry note:** this task is NOT idempotent. Once a ruling is written the entry's `▶ **OPEN...**` marker
is gone, so a blind re-run finds no marker to replace. **On a re-entry, run Step 3's verifier FIRST** — it
reports which of the four are already ruled, and you resume from there.

- [ ] **Step 1: Locate each entry by symbol**

```bash
grep -n "§14f — two shipped artifacts disagree\|§14g — the agy-observations inbox lives INSIDE\|§17a — the shield's debounce key\|§17b — every \`pre-push\` gate reads" clavity-dotnet/ROADMAP.md
```

Expected: four hits. **If any returns nothing, STOP** — the heading changed and this anchor is stale.

- [ ] **Step 2: Write each ruling into its entry**

Each replaces the entry's `▶ **OPEN...**` status marker and adds a ruling block:

```markdown
#### §NNx — <existing heading text unchanged> · ✅ **RULED 2026-08-19**

> **OWNER RULING (2026-08-19).** <the chosen option, stated as a decision not a discussion.>
> **Why:** <the reason, in the owner's terms.>
> **What this means for the plan:** <which later step now executes what, or KILLED and why.>
```

**Every ruling must name its chosen option AND its reason.** A ruling recorded without a reason cannot be
re-litigated safely later, because nobody can tell what evidence it rested on.

**§17b's entry must record KILLED or its retained scope.** Silence is not a closure — that is the defect
that left the Stage 2 merge gate open for eight days.

- [ ] **Step 3: Verify all four landed, using the checked-in verifier**

```bash
pwsh -NoProfile -File scripts/check-rulings-recorded.ps1
echo "exit=$?"
```

Expected — the identifier is left-padded into a 6-character field, so the gap is **four spaces**:

```
14f    RULED
14g    RULED
17a    RULED
17b    RULED

OK: all 4 section(s) carry a 'OWNER RULING (' block.
```

and `exit=0`.

**Do not replace this with an inline one-liner.** An earlier inline `awk` version was wrong two ways: it
bounded sections on `#### ` and so **failed silently** on §17b (the next heading is `### §18`), printing
nothing — which reads as "not ruled" to a human and as success to a pipeline; and it matched
case-insensitively, so it certified §14f as RULED **because the entry's OPEN marker contains the words
"needs an owner ruling"**. The marker matched the negation of itself.

- [ ] **Step 4: Prove the check can still fail — four controls, all of which must behave**

```bash
mkdir -p .clavity/scratch/step-1

# 1. FAILING control: the pre-ruling ROADMAP from git. Must exit 1 and name all four.
git show HEAD:clavity-dotnet/ROADMAP.md > .clavity/scratch/step-1/roadmap-before.md
pwsh -NoProfile -File scripts/check-rulings-recorded.ps1 \
  -RoadmapPath .clavity/scratch/step-1/roadmap-before.md >/dev/null 2>&1
echo "expect exit 1: $?"

# 2. PASSING control: the ruled file. Must exit 0.
pwsh -NoProfile -File scripts/check-rulings-recorded.ps1 >/dev/null 2>&1
echo "expect exit 0: $?"

# 3. STALE-ANCHOR control: a section that does not exist must fail LOUDLY, not silently pass.
pwsh -NoProfile -File scripts/check-rulings-recorded.ps1 -Section 99z >/dev/null 2>&1
echo "expect exit 1: $?"

# 4. CROSS-REFERENCE DECOY: a heading that merely MENTIONS a section id, carrying the marker, must not
#    satisfy that section. Assert the PER-SECTION lines, never the exit code.
python -c "
import io
s = io.open('.clavity/scratch/step-1/roadmap-before.md', encoding='utf-8', newline='').read()
s = '## Dependencies on \u00a714f and \u00a717a\n\n> **OWNER RULING (2026-08-19).** decoy.\n\n' + s
io.open('.clavity/scratch/step-1/roadmap-decoy.md','w',encoding='utf-8',newline='').write(s)
"
pwsh -NoProfile -File scripts/check-rulings-recorded.ps1 \
  -RoadmapPath .clavity/scratch/step-1/roadmap-decoy.md 2>&1 | grep -E '^(14f|17a) '
```

Control 4 expects **both decoyed sections to report `NO RULING`**:

```
14f    NO RULING
17a    NO RULING
```

**Control 4 asserts per-section output, never the exit code, and this took two attempts to get right.** An
earlier version compared exit codes — and **the exit code is 1 in both universes**: a sound verifier reports
all four unruled, and a hijacked one reports 14f and 17a as RULED off the decoy while 14g and 17b stay
unruled, exiting 1 either way. Measured against a deliberately hijackable copy of the script. **When a
control's pass condition is reachable by more than one route, it proves nothing.**

**Read exit codes without a pipe.** `$?` after `| head` or `| tail` is the pipe's exit code, not the
script's — that mistake once made a control report success while the script was correctly failing.

- [ ] **Step 5: Confirm no stale OPEN marker survives**

```bash
grep -n "§14f\|§14g\|§17a\|§17b" clavity-dotnet/ROADMAP.md | grep -i "OPEN"
```

Expected: no output. A ruled entry still marked OPEN is the stale-status defect this ROADMAP has had fixed
twice already.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/ROADMAP.md
git commit -m "docs(roadmap): record the four owner rulings - 14f, 14g, 17a, 17b

<one line per ruling: the chosen option and its reason.>

Rulings elicited under AGY-FIRST: peer consulted on both blast radii (knowledge flow,
hooks), every factual claim verified by measurement before reaching the owner, owner
decided. Each entry's OPEN marker is cleared and each carries its reason, so a later
session can tell what evidence the decision rested on.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Push, and close out

**Files:** `origin/main`.

**Owner gate.** Halt and obtain authorisation for **this specific push**. Approving this plan is not it.

**If declined:** move the commit off `main` before doing anything else, then record that in the durable
index and note that the later steps it gates remain blocked.

```bash
git status --short                          # MUST be empty before the reset below
git branch declined/step-1-rulings
git reset --keep HEAD~1                    # --keep, NOT --hard: it ABORTS rather than destroying
git log --oneline -1                       # confirm main no longer carries it
```

🔴 **`--keep`, not `--hard`, and the distinction is the whole safety of this step.** `git reset --hard`
would also destroy any uncommitted work in the tree, and an earlier draft of this block used it with a
comment calling it "safe" — true of the commit, which the branch above preserves, and false of everything
else. **`git reset --keep` refuses outright if local changes would be lost**, which is the behaviour you
want from a command you are running because something already went wrong. The `git status` line above is
belt-and-braces: if it is not empty, stop and deal with that first.

🔴 **Do not simply leave it committed on `main`.** Any later authorised push of `main` — including Task 4
Step 3's — would carry the declined commit with it, satisfying a refused authorisation by way of an
approved one. **A declined change must never be left on a shared branch that something else is going to
push.** (The companion plan's Task 7 Step 6 carries the same rule for the same reason.)

- [ ] **Step 1: Push**

```bash
git push origin main
git fetch origin
echo "unpushed: $(git rev-list --count origin/main..main)"
```

Expected: `unpushed: 0`.

**This fires CI on `main`.** A push touching only `clavity-dotnet/ROADMAP.md` matches the
`clavity-dotnet/**` path filter of `ci-dotnet.yml` and `ci-installer-dotnet.yml` — measured 2026-08-19,
2 of 12 workflows. (Unlike a `pull_request` event, a `push` event evaluates `paths:` against the pushed
commits, which is why this is a subset rather than the full suite.)

- [ ] **Step 2: Read that run**

```bash
gh run list --branch main --limit 5 --json databaseId,name,conclusion \
  -q '.[] | "\(.conclusion // "running")  \(.name)  \(.databaseId)"'
```

**Write the conclusions and the check count into the durable index.**

- [ ] **Step 3: Handle §17b's adverse branch — the one this plan must not leave orphaned**

**If §17b was ruled KILLED**, the sequencing spec's step 7 describes work that will never happen. Remove it
from `docs/superpowers/specs/2026-08-18-implementation-sequencing-design.md` rather than leaving an orphan,
and renumber or explicitly note the gap. **If §17b was ruled to proceed**, leave the spec's step 7 and
record its retained scope there.

Either way this is an explicit step, not an assumption. An earlier combined plan pointed at a step that
contained no such instruction.

**If you edited the spec, COMMIT AND PUSH it — this step runs AFTER Task 4 Step 1's push, so the edit is
not carried by it.**

```bash
git status --short                                    # expect: the spec file, and nothing else
git add -f docs/superpowers/specs/2026-08-18-implementation-sequencing-design.md
git commit -m "docs(spec): <retire step 7 as KILLED | record 17b's retained scope>

Follows the owner ruling on §17b recorded in clavity-dotnet/ROADMAP.md.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
git push origin main
```

**That push needs its own owner authorisation**, like every other — **and if it is declined, leave the edit
committed-but-unpushed and record that in the durable index**, noting that the spec now disagrees with the
ruling until it lands. Do not revert it, and do not fold it into an unrelated later push. (Task 4 Step 1's
gate carries the same branch; this one was missing it, which is the decline-branch class surviving in a
sibling.) And note the `git add -f`: `docs/superpowers/*` is gitignored. **Leaving this edit uncommitted would end the plan with a dirty tree
and a spec that disagrees with the ruling** — which is the stale-artifact defect this whole sequence keeps
finding.

- [ ] **Step 4: Update the durable index**

Record the commit SHA, which rulings landed, that they are pushed, and which later spec steps each
unblocks.

**Done means:** all four rulings written into their entries with option and reason; the verifier green with
its four controls behaving; §17b recorded as KILLED or scoped; pushed; the `main` run read and recorded.

---

## Self-review

**Spec coverage.** Step 1's requirements: all four rulings obtained (Tasks 1-2) and written into the
entries they belong to (Task 3 Step 2), each naming its chosen option and reason (Task 3 Step 2), §17b
recording KILLED or its scope (Task 3 Step 2, Task 4 Step 3), and §14f's opposite-edits nature carried into
the consult (Task 1 Step 2).

**Placeholders.** None. The ruling *content* is by construction unknown — that is what makes it a ruling —
but every step that produces, verifies or records it is concrete.

**Known gaps, and where each resolves:**
1. **The ruling content itself** — resolves in Task 2, by the owner. Not knowable in advance and must not
   be guessed.
2. **Whether §14f's ruling constrains §14g's** — raised as a consult question in Task 1 Step 2; if the
   answer is yes, the two must be taken together rather than independently.
3. **What each ruling means for the spec's steps 3-9** — recorded per-ruling in Task 3 Step 2, then folded
   into the sequencing spec. Not this plan's scope beyond §17b's orphan, which Task 4 Step 3 owns.

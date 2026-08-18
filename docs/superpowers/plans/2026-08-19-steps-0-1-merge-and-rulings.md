# Steps 0-1: PR-gated integration to `main`, and the four owner rulings — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land `feature/injected-context-governance` on `main` through a pull request that runs CI before
anything touches `main`, and — while that CI runs — obtain and record the four owner rulings (§14f, §14g,
§17a, §17b) that gate later steps.

**Architecture:** Integrate `main` into the branch first so every conflict resolves on the branch, push,
then open a PR. Ten of the eleven `ci-*.yml` workflows carry a `pull_request:` trigger with no base-branch
filter, so the PR runs the same jobs a push to `main` would, with `main` untouched. The four rulings are
docs-only and touch no code CI tests, so they proceed concurrently with the CI wait. Rulings are elicited,
never authored: each task produces the decision material and a stub, and halts for the owner.

**Tech Stack:** git, GitHub Actions, `gh` CLI 2.85.0, lefthook (pre-push), PowerShell 7 gates, `just`.

---

## Route decision, and why this plan departs from the spec's step 0

The spec's step 0 says merge to `main`, then read CI, and treats a red CI on `main` as an emergency that
preempts the sequence. Its stated reason: *"CI has NEVER run on it — every workflow is `branches: [main]`
on push."*

**That is true about `push:` and incomplete about the workflows.** Measured 2026-08-19: ten of eleven
`ci-*.yml` also declare `pull_request:` with **no** `branches:` filter, so a PR fires the same jobs with
the same `paths:` filters. Only `ci-installer-dotnet.yml` filters its PR trigger.

**Owner ruling 2026-08-19: PR-gated, integrate first.** The AGY-FIRST consult initially proposed a third
route — pre-emptively adding the missing `pull_request:` triggers — on the claim that `ci-scripts.yml`,
`ci-injected-context.yml` and `ci-member-docs.yml` lacked them. **Refuted by measurement:** all three carry
`pull_request:` with `paths:` identical to their push triggers. Sent back to the files, the peer withdrew
the route and converged on this one. Its two surviving contributions are folded in: integrate `main` into
the branch first so the final merge is a single deterministic node that is safe to abort, and check whether
the branch pre-decides any pending ruling before merging (Task 1, Step 4).

**One consequence to expect:** under this route the spec's *"If CI reds, it PREEMPTS the whole sequence"*
paragraph never fires, because nothing broken reaches `main`. It is not wrong — it is unreachable. Leave it
in the spec; it becomes live again only if a future step merges without a PR.

---

## File Structure

Steps 0-1 create no source files. What changes:

| Path | Responsibility | Task |
|---|---|---|
| `.git` refs (branch, `main`) | integration state — a merge commit on the branch, then a merge to `main` | 2, 10 |
| GitHub PR (new) | the CI vehicle; carries the run whose result gates the merge | 4, 5, 9 |
| `.clavity/scratch/steps-0-1/` | ephemeral: CI failure triage notes, per-ruling consult briefs | 5, 6, 9 |
| `.clavity/seams/rulings-knowledge.md` | AGY-FIRST consult brief for §14f + §14g (one blast radius) | 6 |
| `.clavity/seams/rulings-hooks.md` | AGY-FIRST consult brief for §17a + §17b (one blast radius) | 6 |
| `clavity-dotnet/ROADMAP.md` | the four rulings, written into the entries they belong to | 7, 8 |
| memory index + `project_*` topic file | durable resume point after each landed unit | every commit |

**Why two consult briefs and not one or four.** §14f and §14g are both about the agy-autotrain knowledge
flow and share files; §17a and §17b are both about the hook/gate layer. That is one review surface each.
Batching all four into one consult would force the reviewer to hold two unrelated domains at once — the
thing the spec's cost model rule 2 forbids. Four separate consults would pay the per-consult context cost
twice over for no coverage gain.

---

## Preconditions for this whole plan

- [ ] The owner has authorised the push in Task 3 and the merge in Task 10 **individually**. The standing
      rule is that the owner owns every push; neither is implied by approving this plan.
- [ ] No `--no-verify`, and no `git add -A` anywhere in this plan. Explicit paths only.
- [ ] `docs/superpowers/*` is gitignored (`.gitignore:32`) — committing this plan or any spec needs
      `git add -f`. `.clavity/` is gitignored (`.gitignore:45`) and must **never** be force-added.

---

## Task 1: Pre-flight — verify the state this plan was written against

**Files:**
- Read only. No modifications.

- [ ] **Step 1: Confirm the branch and its divergence**

```bash
cd /c/Users/user/Development/Rust/clavity
git branch --show-current
echo "ahead=$(git rev-list --count main..HEAD)  behind=$(git rev-list --count HEAD..main)"
git rev-parse --short HEAD main
```

Expected: branch `feature/injected-context-governance`; `ahead=337 behind=1`; HEAD `6a585f4`, main `b1317a2`.

**If `behind` is 0**, someone has already integrated `main` — skip Task 2 and record why.
**If `ahead` differs from 337**, new commits landed after this plan was written. That is fine; re-measure
and carry the new number forward. Do NOT edit this plan's number to match — note the delta in the commit.

- [ ] **Step 2: Confirm the tree is clean**

```bash
git status --short
```

Expected: no output. **If anything is dirty, STOP** and resolve it before integrating — a merge on a dirty
tree makes the abort path in Task 2 unsafe.

- [ ] **Step 3: Confirm the PR trigger surface still holds**

```bash
for f in .github/workflows/ci-*.yml; do
  r=$(awk '/^  pull_request:/{p=1;next} p&&/^  [a-z]/{exit} p&&/branches/{print "HAS-BRANCHES"}' "$f")
  printf '%-34s %s\n' "$(basename $f)" "${r:-fires-on-any-base}"
done
```

Expected: 10 files `fires-on-any-base`, `ci-installer-dotnet.yml` `HAS-BRANCHES`.

**This is the load-bearing fact of the whole route.** If it no longer holds — if workflows lost their
`pull_request:` triggers — the PR would show a false green. **STOP and re-decide the route with the owner.**

- [ ] **Step 4: Confirm the branch does not pre-decide any pending ruling**

The discriminator, from the AGY-FIRST consult: an edit **pre-decides** a ruling when it alters the
*mechanism* of ownership — the scripts, skills or gates that dictate who may write a file. An edit to the
*payload* inside a disputed file is ordinary churn.

```bash
git diff main...HEAD -- agy-autotrain/skills/agy-curate/SKILL.md \
  | grep -iE "^[+-].*(canonical text lives|keep it in sync|MUST also update|never touch|driver-owned|may not auto-apply)"
git diff --numstat main...HEAD -- clavity-classic/src/driver_cheatsheet.rs clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs
```

Expected (measured 2026-08-19): the ownership lines show only em-dash-to-hyphen normalisation and one
reflow — **no change to who owns what**; and both byte-pinned literals were updated alongside `core.md`
(`1/1` and `9/8`), so its edit was a properly synced content change.

**If a substantive ownership-language change appears**, the merge would usurp §14f. **STOP** and put it to
the owner before proceeding.

- [ ] **Step 5: Commit nothing**

This task is read-only. Proceed to Task 2 without a commit.

---

## Task 2: Integrate `main` into the branch

**Files:**
- Modify: git refs only — creates a merge commit on `feature/injected-context-governance`.

**Why this direction.** `main` carries `b1317a2` (the `docs/examples/` before/after snapshots, committed
directly to `main` at the owner's direction) which the branch lacks. Merging `main` in first resolves the
divergence **on the branch**, leaving the eventual merge to `main` a single deterministic node. If CI later
reds, you push a fix to the branch rather than untangling a conflict resolution out of `main`'s history.

- [ ] **Step 1: Fetch and confirm what is being integrated**

```bash
git fetch origin
git log --oneline HEAD..main
```

Expected: exactly one commit — `b1317a2 docs(examples): before/after snapshots of one plan and spec through the AGY ceremony`.

- [ ] **Step 2: Trial the merge without committing**

```bash
git merge --no-commit --no-ff main
```

Expected: `Automatic merge went well; stopped before committing as requested` (measured 2026-08-19).

**If it reports conflicts instead**, abort with `git merge --abort`, then resolve them deliberately as
their own unit of work — do not resolve conflicts inside a step whose expected output says there are none.

- [ ] **Step 3: Abort the trial, then perform the real merge**

```bash
git merge --abort
git merge --no-ff main -m "merge: integrate main (docs/examples snapshots) into the governance branch

main carried b1317a2 directly - the docs/examples before/after snapshots. Integrating it
here rather than at merge-to-main time keeps the eventual merge a single deterministic
node that is safe to abort if CI reds on the PR.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 4: Verify the divergence is gone**

```bash
echo "behind=$(git rev-list --count HEAD..main)"
git status --short
```

Expected: `behind=0`, and no output from `git status`.

- [ ] **Step 5: Verify the integrated file actually arrived**

```bash
ls docs/examples/ 2>/dev/null || echo "MISSING - the merge did not bring the examples"
```

Expected: the `docs/examples/` contents listed. **A merge that reports success but leaves the payload
absent is the exact failure a commit-count check would miss.**

---

## Task 3: Push the branch — the ten pre-push gates fire

**Files:**
- Modify: `origin/feature/injected-context-governance` (remote ref only).

**Owner gate.** The standing rule is that the owner owns every push. **Halt here and obtain explicit
authorisation for this specific push** before running Step 2. Approving this plan is not that
authorisation.

- [ ] **Step 1: State what is about to be pushed**

```bash
echo "unpushed: $(git rev-list --count origin/feature/injected-context-governance..HEAD)"
git log --oneline origin/feature/injected-context-governance..HEAD | head -20
```

Expected: 11 unpushed commits (10 before Task 2, plus the merge commit).

- [ ] **Step 2: Push, and let the pre-push gates run**

```bash
git push origin feature/injected-context-governance
```

`lefthook.yml` defines **exactly 10** pre-push jobs, all of which must pass: `seed-sync`, `agy-skills`,
`doc-stubs`, `member-docs`, `user-facing-docs`, `register-hash`, `installer-ascii`, `check-versions`,
`check-plugin-namespace`, `check-ci-filter-coverage`.

Expected: all ten green, then the push completes.

**NEVER pass `--no-verify`.** If a gate reds, that is the gate doing its job — fix the cause. Note that
§17b records these gates read the **working tree**, not the commits being pushed, so a green here is a
statement about your worktree and not strictly about what lands. That defect is one of the four rulings
(Task 7) and is exactly why the PR's CI is the authority, not this hook.

- [ ] **Step 3: Verify the remote actually moved**

```bash
git fetch origin
echo "unpushed now: $(git rev-list --count origin/feature/injected-context-governance..HEAD)"
```

Expected: `unpushed now: 0`.

---

## Task 4: Open the pull request

**Files:**
- Create: one GitHub pull request. No repository files change.

- [ ] **Step 1: Open the PR**

```bash
gh pr create --base main --head feature/injected-context-governance \
  --title "Injected-context governance: land the two-stage branch" \
  --body "$(cat <<'PRBODY'
Lands `feature/injected-context-governance` after Stage 2 was ruled GREEN (2026-08-18).

**Why a PR rather than a direct merge.** Ten of eleven `ci-*.yml` workflows carry a
`pull_request:` trigger with no base filter, so this PR runs the same jobs a push to
`main` would. CI has never run on this branch, so this is its first execution across the
full range - and this way that first run happens with `main` untouched.

**What to watch.** The pinned `yq` install step in `ci-scripts.yml` has never executed in
CI. It is the single likeliest first failure.

**Review posture.** The branch has been through AGY-CAPSTONE (owner-confirmed GREEN) and
AGY-TEST-AUDIT. This PR is the CI gate, not a fresh code review.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
PRBODY
)"
```

- [ ] **Step 2: Capture the PR number and record it immediately**

```bash
gh pr view --json number,url -q '"PR #\(.number)  \(.url)"'
```

**Record the PR number in the durable execution index before doing anything else.** A CI run whose PR
number lives only in this session is a recovery hole — the whole point of Task 5 is that it may take a
long time, and the session may not survive it.

- [ ] **Step 3: Verify CI actually started**

```bash
sleep 20; gh pr checks --watch=false
```

Expected: a non-empty list of checks in progress or queued.

**If the list is EMPTY, do not read that as "green".** An empty check list means no workflow matched — the
false-green case Task 1 Step 3 guards against. **STOP and re-verify the trigger surface.**

---

## Task 5: Read CI — and start Task 6 while it runs

**Files:**
- Create: `.clavity/scratch/steps-0-1/ci-run.md` (ephemeral, gitignored).

- [ ] **Step 1: Watch the run**

```bash
gh pr checks --watch
```

- [ ] **Step 2: Record the outcome, per check**

```bash
gh pr checks --json name,state,link -q '.[] | "\(.state)  \(.name)  \(.link)"' \
  > .clavity/scratch/steps-0-1/ci-run.md
cat .clavity/scratch/steps-0-1/ci-run.md
```

- [ ] **Step 3: Record the verdict where a successor can find it**

Write to the durable execution index: the PR number, the run conclusion, and **the count of checks that
ran**. "CI was read" is unfalsifiable on its own; the check count and conclusions are the evidence.

**Branch here:**
- **All green** → proceed to Task 6 (if not already started) and then Task 10.
- **Any red** → Task 9 triages it. `main` is untouched, so this is not an emergency; it is the expected
  first-run yield of 337 previously untested commits.

**Do not idle while this runs.** Task 6 is docs-only, touches nothing CI tests, and the owner has directed
that it proceed concurrently.

---

## Task 6: Prepare the four rulings — AGY-FIRST consults, batched by blast radius

**Files:**
- Create: `.clavity/seams/rulings-knowledge.md` (§14f + §14g)
- Create: `.clavity/seams/rulings-hooks.md` (§17a + §17b)

**These are design forks in subproject work, so AGY-FIRST applies: consult the peer first, then put the
question to the owner carrying both the peer's recommendation and yours. The owner decides. Never delegate
the decision to the peer.**

- [ ] **Step 1: Snapshot the tree before any consult**

```bash
git status --short > .clavity/scratch/steps-0-1/before-consult.txt
wc -l < .clavity/scratch/steps-0-1/before-consult.txt
```

Expected: `0`.

- [ ] **Step 2: Write the knowledge-flow brief (§14f + §14g)**

The brief must point at files, never at a pasted summary. Include:

- `clavity-dotnet/ROADMAP.md:1080-1113` (§14f) and `:1115-1140` (§14g)
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
  before sending** — it was 0 repo / 71 installed on 2026-08-17, and the count moves every session. The
  entry's conclusion holds and is in fact stronger; only the figures are stale.

Extra questions worth adding (the owner has invited them): whether §14f's ruling constrains §14g's
architectural move or is independent of it; and whether moving the inbox out of the plugin tree changes
who owns `core.md`, since both concern the same flow.

- [ ] **Step 3: Write the hooks brief (§17a + §17b)**

- `clavity-dotnet/ROADMAP.md:1281-1296` (§17a) and `:1298-1317` (§17b)
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
- **§17b's ruling explicitly includes KILL.** The sequencing spec records this: it is 10 gates and
  repo-wide churn for a defect not yet observed to bite. The brief must present KILL as a first-class
  option, not a fallback.

Extra questions: whether §17a's fix re-arming every existing debounce once is acceptable or needs a
migration; and — for §17b — whether a *subset* of the ten gates (the ones whose false-GREEN direction is
reachable) is a coherent middle option, or whether mixed semantics across ten sibling gates is worse than
either extreme.

- [ ] **Step 4: Run both consults, review-only**

Each payload carries: the 🛑 REVIEW-ONLY banner enumerating writing, redirection and scratch dumps as
separate forbidden acts; a sanctioned scratch directory (`.clavity/scratch/steps-0-1/`); and — as the last
line, verbatim — `IF ANYTHING HERE IS AMBIGUOUS OR UNDER-SPECIFIED, ASK ME A QUESTION RATHER THAN GUESSING.`

- [ ] **Step 5: Diff-after — verify the review-only envelope held**

```bash
git status --short
git rev-parse --short HEAD
```

Expected: no output; HEAD unchanged from Step 1.

**If the tree changed, that is a breach, not a skip.** Surface it to the owner, revert only the paths the
peer touched, and fold nothing from that consult.

- [ ] **Step 6: Verify every factual claim before folding**

The peer states false claims with full confidence — it did so in this plan's own route consult, asserting
three workflows lacked `pull_request:` triggers when all three have them. **Grep every citation it makes.
An unverified claim does not reach the owner.**

- [ ] **Step 7: Commit nothing**

The briefs live in `.clavity/`, which is gitignored and must never be force-added.

---

## Task 7: Put the four rulings to the owner

**Files:**
- Modify: none yet. This task produces a decision, not an edit.

- [ ] **Step 1: Present each ruling as its own question**

Each carries: the measured fact, the named dispositions from the ROADMAP entry, the peer's recommendation,
and yours. **Do not collapse four rulings into one question** — they are independent and §17b's includes
KILL, which no other does.

- [ ] **Step 2: HALT until all four are answered**

This is a hard stop. **Do not infer a ruling from silence, from a prior decision, or from what the code
currently does.** The current code state is the status quo the ruling exists to confirm or change; reading
it as the answer would make the ruling vacuous.

**If the owner defers one**, that is a legitimate outcome — record it as deferred with the reason, and note
which later step is now blocked. §14g gates step 3, §14f gates step 4, §17a gates steps 5 and 9.

---

## Task 8: Write the rulings into the ROADMAP

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md` — the §14f entry at `:1080`, §14g at `:1115`, §17a at `:1281`,
  §17b at `:1298`. **Re-locate each by its heading text, not by these line numbers** — Task 2's merge and
  any concurrent edit will have moved them.

- [ ] **Step 1: Locate each entry by symbol, not line**

```bash
grep -n "§14f — two shipped artifacts disagree\|§14g — the agy-observations inbox lives INSIDE\|§17a — the shield's debounce key\|§17b — every \`pre-push\` gate reads" clavity-dotnet/ROADMAP.md
```

Expected: four hits. **If any returns nothing, STOP** — the heading changed and the plan's anchor is stale.

- [ ] **Step 2: Write each ruling into its entry**

Each ruling replaces the entry's `▶ **OPEN...**` status marker and adds a ruling block. The required shape,
matching how §19's settled decision is recorded in this same file:

```markdown
#### §NNx — <existing heading text unchanged> · ✅ **RULED 2026-08-19**

> **OWNER RULING (2026-08-19).** <the chosen option, stated as a decision not a discussion.>
> **Why:** <the reason, in the owner's terms.>
> **What this means for the plan:** <which step now executes what, or KILLED and why.>
```

**Every ruling must name its chosen option and its reason.** A ruling recorded without a reason cannot be
re-litigated safely later, because nobody can tell what evidence it rested on.

**§17b's entry must record KILLED or its retained scope.** Silence is not a closure — that is the exact
defect that left the Stage 2 merge gate open for eight days.

- [ ] **Step 3: Verify all four landed, by property and not by substring**

```bash
grep -c "OWNER RULING (2026-08-19)" clavity-dotnet/ROADMAP.md
for s in "§14f" "§14g" "§17a" "§17b"; do
  printf '%s: ' "$s"
  awk -v s="$s" '$0 ~ s"[^0-9]" && /^#### |^\*\*§/{f=1} f&&/OWNER RULING/{print "RULED"; exit} f&&/^#### /&&!($0~s){print "NO RULING"; exit}' clavity-dotnet/ROADMAP.md
done
```

Expected: count `4`, and each of the four prints `RULED`.

- [ ] **Step 4: Prove the check can fail**

```bash
sed 's/OWNER RULING (2026-08-19)/OWNER RULING (placeholder)/' clavity-dotnet/ROADMAP.md \
  | grep -c "OWNER RULING (2026-08-19)"
```

Expected: `0`. **A check that has never returned its failing answer is not an oracle** — this repo has been
bitten by a verification that counted a substring including its own prose.

- [ ] **Step 5: Confirm no stale OPEN marker survives**

```bash
grep -n "§14f\|§14g\|§17a\|§17b" clavity-dotnet/ROADMAP.md | grep -i "OPEN"
```

Expected: no output. A ruled entry still marked OPEN is the stale-status defect this ROADMAP has already
had fixed twice.

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

- [ ] **Step 7: Update the durable execution index**

Record the commit SHA, which rulings landed, and which later steps each unblocks. **A commit not reflected
in the index is a recovery hole.**

---

## Task 9: Triage CI failures — conditional, only if Task 5 went red

**Files:**
- Create: `.clavity/scratch/steps-0-1/ci-triage.md` (ephemeral)
- Modify: whatever the failures actually implicate. Unknown until measured.

**This task cannot be written to the line level in advance**, because its content is determined by failures
that have never occurred — CI has never run on this branch. Writing speculative fixes here would be
fabricated precision. What can be specified is the procedure.

- [ ] **Step 1: Get the actual failure, not the summary**

```bash
gh run list --branch feature/injected-context-governance --limit 5
gh run view <run-id> --log-failed
```

- [ ] **Step 2: Reproduce locally before fixing**

The standing circuit-breaker: do not iterate remotely by re-pushing to see whether a guess worked.
Reproduce with the local gate — `just test-scripts-fast` for the scripts suite,
`cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests` for the .NET gate.

**Watch the suite cadence:** the whole `just test-scripts` exceeds the 600s cap. Use `test-scripts-fast`
for the inner loop and background `test-scripts-slow`, blocking on `Tests completed` — never on a process
count. **No `Tests Passed:` line means the run ABORTED, not that it passed.** Never run both halves or two
Pester suites at once — the file-lock produces a false red.

**`dotnet test --filter` exits 0 on no match.** Read the test count, not the exit code.

- [ ] **Step 3: Expect the `yq` step first**

`ci-scripts.yml:185-204` installs a pinned `yq` and hard-fails rather than skipping if it is absent:
`"yq install failed: yq is not on PATH"` and `"yq version mismatch: wanted $ver, got '$got'"`. This step
has never executed. The spec predicts it as the likeliest first failure — **recorded so the prediction can
be scored, not so it is assumed.** If it passes, say so; a prediction that is never checked is not a
prediction.

- [ ] **Step 4: Fix on the branch, push, let CI re-run**

Each fix is its own commit with its own message. `main` is untouched throughout — this is why the route was
chosen.

- [ ] **Step 5: Do not dismiss a failure as pre-existing**

"The old code did it too" is not a disposition. A pre-existing defect surfaced by this run is in scope;
dismissing it prevents the measurement, not just the fix.

---

## Task 10: Merge to `main`

**Files:**
- Modify: `main` (remote and local).

**Owner gate.** A second, separate authorisation. Task 3's push authorisation does not cover this.

- [ ] **Step 1: Confirm CI is green on the head commit that will merge**

```bash
gh pr checks
git rev-parse --short HEAD
gh pr view --json headRefOid -q .headRefOid
```

Expected: every check `pass`, and the PR head matching local HEAD.

**Verify the green covers the CURRENT head.** If fixes landed after the last run, an older green is not
this commit's green — the same trap as greening a capstone whose newest commits were never reviewed.

- [ ] **Step 2: Merge**

```bash
gh pr merge --merge
```

Use a merge commit, not squash: the branch's 337 commits carry the capstone and test-audit history that
the ledger rows cite by range. Squashing would orphan every one of those citations.

- [ ] **Step 3: Verify the merge landed and CI fired on `main`**

```bash
git fetch origin && git log --oneline -3 origin/main
gh run list --branch main --limit 5
```

Expected: the merge commit on `origin/main`, and a fresh set of runs from the `push: branches: [main]`
triggers.

- [ ] **Step 4: Read the `main` run too**

The PR run and the `main` run are not identical: `ci-installer-dotnet.yml` filters its PR trigger by
branch, so it may run here for the first time.

**Done means:** merged; CI has RUN on `main`; its result has been READ; and the run conclusion plus check
count are recorded in the durable index. Not merely that the merge succeeded.

- [ ] **Step 5: Update the spec and the index**

Mark step 0 complete in the sequencing spec, recording the actual route taken and the CI outcome. Update
the durable execution index: `main`'s new SHA, the branch's disposition, and the resume point — step 2
(13b), since steps 0 and 1 are now closed.

---

## Self-review

**Spec coverage.** Step 0's requirements: merged (Task 10), CI has run (Tasks 5, 10), result read
(Tasks 5 Step 3, 10 Step 4), red-CI handling (Task 9), the `yq` prediction (Task 9 Step 3), fix-vs-revert
asymmetry (obviated — the route makes revert unreachable, stated in the route section). Step 1's
requirements: all four rulings (Tasks 6-8), written into the ROADMAP entries they belong to (Task 8
Step 2), each naming its chosen option and reason (Task 8 Step 2), §17b recording KILLED or its scope
(Task 8 Step 2), and 14f's opposite-edits nature (Task 6 Step 2).

**Placeholders.** Task 9 is deliberately procedural rather than line-level, and says why: its content
depends on failures that have never occurred. Per the plan-vs-spec discipline, writing speculative line
numbers there would be fabricated precision. Every other task carries exact commands and expected output.

**Type consistency.** Branch name, the four section identifiers, the ten pre-push job names, and the file
paths are used identically throughout, and each was verified against the repository on 2026-08-19.

**Known gaps, and where each resolves:**
1. **Task 9's specifics** — resolve at execution, from the actual run log.
2. **Whether §14f's ruling constrains §14g's** — raised as a consult question in Task 6 Step 2; if the
   answer is yes, the two rulings must be taken together rather than independently.
3. **What the rulings mean for steps 3-9** — recorded per-ruling in Task 8, then folded into the
   sequencing spec. Not this plan's scope.
4. **§17b's adverse branch** — if ruled KILLED, the sequencing spec's step 7 must be removed rather than
   left as an orphan. Flagged in Task 8 Step 2; execute in Task 10 Step 5.

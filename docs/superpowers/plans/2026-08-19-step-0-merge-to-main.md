# Step 0: PR-gated integration of `feature/injected-context-governance` to `main` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land `feature/injected-context-governance` on `main` through a pull request that runs CI before
anything touches `main`.

**Architecture:** Integrate `main` into the branch first so every conflict resolves on the branch, push,
then open a PR. Ten of eleven `ci-*.yml` workflows carry a `pull_request:` trigger with no base-branch
filter, so the PR runs the same jobs a push to `main` would, with `main` untouched. Merge only once green.
**Strictly linear: one CI story, one wait, nothing concurrent.**

**Tech Stack:** git, GitHub Actions, `gh` CLI 2.85.0, lefthook (pre-push), PowerShell 7 gates, `just`.

**Companion plan:** the four owner rulings are `2026-08-19-step-1-owner-rulings.md`, which runs **after**
this one. See "Why these are two plans" below — the split is forced by a measurement, not a preference.

---

## Why these are two plans, and why this one goes first

An earlier combined plan interleaved the rulings with this plan's CI wait, to use the wait productively.
**Four panel rounds produced three severe defects that all traced to that single interleaving** — a push
racing the run being watched, a routing path that skipped the rulings push entirely, and a CI-fix push that
would have smuggled the rulings past their own authorisation gate. Patching each in turn made the structure
worse, not better.

**The split's shape was then settled by measurement, not by preference.** All four ROADMAP entries the
rulings must edit (§14f, §14g, §17a, §17b) exist **only on this branch** — measured 2026-08-19, they are
absent from `main` (`main=0, HEAD=1` for each heading). **A rulings branch cut from `main` therefore cannot
edit them at all.** The rulings can only be written where the entries exist: on `main`, after this merge
lands them there.

So the two plans are sequential by necessity, and this plan owns no ruling work at all. There is nothing
left to interleave, which is why all three defects are gone rather than patched.

---

## Where "the durable execution index" is

- `C:\Users\user\.claude\projects\C--Users-user-Development-Rust-clavity\memory\MEMORY.md` — one line per
  entry, the live resume point only.
- `…\memory\project_steps-0-1-plan.md` — the topic file, where detail goes.

**Do not invent a new location.** A PR number recorded anywhere else is lost to a successor.

---

## Preconditions

- [ ] **TWO remote-mutating operations, each needing its OWN owner authorisation:** the branch push
      (Task 3) and the merge (Task 7). The standing rule is that the owner owns **every** push. Neither is
      implied by approving this plan, and neither is implied by the other.
- [ ] No `--no-verify`, and no `git add -A` anywhere. Explicit paths only.
- [ ] `docs/superpowers/*` is gitignored (`.gitignore:32`) — committing a plan needs `git add -f`.
      `.clavity/` is gitignored (`.gitignore:45`) and must **never** be force-added.

**Convention for "Expected:" lines.** Anything in `backticks` or a code block is **literal** and should
match exactly; the surrounding sentence is connective prose naming which outputs to look at.

**Three standing rules that govern both plans in this pair.** They were written into the companion plan and
apply equally here, so they are stated in both rather than in whichever one happened to earn them:

- **Every measurement ships with its command.** Ordering a measurement and leaving the operator to invent
  the invocation is how a step becomes unexecutable — and the command must be able to return BOTH answers,
  not just the failing one.
- **Read exit codes without a pipe.** `$?` after `| head` or `| tail` is the pipe's exit code, not the
  command's. That mistake once made a control report success while the script was correctly failing.
- **When a control's pass condition is reachable by more than one route, it proves nothing.** Ask what the
  output would be if the bug WERE present; if it is the same output, the control is vacuous however
  carefully it was built.

---

## Task 1: Pre-flight — verify the state this plan was written against

**Files:** read only.

- [ ] **Step 1: Confirm the branch and its divergence**

```bash
cd /c/Users/user/Development/Rust/clavity
git branch --show-current
echo "ahead=$(git rev-list --count main..HEAD)  behind=$(git rev-list --count HEAD..main)"
git rev-parse --short HEAD main
```

Expected, as four separate outputs: `feature/injected-context-governance`; then `ahead=337  behind=1`;
then the two short SHAs.

**If `behind` is 0**, someone already integrated `main` — skip Task 2 and record why.
**If `ahead` differs from 337**, new commits landed after this plan was written. Re-measure and carry the
new number forward; do NOT edit this plan to match — note the delta in the commit.

- [ ] **Step 2: Confirm the tree is clean**

```bash
git status --short
```

Expected: no output. **If anything is dirty, STOP** — a merge on a dirty tree makes Task 2's abort unsafe.

- [ ] **Step 3: Confirm the PR trigger surface still holds**

```bash
for f in .github/workflows/ci-*.yml; do
  n=$(basename "$f")
  if ! grep -q '^  pull_request:' "$f"; then
    printf '%-34s %s\n' "$n" "NO-PR-TRIGGER  <-- BLOCKS THE ROUTE"
  else
    r=$(awk '/^  pull_request:/{p=1;next} p&&/^  [a-z]/{exit} p&&/branches/{print "HAS-BRANCHES"}' "$f")
    printf '%-34s %s\n' "$n" "${r:-fires-on-any-base}"
  fi
done
```

Expected: 10 files `fires-on-any-base`, `ci-installer-dotnet.yml` `HAS-BRANCHES`, and **zero**
`NO-PR-TRIGGER`.

**The `grep -q` guard is load-bearing.** Without it, a file with no `pull_request:` block never sets the
awk flag, so the shell default prints `fires-on-any-base` — **certifying a workflow that does not fire on
PRs at all**, in the step this plan calls the load-bearing fact of the whole route.

- [ ] **Step 3b: Prove that check can fail**

```bash
mkdir -p .clavity/scratch/step-0
printf 'on:\n  push:\n    branches: [main]\njobs:\n  x:\n    runs-on: ubuntu-latest\n' \
  > .clavity/scratch/step-0/no-pr-trigger.yml
grep -q '^  pull_request:' .clavity/scratch/step-0/no-pr-trigger.yml \
  && echo "BAD - control did not fire" || echo "OK - control fires on a push-only workflow"
```

Expected: `OK - control fires on a push-only workflow`.

**If any real file reports `NO-PR-TRIGGER`, the PR would show a green that means nothing. STOP and
re-decide the route with the owner.**

- [ ] **Step 4: Two blockers checked and REFUTED — recorded so they are not re-raised**

```bash
gh api "repos/{owner}/{repo}/branches/main/protection"  # expect: 404 "Branch not protected"
gh auth status | grep -i "token scopes"                 # expect: scopes including 'repo' and 'workflow'
```

Measured 2026-08-19: `main` carries **no branch protection**, so Task 7's merge needs no review approval;
and the token holds `repo` and `workflow`, so Task 4's PR create is permitted. `{owner}/{repo}` are
placeholders `gh` resolves from the checkout — do not hardcode, which would query the upstream from a fork.

- [ ] **Step 5: Confirm the branch does not pre-decide any pending ruling**

An edit **pre-decides** a ruling when it alters the *mechanism* of ownership — the scripts, skills or gates
dictating who may write a file. An edit to the *payload* inside a disputed file is ordinary churn.

```bash
git diff main...HEAD -- agy-autotrain/skills/agy-curate/SKILL.md \
  | grep -iE "^[+-].*(canonical text lives|keep it in sync|MUST also update|never touch|driver-owned|may not auto-apply)"
git diff --numstat main...HEAD -- clavity-classic/src/driver_cheatsheet.rs clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs
```

Expected (measured 2026-08-19): the ownership lines show only em-dash-to-hyphen normalisation and one
reflow — **no change to who owns what** — and both byte-pinned literals were updated alongside `core.md`
(`1/1` and `9/8`), so its edit was a properly synced content change.

**If a substantive ownership-language change appears**, the merge would usurp §14f. **STOP** and put it to
the owner.

- [ ] **Step 6: Commit nothing.** This task is read-only.

---

## Task 2: Integrate `main` into the branch

**Files:** git refs only — creates a merge commit on `feature/injected-context-governance`.

**Why this direction.** `main` carries `b1317a2` (the `docs/examples/` snapshots, committed directly at the
owner's direction) which the branch lacks. Merging `main` in first resolves the divergence **on the
branch**, leaving the eventual merge a single deterministic node. If CI later reds, you push a fix to the
branch rather than untangling a conflict resolution out of `main`'s history.

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

**If it reports conflicts**, abort with `git merge --abort` and resolve them as their own unit of work — do
not resolve conflicts inside a step whose expected output says there are none.

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

- [ ] **Step 5: Verify the integrated payload actually arrived, and record the SHA**

```bash
ls docs/examples/ 2>/dev/null || echo "MISSING - the merge did not bring the examples"
git rev-parse --short HEAD
```

Expected: the `docs/examples/` contents listed, then the new merge SHA.

**If it reports `MISSING`, STOP. Do not proceed to Task 3.** Pushing would publish the broken integration —
you would have observed the corruption and then shipped it. Reset with `git reset --hard ORIG_HEAD` (safe
here and only here: Task 1 Step 2 verified the tree clean, so nothing of yours is at risk), then diagnose
before retrying.

**Record that SHA in the durable execution index NOW, before Task 3.** Until the push, the merge exists
only locally: a successor reading the remote sees no merge and may reasonably re-attempt the integration.
**This window is the hardest point in the plan to diagnose after a session death**, and one line closes it.

---

## Task 3: Push the branch — the ten pre-push gates fire

**Files:** `origin/feature/injected-context-governance` (remote ref only).

**Owner gate.** Halt here and obtain explicit authorisation for **this specific push**. Approving this plan
is not that authorisation.

**If the owner declines:** stop cleanly. Leave the Task 2 merge commit on the local branch — it is harmless
and re-doing it later is free — record in the durable index that the branch is integrated-but-unpushed with
its SHA, and note that Tasks 4-7 are blocked. **Do not delete the merge, and do not look for another way to
get CI to run.** A declined authorisation is a decision, not an obstacle.

- [ ] **Step 1: State what is about to be pushed**

```bash
echo "unpushed: $(git rev-list --count origin/feature/injected-context-governance..HEAD)"
git log --oneline origin/feature/injected-context-governance..HEAD | head -20
```

- [ ] **Step 2: Push, and let the pre-push gates run**

```bash
git push origin feature/injected-context-governance
```

`lefthook.yml` defines **exactly 10** pre-push jobs, all of which must pass: `seed-sync`, `agy-skills`,
`doc-stubs`, `member-docs`, `user-facing-docs`, `register-hash`, `installer-ascii`, `check-versions`,
`check-plugin-namespace`, `check-ci-filter-coverage`.

**NEVER pass `--no-verify`.** If a gate reds, that is the gate working — fix the cause. Note §17b records
these gates read the **working tree**, not the commits being pushed, so a green here is a statement about
your worktree. That is why the PR's CI is the authority, not this hook.

- [ ] **Step 3: Verify the remote actually moved**

```bash
git fetch origin
echo "unpushed now: $(git rev-list --count origin/feature/injected-context-governance..HEAD)"
```

Expected: `unpushed now: 0`.

---

## Task 4: Open the pull request

**Files:** one GitHub pull request. No repository files change.

- [ ] **Step 1: Check whether the PR already exists**

```bash
gh pr view --json number,url -q '"EXISTS: PR #\(.number)  \(.url)"' 2>/dev/null \
  || echo "NONE - proceed to create"
```

**If it already exists, SKIP Step 1b and go to Step 2.** `gh pr create` exits non-zero when a PR is already
open for the head branch, so a re-run after a session death would crash here with no recovery path — and
the death is most likely during the CI wait that follows.

- [ ] **Step 1b: Open the PR (only if Step 1 printed `NONE - proceed to create`)**

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

**Record it in the durable execution index before anything else.** A CI run whose PR number lives only in
this session is a recovery hole, and Task 5 may take a long time.

- [ ] **Step 3: Verify CI actually started**

```bash
gh pr checks
```

Expected: a non-empty list of checks queued or in progress.

**If the list is EMPTY, do not read that as green.** An empty list means no workflow matched — the
false-green case Step 3 of Task 1 guards against. **STOP and re-verify the trigger surface.**

---

## Task 5: Read CI

**Files:** `.clavity/scratch/step-0/ci-run.md` (ephemeral, gitignored).

- [ ] **Step 1: Watch the run**

```bash
gh pr checks --watch
```

This blocks until the run completes. **There is nothing to do concurrently — that was the source of three
defects in the combined plan, and this plan has no other work to interleave.**

- [ ] **Step 2: Record the outcome, per check**

```bash
gh pr checks --json name,state,link -q '.[] | "\(.state)  \(.name)  \(.link)"' \
  > .clavity/scratch/step-0/ci-run.md
cat .clavity/scratch/step-0/ci-run.md
```

- [ ] **Step 3: Record the verdict where a successor can find it**

Write to the durable index: the PR number, the run conclusion, and **the count of checks that ran**. "CI
was read" is unfalsifiable alone; the check count and conclusions are the evidence.

**Branch here:** all green → Task 7. Any red → Task 6. `main` is untouched, so a red is not an emergency;
it is the expected first-run yield of 337 previously untested commits.

---

## Task 6: Triage CI failures — conditional

**Files:** `.clavity/scratch/step-0/ci-triage.md` (ephemeral), plus whatever the failures implicate.

**This task cannot be written to the line level in advance**, because its content is determined by failures
that have never occurred. Writing speculative fixes would be fabricated precision. The procedure can be
specified; the fixes cannot.

- [ ] **Step 1: Get the actual failure, not the summary**

```bash
gh run list --branch feature/injected-context-governance --limit 5
RUN_ID=00000000        # replace with the databaseId of the failing run listed above
gh run view "$RUN_ID" --log-failed
```

**Assign the id to a variable; do not paste it inline as `<run-id>`.** In bash an unquoted `<` is input
redirection, so `gh run view <run-id> ...` fails with `bash: run-id: No such file or directory` **before
`gh` runs at all** — measured. An agentic executor copy-pasting the block would crash on a shell error
that looks nothing like the CI failure it is triaging.

- [ ] **Step 2: Reproduce locally before fixing**

The standing circuit-breaker: do not iterate remotely to see whether a guess worked. Reproduce with the
local gate — `just test-scripts-fast` for the scripts suite,
`cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests` for the .NET gate.

**Suite cadence — these are SEQUENTIAL, not concurrent.** The whole `just test-scripts` exceeds the 600s
cap, so: run `just test-scripts-fast` for the inner loop; **only once it has finished**, run
`just test-scripts-slow` in the background and wait for the string `Tests completed` to appear in its
output — e.g. `just test-scripts-slow > .clavity/scratch/step-0/slow.log 2>&1 &` then poll that log until
the marker appears or the process exits. **Never poll a process count**, which reports "still running" for
an aborted run. **Never run both halves, or two Pester suites, at once** — the file-lock produces a false
red. **No `Tests Passed:` line means the run ABORTED, not that it passed.**

🔴 **And kill the backgrounded suite before looping.** If the slow half fails and you edit and re-run the
fast half, an orphaned `test-scripts-slow` still holding the file lock **guarantees a false red on the next
attempt** — you would then be debugging a lock, not the defect. Confirm nothing is left running before each
new cycle, and terminate it if it is.

**`dotnet test --filter` exits 0 on no match.** Read the test count, not the exit code.

🔴 **CARVE-OUT: a CI-ENVIRONMENT failure cannot be reproduced locally.** Step 3 anticipates exactly this —
the pinned `yq` install failing on the runner — and a healthy local machine passes `test-scripts-fast`
every time. **When the failure is in the workflow file or the runner environment rather than in the code
under test, a remote iteration IS the correct instrument**, because the broken thing exists only there.
What the breaker forbids is *guessing*: before each such push, state in one line what you expect to change
and why, and if two consecutive remote iterations fail to move the error, STOP and reconsider the
diagnosis rather than pushing a third.

- [ ] **Step 3: Expect the `yq` step first**

`ci-scripts.yml:185-204` installs a pinned `yq` and hard-fails rather than skipping if absent:
`"yq install failed: yq is not on PATH"` and `"yq version mismatch: wanted $ver, got '$got'"`. It has never
executed. **Recorded so the prediction can be scored, not so it is assumed.** If it passes, say so — a
prediction never checked is not a prediction.

**And here is the command to score it, which the plan previously omitted.** Step 1's
`gh run view <run-id> --log-failed` shows *only failed steps* — by construction it can never show you a
`yq` step that PASSED, so it cannot answer this question in the case the prediction is wrong:

```bash
gh run view "$RUN_ID" --json jobs   -q '.jobs[] | .steps[] | select(.name | test("yq")) | "\(.conclusion)  \(.name)"'
```

(`$RUN_ID` is the variable set in Step 1 — same reason: an inline `<run-id>` is parsed as a redirection
and never reaches `gh`.)

Expected: one line per matching step, e.g. `success  Install yq (pinned)`. **Record the conclusion either
way.** Ordering a measurement without a command that can return BOTH of its answers is the same defect
class as a control that cannot fail.

- [ ] **Step 4: Fix on the branch, push, let CI re-run**

Each fix is its own commit with its own message. **Each push needs its own owner authorisation.** `main` is
untouched throughout — this is why the route was chosen.

**If the owner declines a fix push:** stop cleanly. The fix stays committed on the local branch — harmless,
and it will go up whenever a push is authorised. Record in the durable index that a CI fix is
committed-but-unpushed, with its SHA and the failing check it addresses, and note that the PR still shows
red until it lands. **Do not revert the fix, and do not push it as part of some later operation** — that is
how a commit reaches the remote without ever being authorised.

- [ ] **Step 5: Bound the loop**

**After the THIRD full cycle through this task on the same PR, stop and put it to the owner** — three
cycles without green means the diagnosis is wrong, not that the fix needs another attempt. Record each
cycle's failing check in `.clavity/scratch/step-0/ci-triage.md` so the third decision has the first two in
front of it. Each cycle costs a full CI suite and an owner authorisation.

- [ ] **Step 6: Do not dismiss a failure as pre-existing**

"The old code did it too" is not a disposition. A pre-existing defect surfaced by this run is in scope;
dismissing it prevents the measurement, not just the fix.

- [ ] **Step 7: Return to Task 5, NOT to Task 7**

**Go back to Task 5 and watch the new run.** Do not fall through to Task 7 — its first step expects every
check green, and the fix you just pushed has CI still running, so an operator reading linearly would arrive
at a gate that cannot yet pass and be stranded there. **The loop is Task 5 → Task 6 → Task 5**, and only a
green Task 5 routes onward to Task 7.

🔴 **First confirm the NEW run exists, or the loop eats itself.** GitHub takes a few seconds to spawn a run
after a push. `gh pr checks --watch` fired immediately can evaluate the PREVIOUS run — the red one you just
fixed — report it complete, and send you straight back here to re-triage a failure that is already fixed.
**That is an unbounded loop over a stale head**, and it is the same race, in the opposite direction, as the
one round 3 found between the rulings push and the CI watch.

```bash
gh pr view --json headRefOid -q .headRefOid   # must equal the SHA you just pushed
gh run list --branch feature/injected-context-governance --limit 3   --json headSha,status,name -q '.[] | "\(.status)  \(.headSha[0:7])  \(.name)"'
```

**Proceed to Task 5 only when a run is listed against the SHA you just pushed.** If none is, wait and
re-run the command — do not start the watch against the old head.

---

## Task 7: Merge to `main`

**Files:** `main` (remote and local).

**Owner gate.** A second, separate authorisation. Task 3's push authorisation does not cover this.

**If the owner declines:** stop cleanly. The branch stays pushed and the PR stays open — both are harmless,
and the CI result remains valid for whenever the merge is authorised. Record in the durable index that the
PR is green-and-unmerged with its number, and note that the step-1 plan is blocked, because the four
ROADMAP entries it edits reach `main` only through this merge. **Do not close the PR, and do not merge by
another route.**

- [ ] **Step 1: Confirm CI is green on the head that will merge**

```bash
gh pr checks
git rev-parse HEAD
gh pr view --json headRefOid -q .headRefOid
```

Expected: every check `pass`, and the PR head equal to local HEAD.

**Verify the green covers the CURRENT head.** If fixes landed after the last run, an older green is not
this commit's green — the same trap as greening a capstone whose newest commits were never reviewed.

- [ ] **Step 2: Merge**

```bash
gh pr merge --merge
```

Use a merge commit, not squash: the branch's 337 commits carry the capstone and test-audit history the
ledger rows cite by range. Squashing would orphan every one of those citations.

- [ ] **Step 3: Verify the merge landed and CI fired on `main`**

```bash
git fetch origin && git log --oneline -3 origin/main
gh run list --branch main --limit 5
```

Expected: the merge commit on `origin/main`, and a fresh set of runs from the `push: branches: [main]`
triggers.

- [ ] **Step 4: Read the `main` run too, and record it**

The PR run and the `main` run are not identical: `ci-installer-dotnet.yml` filters its PR trigger by
branch, so it may run here for the first time.

```bash
gh run list --branch main --limit 5 --json databaseId,name,conclusion \
  -q '.[] | "\(.conclusion // "running")  \(.name)  \(.databaseId)"'
```

**Write that output and the check count into the durable index.**

**Done means:** merged; CI has RUN on `main`; its result has been READ; and the run conclusion plus check
count are recorded in the durable index. Not merely that the merge succeeded.

- [ ] **Step 5: Move the local checkout to `main` — the seam the next plan stands on**

```bash
git checkout main
git pull origin main
git rev-parse --abbrev-ref HEAD
git log --oneline -1
```

Expected: `main`, and the merge commit as HEAD.

🔴 **Without this step the seam between the two plans is physically broken.** `gh pr merge` mutates the
REMOTE; it leaves this checkout sitting on the feature branch. The step-1 plan opens with a hard
precondition asserting `git rev-parse --abbrev-ref HEAD` is `main`, so it would fail on entry — plan 1
promising a state it never establishes. **This is the defect class a split introduces**: the combined plan
never needed the bridge because it never crossed a boundary.

- [ ] **Step 6: Update the spec and the index, and unblock step 1**

Mark step 0 complete in `docs/superpowers/specs/2026-08-18-implementation-sequencing-design.md`, recording
the route taken and the CI outcome. Update the durable index: `main`'s new SHA, the branch's disposition,
and the resume point.

**COMMIT AND PUSH the spec edit — nothing else in this plan carries it.** You are on `main` after Step 5,
and the merge is already done, so this edit is stranded otherwise:

```bash
git status --short                     # expect: only the spec file
git add -f docs/superpowers/specs/2026-08-18-implementation-sequencing-design.md
git commit -m "docs(spec): mark step 0 complete - branch merged to main

Records the route actually taken (PR-gated) and the CI outcome.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
git push origin main
```

Note the `git add -f`: `docs/superpowers/*` is gitignored. **That push needs its own owner
authorisation**, like every other. **If declined, leave the edit committed-but-unpushed and record that** —
do not revert it.

**This is the sibling of a defect round 5 found in the companion plan and fixed only where it was cited.**
The same "edit a tracked file after the last push, never commit it" shape existed here and survived,
because the fix was applied to the instance rather than to the class.

**Then start `2026-08-19-step-1-owner-rulings.md`** — its four ROADMAP entries reached `main` through the
merge you just performed, which is what makes that plan's precondition satisfiable.

---

## Self-review

**Spec coverage.** Step 0's requirements: merged (Task 7), CI has run (Tasks 5, 7), result read (Task 5
Step 3, Task 7 Step 4), red-CI handling (Task 6), the `yq` prediction (Task 6 Step 3). The spec's
fix-vs-revert asymmetry is obviated: under this route nothing broken reaches `main`, so the revert path is
unreachable — stated in "Why these are two plans".

**Placeholders.** Task 6 is procedural rather than line-level and says why. Every other task carries exact
commands and expected output.

**Known gaps, and where each resolves:**
1. **Task 6's specifics** — resolve at execution from the actual run log.
2. **§17b's adverse branch** — if that ruling comes back KILLED, the sequencing spec's step 7 must be
   removed rather than left as an orphan. **That is step-1 plan work, not this plan's**, and it is named
   there rather than assumed covered here.

# Phase 1 - AGY-AFTER review record

Companion to `2026-09-02-phase-1-output-reply-contract.md`. **The plan is the instructions; this is the
history.** They were one file until round 3, when a Fresh Implementer seat made the case that a reader
handed the plan must parse ~150 lines of review history to reach the actual code changes - the artifact
had drifted from instruction into a record of its own review.

The discipline requires a durable record because a clean panel round may produce no commit at all. That
requirement is satisfied by a committed sibling; it does not require the record to sit inside the
instructions. The plan keeps its `## Stand-downs` section, which is short and load-bearing.

## Panel round 1 - dispositions (AGY-AFTER, 2026-09-02)

Solo floor (10 seats) + agy escalation (`code-reviewer` subagent, 10 seats). **16 findings, 15 FOLDED,
1 REJECTED by measurement.** Verdict of the escalation round: `REQUEST CHANGES`.

- `FOLDED: the mutant regex could not match the clause it perturbs` - '^Put' vs '**Put'; test and linter
  disagreed about one string, so Task 1 could never have passed.
- `FOLDED: the confidence invariant was conditional on the word it guards` - removable by deletion, and
  it also treated a common English noun as banned. Now unconditional.
- `FOLDED: the reply declared its own schema` - the peer declaring what it may emit always passes. Moved
  to a checker-owned registry.
- `FOLDED: the checker required a "discipline" key no task ever tells the peer to emit` - it would have
  rejected 100% of real replies while looking strict. The driver now names the discipline on the CLI.
- `FOLDED: check_row_schema was defined and never called` - replacing the old constant would have left
  the script crashing on a deleted name.
- `FOLDED: norm() flattened leading indentation` - every indented citation would become unresolvable,
  trading one false-drift class for a larger one. Only trailing whitespace is dropped now.
- `FOLDED: the checker aborted on the first bad row` - hiding all later drift, the same silent-drop shape
  as the bug it replaces.
- `FOLDED: Step 4 demanded proof of a normalisation row that was never written` - the row now exists.
- `FOLDED: Task 5's isolation is destroyed by any task merging before it` - execution order is 1, 5, 2, 3, 4.
- `FOLDED: Task 3 Step 3 had no insertion anchor` while Task 1 did.
- `FOLDED: the "guards prove text, not obedience" claim was too broad` - Task 4 IS an obedience check.
- `FOLDED: the Pester suite leaked a temp file per row per run` - AfterAll now removes them.
- `FOLDED: a second suite was going into a cap-adjacent half unmeasured` - defaults to slow.
- `FOLDED: no suite had ever invoked python` - the new one skips visibly when it is absent.
- `FOLDED: the plan named no execution order for its own tasks` - now stated explicitly.
- 🔴 `REJECTED: "Set-ItResult was removed entirely in Pester 5+, so the skip will crash CI"` - **FALSE,
  killed by measurement.** `Get-Command Set-ItResult` resolves from Pester 6.1.0, and
  `scripts/tests/check-plugin-drift.Tests.ps1:370` ships a row using it that passed 18/18 the same day.

⚠ **A defect this round found in the REVIEW, not the artifact.** The first fold pass reported success on
a replacement that silently did not apply, because the script asserted nothing - so a commit message
claimed a fix that was not in the tree. Root cause, measured: backslash escapes were mangled in transit
(`` arrived as a backspace byte), so the anchor could never match. **Every fold in this plan is now
applied under a hard assertion, and one by line surgery rather than string replace.** The lesson is the
one the repository already knows and it was violated while folding a finding about exactly it: a mutation
that is not asserted did not happen.

## Panel round 2 - dispositions (AGY-AFTER, 2026-09-02)

Rotation added **State Corruptor** (dropped in round 1) and a bespoke **Execution Order Auditor**,
because round 1 REWROTE the execution order and nothing had reviewed the rewrite. **9 findings, 9 FOLDED,
0 refuted.** Six seats returned "no new findings" WITH an explicit statement of what they did not examine.
Escalation verdict: `REQUEST CHANGES`.

- `FOLDED: the inserted clause WRAPS across a newline while the linter and mutant match a contiguous
  string` - MEASURED: the phrase sits across lines 242-243 and both matchers searched for it with literal
  spaces, so the linter would have RED on a skill that correctly carries the clause. Both matchers are now
  whitespace-tolerant AND the phrase is kept unwrapped: a guard that breaks when prose re-wraps is a time
  bomb, so fixing only one side would have left it armed.
- `FOLDED: Step 4 told the implementer to break norm() and never to restore it` - MEASURED: the word
  "restore" appeared ZERO times in the plan. A literal implementer commits the crippled checker.
- `FOLDED: a temporal paradox I introduced while fixing something else` - the order says run Task 5
  immediately after Task 1, while Task 5 demanded a baseline from a round run AFTER Task 1 shipped. Task 5
  now generates BOTH arms itself, which removes the dependency on history and is a better experiment.
- `FOLDED: the Goal claimed every step is independently shippable; Task 4 is not` - it hardcodes
  `claim-type`, which Task 2 introduces. Shipping 4 before 2 rejects 100% of replies still using the old
  word - the same failure mode the panel caught once already in this plan.
- `FOLDED: the _partition.md row said 3 tests; the suite has 6` - the suite doubled during review and the
  figure went stale. That count is mechanically enforced by re-running discovery, so it reds the gate.
- `FOLDED: the "reports EVERY bad row" test never entered the code it names` - its fixture used only
  DECLARED keys, so it exercised citation resolution, not the schema validator. It would have passed with
  the abort-on-first-error behaviour it claims to disprove. Fixture now carries undeclared keys.
- `FOLDED: both plugin halves must be committed together` - the pair gate is fail-closed and runs on push.
- `FOLDED: Task 5's baseline era was ambiguous` - superseded by the both-arms design above.
- `FOLDED: Task 3 anchored on the same paragraph as Task 1` - interleaving the two clauses. Now anchored
  after Task 1's clause.

⚠ **Two of round 2's findings were defects round 1's FOLDS introduced** (the temporal paradox, and the
line-wrap that arrived with the clause text). That is the documented reason to re-run a round after
folding: a fix spawns its own edges.


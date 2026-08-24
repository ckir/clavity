# Test suite partition

**Why the split exists (the state that forced it, 2026-08-01).** `just test-scripts` then ran 358 tests in
a single Pester invocation, measured at 917s, 650s, 586s and 590s on four consecutive runs against a 600s
foreground tool cap. It STRADDLED the cap: it worked until it did not. Those figures are history — the
current, re-measured numbers are further down.

The split is decided by measuring the RECIPE as one batch, not by thresholding per-file numbers.

**Per-file runtime here is not a stable quantity, so it cannot be a rule.** Measured three times on one
commit and machine, the same suite swings up to 5.9x purely on its position in the run, because whichever
suite executes first absorbs pwsh + Pester cold-start for the whole run: `agy-after-reminder` measured
48.9s first and 8.3s last; `release-lib` measured 25.7s first and 4.8s last. Eight of twelve suites were
stable within 15%; four were not. A ">= 20s means SLOW" rule classifies those four differently depending
only on sort order, so it is not reproducible and is not used.

**Batching is not a saving.** The fast half as it stood on 2026-08-02 — 13 suites then, **28 now** — run as
one `Invoke-Pester` process measured 94.2s / 75.1s / 73.7s, against a 65.8s warm per-file sum. One process saves repeated pwsh startup but pays cold module
load once and accumulates across files.

- `just test-scripts-fast` — the agent inner-loop gate. **25 suites, 400 tests** (counts measured 2026-08-25 by Pester
  discovery, after two suites moved to slow). The runtime figure below PREDATES both that move and the
  count guard added the same day - see the 2026-08-24 note under ## Measured runtimes. Previously
  **29 suites, 605 tests, 461,95s** (2026-08-16,
  measured by running the recipe's own suite list and reading its `Tests Passed:` line; **`-NoProfile`,
  for the reason in the operator-environment note below**). The previous line read
  **29 suites, 581 tests, 680,47s** (2026-08-12) — same suite count, 24 more tests.
  **That 680,47s duration was CONTENDED and must not be quoted as a clean figure:** the driver was editing
  files and running greps throughout, and this box has measured 2,23x contention. The count is firm; the
  time is an upper bound.
  `check-curate-in-progress.Tests.ps1` reached **20 rows** here — it joined at 11, took 5 more across the
  capstone folds, and gained 4 in the test-audit closure (a behavioural lefthook-wiring row, a glob
  set-equality row, a conditional-key row, and a marker-coupling row). **The behavioural row runs the real
  `lefthook` binary and cost 13,5s of that**, nearly all of it lefthook plus pwsh cold start — expensive
  for one row, though this file has no per-row census to call it the most expensive and does not claim
  one. It THROWS rather than skipping when lefthook is absent, so this half now has a hard dependency on
  `lefthook` being on PATH (CI installs it — see `.github/workflows/ci-scripts.yml`).
  Earlier lines read `29 suites, 572 tests` (no duration — that run was backgrounded without a timer) and
  before it `28 suites, 554 tests`, with
  two samples on 2026-08-11 reading 410,05s and 913,08s. The previous line here read
  `25 suites, 328 tests, 429,46s solo` (2026-08-06;
  that 429,46s was taken at 327 tests — see the count-correction entry below). **The counts are firm; the
  time is not.** Samples across this recipe now span **255 / 410 / 429 / 738 / 913s**, and no sample in
  this file was taken with machine load actually measured — "solo" here has only ever meant "the driver
  believed nothing else was running", and **the driver shares a CPU with the suite, so a driver that works
  during a run slows it down by construction** (see the contention entries below). **Do not quote any
  single figure here as the recipe's runtime**, do not read the fast half as cap-safe on the strength of
  one sample, and background it rather than assuming it fits the 600s foreground cap.
- `just test-scripts-slow` — everything else. **24 suites, 626 tests** (counts measured 2026-08-25; this half
  GAINED `agy-curate-nudge` and `check-injected-context` that day). The runtime below predates that
  move. Previously **19 suites, 382 tests, measured 1346,49s solo** (2026-08-17,
  after the capstone added `check-ci-filter-coverage` to this half and none to fast; the anomaly hot-fix
  batch before it had added five, also all to this half). **ALWAYS MEASURE, EVEN THOUGH DERIVING IS OFTEN
  RIGHT** — and both outcomes are on record here. Deriving 364 + 13 predicted 377 when the truth was 379
  (two tests had drifted in between, unnoticed); one round later, deriving 379 + 7 predicted 386 and the
  measurement agreed exactly. The point is not that arithmetic fails, it is that a derived total inherits
  every change since the last measurement WITHOUT SAYING SO, and you cannot tell the two cases apart
  without running it.
  NOT on any git hook; it is **well past the 600s foreground tool cap** — 653,5s, 761,28s, 819,2s, 1300,19s,
  1274,72s, 1386,48s, 1437,60s, 1439,52s, 1476,67s, 1402,44s, 1352,36s, now 1346,49s —
  and must be BACKGROUNDED by an agent, blocked on by reading its own `Tests completed` line, never by
  watching a process count. **A backgrounded run can also be STOPPED before it finishes** (one was, at 9
  of 13 suites, on 2026-08-06): a log with no `Tests Passed:` line is an ABORTED run, not a passing one,
  and its zero failures mean only that nothing had failed YET.
- `just test-scripts` — both, unchanged in meaning: still every test.

**The runtime target is ~120s, and it is a TARGET, not an enforceable invariant.** Do not gate anything on
it. Day-to-day variance on this machine exceeds the margin it would police: the SAME 162-test fast half
measured ~95s on 2026-08-01 and 125.6-128.5s on 2026-08-02 (a 33% swing on identical code), and the slow
half measured 1192.6s on 2026-08-01 and 469.5s / 503.6s on 2026-08-02 (a factor of 2.5). The dominant
variable is what else the machine is doing, including the driving agent's own tool calls — the same CPU
runs the tests and the agent. Two consequences, both learned the hard way:

1. **Never conclude from one sample.** Take at least two, as the sole command in their message.
2. **Never predict a partition change by SUBTRACTION.** Moving the 78.4s `agy-consult-guard` suite out of
   the fast half was predicted (twice, independently) to land it at ~113s. It measured ~127s. Whichever
   suite runs first absorbs pwsh + Pester cold-start for the whole batch, so removing a suite does not
   remove its share of that cost — it redistributes it. Measure the recipe after the move, every time.

**Neither recipe is wired to `lefthook.yml`, deliberately.** The full suite used to run on pre-push and
was removed because git opens the SSH connection before the hook and the idle time made GitHub hang up
mid-push (`lefthook.yml:11-18`). This split exists to solve the 600s *foreground tool cap* an agent hits,
which is a justfile concern only.

**Every test remains reachable from some recipe. The invariant is STRUCTURAL, not numeric:** every
`*.Tests.ps1` in this directory appears in exactly one of the two halves. The oracle is

```bash
diff <(ls scripts/tests/*.Tests.ps1 | xargs -n1 basename | sort) \
     <(grep -oE "scripts/tests/[A-Za-z0-9._-]+\.Tests\.ps1" justfile | xargs -n1 basename | sort -u)
```

which exits 0 when clean and names the orphan when a suite is unreachable. **Do not pin a test COUNT as
the invariant** — 358 was pinned once and was wrong by the next task, because every milestone that adds a
test raises it. The count today is fast **400** and slow **626**, **both measured, not added up**
(re-measured 2026-08-25 by Pester discovery: 1026 tests over 49 containers; 400 + 626 = 1026).
🔴 **And it decayed a THIRD time, within hours, exactly as the paragraph below predicts.** The
figures were 399/1025 for two commits because they were computed by ARITHMETIC before `ba4fa4f` added
one test to `agy-autotrain-installer` - a FAST suite. The count guard caught the per-row drift (its row
still said 7) and redded; the aggregate prose here is outside what that guard checks, so it went stale
in the same commit that fixed the row. **Add a test, and THREE numbers here move: the half, the total,
and the sum. Only the per-row one is enforced.**
🔴 **This sentence decayed AGAIN.** It was corrected on 2026-08-16 for exactly this reason and went
stale once more when two suites changed halves on 2026-08-24. The count guard in
`test-suite-registration.Tests.ps1` pins the PER-ROW numbers but not this prose, so it will keep
decaying unless whoever moves a suite edits here too. It is a
fact, not a contract, and it was 358 / 363 / 368 / 372 earlier — and this very sentence said
"fast 177 and slow 238" until 2026-08-06, having decayed through five intervening entries below that each
recorded a new number without updating it. **It was updated in place on 2026-08-16 for exactly that
reason** — both halves were re-measured that day and this sentence is where the previous decay was
recorded, so leaving it would have repeated the failure it documents.

🔴 **AND THE FIRST 2026-08-16 EDIT GOT THE FAST NUMBER WRONG, WHICH IS THE LESSON.** It marked fast as
"328 (STALE), stale by a known amount" — reasoning that the hot-fix batch added four rows and no suites,
so the figure was "off by four" and would be 332. **Measured hours later: 605.** The 328 was not four
stale, it was **277** stale, having decayed since 2026-08-06 through changes that had nothing to do with
that batch. **Estimating the size of a drift you have not measured is the same error as quoting the
decayed number** — it manufactures false precision about an unknown. If you have not measured it, say
only that it is stale.

**Since 2026-08-06 the structural invariant is ENFORCED, not just documented.**
`scripts/tests/test-suite-registration.Tests.ps1` runs that `diff` as a test: every suite on disk is in
exactly one half, no recipe names a file that is gone, and no suite sits in both. Before that it was a
command in this file that nothing invoked — and `just test-scripts` globs the directory, so an
unregistered suite ran there and reported green while appearing in NEITHER gate anyone uses.

Fast was re-measured five times on 2026-08-03, every time by running the recipe: **166 / 143,9s** when
`agy-curate-nudge.Tests.ps1` was added at 4 tests, **169 / 145,3s** after capstone round 1 added 3 more,
then **171 / 132,3s** after capstone round 2 added 2 more, and **173 passed / 0 failed in 145,9s**
after capstone round 3 added 2 more. A fifth run, after the cost-clause work added 2 tests to
`agy-after-reminder`, measured **175 passed / 0 failed in 150,6s**. A sixth, after
`plugin-hooks-payload.Tests.ps1` was added as a NEW 15th fast suite at 2 tests, measured
**177 passed / 0 failed in 124,6s** — note the run got FASTER while gaining a suite, which is the
run-order/cold-start effect this file warns about, not a speed-up.

Slow WAS re-measured on 2026-08-03, at the same time, as the sole command on the machine:
**238 passed / 0 failed in 653,5s**. Note what that number exposes — the previously recorded slow
count was **210**, and the cost-clause work added only 6 tests to that half. The other ~22 arrived
from intervening epics that never re-measured this half. **A count in this file decays silently
whenever a suite in the OTHER half is edited; treat any figure here as stale until you re-run the
recipe.** Do not reconcile a surprise like that by arithmetic — the measurement is the fact.

**2026-08-04 — the AGY-ANOMALIES capture-gap change.** Four NEW fast suites landed together
(`plugin-hooks-registration`, `agy-anomaly-capture-reminder`, `agy-anomaly-dispatch-reminder`,
`agy-anomaly-model-notice`), and `check-seed-artifacts-synced` gained 3 tests. Fast went 15 suites / 177
tests to **19 suites / 234 tests**, measured **251,8s then 244,0s** — the first two-sample fast entry in
this file. Slow was measured in the same pass, backgrounded and alone: **238 passed / 0 failed in
761,28s**, its test count unchanged at 238 while its time rose from 653,5s.

**2026-08-04 (later) — the AGY-ANOMALIES contract stamp.** One NEW fast suite
(`agy-anomaly-contract-stamp`, 14 tests) covering the stamp across all three model-addressed hooks and
BOTH drivers, plus **+1 test in `agy-anomaly-model-notice`** pinning its triage directive WHOLE (it was
the only one of the three whose message text was asserted NOWHERE; a mutation proved the pre-existing
bookend assertions all PASSED against a gutted directive). Fast went 19 suites / 234 tests to **20 suites / 249 tests**, measured **231,18s then 220,0s** — faster
than either prior sample despite +14 tests, which is the run-order swing this file already warns about and
NOT evidence the new suite is free. Slow was not re-run in this pass; its 238 / 761,28s entry above is
therefore the newest slow figure and is now one change stale.

**2026-08-04 (later still) — the discipline-reaching recorder.** One NEW fast suite
(`agy-discipline-reaching`, 16 tests). Fast went 20 suites / 249 tests to **21 suites / 265 tests**,
measured **279,58s**. At 69,1s the new suite is now the SECOND-largest in the fast half after
`check-seed-artifacts-synced`; each of its cases spawns a bash hook against a synthetic transcript, so the
cost is real rather than cold-start. It is still fast-half by measurement, but the fast half is now the
first place to look if that recipe starts straddling a cap again.
**↳ SUPERSEDED as of 2026-08-05: that suite is now 15,2s and FIFTH, because `6b87f1f` moved the transcript
scan out of the hook. The paragraph above is kept as the record of what was true when it was written.**

**2026-08-04 (last) — the reaching REPORT (the consumer).** One NEW fast suite
(`discipline-reaching-report`, 11 tests, 8,1s - it invokes a PowerShell script rather than spawning bash
hooks, which is why it is an order of magnitude cheaper than the recorder suite next to it). Fast went
21 suites / 265 tests to **22 suites / 276 tests**, measured **290,53s**.

**2026-08-04 (final) — the scripts/README inventory guard.** One NEW fast suite
(`scripts-readme-inventory`, 3 tests, 4,2s). Fast went 22 suites / 276 tests to **23 suites / 279 tests**,
measured **346,4s**. Added because `scripts/README.md` is an inventory index
(`check-user-facing-docs.ps1:62` names it as one) and nothing verified it was complete — it drifted the
same day, when a new script was added and the index was not updated.

**2026-08-05 — the recorder moves to SessionStart.** NO new suite; the fast half stays **23 suites**. Three
existing suites grew: `discipline-reaching-report` 11 → 22, `plugin-hooks-registration` 18 → 22, and
`agy-discipline-reaching` 13 → 16. Fast went 279 recorded tests to **294 tests**, measured **520,16s then
292,09s**.

🔴 **THAT 1,78x SPREAD IS THE MOST USEFUL NUMBER IN THIS ENTRY, and it is on IDENTICAL code** — same
commit, same machine, back-to-back, 294/294 green both times. It is hard evidence for the rule this file
already states: day-to-day variance here exceeds any margin a time-based partition rule could police. The
first sample was taken immediately after a long editing session and the second was not; that is a
plausible cause (cold cache, or an antivirus pass over freshly-written files) and it is NOT measured, so
do not repeat it as fact. **The operational lesson: one sample of this recipe is not a measurement. Two
disagreeing samples are.** A single slow reading is not evidence of a regression - it very nearly sent a
reader hunting one here.

**2026-08-05 (later) — the AGY-CAPSTONE folds.** Still **23 suites**; no suite added. The capstone put
**9 more tests** into `discipline-reaching-report` (22 -> 31) across three fold commits. Fast went 294 to
**303 tests**, measured **366,46s** — a third sample of this recipe, and it lands between the two taken
earlier the same day (520,16s and 292,09s) on code that differed by nine tests. **Three samples now
bracket 292-520s. Treat any single figure from this recipe as an anecdote.**

**2026-08-05/06 — the pre-release defect sweep (the `.no-agy` repo-root walk).** TWO new fast suites:
`agy-drive-session-reset` (6 tests — the only hook in the agy set that DELETES rather than prints, and it
had never had a suite) and `test-suite-registration` (4 tests). Six existing suites grew, four of them in
the slow half. Fast went 23 suites / 303 tests to **25 suites / 327 tests**; slow stays **13 suites** and
went 238 to **257 tests**.

Fast measured **429,46s solo**, then **665,4s** on a second sample — but read the next paragraph before
comparing them.

🔴 **THE SECOND FAST SAMPLE IS CONTENDED AND IS NOT COMPARABLE TO THE FIRST.** It was launched while
`test-scripts-slow` was still running on the same machine, which is precisely the dominant variable this
file warns about, and it is a measurement error rather than a finding. It is recorded instead of discarded
because of what it shows: **under contention the FAST half took 665,4s and blew the 600s foreground tool
cap**, getting moved to the background by the harness. The fast half is the agent inner-loop recipe; it is
supposed to be the one that never straddles the cap. It does not straddle it solo — 429,46s — but it has
no headroom left for a machine that is doing anything else. **Do not run the two halves concurrently, and
treat the fast half as cap-adjacent, not cap-safe.**

🔴 **2026-08-06 (count correction) — THE FAST COUNT IS 328, AND THIS FILE SAID 327 FOR THREE COMMITS.**
Re-measured by running the recipe: **328 passed / 0 failed**, and the per-suite breakdown of that same run
sums to 328 independently. The 327 above was **not a miscount — it was true when written and then
decayed in 40 minutes**: `c58056a` (01:49) re-measured the partition after the defect sweep and correctly
recorded 327; `413c617` (02:29) added a third test to `plugin-hooks-payload.Tests.ps1` — *"gates every
repo-root walk on one stat, and stops at the UNC volume root"* — and did not re-measure this file. The
suite's row said `2 tests`; it has three. **That is the third row in this file to decay exactly this way**
(`agy-discipline-reaching`, `abort-drain`, now `plugin-hooks-payload`), and the first where the total and
the row were wrong *consistently*, which is the dangerous shape: adding the rows up reproduces the wrong
total and reads as corroboration. This file already forbids that arithmetic — **"both measured, not added
up"** — and this is why.

**How it surfaced is the reusable part:** a plan pinned 328 from its own measurement, this file said 327,
and the disagreement sat unresolved as a known-open question rather than being measured. Resolving it cost
one recipe run. **Two artifacts disagreeing about a measured number is not a tie — it is an unrun
measurement.**

**A fourth data point for the contention rule, and the most extreme yet: 737,5s.** That run was launched
backgrounded while the driving agent kept working — greps, `git commit` with lefthook, file edits — on the
same machine. Nothing else was running; no slow half. **1,72x the 429,46s solo figure, from the agent's own
tool calls alone**, and 137s past the 600s foreground cap. The file already warns that the driving agent's
own work is part of the dominant variable; this measures it. It is **not** comparable to any solo sample
and must not be read as a regression. Operationally: if you need the fast half's *time*, run it as the sole
command; if you only need its *count*, background it and keep working — the count is unaffected.

**And a SECOND solo sample the same day: 254,74s** — same commit range, same machine, deliberately run with
the driver idle, 328/328 green. **That is 1,69x apart from the 429,46s figure recorded above, and both are
"solo".** Three samples now bracket this recipe at **255 / 429 / 738s**. Two consequences:

- **The "cap-adjacent, not cap-safe" reading rests on the 429,46s sample, and 254,74s does not support it.**
  Do not treat either as the recipe's time. The honest statement is that the fast half runs somewhere in the
  250-430s band when nothing else is competing, and blows the 600s cap when something is.
- It is the same lesson this file already states twice (a 1,78x spread on identical code, and
  "one sample of this recipe is not a measurement"), now confirmed a third time. **Stop quoting a single
  figure from this file as if it were the runtime.**

🔴 **`agy-discipline-reaching`'s ROW HAD BEEN WRONG IN BOTH COLUMNS AND NOTHING CAUGHT IT.** The count said
16 while the suite really held 13, and the time said 69,1s while it really ran in ~15s. The figures were
right when written (`d2b8649`); then `6b87f1f` and `872498f` each changed the suite without re-measuring.
The count is only correct today by coincidence - this change added exactly the three tests the row had
been over-claiming. **A file whose job is to be the measured oracle carried a wrong number for two
commits, and the spec and plan for this epic both inherited it.** Nothing enforces this table; re-measuring
after touching a suite is a discipline, not a gate.

Two things that pass are worth recording, because both are the kind of number this file exists to stop
people guessing at:

- **`check-seed-artifacts-synced` is now the largest suite in the fast half at 77,2s.** Its 3 new tests
  each invoke the whole gate, so it absorbed ~21s. It is still fast-half by measurement, but it is the
  first candidate if that half ever needs trimming.
- **The `_partition.md` update was deliberately deferred until every suite had landed.** Registering three
  suites and then measuring, when a fourth was known to be coming, would have written a figure that the
  very next commit falsified — which is precisely how the counts here decayed before.

If you move a file between halves, re-measure BOTH halves and update this file; do not edit it from
memory, and do not compute the new number by subtraction (see above).

**THE SUITE COUNT IS A COUNT TOO — and it decayed silently for longer than the test count did.** On
2026-08-03 this file claimed 13 fast and 12 slow suites while the recipes actually listed 15 and 13.
It went wrong the way the rest of this file warns about: someone adding a suite **incremented the
printed number instead of counting the recipe**, and the error then survived every later edit because
each subsequent editor incremented the already-wrong figure in turn. Do not add one. Count:

```bash
for r in fast slow; do
  printf '%s %s\n' "$r" "$(sed -n "/^test-scripts-$r:/,/^$/p" justfile \
    | grep -oE 'scripts/tests/[A-Za-z0-9._-]+\.Tests\.ps1' | sort -u | wc -l)"
done
```

The `## Measured runtimes` table below is also NOT self-maintaining: `agy-inbox-snapshot.Tests.ps1`
was in `test-scripts-slow` and absent from the table entirely. To find that class of omission,
diff the recipe membership against the table rather than reading down it.

**2026-08-11 — the Stage 2 fix batch.** ONE new fast suite: `check-cheatsheet-budget` (6 tests), the
enforcement half of the driver-cheatsheet budget. Fast went 27 suites / 548 tests to **28 suites /
554 tests**, measured **410,05s**.

**2026-08-12 — that suite DOUBLED, 21,7s -> 43,1s, on a capstone fix.** No test was added; the row count
is still 6. A capstone round defeated the default-pinning assertion twice (once through a `#` comment,
then through a `<#  #>` block comment), so it was rewritten to stop matching source text and instead
INVOKE the script at the byte boundary. That replaced an in-memory string match with two more `pwsh`
spawns - the suite went from 5 to 7 - and process cold-start is what the extra ~21s buys.

🔴 **The correctness of that guard is not in question; the accounting is the point.** The peer flagged the
cost and called it "massive"; the driver dismissed it and estimated "+2-4s" from an assumed 1-2s per cold
start. **Measured solo, it is +21,4s - the peer was closer.** A guard that runs the real thing costs real
process time, and a suite half this file already describes as sitting near a 600s cap has that much less
headroom. Recorded here rather than absorbed silently, because absorbing it silently is exactly the decay
this file exists to catch.

🔴 **THE DRIVING AGENT AND THIS SUITE SHARE ONE CPU. Driver activity during a run is contention BY
CONSTRUCTION, not bad luck.** The agent's harness process, every tool subprocess it spawns (`pwsh`,
`python3`, `rg`, `git`), and the lefthook/rtk hooks that fire on each command all compete with the suite
for the same cores. This is the mechanism behind every "contended" figure in this file, and it is
structural — there is no configuration in which an agent works during a run and does not slow it down.

**Measured 2026-08-11, same commit, same 554 tests, minutes apart: 913,08s with the driver working
(`python3` edits, `rg`/`awk` greps, `wc`, file writes) against 410,05s with the driver idle — 2,23x**, and
the working sample sat 313s past the 600s foreground cap. Caveat on all five samples: **machine load has
never actually been instrumented for any figure in this file.** "Solo" has only ever meant "the driver
believed nothing else was running," so treat the ratio as the expected size of the effect, not as a
controlled measurement.

Recorded for the near-miss it produced: the 913,08s figure was about to be written into the summary line
above as if it were solo, which would have made it the fourth decayed number in a file that documents its
own decay three times. **Two samples disagreeing is not a tie — it is an unrun measurement**, the same
lesson this file already draws from the 327/328 count dispute. Operationally: if you need this recipe's
*time*, run it as the sole command and stay idle; if you only need its *count*, background it and keep
working — the count is unaffected.

**2026-08-16 — the anomaly hot-fix batch moved the slow half by 59%.** Slow went **13 suites / 257 tests /
819,2s** to **18 suites / 364 tests / 1274,72s**, backgrounded and blocked on its own `Tests completed`
line (it now exceeds the foreground cap by more than a factor of two). Five suites joined, all deliberately
routed to SLOW and none to fast: `agy-shield-lib` (34 tests, ~409s on its own), `agy-mark` (26),
`check-cheatsheet-parity` (16, ~136s), `generate-cheatsheet-literals` (12, ~42s) and the previously
ungated `clavity-install` (12). **Four of those five are that batch's new suites; the fifth is an orphan
that ran in no gate at all** — ROADMAP 14b.

🔴 **The routing was a decision, argued once the wrong way and re-affirmed.** `generate-cheatsheet-literals`
is a pure file transform and genuinely quick, and a first draft put it in FAST on that basis. Speed is not
the binding constraint: the fast half is the agent inner-loop recipe and this file already calls it
**cap-adjacent, not cap-safe**. The slow half is backgrounded and already past the cap, so it absorbs new
work at no cost to the loop.

✅ **The fast half WAS re-measured, a few hours later in the same session: 29 suites, 605 tests, 461,95s,
0 failed.** The recorded 328 had decayed by **277**, not by the four this batch added — see the correction
in the count paragraph above.

🔴 **THE RECIPES NOW PASS `-NoProfile` THEMSELVES - this is no longer something to remember.** The recipe USED to invoke plain `pwsh`, which
loads the operator's PowerShell profile. MEASURED 2026-08-16 on this machine: a profile hook around
`Push-Location` raised `The variable '$Script:CPPrevLocationAction' cannot be retrieved because it has
not been set` (`claude-profile-init.ps1:323`), reddening **5 rows in `release-lib.Tests.ps1`** that pass
23/0 in isolation. Two-way control: with the profile it fails, with `-NoProfile` the identical list is
**605/0**. **This is an operator-environment artifact, not a repo defect, and it cannot occur in CI** -
but it cost three wrong bisections here, because every probe used `-NoProfile` while the recipe did not.
**When a suite fails only inside the recipe, check whether your probe and the recipe load the same
profile before hunting cross-suite contamination.**

✅ **CLOSED 2026-08-17 - and the gap between the diagnosis and the fix is the lesson.** The 2026-08-16
discovery produced THIS NOTE and nothing else: it told the operator to type `-NoProfile`, and changed no invocation.
**A rule with no implementation is worse than no rule** - it reads as handled. Twenty-four hours later the same
fault blocked a push through `lefthook`'s `check-versions-all` job, and cost THREE more wrong hypotheses (a
`$PSDefaultParameterValues` entry, an imported module, a profile-defined wrapper) before a `grep -rn CPPrevLocationAction`
found this very paragraph in one command. The note predicted the exact trap it then failed to prevent.

**22 invocations across `lefthook.yml` and `justfile` now carry `-NoProfile`** (3 pre-push gates, the three `test-scripts*`
recipes, and every other `pwsh` call in both files). Prose mentions of `pwsh -File` were deliberately left alone.
**The prior ruling - 'an operator-environment artifact, not a repo defect' - was right about the CAUSE and wrong about
the REMEDY:** the artifact is external, but a runner that inherits an arbitrary operator profile is a repo defect, and
hermetic invocation is the repo's job. ⚠ **`.worktrees/python-gate/` has its own `justfile` and `lefthook.yml` and was
NOT touched** - it is a separate branch with parked work; it needs the same fix on its own terms.

## Measured runtimes

These are per-file numbers taken in one sweep and are INDICATIVE ONLY — the section above explains why a
per-file time is not a stable quantity and is not used as the partition rule. `agy-consult-guard` was
measured separately (2026-08-02) in isolation, as the sole command on a quiet machine.

**2026-08-24 - two suites MOVED from fast to slow, on a measurement.** The AGY-TEST-AUDIT gap closure
added tests to four fast suites, and the fast half was then measured BACKGROUNDED on an idle CPU as ONE
batch at **576,0s against the 600s foreground tool cap** - about 4% headroom, on the recipe that had
already blown that cap once at 665,4s under contention. The closure itself accounts for only ~38s of
that (`agy-curate-nudge` +31s, `plugin-hooks-payload` +4,5s, `drain-lib` +0,8s, the new
`agy-autotrain-installer` +1,3s); the half was already near 538s before it.

Moved: **`agy-curate-nudge`** (48,1s - the suite this work grew) and **`check-injected-context`**
(91,5s - the single largest in the half).

🔴 **THAT PROJECTION WAS WRONG, AND THE MEASUREMENT IS THE POINT OF THIS NOTE.** It predicted
"roughly 435s" and was never run. MEASURED afterwards, backgrounded on an idle CPU, 28 suites as one
batch, THREE consecutive runs: **588,6s / 554,1s / 496,5s** - 462 tests, 0 failed every time.
Mean **546s**, spread **92s (17%)**, trending down across the three, which is the usual warming.

Read it against the 600s foreground cap by the WORST case, not the mean or the warm figure: the cap
bites on a slow run, and the slowest idle sample leaves **11,4s of headroom (1,9%)**. The half is
cap-ADJACENT on this evidence, as it was before the move.

🔴 **A retraction, recorded because the mistake is instructive.** On the strength of the FIRST
sample alone (588,6s) this note briefly claimed the rebalance had made the half WORSE than the 576,0s
measured before it. That claim was not supportable: 576,0s is itself a SINGLE sample, and it sits
comfortably inside the 496-589s range these three runs describe. **One sample cannot be compared to one
sample across a 17% spread.** Whether the move helped, hurt, or did nothing is not resolved by this
data, and saying otherwise repeated - in the act of correcting it - the same derive-rather-than-measure
error the projection made.

**2026-08-25 - a SECOND move, on the owner's ruling, because one move was not enough.** Three more
suites left the fast half: `check-curate-in-progress` (69,5s), `assertion-strength-reminder` (54,9s) and
`check-cheatsheet-budget` (43,1s) - 167,5s by the recorded rows. MEASURED afterwards, backgrounded, 25 suites as one
batch, two consecutive runs: **468,0s then 418,5s** - 400 tests, 0 failed both times.

🔴 **Take 418,5s, and discard 468,0s: run 1 was CONTAMINATED BY THE AGENT.** The orchestrator wrote a
file in the first minutes of that run instead of going idle immediately, and the 49,5s gap between the
two runs is that work. The rule this cost: **a measurement run needs a settle margin at the START, and
the agent must be idle before the clock matters** - launching backgrounded is not the same as being
idle, because preparing the next piece of work is still work. (owner, 2026-08-25)

So the half sits near **420s against the 600s cap** - roughly 30% headroom, against 1,9% at the worst of
the pre-move samples. That is the first figure in this saga that was measured rather than predicted.

🔴 **`check-seed-artifacts-synced` (71,9s) STAYED, and it is the largest suite in the half.** It was
the obvious thing to move on runtime alone. It is a required gate for any byte-identical-pair change -
the standing project rule names it explicitly alongside `plugin-hooks-payload` - so it earns its place
in the inner loop on COVERAGE, not on cost. Partition by what a change needs caught early, then by
seconds; ordering those the other way is how a fast half stops being worth running.

Subtracting 139,6s of moved suites from 576,0s and adding ~21s for the count guard predicts ~457s. Even
the fastest run is 40s above that, and the slowest 131s above. The arithmetic is not the recipe: this
file says so under "Batching is not a saving" and in the derived-total warning above, and the projection
was written as if neither applied. **A projected partition figure is not a measurement: run the half,
more than once, and quote the range.**

Two things about this move are worth keeping. First, the decision was made on the MEASURED batch figure,
not on the sum of the per-file rows - those sum to 531,1s, and the section above explains why a derived
total is not the recipe's runtime. Second, the growth was mostly NOT the new tests: attributing it to
them and moving only those would have left the half at 528s and solved nothing.

```
abort-drain.Tests.ps1                            72,9s   13 tests   <- SLOW, re-measured 2026-08-06. The
                                                                      row said 261,3s: a 3,6x over-claim on
                                                                      an UNCHANGED suite. Nothing edited it;
                                                                      the old figure simply decayed. This is
                                                                      the same failure as agy-discipline-
                                                                      reaching's below, in the other half.
agy-consult-guard.Tests.ps1                     134,4s   11 tests   <- SLOW, moved 2026-08-02; re-measured
                                                                      2026-08-06 (+2 tests: the cross-driver
                                                                      byte-identity check now covers lib.sh
                                                                      too, and the deliberate .no-agy
                                                                      omission is pinned). Now the LARGEST
                                                                      suite in the slow half, past docs-audit.
accept-drain.Tests.ps1                           42,4s   10 tests   <- SLOW, re-measured 2026-08-06
agy-after-reminder.Tests.ps1                      9,7s   14 tests   <- COUNT 2026-08-06 (+4: root-walk
                                                                      silence + control, jq and no-jq).
                                                                      TIME is the 2026-08-05 solo figure.
agy-anomaly-reminder.Tests.ps1                   26,8s   20 tests   <- SLOW, re-measured 2026-08-06 (+4)
agy-anomaly-capture-reminder.Tests.ps1            8,4s   26 tests   <- COUNT 2026-08-06 (+4)
agy-anomaly-dispatch-reminder.Tests.ps1          12,7s   22 tests   <- COUNT 2026-08-06 (+4)
agy-anomaly-model-notice.Tests.ps1               16,7s   11 tests   <- COUNT 2026-08-06 (+2)
agy-drive-session-reset.Tests.ps1                   ?    6 tests   <- FAST, NEW 2026-08-06. NO SOLO TIME
                                                                      YET: its only sweep was the contended
                                                                      one (42,0s there, inflated ~1,55x by
                                                                      the concurrent slow half). Measured
                                                                      26,4s alone as a single suite, which
                                                                      is a different mode again. Re-measure
                                                                      in the next solo fast sweep rather
                                                                      than copying either figure.
test-suite-registration.Tests.ps1                21,9s    8 tests   <- FAST. MEASURED 2026-08-24 WARM on an
  idle CPU (cold 34,5s); the time field was `?` until then. The single count-guard It is 20,9s of that
  21,9s - about 95% - because it spawns a child pwsh and runs Pester DISCOVERY over all 49 suites.
  🔴 The previous note here read "0,7s in the contended sweep... does no I/O beyond reading justfile,
  so it is genuinely near-free". All three clauses were false once the count guard landed, and the guard
  this fold added checks the NUMBER in a row, never its prose - so nothing caught it.
agy-anomaly-contract-stamp.Tests.ps1              5,5s   14 tests   <- FAST, re-measured 2026-08-05
agy-discipline-reaching.Tests.ps1                15,2s   22 tests   <- FAST. The row said 69,1s and it had
                                                                      been WRONG since 6b87f1f split capture
                                                                      from analysis: that figure was measured
                                                                      while the hook still scanned the
                                                                      transcript inline. Its COUNT was stale
                                                                      too - 13 real against 16 recorded -
                                                                      until this change happened to land on
                                                                      16. Two commits changed the suite and
                                                                      neither re-measured. Re-measured
                                                                      2026-08-05.
discipline-reaching-report.Tests.ps1              6,2s   31 tests   <- FAST. Was 8,1s / 11 tests before the
                                                                      SessionStart move; 22 after it; 31
                                                                      after the capstone. It invokes a
                                                                      PowerShell script rather than spawning
                                                                      bash hooks, so it TRIPLED its test
                                                                      count and still got cheaper. The 6,2s
                                                                      figure was taken at 22 tests - the 9
                                                                      capstone tests are not in it.
scripts-readme-inventory.Tests.ps1                0,1s    3 tests   <- FAST, re-measured 2026-08-05
agy-curate-nudge.Tests.ps1                       48,1s   20 tests   <- SLOW as of 2026-08-24; was FAST.
  MOVED with check-injected-context because the FAST half measured 576,0s against the 600s foreground
  cap - see the note under ## Measured runtimes. Re-measured 2026-08-24 WARM on an
  idle CPU (cold 53,6s) after the test-audit closure added 6 tests. The count row had ALSO been stale
  since before that: it said 11 when the file held 14.
agy-inbox-snapshot.Tests.ps1                    120,1s   31 tests   <- SLOW, re-measured 2026-08-24 WARM
  (cold 119,5s - this suite is I/O bound, so warm and cold agree). The test-audit closure added 3 It
  blocks; Pester expands them to 31 because two use -ForEach. The old row said 22. Before 2026-08-03 this
  suite was MISSING from this table entirely.
agy-autotrain-installer.Tests.ps1                 1,3s    8 tests   <- FAST, new 2026-08-24. WARM on an idle
  CPU (cold 9,8s - almost all of that is Pester module load, which this suite does not pay again once
  warm). Pure file parsing, no bash and no process launches, which is why it is the cheapest row here.
agy-learn-reminder.Tests.ps1                      6,4s    5 tests   <- SLOW, new 2026-08-24. 6,4s WARM on an
                                                                      idle CPU; 11,1s cold. It will not be the
                                                                      cold-start absorber in this half
agy-liveness-check.Tests.ps1                     56,4s   31 tests   <- SLOW, re-measured 2026-08-06 (+4)
agy-mark.Tests.ps1                               93,0s   27 tests   <- SLOW, NEW 2026-08-16. Task 6 (14c):
                                                                      agy-mark.sh, the sanctioned .clavity writer for the
                                                                      skills. Bash + git subprocess spawns across 26 Its; the
                                                                      FORWARDS $AGY_SESSION_ID row alone costs ~33,5s (three
                                                                      chained head calls proving the debounce breaks on a
                                                                      different session id, one against a git-tracked marker
                                                                      needing git rm --cached).
agy-seam-inject.Tests.ps1                        39,4s   24 tests   <- SLOW, re-measured 2026-08-06 (+5:
                                                                      four root-walk cases plus the marker
                                                                      cwd-relative contract, which had
                                                                      been comment-only). Time had said
                                                                      18,0s and was "count 2026-08-03,
                                                                      time older" - now both are current.
agy-shield-lib.Tests.ps1                        409,1s   39 tests   <- SLOW, NEW 2026-08-16. Fixture-
                                                                      heavy: many git + bash subprocess spawns per
                                                                      row across 17 Its. Measured solo, two
                                                                      consecutive runs immediately back to back:
                                                                      409,06s and 410,59s, 34/34 BOTH times - the
                                                                      second run is the re-run control the drafted
                                                                      suite could not have produced before the
                                                                      per-invocation debounce-key isolation was
                                                                      added to Invoke-Shield (see that function's
                                                                      comment).
agy-test-audit-reminder.Tests.ps1                50,8s   18 tests   <- SLOW, re-measured 2026-08-06 (+4)
assertion-strength-reminder.Tests.ps1            54,9s   37 tests   <- SLOW as of 2026-08-25; was FAST, measured 2026-08-12 with the driver
                                                                      resident - the same CPU runs the
                                                                      tests and the agent, as this file
                                                                      already warns above.
BashHookHelpers.Tests.ps1                         1,7s    8 tests   <- FAST, re-measured 2026-08-05
check-agy-discipline-skills.Tests.ps1             6,6s   39 tests   <- FAST, re-measured 2026-08-05
check-cheatsheet-budget.Tests.ps1                43,1s    6 tests   <- SLOW as of 2026-08-25; was FAST, re-measured 2026-08-12
check-cheatsheet-parity.Tests.ps1               135,9s   16 tests   <- SLOW, NEW 2026-08-16 (14e): the
                                                                      pre-commit parity gate's own suite.
                                                                      Every row builds a throwaway git repo,
                                                                      which is why it is expensive despite a
                                                                      modest test count. Measured solo as the
                                                                      sole command: "Tests completed in
                                                                      135,92s", 16 passed / 0 failed.
check-ci-filter-coverage.Tests.ps1               54,4s   17 tests   <- SLOW, NEW 2026-08-17: the ci-scripts
                                                                      paths-filter gate's own suite. Nearly
                                                                      every row spawns pwsh to run the gate
                                                                      against a separately mutated copy of the
                                                                      workflow, which is the whole cost - the
                                                                      test count is small and the process count
                                                                      is not. Measured SOLO AND IN BACKGROUND
                                                                      with the driver idle: 54 360 ms at 16 rows
                                                                      (54 450 at 19, 53 857 at 17),
                                                                      after the owner deleted the gate's second
                                                                      half (2026-08-17) and seven rows went with
                                                                      it - the seven that each built a throwaway
                                                                      git repo, which is where the time was.
                                                                      🔴 THE FULL SERIES REFUTES ANY PER-ROW
                                                                      COST: 78 990 ms at 11 rows, 103 065 at 13,
                                                                      120 448 at 20, 163 863 at 22, 147 313 at
                                                                      24 (LOWER at more rows), 53 857 at 17.
                                                                      Cost tracks what a row DOES, not how many
                                                                      there are. Re-measure; never predict. At 11 rows it also measured
                                                                      95s with the driver WORKING - a 1,2x
                                                                      inflation - so every figure here is the
                                                                      idle one, per the warning above.
                                                                      🔴 DO NOT DERIVE A PER-ROW COST FROM THESE.
                                                                      An earlier version of this row claimed
                                                                      "~4-6s apiece" from the 11->20 average;
                                                                      the very next two rows cost ~21s each.
                                                                      Marginal cost depends on what a row DOES
                                                                      (these two build fixtures and spawn the
                                                                      gate) and on the same machine variance
                                                                      this file documents elsewhere. Re-measure
                                                                      after adding rows; do not predict.
check-core-integrity.Tests.ps1                   27,0s    7 tests   <- SLOW, re-measured 2026-08-06
check-curate-in-progress.Tests.ps1               69,5s   20 tests   <- SLOW as of 2026-08-25; was FAST, measured 2026-08-12 with the driver
                                                                      resident - the same CPU runs the
                                                                      tests and the agent, as this file
                                                                      already warns above.
check-growth-budget.Tests.ps1                    15,3s   15 tests   <- FAST, re-measured 2026-08-05
check-injected-context.Tests.ps1                 91,5s  153 tests   <- SLOW as of 2026-08-24; was FAST -
  the single largest suite in that half, moved to buy back cap headroom. Figure measured 2026-08-12 with the driver
                                                                      resident - the same CPU runs the
                                                                      tests and the agent, as this file
                                                                      already warns above.
check-member-docs.Tests.ps1                       7,3s   35 tests   <- FAST, re-measured 2026-08-05
check-plugin-namespace.Tests.ps1                 27,2s    8 tests   <- SLOW, re-measured 2026-08-06
check-roster.Tests.ps1                            4,2s    5 tests   <- FAST, re-measured 2026-08-05
check-seed-artifacts-synced.Tests.ps1            71,9s   10 tests   <- re-measured 2026-08-04, again
                                                                      said 4,1s / 2 tests; the suite had
                                                                      SEVEN tests before this change even
                                                                      touched it, so this figure had
                                                                      decayed silently through at least
                                                                      two prior edits. It is now the
                                                                      LARGEST suite in the fast half -
                                                                      each of its tests invokes the whole
                                                                      gate - and the first candidate if
                                                                      that half ever needs trimming.
check-seed-budget.Tests.ps1                       8,4s    4 tests   <- FAST, re-measured 2026-08-05
check-user-facing-docs.Tests.ps1                 10,4s   15 tests   <- FAST, re-measured 2026-08-05
compute-release.Tests.ps1                        25,0s    7 tests   <- SLOW, re-measured 2026-08-06
docs-audit.Tests.ps1                            130,0s   80 tests   <- SLOW, re-measured 2026-08-06
drain-knowledge.Tests.ps1                        40,5s    8 tests   <- SLOW, re-measured 2026-08-06
drain-lib.Tests.ps1                               4,2s   25 tests   <- FAST, re-measured 2026-08-24 WARM
  (cold 6,1s) after the test-audit closure added 2 tests and strengthened 3.
generate-cheatsheet-literals.Tests.ps1           41,6s   18 tests   <- SLOW, NEW 2026-08-16 (14e): the
                                                                      cheatsheet-literal generator's pinning
                                                                      suite. Measured solo as the sole
                                                                      command: "Tests completed in 41,57s",
                                                                      12 passed / 0 failed.
generate-scoped-manifest.Tests.ps1                2,1s    2 tests   <- FAST, re-measured 2026-08-05
plugin-hooks-registration.Tests.ps1               0,6s   33 tests   <- FAST, re-measured 2026-08-05 (was
                                                                      0,5s / 18 tests; +4 for the recorder's
                                                                      SessionStart registration, which this
                                                                      suite had never covered)
plugin-hooks-payload.Tests.ps1                    3,4s    3 tests   <- FAST. COUNT corrected 2026-08-06:
                                                                      the row said 2 and had been wrong
                                                                      since 413c617 added the repo-root
                                                                      walk case 40 min after the sweep
                                                                      re-measured this file. TIME is the
                                                                      2026-08-05 figure, taken at 2 tests.
register-plugin.Tests.ps1                         6,6s   18 tests   <- FAST, re-measured 2026-08-05
release-lib.Tests.ps1                             5,5s   23 tests   <- FAST, re-measured 2026-08-05
```

Every FAST row above was re-measured in ONE sweep on 2026-08-05 (the 292,09s sample below). The SLOW rows
were not touched and carry their older figures. Test COUNTS were all correct except the three suites this
change edited — so what decays here is TIMES, which is exactly why the section header calls them indicative.

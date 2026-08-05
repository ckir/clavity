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

**Batching is not a saving.** The fast half as it stood on 2026-08-02 — 13 suites then, 15 now — run as
one `Invoke-Pester` process measured 94.2s / 75.1s / 73.7s, against a 65.8s warm per-file sum. One process saves repeated pwsh startup but pays cold module
load once and accumulates across files.

- `just test-scripts-fast` — the agent inner-loop gate. **19 suites, 234 tests, measured 251,8s and
  244,0s** (2026-08-04, TWO samples at THIS configuration, 3% apart — the first time this file records
  two, as its own rule below has always demanded). The preceding entry, 15 suites / 177 tests / 124,6s,
  is a DIFFERENT configuration and must not be compared against these.
- `just test-scripts-slow` — everything else. **13 suites, 238 tests, measured 761,28s** (2026-08-04,
  ONE sample, as the sole command on the machine). NOT on any git hook; it is **well past the 600s
  foreground tool cap** — 653,5s a day earlier, 761,28s now — and must be BACKGROUNDED by an agent,
  blocked on by reading its own `Tests completed` line, never by watching a process count.
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
test raises it. The count today is fast **177** and slow **238**, **both measured, not added up**. It is a
fact, not a contract, and it was 358 / 363 / 368 / 372 earlier.

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

## Measured runtimes

These are per-file numbers taken in one sweep and are INDICATIVE ONLY — the section above explains why a
per-file time is not a stable quantity and is not used as the partition rule. `agy-consult-guard` was
measured separately (2026-08-02) in isolation, as the sole command on a quiet machine.

```
abort-drain.Tests.ps1                           261,3s   13 tests
agy-consult-guard.Tests.ps1                      78,4s    8 tests   <- SLOW, moved 2026-08-02; count 2026-08-03
accept-drain.Tests.ps1                           51,2s   10 tests
agy-after-reminder.Tests.ps1                      9,7s   10 tests   <- FAST, re-measured 2026-08-05
agy-anomaly-reminder.Tests.ps1                   21,4s   16 tests
agy-anomaly-capture-reminder.Tests.ps1            8,4s   10 tests   <- FAST, re-measured 2026-08-05
agy-anomaly-dispatch-reminder.Tests.ps1          12,7s   18 tests   <- FAST, re-measured 2026-08-05
agy-anomaly-model-notice.Tests.ps1               16,7s    9 tests   <- FAST, re-measured 2026-08-05
agy-anomaly-contract-stamp.Tests.ps1              5,5s   14 tests   <- FAST, re-measured 2026-08-05
agy-discipline-reaching.Tests.ps1                15,2s   16 tests   <- FAST. The row said 69,1s and it had
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
agy-curate-nudge.Tests.ps1                       17,1s   11 tests   <- FAST, re-measured 2026-08-05
agy-inbox-snapshot.Tests.ps1                    100,4s   22 tests   <- SLOW; was MISSING from this
                                                                      table entirely until 2026-08-03
agy-liveness-check.Tests.ps1                     40,9s   27 tests
agy-seam-inject.Tests.ps1                        18,0s   19 tests   <- count 2026-08-03, time older
agy-test-audit-reminder.Tests.ps1                32,5s   14 tests   <- count 2026-08-03, time older
BashHookHelpers.Tests.ps1                         1,7s    4 tests   <- FAST, re-measured 2026-08-05
check-agy-discipline-skills.Tests.ps1             6,6s   14 tests   <- FAST, re-measured 2026-08-05
check-core-integrity.Tests.ps1                   24,1s    7 tests
check-growth-budget.Tests.ps1                    15,3s    7 tests   <- FAST, re-measured 2026-08-05
check-member-docs.Tests.ps1                       7,3s   35 tests   <- FAST, re-measured 2026-08-05
check-plugin-namespace.Tests.ps1                 25,8s    8 tests
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
compute-release.Tests.ps1                        22,6s    7 tests
docs-audit.Tests.ps1                            120,6s   80 tests
drain-knowledge.Tests.ps1                        38,2s    7 tests
drain-lib.Tests.ps1                               3,4s   20 tests   <- FAST, re-measured 2026-08-05
generate-scoped-manifest.Tests.ps1                2,1s    2 tests   <- FAST, re-measured 2026-08-05
plugin-hooks-registration.Tests.ps1               0,6s   22 tests   <- FAST, re-measured 2026-08-05 (was
                                                                      0,5s / 18 tests; +4 for the recorder's
                                                                      SessionStart registration, which this
                                                                      suite had never covered)
plugin-hooks-payload.Tests.ps1                    3,4s    2 tests   <- FAST, re-measured 2026-08-05
register-plugin.Tests.ps1                         6,6s   18 tests   <- FAST, re-measured 2026-08-05
release-lib.Tests.ps1                             5,5s   23 tests   <- FAST, re-measured 2026-08-05
```

Every FAST row above was re-measured in ONE sweep on 2026-08-05 (the 292,09s sample below). The SLOW rows
were not touched and carry their older figures. Test COUNTS were all correct except the three suites this
change edited — so what decays here is TIMES, which is exactly why the section header calls them indicative.

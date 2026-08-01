# AGY-CAPSTONE ledger

One row per capstone. Appended before a plan may be declared complete.

**This is a RECORD, not a proof.** Nothing prevents someone appending a GREEN line without running
anything; a self-asserted ledger is the same shape as the re-stamping defect the verify gate removed.
Two things keep it honest, neither a guarantee: the `evidence` column must cite something independently
checkable, and the ledger is reviewed like any other artifact rather than trusted like a gate output.

**`none` is not a permitted evidence value.** A capstone that goes green on its first round still
produces a transcript — the rounds it ran, the lenses it seated, what it tried. Cite that. If there is
nothing to cite, the entry does not go in.

**Absences are meaningful.** SP-0, SP-A, SP-C and SP-D do not appear below. They never had a
reconstructible capstone; their evidence is a verification transcript under
`docs/superpowers/verification/`, which is a different and weaker claim, deliberately not laundered into
this table.

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-07-25 | SP-B agy-capstone skill | 4 | GREEN | folds 2c105ac, 98ffcbd, a879cce, 0f5e3a1 |
| 2026-07-27 | agy-test-audit discipline | 3 | GREEN | folds 61bb193, be2a5e3, cd1a209 |
| 2026-07-30 | clavity-ls channel resilience | 3 | GREEN | folds 131591e, f2bab54, 08abc67 |
| 2026-07-31 | b14bef1..fbb126b | 5 | GREEN | folds 8fcbfa6, a52ef9d, 20834b0, 200c3ff, fbb126b |
| 2026-08-01 | 185affc..757337a | 3 | GREEN | folds f8d9703, 01622ce, 757337a; briefs .clavity/seams/phase-b-capstone-r{1,2,3}.md |
| 2026-08-01 | 19f589a..18495cd | 3 | GREEN | folds da18681, 18495cd; briefs .clavity/seams/anomaly-capstone-r{1,2,3}.md |

**A note on the anomaly-capture row, because it is the first entry whose round 1 was rejected.** Round 1
returned GREEN with zero findings on an 864-line diff. It was not accepted: two of its claims were false —
it asserted the two plugins' `SessionStart` registrations were identical (they differ by design, 2 entries
vs 3) and it cited `agy-anomaly-reminder.sh:88-89` for a construct that sits at 70-71. Checking the first
false claim exposed a real defect the round had missed, and the fix for THAT was itself the wrong shape,
which round 2 caught. Round 2 then closed `VERDICT: GREEN` while listing two findings in its own body; that
was scored RED too. Only round 3 was a GREEN whose verdict matched its body.

The `rounds` column therefore counts three, but the honest reading is that **no peer round produced a
finding until the peer was told its previous verdict had been refuted by measurement.** The defects in this
range were found by checking the reviewer, not by the review. That is worth recording precisely because
this ledger is a record and not a proof: a row reading "3 rounds, GREEN" would otherwise imply a
convergence that did not happen the way the number suggests.

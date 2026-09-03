# AGY-TEST-AUDIT ledger

One row per audit. Appended before an audit run may COMPLETE.

**Append the newest row at the BOTTOM of the table.** Say it here because the sibling ledger does not
settle it: `docs/agy-capstone-ledger.md`'s rows are NOT in date order (2026-08-08 sits between 07-31 and
08-01, and 08-16/08-17 precede 08-10/08-12), so "mirror the capstone" answers the shape of a row and not
the order of the file. A ledger two agents append to differently is a merge conflict per branch-finish;
appending at one end keeps the conflict trivial to resolve.

**This is a RECORD, not a proof.** Nothing prevents someone appending a row without running anything; a
self-asserted ledger is the same shape as the re-stamping defect the verify gate removed. Two things keep
it honest, neither a guarantee: the `evidence` column must cite something independently checkable (the
fold commits, or the brief in `.clavity/seams/`), and `none` is not a permitted value.

**Why this file exists.** The audit's marker `.clavity/agy-marks/agy-test-audit.head` is a NUDGE DEBOUNCE
holding ambient `HEAD` - `agy-test-audit/SKILL.md`, section `## Debounce marker` - not a coverage
attestation. (Cited by SECTION, not by line: this citation read `:313-314`, which was right when written
and had drifted by ~60 lines before anyone noticed. A line number in static prose rots by construction;
a section heading does not.) Before this
ledger, no artifact in the repository recorded which range had been audited, so the question "is a
re-audit owed?" could not be answered from the tree. That question is the input to the
capstone-invalidation loop, which is why the record is not optional bookkeeping.

**What a row does NOT claim.** That the suite is now exhaustive. An audit raises the coverage FLOOR under
one set of lenses; it does not prove no gap remains.

🔴 **ESCAPE EVERY `|` INSIDE A CELL AS `\|`.** The `evidence` column carries free prose and citations, and
a shell command pasted into it (`git log | grep ...`) contains the column delimiter. An unescaped pipe
silently invents a new column boundary: the row misaligns, nothing errors, and the record it was supposed
to preserve is the thing that gets mangled. Nothing validates this file's table structure, so the
convention is the only guard.

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-02 | `d33416c..d528328` | 1 | **GAPS FOUND** - 9 verified gaps folded, 2 REJECTED by measurement, 2 DISCARDED-BELOW-FLOOR | fold commit `f3ea3e9`; brief `.clavity/seams/testaudit-phase1-r1.md`. Every gap was established by a guard mutant - force the guard false, re-run, record what reddens - with baselines 18/0 and 59/0 and a failing control in the same campaign. One finding was a live SOURCE defect rather than a coverage gap: malformed JSON syntax reached `json.load` unguarded. Gates at the fold: 27/0 and 66/0. |

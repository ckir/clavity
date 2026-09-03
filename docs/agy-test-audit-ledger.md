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
| 2026-09-03 | `73efca8..eba63a8` | 1 | **GAPS FOUND** - 4 verified gaps: 1 FOLDED, 3 DEFERRED-TO-ANOMALIES (owner-scoped to gap 1); 3 seats DISCARDED-BELOW-FLOOR | fold commit `65b889a`; brief `.clavity/seams/testaudit-s23.md`. Peer returned a valid `[VERIFIED: ...]` block naming all three files it read. **GAP 1, the one that mattered, was proven by a mutant run BEFORE and AFTER the fix - the strongest control available.** The ledger rejection rows perturbed their fixture by SUBSTITUTING a marker (`docs/some-other-file.md`) rather than deleting the real path, so the fixture differed from the real repo by the PRESENCE of a string the test itself injected. MEASURED: a guard rewritten as `if ($raw.Contains('docs/some-other-file.md'))` - keying on the decoy instead of requiring the real path - passed all seven ledger rows **7/0**, and the real-repo positive control passed too because the real tree has no decoy. After changing the fixture to DELETE the path, the identical mutant fails **2 of 7**. Suite 82/0 unchanged; the row was converted, not added. **DEFERRED, logged in `.clavity/local-anomalies.md` and owed a ROADMAP promotion at triage:** the rejection rows' `-ForEach` array mirrors the linter's ledger map with nothing reconciling them, which is the SAME class the capstone closed for the linter's own roster one day earlier, reintroduced one layer up in the tests; short-circuit masking, since no row perturbs two skills so a rogue `break` replacing the fail-flag would be invisible; and needles that assert only the message prefix, recorded WITH its counter-argument that the fix pins prose verbatim, an anti-pattern this repo folded twice in section 21. **DISCARDED-BELOW-FLOOR, the peer's own three:** scratch-root leakage (guarded by a tracked list swept in `AfterAll`), an empty-file cascade (guarded by the existing `IsNullOrEmpty` check), and validating the ledger's markdown table (outside a skill linter's scope). ⚠ **PRECONDITION NOT MET, stated rather than hidden: this discipline normally runs after the capstone reports GREEN. That capstone closed NOT GREEN, breach-waived, gate armed - the owner asked for the audit anyway and was told the ground it stands on.** 🔴 **THE PEER REJECTED THE FRAME FOR THE SECOND TIME, FROM A SECOND DISCIPLINE:** a linter proves the PROMPT is intact, never that a row is written, and it proposed a behavioural gate at the audit's completing verdict checking the git diff for an appended row. That dodges the refutation that killed its capstone version (which keyed on a gitignored marker). **The owner has REOPENED the scoped-out decision rather than recording it as an accepted limitation.** |

# ROADMAP open-issues sweep - sequence design

**Date:** 2026-09-29 · **Base:** `main` = `origin/main` = `b0e03801` · **Status:** owner-approved order
(2026-09-29); spec awaiting owner review.

**Supersedes** Phases 5 and 6 of `2026-08-31-roadmap-implementation-sequence-design.md` for ORDERING
only. Every per-item ruling recorded there (e.g. §20 forces a re-capstone; the `Clavity.Live.Acceptance`
gating pairs with §20) still holds.

## Goal and success criterion

Sweep every OPEN item across the members' ROADMAPs and `docs/backlog/`. **Done** means every item below
ends as SHIPPED (AGY-CAPSTONE GREEN + AGY-TEST-AUDIT, both with ledger rows), SHIPPED UNDER AN OWNER WAIVER
(the waiver named in its ledger row's verdict column and in the ROADMAP header - never written as GREEN), or
explicitly KILLED / RULED by the owner. No item may be left "noted".

## The principle: one subject per branch

Branches are grouped by the CODE THEY TOUCH, never to save capstones or reinstalls. Quoted from the
2026-08-31 sequence spec (`:418-420`): *"One adversarial panel hunting across both domains splits an
attention budget that this repository has already measured to be the binding constraint."* The cost of that
choice is accepted: **two plugin reinstalls** (Branches 2 and 3) instead of one.

## Inventory (measured 2026-09-29 from the headers, not body text)

- `clavity-classic`, `agy-autotrain`, `commonmemory` ROADMAPs: **nothing open**.
- `review-relay/ROADMAP.md`: R1 (work). D1, D2 are owner DECISIONS, out of this sweep.
- `clavity-dotnet/ROADMAP.md`: §20, §26, §32, §33, §34, §35, §36, §38, §39, §40, §41, §42, §47-§54.
- `docs/backlog/`: 15 stubs whose `**Status:**` reads OPEN / PARTIALLY CLOSED (listed per step below).
- Not work: §16 (a recorded pattern), §14f (RULED, answered by §18), §30c (NOT FIXED by ruling).
- **Stale headers:** §15 reads "pending AGY-CAPSTONE", but `docs/agy-capstone-ledger.md:45` records it
  GREEN 2026-09-14 and `docs/agy-test-audit-ledger.md:44` records its audit.
- **Duplicate:** `docs/backlog/agy-mark-accepts-a-nonexistent-sha.md` is the same defect as §51.
- **New (captured 2026-09-29, owner put it in scope):** `docs/agy-test-audit-ledger.md:43` carries a literal
  NUL byte (column 1505, committed `c22698cb` 2026-09-13), so `git ls-files --eol` reports `i/-text` and
  git treats the ledger as BINARY. A second live instance of §49's class.

## The sequence

Every code branch runs the same cycle: **(a)** re-measure each of its items at the branch's own start
(just-in-time; a pass that re-measures everything up front goes stale as earlier branches land) -> an item
that no longer reproduces is PROPOSED for KILL to the owner with the measurement quoted (the driver never
closes an item on its own read) -> **(b)** writing-plans against the code as it
is then -> **(c)** implement -> **(d)** AGY-CAPSTONE rounds until GREEN, over `<branch base>..<tip>` (the base is the
`main` sha the branch was cut from, never the previous marker) -> **(e)** AGY-TEST-AUDIT -> **(f)**
merge to local `main`. The owner owns every push.

**(e) in full:** every verified test-audit gap is either closed in the branch (with its logic-mutant proof)
or owner-deferred through the anomalies conveyor to a ROADMAP entry, per the agy-test-audit skill. A branch
does not reach (f) with a verified gap that has neither. A gap closed with TEST-ONLY changes is proven by
its logic mutant and needs no new capstone round; a gap whose closure changes any NON-test source sends the
branch back to (d) for a capstone round over that delta, then (e) re-checks. **Circuit breaker:** the
capstone's own round cap counts EVERY capstone round on the branch, including returns from (e); at the cap
the driver halts and asks the owner (continue, or waive). A consult or round the owner WAIVES is recorded as
a waiver in that discipline's ledger row (the capstone skill's round-cap waiver form), and the branch then
proceeds; the driver never records a waiver as GREEN.

**Closing a header.** (c) is therefore at least two commits: the fix commit(s), then a LAST commit, before
(d) starts, that marks each item's ROADMAP header closed and cites those fix shas - never its own sha, which
a commit cannot contain. The header edit is thus inside the capstone range. Every LATER commit on the branch
(capstone folds, and source changes made at (e)) is NOT added to the header: the ledger row's range, which
ends on the branch's last reviewed commit, is the record of them.

**The execution index** is the driver's durable execution-status record for this project (the one the
owner's power-failure rule requires), updated after every commit. Every halt, owner ruling and branch boundary in this sweep is written there before the
driver stops.

**Plugin-pair branches (2 and 3):** mirror every hook/skill change to `clavity-classic` in the same commit;
BUMP the plugin version (a same-version reinstall is a no-op - the plugin runs from the installed cache, not
the tree); the owner reinstalls with Claude Code fully closed, through the plugin manager, never
`clavity-install.ps1`. **After merging Branch 2, and again after Branch 3, the driver HALTS**: it records
the halt in the execution index, asks the owner to reinstall, and starts nothing until the owner confirms
AND the installed cache reports the bumped version. Later branches' reviews then run the fixed hooks.

**Until Branch 2 lands (§52),** the test-audit marker must be written at the sha the ledger row's range ENDS
on (the last commit the audit reviewed - a fold sha if there was one), not ambient HEAD - the gate refuses ambient HEAD. This applies to Branch 1.

**If agy becomes unreachable mid-branch** (quota exhausted, modal-stuck, channel down), the driver HALTS
at the step it is on, records it in the execution index, and asks the owner to restore the channel or waive
that one consult. It never skips a capstone or audit round on its own authority, and never moves on to the
next branch meanwhile (the owner's AGY-UNREACHABLE rule).
### Step 0 - triage pass (no code, no capstone)

Mechanical:
- Close the stale headers: §15 (cite ledger rows 45 / 44), §14f (RULED; answered by §18).
- Merge the §51 backlog duplicate into §51 and delete the stub.
- Repair `docs/agy-test-audit-ledger.md:43`: the NUL is a mangled escape - the row's text reads "the NUL
  arrives as the `<NUL>` ESCAPE that json.load decodes", so the author wrote the six characters `\u0000`
  and a tool interpreted them. Replace the byte with those six ASCII characters (do NOT just delete it).
  Confirm `git ls-files --eol` then reports a TEXT index state (anything but `i/-text`; its sibling ledgers
  measure `i/lf`), and that no other control byte remains in any
  tracked `*.md` (one repo-wide scan, recorded in the commit).
- Remove the `.clavity/local-anomalies.md` entry for the NUL (promoted into this spec + §49).

Owner rulings, one per item (KILL, owner-action, or a branch slot). An item ruled into work joins the
branch below whose files its re-measurement touches; if none matches, it gets a NEW branch appended before
Branch 8, one subject per branch as above.
- **§38** - the publication policy for `docs/superpowers/{specs,plans}/` (72 of 77 tracked files are
  public past the stated opt-in; measured 2026-09-05). The `.gitignore` edit follows the ruling. **This
  spec is itself uncommitted until this ruling** - committing it now would mean a force-add, the practice
  §38 questions.
- **§41** - lift the 2026-09-08 deferral (then it joins Branch 3) or keep it deferred.
- **§35, §36** - both owner-raised, tracked, unbuilt.
- **§14g** - its header says AGY-TEST-AUDIT is still owed on `bd3aa94..f29cd42`.
- **Test audits owed outside the ROADMAP.** The driver's memory lists four epics whose capstone went GREEN
  with AGY-TEST-AUDIT outstanding (step 2 13b, assertion strength, agy-ls discovery fix, post-v14 probes).
  Step 0 checks each against `docs/agy-test-audit-ledger.md`; any still owed goes to the owner as run /
  waive, like §14g. **Every audit ruled "run" executes as Step 0b** (after step 0, before Branch 1): one
  AGY-TEST-AUDIT per owed range, each with its ledger row; gaps it finds follow the "(e) in full" rule above, closed
  on a branch of their own per audited range, and each such branch runs the (a)-(f) cycle, capstone
  included, with the GAPS as its items: (a) re-measures each gap (the audit's own mutant, or its missing
  test's claim); (c) has no ROADMAP header to close - instead the closing branch's OWN test-audit ledger row (a
  new row; existing rows are never edited) names the original range and the gaps it closes.
- **§36** also carries the 2026-08-31 test-gating audit's two orphans: the Python bridge tests (already
  closed by the `classic::pytest` recipe, `fc85437`, per `clavity-dotnet/ROADMAP.md:2926-2927`) and the three
  `test-scripts*` recipes nothing invokes (a recorded DECISION, not a defect: they are the rename detector
  and the suite's only local path - spec `2026-08-31-...:548-560`). Ruled with §36.
- The unassigned stubs: `agent-shell-layer-corrupts-commands-and-probes`,
  `agy-learn-can-silently-not-run-for-a-whole-session`, `agy-status-reports-working-for-an-idle-peer`
  (names no source file; if ruled into a branch, it goes where its re-measurement points),
  `cheatsheet-reaches-live-path-before-the-human-gate`, `cross-project-anomalies-have-no-cross-project-home`,
  `dependency-pins-are-never-re-resolved`, `dev-box-background-load-contaminates-every-timing-figure` (its
  stub says owner action), `git-index-fatal-recurs-during-test-runs` (cause unproven),
  `installed-plugin-drifts-under-an-unchanged-version`, `peer-scratch-dir-contains-executable-session-hooks`
  (partially closed), `whole-tree-sandbox-copies-are-unbounded`.

### Branch 1 - repo gates (`scripts/`, CI; no reinstall)
§42 + §54 (both in `scripts/check-injected-context.ps1` - one branch, never split), §49 (the check must
FAIL on the pre-repair ledger - measure it against `git show b0e03801:docs/agy-test-audit-ledger.md` - and
its Pester row builds its own synthetic fixture, never a gitignored scratch copy; a doc with a legitimate tab
is the required distractor), §47 +
`docs-audit-findings-are-invisible-to-git` (same findings view), §48, §50.

### Branch 2 - marker / ledger hooks (plugin pair; version bump + reinstall 1)
§39, §40, §51, §52. §51 and §52 interact: §52 changes WHICH sha the skill passes to `agy-mark.sh head`, and
§51 adds the existence check on that sha - plan them together. Open question for the plan: whether §51's
check fails open outside a git repository (§27 kept the writer git-optional). Mirror to classic.

### Branch 3 - `agy-anomaly-reminder.sh` (plugin pair; version bump + reinstall 2)
§32 (32a and 32b). §41 joins only if the owner lifts its deferral at step 0. Mirror to classic.

### Branch 4 - C# independent (`Clavity.Ls` / `Clavity.Cli`)
§33 (`TerminalToken.cs` case), §53 (`clavity start` untested), `agy-reply-channel-truncates-and-nulls-silently`
(`BoundedView.cs:27`, `:121`).

### Branch 5 - `AgyView` (one re-capstone of `AgyView`)
§20 (TimeProvider), `agyview-diagnostics-writes-are-unguarded` (`AgyView.cs:615`),
`ls-discovery-misreports-a-busy-peer-as-exited` (`AgyView.cs:320-387`). The two stubs are the FUNCTIONAL
change §20's own "WHEN" clause waits for ("Do not do it as a standalone commit"). Carries the
`Clavity.Live.Acceptance` gating ruled into Phase 5 of the 2026-08-31 spec. Line numbers are as cited by the
stubs and must be re-measured at (a).

### Branch 6 - test hygiene (`scripts/tests/`)
§34 + `pester-temp-dirs-orphan-on-killed-runs` (both leak temp resources).

### Branch 7 - review-relay R1
Standalone; may slot in BETWEEN any two branches, but never concurrently with another branch's capstone or
test audit: each discipline has ONE marker file (`.clavity/agy-marks/<discipline>.head`), so two runs in
flight overwrite each other's marker.

### Branch 8 - §26, LAST
The footprint analyzer, per its accepted spec `2026-09-03-plugin-footprint-analyzer-design.md`. Last
because Branches 2-3 change the footprint it measures.

## Dependencies that fix the order
- 2 before 3 is not forced by code; it keeps the ledger/marker fixes (which the capstone + test-audit
  gates of every LATER branch rely on) ahead of everything that uses them. Branch 2 therefore precedes
  4-6 as well.
- 1 first: its gates (§54, §49) protect every later branch's docs and pushes.
- 8 last: see above. 7 floats.

## Provenance
AGY-FIRST: `.clavity/seams/sweep-sequencing.md` (peer: NEGOTIATE - review-lens dilution; one claim refuted
by measurement: §15 is closed) and `.clavity/seams/sweep-sequencing-r2.md` (ALIGNED on this order; the
peer added the two AgyView stubs to Branch 5, the reply-channel stub to Branch 4, and just-in-time
re-measurement). The only remaining difference, §38 placement, was ruled by the owner: policy at step 0.

## Stand-downs

- DISCARDED-BELOW-FLOOR (panel round 2, peer): the spec names no exact command to read the installed plugin
  version. Unreachable as a wrong result because the halt also requires the OWNER's confirmation, and the
  driver's standing memory rule ("`CLAUDE_PLUGIN_ROOT` is the installed cache ... the plugin VERSION MUST
  BUMP") names what to check; the plan for Branch 2 fixes the command against the code as it then is.
- REJECTED in part (panel round 1, peer): "the Python bridge orphans are missing" - they are closed by
  `fc85437` (`clavity-dotnet/ROADMAP.md:2926-2927`); only the `test-scripts*` recipe decision was missing,
  now recorded under §36.
- REJECTED (panel round 3, peer): "test-only gap closures escape a re-audit". The agy-test-audit skill's
  step 5 requires the SPECIFIC new test to go red under a logic mutant of the guarded code - that proof is
  the re-check; a further paid audit round per test-only closure adds cost, not coverage.
- REJECTED in part (panel round 4, peer): "a waiver in the test-audit ledger corrupts its parser". Both
  ledgers share one column set, `| date | range | rounds | verdict | evidence |`
  (`docs/agy-capstone-ledger.md:39`, `docs/agy-test-audit-ledger.md:34`), and both already hold waiver rows
  (`grep -ci waive`: 38 and 7). The other half - "Done" had no waived outcome - was FOLDED.
- REJECTED (panel round 6, peer): "the old 'Closing a header:' paragraph was never deleted". Measured after
  the round-5 fold: `grep -n 'Closing a header'` returns ONE line; the peer read a stale copy.
- Round 6's Boundary Smuggler finding (the spec named the driver's private memory files) was FOLDED as
  wording only: those names already appear in tracked files (`docs/backlog-triage-runbook.md`,
  `clavity-dotnet/ROADMAP.md`), so committing this spec would publish nothing new.
- **Panel closed at the hard cap (round 6, owner-chosen), NOT GREEN.** Every finding of all six rounds is
  FOLDED or REJECTED above; none is open.

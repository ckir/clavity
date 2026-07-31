# Productize Completion Audit — Design

**Status:** Design approved (owner, 2026-07-31).
**Goal:** Make the productize epic's completion claim **true and verifiable**, decide what ships, and
close the ownership void the epic left behind — so the four productized disciplines can be released
without silently double-firing or silently dying.

---

## Background — what is actually true

The ship-agy-workflow epic (SP-0 rename → SP-A → SP-B → SP-C auto-fire hook → SP-D degradation tests)
productized four agy-driving disciplines out of the author's personal `~/.claude` config into two shipped
driver plugins. It is recorded as COMPLETE and capstone-GREEN. Eight facts, all measured:

1. **It was never released.** The epic's own DoD says "ONE combined release closes the epic". The newest
   release tag `clavity-v13` is dated 2026-07-24; SP-D's commits are 2026-07-25; `agy-test-audit` is
   2026-07-27. Nothing postdates SP-D.
2. **Consequently the author's machine runs the last release**, not a broken install. Its plugins
   legitimately lack the new skills and hooks. A hand-swap of `clavity-ls.exe` to a HEAD build is the
   only skew.
3. **Everything that works today works via the personal `~/.claude` copies**, not the shipped ones.
4. **Hook ownership is a void.** No document across the nine epic files says what becomes of the personal
   original after a hook is productized. A grep for retire/deprecate/disposal language returns zero hits.
5. **The personal and shipped copies have already diverged.** The personal `agy-seam-inject.sh` fires on
   `brainstorming` and `subagent-driven-development`; SP-C's Decision 1 deliberately narrowed the shipped
   one to bind capstone to `finishing-a-development-branch`. Both would be live at once after a release.
6. **SP-0's design instructed its plan to grep-confirm the personal hook was unaffected**
   (`2026-07-24-sp0-clavity-plugin-rename-design.md:104-106`). The plan never did it.
7. **Capstone convergence is unverifiable for SP-0, SP-A, SP-C and SP-D.** Only SP-B has a multi-round
   trail in git; SP-C and SP-D have zero fold commits. *Caveat: a capstone that goes green on round 1
   leaves no commit, so absence is not proof it never ran* — but the claim is not reconstructible by a
   cold successor, which violates the project's own power-failure-resilience rule.
8. An open fork was orphaned by supersession — for clavity-classic, whether the ME1 guard should be
   binary-native or a bash hook (`2026-07-22-ship-agy-disciplines-design.md:134`). ME1 and AGY-LEARN are
   explicitly out of the current epic's scope (`2026-07-24-ship-agy-workflow-design.md:13-14`).

**Already done and NOT in scope here** (surgical box relief, commit `cd9a467`): the PreCompact payload-shape
fix, removal of the duplicate `agy-learn-reminder` registration, relocation of the orphan
`plugins/clavity-dotnet/` directory, and raising `CLAVITY_AGY_IDLE_STALL_SECONDS` to 420.

---

## Decisions

### D1 — Hook ownership is a standing product rule

**The rule, verbatim, to be published in both plugin READMEs and the marker-contract doc:**

> A discipline hook has exactly one owner. Once a hook ships in a plugin, the plugin is its sole owner:
> the operator's personal registration of a same-named hook is retired. Retirement means **removing the
> registration** — the file may stay on disk, since only registration determines execution.
> Turning a shipped hook off is done with the `.no-agy` kill-switch, which is **global — it silences
> every agy discipline, not one hook**. There is deliberately no per-hook off switch: a selective,
> silent disable is the failure mode this rule exists to prevent. Local iteration on a hook is done by
> running the script directly against a synthetic payload, never by shadowing the shipped copy.

**Who performs the retirement, and when — this is not the installer's job.** The operator does it, after
installing the release, prompted by the enforcement notice below. An installer MUST NOT edit any
`settings.json`: those files are the operator's, and silently editing them is exactly the class of
surprise this design removes. See D6 for why this ordering, rather than retire-then-install.

**Rejected alternative, and why.** The peer proposed "shipped hooks yield to local overrides": each
shipped hook probes `~/.claude/hooks/` for a same-named script and exits 0 if found. Measured against
this machine's live state it fails outright — the personal `agy-learn-reminder.sh` exists on disk but is
registered nowhere, so the shipped hook would yield to a script that never runs and **the discipline would
drop entirely, silently**. File existence is a broken proxy for host execution state. The peer accepted
this after measuring it.

**Its counter-cost, folded rather than dismissed.** Sole ownership removes the instant local edit-and-
reload loop for hook development. That loop is preserved by running the script directly with a synthetic
payload — e.g. `echo '{"cwd":"/tmp"}' | bash <hook> PreCompact` — which is faster than any registration
dance and needs no new mechanism.

**Enforcement (this is the part that must not be silent).** `agy-liveness-check.sh` — already shipped by
SP-D, already SessionStart, already writing to stderr — gains a duplicate-ownership check. It lives
entirely inside an artifact we ship and requires nothing from the host application. Five constraints,
each from a measured defect in an earlier draft of this design:

1. **Check every settings file, not just the user one.** Registrations can live in `~/.claude/settings.json`,
   `<repo>/.claude/settings.json`, and `<repo>/.claude/settings.local.json` — all three exist in this
   repository today. Checking only the first yields a false "no duplicates" while a project-level
   duplicate fires every session.
2. **Derive the shipped-hook list at runtime from the sibling `hooks.json`.** A hardcoded array falls out
   of sync the first time someone adds a hook, and the fixture test keeps passing because it tests the
   old names — the gate would be bypassed silently by the very act of extending the plugin.
3. **Assert the schema before concluding "clean".** If the expected `.hooks` node is absent — because the
   host changed its settings schema — emit `schema unrecognised` rather than a false negative. A query
   that returns empty because it no longer matches anything must never read as "nothing to report".
4. **Fail loud on unparseable input.** A malformed `settings.json` (a hand-edited trailing comma is the
   realistic case) must produce `settings unreadable, duplicate check skipped` on stderr — not a silent
   drop and not a crashed SessionStart.
5. **Honour the existing exit-code contract, and extend it deliberately.** `agy-liveness-check.sh:12-14`
   documents exactly two end-states: healthy → `exit 0` with no stderr; not-live → advisory on stderr +
   `exit 2`. The duplicate notice is a **third** state and the header contract must be updated to say so
   in the same change. It is advisory: stderr + `exit 2`, never blocking.

### D2 — Release comes after verification

The disciplines are already functioning for the operator via personal copies, and surgical relief has
already removed the daily friction, so there is no urgency argument for shipping first. Releasing with an
unverified completion claim would make the claim permanent. Verification (D5) precedes the release.

### D3 — The orphaned ME1 fork does not gate the release

Owner ruling. It belongs to the superseded ME1-centric spec, and ME1 is explicitly out of the current
epic's scope. It becomes **tracked debt**, recorded in `clavity-dotnet/ROADMAP.md`, not a release blocker.

### D4 — The two later disciplines are a follow-on, not a re-scope

`agy-test-audit` (shipped 2026-07-27) and the planned `AGY-SCOPE` are not folded into this epic.
Retroactively widening a stalled epic prevents closure. This epic closes at four disciplines; a separate
follow-on covers the other two.

### D5 — A green capstone must leave a durable record

The reason finding 7 is unverifiable is an **evidence-model defect, not necessarily a code defect**: a
capstone that finds nothing produces no commit, so "ran and was clean" is indistinguishable from "never
ran". Fix the model, not just this instance.

**Mechanism:** a committed ledger at `docs/agy-capstone-ledger.md`, one line per capstone, appended
before a plan may be declared complete:

```
| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-07-31 | b14bef1..fbb126b | 5 | GREEN | folds 8fcbfa6,a52ef9d,20834b0,200c3ff,fbb126b |
```

The `agy-capstone` skill gains a step requiring the ledger line. A cold successor can then reconstruct
which ranges have been reviewed and to what depth.

**The ledger is a RECORD, not a proof — say so in the file's own header.** Nothing stops someone
appending `GREEN` without running anything; a self-asserted ledger line is the same shape as the
re-stamping defect this project removed from its verify gate, and pretending otherwise would be worse
than having no ledger. Two things keep it honest, and neither is a guarantee:

- The `evidence` column must cite something independently checkable — the fold commits, or the seam
  files a round produced. A GREEN with an empty evidence column is a first-round-clean capstone and must
  be written as such (`evidence: none — clean on round 1`), so that "nothing to cite" is stated rather
  than indistinguishable from "nothing was done".
- The ledger is reviewed like any other artifact, not trusted like a gate output.

**Seeding is bounded by what is actually reconstructible, and that is the point.** Seed only entries
with real evidence in git — SP-B, the clavity-ls channel epic, `agy-test-audit`, and tonight's
verify-harness range. **Do not back-fill SP-0, SP-A, SP-C or SP-D from memory**: their evidence gap is
the finding, and manufacturing ledger lines for them would erase it. Their rows are written by the
verification pass in scope item 2, or not at all.

### D6 — Retirement happens WITH the release, prompted, not before it

Retiring the personal hooks before the release opens a capability gap: the operator loses every
discipline until the release lands. Retiring long after leaves the double-firing this audit exists to
prevent. Neither is acceptable, and the window cannot be closed by repo changes alone because
`~/.claude/settings.json` is the operator's own file.

**Resolution:** the operator retires the personal registrations *after* installing the release, prompted
by D1's liveness notice, which fires on the first session after install and names the exact entries.
An installer MUST NOT edit any `settings.json` — those files are the operator's, and silent edits to them
are precisely the class of surprise this design is removing.

**The window is bounded by operator action, not by a mechanism — state that honestly.** Between install
and retirement, both copies fire. For a SessionStart reminder that is duplicated context; for a
`PreToolUse` hook it is a doubled directive, and an operator who keeps working through it may spend real
time debugging behaviour caused by the duplication rather than by the release. The notice must therefore
not merely list the entries to remove: it must tell the operator to **remove them and then restart or
`/clear` the session**, so the window closes at a known point rather than whenever they get round to it.
Calling the window "one session" would be an assumption about operator behaviour dressed up as a bound.

---

## Scope

**In scope — and the ORDER here is load-bearing, not editorial**

1. **Verification pass FIRST**, over SP-0, SP-A, SP-C, SP-D (SP-B already has an evidenced trail).
2. Close SP-0's residue: the unrecorded Spike B result and the consequently-indeterminate Task 6.3; the
   Category 9 grep-confirm the plan skipped. Record each outcome **in that sub-project's verification
   transcript from item 1** — running them and not writing down what happened is how the residue was
   created in the first place.
3. Publish and apply D1; implement the D1 liveness enforcement check.
4. Implement D5 — the capstone ledger and the skill step that requires it.
5. Define the release checklist: what the one combined release must contain, plus the post-install
   retirement step.

**Why verification must precede items 3 and 4.** D1 modifies `agy-liveness-check.sh`, which is an SP-D
deliverable. D5 modifies the `agy-capstone` skill, which is an SP-B deliverable. Implementing either
first means the audit is no longer verifying the epic's terminal state — it is verifying a state this
audit itself mutated, and any historical defect in those two artifacts is overwritten before anyone
looks at it. The verification pass must therefore run against the epic's terminal commits, before items
3-4 land. If working-tree convenience is preferred over checking out that range, each transcript must
record the commit it verified against, so a reader can tell what was actually examined.

**Out of scope — stated deliberately, because an unstated boundary is what created finding 4**

- The ME1 binary-native-vs-bash fork (D3, tracked debt).
- Absorbing `agy-test-audit` and `AGY-SCOPE` (D4, follow-on epic).
- Cutting the release itself. The owner owns every push; this design ends at release-ready.
- Anything on the operator's machine beyond the already-completed surgical relief.

---

## Components

| Component | Change |
|---|---|
| `clavity-dotnet/plugin/README.md`, `clavity-classic/plugin/README.md` | publish the D1 rule verbatim (byte-identical, per the epic's Option-A packaging) |
| `docs/agy-disciplines-marker-contract.md` | record D1 alongside the existing marker contracts |
| `clavity-dotnet/plugin/hooks/agy-liveness-check.sh` + classic mirror | add the duplicate-ownership check; byte-identical mirror |
| `docs/agy-capstone-ledger.md` | new; the D5 ledger, seeded with the entries reconstructible today |
| `clavity-dotnet/plugin/skills/agy-capstone/SKILL.md` + classic mirror | add the ledger step to the DoD |
| `docs/superpowers/verification/` | new; one transcript per verified sub-project |
| `clavity-dotnet/ROADMAP.md` | record the ME1 fork as tracked debt; record the follow-on epic |
| `scripts/check-seed-artifacts-synced.sh` | enroll any new byte-identical pair introduced above |

## Verification

- **D1 enforcement:** fixture tests over a synthetic settings tree, one per constraint in D1, not one
  overall. At minimum: notice fires on a user-level duplicate; fires on a project-level duplicate; fires
  on a `settings.local.json` duplicate; stays silent when there is none; says `settings unreadable` on
  malformed JSON; says `schema unrecognised` when `.hooks` is absent; and picks up a hook added to
  `hooks.json` **without any test edit** — that last one is what proves the list is derived at runtime
  rather than hardcoded. Non-vacuity checked by mutation: remove each guard in turn, its named test must
  go red. A guard whose removal leaves the suite green is not a guard.
- **Byte-identical mirrors:** `just seed-sync-check` green; `diff -q` on each mirrored pair.
- **Skill lint:** `just check-agy-skills` green.
- **Verification pass output:** each transcript records the exact commands run and their output, not a
  summary. A transcript asserting a claim without a command is not acceptable evidence — that is the
  failure this whole design exists to correct.

## Risks

- **The verification pass finds a real defect in a sub-project.** Then it is no longer an audit — it
  becomes a fix, and the release slips. That is the correct outcome, not a reason to soften the pass.
- **The liveness notice becomes noise** if it fires for a condition the operator has deliberately chosen.
  Mitigated by naming the exact entries and by `.no-agy` remaining available.
- **Scope drift into the follow-on epic.** D4 is the boundary; a finding about `agy-test-audit` or
  `AGY-SCOPE` gets logged to the follow-on, not absorbed here.

---

## Panel review — round 1 folds

Twelve findings, all folded. Six from the solo panel, six from the agy escalation, **no overlap** — each
reviewer found what the other missed, which is the argument for running both rather than either.

Measured before folding (the solo panel's three, each a defect in an earlier draft of this document):
`.no-agy` is global rather than per-hook, so the original D1 offered an off-switch that does not exist ·
hook registrations live in three settings files, not one, so the original enforcement would have reported
a false clean · `agy-liveness-check.sh:12-14` declares a two-state exit contract that the new notice
extends to three.

From the escalation: the verification pass had to move **before** D1/D5 implementation, because those two
items modify SP-D and SP-B deliverables and would otherwise overwrite the historical state being audited ·
the shipped-hook list must be derived at runtime or extending the plugin silently bypasses the gate ·
an unrecognised settings schema must not read as "clean" · malformed JSON must fail loud · the notice must
instruct a restart, since the double-fire window is bounded by operator action, not by any mechanism ·
SP-0 residue outcomes get recorded in the verification transcripts.

Also folded from the solo panel: the D1 rule text contradicted D6 about who retires the registration and
when · the D5 ledger is self-asserted and must say so rather than pose as proof · ledger seeding must not
back-fill the four sub-projects whose missing evidence is the actual finding.

## Self-audit

**Placeholders:** none. Every decision has a mechanism, an owner, and a location.

**Contracts specified:** the D1 rule text is verbatim and final. The D5 ledger's column shape is fixed.
The liveness notice's trigger condition is stated (shipped hook name present in `~/.claude/settings.json`).

**Deliberately deferred, with where each resolves:**
- The *exact wording* of the liveness notice → plan-time; the trigger and the requirement that it name
  the offending entries are fixed here.
- Which SP-0 disposition applies to Task 6.3 (correctly-skipped vs never-run) → resolved by the Spike B
  re-run in scope item 4; this design does not pre-judge it.
- The release's version number and contents manifest → the release checklist, scope item 5.

**Requirement coverage:** D1→scope 1 · D2→ordering of scope 2 before 5 · D3→scope-out + ROADMAP ·
D4→scope-out + ROADMAP · D5→scope 3 · D6→scope 5. Findings 1,6,7 → scope 2 and 4. Findings 4,5 → D1/D6.
Findings 2,3 → background only; already addressed by the completed surgical relief. Finding 8 → D3.

**Ambiguity check:** "retire" means both delete the registration and leave or delete the file at the
operator's discretion — the rule binds the *registration*, since that is what determines execution. This
is stated explicitly in D1's enforcement paragraph rather than left to inference.

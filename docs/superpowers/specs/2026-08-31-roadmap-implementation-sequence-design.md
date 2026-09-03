# ROADMAP implementation sequence - design

**Date:** 2026-08-31. **HEAD at authoring:** `e5179a5`; **revised after adversarial panel round 1 at
`4392ddf`.**
**Status:** owner-approved sequence. Each phase still needs its own spec-or-plan before execution.

**Goal:** decide the ORDER and BATCHING of the remaining open ROADMAP work. This document does not
design any of that work - every item is already owner-accepted or owner-open, and several carry their
own committed detail. It decides only what is built in what order, in which batches, and why.

**Consulted:** the live agy peer under AGY-FIRST (`.clavity/seams/roadmap-sequencing.md`, reply at
`.clavity/scratch/roadmap-sequencing/reply.md`). Its central reframing was adopted; three of its
supporting claims were checked by measurement and two did not survive. Both outcomes are recorded below,
because the refuted ones are the reason two owner decisions went against its recommendation.

---

## 1. The verified state - and why the ROADMAP itself cannot be trusted as the index

**Before sequencing anything, the index was reconciled against git.** Three sections carry headers that
contradict what shipped:

| section | header says | git says |
|---|---|---|
| §17 | `▶ OPEN` | §17a shipped `99910c0`, capstone GREEN (ledger `eb26709`); §17b RULED KILLED |
| §18 | `▶ OPEN` | shipped, capstone GREEN after 7 rounds (ledger `519833f`) |
| §19 | `DECIDED, DEFERRED` | shipped `64d5be4`, same capstone GREEN |
| §14h | `▶ OPEN - promoted at the 2026-08-15 triage` | **shipped `a652d8d` on 2026-08-16** - "14c + 14h ... seat a panel" |

This is a recurrence of a recorded failure - §13b read `▶ OPEN` seven days after shipping - and the rule
earned from it is that **whoever closes an item writes its closing sha in the same commit.** That rule
was not followed for these three.

**Sequencing from those headers would have scheduled work that is already done.** Reconciling the index
is therefore Phase 0, not a tidy-up.

**§16 is a PATTERN, not schedulable work** (it records the transient-Pester edit-verification approach for
future plans and changes nothing shipped).

**§14a-e and §14g shipped. §14f needs one check, and my first draft of this document got it
wrong.**

**§14h is NOT open - it shipped in `a652d8d` on 2026-08-16, the day after the measurement its ROADMAP entry
records, and that entry was never updated.** Panel round 1 caught this; the first draft of this document
scheduled it as Phase 2's first item. Verified at HEAD: `agy-first/SKILL.md:103` reads **"Seat a panel, not
a persona."** with seat rotation at `:112`; `agy-test-audit/SKILL.md:109` reads **"Seat the audit, do not
send one voice."** placed after the `## The audit round` heading - *exactly* the insertion point the ROADMAP
entry prescribes - and the old `"Optional per-run mitigation: rotate the audit's lens"` wording it names is
**gone** (grep returns nothing). **This is a fourth stale header, and the section above found only three.**
That is not an incidental miss: it is the same defect this document opens by condemning, committed by this
document, and the reason it happened is the drift finding below. §14f was not shipped - it was RULED on 2026-08-19 as "ANSWERED BY §18 and sequenced behind it",
on the reasoning that once §18 ships, `core.md` becomes the pinned driver-owned FLOOR and the growth
region becomes curator-owned, so the ownership contradiction "dissolves rather than being adjudicated".
**§18 has since shipped, but nobody has verified the dissolution actually happened.** A ruling that an
item will resolve as a consequence of other work is not evidence that it did. **Phase 0 must check it and
close or reopen §14f explicitly** - the same discipline this document applies to §17, §18 and §19.

**The genuinely open set:** §15, §20, §21, §22, §23, §24, §25, plus three items promoted from the
anomalies file at the 2026-08-31 triage. **§14h is closed** (above).

### 1a. Why the §14h miss happened - and why it is the sequence's first problem, not a footnote

**Every skill citation in this document's first draft resolved against the INSTALLED plugin copy, not the
repository copy.** The two have drifted apart under an identical version string.

**MEASURED 2026-08-31, installed vs repo, `SKILL.md` line counts:**

| skill | installed | repo | drift |
|---|---|---|---|
| `agy-capstone` | 236 | 429 | **193 lines** |
| `agy-test-audit` | 159 | 332 | **173 lines** |
| `adversarial-panel-review` | 240 | 360 | **120 lines** |
| `agy-first` | 123 | 214 | **91 lines** |
| `open-issues` | 192 | 221 | 29 lines |

**Both sides report `"version": "0.7.0"`.** Nothing detects this.

Two citations in the first draft are corrected below as a direct result, and both were *only* true of the
installed copy: `agy-first/SKILL.md:54-56` for a single default persona (repo `:52-58` is about flagged
replies; the persona text exists at installed `:54-56` verbatim), and `agy-capstone/SKILL.md:191` for the
five-token disposition set (repo `:191` is about `severity`; the real set - `FOLDED`, `REJECTED`,
`DISCARDED-BELOW-FLOOR`, `DEFERRED-TO-ANOMALIES`, `UNVERIFIED-ACCEPTED` - is at repo `:358-360`). **The
substance of the §21 step-2 argument survives** - "disposition" is genuinely taken, on a different axis -
**only its anchor was wrong.**

**This is not a hazard to the phases below. It is corrupting the review of this document.** The panel that
found the §14h miss ran under a `adversarial-panel-review` skill that is 120 lines behind the repo copy.
The live agy peer independently reached the same conclusion from the artifact alone, and put it first:

> *"You cannot execute a sequence built on reviews if the review mechanism is unpinned. Fix the drift in
> Phase 0 or the sequence fails on contact."*

**Consequence for the sequence: the drift moves OUT of "not scheduled here" and INTO Phase 0**, ahead of
every other item. See Phase 0c.

---

## 2. The batching axis - the decision that shapes everything else

The obvious axis is **shared files**. Four items all edit the same four byte-identical `SKILL.md` pairs
(**five before panel round 1 found §14h already shipped** - and note that removing it took `agy-first` out
of the batch entirely, which only sharpens the argument below):

| item | edits |
|---|---|
| §21 - the peer reply contract | all four |
| §23 - AGY-TEST-AUDIT has no ledger | `agy-test-audit` + a new `docs/` ledger |
| §24 - AGY-FIRST mandatory when a capstone develops new code | `agy-capstone` |
| §25 - a negotiation discipline | all four |

Since a plan on plugin-payload code costs a full panel -> capstone -> test-audit cycle, and recent
capstones ran **7, 8 and 11 rounds**, batching by file looks like it saves three review cycles.

**That axis was rejected, and the reasoning is the peer's.** Grouping by file is grouping by storage
location, not by what the instructions DO. These skills are the procedure the capstone itself executes,
so a batch that changes both the review's **output format** and its **conduct rules** forces the capstone
to review its own new rules using its own new rules - and a defect in the JSON contract becomes
indistinguishable from a defect in the negotiation rules. The round cannot converge because it cannot
attribute its own failures.

**The adopted axis is COGNITIVE DOMAIN:**
- **OUTPUT** - what the peer must WRITE DOWN. Mechanical text generation, verifiable by a script.
- **CONDUCT** - how the review is CARRIED OUT. Changes the agent's reasoning and compliance, verifiable
  only by observing behaviour across rounds.

**A caveat the peer did not state, and it applies to the adopted shape too:** any change to the review
disciplines is reviewed *by* those disciplines. Splitting into two batches REDUCES the self-reference; it
does not remove it. Each phase below must therefore state which discipline version reviews it - the one
before its own change, or the one after.

---

## 3. The sequence

### Phase 0 - pin the toolchain, reconcile the index, repair the suite floor (prerequisite)

Three pieces of work, all prerequisite because everything after them depends on their being true.
**Owner-ruled 2026-08-31: this phase's growth beyond its approved docs-only charter is ACCEPTED**, and the
three land as three independent commits, in the order 0c, 0a, 0b.
**0c is new after panel round 1 and it comes first**, because 0a and 0b are themselves reviewed by the
drifted skills.

**0c - pin the installed plugin to the repo copy, and give the drift a detector.** The census in §1a is
the evidence. Without 0c, every review in every phase below is run by an agent holding instructions nobody
has verified - which is exactly how §14h came to be scheduled as open work sixteen days after it shipped.

**Two deliverables, and panel round 2 established they are not the same KIND of thing:**

- **0c-local - reinstall** so the four review skills match the repo. **This is a local machine action and
  cannot be committed**, so it is not "shipped" the way 0a and 0b are. It is a precondition on the operator,
  and it must be re-satisfied after every phase that edits a skill - which is Phases 1 and 2.
- **0c-repo - the detector**, which is committable and is the deliverable that lasts.

**The detector MUST hash the installed files' CONTENTS against the repo copies.** Round 2's Blindspot
Auditor seat put this precisely, and the artifact already contains its own proof: *"If this mechanical check
keys on a plugin manifest, package version, or git SHA, it will glow false green"* - because `:76` records
that both sides report `"version": "0.7.0"` across a 193-line divergence. **Any detector keyed on version,
manifest or sha reproduces the exact blindspot it exists to close.** Content hash, or nothing.

**Round 3 added three constraints on that detector, and it does not work without them.**

**It must hash the WHOLE payload, not the skills.** The Mechanism Gamer seat argued a `.md`-only hash leaves
`.json` schemas unpinned. **That specific claim is REFUTED - measured, the skill directories contain zero
non-`.md` files** - but the generalisation is true and sharper than the seat knew: the plugin also ships
**16 hooks (`.sh`), `plugin.json` and `.mcp.json`**, none of them `.md`. **Phase 3 is hook work**, so a
skills-only detector would be blind to exactly the payload the sequence edits next.

**It must compare against a DECLARED sha, not ambient repo HEAD** - and this one is a genuine contradiction
the earlier rounds created. The Axiom Breaker seat: a detector enforcing *installed == current repo* cannot
coexist with `:358-359`, which requires Phase 2 to review its own changes under a recorded pre-change
version. Install the pre-change copy to conduct that review and the detector reds; satisfy the detector and
the review runs under the rules it is reviewing. **Comparing installed against a NAMED sha dissolves it:**
Phase 2 declares the pre-change sha, the detector validates against that, and both rules hold. This is the
same ambient-HEAD-versus-named-sha distinction that produced a wrong marker on 2026-08-31.

**It must not land as a blocking pre-commit hook before 0c-local has run.** The Cascade Analyst seat: if
0c-repo ships a pre-commit hook and the reinstall has not happened, **the first commit fails its own hook**
and the driver's workflow breaks on the phase meant to unblock everything. 0c-local is a precondition of
0c-repo's commit, not a parallel task - which is a second reason the two are separated above.

**0a - reconcile the ROADMAP index, AND close the mechanism that keeps corrupting it.** Correct the §17,
§18, §19 **and §14h** headers to CLOSED with their closing shas, per the earned rule. This is prerequisite
rather than housekeeping because every later phase cites ROADMAP sections, and a plan that cites a stale
header is a plan built on a false claim about the repository.

**Correcting the four headers is NOT sufficient, and round 2's State Corruptor seat is why:** *"This repairs
the stale state but leaves the corruption mechanism wide open ... Manually correcting the markdown does
nothing to prevent Phase 1 from doing exactly the same thing."* It is right, and it is measurable.
**MEASURED at `f4b128a`: the earned rule "whoever closes an item writes its closing sha in the same commit"
has ZERO implementation** - `grep -rl "closing sha"` across `.github/workflows/`, `scripts/`,
`clavity-dotnet/plugin/hooks/` and `lefthook.yml` returns **nothing**. It is prose, and this repository
already holds the law that **a rule with no implementation is worse than no rule**, because it is believed.

Four stale headers is the measured cost of leaving it prose. **So 0a acquires a second deliverable: a guard,
however cheap, that ties a section's status token to something checkable.** If a guard proves genuinely
infeasible, that is a finding to record explicitly - not a reason to ship the fifth stale header.

**That guard must verify the sha EXISTS, not that it looks like one** - round 3's Mechanism Gamer seat, and
the precedent is in this very document. A guard checking only for a 40-character hex string is satisfied by
an invented commit. **`agy-mark.sh` already has exactly that defect**, it is listed as a Phase 3 item below
("accepts a non-existent sha ... writes any 40-character string with rc=0"), and it produced a real wrong
marker on 2026-08-31. Shipping the same shape in 0a would be this document scheduling a fix for a bug while
committing it. **`git cat-file -e <sha>` is the difference**, and it costs nothing.

**0a is therefore no longer "no code changes",** and the phase's charter widens a second time. That is worth
stating plainly rather than letting it drift.

**§14f needs a criterion before it needs a verdict, and the first draft did not give it one.** It said
"verify by measurement whether §18 shipping actually dissolved its ownership contradiction". The peer's
Literal Implementer seat rejected that as unexecutable, and it is right: *"How do you mechanically measure
the absence of a contradiction? You cannot grep for 'dissolved.'"* **Replace it with a checkable question:**
§14f's contradiction was over who owns `core.md`. So - **name the writer.** Identify every committed path
that writes `core.md` or the growth region.

**That is still not a criterion, and round 2's Axiom Breaker caught it:** *"'Owner' is a human role (curator
vs driver), not a mechanical git property ... the agent still has to guess whether that path constitutes a
'curator' or a 'driver'."* Correct - the first fix replaced one unexecutable judgement with another, and the
enumeration step is mechanical while the adjudication step is not.

**So the criterion is the ENUMERATION, and the adjudication is the owner's:** list every committed writer of
`core.md` and the growth region, with file and line, and put that list to the owner. **§14f closes on the
owner's ruling over a measured list, not on an agent's judgement about what counts as an owner.** If the
list cannot be produced mechanically, §14f is REOPENED as live work. Either outcome is executable; "verify
the contradiction dissolved" never was.

**One more constraint, from round 3's Boundary Smuggler seat, and it is the difference between a gate and a
formality.** The list crosses a trust boundary: an agent generates it, the owner rules on it, and **an
omitted row is invisible to the person deciding.** *"A gate that relies on an untrusted generator not
dropping rows is trivially bypassable."* **So the deliverable is the COMMAND, not the list** - a named,
re-runnable search the owner can execute to reproduce the same rows. A list the owner cannot regenerate is
evidence of nothing, and this failure mode is not hypothetical here: the citation defects that opened this
review were all agent-generated claims nobody re-ran.

**0b - repair the Pester suite floor.** `ci-scripts.yml:203` fails the whole `scripts/tests` sweep only if
`TotalCount -lt 100`. **MEASURED 2026-08-31: the suite holds 982 static `It` blocks across 50 suites** - a
LOWER bound, since `-ForEach` rows expand at runtime. **The floor therefore trips only after roughly 89% of
the suite has stopped running.** A misnamed file, a `BeforeAll` that throws, a suite that silently stops
being discovered: none of it reaches 100. This is the same fail-open class the whole repository keeps
finding, sitting on the gate that guards all 50 suites.

**Two corrections from panel round 1, and together they change what 0b should build.**

**First, one of those three modes is already covered - MEASURED with a paired control.** A suite whose
`BeforeAll` throws yields `FailedCount=1` *and* container `Result=Failed`, so `ci-scripts.yml:200` and
`:201-202` both throw on it independently of the count floor. Only the *misnamed* and *silently
undiscovered* modes reach the floor. Overstating the hole is not harmless here: the size of the hole is
the entire argument for widening Phase 0's charter to touch CI.

**Second, the oracle this phase proposes to build ALREADY EXISTS, is stronger than proposed, and keys on
something else.** `test-suite-registration.Tests.ps1:265` asserts
`$discovered.Count | Should -Be $onDiskCount` - **exact equality, not a floor** - against
`git ls-files '*.Tests.ps1'` (`:87-92`), not against the justfile partition. So 0b must not re-implement it.

**The real hole is one the first draft never named: that oracle guards everything except itself.** Its
equality row only runs while `test-suite-registration.Tests.ps1` is itself discovered. If *that* file is
the one misnamed or lost, its row never executes and the only surviving backstop is `TotalCount -lt 100` -
the very floor it was supposed to make redundant. **A self-guarding oracle is 0b's actual subject.** The
cheapest fix is a CI assertion naming that one suite explicitly, which cannot be satisfied by the suite's
own absence.

**Round 2 challenged that placement, and MEASURING it made the situation worse rather than better.** The
Activation Auditor seat argued a CI-only assertion leaves local `just test` failing open. **The mechanism is
inverted: `just test` (`justfile:17` - `dotnet::test classic::test ghidrust::test`) does not run the Pester
scripts suite AT ALL.** Measured at `f4b128a`, the 50-suite net has **exactly one real invocation path**,
`ci-scripts.yml:199`; the three `test-scripts*` recipes that would give it a local one are referenced only
from `.clavity/scratch/` sandboxes, i.e. by nothing.

So the seat's conclusion (put the assertion where CI is not the only reader) is **not** actionable as stated
- there is no second reader to protect - **but its finding stands in a worse form: this suite has no local
runner at all, so every one of its 982 assertions is invisible until a push.** That materially raises the
stakes of the scope decision below: deleting those three recipes would remove the only local path that could
ever be revived.

**Phase 0's charter widens from docs-only to include this one CI change**, and that is deliberate: every
phase below ends with "the suite is green", and that claim is worth exactly what this floor is worth.
Both the peer and the driver placed it first, independently.

**Round 2 challenged Phase 0's SHAPE, and the challenge is half right.** The Cascade Analyst seat called it
"a bag of unrelated prerequisites" - 0a a docs fix, 0b a CI fix, 0c a plugin fix - warning that batching
them means one failure blocks the others. **They do share a property, and it is the one that matters: each
is a thing every later phase ASSUMES is true.** That is what a prerequisite is, and prerequisites are not
required to be semantically related to each other.

**But the seat is right that they must not be one commit.** 0c-local is not even committable, 0b touches CI
and can red the gate, and 0a now ships a guard. **Land them as three independent commits in the order
0c, 0a, 0b**, so a failure in any one does not strand the others.

**The fix is NOT raising the integer, and the peer's "trivial - raising an integer" was wrong in a useful
direction.** A static floor rots the moment a suite is added. `test-suite-registration.Tests.ps1` also
parses the justfile's fast/slow partition and asserts every suite on disk appears in exactly one half -
and `:131` ("names no suite that is missing from disk") is the row that catches a *rename*, because the
recipe still names the old path while `git ls-files` no longer does. **That row does key on the justfile**,
which is what makes the scope-decision below load-bearing.

**Sweep the same defect class while in there.** That registration suite's own floors are
`Should -BeGreaterThan 5` on each partition and `-BeGreaterThan 20` on the on-disk enumeration, against 50
suites. The guard against weak floors is itself weakly floored.

**Reviewed by:** unchanged disciplines. This phase touches no skill and no hook.

### Phase 1 - OUTPUT: §21 then §23

**§21 - the peer reply contract.** The owner has already fixed its internal order and it is committed in
the ROADMAP; it is NOT re-litigated here:
1. the anti-wrap-up clause, shipped standalone into all four skills' closers;
2. the peer-side table shipped as **`claim-type`, not "disposition"** - the payload already ships a
   5-token AGY-SCOPE disposition set (`FOLDED`, `REJECTED`, `DISCARDED-BELOW-FLOOR`,
   `DEFERRED-TO-ANOMALIES`, `UNVERIFIED-ACCEPTED`) at **repo `agy-capstone/SKILL.md:358-360`**, a different
   axis under the same word. **The first draft cited `:191`, which is the INSTALLED copy's numbering; the
   argument holds, the anchor did not** (see §1a);
3. `confidence` shipped as a POINTER with its measured false rate written in;
4. the JSON shipped INLINE plus a checker, separately.

**§23 - the AGY-TEST-AUDIT ledger.** The audit records no audited range anywhere. Note the ROADMAP entry
records that this item's original capture premise was FALSE and the corrected finding is larger; read the
section, do not re-derive it.

**Why OUTPUT goes first, and the reason is stronger than the peer's.** The peer argued §21 is a multiplier
that makes later capstones mechanically verifiable. **Measured 2026-08-31: that multiplier does not exist
yet.** Two findings, both from live consults today:

- **The checker is schema-rigid.** `scripts/check-peer-reply-citations.py:12` hardcodes a ten-key schema
  including `trigger`. The AGY-TEST-AUDIT brief used `missing_test` for that slot - a reasonable
  per-discipline variation - and every row failed on SCHEMA, so **the citation check silently never ran**.
  A control on a capstone reply using `trigger` passed 4/4, so the checker works; it just cannot survive
  a discipline using different keys. **This is a requirement for §21 step 4, discovered by measurement.**

  **Round 2 sharpened this into a constraint rather than a fix, and it is the more useful form.** The
  Protocol Pedant seat: *"if the checker absorbs arbitrary schema variations, it is no longer a rigid
  protocol. A parser that silently ignores schema drift cannot enforce a contract."* That is right, and it
  rules out the obvious repair. **So step 4's requirement is a schema each discipline DECLARES, validated
  strictly against that declaration** - not a universal ten-key list, and not a parser loose enough to
  swallow anything. A checker that accepts `missing_test` because it accepts everything has the same value
  as one that rejected it: neither is reading the citations.
- **The reply body is DISPLACED, not truncated - and the first draft of this document had the diagnosis
  wrong.** The sequencing consult returned only its `## Anomalies noticed` block and the verdict token;
  the body was lost, and this was written up as "the inline reply channel truncates". **That is false, and
  the ROADMAP at HEAD already said so** (`clavity-dotnet/ROADMAP.md:1884`: *"Nothing was ever truncated.
  The wrong message was collected."*, and `:1917-1919` names this exact write-up as one made before
  probing). `AnswerTruncated` was `false` on all four probes - a field that was available and unread.
  **The measured mechanism is that a brief asking the peer to write a reply FILE makes the peer treat the
  file as the deliverable, degrading its inline message to a receipt.** The fix is one sentence in the
  brief stating the file is not a substitute for the message; it was applied to this document's own panel
  round 1 and the full body arrived inline with `AnswerTruncated: false`. **It still argues for §21's dual
  prose/JSON output** - a durable artifact beats a chat message - **but for that reason, not for a
  truncation that does not happen.**

So every round run before §21 lands is a round whose brief asserts citations are "checked mechanically"
while they are not. That is a False Safety Promise in our own instructions, and it argues for OUTPUT
first more strongly than the multiplier argument does.

**Reviewed by:** the CURRENT discipline versions. Phase 1 changes no conduct rule, so the reviewer is
unchanged by its own subject matter.

### Phase 2 - CONDUCT: §24, then §25

**§14h was the first item here and has been REMOVED - it shipped in `a652d8d`** (see §1a). Its removal
takes the phase from three items to two. **It does not shrink the blast radius**: §25 still edits all four
skill pairs, so `agy-first` remains in scope for this phase.

**§24 - AGY-FIRST becomes mandatory when a capstone round develops new code.** Trigger is mechanical: a
new file, a new function/class declaration, or a whole-function rewrite, in non-test shipped code. It
PAUSES the fold rather than aborting the round.

**§25 - a negotiation discipline in all four review-only skills**, with AGREEMENT explicitly NOT the
criterion; the criterion is EXHAUSTION OF EVIDENCE - one measured round each, then straight to the human.

**Internal order: §24 then §25.** The first draft ordered §14h first, arguing its seats supply
independence that mitigates §24's rubber-stamp problem. **That argument is now moot in the best way:
§14h already shipped, so the mitigation is already in place before §24 starts.** The reasoning is worth
keeping for §24's own design, though, and one half of it was wrong: a persona is the same model in the
same cascade under a different framing, so seats are *not* reviewer independence, and §24's stated problem
is about *who* reviews ("the SAME peer ... a design it endorsed"), not in what voice. Seats MITIGATE and
do not resolve - which is why the open question below is still open.

**§25 stays in this batch. The owner rejected the peer's recommendation to defer it, on measurement.**
The peer's Resource Vampire objection targets unbounded multi-turn negotiation. The committed §25 is
explicitly bounded - "AGREEMENT is the wrong criterion", "one evidence round each, then straight to the
human". It is arguing against a design that was already refined away, **and the refinement exists because
this same peer argued for it in the previous consult.** A fresh cascade carries no memory of its own
contribution. Its accompanying "15+ rounds" estimate for the rejected shape is speculation, not
measurement, and is recorded as such.

**THE OPEN QUESTION THIS PHASE MUST CLOSE.** §24's STRUCTURAL INDEPENDENCE PROBLEM is owner-deferred to
plan time, and this is plan time: **may the design consult and the review rounds be the same peer?**
§14h shipping first does not answer it - it only softens it. The Phase 2 spec must put this to the owner
explicitly rather than inheriting it.

**Reviewed by:** a discipline version this phase is itself changing. State in the Phase 2 plan whether
each round runs under the pre-change or post-change rules, and do not let a round silently switch.

**That instruction FAILS OPEN, and panel round 1 said so.** The peer's Cascade Analyst seat:
*"Stating a version in a markdown plan does not mechanically bind the agent executing the review."* It is
right, and §1a is the proof - the version that actually bound this document's own panel was the installed
one, which no statement in any plan would have changed. **So the Phase 2 plan must record the reviewing
version as a SHA it can be checked against, not as prose**, and 0c is what makes that sha meaningful.

### Phase 2b - §27, the marker-write gate  — **AMENDMENT, owner-ruled 2026-09-03**

> ⚠ **THIS PHASE WAS NOT IN THE 2026-08-31 SEQUENCE.** It is an amendment, added the day §27 was specced,
> and it is marked as one rather than folded silently into a panel-reviewed artifact. §27 did not exist
> when the phases were composed.

**§27 - gate the completion-marker write on a ledger row.** Spec:
`docs/superpowers/specs/2026-09-03-marker-write-gate-design.md`. AGY-FIRST consults:
`.clavity/seams/agyfirst-s23-behavioural-gate.md` (the decision) and
`.clavity/seams/agyfirst-s27-phase2-fold.md` (this placement).

**It gets its OWN phase, sequenced after Phase 2 - it is NOT folded into it, and it is NOT Phase 3.**

**Why not Phase 3, though it edits a hook.** This sequence draws its phase boundaries by SUBJECT, not by
file type, and `:401` says so in its own words: Phase 3's batch is justified because *"none touches
review-discipline semantics, so this batch is immune to the self-reference problem that split Phases 1
and 2"*. §27 edits `agy-mark.sh`, a hook - but it defines what a valid completion contract IS, and its
constraint C2 turns on the semantics of a `round-cap` waiver. **It touches review-discipline semantics
squarely, so it lands on the Phase 1/2 side of the axis.**

**Why not folded into Phase 2.** REVIEW LENS DILUTION. Phase 2 is persona and prompt work; §27 is bash,
git sha resolution and ledger parsing. One adversarial panel hunting across both domains splits an
attention budget that this repository has already measured to be the binding constraint - a fold
introduced a defect in five consecutive review rounds during §23. A regex flaw in `agy-mark.sh` is
exactly the kind of thing that slips through while a panel is arguing about prompt engineering.

**Two arguments for this placement were CONSIDERED AND REJECTED, recorded so they are not re-run.** The
peer offered both; measurement killed both.

- *"Folding means §27 is reviewed by the drifted disciplines; deferring lets Phase 2 ship and re-satisfy
  0c-local first."* **REJECTED:** `:151` requires 0c-local re-satisfied after every phase that edits a
  skill, *"which is Phases 1 and 2"*. Phase 1 has ended, so the reinstall is owed BEFORE Phase 2 either
  way. It does not differentiate the options.
- *"Folding keeps the rule and its enforcement atomic."* **REJECTED:** the rule §27 enforces shipped in
  §23 (`4154800`), not in Phase 2. The rule-without-gate state already exists and folding into Phase 2
  would not make anything atomic. The atomic pairing was §23 and §27, and that opportunity is past.

🔴 **BLOCKING PRECONDITION FOR PHASE 2, AND THEREFORE FOR THIS ONE: 0c-local IS UNSATISFIED RIGHT NOW.**
MEASURED at `262386a` - `check-plugin-drift.ps1` reports **4 of 30 payload files drifted**, all four
review skills. The installed `agy-test-audit/SKILL.md` is **332 lines against the repo's 393 and contains
ZERO occurrences of the §23 ledger clause that shipped today**. **Owner ruled 2026-09-03: reinstall
BEFORE any Phase 2 work starts.** It is an operator action and Claude Code must be fully closed for it.

⚠ **§26 IS ALSO SPECCED, UNBUILT AND UNSEQUENCED.** Its own deferral condition (*"until §23 ships"*) has
fired. It is NOT placed by this amendment, and placing it is open work.

### Phase 3 - HOOKS: §31 FIRST, then §22 + two promoted backlog items

Four items share a blast radius - plugin hook pairs (`.sh`), mechanical, each with an already-measured
mechanism, and **none touches review-discipline semantics**, so this batch is immune to the
self-reference problem that split Phases 1 and 2:

- **§31 - RUNS FIRST, owner-ruled 2026-09-03. See AMENDMENT 3.** Two shipped SessionStart hooks misbehave
  in repositories that are not this one: `agy-anomaly-reminder.sh` renders as a red
  `SessionStart:compact hook error`, and `agy-discipline-reaching.sh` creates a `.clavity/` directory
  everywhere it runs. **It leads the phase because it is the only item in the backlog causing visible
  daily friction** - not because it is the cheapest. ⚠ **It shares `agy-discipline-reaching.sh` with §22
  below, so that file is edited and reinstalled TWICE; §22 must re-derive its site line numbers against
  post-§31 code rather than against the ROADMAP table.**
- **§22** - the leaking redirect order across 16 sites in four plugin hooks. `CMD > "$f" 2>/dev/null` does
  not suppress a failure to OPEN `$f`, because redirections apply left to right; the ROADMAP carries the
  full paired-control table.
- **`agy-mark.sh` accepts a non-existent sha** (`docs/backlog/agy-mark-accepts-a-nonexistent-sha.md`) -
  `head` mode writes any 40-character string with rc=0, so a debounce marker can hold a phantom commit.
  A guard that fails open.
- **Census the executable bit under `scratch/`**
  (`docs/backlog/peer-scratch-dir-contains-executable-session-hooks.md`) - record mode, not content, so a
  new `755` file in the peer's write zone is visible without sanctioned note-writing raising false alarms.

**Why third:** it is independent of the tangle, so it can wait safely, and waiting lets it run under
§21's fixed reply contract and §14h/§25's improved conduct.

**A live instance argues for the third item.** During the AGY-TEST-AUDIT the peer wrote **654 files /
12 MB** into `.clavity/scratch/` and the guard's 8-axis fingerprint did not move at all. That is by
design - `scratch` is censused by name only - but combined with three mode-755 scripts having been wired
as live session hooks from that directory, the write zone is demonstrably both unmonitored and a
code-execution surface. The hooks were un-wired on 2026-08-31, which closed the exposure and not the
question.

### Phase 4 - §15, workflow-position resilience

Spec complete and through **six adversarial panel rounds, all folded**
(`docs/superpowers/specs/2026-08-13-workflow-position-resilience-design.md`, committed `4adab8b`). It was
deprioritised, not cancelled, and it was gated on §17a - which has since shipped, so **it is now
unblocked**. Do not restart the design; read the spec. It inherits at least one unresolved gate: the
discipline's NAME waits on a measurement of whether bare `sync` actually flushes on this platform, and at
what cost under concurrent load.

### Phase 5 - §20, a mockable clock (`TimeProvider`) in `AgyView`, plus the Live Acceptance gating

**§20** - `AgyView` samples `DateTime.UtcNow` directly, making wall-clock an ambient dependency.
**The first draft cited `AgyView.cs:232` and `:243`; both are wrong and the scale was understated 4x.**
MEASURED at `4392ddf`: **eight** occurrences, at `:277`, `:288`, `:356`, `:400`, `:417`, `:445`, `:465`,
`:502`. Lines `232` and `243` are a `TryRemove` call and a doc comment. This matters because Phase 5 is the
phase whose budget is hardest to recover if wrong - it is the one that invalidates a capstone GREEN - and
because fabricated line precision is exactly what this repository's plan-vs-spec discipline forbids. Note the ROADMAP records that `AgyView` is implementation source,
so **§20 invalidates the AGY-CAPSTONE GREEN and requires a re-capstone** - owner-confirmed, and the only
phase here that carries that cost.

**Paired with it: the `Clavity.Live.Acceptance` gating.** Five files in
`clavity-dotnet/tests/Clavity.Live.Acceptance/` are referenced by no workflow and no justfile. They skip
without `CLAVITY_LIVE_AGY=1`, so CI never fails on them and never exercises them.

**Why here rather than a track of its own.** Three of those files construct
`new AgyView(new AgyViewOptions { ... })`, and §20's own ROADMAP entry says it **widens `AgyViewOptions`
or the constructor**. So they sit directly on §20's blast radius, and §20 is the moment someone is already
inside that code.

**What is and is not at risk, measured rather than assumed.** `Clavity.Live.Acceptance.csproj` **is** listed
in `clavity-dotnet/clavity.slnx`, and `ci-dotnet.yml:25` runs a bare `dotnet build` from `clavity-dotnet`,
so **CI does compile these files and a constructor change would red the build.** The compiler covers the
call sites. The residual exposure is narrower and is a vacuity risk rather than a breakage risk: nothing
runs these tests, so **drift in the skip condition or the `[Trait("Category","LiveAgy")]` attribute is
undetectable, and the failure mode is a vacuous pass the day someone finally runs them by hand expecting
coverage.**

The peer placed this in a separate later track, reasoning that Phases 0-4 do not touch .NET. That reasoning
is correct as far as it goes and misses Phase 5, which is exactly where the coupling is.

### UNSCHEDULED - `agy_status` misreports an idle peer as working

`docs/backlog/agy-status-reports-working-for-an-idle-peer.md`. This is the third item promoted at the
2026-08-31 triage, and it is **deliberately not given a phase**, for a reason that is itself the finding:
**it is intermittent and does not reproduce on demand.** It answered correctly throughout the whole
AGY-TEST-AUDIT session; the captured evidence is two polls with an unchanged `TotalSteps` returning
`working` while a `flaui` read showed the CLI idle at its prompt.

It is placed here rather than in a phase because scheduling a FIX for a defect with no reproduction is how
a plan acquires an open-ended task. **What it needs first is a reproduction or an instrumented capture** -
and until then it is not plannable, only watchable.

It matters more than its position suggests: it blocks the precheck-idle gate that ALL FOUR review
disciplines open with, and the realistic failure is not waiting forever but learning to ignore the gate -
which then also defeats it for the cases where the peer really is busy. The backlog file records a cheap
interim mitigation available to the driver today, with no code change: **treat an unchanged `TotalSteps`
across two polls as evidence of idleness regardless of the reported state**, which is precisely the
inference that identified the defect.

---

### Scope decisions for the owner - NOT scheduled work

Two findings from the same test-gating audit are **decisions rather than defects**, and are recorded here
so they are not silently carried as if they were tasks. Both reduce to the same question: *a test nobody
runs is not a test - wire it up, or delete it.*

- **Nine Python bridge test files** under `clavity-classic/agy-mcp-bridge/` have no `pytest` invocation in
  any workflow, justfile or hook. Verified: the `pre-commit` lefthook runs `ruff` on `.py` files, which is
  lint and format, not tests. Wiring them would need `uv run --project clavity-classic/agy-mcp-bridge pytest`
  and would surface however much rot has accumulated while they were unrun.
- **Three justfile recipes** - `test-scripts-fast`, `test-scripts-slow`, `test-scripts` - are invoked by
  nothing. Verified: 0 references outside their own definitions. `ci-scripts.yml` runs
  `Invoke-Pester scripts/tests` directly and bypasses them. **This is already known inside the repository**:
  `test-suite-registration.Tests.ps1:8-9` says so in its own header comment, which is also why that suite
  exists. **The recipes are not decorative, but the first draft named the wrong row.** The discovery-count
  oracle keys on `git ls-files` and does not need them. The row that *does* need them is `:131`, "names no
  suite that is missing from disk", which is the only check that catches a suite RENAMED out of the gate -
  a rename drops the file from `git ls-files` and from disk simultaneously, so the equality row at `:265`
  stays satisfied and sees nothing. **Deleting the recipes would delete the rename detector**, which is a
  narrower and more precise reason than "deleting the oracle", and still a sufficient one.
  **A second reason, measured during round 2: they are also the only local invocation path this suite has
  or could have.** `just test` does not run it; CI is the sole reader. Deleting them makes that permanent.

A third finding is **already tracked and is not re-opened here**: roughly 66 ghidrust live-worker tests run
nowhere automatically, because `ci-ghidrust.yml:31` deliberately runs `just test` without `GHIDRUST_E2E=1`
(its own comment says so) and the release workflow isolates exactly two named smoke tests. That is the
existing SP3 smoke debt.

---

## AMENDMENT 2 - placing the four orphans, owner-ruled 2026-09-03

> ⚠ **NONE of §26, §28, §29 or §30 existed when this sequence was composed on 2026-08-31.** They are
> placed here in ONE decision, and marked as an amendment rather than folded silently into a
> panel-reviewed artifact. AGY-FIRST consult: `.clavity/seams/agyfirst-s28-30-sequencing.md`.

**COMPOSITION IS NOT BATCHING, and that distinction is the ruling.** The peer recommended evaluating all
four together (its Q1) and then, in its own Q5, warned that batching them would couple three contained
fixes to a new feature and reproduce the review-lens dilution that kept §27 out of Phase 2. **Both halves
are right.** The four are placed in ONE decision, into FOUR different slots, on their measured blast
radii - which are genuinely different:

| item | files | shipped payload? | placed |
|---|---|---|---|
| §29a | `Clavity.Ls/{DisciplineContract,TerminalToken}.cs` + their dotnet tests | no | **Phase 0d - PREREQUISITE** |
| §28 + §30 | `scripts/*.ps1`, `scripts/tests/*.Tests.ps1` | no | **Phase 3b** |
| §26 | new analyzer + a generated README block | no | **Phase 6 - last** |

`check-seed-artifacts-synced.sh:23-24` walks only `hooks skills knowledge` inside the two plugin
directories, so **none of these four touches a byte-identical pair and none needs the `0c-local`
reinstall.** Only §27 (Phase 2b) does.

### Phase 0d - §29a, the 13b completeness check. PREREQUISITE, and BOUNDED.

**Why a prerequisite, and why this does not promote everything.** Phase 0's bar is *"everything after
them depends on their being true"*, which on its own would promote almost any bug. The narrower test
this phase actually applies - and 0b (the suite floor) and 0c (the drifted install) both fit it - is:
**the thing under repair is an INSTRUMENT OF VERIFICATION.** A broken instrument does not merely block
later work, it corrupts the evidence later work produces.

§29 is that: the 13b check certifies whether a consult reply is COMPLETE, and it currently tells the
driver *"Treat this consult as INCOMPLETE - do not fold findings from it."* **MEASURED 2026-09-03: the
first reply it flagged carried a confirmed BLOCKING defect.** Obeying it would have discarded that.

🔴 **BOUNDED, owner-ruled, because a prerequisite that is open-ended is how a prerequisite phase swallows
a schedule.** Phase 0's own items were each a known fix. §29a covers ONLY the measured half:

- the `GREEN` literal in `DisciplineContract.cs:25`, which makes **every findings-bearing panel round
  fail the check by construction** - the panel skill names "a list of the open findings" as a legitimate
  terminal disposition;
- the driver-side ECHO INSTRUCTION wording, which caused one of the false flags and is the driver's own
  fault: the brief told the peer to quote a line "with no backticks" and the source line contained them.

**§29b - the flag whose cause is NOT determined - is explicitly OUT of this prerequisite** and tracked
separately in the ROADMAP. It must not gate the sequence.

### Phase 3b - §28 + §30, repo tooling

**Batched, and for a real reason rather than a shared directory.** They share a blast radius (pure
PowerShell repo tooling, no shipped payload, no reinstall) AND a review lens - Pester testing and static
path/regex logic. That is the opposite of the §27 case, where a single panel would have had to split
attention between prompt engineering and bash-git parsing.

**Placed LATE because neither blocks anything.** §28's mechanism is proven but its per-site reachability
is not, and a short root is only ever caller-supplied; §30 is coverage debt on a suite that is green.

### Phase 6 - §26, the footprint analyzer. LAST.

**On its own merits, not batched.** §26 is the ONLY additive item in the whole sequence - every other
phase repairs something that is already wrong. It was deferred until §23 shipped, and that condition has
now fired, so it is unblocked rather than blocked; it is placed last because a repair-ordered sequence
finishes its repairs first. It also needs architectural design review that none of the others do, which
is precisely why batching it with §28/§30 would have diluted the lens.

## AMENDMENT 3 - placing §31 into Phase 3, ordered FIRST. Owner-ruled 2026-09-03.

> ⚠ **§31 did not exist when this sequence was composed on 2026-08-31, nor when AMENDMENT 2 placed the
> four orphans earlier the same day.** It is recorded as an amendment rather than folded silently into a
> panel-reviewed artifact. AGY-FIRST consult: `.clavity/seams/agyfirst-s31-sequencing.md`; the single
> negotiation turn that resolved it: `.clavity/seams/agyfirst-s31-negotiate.md`.

**PLACED: Phase 3, as a SEPARATE item, RUN BEFORE §22.** §31 meets every clause of Phase 3's own
criterion at `:446-448` - *"plugin hook pairs (`.sh`), mechanical, each with an already-measured
mechanism, and none touches review-discipline semantics"* - by direct reading. Both halves are bash
mechanics; neither touches review-discipline semantics.

**ONE item, not two.** 31a (`exit 2` rendering as a hook error on `compact`) and 31b (unconditional
`.clavity/` creation) share a single review lens with each other AND with §22's redirect-order work, so
splitting them buys nothing. This is the opposite of the §27 case at `:418-423`, where a single panel
would have had to split attention between prompt engineering and bash-git parsing.

### The AGY-FIRST consult inverted under challenge, and that is worth recording

The peer opened at `[VERDICT: NEGOTIATE]`, rejecting the frame: §31 was *"an active containment breach"*
warranting an immediate hotfix outside the sequence entirely. Its own Q4 objected that a hotfix would
ship before Phase 0 completed. **One negotiation turn, pointing it at files rather than handing it a
conclusion, collapsed both positions:**

- **The Q4 premise was FALSE.** Phase 0 is complete, Phase 1 shipped, and Phase 0c-local is satisfied -
  the four review skills measure 380/476/393/234 identically in `clavity-dotnet/plugin/skills/` and in
  the installed cache. The peer conceded: *"My objection collapses."*
- **"Containment breach" was OVERSTATED, and the peer downgraded its own wording** to *"a standard,
  contained defect"* after reading `agy-discipline-reaching.sh:129-132`, which writes `*` into
  `.clavity/.gitignore`. The created directory therefore never reaches the unrelated repository's
  `git status`. **The concrete harm is to the OWNER'S ATTENTION, not to any repository's integrity.**

⚠ **ONE PEER CLAIM WAS FALSE AND IS NOT FOLDED.** It stated that Phase 0's range was never capstoned.
`docs/agy-capstone-ledger.md` holds `ee2b385..4680613` and `4680613..9ef3f83`, whose commits are
`fix(capstone-r4)` through `fix(capstone-r11)`. It reasoned from the marker's current value instead of
reading the rows, and reached the right conclusion anyway - which is exactly how a false claim enters a
record uncorrected.

🔴 **DISCOUNT THE CONVERGENCE.** The peer ended on the placement this driver already favoured, after this
driver wrote the challenges. What makes it less suspect than the usual case: Phase 3's criterion is a
mechanical four-clause match, checkable by anyone who opens the file, not a judgment call.

### The ordering decision, and the cost the owner accepted

⚠ **"FIRST" MEANS FIRST WITHIN PHASE 3, NOT SOON.** Phase 3 is still the THIRD phase, so §31 remains
gated behind Phase 0d, Phase 2 and Phase 2b. **The owner was offered an immediate hotfix outside the
sequence and DECLINED it**, so this ordering is not a fast-track - do not read it as one, and do not
"rescue" it into an earlier phase on the grounds that it ships too late.

**MEASURED 2026-09-03: `agy-discipline-reaching.sh` is on BOTH lists, and the two edits are LINE-ADJACENT.**
It carries 3 of §22's leaking `CMD > "$f" 2>/dev/null` sites - **`:130`, `:132` and `:148` per §22's own
table** - while 31b's fix targets the unconditional `mkdir` at **`:123` and `:136`**. Those interleave
inside one ~30-line region that §22 separately flags as carrying prior-fold history at `:120-122`. §22's
four files are `agy-anomaly-capture-reminder.sh`, `agy-consult-guard-pre.sh`, `agy-discipline-reaching.sh`
and `assertion-strength-reminder.sh` - **read from §22's site table, not inferred** (`agy-shield-lib.sh`'s
6 sites were already fixed in the step-5 range and are the safe-order control, not a target).

The owner was offered merging the two into one pass and **ruled against it: §31 runs FIRST, as its own
item.** The reason is that §31 is the only item in the entire backlog causing visible daily friction - a
red `SessionStart:compact hook error` on every `/compact` in every repository where the plugin is
installed - so it is fixed earliest rather than most cheaply.

🔴 **THE ACCEPTED COST, recorded so a successor does not "optimise" it away:** `agy-discipline-reaching.sh`
is edited TWICE and mirrored-and-reinstalled TWICE. **That is the ruling, not an oversight.** §22 will
therefore review a file §31 has just changed; §22's plan must re-derive its site line numbers against
post-§31 code rather than against the table in ROADMAP §22.

**Blast radius.** Both §31 hooks are byte-identical pairs (`cmp` clean against
`clavity-classic/plugin/hooks/`) inside the `hooks` tree that `scripts/check-seed-artifacts-synced.sh`
walks. So §31 is class 2: **mirror to both plugins, and a plugin REINSTALL before either fix takes
effect.** Phase 3 already carried that requirement through §22, so §31 adds a second reinstall cycle
rather than a first.

**A constraint on 31a's fix.** The working precedent is `agy-anomaly-capture-reminder.sh`, which emits
`systemMessage` JSON on stdout with `exit 0` and renders cleanly. But 31a's header at `:9-12` records why
it chose stderr: at SessionStart there is no user turn, so stdout is absorbed into the model's context and
**the OWNER never sees it** - and the owner is who triages. Any fix must still reach a human surface on
`startup`. The root cause is a STALE ASSUMPTION, not broken logic: `:9-12` asserts *"exit 2 is
non-blocking for SessionStart"*, true when written for `SessionStart(startup)` (`:2`), and the matcher
later widened to `"startup|resume|clear|compact"` (`plugin/hooks/hooks.json:52`) with nothing watching.


## 4. What this sequence deliberately does NOT decide

- **The content of any phase.** Each carries its own committed ROADMAP section or backlog file.
- **§24's structural independence question.** Named as Phase 2's gating decision, for the owner.
- **Whether §15's naming measurement changes its design.** That belongs to Phase 4.
- ~~**The installed-plugin drift.**~~ **MOVED. It is now Phase 0c**, after panel round 1 measured the
  drift across all four review skills and the peer put it ahead of everything else. The first draft left
  it unscheduled and called that "a gap the owner should close deliberately rather than by omission" -
  the panel closed it, and the owner should confirm rather than re-decide. Background:
  `docs/backlog/installed-plugin-drifts-under-an-unchanged-version.md`.

## 5. Risks

- **Self-reference is reduced, not removed.** Phases 1 and 2 both edit the disciplines that review them.
  Each plan must state which version reviews it.
- **Phase 2 is the expensive one.** **Two** items (§24, §25), still across all four skill pairs - §24
  touches `agy-capstone`, §25 touches all four - and the only phase whose subject matter is the reviewer's
  own reasoning. If any phase overruns its round budget it will be this one. **The count read "three items"
  until round 3, stale since round 1 removed §14h.** An incomplete fold, in the risks section, in a document
  whose own opening finding is that stale indices misdirect work. **Note the item count fell and the BLAST
  RADIUS did not** - the first correction of this line said "three of the four pairs" and was wrong for
  exactly that reason.
- **Phase 1 must actually fix the checker**, not merely ship JSON. If step 4 lands a checker that is still
  schema-rigid, the multiplier that justifies OUTPUT-first never materialises and later phases inherit a
  gate that reports SCHEMA failures instead of checking citations.
- **Phase 0b must not delete the rename detector.** Narrowed after round 1. The discovery-count oracle
  keys on `git ls-files` and survives deleting the recipes; the rename detector at
  `test-suite-registration.Tests.ps1:131` does not. Sequence the recipe decision after 0b either way.
- ~~**Phase 0 now carries three deliverables it did not have when it was approved.**~~ **SURFACED AND
  RULED: the owner accepted the growth on 2026-08-31**, with the three landing as independent commits in
  the order 0c, 0a, 0b. Recorded here because the phase that was approved as docs-only is now the phase
  with the most new code, and a later reader should see that this was decided rather than drifted into.
- **The 50-suite Pester net has exactly one invocation path** (`ci-scripts.yml:199`). Measured at
  `f4b128a`. Nothing runs it locally, so every assertion in it is invisible until a push - which also means
  every phase's "the suite is green" is a claim about CI, never about the working tree.
- **THE PANEL'S OWN RESULT IS THE STRONGEST RISK IN THIS LIST.** Round 1 found that this document
  scheduled sixteen-day-shipped work (§14h), cited two skill lines that exist only in a stale installed
  copy, and mis-cited §20 by 4x - and it found them by opening the files rather than by reasoning. **Every
  phase below is authored the same way this one was.** Treat 0c as the mitigation and read every later
  citation as unverified until measured.
- **The peer's round 1 was 5 findings, 4 of them real, and it missed every citation defect.** It found the
  drift (independently and first), the fail-open "state the version in the plan" instruction, the
  unmeasurable §14f criterion, and the doubled sync cost; its Mechanism Gamer seat honestly returned "no
  new findings"; its Resource Vampire finding restates a cost `:63-71` already accepts with a reason it
  does not engage. **It found nothing that required reading a cited line.** That is the division of labour
  to expect: the peer reasons about the artifact's shape, the driver measures its claims.
- **Phase 5 is the only phase that invalidates a capstone GREEN.** `AgyView` is implementation source, so
  §20 requires a re-capstone over the new code - owner-confirmed in the ROADMAP. Budget for it.
- **The peer's advice was 1 of 3 correct on its supporting claims in the sequencing consult, and 2 of 4
  in the placement consult** - "fixing the floor is trivial, raising an integer" understated the fix and
  missed that the repository already holds the right oracle, and its reason for deferring the Live
  Acceptance work missed Phase 5 entirely. Its central reframing was sound both times. Later consults in
  these phases should be read the same way: adopt the reasoning, measure the facts.
- **The peer's cost argument is conditional and is recorded as such.** It argued that anything inserted
  before Phase 1 is paid at the expensive pre-§21 capstone rate. That assumes §21's multiplier exists;
  measured today, it does not. If Phase 1 fails to deliver it, that argument never applied to anything.

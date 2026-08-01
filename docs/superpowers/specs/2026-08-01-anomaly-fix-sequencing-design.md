# Anomaly fix sequencing — design

**Goal:** close every entry in `.clavity/local-anomalies.md` by fixing the underlying defect, in an order
that makes each fix cheaper and better-verified than the one before it.

**Status:** design agreed. Sequence converged with the agy peer over an AGY-FIRST consult plus one
AGY-NEGOTIATE round with real position changes on both sides (recorded below).

---

## Context — where these came from

The anomaly-capture mechanism shipped on 2026-08-01 (`32eeacb`..`9a3e23f`). Its purpose is that an agent
noticing a defect while doing something *else* records it durably instead of mentioning it in prose that
scrolls away. It worked: the file reached **8 entries within hours**, and 3 of those were found *by the
mechanism's own construction* — 2 while committing its panel folds, 1 during the capstone.

The owner's ruling on triage: **close the existing anomalies before implementing new features**, where
closing means *fixing the defect*, not merely filing it. The file empties as a consequence.

**The triage outcome, against the criterion the owner set.** The owner defined the test's failure condition
as *"a third outcome appears in practice"* — an entry fitting neither PROMOTE nor DELETE. **It did not
trip.** All 8 entries took one of the two legal outcomes. Recorded because a criterion that never fires is
worth as much as one that does, and because the sibling mechanism failed this exact test the same day (see
"Precedent" below).

### Disposition of all eight

| # | Entry | Disposition |
|---|---|---|
| 1 | consult-guard classifies a Bash call by grepping the whole command for `clavity ask` | PROMOTE → **M3** |
| 2 | consult-guard matcher names a plugin id that no longer exists; dead on the MCP path | PROMOTE → **M3** |
| 3 | `agy_look` truncates the newest reply out of a long cascade | **DELETE** — already tracked in `project_agy-trajectory-readback.md`, root cause found (`LsChannel.cs`, 4 MB default), backlog item `grpc-default-max-message-size` emitted |
| 4 | `just test-scripts` straddles the 600s tool cap | PROMOTE → **M1** |
| 5 | a dispatched subagent wrote outside the file set it was given | PROMOTE → **M4** |
| 6 | the byte-sync gate's FILE list is an allow-list, so new shared files are never compared | PROMOTE → **M2** |
| 7 | the live GROWTH region was mojibake-corrupted for 13 days while its sidecar matched | **DELETE (artifact)** — republished clean and ASCII-only during the 2026-08-01 curate drain. The *class* survives → **M5 (E)**, relocated there from M2 by panel round 1 |
| 8 | `agy-curate` cannot satisfy its own "empty the inbox" step | PROMOTE → **M5** |

### Precedent — the sibling mechanism failed the same test on the same day

`agy-curate` is the same shape as this project's triage half: a manually-invoked skill carrying a prose
procedure, with no executable workflow. Its inbox reached **79 entries against a stated threshold of 8**.
Draining it on 2026-08-01 routed 71 and stranded 8, because its Finish step ("empty the inbox") is
unsatisfiable against its own promotion rubric (which forbids promoting an unverified Empirical Assumption)
whenever the verify harness is stale — which it is, stamped agy 1.1.1 against a live 1.1.9.

That is a third outcome appearing in practice, in production, in the mechanism this one was built to
improve on. **M5 fixes it.** It is listed last not because it is unimportant but because it is prose with
no mechanical oracle, and the milestones with oracles should land while attention is sharpest.

---

## The sequence — T → S → G → D → [C+E]

Five milestones. Each is independently committable, independently verifiable, and a valid stopping point.
No milestone depends on a later one.

### How the order was decided, including where each party was wrong

- **I had T last**, filed as ergonomics. The peer argued it is a velocity multiplier for every fix after
  it: four of the five remaining milestones each need a full gate run to verify, at roughly ten minutes a
  run. **That argument was correct and I changed position.**
- **The peer's stated justification for T was overstated**, and the correction matters. It argued T-first
  removes the risk of "600s tool timeouts or false test-hang abortions." MEASURED: four runs the same day
  at 917s, 650s, 586s and 590s, and **none timed out**, because each was backgrounded. T's real
  justification is ~10 minutes of dead wall-clock per verification × 5, not a hazard that fires. An
  ordering justified by a non-firing hazard is one a later reader can argue away.
- **The peer put G before S; I disputed it and it conceded, with a check rather than an echo.** Under
  today's allow-list gate, G's three new shared files would need manual enrolment, which S then deletes —
  throwaway work. Worse, it forfeits the best available evidence that S works: S landing first makes G's
  arrival a **non-synthetic** proof of the discovery gate. The peer verified the reverse dependency I asked
  it to attack: G's files are transport-agnostic, byte-identical across both plugins, and do not touch the
  twin deny-list, so S needs no prior knowledge of G.
- **The peer argued to drop E entirely; I disputed it and it conceded** — and then the panel proved the
  peer's *original instinct* right and my counter wrong. I argued E into M2 on COST (~5 lines, same file,
  same harness). Cost was never the issue: **E in M2 both breaks the untouched baseline and targets the
  wrong artifact** (both MEASURED — see the note in M2). E now lives in **M5**, at the publish path where
  the corruption actually entered.

**How that error was reachable, since it is the most instructive thing in this document.** During the
negotiation I explicitly invited the peer to argue that folding E into S was scope creep. It agreed with me
instead of attacking, and I recorded that as an unexamined risk rather than resolving it. The panel round
then examined it and found two independent disqualifiers. **A risk you notice, name, and then carry forward
unresolved is still an unfixed defect** — flagging it bought nothing except the ability to say afterwards
that it had been flagged. The scope boundary M2 carries below was written as compensation for that
unresolved risk; it survives on its own merits, but it was not a substitute for answering the question.

---

## M1 — T: partition the test gate

**Problem.** `justfile:91-92` defines `test-scripts` as `pwsh -c "Invoke-Pester scripts/tests -Output
Detailed -CI"` — the whole directory, 358 tests. Measured runtimes: 917s, 650s, 586s, 590s against a 600s
foreground tool cap. It **straddles** the cap: it works until it doesn't, which is worse than being
reliably over.

**Change.** Split into a fast recipe and a slow one, partitioned **by runtime**, and make the slow path's
backgrounding an explicit documented instruction rather than folklore.

**Oracle.**
- The fast recipe completes well under 60s.
- **Total test count across all recipes equals 358.** The guard against the obvious cheat: making the fast
  number look good by dropping coverage. Every test must remain reachable from some recipe.
- **The slow recipe must run somewhere on a stated cadence** — named in the justfile comment and wired into
  whatever CI or pre-push path already exists. *Panel finding (Mechanism Gamer): the count assertion alone
  is gameable.* All 358 tests can still exist while the slow half runs nowhere, which satisfies the count
  and silently retires half the suite. The count proves nothing was deleted; only a stated run cadence
  proves anything is still executed.

**Where new tests land.** *Panel finding (Cascade Analyst): M2, M3 and M4 each add tests, and M1 does not
say into which half.* Rule for the milestones that follow: a new test goes in the FAST recipe unless its
measured runtime forces otherwise. **M3's guard integration test is fast-recipe by default** — it builds a
temporary git repo and pipes synthetic payloads, work measured in hundreds of milliseconds, not the
multi-second Pester fixtures that dominate the slow half. If any new test does land slow, that milestone
must say so explicitly, because a guard covered only by a suite nobody runs is the failure this whole plan
exists to end.

**Risk.** Splitting by the wrong axis (by file, by subject) leaves the fast gate not gating anything
load-bearing. The partition is by measured runtime; the count assertion and the cadence requirement are
what make the split falsifiable.

---

## M2 — S: auto-discovery sync gate

**Problem (S).** `scripts/check-seed-artifacts-synced.sh:15-27` gates cross-plugin files through an
explicit `for rel in` allow-list of 12 entries. Anything not named is silently never compared. **MEASURED:
a skill created only in `clavity-dotnet` left `just seed-sync-check` GREEN.** This is the same shape as the
`SessionStart` allow-list defect fixed in `da18681`/`18495cd` — omission is indistinguishable from
synchronisation, and the gate reports the same green for both.

**Problem (E).** The live GROWTH region carried 22 CP437 mojibake sequences and zero real em-dashes for 13
days while its `.sha256` sidecar **matched**, because the corruption preceded the commit. An integrity
sidecar catches torn writes; it cannot catch content that was already wrong. The artifact is fixed and is
now ASCII-only; nothing stops the next publisher reintroducing non-ASCII.

**Change.** Replace the allow-list with directory discovery over the shared plugin trees, deny-listing the
intentionally-divergent twins.

> **E MOVED OUT OF M2 — panel round 1, and the panel was right against me.** An earlier version of this
> milestone folded in "an assertion that discovered shared files are pure ASCII". That was wrong twice over,
> both MEASURED:
> 1. **It breaks the untouched baseline.** 383 non-ASCII lines across 11 files in those trees, 5 of them
>    shared, using deliberate typography — em-dashes, middle dots, banner emoji. The oracle "the untouched
>    baseline must stay green" and the assertion cannot both hold.
> 2. **It targets the wrong place.** The 13-day corruption happened in `~/.clavity/golden-header.growth.md`
>    — a *published runtime artifact* outside the repository entirely. An ASCII check over the repo's
>    plugin trees would never have caught the defect it was meant to prevent.
>
> **E moves to M5**, which already touches the curate skill that owns the publish path where the corruption
> actually entered. The peer's opening position had been to drop E from this plan; I argued it into M2 on
> cost, and cost was never the issue — target was. Recorded because winning a negotiation on the wrong axis
> is not a small error.

**The deny-list is exactly five files, ENUMERATED BY MEASUREMENT** — a `find` over both plugins'
`hooks/`, `skills/` and `knowledge/` trees, diffed. Do not infer this list; it is the complete set of files
present in one plugin and not the other as of `9a3e23f`:

| Present only in `clavity-classic` | Present only in `clavity-dotnet` |
|---|---|
| `hooks/agy-drive-session-reset.sh` | `skills/ls-driving/SKILL.md` |
| `skills/driving/SKILL.md` | `skills/ls-pairing/SKILL.md` |
| `skills/responder/SKILL.md` | |

The two skill pairs are transport twins (`driving`/`ls-driving`, `responder`/`ls-pairing`); the reset hook
is a classic-only variant behaviour. Everything else in those three trees is shared and must be compared.

**Correction folded during the spec audit, recorded because the error is instructive.** An earlier draft of
this section listed `README.md`, `plugin.json` and `NOTICE` as deny-list entries and omitted
`agy-drive-session-reset.sh`. Those three files live *outside* `hooks/skills/knowledge`, so under M2's own
scope boundary discovery never reaches them and denying them is meaningless — while the reset hook, which
discovery *does* reach, was missing. The list had been carried from a peer's summary rather than measured.
`hooks.json` is handled separately by the three per-block comparisons and stays that way.

**SCOPE BOUNDARY — load-bearing, because the peer declined to attack it.** M2 covers the two plugins'
`hooks/`, `skills/` and `knowledge/` trees **only**. It does not become a general repository linter, it
does not police files outside those trees, and E is an assertion *inside* the existing gate, not a new
gate with its own recipe. If implementing M2 requires touching anything outside those three trees, that is
the signal the scope has slipped and it stops for a decision.

**Oracle.** The mutation matrix already used for `18495cd`, extended:
- a file created in only one plugin **must fire** (currently green — this is the defect);
- a file deleted from one plugin must fire;
- a shared file whose content differs between plugins must fire (the existing behaviour, unregressed);
- every intentionally-divergent twin must stay green;
- the untouched baseline must stay green.

*The row "a non-ASCII byte in a shared file must fire" was removed with E.* It was not merely stale — it
**directly contradicted the row below it**, since 5 shared files in these trees carry deliberate non-ASCII
typography, so the baseline could not stay green while that row held. Two adjacent oracle rows asserting
incompatible things is the kind of defect that only surfaces when someone tries to satisfy both.

**Residual limit to state, not hide.** Discovery replaces an enrolment allow-list with a *divergence*
deny-list. That is strictly better — the failure mode inverts from "silently unchecked" to "loudly
over-checked" — but a newly-added intentionally-divergent file will now fail the gate until it is
deny-listed. That is fail-closed and intended.

---

## M3 — G: relocate and fix the consult guard

**Problem.** The VCS-diff consult guard (`agy-consult-guard-lib.sh` 96 lines, `-post.sh` 91, `-pre.sh` 42;
229 total) exists **only** in `~/.claude/hooks/`. No copy in the repository. It is therefore unversioned,
untested, absent from every installer, uncovered by the sync gate, and lost on a machine rebuild — while
every sibling hook of its family ships inside the plugins with all of those properties.

It is also broken two independent ways, both reproduced:

1. **Dead on the primary path.** `~/.claude/settings.json:46,66` declare the matcher as
   `"Bash|PowerShell|mcp__plugin_clavity-dotnet_clavity-ls__agy_ask"` (lines 50 and 70 are the `command`
   entries beneath them — the distinction matters, see the note below). The live tool is
   `mcp__plugin_clavity_clavity-ls__agy_ask`. **Root cause:** `settings.json:108` enables
   `"clavity@clavity-dotnet": true` — the plugin is *named* `clavity` from the *marketplace*
   `clavity-dotnet`, and the matcher was written with the marketplace name. Two similar identifiers, wrong
   one chosen. The guard has never fired on an MCP consult.
2. **False-positive on the shell path.** `agy-consult-guard-lib.sh:60-62` classifies a Bash call by
   grepping the **whole command string** for `clavity[[:space:]]+ask`. So any command whose *text* merely
   mentions it — a commit message, a heredoc — is classified as a review-only consult, and the driver's own
   commit inside that same call is then reported as the peer modifying version control. **Reproduced:** two
   identical commits differing only in message text give warn vs silent.

Net: **silent where it matters, noisy where it does not** — the worst combination, because the noise trains
the operator to ignore the guard while the silence removes the protection.

**Change.** Move all three files into `clavity-dotnet/plugin/hooks/` and `clavity-classic/plugin/hooks/`,
byte-identical. Fix the matcher. Fix the classifier to anchor on **command position** (start of string, or
after a shell separator) rather than any occurrence. Register in both `hooks.json`. Enrolment in the sync
gate is **automatic** via M2.

**The matcher takes a PATTERN, not the corrected literal.** *Panel finding (Activation Auditor): an earlier
draft said only "fix the matcher to the real namespace", which would repair today's breakage and leave the
mechanism that caused it fully intact.* A literal tool name is exactly what broke — and it broke on a
plugin/marketplace naming distinction the operator can change at install time, so the "correct" literal is
not even stable per-machine. The matcher becomes `mcp__.*agy_ask`, which survives any future rename of the
plugin or its marketplace.

The obvious objection is that a pattern is a broader match than a literal. That is accepted deliberately:
the cost of over-matching is a snapshot taken around a call that was not a consult (cheap, and the diff
simply comes back clean), while the cost of under-matching is the guard silently not existing — which is
the defect being fixed. **Asymmetric costs, so prefer the over-matching side.** The manifest assertion
below then checks consistency; the pattern is what removes the fragility rather than merely re-pointing it.

**THE FULL MATCHER STRING IS `Bash|PowerShell|mcp__.*agy_ask` — all three alternatives.** *Panel round 1
(Mechanism Gamer), confirmed by measurement.* An earlier draft said "the matcher becomes `mcp__.*agy_ask`",
which reads as the whole matcher rather than one alternative in it. Implemented literally, that drops the
`Bash|PowerShell` tokens — and those are the ONLY thing that makes the guard fire on the CLI consult path
(`clavity ask` / `send` / `await-reply`, which is how `clavity-classic` consults at all). The fix for a
guard dead on the MCP path would have killed it on the shell path instead, converting a half-dead guard
into a fully dead one. Write the matcher out in full in both `hooks.json` files; do not paraphrase it.

**Portability is established, not assumed.** MEASURED: the only environment dependency in the whole guard
is `${TMPDIR:-/tmp}` at `agy-consult-guard-lib.sh:43`; there are no operator-specific paths. Living in
personal config was an accident of how it was built, not a property of what it does.

**Self-evidence requirement — this is a requirement, not a nice-to-have.** The guard died silently because
when the matcher drifts, *neither* hook fires, and a Post hook cannot warn about a missing Pre baseline if
Post never runs. M3 therefore ships:
- an **integration test** feeding synthetic `PreToolUse`/`PostToolUse` payloads for both the MCP and CLI
  paths against a temporary git repo, mutating a file mid-consult, asserting the guard warns;
- a **manifest assertion** that any MCP tool name referenced in a hook matcher matches the actual plugin
  namespace — the specific drift that killed it.

**Oracle, and the non-negotiable part.** The integration test **must be seen RED against today's code**
before it is made green. A guard test written after the fix, never observed failing, proves nothing — and
"never observed failing" is exactly how this guard reached production dead. This project has already
shipped two vacuous tests that only mutation caught; this is the third chance to not do that.

---

## M4 — D: dispatch file allow-list

**Problem.** A dispatched subagent wrote to a file outside the set it was told to touch (observed during
the productize epic, task T8). Nothing prevents it. The only mitigation is the driver diffing afterwards,
which is one driver's habit rather than a shipped mechanism.

**Change.** Extend the dispatch clause in `clavity-{dotnet,classic}/plugin/skills/open-issues/SKILL.md`
and the `anomaly-dispatch` directive in `agy-seam-inject.sh` so that a dispatch **states its file
allow-list** and the driver **verifies the actual change set against it** before accepting the work.

**Correction to the peer's suggestion:** it named `subagent-driven-development/SKILL.md` as an edit target.
That is a superpowers skill this project does not own. The two surfaces we ship are the `open-issues` skill
and the seam directive; those are the ones that change.

**Oracle.** `scripts/tests/agy-seam-inject.Tests.ps1`, extended: the injected directive must contain the
allow-list instruction, with a mutation row proving the assertion is not vacuous.

**Honest limit.** This raises the floor; it is not a gate. A subagent can still write outside its list, and
a driver can still skip the diff. What changes is that the expectation is stated in the artifact both
parties read, instead of living in one operator's habits.

---

## M5 — C+E: give `agy-curate` a legal end state, and guard its publish path

**Problem.** `agy-autotrain/skills/agy-curate/SKILL.md` instructs, in its Finish step, to empty the inbox.
Its promotion rubric forbids promoting an Empirical Assumption without a 100% verify-harness pass. When the
harness is stale, assumption-class entries are neither promotable nor droppable, and the skill defines no
state for them. **MEASURED 2026-08-01: 79 entries in, 71 routed, 8 stranded**, harness stamped 1.1.1
against live 1.1.9.

**Change.** Define the missing state explicitly — a HELD disposition with a recorded blocking reason and
the condition that would release it — and reword Finish so "empty" means "every entry routed, promoted,
dropped, or explicitly held with a reason", which is satisfiable.

### E — the encoding guard, relocated here from M2

**Problem.** The live GROWTH region carried 22 CP437 mojibake sequences and zero real em-dashes for 13 days
while its `.sha256` sidecar **matched** — the corruption preceded the commit, so the integrity check
confirmed corrupt content. An integrity sidecar catches torn writes; it cannot catch content that was
already wrong when it arrived.

**Why it belongs in M5 and not M2.** The corrupted artifact is `~/.clavity/golden-header.growth.md`, a
published runtime file outside the repository. The thing that publishes it is the curate skill this
milestone already edits. M2 could not have caught this defect at any scope that also left its baseline
green — MEASURED, and the reason E moved.

**Change.** Assert at the **publish step** that the compiled payload contains no CP437 mojibake signature
before `curate-commit` is invoked, and record ASCII-only as the standing policy for the compiled GROWTH
region (already true of the current published file, which this session republished clean).

**Why a mojibake-signature check and not a blanket ASCII rule.** The SEED region legitimately carries real
em-dashes and is not corrupt; a blanket non-ASCII rejection at publish time would reject valid content and
teach the operator to bypass the check. The signature is specific: the byte sequences that a CP437
round-trip produces (`ce 93 c3 87 c3 b6` and its family) are never intentional.

**Oracle.** Feed the publisher a payload containing a known mojibake sequence and assert it refuses;
feed it the current clean GROWTH and assert it passes. Both are cheap and both must be seen to behave
before the check is trusted.

### Oracle for the C half

None mechanical; this is prose in a skill. Stated plainly rather than dressed up: the C half of M5 is
review-enforced. Its correctness check is that re-reading the skill after the change yields a procedure
that terminates for the 8 entries currently stranded.

**Note.** This is *not* the same as reintroducing a parked state into the anomaly mechanism. The anomaly
file's two-outcome rule stays. `agy-curate` is a different mechanism with a hard external dependency (a
probe harness against a live peer) that the anomaly file does not have.

---

## Out of scope

- **Re-running the agy verify harness.** It is stale (1.1.1 vs live 1.1.9) and it blocks 8 curate entries,
  but it is a separate job with its own live-peer cost. M5 makes the *skill* terminate; it does not make
  the harness current.
- **Fixing `LsChannel.cs`'s `MaxReceiveMessageSize`.** Tracked as backlog item
  `grpc-default-max-message-size`; not one of the eight anomalies.
- **The in-process guard architecture (the peer's "Option D").** Moving the VCS check inside the consult
  entry points would make it immune to hook-matcher drift entirely, and the peer called it the cleanest
  long-term design. It is deliberately not in this plan: M3 ships the existing 229 lines with tests, which
  is the low-risk path. If M3's manifest assertion proves insufficient in practice, Option D is the
  escalation.

## Known limits

1. **M5 has no mechanical oracle.** Prose changes are review-enforced. Named rather than papered over.
2. **M4 raises a floor, it does not close a hole.** Compliance with a stated allow-list is unfalsifiable
   from the driver's side without diffing, and nothing forces the diff.
3. **M2 inverts a failure mode rather than eliminating it.** A missing deny-list entry now fails loud
   instead of passing silent. Better, not perfect.
4. **The sequence assumes no milestone is abandoned midway.** Each is independently committable, so a stop
   after any milestone leaves a consistent tree — but stopping after M2 leaves the guard still dead, which
   is the highest-severity open defect. If only one milestone can be done, it should be M3, not M1.
5. **The anomaly mechanism has a hedge at CAPTURE and none at TRIAGE — the same shape as the defect M5
   fixes elsewhere.** *Panel finding (Axiom Breaker).* The `open-issues` skill already admits a third
   capture path: an anomaly that "cannot be checked cheaply" is recorded as `reported, unverified:` rather
   than dropped. But triage still offers exactly two outcomes, and an entry whose reality cannot be settled
   without some blocked external dependency — a stale probe harness, an unavailable peer — is then neither
   promotable nor deletable on the evidence available. That is precisely the wall `agy-curate` hit with 8
   stranded entries.
   It has not bitten the anomaly file yet: all 8 entries triaged cleanly, and the owner's failure criterion
   did not trip. It is recorded here because the sibling proves the shape is reachable, and because
   discovering it the way `agy-curate` did — mid-drain, with no legal move — is worse than naming it now.
   **Deliberately NOT fixed in this plan.** Adding a HELD state to the anomaly file pre-emptively would
   reintroduce exactly the parked state the two-outcome rule exists to forbid, on a hypothetical. The
   trigger to revisit is the first entry that genuinely cannot take either outcome; until then the rule
   stands unweakened.

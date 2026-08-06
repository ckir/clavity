# Open-work reconsideration — design

**Status:** owner-approved 2026-08-06. AGY-FIRST consulted over two rounds (`open-work-ranking{,-r2}.md`).
**Base commit:** `885905a`.

**Goal.** Every recorded item across all six tracking surfaces ends in one of three states, each with
evidence attached: **CLOSED** (already shipped), **KILLED** (fails the bar), or **KEPT** — and every kept
item is then implemented. No item survives on reputation.

**New features are out of scope.** Everything here already exists as a recorded item. The question is
which deserve to exist, in what order, and which should stop existing.

## LIVE STATUS — read this before anything else

This spec was rebuilt across three adversarial rounds and **carries its own correction history inline**,
deliberately: the errors are instructive and hiding them would repeat them. **But that means a skimmed
sentence may be a recorded MISTAKE rather than an instruction.** Every such passage is marked "an earlier
draft…" — and this table is the authority if anything below appears to disagree with it.

| item | live disposition | decided by |
|---|---|---|
| **§7 AGY-SCOPE** | goes to the §5 gate — **spec it, or kill it** | owner, end of Phase 1 |
| **§0 DISCIPLINE EFFICACY** | **FAILS the bar on clause 1.** Goes to the §5 gate — **do you override?** Not a KEPT item today | owner, end of Phase 1 |
| **§8** | **CLOSE** — already answered by a shipped epic | Phase 1 |
| **§6** | ordinary Phase-1 item; "Owner-surfaced" is not a directive | Phase 1 |
| **§11** | **KEPT** — passes all three clauses | ranked 7th, Phase 3 |
| items 1–6 of §6 | **KEPT** — pass all three clauses | Phase 3 |
| **AT-1 Part B** | candidate **KILL** — needs binary changes the plugin forbids | Phase 1 |

**The two most-corrected claims in this document, so you distrust them by default:** §0's disposition has
moved **three times** under measurement, and the exception criterion in §2 was wrong once. If you need
either, read §7a and §5 — not a summary sentence elsewhere.

---

## 1. Why now, and the base rate that justifies the effort

The 2026-08-06 backlog-triage epic swept four surfaces and found **seven** recorded items describing work
that had already shipped. It deliberately excluded `ROADMAP.md` on the spec's belief that surface was
already in agreement with the code. **Within minutes of including it, two more stale entries surfaced:**

- `clavity-classic/ROADMAP.md`'s await-reply entry read *"a future enhancement, not yet implemented"* while
  Option D had shipped — closed at `885905a`.
- `clavity-dotnet/ROADMAP.md` §8 reads *"Status: brainstorming task, not yet designed"* while the
  cost/quota-hygiene epic shipped and reached capstone GREEN (`c7b3923..8889473`, ledger row 2026-08-03)
  and answered two of §8's three named levers.

**Nine stale items across five surfaces, all found by measurement, none by reading.** That is the base
rate this epic is sized against.

---

## 2. The disposition bar

Adopted from the AGY-FIRST consult, **unamended**. An item survives only if **all three** hold:

1. **Lie / loss / crash.** Its absence causes silent data loss, a crash or hang, or an **active lie** —
   a diagnostic that misdirects debugging. Architectural elegance, cosmetic debt and unmeasured curiosity
   do not qualify.
2. **Unavoidable.** It cannot be rendered harmless by an existing invariant or an ordinary driving
   convention.
3. **Concrete bounded mechanism.** No unresolved design fork, no unbounded research.

**Clause 3 KILLS; it does not park.** An earlier draft of this spec softened it to "evict to a needs-design
list". The peer's counter-argument was accepted: *a needs-design list is a guilt-free parking lot where
items rot without accountability, and killing is cheap because git is the undo.* There is no needs-design
list in this epic.

**Clause 1 needs a test, or it becomes a vibe.** "Active lie" means: **a diagnostic a competent operator
would act on, whose action is wrong.** `ChannelDown.Hint` qualifies — it names a dead peer and sends you to
inspect processes, when the peer is alive. An unhelpful-but-neutral message does not qualify. If you cannot
name the wrong action the message induces, clause 1 is not met.

### The §0/§7 exception, and the criterion that bounds it

`ROADMAP.md` **§7 fails clause 3** today — no mechanism. **§0 SATISFIES clause 3 but fails clause 1**
(§7a). Both reach the §5 gate; neither is auto-killed and neither is carried forward silently — but **they
get there by different routes and are asked different questions.**

⚠️ This sentence read *"§0 and §7 fail clause 3 today"* for two full rounds after that stopped being true.

🔴 **An exception with no criterion is the parking lot re-entering through the back door**, which is exactly
what accepting the peer's argument was meant to close. So the criterion is stated and it is narrow:

> An item qualifies for the §5 binding-ruling treatment ONLY if **all three** hold:
> **(a)** the owner has explicitly ranked or directed it on the record; **(b)** it fails clause 3 — no
> concrete mechanism exists yet; **(c)** it is not already answered or shipped.
> Everything else dies on clause 3.

🔴 **The first draft of this criterion said "no other open item has an owner priority directive, so the
exception admits exactly two." That was FALSE, and measuring it is what produced the three-part test
above.** Measured — `rg -n 'Owner-directed|TOP PRIORITY|BRAINSTORM FIRST|Owner ruling'` over all four
roadmaps returns owner markings on **§0, §7, §8, §9, §10 and §11**. Clause (a) alone would have admitted
six items and re-opened the parking lot at triple the width. What each of the extra four actually needs:

- **§8** — has an owner directive and fails (a)→(b), but **fails (c)**: the cost/quota-hygiene epic shipped
  and reached capstone GREEN (`c7b3923..8889473`), answering two of its three levers, while §8 still reads
  *"not yet designed"*. → **CLOSE it in Phase 1**, do not rule on it in Phase 2.
- **§11** — has an owner ruling (2026-08-02) but **passes clause 3**: its design is settled and the roadmap
  says *"Agreed shape (do not re-derive; these are settled)"*. → an ordinary **KEPT** item, implemented in
  Phase 3.
- **§9 and §10** — carry owner *dispositions* (*"does NOT gate the productize release"*, *"they are a
  follow-on, not a re-scope"*), which are rulings about scope rather than directives to do the work.
  → ordinary Phase-1 items, judged on the bar like anything else.

🔴 **The three-part criterion above admits §7 ONLY. §0 reaches the §5 gate by a DIFFERENT route — see
§7a — and this spec has asserted two wrong things about §0 in as many rounds.**

**What was wrong first:** an earlier draft said *"§0 and §7 fail clause 3: both are marked BRAINSTORM-FIRST
and neither has a specified mechanism."* **Both halves are false for §0:**

- `clavity-dotnet/ROADMAP.md:118` marks §0 **`▶ TOP PRIORITY`**, not `BRAINSTORM FIRST`.
- `clavity-dotnet/ROADMAP.md:177` reads **"THE SEQUENCE — OWNER-RATIFIED 2026-08-04, after a second
  AGY-FIRST consult and measurement"**, followed by a numbered sequence and settled sub-rulings including
  *"Owner ruling on the `PreCompact` channel, same date: ship dispatch-only."*

**So §0 PASSES clause 3** — *this is one clause of three, not a disposition.* Sending it to a *"spec it or
kill it"* ruling would pose a false dilemma about work that is already designed.

**What was wrong second, and is the live statement:** the next draft concluded from that §0 was *"an
ordinary KEPT item, ranked and implemented like any other."* **That does not follow — clause 3 is one of
three.** §7a shows §0 **fails clause 1**, so it fails the bar and is **conditional on an owner override**,
not an ordinary survivor. **§0 is not a KEPT item today.**

🔴 **Read §7a and §5 for §0's actual disposition; do not conclude it from this section.** This paragraph
stood contradicting them for a full round, and the identical mistake — a section left stale by a fold that
moved an item — had already been caught once in criterion 1. **When a fold moves an item, grep the whole
spec for that item's name before committing.**

**§6 is the near-miss worth naming.** `clavity-dotnet/ROADMAP.md:354` ends *"Owner-surfaced 2026-07-11"* —
**surfaced is not directed or ranked**, so clause (a) is not met and §6 is judged on the bar like anything
else. Stated explicitly because "owner touched it at some point" is exactly how this exception would widen.

**THREE times now, measurement has moved §0's disposition** — the owner re-opened its TOP PRIORITY
standing; then its mechanism turned out to exist (so it left the §5 gate); then clause 1 turned out to
reject it (so it returned, asking a different question). Treat any claim about §0's status in this spec
as the thing most likely to be wrong.

---

## 3. The oracle: three-way, and git is the backbone

Per item, all three, in this order:

1. **Current code state** — does the mitigation exist?
2. **Git history** — `git log --grep='<distinctive phrase>'` and `git log -S'<distinctive symbol>'`.
3. **CHANGELOG / release state** — was it released, and under which version channel?

🔴 **Git is the load-bearing oracle, not the code grep.** Both stale ROADMAP entries evaded a code-only
search: a shipped item leaves a commit even after its symbol is renamed or moved to another assembly. This
is the direct lesson of `docs/backlog-triage-runbook.md` §2 and failure mode 6.

**Two traps, both already hit:**

- **A grep hit is not a verdict.** Open the enclosing function and find the caller. Two false dispositions
  were written in one day from hits whose enclosing scope was never read.
- **`--grep` matches the roadmap's own commits.** `docs(roadmap): capture X` proves an item was *recorded*,
  not that it *shipped*. Read the commit, do not count it.

**CHANGELOG caveat, measured:** all five CHANGELOGs stop at 2026-08-04 while ~96 commits sit unpushed.
That is **correct** — release-please writes them at release time. A CHANGELOG lagging unreleased work is
not staleness, and must not be reported as such.

---

## 4. Phase 1 — the sweep

All six surfaces, item by item, against §2's bar and §3's oracle.

| # | Surface | Scope |
|---|---|---|
| 1 | `clavity-dotnet/ROADMAP.md` | forward backlog §0–§11, Stretch, **and** the `# ghidrust` section it contains |
| 2 | `clavity-classic/ROADMAP.md` | the Follow-ups section |
| 3 | `agy-autotrain/ROADMAP.md` | AT-1 (Parts A and B), AT-2 |
| 4 | `commonmemory/ROADMAP.md` | measured COMPLETE; confirm, do not assume |
| 5 | `agy-autotrain/docs/fix-the-tool-backlog/` | the 6 still-open entries |
| 6 | `docs/backlog/` + tracked debt in memory | 1 stub (now closed) + debt #1 and #4 — **located in the auto-memory file `project_tracked-debt.md`**, in the same per-project memory directory named above. It is a markdown file, not an agentmemory slot or a queryable store; read it directly. Measured: **2 of its 4 items are open**, and the item indices are its own. |

**Inventory facts to carry in, all measured 2026-08-06 — do not re-derive, but do not trust blindly either:**

- **There are 4 `ROADMAP.md` files and the fourth is `commonmemory/`, NOT ghidrust.** ghidrust has no
  roadmap file; its roadmap is a `# ghidrust` section inside `clavity-dotnet/ROADMAP.md`.
- 🔴 **The forward backlog HAS been renumbered before** — `252f63c docs(roadmap): mark §1 … SHIPPED +
  renumber backlog`. §0 now forbids renumbering *because* citations depend on the indices. **Audit whether
  any surviving citation to a §-number predates that commit and therefore points at the wrong section.**
  This is a live correctness risk to the whole citation convention, not a tidiness item.
- **Unresolved lead, not a finding:** `ghidrust/CHANGELOG.md` says `1.2.0` while
  `ghidrust/plugin/plugin.json` says `1.0.0` and the roadmap says *"SHIPPED — v1.0.0"*.
  `scripts/lib/release-lib.ps1:37-38` states ghidrust versions a **binary** channel and a **plugin**
  channel separately, so this may be legitimate. **Resolve it before asserting a defect.**

**Output of Phase 1:** every item marked CLOSED / KILLED / KEPT, each with its evidence, and the kept set
ranked. Roadmap entries are closed **in place** (✅ SHIPPED with the evidence), never renumbered.

### Where the evidence lives, and how a crash resumes

🔴 **An earlier draft named no home for Phase 1's output. Without one, Phase 3 cannot consume it and a
fresh session cannot resume** — and this project's standing rule is that any multi-commit work must be
resumable by a cold successor from the index alone.

- **The disposition itself lives on the surface it belongs to** — roadmap entries marked in place,
  frontmatter edited in place. That is the durable record and it is in git.
- **The running sweep state lives in the auto-memory file `project_open-work-reconsideration.md`**, in the
  per-project memory directory — for this machine,
  `C:\Users\user\.claude\projects\C--Users-user-Development-Rust-clavity\memory\`. It is **outside the
  repo and outside git** (see runbook §13 failure mode 4). It records which surfaces are swept, the base
  SHA, and the single ▶ resume point. **Updated the moment a surface completes, never in batch.**
- 🔴 **Order: COMMIT FIRST, then write memory — and on resume, GIT IS THE TRUTH.** These are two records
  that can disagree, and a crash between them is the likely case, not the exotic one. If memory says a
  surface is incomplete but its entries are already marked in committed files, **the surface is done**;
  correct memory and move on. Never re-sweep on memory's word alone, and never re-edit an entry that
  already carries its disposition — the sweep's edits are not idempotent.
- **A resumed run reads memory first, then verifies it against `git log`/`git diff` before acting**, and
  does not trust this spec's inventory over either.

### If the §-renumbering audit finds broken citations

Renumbering is forbidden, so the audit cannot be resolved by fixing the numbers. The disposition path is:
**re-anchor the citation, not the section.** Any citation found pointing at the wrong content is rewritten
to name the section's **title** as well as its number (e.g. "§7 AGY-SCOPE"), so a future renumber degrades
it to ambiguous rather than to silently wrong. **If the audit finds none, say so explicitly** — a silent
pass here is indistinguishable from an audit that never ran.

---

## 5. Phase 2 — the binding disposition on §0 and §7

**This is an owner decision point, and the epic does not proceed past it silently.**

**Two items reach this gate, for opposite reasons. The question asked of each is different, and conflating
them is how an override gets recorded as a bar pass.**

- **§7 (AGY-SCOPE) — no mechanism.** Marked `(BRAINSTORM FIRST)`, *"Status: brainstorming task, not yet
  designed"*, owner directive 2026-07-31. **Question: spec it, or kill it?**
- **§0 (discipline efficacy) — has a mechanism, but fails clause 1.** It has an owner-ratified sequence at
  `clavity-dotnet/ROADMAP.md:177`, so clause 3 is satisfied; §7a shows clause 1 is not, and that widening
  clause 1 to admit it also readmits §6 and §4. **Question: the bar rejects this — do you override it?**
  🔴 **§0 has now moved between phases TWICE under measurement** (out of the gate in round 1, back into it
  in round 2, each time for a different and correct reason). **Do not re-derive its status from an earlier
  section of this spec; read §7a.**

The consult argued items like this should be killed outright; the counter-argument is that §10 of the same
roadmap records the opposite failure — *"retroactively widening a stalled epic prevents it closing"*.

**Resolution (owner-approved): at the end of Phase 1, with the sweep's evidence in hand, the owner rules on
BOTH — two separate rulings, not one.**

- **§7:** *spec it, or kill it.* If kept it gets its own spec, which is a decision rather than a deferral.
  If killed it leaves the roadmap the same day.
- **§0:** *the bar rejects this on clause 1 — do you override?* If overridden it becomes a KEPT item and
  Phase 3 implements **only the steps Phase 1 found unshipped** (§6 item 8). If not overridden it is
  KILLED and struck from the roadmap, exactly like any other item that fails the bar.

**The executor's handover when it reaches this gate** — because an autonomous run must not stall silently:
stop at the end of Phase 1, commit everything, write **both** ruling requests into the memory file as the
▶ resume point, and **surface both questions to the owner in chat with the sweep's evidence attached**.
**Do not proceed into Phase 3 with either §7 or §0 unruled, and do not guess either ruling.** 🔴 An earlier
draft of this paragraph named only §7 — it was written when §0 was not at this gate and was never
reconciled when round 2 put it back, leaving an unhandled branch immediately before Phase 3.

**Why this is not the attrition path the peer warned about:** the disposition is a scheduled, evidenced,
owner-made ruling with a deadline, not an omission. The failure mode it is designed against — an item
excluded from every epic until it is forgotten — requires that no one ever rules on it. Here someone does.

---

## 6. Phase 3 — implement the survivors

> **Seven survivors and one conditional.** Items 1–7 pass the bar. **Item 8 (§0) does NOT** — it is listed
> here only so its ranking is visible, and it enters Phase 3 solely if the owner overrides at the §5 gate.
> Do not read this list as eight approved items.

Ranked. This ordering is **provisional**: Phase 1 may close or kill any of these, and the plan for Phase 3
is written only after Phase 1 lands.

1. **gRPC receive cap + the blanket `ChannelDown` hint — together.** `LsChannel.cs:50` constructs
   `new GrpcChannelOptions { HttpHandler = effective }` with no `MaxReceiveMessageSize`; `git log -S` shows
   it has **never** been set, so gRPC's 4 MB default applies. `ChannelDown.cs:38-42`'s `Hint` is
   unconditional and tells every failure *"agy's language server appears to have shut down or restarted"*.
   🔴 **They ship together deliberately:** fixing the cap alone leaves the misdirecting hint in place for
   every *other* channel failure, which is the actual "active lie".
   🔴 **The entry's reproduction steps are FALSIFIED and must be rewritten.** It says drive past *"roughly
   1100 steps"* and *"Every call fails."* Measured 2026-08-06: three consecutive round-trips succeeded at
   **996, 1111 and 1203 steps**, and a fourth at **1290**. The cap is on **message bytes**; step count is a
   derived consequence and a session with large tool outputs can cross 4 MB in far fewer steps.
   **Open design question for the plan:** unlimited (`null`) versus a large explicit cap. The peer proposed
   `null`; the peer is local, so the DoS argument is weak, but "unbounded" deserves an explicit decision
   rather than a default.
2. **`agy_look` tail truncation.** `AgyView.cs:110` calls `BoundedView.Summarize(trajectory, budgetChars)`;
   `BoundedView.cs:38` defaults `newestFirst = false`. The tail-anchored view **already exists** and is used
   by `agy_ask` and tests — `agy_look` simply does not pass it.
3. **Inbox-snapshot slash-command path.** `agy-autotrain/hooks/hooks.json` registers only
   `PreToolUse: Skill`, `SessionStart` and `PreCompact`, with **no `UserPromptSubmit` event at all**, so the
   pre-drain snapshot never fires on a slash-command invocation of a destructive drain.
   🔴 **The entry's proposed mitigation — a `UserPromptSubmit` matcher on `^/agy-autotrain:agy-curate\b` —
   is an UNCHECKED ASSUMPTION about the hook contract, and this spec inherited it without testing.**
   Measured: **no `UserPromptSubmit` event exists anywhere in this repository**, and every matcher that
   does exist is a tool name or an event-source alternation — `Skill`, `Agent|Task`, `Write|Edit`,
   `startup|clear|compact`, `manual|auto`. **Not one is a regex over prompt text.** So there is zero
   in-repo precedent that `matcher` is even evaluated against the prompt for this event.
   **The plan must establish the contract before building on it** — the repo's own history includes a
   still-open question about whether `Agent|Task` matches unanchored, which is the same class of doubt.
   **If the matcher shape does not hold, mitigation 1 (a snapshot inside `curate-commit` itself) is the
   fallback and needs no hook contract at all.**
4. **No-open-conversation diagnostic.** Conversation-existence is not split from endpoint reachability, so
   the same misleading hint fires when agy is alive but has no open conversation.
5. **`stalled-reply-recoverable-not-lost`.** Idle-wait expiry throws rather than re-polling, discarding a
   turn that completed as the timeout elapsed.
6. **AT-1 Part A** — GROWTH line-density cap and anti-poisoning gate. Markdown-only.
7. **§11 PINNING-ASSERTION-STRENGTH.** Design is settled (`df2b907`, agreed with agy over three rounds);
   `git log --grep` shows it was captured and never implemented.
8. **§0 DISCIPLINE EFFICACY — CONDITIONAL on the §5 override; not a survivor until then.** It passes
   clause 3 (owner-ratified sequence, `clavity-dotnet/ROADMAP.md:177`) and the owner marked it
   `▶ TOP PRIORITY`, but §7a shows it **fails clause 1**. If the override is refused it is KILLED and this
   entry is struck.
   🔴 **It is also by far the largest item here and the only one that is a build rather than a fix** — the
   seven above it are small, bounded and mostly single-file. Two bounding rules therefore apply:
   - **Phase 1 must measure how much of §0's sequence has already shipped.** Its own text orders the work
     *"stamp (item 2) → recorder / step 1a (item 1) → witness trial (item 3)"* and notes step 1b is already
     scheduled — so it is partly underway. **Ranking a partially-shipped item as unstarted is the exact
     error this epic exists to remove.**
   - 🔴 **Phase 3 implements ONLY the steps Phase 1 finds unshipped, and the plan states them by name.**
     "Implement §0" is unbounded and would swallow the epic — which is §10's recorded failure mode. If the
     remaining scope is larger than the other seven items combined, it belongs in its own epic and the
     override ruling should say so.

**Fallback ordering if the epic is ever cut short** — the consult's one-hour version, recorded because it
is a genuinely different answer and close to as good: items 1, 2, 3 plus AT-1 Part A close most of the
crash and data-loss exposure in roughly an hour.

---

## 7. Explicitly out of scope

- **New features.** Including ghidrust's `import_binary` / smart-server / lazy-boot items, which are
  feature requests for a tool with no active development cycle here. The sweep dispositions them; it does
  not build them.
- **AT-1 Part B** (project-local learning tier) — requires binary changes that
  `agy-autotrain/ROADMAP.md` says the plugin must not make. Candidate KILL, decided in Phase 1.
- **Building a TTL / expiry mechanism.** The consult's aviation analogy (AD vs MEL, every item carrying a
  ticking expiry) is a genuinely good idea **and it is a mechanism**. `docs/backlog-triage-runbook.md` §8
  records a measured decision to build none, with §7's revisit triggers as the expiry condition.
  **If a TTL is wanted it must be argued against §8 explicitly, as its own decision — it must not enter
  through this epic's back door.**
- **The `Clavity.Ls` simplification** the consult surfaced (that an ephemeral ~50-turn cascade model would
  make much of the channel/modal/step-delta machinery unnecessary). Recorded because it reframes what that
  subsystem is for; acting on it is a separate architectural decision.

---

## 8. Success criteria

1. Every item on all six surfaces carries a disposition — CLOSED, KILLED, or KEPT — **except §7 and §0,
   whose terminal state is the §5 ruling** (the only permitted fourth outcome, and only for those two).
   **They reach that gate for opposite reasons and the ruling asked of each is different:** §7 has no
   mechanism (*spec it or kill it*); §0 has a mechanism but **fails clause 1** (*the bar rejects this — do
   you override?*). 🔴 An earlier draft of this criterion listed §0 for the wrong reason and then, after
   §0 was moved out, was left stale for a full round contradicting criterion 4. **Both criteria now name
   the same set; check them against each other whenever either changes.**
2. **No item is dispositioned from its own prose, and naming an oracle is not running one.** Each
   disposition records **the oracle's actual OUTPUT** — the command's stdout, the quoted line, or the
   commit — not merely which oracle was chosen. 🔴 This epic's own evidence is that a named oracle can
   point at the wrong file and return a confident wrong answer; a criterion satisfied by *naming* is
   satisfied by a broken oracle.
3. Every CLOSED roadmap entry is marked ✅ in place with its evidence. **Nothing is renumbered**, the
   pre-`252f63c` citation risk is audited, and the audit **states its result either way** — including
   "none found".
4. **§7 and §0** each have a binding owner ruling recorded in the roadmap, neither left undecided:
   **§7** — specced or killed. **§0** — overridden into the KEPT set, or killed on clause 1.
   The ruling records **which** question was answered, so a later reader cannot mistake an override for a
   bar pass.
5. **Every KEPT item is implemented.** 🔴 An earlier draft read *"…or the epic states plainly which were
   not and why"*, which made this criterion unfalsifiable — an epic implementing nothing satisfied it. If
   an item cannot be implemented, the correct action is to **re-disposition it** (it fails clause 3 and is
   KILLED, or the owner rules on it) — not to leave it KEPT-but-undone. **KEPT and unimplemented is not a
   permitted end state.**
6. The falsified `grpc-default-max-message-size` reproduction is rewritten in byte terms; no entry retains
   a repro that measurement has disproven.
7. The scope gate from the prior epic still holds where it applies: no new mechanism is introduced under
   cover of triage — **including the TTL idea in §7, which needs its own decision against runbook §8.**
8. Phase 3 changes code, so the suite count **will** move. The gate is therefore not "unchanged": every
   delta is accounted for by a **named** new test, and the Phase-1 sweep on its own (docs-only) moves it by
   zero.

---

## 7a. The bar must be APPLIED, not merely adopted

🔴 **An earlier draft adopted a three-clause bar in §2 and then listed eight survivors in §6 without ever
applying it to them.** A bar that never touches the list it governs is decorative, and this epic exists to
delete decoration. **Every KEPT item records its clause 1 / 2 / 3 justification in one line**, and two of
them are not obvious and must be argued rather than assumed:

- **§11 (assertion-strength) PASSES clause 1.** A cardinality assertion that stays green while the sort is
  reversed is **literally a false diagnostic**: it prints PASS about code that is broken, and the wrong
  action it induces — merging — is nameable. That is clause 1 exactly as §2 defines it.

- 🔴 **§0 (discipline efficacy) FAILS clause 1, and therefore FAILS THE BAR.** An earlier draft rescued it
  with *"a green gate measuring the wrong thing is an active lie"*. **The agy panel showed that reading is
  a smuggle, and it is right.** No diagnostic lies in §0's case; what is missing is proof that a shipped
  discipline changes behaviour. **Measured, the same premise readmits at least two items this epic
  otherwise judges on their merits:**
  - **§6** — `clavity-dotnet/ROADMAP.md:350-354` asks for *"a probe / verify-harness confirming a delivered
    rule demonstrably changes driver behaviour … so 'delivers better driving' is substantiated, not
    assumed."* **That is §0's argument word for word.**
  - **§4** — the packaging verifications are the same shape: confirm a property nobody has proven.

  A clause that admits every unbuilt validation harness cannot reject one, and rejecting speculative
  harnesses is most of what clause 1 is for. **So clause 1 stays narrow: a false operational diagnostic
  whose induced wrong action can be named.**

  **Consequence, stated plainly rather than engineered around: applied strictly, THE BAR KILLS §0** — the
  item the owner ranked `▶ TOP PRIORITY`. It has a mechanism (clause 3) and is arguably unavoidable
  (clause 2), but it does not clear clause 1.

  **§0 is therefore admitted ONLY by an explicit owner override, which must be ASKED FOR, not assumed.**
  It goes to the §5 gate — not as "spec it or kill it" (it is already specced) but as: *the bar rejects
  this; do you override it?* **An override is legitimate and the owner's to make. Silently widening a
  clause until the favoured item fits is not.** That this bar bites the owner's own top priority is
  evidence it is a real bar rather than a decorative one.

**If an item cannot be given all three justifications in one line each, it is not KEPT.**

## 7b. Disposition vocabulary — this spec's states are not the surfaces' states

🔴 **Unmapped in an earlier draft.** This spec says CLOSED / KILLED / KEPT; `_template.md:6` says
`status: open | fixed | wont-fix`. An executor must not invent the mapping:

| spec state | `fix-the-tool-backlog/` frontmatter | `ROADMAP.md` |
|---|---|---|
| **CLOSED** (already shipped) | `status: fixed` + `fixed-by` + `fixed-on` (the COMMIT's date) | ✅ SHIPPED in place, with evidence |
| **KILLED** (fails the bar) | `status: wont-fix` + `last-triaged` + the clause it failed | struck through in place, with the clause it failed |
| **KEPT** (survives, to implement) | `status: open` + `last-triaged` | left as-is, ranked |

⚠️ **A KILLED entry is the first use of `wont-fix` in this repository** — the runbook records that no entry
uses it today, so there is no example to copy. It therefore MUST carry its reason inline: a `wont-fix` with
no recorded argument is indistinguishable from an entry someone got tired of, and the next reader cannot
reopen it on the merits.

**Three states the table above cannot express, each with its rule:**

1. **A partially-shipped multi-step item** (§0 is one — some steps done, others open). A whole-section ✅
   would be false and a whole-section strike-through would be worse. **Rule: mark the SHIPPED STEPS ✅
   individually, in place, and leave the section open.** The section closes only when its last step does.
2. **An item the owner ruled on at the §5 gate.** It is neither `fixed` nor `wont-fix`. **Rule: record the
   ruling and its DATE on the entry — "owner-overridden into scope" or "killed on clause 1" — so the basis
   is legible later.** A ruling recorded as a plain status loses the reason, and the reason is the whole
   value.
3. 🔴 **A `variant: both` entry fixed on ONE driver.** The single `status:` field cannot say it, which is
   `docs/backlog-triage-runbook.md` §13 failure mode 5. **Rule: it stays `status: open` with
   `last-triaged` naming the driver that IS fixed and the one that is not.** Marking it `fixed` on one
   driver's evidence false-cleans the other — measured live this session on two separate entries, pointing
   in opposite directions.
4. **A tracked-debt item in `project_tracked-debt.md`.** It has no frontmatter, so the table's frontmatter
   column does not apply. **Rule: mark it ✅ in place with its evidence and leave it in the file — do not
   delete it.** That file is the record of what was decided, and a deleted item is indistinguishable from
   one that never existed. Its open/closed count is stated at the top and **must be updated in the same
   edit**, or the file lies about itself the way every other surface here has.

## 8a. Staging and spend — this epic does not fit in one session

🔴 **An earlier draft said nothing about cost, in an epic whose own §7 excludes a mechanism on spend
grounds.** That is the same blind spot `docs/backlog-triage-runbook.md` §8 was written about.

The work is ~25 items × 3 oracles, plus a panel per artifact, plus a capstone, plus possibly two further
specs. **Assume it spans several sessions and stage it so that each stage is independently complete:**

- **Phase 1 is split by SURFACE, and each surface ends in its own commit.** A surface swept is a surface
  banked; the epic is never in a half-swept state that a fresh session cannot resume from.
  🔴 **Surface 6 is the exception and needs its own rule: the tracked-debt half lives in memory, OUTSIDE
  git, so it cannot "end in a commit."** Its completion marker is the memory file itself, which makes it
  the one surface where the commit-is-truth tiebreak above does not apply. **Sweep it LAST**, so that
  every surface with a git record is already banked, and record its completion explicitly rather than
  inferring it from a commit that will never exist.
- **Phase 3 is split by ITEM**, one commit per item, for the same reason.
- **Reviews re-read the whole session context each round, so they cost far more at the end of a long
  session than at the start of a fresh one.** Commit first, then run the panel/capstone after a compaction
  or in a new session. This is a scheduling fact, not a reason to skip them.
- **No stage may be skipped to save spend.** The runbook's position stands: review is investment. Staging
  exists so the cost is *paid where it is cheapest*, not avoided.

## 8b. Two lifecycle gaps the panel found, and where each is handled

**Fixing a tool defect does NOT retire its driver-cheatsheet rule, and the epic must not silently leave
that dangling.** `_template.md` states the two are separate gates and that retirement additionally requires
a committed green regression test on every variant the quirk reproduced on, plus wide end-user adoption.
So for every Phase-3 item that closes a `fix-the-tool-backlog` entry:

- **Do not touch the cheatsheet rule in this epic.** That prohibition stands.
- **Do record, on the closed entry, that its driver rule is now a retirement CANDIDATE** and what the
  remaining gate is. Otherwise the workaround rides in driver context forever with nothing pointing at it —
  the panel's finding, and it is correct: a fixed defect whose workaround is never retired is permanent
  prompt cost.
- Actual retirement is a separate decision, gated on `_template.md`'s conditions. **Not this epic.**

**Anomalies noticed mid-sweep go to `.clavity/local-anomalies.md` via the `open-issues` skill, not into the
sweep.** A sweep that absorbs every defect it notices never terminates. Capture, do not chase — and the
driver verifies before recording.

## 9. Known traps, carried forward

- **A grep hit is not a verdict** — open the enclosing function and the call site. Two false dispositions in
  one day came from skipping this.
- **`rg --no-ignore` for any "are any left?" question** — `.clavity/` and `docs/superpowers/` are gitignored
  and both search tools have returned false zeros, in opposite directions.
- **`fix-the-tool-backlog/` is append-only.** Close by editing frontmatter in place; never delete a file.
- **Marking an entry `fixed` does not authorise touching the driver-cheatsheet rule** (`_template.md`).
- **A `variant: both` entry has one `status:` field** — it needs two real measurements, one per driver.
- **Backticks in a `git commit -m` shell string run as command substitution.** Use `-F -` with a quoted
  heredoc for any message containing them; this silently ate three phrases from a commit message today.
- **Never quote a test count or timing from a document** — `scripts/tests/_partition.md` holds the measured
  figures, and it has itself been wrong three times.

---

## 10. Self-audit

**Coverage.** Every surface in §4 maps to a Phase-1 row. Every §6 item maps to a success criterion. §0/§7
map to §5 and criterion 4. The out-of-scope list in §7 names each excluded item and why.

**Placeholders.** None. Every claim carries a `file:line`, a command, or a commit sha.

**Deliberately unresolved, and where each is settled:**
- The `MaxReceiveMessageSize` value (unlimited vs explicit cap) — **settled in the Phase-3 plan**, flagged
  in §6.1 rather than assumed.
- The ghidrust version-channel question — **settled in Phase 1**, flagged in §4 as a lead, not a finding.
- The §-renumbering citation audit — **settled in Phase 1**, criterion 3.
- **§7** — specced or killed; **§0** — overridden or killed. **Two different questions**, both settled by
  the owner in Phase 2, by design. (Writing this line as a single "specced or killed" for both is the
  error §5 exists to prevent, and this line carried it for a round.)

**Scope check.** Phase 1 is one plan. Phase 3 is a second plan, gated on Phase 1's findings — writing
line-level steps now for items the sweep may delete would be exactly the fabricated precision the plan
discipline forbids.

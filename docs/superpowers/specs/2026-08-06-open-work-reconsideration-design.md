# Open-work reconsideration — design

**Status:** owner-approved 2026-08-06. AGY-FIRST consulted over two rounds (`open-work-ranking{,-r2}.md`).
**Base commit:** `885905a`.

**Goal.** Every recorded item across all six tracking surfaces ends in one of three states, each with
evidence attached: **CLOSED** (already shipped), **KILLED** (fails the bar), or **KEPT** — and every kept
item is then implemented. No item survives on reputation.

**New features are out of scope.** Everything here already exists as a recorded item. The question is
which deserve to exist, in what order, and which should stop existing.

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

`ROADMAP.md` §0 and §7 fail clause 3 today. They are **not** auto-killed and **not** carried forward
silently — see §5.

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

🔴 **The exception admits §7 ONLY. §0 does not qualify, and this spec asserted the opposite.** An earlier
draft said *"§0 and §7 fail clause 3: both are marked BRAINSTORM-FIRST and neither has a specified
mechanism."* **Both halves are false for §0**, and the agy panel caught it:

- `clavity-dotnet/ROADMAP.md:118` marks §0 **`▶ TOP PRIORITY`**, not `BRAINSTORM FIRST`.
- `clavity-dotnet/ROADMAP.md:177` reads **"THE SEQUENCE — OWNER-RATIFIED 2026-08-04, after a second
  AGY-FIRST consult and measurement"**, followed by a numbered sequence and settled sub-rulings including
  *"Owner ruling on the `PreCompact` channel, same date: ship dispatch-only."*

**§0 therefore PASSES clause 3** — it has a concrete owner-ratified mechanism — and is an **ordinary KEPT
item**, ranked and implemented in Phase 3 like any other. Sending it to a "spec it or kill it" ruling would
have posed the owner a **false dilemma about work that is already designed**, and would have re-opened a
sequence the owner ratified two days ago.

**§6 is the near-miss worth naming.** `clavity-dotnet/ROADMAP.md:354` ends *"Owner-surfaced 2026-07-11"* —
**surfaced is not directed or ranked**, so clause (a) is not met and §6 is judged on the bar like anything
else. Stated explicitly because "owner touched it at some point" is exactly how this exception would widen.

**Twice now, measurement has moved §0's disposition** — first when the owner re-opened its TOP PRIORITY
standing, then here when its mechanism turned out to exist. Treat any claim about §0's status in this spec
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
| 6 | `docs/backlog/` + tracked debt in memory | 1 stub (now closed) + debt #1 and #4 |

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

**§7 (AGY-SCOPE) only.** It is marked `(BRAINSTORM FIRST)` with *"Status: brainstorming task, not yet
designed"* and an owner directive dated 2026-07-31 — owner-directed, no mechanism, not already answered.
**§0 was in this section in an earlier draft and has been removed**: it has an owner-ratified sequence
(`clavity-dotnet/ROADMAP.md:177`), so it passes clause 3 and is an ordinary KEPT item. See §2.

The consult argued items like this should be killed outright; the counter-argument is that §10 of the same
roadmap records the opposite failure — *"retroactively widening a stalled epic prevents it closing"*.

**Resolution (owner-approved):** at the end of Phase 1, with the sweep's evidence in hand, the owner rules
on §7: **spec it, or kill it.** Not park it, not carry it forward. If kept, it gets its own spec — which
is then a decision rather than a deferral. If killed, it leaves the roadmap the same day.

**The executor's handover when it reaches this gate** — because an autonomous run must not stall silently:
stop at the end of Phase 1, commit everything, write the ruling request into the memory file as the ▶
resume point, and **surface the question to the owner in chat with the sweep's evidence attached**. Do not
proceed into Phase 3 with §7 unruled, and do not guess the ruling.

**Why this is not the attrition path the peer warned about:** the disposition is a scheduled, evidenced,
owner-made ruling with a deadline, not an omission. The failure mode it is designed against — an item
excluded from every epic until it is forgotten — requires that no one ever rules on it. Here someone does.

---

## 6. Phase 3 — implement the survivors

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
4. **No-open-conversation diagnostic.** Conversation-existence is not split from endpoint reachability, so
   the same misleading hint fires when agy is alive but has no open conversation.
5. **`stalled-reply-recoverable-not-lost`.** Idle-wait expiry throws rather than re-polling, discarding a
   turn that completed as the timeout elapsed.
6. **AT-1 Part A** — GROWTH line-density cap and anti-poisoning gate. Markdown-only.
7. **§11 PINNING-ASSERTION-STRENGTH.** Design is settled (`df2b907`, agreed with agy over three rounds);
   `git log --grep` shows it was captured and never implemented.
8. **§0 DISCIPLINE EFFICACY** — added here after the panel established it passes clause 3. It carries an
   owner-ratified sequence at `clavity-dotnet/ROADMAP.md:177` and the owner marked it `▶ TOP PRIORITY`.
   🔴 **It is also by far the largest item here and the only one that is a build rather than a fix**, so
   its position is the ranking's real open question: the seven above it are small, bounded and mostly
   single-file, while §0 is a multi-session build. **Phase 1 must re-measure how much of §0's sequence has
   already shipped before Phase 3 orders it** — a partially-shipped item ranked as if unstarted is the
   same error this whole epic exists to remove.

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

1. Every item on all six surfaces carries a disposition — CLOSED, KILLED, or KEPT — **except §0 and §7,
   whose terminal state is the §5 ruling** (the only permitted fourth outcome, and only for those two).
2. **No item is dispositioned from its own prose, and naming an oracle is not running one.** Each
   disposition records **the oracle's actual OUTPUT** — the command's stdout, the quoted line, or the
   commit — not merely which oracle was chosen. 🔴 This epic's own evidence is that a named oracle can
   point at the wrong file and return a confident wrong answer; a criterion satisfied by *naming* is
   satisfied by a broken oracle.
3. Every CLOSED roadmap entry is marked ✅ in place with its evidence. **Nothing is renumbered**, the
   pre-`252f63c` citation risk is audited, and the audit **states its result either way** — including
   "none found".
4. **§7** has a binding owner ruling recorded in the roadmap: specced or killed, not left undecided.
   (**§0 is deliberately NOT in this criterion** — it passes clause 3 and is covered by criterion 5 as an
   ordinary KEPT item. An earlier draft had it here.)
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

## 8a. Staging and spend — this epic does not fit in one session

🔴 **An earlier draft said nothing about cost, in an epic whose own §7 excludes a mechanism on spend
grounds.** That is the same blind spot `docs/backlog-triage-runbook.md` §8 was written about.

The work is ~25 items × 3 oracles, plus a panel per artifact, plus a capstone, plus possibly two further
specs. **Assume it spans several sessions and stage it so that each stage is independently complete:**

- **Phase 1 is split by SURFACE, and each surface ends in its own commit.** A surface swept is a surface
  banked; the epic is never in a half-swept state that a fresh session cannot resume from.
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
- Whether §0/§7 are specced or killed — **settled by the owner in Phase 2**, by design.

**Scope check.** Phase 1 is one plan. Phase 3 is a second plan, gated on Phase 1's findings — writing
line-level steps now for items the sweep may delete would be exactly the fabricated precision the plan
discipline forbids.

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

**The one exception, and it is a decision rather than a loophole:** `ROADMAP.md` §0 and §7 fail clause 3
today. They are **not** auto-killed and **not** carried forward silently — see §5.

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

---

## 5. Phase 2 — the binding disposition on §0 and §7

**This is an owner decision point, and the epic does not proceed past it silently.**

§0 (discipline efficacy) and §7 (AGY-SCOPE) fail clause 3: both are marked BRAINSTORM-FIRST and neither has
a specified mechanism. The consult argued they should be killed outright; the counter-argument is that §10
of the same roadmap records the opposite failure — *"retroactively widening a stalled epic prevents it
closing"*.

**Resolution (owner-approved):** at the end of Phase 1, with the sweep's evidence in hand, the owner rules
on each: **spec it, or kill it.** Not park it, not carry it forward. If kept, it gets its own spec — which
is then a decision rather than a deferral. If killed, it leaves the roadmap the same day.

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

1. Every item on all six surfaces carries a disposition — CLOSED, KILLED, or KEPT — and every disposition
   cites a command, a `file:line`, or a commit.
2. **No item is dispositioned from its own prose.** Each names the oracle that was run.
3. Every CLOSED roadmap entry is marked ✅ in place with its evidence. **Nothing is renumbered**, and the
   pre-`252f63c` citation risk is audited and reported.
4. §0 and §7 each have a binding owner ruling recorded in the roadmap: specced or killed. Neither is left
   in its current undecided state.
5. Every KEPT item is implemented, or the epic states plainly which were not and why.
6. The falsified `grpc-default-max-message-size` reproduction is rewritten in byte terms; no entry retains
   a repro that measurement has disproven.
7. The scope gate from the prior epic still holds where it applies: no new mechanism is introduced under
   cover of triage.
8. `just test-scripts-fast` count is unchanged by the sweep itself, and any change during Phase 3 is
   accounted for by a named new test.

---

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

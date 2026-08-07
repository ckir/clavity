# Backlog triage runbook

**Internal.** Not on the user-facing roster (`docs/user-facing-docs.txt`), like
[`release-runbook.md`](release-runbook.md) and [`drain-knowledge-runbook.md`](drain-knowledge-runbook.md).

**Why this exists.** On 2026-08-06, seven backlog entries were found describing work that had already
shipped, across five surfaces, in one day. Clearing them cost one measurement each — minutes. Re-deriving
*how* to clear them cost far more than that, and would have cost it again next time. This file is that
re-derivation, written down once.

**What it is not.** It is a documented procedure, not an enforced gate. The deliberate decision of the
epic that produced it was to build **no mechanism** — see [§8](#8-why-no-mechanism-exists) for the
measured reasoning and [§13](#13-three-ways-this-runbook-fails) for the honest limits.

---

## 1. The six tracking surfaces, by path

An open issue in this repo can be recorded in any of six places. **Two of these were missing from every
prior inventory**, including one presented as complete — so this list is the single most re-derivable
fact in this document.

| # | Surface | Path | Shape |
|---|---|---|---|
| 1 | Product roadmaps | `clavity-dotnet/ROADMAP.md`, `clavity-classic/ROADMAP.md`, `ghidrust/ROADMAP.md`, `agy-autotrain/ROADMAP.md` | numbered `§` sections |
| 2 | Fix-the-tool backlog | `agy-autotrain/docs/fix-the-tool-backlog/<slug>.md` | one file per entry, YAML frontmatter |
| 3 | Doc backlog stubs | `docs/backlog/<topic>.md` | prose with a `**Status:**` line |
| 4 | Doc-accuracy punch-list | `docs/docs-audit-findings.md` | **generated**, gitignored |
| 5 | Untriaged anomalies | `.clavity/local-anomalies.md` | gitignored, one bullet per entry |
| 6 | Out-of-tree memory | the auto-memory dir (`MEMORY.md` + `project_*.md`) | outside the repo entirely |

🔴 **Surfaces 4, 5 and 6 are invisible to a plain search.** 4 and 5 are gitignored; 6 is not in the repo
at all. An inventory built with the Grep tool or bare `grep` will silently omit them — see [§6](#6-are-any-left-needs-rg---no-ignore).

🔴 **An inventory of open issues is itself an artifact, and it goes stale.** The count of surfaces was
wrong three times running, and the entry count inside surface 2 was wrong three times running. Re-derive;
do not read.

## 2. Measure, never read — every entry needs a named oracle

**A status line is not evidence of itself.** All seven stale entries found on 2026-08-06 looked plausible
and read as open. Before dispositioning anything, state its **oracle**: a command, a test name, or a
`file:line` that decides the question.

> 🔴 **CORRECTED 2026-08-07. This rule used to read "a negative result is decisive" and it was BACKWARDS.**
> It manufactured three false "still open" verdicts in a single sweep. It also contradicted this same
> section's own later rule — *"A check that returns the same answer whether the work was done or not is
> not a check"* — because a grep for a name you invented is exactly such a check. **The triagers were not
> careless; they were obeying this section.**

🔴 **THE TEST IS WHO CHOSE THE NAME.** This is the whole rule, and getting it wrong in *either* direction
is costly — the first attempt at this correction said "a negative result is never decisive", which would
have thrown away three sound oracles.

- **A name the implementer could NOT have chosen freely** — a framework API (`MaxReceiveMessageSize`), a
  hook event (`UserPromptSubmit`), a wire field, a config key — **its absence IS strong evidence.** There
  was no synonym available; if the work had been done, that exact token would be there. The
  `grpc-default-max-message-size` and `inbox-snapshot-misses-slash-command-path` stamps are of this kind
  and they are sound.
- **A name YOU invented to describe the fix** — `NoConversation`, "conversation-existence split",
  "idle-expiry poll / retry path" — **its absence proves nothing at all.** The implementer never read your
  entry and had no reason to pick your words.

🔴 **A negative on an INVENTED name is the WEAKEST evidence available**, because it cannot distinguish
*not implemented* from *implemented under a name you did not think of*. **Measured 2026-08-06/07, three
times:**
  - `conversation-scoped-tools` grepped for `NoConversation` / "no open conversation". The shipped fix is
    `AgyConversationPendingException` + `reachedLsButEmpty` (`AgyView.cs:381`), surfacing as
    `waiting_for_human` (`McpTools.cs:52-55`) — **and already pinned by two regression tests**
    (`AgyChannelDownTests.cs:284`, `:358`) that satisfy the entry's own stated retirement gate.
  - `stalled-reply-recoverable-not-lost` looked for an "idle-expiry poll / retry path". The shipped fix is
    the `lastProgress` loop in `WaitForIdleWithProgressAsync` (`AgyView.cs:273-281`), which *is* the
    step-counter discriminator the entry asks for.
  - `agy-autotrain` AT-1 Part A asserted no anti-poisoning gate existed. One had existed at
    `agy-autotrain/skills/agy-curate/SKILL.md:250` since `c46be48` — **four days before the item was
    opened.**

**So an absent INVENTED symbol ESCALATES, it never closes.** Verify behaviourally instead: run the entry's
"Steps to Reproduce", or read the code path the entry's *evidence* names and judge whether the behaviour it
demands is present **under any name**.

✅ **A well-built oracle already exists in this repo — copy its shape.** `agy-look-tail-truncation`'s stamp
cites the exact call site *and* warns: *"NB the tail-anchored view DOES exist (`BoundedView.cs:38-41`
`newestFirst`), used only by `agy_ask` and tests; grep `AgyView.cs` alone and you will wrongly conclude no
such view exists at all."* It anticipated the failure mode and disarmed it in the stamp. **That is what a
negative oracle has to do to be trusted.**

- **A positive result is not decisive either.** A grep hit means *open the file and judge* whether the hit
  is the mitigation the entry asked for or an unrelated use of the same words. That judgement cannot be
  pre-written, because it depends on what the hit turns out to be.

- 🔴 **When neither can be established, say `UNVERIFIED` in the stamp — never "confirmed still open".**
  If the reproduction needs state you cannot reach (a live peer, a >4 MB payload, a timing race), the
  `status:` field still reads `open` — that enum is `open | fixed | wont-fix` and has no fourth value, so
  do **not** invent one. What must change is the **`last-triaged:` stamp**, which records *how much
  evidence there is*, not what the status is:

  ```
  last-triaged: <date>   # UNVERIFIED: <check> could not be run because <reason>. Not evidence of open.
  ```

  **An un-runnable check silently becoming "confirmed still open" is how a shipped fix stays on the
  backlog for weeks** — the failure this section exists to prevent. The two words *"confirmed still open"*
  are what the next triager inherits as evidence; write them only when something was actually confirmed.

🔴 **Point the oracle at the file the entry's own evidence names, not at the file you assume.** Measured
2026-08-06, twice in one session:

- The `agy-look-tail-truncation` oracle grepped `AgyView.cs` for a tail-anchored view and found none. The
  view **does exist** — `BoundedView.cs` takes a `newestFirst` flag — it is simply not passed by
  `agy_look`. The verdict (*still open*) was right; the reason was wrong, and **that oracle would keep
  printing "still open" even after the fix landed**, because the symbol it greps for lives in the other file.
- The `golden-header-per-ask` oracle grepped `GoldenHeader.cs`, but the entry's own evidence section cites
  the **send path**. `GoldenHeader.cs` matches nothing whether the optimisation exists or not.

**A check that returns the same answer whether the work was done or not is not a check.** Before trusting
an oracle, ask what output it would produce if the entry *were* fixed. If that is the same output you are
looking at, the oracle is broken.

🔴 **A HIT can also be a false positive for the entry's actual question — read WHICH symbols came back,
which did not, and WHAT FUNCTION each hit is in.** This produced **two consecutive false dispositions of
the same entry on 2026-08-06**, both citing real line numbers:

1. A grep for `TryReadCombined|Apply|cache` returned **one hit and no `Apply` hit**, read as "the per-ask
   read is still there". The hit was inside a once-per-process guarded method and **the absent `Apply` was
   the whole answer** — the send path had stopped prepending entirely.
2. The retraction then cited `read_combined` at a line in the *other* driver as proof its ask path still
   prepended. That line was inside a `doctor()` diagnostic function, not the ask path — which passes an
   explicit "absent" header.

**Both readings were confident, both cited real lines, and both were caught by an adversarial reader
opening the file rather than by the person who wrote them.**

**A grep result is a list of lines, not a verdict.** Before writing a disposition from one: open the
enclosing function, find the caller, and check what the *call site* passes. If you cannot name the caller,
you have not measured the thing the entry is about.

## 3. Per-surface closing conventions — and the trap

- **`fix-the-tool-backlog/` is APPEND-ONLY.** `README.md:8`: *"One file per entry (append-only)."*
  **Never delete or move an entry file.** Close it by editing frontmatter in place.
- **The three dispositions** (frontmatter keys, per `_template.md:6-7`):

  | outcome | keys |
  |---|---|
  | still open, oracle ran | `status: open` + `last-triaged: <date>` |
  | fixed | `status: fixed` + `fixed-by: <sha[, sha]>` + `fixed-on: <the COMMIT's date>` |
  | oracle could not be run | `status: open` + `last-triaged: <date>` + a comment saying *could not reproduce; NOT evidence of fixed* |

  **`fixed-on` is the date the code was fixed, not the date someone noticed.** Find it with
  `git log --oneline -S'<distinctive symbol>' -- <file> | tail -1`.
- **`docs/backlog/`** — leave `**Status:**` alone unless the status genuinely changed; add
  `**Last triaged:** <date>` beside it, and say what the oracle showed.
- **`ROADMAP.md`** — mark a shipped item ✅ in place. **Never renumber a `§`**: every citation elsewhere
  in the repo and in memory is by section number.
- 🔴 **THE TRAP: marking an entry `fixed` does NOT authorise touching the driver-cheatsheet rule.**
  `_template.md` states it outright — *"Two SEPARATE gates, do not conflate them… Closing this item does
  NOT authorise stripping the rule — an end user on an older build still needs it."* Retiring a cheatsheet
  rule needs a committed green regression test on every variant plus wide end-user adoption. Editing
  `knowledge/driver-cheatsheet.core.md` also red-gates pinning tests in **both** drivers.

## 4. Un-reproduced is not fixed

Several entries need a live agy peer in a specific state, and cannot be reproduced on demand. **A failed
reproduction is not evidence of a fix.** Such an entry keeps `status: open` and gains `last-triaged` with
an explicit *could not reproduce* note.

Closing on a failed reproduction is the false-clean this whole discipline exists to remove: it converts
"I could not check" into "it works", and the record then reads identically to a verified fix.

**The mirror-image rule, for entries that are dropped rather than closed:** a tracked defect must carry the
command, test name, or `file:line` that reproduces it — otherwise it is a reminder to its author and an
unfalsifiable claim to everyone else. One entry was dropped in 2026-08-06's sweep for exactly this reason:
it was not disproven, it was **unintelligible**, and re-measuring it still could not say what state it had
described.

## 5. `docs-audit-findings.md` is LEADS, not defects

- It is **generated** from `docs-audit-findings.json` and **gitignored**. **Never write a judgement into
  it** — the next audit run overwrites the file. Judgements go in `memory/project_docs-accuracy-audit.md`.
- Its `claims: N` count **is not a measurement**. `docs-audit.ps1` records a 30% swing on a file `git log`
  proves untouched — the extractor is an LLM reading prose.

🔴 **Most of its noise is STALENESS, not extractor error — regenerate before triaging.** Measured
2026-08-06 over the full punch-list: of 10 findings across 8 docs, **6 were already fixed** by a single
earlier commit, 1 was a genuine mis-parse (a compound sentence truncated and reported as its own inverse),
and 3 were real. The decisive move was `git show --stat <that commit>`: it touched 9 docs and touched
**neither** of the two findings that survived — which is what turns "these look wrong" into a mechanism.
**A finding's staleness is a property of the file's timestamp, not of the extractor.**

⚠️ `just docs-audit -Only <doc>` **intersects** `docs/user-facing-docs.txt`, so an off-roster value is
silently dropped and the run reports *0 docs audited*. **That is a null result, never a clean pass.**

## 6. "Are any left?" needs `rg --no-ignore`

Both the Grep tool and bash `grep` returned **false zeros** on 2026-08-06, in opposite directions. The
Grep tool honours `.gitignore`; `.clavity/` and `docs/superpowers/` are gitignored. For any
*is-anything-left* question, use `rg --no-ignore` and read the paths it returns.

The same care applies to counting: an exclusion pattern in the enumeration command is usually
**load-bearing, not tidiness**. Enumerating surface 2 with a bare `grep -l '^status: open'` returns
**eight**, because `_template.md` itself carries `status: open` as its placeholder. Drop the
`grep -v '_template'` and every downstream count is off by one.

## 7. The three revisit-triggers

The no-mechanism decision in [§8](#8-why-no-mechanism-exists) is **conditional**. Recording these triggers
is the entire substitute for the mechanism — without them this is a deferral, not a decision.

**Revisit the moment ANY of these stops holding:**

1. **One human owner + paired agents.** A second human makes stale entries a coordination cost, not just a
   re-measurement cost.
2. **The measure-before-coding law holds.** The decision assumes nobody builds from an entry without first
   checking it.
3. **No stale entry has yet caused real rework.** The first time one does, the cost model changes.

## 8. Why no mechanism exists

Three mechanisms were costed against the seven real stale entries and all three were rejected **on
measurement**, not on taste:

- **An LLM backlog auditor** — a second unreliable oracle policing the first. See [§5](#5-docs-audit-findingsmd-is-leads-not-defects).
- **A deterministic ID-collision checker** — catches 2 of 7; structurally blind to untagged fixes and
  unnumbered sub-bullets.
- **A capstone-gate step** — catches 3 of 7. **Blind by construction to the two entries fixed by ordinary
  commits that convene no capstone**, and three more predate the capstone discipline entirely.

**The argument that won:** a stale entry causes no production defect and no duplicate code. It costs one
measurement at triage — which is exactly what happened seven times in one day, minutes each. A permanent
mechanism to prevent a cost already paid cheaply is optimising a non-bottleneck.

**This position was not the one the session opened with.** It opened arguing for the capstone gate, and the
measured retroactive count (3 of 7, not "4+") is what changed it.

## 9. The dual-variant twin check

**Verifying a hook or skill fix on one driver only answers half the question.** Measured 2026-08-06:
`clavity-dotnet/plugin/hooks/` and `clavity-classic/plugin/hooks/` hold **12 `.sh` files that are
byte-identical twins, with zero differing**. A fix applied to one copy and not the other leaves the defect
live on the other driver, and the working tree looks fine.

The gate is `scripts/check-seed-artifacts-synced.sh`. Its `divergent()` function is the **allow-list of
files permitted to differ** — currently the classic-only `hooks/agy-drive-session-reset.sh` plus the
transport-twin skills. It is deliberately **fail-closed**: adding a genuinely variant-specific file makes
the gate FAIL until it is enrolled there, so the failure mode is "loudly over-checked" rather than
"silently unchecked".

**So: after fixing anything under a plugin's `hooks/` or `skills/`, run that gate.** And note it needs
`jq`; without it the script exits 2 loudly rather than passing vacuously.

## 10. The `wont-fix` disposition

`_template.md:6` permits `open | fixed | wont-fix`, and **no entry uses `wont-fix` today** — which is
precisely why it is documented here: a future author has no example to copy.

`wont-fix` records a **deliberate architectural refusal**, not an unreproducible entry (that is
[§4](#4-un-reproduced-is-not-fixed)) and not a deferral (that stays `open`). Use it when the mitigation the
entry asks for is one the project has decided not to make. **The reason goes in the entry body**, stated
so that a reader who disagrees can find the argument and reopen it — a `wont-fix` with no recorded reason
is indistinguishable from an entry someone got tired of.

## 11. `ROADMAP.md` is forward-looking; `CHANGELOG.md` is release history

**Never backfill one into the other.** This was the literal root cause of one section reading as both
pending and shipped at the same time.

- A forward item that ships is marked ✅ **in place** in `ROADMAP.md`.
- Release history belongs to the generated `CHANGELOG.md` and is written by the release tooling.
- Do not copy shipped roadmap items into the changelog, and do not add roadmap entries for things already
  released.

## 12. Routing a newly observed problem

So the next surface is not invented:

| What you observed | Where it goes |
|---|---|
| Transient session friction; anything not yet verified | `.clavity/local-anomalies.md` via the `open-issues` skill |
| A driver/bridge execution defect **with a code-level mitigation** | `agy-autotrain/docs/fix-the-tool-backlog/<slug>.md` from `_template.md` |
| Architecture, or a planned increment | the owning product's `ROADMAP.md` |
| A doc that disagrees with the code | fix the doc in the same commit; record the judgement in memory |

**If the only mitigation is a *driving move* rather than a code change, it is a driver-cheatsheet rule,
not a backlog entry** (`fix-the-tool-backlog/README.md`).

## 13. An epic closes what it fixed — and three ways this runbook fails

**The standing rule.** The failure being prevented is measured: work finished, reached capstone GREEN, had
a ledger row — and its entry still read `open` afterwards, three times.

- **Single-origin epic** (spawned from a `ROADMAP` §, a `fix-the-tool-backlog/<slug>.md`, an anomaly, or a
  memory entry): close **that** entry inside the epic's own commit range.
- **Sweep epic** (no single origin — it resolves many): close **every entry named in its Scope section**.
- **An epic with genuinely no tracking entry** (an ad-hoc fix, a spike) closes nothing, and that is
  correct. Do not invent an entry to satisfy a checklist.

🔴 The first draft of this rule said only *"close the entry that originated it"* — which does not cover a
sweep, and the two most recent epics were both sweeps. **A rule that fails on its own author's case is
already wrong.**

### Three ways this runbook fails

Stated plainly, because a runbook that oversells itself is worse than none:

1. **Ordinary commits consult nothing.** Two of the seven stale entries were fixed by commits that
   convened no epic, ran no discipline, and would read no runbook. This document cannot reach that class
   of work at all.
2. **A passive document in `docs/` is invisible to subagents and fresh sessions.** Nothing injects it into
   a prompt, and this epic deliberately built no injector. It is found only by someone who already knows
   to look — which is not the person most likely to need it.
3. **An incidental fix cannot close an entry its author never saw.** The rule above binds an epic to its
   *own* scope. A fix that happens to resolve an unrelated entry leaves that entry standing, and nothing
   here detects it.
4. **Surface 6 is outside git, so no commit can carry it.** Dispositions recorded in the memory dir are
   not in any clone, not in any other machine's session, and not atomic with the commit that earned them.
   A fresh environment sees the repo surfaces and none of surface 6. There is no fix here short of moving
   that state in-tree, which is its own decision — the point is not to believe the surfaces are in sync
   just because the commit landed.
5. **A `variant: both` entry has ONE `status:` field, so a one-driver fix has no honest disposition.**
   `_template.md:2-6` pairs `variant: <clavity-dotnet | clavity-classic | both>` with a single `status:`.
   Mark it `fixed` on one driver's evidence and you false-clean the other; leave it `open` and you
   misreport the driver that is done. **Neither is right, and nothing warns you.**

   🔴 **This is not hypothetical — both cross-driver entries in 2026-08-06's sweep turned on it.**
   `idle-wait-false-modal` (`variant: both`) was closed `fixed` on dotnet commits; the closure only holds
   because classic was *separately* checked and has no `possible_modal` verdict at all. And
   `docs/backlog/golden-header-per-ask-token-optimization.md` was **triaged wrong twice in one day for
   exactly this reason** — first as "unstarted" (both drivers assumed unchanged), then as "half resolved,
   classic still live" (the second driver assumed unchanged). It is in fact resolved on **both**. Two
   wrong dispositions, one cause: **one driver measured, the other inferred.**
   **Until the frontmatter carries per-variant status, a `both` entry demands two REAL measurements and a
   disposition that names which driver it refers to.** The single `status:` field makes the half-measured
   answer look exactly like the fully-measured one.

6. **The oracles recorded in `last-triaged:` comments ROT, and nothing runs them.** A stamp like
   *"oracle: no `StepDelta` symbol in `Clavity.Ls/*.cs`"* is a grep pinned to a path and a symbol name.
   Move the type to another assembly, rename the symbol, or split the module, and that grep keeps
   returning a confident answer about the wrong place. **A live example is already in this repo:** several
   stamps written on 2026-08-06 scope themselves to `Clavity.Ls/*.cs`, but `McpTools.cs` — which one of
   them cites — lives in `Clavity.Mcp`. Because these oracles are markdown comments and no gate executes
   them, the rot is silent and the next triager inherits it as evidence.

   *(Precisely: two of those stamps scope their grep to `Clavity.Ls/*.cs`, and a third cites `McpTools.cs`
   with no path at all — that file is in `Clavity.Mcp`, so a reader who carries the neighbouring stamps'
   scope over to it searches the wrong assembly and finds nothing.)*

**All six are the same shape: this is documentation, and documentation does not execute.** That was the
accepted trade — see [§8](#8-why-no-mechanism-exists) — and [§7](#7-the-three-revisit-triggers) is what
expires it. **Mode 6 is the one most likely to bite first**, because every stamp this runbook asks you to
write is another instance of it.

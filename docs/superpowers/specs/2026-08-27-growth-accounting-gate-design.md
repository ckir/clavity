# GROWTH accounting gate — design

**Status:** SPEC **v2, post-panel round 1** (solo 8-seat panel + live-peer escalation; verdict on v1 was
**REJECT**, 12 findings folded). Forward-writable: the checker does not exist, so this states intent,
contracts and open forks, not line-level edits. **Round 2 not yet run.**

**Constraint, set by the owner 2026-08-27 and treated as a requirement rather than a goal:**
**knowledge must be preserved — nothing lost.** The rationale is that this knowledge cannot be
implemented, only earned, which makes it the most valuable content in the repository.

---

## 0. 🔴 WHAT THIS GATE ACTUALLY GUARANTEES — read before the rest

v1 buried this. The panel put it plainly and it is the honest frame:

> *"The gate provides no safety; it merely forces the curator to CONFESS to deleting the rule before
> letting the deletion succeed."*

That is correct **for v1**, and it is why §3.4 exists in v2: a `dropped` disposition no longer destroys
anything. Even so, state the guarantee precisely and do not oversell it:

- **It converts a SILENT loss into a LOUD, enumerated one.** That is the whole mechanical claim.
- **It does not judge whether a curation decision was wise.** No mechanism here can.
- **The account is therefore the review surface, not the gate's verdict.** The gate's job is to make the
  account complete, short and legible so a human can actually read it — which matters specifically
  because of the **chameleonic compliance** finding: human review is weakest against a large,
  careful-looking diff, and strongest against a short enumerated list.

## 1. The defect this closes, and what is already done

The drain regenerates `docs/agy-golden-header.growth.md` **wholesale** every run. That is deliberate:
wholesale regeneration is what allows **consolidation** (merge, supersede, drop-on-later-evidence).
Append-only would forbid all three and let the region accrete contradictions. The same property is the
hazard — a rule present yesterday can be absent today.

**Already fixed in `ad3c454` — do not re-solve:** the existing GROWTH is now an INPUT the curator must
read; step 4 requires regeneration *from the previous content plus new entries*; a dedicated
`## GROWTH accounting` sidecar section carries the account; `Get-SidecarRecoverySections` retains it into
the append-only drain log.

**What remains: nothing CHECKS the account.** A prompt is a request, and an instruction competing with
anything else in the context window is honoured probabilistically — measured twice this session across
two different models.

## 2. Why the obvious mechanisms fail — recorded so they are not re-proposed

| approach | why it fails |
|---|---|
| **Count-based assertion** | Gameable, demonstrated: drop a hard-earned rule, add a new one or split a trivial one. Count unchanged, gate passes, knowledge gone. **Count is not an oracle for identity.** |
| **Semantic matching** | Identity judgement over natural language measured **low-recall twice on 2026-08-27** — two readers, same 45 entries, 2 collisions each, **zero overlap**. A gate built from it fails open silently. |
| **Stable per-rule IDs in GROWTH** | Pollutes an artifact injected into every ask, spending token budget on bookkeeping; and an ID survives while the text it names is gutted. |
| **Append-only with strike-throughs** | Dead rules stay in the injected text forever, and it removes consolidation entirely. |
| **~~80-character prefix as the rule identifier~~** | 🔴 **KILLED IN ROUND 1.** Impossible for rules shorter than 80 chars; collides when two rules share a leading tag; and the delimiter `\|` it needed can occur inside rule text. Replaced by §3.2. |

## 3. The design — require an ACCOUNT, check it mechanically

Do not ask a machine whether knowledge was lost. Require the curator to **declare what it did to every
prior rule**, and check that the declaration is **total** and that **every declared target exists**.

### 3.1 The rule unit, and a TOTAL parse
MEASURED 2026-08-27 against the live GROWTH: **18 top-level bullets under 2 section headers**, 123 lines.
A *rule* is a `^- ` bullet plus its continuation lines, terminated by the next `^- `, a `^[` section
header, **or END OF FILE** (round 1: v1 omitted the EOF terminator and would have stranded the last rule
on every run).

🔴 **THE PARSE MUST BE TOTAL, NOT MERELY NON-ZERO.** v1 only failed closed at zero rules. Round 1 showed
the real hazard: if 18 rules parse as 15, the gate demands accounting for 15 and **the other 3 vanish
with no accounting required at all** — the gate's own blind spot becomes the loss channel.
**Requirement: the parser must round-trip.** Re-concatenating the parsed rules plus the parsed headers
must reproduce the source file byte-for-byte after newline normalisation. Any residue is a parse the
model does not understand: **fail closed and name the residue.** A count check cannot detect this; only
a round-trip can.

### 3.2 Rule identity — a content hash, not a prefix
Each rule is identified by `sha256(normalised(rule_text))` truncated to 12 hex characters, where
`normalised` = CRLF→LF, strip trailing whitespace per line, strip leading/trailing blank lines.
(The repo has a documented CRLF hazard; normalisation is not optional.)

This fixes three round-1 findings at once: it is **fixed-length regardless of rule length**, it **cannot
collide** across a corpus of this size, and it **contains no delimiter** that could occur in rule text.
The hash never enters the GROWTH file itself, so the injected token budget is untouched.

### 3.3 The accounting entry — a RIGID schema
v1 said "quotes its first 80 characters" without saying how, which round 1 correctly called impossible to
parse deterministically. The schema is fixed:

```
- [<disposition>] <prev-hash> -> <target-hash|-> | <excerpt> | <reason>
```

- `<disposition>` ∈ `survived-reworded` · `merged-into` · `superseded-by` · `dropped` — exactly one,
  bracketed, machine-matched.
- `<prev-hash>` identifies the rule in `PREV`.
- `<target-hash>` names the rule in `NEW` that carries it forward. **Literal `-` ONLY for `dropped`.**
- `<excerpt>` — first 60 chars of the previous rule, for the HUMAN. The gate never matches on it.
- `<reason>` — free text, required for `dropped` and `superseded-by`.

### 3.4 🔴 `dropped` MUST NOT DESTROY — the round-1 finding that changes the mechanism
Round 1's sharpest point: a curator can satisfy any purely-declarative account by writing
`dropped: I thought it was noise` for every rule. The account is total, the gate passes, everything is
gone. A confession is not a preservation guarantee.

**So `dropped` is redefined as DEMOTION, not deletion.** A `dropped` disposition REQUIRES the rule's
originating observation to be **restored to the inbox as pending**, where a future drain will reconsider
it. The gate verifies the restoration happened.

Knowledge then cannot leave the system through this path at all — only move between tiers:
**GROWTH → inbox → (a later drain) → GROWTH or a recorded disposition.** This is what actually honours
the owner's constraint, rather than documenting its violation.

⚠ **Open dependency:** this requires a rule to be traceable to its originating observation(s). The
`## Promoted` sidecar section records `source observation → GROWTH` per item, so the linkage exists in the
per-run sidecar — but it is **not currently carried into the drain log** and has never been exercised.
Confirm before building.

### 3.5 The check
`PREV` = rules in the previous GROWTH · `NEW` = rules in the proposed GROWTH · `ACCT` = accounting bullets.

For every rule in `PREV`, exactly one must hold:
1. its hash appears in `NEW` (survived untouched — no entry needed); or
2. an `ACCT` entry names its hash, **and** — unless the disposition is `dropped` — the entry's
   `<target-hash>` **exists in `NEW`**. 🔴 v1 checked only that the claim was present; round 1 showed a
   curator could write `survived-reworded` while omitting the text from `NEW` entirely and pass.

Any `PREV` rule satisfying neither is an **unaccounted loss**: FAIL, naming the rule by hash and excerpt.
**Never print an 800-character rule into a failure message** — a bounded excerpt only.

### 3.6 The gate must REPORT, not just verdict
Round 1: if the curator leaves `PREV` untouched and adds fifteen unreviewed new rules, the gate passes and
prints nothing, and "0 accounting entries, PASS" reads as a no-op drain while hiding a large new payload.
**Every run prints a census**: `|PREV|`, `|NEW|`, rules survived-verbatim, entries per disposition, and
**rules in `NEW` with no counterpart in `PREV` (i.e. genuinely new)**. A PASS with 15 new rules must look
different from a PASS with none.

### 3.7 Where it runs — both, and each reads a DIFFERENT baseline
- **Drain time**, pre-review: `PREV` = GROWTH at `HEAD`; `NEW` = the working-tree proposal. Catches the
  curator before a destructive diff reaches a human. Blind to a human editing after the gate ran.
- **Accept time**, at publish: catches curator *and* human edits, on the exact bytes about to publish.
  🔴 **`PREV` here is the GROWTH at the drain commit's PARENT, never `HEAD`.** v1 said "from git HEAD" for
  both; round 1 showed that at accept time `HEAD` already *contains* the new GROWTH, so `PREV == NEW`,
  every rule matches, and the gate passes 100% of the time. That single word would have made the
  accept-time placement entirely vacuous.

## 4. 🔴 THE FIRST RUN IS A NO-OP UNLESS A BASELINE IS COMMITTED FIRST
MEASURED: `git log` shows **zero commits** have ever touched `docs/agy-golden-header.growth.md` or
`docs/agy-drain-proposal.md`. So `PREV` resolved from git is **empty today**, and the gate would pass
vacuously on exactly the transition where the loss occurs — the second drain, which is the first one that
can destroy anything.

**Requirement, not a fork:** before this gate is meaningful, the current runtime GROWTH must be committed
as the baseline. Until then the gate MUST print `PREV is empty — this run is unprotected` rather than a
silent PASS.

## 5. Acceptance criteria
1. A drain dropping a previous rule with no accounting entry **fails**, naming it by hash + excerpt.
2. A drain dropping a rule **and adding a new one** (the count-neutral attack) still **fails** — the
   criterion that distinguishes this from the rejected count-based design.
3. An entry claiming `survived-reworded` whose `<target-hash>` is absent from `NEW` **fails**.
4. Every previous rule surviving verbatim passes with an **empty** account and a census showing it.
5. A first drain with no previous GROWTH passes **and prints the unprotected-run warning**.
6. A GROWTH file whose parse leaves ANY residue fails closed, naming the residue.
7. A `dropped` entry whose observation was not restored to the inbox **fails**.
8. Every new check is **mutation-verified**: the specific new test reds under a logic mutant, and
   assertions are POSITIVE wherever a `-Not -Match` could pass vacuously.

## 6. Open forks — for the owner
- **Drain-time severity.** Hard-fail, or warn-and-halt? The neighbouring budget gate is **warn-only**, and
  that choice is part of how the cap breach went unnoticed for weeks. Consistency argues one way, the
  owner's hard constraint the other.
- **§3.4's restoration mechanism** depends on rule→observation traceability that exists in the sidecar but
  has never been exercised. If it proves unreliable, `dropped` falls back to confession-only and the
  guarantee weakens to v1's — the owner should know that before the build starts.
- **Checker interface** — script name, exit codes, invocation from both placements — deliberately
  unspecified here; it belongs in the plan, once this design is settled.

# GROWTH accounting gate — design

**Status:** SPEC **v4**. v1/v2/v3 all REJECTED by panel (rounds 1–3; 22 findings). v4 folds round 3 and
adds nothing new — every change below is a correction, a retraction, or a statement of a limit that was
previously unstated. **Round 4 not yet run.**

## Standing constraints, in priority order

1. **KNOWLEDGE MUST BE PRESERVED — nothing lost.** It cannot be implemented, only earned, which makes it
   the most valuable content in the repository.
2. **MINIMAL TOKEN SPENDING.** The injected block is charged to the user's agent **every session**; the
   drain's own context is charged every run. This is the same intent already recorded in both `MaxBytes`
   constants. It is not a tiebreaker — it has already killed one otherwise-attractive fix (§0.1).

**v4's token cost against constraint 2, stated up front because it must be:** **zero injected bytes.**
Every mechanism here lives in the gate, the sidecar and the append-only log — all offline maintainer
artifacts. The GROWTH file itself is untouched, so nothing in this design reaches a session's context.

---

## 0. What this guarantees — and the overclaim v3 made

**The guarantee, and the only one:**
> Every rule that leaves the GROWTH region, by any route, has its **full verbatim text** recorded in the
> append-only drain log, permanently.

### 0.1 🔴 RETRACTED: GROWTH is NOT a cache
v3 called GROWTH *"a CACHE — a compiled, regenerable projection"*. **That was wrong and round 3 broke it.**
A cache is rebuildable from its store. **The curator is never fed the drain log** — its inputs are the
staging snapshot, SEED, `agy-verify-needed.md`, and the existing GROWTH. So if GROWTH is emptied, the next
drain rebuilds from the inbox alone and the log's contents never return.

**Preserved ≠ recoverable.** The correct statement:

> The log **preserves** every departed rule's text for **human** recovery. It is **not** an automatic
> rebuild source, and GROWTH is the sole *active* store.

**The obvious fix — feed the log to the curator — is RULED OUT by constraint 2.** The log grows without
bound and would be re-read on every drain, spending context that buys nothing on a normal run. Recovery
is therefore a **documented manual procedure**: read the log, re-add the wanted rule text to the inbox as
a pending entry, drain. Rare by construction, and it costs nothing until it is needed.

### 0.2 What this still does NOT do
- It does not judge whether a curation decision was wise. No mechanism here can.
- It does not prevent a curator emptying GROWTH. If one does, GROWTH is empty and **every rule's text is
  in the log**. The injected region degrades; the knowledge does not.
- **The account is the review surface, not the gate's verdict.** The gate's job is to make the account
  complete, bound and legible so a human can read it — which matters because of the **chameleonic
  compliance** finding: review is weakest against a large, careful-looking diff and strongest against a
  short enumerated list.

## 1. The defect, and what is already shipped

The drain regenerates GROWTH **wholesale** each run — deliberate, because that is what allows
consolidation (merge, supersede, drop-on-later-evidence), which append-only would forbid. The same
property is the hazard: a rule present yesterday can be absent today.

**Shipped in `ad3c454` — do not re-solve:** the existing GROWTH is a curator INPUT; step 4 regenerates
from previous + new; `## GROWTH accounting` exists; the append-only log retains it (mutation-verified).

**What remains: nothing CHECKS the account.** A prompt is a request, and an instruction competing with
other content in the same context window is honoured probabilistically — measured twice, two models.

## 2. Approaches killed, with the reason — so they are not re-proposed

| approach | why it fails |
|---|---|
| **Count-based assertion** | Drop a rule, add another. Count unchanged, gate passes. **Count is not an oracle for identity.** |
| **Semantic matching** | Identity judgement over natural language measured **low-recall twice** — two readers, same 45 entries, 2 findings each, **zero overlap**. Fails open silently. |
| **~~80-char prefix identity~~** | R1: impossible for short rules, collides on shared leading tags, needed a delimiter that occurs in rule text. |
| **~~SHA-256 identity~~** | R2, fatal: the curator IS the LLM and would have to emit hashes for text **it had just written**. *"Statistically impossible."* |
| **~~`dropped` as demotion-to-inbox~~** | R2, three kills: **ping-pongs** with no terminal state; **deadlocks** on legacy rules with no recorded observation; **contradicts** the gate's own guarantee by mutating state. |
| **~~Target verification~~** | R2: existence does not imply relatedness. Bought nothing, cost the hash scheme. ⚠ Its removal has a price — see §3.5. |
| **~~Feeding the drain log to the curator~~** | 🔴 **v4: killed by constraint 2**, not by correctness. It would make GROWTH genuinely rebuildable, but at unbounded and growing per-drain context cost. |

## 3. The design

### 3.1 The rule unit, and a TOTAL parse
MEASURED against the live GROWTH: **18 top-level bullets under 2 section headers**, 123 lines. A *rule* is
a `^- ` bullet plus continuation lines, terminated by the next `^- `, a `^[` header, **or EOF**.

🔴 **The parse must ROUND-TRIP, not merely be non-zero.** If 18 rules parse as 15, the gate demands
accounting for 15 and the other 3 vanish unaccounted — the gate's blind spot becomes the loss channel, and
a count check cannot see it. **Re-concatenating parsed rules + headers must reproduce the source
byte-for-byte after newline normalisation. Any residue fails closed, naming the residue.**

### 3.2 Normalisation — ONE shared implementation, and it MUST DEDENT
Applied to both sides before any comparison:
1. CRLF → LF
2. **strip a uniform leading indent from every line of the block** (dedent)
3. strip trailing whitespace per line
4. strip leading/trailing blank lines

🔴 **Step 2 is the round-3 fix and it was fatal without it.** v3 mandated the accounting block be
*"indented two spaces"* while normalising trailing whitespace only. A `PREV` rule reads `- rule`; the same
text in the account reads `  - rule`; **they never match, so every departed rule would have failed the
gate on every run.** The schema's own indent mandate broke the exact-match it depended on.

⚠ **One implementation, shared by both placements.** Two copies that drift produce a gate that passes at
drain time and fails at accept time on identical bytes.

### 3.3 The accounting entry
For **every** rule in `PREV` that does not appear verbatim in `NEW`:

```
- [<disposition>] <reason>
  <the full verbatim text of the previous rule, indented two spaces>
```

- `<disposition>` ∈ `reworded` · `merged` · `superseded` · `dropped` — bracketed, machine-matched, exactly
  one. **Prose for the human; the gate does not verify it**, because R2 showed target verification proves
  nothing about relatedness while costing implementability.
- `<reason>` — free text, always required.
- The indented verbatim block is load-bearing: it is what the log preserves and what the gate matches.

⚠ **Uniform across dispositions ON PURPOSE.** If only `dropped` required the text, a curator could evade
the record by labelling a deletion `merged`. Requiring it for every departure closes that by construction.

### 3.4 The check — PER ENTRY, not per file
> **For every rule in `PREV`: its normalised text appears verbatim EITHER in `NEW`, OR as the verbatim
> block of EXACTLY ONE well-formed `ACCT` entry** — an entry with a bracketed disposition and a non-empty
> reason.

🔴 **"Exactly one well-formed entry" is the round-3 fix.** v3 asked only whether the text appeared in
`ACCT` *anywhere*, so a curator could dump ten dropped rules' text into a single unrelated entry's reason
block: the string match passed while every disposition and reason — the entire human review surface — was
destroyed, with the gate green.

Anything else is an **unaccounted departure**: FAIL, named by bounded excerpt. **Never print an
800-character rule into a failure message.**

### 3.5 The census — and the limitation removing target links bought
**Every run prints:** `|PREV|`, `|NEW|`, survived-verbatim, entries per disposition, and rules in `NEW`
with no counterpart in `PREV`.

⚠ **STATED LIMIT, previously unstated.** Without target links the gate cannot pair a `reworded` entry with
its resulting text, so **every reworded rule's new text reads as "no counterpart in PREV"** and a batch of
hallucinated rules can hide in that noise.

**Cheap mitigation — arithmetic, not machinery, and it costs no tokens:** the census also prints
`unexplained = |new-in-NEW| - |ACCT entries dispositioned reworded/merged/superseded|`. If the account
claims 5 rewordings and 12 rules look new, **7 are unexplained** and the human is told so by name. This
does not identify *which*; it bounds how much surprise is present, which is what a reviewer needs to know
whether to look closely.

### 3.6 Where it runs — both, each on a DIFFERENT baseline
- **Drain time**, pre-review: `PREV` = GROWTH at `HEAD`, `NEW` = the working-tree proposal. Catches the
  curator before a destructive diff reaches a human.
- **Accept time**, at publish: catches curator *and* human edits, on the exact bytes about to publish.
  🔴 **`PREV` here is the drain commit's PARENT, never `HEAD`** — at accept time `HEAD` already contains
  the new GROWTH, so a `HEAD` baseline makes `PREV == NEW` and the placement is entirely vacuous.

🔴 **A human deleting a rule at review must NOT be forced to hand-write sidecar syntax** (round 3: that
contradicted the gate's own "no decision forbidden"). The accept-time failure **prints the complete
ready-to-paste accounting entry**, verbatim block included, with the disposition left as
`[dropped] <reason>` for the human to complete. The decision stays the human's; the gate supplies the
bureaucracy rather than demanding it.

## 4. 🔴 THE FIRST RUN IS UNPROTECTED UNLESS A BASELINE IS COMMITTED
MEASURED: **zero commits** have ever touched `docs/agy-golden-header.growth.md` or
`docs/agy-drain-proposal.md`. `PREV` from git is **empty today**, so the gate passes vacuously on exactly
the transition where loss occurs — the second drain, the first able to destroy anything.

**Requirement:** commit the current runtime GROWTH as the baseline first. Until then the gate MUST print
`PREV is empty — this run is unprotected`, never a silent PASS.

## 5. Acceptance criteria
1. A `PREV` rule absent from both `NEW` and `ACCT` **fails**, named by bounded excerpt.
2. The count-neutral attack — drop a rule, add a new one — **fails** unless the dropped rule's verbatim
   text is present. Distinguishes v4 from the rejected count-based design.
3. Labelling a deletion `merged` rather than `dropped` changes nothing — **no disposition is an escape
   hatch**.
4. Ten rules' text dumped into ONE entry's reason block **fails** — the per-entry binding of §3.4.
5. A rule whose `PREV` form is indented differently from its `ACCT` form still **matches** — the dedent of
   §3.2, which without a test would regress silently and fail every run.
6. Every previous rule surviving verbatim passes with an **empty** account and a census showing it.
7. A first drain with no previous GROWTH passes **and prints the unprotected-run warning**.
8. A GROWTH parse leaving ANY residue fails closed, naming the residue.
9. A rule whose text is in `ACCT` is present **verbatim in the append-only log** after the run — §0's
   guarantee asserted end to end, not assumed from the retention code.
10. A census where rewordings do not account for the new-rule count prints `unexplained = N`.
11. An accept-time failure prints a ready-to-paste entry — asserted on its content, not just its exit code.
12. Every new check is **mutation-verified**: the specific test reds under a logic mutant, and assertions
    are POSITIVE wherever a `-Not -Match` could pass vacuously.

## 6. Open forks — for the owner
- **Drain-time severity:** hard-fail, or warn-and-halt? The neighbouring budget gate is **warn-only**, and
  that choice is part of how the cap breach went unnoticed for weeks.
- **Log growth vs constraint 2:** every departing rule adds ~800 B to an append-only file. The log is a
  maintainer record and is **never injected**, so it costs no session tokens — but it is unbounded on
  disk, and §0.1's manual recovery means someone eventually reads it. Worth confirming, not assuming.
- **Checker interface** — script name, exit codes, invocation from both placements — belongs in the plan.

# GROWTH accounting gate — design

**Status:** SPEC **v5 — a SUBTRACTION.** v1–v4 all REJECTED (rounds 1–4, 27 findings). v5 adds no
mechanism and **deletes two**. Owner-directed after the round-4 pattern became clear: since round 3 the
core has gone unchallenged, and every finding since has landed on a mitigation bolted over an admitted
limitation. **Round 5 not yet run.**

## Standing constraints, in priority order
1. **KNOWLEDGE MUST BE PRESERVED — nothing lost.** It cannot be implemented, only earned.
2. **MINIMAL TOKEN SPENDING** — both the injected block (charged every session) and the drain's own
   context and output (charged every run).

### v5's honest cost against constraint 2
- **Injected bytes: zero.** Every mechanism lives in the gate, the sidecar and the log — offline
  maintainer artifacts. The GROWTH file is untouched, so nothing here reaches a session's context.
- 🔴 **Output tokens: NOT zero, and v4 hid this behind the input-side claim.** Requiring the full verbatim
  text of every departed rule costs the curator **output** tokens — the expensive, latency-bound side —
  and risks **max-output truncation mid-sidecar**. See §3.6: the answer is to bound how much a single
  drain may shed, not to shrink the record.

---

## 0. The guarantee
> Every rule that leaves the GROWTH region, by any route, has its **full verbatim text** recorded in the
> append-only drain log, permanently.

**GROWTH is NOT a cache** (retracted in v4, restated here because it is the axiom everything rests on).
The curator is never fed the log, so if GROWTH is emptied the next drain rebuilds from the inbox alone.
**Preserved ≠ recoverable.** The log preserves departed text for **human** recovery via a documented
manual procedure — read the log, re-add the wanted text to the inbox as pending, drain. Feeding the log
to the curator would make GROWTH genuinely rebuildable but is **ruled out by constraint 2**: it grows
without bound and would be re-read every run.

**What this does not do:** it does not judge whether a curation decision was wise, and it does not prevent
a curator emptying GROWTH. If one does, GROWTH is empty and every rule's text is in the log.

🔴 **AND IT DOES REQUIRE A DEPARTURE TO BE RECORDED — INCLUDING A HUMAN'S.** v3 and v4 claimed "no
decision forbidden". **That was false and is withdrawn.** A gate that fails on an unrecorded deletion is,
precisely, forbidding an unrecorded deletion. That is the entire point; dressing it up as neutral was the
dishonest part, not the requirement.

## 1. What is already shipped
The drain regenerates GROWTH **wholesale** each run — deliberate, because it allows consolidation (merge,
supersede, drop-on-later-evidence) which append-only forbids. The same property is the hazard.

**Shipped in `ad3c454` — do not re-solve:** the existing GROWTH is a curator INPUT; step 4 regenerates
from previous + new; `## GROWTH accounting` exists; the append-only log retains it (mutation-verified).
**What remains: nothing CHECKS the account.**

## 2. Killed approaches — the reason, so none is re-proposed
| approach | why |
|---|---|
| Count-based assertion | Drop one, add one. Count unchanged. **Count is not an oracle for identity.** |
| Semantic matching | Measured **low-recall twice**: two readers, same 45 entries, 2 findings each, **zero overlap**. Fails open silently. |
| ~~80-char prefix identity~~ | R1: impossible for short rules, collides on shared tags, needed a delimiter that occurs in rule text. |
| ~~SHA-256 identity~~ | R2, fatal: the curator IS the LLM and would emit hashes for text **it just wrote**. |
| ~~`dropped` as demotion-to-inbox~~ | R2: ping-pongs with no terminal state; deadlocks on legacy rules; mutates state. |
| ~~Target verification~~ | R2: existence ≠ relatedness. |
| ~~Feeding the log to the curator~~ | v4: killed by **constraint 2**, not by correctness. |
| ~~The `unexplained` census arithmetic~~ | 🔴 **DELETED IN v5.** R4 killed it twice: it is **1:1 arithmetic over an N:M domain** (merge 3 into 1 ⇒ `1-3 = -2`; supersede 1 with 3 ⇒ false alarm), and it was **forgeable** — fabricate entries to zero the balance and smuggle the payload it existed to expose. |
| ~~"No decision forbidden"~~ | 🔴 **WITHDRAWN IN v5** as a false claim about what the gate does. See §0. |

## 3. The design

### 3.1 The rule unit, and a TOTAL parse
MEASURED: **18 top-level bullets under 2 section headers**, 123 lines. A *rule* is a `^- ` bullet plus
continuation lines, terminated by the next `^- `, a `^[` header, **or EOF**.

🔴 **The parse must ROUND-TRIP.** If 18 rules parse as 15, the gate demands accounting for 15 and 3 vanish
unaccounted — the gate's blind spot becomes the loss channel, and a count check cannot see it.
**Re-concatenating parsed rules + headers must reproduce the source byte-for-byte after newline
normalisation. Any residue fails closed, naming it.**

### 3.2 Normalisation — ONE shared implementation, and it MUST DEDENT
CRLF→LF · **dedent the block** · strip trailing whitespace per line · strip leading/trailing blank lines.

🔴 **The dedent is not optional.** v3 mandated a two-space indent while normalising trailing whitespace
only, so `- rule` and `  - rule` could never match and **every departed rule would have failed on every
run.** One shared implementation: two copies that drift pass at drain time and fail at accept time on
identical bytes.

### 3.3 The accounting entry
For **every** rule in `PREV` absent from `NEW`:
```
- [<disposition>] <reason>
  <the full verbatim text of the previous rule, indented two spaces>
```
`<disposition>` ∈ `reworded` · `merged` · `superseded` · `dropped` — bracketed, exactly one, **prose for
the human; the gate does not verify it** (R2: target verification proves nothing about relatedness).
`<reason>` required. The verbatim block is load-bearing: it is what the log preserves and the gate matches.

⚠ **Uniform across dispositions ON PURPOSE.** If only `dropped` required the text, a curator could evade
the record by labelling a deletion `merged`.

### 3.4 The check — the whole mechanical contract
> **For every rule in `PREV`: its normalised text appears verbatim EITHER in `NEW`, OR as the verbatim
> block of EXACTLY ONE well-formed `ACCT` entry** — bracketed disposition, non-empty reason.

Per-entry binding matters: v3 asked only whether the text appeared in `ACCT` anywhere, so ten rules dumped
into one entry's reason block passed while every disposition and reason was destroyed.

Anything else is an **unaccounted departure**: FAIL, named by bounded excerpt. Never print a whole rule.

**That is the entire contract.** No targets, no hashes, no arithmetic, no state mutation.

### 3.5 The census — RAW COUNTS ONLY, and one honest limitation
**Prints, and never gates on:** `|PREV|`, `|NEW|`, survived-verbatim, entries per disposition, rules in
`NEW` with no counterpart in `PREV`, and **`ACCT` entries matching no `PREV` rule** (non-zero means
something is wrong; it is an observation, not a verdict).

⚠ **STATED LIMITATION, no longer papered over:** the gate **cannot** distinguish a reworded rule's new
text from a hallucinated new rule. Removing target verification bought implementability and cost this.
v4 tried to recover it with derived arithmetic; the arithmetic was wrong and forgeable, so **v5 reports
the raw numbers and says plainly what they do not tell you.** A number a reviewer can interpret beats a
metric that is confidently wrong.

### 3.6 Bounding the output cost — the answer to constraint 2
A drain that sheds many rules must emit each one verbatim, which is where the output-token and truncation
risk lives. **The bound is on the DRAIN, not the record:** if a single drain would shed more than `N`
rules, it **fails and says the drain is too large — split it**. Shrinking the record instead would
re-open the `merged`-relabelling evasion. `N` is unset; see §6.

### 3.7 Where it runs — both, each on a DIFFERENT baseline
- **Drain time**, pre-review: `PREV` = GROWTH at `HEAD`, `NEW` = the working-tree proposal.
- **Accept time**, at publish: on the exact bytes about to publish.
  🔴 **`PREV` is resolved BY RUN-ID from the committed drain log, never by git position.** v4 said "the
  drain commit's PARENT", and R4 showed a blind `HEAD^` validates only the last commit — so a human who
  commits more than once before publishing gets a **vacuous pass while the gate reports success**.
  `accept-drain` already requires the run to be in the committed log (F30), so the run-id is available and
  the baseline is derivable from it rather than guessed from history shape.

🔴 A human deleting a rule at review gets the **complete ready-to-paste entry printed** by the failure.
This reduces the burden; §0 is now honest that it does not remove it.

## 4. 🔴 THE FIRST RUN IS UNPROTECTED UNLESS A BASELINE IS COMMITTED
MEASURED: **zero commits** have ever touched `docs/agy-golden-header.growth.md` or
`docs/agy-drain-proposal.md`. `PREV` from git is empty today, so the gate passes vacuously on exactly the
transition where loss occurs. **Commit the current runtime GROWTH as the baseline first**; until then the
gate MUST print `PREV is empty — this run is unprotected`, never a silent PASS.

## 5. Acceptance criteria
1. A `PREV` rule absent from both `NEW` and `ACCT` **fails**, named by bounded excerpt.
2. Drop a rule and add a new one (count-neutral) **fails** unless the dropped text is present.
3. Labelling a deletion `merged` rather than `dropped` changes nothing — **no disposition is an escape**.
4. Ten rules' text dumped into ONE entry's reason block **fails** (per-entry binding).
5. A rule indented differently in `ACCT` than in `PREV` still **matches** (the dedent — without a test it
   regresses silently and fails every run).
6. All rules surviving verbatim passes with an **empty** account and a census showing it.
7. A first drain with no previous GROWTH passes **and prints the unprotected-run warning**.
8. A parse leaving ANY residue fails closed, naming the residue.
9. A rule accounted for in `ACCT` is present **verbatim in the append-only log** after the run — §0
   asserted end to end, not assumed from the retention code.
10. A drain shedding more than `N` rules **fails as too large**.
11. Accept-time resolves its baseline by **run-id**; a run with two commits between drain and accept is
    still checked against the drain's baseline, not `HEAD^`.
12. Every new check is **mutation-verified**: the specific test reds under a logic mutant, and assertions
    are POSITIVE wherever a `-Not -Match` could pass vacuously.

## 6. Open forks — for the owner
- **`N`, the per-drain departure bound.** Unset deliberately. It should be *measured* against a real drain
  rather than guessed, and it trades constraint 2 against drain ergonomics.
- **Drain-time severity:** hard-fail or warn-and-halt? The neighbouring budget gate is **warn-only**, and
  that is part of how the cap breach went unnoticed for weeks.
- **Checker interface** — script name, exit codes, invocation from both placements — belongs in the plan.

# GROWTH knowledge tiering — design

**Status:** SPEC **v7.** v1–v5 were an *accounting gate* and were rejected five times (32 findings); v6
replaced it with tiering and was rejected once (5 findings). v7 folds round 6. **Round 7 not yet run.**

## Standing constraints, in priority order
1. **KNOWLEDGE MUST BE PRESERVED — nothing lost.** ✅ **OWNER-RULED 2026-08-27: reading (a), NEVER
   DESTROYED.** An archive satisfies it; the knowledge is not required to be in the agent's context at all
   times. This ruling was open for three rounds and it **validates the tiering shape** — under reading (b)
   (*always available to the agent*) tiering would have been the wrong design regardless of quality.
2. **MINIMAL TOKEN SPENDING** — the injected block is charged every session; the drain's context and
   output are charged every run.

**v7 cost against constraint 2: injected bytes go DOWN.** GROWTH becomes a selected projection rather than
the store, bounded by choice instead of by a cap it keeps hitting. Nothing else here is ever injected.

---

## 0. 🔴 THE ROOT CAUSE OF FIVE REJECTED VERSIONS
**GROWTH is currently BOTH the store AND the projection.** If the only copy of a rule *is* the thing
regenerated wholesale, every regeneration is a potential loss and the only defence left is to audit the
regeneration. All 32 accounting-gate findings were downstream of that one error. **The fix is not a better
audit; it is to give the projection a store to be a projection OF.**

## 1. 🔴 THE PORTING ERROR ROUND 6 EXPOSED — and it is about the SOURCE, not the port
v6 ported the memory-index pattern: tier 1 bounded and always loaded, tier 2 unbounded and on demand,
compaction = relocation with a pointer. **MEASURED: tier 2 is 96× tier 1** (2,320,862 B / 24,400 B),
eleven compactions, no fact lost, and **no ledger** — its guarantee is *reachability*.

Round 6 found that **coordinated deletion defeats reachability**: remove a file *and* its pointer together
and both checks pass — `mlc` sees no dangling pointer, the orphan sweep no longer enumerates the file.

**So I measured the source system.** 🔴 **The memory directory is NOT A GIT REPO.** It has no history and
no recovery from a deletion. **It has the identical hole**, and it has survived only because a human edits
it incrementally and nothing automated regenerates it.

> **The porting error: I copied a pattern whose safety rests on a property the target lacks — careful
> incremental human editing — and left behind the property the target HAS: git.**

### 1.1 Corroboration from a second memory system, asked directly
The peer was asked about its own persistent memory, with explicit licence to answer "I have no such
thing". It reported an **append-mostly** store whose conflict resolution is left **entirely to
convention** — *"the system itself does not merge or complain"* — and named its own lived failure mode
unprompted: **dilution**, where querying one topic returns several contradictory states from different
days and the reader must deduce which is current. It also could not determine whether its deletions are
recoverable, so *nothing lost* is **not** a property it has.

Two things follow, and both are load-bearing here:
- **Append-only-without-consolidation degrades by accretion.** §2 rejected it on theory; this is lived
  evidence from a running system.
- **CONVENTION IS NOT A MECHANISM.** Same shape as this repo's own measurement that an instruction
  competing with other content is honoured probabilistically.

## 2. The model
- **THE STORE — tier 2, never injected, unbounded, and IN THE REPO UNDER GIT.** Every rule earned lives
  here permanently, whether or not it is currently projected.
- **GROWTH — tier 1, injected every ask, capped.** A *selected projection* of the store. 🔴 **It carries
  NO POINTERS** (see §4.3).
- **The inbox** is upstream of both: raw observations awaiting distillation into store rules.

**A rule absent from GROWTH is not gone. It is not currently projected.** That sentence makes all 32
accounting findings moot rather than fixed — none describes a real event any more.

## 3. The guarantee — corrected
v6 claimed *"preservation is a property of the store, which nothing overwrites."* 🔴 **False, and round 6
was right: consolidation REQUIRES mutation.** Merge, supersede and drop-on-later-evidence all rewrite
store files, so preservation cannot be intrinsic to the store.

> **Preservation is a property of the STORE PLUS VERSION CONTROL.** The store is in git; every prior text
> of every rule is in history; **deleting a store file is a gate failure.** Consolidation edits CONTENT
> freely — that is the point of it — and git keeps what it replaced.

This closes coordinated deletion **mechanically and without a ledger**: the two topological checks cannot
see a synchronised removal, but git can, because the file existed at the baseline and does not now.

## 4. The checks
⚠ MEASURED 2026-08-27 against a fixture with known ground truth:

| condition | `mlc` v1.2.0 | usable? |
|---|---|---|
| link → missing file | `[Err] Target filename not found`, **exit 1** | ✅ gate it |
| file nothing links to | **reports nothing** | ❌ opposite direction |
| `[[wikilink]]` | `[Warn]`, unresolved | ❌ invisible to it |

### 4.1 Deletion — git, and this is the one that matters
A store file present at the baseline and absent now **fails**, named. No exceptions, no dispositions, no
reasons: to retire a rule you edit its content, you do not delete its file. **This is the check v6 lacked
entirely and the reason round 6 was fatal.**

### 4.2 Dangling pointers — `mlc`, on ITS OWN exit code
🔴 **The store MUST use standard `[text](rule.md)` links, not `[[wikilinks]]`** — measured above, mlc
cannot resolve them, so a wikilink store is **invisible to its own gate**.
⚠ **Read mlc's exit code directly.** Measured: `mlc . | tail` reported 0 while mlc exited 1 — `$?` was
`tail`'s. The repo's standing "read the gate's OWN exit code" trap, which bit inside this measurement.

### 4.3 Orphans — a complement, and why GROWTH carries no pointers
`mlc` validates that pointers resolve; it says nothing about a file nothing points at. Complement:
enumerate store files, enumerate linked targets, fail on the difference.

🔴 **GROWTH carries NO pointers, because it cannot.** Round 6: a curator denied the store listing
(constraint 2) cannot emit exact filenames for files it cannot see, so wholesale regeneration would fail
§4.2 on every run. **Reachability is provided by the store's OWN committed index, maintained
incrementally** — the way the source system is maintained, which §1 identifies as the property that makes
it safe.

### 4.4 The infrastructure already exists — this wires it
⚠ Correcting an earlier draft that called mlc undeclared; that came from a `head -12` of a **14-entry**
manifest. Facts: `mlc` **is** declared, `just check-links` **exists**, `.mlc.toml` **exists** scoped to
tracked product docs — **but it is wired into NEITHER lefthook NOR CI**, so it fires only when someone
remembers. Wiring the existing recipe is the work.
🔴 **`.mlc.toml` deliberately ignores gitignored paths, so a store placed under one would be invisible to
the gate meant to protect it** — the same shape as `check-growth-budget.ps1` reading repo paths while the
breach was in the runtime files. **Site the store inside the gate's scope, and inside git — §3 depends on
it.**

## 5. The write path — round 6's "no write path" finding, answered
v6 specified validation and reading and never said how a rule enters or leaves the store. It shrank partly
by deferral. Concretely:
- **Enters:** the drain distils an inbox observation into a store rule file and adds it to the store index.
  One file per rule, named `<slug>.md`; the index gains one `[title](rules/<slug>.md)` line.
- **Changes:** consolidation edits the file in place. Merging two rules edits one and empties the other to
  a superseded stub that keeps its link — **the file is never removed**, per §4.1.
- **Leaves GROWTH:** by not being selected. No event, no record, nothing to check.
- **Leaves the STORE:** it does not. That is the whole guarantee.

## 6. What v7 deletes from the earlier designs
The entire accounting apparatus — dispositions, verbatim blocks, per-entry binding, the census, departure
bounds, run-id baselines, drain-time and accept-time placements — and v6's false "nothing overwrites"
axiom. None survives; none has anything left to check.

## 7. Acceptance criteria
1. A store file present at the baseline and deleted now **fails**, named.
2. Deleting a store file **and** its index pointer together **still fails** — the coordinated deletion that
   defeated v6, and the criterion that distinguishes v7 from it.
3. A pointer to a non-existent rule **fails** `mlc`, wired to read **mlc's own exit code**, proven by a
   test that pipes it and shows the code is masked.
4. A store written in `[[wikilink]]` style **fails** — the gate must be able to see its own subject.
5. A store file nothing links to **fails** the orphan sweep.
6. GROWTH regenerated with **any** subset of the store passes: selection is never an error.
7. A rule edited in place — including emptied to a superseded stub — **passes**, and its prior text is
   retrievable from git history.
8. A store sited outside `.mlc.toml`'s scope, or outside git, **fails loudly at setup** rather than
   silently passing every run.
9. Every new check is **mutation-verified**: the specific test reds under a logic mutant, and assertions
   are POSITIVE wherever a `-Not -Match` could pass vacuously.

## 8. Open forks — for the owner
- **Store granularity:** one file per rule (assumed above) or themed files? The source system chose themed
  and has held at 95 files; one-per-rule makes §4.1 sharper.
- **Where the store lives** in the repo, and therefore whether `.mlc.toml`'s scope needs widening.
- **Who selects the projection** — curator, ranking, or maintainer — and against what budget.

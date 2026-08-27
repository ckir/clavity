# GROWTH knowledge tiering — design

**Status:** SPEC **v8.** v1–v5 were an *accounting gate*, rejected five times (32 findings). v6–v7 are
tiering, rejected twice more (10 findings). **42 findings, seven rounds, none clean.** v8 folds round 7.
**Round 8 not yet run.**

## Standing constraints, in priority order
1. **KNOWLEDGE MUST BE PRESERVED — nothing lost.** ✅ **OWNER-RULED 2026-08-27: reading (a), NEVER
   DESTROYED.** An archive satisfies it; knowledge need not be in the agent's context at all times. This
   **validates the tiering shape** — under reading (b) tiering would have been wrong regardless of quality.
2. **MINIMAL TOKEN SPENDING** — the injected block is charged every session; the drain's context and
   output are charged every run.

**v8 cost against constraint 2:** injected bytes go DOWN (GROWTH becomes a selected projection). The one
addition is the **store INDEX** as a curator input — bounded at one line per rule, ~18 lines today. That is
deliberate, and §5.2 explains why it is the smallest thing that fixes a blindness the design otherwise
reintroduces.

---

## 0. 🔴 THE ROOT CAUSE OF FIVE REJECTED VERSIONS
**GROWTH is currently BOTH the store AND the projection.** If the only copy of a rule *is* the thing
regenerated wholesale, every regeneration is a potential loss, and the only defence left is auditing the
regeneration. All 32 accounting findings were downstream of that. **The fix is not a better audit; it is
to give the projection a store to be a projection OF.**

## 1. The pattern, the porting error, and one retraction

v6 ported the memory-index pattern — tier 1 bounded and always loaded, tier 2 unbounded and on demand,
compaction = relocation with a pointer. **MEASURED: tier 2 is 96× tier 1** (2,320,862 B / 24,400 B),
eleven compactions, **no ledger** — its guarantee is *reachability*.

🔴 **RETRACTED IN ROUND 8 — an earlier draft wrote "eleven compactions, NO FACT LOST" as if MEASURED.
It was not, it could not be, and it is FALSE.** Two independent reasons:
- The source has **no git history** (established in the same paragraph), so there is **no baseline to diff
  against**. A zero-loss claim over eleven manual compactions is not measurable there, by construction.
- **The artifact I was citing records the opposite on its face.** Its own banner says earlier compactions
  *"orphaned 28 files that way, one of them Task 4's own design record."*

**So the source system HAS lost facts, and it says so in the text I quoted from.** The byte ratio was
genuinely measured; the preservation guarantee was confidence dressed as data — the same error class as
§1.1's circular corroboration, in the same document, found one round later.
⚠ **What the pattern actually demonstrates is a bounded index with an unbounded store at 96×. It does NOT
demonstrate zero loss, and this design must not lean on it as if it did** — which is precisely why §3
puts preservation on **git** rather than on the ported pattern.

Round 6: **coordinated deletion defeats reachability.** Remove a file *and* its pointer and both checks
pass. So I measured the source: 🔴 **the memory directory is NOT A GIT REPO** — no history, no recovery.
**It has the identical hole**, surviving only because a human edits it incrementally.

> **The porting error: I copied a pattern whose safety rests on a property the target lacks — careful
> incremental human editing — and left behind the property the target HAS: git.**

### 1.1 🔴 RETRACTED IN ROUND 7 — a claim of independent corroboration that was circular
An earlier draft cited our `commonmemory` plugin and the peer's self-report as *"two independent sources
… stronger than either alone."* **False.** Verified two ways: `agy plugin list` shows `commonmemory`
imported into the peer with `components:[skills]`, and **the peer disclosed the provenance in the very
reply being quoted** — *"I know this because these facts are explicitly stated in my system rules and
loaded skills (`commonmemory`)."*

**One source wearing two hats.** The disclosure was in hand and was characterised as independence anyway.

**What survives, weaker and sufficient:** `commonmemory/skills/commonmemory/SKILL.md:19` states
*"agentmemory is append-mostly, so superseded notes linger"* — a **first-party** statement about a store
we depend on. Enough to exclude it as a preservation tier; **not** evidence of independent confirmation.
⚠ Genuinely independent evidence needs a source that has never read our plugin. None obtained.

### 1.2 Why `agentmemory` is not the store — and why git's retention is NOT the same flaw
`agentmemory` is append-mostly, its bound is unknown to its own users, and the peer could not confirm its
deletions are recoverable. It fails constraint 1(a) as a preservation tier.

🔴 **Round 7 objected that git is "append-only without consolidation" too, so rejecting one while relying
on the other is self-contradictory. The distinction is real and v7 failed to state it:**

> **Accretion only harms when it pollutes the READ path.** `agentmemory` retrieval returns several
> contradictory states and the reader must deduce which is current — the dilution its own users report.
> A git **checkout returns exactly one state**; history is never queried for current state. Git accretes
> in a place nothing reads by default. That is the whole difference, and it is why one is a preservation
> tier and the other is not.

⚠ Not a criticism of `commonmemory`: that plugin serves cross-agent **handoffs**, where a convention over a
shared append-mostly store is right and staleness is tolerable. This serves the **driver-rule corpus**,
where preservation must be mechanical. Different purpose, different substrate; do not merge them.

## 2. The model
- **THE STORE — tier 2, never injected, unbounded, IN THE REPO UNDER GIT.** Every rule earned lives here
  permanently, projected or not.
- **THE STORE INDEX — one line per rule**, committed, maintained incrementally, and **an input to the
  curator** (§5.2).
- **GROWTH — tier 1, injected every ask, capped.** A *selected projection*. **It carries no pointers**
  (§4.3).
- **The inbox** is upstream: raw observations awaiting distillation.

**A rule absent from GROWTH is not gone. It is not currently projected.**

## 3. The guarantee
> **Preservation is a property of the STORE PLUS VERSION CONTROL.** The store is in git; every prior text
> is in history; **deleting a store file is a gate failure**; consolidation edits CONTENT freely.

This closes coordinated deletion mechanically and without a ledger — topology cannot see a synchronised
removal, git can, because the file existed at the baseline and does not now.

## 4. The checks
⚠ MEASURED 2026-08-27 against a fixture with known ground truth:

| condition | `mlc` v1.2.0 | usable? |
|---|---|---|
| link → missing file | `[Err]`, **exit 1** | ✅ gate it |
| file nothing links to | **reports nothing** | ❌ opposite direction |
| `[[wikilink]]` | `[Warn]`, unresolved | ❌ invisible to it |

### 4.1 Deletion — git baseline
A store file present at the baseline and absent now **fails**, named. To retire a rule you edit its
content; you do not delete its file.

### 4.2 🔴 CONTENT OBLITERATION — round 7, and §4.1 alone does NOT catch it
*"A curator can consolidate a 50-line safety rule down to a single useless word… the gate reports perfect
health while the knowledge is functionally obliterated."* Correct: §4.1 guards the **filename**, `mlc` the
**link**, the orphan sweep the **reference** — none guards the **content**.

**The check, and it is a SHAPE test, not a judgement:** a store file whose content shrinks by more than a
set fraction against the baseline **must match the superseded-stub template** — it must carry a
`> Superseded by [<title>](<slug>.md)` line, or an explicit `> Retired: <reason>`. A rule gutted to
gibberish **fails**; a rule deliberately reduced to a declared stub **passes**.

⚠ This deliberately does not ask whether the *remaining* text is any good. It asks whether a large removal
**declared itself**. That is mechanical, and it is the most this class of gate can honestly do.

### 4.3 Dangling pointers and orphans
🔴 **The store MUST use standard `[text](rule.md)` links, not `[[wikilinks]]`** — mlc cannot resolve them,
so a wikilink store is **invisible to its own gate**.
⚠ **Read mlc's exit code directly.** Measured: `mlc . | tail` reported 0 while mlc exited 1 — `$?` was
`tail`'s. The repo's standing trap, which bit inside this very measurement.
Orphans need a complement (~10 lines): enumerate store files, enumerate linked targets, fail on the
difference. **GROWTH carries no pointers** — a curator denied the store listing cannot emit filenames for
files it cannot see. Reachability comes from the store index.

### 4.4 The infrastructure exists; this wires it
`mlc` **is** declared, `just check-links` **exists**, `.mlc.toml` **exists** — but wired into **neither
lefthook nor CI**, so it fires only when someone remembers. 🔴 `.mlc.toml` ignores gitignored paths, so
**a store under one would be invisible to the gate meant to protect it** — the same shape as
`check-growth-budget.ps1` reading repo paths while the breach was in the runtime files. **Site the store
inside the gate's scope and inside git.**

## 5. The write path — round 7 called it unbuildable; this is the fix

### 5.1 🔴 THE CURATOR EMITS ONE FILE. A SCRIPT DOES THE MULTI-FILE WRITES.
Round 7: v7 demanded dynamic multi-file CRUD — mint slugs, create files, edit in place, update an index,
emit GROWTH — *"from a curator whose script handles the wholesale regeneration of a single file."*
Correct, and the fix is to stop asking:

- **The curator emits a single PROPOSAL file** — the artifact shape it already produces reliably.
- **A deterministic script applies it**: creates `<slug>.md`, edits existing rule files, updates the index,
  writes GROWTH. Slug minting, file creation and index maintenance are **mechanical** and belong in code.
- This mirrors the drain's existing split — the curator writes proposal files, `accept-drain` publishes —
  so it adds no new architectural pattern.

### 5.2 🔴 THE STORE INDEX IS A CURATOR INPUT — otherwise the design reintroduces its own worst bug
Round 7: the store is *"never injected"*, so the curator never sees it; **once a rule leaves GROWTH the
selector is blind to it and can never re-select it.**

🔴 **That is the SAME defect as the blind-overwrite bug fixed in `ad3c454`** — where the curator was told
to overwrite a GROWTH it had never been shown — **reintroduced one tier down. Missing it twice is the
finding**, and it is why §7 asserts re-selection end to end rather than trusting the prose.

**Fix, at the smallest scale that works:** the curator is given the **store INDEX** — one line per rule,
~18 lines today — never the store contents. It can then re-select any rule, and read that rule's file on
demand. Constraint 2 is respected because the index is bounded by rule *count*, not rule *size*.

### 5.3 Lifecycle
- **Enters:** proposal → script creates `<slug>.md`, adds one index line.
- **Changes:** proposal → script edits in place. A merged rule becomes a **declared superseded stub that
  keeps its link** (§4.2); the file is never removed (§4.1).
- **Leaves GROWTH:** by not being selected. No event, nothing to check.
- **Leaves the store:** it does not.

## 6. What v8 deletes from earlier designs
The whole accounting apparatus — dispositions, verbatim blocks, per-entry binding, census, departure
bounds, run-id baselines, drain/accept placements — plus v6's false "nothing overwrites" axiom and v7's
false claim of independent corroboration.

## 7. Acceptance criteria
1. A store file present at the baseline and deleted now **fails**, named.
2. Deleting a store file **and** its index pointer together **still fails** — the coordinated deletion that
   defeated v6.
3. A rule gutted to a fraction of its baseline size **without** a declared stub marker **fails**; the same
   reduction **with** the marker **passes**.
4. A pointer to a non-existent rule **fails** `mlc`, wired to read **mlc's own exit code**, proven by a
   test that pipes it and shows the code is masked.
5. A store in `[[wikilink]]` style **fails** — the gate must see its own subject.
6. A store file nothing links to **fails** the orphan sweep.
7. GROWTH regenerated with **any** subset of the store passes: selection is never an error.
8. A rule dropped from GROWTH in one drain can be **re-selected in the next** — asserted end to end,
   because this is the blindness §5.2 exists to prevent and it has been reintroduced once already.
9. A curator proposal naming a slug that collides with an existing rule **fails in the script**, never
   silently overwriting.
10. A store sited outside `.mlc.toml`'s scope, or outside git, **fails loudly at setup**.
11. Every new check is **mutation-verified**: the specific test reds under a logic mutant, and assertions
    are POSITIVE wherever a `-Not -Match` could pass vacuously.

## 8. Open forks — for the owner
- **The shrink fraction in §4.2.** Measure it against real consolidations rather than guessing — too tight
  and every legitimate merge trips it, too loose and gutting passes.
- **Store granularity:** one file per rule (assumed) or themed files? The source system chose themed and
  has held at 95 files.
- **Where the store lives**, and whether `.mlc.toml`'s scope needs widening to reach it.
- **Who selects the projection** — curator, ranking, or maintainer — and against what budget.

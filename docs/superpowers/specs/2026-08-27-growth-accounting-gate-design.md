# GROWTH knowledge tiering — design

**Status:** SPEC **v6.** v1–v5 were all REJECTED (rounds 1–5, 32 findings) and all five were the same
artifact: an **accounting gate**. v6 deletes that idea entirely. **Round 6 not yet run.**

**The redirect is the owner's:** the memory index already solves this exact problem in production — bounded
tier 1, unbounded tier 2, nothing lost — and it does so **without any ledger**. v6 ports that pattern.

## Standing constraints, in priority order
1. **KNOWLEDGE MUST BE PRESERVED — nothing lost.** It cannot be implemented, only earned.
2. **MINIMAL TOKEN SPENDING** — the injected block is charged every session; the drain's context and
   output are charged every run.

**v6 cost against constraint 2: injected bytes go DOWN, not up.** GROWTH becomes a *selected projection*
rather than the store, so it is bounded by choice rather than by a cap it keeps hitting. Everything else
lives in files that are never injected. There is no verbatim-block output cost, because there are no
accounting entries.

---

## 0. 🔴 THE ROOT CAUSE OF FIVE REJECTED VERSIONS, NAMED

**GROWTH is currently both the store and the projection.** That conflation is why every version had to
defend it so hard: if the only copy of a rule is the thing being regenerated wholesale, then every
regeneration is a potential loss, and the only defence left is to audit the regeneration.

Five rounds of findings were all downstream of that one design error. **The fix is not a better audit. It
is to give the projection a store to be a projection OF.**

### The pattern being ported, with its production numbers
| tier | role | bounded? |
|---|---|---|
| `MEMORY.md` | always loaded; pointers + live state only | **hard cap, 24,400 B** |
| topic files | detail, loaded on demand | unbounded — **2,320,862 B across 95 files** |

**Tier 2 is 96× tier 1.** The index has been compacted eleven times and has never lost a fact, because
compaction there means **relocation down a tier, leaving a pointer** — never deletion.

🔴 **And its guarantee is not an account. It is REACHABILITY.** The index verifies one thing: that nothing
has become unreferenced. There are no dispositions, no verbatim ledgers, no per-entry binding — the
apparatus five versions of this spec kept failing to make sound.

## 1. The model
- **The STORE (tier 2, never injected, unbounded):** durable rule files. Every rule earned lives here,
  permanently, whether or not it is currently injected.
- **GROWTH (tier 1, injected every ask, capped):** a *selected projection* of the store — the rules worth
  spending session tokens on right now, plus pointers.
- **The inbox** is upstream of both: raw observations awaiting distillation into store rules.

**A rule absent from GROWTH is not gone. It is not currently projected.** That single sentence dissolves
`dropped`, `merged`, `superseded`, demotion, ping-pong, legacy deadlock, count-neutrality, hashes,
ordinals, target verification, per-entry binding and verbatim output cost — **all 32 findings become moot
rather than fixed**, because none of them describes a real event any more.

## 2. The guarantee
> Every rule in the store is **reachable**. Nothing is verified about what GROWTH chooses to project.

Preservation is a property of the **store**, which nothing overwrites. Selection is a property of
**GROWTH**, which is regenerated freely — which is what made wholesale regeneration desirable in the
first place, and it is now harmless.

## 3. The checks — two DIFFERENT directions, and only one is off-the-shelf

⚠ MEASURED 2026-08-27 against a fixture with known ground truth, because the tool's actual behaviour
decides the design:

| condition | `mlc` v1.2.0 | usable? |
|---|---|---|
| link → **missing file** (dangling pointer) | `[Err] Target filename not found`, **exit 1** | ✅ gate it |
| file that **nothing links to** (orphan) | **reports nothing at all** | ❌ opposite direction |
| `[[wikilink]]` | `[Warn] Markdown reference not found` — unresolved | ❌ invisible to it |

### 3.1 Dangling pointers — `mlc`, gated on exit code
The index or GROWTH promises a rule that does not exist. `mlc` exits **1**; wire it as a gate.

🔴 **THE STORE MUST USE STANDARD MARKDOWN LINKS `[text](rule.md)`, NOT `[[wikilinks]]`.** Measured above:
mlc cannot resolve `[[...]]` and merely warns. A store written in wikilink style is **invisible to its own
gate** — the shape of a guard that certifies what it never checked.

⚠ **Read mlc's exit code directly, never through a pipe.** Measured: `mlc . | tail` reported exit 0 while
mlc itself exited 1 — `$?` was `tail`'s. This is the repo's standing "run the gate, read ITS exit code"
trap, and it bit inside this very measurement.

### 3.2 Orphans — a complement, ~10 lines, because `mlc` does not do this
`mlc` validates that pointers resolve. It says nothing about a file nothing points at, and **an
unreachable rule is exactly what "lost" means here.** The complement: enumerate store files, enumerate
linked targets, report the difference. Fail on non-empty.

This is not new machinery — it is the check already run by hand when compacting the memory index, where
it found that a topic file had **exactly one inbound link**, so cutting one line would have orphaned a
whole design record.

### 3.3 The infrastructure ALREADY EXISTS — this wires it, it does not build it
⚠ **Correcting my own claim in an earlier draft of this section**, which said mlc was undeclared. It was
written from a `head -12` of a **14-entry** manifest — a positional-truncation error, the same class this
repo has logged before. The facts, re-measured:

- `mlc` **is** declared in `.claude/recommended-tools.json` (`cargo install mlc --locked`).
- `just check-links` **exists** and runs `mlc` config-driven.
- `.mlc.toml` **exists**, scoped to *"TRACKED PRODUCT DOCS ONLY"* with a deliberate ignore list, because
  *"a link error in those is noise that would train us to ignore the whole report."*

🔴 **But it is wired into NOTHING** — measured: `check-links` appears in neither `lefthook.yml` nor any CI
workflow. It is a manual recipe, so today it catches a dangling pointer only when someone remembers to run
it. Wiring the existing recipe is the work; building a checker is not.

🔴 **AND THE STORE MUST FALL INSIDE `.mlc.toml`'s SCOPE.** That config deliberately ignores gitignored
working artifacts. **A store placed under a gitignored path would be invisible to the very gate meant to
protect it** — the same shape as `check-growth-budget.ps1` reading repo paths while the breach was in the
runtime files. Choose the store's location against the gate's scope, not after it.

## 4. 🔴 THE HONEST DISANALOGY — where the ported pattern does NOT reach
`MEMORY.md`'s tier 2 works because **a reader chooses to follow a pointer**. The golden header is injected
**blind**; there is no follow step.

And measured this session across 22 blind driver instances: **11 of 12 ignored a rule that was literally
present in the context window.** A pointer is strictly weaker than presence.

**So tiering solves PRESERVATION completely and does NOT solve PRESENCE.** That is acceptable only under
reading (a) of constraint 1 — *never destroyed* — and not under reading (b) — *always available to the
agent*. **The owner has not yet ruled between them**, and v6 assumes (a). If (b) is meant, v6 is the wrong
design and the answer is a bounded curated tier the curator reads, not a pointer.

## 5. What this deletes
The entire accounting apparatus: dispositions, verbatim blocks, per-entry binding, the census, the
per-drain departure bound, run-id baselines, drain-time and accept-time placements. **None survives,
because none has anything left to check.**

## 6. Acceptance criteria
1. A store file nothing links to **fails** the orphan check, named.
2. A pointer to a non-existent rule **fails** `mlc`, and the wiring reads **mlc's own exit code**, proven
   by a test that pipes it and shows the code is masked.
3. A store written in `[[wikilink]]` style **fails** — the gate must be able to see its own subject.
4. GROWTH regenerated with any subset of the store passes: **selection is never an error.**
5. A rule removed from GROWTH but present in the store passes — the case five versions treated as a loss.
6. A rule removed from the STORE with no relocation **fails**.
7. Every new check is **mutation-verified**: the specific test reds under a logic mutant, and assertions
   are POSITIVE wherever a `-Not -Match` could pass vacuously.

## 7. Open forks — for the owner
- 🔴 **Reading (a) vs (b) of constraint 1.** Everything above assumes (a). This is now the only question
  that can invalidate the whole design, and it is unruled.
- **Store granularity:** one file per rule, or themed files as the memory dir uses? The memory dir chose
  themed and it has held at 95 files.
- **Who selects the projection** — the curator, a ranking, or the maintainer — and against what budget.

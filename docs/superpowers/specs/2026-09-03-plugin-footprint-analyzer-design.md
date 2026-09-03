# Plugin footprint analyzer — design spec

> **Status:** SPEC, not a plan. The analyzer does not exist, so this document carries intent, contracts
> and open forks — **no line numbers into code that has not been written**. The line-level plan is owed
> only once §23 has shipped and this spec has been reviewed.

**ROADMAP item:** `clavity-dotnet/ROADMAP.md` §26, owner-accepted 2026-09-03.
**AGY-FIRST consult:** `.clavity/seams/agyfirst-footprint-analyzer.md`.

---

## Goal

Make the cost of installing one of this repo's plugins **visible to two different readers**, from one
measurement pass:

1. **The maintainer**, who needs a gate that fails when a change ships more than it should.
2. **A stranger reading the repo**, who needs to judge the cost *before* installing.

## The thing that makes this non-trivial

**Those two readers do not want the same number**, and the peer's sharpest contribution was refusing to
let them share one. To a maintainer, bloat is bytes on disk. To a prospective installer, "usage cost"
means context the agent pays for. Publishing the former as the latter is the failure mode: a reader who
sees `348 KB` divides by four, concludes the plugin permanently eats a large slice of their context
window, and declines — on a number that is true and irrelevant.

**The owner's ruling resolves this with a vector rather than a choice.** One analyzer, one discovery
pass, three fields; each consumer reads the field it needs.

---

## The metric vector

| field | what it means | who reads it |
|---|---|---|
| **always-injected** | bytes that enter an agent's context **every session**, before the user does anything | README (the headline "cost of having it installed") |
| **on-invoke** | bytes a single skill adds **when it fires**, reported per skill | README (so a reader can see the tail, not just the floor) |
| **on-disk** | bytes the installer copies | the maintainer gate |

**These are BYTES, deliberately.** A token count is a claim about a tokenizer this repo does not own and
cannot pin; it would go stale on a vendor change with nothing to detect it. The README states bytes and
names the caveat rather than converting.

### What belongs in "always-injected" — TO BE VERIFIED, NOT ASSUMED

The composition below is the current best understanding and **every row is a claim the plan must confirm
by measurement before any number is published.** Getting this set wrong is the one error that makes the
whole exercise worse than nothing, because it publishes a confident wrong figure.

- SessionStart hook output — the injected knowledge header (SEED + GROWTH), already capped at 32.768 B
  by `check-growth-budget.ps1` to match `GoldenHeader.MaxBytes`.
- Skill **frontmatter** — each skill's name and description appear in the agent's skill listing; the
  **body does not** until invoked. This split is the whole reason `on-invoke` is a separate field.
- MCP tool descriptions and server instructions. **This is the row a naive analyzer misses.**
  `scripts/injected-context-ignore.txt:37-45` records that `ghidrust/crates/ghidrust-mcp/src/tools.rs`
  holds 19 `pub const DESC_*` blocks — roughly 12 KB — *"that MCP delivers to EVERY agent via
  tools/list"*, and that it is deliberately outside the injected-context gate because auditing it for
  the ASCII invariant would red-gate correct content.

**Exclusion is a claim too.** Anything the analyzer leaves out must be listed in its output with the
reason, so a reader can see the perimeter rather than inferring completeness from a total.

---

## Discovery: extend, do not add a second walk

`scripts/check-injected-context.ps1` already walks the injected surface and its discovery is
**SUBTRACTIVE by deliberate design** — domain roots minus an explicit ignorelist — because an additive
allowlist of globs was the exact defect that gate exists to remove. Its own header says so.

**The analyzer reuses that discovery rather than reimplementing it.** Two walks would drift, and the one
that drifts is the one nobody runs. Where the analyzer needs a file the ignorelist excludes for an
unrelated reason — `tools.rs` is excluded for an *encoding* invariant, not because it is uninjected — the
correct resolution is to separate the two concerns, not to fork the walk. **How to separate them is an
open fork (F1 below).**

---

## Per-product, not repo-wide

This repo hosts five products. A single repo-wide footprint would be a number no installer can act on,
because nobody installs the repo. **The unit of measurement and of publication is the product** —
`clavity-dotnet`, `clavity-classic`, `ghidrust`, `agy-autotrain`, `commonmemory`.

---

## Output contract

**One machine-readable artifact, one generated prose block.** The analyzer's own output is structured;
the README block is rendered from it. Nothing downstream re-derives a number from prose.

### The README block is GENERATED and GATED

Hand-maintained figures rot here — measured, twice, in this repository: four `(N lines)` claims in the
ROADMAP were simultaneously wrong, and a suite-count table silently reverted to describing an *installed*
copy rather than the repo. Neither was noticed by a reader; both were caught by a gate.

So:

- the analyzer writes the block between explicit begin/end markers;
- a checker recomputes and **fails the build on drift**, in the shape `check-roadmap-claims.ps1` already
  uses for `(N lines)` claims and closure SHAs — that machinery is the precedent, and its existence is
  why this half is cheap rather than a new parser;
- **hand-editing the block becomes a red build, not a silent lie.**

### The maintainer gate

Reads `on-disk` and fails when a product exceeds its budget. The budget is a committed number with a
recorded rationale, in the shape the three existing budget gates already use.

⚠ **The gate must fail CLOSED.** A footprint gate that cannot find a file, cannot parse the ignorelist,
or measures zero bytes must FAIL rather than report a comfortable number — a size gate that silently
measures nothing certifies exactly what it stopped checking.

---

## What this does NOT claim

- **Not a token count.** Bytes only; the conversion is the reader's, and the caveat is stated.
- **Not a performance measurement.** Nothing here says what the plugin costs in latency or spend.
- **Not proof the numbers are complete.** The output states its own perimeter and its exclusions; a
  total with an unstated exclusion list is the misleading shape this spec exists to avoid.
- **Not a substitute for the three existing budget gates.** Those cap specific artifacts against limits
  the binaries enforce. This aggregates and publishes; it does not replace them.

---

## Open forks — for the owner, at plan time

**F1. How to reconcile `tools.rs` with the ignorelist.** It is excluded from `check-injected-context` for
an *encoding* reason while being genuinely always-injected. Options: split the ignorelist into
per-invariant lists; add a per-file invariant exemption so the file can be in the domain but out of the
ASCII check; or have the analyzer carry a small explicit list of injected-but-exempt files, which
reintroduces the additive-allowlist defect the subtractive design removed. **Not resolved here.**

**F2. Where the published block lives.** The umbrella `README.md`, each product's own README, or both.
Both means one generated block per product and a summary table upstream — more surface for the gate to
keep true.

**F3. What the on-disk budget numbers should BE.** Deliberately unset. A budget picked before the first
measurement is a guess; the plan should measure, then propose numbers with headroom and a rationale.

**F4. Whether `on-invoke` is published per skill or as a range.** Per skill is honest and long; a
min/median/max range is readable and hides the outlier that matters.

---

## Sequencing

**Build after §23 ships.** §23 is planned, panel-GREEN and ready to execute; finishing it closes Phase 1
of the approved implementation sequence. This item is Phase-3-adjacent work and its ROADMAP entry records
the deferral.

## Review status

🔴 **This spec has NOT been reviewed.** AGY-AFTER is owed on it before a line-level plan is written. The
AGY-FIRST consult that produced the ruling above is not that review — it decided the fork; a panel tests
the artifact.

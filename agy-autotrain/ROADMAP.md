# agy-autotrain - ROADMAP

Enhancement backlog for the agy-autotrain plugin (the thin, driver-composed agy learning loop:
`agy-learn` capture -> inbox; `agy-curate` offline drain -> the machine-wide golden-header GROWTH region).

Other planning surfaces already exist and are NOT replaced by this file: the external cohesive-distribution
design spec (a LOCAL, gitignored artifact under `docs/superpowers/specs/`, referenced by section -numbers,
and absent from a fresh clone by design), the
`CHANGELOG.md` (shipped changes), and `docs/fix-the-tool-backlog/` (tool *defects*). This file holds
*enhancement* tasks that fit none of those - one heading per task, newest first.

> **Architectural guardrail (do not violate).** agy-autotrain is deliberately being **thinned** - it does NOT
> own the SEED it injects (the driver plugins do), and capabilities migrate OUT to the drivers, not IN.
> Enhancements here must protect the thin / EXTEND model, never graft standalone-product lifecycle features
> onto it. Reaffirmed by an **AGY-FIRST design consult (2026-07-17)**: the divergence from the sibling
> flaui-mcp plugin is intentional and healthy - port only mechanisms that *mechanically protect* the thin
> architecture; do not "upgrade to match" a standalone product.

---

## AT-2 - Durability for the *accumulated* observations inbox (the one artifact with no recovery path)

**Status:** [x] **SHIPPED AND CLOSED 2026-08-02** - capstone GREEN over `6d79bee..a0b2d7b`, recorded in
`docs/agy-capstone-ledger.md`. Verified 2026-08-06: the deliverable `agy-autotrain/hooks/agy-inbox-snapshot.sh`
ships, is registered, and carries a 22-test suite (`scripts/tests/agy-inbox-snapshot.Tests.ps1`, slow half).
The last commit to touch it, `a0b2d7b`, is the very tip that capstone reviewed.
**This heading read "open, needs brainstorming" for four days after it closed.** The brainstorm it was
waiting for happened, the fork below was settled, and the work shipped - everything from here down is the
RECORD of that, not an open question. ~~**Opened:** 2026-07-30~~
[!] **The options/fork sections below are preserved deliberately** - they are why the chosen design looks the
way it does, and the AT-2 capstone's round-1 GREEN was FALSE (a total-data-loss defect was found by hand
afterwards), which is the kind of thing worth being able to re-read.

**Provenance.** Surfaced while driving an unrelated subproject in the sibling `flaui-mcp` repo (2026-07-30).
The driver was asked whether the *capture* skills protect knowledge against `/compact` and power failure, and
measured the answer per store. `flaui-mcp`'s inbox came out fine. This one did not, and the difference is
structural rather than incidental - which is why it belongs here as a task rather than as a note.

### The gap, with measurements (2026-07-30, this machine)

The inbox exists in **two different places that are easy to conflate**, and only one of them is protected:

| | path | protection |
|---|---|---|
| **Shipped seed** | ~~`knowledge/agy-observations.md` in THIS repo~~ **RETIRED at 14g** | the inbox is user-local at `~/.clavity/agy-observations.md`; nothing seeds it |
| **Accumulated inbox** | `%LOCALAPPDATA%\Programs\agy-autotrain\plugins\agy-autotrain\knowledge\agy-observations.md` | **in no git repo at all** |

The accumulated copy is the one with the value: **51.0 KB, 48 pending entries** at time of writing, against a
curate threshold of 8. Every `agy-learn` capture appends *there*. It has no version control, no history, and
no off-machine copy - so there is no way to recover a truncated write, an accidental deletion, or a bad edit
by an agent, and no way to see what an entry said before someone rewrote it.

**Compare the sibling loop, which is fine:** `flaui-mcp`'s `.claude/flaui-mcp/observations.md` lives INSIDE
the project repo, tracked and not ignored, so every capture is one `git add` from durable. The asymmetry is
not an oversight in either design - it follows from agy-autotrain's inbox being **machine-wide** (it must
outlive any single project) while flaui-mcp's is **project-scoped**. Machine-wide is the right call; it just
leaves this artifact outside every repo boundary that would otherwise protect it.

### What ALREADY protects it - do not rebuild this

The installer is not naive here, and any proposal must start from what it already does
(`installer/agy-autotrain.iss`):
- `agy-observations.md` is **excluded from the blanket copy** and seeded separately with
  `onlyifdoesntexist`, precisely so an upgrade cannot replace accumulated observations with the shipped
  template (`:31-41`, `:54`, `:60`). The comments there state the failure mode in as many words.
- An uninstall path warns about *"observations captured but not yet drained"* (`:127`) and there is
  inbox-file handling around `:148-153`, including a deliberate note that renaming the inbox to `.backup`
  would drop it from the injected set.
- A `agy-observations.md.preinstall-backup` exists on this machine.

**So the install/upgrade vector is covered.** The uncovered vectors are everything else.

### Why that is still insufficient - the specific weaknesses

1. **Single slot, overwritten.** One `.preinstall-backup`, replaced by the next install. There is no history,
   so a bad state that survives one install cycle silently overwrites the last good copy.
2. **Measured staleness right now:** the backup is **22.4 KB** against a live **51.0 KB** inbox. Roughly
   **28.6 KB of observations - more than half the corpus - exist in exactly one file on one disk.**
3. **Co-located with what it protects.** The backup sits in the same directory as the original, so it shares
   its fate under directory deletion, disk loss, or a bad recursive operation.
4. **Only the install vector triggers it.** Nothing snapshots on the events that actually happen day to day:
   an agent truncating the file, a botched `agy-curate` drain, an editor writing a partial file, ordinary
   disk failure.
5. **`agy-curate` is destructive by design** - it drains the inbox. A curate run that goes wrong mid-drain
   has no "before" to compare against, which also makes curate mistakes unauditable after the fact.

### Tested against the guardrail (this is the crux of the brainstorm)

The architectural guardrail at the top of this file forbids grafting **standalone-product lifecycle
features** onto a plugin that is deliberately being *thinned*. A general backup/restore/retention subsystem
is exactly such a feature, so **the obvious answer is probably the wrong one.** The interesting question is
whether durability can be bought **without** owning a lifecycle - for example by making the inbox live
somewhere already version-controlled, rather than by teaching this plugin to manage copies.

### Options to weigh (none chosen - this needs an AGY-FIRST consult before it is specced)

- **A - Relocate the inbox into an existing user-owned repo.** Keep the machine-wide scope but put the file
  somewhere the user already versions (a dotfiles repo, or `%USERPROFILE%\.claude\`), leaving a pointer
  behind. *Cheapest to reason about and adds no lifecycle to the plugin - most consistent with the
  guardrail.* Costs: an install-time path decision, a migration for existing users, and it assumes the user
  HAS such a repo.
- **B - `git init` the knowledge directory itself, and have `agy-curate` commit.** Turns every drain into a
  reviewable diff and makes curate mistakes recoverable. Costs: the plugin now owns a repo lifecycle - read
  the guardrail carefully before choosing this, and note it also gives the plugin a second, private history
  that no one will ever look at unless something breaks.
- **C - Rotating pre-drain snapshots (N deep) written by `agy-curate`, not by the installer.** Directly
  targets the destructive operation rather than the install vector. Cheapest to implement; still a retention
  policy, i.e. still lifecycle, and still co-located unless the target directory is elsewhere.
- **D - Do nothing, and say so out loud.** Document the exposure in the README so it is a known accepted
  risk rather than an unexamined one. Legitimate if the corpus is judged cheap to re-accumulate - but note
  that it is explicitly NOT cheap: entries are earned from live sessions, several encode failures that cost
  real money to learn, and by design they exist nowhere else.

### Open questions for the brainstorm

1. Is the inbox the only unprotected machine-wide artifact, or does the compiled **golden-header GROWTH
   region** (the actual output of the loop) have the same exposure? Check before scoping - if both, the
   answer should cover both, and the GROWTH region may matter more since it is what reaches agy's context.
2. Does the sibling `clavity` / driver plugin family already solve this for a machine-wide store? If a
   mechanism exists there, **extending** it is in-model where inventing one here is not.
3. Should durability be `agy-curate`'s job (it is the destructive step and already runs offline) or the
   installer's (it already has file-lifecycle logic)? Splitting it across both is how the current partial
   protection ended up misleading.
4. What is the actual recovery *story*? A backup nobody knows how to restore from is theatre - whichever
   option wins needs one documented sentence saying how a user gets their observations back.

---

## AT-1 - Context-pollution hardening for `agy-curate`'s GROWTH region

**Status:** ~~open~~ -> **KILLED 2026-08-06 (both parts)** * **Opened:** 2026-07-17 *
**last-triaged: 2026-08-06** (open-work reconsideration sweep, Phase 1 Task 3)

**Part A - KILLED on clause 1 and clause 2 of the disposition bar.** Measured 2026-08-06:
- **Its clause-1 premise no longer holds.** Part A's loss argument is the *silent* GROWTH drop past the
  16 KB cap. **That drop is no longer silent.** `clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs:91` emits
  `"golden-header region at {path} is {len}B, over the {MaxBytes}B cap - skipped"`, and `:80` states
  *"over-cap and sidecar-mismatch both warn and degrade the region to absent."* The callback is wired, not
  null: `AgyView.cs:83` passes `Warn` into `TryReadCombined`, and `AgyView.cs:74` defines
  `void Warn(string m) => _options.Diagnostics.WriteLine($"clavity: {m}")`. **An operator is told.**
- **Clause 2 therefore fails too** - the failure mode is neutralised by an existing invariant, which is
  precisely what clause 2 rejects.
- **Its second half was NEVER A GAP.** Part A asks for *"a single explicit anti-poisoning gate"*, stating
  none exists. One did, before this entry was written: `skills/agy-curate/SKILL.md:250`
  **"Anti-poisoning circuit-breaker. You (the curator) are the gate, not a transcriber..."**, present at
  `c46be48` (2026-07-13) - **four days before AT-1 was opened.**
- **Only the line-density cap is genuinely unbuilt** (zero matches in `SKILL.md` for a line cap or ordered
  breach; `git log -S'line-density'` finds no implementation). It is a quality improvement with a loud
  existing signal in front of it, not a lie, loss or crash.

**Part B - KILLED on clause 3 (unresolved design fork), and it fails clause 1 as well.** Its own text is the
evidence: *"[STOP] GATING ARCHITECTURAL FORK (resolve via AGY-FIRST + user BEFORE building Part B)"*, two
unanswered questions (a) and (b), and *"Do NOT implement Part B until this is decided."* The injection half
*"almost certainly needs clavity-binary support that does not exist - which would violate agy-autotrain's
core 'no binary changes' property"*, which the architectural guardrail above (**"capabilities migrate OUT to
the drivers, not IN"**) forbids. Context pollution is degraded quality, not a false diagnostic - clause 1
is not met either. No implementation commit exists.

[!] **Kept in place, struck through rather than deleted** - the analysis of *why* project-local scoping may
belong on the clavity binary's roadmap instead is the durable part, and killing is cheap because git is the
undo.

**The goal (what "context-pollution avoidance" means here).** The golden-header GROWTH region is prepended to
*every* agy ask, so anything low-value or off-domain that leaks into it silently taxes every future call. This
task hardens agy-curate so only **dense, relevant, decision-changing** rules reach agy's context, along two
independent axes: **volume** (Part A) and **relevance** (Part B). Both mechanisms are ported in spirit from the
sibling flaui-mcp autotrain loop, which evolved a stricter guard than agy-curate has today. An AGY-FIRST consult
(2026-07-17) confirmed these are the *only* flaui-mcp advances worth porting into a thin / EXTEND plugin - see
"Out of scope" for what was deliberately rejected.

### ~~Part A - Volume: line-density cap + ordered breach + explicit anti-poisoning gate~~ * [X] **KILLED 2026-08-06 (clauses 1 + 2)**

**Gap.** In `skills/agy-curate/SKILL.md` the *"Compile + commit the GROWTH region"* section (~:119-141) has only
a **coarse 16 KB combined *byte* cap** whose failure mode is a **silent cliff**: if `SEED + GROWTH` exceeds
16 KB the binary silently degrades to SEED-only, so an over-budget GROWTH is written yet **never injected**. The
only guidance is a soft "keep it lean." Separately, the *Promotion rubric* (~:107-117) gates *entry* quality
(Heuristic >=2 independent observations; Empirical Assumption 100 % verify-harness pass) but there is **no single
explicit anti-poisoning gate**.

**Port** (source: the flaui-mcp repo's plugins/flaui-mcp/skills/flaui-curate/SKILL.md - a SIBLING REPO,
not a path in this one, which is why it carries no code span, its *"USER promote ->
the project-local growth file"* section):
1. A **line-density cap** on the compiled GROWTH region **plus an ordered breach procedure**, placed **in front
   of** the existing 16 KB byte cap so active compression happens *before* the silent-degrade cliff. Adapt the
   exact flaui-curate rule to the GROWTH region (regenerated wholesale each run, prepended after SEED):
   > **HARD CAP: <= N lines.** On breach, in order: (1) compress/merge related rules or supersede an old one;
   > (2) drop the lowest-leverage rule.
2. An explicit **anti-poisoning gate**, in flaui-curate's voice, beside the Promotion rubric so a candidate must
   clear **both** the rubric **and** the gate before entering GROWTH:
   > Anti-poisoning gate: you are the gate; when in doubt, drop it.

**Open sub-decision (do NOT fabricate - decide during implementation).** flaui-curate's cap is **<= 30 lines**,
but that governs a *project-local* file; agy-autotrain's GROWTH is a *machine-wide* header, so re-derive the
budget - e.g. from `16 KB - sizeof(golden-header.seed.md)` at a realistic bytes-per-line - and state the
reasoning.

### ~~Part B - Relevance: project-local learning tier + opt-in promote-to-global~~ * [X] **KILLED 2026-08-06 (clause 3: the gating fork below was never resolved)**

**Gap.** agy-curate promotes *all* learned wisdom into the **one machine-wide** golden-header, which is then
injected into *every* agy ask regardless of what the user is working on. Domain-specific wisdom (e.g. a C#
desktop-automation rule) therefore pollutes unrelated sessions (e.g. Rust backend work) - the largest
context-pollution source, and the one Part A's volume cap does not address. flaui-mcp's shape: **project-local
growth by default** (a per-project capped file) **+ an explicit user-invoked promote-to-global** step for the
rare genuinely-cross-project rule.

**[STOP] GATING ARCHITECTURAL FORK (resolve via AGY-FIRST + user BEFORE building Part B).** For flaui-mcp this is
pure markdown, because its *skill* reads both a project-local and a global growth file. agy-autotrain is
different: the **clavity binary** injects a *single* machine-wide golden-header (`%USERPROFILE%\.clavity\`), and
there is **no per-project injection layer today**. So Part B splits:
- **Capture side (thin, markdown):** a per-project growth file (capped, same anti-poisoning gate as Part A) plus
  a single explicit `agy-promote` skill that copies one rule into the global growth file. This alone is
  in-keeping with the thin model.
- **Injection side (the fork):** actually getting a project-local layer *into agy's context* almost certainly
  needs **clavity-binary support that does not exist** - which would violate agy-autotrain's core "no binary
  changes" property. Questions to settle first: (a) should the binary inject a project-local growth layer atop
  the global header (env/override/CWD-scoped)? (b) if not, a project-local file that never reaches agy's context
  is useless - so is project-local scoping viable for *this* plugin at all, or does it belong on the **clavity
  binary's** roadmap instead of agy-autotrain's? Do NOT implement Part B until this is decided.

### Acceptance

- **Part A:** `agy-curate/SKILL.md` states an explicit line-density cap + ordered breach procedure *ahead of*
  (not replacing) the 16 KB byte cap, and an explicit anti-poisoning gate on GROWTH entry. No binary change, no
  new verb/file; EXTEND model untouched. `CHANGELOG.md` updated.
- **Part B:** only after the gating fork is resolved. If it proceeds, the capture side ships as markdown + an
  `agy-promote` skill; any injection-layer work is tracked separately (likely against the clavity binary).

**Explicitly out of scope** (the divergence is intentional - see the guardrail; reaffirmed AGY-FIRST 2026-07-17):
maintainer-edit-canonical mode; a `status` introspection verb; version lockstep; backlog<->xUnit regression
coupling. **Do NOT port these.**

**Provenance.** flaui-mcp <-> agy-autotrain A/B comparison (2026-07-17); AGY-FIRST consult (agy: Part A "Rank 1 -
best fit"; Part B "Rank 2 - good fit, protects the global header from domain-specific pollution"); the folding
of both into one context-pollution task, and this ROADMAP location, were user-decided. "Token savings" in the
originating discussion = this context-pollution-avoidance logic (NOT the machine-wide `rtk` proxy).

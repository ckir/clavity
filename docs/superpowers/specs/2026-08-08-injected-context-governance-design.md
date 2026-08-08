# Injected-context governance - design

**Date:** 2026-08-08
**Status:** design approved by the owner; implementation plan not yet written
**Origin:** owner concern, 2026-08-08 - *"My concern is scoped to text that hits the agent context. As it
created by several rounds might contain anomalies causing problems to other user's agents."* Widened twice
by the owner into the governing rule: **"If something enters into agent context it gets audited"**, and
**"we audit for anomalies of any kind."**

---

## 1. Problem

This repository ships text that is loaded into a **user's AI-agent context on someone else's machine**:
skill bodies, skill frontmatter descriptions, hook-injected reminders, knowledge manuals, and a seed header
prepended to every peer consult. That text is authored and revised by an AI agent across many review
rounds. Multi-round editing is precisely how a document ends up self-contradictory, half-updated, or
carrying an instruction that no longer matches what ships.

A defect here does not break a build and no existing test catches it. It silently misinstructs somebody
else's agent, in their repository, on their work.

A four-round audit of this surface (2026-08-08) found **10 anomalies**. None was caught by any existing
gate, despite the repository having an ASCII lint, a byte-identity mirror check, two size budgets, and a
committed-code review discipline that put 11 adversarial seats over some of this exact code.

### 1.1 The surface, measured

**Audited (2026-08-08):**

| Surface | Size | When it enters an agent's context |
|---|---|---|
| skill frontmatter `description:` x7 | 2 739 B | **every session, unconditionally** |
| SKILL.md bodies x7 | 96 916 B | on skill invoke |
| `seed/golden-header.md` | 5 133 B | **prepended to every peer ask** |
| `clavity-dotnet/plugin/knowledge/*.md` x2 | 21 411 B | on read |
| hook emitted messages, 8 emitters | ~2 700 B | per firing |

Two hooks are **deliberately out of scope**: `agy-liveness-check.sh` and `agy-anomaly-reminder.sh` emit to
**stderr**, which renders in the user's transcript and never enters the agent's context. Each file's header
comment states this. They are a user-facing surface, not an agent-facing one.

**NOT audited, discovered while scoping this design:**

| Surface | Size |
|---|---|
| `agy-autotrain/skills/` | 24 935 B |
| `agy-autotrain/knowledge/` | 16 387 B |
| `agy-autotrain/hooks/` | 12 590 B |
| `ghidrust/plugin/skills/` | 17 320 B |
| `commonmemory/skills/` | 2 275 B |

**73 507 B of injected context across three products was never enumerated by anyone.** All six markdown
files in it carry non-ASCII characters (295 in total). Whether that is a *defect* there is an open question
(see 6.1) - the ASCII rule is currently justified by mojibake risk through the Inno installer and by
verdict-token integrity, and it is not yet established that all three products ship through that path. The
*structural* point is not in question: enumerating the domain immediately surfaced more of it.

---

## 2. Diagnosis

Two **orthogonal** axes. Both are required; fixing either alone reproduces the bug.

### 2.1 Breadth - which files are visited (explains 8 of 10)

No gate has ever held the charter *"all injected context"*. Every gate is scoped to a **subsystem
whitelist**, so the domain fell between subsystems.

The proof is in the checker built for exactly this purpose. `scripts/check-agy-discipline-skills.ps1:13`
reads:

```powershell
$skills = @('agy-first', 'agy-capstone', 'agy-test-audit')
```

It carries a perfectly good ASCII scanner at `:66`:

```powershell
$nonAscii = [regex]::Matches($raw, '[^\x00-\x7F]')
```

...and that scanner never ran against `seed/golden-header.md`, `knowledge/`, `ls-driving`, `ls-pairing`,
`open-issues`, or any of the three unaudited products. The check was right. Its **scope** was a
hand-maintained list, and hand-maintained lists drift.

### 2.2 Depth - container vs claim (explains the other 3)

Files that *were* enrolled still passed, because the assertion checked the **envelope** rather than the
**payload's veracity**: valid JSON, exit code 0, byte-identical between the two plugin trees, under a byte
cap. None of those asks whether the text is *true*.

`scripts/tests/check-seed-budget.Tests.ps1:31` is the sharpest illustration. It is named *"measures UTF-8
BYTES not characters (multibyte)"*. The authors knew the seed could carry multibyte characters, corrected
the size accounting to handle them, and never asked whether they belonged there at all.

### 2.3 Why both axes are needed

A breadth-only fix produces a suite that visits every file in the domain and asserts each one exists and is
non-empty - another container check, and a false sense of coverage. A depth-only fix produces sharper
assertions still pointed at a stale list.

---

## 3. The evidence - 10 anomalies, and what a gate can actually do about each

Every anomaly below was verified by direct measurement. A peer proposed three of them (C1, C2, C3); the
rest were found by the driver. The **mechanizable** column is the honest per-item census, not an estimate:
the peer initially claimed a static gate closes "8 of 10", and when required to justify it item by item,
conceded **5** (6 with the convention in 4.2).

| # | Anomaly | Location | Mechanizable? |
|---|---|---|---|
| A1 | Rendered message opens `[ASSERTION-STRENGTH] ASSERTION-STRENGTH:` - duplicated tag | `assertion-strength-reminder.sh:145-146` | **YES** |
| A2 | Degraded line uses `[ASSERTION-STRENGTH] guard inactive:`; four siblings use `[AGY-DISCIPLINES] guard inactive:` | `assertion-strength-reminder.sh` | **YES** |
| A3 | States "~80 tokens per firing" as settled; shipped messages measure ~190-212 | `clavity-dotnet/ROADMAP.md:742` | **NO** |
| A4 | The only injected message that imperatively demands open-ended work per firing | `assertion-strength-reminder.sh` | **NO** |
| B1 | Owner ruling of 2026-08-07 (`MAX_CAPSTONE_ROUNDS` 3 -> 6) never shipped; all four files still say 3 | `agy-capstone/SKILL.md:190`, `adversarial-panel-review/SKILL.md:157`, both drivers | **NO** |
| C1 | "See the marker contract doc (Task 5)." - plan-artifact residue; siblings cite the real path | `agy-first/SKILL.md:114` | **YES** |
| C2 | Cites hook `agy-first-brainstorm.sh`; `find` returns 0 matches. Real hook is `agy-seam-inject.sh` | `knowledge/agy-capabilities.md:12` | **YES** |
| C3 | 11 non-ASCII chars on 6 lines, in the file prepended to every ask; **no encoding gate exists for it** | `seed/golden-header.md` | **YES** |
| C4 | Cites "the `agy-test-audit` skill, Step 5"; that file has two numbered lists with an item 5 (`:39`, `:88`) | `assertion-strength-reminder.sh:145` | **CONDITIONAL** (see 4.2) |
| C5 | "Keep the four ` * ` separators." The `printf` eight lines above at `:87` has **three** | `open-issues/SKILL.md:95` | **NO** |

**C1 and C2 ship twice** - the two plugin trees are byte-identical, so each anomaly exists in both.

### 3.1 On C5, the specimen worth keeping

`open-issues/SKILL.md:87` is `- [%s] %s * %s * %s * task=%s` - three ` * ` separators. Line `:95` tells the
reader to keep **four**. An agent that carefully *complies* adds a fourth separator, shifting the field
before `task=` off the date, causing exactly the unreadable-age failure that `:96` warns about in the next
sentence. This is the class of defect that no script will catch and that a reviewer only finds by asking
"what would a reader-agent actually do".

### 3.2 Detection provenance, recorded honestly

The peer found C1, C2 and C3 - all three in files the driver's own first pass had not opened. It also
returned two `[VERDICT: CLEAN]` rounds; one survived probing and one did not (its own below-floor discard
in the clean round was C5, a real defect mis-dispositioned). Its stated coverage number was wrong until
challenged, and one cited constant was wrong (it gave the seed cap as 6000 B; `check-seed-budget.ps1:15`
reads `7992`). **Every peer claim in this document was re-measured by the driver before being written down.**

---

## 4. Design

Four parts. Parts 1 and 2 are code; parts 3 and 4 are decisions about process and scope.

### 4.1 Part 1 - a fail-closed, discovery-based gate

A new Pester suite that **discovers** the injected-context domain rather than listing it.

**Domain roots** (final list to be fixed in the plan, gated on 6.1):
`clavity-dotnet/plugin/`, `clavity-classic/plugin/`, `seed/`, and - subject to 6.1 - `agy-autotrain/`,
`ghidrust/plugin/`, `commonmemory/`.

**The fail-closed property is the load-bearing part.** For every file discovered under a domain root, the
file must either:

1. satisfy every applicable invariant, **or**
2. match an entry in a **committed** exemptions file carrying a mandatory free-text `reason`.

A file that is neither covered nor exempted **fails the build**. This is what makes the gate survive its
own future: a new skill, hook, or knowledge file added six months from now is covered by default, and the
only way to opt out is to write down why. A suite that hard-codes the file list is a second generation of
`check-agy-discipline-skills.ps1:13` and will drift exactly as that one did.

**Two things must be constrained, or "fail-closed" is decoration:**

- **What counts as a domain file - and it must be SUBTRACTIVE, not additive.** A domain root does contain
  files that are not injected context (`README.md`, `plugin.json`, `NOTICE`, `.mcp.json`,
  `.claude-plugin/`). The tempting fix is to define the domain by **role** - match `skills/*/SKILL.md`,
  `knowledge/*.md`, hook files, the seed. **That is wrong, and it was caught only on the second panel
  round.** An additive role matcher is mathematically an allowlist of globs: introduce a new category of
  injected text (a prompt template under `plugin/templates/`, a cheatsheet under `plugin/cheatsheets/`)
  and the matcher silently skips it - recreating the exact whitelist drift this design exists to cure.
  The gate must therefore **walk every file under the domain roots and subtract an explicit, checked-in
  ignorelist of known non-injected infrastructure**. Anything not on that ignorelist is audited by
  default, so a new file type fails until someone classifies it deliberately.
- **Exemption discipline.** A free-text `reason` that nothing checks is a rubber stamp; under time
  pressure it becomes `"deliberate"` and the gate is theatre. Each exemption entry must therefore name
  **which invariant** it waives (never a blanket waiver of all of them), and **no exemption may name an
  anomaly in section 3** - closing those is the point, and exempting one to reach green inverts the
  sequencing in section 7.
  🔴 **That last rule is not self-enforcing, and saying so is the whole point of this document.** A parser
  matching entries against failing files has no idea what "section 3" contains; because those 10 defects
  are *actively failing*, an exemption for one passes bidirectional validation and turns CI green,
  shipping the defect. So the plan must implement it as a **hardcoded blocklist of `(file, invariant)`
  tuples** that the suite refuses to honour until each anomaly is closed - or state plainly that it is a
  human review policy rather than an automated invariant. What it must NOT do is leave prose that reads
  like a gate and enforces nothing. That is the exact failure this design was written to end, and it was
  reproduced here, inside the design, at round 3.
  🔴 **The blocklist is temporary scaffolding and must carry its own retirement**, or it becomes permanent
  dead state that silently forbids a legitimate future exemption on those files long after the reason has
  gone. It exists only to stop the 10 anomalies being exempted during standup; **once an anomaly is closed,
  its tuple is removed and the guarantee transfers to the ordinary invariant**, which now passes on that
  file and will fail again if the defect returns. The plan must therefore delete blocklist entries as part
  of each anomaly's fix commit, and the last such commit removes the blocklist entirely.
- **Exemptions must validate BIDIRECTIONALLY.** Requiring that every failing file has an exemption is only
  half the contract. Without the other half, exemptions become zombies: a file is cleaned up or deleted,
  its entry stays, and when the defect is reintroduced months later the stale entry silently masks the
  regression. So the gate must also assert that **every exemption entry corresponds to a file that exists
  and an invariant that is actively failing** - an entry whose file now passes without it fails the build
  as `unused exemption`. This makes the exemption list self-pruning rather than self-accumulating.
- **Exemption path keys - deduplicated ONLY across the mirrored twins.** Paths are keyed relative to the
  domain root (`skills/adversarial-panel-review/SKILL.md`) *for the two byte-identical plugin trees only*,
  which are aliased to a single logical root. Keying those at repo root would require duplicating every
  entry, and exempting only one tree leaves the mirror gate green while CI fails on the other.
  🔴 **Every OTHER product keeps its product prefix** (`agy-autotrain/...`, `ghidrust/plugin/...`,
  `commonmemory/...`, `seed/...`). Stripping the root globally would let `skills/review/SKILL.md` in one
  product silently waive an invariant for a same-named file in a different product - a real collision once
  the domain covers six roots, and one that grows more likely as products add skills.
  Keys are normalised to forward slashes regardless of host OS.

**Operator failure surface.** When the gate fails it must say which file, which invariant, what was found,
and the exact exemption line that would waive it. A discovery gate that reports only *"file X is not
covered"* forces the operator to reverse-engineer the check, which is how a gate acquires a reputation for
being easier to bypass than to satisfy.

**Aggregate, never short-circuit.** Every invariant evaluates the whole domain and reports all violations
in one summary; the suite must not abort on the first one. Section 7 sequences the gate *before* the 10
anomalies are fixed, so on the very first run the gate is expected to be red in several places at once.
A short-circuiting runner would surface one failure, hide the rest, and destroy the red-to-green
demonstration that is the only evidence each check actually catches the anomaly it was written for.

🔴 **But the obvious way to aggregate is itself a banned pattern in this repository.** Pester fails an
`It` on its first failed assertion, so the natural workaround is to collect violations and assert once -
`$violations.Count | Should -Be 0`. That is a **CARDINALITY assertion over a filtered collection**, which
is smell (1) in the very list `assertion-strength-reminder.sh` injects into every agent that touches a
test file, and which `agy-test-audit` Step 5 exists to catch. A spec that ships this gate with a
count-only assertion would be caught by its own sibling discipline.

**Therefore: one `It` row per (file, invariant) pair**, generated from discovery with `-ForEach`, so a
failure names *which* file broke *which* invariant rather than reporting that some number of things are
wrong. That satisfies aggregation and per-row attribution at once, and it is the same shape the repository
already requires when proving a check non-vacuous under a logic mutant.

🔴 **Discovery-driven rows cannot see a deleted file, which silently breaks bidirectional validation.**
If every row is generated by walking what is on disk, an exemption whose file has been deleted or renamed
never gets a row - so the `unused exemption` rule above, which exists precisely to stop zombie entries,
never fires for the one case most likely to produce one. The suite therefore needs **two** iterations, not
one: rows generated from **discovery** (file -> invariants), and a separate set generated from the
**exemptions file** (entry -> must name a path that exists and an invariant that is currently failing).
Only the second can catch an entry whose subject no longer exists.

🔴 **An aliased key must be validated against BOTH twin trees, not either one.** Because keys for the two
byte-identical plugin trees are stored once under a single logical root, the exemptions iteration has to
expand each aliased key back into both concrete paths and require the invariant to be failing in both. If
it settles for the first tree it finds, one tree can be cleaned up while the other still carries the
defect, and the exemption goes on masking the survivor - a divergence the mirror gate would catch only if
the trees differ in bytes, which is exactly what a shared exemption invites people to stop checking.

**Traversal pruning is cheap insurance, not a live problem.** The panel raised build-artifact traversal
(`target/`, `node_modules/`, `.venv/`, `.git/`) as a cost risk. **Measured and refuted for the current
tree:** zero such directories exist under any of the six domain roots, and the entire corpus is 130 files.
Prune them at the directory level anyway - it costs one line and the claim stops being true the day a
domain root gains build output - but this is hardening, not a defect being fixed.

**Invariants at first cut:**

- **Encoding** - pure ASCII across the domain. First exemption entry is
  `adversarial-panel-review/SKILL.md` (69 non-ASCII characters, already deliberate and already documented
  at `scripts/check-agy-discipline-skills.ps1:20-22`).
- **Reference resolution** - a **narrowed** check, see 4.1.1. Closes C2.
- **Plan-residue ban** - no `(Task N)` / `(Step N)` / `(Phase N)` bare plan references in shipped text.
  Closes C1.
- **Tag hygiene** - no `[X] X:` duplicated-prefix pattern in any emitted string. Closes A1.
- **Degraded-line namespace** - every `guard inactive:` string opens with the same prefix. Closes A2.
- **Emitted-payload budget** - an upper bound on emitted hook message size, asserted against the *measured*
  strings rather than a number in prose. Does not close A3 (which is a stale claim in `ROADMAP.md`), but
  prevents the drift that made A3 wrong.
  🔴 **This check is vacuous unless it drives each hook's MAXIMAL output branch.** Hooks emit their full
  payload only when their trigger conditions are met. Measured: piping `{}` into
  `assertion-strength-reminder.sh` produces **no output at all** and exits 0. A budget test written against
  default execution therefore measures an empty string, passes with 100% headroom, and is blind to every
  full-payload regression - a textbook vacuous test, and precisely the defect class this repository already
  has a discipline for. The plan must set up, per emitter, the explicit input that forces its longest
  branch, and prove non-vacuity by mutating the message and seeing that specific row go red.

**Cost:** sub-second, zero model tokens, zero recurring human attention.
**Closes:** A1, A2, C1, C2, C3 - **five**.

#### 4.1.1 Reference resolution must be narrowed, or it is unusable

The obvious form of this check - *"every backticked path-like token must resolve on disk"* - was measured
against the real corpus before being specified here, and **it fails**. Of 12 distinct backticked path
tokens in `clavity-dotnet/plugin/skills/*/SKILL.md`, **7 do not resolve at repo root - a 58% false-positive
rate** - and every one of the 7 is legitimate:

| Token | Why it legitimately does not resolve |
|---|---|
| `%USERPROFILE%\.clavity\driver-cheatsheet.md` | runtime path on the user's machine |
| `golden-header.seed.md`, `golden-header.growth.md`, `golden-header.md` | runtime artifacts in the user's profile |
| `.clavity/seams/<topic>.md` | template carrying a `<placeholder>` |
| `ROADMAP.md` | product-relative, not repo-root-relative |
| `assertion-strength-reminder.sh` | bare filename; exists at `clavity-dotnet/plugin/hooks/` |

A check with that false-positive rate would be loosened until it meant nothing - which is precisely the
bypass failure mode this design is supposed to avoid. **The check must therefore classify before it
asserts**, and only assert on the class it can be right about:

- **ASSERT** - tokens containing a `/` that look repo-relative and carry a known repo prefix
  (`docs/`, `scripts/`, `clavity-dotnet/`, `clavity-classic/`, `seed/`, `installer/`).
- **RESOLVE-THEN-ASSERT** - bare filenames with a known shipped extension, resolved against a **search
  set**, not the repo root. This is the class that catches C2 (`agy-first-brainstorm.sh` resolves nowhere
  under `plugin/hooks/`).
  The search set is the domain roots, **plus each product root, plus the repo root** - `ROADMAP.md` is a
  bare filename with a known extension living at `clavity-dotnet/ROADMAP.md`, outside every domain root,
  and top-level files are cited too.

  🔴 **This class can only make a NEGATIVE assertion safely, and that limit must be written into the
  check.** Measured: the corpus carries 10 bare-filename tokens, and resolving them against a multi-root
  search set is **ambiguous for three of them**:

  | Token | Resolves to |
  |---|---|
  | `ROADMAP.md` | **three** files - `agy-autotrain/`, `clavity-classic/`, `clavity-dotnet/` |
  | `agy-remote-control-protocol.md` | **two** - `docs/` and `clavity-classic/docs/` |
  | `settings.json` | **two** in-repo - `.claude/` and `.vscode/` - while the intended referent is the user's `~/.claude/settings.json`, which is not in the repo at all |

  So "a file with this name exists somewhere in the search set" is a weak signal: it would happily pass a
  reference pointing at the *wrong product's* `ROADMAP.md`, and it passes `settings.json` by accidentally
  matching a file that is not the referent. **The check therefore reports three outcomes, not two:**
  resolves nowhere = `broken reference` (a hard failure, and the one that catches C2); resolves to exactly
  one = pass; resolves to more than one = `ambiguous reference`. Widening the search set to remove false
  positives necessarily weakens the positive assertion - saying so is the difference between a check and a
  comfort.

  🔴 **`ambiguous reference` DOES NOT FAIL THE BUILD, and the spec must say so rather than leave it to the
  implementer.** Describing it only as "a distinct and weaker diagnostic" left the pass/fail question open,
  and an implementer could reasonably read it either way. It cannot be a hard failure: `ROADMAP.md`
  resolves to three files today and is a legitimate citation, so failing on ambiguity would red the build
  on correct text. It is therefore a **non-failing reported diagnostic** - surfaced in the run output and
  countable over time, never a gate. If that count ever becomes actionable, tightening it is a separate
  decision with its own evidence, not something to smuggle in as an implementation detail.

  `settings.json` also joins the runtime-artifact SKIP list alongside the `golden-header.*` files: bare
  filenames whose referent lives on the user's machine, not in this repository. That list is a small
  explicit whitelist and is acceptable only because it is short, enumerated, and reviewed in the diff.

- **RELATIVE** - a token beginning `./` or `../` is normalised against the directory of the **enclosing
  document** and asserted there. Candidate identification admits these, so without their own class they
  would fall through to UNCLASSIFIED and fail the build. **Measured incidence in the current corpus: zero**
  - this is a latent gap being closed before it can bite, not a live defect.
- **SKIP** - anything containing `%`, `$`, `~`, or a `<...>` placeholder; anything matching a declared
  runtime-artifact name list.
- **UNCLASSIFIED - an error, never a silent skip.** A token containing `/` that matches neither ASSERT's
  known-prefix list nor SKIP falls in no class, and the fallback must be stated or the check is unsound in
  both directions. Defaulting such tokens to SKIP silently drops exactly the defect most worth catching -
  a top-level typo like `doc/marker-contract.md` or `script/check-seed.ps1`, which is broken *because* the
  prefix is wrong. Defaulting them to ASSERT re-imports false positives. So an unclassified path-like
  token **fails the build as `unclassified reference`**, and is resolved by adding it to ASSERT's prefix
  list or to SKIP - a deliberate act, recorded in the diff.

**But "contains a `/`" is the wrong candidate filter, and this was measured.** In
`plugin/skills/*/SKILL.md` plus `plugin/knowledge/*.md` there are **23 backticked slash-bearing tokens
carrying no file extension and no variable marker**. They are not paths at all:

- **slash-commands** - `/agent`, `/mcp`, `/model`, `/skills`, `/tasks`, `/usage`, `/teamwork-preview`
- **directory references** - `.clavity/`, `.clavity/agy-marks/`, `.git/`, `.agents/skills/`
- **prose** - `[doc/user]`

Under a bare "contains `/`" filter all 23 fail the build on day one, and the repair - dumping English and
command names into SKIP - pollutes the skip list until it means nothing. **Slash-commands are the worst
case because they recur: every new command adds one.**

**A candidate must therefore be positively identified as a path**, not merely contain a separator:
it carries a known shipped file extension (`.md`, `.sh`, `.ps1`, `.json`, `.cs`, `.rs`, `.toml`), **or**
begins with `./` or `../`, **or** begins with a known repo prefix. Everything else is not a reference and
is never classified.

🔴 **A leading bare `/` must NOT qualify a token as a path.** The panel proposed exactly that, and it is
wrong on this corpus: `/agent`, `/mcp`, `/skills` and `/tasks` all begin with `/` and are slash-commands,
so that rule converts seven correct tokens into seven build failures. Recorded because the finding was
right while its suggested fix was not - the fix needed its own measurement.

Directory references (`.clavity/agy-marks/`, trailing slash, no extension) are their own small class: they
resolve as directories or they are skipped, and the plan must state which. They must not fall into the
file-resolution path.

The plan must re-measure the false-positive rate against the **full** domain after implementing this
classification, and the check does not ship until that rate is zero on the current corpus. A check that
ships with known false positives trains its operator to ignore it.

### 4.2 Part 2 - an anchor convention for cross-references

C4 is unlintable as free English ("Step 5"). It becomes lintable if cross-references between shipped
documents must use an explicit, unique anchor, and unanchored step citations are banned. That converts C4
from a judgement call into a resolvable reference, and folds it into the reference-resolution invariant
above.

**Closes:** C4 - **a sixth**.

This is a real cost: it constrains how these documents are written, and every existing cross-reference must
be converted. The plan must count them before committing to this part.

### 4.3 Part 3 - rulings become committed tracked items, immediately

B1 is not a missing mechanism. The ruling was recorded in a session note - *"rides with section 7's edit
pass"* - section 7 shipped, and nothing ever asserted the value landed.

**Rule:** an owner ruling that changes shipped text becomes a **committed `ROADMAP.md` entry at the moment
it is made**, not a note to be actioned later. This adds no machinery; `ROADMAP.md` is already the promote
target that the `open-issues` triage contract names, and it is already what the owner reads.

**Two rejected alternatives, and why** - both were proposed during design and both were killed:

- **A deliberately-failing test to keep the ruling alive.** Rejected: a red test in the fast suite poisons
  the green signal for everything else committed until the edit lands, breaks `git bisect`, and degrades
  the harness it is meant to guard. That is the same defect class this whole document is about.
- **A `.clavity/pending-invariants.json` ledger, or routing rulings through `.clavity/local-anomalies.md`.**
  Rejected: `.clavity/` is gitignored (`.gitignore:45`, confirmed with `git check-ignore -v`). Both records
  would be local-only and invisible to CI and to every other clone - **B1's exact failure mode**, a record
  that never reaches the shipped artifact.

**Mitigates - does NOT close - B1-class recurrences, and the distinction is not pedantic.** This part is
**process discipline, not tooling**. Nothing enforces that a ruling given in conversation reaches
`ROADMAP.md`, and nothing asserts that a prose entry in `ROADMAP.md` is reflected in a skill constant. An
earlier draft of this section claimed it "closes" the class; that claim presented unmonitored human
discipline as an automated gate, which is the same category error the rest of this document is about.
B1 itself is fixed by hand.

**If the owner later wants this mechanised**, the smallest honest version is a release-time validator: a
ruling is recorded in `ROADMAP.md` with an explicit machine-readable tag (`[RULING: MAX_CAPSTONE_ROUNDS=6]`)
and the release gate refuses to tag while any such tag is unsatisfied in its target files. That is out of
scope here and is not being proposed - it is recorded so the option is not lost the way B1 was.

### 4.4 Part 4 - no sixth standing discipline

The four-round peer sweep stays a **manually invoked tool**, not an auto-firing discipline.

Reasoning, against three measured facts: five agy disciplines already exist and whether they cohere is an
open unresolved fork; 87.2% of what these disciplines cost is context re-payment, so the dominant lever is
*when* a discipline runs, not what it checks; and there is one human owner who personally owns every push.
Institutionalising the sweep is an over-engineered response to a one-time stabilisation backlog. The sweep
costs nothing sitting idle and can be run whenever the surface changes materially.

---

## 5. What this design does NOT do

Stated plainly, because a governance mechanism that oversells its coverage is itself the failure mode.

- **A3, A4, C5 are not closed by anything here.** A stale measurement in prose, an ergonomics judgement,
  and a prose quantifier disagreeing with an adjacent code snippet all require judgement. They are caught
  by a manual sweep or not at all.
- **The gate cannot check invariants nobody thought to write.** It raises the floor; it is not proof of
  correctness.
- **Byte-identity between the two plugin trees means a defect committed identically to both is invisible to
  the mirror gate.** That remains true and is not addressed here.
- **The gate does not read for meaning.** It will never catch an instruction that is well-formed,
  well-referenced, ASCII-clean, and simply wrong.

---

## 6. Open questions for the owner

### 6.1 Domain boundary - does the gate cover the other three products?

`agy-autotrain/`, `ghidrust/plugin/`, and `commonmemory/` ship 73 507 B of injected context, all six of
their markdown files carry non-ASCII, and none has ever been audited. Including them makes the gate
genuinely domain-wide; it also means 295 non-ASCII characters must be either sanitised or exempted with
reasons before the gate can go green. Excluding them re-creates, on day one, the exact whitelist gap that
caused this.

**Recommendation:** include them, with a **per-file, single-invariant** exemption - each of the six files
waiving *only* the encoding invariant, each carrying the same tracked reason
(`"not yet audited - tracked at <ROADMAP ref>"`). Every other invariant applies to them from day one.

This deliberately avoids a **bulk** exemption, which the solo panel flagged as reintroducing the very
defect this design exists to remove: a single entry waiving everything for a whole subtree is a whitelist
wearing a different hat, and it would hide any *reference* or *tag* defect in 73 507 B of never-audited
text. Six narrow entries keep the debt visible and countable; one broad entry makes it invisible again.

### 6.2 A4 - the ergonomics of the assertion-strength message

Deferred here by owner ruling on 2026-08-08. `assertion-strength-reminder.sh` is the only injected message
that imperatively demands open-ended work (prove a test non-vacuous with a logic mutant) on every first
touch of every test file, in another user's session. The question is whether it should inform rather than
command. No script can settle it. To be ruled when the replacement text can be seen in context.

### 6.3 Disposition of the 10

Owner ruled on 2026-08-08: **fix nothing yet, carry all 10 into the spec.** They are this design's
evidence and its first test cases. The implementation plan must close them as part of standing the gate up
- a gate that ships green over a surface with 10 known defects in it has been calibrated to pass.

---

## 7. Sequencing and constraints the plan must respect

- **Byte-identical mirrors.** `clavity-dotnet/plugin/` and `clavity-classic/plugin/` are kept
  byte-identical by `scripts/check-seed-artifacts-synced.sh`. Any change to shipped text must be mirrored
  by copy, never retyped, and must pass that gate plus `plugin-hooks-payload.Tests.ps1`.
- **Explicit test registration.** Test suites are an explicit list in `justfile`, not a glob, enforced by
  `scripts/tests/test-suite-registration.Tests.ps1`. The new suite must be registered there.
- **CI weight is real, and the naive implementation blows it.** The script suite is already split into
  fast and slow halves because the whole suite exceeds the tool timeout. The new gate belongs in the fast
  half only if it stays sub-second - and **executing the hooks to measure their output does not**.
  Measured on this machine: **16 `bash -c 'exit 0'` invocations took 5.24s against a control of 0.64s for
  16 no-op shell builtins** - an ~8x ratio, roughly 290ms of pure spawn overhead per invocation. Eight
  emitters across two plugin trees is exactly 16 spawns, so a naive implementation costs ~5s and misses
  the budget by 5x. (Absolute figures are inflated by this machine's load; the control ratio is the
  signal.) **Mitigation:** parse the `printf` / `msg=` template literals statically where possible, and
  where a hook genuinely must run, execute only the `clavity-dotnet` tree in one batched runner and rely
  on `check-seed-artifacts-synced.sh` for mirror equality.
- **Encoding reads must be explicit.** Under Windows PowerShell 5.1 a bare `Get-Content` decodes using the
  system ANSI code page, not UTF-8, so multibyte sequences can be transcoded before a `[^\x00-\x7F]` regex
  ever sees them - a platform-dependent false negative in the one check that has to be exact. Read bytes
  (`[System.IO.File]::ReadAllBytes`) or decode UTF-8 explicitly. **Two in-repo precedents already exist and
  the plan should follow them rather than invent a third:** the string case at
  `scripts/tests/agy-anomaly-capture-reminder.Tests.ps1:273` (`$bytes = [Text.Encoding]::UTF8.GetBytes($m)`),
  and the file case at `scripts/check-seed-budget.ps1:32`
  (`[System.Text.Encoding]::UTF8.GetByteCount([System.IO.File]::ReadAllText($SeedPath))`).
  An earlier draft of this section asserted that no file-read precedent existed - that was wrong, and it
  was wrong about the very script whose byte-cap this document cites elsewhere. For an ASCII scan
  `ReadAllBytes` is still the more direct instrument than decode-then-recount, but the encoding discipline
  is established, not new.
- **Order.** Stand up the gate with its exemptions first, then close the 10 anomalies against it, so each
  fix is demonstrated by a check that goes from red to green. Closing them first and adding the gate
  afterwards proves nothing about the gate.
- **Non-vacuity.** Every new check must be shown to fail against a deliberate logic mutant of the thing it
  guards, with per-check attribution - not merely that the suite went non-zero.

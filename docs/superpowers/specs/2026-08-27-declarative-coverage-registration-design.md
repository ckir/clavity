# Declarative Coverage Registration — design spec

**Status:** 🔴 **SUPERSEDED 2026-08-27 - NOT BUILT.** Owner chose THE UNIVERSAL RUN instead: the
`paths:` filter, the coverage gate and `$Required` were all DELETED, so the defect class this spec tried to
detect can no longer occur. **This document is kept for its reasoning, not as a plan.** Its three panel
rounds are what established that DCR would not have caught the historical misses - which is the finding that
led to removing the filter instead. Read §0 for that argument.

**Superseded status:** SPEC (v4, post-panel round 3). Forward-writable; no implementation plan yet.
**Date:** 2026-08-27
**Origin:** AGY-CAPSTONE round 27 seat H, then an owner + peer consult over three negotiation rounds.
**Reviewed:** adversarial panel round 1 — solo panel (8 seats) + live-peer escalation (8 seats).
Every fold below is recorded in §10.
**Sequenced:** step 4 of the 2026-08-27 sequence, after `PUSH -> CI green` (satisfied at `30eca89`).

---

## 0. 🔴 ROUND 3 CHALLENGED THE PREMISE - the owner should read this before the rest

Rounds 1 and 2 improved the design. **Round 3 attacked whether it is worth building**, and the attack
lands. Three findings compound:

**It would not have caught the defects that motivated it.** Walked against this repository's own history:
`lefthook.yml` is read by two suites and `build/members.json` by one. In each historical miss, an author
added a dependency and failed to update a distant table. Under DCR that author must instead remember to
add a header line - and §4.7 admits the gate is BLIND TO UNDER-DECLARATION, so a forgotten header passes
green. The peer put the contradiction sharply: *the mechanism only fires if the author remembered to
declare the dependency but forgot the CI YAML - yet if they remembered to declare it, they already knew
about the dependency.*

**What DCR actually buys is LOCALITY, not detection**, and v1-v3 never said so. Updating `$Required` means
opening a file you have no reason to open; writing a header means editing the file you are already in, at
the moment you add the dependency. That is a genuine reduction in failure rate. It is not a mechanical
guarantee, and §1 was written as though it were.

**The one class it DOES close mechanically is §4.4** - a suite with NO header at all. That is real but
narrow, and it is not the historical failure shape.

⚠ **THE QUESTION FOR THE OWNER IS THEREFORE NOT "which fork?" BUT "does this survive at all?"** Fifty
suite migrations, a rewritten checker and a new CI job buy locality plus one narrow mechanical check. That
may still be worth it - locality is why the design was proposed - but it must be chosen with the ceiling
known, not on §1's original framing.

---

## 1. The defect this exists to end

Round 27 found that **five Pester suites assert against `agy-autotrain/hooks/*` and no workflow in the
repository triggered on that tree.** A commit touching only those four tracked hook files merged with
every suite guarding them unrun. The suites were correct, green, and unreachable.

`ci-scripts.yml` runs suites by DIRECTORY SWEEP (`Invoke-Pester scripts/tests`), so no suite appears in
the workflow by name. The link between "what a suite tests" and "what makes CI run it" lives only in a
hand-maintained table, `$Required` in `scripts/check-ci-filter-coverage.ps1`, and **nothing connects a
suite to its own row.**

The same file's history records `agy-autotrain/skills/agy-curate/SKILL.md` being MISSED when
`lefthook.yml` was added — in the very commit that added the row reading it — and a later audit finding
five more.

### Why restoring the deleted scanner is not the answer

A "root vocabulary" check once parsed every suite's AST for string literals. It was **DELETED by owner
decision**: across five capstone rounds it produced FOUR defects of its own against FIVE real gaps found
once. **MEASURED 2026-08-27: it would not have caught the round-27 defect either** — it worked at
TOP-LEVEL granularity and `agy-autotrain` IS reached, by four narrow rows.

**The goal is the scanner's automation with none of its guessing:** the author states the dependency, and
a gate checks it mechanically.

---

## 2. Measured facts (all measured 2026-08-27 at `30eca89`)

| fact | value |
|---|---|
| Pester suites under `scripts/tests/` | **49** |
| Pester suites elsewhere | **1** — `clavity-dotnet/install/clavity-install.Tests.ps1` |
| Non-Pester CI suites | **≥1** — `agy-autotrain/verify/testdata/run-hook-tests.sh` (15 cases, bash) |
| `ci-scripts.yml` filter entries | **16**, mirrored in `on.push.paths` and `on.pull_request.paths` |
| Filter parser | `yq` v4.50.1 — required, never optional. Returns entries **unquoted** (`'scripts/**'` → `scripts/**`) |
| `test-suite-registration.Tests.ps1` population | globs `$PSScriptRoot` → **49**, blind to the 50th |
| Files on disk vs tracked | **46,991 vs 620**; 36,205 sit in `*/target` |
| **Where `check-ci-filter-coverage.ps1` is invoked** | **`lefthook.yml:54` ONLY — a local pre-push hook. It does NOT run in CI.** Its two mentions in `ci-scripts.yml` are comments. |

---

## 3. The proposed mechanism

**Every test suite declares, in its own file, the repository paths whose modification must trigger it.**
A gate extracts those declarations, unions them, and asserts the union is covered by the filter of the
workflow that RUNS that suite.

```powershell
# CI-Coverage: agy-autotrain/hooks/**
# CI-Coverage: clavity-dotnet/plugin/**
Describe 'agy-curate-nudge' { ... }
```

- **No guessing.** The author states the dependency; nothing infers it. The 4:5 noise ratio that killed
  the scanner cannot recur, because there is no heuristic.
- ~~**Exact granularity.** A top-level blind spot is not expressible.~~ 🔴 **RETRACTED in round 3.**
  Under §5.2(a) the author must declare at the FILTER's granularity, not at the true dependency's, and the
  filter is coarse. The claim was false as written.
- **Cannot be orphaned** — *conditional on §4.4 and §4.6*. Without both, this property is FALSE.

---

## 4. Contracts

### 4.1 The header
- Syntax `# CI-Coverage: <entry>`, one entry per line, repeatable.
- **Must appear within the file's first header block** — see §5.1, whose recommendation the panel reversed.
- `<entry>` is the **exact filter-entry string**, parsed up to the first ` #` (space-hash), then
  `TrimEnd()`, unquoted, and **rejected if empty**. An empty value is a parse ERROR, never a silent
  zero-entry line. ⚠ This repo has a documented CRLF hazard; the trim must remove `\r`.
- **A trailing ` # reason` is permitted and is how §4.3 preserves the `$Required` REASON text.**
  🔴 **v2 forbade this and thereby contradicted its own §4.3** — an exact end-of-line-anchored match makes
  `# CI-Coverage: path/** # reason` fail, so the reason could not be carried anywhere. Found independently
  by BOTH panels in round 2, which is the strongest signal this review has produced about a fold.

### 4.2 The checker (`scripts/check-ci-filter-coverage.ps1`, rewritten)
- Enumerate suites (§4.5); extract every `# CI-Coverage:` entry; union them.
- Parse both filter blocks with `yq` — unchanged, still REQUIRED, never skipped.
- **Assert `declared ⊆ filter`, NOT equality**, and see the limitation in §4.7 — this asymmetry is the
  design's sharpest edge, not a detail.
- Assert `on.push.paths` and `on.pull_request.paths` agree. Nothing else performs that check.
- **Handle universal coverage as a special case.** A workflow with no `paths:` block, or one containing a
  bare `**`, triggers on everything, so every declaration is trivially covered and the subset check must
  PASS rather than fail on a missing literal. MEASURED: not currently reachable — all 16 entries are
  explicit paths and no bare `**` exists — but exact-string matching would otherwise force the filter to
  enumerate redundant sub-paths purely to satisfy the matcher.
- **The failure message must not teach the wrong repair.** When suite X declares an entry the filter
  lacks, there are two valid fixes — add it to the filter, or correct a wrong declaration — and the gate
  cannot know which. A message saying only "add it to the filter" trains an author with a typo'd
  declaration to add junk to the filter. State both.

### 4.3 `$Required` is DELETED, not shrunk
v1 kept a residual hand-maintained list for "infrastructure" entries. **The panel refuted that and it was
verified:**
- `check-ci-filter-coverage.Tests.ps1` exists and references `ci-scripts.yml` twice — it genuinely
  depends on the workflow and can declare `.github/workflows/ci-scripts.yml` itself.
- The bash suite declares `.claude/hooks/**` and `agy-autotrain/verify/**` under §5.3(a).

A manual list of two decays by the same mechanism as a list of twenty. **There is no exception; the table
goes.** Its per-entry REASON text is preserved by moving it into the declaring suite's header comment.

### 4.4 The registration assertion — without which the scheme is decorative
`test-suite-registration.Tests.ps1` gains: **every discovered suite carries at least one well-formed
`# CI-Coverage:` line.** Without it a new suite with no header is invisible exactly as it is today.

### 4.5 Suite discovery — ONE population, bounded
The checker and the registration suite **must enumerate from the same list**, or they will disagree
silently. Two hazards, both measured:
- An unbounded `**/*.Tests.ps1` crosses into `target/` (36,205 files). **Bound to named domain roots.**
- `Get-ChildItem` sees untracked files; `git ls-files` does not.
  *Recommendation: `git ls-files`. An untracked suite cannot run in CI, so it cannot be a coverage gap
  there; and the tracked set is the one every other gate in this repo reasons about.* v2 said only "pick
  one and state it", which left a CONTRACT with an undefined term.

### 4.6 The suite-to-workflow invariant — UNSTATED in v1
A declaration is meaningful only against **the filter of the workflow that RUNS that suite**, not against
a global set. This is load-bearing and non-obvious: MEASURED, `ci-injected-context.yml` and
`ci-installer-agy-autotrain.yml` BOTH trigger on `agy-autotrain/**` — so a path can be "covered" by a
workflow that never runs the suite in question. If a suite is ever run by two workflows, the model must
say which filter it is checked against.

🔴 **v2 ASSERTED THIS INVARIANT WITH NO MECHANISM, and the panel was right to call it impossible as
written:** workflows run suites by anonymous directory sweep, so nothing statically maps a suite to its
workflow. **MEASURED 2026-08-27, which bounds the problem rather than solving it:** `ci-scripts.yml` is
the ONLY workflow in the repository that invokes `Invoke-Pester` at all, and the only one that sweeps
`scripts/tests`. So the mapping is trivial TODAY — one workflow — and the spec may assume it.
**The assumption must be GUARDED, not merely stated:** the checker fails closed if more than one workflow
is found to sweep the suite directory, because at that moment the model it relies on has silently stopped
being true.

🔴 **BUT THAT GUARD CANNOT BE SOUND, and v3 overstated it.** Detecting "sweeps the suite directory"
means recognising `Invoke-Pester scripts/tests` inside arbitrary `run:` steps - and a workflow can invoke
suites behind a script (`bash run-ci.sh`) or a reusable workflow, where no static parse can see it. The
guard is therefore a **heuristic** - a grep that fails open on indirection - and must be labelled as one
rather than presented as a structural guarantee. **A guard that fails open certifies what it stopped
checking**, which is this repository's own standing law; the honest form is a loud heuristic plus a
documented assumption, not a claim of soundness.

### 4.7 STATED LIMITATION — the gate cannot detect UNDER-declaration
`declared ⊆ filter` fails only when a suite declares something the filter lacks. **If a suite declares
half of what it depends on, the subset still holds and the gate passes.** The gate catches
under-FILTERING; it is blind to under-DECLARING.

This is the design's boundary and it must not be papered over. It does catch the round-27 defect — those
five suites would have declared `agy-autotrain/hooks/**` and the gate would have demanded it — **but only
because the declaration was made.** Nothing forces a declaration to be complete.

---

## 5. Design forks

### 5.1 Where must the header sit? — **recommendation REVERSED by the panel**
v1 recommended "anywhere in the file". That is a false-positive generator, and self-referentially so: a
suite that tests the gate's rejection of a malformed header **contains `# CI-Coverage:` as fixture data**,
and a full-file scan would extract it as a real declaration. Commented-out blocks and heredocs do the same.
*Recommendation: a bounded header region (first N lines, or a contiguous block before the first `Describe`).*

### 5.2 FILTER ENTRY or SUBJECT PATH? — **(a), with its cost now acknowledged**
**(a) Exact filter entry** — a string-set comparison with zero glob semantics. This repo has already
refused to depend on unverifiable filter semantics once (a `!` negation was rejected because it could not
be verified without pushing).
**(b) Subject path** — requires reimplementing GitHub's path-matching, i.e. the guessing this design removes.
*Recommendation: (a), but **the fork is harder than v1-v3 presented and both options now carry a real
defect.***

🔴 **GLOB SUBSUMPTION BREAKS (a), and it is the SAME DEFECT as §6a seen from the other side.** The
filter's entries are coarse - MEASURED, six of the sixteen end in `/**`. A suite that reads
`scripts/drain-lib.ps1` cannot declare that path: the exact-string subset check would fail even though
`scripts/**` already covers it. So the author is forced to declare at the FILTER's granularity, which
means declaring `scripts/**` - the uninformative declaration §6a describes. The two findings are one
phenomenon: **exact-string matching forces coarse declarations, and coarse declarations convey nothing.**

Left unhandled it also cascades: an author declaring a legitimately narrow path is told to "fix" it by
appending a redundant sub-path to the workflow, so the filter accretes narrow entries purely to satisfy
the matcher.

**Acknowledged cost of (a):** it couples suite text to CI infrastructure strings, so renaming a folder in
`ci-scripts.yml` means editing several disconnected suites. **Resolving subsumption requires implementing
glob semantics - which is option (b), the guessing this design exists to avoid.** That is the real shape
of this fork and the owner should choose it knowing both sides are compromised.

### 5.3 How is the bash suite covered?
**(a)** Same header convention in `.sh` files — one parser, one rule, both suite kinds. Comment syntax is
identical. **(b)** Leave its entries hand-maintained — but §4.3 deletes that list, so (b) resurrects it.
*Recommendation: (a).*

### 5.4 The `none` escape hatch — **RESOLVED BY MEASUREMENT, no longer a fork**
v1 proposed `# CI-Coverage: none` for a suite depending on nothing. **Measured: it is never needed.** All
49 suites live under `scripts/tests/`, covered by `scripts/**`; the 50th lives under
`clavity-dotnet/install/`, covered by `clavity-dotnet/install/**`. Both entries are already in the filter,
so **an honest non-empty declaration always exists.** `none` is rejected — it would convert a hard failure
into a silent opt-out, which is how this defect class returns.

### 5.5 The 50th suite — **widen, but BOUNDED**
`clavity-install.Tests.ps1` is invisible to the registration glob, and is already the one suite with no
row in the `_partition.md` runtime table — the same blind spot, found twice independently.
*Recommendation: widen to a named, bounded set of domain roots — never an unbounded recursive wildcard (§4.5).*

### 5.6 NEW — where does the gate RUN? *(added by the panel; v1 never asked)*
**MEASURED: `check-ci-filter-coverage.ps1` runs ONLY from `lefthook.yml:54`, a local pre-push hook. It
does not run in CI at all** — not for a fork PR, not from a machine without lefthook installed. A gate
that exists and is never executed is precisely the round-27 defect class, sitting inside the gate this
spec rewrites.
*Recommendation: the rewrite must be wired into CI as well as pre-push, and the spec must name both sites.
An implementation that changes the logic and leaves the invocation alone has not fixed anything.*

---

## 6. Migration — and the claim v1 got wrong

50 Pester suites plus the bash suite need headers.

🔴 **v1 claimed "the gate is the oracle for its own migration". THAT IS FALSE (§4.7).** The gate fails only
on over-declaration; an incomplete declaration is a valid subset and passes. **The gate cannot tell you
what you forgot.** The migration is therefore a genuine manual audit of 50 suites, not a
gate-driven convergence, and the spec no longer pretends otherwise.

The criterion for a correct declaration, which v1 also left unstated: **the set of paths outside the suite's
own file that the suite reads or asserts about.**

⚠ **Do not seed the headers from `$Required`.** That table is the artefact under replacement and is known
to have been wrong at least six times. Seeding from it would launder its errors into the new mechanism.

---

## 6a. Known limitation — `scripts/**` is a legal synonym for the banned `none`

§5.4 rejects `# CI-Coverage: none` because an honest declaration always exists. **That fix moved the hole
rather than closing it.** MEASURED: `scripts/**` is in the filter and covers 49 of the 50 suites, because
every suite's own file lives there. So any author can satisfy §4.4 with `# CI-Coverage: scripts/**` — a
declaration that is TRUE, passes the subset check, and conveys nothing about what the suite actually
depends on.

**This cannot be closed syntactically without false positives**, because for a suite that genuinely only
tests a script under `scripts/`, `scripts/**` IS the honest and complete answer. A rule banning it would
reject correct declarations.

*Mitigation, and it is observability rather than a gate — stated plainly because this spec criticises
exactly that substitution elsewhere:* the checker reports the count of suites whose only declaration is
the entry already covering their own location. A trend is visible even though no individual case can be
adjudicated mechanically.

## 6b. 🔴 SECURITY - the gate must never echo an untrusted header, and fold §5.6 created this surface

§5.6 puts the gate in CI. A **fork pull request** then supplies suite files an attacker controls, and the
gate parses comment headers out of them and names the offending entry in its failure message.

GitHub Actions interprets certain strings on a step's stdout as **workflow commands** (`::error::`,
`::warning::`, `::add-mask::`, `::stop-commands::`). A header crafted as
`# CI-Coverage: ::add-mask::something` is guaranteed to fail the subset check - it is not in the filter -
and the gate would then echo the attacker's string verbatim into the runner's control plane.

**Contract:** untrusted header text is never echoed raw. Escape or elide it; report the SUITE and a
sanitised excerpt, never the attacker's bytes. Prefer running the gate on a fork PR without elevated
permissions.

⚠ **HONESTY ABOUT EVIDENCE: I have NOT measured this injection.** The workflow-command behaviour is
documented GitHub Actions behaviour, not something this review reproduced; testing it would mean pushing a
hostile branch. Treat it as a design constraint on strong documentary grounds, not as a measured finding.

🔴 **The provenance is the lesson.** This surface does not exist today - MEASURED, the checker has no
real invocation in `ci-scripts.yml`. It would be CREATED by §5.6, which was the solo panel's own round-1
finding. **A fix spawning its own edge, for the third demonstrated time in this review.**

## 7. Known limitation — orphaned filter entries

The gate prevents suites being orphaned from CI; it does **not** prevent CI triggers being orphaned from
suites. Delete the last suite declaring an entry and the entry stays in the filter forever, firing
expensive vacuous runs on every push to that path. `declared ⊆ filter` cannot see it, by construction.
Recorded as a limitation; closing it needs a separate reverse check.

---

## 8. Non-goals

- **Not** a replacement for the directory sweep. Suites still run via `Invoke-Pester scripts/tests`.
- **Not** a per-suite CI job. Nothing changes what runs, only what *triggers* a run.
- **Not** the stopping rule's Rule 2 ("derive user-facing from the installer payload").

---

## 9. Success criteria

1. A suite declaring a path the filter does not reach **fails a gate locally AND in CI**.
   ⚠ This criterion PRESUMES fork §5.6 resolves to "both sites". It is listed as binding while §5.6 is
   still open, which is a contradiction the owner must settle rather than the spec assume.
2. A suite with no well-formed `# CI-Coverage:` line **fails a gate**.
3. `$Required` no longer exists.
4. The push/pull_request agreement check survives the rewrite.
5. 🔴 **The acceptance test proves EXTRACTION, not merely the gate.** v1's criterion — remove
   `agy-autotrain/hooks/**` from the filter and watch the gate redden — **is satisfiable by the hardcoded
   `$Required` table this spec deletes**, so it proves nothing about the new mechanism. Replaced:
   **inject a fabricated `# CI-Coverage: fake/path/**` into a suite and verify the gate fails naming
   that suite and that entry.** Only a declaration the old mechanism could not know about proves the
   declarative path is live.
   🔴 **THE INJECTION MUST TARGET AN ISOLATED FIXTURE, NEVER A LIVE TRACKED SUITE.** A test that writes a
   fabricated CI directive into a real file leaves the working tree dirty if it is interrupted, and the
   fake trigger can be committed by the developer's next `git add`. This correction is itself instructive:
   the injection test was the PEER's own round-1 fix, and the peer's round-2 seat found that fix unsafe as
   written. A correct finding routinely arrives with an incomplete fix.
6. Per the guard law, (5) ships as a **committed test**, not a one-time manual mutation.

---

## 10. Panel round 1 — folded findings

| # | seat | finding | disposition |
|---|---|---|---|
| 1 | Axiom Breaker (peer) | `$Required` should be deleted, not shrunk — infrastructure entries are declarable | FOLDED §4.3, fix verified |
| 2 | Mechanism Gamer (peer) | criterion 5 is satisfiable by the mechanism being deleted | FOLDED §9.5 |
| 3 | Literal Implementer (peer) | "the gate is the oracle for its own migration" is mathematically false | FOLDED §4.7, §6 |
| 4 | Protocol Pedant (peer) | "anywhere in the file" false-positives on fixture data | FOLDED §5.1 (reversed) |
| 5 | Protocol Pedant (both) | delimiters undefined | FOLDED §4.1 |
| 6 | Blindspot (peer) | widening the glob is un-sized; crosses `target/` | FOLDED §4.5, §5.5 |
| 7 | Cascade (both) | orphaned filter entries on suite deletion | FOLDED §7 as limitation |
| 8 | Dependency Cynic (peer) | 5.2(a) couples suite text to CI strings; cost unacknowledged | FOLDED §5.2 |
| 9 | Activation (peer) | a suite outside the discovery glob bypasses both gates | FOLDED §4.5 |
| 10 | Axiom Breaker (peer) | `none` is a conceptual error | FOLDED §5.4, resolved by measurement |
| 11 | **Activation (solo)** | **the checker runs ONLY in pre-push, never in CI** | FOLDED §5.6 — peer missed it |
| 12 | **Axiom (solo)** | the suite-to-workflow invariant was unstated; two workflows share a path | FOLDED §4.6 — peer missed it |
| 13 | **Blindspot (solo)** | the failure message teaches the wrong repair | FOLDED §4.2 — peer missed it |

**PANEL VERDICT (round 1):** substance found by both panels with only partial overlap — the peer broke the
migration claim and the acceptance test; the solo panel found the gate does not run in CI. Folded; round 2
required.

## 11. Panel round 2 — seats rotated, hunting defects in the round-1 FOLDS

Rotation: **Fold Consistency Auditor** (bespoke) + Resource Vampire, plus the two core seats. The bespoke
seat was chosen on this repository's own measured law — roughly half of all fixes in this review series
repaired an earlier fix's code, so the round after a fold is the highest-yield.

| # | seat | finding | disposition |
|---|---|---|---|
| 14 | Fold Consistency (**BOTH panels, independently**) | fold 1 (reason text) contradicted fold 5 (strict parsing) — the reason could not be carried anywhere | FOLDED §4.1 |
| 15 | Axiom Breaker (peer) | §4.6 asserted a suite→workflow mapping with NO mechanism; sweeps are anonymous | FOLDED §4.6 — bounded by measurement (one sweeping workflow) and now GUARDED |
| 16 | Axiom Breaker (peer) | exact-string matching breaks against a bare `**` or an absent `paths:` block | FOLDED §4.2 — handled as universal coverage; measured not currently reachable |
| 17 | Cascade (peer) | the acceptance test mutates a LIVE TRACKED suite and can leave a fake CI directive committed | FOLDED §9.5 — fixture isolation. **The test was the peer's own round-1 fix; its round-2 seat found that fix unsafe.** |
| 18 | **Axiom (solo)** | `scripts/**` is a legal synonym for the banned `none` — covers 49 of 50 suites | FOLDED §6a as a limitation; **peer missed it** |
| 19 | **Literal Implementer (solo)** | criterion 9.1 is binding while the fork it depends on (§5.6) is open | FOLDED §9.1 |
| 20 | **Literal Implementer (solo)** | §4.5 was a CONTRACT with an undefined term ("pick one") | FOLDED §4.5 |
| — | Resource Vampire (both) | no new findings | — |

**PANEL VERDICT (round 2):** the v2 folds introduced three defects of their own and both panels found the
same one independently. Still finding substance; ROUND 3 REACHES THE HARD CAP and is the operator's call.

## 12. Panel round 3 — authorised past the cap by the owner

Rotation: **Boundary Smuggler** (newly triggered — fold §5.6 put the gate in CI, so fork PRs now feed it
attacker-controlled headers; the seat could not fire before that fold) + a bespoke **Historical
Counterfactual Auditor**, plus the two core seats.

| # | seat | finding | disposition |
|---|---|---|---|
| 21 | Historical Counterfactual (**BOTH panels**) | the design would NOT have caught the six historical misses; §1's claim is an overclaim | FOLDED §0 — **the premise challenge** |
| 22 | Boundary Smuggler (peer) | fork-PR headers echoed raw into GitHub Actions stdout = workflow-command injection | FOLDED §6b. ⚠ NOT measured — documented behaviour only |
| 23 | Cascade (peer) | glob subsumption: exact matching rejects a legitimately narrow declaration the filter already covers | FOLDED §5.2 — **and it is §6a from the other side** |
| 24 | Axiom Breaker (**both**) | the §4.6 guard cannot be sound; detecting a "sweeping" workflow is undecidable statically | FOLDED §4.6 — relabelled a heuristic |
| 25 | **Axiom (solo)** | §3's "exact granularity" is false under §5.2(a) | FOLDED §3 — retracted |

**PANEL VERDICT (round 3):** round 3 did not polish the design, it challenged whether the design should be
built. The strongest finding — reached independently by both panels — is that DCR would not have caught the
defects that motivated it. What survives is a real but narrower value proposition (locality, plus one
mechanical check for a missing header), and the owner should choose on that basis rather than on §1's
original framing.

**Panel disposition: NOT GREEN.** Three rounds, 25 findings, substance in every round including round 3.
The remaining open items are decisions for the owner, not defects for another round to find.

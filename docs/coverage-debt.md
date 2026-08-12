# Coverage debt and accepted test boundaries

The rolling, committed output of **AGY-TEST-AUDIT**. It holds only what must persist between audits:
owner-deferred coverage gaps (tracked debt) and the accepted-boundary ledger (the do-not-re-raise list).
Closed gaps are REMOVED from this file, not marked done.

Per-run audit reports are ephemeral and are NOT committed - they live under `.clavity/scratch/`.

> **Re-validate before honouring a do-not-re-raise entry.** Each accepted boundary records the specific
> compensation that justifies it. An entry whose compensation has vanished from the code is promoted back
> to a live gap - the ledger is not a permanent amnesty.

---

## Tracked debt - verified gaps the owner deferred

### 1. `'still subtracts the REAL build directories, by anchored path'` is a parser test, not a corpus test

- **Where:** `scripts/tests/check-injected-context.Tests.ps1`, the `-ForEach` row over five build paths.
- **What it asserts:** `Test-IsIgnored -RelPath $Rel -Globs (Get-IgnoreGlobs ...) | Should -BeTrue`.
- **What its name claims:** that those paths are subtracted from the audited corpus.
- **The gap:** it never runs the corpus walk. It would still pass if the walk stopped consulting the
  ignorelist entirely, because the glob itself would still match the path.
- **The regression that would slip through:** a change to `Get-InjectedContextFiles` that drops the
  `Test-IsIgnored` call. The corpus would silently grow by a virtualenv and every ignored build artifact,
  and this row - the one named for the behaviour - would stay green.
- **The test that should exist:** assert `Get-InjectedContextFiles -RepoRoot $d` does NOT contain each of
  those five paths, against a fixture that actually plants them.
- **Deferred by the owner:** 2026-08-10, AGY-TEST-AUDIT on `c17bcbe..06a39af`. Verified by reading the row.

### 2. The `curate-commit` invocation snippet dereferences a driver that may not exist

- **Where:** `agy-autotrain/skills/agy-curate/SKILL.md`, the publish snippet - `$exe = (Get-Command clavity-ls -EA SilentlyContinue) ?? (Get-Command clavity -EA SilentlyContinue)` followed two lines later by `$psi.FileName = $exe.Source`.
- **The gap:** nothing between those two lines checks `$exe` for `$null`. Both lookups use
  `-EA SilentlyContinue`, so on a machine with no clavity driver on PATH both return nothing and the
  dereference throws.
- **Why it matters, and why it is not merely cosmetic:** the same file states the intended behaviour for
  exactly that case - *"If no clavity binary is on PATH, still compile and write `golden-header.growth.md`
  ... Do NOT hard-fail; the capture still has value."* The snippet an agent copies contradicts the
  instruction twelve lines below it, so following the guide produces the one outcome the guide forbids.
- **The regression that would slip through:** a user without the driver installed runs the curate flow,
  the snippet throws, and the run ends in the error state (1) rather than the not-published state (2) -
  mapping a deliberate, benign condition onto a fault.
- **The fix that should exist:** guard the dereference and branch to the documented no-driver path.
- **Deferred by the owner:** 2026-08-12, AGY-CAPSTONE round 2 on `90cb0b5..00e3291`. **Verified
  PRE-EXISTING:** `git diff 90cb0b5..00e3291 -- <that file>` shows the snippet as an unchanged line, so
  it predates the reviewed range. Raised by the peer, which then withdrew it from the capstone's scope on
  that evidence while maintaining the defect is real. Recorded here rather than fixed inside a batch
  scoped to other work.

---

## Accepted-boundary ledger - deliberately uncovered, do NOT re-raise

### A. The two walk-level guards (`2fa88e0`, `76e1ba8`)

- **Behaviour:** `Get-InjectedContextFiles` and `Get-UnexpectedBuildDirs` each seed their visited set with
  a guarded `Get-Item -ErrorAction SilentlyContinue`, falling back to the raw path. Without it, a domain
  root that disappears or locks between `Test-Path` and `Get-Item` throws through
  `$ErrorActionPreference = 'Stop'` and the gate exits by neither documented route.
- **Why uncovered:** no portable behavioural pin exists. Reproducing it needs either a `Get-Item` mock
  (fragile structural coupling) or a real delete-vs-walk race whose timing window is too narrow to be
  deterministic. Reached independently by capstone R20 and again by the AGY-TEST-AUDIT peer, which
  considered adapting the existing `Start-Job` junction-hang pattern and rejected it.
- **Compensation:** verified by direct manual control at fold time; the guard is a two-line fallback with
  no branching logic of its own.
- **Anchor:** the `$rootItem = Get-Item -LiteralPath $full -ErrorAction SilentlyContinue` lines in both
  functions. **If either loses its `-ErrorAction SilentlyContinue`, this entry is void and the gap is live.**

### B. `payload-budget` measures the template, not the interpolated result

- **Behaviour:** the invariant parses the hook message TEMPLATE. At runtime an interpolated value (e.g. a
  `git log` result) can push the delivered message over the budget.
- **Guarantee as written:** "no over-budget TEMPLATE ships" - NOT "no over-budget message reaches an agent".
- **Why uncovered:** bounding the interpolated result requires executing the hooks, which the gate does not
  and should not do.
- **Compensation:** documented in-source as an intended limit, adjacent to the check itself.
- **Anchor:** the comment block above the `payload-budget` emission in `check-injected-context.ps1`.
  **If that comment goes, the limit is no longer documented and this entry is void.**

### C. The junction / symlink / reparse-point / cross-root-alias family

- **Why uncovered:** unreachable on real inputs. Measured 2026-08-10: this tree contains zero reparse
  points, `git checkout` creates none, and a file symlink cannot be created on Windows without elevation.
  The only junctions that have ever existed here were created by this suite's own fixtures.
- **Compensation:** the walk fails CLOSED - an aliased file is audited more than once, never zero times -
  so no content reaches an agent unaudited even if the topology did occur.
- **Note:** the per-route subtraction asymmetry was ruled out of scope and documented as intended in
  `06a39af`. Re-raising this family is a wrong answer unless the reachability facts above change.

### D. `.iss` references are unresolvable by design (Stage 2, D1)

`$ShippedExtensions` in `scripts/check-injected-context.ps1` omits `iss`, so every `.iss` token is dropped
before reference resolution. A genuinely broken `.iss` reference will not be reported.

**Compensation:** installer content is packaging input, never injected context, so it is outside what this
gate is for. The two dead references that existed were rewritten (`commonmemory/ROADMAP.md:20-21`, `:31`)
so no deleted file is cited as a live backticked path.
**Anchor (its disappearance voids this entry):** the ABSENCE of `'iss'` from `$script:ShippedExtensions` in `scripts/check-injected-context.ps1`. Adding that extension is what would close this gap, so the entry must void when it appears. **Deliberately NOT the explanatory comment above `$AssertPrefixes`** - a comment can be reworded or deleted with the gate's behaviour completely unchanged, so anchoring there would void the entry while the `.iss` blind spot it documents remained exactly as it was.

### E. `ghidrust/crates/ghidrust-mcp/src/tools.rs` has zero automated coverage (Stage 2, D3)

19 `pub const DESC_*` blocks totalling roughly 12 KB of description text, delivered to every agent by MCP `tools/list` (all 19 verified wired into `server.rs`, not dead constants). `ghidrust/crates`
is not a domain root and is deliberately not being added: the encoding invariant exists for the Inno /
CP437 route, and these descriptions travel UTF-8 JSON-RPC over stdio, so adding the file would red-gate
correct content.

**Compensation:** accuracy hand-verified 2026-08-11 - all 19 documented tool names exist in
`ghidrust/crates/`, and all 5 tools the skill says will "dead-end" are genuinely absent.
**Re-check trigger: a tool is added or renamed.**
**Anchor (its disappearance voids this entry):** the ABSENCE of `ghidrust/crates` from `$script:DomainRoots` in `scripts/check-injected-context.ps1`. Adding that root is precisely what would close this gap, so the entry must void the moment it appears. Anchoring on the `DESC_*` block instead would anchor on something that exists as long as the file does and could therefore never void anything.

### F. Repo-vs-install drift is undetected (Stage 2, D2)

Nothing detects that a fix committed to the repo has not reached a user's installed tree. A CI check was
rejected: CI cannot see a user-machine artifact, so it would be green-by-absence - a guard that fails open.

**Compensation:** the backlog status enum now makes "fixed for the user" a distinct, required state
(`open | fixed-in-repo | released | wont-fix`), decided by commit ancestry against the latest release tag
rather than by guess. Escalation path if this recurs: an **install-time** diagnostic inside the installer,
which reaches the user rather than CI.
**Anchor:** the `status:` enum line in `agy-autotrain/docs/fix-the-tool-backlog/_template.md`.

### G. commonmemory's agy-native recall rule is never verified to load (Stage 2, R5-O2)

`commonmemory/rules/commonmemory.md` is audited as injected context, but `commonmemory/README.md:22`
and `:77` annotate it "agy-native proactive-recall rule (Claude ignores it)", and `:57-58` leaves the
loading mechanism unconfirmed - "if your agy auto-applies plugin `rules/` ... verify once". Neither
manifest declares a `rules/` surface, and that "verify once" appears never to have happened. Whether
commonmemory's core recall mechanism fires for agy at all is unknown.

**Compensation:** the failure mode is inert, not wrong - a rule that never loads is a no-op, not an
incorrect action. The gate auditing it anyway is fail-safe over-coverage.
**Re-check trigger: the next time a live agy peer is reachable.** Closing this needs an empirical test
against a live agy, which is out of scope for a doc-and-test batch.
**Anchor:** the "verify once" sentence at `commonmemory/README.md:57-58`.

### H. The backlog `status:` enum has no durable enforcement (Stage 2, D2)

D2 replaces `open | fixed | wont-fix` with `open | fixed-in-repo | released | wont-fix`, and requires
`released-in:` alongside `released`. **Nothing enforces either.** Measured 2026-08-11: several scripts read
`agy-autotrain/docs/fix-the-tool-backlog/` (`drain-lib.ps1`, `abort-drain.ps1`, `check-user-facing-docs.ps1`,
the injected-context gate) but **no test asserts a `status:` value is in the enum**, and none checks that a
`released` item carries `released-in:`. A future item typed `fixed-in-repos`, or marked `released` with no
version, passes every gate.

This is the exact defect shape F1 addresses elsewhere in this batch: a stated rule with no mechanism drifts,
and the drift is invisible because the file still looks well-formed.

**Compensation:** the batch's own backfill is verified at execution time - Task 2 Step 8 asserts the exact
population (`4x released, 3x fixed-in-repo, 1x wont-fix, 1x open`, no bare `fixed`), so the *current* state
is known-good. What is missing is a guard against the *next* edit. The `_template.md` enum line carries the
rule and the measurable ancestry test for deciding `released`, so an author following the template is
steered correctly.
**Re-check trigger: the next time an item is added or its status changed.** Closing it means a Pester row
over that directory asserting the enum and the `released` -> `released-in:` pairing - deliberately not done
here, because it needs a new registered suite and this batch's scope is the seventeen findings.
**Void condition (stated, deliberately NOT a pattern-match):** this entry is closed when **a registered Pester suite asserts the `status:` frontmatter of `agy-autotrain/docs/fix-the-tool-backlog/*.md`** - the permitted values, and the `released` -> `released-in:` pairing. Whoever adds that assertion closes this entry BY HAND, in the same commit.

**Re-check trigger:** the next time an item is added to that directory or its status changed. Verify with `rg -n '^status:' agy-autotrain/docs/fix-the-tool-backlog/*.md` and confirm no registered suite asserts those values.

> 🔴 **This entry has no mechanical anchor, and that is the finding rather than an omission.** Three were tried and each was defeated by an ordinary edit:
>
> | attempt | defeated by |
> |---|---|
> | the ancestry-rule **comment block** in `_template.md` | moving that paragraph into a contributing guide |
> | the **ABSENCE of the tokens** `fixed-in-repo` / `wont-fix` from any suite | one comment - `# we wont-fix this edge case` - anywhere in `scripts/tests/` |
> | the **ABSENCE of a `backlog-*.Tests.ps1`** registered suite | naming an unrelated suite `backlog-parser.Tests.ps1` |
>
> Every one was a proxy looser than the condition it stood for, and each failed the same way: **it would have voided the entry while the gap stayed wide open.** The pattern is the lesson - "no enforcement exists anywhere" is a claim about behaviour that no filename or string test can express, so a fourth proxy would fail too.
>
> **The two failure directions are not equally bad, and that is what settles it.** A too-loose anchor VANISHES while the gap remains, silently and with nobody looking. A stated condition plus a re-check trigger can only LINGER - it stays until a human closes it, and a stale entry is something a reader notices and deletes. **An anchor that overstays is a chore; an anchor that disappears early is a lie.** Prefer the honest manual condition over an automatic one that is quietly wrong.

> **Why not the `_template.md` comment block, which this entry originally named.** Entry D above states the rule directly - *"a comment can be reworded or deleted with the gate's behaviour completely unchanged, so anchoring there would void the entry while the blind spot it documents remained exactly as it was"* - and this entry then anchored on a comment block anyway. Moving that paragraph into a contributing guide, an ordinary tidy-up, would have voided the entry while the absent enforcement stayed exactly as absent. It also resolves the original concern that drove that choice: it does not collide with entry F's anchor (the `status:` enum line), because absence-of-a-test and presence-of-an-enum-line are different facts that no single edit changes together.

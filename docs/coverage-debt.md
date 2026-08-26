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

### 3. The `agy-curate` skill's exit-code, dirty-path and routing contracts have no test at all

- **Where:** `agy-autotrain/skills/agy-curate/SKILL.md` - the exit table at `:278`, the cross-cutting
  dirty-path rule ("READ THIS BEFORE THE BRANCHES BELOW"), and the routing rule at `:121`.
- **The gap:** nothing asserts any of it. `scripts/tests/check-agy-discipline-skills.Tests.ps1` resolves
  its targets under `clavity-dotnet/plugin/skills/<skill>/SKILL.md` (`:15`, `:20`, `:209`, `:223`) and
  never reaches `agy-autotrain/skills/`. This is the single largest change in the batch - 152 lines
  matured over fifteen adversarial rounds - and it is entirely unguarded.
- **NOT the regression:** the audit peer first stated this as "silently breaking the downstream hook
  scripts that parse these values". **Measured, twice: nothing parses them.** `agy-curate-nudge.sh` and
  `agy-inbox-snapshot.sh` match on the skill NAME only. The peer withdrew that wording when asked to
  name a consumer.
- **The regression, stated in two phases because the second half does not exist yet:**
  1. **Today** the STDERR warning is the ONLY mitigation, precisely because the pre-commit guard below
     was deliberately not built. If the dirty-path predicate drifts, the executing agent emits the wrong
     warning or none at all, and the operator is told nothing about unreviewed machine-generated content
     sitting in the working tree.
  2. **Once the guard in `docs/backlog/curate-abort-leaves-unreviewed-content-with-only-a-warning.md`
     ships**, it will be keyed on this same predicate, so the same drift additionally fails to arm the
     marker and the guard fails open.
  **Do not restate this as "the lefthook guard fails open" alone** - `lefthook.yml` exists but carries no
  curate/marker/abort hook, so that phrasing describes a mechanism that is not there.
- **The consumer is the executing agent, not a script.** That is what makes the drift reachable: this
  document IS the program, and the file itself enumerates FIVE previously-rejected formulations of the
  dirty-path rule, two of which mutually reverted. Drift here is demonstrated, not hypothetical.
- 🔴 **NO MECHANICAL TEST FORM SURVIVES, AND THAT WAS MEASURED RATHER THAN ASSUMED.** A text pin was
  proposed (assert the literal exit-code rows remain in the file) and rejected: `.Contains` searches RAW
  markdown, so wrapping the real table in `<!-- ... -->` above a drifted live table keeps the assertion
  green. This is the same class already recorded at `scripts/tests/check-cheatsheet-budget.Tests.ps1:47-52`,
  where two text-matching forms were defeated and a 6000-byte file passed while the row stayed green.
  **Same shape as accepted boundary H below: a stated manual condition beats a proxy anchor looser than
  the condition it stands for.**
- **Re-check trigger:** any edit to the exit table, the dirty-path rule, or the routing rule in that file.
- **Deferred by the owner:** 2026-08-12, AGY-TEST-AUDIT on `90cb0b5..a3ce038`.

### 4. The hook-population walk fails OPEN where the gate it tests fails CLOSED

- **Where:** `scripts/tests/check-injected-context.Tests.ps1:1279-1283` - the `BeforeAll` of the
  `hook message extraction reaches every emitting hook` context builds its own file list with
  `foreach ($root in $script:DomainRoots) { ... if (Test-Path $dir) { Get-ChildItem ... } }`.
- **The gap:** that `if (Test-Path $dir)` **silently skips** a domain root that has moved or been renamed.
  The gate it tests does the opposite deliberately - **measured** with a control that asserts its own
  precondition (`CONTROL A -> RAN=yes FILES=1 THREW=no`, `CONTROL B -> THREW=YES`): discovery raises
  `domain root missing: <path> - if a product moved or was renamed, update $script:DomainRoots`. That
  closed-failure design is documented in prose at `:756-764` of this same file.
- **The regression that would slip through:** the non-vacuity guard at `:1286` asserts the population is
  `-BeGreaterThan 20`. **Measured population is 31, unevenly spread:** `clavity-dotnet/plugin` 13,
  `clavity-classic/plugin` 14, `agy-autotrain` 4, and the remaining six roots contribute ZERO. So losing
  either large root reds the guard (18, 17), but **losing `agy-autotrain` (4 -> 27) does not** - and that
  is the root most actively edited here.
- **Why this is LOW and not High:** the audit peer rated it High on the claim that dropped hooks "evade
  all budget/hygiene audits". They do not - sibling rows in this file call discovery, which throws, so a
  missing root reds the suite elsewhere and the corpus never silently shrinks. What remains is a real
  inconsistency in one block's helper, compensated by those rows.
- **The test that should exist:** `every domain root contributes to the hook population` - assert
  per-root that a root either yields at least one `.sh` or is on an explicit known-empty list, rather
  than asserting a single aggregate floor. Closing it means deciding what to do about the six roots that
  legitimately hold no hooks today, which is why it is not a one-line fix.
- **Deferred by the owner:** 2026-08-12, AGY-TEST-AUDIT round 2 on `90cb0b5..a3ce038`.

---

### 5. `check-cheatsheet-parity.ps1`'s CRLF-agnostic guard cannot be told from a byte compare

- **Where:** `scripts/check-cheatsheet-parity.ps1:179` -
  `& git -C $RepoRoot diff --quiet -- $Core          # worktree vs index, CRLF-agnostic. NEVER a byte compare.`
- **The gap:** no test can distinguish that call from a byte comparison, because the suite's own fixture
  sets `core.autocrlf false` (`scripts/tests/check-cheatsheet-parity.Tests.ps1:23`), which **eliminates the
  worktree-CRLF/index-LF condition the guard exists for**. MEASURED 2026-08-16 by replacing the call with a
  byte comparison: the full suite stayed **16/16 green**.
- **The regression that would slip through:** someone "simplifies" the guard to a byte compare. On any
  developer machine with `core.autocrlf true` - the normal Windows setting, and what this repo actually uses -
  the gate then reports drift on every checkout of an LF-committed file.
- **Second-order:** the site is only reachable when `$mismatched.Count -gt 0` (early exit at `:169`), so the
  hot-fix plan's mutation table named rows 2/3 which **cannot reach it at all**.
- **The tension that makes this non-trivial:** the fixture sets `core.autocrlf false` deliberately, for
  determinism - FIXTURE HYGIENE, so a suite never inherits the host's setting. Closing this needs a SECOND
  fixture that deliberately sets `core.autocrlf true`, not a change to the existing one. A test that flips
  the shared fixture would trade this gap for a flakiness source.
- **Raised:** hot-fix batch Task 11 Step 7 mutation 7. **Promoted at the 2026-08-17 anomaly triage.**

---

### 6. The `BaseStream` index extraction is defensive for PowerShell 5.1 and has no oracle here

- **Where:** `scripts/check-cheatsheet-parity.ps1:46-64`, `Get-IndexBytes` /
  `$p.StandardOutput.BaseStream.CopyTo($fs)`.
- **The gap:** the byte-exact extraction exists to avoid Windows PowerShell 5.1's UTF-16LE default mangling
  the blob. **This script runs only under pwsh 7**, which MEASURED on 7.6.4 round-trips the probe byte
  losslessly (10 bytes -> 10, byte-identical) - so replacing the whole thing with a `ReadToEnd()` /
  `WriteAllText` text pipeline left row 12 **green**. The defensive choice is correct and **untested on the
  platform it defends against**.
- **The regression that would slip through:** the BaseStream handling is simplified away as "unnecessary
  complexity". Nothing reddens, because nothing here runs 5.1.
- **Why it is not a one-line fix:** an honest oracle needs the script exercised under Windows PowerShell 5.1.
  CI has a `installer-5-1` job, but it is scoped to `installer/_shared` - `scripts/**` is deliberately
  pwsh-7-only, and widening that scope re-introduces the mis-scoped contract that job was split to fix
  (it failed 9 containers on PS7-only syntax while never exercising the end-user surface).
- **Related, already documented in-source:** `:119-124` records a DIFFERENT unreachable pair - the two
  `Get-IndexBytes` failure branches, kept deliberately after capstone R4 measured that neutering both leaves
  the suite 16/0 green. That admission is about the failure branches; this entry is about the extraction
  mechanism itself.
- **Raised:** hot-fix batch Task 11 Step 7 mutation 9. **Promoted at the 2026-08-17 anomaly triage.**

---

### 7. The 6x timing widening on the two absolute-max tests is an open owner decision

- **Where:** `clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs`, the two
  `absolute_max` tests - `500ms/1500ms` and `1000ms/1500ms`, scaled up from `100ms/250ms` and `150ms/250ms`
  in `bcd4125`.
- **What it buys:** it is the mitigation for a REAL flake - `lastProbe` is null at `AgyView.cs:234` while
  the budget check at `:240-244` runs on the first iteration before any probe, so a pause longer than the
  whole budget throws a null diagnostic and fails `Assert.NotNull`. At a 250ms budget that needed only a
  quarter-second hiccup. Validated 12/12 on an idle machine after widening.
- **What it costs:** roughly 2s of wall-clock on EVERY green suite run (measured 14s -> 16s), permanently,
  for two tests. The capstone peer's RESOURCE VAMPIRE seat argued this scales badly if the pattern is
  copied to the next timing-bound test, and that argument is sound.
- **The alternative, and its trap:** restore the fast budgets and retry the ask when it exits before any
  probe. A retry is honest ONLY for that precondition failure. It must never cover a wrong `Limit`, which
  would be retrying until the assertion passes - a test that cannot fail. Any implementation must keep
  those two cases visibly separate.
- **Status:** owner deferred the decision on 2026-08-19, after the limit-label fixes, on the grounds that a
  deterministic boundary changes what the margins must absorb. **It does not: this flake is the
  pre-first-probe starvation case, which neither `0fb47f6` nor `1748754` touches.** Recorded here so the
  decision is tracked rather than carried in conversation.

---

### 8. The AGGREGATE figures in `_partition.md` are unguarded, and have decayed three times

- **Where:** `scripts/tests/_partition.md`, the `just test-scripts-fast` / `just test-scripts-slow`
  bullets near the top that state "N suites, M tests, <runtime>".
- **The gap:** `scripts/tests/test-suite-registration.Tests.ps1` guards the per-suite rows of the fenced
  table and nothing else. MEASURED 2026-08-25 in a sandbox with BOTH controls: unmutated the suite is
  8 passed / 0 failed; falsifying one TABLE ROW reds exactly `every _partition.md row states the CURRENT
  test count for its suite`; but `407 tests -> 999 tests`, `25 suites -> 3 suites` and
  `492,9s warm -> 5,0s warm` each pass 8/0 with nothing red.
- 🔴 **This is a GAP, not a defect in the guard.** `test-suite-registration.Tests.ps1:246-249`
  scopes to the fenced table DELIBERATELY and records why: an unscoped first-match-wins parse let a prose
  line 77 lines above the fence supply the count, and the real row was then never compared at all.
  Widening the row regex back into prose would re-open that measured defect.
- **The regression that would slip through:** the aggregate drifts from the recipe it describes and no
  test notices. This is not hypothetical - this file's own history records the aggregates decaying three
  separate times, and the aggregate is the line a reader actually reads.
- **The test that should exist:** a SEPARATE assertion (not a wider row regex) that parses the two
  aggregate bullets and compares the suite count against the justfile recipe parse and the test count
  against the discovery total the census row already computes.
🔴 **IT DECAYED AGAIN ON 2026-08-26, exactly as this entry predicted.** Five folds added tests.
  The per-suite ROW guard caught two drifted rows and went RED; this aggregate silently went 407 -> 411
  with nothing red at all. The gap is no longer hypothetical - it was demonstrated by the very work
  going on while the entry sat open, which is the strongest argument available for closing it.
- **Deferred by the owner:** 2026-08-25, AGY-CAPSTONE round 7 on `f29cd42..a1ad1d1`. Verified by
  sandboxed mutation with a passing and a failing control.

### 9. The migration's ENCODING fix has only a structural pin, never a behavioural one

- **Where:** `agy-autotrain/installer/agy-autotrain.iss` (`LoadStringFromFile`/`SaveStringToFile` in
  `MigrateInboxToUserState`), guarded by `scripts/tests/agy-autotrain-installer.Tests.ps1`.
- **The gap:** the guard asserts the singular byte-oriented CALL IS PRESENT. It does not assert that a
  non-ASCII byte SURVIVES. Any change that re-encodes while still using a call of that name passes.
- **The regression that would slip through:** the exact defect fixed in `1b2f7b7` - an em-dash entering
  as UTF-8 `e2 80 94` and leaving as the Windows-1252 byte `97`, which PowerShell then renders as
  U+FFFD. MEASURED on the live inbox: **138 non-ASCII lines** would be destroyed, while the bullet count
  and the `^- \[` anchor stay correct so nothing notices.
- **The test that should exist:** a behavioural step in the migration smoke that plants a known
  multi-byte marker in the pre-migration inbox and asserts the post-migration file contains those exact
  bytes. The reproduction is already written and proven: a no-`[Files]` probe installer that aborts in
  `InitializeSetup` exercises the real Pascal pair and installs nothing.
- **Why it is NOT being added here:** it belongs in a CI workflow that cannot be executed locally, and
  an assertion nobody can run before merging is how round 1's smoke defects got in - a poll that could
  never fail red. Owner to scope.
- **Raised:** 2026-08-26, AGY-CAPSTONE round 14, stop-condition seat.

### 10. The PURGE destruction path is structurally asserted and behaviourally unreachable in CI

- **Where:** the migration smoke in `.github/workflows/build-agy-autotrain.yml`; the gate itself at
  `agy-autotrain/installer/agy-autotrain.iss` under `if RemoveGrowth then`.
- **The gap:** a silent uninstall defaults the consent prompt to IDNO, so CI always takes the KEEP path.
  The reviewer put it exactly: **removing the `DeleteFile` calls from the purge gate entirely would
  leave the smoke green.** Deletion on consent is asserted structurally and never once executed.
- **The regression that would slip through:** any change that stops the purge deleting - including the
  two paths added in `f06fb3e` and the census that pins them, all of which assert TEXT, not behaviour.
- **Note:** the structural census added in `f06fb3e` is real coverage and is not being double-counted
  here; the gap is that nothing runs the branch.
- **Raised:** 2026-08-26, AGY-CAPSTONE round 14, unrun-guard and stop-condition seats agreeing.

## Accepted-boundary ledger - deliberately uncovered, do NOT re-raise

🔴 **Letters are assigned in CAPTURE order and are NOT alphabetically sorted - do not "tidy" them.**
They are cited by letter from outside this file (`docs/agy-capstone-ledger.md` cites boundary D and
boundary J; the entry below cites boundary H), so renaming one silently redirects a citation. Until
2026-08-25 TWO entries were lettered **D**, which made `agy-capstone-ledger.md:61`'s "accepted boundary D"
ambiguous; the second was renamed to **K** because the citation means the SemanticEcho entry. Append the
next free letter; never re-letter an existing entry.

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

### A2. `agy-learn-reminder.sh`'s `${USERPROFILE:-$HOME}` fallback has no separately-reachable regression

- **Behaviour:** all three agy-autotrain hooks resolve `HOME_DIR="${USERPROFILE:-$HOME}"`. The
  AGY-TEST-AUDIT of `bd3aa94..f29cd42` raised the missing absent/empty-`USERPROFILE` coverage against all
  three. It is a real gap in `agy-curate-nudge.sh` and `agy-inbox-snapshot.sh`, where `HOME_DIR` locates
  the INBOX - dropping the fallback there sends both hooks permanently silent, and both are now covered.
- **Why this one is different:** in `agy-learn-reminder.sh`, `HOME_DIR` is used at exactly ONE site
  (`:27`), inside an OR'd kill-switch condition that already tests bare `${HOME}` on the same line. It
  locates no file of its own. Losing the fallback can therefore only make the switch LESS likely to fire,
  and the bare-`${HOME}` clause beside it catches the marker anyway.
- **MEASURED 2026-08-24:** with `USERPROFILE` absent and a marker under `HOME`, the unmutated hook is
  silent and the mutant (`HOME_DIR="${USERPROFILE}"`) is EQUALLY silent. Control: with no marker at all
  both speak, so the fixture is live and the agreement is real rather than a broken probe.
- **Compensation:** the bare-`${HOME}` clause on the same condition, plus the three existing tests that
  already cover every reachable marker cell for this hook (`HOME` root, `USERPROFILE` root, payload cwd).
- **Anchor:** the third clause of the condition at `agy-learn-reminder.sh:27`,
  `[ -f "${HOME}/.claude/.no-agy" ]`. **If that clause is removed, `HOME_DIR` becomes the only resolver
  for the marker, this entry is VOID, and the gap is live** - write the absent/empty test then.
- **Not to be confused with:** the kill-switch WIDENING sweep still outstanding for the other plugins'
  hooks. That is a different defect (a bare `$HOME` with no `HOME_DIR` companion at all) and is unaffected.

### B. `payload-budget` measures the template, not the interpolated result

- **Behaviour:** the invariant parses the hook message TEMPLATE. At runtime an interpolated value (e.g. a
  `git log` result) can push the delivered message over the budget.
- **Guarantee as written:** "no over-budget TEMPLATE ships" - NOT "no over-budget message reaches an agent".
- **Why uncovered:** bounding the interpolated result requires executing the hooks, which the gate does not
  and should not do.
- **Compensation:** documented in-source as an intended limit, adjacent to the check itself.
- **Anchor:** the `WHAT THIS BUDGET ACTUALLY BOUNDS` comment block in `check-injected-context.ps1`,
  whose load-bearing sentence is *"Static parsing measures the TEMPLATE, not the payload an agent
  receives."* **If that comment goes, the limit is no longer documented and this entry is void.**
  <br>*(Corrected 2026-08-17, AGY-TEST-AUDIT round B prep: the anchor previously read "the comment block
  above the `payload-budget` emission". It is not - the emission is far below it, and the only
  `payload-budget` text near that point is an unrelated mention in the extraction-convention comment. A
  re-validator following the old pointer would have looked in the wrong place and could have voided a
  live entry, or honoured a dead one. Naming the block by its heading text survives the line moving.)*

### D. `SemanticEcho.ExpectedFrom`'s two file-read guards are not SEPARATELY testable

**What is uncovered.** `ExpectedFrom` opens a caller-supplied path and carries three guards: `File.Exists`
(regular files only), a handle check (`CanSeek` + `Length` on the OPEN stream), and a read budget. No
in-process test can distinguish them, and one intended assertion was measured VACUOUS.

**Measured, 2026-08-20, capstone R10:**
- Dropping the handle check alone: suite stays GREEN (the budget catches the same file).
- Dropping the budget alone: suite stays GREEN (the handle check catches it first).
- Dropping BOTH: `ExpectedFrom_refuses_an_artifact_larger_than_the_cap` goes RED.
  So the pair is a **multi-guard regression target** - defense-in-depth, not vacuity.
- Dropping `File.Exists` and asserting on a DIRECTORY: **stays GREEN**. Opening a directory throws
  `UnauthorizedAccessException`, the catch swallows it, and the method returns `null` - the same answer
  the guard produces. That assertion could never fail, so it was DELETED rather than left as decoration.

**Why it is not covered.** The remaining discriminators are a hang and a race, and neither belongs in a
unit suite: `File.Exists` exists to stop a pipe or console device BLOCKING the ask forever, and a test
that proves it would have to hang to fail. The budget covers a file that grows under another writer,
which needs a concurrent appender to reproduce.

**Compensation.** The over-cap row pins the pair jointly; the three guards are each documented in
`SemanticEcho.cs` with the measurement that justifies them; and every failure route in that method
returns `null`, so the check degrades to skipped rather than to a wrong answer.

**A SECOND masking pair in the same method, measured 2026-08-20 (capstone R11).** The reader splits lines
itself with a capped line buffer, and separately refuses a line that HIT the cap as an echo candidate.
Removing the buffer cap alone leaves the suite GREEN - the whole line gets buffered, and the truncation
check rejects it anyway, producing the same answer. Removing the truncation check alone goes RED.
So the observable behaviour is pinned, but the CAP's real purpose - bounding MEMORY when a writer appends
without ever emitting a newline - cannot be asserted without actually exhausting memory in a unit test.

**Compensation.** The observable answer is pinned by
`A_single_ENORMOUS_line_is_bounded_and_never_becomes_the_echo_target` plus its passing control
`A_normal_line_after_an_enormous_one_is_still_found`; the memory bound is a structural property of a
fixed-size buffer that is visible by reading twenty lines of code.

**Anchor:** `clavity-dotnet/src/Clavity.Ls/SemanticEcho.cs` - `ExpectedFrom`.

### C. The junction / symlink / reparse-point / cross-root-alias family

- **Why uncovered:** unreachable on real inputs. Measured 2026-08-10: this tree contains zero reparse
  points, `git checkout` creates none, and a file symlink cannot be created on Windows without elevation.
  The only junctions that have ever existed here were created by this suite's own fixtures.
- **Compensation:** the walk fails CLOSED - an aliased file is audited more than once, never zero times -
  so no content reaches an agent unaudited even if the topology did occur.
- **Note:** the per-route subtraction asymmetry was ruled out of scope and documented as intended in
  `06a39af`. Re-raising this family is a wrong answer unless the reachability facts above change.

### K. `.iss` references are unresolvable by design (Stage 2, D1)

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

> ⚠ **RE-VALIDATED 2026-08-19 AND THE COMPENSATION IS PRESENT BUT INOPERATIVE.** The anchor holds in the
> REPOSITORY - `_template.md:6` reads `open | fixed-in-repo | released | wont-fix`. The INSTALLED tree still
> carries the superseded three-state `open | fixed | wont-fix`. So the four-state enum, which exists
> specifically because a 2026-08-11 incident had an installed tree missing a hook whose item read
> `status: fixed` (that rationale is written into the template itself), **has not itself reached the
> install** - the fix for repo-vs-install drift is subject to repo-vs-install drift. Measured the same day:
> the installed `agy-curate/SKILL.md` is 276 lines against the repository's 518, under an identical
> `"version": "0.4.0"` on both sides, so nothing on either side can detect the gap.
>
> This entry is therefore **honoured on its anchor but weakened in substance**, and it is recorded here
> rather than silently re-raised: the compensation is real, it is simply not where it needs to be. The
> underlying drift is captured as an untriaged anomaly (`.clavity/local-anomalies.md`, 2026-08-19,
> `[tool]`). **Promote this to a live gap if a triage decides the install-time diagnostic named in the
> escalation path above is the answer.**

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
the injected-context gate)
🔴 **- and that sentence was FALSE when written, corrected 2026-08-25.** Only
`check-user-facing-docs.ps1` used the agy-autotrain-rooted path; `Get-DrainOutputPaths` in `drain-lib.ps1`
named the UMBRELLA-rooted `docs/fix-the-tool-backlog`, which matches zero tracked files, and `abort-drain.ps1`
inherited it through that single source of truth. Both are fixed; the sentence is true now but **no test asserts a `status:` value is in the enum**, and none checks that a
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

### I. The UNC volume-root walk terminator (`agy-discipline-reaching.sh:75`)

- **Behaviour:** the repo-root walk stops early at a UNC volume root -
  `case "$_d" in //*/*/*) ;; //*) break ;; esac` - so it never stats `//server/.git`, a path that cannot
  be a repository and costs another SMB round-trip to ask about.
- **Why uncovered:** the walk is gated at `:69` by `[ -d "$cwd_path" ]`, so reaching line 75 at all
  requires an **existing** directory under a `//` root. **Measured 2026-08-17:** `//localhost/c$` is
  reachable on this developer box, but `New-SmbShare` returns *"Access is denied"* without elevation and
  `//wsl.localhost` is absent - so a row would depend on the runner being an SMB server, or on admin
  rights, and would not run on `windows-latest`. Same class as entry C: the fixture, not the assertion,
  is what needs privileges this suite does not have.
- **Why LOW, and this is the part that settles the disposition:** deleting line 75 costs **latency, not
  correctness**. Measured 2026-08-06 and recorded in the source at `:65-68`: 20314ms walking an
  unreachable `//server/share/a/b/c` versus 9282ms gated. Nothing is mis-recorded and nothing leaks; the
  hook is registered with a `timeout`, so the worst outcome is a session start that is slow or killed -
  loud, and attributable. Contrast the shield branches in this same file, where a regression is silent.
- **Compensation:** the walk's *other* termination conditions are covered - `writes NOTHING and creates
  no directory when cwd has no .git ancestor` exercises the loop running to exhaustion - so a regression
  that broke termination generally, rather than the UNC case specifically, still reddens the suite.
- **Condition rather than an anchor** (per the guidance above - an anchor that disappears early is a
  lie): **this entry is void if the walk stops being gated on `[ -d "$cwd_path" ]`**, which is what makes
  the branch unreachable from a synthetic path, **or if CI gains a runner where a UNC path is mountable
  without elevation.** Either change makes an honest row writable, and it should then be written.
- **Raised by:** AGY-TEST-AUDIT round A on `8a2c2dc..69b1c86` (peer severity High; downgraded to Low on
  the latency-versus-correctness measurement above). Accepted as a boundary 2026-08-17.

### J. `windowElapsed`'s knife-edge protection cannot be pinned by a test (AGY-TEST-AUDIT 2026-08-19)

- **Behaviour:** the idle-wait limit label branches on
  `windowWasBudgetClamped && (windowElapsed || (DateTime.UtcNow - start) >= absoluteMax)`
  in `clavity-dotnet/src/Clavity.Ls/AgyView.cs`. The `windowElapsed` disjunct exists so the knife-edge case
  - a budget-clamped window that our own timer ran to its end - is decided WITHOUT reading the clock.
- **Why uncovered:** every case a test can construct deterministically ALSO satisfies the clock check, so
  removing `windowElapsed` changes no test outcome. **Measured: mutant M9 (drop `windowElapsed`, leave only
  the clock) SURVIVES the full suite**, while the other nine mutants in that sweep are each caught by their
  specific intended test. The only scenario where the two disagree is an early timer wakeup, which cannot be
  produced on demand.
- **Compensation:** the reason the disjunct exists is a MEASUREMENT rather than an argument. Instrumenting
  the decision point over 10 runs / 50 decisions gave a worst-case margin of **+5.1 ms** between the clamped
  window ending and the clock agreeing the budget was spent, against Windows' ~15 ms timer resolution. That
  margin is the defect; `windowElapsed` removes the dependence on winning that race. The adjacent cases ARE
  pinned - M6 (clamp alone decides) and M8 (drop the budget-spent disjunct) are both caught - so only this
  one sub-condition rests on the measurement.
- **Anchor (its disappearance voids this entry):** the `windowElapsed ||` term in that condition. If the
  condition is ever reduced to the clock alone, the original mislabel is back and this entry is void, not
  satisfied. **Re-check trigger:** any change to the wait loop's limit-label branch, or the arrival of a
  mockable clock (`TimeProvider`) in `AgyView`, which would make the case constructible and retire this
  entry outright.

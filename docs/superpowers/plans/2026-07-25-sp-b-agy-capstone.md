# SP-B agy-capstone Discipline Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `agy-capstone` - a manually-invokable discipline skill, byte-identical in both driver plugins - that runs a convergent, rounds-until-green review of already-COMMITTED code before the driving agent may declare a plan COMPLETE, and mechanically enroll it in the SP-A lint / seed-sync / marker-contract / Pester machinery.

**Architecture:** Self-contained skill (parent Decision 4; spec "Structural decision"), mirroring the shipped `agy-first` skill's shape and reusing its four ASCII `[VERDICT]` tokens verbatim - NOT a delegator to `adversarial-panel-review`. The peer reviews and cites file:line; the driver measures every finding before folding (single, driver-side execution cost). Enrollment is a mechanical extension of the SP-A arrays: the lint already carries the `# SP-B appends 'agy-capstone'` seam.

**Tech Stack:** Markdown skill file (ASCII-only), PowerShell lint + Pester tests, bash seed-sync gate, `just` recipes (`check-agy-skills`, `seed-sync-check`, `test-scripts`).

**Governing spec:** `docs/superpowers/specs/2026-07-25-sp-b-agy-capstone-design.md` (committed `4ba0114` + `a9e559b`; AGY-AFTER panel-GREEN, owner-approved). Baseline: SP-A on local `main` (`58607ee`), 42 commits unpushed.

**Owner-confirm (spec plan-gap):** `MAX_CAPSTONE_ROUNDS` default is set to **`3`** in the SKILL.md below, matching `adversarial-panel-review`'s round-3 halt-and-ask precedent and parent Decision 2b (tunable). The spec flagged this to confirm in-plan; it is surfaced in the handoff for the owner to override.

---

## File Structure

| File | Create/Modify | Responsibility |
|---|---|---|
| `clavity-dotnet/plugin/skills/agy-capstone/SKILL.md` | Create | The capstone discipline skill (lint-checked copy). |
| `clavity-classic/plugin/skills/agy-capstone/SKILL.md` | Create | Byte-identical copy (marketplace discovers skills only from a committed dir). |
| `scripts/check-agy-discipline-skills.ps1` | Modify (line 13) | Add `'agy-capstone'` to `$skills`. |
| `scripts/tests/check-agy-discipline-skills.Tests.ps1` | Modify (rewrite fixtures) | Stage BOTH skills per rejection fixture; add `agy-capstone` pinning tests. |
| `scripts/check-seed-artifacts-synced.sh` | Modify (line 10-15 loop) | Enroll `skills/agy-capstone/SKILL.md` in byte-identity gate. |
| `docs/agy-disciplines-marker-contract.md` | Modify (Rules + log) | Document capstone's terminal-state write trigger + WAIVED / UNVERIFIED-ACCEPTED audit lines. |

The lint inspects only the **dotnet** copy (`check-agy-discipline-skills.ps1:27`); the classic copy's correctness is enforced solely by seed-sync byte-identity - so both copies must be created together and the seed-sync loop must enroll the new pair.

---

### Task 1: Author `agy-capstone/SKILL.md` (both plugins) + enroll in the lint

**Files:**
- Create: `clavity-dotnet/plugin/skills/agy-capstone/SKILL.md`
- Create: `clavity-classic/plugin/skills/agy-capstone/SKILL.md`
- Modify: `scripts/check-agy-discipline-skills.ps1:13`

- [ ] **Step 1: Create the dotnet copy of `SKILL.md`**

Create `clavity-dotnet/plugin/skills/agy-capstone/SKILL.md` with EXACTLY this content (ASCII only - no em-dash, no smart quotes; the lint's non-ASCII gate will reject any Unicode):

````markdown
---
name: agy-capstone
description: Use ONLY before declaring a plan or implementation COMPLETE - never on routine intermediate commits. Runs a convergent, rounds-until-green adversarial review of the already-COMMITTED code (executable code + tests, not the plan artifact): the peer reasons and cites file:line, the driver measures every finding before folding. A hard round cap plus human-adjudicated GREEN gate the completion claim. Ends with one ASCII [VERDICT] token. Best-effort prompt-discipline, manually invokable; auto-fire is added separately.
---

# agy-capstone - tear down the committed code before you call the plan done

## When to use
Invoke this skill at exactly one moment: **before you declare a plan or implementation COMPLETE.** Its
job is to catch **reachable behavioural defects in the code that actually shipped** - the class a
pre-execution spec/plan review structurally cannot, because that review never runs the code. Review the
**committed implementation** (the executable code and its tests), never the plan artifact.

Do **not** fire it on routine intermediate commits mid-plan - that traps you in premature completion
breakpoints and burns a redundant paid review. One capstone per completion, on the range the plan
produced.

This is **best-effort prompt-discipline, not a sandbox.** The `[VERDICT]` token below is self-reported;
its forcing functions make hollow compliance visible to your human - do not make it impossible. The bar
is "materially better than shipping un-reviewed," not determinism.

Works with or without superpowers - superpowers only adds the auto-fire and the completion breakpoint
where the human adjudicates GREEN. You can always invoke this skill directly; when you do, **surface
every round, finding, and GREEN adjudication to your human in-chat** (there is no breakpoint to defer
to).

## Transport (resolve to your own plugin)
Send every round's consult over your driver's review-ask transport, review-only:
- **clavity-dotnet:** the `agy_ask` MCP tool, after an `agy_status` idle-check (do not fire while the
  peer is busy).
- **clavity-classic:** `clavity ask --review-only` (subagents use the CLI form, not the MCP bus).

## Safety envelope (every consult, no exceptions)
A bare "review-only" once let the peer write to the tree anyway. Wrap each round's consult:
1. **Snapshot before** - capture `git status --short` (and reflog, since the capstone reviews committed
   work).
2. **Forbidden-actions banner** - state in the payload: "REVIEW-ONLY. Do not edit, create, move, or
   delete any file. Do not run mutating commands. Respond with analysis only."
3. **Permission to pass** - the peer may decline or say it needs more; it must not act.
4. **Point at files, not summaries** - write the review brief + the exact commit range to
   `.clavity/seams/<topic>.md` and send the peer the PATH; let it read the committed diff itself. Never
   consult it on a pasted summary of your own reading. Any measure-and-reproduce framing MUST name a
   scratch dir (`.clavity/scratch/<topic>/`) for the peer to work in, so it never writes to cwd.
5. **Diff after** - re-check `git status` against the before-snapshot. If the tree changed, the peer
   breached review-only. Because the capstone is a **completion GATE**, a breach is handled more
   strictly than agy-first's advisory skip: (a) surface the breach loudly to your human; (b) revert
   **only the paths the peer touched** (diff the after-state against the before-snapshot and restore
   exactly those files) - **never** a blind `git reset --hard` / `git checkout -- .`, which would also
   destroy your own legitimate uncommitted work; (c) then **HALT-AND-ASK the human** - do NOT
   auto-proceed and do NOT emit `[VERDICT: SKIPPED-UNREACHABLE]` (that token is reserved for a genuine
   connectivity failure and auto-proceeds the gate; a breach must not silently pass "done"). The human
   decides: re-run the capstone cleanly, or explicitly waive (which writes the WAIVED audit line below).

## Review range (what the peer reviews)
Review the range of commits the just-finished plan produced: `<plan-base>..HEAD`. Resolve `<plan-base>`
from the plan's recorded start - the durable execution index or the plan doc; absent that (a cold manual
invocation), the merge-base with the integration branch, or the last release tag. State the resolved
range explicitly in the brief. Bind the peer's scope: review ONLY that diff, assume the surrounding code
is correct unless it is obviously flawed, no open-ended global discovery.

- **Exclude generated / vendored files.** Drop lockfiles, minified or generated assets, and generated
  manifests from the reviewed diff (a git pathspec `:(exclude)` or a documented exclude list). They are
  not human-authored behaviour; a large generated diff both buries real findings and can overflow the
  reviewer's context.
- **Re-extend the range after every fold.** Each round's folded fixes are themselves new committed code,
  so re-capture `HEAD` and extend the range to cover the fix commits. The final clean round MUST cover
  those fix commits before you may declare GREEN - otherwise you green a `HEAD` whose newest commits (its
  own fixes) were never reviewed. The marker records that post-fold reviewed `HEAD`.

## The convergent round (creative-adversarial teardown)
The loop converges (rounds-until-green), but the **defect discovery inside each round must be creatively
adversarial**, or the capstone degrades into a rote checklist that misses the non-obvious reachable
defect that is its entire reason to exist. Frame each round's consult with named adversarial seats +
forcing functions, not a flat "find bugs":

- **Seats (defect-class lenses).** Seat the proven adversarial-panel-review personas - Axiom Breaker
  (contradictions / unstated invariants), Cascade Analyst (unhandled failure paths), Mechanism Gamer
  (gameable gates / false-GREEN), Protocol Pedant (contract / serialization), State Corruptor, Boundary
  Smuggler, and the rest - pointing each at the COMMITTED CODE, seating those whose trigger the diff
  meets. Override with a sharper bespoke lens when the diff calls for it. This reuses the persona
  vocabulary; it is not a code dependency on the panel skill.
- **Forcing functions (creative, not checklist).** Each seated persona must produce a **reachable**
  defect citing **file:line** - invert the happy path (what input / state / sequence breaks this?), the
  hostile or malformed input, the concurrent / re-entrant / out-of-order case, the boundary / empty /
  zero / overflow case, a cross-domain failure analogy - never a contrived or exotic edge.
- **Reachability floor.** Stop nitpicking: a round producing only stylistic or contrived-edge
  observations - nothing touching correctness / safety / contract / completeness - counts as no live
  challenge.
- **Rotate seats across rounds.** Each additional round seats at least one lens not used in a prior
  round, so the loop surfaces NEW defect-classes instead of re-deriving covered ones.

Send the peer the committed range + this framing + the do-not-re-raise ledger; ask it to enumerate
reachable defects citing file:line. **Commit before the next round:** the peer reviews COMMITTED code, so
`git commit` every measurement-verified fold-fix BEFORE re-capturing `HEAD` and launching the next round
- a fix left uncommitted sends the peer the identical broken diff and it re-raises the defect.

Intermediate fold-and-loop rounds report progress and loop; they emit **no** token. You emit a
`[VERDICT]` token only at a terminal disposition or completion proposal (below).

## Division of labor: peer REVIEWS, driver MEASURES (the spine)
The peer must **never run the test suite** - execution is driver-side, once.
- **Peer role:** reads the committed diff and reasons - enumerates reachable defects, cites file:line,
  predicts what breaks under what input/state. It does not execute tests or the code.
- **Driver role:** for every peer finding, **you** run the relevant test / probe and **quote the measured
  stdout** (or the file line) that confirms or kills the finding *before folding it*. A fold with no
  quoted measurement is visibly hollow. The peer states false claims with full confidence; your
  measurement is what makes a fold safe.

**Unmeasurable findings.** If a finding can be neither run nor resolved by reading the cited line, FIRST
attempt a targeted repro/probe in the scratch dir (`.clavity/scratch/<topic>/`) to make it measurable. If
it is still genuinely unmeasurable, surface it to your human as **UNVERIFIED** - never silently fold it
as verified, never silently drop it. A material UNVERIFIED finding blocks a clean `[VERDICT: ALIGNED]`
until the human rules. The ruling is a **per-finding disposition, distinct from the global waiver below**:
either (a) direct a fix (folded next round), or (b) explicitly ACCEPT the risk, recorded as a durable
audit line (`<iso-8601>  agy-capstone  UNVERIFIED-ACCEPTED  HEAD=<sha>  <finding>`) that does NOT write
the completion marker and does NOT abort the capstone - the loop continues and can still reach ALIGNED.

## Do-not-re-raise ledger
Keep a running list of already-folded and already-refuted findings, and **inline it into every round's
brief** (the peer's context can truncate across a long review; a shorthand "see round 1" can point at
something it no longer holds). Ledger entries are plain factual findings, not your rationale.

## Round cap + human-adjudicated GREEN + override re-entry
- **`MAX_CAPSTONE_ROUNDS = 3` (tunable).** At the cap, **halt and ask your human** ("still finding
  substance at round 3 - continue or ship?") rather than looping or silently stopping.
- **GREEN is human-adjudicated** - you cannot self-declare it. A self-reported clean round is a proposal
  the human confirms or rejects at the superpowers completion breakpoint (or in-chat under manual
  invocation, which has no breakpoint).
- **Write on resume, not on the proposal.** Your session persists across the adjudication pause. AFTER
  the human confirms GREEN, resume and write the marker (below) as your next action; do NOT stop dead at
  the proposal, and do NOT write on an unconfirmed proposal.
- **Override re-entry.** If the human rejects a proposed GREEN or names an unaddressed defect, **re-enter
  capstone rounds on that defect** rather than closing the book. A human "continue" / re-entry answer
  AUTHORIZES that ordered work; the cap does NOT re-halt inside the authorized extension. The
  halt-and-ask re-triggers only if, after the authorized extension, findings are STILL live and no fresh
  override is given - so the ceiling holds without trapping you in an instant re-prompt loop.

## AGY-NEGOTIATE (auto-fires on material disagreement)
When a **material** disagreement (architecture / performance / security - never style / naming / trivia)
surfaces inside a round, run AGY-NEGOTIATE **immediately** - the moment a
`[VERDICT: NEGOTIATE - <reason>]` is emitted or you reject a peer finding you deem material. Do NOT wait
for the human to ask, and do NOT kick the raw disagreement to the human as a fork-question.
- **Round cap:** `MAX_NEGOTIATE_ROUNDS = 2`. Round 1: you present measured evidence, the peer counters.
  Round 2: you attempt a synthesis taking the best of both.
- **Impasse:** if not converged at the cap, declare IMPASSE, document both positions in-chat (each with
  its measured support), and hand the human the tie-break. Do not fabricate agreement.
- The human is brought in only on IMPASSE, or is shown the already-CONVERGED result. "negotiate with agy"
  stays a manual backstop.

## The [VERDICT] tokens (ASCII only, emitted by disposition)
ASCII only - no em-dash or other non-ASCII (mojibake risk; this project has hit corruption). You (the
driver) emit these, keyed to disposition, not a fixed count:
- `[VERDICT: ALIGNED]` - a **clean terminal round**: every finding across the run has a disposition -
  folded (fixed + measured clean), killed by measurement (`[VERDICT: REJECTED - ...]`), or explicitly
  human-accepted as an UNVERIFIED risk - and no material unrefuted defect remains. A run whose findings
  were ALL refuted-by-measurement IS `ALIGNED` (a peer hallucination you kill does not block completion,
  else "run until green" with an eager peer loops forever inventing fresh refuted findings). This
  PROPOSES completion; the human adjudicates GREEN. It **MAY RECUR** - if the human rejects it and you
  re-enter rounds, you propose `ALIGNED` again after the next clean round.
- `[VERDICT: REJECTED - <measured reason>]` - a **per-finding disposition**, not a terminus: a specific
  peer finding killed by your measurement, quoted and ledgered. It does NOT halt the loop; the run still
  terminates as `[VERDICT: ALIGNED]` once a round is clean.
- `[VERDICT: NEGOTIATE - <material reason>]` - a material disagreement remains at impasse; run
  AGY-NEGOTIATE above. A peer merely REPORTING defects is NOT this - that is the normal case you verify,
  fold, and loop on.
- `[VERDICT: SKIPPED-UNREACHABLE]` - the consult could not run (genuine connectivity failure only; below).

**GREEN is a human-adjudicated meta-state, not a token.** A terminal `[VERDICT: ALIGNED]` is a proposal;
GREEN is reached only when the human confirms the clean terminal round.

## If the peer is unreachable
No live peer / no auth / the idle-check never clears: emit `[VERDICT: SKIPPED-UNREACHABLE]` and
**proceed** - never hang, never hard-block "done". Make the skip loud and durable: (a) tell your human
in-chat that the completion **gate was skipped** and name the range it did not review; (b) create
`.clavity/agy-marks/` if absent (gitignored runtime state - a bare `>>` append would fail on a fresh
clone), then append one durable line to `.clavity/agy-marks/skipped.log`
(`<iso-8601>  agy-capstone  SKIPPED-UNREACHABLE  HEAD=<sha>`, where `<sha>` is `git rev-parse HEAD` or
the literal `none` if HEAD cannot resolve); (c) write NO consulted marker, so the next trigger retries.

**A review FAILURE is not an unreachable peer.** `[VERDICT: SKIPPED-UNREACHABLE]` is reserved for a
genuine connectivity failure. A review that fails because the diff is **too large to review** (context /
API overflow), or any other non-connectivity crash, is NOT that - treating it as skip-and-proceed would
let a diff-bomb silently BYPASS the completion gate. **Halt-and-ask the human** instead (chunk the
review, or the human decides); never auto-proceed.

## Debounce marker (hook contract - written here, read by the auto-fire hook)
Record the terminal state so the auto-fire hook (shipped separately) does not re-inject the capstone for
the same `HEAD`. Create `.clavity/agy-marks/` first if it does not exist.
- **Path:** `.clavity/agy-marks/agy-capstone.head` - a single discipline-keyed marker, no `<plugin-id>`
  prefix (Option S, as for agy-first: the byte-identical body cannot carry a per-plugin literal and the
  two drivers are mutually exclusive). See `docs/agy-disciplines-marker-contract.md`.
- **Content:** the output of `git rev-parse HEAD` at the terminal state, nothing else. If HEAD cannot
  resolve, skip writing the marker (the discipline re-fires next trigger - safe).
- **Written ONLY on the terminal state** - human-confirmed GREEN **or** explicit human waiver. A
  self-declared round-ALIGNED not yet confirmed, an override re-entry still in progress, or a
  `[VERDICT: SKIPPED-UNREACHABLE]` / breach writes **no** marker. A new commit (new HEAD) re-arms the
  gate.
- **A human WAIVER also appends a durable audit line** to the same log the skip path uses
  (`<iso-8601>  agy-capstone  WAIVED  HEAD=<sha>`), so a mechanically-verified GREEN and a human waiver -
  which write the same bare-sha marker - stay distinguishable in the durable record. The marker content
  stays the bare sha (the auto-fire hook reads `content == current HEAD`; encoding `WAIVED` into the
  marker would break that read).

`.clavity/` is runtime state and is gitignored - never commit a marker.
````

- [ ] **Step 2: Create the byte-identical classic copy**

Do NOT retype it (byte-identity is gate-enforced). Copy the file:

Run:
```bash
mkdir -p clavity-classic/plugin/skills/agy-capstone
cp clavity-dotnet/plugin/skills/agy-capstone/SKILL.md clavity-classic/plugin/skills/agy-capstone/SKILL.md
```

- [ ] **Step 3: Enroll `agy-capstone` in the lint**

Modify `scripts/check-agy-discipline-skills.ps1` line 13:

```powershell
# Discipline skills shipped so far. SP-B appends 'agy-capstone'.
$skills = @('agy-first', 'agy-capstone')
```

- [ ] **Step 4: Run the lint - verify it passes for both skills**

Run: `just check-agy-skills`
Expected: `agy-discipline skills OK` and exit 0. (The lint checks the dotnet copy of each skill in `$skills`; the new `agy-capstone/SKILL.md` satisfies frontmatter-name, all four `[VERDICT]` forms, both transports, the `.clavity/agy-marks/` constant, and pure-ASCII.)

- [ ] **Step 5: Confirm the SKILL.md is pure ASCII (independent check)**

Run:
```bash
LC_ALL=C grep -nP '[^\x00-\x7F]' clavity-dotnet/plugin/skills/agy-capstone/SKILL.md && echo "NON-ASCII FOUND" || echo "PURE ASCII"
```
Expected: `PURE ASCII` (grep finds nothing, exits 1). If any line prints, fix the offending character (usually a stray em-dash or smart quote) before committing.

- [ ] **Step 6: Confirm byte-identity of the two copies**

Run:
```bash
diff -q clavity-dotnet/plugin/skills/agy-capstone/SKILL.md clavity-classic/plugin/skills/agy-capstone/SKILL.md && echo IDENTICAL
```
Expected: `IDENTICAL` (no diff output).

- [ ] **Step 7: Commit**

```bash
git add clavity-dotnet/plugin/skills/agy-capstone/SKILL.md \
        clavity-classic/plugin/skills/agy-capstone/SKILL.md \
        scripts/check-agy-discipline-skills.ps1
git commit -m "feat(sp-b): agy-capstone discipline skill (both plugins) + lint enrollment"
```

---

### Task 2: Restore + extend the Pester fixtures

**Why:** Once `'agy-capstone'` is in `$skills`, the existing rejection tests stage a scratch `-Root` containing only `agy-first`, so the lint reports `MISSING: agy-capstone` and exits 1 - the assertion `Should -Be 1` still passes but for the WRONG reason, silently losing its power to discriminate an agy-first defect. Each rejection fixture must stage a VALID `agy-capstone` copy too. Additionally, add symmetric pinning tests that prove the lint gates `agy-capstone` itself.

**Files:**
- Modify (rewrite): `scripts/tests/check-agy-discipline-skills.Tests.ps1`

- [ ] **Step 1: Rewrite the test file with a both-skills fixture helper**

Replace the ENTIRE contents of `scripts/tests/check-agy-discipline-skills.Tests.ps1` with:

```powershell
# scripts/tests/check-agy-discipline-skills.Tests.ps1
BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Lint     = Join-Path $script:RepoRoot 'scripts/check-agy-discipline-skills.ps1'

    # Stage a scratch -Root containing a VALID copy of EVERY shipped discipline skill, so a rejection
    # test that perturbs ONE skill fails on THAT defect, not on a MISSING sibling (SP-B: once
    # 'agy-capstone' joined $skills, a fixture staging only agy-first exited 1 for MISSING agy-capstone,
    # silently losing its discriminating power).
    function New-ScratchRoot {
        $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("agyskilltest-" + [guid]::NewGuid())
        foreach ($s in @('agy-first', 'agy-capstone')) {
            $dst = Join-Path $scratch "clavity-dotnet/plugin/skills/$s"
            New-Item -ItemType Directory -Path $dst -Force | Out-Null
            Copy-Item (Join-Path $script:RepoRoot "clavity-dotnet/plugin/skills/$s/SKILL.md") `
                      (Join-Path $dst 'SKILL.md')
        }
        return $scratch
    }
    $script:SkillPath = { param($root, $skill) Join-Path $root "clavity-dotnet/plugin/skills/$skill/SKILL.md" }
}

Describe 'check-agy-discipline-skills' {
    It 'passes when every shipped skill satisfies all invariants (real repo)' {
        $out = & $script:Lint 2>&1
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'agy-discipline skills OK'
    }

    Context 'rejection cases (each perturbs one skill; the other stays valid)' {
        It 'fails loudly on a non-ASCII character in <skill>' -ForEach @(
            @{ skill = 'agy-first' }, @{ skill = 'agy-capstone' }
        ) {
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            $body = (Get-Content -Raw $target) + "`nA stray em-dash `u{2014} here.`n"
            Set-Content -Path $target -Value $body -Encoding utf8
            & $script:Lint -Root $scratch 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
            Remove-Item -Recurse -Force $scratch
        }

        It 'fails when a required [VERDICT] form is missing from <skill>' -ForEach @(
            @{ skill = 'agy-first' }, @{ skill = 'agy-capstone' }
        ) {
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            $body = (Get-Content -Raw $target) -replace '\[VERDICT: SKIPPED-UNREACHABLE\]', '[VERDICT: GONE]'
            Set-Content -Path $target -Value $body -Encoding utf8
            & $script:Lint -Root $scratch 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
            Remove-Item -Recurse -Force $scratch
        }

        It 'fails cleanly (no unhandled crash) on an empty <skill> file' -ForEach @(
            @{ skill = 'agy-first' }, @{ skill = 'agy-capstone' }
        ) {
            # Capstone R1 (Cascade): a 0-byte SKILL.md made Get-Content -Raw return $null, and
            # $raw.Contains() threw an unhandled terminating error instead of a clean Fail.
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            Set-Content -Path $target -Value '' -NoNewline -Encoding utf8
            $out = & $script:Lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 1
            ($out -join "`n") | Should -Match 'EMPTY'
            ($out -join "`n") | Should -Not -Match 'null-valued expression'
            Remove-Item -Recurse -Force $scratch
        }

        It 'fails when name: is absent from <skill> real frontmatter even if present in the body' -ForEach @(
            @{ skill = 'agy-first' }, @{ skill = 'agy-capstone' }
        ) {
            # Capstone R1 (Protocol/Mechanism): the old lazy (?ms).*? frontmatter regex spanned past the
            # closing fence, so a 'name:' smuggled into the body plus any body '---' falsely satisfied it.
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            $real = Get-Content -Raw $target
            $body = ($real -replace "(?m)^name:\s*$skill\s*\r?\n", '') + "`nname: $skill`n---`n"
            Set-Content -Path $target -Value $body -NoNewline -Encoding utf8
            & $script:Lint -Root $scratch 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
            Remove-Item -Recurse -Force $scratch
        }
    }
}
```

- [ ] **Step 2: Verify the empty-file fixture actually reaches the EMPTY branch**

The lint's empty-file guard (`check-agy-discipline-skills.ps1:32`) fires only when `Get-Content -Raw` returns `$null`/empty. `Set-Content -Value '' -NoNewline` writes a 0-byte file, matching the shipped behaviour the guard was added for. (This replaces the old `New-Item -ItemType File` fixture; both yield a 0-byte file, but `Set-Content` on the pre-staged copy is uniform with the other perturbation steps.)

- [ ] **Step 3: Run the tests - verify all pass**

Run: `just test-scripts`
Expected: all `check-agy-discipline-skills` examples pass - 1 happy-path + 8 rejection examples (4 cases x 2 skills), 0 failures. Watch for the two `agy-capstone` rows in each `-ForEach` block: they prove the lint now gates the new skill.

- [ ] **Step 4: Prove the rejection tests still discriminate (watch one fail for the right reason)**

Temporarily break the assertion to confirm the fixture is testing the injected defect, not a MISSING sibling. In a scratch shell (do NOT commit this):
```bash
# Sanity check only - revert immediately:
pwsh -NoProfile -Command "
  \$scratch = Join-Path ([IO.Path]::GetTempPath()) ('sanity-' + [guid]::NewGuid())
  foreach (\$s in @('agy-first','agy-capstone')) {
    \$d = Join-Path \$scratch \"clavity-dotnet/plugin/skills/\$s\"
    New-Item -ItemType Directory -Path \$d -Force | Out-Null
    Copy-Item \"clavity-dotnet/plugin/skills/\$s/SKILL.md\" (Join-Path \$d 'SKILL.md')
  }
  # Both valid -> lint should PASS (exit 0), proving MISSING is not the failure cause:
  & ./scripts/check-agy-discipline-skills.ps1 -Root \$scratch 2>&1 | Out-Null
  Write-Output \"both-valid exit = \$LASTEXITCODE (expect 0)\"
  Remove-Item -Recurse -Force \$scratch
"
```
Expected: `both-valid exit = 0` - confirms a scratch root with both valid skills passes, so any rejection test's exit 1 is caused by its injected defect, not a missing sibling.

- [ ] **Step 5: Commit**

```bash
git add scripts/tests/check-agy-discipline-skills.Tests.ps1
git commit -m "test(sp-b): stage agy-capstone in every lint rejection fixture + pin the new skill"
```

---

### Task 3: Enroll `agy-capstone/SKILL.md` in the seed-sync gate

**Files:**
- Modify: `scripts/check-seed-artifacts-synced.sh:10-15`

- [ ] **Step 1: Add the new skill to the byte-identity loop**

In `scripts/check-seed-artifacts-synced.sh`, add `skills/agy-capstone/SKILL.md` to the `for rel in` list (after `skills/agy-first/SKILL.md`, line 12):

```bash
for rel in \
  skills/adversarial-panel-review/SKILL.md \
  skills/agy-first/SKILL.md \
  skills/agy-capstone/SKILL.md \
  hooks/agy-after-reminder.sh \
  knowledge/agy-assumptions.md \
  knowledge/agy-capabilities.md ; do
```

- [ ] **Step 2: Run seed-sync - verify the two copies are in sync**

Run: `just seed-sync-check`
Expected: `seed agent artifacts in sync (dotnet == classic)` and exit 0.

- [ ] **Step 3: Prove the gate now catches capstone drift (watch it fail, then revert)**

```bash
# Perturb the classic copy, confirm the gate FAILS, then restore it:
printf '\n<!-- drift -->\n' >> clavity-classic/plugin/skills/agy-capstone/SKILL.md
bash scripts/check-seed-artifacts-synced.sh; echo "exit=$?  (expect 1 + SEED-DRIFT on agy-capstone)"
git checkout -- clavity-classic/plugin/skills/agy-capstone/SKILL.md
bash scripts/check-seed-artifacts-synced.sh && echo "restored: in sync"
```
Expected: first run prints `SEED-DRIFT: skills/agy-capstone/SKILL.md differs ...` and `exit=1`; after `git checkout` restore, `restored: in sync`. (Uses a targeted per-file `git checkout` - never a broad restore.)

- [ ] **Step 4: Commit**

```bash
git add scripts/check-seed-artifacts-synced.sh
git commit -m "feat(sp-b): enroll agy-capstone/SKILL.md in the seed byte-identity gate"
```

---

### Task 4: Extend the marker-contract doc for the capstone write trigger

**Why:** The doc already enumerates `agy-capstone` in its constant and skip-log format, but its **Rules** write-trigger describes agy-first's "after a consult completes" semantics only. Capstone writes on a DIFFERENT terminal state (human-confirmed GREEN or explicit waiver), and adds two new audit-line kinds (WAIVED, UNVERIFIED-ACCEPTED). Document both, keeping the marker CONTENT a bare sha so SP-C's `content == HEAD` read stays uniform.

**Files:**
- Modify: `docs/agy-disciplines-marker-contract.md` (Constant skip-log bullet + Rules)

- [ ] **Step 1: Extend the skip-log bullet to list all three event kinds**

In `docs/agy-disciplines-marker-contract.md`, replace the "Skip log" bullet (currently lines 20-21):

```markdown
- **Skip log:** `.clavity/agy-marks/skipped.log`, append-only, one line per skipped consult:
  `<iso-8601>  <discipline>  SKIPPED-UNREACHABLE  HEAD=<sha>`.
```

with:

```markdown
- **Skip / audit log:** `.clavity/agy-marks/skipped.log`, append-only, one line per event:
  - `<iso-8601>  <discipline>  SKIPPED-UNREACHABLE  HEAD=<sha>` - peer unreachable (any discipline).
  - `<iso-8601>  agy-capstone  WAIVED  HEAD=<sha>` - human waived the capstone gate (SP-B; also writes
    the marker, so this line is what distinguishes a waiver from a mechanically-verified GREEN in the
    durable record).
  - `<iso-8601>  agy-capstone  UNVERIFIED-ACCEPTED  HEAD=<sha>  <finding>` - human accepted the risk of a
    single unmeasurable finding (SP-B; per-finding, non-terminal - writes NO marker, does NOT abort the
    capstone).
```

- [ ] **Step 2: Split the Rules write-trigger by discipline**

Replace the first Rules bullet (currently lines 48-50):

```markdown
- The **skill** writes `<discipline>.head` **only** after a consult actually completes
  (ALIGNED / REJECTED / resolved NEGOTIATE). A `SKIPPED-UNREACHABLE` or a review-only breach writes NO
  marker and instead appends to `skipped.log`.
```

with:

```markdown
- The **skill** writes `<discipline>.head` **only** at that discipline's terminal state:
  - `agy-first` writes after a consult completes (ALIGNED / REJECTED / resolved NEGOTIATE).
  - `agy-capstone` writes only on **human-confirmed GREEN or explicit human waiver** - NOT on a raw
    self-reported clean round, an override re-entry still in progress, or a `SKIPPED-UNREACHABLE`. A
    review-only breach at the capstone gate does NOT write the marker either (it halts-and-asks the
    human; see the skill).
  In every case the content stays the bare `git rev-parse HEAD` sha, so the SP-C hook's
  `content == HEAD` read is uniform across disciplines; capstone's WAIVED / UNVERIFIED-ACCEPTED
  distinctions live in the log above, never in the marker.
- A `SKIPPED-UNREACHABLE` or a review-only breach writes NO `.head` marker (the discipline re-fires next
  trigger); the skip appends to `skipped.log` as above.
```

- [ ] **Step 3: Verify the doc reads coherently**

Re-read `docs/agy-disciplines-marker-contract.md` and confirm: the Constant section lists all three audit-line kinds; the Rules section distinguishes agy-first vs agy-capstone write triggers; the marker content is stated as a bare sha in both places; no contradiction with the existing "Resolved: marker namespacing = Option S" section.

- [ ] **Step 4: Commit**

```bash
git add docs/agy-disciplines-marker-contract.md
git commit -m "docs(sp-b): document agy-capstone terminal-state write trigger + WAIVED/UNVERIFIED audit lines"
```

---

### Task 5: Full-gate integration verification

**Files:** none modified - this task only runs the gates that CI/pre-push will run.

- [ ] **Step 1: Run the lint**

Run: `just check-agy-skills`
Expected: `agy-discipline skills OK`, exit 0.

- [ ] **Step 2: Run the seed-sync gate**

Run: `just seed-sync-check`
Expected: `seed agent artifacts in sync (dotnet == classic)`, exit 0.

- [ ] **Step 3: Run the script unit tests**

Run: `just test-scripts`
Expected: all Pester examples pass, 0 failures (includes the 1 happy-path + 8 rejection examples from Task 2).

- [ ] **Step 4: Confirm the tree is clean and the commit range is what the plan produced**

Run:
```bash
git status --short && echo "---" && git log --oneline -5
```
Expected: empty `git status` (all work committed); the last 4 commits are Tasks 1-4 (skill+lint, tests, seed-sync, marker-doc), atop `a9e559b` (the SP-B spec).

- [ ] **Step 5: Manual-invocation smoke (discoverability)**

Confirm both `SKILL.md` files are discoverable skills: `name: agy-capstone` on line 2 of each, the body names the four `[VERDICT]` tokens, both transports (`agy_ask`, `clavity ask --review-only`), and the marker constant `.clavity/agy-marks/`.

Run:
```bash
for p in clavity-dotnet clavity-classic; do
  f="$p/plugin/skills/agy-capstone/SKILL.md"
  echo "=== $f ==="
  grep -c 'name: agy-capstone' "$f"
  grep -c 'agy_ask' "$f"
  grep -c 'clavity ask --review-only' "$f"
  grep -c '.clavity/agy-marks/' "$f"
done
```
Expected: each `grep -c` returns >= 1 for both plugins.

---

## Post-plan discipline (not a task - handoff note)

Per the AGY-CAPSTONE rule, after execution completes, run a convergent capstone review of the COMMITTED SP-B code (`a9e559b..HEAD`, the Task 1-4 commits) - rounds-until-green, verify each finding by measurement, fold + commit, re-run until a clean round, human-adjudicated GREEN. This is the first real dogfood of the very skill this plan ships. The OWNER owns every push; the 42 (now ~46) commits stay unpushed until the owner pushes and merges SP-0.

---

## Self-Review

**1. Spec coverage** (every spec section -> a task):
- "The skill's shape" (13 sections) -> Task 1 SKILL.md (all 13 present: frontmatter w/ restrictive trigger, when-to-use, transport, safety-envelope-with-breach-halt, review-range w/ generated-exclusion + fold-re-extension, convergent-round w/ seats+forcing-functions+rotation+commit-before-next, division-of-labor-spine + unmeasurable/UNVERIFIED, ledger, round-cap+GREEN+override, AGY-NEGOTIATE-auto-fire, tokens-by-disposition, unreachable + review-failure-distinction, marker w/ waiver-audit-line).
- "Token model" -> Task 1 `## The [VERDICT] tokens` section (four forms verbatim, emitted by disposition, GREEN = meta-state).
- "Enrollment" items 1-3 -> Tasks 1 (lint), 3 (seed-sync), 4 (marker-doc). Items 4-5 (justfile/lefthook, scripts/README) need NO change (spec confirms auto-pickup).
- "Testing posture" -> Task 2 (fixture restore + pinning) + Task 5 (gate run). Existing-test-integrity bullet -> Task 2 Step 1 `New-ScratchRoot`.
- "Gaps flagged for the PLAN" -> SKILL.md prose (Task 1); seed-sync insertion line (Task 3); marker-doc edit (Task 4); `MAX_CAPSTONE_ROUNDS = 3` (set in SKILL.md + owner-confirm note in header); Pester fixtures (Task 2); generated-file exclude list (documented as pathspec `:(exclude)` in SKILL.md review-range); waiver + UNVERIFIED-ACCEPTED audit-line formats (Task 4 + SKILL.md).

**2. Placeholder scan:** No "TBD"/"TODO"/"implement later". The SKILL.md prose is complete (not "author appropriate content"); every command has expected output; every edit shows the exact before/after text.

**3. Type/name consistency:** `$skills = @('agy-first', 'agy-capstone')` (Task 1) matches the `New-ScratchRoot` loop `@('agy-first','agy-capstone')` (Task 2) and the seed-sync `skills/agy-capstone/SKILL.md` path (Task 3). Marker path `.clavity/agy-marks/agy-capstone.head` matches the marker-contract doc's `<discipline>.head` with `<discipline> = agy-capstone`. All four `[VERDICT]` literals in the SKILL.md exactly match the lint's `$requiredVerdicts` (incl. the trailing `- ` on REJECTED/NEGOTIATE).

## Exhaustiveness self-audit (2026-07-25)

- **Under-specified "what":** none. SKILL.md is fully authored; every script edit shows exact text; every command shows expected output.
- **Placeholders / TBD:** none. `MAX_CAPSTONE_ROUNDS = 3` is set (not deferred) with an owner-override note.
- **Missing cases / edges:** covered - lint checks only the dotnet copy (classic guarded by seed-sync, Task 3); the vacuous-green Pester trap (Task 2 Step 1 helper + Step 4 discrimination proof); empty-file guard reached via `Set-Content -Value '' -NoNewline` (Task 2 Step 2); ASCII gate double-checked independently (Task 1 Step 5); byte-identity checked before AND after seed-sync enrollment (Task 1 Step 6 + Task 3 Step 3); targeted `git checkout -- <file>` restore, never broad (Task 3 Step 3).
- **Requirement -> task:** every spec section maps (Self-Review point 1).
- **Deferred-with-owner:** `MAX_CAPSTONE_ROUNDS = 3` surfaced for override; nothing else silent. Auto-fire/hook -> SP-C (out of scope, spec Non-goals); hook-activation test -> SP-D.
- **Remaining gap flagged for execution:** the generated/vendored-file exclude list in the SKILL.md is stated as a general pattern (lockfiles/minified/generated manifests via `:(exclude)`), not a repo-specific enumeration - correct, because the skill ships to arbitrary consumer repos and cannot hardcode one repo's generated paths. No open gap.

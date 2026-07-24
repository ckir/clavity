# SP-A — AGY-FIRST + AGY-NEGOTIATE skill + the [VERDICT] contract — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a first-class, manually-invokable `agy-first` discipline skill into both driver plugins (`clavity-dotnet`, `clavity-classic`), carrying the AGY-FIRST divergent-consult protocol, the inlined AGY-NEGOTIATE sub-protocol, and the ASCII `[VERDICT]` token contract — kept byte-identical across plugins by the existing seed-sync check.

**Architecture:** One skill per the shipped `adversarial-panel-review` pattern: a single `SKILL.md` authored once and committed byte-identical into `clavity-dotnet/plugin/skills/agy-first/` and `clavity-classic/plugin/skills/agy-first/` (the marketplace discovers skills only from a committed dir, so both copies must exist and match). The transport delta (dotnet `agy_ask` after `agy_status`; classic `clavity ask --review-only`) is named **inline** in the body — the driving agent resolves its own transport — so the two files stay byte-identical (Decision 4). AGY-NEGOTIATE is **inlined** as a sub-section, not a standalone skill (Decision 4 rejects a shared core). The skill's checkable invariants (frontmatter, ASCII-only `[VERDICT]` grammar, byte-identity, marker-contract constant) are enforced by a new Pester lint test + an extension of `scripts/check-seed-artifacts-synced.sh`; the prose protocol itself is best-effort prompt-discipline (Posture) reviewed by the AGY-AFTER panel and the owner, not unit-tested.

**Tech Stack:** Markdown skills (Claude Code / agy plugin skill convention), Bash sync-check (`diff` + `jq`), Pester 5 (`scripts/tests/*.Tests.ps1`), `just` recipes.

---

## Design anchors (the oracle for every task)

Governing spec: `docs/superpowers/specs/2026-07-24-ship-agy-workflow-design.md` (`3f31d85`). The load-bearing spec clauses this plan implements — cite these when a value looks wrong; the spec wins:

- **Posture (spec L18-36):** best-effort prompt-discipline, NOT a code-enforced sandbox. Firing and the `[VERDICT]` token are self-reported. The bar is "materially better than baseline," not determinism. Forcing functions make hollow compliance *visible*, they do not make it impossible.
- **What the value is (spec L41-54):** the load-bearing discipline is verify-every-bare-factual-claim-by-measurement-before-folding + negotiate-on-disagreement. A skill that fires a consult but omits verify-and-quote is a footgun and is disallowed.
- **Decision 2 (spec L152-185):** the `[VERDICT]` grammar (ASCII-only), materiality floor (arch/perf/security only), `MAX_NEGOTIATE_ROUNDS = 2`, impasse → human tie-break, quote-the-measurement forcing function, `SKIPPED-UNREACHABLE` + out-of-band durable record.
- **Decision 4 (spec L264-280):** per-plugin self-contained, transport delta inline, byte-identical bodies, state files namespaced per plugin, extend `check-seed-artifacts-synced.sh`.
- **Marker contract (spec L335-336, gap flagged for this plan):** the exact marker path + format + HEAD-hash key the skill WRITES and the SP-C hook READS must be a single documented constant. This plan defines it (Task 5); SP-C consumes it.

**Scope boundary:** SP-A ships the **skill only** (manually invokable + correct when auto-fired later). The auto-fire hook that reads the marker is **SP-C**. AGY-CAPSTONE is **SP-B**. Do not build the hook or the capstone here.

---

## File Structure

**Created:**
- `clavity-dotnet/plugin/skills/agy-first/SKILL.md` — the discipline skill (authoritative copy).
- `clavity-classic/plugin/skills/agy-first/SKILL.md` — byte-identical mirror.
- `scripts/check-agy-discipline-skills.ps1` — lint: ASCII-only `[VERDICT]` grammar + frontmatter + marker-constant presence, over every shipped `agy-first/SKILL.md`.
- `scripts/tests/check-agy-discipline-skills.Tests.ps1` — Pester tests for the lint script (RED first).

**Modified:**
- `scripts/check-seed-artifacts-synced.sh:10-14` — add `skills/agy-first/SKILL.md` to the byte-identical enumeration.
- `scripts/README.md` — add a row for `check-agy-discipline-skills.ps1`.
- The repo's pre-push gate — memory records this as `lefthook.yml` (which also exposes a `just seed-sync-check` recipe); add the new lint to the SAME gate that already runs `check-seed-artifacts-synced.sh`, plus a `just`-style recipe wrapper only if that is the repo's convention. **Step 0 of Task 6 verifies the actual gate file (`lefthook.yml`) and any recipe wrapper (`justfile`) before editing** — do not assume, and do not add a stricter gate than the repo already runs.

**Why `agy-first` is one skill, not two:** the spec titles SP-A "AGY-FIRST + AGY-NEGOTIATE skills," but Decision 4 forbids a shared-core skill and calls NEGOTIATE "a conditional sub-step of AGY-FIRST/CAPSTONE." So NEGOTIATE inlines as a `## AGY-NEGOTIATE` section inside `agy-first`; SP-B's capstone skill re-inlines the same protocol (duplication kept honest by the sync-check), rather than depending on a shared `agy-negotiate` skill.

---

## Task 1: Lint script + failing Pester test for the `agy-first` skill invariants

**Files:**
- Create: `scripts/check-agy-discipline-skills.ps1`
- Test: `scripts/tests/check-agy-discipline-skills.Tests.ps1`

The lint asserts the *checkable* invariants of every shipped discipline skill (currently just `agy-first`): (a) it exists in both plugins; (b) valid frontmatter with `name:` matching the dir; (c) contains all four ASCII `[VERDICT]` forms; (d) is pure ASCII (no em-dash / non-ASCII — the `ΓÇö` mojibake guard, spec Decision 2.1); (e) names both transports (`agy_ask` and `clavity ask --review-only`); (f) contains the marker-contract constant token. Byte-identity across plugins is left to `check-seed-artifacts-synced.sh` (Task 6) — the single source of truth for cross-plugin drift — so this lint reads only the dotnet copy for content checks to avoid two scripts asserting the same thing.

- [ ] **Step 0: State-verification.** Confirm `scripts/check-installer-ascii.ps1` and `scripts/tests/check-seed-budget.Tests.ps1` exist and observe their shape (param block, `$PSScriptRoot` resolution, Pester `Describe/It`, exit-code convention). If either is absent or structured differently than described, STOP and report `STATE_MISMATCH: <what>`.

- [ ] **Step 1: Write the failing test**

```powershell
# scripts/tests/check-agy-discipline-skills.Tests.ps1
BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Lint     = Join-Path $script:RepoRoot 'scripts/check-agy-discipline-skills.ps1'
}

Describe 'check-agy-discipline-skills' {
    It 'passes when the shipped agy-first skill satisfies every invariant' {
        $out = & $script:Lint 2>&1
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'agy-discipline skills OK'
    }

    It 'fails loudly if a shipped skill contains a non-ASCII character' {
        # Copy the real skill into a scratch tree, inject an em-dash, point the lint at it.
        $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("agyskilltest-" + [guid]::NewGuid())
        $dst = Join-Path $scratch 'clavity-dotnet/plugin/skills/agy-first'
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
        $src = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/skills/agy-first/SKILL.md'
        $body = (Get-Content -Raw $src) + "`nA stray em-dash `u{2014} here.`n"
        Set-Content -Path (Join-Path $dst 'SKILL.md') -Value $body -Encoding utf8
        & $script:Lint -Root $scratch 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
        Remove-Item -Recurse -Force $scratch
    }

    It 'fails if a required [VERDICT] form is missing' {
        $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("agyskilltest2-" + [guid]::NewGuid())
        $dst = Join-Path $scratch 'clavity-dotnet/plugin/skills/agy-first'
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
        $src = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/skills/agy-first/SKILL.md'
        $body = (Get-Content -Raw $src) -replace '\[VERDICT: SKIPPED-UNREACHABLE\]', '[VERDICT: GONE]'
        Set-Content -Path (Join-Path $dst 'SKILL.md') -Value $body -Encoding utf8
        & $script:Lint -Root $scratch 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
        Remove-Item -Recurse -Force $scratch
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"`
Expected: FAIL — the lint script does not exist yet (`& $script:Lint` errors / non-zero), and the real skill file does not exist yet so even the happy-path `It` cannot pass.

- [ ] **Step 3: Write the lint script**

```powershell
# scripts/check-agy-discipline-skills.ps1
# Lints the shipped agy-driving discipline skills for their checkable invariants.
# Byte-identity across plugins is enforced separately by scripts/check-seed-artifacts-synced.sh.
[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
$fail = $false
function Fail($msg) { Write-Error $msg -ErrorAction Continue; $script:fail = $true }

# Discipline skills shipped so far. SP-B appends 'agy-capstone'.
$skills = @('agy-first')

# The four ASCII [VERDICT] forms the contract requires (spec Decision 2.1 + 2.7).
$requiredVerdicts = @(
    '[VERDICT: ALIGNED]',
    '[VERDICT: REJECTED - ',
    '[VERDICT: NEGOTIATE - ',
    '[VERDICT: SKIPPED-UNREACHABLE]'
)
# The documented marker-contract constant the skill must reference (Task 5).
$markerConstant = '.clavity/agy-marks/'

foreach ($skill in $skills) {
    $rel = "clavity-dotnet/plugin/skills/$skill/SKILL.md"
    $path = Join-Path $Root $rel
    if (-not (Test-Path $path)) { Fail "MISSING: $rel"; continue }
    $raw = Get-Content -Raw $path

    # (b) frontmatter name matches dir
    if ($raw -notmatch "(?ms)\A---\r?\n.*?^name:\s*$skill\s*$.*?^---\r?\n") {
        Fail "$rel : frontmatter 'name:' must equal '$skill'"
    }
    # (c) all required [VERDICT] forms present
    foreach ($v in $requiredVerdicts) {
        if (-not $raw.Contains($v)) { Fail "$rel : missing required verdict form '$v'" }
    }
    # (d) pure ASCII (mojibake guard)
    $nonAscii = [regex]::Matches($raw, '[^\x00-\x7F]')
    if ($nonAscii.Count -gt 0) {
        Fail "$rel : contains $($nonAscii.Count) non-ASCII char(s); first = U+$([int][char]$nonAscii[0].Value | ForEach-Object { $_.ToString('X4') })"
    }
    # (e) both transports named inline
    if (-not $raw.Contains('agy_ask'))               { Fail "$rel : missing dotnet transport 'agy_ask'" }
    if (-not $raw.Contains('clavity ask --review-only')) { Fail "$rel : missing classic transport 'clavity ask --review-only'" }
    # (f) marker-contract constant referenced
    if (-not $raw.Contains($markerConstant)) { Fail "$rel : missing marker-contract constant '$markerConstant'" }
}

if ($fail) { Write-Error 'agy-discipline skill lint FAILED' -ErrorAction Continue; exit 1 }
Write-Output 'agy-discipline skills OK'
exit 0
```

- [ ] **Step 4: Run the test — happy path still fails (skill not written yet), the two negative `It`s cannot run cleanly**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"`
Expected: the happy-path `It` FAILS (skill file absent → lint exits 1); the two negative-path `It`s reference the not-yet-existing real skill and also fail. This is correct RED — the skill is Task 2.

- [ ] **Step 5: Commit**

```bash
git add scripts/check-agy-discipline-skills.ps1 scripts/tests/check-agy-discipline-skills.Tests.ps1
git commit -m "test(agy-first): lint + failing Pester for discipline-skill invariants"
```

---

## Task 2: Author the `agy-first` skill (dotnet copy = authoritative)

**Files:**
- Create: `clavity-dotnet/plugin/skills/agy-first/SKILL.md`

This is the deliverable's heart. Write it complete — no placeholders. The body below is the tests-are-already-written target from Task 1; implement until the lint passes. The prose is authored to the spec's Decision 2 / Posture / value clauses (the oracle) and mirrors the shipped `adversarial-panel-review` voice + the `agy-seam-inject.sh` `*brainstorm*` forcing-function wording.

- [ ] **Step 0: State-verification.** Open `clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md` and confirm the frontmatter shape (`---` / `name:` / `description:` / `---`) and that its Step-2 transport clause reads "clavity-dotnet: the `agy_ask` MCP tool, after an `agy_status` idle-check; clavity-classic: `clavity ask --review-only`". If it differs, STOP and report `STATE_MISMATCH: <what>` — the transport clause is a contract this skill must match verbatim.

- [ ] **Step 1: Write the skill file** with exactly this content:

````markdown
---
name: agy-first
description: Use when facing a design, scope, approach, or sequencing fork in subproject work (typically at the brainstorming approaches step). Runs a divergent, review-only consult of the live agy peer under forcing functions, verifies every factual claim by measurement before folding, negotiates on material disagreement, and ends with one ASCII [VERDICT] token. Best-effort prompt-discipline, manually invokable; auto-fire is added separately.
---

# agy-first — consult the peer on a fork before you commit to it

## When to use
Invoke this skill whenever you face a **design / scope / approach / sequencing fork** in subproject work
and are about to pick a direction — invoke it manually, or run it when the auto-fire hook (shipped
separately) injects its directive at the brainstorming approaches step. The value is not "ask agy" — the
peer is confidently wrong often enough that folding its advice unchecked would *degrade* the outcome. The
value is the discipline that wraps the consult: **verify every bare factual claim by measurement before
folding it, and negotiate a synthesis on material disagreement** rather than defer-to-peer or
dismiss-the-peer.

This is **best-effort prompt-discipline, not a sandbox.** The `[VERDICT]` token below is self-reported;
its forcing functions make hollow compliance visible to your human — do not make it impossible. The bar
is "materially better than deciding blind," not determinism.

Works with or without superpowers — superpowers only adds the auto-fire and its approval breakpoints.
You can always invoke this skill directly on a fork; when you do, **surface every result and decision to
your human in-chat** (there is no breakpoint to defer to).

## Transport (resolve to your own plugin)
Send the consult over your driver's review-ask transport, review-only:
- **clavity-dotnet:** the `agy_ask` MCP tool, after an `agy_status` idle-check (do not fire while the
  peer is busy).
- **clavity-classic:** `clavity ask --review-only` (subagents use the CLI form, not the MCP bus).

## Safety envelope (every consult, no exceptions)
A bare "review-only" once let the peer write to the tree anyway. Wrap each consult:
1. **Snapshot before** — capture `git status --short` (and reflog if the fork touches committed work).
2. **Forbidden-actions banner** — state in the payload: "REVIEW-ONLY. Do not edit, create, move, or
   delete any file. Do not run mutating commands. Respond with analysis only."
3. **Permission to pass** — the peer may decline or say it needs more; it must not act.
4. **Point at files, not summaries** — write the fork/options to `.clavity/seams/<topic>.md` and send
   the peer the PATH; let it read the artifact itself. Never consult it on a pasted summary of your own
   measurements.
5. **Diff after** — re-check `git status` against the before-snapshot. If the tree changed, the peer
   breached review-only. A breach is a **security event, not a routine skip** — do NOT proceed silently
   and do NOT fold anything: (a) surface the breach loudly to your human and get confirmation before
   continuing; (b) revert **only the paths the peer touched** (diff the after-state against your
   before-snapshot and restore exactly those files) — **never** a blind `git reset --hard` /
   `git checkout -- .`, which would also destroy your own legitimate uncommitted work captured in the
   snapshot; (c) then emit `[VERDICT: SKIPPED-UNREACHABLE]` (the peer's advice is discarded). The
   "proceed, never hang" rule below is for a genuinely *unreachable* peer, NOT a detected breach.

## The consult (divergent, forcing-function driven)
Frame the fork as a GOAL + a checkable SUCCESS CRITERION with full method latitude — NOT a vague "be
creative" dial (the peer converts that into superficial novelty). Shape divergence with vectors as
needed: invert the core constraint (solve it WITHOUT the main assumed component); the extreme-resource
version (1 hour / $0, or the opposite); the dumbest brute-force baseline that still works; a cross-domain
analogy. Each alternative must stay USEFUL against the goal and note its real tradeoffs. Default persona:
bold inventive systems-designer; override when a sharper lens fits (security-auditor, perf-skeptic,
API-contract-pedant). The peer is empowered to CHALLENGE your own settled decision when it has a
substantive reason (correctness, safety, a materially better design, a hidden contradiction) — you keep
the final call.

## Verify before you fold (the spine)
Before folding ANY factual claim the peer makes, **verify it by measurement and quote the measured
output** — the tool stdout or the file line you relied on — in your writeup. A fold with no quoted
measurement is visibly hollow to your human. The peer states false claims with identical confidence to
true ones; an unverified fold is how a confabulation enters your design.

## AGY-NEGOTIATE (conditional sub-protocol)
Engage negotiation ONLY on a **material** disagreement — one that changes **architecture, performance,
or security**. Style, naming, and trivia never qualify (those resolve to `ALIGNED`; you yield). Trigger:
your consult emits `[VERDICT: NEGOTIATE - <reason>]`.

- **Round cap:** `MAX_NEGOTIATE_ROUNDS = 2` (tunable). Round 1: you present measured evidence, the peer
  counters. Round 2: you attempt a synthesis that takes the best of both.
- **Impasse (no forced synthesis):** if not converged at the cap, declare **IMPASSE**, document both
  positions plainly in-chat (each with its measured support), and hand your human the tie-break directly.
  If running under superpowers its approval breakpoint is the natural place to adjudicate, but never rely
  on a breakpoint that may not exist (manual invocation has none). Do not fabricate agreement.
- **Manual backstop:** your human can type "negotiate with agy" to trigger this protocol on any observed
  disagreement, regardless of the emitted token.

## End with exactly one [VERDICT] token (ASCII only)
ASCII only — no em-dash or other non-ASCII (mojibake risk; this project has hit corruption). Emit exactly
one, as the last line:
- `[VERDICT: ALIGNED]` — you and the peer agree; proceed.
- `[VERDICT: REJECTED - <measured reason>]` — the peer is factually wrong, killed by measurement; you
  override without negotiation and quote the measurement that killed it.
- `[VERDICT: NEGOTIATE - <one-line material reason>]` — a material disagreement remains; run
  AGY-NEGOTIATE above.
- `[VERDICT: SKIPPED-UNREACHABLE]` — the consult could not run.

## If the peer is unreachable
No live peer / no auth / the idle-check never clears: emit `[VERDICT: SKIPPED-UNREACHABLE]` and
**proceed** — never hang, never hard-block. Surface the skip on BOTH channels: (a) tell your human
in-chat that the consult was skipped and name the fork it skipped; (b) create `.clavity/agy-marks/` if
it does not exist (gitignored runtime state — absent on a fresh clone; a bare `>>` append would fail
`No such file or directory`), then append one durable line to
`.clavity/agy-marks/skipped.log` (`<iso-8601>  agy-first  SKIPPED-UNREACHABLE  HEAD=<sha>`, where
`<sha>` is the `git rev-parse HEAD` output, or the literal `none` if HEAD cannot resolve — never a git
error string) so it is not lost if the chat summary drops it. Do NOT write the consulted marker (below), so the next trigger
retries. (The log is a gitignored breadcrumb — it survives normal operation; only a deliberate
`git clean -fd` wipes it, which is an accepted level for a skip breadcrumb, so the in-chat notice is the
immediate signal and the log the durable backstop.)

## Debounce marker (hook contract — written here, read by the auto-fire hook)
Only AFTER a consult actually completes (any of ALIGNED / REJECTED / NEGOTIATE-resolved), record it so
the auto-fire hook does not re-inject this discipline for the same cycle. Create `.clavity/agy-marks/`
first if it does not exist (gitignored runtime state, absent on a fresh clone), then write the current
commit sha to the marker:

- **Path:** `.clavity/agy-marks/agy-first.head` — a single discipline-keyed marker, no `<plugin-id>`
  prefix (**DECIDED: Option S**; AGY-AFTER solo panel + agy escalation ALIGNED, owner ratifies). The
  byte-identical skill body cannot carry a per-plugin literal, and the two drivers are mutually exclusive
  (only one `clavity` plugin installed; both-installed is a transient migration state where a shared
  marker correctly debounces the shared phase and *prevents* a duplicate paid consult). See the marker
  contract doc (Task 5).
- **Content:** the output of `git rev-parse HEAD` at consult time, nothing else. **If `git rev-parse
  HEAD` cannot resolve** (not a git repo / a repo with no commits), skip writing the marker entirely —
  the discipline simply re-fires next trigger, which is safe.
- **Lifecycle:** a new commit (new HEAD sha) or a later fork on the same branch changes the content and
  re-arms the discipline. A `SKIPPED-UNREACHABLE` or a review-only breach writes NO marker (see above),
  so the next trigger retries. If you ignore the injected directive entirely, no marker is written and
  the next trigger re-fires — non-compliance self-heals to a retry.

`.clavity/` is runtime state and is gitignored — never commit a marker.
````

- [ ] **Step 2: Run the lint's happy-path check directly**

Run: `pwsh -NoProfile -Command "./scripts/check-agy-discipline-skills.ps1"`
Expected: prints `agy-discipline skills OK`, exit 0. (The dotnet copy now satisfies every content invariant.)

- [ ] **Step 3: Commit**

```bash
git add clavity-dotnet/plugin/skills/agy-first/SKILL.md
git commit -m "feat(agy-first): author the AGY-FIRST + AGY-NEGOTIATE discipline skill"
```

---

## Task 3: Mirror the skill byte-identically into clavity-classic

**Files:**
- Create: `clavity-classic/plugin/skills/agy-first/SKILL.md` (byte-identical copy)

- [ ] **Step 0: State-verification.** Confirm `clavity-classic/plugin/skills/adversarial-panel-review/SKILL.md` exists (the mirror precedent). If the `clavity-classic/plugin/skills/` dir is absent, STOP and report `STATE_MISMATCH: clavity-classic plugin skills dir missing`.

- [ ] **Step 1: Copy the authoritative file verbatim**

Run:
```bash
mkdir -p clavity-classic/plugin/skills/agy-first
cp clavity-dotnet/plugin/skills/agy-first/SKILL.md clavity-classic/plugin/skills/agy-first/SKILL.md
```
(Use `cp` — do NOT re-type the body; byte-identity is the contract. `check-seed-artifacts-synced.sh` will enforce it in Task 6.)

- [ ] **Step 2: Verify the two copies are byte-identical**

Run: `diff clavity-dotnet/plugin/skills/agy-first/SKILL.md clavity-classic/plugin/skills/agy-first/SKILL.md && echo IDENTICAL`
Expected: `IDENTICAL` (no diff output).

- [ ] **Step 3: Run the full Pester test — now GREEN**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"`
Expected: PASS — all three `It`s green (happy path passes; the two negative-path `It`s can now clone the real skill and confirm the lint rejects the corruption).

- [ ] **Step 4: Commit**

```bash
git add clavity-classic/plugin/skills/agy-first/SKILL.md
git commit -m "feat(agy-first): mirror the discipline skill into clavity-classic (byte-identical)"
```

---

## Task 4: Namespace `.clavity/agy-marks/` and confirm it is gitignored

**Files:**
- Modify: `.gitignore` (only if `.clavity/` is not already ignored)

The skill writes runtime markers under `.clavity/agy-marks/`. These must never be committed.

- [ ] **Step 0: State-verification.** Run `git check-ignore -v .clavity/agy-marks/x.head` (a probe path). If it prints a matching `.gitignore` rule, `.clavity/` is already ignored — SKIP Steps 1-2, go to Step 3. If it prints nothing (not ignored), do Steps 1-2.

- [ ] **Step 1: Add the ignore rule** (only if Step 0 showed it is not ignored)

Append to the repo-root `.gitignore`:
```gitignore
# Runtime state for the agy-driving disciplines (markers, skip log, seam artifacts)
.clavity/
```

- [ ] **Step 2: Verify**

Run: `git check-ignore -v .clavity/agy-marks/x.head`
Expected: prints the `.clavity/` rule (path is now ignored).

- [ ] **Step 3: Commit** (only if `.gitignore` changed)

```bash
git add .gitignore
git commit -m "chore(agy-first): gitignore .clavity/ runtime state (markers, skip log)"
```

---

## Task 5: Document the hook↔skill marker contract as a single shared constant

**Files:**
- Create: `docs/agy-disciplines-marker-contract.md`

The spec (L335-336) requires the marker path/format/HEAD-hash key to be ONE documented constant shared by the skill (writer) and the SP-C hook (reader). SP-A owns the writer, so SP-A publishes the contract; SP-C's plan will cite this file as its oracle.

- [ ] **Step 1: Write the contract doc**

```markdown
# agy-disciplines marker contract (skill writes, auto-fire hook reads)

Single source of truth for the debounce marker shared between the discipline **skills** (which WRITE it,
in-flow, only after a consult completes) and the SP-C **auto-fire hook** (which READS it to decide whether
to inject a discipline's directive). Spec: `docs/superpowers/specs/2026-07-24-ship-agy-workflow-design.md`
Decision 1 (debounce) + Decision 4 (per-plugin state).

## Constant

- **Directory:** `.clavity/agy-marks/` (repo-cwd-relative; runtime state; gitignored).
- **Marker file:** `<discipline>.head`
  - `<discipline>` ∈ { `agy-first` (SP-A), `agy-capstone` (SP-B) }.
  - **No `<plugin-id>` prefix** (DECIDED: Option S). A byte-identical skill body cannot carry a per-plugin
    literal and has no runtime mechanism to resolve which plugin it is; and the two drivers are mutually
    exclusive (both-installed is a transient migration state), so a single discipline-keyed marker is
    safe — at worst one duplicate consult during migration. See "Resolved: marker namespacing" below: this
    drops Decision 4's per-plugin-state clause *for the marker specifically*.
- **Content:** the commit sha from `git rev-parse HEAD` at consult time, and nothing else. If HEAD cannot
  resolve (no repo / no commits), no marker is written (the discipline re-fires — safe).
- **Skip log:** `.clavity/agy-marks/skipped.log`, append-only, one line per skipped consult:
  `<iso-8601>  <discipline>  SKIPPED-UNREACHABLE  HEAD=<sha>`.

## Resolved: marker namespacing = Option S (single, no plugin-id)
DECIDED (AGY-AFTER solo panel + agy escalation + owner-triggered AGY-NEGOTIATE all ALIGNED; owner
RATIFIED): a single discipline-keyed marker `<discipline>.head`, NO `<plugin-id>` prefix. The rejected
alternative (Option P) resolved `<plugin-id>` at runtime from `CLAUDE_PLUGIN_ROOT` and kept
`<plugin-id>-<discipline>.head`; it preserves Decision 4's per-plugin-state clause but adds a fragile
runtime-resolution mechanism the byte-identical skill body and the SP-C hook would both have to share
exactly, for zero benefit. Three verified reasons P is not just unnecessary but strictly worse:

1. **P is degenerate post-SP-0.** SP-0 unified both drivers to plugin identity `clavity`, staging to
   `plugins/clavity` (`clavity-dotnet.iss:40`, `clavity-classic.iss:50`), so `CLAUDE_PLUGIN_ROOT`'s leaf
   is `clavity` for BOTH drivers. Resolving `<plugin-id>` from it yields `clavity` either way —
   P produces the SAME filename as S (`clavity-agy-first.head`), adding fragile parsing for an identical
   result.
2. **P regresses on migration.** Retaining one `agy-first.head` across a classic->dotnet swap is the
   CORRECT debounce behavior (that HEAD's fork was already resolved); P would falsely hide the debounce
   state from the new plugin and spuriously re-fire a paid consult.
3. **No cross-project clobber to guard against.** The marker is repo-cwd-relative, so per-repo/worktree
   isolation already holds — Decision 4's per-plugin-path guard is moot for the marker.

Mutual exclusivity means S never races in steady state; during the transient both-installed migration a
shared marker correctly debounces the shared phase (whichever hook fires first sets it, preventing a
duplicate paid consult). SP-C's reader consumes this same constant.

## Rules

- The **skill** writes `<discipline>.head` **only** after a consult actually completes
  (ALIGNED / REJECTED / resolved NEGOTIATE). A `SKIPPED-UNREACHABLE` or a review-only breach writes NO
  marker and instead appends to `skipped.log`.
- The **hook** (SP-C) READS the marker: if it exists AND its content == current `git rev-parse HEAD`,
  the discipline was already consulted this cycle → do not inject. Otherwise → inject the directive.
  The hook never writes the `.head` marker (a PreToolUse hook fires before the consult and cannot know
  its outcome).
- A new commit changes HEAD → content mismatch → re-arms the discipline. There is no branch-keyed
  marker with no expiry (that would permanently silence the discipline).
```

- [ ] **Step 2: Commit**

```bash
git add docs/agy-disciplines-marker-contract.md
git commit -m "docs(agy-first): publish the shared hook<->skill marker contract"
```

---

## Task 6: Enroll `agy-first` in the seed-sync check + lint gate

**Files:**
- Modify: `scripts/check-seed-artifacts-synced.sh:10-14`
- Modify: `scripts/README.md`
- Modify: `lefthook.yml` (the real pre-push gate that runs the sync-check) and/or the `justfile` recipe wrapper — verify which in Step 0

- [ ] **Step 0: State-verification.** Read `scripts/check-seed-artifacts-synced.sh` and confirm its byte-identical enumeration is the `for rel in \ ... ; do` list at lines 10-14 containing `skills/adversarial-panel-review/SKILL.md`. Read `lefthook.yml` and find the pre-push gate that already invokes `check-seed-artifacts-synced.sh` (memory: it runs there, exposed via a `just seed-sync-check` recipe) — that is the gate the new lint joins. Read the repo-root `justfile` (if present) to confirm the recipe-wrapper convention. Read `scripts/README.md` and observe its table format. If any of these differ from this description, STOP and report `STATE_MISMATCH: <what>` — do NOT invent recipe names or a stricter gate than the repo already runs.

- [ ] **Step 1: Add the skill to the byte-identical enumeration**

Edit `scripts/check-seed-artifacts-synced.sh` — add `skills/agy-first/SKILL.md \` to the `for rel in` list so it reads:
```bash
for rel in \
  skills/adversarial-panel-review/SKILL.md \
  skills/agy-first/SKILL.md \
  hooks/agy-after-reminder.sh \
  knowledge/agy-assumptions.md \
  knowledge/agy-capabilities.md ; do
```

- [ ] **Step 2: Verify the sync-check passes (both copies exist + match)**

Run: `bash scripts/check-seed-artifacts-synced.sh`
Expected: `seed agent artifacts in sync (dotnet == classic)`, exit 0.

- [ ] **Step 3: Wire the lint into the pre-push gate** (verified chain: `lefthook.yml:22 → run: just seed-sync-check` → `justfile:26-27 → bash scripts/check-seed-artifacts-synced.sh`; follow that exact convention — a `just` recipe referenced from `lefthook.yml`)

First add the recipe to `justfile` (next to `seed-sync-check`):
```just
check-agy-skills:
    pwsh -NoProfile -Command "./scripts/check-agy-discipline-skills.ps1"
```
Then add a matching pre-push entry in `lefthook.yml` next to the `just seed-sync-check` command (same `commands:` block, its own named key — 4-space key, 6-space `run:`, matching the existing entries):
```yaml
    agy-skills:
      run: just check-agy-skills
```
Do not add a new stricter gate; confirm the exact `lefthook.yml` block shape in Step 0 before editing (indentation and the surrounding `commands:` keys must match the existing entry).

- [ ] **Step 4: Add the `scripts/README.md` row**

Add a row for `check-agy-discipline-skills.ps1` in the appropriate table, matching the existing column format (script name, one-line purpose, the `just` recipe / gate that invokes it).

- [ ] **Step 5: Run the full local gate to confirm nothing regressed**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"` then `bash scripts/check-seed-artifacts-synced.sh`
Expected: Pester all green; sync-check in sync. Also run the repo's existing docs/user-facing gate if `scripts/README.md` is in the audited set — `pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/check-user-facing-docs.Tests.ps1"` — expected: still green (a new script row must not break the doc audit).

- [ ] **Step 6: Commit**

```bash
git add scripts/check-seed-artifacts-synced.sh scripts/README.md lefthook.yml justfile
git commit -m "chore(agy-first): enroll discipline skill in seed-sync + lint gate"
```

---

## Task 7: Manual-invocation smoke (no superpowers required)

**Files:** none (verification only)

Confirm the spec's "works without superpowers, manually invokable" guarantee at the skill level.

- [ ] **Step 1: Confirm the skill is discoverable in both plugins**

Run: `pwsh -NoProfile -Command "Get-ChildItem -Recurse -Filter SKILL.md clavity-dotnet/plugin/skills/agy-first, clavity-classic/plugin/skills/agy-first | Select-Object FullName"`
Expected: both `SKILL.md` paths listed.

- [ ] **Step 2: Confirm the frontmatter `name:` is `agy-first` in both** (so the Skill tool resolves `agy-first` / `clavity:agy-first` — post-SP-0 both driver plugins are named `clavity` and are mutually exclusive, so whichever is installed surfaces the skill under the single `clavity:` namespace)

Run: `pwsh -NoProfile -Command "Select-String -Path clavity-*/plugin/skills/agy-first/SKILL.md -Pattern '^name:\s*agy-first$'"`
Expected: two matches (one per plugin).

- [ ] **Step 3: No commit** — verification only. Record the result in the plan checkboxes.

---

## Definition of done (SP-A)

- `agy-first` skill shipped byte-identical in both driver plugins, carrying the AGY-FIRST protocol, the inlined AGY-NEGOTIATE sub-protocol, the safety envelope, verify-and-quote spine, the ASCII `[VERDICT]` grammar, the `SKIPPED-UNREACHABLE` out-of-band record, and the marker-write contract.
- Lint (`check-agy-discipline-skills.ps1`) + Pester green; `check-seed-artifacts-synced.sh` green; both wired into the repo's existing gate.
- Marker contract published as a shared constant doc for SP-C to consume.
- `.clavity/` gitignored.
- Manual invocation works with no superpowers dependency.

**Explicitly NOT in SP-A** (later SPs): the auto-fire hook that reads the marker (SP-C); AGY-CAPSTONE (SP-B); the superpowers-degradation / dependency-guard SessionStart wiring (SP-D); the "directive actually fires" spike (SP-C).

## Post-implementation gate (per the disciplines being shipped)
- **AGY-AFTER** panel over THIS plan before execution (Activation Auditor + Literal Implementer + Mechanism Gamer seats are the relevant lenses: skill-trigger reachability, no-placeholder completeness, and whether the self-reported `[VERDICT]` gate is gameable).
- **AGY-CAPSTONE** over the committed SP-A implementation before declaring SP-A complete — rounds until green, verify each finding by measurement.
- Owner owns the push.

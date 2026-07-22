# docs-rationalize tool — design (2026-07-22)

A maintainer tool that reflects **code changes into user-facing docs before a release push**. It replaces
the hand-run parts of the `~/.claude/skills/docs-rationalize/SKILL.md` procedure with a background,
auditable, hybrid pipeline: mechanical link-check + a headless `claude -p` accuracy audit that produces a
**punch-list** (it never rewrites), handed back to the main session where **agy writes the fixes and the
human verifies them by measurement**.

## Why (the gap this closes)

The intended tool was only half-built. What exists today:

- `mlc` mechanical link-check — `.mlc.toml` + `just check-links` (adopted `97af1f3`). Keep.
- `docs/docs-spec.md` — voices all tracked `.md` via a glob-shaped audience→voice table (broader than
  user-facing) plus a do-not-touch set. (It has no flat "user-facing" bucket — see §List storage and drift.)
- The `docs-rationalize` SKILL.md — the manual writer≠reviewer procedure.

What is missing, and this spec adds:

- The **`claude -p` headless doc-vs-code accuracy step** (never automated; done by hand as a subagent
  audit until now).
- The **orchestration** chaining link-check → accuracy audit → hand-back, with a **permanent audit log**.

## The one non-negotiable rule (inherited)

The **WRITER and the REVIEWER are different contexts.** WRITER = the agy peer (routed via `agy_ask` /
`clavity ask`, in the same tree the reviewer measures — never a worktree-isolating bridge). REVIEWER = the
driving session, verifying every changed claim **by measurement**. The `claude -p` audit is a third,
still-separate context and only ever produces findings — it does not write the docs.

## Scope: the user-facing doc list (the tool's target — 25 files)

This is **narrower than `docs-spec.md`'s full voice-table**, which also voices agent files (`CLAUDE.md`),
internal design/assumption docs, and research logs no user reads. The tool targets only the user-facing subset,
derived by an agy repo-search pass (2026-07-22) and human-approved:

**End-user / operator / integrator (12):**
`README.md`, `agy-autotrain/README.md`, `commonmemory/README.md`, `clavity-classic/README.md`,
`clavity-dotnet/README.md`, `ghidrust/README.md`, `clavity-classic/plugin/README.md`,
`clavity-dotnet/plugin/README.md`, `ghidrust/plugin/README.md`,
`clavity-classic/installer/clavity-classic-MANUAL-SETUP.md`,
`clavity-classic/installer/clavity-classic-bridge-README-FIRST.md`, `SECURITY.md`

**Contributor (10):**
`CONTRIBUTING.md`, `agy-autotrain/CONTRIBUTING.md`, `clavity-classic/CONTRIBUTING.md`,
`clavity-dotnet/CONTRIBUTING.md`, `commonmemory/CONTRIBUTING.md`, `ghidrust/CONTRIBUTING.md`,
`.github/pull_request_template.md`, `.github/ISSUE_TEMPLATE/bug_report.md`,
`.github/ISSUE_TEMPLATE/feature_request.md`, `CODE_OF_CONDUCT.md`

**Umbrella / evaluator (3):**
`docs/README.md`, `clavity-classic/docs/how-it-works.md`, `clavity-classic/docs/launching-and-driving-agy.md`

Explicitly EXCLUDED (verified, do not audit as user-facing): every `CLAUDE.md` (agent, absent-or-correct),
every `ROADMAP.md` (intent), the internal `docs/**` + `<member>/docs/**` design/assumption/research docs,
and everything in the `docs-spec.md` do-not-touch set (`**/SKILL.md`, `**/knowledge/**`,
`scripts/drain-knowledge-prompt.md`, `seed/`, `**/CHANGELOG.md`, `**/archive/**`, fixtures, generated
files). The tool's OWN generated outputs (`docs/docs-audit-findings.md`, `docs/docs-audit-log.md`) and the
sibling `docs/agy-drain-log.md` are non-user-facing generated artifacts — never audited, never added to the
list (a self-reference exclusion; see §Components).

### Voice-contract coverage (a Stage-2 precondition)

Stage 2 tells agy to rewrite each doc "per `docs-spec.md`" (§Stage 2). That is only actionable if every one
of the 25 files has a voice entry (by name or by a covering glob) in `docs-spec.md`. **Measured 2026-07-22:
`docs-spec.md` names neither `clavity-classic/docs/how-it-works.md` nor
`clavity-classic/docs/launching-and-driving-agy.md`.** SP1 must close this: extend `docs-spec.md` so all 25
user-facing docs resolve to a voice entry, and add a check (see §Testing) that fails if any listed doc has
no `docs-spec.md` entry. Absent that, Stage 2 has no voice contract for those two docs and agy will guess.

### List storage and drift

The list is a **tracked plain file**: `docs/user-facing-docs.txt` — one repo-relative path per line,
comments with `#`. Rationale: greppable, diffable, and the single source of truth the script reads. It is
referenced from `docs/docs-spec.md` (a one-line pointer).

**Two sources of truth exist** — `user-facing-docs.txt` (the 25) and `docs-spec.md` — so drift between them
is a live hazard, not a hypothetical. A one-line pointer does NOT prevent it. But note what `docs-spec.md`
actually classifies: its "Docs (audience → voice)" table is glob-shaped and **broader than user-facing** —
it carries a voice for `<member>/CLAUDE.md`, `ROADMAP.md`, `docs/**` and more, none of which are in the 25.
`docs-spec.md` has **no "user-facing" bucket**, only *in-the-voice-table* vs *do-not-touch*. So the check
must be framed to what that taxonomy can support (else it fires false positives on every CLAUDE.md/ROADMAP):
- (a) every path in `user-facing-docs.txt` exists;
- (b) every listed path resolves to a voice entry in `docs-spec.md`'s table AND is not in its do-not-touch
  set — this is the Stage-2 voice precondition, and it is implementable because the voice table is a
  superset of the 25;
- (c) drift the OTHER direction (a genuinely user-facing doc missing from the list) stays a **heuristic**
  shape-match warning — it CANNOT be a `docs-spec.md` cross-check, because `docs-spec.md` does not mark
  which of its voiced docs are user-facing. Label the (c) warning as heuristic; a maintainer confirms it.

Existence-only checking would let the two diverge as silently as a bare pointer; keying (c) off "in the
voice table" would flag every non-user-facing doc the table legitimately voices. Both are wrong — (a)+(b)+(c
-as-heuristic) is the honest guard.

## Architecture — two stages

### Stage 1 — background audit (on-demand; NOT a `just` auto-gate)

**Invocation.** Launched **on demand, in the background** — never wired into a hook, pre-push, or automatic
`just` gate. The driving session starts it as a background job and is notified on completion, then continues
in the main session with the results. A convenience `just` recipe MAY exist, but only ever run manually /
backgrounded; it is never part of an automatic gate.

**Steps (in `scripts/docs-audit.ps1`):**

1. **Link-check** — run the existing full `mlc` (`just check-links` = bare `mlc`, config in `.mlc.toml`).
   **`mlc` is NOT list-scoped**: its model is `mlc [directory]` + `--ignore-path` (scan a tree, minus
   ignores) — it does not accept a 25-file allowlist. So the link-check is inherently repo-wide (it covers
   all product docs, not just the 25); only the step-2 accuracy audit is scoped to the user-facing list.
   That is fine — a broader link-check is a bonus, and the baseline below is defined for the full run. Per
   `.mlc.toml`, the documented **expected baseline is 2 errors** (GitHub-relative release links an offline
   check cannot resolve); **any 3rd error is a genuine regression.** The script records mlc's **raw error
   count** and does NOT try to parse the baseline: `.mlc.toml`'s "2 errors" lives in a human-written COMMENT
   (~line 52), not a structured field, so regexing it would be brittle. The human compares the raw count
   against the known baseline of 2 (stated in `.mlc.toml` and echoed in the run-log header). Surface a
   regression but do not block. (Do not hard-code "4"/"a 5th" — that was wrong — and do not regex the prose
   comment either.) Because the link-check is repo-wide and not list-scopable, a narrowing/**subset run SKIPS
   it** (link-check runs on full audits only): re-running the full-tree mlc for a 1-doc audit costs the whole
   scan and adds nothing list-specific.
2. **Accuracy audit** — for each doc in scope, invoke a headless `claude -p` that reads *that doc's own*
   cited paths/commands/flags and verifies each against the current code (no code→doc map needed; the doc's
   claims are the audit surface). The invocation is **read-only**: it audits and reports, it never edits, so
   it must NOT carry `--dangerously-skip-permissions` or any write/edit grant (that flag exists on
   `drain-knowledge.ps1`'s curator *because that curator edits files* — the audit must not inherit it).
   Output per doc: a punch-list of accuracy/staleness findings, each with the proving `code:line`, **plus a
   mandatory liveness token: the count of claims the audit actually inspected in that doc.** The token is
   self-reported by the same untrusted `claude -p`, so it is not a full guarantee — it reliably catches the
   0-claim case (refusal / apology / empty output), but a confabulating audit could report a nonzero count
   without truly reading. Harden it cheaply but CONSERVATIVELY: do NOT equate the claim-count to a per-span
   tally — a single command with three flags is ~4 inline-`code` spans but ~1 claim, so a 1:1 floor would
   over-trigger and flood `AUDIT-SUSPECT`. Use a coarse degeneracy check instead: e.g. a doc with several
   fenced code blocks whose audit reports 0–1 claims inspected is `AUDIT-SUSPECT`. The exact heuristic is a
   plan decision; err toward under-flagging (a false SUSPECT is noise the human must triage). This is a
   floor, not proof; the human still spot-checks a sample per §Stage 2.
   - The prompt is a first-class, templated file — `scripts/docs-audit-prompt.md` (mirrors
     `scripts/drain-knowledge-prompt.md`): it defines the extract-claims-and-trace-to-code contract and the
     required output shape (findings + claim-count). The script templates the doc path into it, exactly as
     `drain-knowledge.ps1` templates `{{STAGING_PATH}}`/`{{REPO_ROOT}}`.
   - **The `claude -p` call is the single external boundary and is exercised in tests via a
     parameter-injected seam, NOT a Pester `Mock`.** `drain-knowledge.ps1` does this with a `-SkipCurator`
     switch (skip the live call) and a `-CuratorStub` path-to-`.ps1` (run a stub in place of the live call),
     precisely because a Pester `Mock claude {}` in the parent process cannot cross a `pwsh -File`
     child-process boundary — the child would call the real CLI while the parent's mock records nothing, a
     vacuous green. `docs-audit.ps1` mirrors that seam: expose `-SkipAudit` / `-AuditStub` (or an
     equivalent single stub-path parameter) so tests inject audit outcomes deterministically.
3. **Write artifacts INCREMENTALLY (no doc edits, no commit):**
   - **Punch-list** — `docs/docs-audit-findings.md`: per-doc findings the main thread consumes. Empty
     findings for a doc that DID run (claim-count > 0) mean "clean"; a doc with no entry at all means "not
     yet audited / audit did not complete". **A subset (narrowing-arg) run must update only the audited
     docs' sections and preserve every other doc's existing findings — it must NOT wipe the file and
     regenerate from scratch, or a 3-doc re-run silently destroys the other 22 docs' unactioned findings
     that Stage 2 still needs.** Implement as a per-doc keyed merge (read existing, replace only audited
     docs' sections, rewrite). **The merge is outcome-aware:** only a re-run that reaches `CLEAN` or
     `FINDINGS` replaces a doc's prior section; a re-run that returns `AUDIT-INCONCLUSIVE` or `AUDIT-SUSPECT`
     must PRESERVE the doc's prior findings and annotate them with the failed re-attempt — never silently
     drop the old findings (they may still hold — the doc did not change, the audit merely failed), and
     never silently hide the failed re-audit. Stage 2 then sees both the known work items and that the
     latest re-audit could not confirm them.
   - **Permanent log** — `docs/docs-audit-log.md` (**append-only**): the run's entry is opened before the
     audit loop and **each doc's outcome is appended as that doc completes**, not batched at the end. This is
     what makes the "trail is never silently lost on partial failure" guarantee true: if the run crashes at
     doc 20, docs 1–19's outcomes are already durably on disk. Each per-doc line records the doc path, its
     **audit outcome** (§Per-doc outcome states), the **invocation shape** (model alias + prompt-file + doc
     path — NOT the fully expanded prompt, which would bloat an append-only file 25× per run), the
     claim-count liveness token, and the findings. The run-entry **header** (written once, before the loop)
     carries the caller-supplied run id + timestamp AND the **repo-wide `mlc` result** — mlc is global (one
     result per run, and a subset run skips it entirely), so it lives in the header, never duplicated into
     per-doc lines where a subset run would leave it undefined.

**Makes no doc edits and no commit.** It is advisory: it never blocks a release; the human decides what to
act on.

### Stage 2 — main thread (agy writes, human checks)

On pickup, the driving session reads `docs/docs-audit-findings.md`. For each doc with findings:

1. Point agy (via `agy_ask` / `clavity ask`, in-tree) at the doc + its punch-list; agy rewrites the doc
   terse/scannable per `docs-spec.md`, fixing the findings. (Precondition: the doc has a `docs-spec.md`
   voice entry — see §Voice-contract coverage.)
2. The human **verifies every changed claim by measurement** (grep/read the cited source) — agy can state a
   false claim with confidence — and drives corrections until clean.
3. The human commits; the owner pushes (the release push gate).

## Components / files

| Path | Role | New? |
|---|---|---|
| `docs/user-facing-docs.txt` | the 25-doc target list (source of truth) | new |
| `scripts/docs-audit.ps1` | Stage 1 script (mlc + `claude -p` audit + incremental log) | new |
| `scripts/docs-audit-prompt.md` | the templated audit-prompt contract (extract claims → trace to code) | new |
| `docs/docs-audit-findings.md` | per-doc punch-list, per-doc merge on subset runs | new (generated) |
| `docs/docs-audit-log.md` | append-only permanent audit log, written incrementally | new (generated) |
| `.mlc.toml`, `just check-links` | reused mechanical link-check | exists |
| `docs/docs-spec.md` | audience/voice contract + do-not-touch; gains the list pointer + voice entries for all 25 | exists, edited |
| `~/.claude/skills/docs-rationalize/SKILL.md` | documents Stage 2 (agy writes / human checks); references the tool for Stage 1 | exists, edited |

The two generated files (`docs-audit-findings.md`, `docs-audit-log.md`) are non-user-facing generated
artifacts: **never audited, never in `user-facing-docs.txt`** (self-reference exclusion). They do not need a
special installer rule — no `installer/*.iss` packages the root `docs/` tree, so nothing ships them (the
sibling `docs/agy-drain-log.md` is in the same position — it is not human-facing and no installer excludes
it because none includes it). If either file trips `mlc`, add it to `.mlc.toml`'s ignore list.

## Per-doc outcome states (the complete set SP2 implements)

Every audited doc resolves to exactly one of these — enumerated here so SP2 and the Stage-2 reader agree on
one state machine rather than four scattered mentions:

| State | Trigger | Reads as |
|---|---|---|
| `CLEAN` | claim-count > 0, zero findings | nothing to fix |
| `FINDINGS` | ≥ 1 accuracy/staleness finding | Stage-2 work items |
| `AUDIT-INCONCLUSIVE` | claim-count = 0 (refusal/empty), a hard `claude -p` failure, **or** a per-doc timeout (`AUDIT-TIMEOUT` is a labelled sub-case of this state) | audit did not truly run — NOT clean; human re-runs |
| `AUDIT-SUSPECT` | claim-count is degenerately low vs the coarse mechanical floor (§Stage 1.2) | possible non-read — human spot-checks |

`CLEAN` requires claim-count > 0; a doc with no entry at all means "not yet audited". No other state exists.

## Error handling

- **A single `claude -p` doc audit fails** → log the failure in that doc's (already-open) entry as
  `AUDIT-INCONCLUSIVE`, continue the rest; the run still completes. One bad doc never sinks the batch.
- **A doc audit soft-fails (exit 0 but did not really read the doc — a refusal, an apology, empty output)**
  → this is the dangerous case: an empty findings section would read as "clean". The mandatory claim-count
  liveness token (§Stage 1.2) defends against it — a doc whose audit reports **0 claims inspected** is
  recorded as `AUDIT-INCONCLUSIVE`, not clean, and surfaced to the human. Absence of findings is only
  "clean" when claim-count > 0.
- **mlc baseline vs regression** → the 2 documented in `.mlc.toml` are expected; a 3rd is a real regression,
  surfaced but non-blocking.
- **The audit never mutates or blocks** → worst case it produces an incomplete punch-list, which the human
  sees in the log.
- **Permanent log is append-only and written per-doc** → because each doc's outcome is appended as it
  completes (not batched at the end), a mid-run crash still leaves every completed doc's outcome on disk.
- **Concurrent runs must not interleave** → because the tool is backgrounded and appends per-doc, two
  overlapping runs would interleave their lines into `docs-audit-log.md` and race on the punch-list. A
  single-run refuse-guard (a lock/marker file) makes a second concurrent start refuse cleanly rather than
  corrupt the log. **But it must be SELF-CLEARING, unlike `drain-knowledge.ps1`'s marker** — drain's marker
  is deliberately human-cleared (by `accept-drain` / `abort-drain`, because a pending drain awaits a human
  decision), so blindly copying it would let a crashed background audit **permanently wedge every future
  run**. Remove the lock in a `finally`, and treat a lock older than a run-max age or whose recorded PID is
  dead as stale and reclaim it.

## Testing (Pester, mirroring the drain tooling)

`scripts/tests/docs-audit.Tests.ps1`:

- List parsing: reads `docs/user-facing-docs.txt`, ignores comments/blanks, resolves paths.
- Scope arg: full list by default; a narrowing arg audits only the named subset.
- **Audit seam (parameter-injected, not a Pester `Mock`)**: drive `docs-audit.ps1` with its `-SkipAudit` /
  `-AuditStub` seam (as `drain-knowledge.ps1` is driven with `-SkipCurator` / `-CuratorStub`). Assert the
  stub is invoked once per in-scope doc with the doc path, and that a stubbed finding lands in the punch-list
  + log. Do NOT `Mock claude` — the child `pwsh -File` boundary defeats it (that is the whole reason the
  seam is a stub parameter).
- Liveness token: a stub returning 0 claims yields `AUDIT-INCONCLUSIVE`, not an empty-clean section.
- Log is append-only and incremental: a doc's entry is on disk before the next doc runs; a second run does
  not truncate the first run's entry.
- **Subset run preserves other docs' findings**: seed the punch-list with findings for docs A/B/C, run a
  subset audit of only doc A, assert B's and C's findings survive.
- Partial failure: a stubbed failing doc audit is logged and does not abort the others, and the docs already
  completed keep their log entries.
- **Outcome-aware merge on a failed re-run**: seed the punch-list with `FINDINGS` for doc A, run a subset
  re-audit of A whose stub returns `AUDIT-INCONCLUSIVE`, assert A's prior findings SURVIVE (annotated with
  the failed re-attempt), not overwritten — and the failed re-audit is not hidden.
- **`AUDIT-SUSPECT` floor**: a stub reporting a degenerately-low claim-count for a code-block-heavy doc
  yields `AUDIT-SUSPECT`, not `CLEAN`.
- **Self-clearing lock**: a second concurrent start refuses cleanly; and a stale lock (dead PID or past
  max-age) is reclaimed rather than treated as live — a crashed prior run does not wedge the next.

A separate check (extend `check-member-docs` or a small `check-user-facing-docs.ps1`) asserts (a) every path
in `docs/user-facing-docs.txt` exists; (b) every listed path resolves to a voice entry in `docs-spec.md`'s
table and is not in its do-not-touch set — the Stage-2 voice precondition (note `docs-spec.md` has NO
"user-facing" bucket to key on, only voice-table vs do-not-touch, per §List storage and drift); and (c) as a
**heuristic** shape-match, warns when a tracked doc that looks user-facing is absent from the list — a
maintainer confirms it, because it CANNOT be a `docs-spec.md` cross-check. (a)+(b)+(c-as-heuristic) are the
anti-drift guard for the two sources of truth.

## Sub-project decomposition

- **SP1** — `docs/user-facing-docs.txt` + the existence/classification/voice-coverage check + the
  `docs-spec.md` pointer AND its voice entries for all 25 (closing the `how-it-works` /
  `launching-and-driving-agy` gap). Gates the rest — **and specifically gates SP3**: SP1's `docs-spec.md`
  voice entries are the contract SP3's Stage-2 rewrites "per `docs-spec.md`" against, so Stage-2 is not
  executable for those two docs until SP1 lands them.
- **SP2** — `scripts/docs-audit.ps1` (mlc + read-only `claude -p` audit + `docs-audit-prompt.md` +
  per-doc-merged punch-list + incremental append-only log + single-run refuse-guard) + its Pester tests,
  with the audit seam parameter-injected (`-SkipAudit` / `-AuditStub`). **SP2's opening step must first
  resolve the two Deferred items it structurally depends on — the punch-list store format and the fan-out
  shape — because you cannot build the per-doc merge or the audit loop without them** (a deferred decision
  that gates the task, not one that can wait for "later").
- **SP3** — the Stage-2 main-thread workflow: update `docs-rationalize` SKILL.md to reference the tool for
  Stage 1 and own Stage 2 (agy writes / human checks / commit). Depends on SP1 (voice entries) and SP2 (the
  punch-list it consumes).

## Deferred (decide in the plan, not here)

- The `claude -p` model tier (lean: the cheapest that reliably traces claims to code; escalate only on a
  capability miss). The audit takes its OWN model-override env var (e.g. `CLAVITY_DOCS_AUDIT_MODEL`) — it
  must NOT reuse `drain-knowledge.ps1`'s `CLAVITY_DRAIN_MODEL`. Precondition: the `claude` CLI is installed +
  authenticated (a global auth failure surfaces as N `AUDIT-INCONCLUSIVE`, not silent clean, via the
  liveness token); `mlc` is already declared in `.claude/recommended-tools.json`.
- Audit fan-out shape — the audit is O(N) cold `claude -p` invocations (25 today, growing with the list),
  run sequentially. Whether to bound concurrency, batch docs per call, or add a per-invocation timeout so a
  single hang cannot stall the whole background run is a plan decision; default is sequential with a
  per-doc timeout that records `AUDIT-TIMEOUT` (a specific `AUDIT-INCONCLUSIVE`) and moves on.
- Punch-list format (markdown vs JSON) — the per-doc-keyed merge (§Stage 1.3) is the deciding constraint,
  not human readability: a naive `##`-heading markdown merge is fragile (a stray heading inside a finding
  corrupts the parse and can truncate a neighbouring doc's section). Prefer a STRUCTURED durable store (JSON
  keyed by doc path) that merges safely, rendered to a markdown VIEW for the human; if markdown is kept as
  the store, each doc's section must be bracketed by explicit machine-parseable delimiters
  (`<!-- doc:PATH start -->…<!-- doc:PATH end -->`), never bare headings.
- git-diff auto-scoping (audit only docs whose cited code intersects the diff) — deferred; default is the
  full list with a manual narrowing arg, because a code→doc map is fragile and the full list is a safer net.

## Exhaustiveness self-audit

- **Contracts pinned:** list file format (one path/line, `#` comments); log format (header: run id,
  timestamp, repo-wide mlc result; per-doc: path, audit outcome, invocation shape, claim-count, findings),
  append-only + incremental;
  punch-list is per-doc, subset-merge not wipe. Timestamp + run id are caller-supplied (scripts must not
  call `Date.now`-equivalents that break determinism in tests — pass them in).
- **Placeholders:** none; every deferred item names WHERE it resolves (the plan).
- **Edges covered:** single-doc hard-failure, single-doc soft-failure (liveness token), mlc baseline vs
  regression (2 / 3rd), empty-but-ran (clean) vs not-run (inconclusive), append-only + incremental log,
  subset run not clobbering others, scope arg, list drift (existence + classification + voice check),
  read-only least-privilege audit.
- **Requirements mapped:** punch-list-not-rewrite (§Stage 1.2), permanent+incremental log (§Stage 1.3),
  background + not-a-just-gate (§Stage 1 invocation), agy-writes/human-checks (§Stage 2), the 25-doc list
  (§Scope), voice-contract precondition (§Voice-contract coverage).
- **Remaining open:** the 4 Deferred items above — each explicitly routed to the implementation plan.

# docs-rationalize tool — design (2026-07-22)

A maintainer tool that reflects **code changes into user-facing docs before a release push**. It replaces
the hand-run parts of the `~/.claude/skills/docs-rationalize/SKILL.md` procedure with a background,
auditable, hybrid pipeline: mechanical link-check + a headless `claude -p` accuracy audit that produces a
**punch-list** (it never rewrites), handed back to the main session where **agy writes the fixes and the
human verifies them by measurement**.

## Why (the gap this closes)

The intended tool was only half-built. What exists today:

- `mlc` mechanical link-check — `.mlc.toml` + `just check-links` (adopted `97af1f3`; 4 known/explained
  baseline errors). Keep.
- `docs/docs-spec.md` — classifies all tracked `.md` into 46 "in-scope" (for a *full* docs-rationalize)
  plus the do-not-touch set.
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

This is **narrower than `docs-spec.md`'s 46 in-scope.** The 46 includes agent files (`CLAUDE.md`), internal
design/assumption docs, and research logs no user reads. The tool targets only the user-facing subset,
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
`scripts/drain-knowledge-prompt.md`, `seed/`, `**/CHANGELOG.md`, `**/archive/**`, fixtures, generated files).

### List storage

The list is a **tracked plain file**: `docs/user-facing-docs.txt` — one repo-relative path per line,
comments with `#`. Rationale: greppable, diffable, and the single source of truth the script reads. It is
referenced from `docs/docs-spec.md` (a one-line pointer) so the two do not drift silently. A future check
(see Testing) can assert every listed file exists and flag a new user-facing doc that is absent from it.

## Architecture — two stages

### Stage 1 — background audit (on-demand; NOT a `just` auto-gate)

**Invocation.** Launched **on demand, in the background** — never wired into a hook, pre-push, or automatic
`just` gate. The driving session starts it as a background job and is notified on completion, then continues
in the main session with the results. A convenience `just` recipe MAY exist, but only ever run manually /
backgrounded; it is never part of an automatic gate.

**Steps (in `scripts/docs-audit.ps1`):**

1. **Link-check** — run `mlc` over the user-facing list (reuse `.mlc.toml`). Record its result; the 4 known
   baseline errors documented in `.mlc.toml` are NOT failures.
2. **Accuracy audit** — for each doc in scope, invoke a headless `claude -p` that reads *that doc's own*
   cited paths/commands/flags and verifies each against the current code (no code→doc map needed; the doc's
   claims are the audit surface). Output per doc: a punch-list of accuracy/staleness findings, each with the
   proving `code:line`. The `claude -p` call is the single external boundary and is **mockable** for tests
   (mirror `scripts/drain-knowledge.ps1`'s test seam).
3. **Write artifacts** (no doc edits, no commit):
   - **Punch-list** — `docs/docs-audit-findings.md` (regenerated each run): per-doc findings the main
     thread consumes. Empty sections mean "clean".
   - **Permanent log** — `docs/docs-audit-log.md` (**append-only**): one entry per run with a run id, a
     caller-supplied timestamp, the docs audited, the mlc result, the exact `claude -p` invocation(s), and
     the findings. This is the audit trail — the maintainer can inspect exactly what the headless pass did.

**Makes no doc edits and no commit.** It is advisory: it never blocks a release; the human decides what to
act on.

### Stage 2 — main thread (agy writes, human checks)

On pickup, the driving session reads `docs/docs-audit-findings.md`. For each doc with findings:

1. Point agy (via `agy_ask` / `clavity ask`, in-tree) at the doc + its punch-list; agy rewrites the doc
   terse/scannable per `docs-spec.md`, fixing the findings.
2. The human **verifies every changed claim by measurement** (grep/read the cited source) — agy can state a
   false claim with confidence — and drives corrections until clean.
3. The human commits; the owner pushes (the release push gate).

## Components / files

| Path | Role | New? |
|---|---|---|
| `docs/user-facing-docs.txt` | the 25-doc target list (source of truth) | new |
| `scripts/docs-audit.ps1` | Stage 1 script (mlc + `claude -p` audit + log) | new |
| `docs/docs-audit-findings.md` | regenerated per-run punch-list | new (generated) |
| `docs/docs-audit-log.md` | append-only permanent audit log | new (generated) |
| `.mlc.toml`, `just check-links` | reused mechanical link-check | exists |
| `docs/docs-spec.md` | audience/voice contract + do-not-touch; gains a pointer to the list | exists |
| `~/.claude/skills/docs-rationalize/SKILL.md` | documents Stage 2 (agy writes / human checks); references the tool for Stage 1 | exists, edited |

Both generated files (`docs-audit-findings.md`, `docs-audit-log.md`) are installer-excluded like
`docs/agy-drain-log.md`, and added to `.mlc.toml` ignore if they trip link-check.

## Error handling

- **A single `claude -p` doc audit fails** → log the failure in that doc's entry, continue the rest; the run
  still completes and writes its log. One bad doc never sinks the batch.
- **mlc baseline errors** → the 4 explained in `.mlc.toml` are expected; a 5th is a real regression, surfaced
  but non-blocking.
- **The audit never mutates or blocks** → worst case it produces an incomplete punch-list, which the human
  sees in the log.
- **Permanent log is append-only** → a run always appends its entry, even on partial failure, so the trail
  is never silently lost.

## Testing (Pester, mirroring the drain tooling)

`scripts/tests/docs-audit.Tests.ps1`:

- List parsing: reads `docs/user-facing-docs.txt`, ignores comments/blanks, resolves paths.
- Scope arg: full list by default; a narrowing arg audits only the named subset.
- `claude -p` seam: mocked (as `drain-knowledge.ps1` mocks its curator) — assert it is invoked once per
  in-scope doc with the doc path, and that a mocked finding lands in the punch-list + log.
- Log is append-only: a second run does not truncate the first run's entry.
- Partial failure: a mocked failing doc audit is logged and does not abort the others.

A separate check (extend `check-member-docs` or a small `check-user-facing-docs.ps1`) asserts every path in
`docs/user-facing-docs.txt` exists and, optionally, warns when a tracked doc matches a user-facing shape but
is absent from the list.

## Sub-project decomposition

- **SP1** — `docs/user-facing-docs.txt` + the existence check + the `docs-spec.md` pointer. (Gates the rest.)
- **SP2** — `scripts/docs-audit.ps1` (mlc + `claude -p` audit + punch-list + append-only log) + its Pester
  tests, with the `claude -p` seam mocked.
- **SP3** — the Stage-2 main-thread workflow: update `docs-rationalize` SKILL.md to reference the tool for
  Stage 1 and own Stage 2 (agy writes / human checks / commit).

## Deferred (decide in the plan, not here)

- The `claude -p` model tier (lean: the cheapest that reliably traces claims to code; escalate only on a
  capability miss).
- Punch-list format (markdown vs JSON) — markdown by default for human review; revisit if the main thread
  needs to parse it programmatically.
- git-diff auto-scoping (audit only docs whose cited code intersects the diff) — deferred; default is the
  full list with a manual narrowing arg, because a code→doc map is fragile and the full list is a safer net.

## Exhaustiveness self-audit

- **Contracts pinned:** list file format (one path/line, `#` comments); log format (run id, timestamp,
  docs, mlc result, `claude -p` invocation, findings); punch-list is per-doc, regenerated. Timestamp is
  caller-supplied (scripts must not call `Date.now`-equivalents that break determinism in tests — pass it in).
- **Placeholders:** none; every deferred item names WHERE it resolves (the plan).
- **Edges covered:** single-doc failure, mlc baseline vs regression, empty findings (clean), append-only log,
  scope arg, list drift (the check).
- **Requirements mapped:** punch-list-not-rewrite (§Stage 1.2), permanent log (§Stage 1.3), background +
  not-a-just-gate (§Stage 1 invocation), agy-writes/human-checks (§Stage 2), the 25-doc list (§Scope).
- **Remaining open:** the 3 Deferred items above — each explicitly routed to the implementation plan.

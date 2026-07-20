# Drain-knowledge maintainer runbook

`agy-learn` captures land in a machine-local app-data inbox (`agy-observations.md`, `## Pending`
section) — they are **not** shippable until a maintainer drains them into the four committed manuals
(`clavity-dotnet/plugin/knowledge/agy-{assumptions,capabilities}.md` and their `clavity-classic`
mirrors) and the injected SEED (`seed/golden-header.md`). This runbook is the maintainer procedure for
that drain. It is dev-facing only — it never ships and nothing here runs on an end-user box.

The three recipes are thin wrappers around `scripts/drain-knowledge.ps1`, `scripts/abort-drain.ps1`,
and `scripts/accept-drain.ps1`. Read those scripts (and `scripts/drain-lib.ps1`) as the ground truth if
this doc and their behavior ever disagree — the scripts win.

## The three recipes and their contract

| Recipe | Script | What it does |
|---|---|---|
| `just drain-knowledge [-WhatIf]` | `scripts/drain-knowledge.ps1` | Stages `## Pending` observations, runs a headless `claude -p` curator to fold them into the manuals + SEED, runs the `[Core]`-integrity gate (hard) and the SEED-budget gate (warn), and appends a summary to `docs/agy-drain-log.md`. **Makes NO commit.** |
| `just accept-drain` | `scripts/accept-drain.ps1` | Confirms the drain's run-ID is in the **committed** `docs/agy-drain-log.md` and the tree is clean, then deletes the staging snapshot. This is the "I reviewed and committed it" step. |
| `just abort-drain` | `scripts/abort-drain.ps1` | Refuses outright (nothing touched, staging retained) if the tree has an unrelated tracked change or an unrelated untracked file under the drain's output paths — see the exit-code table below. Otherwise runs `git reset --hard HEAD` — an unscoped whole-tree reset of every tracked file, not just the drain's outputs — removes the drain's untracked outputs, and re-queues the staged observations back into `## Pending` of the inbox. This is the "reject this drain" step. |

The maintainer loop is:

1. `just drain-knowledge` (on a pristine tree — see below).
2. Review `git diff` (especially the golden-header SEED diff and the four manuals) and read
   `docs/agy-drain-proposal.md` (the curator's sidecar — what it dropped/merged/parked, and why).
3. Either:
   - **Accept**: `git add` the changed files, commit, then `just accept-drain` (deletes the staging
     snapshot — the drain is now permanent).
   - **Reject**: `just abort-drain` (no commit needed — it reverts everything and re-queues the
     observations for a future drain attempt).

`drain-knowledge` never commits on its own; the maintainer is always the one who decides whether a
drain's output is good enough to land, by committing it (or not) between steps 1 and 2/3 above.

## Security / trust model

`just drain-knowledge` runs the curator as a **headless Claude session with
`--dangerously-skip-permissions`**: by design (it must edit the manuals and SEED unattended, with no
one present to click "approve"), that flag makes it auto-approve **every** tool call, including Bash —
no prompting, no confirmation.

That curator's *input* is the batch of `## Pending` observations captured by `agy-learn` — machine-local
captures that are, from the drain's point of view, **untrusted**. The deterministic gates that run after
the curator (the `[Core]` set-equality check, the SEED-budget check) and the human `git diff` review in
the maintainer loop above all inspect the *resulting file contents* — they check what the curator wrote,
not what it *did* while writing it. None of them defend against a prompt-injected observation that gets
the curator to run an arbitrary tool (including shell) **during** the run, before any gate ever sees the
output.

**Practical consequence:** only drain observations you trust, on a machine you control. Treat
`just drain-knowledge` as running trusted-but-unverified code over your own captures, not as a sandboxed
or content-filtered pipeline. This is an accepted dev-only residual risk — the runbook is dev-facing only
and the maintainer runs the drain deliberately, on their own box, over their own captures. A future
hardening could scope the curator's allowed tools instead of granting it all of them.

## The pristine-tree precondition

`just drain-knowledge` refuses to run if the working tree is dirty (`git status --porcelain` is
non-empty at the start): **exit 4**. Commit or stash everything first. This exists so that (a)
`abort-drain`'s revert-to-HEAD is safe — it can never destroy pre-existing uncommitted work — and (b)
every file the curator touches, including a hallucinated stray path outside the known output set, is
attributable to this drain and visible in `git diff` before you accept.

## The run-ID / staging / drain-log recovery transaction

Each drain gets a run-ID and moves the inbox's `## Pending` section into a staging snapshot file
(`agy-observations.staging.<runId>.md`, in the same app-data directory as the inbox) before invoking
the curator. That staging file is the recovery anchor: it exists only while a drain is pending a
maintainer decision, and both `accept-drain` and `abort-drain` key off it.

Beside it the drain writes an **output manifest**, `agy-observations.staging.<runId>.outputs.txt`:
one repo-relative path per line, listing every untracked file the curator created this run under the
drain's output paths. It is derived, not declared — the drain snapshots `git ls-files --others` over
those paths before and after the curator runs and takes the difference, so it stays correct even if
the curator's prompt changes or it misreports what it wrote. In practice this only ever names files
under `docs/fix-the-tool-backlog/`, whose slugs the curator picks per run.

`abort-drain` needs it because its `git clean -fd` step deletes untracked files under those paths: the
manifest is how it tells the curator's own new backlog file (safe to remove) from a note you dropped in
the same directory during the review pause (must not be). An empty manifest is valid and means the
curator created nothing new. Its **absence** means the run predates this mechanism, and `abort-drain`
then falls back to refusing on any unrecognised untracked file there. Both `accept-drain` and
`abort-drain` delete it alongside the staging snapshot, so it never outlives its run.

**`drain-knowledge` exit codes:**

| Exit | Condition |
|---|---|
| `0` | Success — drain ran and finished (including the "nothing to drain, `## Pending` is empty" case). |
| `2` | Refuse-guard: a prior drain's staging file is still pending a decision. Resolve it first with `just accept-drain` (after committing) or `just abort-drain`. |
| `3` | `[Core]`-integrity check failed after the curator ran. **Staging is retained** — run `just abort-drain` to reject and recover. |
| `4` | Working tree was dirty at the pristine-tree precondition check (see above). |

The SEED-budget check (step 7 of the script) is **warn-only** inside `drain-knowledge` — an
over-budget SEED does not block the drain or change its exit code; it's a signal that the curator
should have parked a demotion. The hard budget gate lives in the release preflight (CI), not here.

**`abort-drain` exit codes:**

| Exit | Condition |
|---|---|
| `0` | No pending staging file (nothing to abort) — or a successful reject: tracked files reverted to `HEAD`, untracked drain outputs cleaned, staged observations re-queued into `## Pending`, staging file removed. |
| `1` | The run-ID is **already in the committed** `docs/agy-drain-log.md` — aborting would re-queue already-shipped observations, so it refuses; use `just accept-drain` instead. |
| `1` | **REFUSES** — a modified/staged **tracked** file is not one of the drain's own outputs, so `git reset --hard HEAD` would silently destroy it. Nothing is touched; staging retained. Move, commit, or delete the file, then re-run. |
| `1` | **REFUSES** — an **untracked** file under one of the drain's output paths (e.g. `docs/fix-the-tool-backlog/`) is neither one of the eight individually-named outputs nor listed in this run's output manifest, so the scoped `git clean -fd` would delete it. Nothing is touched; staging retained. Move, commit, or delete the file, then re-run. A backlog file the curator wrote *this run* does NOT trigger this: `drain-knowledge` records it in the manifest (below), so it is recognised as the drain's own output and cleaned normally. |
| `1` | **REFUSES (runs predating the manifest only)** — with no `…outputs.txt` manifest beside the staging snapshot, the drain has no record of which backlog files its curator wrote, so *any* untracked file under `docs/fix-the-tool-backlog/` is refused. Delete it yourself if it is the drain's output, or move your own file aside, then re-run. |
| `1` | `git reset --hard HEAD` (the revert) failed — tree not reverted; staging retained so you can fix the repo and re-run. |
| `1` | `git clean -fd` (removing the drain's untracked outputs) failed — staging retained; fix the repo and re-run. |

(Both `git reset --hard HEAD` and `git clean` failures share exit `1`; the console message tells you which step
failed.) After a successful revert+clean, `abort-drain` also surfaces (non-fatally) any file that still
differs from `HEAD` — a possible curator stray outside the known output set — for you to review by hand.

**`accept-drain` exit codes:**

| Exit | Condition |
|---|---|
| `0` | No pending staging file (nothing to accept) — or a successful accept: staging snapshot deleted. |
| `1` | The run-ID is **not** in the committed `docs/agy-drain-log.md` — commit the drain's changes first (`git add` + commit), then re-run; or run `just abort-drain` to reject instead. |
| `1` | The working tree is dirty (uncommitted drain outputs remain) — commit them before accepting. |
| `1` | `git status` itself failed — accept cannot confirm a clean tree; staging retained; fix the repo and re-run. |

In short: `accept-drain` requires BOTH "run-ID is committed" AND "tree is clean" before it will delete
the staging snapshot; any failure leaves the staging file in place so the pending drain isn't silently
lost.

## `SEED_MAX_BYTES` — the SEED byte budget

The budget lives as the `-MaxBytes` **default parameter value in `scripts/check-seed-budget.ps1`**
(currently `7992`, chosen as 8 KiB minus ~200 B of runtime-escalation-index headroom). It is the single
source of truth — there is no separate config file or env var. To bump it deliberately, edit that
default and commit the change; do not pass `-MaxBytes` ad hoc as a workaround, since CI and other
maintainers won't see an uncommitted override.

`check-seed-budget.ps1` treats a missing SEED file as 0 bytes (never crashes on a fresh clone that
hasn't been drained yet).

## The `**[Core]**` and `[SEED-tier]` markers

- **`**[Core]**`** — a line in the SEED or one of the four manuals that begins with the literal marker
  `**[Core]**` (leading whitespace tolerated) is **maintainer-owned and script-locked**. The
  `check-core-integrity.ps1` gate (run as a hard block inside `drain-knowledge`, step 6, exit 3 on
  failure) enforces **set-equality** between the committed `HEAD` version of each guarded file and the
  working-tree version: every `[Core]` line present at `HEAD` must survive **verbatim**, and no **new**
  `[Core]` line may appear. The curator (and, by extension, any drain) may never add, alter, or remove
  a `[Core]` line — this is what closes the prompt-injection hole where a hostile observation tries to
  get the curator to write a new `**[Core]**` line into the SEED. If a file has no committed baseline
  yet (new/uncommitted), there is nothing to protect and the check skips it; if a guarded file with
  committed `[Core]` lines is deleted entirely, that's also a hard fail.
- **`[SEED-tier]`** — by contrast, this marker is **human-diff-gated, not script-enforced**. It's
  editable by the curator; nothing in the scripts checks its set-equality. Its survival across a drain
  is entirely a matter of maintainer review — read the SEED diff during review (step 2 of the loop
  above) and confirm no `[SEED-tier]` rule was silently dropped by an LLM formatting slip.

## Review discipline

Before accepting a drain:

- Read the full `git diff`, not just the SEED — the curator can touch all four manuals plus the SEED.
- Read `docs/agy-drain-proposal.md` (the curator's sidecar for that run) to see what it dropped,
  merged, or parked, and why.
- Cross-check `docs/agy-drain-log.md` — `drain-knowledge` appends a summary line (SEED bytes
  before/after, verify-needed count, and the sidecar's Dropped/Parked sections) for every run, giving
  you a running audit trail independent of the working-tree diff.
- For any item the curator left in `docs/agy-verify-needed.md` (assumptions it couldn't verify from
  the observation alone), run a **live verify-probe** against the real agy peer before re-draining or
  promoting that item — don't accept an unverified assumption into a manual on the curator's say-so
  alone.

If you reject the drain (`just abort-drain`), the staged observations are automatically re-queued into
`## Pending` so nothing is lost — you can re-attempt the drain later (after fixing the inbox, adjusting
the curator prompt, or waiting for more captures to accumulate).

## Dev prerequisite: Pester

The drain scripts' tests (`scripts/tests/*.Tests.ps1`) run under [Pester](https://pester.dev/), the
PowerShell testing framework. It is not bundled with PowerShell — install it once per dev box:

```powershell
Install-Module Pester -Scope CurrentUser -Force
```

Then run the suite with:

```powershell
Invoke-Pester scripts/tests/
```

Pester is a **manual dev prerequisite** — install it yourself. The `.claude/recommended-tools.json`
entry documents Pester and its install command, but the `SessionStart` tooling check only presence-checks
PATH executables and exact file paths; it cannot check for an installed PowerShell *module*, so it will
NOT auto-remind you when Pester is missing.

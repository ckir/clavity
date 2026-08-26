# Drain-knowledge maintainer runbook

`agy-learn` captures land in a machine-local app-data inbox (`agy-observations.md`, `## Pending`
section). A maintainer drains them into a reviewable **GROWTH proposal**
(`docs/agy-golden-header.growth.md`) plus a few docs side-artifacts, and then publishes that proposal
to the runtime golden-header (`~/.clavity/golden-header.growth.md`). **That publish is the end of this
loop, and it is still MACHINE-LOCAL — it does not ship anything to anyone.** Getting knowledge to
other users is a separate, human step; see "How knowledge actually reaches a user" below. This is the
**EXTEND model**: the curator never edits the driver-owned SEED (`seed/golden-header.md`), the four
driver manuals (`clavity-dotnet/plugin/knowledge/agy-{assumptions,capabilities}.md` and their
`clavity-classic` mirrors), or `agy-autotrain/knowledge/driver-cheatsheet.core.md` — those stay
maintainer/driver-owned and untouched by any drain. This runbook is the maintainer procedure for
the drain → review → accept/abort loop. It is dev-facing only — it never ships and nothing here
runs on an end-user box.

The three recipes are thin wrappers around `scripts/drain-knowledge.ps1`, `scripts/abort-drain.ps1`,
and `scripts/accept-drain.ps1`. Read those scripts (and `scripts/drain-lib.ps1`) as the ground truth if
this doc and their behavior ever disagree — the scripts win.

## How knowledge actually reaches a user (the step this loop does NOT do)

**Nothing in the drain loop ships.** Both automated curators terminate in machine-local state:

| path | writes | ships? |
|---|---|---|
| `agy-curate` (the skill) | `~/.clavity/golden-header.growth.md` via `curate-commit` | **no** — per-machine runtime |
| `just drain-knowledge` -> `just accept-drain` | `docs/agy-golden-header.growth.md`, then the same runtime file | **no** — same terminal |
| `agy-curate` cheatsheet arm | `agy-autotrain/knowledge/driver-cheatsheet.core.md` | yes — pinned into both binaries |

Only three artifacts are carried to end users by the installers, and **all three are PROTECTED from
every drain** (`scripts/drain-lib.ps1:107-119`, enforced by `scripts/check-core-integrity.ps1`):

- `seed/golden-header.md` — the **injected** SEED, prepended to *every ask on every install*
- the four driver manuals `clavity-{dotnet,classic}/plugin/knowledge/agy-{assumptions,capabilities}.md`
  — not injected; reachable via the escalation index. Must stay **byte-identical across drivers**
  (`just seed-sync-check`)
- `agy-autotrain/knowledge/driver-cheatsheet.core.md` — plus its two pinned literals in
  `clavity-classic/src/driver_cheatsheet.rs` and `clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs`

They are protected *on purpose*: promoting a machine-local, self-reported capture into something every
user receives is a judgement call, so it is human-gated by construction. The consequence to internalise
is that **if no human performs the promotion, learned knowledge never leaves the machine that learned
it** — and that is a silent outcome, because every gate in the loop still reports green.

### The promotion procedure

1. **Drain first**, so the material is distilled: `just drain-knowledge` -> review -> `just accept-drain`.
2. **Read `~/.clavity/golden-header.growth.md`.** *This* is the source to promote from — not the inbox.
   After a drain the inbox is empty or holds only rubric-parked entries, and running a drain purely to
   re-fill it will promote entries `agy-curate` deliberately parked (the two curators read one inbox with
   different bars; whichever runs first wins).
3. **Split by the SEED-tier bar:** inject a rule *iff not knowing it immediately corrupts the workspace
   or loops*. Everything else goes to the manuals, reachable via the escalation index. SEED is re-paid on
   every ask of every install, so compress hard and leave headroom.
4. **Hand-edit the protected carriers** above. Selection is mandatory, not optional: the cap is
   `SEED_MAX_BYTES = 7992` (`scripts/check-seed-budget.ps1`, the single source of truth). Worked example,
   2026-08-04: a 7 984 B GROWTH could not be folded wholesale into a 2 067 B SEED — 7 promoted rules took
   it to 5 133 B and 4 were left manual-tier.
5. **Verify:** `scripts/check-seed-budget.ps1`, `just seed-sync-check`, `scripts/check-core-integrity.ps1`;
   if `core.md` moved, both pinning oracles **by name**.
6. **Commit, then RELEASE.** The release is what reaches users — the commit alone does not.

### Four traps, all hit in practice

- **`check-core-integrity` FAILS on an uncommitted protected file, by design.** It diffs worktree against
  HEAD to prove a drain never touched them. A legitimate hand-edit trips it until you commit. Commit —
  never bypass the gate.
- **Your editor may write CRLF into these LF files, and git normalises it silently.** The installers copy
  `seed/golden-header.md` verbatim under a CI byte-check, so normalise to LF *before* staging and confirm
  the diff is additions-only (`git diff --numstat`) with no reflow of existing lines.
- **The inbox is not the source** — see step 2.
- **"Installed and registered" is a presence check, not proof of effect.** A faithful install whose
  knowledge never got promoted looks identical to one that did.

## The three recipes and their contract

| Recipe | Script | What it does |
|---|---|---|
| `just drain-knowledge [-WhatIf]` | `scripts/drain-knowledge.ps1` | Stages `## Pending` observations, runs a headless `claude -p` curator to compile them into a reviewable GROWTH proposal (`docs/agy-golden-header.growth.md`) plus docs side-artifacts, runs the protected-files integrity gate (hard) and the combined GROWTH-budget gate (warn), and appends a summary to `docs/agy-drain-log.md`. **Makes NO commit and NO runtime write.** |
| `just accept-drain` | `scripts/accept-drain.ps1` | Confirms the drain's run-ID is in the **committed** `docs/agy-drain-log.md` and the tree is clean, **publishes the committed GROWTH proposal to the runtime header (`~/.clavity/golden-header.growth.md`) via `clavity-ls curate-commit`**, then deletes the staging snapshot. This is the "I reviewed, committed, and shipped it" step. |
| `just abort-drain` | `scripts/abort-drain.ps1` | Refuses outright (nothing touched, staging retained) if the tree has an unrelated tracked change or an unrelated untracked file under the drain's output paths — see the exit-code table below. Otherwise runs `git reset --hard HEAD` — an unscoped whole-tree reset of every tracked file, not just the drain's outputs — removes the drain's untracked outputs, and re-queues the staged observations back into `## Pending` of the inbox. No runtime rollback is needed here: the drain never wrote the runtime file in the first place. This is the "reject this drain" step. |

The maintainer loop is:

1. `just drain-knowledge` (on a pristine tree — see below).
2. Run `git status` **first** — the drain's outputs are new **untracked** files, which a bare
   `git diff` does not show at all. Then review the diff (especially
   `docs/agy-golden-header.growth.md`, the compiled GROWTH proposal) and read
   `docs/agy-drain-proposal.md` (the curator's sidecar — what it promoted, dropped, or parked, and
   why).
3. Either:
   - **Accept**: `git add` the changed/new files, commit, then `just accept-drain` (publishes the
     GROWTH proposal to the runtime header via `curate-commit`, then deletes the staging snapshot —
     the drain is now permanent and live).
   - **Reject**: `just abort-drain` (no commit needed — it reverts everything and re-queues the
     observations for a future drain attempt).

`drain-knowledge` never commits and never writes the runtime file on its own — the maintainer decides
whether to land a drain's output, by committing it (or not) between steps 1 and 2/3. The runtime header
is touched at exactly one point in the whole flow: `accept-drain`'s `curate-commit` call.

## Security / trust model

`just drain-knowledge` runs the curator as a **headless Claude session with
`--dangerously-skip-permissions`**: by design (it must write the GROWTH proposal and docs
side-artifacts unattended, with no one present to click "approve"), that flag makes it auto-approve
**every** tool call, including Bash — no prompting, no confirmation.

That curator's *input* is the batch of `## Pending` observations captured by `agy-learn` — machine-local
captures that are, from the drain's point of view, **untrusted**. Three deterministic mechanisms run
after the curator and before any human sees the result: the **protected-files integrity gate**
(`check-core-integrity.ps1` — every driver-owned file must be byte-identical to `HEAD`, checked in
*both* the working tree and the index), the **HEAD-pin gate** (rejects the run outright if the curator
advanced `HEAD`, i.e. committed, which would otherwise let the protected-files gate pass vacuously
against the curator's own commit), and the **combined GROWTH-budget** warn. Together with the human
`git status`/`git diff` review in the maintainer loop above, these inspect the *resulting file
contents* (and, for the HEAD-pin, the repo's commit state) — they check what the curator wrote, not
what it *did* while writing it. None of them defend against a prompt-injected observation that gets
the curator to run an arbitrary tool (including shell) **during** the run, before any gate or commit
ever sees the output. That residual risk is bounded, not eliminated, by the gates plus human review.

**Practical consequence:** only drain observations you trust, on a machine you control. Treat
`just drain-knowledge` as running trusted-but-unverified code over your own captures, not as a sandboxed
or content-filtered pipeline. This is an accepted dev-only residual risk — the runbook is dev-facing only
and the maintainer runs the drain deliberately, on their own box, over their own captures. A future
hardening could scope the curator's allowed tools instead of granting it all of them.

## The pristine-tree precondition

`just drain-knowledge` refuses to run if the working tree is dirty (`git status --porcelain` is
non-empty at the start), or if `git status` itself fails to run: **exit 4** either way. Commit or
stash everything first. This exists so that (a) `abort-drain`'s revert-to-HEAD is safe — it can never
destroy pre-existing uncommitted work — and (b) every file the curator touches, including a
hallucinated stray path outside the known output set, is attributable to this drain and visible in
`git status`/`git diff` before you accept.

## The run-ID / staging / drain-log recovery transaction

Each drain gets a run-ID and moves the inbox's `## Pending` section into a staging snapshot file
(`agy-observations.staging.<runId>.md`, in the same app-data directory as the inbox) before invoking
the curator. That staging file is the recovery anchor: it exists only while a drain is pending a
maintainer decision, and both `accept-drain` and `abort-drain` key off it.

The curator owns exactly these tracked repo paths (`Get-DrainOutputPaths` in `scripts/drain-lib.ps1`
is the single source of truth):

- `docs/agy-golden-header.growth.md` — the compiled, reviewable GROWTH proposal (piped to
  `curate-commit` at accept)
- `docs/agy-drain-log.md` — the append-only maintainer audit log (written by the script itself, not
  the curator)
- `docs/agy-verify-needed.md` — the accumulating parked-probe backlog
- `docs/agy-drain-proposal.md` — the rationale sidecar (`Promoted` / `Proposed cheatsheet changes` /
  `Proposed demotions` / `Parked` / `Dropped`)
- `agy-autotrain/docs/fix-the-tool-backlog/` — one file per tool-fixable finding, dynamically named by the curator

It must **never** touch `seed/golden-header.md`, the four driver manuals, or
`agy-autotrain/knowledge/driver-cheatsheet.core.md` — those are protected (see below).

Beside the staging file the drain writes an **output manifest**,
`agy-observations.staging.<runId>.outputs.txt`: one repo-relative path per line, listing every
untracked file the curator created this run under the output paths above. It is derived, not
declared — the drain snapshots `git ls-files --others` over those paths before and after the curator
runs and takes the difference, so it does not depend on the curator's prompt or on the curator
reporting honestly. In practice this only ever names files under `agy-autotrain/docs/fix-the-tool-backlog/` (the
other four output paths are typically already tracked after the first drain), whose slugs the curator
picks per run.

Be precise about what that buys: the manifest records what **appeared during the curator's run**, which
is not quite the same as what the curator **wrote**. The curator call takes roughly 30-60s, and anything
else that creates a file under those paths in that window — an editor autosave, a second terminal, a
concurrent script — is indistinguishable from curator output and lands in the manifest, after which
`abort-drain` will delete it without complaint. The pristine-tree precondition only covers drain *start*.
The window is narrow and needs concurrent activity on the same paths, but it is real: while a drain is
running, do not create files under `agy-autotrain/docs/fix-the-tool-backlog/`.

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
| `3` | The **protected-files integrity gate** failed after the curator ran — it modified the SEED, a manual, or `driver-cheatsheet.core.md`. Each offending file is **targeted-reverted to `HEAD`** (`git checkout HEAD -- <path>`) before exiting. **Staging is retained** — run `just abort-drain` to reject and recover. |
| `3` | The **HEAD-pin gate** failed — the curator advanced `HEAD` (i.e. it ran `git commit`) during its run, a protocol violation that would otherwise let the protected-files gate above pass vacuously against the curator's own committed edit. Staging retained. Recover with `git reset --hard <headBefore>` (the SHA is printed in the console message) to discard the rogue commit and its edits, then `just abort-drain` to clean the curator's untracked outputs and re-queue the staged observations. |
| `4` | Working tree was dirty at the pristine-tree precondition check, **or** `git status` itself failed there. |

The **combined GROWTH-budget** check (step 7 of the script, `check-growth-budget.ps1`) is **warn-only**
inside `drain-knowledge` — it does not block the drain or change its exit code. It warns when
`seed/golden-header.md` + `docs/agy-golden-header.growth.md` (plus a 2-byte join separator when both
are present) together exceed 16 KiB, the binary's combined injection cap — past that cap the binary
silently drops GROWTH and injects SEED-only, so an over-budget proposal is written but never actually
delivered to agy. Trim `docs/agy-golden-header.growth.md` and re-drain if you see this warning. The
separate, unchanged **`check-seed-budget.ps1`** CI gate (see the budgets section below) is **not**
called by the drain at all, since the drain never edits the SEED.

**`abort-drain` exit codes:**

| Exit | Condition |
|---|---|
| `0` | No pending staging file (nothing to abort) — or a successful reject: tracked files reverted to `HEAD`, untracked drain outputs cleaned, staged observations re-queued into `## Pending`, staging file removed. |
| `1` | The run-ID is **already in the committed** `docs/agy-drain-log.md` — aborting would re-queue already-shipped observations, so it refuses; use `just accept-drain` instead. |
| `1` | **REFUSES** — a modified/staged **tracked** file is not one of the drain's own outputs, so `git reset --hard HEAD` would silently destroy it. Nothing is touched; staging retained. Move, commit, or delete the file, then re-run. |
| `1` | **REFUSES** — an **untracked** file under one of the drain's output paths (in practice, `agy-autotrain/docs/fix-the-tool-backlog/`) is neither one of the four individually-named output files nor recorded in this run's output manifest, so the scoped `git clean -fd` would delete it. Nothing is touched; staging retained. Move, commit, or delete the file, then re-run. A backlog file the curator wrote *this run* does NOT trigger this: `drain-knowledge` records it in the manifest, so it is recognised as the drain's own output and cleaned normally. |
| `1` | **REFUSES (no manifest, from EITHER route)** — with no `…outputs.txt` manifest beside the staging snapshot, the drain has no record of which backlog files its curator wrote, so *any* untracked file under `agy-autotrain/docs/fix-the-tool-backlog/` is refused. Two different runs land here and the tool cannot tell them apart: one predating manifest recording, and a MODERN run interrupted before it wrote one. The message says both since `6d02a57`; this row said "runs predating the manifest only" until 2026-08-26, which would send someone whose run died minutes ago hunting a version problem that does not exist. Delete it yourself if it is the drain's output, or move your own file aside, then re-run. |
| `1` | `git reset --hard HEAD` (the revert) failed — tree not reverted; staging retained so you can fix the repo and re-run. |
| `1` | `git clean -fd` (removing the drain's untracked outputs) failed — staging retained; fix the repo and re-run. |

(Both `git reset --hard HEAD` and `git clean` failures share exit `1`; the console message tells you which step
failed.) After a successful revert+clean, `abort-drain` also surfaces (non-fatally) any file that still
differs from `HEAD` — a possible curator stray outside the known output set — for you to review by hand.

**`accept-drain` exit codes:**

| Exit | Condition |
|---|---|
| `0` | No pending staging file (nothing to accept) — or a successful accept: GROWTH proposal published to the runtime header (or nothing to publish), staging snapshot deleted. |
| `1` | The run-ID is **not** in the committed `docs/agy-drain-log.md` — commit the drain's changes first (`git add` + commit), then re-run; or run `just abort-drain` to reject instead. |
| `1` | The working tree is dirty (uncommitted drain outputs remain) — commit them before accepting. |
| `1` | `git status` itself failed — accept cannot confirm a clean tree; staging retained; fix the repo and re-run. |
| `1` | **No `clavity` driver found on `PATH`** (`clavity-ls` or `clavity`) — the drain is committed but the runtime header was **not** updated. Staging retained. Install a clavity driver and re-run `just accept-drain` to finish publishing. Do **not** hand-pipe the growth file into `curate-commit` (`clavity-ls curate-commit < file` or `Get-Content file \| clavity-ls curate-commit`) as a workaround — PowerShell's `<` redirection isn't supported for external commands, and the pipe path re-encodes through the console code page (CP437), the exact mojibake corruption `curate-commit`'s raw-byte transport exists to avoid. |
| `1` | `curate-commit` **failed** to publish the GROWTH proposal (non-zero exit) — staging retained; fix the underlying issue and re-run `just accept-drain`. |

If `docs/agy-golden-header.growth.md` doesn't exist at all (a docs-only drain — e.g. only backlog or
verify-needed entries, nothing promoted), accept treats that as "nothing to publish": the runtime
header is left unchanged and the accept proceeds normally to delete staging with exit `0`.

In short: `accept-drain` requires the run-ID to be committed, the tree to be clean, **and** the GROWTH
proposal (if any) to publish successfully before it will delete the staging snapshot; any failure
leaves the staging file in place so the pending drain isn't silently lost.

## Budgets: the CI SEED gate and the drain-side combined GROWTH cap

Two independent byte budgets exist; only one is part of the drain flow.

**`check-seed-budget.ps1`** is a **separate CI gate**, not called by `drain-knowledge` at all (the
drain never edits the SEED, so there's nothing for it to check here). Its budget lives as the
`-MaxBytes` **default parameter value in `scripts/check-seed-budget.ps1`** (currently `7992`, chosen
as 8 KiB minus ~200 B of runtime-escalation-index headroom). It is the single source of truth — there
is no separate config file or env var. To bump it deliberately, edit that default and commit the
change; do not pass `-MaxBytes` ad hoc as a workaround, since CI and other maintainers won't see an
uncommitted override. It treats a missing SEED file as 0 bytes (never crashes on a fresh clone that
hasn't been drained yet).

**`check-growth-budget.ps1`** is the drain-side gate, run **warn-only** as step 7 of
`drain-knowledge.ps1` (see the exit-code table above). It asserts that
`seed/golden-header.md` + `docs/agy-golden-header.growth.md` (raw on-disk bytes, plus a 2-byte join
separator when both are non-empty) together stay within a hardcoded **16 KiB** default — matching
`GoldenHeader.MaxBytes` in both driver binaries, the combined size at which the binary injects
SEED+GROWTH into agy. Above that cap the binary drops GROWTH entirely and injects SEED-only, so an
over-budget proposal is written to the repo but silently never delivered. A breach here does **not**
abort or change the exit code of `drain-knowledge` — it's a signal the curator (or the maintainer,
during review) should trim `docs/agy-golden-header.growth.md`.

## The protected-files byte-identity gate

Under the EXTEND model, `check-core-integrity.ps1` asserts that every **protected, driver-owned
file** is **byte-identical to its committed `HEAD` version** after a drain. The protected set
(`Get-DrainProtectedPaths` in `scripts/drain-lib.ps1` — the single source of truth, shared with the
targeted-revert loop in `drain-knowledge.ps1`) is:

- `seed/golden-header.md`
- `clavity-dotnet/plugin/knowledge/agy-assumptions.md` and `agy-capabilities.md`
- `clavity-classic/plugin/knowledge/agy-assumptions.md` and `agy-capabilities.md`
- `agy-autotrain/knowledge/driver-cheatsheet.core.md`

For each file with a committed baseline at `HEAD`, the gate checks **both** `git diff --quiet HEAD --
<path>` (working tree vs. `HEAD`) **and** `git diff --cached --quiet HEAD -- <path>` (index vs.
`HEAD` — the "index smuggle" guard: a curator that `git add`s an edit and then restores only the
worktree would otherwise leave the malicious change staged and invisible to the worktree-only check).
A file with no committed baseline (new/uncommitted) has nothing to protect and is skipped; the gate
fails closed if `git` itself can't run or the repo isn't a work tree.

This **replaces** the older per-line `**[Core]**`/`[SEED-tier]` marker scheme entirely — those
markers no longer exist anywhere in the codebase and are not checked by any script. Since the curator
under EXTEND never touches the SEED or the manuals at all, byte-identity is both simpler and strictly
stronger than line-level survival: an unchanged file trivially preserves everything, and any other
rewrite of a protected file (not just a marker line) now fails the gate. If you need to change the
SEED or a manual, do it yourself, directly, outside the drain — the drain will never do it for you,
and will revert it if it somehow happens during a curator run (see the exit-`3` rows above).

## Review discipline

Before accepting a drain:

- Run `git status` first, then read the full `git diff` — the drain's outputs are new *untracked*
  files (`docs/agy-golden-header.growth.md` on a first drain, the docs side-artifacts, and any new
  `agy-autotrain/docs/fix-the-tool-backlog/<slug>.md`), which a bare `git diff` will not show at all.
- Read `docs/agy-golden-header.growth.md` itself — it is the compiled proposal that
  `just accept-drain` will publish verbatim to the runtime header.
- Read `docs/agy-drain-proposal.md` (the curator's sidecar for that run) under its `## Promoted`,
  `## Proposed cheatsheet changes`, `## Proposed demotions`, `## Parked (verify-needed)`, and
  `## Dropped` headings, to see what it promoted, dropped, or parked, and why. `## Proposed
  cheatsheet changes` and `## Proposed demotions` are the curator's *wishes* for the driver-owned
  cheatsheet/manuals — it cannot apply them itself; hand-apply anything you agree with, separately
  from this drain.
- Cross-check `docs/agy-drain-log.md` — `drain-knowledge` appends a summary line (compiled GROWTH
  bytes, the verify-needed count, and the sidecar's `## Dropped`/`## Parked` sections verbatim) for
  every run, giving you a running audit trail independent of the working-tree diff.
- For any item the curator left in `docs/agy-verify-needed.md` (assumptions it couldn't verify from
  the observation alone), run a **live verify-probe** against the real agy peer before re-draining or
  promoting that item — don't accept an unverified assumption into the GROWTH proposal on the curator's
  say-so alone.

If you reject the drain (`just abort-drain`), the staged observations are automatically re-queued into
`## Pending` so nothing is lost — you can re-attempt the drain later (after fixing the inbox, adjusting
the curator prompt, or waiting for more captures to accumulate).

## Dev prerequisite: Pester

The drain scripts' tests (`scripts/tests/*.Tests.ps1`) run under [Pester](https://pester.dev/), the
PowerShell testing framework. It is not bundled with PowerShell — install it once per dev box:

```powershell
Install-Module Pester -MinimumVersion 6.0.0 -MaximumVersion 6.99.99 -Scope CurrentUser -Force -SkipPublisherCheck
```

**Pin the major line.** These suites are validated on **Pester 6**, and CI pins `6.x` to match. An
unpinned `Install-Module` resolves to the newest version at or above the floor, so it silently follows
the next major - which is exactly how the pin came to exist. Pester 6 needs Windows PowerShell 5.1 or
PowerShell 7.4+; note that the Pester **3.4.0** shipped inside Windows PowerShell 5.1 will shadow it
unless you `Import-Module Pester -MinimumVersion 6.0.0` explicitly, as CI does.

Then run the suite with:

```powershell
Invoke-Pester scripts/tests/
```

Pester is a **manual dev prerequisite** — install it yourself. The `.claude/recommended-tools.json`
entry documents Pester and its install command, but the `SessionStart` tooling check only presence-checks
PATH executables and exact file paths; it cannot check for an installed PowerShell *module*, so it will
NOT auto-remind you when Pester is missing.

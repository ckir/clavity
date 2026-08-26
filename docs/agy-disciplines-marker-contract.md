# agy-disciplines marker contract (skill writes, auto-fire hook reads)

Single source of truth for the debounce marker shared between the discipline **skills** (which WRITE it,
in-flow, only after a consult completes) and the SP-C **auto-fire hook** (which READS it to decide whether
to inject a discipline's directive). Spec: `docs/superpowers/specs/2026-07-24-ship-agy-workflow-design.md`
Decision 1 (debounce) + Decision 4 (per-plugin state).

## Constant

- **Directory:** `.clavity/agy-marks/` (repo-cwd-relative; runtime state; gitignored).
- **Marker file:** `<discipline>.head`
  - `<discipline>` ∈ { `agy-first` (SP-A), `agy-capstone` (SP-B), `agy-test-audit` (AGY-TEST-AUDIT) }.
  - **No `<plugin-id>` prefix** (DECIDED: Option S). A byte-identical skill body cannot carry a per-plugin
    literal and has no runtime mechanism to resolve which plugin it is; and the two drivers are mutually
    exclusive (both-installed is a transient migration state), so a single discipline-keyed marker is
    safe — at worst one duplicate consult during migration. See "Resolved: marker namespacing" below: this
    drops Decision 4's per-plugin-state clause *for the marker specifically*.
- **Content:** the commit sha from `git rev-parse HEAD` at consult time, and nothing else. If HEAD cannot
  resolve (no repo / no commits), no marker is written (the discipline re-fires — safe).
- **Skip / audit log:** `.clavity/agy-marks/skipped.log`, append-only, one line per event:
  - `<iso-8601>  <discipline>  SKIPPED-UNREACHABLE  HEAD=<sha>` - peer unreachable (any discipline).
  - `<iso-8601>  agy-capstone  WAIVED  HEAD=<sha>  <reason>` - human waived (SP-B; `<reason>` is `breach`
    for a review-only-breach waiver or `round-cap` for a completion-gate waiver; also writes the marker,
    so this line distinguishes a waiver from a mechanically-verified GREEN, AND a breach-waiver from a
    gate-waiver, in the durable record).
  - `<iso-8601>  agy-capstone  UNVERIFIED-ACCEPTED  HEAD=<sha>  <finding>` - human accepted the risk of a
    single unmeasurable finding (SP-B; per-finding, non-terminal - writes NO marker, does NOT abort the
    capstone).

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

- The **skill** writes `<discipline>.head` **only** at that discipline's terminal state:
  - `agy-first` writes after a consult completes (ALIGNED / REJECTED / resolved NEGOTIATE).
  - `agy-capstone` writes only on **human-confirmed GREEN or an explicit human completion-gate waiver
    (`round-cap`)** - NOT on a raw self-reported clean round, an override re-entry still in progress, or a
    `SKIPPED-UNREACHABLE`. A review-only breach does NOT write the marker whether or not the human waives
    it: a `breach` waiver is a skip-equivalent (proceed without a clean review; gate not satisfied), so it
    writes ONLY the `WAIVED ... breach` audit line and re-arms next trigger. This prevents a peer from
    smuggling unreviewed code past the gate by forcing a trivial breach and getting it waived.
  In every case the content stays the bare `git rev-parse HEAD` sha, so the SP-C hook's
  `content == HEAD` read is uniform across disciplines; capstone's WAIVED / UNVERIFIED-ACCEPTED
  distinctions live in the log above, never in the marker.
- `agy-test-audit` writes `agy-test-audit.head` only on a **completed audit**: an `[VERDICT: EXHAUSTIVE]`,
  or a `[VERDICT: GAPS FOUND]` whose every gap carries one of the five AGY-SCOPE disposition tokens
  (`FOLDED`, `REJECTED`, `DISCARDED-BELOW-FLOOR`, `DEFERRED-TO-ANOMALIES`, `UNVERIFIED-ACCEPTED`); a
  material `DEFERRED-TO-ANOMALIES` needs the owner's ruling first. An
  `[VERDICT: agy-required-but-unreachable]` abort writes NO marker (re-fires
  next trigger). Content is the audited `git rev-parse HEAD`.
- A `SKIPPED-UNREACHABLE` or a review-only breach writes NO `.head` marker (the discipline re-fires next
  trigger); the skip appends to `skipped.log` as above.
- **Cross-marker sequencing (AGY-TEST-AUDIT).** Unlike the SP-C `agy-seam-inject.sh` reader (which reads
  only its own discipline's marker), the `agy-test-audit-reminder.sh` hook READS `agy-capstone.head` to
  enforce ordering: it nudges the audit only when `agy-capstone.head` STILL DESCRIBES HEAD - it either
  EQUALS HEAD, or is an ANCESTOR of HEAD with nothing executable landed since - AND `agy-test-audit.head`
  does NOT still describe HEAD by that same rule, AND the reviewed range touched executable code/tests.

  > Both markers were `== HEAD` until 2026-08-26. Strict equality was silenced by AGY-CAPSTONE's own
  > mandatory final step: the skill writes the reviewed tip to its marker and then REQUIRES a ledger row,
  > and committing that row advances HEAD. MEASURED in this repository - marker `f29cd42`, next commit the
  > ledger row, silent for the 34 commits that followed. The relaxation is applied to BOTH markers by one
  > shared helper, because they age for the same reason: relaxing only the capstone one nudged the driver
  > who ran the audit at the reviewed tip and then filed the paperwork.

  The cross-marker read is sound precisely because `agy-capstone.head` is written ONLY at a
  gate-satisfied terminal state (GREEN or a `round-cap` waiver) - so its presence at HEAD is a reliable
  "capstone is satisfied here" signal for a *different* hook to read. The audit hook, like every reader,
  never writes a `.head` marker.
- The **hook** (SP-C) READS the marker: if it exists AND its content == current `git rev-parse HEAD`,
  the discipline was already consulted this cycle → do not inject. Otherwise → inject the directive.
  The hook never writes the `.head` marker (a PreToolUse hook fires before the consult and cannot know
  its outcome).
- A new commit changes HEAD → content mismatch → re-arms the discipline. There is no branch-keyed
  marker with no expiry (that would permanently silence the discipline).

## Hook ownership (D1)

Shipped plugin hooks are sole-owned by the plugin. A personal registration of a same-named hook in any
`settings.json` is retired at release-install time by the operator, prompted by the ownership notice in
`agy-liveness-check.sh`. Installers MUST NOT edit an operator's settings files.

The ownership notice is the ONE agy hook exempt from `.no-agy` — a gate the policed party can switch off
is not a gate. Guarded by `scripts/tests/agy-liveness-check.Tests.ps1`.

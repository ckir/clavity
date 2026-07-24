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

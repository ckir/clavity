---
slug: guard-ignored-axis-blind-to-dependency-tree-writes
variant: both
observed: 2026-11-12
source-inbox-entry: "- [anti-pattern] (driver/deterministic) A review-only peer given an out-of-repository scratch directory may symlink"
status: OPEN
---

# The consult guard's ignored-path axis cannot see a peer write into the repository's dependency tree

## Steps to Reproduce

Observed live 2026-11-12 on a review-only consult that was given an out-of-repository scratch
directory; re-measured at the guard level in this drain (2026-11-13), not re-driven through a peer.

1. Run a review-only consult under `agy-consult-guard-pre.sh` / `agy-consult-guard-post.sh`
   (`clavity-dotnet/plugin/hooks/`) in a repository whose dependency folder (e.g. `node_modules/`) is
   git-ignored and holds a workspace link (`node_modules/@s/pkg -> ../../packages/pkg`).
2. The peer, wanting its throwaway builds to resolve, symlinks ITS scratch directory's dependency folder to
   the repository's. Its writes then land inside the repository's ignored dependency tree; here, the
   workspace link was replaced by a stub directory.
3. The post-consult guard reports a clean consult. `git status --porcelain` omits ignored files by design
   (`agy-consult-guard-lib.sh:53-55`), and `agy_guard_ignored` (`agy-consult-guard-lib.sh:369-375`) fingerprints
   only `.clavity/.gitignore`, `.env`, `.claude/settings.local.json` and a census of `.clavity/`.

Measurement of the blindness (scratch repo, `source agy-consult-guard-lib.sh`): build a git repo with
`node_modules` ignored and a symlink `node_modules/@s/pkg`; compute `agy_guard_quad`; replace the symlink with a
real directory holding a stub file; compute `agy_guard_quad` again. Result: the two fingerprints are
byte-identical (`GUARD BLIND`). The write is invisible to all eight axes.

## Code-level Mitigation

Add one component to the ignored axis, `agy_guard_depcensus`, and join it in `agy_guard_ignored` with the
existing `:` delimiter (the value is a digest, so it contains neither `:` nor `|`):

- For each of a short fixed list of dependency/cache directory names that exist at the repository root
  (`node_modules`, `vendor`, `.venv`, `target`), run a bounded
  `find "$c/<dir>" -maxdepth 2 -type l -printf '%p -> %l\0' | LC_ALL=C sort -z`, and hash the result with
  `agy_guard_hash`. `-maxdepth 2` reaches scoped workspace links (`node_modules/@scope/pkg`) without walking
  the tree. Do NOT use `-type f`: it would walk the whole dependency tree on every consult.
- Distinguish ABSENT (directory missing) from an empty census, as `agy_guard_file_state` does for files, so
  "no dependency dir" and "dependency dir with no links" cannot compare equal to an unreadable one.
- Pinning test: the scratch-repo measurement above as a fixture. Before the change the two fingerprints
  are equal; after it they differ. Control: an untouched repo yields identical fingerprints across two
  consecutive calls.

Limit, stated rather than hidden: this sees a replaced or added LINK, not an edit to a regular file inside a
real dependency directory. That wider case needs a mtime-newer-than-snapshot sweep, which is unbounded on a
large tree; decide separately whether it is worth the cost.

## Notes

Both variants: `clavity-dotnet/plugin/hooks/` and `clavity-classic/plugin/hooks/` ship byte-identical copies of
`agy-consult-guard-lib.sh`, `-pre.sh` and `-post.sh` (`cmp` clean on 2026-11-13), so the fix lands in both copies
together. Determinism is therefore the same on both variants. The driving-side workaround (forbid symlinks into the
repository and writes under any dependency or cache directory in the review-only banner, then compare ignored
paths by hand after the consult) is carried in the cheatsheet GROWTH from 2026-11-13 and must not be retired when
this ships: an end user on an older build still has a blind guard.

Adjacent: `agyview-diagnostics-writes-are-unguarded` and `peer-scratch-dir-contains-executable-session-hooks`
(other writes the guard's axes do not cover).

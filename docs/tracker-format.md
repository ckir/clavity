# Tracker entry format

Every tracked work item - a `clavity-dotnet/ROADMAP.md` section, a `docs/backlog/*.md` stub, an
`agy-autotrain/docs/fix-the-tool-backlog/*.md` entry, a `review-relay/ROADMAP.md` item, an
`agy-autotrain/ROADMAP.md` item - has ONE current status in ONE fixed place, enforced by
`scripts/check-tracker-status.ps1` (`just check-tracker-status`).

<!-- tracker-format:begin -->
**Writing a tracker entry** (full rules: `docs/tracker-format.md`): the heading is the TITLE ONLY; the next non-blank line is `**Status:** <TOKEN> <YYYY-MM-DD> - <one line>`. TOKEN is one of OPEN, SCHEDULED, IMPLEMENTED (open) or SHIPPED (cite a commit sha), CLOSED-BY-RULING (a ROADMAP entry needs a Non-goals bullet; a stub needs a `**Reopen if:**` line), KILLED (state why). Never put a status in the heading; an open sub-item gets its own entry. `just check-tracker-status` enforces this.
<!-- tracker-format:end -->

## The status line
`**Status:** <TOKEN> <YYYY-MM-DD> - <one line>` - the date is the date of that status; the one line is a
sentence, not history. History goes in the body; when a status changes, the line is REPLACED and the old
line is kept in the body (`> **Previous status:** ...`).

## Tokens (one closed set for every tracker)
| Partition | Token | Meaning | Evidence the gate requires |
|---|---|---|---|
| open | `OPEN` | real, not yet scheduled | none |
| open | `SCHEDULED` | has an owner branch or slot | none |
| open | `IMPLEMENTED` | built on an UNMERGED branch | none |
| closed | `SHIPPED` | merged to `main` | a backticked 7-40 hex commit sha on the status line that exists in the repository |
| closed | `CLOSED-BY-RULING` | an accepted limitation, with a reopen condition | ROADMAP file: a `- **<id> ...` bullet under "Non-goals / accepted limitations"; standalone file: a `**Reopen if:**` line in the entry |
| closed | `KILLED` | will not be done | a reason of at least 12 characters after the dash |

Release is NOT a status. When a release ships an item, add ONE line directly under the status line:
`**Released:** clavity-v<N>`. Only `SHIPPED` may carry it.
A docs-only closure cites the sha of the commit that made it true (the code commit, or for a ruling use
`CLOSED-BY-RULING`, which needs no sha).

## Per-tracker shapes
- `clavity-dotnet/ROADMAP.md`: `### §N - Title` or `### N. Title` (legacy numbered items 0-13); ids are `§N` / `item N`.
- `review-relay/ROADMAP.md`: `### D1 - Title`, `### R1 - Title`; `agy-autotrain/ROADMAP.md`: `## AT-1 - Title`.
- `docs/backlog/*.md`: line 1 `# Title`; the status line is the next non-blank line. Id = file name.
- fix-the-tool entries: frontmatter keys instead of a line - `status: <TOKEN>`; `SHIPPED` needs `fixed-by: <sha, ...>` and
  `fixed-on: <date>` (and `released-in: clavity-vN` once released); `KILLED` needs `reason: <text>`; `CLOSED-BY-RULING` needs
  a `**Reopen if:**` line in the body.
- The heading never carries a status marker (no check mark, arrow, `~~` strike-through, red circle, or status word after the title).

## What the gate can and cannot see
It checks that a cited sha EXISTS in the repository, not that it is the commit that did the work (a real but unrelated sha passes);
that a Non-goals bullet or `**Reopen if:**` line EXISTS, not that its reasoning is sound; and that a pointer is in range (and, if
anchored, that its quoted text is on the line), not that an un-anchored pointer still means what it did. Review and the capstone
carry those; the gate removes the failure where nothing was recorded at all. It also cannot read prose: an open sub-item buried in the BODY of a SHIPPED entry ("Fork 2: OPEN") is invisible to it - the format forbids that (split it into its own entry) and the Done-check's body marker scan (Task 4 Step 8, read line by line and shown to the owner) is what catches a violation.
- An open sub-item (a lettered paragraph, a "Fork 2") is NOT allowed inside a closed entry: it becomes its own entry titled
  "... (formerly <old id>)".

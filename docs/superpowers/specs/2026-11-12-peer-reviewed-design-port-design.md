# Ship the peer-reviewed-design skill in both clavity plugins - short design

Status: DRAFT for owner approval, 2026-11-12. Size: a small change (a port plus text edits; no new code).

## Intent and why

The owner's personal skill `~/.claude/skills/peer-reviewed-design` drives a design phase through
decision forks, an independent adversarial peer (agy), measurement of every claim, and an owner ruling.
It should ship inside the clavity plugins like the other disciplines, so it installs, updates and
uninstalls with the plugin and leaves no residue in personal config, and so clavity-classic users get it
too. It appears as `clavity:peer-reviewed-design`.

## Goals

1. The skill ships in `clavity-dotnet/plugin/skills/peer-reviewed-design/` and
   `clavity-classic/plugin/skills/peer-reviewed-design/`, byte-identical, as `SKILL.md` plus
   `references/*.md`.
2. Every command the skill tells the driver to run resolves in a fresh install on a machine with none of
   the owner's personal config.
3. Every repo gate that scans skills stays green.
4. The skill's behaviour is unchanged for the owner.

## Non-goals

- No new code, no `DisciplineContract.cs` entry (the skill reuses the `agy-first` and panel tokens).
- No new release machinery. The driver does not cut releases.
- The two eval cases stay out of the plugin (development files; driver's call, see "Calls made").

## Anti-goals (a failure even if it technically works)

- A skill that works only because `~/.claude/...` happens to exist on the owner's machine.
- Two copies that drift, or a transport paragraph that is true for one variant and wrong for the other.
- Deleting the personal copy before the plugin copy is installable.

## Constraints (measured 2026-11-12)

- The marketplace serves the dotnet plugin as git-subdir `clavity-dotnet/plugin`, so a `references/` folder
  travels with it. Precedent: the installed superpowers `brainstorming` skill ships sibling `.md` files and
  tells the reader to read them "in this directory".
- No clavity skill has a `references/` folder today; all eight are a single `SKILL.md`.
- `scripts/check-seed-artifacts-synced.sh` already requires every file under `skills/` to exist in both
  plugins and be byte-identical, apart from its explicit variant list. It is the drift guard; nothing new is needed.
- Trial on a scratch `git archive` copy with the skill dropped in unchanged: `check-skill-frontmatter` OK,
  `check-seed-artifacts-synced` OK, `check-injected-context` 8 violations, all in `SKILL.md` and
  `references/execution-index.md` (times two plugins): `encoding` (3 non-ASCII lines: a box-drawing diagram and
  arrows) and `reference` (the backticked name `MEMORY.md` does not resolve). The other five reference files pass.
- `check-agy-discipline-skills.ps1` iterates a hardcoded discipline list, so it neither checks nor breaks on this skill.
- Shipped skills find the marker writer as `bash "<BASE>/../../hooks/agy-mark.sh"`; `agy-mark.sh` is
  byte-identical in both plugins.

## Approaches

- **A. Faithful multi-file port (CHOSEN by the owner, 2026-11-12).** `SKILL.md` about 190 lines plus six
  references loaded on demand, identical in both plugins. Trades: first multi-file skill in the repo.
- **B. Single-file port (about 520 lines).** Matches the shipped convention; loads everything on every
  trigger. The peer recommended B (`REJECTED` on A). Driver measured its grounds: the gate failures are real but
  fixable text edits that B needs equally; the claimed runtime failure is unsupported (the peer called it
  unmeasured; the superpowers precedent contradicts it); the "no drift check" belief was the driver's error and
  is corrected above. The residual was convention versus progressive disclosure, which the owner ruled.
- **C. `SKILL.md` only.** Rejected: references would stay personal, so the skill breaks for other users.

## The design

Copy `SKILL.md` and `references/` into both plugin skill folders, then apply exactly these edits (the same
edits in both copies, so they stay byte-identical):

1. **ASCII.** Replace the box-drawing diagram in `SKILL.md` and the arrows in `references/execution-index.md`
   with plain ASCII. Meaning unchanged.
2. **No unresolvable names.** Reword the backticked `MEMORY.md` mentions so the reference gate does not read
   them as file paths (describe it as "the memory index file" or similar).
3. **Marker writer, every mention.** There are exactly two `agy-mark` mentions in the personal skill:
   `references/fork-brief.md` line 10 (the `~/.claude/plugins/cache/...` glob) and `references/panel-brief.md`
   line 80 (a bare `agy-mark.sh head "agy-panel" ...` that would exit 127 if run as written). Make both read
   `bash "<BASE>/../../hooks/agy-mark.sh"`. Define `<BASE>` once in `SKILL.md`, in the shipped skills' words: this
   skill's own base directory as the harness supplies it at invocation time, not `${BASH_SOURCE[0]}`. The failure
   path (no writer found: halt and ask the owner) keeps its meaning.
4. **Transport, one text for both variants** (as `agy-first` does): dotnet = `agy_status` idle check then
   `agy_ask` with `discipline` and `artifactPath`; classic = `clavity ask --review-only`, where no such
   parameters exist, so the driver demands the echo and checks it by eye. Give every place that mentions
   driver-side checks both clauses: `SKILL.md` section 3, `references/fork-brief.md` "Transport", and
   `references/panel-brief.md` lines 46-48 (which says the driver flags a reply not ending in `PANEL VERDICT`; that
   is dotnet-only). The builder finds all such places by grepping `references/` for `driver`, `discipline`,
   `artifactPath` and `agy_ask`.
5. **Reference paths.** Say that `references/` files live in this skill's own directory (`<BASE>`), so a reader
   resolves them from the skill's base directory and never from the working directory. Every citation of one
   reference file from another (for example `agreement-round.md` citing `fork-brief.md`) reads
   `<BASE>/references/<file>`.
6. **Cross-references.** In prose, name sibling disciplines by their plugin names (`clavity:agy-first`,
   `clavity:adversarial-panel-review`); name superpowers skills as optional ("when available"). The `discipline:`
   argument values passed to `agy_ask` stay bare (`agy-first`, `adversarial-panel-review`): the driver looks them
   up by exact key, so a `clavity:`-prefixed value would silently turn its completeness checks off.
7. **Execution-index location.** Use the harness's persistent memory directory when it has one (the owner's
   setup); otherwise write ONE file per project, `.clavity/execution/<project>.md` (the skill's rule is one index
   per project, not per topic), creating and shielding the directory first with
   `bash "<BASE>/../../hooks/agy-mark.sh" prepare "execution/<project>.md"` (the writer is generic over the
   relative path and asserts the `.clavity/` shield; abort the step if it exits non-zero, as the shipped skills
   do). The index content template is unchanged. `<project>` is the repository directory's basename with every
   character outside `[A-Za-z0-9_-]` replaced by `-` (measured: `agy-mark.sh prepare` refuses any relpath containing
   `..`, so `.` or `a..b` would abort the run; spaces and `/` pass). Only one location is ever written: the memory
   directory when the harness has one, otherwise the fallback file. Without a memory pointer nothing loads the file
   for a successor, so the skill's opening step lists `.clavity/execution/` and the memory index; when it finds
   more than one candidate it asks the owner which project is meant (it never guesses), and a finished project's
   index is closed by writing `DONE` as its resume point so a later session does not resume it. The skill states that `.clavity/` is gitignored, so a `git clean -fdx` erases it: commit shas
   are re-derivable from git, but the owner's verbatim rulings are not, so each ruling is also written into the
   committed artifact's review ledger as it lands.
8. Add one line for the skill to `clavity-dotnet/plugin/README.md`'s skill list. Classic's `plugin/README.md`
   lists only its two variant skills (`responder`, `driving`) and does not enumerate the shared disciplines, so
   it gets no line (precedent: the `platform-handoff` commit 80d0a442 touched only the dotnet README).
9. **Path defaults.** The skill's artifact locations (`docs/superpowers/specs/...`, `docs/superpowers/plans/`)
   are stated as defaults that a project's own convention overrides.

## Verification the builder runs (all must pass before the change is called done)

- `check-skill-frontmatter`, `check-injected-context`, `check-seed-artifacts-synced` and `check-plugin-namespace`
  from `scripts/`, plus the repo's own test gate (`cd clavity-dotnet && just test`, and the classic equivalent).
  `check-agy-discipline-skills` is run only as a no-regression check on the other skills: it iterates a hardcoded
  discipline list and never reads this skill, so a pass says nothing about it.
- Every `agy-mark` command in the shipped skill folders carries `<BASE>/../../hooks/`: run
  `grep -rn 'agy-mark' <skill folder> | grep -v '<BASE>/../../hooks/'`; the output must be empty, or every
  remaining line must be prose that names the script without running it (the builder reads each one). Control,
  measured 2026-11-12: on the unedited personal skill this command returns exactly two lines
  (`references/fork-brief.md:10` and `references/panel-brief.md:80`), so it can see the defect it targets.
- Every `discipline` argument value is bare and spelled exactly. Mechanical negative:
  `grep -rnE 'discipline.*clavity:' <skill folder>` returns nothing. Then enumerate with
  `grep -rn 'discipline' <skill folder>`, which is a few lines (the personal skill has seven), and the builder reads
  each and confirms every value passed to `agy_ask` is `agy-first` or `adversarial-panel-review`. (A `grep -o`
  pattern for the values was tried and rejected: it also matches prose such as "discipline is", so it would fail
  on correct text.)
- `claude plugin validate` on both plugin directories.
- A diff of the two skill folders: zero differences.
- A grep of the shipped skill folders for these patterns: `~/.claude`, `/home/`, `C:\\Users`, `<owner-given-name>`,
  `<owner-handle>`, `<owner-surname>`, `<owner-mail-provider>`: zero hits. (Each pattern is a literal the builder
  can run; a clean result with no pattern list does not count. The four `<owner-...>` placeholders stand for the
  owner's real given name, handle, surname and mail-provider word, which were run as literals when this was built
  and replaced here when the document was committed.)
- The marker writer resolves from the new folder in both plugins: `test -f` on
  `clavity-dotnet/plugin/skills/peer-reviewed-design/../../hooks/agy-mark.sh` and the classic equivalent.
- Run `claude --plugin-dir clavity-dotnet/plugin` (and classic) in a fresh session, which works before any
  release because the marketplace's `release` branch advances only at release time. Confirm the advertised name
  is `clavity:peer-reviewed-design`, that it appears once (the personal copy is a different name), and that a
  reference file reads from `<BASE>/references/`. While the personal copy still exists, invoke the skill by its
  qualified name and confirm the "Base directory for this skill:" line that heads the loaded skill text is under
  the plugin path, not under
  `~/.claude/skills`; otherwise the personal copy could answer and the check would pass falsely.

## Release and retirement

Both plugins gain the skill in one change on `main`. Releases are the owner's call: dotnet's next is 0.19.0 (a
`feat`), classic ships on its own release. The driver cuts neither. The personal copy
`~/.claude/skills/peer-reviewed-design` is retired by the owner only after a released plugin install shows
`clavity:peer-reviewed-design`; until then both exist and the plugin name is namespaced, so they do not collide.

## Calls made by the driver (check these)

- Evals excluded from the plugin.
- Execution-index fallback is `.clavity/execution/<project>.md`, with the harness memory directory preferred.
  The peer suggested a deterministic repo-local index; I kept the harness memory first because the owner's
  standing power-failure rule uses it.
- No new parity test: `check-seed-artifacts-synced.sh` already covers it.
- Skill name stays `peer-reviewed-design` (the plugin namespace makes it `clavity:peer-reviewed-design`).
- The frontmatter `description` ships verbatim (goal 4: the owner's behaviour is unchanged). It overlaps
  `clavity:agy-first` (which handles one fork) by design: this skill is the phase driver that runs that
  consult per fork. The description is also broad ("even if the user does not say design"), which may fire more
  often for other users than for the owner. If that proves too eager, narrowing it is a follow-up the owner
  rules on; it is not done speculatively here.

## Left to the builder

Exact wording of the replacements in edits 1, 2, 5 and 6; the README line text; whether the builder's trial run
needs a `just` target or just the scripts above.

## Left to the owner

Release timing for both plugins; retiring the personal copy; whether to commit this document and the port on a
branch now. Note for that commit: `.gitignore:33` ignores `docs/superpowers/specs/*`, and the earlier specs
(`2026-11-10-agent-install-design.md` and others) are tracked because they were force-added, so committing this
document needs `git add -f`.

## Review ledger

- agy-first consult, 2026-11-12: seam `.clavity/seams/pr-design-port-first.md`, reply
  `.clavity/scratch/pr-design-port/reply.md`. Verdict by the peer `REJECTED` on A; driver token `NEGOTIATE`;
  owner ruled A. Tree unchanged before and after (no review-only breach).
- Builder check: not run (small change; short design goes straight to the owner).
- Panel round 1, solo floor (driver, seats Axiom Breaker, Cascade Analyst, Literal Implementer, Activation
  Auditor, Mechanism Gamer, Dependency Cynic): five findings, all measured and FOLDED: edit 8 wrong for classic
  (classic README does not enumerate shared disciplines); the installed-skill verification step cannot run before
  a release (replaced with `claude --plugin-dir`); the personal-names grep had no patterns and the marker path was
  never executed (patterns and a `test -f` added); the execution-index fallback must go through
  `agy-mark.sh prepare` (edit 7); the description overlaps `clavity:agy-first` (recorded as a call). Edit 9
  (path defaults) added. Seats dropped: State Corruptor (no runtime state changes), Boundary Smuggler (no trust
  boundary crossed), Resource Vampire (no loops or quotas).
- Panel round 1, peer escalation (seam `.clavity/seams/pr-design-port-doc-panel-r1.md`, reply
  `.clavity/scratch/pr-design-port-doc/reply.md`, `PANEL VERDICT: FINDINGS-6`; tree, doc checksum and home-directory
  mtimes unchanged, no breach). Each finding measured by the driver:
  - FOLDED: execution index is per project, not per topic, and needs a discovery step (execution-index.md line 3).
  - FOLDED: edit 3 covered one of two `agy-mark` mentions; `panel-brief.md:80` is bare (grep: two mentions total).
  - FOLDED: edit 6 ambiguity about `discipline:` argument values (the driver's lookup is an exact key match).
  - FOLDED: edit 4 missed `panel-brief.md:46-48`, a dotnet-only driver-check claim.
  - FOLDED: `<BASE>` definition and unqualified inter-reference citations (`agreement-round.md:14`).
  - FOLDED: both skill copies present during `--plugin-dir` verification could give a false pass.
  - FOLDED: `check-agy-discipline-skills` relabelled as a no-regression run (it never reads this skill).
  - FOLDED: verbatim rulings are lost by `git clean -fdx` (edit 7 now copies them into the committed ledger).
  - DISCARDED-BELOW-FLOOR: Windows drive-boundary resolution of `<BASE>` is unreachable as a new risk because
    shipped skills already use the identical `<BASE>/../../hooks/` form (`adversarial-panel-review/SKILL.md:71`).
- Panel round 2 (fold audit, seats Fold Auditor, State Corruptor, Boundary Smuggler, Literal Implementer,
  Mechanism Gamer; seam `.clavity/seams/pr-design-port-doc-panel-r2.md`, reply
  `.clavity/scratch/pr-design-port-doc-r2/reply.md`, `PANEL VERDICT: FINDINGS-5`; no breach: tree, checksum and
  home mtimes unchanged):
  - FOLDED: the "Calls made" section still said `<topic>` (grep: line 140), contradicting edit 7.
  - FOLDED: `<project>` had no derivation rule; measured with the real script that `.` and `a..b` are refused.
  - FOLDED: the discovery step had no precedence or closure rule (edit 7 now: one written location, ask on more
    than one candidate, `DONE` closes an index).
  - FOLDED: the bare-`agy-mark` check had no command; the `discipline` check caught only the `clavity:` prefix
    (both now explicit commands with an allowed-value list).
  - REJECTED: "Claude Code prints no base directory at invocation". Measured in this session: every loaded skill's
    text opens with "Base directory for this skill: <path>". The step now quotes that line.
- Panel round 3 (fold audit of the round 2 edits; seats Fold Auditor, Literal Implementer, Dependency Cynic,
  State Corruptor; seam `.clavity/seams/pr-design-port-doc-panel-r3.md`, reply
  `.clavity/scratch/pr-design-port-doc-r3/reply.md`, `PANEL VERDICT: CLEAN`; no breach). The clean round was
  checked, not assumed: the peer's unprompted line citations (93 and 154) matched the file. Its coverage is the
  five edits it was scoped to, not a fresh read of the whole document. Panel concluded: no live challenge.
- Execution (native, branch `feat/peer-reviewed-design-port`, nothing committed): all six plan tasks complete with
  evidence in the executor's ledger. Gates after the port: seed-sync in sync; frontmatter `OK - 23 SKILL.md checked`;
  `check-injected-context: OK` (was 4 violations before the text edits); control-bytes, user-facing-docs, doc-stubs,
  agy-skills and plugin-namespace all pass; `just test` passes; `claude plugin validate` passes with the same
  pre-existing warnings on both plugins; `diff -r` of the two skill folders is empty; personal-name and bare-marker
  greps return nothing. Load check with the personal copy present, in a hook-less scratch copy of each plugin: the
  skill is advertised as `clavity:peer-reviewed-design` and the base directory is under the plugin path, and
  `references/execution-index.md` reads from it, for both dotnet and classic. Whole-branch review (Sonnet, read-only,
  tree unchanged after): no Critical or Important findings, six Minors deferred to the owner.

## Stand-downs

DISCARDED-BELOW-FLOOR: Windows drive-boundary resolution of the base directory, guard: identical pattern already ships at adversarial-panel-review/SKILL.md:71. UNVERIFIED-ACCEPTED: none.

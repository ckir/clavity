# Ship peer-reviewed-design in both clavity plugins - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the personal skill `~/.claude/skills/peer-reviewed-design` (SKILL.md + 6 references, no evals) into `clavity-dotnet/plugin/skills/` and `clavity-classic/plugin/skills/` as byte-identical folders, with the nine text edits the design lists.

**Architecture:** Pure text port, no code. "Tests" are the repo's own gates plus the greps the design lists, each run red before the edit and green after. Work happens in `clavity-dotnet` first, then the folder is copied to classic so the two cannot differ.

**Tech Stack:** Markdown skill files; `just` recipes from the repo root; `pwsh`, `yq`, `rg`, `git`, `claude` CLI.

**Spec:** `docs/superpowers/specs/2026-11-12-peer-reviewed-design-port-design.md` (approved 2026-11-12; read it with this plan). Both docs are gitignored: committing either needs `git add -f`.

## Global Constraints

- Source of truth for the text: `~/.claude/skills/peer-reviewed-design/` (SKILL.md 192 lines, `references/` six files). Copy `SKILL.md` and `references/` only; never `evals/`.
- The two plugin folders must be byte-identical (`just seed-sync-check` enforces it).
- Every shipped file is pure ASCII (gate: `check-injected-context`, invariant `encoding`).
- No backticked name in shipped text may be an unresolvable file name (gate invariant `reference`; `MEMORY.md` was the offender).
- `discipline:` values passed to `agy_ask` stay bare: `agy-first`, `adversarial-panel-review`.
- The frontmatter `name` equals the folder name `peer-reviewed-design`; the `description` ships verbatim.
- No commit, no push, no release unless the owner says so. Commit steps below are marked HOLD; run them only on the owner's word, on branch `feat/peer-reviewed-design-port`.

## Review Focus

Failure modes the design implies that no gate exercises (each is pinned by a step marked `[RF n]`):

1. A project directory whose name has dots or spaces: `prepare` refuses `..` (measured), so the `<project>` rule must sanitize. Pinned in Task 4.
2. A classic user, who has no `agy_ask` tool: every driver-check mention must carry the by-eye clause. Pinned in Task 4.
3. The personal copy still installed: the load check must prove which copy answered. Pinned in Task 6.
4. A Windows CRLF checkout: the frontmatter must stay valid YAML under both line endings. Pinned in Task 1 (the repo's yq-based gate is stricter than Claude Code).
5. A repository with no commits, where `git rev-parse HEAD` fails and the panel marker call would be refused: NOT in the approved design. Flagged to the owner at handoff; no step changes the skill for it.

## File Structure

- Create: `clavity-dotnet/plugin/skills/peer-reviewed-design/SKILL.md`
- Create: `clavity-dotnet/plugin/skills/peer-reviewed-design/references/{fork-brief,panel-brief,agreement-round,verification-playbook,design-doc-outline,execution-index}.md`
- Create: the same seven files under `clavity-classic/plugin/skills/peer-reviewed-design/` (Task 5, by copy)
- Modify: `clavity-dotnet/plugin/README.md` (one line after line 23)

Baseline, measured 2026-11-12 on clean `main` f9b879ec: `just seed-sync-check`, `check-skill-frontmatter` ("OK - 21 SKILL.md checked (1 excluded)"), `check-injected-context` ("OK"), `check-control-bytes`, `check-user-facing-docs`, `check-doc-stubs`, `check-agy-skills`, and `pwsh -NoProfile -File scripts/check-plugin-namespace.ps1` ("OK: plugin namespace rename complete ...") all exit 0; `claude plugin validate clavity-dotnet/plugin` and `... clavity-classic/plugin` both exit 0 with "Validation passed with warnings". `just check-links` already FAILS on clean `main` (`./README.md (104, 14) => ../../releases`, exit 1): compare it before and after, never expect green.

---

### Task 1: Branch, copy into clavity-dotnet, see the gates go red

**Files:** Create the seven files listed under File Structure for clavity-dotnet.

**Interfaces:** Produces the dotnet skill folder that Tasks 2-4 edit and Task 5 copies.

- [ ] **Step 1: Branch and copy.** `git switch -c feat/peer-reviewed-design-port`, then copy `SKILL.md` and `references/` from the source into `clavity-dotnet/plugin/skills/peer-reviewed-design/`. Then `git add -N clavity-dotnet/plugin/skills/peer-reviewed-design` (the frontmatter gate lists files with `git ls-files`, so an unstaged new file is silently skipped).
- [ ] **Step 2: Red.** Run `just check-injected-context`. Expected: FAIL, violations only in `SKILL.md` and `references/execution-index.md`, invariants `encoding` and `reference` (`broken: MEMORY.md`). Run `just check-skill-frontmatter`. Expected: `OK - 22 SKILL.md checked (1 excluded)`. [RF 4] That gate parses with strict yq, stricter than Claude Code under CRLF, so a pass covers a Windows checkout.
- [ ] **Step 3: Confirm the byte-level source of the failures.** `LC_ALL=C grep -n -P '[^\x00-\x7F]' <dotnet skill folder>/SKILL.md <dotnet skill folder>/references/*.md` must show exactly three lines: `SKILL.md:19`, `SKILL.md:20`, `references/execution-index.md:44`.

### Task 2: Mechanical fixes (design edits 1 and 2)

**Files:** Modify `SKILL.md` lines 19-20 and 171; `references/execution-index.md` lines 4 and 44 (dotnet copy).

**Interfaces:** Consumes Task 1's folder. Produces a folder that passes `check-injected-context`.

- [ ] **Step 1: ASCII diagram.** In `SKILL.md` lines 19-20 replace `──>` with `-->` and `│` with `|`, re-aligning the columns so the picture reads the same. In `references/execution-index.md` line 44 replace the leading `▶` with `->`. No other character changes.
- [ ] **Step 2: Unresolvable name.** In `SKILL.md` line 171 and `references/execution-index.md` line 4, replace the backticked `MEMORY.md` with the plain words "the memory index file". Keep the sentence otherwise as is.
- [ ] **Step 3: Green.** Run `just check-injected-context`. Expected: `check-injected-context: OK`. Run the Task 1 Step 3 grep again: zero output.

### Task 3: Marker writer, `<BASE>`, reference paths, cross-references (design edits 3, 5, 6, 9)

**Files:** Modify `SKILL.md` (sections 2 and "References", line ~184), `references/fork-brief.md` lines 3-17, `references/panel-brief.md` line 80, `references/agreement-round.md` line 14.

**Interfaces:** Produces the `<BASE>` convention Task 4 relies on.

- [ ] **Step 1: Red.** `grep -rn 'agy-mark' <dotnet skill folder> | grep -v '<BASE>/../../hooks/'` returns exactly two lines: `references/fork-brief.md:10` and `references/panel-brief.md:80` (control, measured on the source skill).
- [ ] **Step 2: `fork-brief.md` lines 3-17.** Replace the `MARK=$(ls -d ~/.claude/plugins/cache/...)` block with the shipped skills' form: two guarded calls `bash "<BASE>/../../hooks/agy-mark.sh" prepare "seams/<topic>-first.md"` and `... prepare "scratch/<topic>/notes.md"`, each as `if ! bash ...; then echo "peer-reviewed-design: ABORTING - could not prepare a shielded .clavity/ directory for <relpath>." >&2; exit 1; fi`. Replace the "If no writer is found" paragraph so it says: a non-zero exit means the peer channel is unavailable; halt and ask the owner, as for an unreachable peer.
- [ ] **Step 3: `panel-brief.md` line 80.** Write the call as `bash "<BASE>/../../hooks/agy-mark.sh" head "agy-panel" "$(git rev-parse HEAD)"`.
- [ ] **Step 4: Define `<BASE>` once.** Add this paragraph at the top of `SKILL.md`'s "## References" section: `<BASE>` is this skill's own base directory, as the harness supplies it at invocation time (the "Base directory for this skill:" line that heads the loaded text); it is not `${BASH_SOURCE[0]}`. Every `references/<file>` in this skill means `<BASE>/references/<file>`. In `agreement-round.md` line 14 write the citation as `<BASE>/references/fork-brief.md`.
- [ ] **Step 5: Cross-references and defaults.** In `SKILL.md` lines 30, 143 and 179, name the superpowers skills (brainstorming, writing-plans, subagent-driven-development, executing-plans) with "when available". Leave every `discipline` value bare. In `SKILL.md` lines 137, 141 and 144 state the `docs/superpowers/...` locations as defaults that the project's own convention overrides.
- [ ] **Step 6: Green.** The Step 1 command now prints nothing. `grep -rnE 'discipline.*clavity:' <dotnet skill folder>` prints nothing. `just check-injected-context` prints `OK`.

### Task 4: Transport for both variants, execution-index fallback (design edits 4 and 7)

**Files:** Modify `SKILL.md` section 3 (lines 71-80) and section 8 (lines 168-175); `references/fork-brief.md` lines 99-105 and "## Transport" (lines 111-118); `references/panel-brief.md` lines 46-48; `references/execution-index.md` lines 1-6.

**Interfaces:** Consumes `<BASE>` from Task 3.

- [ ] **Step 1: Find every place.** `grep -rn 'driver\|artifactPath\|agy_ask\|agy_status\|clavity ask' <dotnet skill folder>` lists them; the source has these: `SKILL.md:73-74`, `fork-brief.md:99-105`, `fork-brief.md:113-116`, `panel-brief.md:46-48`. "Driver" has two senses in this skill: the driving agent (you), at `SKILL.md:10`, `fork-brief.md:42` and `execution-index.md:25`: leave those; and the MCP server's completeness checks, at `panel-brief.md:48`, `fork-brief.md:102` and `fork-brief.md:115`: those get the two-clause text.
- [ ] **Step 2: Two-clause text in each place.** Each of the four places states both variants in one text: on clavity-dotnet the driver checks completeness (idle check with `agy_status`, then `agy_ask` with `discipline` and `artifactPath`; a reply not ending in the expected token is flagged); on clavity-classic there is no such parameter, `clavity ask "<payload>" --review-only` is the front door, and the driver demands the echo and the terminal line and verifies both by eye. Keep the existing sentence about never using the delegation bridge.
- [ ] **Step 3: Execution index [RF 1].** In `SKILL.md` section 8 and `references/execution-index.md` lines 1-6 write the rule: use the harness's persistent memory directory when it has one; otherwise ONE file per project at `.clavity/execution/<project>.md`, where `<project>` is the repository directory's basename with every character outside `[A-Za-z0-9_-]` replaced by `-`; create it through `bash "<BASE>/../../hooks/agy-mark.sh" prepare "execution/<project>.md"` and abort if that exits non-zero. Add the discovery rule (the skill's opening step lists `.clavity/execution/` and the memory index; more than one candidate means ask the owner), the closing rule (`DONE` as the resume point), and the loss rule (`.clavity/` is gitignored and `git clean -fdx` erases it; shas are re-derivable from git but verbatim rulings are not, so each ruling is also written into the committed artifact's review ledger).
- [ ] **Step 4: Prove the sanitizing rule is needed [RF 1].** In a scratch git repo (`mktemp -d`, outside the repository), run `bash <dotnet plugin>/hooks/agy-mark.sh prepare "execution/a..b.md"`: expected exit 1, `REFUSED - relpath must not contain '..'`. Then with the sanitized name `a-b`: expected exit 0.
- [ ] **Step 5: Green.** Re-run Step 1's grep: every hit sits in a text that carries both clauses ([RF 2], read each). `just check-injected-context` prints `OK`.

### Task 5: README line, mirror to classic, shared gates

**Files:** Modify `clavity-dotnet/plugin/README.md` after line 23; Create the seven files under `clavity-classic/plugin/skills/peer-reviewed-design/`.

**Interfaces:** Consumes the finished dotnet folder.

- [ ] **Step 1: README.** After the `skills/platform-handoff/` line (23) add `  skills/peer-reviewed-design/               # Claude: drive a design phase through decision forks, a peer consult per fork, measurement and owner rulings`, keeping the existing column alignment. Classic's `plugin/README.md` gets no line (it lists only `responder` and `driving`).
- [ ] **Step 2: Mirror.** Copy the dotnet skill folder to `clavity-classic/plugin/skills/peer-reviewed-design/` (`cp -r`), then `git add -N` it.
- [ ] **Step 3: Gates.** Run, from the repo root: `just seed-sync-check` (expect `seed agent artifacts in sync ...`), `just check-skill-frontmatter` (expect `OK - 23 SKILL.md checked (1 excluded)`), `just check-injected-context` (`OK`), `just check-control-bytes`, `just check-user-facing-docs`, `just check-doc-stubs`, `just check-agy-skills` (no-regression only: it never reads this skill), and `pwsh -NoProfile -File scripts/check-plugin-namespace.ps1`. Each exits 0. `just check-links` still fails exactly as on `main` and prints no new offender.
- [ ] **Step 4: Repo test gate.** `just test` (compiles dotnet and rust; slow). Expected: exits 0, the same as on `main`. If it fails, run it on `main` before blaming the port.

### Task 6: Verification the design lists

**Files:** none modified; results go into the review ledger of the design doc.

- [ ] **Step 1: Folders identical.** `diff -r clavity-dotnet/plugin/skills/peer-reviewed-design clavity-classic/plugin/skills/peer-reviewed-design` prints nothing.
- [ ] **Step 2: Personal-name and path greps.** `rg -n -e '~/.claude' -e '/home/' -e 'C:\\Users' -e '<owner-given-name>' -e '<owner-handle>' -e '<owner-surname>' -e '<owner-mail-provider>' clavity-dotnet/plugin/skills/peer-reviewed-design clavity-classic/plugin/skills/peer-reviewed-design` prints nothing (the four `<owner-...>` placeholders stand for the owner's real given name, handle, surname and mail-provider word; the literals were run when this was executed and replaced when the plan was committed).
- [ ] **Step 3: Marker path resolves.** `test -f clavity-dotnet/plugin/skills/peer-reviewed-design/../../hooks/agy-mark.sh` and the classic equivalent both exit 0.
- [ ] **Step 4: Bare-marker and discipline checks.** The Task 3 Step 1 command prints nothing; `grep -rn 'discipline' <skill folder>` lists seven or fewer lines, each read: every value passed to `agy_ask` is `agy-first` or `adversarial-panel-review`.
- [ ] **Step 5: Validate.** `claude plugin validate clavity-dotnet/plugin` and `claude plugin validate clavity-classic/plugin`: each exits 0 with `Validation passed` (baseline for dotnet: "passed with warnings"; no new warning may name this skill).
- [ ] **Step 6: Load check, personal copy present [RF 3].** In a fresh session run `claude --plugin-dir clavity-dotnet/plugin`, invoke `/clavity:peer-reviewed-design`, and confirm (a) the name is `clavity:peer-reviewed-design`, (b) it is advertised once, (c) the "Base directory for this skill:" line points under `clavity-dotnet/plugin/skills/peer-reviewed-design`, not `~/.claude/skills`, and (d) one `references/` file reads from that base directory. Repeat for `clavity-classic/plugin`.
- [ ] **Step 7: Record.** Append the Task 5 and 6 results to the design doc's Review ledger. HOLD: commit on the owner's word with `git add -f docs/superpowers/specs/2026-11-12-peer-reviewed-design-port-design.md docs/superpowers/plans/2026-11-12-peer-reviewed-design-port.md` plus the plugin files, message `feat(plugin): peer-reviewed-design skill in both plugins`.

## Self-review (run 2026-11-12)

- **Spec coverage:** goals 1-4 -> Tasks 1-5; edits 1, 2 -> Task 2; 3, 5, 6, 9 -> Task 3; 4, 7 -> Task 4; 8 -> Task 5; every Verification bullet in the spec -> Task 6 (the `just test` run is Task 5 Step 4). Release and retirement are owner items, deliberately no task.
- **Step scan:** the two edits whose wording the spec fixes (transport clauses, execution-index rules) are given as rules with their exact values, not drafted prose; the implementer writes the sentences.
- **Types/names:** `<BASE>`, `<project>`, `agy-mark.sh prepare|head`, bare discipline values are spelled the same in every task.
- **Proportion:** this plan is shorter than the design plus its ledger; no code bodies.
- **Open for the owner at handoff:** Review Focus item 5 (no-commit repository) and the pre-existing `check-links` failure on `main`.

## Review ledger

- Panel round 1, solo floor (driver): one finding, FOLDED: Task 4 Step 1 mislabelled the word "driver" at three
  places (it means the driving agent there, not the person at the keyboard); the plan now separates the two senses.
  Two commands without a baseline (`check-plugin-namespace`, `claude plugin validate` on classic) were run and their
  baselines added.
- Panel round 1, peer (seam `.clavity/seams/pr-design-port-plan-panel-r1.md`, reply
  `.clavity/scratch/pr-design-port-plan/reply.md`): `PANEL VERDICT: CLEAN`, no breach (tree, both checksums and the
  home mtime unchanged). The clean round was not taken on trust: the driver ran the plan's two riskiest red steps
  in a scratch copy and they matched the plan exactly (intent-to-add files seen by `git ls-files`; frontmatter
  `OK - 22 SKILL.md checked`; `check-injected-context: 4 violation(s)` in the two named files; the Task 6 name grep
  finds exactly `references/fork-brief.md:10` on the unedited source). The round's own coverage claims were mostly
  restatements of the plan's numbers.

## Stand-downs

None. DISCARDED-BELOW-FLOOR: none. UNVERIFIED-ACCEPTED: none.

Plan ends here: the execution style is the owner's choice.

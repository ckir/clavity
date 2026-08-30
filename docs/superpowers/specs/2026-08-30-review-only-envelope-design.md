# Review-only consult envelope: close the detection hole and the two skill gaps

**Status:** design, owner-approved to write 2026-08-30. Not yet planned, not yet implemented.

**Goal.** Every review-only consult this plugin runs is wrapped in an envelope that (a) tells the peer
what is forbidden, (b) gives it a legal place to work, and (c) lets the driver DETECT a breach
afterwards - including breaches the current detection cannot see.

**Success criterion, checkable — and deliberately narrower than the first draft's.** After this change
the automatic guard reports: a change to the `.clavity/` shield file; a change to a named sensitive path
(`.env`, `.claude/settings.local.json`); and the appearance or disappearance of any top-level entry
under `.clavity/`. Today none of these is reported - measured, `git status --short` returns clean after
all of them.

⚠ **It does NOT report arbitrary writes inside driver-written subtrees** (`seams/`, `agy-marks/`,
`scratch/`). The first draft claimed to catch "a peer write to `.clavity/` outside its sanctioned
scratch directory"; a panel seat correctly pointed out that the revised design cannot honour that, and
the criterion is narrowed here rather than left overclaimed. Files in those subtrees are inert - nothing
executes or trusts them - whereas the shield governs whether the whole directory is exposed to git.

---

## 1. Context: what was measured, and what it overturned

### 1.1 The four review-only skills are inconsistent

All four ship twice, byte-identical (`clavity-dotnet/` and `clavity-classic/plugin/skills/<n>/SKILL.md`).

| skill | forbidden-actions banner | snapshot/diff instruction | scratch dir for the peer |
|---|---|---|---|
| `agy-capstone` | yes | yes | yes |
| `agy-test-audit` | yes | yes | yes |
| `agy-first` | yes | yes | **no** |
| `adversarial-panel-review` | **no** | **no** | **no** |

`ls-driving` is a mixed driving guide (it also delegates *mutating* work) and carries a banner at
`:53-54`; `ls-pairing` is the peer-side skill and needs no driver envelope. Neither is in scope.

> **Method warning, earned three times in one session.** Probing these files by grepping a single
> wording returned a WRONG answer three times: `ls-driving` has a forbidden-actions banner that never
> uses that phrase; `agy-first:67` provisions a working directory never called "scratch"; and a
> `grep -v` filter excluded the very path that answered whether the guard was wired. **Any check over
> this surface must key on structure, not phrasing.** This is also the argument that killed the
> consistency gate (section 4).

### 1.2 The detection hole - the finding that drives this spec

Every one of these skills instructs the driver to detect a breach with `git status --short`.

**Measured with `git check-ignore`:** `.env`, `.claude/settings.local.json`, and everything under
`.clavity/` are ALL ignored. That check therefore reports a clean run after a peer overwrites the
owner's local Claude settings file, or drops a payload into `.clavity/`.

The record shows why this matters: `.clavity/agy-marks/skipped.log` carries **12 `agy-capstone` and 1
`agy-test-audit`** breach/waiver lines. The round-10 breach was caught ONLY because that peer wrote to
the repository **root**, which is visible to `git status`.

### 1.3 A strong guard already exists, and the skills do not know about it

`plugin/hooks/agy-consult-guard-{pre,post}.sh` are registered in `plugin/hooks/hooks.json:17-19` and
`:38-40` on `PreToolUse` and `PostToolUse` with matcher `Bash|PowerShell|mcp__.*agy_ask`. They bracket
every consult automatically and compare a 7-axis fingerprint, `agy_guard_quad`
(`agy-consult-guard-lib.sh:102-121`):

| axis | what it catches |
|---|---|
| `HEAD` | a commit or reset |
| `git status --porcelain` (hashed) | tracked + untracked visible changes |
| `git diff` + `git diff --cached` | content changes staged or not |
| `refs/stash` | a stash push/pop |
| `show-ref` minus stash | any branch/tag movement |
| `$gitdir/hooks/*` contents + `config` + `info/exclude` | a planted git hook or config change |
| `ls-files -v` non-`H` entries | skip-worktree / assume-unchanged smuggling |

**This is considerably stronger than what the skills describe** - it already covers `.git/hooks`, which
`git status` never sees. **It has exactly one hole: gitignored worktree paths**, because
`status --porcelain` omits them without `--ignored`.

**No skill mentions the guard exists.** Confirmed: `grep -rln 'consult-guard\|guard_quad'` over the four
`SKILL.md` files returns nothing. So drivers perform a weaker manual check and may reasonably mistake it
for the safety net.

### 1.4 Prevention was investigated and is KILLED - do not reopen

An AGY-FIRST consult (4 negotiation rounds, 2026-08-30) proposed that the driver mechanically strip
mutating tools from the peer instead of asking it to behave. **That proposal is dead on two independent
grounds, and the peer itself withdrew it:**

1. **Not available on the transport.** `SendUserCascadeMessageRequest` carries `cascade_id`, `items`,
   `cascade_config`, `blocking` and nothing else (`clavity.proto:127-133`). `BoundedView.cs:12`'s
   "permission arrays" are READ-side trajectory output, not a settable input.
2. **Not cheaply testable, and structurally self-defeating.** The local proto is marked `// partial`
   with fields "6..23 skipped", and is pinned at `:146` to revision `753169f` / agy-1.0.11 while the
   live peer is newer - so absence there proves nothing. The peer confirmed it exposes **no user-facing
   tool-restriction mode**, so its client never populates such a field and a wire capture yields only a
   weak negative. It concluded the question "cannot be settled cheaply at all"; the only stronger oracle
   is decompiling a 178 MB binary.
3. **Even if it were possible, it would break the discipline.** `agy-capstone:69-70` requires the driver
   to "let it read the committed diff itself" and to "never consult it on a pasted summary of your own
   reading". That rule is the spine of all four skills. Removing the peer's ability to read the
   repository removes the reason to ask a second model at all.

**Therefore prevention is out of reach and detection is the strongest available construct.** The peer's
converged position, after initially arguing the opposite: the detection work is "no longer conditional
fallbacks - they are the only viable path forward."

> **Caveat recorded deliberately:** item 2's claim that agy exposes no tool-restriction mode is **peer
> self-report about its own product**, not something this repository measured. Everything else in
> section 1 was verified against files. If that self-report is ever falsified, item 3 still stands
> independently.

---

## 2. Task 1 - give the guard an eighth axis: ignored paths

**Change:** extend `agy_guard_quad` in `plugin/hooks/agy-consult-guard-lib.sh` (both halves) with one
additional hashed axis covering the gitignored paths that must not change during a consult, and widen
the printed fingerprint from 7 fields to 8.

**What the axis covers — a NAMED SET, not a directory walk.** The first draft hashed all of `.clavity/`
minus `scratch/`. An adversarial panel killed that (section 2.3); what follows is the surviving design.

- `<repo>/.clavity/.gitignore` — **the shield.** This one file is the highest-value target under
  `.clavity/`: it contains a bare `*`, and it is the only reason the directory is invisible to git in a
  repository whose own `.gitignore` we do not control. Empty or delete it and the next `git add .`
  publishes untriaged anomalies and scratch content. It is tiny, and no driver rewrites it mid-consult.
- An explicit sensitive-path list, hashed by path and content when present: `.env`,
  `.claude/settings.local.json`.
- **The sorted list of top-level entry NAMES under `.clavity/`** - names only, not contents, not
  recursive. This is what catches a peer dropping a new file (`.clavity/backdoor.ps1`) that no
  content-hash of three named paths would ever see. It is one `readdir`, so it stays cheap, and it is
  concurrency-safe in practice because the churn under `.clavity/` happens *inside* `seams/`,
  `agy-marks/` and `scratch/` - a NEW top-level entry appears about once per install, not once per
  consult.

  ⚠ **Do not implement this as an allowlist of expected names.** Measured on this repository today,
  `.clavity/` holds **ten** top-level entries (`RUNBOOK-sessionstart-install.md`, `agy-marks`,
  `agy-model`, `consult-baseline`, `discipline-reaching.jsonl`, `local-anomalies.md`, two `.bak` files,
  `scratch`, `seams`) - and that set drifts as tooling is added. An allowlist would red on legal input
  the first time a new runtime file appears. Hash the observed set at PRE and compare to the observed
  set at POST; the guard needs to know only that it CHANGED, not what the legitimate set is.

**What it deliberately does NOT cover, beyond `scratch/` — and this is the panel's doing.**
`.clavity/seams/`, `.clavity/agy-marks/` and `.clavity/local-anomalies.md` are **driver-written and
concurrent by design**, so hashing them manufactures false breach reports (section 2.3). They are out.

The set is therefore **three named paths**, which is what makes the rest of this design work: it is
cheap regardless of repository age, it cannot collide with a concurrent session's legitimate writes, and
because it is a fixed enumerable list, `post` can name exactly which member changed instead of trying to
invert a hash.

**Two mechanisms rejected, and why - so they are not re-proposed.**

- **A per-topic scratch check.** Each consult sanctions exactly `.clavity/scratch/<topic>/`, so it is
  tempting to report writes to any OTHER topic's scratch dir. Rejected: the guard is generic - it fires
  on a tool matcher and has no idea which topic is live - so honouring the distinction means threading
  per-consult state into a hook that deliberately has none. A peer writing into a different topic's
  scratch directory is therefore invisible, accepted because scratch is disposable by construction and
  nothing downstream trusts it. Recorded because this is the obvious "improvement" a future reader will
  propose.
- `git status --ignored` as the mechanism. It would technically see these paths, but it also enumerates
  every build artifact (`bin/`, `obj/`, `target/`, `node_modules/`). A check that shouts on every run is
  a check operators learn to ignore, which is how a guard becomes decorative.
- Paths outside the repository (`~/.claude/`, `%USERPROFILE%`). Out of scope for a repo-anchored guard;
  recorded as an accepted limitation in section 6.

**Why this does not fire on ordinary Bash calls - the obvious objection, answered.** The hook matcher is
wide, but `agy_guard_category` (`agy-consult-guard-lib.sh`) classifies each call, and
`agy-consult-guard-post.sh:26-30` COMPARES only for the `sync` and `terminal` categories; `open` and
`none` exit 0 immediately. An ordinary Bash call is `none`. So the comparison window is exactly the
consult, and a driver writing `.clavity/seams/<topic>.md` in a separate earlier call is never inside it.

**Cost, measured rather than assumed.** `agy-consult-guard-pre.sh:23-27` exits 0 for the `none` and
`terminal` categories, so the fingerprint is computed only for `sync` and `open` - consults - and NOT on
every Bash/PowerShell turn. A panel seat argued the opposite and it is refuted by that branch.

The growth concern behind that seat's finding is real, though, and measuring it is what killed the
directory-walk design: **`.clavity/seams/` already holds 702 files / 5.9 MB and grows by one file per
consult, forever.** Hashing it per consult is a monotonically growing cost for no benefit, since nothing
under `seams/` is peer-writable. The three-path named set is bounded by construction and needs no
size fallback.

**The sensitive-path list is FIXED, not configurable.** A user-editable list is a way to quietly disable
the check, and the two entries are chosen because both were measured invisible today. Adding a path is a
code change that goes through review, which is the point.

**What "REPORTED" means concretely.** The axis emits through the existing `emit` path with its own
distinct message naming the changed path class - never folded into the existing
`VERSION CONTROL CHANGED` string. A shared message would make the two indistinguishable in the log and
would defeat the row in section 5 that must assert WHICH warning fired.

### 2.0 The fingerprint is a positional contract - three call sites, not one

`agy_guard_quad` returns a `|`-delimited 7-field string, and `agy-consult-guard-post.sh:66-71` parses it
**positionally, with exactly seven `read` variables**, twice (once for `before`, once for `after`).
Adding a field without updating those parses does NOT fail loudly.

**Measured with a control:** `IFS='|' read -r a b c d e f g <<< "1|2|3|4|5|6|7|8"` leaves `g` holding
`7|8`. So an unupdated parse folds the new axis into `b_flags`/`a_flags`.

The consequence is specific and worse than a crash:

- Detection still fires (the concatenated value differs), so the change is *caught* - the failure is
  fail-safe in direction.
- But the axis-diagnosis block at `:72-79` would report **"assume-unchanged/skip-worktree bits (hidden
  index smuggle)"** for what was actually a write to `.clavity/`. The operator is sent hunting an index
  attack that did not happen.

**Therefore this change has three coupled edit sites, and a plan must treat them as one unit:**
`agy_guard_quad` (emit 8), both `read` lines in `post.sh` (consume 8), and the diagnosis block (a branch
naming the new axis in its own words).

**And a fourth, easily missed.** The warning ends with `Changed paths:` populated from
`git status --porcelain` (`:81`). That command omits ignored files - which is the entire reason this
axis exists - so an ignored-path breach would report a breach with an **empty path list**: an alarming
event with no evidence for it.

This is why the axis is a **named set of three** rather than a directory hash. `post` cannot invert a
hash to recover which file moved (a panel seat raised exactly this, correctly), but it can re-check
three named paths and say which one differs. **The enumeration requirement is what forces the design to
stay small** - it is a constraint, not a nice-to-have.

**Delimiter safety.** `agy_guard_quad` joins fields with `|` and `post` splits on it positionally, so
any value this axis contributes - including any "unreadable" sentinel from the fail-open path above -
**MUST NOT contain a `|`**. A sentinel carrying the delimiter would shift every later field and corrupt
the comparison silently. Constrain the sentinel to a fixed delimiter-free literal, and pin it with a row.

### 2.1 A pre-existing defect this change must fix, not propagate

`agy-consult-guard-post.sh:53` tells the operator that with no hashing tool **"4 of 7 axes"** collapse,
and at `:57` that **"only HEAD and stash were compared"**. Those two claims contradict each other, and
the second is the correct one.

**Measured:** `agy_guard_quad` calls `agy_guard_hash` **5** times (status, diff, refs, gitmeta, flags),
and `agy_guard_hash` returns the constant `'NOHASH'` when neither `sha256sum` nor `shasum` is on PATH
(`agy-consult-guard-lib.sh:38-43`). So 5 of 7 collapse, leaving exactly HEAD and stash. The `4` is an
off-by-one, consistent with the `ls-files -v` flags axis having been added without updating the count.

The effect is that a degraded guard **understates its own blindness** to the operator - in the one
message whose entire job is to prevent false confidence.

This change touches that message anyway (7 axes become 8, and 5 collapsing become 6), so the count is
corrected in the same edit. Recorded explicitly because a pre-existing defect in code being modified is
in scope, and because silently rewriting the number would hide that it had been wrong.

**Failure posture.** The guard is `set +e` and fail-open by design (`agy-consult-guard-pre.sh:4`: "any
error -> exit 0"). The new axis MUST preserve that: an unreadable file or missing directory contributes
an empty component, never a non-zero exit. A PreToolUse hook that exits non-zero BLOCKS the tool call.

🔴 **But fail-open here has a failure mode the other axes do not, and it must be designed against.**
If a member of the set cannot be read, the naive implementation contributes the same empty value at PRE
and at POST. The two fingerprints then **compare equal, and the guard reports a CLEAN consult** - the
exact false confidence this whole spec exists to remove, reintroduced by the fix for it. "I could not
look" and "nothing changed" must not produce the same bytes.

**The axis is therefore FOUR independent components, not one blended hash**, joined by a delimiter that
is not `|`:

    <shield-hash-or-sentinel>:<env-hash-or-sentinel>:<settings-hash-or-sentinel>:<toplevel-names-hash>

Two properties follow, and both are required:

1. **Per-member state is recoverable at POST**, so the warning can name WHICH member changed. A single
   blended hash cannot support the enumeration section 2.0 requires - a panel seat raised exactly this
   and it is correct.
2. **Each component distinguishes "absent", "unreadable" and "present with content X"** using distinct
   delimiter-free sentinels. Absent is a legitimate steady state (`.env` usually does not exist); it must
   compare equal to itself across a clean consult, and must NOT compare equal to "unreadable".

A member that was readable at PRE and unreadable at POST must be reported, and a consult that could not
check the axis at all must emit the same class of `PARTIALLY VERIFIED` warning the no-hashing-tool path
already emits at `agy-consult-guard-post.sh:49-52`. That precedent is the model: the existing guard
already refuses to let a degraded check pass silently, and this axis must not be the exception.

**Scope of the hole this closes - stated so it is not oversold.** The axis covers `.clavity/` and two
named paths. It does NOT cover arbitrary gitignored files elsewhere in the tree (a gitignored
`secrets.yml`, a `.vscode/` setting). The blind spot is **narrowed to a bounded, reviewed set, not
closed.** Anything wider runs into the `--ignored` noise problem above.

---

### 2.3 What the adversarial panel changed, and what it got wrong

An agy panel round over the first draft returned **RED** with four findings. Three were confirmed by
measurement and folded; one was half right. Recorded because the design it produced is materially
different from the one it reviewed, and a later reader should know why the obvious approach was rejected.

| finding | verdict | how it was settled |
|---|---|---|
| A `\|` inside the "unreadable" sentinel shatters positional parsing | **CONFIRMED** | The delimiter contract is real; a control (`read` with 7 vars, 8 fields) already showed the shift. Folded as an explicit delimiter ban. |
| Hashing `.clavity/` falsely accuses a peer when a CONCURRENT session writes a seam | **CONFIRMED, and it killed the original design** | `.clavity/seams/`, `agy-marks/` and `local-anomalies.md` are driver-written; the open-issues skill mandates atomic `>>` appends precisely because two sessions on one repository "is ordinary". A guard that reds on legal input is its own defect. |
| Enumerating changed paths from a one-way hash is impossible | **CONFIRMED** | `pre` stores only the fingerprint, so there is no manifest to diff. Resolved structurally: a fixed three-path set is enumerable without inverting anything. |
| The hook hashes on every shell turn, an unbounded hot-path penalty | **HALF** | Mechanism **refuted**: `pre.sh:23-27` exits 0 for `none`/`terminal`, so only consults compute it. Growth claim **confirmed and understated**: `seams/` measured at 702 files / 5.9 MB. |

**The pattern worth carrying forward:** two seats reached the same place from different directions -
concurrency safety and cost both said *stop walking the directory*. Neither alone would have been
decisive; together they replaced a directory hash with a named set, which then dissolved the third
finding as a side effect.

⚠ **One seat's stated mechanism was wrong while its conclusion was right.** Folding the Resource
Vampire finding as stated would have produced a size-based fallback for a problem that does not exist on
the hot path. Verifying the mechanism, not just the conclusion, is what turned it into the right change.

### 2.4 Panel round 2 - the fix reopened the hole, and a seat caught it

Round 2 was RED with four more findings: three confirmed, one refuted. The round was worth running
specifically because a bespoke seat was staffed at *"where does this fix introduce the defect it was
written to prevent?"* - and that is the seat that found the worst item.

| finding | verdict | how it was settled |
|---|---|---|
| The named 3-path set ignores NEW files dropped into `.clavity/`, so a payload write reports CLEAN - **"you fixed the false positive by reopening the literal hole you started with"** | **CONFIRMED, and worse than stated** | Correct, and it also broke the spec's own success criterion. Fixed by adding a top-level NAME census, and by narrowing the success criterion instead of leaving it overclaimed. The seat assumed a small known set; measured, `.clavity/` holds **ten** top-level entries and drifts - which is why the census must hash the observed set rather than check an allowlist. |
| `post` cannot name which member changed if the axis is one blended hash | **CONFIRMED** | The axis is now four independently-serialized components. |
| The fail-open text still describes directory enumeration, vestigial from the killed design | **CONFIRMED** | Rewritten for a named set, with explicit absent / unreadable / present sentinels. A genuine internal inconsistency my own consistency pass missed because I re-read only the top of section 2. |
| The hook matcher omits agy's own shell tool (`run_command`), so the guard never fires for peer shell execution | **REFUTED** | This is a **Claude Code** hook (`${CLAUDE_PLUGIN_ROOT}`, `PreToolUse`/`PostToolUse`) matching on *Claude's* tool names. It brackets the driver's `agy_ask` call; the peer runs in a separate process and its tool calls are never visible to it. Adding `run_command` would match nothing. The seat misread whose tools the matcher covers. |

**The lesson this round paid for:** the round-1 fix was correct about concurrency and *introduced* a
false-GREEN while removing a false-RED. Nothing in rounds 0 or 1 would have caught it, because both were
looking at the design as proposed rather than at the delta between designs. **A seat aimed explicitly at
the fix, rather than at the artifact, is what found it** - and this repository already had the evidence
that it would (three consecutive rounds in one file, each finding a defect created by the previous
round's fix).

## 3. Tasks 2 and 3 - close the two skill gaps

**Task 2 - `agy-first` gets a legal scratch directory.** It currently prepares only
`.clavity/seams/<topic>.md` (`agy-first:64-76`), giving the peer somewhere to READ but nowhere to WRITE.
The breach log attributes one recorded breach to exactly this driver-side defect: a payload that forbade
any working file while asking the peer to verify against live files, so no legal scratch area existed.
Add the `prepare "scratch/<topic>/notes.md"` call and the naming requirement, matching
`agy-capstone:71-84` and `agy-test-audit:67-75`.

> Note: `agy-first` does NOT order the peer to measure - `:128` puts that duty on the driver
> ("Before folding ANY factual claim **the peer** makes, verify it by measurement"). The consult peer
> initially misread this and called `agy-first` the worst of the four; sent back to the line, it
> withdrew. The scratch directory is still warranted, because a driver MAY legitimately frame a
> measure-and-reproduce consult - `agy-capstone:70` explicitly contemplates that framing and requires a
> scratch dir when it happens.

**Task 3 - `adversarial-panel-review` gets the full envelope.** It routes an artifact to the live peer
in its Step 2 (`:49-85`) with no snapshot, no forbidden-actions banner, no scratch directory and no
diff-after. Add the same five-step envelope the other three carry, adapted to the panel's Step 2, plus
the `prepare` call and its abort-on-failure branch.

---

## 4. Explicit non-goal: no consistency gate

A mechanical check asserting "every review-only skill carries all three properties" was considered and
**rejected**, independently by the driver and the consult peer.

The reason is measured, not aesthetic: probing this exact surface by phrasing produced three wrong
answers in one session (section 1.1). A prose-matching gate inherits that fragility and goes vacuous the
moment someone rephrases a banner - yielding a false GREEN while providing no coverage. This repository
has already deleted one gate whose own defect rate exceeded its discovery rate.

**If a future maintainer decides one is needed anyway**, the peer's suggestion is on record and is
better than grep: key it on a structural marker that cannot drift, such as a `SKILL.md` frontmatter flag
(`requires_review_envelope: true`), never on the body text.

---

## 5. Testing

Both halves of every changed file must stay byte-identical, and the change must pass
`plugin-hooks-payload.Tests.ps1` and `check-seed-artifacts-synced.sh`.

The new axis needs rows in `scripts/tests/agy-consult-guard.Tests.ps1` pinning **both directions** - a
gate that reds on legal input is its own defect:

1. **Reds on the illegal shape:** emptying or deleting `.clavity/.gitignore` between pre and post is
   REPORTED. Must fail if the axis is removed. (Chosen deliberately: this is the shield, and its loss is
   the highest-consequence silent change under `.clavity/`.)
2. **Accepts legitimate concurrency - the false-positive guard, and the row most likely to be got
   wrong.** Writes to `.clavity/seams/other-topic.md`, `.clavity/agy-marks/skipped.log` and
   `.clavity/scratch/<topic>/notes.md` between pre and post are **NOT** reported. These are the paths a
   concurrent driver session legitimately writes; a guard that reds here is worse than no guard, because
   it trains the operator to dismiss the warning. **This row is what the panel bought** (section 2.3).
3. **Reds on a sensitive path:** a write to `.claude/settings.local.json` is REPORTED.
3a. **Reds on a dropped payload:** creating `.clavity/backdoor.ps1` between pre and post is REPORTED by
   the top-level name census. **This is the row that pins the hole the round-1 fix reopened**
   (section 2.4); without it the design passes every other row while failing its own success criterion.
3b. **The sentinel is delimiter-free:** whatever value the axis contributes on an unreadable read
   contains no `|`. Assert it directly rather than trusting the literal to stay safe through edits.
4. **Fail-open preserved:** with `.clavity/` absent or unreadable, the hook still exits 0 and the
   fingerprint is well-formed. A PreToolUse hook that exits non-zero blocks the tool call.
5. **Field count:** the fingerprint has 8 components, asserted structurally rather than by matching the
   printed string.
6. **"Could not look" is distinguishable from "nothing changed."** With `.clavity/` made unreadable
   between PRE and POST, the guard must NOT report a clean consult - it must warn. **This is the row
   that pins the failure mode the fix could otherwise introduce**, and it is the one to write first,
   because a naive implementation passes every other row on this list while failing this one.
7. **The degraded-mode count is self-checking** (section 2.1). With no hashing tool on PATH, the guard
   emits `PARTIALLY VERIFIED` and the number it names must EQUAL the count of `agy_guard_hash` call
   sites in `agy-consult-guard-lib.sh`. Deriving the expected value from the source rather than hard-
   coding `6` is what stops the off-by-one recurring the next time an axis is added - a literal `6`
   would rot exactly as the `4` did. This is a mechanical oracle, not a source-text match.

**Every new row must be mutation-proven** - a logic mutant of the axis, not a signature break - and the
specific new row must be the one that goes red. Assert WHICH row failed, not that the suite returned
non-zero.

⚠ `agy-consult-guard.Tests.ps1` has known pre-existing coverage gaps recorded in earlier capstone rounds
(no exit-code assertions; the async half untested). Those are NOT in scope here and must not be silently
absorbed; if the new rows touch that machinery, say so rather than expanding scope.

---

## 6. Accepted limitations

- **Detection, not prevention.** A peer that runs `rm -rf` outside the repository, drops a database, or
  calls an external API leaves no trace any of these axes can see. The guard is a repo-anchored
  hygiene-and-attribution mechanism. Stating this plainly is part of the design, because the previous
  wording let `git status --short` read as a safety boundary.
- **Writes outside the repository are invisible** (`~/.claude/`, `%USERPROFILE%`, system paths).
- **The guard is fail-open by construction.** A machine with no hashing tool degrades to a partial
  check; the guard says so rather than passing silently, and that behaviour is preserved.

---

## 7. Sequencing

This spec is Task 1-3 of the sequence the owner ruled on 2026-08-30: bootstrap the reviewer before
using it. ROADMAP §22, §21 and §23 follow, in that order, after this lands.

Because all changed files ship in the installer payload, a defect here is class 2 (BLOCKING) by
`agy-capstone/SKILL.md:156-193`. This change wants a panel review and its own capstone - not a quiet
edit.

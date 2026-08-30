# Review-only consult envelope: close the detection hole and the two skill gaps

**Status:** design, owner-approved to write 2026-08-30. Not yet planned, not yet implemented.

**Goal.** Every review-only consult this plugin runs is wrapped in an envelope that (a) tells the peer
what is forbidden, (b) gives it a legal place to work, and (c) lets the driver DETECT a breach
afterwards - including breaches the current detection cannot see.

**Success criterion, checkable.** After this change, a peer write to `.clavity/` outside its sanctioned
scratch directory, or to a named sensitive path, is reported by the automatic guard. Today it is not:
measured, `git status --short` reports a clean run after such a write.

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

**What the axis covers.**

- Everything under `<repo>/.clavity/` **except** `<repo>/.clavity/scratch/`. Scratch is by definition
  the sanctioned write area; marks, seams and the anomalies file are not.
- An explicit sensitive-path list, hashed by path and content when present: `.env`,
  `.claude/settings.local.json`.

**What it deliberately does NOT cover, and why.**

- `.clavity/scratch/**` - the peer is invited to write there; hashing it guarantees a false positive on
  every legitimate consult. This is the single most important exclusion in the design.
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

**Cost constraint, which is still load-bearing.** `pre.sh` computes the fingerprint on every matched
call even when `post` will not compare it, so the axis must stay cheap: excluding `scratch/` removes the
only directory expected to grow, and the sensitive-path list is a fixed set of two. If the axis
measurably slows the hot path, the fallback is to hash names+sizes+mtimes rather than contents.

**The sensitive-path list is FIXED, not configurable.** A user-editable list is a way to quietly disable
the check, and the two entries are chosen because both were measured invisible today. Adding a path is a
code change that goes through review, which is the point.

**What "REPORTED" means concretely.** The axis emits through the existing `emit` path with its own
distinct message naming the changed path class - never folded into the existing
`VERSION CONTROL CHANGED` string. A shared message would make the two indistinguishable in the log and
would defeat the row in section 5 that must assert WHICH warning fired.

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

---

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

1. **Reds on the illegal shape:** a write to `.clavity/local-anomalies.md` between pre and post is
   REPORTED. Must fail if the axis is removed.
2. **Accepts the legal shape:** a write to `.clavity/scratch/<topic>/notes.md` between pre and post is
   NOT reported. This is the false-positive guard and it is the row most likely to be got wrong.
3. **Reds on a sensitive path:** a write to `.claude/settings.local.json` is REPORTED.
4. **Fail-open preserved:** with `.clavity/` absent or unreadable, the hook still exits 0 and the
   fingerprint is well-formed. A PreToolUse hook that exits non-zero blocks the tool call.
5. **Field count:** the fingerprint has 8 components, asserted structurally rather than by matching the
   printed string.
6. **The degraded-mode count is self-checking** (section 2.1). With no hashing tool on PATH, the guard
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

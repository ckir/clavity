# Pre-release defect sweep — design

**Status:** owner-approved 2026-08-05. Written against `1516a2e`, tree clean, 42 unpushed.

**Framing ruling, owner, verbatim:** *"A release must not contain defects that can be fixed."*

That filter is not severity. It is three questions: does it SHIP, is it a DEFECT, can it be FIXED now.
An unknown is not a defect until investigated — a principle applied consistently below, including against
one item I wanted to keep.

---

## 1. What this is not — four phantom items, and one closed by investigation

Four entries carried in memory as open defects were verified **already fixed or never defects**. They are
recorded here so nobody re-adds them.

| carried as | reality |
|---|---|
| `check-seed-artifacts-synced.sh` "passes when `jq` is absent" | **Fixed.** `:10` — `command -v jq >/dev/null 2>&1 \|\| { echo "…jq is required"; }` fails loud |
| `LsDiscovery.cs` "never checks the HTTP pid matches the gRPC pid" | **Fixed.** `:136` `httpPid == pid`; fallback at `:148` additionally requires adjacent ports |
| two hardcoded `C:\!PORTABLES\!BIN\tmux.exe` paths | **Not shipped.** They exist only in `clavity-classic/publish/`, gitignored build output that `clavity-classic/scripts/build-classic-release.ps1` restages from source which no longer contains the path |
| `docs-audit` claim-count instability | **Documented at source** 2026-08-05 in `scripts/docs-audit.ps1`'s header |

**And one closed by investigation — `path-scan.iss` "dotnet gap".** Not a defect. `clavity-dotnet.iss:71`
implements the same PATH scan as Pascal `ClassicClavityOnPath`, and `scripts/lib/release-lib.ps1:47`
deliberately scopes it `Members=@('classic')` so `Assert-SharedMapHealthy` passes. Duplication is
intentional and both installers work. **Refactoring installer Pascal immediately before a release buys
nothing and risks Inno compilation.** Out of scope; revisit post-release if ever.

**Out of scope, does not ship — the ECC hook tax.** Seven ECC plugin hooks cost ~4-5s per firing, measured
at 770,0s of hook time in one `claude -p` run. Real, and the largest daily cost on this machine, but it is
not in the clavity release artifact. Tracked in `memory/project_tracked-debt.md` as an owner decision.

**Why this section exists.** Four of the items above came from my own notes, and every one was stale — twice
in the direction of phantom debt. A list assembled from notes tracks *past friction*, not *present surface*.

---

## 2. Scope — four units

### U1 — the `.no-agy` subdirectory bypass (17 files)

**The defect.** Each hook tests `.no-agy` against the payload's `cwd` and has **no repo-root walk at all**.
A user with `.no-agy` at their repository root who launches Claude in `repo/src` is not suppressed. This
is the same bug fixed in the recorder at `b5d6742`; these were left because they emit a message rather
than write a file, which is a different severity, not a different bug.

**Each hook has TWO `.no-agy` checks, not one.** This was missed on the first pass and is the single most
important structural fact for the plan:

- a **NORMAL-PATH** check against the payload's `cwd`, reached when `jq` is present;
- a **DEGRADED-BRANCH** check inside `if ! command -v jq`, testing `./.no-agy` — the PROCESS cwd — because
  without `jq` the payload cannot be parsed at all. `agy-after-reminder.sh:17` documents the intent:
  *"Honor the kill-switch first (global; cwd falls back to the process cwd without jq)."*

**The 17 files**, MEASURED 2026-08-05. Both drivers carry identical line numbers (the 8 shared files are
byte-identical pairs):

| hook | NORMAL-PATH check | DEGRADED-BRANCH check |
|---|---|---|
| `agy-anomaly-model-notice.sh` | `:26` | — (none) |
| `agy-anomaly-reminder.sh` | `:37` | `:27` |
| `agy-after-reminder.sh` | `:29` | `:18` |
| `agy-seam-inject.sh` | `:46` | `:32` |
| `agy-anomaly-capture-reminder.sh` | `:48` | `:40` |
| `agy-anomaly-dispatch-reminder.sh` | `:57` | `:49` |
| `agy-test-audit-reminder.sh` | `:61` | `:50` (uses `$cwd`, not `./`) |
| `agy-liveness-check.sh` | `:128` | `:29` + `:33` (announces, `exit 2`) |

Plus **classic-only**: `clavity-classic/plugin/hooks/agy-drive-session-reset.sh:9` — a bare
`[ -f "${cwd}/.no-agy" ] && exit 0`, no degraded branch, no `jq` dependency.

8 × 2 + 1 = **17 files**.

**The plan must decide the degraded branch explicitly, and it is not obvious.** The repo-root walk is pure
bash and needs no `jq`, so a degraded branch COULD walk up from `./`. Against that: `./` is the process
cwd, which is not necessarily the session's workspace, so walking from it could suppress on an unrelated
repository's `.no-agy`. Leaving it as-is preserves a known-narrow behaviour; changing it trades one
imprecision for another. **Decide in the plan with the reasoning recorded; do not let it default.**

**Provenance note, because it bears on trust.** These line numbers match the ORIGINAL anomaly capture
exactly. During this spec's self-audit I "re-measured" them twice and got two different wrong answers —
first matching `.no-agy` in COMMENT prose, then matching the DEGRADED-branch check — and briefly recorded
in this document that the original numbers were stale. They were not; my greps were. The lesson for the
plan: `grep` for a bare string finds comments and fallback paths, and `head -1` silently discards the one
you want.

**The template** is the recorder's fixed shape (`agy-discipline-reaching.sh`, `b5d6742`): check the GLOBAL
opt-out first (it does not depend on the root, so it stays cheap), then walk up for `.git`, then check
**both** `$root/.no-agy` and `$cwd_path/.no-agy`.

**Deliberately NOT copied from that template: `[ -e "$root/.git" ] || exit 0`.** That guard exists because
the recorder WRITES A FILE into the user's tree and a non-repo directory has no project to attribute a row
to. These nine only emit a message, so a non-git directory is harmless. Copying it would carry a guard
whose reason does not apply — and would silence nine hooks in every non-repo directory, a behaviour change
nobody asked for.

### U2 — a comment that asserts a false invariant (2 files)

`agy-discipline-reaching.sh` near `:94` justifies capturing `model` with *"a field not written at session
N cannot be recovered at N+1"*. MEASURED 2026-08-05: the first real post-install row was
`{"v":3,…,"source":"resume","model":""}` — `startup` and `compact` payloads carry `model`, `resume` does
not. **The hook is correct; it records what it is handed.** The comment is what is wrong.

In scope because a false invariant in shipped source is a defect attractor: the next reader — human or
model — reasons from it. One-line edit, both drivers, zero behaviour change, zero regression risk.

### U3 — ME1's two known gaps (3 files)

**U3a — `agy-consult-guard-lib.sh` has no test coverage.** `scripts/tests/agy-consult-guard.Tests.ps1:5-6`
binds only `$script:Pre` and `$script:Post`. The lib is the largest of the three at 6,9K and carries the
7-axis snapshot logic. Bind `$script:Lib` and include it in the ASCII and cross-driver parity assertions.

**U3b — the missing `.no-agy` opt-out is DESIGN, and must be documented as such.**

This was argued out with the peer and **both of our first answers were wrong.** Adding `.no-agy` to ME1
would create a **self-suppression exploit**: `.no-agy` is a file in the repository, so a review-only
consult that mutated version control could write `.no-agy` and thereby hide its own write — `post.sh`
would exit before diffing. A guard the untrusted actor can switch off is not a guard.

The codebase already states this principle. `clavity-classic/plugin/README.md`:

> There is deliberately no per-hook off switch… **One documented exception: the ownership check itself
> still runs under `.no-agy`** and reports that personal registrations remain, so the kill-switch cannot
> be used to hide an override.

ME1 is that class. `agy-consult-guard-lib.sh:17` already has a
`DELIBERATELY OUT OF SCOPE (documented, not a silent gap)` block listing the MCP signal bus and
`clavity ring`. **Add the `.no-agy` omission there**, with the self-suppression reason. Follows the file's
own convention; changes no behaviour.

**Verified and NOT a defect:** `agy-consult-guard-pre.sh` fails open — `exit 0` at `:11`, `:14`, `:27`,
`:29`, `:31`. A `PreToolUse` hook exiting 2 would BLOCK the tool call; this one cannot.

### U4 — `agy-drive-session-reset.sh` has no test suite

Eight of the nine hooks in U1 have suites with existing `.no-agy` coverage. This one has **none**. It is
also the hook a sweep of `clavity-dotnet/plugin/hooks` cannot find, being classic-only — it was missed by
exactly that method during this analysis and surfaced only by the peer. **Two independent signals landing
on one file is the argument for giving it a suite, not just a fix.**

Minimum: the same `.no-agy` scope coverage the other eight have, including the new subdirectory case.

---

## 3. Testing

**U1** — eight suites already assert `.no-agy` suppression. Extend each with the **subdirectory scope**,
following the shape proven in `scripts/tests/agy-discipline-reaching.Tests.ps1:201` — a `-ForEach` block
whose data gains a `root-from-subdir` case, so the TEST count rises without the BLOCK count changing.

Each case must assert the hook is **silent** — not merely that it exits 0, which the bypass also satisfies.

**U4** — a new suite. The eight existing ones supply the pattern.

**U3a** — extend the ME1 suite to cover the lib.

**Mutation requirement.** For each unit, prove the new assertion is load-bearing: revert the guard, confirm
the test fails, restore. Three vacuous assertions shipped in the SessionStart epic and were only caught by
mutation. A test that cannot fail is not coverage.

**Gates.** `bash scripts/check-seed-artifacts-synced.sh` (exit 0) for the 16 dual-driver files;
`just test-scripts-fast`; `just test-scripts-slow` (backgrounded — it exceeds the 600s tool cap, and the
ME1 suite lives there).

---

## 4. Sequence, and what forces it

**(U1 + U2) → (U3 + U4) → commit → capstone with ME1 seated → full gates → release.**

The peer initially argued the reverse — review ME1 first, because it would "overwrite" U1's edits in the
same directory. **Measured and refuted:** the six `agy-consult-guard-*` files contain **zero** occurrences
of `.no-agy`, so U1 never opens them. The two sets are disjoint. The peer withdrew the constraint, calling
it a false spatial generalization, and reversed to this order.

What genuinely orders it: U1 and U2 are the low-discovery work; landing them first banks the largest chunk
and leaves ME1 as an isolated task. Nothing else constrains it.

**U1 is NOT purely mechanical, and an earlier draft of this spec wrongly called it "zero-discovery".** The
two-check structure above means every one of the 17 files carries a judgement call about its degraded
branch, and `agy-liveness-check.sh` differs further: its degraded checks ANNOUNCE and `exit 2` rather than
exiting silently, so a change there alters user-visible boot output. Budget U1 as careful repetitive work
with one real decision, not as find-and-replace.

**One capstone, not two.** ME1's staged round-3 brief (`.clavity/seams/me1-capstone-r3.md`) is **stale** —
it names `C:/Users/user/.claude/hooks/…` from when ME1 was global config, and the old matcher
`mcp__plugin_clavity-dotnet_clavity-ls__agy_ask`; it ships from the plugin now with `mcp__.*agy_ask`.
Rather than repair it and run a separate review, fold its four hunt questions in as **named seats of the
single capstone over this release's committed range**. A capstone reviews committed code, so it would wait
for these commits regardless, and ME1's changed files are part of this diff. One review of what ships
together.

Its four seats, carried forward: a VCS mutation invisible to the 7 axes; a path that silently disables the
guard while the driver believes it protected; category mis-classification; and a two-slot lifecycle race
leaving a real mutation unreported — **a false negative being the fatal class for a guard.**

---

## 5. Risks

- **Byte-parity.** 16 of 17 files are dual-driver pairs. Every hook edit is two identical edits; never
  hand-type the second. `check-seed-artifacts-synced.sh` is the gate.
- **CRLF.** Editing an LF file has silently converted it four times in this repo. Verify CR counts by
  reading raw bytes in PowerShell — **not** with `grep -c $'\r'` inside command substitution, which returns
  the line count.
- **The installed plugin goes stale.** The hot-copy that proved the SessionStart recorder live will be
  superseded. Either redo it or let the release supersede it — but do not read the stale installed tree as
  evidence about the new code.
- **Test-suite registration is an explicit list in `justfile`, not a glob.** U4 adds a new suite; unless it
  is registered there it exists and never runs.
- **`_partition.md` must be re-measured**, not hand-edited, after the suites change. It was wrong in both
  columns for two commits precisely because nobody re-measured.

---

## 6. Success criteria

1. All 17 files honour `.no-agy` at the repo root from a subdirectory, each pinned by a test that fails
   when the guard is reverted.
2. `agy-drive-session-reset.sh` has a suite, registered in `justfile`.
3. `agy-consult-guard-lib.sh` is covered by the ME1 suite.
4. The `model` comment states what is true.
5. `lib.sh`'s OUT OF SCOPE block records the `.no-agy` omission and its reason.
6. Fast half and slow half green; `check-seed-artifacts-synced.sh` exit 0; `_partition.md` re-measured.
7. A capstone over the committed range, with ME1's four seats, reaching owner-confirmed GREEN.

---

## 7. Deliberately excluded

| item | why |
|---|---|
| Adding `.no-agy` to the consult guards | Would create a self-suppression exploit — see U3b |
| `[ -e "$root/.git" ] \|\| exit 0` in the nine reminders | The guard's reason does not apply; would silence them in every non-repo directory |
| `path-scan.iss` / `ClassicClavityOnPath` unification | Intentional duplication, roster correctly scoped, installer refactor before a release is unjustified risk |
| The ECC hook tax | Does not ship in this artifact; owner config decision |
| ME1 async attribution, the MCP signal bus, `clavity ring` | Already documented as out of scope in `lib.sh:17-21`; unchanged by this work |

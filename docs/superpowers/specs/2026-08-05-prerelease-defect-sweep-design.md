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
| two hardcoded `C:\!PORTABLES\!BIN\tmux.exe` paths | **Not shipped — but not where this row said.** RE-MEASURED panel round 3: the repo now contains exactly ONE occurrence, `clavity-classic/docs/archive/2026-06-16-agy-remote-control-design.md:75`, and it is prose in an archived design doc, not code. The two `clavity-classic/publish/` copies this row named are GONE — `publish/` still exists and contains no such reference |
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

**That "only a message" premise is TRUE OF SIXTEEN AND FALSE OF THE SEVENTEENTH.**
`agy-drive-session-reset.sh` deletes files — see the severity inversion under U4. It is stated here, at the
first place a reader meets the premise, because leaving the correction only at U4 lets anyone reading top
to bottom act on a claim this document itself refutes ninety lines later.

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
`[ -f "${cwd}/.no-agy" ] && exit 0`, with no degraded branch.

**CORRECTION (panel round 1, measured).** An earlier draft said this hook has "no `jq` dependency". That
is FALSE: `:7-8` call `jq` twice —

```bash
source="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
```

Without `jq` both are empty, so `:9` evaluates `[ -f "/.no-agy" ]` and `:13`
(`[ "$source" = "startup" ] || exit 0`) exits. The hook therefore HAS a degraded path — an undeclared,
untested one in which the kill-switch check reads an absolute `/.no-agy`. The plan must treat it as a
ninth degraded branch, not as the one file exempt from the question.

8 × 2 + 1 = **17 files**.

**The plan must decide the degraded branch explicitly, and it is not obvious.** The repo-root walk is pure
bash and needs no `jq`, so a degraded branch COULD walk up from `./`. Against that: `./` is the process
cwd, which is not necessarily the session's workspace, so walking from it could suppress on an unrelated
repository's `.no-agy`. **Decide in the plan with the reasoning recorded; do not let it default.**

**🔴 CORRECTION (panel round 1): that is a FALSE BINARY, and the third option is already proven in-tree.**
An earlier draft framed this as "leave `./` as-is" vs "walk from `./`", and the peer answered inside that
frame. Both miss that **the real cwd is recoverable without `jq`**. `agy-test-audit-reminder.sh:47` already
does it, with a field-bounded `sed` on the raw payload, and `:43-46` states the reason — *"the gate itself
needs the real cwd (not the process cwd, which may be an unrelated directory)"*, which is precisely the
objection raised against walking from `./`. The recorder does the same thing with a bash regex
(`agy-discipline-reaching.sh:41`) and no subprocess at all.

So the options are three, not two:

| option | degraded branch behaviour | cost |
|---|---|---|
| A — leave as-is | checks `./.no-agy` only; root opt-out ignored without `jq` | none; keeps a known gap |
| B — walk from `./` | walks up from the PROCESS cwd | may suppress on an unrelated repo |
| **C — recover the real cwd, then walk** | matches the normal path exactly | one regex; **already shipped in two hooks** |

**Option C makes the degraded branch as accurate as the normal path**, which collapses the whole dilemma:
there is then no "degraded" `.no-agy` semantics to reason about, only a degraded *output* path.

**DECIDED: option C.** The peer answered B in round 1 on the premise that *"the process cwd is always
inside the target workspace"*; challenged in round 2 to check that premise against the files, it withdrew
B and adopted C. Its Q2 answer is the part worth recording, because it is the honest one: **whether `./`
can differ from the payload `cwd` is NOT establishable from this repository** — the hook dispatcher is
closed-source host behaviour, and nothing in-tree constrains what working directory it hands a child hook.
An assumption we cannot check is exactly the assumption not to build on, and C is the option that does not
need it. Use the recorder's subprocess-free bash regex (`agy-discipline-reaching.sh:41`), not `sed`, so the
degraded branch costs zero forks.

**Recovery does not exempt any hook from normalization** — C recovers the *escaped* value, so `:49` is
still mandatory. C without `:49` is the same no-op with extra steps.

**🔴 AND THE EXISTING `sed` RECOVERY IS ALREADY BROKEN ON WINDOWS — a reachable, pre-existing defect in the
exact lines U1 edits.** MEASURED 2026-08-05 on `{"cwd":"C:\\Users\\user\\repo\\src"}`, the `:47` `sed`
captures `[^"]*` from the **raw, still-escaped** payload and yields `C:\\Users\\user\\repo\\src` with
DOUBLED backslashes. `:50` then evaluates `[ -f "C:\\Users\\user\\repo\\src/.no-agy" ]`, which does not
stat the intended file. **So `agy-test-audit-reminder.sh`'s degraded kill-switch check does not work on this
project's only target platform today.** Option C must therefore carry the recorder's `:49` normalization
too — recovery without normalization reproduces this bug in eight more files.

Per the standing owner ruling that pre-existing defects are in scope, this is in scope: it is reachable, it
ships, and U1 is already editing that line.

**Provenance note, because it bears on trust.** These line numbers match the ORIGINAL anomaly capture
exactly. During this spec's self-audit I "re-measured" them twice and got two different wrong answers —
first matching `.no-agy` in COMMENT prose, then matching the DEGRADED-branch check — and briefly recorded
in this document that the original numbers were stale. They were not; my greps were. The lesson for the
plan: `grep` for a bare string finds comments and fallback paths, and `head -1` silently discards the one
you want.

**The template** is the recorder's fixed shape (`agy-discipline-reaching.sh`, `b5d6742`): check the GLOBAL
opt-out first (`:53` — it does not depend on the root, so it stays cheap), then walk up for `.git`
(`:58-66`), then check **both** `$root/.no-agy` and `$cwd_path/.no-agy`.

**🔴 THE TEMPLATE INCLUDES `:49`, AND OMITTING IT MAKES THE ENTIRE FIX A NO-OP ON WINDOWS.** This is the
highest-severity finding of the panel and the one most likely to be lost in transcription.

The walk at `:62` advances with `_p=${_d%/*}`, which strips on `/` only. The recorder feeds it a
*normalized* path — `cwd_path=${cwd//\\\\//}` at `:49` — because the payload's `cwd` arrives as raw
JSON-escaped text with **doubled** backslashes. MEASURED 2026-08-05 on `{"cwd":"C:\\Users\\user\\repo\\src"}`:

| step | value |
|---|---|
| extracted, un-normalized | `C:\\Users\\user\\repo\\src` |
| `${_d%/*}` on it | `C:\\Users\\user\\repo\\src` — **unchanged** |
| loop outcome | `_p = _d` → `break` at `:63` on iteration 1 |

So a hook that gains the walk but not the normalization **resolves `root` to the cwd it started from, silently
does nothing, and still passes any test that only asserts "not suppressed from a subdirectory" by accident.**
Normalization is not a detail of the template — it is load-bearing, and **none of the eight target hooks
currently normalizes `$cwd`.** (`agy-after-reminder.sh:34` normalizes `$fp`, a different field — do not
mistake it for precedent.)

Note the normalized form is `C://Users//user//repo//src` — doubled slashes, which are benign for `[ -e ]`
and for `${_d%/*}`. **Do not "tidy" them**; collapsing them is an unrequested change to a measured-working
path shape.

**Root-idiom collision — two hooks already resolve the root, a different way.** `agy-anomaly-reminder.sh:44`
and `agy-anomaly-model-notice.sh:30` both run
`root=$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)` — *after* their `.no-agy`
check. `agy-anomaly-reminder.sh:41-43` states the reason in terms that describe U1's own defect exactly:

> *"A capturing session cd'd into a subdirectory writes to the root; if this hook looked only at the payload
> cwd it would miss an anomaly that was captured correctly."*

These two hooks already understand the subdirectory problem and already fixed it — for the anomalies-FILE
lookup, while leaving the kill-switch check above it root-blind. **For these two the correct fix is to move
the kill-switch check below the existing root resolution, not to add a second walk.** Adding the in-shell
walk would put two different root idioms in one file, and they can disagree: `git rev-parse` follows
worktrees and submodules, whereas the in-shell walk stops at the first `.git` *entry*. Also note
`agy-anomaly-model-notice.sh:9-13` claims the two halves "can never disagree", pinned by a test that compares
**counts** — a test that would not notice a `.no-agy` divergence between them.

**The check form, for every hook in the set** — three candidates, global first (cheapest, root-independent),
then the two path candidates:

```bash
[ -f "$HOME/.claude/.no-agy" ] && exit 0
if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
  exit 0            # per-hook: the SessionStart hooks announce first; see the exit-contract table
fi
```

Use the explicit `if`, matching every existing hook. The one-line `[ -f a ] || [ -f b ] && exit 0` does
work — `||` and `&&` are equal precedence and left-associative, so it groups `(a || b) && exit`, verified
by running it — but it reads as though the `&&` binds only to the second test, and this is a snippet that
will be pasted seventeen times.

Both path candidates are required, not just `$root`. Outside a git worktree `$root` falls back to `$cwd`
and the two coincide; inside one they differ, and a user may legitimately have opted out at either level.
Dropping `$cwd` would silently narrow today's behaviour while claiming to widen it.

**Deliberately NOT copied from that template: `[ -e "$root/.git" ] || exit 0`.** That guard exists because
the recorder WRITES A FILE into the user's tree and a non-repo directory has no project to attribute a row
to. Copying it would carry a guard whose reason does not apply — and would silence nine hooks in every
non-repo directory, a behaviour change nobody asked for.

**The original wording of this paragraph justified that on "these nine only emit a message", which is
false — `agy-drive-session-reset.sh` deletes files. The conclusion survives the corrected premise, but only
by a different argument, and it is worth writing down rather than inheriting.** The `.git` guard exists to
stop the recorder WRITING INTO THE USER'S TREE at a path it cannot attribute. `agy-drive-session-reset.sh`
deletes from `${CLAVITY_GOLDEN_HEADER:-$HOME/.clavity}` (`:16`) — a fixed location in the user's profile,
never a path derived from the repo root — so a non-git directory creates no unattributable write for it
either. The guard stays out for all nine; the reason for the ninth is not the reason for the other eight.

**Also NOT uniform across the 17: the exit contract.** The hooks span three lifecycle events with different
semantics, and the shared edit must preserve each one:

| event | example | on suppression |
|---|---|---|
| `SessionStart` | `agy-anomaly-reminder.sh:31`, `agy-liveness-check.sh` | stderr + `exit 2` (non-blocking here) |
| `PreToolUse` | `agy-seam-inject.sh` | stdout JSON + **`exit 0`** |
| `PostToolUse` | `agy-after-reminder.sh`, `agy-test-audit-reminder.sh` | stdout JSON + **`exit 0`** |

`exit 2` is non-blocking on `SessionStart` but **BLOCKING on `PreToolUse`** — a standing fact in this repo.
A snippet pasted uniformly across all 17 files that carries a `SessionStart` exit code into the
`PreToolUse` hook would abort the user's tool call on any box lacking `jq`. **The walk is shared; the exit
line is not.**

**And `agy-liveness-check.sh:129` must be updated with the walk, not just alongside it.** It reports the
suppressing path to the user at boot:

```bash
suppressed="$cwd/.no-agy"; [ -f "$suppressed" ] || suppressed="$HOME/.claude/.no-agy"
```

That is a two-way fallback. Once `$root/.no-agy` becomes a third way to be suppressed, this line names a
file that does not exist — it would tell the user they are suppressed by `$cwd/.no-agy` while the real
opt-out sits at the repo root. This hook's entire purpose is to say LOUDLY why the disciplines are off, so
a wrong path here is a defect in the one hook that exists to prevent confusion. Set the reported path from
whichever candidate actually matched.

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

**🔴 SEVERITY INVERSION — this hook is the most serious of the 17, and the spec had it as a footnote.**
§U1 justifies leaving these hooks unfixed until now on the grounds that *"they emit a message rather than
write a file, which is a different severity."* **That rationale does not apply here.** Measured, this hook
emits nothing and instead MUTATES DISK:

```bash
rm -f "${DIR}/.active-drive-session-${SAFE}" 2>/dev/null                                    # :21
find "${DIR}" -maxdepth 1 -name '.active-drive-session-*' -type f -mtime +7 -delete 2>/dev/null  # :25
```

A `.no-agy` bypass in the other sixteen produces an unwanted *message*. A bypass here produces an unwanted
*deletion* in a user who has explicitly opted out. It is therefore the one file in the set whose defect is
in the same severity class as the recorder's — the bug that was already judged worth fixing at `b5d6742` —
and it should be sequenced FIRST within U1, not last.

**Test shape differs from the other eight, so "the eight existing ones supply the pattern" is only half
true.** Those suites assert on emitted stdout JSON or stderr text. This hook's observable behaviour is
filesystem state. Its suite must assert: the flag file is deleted when `source=startup`; it is RETAINED when
`source=resume`; it is retained under `.no-agy` at each scope (workspace, global, and root-from-subdir); and
the `-mtime +7` sweep does not remove a fresh flag. The last is the one a copied pattern would miss, and
`:22-24` documents why it matters — an `-empty` sweep would delete a concurrent session's live flag.

**The concurrency case is not hypothetical, which raises what the `.no-agy` fix is worth here.** `:17` is
`KEY="${CLAVITY_SESSION:-${AGY_SESSION:-default}}"`, so when neither variable is set — the ordinary case —
every concurrent session on the machine shares one flag file, `.active-drive-session-default`. Combined
with the bypass in U1, a session the user has explicitly opted out of, launched from a subdirectory, will
still reach `:21` and delete the flag belonging to a **different, opted-in, running session**, which then
silently re-delivers its guidance. That is the cross-session consequence of the same one-line bug, and it
is the concrete reason this hook sequences first. The suite must cover it: with `.no-agy` at the repo root
and the payload `cwd` in a subdirectory, a pre-existing `.active-drive-session-default` must still exist
afterwards.

---

## 3. Testing

**U1** — eight suites already assert `.no-agy` suppression. Extend each with the **subdirectory scope**,
following the shape proven in `scripts/tests/agy-discipline-reaching.Tests.ps1:223` —
`It 'is SILENT under .no-agy (<Scope>) and writes nothing' -ForEach @(` — a `-ForEach` block whose data
gains a `root-from-subdir` case, so the TEST count rises without the BLOCK count changing.
(**Citation corrected in panel round 1:** an earlier draft said `:201`, which is inside an unrelated test.
`:187` is a second `-ForEach` block and is also not the one to copy.)

Each case must assert the hook is **silent** — not merely that it exits 0, which the bypass also satisfies.

**Every suppression case needs a PAIRED POSITIVE CONTROL in the same `-ForEach` data.** Silence assertions
are one-sided: a hook reduced to `exit 0` passes all of them, and so does a hook whose walk is a no-op
because normalization was omitted. Each `.no-agy` case must be accompanied by an assertion that **without**
`.no-agy` at that same scope the hook DOES fire with its specific message. Without the positive half, the
Windows no-op above ships green. This is the same defect class as the three vacuous assertions caught by
mutation in the SessionStart epic — a control that cannot fail is not a control.

**🔴🔴 THE TEST HELPER ERASES THE EXACT CONDITION THE FIX DEPENDS ON. Copying `:223` as instructed
produces a GREEN test over a BROKEN fix.** This is the most important item in this document for whoever
writes the tests, and it was found only by opening the helper.

MEASURED at `scripts/tests/agy-discipline-reaching.Tests.ps1:76`, the shared payload builder every test
routes through does this:

```powershell
$o = @{ cwd = ($Cwd -replace '\\','/'); session_id = $Sid; hook_event_name = 'SessionStart'; ... }
```

It **forward-slashes the cwd before serialising the payload.** `BashHookHelpers.ps1`'s `New-TempRepo` says
the same thing in its contract — *"Returns the dir path (Windows form); callers forward-slash it for the
payload cwd."* And the existing subdirectory case at `:236` builds its path with `Join-Path` (which yields
backslashes on Windows) only for `:76` to strip them again.

Consequences, and they are not subtle:

1. **Every existing `.no-agy` test feeds a POSIX-shaped path.** That is why the no-op above has never been
   caught — not because nobody looked, but because the harness cannot express the failing input.
2. **A `root-from-subdir` case added to the `:223` block in the obvious way inherits `:76` and therefore
   passes whether or not normalization was implemented.** It would be a fourth vacuous assertion, added by
   a spec that explicitly warns against vacuous assertions.
3. So success criterion 1 is not satisfiable through the existing helper. **At least one test per hook must
   bypass its suite's payload builder and feed a raw, JSON-escaped, backslashed `cwd`** — the shape the
   real payload has — asserting suppression still occurs. That test is the only thing standing between
   this fix and a silent no-op in production.

**It is not one helper — it is a repo-wide test convention, and that changes the instruction.** Found in
panel round 3: `scripts/tests/agy-consult-guard.Tests.ps1:19` has its own independent `Payload` function
doing the identical thing —

```powershell
function Payload { param([string]$Tool, [string]$Cmd, [string]$Cwd)
    @{ tool_name = $Tool; tool_input = @{ command = $Cmd }; cwd = ($Cwd -replace '\\','/'); ... }
```

Two suites, two separately-written builders, same normalization. So "bypass `:76`" is the wrong
instruction — **each suite has its own builder and each must be checked**, because a suite whose builder
was written the same way will mask the failure the same way. The plan must enumerate the payload builder
in every suite it touches rather than assuming one shared helper.

**Method note, because it nearly cost this finding:** a bash `grep -rn` for the `-replace '\\','/'` pattern
returned ZERO matches while the code was plainly there — the third bash-grep false zero recorded in this
repo. It was found by reading the file directly. Do not accept a bash `grep` zero as evidence of absence
when planning this work; cross-check with a different tool.

**Mutation proof for this specific case:** with the backslashed-payload test in place, remove the `:49`
normalization and confirm the test FAILS. If it still passes, the test is going through `:76` and must be
rewritten. Do not accept "the suite is green" as evidence here.

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
- **Test-suite registration is two explicit lists in `justfile`, and nothing enforces membership.**
  `justfile:101` (`test-scripts-fast`) and `:108` (`test-scripts-slow`) are hand-maintained arrays.
  **CORRECTION (panel round 1, measured):** an earlier draft said an unregistered suite "exists and never
  runs" — that is false. `justfile:112` (`test-scripts`) runs `Invoke-Pester scripts/tests`, a **glob**, so
  an unregistered suite does run there. The true hazard is narrower and worse: it runs in **neither gate
  this spec actually names in §3**, while `just test-scripts` reports it green — and per the standing
  cadence note the whole-suite recipe exceeds the 600s cap and is not routinely run. So the suite is green
  in the recipe nobody runs and absent from the two everybody runs.
  The only detector is the `diff` oracle documented at `scripts/tests/_partition.md:53-54`, and **no test
  invokes it** — `grep -rln justfile scripts/tests/*.Tests.ps1` returns nothing. It is a manual command in a
  Markdown file. **U4 must state which list it joins** (`test-scripts-fast`, on the peer's reasoning that it
  touches filesystem flags without heavy analysis) and the plan must run that oracle by hand.
- **`_partition.md` must be re-measured**, not hand-edited, after the suites change. It was wrong in both
  columns for two commits precisely because nobody re-measured.

---

## 6. Success criteria

1. All 17 files honour `.no-agy` at the repo root from a subdirectory, **on a Windows-shaped `cwd`** (the
   normalization above; a test using a POSIX path cannot detect the no-op), each pinned by a test that
   fails when the guard is reverted **and** by a positive control that fires when it is absent.

   **How the 17 are actually covered — state it, do not leave it implied.** MEASURED: 8 suites bind the
   **dotnet** copies; only 4 bind classic, and 5 classic copies (`agy-anomaly-capture-reminder`,
   `-dispatch-reminder`, `-model-notice`, `agy-anomaly-reminder`, `agy-liveness-check`) have no suite of
   their own. They are covered **transitively**, by `scripts/check-seed-artifacts-synced.sh` proving byte
   parity with the dotnet copy it tests — that script discovers files under the shared trees rather than
   reading an enrolment list (`:15`, `:63`), and exempts `agy-drive-session-reset.sh` as classic-only
   (`:29`). That is a sound argument, but the spec had not made it, and "each pinned by a test" read
   literally would send an implementer to write 5 unnecessary suites. **Direct test + parity gate = covered;
   `agy-drive-session-reset.sh` has no parity pair and so needs its own suite — which is U4.**
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
| `[ -e "$root/.git" ] \|\| exit 0` in the nine hooks | The guard's reason does not apply; would silence them in every non-repo directory. **Not** because "they only emit a message" — that is false of `agy-drive-session-reset.sh`; see §U1 for the corrected argument |
| `path-scan.iss` / `ClassicClavityOnPath` unification | Intentional duplication, roster correctly scoped, installer refactor before a release is unjustified risk |
| The ECC hook tax | Does not ship in this artifact; owner config decision |
| ME1 async attribution, the MCP signal bus, `clavity ring` | Already documented as out of scope in `lib.sh:17-21`; unchanged by this work |

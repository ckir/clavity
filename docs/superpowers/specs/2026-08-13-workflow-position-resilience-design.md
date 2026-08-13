# Workflow-position resilience - surviving a session death

**Status:** design, owner-approved 2026-08-13. Ships with the plugin to end-user machines.
**Replaces:** the POWER-FAILURE sections 9/9a of `2026-08-13-agy-policy-gate-implementation-spec.md`,
which are marked DO-NOT-BUILD and retained there only as input.

**This is a new design, not a productisation.** The owner rejected that label, correctly: moving the
personal hook would have kept its mechanism, and every part of that mechanism changed.

---

## 1. The problem, stated precisely

A session dies without warning - power cut, box reset, context loss. A fresh session must resume the
work. The question is what it needs that it cannot already get.

**Git holds the past.** `git log` gives what landed, `git status` gives what is dirty, `git stash list`
gives stashes. None of that needs saving.

**What git cannot hold is workflow POSITION.** A review round reads code and produces findings; it makes
no commit. So a four-round review is invisible to git. The existing `.clavity/agy-marks/<name>.head`
markers do not help: each is a bare 40-character SHA meaning *this discipline COMPLETED at this commit*.
There is no representation of "in progress, round 5".

**What we are NOT solving.** Transient execution facts - running processes, gateways up, live peer
request or cascade ids - are worthless after a restart, because the processes are dead and the ids name
a session that no longer exists. Recording them produces a file whose contents are guaranteed false by
the time anyone reads it. Owner ruling, and it removed most of an earlier draft.

**Also not solving: knowledge retention.** Owner rulings, rejected approaches, chosen options are
durable and must survive the work landing; workflow position is transient and must not. One artifact
cannot carry both, because clearing it would destroy the decisions and never clearing it would turn the
resume state into a graveyard. This spec covers only the transient half. The durable half stays wherever
the host already keeps it, and we ship no competitor to it - which is what would have created the
two-index problem this design was accused of creating.

## 2. The measurement that decided the design

Two mechanisms, same agent, same repository, full history:

| mechanism | artifacts produced |
|---|---|
| **seam files** - the agent cannot consult the peer without writing one | **434** agent-written (536 total, of which 102 are peer-written replies) |
| **plan checkboxes** - the agent is asked to tick one as each step completes | **0 ticked**, out of **1,233**, across **27** plan files |

Zero. Not once, in any plan, including plans that were executed to completion.

**Verify before trusting either number.** The tick count was first measured with `^- \[x\]`, which cannot
see an indented or capital-`X` checkbox; re-measured with `^[[:space:]]*[-*] \[x\]` case-insensitively,
against a fixture containing a known indented capital-`X` tick to prove the pattern can find one. The
control passes and the count is still zero.

### 2a. The causal claim, and it is not the obvious one

The obvious reading is *structural writes beat administrative ones*. That is close but wrong, and the
difference matters:

> **Measured: nothing anywhere reads a ticked checkbox** - no shipped hook, no skill, no script. A tick
> buys nothing for anyone, ever. A seam buys an answer from the peer *immediately, for the current
> session*.

**The variable is whether the write has a CONSUMER, not whether it is forced.**

**Therefore the design principle:** *harvest state the current session already had to produce for its own
reasons; never create state whose only beneficiary is a successor who may not exist.*

**And its falsifier, stated so it can be checked later:** if we ever add a field that only a successor
reads, that field is a checkbox and it will be empty. Anything this design asks anyone to write *for the
crash* is already on the path to zero.

## 3. The design

**The seam file IS the workflow-position record.** No new artifact, no index, nothing to maintain. The
agent must write a seam to consult the peer at all, so the record exists whenever a consult happened -
which is exactly when a multi-round discipline is mid-flight.

### 3a. The filename carries discipline and round

The reader needs to say *which* discipline and *which* round. That must come from the filename, because
parsing seam prose is exactly the fragility this project has already rejected elsewhere.

**Convention: `<discipline>-r<N>-<topic>.md`**, e.g. `agy-capstone-r5-a2-audit.md`. Replies keep the
existing `-REPLY` suffix.

This is a free rider on a decision the author must make anyway - the file needs *a* name - so it adds no
step to remember. It is not free of error, and section 5 covers what happens when it is wrong.

### 3b. SessionStart surfaces EXISTENCE and AGE. Never CONTENT.

One line per open seam:

```
workflow position: agy-capstone r5 (.clavity/seams/agy-capstone-r5-a2-audit.md), written 4 commits ago
```

**It must never inject the seam's body into the context.** A single abandoned review would otherwise
poison the startup of every future session with a ghost, permanently. Naming the path lets the agent
read it deliberately if it is relevant; injecting the content decides that for it, forever. This mirrors
the ruling already made for the policy gate's block message: point at the file, do not inline it.

**Age is expressed in commits, not time.** A wall-clock age cannot distinguish a long weekend from an
abandoned branch; commit distance measures how much work has happened since, which is the thing a reader
actually wants to weigh.

### 3b-0. The CANDIDATE SET is seams newer than the newest discipline marker

**Found by this spec's own panel, and it would have killed the mechanism.** The reader must not consider
every seam on disk. Measured on this repository: **434 agent-written seams exist, and only 25 match the
naming convention below** - 5.8%. Under section 5's "report, never skip" rule, a first run would have
announced three seams and *"406 more unrecognised"*. That is noise, and noise trains a reader to ignore
the line - the checkbox outcome reached by a different road.

> **The reader considers only seams NEWER than the most recent file in `.clavity/agy-marks/`.**

Measured with the same command the hook will use: **11 candidates, 423 filtered out**, with a control
confirming the predicate varies (a 2020 reference matches all 536). Historical seams age out on their
own, with no migration, no cleanup, and no convention applied retroactively.

**Section 5's "never skip" rule is scoped to THIS candidate set**, not to the whole directory. An
unparseable name among live seams is still reported; a three-month-old seam is simply not a candidate.

### 3b-i. The reference point is the seam's MTIME - the design stores no SHA

The self-audit caught this: an earlier draft's rules referred to "the seam's own SHA", but the filename
convention stores no SHA and nothing else records one. Both the age report and the conclusion test need
a reference point, and **asking the author to write a SHA into the seam would be writing for the
successor - which section 2a says goes to zero.**

**Use the file's mtime.** It costs nobody anything, because the filesystem records it whether we ask or
not - the same free-rider logic as the filename.

- **age in commits:** `git rev-list --count --since="<seam mtime>" HEAD`
- **concluded?** the discipline's marker file is newer than the seam - `[ "$marker" -nt "$seam" ]`

Verified on this repository: `date -r` yields the mtime, the `--since` count returns 0 for a seam
written after the last commit and 1334 for a 2020 baseline (so the counter genuinely varies rather than
always returning the same number), and `-nt` correctly reports the existing capstone marker as OLDER
than a seam written today.

**Named dependency, checked rather than assumed:** the age report uses `date -r`, which is GNU. Measured
here, `date` resolves to `/usr/bin/date` - GNU coreutils 8.32, which Git Bash ships by default - so this
is not an author-machine assumption, and a panel seat that suspected one was wrong. The conclusion test
needs no `date` at all: `[ "$marker" -nt "$seam" ]` and `find -newer` are POSIX test primitives.
**If `date -r` fails anyway, degrade: report the seam without its age.** Never drop the seam because a
decoration could not be computed.

**Stated limitation:** mtime is not preserved by copy or clone, and a `touch` resets it. That is
acceptable precisely here - `.clavity/` is gitignored, never cloned, and purely local runtime state,
which is the one domain where mtime is dependable. If that ever stops being true, this rule breaks
silently, so the test row pinning the `-nt` comparison is what would catch it.

### 3c. NOTHING infers abandonment. No TTL, no auto-delete.

An earlier proposal expired a seam once `HEAD` moved past the SHA it was written at, reasoning that a
moved `HEAD` meant the human had moved on.

**Refuted by counter-example from the session that produced this spec.** Commits `5ca879b` and `940be82`
are the round-3 and round-4 *fold* commits of a review that was still live. **In a multi-round review,
folding findings between rounds IS committing** - a moved `HEAD` is evidence of progress, not
abandonment. That rule would have deleted the live review immediately after round 3.

The peer conceded the general point on re-derivation: **abandonment is a cognitive state that leaves no
exhaust.** A paused review and an abandoned one are mechanically identical.

**And the costs are asymmetric.** A wrong "still live" is one line in a startup message that a reader
ignores. A wrong "abandoned" destroys the only record of where the work was - the precise thing this
design exists to preserve. **Never take the destructive action on an inference.**

**Clearing is therefore explicit and human-or-discipline driven**, never automatic:
- a discipline that COMPLETES writes its `.clavity/agy-marks/<name>.head` marker as it already does;
  a seam whose discipline marker is NEWER than the seam (3b-i) is CONCLUDED and is not surfaced.
- anything else stays surfaced until someone deletes it. Being nagged about a dead review costs a line;
  the alternative costs the work.

## 4. What we do NOT build

- No `.clavity/session.state`, no WAL, no resume file of any kind.
- No shipped index of decisions, and no nudge to maintain one.
- No `PostToolUse` hook on commits. The earlier draft had one; it detected commits by grepping the
  command text, which imported an assumption about a command-rewriting wrapper on the author's machine.
  Nothing here needs to detect a commit at all.
- No competitor to whatever durable knowledge store the user already has.

**The entire build is a SessionStart reader plus a naming convention.**

## 5. Failure modes, each with what it costs

| failure | what happens | cost |
|---|---|---|
| the author names a seam off-convention | the reader cannot parse discipline or round | **it must degrade, not vanish**: report `an unrecognised seam exists (<path>), written N commits ago`. Never silently skip - a skipped seam is an invisible loss |
| a review is genuinely abandoned | the seam is surfaced forever until deleted | one line per session. Accepted, by the asymmetry in 3c |
| many seams accumulate | the startup line becomes a wall | cap the report at the **3 most recent unconcluded** seams and state the count of the remainder. A cap that is silent is a lie; the count must be printed |
| the successor is told a seam exists and does not read it | resume is no better than today | accepted: this is a floor, not a guarantee. The seam's primary consumer remains the peer, which is what keeps it written at all |
| the user uninstalls the plugin | seams remain in `.clavity/`, unread | harmless: gitignored runtime state, no residue outside the directory |

## 6. Build surface

| artifact | why |
|---|---|
| an existing SessionStart hook, both products | the reader. Extend one rather than add another script |
| `clavity-*/plugin/skills/*/SKILL.md` for the multi-round disciplines | state the seam naming convention where the seam is written |
| `scripts/tests/<name>.Tests.ps1` | every hook here has its own suite |
| `justfile` | suite registration is an explicit list, not a glob |
| `scripts/tests/_partition.md` | a measured row; the census gate reds the suite if omitted |

**The reader must assert the `.clavity/.gitignore` shield** (`[ -f ... ] || printf '%s\n' '*' >> ...`)
before any write, on every invocation, exactly as `open-issues/SKILL.md:79` does. It writes nothing
today, but it will run in a stranger's repository where `.clavity/` is not ignored unless the shield
exists.

## 7. Tests - every row names the mutant that reds it

| row | mutant that must red it |
|---|---|
| an unconcluded seam is reported with discipline and round | remove the filename parse -> row reds |
| the report names the PATH and does NOT contain the seam's body | inline the content -> row reds |
| a seam whose discipline marker is NEWER than it is NOT reported | drop the marker check -> row reds |
| a seam NEWER than its discipline marker IS reported | invert the `-nt` comparison -> row reds. Pins the direction, which a one-sided row would not |
| **a seam is still reported after HEAD has moved** | add a HEAD-based TTL -> row reds. This pins the 3c refutation |
| an off-convention filename is reported as unrecognised, not skipped | skip on parse failure -> row reds |
| more than 3 open seams reports 3 plus a remainder count | cap silently -> row reds |
| age is reported in commits | switch to wall-clock -> row reds |
| no seams at all produces NO output | emit an empty header -> row reds |
| the hook exits 0 when `.clavity/` does not exist | fail on a missing directory -> row reds |
| the shield is asserted before any write | remove the assertion -> row reds |

## 8. Self-audit

**Closed in-document:** the earlier draft's transient-facts store (removed, section 1); its commit-
detection hook (removed, section 4); the HEAD TTL (refuted with a counter-example, 3c); the "structural
vs administrative" framing (corrected to consumer-vs-no-consumer, 2a).

**Resolved at plan time, each with a home:**

| gap | where |
|---|---|
| which SessionStart hook is extended, per product | plan - dotnet and classic have different SessionStart sets |
| the exact filename regex, including a Windows-path case | plan, pinned by the off-convention test row |
| whether `-REPLY` files are ever reported | plan - they are peer output, so probably not, but it is reachable and should be an explicit row |
| which disciplines are multi-round enough to need the convention | plan - capstone and panel certainly; first and test-audit are single-shot |

**Known and accepted, not gaps:** this is a floor, not a guarantee (5); a seam's primary consumer stays
the peer, and that is deliberate (2a); abandonment cannot be detected (3c).

**Requirement coverage:** owner ruling that the discipline owns both halves -> the write half is the
seam, already structural (3), and the read half is the SessionStart reader (3b). Owner ruling that
transient facts are worthless -> section 1. Owner's question "how does a new session know it is at
capstone R5" -> 3a and 3b answer it directly.

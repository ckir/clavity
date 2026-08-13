# Workflow-position resilience - surviving a session death

**Status:** design, 2026-08-13. Ships with the plugin to end-user machines.
**The NAME is DEFERRED TO PLAN TIME, gated on a measurement** (owner ruling, 2026-08-13). It is not
renamed now, because whether "power-failure" is honest depends on a probe that has not been run -
deciding first would be guessing. **Nothing else blocks this spec.** The decision rule is in 3g.
**Replaces:** the POWER-FAILURE sections 9/9a of `2026-08-13-agy-policy-gate-implementation-spec.md`,
which are marked DO-NOT-BUILD and retained there only as input.

**This is a new design, not a productisation.** The owner rejected that label, correctly: moving the
personal hook would have kept its mechanism, and every part of that mechanism changed.

---

## 1. The problem, stated precisely

A session dies without warning - the process is killed, the box resets, context is lost. A fresh session
must resume the work. The question is what it needs that it cannot already get.

**Scope of the claim, stated up front because section 3e narrows it twice:** this design addresses
**session death**, not **power loss**, and it covers **consult-driven work**, not implementation. Both
limits are traced in 3e. Do not read the title as a broader promise than that.

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

**The `<discipline>` token is a CLOSED list, and it is the marker's basename - not free prose.** The
round-1 panel found this, and without it the design's only clearing mechanism can never fire:

> **Measured on this repository: 27 seams already match the shape `<something>-r<N>-<topic>.md`, and
> ZERO of their 8 distinct prefixes map to any marker file.** Authors wrote `capstone-stage2`,
> `capstone-injected`, `sp2-capstone`, `python-gate-plan-review`, `drain-knowledge-panel-agy` - all
> natural, all unresolvable. The markers on disk are `agy-capstone`, `agy-first`, `agy-test-audit`.

So an unconstrained token is not a convention, it is a wish. The permitted tokens are exactly the marker
basenames, and the conclusion test in 3b-i resolves `<token>` to `.clavity/agy-marks/<token>.head` by
string equality with no normalisation:

| token | marker | multi-round? |
|---|---|---|
| `agy-capstone` | `agy-capstone.head` | yes - the primary case |
| `agy-panel` | `agy-panel.head` | yes - **the marker does not exist yet; see section 6** |
| `agy-test-audit` | `agy-test-audit.head` | rarely, but it can re-round after a refactor |
| `agy-first` | `agy-first.head` | no - single-shot, listed so the token resolves if used |

Anything else is an off-convention name and takes the degrade path in section 5. The example above is
correct precisely because `agy-capstone` is a marker basename; a plausible-looking `capstone-r5-x.md`
is NOT.

**Two implementation rules that are NOT plan-time latitude, because round 2 showed both forks produce
wrong behaviour:**

- **The token list is the LITERAL table above - never derived from what is in `.clavity/agy-marks/`.**
  An implementer who enumerates the directory instead will not find `agy-panel.head` on a fresh install
  (it is written only when a panel first completes), so every panel seam would silently take the
  off-convention branch on exactly the machines that most need it to work. The table is the contract;
  the directory is state.
- **Extraction is a single anchored full-match, never a prefix or fuzzy match.** The name must match
  `^(<token>)-r([0-9]+)-.+\.md$` in full, with `<token>` an alternation of the table's literal values.
  `agy-capstone-stage2.md` therefore does NOT resolve to `agy-capstone` - it has no `-r<N>-` segment and
  is off-convention. A parser that greedily extracts a leading token would conclude a live seam against
  a marker that was never about it, and the section 7 row pins this direction.

### 3b. SessionStart surfaces EXISTENCE and AGE. Never CONTENT.

One line per open seam, **and it must carry a DIRECTIVE, not only a fact**:

```
workflow position: agy-capstone r5 (.clavity/seams/agy-capstone-r5-a2-audit.md), written 4 commits ago.
Read that seam before starting new work, or say why you are not resuming it.
```

**Why the second sentence exists.** The round-1 panel's Mechanism Gamer argued the whole design is
theatre: it surfaces the state, satisfies its own success criterion, and produces zero resumptions,
because a model does not autonomously open a path printed in its startup context.

**Its conclusion is overstated and this session refutes it, but the residue is real and cheap to fix.**
Measured here: the shipped anomaly hook's `SessionStart` line - *"3 untriaged in
`.clavity/local-anomalies.md`. Triage before new work via the open-issues skill"* - **did** cause the
file to be opened before any other work this session. So a startup line demonstrably can drive action.
**The difference is that it carries an imperative.** The declarative line first drafted here ("workflow
position: ... written 4 commits ago") states a fact and asks for nothing, and it is the version the
Gamer's objection actually lands on.

This costs one sentence, so there is no reason to ship the version the objection kills.

**It must never inject the seam's body into the context.** A single abandoned review would otherwise
poison the startup of every future session with a ghost, permanently. Naming the path lets the agent
read it deliberately if it is relevant; injecting the content decides that for it, forever. This mirrors
the ruling already made for the policy gate's block message: point at the file, do not inline it.

**Age is expressed in commits, not time.** A wall-clock age cannot distinguish a long weekend from an
abandoned branch; commit distance measures how much work has happened since, which is the thing a reader
actually wants to weigh.

### 3b-0. The CANDIDATE SET is decided PER SEAM, never by one global cutoff

**Found by this spec's own panel, and it would have killed the mechanism.** The reader must not consider
every seam on disk. Measured on this repository: **434 agent-written seams exist, and only 25 match the
naming convention's SHAPE** - 5.8%, and per 3a **none of them match its closed token list**. Under
section 5's "report, never skip" rule, a first run would have announced three seams and *"406 more
unrecognised"*. That is noise, and noise trains a reader to ignore the line - the checkbox outcome
reached by a different road.

The first draft of this rule was **one global cutoff** - *"only seams newer than the most recent file in
`.clavity/agy-marks/`"*. The round-1 panel killed it, and the measurements below are why. It is replaced
by a **per-seam** rule.

> **The candidate rule, evaluated per seam:**
>
> 1. **A `-REPLY` file is never a candidate.** It is peer output, not a position record.
> 2. **If no `*.head` marker exists at all**, every remaining seam is a candidate. Nothing has ever
>    concluded, so nothing can be aged out.
> 3. **If the filename's discipline token is in the closed list (3a)**, the seam is a candidate unless
>    its OWN marker `.clavity/agy-marks/<token>.head` is newer than it. No other discipline's marker
>    can conclude it.
> 4. **Otherwise** (off-convention name), the seam is a candidate if it is newer than the newest
>    `*.head` marker **OR is among the 10 most recent seams by mtime**. The first clause ages out the
>    historical corpus; **the second is what stops a mistyped LIVE seam from being destroyed, and
>    without it rule 4 reintroduces the exact bug this rewrite exists to fix.**

**Three measured defects in the global cutoff, each fatal on its own:**

- **It let one discipline conclude another's live work.** On this repository right now,
  `agy-first.head` (2026-08-13 01:41:58) is **five hours newer** than `agy-capstone.head`
  (2026-08-12 20:29:33). Any capstone seam written in that window is silently dropped from the
  candidate set while the capstone is still unconcluded. **That is the destructive action on an
  inference that 3c forbids**, committed by the design's own filter.
- **`skipped.log` is a file in `.clavity/agy-marks/`, and the global rule counted it.** It is not a
  marker: agy-first appends to it precisely when a consult is SKIPPED and deliberately writes no
  marker, so the discipline re-fires. Under the old rule a recorded NON-completion advanced the cutoff
  and aged out live seams. **Rule 4 reads `*.head` only** - never every file in the directory.
- **It was unspecified when the directory is empty or absent, and both concrete forms misbehave.**
  Measured: with the directory absent, the filter errors -
  `find: '/tmp/pv2/marks/': No such file or directory`. With it present but empty, the argument
  degenerates to the directory itself and `find` silently uses the DIRECTORY's mtime as the cutoff -
  an arbitrary timestamp that still excluded an older seam in a control where one existed. Neither is
  the intended "nothing has concluded". **Rule 2 states it outright.**

**Round 2 found the rewrite had left the same bug alive in its own rule 4, and it is measured:**

```
seams/capstone-r5-live.md   <- a LIVE seam, mistyped (no agy- prefix) -> rule 4 branch
marks/agy-test-audit.head   <- an UNRELATED discipline completes one second later
-> newer than the newest *.head marker?  NO - SILENTLY DROPPED
   CONTROL: a correctly-named seam survives via rule 3   -> candidate
```

A typo is not an exotic input; it is the single most likely author error, and section 5 exists
precisely because off-convention names happen. **So the population rule 4 governs is the one population
that is definitionally the result of a mistake, and the first draft of rule 4 destroyed its live members
silently** - the same cross-discipline destruction, reached by a different road. The `10 most recent
seams` clause closes it: measured on the same fixture, the mistyped live seam sits at position 4, so any
small cap keeps it. What it still cannot save is a mistyped seam with ten newer seams written after it,
which requires enough subsequent work to be real evidence of moving on.

**Rule 2's honest limit, also from round 2.** It assumes an empty marker directory means a fresh
repository. A user who runs consults for weeks without ever completing a discipline has seams and no
marker, so every one stays a candidate and the remainder count grows. That is bounded rather than fixed:
section 5 caps the report at 3 and prints the count. **It is also self-limiting in practice** - a single
completed `agy-first` consult writes a marker, and that is the most frequent discipline here.

**What the rule still buys, and what it does not.** The noise problem it was invented for is real:
measured today, **28 of 549 seam files are candidates, and only 2 of the 28 match the convention**, so a
first run would report 3 and *"25 more unrecognised"*. Rule 1 removes the 14 `-REPLY` files from that
count immediately. The rest age out as markers advance past them, with no migration, no cleanup and no
convention applied retroactively - but **be honest that this shrinks the noise rather than eliminating
it**, and that the cap in section 5 is what bounds it in the meantime.

**Section 5's "never skip" rule is scoped to THIS candidate set**, not to the whole directory. An
unparseable name among live seams is still reported; a three-month-old seam is simply not a candidate.

### 3b-i. The reference point is the seam's MTIME - the design stores no SHA

The self-audit caught this: an earlier draft's rules referred to "the seam's own SHA", but the filename
convention stores no SHA and nothing else records one. Both the age report and the conclusion test need
a reference point, and **asking the author to write a SHA into the seam would be writing for the
successor - which section 2a says goes to zero.**

**Use the file's mtime.** It costs nobody anything, because the filesystem records it whether we ask or
not - the same free-rider logic as the filename.

- **age in commits:** `git rev-list --count --since="@$(date -r "$seam" +%s)" HEAD`
- **concluded?** the seam's OWN discipline marker is newer than it - `[ "$marker" -nt "$seam" ]`, where
  `$marker` is `.clavity/agy-marks/<token>.head` for the token parsed in 3a, and **no other file**. If
  that marker does not exist, the seam is not concluded.

**The date is passed as `@<epoch>`, never as `date -r`'s default output.** The round-1 panel's
Dependency Cynic claimed the default output would be misparsed under a non-C locale. **That mechanism
did not reproduce here** - measured, `date -r` prints `Thu Aug 13 16:01:08 GTBDT 2026` and git parses
it to exactly the same answer as the epoch form (both `1`), with a control that discriminates (a 2020
reference gives `1341` in both forms, 2030 gives `0`). So the claim as stated is refuted on this box.

**What survives the refutation is worse, and it is why the fix is adopted anyway:** `git` never errors
on a date it cannot parse. Measured, `--since="zzz not a date zzz"` returns `0` and
`--since="Do 13 Aug 2026 10:15:00 CEST"` returns `1` - both plausible numbers, silently wrong, on a
zero exit code. There is no signal to detect. Since `+%s` is locale-independent, costs nothing, and
was measured to agree with the current form, shipping the form that *can* fail silently would be
choosing the riskier of two equal-cost options.

Also verified on this repository: `-nt` correctly reports the existing capstone marker as OLDER than a
seam written today.

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

**Editing a concluded seam resurrects it, and that is the acceptable direction.** Round 2 raised this
as state corruption "irreversibly destroying the one-way transition". **The mechanism is real and the
severity is not** - measured on a fixture:

```
1. after the discipline completes   -> concluded
2. after a human edits the seam     -> RESURRECTED (candidate again)
3. after the next completion        -> concluded again  ->  REVERSIBLE
```

So it is not one-way and nothing is destroyed. A resurrected dead review costs **one line in a startup
message**; the opposite error - concluding a live seam - costs the record of where the work was. 3c
already ruled on exactly that asymmetry, and this lands on the side it chose. **It is written down
rather than fixed, because the fix (a marker that records which seam it concluded) is a new field whose
only reader is a successor**, which section 2a says goes to zero.

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
  a seam whose OWN discipline marker is NEWER than the seam (3b-i) is CONCLUDED and is not surfaced.
- anything else stays surfaced until someone deletes it. Being nagged about a dead review costs a line;
  the alternative costs the work.

**This is the design's ONLY clearing mechanism, so a discipline with no marker can never clear.**
Measured: markers exist for `agy-capstone`, `agy-first` and `agy-test-audit`, and **the panel
discipline writes none at all** - `adversarial-panel-review` has no debounce-marker contract, unlike
its two siblings. A panel is the most multi-round discipline here, so every panel seam would be
surfaced forever and the section 5 cap would carry a permanently growing remainder. **Section 6 carries
the fix, and it is a change to a shipped skill rather than to this reader.**

**One clearing failure is accepted rather than fixed, and it is stated because 3c's own rule condemns
it.** If two sessions run the SAME discipline concurrently, the first to finish writes the marker and
the second's live seam is instantly "concluded" - a destructive action taken on an inference, which is
exactly what this section forbids. It is not fixed because the honest fix is a per-session marker, and
that is a new artifact whose only reader is a successor: section 2a says it goes to zero. **It
self-heals on the next round**, because that round writes a newer seam. The unrecovered case is a crash
in the window between the other session's marker and the next seam. Two sessions on one repository is
ordinary here; two running the same discipline at once is not.

## 3d. The ANNOUNCED ending - PreCompact, and why the agent cannot help

A session ends one of two ways, and section 3 covers only one of them.

| ending | today |
|---|---|
| **unannounced** - the session dies | the seam, harvested for free (3, 3a-3c) - **for consult-driven work only, and not against power loss; see 3e** |
| **announced** - the human compacts | **nothing.** `PreCompact` fires exactly one hook, the anomaly reminder, and **no shipped hook mentions the index at all** |

**The owner's observation, which started this section:** typing *"I will /compact then continue. Are you
ready?"* reliably produces correct state capture, and **without the question it does not**.

**My explanation was wrong, and the panel's Mechanism Gamer objection killed it.** I proposed that a
question forces verification where a statement invites acknowledgement. But a model can answer "yes"
without checking anything, so grammar cannot be the mechanism.

**The real mechanism: the question grants a conversational TURN.** It is a turn allocator, not an
interrogation. The agent needs a turn to run `git status`, read the index and write to it; a question
creates one, and a bare statement followed immediately by `/compact` does not. That explains the
observation exactly, and it has a consequence the original idea did not survive:

> **A hook cannot yield a turn to the agent.** It injects context and the session proceeds. So any
> `PreCompact` design that depends on the AGENT gathering state is structurally impossible - the agent
> is paralysed for the entire window. **Do not port the question into a hook; it would be swallowed in
> silence.**

**What survives is the second half of the idea.** At `/compact` the successor is guaranteed and seconds
away, which satisfies section 2a's consumer rule exactly - this is the one boundary where writing for a
successor is not a checkbox. **So the HOOK gathers the state itself**, reusing the candidate-set and
mtime logic already specified in 3b-0 and 3b-i, and emits the active seam's path and age.

**Hard constraint, measured, and it would have broken the naive implementation:**
`agy-anomaly-capture-reminder.sh:13-14` records that **`hookSpecificOutput` is INVALID for `PreCompact`**
- Claude Code rejects the payload outright and the user sees a schema-validation dump instead of the
message. **PreCompact must emit a top-level `systemMessage`.** That is prior art already paid for in this
repository; do not rediscover it.

**Honest limit on what this can claim.** Whether the compaction summariser *consumes* the message is not
verifiable from here, and a design that depended on that would be asserting something it cannot check.
It does not need to: **measured in this session, a `PreCompact` `systemMessage` reaches the continuing
post-compact context** - the anomaly reminder's text arrived intact after compaction. So the new session
sees the seam path whether or not the summariser cooperates, which is the more robust of the two paths.

**A note worth passing to the human rather than burying:** since the mechanism is the turn and not the
question, *any* message before `/compact` grants it. The habit that works is "give the agent one turn
before compacting" - the phrasing is incidental.

**But that note must ship with its precondition, or it is a placebo.** The round-1 panel's Blindspot
Auditor is right: **a turn is only worth something if the agent has somewhere durable to write.** The
author's host provides one; a stranger's may not, and this spec deliberately ships no index (section 1).
On a bare host the extra turn produces an agent saying "ready" and writing nothing - a habit that feels
protective and is not.

**So the turn is an OWNER-side bonus, never the stranger's protection.** What protects the stranger is
the hook path above, which gathers the state itself and needs no habit, no phrasing and no host memory
store. **Any documentation of the habit must say which of the two it is**, otherwise it teaches a
stranger to rely on the half that does not work for them.

## 3e. Does this actually survive a crash? Traced, not assumed

**Answer: for consult-driven work, yes. For implementation work, NO - and that is the design's real
hole, stated here rather than discovered later.**

**The path that works.** A crash writes no marker, because `.clavity/agy-marks/<name>.head` is written
only when a discipline COMPLETES. So a seam from an interrupted review is necessarily newer than the
newest marker, which makes it a candidate under 3b-0. The next session starts (`SessionStart` matcher
`startup`), the reader names the seam and its age, and the agent gets a turn on the human's first
message in which to read it. Every link in that chain holds.

**The hole, measured: 435 of 435 agent-written seams are consult payloads.** A seam is *by definition*
what an agent writes to ask the peer something. **A session that edits code, runs tests and commits -
with no consult - produces no seam at all.** After a crash the successor gets git, which says what
landed, and nothing that says which task was in flight. The plan's checkboxes cannot fill that hole
either: 0 ticked out of 1,233.

**This is not fixable by trying harder.** Implementation work has no structural artifact to harvest - no
write the agent must make for its own immediate reasons - so any record of "which task am I on" would be
written purely for a successor, which section 2a says goes to zero. **Inventing one would reproduce the
checkbox.** The honest position is that this design covers reviews and not implementation, and that the
implementation case needs a different idea rather than a bolted-on field.

**Two further limits, both real:**
- **Process crash versus power cut.** A seam already written and closed survives a process death. A
  seam written seconds before a POWER cut may still sit in the OS buffer and be lost - the file is
  written by the host's tooling, which this design does not control, so it cannot force an `fsync`. The
  earlier WAL proposal carried an explicit `sync` for exactly this reason; that guarantee went away with
  the WAL. **Superseded in part by 3f: the peer found a hook surface that could carry a flush, so this
  may be closable - but its proposed mechanism failed measurement and the fix is unproven. Until the
  probe named in 3f exists, this limitation stands as written.** **Claim resilience against session
  death, not against power
  loss.**
- **Durable decisions are out of scope by design** (section 1). On a machine with no host memory store,
  a crash loses every owner ruling and rejected approach made in that session. This design does not
  address that and must not be read as if it does.

## 3f. Peer review of the limitations - what survived measurement

The three limitations in 3e were put to the peer with instructions to attack them. Its dispositions,
each checked before folding.

**Limitation 1, the implementation gap - CONFIRMED as an accepted hole.** The peer went looking for a
structural artifact in implementation work and reports finding none that encodes workflow position:
modified source shows the result, not the position in the plan. It agrees that demanding a declaration
recreates the checkbox. No change.

**Limitation 2, power loss - finding accepted, FIX NOT ADOPTED.** The peer correctly identified that a
`PostToolUse` hook on `Write|Edit` already exists (`hooks.json:25`) and could carry a flush. **But its
mechanism failed on measurement:**

```
sync -d <a file I own, just created>   ->  sync: error syncing '...': Permission denied
sync -d <a path that does not exist>   ->  sync: error opening '...': No such file or directory
```

The control distinguishes the two, so the `Permission denied` is real and not a probe artifact: **the
cheap per-file forms (`-d`, `-f`) do not work here.** Bare `sync` exits 0, but an exit code is not
evidence that data reached the disk, and the peer asserted the flush without testing it. Its cost claim
("negligible") is likewise unmeasured - a system-wide `sync` after every agent write blocks on every
filesystem and affects unrelated processes.

> **Plan-time item, with the measurement it requires:** before adopting any flush, prove that bare
> `sync` actually flushes on this platform - not that it exits 0 - and measure its cost under a
> concurrent build. **Until that probe exists, section 3e's power-loss limitation stands.**

**Limitation 3, durable decisions - the peer's FINDING is right and its FIX contradicts its own
reasoning.** It calls the omission fatal: a stranger installing something advertised as POWER-FAILURE
RESILIENCE reasonably expects a crash not to vaporise the session's decisions, and *"the user does not
distinguish between 'the agent forgot what round it was on' and 'the agent forgot we decided to drop
Redis'"*. **That is correct, and it is the same class of defect the owner caught when he rejected the
word "productisation": a name that promises more than the mechanism delivers.**

Its proposed remedy - ship a durable index plus *"a mechanism to enforce its use"* - **is the checkbox it
had just declared unbuildable four paragraphs earlier**, where it wrote that any mechanism demanding a
declaration is administrative and will not be complied with. An enforced decisions-index has no
structural consumer and would land at 0 out of 1,233 exactly like the plan checkboxes.

**So the remedy is the other option it offered: rename.** This mechanism recovers interrupted CONSULTS.
It does not survive power loss, does not cover implementation, and does not retain decisions. **A name
that says so is free; a mechanism that delivers the promise is not.**

**The owner has since ruled the name DEFERRED to plan time and gated on a measurement (3g), so it no
longer blocks this spec.** Note what that defers and what it does not: the power-loss overclaim is a
live empirical question, but the other two - implementation coverage and decision retention - are
settled permanently against this mechanism, so even a successful probe yields a narrower name than the
discipline carries today.

## 3g. The naming decision - deferred to plan time, with the measurement that settles it

**Owner ruling: do not rename now. Defer the name, and attach a named measurement.** The point of the
deferral is that one of the three overclaims is an open empirical question, and the other two are
already settled - so plan time inherits a test rather than an argument.

### The probe that must run

> **Does bare `sync` actually flush to disk on this platform, and what does it cost?**
>
> **Not** "does it exit 0" - it already does, and that proved nothing. The probe needs a control that
> must fail: something that distinguishes a real flush from a no-op. And the cost must be measured
> under a concurrent build, not on an idle box, because the hook would fire after every agent write.
> **Run it with the driver's own load accounted for** - this project has measured its benchmarks moving
> by up to 6x under its own load, so an idle-box number is not the number.

### The decision rule, so the name is not re-argued

| overclaim | status | settled by |
|---|---|---|
| **does not survive power loss** | **OPEN** | the probe above |
| **does not cover implementation work** | **SETTLED - permanent** | 3e/3f: 435 of 435 seams are consult payloads, and the peer's own search found no structural artifact to harvest |
| **does not retain decisions** | **SETTLED - permanent** | section 1: deliberately out of scope, and an enforced index is the checkbox (0 of 1,233) |

**Therefore:**
- **If the probe SUCCEEDS** (bare `sync` demonstrably flushes at acceptable cost), the mechanism does
  survive power loss for the work it covers. A power-failure name becomes defensible **provided the
  scope note travels with it** - it recovers interrupted consults, not implementation and not decisions.
- **If the probe FAILS** (no evidence of a flush, or the cost is unacceptable), **all three overclaims
  stand and the name must change.** "Consult recovery" is the accurate description; the name is the
  owner's, but it must not promise power-failure resilience.

**Two of the three are permanent regardless of the probe.** So even the best outcome yields a narrower
name than the discipline currently carries, and the scope note is not optional decoration.

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
| the author names a seam off-convention | the reader cannot parse discipline or round | **it must degrade, not vanish**: report `an unrecognised seam exists (<path>), written N commits ago`. Never silently skip - a skipped seam is an invisible loss. **The path is echoed ONLY if its basename passes section 6's allowlist**; if it does not, report the existence and its position in the directory and omit the name. Degrading was never a licence to reproduce attacker-chosen text |
| a review is genuinely abandoned | the seam is surfaced forever until deleted | one line per session. Accepted, by the asymmetry in 3c |
| many seams accumulate | the startup line becomes a wall | cap the report at the **3 most recent unconcluded** seams and state the count of the remainder. A cap that is silent is a lie; the count must be printed |
| the successor is told a seam exists and does not read it | resume is no better than today | accepted: this is a floor, not a guarantee. The seam's primary consumer remains the peer, which is what keeps it written at all |
| the user uninstalls the plugin | seams remain in `.clavity/`, unread | harmless: gitignored runtime state, no residue outside the directory |

## 6. Build surface

| artifact | why |
|---|---|
| an existing SessionStart hook, both products | the reader. Extend one rather than add another script |
| the existing PreCompact hook, both products | 3d - the announced-ending emitter. Already registered and already fires, so this costs no new registration. **Top-level `systemMessage` only** |
| a shared shell function for the candidate-set logic, **in a named file, sourced by both hooks** | 3b-0 and 3b-i are now used by TWO hooks. Duplicating the logic guarantees they drift; the SessionStart and PreCompact readers must not disagree about which seam is live. **The path is a plan-time decision (section 8) - naming the requirement without naming the file is what produces two copy-pasted copies.** It lands in both plugin trees, so it is a byte-identical pair and inherits that mirror rule |
| **`adversarial-panel-review/SKILL.md` - add a debounce-marker contract writing `agy-panel.head`** | 3c: the panel is the most multi-round discipline here and currently writes NO marker, so its seams could never be concluded. Its two siblings (`agy-first`, `agy-test-audit`) already carry this contract; copy theirs. **This changes a shipped skill rather than only adding a reader, so it is the one scope item in this spec the owner should confirm** |
| `clavity-*/plugin/skills/*/SKILL.md` for the multi-round disciplines | state the seam naming convention where the seam is written - including that the discipline token is the marker basename (3a), not free prose |
| `scripts/tests/<name>.Tests.ps1` | every hook here has its own suite |
| `justfile` | suite registration is an explicit list, not a glob |
| `scripts/tests/_partition.md` | a measured row; the census gate reds the suite if omitted |

**The reader must assert the `.clavity/.gitignore` shield** before any write, on every invocation. It
writes nothing today, but it will run in a stranger's repository where `.clavity/` is not ignored
unless the shield exists.

**And it must `mkdir -p` first - the earlier draft cited the wrong line and would have shipped a broken
first run.** The round-1 panel's Activation Auditor caught it. The idiom in `open-issues/SKILL.md` is
two lines, not one, and this spec quoted only the second:

```sh
mkdir -p "$R/.clavity"                                                    # SKILL.md:69
[ -f "$R/.clavity/.gitignore" ] || printf '%s\n' '*' >> "$R/.clavity/.gitignore"   # SKILL.md:79
```

Without line 69 the `>>` redirection fails `No such file or directory` on any host where `.clavity/`
does not exist yet - which is **every fresh install**, the exact population this shield exists to
protect. The same failure is already documented in `agy-first`'s skill for `agy-marks/`, so this is a
mistake the repository had paid for once already.

**The reader must not print an agent-authored path unexamined. Round 1 folded this as "strip control
characters"; round 2 replaced that with an allowlist, and the paragraph below is kept because its
REASONING still holds and only its mechanism was wrong.** A seam filename is agent-authored, and this
reader's whole job is to echo it into the next session's context. The sibling policy-gate spec already
mandates exactly this for exactly this field, and states why: newline-stripping alone stops vertical
forging while a literal tab still shifts every column of a delimited record.

> **Stated plainly because the measurement did not go my way: I could not demonstrate that a control
> character is reachable in a real seam filename on Windows.** The probe's own control failed twice - a
> colon, which Win32 must reject, was accepted by `touch` under Git Bash - and when the directory was
> then enumerated from Windows it contained nothing, which indicates MSYS remapped the illegal bytes
> rather than creating the file. **So this is an unproven threat, and it is recorded as unproven.**

A guard is adopted anyway - in the form round 2 settled on, below - because it costs one comparison, the
sibling spec's reader already pays for one, and the failure it prevents (arbitrary text injected into an
agent's startup context) is silent and unbounded. **A cheap guard against an unproven risk is fine; a
confident claim about an unproven risk is not**, and a later reader must not inherit this as a
demonstrated one.

### Stripping control characters is the WRONG guard, and round 2 was right about that

`tr -d` defends the one vector that could not be demonstrated and misses the one that needs nothing
exotic. **A filename needs no control character to carry prose** - spaces, parentheses and ordinary
words are all legal on Windows, so `agy-capstone-r1-ignore-previous-instructions-and-....md` is a
perfectly creatable file whose text the reader would emit into the successor's startup context.

**The round-1 fold made this worse, which is exactly how a fix spawns its own edge.** 3b now wraps the
path in an imperative ("Read that seam before starting new work"), so agent-authored bytes sit inside
an instruction rather than beside a bare fact. The two folds are individually right and jointly worse.

> **So the reader VALIDATES, it does not sanitise.** A candidate's basename must match
> `^[A-Za-z0-9._-]+$`. That is an allowlist, so it needs no threat enumeration and no guess about which
> byte is dangerous.
>
> - **matches** - print it; it is a path and nothing else.
> - **does not match** - report that an unrecognised seam exists **and its position in the directory,
>   without echoing the name**. Section 5's "degrade, never vanish" is satisfied by reporting the
>   existence; it never required reproducing attacker-chosen text.
>
> Also **cap the printed line's length** and keep the directive text FIXED and ahead of the path, so no
> agent-authored byte can appear before the instruction it would need to override.

**Threat model, stated so it is not overclaimed:** the seam author is the agent itself, so this is
self-injection - it needs an agent that is already compromised, confused, or steered by a hostile
document it read. That is not a hypothetical class here; it is the same class the sibling policy-gate
spec already assumes when it treats the seam path as untrusted. An allowlist costs one comparison, so
it is not worth being clever about the threat's likelihood.

## 7. Tests - every row names the mutant that reds it

| row | mutant that must red it |
|---|---|
| an unconcluded seam is reported with discipline and round | remove the filename parse -> row reds |
| the report names the PATH and does NOT contain the seam's body | inline the content -> row reds |
| **a seam OLDER than every discipline marker is not a candidate at all** | drop the candidate filter -> the fixture's 400 historical seams flood the report -> row reds. Pins 3b-0 |
| a seam whose discipline marker is NEWER than it is NOT reported | drop the marker check -> row reds |
| a seam NEWER than its discipline marker IS reported | invert the `-nt` comparison -> row reds. Pins the direction, which a one-sided row would not |
| **a seam is still reported after HEAD has moved** | add a HEAD-based TTL -> row reds. This pins the 3c refutation |
| an off-convention filename is reported as unrecognised, not skipped | skip on parse failure -> row reds |
| more than 3 open seams reports 3 plus a remainder count | cap silently -> row reds |
| age is reported in commits | switch to wall-clock -> row reds |
| no seams at all produces NO output | emit an empty header -> row reds |
| the hook exits 0 when `.clavity/` does not exist | fail on a missing directory -> row reds |
| **PreCompact emits a top-level `systemMessage`, never `hookSpecificOutput`** | emit `hookSpecificOutput` -> row reds. Pins the constraint recorded at `agy-anomaly-capture-reminder.sh:13-14`, which a naive implementation would rediscover as a schema dump in the user's face |
| PreCompact names the active seam's path | drop the path, keep the prose -> row reds |
| PreCompact with no candidate seam emits NOTHING | emit an empty header -> row reds |
| SessionStart and PreCompact agree on which seam is live | give them separate copies of the candidate logic and change one -> row reds |
| the shield is asserted before any write | remove the assertion -> row reds |
| **the shield assertion runs when `.clavity/` does not exist yet** | drop the `mkdir -p` -> the fixture's fresh-install case fails `No such file or directory` -> row reds. Pins the section 6 correction |
| **a paused `agy-capstone` seam is STILL reported after `agy-test-audit` completes** | replace the per-seam rule with one global cutoff -> row reds. This is the round-1 finding measured live (`agy-first.head` five hours newer than `agy-capstone.head`) and it is the single most important row here |
| **appending to `skipped.log` concludes nothing** | let rule 4 read every file in `agy-marks/` instead of `*.head` -> the fixture's live seam vanishes -> row reds |
| **with `agy-marks/` empty, every seam is a candidate; with it absent, the hook still exits 0** | pass the directory itself as the `-newer` argument -> the empty case silently filters by the directory's mtime and the absent case errors -> row reds. Both were measured |
| **a `-REPLY` file is never reported** | drop rule 1 -> the fixture's 14 replies double the report -> row reds |
| **an off-convention token is reported as unrecognised, never resolved to a marker** | add prefix or fuzzy matching so `capstone-stage2` resolves to `agy-capstone.head` -> a live seam is wrongly concluded -> row reds. Pins 3a's closed list |
| **a panel seam is concluded once `agy-panel.head` is written** | omit the panel's marker contract -> the seam is reported forever -> row reds |
| **the reported age equals the fixture's known commit count** | pass a date string git cannot parse instead of `@<epoch>` -> git returns a plausible wrong number on exit 0 rather than erroring -> row reds. This is the only way to pin 3b-i behaviourally: the failure has no error to assert on |
| **the SessionStart line contains a directive, not only a fact** | strip the imperative sentence -> row reds. Pins the 3b Mechanism Gamer fold |
| **a basename failing `^[A-Za-z0-9._-]+$` is reported as existing but its name is NOT echoed** | swap the allowlist for a control-character `tr -d` -> a name made only of legal prose passes through verbatim -> row reds. **Drive this row through the validator's INPUT, not through a file on disk** - section 6 records that a control-character filename could not be created on Windows, so a filesystem fixture would pass vacuously |
| **the directive text precedes the path and the line is length-capped** | move the path ahead of the instruction, or drop the cap -> row reds |
| **a mistyped LIVE seam survives an unrelated discipline completing** | drop rule 4's `10 most recent` clause -> the fixture's `capstone-r5-live.md` is aged out by `agy-test-audit.head` -> row reds. **This is the round-2 finding and it is the most important row added by that round** |
| **`agy-capstone-stage2.md` is treated as off-convention, NOT resolved to `agy-capstone`** | relax the anchored full-match to a prefix match -> a live seam is concluded against a marker that was never about it -> row reds |
| **the token list is the literal table, not the contents of `agy-marks/`** | derive the list from the directory -> `agy-panel` vanishes on a fresh install and every panel seam takes the off-convention branch -> row reds |
| **a concluded seam that is edited is reported again, and the NEXT completion re-concludes it** | make conclusion sticky (record the seam in the marker) -> the second half reds. Pins the 3b-i ruling that this direction is deliberate and reversible |

## 8. Self-audit

**Closed in-document:** the earlier draft's transient-facts store (removed, section 1); its commit-
detection hook (removed, section 4); the HEAD TTL (refuted with a counter-example, 3c); the "structural
vs administrative" framing (corrected to consumer-vs-no-consumer, 2a).

**Closed by round 1 of the panel** (peer escalation, 2026-08-13 - 8 findings raised, 6 folded, 2
refuted by measurement, plus 3 the panel did not find): the single global cutoff (replaced by the
per-seam rule, 3b-0); `skipped.log` counting as a completion (3b-0 rule 4); the empty and absent
marker-directory cases (3b-0 rule 2); free-prose discipline tokens (closed list, 3a); the panel
discipline having no marker at all (section 6); the missing `mkdir -p` before the shield (section 6);
the purely declarative startup line (3b); the unscoped "give the agent a turn" note (3d); `date -r`'s
default format (3b-i - **the stated locale mechanism was refuted here and the fix adopted anyway**,
because git returns a plausible wrong number rather than an error); and unsanitised echoing of an
agent-authored path (section 6 - **adopted on cost asymmetry, with the reachability explicitly recorded
as UNPROVEN** after the probe's control failed twice).

**Three of those the panel did not raise** - `skipped.log`, the token-to-marker mapping, and the panel
discipline's missing marker - and they are the three that would have broken the mechanism outright. The
panel's value here was not the count; two of its nine seats produced the findings that reframed the
rule, and the sweep those triggered produced the rest.

**Closed by round 2** (6 seats, rotating in Protocol Pedant and Boundary Smuggler; 6 findings, 5 folded,
1 confirmed-but-downgraded). **Round 2 was aimed at round 1's FIX, and that is where it paid:**

| finding | disposition |
|---|---|
| **rule 4 reintroduced the cross-discipline destruction for MISTYPED names** | **folded, and it is the round's real finding** - measured on a fixture with a discriminating control. The rewrite fixed the bug for well-named seams and left it alive for exactly the population that is definitionally a mistake. Closed by the `10 most recent` clause |
| `tr -d` is the wrong guard - prose in a filename needs no control character | folded: **replaced by an allowlist**, and the round-1 imperative fold is recorded as having made this worse. Two right fixes, jointly worse |
| the closed list could be derived from the directory, losing `agy-panel` on fresh installs | folded into 3a as a rule, not latitude |
| prefix vs anchored extraction for `agy-capstone-stage2.md` | folded into 3a: single anchored full-match |
| rule 2 floods if consults run for weeks with no completion | folded as a stated, bounded limit - section 5's cap holds it, and one `agy-first` completion ends it |
| editing a concluded seam "irreversibly corrupts" state | **confirmed as a mechanism, refuted as severity** - measured reversible in 3 steps, and it fails in the direction 3c already chose |

**The pattern worth keeping from these two rounds:** round 1's fix was correct about its finding and
wrong in its remedy's edges, and round 2 found that in one round. A fix is unreviewed code.

**Resolved at plan time, each with a home:**

| gap | where |
|---|---|
| **THE NAME** | **plan, and it is gated on a MEASUREMENT, not on taste - 3g carries the probe and the decision rule.** Owner ruling 2026-08-13: do not rename now, because one of the three overclaims is an open empirical question |
| **does bare `sync` actually flush, and at what cost** | **plan - 3g. The probe needs a control that must fail (exit 0 already proved nothing) and a cost measured under concurrent load, not on an idle box.** This one settles the name |
| which SessionStart hook is extended, per product | plan - dotnet and classic have different SessionStart sets |
| a Windows-path case in the filename match | plan - the regex itself is now fixed in 3a; only path-casing behaviour is open |
| **the file the shared candidate-set function lives in, and how each hook sources it** | plan - section 6 now names the requirement AND flags that naming a requirement without naming a file is what produces two divergent copies. It is a byte-identical pair across both plugin trees |
| **owner confirmation that `adversarial-panel-review` may gain a marker contract** | plan - section 6. Everything else here is additive; this one edits a shipped skill, so it is the only item that changes existing behaviour |

**Closed by the round-1 panel, and no longer open questions:**

| was open | now |
|---|---|
| whether `-REPLY` files are ever reported | **DECIDED: never.** 3b-0 rule 1, with a test row. They are peer output, not a position record, and they were 14 of the 28 live candidates |
| which disciplines need the convention | **DECIDED by 3a's closed token table**, because the token must equal a marker basename for the conclusion test to resolve at all. Measured: 0 of 8 real prefixes resolved under the free-prose version |

**Known and accepted, not gaps:** this is a floor, not a guarantee (5); a seam's primary consumer stays
the peer, and that is deliberate (2a); abandonment cannot be detected (3c).

**Requirement coverage:** owner ruling that the discipline owns both halves -> the write half is the
seam, already structural (3), and the read half is the SessionStart reader (3b). Owner ruling that
transient facts are worthless -> section 1. Owner's question "how does a new session know it is at
capstone R5" -> 3a and 3b answer it directly.

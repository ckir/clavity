# AGY policy gate - implementation spec

**Status:** owner-approved 2026-08-13. **Build from THIS file.**
**Supersedes in part:** `2026-08-13-agy-role-enforcement-design.md`, now a frozen ADR. That document
records WHY; this one records WHAT. Where they differ, this file wins.

**This ships with the plugin to end-user machines.** Every requirement below is written for a stranger's
repository on a standard Windows box, not for the author's machine.

---

## 1. What this builds

**ONE thing, plus the generic infrastructure a later tenant will reuse.**

1. **A policy gate** that refuses an AGY-* peer consult whose seam file names no adversarial roles. Its
   first and only rule in this build is `ROLES`.

**This section previously said "two things", the second being a productised POWER-FAILURE nudge. That is
no longer in this build** - it was extracted to its own design and then **deferred by the owner to a
future release** (2026-08-13). Sections 9 and 9a are retained as INPUT to that separate spec and are
marked DO-NOT-BUILD. **This paragraph exists because the summary sentence outlived the decision** - the
same drift that a sibling spec's scope line suffered, caught there in review.

The infrastructure - the skip token, the log, the degraded sentinel, the SessionStart reader - is built
**generic from the start**, because further tenants are already named and deferred: `OPEN-PROPOSAL`,
`NEGOTIATED`, and a future stateless form of power-failure. Naming these artifacts generically now costs
nothing; renaming them later would migrate files users already have.

## 2. The predicate

> **If the tool payload names a path under `.clavity/seams/` ending in `.md`, that file MUST contain a
> non-empty `PANEL-SEATS:` line. If it does not, block.**

Nothing else is inferred. No discipline is detected, no keyword is matched, no prose is parsed beyond
one narrow path shape. This is deliberate and load-bearing: any predicate requiring the driver to label
the consult would fail exactly when the driver is working from memory, which is the failure being
guarded.

The predicate is total because a standing rule already constrains every consult - point the peer at
files, never at a pasted summary - so every AGY-* consult names a seam. A payload naming no seam path
**fails open**: that is a violation of a different rule and not this gate's business.

**Producing a seam without roles therefore means DELETING a line, not forgetting to add one.**

## 3. Two hooks, and they are NOT byte-identical

This is the one place the two products genuinely diverge, and it is an owner ruling.

| product | matcher | how it finds the seam path |
|---|---|---|
| clavity-dotnet | a **NEW** entry matching `mcp__.*agy_ask` ALONE | `jq` over the MCP tool payload |
| clavity-classic | `Bash\|PowerShell` | exits 0 immediately unless the command is a `clavity ask`; then string-extracts the path |

**The dotnet entry must NOT extend the existing `Bash|PowerShell|mcp__.*agy_ask` entry**, which would
put this check on every shell command in the session.

**clavity-dotnet additionally changes its skills so subagents consult over `agy_ask`** rather than
`clavity ask --review-only`, which brings subagent consults under the matcher by construction.

**Measured, because the count matters to the edit list:** exactly **three** skills carry the subagent
parenthetical *"(subagents use the CLI form, not the MCP bus)"* - `agy-first`, `agy-capstone` and
`agy-test-audit`. **`adversarial-panel-review` does NOT** (zero occurrences); it names the classic CLI
transport generally, without routing subagents to it. So three skills need the subagent sentence
changed, and the fourth needs only its transport line checked for consistency - do not edit it blindly
to match the others.

**Consequences to handle, not discover:**
- `plugin-hooks-payload.Tests.ps1` asserts byte-identity for the shipped hook pair. **It must change** to
  exempt this pair, and the exemption must be explicit and named, never a loosened glob.
- **clavity-classic's gate is knowingly leakier.** Extracting a path from an arbitrary shell command is
  fragile against piping, aliases and quoting. It fails open when extraction fails. This is accepted;
  state it in the classic hook's header comment so the next reader does not treat it as a bug.

## 4. Fail OPEN on error, fail CLOSED on a violation

- **Any infrastructure failure exits 0.** No `jq`, no `sed`, unreadable file, unresolvable path, a
  `bash` that is not Git Bash, a seam that does not exist yet at PreToolUse time. A broken hook must
  never paralyse a stranger's session.
- **A positively-detected violation blocks.** The payload named a seam, the hook read it, the marker is
  absent or empty. That is policy, not error.

*Absence of evidence fails open; evidence of absence fails closed.*

**Exit code 2 BLOCKS on PreToolUse.** That is the mechanism, and it is why every error path above must
reach `exit 0` instead.

## 5. Locating plugin files - use `dirname "$0"`, never `${CLAUDE_PLUGIN_ROOT}`

Resolve any plugin-relative path from the script's own location:

```sh
here="$(dirname "$0")"
```

**Do not use `${CLAUDE_PLUGIN_ROOT}` in a hook body.** Measured: `agy-consult-guard-pre.sh` contains
zero occurrences of it, and only 1 of 13 hook bodies reads it at all - there is no precedent to lean on.
Unset, it collapses a path to an absolute `/skills/...` that cannot be opened. The repo's own idiom is
`agy-liveness-check.sh:126`. `dirname "$0"` cannot be unset.

## 6. The block message - a repair kit, in this order

1. **One line stating what is missing AND that this is a local role check - the peer was never
   contacted.** Every AGY-* discipline has an `agy-required-but-unreachable` terminal that halts and asks
   a human; a driver who misreads a block as a channel failure halts for an outage that never happened.
2. **A static pointer to where the seats are defined** - the consulting discipline's own `SKILL.md`,
   named by path.
3. **The skip token, last** (section 7).

**The block does NOT extract or inject a palette.** An earlier design extracted one between HTML-comment
delimiters. It is deleted, with its delimiters, its `sed`, its over-long bound and its empty-extraction
fallback. The reason is shipping: the palette path was hardcoded to one skill while the predicate covers
every seam, so a user running a different or custom discipline would be blocked and handed an
irrelevant repair kit. A static pointer is correct for every discipline, shipped or custom, and removes
roughly 60% of the implementation surface.

**Accepted cost, stated because it is real:** the seats no longer land in the terminal, so the driver
reads one file. That makes the skip token relatively cheaper, which is precisely why the skip count in
section 8 is load-bearing rather than decorative.

## 7. The skip token - generic, and honoured only by its own rule

**Format: `AGY-SKIP: <rule> <reason>`**, in-band in the payload. Example:
`AGY-SKIP: ROLES verifying the gate blocks`.

- **In-band, not an environment variable.** The agent invokes an MCP tool with a JSON payload and cannot
  set an env var for that call; an env-var hatch is reachable only by a human in a shell, which is a
  phantom for the actor it exists to rescue.
- **The reason is mandatory.** A token with a rule and no reason does not skip.
- **A hook MUST honour only a skip naming ITS OWN rule.** A bare `AGY-SKIP:`, or one naming a different
  rule, does not skip this gate. Without this, one token disables every present and future gate at once
  - a wildcard bypass, and the more dangerous failure direction than a hatch that fails to open.
- The block message names the token verbatim, including the rule name.

## 8. Observability - generic artifacts, and the readers are part of the build

A fail-open gate that dies silently certifies what it stopped checking. Every decision - pass, block, or
skip - appends **one short sanitised line** to `.clavity/policy.log`.

- **One `printf` append. Never a read-modify-write.** A single short append is atomic on POSIX, so
  concurrent writers interleave lines rather than scrambling them.
- **Sanitise every agent-authored field** - the seam path and the skip reason - by stripping ALL control
  characters and whatever delimiter the record uses, then length-capping. Newline-stripping alone stops
  vertical forging and leaves horizontal forging open: a literal tab shifts every column of a
  tab-delimited record. The log is the only audit trail for the escape hatch, so it must not be forgeable
  by the thing it audits.
- **Bound by ROTATION, not truncation.** At 500 lines, `mv` the log to `.clavity/policy.log.1` and let
  the next append create a fresh file. Truncation (`tail -n 500 f > tmp && mv tmp f`) is a
  read-modify-write and drops any append landing mid-shuffle.
  - **Rotation is BEST-EFFORT.** On Windows, renaming a file another handle holds open fails rather than
    succeeding atomically. Attempt it, ignore failure, never let it fail the hook. The honest guarantee
    is "bounded on POSIX, best-effort on Windows".
- **Degraded sentinel.** If `jq` is absent the hook cannot tell an `agy_ask` payload from a routine
  shell command, so it cannot log per-invocation without writing on every command. Instead it touches
  `.clavity/policy.degraded` **once**.
- **The SessionStart reader is a build row, not a someday.** It surfaces (a) the existence of
  `.clavity/policy.degraded`, and (b) the **skip count grouped by rule** since the last session.
  **It must read BOTH `policy.log` and `policy.log.1`**, or a mid-session rotation zeroes the count
  exactly when the hatch is being used most.
- **Specify when the sentinel is CLEARED.** An uncleared sentinel becomes permanent noise. Clear it on a
  successful `jq`-capable invocation.

### 8a. The `.clavity/.gitignore` shield is mandatory and re-asserted on EVERY invocation

```sh
[ -f "$R/.clavity/.gitignore" ] || printf '%s\n' '*' >> "$R/.clavity/.gitignore"
```

`.clavity/` is gitignored **in this repository**, which is a property of this repo's `.gitignore` and
not of the directory name. On a repository we do not control it is git-visible unless this shield
exists. Without it the hook drops seam paths and agent-authored skip reasons into a stranger's
repository, where a routine `git add .` publishes them.

**Re-assert on every invocation, not only at creation** - a shield deleted by hand or by `git clean -Xdf`
would otherwise leave the directory exposed forever after. One `stat` per invocation.

**The shield is `*` - the WHOLE directory - and narrowing it is a regression, not a fix.** It also
covers `.clavity/seams/`, which is correct: nothing under `.clavity/` has ever been tracked
(`git ls-files .clavity/` is empty), seams are runtime state, and they carry consult payloads and local
filesystem paths. Recorded because the next reader will want to narrow it.

**Resolve the repository root, never a relative path** - `git rev-parse --show-toplevel`, falling back
to `pwd`. A relative path writes into whatever subdirectory the caller happened to be in.

## 9. POWER-FAILURE - EXTRACTED. DO NOT BUILD SECTIONS 9 OR 9a FROM THIS FILE.

> 🔴 **These two sections are OUT OF SCOPE for this build.** Their own spec now exists -
> `2026-08-13-workflow-position-resilience-design.md` - and the owner has **deferred it to a future
> release as second priority** (2026-08-13; tracked in `clavity-dotnet/ROADMAP.md`). So this text is
> input to an artifact that is itself parked: **nothing here is on anyone's critical path.**
>
> Owner ruling: calling this a *productisation* was wrong. A productisation moves a working
> thing; this changed **the detection mechanism** (command-text grep -> `HEAD` moved), **the trigger
> gating** (always-on -> marker opt-in) and **the index-location contract** (the author's auto-memory
> path -> "whatever the host provides"). That is a new design, and a new design earns its own
> brainstorm, its own spec and its own review rather than riding in as a subsection of an unrelated gate.
>
> It is also a different *kind* of thing: this document specifies a stateless, syntactic check on a file
> named in a payload. Power-failure resilience is a stateful discipline about surviving session death.
> They share only the `.clavity/` infrastructure this build already provides.
>
> **What this build still owes it:** nothing but the generic infrastructure in sections 7 and 8 -
> `.clavity/policy.log`, `.clavity/policy.degraded`, and the `AGY-SKIP: <rule> <reason>` token - which
> exist so a future tenant does not reinvent them. **No power-failure artifact ships from this plan.**
>
> The text below is preserved verbatim as INPUT to that separate design, not as a requirement here.

### (retained as input only) POWER-FAILURE as a nudge, never a gate

Move the discipline out of the personal, unshipped
`~/.claude/hooks/power-failure-index-reminder.sh` and into the plugin, so it installs, updates and
uninstalls with it - the same migration AGY-AFTER already made.

**It ships as a reminder and MUST NOT become a gate.** Its predicate is stateful and semantic - *if
meaningful work landed, the index must have been updated* - where the role check is stateless and
syntactic. A hook cannot distinguish "I forgot the index" from "no update was warranted", so a gate
would fire on read-only exploration and make dummy index updates the cheapest compliance. It would also
gate a stranger's session on a file in their home directory tied to a memory feature they may not use.

### 9a. How the nudge detects a commit - do NOT port the personal hook's approach unexamined

The personal hook greps the agent's shell command for `git commit` as a word. **An earlier draft of this
spec listed "rtk-prefix tolerance" among the properties to preserve. That was wrong and is struck.**
`rtk` is a command-rewriting wrapper on the AUTHOR's machine, not a property of this discipline, and a
shipped hook must assume no such wrapper exists. Measured, the regex
`git[[:space:]]+commit([[:space:]]|$)` behaves like this:

| command | matches? | |
|---|---|---|
| `git commit -m x` | yes | intended |
| `rtk git commit -m x` | yes | not a designed accommodation - the pattern is simply unanchored |
| `sudo git commit` | yes | same reason |
| `echo remember to git commit later` | **yes** | **false positive** - it nudges on a command that commits nothing |
| `git commit --dry-run` | **yes** | which is why the second exclusion grep is load-bearing |
| `git commit-graph write` | no | already rejected by the trailing-whitespace requirement, so the `commit-graph` exclusion term is **redundant** |

**Requirement: detect the EFFECT, not the command text.** The nudge fires when `HEAD` actually moved -
compare `git rev-parse HEAD` against the value stored at the previous invocation. This removes every row
of the table above at once: no wrapper assumptions, no false positive on a command that merely mentions
committing, no `--dry-run` special case (a dry run does not move `HEAD`), and no `commit-graph` term.
It also catches a commit made by any route the string match would miss, such as an amend or a
`git rebase --continue`.

**Stated limit either way:** a `PostToolUse` hook only observes commits made through the agent's own
shell tool. A commit the human makes in another terminal is invisible to it. That is inherent to the
mechanism, is true of the personal hook today, and is acceptable for a nudge - but it must not be
described as complete coverage.

**Preserve these, which are measured and were nearly lost in the move:**
- **The message addresses the orchestrator explicitly and says so.** The hook fires in every context
  that runs a commit, including inside a dispatched subagent. Measured 2026-08-07: a haiku subagent
  obeyed it and wrote a memory file outside its dispatch's FILES list, while two sonnet subagents
  declined as out of scope - **compliance was tier-dependent**. Memory files live outside the worktree,
  so that write is invisible to BOTH verification axes (`git status --short` and `git log --stat`). There
  is no reliable payload signal for "am I a subagent", so **the message must carry the addressing** rather
  than the hook attempting detection.
- **Fail-open**: any error exits 0.

**New, required by shipping - the nudge is OPT-IN per project.** It fires only when
`.clavity/power-failure.enabled` exists; absent, it exits 0 silently. Firing on every commit in every
repository a user owns would be intrusive noise for people who never adopted the discipline. Marker-gated
nudges are established practice in this plugin - `agy-test-audit-reminder.sh` already works this way. The
marker is created when the discipline is adopted, by its skill.

**The shipped skill must NOT hardcode `~/.claude/projects/...`.** It describes the discipline and the
index's required CONTENT - each task with its commit SHA, the single resume point, in-flight state a
successor cannot derive from git - and points at whatever durable store the host provides. The author's
own auto-memory layout is not a contract for anyone else.

**Removing the personal residue is the owner's call**, not this build's: the personal hook and the
`CLAUDE.md` section stop being needed once the plugin ships them, but both are the owner's files.

## 10. Build surface

| artifact | why |
|---|---|
| `clavity-dotnet/plugin/hooks/agy-policy-roles-pre.sh` | the gate, MCP form. Name must not collide with the existing `agy-consult-guard-*` pair |
| `clavity-classic/plugin/hooks/agy-policy-roles-pre.sh` | the gate, shell form. **Not byte-identical to the above** |
| both `hooks/hooks.json` | dotnet: a NEW `mcp__.*agy_ask` entry. classic: a `Bash\|PowerShell` entry |
| an existing SessionStart hook, both products | surfaces the degraded sentinel and the per-rule skip counts. Extend one rather than adding a fourth script |
| `clavity-dotnet/plugin/skills/{agy-first,agy-capstone,agy-test-audit,adversarial-panel-review}/SKILL.md` | subagents consult over `agy_ask`, not the CLI |
| `scripts/tests/<name>.Tests.ps1` | every hook here has its own suite |
| `plugin-hooks-payload.Tests.ps1` | **must change** - an explicit, named byte-identity exemption for the gate pair |
| `justfile` | suite registration is an explicit list, not a glob |
| `scripts/tests/_partition.md` | a measured row; the census gate reds the suite if omitted |

## 11. Tests - every row names the mutant that reds it

The suite must prove the gate **blocks**, by asserting an exit code from a real invocation - not by
inspecting source text.

| row | mutant that must red it |
|---|---|
| a seam WITH a non-empty marker passes | remove the marker -> must block |
| a seam WITHOUT one blocks | add a marker -> must pass |
| a seam with an EMPTY marker (`PANEL-SEATS:` and nothing) blocks | give it content -> must pass |
| a payload naming no seam fails OPEN | **replace the hook body with `exit 0`** -> this row still passes, but every blocking row REDS. The suite, not the row, is the oracle |
| missing `jq` fails OPEN | same coupling: `exit 0` reds the blocking rows |
| missing `jq` touches the degraded sentinel | remove the sentinel write -> row reds |
| the sentinel is CLEARED on a healthy invocation | remove the clear -> row reds |
| the block message names the discipline's SKILL.md path | remove the pointer -> row reds |
| the block message states the peer was not contacted | remove that line -> row reds |
| `AGY-SKIP: ROLES <reason>` passes | omit the reason -> must block |
| **a bare `AGY-SKIP:` does NOT skip** | honour it -> row reds. This is the wildcard-bypass guard |
| **`AGY-SKIP: OTHERRULE <reason>` does NOT skip ROLES** | honour any rule -> row reds |
| a skip reason containing a newline logs ONE line | drop sanitisation -> the log gains a forged line -> row reds |
| a skip reason containing the record delimiter does not shift columns | sanitise newlines only -> row reds |
| the `.clavity/.gitignore` shield is restored before the first write | remove the re-assertion -> row reds |
| the log rotates at the bound and the reader still counts | make the reader read only `policy.log` -> the count drops after rotation -> row reds |
| classic: a non-`clavity ask` shell command exits 0 without reading anything | make it parse every command -> row reds |

## 12. What this is and is not

**It is a floor.** It proves syntactic compliance: a marker exists and is non-empty. It **cannot** check
the palette's anti-gaming requirement - which triggers fired, which seats were dropped and why, whether
the seated lenses cover the real risk surface. It prevents memory-driven omission; it cannot prevent
hollow compliance. **The block message must say so**, for the same reason the test-audit discipline says
it of itself: a guard that overstates its reach manufactures the blind spot it claims to cover.

**Known and accepted:**
- A seam authored outside `.clavity/seams/` escapes the block. Mitigated, not sealed: a `.md` path named
  elsewhere in the payload that carries no marker is **logged as a warning and passed**.
- clavity-classic's extraction is fragile and fails open more often than dotnet's.
- Rotation is best-effort on Windows.
- The skip token is honest but cheap; the per-rule skip count is its only counterweight.

## 13. Resolved at plan time

| item | note |
|---|---|
| exact marker syntax - line-anchored? case-sensitive? what counts as non-empty? | pin it with the test row that asserts it |
| the seam-path regex, concretely | needs a Windows-path case: payloads here carry `C:/Users/...` forms |
| the log record format and field order | one short line; fix the delimiter here, since section 8's sanitisation depends on it |
| the over-long / length cap for sanitised fields | a number |
| a payload naming MULTIPLE seam paths | check all, or the first? Reachable and unresolved |
| is the `<rule>` in `AGY-SKIP:` case-sensitive? | pin it with the row that asserts a non-matching rule does not skip |
| a seam path that resolves OUTSIDE the repository root | fails open under section 4, but the ordering deserves an explicit row so it is not discovered later |
| the seam file exists but is unreadable (permissions) | fails open under section 4; name it so the implementer does not add a fail-closed branch for it |
| which existing SessionStart hook is extended, per product | dotnet and classic have different SessionStart sets |

## 14. Provenance

Every requirement above was earned, most of them adversarially. The reasoning - four panel rounds, ~20
findings, the arguments for and against a `palette.json`, the delimiter design and why it was abandoned
- lives in the ADR: `2026-08-13-agy-role-enforcement-design.md`. Read it when asking "why is this like
this"; do not build from it.

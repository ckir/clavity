# Backlog triage — prune what is already true, build nothing

**Status:** design, owner-approved 2026-08-06 (option "Prune only — no new mechanism").
**Preceded by:** an AGY-FIRST fork consult + a 2-round AGY-NEGOTIATE, brief `.clavity/seams/backlog-fork.md`.

## Goal

Bring every open-issue tracking surface into agreement with the code, and **add no new mechanism to keep
it that way.**

## Why nothing is being built — the decision, and what would overturn it

Seven backlog entries were found describing already-shipped work, across five surfaces, in one day. The
obvious response is a checker. It was considered as **Direction B** and rejected on evidence:

- An LLM verifying natural-language claims against code is a **flaky oracle in this repo, measured.**
  `scripts/docs-audit.ps1:16-19` records a 30% claim-count swing on a file `git log` proves untouched.
  Two of two findings spot-checked from its punch-list were stale or a misparse. A backlog auditor built
  the same way would be a second unreliable oracle policing the first.
- A **deterministic** ID-collision checker was then costed. It catches 2 of the 7 and is structurally
  blind to untagged fixes and unnumbered sub-bullets.
- A **capstone-gate** step was costed. Measured: 3 of the 7 (AT-2 plus the two tracked-debt items closed
  under `a605275..413c617`). It is blind by construction to the two defects fixed by ordinary commits
  (`01b97a9`, `5542d38`) that convene no capstone. Three more (§2, §3, §5) predate the capstone discipline
  entirely — its first ledger row is 2026-07-25, those commits are 2026-07-20.

**The argument that won, and it came from the peer, against the position this session opened with:** a
stale entry causes **no production defect and no duplicate code**. It costs exactly one measurement at
triage. That is not hypothetical — seven were found and cleared on 2026-08-06, minutes each. Building a
permanent mechanism to prevent a cost that is already paid cheaply, by a discipline that already works, is
optimizing a non-bottleneck.

**This decision is conditional. Revisit it if ANY of these stops being true:**

1. **One human owner** plus paired agents. A second human introduces the coordination problem this
   reasoning assumes away — B implementing A's stale entry.
2. **The measure-before-coding law holds.** If an agent ever writes code from backlog prose without first
   measuring the file, a stale entry stops being free.
3. **A stale entry causes real rework.** The moment one costs more than a triage measurement, the
   arithmetic above is wrong and the mechanism becomes worth its tax.

Recording the trigger conditions is the whole substitute for the mechanism. Without them this is not a
decision, it is a deferral.

## Scope

### Already done (2026-08-06, before this spec) — stated so the plan does not redo it

- `clavity-dotnet/ROADMAP.md` §2, §3, §5 marked ✅ SHIPPED in place, with the verifying code cited (`9f3838f`).
- `agy-autotrain/ROADMAP.md` AT-2 marked ✅ SHIPPED AND CLOSED, capstone `6d79bee..a0b2d7b` cited (`9f3838f`).
- Tracked-debt #2 and #3 moved to RESOLVED with their fix SHAs.
- The dotnet release list flagged as stopping at v0.1.9 with `CHANGELOG.md` named as the current record.
- `MEMORY.md` compacted 21,0 KB → 13,6 KB; the docs-audit spot-check moved into `project_docs-accuracy-audit.md`.

**Numbering was NOT compacted anywhere, deliberately** — `clavity-dotnet/ROADMAP.md` §0 states that
renumbering invalidates every citation to §7 and §8, and `MEMORY.md` cites tracked-debt "#1" by index.

### U1 — Close the tracked-defect list

- **D1** (`check-seed-artifacts-synced.sh` passes silently without `jq`) — **DELETE.** Fixed by `01b97a9`.
  Verified by execution 2026-08-06: with `jq` on PATH exit 0; with PATH stripped to Git `usr/bin`,
  **exit 2** and the message `check-seed-artifacts-synced: jq is required but not found on PATH`.
- **D3** (`ParseLatest` never checks the HTTP pid matches the gRPC pid) — **DELETE.** Fixed by `5542d38`.
  Verified by execution: 19 `LsDiscovery` tests pass, including
  `ParseLatest_pairs_the_http_line_of_the_SAME_session_when_two_sessions_interleave`, which exists to kill
  exactly the chimera mutant the entry describes.
- **D2** (check-roster `path-scan.iss` dotnet gap) — **DROP as unreproducible**, and record why. The map at
  `scripts/lib/release-lib.ps1:47` declares `path-scan.iss` with `Members=@('classic')` and `Provable=$true`;
  only `clavity-classic/installer/clavity-classic.iss` references it. That is self-consistent. The entry as
  written does not describe a state anyone can reach from its own text.
  **If the original observation was real, it is lost — the entry did not carry a reproduction.** That is the
  finding to keep. It goes as one line into `memory/feedback-preexisting-defects-in-scope.md`, the file that
  already governs how a pre-existing defect is written down: **a tracked defect must carry the command or
  file:line that reproduces it, or it is not trackable.** It does not stay a permanent unactionable row.

`.clavity/local-anomalies.md` needs no action — verified EMPTY on 2026-08-06, 0 bracketed-bullet entries,
fully triaged on 2026-08-05. It is listed here so the plan does not go looking.

### U2 — Inventory and triage `agy-autotrain/docs/fix-the-tool-backlog/` (never inventoried)

Eight real entries, discovered during this brainstorm and absent from every prior inventory:

| file | recorded status | action |
|---|---|---|
| `curate-nudge-age-reads-drain-log-dates.md` | `status: fixed` | verify the SHAs in `fixed-by` land the fix; leave the file in place |
| `agy-look-tail-truncation.md` | `status: open` | verify still true |
| `grpc-default-max-message-size.md` | `status: open` | verify — this is the `MaxReceiveMessageSize` fact already in `MEMORY.md` |
| `idle-wait-false-modal.md` | `status: open` | verify still true |
| `inbox-snapshot-misses-slash-command-path.md` | `status: open` | verify still true |
| `stalled-reply-recoverable-not-lost.md` | `status: open` | verify still true |
| `working-vs-stuck-step-delta.md` | `status: open` | verify still true |
| `conversation-scoped-tools-vs-no-open-conversation.md` | no status line | classify |
| `DRY-RUN-2026-07-11.md` | n/a | confirm it is an artifact, not an entry |

**Verify means measure, not read.** Every stale entry found today looked plausible.
`README.md` and `_template.md` are infrastructure, not entries.

**Each entry needs its own oracle, and the PLAN must name it per file — this spec cannot.** These are
defects in an EXTERNAL tool (agy) and its bridge, so the oracle is not uniformly a test: some are
reproducible only against a live peer, some are code reads against `clavity-dotnet/src`, and at least one
(`grpc-default-max-message-size`) is already stated as a live fact in `MEMORY.md` and needs no re-probe.
Writing "verify each" without naming how is the placeholder this repo's plan discipline exists to catch.

**If triage finds a REAL and severe open defect** — one reachable and worse than an annoyance — it does NOT
get silently fixed inside this epic. Scope is triage. Surface it to the owner with the measurement and let
them decide whether it interrupts. Quietly widening a hygiene pass into a defect fix is how an epic stops
being reviewable.

**THE THIRD DISPOSITION — an entry that can be neither reproduced NOR disproven.** Several of these need a
live peer in a specific state (`idle-wait-false-modal`, `stalled-reply-recoverable-not-lost`,
`working-vs-stuck-step-delta` are the likely cases). A binary open/fixed forces a guess, and a guess here
is how a false `fixed` ships. Such an entry keeps `status: open` and gains one frontmatter line recording
that triage tried:

```
last-triaged: 2026-08-06   # could not reproduce; NOT evidence of fixed
```

**Un-reproduced is not fixed.** The distinction is the entire point — an entry closed on a failed
reproduction is exactly the false-clean this repo keeps paying for.

**HOW A FIXED ENTRY IS CLOSED — and the trap in the word "retire".** This directory is **append-only**
(`fix-the-tool-backlog/README.md:8`: *"One file per entry (append-only)"*). Files are never deleted or
moved to an archive. Closing means editing the frontmatter in place to `status: fixed` plus `fixed-by:
<sha>` and `fixed-on: <date>`, per `_template.md:6-7`.

🔴 **Do NOT touch the driver-cheatsheet rule.** `_template.md:14-18` states it outright: *"Two SEPARATE
gates, do not conflate them. Marking this item `fixed` records that the CODE is fixed. RETIRING the
corresponding driver-cheatsheet rule is a later, deliberate decision requiring BOTH a committed green CI
regression test on every variant the quirk reproduced on, AND wide end-user adoption… Closing this item
does NOT authorise stripping the rule — an end user on an older build still needs it."*
An earlier draft of this spec said "retire per the dir's own convention", which conflated precisely the two
gates that template forbids conflating. It was caught by the panel, not by review of the draft.

### U3 — `docs/backlog/` (1 file)

`golden-header-per-ask-token-optimization.md`, `**Status:** BACKLOG (not started)`. Confirm still
unstarted, then leave or retire.

### U4 — The docs punch-list, bounded

`docs/docs-audit-findings.md` holds 8 findings. Two were checked: one stale, one a misparse. **Check the
remaining six.** Expect a high false rate.

**Record each judgement in `memory/project_docs-accuracy-audit.md`, NOT in the punch-list file** — that
file is a GENERATED view of `docs-audit-findings.json` and is overwritten by the next audit run, so a
judgement written there is erased by the tool that produced it. The two already-checked findings are
recorded there, with the six unchecked ones named so the section cannot be misread as a clearance.

## Explicitly OUT of scope

- Any new checker, gate, protocol step, or CI assertion. That is the decision, not an omission.
- New features: `clavity --restart-agy`, classic pre-flight thread discovery, §10 productization.
- Owner-decision items that no amount of triage resolves: the ECC hook latency tax (not this repo's code),
  ROADMAP §7 / §8 (both brainstorm-first), the two open design forks (§9, AGY-* family #2).
- Backfilling the dotnet release list. `CHANGELOG.md` is generated and current; reconstructing six minors
  from commit messages would manufacture recollection.
- `clavity-classic/README.md` verification against `src/membus.rs`. Real, but it is a doc-accuracy task with
  its own oracle, and folding it in would make this epic two epics.

## Success criteria

1. The tracked-defect list contains only entries reproducible from their own text.
2. Every `fix-the-tool-backlog/` entry carries a status verified by measurement on 2026-08-06, or is retired.
3. All six docs-audit findings have a recorded per-finding judgement.
4. **No new mechanism exists**, checked as an ALLOW-LIST, not a deny-list: **the epic's diff touches only
   `*.md` files** (plus the frontmatter inside them) **and out-of-tree memory files.** Any change under
   `scripts/`, `src/`, `installer/`, `plugin/hooks/`, a skill, a CI workflow, or `justfile` fails this
   criterion. The earlier deny-list phrasing named four paths and would have passed a new
   `scripts/check-backlog-status.ps1` — the exact mechanism this epic exists not to build.
   Check with `git diff --name-only <base>..HEAD` and read it; a one-line eyeball is the whole gate.
5. **The three revisit-triggers are appended to `MEMORY.md`** under the tracked-debt pointer, in the same
   commit range as the triage. Not "somewhere a future session will read" — that is unpinnable and passes
   by assertion. `MEMORY.md` is the file loaded into every session's context, which is what makes it the
   only location that satisfies the intent.

## Testing

There is nothing executable to test: every change is to a tracking document. The verification burden is on
each individual disposition, and the standard is the one this session used throughout — **a control that
must fail.** For a "fixed" claim that means demonstrating the old behaviour is gone AND that the check
could still detect it (D1's control: `jq` present → exit 0; treatment: absent → exit 2).

No suite should move. If `just test-scripts-fast` changes from **328 passed / 0 failed**, something outside
this scope was touched.

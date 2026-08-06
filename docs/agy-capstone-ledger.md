# AGY-CAPSTONE ledger

One row per capstone. Appended before a plan may be declared complete.

**This is a RECORD, not a proof.** Nothing prevents someone appending a GREEN line without running
anything; a self-asserted ledger is the same shape as the re-stamping defect the verify gate removed.
Two things keep it honest, neither a guarantee: the `evidence` column must cite something independently
checkable, and the ledger is reviewed like any other artifact rather than trusted like a gate output.

**`none` is not a permitted evidence value.** A capstone that goes green on its first round still
produces a transcript — the rounds it ran, the lenses it seated, what it tried. Cite that. If there is
nothing to cite, the entry does not go in.

**A row is written BEFORE adjudication and must be RETURNED TO after it.** The verdict a capstone
proposes is `GREEN (proposed)`; only the owner turns that into `GREEN`. Nothing prompts that second edit,
and on 2026-08-06 a row was found still claiming `(proposed)` long after its marker had been written —
the record was pessimistic rather than wrong, but a cell nobody trusts to be current is a cell nobody
reads. **When the owner confirms, come back and say so, and cite the REVIEWED tip** (which is not the
commit that added the ledger row — that commit is by construction unreviewed).

**How to tell a confirmed GREEN from a waiver, later, without asking anyone.** Both write the marker, so
the marker alone does not distinguish them. A round-cap waiver ALSO appends a `WAIVED` line to
`.clavity/agy-marks/skipped.log`; a confirmed GREEN appends nothing. Absence of a line there, plus a
written marker, is the confirmation. Note that log is gitignored runtime state, so this check works on the
machine that ran the capstone and nowhere else — if you need the fact to survive the machine, put it in
the row.

**Absences are meaningful.** SP-0, SP-A, SP-C and SP-D do not appear below. They never had a
reconstructible capstone; their evidence is a verification transcript under
`docs/superpowers/verification/`, which is a different and weaker claim, deliberately not laundered into
this table.

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-07-25 | SP-B agy-capstone skill | 4 | GREEN | folds 2c105ac, 98ffcbd, a879cce, 0f5e3a1 |
| 2026-07-27 | agy-test-audit discipline | 3 | GREEN | folds 61bb193, be2a5e3, cd1a209 |
| 2026-07-30 | clavity-ls channel resilience | 3 | GREEN | folds 131591e, f2bab54, 08abc67 |
| 2026-07-31 | b14bef1..fbb126b | 5 | GREEN | folds 8fcbfa6, a52ef9d, 20834b0, 200c3ff, fbb126b |
| 2026-08-01 | 185affc..757337a | 3 | GREEN | folds f8d9703, 01622ce, 757337a; briefs .clavity/seams/phase-b-capstone-r{1,2,3}.md |
| 2026-08-01 | 19f589a..18495cd | 3 | GREEN | folds da18681, 18495cd; briefs .clavity/seams/anomaly-capstone-r{1,2,3}.md |
| 2026-08-02 | 29a5db8..c70f145 | 4 | GREEN | folds d089552, 0ca7407, c70f145; briefs .clavity/seams/capstone-anomaly-fix-r{1,2,3,4}.md |
| 2026-08-02 | 6d79bee..a0b2d7b (AT-2 durability) | 3 | GREEN | folds 3adc045, a0b2d7b; round 1's miss reproduced by the probe recorded in 3adc045's message |
| 2026-08-03 | 4a25d7a..5dc8822 (curate-nudge age scan) | 4 | GREEN | folds a357d7a, 8099813, 5dc8822; brief `.clavity/seams/capstone-nudge.md` (rewritten per round). Every finding measured before folding; round 3's finding was one the peer itself dismissed as unrealistic |
| 2026-08-06 | a605275..413c617 (pre-release defect sweep, `.no-agy` repo-root walk) | 2 | GREEN (owner-confirmed 2026-08-06; reviewed tip `be851cc`) | fold 413c617; **LIVE-PROVEN in the INSTALLED plugin**, which is the evidence that matters most here: the same smoke (`.clavity/scratch/prerelease/livesmoke.ps1`, takes `-HooksDir`) run against the pre-fix installed hooks kept as a backup scored **9/9 BROKEN** — every hook fired straight through a root `.no-agy` — against **9/9 correct with every control firing** after the hot-copy. Same script, same payloads, same machine; only the hooks differed; briefs `.clavity/seams/prerelease-capstone-r{1,2}.md` + the fork brief `prerelease-unc-fork.md`. **R1 GREEN rejected as false, the 5th consecutive one** — it cited `agy-consult-guard.Tests.ps1:489-505` (file has 146 lines) and `agy-test-audit-reminder.sh:113` (has 104), and reported *measured* file counts of 28/14 that are really 25/11. Numbered "quote line N verbatim, or reply DOES NOT EXIST" made it retract both citations and name the cause: round-1 line numbers were **diff-stream offsets, not source lines**. **The defect that mattered was found by the DRIVER running the shipped hook against its own pre-change self** — an unreachable UNC cwd cost 20343ms against 3882ms before, worst on the two PreToolUse hooks. **R2 (Regression Auditor, rotated in) was well-grounded and produced one real new finding** — extended-length UNC (`//?/UNC/server/share/...`) walks two levels past the true volume root — **verified, then measured at 974ms because the `[ -d ]` gate short-circuits that shape entirely. Below the severity floor; recorded, not fixed.** The peer's own suggested fix was WRONG on its number (claimed the gate costs one stat / ~3882ms; measured 9481ms) while its refutation of the obvious `//`-prefix alternative was RIGHT and changed what shipped: WSL repos are live UNC paths |
| 2026-08-03 | c7b3923..8889473 (agy discipline cost/quota hygiene) | 4 | **GREEN — owner-confirmed.** Marker `8889473` (the REVIEWED tip, not the ledger commit `8d2daa3`). Cell corrected 2026-08-06: it had read `GREEN (proposed)` since the row was written and was never updated after adjudication. **The confirmation is evidenced, the DATE is not** — a marker is written only on a gate-satisfied terminal state, and the only other such state is a round-cap waiver, which would have left a `WAIVED` line in `.clavity/agy-marks/skipped.log`; there is none for this HEAD. No confirmation date is recorded anywhere, so none is invented here | folds 309fb4e, c72d94b, 8889473; brief `.clavity/seams/capstone-cost-hygiene.md` (rewritten per round). **R1 GREEN rejected as false** — all six seats returned "no new findings" while restating the driver's own do-not-re-raise ledger as their "where looked", and one claim (`all hooks maintain set +e`) measured false. R2 RED with 3 findings, all verified true by counting. R3 GREEN rejected — its Fold Auditor cited `_partition.md:17` and declared it dated when it was not. R4 GREEN, and its one directly-checkable citation quoted the fixed line verbatim |
| 2026-08-06 | `c4cfce4..96d1178` (backlog triage — docs-only) | 3 | **GREEN — owner-confirmed 2026-08-06.** Marker `96d1178`, the REVIEWED tip — **not** the ledger commit `ec45a94`, which the peer never saw. HEAD was re-checked at confirmation and had not moved. No `WAIVED`/`SKIPPED` line exists for this HEAD (`skipped.log` holds only the two 2026-08-04 `d0b4cb1` entries), so this is a clean adjudicated GREEN rather than a gate-waiver | folds `e0afd0c`, `eddcf7c`, `96d1178`; briefs `.clavity/seams/backlog-triage-capstone{,-r2,-r3}.md`. **The owner chose to run a capstone over a range with ZERO executable code** — 12 markdown files — and it was the right call: **the peer refuted a committed claim of mine in BOTH of the first two rounds, and both times it was right and I was wrong.** R1 killed the Task-4 stamp (`AgyView.cs:83` is inside `TryTakeGuidanceBlock()`, gated at `:71` by `Interlocked.Exchange(ref _guidanceDelivered,1)`, and `AskAsync:178-181` sends `var outgoing = message;` after the T4b comment). R2 then killed **my retraction** (`main.rs:641-647` passes `HeaderState::Absent` under *"The PEER gets the ask only"*, and the `read_combined` I cited at `:892` is inside `fn doctor()` at `:859`) — so the item is resolved on BOTH drivers and the stub is now closed as obsolete, not re-scoped. **One cause both times: one driver measured, the other INFERRED from a grep hit whose enclosing function I never opened.** R3 GREEN, four seats, all `no new findings`; I re-verified its two load-bearing claims independently — `TryReadCombined` has exactly one call site and `golden_header::apply` exactly one production call site, whose only caller passes `Absent`. Peer also contributed failure mode 6 (prose-oracle rot), verified live: `McpTools.cs` is in `Clavity.Mcp` while neighbouring stamps scope to `Clavity.Ls/*.cs`. No review-only breach: tree clean, HEAD and reflog tip unchanged, scratch dir empty |
| 2026-08-04 | fe38993..d0b4cb1 (AGY-ANOMALIES capture gap) | 1 | **GREEN — owner-confirmed 2026-08-04**, with one UNVERIFIED finding surfaced and its risk explicitly ACCEPTED (`Agent\|Task` matcher anchoring; audit line in `.clavity/agy-marks/skipped.log`) | brief `.clavity/seams/capstone-anomaly-capture.md`; five seats (Cascade Analyst, Protocol Pedant, Mechanism Gamer, State Corruptor, Boundary Smuggler), all "no new findings", 3/3 spot-checked citations quoted the cited line verbatim. No review-only breach: status clean, HEAD and reflog tip unmoved. **The seven defects that mattered were all found earlier, by RUNNING the suites during execution, not by any panel** — four of them one family: an assertion satisfied by the ABSENCE of its subject (equality between two silent channels; a source scan over a missing file; a `.Count` on a PowerShell-unwrapped scalar; `-Match '2 untriaged'` matching `12`). **Driver's own round found what the panel did not:** the two SessionStart halves were probed with and without `jq` (agree 3/3, silent/silent — control fired, so non-vacuous), and the `Agent\|Task` matcher-anchoring question was raised and could NOT be settled here — logged UNVERIFIED below rather than folded |
| 2026-08-05 | f43f364..a6bcdf2 (SessionStart capture) | 4 | **GREEN — owner-confirmed 2026-08-05.** Marker `.clavity/agy-marks/agy-capstone.head` = `a6bcdf2…`, the REVIEWED tip, deliberately NOT ambient HEAD (`d32e1f4`, a docs-only commit made after round 4); the gate therefore re-arms on the next trigger, which is correct-by-design. **And the thing this ledger cannot record from a review alone: the recorder was then PROVEN TO FIRE** — hot-copied into the installed plugin, session restarted, and a real `{"v":3",…,"source":"resume"}` row landed. That is the measurement v17 never had, and the inference it died on | folds `ea520a4`, `cfd4a25`, `a6bcdf2`; brief `.clavity/seams/capstone-sessionstart.md` (rewritten per round). **The highest-yield capstone in this ledger: 9 real defects across rounds 1-3, every one verified by driver-side measurement before folding, and NONE of them found by the twelve rounds of plan review, my own review, five implementer subagents, or 532 passing tests that preceded it.** R1 (3): a LOCALISED sort key — `ConvertFrom-Json` returns `[DateTime]`, not the ISO string, so `[string]` formatted it per culture (`el-GR` → `08/05/2026 …`) and `-Last N` kept the OLDEST sessions; a merged session losing a transcript a later fire named; and `keep = $g[0]` being unpinnable. R2 (5): **the v15 alarm was SILENT during a live outage** — it summed only completed sessions, and the session you run the report from is by definition still running; plus an unpinned intra-group sort, `began , 2 fires` on an empty source, a dead `first_seen`, a lying test title. R3 (1+3): **a failed `jq` reported as a CLEAN scan** — PowerShell `try/catch` does not catch a native non-zero exit, so a truncated transcript (jq exit 5, measured) had its PARTIAL count stamped `ok`; plus `Get-Num` killing the whole report on `[int]"N/A"`, and two correct-but-invisible branches. R4 CLEAN across three seats, and its four mutation predictions each matched a mutation I had already run independently; its one novel claim (`Sort-Object` does not clobber `$LASTEXITCODE`) I measured separately and it held. **All four R3 guards mutation-proven — four simultaneous mutations produced exactly four matching failures.** One finding REJECTED by measurement (an ASCII sub-second sort inversion: real ordering, unreachable input — the peer concurred, and the overclaiming COMMENT was corrected instead of the code). One AGY-NEGOTIATE, owner-directed, on the `-Last 0` default: converged on keep-the-default-plus-a-notice, **with the peer correctly pressing that my "silent window drift" argument was over-weighted** — an unbounded store already drifts. No review-only breach in any round: status clean, HEAD and reflog tip unmoved (the one dirty file at R1's after-snapshot was my own edit, checked before attributing it) |

**A note on the AT-2 row: round 1 returned GREEN with zero findings, and it was wrong.** Its answer walked
the six-item do-not-re-raise ledger it had been given and confirmed each item back to the author. Nothing
in it was a surprise, which is the tell — a review whose findings never surprise the author has agreed
with the author rather than read the code. The defect was on the surface the ledger never mentioned:
`AGY_INBOX_SNAPSHOT_KEEP` fed `tail -n +$((KEEP + 1))` unvalidated, and because bash evaluates a
non-numeric name as 0, a typo (`abc`), a negative, or a literal `0` all became `tail -n +1` — which lists
every slot and deletes them all, **including the snapshot written moments earlier by that same
invocation.** Measured with a control that had to retain: `KEEP=5` → 4 slots kept; `KEEP=0`/`abc`/`-1` →
0 kept, silently, exit 0. A typo in a documented knob was total loss of the history the hook exists to
preserve. Fixed in `3adc045`.

Round 2, run with five rotated lenses and told plainly that round 1 had been refuted by measurement,
produced two findings. One was real (`B1`: the prune re-derived its directory with `!` where the adjacent
line already guards the empty case). **The other arrived with fabricated evidence** — it cited
bullet-bearing comment blocks at "lines 98, 104, 138" of a file that is 62 lines long; those lines do not
exist, and its stated consequence was independently wrong, since the dedup invariant bounds unchanged
content to one slot. The underlying observation was still correct and cheap, so it was folded as
hardening with a mutation-proven test, and the fabrication recorded rather than quietly dropped.

Round 3 rotated five further lenses and returned clean, citing two files it had not been pointed at. Its
highest-risk claim — that the installed layout actually reaches the new hook — was checked independently
rather than accepted: `agy-autotrain/installer/agy-autotrain.iss:53` ships `..\*` with `recursesubdirs`,
excluding only `installer,dist,publish,agy-observations.md`, so a newly added hook file does reach an
installed box. That check is the difference between this GREEN and round 1's.

**This is the second consecutive capstone in which the peer's first-round GREEN was false, and the second
in which a confident, specific, verifiable-looking line citation was invented.** Both times the defect was
found by checking the reviewer rather than by the review. The `rounds` column reads 3; the honest reading
is that the peer produced nothing of value until it was told, with measurements, that it had been wrong.

**A note on the anomaly-capture row, because it is the first entry whose round 1 was rejected.** Round 1
returned GREEN with zero findings on an 864-line diff. It was not accepted: two of its claims were false —
it asserted the two plugins' `SessionStart` registrations were identical (they differ by design, 2 entries
vs 3) and it cited `agy-anomaly-reminder.sh:88-89` for a construct that sits at 70-71. Checking the first
false claim exposed a real defect the round had missed, and the fix for THAT was itself the wrong shape,
which round 2 caught. Round 2 then closed `VERDICT: GREEN` while listing two findings in its own body; that
was scored RED too. Only round 3 was a GREEN whose verdict matched its body.

The `rounds` column therefore counts three, but the honest reading is that **no peer round produced a
finding until the peer was told its previous verdict had been refuted by measurement.** The defects in this
range were found by checking the reviewer, not by the review. That is worth recording precisely because
this ledger is a record and not a proof: a row reading "3 rounds, GREEN" would otherwise imply a
convergence that did not happen the way the number suggests.

---

**Anomaly file drained 2026-08-02 — the 8 captured entries, all fixed rather than filed.** The owner's
ruling was that closing an anomaly means fixing the defect and letting the file empty as a consequence.
`.clavity/local-anomalies.md` is gitignored, so deleting an entry destroys the only record of it; the
dispositions are therefore recorded here.

| # | Anomaly | Disposition |
|---|---------|-------------|
| 1 | consult guard classified any command whose TEXT mentioned the consult CLI as a consult | fixed — classifier anchored on command position (`a25ebd2`'s predecessor `fbd89b9`), integration test seen RED first |
| 2 | consult guard matcher named the MARKETPLACE where the live tool names the PLUGIN, so it never fired on the MCP path | fixed — matcher is now a pattern, plus a namespace assertion that rejects a literal plugin-qualified tool id (`fbd89b9`) |
| 3 | `agy_look` truncates the newest reply out of a long cascade | tracked elsewhere — root cause is the gRPC 4 MB default in `LsChannel.cs`; backlog item `agy-autotrain/docs/fix-the-tool-backlog/grpc-default-max-message-size.md`, committed `1d4a016` |
| 4 | `just test-scripts` grew past the 600s foreground tool cap | fixed — suite partitioned by measured batch runtime (`a52a991`, re-partitioned `0543dcc`) |
| 5 | a dispatched subagent wrote to a file outside the set it was told to touch | fixed — dispatch now states a FILES allow-list and the driver diffs the real change set against it (`9d7f484`). **Corrected by the capstone (`0ca7407`): the original wording said `git status --short`, which is BLIND to a committed write, and implementer subagents commit by default. Both axes are now required.** |
| 6 | seed sync gate used an ALLOW-LIST, so any new shared file was silently ungated | fixed — replaced with discovery over the union of both plugin trees (`29a5db8`) |
| 7 | GROWTH region mojibake-corrupted for 13 days while its sha256 sidecar MATCHED | artifact republished clean; class closed by a tripwire inside `curate-commit`, both binaries (`a25ebd2`) |
| 8 | `agy-curate` had no legal end state for an entry that is neither promotable nor droppable | fixed — HELD added as a fourth disposition, and the promotion rubric's scope bounded (`a51a20e`) |
| 9 | three shipped hooks carried non-ASCII bytes, and the ASCII guard excluded the one file that violated | fixed — bytes stripped and the CLASS closed by `scripts/tests/plugin-hooks-payload.Tests.ps1`, a glob-based guard over the whole payload (`29255bc`). The bytes were comment-only and harmless; the defect was the guard. `agy-consult-guard.Tests.ps1:111` looped ASCII over `-pre.sh`/`-post.sh` and skipped the `-lib.sh` those two SOURCE, and `agy-drive-session-reset.sh` had no suite at all. **The new guard's own first version repeated the bug it exists to catch** — an aggregate count control still passed with one driver's path broken, because the other driver's files satisfied the count; controls are now per-directory and each was proven by breaking each path independently |
| 10 | the pre-drain inbox snapshot silently does not happen when `agy-curate` is invoked as a slash command | tracked — `hooks.json` matches the `Skill` TOOL, which a slash-command invocation never issues, so the guard is absent on the most natural entry path. Backlog item `agy-autotrain/docs/fix-the-tool-backlog/inbox-snapshot-misses-slash-command-path.md` (`77a1d1b`) with two concrete mitigations. Found by RUNNING the drain, not by reading the hook |

The owner's failure criterion for the first triage — "a third outcome appears in practice" — did not trip.

**At the time this section was written the file was NOT empty, and that was the correct outcome** — four
entries captured DURING the fix work remained, and an entry is deleted only when it is genuinely
dispositioned, never to quieten a hook. All four were dispositioned later the same day (see the two
disposition notes at the foot of this file), and only then did the file empty. The order matters: the plan
had predicted a silent hook at exit 0 on the assumption the file held only the original eight. Emptying it
on that schedule would have destroyed the record of four live observations — the exact failure this capture
mechanism exists to prevent — so the hook stayed noisy until each entry had a recorded reason.

**Three of the original eight were found by the capture mechanism during its own construction.**

**On the 2026-08-02 row (`29a5db8..c70f145`, 4 rounds).** Three of the four rounds were scored RED, and
two of those were rounds the peer itself closed GREEN. The pattern is now consistent enough across three
capstones to state as a rule rather than an anecdote: **a clean verdict is a claim, and the claim has to be
checked against its own body and its own citations before it is banked.**

- **Round 1** returned `VERDICT: GREEN` while its Lens 1 enumerated real evasions and a real false
  positive. It also carried three false citations, two labelled MEASURED — including a classifier located
  at `lib.sh:143-159` in a 103-line file, which the same paragraph had cited correctly as `:66` two lines
  earlier. Every finding it listed turned out to be REAL and reproducible; the disposition was what failed.
- **Round 3** returned `VERDICT: GREEN` with "no new findings" in all six lenses, while its Lens 1 text
  described a regression that the round-2 fold had introduced. Measured: the original code left two body
  lines alone, the round-2 replacement deleted both.
- **Round 2** was the honest RED, and all four of its findings were real. Its verdict matched its body.

**Verify the FIX, not only the finding — proven twice in this one capstone, from both directions.** In
round 1 the peer's proposed regex was correct about the defect and harmful in its remedy: measured
one-for-one, it bought one evasion and cost one new false alarm, so it was refused and a narrower variant
shipped. In round 3 the harmful fix was MINE — a correct fix for a repeating sed range that quietly made
the no-frontmatter case worse. The same single line needed three attempts, and the first two each broke an
adjacent case.

**Severity was bounded by a fact found during review, not assumed before it:** the consult guard's MCP
path is classified structurally by tool name and returns before the shell regex is ever reached, so the
primary consult channel was never exposed to any of the classifier findings.

**The most reachable defect was in the verification step of a mechanism this same range had just shipped.**
The dispatch allow-list told the driver to check `git status --short`; measured, that command prints
nothing after a subagent commits a file outside its list, and implementer subagents commit by default. The
mechanism's own commit message says a list without a diff is theatre. It prescribed the wrong diff.

---

**Anomaly #1 (`.git/index` race) dispositioned 2026-08-02 — DELETED, suites exonerated by construction.**

Captured 2026-08-01: `fatal: .git/index: index file smaller than expected`, seen twice on stderr during a
per-file runtime measurement, after `abort-drain.Tests.ps1` and after `docs-audit.Tests.ps1`. The cause was
recorded as UNCONFIRMED at capture time, because the driver's own concurrent `git status` calls also write
`.git/index` — two candidate authors, and no basis to blame either.

**Settled from the CODE, which three attempted reproductions could not have settled.** MEASURED by audit:

- `scripts/tests/docs-audit.Tests.ps1`, `scripts/docs-audit.ps1` and `scripts/docs-audit-lib.ps1` contain
  **zero `git` invocations** between them; the single textual match is a comment at
  `docs-audit.Tests.ps1:555`. That suite is structurally incapable of touching any index.
- `scripts/tests/abort-drain.Tests.ps1` creates its repo under `[System.IO.Path]::GetTempPath()` (`:8`),
  and **every** git call in the file sits inside a `Push-Location $script:Repo` / `Pop-Location` pair —
  `:10-15`, `:34-37`, `:60-63`, `:99-101`, and `:105` inline. Zero unscoped calls.

Neither suite can reach the real repository's `.git/index`. The correlation with those two files is a
sampling artifact: at 261.3s and 120.6s they are the two longest in the partition and together span most
of a full run, so any ambient collision is overwhelmingly likely to land inside their window.

**The reproduction attempts are recorded because a negative result is worth keeping, not because they
decided it.** Three conditions, all clean: quiet (185.75s), with a `git status --porcelain` loop hammering
the index (271.9s), and the same with the loop's own stderr captured (347.99s, 0 bytes of stderr). Runtime
rising monotonically is the positive control that the contention was real rather than a loop that never
started. The capture path was separately proven to carry a git `fatal:` through `pwsh` into the log, so
these are real negatives and not empty-vs-empty passes.

**What this does and does not establish.** It establishes that no code in this repository caused it, which
is what makes it undeployable as a backlog item — there is no change here that would fix it. It does NOT
establish what did. The driver's own concurrent `git status` remains the leading candidate and was
demonstrably running at the time; an external Windows filter driver is another. That mechanism is INFERRED
and unproven, and is recorded as such rather than asserted.

**Durable driving rule, which is the part worth keeping:** do not poll git while a test suite is running.
The reader is the victim of a torn index, not its author, so a supervising `git status` can surface an
error it did not cause — and then be mistaken for evidence against the code under test.

**The remaining three anomalies, dispositioned 2026-08-02 — all DELETED, none a defect in this repo.**
Triaged by hand against the `open-issues` rule (promote with an owner, or delete with a recorded reason;
no parked state), because that skill is not yet installed on this machine. The anomaly file is gitignored,
so the reasons live here.

**1. "a Pester suite mutates the TRACKED `build/members.json`."** DELETED — the same misattribution as the
`.git/index` entry above, and found the same way. MEASURED: every `members.json` write in the suites
targets a fixture, not the repository. `check-plugin-namespace.Tests.ps1:14,54` writes under
`$env:TEMP/ns-clean-<pid>-<rand>` (`:7`); `check-member-docs.Tests.ps1:166` writes under
`$TestDrive/<guid>/build/` (`:157-158`); `check-roster.Tests.ps1:10` only READS the real file and sends
its own writes to `$TestDrive` (`:17,25,37`). No suite writes the tracked file. The emitter is a git
WRITE-op notice: that identical warning printed on many `git add` calls made by the driver during this
very session, and the driver was running git write-ops during the original measurement.

**2. "a `\uXXXX` escape written through the editing tool can arrive DECODED."** DELETED from this backlog,
and the observation kept as a driving rule instead. It is REAL and was reproduced twice — a subagent hit
it inserting mojibake signatures into two C# files, and the driver reproduced it deliberately (`A`
produced a bare `0x41`, confirmed by `od -c`). But the mechanism sits in the agent's editing harness, not
in this codebase: there is no change here that would fix it, so carrying it as a repo backlog item would
imply an owner who does not exist. The impact is worth restating because it is subtle — source that must
contain escape TEXT (mojibake signatures, regex character classes, test fixtures) can silently become
decoded non-ASCII that still compiles and still passes its tests, which is precisely the class the
`curate-commit` tripwire in this range exists to catch, arriving through the authoring path instead of the
transport. **Rule: after writing any escape literal, verify at byte level.**

**3. "`git commit -m` shell-expands its own message."** DELETED — not a defect at all, but correct and
documented shell behaviour, hit while writing a commit message that DOCUMENTED shell syntax. The
substitution executed, printed `command not found`, and the message committed as `X=.` with the documented
text gone. The commit SUCCEEDED, which is what made it silent; the corruption was visible only by reading
the message back, and cost an `--amend`. **Rule: write commit messages via a quoted-delimiter heredoc into
`git commit -F -` whenever the message contains `$( )`, backticks, or `${ }`.**

**The pattern across all four dispositioned entries is the finding.** Two of the original "suite defects"
were the driver's own tooling, misattributed to whatever happened to be running at the time, and a third
was standard shell semantics. Each was captured honestly — the `.git/index` entry explicitly recorded its
cause as UNCONFIRMED — but each would have been promoted as a code defect on the strength of correlation
alone. What settled all of them was reading the code, not re-running the scenario. **Correlation with a
long-running suite is not evidence about that suite; it is evidence about which window was widest.**

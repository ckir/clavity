# AGY-CAPSTONE ledger

One row per capstone. Appended before a plan may be declared complete.

**This is a RECORD, not a proof.** Nothing prevents someone appending a GREEN line without running
anything; a self-asserted ledger is the same shape as the re-stamping defect the verify gate removed.
Two things keep it honest, neither a guarantee: the `evidence` column must cite something independently
checkable, and the ledger is reviewed like any other artifact rather than trusted like a gate output.

**`none` is not a permitted evidence value.** A capstone that goes green on its first round still
produces a transcript — the rounds it ran, the lenses it seated, what it tried. Cite that. If there is
nothing to cite, the entry does not go in.

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

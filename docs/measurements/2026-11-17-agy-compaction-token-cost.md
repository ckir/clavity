# Does compacting agy's chat after a request save tokens? (measurement, 2026-11-17)

**Status:** measurement only. Nothing here changes how clavity drives agy and no change is proposed. agy 1.5.9.

**Short answer.** It depends on how a cache read is priced against fresh input. Counted in raw tokens
(uncached input plus cache read) compacting a ~146K-token chat before the next request is cheaper, net of the
compaction's own cost. Under an assumed weighting (cache read x0.1, output x5) it is slightly dearer. The two
readings disagree, so the measurement alone does not settle it; the sign flips at a cache-read price of about
0.17 of fresh input. The sample is two runs per arm at one context size, so this is a pointer, not a rule.

## Question

For the human whose agy quota or bill the pairing spends: after a request, does running agy's `/compact` before
the next request lower the tokens spent on that next request by more than the compaction itself costs?

## Method

- Four separate chats, each grown by the same fixed script (three read-only full-file reads through `agy_ask`)
  to a start context of about 146K tokens (145,851 / 146,645 / 147,037 / 144,994). Each ran one follow-up
  request: read a ~39 KB file and answer in a few lines. Two follow-up targets (T1, T2), each used once per arm.
- Arm A: send the follow-up as is. Arm B: a person types a bare `/compact` in agy, then the follow-up is sent.
  Run order A, B, B, A (T1, T1, T2, T2). Each run was verified to be in the intended chat before every ask.
- The cost of a run is the sum of the model calls of the follow-up only. The compaction call is not in the
  transcript's call list; its cost is added separately (C).
- Weighted figure: uncached x1 + cache read x0.1 + output x5. This is an ASSUMPTION, not agy's price list.
  Raw figure: uncached + cache read, output reported apart.
- Verdict rule fixed before any run, from the saving interval `lo = min(A) - max(B)`, `hi = max(A) - min(B)`
  and the measured C range: "saves" only if `lo > C_hi`; "does not save" only if `hi < C_lo`; otherwise
  "net effect unknown".
- Spend for the whole measurement: about 6.6M raw tokens (a 10M ceiling was set beforehand).

## Runs

| run | arm | target | start ctx | calls | processed (raw) | weighted | output | first-call cache read | idle gap s | checkpoints | oracle | reads | flags |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | A | T1 | 145851 | 2 | 306101 | 51506 | 1308 | 143830 | 16.0 | 0 | ok | 1 |  |
| 2 | B | T1 | 146645 | 2 | 46714 | 38482 | 1352 | 0 | 48.0 | 1 | ok | 1 | COLD |
| 3 | B | T2 | 147037 | 3 | 80338 | 76443 | 7456 | 0 | 39.0 | 1 | ok | 2 | COLD |
| 4 | A | T2 | 144994 | 3 | 466681 | 93714 | 5740 | 142971 | 20.0 | 0 | ok | 2 |  |

## Compaction cost C (arm B)

| run | uncached | cache read | output | C raw | C weighted | flags |
|---|---|---|---|---|---|---|
| 2 | 3156 | 144582 | 1549 | 147738 | 25359 |  |
| 3 | 3178 | 145013 | 2514 | 148191 | 30249 |  |

## Verdict

### weighted units
- arm A: min 51506, max 93714, spread 42208
- arm B: min 38482, max 76443, spread 37961
- saving interval (lo, hi): (-24937, 55232)
- C range: 25359 to 30249
- per-run net (total_B + C_B) against mean of arm A (72610): run 2: 63841 (-8769), run 3: 106692 (34082)
- n* (calls to repay C): 4.6
- verdict: net effect unknown, pays off above n* calls

### raw units
- arm A: min 306101, max 466681, spread 160580
- arm B: min 46714, max 80338, spread 33624
- saving interval (lo, hi): (225763, 419967)
- C range: 147738 to 148191
- per-run net (total_B + C_B) against mean of arm A (386391): run 2: 194452 (-191939), run 3: 228529 (-157862)
- n* (calls to repay C): 1.1
- verdict: saves

VERDICT FLIPS between raw and weighted units

## Paired by target (same file, same start context, arm A against arm B plus its compaction)

| target | raw A | raw B + C | weighted A | weighted B + C |
|---|---|---|---|---|
| T1 (runs 1, 2) | 306101 | 46714 + 147738 = 194452 | 51506 | 38482 + 25359 = 63841 |
| T2 (runs 4, 3) | 466681 | 80338 + 148191 = 228529 | 93714 | 76443 + 30249 = 106692 |

Raw: compacting first is cheaper by 111,649 (T1) and 238,152 (T2), net of C. Weighted: it is dearer by 12,335 (T1) and 12,978 (T2), net of C.

## Post-hoc sensitivity (NOT part of the pre-set verdict rule; exploratory, n = 2 pairs)

How the net result moves with the price of a cache read relative to uncached input (output kept at x5). A positive last column means compacting first costs MORE than not compacting.

| cache-read price (x uncached) | T1: A | T1: B+C | T2: A | T2: B+C | mean A | mean B+C | B+C minus A |
|---|---|---|---|---|---|---|---|
| 0.05 | 36998 | 55779 | 71399 | 97154 | 54199 | 76467 | +22268 |
| 0.1 | 51506 | 63841 | 93714 | 106692 | 72610 | 85267 | +12657 |
| 0.25 | 95028 | 88027 | 160658 | 135307 | 127843 | 111667 | -16176 |
| 0.5 | 167566 | 128337 | 272232 | 182998 | 219899 | 155667 | -64232 |
| 1.0 | 312641 | 208957 | 495381 | 278379 | 404011 | 243668 | -160343 |

Reading: with the assumed 0.1 weight the compaction does not pay back for either target; the sign flips at a cache-read price of about 0.17 of fresh input (linear interpolation between the 0.1 and 0.25 rows: +12,657 and -16,176); above that, or whenever the bill counts raw tokens, it does pay back. The agy user's real price ratio decides which unit matters, and it was not measured here.

## Sanity checks

- Oracles: all four passed on the pre-set text (583 and `## 3. Testing` for T1; 844 and `## Preflight` for T2; every probe made at least one read call on its target file). Both T2 replies hedged with an extra note about `## Self-review` when fenced code blocks are excluded; this made the final call long (5,394 and 6,945 output tokens), which inflates the weighted figure for T2 in both arms (output is weighted x5). T1 replies were short.
- Exclusions: none. Arm A runs had 0 checkpoints; arm B runs had exactly 1 (the owner-typed `/compact`), whose own row is excluded from the probe totals by `from_step`.
- Start contexts: 145,851 / 146,645 / 147,037 / 144,994, all within 15,000 of each other (maximum spread 2,043).
- Cache temperature: arm A probes were hot (first call read 143K / 143K from cache, idle gap 16-20 s). Arm B probes show `COLD` on the first call by construction (the summary is new context, so nothing is cached; 16.5K tokens uncached on the first call, 2 of 2). Both compactions themselves were hot (cache read 145K of 148K). The idle gap between compaction and probe was 39-48 s.
- C was read live from a copy of the conversation database (mode=ro, with the WAL); the transcript's own CHECKPOINT row carried identical numbers in both runs and in the gate chat.
- Spend: about 6.64M raw tokens in total for step 2 (ceiling 10M; the 5M ask was answered "continue" at 3.39M). Output tokens are not in that figure.
- agy version 1.5.9.

## What this result does and does not say

- It is two runs per arm at one context size (about 146K), one model (unnamed in the transcripts), and one request shape (read a ~39 KB file, answer in a few lines). It does not say anything about other context sizes, other request shapes, or compacting after every request. The verdict rule's "saves"/"does not save" thresholds were built for exactly this small sample and are conservative.
- The raw and weighted units disagree, so the sign depends on the cache-read price, which this measurement cannot supply.
- Compaction was typed by hand as a separate turn rather than `/compact <message>` (the driver cannot send slash commands); the compaction cost and the follow-up were measured separately, so the totals are unaffected, but a single combined turn was not tested.
- Break-even: n* is 1.1 calls in raw units and 4.6 calls in weighted units, using this probe's calls per request (2-3). Each request here costs only 2-3 calls, so a user who sends one more request after compacting recovers the cost in raw terms, but in weighted terms needs about five calls' worth of savings.

## Findings about agy worth keeping

- A compaction's own token cost is observable. It is stored in the conversation database
  (`~/.gemini/antigravity-cli/conversations/<cascade_id>.db`, table `steps`, `step_type = 23`; the `metadata`
  protobuf field 28, then its field 2, holds varints 2 = uncached input, 3 = output, 5 = cache read, absent
  meaning 0). The transcript's `CHECKPOINT` row carries the same three numbers in the chats written since
  2026-11-04 (the older ones carry none). In this measurement they were identical in all three live compactions (the gate chat and runs 2 and 3); across history
  95 of 96 cross-checked rows matched.
- `agy_status.CascadeId` is the trajectory id, not the brain-folder id. The brain folder and database are named by
  `trajectory_meta.cascade_id` in the database.
- A copy of a live database must be opened without `immutable=1` when its `-wal` is included; with it the
  uncommitted tables are invisible ("no such table").
- agy's `view_file` header reports "Total Lines" as `wc -l` + 1. A line-count oracle should accept N or N+1.
- The `agy_ask` driver delivers `/compact ...` as plain text wrapped in the user request, so agy treats it as
  conversation, not as a command, and no compaction happens. A person has to type it in agy.
- History (all local transcripts, 335 compactions with a measured cost): a compaction with a warm cache
  (cache read above 0; 287 of 335) had a median pre-compaction context of 248K and cost about 45K weighted; a cold
  one (48 of 335) cost about 160K weighted. A cold cache is common enough that a result can swing on it.
- Auto-compaction fires at about 250-270K tokens of context; the runs stayed clear of it.

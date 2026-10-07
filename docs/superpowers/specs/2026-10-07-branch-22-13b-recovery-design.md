# Branch 22 — `[13b]` reply recovery: design spec

**Status:** v2 - AGY-FIRST done (seam `.clavity/seams/b22-agy-first-forks.md`); owner ruled the capture shape "BOTH"; the remaining sub-choices are PROPOSED DEFAULTS below, approved with the spec after the AGY-AFTER panel.
**ROADMAP:** `clavity-dotnet/ROADMAP.md` section 74. **Branch:** `sweep/branch-22-13b-recovery` (from `main` `500b3428`).
**Owner rulings already made (2026-10-07):** a separate branch before Branch 21 phase 1; scope FULL — (a) every
`[13b]` notice and the four discipline skills name the same recovery order; (b) `agy_ask` with a `discipline`
itself asks the peer for a reply file; (c) `clavity-ls` reads that file to run the `[13b]` checks. Defect 2's
matching rule is decided (below).

## 1. Problem (measured)

- **D1 — no named recovery.** `McpTools.cs:90-107`: TRUNCATED REPLY says "Recover with agy_look or re-ask"; ECHO
  MISSING names nothing. The four skills say the same (`agy-first/SKILL.md:52`, `agy-capstone:54`,
  `agy-test-audit:81`, `adversarial-panel-review:138`, each byte-identical in `clavity-classic/plugin/skills/`).
  `agy_look` caps each step at `MaxStepTextChars = 1000` (`BoundedView.cs:23`), so it cannot recover a long report.
- **D2 — false ECHO MISSING.** `SemanticEcho.Normalise` (`:198-199`) trims decoration at the line ENDS only; a peer
  that escapes inner backticks never matches. Reproduced with a control.
- **D3 — answers that lose their verdict in transit.** The reply text the checks see is only the TRAILING run of
  assistant steps (`BoundedView.cs:107-124`): a reply whose last step is a tool call yields `Answer = null` by
  design, and an answer over `AskMaxStepChars = 16_000` keeps its HEAD (`:126-130`), so its terminal token is cut.
  Both read as TRUNCATED REPLY although the peer produced a complete report.
- **Stale doc (fold).** `SemanticEcho.cs:11-17` says "the language server never learns which file a consult is
  about"; `ExpectedFrom` (`:47`) reads the artifact itself.

## 2. What exists today (from the code map, verified)

- The outgoing message is the raw ask, by design (`AgyView.cs:210-213`, "T4b audience split": driver guidance goes
  to the RESULT via `TryTakeGuidanceBlock`, never to the peer).
- No C# code creates or shields a repository `.clavity/` (that is bash: `agy-mark.sh prepare` + `agy-shield-lib.sh`).
- No workspace-root concept: a relative `artifactPath` resolves against the server's working directory, which is the
  repository root in practice (every relative artifact path used on 2026-10-07 resolved; no ECHO WEAK appeared).
- The classic driver (Rust, `clavity ask --review-only`) carries neither `discipline` nor `artifactPath`; its
  skills say so and verify the echo by eye.

## 3. Contracts

**Owner ruling 2026-10-07 (after AGY-FIRST):** BOTH capture paths. agy's unnamed option - the server captures the reply
itself - runs on EVERY ask; the peer-written file is a SECOND copy, requested only when a known `discipline` is named.

- **C-echo (D2, decided).** `SemanticEcho.IsSatisfied` is SATISFIED when, within the existing tail window
  (`TailLines = 3`), some line satisfies ANY of: raw line contains the needle; the reply line with markdown escapes
  removed contains the needle; both sides with escapes removed match. Escape set: a backslash before one of backtick,
  `*`, `_`, `>`, backslash. Driver-tested on 7 cases (accepts the 4 honest forms; rejects a different line, a
  truncated prefix, a one-word change).
- **C-capture (server side, every ask).** After the wait (`AgyView.AskAsync`, after `WaitForIdleWithProgressAsync`),
  the server writes the FULL text of every assistant step in this ask's delta - untruncated, in order, each step preceded by the
  line `----- agy step <index> -----` (index = the step's position in the trajectory) - to `<user-profile>/.clavity/agy-replies/<cascade-id>-<first-step-index>.md`, under a size cap
  (PROPOSED: 1 MiB; over it, the first 768 KiB and the last 128 KiB are kept with the line
  `----- cut: <n> characters omitted -----` between them, so the verdict at the end survives). The user-profile `.clavity` is already this server's data directory (`SessionPaths.cs:12`) and
  is not inside any repository, so no shield is involved. The result JSON gains `replyFile` (absolute path) and every
  `[13b]` notice names it. **A failed capture never fails the ask** (panel R1, CA1): on any IO error the ask returns as
  today, `replyFile` is `null`, the result gains `captureError: <one-line reason>`, and every notice drops recovery step
  (1) and says the capture failed - a notice must never send the driver to a file that does not exist.
- **C-check (D3).** The `[13b]` checks run on the UNTRUNCATED trailing assistant run (the same run `Answer` is cut
  from), not on the 16 000-char head copy - so a long but complete reply keeps its terminal token. When `AnswerTruncated` is true the result says so and points at
  `replyFile` EVEN IF every check passed (panel R1: a passing verdict must not hide that `Answer` is cut). A trailing TOOL step
  still yields `Answer = null` (the "failure not hidden" design in `AskReplyProjectionTests` is kept); the notice then
  points at `replyFile`, which holds the text.
- **C-request (peer side, discipline named).** The outgoing message gains a short appended block asking the peer to
  ALSO write its whole reply verbatim to `<root>/.clavity/scratch/agy-replies/<cascade-id>-<first-step-index>.md`,
  with a server-generated nonce as the file's FIRST line, exactly `agy-reply-nonce: <32 lowercase hex>` (a fresh
  `Guid.NewGuid().ToString("N")` per ask; panel R1, PP1). This is a RECORDED EXCEPTION to the T4b "raw ask only" note
  (`AgyView.cs:210-213`): the appended block is peer-facing completion protocol, never driver guidance; the note is
  amended to say so. Ordinary asks (no discipline) are unchanged.
- **C-peer-read.** If the chat text (C-check) FAILS a check and the peer file exists with the matching nonce on its
  first line, is at most 1 MiB (the same cap as C-capture; a larger peer file is NOT read - the result says so and
  the chat verdict stands; panel R3, LI1), and passes, the reply is reported complete AND the result's `Answer` is the PEER
  FILE's text - BOUNDED EXACTLY LIKE A CHAT `Answer` (`AskMaxStepChars`, head kept, `AnswerTruncated` set, and the result
  pointing at the peer file for the rest; panel R4, FA1: the checks run on the whole file, but the 16 000-character
  context bound is never bypassed) (agy F4: the text that passed is the text the driver receives - never check one text and surface
  another). When the chat answer was null because the turn ENDED ON A TOOL STEP, the rescue still reports complete (a
  nonce-correct file that passes the token and echo checks IS a complete report by the discipline's own test) but the
  result carries `turnEndedOnToolStep: true` and a notice saying so - the "failure not hidden" design
  (`BoundedView.cs:121-122`) is kept by REPORTING the tool-ended turn, not by declaring a complete report incomplete
  (panel R1, AB1/MG1). The result says which source passed: `checkedSource: chat | peer-file` (panel R1: `capture` was dropped - the checks never run on the full capture, whose
  last line in the measured failure is the same bare acknowledgement that failed the chat check).
- **C-order (D1 wording).** Every flagged notice and all four skills (both plugins) name ONE recovery order: (1) read
  `replyFile` WHEN THE RESULT NAMES ONE - its END first: the verdict, the echo and the json sit at the TAIL of a file
  that can reach 1 MiB, so the notice says "read its last 200 lines" rather than leaving the agent to page from the
  top (panel R4, OA1) (the skills are static text and cannot promise it: a failed capture leaves it
  `null` - panel R2, FA1); (2) read the peer file if it was requested; (3) re-ask AT MOST ONCE; (4) halt and ask
  the human. `agy_look` is named only as a SHORT-reply tool with its 1000-character step cap stated. ECHO MISSING
  gains the same steps. When NO file is available (capture failed AND no peer file), the notice says so and names the
  two steps left - `agy_look` for a short reply, then the single re-ask - so it never ends on a dead end (panel R2, BA2).
- **C-doc.** `SemanticEcho.cs` header comment corrected (the class reads the artifact itself now).

## 4. Proposed defaults for the remaining sub-choices (agy's recommendation unless stated)

- **D-root (F1).** `<root>` for the PEER file = the server's working directory - the same base `ExpectedFrom` already
  resolves `artifactPath` against, measured to be the repository root on 2026-10-07. agy recommended its own
  workspace via `GetConversationMetadataAsync` (`LsClient.cs:55`, unused today); the driver's lean differs because a
  second root concept would let the artifact and the reply resolve against different directories. **Owner to rule.**
- **D-name (F2).** Unique per ask (`<cascade-id>-<first-step-index>`) + a nonce first line (defeats a stale or
  touched file; mtime is not trusted).
- **D-shield (F3).** Refuse-and-degrade: request the peer file ONLY when `<root>/.clavity/.gitignore` already holds a
  bare `*` line; otherwise do not append the block and say so in the result. The server never writes the shield.
- **D-prune (F6).** Keep the newest 50 files per location (count, not age: agy - long sessions defeat an age rule),
  each location pruned on ITS OWN event - the capture directory after every capture write ATTEMPT, the peer-file
  directory whenever a peer file was requested - so a capture that keeps failing cannot let peer files grow without
  bound (panel R2, RV1). Pruning is best-effort and never fails the ask.
- **D-classic (F7).** Classic's TRANSPORT is unchanged (it carries no `discipline`), but its four skills are NOT
  reworded separately: `scripts/check-seed-artifacts-synced.sh` byte-diffs every file under `skills/` between the two
  plugins and exempts only the four transport twins (`driving`, `responder`, `ls-driving`, `ls-pairing`) - a
  classic-only wording turns that gate red (panel R3, AA1, measured). So the four discipline skills keep ONE shared
  text, as they already do for the `discipline`/`artifactPath` parameters ("On clavity-classic neither parameter
  exists"): the recovery paragraph names the dotnet `replyFile` step AND says that on classic the driver requests the
  peer file by hand in its brief.

## 5. Out of scope

The bash shield's semantics (section 41 stays deferred); Branch 21's hooks; `agy_look`'s caps.

## 6. Stand-downs (AGY-AFTER panel)

- `DISCARDED-BELOW-FLOOR` (R1 solo, Boundary Smuggler): a symlink planted at the peer-file path makes the server read and
  surface another local file - same-user only, inside the accepted same-user trust boundary
  (`clavity-dotnet/ROADMAP.md`, "Non-goals / accepted limitations": "Same-user trust boundary").
- `DISCARDED-BELOW-FLOOR` (R1 agy, SC1): peer text that happens to equal the capture's cut-marker line is cosmetic only -
  no check ever parses the capture file (C-check runs on the chat trailing run; C-peer-read on the peer file).
- `REJECTED` (R2 agy, BA1): "reporting a rescued tool-ended turn complete crashes the session because the driver must
  supply a tool result" - agy runs its own tools; the driver only ever sends `SendUserCascadeMessageAsync` and waits for
  idle (`AgyView.cs` `AskAsync`), and today's own recovery for that exact turn is a re-ask. agy withdrew it after
  reading both files.
- Declined (R4 agy, open-question answer, not a finding row): "C-peer-read is unnecessary - remove it". The owner ruled
  BOTH capture paths knowingly; C-peer-read is what turns a report-then-bare-acknowledgement reply into a COMPLETE result
  without a re-ask. Its one real hazard (an unbounded `Answer`) was folded as R4 FA1.

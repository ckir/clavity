---
slug: token-mismatch-and-not-last-both-read-as-truncated
variant: clavity-dotnet
observed: 2026-10-07
source-inbox-entry: "- [anti-pattern] (driver/deterministic) When the driver tool owns the terminal-token table (the discipline is passed"
status: open
---

# A wrong token and a token that is not last are both reported as `[13b] TRUNCATED REPLY`

## Steps to Reproduce

Three shapes, all observed live on `mcp__plugin_clavity_clavity-ls__agy_ask` (dotnet 0.10.2), in three
sessions (2026-10-07, 2026-10-09 twice):

1. **Token mismatch.** Pass `discipline: "adversarial-panel-review"` and a brief that dictates its own
   closing line, `[VERDICT: GREEN]`. The peer complies and ends exactly so. `DisciplineContract` expects
   `PANEL VERDICT` for that discipline (`clavity-dotnet/src/Clavity.Ls/DisciplineContract.cs:30-33`);
   `TerminalToken.IsSatisfied` (`TerminalToken.cs`) compares only the last non-blank line, start-with, so
   the reply is reported `[13b] TRUNCATED REPLY: the terminal token this discipline requires is missing or
   not at the end` (`clavity-dotnet/src/Clavity.Mcp/McpTools.cs:90-97`). Nothing was truncated.
2. **Token not last.** Pass `discipline: "agy-capstone"`. The peer writes a complete report, the
   `[VERDICT: FINDINGS]` line, and THEN its echo line (quoted from the artifact) or a stale leftover line
   from drafting. Same flag, same wording. The report is complete and the driver must not fold from the
   flag; measured, the scratch file the peer had been told to write carried the full report.
3. **Capped by the bridge.** A reply over `AskMaxStepChars` is cut from the TAIL by
   `BoundedView.ProjectAskReply` (`answer[..AskMaxStepChars]`), which removes the token itself; the
   same flag again, with the cause being the bridge, not the peer. Tracked separately as the umbrella
   stub `docs/backlog/agy-reply-channel-truncates-and-nulls-silently.md` (addendum 2026-10-11).

In every shape the driver's instruction is identical - "Recover with agy_look or re-ask" - although the
correct action differs: (1) fix the brief, (2) read the reply as complete and tell the peer about the
ordering, (3) read the scratch file or raise the cap. A flag that names one cause for three conditions
sends the driver to the wrong recovery two times in three, and each wrong recovery is a paid re-ask.

## Code-level Mitigation

`TerminalToken.IsSatisfied` returns a `bool`; make it return a reason and let `McpTools.cs:90` print it:

- `Satisfied` - unchanged.
- `TokenAbsent` - the expected token starts no line anywhere in `Answer`. Keep today's wording; this is
  the genuine truncation / stopped-mid-thought case.
- `TokenNotLast(lineIndex, trailingLines)` - the token starts a line that is not the last non-blank one.
  Report `[13b] TOKEN NOT TERMINAL: "<token line>" is followed by N line(s): <first trailing line,
  elided>`. The reply is complete; the breach is ordering. Do not tell the driver to re-ask.
- `TokenMismatch(expected, actualLastLine)` - the last non-blank line, after `IsDecoration` stripping,
  starts with a different discipline's token (any entry of `DisciplineContract.Tokens`) or with
  `VERDICT`-like text. Report `[13b] TOKEN MISMATCH: discipline "<d>" expects "<expected>", the reply
  ends with "<line>" - the BRIEF dictated a different token; fix the brief, the reply is complete`.

The existing `IsSatisfied(answer, expected)` can stay as a thin wrapper (`== Satisfied`) so
`DisciplineContractTests` and the `[`-stripping invariant tests keep their shape. Pinning tests, one per
reason, with the three observed reply shapes above as fixtures; the control is the existing truncated
shape ending `"VERDICT: ALIGNED\n["`, which must still read `TokenAbsent`/not satisfied.

## Notes

Deterministic on dotnet only: classic's `clavity ask --review-only` has no `discipline` parameter and
runs no 13b check, so there the observation is a carried driving rule (verify the token by eye). The
driving-side workaround is carried in the cheatsheet GROWTH as of 2026-10-11 ("a bridge flag is a verdict
about the reply's SHAPE ... read the tail of the scratch file before any re-ask") and must not be retired
when this ships; end-users on older builds keep seeing the one-cause flag.

Adjacent: `answer-null-content-only-in-truncated-activity` (Answer null, content in Activity) and
`terminal-step-kind-signature-not-surfaced` (naming WHICH failure a null answer was). This item is the
same principle - name the cause - applied to a NON-null answer that carries a token in the wrong place or
of the wrong discipline.

## Addendum 2026-10-26 - a fourth shape, hypothesis from code reading, not yet measured

An inbox entry drained 2026-10-26 reports the flag firing while the reply file's tail ALREADY held the
echo line and the terminal token, "because the chat capture and the file capture diverge". The driving
move (read the last 200 lines of the file before spending the re-ask) is the carried cheatsheet rule and
was enough to recover; the mechanism was not isolated at capture time.

One candidate mechanism is visible in the code and is recorded here so the next measurement starts
from it rather than from zero: `Evaluate13b` (`AgyView.cs:294-310`) judges only the TRAILING assistant
run (`BoundedView.TrailingAnswer`, `BoundedView.cs:163-168`, which returns null unless the delta ENDS on
an assistant step), while `ReplyCapture.Write` renders EVERY assistant step of the delta. A turn whose
last step is a tool step - the peer writing or re-reading a file after its chat reply - therefore reads
as token-absent in chat while the capture file holds the complete reply, and the peer-file rescue
(`AgyView.cs:268-269`) runs only when a peer file was requested. If measured, the mitigation is: when
`TurnEndedOnToolStep` is true, judge the LAST assistant run rather than requiring it to be trailing
(or judge the rendered capture text the way `RescueFromPeerFile` judges the peer file). Unmeasured -
reproduce before building; the entry stays a carried rule either way.

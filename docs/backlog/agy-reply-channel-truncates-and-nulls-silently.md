# Backlog stub - the agy reply channel truncates and nulls, and both look like something else

**Status:** OPEN. Promoted 2026-08-27 from `.clavity/local-anomalies.md` (2 entries).
**Raised:** capstone rounds 7 and 8, 2026-08-25.
**Scope:** `agy_ask` / `agy_look` and the four AGY-* disciplines that consume them.

## Two failure modes, both silent at the call site

**1. A long reply is CUT MID-SENTENCE.** `AskMaxStepChars = 16_000` (`BoundedView.cs:27`) hard-caps
`Answer` at `:126-130` and sets `AnswerTruncated`. MEASURED 2026-08-25: capstone round 8 lost the whole
of Seat 2 plus the tail of Seat 1 - the text stopped mid-word at "spans tw". `agy_look` truncates too.

**2. `Answer: null` with `Diagnostic: null`** whenever the peer cascade ends on a TOOL step rather than
assistant prose - BY DESIGN (`BoundedView.cs:121-124`). At the call site that is indistinguishable from
an unreachable peer or an exhausted quota, while the completed analysis still sits in the trajectory.
MEASURED in capstone round 7.

## Relationship to ROADMAP 13b - related, NOT the same, and 13b has shipped

`13b` ("no discipline requires a peer's ANSWER to survive truncation") SHIPPED 2026-08-20 (`20f38cc`,
capstone GREEN after 11 rounds). It made the reply PERSIST. **These two entries were captured on
2026-08-25, AFTER that fix**, and they are the adjacent problem it did not cover: persistence does not
tell the driver that a reply was cut, nor distinguish a by-design null from a dead channel. A driver that
reads a truncated round as a complete one draws a conclusion from evidence it does not have.

## Addendum 2026-10-11 - the Answer cap drops the TAIL, which is where the 13b evidence lives

Observed live (two sessions, 2026-10-08 and 2026-10-09, dotnet 0.10.2) and re-read in the code today:
`BoundedView.ProjectAskReply` caps `Answer` with `answer[..AskMaxStepChars]` - it KEEPS THE HEAD. The
activity projection in the same method already does the opposite ("drop from the HEAD until it fits
(preserve the tail)"). Because every AGY-* discipline puts its echo line, its JSON block and its terminal
token LAST, a capped reply loses exactly the three things `Evaluate13b` then looks for, so the same reply
is ALSO reported `[13b] TRUNCATED REPLY` - a true statement with a misleading cause (the bridge cut it, not
the peer), and the driver's only recovery is the scratch file the peer was told to write.

Mitigation sketch, additive to the two modes above: when `answer.Length > AskMaxStepChars`, keep the head
AND the last ~2 KB (marker between them), or at minimum run the 13b checks on the UNCAPPED text before
capping; and name the cause in the flag ("capped by the bridge at N chars" vs "token absent in the peer's
text"). Driving-side workaround carried in the cheatsheet GROWTH: demand a short chat reply, full analysis
in a scratch file.

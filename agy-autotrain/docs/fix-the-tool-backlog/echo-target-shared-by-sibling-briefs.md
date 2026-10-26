---
slug: echo-target-shared-by-sibling-briefs
variant: clavity-dotnet
observed: 2026-10-26
source-inbox-entry: "- [anti-pattern] (driver/deterministic) When two review briefs share a filename prefix (a round-one brief and its re-ask)"
status: OPEN
---

# The echo check keys on the artifact's last line, which a round-one brief and its re-ask can share

## Steps to Reproduce

On `mcp__plugin_clavity_clavity-ls__agy_ask` (dotnet), observed live 2026-10-26:

1. Write a round-one brief `.clavity/scratch/<topic>/brief.md` and, after the round, a re-ask brief
   `.clavity/scratch/<topic>/brief-r2.md`. Both end with the same closing instruction (the discipline's
   standard ending block), so the LAST SUBSTANTIVE LINE of the two files is identical.
2. Fire the re-ask with `discipline: "<d>"` and `artifactPath: ".clavity/scratch/<topic>/brief-r2.md"`.
3. The driver derives the expected echo from `artifactPath` alone
   (`clavity-dotnet/src/Clavity.Ls/SemanticEcho.cs` `ExpectedFrom`, called from
   `clavity-dotnet/src/Clavity.Mcp/McpTools.cs:60`): the last line carrying at least the minimum of
   letters or digits. Because the two briefs share that line, the expectation is the same string for
   both.
4. The peer, having both files open under one prefix, reads and echoes the tail of the ROUND-ONE brief. The echo
   check (`SemanticEcho.IsSatisfied`, `AgyView.cs:298`) PASSES, because the quoted line is the same
   text - the check cannot tell which artifact was read. Conversely, when the two briefs differ only in
   their closing line, the peer's echo of the sibling's tail FAILS the check against the right artifact,
   and the notice sends the driver to a re-ask for a reply that is complete.

The driving-side workaround - a distinct end-marker string per brief naming its round and range - is
carried in the cheatsheet GROWTH as of 2026-10-26 and must not be retired when this ships.

## Code-level Mitigation

The driver already generates a per-ask nonce and appends it to the outgoing message in the REPLY FILE
block (`PeerReplyFile.RequestBlock`, `AgyView.cs:233`), but only the peer FILE is checked for it
(`PeerReplyFile.TryRead`). Make the completeness protocol key on that nonce in CHAT as well:

- Append to the outgoing message, for every discipline ask, one line the peer must reproduce verbatim
  immediately before the terminal token: `agy-ask-marker: <nonce>` (the same nonce the reply file
  carries, so one value serves both copies).
- In `Evaluate13b`, require that marker line within `SemanticEcho.TailLines` of the end, in addition to
  the artifact echo. A reply quoting the sibling brief's tail but carrying this ask's marker is a
  complete reply to THIS ask (echo verdict stands as today); a reply carrying ANOTHER ask's marker, or
  none, is reported `[13b] MARKER MISSING: the reply does not carry this ask's marker` - a new reason,
  not folded into TRUNCATED, because the recovery differs (the reply may belong to a different round).
- Pinning tests: two fixture briefs with identical last lines; a reply echoing the sibling's tail with
  the right marker passes; the same reply with the previous ask's marker is flagged MARKER MISSING;
  the control is today's echo-missing fixture, which must still read EchoMissing.

## Notes

Deterministic on dotnet only: classic's `clavity ask --review-only` runs no echo check, so there the
observation is a carried driving rule (verify by eye which brief the echo quotes). On dotnet the driver
owns both the expectation and the nonce, so the ambiguity is removable in the execution path rather
than by brief wording.

Adjacent: `token-mismatch-and-not-last-both-read-as-truncated` (one flag naming one cause for three
conditions). This item is the same principle applied to the ECHO half of the check: the echo proves a
line was quoted, not which file it came from.

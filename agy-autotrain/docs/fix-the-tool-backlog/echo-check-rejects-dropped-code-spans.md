---
slug: echo-check-rejects-dropped-code-spans
variant: clavity-dotnet
observed: 2026-11-07
source-inbox-entry: "- [anti-pattern] (driver/probabilistic) A verbatim-echo completeness check fails when the line to be echoed"
status: OPEN
---

# The echo check fails an honest echo when the peer drops a line's inline backticks

## Steps to Reproduce

On `mcp__plugin_clavity_clavity-ls__agy_ask` (dotnet), observed live 2026-11-07:

1. Write a brief whose last substantive line contains an inline markdown code span, e.g.
   ``Then run `just test` and report.``
2. Fire it with a `discipline` and `artifactPath` pointing at that brief. `SemanticEcho.ExpectedFrom`
   takes that line as the expected echo.
3. The peer quotes the line without backticks: `Then run just test and report.`
4. `SemanticEcho.IsSatisfied` (`clavity-dotnet/src/Clavity.Ls/SemanticEcho.cs:182`) returns false and the
   reply is flagged ECHO MISSING, even though the peer read to the end. `Normalise` (`:238`) strips
   backticks only at the ENDS of a line, and `Unescape` removes only backslash escapes (`` \` ``). Neither
   handles backticks the peer dropped from inside the line, so `"Then run just test and report."` never
   contains `` "Then run `just test` and report." ``.

## Code-level Mitigation

In `IsSatisfied`, add a fourth accepted form: compare with every backtick removed from both sides, i.e.
`StripTicks(bare).Contains(StripTicks(bareNeedle))` where `StripTicks` deletes all `` ` `` characters.
Add a pinning test in `SemanticEchoTests` with the line above. The `IsUsableExpectation` thinness check
must run on the stripped needle too, so a line made of code spans can't shrink to something too thin to
discriminate.

## Notes

- classic: N/A. It has no semantic-echo check (no counterpart of `SemanticEcho` in `clavity-classic/src`).
- Carried driver-cheatsheet clause until fixed and adopted: "Pick an echo line with no inline code
  spans: the peer drops the backticks." Retiring it follows the two-gate rule in the template header.

---
slug: echo-source-bound-to-artifact-path
variant: clavity-dotnet
observed: 2026-11-24
source-inbox-entry: "- [anti-pattern] (driver/deterministic) When the echo line the peer must quote lives in the brief, pass the brief"
status: OPEN
---

# The expected echo is derived from `artifactPath` alone, so a brief that carries the echo line cannot name the reviewed artifact

## Steps to Reproduce

On `mcp__plugin_clavity_clavity-ls__agy_ask` (dotnet), observed live 2026-11-24 (inbox capture; the code path
below was confirmed by reading the source, not re-run for this item):

1. Write a brief `.clavity/scratch/<topic>/brief.md` whose last substantive line is the echo line the peer is told to
   quote. The brief points the peer at a reviewed artifact `src/<file>` (a different file with a different last line).
2. Fire the ask with `discipline: "<d>"` and `artifactPath: "src/<file>"` (naming the artifact under review).
3. The driver derives the expectation from `artifactPath` only: `clavity-dotnet/src/Clavity.Mcp/McpTools.cs:78`
   calls `SemanticEcho.ExpectedFrom(artifactPath)`, which returns the last line of THAT file
   (`clavity-dotnet/src/Clavity.Ls/SemanticEcho.cs:52`). The peer quotes the brief's echo line as instructed, so the
   completeness check looks for the artifact's last line, does not find it, and flags a complete reply as incomplete.

The ask has exactly one file parameter, so a caller cannot name both "the file the echo line lives in" and "the file
under review". The driving-side workaround (pass the brief as `artifactPath`) is carried in the cheatsheet GROWTH
as of 2026-11-25 and must not be retired when this ships.

## Code-level Mitigation

Add an optional `echoSourcePath` argument to `agy_ask` (`McpTools.AgyAsk`, `McpTools.cs:48-51`), defaulting to
`artifactPath` so every existing caller is unchanged. Compute `expectEcho` from `echoSourcePath ?? artifactPath`
(`McpTools.cs:78`). Keep the `[13b] NO ECHO` notice (`McpTools.cs:187`) keyed on whether EITHER path was supplied, so
naming only an echo source does not read as "no artifact". Reuse `ExpectedFrom` unchanged, so the regular-file, size-cap
and FIFO guards apply to the new path too. Update the `agy_ask` tool description and `ArgumentPrecheck`'s optional-argument
list for the new name.

Pinning tests: a brief whose last line differs from the artifact's; `echoSourcePath` = brief with a reply echoing the
brief line passes and the same reply with `artifactPath` alone is flagged (today's behaviour, the control); a
`echoSourcePath` naming a FIFO or directory degrades to nothing claimed, like `artifactPath`.

## Notes

Deterministic on dotnet only: classic's `clavity ask --review-only` runs no echo check, so there it is not reachable.
Related, not duplicates: `echo-target-shared-by-sibling-briefs` (two briefs share a last line; closed by ruling) and
`echo-check-rejects-dropped-code-spans`. Overlap with the first item: both stem from the echo being keyed on one
caller-named file.

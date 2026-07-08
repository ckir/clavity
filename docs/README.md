# docs/ — umbrella & cross-cutting docs

This directory holds **umbrella / cross-cutting** documentation only — things that span the whole
`clavity` multi-tool repo. It is the consistency guard for two decisions:

- **New tools (D4):** put tool-specific docs **beside the plugin** — `plugins/<tool>/README.md`
  (operator) and optional `plugins/<tool>/docs/` (design). Not here.
- **clavity is the grandfathered exception (D5):** clavity is a multi-plugin product whose docs are
  heavily cross-linked from `CLAUDE.md`, `README.md`, hooks, and memory, so they stay where they are.
  Its product manual is the root `README-CLAVITY.md`. Do not "tidy" the clavity docs into a per-plugin
  layout.

## What lives here
- `hosting-a-tool.md` — the onboarding playbook for adding a tool to the umbrella.
- `superpowers/`, `session-notes/`, `agy-*.md`, `plugin-formats.md`, `clavity-dotnet-*.md` — grandfathered
  clavity/agy docs (D5).

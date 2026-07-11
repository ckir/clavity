# docs/ — umbrella & cross-cutting docs

> **Superseded (2026-07-11) for doc layout:** the `plugins/<tool>/README.md` per-plugin doc path and
> the "clavity is the grandfathered exception" split below describe the pre-monorepo layout. Every
> product — including clavity's `clavity-dotnet` / `clavity-classic` variants — now lives in its own
> top-level folder with docs at `<product>/README.md` and `<product>/plugin/README.md`; see the root
> [`README.md`](../README.md) for the current product index.

This directory holds **umbrella / cross-cutting** documentation only — things that span the whole
`clavity` multi-tool repo. It is the consistency guard for two decisions:

- **New tools (D4):** put tool-specific docs **beside the plugin** — `<product>/README.md`
  (operator) and optional `<product>/docs/` (design). Not here.
- **clavity is the grandfathered exception (D5):** clavity is a multi-plugin product whose docs are
  heavily cross-linked from `CLAUDE.md`, `README.md`, hooks, and memory, so they stay where they are.
  Its product manual is the root [`README.md`](../README.md). Do not "tidy" the clavity docs into a
  per-plugin layout.

## What lives here
- `hosting-a-tool.md` — the onboarding playbook for adding a tool to the umbrella.
- `superpowers/`, `session-notes/`, `agy-*.md`, `plugin-formats.md`, `clavity-dotnet-*.md` — grandfathered
  clavity/agy docs (D5).

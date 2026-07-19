# docs-spec — the clavity documentation convention

What each human-facing doc is for, how it should read, and what must never be edited by hand.

This is the input to the `docs-rationalize` procedure: a WRITER rewrites against this spec, and a
separate REVIEWER verifies every claim by measurement. Doc architecture is a product decision — this
file is where that decision is recorded, so it is not re-litigated per document.

## Doc list — audience and voice

Per-member docs follow the standard already set in
[`hosting-a-tool.md` § Per-member documentation](hosting-a-tool.md#per-member-documentation); this
table adds the **voice** for each.

| Doc | Audience | Voice |
|---|---|---|
| Root `README.md` | Someone who just landed on the repo and knows nothing | Answers three questions in order: what is this, which product do I want, how do I start. Plain English before jargon. Maintainer detail goes last or to `CONTRIBUTING.md`. |
| `<member>/README.md` | A repo reader evaluating or building that member | Operator-facing. **Not** the installed operator — the installer ships `plugin/`, never the member README. |
| `<member>/plugin/README.md` | The integrator wiring the plugin — **and the installed operator, because this file ships** | Mechanics: what it provides, how it registers, MCP wiring, troubleshooting. |
| `<member>/CONTRIBUTING.md` | A contributor to that member | Member-specific mechanics only — toolchain, test tiers, its own failure modes. Defers to the umbrella `CONTRIBUTING.md` for licence, DCO, and release policy. Never restates them. |
| `<member>/CLAUDE.md` | The agent working in that folder | Load-bearing facts and traps only. Auto-loaded, so a wrong one is worse than none. **Never start from a sibling's copy.** |
| `<member>/ROADMAP.md` | Anyone asking "what's next / did this ship" | Optional. States outcomes, not intentions-as-facts. |
| Umbrella `docs/` | Cross-cutting readers | Umbrella-only. Member-specific design belongs in `<member>/docs/`. |

## Scannable rules

- **Headings carry the scan.** A reader skimming only `##` lines should be able to navigate. A heading
  that hides a requirement (`## Configuration` for a mandatory step) is a defect, even if the body says so.
- Bullet lists **≤ 5 items**. Longer means it wants to be a table or subsections.
- Tables stay small and comparative. A table of build commands is not a choice aid.
- Fenced code blocks are **tight and copy-pasteable** — no prose inside, no invented placeholders where
  a real value exists.
- **Prose is reserved for reasoning** — why a thing is the way it is. Steps and facts are lists/tables.
- Section order per document is fixed by the templates in
  `clavity-dotnet/templates/tool-skeleton/`, which are the single source of truth for that order.
  A member **omits** a section that does not apply rather than reordering, renaming, or padding it.
- A hand-maintained table of contents is allowed only above ~150 lines, and must mirror the `##`
  headings exactly. A drifted TOC is worse than none.

### No AI-tells

No marketing voice, no "blazingly fast", no "seamless", no exclamation marks, no emoji as decoration
(as a status marker in a table is fine). Do not open a section by restating its heading. Do not pad
with "it's worth noting that". Short sentences. This is a technical audience that dislikes being sold to.

## Accuracy rules

- Every concrete claim — command, flag, env var, path, script name, count, version, licence — must be
  verifiable against the code or the tree. **An omission is cheap; a confident false claim is not.**
- Where a doc describes a contract enforced elsewhere, cite the enforcer (e.g. the CHANGELOG's leading
  H1 is required by `scripts/lib/release-lib.ps1`'s injection regex).
- Prefer a link to the canonical copy over restating it. Restating is how the two agy manuals drifted.

## Do-not-touch list

Never edited by the docs-rationalize procedure, by a WRITER, or by hand:

| Path | Why |
|---|---|
| All six `LICENSE` files | Legal text. Changing the licence is not a docs decision. |
| All five `<member>/CHANGELOG.md` | `just release` injects into these. Hand-editing fights the injector; the leading H1 is load-bearing. |
| `agy-autotrain/knowledge/driver-cheatsheet.core.md` | Pinned **byte-identical** across three files (this, `clavity-classic`'s `BASELINE_FLOOR`, `clavity-dotnet`'s `BaselineFloor`). Editing it alone red-gates both test suites. |
| `*/plugin/knowledge/agy-*.md` | Driver-owned SEED manuals, refreshed by the `agy-curate` loop, not by hand. |
| `docs/agy-assumptions.md`, `docs/agy-capabilities.md`, `clavity-classic/docs/agy-test-suite.md` | Deliberate pointer stubs. `scripts/check-doc-stubs.ps1` fails if they are re-fattened. |
| `*/installer/marketplace.install.json`, `installer/_shared/register-plugin-hash.iss` | Generated. Regenerate via their scripts. |
| `docs/superpowers/`, `.clavity/` | Gitignored working artifacts, not published docs. |
| Vendored trees (`**/.venv/`, `**/node_modules/`, `*/agy-mcp-bridge/` third-party) | Not ours. |

## Procedure

Run `docs-rationalize`. The non-negotiable rule: **the WRITER and the REVIEWER are different contexts.**
The WRITER (the agy peer, or a fresh isolated subagent) rewrites against this spec; the driving session
REVIEWS by measuring every changed claim against the code. A context that reviews its own prose
rubber-stamps its own confabulations.

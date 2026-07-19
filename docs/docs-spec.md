# docs-spec — clavity documentation convention

The contract the `docs-rationalize` skill binds to. Human-facing docs are role-scoped and written in a
terse, human, scannable voice. Per-member doc set and section order:
[`hosting-a-tool.md` § Per-member documentation](hosting-a-tool.md#per-member-documentation).

## Docs (audience → voice)

| Doc | Audience | Voice |
|---|---|---|
| `README.md` | Orient, choose a product, get running — then route out (≤ ~90 lines) | terse-technical |
| `<member>/README.md` | A repo reader evaluating or building that member. **Not** the installed operator — the installer ships `plugin/`, never this file | terse-technical |
| `<member>/plugin/README.md` | The integrator wiring the plugin — **and the installed operator, because this file ships** | terse-technical |
| `<member>/CONTRIBUTING.md` | A contributor to that member — its toolchain, test tiers, failure modes. Defers to umbrella `CONTRIBUTING.md` for licence/DCO/release | terse-technical |
| `<member>/CLAUDE.md` | The agent working in that folder — load-bearing facts and traps only | terse, dense |
| `<member>/ROADMAP.md` | Outcomes, not intentions-as-facts (optional) | terse |
| `docs/**` | Cross-cutting readers; umbrella-only. Member design lives in `<member>/docs/` | terse-technical |
| `CONTRIBUTING.md` | A new contributor | terse-technical |

## Voice / scannable rules

- Terse-technical and human — short lines, no run-on sentences, no AI-tells (no "superpower",
  "seamless", "blazingly fast", no exclamation marks, no decorative emoji).
- Scannable: headings, tight fenced code blocks, small tables, bullet lists ≤ 5 items; prose reserved
  for reasoning.
- Prefer a code block / command over prose where it carries the meaning.
- Section order comes from `clavity-dotnet/templates/tool-skeleton/` — the single source of truth. Omit
  an inapplicable section; never reorder, rename, or pad it.
- A heading that hides a requirement (`## Configuration` for a mandatory step) is a defect even if the
  body states it.
- Hand-maintained TOC only above ~150 lines, mirroring the `##` headings exactly.

## Accuracy

- Every concrete claim — command, flag, env var, path, script, count, version, licence — must be
  verifiable against the tree. An omission is cheap; a confident false claim is not.
- Cite the enforcer where one exists (e.g. a CHANGELOG's leading H1 is required by
  `scripts/lib/release-lib.ps1`'s injection regex).
- Link the canonical copy instead of restating it — restating is how the two agy manuals drifted.

## Do-not-touch (out of scope for a docs pass)

- **Any code, script, or workflow file** (`*.rs`, `*.cs`, `*.ps1`, `*.sh`, `*.yml`, `*.iss`) — a docs
  pass never edits the system it describes.
- `LICENSE` (all six) — legal text.
- `<member>/CHANGELOG.md` (all five) — injected by `just release`; the leading H1 is load-bearing.
- `agy-autotrain/knowledge/driver-cheatsheet.core.md` — pinned byte-identical across three files;
  editing it alone red-gates both test suites.
- `*/plugin/knowledge/agy-*.md` — driver-owned SEED, refreshed by the `agy-curate` loop.
- The three pointer stubs (`docs/agy-assumptions.md`, `docs/agy-capabilities.md`,
  `clavity-classic/docs/agy-test-suite.md`) — `scripts/check-doc-stubs.ps1` fails if re-fattened.
- Generated: `*/installer/marketplace.install.json`, `installer/_shared/register-plugin-hash.iss`.
- `docs/superpowers/**`, `.clavity/**` — working artifacts, not product docs.
- Vendored trees (`**/.venv/`, `**/node_modules/`).

## Roles

The WRITER and the REVIEWER are different contexts — non-negotiable. A context that reviews its own
prose rubber-stamps its own confabulations. WRITER: the agy peer, else a fresh isolated subagent.
REVIEWER: the driving session, verifying every changed claim by measurement.

# docs-spec — clavity documentation convention

The contract the `docs-rationalize` skill binds to. Human-facing docs are role-scoped and written in a
terse, human, scannable voice.

Two authorities this file defers to, and does not duplicate:
- **Which docs each member carries** — [`hosting-a-tool.md` § Per-member documentation](hosting-a-tool.md#per-member-documentation).
- **Section order within a doc** — the templates in `clavity-dotnet/templates/tool-skeleton/`.

This file is also the authority over the **user-facing subset** that the `docs-rationalize` tool targets: [`docs/user-facing-docs.txt`](user-facing-docs.txt) — 25 files, a subset of the table below, validated by `scripts/check-user-facing-docs.ps1`.

## Docs (audience → voice)

| Doc | Audience | Voice |
|---|---|---|
| `README.md` | Orient, choose a product, get running — then route out (≤ ~90 lines) | terse-technical |
| `<member>/README.md` | A repo reader evaluating or building that member. For the **code+plugin** members (dotnet, classic, ghidrust) this file does **not** ship — their `.iss` ships `..\plugin\*`. For the **plugin-only** members (agy-autotrain, commonmemory) it **does** — their `.iss` ships `..\*` recursively, so write those two for an installed operator too | terse-technical |
| `<member>/plugin/README.md` | The integrator wiring the plugin — **and the installed operator, because this file ships** | terse-technical |
| `<member>/CONTRIBUTING.md` | A contributor to that member — its toolchain, test tiers, failure modes. Defers to umbrella `CONTRIBUTING.md` for licence/DCO/release | terse-technical |
| `<member>/CLAUDE.md` | The agent working in that folder — load-bearing facts and traps only | terse, dense |
| `<member>/ROADMAP.md` | Outcomes, not intentions-as-facts (optional) | terse |
| `docs/**` | Cross-cutting readers; umbrella-only | terse-technical |
| `<member>/docs/**` | That member's design/protocol depth — runbooks, transport notes, research logs | terse-technical; research logs may be long |
| `clavity-classic/docs/how-it-works.md`, `clavity-classic/docs/launching-and-driving-agy.md` | **User-facing evaluator docs** — someone deciding whether/how to run clavity-classic. More specific than the generic `<member>/docs/**` internal-depth row above; keep them terse and scannable, not research-log-long | terse-technical |
| `CONTRIBUTING.md` | A new contributor | terse-technical |
| `CLAUDE.md` (root) | The agent working anywhere in the repo — cross-cutting rules only | terse, dense |
| `SECURITY.md` | Someone reporting a vulnerability | terse, unambiguous |
| `CODE_OF_CONDUCT.md` | Participants | leave substance alone; formatting only |
| `.github/pull_request_template.md` | A PR author's checklist | terse |
| `.github/ISSUE_TEMPLATE/*.md` | A bug/feature reporter | terse |
| `clavity-classic/installer/*MANUAL-SETUP.md`, `*README-FIRST.md` | **The installed operator** — these ship inside the installer | terse-technical, imperative |

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
- `LICENSE`, `**/LICENSE` — legal text.
- `**/CHANGELOG.md` — injected by `just release`; the leading H1 is load-bearing.
- `agy-autotrain/knowledge/driver-cheatsheet.core.md` — pinned byte-identical across three files;
  editing it alone red-gates both test suites.
- `**/knowledge/**` — driver-owned SEED manuals and the learning loop's working files, refreshed by
  `agy-curate`. Matched on `knowledge/` at any depth deliberately: `*/plugin/knowledge/` would fire only
  on the code+plugin shape and leave a plugin-only member's `<member>/knowledge/` unprotected.
- The three pointer stubs (`docs/agy-assumptions.md`, `docs/agy-capabilities.md`,
  `clavity-classic/docs/agy-test-suite.md`) — `scripts/check-doc-stubs.ps1` fails if re-fattened.
- Generated: `*/installer/marketplace.install.json`, `installer/_shared/register-plugin-hash.iss`.
- **Every `SKILL.md`, anywhere — `**/SKILL.md`** — behavioural contracts injected into agent
  context. Rewording them changes what an agent *does*, so they are changed deliberately with their own
  review, never by a docs pass. Match on the filename alone: an earlier version enumerated directory
  shapes (`*/skills/**`, `*/skill/`, `*/agy_skills/**`) and silently missed 8 of 13 — every
  `*/plugin/skills/**` file plus `clavity-classic/agy-mcp-bridge/SKILL.md`.
- `agy-autotrain/knowledge/agy-observations.md` — the `agy-learn` capture inbox, drained by `agy-curate`.
- `agy-autotrain/verify/*.md` — the probe harness; `assertions.md` records measured outcomes.
- `agy-autotrain/docs/fix-the-tool-backlog/**` — generated from `_template.md`, append-only.
- `seed/golden-header.md` — compiled SEED, written by `curate-commit`.
- `scripts/drain-knowledge-prompt.md` — a prompt, functionally code.
- `commonmemory/rules/commonmemory.md` — an agy rule file the agent consumes, not prose.
- `**/docs/archive/**` — deliberately frozen historical artifacts, at ANY depth. Matched with a leading
  `**/` deliberately: a root-anchored `docs/archive/**` covers only the umbrella's copy and silently
  leaves a member's `<member>/docs/archive/**` in scope. That exact root-anchoring bug is how
  `clavity-classic/docs/superpowers/**` (5 files, 2,215 lines of superseded design docs) classified as
  in-scope product documentation — the root `docs/superpowers/` is gitignored, but the member-nested
  copy was tracked and matched nothing here. Those files now live in `clavity-classic/docs/archive/`.
- `**/tests/fixtures/**` — test data.
- `*/agy-mcp-bridge/VENDORED-FROM.md` — vendored provenance.
- `**/docs/superpowers/**`, `**/.clavity/**` — working artifacts, not product docs. Same leading-`**/`
  reasoning as the archive entry above: the root copies are gitignored, so only a member-nested copy can
  ever be tracked — and a root-anchored pattern is exactly what would miss it.
- Vendored trees (`**/.venv/`, `**/node_modules/`).
- **This file, `docs/docs-spec.md`** — it matches the in-scope `docs/**`, so without this line a docs
  pass could rewrite its own governing contract. Changed deliberately by the owner, never by a pass.

**Exclusions win.** Where a path matches both the doc list and this list, it is out of scope — e.g.
`ghidrust/crates/**/tests/fixtures/README.md` matches `<member>/README.md` by shape but is test data.

> Every tracked `.md` is either named in the table above or excluded here. If a pass encounters one that
> is neither, that is a spec gap — report it rather than guessing whether it is in scope.

## Roles

The WRITER and the REVIEWER are different contexts — non-negotiable. A context that reviews its own
prose rubber-stamps its own confabulations. WRITER: the agy peer, else a fresh isolated subagent.
REVIEWER: the driving session, verifying every changed claim by measurement.

**`<member>` resolves against `build/members.json`** — the five entries there are the roster. A member's
shape comes from its `source`: ending in `/plugin` = code+plugin, otherwise plugin-only. Hand the roster
to any WRITER or auditor; without it `<member>` is undefined and they will guess.

**Route the WRITER in the SAME working tree the REVIEWER will measure.** Use the `agy_ask` MCP tool (or
`clavity ask`), which acts on this tree. Do **not** use the `delegate_to_antigravity` bridge for a docs
pass. It runs agy in an isolated git worktree, so Phase 3 would measure the driver's tree, see the files
unchanged, and pass a review of work it never looked at. The failure is worse than it sounds:
`clavity-classic/agy-mcp-bridge/isolation.py:87` defines
`cleanup_worktree(target_dir, task_id, success=False)` — **`success` defaults to False**, so a timed-out
or unreported run discards the worktree entirely. A parked reply arriving later then reads as success
over a tree that never received the work. Long agy turns time out routinely, so this is the common path,
not the edge case.

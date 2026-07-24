# SP-0 — Unify the driver plugins under a `clavity:` namespace — Design

**Status:** Design approved by the driving session (2026-07-24). Part of the ship-agy-workflow epic; it is the
**prerequisite** sub-project that must merge before SP-A. AGY-FIRST-consulted (packaging fork + rename-scope fork);
sequence AGY-NEGOTIATE-agreed with the owner. Panel review (AGY-AFTER) pending before the plan.

**Goal:** Collapse the two driver plugins (`clavity-dotnet`, `clavity-classic`) to a single **plugin identity
named `clavity`**, and strip redundant prefixes from their existing skills, so every shipped skill surfaces under
one uniform `clavity:<skill>` namespace (the `ecc:` pattern the owner asked for). Mutual exclusivity means only one
driver is ever installed, so it owns the namespace unambiguously.

**Why this is its own sub-project:** the change is cross-cutting and release-sensitive — it touches plugin manifests,
scoped-marketplace registration, the installers, CI, docs, and re-namespaces every already-shipped skill. Coupling it
into SP-A would let an installer bug mask a discipline-logic flaw (the "entangled review" failure the sequencing
negotiation rejected). It lands isolated; SP-A→SP-D then build on the `clavity:` baseline; **one combined release**
ships the whole epic.

---

## Decisions (settled in brainstorming)

### D1 — Plugin identity unifies to `clavity`; marketplace *scope* stays distinct
The skill namespace prefix in Claude Code **is the plugin name** (verified: the `ecc` plugin's `plugin.json` is
literally `"name": "ecc"`, surfacing `ecc:<skill>`). So each driver sets its **plugin** `name` to `clavity`. The
**scoped-marketplace** outer `name` (a different field) **stays distinct** (`clavity-dotnet` / `clavity-classic`) so
the two scoped marketplaces do not collide at the marketplace layer — only the *plugin* identity unifies.

Concretely, per driver:
- `clavity-<flavor>/plugin/plugin.json` → `"name": "clavity"`
- `clavity-<flavor>/plugin/.claude-plugin/plugin.json` → `"name": "clavity"`
- `clavity-<flavor>/installer/marketplace.install.json` → the **`plugins[].name`** entry → `"clavity"`; the outer
  marketplace **`name`** field → **unchanged** (`clavity-dotnet` / `clavity-classic`).

**Panel finding (Axiom/Protocol) — the registration-key hazard:** because the marketplace *scope* stays
`clavity-dotnet` while the *plugin* it registers changes from `clavity-dotnet` → `clavity`, the plan MUST pin the
exact registration key Claude Code / agy use (marketplace+plugin, or plugin-name alone). D2's clean-break removal
targets the **old plugin identity** (`clavity-dotnet` the plugin); it must NOT remove the **retained marketplace
scope** (`clavity-dotnet` the marketplace) or it would delete its own new registration. This distinction is
load-bearing and is the first thing the plan's registration-tooling task resolves.

### D2 — Migration: clean break
The installer registers the `clavity` plugin and **removes any prior `clavity-dotnet` / `clavity-classic`
registration** it finds. Old `clavity-dotnet:<skill>` / `clavity-classic:<skill>` references stop resolving; the
release notes document the namespace change. No backward-compat alias (rejected as YAGNI for the known, small,
owner-controlled, mutually-exclusive user base).

### D3 — Skill prefix strip (Option B); cross-driver unify deferred
Strip the redundant plugin-ish prefix from existing skills. Exact mapping — the oracle for the rename:

| Driver | Current skill dir + `name` | New skill dir + `name` | Surfaces as |
|---|---|---|---|
| dotnet | `clavity-ls-driving` | `ls-driving` | `clavity:ls-driving` |
| dotnet | `clavity-ls-pairing` | `ls-pairing` | `clavity:ls-pairing` |
| dotnet | `adversarial-panel-review` | *(unchanged)* | `clavity:adversarial-panel-review` |
| dotnet | `agy-first` (SP-A, not yet shipped) | *(unchanged)* | `clavity:agy-first` |
| classic | `clavity-driving` | `driving` | `clavity:driving` |
| classic | `claudavity-responder` | `responder` | `clavity:responder` |
| classic | `adversarial-panel-review` | *(unchanged)* | `clavity:adversarial-panel-review` |

The `ls-` in the dotnet skills is **kept** — it denotes the Language-Server transport and is meaningful, not
redundant. Each rename = **rename the skill directory + change the frontmatter `name:` + update every reference**
(see D6). **Cross-driver unify** (collapsing dotnet `ls-driving` + classic `driving` into one byte-identical
`clavity:driving`) is **explicitly out of scope** — it requires first rewriting the two driving skills to a single
transport-agnostic body (the `agy-first` inline-transport pattern), which is a future epic, not SP-0.

### D4 — Both-installed collision: installer-enforced single install + a verification spike
agy asserted that two plugins declaring the same `name` "crash on boot" — **unverified** (a confident claim to
measure, not fold). The design does not depend on that claim being true:
- The installer enforces a **single `clavity` install**: installing either flavor removes the *other* flavor's
  install/registration first, so a supported box never holds two `clavity` plugins. **(Panel/Blindspot)** this
  cross-flavor removal is **destructive** (it uninstalls another plugin) — the installer must **surface/confirm it to
  the operator**, never silently uninstall.
- Mutual exclusivity (the owner's standing rule) makes both-installed an unsupported transient anyway.
- **Dual-agent verification (Panel/Dependency):** the `plugin-name-is-the-namespace` fact was verified for **Claude
  Code** (the `ecc` plugin). These plugins install into **both** Claude Code *and* agy. The spike MUST confirm the
  `clavity:<skill>` namespace resolves correctly under **agy** too — do not assume the two agents namespace
  identically.
- **Spike (run in the plan, before finalizing the installer logic):** stage both flavors as `clavity` and observe
  whether Claude Code / agy actually collide on boot. The result decides whether the installer's cross-flavor
  removal is load-bearing (must-have) or belt-and-suspenders (nice-to-have). Either way the installer performs it.

### D5 — Release shape
SP-0 merges first to establish the `clavity:` baseline (to `main` or a holding branch). SP-A→SP-D build against it.
**One combined version bump** delivers the unified namespace + the new disciplines together — the breaking rename
ships *with* value, in a single user migration (a value-less rename-only release was rejected by both agents).

### D6 — Reference-update surface (categories; the plan enumerates exact sites)
The rename touches these categories. The **implementation plan** grep-verifies and lists every exact file/line; the
spec fixes only the categories so none is missed:
1. **Plugin manifests** — `plugin.json` (×2 per driver) + `marketplace.install.json` (plugin-entry name) (×2).
2. **Aggregate manifests** — `build/members.json` and any roster/member manifest that lists the plugin by name.
3. **Installers** — `clavity-dotnet/installer/clavity-dotnet.iss`, `clavity-classic/installer/clavity-classic.iss`
   (registered plugin name + the clean-break removal of the old name + cross-flavor removal).
4. **Registration tooling** — `scripts/generate-scoped-manifest.ps1`, `scripts/*register*` (`register-plugin`,
   `sync-register-hash`, `check-register-hash-synced`) — anything that keys on the plugin name.
5. **CI** — `.github/workflows/build-*.yml`, `ci-installer-*.yml`, `umbrella-release.yml`, `ci-member-docs.yml`,
   `lefthook.yml` — any that reference the plugin name.
6. **Skill dirs + frontmatter** — the D3 renames (dir + `name:`), and any skill `description`/body that names a
   sibling skill.
7. **Anti-drift** — `scripts/check-seed-artifacts-synced.sh` enrollment paths (the `adversarial-panel-review` path
   is unchanged; confirm no enrolled path embeds a renamed skill dir).
8. **Docs** — every user-facing doc referencing a `clavity-dotnet:` / `clavity-classic:` skill namespace or a renamed
   skill (the `docs/user-facing-docs.txt` set + CLAUDE.md files + READMEs).
9. **Hooks/scripts that match a skill by name** — grep the repo (and note, out-of-repo, the owner's personal
   `~/.claude/hooks/agy-seam-inject.sh`, which currently matches only *superpowers* skills, not clavity skills — so
   it is expected to need **no** change; the plan confirms this by grep rather than assuming).

---

## Testing posture
- **Namespace-grep gate (new):** the primary correctness net for a mechanical mass-rename. It must assert **all
  three** of: (a) no stray `clavity-dotnet:<skill>` / `clavity-classic:<skill>` **namespace** references survive;
  (b) no old **skill-dir names** (`clavity-ls-driving`, `clavity-driving`, `clavity-ls-pairing`,
  `claudavity-responder`) survive; (c) no old **plugin `name`** (`clavity-dotnet`/`clavity-classic`) survives in a
  `plugin.json` or a `marketplace.install.json` `plugins[].name`. **(Panel/Cascade)** the gate MUST NOT
  false-positive on the intentionally-**retained marketplace *scope* name** (`clavity-dotnet`/`clavity-classic` as the
  outer `marketplace.install.json` `name` and in scope paths) — target the namespace/`:`-qualified and the specific
  field/dir patterns, not the bare string. Incomplete coverage of (a)–(c) is a false-GREEN. Wire it into the same
  pre-push gate as the seed sync-check.
- **Registration / install tests** (`scripts/tests/register-plugin.Tests.ps1`, `clavity-dotnet/install/
  clavity-install.Tests.ps1`, `scripts/tests/check-roster.Tests.ps1`, `compute-release`/`release-lib` tests)
  updated for the new plugin name and green.
- **Seed sync-check** (`check-seed-artifacts-synced.sh`) green (its enrolled paths are unaffected by D3).
- **Docs-audit** (`scripts/tests/docs-audit.Tests.ps1` + the user-facing-docs Pester) green after the doc
  re-namespace.
- **Collision spike** result recorded (D4).
- **A real install smoke** (the installer registers `clavity`, removes the old name, and the skills resolve as
  `clavity:<skill>`) — the definition-of-done check.

## Non-goals / explicitly deferred
- **Cross-driver skill unify** (one byte-identical `clavity:driving` for both drivers) — future epic (D3).
- **Backward-compat alias** for the old namespace — rejected (D2).
- Renaming the repo **folders** `clavity-dotnet/` / `clavity-classic/` — the folders stay; only the plugin *identity*
  changes. (Renaming folders is a much larger, unnecessary churn.)
- The **marketplace scope** names — stay distinct (D1).

## Gaps flagged for the plan (not the spec)
- The exact line-level reference sites in every D6 category (grep-verify each before writing the plan tasks).
- The installer's precise cross-flavor removal mechanism (per `.iss` capability) + the D4 spike.
- The exact namespace-grep gate implementation (pattern set + placement) and its Pester test.
- The precise registration-tooling changes (whether `generate-scoped-manifest.ps1` / the register-hash scripts key
  on the plugin name vs the marketplace scope name — determines how much they change).
- **(Panel/Activation) skill-caching:** a dir+frontmatter rename may not take effect until the plugin is
  reinstalled / the skill cache is cleared (see `agy-assumptions.md` on skill caching). The plan must specify the
  reinstall/cache-clear step for the owner's own env and document it for end users, so a rename does not appear to
  "not work" because a stale cache still serves the old name.

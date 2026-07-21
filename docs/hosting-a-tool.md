# Hosting a tool in the `clavity` umbrella

`clavity` is an umbrella repo: it hosts several independently-installable tools under one brand. This is
the checklist to graft a new one in.

> **Rewritten 2026-07-19 from how `ghidrust` was actually onboarded.** The previous version of this
> playbook described a **branch-per-tool** model (code on a `<tool-id>` branch, plugin under
> `plugins/<tool-id>/` on `main`, a per-tool `<tool-id>-v<N>` release lineage, an entry in a repo-root
> `.claude-plugin/marketplace.json`). **None of that exists any more** — every path it named is either
> gone or somewhere else. Treat any surviving copy of those instructions as stale.

## The current model

- **One tree, no branches.** Every member is a **top-level folder on `main`** — `clavity-dotnet/`,
  `clavity-classic/`, `ghidrust/`, `agy-autotrain/`, `commonmemory/`. There is no `plugins/` directory
  and no per-tool branch. A `clavity-v<N>` tag on `main` deterministically pins all members at once.
- **One release, five independent installers.** The umbrella release is the catalog page; each member
  ships its **own standalone installer** that registers only itself into its own scoped marketplace.
  No installer bundles or downloads a sibling, and there is no live remote marketplace channel.
- **One tag lineage.** Only `clavity-v<N>` triggers a release (`umbrella-release.yml`). The legacy
  `v*`, `clavity-dotnet-v*`, and `clavity-classic-v*` tags are dead no-ops, and `release-ghidrust.yml`
  is `workflow_dispatch`-only — its tag trigger was deliberately removed. Do not invent a new per-tool
  tag namespace.
- **Members are declared in `build/members.json`.** That file is the roster. It is **not** a Claude
  marketplace manifest and must never be placed under a `.claude-plugin/` directory; each installer's
  own scoped one-entry `marketplace.json` is *generated* from it by
  `scripts/generate-scoped-manifest.ps1`.

### Two member shapes

`build/members.json` gives each member a `source`, and there are two legitimate layouts. Pick the one
that matches what you are adding:

| Shape | `source` | Examples |
|---|---|---|
| **Code + plugin** — a binary plus a plugin that drives it | `./<member>/plugin` | `clavity-dotnet`, `clavity-classic`, `ghidrust` |
| **Plugin-only** — no binary; the member root *is* the plugin | `./<member>` | `agy-autotrain`, `commonmemory` |

A plugin-only member has `plugin.json` at its root and no `plugin/` subdirectory. It also has no
`justfile` and is skipped by the build/lint/test aggregates.

## Conventions that still hold

- **`<member>` is a flat kebab slug**, used identically for the folder, the installer basename, the
  `.iss` filename, and the workflow suffixes. No slashes.
- **Unique binary name.** Binaries land on the shared user PATH, so name the binary for the tool
  (`ghidrust`, `clavity-ls`) — never a generic `agent.exe` / `proxy.exe`.
- **Docs live with the member** — `<member>/README.md` (operator) and optional `<member>/docs/`
  (design). Root `docs/` is umbrella-only; see [`README.md`](README.md) in this directory.
- **Member-specific `CLAUDE.md`.** If you add one, write it *for that member*. It is auto-loaded into
  agent context for work in that folder, so a copied-from-a-sibling `CLAUDE.md` actively poisons
  sessions — this happened to `ghidrust` and went unnoticed for weeks.
- **`*.template` rule.** Skeletons live in **`clavity-dotnet/templates/tool-skeleton/`** with a
  `.template` suffix so no loader ever ingests them as a live tool. (Note the location — they are *not*
  at the repo root.)
- **Substitute EVERY placeholder.** When you copy any `*.template`, replace all `<…>` tokens
  (`<TOOL-ID>`, `<BINARY>`, `<VERSION>`, `<DESCRIPTION>`, `<SKILL-NAME>`) and generate a fresh `AppId`
  GUID before committing. A raw `<TOOL-ID>` left in a live `plugin.json` or workflow is a silent breakage.
  Some templates still carry branch-era assumptions (`build-tool.yml.template`,
  `release-tool.yml.template`) — read them against a real member's current files before trusting them.

## The registration checklist

**This is the part that bites.** A new member is not "added" by creating its folder; it is added by
registering it in every place that enumerates members. Miss one and the failure is usually silent — a
member that never builds, never version-checks, or never ships. Verified list:

**Roster**
1. `build/members.json` — add the member object (`name`, `source`, `description`, `marketplaceName`).
2. `scripts/validate-members-manifest.ps1` — asserts an exact member **count**; it will fail until updated.
3. `scripts/tests/check-roster.Tests.ps1` — Pester fixtures assert the roster; update them too.

**Versioning**
4. `scripts/check-versions.ps1` — add the member to the `[ValidateSet(...)]` on `-Member` **and** add its
   `$Registry` entry: the equality class(es) listing every version-bearing source (its
   `installer/<member>.iss` `#define AppVersion`, its `plugin.json`(s), plus any `Cargo.toml`/`Cargo.lock`
   or `pyproject.toml`+`uv.lock`), plus a matching `CoverageFiles` list so `-Coverage` does not flag the
   new files as unregistered. Note `ghidrust` uses **two** classes (`binary` and `plugin`) because it
   versions those independently — copy that shape only if you need it.
5. `scripts/bump-version.ps1` — add the member to its `[ValidateSet(...)]`.
6. `lefthook.yml` — append `pwsh -File scripts/check-versions.ps1 <member>` to the pre-push
   `check-versions` chain.

Thereafter bump **only** via `just bump <member> <version>`. Never hand-edit a version source;
`bump-version.ps1` is the sole writer, and `check-versions.ps1` is what catches you.

**Installer**
7. `<member>/installer/<member>.iss` — from `installer.iss.template`; fresh `AppId` GUID. `#include` the
   shared pieces from `installer/_shared/` (`claude-running.iss`, `register-invoke.iss`,
   `register-plugin-hash.iss`) and call `RegisterMemberPlugin` / `DeregisterMemberPluginOnUninstall`.
   Do **not** write your own registration logic — `installer/_shared/register-plugin.ps1` is the single
   registrar for every member and for the .NET binary alike.
8. `scripts/lib/release-lib.ps1` — add the member's `Key` to the `Members` list of **every**
   `$SharedPaths` entry it ships. A shared asset arrives three different ways — an `#include`, a
   `[Files] Source:` line, or a runtime invocation — and each one counts, so go by what the member
   actually ships, not by what it `#include`s. Skip this and a fix to that shared asset bumps every
   member **except** yours: the installer changes, the version does not, and nothing says so. See
   "Releasing" below for why the release engine needs this.
9. `<member>/installer/marketplace.install.json` — generated; do not hand-author.

**CI / release**
10. `.github/workflows/build-<member>.yml` — `workflow_call` + `workflow_dispatch`, produces the installer
    and its `.sha256`.
11. `.github/workflows/ci-<member>.yml` — push/PR gated on `paths: [<member>/**, …]`. Plugin-only members
    may not need one.
12. `.github/workflows/ci-installer-<member>.yml` — also watch `installer/_shared/**` and the shared
    scripts in **both** `paths:` blocks.
13. `.github/workflows/umbrella-release.yml` — five separate touch points: the per-member **job**, the
    publish job's **`needs:`**, its **download** step, the **`cp dist-<member>/*`** line, and the release-notes
    **table row**.
14. `.github/workflows/republish-member.yml` — add the member to the `workflow_dispatch` input's
    `choice` options, or it can never be hotfixed independently.

**Developer surface**
15. Root `justfile` — only if the member is **buildable** (has its own `justfile`): add its `mod` line and
    append `<member>::lint` / `::test` / `::build` / `::fmt` to the four aggregate recipes. Plugin-only
    members need no change.
16. `DevelopersCockpit.ps1` — `$Buildable` (buildable members only), `$Versioned` (all), and
    `$BannerMembers`.
17. Root [`README.md`](../README.md) product table and the root [`CLAUDE.md`](../CLAUDE.md) products table.
18. **Documentation** — create the member's `README.md` and `CHANGELOG.md` (and `plugin/README.md` if it
    is a code+plugin member) from the templates listed under "Per-member documentation" below.
    `just check-member-docs` fails until they exist.

**Verify the registration landed:**

```bash
pwsh -File scripts/check-versions.ps1 <member>
pwsh -File scripts/check-versions.ps1 <member> -Coverage
pwsh -File scripts/validate-members-manifest.ps1
pwsh -File scripts/check-roster.ps1   # roster vs members.json, AND the shared-path map vs the installers
just test-scripts          # Pester, incl. the roster tests
```

## Per-member documentation

Every member carries the same required documents, so a reader moving between members can rely on it.

| Doc | code+plugin | plugin-only | Audience |
|---|---|---|---|
| `README.md` | **required** | **required** | Repo reader — what it is, how to build/install, how to drive it |
| `CHANGELOG.md` | **required** | **required** | History; also written by `just release` |
| `plugin/README.md` | **required** | n/a — the root README doubles | Plugin mechanics; **ships with the installer** |
| `CLAUDE.md` | optional | optional | The agent working in that folder |
| `CONTRIBUTING.md` | optional | optional | Contributor — member-specific mechanics only |
| `ROADMAP.md` | optional | optional | Forward backlog |
| `docs/` | optional | optional | Design depth |

The required floor is enforced by `scripts/check-member-docs.ps1` (`just check-member-docs`, wired to
pre-push and `ci-member-docs.yml`). The optional files are convention — judgement, not a gate.

Three rules carry the weight:

- **`CLAUDE.md` is absent-or-correct, never copied.** A missing one is harmless; the umbrella
  `CLAUDE.md` applies. A *wrong* one is actively harmful, because it is auto-loaded into agent context
  for work in that directory. `ghidrust/CLAUDE.md` was once a verbatim copy of clavity-classic's and
  poisoned every session opened there for weeks. **Never start from a sibling's copy.**
- **A member `CONTRIBUTING.md` defers for policy.** Licensing, DCO, and the release process live in the
  umbrella `CONTRIBUTING.md` and are never restated. The member file carries only its own toolchain,
  test tiers, and failure modes.
- **`README.md` is repo-facing; `plugin/README.md` ships.** Verified in
  `clavity-classic/installer/clavity-classic.iss`: the installer ships `..\plugin\*` and a
  purpose-written `MANUAL-SETUP.md`, and does **not** ship the member's root README at all. So deep
  setup mechanics belong in `plugin/README.md`, where the installed operator will actually find them.

### Section order

Each document has a fixed section order. A member **omits** a section that does not apply rather than
reordering or renaming it — that is what makes cross-member navigation work.

**The templates are the single source of truth for that order. Copy the matching one and fill it in:**

- [`clavity-dotnet/templates/tool-skeleton/README.md.template`](../clavity-dotnet/templates/tool-skeleton/README.md.template) — code+plugin member README
- [`clavity-dotnet/templates/tool-skeleton/README-plugin-only.md.template`](../clavity-dotnet/templates/tool-skeleton/README-plugin-only.md.template) — plugin-only member README
- [`clavity-dotnet/templates/tool-skeleton/plugin-README.md.template`](../clavity-dotnet/templates/tool-skeleton/plugin-README.md.template) — `plugin/README.md`
- [`clavity-dotnet/templates/tool-skeleton/CHANGELOG.md.template`](../clavity-dotnet/templates/tool-skeleton/CHANGELOG.md.template) — `CHANGELOG.md`

The order is deliberately **not** written out here. One canonical copy, in the templates, is the whole
lesson of this repo applied to its own standard.

> **Do not demote a CHANGELOG's `# title` to `##`.** `scripts/lib/release-lib.ps1` injects each release
> after the leading H1 using `(?s)^(#[^\n]*\n+)(.*)$`. That regex also matches `##`, so a demoted title
> makes the injector write the new release *inside* the previous release's body and silently
> reattribute its entries. `just check-member-docs` rejects this.

## Cutting the release

Nothing member-specific is needed — once registered, the member is in the umbrella release. Run
`just release` from the repo root (preview with `just release-dry`): it derives each member's next
semver + CHANGELOG from conventional commits, previews every bump, and on a typed confirmation plus a
green local gate pushes `main` to the public remote — publishing every accumulated commit — before
creating and pushing the `clavity-v<N>` tag that triggers `umbrella-release.yml`.

`ghidrust` is gated by its live E2E before publish, so a broken ghidrust blocks a **full** cut — but not
a single-member hotfix. `republish-member.yml` rebuilds one member onto an already-published release
without any sibling's build or gate running (this is why step 14 above matters).

**Which commits bump your member.** The engine does not bump on "any commit since the last release"; it
attributes each commit by the paths it touches, and every tracked path falls in exactly one of three
buckets (`scripts/lib/release-lib.ps1`):

| bucket | what it is | effect |
|---|---|---|
| member-bound | anything under `<member>/` | bumps that member |
| shared-shipping | `$SharedPaths` — assets that ship into members (`installer/_shared/**`, `seed/**`, `build/members.json`) | bumps the members declared for that asset |
| dev-only | `$DevOnlyPaths` — CI, docs, tooling | bumps nobody, deliberately |

A path in **none** of the three is *unclassified*, and the release refuses to run until you put it in a
bucket. That is on purpose: before this existed, a commit touching only shared paths bumped nobody and
the release reported a cheerful "nothing to release", which is how a fix to plugin registration —
affecting every install — sat unshippable. If you add a top-level path, classify it.

The map is audited, not trusted: `check-roster.ps1` re-derives each shared asset's member set by
searching the members' own installer sources and fails on any disagreement, so a member that quietly
starts or stops shipping a shared asset cannot drift out of the table.

## De-listing a member

Removing the folder first breaks the build — every enumeration in the checklist becomes a dangling
reference. Decouple first, in this order:

1. Remove it from `build/members.json`, and update `validate-members-manifest.ps1`'s count and the roster
   tests.
2. Remove it from `umbrella-release.yml` (all five touch points) and `republish-member.yml`'s choices.
3. Delete its `build-<member>.yml`, `ci-<member>.yml`, `ci-installer-<member>.yml`.
4. Remove it from `check-versions.ps1` (ValidateSet + `$Registry`), `bump-version.ps1`, `lefthook.yml`,
   the root `justfile`, and `DevelopersCockpit.ps1`.
5. Remove its `Key` from every `$SharedPaths` entry in `scripts/lib/release-lib.ps1`. Leave one behind
   and `check-roster.ps1` fails: the map claims a member ships an asset whose installer no longer
   mentions it.
6. Remove its rows from the root `README.md` / `CLAUDE.md` tables.
7. **Only now** delete the member folder.
8. Keep the last published release for existing installs (immutable), or mark it deprecated in its notes.

## Tag-namespace protection

A per-workflow tag filter does not protect the git namespace — a stray `v1.0.0` still pushes and clutters
Releases. The namespace to protect is now just `clavity-v<N>`.

- A GitHub **repo ruleset** on tags rejecting anything not matching `^clavity-v[0-9]+`.
  > **Plan gate (verified 2026-07-09):** the name-pattern rule (`tag_name_pattern`) is a **GitHub
  > Enterprise Cloud** feature — `POST /repos/…/rulesets` returns `422 Invalid rule 'tag_name_pattern'`
  > on Free/Pro/Team (a parameterless tag ruleset still works; only the pattern rule is gated). On a
  > non-Enterprise plan this layer is unavailable; the reactive substitute is a tag-push CI job that
  > fails when the tag does not match.
- `umbrella-release.yml` triggers only on `clavity-v*`, which is the floor that always holds.

# Hosting a tool in the `clavity` umbrella

> **Superseded (2026-07-11) for packaging/distribution:** the branch-per-tool split, the
> repo-root `.claude-plugin/marketplace.json` entry (step 6 below), and the per-tool remote
> marketplace delivery this playbook describes are replaced by the cohesive distribution model —
> see `docs/superpowers/specs/2026-07-11-cohesive-distribution-design.md`. A new tool now gets its
> own standalone installer (self-registering a local scoped marketplace, C1/C9) built from `main`,
> not a `plugins/<tool-id>/` entry in a repo-root addable manifest. This file's non-distribution
> guidance (ROADMAP/README indexing, `*.template` skeletons, tag-namespace protection) still
> applies; its Phase B step 6 ("Add one entry to `.claude-plugin/marketplace.json`") does not — that
> file no longer exists at the repo root (relocated to the non-addable `build/members.json`).

`clavity` is an umbrella repo: it hosts several independently-released tools under one brand. This is
the repo-side counterpart to a tool's own `HANDOFF.md` — the checklist to graft a new tool in.

## Load-bearing conventions (read first)
- **Branch / `main` split (D7).** Code + `installer/<tool-id>.iss` + the reusable `build-<tool-id>.yml`
  live on the tool's **branch**. The plugin `plugins/<tool-id>/`, its `marketplace.json` entry, the
  ROADMAP section, and the release **orchestration** `release-<tool-id>.yml` live on **`main`**.
- **Per-tool release lineage (D2).** Each tool releases under its own `<tool-id>-v<N>` tag → its own
  GitHub Release + installer. `clavity` keeps its `clavity-v<N>` lineage (bundling its two variants).
- **`<tool-id>` is a flat kebab slug (D8)** — used identically for the plugin dir, marketplace name, tag
  prefix, and installer basename, with **no slash**. The git **branch ref is a separate variable**
  (`<branch-ref>`, recommended == `<tool-id>`), used only in the orchestration's `uses: …@<branch-ref>`.
- **Unique binary name (D8).** Binaries land on the shared user PATH, so name the binary for the tool
  (`ghidrust`, `clavity-ls`) — never a generic `agent.exe` / `proxy.exe`.
- **Docs beside the plugin (D4).** A new tool's docs go in `plugins/<tool-id>/README.md` (+ optional
  `plugins/<tool-id>/docs/`). Root `docs/` is umbrella-only. (`clavity` is the grandfathered exception,
  D5 — its manual is the root `README-CLAVITY.md`.)
- **`*.template` rule (D6).** Skeletons live in `templates/tool-skeleton/` with a `.template` suffix so
  no loader/globber ever ingests them as a live tool.
- **Substitute EVERY placeholder (global precondition).** When you copy ANY `*.template`, replace ALL
  `<…>` tokens (`<TOOL-ID>`, `<BRANCH-REF>`, `<BINARY>`, `<VERSION>`, `<DESCRIPTION>`, `<SKILL-NAME>`) and
  generate a fresh `AppId` GUID **before committing** — a raw `<TOOL-ID>` left in a live `plugin.json` or
  workflow is a silent breakage. `FILL:`-marked comments mark tool-specific steps you must complete.
- **⚠ UNSOLVED — cross-branch plugin bundling (D7 note).** `clavity-dotnet` is entirely on `main`;
  `clavity-classic` ships no plugin. A tool that is **code-on-branch AND ships a plugin** (e.g. the
  incoming `ghidrust`) is the FIRST to hit this: its branch-side installer build must obtain
  `plugins/<tool-id>/` (which lives on `main`). DECIDE the mechanism during that tool's onboarding —
  candidates: (a) the build checks out `main` to stage the plugin before ISCC; (b) duplicate the plugin
  onto the tool branch for packaging; (c) omit the plugin from the installer and deliver it via the
  marketplace only. Do NOT leave it unresolved at release time.

## Phase A — on the tool branch `<tool-id>` (`git checkout -b <tool-id>`)
Everything that ships WITH the code.
0. **Precondition:** the branch must contain this repo's `templates/tool-skeleton/` (they live on
   `main`). A branch cut before the umbrella prep merged must first `git merge main` (or
   `git checkout main -- templates/tool-skeleton`).
1. Push the tool's source to branch `<tool-id>`.
2. Add `installer/<tool-id>.iss` from `templates/tool-skeleton/installer.iss.template`; fill
   `<TOOL-ID>` / `<VERSION>` / `<BINARY>` and generate a FRESH `AppId` GUID (never reuse another tool's).
3. Add `.github/workflows/build-<tool-id>.yml` from `build-tool.yml.template`; fill the `FILL`-marked
   toolchain + binary-build steps. Prefer local `uses: ./…`; keep any cross-branch code checkout
   SHA-pinned. **Do NOT copy `build-dotnet.yml` as your starting point** — clavity-dotnet is code-on-`main`,
   so it uses a naked `actions/checkout` that, for a BRANCH tool, would build `main` instead of your code.
   Start from the template, whose checkout is `ref`-pinned to the tool branch.
4. Stage the built binary in `publish/` per the tool's build recipe.

## Phase B — on `main` (`git checkout main`)
The umbrella surface + the plugin.
5. Create `plugins/<tool-id>/` from `templates/tool-skeleton/`: `plugin.json`, `.mcp.json` (runs the
   installed binary, e.g. `<binary> serve`), `skills/<skill-name>/SKILL.md`, `README.md`, optional
   `docs/`.
6. Add one entry to `.claude-plugin/marketplace.json` from `marketplace-entry.json.template`
   (`source: ./plugins/<tool-id>`).
7. Add `.github/workflows/release-<tool-id>.yml` from `release-tool.yml.template` (tag-filtered
   `<tool-id>-v*`, `uses: …@<branch-ref>`, `make_latest: false`).
   **Admin gate (must precede Phase C):** if the tag-namespace ruleset (below) is active, a repo ADMIN
   must extend its allowed pattern to include `<tool-id>-v*` FIRST — otherwise the Phase C tag push is
   rejected and no release fires.
8. Add a `# <tool-id>` section to `ROADMAP.md` and a row to its "Hosted tools" index; add a row to the
   root `README.md` "Tools hosted here" table linking `plugins/<tool-id>/README.md`.

## Phase C — cut the release
9. Push tag `<tool-id>-v1` **on `main`** (matching the `clavity-v<N>` precedent). The tag must land where
   `release-<tool-id>.yml` lives so CI fires; the workflow reaches the branch's code via
   `uses: …@<branch-ref>` + SHA-pin. Verify the GitHub Release + installer + `.sha256` are produced and
   the plugin resolves in the marketplace.
   > Do NOT tag on the tool branch to "fix" the auto "Source code (zip)" asset: a branch-tip tag won't
   > find the main-resident orchestration and CI silently won't trigger. The auto source-zip reflecting
   > `main` is a known cosmetic; the shipped deliverable is the installer, and the branch is the
   > SHA-pinned source of truth for the build.

## Tag-namespace protection (two layers)
A per-workflow tag filter alone does not protect the git namespace (a stray `v1.0.0` still pushes and
clutters Releases). Enforce BOTH:
1. A GitHub **repo ruleset** on tags rejecting any tag not matching `^(clavity|<tool-id>|…)-v[0-9]+` at
   push time. Extending the alternation for a new tool is an **admin-only** action and MUST land before
   that tool's first `<tool-id>-v1` push (Phase C) — otherwise the push is rejected.
   > **Plan gate (verified 2026-07-09):** the name-pattern ruleset rule (`tag_name_pattern`) is a
   > **GitHub Enterprise Cloud** feature — `POST /repos/…/rulesets` returns `422 Invalid rule
   > 'tag_name_pattern'` on Free/Pro/Team plans (a parameterless tag ruleset still works; only the
   > pattern rule is gated). On a non-Enterprise plan, **Layer 2 is the floor** — Layer 1 is unavailable,
   > so an optional reactive substitute is a tag-push CI job that fails when the tag doesn't match the
   > namespace regex.
2. Each release workflow triggers only on its own `<tool-id>-v*` prefix.

## De-listing / sunsetting a tool
Hosting implies un-hosting. Deleting the branch FIRST breaks `main` (a dangling `uses: …@<branch-ref>`,
an orphan `plugins/<tool-id>/`, a dead marketplace entry). Decouple from `main` FIRST:
1. Remove the `marketplace.json` entry (stops serving the plugin).
2. Delete `plugins/<tool-id>/` and its `ROADMAP.md` section (or move it to a "Sunset" list); remove its
   ROADMAP/README index rows.
3. Delete `.github/workflows/release-<tool-id>.yml` (removes the dangling cross-branch `uses:`).
4. Optionally keep the last published Release/tag for existing installs (immutable), or mark it
   deprecated in its notes.
5. Only NOW delete the tool branch.

## Mapping a `HANDOFF.md` onto this playbook
A tool's `HANDOFF.md` (binary name, build/gate commands, MCP invocation, `.mcp.json` env/config, skill
delivery, tool surface, quirks) supplies the per-tool FILL values for the templates in Phases A/B. Work
through it top-to-bottom; anything it does not cover — notably the cross-branch plugin-bundling decision
above — is resolved here.

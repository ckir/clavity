# Spec: Prepare `clavity` as a multi-tool umbrella repository

> **Status:** design approved 2026-07-09. Scope is **preparation only** — this spec restructures the
> repo and codifies the pattern for hosting several independent tools. It does **not** onboard the
> incoming `ghidrust` tool (that is the next session's work; its `HANDOFF.md` already exists at
> `C:\Users\user\Development\Rust\ghidra-mcp\HANDOFF.md`).

---

## 1. Problem

The repo is currently organized around **one product (`clavity`) shipped in two mutually-exclusive
variants** (dotnet + classic). Everything assumes a single product:

- `ROADMAP.md` is one ~10 KB clavity-only document.
- `umbrella-release.yml` bundles **both variants' installers into one GitHub Release named "clavity"**
  via a single serial `clavity-v<N>` tag — correct for *variants of one product*, wrong for
  *independent tools*.
- `docs/` is entirely clavity/agy-centric.
- There is no written convention for adding a new tool; the only instance of that knowledge is the
  incoming tool's own `HANDOFF.md`.

A genuinely different tool (`ghidrust`, a Ghidra reverse-engineering MCP server) is ready to be hosted
here, and more will follow. Before hosting more tools, the repo must be generalized to host **several
independent tools** under one umbrella, following **one repeatable pattern**.

## 2. Goals & non-goals

**Goals**
- `clavity` becomes **one hosted tool among several** under the `clavity` umbrella brand (no repo /
  marketplace rename — least churn, existing installs & URLs keep working).
- Each hosted tool follows **one documented pattern**: code on its own branch; a Claude-Code plugin
  under `plugins/<tool>/` on `main`; a `marketplace.json` entry; an Inno-Setup installer; its **own**
  release lineage.
- A future maintainer (or a fresh session) can onboard a new tool by following a single checklist.

**Non-goals (explicitly out of scope for this work)**
- Onboarding `ghidrust` — no ghidrust binary, branch, plugin, installer, or `marketplace.json` entry.
- Renaming the repo, the marketplace, or the `clavity` release lineage.
- Moving or restructuring the existing clavity/agy docs (grandfathered — see D5).
- The optional `scripts/new-tool.ps1` scaffolder (noted as a stretch in §7).

## 3. Decisions (with rationale)

Each decision below was taken as a design fork, consulted with the `agy` peer, and confirmed by the
owner. Where the owner or the verified repo state overrode `agy`, that is recorded.

### D1 — Umbrella identity: **keep `clavity`** *(owner)*
Repo + `marketplace.json` stay named `clavity`. The `clavity` marketplace is the host/brand; `clavity`
itself is one tool under it. Rejected: neutral rename (churns repo URL, marketplace name, install docs,
release lineage for no functional gain).

### D2 — Release model: **per-tool release lineage** *(owner; agy concurred)*
Each *product* releases independently:
- `clavity` keeps its serial `clavity-v<N>` tag → one "clavity" Release that **still bundles its two
  variants** (they are one mutually-exclusive product — "install ONE").
- Each new tool gets its **own** tag series (`<tool>-v<N>`) → its **own** GitHub Release + installer.
- The single root `marketplace.json` stays a **shared plugin index**, decoupled from release tags.

Rejected: **(B)** one umbrella release bundling *all* tools under `clavity-v<N>` — it couples unrelated
release cadences (a `ghidrust` patch would force a `clavity` re-tag / version skew) and misrepresents a
release literally named `clavity-v<N>` as containing an unrelated tool.

> **Correction of the agy consult:** agy's strongest argument for (B) was a "marketplace-sync
> guarantee" / "Ouroboros" trap (the release workflow must commit back to `main` to update
> release-asset URLs in `marketplace.json`). **Verified false for this repo:** `marketplace.json`
> entries point to **local plugin source dirs** (`"source": "./plugins/<tool>"`), not release-download
> URLs. The plugin (skills + `.mcp.json`) is served from the repo tree; the binary ships via the
> separate Inno installer. There is no release-URL coupling to keep in sync, so (B)'s main advantage
> does not exist here.

### D3 — ROADMAP: **one file, per-tool sections** *(owner-hinted; agy concurred)*
`ROADMAP.md` is restructured into: umbrella overview → tool index → one section per hosted tool
(`clavity` first, its existing content preserved). Split into per-tool files only later, if it bloats.

> **Correction of the agy consult:** agy's "branch-collision trap" counter (a tool branch can't edit a
> single `main` ROADMAP without conflicts) rests on a wrong assumption. The established pattern is
> *code at branch, **plugin/docs/marketplace/roadmap at `main`***; roadmap edits always land on `main`,
> and the tool branch holds only code + its build workflow. The trap does not apply.

### D4 — Per-tool docs home: **beside the plugin** *(agy's locality principle; adopted)*
Going forward, everything specific to a tool lives in that tool's bounding box:
`plugins/<tool>/README.md` (operator docs) + optional `plugins/<tool>/docs/` (design docs). Root
`docs/` is reserved for **umbrella / cross-cutting** concerns only. This makes "branch / review / delete
a tool" a single-directory operation. (This adopts agy's locality-of-behavior argument and supersedes
an earlier lean toward a `docs/tools/<tool>/` split.)

> **agy internal contradiction, resolved:** agy's F2 answer said "move clavity docs to
> `docs/tools/clavity/`" while its F3 answer said "per-tool docs belong beside the plugin, not in
> `docs/tools/`." Those are mutually exclusive. Resolved in favor of the F3 locality principle, which
> makes `docs/tools/` unnecessary.

### D5 — Existing clavity docs: **grandfather in place** *(owner; over agy)*
The existing clavity/agy docs (`docs/superpowers/specs+plans/`, `docs/session-notes/`,
`docs/agy-*.md`, etc.) stay where they are. Rationale: `clavity` is a **multi-plugin** product
(clavity-dotnet + agy-autotrain + commonmemory + shared agy docs), so the D4 "beside the *one* plugin"
rule does not map to it; and the docs are heavily cross-linked from `CLAUDE.md`, `README.md`, hooks, and
memory files — moving them is pure churn + link-rot for mostly historical/provenance material.
agy's counter (umbrella *symmetry* / avoid signaling clavity as privileged) was weighed and the owner
chose lowest-churn grandfathering. New tools follow D4; clavity is the documented special case.

### D6 — Templates: **`templates/tool-skeleton/` with `*.template` suffixes** *(owner; agy hardening adopted)*
Copy-me stubs live in a top-level `templates/tool-skeleton/` (outside `plugins/`), every file carrying a
`.template` suffix (e.g. `plugin.json.template`). Rationale for the suffix (adopted from agy): it makes
it **mechanically impossible** for any parser/globber (marketplace loader, CI, plugin discovery) to
ingest the skeleton as a live tool — defense-in-depth beyond the fact that today nothing globs
`plugins/*` or `installer/*`.

### D7 — Branch/`main` split: the load-bearing invariant *(verified against the live repo; from AGY-AFTER panel round 1)*
The panel challenged a loose "plugin/docs/**installer/CI** at main" phrasing in an earlier draft. Verified
against the real repo (`git ls-tree origin/main` vs `origin/clavity-classic`):

- **On the tool's BRANCH** (`<tool>`, where the code lives): the source, `installer/<tool>.iss`, and the
  reusable `build-<tool>.yml`. Confirmed: `installer/clavity-classic.iss` and `build-classic.yml` live on
  `clavity-classic`, **not** `main`. The branch-side release build runs here (code SHA-pinned).
- **On `main`**: the Claude-Code plugin `plugins/<tool>/` (so root `marketplace.json` resolves
  `./plugins/<tool>`), the `marketplace.json` entry, the ROADMAP section, and the release *orchestration*
  workflow, which reaches into the branch via `uses: …@<branch>`.

So the correct statement of the pattern is **"code + installer + build-workflow at branch; plugin (+
marketplace/ROADMAP/orchestration) at `main`."** Every §4/§5 reference is corrected to this.

> **New unsolved integration point (named for the plan, D8-adjacent):** neither existing tool exercises
> the hard case. `clavity-dotnet` is *entirely on `main`* (no cross-branch step). `clavity-classic` ships
> **no plugin** in its installer (only the `agy-mcp-bridge` add-on). **`ghidrust` will be the first tool
> that is code-on-branch AND ships a plugin**, so its branch-side release build must obtain
> `plugins/ghidrust/` (which lives on `main`) to bundle it into the installer. This spec does not solve
> that bundling mechanism (ghidrust onboarding is out of scope) but **names it as a required design
> decision for the ghidrust session** and for the onboarding playbook (§5) to flag. Candidate approaches
> to evaluate then: (a) release workflow checks out `main` to stage the plugin before ISCC; (b) the plugin
> is duplicated onto the tool branch for packaging; (c) the installer omits the plugin and the plugin is
> delivered purely via the marketplace. Do not pre-decide here.

### D8 — Naming: `<tool-id>` is a flat slug, decoupled from the git branch ref *(from AGY-AFTER panel round 2)*
The onboarding identifier `<tool-id>` is a **flat kebab slug** (e.g. `ghidrust`) used identically for the
plugin dir (`plugins/<tool-id>/`), the marketplace name, the tag prefix (`<tool-id>-v<N>`), and the
installer basename (`<tool-id>-setup-*.exe`). It must **not** contain a slash — a hierarchical git branch
like `tools/ghidrust` would produce a malformed tag `tools/ghidrust-v1` and a wrong dir
`plugins/tools/ghidrust`. Therefore the **git branch ref is a separate variable** (`<branch-ref>`, used
only in the release orchestration's `uses: …@<branch-ref>`); the playbook and templates decouple them
(recommend `<branch-ref>` == `<tool-id>` for simplicity, but do not assume it). Additionally, the tool's
**binary name must be uniquely namespaced** to the tool (e.g. `ghidrust.exe`, `clavity-ls.exe`) — the
umbrella installs binaries onto the shared user `PATH`, so a generic name (`agent.exe`, `proxy.exe`) is a
collision / PATH-shadowing hazard. A `<tool-id>` may own **more than one plugin** (clavity owns
clavity-dotnet + agy-autotrain + commonmemory) — `<tool-id>` is the release/brand unit, not necessarily
1:1 with a plugin.

## 4. Target repository structure

Split by where each artifact lives (per D7). `clavity-dotnet` is the special case: its code is *also* on
`main`, so its installer/build sit on `main` — that does not change the general rule below.

**On `main`** (the umbrella surface + each tool's plugin):
```
ROADMAP.md                      # umbrella overview + tool index + per-tool sections (D3)
README.md                       # reframed: "what this umbrella hosts" + per-tool links
CONTRIBUTING.md                 # add a pointer to docs/hosting-a-tool.md
docs/                           # UMBRELLA / cross-cutting only, going forward (D4)
  README.md                     # NEW — states root docs/ is umbrella-only; clavity docs grandfathered;
                                #   new tools put docs beside the plugin (the D5 consistency guard)
  hosting-a-tool.md             # NEW — onboarding playbook + checklist (§5)
  superpowers/ , session-notes/ , agy-*.md   # existing clavity docs, grandfathered (D5)
plugins/<tool>/                 # per tool, on main: .claude-plugin/plugin.json, .mcp.json,
                                #   skills/<name>/SKILL.md, README.md, optional docs/
.claude-plugin/marketplace.json # single shared plugin index (unchanged shape)
templates/tool-skeleton/        # NEW — copy-me stubs, all *.template (D6)
installer/clavity-dotnet.iss    # clavity-dotnet is code-on-main, so ITS installer is on main
.github/workflows/
  ci.yml                        # unchanged (targets clavity-classic branch)
  build-dotnet.yml              # unchanged reusable clavity-dotnet build block (code-on-main)
  <clavity release workflow>    # umbrella-release.yml reframed as the clavity-product release (D2)
  release-<tool>.yml            # NEW per-tool release ORCHESTRATION, tag-filtered <tool>-v* (D2);
                                #   reaches into the tool branch via uses: …@<branch>
```
**On each tool's own branch `<tool>`** (code + packaging, per D7):
```
<tool source>
installer/<tool>.iss            # the tool's installer lives with its code
.github/workflows/build-<tool>.yml   # reusable build block the release orchestration calls @<branch>
```

## 5. The onboarding playbook (`docs/hosting-a-tool.md`)

A numbered, copy-followable checklist — the generalized, repo-side counterpart to a tool's `HANDOFF.md`.
It is grouped into explicit **branch phases** with hard `git checkout` boundaries, because the artifacts
straddle two branches (D7) and a naive sequential run would otherwise commit the plugin to the tool
branch or the installer to `main`. (This phasing fixes an ordering hazard the AGY-AFTER panel flagged.)

**Phase A — on the tool branch `<tool>` (`git checkout -b <tool>`):** everything that ships *with the
code*.
0. **Precondition:** the branch must contain this prep's `templates/tool-skeleton/` (they live on `main`).
   A branch cut *before* this prep merged (e.g. an in-flight `ghidrust`) must first `git merge main` (or
   `git checkout main -- templates/tool-skeleton`) so the skeleton files exist in its tree. (AGY-AFTER
   round-3 point.)
1. Push the tool's source to branch `<tool>`.
2. Add `installer/<tool>.iss` from `templates/tool-skeleton/installer.iss.template` (per-user, PATH,
   uninstall).
3. Add `.github/workflows/build-<tool>.yml` (reusable build block). Call sub-workflows by local path
   (`uses: ./…`) where possible; keep any cross-branch `@ref` code checkout SHA-pinned.
4. Stage the built binary in `publish/` per the tool's build recipe.

**Phase B — on `main` (`git checkout main`):** the umbrella surface + the plugin.
5. Create `plugins/<tool>/` from `templates/tool-skeleton/`: `plugin.json`, `.mcp.json` (runs the
   installed binary, e.g. `<binary> serve`), `skills/<name>/SKILL.md`, `README.md`, optional `docs/`.
6. Add one entry to `.claude-plugin/marketplace.json` (`source: ./plugins/<tool>`).
7. Add `.github/workflows/release-<tool>.yml` — release *orchestration*, tag-filtered `<tool>-v*`,
   reaching into the branch via `uses: …@<tool>`. Confirm the tag-protection ruleset covers `<tool>-v*`
   (§6).
8. Add a `## <tool>` section to `ROADMAP.md`.

**Phase C — cut the release.**
9. Push tag `<tool>-v1` **on `main`** (matching the clavity precedent: `clavity-v<N>` is tagged on `main`).
   The tag must land where the `release-<tool>.yml` orchestration lives so CI fires; the workflow then
   reaches the branch's code via `uses: …@<branch-ref>` + SHA-pin. Verify the GitHub Release + installer +
   `.sha256` are produced and the plugin resolves in the marketplace.
   > *Do NOT tag on the tool branch* to "fix" the auto "Source code (zip)" asset (an AGY-AFTER round-3
   > suggestion, rejected): a branch-tip tag wouldn't find the main-resident orchestration and CI would
   > silently not trigger (the round-1 ghost-trigger trap). GitHub's auto source-zip reflecting `main` is a
   > known cosmetic — the shipped deliverable is the installer asset; the branch is the SHA-pinned source
   > of truth for the build.

(Throughout, `<tool>` is the flat `<tool-id>` slug of D8; `<branch-ref>` may differ and is used only in
the release orchestration's `uses: …@<branch-ref>`.)

**De-listing / sunsetting a tool** (symmetric teardown — hosting implies un-hosting; from AGY-AFTER panel
round 2). Deleting a tool branch *first* leaves `main` broken: a `release-<tool>.yml` whose
`uses: …@<branch-ref>` hard-fails, a dangling `plugins/<tool>/`, and a dead `marketplace.json` entry.
Correct order — **decouple from `main` before deleting the branch**:
1. Remove the `marketplace.json` entry (stops the plugin being served).
2. Delete `plugins/<tool>/` and its `ROADMAP.md` section (or move the section to a "Sunset" list).
3. Delete `.github/workflows/release-<tool>.yml` (removes the dangling cross-branch `uses:`).
4. Optionally leave the last published GitHub Release/tag for existing installs (immutable), or mark it
   deprecated in its notes.
5. Only now delete the tool branch.

The playbook header states the load-bearing conventions up front: the D7 branch/`main` split; the
**unsolved cross-branch plugin-bundling** question (D7 note — a code-on-branch tool that also ships a
plugin must decide how its branch-side build obtains `plugins/<tool>/` from `main`); per-tool release
lineage (D2); tag-namespace protection (§6); the `*.template` rule (D6); and that new tools put docs
beside the plugin while the grandfathered clavity root docs are the documented exception (D5).

## 6. CI generalization details

- **Reframe** the current umbrella release into the **clavity-product** release (it keeps bundling the
  dotnet + classic variants). **Do NOT rename the file on disk** — `umbrella-release.yml` is referenced by
  name in `CONTRIBUTING.md` and a `build-dotnet.yml` comment (verified; there are no status badges), so a
  rename only causes doc drift for zero gain. Change only the internal `name:` key, header comment, and
  prose so "clavity release" no longer implies "the only release." Keep the resolve-classic SHA-pinning
  and per-branch build-block pattern already proven.
- **Per-tool release is delivered as a TEMPLATE, not a live workflow.** This prep ships
  `release-tool.yml.template` + `build-tool.yml.template` (in `templates/`, per D6) — instantiated per
  tool during onboarding (Phase B/A of §5). No live `release-<tool>.yml` is committed until a real tool
  exists, so this work needs no dummy tool to be complete. The template filters strictly on `<tool>-v*`,
  reuses build → smoke → `.sha256` → publish blocks, and sets an explicit `make_latest` policy.
- **`make_latest` policy** *(owner-settled 2026-07-09: pin clavity as flagship)* — the `clavity` release
  claims the "Latest" badge; every tool release publishes with `make_latest: false` so a `ghidrust` patch
  can't hijack the umbrella repo's "Latest" sidebar. Exact mechanism (softprops `make_latest` input on
  each `action-gh-release` step) to be wired in the plan; the policy itself is fixed.
- **Tag protection** — enforce at **two layers** (a per-workflow filter alone does not protect the git
  namespace — a stray `v1.0.0` still pushes and clutters Releases; AGY-AFTER panel point): (1) a GitHub
  **repo ruleset** on tags rejecting any tag not matching `^(clavity|<tool>|…)-v[0-9]+` at push time; and
  (2) each release workflow triggering only on its own tool's `<tool>-v*` prefix.
- **`@ref` discipline** — prefer local-path `uses: ./.github/workflows/…` so a tool branch relies on its
  own contemporaneous build block; where a cross-branch `@ref` is unavoidable (as today's
  `build-classic.yml@clavity-classic`), keep the *code* checkout SHA-pinned separately.

## 7. Templates (`templates/tool-skeleton/`)

All files `*.template`, with `<TOOL-ID>` / `<BRANCH-REF>` / `<BINARY>` / `<VERSION>` placeholders (D8):
`plugin.json.template`, `mcp.json.template`, `SKILL.md.template`, `installer.iss.template`,
`marketplace-entry.json.template`, `README.md.template`, and the CI templates `release-tool.yml.template`
+ `build-tool.yml.template` (§6).

**Stretch (not in this work):** a `scripts/new-tool.ps1` scaffolder that stamps the templates out with a
tool name, to counter static-skeleton rot. Deferred; the static templates + playbook are the floor.

## 8. Verification

- `marketplace.json` still parses and resolves its **3 existing** plugins (agy-autotrain, clavity-dotnet,
  commonmemory) — no accidental change to the clavity family.
- The clavity release workflow + `build-dotnet.yml` still parse (YAML lint / `act`-dry or syntax check);
  no behavioral change to the dotnet build/smoke.
- No existing doc link broken by the restructure (grandfathering keeps clavity doc paths stable; verify
  `CLAUDE.md` / `README.md` links still resolve after the README reframe).
- Every file under `templates/tool-skeleton/` carries a `.template` suffix; confirm nothing in
  `marketplace.json` or CI globs it.
- `docs/hosting-a-tool.md` checklist is self-consistent with the target structure (§4) and the incoming
  `ghidrust` `HANDOFF.md` maps cleanly onto it (spot-check, without onboarding ghidrust).

Verification of the NEW deliverables (not just the grandfathered clavity surface):
- **ROADMAP restructure** — `ROADMAP.md` renders; the tool index links resolve; the clavity section
  retains all prior shipped/backlog content (nothing dropped in the reshuffle).
- **CI templates** — `release-tool.yml.template` + `build-tool.yml.template` pass `actionlint`/`yq` after
  a placeholder substitution into a throwaway file (they are `.template`, so they aren't valid workflow
  paths in place — validate a rendered copy, discard it). This proves the pattern is well-formed **without
  committing a live `release-<tool>.yml` or scaffolding a dummy tool** (which would cross into onboarding
  scope).
- **Reframed clavity workflow** — `umbrella-release.yml` still parses and its job graph is unchanged
  (only `name:`/comments/prose edited); no behavioral diff.
- **Templates** — each renders to syntactically valid target output when placeholders are substituted
  (`plugin.json.template` → valid JSON, `installer.iss.template` → ISCC-parseable, etc.).

## 9. Open items deferred to the plan

- Final template placeholder tokens and whether `README.md`'s reframe is a rewrite or an additive
  "Tools hosted here" section.
- **Cross-branch plugin bundling** (D7 note) — the mechanism by which a code-on-branch tool that also
  ships a plugin gets `plugins/<tool>/` into its branch-side installer build. Not decided here; owned by
  the ghidrust onboarding session. The playbook must flag it so the first such tool doesn't discover it
  at release time.

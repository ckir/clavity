# Umbrella-Repo Preparation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended)
> or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Generalize the `clavity` repo from one product into an umbrella that hosts several
independently-released tools under one repeatable pattern — **without** onboarding any new tool.

**Architecture:** Preparation-only. Add copy-me `templates/tool-skeleton/*.template`, an onboarding
playbook + a `docs/` umbrella-only guard, restructure `ROADMAP.md`/`README.md` for multiple tools, and
reframe the existing release workflow's prose. No behavioral change to the shipped clavity build.

**Tech Stack:** Markdown docs, JSON manifests, Inno Setup (`.iss`), GitHub Actions YAML. Validation via
`node` (JSON), `yq` (YAML), and ISCC where available.

**Spec:** `docs/superpowers/specs/2026-07-09-umbrella-repo-prep-design.md` (decisions D1–D8).

---

## Token-Efficiency Contract (execution rules — the optimization to verify)

This plan is written to minimize tokens *at execution time*. Whoever runs it MUST honor these:

1. **Anchored edits, no blind reads.** Every task that modifies an existing file quotes the exact
   `old_string` → `new_string` here. Apply the Edit directly. Do **NOT** re-open the whole file to
   "find" the anchor — the anchor is already in this plan. (Read only the ±5 lines around an anchor if
   an Edit fails on a uniqueness collision.)
2. **New-file content is quoted once; copy verbatim.** Do not re-derive or "improve" it.
3. **Model tiers (per user's bottom-up gating).** Each task is tagged `[Haiku]`, `[Sonnet]`, or
   `[owner]`. Pure mechanical file-creation → Haiku. Prose/edit judgment → Sonnet. Repo-settings →
   owner-run. A subagent-driven run SHOULD batch the `[Haiku]` file-creation tasks (1–3) into **one**
   Haiku subagent — the content is fully specified, zero judgment.
4. **Cheap verification only.** Validate with `node -e`/`yq`, never by reading whole files into context.
5. **Templates are authored once (Task 1).** Later tasks and the playbook *reference* them by path — no
   task re-inlines a template body.

> **STATE-VERIFICATION (Step 0 for every editing task):** before editing, confirm the quoted `old_string`
> exists verbatim. If it differs from what's in the file, STOP and report `STATE_MISMATCH: <what>` rather
> than adapting — the repo may have drifted since this plan was written (2026-07-09).

> **Commit idempotency:** every `git commit` step below is written bare for readability. On a re-run where
> the change already landed, append `|| echo "already committed"` so a "nothing to commit" exit 1 does not
> crash the executor (as Task 9 Step 6 already shows).

---

## File map

**Created (new):**
- `templates/tool-skeleton/plugin.json.template`
- `templates/tool-skeleton/mcp.json.template`
- `templates/tool-skeleton/SKILL.md.template`
- `templates/tool-skeleton/installer.iss.template`
- `templates/tool-skeleton/marketplace-entry.json.template`
- `templates/tool-skeleton/README.md.template`
- `templates/tool-skeleton/release-tool.yml.template`
- `templates/tool-skeleton/build-tool.yml.template`
- `docs/README.md` — umbrella-only docs guard (D4/D5)
- `docs/hosting-a-tool.md` — onboarding playbook (§5)
- `README-CLAVITY.md` — extracted clavity product manual (owner decision 2026-07-09)

**Modified:**
- `ROADMAP.md` — umbrella preamble + tool index; wrap existing content under `# clavity`
- `README.md` — reframe to a thin umbrella router
- `CONTRIBUTING.md` — pointer to the playbook
- `.github/workflows/umbrella-release.yml` — `name:`/comment/prose reframe only (no behavioral change)

**Settings (owner-run, not a file commit):**
- GitHub repo tag-protection ruleset (§6)

**Placeholder tokens used by every template:** `<TOOL-ID>` (flat kebab slug), `<BRANCH-REF>` (git
branch, default == `<TOOL-ID>`), `<BINARY>` (PATH binary name), `<VERSION>` (semver), `<DESCRIPTION>`
(one line), `<SKILL-NAME>` (skill dir). `FILL:` comments mark intentional per-tool extension points
(tool-specific build steps) — they are template design, **not** plan gaps.

---

## Task 0: Create the working branch  [Sonnet]

**Files:** none (git only).

- [ ] **Step 1: Branch off `main`**

Run:
```bash
git checkout -b umbrella-repo-prep
```
Expected: `Switched to a new branch 'umbrella-repo-prep'`. (All commits below land here; do not push
until the owner asks.)

---

## Task 1: Author the tool-skeleton templates  [Haiku]

**Files (create all eight):** the `templates/tool-skeleton/*.template` set from the File map.

- [ ] **Step 1: `templates/tool-skeleton/plugin.json.template`**

```json
{
  "name": "<TOOL-ID>",
  "version": "<VERSION>",
  "description": "<DESCRIPTION>"
}
```

- [ ] **Step 2: `templates/tool-skeleton/mcp.json.template`**

```json
{
  "mcpServers": {
    "<TOOL-ID>": { "command": "<BINARY>", "args": ["serve"] }
  }
}
```

- [ ] **Step 3: `templates/tool-skeleton/SKILL.md.template`**

```markdown
---
name: <SKILL-NAME>
description: <DESCRIPTION>
---

<!-- FILL: how the agent should drive <TOOL-ID>. Replace this body with the tool's real guidance. -->
```

- [ ] **Step 4: `templates/tool-skeleton/marketplace-entry.json.template`**

```json
    {
      "name": "<TOOL-ID>",
      "source": "./plugins/<TOOL-ID>",
      "description": "<DESCRIPTION>"
    }
```

- [ ] **Step 5: `templates/tool-skeleton/README.md.template`**

```markdown
# <TOOL-ID>

<DESCRIPTION>

## Install
Ships in the `clavity` umbrella. Install via the `<TOOL-ID>-v<N>` GitHub Release installer
(`<TOOL-ID>-setup-<VERSION>.exe`), or add the plugin from this repo's marketplace.

## What it provides
- Binary `<BINARY>` on your PATH; the plugin runs `<BINARY> serve` as an MCP server.
<!-- FILL: list the tool's MCP tools / skills. -->

## Configuration
<!-- FILL: env vars / flags the .mcp.json env block must carry, or "none". -->

## Uninstall
Windows Add/Remove Programs (removes the binary + its PATH entry).
```

- [ ] **Step 6: `templates/tool-skeleton/installer.iss.template`**

```
; Inno Setup script for <TOOL-ID>. Build: ISCC.exe installer\<TOOL-ID>.iss
; Expects (produced by the tool's build recipe / build-<TOOL-ID>.yml):
;   ..\publish\<BINARY>   — the tool's single-file binary
; If <TOOL-ID> ALSO ships a plugin, staging plugins\<TOOL-ID>\ here is the D7 open question —
; see docs/hosting-a-tool.md before wiring it.

#define AppName "<TOOL-ID>"
#define AppVersion "<VERSION>"
#define ExeName "<BINARY>"

[Setup]
; Stable AppId so upgrades replace in place — GENERATE A FRESH GUID per tool (never reuse another tool's).
AppId={{REPLACE-WITH-A-FRESH-GUID}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=clavity
DefaultDirName={localappdata}\Programs\<TOOL-ID>
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=<TOOL-ID>-setup-{#AppVersion}
OutputDir=..\dist
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
ChangesEnvironment=yes

[Files]
Source: "..\publish\{#ExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Tasks]
Name: "addtopath"; Description: "Add <TOOL-ID> to PATH"; Flags: checkedonce

[Registry]
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; \
  ValueData: "{olddata};{app}"; Tasks: addtopath; Check: NeedsAddPath('{app}')

[Code]
function NeedsAddPath(Param: string): Boolean;
var
  OrigPath: string;
begin
  if not RegQueryStringValue(HKCU, 'Environment', 'Path', OrigPath) then
  begin
    Result := True;
    exit;
  end;
  Result := Pos(';' + Param + ';', ';' + OrigPath + ';') = 0;
end;

procedure RemoveFromUserPath(const Dir: string);
var
  Path: string;
begin
  if not RegQueryStringValue(HKCU, 'Environment', 'Path', Path) then
    exit;
  StringChangeEx(Path, ';' + Dir, '', True);
  StringChangeEx(Path, Dir + ';', '', True);
  StringChangeEx(Path, Dir, '', True);
  RegWriteExpandStringValue(HKCU, 'Environment', 'Path', Path);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    RemoveFromUserPath(ExpandConstant('{app}'));
end;
```

- [ ] **Step 7: `templates/tool-skeleton/build-tool.yml.template`**

```yaml
name: build-<TOOL-ID>

# Reusable build+package block for the <TOOL-ID> release, minus publish. Lives ON THE TOOL BRANCH with
# the code (D7). Called by release-<TOOL-ID>.yml and runnable via workflow_dispatch.
on:
  workflow_call:
    inputs:
      ref:
        description: 'Tool-branch commit to build (SHA-pinned by the caller; blank = default ref).'
        required: false
        type: string
        default: ''
    outputs:
      version:
        value: ${{ jobs.build.outputs.version }}
      sha:
        value: ${{ jobs.build.outputs.sha }}
      artifact-name:
        value: ${{ jobs.build.outputs.artifact-name }}
  workflow_dispatch:
    inputs:
      ref:
        description: 'Commit/branch to build (blank = the branch this run is on).'
        required: false
        type: string
        default: ''

jobs:
  build:
    runs-on: windows-latest
    outputs:
      version: ${{ steps.ver.outputs.version }}
      sha: ${{ steps.sha.outputs.sha }}   # the ACTUAL built commit — NOT github.sha, which is the caller's
                                           # tag-on-main commit, not the tool code checked out below.
      artifact-name: <TOOL-ID>-installer
    steps:
      # SHA-pinned tool-branch checkout. A NAKED checkout would fetch the CALLER's ref (the tag on main),
      # NOT the tool's code, which lives on the branch (D7) — the build would run against the wrong tree.
      # The release orchestration passes the resolved SHA; a blank ref (standalone dispatch on the branch)
      # falls back to the default ref.
      - uses: actions/checkout@v4
        with:
          ref: ${{ inputs.ref }}

      - name: Record the built commit
        id: sha
        shell: bash
        run: echo "sha=$(git rev-parse HEAD)" >> "$GITHUB_OUTPUT"

      # FILL(per-tool): install the tool's build toolchain (e.g. actions/setup-* / rustup / dtolnay).

      - name: Extract version from .iss
        id: ver
        shell: pwsh
        run: |
          $v = (Select-String -Path installer/<TOOL-ID>.iss -Pattern '#define AppVersion "([^"]+)"').Matches[0].Groups[1].Value
          "version=$v" | Out-File -FilePath $env:GITHUB_OUTPUT -Append
          "TOOL_VER=$v" | Out-File -FilePath $env:GITHUB_ENV -Append

      # FILL(per-tool): build the binary into publish/<BINARY> per the tool's build recipe.

      # OPEN QUESTION (D7 / docs/hosting-a-tool.md): a code-on-branch tool that ALSO ships a plugin must
      # stage plugins/<TOOL-ID>/ (which lives on main) HERE before ISCC. Decide the mechanism during
      # onboarding — do NOT leave unresolved for a plugin-shipping tool.

      - name: Install Inno Setup
        shell: pwsh
        run: choco install innosetup --no-progress -y

      - name: Build installer (ISCC)
        shell: pwsh
        run: |
          $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
          if (-not (Test-Path $iscc)) { throw "ISCC.exe not found at $iscc" }
          & $iscc installer/<TOOL-ID>.iss
          if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }
          $setup = "dist/<TOOL-ID>-setup-$env:TOOL_VER.exe"
          if (-not (Test-Path $setup)) { throw "$setup was not produced" }

      - name: Compute SHA-256 companion
        shell: pwsh
        run: |
          $name = "<TOOL-ID>-setup-$env:TOOL_VER.exe"
          $h = (Get-FileHash "dist/$name" -Algorithm SHA256).Hash.ToLower()
          "$h  $name" | Set-Content -Path "dist/$name.sha256" -Encoding ascii

      - name: Upload installer artifact
        uses: actions/upload-artifact@v4
        with:
          name: <TOOL-ID>-installer
          path: |
            dist/<TOOL-ID>-setup-*.exe
            dist/<TOOL-ID>-setup-*.exe.sha256
```

- [ ] **Step 8: `templates/tool-skeleton/release-tool.yml.template`**

```yaml
name: release-<TOOL-ID>

# THE release entry point for the <TOOL-ID> tool. A <TOOL-ID>-v<N> tag builds the installer and publishes
# the tool's OWN GitHub Release (per-tool lineage, D2). Lives on MAIN (orchestration); reaches the tool's
# code + build block on its branch via uses: ...@<BRANCH-REF> (D7).
on:
  push:
    tags:
      - '<TOOL-ID>-v*'
  workflow_dispatch:
    inputs:
      tag:
        description: 'Release tag (e.g. <TOOL-ID>-v1) — REQUIRED on dispatch (a dispatch has no triggering tag).'
        required: true
        type: string

permissions:
  contents: write

concurrency:
  group: release-<TOOL-ID>
  cancel-in-progress: false

jobs:
  resolve-ref:
    # Pin the tool-branch commit ONCE at cut time (D7 SHA-pin) so a re-run weeks later rebuilds the SAME
    # snapshot.
    runs-on: ubuntu-latest
    outputs:
      sha: ${{ steps.r.outputs.sha }}
    steps:
      - id: r
        shell: bash
        run: |
          sha=$(git ls-remote https://github.com/${{ github.repository }} refs/heads/<BRANCH-REF> | cut -f1)
          if [ -z "$sha" ]; then echo "::error::could not resolve <BRANCH-REF> SHA"; exit 1; fi
          echo "sha=$sha" >> "$GITHUB_OUTPUT"

  build:
    needs: resolve-ref
    # Cross-branch: the reusable build block FILE is loaded from the tool branch tip (D7). owner/repo is
    # HARDCODED — Actions forbids expressions in `uses:` (a fork calls this upstream, as build-classic does).
    # The CODE checkout is SHA-pinned separately via the `ref` input below (§6 @ref discipline).
    uses: ckir/clavity/.github/workflows/build-<TOOL-ID>.yml@<BRANCH-REF>
    with:
      ref: ${{ needs.resolve-ref.outputs.sha }}

  publish:
    needs: build
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: Download installer
        uses: actions/download-artifact@v4
        with:
          name: ${{ needs.build.outputs.artifact-name }}
          path: dist

      - name: Assemble release notes
        id: notes
        shell: bash
        env:
          # Pass the dispatch-supplied tag via env, NOT inline ${{…}} interpolation, so a crafted
          # workflow_dispatch input cannot inject shell (Actions script-injection hardening). ref_name on a
          # tag push is constrained by the tag ruleset, so it stays inline.
          TAG_INPUT: ${{ github.event.inputs.tag }}
        run: |
          TAG="$TAG_INPUT"
          if [ -z "$TAG" ]; then TAG="${{ github.ref_name }}"; fi
          echo "tag=$TAG" >> "$GITHUB_OUTPUT"
          cat > body.md <<EOF
          # <TOOL-ID> $TAG

          | tool | version | source |
          |------|---------|--------|
          | <TOOL-ID> | ${{ needs.build.outputs.version }} | <BRANCH-REF>@${{ needs.build.outputs.sha }} |

          Installer is **unsigned** (Windows SmartScreen may warn: *More info -> Run anyway*).
          Verify the \`.sha256\` against the \`.exe\` before running.
          EOF

      - name: Publish the <TOOL-ID> release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ steps.notes.outputs.tag }}
          name: ${{ steps.notes.outputs.tag }}
          body_path: body.md
          make_latest: false   # D2/§6: only the clavity flagship claims the "Latest" badge
          files: |
            dist/<TOOL-ID>-setup-*.exe
            dist/<TOOL-ID>-setup-*.exe.sha256
```

- [ ] **Step 9: Verify the JSON + CI templates render to valid targets**

Render the JSON + CI templates with placeholders substituted into a throwaway dir, then parse. Run (Bash):
```bash
command -v node >/dev/null && command -v yq >/dev/null || { echo "need node + yq on PATH"; exit 1; }
SCRATCH=$(mktemp -d); T="templates/tool-skeleton"
sed -e 's/<TOOL-ID>/ghidrust/g' -e 's/<VERSION>/1.0.0/g' -e 's/<BINARY>/ghidrust/g' \
    -e 's/<DESCRIPTION>/x/g' "$T/plugin.json.template" > "$SCRATCH/plugin.json"
sed -e 's/<TOOL-ID>/ghidrust/g' -e 's/<BINARY>/ghidrust/g' "$T/mcp.json.template" > "$SCRATCH/mcp.json"
node -e "JSON.parse(require('fs').readFileSync('$SCRATCH/plugin.json','utf8')); JSON.parse(require('fs').readFileSync('$SCRATCH/mcp.json','utf8')); console.log('JSON OK')"
sed -e 's/<TOOL-ID>/ghidrust/g' -e 's/<BRANCH-REF>/ghidrust/g' "$T/release-tool.yml.template" > "$SCRATCH/release.yml"
sed 's/<TOOL-ID>/ghidrust/g' "$T/build-tool.yml.template" > "$SCRATCH/build.yml"
yq '.' "$SCRATCH/release.yml" > /dev/null && yq '.' "$SCRATCH/build.yml" > /dev/null && echo "YAML OK"
rm -rf "$SCRATCH"
```
Expected: `JSON OK` then `YAML OK`. (`marketplace-entry.json.template` is a fragment, not standalone
JSON — it is validated in Task 9 by splicing into `marketplace.json`.)

- [ ] **Step 10: Verify `installer.iss.template` is ISCC-parseable (spec §8; Windows, tool-gated)**

The template is inert (placeholders + no real binary), so validate a RENDERED copy against a stub source.
Run (Git Bash on Windows; skips cleanly where ISCC is absent):
```bash
ISCC="/c/Program Files (x86)/Inno Setup 6/ISCC.exe"
if [ ! -f "$ISCC" ]; then
  echo "ISCC absent — .iss parse deferred to tool onboarding (template is inert)"
else
  S=$(mktemp -d); mkdir -p "$S/installer" "$S/publish" "$S/dist"
  sed -e 's/<TOOL-ID>/ghidrust/g' -e 's/<VERSION>/1.0.0/g' -e 's/<BINARY>/ghidrust.exe/g' \
      -e 's/{{REPLACE-WITH-A-FRESH-GUID}/{{6F9619FF-8B86-D011-B42D-00CF4FC964FF}/' \
      templates/tool-skeleton/installer.iss.template > "$S/installer/ghidrust.iss"
  : > "$S/publish/ghidrust.exe"   # stub source so [Files] resolves
  "$ISCC" "$(cygpath -w "$S/installer/ghidrust.iss")" >/dev/null && echo "ISCC OK" || { echo "ISCC FAILED"; rm -rf "$S"; false; }
  rm -rf "$S"
fi
```
Expected: `ISCC OK` (or the "deferred" notice if Inno Setup isn't installed on this machine).

- [ ] **Step 11: Commit**

```bash
git add templates/tool-skeleton
git commit -m "feat(umbrella): add tool-skeleton templates (D6/D8)"
```

---

## Task 2: Add the `docs/` umbrella-only guard  [Haiku]

**Files:** Create `docs/README.md`.

- [ ] **Step 1: Create `docs/README.md`**

```markdown
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
```

- [ ] **Step 2: Commit** (bundled with Task 3.)

---

## Task 3: Write the onboarding playbook  [Sonnet]

**Files:** Create `docs/hosting-a-tool.md`.

- [ ] **Step 1: Create `docs/hosting-a-tool.md`**

````markdown
# Hosting a tool in the `clavity` umbrella

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
````

- [ ] **Step 2: Commit docs (Tasks 2 + 3)**

```bash
git add docs/README.md docs/hosting-a-tool.md
git commit -m "docs(umbrella): add docs/ umbrella-only guard + hosting-a-tool playbook (D4/D5/§5)"
```

---

## Task 4: Restructure `ROADMAP.md`  [Sonnet]

**Files:** Modify `ROADMAP.md:1-8` (title + intro block only; all content from `## What clavity is now`
down is preserved verbatim by nesting it under a new `# clavity` heading).

- [ ] **Step 1: Prepend the umbrella preamble + tool index and open the clavity section**

Edit — replace this exact block (lines 1–8):
```
# clavity ROADMAP

> **Live roadmap — reconciled 2026-06-30.** This file is the single forward-looking source of truth.
> It supersedes the original 2026-06-16 driving-session roadmap (now folded into **§ Shipped — history**
> below). Detail for each item lives in `docs/superpowers/specs/` + `docs/superpowers/plans/`; this file
> tracks **what is done** and **what is next, in order**.

---
```
with:
```
# clavity umbrella — ROADMAP

> **Umbrella roadmap.** This repository is a **host for several independently-released tools** under the
> `clavity` brand. Each tool follows one pattern — code on its own branch; a plugin under
> `plugins/<tool>/` on `main`; an Inno-Setup installer; its own `<tool>-v<N>` release lineage — see
> [`docs/hosting-a-tool.md`](docs/hosting-a-tool.md). This file carries an umbrella overview, a tool
> index, and one roadmap section per hosted tool.

## Hosted tools
| Tool | What it is | Release lineage |
|------|-----------|-----------------|
| [`clavity`](#clavity) | Pairs Claude with a live Antigravity (`agy`) peer (dotnet + classic variants). | `clavity-v<N>` |

*(New tools add a row here and a `# <tool>` section below during onboarding — see the playbook, Phase B.)*

---

# clavity

> **Live roadmap — reconciled 2026-06-30.** This file is the single forward-looking source of truth.
> It supersedes the original 2026-06-16 driving-session roadmap (now folded into **§ Shipped — history**
> below). Detail for each item lives in `docs/superpowers/specs/` + `docs/superpowers/plans/`; this file
> tracks **what is done** and **what is next, in order**.

---
```

- [ ] **Step 2: Verify the file still renders and the clavity content is intact**

Run (Bash):
```bash
grep -n '^# clavity umbrella — ROADMAP' ROADMAP.md && grep -n '^# clavity$' ROADMAP.md \
  && grep -c '^## What clavity is now' ROADMAP.md
```
Expected: the umbrella title (line 1), the `# clavity` heading, and `1` (the preserved section).

- [ ] **Step 3: Commit**

```bash
git add ROADMAP.md
git commit -m "docs(umbrella): restructure ROADMAP into umbrella overview + tool index + clavity section (D3)"
```

---

## Task 5: Reframe `README.md` + extract `README-CLAVITY.md`  [Sonnet]

**Files:** Create `README-CLAVITY.md`; overwrite `README.md` with a thin umbrella router.

- [ ] **Step 1: Create `README-CLAVITY.md` (the extracted clavity product manual)**

Write the following (this is the current README body, re-titled and with the umbrella framing removed):
````markdown
# clavity — pair Claude with a live agy peer

Clavity pairs [Claude Code](https://claude.com/claude-code) with [Antigravity (`agy`)](https://antigravity.google),
shipped as universal dual-plugins. It is one tool in the [`clavity` umbrella](README.md).

## Quick Start

Run this in **PowerShell** (not `cmd.exe`) to install:

```powershell
irm https://raw.githubusercontent.com/ckir/clavity/main/install/clavity-install.ps1 | iex
```

*Note: The installer is unsigned, so Windows SmartScreen may warn on first run (choose "More info" →
"Run anyway"). The script resolves the latest GitHub release and verifies the installer's SHA-256
automatically.*

The installer will prompt you to choose between the **.NET** (Primary) or **Classic** (Failover) host
variant, and allow you to opt-in to extras like `agy-autotrain` or `commonmemory`.

Start a paired session:
```powershell
clavity-ls start C:\path\to\your\project
```

*(To uninstall, use Windows Add/Remove Programs. It cleanly de-registers the plugin from each agent).*

## The Ecosystem

Clavity is split into **Core Hosts** (the routing engines) and **Extra Plugins** (optional skills). The
single installation script handles both.

### The Core Hosts (Pick One)

- **`clavity-dotnet` (Primary)**
  The modern, greenfield **.NET 10** rebuild. It turns `agy` into an interactive superpower for Claude via
  a local Language Server (LS-API MCP bridge). Claude spawns an MCP server that exposes three core tools:
  - `agy_look` / `agy_status`: Check what `agy` is doing.
  - `agy_ask`: Send a task or message to `agy` and wait for its reply. Useful for design review, second
    opinions, and delegated parallel work.
  - **Multi-session:** Each Claude instance drives its *own* isolated `agy` instance.
  - **Dynamic send-model:** Drives `agy` using the model your conversation last used, instead of forcing a
    baked-in default.

- **`clavity-classic` (Failover)**
  The original Rust-based psmux doorbell bridge. Claude drives a live, signed-in `agy` peer in the same
  folder over a doorbell mechanism and the agentmemory bus (for review, second opinions, delegated work).
  **This is a fallback solution.** If a future `antigravity-cli` update breaks the `.NET` Language Server
  integration, you can reinstall using the `classic` variant to keep working.

### The Extra Plugins (Opt-In)

- **`commonmemory`**
  A shared cross-agent memory convention. Teaches Claude and `agy` to tag notes (decisions, gotchas, bug
  fixes) with `[common]` and proactively share context via the agentmemory bus.
- **`agy-autotrain`**
  Allows Claude to drive `agy` like a model (`clavity ask`) and auto-trains clavity's knowledge from
  everyday usage. It captures insights, verifies them, and compiles them into a project-agnostic manual.

## Developer & Contributor Guide

If you want to build your own dual-plugins or contribute to Clavity, this section is for you.

### Project Layout

| Path | Role |
| --- | --- |
| `plugins/<name>/` | A universal dual-plugin (contains both manifest sets + `skills/`, ± a server). |
| `docs/plugin-formats.md` | The verified Claude + Agy plugin-format reference. |
| `docs/agy-*.md` | Agy behavior/assumptions references + design specs & plans. |

### Dual-Manifest Architecture
The two CLIs read disjoint filenames, so both manifest sets coexist in one directory:
- **Claude reads:** `.claude-plugin/plugin.json`, `.mcp.json`, `hooks/hooks.json`
- **Agy reads:** `plugin.json`, `mcp_config.json`, `hooks.json`

### Building the Source
To build the `.NET` host:
```bash
dotnet build -c Release
dotnet test -c Release --filter "Category!=LiveAgy"
```
*(Live-agy tests are gated out of CI as they require a running instance).*

### Adding a Plugin
1. Create `plugins/<name>/`.
2. Add both manifest sets and any `skills/` following `docs/plugin-formats.md`. (See `clavity-classic`
   and `commonmemory` as working examples).
````

- [ ] **Step 2: Overwrite `README.md` with the thin umbrella router**

Write:
````markdown
# clavity

[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-blue.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)]()

**clavity** is a host for several independently-released tools that pair AI coding agents with live
peers. Each hosted tool ships its own installer and its own `<tool>-v<N>` GitHub Release; this repo is
the shared home for their plugins, docs, and release machinery.

## Tools hosted here

| Tool | What it is | Docs | Release lineage |
|------|-----------|------|-----------------|
| **clavity** | Pairs [Claude Code](https://claude.com/claude-code) with [Antigravity (`agy`)](https://antigravity.google) — `.NET` + `classic` variants, plus `agy-autotrain` / `commonmemory` add-ons. | [README-CLAVITY.md](README-CLAVITY.md) | `clavity-v<N>` |

## Adding a tool

New tools follow one repeatable pattern (code on a branch; plugin under `plugins/<tool>/` on `main`; an
Inno-Setup installer; its own release lineage). See the playbook: [`docs/hosting-a-tool.md`](docs/hosting-a-tool.md).

## License

This project is licensed under the **PolyForm Noncommercial License 1.0.0** — free for non-commercial
use (personal, academic, non-profit). See [LICENSE](LICENSE).

---

> **Looking for clavity install & usage?** It moved to **[README-CLAVITY.md](README-CLAVITY.md)**.
````

- [ ] **Step 3: Verify links resolve**

Run (Bash):
```bash
test -f README-CLAVITY.md && test -f docs/hosting-a-tool.md && test -f LICENSE \
  && grep -q 'README-CLAVITY.md' README.md && echo "links OK"
```
Expected: `links OK`.

- [ ] **Step 4: Commit**

```bash
git add README.md README-CLAVITY.md
git commit -m "docs(umbrella): reframe README as umbrella router; extract README-CLAVITY.md (owner decision)"
```

---

## Task 6: Point `CONTRIBUTING.md` at the playbook  [Sonnet]

**Files:** Modify `CONTRIBUTING.md` — insert a section immediately before `## Releasing (umbrella)`
(currently `CONTRIBUTING.md:83`).

- [ ] **Step 1: Insert the pointer**

Edit — replace this exact text:
```
## Releasing (umbrella)
```
with:
```
## Hosting a new tool

`clavity` is an umbrella repo that hosts several independently-released tools. To add one, follow the
onboarding playbook: [`docs/hosting-a-tool.md`](docs/hosting-a-tool.md) (code on a branch; plugin under
`plugins/<tool>/` on `main`; per-tool `<tool>-v<N>` release lineage).

## Releasing (umbrella)
```

- [ ] **Step 2: Verify**

Run (Bash):
```bash
grep -n '## Hosting a new tool' CONTRIBUTING.md && grep -c '## Releasing (umbrella)' CONTRIBUTING.md
```
Expected: the new heading plus `1` (the original release section still present, once).

- [ ] **Step 3: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "docs(umbrella): point CONTRIBUTING at the hosting-a-tool playbook"
```

---

## Task 7: Reframe `umbrella-release.yml` prose (no behavioral change)  [Sonnet]

**Files:** Modify `.github/workflows/umbrella-release.yml:1-8` (the `name:` + header comment only). The
job graph, triggers, and steps are unchanged.

- [ ] **Step 1: Reframe the workflow name + header comment**

Edit — replace this exact block (lines 1–8):
```
name: umbrella-release

# THE single release entry point. A serial clavity-v<N> tag bundles both variants' installers into one
# GitHub Release named "clavity". Only this workflow produces releases going forward.
on:
  push:
    tags:
      - 'clavity-v*'
```
with:
```
name: release-clavity

# The clavity PRODUCT release (one of several tools in this umbrella repo — NOT the only release). A
# serial clavity-v<N> tag bundles clavity's two mutually-exclusive variants' installers into one GitHub
# Release named "clavity". Other tools release independently via their own release-<tool>.yml (see
# docs/hosting-a-tool.md). The file keeps its umbrella-release.yml name to avoid doc-drift (it is
# referenced by name in CONTRIBUTING.md and build-dotnet.yml).
on:
  push:
    tags:
      - 'clavity-v*'
```

- [ ] **Step 2: Verify YAML still parses and the job graph is unchanged**

Run (Bash):
```bash
yq '.jobs | keys' .github/workflows/umbrella-release.yml
```
Expected: `resolve-classic`, `dotnet`, `classic`, `publish` (the four existing jobs — unchanged).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/umbrella-release.yml
git commit -m "ci(umbrella): reframe clavity release workflow as one product among several (D2/§6)"
```

---

## Task 8: Tag-namespace protection ruleset  [owner]

**Files:** none — this is a GitHub **repo setting** (a tag ruleset), not a committed file. It is
**owner-run** because it changes outward-facing repo configuration and a bad pattern could reject
legitimate future tag pushes.

- [ ] **Step 1: Owner creates the tag ruleset**

Present this to the owner to run (do NOT run it unattended). Layer 1 of §6 — reject any tag not matching
the umbrella's `<tool>-v<N>` convention at push time:
```bash
gh api -X POST repos/ckir/clavity/rulesets -f name='umbrella-tag-namespace' -f target='tag' \
  -f enforcement='active' \
  -F 'conditions[ref_name][include][]=~ALL' \
  -F 'rules[][type]=tag_name_pattern' \
  -F 'rules[][parameters][operator]=regex' \
  -F 'rules[][parameters][pattern]=^(clavity)-v[0-9]+$' \
  -F 'rules[][parameters][negate]=false'
```
When a new tool is onboarded, the owner extends the pattern's alternation, e.g.
`^(clavity|ghidrust)-v[0-9]+$`. Layer 2 (each workflow's own `<tool>-v*` trigger) is already carried by
the release templates (Task 1) and the existing clavity workflow.

> This step is **optional for the prep to be complete** — it hardens the namespace but ships no code.
> If the owner defers it, note it in the ROADMAP clavity backlog and proceed; the templates already
> enforce Layer 2.

---

## Task 9: Final verification sweep  [Sonnet]

**Files:** none created; validates the whole change set with cheap checks only.

- [ ] **Step 1: marketplace.json unchanged and still valid (3 plugins)**

Run (Bash):
```bash
node -e "const m=require('./.claude-plugin/marketplace.json'); const n=m.plugins.map(p=>p.name).sort(); if(JSON.stringify(n)!==JSON.stringify(['agy-autotrain','clavity-dotnet','commonmemory'])) throw new Error('marketplace changed: '+n); console.log('marketplace OK')"
```
Expected: `marketplace OK`.

- [ ] **Step 2: `marketplace-entry.json.template` splices into a valid array**

Run (Bash):
```bash
node -e "const fs=require('fs'); let e=fs.readFileSync('templates/tool-skeleton/marketplace-entry.json.template','utf8'); e=e.replace(/<TOOL-ID>/g,'ghidrust').replace(/<DESCRIPTION>/g,'x'); JSON.parse('['+e+']'); console.log('entry template OK')"
```
Expected: `entry template OK`.

- [ ] **Step 3: every skeleton file carries `.template`, and nothing globs it**

Run (Bash):
```bash
bad=$(find templates/tool-skeleton -type f ! -name '*.template'); [ -z "$bad" ] && echo "suffix OK" || { echo "NON-TEMPLATE: $bad"; false; }
grep -rn 'templates/tool-skeleton' .claude-plugin/ .github/workflows/ installer/ 2>/dev/null || echo "no glob refs OK"
```
Expected: `suffix OK` then `no glob refs OK` (nothing in the marketplace/CI/installer references the
skeleton).

- [ ] **Step 4: umbrella-release.yml is behaviorally unchanged vs `main`**

Run (Bash):
```bash
rogue=$(git diff main -- .github/workflows/umbrella-release.yml | grep -E '^\+' | grep -vE '^\+\+\+|^\+name:|^\+#|^\+$')
[ -z "$rogue" ] && echo "only name/comment changed OK" || { echo "UNEXPECTED ADDED LINES:"; echo "$rogue"; false; }
```
Expected: `only name/comment changed OK`. (Non-empty output → the reframe changed more than `name:`/comments; the command exits non-zero so the check cannot false-pass.)

- [ ] **Step 5: no broken internal doc links introduced**

Run (Bash):
```bash
for f in docs/hosting-a-tool.md docs/README.md; do test -f "$f" || { echo "MISSING $f"; false; }; done
grep -q 'docs/hosting-a-tool.md' README.md && grep -q 'docs/hosting-a-tool.md' CONTRIBUTING.md \
  && grep -q 'README-CLAVITY.md' README.md && echo "doc links OK"
```
Expected: `doc links OK`.

- [ ] **Step 6: Commit any fixups** (only if a check above forced a change)

```bash
git add -A
git commit -m "chore(umbrella): verification fixups" || echo "nothing to fix up"
```

---

## Self-Review (completed by the plan author)

- **Spec coverage:** D1 (no rename — no task, correctly nothing to do). D2 → Tasks 1 (templates set
  `make_latest:false` + per-tool tag) + 7 (clavity reframed). D3 → Task 4. D4 → Task 2 guard + Task 3
  playbook. D5 → Task 2 guard + Task 5 (clavity grandfathered; manual at root). D6 → Task 1 (`.template`
  suffix) + Task 9 Step 3. D7 → Task 3 (branch/main split + phases + cross-branch open question) + the
  CI templates' `uses: …@<BRANCH-REF>`. D8 → Task 1 placeholder tokens + Task 3 conventions. §5 playbook
  → Task 3 (all phases + de-listing + HANDOFF mapping). §6 → Tasks 1, 7, 8. §7 templates → Task 1. §8
  verification → Task 9. §9 open items → README shape RESOLVED (owner: root `README-CLAVITY.md`);
  cross-branch bundling deferred to ghidrust and flagged in the playbook.
- **Placeholder scan:** the only `FILL:`/`OPEN QUESTION`/`REPLACE-WITH-A-FRESH-GUID` markers live
  *inside template files*, where they are intentional per-tool extension points (documented in the File
  map and Task 1) — not plan gaps.
- **Type/name consistency:** `<TOOL-ID>`, `<BRANCH-REF>`, `<BINARY>`, `<VERSION>`, `<DESCRIPTION>`,
  `<SKILL-NAME>` used identically across all templates and the playbook; artifact/output names
  (`<TOOL-ID>-installer`, `<TOOL-ID>-setup-*.exe[.sha256]`) match between `build-tool` and `release-tool`.
- **AGY-AFTER panel round 1 folded (cascade e350f145):** (1) *critical* — added SHA-pinned `ref` input +
  `resolve-ref` job to the CI templates so the cross-branch build checks out the tool BRANCH, not the
  caller's tag-on-`main` tree (mirrors the proven `umbrella-release.yml`→`build-classic` pattern); (2)
  added a global placeholder-substitution precondition to the playbook; (3) made the tag-ruleset
  extension an explicit admin gate before Phase C; (4) fixed the Task 9 Step 4 shell false-pass. agy's
  token-efficiency seat found nothing (verified — the contract holds). No settled decision was challenged.
- **AGY-AFTER panel round 2 folded (cascade e350f145):** (1) *security* — the release template passes the
  `workflow_dispatch` tag via `env:` instead of inline `${{…}}` (Actions script-injection hardening);
  (2) *correctness* — the build job now outputs `git rev-parse HEAD` (the real built commit) rather than
  `github.sha` (which would be the caller's tag-on-`main` commit → wrong release-notes provenance); (3)
  *re-entrancy* — added a global commit-idempotency note; (4) added a playbook caution against copying
  `build-dotnet.yml` (naked checkout, code-on-`main`). **Rejected #5** (agy: "README extraction breaks
  inbound deep links") — VERIFIED FALSE by grep: zero references to the root README's anchors exist in
  the repo (the only `README.md` hits are a throwaway test repo in CONTRIBUTING's runbook); the thin
  README's redirect line already covers external bookmarks.
- **AGY-AFTER panel round 3 folded (cascade e350f145):** (1) added a tool-gated ISCC render/compile check
  for `installer.iss.template` (Task 1 Step 10) to close the spec §8 coverage gap; (2) verification scratch
  dirs now use `mktemp -d` (not `$TMPDIR/tpl`, which resolves to `/tpl` when `TMPDIR` is unset); (3) added
  a `command -v node/yq` preflight. **Rejected #1** (agy: "`outputs.artifact-name` parses as subtraction →
  null") — VERIFIED FALSE: it is the exact shipped pattern in `umbrella-release.yml` (lines 69/75) +
  `build-dotnet.yml`, which has already cut `clavity-v1`; dashed output names work in Actions dot-notation.
- **AGY-AFTER panel round 4 — GREEN (cascade e350f145):** all four rotated seats (cross-reference
  integrity, verification-block executability, contradiction hunt, operator dead-ends) returned "no new
  findings"; PANEL VERDICT GREEN. Stop signal = a full panel landed no live challenge. Total: 4 rounds,
  ~7 valid findings folded (2 critical), 2 confident-but-false agy claims rejected by measurement.
````

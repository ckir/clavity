# SP-0 — Unify the driver plugins under a `clavity:` namespace — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give both driver plugins the single plugin identity `clavity` (so every shipped skill surfaces under one `clavity:<skill>` namespace), strip redundant prefixes from four skills, and rename the on-disk plugin staging dir to match — leaving marketplace *scope* names, the release roster, and cross-flavor single-install behavior unchanged.

**Architecture:** Plugin identity is decoupled from the member key. `build/members.json` keeps its unique `name` key (`clavity-dotnet`/`clavity-classic`) so every lookup/validation/roster gate stays untouched; a new `pluginName: "clavity"` field carries the actual plugin identity that `generate-scoped-manifest.ps1` emits into `plugins[].name` and the `./plugins/<id>` source path. Marketplace *scope* names stay distinct (`clavity-dotnet`/`clavity-classic`), so `claude plugin install clavity@clavity-dotnet` / `clavity@clavity-classic`. The classic responder skill is renamed only in its Claude Code plugin copy (Option A) — the binary-embedded agy-side twin stays `claudavity-responder` and both copies get enrolled in the seed sync-check. Cross-flavor single-install keeps the existing refusal logic (Option R) — no new destructive installer code. Two spikes de-risk the two unverified CLI behaviors (namespace-resolution-under-both-agents, and upgrade/collision) before and during the install smoke.

**Tech Stack:** PowerShell (build/registration tooling, Pester), Inno Setup (`.iss`), C# (`clavity-ls.exe` install path), Rust (classic binary), bash (seed sync-check), Markdown docs. Exact gates: `just test-scripts` (Pester over `scripts/tests`), `just seed-sync-check`, `just check-register-hash` / `just sync-register-hash`, `just test`, `just check-member-docs`, `just check-links`, `just check-installer-ascii`.

**Owner-settled decisions this plan encodes (do NOT re-litigate):**
- **Plugin identity via a new `pluginName` field** — NOT by renaming `members[].name` (that key collides for both drivers). Mechanism decision, source-verified.
- **Responder = Option A** — rename the Claude Code plugin copy only; agy-side `agy_skills/claudavity-responder/` stays; enroll both in the seed sync-check.
- **Cross-flavor = Option R** — keep the existing install-time refusal; ship no active cross-flavor removal.
- **Marketplace scope names, `release-lib.ps1` roster, and `Assert-RosterMatchesMembers` stay unchanged.**

**Reference spec:** `docs/superpowers/specs/2026-07-24-sp0-clavity-plugin-rename-design.md` (`da8806c`).

---

## File Structure

**Modified — plugin identity:**
- `build/members.json` — add `pluginName` to the two driver members.
- `scripts/generate-scoped-manifest.ps1` — emit plugin identity + source from `pluginName ?? name`.
- `clavity-dotnet/plugin/.claude-plugin/plugin.json`, `clavity-dotnet/plugin/plugin.json` — `name` → `clavity`.
- `clavity-classic/plugin/.claude-plugin/plugin.json`, `clavity-classic/plugin/plugin.json` — `name` → `clavity`.
- `clavity-classic/installer/clavity-classic.iss` — `RegisterMemberPlugin`/`DeregisterMemberPluginOnUninstall` first arg → `clavity`; `[Files]` DestDir → `plugins\clavity`.
- `clavity-dotnet/installer/clavity-dotnet.iss` — `[Files]` DestDir → `plugins\clavity`.
- `clavity-dotnet/src/Clavity.Ls/Install/PluginInstaller.cs` — `PluginName` const → `clavity` (rebuild `clavity-ls.exe`).
- `.github/workflows/build-dotnet.yml`, `.github/workflows/build-classic.yml` — smoke assertions → `plugins/clavity`.

**Modified — skill renames (D3):** four skill dirs + frontmatter + two KEEP-IN-SYNC comments (see Phase 2).

**Modified — drift guard + gate:**
- `scripts/check-seed-artifacts-synced.sh` — enroll the responder byte-identical pair.
- `scripts/check-plugin-namespace.ps1` (**new**) + `scripts/tests/check-plugin-namespace.Tests.ps1` (**new**) — the namespace-grep gate.
- `lefthook.yml` — wire the new gate into pre-push.

**Modified — docs (surgical):** see Phase 5's KEEP/CHANGE table.

**Conditional (spike-gated) — within-flavor clean-break:** `installer/_shared/register-plugin.ps1` + `installer/_shared/register-invoke.iss` + callers + `scripts/tests/register-plugin.Tests.ps1` + hash re-sync (only if Spike B shows the old plugin lingers — Phase 6).

---

## Phase 0 — Spike A: de-risk `clavity:` namespace resolution under both agents

This is the load-bearing unverified assumption (plugin-name-is-the-namespace was verified for Claude Code via the `ecc` plugin, NOT for agy). Prove it with a throwaway staged plugin *before* doing the real rename, so the whole plan isn't built on a false premise.

### Task 0.1: Stage a throwaway `clavity` plugin and confirm the namespace under Claude Code and agy

**Files:**
- Create (scratch, outside the repo): a temp dir `%TEMP%\clavity-ns-spike\` containing `.claude-plugin/plugin.json` (`{"name":"clavity","version":"0.0.0","description":"ns spike"}`) and `skills/ns-probe/SKILL.md` (frontmatter `name: ns-probe`, a one-line body).

- [ ] **Step 1: Build the throwaway plugin**

Create `%TEMP%\clavity-ns-spike\.claude-plugin\plugin.json`:
```json
{ "name": "clavity", "version": "0.0.0", "description": "namespace spike (throwaway)" }
```
Create `%TEMP%\clavity-ns-spike\skills\ns-probe\SKILL.md`:
```markdown
---
name: ns-probe
description: Throwaway probe to confirm the clavity: namespace resolves.
---
This is a throwaway spike skill.
```

- [ ] **Step 2: Install it into Claude Code and agy from a scratch scoped marketplace**

Mirror the real install path (`register-plugin.ps1:131-134`): create a one-entry scoped `marketplace.json` next to the plugin pointing `source` at `./skills/..`-parent, then:
```
claude plugin marketplace add %TEMP%\clavity-ns-spike --scope user
claude plugin install clavity@<scope> --scope user
agy    plugin install %TEMP%\clavity-ns-spike
```
(Use whatever scope name the scratch marketplace declares; the point is only to observe the resolved skill namespace.)

- [ ] **Step 3: Observe the resolved skill namespace under BOTH agents**

Run `claude plugin list` (and inspect the skill listing) and the agy equivalent. **Expected:** the probe skill surfaces as `clavity:ns-probe` under Claude Code AND under agy. Record the exact observed strings.

- [ ] **Step 4: Decide/record**

- If both resolve `clavity:ns-probe` → assumption CONFIRMED, proceed to Phase 1.
- If agy namespaces differently (e.g. by the marketplace scope, or not at all) → **STOP and report to the operator**: the D1 approach needs revisiting before any real edit. Do not proceed on an unconfirmed namespace.

- [ ] **Step 5: Tear down the spike**

```
claude plugin uninstall clavity ; claude plugin marketplace remove <scope>
agy    plugin uninstall clavity
```
Delete `%TEMP%\clavity-ns-spike\`. This is a spike — no repo changes, nothing to commit.

---

## Phase 1 — Plugin identity → `clavity`

### Task 1.1: Add `pluginName` to the two driver members

**Files:**
- Modify: `build/members.json` (the `clavity-dotnet` member at lines 14-19; the `clavity-classic` member at lines 20-25)

- [ ] **Step 1 (Step 0 — state-verify):** Open `build/members.json`. Confirm the `clavity-dotnet` member is `{ "name": "clavity-dotnet", "source": "./clavity-dotnet/plugin", "description": "...", "marketplaceName": "clavity-dotnet" }` (lines 14-19) and the `clavity-classic` member similarly (lines 20-25). If the shape differs, STOP and report `STATE_MISMATCH`.

- [ ] **Step 2: Add `pluginName: "clavity"` to both driver members only**

For the `clavity-dotnet` member, add the field (keep `name`/`source`/`marketplaceName` exactly as-is):
```json
    {
      "name": "clavity-dotnet",
      "pluginName": "clavity",
      "source": "./clavity-dotnet/plugin",
      "description": "Pair Claude with a live agy peer via the clavity-ls Language-Server bridge (agy_look / agy_status / agy_ask).",
      "marketplaceName": "clavity-dotnet"
    },
```
For the `clavity-classic` member:
```json
    {
      "name": "clavity-classic",
      "pluginName": "clavity",
      "source": "./clavity-classic/plugin",
      "description": "clavity-classic: Claude drives a live agy peer via a psmux doorbell + the agentmemory bus.",
      "marketplaceName": "clavity-classic"
    },
```
Do **not** add `pluginName` to `agy-autotrain`, `commonmemory`, or `ghidrust` (they are not renamed; their plugin identity stays `= name`).

- [ ] **Step 3: Confirm `validate-members-manifest.ps1` still passes**

Run: `pwsh -File scripts/validate-members-manifest.ps1`
Expected: `OK: 5 members, 5 distinct marketplaceName values: ...` (the extra `pluginName` field is ignored by the presence/uniqueness checks — it keys on `marketplaceName`).

- [ ] **Step 4: Commit**

```bash
git add build/members.json
git commit -m "feat(sp0): add pluginName field to driver members (identity != member key)"
```

### Task 1.2: Emit plugin identity + source from `pluginName` in the scoped-manifest generator

**Files:**
- Modify: `scripts/generate-scoped-manifest.ps1:38-54`
- Test: `scripts/tests/generate-scoped-manifest.Tests.ps1` (**new** — no existing test covers this generator)

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/generate-scoped-manifest.Tests.ps1`:
```powershell
Describe 'generate-scoped-manifest pluginName' {
    BeforeAll {
        $script:gen  = Join-Path $PSScriptRoot '..' 'generate-scoped-manifest.ps1'
        $script:mem  = Join-Path $PSScriptRoot 'fixtures' 'members-pluginName.json'
        New-Item -ItemType Directory -Force -Path (Split-Path $script:mem) | Out-Null
        @'
{ "owner": { "name": "ckir", "url": "https://x" }, "members": [
  { "name": "clavity-dotnet", "pluginName": "clavity", "source": "./clavity-dotnet/plugin", "description": "d", "marketplaceName": "clavity-dotnet" },
  { "name": "ghidrust", "source": "./ghidrust/plugin", "description": "g", "marketplaceName": "clavity-ghidrust" }
] }
'@ | Set-Content -Path $script:mem -Encoding utf8
    }
    It 'emits pluginName as the plugin identity and source when present' {
        $out = Join-Path $env:TEMP "scoped-dotnet-$PID.json"
        & $script:gen -MemberName 'clavity-dotnet' -MembersJsonPath $script:mem -OutFile $out | Out-Null
        $m = Get-Content $out -Raw | ConvertFrom-Json
        $m.name              | Should -Be 'clavity-dotnet'      # OUTER = marketplaceName, unchanged
        $m.plugins[0].name   | Should -Be 'clavity'             # identity = pluginName
        $m.plugins[0].source | Should -Be './plugins/clavity'   # staging dir = pluginName
    }
    It 'falls back to name as identity when pluginName absent' {
        $out = Join-Path $env:TEMP "scoped-ghidrust-$PID.json"
        & $script:gen -MemberName 'ghidrust' -MembersJsonPath $script:mem -OutFile $out | Out-Null
        $m = Get-Content $out -Raw | ConvertFrom-Json
        $m.plugins[0].name   | Should -Be 'ghidrust'
        $m.plugins[0].source | Should -Be './plugins/ghidrust'
    }
}
```

- [ ] **Step 2: Run it — verify it fails**

Run: `pwsh -c "Invoke-Pester scripts/tests/generate-scoped-manifest.Tests.ps1 -Output Detailed"`
Expected: FAIL — the first test's `plugins[0].name` is `clavity-dotnet` (current code emits `$member.name`), not `clavity`.

- [ ] **Step 3: Implement — derive identity from `pluginName ?? name`**

In `scripts/generate-scoped-manifest.ps1`, replace the `plugins` block (lines 42-48) so the identity + source use `pluginName` when present:
```powershell
$pluginId = if ($member.PSObject.Properties['pluginName'] -and $member.pluginName) { $member.pluginName } else { $member.name }
$scoped = [ordered]@{
    '$schema' = 'https://code.claude.com/schemas/marketplace.json'
    name      = $member.marketplaceName
    owner     = $root.owner
    plugins   = @(
        [ordered]@{
            name        = $pluginId
            source      = "./plugins/$pluginId"
            description = $member.description
        }
    )
}
```
Also update the trailing `Write-Host` (line 54) to print `plugin=$pluginId source=./plugins/$pluginId`, and update the `.SYNOPSIS`/`.PARAMETER MemberName` comment (lines 9-11, 35-37) to note that `MemberName` still keys on `name`, but the emitted plugin identity + staging path now come from the optional `pluginName` (defaulting to `name`), and the installer's `[Files]` DestDir MUST match `./plugins/<pluginName>`.

- [ ] **Step 4: Run the test — verify it passes**

Run: `pwsh -c "Invoke-Pester scripts/tests/generate-scoped-manifest.Tests.ps1 -Output Detailed"`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/generate-scoped-manifest.ps1 scripts/tests/generate-scoped-manifest.Tests.ps1 scripts/tests/fixtures/members-pluginName.json
git commit -m "feat(sp0): scoped manifest emits plugin identity from pluginName"
```

### Task 1.3: Rename the plugin `name` in all four plugin.json files

**Files:**
- Modify: `clavity-dotnet/plugin/.claude-plugin/plugin.json:2`
- Modify: `clavity-dotnet/plugin/plugin.json:2`
- Modify: `clavity-classic/plugin/.claude-plugin/plugin.json:2`
- Modify: `clavity-classic/plugin/plugin.json:2`

- [ ] **Step 1 (state-verify):** Open all four. Confirm line 2 of each is `"name": "clavity-dotnet",` (dotnet pair) / `"name": "clavity-classic",` (classic pair). If any differs, STOP `STATE_MISMATCH`.

- [ ] **Step 2: Change `name` to `clavity` in all four** (leave `version`, `description`, and every other field untouched). Both the `.claude-plugin/plugin.json` and the top-level `plugin/plugin.json` twin per driver must change and stay in sync.

- [ ] **Step 3: Verify** — `git diff --stat` shows exactly four one-line changes; grep confirms no `"name": "clavity-dotnet"`/`"name": "clavity-classic"` remains in any `plugin.json`:
```
rg -n '"name":\s*"clavity-(dotnet|classic)"' clavity-dotnet/plugin clavity-classic/plugin
```
Expected: no matches.

- [ ] **Step 4: Commit**

```bash
git add clavity-dotnet/plugin/.claude-plugin/plugin.json clavity-dotnet/plugin/plugin.json clavity-classic/plugin/.claude-plugin/plugin.json clavity-classic/plugin/plugin.json
git commit -m "feat(sp0): plugin.json name -> clavity for both drivers"
```

### Task 1.4: Point the classic installer's registration calls at the `clavity` plugin identity

**Files:**
- Modify: `clavity-classic/installer/clavity-classic.iss:179` (`RegisterMemberPlugin` call)
- Modify: `clavity-classic/installer/clavity-classic.iss:307` (`DeregisterMemberPluginOnUninstall` call)

- [ ] **Step 1 (state-verify):** Confirm line 179 is `RegisterMemberPlugin(ExpandConstant('{app}'), 'clavity-classic', 'clavity-classic', ...)` and line 307 is `DeregisterMemberPluginOnUninstall('clavity-classic', 'clavity-classic');`. The signature is `(..., PluginName, MarketplaceName, ...)` — the FIRST `'clavity-classic'` is the plugin name, the SECOND is the marketplace scope. If the shape differs, STOP `STATE_MISMATCH`.

- [ ] **Step 2: Change ONLY the first arg (plugin name) to `'clavity'`, leaving the marketplace arg `'clavity-classic'` untouched:**
  - Line 179 → `RegisterMemberPlugin(ExpandConstant('{app}'), 'clavity', 'clavity-classic', ...)`
  - Line 307 → `DeregisterMemberPluginOnUninstall('clavity', 'clavity-classic');`

- [ ] **Step 3 (SHAPE-DIVERGENCE check):** The marketplace-name arg stays `'clavity-classic'` in BOTH calls. If making this compile would change the marketplace arg, STOP and report — the two args are a contract (`<plugin>@<marketplace>` → `clavity@clavity-classic`).

- [ ] **Step 4: Commit**

```bash
git add clavity-classic/installer/clavity-classic.iss
git commit -m "feat(sp0): classic installer registers plugin identity clavity"
```

### Task 1.5: Rename the dotnet plugin identity constant and rebuild `clavity-ls.exe`

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/Install/PluginInstaller.cs:9` (`PluginName` const)

- [ ] **Step 1 (state-verify):** Confirm lines 8-9 are `public const string MarketplaceName = "clavity-dotnet";` and `public const string PluginName = "clavity-dotnet";`. Confirm `CliRouter.cs:57,89` fall through to `PluginInstaller.PluginName` (no separate literal). **Also confirm `PluginInstaller.cs` does NOT construct any `plugins\<dir>` staging/source path or carry any other `clavity-dotnet` literal beyond these consts** (verified at plan time: the file has only these two consts — the staging/agy path is built entirely in the streamed `register-plugin.ps1` from `$PluginName`). Grep to reconfirm: `rg -n 'plugins|Path.Combine|Join|clavity-dotnet' clavity-dotnet/src/Clavity.Ls/Install/PluginInstaller.cs` should surface only lines 8-10. If a path is built from a separate literal, STOP `STATE_MISMATCH` — the staging-dir rename (Task 1.6) would then also need a C# change. If any of the above differs, STOP `STATE_MISMATCH`.

- [ ] **Step 2: Change `PluginName` only:** line 9 → `public const string PluginName = "clavity";`. Leave `MarketplaceName` (line 8) as `"clavity-dotnet"` and `LegacyMarketplaceName` (line 10) as `"clavity"`.

- [ ] **Step 3: Build + test dotnet**

Run: `just dotnet::test`
Expected: build succeeds and the dotnet test suite passes. If any test asserts the old `PluginName == "clavity-dotnet"`, that is the oracle telling you the identity changed — update the test assertion to `"clavity"` (it is a pinning test for the constant, not a behavior contract), never revert the constant.

- [ ] **Step 4: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/Install/PluginInstaller.cs
git commit -m "feat(sp0): dotnet PluginName const -> clavity (rebuild clavity-ls)"
```

### Task 1.6: Rename the on-disk plugin staging dir to `plugins\clavity`

Both the generated manifest `source` (`./plugins/clavity`, Task 1.2) and the agy install path (`register-plugin.ps1:150` `$pluginDir = plugins\$PluginName` → `plugins\clavity`) now derive the staging dir from the plugin identity. The installers' `[Files]` DestDir must match, or every install aborts (Failure mode J — see `generate-scoped-manifest.ps1:35-37`).

**Files:**
- Modify: `clavity-dotnet/installer/clavity-dotnet.iss:40` (`[Files]` DestDir)
- Modify: `clavity-classic/installer/clavity-classic.iss:50` (`[Files]` DestDir)

- [ ] **Step 1 (state-verify):** Confirm dotnet `.iss:40` is `Source: "..\plugin\*"; DestDir: "{app}\plugins\clavity-dotnet"; ...` and classic `.iss:50` is `Source: "..\plugin\*"; DestDir: "{app}\plugins\clavity-classic"; ...`. If either differs, STOP `STATE_MISMATCH`.

- [ ] **Step 2: Change both DestDir values to `{app}\plugins\clavity`** (leave `Source`, `Flags`, and everything else identical).

- [ ] **Step 3: Verify no OTHER `.iss` line depends on the old staging path.** Grep each installer:
```
rg -n 'plugins\\clavity-(dotnet|classic)' clavity-dotnet/installer clavity-classic/installer
```
Expected: no matches (the only staging-path references are the two DestDir lines just changed). If a `[Code]`/`[Run]` step references `plugins\clavity-dotnet`, STOP and report — it also needs updating.

- [ ] **Step 4: Commit**

```bash
git add clavity-dotnet/installer/clavity-dotnet.iss clavity-classic/installer/clavity-classic.iss
git commit -m "feat(sp0): stage plugin at plugins/clavity to match derived identity"
```

### Task 1.7: Update the CI install-smoke assertions to the new staging path + add a plugin-identity assertion

**Files:**
- Modify: `.github/workflows/build-dotnet.yml:117,118` (+ any plugin-dir path refs at 255-257, 275)
- Modify: `.github/workflows/build-classic.yml:120,121` (+ plugin-manifest path ref at 133)

- [ ] **Step 1 (state-verify):** Confirm `build-dotnet.yml:117` asserts `$installedManifest.plugins[0].source -ne './plugins/clavity-dotnet'` and `:118` `Test-Path "$app\plugins\clavity-dotnet"`; `:115` asserts `$installedManifest.name -ne 'clavity-dotnet'` (the OUTER marketplace name). Confirm the analogous classic lines. If any differs, STOP `STATE_MISMATCH`.

- [ ] **Step 2: Update the staging-path assertions (NOT the marketplace-name assertion):**
  - `build-dotnet.yml:117` → `-ne './plugins/clavity'`
  - `build-dotnet.yml:118` → `Test-Path "$app\plugins\clavity"`
  - Any dotnet path refs at 255-257, 275 that read `$app\plugins\clavity-dotnet\...` → `$app\plugins\clavity\...`
  - `build-classic.yml:120` → `-ne './plugins/clavity'`; `:121` → `Test-Path "$app\plugins\clavity"`; `:133` plugin-manifest path → `$app\plugins\clavity\.claude-plugin\plugin.json`
  - **Leave `:115` (`installedManifest.name -ne 'clavity-dotnet'`) unchanged** — that is the marketplace scope, which stays. Leave the C10 sibling-teardown checks (`plugins\agy-autotrain` etc.) unchanged.

- [ ] **Step 3: Add a plugin-identity assertion (currently missing).** After the `source` check in each smoke block, add:
```powershell
if ($installedManifest.plugins[0].name -ne 'clavity') { throw "expected plugin identity clavity, got $($installedManifest.plugins[0].name)" }
```

- [ ] **Step 4: Verify** — grep both workflows for a surviving staging-path reference to the old dir:
```
rg -n "plugins[\\\\/]clavity-(dotnet|classic)" .github/workflows/build-dotnet.yml .github/workflows/build-classic.yml
```
Expected: no matches. (References to `clavity-dotnet`/`clavity-classic` as the marketplace name, ARP display name, artifact filename, or `-MemberName` arg are correct and STAY.)

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/build-dotnet.yml .github/workflows/build-classic.yml
git commit -m "feat(sp0): CI smoke asserts plugins/clavity staging + clavity identity"
```

---

## Phase 2 — Skill renames (D3)

Each rename = rename the dir + change frontmatter `name:` + update every reference. The `ls-` prefix on the dotnet skills is KEPT (it denotes the Language-Server transport). `adversarial-panel-review` (both drivers) and `agy-first` (SP-A, not yet shipped) are UNCHANGED.

### Task 2.1: Rename dotnet `clavity-ls-driving` → `ls-driving`

**Files:**
- Rename: `clavity-dotnet/plugin/skills/clavity-ls-driving/` → `.../ls-driving/`
- Modify: `.../ls-driving/SKILL.md:2` (frontmatter `name:`)
- Modify: `.../ls-driving/SKILL.md:48` (KEEP-IN-SYNC comment referencing `clavity-driving`)

- [ ] **Step 1 (state-verify):** Confirm `clavity-dotnet/plugin/skills/clavity-ls-driving/SKILL.md:2` is `name: clavity-ls-driving`, and line 48 is a `<!-- KEEP IN SYNC WITH clavity-driving (clavity-classic/plugin/skills/clavity-driving/SKILL.md) -->` comment. If either differs, STOP `STATE_MISMATCH`.

- [ ] **Step 2: Rename the directory**
```bash
git mv clavity-dotnet/plugin/skills/clavity-ls-driving clavity-dotnet/plugin/skills/ls-driving
```

- [ ] **Step 3: Update frontmatter** — `SKILL.md:2` → `name: ls-driving`.

- [ ] **Step 4: Update the KEEP-IN-SYNC comment** — `SKILL.md:48` → reference the classic skill's NEW path/name: `<!-- KEEP IN SYNC WITH driving (clavity-classic/plugin/skills/driving/SKILL.md) -->`. (The classic side is renamed in Task 2.3; keep both comments consistent.)

- [ ] **Step 5: Commit**

```bash
git add clavity-dotnet/plugin/skills/ls-driving
git commit -m "feat(sp0): rename skill clavity-ls-driving -> ls-driving"
```

### Task 2.2: Rename dotnet `clavity-ls-pairing` → `ls-pairing`

**Files:**
- Rename: `clavity-dotnet/plugin/skills/clavity-ls-pairing/` → `.../ls-pairing/`
- Modify: `.../ls-pairing/SKILL.md:2`

- [ ] **Step 1 (state-verify):** Confirm `.../clavity-ls-pairing/SKILL.md:2` is `name: clavity-ls-pairing`. If not, STOP `STATE_MISMATCH`.

- [ ] **Step 2: Rename + frontmatter**
```bash
git mv clavity-dotnet/plugin/skills/clavity-ls-pairing clavity-dotnet/plugin/skills/ls-pairing
```
Then `SKILL.md:2` → `name: ls-pairing`.

- [ ] **Step 3: Commit**

```bash
git add clavity-dotnet/plugin/skills/ls-pairing
git commit -m "feat(sp0): rename skill clavity-ls-pairing -> ls-pairing"
```

### Task 2.3: Rename classic `clavity-driving` → `driving`

**Files:**
- Rename: `clavity-classic/plugin/skills/clavity-driving/` → `.../driving/`
- Modify: `.../driving/SKILL.md:2` (frontmatter `name:`)
- Modify: `.../driving/SKILL.md:107` (KEEP-IN-SYNC comment referencing `clavity-ls-driving`)

- [ ] **Step 1 (state-verify):** Confirm `.../clavity-driving/SKILL.md:2` is `name: clavity-driving` and line 107 is the `<!-- KEEP IN SYNC WITH clavity-ls-driving (clavity-dotnet/plugin/skills/clavity-ls-driving/SKILL.md) — ... -->` comment. If either differs, STOP `STATE_MISMATCH`.

- [ ] **Step 2: Rename the directory**
```bash
git mv clavity-classic/plugin/skills/clavity-driving clavity-classic/plugin/skills/driving
```

- [ ] **Step 3: Update frontmatter** — `SKILL.md:2` → `name: driving`.

- [ ] **Step 4: Update the KEEP-IN-SYNC comment** — `SKILL.md:107` → reference the dotnet skill's NEW path: `<!-- KEEP IN SYNC WITH ls-driving (clavity-dotnet/plugin/skills/ls-driving/SKILL.md) — task-assignment protocol + peer-decision-loop (transport idioms differ: classic uses \`clavity ask\`, dotnet uses \`agy_ask\`) -->`.

- [ ] **Step 5: Commit**

```bash
git add clavity-classic/plugin/skills/driving
git commit -m "feat(sp0): rename skill clavity-driving -> driving"
```

### Task 2.4: Rename the classic responder — PLUGIN COPY ONLY (Option A)

**Files:**
- Rename: `clavity-classic/plugin/skills/claudavity-responder/` → `.../responder/`
- Modify: `.../responder/SKILL.md:2` (frontmatter `id:`) and `:3` (frontmatter `name:`)
- **DO NOT TOUCH** `clavity-classic/agy_skills/claudavity-responder/` (the binary-embedded agy-side twin stays `claudavity-responder` — Option A).

- [ ] **Step 1 (state-verify):** Confirm `clavity-classic/plugin/skills/claudavity-responder/SKILL.md` has `id: claudavity-responder` (line 2) and `name: claudavity-responder` (line 3). Confirm `agy_skills/claudavity-responder/SKILL.md` still exists (it must NOT be renamed). If the plugin copy's shape differs, STOP `STATE_MISMATCH`.

- [ ] **Step 2: Rename the PLUGIN dir only**
```bash
git mv clavity-classic/plugin/skills/claudavity-responder clavity-classic/plugin/skills/responder
```

- [ ] **Step 3: Update the plugin copy's frontmatter** — `SKILL.md:2` → `id: responder`, `SKILL.md:3` → `name: responder`. (Verify `id` is not referenced elsewhere: `rg -n 'id:\s*claudavity-responder' --glob '!*/agy_skills/*'` should return nothing beyond this file.)

- [ ] **Step 4 (SHAPE-DIVERGENCE guard):** Confirm the two responder copies are now intentionally DIVERGENT in dir name but must stay byte-identical in body. Do NOT edit the body. The seed-sync enrollment in Phase 3 enforces byte-identity.

- [ ] **Step 5: Commit**

```bash
git add clavity-classic/plugin/skills/responder
git commit -m "feat(sp0): rename plugin responder skill claudavity-responder -> responder (Option A)"
```

---

## Phase 3 — Responder drift guard (Option A)

The two responder copies are byte-identical today with no automated check. Now that their dir names diverge, enroll the pair in the seed sync-check so a future edit to one that misses the other fails the gate.

### Task 3.1: Enroll the responder byte-identical pair in the seed sync-check

**Files:**
- Modify: `scripts/check-seed-artifacts-synced.sh`

- [ ] **Step 1 (state-verify + read the oracle):** Open `scripts/check-seed-artifacts-synced.sh`. Confirm lines 10-14 enumerate byte-identical-required relative paths (`skills/adversarial-panel-review/SKILL.md`, `hooks/agy-after-reminder.sh`, `knowledge/agy-assumptions.md`, `knowledge/agy-capabilities.md`) compared across the two driver plugin dirs, plus a `.hooks.PostToolUse` jq check (lines 25-27). Understand the existing loop's shape (same relative path echoed across both driver dirs). If the structure differs, STOP `STATE_MISMATCH`.

- [ ] **Step 2: Add a NAMED-PAIR byte-identity check for the responder.** This is a different shape from the existing loop (different basenames, same driver), so add an explicit `diff` of the two absolute paths:
```sh
# Responder skill: the Claude Code plugin copy (renamed to `responder`, Option A/SP-0) and the
# binary-embedded agy-side twin (kept as `claudavity-responder`) must stay byte-identical, though
# their directory names deliberately differ. No structural sync-check tied them before SP-0.
plugin_responder="clavity-classic/plugin/skills/responder/SKILL.md"
agy_responder="clavity-classic/agy_skills/claudavity-responder/SKILL.md"
if ! diff -q "$plugin_responder" "$agy_responder" >/dev/null 2>&1; then
  echo "SEED SYNC FAIL: responder copies diverged:"
  echo "  $plugin_responder"
  echo "  $agy_responder"
  fail=1
fi
```
Match the script's existing failure-accumulation convention (reuse its `fail`/exit-code variable; read the script to use the exact idiom — do not invent a new one).

- [ ] **Step 3: Run the gate — verify GREEN**

Run: `just seed-sync-check`
Expected: passes (the two responder copies are byte-identical). To prove the check WORKS, temporarily append a space to one copy, re-run (expect FAIL), then revert.

- [ ] **Step 4: Commit**

```bash
git add scripts/check-seed-artifacts-synced.sh
git commit -m "feat(sp0): enroll responder byte-identical pair in seed sync-check"
```

---

## Phase 4 — Namespace-grep gate

A mass mechanical rename needs a completeness net. This gate asserts all three of the spec's testing-posture conditions, without false-positiving on the intentionally-retained names.

### Task 4.1: Write the namespace-grep gate and its Pester test

**Files:**
- Create: `scripts/check-plugin-namespace.ps1`
- Create: `scripts/tests/check-plugin-namespace.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/check-plugin-namespace.Tests.ps1`:
```powershell
Describe 'check-plugin-namespace' {
    BeforeAll {
        $script:gate = Join-Path $PSScriptRoot '..' 'check-plugin-namespace.ps1'
        # Build a CLEAN renamed fixture (a temp $Root), so the unit tests do not depend on the live
        # repo's phase-in-progress state (the real-repo green check lives in Phase 7, after docs).
        function New-CleanFixture {
            $t = Join-Path $env:TEMP "ns-clean-$PID-$(Get-Random)"
            New-Item -ItemType Directory -Force -Path (Join-Path $t 'build') | Out-Null
            @'
{ "members": [
  { "name": "clavity-dotnet",  "pluginName": "clavity", "source": "./clavity-dotnet/plugin",  "marketplaceName": "clavity-dotnet" },
  { "name": "clavity-classic", "pluginName": "clavity", "source": "./clavity-classic/plugin", "marketplaceName": "clavity-classic" }
] }
'@ | Set-Content (Join-Path $t 'build/members.json')
            foreach ($d in 'clavity-dotnet','clavity-classic') {
                New-Item -ItemType Directory -Force -Path (Join-Path $t "$d/plugin/.claude-plugin") | Out-Null
                '{ "name": "clavity", "version": "0.0.0" }' | Set-Content (Join-Path $t "$d/plugin/.claude-plugin/plugin.json")
                '{ "name": "clavity", "version": "0.0.0" }' | Set-Content (Join-Path $t "$d/plugin/plugin.json")  # outer twin (both guarded by (d))
            }
            return $t
        }
    }
    It 'passes on a clean renamed fixture' {
        $t = New-CleanFixture
        $out = & pwsh -File $script:gate -Root $t 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "a fully-renamed tree must be clean: $out"
    }
    It 'flags a stray colon-namespace reference' {
        $t = New-CleanFixture
        New-Item -ItemType Directory -Force -Path (Join-Path $t 'docs') | Out-Null
        'see clavity-classic:driving for details' | Set-Content (Join-Path $t 'docs/x.md')
        & pwsh -File $script:gate -Root $t 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0 -Because "a namespaced old ref must fail (a)"
    }
    It 'flags a stale DOC skill-dir ref with NO plugin/ prefix' {
        $t = New-CleanFixture
        New-Item -ItemType Directory -Force -Path (Join-Path $t 'x') | Out-Null
        '- `skills/clavity-driving/` — old path' | Set-Content (Join-Path $t 'x/README.md')
        & pwsh -File $script:gate -Root $t 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0 -Because "a doc ref to an old skill dir must fail (b)"
    }
    It 'flags a driver member whose pluginName is not clavity' {
        $t = New-CleanFixture
        (Get-Content (Join-Path $t 'build/members.json') -Raw).Replace('"pluginName": "clavity", "source": "./clavity-dotnet/plugin"','"pluginName": "clavity-dotnet", "source": "./clavity-dotnet/plugin"') |
            Set-Content (Join-Path $t 'build/members.json')
        & pwsh -File $script:gate -Root $t 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0 -Because "members.json identity drift must fail (d)"
    }
    It 'does NOT flag the retained marketplace scope name' {
        $t = New-CleanFixture
        '{ "name": "clavity-dotnet", "owner": { "name": "x" }, "plugins": [ { "name": "clavity" } ] }' | Set-Content (Join-Path $t 'marketplace.install.json')
        & pwsh -File $script:gate -Root $t 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0 -Because "outer marketplace scope clavity-dotnet is retained"
    }
    It 'does NOT flag the retained agy-side claudavity-responder dir' {
        $t = New-CleanFixture
        New-Item -ItemType Directory -Force -Path (Join-Path $t 'clavity-classic/agy_skills/claudavity-responder') | Out-Null
        "---`nname: claudavity-responder`n---" | Set-Content (Join-Path $t 'clavity-classic/agy_skills/claudavity-responder/SKILL.md')
        & pwsh -File $script:gate -Root $t 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0 -Because "the agy-side twin is intentionally retained (Option A)"
    }
}
```

- [ ] **Step 2: Run it — verify it fails**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-plugin-namespace.Tests.ps1 -Output Detailed"`
Expected: FAIL (the gate script does not exist yet).

- [ ] **Step 3: Implement the gate**

Create `scripts/check-plugin-namespace.ps1` asserting all three conditions, with the two exemptions:
```powershell
<#
.SYNOPSIS
SP-0 namespace-rename completeness gate. Fails if the mass rename left any stray old reference.
Asserts (a) no `clavity-dotnet:<skill>` / `clavity-classic:<skill>` NAMESPACE refs; (b) no old
skill-DIR names (clavity-ls-driving, clavity-ls-pairing, clavity-driving) referenced anywhere
(on disk OR in a doc), matched WITHOUT a `plugin/` prefix; (c) no old plugin `name`
(clavity-dotnet/clavity-classic) in a plugin.json or a marketplace plugins[].name; (d) each driver
member in build/members.json carries pluginName='clavity' AND its plugin.json `name` agrees.
Must NOT flag: the retained marketplace SCOPE name (outer marketplace.install.json `name`, member
marketplaceName, scope paths); folder paths (clavity-dotnet/ , clavity-classic/); or the retained
agy-side `agy_skills/claudavity-responder` twin (Option A, deliberately excluded from (b)).
#>
param([string]$Root = "$PSScriptRoot/..")
$ErrorActionPreference = 'Stop'
# ripgrep exits 1 when it finds NO matches (the CLEAN case). Under PowerShell 7.4+ with EAP='Stop',
# $PSNativeCommandUseErrorActionPreference defaults to $true, turning that non-zero native exit into a
# THROW — which would crash this gate on a clean repo. We test rg's OUTPUT (presence of hits), never its
# exit code, so disable native-command error propagation. (rg is a repo-wide tooling assumption per
# cli-tooling.md; if it is somehow absent, the Get-Command guard below fails loudly instead of cryptically.)
$PSNativeCommandUseErrorActionPreference = $false
if (-not (Get-Command rg -ErrorAction SilentlyContinue)) { Write-Error "check-plugin-namespace requires ripgrep (rg) on PATH"; exit 2 }
$violations = @()

# (a) namespace-qualified old refs anywhere (the `:` is what makes it a namespace, not a folder/scope)
$nsHits = rg -n --glob '!**/docs/superpowers/**' --glob '!**/docs/session-notes/**' --glob '!**/docs/archive/**' `
    'clavity-(dotnet|classic):[a-z]' $Root 2>$null
if ($nsHits) { $violations += "(a) stray namespace ref(s):`n$nsHits" }

# (b) old skill-DIR names surviving anywhere (on disk OR in a doc/README reference). Match a bare
#     `skills/<oldname>` segment WITHOUT requiring a `plugin/` prefix, so a stale doc ref like
#     `skills/clavity-driving/` is caught too. `claudavity-responder` is DELIBERATELY NOT listed: its
#     plugin copy is renamed to `responder`, but the agy-side twin legitimately KEEPS the name
#     (Option A), and `agy_skills/claudavity-responder` ends in `skills/claudavity-responder`, so
#     listing it here would over-flag the retained twin. Plugin-responder completeness is covered by
#     the Phase 2 dir rename + the Phase 3 seed-sync + the Phase 5 doc pass, not by this gate.
$dirHits = rg -n 'skills[\\/](clavity-ls-driving|clavity-ls-pairing|clavity-driving)\b' $Root 2>$null
if ($dirHits) { $violations += "(b) old skill-dir ref(s):`n$dirHits" }

# (c) old plugin identity in a plugin.json `name` or a marketplace plugins[].name.
#     Scope to plugin.json / marketplace.install.json; match ONLY a plugins-array/identity `name`, never
#     the OUTER marketplace `name` (retained scope). NOTE: marketplace.install.json is GITIGNORED/generated,
#     so on committed state this branch typically scans only committed plugin.json files — the generated
#     manifest's plugins[].name is covered by CI install-smoke (Task 1.7) and, at its source, by check (d).
foreach ($f in (rg --files -g '**/plugin.json' -g '**/marketplace.install.json' $Root 2>$null)) {
    $j = Get-Content $f -Raw | ConvertFrom-Json
    if ($j.PSObject.Properties['plugins']) {
        foreach ($p in $j.plugins) { if ($p.name -in @('clavity-dotnet','clavity-classic')) { $violations += "(c) old plugin identity in ${f}: plugins[].name=$($p.name)" } }
    } elseif ($j.PSObject.Properties['name'] -and -not $j.PSObject.Properties['owner']) {
        # a bare plugin.json (not a marketplace manifest, which has owner/plugins): its `name` IS the identity
        if ($j.name -in @('clavity-dotnet','clavity-classic')) { $violations += "(c) old plugin identity in ${f}: name=$($j.name)" }
    }
}

# (d) members.json is the COMMITTED source of the emitted plugin identity (marketplace.install.json is
#     generated from it). Assert each driver member (keyed by its retained marketplaceName) carries
#     pluginName='clavity', and that the corresponding plugin.json `name` agrees — closing the drift hole
#     (c) cannot see on committed state.
$membersPath = Join-Path $Root 'build/members.json'
if (Test-Path $membersPath) {
    $members = (Get-Content $membersPath -Raw | ConvertFrom-Json).members
    # Cross-check BOTH plugin.json twins per driver (inner .claude-plugin/ AND top-level) — Task 1.3
    # renames all four; (d) must guard all four against future identity drift, not just the inner two.
    $driverMap = @{
        'clavity-dotnet'  = @('clavity-dotnet/plugin/.claude-plugin/plugin.json',  'clavity-dotnet/plugin/plugin.json')
        'clavity-classic' = @('clavity-classic/plugin/.claude-plugin/plugin.json', 'clavity-classic/plugin/plugin.json')
    }
    foreach ($mkt in $driverMap.Keys) {
        $m = $members | Where-Object { $_.marketplaceName -eq $mkt }
        if (-not $m) { $violations += "(d) members.json missing driver member with marketplaceName=$mkt"; continue }
        $pn = if ($m.PSObject.Properties['pluginName']) { $m.pluginName } else { $m.name }
        if ($pn -ne 'clavity') { $violations += "(d) members.json member $mkt has pluginName '$pn', expected 'clavity'" }
        foreach ($rel in $driverMap[$mkt]) {
            $pj = Join-Path $Root $rel
            if (Test-Path $pj) {
                $pjName = (Get-Content $pj -Raw | ConvertFrom-Json).name
                if ($pjName -ne $pn) { $violations += "(d) identity drift: $mkt members pluginName='$pn' but $rel name='$pjName'" }
            }
        }
    }
}

if ($violations.Count) { $violations | ForEach-Object { Write-Host $_ }; Write-Error "namespace-rename incomplete ($($violations.Count) class(es))"; exit 1 }
Write-Host "OK: plugin namespace rename complete (no stray clavity-dotnet/clavity-classic identity refs)."
```
Note: this reads `plugin.json`/`marketplace.install.json` structurally (via `ConvertFrom-Json`) for conditions (c)/(d) so it can distinguish the outer marketplace `name` (retained scope) from `plugins[].name` (identity), and cross-check `members.json` `pluginName` against the plugin.json `name`. Conditions (a)/(b) are string patterns scoped to exclude the historical `docs/superpowers`, `docs/session-notes`, and `docs/archive` trees (dated artifacts, out of scope per the docs recon).

- [ ] **Step 4: Run the test — verify it passes** (fixture-based; independent of live-repo phase state)

Run: `pwsh -c "Invoke-Pester scripts/tests/check-plugin-namespace.Tests.ps1 -Output Detailed"`
Expected: PASS (all seven cases — clean-fixture pass; three negative cases (a)/(b)/(d); two exemption cases (retained scope, retained agy-side twin)). These use temp `-Root` fixtures, so they pass regardless of where the live repo is in the phase sequence.

- [ ] **Step 5: Run the gate against the real repo — EXPECT IT TO STILL FLAG DOC REFS**

Run: `pwsh -File scripts/check-plugin-namespace.ps1`
**Expected at this point: NON-zero** — condition (b) now catches stale `skills/<oldname>` references in docs/READMEs, which Phase 5 has not yet cleaned. That is correct and expected. Confirm the ONLY violations reported are (b) doc references slated for Phase 5 (not any (c)/(d) identity drift — those must already be clean from Phase 1). If a (c)/(d) violation appears, that is a real Phase 1 miss — fix it now. The gate goes fully green in Phase 7 Step 1, after the Phase 5 doc pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/check-plugin-namespace.ps1 scripts/tests/check-plugin-namespace.Tests.ps1
git commit -m "feat(sp0): namespace-rename completeness gate + Pester"
```

### Task 4.2: Author the pre-push wiring (activated in Phase 7)

**Files:**
- Modify: `lefthook.yml`

**Sequencing note:** the gate's condition (b) intentionally fails on stale doc refs that Phase 5 has not yet cleaned. Do NOT rely on the wired hook passing until Phase 7. You MAY commit the `lefthook.yml` change here (commits do not push — the owner pushes at the end), but the gate is not expected to pass a real `lefthook run pre-push` until after Phase 5. Phase 7 Step 1 verifies it green.

- [ ] **Step 1 (state-verify):** Open `lefthook.yml`. Find the pre-push section and confirm how existing gates are invoked (e.g. `run: just seed-sync-check`). Match that idiom exactly. If the file's structure differs from the recon (a `pre-push` group of `run:` commands), STOP `STATE_MISMATCH`.

- [ ] **Step 2: Add the gate** as a new pre-push command, mirroring the existing entries:
```yaml
    check-plugin-namespace:
      run: pwsh -File scripts/check-plugin-namespace.ps1
```
(Place it beside the other script gates; use the exact key/indentation style the file already uses.)

- [ ] **Step 3: Verify the hook INVOKES the gate** — `lefthook run pre-push` (or the repo's documented way to dry-run the hook) executes the new `check-plugin-namespace` entry. It is EXPECTED to fail here on stale (b) doc refs (Phase 5 not yet done); the point of this step is only to confirm the wiring runs the gate, not that it passes. Full green is verified in Phase 7 Step 1.

- [ ] **Step 4: Commit**

```bash
git add lefthook.yml
git commit -m "feat(sp0): wire namespace gate into pre-push (green after Phase 5)"
```

---

## Phase 5 — Docs re-namespace (surgical)

Under Option A the agy-side responder stays `claudavity-responder`, so most `claudavity-responder` doc mentions (which describe the agy-side skill) are STILL CORRECT and must NOT change. Only references to the renamed PLUGIN skill dirs change.

### Task 5.1: Update doc references to the renamed PLUGIN skills

**Files (CHANGE — renamed plugin skill dirs):**
- `clavity-dotnet/plugin/README.md:16,17` — `skills/clavity-ls-driving/` → `skills/ls-driving/`; `skills/clavity-ls-pairing/` → `skills/ls-pairing/`
- `clavity-dotnet/CONTRIBUTING.md:52` — `clavity-ls-pairing` → `ls-pairing`
- `clavity-classic/plugin/README.md:13` — `skills/clavity-driving/` → `skills/driving/`
- `clavity-classic/plugin/README.md:12` — `skills/claudavity-responder/` → `skills/responder/` (this line describes the PLUGIN's own skills-dir listing)
- `agy-autotrain/README.md:9,10` — `clavity-driving` → `driving`; `clavity-ls-driving` → `ls-driving`
- `clavity-dotnet/ROADMAP.md:126` — `clavity-ls-driving` → `ls-driving` (not in the audited set, but a live doc; update for accuracy)

**Files (KEEP — agy-side responder refs; DO NOT CHANGE):**
- `CONTRIBUTING.md:74,208,224` — all reference `agy_skills/claudavity-responder/SKILL.md` / "the claudavity-responder skill" agy runs → **agy-side, stays `claudavity-responder`.**
- `clavity-classic/CONTRIBUTING.md:48,97,112` — same agy-side refs → **stay.**
- `clavity-classic/installer/clavity-classic-MANUAL-SETUP.md:37` — "invoke the claudavity-responder skill" (agy invokes it) → **stays.**
- `clavity-classic/plugin/README.md:64,66,109,118,119` — **classify each individually:** a `Copy-Item`/path example pointing at `agy_skills/claudavity-responder` STAYS; a reference to the plugin's own `skills/` listing CHANGES to `responder`. Read each line in context before editing.

- [ ] **Step 1 (state-verify):** Open each CHANGE file at the cited line and confirm it holds the old string in the described role (plugin skills-dir reference). Open each KEEP file at the cited line and confirm it is an agy-side reference. If any line's role differs from this table, STOP and report the mismatch rather than editing.

- [ ] **Step 2: Apply the CHANGE edits** exactly as tabled. For `clavity-classic/plugin/README.md:64,66,109,118,119`, edit ONLY the lines that reference the plugin's own `skills/` dir; leave `agy_skills/` example paths untouched.

- [ ] **Step 3: Verify the KEEP refs survived** — the agy-side `claudavity-responder` mentions must still be present:
```
rg -n 'claudavity-responder' CONTRIBUTING.md clavity-classic/CONTRIBUTING.md clavity-classic/installer/clavity-classic-MANUAL-SETUP.md
```
Expected: the agy-side references are still there (they describe the retained agy-side skill).

- [ ] **Step 4: Run the doc gates**

Run: `just check-user-facing-docs` then `just check-member-docs` then `just check-links`
Expected: `check-user-facing-docs`/`check-member-docs` pass; `check-links` reports only the 2 known GitHub-relative errors (baseline, per the justfile comment) and nothing new.

- [ ] **Step 5: Run the namespace gate again** — `pwsh -File scripts/check-plugin-namespace.ps1` → `OK` (confirms the doc pass didn't leave a stray plugin-namespace ref, and didn't over-flag the retained agy-side refs).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "docs(sp0): re-namespace renamed plugin skills (agy-side responder refs kept)"
```

---

## Phase 6 — Build, Spike B, conditional within-flavor clean-break, full smoke

### Task 6.1: Full build + all unit gates green

- [ ] **Step 1: Build everything**

Run: `just build`
Expected: dotnet (`clavity-ls.exe` with the new `PluginName`), classic (Rust), and ghidrust all build clean.

- [ ] **Step 2: Run every unit gate**

Run each and confirm green:
```
just test-scripts        # Pester: generate-scoped-manifest, check-plugin-namespace, (roster/register unchanged)
just seed-sync-check     # responder pair + existing enrollments byte-identical
just check-register-hash # register-plugin.ps1 hash NOT drifted (unchanged unless Task 6.3 fires)
just check-installer-ascii
just test                # dotnet + classic + ghidrust suites
```
Expected: all pass. If `just test` surfaces a test pinning the old plugin identity, update that assertion to `clavity` (oracle = the identity changed), never revert the rename.

### Task 6.2: Spike B — upgrade cascade + both-flavor collision (real installers)

- [ ] **Step 1: Build the two installers** locally, exactly mirroring the CI installer-build steps (the canonical recipe — cite these lines if a step is unclear):
  - **dotnet** (`.github/workflows/build-dotnet.yml`): (1) build/publish the dotnet binary so `clavity-ls.exe` is staged where the `.iss` expects it; (2) from the `clavity-dotnet/` dir, `pwsh -File ../scripts/generate-scoped-manifest.ps1 -MemberName clavity-dotnet -OutFile installer/marketplace.install.json` (workflow line 72); (3) compile: `& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" installer/clavity-dotnet.iss` (workflow line 86). Produces `clavity-dotnet-setup-<ver>.exe`.
  - **classic** (`.github/workflows/build-classic.yml`): (1) `pwsh -NoProfile -File scripts/build-classic-release.ps1` (workflow line 62) — stages the runtime files; (2) generate the scoped manifest for `clavity-classic`; (3) `& <ISCC.exe> installer/clavity-classic.iss` (workflow line 85). Produces `clavity-classic-setup-<ver>.exe`.
  - Confirm each produces a `*-setup-*.exe`. (ISCC lives at `${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe`; `choco install innosetup` if absent — build-classic.yml:74.)

- [ ] **Step 2: Upgrade-cascade test.** On a clean box/VM: install the CURRENT released driver (old plugin identity `clavity-dotnet`), then install the NEW SP-0 build over it. After install, inspect `claude plugin list`:
  - **Expected/desired:** only `clavity@clavity-dotnet` is registered; the old `clavity-dotnet@clavity-dotnet` is gone.
  - **If the old `clavity-dotnet` plugin LINGERS alongside `clavity`** → the existing `marketplace remove` (register-plugin.ps1:130) does NOT cascade to its plugins → **Task 6.3 (within-flavor clean-break) is REQUIRED.** Record the result.

- [ ] **Step 3: Namespace-under-both-agents (real install) + skill-cache clear.** Skills are cached (see `clavity-dotnet/CONTRIBUTING.md:52` and `agy-assumptions.md` on skill caching): a dir+frontmatter rename may keep serving the OLD name from a stale cache until the plugin is reinstalled / the cache is cleared. Do the real install as a clean reinstall (the installer's marketplace remove+re-add + `plugin uninstall`/`install` cycle already forces this), then confirm the renamed skills surface as `clavity:ls-driving` / `clavity:driving` / `clavity:responder` etc. under BOTH Claude Code and agy (the definitive version of Spike A). If a stale old-named skill still resolves, clear the agent's skill cache and re-check before concluding the rename "doesn't work." Record the exact reinstall/cache-clear step needed so it can go into the release notes for end users (the clean-break migration must tell users to reinstall, not just upgrade in place).

- [ ] **Step 4: Record the spike results** in the plan's execution notes / the memory index (upgrade-cascade outcome decides Task 6.3; namespace outcome is the definition-of-done check).

### Task 6.3: (CONDITIONAL — only if Spike B Step 2 showed the old plugin lingers) Within-flavor clean-break

If and only if the old same-flavor plugin lingers after upgrade, add an explicit legacy-plugin uninstall, mirroring the existing `LegacyMarketplaceName` cleanup.

**Files:**
- Modify: `installer/_shared/register-plugin.ps1` (add `[string]$LegacyPluginName = ''` param to `Install-ClaudePlugin` + `Invoke-Registration`; uninstall it when non-empty)
- Modify: `installer/_shared/register-invoke.iss` (thread `LegacyPluginName` through `RegisterMemberPlugin`/`ExecRegisterScript`)
- Modify: `clavity-classic/installer/clavity-classic.iss:179` (pass `'clavity-classic'` as the legacy plugin name)
- Modify: `clavity-dotnet/src/Clavity.Ls/Install/PluginInstaller.cs` (pass `LegacyPluginName = "clavity-dotnet"` into the streamed registration; add a `LegacyPluginName` const)
- Modify: `scripts/tests/register-plugin.Tests.ps1` (golden-vector: assert the extra `plugin uninstall <legacy>` when `LegacyPluginName` is set; assert NO extra uninstall when empty)

- [ ] **Step 1: Write the failing golden-vector test** — extend `register-plugin.Tests.ps1` to call `Install-ClaudePlugin -PluginName 'clavity' -MarketplaceName 'clavity-classic' -LegacyPluginName 'clavity-classic' -AppDir ...` and assert the command vector now includes `plugin uninstall clavity-classic` (before `plugin install clavity@clavity-classic`), AND a second case with no `-LegacyPluginName` asserting no such extra uninstall. Run: `just test-scripts` → expect FAIL.

- [ ] **Step 2: Implement** — add the param + a guarded `if ($LegacyPluginName) { [void](Invoke-AgentCli 'claude' @('plugin','uninstall',$LegacyPluginName)) }` **placed alongside the existing `$PluginName` pre-clean at line 133 (i.e. AFTER the marketplace re-add at line 131), NOT after the line-129/130 marketplace removals.** Placing it between lines 130-131 would run `plugin uninstall` while the plugin's marketplace is deregistered, risking a silent (`[void]`-swallowed) fail that orphans the old plugin. Line 133 is the proven context (it is exactly where the existing new-name pre-clean runs, with the marketplace present). Thread the param through `register-invoke.iss` and the two callers. Do NOT change the existing `$PluginName`/`$MarketplaceName` semantics.

- [ ] **Step 3: Re-sync the pinned hash** (register-plugin.ps1 changed): `just sync-register-hash`, then `just check-register-hash` → passes.

- [ ] **Step 4: Run tests** — `just test-scripts` → PASS; `just dotnet::test` → PASS (C# change builds).

- [ ] **Step 5: Re-run Spike B Step 2** — confirm the old plugin is now removed on upgrade.

- [ ] **Step 6: Commit**

```bash
git add installer/_shared/register-plugin.ps1 installer/_shared/register-invoke.iss clavity-classic/installer/clavity-classic.iss clavity-dotnet/src/Clavity.Ls/Install/PluginInstaller.cs scripts/tests/register-plugin.Tests.ps1 installer/_shared/register-plugin-hash.iss
git commit -m "feat(sp0): within-flavor clean-break removes old plugin identity on upgrade"
```

### Task 6.4: Cross-flavor stays refusal (Option R) — verification only, no code change

- [ ] **Step 1: Confirm no cross-flavor removal was introduced.** Grep the installers for any new active uninstall-the-other-flavor logic:
```
rg -n 'uninstall|remove' clavity-dotnet/installer/clavity-dotnet.iss clavity-classic/installer/clavity-classic.iss
```
Expected: only the existing within-flavor deregistration + the existing refusal messages — NO logic that uninstalls the OTHER flavor. Option R = the pre-existing refusal in `InitializeSetup` is unchanged.

- [ ] **Step 2: Spot-check the refusal still fires** — on a box with the other flavor present, the new installer aborts in `InitializeSetup` with the existing message (no files laid down). This is a behavioral confirmation, not a new test.

---

## Phase 7 — Definition of done

- [ ] **Step 1: Every gate green** — re-run the full set: `just build`, `just test`, `just test-scripts`, `just seed-sync-check`, `just check-register-hash`, `just check-installer-ascii`, `just check-user-facing-docs`, `just check-member-docs`, `just check-links` (only the 2 known baseline errors), `pwsh -File scripts/check-plugin-namespace.ps1`.

- [ ] **Step 2: The definition-of-done install smoke** — a real install of each flavor registers plugin `clavity` (marketplace `clavity-<flavor>`), stages it at `plugins\clavity`, and every renamed skill resolves as `clavity:<skill>` under BOTH Claude Code and agy (Spike B Step 3 result).

- [ ] **Step 3: Update the memory index** — record every commit SHA, the Spike A/B results, and whether Task 6.3 fired. Set the resume point to "SP-0 complete → SP-A rebases on the `clavity:` baseline."

- [ ] **Step 4: AGY-CAPSTONE** — before declaring SP-0 complete, run a convergent agy review of the COMMITTED SP-0 range (the executable diff, not this plan), rounds-until-green, verifying each finding by measurement. Only the owner declares SP-0 done and merges (one combined release ships the whole epic).

---

## Notes for the executor

- **Do NOT rename `build/members.json` `name`** — it is the unique member key; the rename rides the new `pluginName` field. This keeps `Assert-RosterMatchesMembers`, `validate-members-manifest.ps1`, and `release-lib.ps1` untouched.
- **The `clavity` name sits next to a pre-existing `LegacyMarketplaceName = 'clavity'` cleanup** (`register-plugin.ps1:37,129`; `PluginInstaller.cs:10`) that runs `marketplace remove clavity` on every install. Our new *marketplace* scopes stay `clavity-dotnet`/`clavity-classic`, so that line removes a *marketplace* named `clavity` (which we do not create) — it does NOT touch our new *plugin* named `clavity`. Spike B Step 2 confirms this coexistence empirically; if the spike ever shows the legacy line removing our plugin, STOP and report.
- **Marketplace scope names, ARP display names, install-dir names, artifact filenames, folder paths, and CI `-MemberName` args all stay `clavity-dotnet`/`clavity-classic`.** Only the plugin *identity*, the staging dir, and the renamed skill dirs change.
- **Every commit lands on `main` (or a holding branch) but the owner owns every push.** Do not push.

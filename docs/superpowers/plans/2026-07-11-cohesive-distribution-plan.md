# Cohesive Distribution Model — Implementation Plan

> For agentic workers: follow the `superpowers:executing-plans` skill's checkpoint discipline while
> executing this plan — one task at a time, verify before moving on, do not skip ahead.

**Goal:** Replace the incoherent bundled-installer distribution (dotnet's installer aggregates
every other member's plugin; ghidrust's plugin lives only on a remote marketplace; agy-autotrain
and commonmemory have no installer at all) with **five standalone, per-member installers**, each
self-registering its own plugin from a **local, uniquely-named, scoped marketplace manifest**, with
**no** live-remote marketplace channel and **no** competing version authority. One `clavity-v<N>`
GitHub release remains the user-facing catalog (the "palette"), but it is a **menu**, not a bundle.

**Architecture:** Every member (clavity-dotnet, clavity-classic, ghidrust, agy-autotrain,
commonmemory) ships one Inno Setup installer. Each installer embeds its own plugin folder, stages
it at `{app}\plugins\<name>`, writes a scoped 1-entry `{app}\.claude-plugin\marketplace.json` under
a **unique** top-level `name` (`clavity-dotnet`, `clavity-classic`, `clavity-ghidrust`,
`clavity-agy-autotrain`, `clavity-commonmemory`), and registers that plugin against every detected
agent (Claude Code, agy) using the verbatim CLI argument vectors from the oracle
(`clavity-dotnet/src/Clavity.Ls/Install/PluginInstaller.cs`). The three binary members
(clavity-dotnet, clavity-classic, ghidrust) additionally embed and unpack their binary to `{app}`
and add it to PATH; dotnet and classic remain mutually exclusive. The repo-root
`.claude-plugin/marketplace.json` (currently a **publicly addable** 5-plugin manifest — the exact
version-skew door this design closes) is relocated to a non-addable build-only data file,
`build/members.json`, from which every installer's scoped manifest is **generated** at build time.
A new shared Inno `[Code]` include holds the registration/idempotency/rollback/deregistration logic
once, so five installers don't fork five copies of the claude/agy CLI contract.

**Tech Stack:** Inno Setup 6 (`[Code]` Pascal Script) for all five installers; a small shared
`.iss` include (Component O1); PowerShell 7 (`pwsh`) build-time scripts for the scoped-manifest
generator (Component O3) and the CI namespace-collision guard; GitHub Actions (`workflow_call` +
`workflow_dispatch`) for per-member reusable builds and the umbrella release; C# (.NET 10) for the
two files inside `clavity-dotnet` that change (`PluginInstaller.cs`, `CliRouter.cs`).

---

## State-verification summary (Step 0 — completed before authoring tasks)

Read in full and confirmed against the design spec's description, with two corrections folded
into the tasks below (found while reading, not contradicting the spec — the spec's C6/Acceptance#10
requirement exposes a **pre-existing bug** in the shipped code that this plan must fix, not a
mismatch in the spec itself):

- `clavity-dotnet/src/Clavity.Ls/Install/PluginInstaller.cs` (48 lines) — oracle confirmed verbatim:
  `MarketplaceName = "clavity"` (line 10), `Install` (17–37), `Uninstall` (39–45, **no**
  `marketplace remove` call today — C6 adds this). Also read `CliRouter.cs` (185 lines) and
  `AgentDetection.cs`/`AgentResult.cs` for the full call chain (not named in the brief, but needed
  because the per-agent OR-semantics fix (C1) and the rollback wiring live in `CliRouter.cs`, not
  `PluginInstaller.cs`). **Found:** `CliRouter.cs:62` (`ok &= r.Ok`) implements AND-semantics
  ("every detected agent must succeed") which contradicts C1's "fail only if **every** detected
  agent fails" (OR-semantics) — Task 2.2 fixes this.
- `clavity-dotnet/installer/clavity-dotnet.iss` (335 lines) — every cited line range confirmed
  exactly: `[Files]` siblings 45–46/49, `[Tasks]` 54–55, `InstallAddon` 178–189, gated calls
  227–235, uninstall dereg 316–319, `New-Item -Path` (no `-LiteralPath`) at line 215,
  `Copy-Item -LiteralPath` source at 216. **Additionally found:** `CurUninstallStepChanged`
  (325–330) calls `BackupHeaderFile` on **all three** of `seed.md`, `growth.md`, and the legacy
  flat file — this **renames agy-autotrain's `growth.md` out from under it** on every driver
  uninstall (even a bare uninstall that keeps data), which is exactly failure-mode H that
  Acceptance #10 forbids. Task 2.3 removes the `growth.md` line from this driver's uninstall path.
- `clavity-classic/installer/clavity-classic.iss` (325 lines) — confirmed: no plugin registration
  anywhere in the file; `StemOnPath` (102–154), `DotnetArpPresent` (157–175), `BackupHeaderFile`
  (288–298, referenced as 288–298 — same off-by-nothing match), `New-Item -Path` gap at line 220,
  registry marker `Software\clavity\classic` (60–61). **Same `growth.md` bug** at line 312 as
  dotnet's — Task 2.4 fixes it identically.
- `ghidrust/installer/ghidrust.iss` (106 lines) — see "ghidrust actuals" below (no line anchors were
  given for this file; reported fresh).
- `.github/workflows/build-dotnet.yml` (177 lines) — flat-manifest generation confirmed at 65–75;
  the sibling-bundling smoke assertions are at lines **108–116** (brief said "~109–116" — a
  1-line offset, not a mismatch).
- `.github/workflows/build-classic.yml`, `build-ghidrust.yml`, `umbrella-release.yml` — read in
  full (no anchors given); see "actuals" below. **Found:** `build-ghidrust.yml` has **no**
  install/uninstall smoke test at all today (Task 4.3 adds one — it doesn't exist to "flip").
- `.claude-plugin/marketplace.json` — confirmed the exact 5-plugin repo-root manifest described.
- No existing `#include` in any `.iss` in the repo, and no repo-root `installer/` folder — O1's
  shared include is new infrastructure, not a refactor of something that already exists.
- Additional (not in the brief, needed for completeness): `agy-autotrain/.claude-plugin/plugin.json`
  (name `agy-autotrain`, version `0.1.4`), `commonmemory/.claude-plugin/plugin.json` (version
  `0.1.0`), `ghidrust/plugin/.claude-plugin/plugin.json` (version `0.1.0`) — read to confirm the
  plugin folders already exist and are ready to stage (only `ghidrust`'s installer doesn't stage
  its own plugin yet; `agy-autotrain`/`commonmemory` have no installer at all). `agy-curate`'s
  loud-guide warning (C7) **already exists** verbatim (`agy-autotrain/skills/agy-curate/SKILL.md:91-92`)
  — no code task needed for C7, it's a pre-existing behavior this design simply doesn't disturb.
  `clavity-classic/src/golden_header.rs` confirms both `seed.md` and `growth.md` carry a
  `<file>.sha256` sidecar (`with_suffix(path, ".sha256")`) — so the driver-uninstall backup logic
  (Task 2.3/2.4) and agy-autotrain's own uninstall (Task 3.1) must handle the sidecar too, which
  the current shipped `BackupHeaderFile` calls do **not** (they only ever touch the `.md` files).

**ghidrust.iss actuals** (no anchors given — reported fresh): 106 lines. `AppVersion "1.0.0"`,
`DefaultDirName={localappdata}\Programs\ghidrust`, no `SetupMutex`, `[Files]` stages only
`..\publish\ghidrust.exe` (no plugin staging — the header comment says the plugin is "marketplace
on main"), a `TInputDirWizardPage` for the Ghidra install dir, `CurStepChanged`/
`CurUninstallStepChanged` handle only the `GHIDRA_INSTALL_DIR` env var and PATH.

**umbrella-release.yml actuals** (no anchors given): `release-clavity` workflow, triggers on
`clavity-v*` tag push or dispatch; 5 jobs — `dotnet`/`classic`/`ghidrust` (each `uses:` its
`build-<x>.yml`), `e2e-ghidrust` (`needs: [ghidrust]`, blocking live gate), `publish` (`needs: [dotnet,
classic, ghidrust, e2e-ghidrust]`, atomic — no `continue-on-error`) downloads 3 artifacts, writes a
3-row `body.md` table, and publishes all 6 assets (3 `.exe` + 3 `.sha256`) via
`softprops/action-gh-release@v2` under `tag_name: <effective tag>`.

**SPEC_MISMATCH / STATE_MISMATCH / SHAPE-DIVERGENCE: none.** The only surprises were the
`growth.md`-backup bug (a real defect the new Acceptance #10 exposes, not a spec error) and
ghidrust's total absence of an install/uninstall smoke test (an existing gap the plan must fill,
not a "flip"). Both are folded into the tasks below with an explicit note.

---

## Phase 1 — Shared build infrastructure

Produces: the non-addable build-data source, the scoped-manifest generator, the CI
namespace-collision guard, and the two shared Inno `[Code]` includes that every later phase's
installer edits consume. Nothing in this phase touches a shipping installer yet, so it is safe to
land first and is testable in isolation (the generator + guard run without ISCC).

### Task 1.1 — Relocate the repo-root marketplace manifest to a non-addable build source (C3, C9, C10, O3)

**Files:**
- Create: `build/members.json`

**Why here first:** every other task in every later phase reads `build/members.json` (the
generator in Task 1.2, and every installer's build workflow). Doing this first means nothing
downstream is ever written against the soon-to-be-deleted addressable manifest.

**Ordering note (Finding-2 fold):** this task is **additive only** — it CREATES `build/members.json`
but does **not** delete the repo-root `.claude-plugin/marketplace.json`. The delete is deferred to
**Task 4.1**, which lands it atomically with the re-point of `build-dotnet.yml`'s manifest
generation. Deleting here would break `build-dotnet.yml` (it reads `../.claude-plugin/marketplace.json`
at lines 65–75) for the entire window between this task and Task 4.1. The two files coexist
harmlessly in the interim (nothing new reads the old root manifest; the old workflow keeps reading
it until Task 4.1 flips it).

- [ ] Create `build/members.json` with the same 5 members plus a new `marketplaceName` field per
      member (the C9 unique name each installer's generated scoped manifest must carry) and
      **without** a top-level `name`/`plugins` shape that a Claude marketplace-add tool would
      recognize (C3 — the file's *shape*, not just its *location*, must not resemble an addable
      manifest, since a future accidental `git mv` back into `.claude-plugin/` should still not
      silently "just work"):

```json
{
  "$comment": "NOT a Claude marketplace manifest (C3) — a plain build-data source. Never place this file under any '.claude-plugin/' directory. Each installer's own scoped 1-entry marketplace.json is GENERATED from this by scripts/generate-scoped-manifest.ps1 (O3).",
  "owner": {
    "name": "ckir",
    "url": "https://github.com/ckir/clavity"
  },
  "members": [
    {
      "name": "agy-autotrain",
      "source": "./agy-autotrain",
      "description": "Drive the agy peer like a model and auto-train clavity's agy knowledge from everyday usage (capture -> curate -> verify -> golden-header).",
      "marketplaceName": "clavity-agy-autotrain"
    },
    {
      "name": "clavity-dotnet",
      "source": "./clavity-dotnet/plugin",
      "description": "Pair Claude with a live agy peer via the clavity-ls Language-Server bridge (agy_look / agy_status / agy_ask).",
      "marketplaceName": "clavity-dotnet"
    },
    {
      "name": "clavity-classic",
      "source": "./clavity-classic/plugin",
      "description": "clavity-classic: Claude drives a live agy peer via a psmux doorbell + the agentmemory bus.",
      "marketplaceName": "clavity-classic"
    },
    {
      "name": "commonmemory",
      "source": "./commonmemory",
      "description": "Optional add-on: a shared notebook so Claude and agy share facts across the pairing.",
      "marketplaceName": "clavity-commonmemory"
    },
    {
      "name": "ghidrust",
      "source": "./ghidrust/plugin",
      "description": "Drive a persistent headless Ghidra JVM from your agent: 19 reverse-engineering tools (decompile, navigate, durable rename/type/prototype writes) over MCP.",
      "marketplaceName": "clavity-ghidrust"
    }
  ]
}
```

- [ ] **Test (CI):** Task 1.3 adds the CI job that validates this file's shape and distinctness —
      see there for the exact assertions. There is nothing to smoke-test about a *deletion*, so
      this task's own verification is: `claude plugin marketplace add ckir/clavity` (run manually,
      once, by the owner post-merge — not automatable in this repo's CI since it requires a real
      Claude Code install) now finds no `.claude-plugin/marketplace.json` at the repo root and
      fails to add anything. Note this as an owner-run manual acceptance check for Acceptance #3
      (documented once here; not repeated per task).

### Task 1.2 — Scoped-manifest generator script (O3)

**Files:**
- Create: `scripts/generate-scoped-manifest.ps1`

- [ ] Create the generator. Every build workflow (Tasks 4.1–4.3, 3.2, 3.4) calls this with its own
      member name and output path — it is the **single** place the "rewrite the top-level `name`
      to the unique per-member value" logic (O3) lives:

```powershell
<#
.SYNOPSIS
Generates a single-plugin scoped marketplace.json for one clavity member, from the non-addable
build/members.json build source (docs/superpowers/specs/2026-07-11-cohesive-distribution-design.md,
C1/C3/C9/O3). The output's top-level "name" is the member's UNIQUE marketplaceName (C9) — this is
the value `claude plugin install <plugin>@<name>` must match, and it must never collide across the
five installers.

.PARAMETER MemberName
The member's plugin real name exactly as it appears in build/members.json "name" (e.g.
"clavity-dotnet", "ghidrust", "agy-autotrain") — NOT the marketplaceName.

.PARAMETER MembersJsonPath
Path to the repo-root build/members.json. Defaults to a path relative to this script's own
location so it resolves correctly regardless of the caller's working directory.

.PARAMETER OutFile
Destination path for the generated scoped marketplace.json (e.g.
"installer/marketplace.install.json" — the installer's [Files] then copies this literal path to
{app}\.claude-plugin\marketplace.json, DestName-renamed).
#>
param(
    [Parameter(Mandatory = $true)][string]$MemberName,
    [string]$MembersJsonPath = "$PSScriptRoot/../build/members.json",
    [Parameter(Mandatory = $true)][string]$OutFile
)

$ErrorActionPreference = "Stop"

$root = Get-Content $MembersJsonPath -Raw | ConvertFrom-Json
$member = $root.members | Where-Object { $_.name -eq $MemberName }
if (-not $member) { throw "member '$MemberName' not found in $MembersJsonPath" }
if (-not $member.marketplaceName) { throw "member '$MemberName' has no marketplaceName in $MembersJsonPath" }

# C1 scoped-manifest path/source contract: the plugin is always staged at {app}\plugins\<name> by
# the installer's own [Files] section — the generated source MUST match that literally, or every
# install fatally aborts (Failure mode J).
$scoped = [ordered]@{
    '$schema' = 'https://code.claude.com/schemas/marketplace.json'
    name      = $member.marketplaceName
    owner     = $root.owner
    plugins   = @(
        [ordered]@{
            name        = $member.name
            source      = "./plugins/$($member.name)"
            description = $member.description
        }
    )
}

$outDir = Split-Path -Parent $OutFile
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
$scoped | ConvertTo-Json -Depth 10 | Set-Content -Path $OutFile -Encoding utf8
Write-Host "generated ${OutFile}: name=$($member.marketplaceName) plugin=$($member.name) source=./plugins/$($member.name)"
```

- [ ] **Test (CI):** exercised transitively by every build workflow that calls it (Tasks 4.1/4.2/
      4.3/3.2/3.4) — each of those workflows' own smoke step asserts the generated file's `name`
      and `plugins[0].source` on the **installed** copy (post-`{app}` extraction), which is the
      end-to-end proof this script produced a correct file. No standalone CI job for the script
      alone (it has no meaningful behavior to test outside a real member + destination).

### Task 1.3 — Namespace-collision CI guard (C9, Acceptance #7)

**Files:**
- Create: `scripts/validate-members-manifest.ps1`
- Create: `.github/workflows/validate-members.yml`

- [ ] Create the guard script — this is the **direct, standalone** implementation of Acceptance #7
      ("the five scoped marketplace manifests carry five distinct top-level names, CI-asserted"),
      running directly against `build/members.json` so it doesn't need any of the five installers
      built:

```powershell
<#
.SYNOPSIS
CI guard (Acceptance #7 / C9): asserts build/members.json has exactly 5 members, each with a
name/source/marketplaceName, and that all 5 marketplaceName values are pairwise DISTINCT (a
collision silently steals the namespace and breaks every previously-installed member's plugin
resolution — Failure mode B).
#>
$ErrorActionPreference = "Stop"
$root = Get-Content "$PSScriptRoot/../build/members.json" -Raw | ConvertFrom-Json
$members = $root.members
if ($members.Count -ne 5) { throw "expected 5 members in build/members.json, found $($members.Count)" }

foreach ($m in $members) {
    if (-not $m.name) { throw "a member is missing 'name'" }
    if (-not $m.source) { throw "member '$($m.name)' is missing 'source'" }
    if (-not $m.marketplaceName) { throw "member '$($m.name)' is missing 'marketplaceName'" }
}

$names = $members | ForEach-Object { $_.marketplaceName }
$distinct = $names | Select-Object -Unique
if ($distinct.Count -ne 5) {
    throw "marketplaceName collision: expected 5 distinct names, found $($distinct.Count) ($($names -join ', '))"
}
Write-Host "OK: 5 members, 5 distinct marketplaceName values: $($distinct -join ', ')"
```

- [ ] Create the workflow that runs it on every change to the data file:

```yaml
name: validate-members
on:
  push:
    paths:
      - 'build/members.json'
      - 'scripts/validate-members-manifest.ps1'
  pull_request:
    paths:
      - 'build/members.json'
      - 'scripts/validate-members-manifest.ps1'
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Assert 5 distinct marketplace names (Acceptance #7 / C9)
        shell: pwsh
        run: ./scripts/validate-members-manifest.ps1
```

- [ ] **Test:** this workflow **is** the test — push/PR touching `build/members.json` runs it in
      CI; expected pass line is `OK: 5 members, 5 distinct marketplaceName values: clavity-dotnet,
      clavity-classic, clavity-ghidrust, clavity-agy-autotrain, clavity-commonmemory` (order as
      written in `build/members.json`, i.e. agy-autotrain, dotnet, classic, commonmemory, ghidrust
      per the file above — the assertion doesn't care about order, only distinctness).

### Task 1.4 — Shared Inno `[Code]` include: plugin registration (C1, C5 dedup, O1, O6)

**Files:**
- Create: `installer/_shared/plugin-registration.iss` (new top-level `installer/` folder at the
  repo root, distinct from each product's own `<product>/installer/` folder)

- [ ] Create the shared include. This is the **single editable place** (O1, mitigating Failure
      mode F) for the claude/agy CLI contract, used by classic/ghidrust/agy-autotrain/commonmemory
      (Task 2.4, 2.5, 3.1, 3.3 — dotnet keeps its own binary-mediated path, see Task 2.3's rationale).
      `StemOnPath` is moved here verbatim from `clavity-classic.iss` (today's only copy is
      byte-identical to dotnet's inline `ClassicClavityOnPath` scan loop, just parameterized) — this
      is a pure move, not a rewrite, so its behavior for the existing mutual-exclusion callers is
      unchanged.

```pascal
{ ============================================================================
  installer/_shared/plugin-registration.iss
  Shared Inno [Code] primitives for the cohesive-distribution model (2026-07-11 design, C1/C5/C9/
  O1/O6). #include this file INSIDE a product's own [Code] section (right after the [Code] header,
  before that product's own procedures). Every caller passes its OWN AppDir/PluginName/
  MarketplaceName — this file holds no per-product constants.

  CLI ARGUMENT VECTORS ARE VERBATIM FROM THE ORACLE
  (clavity-dotnet/src/Clavity.Ls/Install/PluginInstaller.cs, lines 17-45):
    claude plugin marketplace add <AppDir> --scope user
    claude plugin install <PluginName>@<MarketplaceName> --scope user
    agy    plugin install <AppDir>\plugins\<PluginName>
    claude|agy plugin uninstall <PluginName>
  PLUS one call this design ADDS that the oracle never issued (C6 — closing failure mode A1):
    claude plugin marketplace remove <MarketplaceName>
  (agy has no marketplace concept, so there is nothing extra to remove for it on uninstall.)

  IDEMPOTENCY IS STRUCTURAL (Finding-4), not output-parsed: RegisterClaude/RegisterAgy do a
  best-effort REMOVE of any prior registration (swallowing its result) BEFORE add/install, then
  treat the add/install exit codes normally. There is NO "already registered" substring heuristic
  to get wrong across CLI-wording changes.
============================================================================ }

{ ---- generic: is Stem[+PATHEXT] resolvable on PATH? (moved here verbatim from clavity-classic.iss
  StemOnPath — same in-process technique used by the mutual-exclusion scans: a child process with
  redirected handles inside a hidden, non-interactive Exec deadlocked the silent install; see
  clavity-classic.iss's StemOnPath comment history. Now ALSO used below for agent detection.) ---- }
function StemOnPath(const Stem: string; var FoundPath: string): Boolean;
var
  PathExt, Dir, Ext, Rest, Exts, Candidate: string;
  SemiPos: Integer;
begin
  Result := False;
  FoundPath := '';
  PathExt := GetEnv('PATHEXT');
  if PathExt = '' then PathExt := '.EXE;.BAT;.CMD';
  Rest := GetEnv('PATH');
  while (Rest <> '') and (not Result) do
  begin
    SemiPos := Pos(';', Rest);
    if SemiPos > 0 then
    begin
      Dir := Copy(Rest, 1, SemiPos - 1);
      Rest := Copy(Rest, SemiPos + 1, Length(Rest));
    end
    else
    begin
      Dir := Rest;
      Rest := '';
    end;
    Dir := Trim(Dir);
    if (Length(Dir) >= 2) and (Dir[1] = '"') and (Dir[Length(Dir)] = '"') then
      Dir := Copy(Dir, 2, Length(Dir) - 2);
    if Dir <> '' then
    begin
      if Dir[Length(Dir)] <> '\' then Dir := Dir + '\';
      Exts := PathExt;
      while (Exts <> '') and (not Result) do
      begin
        SemiPos := Pos(';', Exts);
        if SemiPos > 0 then
        begin
          Ext := Copy(Exts, 1, SemiPos - 1);
          Exts := Copy(Exts, SemiPos + 1, Length(Exts));
        end
        else
        begin
          Ext := Exts;
          Exts := '';
        end;
        Candidate := Dir + Stem + Ext;
        if FileExists(Candidate) then
        begin
          FoundPath := Candidate;
          Result := True;
        end;
      end;
    end;
  end;
end;

{ ---- agent detection: present iff its CLI resolves on PATH OR its config dir exists (mirrors
  Clavity.Ls.Install.AgentDetection.IsPresent exactly — the C# oracle for the non-Inno installer). ---- }
function ClaudePresent(): Boolean;
var
  FoundPath: string;
begin
  Result := StemOnPath('claude', FoundPath) or DirExists(ExpandConstant('{%USERPROFILE}\.claude'));
end;

function AgyPresent(): Boolean;
var
  FoundPath: string;
begin
  Result := StemOnPath('agy', FoundPath) or DirExists(ExpandConstant('{%USERPROFILE}\.gemini'));
end;

{ ---- idempotent-tolerant Exec wrapper: capture combined stdout+stderr via a temp file (Inno's
  Exec has no built-in output-capture primitive). ---- }
function ExecCaptured(const Exe, Params, WorkDir: string; var ResultCode: Integer; var Output: string): Boolean;
var
  TmpFile: string;
  Lines: TArrayOfString;
  i: Integer;
begin
  TmpFile := ExpandConstant('{tmp}') + '\clavity-exec-' + IntToStr(Random(1000000)) + '.log';
  Result := Exec(ExpandConstant('{cmd}'), '/C ' + Exe + ' ' + Params + ' > "' + TmpFile + '" 2>&1',
    WorkDir, SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Output := '';
  if LoadStringsFromFile(TmpFile, Lines) then
    for i := 0 to GetArrayLength(Lines) - 1 do
      Output := Output + Lines[i] + #13#10;
  DeleteFile(TmpFile);
end;

{ ---- register ONE agent's plugin. Idempotent BY CONSTRUCTION (Finding-4): best-effort remove of
  any prior registration (result swallowed), THEN add/install with normal exit-code handling. Returns
  True on success. AppDir is the installer's {app}; PluginName/MarketplaceName are THIS installer's
  own unique values (C9). ---- }
function RegisterClaude(const AppDir, PluginName, MarketplaceName: string; var Detail: string): Boolean;
var
  ResultCode: Integer;
  Output: string;
begin
  { remove-then-add: pre-clean any prior registration; a first-time install has nothing to remove,
    so the non-zero exit / launch failure here is IGNORED (not captured into Detail). }
  ExecCaptured('claude', 'plugin marketplace remove ' + MarketplaceName, '', ResultCode, Output);
  if not ExecCaptured('claude', 'plugin marketplace add "' + AppDir + '" --scope user', '', ResultCode, Output) then
  begin
    Detail := 'could not launch claude: ' + Output;
    Result := False;
    exit;
  end;
  if ResultCode <> 0 then
  begin
    Detail := 'marketplace add failed: ' + Output;
    Result := False;
    exit;
  end;
  ExecCaptured('claude', 'plugin uninstall ' + PluginName, '', ResultCode, Output);
  if not ExecCaptured('claude', 'plugin install "' + PluginName + '@' + MarketplaceName + '" --scope user', '', ResultCode, Output) then
  begin
    Detail := 'could not launch claude: ' + Output;
    Result := False;
    exit;
  end;
  if ResultCode <> 0 then
  begin
    Detail := 'plugin install failed: ' + Output;
    Result := False;
    exit;
  end;
  Detail := 'installed ' + PluginName + '@' + MarketplaceName;
  Result := True;
end;

function RegisterAgy(const AppDir, PluginName: string; var Detail: string): Boolean;
var
  ResultCode: Integer;
  Output, PluginDir: string;
begin
  PluginDir := AppDir + '\plugins\' + PluginName;
  { remove-then-add: pre-clean any prior registration; result swallowed for a first-time install. }
  ExecCaptured('agy', 'plugin uninstall ' + PluginName, '', ResultCode, Output);
  if not ExecCaptured('agy', 'plugin install "' + PluginDir + '"', '', ResultCode, Output) then
  begin
    Detail := 'could not launch agy: ' + Output;
    Result := False;
    exit;
  end;
  if ResultCode <> 0 then
  begin
    Detail := 'agy plugin install failed: ' + Output;
    Result := False;
    exit;
  end;
  Detail := 'installed ' + PluginName + ' from ' + PluginDir;
  Result := True;
end;

{ ---- best-effort, exception-swallowing deregistration of ONE agent (used both by rollback on a
  failed install, and by uninstall). Never raises — every step is independently guarded (K —
  a rollback that throws mid-cleanup re-creates the exact dangling state it exists to prevent). ---- }
procedure DeregisterClaude(const PluginName, MarketplaceName: string);
var
  ResultCode: Integer;
  Output: string;
begin
  try
    ExecCaptured('claude', 'plugin uninstall ' + PluginName, '', ResultCode, Output);
  except
  end;
  try
    { C6 — the oracle never called this; it's the fix for Failure mode A1 (dangling marketplace). }
    ExecCaptured('claude', 'plugin marketplace remove ' + MarketplaceName, '', ResultCode, Output);
  except
  end;
end;

procedure DeregisterAgy(const PluginName: string);
var
  ResultCode: Integer;
  Output: string;
begin
  try
    ExecCaptured('agy', 'plugin uninstall ' + PluginName, '', ResultCode, Output);
  except
  end;
end;

{ ---- top-level orchestration: register the plugin with every DETECTED agent, independently.
  RegisteredClaude/RegisteredAgy tell the caller which agents to roll back if a LATER step fails
  (C1 "rollback MUST track which agents actually registered"). AnySucceeded/AnyDetected drive the
  "fail only if every detected agent fails" rule (C1 per-agent semantics). ---- }
procedure RegisterMemberPlugin(const AppDir, PluginName, MarketplaceName: string;
  var RegisteredClaude, RegisteredAgy, AnyDetected, AnySucceeded: Boolean; var Report: string);
var
  Detail: string;
  ok: Boolean;
begin
  RegisteredClaude := False;
  RegisteredAgy := False;
  AnyDetected := False;
  AnySucceeded := False;
  Report := '';

  if ClaudePresent() then
  begin
    AnyDetected := True;
    ok := RegisterClaude(AppDir, PluginName, MarketplaceName, Detail);
    RegisteredClaude := ok;
    AnySucceeded := AnySucceeded or ok;
    Report := Report + '[claude] ' + Detail + #13#10;
  end
  else
    Report := Report + '[claude] not present on this machine' + #13#10;

  if AgyPresent() then
  begin
    AnyDetected := True;
    ok := RegisterAgy(AppDir, PluginName, Detail);
    RegisteredAgy := ok;
    AnySucceeded := AnySucceeded or ok;
    Report := Report + '[agy] ' + Detail + #13#10;
  end
  else
    Report := Report + '[agy] not present on this machine' + #13#10;
end;

{ ---- rollback: deregister only the agents THIS install actually registered (C1 "per-agent-
  tracked"), used when a step AFTER a successful registration fails. THIS PLAN'S CONCRETE
  RESOLUTION of the design's illustrative rollback-trigger list ("binary unpack, PATH, a second
  agent"): the one concrete post-registration step in this codebase is the golden-header seed
  write (dotnet/classic only — Task 2.3/2.4 call this on a SeedGoldenHeader failure). ghidrust/
  agy-autotrain/commonmemory have no post-registration step, so rollback is structurally moot for
  them (documented, not a gap — see the plan's self-audit). ---- }
procedure RollbackMemberPlugin(const PluginName, MarketplaceName: string; RegisteredClaude, RegisteredAgy: Boolean);
begin
  try
    if RegisteredClaude then DeregisterClaude(PluginName, MarketplaceName);
  except
  end;
  try
    if RegisteredAgy then DeregisterAgy(PluginName);
  except
  end;
end;

{ ---- uninstall-time deregistration: best-effort, tolerates a missing/absent agent (fail-open,
  C6). Callers invoke this from CurUninstallStepChanged's usUninstall step. ---- }
procedure DeregisterMemberPluginOnUninstall(const PluginName, MarketplaceName: string);
begin
  try
    if ClaudePresent() then DeregisterClaude(PluginName, MarketplaceName);
  except
  end;
  try
    if AgyPresent() then DeregisterAgy(PluginName);
  except
  end;
end;

{ ---- shared install-time reporting (C1 per-agent semantics): partial failure is REPORTED, not
  rolled back, at the plugin-registration step itself (only the golden-header rollback path in
  Task 2.3/2.4 actually reverses a registration). ---- }
procedure ReportRegistrationOutcome(AnyDetected, AnySucceeded, RegisteredClaude, RegisteredAgy: Boolean; const Report: string);
begin
  if not AnyDetected then
    SuppressibleMsgBox('No compatible agent (Claude Code / agy) found on this machine. Install ' +
      'Claude Code or agy, then re-run this setup.', mbError, MB_OK, IDOK)
  else if not AnySucceeded then
    SuppressibleMsgBox('Plugin registration failed for every detected agent:' + #13#10 + Report,
      mbError, MB_OK, IDOK)
  else if (ClaudePresent() and not RegisteredClaude) or (AgyPresent() and not RegisteredAgy) then
    SuppressibleMsgBox('Plugin registered, but a partial failure occurred (not rolled back):' +
      #13#10 + Report, mbInformation, MB_OK, IDOK);
end;
```

- [ ] **Test (CI):** this file has no behavior on its own (Inno never compiles an `#include`
      standalone) — it is exercised end-to-end by every installer that includes it, starting at
      Task 2.4. No task-local CI step here.

### Task 1.5 — Shared Inno `[Code]` include: golden-header seed + per-file backup (C4, C6)

**Files:**
- Create: `installer/_shared/golden-header-data.iss`

- [ ] Create the second shared include — used ONLY by clavity-dotnet and clavity-classic (Task
      2.3/2.4) for `SeedGoldenHeader`, and additionally by agy-autotrain (Task 3.1) for
      `BackupDataFile` on its own `growth.md`. This is where the `-LiteralPath` gap (C4) is closed
      **once** instead of in two duplicated inline blocks, and where the `growth.md`-touching bug
      found in Step 0 is fixed by construction (this function backs up exactly one path the
      caller names — it is never called with a file the caller doesn't own):

```pascal
{ ============================================================================
  installer/_shared/golden-header-data.iss
  Shared Inno [Code] primitives for the golden-header SEED baseline (C4) and per-file backup (C6).
  #include INSIDE a [Code] section. Used by clavity-dotnet + clavity-classic (SeedGoldenHeader);
  BackupDataFile is additionally used by agy-autotrain for its OWN growth.md (never call it on a
  file the caller does not own — C6 per-file ownership).
============================================================================ }

{ ---- C4 / Boundary-Smuggler (Failure mode D): seed {app}\seed\golden-header.md into
  %USERPROFILE%\.clavity\golden-header.seed.md. EVERY path-bound PowerShell cmdlet uses
  -LiteralPath — including New-Item, which the pre-cohesion code called with -Path (glob-
  vulnerable: a profile containing '[' silently fails to create ~/.clavity, dropping the seed). ---- }
function SeedGoldenHeader(const AppDir: string): Boolean;
var
  ResultCode: Integer;
  PsCmd, SrcPath, DestDir: string;
begin
  SrcPath := AppDir + '\seed\golden-header.md';
  DestDir := ExpandConstant('{%USERPROFILE}\.clavity');
  { panel R2-1 (pre-existing, preserved): double any single-quote so a username like O'Brien can't
    break the PS single-quoted literals. }
  StringChangeEx(SrcPath, '''', '''''', True);
  StringChangeEx(DestDir, '''', '''''', True);
  PsCmd :=
    'New-Item -ItemType Directory -Force -LiteralPath ''' + DestDir + ''' | Out-Null;' +
    'Copy-Item -LiteralPath ''' + SrcPath + ''' ' +
    '-Destination ''' + DestDir + '\golden-header.seed.md'' -Force';
  { -Command (inline) is not governed by execution policy — no -ExecutionPolicy flag needed
    (pre-existing rationale, preserved). }
  Result := Exec('powershell.exe', '-NoProfile -Command "' + PsCmd + '"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

{ ---- rename-to-.backup (never auto-restored) for exactly ONE file the CALLER owns. A driver
  passes its own seed.md / seed.md.sha256 / legacy flat file; agy-autotrain passes its own
  growth.md / growth.md.sha256. NEVER call this on a sibling's file (C6 — the exact bug this shared
  helper exists to make structurally impossible to repeat: the pre-cohesion dotnet/classic .iss
  each called their inline BackupHeaderFile on growth.md too, which is NOT theirs to touch). ---- }
procedure BackupDataFile(const Path: string);
var
  Backup: string;
begin
  Backup := Path + '.backup';
  if FileExists(Path) then
  begin
    DeleteFile(Backup);
    RenameFile(Path, Backup);
  end;
end;
```

- [ ] **Test (CI):** exercised by Task 2.3/2.4's existing "seed matches bundled baseline" smoke
      step (unchanged assertion, now backed by the shared function) plus the **new** Task 2.3/2.4
      smoke step asserting `growth.md` survives a driver uninstall (Acceptance #10).

---

## Phase 2 — Wire the three binary installers into the new model

Each task in this phase produces a rebuildable, independently-smokeable installer. Order within
the phase (dotnet's C# first, then its `.iss`, then classic, then ghidrust) matches the dependency
direction: the `.iss` teardown in Task 2.3 assumes the C# fixes in 2.1/2.2 already exist, and
classic/ghidrust (2.4/2.5) both consume the Phase 1 shared includes.

### Task 2.1 — dotnet: `PluginInstaller.cs` — unique marketplace name, idempotency, marketplace-remove (C1, C6, C9)

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/Install/PluginInstaller.cs` (48 lines, whole file is small
  enough to show as one replacement)

- [ ] Replace the file's contents:

```csharp
namespace Clavity.Ls.Install;

/// <summary>
/// Installs / uninstalls the clavity-dotnet plugin for one agent via that agent's NATIVE plugin
/// command. Claude is marketplace-based (add a marketplace root, then install plugin@marketplace);
/// agy takes the local plugin directory. The runner is injected.
/// C9: MarketplaceName is UNIQUE to this member — "clavity" would collide with every other
/// installer's local marketplace and steal the namespace (Failure mode B).
/// </summary>
public static class PluginInstaller
{
    public const string MarketplaceName = "clavity-dotnet";
    public const string PluginName = "clavity-dotnet";

    /// <summary>Install <paramref name="pluginName"/> for one agent. Claude installs it from the
    /// marketplace at <paramref name="marketplaceRoot"/>; agy installs the local
    /// <paramref name="pluginDir"/>. C1 idempotent re-run made structural (Finding-4): before adding
    /// the marketplace / installing the plugin, best-effort REMOVE the prior registration and swallow
    /// its result — so a re-run (upgrade in place) starts from a clean slate and the subsequent
    /// add/install exit codes are treated normally (non-zero = a real failure). No output-substring
    /// heuristic. Caveat: if the add/install fails right after the remove/uninstall, the prior
    /// registration is gone and that surfaces as a reported registration failure (for dotnet/classic,
    /// the install-time rollback path in Task 2.3/2.4 covers a later-step failure).</summary>
    public static AgentResult Install(Agent agent, string pluginName, string marketplaceRoot, string pluginDir, ProcessRunner run)
    {
        switch (agent)
        {
            case Agent.Claude:
                // remove-then-add: swallow the pre-clean result (a first-time install has nothing to remove).
                run("claude", new[] { "plugin", "marketplace", "remove", MarketplaceName });
                var add = run("claude", new[] { "plugin", "marketplace", "add", marketplaceRoot, "--scope", "user" });
                if (add.ExitCode != 0)
                    return new AgentResult(agent, false, $"marketplace add failed: {Clip(add.Output)}");
                run("claude", new[] { "plugin", "uninstall", pluginName });
                var ins = run("claude", new[] { "plugin", "install", $"{pluginName}@{MarketplaceName}", "--scope", "user" });
                if (ins.ExitCode != 0)
                    return new AgentResult(agent, false, $"install failed: {Clip(ins.Output)}");
                return new AgentResult(agent, true, $"installed {pluginName}@{MarketplaceName}");

            case Agent.Agy:
                run("agy", new[] { "plugin", "uninstall", pluginName });
                var r = run("agy", new[] { "plugin", "install", pluginDir });
                if (r.ExitCode != 0)
                    return new AgentResult(agent, false, $"install failed: {Clip(r.Output)}");
                return new AgentResult(agent, true, $"installed {pluginName} from {pluginDir}");

            default:
                throw new ArgumentOutOfRangeException(nameof(agent));
        }
    }

    /// <summary>C6: deregister the plugin AND the scoped local marketplace, so no dangling registry
    /// path survives an uninstall (Failure mode A1 — the pre-cohesion oracle only ever removed the
    /// plugin, never the marketplace entry). Best-effort: a marketplace-remove failure does not
    /// flip an otherwise-OK plugin uninstall to failure (uninstall stays fail-open, C6).</summary>
    public static AgentResult Uninstall(Agent agent, string pluginName, ProcessRunner run)
    {
        var exe = agent == Agent.Claude ? "claude" : "agy";
        var r = run(exe, new[] { "plugin", "uninstall", pluginName });
        if (agent == Agent.Claude)
            run("claude", new[] { "plugin", "marketplace", "remove", MarketplaceName });
        return new AgentResult(agent, r.ExitCode == 0,
            r.ExitCode == 0 ? $"uninstalled {pluginName}" : $"uninstall failed: {Clip(r.Output)}");
    }

    private static string Clip(string s) => string.IsNullOrEmpty(s) ? "(no output)" : (s.Length > 200 ? s[..200] : s);
}
```

- [ ] **Test:** `dotnet test tests/Clavity.Ls.Tests` from `clavity-dotnet/` — the existing
      `PluginInstaller`-targeting unit tests (if any assert the literal `"clavity"` marketplace
      name, they must be updated to `"clavity-dotnet"` — grep
      `tests/Clavity.Ls.Tests` for `MarketplaceName` / `"clavity"` before running and update any
      hard-coded expectation to `"clavity-dotnet"`). Expected pass line: `Passed!` with 0 failed
      (matches the repo's existing full-suite green baseline — do not narrow the run scope).

### Task 2.2 — dotnet: `CliRouter.cs` — per-agent OR-semantics (C1)

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/Install/CliRouter.cs`, the `"install"` case only (lines
  53–66 today)

- [ ] Replace the `"install"` case (leave the `"uninstall"` and `"is-installed"` cases unchanged —
      the design's per-agent semantics section is explicit that it governs **install**; the plan
      does not extend it to uninstall, which stays fail-if-any-agent-fails as it is today):

```csharp
            case "install":
            {
                var pluginName = OptionValue(args, "--plugin") ?? PluginInstaller.PluginName;   // default = core
                var dir = PluginDirFor(pluginName, pluginDir);
                var anySucceeded = false;
                var registeredCount = 0;
                foreach (var a in Enum.GetValues<Agent>())
                {
                    if (!present.Contains(a)) { output.WriteLine($"[{a}] skipped — not present on this machine"); continue; }
                    var r = PluginInstaller.Install(a, pluginName, marketplaceRoot, dir, run);
                    if (r.Ok) registeredCount++;
                    anySucceeded |= r.Ok;
                    output.WriteLine($"[{a}] {(r.Ok ? "ok" : "FAILED")}: {r.Detail}");
                }
                // C1 per-agent semantics: fail only if EVERY detected agent's registration failed
                // (a genuine no-op install). A partial success is reported, not rolled back here.
                if (!anySucceeded)
                {
                    output.WriteLine("clavity-ls: plugin registration failed for every detected agent.");
                    return 1;
                }
                if (registeredCount < present.Count)
                    output.WriteLine("clavity-ls: plugin registered for at least one agent; the FAILED agent(s) above were left as reported (not rolled back).");
                return 0;
            }
</br>
```

  (Remove the stray `</br>` — Markdown artifact; the C# block ends at the closing `}` of the
  `case "install":` block above. Everything else in `CliRouter.cs` — the `"uninstall"` case, the
  `present.Count == 0` short-circuit, `PluginDirFor`, `RealRunner` — is unchanged.)

- [ ] **Test:** `dotnet test tests/Clavity.Ls.Tests`. Name the oracle: any existing `CliRouter`
      install test that asserts a **mixed** per-agent result (one `Agent.Claude` failure + one
      `Agent.Agy` success, or vice versa via an injected fake `ProcessRunner`) must now assert
      **exit code 0** (was 1 before this change) — if no such test exists today, this task adds
      one: fake two present agents, one `run()` delegate returns exit 0 for Claude and non-zero
      for agy, assert `CliRouter.Run(...)` returns `0` and the output contains both `"[Claude] ok"`
      and `"[Agy] FAILED"`. Expected pass line: `Passed!`.

### Task 2.3 — dotnet: `clavity-dotnet.iss` — teardown bundled siblings, adopt shared seed include, fix `growth.md` bug, version bump (C2, C4, C6, C10)

**Files:**
- Modify: `clavity-dotnet/installer/clavity-dotnet.iss`

**Decision (per the spec's explicit invitation to decide per-installer, C1):** dotnet **keeps**
registering via `Exec({app}\clavity-ls.exe, 'install --agent all')` (unchanged mechanism — it
already has its own binary, and Tasks 2.1/2.2 just fixed that binary's C# logic) rather than
adopting `installer/_shared/plugin-registration.iss`. It **does** adopt
`installer/_shared/golden-header-data.iss` (O1 DRY — its seeding block is byte-identical to
classic's today).

- [ ] Remove the sibling `[Files]` lines (45–46, 49) and the now-obsolete comment block (lines
      6, 8–10 describing the bundled layout):

  Before (lines 43–49):
  ```
  Source: "..\plugin\*"; DestDir: "{app}\plugins\clavity-dotnet"; Flags: ignoreversion recursesubdirs createallsubdirs
  ; Optional add-ons: shipped so the marketplace resolves, but only INSTALLED if the Phase 4 [Tasks] are ticked.
  Source: "..\..\agy-autotrain\*"; DestDir: "{app}\plugins\agy-autotrain"; Flags: ignoreversion recursesubdirs createallsubdirs
  Source: "..\..\commonmemory\*"; DestDir: "{app}\plugins\commonmemory"; Flags: ignoreversion recursesubdirs createallsubdirs
  ; ghidrust: staged so the bundled marketplace's ./plugins/ghidrust entry resolves (else it dangles). Claude
  ; installs it from the marketplace; the ghidrust.exe binary ships separately via the ghidrust-v<N> installer (D7).
  Source: "..\..\ghidrust\plugin\*"; DestDir: "{app}\plugins\ghidrust"; Flags: ignoreversion recursesubdirs createallsubdirs
  ```
  After:
  ```
  Source: "..\plugin\*"; DestDir: "{app}\plugins\clavity-dotnet"; Flags: ignoreversion recursesubdirs createallsubdirs
  ```

- [ ] Remove the two add-on `[Tasks]` lines (54–55):

  Before:
  ```
  Name: "install_agy_autotrain"; Description: "Install agy-autotrain — lets the AI permanently learn your project's rules and stop repeating mistakes"; Flags: unchecked
  Name: "install_commonmemory"; Description: "Install commonmemory — a shared notebook so Claude and agy share facts (needs the agentmemory MCP server)"; Flags: unchecked
  ```
  After: (deleted — `[Tasks]` now has only `addtopath`)

- [ ] Remove the `InstallAddon` procedure (178–189) entirely, and the two gated calls in
      `CurStepChanged` (227–235):

  Before (227–235):
  ```
      { Optional add-ons — install each ticked one (default OFF). }
      if WizardIsTaskSelected('install_agy_autotrain') then InstallAddon('agy-autotrain');
      if WizardIsTaskSelected('install_commonmemory') then
      begin
        InstallAddon('commonmemory');
        { commonmemory has a runtime dependency on the agentmemory MCP server — be honest, do not auto-install it. }
        SuppressibleMsgBox('commonmemory was registered, but it needs the agentmemory MCP server to actually work.' + #13#10 +
          'If you have not installed agentmemory yet, install it separately — until then the shared notebook stays inactive.',
          mbInformation, MB_OK, IDOK);
      end;
  ```
  After: (deleted)

- [ ] Add the shared include at the top of `[Code]` (after `var RemoveConfig: Boolean;`), and
      replace the inline seeding block (204–225) with a call to the shared function, wiring in the
      install-time rollback this design adds (a seed failure after a successful registration rolls
      the registration back — this task's concrete resolution of the illustrative rollback trigger
      list, per Task 1.4's include comment):

  Before (`[Code]` header + var):
  ```
  [Code]
  var
    RemoveConfig: Boolean;
  ```
  After:
  ```
  [Code]
  #include "..\..\installer\_shared\golden-header-data.iss"

  var
    RemoveConfig: Boolean;
  ```

  Before (204–225, the seeding block inside `CurStepChanged`):
  ```
      { Phase 3: seed golden-header.seed.md from the bundled baseline with standard PowerShell (always
        available; no dependency on the just-installed binary running). Overwrites SEED only; never touches GROWTH. }
      SrcPath := ExpandConstant('{app}\seed\golden-header.md');
      { panel agy-R3-a: resolve the profile via Inno's {%USERPROFILE} (same as the zombie-header rename
        below), NOT PowerShell's $env:USERPROFILE — under any elevation the two can differ, silently seeding the wrong
        profile. Inno's constant matches the interactive install user consistently. }
      DestDir := ExpandConstant('{%USERPROFILE}\.clavity');
      { panel R2-1: double any single-quote so a username like O'Brien can't break the PS single-quoted literals. }
      StringChangeEx(SrcPath, '''', '''''', True);
      StringChangeEx(DestDir, '''', '''''', True);
      PsCmd :=
        'New-Item -ItemType Directory -Force -Path ''' + DestDir + ''' | Out-Null;' +
        'Copy-Item -LiteralPath ''' + SrcPath + ''' ' +
        '-Destination ''' + DestDir + '\golden-header.seed.md'' -Force';
      { -Command (inline) is not governed by execution policy, so no -ExecutionPolicy flag is needed (panel R2-2). }
      if not Exec('powershell.exe', '-NoProfile -Command "' + PsCmd + '"',
                  '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
        SuppressibleMsgBox('Could not seed the golden-header baseline. The AI still works; seed it later by copying' + #13#10 +
          ExpandConstant('{app}\seed\golden-header.md') + '  to  %USERPROFILE%\.clavity\golden-header.seed.md', mbInformation, MB_OK, IDOK)
      else if ResultCode <> 0 then
        SuppressibleMsgBox('Seeding the golden-header baseline reported a problem (exit code ' + IntToStr(ResultCode) + ').',
          mbInformation, MB_OK, IDOK);
  ```
  After:
  ```
      { C4/O1: shared seeding function (installer/_shared/golden-header-data.iss) — -LiteralPath on
        every path-bound cmdlet, including New-Item (the pre-cohesion gap). C1 install-time rollback:
        a seed failure after a successful clavity-ls registration rolls that registration back rather
        than leaving a half-installed plugin whose seed never landed. }
      if not SeedGoldenHeader(ExpandConstant('{app}')) then
      begin
        Exec(ExpandConstant('{app}\{#ExeName}'), 'uninstall --agent all', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
        SuppressibleMsgBox('Could not seed the golden-header baseline, so the plugin registration was rolled ' +
          'back. Re-run this setup. (You can also seed it manually later by copying' + #13#10 +
          ExpandConstant('{app}\seed\golden-header.md') + '  to  %USERPROFILE%\.clavity\golden-header.seed.md and ' +
          'running:  clavity-ls install --agent all)', mbError, MB_OK, IDOK);
      end;
  ```
  (`SrcPath`/`DestDir`/`PsCmd` local vars in `CurStepChanged`'s `var` block become unused — remove
  them from that `var` block too, keeping only `ResultCode` and any vars still used by the
  add-on-free rest of the procedure.)

- [ ] Fix the `growth.md`-touching bug in `CurUninstallStepChanged` (Step 0 finding — Acceptance
      #10). Replace the three `BackupHeaderFile` calls with the shared `BackupDataFile` and drop
      the `growth.md` line entirely (it is agy-autotrain's file, not this driver's):

  Before (327–329):
  ```
        BackupHeaderFile(ExpandConstant('{%USERPROFILE}\.clavity\golden-header.seed.md'));
        BackupHeaderFile(ExpandConstant('{%USERPROFILE}\.clavity\golden-header.growth.md'));
        BackupHeaderFile(ExpandConstant('{%USERPROFILE}\.clavity\golden-header.md'));  { legacy flat, if present }
  ```
  After:
  ```
        { C6: back up ONLY driver-owned files — seed.md + its .sha256 sidecar + the legacy flat file.
          growth.md is agy-autotrain's file; touching it here was the pre-cohesion bug (Failure mode
          H) this design fixes — it is removed/backed up ONLY by agy-autotrain's own uninstall. }
        BackupDataFile(ExpandConstant('{%USERPROFILE}\.clavity\golden-header.seed.md'));
        BackupDataFile(ExpandConstant('{%USERPROFILE}\.clavity\golden-header.seed.md.sha256'));
        BackupDataFile(ExpandConstant('{%USERPROFILE}\.clavity\golden-header.md'));  { legacy flat, if present }
  ```
  - [ ] Also delete the now-redundant local `BackupHeaderFile` procedure definition (297–307) —
        the shared `BackupDataFile` replaces it.

- [ ] Bump `#define AppVersion "0.1.13"` → `#define AppVersion "0.1.14"` (line 13) — this is a
      real behavior/release change per repo convention ("bump each variant's version in its own
      `installer/*.iss`").

- [ ] **Test (CI):** Task 4.1 rewrites `build-dotnet.yml`'s smoke section to match this teardown —
      see that task for the exact new assertions (single-member manifest, no sibling `plugins\*`
      dirs, `growth.md` survives, idempotent re-run). This task's own local check before Task 4.1
      lands: `dotnet build` from `clavity-dotnet/` still succeeds (no `.iss` change touches C#, but
      confirms Tasks 2.1/2.2 compile cleanly with this task's Exec-based rollback call, which
      depends on nothing new in C#).

### Task 2.4 — classic: `clavity-classic.iss` — gain self-registration (C1, C4, C6, C9, O1)

**Files:**
- Modify: `clavity-classic/installer/clavity-classic.iss`

- [ ] Add plugin staging + scoped-manifest copy to `[Files]` (after line 47, the bridge
      README-FIRST line):

```
Source: "marketplace.install.json"; DestDir: "{app}\.claude-plugin"; DestName: "marketplace.json"; Flags: ignoreversion
Source: "..\plugin\*"; DestDir: "{app}\plugins\clavity-classic"; Flags: ignoreversion recursesubdirs createallsubdirs
```

- [ ] Add the two shared `#include`s to `[Code]`, right after the header:

  Before:
  ```
  [Code]
  var
    RemoveConfig: Boolean;
  ```
  After:
  ```
  [Code]
  #include "..\..\installer\_shared\plugin-registration.iss"
  #include "..\..\installer\_shared\golden-header-data.iss"

  var
    RemoveConfig: Boolean;
  ```

- [ ] **DELETE classic.iss's inline `StemOnPath` function (lines 102–154) (Finding-1 fold —
      BLOCKING).** Task 1.4 moved `StemOnPath` verbatim into
      `installer/_shared/plugin-registration.iss`; that file is now `#include`d above, so keeping
      classic's inline copy makes ISCC throw a duplicate-identifier error. Remove the entire inline
      `function StemOnPath(...)` block (the header comment at 100–101 plus the body 102–154). The
      shared include sits at the top of `[Code]`, declared BEFORE any use, so classic's
      `InitializeSetup` mutual-exclusion call `StemOnPath('clavity-ls', FoundPath)` (line 183) and
      the bridge `StemOnPath('uv', UvPath)` call (line 234) both resolve cleanly against the
      include's copy — same signature, same behavior (the include's version is a byte-for-byte move
      of classic's, per Task 1.4). **Scope note:** classic is the ONLY installer that collides —
      dotnet uses a differently-named `ClassicClavityOnPath` (not `StemOnPath`) AND per Task 2.3
      does NOT `#include` plugin-registration.iss, so no dotnet collision; ghidrust/agy-autotrain/
      commonmemory have no inline `StemOnPath` of their own (they only gain the include). No other
      inline-vs-include duplication exists across the five installers.

- [ ] Replace the inline seeding block in `CurStepChanged` (207–230) with the shared function +
      registration call, inserted BEFORE the existing seeding position so registration happens
      first (matching C1's ordering: register, then seed, then roll back the registration if
      seeding fails):

  Before (204–230, the whole seeding block plus its preceding `var` line already shown in Step 0):
  ```
    if CurStep = ssPostInstall then
    begin
      { Phase 3 parity: seed golden-header.seed.md from the bundled baseline with standard PowerShell (always
        available; no dependency on running the just-installed binary). Overwrites SEED only; never touches GROWTH.
        Unconditional — runs regardless of the bridge task. }
      SrcPath := ExpandConstant('{app}\seed\golden-header.md');
      ...
      if not Exec('powershell.exe', '-NoProfile -Command "' + PsCmd + '"',
                  '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
        SuppressibleMsgBox('Could not seed the golden-header baseline. clavity still works; seed it later by copying' + #13#10 +
          ExpandConstant('{app}\seed\golden-header.md') + '  to  %USERPROFILE%\.clavity\golden-header.seed.md', mbInformation, MB_OK, IDOK)
      else if ResultCode <> 0 then
        SuppressibleMsgBox('Seeding the golden-header baseline reported a problem (exit code ' + IntToStr(ResultCode) + ').',
          mbInformation, MB_OK, IDOK);
      if WizardIsTaskSelected('install_bridge') then
  ```
  After:
  ```
    if CurStep = ssPostInstall then
    begin
      { C1/C9: register the clavity-classic plugin against every detected agent — classic has no
        own binary, so (unlike dotnet) it uses the shared Inno registration primitives directly. }
      RegisterMemberPlugin(ExpandConstant('{app}'), 'clavity-classic', 'clavity-classic',
        RegisteredClaude, RegisteredAgy, AnyDetected, AnySucceeded, RegReport);
      ReportRegistrationOutcome(AnyDetected, AnySucceeded, RegisteredClaude, RegisteredAgy, RegReport);

      { C4/O1: shared seeding function. C1 install-time rollback: a seed failure after a successful
        registration rolls the registration back. Unconditional — runs regardless of the bridge task. }
      if AnySucceeded and (not SeedGoldenHeader(ExpandConstant('{app}'))) then
      begin
        RollbackMemberPlugin('clavity-classic', 'clavity-classic', RegisteredClaude, RegisteredAgy);
        SuppressibleMsgBox('Could not seed the golden-header baseline, so the plugin registration was rolled ' +
          'back. Re-run this setup. (You can also seed it manually later by copying' + #13#10 +
          ExpandConstant('{app}\seed\golden-header.md') + '  to  %USERPROFILE%\.clavity\golden-header.seed.md)',
          mbError, MB_OK, IDOK);
      end;
      if WizardIsTaskSelected('install_bridge') then
  ```
  - [ ] Add `RegisteredClaude, RegisteredAgy, AnyDetected, AnySucceeded: Boolean; RegReport: string;`
        to `CurStepChanged`'s `var` block (alongside the existing `UvPath, BridgeDir, PsCmd,
        SrcPath, DestDir: string;` — remove `PsCmd`/`SrcPath`/`DestDir` since they're now unused,
        the shared function owns them internally).

- [ ] Fix the `growth.md` bug in `CurUninstallStepChanged` (Step 0 finding), same as Task 2.3:

  Before (311–313):
  ```
        BackupHeaderFile(ExpandConstant('{%USERPROFILE}\.clavity\golden-header.seed.md'));
        BackupHeaderFile(ExpandConstant('{%USERPROFILE}\.clavity\golden-header.growth.md'));
        BackupHeaderFile(ExpandConstant('{%USERPROFILE}\.clavity\golden-header.md'));  { legacy flat, if present }
  ```
  After:
  ```
        { C6: back up ONLY driver-owned files — growth.md is agy-autotrain's, not touched here. }
        BackupDataFile(ExpandConstant('{%USERPROFILE}\.clavity\golden-header.seed.md'));
        BackupDataFile(ExpandConstant('{%USERPROFILE}\.clavity\golden-header.seed.md.sha256'));
        BackupDataFile(ExpandConstant('{%USERPROFILE}\.clavity\golden-header.md'));  { legacy flat, if present }
  ```
  - [ ] Delete the now-redundant local `BackupHeaderFile` procedure (288–298).

- [ ] Add deregistration to `CurUninstallStepChanged`'s `usUninstall` branch (alongside the
      existing backup calls):

```
    DeregisterMemberPluginOnUninstall('clavity-classic', 'clavity-classic');
```

- [ ] Extend O6's shared-mutex convention: `SetupMutex=ClavitySetupMutex` is **already** present
      (line 31, shared with dotnet) — no change needed here; this task just documents that classic
      is already part of the O6 mutex group (dotnet+classic today; Tasks 2.5/3.1/3.3 extend the
      same literal value to the other three installers, achieving the full 5-way serialization).

- [ ] Bump `#define AppVersion "0.1.0"` → `#define AppVersion "0.1.1"` (line 11) — and update the
      3-way version-consistency check's other two files to match (`Cargo.toml`, and
      `agy-mcp-bridge/pyproject.toml`), since `build-classic.yml`'s "Version consistency" step
      (Task 0, unmodified by this plan) throws if the three ever disagree.

- [ ] **Test (CI):** Task 4.2 adds the new smoke assertions for this installer — see that task.

### Task 2.5 — ghidrust: `ghidrust.iss` — gain self-registration + join the O6 mutex (C1, C9, O6)

**Files:**
- Modify: `ghidrust/installer/ghidrust.iss`

- [ ] Add plugin staging + scoped-manifest copy to `[Files]` (after line 31):

```
Source: "marketplace.install.json"; DestDir: "{app}\.claude-plugin"; DestName: "marketplace.json"; Flags: ignoreversion
Source: "..\plugin\*"; DestDir: "{app}\plugins\ghidrust"; Flags: ignoreversion recursesubdirs createallsubdirs
```

- [ ] Add the O6 shared mutex to `[Setup]` (after `ChangesEnvironment=yes`, line 28):

```
; O6: shared with ALL FIVE member installers (was dotnet+classic only). Defensive default — this
; plan could not live-verify whether the claude/agy CLIs serialize their own global-config writes
; (that needs a live two-terminal test against the real CLI, out of scope for a static plan), so it
; adds the cheap, already-proven mutex mechanism defensively rather than leaving the race open.
SetupMutex=ClavitySetupMutex
```

- [ ] Add the shared `#include` and a registration call to the existing `CurStepChanged` (which
      today only handles the Ghidra install-dir env var):

  Before (84–99):
  ```
  procedure CurStepChanged(CurStep: TSetupStep);
  var
    Dir: string;
  begin
    if CurStep = ssPostInstall then
    begin
      Dir := Trim(GhidraPage.Values[0]);
      if Dir <> '' then
      begin
        RegWriteExpandStringValue(HKCU, 'Environment', 'GHIDRA_INSTALL_DIR', Dir);
        if not FileExists(Dir + '\support\analyzeHeadless.bat') then
          MsgBox('Warning: support\analyzeHeadless.bat was not found under the Ghidra folder you gave. ' +
                 'Install Ghidra 12.1.2 before using ghidrust. (Install continues.)', mbInformation, MB_OK);
      end;
    end;
  end;
  ```
  After:
  ```
  procedure CurStepChanged(CurStep: TSetupStep);
  var
    Dir: string;
    RegisteredClaude, RegisteredAgy, AnyDetected, AnySucceeded: Boolean;
    RegReport: string;
  begin
    if CurStep = ssPostInstall then
    begin
      { C1/C9: register the ghidrust plugin against every detected agent (ghidrust has no post-
        registration step like the golden-header seed, so there is nothing here to roll back on —
        see installer/_shared/plugin-registration.iss's RollbackMemberPlugin comment). }
      RegisterMemberPlugin(ExpandConstant('{app}'), 'ghidrust', 'clavity-ghidrust',
        RegisteredClaude, RegisteredAgy, AnyDetected, AnySucceeded, RegReport);
      ReportRegistrationOutcome(AnyDetected, AnySucceeded, RegisteredClaude, RegisteredAgy, RegReport);

      Dir := Trim(GhidraPage.Values[0]);
      if Dir <> '' then
      begin
        RegWriteExpandStringValue(HKCU, 'Environment', 'GHIDRA_INSTALL_DIR', Dir);
        if not FileExists(Dir + '\support\analyzeHeadless.bat') then
          MsgBox('Warning: support\analyzeHeadless.bat was not found under the Ghidra folder you gave. ' +
                 'Install Ghidra 12.1.2 before using ghidrust. (Install continues.)', mbInformation, MB_OK);
      end;
    end;
  end;
  ```
  - [ ] Add `#include "..\..\installer\_shared\plugin-registration.iss"` right after `[Code]`
        (before the existing `var GhidraPage: TInputDirWizardPage;`).

- [ ] Add deregistration to `CurUninstallStepChanged` (today it only has a `usPostUninstall`
      branch for PATH removal):

  Before (101–105):
  ```
  procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
  begin
    if CurUninstallStep = usPostUninstall then
      RemoveFromUserPath(ExpandConstant('{app}'));
  end;
  ```
  After:
  ```
  procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
  begin
    if CurUninstallStep = usUninstall then
      DeregisterMemberPluginOnUninstall('ghidrust', 'clavity-ghidrust');
    if CurUninstallStep = usPostUninstall then
      RemoveFromUserPath(ExpandConstant('{app}'));
  end;
  ```

- [ ] Bump `#define AppVersion "1.0.0"` → `#define AppVersion "1.1.0"` (line 9) — a real new
      capability (plugin self-registration) on top of the existing binary-only install.

- [ ] Update the file's header comment (lines 4–6, describing "two-channel delivery... the plugin
      is delivered via the marketplace on main") to reflect that this is now false — see also Task
      4.6 for the umbrella-level doc fix:

  Before:
  ```
  ; Two-channel delivery (see docs/superpowers/specs/2026-07-09-ghidrust-onboarding-design.md): this installer
  ; ships ONLY the binary. The plugin (skill + .mcp.json) is delivered via the marketplace on main — the
  ; installer never stages plugins/, so there is no cross-branch bundling.
  ```
  After:
  ```
  ; Cohesive distribution model (docs/superpowers/specs/2026-07-11-cohesive-distribution-design.md,
  ; supersedes the two-channel note this replaced): this installer ships BOTH the binary AND its own
  ; plugin, self-registering a local scoped marketplace (clavity-ghidrust) against each detected
  ; agent. There is no remote-marketplace delivery path anymore.
  ```

- [ ] **Test (CI):** Task 4.3 adds ghidrust's first-ever install/uninstall smoke test (it has none
      today — see Step 0 finding) — see that task for the full assertions.

---

## Phase 3 — Two new plugin-only installers

Neither `agy-autotrain` nor `commonmemory` has an installer today. Both are pure-plugin folders
already living at the repo root on `main` (confirmed: `agy-autotrain/.claude-plugin/plugin.json`
v0.1.4, `commonmemory/.claude-plugin/plugin.json` v0.1.0) — Task 1.1's `build/members.json`
already lists both. This phase adds their installers and reusable build workflows, using the
Phase 1 shared includes throughout (O1).

### Task 3.1 — agy-autotrain installer (C1, C6, C9)

**Files:**
- Create: `agy-autotrain/installer/agy-autotrain.iss`

- [ ] Create the installer. Fresh `AppId` GUID generated for this task (never reuse another
      member's): `84B5A584-55BB-44DE-B53C-E6602880AE6B`. This member additionally implements its
      OWN half of C6 (Acceptance #10's "removed only by agy-autotrain's own uninstall") — a
      keep/purge prompt for `golden-header.growth.md` + its `.sha256` sidecar, symmetric with how
      the drivers handle their own `seed.md`:

```pascal
; Inno Setup script for agy-autotrain (plugin-only member; no binary). Build with:
; ISCC.exe installer\agy-autotrain.iss
; Cohesive distribution model (docs/superpowers/specs/2026-07-11-cohesive-distribution-design.md):
; ships the agy-autotrain plugin folder + a scoped 1-entry marketplace.json, self-registering
; against each detected agent (Claude Code / agy). No binary, no download, no remote marketplace.

#define AppName "agy-autotrain"
#define AppVersion "0.1.0"

[Setup]
AppId={{84B5A584-55BB-44DE-B53C-E6602880AE6B}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=clavity
LicenseFile=..\LICENSE
DefaultDirName={localappdata}\Programs\agy-autotrain
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=agy-autotrain-setup-{#AppVersion}
OutputDir=..\dist
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; O6: shared with all five member installers (defensive default — see ghidrust.iss's comment).
SetupMutex=ClavitySetupMutex

[Files]
Source: "marketplace.install.json"; DestDir: "{app}\.claude-plugin"; DestName: "marketplace.json"; Flags: ignoreversion
Source: "..\*"; DestDir: "{app}\plugins\agy-autotrain"; Flags: ignoreversion recursesubdirs createallsubdirs; \
  Excludes: "installer,dist,publish"

[Code]
#include "..\..\installer\_shared\plugin-registration.iss"
#include "..\..\installer\_shared\golden-header-data.iss"

var
  RemoveGrowth: Boolean;

procedure CurStepChanged(CurStep: TSetupStep);
var
  RegisteredClaude, RegisteredAgy, AnyDetected, AnySucceeded: Boolean;
  RegReport: string;
begin
  if CurStep = ssPostInstall then
  begin
    RegisterMemberPlugin(ExpandConstant('{app}'), 'agy-autotrain', 'clavity-agy-autotrain',
      RegisteredClaude, RegisteredAgy, AnyDetected, AnySucceeded, RegReport);
    ReportRegistrationOutcome(AnyDetected, AnySucceeded, RegisteredClaude, RegisteredAgy, RegReport);
  end
  else if CurStep = ssDone then
    SuppressibleMsgBox('agy-autotrain is installed. It will start learning from your project the ' +
      'next time you drive agy from Claude Code. C7: if no clavity driver (clavity-dotnet or ' +
      'clavity-classic) is installed yet, the learned header will not be injected until one is — ' +
      'this is expected and non-blocking.', mbInformation, MB_OK, IDOK);
end;

function InitializeUninstall(): Boolean;
begin
  Result := True;
  { C6: this member owns growth.md — offer the same keep/purge choice the drivers offer for their
    own seed.md. Silent uninstall defaults to KEEP (IDNO) — never delete user data without an
    explicit answer. }
  RemoveGrowth := SuppressibleMsgBox('Also remove the learned golden-header growth data ' +
    '(~\.clavity\golden-header.growth.md)?' + #13#10 + 'Choose No to keep it for a future reinstall.',
    mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  GrowthFile: string;
begin
  if CurUninstallStep = usUninstall then
  begin
    DeregisterMemberPluginOnUninstall('agy-autotrain', 'clavity-agy-autotrain');
    GrowthFile := ExpandConstant('{%USERPROFILE}\.clavity\golden-header.growth.md');
    if RemoveGrowth then
    begin
      if FileExists(GrowthFile) then DeleteFile(GrowthFile);
      if FileExists(GrowthFile + '.sha256') then DeleteFile(GrowthFile + '.sha256');
    end
    else
    begin
      BackupDataFile(GrowthFile);
      BackupDataFile(GrowthFile + '.sha256');
    end;
  end;
end;
```

- [ ] **Test (CI):** Task 3.2's build workflow adds the smoke assertions.

### Task 3.2 — `build-agy-autotrain.yml` (O4)

**Files:**
- Create: `.github/workflows/build-agy-autotrain.yml`

- [ ] Create the reusable build workflow, mirroring `build-ghidrust.yml`'s shape (outputs:
      version/sha/artifact-name) but with **no** compile step (O4: this member builds straight
      from `main`, since it is pure plugin content and already lives there — no reason to add a
      branch):

```yaml
name: build-agy-autotrain

# Reusable build+smoke for the agy-autotrain installer. Plugin-only member — no compile step (O4:
# builds from main, same as the plugin content itself already does).
on:
  workflow_call:
    outputs:
      version:
        value: ${{ jobs.build.outputs.version }}
      sha:
        value: ${{ jobs.build.outputs.sha }}
      artifact-name:
        value: ${{ jobs.build.outputs.artifact-name }}
  workflow_dispatch:

jobs:
  build:
    runs-on: windows-latest
    defaults:
      run:
        working-directory: agy-autotrain
    outputs:
      version: ${{ steps.ver.outputs.version }}
      sha: ${{ steps.sha.outputs.sha }}
      artifact-name: agy-autotrain-installer
    steps:
      - uses: actions/checkout@v4

      - name: Record the built commit
        id: sha
        shell: bash
        run: echo "sha=$(git rev-parse HEAD)" >> "$GITHUB_OUTPUT"

      - name: Extract version from .iss
        id: ver
        shell: pwsh
        run: |
          $v = (Select-String -Path installer/agy-autotrain.iss -Pattern '#define AppVersion "([^"]+)"').Matches[0].Groups[1].Value
          "version=$v" | Out-File -FilePath $env:GITHUB_OUTPUT -Append
          "TOOL_VER=$v" | Out-File -FilePath $env:GITHUB_ENV -Append

      - name: Generate scoped marketplace.json (O3)
        shell: pwsh
        run: ../scripts/generate-scoped-manifest.ps1 -MemberName agy-autotrain -OutFile installer/marketplace.install.json

      - name: Install Inno Setup
        shell: pwsh
        run: choco install innosetup --no-progress -y

      - name: Build installer (ISCC)
        shell: pwsh
        run: |
          $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
          if (-not (Test-Path $iscc)) { throw "ISCC.exe not found at $iscc" }
          & $iscc installer/agy-autotrain.iss
          if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }
          $setup = "dist/agy-autotrain-setup-$env:TOOL_VER.exe"
          if (-not (Test-Path $setup)) { throw "$setup was not produced" }

      - name: Compute SHA-256 companion
        shell: pwsh
        run: |
          $name = "agy-autotrain-setup-$env:TOOL_VER.exe"
          $h = (Get-FileHash "dist/$name" -Algorithm SHA256).Hash.ToLower()
          "$h  $name" | Set-Content -Path "dist/$name.sha256" -Encoding ascii

      - name: Smoke — install/uninstall lifecycle + namespace + C6 growth ownership
        timeout-minutes: 6
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $setup = "dist/agy-autotrain-setup-$env:TOOL_VER.exe"
          $app = "$env:LOCALAPPDATA\Programs\agy-autotrain"

          $p = Start-Process $setup -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait -PassThru
          if ($p.ExitCode -ne 0) { throw "install exit $($p.ExitCode)" }
          # Finding-5: re-run the SAME installer — idempotent upgrade (remove-then-add) must exit 0.
          $p2 = Start-Process $setup -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait -PassThru
          if ($p2.ExitCode -ne 0) { throw "re-run install exit $($p2.ExitCode) — idempotent upgrade must not abort" }
          if (-not (Test-Path "$app\.claude-plugin\marketplace.json")) { throw "marketplace.json not installed" }
          $manifest = Get-Content "$app\.claude-plugin\marketplace.json" -Raw | ConvertFrom-Json
          if ($manifest.name -ne 'clavity-agy-autotrain') { throw "expected marketplace name clavity-agy-autotrain, got $($manifest.name)" }
          if ($manifest.plugins.Count -ne 1) { throw "expected 1 plugin in scoped manifest, got $($manifest.plugins.Count)" }
          if ($manifest.plugins[0].source -ne './plugins/agy-autotrain') { throw "unexpected plugin source $($manifest.plugins[0].source)" }
          if (-not (Test-Path "$app\plugins\agy-autotrain\skills\agy-curate\SKILL.md")) { throw "plugin content not staged" }

          # C6: pre-seed a fake growth.md and confirm a plain (keep-data) uninstall does NOT delete it.
          New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.clavity" | Out-Null
          Set-Content "$env:USERPROFILE\.clavity\golden-header.growth.md" "fake learned wisdom"
          $uninst = Get-ChildItem $app -Filter "unins*.exe" | Select-Object -First 1
          Start-Process $uninst.FullName -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait | Out-Null
          $deadline = (Get-Date).AddSeconds(30)
          while ((Test-Path $app) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
          if (-not (Test-Path "$env:USERPROFILE\.clavity\golden-header.growth.md")) { throw "C6 VIOLATION: growth.md was deleted by a keep-data uninstall" }
          "install/uninstall + namespace + C6 growth-ownership smoke PASSED"

      - name: Upload installer artifact
        uses: actions/upload-artifact@v4
        with:
          name: agy-autotrain-installer
          path: |
            agy-autotrain/dist/agy-autotrain-setup-*.exe
            agy-autotrain/dist/agy-autotrain-setup-*.exe.sha256
```

- [ ] **Test:** the workflow's own smoke step above; expected pass line:
      `install/uninstall + namespace + C6 growth-ownership smoke PASSED`.

### Task 3.3 — commonmemory installer (C1, C9)

**Files:**
- Create: `commonmemory/installer/commonmemory.iss`

- [ ] Create the installer (commonmemory owns no `~/.clavity` data, so it needs no growth-style
      keep/purge prompt — plain registration + deregistration only). Fresh `AppId` GUID:
      `4EA2EF84-6B61-482C-A3CE-5CC0135BB553`.

```pascal
; Inno Setup script for commonmemory (plugin-only member; no binary). Build with:
; ISCC.exe installer\commonmemory.iss
; Cohesive distribution model (docs/superpowers/specs/2026-07-11-cohesive-distribution-design.md):
; ships the commonmemory plugin folder + a scoped 1-entry marketplace.json, self-registering
; against each detected agent. Runtime dependency on the agentmemory MCP server is out of scope
; for this installer (be honest, do not auto-install it — matches the pre-cohesion add-on's UX).

#define AppName "commonmemory"
#define AppVersion "0.1.0"

[Setup]
AppId={{4EA2EF84-6B61-482C-A3CE-5CC0135BB553}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=clavity
LicenseFile=..\LICENSE
DefaultDirName={localappdata}\Programs\commonmemory
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=commonmemory-setup-{#AppVersion}
OutputDir=..\dist
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; O6: shared with all five member installers (defensive default — see ghidrust.iss's comment).
SetupMutex=ClavitySetupMutex

[Files]
Source: "marketplace.install.json"; DestDir: "{app}\.claude-plugin"; DestName: "marketplace.json"; Flags: ignoreversion
Source: "..\*"; DestDir: "{app}\plugins\commonmemory"; Flags: ignoreversion recursesubdirs createallsubdirs; \
  Excludes: "installer,dist,publish"

[Code]
#include "..\..\installer\_shared\plugin-registration.iss"

procedure CurStepChanged(CurStep: TSetupStep);
var
  RegisteredClaude, RegisteredAgy, AnyDetected, AnySucceeded: Boolean;
  RegReport: string;
begin
  if CurStep = ssPostInstall then
  begin
    RegisterMemberPlugin(ExpandConstant('{app}'), 'commonmemory', 'clavity-commonmemory',
      RegisteredClaude, RegisteredAgy, AnyDetected, AnySucceeded, RegReport);
    ReportRegistrationOutcome(AnyDetected, AnySucceeded, RegisteredClaude, RegisteredAgy, RegReport);
  end
  else if CurStep = ssDone then
    SuppressibleMsgBox('commonmemory was registered, but it needs the agentmemory MCP server to ' +
      'actually work. If you have not installed agentmemory yet, install it separately — until ' +
      'then the shared notebook stays inactive.', mbInformation, MB_OK, IDOK);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    DeregisterMemberPluginOnUninstall('commonmemory', 'clavity-commonmemory');
end;
```

- [ ] **Test (CI):** Task 3.4 adds the smoke assertions.

### Task 3.4 — `build-commonmemory.yml` (O4)

**Files:**
- Create: `.github/workflows/build-commonmemory.yml`

- [ ] Create the reusable build workflow (same shape as Task 3.2, member-specific paths):

```yaml
name: build-commonmemory

on:
  workflow_call:
    outputs:
      version:
        value: ${{ jobs.build.outputs.version }}
      sha:
        value: ${{ jobs.build.outputs.sha }}
      artifact-name:
        value: ${{ jobs.build.outputs.artifact-name }}
  workflow_dispatch:

jobs:
  build:
    runs-on: windows-latest
    defaults:
      run:
        working-directory: commonmemory
    outputs:
      version: ${{ steps.ver.outputs.version }}
      sha: ${{ steps.sha.outputs.sha }}
      artifact-name: commonmemory-installer
    steps:
      - uses: actions/checkout@v4

      - name: Record the built commit
        id: sha
        shell: bash
        run: echo "sha=$(git rev-parse HEAD)" >> "$GITHUB_OUTPUT"

      - name: Extract version from .iss
        id: ver
        shell: pwsh
        run: |
          $v = (Select-String -Path installer/commonmemory.iss -Pattern '#define AppVersion "([^"]+)"').Matches[0].Groups[1].Value
          "version=$v" | Out-File -FilePath $env:GITHUB_OUTPUT -Append
          "TOOL_VER=$v" | Out-File -FilePath $env:GITHUB_ENV -Append

      - name: Generate scoped marketplace.json (O3)
        shell: pwsh
        run: ../scripts/generate-scoped-manifest.ps1 -MemberName commonmemory -OutFile installer/marketplace.install.json

      - name: Install Inno Setup
        shell: pwsh
        run: choco install innosetup --no-progress -y

      - name: Build installer (ISCC)
        shell: pwsh
        run: |
          $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
          if (-not (Test-Path $iscc)) { throw "ISCC.exe not found at $iscc" }
          & $iscc installer/commonmemory.iss
          if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }
          $setup = "dist/commonmemory-setup-$env:TOOL_VER.exe"
          if (-not (Test-Path $setup)) { throw "$setup was not produced" }

      - name: Compute SHA-256 companion
        shell: pwsh
        run: |
          $name = "commonmemory-setup-$env:TOOL_VER.exe"
          $h = (Get-FileHash "dist/$name" -Algorithm SHA256).Hash.ToLower()
          "$h  $name" | Set-Content -Path "dist/$name.sha256" -Encoding ascii

      - name: Smoke — install/uninstall lifecycle + namespace
        timeout-minutes: 6
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $setup = "dist/commonmemory-setup-$env:TOOL_VER.exe"
          $app = "$env:LOCALAPPDATA\Programs\commonmemory"

          $p = Start-Process $setup -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait -PassThru
          if ($p.ExitCode -ne 0) { throw "install exit $($p.ExitCode)" }
          # Finding-5: re-run the SAME installer — idempotent upgrade (remove-then-add) must exit 0.
          $p2 = Start-Process $setup -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait -PassThru
          if ($p2.ExitCode -ne 0) { throw "re-run install exit $($p2.ExitCode) — idempotent upgrade must not abort" }
          if (-not (Test-Path "$app\.claude-plugin\marketplace.json")) { throw "marketplace.json not installed" }
          $manifest = Get-Content "$app\.claude-plugin\marketplace.json" -Raw | ConvertFrom-Json
          if ($manifest.name -ne 'clavity-commonmemory') { throw "expected marketplace name clavity-commonmemory, got $($manifest.name)" }
          if ($manifest.plugins.Count -ne 1) { throw "expected 1 plugin in scoped manifest, got $($manifest.plugins.Count)" }
          if (-not (Test-Path "$app\plugins\commonmemory\skills\commonmemory\SKILL.md")) { throw "plugin content not staged" }

          $uninst = Get-ChildItem $app -Filter "unins*.exe" | Select-Object -First 1
          Start-Process $uninst.FullName -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait | Out-Null
          $deadline = (Get-Date).AddSeconds(30)
          while ((Test-Path "$app\plugins") -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
          if (Test-Path "$app\plugins") { throw "uninstall did not remove staged plugin files within 30s" }
          "install/uninstall + namespace smoke PASSED"

      - name: Upload installer artifact
        uses: actions/upload-artifact@v4
        with:
          name: commonmemory-installer
          path: |
            commonmemory/dist/commonmemory-setup-*.exe
            commonmemory/dist/commonmemory-setup-*.exe.sha256
```

- [ ] **Test:** the workflow's own smoke step; expected pass line:
      `install/uninstall + namespace smoke PASSED`.

---

## Phase 4 — CI flips + umbrella release wiring + docs

### Task 4.1 — `build-dotnet.yml`: single-member manifest + C9/C6 assertions + delete the root manifest (C10)

**Files:**
- Modify: `.github/workflows/build-dotnet.yml`
- Delete: `.claude-plugin/marketplace.json`

**Ordering (Finding-2 fold):** the DELETE of `.claude-plugin/marketplace.json` lives HERE, not in
Task 1.1, so it lands atomically with the workflow re-point below. Until this task, `build-dotnet.yml`
still reads `../.claude-plugin/marketplace.json` (lines 65–75), so deleting it earlier would break
CI for the whole Phase-1-through-Phase-4 window. This task depends on Task 1.2 (the generator) and
Task 1.1 (`build/members.json`) already existing.

- [ ] Delete `.claude-plugin/marketplace.json` (its directory has no other file — confirmed by
      listing; the whole `.claude-plugin/` folder disappears with it). This is the C3 "local-only
      must be structural" fix: after this, `claude plugin marketplace add ckir/clavity` finds no
      addable manifest at the repo root.
- [ ] Replace the "Generate flat install manifest" step (lines 65–75) with a call to the Phase 1
      generator:

  Before:
  ```yaml
        - name: Generate flat install manifest (4 bundled plugins; EXCLUDE mutually-exclusive classic)
          shell: pwsh
          run: |
            $root = Get-Content ../.claude-plugin/marketplace.json -Raw | ConvertFrom-Json
            $bundled = $root.plugins | Where-Object { $_.name -ne 'clavity-classic' }
            foreach ($p in $bundled) { $p.source = "./plugins/$($p.name)" }
            $root.plugins = $bundled
            $root | ConvertTo-Json -Depth 10 | Set-Content installer/marketplace.install.json -Encoding utf8
            if ($bundled.Count -ne 4) { throw "expected 4 bundled plugins, got $($bundled.Count)" }
            if (($bundled | Where-Object { $_.source -notmatch '^\./plugins/' }).Count -ne 0) { throw "flat manifest has a non-flat source" }
            Write-Host "generated installer/marketplace.install.json with 4 flat sources (classic excluded)"
  ```
  After:
  ```yaml
        - name: Generate scoped marketplace.json (O3, single member)
          shell: pwsh
          run: ../scripts/generate-scoped-manifest.ps1 -MemberName clavity-dotnet -OutFile installer/marketplace.install.json
  ```

- [ ] Replace the bundled-sibling smoke assertions (lines 108–116) with single-member + C9 + C6
      checks:

  Before:
  ```yaml
            if (-not (Test-Path "$app\.claude-plugin\marketplace.json")) { throw "marketplace.json not installed" }
            $installedManifest = Get-Content "$app\.claude-plugin\marketplace.json" -Raw | ConvertFrom-Json
            if ($installedManifest.plugins.Count -ne 4) { throw "installed marketplace.json has $($installedManifest.plugins.Count) plugins, expected 4 (classic excluded)" }
            if (($installedManifest.plugins | Where-Object { $_.source -notmatch '^\./plugins/' }).Count -ne 0) { throw "installed marketplace.json has a non-flat plugin source" }
            if (-not (Test-Path "$app\plugins\clavity-dotnet")) { throw "plugins\clavity-dotnet not installed" }
            if (-not (Test-Path "$app\plugins\agy-autotrain")) { throw "plugins\agy-autotrain (add-on) not shipped" }
            if (-not (Test-Path "$app\plugins\commonmemory")) { throw "plugins\commonmemory (add-on) not shipped" }
            if (-not (Test-Path "$app\plugins\ghidrust")) { throw "plugins\ghidrust not shipped (bundled marketplace ./plugins/ghidrust entry would dangle)" }
  ```
  After:
  ```yaml
            if (-not (Test-Path "$app\.claude-plugin\marketplace.json")) { throw "marketplace.json not installed" }
            $installedManifest = Get-Content "$app\.claude-plugin\marketplace.json" -Raw | ConvertFrom-Json
            if ($installedManifest.name -ne 'clavity-dotnet') { throw "expected marketplace name clavity-dotnet (C9), got $($installedManifest.name)" }
            if ($installedManifest.plugins.Count -ne 1) { throw "installed marketplace.json has $($installedManifest.plugins.Count) plugins, expected 1 (C10 teardown)" }
            if ($installedManifest.plugins[0].source -ne './plugins/clavity-dotnet') { throw "unexpected plugin source $($installedManifest.plugins[0].source)" }
            if (-not (Test-Path "$app\plugins\clavity-dotnet")) { throw "plugins\clavity-dotnet not installed" }
            if (Test-Path "$app\plugins\agy-autotrain") { throw "C10 VIOLATION: sibling agy-autotrain still bundled" }
            if (Test-Path "$app\plugins\commonmemory") { throw "C10 VIOLATION: sibling commonmemory still bundled" }
            if (Test-Path "$app\plugins\ghidrust") { throw "C10 VIOLATION: sibling ghidrust still bundled" }
  ```

- [ ] Add a new smoke step after the existing "Smoke — silent install then uninstall" step,
      asserting Acceptance #10 (`growth.md` survival) and Acceptance #8 (idempotent re-run):

```yaml
      - name: Smoke — C6 growth.md survives a keep-data uninstall + C1 idempotent re-run
        timeout-minutes: 6
        continue-on-error: true   # informational, matching the sibling smoke step's policy
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $setup = "dist/clavity-dotnet-setup-$env:CLAVITY_VER.exe"
          $app = "$env:LOCALAPPDATA\Programs\clavity-dotnet"

          Write-Host "[smoke] first install..."
          $p1 = Start-Process $setup -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait -PassThru
          if ($p1.ExitCode -ne 0) { throw "first install exited $($p1.ExitCode)" }

          Write-Host "[smoke] re-running the SAME installer over the existing install (Acceptance #8)..."
          $p2 = Start-Process $setup -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait -PassThru
          if ($p2.ExitCode -ne 0) { throw "re-run install exited $($p2.ExitCode) — idempotent upgrade must not abort" }
          if (-not (Test-Path "$app\clavity-ls.exe")) { throw "clavity-ls.exe missing after re-run install" }

          New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.clavity" | Out-Null
          Set-Content "$env:USERPROFILE\.clavity\golden-header.growth.md" "fake learned wisdom"
          $uninst = Get-ChildItem "$app" -Filter "unins*.exe" | Select-Object -First 1
          Start-Process $uninst.FullName -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait | Out-Null
          Start-Sleep -Seconds 2
          if (-not (Test-Path "$env:USERPROFILE\.clavity\golden-header.growth.md")) { throw "C6 VIOLATION: growth.md deleted by a keep-data driver uninstall" }
          Write-Host "C6 growth-ownership + C1 idempotent-upgrade smoke PASSED"
```

- [ ] **Test:** the two rewritten steps above run in CI on the next `build-dotnet` invocation (push
      to `clavity-dotnet/**` or `workflow_dispatch`). Expected pass lines: no thrown error in the
      rewritten "Smoke — silent install then uninstall" step, plus
      `C6 growth-ownership + C1 idempotent-upgrade smoke PASSED`.

### Task 4.2 — `build-classic.yml`: add scoped-manifest generation + registration/C6 smoke

**Files:**
- Modify: `.github/workflows/build-classic.yml`

- [ ] Insert a scoped-manifest generation step right before "Build installer (ISCC)" (the `.iss`
      copies this file at build time, so it must exist before ISCC runs):

```yaml
      - name: Generate scoped marketplace.json (O3, single member)
        shell: pwsh
        run: ../scripts/generate-scoped-manifest.ps1 -MemberName clavity-classic -OutFile installer/marketplace.install.json
```

- [ ] Extend the existing BLOCKING "Smoke — install/uninstall lifecycle" step (today asserts
      `clavity.exe`, bridge `SKILL.md`, the seed) with the new registration + C6 assertions —
      insert right after the existing `$bundled = Get-Content ...` seed-match check and before the
      ARP-key check:

```yaml
          if (-not (Test-Path "$app\.claude-plugin\marketplace.json")) { throw "marketplace.json not installed" }
          $manifest = Get-Content "$app\.claude-plugin\marketplace.json" -Raw | ConvertFrom-Json
          if ($manifest.name -ne 'clavity-classic') { throw "expected marketplace name clavity-classic (C9), got $($manifest.name)" }
          if ($manifest.plugins.Count -ne 1) { throw "expected 1 plugin in scoped manifest, got $($manifest.plugins.Count)" }
          if ($manifest.plugins[0].source -ne './plugins/clavity-classic') { throw "unexpected plugin source $($manifest.plugins[0].source)" }
          if (-not (Test-Path "$app\plugins\clavity-classic")) { throw "plugins\clavity-classic not staged" }

          # C6: pre-seed a fake growth.md and confirm a keep-data uninstall does NOT touch it.
          Set-Content "$env:USERPROFILE\.clavity\golden-header.growth.md" "fake learned wisdom"
```

  and, right after the existing uninstall `Start-Process` line in that same step, add:

```yaml
          if (-not (Test-Path "$env:USERPROFILE\.clavity\golden-header.growth.md")) { throw "C6 VIOLATION: growth.md deleted by a keep-data driver uninstall" }
```

- [ ] **Add the install-twice idempotency assertion (Finding-5 fold).** Insert immediately after
      the FIRST install's `if ($p.ExitCode -ne 0) { throw "install exit $($p.ExitCode)" }` line
      and before the `clavity.exe`/`SKILL.md` checks, so the re-run exercises the new remove-then-add
      `[Code]` path (proves it re-runs cleanly, not aborts):

```yaml
          # Finding-5: re-run the SAME installer over the fresh install — idempotent upgrade must exit 0.
          $p2 = Start-Process $setup -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART","/TASKS=addtopath,install_bridge" -Wait -PassThru
          if ($p2.ExitCode -ne 0) { throw "re-run install exit $($p2.ExitCode) — idempotent upgrade must not abort" }
          if (-not (Test-Path "$app\.claude-plugin\marketplace.json")) { throw "scoped manifest missing after re-run install" }
```

- [ ] **Test:** this step is already BLOCKING (no `continue-on-error`) — a red run here fails the
      job. Expected pass line: `lifecycle smoke PASSED` (unchanged, plus no thrown error from the
      new assertions above it).

### Task 4.3 — `build-ghidrust.yml`: add plugin staging + first-ever install/uninstall smoke

**Files:**
- Modify: `.github/workflows/build-ghidrust.yml`

- [ ] Replace the "Two-channel delivery" comment (lines 81–82) and insert a scoped-manifest
      generation step before "Build installer (ISCC)":

  Before:
  ```yaml
        # Two-channel delivery: the installer ships ONLY the binary; the plugin is marketplace-delivered on
        # main. No plugins/ staging here — D7 cross-branch bundling does not apply (see the onboarding spec).
  ```
  After:
  ```yaml
        - name: Generate scoped marketplace.json (O3, single member)
          shell: pwsh
          run: ../scripts/generate-scoped-manifest.ps1 -MemberName ghidrust -OutFile installer/marketplace.install.json

        # Cohesive distribution model: the installer now ships its own plugin + a scoped local
        # marketplace, self-registering it (supersedes the old "two-channel" remote-marketplace note).
  ```

- [ ] Add ghidrust's first-ever install/uninstall smoke test (Step 0 finding — none exists today),
      inserted after "Compute SHA-256 companion" and before "Upload installer artifact":

```yaml
      - name: Smoke — install/uninstall lifecycle + namespace (BLOCKING — first-ever for ghidrust)
        timeout-minutes: 6
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $setup = "dist/ghidrust-setup-$env:TOOL_VER.exe"
          $app = "$env:LOCALAPPDATA\Programs\ghidrust"

          $p = Start-Process $setup -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait -PassThru
          if ($p.ExitCode -ne 0) { throw "install exit $($p.ExitCode)" }
          # Finding-5: re-run the SAME installer — idempotent upgrade (remove-then-add) must exit 0.
          $p2 = Start-Process $setup -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait -PassThru
          if ($p2.ExitCode -ne 0) { throw "re-run install exit $($p2.ExitCode) — idempotent upgrade must not abort" }
          if (-not (Test-Path "$app\ghidrust.exe")) { throw "ghidrust.exe missing" }
          if (-not (Test-Path "$app\.claude-plugin\marketplace.json")) { throw "marketplace.json not installed" }
          $manifest = Get-Content "$app\.claude-plugin\marketplace.json" -Raw | ConvertFrom-Json
          if ($manifest.name -ne 'clavity-ghidrust') { throw "expected marketplace name clavity-ghidrust (C9), got $($manifest.name)" }
          if ($manifest.plugins.Count -ne 1) { throw "expected 1 plugin, got $($manifest.plugins.Count)" }
          if (-not (Test-Path "$app\plugins\ghidrust")) { throw "plugins\ghidrust not staged" }
          $userPath = (Get-ItemProperty "HKCU:\Environment" -Name Path -ErrorAction SilentlyContinue).Path
          if ($userPath -notlike "*$app*") { throw "PATH entry not added after install" }

          $uninst = Get-ChildItem $app -Filter "unins*.exe" | Select-Object -First 1
          Start-Process $uninst.FullName -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait | Out-Null
          $deadline = (Get-Date).AddSeconds(30)
          while ((Test-Path "$app\ghidrust.exe") -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
          if (Test-Path "$app\ghidrust.exe") { throw "uninstall did not complete within 30s" }
          $userPath2 = (Get-ItemProperty "HKCU:\Environment" -Name Path -ErrorAction SilentlyContinue).Path
          if ($userPath2 -like "*$app*") { throw "PATH entry not removed after uninstall" }
          "install/uninstall + namespace smoke PASSED"
```

- [ ] **Test:** this new step is BLOCKING (consistent with ghidrust's existing e2e-ghidrust
      posture, per C8 "ghidrust keeps its BLOCKING live gate" — the plan extends that same
      no-tolerance posture to this new smoke). Expected pass line:
      `install/uninstall + namespace smoke PASSED`.

### Task 4.4 — `umbrella-release.yml`: add the two new members + a decoupled per-member republish workflow (C8, Acceptance #1, #11)

**Files:**
- Modify: `.github/workflows/umbrella-release.yml`
- Create: `.github/workflows/republish-member.yml`

- [ ] Add the two new build jobs to `umbrella-release.yml` and extend `publish`'s `needs:` (still
      fully atomic for a FULL cut — C8's "all-or-nothing" language applies only to a full umbrella
      build; the NEW decoupled path is the separate workflow below):

  Before (jobs 29–47):
  ```yaml
  jobs:
    dotnet:
      uses: ./.github/workflows/build-dotnet.yml

    classic:
      uses: ./.github/workflows/build-classic.yml

    ghidrust:
      uses: ./.github/workflows/build-ghidrust.yml

    e2e-ghidrust:
      needs: [ghidrust]
      uses: ./.github/workflows/e2e-ghidrust.yml

    publish:
      needs: [dotnet, classic, ghidrust, e2e-ghidrust]
      runs-on: ubuntu-latest
  ```
  After:
  ```yaml
  jobs:
    dotnet:
      uses: ./.github/workflows/build-dotnet.yml

    classic:
      uses: ./.github/workflows/build-classic.yml

    ghidrust:
      uses: ./.github/workflows/build-ghidrust.yml

    e2e-ghidrust:
      needs: [ghidrust]
      uses: ./.github/workflows/e2e-ghidrust.yml

    agy-autotrain:
      uses: ./.github/workflows/build-agy-autotrain.yml

    commonmemory:
      uses: ./.github/workflows/build-commonmemory.yml

    publish:
      needs: [dotnet, classic, ghidrust, e2e-ghidrust, agy-autotrain, commonmemory]
      runs-on: ubuntu-latest
  ```

- [ ] Extend the `publish` job's artifact downloads, `body.md` table, and `files:` list to 5
      members / 10 assets:

  Before (the download steps + body.md + files):
  ```yaml
        - name: Download dotnet installer
          uses: actions/download-artifact@v4
          with:
            name: ${{ needs.dotnet.outputs.artifact-name }}
            path: dist-dotnet

        - name: Download classic installer
          uses: actions/download-artifact@v4
          with:
            name: ${{ needs.classic.outputs.artifact-name }}
            path: dist-classic

        - name: Download ghidrust installer
          uses: actions/download-artifact@v4
          with:
            name: ${{ needs.ghidrust.outputs.artifact-name }}
            path: dist-ghidrust
  ```
  After (add two more download steps, same shape):
  ```yaml
        - name: Download dotnet installer
          uses: actions/download-artifact@v4
          with:
            name: ${{ needs.dotnet.outputs.artifact-name }}
            path: dist-dotnet

        - name: Download classic installer
          uses: actions/download-artifact@v4
          with:
            name: ${{ needs.classic.outputs.artifact-name }}
            path: dist-classic

        - name: Download ghidrust installer
          uses: actions/download-artifact@v4
          with:
            name: ${{ needs.ghidrust.outputs.artifact-name }}
            path: dist-ghidrust

        - name: Download agy-autotrain installer
          uses: actions/download-artifact@v4
          with:
            name: ${{ needs.agy-autotrain.outputs.artifact-name }}
            path: dist-agy-autotrain

        - name: Download commonmemory installer
          uses: actions/download-artifact@v4
          with:
            name: ${{ needs.commonmemory.outputs.artifact-name }}
            path: dist-commonmemory
  ```

  Before (the `body.md` heredoc + `cp` lines):
  ```yaml
            mkdir -p out
            cp dist-dotnet/* out/
            cp dist-classic/* out/
            cp dist-ghidrust/* out/
            echo "assets in release:"; ls -1 out
            cat > body.md <<EOF
            # clavity $TAG

            | component | version | source |
            |-----------|---------|--------|
            | clavity-dotnet  | ${{ needs.dotnet.outputs.version }}  | main@${{ needs.dotnet.outputs.sha }} |
            | clavity-classic | ${{ needs.classic.outputs.version }} | main@${{ needs.classic.outputs.sha }} |
            | ghidrust        | ${{ needs.ghidrust.outputs.version }} | main@${{ needs.ghidrust.outputs.sha }} |

            **clavity-dotnet** and **clavity-classic** are the two **mutually exclusive** clavity variants — install
            ONE. **ghidrust** is a separate tool (install alongside either). Installers are **unsigned** (Windows
            SmartScreen may warn on first run: *More info -> Run anyway*). Verify each \`.sha256\` against its \`.exe\`.
            EOF
  ```
  After (Acceptance #1's palette notes table — what each installer gives you + when you'd want it):
  ```yaml
            mkdir -p out
            cp dist-dotnet/* out/
            cp dist-classic/* out/
            cp dist-ghidrust/* out/
            cp dist-agy-autotrain/* out/
            cp dist-commonmemory/* out/
            echo "assets in release:"; ls -1 out
            cat > body.md <<EOF
            # clavity $TAG

            Five standalone installers. Each does exactly ONE member and references no other —
            grab whichever you want from this one page.

            | installer | version | what it gives you | when you'd want it |
            |-----------|---------|--------------------|--------------------|
            | clavity-dotnet-setup      | ${{ needs.dotnet.outputs.version }}        | Claude Code <-> agy pairing (Primary, .NET host)  | Default choice for pairing Claude with agy |
            | clavity-classic-setup     | ${{ needs.classic.outputs.version }}       | Claude Code <-> agy pairing (Failover, Rust host) | Prefer the original Rust host, or dotnet is unavailable |
            | ghidrust-setup            | ${{ needs.ghidrust.outputs.version }}      | Headless Ghidra reverse-engineering over MCP      | You reverse-engineer binaries and want AI-assisted decompile/rename |
            | agy-autotrain-setup       | ${{ needs.agy-autotrain.outputs.version }} | agy auto-training loop (capture -> curate -> golden-header) | You already run a clavity driver and want it to keep learning your project |
            | commonmemory-setup        | ${{ needs.commonmemory.outputs.version }}  | Shared Claude<->agy notebook over agentmemory     | You run the agentmemory MCP server and want cross-agent shared facts |

            **clavity-dotnet** and **clavity-classic** are **mutually exclusive** — install ONE, not both.
            The other three install alongside either (or standalone). Installers are **unsigned** (Windows
            SmartScreen may warn on first run: *More info -> Run anyway*). Verify each \`.sha256\` against its \`.exe\`.
            There is **no** remote marketplace channel — every plugin ships locally inside its own installer.
            EOF
  ```

  Before (`files:` list in the "Publish ONE clavity release" step):
  ```yaml
            files: |
              out/clavity-dotnet-setup-*.exe
              out/clavity-dotnet-setup-*.exe.sha256
              out/clavity-classic-setup-*.exe
              out/clavity-classic-setup-*.exe.sha256
              out/ghidrust-setup-*.exe
              out/ghidrust-setup-*.exe.sha256
  ```
  After:
  ```yaml
            files: |
              out/clavity-dotnet-setup-*.exe
              out/clavity-dotnet-setup-*.exe.sha256
              out/clavity-classic-setup-*.exe
              out/clavity-classic-setup-*.exe.sha256
              out/ghidrust-setup-*.exe
              out/ghidrust-setup-*.exe.sha256
              out/agy-autotrain-setup-*.exe
              out/agy-autotrain-setup-*.exe.sha256
              out/commonmemory-setup-*.exe
              out/commonmemory-setup-*.exe.sha256
  ```

- [ ] Create the decoupled per-member republish workflow (Acceptance #11 — a single member
      rebuildable/republishable onto the EXISTING `clavity-v<N>` release without any sibling's
      build/gate passing):

```yaml
name: republish-member

# Decoupled per-member republish (Acceptance #11 / C8 "Release coupling — decoupled by design"):
# rebuild ONE member and republish its 2 assets onto an EXISTING clavity-v<N> release, without any
# sibling's build/gate passing. Use this for a hotfix on one member after umbrella-release.yml
# already published that tag (e.g. a flaky e2e-ghidrust network fetch must not block an unrelated
# dotnet-only fix from reaching the SAME release page).
on:
  workflow_dispatch:
    inputs:
      tag:
        description: 'Existing clavity-v<N> release tag to republish onto (e.g. clavity-v3) — REQUIRED.'
        required: true
        type: string
      member:
        description: 'Which member to rebuild and republish.'
        required: true
        type: choice
        options:
          - dotnet
          - classic
          - ghidrust
          - agy-autotrain
          - commonmemory

permissions:
  contents: write

jobs:
  dotnet:
    if: inputs.member == 'dotnet'
    uses: ./.github/workflows/build-dotnet.yml

  classic:
    if: inputs.member == 'classic'
    uses: ./.github/workflows/build-classic.yml

  ghidrust:
    if: inputs.member == 'ghidrust'
    uses: ./.github/workflows/build-ghidrust.yml

  e2e-ghidrust:
    # ghidrust keeps its BLOCKING live gate (C8) — but ONLY for a ghidrust republish; it never
    # runs, and so never blocks, a dotnet/classic/agy-autotrain/commonmemory republish.
    if: inputs.member == 'ghidrust'
    needs: [ghidrust]
    uses: ./.github/workflows/e2e-ghidrust.yml

  agy-autotrain:
    if: inputs.member == 'agy-autotrain'
    uses: ./.github/workflows/build-agy-autotrain.yml

  commonmemory:
    if: inputs.member == 'commonmemory'
    uses: ./.github/workflows/build-commonmemory.yml

  publish:
    # Finding-3 fold: GitHub Actions SKIPS a downstream job by default when ANY of its `needs`
    # jobs was skipped — so with 5 of 6 build jobs skipped (only the selected member ran), the
    # default condition would skip `publish` entirely and NOTHING would republish. The explicit
    # `if:` below overrides that: run as long as the job wasn't cancelled and NONE of the needs
    # actually FAILED (a skipped need is tolerated; a real failure of the one member that ran is
    # not). Only the selected member's 2 assets are downloaded/published (see the `member` switch
    # in the steps), so republishing one member never touches a sibling's assets.
    needs: [dotnet, classic, ghidrust, e2e-ghidrust, agy-autotrain, commonmemory]
    if: ${{ always() && !cancelled() && !contains(needs.*.result, 'failure') }}
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: Determine which build job ran + its artifact name
        id: which
        shell: bash
        run: |
          case "${{ inputs.member }}" in
            dotnet)        echo "artifact=${{ needs.dotnet.outputs.artifact-name }}" >> "$GITHUB_OUTPUT" ;;
            classic)       echo "artifact=${{ needs.classic.outputs.artifact-name }}" >> "$GITHUB_OUTPUT" ;;
            ghidrust)      echo "artifact=${{ needs.ghidrust.outputs.artifact-name }}" >> "$GITHUB_OUTPUT" ;;
            agy-autotrain) echo "artifact=${{ needs.agy-autotrain.outputs.artifact-name }}" >> "$GITHUB_OUTPUT" ;;
            commonmemory)  echo "artifact=${{ needs.commonmemory.outputs.artifact-name }}" >> "$GITHUB_OUTPUT" ;;
          esac

      - name: Download the rebuilt installer
        uses: actions/download-artifact@v4
        with:
          name: ${{ steps.which.outputs.artifact }}
          path: dist-member

      - name: Republish onto the existing release (adds/overwrites only this member's 2 assets)
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ inputs.tag }}
          name: ${{ inputs.tag }}
          files: |
            dist-member/*
```

- [ ] **Test (CI):** `umbrella-release.yml`'s own next tag-push run (owner-gated, push-triggered —
      not a task this plan can auto-run) is the full-cut test; `republish-member.yml` is exercised
      via `workflow_dispatch` (owner-run, dispatch inputs `tag=<existing clavity-v<N>>`,
      `member=agy-autotrain` as the first live check, since it has the shortest, lowest-risk build).
      Expected pass line for `republish-member`: the `publish` job succeeds and the release page
      shows the member's 2 assets updated without any other job having run.

### Task 4.5 — `CONTRIBUTING.md`: fix the stale "Releasing (umbrella)" topology section (O5)

**Files:**
- Modify: `CONTRIBUTING.md`

**O5 resolution (explicit call, backed by evidence from Step 0):** keep `clavity-dotnet` on
`main`. The existing text's premise — that `classic`/`ghidrust` live on their own branches while
`dotnet` is the `main`-resident "aggregator" — is **already false today**: `build-classic.yml` and
`build-ghidrust.yml` both do a naked `actions/checkout@v4` (no ref/branch pin) and `cd` into their
product subfolder, i.e. all three binary members (and both plugin-only members) already live on
`main` in the same monorepo tree (confirmed by this plan's Step 0 read and by
`project_monorepo-consolidation_execution` history). There is no branch-per-tool asymmetry left for
`dotnet` to "match" by moving — the monorepo consolidation already achieved full symmetry. Moving
`dotnet` to its own branch now would be a **regression** (reintroducing exactly the branch-per-tool
split the consolidation removed), not a fix.

- [ ] Replace the stale paragraph (lines 91–116) describing bundling + branch asymmetry + the
      4-plugin flat manifest with an accurate description of the five-standalone-installer model:

  Before (91–116, full text — see Step 0 read above for the verbatim original):
  ```
  ## Releasing (umbrella)

  Releases are produced **only** by pushing a serial umbrella tag `clavity-v<N>` (e.g. `clavity-v1`,
  `clavity-v2`), which triggers `.github/workflows/umbrella-release.yml`. That one release, named
  `clavity`, is the **canonical** download and bundles every tool's version-stamped installer, each with a
  `.sha256`: `clavity-dotnet-setup-<ver>.exe`, `clavity-classic-setup-<ver>.exe`, and
  `ghidrust-setup-<ver>.exe` (ghidrust is gated by its live-E2E before publish, so a broken ghidrust blocks
  the whole release). The standalone `release-ghidrust.yml` (`ghidrust-v<N>`) remains a **dispatch-only**
  escape hatch for a ghidrust patch without a full clavity cut.

  **Repo topology (why the asymmetry):** `main` houses the orchestration + the flagship **aggregator**
  (`dotnet` — its installer bundles the shared `marketplace.json` + all plugin dirs, which are umbrella-scoped
  and live on `main`). Independent binaries (`classic`, `ghidrust`) live on their own branches to prevent
  cross-contamination, and are SHA-pinned at cut time via `resolve-*`. `dotnet` needs no pin — the
  `clavity-v<N>` tag is on `main`, so it already pins `dotnet` deterministically.

  Bump each variant's version in its own `installer/*.iss` `#define AppVersion` (dotnet on `main`; classic
  on the `clavity-classic` branch, kept in sync with `Cargo.toml` + `agy-mcp-bridge/pyproject.toml`) before
  cutting. To pin an exact classic commit, run the workflow via `workflow_dispatch` supplying the required
  `tag` (the serial `clavity-v<N>`) and the `classic_ref` SHA (a dispatch has no triggering tag, so `tag`
  is mandatory there).

  **Deprecated tags (no-ops):** the legacy `v*`, `clavity-dotnet-v*`, and `clavity-classic-v*` tags no
  longer trigger anything — the per-variant release workflows were retired. Pushing one produces **no
  release** (a silent "ghost" tag). The historical per-variant releases and their tags are kept as frozen
  history.
  ```
  After:
  ```
  ## Releasing (umbrella)

  Releases are produced **only** by pushing a serial umbrella tag `clavity-v<N>` (e.g. `clavity-v1`,
  `clavity-v2`), which triggers `.github/workflows/umbrella-release.yml`. That one release, named
  `clavity`, is the **canonical catalog page** for five INDEPENDENT installers (cohesive-distribution
  model, `docs/superpowers/specs/2026-07-11-cohesive-distribution-design.md`): `clavity-dotnet-setup`,
  `clavity-classic-setup`, `ghidrust-setup`, `agy-autotrain-setup`, `commonmemory-setup` — each with its
  own `.sha256`. Each installer does exactly one member; none bundles or downloads another (there is no
  live remote marketplace channel). ghidrust is gated by its live-E2E before publish, so a broken ghidrust
  blocks a **full** umbrella cut — but NOT a single-member hotfix: see "Republishing one member" below.

  **Repo topology:** all five members live on `main` in this monorepo (one top-level folder each) — there
  is no branch-per-tool split. `main` also houses the orchestration (`umbrella-release.yml` +
  `build-<member>.yml` per member). A `clavity-v<N>` tag on `main` deterministically pins every member.

  Bump each member's version in its own `installer/*.iss` `#define AppVersion` (all five on `main`;
  classic's is additionally kept in sync with `Cargo.toml` + `agy-mcp-bridge/pyproject.toml`) before
  cutting.

  **Republishing one member (Acceptance #11):** `republish-member.yml` (`workflow_dispatch`, inputs
  `tag=<existing clavity-v<N>>` + `member=<one of the five>`) rebuilds ONE member and republishes its 2
  assets onto an already-published `clavity-v<N>` release, without any sibling's build or gate (including
  ghidrust's live-E2E) running at all — a decoupled hotfix path, not a second release lineage.

  **Deprecated tags (no-ops):** the legacy `v*`, `clavity-dotnet-v*`, and `clavity-classic-v*` tags no
  longer trigger anything — the per-variant release workflows were retired. Pushing one produces **no
  release** (a silent "ghost" tag). The historical per-variant releases and their tags are kept as frozen
  history.
  ```

- [ ] **Test:** documentation-only; no CI gate. Verify by reading the rendered section back and
      confirming it matches Task 4.4's actual workflow shapes (member names, job names, inputs).

### Task 4.6 — `README.md` palette fix + `docs/hosting-a-tool.md` supersede notice (C3, C8)

**Files:**
- Modify: `README.md`
- Modify: `docs/hosting-a-tool.md`

- [ ] `README.md`: replace the stale "one installer with checkboxes" framing (lines 22–29):

  Before:
  ```
  - **clavity-dotnet** / **clavity-classic** — two variants that pair [Claude Code](https://claude.com/claude-code)
    with [Antigravity (`agy`)](https://antigravity.google). See [clavity-dotnet/README.md](clavity-dotnet/README.md)
    for install & usage (the installer lets you choose the **.NET** (Primary) or **Classic** (Failover)
    host variant, and opt in to `agy-autotrain` / `commonmemory` extras).
  - **ghidrust** — drives a persistent headless Ghidra JVM: 19 reverse-engineering tools over MCP
    (attach + decompile + durable edits). See [ghidrust/README.md](ghidrust/README.md).
  - **agy-autotrain** / **commonmemory** — plugin-only add-ons (no standalone build); installed alongside
    clavity via the umbrella installer.
  ```
  After:
  ```
  - **clavity-dotnet** / **clavity-classic** — two **mutually exclusive** variants that pair
    [Claude Code](https://claude.com/claude-code) with [Antigravity (`agy`)](https://antigravity.google);
    install ONE, via its OWN standalone installer (**.NET** Primary or **Classic** Failover — see
    [clavity-dotnet/README.md](clavity-dotnet/README.md)).
  - **ghidrust** — drives a persistent headless Ghidra JVM: 19 reverse-engineering tools over MCP
    (attach + decompile + durable edits), via its own standalone installer. See
    [ghidrust/README.md](ghidrust/README.md).
  - **agy-autotrain** / **commonmemory** — plugin-only add-ons, each with its OWN standalone installer
    (no binary; no bundling with any other member). `agy-autotrain` needs a clavity driver installed to
    have somewhere to inject its learned header (a non-blocking runtime warning otherwise); `commonmemory`
    needs the `agentmemory` MCP server to be useful.

  Every installer is independent — grab exactly the ones you want from the same
  [release page](../../releases). There is **no** live remote marketplace; every plugin ships locally
  inside its own installer.
  ```

- [ ] `docs/hosting-a-tool.md`: add a supersede notice at the top (this doc's branch-per-tool +
      remote-marketplace-entry onboarding playbook is now superseded by the cohesive-distribution
      model for **packaging/distribution** — this plan does not rewrite the whole playbook, which
      also covers non-distribution onboarding steps like ROADMAP/README indexing that remain
      valid; flagged fully in the self-audit below):

```markdown
> **Superseded (2026-07-11) for packaging/distribution:** the branch-per-tool split, the
> repo-root `.claude-plugin/marketplace.json` entry (step 6 below), and the per-tool remote
> marketplace delivery this playbook describes are replaced by the cohesive distribution model —
> see `docs/superpowers/specs/2026-07-11-cohesive-distribution-design.md`. A new tool now gets its
> own standalone installer (self-registering a local scoped marketplace, C1/C9) built from `main`,
> not a `plugins/<tool-id>/` entry in a repo-root addable manifest. This file's non-distribution
> guidance (ROADMAP/README indexing, `*.template` skeletons, tag-namespace protection) still
> applies; its Phase B step 6 ("Add one entry to `.claude-plugin/marketplace.json`") does not — that
> file no longer exists at the repo root (relocated to the non-addable `build/members.json`).
```

- [ ] **Test:** documentation-only; no CI gate.

---

## Exhaustiveness self-audit

### 1. Every spec Component → implementing task(s)

| Component | Implemented by |
|---|---|
| C1 — plugin as universal packaging unit; installer-local registration; idempotency; per-agent semantics; install-time rollback; scoped-manifest path/source contract; upgrade hygiene; concurrent installs | Task 1.4 (shared include), 2.1/2.2 (dotnet C#), 2.3/2.4/2.5 (registration wiring), 3.1/3.3 (new installers) |
| C2 — binaries embedded, not downloaded | Already true for dotnet/classic/ghidrust today (unchanged by this plan — no task needed; confirmed no download/opt-in mechanism exists in any `.iss` read in Step 0) |
| C3 — local-only, structural (non-addable build source) | Task 1.1 (relocate to `build/members.json`), Task 4.6 (remove advertising language) |
| C4 — golden-header seed as installer payload, `-LiteralPath` everywhere | Task 1.5 (shared `SeedGoldenHeader`), 2.3/2.4 (adopt it) |
| C5 — mutual exclusion (dotnet XOR classic) | Already implemented (`StemOnPath`/`DotnetArpPresent`, unchanged) — Task 1.4 relocates `StemOnPath` into the shared include as a pure move, preserving behavior |
| C6 — uninstall robustness; no dangling marketplace; per-file `~/.clavity` ownership | Task 1.4 (`marketplace remove` + `DeregisterMemberPluginOnUninstall`), 1.5 (`BackupDataFile`), 2.1 (C# marketplace-remove), 2.3/2.4 (fix the `growth.md` bug), 3.1 (agy-autotrain's own growth.md keep/purge) |
| C7 — dependency blindness is runtime-only | **Already implemented** (`agy-autotrain/skills/agy-curate/SKILL.md:91-92`) — confirmed present in Step 0; no task needed |
| C8 — umbrella release wiring; decoupled per-member republish | Task 4.4 (`umbrella-release.yml` 5-member extension + `republish-member.yml`) |
| C9 — unique marketplace name per installer | Task 1.1 (`marketplaceName` field), 1.2 (generator rewrites `name`), 2.1 (dotnet C# const), 2.4/2.5/3.1/3.3 (Pascal literals) |
| C10 — migration/teardown of the bundled model | Task 1.1 (relocate manifest), 2.3 (dotnet `[Files]`/`[Tasks]`/`InstallAddon` removal), 3.1/3.3 (new installers), 4.1 (build-dotnet.yml flip) |

### 2. Every Acceptance item → verifying task(s)

| # | Acceptance | Verified by |
|---|---|---|
| 1 | 5 standalone installers + palette table on the release page | Task 4.4 (body.md palette table) |
| 2 | local scoped marketplace, unique name, no network, PATH for binaries | Task 4.1/4.2/4.3/3.2/3.4 smoke assertions (manifest `name`/`source`, PATH check) |
| 3 | no addable repo-root manifest; local-only structural | Task 1.1 (relocation) + owner manual check noted there |
| 4 | uninstall deregisters + removes marketplace entry; failed install rolls back | Task 1.4 (`DeregisterMemberPluginOnUninstall`, `RollbackMemberPlugin`), 4.1/4.2/4.3/3.2/3.4 uninstall smoke steps |
| 5 | dotnet/classic mutual exclusion retained | Unchanged code, existing `build-dotnet.yml` "Smoke — mutual-exclusion refusal" step (not modified by this plan) + `build-classic.yml`'s equivalent |
| 6 | seed survives `[`/`]`/`'` in profile path; agy-autotrain warns non-blocking without a driver | Task 1.5 (`-LiteralPath`), C7 already-implemented (Step 0) |
| 7 | 5 distinct marketplace names, CI-asserted | Task 1.3 (`validate-members.yml`) |
| 8 | re-running an installer upgrades in place (idempotent) | Task 2.1 (C# remove-then-add) + Task 1.4 (Inno remove-then-add) — idempotency is STRUCTURAL, no output heuristic (Finding-4); install-twice smoke asserted for ALL FIVE members: Task 4.1 (dotnet), 4.2 (classic), 4.3 (ghidrust), 3.2 (agy-autotrain), 3.4 (commonmemory) (Finding-5) |
| 9 | per-agent independent registration; partial failure reported not silently dropped; rollback per-agent-scoped, exception-safe | Task 2.2 (`CliRouter.cs` OR-semantics), Task 1.4 (`ReportRegistrationOutcome`, `RollbackMemberPlugin` exception-swallowing) |
| 10 | driver uninstall removes only driver-owned files; growth.md survives | Task 2.3/2.4 (bug fix + new smoke), Task 3.1/3.2 (agy-autotrain's own growth.md handling + smoke) |
| 11 | single-member rebuild/republish without any sibling's gate | Task 4.4 (`republish-member.yml`) |

### 3. Under-specified "what"s still vague (flagged, not silently resolved)

- **(a) Idempotency mechanism — RESOLVED (Finding-4).** The earlier plan relied on a fragile
  output-substring heuristic (`LooksAlreadyRegistered` / `IsAlreadyRegisteredOutcome`) with no
  static oracle for the CLI's exact "already registered" wording. That is now replaced by a
  STRUCTURAL remove-then-add in both `PluginInstaller.Install` (C#, Task 2.1) and
  `RegisterClaude`/`RegisterAgy` (Inno, Task 1.4): best-effort `marketplace remove`/`plugin
  uninstall` (result swallowed) before `add`/`install`, whose exit codes are then handled normally.
  No CLI-wording assumption remains. Documented caveat: if `add`/`install` fails right after the
  pre-clean remove, the prior registration is gone and surfaces as a reported registration failure
  (for dotnet/classic the install-time rollback path covers a later-step failure).
- **(b) Install-twice smoke coverage — CLOSED (Finding-5).** All five members' install/uninstall
  smoke steps now re-run the installer a second time and assert exit 0 + the scoped manifest still
  present: Task 4.1 (dotnet), 4.2 (classic), 4.3 (ghidrust), 3.2 (agy-autotrain), 3.4
  (commonmemory). This exercises the new remove-then-add `[Code]`/C# path on every member.
- **The exact rollback-trigger scope** (Task 1.4's `RollbackMemberPlugin` comment): the design
  spec's illustrative list ("binary unpack, PATH, a second agent") is not a literal enumeration;
  this plan's concrete resolution — rollback triggers only on a post-registration golden-header
  seed failure (dotnet/classic) and is structurally moot elsewhere — is a reasonable, documented
  synthesis, not a verified requirement. Flagged for owner sign-off during plan review.
- **O6 (concurrent-install serialization):** this plan did **not** live-verify whether the
  claude/agy CLIs already serialize their own global-config writes (that requires a live
  two-terminal test against the real CLI, out of scope for a static plan-authoring pass) — it
  resolves O6 by extending the already-proven `ClavitySetupMutex` to all five installers
  defensively, per the spec's "else add a shared mutex" branch. If a future live check confirms
  the CLIs already serialize themselves, the mutex extension can be safely reverted (it costs
  nothing but serializes ALL FIVE installs, not just the plugin-registration critical section —
  a documented over-approximation, not a gap).

### 4. Remaining placeholder/TBD

None in the code/YAML blocks above — every block is complete (no `...`, no "same as Task N", no
elided match arms). §3 gaps (a) and (b) are now RESOLVED/CLOSED (Findings 4 and 5); the two
remaining §3 items (rollback-trigger scope synthesis, O6 mutex over-approximation) are documented
design judgments awaiting owner sign-off, not placeholders in the plan's own artifacts. One further
non-blocking item: `docs/hosting-a-tool.md` is only partially updated (Task 4.6 adds a supersede notice; it
does not rewrite the full onboarding playbook, since the branch-per-tool/remote-marketplace
sections it would need to replace are a larger doc-restructuring effort outside this plan's
distribution-model scope) — flagged, not silently dropped.

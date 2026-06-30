# clavity-classic packaging (Option A) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ship `clavity-classic-setup.exe` — a no-Rust-toolchain installer for the classic `clavity` binary —
matching classic's deliberate **manual-wiring** architecture (Spec B **Option A**, user-approved 2026-06-30).

**Architecture:** Mirror the proven dotnet installer (`installer/clavity-dotnet.iss` +
`.github/workflows/release-clavity-dotnet.yml`) as the **structural oracle**, with Option-A deltas: NO install
verb / NO MCP or GEMINI.md registration (classic does these manually by design) / NO plugin tree or add-ons
(none exist for classic). The installer's real jobs: `clavity.exe`→PATH, the HKCU mutual-exclusion marker,
bidirectional refuse-vs-dotnet, the opt-in Python/uv **bridge** add-on, responder-skill teardown on uninstall,
and a **loud guided-manual** wiring surface (shipped docs + final summary).

**Tech Stack:** Inno Setup 6 (ISCC), GitHub Actions (`windows-2022`), `cargo build --release --locked` (the
`clavity` crate on `clavity-classic`), `uv` (bridge runtime), PowerShell (CI glue + local smoke).

**Branch:** all work on `clavity-classic` (the crate + `agy-mcp-bridge/` live there). The dotnet oracle files
are read from `main`.

**Grounded facts (verified 2026-06-30 against the `clavity-classic` worktree):** crate bin = `clavity`
(`Cargo.toml` `[[bin]] name="clavity"`, `default-run`), version `0.1.0`; bridge `agy-mcp-bridge/pyproject.toml`
version `0.1.0`; the 7.8 recipe `scripts/build-classic-release.ps1` **exists and is proven**; `rust-toolchain.toml`,
`installer/`, `dist/`, and `release-clavity-classic.yml` **do not exist yet** (this plan creates them); responder
skill is written by `install_skill()` (`src/main.rs:639`) to `~/.gemini/antigravity-cli/skills/claudavity-responder/`
on `clavity start`; dotnet AppId is `{B7E4B2A1-9C3D-4F5E-8A1B-2C3D4E5F6A7B}`; the shared setup mutex is
`ClavitySetupMutex`; dotnet's classic-marker check is `RegKeyExists(HKCU, 'Software\clavity\classic')`
(`clavity-dotnet.iss:135`).

**"Tests" for installer work** are concrete gates, not unit tests: `ISCC` compiles clean; a **silent
install/uninstall smoke** asserts the file/PATH/marker/ARP lifecycle; **mutual-exclusion** refusal; **`.env`
absence**; and (local-only) **both `.env` keep/purge branches**. Each task names its gate.

---

### Task 0: Pin the Rust toolchain (`rust-toolchain.toml`)

Reproducible local↔CI builds (Spec B 7.2) need a pinned toolchain; classic has none.

**Files:**
- Create: `rust-toolchain.toml` (repo root, `clavity-classic`)

- [ ] **Step 1: Create the toolchain pin**

```toml
# Pin the toolchain so the local ISCC gate and the release CI build the SAME binary, and a historic tag stays
# rebuildable. Bump deliberately, never float. (Verified local rustc at authoring: 1.96.0.)
[toolchain]
channel = "1.96.0"
components = ["clippy", "rustfmt"]
profile = "minimal"
```

- [ ] **Step 2: Verify the build still passes under the pin**

Run: `cargo build --release --locked`
Expected: builds `target/release/clavity.exe`, exit 0. Then `cargo test --all --features test-fakes` stays green.

- [ ] **Step 3: Commit**

```bash
git add rust-toolchain.toml
git commit -m "build(classic): pin rust toolchain (1.96.0) for reproducible installer builds"
```

---

### Task 1: Confirm the 7.8 build recipe produces `publish/` (already authored)

`scripts/build-classic-release.ps1` already exists and was proven (builds the exe, stages the bridge runtime
whitelist incl. `SKILL.md`, asserts no `.env`). This task only **verifies** it so Task 3's `.iss` can be
ISCC-compiled against a real `publish/`.

**Files:**
- Verify (no edit expected): `scripts/build-classic-release.ps1`

- [ ] **Step 1: Run the recipe locally**

Run: `pwsh -NoProfile -File scripts/build-classic-release.ps1`
Expected: prints "staged N bridge runtime files + clavity.exe"; `publish/clavity.exe` and
`publish/agy-mcp-bridge/{server.py,…,SKILL.md,.env.example}` exist; **`publish/agy-mcp-bridge/.env` does NOT
exist** (the recipe throws if it ever does).

- [ ] **Step 2: Assert the staged layout the `.iss` depends on**

Run:
```pwsh
$d = "publish/agy-mcp-bridge"
foreach ($f in @("server.py","agy_bus.py","agy_tmux.py","isolation.py","telemetry.py","SKILL.md","pyproject.toml","uv.lock","start-claudavity.ps1",".env.example","LICENSE")) {
  if (-not (Test-Path "$d/$f")) { throw "missing staged runtime file: $f" }
}
if (Test-Path "$d/.env") { throw "SECURITY: .env present in publish/" }
"publish layout OK"
```
Expected: "publish layout OK". **No commit** (the recipe is unchanged; `publish/` is gitignored).

---

### Task 2: Author the guided-manual wiring docs

Option A surfaces the manual steps honestly via shipped docs (no installer config editing). Two docs: a core
one (always shipped) and a bridge one (shipped with the bridge task).

**Files:**
- Create: `installer/clavity-classic-MANUAL-SETUP.md`
- Create: `installer/clavity-classic-bridge-README-FIRST.md`

- [ ] **Step 1: Write the core manual-setup doc**

Create `installer/clavity-classic-MANUAL-SETUP.md`:
```markdown
# clavity-classic — required manual wiring

The installer placed `clavity.exe` on your PATH. Classic uses **manual wiring by design** (unlike the
zero-touch dotnet variant) — finish these one-time steps, then `clavity start` does the rest.

## 1. Register the agentmemory bus MCP in BOTH agents (clavity's data channel)

**Claude Code:**
    claude mcp add agentmemory -s user -- npx @agentmemory/agentmemory mcp

**agy** — add to `%USERPROFILE%\.gemini\config\mcp_config.json` (i.e. `C:\Users\<You>\.gemini\config\...`) under
`mcpServers` (Windows needs `cmd /c` for a bare `npx`):
    "agentmemory": { "command": "cmd", "args": ["/c", "npx", "@agentmemory/agentmemory", "mcp"] }
Restart each agent after editing. (Even the dotnet variant requires this — agentmemory is a separate
prerequisite, not something either installer registers.)

## 2. Add the claudavity doorbell pointer to `%USERPROFILE%\.gemini\GEMINI.md` (one-time)
(That's `C:\Users\<You>\.gemini\GEMINI.md` — paste the path into Explorer's address bar to get there.)

Append this block (re-running is harmless — it's idempotent guidance, not config):
    <!-- clavity-classic doorbell (safe to keep) -->
    When you see `claudavity: check your inbox and act on any request from claude, then reply on the bus.`
    (or are told to check claudavity/claude signals), invoke the claudavity-responder skill and follow it.
    A request whose instruction is exactly `[ping]` -> reply `[req_id=…] READY` immediately.
The responder skill itself is auto-installed by `clavity start` — you do not copy it by hand.

## 3. Launch
    clavity start C:\path\to\your\project
```

- [ ] **Step 2: Write the bridge first-run doc**

Create `installer/clavity-classic-bridge-README-FIRST.md`:
```markdown
# Antigravity bridge — first-run setup (delegate_to_antigravity)

This folder is the opt-in bridge. It is INACTIVE until you finish these steps **in a terminal opened HERE**
(in Explorer: type `cmd` in the address bar and press Enter, or Shift+Right-click -> "Open in Terminal").

1. Install uv if you don't have it: https://docs.astral.sh/uv/
2. Materialize the environment from the pinned lockfile (do NOT use a bare `uv sync` — it may re-resolve):
       uv sync --frozen
   *(If the installer already ran this for you during setup — it does when uv was already installed — you can
   skip this step.)*
3. Create your secret file (use `copy`, which works in both cmd and PowerShell; do NOT rename in Explorer — it
   blocks dot-leading names):
       copy .env.example .env
   then open `.env` and paste your `GEMINI_API_KEY` (the SDK does NOT reuse agy's OAuth login).
4. Register the bridge MCP with your agent, DIRECTORY-ANCHORED so it finds its env + `.env` regardless of the
   agent's working directory (paste into the agent's MCP config, adjusting the path). **Use FORWARD slashes** in
   the path — a Windows path with single `\` backslashes is INVALID JSON (e.g. `\U` is a bad escape) and will
   corrupt your agent config:
       "agy-bridge": { "command": "uv",
         "args": ["--directory", "C:/Users/<You>/AppData/Local/Programs/clavity-classic/agy-mcp-bridge",
                  "run", "C:/Users/<You>/AppData/Local/Programs/clavity-classic/agy-mcp-bridge/server.py"] }
   Replace the path with THIS directory's absolute path (shown in the Explorer address bar), converting `\` to `/`.

> Do NOT run `start-claudavity.ps1` by hand — the MCP server is launched in the background by the host agent;
> running it manually just hangs the terminal.
```

- [ ] **Step 3: Commit**

```bash
git add installer/clavity-classic-MANUAL-SETUP.md installer/clavity-classic-bridge-README-FIRST.md
git commit -m "docs(classic-installer): guided-manual wiring docs (core MCP/GEMINI.md + bridge README-FIRST)"
```

---

### Task 3: The Inno installer (`installer/clavity-classic.iss`)

The core deliverable. Greenfield, authored against the dotnet oracle with Option-A deltas. Reuses dotnet's
proven hardening verbatim (in-process PATH scan — no `where` subprocess; suppressible msgboxes; append-never
PATH; fail-open uninstall).

**Files:**
- Create: `installer/clavity-classic.iss`

- [ ] **Step 1: Write the installer script**

Create `installer/clavity-classic.iss`:
```pascal
; Inno Setup script for clavity-classic. Build with: ISCC.exe installer\clavity-classic.iss
; Expects (from scripts/build-classic-release.ps1 = the 7.8 recipe, run first):
;   ..\publish\clavity.exe              — the prebuilt Rust binary (single self-contained exe)
;   ..\publish\agy-mcp-bridge\*         — staged bridge RUNTIME whitelist (NO .env)
; Plus committed installer docs (..\installer\clavity-classic-*.md).
;
; Option A (minimal/honest): classic wires manually BY DESIGN — this installer does NOT register the
; agentmemory MCP or the GEMINI.md doorbell (guided-manual via the shipped docs + final summary).

#define AppName "clavity-classic"
#define AppVersion "0.1.0"
#define ExeName "clavity.exe"

[Setup]
; Fresh STABLE AppId — distinct from dotnet's {B7E4B2A1-…} so the two never share an uninstall identity.
AppId={{B59E963B-BE49-47B2-8CAB-5A3417D775C3}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=clavity
DefaultDirName={localappdata}\Programs\clavity-classic
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=clavity-classic-setup
OutputDir=..\dist
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
ChangesEnvironment=yes
; SHARED with the dotnet installer — blocks a concurrent classic+dotnet setup race. Name MUST match dotnet's.
SetupMutex=ClavitySetupMutex

[Files]
Source: "..\publish\{#ExeName}"; DestDir: "{app}"; Flags: ignoreversion
; Core guided-manual wiring doc — ALWAYS shipped.
Source: "..\installer\clavity-classic-MANUAL-SETUP.md"; DestDir: "{app}"; DestName: "MANUAL-SETUP.md"; Flags: ignoreversion
; Opt-in bridge tree (gated). Staged WITHOUT the secret; exclude regenerable + secret artifacts defensively.
Source: "..\publish\agy-mcp-bridge\*"; DestDir: "{app}\agy-mcp-bridge"; \
  Flags: ignoreversion recursesubdirs createallsubdirs; Tasks: install_bridge; \
  Excludes: ".env,.venv,__pycache__,.agent,*.pyc"
; Bridge first-run doc (gated with the bridge).
Source: "..\installer\clavity-classic-bridge-README-FIRST.md"; DestDir: "{app}\agy-mcp-bridge"; \
  DestName: "README-FIRST.md"; Flags: ignoreversion; Tasks: install_bridge

[Tasks]
Name: "addtopath"; Description: "Add clavity to PATH"; Flags: checkedonce
; Opt-in bridge add-on (default OFF) — value FIRST, prerequisite second (UX round).
Name: "install_bridge"; Flags: unchecked; \
  Description: "Install the Antigravity bridge — let Claude hand off a coding task for Antigravity to do autonomously in an isolated worktree (delegate_to_antigravity). Needs Python 3.10+ and uv."

[Registry]
; Per-user PATH APPEND (never prepend) when selected.
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; \
  ValueData: "{olddata};{app}"; Tasks: addtopath; Check: NeedsAddPath('{app}')
; Mutual-exclusion marker the dotnet installer reads via RegKeyExists. uninsdeletekey removes it on uninstall.
Root: HKCU; Subkey: "Software\clavity\classic"; ValueType: string; ValueName: "variant"; \
  ValueData: "classic"; Flags: uninsdeletekey

[Run]
; Final wizard page (Option A: classic needs manual wiring — open the doc so the steps aren't lost in a dismissed
; modal). notepad.exe is always present + renders .md as text; ungated (core wiring applies without the bridge).
Filename: "notepad.exe"; Parameters: """{app}\MANUAL-SETUP.md"""; \
  Description: "View the required manual wiring steps (MUST READ)"; Flags: postinstall skipifsilent
; Open the bridge folder for manual setup (gated; skipped on silent installs).
Filename: "{app}\agy-mcp-bridge"; Description: "Open the bridge setup folder (finish setup per README-FIRST.md)"; \
  Flags: postinstall shellexec skipifsilent; Tasks: install_bridge

[UninstallDelete]
; Tear down the responder skill clavity-start writes OUTSIDE {app} (Inno has no record of it -> would orphan).
; DELIBERATE: {%USERPROFILE} (the env var), NOT the native {userprofile} (CSIDL_PROFILE) constant. The Rust
; binary resolves home via std::env::var_os("USERPROFILE") (src/main.rs:640), so the installer MUST resolve the
; same way to target the exact dir the binary wrote — matching the dotnet oracle (clavity-dotnet.iss:286). Do
; NOT "modernize" this to {userprofile}: if the env var and the API path ever diverge, the cleanup misses.
Type: filesandordirs; Name: "{%USERPROFILE}\.gemini\antigravity-cli\skills\claudavity-responder"
; Regenerable bridge artifacts (no secret, no user intent) — removed unconditionally.
Type: filesandordirs; Name: "{app}\agy-mcp-bridge\.venv"
Type: filesandordirs; Name: "{app}\agy-mcp-bridge\__pycache__"
Type: filesandordirs; Name: "{app}\agy-mcp-bridge\.agent"

[Code]
var
  RemoveConfig: Boolean;

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

{ Generic in-process PATH scan for an exe stem (each PATHEXT) — NO `where` subprocess (it deadlocks a hidden,
  non-interactive installer Exec; dotnet confirmed this via CI log). Returns the first match. }
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

{ dotnet sets no HKCU self-marker, so detect it by its Inno ARP uninstall key (DisplayName like 'clavity-dotnet*'). }
function DotnetArpPresent(): Boolean;
var
  Names: TArrayOfString;
  i: Integer;
  Sub, Disp: string;
begin
  Result := False;
  if RegGetSubkeyNames(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall', Names) then
    for i := 0 to GetArrayLength(Names) - 1 do
    begin
      Sub := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' + Names[i];
      if RegQueryStringValue(HKCU, Sub, 'DisplayName', Disp) then
        if Pos('clavity-dotnet', Disp) = 1 then
        begin
          Result := True;
          exit;
        end;
    end;
end;

function InitializeSetup(): Boolean;
var
  FoundPath: string;
begin
  Result := True;
  { Refuse if dotnet's clavity-ls is on PATH (NOT the bare 'clavity' stem — that is OUR binary). }
  if StemOnPath('clavity-ls', FoundPath) then
  begin
    SuppressibleMsgBox('clavity-dotnet is already installed (clavity-ls at:' + #13#10 + FoundPath + #13#10#13#10 +
      'clavity-classic and clavity-dotnet cannot be installed together. Uninstall clavity-dotnet first, then run this setup again.',
      mbCriticalError, MB_OK, IDOK);
    Result := False;
    exit;
  end;
  if DotnetArpPresent() then
  begin
    SuppressibleMsgBox('clavity-dotnet is registered on this machine. Uninstall it first, then run this setup again.',
      mbCriticalError, MB_OK, IDOK);
    Result := False;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  UvPath, BridgeDir: string;
begin
  if CurStep = ssPostInstall then
  begin
    if WizardIsTaskSelected('install_bridge') then
    begin
      BridgeDir := ExpandConstant('{app}\agy-mcp-bridge');
      if StemOnPath('uv', UvPath) then
      begin
        { Materialize .venv from the pinned lockfile; --frozen errors instead of silently re-resolving (supply-chain).
          The Exec BLOCKS the wizard UI for 10-30s+ (uv fetches the toolchain + deps). Set the status caption FIRST
          (so the frozen page explains itself) and SW_SHOW uv's console (live progress) so the operator doesn't
          assume a hang and kill the installer mid-sync — which would corrupt the bridge env. }
        WizardForm.StatusLabel.Caption := 'Installing the bridge''s Python dependencies (uv sync) — up to a minute...';
        WizardForm.StatusLabel.Update;
        if (not Exec(UvPath, 'sync --frozen', BridgeDir, SW_SHOW, ewWaitUntilTerminated, ResultCode)) or (ResultCode <> 0) then
          SuppressibleMsgBox('The bridge was installed but `uv sync` did not complete. Open a terminal in:' + #13#10 +
            BridgeDir + #13#10 + 'and run:  uv sync --frozen', mbError, MB_OK, IDOK);
      end
      else
        SuppressibleMsgBox('The bridge was installed but is INACTIVE until you install uv (https://docs.astral.sh/uv/)' + #13#10 +
          'and run `uv sync --frozen` in:' + #13#10 + BridgeDir + #13#10 + 'BEFORE first use. See README-FIRST.md there.',
          mbInformation, MB_OK, IDOK);
    end;
  end;
  { No ssDone MsgBox: a final modal listing mandatory steps gets double-Enter-dismissed and is uncopyable. The
    manual-wiring handoff is the [Run] "View the required manual wiring steps (MUST READ)" checkbox on the
    Finished page, which opens the persistent, copyable MANUAL-SETUP.md in the app folder.
    (Do NOT write an Inno {app}-style constant inside a Pascal { } comment — the brace starts a constant and
    breaks the comment; ISCC errors "Syntax error". Caught by the local ISCC gate, not by review.) }
end;

function InitializeUninstall(): Boolean;
var
  Prompt: string;
begin
  Result := True;
  { Option A: no clavity uninstall verb to run and no live-session mutex (classic has no long-running --mcp host),
    so this is just the data keep/purge decision. Enumerate the data classes it governs so the choice is informed:
    golden-header ALWAYS; the bridge API key ONLY when a post-install .env exists (opt-in, default-OFF). }
  Prompt := 'Also remove clavity''s data?' + #13#10#13#10 +
    '  - the golden-header wisdom (~\.clavity\golden-header.md)';
  if FileExists(ExpandConstant('{app}\agy-mcp-bridge\.env')) then
    Prompt := Prompt + #13#10 + '  - your stored bridge API key (agy-mcp-bridge\.env)';
  Prompt := Prompt + #13#10#13#10 + 'Choose No to KEEP it for a future reinstall.';
  { Silent uninstall defaults to KEEP (IDNO) — never delete user data without an explicit answer. }
  RemoveConfig := SuppressibleMsgBox(Prompt, mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES;
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
var
  Header, Backup, BridgeDir, EnvFile: string;
begin
  if CurUninstallStep = usUninstall then
  begin
    { Zombie-header fix (mirror dotnet): when KEEPING, rename golden-header.md -> .backup so a reinstall does not
      auto-inject frozen wisdom. Skipped on purge. Default path only (a CLAVITY_GOLDEN_HEADER override is rare). }
    if not RemoveConfig then
    begin
      Header := ExpandConstant('{%USERPROFILE}\.clavity\golden-header.md');
      Backup := Header + '.backup';
      if FileExists(Header) then
      begin
        DeleteFile(Backup);
        RenameFile(Header, Backup);
      end;
    end;
    { Bridge .env (live secret): gated on the keep/purge answer. On purge, remove .env (regenerable
      .venv/__pycache__/.agent already go via [UninstallDelete]); on keep, leave it. }
    BridgeDir := ExpandConstant('{app}\agy-mcp-bridge');
    EnvFile := BridgeDir + '\.env';
    if RemoveConfig and FileExists(EnvFile) then
      DeleteFile(EnvFile);
  end
  else if CurUninstallStep = usPostUninstall then
    RemoveFromUserPath(ExpandConstant('{app}'));
end;
```

> **PLAN NOTE (purge of `{app}` dir):** Inno's uninstaller removes files it *installed* and (via `[UninstallDelete]`)
> the listed regenerable artifacts; on **purge** the only extra step is deleting the user-created `.env`. Any
> remaining empty `{app}\agy-mcp-bridge` is removed by Inno's normal dir cleanup once its tracked files +
> `[UninstallDelete]` targets are gone. If the local smoke (Task 4) shows the dir lingering on purge, add an
> explicit `DelTree(BridgeDir, True, True, True)` in the purge branch.

- [ ] **Step 2: ISCC compiles clean (the unit gate)**

Run (after Task 1 populated `publish/`):
```pwsh
$iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
& $iscc installer/clavity-classic.iss
if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }
if (-not (Test-Path dist/clavity-classic-setup.exe)) { throw "setup.exe not produced" }
```
Expected: ISCC exit 0; `dist/clavity-classic-setup.exe` exists.

- [ ] **Step 3: Commit**

```bash
git add installer/clavity-classic.iss
git commit -m "feat(classic-installer): Option A Inno installer (PATH+marker+mutual-exclusion+bridge add-on)"
```

---

### Task 4: Local install/uninstall + mutual-exclusion + `.env` smoke (RIGHT-TOOL gate — before any tag)

The authoritative gate. Drives BOTH `.env` keep/purge branches (CI can only do KEEP) and both exclusion
directions. No remote-CI iteration to find installer bugs.

**Files:** none (a throwaway smoke script; do not commit).

- [ ] **Step 1: Silent install + lifecycle asserts**

```pwsh
$ErrorActionPreference = "Stop"
$setup = "dist/clavity-classic-setup.exe"; $app = "$env:LOCALAPPDATA\Programs\clavity-classic"
$p = Start-Process $setup -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART","/TASKS=addtopath,install_bridge" -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "install exit $($p.ExitCode)" }
if (-not (Test-Path "$app\clavity.exe")) { throw "clavity.exe missing" }
if (-not (Test-Path "$app\MANUAL-SETUP.md")) { throw "MANUAL-SETUP.md missing" }
if (-not (Test-Path "$app\agy-mcp-bridge\server.py")) { throw "bridge not staged" }
if (-not (Test-Path "$app\agy-mcp-bridge\SKILL.md")) { throw "bridge SKILL.md missing (runtime!)" }
if (Test-Path "$app\agy-mcp-bridge\.env") { throw "SECURITY: .env present after install" }
if (-not (Get-Item "HKCU:\Software\clavity\classic" -EA SilentlyContinue)) { throw "classic marker missing" }
$userPath = (Get-ItemProperty "HKCU:\Environment" -Name Path -EA SilentlyContinue).Path
if ($userPath -notlike "*$app*") { throw "PATH not added" }
"install asserts PASSED"
```

- [ ] **Step 2: `.env` KEEP branch (seed a fake key, uninstall silently, assert retained + responder torn down)**

```pwsh
Set-Content "$app\agy-mcp-bridge\.env" "GEMINI_API_KEY=smoke-fake"   # simulate user post-install setup
$uninst = Get-ChildItem $app -Filter "unins*.exe" | Select -First 1
# /SUPPRESSMSGBOXES makes the keep/purge prompt take its default (KEEP / IDNO).
Start-Process $uninst.FullName -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait | Out-Null
# Inno's silent uninstaller relaunches itself from %TEMP% and the stub returns immediately, so -Wait does NOT
# mean "done". Poll a completion SIGNAL (the installed exe is gone) with a timeout — robust to the temp-RENAMED
# worker process (matching a process NAME would miss it). Only THEN assert + clean up (no racing the deleter).
$deadline = (Get-Date).AddSeconds(30)
while ((Test-Path "$app\clavity.exe") -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
if (Test-Path "$app\clavity.exe") { throw "uninstall did not complete within 30s" }
if (-not (Test-Path "$app\agy-mcp-bridge\.env")) { throw "KEEP branch FAILED — .env was deleted" }
if (Test-Path "$HOME\.gemini\antigravity-cli\skills\claudavity-responder") { throw "responder skill orphaned" }
"KEEP-branch + responder-teardown PASSED"; Remove-Item "$app" -Recurse -Force -EA SilentlyContinue
```

- [ ] **Step 3: `.env` PURGE branch + conditional prompt wording (manual GUI uninstall)**

Reinstall (Step 1), re-seed `.env`, run the uninstaller **non-silently**, click **Yes** on the data prompt.
Assert: `$app\agy-mcp-bridge\.env` is gone AND the prompt **named the bridge API key** (because `.env` existed).
Then reinstall **without** the bridge task, uninstall non-silently: assert the prompt **omits** the API-key line.
Expected: purge removes the key; the API-key line appears only when `.env` exists.

- [ ] **Step 4: Mutual exclusion (both directions — Spec B "live-test BOTH before merge")**

```pwsh
$app = "$env:LOCALAPPDATA\Programs\clavity-classic"
# Step 4 mutates $env:PATH — RESTORE it (and remove the fake dir) in a finally, or it poisons Step 5's reinstall
# (the fake clavity-ls would still be on PATH, tripping the exclusion guard and falsely failing Step 5).
$oldPath = $env:PATH
$fake = "$env:TEMP\fakels"; New-Item $fake -ItemType Directory -Force | Out-Null
try {
  Set-Content "$fake\clavity-ls.exe" "x"; $env:PATH = "$fake;$env:PATH"
  $p = Start-Process "dist/clavity-classic-setup.exe" -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait -PassThru
  if ($p.ExitCode -eq 0 -and (Test-Path "$app\clavity.exe")) { throw "refusal FAILED (clavity-ls on PATH)" }
  "refuse-on-clavity-ls PASSED"
} finally {
  $env:PATH = $oldPath; Remove-Item $fake -Recurse -Force -EA SilentlyContinue
}
```
Then install the real dotnet setup and attempt the classic install → assert refusal via `DotnetArpPresent`
(manual). The reverse (dotnet refuses when the classic marker exists) is the dotnet oracle's own smoke (unchanged).

- [ ] **Step 5: PATH-append idempotency on reinstall**

Install twice; assert `HKCU:\Environment` Path contains `;{app}` **exactly once** (the `NeedsAddPath` guard).

---

### Task 5: Release workflow (`.github/workflows/release-clavity-classic.yml`)

Mirror `release-clavity-dotnet.yml` with Option-A + the Spec B 7.2 hardening (pinned toolchains, version
triangulation, tag-lineage guard, blocking timeout-bounded smokes, concurrency, atomic publish).

**Files:**
- Create: `.github/workflows/release-clavity-classic.yml` (on `clavity-classic`)

- [ ] **Step 1: Write the workflow**

```yaml
name: release-clavity-classic

on:
  push:
    tags:
      - 'clavity-classic-v*'   # distinct from dotnet's clavity-dotnet-v*/v* — do NOT reuse the bare v* glob.

permissions:
  contents: write

concurrency:
  # A deleted+force-pushed tag otherwise races two publish jobs (exe from one runner, sha256 from another).
  group: release-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-and-release:
    runs-on: windows-2022   # STATIC image (not -latest): keep MSVC/SDK stable so a historic tag stays rebuildable.
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.ref }}
          fetch-depth: 0   # need history for the tag-lineage ancestor check.

      - name: Tag-lineage guard (must be on clavity-classic, not main)
        shell: bash
        run: |
          # A clavity-classic-v* tag accidentally pushed onto main would build the wrong code. Assert ancestry.
          git fetch origin clavity-classic
          if ! git merge-base --is-ancestor "$GITHUB_SHA" origin/clavity-classic; then
            echo "::error::tag commit $GITHUB_SHA is not on clavity-classic"; exit 1
          fi

      - name: Version triangulation (assert BEFORE building)
        shell: pwsh
        run: |
          # tag clavity-classic-vX.Y.Z must equal Cargo.toml, the .iss AppVersion, and the bridge pyproject.
          $tag = "${{ github.ref_name }}" -replace '^clavity-classic-v',''
          $cargo  = (Select-String -Path Cargo.toml -Pattern '^version\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value
          $iss    = (Select-String -Path installer/clavity-classic.iss -Pattern '#define AppVersion "([^"]+)"').Matches[0].Groups[1].Value
          $bridge = (Select-String -Path agy-mcp-bridge/pyproject.toml -Pattern '^version\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value
          "tag=$tag cargo=$cargo iss=$iss bridge=$bridge"
          if (($cargo -ne $tag) -or ($iss -ne $tag) -or ($bridge -ne $tag)) { throw "version mismatch (all must equal $tag)" }

      - uses: dtolnay/rust-toolchain@stable   # rust-toolchain.toml pins the actual channel; this provides the harness.

      - name: Build + stage (the 7.8 recipe)
        shell: pwsh
        run: |
          pwsh -NoProfile -File scripts/build-classic-release.ps1
          if (-not (Test-Path publish/clavity.exe)) { throw "publish/clavity.exe not produced" }
          if (Test-Path publish/agy-mcp-bridge/.env) { throw "SECURITY: .env staged" }

      - name: Test gate
        run: cargo test --all --features test-fakes

      - name: Locate Inno Setup (windows-2022 ships it preinstalled; the STATIC image pins the version)
        id: inno
        shell: pwsh
        run: |
          # windows-2022 already has Inno Setup 6.x — do NOT choco-pin a downgrade (it errors "a newer version is
          # already installed"). The static image IS the version pin. Only install if absent; discover the path.
          $iscc = Get-ChildItem "C:\Program Files*\Inno Setup 6\ISCC.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
          if (-not $iscc) { choco install innosetup --no-progress -y; $iscc = Get-ChildItem "C:\Program Files*\Inno Setup 6\ISCC.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 }
          if (-not $iscc) { throw "ISCC.exe not found (no preinstall, install failed)" }
          "iscc=$($iscc.FullName)" | Out-File -FilePath $env:GITHUB_OUTPUT -Append

      - name: Build installer (ISCC)
        shell: pwsh
        run: |
          & "${{ steps.inno.outputs.iscc }}" installer/clavity-classic.iss
          if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }
          if (-not (Test-Path dist/clavity-classic-setup.exe)) { throw "setup.exe not produced" }

      - name: SHA-256 companion
        shell: pwsh
        run: |
          $h = (Get-FileHash dist/clavity-classic-setup.exe -Algorithm SHA256).Hash.ToLower()
          # Write LF, NOT Set-Content's CRLF (measured: Set-Content appends 0x0D,0x0A). A CRLF .sha256 makes GNU
          # `sha256sum -c` parse the filename with a trailing \r -> "No such file or directory". WriteAllText emits
          # exact bytes (no BOM, LF only). Two spaces between hash and filename (sha256sum format).
          [IO.File]::WriteAllText("$PWD/dist/clavity-classic-setup.exe.sha256", "$h  clavity-classic-setup.exe`n")

      - name: Smoke — install/uninstall lifecycle (BLOCKING)
        timeout-minutes: 6   # a HANG fails fast; a real regression must NOT publish.
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $setup = "dist/clavity-classic-setup.exe"; $app = "$env:LOCALAPPDATA\Programs\clavity-classic"
          $p = Start-Process $setup -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART","/TASKS=addtopath,install_bridge" -Wait -PassThru
          if ($p.ExitCode -ne 0) { throw "install exit $($p.ExitCode)" }
          if (-not (Test-Path "$app\clavity.exe")) { throw "clavity.exe missing" }
          if (-not (Test-Path "$app\agy-mcp-bridge\SKILL.md")) { throw "bridge SKILL.md missing" }
          # Assert the EXACT Inno ARP key ({AppId}_is1), not a DisplayName wildcard (which can match a sibling
          # product and yield a truthy array, defeating the precision of the test).
          $arpKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{B59E963B-BE49-47B2-8CAB-5A3417D775C3}_is1"
          if (-not (Test-Path $arpKey)) { throw "ARP key missing (exact AppId _is1)" }
          $uninst = Get-ChildItem $app -Filter "unins*.exe" | Select -First 1
          Start-Process $uninst.FullName -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait | Out-Null
          # -Wait returns when Inno's stub exits, not when deletion finishes — poll a completion signal + timeout.
          $deadline = (Get-Date).AddSeconds(30)
          while ((Test-Path "$app\clavity.exe") -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
          if (Test-Path "$app\clavity.exe") { throw "uninstall did not complete within 30s" }
          "lifecycle smoke PASSED"

      - name: Smoke — mutual-exclusion refusal (BLOCKING)
        timeout-minutes: 4
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $app = "$env:LOCALAPPDATA\Programs\clavity-classic"
          $fake = "$env:TEMP\fakels"; New-Item $fake -ItemType Directory -Force | Out-Null
          Set-Content "$fake\clavity-ls.exe" "x"; $env:PATH = "$fake;$env:PATH"
          $p = Start-Process "dist/clavity-classic-setup.exe" -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait -PassThru
          if ($p.ExitCode -eq 0 -and (Test-Path "$app\clavity.exe")) { throw "refusal FAILED" }
          "mutual-exclusion smoke PASSED"

      - name: Smoke — .env exclusion (BLOCKING — secret-boundary guard)
        timeout-minutes: 4
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $app = "$env:LOCALAPPDATA\Programs\clavity-classic"
          # /TASKS overrides the default checkbox set (unlisted tasks are DESELECTED), so name addtopath too to
          # mirror the lifecycle smoke's internal state — even though this smoke only asserts .env absence.
          $p = Start-Process "dist/clavity-classic-setup.exe" -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART","/TASKS=addtopath,install_bridge" -Wait -PassThru
          if ($p.ExitCode -ne 0) { throw "install exit $($p.ExitCode)" }
          if (Test-Path "$app\agy-mcp-bridge\.env") { throw "SECURITY: .env shipped in installed tree" }
          $uninst = Get-ChildItem $app -Filter "unins*.exe" | Select -First 1
          Start-Process $uninst.FullName -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait | Out-Null
          ".env-exclusion smoke PASSED"

      - name: Upload build artifacts (recover even if the Release API blips)
        uses: actions/upload-artifact@v4
        with:
          name: clavity-classic-setup
          path: |
            dist/clavity-classic-setup.exe
            dist/clavity-classic-setup.exe.sha256

      - name: Publish release (atomic multi-asset)
        uses: softprops/action-gh-release@v2
        with:
          files: |
            dist/clavity-classic-setup.exe
            dist/clavity-classic-setup.exe.sha256
```

- [ ] **Step 2: Validate workflow YAML**

Run an `actionlint` pass if available (best-effort), else assert it parses:
`pwsh -NoProfile -Command "[void](Get-Content .github/workflows/release-clavity-classic.yml -Raw)"`.
Expected: parses; no schema errors.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release-clavity-classic.yml
git commit -m "ci(classic): release-clavity-classic.yml — pinned, triangulated, blocking smokes, atomic publish"
```

---

### Task 6: First release (version triangulation + tag)

**Files:** none (tag + verify).

- [ ] **Step 1: Confirm all four versions equal `0.1.0`**

`Cargo.toml`, `installer/clavity-classic.iss` (`AppVersion`), `agy-mcp-bridge/pyproject.toml`, and the intended
tag `clavity-classic-v0.1.0`. (All are `0.1.0` at authoring — no bump needed for the first release.)

- [ ] **Step 2: Push the BRANCH, THEN the tag (ONLY after Task 4's local gate is GREEN)**

The branch MUST be pushed before the tag, or the workflow's tag-lineage guard
(`git merge-base --is-ancestor <tag> origin/clavity-classic`) fails: if `origin/clavity-classic` is stale, the
tagged commit is a *descendant* (not an ancestor) of the remote branch tip and the guard hard-fails the job.

```bash
git push origin clavity-classic          # publish the Task 0-5 commits FIRST
git tag clavity-classic-v0.1.0
git push origin clavity-classic-v0.1.0   # then the tag (now an ancestor of origin/clavity-classic)
```

- [ ] **Step 3: Verify CI**

Watch the run: all asserts/smokes green; the Release carries both `clavity-classic-setup.exe` + `.sha256`.
Record the **yank/rollback** procedure (no `cargo yank` for a binary release: mark the Release draft/deleted,
destroy the tag, roll FORWARD with `clavity-classic-v0.1.1`).

---

## Self-Review (against Spec B Option A)

- **7.8 (prebuild):** Task 1 (recipe exists/verified). ✅
- **7.1 (installer):** Task 3 — PATH, marker, mutual-exclusion (both ways), bridge add-on (gated, Excludes,
  uv-sync warmup, README-FIRST), responder teardown, golden-header zombie rename, informed `.env` keep/purge,
  loud manual-wiring summary. Dropped (per Option A): plugin tree, add-ons, MCP/GEMINI.md/tmux.conf registration. ✅
- **7.2 (release CI):** Task 5 — distinct tag glob, single checkout, version triangulation (4-way), tag-lineage
  guard, pinned toolchain+Inno+static runner, blocking timeout-bounded smokes, concurrency, upload-artifact then
  atomic gh-release, yank procedure. ✅
- **Secret boundary:** staged whitelist (7.8) + `[Files]` Excludes + CI `.env`-exclusion smoke + informed
  uninstall prompt. ✅
- **Open verification (resolve during execution, NOT fabricated now):** (a) Inno `ValueType: string` marker
  satisfies dotnet's `RegKeyExists` — Task 4 Step 1 asserts the key exists. (b) Whether purge leaves an empty
  `{app}\agy-mcp-bridge` dir — Task 3 PLAN NOTE + Task 4 Step 3 decide if an explicit `DelTree` is needed. (c)
  `choco innosetup --version=6.2.2` availability on `windows-2022` — if unavailable, pick the nearest published
  6.x and record it. (d) `actionlint` presence (Task 5 Step 2) is best-effort.

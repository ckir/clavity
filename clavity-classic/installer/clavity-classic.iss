; Inno Setup script for clavity-classic. Build with: ISCC.exe installer\clavity-classic.iss
; Expects (from scripts/build-classic-release.ps1 = the 7.8 recipe, run first):
;   ..\publish\clavity.exe              — the prebuilt Rust binary (single self-contained exe)
;   ..\publish\agy-mcp-bridge\*         — staged bridge RUNTIME whitelist (NO .env)
; Plus committed installer docs (..\installer\clavity-classic-*.md).
;
; Option A (minimal/honest): classic wires manually BY DESIGN — this installer does NOT register the
; agentmemory MCP or the GEMINI.md doorbell (guided-manual via the shipped docs + the Finished-page [Run]).

#define AppName "clavity-classic"
#define AppVersion "0.4.0"
#define ExeName "clavity.exe"

[Setup]
; Fresh STABLE AppId — distinct from dotnet's {B7E4B2A1-...} so the two never share an uninstall identity.
AppId={{B59E963B-BE49-47B2-8CAB-5A3417D775C3}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=clavity
DefaultDirName={localappdata}\Programs\clavity-classic
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=clavity-classic-setup-{#AppVersion}
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
; Phase 3 parity: the golden-header SEED baseline. Installer seeds %USERPROFILE%\.clavity\golden-header.seed.md
; post-install (via standard PowerShell). Unconditional — the SEED ships even without the agy-autotrain add-on.
; Path is repo-root seed/ (from clavity-classic/installer/, ..\..\seed = repo root), same as the dotnet installer.
Source: "..\..\seed\golden-header.md"; DestDir: "{app}\seed"; Flags: ignoreversion
; Core guided-manual wiring doc — ALWAYS shipped.
Source: "..\installer\clavity-classic-MANUAL-SETUP.md"; DestDir: "{app}"; DestName: "MANUAL-SETUP.md"; Flags: ignoreversion
; Opt-in bridge tree (gated). Staged WITHOUT the secret; exclude regenerable + secret artifacts defensively.
Source: "..\publish\agy-mcp-bridge\*"; DestDir: "{app}\agy-mcp-bridge"; \
  Flags: ignoreversion recursesubdirs createallsubdirs; Tasks: install_bridge; \
  Excludes: ".env,.venv,__pycache__,.agent,*.pyc"
; Bridge first-run doc (gated with the bridge).
Source: "..\installer\clavity-classic-bridge-README-FIRST.md"; DestDir: "{app}\agy-mcp-bridge"; \
  DestName: "README-FIRST.md"; Flags: ignoreversion; Tasks: install_bridge
Source: "marketplace.install.json"; DestDir: "{app}\.claude-plugin"; DestName: "marketplace.json"; Flags: ignoreversion
Source: "..\..\installer\_shared\register-plugin.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\plugin\*"; DestDir: "{app}\plugins\clavity"; Flags: ignoreversion recursesubdirs createallsubdirs

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
#include "..\..\installer\_shared\claude-running.iss"
#include "..\..\installer\_shared\path-scan.iss"
#include "..\..\installer\_shared\register-plugin-hash.iss"
#include "..\..\installer\_shared\register-invoke.iss"
#include "..\..\installer\_shared\golden-header-data.iss"

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
  if ClaudeIsRunning() then
  begin
    SuppressibleMsgBox('Claude Code is running. Close it COMPLETELY before installing clavity-classic — a '
      + 'running Claude overwrites the plugin registration and leaves it unregistered. Quit Claude Code, '
      + 'then run this setup again.', mbCriticalError, MB_OK, IDOK);
    Result := False;
    exit;
  end;
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

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if ClaudeIsRunning() then
    Result := 'Claude Code is running. Close it completely, then run this setup again — a running Claude '
      + 'overwrites the plugin registration and leaves it unregistered.';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  UvPath, BridgeDir: string;
  RegisteredClaude, RegisteredAgy, AnyDetected, AnySucceeded: Boolean;
  RegReport: string;
begin
  if CurStep = ssPostInstall then
  begin
    { C1/C9: register the clavity-classic plugin against every detected agent — classic has no
      own binary, so (unlike dotnet) it uses the shared Inno registration primitives directly. }
    RegisterMemberPlugin(ExpandConstant('{app}'), 'clavity', 'clavity-classic',
      RegisteredClaude, RegisteredAgy, AnyDetected, AnySucceeded, RegReport);
    ReportRegistrationOutcome(AnyDetected, AnySucceeded, RegisteredClaude, RegisteredAgy, RegReport);

    { C4/O1: seed the golden-header baseline UNCONDITIONALLY — it must NOT depend on whether an agent was
      detected/registered (the [Files] comment: "the SEED ships even without the agy-autotrain add-on"; a
      no-agent box still gets the seed). NON-FATAL (parity with clavity-dotnet): the plugin is registered and
      fully works without the pre-seeded baseline (agy-curate writes the growth header on its first run). A
      seed hiccup must NOT roll back a good registration — that rollback is exactly what blocked a real user's
      install on the dotnet side — so just surface the manual step. }
    if not SeedGoldenHeader(ExpandConstant('{app}')) then
      SuppressibleMsgBox('clavity-classic is installed and registered, but the golden-header baseline could ' +
        'not be pre-seeded (non-blocking). Add it any time by copying' + #13#10 +
        ExpandConstant('{app}\seed\golden-header.md') + '  to  ' +
        GoldenHeaderDataDir() + '\golden-header.seed.md',
        mbInformation, MB_OK, IDOK);
    if WizardIsTaskSelected('install_bridge') then
    begin
      BridgeDir := ExpandConstant('{app}\agy-mcp-bridge');
      if StemOnPath('uv', UvPath) then
      begin
        { Materialize .venv from the pinned lockfile; --frozen errors instead of silently re-resolving (supply-chain).
          The Exec BLOCKS the wizard UI for 10-30s+ (uv fetches the toolchain + deps). Set the status caption FIRST
          (so the frozen page explains itself) and SW_SHOW uv's console (live progress) so the operator doesn't
          assume a hang and kill the installer mid-sync — which would corrupt the bridge env. }
        WizardForm.StatusLabel.Caption := 'Installing the bridge''s Python dependencies (uv sync) - up to a minute...';
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
    (Do not write an Inno constant like the app-dir brace inside a Pascal comment: the brace starts a constant
    and breaks the comment.) }
end;

function InitializeUninstall(): Boolean;
var
  Prompt: string;
begin
  Result := True;
  if ClaudeIsRunning() then
  begin
    SuppressibleMsgBox('Claude Code is running. Close it COMPLETELY before uninstalling — otherwise Claude '
      + 'restores the plugin registration on exit and then loads deleted files. Quit Claude Code, then '
      + 'uninstall again.', mbCriticalError, MB_OK, IDOK);
    Result := False;
    exit;
  end;
  { Option A: no clavity uninstall verb to run and no live-session mutex (classic has no long-running --mcp host),
    so this is just the data keep/purge decision. Enumerate the data classes it governs so the choice is informed:
    golden-header ALWAYS; the bridge API key ONLY when a post-install .env exists (opt-in, default-OFF). }
  Prompt := 'Also remove clavity''s data?' + #13#10#13#10 +
    '  - the golden-header seed baseline (~\.clavity\golden-header.seed.md, its .sha256, and any' + #13#10 +
    '    pre-split golden-header.md). The learned growth file belongs to agy-autotrain and is' + #13#10 +
    '    removed by that product''s own uninstaller, not this one.';
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
  BridgeDir, EnvFile, HeaderDir: string;
begin
  if CurUninstallStep = usUninstall then
  begin
    { Zombie-header fix: on KEEP, step the driver-SEEDED baseline aside to .backup so a reinstall installs a
      fresh baseline instead of auto-injecting a frozen one. That is safe for seed.md precisely BECAUSE the
      installer re-seeds it — nothing of the user's is lost.
      The legacy pre-split golden-header.md is deliberately NOT backed up: it is the USER's own accumulated
      wisdom, it is never re-seeded, and renaming it drops it out of the driver's migration read path for
      good — the dialog says "keep", so keeping it where the driver reads it is the only honest reading.
      agy-autotrain applies exactly this reasoning to its growth.md and leaves it alone on keep. }
    HeaderDir := GoldenHeaderDataDir();   { honors CLAVITY_GOLDEN_HEADER; see golden-header-data.iss }
    if not RemoveConfig then
    begin
      { C6: back up ONLY driver-owned files — growth.md is agy-autotrain's, not touched here. }
      BackupDataFile(HeaderDir + '\golden-header.seed.md');
      BackupDataFile(HeaderDir + '\golden-header.seed.md.sha256');
    end
    else
    begin
      { PURGE: actually delete what the prompt promised. The dotnet member delegates this to its
        `clavity-ls uninstall --purge-data` call; classic ships no uninstall verb, so without these
        deletes a user who explicitly consented to removal simply kept their data — the dialog was
        making a promise no code kept. C6 ownership still applies: driver-owned files ONLY. The
        learned growth file belongs to agy-autotrain and is purged by ITS uninstaller, not here. }
      DeleteFile(HeaderDir + '\golden-header.seed.md');
      DeleteFile(HeaderDir + '\golden-header.seed.md.sha256');
      DeleteFile(HeaderDir + '\golden-header.md');  { legacy flat, if present }
      { ...and the .backup copies a PREVIOUS keep-data uninstall left behind (BackupDataFile renames to
        <path>.backup). Without these, a purge deletes the active files while silently retaining the
        user's data in the backups beside them — consent given, data kept. The dotnet member avoids this
        only because it purges the whole data dir via its own uninstall verb. The legacy .backup is still
        swept even though keep no longer creates one, because an OLDER build did. }
      DeleteFile(HeaderDir + '\golden-header.seed.md.backup');
      DeleteFile(HeaderDir + '\golden-header.seed.md.sha256.backup');
      DeleteFile(HeaderDir + '\golden-header.md.backup');
    end;
    { Bridge .env (live secret): gated on the keep/purge answer. On purge, remove .env (regenerable
      .venv/__pycache__/.agent already go via [UninstallDelete]); on keep, leave it. }
    BridgeDir := ExpandConstant('{app}\agy-mcp-bridge');
    EnvFile := BridgeDir + '\.env';
    if RemoveConfig and FileExists(EnvFile) then
      DeleteFile(EnvFile);
    DeregisterMemberPluginOnUninstall('clavity', 'clavity-classic');
  end
  else if CurUninstallStep = usPostUninstall then
    RemoveFromUserPath(ExpandConstant('{app}'));
end;

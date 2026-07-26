; Inno Setup script for clavity-dotnet. Build with: ISCC.exe installer\clavity-dotnet.iss
; Expects (produced by the release CI, Task 3.3):
;   ..\publish\clavity-ls.exe        — single-file publish of Clavity.Cli
;   ..\.claude-plugin\marketplace.json  — the marketplace root manifest (committed in-repo)
;   ..\plugins\clavity-dotnet\*       — the core plugin (referenced as ./plugins/clavity-dotnet by the manifest)
;

#define AppName "clavity-dotnet"
#define AppVersion "0.3.1"
#define ExeName "clavity-ls.exe"

[Setup]
; Stable AppId so version upgrades replace in place (do NOT change between releases).
AppId={{B7E4B2A1-9C3D-4F5E-8A1B-2C3D4E5F6A7B}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=clavity
LicenseFile=..\LICENSE
DefaultDirName={localappdata}\Programs\clavity-dotnet
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=clavity-dotnet-setup-{#AppVersion}
; OutputDir is relative to THIS script's dir (installer/), so ..\dist = repo-root dist/ where the release CI expects it.
OutputDir=..\dist
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
ChangesEnvironment=yes
; Shared across BOTH variant installers — blocks a concurrent classic+dotnet setup race (hardened fix).
SetupMutex=ClavitySetupMutex

[Files]
Source: "..\publish\{#ExeName}"; DestDir: "{app}"; Flags: ignoreversion
; Phase 3: the golden-header SEED baseline (installer-seeded into %USERPROFILE%\.clavity\golden-header.seed.md
; post-install). Unconditional — the SEED always ships with this installer.
Source: "..\..\seed\golden-header.md"; DestDir: "{app}\seed"; Flags: ignoreversion
Source: "marketplace.install.json"; DestDir: "{app}\.claude-plugin"; DestName: "marketplace.json"; Flags: ignoreversion
Source: "..\..\installer\_shared\register-plugin.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\plugin\*"; DestDir: "{app}\plugins\clavity"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "agy-mcp-bridge"
; Opt-in bridge tree (gated). Staged WITHOUT the secret; exclude regenerable + secret artifacts defensively.
Source: "..\plugin\agy-mcp-bridge\*"; DestDir: "{app}\plugins\clavity\agy-mcp-bridge"; \
  Flags: ignoreversion recursesubdirs createallsubdirs; Tasks: install_bridge; \
  Excludes: ".env,.venv,__pycache__,.agent,*.pyc"
; Bridge first-run doc (gated with the bridge).
Source: "..\..\clavity-classic\installer\clavity-classic-bridge-README-FIRST.md"; DestDir: "{app}\plugins\clavity\agy-mcp-bridge"; \
  DestName: "README-FIRST.md"; Flags: ignoreversion; Tasks: install_bridge

[Tasks]
Name: "addtopath"; Description: "Add clavity-ls to PATH"; Flags: checkedonce
; Opt-in bridge add-on (default OFF) — value FIRST, prerequisite second (UX round).
Name: "install_bridge"; Flags: unchecked; \
  Description: "Install the Antigravity bridge — let Claude hand off a coding task for Antigravity to do autonomously in an isolated worktree (delegate_to_antigravity). Needs Python 3.10+ and uv."

[Registry]
; Per-user PATH APPEND (never prepend) when the task is selected (security: PATH hygiene).
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; \
  ValueData: "{olddata};{app}"; Tasks: addtopath; Check: NeedsAddPath('{app}')

[Code]
#include "..\..\installer\_shared\golden-header-data.iss"
#include "..\..\installer\_shared\claude-running.iss"
#include "..\..\installer\_shared\path-scan.iss"

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

{ --- Component E: refuse to install if the CLASSIC variant is present (mutual exclusion). --- }

function ClassicClavityOnPath(var FoundPath: string): Boolean;
var
  PathExt, Dir, Ext, Rest, Exts, Candidate: string;
  SemiPos: Integer;
begin
  { In-process PATH scan — NO `where` subprocess. Spawning a child with redirected handles inside the installer's
    hidden, non-interactive Exec deadlocked the silent install (agy consults req-djlnh6yfta8k / req-djlo798boabs;
    the latter confirmed via CI log that the hang was this very `where clavity` Exec). The .NET side was fixed the
    same way (AgentDetection.OnRealPath). An in-process scan can't fail to launch, so there is no "probe failed"
    case to handle. Matches the EXACT `clavity` stem (the classic Rust binary) + each PATHEXT, NOT `clavity-ls.exe`. }
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
        Candidate := Dir + 'clavity' + Ext;
        if FileExists(Candidate) then
        begin
          FoundPath := Candidate;
          Result := True;
        end;
      end;
    end;
  end;
end;

function ClassicRegistered(): Boolean;
begin
  { The classic installer (follow-on Task 7.1) sets this marker; refuse if present. }
  Result := RegKeyExists(HKCU, 'Software\clavity\classic');
end;

function InitializeSetup(): Boolean;
var
  FoundPath: string;
begin
  Result := True;
  if ClaudeIsRunning() then
  begin
    SuppressibleMsgBox('Claude Code is running. Close it COMPLETELY before installing clavity-dotnet — a '
      + 'running Claude overwrites the plugin registration and leaves it unregistered. Quit Claude Code, '
      + 'then run this setup again.', mbCriticalError, MB_OK, IDOK);
    Result := False;
    exit;
  end;
  if ClassicClavityOnPath(FoundPath) then
  begin
    SuppressibleMsgBox('clavity (classic) is already installed at:' + #13#10 + FoundPath + #13#10#13#10 +
      'clavity-dotnet and clavity classic cannot be installed together. Remove the classic install first ' +
      '(run `cargo uninstall clavity`, or use its uninstaller), then run this setup again.',
      mbCriticalError, MB_OK, IDOK);
    Result := False;
    exit;
  end;
  if ClassicRegistered() then
  begin
    SuppressibleMsgBox('clavity (classic) is registered on this machine. Uninstall it first, then run this setup again.',
      mbCriticalError, MB_OK, IDOK);
    Result := False;
  end;
end;

{ --- Component B/D: refuse to install over a live pairing session (the --mcp host holds this mutex, Task 2.4). --- }

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if CheckForMutexes('Local\ClavityMcpRunning') then
    Result := 'A live Claude pairing session (clavity-ls --mcp) is running. Close it, then run this setup again.'
  else if ClaudeIsRunning() then
    Result := 'Claude Code is running. Close it completely, then run this setup again — a running Claude '
      + 'overwrites the plugin registration and leaves it unregistered.';
end;

{ --- Install: register the plugin AFTER files are placed, and SURFACE a failure (UX: no false "Success"). --- }

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    if not Exec(ExpandConstant('{app}\{#ExeName}'), 'install --agent all', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
      SuppressibleMsgBox('clavity-ls could not be launched to register the plugin. Finish manually by running:' + #13#10 +
        ExpandConstant('{app}\{#ExeName}') + ' install --agent all', mbError, MB_OK, IDOK)
    else if ResultCode <> 0 then
      SuppressibleMsgBox('clavity-ls plugin registration reported a problem (exit code ' + IntToStr(ResultCode) + ').' + #13#10 +
        'Open a terminal and re-run:  clavity-ls install --agent all', mbError, MB_OK, IDOK);
    { C4/O1: shared seeding function (installer/_shared/golden-header-data.iss), now native FileCopy.
      NON-FATAL: the plugin is registered and fully works without the pre-seeded baseline (agy-curate
      writes the growth header on its first run). A seed hiccup must NOT roll back a good registration
      (the old rollback is exactly what blocked a real user's install) — just surface the manual step. }
    if not SeedGoldenHeader(ExpandConstant('{app}')) then
      SuppressibleMsgBox('clavity-dotnet is installed and registered, but the golden-header baseline could ' +
        'not be pre-seeded (non-blocking). Add it any time by copying' + #13#10 +
        ExpandConstant('{app}\seed\golden-header.md') + '  to  ' +
        GoldenHeaderDataDir() + '\golden-header.seed.md',
        mbInformation, MB_OK, IDOK);
    if WizardIsTaskSelected('install_bridge') then
    begin
      BridgeDir := ExpandConstant('{app}\plugins\clavity\agy-mcp-bridge');
      if StemOnPath('uv', UvPath) then
      begin
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
  end
  else if CurStep = ssDone then
    SuppressibleMsgBox('clavity-dotnet is installed. Open a terminal (PowerShell) and run:' + #13#10 +
      '  clavity-ls start C:\path\to\your\project', mbInformation, MB_OK, IDOK);
end;

{ --- Uninstall: gate on the agent-removal exit code BEFORE any files are deleted (Component B; [UninstallRun] can't abort). --- }

function InitializeUninstall(): Boolean;
var
  ResultCode: Integer;
  Params: string;
  ExePath: string;
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
  { Refuse if a live pairing session (clavity-ls --mcp) holds the exe — otherwise Exec + the file deletion break
    mid-uninstall on the locked binary, leaving a partial/broken uninstall (agy review req-djljyi3pj7e8). }
  if CheckForMutexes('Local\ClavityMcpRunning') then
  begin
    SuppressibleMsgBox('A live Claude pairing session (clavity-ls --mcp) is running. Close it before uninstalling clavity-dotnet.',
      mbError, MB_OK, IDOK);
    Result := False;
    exit;
  end;
  ExePath := ExpandConstant('{app}\{#ExeName}');
  { F15: if the exe is gone (AV quarantine / manual delete), fail OPEN so Add/Remove Programs can still clean the dir. }
  if not FileExists(ExePath) then
    exit;

  { Silent uninstall defaults to KEEPING data (IDNO) — never delete user data without an explicit answer. }
  RemoveConfig := SuppressibleMsgBox('Also remove clavity''s data (the .clavity folder in your profile: the golden-header seed + learned growth)?' + #13#10 +
    'Choose No to keep it for a future reinstall.', mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES;

  if RemoveConfig then
    Params := 'uninstall --agent all --purge-data'
  else
    Params := 'uninstall --agent all';

  if not Exec(ExePath, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    Result := SuppressibleMsgBox('Could not run clavity-ls to remove the plugin from your agents. Uninstall anyway?',
      mbError, MB_YESNO or MB_DEFBUTTON2, IDYES) = IDYES;
    exit;
  end;
  if ResultCode <> 0 then
    Result := SuppressibleMsgBox('Removing the clavity plugin from one or more agents FAILED (exit code ' + IntToStr(ResultCode) + ').' + #13#10 +
      'Uninstall anyway (the plugin stays registered in that agent)?', mbError, MB_YESNO or MB_DEFBUTTON2, IDYES) = IDYES;
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
  ResultCode: Integer;
  HeaderDir: string;
begin
  if CurUninstallStep = usUninstall then
  begin
    { Zombie-header fix (spec data-lifecycle): on KEEP, step the driver-SEEDED baseline aside to .backup so a
      future reinstall installs a fresh baseline rather than auto-injecting a frozen one. Safe for seed.md
      precisely BECAUSE the installer re-seeds it — nothing of the user's is lost, and .backup never
      auto-restores. Skipped on purge (the whole data dir goes via clavity-ls --purge-data).
      The legacy pre-split golden-header.md is deliberately NOT backed up: it is the USER's own accumulated
      wisdom, is never re-seeded, and renaming it drops it out of the driver's migration read path
      permanently. The dialog says "keep", so it stays where the driver reads it. agy-autotrain applies the
      same reasoning to its growth.md. }
    if not RemoveConfig then
    begin
      { C6: back up ONLY driver-owned files — seed.md + its .sha256 sidecar. growth.md is agy-autotrain's
        file; touching it here was the pre-cohesion bug (Failure mode H) this design fixes — it is
        removed/backed up ONLY by agy-autotrain's own uninstall. }
      HeaderDir := GoldenHeaderDataDir();   { honors CLAVITY_GOLDEN_HEADER; see golden-header-data.iss }
      BackupDataFile(HeaderDir + '\golden-header.seed.md');
      BackupDataFile(HeaderDir + '\golden-header.seed.md.sha256');
    end;
    { Bridge .env (live secret): gated on the keep/purge answer. On purge, clavity-ls --purge-data already removes it, but we can be safe. }
  end
  else if CurUninstallStep = usPostUninstall then
    RemoveFromUserPath(ExpandConstant('{app}'));
end;

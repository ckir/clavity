; Inno Setup script for clavity-dotnet. Build with: ISCC.exe installer\clavity-dotnet.iss
; Expects (produced by the release CI, Task 3.3):
;   ..\publish\clavity-ls.exe        — single-file publish of Clavity.Cli
;   ..\.claude-plugin\marketplace.json  — the marketplace root manifest (committed in-repo)
;   ..\plugins\clavity-dotnet\*       — the core plugin (referenced as ./plugins/clavity-dotnet by the manifest)
;   ..\plugins\agy-autotrain\* , ..\plugins\commonmemory\*  — optional add-ons (shipped; install gated by Phase 4 [Tasks])
;
; Layout note (2.2<->3.1 coupling): clavity-ls resolves marketplaceRoot = {app} and pluginDir =
; {app}\plugins\clavity-dotnet. So the marketplace.json + the plugins/ tree ship UNDER {app}, matching the
; manifest's ./plugins/<name> source paths. claude installs via the marketplace; agy installs the local dir.

#define AppName "clavity-dotnet"
#define AppVersion "0.1.0"
#define ExeName "clavity-ls.exe"

[Setup]
; Stable AppId so version upgrades replace in place (do NOT change between releases).
AppId={{B7E4B2A1-9C3D-4F5E-8A1B-2C3D4E5F6A7B}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=clavity
DefaultDirName={localappdata}\Programs\clavity-dotnet
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=clavity-dotnet-setup
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
Source: "..\.claude-plugin\marketplace.json"; DestDir: "{app}\.claude-plugin"; Flags: ignoreversion
Source: "..\plugins\clavity-dotnet\*"; DestDir: "{app}\plugins\clavity-dotnet"; Flags: ignoreversion recursesubdirs createallsubdirs
; Optional add-ons: shipped so the marketplace resolves, but only INSTALLED if the Phase 4 [Tasks] are ticked.
Source: "..\plugins\agy-autotrain\*"; DestDir: "{app}\plugins\agy-autotrain"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\plugins\commonmemory\*"; DestDir: "{app}\plugins\commonmemory"; Flags: ignoreversion recursesubdirs createallsubdirs

[Tasks]
Name: "addtopath"; Description: "Add clavity-ls to PATH"; Flags: checkedonce
; Phase 4 (Task 4.2) appends two default-OFF add-on tasks here: install-agy-autotrain, install-commonmemory.

[Registry]
; Per-user PATH APPEND (never prepend) when the task is selected (security: PATH hygiene).
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; \
  ValueData: "{olddata};{app}"; Tasks: addtopath; Check: NeedsAddPath('{app}')

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

{ --- Component E: refuse to install if the CLASSIC variant is present (mutual exclusion). --- }

function ClassicClavityOnPath(var FoundPath: string; var ProbeRan: Boolean): Boolean;
var
  ResultCode: Integer;
  Lines: TArrayOfString;
  TmpFile: string;
begin
  Result := False;
  FoundPath := '';
  { `where clavity` matches the EXACT `clavity` stem (the classic Rust binary), NOT our `clavity-ls.exe`. }
  TmpFile := ExpandConstant('{tmp}\clavity_where.txt');
  ProbeRan := Exec(ExpandConstant('{cmd}'), '/C where clavity > "' + TmpFile + '" 2>nul', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if ProbeRan then
  begin
    if (ResultCode = 0) and LoadStringsFromFile(TmpFile, Lines) and (GetArrayLength(Lines) > 0) then
    begin
      FoundPath := Trim(Lines[0]);
      Result := FoundPath <> '';
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
  ProbeRan: Boolean;
begin
  Result := True;
  if ClassicClavityOnPath(FoundPath, ProbeRan) then
  begin
    MsgBox('clavity (classic) is already installed at:' + #13#10 + FoundPath + #13#10#13#10 +
      'clavity-dotnet and clavity classic cannot be installed together. Remove the classic install first ' +
      '(run `cargo uninstall clavity`, or use its uninstaller), then run this setup again.',
      mbCriticalError, MB_OK);
    Result := False;
    exit;
  end;
  if not ProbeRan then
  begin
    { Probe couldn't run — let the user decide rather than silently risk a dual-install (agy review req-djljyi3pj7e8). }
    if MsgBox('Could not verify whether classic clavity is already installed (the check could not run).' + #13#10 +
      'Installing both variants together can corrupt your setup. Install anyway?',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDNO then
    begin
      Result := False;
      exit;
    end;
  end;
  if ClassicRegistered() then
  begin
    MsgBox('clavity (classic) is registered on this machine. Uninstall it first, then run this setup again.',
      mbCriticalError, MB_OK);
    Result := False;
  end;
end;

{ --- Component B/D: refuse to install over a live pairing session (the --mcp host holds this mutex, Task 2.4). --- }

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if CheckForMutexes('Local\ClavityMcpRunning') then
    Result := 'A live Claude pairing session (clavity-ls --mcp) is running. Close it, then run this setup again.';
end;

{ --- Install: register the plugin AFTER files are placed, and SURFACE a failure (UX: no false "Success"). --- }

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    if not Exec(ExpandConstant('{app}\{#ExeName}'), 'install --agent all', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
      MsgBox('clavity-ls could not be launched to register the plugin. Finish manually by running:' + #13#10 +
        ExpandConstant('{app}\{#ExeName}') + ' install --agent all', mbError, MB_OK)
    else if ResultCode <> 0 then
      MsgBox('clavity-ls plugin registration reported a problem (exit code ' + IntToStr(ResultCode) + ').' + #13#10 +
        'Open a terminal and re-run:  clavity-ls install --agent all', mbError, MB_OK);
  end
  else if CurStep = ssDone then
    MsgBox('clavity-dotnet is installed. Open a terminal (PowerShell) and run:' + #13#10 +
      '  clavity-ls start C:\path\to\your\project', mbInformation, MB_OK);
end;

{ --- Uninstall: gate on the agent-removal exit code BEFORE any files are deleted (Component B; [UninstallRun] can't abort). --- }

function InitializeUninstall(): Boolean;
var
  ResultCode: Integer;
  Params: string;
  ExePath: string;
begin
  Result := True;
  { Refuse if a live pairing session (clavity-ls --mcp) holds the exe — otherwise Exec + the file deletion break
    mid-uninstall on the locked binary, leaving a partial/broken uninstall (agy review req-djljyi3pj7e8). }
  if CheckForMutexes('Local\ClavityMcpRunning') then
  begin
    MsgBox('A live Claude pairing session (clavity-ls --mcp) is running. Close it before uninstalling clavity-dotnet.',
      mbError, MB_OK);
    Result := False;
    exit;
  end;
  ExePath := ExpandConstant('{app}\{#ExeName}');
  { F15: if the exe is gone (AV quarantine / manual delete), fail OPEN so Add/Remove Programs can still clean the dir. }
  if not FileExists(ExePath) then
    exit;

  RemoveConfig := MsgBox('Also remove clavity''s data (the .clavity folder in your profile: the golden-header)?' + #13#10 +
    'Choose No to keep it for a future reinstall.', mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;

  if RemoveConfig then
    Params := 'uninstall --agent all --purge-data'
  else
    Params := 'uninstall --agent all';

  if not Exec(ExePath, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    Result := MsgBox('Could not run clavity-ls to remove the plugin from your agents. Uninstall anyway?',
      mbError, MB_YESNO or MB_DEFBUTTON2) = IDYES;
    exit;
  end;
  if ResultCode <> 0 then
    Result := MsgBox('Removing the clavity plugin from one or more agents FAILED (exit code ' + IntToStr(ResultCode) + ').' + #13#10 +
      'Uninstall anyway (the plugin stays registered in that agent)?', mbError, MB_YESNO or MB_DEFBUTTON2) = IDYES;
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

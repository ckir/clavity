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
#define AppVersion "0.1.5"
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
; Optional add-ons (default OFF) — plain-English, value-driven labels (spec UX).
Name: "install_agy_autotrain"; Description: "Install agy-autotrain — lets the AI permanently learn your project's rules and stop repeating mistakes"; Flags: unchecked
Name: "install_commonmemory"; Description: "Install commonmemory — a shared notebook so Claude and agy share facts (needs the agentmemory MCP server)"; Flags: unchecked

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
    Result := 'A live Claude pairing session (clavity-ls --mcp) is running. Close it, then run this setup again.';
end;

{ --- Install: register the plugin AFTER files are placed, and SURFACE a failure (UX: no false "Success"). --- }

procedure InstallAddon(const Name: string);
var
  ResultCode: Integer;
begin
  // Install one optional add-on plugin from the app's plugins dir via clavity-ls (gated by the [Tasks] checkbox).
  if not Exec(ExpandConstant('{app}\{#ExeName}'), 'install --agent all --plugin ' + Name, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    SuppressibleMsgBox('Could not install the ' + Name + ' add-on. Install it later with:' + #13#10 +
      '  clavity-ls install --agent all --plugin ' + Name, mbError, MB_OK, IDOK)
  else if ResultCode <> 0 then
    SuppressibleMsgBox('The ' + Name + ' add-on reported a problem (exit code ' + IntToStr(ResultCode) + '). Re-run:' + #13#10 +
      '  clavity-ls install --agent all --plugin ' + Name, mbError, MB_OK, IDOK);
end;

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
  RemoveConfig := SuppressibleMsgBox('Also remove clavity''s data (the .clavity folder in your profile: the golden-header)?' + #13#10 +
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
  Header, Backup: string;
begin
  if CurUninstallStep = usUninstall then
  begin
    { Remove the optional add-ons from the agents too (best-effort — they may not be installed; not gated). }
    if FileExists(ExpandConstant('{app}\{#ExeName}')) then
    begin
      Exec(ExpandConstant('{app}\{#ExeName}'), 'uninstall --agent all --plugin agy-autotrain', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      Exec(ExpandConstant('{app}\{#ExeName}'), 'uninstall --agent all --plugin commonmemory', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;
    { Zombie-header fix (spec data-lifecycle): when KEEPING data (not --purge-data), rename golden-header.md ->
      .backup so a future reinstall does not auto-inject frozen wisdom. .backup does NOT auto-restore. Skipped on
      purge (the whole .clavity dir is deleted by clavity-ls --purge-data). NOTE: honors only the default path,
      not a CLAVITY_GOLDEN_HEADER override (rare edge). }
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
  end
  else if CurUninstallStep = usPostUninstall then
    RemoveFromUserPath(ExpandConstant('{app}'));
end;

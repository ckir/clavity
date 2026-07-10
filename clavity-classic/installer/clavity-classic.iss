; Inno Setup script for clavity-classic. Build with: ISCC.exe installer\clavity-classic.iss
; Expects (from scripts/build-classic-release.ps1 = the 7.8 recipe, run first):
;   ..\publish\clavity.exe              — the prebuilt Rust binary (single self-contained exe)
;   ..\publish\agy-mcp-bridge\*         — staged bridge RUNTIME whitelist (NO .env)
; Plus committed installer docs (..\installer\clavity-classic-*.md).
;
; Option A (minimal/honest): classic wires manually BY DESIGN — this installer does NOT register the
; agentmemory MCP or the GEMINI.md doorbell (guided-manual via the shipped docs + the Finished-page [Run]).

#define AppName "clavity-classic"
#define AppVersion "0.1.0"
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
  PsCmd, SrcPath, DestDir: string;
begin
  if CurStep = ssPostInstall then
  begin
    { Phase 3 parity: seed golden-header.seed.md from the bundled baseline with standard PowerShell (always
      available; no dependency on running the just-installed binary). Overwrites SEED only; never touches GROWTH.
      Unconditional — runs regardless of the bridge task. }
    SrcPath := ExpandConstant('{app}\seed\golden-header.md');
    { panel agy-R3-a: resolve the profile via Inno's %USERPROFILE% env constant (same as the zombie-header rename
      below), NOT PowerShell's $env:USERPROFILE — under any elevation the two can differ, silently seeding the wrong
      profile. (Written percent-style here because a literal Inno brace-constant inside a Pascal comment would
      prematurely close the comment.) }
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
      SuppressibleMsgBox('Could not seed the golden-header baseline. clavity still works; seed it later by copying' + #13#10 +
        ExpandConstant('{app}\seed\golden-header.md') + '  to  %USERPROFILE%\.clavity\golden-header.seed.md', mbInformation, MB_OK, IDOK)
    else if ResultCode <> 0 then
      SuppressibleMsgBox('Seeding the golden-header baseline reported a problem (exit code ' + IntToStr(ResultCode) + ').',
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
  { Option A: no clavity uninstall verb to run and no live-session mutex (classic has no long-running --mcp host),
    so this is just the data keep/purge decision. Enumerate the data classes it governs so the choice is informed:
    golden-header ALWAYS; the bridge API key ONLY when a post-install .env exists (opt-in, default-OFF). }
  Prompt := 'Also remove clavity''s data?' + #13#10#13#10 +
    '  - the golden-header wisdom (~\.clavity\: the seed baseline + learned growth)';
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

procedure BackupHeaderFile(const Header: string);
var
  Backup: string;
begin
  Backup := Header + '.backup';
  if FileExists(Header) then
  begin
    DeleteFile(Backup);
    RenameFile(Header, Backup);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  BridgeDir, EnvFile: string;
begin
  if CurUninstallStep = usUninstall then
  begin
    { Zombie-header fix (mirror dotnet): when KEEPING data (not purge), back up each golden-header file (the SEED
      baseline + learned GROWTH + any legacy flat file) -> .backup so a reinstall does not auto-inject frozen
      wisdom. .backup does NOT auto-restore. Skipped on purge. Default path only (CLAVITY_GOLDEN_HEADER override is rare). }
    if not RemoveConfig then
    begin
      BackupHeaderFile(ExpandConstant('{%USERPROFILE}\.clavity\golden-header.seed.md'));
      BackupHeaderFile(ExpandConstant('{%USERPROFILE}\.clavity\golden-header.growth.md'));
      BackupHeaderFile(ExpandConstant('{%USERPROFILE}\.clavity\golden-header.md'));  { legacy flat, if present }
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

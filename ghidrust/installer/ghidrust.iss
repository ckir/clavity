; Inno Setup script for ghidrust. Build: ISCC.exe installer\ghidrust.iss
; Expects (produced by the tool's build recipe / build-ghidrust.yml):
;   ..\publish\ghidrust.exe   — the tool's single-file binary
; Cohesive distribution model (docs/superpowers/specs/2026-07-11-cohesive-distribution-design.md,
; supersedes the two-channel note this replaced): this installer ships BOTH the binary AND its own
; plugin, self-registering a local scoped marketplace (clavity-ghidrust) against each detected
; agent. There is no remote-marketplace delivery path anymore.

#define AppName "ghidrust"
#define AppVersion "1.0.0"
#define ExeName "ghidrust.exe"

[Setup]
; Stable AppId so upgrades replace in place — GENERATE A FRESH GUID per tool (never reuse another tool's).
AppId={{270CC1D9-B3CF-4CD2-B9A4-738C99CE7397}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=clavity
LicenseFile=..\LICENSE
DefaultDirName={localappdata}\Programs\ghidrust
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=ghidrust-setup-{#AppVersion}
OutputDir=..\dist
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
ChangesEnvironment=yes
; O6: shared with ALL FIVE member installers (was dotnet+classic only). Defensive default — this
; plan could not live-verify whether the claude/agy CLIs serialize their own global-config writes
; (that needs a live two-terminal test against the real CLI, out of scope for a static plan), so it
; adds the cheap, already-proven mutex mechanism defensively rather than leaving the race open.
SetupMutex=ClavitySetupMutex

[Files]
Source: "..\publish\{#ExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "marketplace.install.json"; DestDir: "{app}\.claude-plugin"; DestName: "marketplace.json"; Flags: ignoreversion
Source: "..\plugin\*"; DestDir: "{app}\plugins\ghidrust"; Flags: ignoreversion recursesubdirs createallsubdirs

[Tasks]
Name: "addtopath"; Description: "Add ghidrust to PATH"; Flags: checkedonce

[Registry]
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; \
  ValueData: "{olddata};{app}"; Tasks: addtopath; Check: NeedsAddPath('{app}')

[Code]
#include "..\..\installer\_shared\plugin-registration.iss"

var
  GhidraPage: TInputDirWizardPage;

procedure InitializeWizard;
var
  Existing: string;
begin
  GhidraPage := CreateInputDirPage(wpSelectTasks,
    'Ghidra install location (optional)',
    'ghidrust needs Ghidra 12.1.2 and a JDK 21 at run time.',
    'Point to your Ghidra install root (the folder containing support\analyzeHeadless.bat). ' +
    'Leave blank to skip — you can set GHIDRA_INSTALL_DIR yourself later.',
    False, '');
  GhidraPage.Add('');
  Existing := GetEnv('GHIDRA_INSTALL_DIR');
  if Existing <> '' then
    GhidraPage.Values[0] := Existing;
end;

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

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    DeregisterMemberPluginOnUninstall('ghidrust', 'clavity-ghidrust');
  if CurUninstallStep = usPostUninstall then
    RemoveFromUserPath(ExpandConstant('{app}'));
end;

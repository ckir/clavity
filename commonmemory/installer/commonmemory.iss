; Inno Setup script for commonmemory (plugin-only member; no binary). Build with:
; ISCC.exe installer\commonmemory.iss
; Cohesive distribution model (docs/superpowers/specs/2026-07-11-cohesive-distribution-design.md):
; ships the commonmemory plugin folder + a scoped 1-entry marketplace.json, self-registering
; against each detected agent. Runtime dependency on the agentmemory MCP server is out of scope
; for this installer (be honest, do not auto-install it — matches the pre-cohesion add-on's UX).

#define AppName "commonmemory"
#define AppVersion "0.1.1"

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
  Excludes: "installer,dist,publish,.claude-plugin"

[Code]
#include "..\..\installer\_shared\claude-running.iss"
#include "..\..\installer\_shared\plugin-registration.iss"

function InitializeSetup(): Boolean;
begin
  Result := True;
  if ClaudeIsRunning() then
  begin
    SuppressibleMsgBox('Claude Code is running. Close it COMPLETELY before installing commonmemory — a '
      + 'running Claude overwrites the plugin registration and leaves it unregistered. Quit Claude Code, '
      + 'then run this setup again.', mbCriticalError, MB_OK, IDOK);
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

function InitializeUninstall(): Boolean;
begin
  Result := True;
  if ClaudeIsRunning() then
  begin
    SuppressibleMsgBox('Claude Code is running. Close it COMPLETELY before uninstalling — otherwise Claude '
      + 'restores the plugin registration on exit and then loads deleted files. Quit Claude Code, then '
      + 'uninstall again.', mbCriticalError, MB_OK, IDOK);
    Result := False;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    DeregisterMemberPluginOnUninstall('commonmemory', 'clavity-commonmemory');
end;

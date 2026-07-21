; Inno Setup script for commonmemory (plugin-only member; no binary). Build with:
; ISCC.exe installer\commonmemory.iss
; Cohesive distribution model (docs/superpowers/specs/2026-07-11-cohesive-distribution-design.md):
; ships the commonmemory plugin folder + a scoped 1-entry marketplace.json, self-registering
; against each detected agent. Runtime dependency on the agentmemory MCP server is out of scope
; for this installer (be honest, do not auto-install it — matches the pre-cohesion add-on's UX).

#define AppName "commonmemory"
#define AppVersion "0.2.1"

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
Source: "..\..\installer\_shared\register-plugin.ps1"; DestDir: "{app}"; Flags: ignoreversion
; Every pattern here is ANCHORED with a leading backslash, i.e. matched against the path relative to the
; Source root rather than by bare name. That is load-bearing twice over:
;
; 1. An UNANCHORED pattern matches at ANY DEPTH, and against DIRECTORY names as well as file names. That
;    is precisely how this line shipped a bug: the old `.claude-plugin` entry matched the directory and
;    dropped .claude-plugin\plugin.json from the payload entirely. Claude Code prefers that manifest over
;    the root plugin.json, so an UPGRADE could not overwrite a stale one — a 0.1.1 manifest survived a
;    0.2.1 install and re-registered the OLD version. Anchoring `\.claude-plugin\marketplace.json` drops
;    exactly the dev-only marketplace (it declares the `-dev` marketplace for local
;    `/plugin marketplace add`) and nothing else, so the manifest beside it ships and overwrites.
; 2. The same any-depth hazard applies to the plain words: unanchored, `installer`/`dist`/`publish` would
;    silently strip a future subdirectory of that name ANYWHERE in the plugin tree — e.g. a skill with an
;    `installer\` folder. Anchored, they only ever mean the three top-level dev folders they are meant to.
;
; The installed marketplace.json comes from the separate marketplace.install.json entry above, which has
; its own Source line and is unaffected by this exclude.
Source: "..\*"; DestDir: "{app}\plugins\commonmemory"; Flags: ignoreversion recursesubdirs createallsubdirs; \
  Excludes: "\installer,\dist,\publish,\.claude-plugin\marketplace.json"

[InstallDelete]
; Tombstone for a file this installer USED to ship and no longer does. Inno never deletes a file that has
; dropped out of the payload, so dropping it from [Files] is only half a removal — the copy already on disk
; survives every future upgrade untouched. Concretely: commonmemory 0.1.0 and 0.1.1 (shipped in clavity-v7
; through v10) excluded only "installer,dist,publish", so the blanket copy carried the DEV marketplace
; (..\.claude-plugin\marketplace.json) into the plugin tree. It declares a SECOND marketplace named
; `clavity-commonmemory-dev` whose `"source": "."` resolves inside the installed plugin folder, so a box
; upgraded from any of those releases offers the same plugin under two marketplace names. The exclude added
; later stopped shipping it but could not retract it; this line does.
; Runs before [Files], and names one exact file rather than the directory — the sibling plugin.json in that
; same directory is live payload and must survive.
Type: files; Name: "{app}\plugins\commonmemory\.claude-plugin\marketplace.json"

[Code]
#include "..\..\installer\_shared\claude-running.iss"
#include "..\..\installer\_shared\register-plugin-hash.iss"
#include "..\..\installer\_shared\register-invoke.iss"

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

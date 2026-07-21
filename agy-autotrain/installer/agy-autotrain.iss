; Inno Setup script for agy-autotrain (plugin-only member; no binary). Build with:
; ISCC.exe installer\agy-autotrain.iss
; Cohesive distribution model (docs/superpowers/specs/2026-07-11-cohesive-distribution-design.md):
; ships the agy-autotrain plugin folder + a scoped 1-entry marketplace.json, self-registering
; against each detected agent (Claude Code / agy). No binary, no download, no remote marketplace.

#define AppName "agy-autotrain"
#define AppVersion "0.2.1"

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
Source: "..\..\installer\_shared\register-plugin.ps1"; DestDir: "{app}"; Flags: ignoreversion
; agy-observations.md is EXCLUDED from the blanket copy below and seeded separately, `onlyifdoesntexist`.
; It is the agy-learn capture inbox: USER DATA that happens to live inside the plugin tree and accumulates
; between drains. The blanket copy is `ignoreversion` (= always overwrite), so without this split an UPGRADE
; silently replaces a user's accumulated observations with the shipped template — destroying the exact
; knowledge this plugin exists to collect, with no warning and no backup. A fresh install still gets the
; template; an upgrade leaves the live inbox alone. Verified 2026-07-20 against a real box holding 23
; uncurated entries. Excludes matches on FILENAME (no path separator), so it applies wherever the file sits.
Source: "..\*"; DestDir: "{app}\plugins\agy-autotrain"; Flags: ignoreversion recursesubdirs createallsubdirs; \
  Excludes: "installer,dist,publish,agy-observations.md"
; uninsneveruninstall as well as onlyifdoesntexist: without it the uninstaller deletes this file like any
; other installed file, so a KEEP-DATA uninstall would preserve growth.md (which lives outside the app dir)
; while silently destroying the pending inbox — the same asymmetry the growth.md handling below exists to
; avoid. Note the remaining gap: a PURGE-data uninstall does not remove it either, so the purge prompt below
; covers growth.md only. Leaving a file behind is the recoverable failure; deleting one is not.
Source: "..\knowledge\agy-observations.md"; DestDir: "{app}\plugins\agy-autotrain\knowledge"; Flags: onlyifdoesntexist uninsneveruninstall

[Code]
#include "..\..\installer\_shared\claude-running.iss"
#include "..\..\installer\_shared\register-plugin-hash.iss"
#include "..\..\installer\_shared\register-invoke.iss"
#include "..\..\installer\_shared\golden-header-data.iss"

var
  RemoveGrowth: Boolean;

function InitializeSetup(): Boolean;
begin
  Result := True;
  if ClaudeIsRunning() then
  begin
    SuppressibleMsgBox('Claude Code is running. Close it COMPLETELY before installing agy-autotrain — a '
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
  if ClaudeIsRunning() then
  begin
    SuppressibleMsgBox('Claude Code is running. Close it COMPLETELY before uninstalling — otherwise Claude '
      + 'restores the plugin registration on exit and then loads deleted files. Quit Claude Code, then '
      + 'uninstall again.', mbCriticalError, MB_OK, IDOK);
    Result := False;
    exit;
  end;
  { C6: this member owns growth.md — offer the same keep/purge choice the drivers offer for their
    own seed.md. Silent uninstall defaults to KEEP (IDNO) — never delete user data without an
    explicit answer. }
  RemoveGrowth := SuppressibleMsgBox('Also remove agy-autotrain''s learned data?' + #13#10#13#10 +
    '  - the learned golden-header growth (~\.clavity\golden-header.growth.md and its .sha256)' + #13#10 +
    '  - any observations captured but not yet drained (knowledge\agy-observations.md)' + #13#10#13#10 +
    'Choose No to keep both for a future reinstall.',
    mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  GrowthFile, InboxFile: string;
begin
  if CurUninstallStep = usUninstall then
  begin
    DeregisterMemberPluginOnUninstall('agy-autotrain', 'clavity-agy-autotrain');
    GrowthFile := ExpandConstant('{%USERPROFILE}\.clavity\golden-header.growth.md');
    if RemoveGrowth then
    begin
      if FileExists(GrowthFile) then DeleteFile(GrowthFile);
      if FileExists(GrowthFile + '.sha256') then DeleteFile(GrowthFile + '.sha256');
      { The capture inbox is marked uninsneveruninstall so a KEEP-data uninstall cannot destroy it.
        That flag is unconditional, so on an explicit PURGE it must be removed here or the user's
        consent is ignored in the other direction — the same promise-not-kept failure the classic
        member's purge branch was just fixed for. It lives inside the install dir, unlike growth.md. }
      InboxFile := ExpandConstant('{app}\plugins\agy-autotrain\knowledge\agy-observations.md');
      if FileExists(InboxFile) then DeleteFile(InboxFile);
    end;
    { KEEP (RemoveGrowth=False): leave growth.md exactly where it is. It lives outside the install dir,
      so Inno never auto-removes it, and (unlike a driver's seed.md) it is never re-seeded on install, so
      is nothing to step aside for. Renaming it to .backup here would drop it from the driver's read
      path (~\.clavity\golden-header.growth.md) on a keep-data uninstall — silently losing the user's
      learned wisdom from the active path. So on keep, do nothing. }
  end;
end;

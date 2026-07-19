{ ============================================================================
  installer/_shared/claude-running.iss
  Shared refuse-guard detection: is Claude Code (claude.exe) currently running?
  Include this file in a member's [Code] section, then call ClaudeIsRunning() from InitializeSetup and abort
  if True — a running Claude reconciles its plugin registry from settings.json and CLOBBERS the installer's
  registration writes (verified 2026-07-13 spike; agy-concurred fix). Process name = claude.exe (spike Q1).

  Detection = `tasklist` via SAFE shell-file redirection (cmd /C tasklist ... > tmp 2>&1), the SAME
  mechanism the deleted plugin-registration.iss's ExecCaptured used — NOT in-process handle redirection,
  which deadlocked the silent install (see path-scan.iss StemOnPath history). tasklist ships on every
  Windows. Fail-OPEN: if the probe cannot run, do NOT block the install (the read-back backstop + the
  owner canary cover the residual). Self-contained: depends on no other shared file.
============================================================================ }
function ClaudeIsRunning(): Boolean;
var
  TmpDir, TmpFile, Params, Blob: string;
  ResultCode, i: Integer;
  Lines: TArrayOfString;
begin
  Result := False;
  { Use %TEMP% (GetEnv), NOT the Inno tmp constant: that dir may not be created yet in early hooks
    (InitializeSetup / InitializeUninstall), which would make the redirection target a missing dir and the
    probe fail-OPEN (silently return False), neutralizing the guard. %TEMP% is a standard env var present
    from process start in every hook. }
  TmpDir := GetEnv('TEMP');
  if TmpDir = '' then TmpDir := GetEnv('TMP');
  TmpFile := TmpDir + '\clavity-claudecheck-' + IntToStr(Random(1000000)) + '.txt';
  Params := '/C tasklist /FI "IMAGENAME eq claude.exe" /NH > "' + TmpFile + '" 2>&1';
  if Exec(ExpandConstant('{cmd}'), Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    if LoadStringsFromFile(TmpFile, Lines) then
    begin
      Blob := '';
      for i := 0 to GetArrayLength(Lines) - 1 do
        Blob := Blob + Lines[i] + #10;
      Result := Pos('claude.exe', Lowercase(Blob)) > 0;
    end;
  DeleteFile(TmpFile);
end;

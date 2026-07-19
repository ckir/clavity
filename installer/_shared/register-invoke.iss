{ ============================================================================
  installer/_shared/register-invoke.iss
  THIN Inno shell over the single source of truth installer/_shared/register-plugin.ps1 (decision D2).
  Re-implements the SAME public signatures the deleted plugin-registration.iss exposed
  (RegisterMemberPlugin / DeregisterMemberPluginOnUninstall / RollbackMemberPlugin / ReportRegistrationOutcome)
  so member .iss call sites are unchanged — but the bodies SHELL the .ps1 and parse its fixed machine
  contract (exit 0/2/3/4 + "AGENT <name> OK|FAIL <reason>" lines). No CLI vectors live here.

  Requires (member must also #include, BEFORE this file):
    - claude-running.iss    (ClaudeIsRunning — the outer running-Claude gate stays .iss-level)
    - register-plugin-hash.iss  (#define ExpectedRegisterPs1Sha256 — uninstall tamper check)
  Member must ship register-plugin.ps1 into the app dir via [Files].
  (Inno constant names are written WITHOUT their surrounding braces in these comments on purpose.)
============================================================================ }

{ ---- build the pinned 5.1 interpreter path via the sysnative constant (NOT sys): Inno's setup process is
  32-bit, so the sys constant would resolve to SysWOW64 (32-bit PS under WOW64 redirection). sysnative is
  unconditionally the native System32 and degrades safely on a true 32-bit OS (§3.5). ---- }
function PwshExePath(): string;
begin
  Result := ExpandConstant('{sysnative}\WindowsPowerShell\v1.0\powershell.exe');
end;

{ ---- double a single trailing backslash before the closing quote: CommandLineToArgvW reads \" as an
  escaped literal quote, so -AppDir "C:\" would swallow the closing quote AND the rest of the line
  (measured 2026-07-19). "C:\\" yields C:\ correctly (§3.5). ---- }
function QuoteArg(const S: string): string;
var
  V: string;
begin
  V := S;
  if (Length(V) > 0) and (V[Length(V)] = '\') then
    V := V + '\';
  Result := '"' + V + '"';
end;

{ ---- native exact-prefix slice (Inno Pascal has no regex). Reads the OK/FAIL token from the FIRST
  "AGENT <agent> " record. Binds mid-line matches out by anchoring at position 1 (NOT Pos(), which would
  reopen the newline-forge hole the registrar already closes at the source, §3.1.1). ---- }
function AgentLineVerdict(const Lines: TArrayOfString; const AgentName: string; var Found: Boolean): Boolean;
var
  i: Integer;
  Prefix, Line, Rest, Token: string;
begin
  Result := False;
  Found := False;
  Prefix := 'AGENT ' + AgentName + ' ';
  for i := 0 to GetArrayLength(Lines) - 1 do
  begin
    Line := Lines[i];
    if (Length(Line) >= Length(Prefix)) and (Copy(Line, 1, Length(Prefix)) = Prefix) then
    begin
      Found := True;
      Rest := Trim(Copy(Line, Length(Prefix) + 1, Length(Line)));   { "OK" or "FAIL <reason>" — Trim strips a trailing CR from the capture }
      if Pos(' ', Rest) > 0 then Token := Copy(Rest, 1, Pos(' ', Rest) - 1) else Token := Rest;
      Result := (Trim(Token) = 'OK');   { exact token compare, whitespace-hardened (F3) }
      exit;   { bind the FIRST matching record }
    end;
  end;
end;

{ ---- core: shell register-plugin.ps1 for one verb + agent-selection, capture + Log its output, parse the
  contract. Returns the launch-ok boolean (False = could not even launch = total failure per §3.1.1). ---- }
function ExecRegisterScript(const Verb, AppDir, PluginName, MarketplaceName, AgentSel: string;
  var RegisteredClaude, RegisteredAgy, AnyDetected, AnySucceeded: Boolean;
  var ExitCode: Integer): Boolean;
var
  TmpDir, TmpFile, Ps1Path, ScriptArgs, CmdParams, Blob, VerbFlag: string;
  Lines: TArrayOfString;
  i, LaunchAttempt: Integer;
  fc, fa, Launched: Boolean;
begin
  RegisteredClaude := False; RegisteredAgy := False; AnyDetected := False; AnySucceeded := False;
  ExitCode := 3;   { conservative default: total failure until proven otherwise }

  Ps1Path := ExpandConstant('{app}\register-plugin.ps1');
  TmpDir := GetEnv('TEMP'); if TmpDir = '' then TmpDir := GetEnv('TMP');
  TmpFile := TmpDir + '\clavity-reg-' + IntToStr(Random(1000000)) + '.log';

  if Verb = 'uninstall' then VerbFlag := '-Uninstall' else VerbFlag := '-Install';
  ScriptArgs := VerbFlag +
    ' -PluginName ' + QuoteArg(PluginName) +
    ' -MarketplaceName ' + QuoteArg(MarketplaceName) +
    ' -AppDir ' + QuoteArg(AppDir) +
    ' -Agent ' + AgentSel;

  { cmd /C ""<pwsh>" ... > "tmp" 2>&1"  — the mandated file-redirection wrapper (§3.5). The outer ""..."" pair
    satisfies cmd's "strip first & last quote" rule so a quoted program path with spaces launches. }
  CmdParams := '/C ""' + PwshExePath() + '" -NoProfile -ExecutionPolicy Bypass -File "' + Ps1Path + '" ' +
    ScriptArgs + ' > "' + TmpFile + '" 2>&1"';

  { Check the Exec BOOLEAN before trusting ExitCode: a launch failure returns False and leaves ExitCode at
    its init 0 (§3.1.1). We treat any launch failure as total failure. AV scan-on-write can transiently lock
    the freshly-written .ps1 (or cmd/pwsh image) so the launch itself fails; retry ONLY the launch-False path
    (never a non-zero registrar exit, which is a real result) up to 3x with a short backoff (§7). }
  LaunchAttempt := 0;
  Launched := False;
  while (not Launched) and (LaunchAttempt < 3) do
  begin
    LaunchAttempt := LaunchAttempt + 1;
    Launched := Exec(ExpandConstant('{cmd}'), CmdParams, '', SW_HIDE, ewWaitUntilTerminated, ExitCode);
    if (not Launched) and (LaunchAttempt < 3) then Sleep(2000);
  end;
  if not Launched then
  begin
    Log('register-plugin.ps1 could not be launched after ' + IntToStr(LaunchAttempt) + ' attempt(s).');
    DeleteFile(TmpFile);
    Result := False;
    ExitCode := 3;
    exit;
  end;
  Result := True;

  Blob := '';
  if LoadStringsFromFile(TmpFile, Lines) then
    for i := 0 to GetArrayLength(Lines) - 1 do
      Blob := Blob + Lines[i] + #13#10;
  { STDOUT captured to tmp does NOT reach Setup Log on its own — Log() it explicitly before deleting (§7). }
  Log('register-plugin.ps1 [' + Verb + ' ' + PluginName + '] exit=' + IntToStr(ExitCode) + ' output:' + #13#10 + Blob);
  DeleteFile(TmpFile);

  { Map exit codes with an EXPLICIT default-fail arm: any unmapped value (1 = throw, 9009 = pwsh not found,
    or anything else) is total failure, never a silent no-op/success (§3.1.1). }
  case ExitCode of
    0: begin AnyDetected := True; AnySucceeded := True;  end;   { all detected ok }
    2: begin AnyDetected := True; AnySucceeded := True;  end;   { partial: >=1 ok }
    3: begin AnyDetected := True; AnySucceeded := False; end;   { all detected failed }
    4: begin AnyDetected := False; AnySucceeded := False; end;  { none detected }
  else
    begin AnyDetected := True; AnySucceeded := False; end;     { DEFAULT-FAIL — unmapped code }
  end;

  { Per-agent booleans from the AGENT lines (for classic's selective rollback fidelity). }
  RegisteredClaude := AgentLineVerdict(Lines, 'claude', fc) and fc;
  RegisteredAgy    := AgentLineVerdict(Lines, 'agy', fa) and fa;
end;

{ ---- top-level install orchestration (same signature as the deleted Pascal). ---- }
procedure RegisterMemberPlugin(const AppDir, PluginName, MarketplaceName: string;
  var RegisteredClaude, RegisteredAgy, AnyDetected, AnySucceeded: Boolean; var Report: string);
var
  ExitCode: Integer;
begin
  ExecRegisterScript('install', AppDir, PluginName, MarketplaceName, 'all',
    RegisteredClaude, RegisteredAgy, AnyDetected, AnySucceeded, ExitCode);
  Report := 'register-plugin.ps1 exit=' + IntToStr(ExitCode) +
    ' (claude=' + IntToStr(Ord(RegisteredClaude)) + ' agy=' + IntToStr(Ord(RegisteredAgy)) + ')';
end;

{ ---- install-time rollback: selectively deregister ONLY the agents this run registered (per-agent
  fidelity, §3.1.1). Files still present in ssPostInstall (pre-purge). ---- }
procedure RollbackMemberPlugin(const PluginName, MarketplaceName: string; RegisteredClaude, RegisteredAgy: Boolean);
var
  rc, ra, ad, asuc: Boolean; ec: Integer;
begin
  if RegisteredClaude then
    ExecRegisterScript('uninstall', '', PluginName, MarketplaceName, 'claude', rc, ra, ad, asuc, ec);
  if RegisteredAgy then
    ExecRegisterScript('uninstall', '', PluginName, MarketplaceName, 'agy', rc, ra, ad, asuc, ec);
end;

{ ---- uninstall-time deregistration: re-detect live (no persisted per-agent memory across the process
  boundary — the script's -Agent all re-detects). Verify the pinned hash BEFORE exec (LPE mitigation);
  a mismatch skips exec (fail-open, but never run a tampered script). ---- }
procedure DeregisterMemberPluginOnUninstall(const PluginName, MarketplaceName: string);
var
  rc, ra, ad, asuc: Boolean; ec: Integer; Ps1Path, Actual: string;
begin
  Ps1Path := ExpandConstant('{app}\register-plugin.ps1');
  if not FileExists(Ps1Path) then
  begin
    Log('register-plugin.ps1 absent at uninstall — skipping deregistration (fail-open).');
    exit;
  end;
  Actual := GetSHA256OfFile(Ps1Path);
  if CompareText(Actual, '{#ExpectedRegisterPs1Sha256}') <> 0 then
  begin
    Log('register-plugin.ps1 SHA-256 mismatch (tamper?) — refusing to exec. Expected {#ExpectedRegisterPs1Sha256}, got ' + Actual);
    exit;   { fail-open deregistration; never run a tampered script }
  end;
  ExecRegisterScript('uninstall', ExpandConstant('{app}'), PluginName, MarketplaceName, 'all', rc, ra, ad, asuc, ec);
end;

{ ---- shared install-time reporting: partial failure is REPORTED, not rolled back, at the registration step
  (only the golden-header rollback path reverses a registration). Uses the returned booleans — does NOT
  re-detect (detection now lives in the PS registrar). ---- }
procedure ReportRegistrationOutcome(AnyDetected, AnySucceeded, RegisteredClaude, RegisteredAgy: Boolean; const Report: string);
begin
  if not AnyDetected then
    SuppressibleMsgBox('No compatible agent (Claude Code / agy) found on this machine. Install ' +
      'Claude Code or agy, then re-run this setup.', mbError, MB_OK, IDOK)
  else if not AnySucceeded then
    SuppressibleMsgBox('Plugin registration failed for every detected agent:' + #13#10 + Report,
      mbError, MB_OK, IDOK)
  else if (not RegisteredClaude) or (not RegisteredAgy) then
    SuppressibleMsgBox('Plugin registered, but a partial failure may have occurred (not rolled back):'
      + #13#10 + Report, mbInformation, MB_OK, IDOK);
end;

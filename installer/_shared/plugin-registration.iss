{ ============================================================================
  installer/_shared/plugin-registration.iss
  Shared Inno [Code] primitives for the cohesive-distribution model (2026-07-11 design, C1/C5/C9/
  O1/O6). #include this file INSIDE a product's own [Code] section (right after the [Code] header,
  before that product's own procedures). Every caller passes its OWN AppDir/PluginName/
  MarketplaceName — this file holds no per-product constants.

  CLI ARGUMENT VECTORS ARE VERBATIM FROM THE ORACLE
  (clavity-dotnet/src/Clavity.Ls/Install/PluginInstaller.cs, lines 17-45):
    claude plugin marketplace add <AppDir> --scope user
    claude plugin install <PluginName>@<MarketplaceName> --scope user
    agy    plugin install <AppDir>\plugins\<PluginName>
    claude|agy plugin uninstall <PluginName>
  PLUS one call this design ADDS that the oracle never issued (C6 — closing failure mode A1):
    claude plugin marketplace remove <MarketplaceName>
  (agy has no marketplace concept, so there is nothing extra to remove for it on uninstall.)

  IDEMPOTENCY IS STRUCTURAL (Finding-4), not output-parsed: RegisterClaude/RegisterAgy do a
  best-effort REMOVE of any prior registration (swallowing its result) BEFORE add/install, then
  treat the add/install exit codes normally. There is NO "already registered" substring heuristic
  to get wrong across CLI-wording changes.
============================================================================ }

{ ---- generic: is Stem[+PATHEXT] resolvable on PATH? (moved here verbatim from clavity-classic.iss
  StemOnPath — same in-process technique used by the mutual-exclusion scans: a child process with
  redirected handles inside a hidden, non-interactive Exec deadlocked the silent install; see
  clavity-classic.iss's StemOnPath comment history. Now ALSO used below for agent detection.) ---- }
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

{ ---- agent detection: present iff its CLI resolves on PATH OR its config dir exists (mirrors
  Clavity.Ls.Install.AgentDetection.IsPresent exactly — the C# oracle for the non-Inno installer). ---- }
function ClaudePresent(): Boolean;
var
  FoundPath: string;
begin
  Result := StemOnPath('claude', FoundPath) or DirExists(ExpandConstant('{%USERPROFILE}\.claude'));
end;

function AgyPresent(): Boolean;
var
  FoundPath: string;
begin
  Result := StemOnPath('agy', FoundPath) or DirExists(ExpandConstant('{%USERPROFILE}\.gemini'));
end;

{ ---- idempotent-tolerant Exec wrapper: capture combined stdout+stderr via a temp file (Inno's
  Exec has no built-in output-capture primitive). ---- }
function ExecCaptured(const Exe, Params, WorkDir: string; var ResultCode: Integer; var Output: string): Boolean;
var
  TmpFile: string;
  Lines: TArrayOfString;
  i: Integer;
begin
  TmpFile := ExpandConstant('{tmp}') + '\clavity-exec-' + IntToStr(Random(1000000)) + '.log';
  Result := Exec(ExpandConstant('{cmd}'), '/C ' + Exe + ' ' + Params + ' > "' + TmpFile + '" 2>&1',
    WorkDir, SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Output := '';
  if LoadStringsFromFile(TmpFile, Lines) then
    for i := 0 to GetArrayLength(Lines) - 1 do
      Output := Output + Lines[i] + #13#10;
  DeleteFile(TmpFile);
end;

{ ---- register ONE agent's plugin. Idempotent BY CONSTRUCTION (Finding-4): best-effort remove of
  any prior registration (result swallowed), THEN add/install with normal exit-code handling. Returns
  True on success. AppDir is the installer's app directory; PluginName/MarketplaceName are THIS installer's
  own unique values (C9). ---- }
function RegisterClaude(const AppDir, PluginName, MarketplaceName: string; var Detail: string): Boolean;
var
  ResultCode: Integer;
  Output: string;
begin
  { remove-then-add: pre-clean any prior registration; a first-time install has nothing to remove,
    so the non-zero exit / launch failure here is IGNORED (not captured into Detail). }
  ExecCaptured('claude', 'plugin marketplace remove ' + MarketplaceName, '', ResultCode, Output);
  if not ExecCaptured('claude', 'plugin marketplace add "' + AppDir + '" --scope user', '', ResultCode, Output) then
  begin
    Detail := 'could not launch claude: ' + Output;
    Result := False;
    exit;
  end;
  if ResultCode <> 0 then
  begin
    Detail := 'marketplace add failed: ' + Output;
    Result := False;
    exit;
  end;
  ExecCaptured('claude', 'plugin uninstall ' + PluginName, '', ResultCode, Output);
  if not ExecCaptured('claude', 'plugin install "' + PluginName + '@' + MarketplaceName + '" --scope user', '', ResultCode, Output) then
  begin
    Detail := 'could not launch claude: ' + Output;
    Result := False;
    exit;
  end;
  if ResultCode <> 0 then
  begin
    Detail := 'plugin install failed: ' + Output;
    Result := False;
    exit;
  end;
  Detail := 'installed ' + PluginName + '@' + MarketplaceName;
  Result := True;
end;

function RegisterAgy(const AppDir, PluginName: string; var Detail: string): Boolean;
var
  ResultCode: Integer;
  Output, PluginDir: string;
begin
  PluginDir := AppDir + '\plugins\' + PluginName;
  { remove-then-add: pre-clean any prior registration; result swallowed for a first-time install. }
  ExecCaptured('agy', 'plugin uninstall ' + PluginName, '', ResultCode, Output);
  if not ExecCaptured('agy', 'plugin install "' + PluginDir + '"', '', ResultCode, Output) then
  begin
    Detail := 'could not launch agy: ' + Output;
    Result := False;
    exit;
  end;
  if ResultCode <> 0 then
  begin
    Detail := 'agy plugin install failed: ' + Output;
    Result := False;
    exit;
  end;
  Detail := 'installed ' + PluginName + ' from ' + PluginDir;
  Result := True;
end;

{ ---- best-effort, exception-swallowing deregistration of ONE agent (used both by rollback on a
  failed install, and by uninstall). Never raises — every step is independently guarded (K —
  a rollback that throws mid-cleanup re-creates the exact dangling state it exists to prevent). ---- }
procedure DeregisterClaude(const PluginName, MarketplaceName: string);
var
  ResultCode: Integer;
  Output: string;
begin
  try
    ExecCaptured('claude', 'plugin uninstall ' + PluginName, '', ResultCode, Output);
  except
  end;
  try
    { C6 — the oracle never called this; it's the fix for Failure mode A1 (dangling marketplace). }
    ExecCaptured('claude', 'plugin marketplace remove ' + MarketplaceName, '', ResultCode, Output);
  except
  end;
end;

procedure DeregisterAgy(const PluginName: string);
var
  ResultCode: Integer;
  Output: string;
begin
  try
    ExecCaptured('agy', 'plugin uninstall ' + PluginName, '', ResultCode, Output);
  except
  end;
end;

{ ---- top-level orchestration: register the plugin with every DETECTED agent, independently.
  RegisteredClaude/RegisteredAgy tell the caller which agents to roll back if a LATER step fails
  (C1 "rollback MUST track which agents actually registered"). AnySucceeded/AnyDetected drive the
  "fail only if every detected agent fails" rule (C1 per-agent semantics). ---- }
procedure RegisterMemberPlugin(const AppDir, PluginName, MarketplaceName: string;
  var RegisteredClaude, RegisteredAgy, AnyDetected, AnySucceeded: Boolean; var Report: string);
var
  Detail: string;
  ok: Boolean;
begin
  RegisteredClaude := False;
  RegisteredAgy := False;
  AnyDetected := False;
  AnySucceeded := False;
  Report := '';

  if ClaudePresent() then
  begin
    AnyDetected := True;
    ok := RegisterClaude(AppDir, PluginName, MarketplaceName, Detail);
    RegisteredClaude := ok;
    AnySucceeded := AnySucceeded or ok;
    Report := Report + '[claude] ' + Detail + #13#10;
  end
  else
    Report := Report + '[claude] not present on this machine' + #13#10;

  if AgyPresent() then
  begin
    AnyDetected := True;
    ok := RegisterAgy(AppDir, PluginName, Detail);
    RegisteredAgy := ok;
    AnySucceeded := AnySucceeded or ok;
    Report := Report + '[agy] ' + Detail + #13#10;
  end
  else
    Report := Report + '[agy] not present on this machine' + #13#10;
end;

{ ---- rollback: deregister only the agents THIS install actually registered (C1 "per-agent-
  tracked"), used when a step AFTER a successful registration fails. THIS PLAN'S CONCRETE
  RESOLUTION of the design's illustrative rollback-trigger list ("binary unpack, PATH, a second
  agent"): the one concrete post-registration step in this codebase is the golden-header seed
  write (dotnet/classic only — Task 2.3/2.4 call this on a SeedGoldenHeader failure). ghidrust/
  agy-autotrain/commonmemory have no post-registration step, so rollback is structurally moot for
  them (documented, not a gap — see the plan's self-audit). ---- }
procedure RollbackMemberPlugin(const PluginName, MarketplaceName: string; RegisteredClaude, RegisteredAgy: Boolean);
begin
  try
    if RegisteredClaude then DeregisterClaude(PluginName, MarketplaceName);
  except
  end;
  try
    if RegisteredAgy then DeregisterAgy(PluginName);
  except
  end;
end;

{ ---- uninstall-time deregistration: best-effort, tolerates a missing/absent agent (fail-open,
  C6). Callers invoke this from CurUninstallStepChanged's usUninstall step. ---- }
procedure DeregisterMemberPluginOnUninstall(const PluginName, MarketplaceName: string);
begin
  try
    if ClaudePresent() then DeregisterClaude(PluginName, MarketplaceName);
  except
  end;
  try
    if AgyPresent() then DeregisterAgy(PluginName);
  except
  end;
end;

{ ---- shared install-time reporting (C1 per-agent semantics): partial failure is REPORTED, not
  rolled back, at the plugin-registration step itself (only the golden-header rollback path in
  Task 2.3/2.4 actually reverses a registration). ---- }
procedure ReportRegistrationOutcome(AnyDetected, AnySucceeded, RegisteredClaude, RegisteredAgy: Boolean; const Report: string);
begin
  if not AnyDetected then
    SuppressibleMsgBox('No compatible agent (Claude Code / agy) found on this machine. Install ' +
      'Claude Code or agy, then re-run this setup.', mbError, MB_OK, IDOK)
  else if not AnySucceeded then
    SuppressibleMsgBox('Plugin registration failed for every detected agent:' + #13#10 + Report,
      mbError, MB_OK, IDOK)
  else if (ClaudePresent() and not RegisteredClaude) or (AgyPresent() and not RegisteredAgy) then
    SuppressibleMsgBox('Plugin registered, but a partial failure occurred (not rolled back):'
      + #13#10 + Report, mbInformation, MB_OK, IDOK);
end;

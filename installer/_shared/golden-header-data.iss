{ ============================================================================
  installer/_shared/golden-header-data.iss
  Shared Inno [Code] primitives for the golden-header SEED baseline (C4) and per-file backup (C6).
  Meant to be #include'd INSIDE a [Code] section. Used by clavity-dotnet + clavity-classic (SeedGoldenHeader);
  BackupDataFile is additionally used by agy-autotrain for its OWN growth.md (never call it on a
  file the caller does not own — C6 per-file ownership).
============================================================================ }

{ ---- C4 / Boundary-Smuggler (Failure mode D): seed the app dir's seed\golden-header.md into
  %USERPROFILE%\.clavity\golden-header.seed.md. EVERY path-bound PowerShell cmdlet uses
  -LiteralPath — including New-Item, which the pre-cohesion code called with -Path (glob-
  vulnerable: a profile containing '[' silently fails to create ~/.clavity, dropping the seed). ---- }
function SeedGoldenHeader(const AppDir: string): Boolean;
var
  ResultCode: Integer;
  PsCmd, SrcPath, DestDir: string;
begin
  SrcPath := AppDir + '\seed\golden-header.md';
  DestDir := ExpandConstant('{%USERPROFILE}\.clavity');
  { panel R2-1 (pre-existing, preserved): double any single-quote so a username like O'Brien can't
    break the PS single-quoted literals. }
  StringChangeEx(SrcPath, '''', '''''', True);
  StringChangeEx(DestDir, '''', '''''', True);
  PsCmd :=
    'New-Item -ItemType Directory -Force -LiteralPath ''' + DestDir + ''' | Out-Null;' +
    'Copy-Item -LiteralPath ''' + SrcPath + ''' ' +
    '-Destination ''' + DestDir + '\golden-header.seed.md'' -Force';
  { -Command (inline) is not governed by execution policy — no -ExecutionPolicy flag needed
    (pre-existing rationale, preserved). }
  Result := Exec('powershell.exe', '-NoProfile -Command "' + PsCmd + '"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

{ ---- rename-to-.backup (never auto-restored) for exactly ONE file the CALLER owns. A driver
  passes its own seed.md / seed.md.sha256 / legacy flat file; agy-autotrain passes its own
  growth.md / growth.md.sha256. NEVER call this on a sibling's file (C6 — the exact bug this shared
  helper exists to make structurally impossible to repeat: the pre-cohesion dotnet/classic .iss
  each called their inline BackupHeaderFile on growth.md too, which is NOT theirs to touch). ---- }
procedure BackupDataFile(const Path: string);
var
  Backup: string;
begin
  Backup := Path + '.backup';
  if FileExists(Path) then
  begin
    DeleteFile(Backup);
    RenameFile(Path, Backup);
  end;
end;

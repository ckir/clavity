{ ============================================================================
  installer/_shared/golden-header-data.iss
  Shared Inno [Code] primitives for the golden-header SEED baseline (C4) and per-file backup (C6).
  Meant to be #include'd INSIDE a [Code] section. SeedGoldenHeader is used by clavity-dotnet +
  clavity-classic. BackupDataFile has exactly TWO callers, both of them those same two members, both
  backing up the seed baseline + its .sha256 + the pre-split flat file on a KEEP-data uninstall.
  agy-autotrain does NOT call it: it owns the learned growth file and deletes that directly on an
  explicit purge, keeping it untouched otherwise. (This header previously claimed agy-autotrain used
  BackupDataFile for growth.md, which was never true — a future editor must not assume growth.md goes
  through the quarantine-backup path.) C6 per-file ownership still governs every call: never pass a
  file the calling member does not own.
  NOTE: this is a Pascal comment and ends at the first closing brace — never write a brace-wrapped
  Inno constant anywhere in here, or every installer build breaks.
============================================================================ }

{ ---- C4 / Boundary-Smuggler (Failure mode D): seed the app dir's seed\golden-header.md into
  %USERPROFILE%\.clavity\golden-header.seed.md. EVERY path-bound PowerShell cmdlet uses
  -LiteralPath — including New-Item, which the pre-cohesion code called with -Path (glob-
  vulnerable: a profile containing '[' silently fails to create ~/.clavity, dropping the seed). ---- }
function SeedGoldenHeader(const AppDir: string): Boolean;
var
  DestDir: string;
begin
  { Native Inno file ops — NO PowerShell shell-out. The old code shelled out to powershell.exe to copy
    the seed; it passed on the clean CI runner but FAILED on a real user box (the subprocess launch /
    inline-command surface is environment-fragile: PATH/AV/language-mode/32-vs-64-bit powershell.exe).
    ForceDirectories + FileCopy take LITERAL paths (no glob), so a profile whose name contains '[' is
    still handled correctly — the sole reason PowerShell -LiteralPath was originally used. }
  DestDir := ExpandConstant('{%USERPROFILE}\.clavity');
  Result := ForceDirectories(DestDir)
            and FileCopy(AppDir + '\seed\golden-header.md', DestDir + '\golden-header.seed.md', False);
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

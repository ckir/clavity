// ============================================================================
// installer/_shared/user-path.iss
// The ONE per-user PATH add/remove for every member installer. #include in a member's [Code] section.
//
// WHY THIS EXISTS - A DEFECT EVERY INSTALLER SHIPPED, MEASURED 2026-09-11. The members added themselves to
// PATH with a [Registry] entry of the form  ValueData: "<olddata>;<app>"  guarded by a Check function
// called with the app-dir constant as its argument. Inno Setup does NOT expand constants in a Check
// function's parameters: a probe installer logged the parameter as the literal six characters of the
// constant, never the directory. The guard therefore searched PATH for text that is never there, reported
// "not present" every time, and EVERY install and upgrade appended another copy. An owner had to clean
// their PATH by hand. CI never saw it: two smoke workflows install twice and then asserted only that the
// directory appeared SOMEWHERE in PATH - a presence test that passes with two copies as well as one.
//
// AND THE UNINSTALL HALF WAS BOUNDARY-BLIND. It stripped the directory as a plain SUBSTRING, case-
// sensitively. MEASURED on the shipped logic: a sibling entry "...\<app>-old" was left as "-old" glued onto
// the entry before it, a subdirectory "...\<app>\bin" became "\bin" glued the same way, and an upper-case
// copy of the directory was not removed at all. That is the same boundary defect ROADMAP section 28 closed
// for repo-relative paths: a prefix match is not a containment test.
//
// SO BOTH DIRECTIONS WORK ENTRY BY ENTRY. The value is split on ';' and each entry is compared as a whole,
// ignoring case, surrounding quotes and one trailing backslash. Every entry that is not this directory -
// including empty ones and unexpanded %VARIABLES% - is written back byte-for-byte and in its original order.
//   ADD    keeps the FIRST entry that names the directory and drops every later one, which also HEALS a PATH
//          the old installers had already bloated; if none names it, it is appended once. Never prepended.
//   DEDUPE keeps the first and drops the rest exactly like ADD, but NEVER appends. The installers run it on
//          EVERY install where the PATH task is not selected. MEASURED in CI on the first build of this file:
//          dotnet and ghidrust re-run silently with no /TASKS, and a planted duplicate SURVIVED the re-run,
//          while classic - whose re-run passes /TASKS=addtopath - healed it, with identical code. The likely
//          reason, INFERRED and not separately measured: the task is `checkedonce`, which Inno leaves
//          unchecked when a previous version is installed (the smoke steps now print the tasks a re-run
//          recorded). Either way, healing only when the task was ticked would leave exactly the users the
//          old installers damaged still damaged after they upgrade.
//   REMOVE drops every entry that names the directory, and nothing else.
// KNOWN AND ACCEPTED: an entry that names the directory through an environment variable is not recognised
// as the same directory, because Pascal Script has no general expansion call. The installers only ever
// wrote the literal path, so every copy they created is recognised.
//
// The pure half (RebuildUserPath) never touches the registry, so scripts/tests/installer-user-path.Tests.ps1
// drives it from a probe installer. The registry half takes its subkey and value name as parameters for the
// same reason: the probe points it at a scratch key, never at the user's real PATH.
// ============================================================================

// The comparison key for one PATH entry: trimmed, unquoted, one trailing backslash removed (a drive root
// keeps its own), upper-cased with the locale-aware call so a non-ASCII profile name compares correctly.
function UserPathKey(const Entry: string): string;
var
  S: string;
begin
  S := Trim(Entry);
  StringChangeEx(S, '"', '', True);
  S := RemoveBackslashUnlessRoot(Trim(S));
  Result := AnsiUppercase(S);
end;

// The three modes, as named constants so no call site passes a bare number.
const
  UP_REMOVE = 0;
  UP_ADD    = 1;
  UP_DEDUPE = 2;

// Rebuild a PATH value in one of the three modes above. Pure: no registry, no environment.
function RebuildUserPath(const PathValue, Dir: string; const Mode: Integer): string;
var
  Rest, Entry, Key: string;
  SemiPos, Kept: Integer;
  Seen, Matches: Boolean;
begin
  Key := UserPathKey(Dir);
  Result := '';
  Kept := 0;
  Seen := False;
  Rest := PathValue;
  repeat
    SemiPos := Pos(';', Rest);
    if SemiPos > 0 then
    begin
      Entry := Copy(Rest, 1, SemiPos - 1);
      Rest := Copy(Rest, SemiPos + 1, Length(Rest));
    end
    else
    begin
      Entry := Rest;
      Rest := '';
    end;
    Matches := (Key <> '') and (UserPathKey(Entry) = Key);
    // Keep every non-matching entry, and in ADD or DEDUPE mode the first matching one. Drop the rest.
    if (not Matches) or ((Mode <> UP_REMOVE) and (not Seen)) then
    begin
      if Matches then
        Seen := True;
      if Kept > 0 then
        Result := Result + ';';
      Result := Result + Entry;
      Kept := Kept + 1;
    end;
  until SemiPos = 0;

  if (Mode = UP_ADD) and (not Seen) and (Key <> '') then
  begin
    // Reuse a trailing ';' rather than writing an empty entry before the directory.
    if (Result = '') or (Copy(Result, Length(Result), 1) = ';') then
      Result := Result + Dir
    else
      Result := Result + ';' + Dir;
  end;
end;

// Apply RebuildUserPath to a per-user registry value. Writes ONLY when the value changes, and always as
// REG_EXPAND_SZ so the other entries' %VARIABLES% keep expanding. Returns True when it wrote.
function UpdateUserPathValue(const SubKey, ValueName, Dir: string; const Mode: Integer): Boolean;
var
  OldValue, NewValue: string;
begin
  Result := False;
  if not RegQueryStringValue(HKCU, SubKey, ValueName, OldValue) then
  begin
    // Only ADD may create the value; there is nothing to remove from, or dedupe in, a value that is absent.
    if Mode <> UP_ADD then
      exit;
    OldValue := '';
  end;
  NewValue := RebuildUserPath(OldValue, Dir, Mode);
  if NewValue <> OldValue then
    Result := RegWriteExpandStringValue(HKCU, SubKey, ValueName, NewValue);
end;

// What the installers call. ChangesEnvironment=yes in each member's [Setup] broadcasts the change.
// Install:   if the PATH task is selected, AddDirToUserPath, else DedupeDirInUserPath - so a bloated PATH
//            heals on every install, whether or not the user ticked the box this time.
// Uninstall: RemoveDirFromUserPath.
procedure AddDirToUserPath(const Dir: string);
begin
  UpdateUserPathValue('Environment', 'Path', Dir, UP_ADD);
end;

procedure DedupeDirInUserPath(const Dir: string);
begin
  UpdateUserPathValue('Environment', 'Path', Dir, UP_DEDUPE);
end;

procedure RemoveDirFromUserPath(const Dir: string);
begin
  UpdateUserPathValue('Environment', 'Path', Dir, UP_REMOVE);
end;

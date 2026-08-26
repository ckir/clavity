; Inno Setup script for agy-autotrain (plugin-only member; no binary). Build with:
; ISCC.exe installer\agy-autotrain.iss
; Cohesive distribution model (docs/superpowers/specs/2026-07-11-cohesive-distribution-design.md):
; ships the agy-autotrain plugin folder + a scoped 1-entry marketplace.json, self-registering
; against each detected agent (Claude Code / agy). No binary, no download, no remote marketplace.

#define AppName "agy-autotrain"
#define AppVersion "0.4.0"

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
; agy-observations.md is EXCLUDED from the blanket copy below and, since ROADMAP 14g, is NOT SHIPPED AT
; ALL. It is the agy-learn capture inbox: USER DATA that used to live inside the plugin tree and
; accumulate between drains. Two things made that wrong. The blanket copy is `ignoreversion` (= always
; overwrite), so without the exclude an UPGRADE would replace a user's accumulated observations with the
; shipped template. And the plugin tree exists in N copies - the install, every checkout, every worktree -
; so nothing could tell which inbox was live: measured 2026-08-15 at 30 pending in one and 18 in another
; with ZERO overlap. The inbox is now user-local at %USERPROFILE%\.clavity\agy-observations.md, beside
; golden-header.growth.md, and MigrateInboxToUserState moves any pre-14g file there once, on upgrade.
; The exclude below STAYS regardless: it is what stops the blanket copy resurrecting a plugin-tree inbox.
; Note the two DELIBERATELY DIFFERENT exclude forms below, because the difference is load-bearing:
;   * A pattern with NO path separator matches at ANY DEPTH — and against DIRECTORY names as well as file
;     names. `agy-observations.md` uses that form ON PURPOSE, so the inbox is protected from the blanket
;     `ignoreversion` copy wherever in the plugin tree it lives, now or after any future reorganisation.
;   * A pattern with a LEADING BACKSLASH is anchored to the Source root. The three dev folders use that
;     form because the any-depth behaviour is a hazard for them: unanchored, `installer` would silently
;     strip a future subdirectory of that name ANYWHERE in the tree — e.g. a skill with an `installer\`
;     folder — and the file dropped that way is simply absent from the payload, with no build error.
;     That exact mistake shipped a bug in the sibling commonmemory installer: an unanchored
;     `.claude-plugin` entry matched the DIRECTORY and dropped its plugin.json, so upgrades could not
;     overwrite a stale manifest. Anchored, these three only ever mean the top-level folders they name.
; No [InstallDelete] tombstone is wanted here, and 14g makes that sharper rather than softer. Removing
; agy-observations.md from the payload is NOT a deletion of user data - the migration renames the old
; file aside rather than deleting it - but a tombstone WOULD delete a pre-14g inbox on upgrade, and it
; would run before ssPostInstall, i.e. before the migration that rescues it. Leaving a file behind is the
; recoverable failure; deleting one is not.
Source: "..\*"; DestDir: "{app}\plugins\agy-autotrain"; Flags: ignoreversion recursesubdirs createallsubdirs; \
  Excludes: "\installer,\dist,\publish,agy-observations.md"
; ROADMAP 14g: the inbox is NO LONGER SHIPPED into the plugin tree. It is user-local state and lives at
; %USERPROFILE%\.clavity\agy-observations.md, beside golden-header.growth.md, because the plugin tree
; exists in N copies (install, every checkout, every worktree) and nothing could tell which was live -
; measured 30-vs-18 pending entries with ZERO overlap. The Excludes above still keeps it out of the
; blanket copy; the separate onlyifdoesntexist Source line that used to seed it here is deliberately GONE.
; Nothing seeds the new location either: an absent inbox is already the designed cold-start state, and the
; capture skill creates the directory and file on first append. MigrateInboxToUserState (below) moves any
; pre-14g inbox out of the old location on upgrade, once.

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

{ ROADMAP 14g one-time migration. Pre-14g the capture inbox lived in the plugin tree; it is now user-local.
  The installer does this rather than the skills because it DEFINITELY runs, exactly once, at upgrade -
  a lazy skill-side migration only fires when someone next captures or drains, which may be never, and
  until then the entries sit where no code looks. Guarded so a partial or repeated run can neither
  lose anything NOR duplicate anything: copy only when the destination is absent or empty, APPEND
  otherwise (the inbox is an append log, so concatenation is semantically correct), and retire the
  source by RENAME, never by delete. Fail-open throughout - a failed migration must never fail the
  install.

  THE RENAME IS THE COMMIT POINT AND HAPPENS BEFORE THE WRITE. An earlier revision wrote first and
  renamed last, discarding the rename's return value. A capstone found the reachable consequence: when
  the write succeeded and the rename then failed - on Windows an AV hold or another process holding the
  file open for read is enough, since a readable file can still be un-renameable - the source stayed
  put. The next upgrade re-entered, found a now-NON-EMPTY destination, took the append branch, and
  appended every entry a second time. Repeated upgrades multiplied the inbox without bound, and a later
  drain then triaged N copies of each observation. Claiming the source FIRST inverts that: if the rename
  fails, nothing has been written, so the run is a clean no-op and the next upgrade retries from scratch.

  ON A FAILED WRITE THE RENAME IS ROLLED BACK, which is what stops claim-first from merely trading
  duplication for stranding. Without the rollback a failed write would leave the data only under the
  aside name with the source gone, so the next run would exit at the FileExists guard above and never
  look again - silently. The content is already in memory from the load above, so the write needs no
  re-read, which is what makes the rollback cheap.
  NOTE: no Inno constant braces appear inside these comments - a brace-wrapped constant in a Pascal
  comment ENDS the comment and breaks the compile. }
procedure MigrationProblem(const Detail: String);
begin
  { Finding 5 of the round-1 capstone: every failure branch used to be a bare exit, so a migration that
    stranded the operator's whole backlog looked exactly like one that succeeded. Fail-open is still the
    rule - this never blocks or fails the install - but fail-open must not mean fail-SILENT.

    ACCEPTED BOUNDARY, measured - do not re-raise. A capstone round argued this reporting is theater
    because a silent install auto-answers the box. It overstated the trigger: per the Inno documentation
    for Setup Command-Line Parameters, /SILENT and /VERYSILENT do NOT suppress message boxes on their
    own - "error messages during installation are displayed" unless the operator ALSO passes
    /SUPPRESSMSGBOXES, which "only has an effect when combined with /SILENT or /VERYSILENT". So the box
    is hidden only when the operator has explicitly asked for no boxes. That is an opt-out, not a defect,
    and SuppressibleMsgBox is the file-wide convention here - every operator-facing message in this
    installer, including the running-Claude critical error and the uninstall data-purge prompt, uses it.
    Nothing is deleted on any failure path, so a suppressed report costs visibility, never data.
    If unattended deployment ever becomes a supported scenario, revisit this: a durable log line beside
    the install would be mode-independent where a dialog is not. }
  SuppressibleMsgBox('agy-autotrain could not finish moving your captured observations to the new '
    + 'user-local inbox.' + #13#10#13#10 + Detail + #13#10#13#10
    + 'Nothing has been deleted and the install itself is unaffected.', mbInformation, MB_OK, IDOK);
end;

procedure MigrateInboxToUserState();
var
  OldPath, NewDir, NewPath, Aside: String;
  OldBytes, DestBytes: AnsiString;
  DestSize: Integer;
  Wrote: Boolean;
begin
  OldPath := ExpandConstant('{app}\plugins\agy-autotrain\knowledge\agy-observations.md');
  Aside := OldPath + '.migrated-14g';
  if not FileExists(OldPath) then
  begin
    { THE INTERRUPTED MIGRATION, WHICH USED TO BE ABANDONED IN SILENCE. This procedure CLAIMS the source
      by renaming it to Aside before writing anything, so that a crash between the two is a clean no-op
      the next upgrade retries. But the retry never happened: with OldPath gone, every later run exited
      right here, nothing ever looked at Aside, and the operator was told nothing - their whole undrained
      backlog sat under a name no running code reads. The two "the next upgrade will retry" messages
      below are about the OTHER two failure paths, where the source is genuinely still in place.

      THE DISCRIMINATOR IS THE DESTINATION, NOT THE SIDECAR. A SUCCESSFUL migration also leaves Aside
      behind and OldPath absent - the sidecar is the audit trail of the normal case - so keying off the
      sidecar alone would nag every user forever after a perfectly good migration. What separates the two
      is that a successful migration WROTE: the destination is non-empty. Probed without
      ForceDirectories, so this diagnosis never creates the folder it is reporting on. }
    NewPath := ExpandConstant('{%USERPROFILE}') + '\.clavity\agy-observations.md';
    DestSize := 0;
    if FileExists(NewPath) then
      FileSize(NewPath, DestSize);
    if FileExists(Aside) and (DestSize = 0) then
      MigrationProblem('An earlier migration was interrupted after claiming your captured observations '
        + 'and before writing them. Nothing was lost - they are in:' + #13#10 + Aside + #13#10#13#10
        + 'Rename that file back to:' + #13#10 + OldPath + #13#10#13#10
        + 'and the next upgrade will complete the move. Until then the tool reads only ' + NewPath
        + ', which is empty.');
    exit;
  end;

  NewDir := ExpandConstant('{%USERPROFILE}') + '\.clavity';
  if not ForceDirectories(NewDir) then
  begin
    MigrationProblem('The folder ' + NewDir + ' could not be created.');
    exit;
  end;
  NewPath := NewDir + '\agy-observations.md';

  { RAW BYTES, not lines. LoadStringsFromFile/SaveStringsToFile decode and RE-ENCODE: MEASURED with a
    no-install probe installer, an em-dash went in as UTF-8 e2 80 94 and came out as the Windows-1252
    byte 97, and LF line endings came out CRLF. PowerShell then reads that file as UTF-8 and renders
    every such character as U+FFFD - the observation text is destroyed, while the bullet count and the
    `^- \[` anchor still match, so nothing detects it. The live inbox carries 138 non-ASCII lines.
    LoadStringFromFile/SaveStringToFile move bytes without interpreting them, which is all a MOVE needs.
    SaveStringsToUTF8File was measured too and is NOT the fix: it preserves the character but writes a
    UTF-8 BOM, and the BOM breaks agy-inbox-snapshot.sh's `grep '^# agy observations inbox'`, so the
    snapshot silently stops and the drain runs unprotected. UTF-8 WITHOUT a BOM is the requirement. }
  if not LoadStringFromFile(OldPath, OldBytes) then
  begin
    MigrationProblem('The old inbox at ' + OldPath + ' could not be read.');
    exit;
  end;

  { Aside was computed at the top, where the interrupted-state check needs it. }
  if FileExists(Aside) then
  begin
    { A sidecar from an earlier successful migration is already here, yet a source file exists again.
      That state is ambiguous - the source may be content already migrated, or genuinely new captures -
      and appending blind would duplicate. Touch nothing; this is the one case the procedure cannot
      resolve on its own, so it is handed to the operator instead of guessed at.

      BEHAVIOUR CHANGE from the pre-fold code, recorded here because the fold commit did not state it.
      Before, this same condition merely SKIPPED the rename - and it was reached only AFTER the write had
      already happened - so the procedure ended normally and the source silently stayed put forever. Now
      nothing is written, the procedure aborts, and the operator is told. The new shape is deliberate: an
      ambiguous source is exactly the input that used to cause the duplication this fold exists to kill. }
    MigrationProblem('A sidecar from an earlier migration already sits beside ' + OldPath
      + ', so that file was left untouched rather than risk duplicating entries.' + #13#10#13#10
      + 'Merge it by hand into ' + NewPath);
    exit;
  end;

  { CLAIM THE SOURCE FIRST - see the header comment. A failed rename means nothing was written, so this
    run is a clean no-op and the next upgrade retries from scratch. }
  if not RenameFile(OldPath, Aside) then
  begin
    MigrationProblem('The old inbox at ' + OldPath + ' could not be claimed - it may be open in another '
      + 'program. The next upgrade will retry.');
    exit;
  end;

  DestSize := 0;
  if FileExists(NewPath) then
    if not FileSize(NewPath, DestSize) then
    begin
      { A FAILED SIZE READ MUST NOT LOOK LIKE AN EMPTY FILE. FileSize returns a Boolean nobody read: on
        failure DestSize stays 0, the branch below reads that as "the destination is empty" and takes
        FileCopy(..., False), which OVERWRITES it - and the file it would overwrite is the user's inbox,
        possibly newer than what we are holding. The source is already claimed at this point, so stopping
        here is recoverable: the rollback puts it back and the next upgrade retries. Guessing is not. }
      if RenameFile(Aside, OldPath) then
        MigrationProblem('The size of ' + NewPath + ' could not be read, so the migration stopped rather '
          + 'than risk overwriting it. Your observations were put back unchanged and the next upgrade '
          + 'will retry.')
      else
        MigrationProblem('The size of ' + NewPath + ' could not be read, so the migration stopped rather '
          + 'than risk overwriting it. Your observations are safe under:' + #13#10 + Aside + #13#10#13#10
          + 'Rename it back to' + #13#10 + OldPath + #13#10#13#10 + 'and the next upgrade will retry.');
      exit;
    end;

  if (not FileExists(NewPath)) or (DestSize = 0) then
    Wrote := FileCopy(Aside, NewPath, False)
  else
  begin
    { Destination already has content - a newer inbox, or a second run. Append rather than clobber.
      OldBytes was loaded before the rename, so this needs no re-read of the claimed file.
      The FileCopy branch above was MEASURED byte-identical and needs no change; this append was the
      only branch that re-encoded.
      Guard the join: Set-PendingBody always ends the file with LF (drain-lib.ps1:105), but a
      hand-edited inbox need not, and appending to a file with no trailing newline would splice the
      first migrated line onto the last existing one. }
    if LoadStringFromFile(NewPath, DestBytes) then
      if (Length(DestBytes) > 0) and (DestBytes[Length(DestBytes)] <> #10) then
        OldBytes := #10 + OldBytes;
    Wrote := SaveStringToFile(NewPath, OldBytes, True);
  end;

  if not Wrote then
  begin
    { Roll the claim back so the source returns to the path the next upgrade looks at. Only if THAT also
      fails is the data somewhere no operator would think to look. }
    if RenameFile(Aside, OldPath) then
      MigrationProblem('Writing to ' + NewPath + ' failed, so the old inbox was put back unchanged. '
        + 'The next upgrade will retry.')
    else
      { The sibling branch above tells the operator WHY renaming back is the right move - "the next
        upgrade will retry". This one said only "rename it back", which is the same instruction with the
        reason removed: an operator who renames it back and then simply USES the tool finds an empty
        inbox, because nothing but this migration ever reads OldPath (drain-lib.ps1 Resolve-InboxPath
        goes explicit -> CLAVITY_AGY_INBOX -> %USERPROFILE%\.clavity, and never the install tree). The
        data is not lost - it is where no running code looks until a migration runs again - and saying so
        is the difference between a recoverable state and one the operator abandons. }
      MigrationProblem('Writing to ' + NewPath + ' failed. Your observations are safe, but under a '
        + 'renamed file:' + #13#10 + Aside + #13#10#13#10
        + 'Rename it back to' + #13#10 + OldPath + #13#10#13#10
        + 'and the next upgrade will retry the move. Until it does, the tool reads only ' + NewPath
        + ', so a renamed-back file is safe but not yet in use. Or merge it into ' + NewPath + ' by hand.');
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  RegisteredClaude, RegisteredAgy, AnyDetected, AnySucceeded: Boolean;
  RegReport: string;
begin
  if CurStep = ssPostInstall then
  begin
    MigrateInboxToUserState();
    { agy-autotrain is a CLAUDE-driver discipline (AGY-LEARN capture/curate) with no agy-side content,
      so it registers with Claude Code ONLY — never agy (which has no use for it). }
    RegisterMemberPluginFor(ExpandConstant('{app}'), 'agy-autotrain', 'clavity-agy-autotrain', 'claude',
      RegisteredClaude, RegisteredAgy, AnyDetected, AnySucceeded, RegReport);
    ReportRegistrationOutcomeFor('claude', AnyDetected, AnySucceeded, RegisteredClaude, RegisteredAgy, RegReport);
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
    '  - the learned golden-header growth (%USERPROFILE%\.clavity\golden-header.growth.md and its .sha256)' + #13#10 +
    { Both plugin-folder items are named, and they arrive by OPPOSITE routes: the .migrated-14g
      sidecar is left by a migration that SUCCEEDED - it is the audit trail of the normal case -
      while the plain inbox is there only if a migration FAILED and rolled back. Calling both of
      them failure wreckage, as this dialog did for one commit, mislabels the common case to the
      one person who most needs it stated plainly. }
    { `~` IS NOT A WINDOWS PATH. This dialog is the last thing an operator sees before consenting to the
      destruction of their capture inbox, and it is the one moment they might want to go and look at it
      first. `~\.clavity` resolves in a POSIX shell and in PowerShell, and in none of the places a Windows
      operator would actually paste it: Explorer's address bar, cmd.exe, or Win+R. `%USERPROFILE%` resolves
      in all three. Changed 2026-08-26; both this line and the growth line above carried it. }
    '  - any observations captured but not yet drained: the inbox in %USERPROFILE%\.clavity, plus'#13#10 +
    '    anything an earlier migration left in the plugin folder - its .migrated-14g'#13#10 +
    '    backup, or the inbox itself if that migration had to roll back' + #13#10#13#10 +
    'Choose No to keep both for a future reinstall.',
    mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  GrowthFile, InboxFile: string;
begin
  if CurUninstallStep = usUninstall then
  begin
    DeregisterMemberPluginOnUninstallFor('agy-autotrain', 'clavity-agy-autotrain', 'claude');
    GrowthFile := ExpandConstant('{%USERPROFILE}\.clavity\golden-header.growth.md');
    if RemoveGrowth then
    begin
      if FileExists(GrowthFile) then DeleteFile(GrowthFile);
      if FileExists(GrowthFile + '.sha256') then DeleteFile(GrowthFile + '.sha256');
      { REMOVED 2026-08-24, and the removal matters more than the text did. This comment claimed the
        inbox was "marked uninsneveruninstall so a KEEP-data uninstall cannot destroy it" and that it
        "lives inside the install dir". BOTH halves were false at 14g: `uninsneveruninstall` appears
        nowhere in this file TODAY, and the inbox moved to %USERPROFILE%\.clavity. (It said "no [Files]
        entry ever carried it" until 2026-08-26, which the comment TWENTY-THREE LINES BELOW contradicts
        outright: dc85d2d, 25b83cf and bd83435 each shipped that entry with the flag. Same fact, two
        statements, one procedure - and the ROADMAP's re-correction of it landed while this copy did not.) Sitting directly above the only code that deletes a user's
        observations, it invited exactly the misreading that would license moving these DeleteFile calls
        out of the `if RemoveGrowth` gate: "the flag protects it anyway". Nothing protects it but the
        gate. The comment below states the actual contract. }
      { ROADMAP 14g: the inbox now lives BESIDE growth.md in the user-local state directory, not in
        the install dir. On an explicit PURGE it must still be removed, or the user's consent is
        ignored in the other direction. Also retire the one-time migration sidecar - same user data. }
      InboxFile := ExpandConstant('{%USERPROFILE}') + '\.clavity\agy-observations.md';
      if FileExists(InboxFile) then DeleteFile(InboxFile);
      InboxFile := ExpandConstant('{app}\plugins\agy-autotrain\knowledge\agy-observations.md.migrated-14g');
      if FileExists(InboxFile) then DeleteFile(InboxFile);
      { And the PLAIN path, not only the sidecar. When a migration write fails it ROLLS BACK by renaming
        the aside file to the plugin knowledge folder's plain agy-observations.md (spelled with ExpandConstant
        below, not here: an app-constant's closing brace inside a Pascal brace comment ENDS the
        comment early - measured, it broke this compile once), so after a
        rollback the user's ENTIRE undrained backlog sits at that name. The installer has not shipped
        that file since 14g, so it can only exist because a pre-14g install left it or a rollback put it
        back - user data either way. A reviewer corrected this comment on 2026-08-26 and the correction
        matters: it used to claim Inno's uninstaller "removes only files it LOGGED, and this is not one,
        so nothing else would ever take it". The second half is FALSE. A pre-14g installer DID ship this
        path through a [Files] entry, so it IS logged in an existing unins000.dat, and the flag that
        protects it was added part-way through that history - measured across the four commits that
        shipped it: 74ffd27 carried only `onlyifdoesntexist`, while dc85d2d, 25b83cf and bd83435 added
        `uninsneveruninstall`. So on a machine installed BEFORE that flag arrived, Inno's own uninstall
        engine deletes this file on a KEEP uninstall - the opposite consent failure, and one this
        procedure cannot prevent because the log was written by an installer that has already run.
        What IS true, and is why the line below exists: nothing DELIBERATE removed it on a PURGE, so a
        user who explicitly asked for their data to go kept their whole backlog. That is the "consent ignored in the other direction" the comment above forbids, and it
        is why this line sits INSIDE the gate - deleted on an explicit purge, never on KEEP. }
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

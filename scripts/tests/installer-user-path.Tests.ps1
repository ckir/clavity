# The per-user PATH handling every member installer shares: installer/_shared/user-path.iss.
#
# THE DEFECT THIS PINS, MEASURED 2026-09-11. Every installer appended itself to PATH through a [Registry]
# entry guarded by a Check function called with the app-dir constant. Inno Setup does not expand constants
# in a Check function's parameters - a probe logged the literal constant text - so the guard never found the
# directory and EVERY install and upgrade appended another copy. An owner had to clean their PATH by hand.
# The uninstall half matched by SUBSTRING, so a sibling or subdirectory entry was left glued to its neighbour.
# The include's header has the full measurement.
#
# WHY CI NEVER SAW IT. Two smoke workflows install twice and then asserted `-like "*$app*"` - a PRESENCE test,
# satisfied by two copies exactly as by one. A count over a filtered collection has to be an IDENTITY
# assertion, and so does every oracle here.
#
# TWO HALVES, AND THEY FAIL DIFFERENTLY.
#   STRUCTURAL - every installer that offers the PATH task goes through the shared include, and none writes
#   PATH any other way. No Inno needed; runs everywhere.
#   BEHAVIOURAL - the include's Pascal is compiled into a throwaway probe installer by the real ISCC and RUN,
#   on synthetic PATH values and on a SCRATCH registry key. Pascal Script cannot be executed any other way, so
#   where ISCC is absent these rows SKIP, visibly - they never pass without running. The probe returns False
#   from InitializeSetup: it installs nothing, creates no app directory and no uninstall entry, and the row
#   asserts the user's real PATH is byte-identical before and after.
BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Include  = Join-Path $script:RepoRoot 'installer/_shared/user-path.iss'
    $script:Iscc = @(Get-ChildItem -Path "$env:ProgramFiles\Inno Setup *\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup *\ISCC.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1)

    # Every tracked installer script. DISCOVERED through git, never listed: a hand list is how a fourth copy
    # of the defect would go unchecked.
    $script:AllIss = @(git -C $script:RepoRoot ls-files -- '*.iss' '*.iss.template' | ForEach-Object { Join-Path $script:RepoRoot $_ })
}

Describe 'installer user PATH handling' {

    Context 'structural - every installer goes through installer/_shared/user-path.iss' {

        It 'discovers every installer that offers the PATH task, by name' {
            $withTask = @($script:AllIss | Where-Object { (Get-Content -Raw -LiteralPath $_) -match 'Name:\s*"addtopath"' } |
                ForEach-Object { $_.Substring($script:RepoRoot.Length + 1).Replace('\', '/') } | Sort-Object)
            # IDENTITY, not a count: a discovery that lost one and gained another would keep the count.
            $withTask | Should -Be @(
                'clavity-classic/installer/clavity-classic.iss'
                'clavity-dotnet/installer/clavity-dotnet.iss'
                'clavity-dotnet/templates/tool-skeleton/installer.iss.template'
                'ghidrust/installer/ghidrust.iss'
            )
        }

        It 'each one includes the shared file, adds on the task, dedupes otherwise, and removes on uninstall' {
            $problems = @(foreach ($f in $script:AllIss) {
                $t = Get-Content -Raw -LiteralPath $f
                if ($t -notmatch 'Name:\s*"addtopath"') { continue }
                $n = Split-Path -Leaf $f
                if ($t -notmatch '(?m)^#include\s+"[^"]*installer\\_shared\\user-path\.iss"') { "$n does not #include installer\_shared\user-path.iss" }
                if ($t -notmatch "if WizardIsTaskSelected\('addtopath'\) then\s+AddDirToUserPath\(ExpandConstant\('\{app\}'\)\)\s+else\s+DedupeDirInUserPath\(ExpandConstant\('\{app\}'\)\)") { "$n does not add under the addtopath task and DEDUPE otherwise" }
                if ($t -notmatch "RemoveDirFromUserPath\(ExpandConstant\('\{app\}'\)\)") { "$n never calls RemoveDirFromUserPath(ExpandConstant('{app}'))" }
            })
            $problems | Should -BeNullOrEmpty
        }

        It 'no installer writes the user PATH any other way' {
            # The two forms that shipped the defect: a [Registry] entry on Environment\Path, and a private
            # PATH function in the installer itself. Either one bypasses the shared, tested logic.
            $problems = @(foreach ($f in $script:AllIss) {
                $n = Split-Path -Leaf $f
                foreach ($line in (Get-Content -LiteralPath $f)) {
                    if ($line -match '^\s*Root:\s*HKCU;\s*Subkey:\s*"Environment";.*ValueName:\s*"Path"') { "$n writes PATH from a [Registry] entry: $($line.Trim())" }
                    if ($line -match '^\s*(function|procedure)\s+(NeedsAddPath|RemoveFromUserPath)\b') { "$n defines its own PATH routine: $($line.Trim())" }
                }
            })
            $problems | Should -BeNullOrEmpty
        }
    }

    Context 'behavioural - the include, compiled by ISCC and run' {
        BeforeAll {
            $script:Work = Join-Path ([IO.Path]::GetTempPath()) ("userpath-" + [guid]::NewGuid().ToString('N'))
            $script:RegKey = 'Software\ClavityUserPathProbe-' + [guid]::NewGuid().ToString('N')
            $script:Dir = 'C:\Tools\Programs\clavity-dotnet'
            $script:Out = Join-Path $script:Work 'out.txt'
            $script:RealPathBefore = (Get-Item -LiteralPath 'HKCU:\Environment').GetValue('Path', $null, 'DoNotExpandEnvironmentNames')

            # Each case: mode, PATH value, expected result. The directory is $script:Dir unless the case names one.
            $d = $script:Dir
            $script:Cases = @(
                @{ Id = 'add to an empty PATH';                      Mode = 'add';    Path = '';                                        Expected = $d }
                @{ Id = 'add when absent';                           Mode = 'add';    Path = 'C:\W;C:\T';                               Expected = "C:\W;C:\T;$d" }
                @{ Id = 'add when present once - unchanged';         Mode = 'add';    Path = "C:\W;$d;C:\T";                            Expected = "C:\W;$d;C:\T" }
                @{ Id = 'add HEALS the duplicates the bug left';     Mode = 'add';    Path = "C:\W;$d;C:\T;$d;$d";                      Expected = "C:\W;$d;C:\T" }
                @{ Id = 'add keeps the FIRST spelling of a match';   Mode = 'add';    Path = "C:\W;$($d.ToLowerInvariant())\;$d";       Expected = "C:\W;$($d.ToLowerInvariant())\" }
                @{ Id = 'add reuses a trailing semicolon';           Mode = 'add';    Path = 'C:\W;';                                   Expected = "C:\W;$d" }
                @{ Id = 'add does not mistake a SIBLING for it';     Mode = 'add';    Path = "C:\W;$d-old";                             Expected = "C:\W;$d-old;$d" }
                @{ Id = 'add recognises a QUOTED entry';             Mode = 'add';    Path = "C:\W;`"$d`"";                             Expected = "C:\W;`"$d`"" }
                @{ Id = 'add keeps other %VARIABLE% entries raw';    Mode = 'add';    Path = '%USERPROFILE%\bin;C:\W';                  Expected = "%USERPROFILE%\bin;C:\W;$d" }
                # DEDUPE is what an install runs when the PATH task is NOT ticked - on an upgrade, usually.
                @{ Id = 'dedupe HEALS duplicates';                   Mode = 'dedupe'; Path = "C:\W;$d;C:\T;$d;$d";                      Expected = "C:\W;$d;C:\T" }
                @{ Id = 'dedupe NEVER appends when absent';          Mode = 'dedupe'; Path = 'C:\W;C:\T';                               Expected = 'C:\W;C:\T' }
                @{ Id = 'dedupe keeps a single entry in place';      Mode = 'dedupe'; Path = "$d;C:\W";                                 Expected = "$d;C:\W" }
                @{ Id = 'remove the single entry';                   Mode = 'remove'; Path = "C:\W;$d;C:\T";                            Expected = 'C:\W;C:\T' }
                @{ Id = 'remove EVERY duplicate';                    Mode = 'remove'; Path = "$d;C:\W;$d";                              Expected = 'C:\W' }
                @{ Id = 'remove leaves a SIBLING intact';            Mode = 'remove'; Path = "C:\W;$d;$d-old;C:\T";                     Expected = "C:\W;$d-old;C:\T" }
                @{ Id = 'remove leaves a SUBDIRECTORY intact';       Mode = 'remove'; Path = "C:\W;$d\bin;$d";                          Expected = "C:\W;$d\bin" }
                @{ Id = 'remove matches other case and a trailing \';Mode = 'remove'; Path = "C:\W;$($d.ToUpperInvariant())\";           Expected = 'C:\W' }
                @{ Id = 'remove the only entry';                     Mode = 'remove'; Path = $d;                                        Expected = '' }
                @{ Id = 'remove when absent - unchanged';            Mode = 'remove'; Path = 'C:\W;C:\T';                               Expected = 'C:\W;C:\T' }
                @{ Id = 'remove preserves an unrelated empty entry'; Mode = 'remove'; Path = "C:\W;;$d;C:\T";                           Expected = 'C:\W;;C:\T' }
                # A non-ASCII profile name, compared case-insensitively. The owner's locale is Greek.
                @{ Id = 'add matches a NON-ASCII path in other case'; Mode = 'add';   Path = 'C:\W;c:\' + [char]0x03C7 + [char]0x03C1 + '\app'; Dir = 'C:\' + [char]0x03A7 + [char]0x03A1 + '\app'; Expected = 'C:\W;c:\' + [char]0x03C7 + [char]0x03C1 + '\app' }
            )

            if (-not $script:Iscc) { return }
            New-Item -ItemType Directory -Force -Path $script:Work | Out-Null

            # Tab-separated: mode, path, dir. UTF-8 WITH a BOM, which is how LoadStringsFromFile tells UTF-8 from ANSI.
            $lines = foreach ($c in $script:Cases) { "$($c.Mode)`t$($c.Path)`t$(if ($c.Dir) { $c.Dir } else { $d })" }
            [IO.File]::WriteAllLines((Join-Path $script:Work 'cases.txt'), [string[]]$lines, [Text.UTF8Encoding]::new($true))

            $probe = @'
[Setup]
AppName=ClavityUserPathProbe
AppVersion=1
AppId=ClavityUserPathProbe
CreateAppDir=no
Uninstallable=no
PrivilegesRequired=lowest
OutputDir=%WORK%
OutputBaseFilename=probe

[Code]
#include "%INCLUDE%"

function Field(const Line: string; Index: Integer): string;
var
  Rest: string;
  P, I: Integer;
begin
  Rest := Line;
  for I := 1 to Index do
  begin
    P := Pos(#9, Rest);
    if P = 0 then Rest := '' else Rest := Copy(Rest, P + 1, Length(Rest));
  end;
  P := Pos(#9, Rest);
  if P > 0 then Result := Copy(Rest, 1, P - 1) else Result := Rest;
end;

function ModeOf(const S: string): Integer;
begin
  if S = 'add' then Result := UP_ADD
  else if S = 'dedupe' then Result := UP_DEDUPE
  else if S = 'remove' then Result := UP_REMOVE
  else Result := -1;
end;

function InitializeSetup(): Boolean;
var
  Cases, Output: TArrayOfString;
  I, N: Integer;
  SubKey, Dir, V: string;
begin
  Result := False;
  if not LoadStringsFromFile(ExpandConstant('{param:CASES}'), Cases) then exit;
  N := GetArrayLength(Cases);
  SetArrayLength(Output, N + 5);
  for I := 0 to N - 1 do
    if ModeOf(Field(Cases[I], 0)) < 0 then
      Output[I] := 'BAD-MODE ' + Field(Cases[I], 0)
    else
      Output[I] := RebuildUserPath(Field(Cases[I], 1), Field(Cases[I], 2), ModeOf(Field(Cases[I], 0)));
  SubKey := ExpandConstant('{param:REGKEY}');
  Dir := ExpandConstant('{param:REGDIR}');
  Output[N] := 'ADD-WROTE=' + IntToStr(Ord(UpdateUserPathValue(SubKey, 'Path', Dir, UP_ADD)));
  Output[N + 1] := 'ADD-AGAIN-WROTE=' + IntToStr(Ord(UpdateUserPathValue(SubKey, 'Path', Dir, UP_ADD)));
  V := '<absent>';
  RegQueryStringValue(HKCU, SubKey, 'Path', V);
  Output[N + 2] := 'AFTER-ADD=' + V;
  UpdateUserPathValue(SubKey, 'Path', Dir, UP_REMOVE);
  V := '<absent>';
  RegQueryStringValue(HKCU, SubKey, 'Path', V);
  Output[N + 3] := 'AFTER-REMOVE=' + V;
  Output[N + 4] := 'CREATE-WROTE=' + IntToStr(Ord(UpdateUserPathValue(SubKey, 'Fresh', Dir, UP_ADD)));
  SaveStringsToUTF8File(ExpandConstant('{param:OUT}'), Output, False);
end;
'@
            $probe = $probe.Replace('%WORK%', $script:Work).Replace('%INCLUDE%', $script:Include)
            [IO.File]::WriteAllText((Join-Path $script:Work 'probe.iss'), $probe, [Text.UTF8Encoding]::new($true))
            $script:CompileOut = & $script:Iscc[0].FullName /Q (Join-Path $script:Work 'probe.iss') 2>&1 | Out-String
            $script:CompileExit = $LASTEXITCODE

            # The scratch key the registry half is pointed at - never HKCU\Environment. Seeded the way the old
            # installers left a PATH: the directory twice, beside a %VARIABLE% entry that must stay unexpanded.
            $null = New-Item -Path "HKCU:\$($script:RegKey)" -Force
            New-ItemProperty -Path "HKCU:\$($script:RegKey)" -Name 'Path' -PropertyType ExpandString `
                -Value "%USERPROFILE%\bin;C:\W;$d;C:\T;$d" | Out-Null

            if ($script:CompileExit -eq 0) {
                $exe = Join-Path $script:Work 'probe.exe'
                $probeArgs = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART',
                               "/CASES=`"$(Join-Path $script:Work 'cases.txt')`"", "/OUT=`"$($script:Out)`"",
                               "/REGKEY=`"$($script:RegKey)`"", "/REGDIR=`"$d`"")
                Start-Process -FilePath $exe -ArgumentList $probeArgs -Wait | Out-Null
            }
            $script:Results = if (Test-Path -LiteralPath $script:Out) { @(Get-Content -LiteralPath $script:Out -Encoding utf8) } else { @() }
            $scratch = Get-Item -LiteralPath "HKCU:\$($script:RegKey)"
            $script:ScratchKind = $scratch.GetValueKind('Path')
            $script:FreshKind   = if ($scratch.GetValueNames() -contains 'Fresh') { $scratch.GetValueKind('Fresh') } else { '<absent>' }
            $script:FreshValue  = $scratch.GetValue('Fresh', '<absent>', 'DoNotExpandEnvironmentNames')
            $script:RealPathAfter = (Get-Item -LiteralPath 'HKCU:\Environment').GetValue('Path', $null, 'DoNotExpandEnvironmentNames')
        }
        AfterAll {
            if ($script:RegKey) { Remove-Item -Path "HKCU:\$($script:RegKey)" -Recurse -Force -ErrorAction SilentlyContinue }
            if ($script:Work)   { Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It 'RebuildUserPath returns the expected value for every case' {
            if (-not $script:Iscc) { Set-ItResult -Skipped -Because 'ISCC (Inno Setup) is not installed, so the Pascal cannot be run here' }
            $script:CompileExit | Should -Be 0 -Because "the probe must compile against the include; ISCC said:`n$($script:CompileOut)"
            # PRECONDITION: the probe RAN and wrote one line per case plus the four registry lines. Without
            # this, an empty result would fail every case for the wrong reason - or, compared loosely, pass.
            $script:Results.Count | Should -Be ($script:Cases.Count + 5) -Because 'the probe must have run and written every result'
            $mismatch = @(for ($i = 0; $i -lt $script:Cases.Count; $i++) {
                if ($script:Results[$i] -cne $script:Cases[$i].Expected) {
                    "$($script:Cases[$i].Id): expected [$($script:Cases[$i].Expected)] got [$($script:Results[$i])]"
                }
            })
            $mismatch | Should -BeNullOrEmpty
        }

        It 'the registry half heals duplicates, writes REG_EXPAND_SZ, and writes only on a change' {
            if (-not $script:Iscc) { Set-ItResult -Skipped -Because 'ISCC (Inno Setup) is not installed, so the Pascal cannot be run here' }
            $n = $script:Cases.Count
            $d = $script:Dir
            $script:Results[$n]     | Should -Be 'ADD-WROTE=1' -Because 'the seeded value held the directory twice, so the add must rewrite it'
            $script:Results[$n + 1] | Should -Be 'ADD-AGAIN-WROTE=0' -Because 'a second add has nothing to change and must not rewrite the value'
            $script:Results[$n + 2] | Should -Be "AFTER-ADD=%USERPROFILE%\bin;C:\W;$d;C:\T"
            $script:Results[$n + 3] | Should -Be 'AFTER-REMOVE=%USERPROFILE%\bin;C:\W;C:\T'
            $script:ScratchKind | Should -Be 'ExpandString' -Because 'PATH must stay REG_EXPAND_SZ or its %VARIABLE% entries stop expanding'
        }

        It 'the registry half CREATES an absent PATH value as REG_EXPAND_SZ' {
            # THE ROW ABOVE CANNOT SEE THIS. MEASURED: swapping the expandable write for a plain REG_SZ write
            # left it green, because Inno keeps REG_EXPAND_SZ when the value ALREADY has that type. Only a
            # value that does not exist yet - a fresh profile with no user PATH - shows the difference, and a
            # REG_SZ PATH silently stops expanding every %VARIABLE% entry any other tool adds later.
            if (-not $script:Iscc) { Set-ItResult -Skipped -Because 'ISCC (Inno Setup) is not installed, so the Pascal cannot be run here' }
            $script:Results[$script:Cases.Count + 4] | Should -Be 'CREATE-WROTE=1'
            $script:FreshValue | Should -Be $script:Dir
            $script:FreshKind | Should -Be 'ExpandString'
        }

        It 'never touches the real user PATH' {
            if (-not $script:Iscc) { Set-ItResult -Skipped -Because 'ISCC (Inno Setup) is not installed, so the probe was not run' }
            $script:RealPathAfter | Should -BeExactly $script:RealPathBefore
        }
    }
}

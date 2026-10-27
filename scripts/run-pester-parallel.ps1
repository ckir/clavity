<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

<#
.SYNOPSIS
  Run Pester suite files in parallel, one pwsh PROCESS per file, as strict as a single Invoke-Pester.

.DESCRIPTION
  Pester 6 has no parallel runner. Measured 2026-10-12 (Linux, 8 cores, 32 fast-half files): one process per file,
  sequential, is ~2.2x SLOWER than the single-process recipe (pwsh + Pester start-up per file); 4 at once is ~1.6x
  faster and 8 at once ~1.9x faster, with the same pass/fail census and no tree pollution. The longest single file
  (~32 s) bounds the speed-up, so more cores stop helping early. Windows (CI) is unmeasured.

  The suite list is read from a justfile recipe (default test-scripts-fast), so there is ONE list; this script never
  carries its own. Exit 1 when ANY of: a test failed; a container did not end Passed or Skipped (a container that fails
  DISCOVERY contributes 0 failed tests, so counting failures alone would call a broken suite green); a named file is
  missing; a child produced no result; or there were no files at all.

.PARAMETER Recipe      justfile recipe whose Invoke-Pester list to run.
.PARAMETER Justfile    justfile to read (default: the repo root's).
.PARAMETER Files       explicit suite paths (comma-separated); overrides -Directory and -Recipe.
.PARAMETER Directory   run every *.Tests.ps1 under this directory (recursive, sorted by full path; relative paths resolve against the
               repo root). Precedence: -Files > -Directory > -Recipe. A missing directory exits 1.
.PARAMETER SkipInventory  the generated skip-inventory file (relative paths resolve against the repo root). In check mode the
               run's skipped rows are compared with this OS's section; a stale static table or an unlisted conditional skip exits 1,
               and so does a file with no section for this OS (fails closed).
.PARAMETER WriteSkipInventory  write mode: regenerate this OS's section of -SkipInventory from the run. Requires -Directory (a partial
               run would drop other suites' rows) and -SkipInventory. Other OS sections are preserved; LF endings, no BOM.
.PARAMETER Exclude     suites to leave out, by BASE name (the file name without .Tests.ps1), comma-separated. A name that matches no
               suite is an error (a typo must not silently exclude nothing), and excluding every suite is an error. Excluded
               suites are NAMED in the output: a lane that skips a suite must say so, because it is not a full gate.
.PARAMETER ShowMessages  print each failing row's first error message (whitespace collapsed, cut at 300 chars) under its FAILED
               name, so a flaky row that fails once can be diagnosed from the run that failed instead of a re-run.
.PARAMETER MinTests    fail (exit 1) when fewer tests than this ran in total (passed + failed + skipped). A coverage floor: a lane whose suites
               were deleted or never discovered must not stay green.
.PARAMETER RequireSuite  suites that MUST report a result, by BASE name, comma-separated. A required suite that is missing, excluded or whose child
               produced no result fails the run. Use it for the suite that proves all the others exist (the registration oracle).
.PARAMETER ThrottleLimit  files running at once (default 4).
.PARAMETER ListOnly    print the resolved suite paths and exit 0.
.PARAMETER Child       internal: run ONE file and print a PESTER-RESULT line.
#>
[CmdletBinding()]
param(
    [string]$Recipe = 'test-scripts-fast',
    [string]$Justfile,
    [string[]]$Files,
    [string[]]$Exclude,
    [ValidateRange(0, 100000)][int]$MinTests = 0,
    [string[]]$RequireSuite,
    [switch]$ShowMessages,
    [ValidateRange(1, 64)][int]$ThrottleLimit = 4,
    [switch]$ListOnly,
    [string]$Child,
    [string]$Directory,
    [string]$SkipInventory,
    [switch]$WriteSkipInventory
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if ($Child) {
    # NOT 'Stop' (the parent's setting above): the tests run in THIS process and inherit it, and Stop turns a non-terminating
    # error inside a row into a failure that a plain Invoke-Pester never reports (measured 2026-10-12, agy-anomaly-reminder's
    # '.git is a FILE' row). The runner must be exactly as strict as the gate it replaces, no stricter.
    $ErrorActionPreference = 'Continue'
    Import-Module Pester -MinimumVersion 6.0.0 -MaximumVersion 6.99.99 -Force
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = Invoke-Pester -Path $Child -Output None -PassThru
    # A test's own -Tag plus every enclosing block's (Context/Describe), walking Block then Parent.
    function Get-EffectiveTags($t) { $tags = @($t.Tag); $b = $t.Block; while ($b) { $tags += @($b.Tag); $b = $b.Parent }; @($tags | Where-Object { $_ } | Select-Object -Unique) }
    $summary = [ordered]@{
        file = $Child
        passed = $r.PassedCount; failed = $r.FailedCount; skipped = $r.SkippedCount; notrun = $r.NotRunCount
        # A container whose every test skipped ends 'Skipped', not 'Passed': that is not a broken container (each skip is gated by the parent).
        badContainers = @($r.Containers | Where-Object { $_.Result -cnotin 'Passed', 'Skipped' } | ForEach-Object { [string]$_.Name }).Count
        failedNames = @($r.Failed | ForEach-Object { [string]$_.ExpandedPath })
        # Always captured (cheap); the parent decides whether to print. One line, bounded, so a 2000-char assertion dump cannot flood a log.
        failedMessages = @($r.Failed | ForEach-Object {
            $m = if ($_.ErrorRecord) { ([string]$_.ErrorRecord[0].Exception.Message) -replace '\s+', ' ' } else { '' }
            $m.Trim().Substring(0, [Math]::Min(300, $m.Trim().Length))
        })
        # Skipped rows: reason = the Set-ItResult -Because text (a discovery-time -Skip carries no ErrorRecord, so '').
        skips = @($r.Skipped | ForEach-Object {
            $m = if ($_.ErrorRecord) { (([string]$_.ErrorRecord[0].Exception.Message) -replace '^is skipped, because ', '' -replace '\s+', ' ').Trim() } else { '' }
            [ordered]@{ path = [string]$_.ExpandedPath; tags = @(Get-EffectiveTags $_ | ForEach-Object { [string]$_ }); reason = $m }
        })
        # Rows that did NOT skip but carry an OS tag (a WindowsOnly row that ran on Linux is a lie in the tag).
        osTagged = @(@($r.Passed) + @($r.Failed) | Where-Object { $_ } | ForEach-Object {
            $tg = @(Get-EffectiveTags $_ | ForEach-Object { [string]$_ })
            if ($tg -ccontains 'WindowsOnly' -or $tg -ccontains 'LinuxOnly') { [ordered]@{ path = [string]$_.ExpandedPath; tags = $tg } }
        })
        secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    }
    'PESTER-RESULT ' + ($summary | ConvertTo-Json -Compress -Depth 4)
    exit 0
}

function Get-RecipeSuites([string]$JustfilePath, [string]$Name) {
    # Same extraction rules as scripts/tests/test-suite-registration.Tests.ps1 (that test pins them): the recipe's OWN
    # body, with comments stripped, so a suite named in a comment is not run and not counted.
    $text = Get-Content -LiteralPath $JustfilePath -Raw
    $m = [regex]::Match($text, "(?m)^$([regex]::Escape($Name)):\r?\n(?<body>(?:[ \t]+.*\r?\n?|[ \t]*\r?\n)+)")
    if (-not $m.Success) { return @() }
    $body = ($m.Groups['body'].Value -split "`n" | ForEach-Object {
        ($_ -replace '<#.*?#>', '') -replace '(^|\s)<#.*$', '' -replace '(^|\s)#.*$', ''
    }) -join "`n"
    @([regex]::Matches($body, "[A-Za-z0-9._/-]+/[A-Za-z0-9._-]+\.Tests\.ps1(?![A-Za-z0-9._#-])") |
        ForEach-Object { $_.Value } | Select-Object -Unique)
}

if ($WriteSkipInventory -and (-not $Directory -or -not $SkipInventory)) {
    Write-Host "-WriteSkipInventory requires -Directory (a partial run would drop other suites' rows) and -SkipInventory"; exit 1
}

if ($Files) { $suites = @($Files | ForEach-Object { $_ -split ',' } | Where-Object { $_ }) }
elseif ($Directory) {
    $dirPath = if ([IO.Path]::IsPathRooted($Directory)) { $Directory } else { Join-Path $root $Directory }
    if (-not (Test-Path -LiteralPath $dirPath)) { Write-Host "run-pester-parallel: -Directory '$dirPath' does not exist"; exit 1 }
    $suites = @(Get-ChildItem -LiteralPath $dirPath -Recurse -Filter '*.Tests.ps1' -File | Sort-Object FullName | ForEach-Object FullName)
}
else {
    $jf = if ($Justfile) { $Justfile } else { Join-Path $root 'justfile' }
    $suites = @(Get-RecipeSuites $jf $Recipe)
}

$excluded = @()
if ($Exclude) {
    $names = @($Exclude | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object { $_.Trim() })
    $base = { param($p) ([IO.Path]::GetFileName($p)) -replace '\.Tests\.ps1$', '' }
    $unknown = @($names | Where-Object { $n = $_; -not (@($suites | Where-Object { (& $base $_) -eq $n }).Count) })
    if ($unknown.Count -gt 0) { Write-Host ("run-pester-parallel: -Exclude names no suite in the list: " + ($unknown -join ', ')); exit 1 }
    $excluded = @($suites | Where-Object { (& $base $_) -in $names })
    $suites = @($suites | Where-Object { (& $base $_) -notin $names })
}

if ($ListOnly) { $suites; exit 0 }

if ($suites.Count -eq 0) { Write-Host "run-pester-parallel: no suite files resolved (recipe '$Recipe'); an empty gate is not a green gate."; exit 1 }

$resolved = foreach ($s in $suites) { if ([IO.Path]::IsPathRooted($s)) { $s } else { Join-Path $root $s } }
$missing = @($resolved | Where-Object { -not (Test-Path -LiteralPath $_) })
if ($missing.Count -gt 0) { Write-Host ("run-pester-parallel: MISSING suite file(s): " + ($missing -join ', ')); exit 1 }

foreach ($x in $excluded) { Write-Host ("EXCLUDED (not run): " + ((([IO.Path]::GetFileName($x)) -replace '\.Tests\.ps1$', ''))) }

# ---- skip-approval gate and generated skip inventory -------------------------------------------------------------------
# Every skipped row must be approved IN THE TEST (a vocabulary -Tag, or an 'APPROVED:<tag>: why' -Because), so a skip cannot
# slip in unseen; the per-OS inventory file is GENERATED from the run, and the check compares it as sets of exact row text.
$script:VocabRx    = '^(WindowsOnly|LinuxOnly|NotAsRoot|(?:NeedsTool|FsFeature):[A-Za-z0-9._-]+)$'
$script:ApprovedRx = '^APPROVED:(WindowsOnly|LinuxOnly|NotAsRoot|(?:NeedsTool|FsFeature):[A-Za-z0-9._-]+): '
$script:Os = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
$script:TableHead = @('| Suite | Row | Tag | Reason |', '| --- | --- | --- | --- |')

function Get-InvRowKey([string]$Line) {
    $m = [regex]::Match($Line, '^\| (?<s>[^|]+?) \| (?<r>.+?) \| (?<t>[A-Za-z0-9._:-]+) \| (?<x>.*) \|$')
    if ($m.Success) { [pscustomobject]@{ Suite = $m.Groups['s'].Value; Row = $m.Groups['r'].Value } }
    else { [pscustomobject]@{ Suite = $Line; Row = '' } }
}
function Sort-InvRows($Rows) {
    $l = New-Object 'System.Collections.Generic.List[string]'
    foreach ($x in @($Rows)) { if ($x) { $l.Add([string]$x) } }
    $l.Sort([Comparison[string]]{ param($a, $b)
        $ka = Get-InvRowKey $a; $kb = Get-InvRowKey $b
        $c = [string]::CompareOrdinal($ka.Suite, $kb.Suite); if ($c -ne 0) { return $c }
        $c = [string]::CompareOrdinal($ka.Row, $kb.Row); if ($c -ne 0) { return $c }
        [string]::CompareOrdinal($a, $b) })
    @($l)
}
# This OS's committed section -> @{ static = rows; conditional = rows; start; end } ; $null when there is none.
function Read-InvSection([string[]]$Lines, [string]$Os) {
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -cmatch "^##\s+$([regex]::Escape($Os))\s*$") { $start = $i; break } }
    if ($start -lt 0) { return $null }
    $end = $Lines.Count
    for ($i = $start + 1; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match '^##\s') { $end = $i; break } }
    $mode = ''; $st = @(); $co = @()
    for ($i = $start + 1; $i -lt $end; $i++) {
        $ln = $Lines[$i]
        if ($ln -match '^###\s+static\s*$') { $mode = 's'; continue }
        if ($ln -match '^###\s+conditional\s*$') { $mode = 'c'; continue }
        if ($ln -notmatch '^\| ' -or $ln -match '^\| Suite \| Row \|' -or $ln -match '^\| --- ') { continue }
        if ($mode -eq 's') { $st += $ln } elseif ($mode -eq 'c') { $co += $ln }
    }
    @{ static = $st; conditional = $co; start = $start; end = $end }
}

function Test-SkipGate {
    $failed = $false
    $nativeTag = if ($IsWindows) { 'WindowsOnly' } elseif ($IsMacOS) { $null } else { 'LinuxOnly' }
    $foreign = @(@('WindowsOnly', 'LinuxOnly') | Where-Object { $_ -cne $nativeTag })

    # 1. every skipped row must be approved; remember the approving tag + the reason text for the inventory.
    $unapproved = 0; $observed = @()
    foreach ($k in $allSkips) {
        $rm = [regex]::Match($k.Reason, $script:ApprovedRx, [Text.RegularExpressions.RegexOptions]::None)
        # A valid APPROVED:<tag>: reason is the row's OWN approval and wins over an inherited tag: a native-OS-tagged probe skip
        # (WindowsOnly Context, 'APPROVED:NeedsTool:ISCC: ...') is conditional, not static, or a host that has the tool would see a false STALE.
        $tag = @(if ($rm.Success) { $rm.Groups[1].Value } else { $k.Tags | Where-Object { $_ -cmatch $script:VocabRx } | Select-Object -First 1 })
        if (-not $tag) { Write-Host "UNAPPROVED SKIP $($k.Suite) :: $($k.Path)"; $unapproved++; continue }
        $why = if ($rm.Success) { $k.Reason.Substring($rm.Length) } else { $k.Reason }
        $observed += [pscustomobject]@{ Suite = $k.Suite; Path = $k.Path; Tag = [string]$tag[0]; Why = $why }
    }
    if ($unapproved -gt 0) {
        Write-Host "  a discovery-time -Skip carries no reason text, so it needs a -Tag from the vocabulary; a run-time Set-ItResult -Skipped needs -Because 'APPROVED:<tag>: <why>'"
        $failed = $true
    }

    # 2. OS tags must tell the truth.
    foreach ($k in $allOsTagged) {
        $bad = @($k.Tags | Where-Object { $_ -cin $foreign })
        if ($bad.Count -gt 0) { Write-Host "OS-TAG MISMATCH $($k.Suite) :: $($k.Path) (tagged $($bad[0]) but it ran on $($script:Os))"; $failed = $true }
    }
    if ($nativeTag) {
        foreach ($k in $allSkips) {
            if ($k.Tags -ccontains $nativeTag -and $k.Reason -cnotmatch $script:ApprovedRx) {
                Write-Host "OS-TAG MISMATCH $($k.Suite) :: $($k.Path) (tagged $nativeTag but skipped on $($script:Os) without an APPROVED: reason)"; $failed = $true
            }
        }
    }

    if (-not $SkipInventory) { return $failed }
    $invPath = if ([IO.Path]::IsPathRooted($SkipInventory)) { $SkipInventory } else { Join-Path $root $SkipInventory }
    $obsStatic = @(); $obsCond = @()
    foreach ($o in $observed) {
        $esc = { param($x) ([string]$x).Replace('|', '\|') }
        $line = "| $($o.Suite) | $(& $esc $o.Path) | $($o.Tag) | $(if ($o.Why) { & $esc $o.Why } else { '-' }) |"
        if ($o.Tag -cin 'WindowsOnly', 'LinuxOnly') { $obsStatic += $line } else { $obsCond += $line }
    }
    $obsStatic = @($obsStatic | Select-Object -Unique); $obsCond = @($obsCond | Select-Object -Unique)
    $covered = @($coveredSuites)
    $inCovered = { param($l) (Get-InvRowKey $l).Suite -cin $covered }

    if ($WriteSkipInventory) {
        if ($tot.failed -gt 0 -or $tot.bad -gt 0 -or $tot.noresult -gt 0) {
            Write-Host 'SKIP-INVENTORY: refusing to write: the run had failing tests, bad containers or missing results (a partial run would drop rows)'; return $true
        }
        if ($failed) { Write-Host 'SKIP-INVENTORY not written: fix the skip-approval / OS-tag failures above first'; return $true }
        $lines = if (Test-Path -LiteralPath $invPath) { @([IO.File]::ReadAllLines($invPath)) } else { @() }
        $sec = Read-InvSection $lines $script:Os
        $oldS = if ($sec) { @($sec.static) } else { @() }; $oldC = if ($sec) { @($sec.conditional) } else { @() }
        $newS = Sort-InvRows (@($oldS | Where-Object { -not (& $inCovered $_) }) + $obsStatic | Select-Object -Unique)
        $newC = Sort-InvRows (@($oldC) + $obsCond | Select-Object -Unique)
        $gen = @("## $($script:Os)", '', '### static', '') + $script:TableHead + $newS + @('', '### conditional', '') + $script:TableHead + $newC
        if ($sec) {
            $e = $sec.end; while ($e -gt $sec.start + 1 -and [string]::IsNullOrWhiteSpace($lines[$e - 1])) { $e-- }
            $out = @(if ($sec.start -gt 0) { $lines[0..($sec.start - 1)] }) + $gen
            if ($e -lt $lines.Count) { $out += @($lines[$e..($lines.Count - 1)]) }
        } else {
            $n = $lines.Count; while ($n -gt 0 -and [string]::IsNullOrWhiteSpace($lines[$n - 1])) { $n-- }
            $keep = @(if ($n -gt 0) { $lines[0..($n - 1)] })
            $out = @($keep) + $(if ($keep.Count -gt 0) { @('') } else { @() }) + $gen
        }
        $dir = Split-Path -Parent $invPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [IO.File]::WriteAllText($invPath, (($out -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
        Write-Host "SKIP-INVENTORY written: $SkipInventory ($($newS.Count) static, $($newC.Count) conditional)"
        return $false
    }

    if (-not (Test-Path -LiteralPath $invPath)) { Write-Host "SKIP-INVENTORY: file not found: $SkipInventory"; return $true }
    $sec = Read-InvSection @([IO.File]::ReadAllLines($invPath)) $script:Os
    if (-not $sec) {
        Write-Host "SKIP-INVENTORY: no `"## $($script:Os)`" section in $SkipInventory"
        Write-Host "  regenerate on this OS (review the diff before committing): pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory $SkipInventory -WriteSkipInventory"
        return $true
    }
    $comS = @($sec.static | Where-Object { & $inCovered $_ }); $comC = @($sec.conditional | Where-Object { & $inCovered $_ })
    $diff = @()
    foreach ($l in $obsStatic) { if ($l -cnotin $comS) { $diff += "+ $l" } }
    foreach ($l in $comS) { if ($l -cnotin $obsStatic) { $diff += "- $l" } }
    foreach ($l in $obsCond) { if ($l -cnotin $comC) { $diff += "+ $l" } }
    if ($diff.Count -gt 0) {
        Write-Host 'SKIP-INVENTORY STALE: regenerate with -WriteSkipInventory and review the diff'
        $diff | ForEach-Object { Write-Host "    $_" }
        return $true
    }
    if (-not $failed) { Write-Host "SKIP-INVENTORY ok os=$($script:Os) static=$($obsStatic.Count) conditional=$($obsCond.Count)" }
    $failed
}

$self = $PSCommandPath
$pwshExe = (Get-Process -Id $PID).Path
$wall = [Diagnostics.Stopwatch]::StartNew()
$results = $resolved | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
    $raw = & $using:pwshExe -NoProfile -File $using:self -Child $_ 2>&1 | Out-String
    [pscustomobject]@{ File = $_; Exit = $LASTEXITCODE; Raw = $raw }
}

$tot = @{ passed = 0; failed = 0; skipped = 0; bad = 0; noresult = 0 }
$allSkips = New-Object System.Collections.Generic.List[object]
$allOsTagged = New-Object System.Collections.Generic.List[object]
$coveredSuites = New-Object System.Collections.Generic.List[string]
foreach ($r in ($results | Sort-Object File)) {
    $line = ($r.Raw -split "`r?`n" | Where-Object { $_ -like 'PESTER-RESULT *' } | Select-Object -Last 1)
    $name = Split-Path -Leaf $r.File
    if (-not $line -or $r.Exit -ne 0) {
        $tot.noresult++
        Write-Host "NO-RESULT $name (child exit $($r.Exit))"
        Write-Host $r.Raw
        continue
    }
    $s = ($line.Substring('PESTER-RESULT '.Length) | ConvertFrom-Json)
    $coveredSuites.Add($name)
    foreach ($k in @($s.skips)) { if ($k) { $allSkips.Add([pscustomobject]@{ Suite = $name; Path = [string]$k.path; Tags = @($k.tags | ForEach-Object { [string]$_ }); Reason = [string]$k.reason }) } }
    foreach ($k in @($s.osTagged)) { if ($k) { $allOsTagged.Add([pscustomobject]@{ Suite = $name; Path = [string]$k.path; Tags = @($k.tags | ForEach-Object { [string]$_ }) }) } }
    $tot.passed += $s.passed; $tot.failed += $s.failed; $tot.skipped += $s.skipped; $tot.bad += $s.badContainers
    $flag = if ($s.failed -gt 0 -or $s.badContainers -gt 0) { 'FAIL' } else { 'ok  ' }
    Write-Host ("{0} {1} passed={2} failed={3} skipped={4} badContainers={5} secs={6}" -f $flag, $name, $s.passed, $s.failed, $s.skipped, $s.badContainers, $s.secs)
    $names = @($s.failedNames); $msgs = @($s.failedMessages)
    for ($i = 0; $i -lt $names.Count; $i++) {
        Write-Host "    FAILED $($names[$i])"
        if ($ShowMessages -and $i -lt $msgs.Count -and $msgs[$i]) { Write-Host "        $($msgs[$i])" }
    }
}

Write-Host ("TOTAL files={0} excluded={8} passed={1} failed={2} skipped={3} badContainers={4} noResult={5} wall={6}s throttle={7}" -f
    $resolved.Count, $tot.passed, $tot.failed, $tot.skipped, $tot.bad, $tot.noresult, [math]::Round($wall.Elapsed.TotalSeconds, 1), $ThrottleLimit, $excluded.Count)

$gateFailed = Test-SkipGate
$ran = $tot.passed + $tot.failed + $tot.skipped
if ($MinTests -gt 0 -and $ran -lt $MinTests) {
    Write-Host "MIN-TESTS: only $ran tests ran, expected at least $MinTests - suites deleted, excluded or never discovered?"
    $gateFailed = $true
}
foreach ($req in @($RequireSuite | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object { $_.Trim() })) {
    if (-not (@($coveredSuites | ForEach-Object { $_ -replace '\.Tests\.ps1$', '' }) -ccontains $req)) {
        Write-Host "REQUIRED-SUITE: $req did not report a result (deleted, renamed, excluded, or its child failed)"
        $gateFailed = $true
    }
}
if ($tot.failed -gt 0 -or $tot.bad -gt 0 -or $tot.noresult -gt 0 -or $gateFailed) { exit 1 }
exit 0

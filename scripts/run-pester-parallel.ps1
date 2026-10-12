<#
.SYNOPSIS
  Run Pester suite files in parallel, one pwsh PROCESS per file, as strict as a single Invoke-Pester.

.DESCRIPTION
  Pester 6 has no parallel runner. Measured 2026-10-12 (Linux, 8 cores, 32 fast-half files): one process per file,
  sequential, is ~2.2x SLOWER than the single-process recipe (pwsh + Pester start-up per file); 4 at once is ~1.6x
  faster and 8 at once ~1.9x faster, with the same pass/fail census and no tree pollution. The longest single file
  (~32 s) bounds the speed-up, so more cores stop helping early. Windows (CI) is unmeasured.

  The suite list is read from a justfile recipe (default test-scripts-fast), so there is ONE list; this script never
  carries its own. Exit 1 when ANY of: a test failed; a container did not end Passed (a container that fails
  DISCOVERY contributes 0 failed tests, so counting failures alone would call a broken suite green); a named file is
  missing; a child produced no result; or there were no files at all.

.PARAMETER Recipe      justfile recipe whose Invoke-Pester list to run.
.PARAMETER Justfile    justfile to read (default: the repo root's).
.PARAMETER Files       explicit suite paths (comma-separated); overrides -Recipe.
.PARAMETER ThrottleLimit  files running at once (default 4).
.PARAMETER ListOnly    print the resolved suite paths and exit 0.
.PARAMETER Child       internal: run ONE file and print a PESTER-RESULT line.
#>
[CmdletBinding()]
param(
    [string]$Recipe = 'test-scripts-fast',
    [string]$Justfile,
    [string[]]$Files,
    [ValidateRange(1, 64)][int]$ThrottleLimit = 4,
    [switch]$ListOnly,
    [string]$Child
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
    $summary = [ordered]@{
        file = $Child
        passed = $r.PassedCount; failed = $r.FailedCount; skipped = $r.SkippedCount; notrun = $r.NotRunCount
        badContainers = @($r.Containers | Where-Object { $_.Result -ne 'Passed' } | ForEach-Object { [string]$_.Name }).Count
        failedNames = @($r.Failed | ForEach-Object { [string]$_.ExpandedPath })
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

if ($Files) { $suites = @($Files | ForEach-Object { $_ -split ',' } | Where-Object { $_ }) }
else {
    $jf = if ($Justfile) { $Justfile } else { Join-Path $root 'justfile' }
    $suites = @(Get-RecipeSuites $jf $Recipe)
}

if ($ListOnly) { $suites; exit 0 }

if ($suites.Count -eq 0) { Write-Host "run-pester-parallel: no suite files resolved (recipe '$Recipe'); an empty gate is not a green gate."; exit 1 }

$resolved = foreach ($s in $suites) { if ([IO.Path]::IsPathRooted($s)) { $s } else { Join-Path $root $s } }
$missing = @($resolved | Where-Object { -not (Test-Path -LiteralPath $_) })
if ($missing.Count -gt 0) { Write-Host ("run-pester-parallel: MISSING suite file(s): " + ($missing -join ', ')); exit 1 }

$self = $PSCommandPath
$pwshExe = (Get-Process -Id $PID).Path
$wall = [Diagnostics.Stopwatch]::StartNew()
$results = $resolved | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
    $raw = & $using:pwshExe -NoProfile -File $using:self -Child $_ 2>&1 | Out-String
    [pscustomobject]@{ File = $_; Exit = $LASTEXITCODE; Raw = $raw }
}

$tot = @{ passed = 0; failed = 0; skipped = 0; bad = 0; noresult = 0 }
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
    $tot.passed += $s.passed; $tot.failed += $s.failed; $tot.skipped += $s.skipped; $tot.bad += $s.badContainers
    $flag = if ($s.failed -gt 0 -or $s.badContainers -gt 0) { 'FAIL' } else { 'ok  ' }
    Write-Host ("{0} {1} passed={2} failed={3} skipped={4} badContainers={5} secs={6}" -f $flag, $name, $s.passed, $s.failed, $s.skipped, $s.badContainers, $s.secs)
    foreach ($n in @($s.failedNames)) { Write-Host "    FAILED $n" }
}

Write-Host ("TOTAL files={0} passed={1} failed={2} skipped={3} badContainers={4} noResult={5} wall={6}s throttle={7}" -f
    $resolved.Count, $tot.passed, $tot.failed, $tot.skipped, $tot.bad, $tot.noresult, [math]::Round($wall.Elapsed.TotalSeconds, 1), $ThrottleLimit)

if ($tot.failed -gt 0 -or $tot.bad -gt 0 -or $tot.noresult -gt 0) { exit 1 }
exit 0

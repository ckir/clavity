# Shared test hygiene. Dot-sourced by BashHookHelpers.ps1 and by suites that do not use it.
function Remove-TestPath {
    # MEASURED (pwsh 7): `Remove-Item $null,$x -ErrorAction SilentlyContinue` THROWS ParameterBindingValidationException
    # (the error action does not cover binding), and so does an empty set. So filter, and skip when nothing is left.
    param([Parameter(ValueFromRemainingArguments)] $Path)
    $p = @($Path | ForEach-Object { $_ } | Where-Object { $_ })
    if ($p.Count -eq 0) { return }
    Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-TestTempRoot {
    # ONE parent for every suite's scratch, so a killed run orphans files under ONE directory that the sweep can age out,
    # instead of 30 000 siblings in %TEMP% (measured 2026-10-08: 30 765 directories).
    $root = if ($env:CLAVITY_TEST_TEMP_ROOT) { $env:CLAVITY_TEST_TEMP_ROOT } else { Join-Path ([IO.Path]::GetTempPath()) 'clavity-tests' }
    $null = New-Item -ItemType Directory -Path $root -Force
    $root
}
function New-TestTempPath {
    # Returns a path (not created): '<root>/<prefix>-<guid>'. $Suffix is for the few callers that need an extension.
    param([Parameter(Mandatory)][string]$Prefix, [string]$Suffix = '')
    Join-Path (Get-TestTempRoot) ("$Prefix-" + [Guid]::NewGuid().ToString('N') + $Suffix)
}
function Invoke-TestTempSweep {
    # Deletes children of the shared root older than MaxAgeHours. 72 h by default: a run paused over a weekend (Friday evening to
    # Monday morning is ~60 h) keeps its scratch (panel round 1 found 24 h breaks on weekends); scratch is small, so three days of slack costs nothing.
    param([double]$MaxAgeHours = 72)
    $root = Get-TestTempRoot
    # A root that is a junction/symlink would make Get-ChildItem list the TARGET's children, and the sweep would delete them (AGY-CAPSTONE
    # branch T round 2). Refuse the root. (MEASURED, pwsh 7: Remove-Item -Recurse on a CHILD junction removes the link only, never its target - pinned by the test.)
    if ((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { return }
    $cut = (Get-Date).AddHours(-$MaxAgeHours)
    foreach ($c in @(Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cut })) {
        Remove-Item -LiteralPath $c.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}
# Once per RUN, at dot-source time. A `$script:` flag would reset for every suite file (Pester gives each its own script scope), so ~58 sweeps per run
# (panel round 3); an environment flag is inherited by child processes and lives for the whole run.
if (-not $env:CLAVITY_TEST_TEMP_SWEPT) { $env:CLAVITY_TEST_TEMP_SWEPT = '1'; try { Invoke-TestTempSweep } catch { } }

function Get-ParkedFilePath {
    # Where a test parks a TRACKED file it temporarily moves away. Deliberately NOT under the swept root: a sweep that deleted the parked
    # copy would destroy the only copy of a tracked file (the backup must outlive the 72 h sweep window of a paused run).
    param([Parameter(Mandatory)][string]$Name)
    Join-Path ([IO.Path]::GetTempPath()) $Name
}
function Restore-KilledRunBackup {
    # A test that parks a tracked file at a fixed backup path and restores it in `finally` leaves the TRACKED file MISSING if the run is killed
    # in between. Call at suite start. Restore ONLY when the target is missing; if the target exists the backup is stale and must never be moved
    # over newer content - it is deleted instead.
    param([Parameter(Mandatory)][string]$Backup, [Parameter(Mandatory)][string]$Target)
    if (-not (Test-Path -LiteralPath $Backup -PathType Leaf)) { return }
    if (-not (Test-Path -LiteralPath $Target)) {
        Move-Item -LiteralPath $Backup -Destination $Target -Force
        Write-Warning "RESTORED-FROM-KILLED-RUN $Target (from $Backup)"
    } else {
        Remove-Item -LiteralPath $Backup -Force -ErrorAction SilentlyContinue
        Write-Warning "STALE-BACKUP-IGNORED $Backup (the target exists; the backup was deleted)"
    }
}

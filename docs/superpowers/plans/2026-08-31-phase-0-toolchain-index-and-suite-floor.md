# Phase 0 Implementation Plan - pin the toolchain, reconcile the index, repair the suite floor

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking.

**Goal:** close the three measured fail-opens that every later phase of the sequencing spec assumes are
already shut - a plugin install that has silently drifted from the repo, a ROADMAP index that has been wrong
four times, and a test gate whose only real oracle does not guard itself.

**Architecture:** three independent commits, landed in the order **0c, 0a, 0b**, each with its own checker
script plus a Pester suite. Every checker is read-only (so the repo's `-WhatIf` rule does not apply, which
exempts read-only checkers) and follows the shape of `scripts/check-roster.ps1`: `[CmdletBinding()]`,
`Set-StrictMode -Version Latest`, try/catch, explicit exit codes. Every checker's tests build **throwaway
fixtures under `$TestDrive`** and never assert against live machine state, because CI has no installed
plugin and a test that silently skips is the fail-open class this whole phase exists to close.

**Tech Stack:** PowerShell 7 (`pwsh`), Pester 6.x (`-MinimumVersion 6.0.0 -MaximumVersion 6.99.99`), git
plumbing (`git ls-tree`, `git show`, `git cat-file -e`), GitHub Actions YAML.

---

## Ground truth - every figure below was measured at `8d6d430` before this plan was written

Do not re-derive these; do re-verify any you are about to depend on.

| fact | measured value |
|---|---|
| repo plugin payload | **30 files** under `clavity-dotnet/plugin/` |
| installed plugin root | `$env:LOCALAPPDATA\Programs\clavity-dotnet\plugins\clavity` |
| installed vs repo, **normalized** | **16 drifted, 3 missing, 1 extra, 11 identical** |
| installed vs repo, **raw bytes** | **19 drifted** - 3 of those differ *only* in line endings |
| committed line endings | **LF** for every payload file |
| worktree + installed line endings | **CRLF** for `.md`/`.json`, **LF** for `.sh` |
| the 3 missing files | `hooks/agy-mark.sh`, `hooks/agy-shield-lib.sh`, `hooks/assertion-strength-reminder.sh` |
| the 1 extra file | `.mcp.json.bak-2026-08-25` |
| `plugin.json` version, both sides | `"version": "0.7.0"` - **identical across the drift** |
| ROADMAP `(N lines)` claims | **4 total, 4 wrong**, all at `clavity-dotnet/ROADMAP.md:1222-1225` |
| ROADMAP backticked shas near a closure token | **28 distinct, 0 non-existent** |

**The line-ending fact is the one that sinks a naive implementation.** The installed copy is a copy of a
*worktree*, so it is CRLF for `.md`/`.json`; `git show <sha>:<path>` returns the *committed* form, which is
LF. Comparing those bytes directly reports drift on 19 files when only 16 have really drifted. **Normalize
CRLF to LF on both sides before hashing.**

---

## File structure

| file | responsibility |
|---|---|
| **Create** `scripts/check-plugin-drift.ps1` | 0c. Compare an installed plugin tree against the repo payload **at a declared sha**. Set comparison (missing/extra) plus normalized content hash. Read-only. |
| **Create** `scripts/tests/check-plugin-drift.Tests.ps1` | 0c tests. Throwaway git repo + fake install under `$TestDrive`. |
| **Create** `scripts/check-roadmap-claims.ps1` | 0a. Verify the ROADMAP's own checkable claims: every `` `file` (N lines) `` matches, and every sha cited beside a closure token exists. Read-only. |
| **Create** `scripts/tests/check-roadmap-claims.Tests.ps1` | 0a tests. Fixture ROADMAP files under `$TestDrive`. |
| **Modify** `clavity-dotnet/ROADMAP.md` | 0a. Four stale headers (`:1215` §14h, `:1343` §17, `:1419` §18, `:1652` §19) and the four wrong line-counts at `:1222-1225`. |
| **Modify** `.github/workflows/ci-scripts.yml:199-203` | 0b. Add an assertion that the registration oracle itself ran. |
| **Modify** `scripts/tests/test-suite-registration.Tests.ps1` | 0b. One row pinning that the CI guard exists. |
| **Modify** `justfile:100`, `justfile:107` | Register the two new suites in the fast/slow partition. |
| **Modify** `scripts/tests/_partition.md` | Two rows in the `## Measured runtimes` fenced table (fence at `:529`-`:748`). |

**Why two checkers and not one.** They answer unrelated questions against unrelated inputs (a filesystem
tree versus a markdown document), they fail for unrelated reasons, and 0a's must be able to red while 0c's
is green. Merging them would produce one script with two disjoint halves and a single exit code.

---

## COMMIT 1 - 0c: the plugin drift detector

### Task 1: `check-plugin-drift.ps1` - the failing test first

**Files:**
- Create: `scripts/tests/check-plugin-drift.Tests.ps1`
- Create: `scripts/check-plugin-drift.ps1`

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/check-plugin-drift.Tests.ps1`:

```powershell
# Fixtures are a THROWAWAY git repo plus a fake install, both under $TestDrive. Nothing here reads the
# real installed plugin: CI has no install, and a row that silently skips when the install is absent is
# the exact fail-open this checker exists to close. The live check is a manual step in the plan, not a row.
BeforeAll {
    $script:Script = (Resolve-Path (Join-Path $PSScriptRoot '..' 'check-plugin-drift.ps1')).Path

    function New-FixtureRepo {
        param([hashtable]$Files)
        $repo = Join-Path $TestDrive ("repo-" + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $repo -Force
        & git -C $repo init -q
        & git -C $repo config user.email 't@t.t'
        & git -C $repo config user.name  'T'
        & git -C $repo config core.autocrlf false
        foreach ($rel in $Files.Keys) {
            $p = Join-Path $repo ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            $null = New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force
            [IO.File]::WriteAllText($p, $Files[$rel])
        }
        & git -C $repo add -A
        & git -C $repo commit -q -m 'fixture'
        $sha = (& git -C $repo rev-parse HEAD).Trim()
        [pscustomobject]@{ Root = $repo; Sha = $sha }
    }

    function New-FixtureInstall {
        param([hashtable]$Files)
        $inst = Join-Path $TestDrive ("inst-" + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $inst -Force
        foreach ($rel in $Files.Keys) {
            $p = Join-Path $inst ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            $null = New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force
            [IO.File]::WriteAllText($p, $Files[$rel])
        }
        $inst
    }

    function Invoke-Drift {
        param($Repo, $Sha, $Install, [string]$PluginPath = 'plugin')
        $out = & pwsh -NoProfile -File $script:Script -RepoRoot $Repo -Sha $Sha `
                      -InstalledRoot $Install -PluginPath $PluginPath 2>&1 | Out-String
        [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
    }

    $script:Payload = @{
        'plugin/skills/a/SKILL.md' = "line one`nline two`n"
        'plugin/hooks/h.sh'        = "#!/usr/bin/env bash`necho hi`n"
        'plugin/plugin.json'       = "{`n  `"version`": `"0.7.0`"`n}`n"
    }
}

Describe 'check-plugin-drift.ps1' {

    It 'exits 0 when the install matches the declared sha exactly' {
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'skills/a/SKILL.md' = "line one`nline two`n"
            'hooks/h.sh'        = "#!/usr/bin/env bash`necho hi`n"
            'plugin.json'       = "{`n  `"version`": `"0.7.0`"`n}`n"
        }
        $res = Invoke-Drift $r.Root $r.Sha $i
        $res.Code | Should -Be 0 -Because "a matching install must pass; output was:`n$($res.Out)"
    }

    It 'exits 0 when the ONLY difference is CRLF vs LF' {
        # THE row that stops 3 false positives. MEASURED on the real install 2026-08-31: raw-byte
        # comparison reported 19 drifted files where normalized comparison reported 16. The installed
        # tree is a copy of a CRLF worktree; `git show` returns the committed LF form.
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'skills/a/SKILL.md' = "line one`r`nline two`r`n"
            'hooks/h.sh'        = "#!/usr/bin/env bash`r`necho hi`r`n"
            'plugin.json'       = "{`r`n  `"version`": `"0.7.0`"`r`n}`r`n"
        }
        $res = Invoke-Drift $r.Root $r.Sha $i
        $res.Code | Should -Be 0 -Because "line endings alone are not drift; output was:`n$($res.Out)"
    }

    It 'exits 1 and NAMES the file when content drifted' {
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'skills/a/SKILL.md' = "line one`nline TWO CHANGED`n"
            'hooks/h.sh'        = "#!/usr/bin/env bash`necho hi`n"
            'plugin.json'       = "{`n  `"version`": `"0.7.0`"`n}`n"
        }
        $res = Invoke-Drift $r.Root $r.Sha $i
        $res.Code | Should -Be 1
        $res.Out  | Should -Match 'DRIFTED'
        $res.Out  | Should -Match 'skills/a/SKILL\.md'
    }

    It 'exits 1 and NAMES the file when it is missing from the install' {
        # The real install is missing three hooks outright, so absence must be a first-class outcome
        # and not merely "nothing to compare".
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'skills/a/SKILL.md' = "line one`nline two`n"
            'plugin.json'       = "{`n  `"version`": `"0.7.0`"`n}`n"
        }
        $res = Invoke-Drift $r.Root $r.Sha $i
        $res.Code | Should -Be 1
        $res.Out  | Should -Match 'MISSING'
        $res.Out  | Should -Match 'hooks/h\.sh'
    }

    It 'exits 1 and NAMES the file when the install carries an extra file' {
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'skills/a/SKILL.md'      = "line one`nline two`n"
            'hooks/h.sh'             = "#!/usr/bin/env bash`necho hi`n"
            'plugin.json'            = "{`n  `"version`": `"0.7.0`"`n}`n"
            '.mcp.json.bak-2026-01-01' = "stale`n"
        }
        $res = Invoke-Drift $r.Root $r.Sha $i
        $res.Code | Should -Be 1
        $res.Out  | Should -Match 'EXTRA'
        $res.Out  | Should -Match 'bak-2026-01-01'
    }

    It 'exits 2 - NOT 0 - when the declared sha does not exist' {
        # Fail-closed. A checker that cannot check must never report clean.
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{ 'plugin.json' = "{}`n" }
        $res = Invoke-Drift $r.Root '63eb46f0000000000000000000000000deadbeef' $i
        $res.Code | Should -Be 2 -Because "an unresolvable sha is 'cannot check', not 'clean'; output was:`n$($res.Out)"
        $res.Out  | Should -Match 'does not exist'
    }

    It 'exits 2 - NOT 0 - when the installed root is absent' {
        $r = New-FixtureRepo $script:Payload
        $res = Invoke-Drift $r.Root $r.Sha (Join-Path $TestDrive 'no-such-install')
        $res.Code | Should -Be 2 -Because "an absent install is 'cannot check', not 'clean'; output was:`n$($res.Out)"
        $res.Out  | Should -Match 'not installed|does not exist'
    }

    It 'reports a clean tree without printing any of the three defect tokens' {
        # Guards against a report that always prints its own vocabulary and so can never be read.
        $r = New-FixtureRepo $script:Payload
        $i = New-FixtureInstall @{
            'skills/a/SKILL.md' = "line one`nline two`n"
            'hooks/h.sh'        = "#!/usr/bin/env bash`necho hi`n"
            'plugin.json'       = "{`n  `"version`": `"0.7.0`"`n}`n"
        }
        $res = Invoke-Drift $r.Root $r.Sha $i
        $res.Out | Should -Not -Match 'DRIFTED|MISSING|EXTRA'
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
pwsh -NoProfile -c "Import-Module Pester -MinimumVersion 6.0.0 -MaximumVersion 6.99.99 -Force; Invoke-Pester scripts/tests/check-plugin-drift.Tests.ps1 -Output Detailed"
```
Expected: **every row fails**, because `scripts/check-plugin-drift.ps1` does not exist yet. Read the
`Tests Passed:` line - a run with no such line ABORTED and is not a result.

- [ ] **Step 3: Write the implementation**

Create `scripts/check-plugin-drift.ps1`:

```powershell
#!/usr/bin/env pwsh
# Fails when an INSTALLED plugin tree has drifted from the repo payload at a DECLARED sha.
#
# WHY THIS EXISTS. MEASURED 2026-08-31: the installed clavity plugin differed from the repo in 16 files,
# was missing 3 outright and carried 1 stray backup, while BOTH sides reported "version": "0.7.0". A
# version string that does not move when 193 lines do is not a detector, so this compares CONTENT.
#
# WHY A DECLARED SHA AND NOT HEAD. A phase that edits a review skill must sometimes run its review under
# the PRE-change rules; pinning the check to ambient HEAD would make that impossible to satisfy (install
# the older copy and the check reds; satisfy the check and the review runs under the rules it is
# reviewing). Naming the sha dissolves that: the caller declares what the install is supposed to be.
#
# WHY NORMALIZED COMPARISON. The installed tree is a copy of a WORKTREE (CRLF for .md/.json under
# core.autocrlf, LF for .sh), while `git show` returns the COMMITTED form (LF). MEASURED: raw-byte
# comparison reports 19 drifted files where 16 have really drifted. CRLF -> LF, then hash.
#
# EXIT CODES: 0 = clean · 1 = drift found · 2 = CANNOT CHECK (bad sha, absent install, bad payload path).
# 2 is deliberately NOT 0: a checker that cannot check must never report clean.
[CmdletBinding()]
param(
    [string]$Sha           = 'HEAD',
    [string]$RepoRoot,
    [string]$InstalledRoot,
    [string]$PluginPath    = 'clavity-dotnet/plugin'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
if (-not $InstalledRoot) {
    $InstalledRoot = Join-Path $env:LOCALAPPDATA 'Programs\clavity-dotnet\plugins\clavity'
}

function Fail2([string]$m) { Write-Host "check-plugin-drift: $m" -ForegroundColor Yellow; exit 2 }

# --- the sha must EXIST, not merely look like one -------------------------------------------------
# `agy-mark.sh` shipped the other shape (accept any 40-char string) and wrote a phantom marker on
# 2026-08-31. Shape is not existence.
& git -C $RepoRoot cat-file -e "$Sha^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) { Fail2 "declared sha '$Sha' does not exist in $RepoRoot - cannot check" }
$resolved = (& git -C $RepoRoot rev-parse $Sha).Trim()

if (-not (Test-Path -LiteralPath $InstalledRoot)) {
    Fail2 "installed root '$InstalledRoot' does not exist - the plugin is not installed, so nothing was checked"
}

$prefix = $PluginPath.TrimEnd('/') + '/'
$repoFiles = @(& git -C $RepoRoot ls-tree -r --name-only $resolved -- $PluginPath |
    Where-Object { $_ -and $_.StartsWith($prefix) } |
    ForEach-Object { $_.Substring($prefix.Length) })
if ($repoFiles.Count -eq 0) { Fail2 "no files under '$PluginPath' at $resolved - wrong payload path?" }

$installed = @(Get-ChildItem -LiteralPath $InstalledRoot -Recurse -File |
    ForEach-Object { $_.FullName.Substring($InstalledRoot.Length).TrimStart('\', '/') -replace '\\', '/' })

function Get-BlobBytes {
    param([string]$RepoRoot, [string]$Rev, [string]$Path)
    # RAW BYTES via the process BaseStream - the repo's documented raw-byte transport (the same one
    # curate-commit uses on stdin, and for the same reason).
    #
    # MEASURED 2026-08-31 against `git cat-file -s` as ground truth on an 8142-byte blob:
    #   `git cat-file blob ... | Set-Content -AsByteStream`  ->  0 bytes, and it THROWS
    #        "Cannot proceed with byte encoding. When using byte encoding the content must be of type byte."
    #        because a PowerShell pipeline delivers STRINGS, not bytes.
    #   ProcessStartInfo + BaseStream                        ->  8142 bytes, exact.
    # Do not "simplify" this back into a pipeline.
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'git'
    foreach ($a in @('-C', $RepoRoot, 'cat-file', 'blob', "${Rev}:${Path}")) { $null = $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $p  = [System.Diagnostics.Process]::Start($psi)
    $ms = [IO.MemoryStream]::new()
    try {
        $p.StandardOutput.BaseStream.CopyTo($ms)
        $p.WaitForExit()
        if ($p.ExitCode -ne 0) { throw "git cat-file blob ${Rev}:${Path} exited $($p.ExitCode)" }
        # The leading comma stops PowerShell unrolling the array into the pipeline.
        ,$ms.ToArray()
    } finally { $ms.Dispose() }
}

function Get-NormalizedHash([byte[]]$Bytes) {
    # CRLF -> LF on the RAW BYTES; do not round-trip through a string, which would re-encode.
    $out = [System.Collections.Generic.List[byte]]::new($Bytes.Length)
    for ($i = 0; $i -lt $Bytes.Length; $i++) {
        if ($Bytes[$i] -eq 13 -and ($i + 1) -lt $Bytes.Length -and $Bytes[$i + 1] -eq 10) { continue }
        $out.Add($Bytes[$i])
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { -join ($sha.ComputeHash($out.ToArray()) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha.Dispose() }
}

$drifted = @(); $missing = @(); $extra = @(); $same = 0
foreach ($f in ($repoFiles | Sort-Object)) {
    $ip = Join-Path $InstalledRoot ($f -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $ip)) { $missing += $f; continue }
    $rb = Get-BlobBytes -RepoRoot $RepoRoot -Rev $resolved -Path "${prefix}${f}"
    $ib = [IO.File]::ReadAllBytes($ip)
    if ((Get-NormalizedHash $rb) -ne (Get-NormalizedHash $ib)) { $drifted += $f } else { $same++ }
}
foreach ($f in ($installed | Sort-Object)) { if ($repoFiles -notcontains $f) { $extra += $f } }

foreach ($f in $missing) { Write-Host "MISSING  $f" -ForegroundColor Red }
foreach ($f in $drifted) { Write-Host "DRIFTED  $f" -ForegroundColor Red }
foreach ($f in $extra)   { Write-Host "EXTRA    $f" -ForegroundColor Red }

$bad = $missing.Count + $drifted.Count + $extra.Count
if ($bad -gt 0) {
    Write-Host ""
    Write-Host ("check-plugin-drift: {0} file(s) differ from {1} ({2} drifted, {3} missing, {4} extra, {5} identical)" -f `
        $bad, $resolved.Substring(0, 7), $drifted.Count, $missing.Count, $extra.Count, $same) -ForegroundColor Red
    Write-Host "Reinstall the plugin, then re-run. Until then every discipline is running instructions nobody has verified." -ForegroundColor Red
    exit 1
}
Write-Host ("check-plugin-drift: OK - {0} payload file(s) identical to {1}" -f $same, $resolved.Substring(0, 7)) -ForegroundColor Green
exit 0
```

**SHAPE-DIVERGENCE STOP.** `Get-BlobBytes` reads the blob through `ProcessStartInfo` +
`StandardOutput.BaseStream` on purpose, and the first draft of this plan got it wrong in a way that only
measurement caught: `git cat-file blob ... | Set-Content -AsByteStream` produces **0 bytes and throws**,
because a PowerShell pipeline carries strings. `Get-Content -Raw` and `(& git show ...) -join` re-encode
just as badly. If making this compile or run would change the shape, type or encoding of any value here -
even trivially - STOP and report `[original] -> [yours] because <reason>`. "It runs" is not justification;
this comparison is the entire product.

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```
pwsh -NoProfile -c "Import-Module Pester -MinimumVersion 6.0.0 -MaximumVersion 6.99.99 -Force; Invoke-Pester scripts/tests/check-plugin-drift.Tests.ps1 -Output Detailed"
```
Expected: `Tests Passed: 8, Failed: 0`. **Read the count.** A `-Path` that matches nothing exits 0 with
`Tests Passed: 0`, which reads like success and is not.

- [ ] **Step 5: Register the suite in the fast partition**

Registration is an explicit list, not a glob, and `test-suite-registration.Tests.ps1` fails if a suite on
disk is in neither half. In `justfile:100`, inside the `test-scripts-fast:` recipe's quoted array, add
`'scripts/tests/check-plugin-drift.Tests.ps1', ` immediately before
`'scripts/tests/check-agy-discipline-skills.Tests.ps1'`.

- [ ] **Step 6: Add its row to the runtimes table**

In `scripts/tests/_partition.md`, inside the fenced block that opens at `:529`, add a row in the same
column shape as its neighbours (suite name, measured time, test count):

```
check-plugin-drift.Tests.ps1                      <MEASURED>s    8 tests   <- FAST. Fixtures are a throwaway
                                                                     git repo + fake install under
                                                                     $TestDrive; reads no live install.
```

Replace `<MEASURED>` with the real figure from a run - do not invent one. The registration suite parses
this row and compares the count against a live discovery, so a wrong count reds the gate.

- [ ] **Step 7: Verify the registration gate is green**

Run:
```
pwsh -NoProfile -c "Import-Module Pester -MinimumVersion 6.0.0 -MaximumVersion 6.99.99 -Force; Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1 -Output Detailed"
```
Expected: all rows pass. If `every _partition.md row states the CURRENT test count` fails, the count you
wrote in Step 6 is wrong - fix the row, not the test.

- [ ] **Step 8: Run it against the REAL install and record the result**

This is the real-world proof, and it is a manual verification step, not a test row.

Run:
```
pwsh -NoProfile -File scripts/check-plugin-drift.ps1
```
Expected **before** the reinstall in Task 2: **exit 1**, reporting **16 DRIFTED, 3 MISSING, 1 EXTRA,
11 identical**, with `hooks/agy-mark.sh`, `hooks/agy-shield-lib.sh` and `hooks/assertion-strength-reminder.sh`
named as MISSING and `.mcp.json.bak-2026-08-25` as EXTRA.

If the numbers differ from those, **stop and report it** rather than adjusting the plan: the install may
have changed since 2026-08-31, and that is information, not noise.

- [ ] **Step 9: Commit**

```bash
git add scripts/check-plugin-drift.ps1 scripts/tests/check-plugin-drift.Tests.ps1 justfile scripts/tests/_partition.md
git commit -m "feat(0c): detect installed-plugin drift by content hash at a declared sha"
```

### Task 2: 0c-local - reinstall, then confirm the detector goes green

**Files:** none in the repo. This task changes **local machine state only** and cannot be committed.

- [ ] **Step 1: Reinstall the clavity plugin**

Reinstall from `clavity-dotnet/install/clavity-install.ps1` (or re-run the installer you normally use) so
the installed tree at `$env:LOCALAPPDATA\Programs\clavity-dotnet\plugins\clavity` matches the repo payload.

**Ask the operator to do this if you are an agent** - it writes outside the repository, and the plan's own
rule is that a step touching machine state is the operator's.

- [ ] **Step 2: Delete the stray backup the detector found**

```
Remove-Item -LiteralPath "$env:LOCALAPPDATA\Programs\clavity-dotnet\plugins\clavity\.mcp.json.bak-2026-08-25"
```
This is the one EXTRA file. A reinstall will not remove it, because installers add and overwrite rather
than prune.

- [ ] **Step 3: Re-run the detector and confirm it is clean**

```
pwsh -NoProfile -File scripts/check-plugin-drift.ps1
```
Expected: **exit 0**, `check-plugin-drift: OK - 30 payload file(s) identical to <sha>`.

If any file still drifts, the installer is not shipping it - **report which, and stop.** That is a finding
about the installer, and inventing a deny-list for it here would rebuild the fail-open this task closes.

- [ ] **Step 4: Confirm the four review skills specifically**

```
pwsh -NoProfile -c "'adversarial-panel-review','agy-capstone','agy-first','agy-test-audit' | ForEach-Object { $r = 'clavity-dotnet/plugin/skills/' + $_ + '/SKILL.md'; $i = Join-Path $env:LOCALAPPDATA ('Programs\clavity-dotnet\plugins\clavity\skills\' + $_ + '\SKILL.md'); '{0,-26} repo={1,-5} installed={2}' -f $_, (Get-Content $r).Count, (Get-Content $i).Count }"
```
Expected: the two counts equal on all four rows. Before this task they were 360/240, 429/236, 214/123 and
332/159.

**Note the line counts are a convenience readout here, not the gate.** `ls-pairing/SKILL.md` measured 25
lines on BOTH sides while differing in content (em-dash versus ASCII hyphen), which is exactly why the
detector hashes rather than counts.

---

## COMMIT 2 - 0a: reconcile the index, and guard it

### Task 3: `check-roadmap-claims.ps1` - a guard that is RED before the fix

**Files:**
- Create: `scripts/tests/check-roadmap-claims.Tests.ps1`
- Create: `scripts/check-roadmap-claims.ps1`

This guard is unusual and deliberately so: **it fails on the real repository right now**, and Task 4 is
what turns it green. That coupling is the point - the guard proves the reconcile happened instead of
asserting it did.

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/check-roadmap-claims.Tests.ps1`:

```powershell
# Fixture ROADMAPs under $TestDrive plus a throwaway git repo for the sha-existence half. The real
# ROADMAP is exercised by exactly one row, and only AFTER Task 4 reconciles it.
BeforeAll {
    $script:Script   = (Resolve-Path (Join-Path $PSScriptRoot '..' 'check-roadmap-claims.ps1')).Path
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

    function New-ClaimRepo {
        param([string]$Roadmap, [hashtable]$Files = @{})
        $repo = Join-Path $TestDrive ("rm-" + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $repo -Force
        & git -C $repo init -q
        & git -C $repo config user.email 't@t.t'
        & git -C $repo config user.name  'T'
        foreach ($rel in $Files.Keys) {
            $p = Join-Path $repo ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            $null = New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force
            [IO.File]::WriteAllText($p, $Files[$rel])
        }
        $rmPath = Join-Path $repo 'ROADMAP.md'
        [IO.File]::WriteAllText($rmPath, $Roadmap)
        & git -C $repo add -A
        & git -C $repo commit -q -m 'fixture'
        [pscustomobject]@{ Root = $repo; Roadmap = $rmPath; Sha = (& git -C $repo rev-parse HEAD).Trim() }
    }

    function Invoke-Claims {
        param([string]$RepoRoot, [string]$RoadmapPath)
        $out = & pwsh -NoProfile -File $script:Script -RepoRoot $RepoRoot -RoadmapPath $RoadmapPath 2>&1 | Out-String
        [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
    }
}

Describe 'check-roadmap-claims.ps1 - the (N lines) half' {

    It 'exits 0 when a line-count claim is correct' {
        $f = New-ClaimRepo -Files @{ 'skills/a/SKILL.md' = "1`n2`n3`n" } `
             -Roadmap "Entry. ``skills/a/SKILL.md`` (3 lines) is fine.`n"
        $r = Invoke-Claims $f.Root $f.Roadmap
        $r.Code | Should -Be 0 -Because "output was:`n$($r.Out)"
    }

    It 'exits 1 and names the file when a line-count claim is STALE' {
        # This is the 14h failure exactly: the entry claimed 123 lines against an actual 214.
        $f = New-ClaimRepo -Files @{ 'skills/a/SKILL.md' = "1`n2`n3`n" } `
             -Roadmap "Entry. ``skills/a/SKILL.md`` (99 lines) is stale.`n"
        $r = Invoke-Claims $f.Root $f.Roadmap
        $r.Code | Should -Be 1
        $r.Out  | Should -Match 'skills/a/SKILL\.md'
        $r.Out  | Should -Match '99'
        $r.Out  | Should -Match '3'
    }

    It 'exits 1 when a claimed file does not exist at all' {
        $f = New-ClaimRepo -Roadmap "Entry. ``skills/ghost/SKILL.md`` (10 lines).`n"
        $r = Invoke-Claims $f.Root $f.Roadmap
        $r.Code | Should -Be 1
        $r.Out  | Should -Match 'UNRESOLVED|not found'
    }

    It 'exits 1 when a claim resolves to two tracked files with DIFFERENT counts' {
        # Both plugins carry byte-identical copies of these skills, so a bare `agy-first/SKILL.md`
        # resolves twice. Equal counts are fine; unequal means the pair has diverged and the claim is
        # ambiguous - which must be an error, not a coin flip on whichever path sorted first.
        $f = New-ClaimRepo -Files @{
                'p1/skills/a/SKILL.md' = "1`n2`n3`n"
                'p2/skills/a/SKILL.md' = "1`n2`n"
             } -Roadmap "Entry. ``skills/a/SKILL.md`` (3 lines).`n"
        $r = Invoke-Claims $f.Root $f.Roadmap
        $r.Code | Should -Be 1
        $r.Out  | Should -Match 'AMBIGUOUS'
    }
}

Describe 'check-roadmap-claims.ps1 - the sha-existence half' {

    It 'exits 0 when a sha cited beside a closure token exists' {
        $f = New-ClaimRepo -Roadmap "placeholder`n"
        $rm = Join-Path $f.Root 'R2.md'
        [IO.File]::WriteAllText($rm, "Item. SHIPPED 2026-01-01 (``$($f.Sha.Substring(0,7))``).`n")
        $r = Invoke-Claims $f.Root $rm
        $r.Code | Should -Be 0 -Because "output was:`n$($r.Out)"
    }

    It 'exits 1 when a sha beside a closure token does NOT exist' {
        # The agy-mark.sh defect class: a 40-character string that looks like a sha and is not one.
        $f = New-ClaimRepo -Roadmap "placeholder`n"
        $rm = Join-Path $f.Root 'R2.md'
        [IO.File]::WriteAllText($rm, "Item. SHIPPED 2026-01-01 (``63eb46f0000000000000000000000000deadbeef``).`n")
        $r = Invoke-Claims $f.Root $rm
        $r.Code | Should -Be 1
        $r.Out  | Should -Match 'PHANTOM|does not exist'
    }

    It 'IGNORES a sha-shaped string on a line with no closure token' {
        # Scope control. The ROADMAP quotes hashes in prose all over; only closure claims are bound.
        $f = New-ClaimRepo -Roadmap "placeholder`n"
        $rm = Join-Path $f.Root 'R2.md'
        [IO.File]::WriteAllText($rm, "Discussion of ``63eb46f0000000000000000000000000deadbeef`` in passing.`n")
        $r = Invoke-Claims $f.Root $rm
        $r.Code | Should -Be 0 -Because "output was:`n$($r.Out)"
    }
}

Describe 'check-roadmap-claims.ps1 - the real repository' {
    It 'passes on the committed ROADMAP' {
        # RED until Task 4 reconciles the four stale headers. That is deliberate: this row is the
        # oracle that the reconcile actually happened, rather than a claim that it did.
        $r = Invoke-Claims $script:RepoRoot (Join-Path $script:RepoRoot 'clavity-dotnet' 'ROADMAP.md')
        $r.Code | Should -Be 0 -Because "the real ROADMAP must satisfy its own checkable claims; output was:`n$($r.Out)"
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```
pwsh -NoProfile -c "Import-Module Pester -MinimumVersion 6.0.0 -MaximumVersion 6.99.99 -Force; Invoke-Pester scripts/tests/check-roadmap-claims.Tests.ps1 -Output Detailed"
```
Expected: all rows fail (no script yet).

- [ ] **Step 3: Write the implementation**

Create `scripts/check-roadmap-claims.ps1`:

```powershell
#!/usr/bin/env pwsh
# Verifies the ROADMAP's own MECHANICALLY CHECKABLE claims. It does not judge whether an item is done -
# nothing can - it checks the evidence an entry cites about the repository.
#
# WHY THIS EXISTS. The ROADMAP has read OPEN for shipped work FOUR times (13b, 17, 18, 19, 14h). The rule
# earned from that - "whoever closes an item writes its closing sha in the same commit" - had ZERO
# implementation when this was written, and a rule with no implementation is worse than none because it is
# believed. MEASURED 2026-08-31: all FOUR of the ROADMAP's `(N lines)` claims were wrong, and all four sat
# in the 14h entry - the one that had been stale for sixteen days. Precision 4/4 on the real defect.
#
# TWO CHECKS, deliberately narrow so they cannot be argued with:
#   A. every `path` (N lines) claim matches the tracked file it names;
#   B. every backticked 7-40 hex sha on a line ALSO carrying a closure token actually exists.
# Check B passed 28/28 when written - it is a trap for a future phantom, not a backlog.
#
# EXIT CODES: 0 = every claim holds · 1 = at least one claim is false · 2 = cannot check.
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$RoadmapPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot)    { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
if (-not $RoadmapPath) { $RoadmapPath = Join-Path $RepoRoot 'clavity-dotnet' 'ROADMAP.md' }

if (-not (Test-Path -LiteralPath $RoadmapPath)) {
    Write-Host "check-roadmap-claims: '$RoadmapPath' not found - nothing was checked" -ForegroundColor Yellow
    exit 2
}

$tracked = @(& git -C $RepoRoot ls-files)
if ($LASTEXITCODE -ne 0) {
    Write-Host "check-roadmap-claims: '$RepoRoot' is not a git repository - nothing was checked" -ForegroundColor Yellow
    exit 2
}

$lines = [IO.File]::ReadAllText($RoadmapPath) -split "`r?`n"
$problems = @()

# --- A. line-count claims -------------------------------------------------------------------------
$claimRe = [regex]'`([A-Za-z0-9_./-]+\.(?:md|ps1|sh|cs|rs|json))`\s*\((\d+)\s+lines\)'
for ($i = 0; $i -lt $lines.Count; $i++) {
    foreach ($m in $claimRe.Matches($lines[$i])) {
        $rel     = $m.Groups[1].Value
        $claimed = [int]$m.Groups[2].Value
        $hits    = @($tracked | Where-Object { $_ -eq $rel -or $_.EndsWith("/$rel") })
        if ($hits.Count -eq 0) {
            $problems += "UNRESOLVED  ROADMAP:$($i+1)  ``$rel`` is not a tracked file"
            continue
        }
        $counts = @($hits | ForEach-Object {
            ([IO.File]::ReadAllText((Join-Path $RepoRoot ($_ -replace '/', [IO.Path]::DirectorySeparatorChar))) -split "`n").Count - 1
        })
        if (@($counts | Sort-Object -Unique).Count -gt 1) {
            $problems += "AMBIGUOUS   ROADMAP:$($i+1)  ``$rel`` resolves to $($hits.Count) tracked files with different counts ($($counts -join ', ')) - name the path"
            continue
        }
        if ($counts[0] -ne $claimed) {
            $problems += "STALE       ROADMAP:$($i+1)  ``$rel`` claims $claimed lines, actual $($counts[0])"
        }
    }
}

# --- B. sha existence beside a closure token -------------------------------------------------------
$closure = [regex]'SHIPPED|RULED|OWNER ACCEPTED|CLOSED'
$shaRe   = [regex]'`([0-9a-f]{7,40})`'
$seen    = @{}
for ($i = 0; $i -lt $lines.Count; $i++) {
    if (-not $closure.IsMatch($lines[$i])) { continue }
    foreach ($m in $shaRe.Matches($lines[$i])) {
        $s = $m.Groups[1].Value
        $key = "$s|$($i+1)"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        & git -C $RepoRoot cat-file -e "$s^{commit}" 2>$null
        if ($LASTEXITCODE -ne 0) {
            $problems += "PHANTOM     ROADMAP:$($i+1)  ``$s`` does not exist in this repository"
        }
    }
}

if ($problems.Count -gt 0) {
    foreach ($p in $problems) { Write-Host $p -ForegroundColor Red }
    Write-Host ""
    Write-Host "check-roadmap-claims: $($problems.Count) false claim(s) in $RoadmapPath" -ForegroundColor Red
    exit 1
}
Write-Host "check-roadmap-claims: OK - every line-count claim and closure sha in $RoadmapPath holds" -ForegroundColor Green
exit 0
```

- [ ] **Step 4: Run the tests - 8 of 9 must pass, and the 9th must fail for the RIGHT reason**

Run:
```
pwsh -NoProfile -c "Import-Module Pester -MinimumVersion 6.0.0 -MaximumVersion 6.99.99 -Force; Invoke-Pester scripts/tests/check-roadmap-claims.Tests.ps1 -Output Detailed"
```
Expected: `Tests Passed: 7, Failed: 1` (the suite has **8** `It` blocks). The single failure must be
`the real repository.passes on the committed ROADMAP`, and its output must name **four STALE claims at
ROADMAP:1222, 1223, 1224 and 1225**. If it fails for any other reason, or names a different count, stop and
diagnose - do not proceed to Task 4.

- [ ] **Step 5: Confirm the guard discriminates (non-vacuity, half B)**

Half A is proven non-vacuous by the real ROADMAP failing it. Half B currently passes 28/28, so prove it
can fail:

```
pwsh -NoProfile -c "$p = Join-Path $env:TEMP 'rm-mutant.md'; Set-Content -LiteralPath $p -Value 'Item. SHIPPED 2026-01-01 (`63eb46f0000000000000000000000000deadbeef`).'; pwsh -NoProfile -File scripts/check-roadmap-claims.ps1 -RoadmapPath $p; 'exit=' + $LASTEXITCODE"
```
Expected: `PHANTOM` on the line, and `exit=1`. `63eb46f...` was verified non-existent in this repository on
2026-08-31 while `99910c0`, `519833f`, `64d5be4` and `a652d8d` all exist - a passing and a failing control
on the same mechanism.

### Task 4: reconcile the four stale headers - the guard turns green

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md:1215` (§14h), `:1222-1225` (the four line-counts), `:1343` (§17),
  `:1419` (§18), `:1652` (§19)

All four closing shas below were verified to exist on 2026-08-31.

- [ ] **Step 1: Close §14h**

At `clavity-dotnet/ROADMAP.md:1215-1216`, replace:

```
**§14h — two AGY-* review disciplines prescribe a SINGLE persona, so their consults are single-voice
by instruction.** ▶ **OPEN — promoted at the 2026-08-15 triage.**
```

with:

```
**§14h — two AGY-* review disciplines prescribe a SINGLE persona, so their consults are single-voice
by instruction.** ✅ **SHIPPED 2026-08-16** (`a652d8d` — "refactor(shield): 14c + 14h — disciplines write
via agy-mark.sh and seat a panel"). **Closed retroactively on 2026-08-31**: the header read `OPEN` for
fifteen days after the fix landed, and a sequencing spec scheduled it as live work as a result. Verified at
HEAD: `agy-first/SKILL.md:103` reads "**Seat a panel, not a persona.**" with seat rotation at `:112`, and
`agy-test-audit/SKILL.md:109` reads "**Seat the audit, do not send one voice.**" placed after the
`## The audit round` heading — the insertion point this entry itself prescribed. The old
"Optional per-run mitigation: rotate the audit's lens" wording is gone.
```

- [ ] **Step 2: Correct the four line-count claims**

At `:1222-1225`, the measurement table's four rows carry counts taken on 2026-08-15 that no longer hold.
Update each to its current value, and mark the table as historical so the numbers are not read as current:

| file | claimed | actual |
|---|---|---|
| `agy-first/SKILL.md` | 123 | **214** |
| `agy-test-audit/SKILL.md` | 231 | **332** |
| `agy-capstone/SKILL.md` | 289 | **429** |
| `adversarial-panel-review/SKILL.md` | 297 | **360** |

Add this sentence immediately above the table:

```
**The line counts below were measured 2026-08-15 and are CORRECTED to their 2026-08-31 values.** The
originals (123 / 231 / 289 / 297) were the INSTALLED plugin's, which had drifted from the repo under an
unchanged version string — see Phase 0c. `scripts/check-roadmap-claims.ps1` now fails if any of them rots
again.
```

- [ ] **Step 3: Close §17**

At `:1343`, replace `### §17 — anomalies promoted at the 2026-08-17 triage — ▶ **OPEN**` with:

```
### §17 — anomalies promoted at the 2026-08-17 triage — ✅ **CLOSED 2026-08-30** (§17a SHIPPED `99910c0`, AGY-CAPSTONE GREEN per ledger `eb26709`; §17b RULED KILLED — see the sub-entries)
```

- [ ] **Step 4: Close §18**

At `:1419`, replace the `▶ **OPEN. BOTH gating measurements are DONE...**` status with:

```
### §18 — SEED/GROWTH split for the driver cheatsheet — ✅ **SHIPPED, AGY-CAPSTONE GREEN after 7 rounds** (ledger `519833f`)
```

- [ ] **Step 5: Close §19**

At `:1652`, replace `▶ **DECIDED, DEFERRED**` with:

```
### §19 — `agy-mark.sh` exit codes: collapse the tri-state to 0 / non-zero — ✅ **SHIPPED 2026-08-29** (`64d5be4`, same capstone GREEN as §17a — ledger `eb26709`)
```

- [ ] **Step 6: Run the guard against the real ROADMAP**

```
pwsh -NoProfile -File scripts/check-roadmap-claims.ps1
```
Expected: `check-roadmap-claims: OK - every line-count claim and closure sha in ...ROADMAP.md holds`,
exit 0.

- [ ] **Step 7: Run the full suite for this task**

```
pwsh -NoProfile -c "Import-Module Pester -MinimumVersion 6.0.0 -MaximumVersion 6.99.99 -Force; Invoke-Pester scripts/tests/check-roadmap-claims.Tests.ps1 -Output Detailed"
```
Expected: `Tests Passed: 8, Failed: 0`. The row that failed in Task 3 Step 4 now passes **because the
ROADMAP was fixed, not because the test was**. If you find yourself editing that row, stop: the oracle wins.

- [ ] **Step 8: Register the suite and add its runtimes row**

In `justfile:100` (`test-scripts-fast:`), add `'scripts/tests/check-roadmap-claims.Tests.ps1', ` before
`'scripts/tests/check-agy-discipline-skills.Tests.ps1'`. Then add its row to the fenced table in
`scripts/tests/_partition.md`, with a **measured** time and `8 tests`. **That count is load-bearing:**
`test-suite-registration.Tests.ps1` parses this row and compares it against a live discovery, so a wrong
number reds the gate - which is how this very figure was caught wrong in the plan's self-audit.

- [ ] **Step 9: Commit**

```bash
git add scripts/check-roadmap-claims.ps1 scripts/tests/check-roadmap-claims.Tests.ps1 clavity-dotnet/ROADMAP.md justfile scripts/tests/_partition.md
git commit -m "fix(0a): reconcile four stale ROADMAP headers and guard the claims that rotted"
```

---

## COMMIT 3 - 0b: make the suite oracle guard itself

### Task 5: assert that the registration oracle actually ran

**The defect, stated precisely.** `scripts/tests/test-suite-registration.Tests.ps1:265` already asserts
`$discovered.Count | Should -Be $onDiskCount` - **exact equality**, against `git ls-files '*.Tests.ps1'`
(`:87-92`). That is a strictly better oracle than the `TotalCount -lt 100` floor at
`.github/workflows/ci-scripts.yml:203`, and it already exists, so **do not rebuild it**.

What it cannot do is guard itself. Its row only runs if that suite is discovered; if *that* file is the one
misnamed or lost, the row never executes and the only surviving backstop is the floor it was supposed to
make redundant - a floor that MEASURED 2026-08-31 tolerates losing about 89% of 982 assertions.

**Files:**
- Modify: `.github/workflows/ci-scripts.yml:199-203`
- Modify: `scripts/tests/test-suite-registration.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Add this row to `scripts/tests/test-suite-registration.Tests.ps1`, inside the top-level `Describe`. Reading
a workflow's text is an established pattern here (`check-injected-context.Tests.ps1:329` does the same).

```powershell
    It 'CI asserts that THIS suite itself was discovered' {
        # SELF-GUARDING ORACLE. The equality row in this file proves every other suite was discovered -
        # but only while this file is itself discovered. If this one is misnamed or deleted, its row
        # never runs and CI falls back to `TotalCount -lt 100`, which MEASURED 2026-08-31 tolerates
        # losing ~89% of 982 assertions. So CI must name this suite explicitly, and that naming is what
        # this row pins. Source-text pinning is used because the assertion lives in YAML, where there is
        # no behaviour to call.
        $wf = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/ci-scripts.yml') -Raw
        $wf | Should -Match 'test-suite-registration\.Tests\.ps1' -Because 'ci-scripts.yml must name this suite so its absence cannot pass quietly'
        $wf | Should -Match 'registration oracle' -Because 'the guard must say WHY it exists, or a later reader will delete it as redundant'
    }
```

- [ ] **Step 2: Run it to verify it fails**

```
pwsh -NoProfile -c "Import-Module Pester -MinimumVersion 6.0.0 -MaximumVersion 6.99.99 -Force; Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1 -Output Detailed"
```
Expected: exactly one failure, the new row, because `ci-scripts.yml` does not yet name the suite.

- [ ] **Step 3: Add the CI assertion**

In `.github/workflows/ci-scripts.yml`, in the `Pester - full scripts suite (pwsh 7)` step, insert after the
`TotalCount -lt 100` line at `:203`:

```yaml
          # The registration oracle must itself have run. test-suite-registration.Tests.ps1 asserts an
          # EXACT equality between discovered containers and `git ls-files '*.Tests.ps1'`, which is what
          # proves every other suite was discovered - but that row only runs while this suite is itself
          # discovered. Without this check, losing THAT file degrades the whole gate to the count floor
          # above, which tolerates losing ~89% of the suite.
          $oracle = @($r.Containers | Where-Object { (Split-Path $_.Item -Leaf) -eq 'test-suite-registration.Tests.ps1' })
          if ($oracle.Count -ne 1) { throw "the registration oracle did not run (found $($oracle.Count) container(s) named test-suite-registration.Tests.ps1) - it is the check that proves every other suite was discovered, so this run cannot be trusted" }
```

- [ ] **Step 4: Run the test to verify it passes**

```
pwsh -NoProfile -c "Import-Module Pester -MinimumVersion 6.0.0 -MaximumVersion 6.99.99 -Force; Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1 -Output Detailed"
```
Expected: all rows pass, including the new one. Note the count went up by one - update this suite's row in
`scripts/tests/_partition.md` accordingly, or its own `every _partition.md row states the CURRENT test
count` row will red.

- [ ] **Step 5: Prove the CI guard is not vacuous**

The YAML cannot be unit-tested, so exercise its logic directly against a container set that lacks the
oracle:

```
pwsh -NoProfile -c "$r = [pscustomobject]@{ Containers = @([pscustomobject]@{ Item = 'scripts/tests/other.Tests.ps1' }) }; $oracle = @($r.Containers | Where-Object { (Split-Path $_.Item -Leaf) -eq 'test-suite-registration.Tests.ps1' }); if ($oracle.Count -ne 1) { 'WOULD THROW - correct' } else { 'VACUOUS - the guard cannot fail' }"
```
Expected: `WOULD THROW - correct`. Then run the same snippet with the container named
`scripts/tests/test-suite-registration.Tests.ps1` and expect no throw - a passing and a failing control on
the same expression.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/ci-scripts.yml scripts/tests/test-suite-registration.Tests.ps1 scripts/tests/_partition.md
git commit -m "fix(0b): assert the suite-registration oracle itself ran"
```

### Task 6: run the gates the repository actually uses

- [ ] **Step 1: Run the fast script gate**

```
pwsh -NoProfile -c "just test-scripts-fast"
```
Expected: a `Tests Passed:` line with **zero failures**. There is no `Tests Passed:` line on an aborted
run - absence of the line is not a pass.

**Do not run both halves at once, and never two Pester suites concurrently.** The fast half measured 576s
against a 600s foreground cap; run it backgrounded and stay idle until it reports.

- [ ] **Step 2: Confirm the three new/changed checkers are green**

```
pwsh -NoProfile -File scripts/check-plugin-drift.ps1
pwsh -NoProfile -File scripts/check-roadmap-claims.ps1
```
Expected: both exit 0.

- [ ] **Step 3: Verify what actually landed, by code rather than by checkbox**

```bash
git log --oneline -3
git show --stat HEAD~2 HEAD~1 HEAD
```
Expected: exactly three commits, touching only the files named in this plan. A checkbox is not evidence a
task landed; the diff is.

---

## What this plan deliberately does NOT do

- **It does not wire the drift detector into a hook.** Round 3 of the panel established that a blocking
  pre-commit hook landing before the reinstall makes the first commit fail its own hook. The detector ships
  as a script plus a justfile-reachable command; **wiring it to SessionStart or pre-commit is a separate
  decision for the owner**, and it should only be taken once Task 2 has left the install clean.
- **It does not require every SHIPPED entry to name a sha.** MEASURED: 43 lines carry a closure token and
  only 14 carry a backticked sha, so that rule would red 29 lines immediately, many of them prose rather
  than section headers. The guard checks the shas that ARE cited.
- **It does not touch the `TotalCount -lt 100` floor.** It is now a backstop behind a real oracle rather
  than the primary gate. Raising the integer would rot; the equality row is the answer.
- **It does not delete the three unused `test-scripts*` justfile recipes.** They are the only local
  invocation path this suite has or could have, and `:131` of the registration suite keys its rename
  detector on them. That decision is the owner's and is recorded in the spec.

---

## Self-review

**Spec coverage.** Phase 0c → Tasks 1-2 (detector, declared sha, content hash, whole payload, local
reinstall separated from the committable half). Phase 0a → Tasks 3-4 (four headers reconciled; the guard
that closes the corruption mechanism; `git cat-file -e` rather than shape-matching). Phase 0b → Task 5
(the self-guarding oracle). The three-independent-commits ordering (0c, 0a, 0b) is the commit structure.

**Round-3 constraints, each mapped to a step.** Declared sha not ambient HEAD → Task 1 Step 3, `-Sha`
parameter plus the `cat-file -e` gate. Whole payload not skills-only → Task 1 Step 3 enumerates via
`git ls-tree` over the entire plugin path (30 files, including 16 hooks and both json files). Sha existence
not shape → Task 3 Step 3 half B, with a failing control at Step 5. No blocking hook before the reinstall →
the "deliberately does NOT do" section. The enumeration crossing a trust boundary → Task 4 ships the
command, and Task 3's guard re-runs it mechanically rather than trusting a generated list.

**Placeholder scan.** One intentional placeholder remains: `<MEASURED>` for the two `_partition.md`
runtime figures, in Task 1 Step 6 and Task 4 Step 8. It is marked, and both steps say explicitly to take a
real figure rather than invent one - a fabricated timing would be caught by the registration suite anyway.

**Type consistency.** `check-plugin-drift.ps1` exposes `-Sha`, `-RepoRoot`, `-InstalledRoot`, `-PluginPath`;
its test helper `Invoke-Drift` passes exactly those four. `check-roadmap-claims.ps1` exposes `-RepoRoot`
and `-RoadmapPath`; `Invoke-Claims` passes exactly those two. Exit codes are 0/1/2 with the same meaning in
both scripts, and every "cannot check" path returns 2 rather than 0.

**Known gap, flagged rather than closed.** Neither guard detects the general case of a ROADMAP section
marked OPEN whose work has shipped - nothing mechanical can, since that needs a link from prose to code.
What Task 3 does is narrower and was measured to be sufficient for the case that actually recurred: the
stale entry cited evidence about the repository, and that evidence had rotted. If a future stale entry
cites no checkable evidence, this guard will not catch it, and that limitation belongs in the entry's own
review rather than in a stronger claim here.

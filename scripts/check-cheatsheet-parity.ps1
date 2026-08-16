#!/usr/bin/env pwsh
# Pre-commit parity gate for the three pinned cheatsheet paths (ROADMAP 14e).
#
# NON-DESTRUCTIVE: it generates to a TEMPORARY location and COMPARES. Writing into the working tree
# during a commit hands the author files they did not edit and can collide with work in progress.
# Repair is the author running `just gen-cheatsheet-literals` deliberately.
#
# IT COMPARES THE INDEX TO THE INDEX. Both the generator's INPUT and the literals it is compared
# against are read with `git show :<path>`, extracted the SAME way - see Get-IndexBytes below.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# $RepoRoot IS USED SEVEN TIMES BELOW AND WAS NEVER DEFINED - panel R15. Under Set-StrictMode that throws
# on the first reference, so the hook would have crashed on EVERY invocation. This is the identical defect
# class as the undefined $temps caught in round 6: code drafted alongside a helper, where only the code
# landed. The mechanical sweep that now covers FUNCTIONS does not cover VARIABLES - see the note below.
#
# Resolved from this script's own location rather than from the caller's cwd: lefthook invokes it as
# `pwsh -NoProfile -File scripts/check-cheatsheet-parity.ps1`, and a hook must not depend on where the
# committing shell happens to be.
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$Core = 'agy-autotrain/knowledge/driver-cheatsheet.core.md'
$Rs   = 'clavity-classic/src/driver_cheatsheet.rs'
$Cs   = 'clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs'

# BYTE-EXACT INDEX EXTRACTION. `>` in PowerShell is NOT a byte redirect - it is Out-File, which decodes
# the stream and re-encodes it. Measured 2026-08-14 on `git show :<core.md>`: pwsh 7 produced 3508
# bytes byte-identical to the index blob, while Windows PowerShell 5.1 produced 7032 bytes - exactly
# double - as UTF-16LE. lefthook invokes this as `pwsh` today, so the shipped path is currently safe,
# which is exactly the kind of incidental safety this item refuses to rely on.
# EVERY temp path this hook creates is registered here as it is handed out, so the finally block at the
# very bottom can remove all of them on EVERY exit path. Panel R6 caught the first draft of this step
# calling New-TempPath four times and iterating $temps once while DEFINING NEITHER - under StrictMode
# that crashes on the first call, and the cleanup block would have thrown as well, stranding the temps it
# exists to remove. Declare them before any function that uses them.
$temps = New-Object System.Collections.ArrayList
function New-TempPath {
    param([string]$Suffix)
    $p = Join-Path ([IO.Path]::GetTempPath()) ('cheatsheet-parity-' + [guid]::NewGuid().ToString('N') + $Suffix)
    [void]$temps.Add($p)
    return $p
}

function Get-IndexBytes {
    param([string]$Path, [string]$OutFile)
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'git'
    # `Arguments`, NOT `ArgumentList` - MEASURED, with a control: Windows PowerShell 5.1 (.NET Framework
    # 4.8) has NO ArgumentList property at all (`Get-Member ArgumentList` -> False; `Arguments` -> True),
    # while pwsh 7 has both. The ArgumentList form throws a runtime error on 5.1 - which would destroy
    # the exact cross-engine safety this function exists to provide. Neither path here contains a space,
    # but they are quoted anyway so a future path with one cannot break the split.
    # TrimEnd the separators: a path ending in a backslash would produce `"C:\"`, and under Windows
    # CommandLineToArgvW rules `\"` ESCAPES the closing quote, so git would receive a mangled argv.
    # Unreachable for a normal repo root, which is exactly why it would only ever bite in the one
    # environment nobody tests in.
    $psi.Arguments = ('-C "{0}" show ":{1}"' -f $RepoRoot.TrimEnd('\', '/'), $Path)
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $p = [Diagnostics.Process]::Start($psi)
    $fs = [IO.File]::Create($OutFile)
    try { $p.StandardOutput.BaseStream.CopyTo($fs) } finally { $fs.Dispose() }
    $p.WaitForExit()
    return $p.ExitCode
}

function Test-InIndex {
    param([string]$Path)
    # $LASTEXITCODE is only meaningful if git actually RAN. With $ErrorActionPreference='Stop' a missing
    # git throws rather than leaving a stale code behind, but assert it explicitly rather than relying on
    # that: a stale exit code from the previous command would otherwise read as a confident answer.
    $global:LASTEXITCODE = $null
    & git -C $RepoRoot ls-files --error-unmatch -- $Path *> $null
    if ($null -eq $LASTEXITCODE) { throw "git did not run for ls-files on $Path" }
    return ($LASTEXITCODE -eq 0)
}

# Fail REPORTS; it does not decide. Every call site below exits explicitly on the next line, so there is
# deliberately no accumulated $failed flag: a flag nothing reads implies a code path that does not exist,
# and the next reader would add one.
function Fail([string]$msg) { Write-Host "check-cheatsheet-parity: $msg" -ForegroundColor Red }

try {
    # ---- 1. PRESENCE, for ALL THREE, before extracting ANY of them. `git show :<path>` exits 128 with a
    # fatal: when a path's deletion is staged, and guarding only core.md leaves the identical crash on the
    # other side - the operator gets a raw fatal: and a rejected commit with no guidance at all.
    $coreIn = Test-InIndex $Core
    $rsIn   = Test-InIndex $Rs
    $csIn   = Test-InIndex $Cs

    if (-not $coreIn) {
        # The canonical source is going away. There is no parity to assert - but do NOT pass wholesale:
        # a surviving, possibly MUTATED, generated output would be certified on the way out.
        $left = @()
        if ($rsIn) { $left += $Rs }
        if ($csIn) { $left += $Cs }
        if ($left.Count -gt 0) {
            Fail ("$Core is being deleted, but its generated literal(s) are still present: " + ($left -join ', ') + ". Stage their deletion too, or restore $Core.")
            exit 1
        }
        Write-Host "check-cheatsheet-parity: OK - $Core and both generated literals are all being deleted; no parity to assert." -ForegroundColor Green
        exit 0
    }

    # ---- 2. PER-PATH skip, never per-run. A blanket "any deletion means skip" exits 0 while the OTHER
    # literal may have diverged - silently certifying it, which is exactly what 14e exists to prevent.
    $targets = @()
    if ($rsIn) { $targets += @{ Path = $Rs; Kind = 'rust' } } else { Write-Host "check-cheatsheet-parity: $Rs deletion is staged - skipping parity FOR THAT LITERAL ONLY." -ForegroundColor Yellow }
    if ($csIn) { $targets += @{ Path = $Cs; Kind = 'cs' }   } else { Write-Host "check-cheatsheet-parity: $Cs deletion is staged - skipping parity FOR THAT LITERAL ONLY." -ForegroundColor Yellow }
    if ($targets.Count -eq 0) { Write-Host "check-cheatsheet-parity: OK - both literals are being deleted." -ForegroundColor Green; exit 0 }

    # ---- 3. Extract BOTH SIDES from the index, the SAME way. Scoping byte-exact extraction to the
    # generator's INPUT alone guarantees a mismatch: the staged literals would come back re-encoded
    # (UTF-16LE under 5.1, measured) while the generated side is byte-exact, and parity is an EXACT
    # comparison.
    $coreTmp = New-TempPath '.md'
    if ((Get-IndexBytes $Core $coreTmp) -ne 0) { Fail "could not read $Core out of the index"; exit 1 }

    $stagedTmp = @{}
    foreach ($t in $targets) {
        $p = New-TempPath ('.staged.' + $t.Kind)
        if ((Get-IndexBytes $t.Path $p) -ne 0) { Fail ("could not read " + $t.Path + " out of the index"); exit 1 }
        $stagedTmp[$t.Path] = $p
    }

    # ---- 4. Generate into temp copies, then ASSERT THE GENERATOR'S EXIT STATUS FIRST. If the generator
    # crashes the tree is untouched, so any later "no difference" result means "nothing ran", not "nothing
    # differed" - a generator that failed to run is not evidence of parity.
    # ONLY SCAFFOLD THE TARGETS WE WILL ACTUALLY COMPARE. The generator SPLICES into an existing source
    # file, so it needs a copy to work on - but a literal whose deletion is staged is gone from the
    # worktree too, and an unconditional Copy-Item throws under $ErrorActionPreference='Stop'. That would
    # CRASH the hook on exactly the path test-table row 10 says must PASS. An empty target tells the
    # generator to skip that half (see Task 10).
    #
    # SCAFFOLD FROM THE INDEX BLOBS, NEVER FROM THE WORKTREE. This copied
    # `(Join-Path $RepoRoot $Rs)` - the worktree file - while step 5 compares the generator's output
    # against `$stagedTmp`, the INDEX blob. The generator only replaces the LITERAL lines and carries
    # everything else through, so any unstaged edit elsewhere in the .rs/.cs (an unrelated comment,
    # say) lands in the generated output and is absent from the index blob. SequenceEqual then fails
    # and the hook BLOCKS A CORRECT COMMIT, routing the developer to advice that tells them to
    # `git add` the file - which sweeps their unstaged work into the commit.
    #
    # That is a false REJECT, and it violates obligation #2 of this task ("Compare INDEX to INDEX,
    # never HEAD, and never the worktree") as well as this hook's own comment a few lines below:
    # "rejecting a correct commit because of unstaged work teaches --no-verify".
    #
    # `$stagedTmp[$Rs]` exists exactly when `$rsIn` is true, so the guard above still does its job -
    # the crash-on-missing-file reasoning in the comment above is unaffected.
    $genRs = ''; $genCs = ''
    if ($rsIn) { $genRs = New-TempPath '.gen.rs'; Copy-Item -LiteralPath $stagedTmp[$Rs] -Destination $genRs }
    if ($csIn) { $genCs = New-TempPath '.gen.cs'; Copy-Item -LiteralPath $stagedTmp[$Cs] -Destination $genCs }
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'generate-cheatsheet-literals.ps1') `
        -CoreSource $coreTmp -RustTarget $genRs -CsTarget $genCs *> $null
    if ($LASTEXITCODE -ne 0) { Fail "the generator exited $LASTEXITCODE - parity was NOT established (a generator that failed to run is not evidence of parity)."; exit 1 }
    $genFor = @{ $Rs = $genRs; $Cs = $genCs }

    # ---- 5. Compare generated bytes against the STAGED bytes, exactly.
    $mismatched = @()
    foreach ($t in $targets) {
        $a = [IO.File]::ReadAllBytes($genFor[$t.Path])
        $b = [IO.File]::ReadAllBytes($stagedTmp[$t.Path])
        if (-not [Linq.Enumerable]::SequenceEqual($a, $b)) { $mismatched += $t.Path }
    }

    # ---- 6. Agreement: PASS AND STOP, whatever the worktree looks like. This is the only thing the hook
    # is entitled to validate, and rejecting a correct commit because of unstaged work teaches --no-verify.
    if ($mismatched.Count -eq 0) { Write-Host "check-cheatsheet-parity: OK - the staged literals match the staged $Core." -ForegroundColor Green; exit 0 }

    # ---- 7. DIAGNOSIS ONLY FROM HERE, in the order 3, then 1, then 2. A partial stage also satisfies
    # case 1 or 2, so checking them in table order sends the user advice whose remedy fails again.
    & git -C $RepoRoot diff --quiet -- $Core          # worktree vs index, CRLF-agnostic. NEVER a byte compare.
    $coreDirty = ($LASTEXITCODE -ne 0)
    if ($coreDirty) {
        & git -C $RepoRoot diff --cached --quiet -- $Core
        $coreStaged = ($LASTEXITCODE -ne 0)
        if ($coreStaged) {
            Fail "partial staging of $Core is not supported. The literals are generated from the STAGED text and the just task reads the WORKTREE, so the two cannot agree. Stage $Core in full TOGETHER with the regenerated literals."
        } else {
            Fail "you staged the generated literals but not $Core itself. git add it."
        }
        exit 1
    }

    # Case 1 vs 2: is the generated output already sitting in the WORKTREE? This comparison is
    # temp-file-to-worktree, so no form of `git diff` can express it - normalise both sides and compare
    # the normalised TEXT, exactly as DriverCheatsheetTests.cs:92 already does.
    #
    # INTERACTION WITH THE INDEX-SOURCED SCAFFOLD, traced deliberately and ACCEPTED. `$genFor` is now
    # built from the INDEX blob (see step 4 - it used to come from the worktree, which made the
    # VALIDATION reject correct commits). That means when a developer has regenerated the literals AND
    # also has an unrelated unstaged edit in the same file, `$genFor` and the worktree differ, so this
    # lands on case 2 ("run just gen-cheatsheet-literals, then git add") rather than case 1 ("git add").
    # That is a REDUNDANT instruction, not a wrong one: case 2's remedy is a superset of case 1's and
    # still resolves the failure. The spec's bar is that a remedy must not be a TRAP (spec:953), and it
    # is not. Sourcing the scaffold from the worktree to sharpen this message would re-break the
    # validation obligations at :3699 (#2), :4207 (#5) and :4209 (#6). Do not trade a correct gate for
    # a tidier diagnosis.
    $worktreeMatches = $true
    foreach ($m in $mismatched) {
        $gen  = [IO.File]::ReadAllText($genFor[$m]).Replace("`r`n", "`n")
        $work = [IO.File]::ReadAllText((Join-Path $RepoRoot $m)).Replace("`r`n", "`n")
        if ($gen -ne $work) { $worktreeMatches = $false }
    }
    if ($worktreeMatches) {
        Fail ("regenerated output is already in your worktree - git add the literal(s): " + ($mismatched -join ', '))
    } else {
        Fail ("run 'just gen-cheatsheet-literals', then git add the literal(s): " + ($mismatched -join ', '))
    }
    exit 1
}
finally {
    # EVERY exit path, including the failure paths. A unique-per-invocation temp with no cleanup is
    # unbounded growth, and this hook runs on every commit that stages one of the three paths.
    foreach ($t in $temps) { Remove-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue }
}

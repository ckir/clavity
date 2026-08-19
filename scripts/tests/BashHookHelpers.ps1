# Shared Pester helpers for driving the shipped bash hooks with synthetic payloads.
# Dot-source from a *.Tests.ps1 BeforeAll: . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')

function Get-GitBashOrThrow {
    # Claude Code runs plugin hooks with Git Bash on Windows; pin it explicitly. `Get-Command bash` is
    # NON-DETERMINISTIC: locally it resolves to WSL's C:\WINDOWS\System32\bash.exe (own filesystem, cannot
    # run a Windows-path hook); CI (no WSL) resolves to Git Bash. Prefer the standard Git install, else the
    # first PATH bash that is NOT the System32 WSL shim.
    $candidates = @(
        'C:\Program Files\Git\bin\bash.exe',
        'C:\Program Files (x86)\Git\bin\bash.exe'
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
    $onPath = Get-Command bash -All -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notmatch '\\System32\\bash\.exe$' } |
        Select-Object -First 1 -ExpandProperty Source
    if ($onPath) { return $onPath }
    throw 'Git Bash not found on PATH; the SP-D hook tests require Git Bash (not WSL bash).'
}

function New-TempRepo {
    # A throwaway git repo so a hook's `git -C "$cwd" rev-parse HEAD` has a real HEAD without touching
    # the real repo. Returns the dir path (Windows form); callers forward-slash it for the payload cwd.
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    & git -C $dir init -q
    & git -C $dir -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= commit --allow-empty -qm init
    return $dir
}

function Invoke-BashHook {
    # Run a bash hook with a synthetic JSON payload on stdin. Captures stdout, stderr, and the exit code
    # separately (SP-D hooks emit user-visible notices on STDERR with exit 2). $Env overrides are applied
    # process-wide for the call then restored; use ABSOLUTE paths for HOME (MSYS mangles relative values).
    param(
        [Parameter(Mandatory)][string]$HookPath,
        [string]$Payload = '{}',
        [hashtable]$Env = @{},
        [string[]]$Arguments = @()
    )
    $bash = Get-GitBashOrThrow
    $hookPosix = ($HookPath -replace '\\','/')
    # ABSENCE AND EMPTINESS ARE DIFFERENT STATES, and restoring them is not the same operation.
    # Conflating them leaked for real: `[Environment]::SetEnvironmentVariable($k, $null)` does NOT
    # delete the key in PowerShell, it leaves it PRESENT WITH AN EMPTY VALUE. Measured, all four forms:
    #     SetEnvironmentVariable(n, $null)               -> present=True  value=[]
    #     SetEnvironmentVariable(n, '')                  -> present=True  value=[]
    #     SetEnvironmentVariable(n, [NullString]::Value) -> present=False
    #     Remove-Item Env:n                              -> present=False
    # So restoring a previously-ABSENT variable with the saved $null re-created it as empty, and every
    # later child process in the same Pester run inherited it. That is not cosmetic on this platform:
    # MSYS/Git Bash converts an EMPTY TMPDIR into the bogus relative path `<cwd>/=` instead of passing
    # it through empty, so `${TMPDIR:-/tmp}` never defaults. A suite at position 5 overriding TMPDIR
    # therefore poisoned every bash child that ran after it - which is why agy-shield-lib.Tests.ps1
    # passed 39/39 in ISOLATION and failed 5 rows in the full sweep and in CI.
    $saved = @{}
    $wasAbsent = @{}
    $errFile = [IO.Path]::GetTempFileName()
    try {
        # Inside the try on purpose: this used to run BEFORE it, so anything that threw between the
        # mutation and the try left the override installed permanently, with no finally to undo it.
        foreach ($k in $Env.Keys) {
            # CASE-INSENSITIVE, because the setter is. `GetEnvironmentVariables().Contains($k)` is a
            # plain Hashtable lookup and is case-SENSITIVE, so it reports a PRESENT variable as absent
            # whenever the caller's casing differs from the block's actual key - and this restore would
            # then DELETE it. MEASURED on a block whose real key is `PATH`:
            #     Contains('PATH') = True      GetEnvironmentVariable('PATH') = <value>
            #     Contains('Path') = False     GetEnvironmentVariable('Path') = <value>   <-- disagree
            # Shipped that way once: locally the casings happened to align so a 989/0 sweep passed, and
            # CI - where they did not - deleted PATH and every hook lost `jq`.
            # GetEnvironmentVariable returns $null ONLY for a genuinely absent variable; a present-but-
            # empty one returns '', which is exactly the distinction this restore turns on.
            $wasAbsent[$k] = ($null -eq [Environment]::GetEnvironmentVariable($k))
            $saved[$k] = [Environment]::GetEnvironmentVariable($k)
            [Environment]::SetEnvironmentVariable($k, $Env[$k])
        }
        $out = ($Payload | & $bash $hookPosix @Arguments 2>$errFile | Out-String)
        $code = $LASTEXITCODE
        $err = (Get-Content -Raw -LiteralPath $errFile -ErrorAction SilentlyContinue)
        if ($null -eq $err) { $err = '' }
        [pscustomobject]@{ StdOut = $out.Trim(); StdErr = $err.Trim(); ExitCode = $code }
    } finally {
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
        foreach ($k in $saved.Keys) {
            if ($wasAbsent[$k]) {
                # [NullString]::Value is the only form that DELETES - see the note above.
                [Environment]::SetEnvironmentVariable($k, [NullString]::Value)
            }
            else {
                [Environment]::SetEnvironmentVariable($k, $saved[$k])
            }
        }
    }
}

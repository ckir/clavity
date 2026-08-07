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
    $saved = @{}
    foreach ($k in $Env.Keys) {
        $saved[$k] = [Environment]::GetEnvironmentVariable($k)
        [Environment]::SetEnvironmentVariable($k, $Env[$k])
    }
    $errFile = [IO.Path]::GetTempFileName()
    try {
        $out = ($Payload | & $bash $hookPosix @Arguments 2>$errFile | Out-String)
        $code = $LASTEXITCODE
        $err = (Get-Content -Raw -LiteralPath $errFile -ErrorAction SilentlyContinue)
        if ($null -eq $err) { $err = '' }
        [pscustomobject]@{ StdOut = $out.Trim(); StdErr = $err.Trim(); ExitCode = $code }
    } finally {
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
}

<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

# clavity-ls-launcher-lib.sh keeps a `clavity-ls` launcher on PATH: a ~/.local/bin symlink on Linux/macOS, the data dir
# appended to the user PATH (HKCU, through powershell.exe) on Windows under git-bash. Every row runs the lib STANDALONE.
#
# ISOLATION, the reason this suite can run on a developer's machine at all: every row sets HOME to the fixture (so
# ~/.local/bin is the fixture's) and sets PATH explicitly INSIDE bash, never inheriting it. The Windows-branch rows put a
# fake powershell.exe first and otherwise only /usr/bin:/bin, which hold no powershell.exe on Linux or under Git Bash
# (Windows keeps it in System32), so no row can reach the real user PATH. OSTYPE is pinned per row: bash honours it from
# the environment (measured), and Git Bash would otherwise report msys.
#
# OS split. A row that creates or inspects a symlink is LinuxOnly: Git for Windows' `ln -s` makes a COPY unless
# MSYS=winsymlinks:native* is set, so [ -L ] can never be true there, and the lib's Windows branch never touches a
# symlink. The `windows:` rows pin OSTYPE=msys and run on EVERY OS through the shim cygpath and fake powershell.exe,
# the way fetch-clavity-ls.Tests.ps1 runs its msys rows on Linux.
BeforeAll {
    . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
    $script:Lib = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'clavity-dotnet/plugin/hooks/clavity-ls-launcher-lib.sh'
    $script:Bash = Get-GitBashOrThrow

    function New-Fx {
        $root = New-TestTempPath 'cll'
        $fx = [pscustomobject]@{
            Root = $root; Home = (Join-Path $root 'home'); Bin = (Join-Path $root 'data/bin'); OtherBin = (Join-Path $root 'other/bin')
            Shim = (Join-Path $root 'shim'); ShimNoPs = (Join-Path $root 'shim-nops'); PsLog = (Join-Path $root 'ps.log')
        }
        New-Item -ItemType Directory -Path $fx.Home, $fx.Bin, $fx.OtherBin, $fx.Shim, $fx.ShimNoPs | Out-Null
        [IO.File]::WriteAllText((Join-Path $fx.Bin 'clavity-ls.exe'), 'BIN')
        [IO.File]::WriteAllText((Join-Path $fx.OtherBin 'clavity-ls.exe'), 'OTHER')
        # Fake cygpath: only -w, the one form the lib uses. /x/rest -> X:\rest, everything else gets backslashes.
        $cygpath = @'
#!/usr/bin/env bash
[ "$1" = -w ] || exit 2
x=$2
case "$x" in /[a-zA-Z]/*) d=${x:1:1}; x="${d^^}:${x:2}";; esac
printf '%s\n' "${x//\//\\}"
'@
        # Fake powershell.exe: every call appends to FAKE_PS_LOG (the -Command text on its own line), so an absent log
        # proves no call was made. Without FAKE_PS_LOG it fails loudly rather than pretending.
        $ps = @'
#!/usr/bin/env bash
[ -n "${FAKE_PS_LOG:-}" ] || { echo "fake powershell.exe: FAKE_PS_LOG unset" >&2; exit 97; }
while [ $# -gt 0 ]; do
  case "$1" in -Command) printf 'COMMAND %s\n' "$2" >> "$FAKE_PS_LOG"; shift 2;; *) printf 'ARG %s\n' "$1" >> "$FAKE_PS_LOG"; shift;; esac
done
exit "${FAKE_PS_EXIT:-0}"
'@
        foreach ($d in $fx.Shim, $fx.ShimNoPs) { [IO.File]::WriteAllText((Join-Path $d 'cygpath'), $cygpath) }
        [IO.File]::WriteAllText((Join-Path $fx.Shim 'powershell.exe'), $ps)
        Set-ShimExecutable -Path (Join-Path $fx.Shim 'cygpath'), (Join-Path $fx.ShimNoPs 'cygpath'), (Join-Path $fx.Shim 'powershell.exe')
        return $fx
    }
    function Invoke-Lib($Fx, [Parameter(Mandatory)][string]$OsType, [Parameter(Mandatory)][string]$PathValue,
                        [string]$Target = '$p/data/bin/clavity-ls.exe', [string]$BinDir = '$p/data/bin', [string]$Ver = '9.9.9',
                        [string[]]$Extra = @()) {
        # $PathValue, $Target and $BinDir are bash DOUBLE-QUOTED bodies evaluated inside bash, where $p is the fixture
        # root in POSIX form (Get-BashCygpathPrelude). A Windows-form literal is written with its backslashes as-is: inside
        # bash double quotes a backslash before a letter stays a backslash. $Extra is NAME=value words exported verbatim.
        # The shim dir is prepended INSIDE bash, never via the Windows PATH (Git's bin/bash.exe launcher reorders that).
        $cmd = (Get-BashCygpathPrelude) + '; lib="$2"; shift 2; export HOME="$p/home" OSTYPE="' + $OsType + '" FAKE_PS_LOG="$p/ps.log"; ' +
            'unset CLAVITY_SKIP_PATH; [ $# -gt 0 ] && export "$@"; ' +
            'PATH="' + $PathValue + '" "$BASH" "$lib" "' + $Target + '" "' + $BinDir + '" "' + $Ver + '" </dev/null'
        $errFile = New-TestTempPath 'cll-err'
        try {
            $out = & $script:Bash -c $cmd _ $Fx.Root ($script:Lib -replace '\\', '/') @Extra 2>$errFile | Out-String
            $code = $LASTEXITCODE
            $err = if (Test-Path -LiteralPath $errFile) { "$(Get-Content -Raw -LiteralPath $errFile)".Trim() } else { '' }
            return [pscustomobject]@{ StdOut = $out.Trim(); StdErr = $err; ExitCode = $code }
        } finally { Remove-Item -LiteralPath $errFile -ErrorAction SilentlyContinue }
    }
    function Test-Bash([string]$Test, [string[]]$Paths) {
        # A bash [ ] test over fixture paths ($1, $2, ...), so -L / -ef mean exactly what they mean to the lib.
        & $script:Bash -c "if $Test; then echo YES; else echo NO; fi" _ @($Paths | ForEach-Object { $_ -replace '\\', '/' })
    }
    # The PATH tail every non-steady row gets: mkdir/ln (Unix branch) and the shims' env/bash. No powershell.exe here.
    $script:Sys = '/usr/bin:/bin'
}

Describe 'clavity-ls-launcher-lib' {
    It 'creates the ~/.local/bin symlink to TARGET and returns 0 when ~/.local/bin is on PATH' -Tag 'LinuxOnly' -Skip:($IsWindows) {
        $fx = New-Fx
        try {
            $res = Invoke-Lib $fx -OsType 'linux-gnu' -PathValue ('$p/home/.local/bin:' + $script:Sys)
            $res.ExitCode | Should -Be 0 -Because $res.StdErr
            $res.StdErr | Should -BeNullOrEmpty
            $link = Join-Path $fx.Home '.local/bin/clavity-ls'
            Test-Bash '[ -L "$1" ] && [ "$1" -ef "$2" ]' $link, (Join-Path $fx.Bin 'clavity-ls.exe') | Should -Be 'YES'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'returns 3 and says NOT on PATH once per version when ~/.local/bin is not on PATH' -Tag 'LinuxOnly' -Skip:($IsWindows) {
        $fx = New-Fx
        try {
            $res = Invoke-Lib $fx -OsType 'linux-gnu' -PathValue $script:Sys
            $res.ExitCode | Should -Be 3
            $res.StdErr | Should -Match 'NOT on PATH'
            $res.StdErr | Should -Match ([regex]::Escape('.local/bin'))
            Test-Path -LiteralPath (Join-Path $fx.Bin '.path-note.9.9.9') | Should -BeTrue
            Test-Bash '[ -L "$1" ] && [ "$1" -ef "$2" ]' (Join-Path $fx.Home '.local/bin/clavity-ls'), (Join-Path $fx.Bin 'clavity-ls.exe') | Should -Be 'YES'

            $again = Invoke-Lib $fx -OsType 'linux-gnu' -PathValue $script:Sys
            $again.ExitCode | Should -Be 3
            $again.StdErr | Should -BeNullOrEmpty -Because 'the note is emitted once per version'

            # A new version speaks once more.
            $next = Invoke-Lib $fx -OsType 'linux-gnu' -PathValue $script:Sys -Ver '9.9.10'
            $next.ExitCode | Should -Be 3
            $next.StdErr | Should -Match 'NOT on PATH'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'repairs a dangling symlink' -Tag 'LinuxOnly' -Skip:($IsWindows) {
        $fx = New-Fx
        try {
            $link = Join-Path $fx.Home '.local/bin/clavity-ls'
            & $script:Bash -c 'mkdir -p "${1%/*}" && ln -s "$2" "$1"' _ $link (Join-Path $fx.Root 'gone/clavity-ls.exe')
            Test-Bash '[ -L "$1" ] && [ ! -e "$1" ]' $link | Should -Be 'YES' -Because 'the fixture must start dangling'
            $res = Invoke-Lib $fx -OsType 'linux-gnu' -PathValue ('$p/home/.local/bin:' + $script:Sys)
            $res.ExitCode | Should -Be 0 -Because $res.StdErr
            Test-Bash '[ -L "$1" ] && [ "$1" -ef "$2" ]' $link, (Join-Path $fx.Bin 'clavity-ls.exe') | Should -Be 'YES'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'repairs a symlink into another data dir' -Tag 'LinuxOnly' -Skip:($IsWindows) {
        $fx = New-Fx
        try {
            $link = Join-Path $fx.Home '.local/bin/clavity-ls'
            & $script:Bash -c 'mkdir -p "${1%/*}" && ln -s "$2" "$1"' _ $link (Join-Path $fx.OtherBin 'clavity-ls.exe')
            Test-Bash '[ "$1" -ef "$2" ]' $link, (Join-Path $fx.OtherBin 'clavity-ls.exe') | Should -Be 'YES' -Because 'the fixture must start pointing elsewhere'
            $res = Invoke-Lib $fx -OsType 'linux-gnu' -PathValue ('$p/home/.local/bin:' + $script:Sys)
            $res.ExitCode | Should -Be 0 -Because $res.StdErr
            Test-Bash '[ -L "$1" ] && [ "$1" -ef "$2" ]' $link, (Join-Path $fx.Bin 'clavity-ls.exe') | Should -Be 'YES'
            Get-Content -Raw -LiteralPath (Join-Path $fx.OtherBin 'clavity-ls.exe') | Should -BeExactly 'OTHER' -Because 'the other data dir is never written'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'leaves a regular file alone and names it' {
        $fx = New-Fx
        try {
            $link = Join-Path $fx.Home '.local/bin/clavity-ls'
            New-Item -ItemType Directory -Path (Split-Path -Parent $link) | Out-Null
            [IO.File]::WriteAllText($link, 'MINE')
            $res = Invoke-Lib $fx -OsType 'linux-gnu' -PathValue ('$p/home/.local/bin:' + $script:Sys)
            $res.ExitCode | Should -Be 2
            $res.StdErr | Should -Match ([regex]::Escape('.local/bin/clavity-ls'))
            Test-Bash '[ -f "$1" ] && [ ! -L "$1" ]' $link | Should -Be 'YES'
            Get-Content -Raw -LiteralPath $link | Should -BeExactly 'MINE'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'skips with CLAVITY_SKIP_PATH=1 and says so' {
        $fx = New-Fx
        try {
            $res = Invoke-Lib $fx -OsType 'linux-gnu' -PathValue ('$p/home/.local/bin:' + $script:Sys) -Extra 'CLAVITY_SKIP_PATH=1'
            $res.ExitCode | Should -Be 0
            $res.StdErr | Should -Match 'skipped'
            Test-Path -LiteralPath (Join-Path $fx.Home '.local/bin/clavity-ls') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $fx.Home '.local') | Should -BeFalse
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'skips when .no-launcher exists and names the marker' {
        $fx = New-Fx
        try {
            [IO.File]::WriteAllText((Join-Path $fx.Bin '.no-launcher'), '')
            $res = Invoke-Lib $fx -OsType 'linux-gnu' -PathValue ('$p/home/.local/bin:' + $script:Sys)
            $res.ExitCode | Should -Be 0
            $res.StdErr | Should -Match ([regex]::Escape('.no-launcher'))
            Test-Path -LiteralPath (Join-Path $fx.Home '.local/bin/clavity-ls') | Should -BeFalse
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'windows: spawns nothing when the data dir is already in PATH in either form' {
        $fx = New-Fx
        try {
            # The data dir as C:\... and as /c/... (and a mixed-case, trailing-slash spelling); PATH carries it in yet
            # another casing. Every form must be recognised without a call.
            foreach ($bin in 'C:\Users\u\d\bin', '/c/Users/u/d/bin', 'c:/USERS/u/d/bin/') {
                $res = Invoke-Lib $fx -OsType 'msys' -PathValue ('$p/shim:' + $script:Sys + ':/c/users/u/d/bin') -BinDir $bin -Target "$bin/clavity-ls.exe"
                $res.ExitCode | Should -Be 0 -Because "BIN_DIR=$bin $($res.StdErr)"
                $res.StdErr | Should -BeNullOrEmpty -Because "BIN_DIR=$bin"
                Test-Path -LiteralPath $fx.PsLog | Should -BeFalse -Because "BIN_DIR=$bin must not reach powershell.exe"
            }
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'windows: appends via powershell when absent, never setx' {
        $fx = New-Fx
        try {
            foreach ($bin in 'C:\Users\u\d\bin', '/c/Users/u/d/bin') {
                Remove-Item -LiteralPath $fx.PsLog -ErrorAction SilentlyContinue
                $res = Invoke-Lib $fx -OsType 'msys' -PathValue ('$p/shim:' + $script:Sys + ':/c/users/u/other') -BinDir $bin -Target "$bin/clavity-ls.exe"
                $res.ExitCode | Should -Be 0 -Because "BIN_DIR=$bin $($res.StdErr)"
                Test-Path -LiteralPath $fx.PsLog | Should -BeTrue -Because "BIN_DIR=$bin must reach powershell.exe"
                $log = Get-Content -Raw -LiteralPath $fx.PsLog
                @($log -split "`n" | Where-Object { $_ -like 'COMMAND *' }).Count | Should -Be 1 -Because 'one powershell call'
                $log | Should -Match ([regex]::Escape("GetEnvironmentVariable('Path','User')"))
                $log | Should -Match 'SetEnvironmentVariable'
                $log | Should -Match ([regex]::Escape('C:\Users\u\d\bin')) -Because 'the Windows form of the data dir is what reaches the user PATH'
                $log | Should -Match '(?m)^ARG -NoProfile$'
                $log | Should -Match '(?m)^ARG -NonInteractive$'
                $log | Should -Not -Match '(?i)setx'
                $res.StdErr | Should -Match 'new terminal'
            }
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'windows: a missing powershell.exe is a message and exit 2' {
        $fx = New-Fx
        try {
            $res = Invoke-Lib $fx -OsType 'msys' -PathValue ('$p/shim-nops:' + $script:Sys) -BinDir 'C:\Users\u\d\bin' -Target 'C:\Users\u\d\bin\clavity-ls.exe'
            $res.ExitCode | Should -Be 2
            $res.StdErr | Should -Match ([regex]::Escape('powershell.exe'))
            $res.StdErr | Should -Not -Match 'command not found'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'unix steady state runs on builtins alone: exit 0 and silence with PATH holding only the link dir' -Tag 'LinuxOnly' -Skip:($IsWindows) {
        $fx = New-Fx
        try {
            $link = Join-Path $fx.Home '.local/bin/clavity-ls'
            & $script:Bash -c 'mkdir -p "${1%/*}" && ln -s "$2" "$1"' _ $link (Join-Path $fx.Bin 'clavity-ls.exe')
            # PATH is the link dir ONLY: no mkdir, ln, readlink or any other tool resolves, so any external command the
            # steady state took would print `command not found` on stderr.
            $res = Invoke-Lib $fx -OsType 'linux-gnu' -PathValue '$p/home/.local/bin'
            $res.ExitCode | Should -Be 0
            $res.StdErr | Should -BeNullOrEmpty
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'windows steady state runs on builtins alone: exit 0 and silence with PATH holding only BIN_DIR' {
        $fx = New-Fx
        try {
            # PATH is the data dir ONLY, in the /c/... form; no shim dir, so a wrongly-taken cygpath or powershell.exe call
            # prints `command not found`. BIN_DIR arrives in the C:\... form, so the normalisation itself is exercised.
            $res = Invoke-Lib $fx -OsType 'msys' -PathValue '/c/Users/u/d/bin' -BinDir 'C:\Users\u\d\bin' -Target 'C:\Users\u\d\bin\clavity-ls.exe'
            $res.ExitCode | Should -Be 0
            $res.StdErr | Should -BeNullOrEmpty
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'windows steady state spawns zero processes' -Tag 'WindowsOnly' -Skip:(-not $IsWindows) {
        # Measure-BashHookProcesses is a kernel32 job-object counter (Windows only, as hook-spawn-budget.Tests.ps1 skips
        # its rows). This is the branch Windows runs in production, so it is the one the counter pins.
        $fx = New-Fx
        try {
            $wrapper = Join-Path $fx.Root 'wrapper.sh'
            [IO.File]::WriteAllText($wrapper, ". `"`$1`" && clavity_ls_launcher_ensure `"`$2`" `"`$3`" 9.9.9`n")
            $binWin = $fx.Bin -replace '/', '\'
            # PATH is the fake-powershell shim and the data dir, NOT the inherited Windows PATH: a regression that missed
            # the match must land on the fake (and be counted), never on System32's powershell.exe and the real user PATH.
            # The counter itself prepends /ucrt64/bin:/mingw64/bin:/usr/bin, none of which holds a powershell.exe.
            $r = Measure-BashHookProcesses -HookPath $wrapper -Arguments @(($script:Lib -replace '\\', '/'), "$binWin\clavity-ls.exe", $binWin) `
                -Env @{ OSTYPE = 'msys'; HOME = $fx.Home; PATH = "$($fx.Shim);$binWin"; FAKE_PS_LOG = $fx.PsLog; CLAVITY_SKIP_PATH = $null }
            $r.ExitCode | Should -Be 0 -Because $r.StdErr
            $r.StdErr | Should -BeNullOrEmpty
            $r.Spawned | Should -Be 0
            Test-Path -LiteralPath $fx.PsLog | Should -BeFalse
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

# install.sh (repository root): the agent-runnable install. It runs the `claude plugin` commands, runs the plugin's
# SessionStart fetch hook by hand, registers the plugin with agy when agy is on PATH, runs the launcher library
# standalone, verifies in two tiers and prints the launch line last, exiting 0/1/2/3 (spec section 2).
#
# ISOLATION: every row sets HOME and CLAUDE_CONFIG_DIR into the fixture and sets PATH explicitly INSIDE bash, never
# inheriting it. The shim dir holds fake claude, curl, cygpath and powershell.exe, each logging to a fixture file; agy
# lives in its own shim dir, put on PATH only by the rows that want it. /usr/bin:/bin hold no claude, agy or
# powershell.exe on Linux or under Git Bash, so no row can reach a real one. OSTYPE is pinned per row (bash honours it
# from the environment); the Windows rows pin `msys` and run on every OS through the fakes.
#
# The plugin under test is a fixture dir holding plugin.json ("version": "9.9.9") and a STUB hooks/fetch-clavity-ls.sh:
# it logs what it saw (CLAUDE_PLUGIN_ROOT, CLAUDE_PLUGIN_DATA, whether the fail stamp existed), prints one JSON object
# to stdout (install.sh must discard it) and one line to stderr (install.sh must let it through), and writes an
# executable clavity-ls.exe whose --version exits FAKE_BIN_EXIT (default 0). FAKE_HOOK_FAIL=1 makes it place nothing.
# The launcher lib is the REAL one, handed over through CLAVITY_INSTALL_LIB (one row fetches it through the fake curl).
#
# OS split: a row whose oracle needs a real ~/.local/bin symlink is LinuxOnly, as in clavity-ls-launcher-lib.Tests.ps1
# (Git for Windows' ln -s makes a copy).
BeforeAll {
    . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Install = Join-Path $script:RepoRoot 'install.sh'
    $script:Lib = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/clavity-ls-launcher-lib.sh'
    $script:Bash = Get-GitBashOrThrow
    $script:LaunchPrefix = 'If Claude Code or agy is already running in this folder, exit them first. Then open a new terminal and run: '
    $script:LaunchLine = $script:LaunchPrefix + 'clavity-ls start <folder>'
    $script:NotInstalledLine = '[clavity install] clavity is NOT installed: fix the FAILED line above, then run this again'
    $script:RawBase = 'http://raw.test/ckir/clavity/main'
    $script:LibRel = 'clavity-dotnet/plugin/hooks/clavity-ls-launcher-lib.sh'

    function New-Plugin([string]$Id, [string]$Path, [bool]$Enabled = $true, [string]$Version = '9.9.9') {
        [ordered]@{ id = $Id; version = $Version; scope = 'user'; enabled = $Enabled; installPath = $Path
                    installedAt = '2026-11-10T08:00:00.000Z'; lastUpdated = '2026-11-10T08:00:00.000Z'; projectEnabled = $false }
    }
    function ConvertTo-Listing([object[]]$Objs) {
        # Pretty-printed, as the real `claude plugin list --json` prints it.
        if ($Objs.Count -eq 0) { return '[]' }
        ConvertTo-Json -InputObject @($Objs) -Depth 8
    }
    function ConvertTo-Markets([string[]]$Repos) {
        if ($Repos.Count -eq 0) { return '[]' }
        ConvertTo-Json -InputObject @($Repos | ForEach-Object { [ordered]@{ name = ($_ -split '/')[1]; source = 'github'; repo = $_ } }) -Depth 4
    }

    function New-Fx {
        $root = New-TestTempPath 'install-sh'
        $fx = [pscustomobject]@{
            Root = $root; Home = (Join-Path $root 'home'); Cfg = (Join-Path $root 'cfg'); Plugin = (Join-Path $root 'plugin')
            Shim = (Join-Path $root 'shim'); AgyShim = (Join-Path $root 'agyshim'); Work = (Join-Path $root 'work')
            Served = (Join-Path $root 'served'); Tmp = (Join-Path $root 'tmp')
            ClaudeLog = (Join-Path $root 'claude.log'); AgyLog = (Join-Path $root 'agy.log'); PsLog = (Join-Path $root 'ps.log')
            CurlLog = (Join-Path $root 'curl.log'); HookLog = (Join-Path $root 'hook.log')
        }
        $fx | Add-Member -NotePropertyName Data -NotePropertyValue (Join-Path $fx.Cfg 'plugins/data/clavity-clavity')
        $fx | Add-Member -NotePropertyName PluginFwd -NotePropertyValue ($fx.Plugin -replace '\\', '/')
        New-Item -ItemType Directory -Path $fx.Home, $fx.Cfg, (Join-Path $fx.Plugin 'hooks'), $fx.Shim, $fx.AgyShim, $fx.Work, $fx.Served, $fx.Tmp | Out-Null
        [IO.File]::WriteAllText((Join-Path $fx.Plugin 'plugin.json'), "{`n  `"name`": `"clavity`",`n  `"version`": `"9.9.9`"`n}`n")
        $hook = @'
#!/usr/bin/env bash
# STUB fetch-clavity-ls.sh (install-sh.Tests.ps1)
fs=absent; [ -e "$CLAUDE_PLUGIN_DATA/bin/.clavity-ls.version.fail" ] && fs=present
printf 'ROOT=%s\nDATA=%s\nFAILSTAMP=%s\n' "${CLAUDE_PLUGIN_ROOT:-}" "${CLAUDE_PLUGIN_DATA:-}" "$fs" >> "$FAKE_HOOK_LOG"
printf '%s\n' '{"systemMessage":"STUB-HOOK-JSON"}'
if [ -n "${FAKE_HOOK_FAIL:-}" ]; then
  echo "[clavity-ls] STUB release lookup failed (offline?) - install clavity-ls manually" >&2
  exit 0
fi
mkdir -p "$CLAUDE_PLUGIN_DATA/bin"
printf '#!/usr/bin/env bash\necho "clavity-ls 9.9.9"\nexit %s\n' "${FAKE_BIN_EXIT:-0}" > "$CLAUDE_PLUGIN_DATA/bin/clavity-ls.exe"
chmod +x "$CLAUDE_PLUGIN_DATA/bin/clavity-ls.exe"
echo "[clavity-ls] STUB installed clavity-ls 9.9.9" >&2
exit 0
'@
        [IO.File]::WriteAllText((Join-Path $fx.Plugin 'hooks/fetch-clavity-ls.sh'), $hook)
        # Fake claude: argv to FAKE_CLAUDE_LOG (one line per call, so an absent log proves no call). It serves FAKE_MARKETS for
        # `plugin marketplace list --json` and FAKE_PLUGINS for `plugin list --json`, switching to FAKE_PLUGINS_AFTER (when
        # set) once a `plugin install` has been logged.
        $claude = @'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_CLAUDE_LOG"
case "$*" in
  'plugin marketplace list --json') printf '%s\n' "${FAKE_MARKETS:-[]}" ;;
  'plugin list --json')
    if [ -n "${FAKE_PLUGINS_AFTER+x}" ] && grep -q '^plugin install ' "$FAKE_CLAUDE_LOG"; then printf '%s\n' "$FAKE_PLUGINS_AFTER"
    else printf '%s\n' "${FAKE_PLUGINS:-[]}"; fi ;;
esac
exit "${FAKE_CLAUDE_EXIT:-0}"
'@
        $agy = @'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_AGY_LOG"
exit "${FAKE_AGY_EXIT:-0}"
'@
        # Fake curl: records the URL; serves FAKE_SERVED/<rel> for FAKE_CURL_BASE/<rel>, else exits 22 (curl -f's code).
        $curl = @'
#!/usr/bin/env bash
url=; out=
while [ $# -gt 0 ]; do
  case "$1" in -o) out=$2; shift 2 ;; -*) shift ;; *) url=$1; shift ;; esac
done
printf '%s\n' "$url" >> "$FAKE_CURL_LOG"
rel=${url#"$FAKE_CURL_BASE"/}
{ [ "$rel" != "$url" ] && [ -f "$FAKE_SERVED/$rel" ]; } || exit 22
if [ -n "$out" ]; then cp "$FAKE_SERVED/$rel" "$out"; else cat "$FAKE_SERVED/$rel"; fi
'@
        $cygpath = @'
#!/usr/bin/env bash
[ "$1" = -w ] || exit 2
x=$2
case "$x" in /[a-zA-Z]/*) d=${x:1:1}; x="${d^^}:${x:2}";; esac
printf '%s\n' "${x//\//\\}"
'@
        # Fake powershell.exe: logs every call. A SetEnvironmentVariable script (the lib's append) answers FAKE_PS_OUT
        # (default `added`); any other script (install.sh's read-back of the USER PATH) answers FAKE_USER_PATH. CRLF, as
        # real PowerShell ends its output.
        $ps = @'
#!/usr/bin/env bash
[ -n "${FAKE_PS_LOG:-}" ] || { echo "fake powershell.exe: FAKE_PS_LOG unset" >&2; exit 97; }
cmd=
while [ $# -gt 0 ]; do
  case "$1" in -Command) cmd=$2; printf 'COMMAND %s\n' "$2" >> "$FAKE_PS_LOG"; shift 2;; *) printf 'ARG %s\n' "$1" >> "$FAKE_PS_LOG"; shift;; esac
done
case "$cmd" in
  *SetEnvironmentVariable*) printf '%s\r\n' "${FAKE_PS_OUT:-added}" ;;
  *) printf '%s\r\n' "${FAKE_USER_PATH:-}" ;;
esac
exit 0
'@
        [IO.File]::WriteAllText((Join-Path $fx.Shim 'claude'), $claude)
        [IO.File]::WriteAllText((Join-Path $fx.Shim 'curl'), $curl)
        [IO.File]::WriteAllText((Join-Path $fx.Shim 'cygpath'), $cygpath)
        [IO.File]::WriteAllText((Join-Path $fx.Shim 'powershell.exe'), $ps)
        [IO.File]::WriteAllText((Join-Path $fx.AgyShim 'agy'), $agy)
        Set-ShimExecutable -Path (Join-Path $fx.Shim 'claude'), (Join-Path $fx.Shim 'curl'), (Join-Path $fx.Shim 'cygpath'),
            (Join-Path $fx.Shim 'powershell.exe'), (Join-Path $fx.AgyShim 'agy'), (Join-Path $fx.Plugin 'hooks/fetch-clavity-ls.sh')
        $fx | Add-Member -NotePropertyName DefaultPlugins -NotePropertyValue (ConvertTo-Listing @(
            (New-Plugin 'superpowers@superpowers-marketplace' (($fx.Root -replace '\\', '/') + '/other/sp')),
            (New-Plugin 'clavity@clavity' $fx.PluginFwd)))
        return $fx
    }

    # Runs install.sh. $Env overrides the defaults below (a value of '' exports the variable EMPTY, which install.sh treats as
    # unset). $PathValue and $Cwd are bash double-quoted bodies where $p is the fixture root in POSIX form. $InstallArgs is
    # spliced into the command line as-is (flags only).
    function Invoke-Install($Fx, [string]$InstallArgs = '', [hashtable]$Env = @{}, [string]$OsType = 'linux-gnu',
                            [string]$PathValue = '$p/shim:$p/home/.local/bin:/usr/bin:/bin', [string]$Cwd = '$p/work', [switch]$Truncate) {
        $vars = [ordered]@{
            FAKE_MARKETS = (ConvertTo-Markets 'ckir/clavity', 'obra/superpowers-marketplace')
            FAKE_PLUGINS = $Fx.DefaultPlugins
            FAKE_CURL_BASE = $script:RawBase
        }
        foreach ($k in $Env.Keys) { $vars[$k] = $Env[$k] }
        $extra = @($vars.Keys | ForEach-Object { "$_=$($vars[$_])" })
        $run = if ($Truncate) {
            'head -c "$(( $(wc -c < "$inst") / 2 ))" "$inst" | "$BASH" -s --'
        } else { '"$BASH" "$inst" ' + $InstallArgs + ' </dev/null' }
        $cmd = (Get-BashCygpathPrelude) + '; inst="$2"; lib="$3"; shift 3; ' +
            'unset CLAVITY_SKIP_PATH CLAVITY_SKIP_AGY CLAVITY_INSTALL_RAW_BASE CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA FAKE_PLUGINS_AFTER; ' +
            'export HOME="$p/home" CLAUDE_CONFIG_DIR="$p/cfg" TMPDIR="$p/tmp" OSTYPE="' + $OsType + '" CLAVITY_INSTALL_LIB="$lib" ' +
            'FAKE_CLAUDE_LOG="$p/claude.log" FAKE_AGY_LOG="$p/agy.log" FAKE_PS_LOG="$p/ps.log" FAKE_CURL_LOG="$p/curl.log" ' +
            'FAKE_HOOK_LOG="$p/hook.log" FAKE_SERVED="$p/served"; ' +
            'export "$@"; cd "' + $Cwd + '" || exit 99; export PATH="' + $PathValue + '"; ' + $run
        $errFile = New-TestTempPath 'install-sh-err'
        try {
            $out = & $script:Bash -c $cmd _ $Fx.Root ($script:Install -replace '\\', '/') ($script:Lib -replace '\\', '/') @extra 2>$errFile
            $code = $LASTEXITCODE
            $lines = @($out | ForEach-Object { "$_" })
            $err = if (Test-Path -LiteralPath $errFile) { "$(Get-Content -Raw -LiteralPath $errFile)".Trim() } else { '' }
            return [pscustomobject]@{ Lines = $lines; StdOut = ($lines -join "`n"); StdErr = $err; ExitCode = $code
                                      Last = $(if ($lines.Count) { $lines[-1] } else { '' }) }
        } finally { Remove-Item -LiteralPath $errFile -ErrorAction SilentlyContinue }
    }
    function Get-Log([string]$Path) { if (Test-Path -LiteralPath $Path) { @(Get-Content -LiteralPath $Path) } else { @() } }
    function Test-Bash([string]$Test, [string[]]$Paths) {
        & $script:Bash -c "if $Test; then echo YES; else echo NO; fi" _ @($Paths | ForEach-Object { $_ -replace '\\', '/' })
    }
    $script:Skip = @{ CLAVITY_SKIP_PATH = '1'; CLAVITY_SKIP_AGY = '1' }
}

Describe 'install.sh' {
    It 'adds the clavity marketplace only when no entry has repo ckir/clavity' {
        $fx = New-Fx
        try {
            $res = Invoke-Install $fx -Env ($script:Skip + @{ FAKE_MARKETS = (ConvertTo-Markets 'obra/superpowers-marketplace') })
            Get-Log $fx.ClaudeLog | Should -Contain 'plugin marketplace add ckir/clavity' -Because $res.StdOut
            Get-Log $fx.ClaudeLog | Should -Not -Contain 'plugin marketplace add obra/superpowers-marketplace'

            Remove-Item -LiteralPath $fx.ClaudeLog
            # Present under another NAME: the repo is what counts.
            $m = ConvertTo-Json -InputObject @([ordered]@{ name = 'mine'; source = 'github'; repo = 'ckir/clavity' },
                                               [ordered]@{ name = 'superpowers-marketplace'; source = 'github'; repo = 'obra/superpowers-marketplace' }) -Depth 4
            $res = Invoke-Install $fx -Env ($script:Skip + @{ FAKE_MARKETS = $m })
            @(Get-Log $fx.ClaudeLog | Where-Object { $_ -like 'plugin marketplace add*' }).Count | Should -Be 0 -Because $res.StdOut
        } finally { Remove-TestPath $fx.Root }
    }

    It 'adds the superpowers marketplace only when absent AND no superpowers@* plugin is enabled' {
        $fx = New-Fx
        try {
            $official = ($fx.Root -replace '\\', '/') + '/other/off'
            # Absent, and the official superpowers is enabled: no add.
            $plugins = ConvertTo-Listing @((New-Plugin 'superpowers@claude-plugins-official' $official), (New-Plugin 'clavity@clavity' $fx.PluginFwd))
            $res = Invoke-Install $fx -Env ($script:Skip + @{ FAKE_MARKETS = (ConvertTo-Markets 'ckir/clavity'); FAKE_PLUGINS = $plugins })
            Get-Log $fx.ClaudeLog | Should -Not -Contain 'plugin marketplace add obra/superpowers-marketplace' -Because $res.StdOut

            # Absent, and that superpowers is installed but DISABLED: add.
            Remove-Item -LiteralPath $fx.ClaudeLog
            $plugins = ConvertTo-Listing @((New-Plugin 'superpowers@claude-plugins-official' $official $false), (New-Plugin 'clavity@clavity' $fx.PluginFwd))
            $res = Invoke-Install $fx -Env ($script:Skip + @{ FAKE_MARKETS = (ConvertTo-Markets 'ckir/clavity'); FAKE_PLUGINS = $plugins })
            Get-Log $fx.ClaudeLog | Should -Contain 'plugin marketplace add obra/superpowers-marketplace' -Because $res.StdOut

            # Present: no add, even with no superpowers plugin at all.
            Remove-Item -LiteralPath $fx.ClaudeLog
            $res = Invoke-Install $fx -Env ($script:Skip + @{ FAKE_PLUGINS = (ConvertTo-Listing @((New-Plugin 'clavity@clavity' $fx.PluginFwd))) })
            Get-Log $fx.ClaudeLog | Should -Not -Contain 'plugin marketplace add obra/superpowers-marketplace' -Because $res.StdOut
        } finally { Remove-TestPath $fx.Root }
    }

    It 'installs superpowers only when no superpowers@* id is enabled, with -y --scope user' {
        $fx = New-Fx
        try {
            $plugins = ConvertTo-Listing @((New-Plugin 'superpowers@claude-plugins-official' (($fx.Root -replace '\\', '/') + '/other/off')), (New-Plugin 'clavity@clavity' $fx.PluginFwd))
            $res = Invoke-Install $fx -Env ($script:Skip + @{ FAKE_PLUGINS = $plugins })
            @(Get-Log $fx.ClaudeLog | Where-Object { $_ -like 'plugin install superpowers*' }).Count | Should -Be 0 -Because $res.StdOut

            Remove-Item -LiteralPath $fx.ClaudeLog
            $res = Invoke-Install $fx -Env ($script:Skip + @{ FAKE_PLUGINS = (ConvertTo-Listing @((New-Plugin 'clavity@clavity' $fx.PluginFwd))) })
            Get-Log $fx.ClaudeLog | Should -Contain 'plugin install superpowers@superpowers-marketplace -y --scope user' -Because $res.StdOut
        } finally { Remove-TestPath $fx.Root }
    }

    It 'installs clavity@clavity then each --with add-on, and --all installs all three' {
        $fx = New-Fx
        try {
            $sp = New-Plugin 'superpowers@superpowers-marketplace' (($fx.Root -replace '\\', '/') + '/other/sp')
            $env1 = $script:Skip + @{ FAKE_PLUGINS = (ConvertTo-Listing @($sp)); FAKE_PLUGINS_AFTER = $fx.DefaultPlugins }
            $res = Invoke-Install $fx '--with agy-autotrain,review-relay' -Env $env1
            $installs = @(Get-Log $fx.ClaudeLog | Where-Object { $_ -like 'plugin install *' })
            $installs | Should -Be @('plugin install clavity@clavity -y --scope user',
                                     'plugin install agy-autotrain@clavity -y --scope user',
                                     'plugin install review-relay@clavity -y --scope user') -Because $res.StdOut

            Remove-Item -LiteralPath $fx.ClaudeLog
            $res = Invoke-Install $fx '--all' -Env $env1
            $installs = @(Get-Log $fx.ClaudeLog | Where-Object { $_ -like 'plugin install *' })
            $installs | Should -Be @('plugin install clavity@clavity -y --scope user',
                                     'plugin install agy-autotrain@clavity -y --scope user',
                                     'plugin install commonmemory@clavity -y --scope user',
                                     'plugin install review-relay@clavity -y --scope user') -Because $res.StdOut
            $res.StdOut | Should -Match 'agentmemory' -Because 'the commonmemory prerequisite is printed as a note'
            $res.StdOut | Should -Match 'AiSaveDev' -Because 'the review-relay prerequisite is printed as a note'
        } finally { Remove-TestPath $fx.Root }
    }

    It 'reports an enabled plugin as already installed and does not reinstall' {
        $fx = New-Fx
        try {
            $plugins = ConvertTo-Listing @((New-Plugin 'superpowers@superpowers-marketplace' (($fx.Root -replace '\\', '/') + '/other/sp')),
                                           (New-Plugin 'clavity@clavity' $fx.PluginFwd),
                                           (New-Plugin 'commonmemory@clavity' (($fx.Root -replace '\\', '/') + '/other/cm')))
            $res = Invoke-Install $fx '--with commonmemory' -Env ($script:Skip + @{ FAKE_PLUGINS = $plugins })
            @(Get-Log $fx.ClaudeLog | Where-Object { $_ -like 'plugin install *' }).Count | Should -Be 0 -Because $res.StdOut
            $res.Lines | Should -Contain '[clavity install] clavity@clavity already installed'
            $res.Lines | Should -Contain '[clavity install] commonmemory@clavity already installed'
        } finally { Remove-TestPath $fx.Root }
    }

    It 'extracts installPath for clavity@clavity when it is listed LAST' {
        $fx = New-Fx
        try {
            $o = ($fx.Root -replace '\\', '/') + '/other'
            $plugins = ConvertTo-Listing @((New-Plugin 'superpowers@superpowers-marketplace' "$o/sp"),
                                           (New-Plugin 'agy-autotrain@clavity' "$o/aa"),
                                           (New-Plugin 'clavity@clavity' $fx.PluginFwd))
            $res = Invoke-Install $fx -Env ($script:Skip + @{ FAKE_PLUGINS = $plugins })
            Get-Log $fx.HookLog | Should -Contain "ROOT=$($fx.PluginFwd)" -Because $res.StdOut
            $res.StdOut | Should -Not -Match ([regex]::Escape("$o/aa"))
        } finally { Remove-TestPath $fx.Root }
    }

    It 'extracts installPath and version when the clavity@clavity object carries a nested mcpServers object and another plugin with its own installPath follows' {
        $fx = New-Fx
        try {
            $o = ($fx.Root -replace '\\', '/') + '/other'
            # The measured shape, by hand: id first, mcpServers{clavity-ls{command,args[],env{}}} between lastUpdated and
            # projectEnabled, then a second object with its own installPath and version.
            $plugins = @"
[
  {
    "id": "clavity@clavity",
    "version": "1.2.3",
    "scope": "user",
    "enabled": true,
    "installPath": "$($fx.PluginFwd)",
    "installedAt": "2026-11-10T08:00:00.000Z",
    "lastUpdated": "2026-11-10T08:00:00.000Z",
    "mcpServers": {
      "clavity-ls": {
        "command": "`${CLAUDE_PLUGIN_DATA}/bin/clavity-ls.exe",
        "args": [
          "mcp"
        ],
        "env": {}
      }
    },
    "projectEnabled": false
  },
  {
    "id": "agy-autotrain@clavity",
    "version": "4.5.6",
    "scope": "user",
    "enabled": true,
    "installPath": "$o/aa",
    "installedAt": "2026-11-10T08:00:00.000Z",
    "lastUpdated": "2026-11-10T08:00:00.000Z",
    "projectEnabled": false
  }
]
"@
            $res = Invoke-Install $fx -Env ($script:Skip + @{ FAKE_PLUGINS = $plugins })
            Get-Log $fx.HookLog | Should -Contain "ROOT=$($fx.PluginFwd)" -Because $res.StdOut
            $res.Lines | Should -Contain "[clavity install] clavity@clavity 1.2.3 at $($fx.PluginFwd)"
            $res.StdOut | Should -Not -Match '4\.5\.6'
            $res.StdOut | Should -Not -Match ([regex]::Escape("$o/aa"))
        } finally { Remove-TestPath $fx.Root }
    }

    It 'unescapes a JSON-encoded Windows installPath' {
        $fx = New-Fx
        try {
            $win = 'C:\Users\u\.claude\plugins\cache\clavity\clavity\9.9.9'
            $plugins = ConvertTo-Listing @((New-Plugin 'superpowers@superpowers-marketplace' 'C:\sp'), (New-Plugin 'clavity@clavity' $win))
            $plugins | Should -Match ([regex]::Escape('"C:\\Users\\u\\.claude\\plugins\\cache\\clavity\\clavity\\9.9.9"')) -Because 'the fixture must carry the JSON-escaped form'
            $res = Invoke-Install $fx -Env @{ CLAVITY_SKIP_PATH = '1'; FAKE_PLUGINS = $plugins } -PathValue '$p/shim:$p/agyshim:/usr/bin:/bin'
            $res.Lines | Should -Contain "[clavity install] clavity@clavity 9.9.9 at $win"
            Get-Log $fx.AgyLog | Should -Contain "plugin install $win"
        } finally { Remove-TestPath $fx.Root }
    }

    It 'deletes the fail stamp before running the hook' {
        $fx = New-Fx
        try {
            New-Item -ItemType Directory -Path (Join-Path $fx.Data 'bin') -Force | Out-Null
            $stamp = Join-Path $fx.Data 'bin/.clavity-ls.version.fail'
            [IO.File]::WriteAllText($stamp, "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())`n")
            $res = Invoke-Install $fx -Env $script:Skip
            Get-Log $fx.HookLog | Should -Contain 'FAILSTAMP=absent' -Because $res.StdOut
            $stamp | Should -Not -Exist
        } finally { Remove-TestPath $fx.Root }
    }

    It 'runs the hook with CLAUDE_PLUGIN_ROOT and CLAUDE_PLUGIN_DATA exported' {
        $fx = New-Fx
        try {
            $res = Invoke-Install $fx -Env $script:Skip
            $log = Get-Log $fx.HookLog
            $log | Should -Contain "ROOT=$($fx.PluginFwd)" -Because $res.StdOut
            @($log | Where-Object { $_ -like 'DATA=*' }).Count | Should -Be 1
            @($log | Where-Object { $_ -like 'DATA=*' })[0] | Should -Match '^DATA=.+/cfg/plugins/data/clavity-clavity$'
            $res.StdErr | Should -Match ([regex]::Escape('[clavity-ls] STUB installed clavity-ls 9.9.9')) -Because 'the hook stderr passes through'
            $res.StdOut | Should -Not -Match 'STUB-HOOK-JSON' -Because 'the hook stdout (its JSON) is discarded'
        } finally { Remove-TestPath $fx.Root }
    }

    It 'runs the agy pair and writes .agy-registered with the version when agy is on PATH' {
        $fx = New-Fx
        try {
            $res = Invoke-Install $fx -Env @{ CLAVITY_SKIP_PATH = '1' } -PathValue '$p/shim:$p/agyshim:/usr/bin:/bin'
            Get-Log $fx.AgyLog | Should -Be @('plugin uninstall clavity', "plugin install $($fx.PluginFwd)") -Because $res.StdOut
            $stamp = Join-Path $fx.Data '.agy-registered'
            $stamp | Should -Exist
            Get-Content -Raw -LiteralPath $stamp | Should -BeExactly '9.9.9'

            # A failed install is a warning carrying the manual remedy, never exit 2.
            Remove-Item -LiteralPath $stamp, $fx.AgyLog -Force
            $res = Invoke-Install $fx -Env @{ CLAVITY_SKIP_PATH = '1'; FAKE_AGY_EXIT = '1' } -PathValue '$p/shim:$p/agyshim:/usr/bin:/bin'
            $res.ExitCode | Should -Not -Be 2
            $res.StdOut | Should -Match ([regex]::Escape("agy plugin install `"$($fx.PluginFwd)`""))
            $stamp | Should -Not -Exist -Because "$($res.StdOut)`n$((Get-Log $fx.AgyLog) -join '|')"
        } finally { Remove-TestPath $fx.Root }
    }

    It 'says registration happens at the first session start when agy is absent' {
        $fx = New-Fx
        try {
            $res = Invoke-Install $fx -Env @{ CLAVITY_SKIP_PATH = '1' }
            $res.StdOut | Should -Match 'agy is not on PATH.*first Claude Code session start'
            Get-Log $fx.AgyLog | Should -BeNullOrEmpty
            Join-Path $fx.Data '.agy-registered' | Should -Not -Exist
        } finally { Remove-TestPath $fx.Root }
    }

    It 'skips the agy pair with CLAVITY_SKIP_AGY=1 and says so' {
        $fx = New-Fx
        try {
            $res = Invoke-Install $fx -Env $script:Skip -PathValue '$p/shim:$p/agyshim:/usr/bin:/bin'
            Get-Log $fx.AgyLog | Should -BeNullOrEmpty
            @($res.Lines | Where-Object { $_ -match 'CLAVITY_SKIP_AGY=1' }).Count | Should -Be 1 -Because $res.StdOut
            Join-Path $fx.Data '.agy-registered' | Should -Not -Exist
        } finally { Remove-TestPath $fx.Root }
    }

    It 'exit 0 happy path: link in place, dir on PATH, plugin enabled, launch line last' -Tag 'LinuxOnly' -Skip:($IsWindows) {
        $fx = New-Fx
        try {
            $res = Invoke-Install $fx
            $res.ExitCode | Should -Be 0 -Because "$($res.StdOut)`n$($res.StdErr)"
            Test-Bash '[ -L "$1" ] && [ "$1" -ef "$2" ]' (Join-Path $fx.Home '.local/bin/clavity-ls'), (Join-Path $fx.Data 'bin/clavity-ls.exe') | Should -Be 'YES'
            $res.Lines | Should -Contain '[clavity install] clavity-ls will resolve in new terminals'
            $res.Last | Should -BeExactly $script:LaunchLine
            Get-Log $fx.ClaudeLog | Should -Contain 'plugin list --json'
            foreach ($l in $res.Lines[0..($res.Lines.Count - 2)]) { $l | Should -BeLike '`[clavity install`] *' }
            Get-ChildItem -LiteralPath $fx.Tmp -Force | Should -BeNullOrEmpty -Because 'the mktemp dir is removed on exit'
        } finally { Remove-TestPath $fx.Root }
    }

    It 'exit 1 when claude is not on PATH' {
        $fx = New-Fx
        try {
            $res = Invoke-Install $fx -PathValue '/usr/bin:/bin'
            $res.ExitCode | Should -Be 1
            $res.StdOut | Should -Match '\[clavity install\] .*claude'
            Get-Log $fx.ClaudeLog | Should -BeNullOrEmpty
            Join-Path $fx.Cfg 'plugins' | Should -Not -Exist
        } finally { Remove-TestPath $fx.Root }
    }

    It 'exit 2 when the binary does not run after the hook, naming it' {
        $fx = New-Fx
        try {
            # The hook placed nothing: its own message is repeated.
            $res = Invoke-Install $fx -Env ($script:Skip + @{ FAKE_HOOK_FAIL = '1' })
            $res.ExitCode | Should -Be 2 -Because $res.StdOut
            $fail = @($res.Lines | Where-Object { $_ -match 'FAILED' })
            $fail.Count | Should -BeGreaterThan 0 -Because $res.StdOut
            $fail[0] | Should -Match ([regex]::Escape('clavity-ls.exe --version'))
            $fail[0] | Should -Match ([regex]::Escape('STUB release lookup failed (offline?)'))
            $res.StdErr | Should -Match 'FAILED'
            $res.Last | Should -BeExactly $script:NotInstalledLine
            @($res.Lines | Where-Object { $_ -like ($script:LaunchPrefix + '*') }).Count | Should -Be 0 -Because 'there is nothing to launch on exit 2'

            # The binary is there but does not run.
            $res = Invoke-Install $fx -Env ($script:Skip + @{ FAKE_BIN_EXIT = '1' })
            $res.ExitCode | Should -Be 2 -Because $res.StdOut
            @($res.Lines | Where-Object { $_ -match 'FAILED' -and $_ -match [regex]::Escape('clavity-ls.exe --version') }).Count | Should -Be 1
            $res.Last | Should -BeExactly $script:NotInstalledLine
            @($res.Lines | Where-Object { $_ -like ($script:LaunchPrefix + '*') }).Count | Should -Be 0 -Because 'there is nothing to launch on exit 2'
        } finally { Remove-TestPath $fx.Root }
    }

    It 'exit 2 when clavity@clavity is not enabled after install' {
        $fx = New-Fx
        try {
            $plugins = ConvertTo-Listing @((New-Plugin 'superpowers@superpowers-marketplace' (($fx.Root -replace '\\', '/') + '/other/sp')),
                                           (New-Plugin 'clavity@clavity' $fx.PluginFwd $false))
            $res = Invoke-Install $fx -Env ($script:Skip + @{ FAKE_PLUGINS = $plugins })
            $res.ExitCode | Should -Be 2 -Because $res.StdOut
            @($res.Lines | Where-Object { $_ -match 'FAILED' -and $_ -match 'clavity@clavity is not enabled' }).Count | Should -Be 1 -Because $res.StdOut
            $res.StdErr | Should -Match 'clavity@clavity is not enabled'
            $res.Last | Should -BeExactly $script:NotInstalledLine
            @($res.Lines | Where-Object { $_ -like ($script:LaunchPrefix + '*') }).Count | Should -Be 0 -Because 'there is nothing to launch on exit 2'
        } finally { Remove-TestPath $fx.Root }
    }

    It 'exit 3 names a foreign regular file at ~/.local/bin/clavity-ls instead of saying there is none' {
        $fx = New-Fx
        try {
            # A hand-placed file at the link path: the lib leaves it alone, and the status line must name it as the
            # user's own file, not claim there is no link. ~/.local/bin is on PATH (the default), so only the file is wrong.
            $link = Join-Path $fx.Home '.local/bin/clavity-ls'
            New-Item -ItemType Directory -Path (Split-Path -Parent $link) | Out-Null
            [IO.File]::WriteAllText($link, 'MINE')
            $res = Invoke-Install $fx -Env @{ CLAVITY_SKIP_AGY = '1' }
            $res.ExitCode | Should -Be 3 -Because "$($res.StdOut)`n$($res.StdErr)"
            $status = @($res.Lines | Where-Object { $_ -like '`[clavity install`] clavity-ls is NOT on PATH yet: *' })
            $status.Count | Should -Be 1 -Because $res.StdOut
            $status[0] | Should -Match 'your own file'
            $status[0] | Should -Not -Match 'there is no' -Because 'a file IS there'
            $res.Last | Should -BeLike ($script:LaunchPrefix + '*')
            Test-Bash '[ -f "$1" ] && [ ! -L "$1" ]' $link | Should -Be 'YES'
            Get-Content -Raw -LiteralPath $link | Should -BeExactly 'MINE'
        } finally { Remove-TestPath $fx.Root }
    }

    It 'exit 3 with CLAVITY_SKIP_PATH=1 on Unix, status line says NOT on PATH, launch line carries export PATH' {
        $fx = New-Fx
        try {
            $res = Invoke-Install $fx -Env $script:Skip
            $res.ExitCode | Should -Be 3 -Because "$($res.StdOut)`n$($res.StdErr)"
            $status = @($res.Lines | Where-Object { $_ -like '`[clavity install`] clavity-ls is NOT on PATH yet: *' })
            $status.Count | Should -Be 1 -Because $res.StdOut
            $status[0] | Should -Match 'CLAVITY_SKIP_PATH=1'
            @($res.Lines | Where-Object { $_ -like '`[clavity install`]*skipped*CLAVITY_SKIP_PATH=1*' }).Count | Should -BeGreaterThan 0
            $res.Last | Should -BeLike ($script:LaunchPrefix + 'export PATH=*')
            $res.Last | Should -BeLike '* start <folder>'
            # Works as pasted: the command, with `start <folder>` swapped for --version, runs in a fresh shell.
            $pasted = $res.Last.Substring($script:LaunchPrefix.Length) -replace ' start <folder>$', ' --version'
            $out = & $script:Bash -c "PATH=/usr/bin:/bin; $pasted"
            $LASTEXITCODE | Should -Be 0 -Because $pasted
            "$out" | Should -Match 'clavity-ls 9\.9\.9'
        } finally { Remove-TestPath $fx.Root }
    }

    It 'exit 3 with CLAVITY_SKIP_PATH=1 on Windows, never 2' {
        $fx = New-Fx
        try {
            $res = Invoke-Install $fx -OsType 'msys' -Env ($script:Skip + @{ FAKE_USER_PATH = 'C:\Windows;C:\Users\u\other' })
            $res.ExitCode | Should -Be 3 -Because "$($res.StdOut)`n$($res.StdErr)"
            @($res.Lines | Where-Object { $_ -like '`[clavity install`] clavity-ls is NOT on PATH yet: *' }).Count | Should -Be 1 -Because $res.StdOut
            $res.Last | Should -BeLike ($script:LaunchPrefix + '& "*\bin\clavity-ls.exe" start <folder>')
            $res.Last | Should -Match ([regex]::Escape('\cfg\plugins\data\clavity-clavity\bin\clavity-ls.exe'))
            $ps = (Get-Log $fx.PsLog) -join "`n"
            $ps | Should -Match ([regex]::Escape("[Environment]::GetEnvironmentVariable('Path','User')")) -Because 'the USER PATH is read back from the registry'
            $ps | Should -Not -Match 'SetEnvironmentVariable' -Because 'CLAVITY_SKIP_PATH=1 skips the launcher step'

            # The same dir present in the user PATH (any spelling): exit 0, and the console-window clause.
            $winBin = (& $script:Bash -c 'PATH="$1:/usr/bin:/bin" cygpath -w "$2"' _ ($fx.Shim -replace '\\', '/') ((Join-Path $fx.Data 'bin') -replace '\\', '/')).Trim()
            $res = Invoke-Install $fx -OsType 'msys' -Env ($script:Skip + @{ FAKE_USER_PATH = "C:\Windows;$($winBin.ToUpper())\" })
            $res.ExitCode | Should -Be 0 -Because "$($res.StdOut)`n$($res.StdErr)"
            @($res.Lines | Where-Object { $_ -like '`[clavity install`] clavity-ls will resolve in new terminals*new console window*' }).Count | Should -Be 1 -Because $res.StdOut
            $res.Last | Should -BeExactly $script:LaunchLine
        } finally { Remove-TestPath $fx.Root }
    }

    It '--no-launcher writes .no-launcher and exits 3 naming the marker; --launcher removes it and exits 0' -Tag 'LinuxOnly' -Skip:($IsWindows) {
        $fx = New-Fx
        try {
            $marker = Join-Path $fx.Data 'bin/.no-launcher'
            $res = Invoke-Install $fx '--no-launcher' -Env @{ CLAVITY_SKIP_AGY = '1' }
            $marker | Should -Exist
            $res.ExitCode | Should -Be 3 -Because "$($res.StdOut)`n$($res.StdErr)"
            $status = @($res.Lines | Where-Object { $_ -like '`[clavity install`] clavity-ls is NOT on PATH yet: *' })
            $status.Count | Should -Be 1
            $status[0] | Should -Match ([regex]::Escape('.no-launcher'))
            Join-Path $fx.Home '.local/bin/clavity-ls' | Should -Not -Exist

            # A plain run never touches the marker.
            $res = Invoke-Install $fx -Env @{ CLAVITY_SKIP_AGY = '1' }
            $marker | Should -Exist
            $res.ExitCode | Should -Be 3

            $res = Invoke-Install $fx '--launcher' -Env @{ CLAVITY_SKIP_AGY = '1' }
            $marker | Should -Not -Exist
            $res.ExitCode | Should -Be 0 -Because "$($res.StdOut)`n$($res.StdErr)"
            Test-Bash '[ -L "$1" ] && [ "$1" -ef "$2" ]' (Join-Path $fx.Home '.local/bin/clavity-ls'), (Join-Path $fx.Data 'bin/clavity-ls.exe') | Should -Be 'YES'
            $res.Last | Should -BeExactly $script:LaunchLine
        } finally { Remove-TestPath $fx.Root }
    }

    It '--dry-run prints the commands and runs none' {
        $fx = New-Fx
        try {
            $res = Invoke-Install $fx '--dry-run --all' -PathValue '$p/shim:$p/agyshim:/usr/bin:/bin'
            $res.ExitCode | Should -Be 0 -Because $res.StdOut
            Get-Log $fx.ClaudeLog | Should -BeNullOrEmpty
            Get-Log $fx.AgyLog | Should -BeNullOrEmpty
            Get-Log $fx.CurlLog | Should -BeNullOrEmpty
            Get-Log $fx.HookLog | Should -BeNullOrEmpty
            Join-Path $fx.Cfg 'plugins' | Should -Not -Exist
            foreach ($c in 'claude plugin marketplace list --json', 'claude plugin marketplace add ckir/clavity',
                           'claude plugin marketplace add obra/superpowers-marketplace',
                           'claude plugin install superpowers@superpowers-marketplace -y --scope user',
                           'claude plugin install clavity@clavity -y --scope user',
                           'claude plugin install agy-autotrain@clavity -y --scope user',
                           'claude plugin install commonmemory@clavity -y --scope user',
                           'claude plugin install review-relay@clavity -y --scope user',
                           'hooks/fetch-clavity-ls.sh', 'agy plugin uninstall clavity', 'agy plugin install', 'clavity-ls.exe --version') {
                $res.StdOut | Should -Match ([regex]::Escape($c)) -Because "dry-run must print '$c'"
            }
            $res.Last | Should -BeExactly $script:LaunchLine
        } finally { Remove-TestPath $fx.Root }
    }

    It 'an unknown flag prints the usage line and exits 1 before running anything' {
        $fx = New-Fx
        try {
            $res = Invoke-Install $fx '--bogus'
            $res.ExitCode | Should -Be 1
            $res.Lines.Count | Should -Be 1 -Because $res.StdOut
            $res.Lines[0] | Should -BeLike '`[clavity install`] *usage*'
            foreach ($f in '--with', '--all', '--dry-run', '--no-launcher', '--launcher') { $res.Lines[0] | Should -Match ([regex]::Escape($f)) }
            Get-Log $fx.ClaudeLog | Should -BeNullOrEmpty
            Join-Path $fx.Cfg 'plugins' | Should -Not -Exist

            $res = Invoke-Install $fx '--with nosuchaddon'
            $res.ExitCode | Should -Be 1
            Get-Log $fx.ClaudeLog | Should -BeNullOrEmpty
        } finally { Remove-TestPath $fx.Root }
    }

    It 'a truncated script runs nothing' {
        $fx = New-Fx
        try {
            $res = Invoke-Install $fx -Truncate -Env $script:Skip
            Get-Log $fx.ClaudeLog | Should -BeNullOrEmpty -Because "$($res.StdOut)`n$($res.StdErr)"
            Get-Log $fx.HookLog | Should -BeNullOrEmpty
            Join-Path $fx.Cfg 'plugins' | Should -Not -Exist
            $res.StdOut | Should -Not -Match '\[clavity install\]'
            # Control: the whole file, fed the same way, does run.
            $full = & $script:Bash -c 'export PATH="$2/shim:/usr/bin:/bin" HOME="$2/home" CLAUDE_CONFIG_DIR="$2/cfg" FAKE_CLAUDE_LOG="$2/claude.log"; cat "$1" | "$BASH" -s -- --bogus' _ ($script:Install -replace '\\', '/') ($fx.Root -replace '\\', '/')
            "$full" | Should -Match 'usage'
        } finally { Remove-TestPath $fx.Root }
    }

    It 'fetches the lib from RAW_BASE/clavity-dotnet/plugin/hooks/clavity-ls-launcher-lib.sh when CLAVITY_INSTALL_LIB is unset' -Tag 'LinuxOnly' -Skip:($IsWindows) {
        $fx = New-Fx
        try {
            $dst = Join-Path $fx.Served $script:LibRel
            New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
            Copy-Item -LiteralPath $script:Lib -Destination $dst
            $res = Invoke-Install $fx -Env @{ CLAVITY_SKIP_AGY = '1'; CLAVITY_INSTALL_LIB = ''; CLAVITY_INSTALL_RAW_BASE = $script:RawBase }
            Get-Log $fx.CurlLog | Should -Contain "$($script:RawBase)/$($script:LibRel)" -Because $res.StdOut
            $res.ExitCode | Should -Be 0 -Because "$($res.StdOut)`n$($res.StdErr)"
            Test-Bash '[ -L "$1" ] && [ "$1" -ef "$2" ]' (Join-Path $fx.Home '.local/bin/clavity-ls'), (Join-Path $fx.Data 'bin/clavity-ls.exe') | Should -Be 'YES'
            Get-ChildItem -LiteralPath $fx.Tmp -Force | Should -BeNullOrEmpty -Because 'the mktemp dir holding the fetched lib is removed on exit'
        } finally { Remove-TestPath $fx.Root }
    }

    It 'a failed lib fetch is a warning naming the URL, not exit 2' {
        $fx = New-Fx
        try {
            $res = Invoke-Install $fx -Env @{ CLAVITY_SKIP_AGY = '1'; CLAVITY_INSTALL_LIB = ''; CLAVITY_INSTALL_RAW_BASE = $script:RawBase }
            $url = "$($script:RawBase)/$($script:LibRel)"
            Get-Log $fx.CurlLog | Should -Contain $url
            @($res.Lines | Where-Object { $_ -like '`[clavity install`] WARNING*' -and $_ -like "*$url*" }).Count | Should -Be 1 -Because $res.StdOut
            @($res.Lines | Where-Object { $_ -like '`[clavity install`] clavity-ls is NOT on PATH yet: *' }).Count | Should -Be 1
            $res.ExitCode | Should -Be 3 -Because "$($res.StdOut)`n$($res.StdErr)"
            $res.Last | Should -BeLike ($script:LaunchPrefix + 'export PATH=*')
        } finally { Remove-TestPath $fx.Root }
    }

    It 'launch line names the git toplevel when run inside a repo, else the placeholder' {
        $fx = New-Fx
        try {
            $repo = Join-Path $fx.Root 'repo'
            New-Item -ItemType Directory -Path (Join-Path $repo 'sub') -Force | Out-Null
            & git -C $repo init -q
            $top = "$(& git -C $repo rev-parse --show-toplevel)".Trim()
            $res = Invoke-Install $fx -Env $script:Skip -Cwd '$p/repo/sub'
            $res.Last | Should -BeLike ($script:LaunchPrefix + '*')
            $res.Last | Should -BeLike "* start $top"

            $res = Invoke-Install $fx -Env $script:Skip
            $res.Last | Should -BeLike '* start <folder>'
        } finally { Remove-TestPath $fx.Root }
    }
}

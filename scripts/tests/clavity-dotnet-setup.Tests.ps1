# ROADMAP section 68. clavity-dotnet-setup.sh registers the plugin with agy (`agy plugin uninstall clavity` + `agy plugin install
# <root>`) and used to do so ONCE, gated by an empty stamp in CLAUDE_PLUGIN_DATA - which survives plugin upgrades, so no upgrade
# ever reached agy's copy. The stamp now holds the plugin version and the hook registers again whenever it differs.
# `agy` is a SHIM on PATH that logs its arguments (this box has a REAL agy: an unshimmed row would uninstall the owner's plugin).
# The shim needs its exec bit (chmod) and the PATH prefix is converted with cygpath only where cygpath exists, so the suite runs
# on Git Bash and on Linux alike.
BeforeAll {
    . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
    $script:Hook = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'clavity-dotnet/plugin/hooks/clavity-dotnet-setup.sh'
    $script:Bash = Get-GitBashOrThrow
    $script:ConvPath = 'p="$1"; command -v cygpath >/dev/null 2>&1 && p="$(cygpath -u "$1")"'

    function New-Fx([string]$Manifest = '{ "name": "clavity", "version": "9.9.9" }') {
        $root = New-TestTempPath 'cds'
        $fx = [pscustomobject]@{
            Root = $root; Data = (Join-Path $root 'data'); PluginRoot = (Join-Path $root 'plugin')
            Shim = (Join-Path $root 'shim'); Home = (Join-Path $root 'home'); Log = (Join-Path $root 'agy.log')
        }
        New-Item -ItemType Directory -Path $fx.Data, $fx.PluginRoot, $fx.Shim, $fx.Home | Out-Null
        [IO.File]::WriteAllText((Join-Path $fx.PluginRoot 'plugin.json'), "$Manifest`n")
        # Fake agy: logs "<args>" and fails `plugin install` when FAKE_AGY=fail.
        $agy = @'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
[ "${FAKE_AGY:-ok}" = fail ] && [ "$1 $2" = "plugin install" ] && exit 1
exit 0
'@
        [IO.File]::WriteAllText((Join-Path $fx.Shim 'agy'), $agy)
        $s = $fx.Shim -replace '\\', '/'
        & $script:Bash -c "chmod +x '$s/agy'"
        # FIXTURE SANITY: the shim must win over any real agy, or every row below would drive the owner's real plugin registration.
        (& $script:Bash -c "$($script:ConvPath); PATH=`"`$p:`$PATH`"; type -P agy" _ $fx.Shim | Out-String).Trim() | Should -Match '/shim/agy$'
        return $fx
    }
    function Invoke-Setup($Fx, [string]$Fake = 'ok', [switch]$NoAgy, [switch]$NoPluginContext) {
        $vars = @{
            CLAUDE_PLUGIN_ROOT = $Fx.PluginRoot; CLAUDE_PLUGIN_DATA = $(if ($NoPluginContext) { '' } else { $Fx.Data })
            FAKE_AGY = $Fake; FAKE_LOG = ($Fx.Log -replace '\\', '/'); HOME = $Fx.Home; CLAVITY_GOLDEN_HEADER = (Join-Path $Fx.Home '.clavity')
        }
        $errFile = [IO.Path]::GetTempFileName()
        try {
            foreach ($k in $vars.Keys) { Set-Item -Path "Env:$k" -Value $vars[$k] }
            # -NoAgy drops every PATH directory holding an agy, so the hook sees no agy CLI at all.
            $cmd = if ($NoAgy) {
                'np=; IFS=:; for d in $PATH; do [ -x "$d/agy" ] || [ -x "$d/agy.exe" ] || np="$np${np:+:}$d"; done; unset IFS
                 PATH="$np"; command -v agy >/dev/null && { echo "fixture: agy still on PATH" >&2; exit 99; }
                 bash "$2" </dev/null'
            } else { "$($script:ConvPath); PATH=`"`$p:`$PATH`" bash `"`$2`" </dev/null" }
            $null = & $script:Bash -c $cmd _ $Fx.Shim ($script:Hook -replace '\\', '/') 2>$errFile | Out-String
            $code = $LASTEXITCODE
            $calls = if (Test-Path -LiteralPath $Fx.Log) { @(Get-Content -LiteralPath $Fx.Log) } else { @() }
            return [pscustomobject]@{ ExitCode = $code; StdErr = "$(Get-Content -Raw -LiteralPath $errFile)".Trim(); Calls = $calls }
        } finally {
            foreach ($k in $vars.Keys) { Remove-Item -Path "Env:$k" -ErrorAction SilentlyContinue }
            Remove-Item -LiteralPath $errFile -ErrorAction SilentlyContinue
        }
    }
    function Get-Stamp($Fx) { Get-Content -Raw -LiteralPath (Join-Path $Fx.Data '.agy-registered') }
    function Set-Stamp($Fx, [string]$Text) { [IO.File]::WriteAllText((Join-Path $Fx.Data '.agy-registered'), $Text) }
}

Describe 'clavity-dotnet-setup.sh keeps agy registered at the CURRENT plugin version' {
    It 'registers once when there is no stamp, and writes the plugin VERSION into the stamp' {
        $fx = New-Fx
        try {
            $res = Invoke-Setup $fx
            $res.ExitCode | Should -Be 0
            $res.Calls | Should -HaveCount 2
            $res.Calls[0] | Should -BeExactly 'plugin uninstall clavity'
            $res.Calls[1] | Should -BeExactly "plugin install $($fx.PluginRoot)"   # the hook passes CLAUDE_PLUGIN_ROOT through verbatim: backslashes stay on Windows
            Get-Stamp $fx | Should -BeExactly '9.9.9'
            $res.StdErr | Should -Match 'registered the plugin with agy'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does nothing when the stamp already names the current version (<Name>)' -TestCases @(
        @{ Name = 'bare'; Text = '9.9.9' }
        @{ Name = 'newline-terminated'; Text = "9.9.9`n" }
    ) {
        $fx = New-Fx
        try {
            Set-Stamp $fx $Text
            $res = Invoke-Setup $fx
            $res.ExitCode | Should -Be 0
            $res.Calls | Should -HaveCount 0
            Get-Stamp $fx | Should -BeExactly $Text
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'registers again when the stamp names an OLDER version, and rewrites the stamp to the new one' {
        $fx = New-Fx
        try {
            Set-Stamp $fx '9.9.8'
            $res = Invoke-Setup $fx
            $res.Calls | Should -HaveCount 2
            $res.Calls[0] | Should -BeExactly 'plugin uninstall clavity'
            $res.Calls[1] | Should -Match '^plugin install '
            Get-Stamp $fx | Should -BeExactly '9.9.9'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'treats the EMPTY stamp the old hook wrote as an older version (the upgrade path of every existing install)' {
        $fx = New-Fx
        try {
            Set-Stamp $fx ''
            $res = Invoke-Setup $fx
            $res.Calls | Should -HaveCount 2
            Get-Stamp $fx | Should -BeExactly '9.9.9'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'a version that merely CONTAINS the stamp is a different version (9.9.9 vs 9.9.90)' {
        $fx = New-Fx '{ "name": "clavity", "version": "9.9.90" }'
        try {
            Set-Stamp $fx '9.9.9'
            $res = Invoke-Setup $fx
            $res.Calls | Should -HaveCount 2
            Get-Stamp $fx | Should -BeExactly '9.9.90'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'keeps the OLD stamp, says how to pair by hand, and still exits 0 when agy refuses the install' {
        $fx = New-Fx
        try {
            Set-Stamp $fx '9.9.8'
            $res = Invoke-Setup $fx -Fake fail
            $res.ExitCode | Should -Be 0
            $res.Calls | Should -HaveCount 2
            $res.StdErr | Should -Match 'could not auto-register with agy'
            Get-Stamp $fx | Should -BeExactly '9.9.8' -Because 'a failed install must be retried by the next session'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'writes no stamp at all when the FIRST install fails' {
        $fx = New-Fx
        try {
            $res = Invoke-Setup $fx -Fake fail
            $res.ExitCode | Should -Be 0
            Test-Path -LiteralPath (Join-Path $fx.Data '.agy-registered') | Should -BeFalse
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'leaves a registered agy alone when the plugin version cannot be read, and registers once when nothing is stamped' {
        $fx = New-Fx '{ "name": "clavity" }'
        try {
            Set-Stamp $fx '9.9.8'
            (Invoke-Setup $fx).Calls | Should -HaveCount 0
            Get-Stamp $fx | Should -BeExactly '9.9.8'
            # -Force: PowerShell on Linux treats a dotfile as hidden and refuses a plain Remove-Item (measured; the error is non-terminating).
            Remove-Item -LiteralPath (Join-Path $fx.Data '.agy-registered') -Force -ErrorAction Stop
            $res = Invoke-Setup $fx
            $res.Calls | Should -HaveCount 2
            Test-Path -LiteralPath (Join-Path $fx.Data '.agy-registered') | Should -BeTrue
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does nothing without the agy CLI, and leaves no stamp so a later session registers' {
        $fx = New-Fx
        try {
            $res = Invoke-Setup $fx -NoAgy
            $res.ExitCode | Should -Be 0
            $res.Calls | Should -HaveCount 0
            Test-Path -LiteralPath (Join-Path $fx.Data '.agy-registered') | Should -BeFalse
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'says and does nothing outside a plugin context' {
        $fx = New-Fx
        try {
            $res = Invoke-Setup $fx -NoPluginContext
            $res.ExitCode | Should -Be 0
            $res.Calls | Should -HaveCount 0
            $res.StdErr | Should -BeNullOrEmpty
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

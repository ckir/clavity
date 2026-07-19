#requires -Version 5.1
<#
.SYNOPSIS  The single tested source of truth for clavity plugin registration (decision D2).
.DESCRIPTION
  Behavior is PluginInstaller.cs's contract, verbatim. Registers/deregisters a member plugin into Claude
  Code and/or agy via each agent's PUBLIC plugin CLI only. Idempotency is structural (remove-then-add,
  swallow the remove). Every agent-CLI call is time-boxed. Per-agent results are fixed single-line
  "AGENT <name> OK|FAIL <reason>" records on STDOUT; the process exit code encodes the aggregate:
    0 = every DETECTED agent succeeded   2 = partial   3 = every detected agent failed   4 = none detected
  Invoked two ways: Inno `powershell -File` (plugin-only members) and clavity-ls streaming via
  -EncodedCommand + env params (dotnet). An uncaught throw collapses to exit 1 (callers treat 1/unmapped
  as total failure).
#>
[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Uninstall,
    [string]$PluginName,
    [string]$MarketplaceName,
    [string]$AppDir,
    [ValidateSet('all', 'claude', 'agy')]
    [string]$Agent = 'all'
)

# Dual-binding fallback (§3.4): the streaming (C#/stdin) path passes params as env vars, NOT named args;
# a PS 5.1 param() does not auto-populate from $env:, so bind explicitly when the named arg was omitted.
if (-not $PluginName)      { $PluginName      = $env:CLAVITY_PLUGINNAME }
if (-not $MarketplaceName) { $MarketplaceName = $env:CLAVITY_MARKETPLACENAME }
if (-not $AppDir)          { $AppDir          = $env:CLAVITY_APPDIR }
if (-not $PSBoundParameters.ContainsKey('Agent') -and $env:CLAVITY_AGENT) { $Agent = $env:CLAVITY_AGENT }
if (-not $PSBoundParameters.ContainsKey('Install')   -and $env:CLAVITY_VERB -eq 'install')   { $Install = $true }
if (-not $PSBoundParameters.ContainsKey('Uninstall') -and $env:CLAVITY_VERB -eq 'uninstall') { $Uninstall = $true }

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:LegacyMarketplaceName = 'clavity'   # the one pre-cohesive shared marketplace (Bug-1 migration)
$script:CliTimeoutSec         = 60          # per-call time-box; an expired call = that-agent FAIL

# Bound + single-line the untrusted <reason> so a child's newline can never forge a second AGENT line.
function Format-Reason {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '(no output)' }
    $flat = $Text -replace '[\r\n]+', ' '
    if ($flat.Length -gt 200) { $flat = $flat.Substring(0, 200) }
    return $flat.Trim()
}

function Test-CliPresent {
    param([string]$Stem)
    $cmd = Get-Command $Stem -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    return [bool]$cmd
}

# Detection mirrors Clavity.Ls.Install.AgentDetection: present iff CLI on PATH OR config dir exists.
function Test-AgentPresent {
    param([string]$Name)
    switch ($Name) {
        'claude' { return (Test-CliPresent 'claude') -or (Test-Path (Join-Path $env:USERPROFILE '.claude')) }
        'agy'    { return (Test-CliPresent 'agy')    -or (Test-Path (Join-Path $env:USERPROFILE '.gemini')) }
    }
    return $false
}

# Inner running-Claude re-check (§3.3): PS-native, same public surface as the outer tasklist gate.
function Test-ClaudeRunning {
    return [bool](Get-Process -Name claude -ErrorAction SilentlyContinue)
}

# Time-boxed agent-CLI call. Runs `& <exe> @args` INSIDE a background job so arg-array quoting is preserved
# (injection-safe, §3.5) AND we get a kill handle for the time-box. Captures the child's own stdout/stderr
# INTERNALLY (§3.1.1). Returns @{ ExitCode; Output }.
# Tradeoff (agy review A1): Start-Job spawns a child powershell per call (~hundreds of ms). Accepted — it is
# ~8 calls once per install, and a lighter System.Diagnostics.Process would lose ArgumentList under PS 5.1
# (.NET Framework), re-introducing the manual arg-quoting bug the array form exists to avoid.
function Invoke-AgentCli {
    param(
        [string]$Exe,
        [string[]]$CliArgs,
        [int]$TimeoutSec = $script:CliTimeoutSec
    )
    # A .cmd/.bat shim needs explicit quoting: PS 5.1 lacks PSNativeCommandArgumentPassing, so array args
    # through a shim can re-split. Native .exe (the verified norm) uses plain array passing.
    $resolved = Get-Command $Exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $isShim = $false
    if ($resolved) {
        $ext = [System.IO.Path]::GetExtension($resolved.Source).ToLowerInvariant()
        if ($ext -eq '.cmd' -or $ext -eq '.bat') { $isShim = $true }
    }
    # NOTE the (,$CliArgs) wrap — forces the array through -ArgumentList as ONE param (PS 5.1 unwraps a bare array).
    $job = Start-Job -ScriptBlock {
        param($JExe, $JArgs, $JIsShim)
        $ErrorActionPreference = 'Continue'
        # Out-String -Width 4096: a job runspace has no console host, so a bare Out-String defaults to ~80
        # cols and would inject \r\n MID-LINE, splitting a long `plugin@marketplace` token so the read-back
        # Select-String misses it (agy review A4). The wide width prevents the spurious wrap.
        if ($JIsShim) {
            $q = $JArgs | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }
            $out = & $JExe @q 2>&1 | Out-String -Width 4096
        }
        else {
            $out = & $JExe @JArgs 2>&1 | Out-String -Width 4096
        }
        [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = $out }
    } -ArgumentList $Exe, (, $CliArgs), $isShim

    $finished = Wait-Job -Job $job -Timeout $TimeoutSec
    if (-not $finished) {
        Stop-Job   -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        return @{ ExitCode = 124; Output = "timed out after ${TimeoutSec}s" }
    }
    # Receive-Job may surface job-infra ErrorRecords (e.g. a not-found exe throws inside the job) alongside or
    # instead of our object. Under StrictMode 2.0, `$errorRecord.ExitCode` would THROW (agy review A3), so pick
    # the LAST emitted item that actually carries an ExitCode property; treat anything else as a clean failure.
    $items = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    $r = $items | Where-Object { ($null -ne $_) -and $_.PSObject.Properties['ExitCode'] } | Select-Object -Last 1
    if ($null -eq $r) { return @{ ExitCode = 1; Output = '(command not found or no result from agent CLI)' } }
    return @{ ExitCode = [int]$r.ExitCode; Output = [string]$r.Output }
}

# --- (verb functions + orchestrator added in Tasks 2-3) ---

# main-guard: run only when invoked directly (NOT when dot-sourced by Pester — InvocationName is '.').
if ($MyInvocation.InvocationName -ne '.') {
    $verb = 'install'
    if ($Uninstall) { $verb = 'uninstall' }
    $result = Invoke-Registration -Verb $verb -PluginName $PluginName -MarketplaceName $MarketplaceName -AppDir $AppDir -AgentSel $Agent
    $result.AgentLines | ForEach-Object { Write-Output $_ }
    exit $result.ExitCode
}

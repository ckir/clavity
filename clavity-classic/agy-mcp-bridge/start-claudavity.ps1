#!/usr/bin/env pwsh
# start-claudavity.ps1
# Launch the Claude <-> agy "remote control" pair in one shared folder:
#   1) agy (Antigravity CLI) in a detached psmux session, signed-in
#   2) Claude Code in the same folder (foreground)
#
# Run this from YOUR normal pwsh (not from inside Claude) so agy inherits your
# signed-in session. The psmux session name defaults to "claude_agy", matching
# agy_tmux.py so the doorbell targets it with no extra config.
#
# Usage:
#   start-claudavity.ps1                                  # current folder
#   start-claudavity.ps1 C:\path\to\project               # given folder
#   start-claudavity.ps1 --resume                         # current folder; forward --resume to claude
#   start-claudavity.ps1 C:\path --resume --model opus    # folder + flags forwarded to claude
#
# The FIRST argument is the folder only if it does not start with '-'; every other
# argument is forwarded verbatim to `claude`. agy's own flags come from
# $env:AGY_START_ARGS (default: --dangerously-skip-permissions).
# Overrides: $env:AGY_TMUX_BIN (psmux path), $env:AGY_SESSION (session name).
# Watch agy live: <psmux> attach -t claude_agy   (detach with Ctrl-b d)

param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)

$psmux = if ($env:AGY_TMUX_BIN) {
    $env:AGY_TMUX_BIN
} else {
    # PATH, never a hardcoded location: a pinned path only works on the machine it was written on.
    $found = @('psmux', 'tmux') |
        ForEach-Object { (Get-Command $_ -ErrorAction SilentlyContinue).Source } |
        Where-Object { $_ } | Select-Object -First 1
    if (-not $found) {
        throw "Cannot find the psmux/tmux binary. Put psmux (or tmux) on PATH, or set AGY_TMUX_BIN to its full path."
    }
    $found
}
$session = if ($env:AGY_SESSION)    { $env:AGY_SESSION }    else { "claude_agy" }
$agyArgs = if ($env:AGY_START_ARGS) { $env:AGY_START_ARGS } else { "--dangerously-skip-permissions" }

# First non-dash arg is the folder; everything else is forwarded to claude.
$Folder = (Get-Location).Path
$ClaudeArgs = @()
if ($Rest) {
    if ($Rest[0] -notlike '-*') {
        $Folder = $Rest[0]
        if ($Rest.Count -gt 1) { $ClaudeArgs = $Rest[1..($Rest.Count - 1)] }
    } else {
        $ClaudeArgs = $Rest
    }
}

if (-not (Test-Path $Folder)) {
    Write-Error "Folder not found: $Folder"
    exit 1
}
$Folder = (Resolve-Path $Folder).Path

if (-not (Test-Path (Join-Path $Folder ".git"))) {
    Write-Warning "$Folder is not a git repo - agy's safety checkpoints will report 'checkpoint=none'."
}

# 1) agy in a detached psmux session at $Folder (idempotent: reuse if already up)
& $psmux has-session -t $session 2>$null
if ($LASTEXITCODE -ne 0) {
    & $psmux new-session -d -s $session -c $Folder
    & $psmux send-keys -t $session "agy $agyArgs" Enter
    Write-Host "agy starting in psmux '$session' at $Folder  (watch: $psmux attach -t $session)"
} else {
    Write-Host "psmux '$session' already running - reusing it"
}

# 2) Claude Code in the same folder (foreground), forwarding any extra flags
Set-Location $Folder
if ($ClaudeArgs.Count) { Write-Host "launching: claude $($ClaudeArgs -join ' ')" }
claude @ClaudeArgs

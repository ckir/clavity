#!/usr/bin/env bash
# Copyright (c) 2026 Costas Kirgoussios
#
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# You may obtain a copy of the License at:
# https://polyformproject.org/licenses/noncommercial/1.0.0/

# clavity-ls launcher, shared library (plugin-shipped, dotnet-only).
# Dot-sourced by fetch-clavity-ls.sh (SessionStart) and run standalone by install.sh:
#     bash clavity-ls-launcher-lib.sh TARGET BIN_DIR [VER]
#
# The plugin's MCP server launches ${CLAUDE_PLUGIN_DATA}/bin/clavity-ls.exe by its full path, but a person typing
# `clavity-ls` in a new terminal needs it on PATH. This keeps a launcher there:
#   Linux/macOS : a symlink ~/.local/bin/clavity-ls -> TARGET (the plain name; the .exe suffix is cosmetic there).
#   Windows     : (git-bash, OSTYPE msys*/cygwin*) BIN_DIR appended to the USER PATH (HKCU) through powershell.exe.
#                 The native name is already clavity-ls.exe, so no copy or shim.
#
# clavity_ls_launcher_ensure TARGET BIN_DIR VER returns
#   0  a new terminal will resolve clavity-ls (or the step was skipped on purpose),
#   3  the launcher is in place but its directory is not on PATH,
#   2  it could not be placed.
# Opt-outs: CLAVITY_SKIP_PATH=1 (this run only) and the marker file BIN_DIR/.no-launcher (durable; the user creates it).
#
# STEADY STATE SPAWNS NOTHING. This runs on every session start, so the "already right" checks are bash builtins only
# ([ -L ], [ -ef ], case, parameter expansion, an IFS=: loop): no readlink, dirname, grep, tr, sed, cygpath or
# powershell.exe until something actually has to change. The spawn-budget row for fetch-clavity-ls.sh pins that at 0.
#
# Every message is a msg*= assignment at the start of its own line (the shape scripts/check-injected-context.ps1
# extracts), then passed to _launcher_say. The caller may define _launcher_say before sourcing (the hook routes it to
# its JSON _say); otherwise the default below prints to stderr.
#
# FAIL-OPEN like the hooks: no set -e, nothing here exits a sourcing caller.

declare -F _launcher_say >/dev/null || _launcher_say() { printf '%s\n' "$1" >&2; }

# Normalise a directory for comparison, into the global _cll_n: forward slashes, lower case (Windows paths are
# case-insensitive), C:/... and /cygdrive/c/... folded to /c/..., trailing slashes dropped. Accepts BOTH the C:\... and
# the /c/... spelling, because the form Claude Code hands CLAUDE_PLUGIN_DATA to git-bash has not been measured yet.
_clavity_ls_launcher_norm() {
  local x=${1//\\//}
  x=${x,,}
  case "$x" in
    [a-z]:|[a-z]:/*) x="/${x:0:1}${x:2}" ;;
    /cygdrive/[a-z]|/cygdrive/[a-z]/*) x=${x#/cygdrive} ;;
  esac
  while [ "${#x}" -gt 1 ] && [ "${x%/}" != "$x" ]; do x=${x%/}; done
  _cll_n=$x
}

_clavity_ls_launcher_windows() {
  local bin_dir="$1" want e hit= nof= msg win ps_script
  _clavity_ls_launcher_norm "$bin_dir"; want=$_cll_n
  # Split $PATH with IFS=: and globbing OFF (a PATH entry holding * or ? must not expand); restore -f as found.
  case $- in *f*) nof=1 ;; esac
  set -f
  local IFS=:
  for e in $PATH; do
    _clavity_ls_launcher_norm "$e"
    [ "$_cll_n" = "$want" ] && { hit=1; break; }
  done
  [ -n "$nof" ] || set +f
  [ -n "$hit" ] && return 0

  # Not on PATH: from here on, processes are allowed (this runs once, then the steady state above takes over).
  if ! command -v powershell.exe >/dev/null 2>&1; then
    msg="[clavity-ls] powershell.exe not found, so $bin_dir was not added to your user PATH; add it yourself, then open a new terminal"
    _launcher_say "$msg"
    return 2
  fi
  win=$(cygpath -w "$bin_dir" 2>/dev/null)
  if [ -z "$win" ]; then
    msg="[clavity-ls] could not convert $bin_dir to a Windows path (cygpath), so it was not added to your user PATH; add it yourself"
    _launcher_say "$msg"
    return 2
  fi
  # One PowerShell string. The user PATH is read and written through [Environment] - never setx, which truncates the
  # value at 1024 characters. Append only when no entry equals the dir case-insensitively (a trailing backslash
  # ignored), keeping the existing value as it is. The dir goes in a single-quoted PowerShell literal: ' is doubled.
  win=${win//\'/\'\'}
  ps_script="\$ErrorActionPreference = 'Stop'; \$d = '$win'; "
  ps_script+="\$p = [Environment]::GetEnvironmentVariable('Path','User'); "
  ps_script+="\$e = @(if (\$p) { \$p -split ';' }); "
  ps_script+="if (-not (\$e | Where-Object { \$_.TrimEnd('\\') -ieq \$d.TrimEnd('\\') })) { "
  ps_script+="\$new = if (\$p) { \$p.TrimEnd(';') + ';' + \$d } else { \$d }; "
  ps_script+="[Environment]::SetEnvironmentVariable('Path', \$new, 'User') }"
  if ! powershell.exe -NoProfile -NonInteractive -Command "$ps_script" >/dev/null 2>&1; then
    msg="[clavity-ls] powershell.exe could not add $win to your user PATH; add it yourself, then open a new terminal"
    _launcher_say "$msg"
    return 2
  fi
  msg="[clavity-ls] added $win to your user PATH; a new terminal will find clavity-ls"
  _launcher_say "$msg"
  return 0
}

_clavity_ls_launcher_unix() {
  local target="$1" bin_dir="$2" ver="$3" msg dir link stamp
  if [ -z "${HOME:-}" ]; then
    msg="[clavity-ls] HOME is not set, so no launcher was placed; run $target directly"
    _launcher_say "$msg"
    return 2
  fi
  dir="$HOME/.local/bin"
  link="$dir/clavity-ls"
  # -ef follows the link and compares inodes: false for a dangling link and for a link into another data dir
  # (another profile, an older install), so both are recreated below. Builtins only.
  if [ -L "$link" ] && [ "$link" -ef "$target" ]; then
    :
  elif [ -e "$link" ] && [ ! -L "$link" ]; then
    # Somebody else's file (a hand-placed binary, a wrapper script). Never replace it.
    msg="[clavity-ls] $link exists and is not a clavity link, so it was left alone; remove it to let clavity manage it"
    _launcher_say "$msg"
    return 2
  elif [ ! -f "$target" ]; then
    msg="[clavity-ls] $target does not exist, so no launcher was placed"
    _launcher_say "$msg"
    return 2
  else
    # -f because a plain ln -s fails with "Already exists" on a dangling link; -n so a link to a directory is
    # replaced, not followed.
    if ! { mkdir -p "$dir" && ln -sfn "$target" "$link"; } 2>/dev/null; then
      msg="[clavity-ls] could not create $link; link it to $target yourself"
      _launcher_say "$msg"
      return 2
    fi
  fi
  case ":$PATH:" in
    *":$dir:"*|*":$dir/:"*) return 0 ;;
  esac
  # Once per version, not on every session start: the stamp sits beside the version stamp and is checked with [ -f ].
  stamp="$bin_dir/.path-note.$ver"
  if [ ! -f "$stamp" ]; then
    msg="[clavity-ls] $link is in place but $dir is NOT on PATH; add this line to your shell profile, then open a new terminal: export PATH=\"\$HOME/.local/bin:\$PATH\""
    _launcher_say "$msg"
    : 2>/dev/null > "$stamp"
  fi
  return 3
}

clavity_ls_launcher_ensure() {
  local target="${1:-}" bin_dir="${2:-}" ver="${3:-}" msg
  if [ -z "$target" ] || [ -z "$bin_dir" ]; then
    msg="[clavity-ls] launcher: usage: clavity_ls_launcher_ensure TARGET BIN_DIR [VER]"
    _launcher_say "$msg"
    return 2
  fi
  if [ "${CLAVITY_SKIP_PATH:-}" = 1 ]; then
    msg="[clavity-ls] PATH launcher skipped (CLAVITY_SKIP_PATH=1); clavity-ls stays at $target"
    _launcher_say "$msg"
    return 0
  fi
  if [ -e "$bin_dir/.no-launcher" ]; then
    msg="[clavity-ls] PATH launcher skipped: $bin_dir/.no-launcher exists; clavity-ls stays at $target"
    _launcher_say "$msg"
    return 0
  fi
  case "${OSTYPE:-}" in
    msys*|cygwin*) _clavity_ls_launcher_windows "$bin_dir" ;;
    *)             _clavity_ls_launcher_unix "$target" "$bin_dir" "$ver" ;;
  esac
}

# Standalone (install.sh): run the function and exit with its code. Sourced, BASH_SOURCE[0] is this file and $0 the
# caller, so nothing below runs.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  clavity_ls_launcher_ensure "$@"
  exit $?
fi

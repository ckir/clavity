#!/usr/bin/env bash
# Copyright (c) 2026 Costas Kirgoussios
#
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# You may obtain a copy of the License at:
# https://polyformproject.org/licenses/noncommercial/1.0.0/

# clavity install, runnable by a person or by their coding agent:
#     curl -fsSL https://raw.githubusercontent.com/ckir/clavity/main/install.sh | bash -s --
#     install.sh [--with agy-autotrain,commonmemory,review-relay] [--all] [--dry-run] [--no-launcher] [--launcher]
#
# Steps (spec 2026-11-10-agent-install-design.md, section 2), each idempotent and reported on one line:
#   1. preconditions: claude, curl, tar, sha256sum or shasum
#   2. the clavity and superpowers marketplaces
#   3. superpowers, clavity@clavity and the chosen add-ons (claude plugin install <id> -y --scope user)
#   4. the plugin's fetch hook, run by hand so clavity-ls lands now; then the agy registration when agy is on PATH
#   5. the PATH launcher, through clavity-ls-launcher-lib.sh fetched from this repository's main branch
#   6. verify, in two tiers: hard checks (exit 2) and the resolution check (exit 3, never 2)
#   7. the launch line, printed LAST (on exit 2 the last line says clavity is NOT installed instead, and there is no
#      launch line)
# Exit codes: 0 done and clavity-ls resolves in new terminals, 1 precondition missing or bad argument, 2 the binary does
# not run or clavity@clavity is not enabled, 3 done but clavity-ls is NOT on PATH yet (the status and launch lines say
# what to do; an agent must not report plain success on 3).
#
# Environment: CLAUDE_CONFIG_DIR (default ~/.claude), CLAVITY_SKIP_PATH=1 (skip the launcher step this run),
# CLAVITY_SKIP_AGY=1 (skip the agy registration), CLAVITY_INSTALL_LIB (a local launcher lib: no fetch),
# CLAVITY_INSTALL_RAW_BASE (default https://raw.githubusercontent.com/ckir/clavity/main).
#
# Every message of this script is one line on stdout, prefixed [clavity install]; the last line is the closing message,
# verbatim: the launch line on 0 and 3, the NOT-installed line on 2. The fetch hook's stderr passes through untouched and its stdout (hook JSON) is discarded.
#
# The whole body is functions; the only top-level command is `main "$@"` on the LAST line, so a download truncated by
# a dropped connection runs nothing. No set -e: the script decides its own exit codes.
set -u

say() { printf '[clavity install] %s\n' "$1"; }
# A hard-check failure: on stdout like every message, and on stderr so "which one" is there too.
fail() { say "FAILED: $1"; printf '[clavity install] FAILED: %s\n' "$1" >&2; }
usage() {
  say "${1:+$1; }usage: install.sh [--with agy-autotrain,commonmemory,review-relay] [--all] [--dry-run] [--no-launcher] [--launcher]"
}

# Normalise a Windows directory for comparison into _n: forward slashes, lower case, C:/... and /cygdrive/c/... folded
# to /c/..., trailing slashes dropped (the same rule as clavity-ls-launcher-lib.sh).
_norm() {
  local x=${1//\\//}
  x=${x,,}
  case "$x" in
    [a-z]:|[a-z]:/*) x="/${x:0:1}${x:2}" ;;
    /cygdrive/[a-z]|/cygdrive/[a-z]/*) x=${x#/cygdrive} ;;
  esac
  while [ "${#x}" -gt 1 ] && [ "${x%/}" != "$x" ]; do x=${x%/}; done
  _n=$x
}

# The text of the object whose "id" is $1 in $2 (a `claude plugin list --json` listing), into _obj. `id` is the FIRST
# key of every object, so the object runs from its id to the next "id". No brace matching: the clavity object nests
# mcpServers{...}, which a [^{}]* match cannot cross.
_obj_of() {
  local rest
  _obj=
  [[ $2 =~ \"id\"[[:space:]]*:[[:space:]]*\""$1"\"(.*) ]] || return 1
  rest=${BASH_REMATCH[1]}
  _obj=${rest%%\"id\"*}
  return 0
}
_enabled() { _obj_of "$1" "$PLUGINS_JSON" && [[ $_obj =~ \"enabled\"[[:space:]]*:[[:space:]]*true ]]; }
# The first ENABLED id starting with $1, into _found.
_enabled_prefix() {
  local rest=$PLUGINS_JSON id obj
  _found=
  while [[ $rest =~ \"id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"(.*) ]]; do
    id=${BASH_REMATCH[1]}; rest=${BASH_REMATCH[2]}; obj=${rest%%\"id\"*}
    case "$id" in
      "$1"*) if [[ $obj =~ \"enabled\"[[:space:]]*:[[:space:]]*true ]]; then _found=$id; return 0; fi ;;
    esac
  done
  return 1
}
_has_repo() { [[ $MARKETS_JSON =~ \"repo\"[[:space:]]*:[[:space:]]*\""$1"\" ]]; }
# Runs a claude command, quiet on success; on failure a WARNING carrying its last output line. Returns its code.
_claude() {
  local out rc last
  out=$(claude "$@" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    out=${out//$'\r'/}; last=${out##*$'\n'}
    say "WARNING: claude $* failed (exit $rc)${last:+: $last}"
  fi
  return "$rc"
}

parse_args() {
  local a
  WITH=; ALL=; DRY_RUN=; LAUNCHER_MODE=; ADDONS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --with) [ $# -ge 2 ] || { usage "--with needs a value"; return 1; }; WITH=$2; shift 2 ;;
      --with=*) WITH=${1#--with=}; shift ;;
      --all) ALL=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --no-launcher) [ "$LAUNCHER_MODE" = yes ] && { usage "--no-launcher and --launcher together"; return 1; }; LAUNCHER_MODE=no; shift ;;
      --launcher) [ "$LAUNCHER_MODE" = no ] && { usage "--no-launcher and --launcher together"; return 1; }; LAUNCHER_MODE=yes; shift ;;
      *) usage "unknown argument '$1'"; return 1 ;;
    esac
  done
  if [ -n "$ALL" ]; then
    ADDONS=(agy-autotrain commonmemory review-relay)
  elif [ -n "$WITH" ]; then
    local IFS=,
    for a in $WITH; do
      case "$a" in
        agy-autotrain|commonmemory|review-relay)
          case " ${ADDONS[*]:-} " in *" $a "*) ;; *) ADDONS+=("$a") ;; esac ;;
        '') ;;
        *) usage "unknown add-on '$a'"; return 1 ;;
      esac
    done
  fi
  return 0
}

preconditions() {
  local miss=0
  command -v claude >/dev/null 2>&1 || { say "missing: claude (Claude Code, https://docs.claude.com/en/docs/claude-code); install it, then run this again"; miss=1; }
  command -v curl >/dev/null 2>&1 || { say "missing: curl; install it, then run this again"; miss=1; }
  command -v tar >/dev/null 2>&1 || { say "missing: tar; install it, then run this again"; miss=1; }
  command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 \
    || { say "missing: sha256sum or shasum; install one, then run this again"; miss=1; }
  return "$miss"
}

ensure_marketplaces() {
  if [ -n "$DRY_RUN" ]; then
    say "dry-run: claude plugin marketplace list --json"
    say "dry-run: claude plugin list --json"
    say "dry-run: claude plugin marketplace add ckir/clavity   (when no marketplace has repo ckir/clavity)"
    say "dry-run: claude plugin marketplace add obra/superpowers-marketplace   (when absent and no superpowers@* plugin is enabled)"
    return 0
  fi
  MARKETS_JSON=$(claude plugin marketplace list --json 2>/dev/null) || MARKETS_JSON=
  PLUGINS_JSON=$(claude plugin list --json 2>/dev/null) || PLUGINS_JSON=
  if _has_repo ckir/clavity; then
    say "marketplace ckir/clavity already added"
  elif _claude plugin marketplace add ckir/clavity; then
    say "added marketplace ckir/clavity"
  fi
  if _has_repo obra/superpowers-marketplace; then
    say "marketplace obra/superpowers-marketplace already added"
  elif _enabled_prefix 'superpowers@'; then
    say "superpowers is already enabled ($_found), so its marketplace is not needed"
  elif _claude plugin marketplace add obra/superpowers-marketplace; then
    say "added marketplace obra/superpowers-marketplace"
  fi
  return 0
}

ensure_plugins() {
  local ids=() id a installed=
  if [ -n "$DRY_RUN" ] || ! _enabled_prefix 'superpowers@'; then
    ids+=(superpowers@superpowers-marketplace)
  else
    say "superpowers already installed ($_found)"
  fi
  ids+=(clavity@clavity)
  for a in "${ADDONS[@]+"${ADDONS[@]}"}"; do ids+=("$a@clavity"); done
  for id in "${ids[@]}"; do
    if [ -n "$DRY_RUN" ]; then
      say "dry-run: claude plugin install $id -y --scope user   (when $id is not already enabled)"
    elif _enabled "$id"; then
      say "$id already installed"
    elif _claude plugin install "$id" -y --scope user; then
      say "installed $id"; installed=1
    fi
  done
  for a in "${ADDONS[@]+"${ADDONS[@]}"}"; do
    case "$a" in
      commonmemory) say "note: commonmemory needs the @agentmemory/agentmemory npm package, which this script does not install" ;;
      review-relay) say "note: review-relay needs the AiSaveDev browser extension, which this script does not install" ;;
    esac
  done
  if [ -n "$installed" ]; then
    PLUGINS_JSON=$(claude plugin list --json 2>/dev/null) || PLUGINS_JSON=
  fi
  return 0
}

locate_plugin() {
  local p
  ROOT=; VERSION=
  if [ -n "$DRY_RUN" ]; then
    ROOT='<installPath>'; VERSION='<version>'
    say "dry-run: read installPath and version of clavity@clavity from claude plugin list --json"
    return 0
  fi
  if ! _obj_of clavity@clavity "$PLUGINS_JSON"; then
    say "WARNING: clavity@clavity is not in claude plugin list --json, so the fetch hook cannot run"
    return 1
  fi
  [[ $_obj =~ \"installPath\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && p=${BASH_REMATCH[1]} || p=
  [[ $_obj =~ \"version\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && VERSION=${BASH_REMATCH[1]}
  # JSON-unescape: \\ -> \ and \/ -> /, the \\ pairs parked on \001 first so `\\/` stays `\` + `/`.
  p=${p//\\\\/$'\001'}
  p=${p//\\\//\/}
  ROOT=${p//$'\001'/\\}
  if [ -z "$ROOT" ]; then
    say "WARNING: clavity@clavity has no installPath in claude plugin list --json, so the fetch hook cannot run"
    return 1
  fi
  say "clavity@clavity ${VERSION:-(no version)} at $ROOT"
  return 0
}

run_hook() {
  local hook
  HOOK_MSG=
  if [ -n "$DRY_RUN" ]; then
    case "$LAUNCHER_MODE" in
      no) say "dry-run: create $BIN_DIR/.no-launcher" ;;
      yes) say "dry-run: rm -f $BIN_DIR/.no-launcher" ;;
    esac
    say "dry-run: rm -f $BIN_DIR/.clavity-ls.version.fail"
    say "dry-run: CLAUDE_PLUGIN_ROOT=\"$ROOT\" CLAUDE_PLUGIN_DATA=\"$DATA\" bash \"$ROOT/hooks/fetch-clavity-ls.sh\" >/dev/null"
    return 0
  fi
  mkdir -p "$BIN_DIR" 2>/dev/null
  # The marker goes in BEFORE the hook runs: the hook places the launcher itself on success.
  case "$LAUNCHER_MODE" in
    no) : 2>/dev/null > "$BIN_DIR/.no-launcher" \
          && say "wrote $BIN_DIR/.no-launcher: the PATH launcher stays off (install.sh --launcher turns it back on)" ;;
    yes) if [ -e "$BIN_DIR/.no-launcher" ]; then
           rm -f "$BIN_DIR/.no-launcher" && say "removed $BIN_DIR/.no-launcher: the PATH launcher is on again"
         fi ;;
  esac
  [ -n "$ROOT" ] || return 1
  # A failed fetch within the last 10 minutes would otherwise make the hook return at once.
  rm -f "$BIN_DIR/.clavity-ls.version.fail" 2>/dev/null
  export CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PLUGIN_DATA="$DATA"
  hook="$ROOT/hooks/fetch-clavity-ls.sh"
  if [ ! -f "$hook" ]; then
    HOOK_MSG="$hook does not exist"
    say "WARNING: the fetch hook $hook does not exist"
    return 1
  fi
  say "running the plugin's fetch hook (downloads clavity-ls now)"
  # stderr is captured to repeat it on a failure, and printed as it was; stdout (hook JSON) is discarded.
  HOOK_MSG=$(bash "$hook" 2>&1 >/dev/null)
  [ -n "$HOOK_MSG" ] && printf '%s\n' "$HOOK_MSG" >&2
  HOOK_MSG=${HOOK_MSG//$'\r'/}
  HOOK_MSG=${HOOK_MSG//$'\n'/ / }
  return 0
}

register_agy() {
  local ver='' re_ver l
  if [ "${CLAVITY_SKIP_AGY:-}" = 1 ]; then
    say "agy registration skipped (CLAVITY_SKIP_AGY=1)"
    return 0
  fi
  if ! command -v agy >/dev/null 2>&1; then
    say "agy is not on PATH; the plugin registers itself with agy at the first Claude Code session start"
    return 0
  fi
  if [ -n "$DRY_RUN" ]; then
    say "dry-run: agy plugin uninstall clavity"
    say "dry-run: agy plugin install \"$ROOT\""
    return 0
  fi
  [ -n "$ROOT" ] || return 0
  # The pair and the stamp exactly as clavity-dotnet-setup.sh does at session start, so that hook sees it as done.
  agy plugin uninstall clavity >/dev/null 2>&1
  if agy plugin install "$ROOT" >/dev/null 2>&1; then
    if [ -f "$ROOT/plugin.json" ]; then
      re_ver='.*"version"[[:space:]]*:[[:space:]]*"([^"]*)"'
      while IFS= read -r l || [ -n "$l" ]; do
        if [[ $l =~ $re_ver ]]; then ver=${BASH_REMATCH[1]}; break; fi
      done 2>/dev/null < "$ROOT/plugin.json"
    fi
    printf '%s' "$ver" 2>/dev/null > "$DATA/.agy-registered"
    rm -f "$DATA/.agy-register-failed" 2>/dev/null
    say "registered the plugin with agy (agy plugin install)"
  else
    say "WARNING: could not register the plugin with agy - to pair, run once: agy plugin install \"$ROOT\""
  fi
  return 0
}

run_launcher() {
  local url lib
  LAUNCHER_SKIP=
  if [ "${CLAVITY_SKIP_PATH:-}" = 1 ]; then
    LAUNCHER_SKIP='env'
    say "PATH launcher step skipped (CLAVITY_SKIP_PATH=1)"
    return 0
  fi
  if [ "$LAUNCHER_MODE" = no ] || { [ "$LAUNCHER_MODE" != yes ] && [ -e "$BIN_DIR/.no-launcher" ]; }; then
    LAUNCHER_SKIP=marker
    say "PATH launcher step skipped: $BIN_DIR/.no-launcher exists"
    return 0
  fi
  url="${CLAVITY_INSTALL_RAW_BASE:-https://raw.githubusercontent.com/ckir/clavity/main}/clavity-dotnet/plugin/hooks/clavity-ls-launcher-lib.sh"
  if [ -n "${CLAVITY_INSTALL_LIB:-}" ]; then
    lib=$CLAVITY_INSTALL_LIB
  elif [ -n "$DRY_RUN" ]; then
    lib='<tmpdir>/clavity-ls-launcher-lib.sh'
    say "dry-run: curl -fsSL \"$url\" -o \"$lib\""
  else
    TMPD=$(mktemp -d 2>/dev/null) || TMPD=
    lib="${TMPD:-/nonexistent}/clavity-ls-launcher-lib.sh"
    if [ -z "$TMPD" ] || ! curl -fsSL "$url" -o "$lib" 2>/dev/null; then
      rm -f "$lib" 2>/dev/null
      LAUNCHER_SKIP=fetch
      say "WARNING: could not fetch $url, so the PATH launcher step was skipped"
      return 0
    fi
  fi
  if [ -n "$DRY_RUN" ]; then
    say "dry-run: bash \"$lib\" \"$TARGET\" \"$BIN_DIR\" \"$VERSION\""
    return 0
  fi
  if [ ! -f "$lib" ]; then
    LAUNCHER_SKIP=fetch
    say "WARNING: the launcher library $lib does not exist, so the PATH launcher step was skipped"
    return 0
  fi
  # The lib speaks for itself on stderr. verify does not trust its code: it checks what a new terminal will see.
  bash "$lib" "$TARGET" "$BIN_DIR" "$VERSION"
  return 0
}

verify() {
  local hard=0 dir link why='' what win up e want hit='' IFS
  LAUNCH_CMD="clavity-ls start $FOLDER"
  if [ -n "$DRY_RUN" ]; then
    say "dry-run: $TARGET --version"
    say "dry-run: claude plugin list --json   (clavity@clavity must be enabled)"
    return 0
  fi
  # Tier 1, hard checks (exit 2). The binary by its data path: this shell's PATH may predate any PATH edit.
  if ! "$TARGET" --version >/dev/null 2>&1; then
    fail "$TARGET --version did not run (the hook or launcher said: ${HOOK_MSG:-nothing})"
    hard=1
  fi
  PLUGINS_JSON=$(claude plugin list --json 2>/dev/null) || PLUGINS_JSON=
  if ! _enabled clavity@clavity; then
    fail "clavity@clavity is not enabled in claude plugin list --json (run: claude plugin install clavity@clavity -y --scope user)"
    hard=1
  fi
  [ "$hard" -eq 0 ] || return 2

  # Tier 2, resolution (exit 3, never 2): will a NEW terminal resolve clavity-ls?
  case "$LAUNCHER_SKIP" in
    'env') why="the PATH launcher step was skipped (CLAVITY_SKIP_PATH=1)" ;;
    marker) why="the PATH launcher is off because $BIN_DIR/.no-launcher exists (install.sh --launcher removes it)" ;;
    fetch) why="the launcher library could not be fetched" ;;
  esac
  case "${OSTYPE:-}" in
    msys*|cygwin*)
      win=$(cygpath -w "$BIN_DIR" 2>/dev/null) || win=
      win=${win//$'\r'/}; win=${win//$'\n'/}
      [ -n "$win" ] || win=${BIN_DIR//\//\\}
      # The USER PATH from the registry, never this git-bash's $PATH: it cannot see a change made during its lifetime.
      up=$(powershell.exe -NoProfile -NonInteractive -Command "[Environment]::GetEnvironmentVariable('Path','User')" 2>/dev/null) || up=
      up=${up//$'\r'/}; up=${up//$'\n'/}
      _norm "$win"; want=$_n
      set -f
      IFS=';'
      for e in $up; do
        _norm "$e"
        [ "$_n" = "$want" ] && { hit=1; break; }
      done
      set +f
      unset IFS
      if [ -n "$hit" ]; then
        say "clavity-ls will resolve in new terminals (open a new console window, not a new tab inside an editor whose terminal was already open: that tab inherits the editor's environment)"
        return 0
      fi
      what="add $win to your user PATH (Edit environment variables for your account), then open a new console window"
      say "clavity-ls is NOT on PATH yet: ${why:+$why; }$what"
      LAUNCH_CMD="& \"$win\\clavity-ls.exe\" start $FOLDER"
      return 3 ;;
  esac
  dir="$HOME/.local/bin"
  link="$dir/clavity-ls"
  if [ -L "$link" ] && [ "$link" -ef "$TARGET" ]; then
    case ":$PATH:" in
      *":$dir:"*|*":$dir/:"*)
        say "clavity-ls will resolve in new terminals"
        return 0 ;;
    esac
    say "clavity-ls is NOT on PATH yet: ${why:+$why; }add this line to your shell profile, then open a new terminal: export PATH=\"\$HOME/.local/bin:\$PATH\""
    LAUNCH_CMD="export PATH=\"\$HOME/.local/bin:\$PATH\"; clavity-ls start $FOLDER"
    return 3
  fi
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    say "clavity-ls is NOT on PATH yet: $link is your own file, not clavity's launcher; remove it and run this again, or use the launch line below"
  elif [ -L "$link" ]; then
    say "clavity-ls is NOT on PATH yet: ${why:+$why; }$link points elsewhere; relink it (ln -sfn \"$TARGET\" \"$link\") or use the launch line below"
  else
    [ -n "$why" ] || why="the launcher step did not place $link (see the [clavity-ls] note above)"
    say "clavity-ls is NOT on PATH yet: $why, so there is no $link; link it yourself (ln -s \"$TARGET\" \"$link\") or use the launch line below"
  fi
  LAUNCH_CMD="export PATH=\"$BIN_DIR:\$PATH\"; clavity-ls.exe start $FOLDER"
  return 3
}

launch_line() {
  printf '%s\n' "If Claude Code or agy is already running in this folder, exit them first. Then open a new terminal and run: ${LAUNCH_CMD:-clavity-ls start $FOLDER}"
}

main() {
  local rc
  # Under `curl | bash` stdin is this script: no child may read it.
  exec </dev/null
  parse_args "$@" || exit 1
  preconditions || exit 1
  CONFIG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  DATA="$CONFIG/plugins/data/clavity-clavity"
  BIN_DIR="$DATA/bin"
  TARGET="$BIN_DIR/clavity-ls.exe"
  MARKETS_JSON=; PLUGINS_JSON=; ROOT=; VERSION=; HOOK_MSG=; LAUNCHER_SKIP=; LAUNCH_CMD=; TMPD=
  FOLDER=$(git rev-parse --show-toplevel 2>/dev/null) || FOLDER=
  [ -n "$FOLDER" ] || FOLDER='<folder>'
  case "$FOLDER" in *[[:space:]]*) FOLDER="\"$FOLDER\"" ;; esac
  trap '[ -n "${TMPD:-}" ] && rm -rf "$TMPD"' EXIT
  ensure_marketplaces
  ensure_plugins
  locate_plugin
  run_hook
  register_agy
  run_launcher
  verify; rc=$?
  if [ "$rc" -eq 2 ]; then
    # Nothing to launch: the closing line says so instead, and is the LAST line.
    say "clavity is NOT installed: fix the FAILED line above, then run this again"
  else
    launch_line
  fi
  exit "$rc"
}

main "$@"

#!/usr/bin/env bash
# agy-consult VCS-diff guard, PRE half.
# PreToolUse(Bash|PowerShell|<agy_ask MCP>): snapshot a VCS baseline for a consult so POST can
# detect a mutation. Silent (emits nothing). Fail-open: any error -> exit 0.
#   sync  -> write the .sync  baseline FRESH each call (Pre/Post bracket a blocking consult)
#   open  -> write the .async baseline IF-NONE (preserve the oldest in-flight; overwrite only if
#            stale). Favors DETECTION: never drop an in-flight mutation across multi-message async.
#   term. -> no-op (its baseline was written by the matching open)
set +e
# Process budget (every process costs ~200 ms on Windows): read stdin with the builtin, and bail out
# on the RAW JSON text before sourcing the lib or starting jq. A consult is either the MCP tool
# (tool_name ends in agy_ask) or a command naming `clavity` then ask|send|await-reply. In the JSON
# text the separator between the words is whitespace or a JSON escape (\n \t \r \f \u000b); this
# regex is a SUPERSET of agy_guard_category's command-position match (it drops the anchor and the
# trailing-boundary test), so a prefilter miss can never be a consult.
# (read -N, looped to EOF: `read -d ''` on a pipe is one syscall per byte and measured ~6x slower
# than $(cat) on a 100 KB payload; -N reads in chunks.)
input=; while IFS= read -r -N 1048576 chunk 2>/dev/null; do input+=$chunk; done; input+=$chunk
shopt -s nocasematch   # Windows runs CLAVITY / Clavity.EXE as clavity (Branch 20 panel R1)
if [[ $input != *agy_ask* ]]; then
  re='clavity(\.exe)?([[:space:]]|\\[ntrf]|\\u[0-9a-fA-F]{4})+(ask|send|await-reply)'
  [[ $input =~ $re ]] || exit 0
fi
command -v jq >/dev/null 2>&1 || exit 0

# shellcheck source=agy-consult-guard-lib.sh
d=${0%[/\\]*}; [ "$d" = "$0" ] && d=.; [ -z "$d" ] && d=/
. "$d/agy-consult-guard-lib.sh" 2>/dev/null || exit 0

# ONE jq call for all four fields, NUL-terminated and read with the builtin. Each field keeps the
# value the old per-field `$(jq -r ...)` produced: `?` makes a non-object tool_input yield "" for
# the command only (as the failing per-field call did), and trailing newlines are stripped per
# field below, as command substitution did.
{ IFS= read -r -d '' tool; IFS= read -r -d '' cmd; IFS= read -r -d '' cwd; IFS= read -r -d '' sid; } < <(
  jq -j '(.tool_name // ""), "\u0000", (.tool_input.command? // ""), "\u0000", (.cwd // "."), "\u0000", (.session_id // "default"), "\u0000"' <<<"$input" 2>/dev/null)
tool=${tool%"${tool##*[!$'\n']}"}; cmd=${cmd%"${cmd##*[!$'\n']}"}
cwd=${cwd%"${cwd##*[!$'\n']}"};   sid=${sid%"${sid##*[!$'\n']}"}
[ -z "$sid" ] && sid=default
# tr -c 'A-Za-z0-9_-' '_' is byte-wise; the C locale makes the expansion byte-wise too.
_o=${LC_ALL-}; _s=${LC_ALL+x}; LC_ALL=C
sid=${sid//[^A-Za-z0-9_-]/_}
if [ -n "$_s" ]; then LC_ALL=$_o; else unset LC_ALL; fi

# Second prefilter, on the DECODED command: agy_guard_category costs 10 processes (a subshell plus
# three printf|grep pipelines). Skip it unless the command could match its anchor - same anchor as
# the lib (line start, a newline, or ; & |, optional path prefix, clavity[.exe], whitespace) followed
# by ask|send|await-reply, minus the trailing-boundary test, so it is a superset of every grep there.
if [[ $tool != *agy_ask ]]; then
  _nl=$'\n'
  pfx="(^|[;&|${_nl}])[[:space:]]*([[:graph:]]*[/\\\\])?clavity(\\.exe)?[[:space:]]+"
  re="${pfx}(ask|send|await-reply)"
  [[ $cmd =~ $re ]] || exit 0
  # PRE is a no-op for a terminal (await-reply) call. If the await-reply superset matches and the
  # ask|send supersets do NOT, agy_guard_category cannot return sync/open (each needs an ask/send
  # match), so skip its 10 processes. Any command that could be sync/open still reaches the lib.
  re="${pfx}await-reply"; re2="${pfx}(ask|send)"
  if [[ $cmd =~ $re ]] && ! [[ $cmd =~ $re2 ]]; then exit 0; fi
fi

cat=$(agy_guard_category "$tool" "$cmd")
case "$cat" in
  sync)  slot=sync  ;;
  open)  slot=async ;;
  *)     exit 0      ;;   # terminal (baseline already set) or none
esac
agy_guard_in_git_repo "$cwd" || exit 0

sf=$(agy_guard_state_file "$sid" "$slot") || exit 0

# Async: preserve the OLDEST in-flight baseline (do not drop an in-flight mutation). Only the sync
# slot re-baselines every call. A stale async baseline is overwritten so it can't misattribute.
if [ "$slot" = async ] && [ -f "$sf" ] && [ -z "$(find "$sf" -mmin +"$AGY_GUARD_TTL_MIN" 2>/dev/null)" ]; then
  exit 0   # fresh open baseline exists -> keep it
fi

quad=$(agy_guard_quad "$cwd")
tmp="$sf.tmp.$$"
printf '%s\n' "$quad" 2>/dev/null > "$tmp" && mv -f "$tmp" "$sf" 2>/dev/null
exit 0

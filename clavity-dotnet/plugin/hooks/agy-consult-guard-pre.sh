#!/usr/bin/env bash
# agy-consult VCS-diff guard, PRE half.
# PreToolUse(Bash|PowerShell|<agy_ask MCP>): snapshot a VCS baseline for a consult so POST can
# detect a mutation. Silent (emits nothing). Fail-open: any error -> exit 0.
#   sync  -> write the .sync  baseline FRESH each call (Pre/Post bracket a blocking consult)
#   open  -> write the .async baseline IF-NONE (preserve the oldest in-flight; overwrite only if
#            stale). Favors DETECTION: never drop an in-flight mutation across multi-message async.
#   term. -> no-op (its baseline was written by the matching open)
set +e
input=$(cat 2>/dev/null)
command -v jq >/dev/null 2>&1 || exit 0

# shellcheck source=agy-consult-guard-lib.sh
. "$(dirname "$0")/agy-consult-guard-lib.sh" 2>/dev/null || exit 0

tool=$(printf '%s' "$input" | jq -r '.tool_name // ""'          2>/dev/null)
cmd=$( printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)
cwd=$( printf '%s' "$input" | jq -r '.cwd // "."'               2>/dev/null)
sid=$( printf '%s' "$input" | jq -r '.session_id // "default"'  2>/dev/null)
[ -z "$sid" ] && sid=default
sid=$(printf '%s' "$sid" | tr -c 'A-Za-z0-9_-' '_')

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
printf '%s\n' "$quad" > "$tmp" 2>/dev/null && mv -f "$tmp" "$sf" 2>/dev/null
exit 0

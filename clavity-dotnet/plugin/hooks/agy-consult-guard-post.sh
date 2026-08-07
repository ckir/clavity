#!/usr/bin/env bash
# agy-consult VCS-diff guard, POST half.
# PostToolUse(Bash|PowerShell|<agy_ask MCP>): if this consult has a baseline, diff it and warn
# LOUDLY on any delta. READ-ONLY: never reverts/stages/blocks. Fail-open. It never stays SILENT on
# a case that would leave the driver falsely confident - an inconclusive check warns too.
#   sync  -> compare+consume the .sync  baseline (precise); no baseline => Pre failed => warn
#   term. -> compare+consume the .async baseline (best-effort); stale => warn inconclusive
#   open  -> no-op (baseline set in Pre; nothing has run yet)
set +e
input=$(cat 2>/dev/null)
command -v jq >/dev/null 2>&1 || exit 0

# shellcheck source=agy-consult-guard-lib.sh
. "$(dirname "$0")/agy-consult-guard-lib.sh" 2>/dev/null || exit 0

emit(){ jq -nc --arg m "$1" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'; }

tool=$(printf '%s' "$input" | jq -r '.tool_name // ""'          2>/dev/null)
cmd=$( printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)
cwd=$( printf '%s' "$input" | jq -r '.cwd // "."'               2>/dev/null)
sid=$( printf '%s' "$input" | jq -r '.session_id // "default"'  2>/dev/null)
[ -z "$sid" ] && sid=default
sid=$(printf '%s' "$sid" | tr -c 'A-Za-z0-9_-' '_')

cat=$(agy_guard_category "$tool" "$cmd")
case "$cat" in
  sync)     slot=sync  ;;
  terminal) slot=async ;;
  *)        exit 0      ;;   # open (nothing yet) or none
esac
agy_guard_in_git_repo "$cwd" || exit 0

sf=$(agy_guard_state_file "$sid" "$slot") || exit 0

if [ ! -f "$sf" ]; then
  # A SYNC consult always has its Pre run first, so a missing baseline means Pre could not write
  # state (e.g. TMPDIR unwritable) -> warn rather than give false confidence. A terminal with no
  # baseline is legitimately ambiguous (no matching send) -> stay silent.
  if [ "$slot" = sync ]; then
    emit "AGY CONSULT GUARD - NOT VERIFIED (guard failed to initialize): no VCS baseline was captured for this review-only agy consult, because the Pre hook could not write its state file (e.g. an unwritable TMPDIR). This consult was therefore NOT checked for peer-made version-control changes - confirm manually that the peer changed nothing."
  fi
  exit 0
fi

# Async best-effort: a terminal firing long after its send is too stale to attribute -> warn
# inconclusive (do NOT silently pass, which would read as "verified clean").
if [ "$slot" = async ] && [ -n "$(find "$sf" -mmin +"$AGY_GUARD_TTL_MIN" 2>/dev/null)" ]; then
  rm -f "$sf" 2>/dev/null
  emit "AGY CONSULT GUARD - NOT VERIFIED (async baseline too stale): this asynchronous agy consult's VCS baseline is older than ${AGY_GUARD_TTL_MIN} min, too stale to attribute a change reliably, so it was NOT checked. Confirm manually that the peer made no version-control changes."
  exit 0
fi

# Degraded-guard: with no hashing tool, 4 of 7 axes collapse to a constant and would compare-equal
# silently. Fail LOUD instead of giving false confidence.
if ! agy_guard_have_hash; then
  rm -f "$sf" 2>/dev/null
  emit "AGY CONSULT GUARD - PARTIALLY VERIFIED (no hashing tool): neither sha256sum nor shasum is on PATH, so this review-only agy consult could NOT be checked for worktree / index / .git-metadata / refs changes (only HEAD and stash were compared). Do NOT trust the absence of a warning - manually confirm the peer made no version-control changes."
  exit 0
fi

before=$(cat "$sf" 2>/dev/null)
after=$(agy_guard_quad "$cwd")
rm -f "$sf" 2>/dev/null            # consume the baseline

[ "$before" = "$after" ] && exit 0   # clean: peer honored review-only

IFS='|' read -r b_head b_status b_diff b_stash b_refs b_meta b_flags <<EOF
$before
EOF
IFS='|' read -r a_head a_status a_diff a_stash a_refs a_meta a_flags <<EOF
$after
EOF
axes=""
[ "$b_head"   != "$a_head"   ] && axes="${axes}committed-HEAD (a commit landed); "
[ "$b_diff"   != "$a_diff"   ] && axes="${axes}staged/worktree diff; "
[ "$b_status" != "$a_status" ] && axes="${axes}worktree/untracked files; "
[ "$b_stash"  != "$a_stash"  ] && axes="${axes}stash (refs/stash moved); "
[ "$b_refs"   != "$a_refs"   ] && axes="${axes}other refs (tags/branches/notes moved); "
[ "$b_meta"   != "$a_meta"   ] && axes="${axes}.git hooks/config/exclude (ARBITRARY-CODE-EXEC or hide-file vector); "
[ "$b_flags"  != "$a_flags"  ] && axes="${axes}assume-unchanged/skip-worktree bits (hidden index smuggle); "
[ -z "$axes" ] && axes="VCS state; "

paths=$(git -C "$cwd" status --porcelain 2>/dev/null | head -20)
headmsg=""
if [ "$b_head" != "$a_head" ]; then
  headmsg=" New commit(s): $(git -C "$cwd" log --oneline "${b_head}..${a_head}" 2>/dev/null | head -5 | tr '\n' ';')"
fi

msg="AGY CONSULT GUARD - VERSION CONTROL CHANGED DURING A REVIEW-ONLY CONSULT: the agy peer appears to have modified git state during a consult that was supposed to make ZERO changes. What changed: ${axes}CAVEAT - this guard compares VCS state before and after the consult and CANNOT attribute a change to the peer rather than to anything else running in this repository at the same time. If you dispatched a local subagent, or another session is open on this repo, that is the likelier cause, and reverting would destroy its in-flight work. Next: verify the peer - not you, and not a concurrent local agent - made these changes; if so, undo them with a TARGETED per-file 'git checkout -- <file>' / 'git reset' (NEVER a broad 'git checkout <dir>/'), then re-issue the consult with a louder forbidden-actions banner. Changed paths:\n${paths}${headmsg}"
emit "$msg"
exit 0

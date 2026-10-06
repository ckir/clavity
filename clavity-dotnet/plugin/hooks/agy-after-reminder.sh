#!/usr/bin/env bash
# AGY-AFTER (plugin-shipped). PostToolUse(Write|Edit): when a SPEC or PLAN artifact is
# authored/edited (docs/superpowers/specs/** or docs/superpowers/plans/**), inject a
# reminder to route the FINISHED artifact through an adversarial panel BEFORE presenting
# it to the user - the complement to AGY-FIRST (forks). The full procedure lives in the
# `adversarial-panel-review` skill (this hook only POINTS at it; it never runs the panel).
# Ships with this driver's plugin, so it installs/uninstalls with the plugin and leaves
# no residue in the user's CLAUDE.md. Fail-open: any error -> exit 0. Suppressed by a
# `.no-agy` kill-switch (cwd or ~/.claude), matching the other agy-weave hooks.
set +e
# stderr is silenced ONCE, here: a per-command `2>/dev/null` inside a command substitution costs an extra
# process (MEASURED: `x=$(jq -r . 2>/dev/null)` 6 vs `x=$(jq -r .)` 5). Nothing in this hook writes to stderr.
exec 2>/dev/null
# PROCESS BUDGET (owner ruling: at most 16 processes per hook run, bash's own boot included; on this
# platform every process costs ~200ms and this hook runs after EVERY Write/Edit). The payload is read into
# $input only when jq is ABSENT; with jq present, jq reads this hook's own stdin directly (no `$(cat)`, no
# `printf | jq` pipelines, no `printf | tr | grep` match - all of those are 2-3 processes each).
if command -v jq >/dev/null 2>&1; then _have_jq=1; else _have_jq=''; if [ -z "${CLAVITY_HOOK_BASH3:-}" ] && ((BASH_VERSINFO[0]*100+BASH_VERSINFO[1] >= 401)); then input=; while IFS= read -r -N 1048576 _c; do input+=$_c; done; input+=$_c; else input=$(cat); fi; fi

# --- jq guard (spec Decision 4 / SP-D). jq parses the payload + emits structured JSON. Without it,
# fall back to a separator-agnostic, FIELD-BOUNDED grep on the RAW payload's file_path and, ONLY on a
# spec/plan match, emit a loud hard-coded ASCII line so the AGY-AFTER reminder is never a silent no-op.
# Honor the kill-switch first (global; cwd falls back to the process cwd without jq). ---
if [ -z "$_have_jq" ]; then
  # Recover the REAL cwd from the raw payload rather than trusting the process cwd, which is not
  # necessarily the session's workspace. Same technique the recorder uses; needs no jq. This value keeps
  # its JSON escaping, hence the DOUBLE-backslash pattern - see the note at the jq path below.
  [[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && cwd=${BASH_REMATCH[1]}
  cwd_path=${cwd//\\\\//}
  [ -z "$cwd_path" ] && cwd_path="."
  [ -f "$HOME/.claude/.no-agy" ] && exit 0
  root=$cwd_path
  # ONE stat gates the walk. On an unreachable share EVERY level pays an SMB timeout - MEASURED
  # 2026-08-06: 20314ms walking an unreachable //server/share/a/b/c vs 9282ms gated. Do NOT replace
  # this with a "//" prefix test: WSL repos are LIVE UNC paths (\\wsl.localhost\<distro>\...) and
  # such a test would silently disable the root walk for them.
  if [ -d "$cwd_path" ]; then
    _d=$cwd_path
    while [ -n "$_d" ] && [ "$_d" != "/" ] && [ "$_d" != "." ]; do
      if [ -e "$_d/.git" ]; then root=$_d; break; fi
      # Stop at the UNC volume root - //server/.git is not a valid path and statting it costs
      # another network round-trip for a result that can never be a repo.
      case "$_d" in //*/*/*) ;; //*) break ;; esac
      _p=${_d%/*}
      [ "$_p" = "$_d" ] && break
      [ -z "$_p" ] && break
      _d=$_p
    done
  fi
  if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then exit 0; fi
  # grep -Eq, line by line, in the shell: `[[ =~ ]]` is POSIX ERE like grep -E, and the per-line loop keeps
  # grep's rule that a match never spans a newline.
  _re='"(file_path|path)"[[:space:]]*:[[:space:]]*"[^"]*docs[\\/]+superpowers[\\/]+(specs|plans)[\\/]+[^"]*\.md'
  while IFS= read -r _l; do
    if [[ $_l =~ $_re ]]; then
      printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[AGY-DISCIPLINES] guard inactive: missing jq - the AGY-AFTER panel reminder will not fire on spec/plan writes"}}'
      break
    fi
  done <<<"$input"
  exit 0
fi
# ONE jq call yields both fields (file path, cwd), joined by \u0001 - a character no path contains. The
# `// ""` keeps an absent path an EMPTY field (the old `// empty` printed nothing), and `$(...)` strips
# trailing newlines exactly as the two old substitutions did.
out=$(jq -r '"\(.tool_input.file_path // .tool_input.path // "")\u0001\(.cwd // ".")"')
fp=${out%%$'\001'*}
cwd=${out#*$'\001'}
while [[ $fp == *$'\n' ]]; do fp=${fp%$'\n'}; done
[ -z "$fp" ] && exit 0

# THE NORMALIZATION FORM MUST MATCH THE EXTRACTION SOURCE. jq -r DECODES the JSON escaping, so cwd holds
# SINGLE backslashes here and the pattern is one escaped backslash. The degraded branch above recovers cwd
# from the RAW payload, where the DOUBLE backslashes survive, so it uses ${cwd//\\\\//} instead. MEASURED
# 2026-08-05: the raw form applied to a jq-decoded value matches nothing and leaves the path untouched - a
# silent no-op that looks exactly like a working fix. Do NOT unify the two spellings.
cwd_path=${cwd//\\//}
[ -z "$cwd_path" ] && cwd_path="."

# Opt-out kill-switch (mirrors agy-seam-inject.sh). Global first - it needs no root.
[ -f "$HOME/.claude/.no-agy" ] && exit 0

# Repo root by walking up for .git, in-shell, so a .no-agy at the REPO ROOT is honoured when the session
# was launched from a subdirectory. The normalization above is load-bearing: ${_d%/*} strips on "/" only,
# so an un-normalized Windows path breaks this loop on its first iteration. A .git entry matches as a
# directory (normal clone) or a file (worktree/submodule).
root=$cwd_path
# ONE stat gates the walk. On an unreachable share EVERY level pays an SMB timeout - MEASURED
# 2026-08-06: 20314ms walking an unreachable //server/share/a/b/c vs 9282ms gated. Do NOT replace
# this with a "//" prefix test: WSL repos are LIVE UNC paths (\\wsl.localhost\<distro>\...) and
# such a test would silently disable the root walk for them.
if [ -d "$cwd_path" ]; then
  _d=$cwd_path
  while [ -n "$_d" ] && [ "$_d" != "/" ] && [ "$_d" != "." ]; do
    if [ -e "$_d/.git" ]; then root=$_d; break; fi
    # Stop at the UNC volume root - //server/.git is not a valid path and statting it costs
    # another network round-trip for a result that can never be a repo.
    case "$_d" in //*/*/*) ;; //*) break ;; esac
    _p=${_d%/*}
    [ "$_p" = "$_d" ] && break
    [ -z "$_p" ] && break
    _d=$_p
  done
fi

if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
  exit 0
fi

# Normalize slashes; fire only for spec/plan artifacts under docs/superpowers/.
norm=${fp//\\//}
_hit=''
while IFS= read -r _l; do   # grep -Eq is per line; so is this
  if [[ $_l =~ docs/superpowers/(specs|plans)/.*\.md$ ]]; then _hit=1; break; fi
done <<<"$norm"
if [ -n "$_hit" ]; then
  msg="AGY-AFTER: you just authored/edited a spec or plan. BEFORE presenting it to the user, run an adversarial panel over the FINISHED artifact - do NOT wait for the user to ask \"did agy check?\". Invoke the \`adversarial-panel-review\` skill (it carries the full procedure: seat/persona palette, the live-peer escalation round, fold-with-verification, the PANEL VERDICT, and the hard round cap). Load-bearing posture: stay adversarial (a panel is the review FLOOR, not the ceiling); VERIFY every bare factual claim the peer makes BY MEASUREMENT before folding (it makes confident false claims); neither fold-nor-dismiss on disagreement - negotiate; the user still owns the review gate. If the artifact is genuinely mid-draft (incomplete), defer until the final write."
  jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
fi
exit 0

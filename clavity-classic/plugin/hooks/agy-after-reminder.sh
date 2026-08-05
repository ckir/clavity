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
input=$(cat)

# --- jq guard (spec Decision 4 / SP-D). jq parses the payload + emits structured JSON. Without it,
# fall back to a separator-agnostic, FIELD-BOUNDED grep on the RAW payload's file_path and, ONLY on a
# spec/plan match, emit a loud hard-coded ASCII line so the AGY-AFTER reminder is never a silent no-op.
# Honor the kill-switch first (global; cwd falls back to the process cwd without jq). ---
if ! command -v jq >/dev/null 2>&1; then
  # Recover the REAL cwd from the raw payload rather than trusting the process cwd, which is not
  # necessarily the session's workspace. Same technique the recorder uses; needs no jq. This value keeps
  # its JSON escaping, hence the DOUBLE-backslash pattern - see the note at the jq path below.
  [[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && cwd=${BASH_REMATCH[1]}
  cwd_path=${cwd//\\\\//}
  [ -z "$cwd_path" ] && cwd_path="."
  [ -f "$HOME/.claude/.no-agy" ] && exit 0
  root=$cwd_path
  _d=$cwd_path
  while [ -n "$_d" ] && [ "$_d" != "/" ] && [ "$_d" != "." ]; do
    if [ -e "$_d/.git" ]; then root=$_d; break; fi
    _p=${_d%/*}
    [ "$_p" = "$_d" ] && break
    [ -z "$_p" ] && break
    _d=$_p
  done
  if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then exit 0; fi
  if printf '%s' "$input" | grep -Eq '"(file_path|path)"[[:space:]]*:[[:space:]]*"[^"]*docs[\\/]+superpowers[\\/]+(specs|plans)[\\/]+[^"]*\.md'; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[AGY-DISCIPLINES] guard inactive: missing jq - the AGY-AFTER panel reminder will not fire on spec/plan writes"}}'
  fi
  exit 0
fi
fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)
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
_d=$cwd_path
while [ -n "$_d" ] && [ "$_d" != "/" ] && [ "$_d" != "." ]; do
  if [ -e "$_d/.git" ]; then root=$_d; break; fi
  _p=${_d%/*}
  [ "$_p" = "$_d" ] && break
  [ -z "$_p" ] && break
  _d=$_p
done

if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
  exit 0
fi

# Normalize slashes; fire only for spec/plan artifacts under docs/superpowers/.
norm=$(printf '%s' "$fp" | tr '\\' '/')
if printf '%s' "$norm" | grep -Eq 'docs/superpowers/(specs|plans)/.*\.md$'; then
  msg="AGY-AFTER: you just authored/edited a spec or plan. BEFORE presenting it to the user, run an adversarial panel over the FINISHED artifact - do NOT wait for the user to ask \"did agy check?\". Invoke the \`adversarial-panel-review\` skill (it carries the full procedure: seat/persona palette, the live-peer escalation round, fold-with-verification, the PANEL VERDICT, and the hard round cap). Load-bearing posture: stay adversarial (a panel is the review FLOOR, not the ceiling); VERIFY every bare factual claim the peer makes BY MEASUREMENT before folding (it makes confident false claims); neither fold-nor-dismiss on disagreement - negotiate; the user still owns the review gate. If the artifact is genuinely mid-draft (incomplete), defer until the final write."
  jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
fi
exit 0

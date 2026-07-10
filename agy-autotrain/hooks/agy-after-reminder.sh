#!/usr/bin/env bash
# AGY-AFTER (plugin-shipped). PostToolUse(Write|Edit): when a SPEC or PLAN artifact is
# authored/edited (docs/superpowers/specs/** or docs/superpowers/plans/**), inject a
# reminder to route the FINISHED artifact through an adversarial panel BEFORE presenting
# it to the user — the complement to AGY-FIRST (forks). The full procedure lives in the
# `adversarial-panel-review` skill (this hook only POINTS at it; it never runs the panel).
# Ships with the agy-autotrain plugin, so it installs/uninstalls with the plugin and leaves
# no residue in the user's CLAUDE.md. Fail-open: any error → exit 0. Suppressed by a
# `.no-agy` kill-switch (cwd or ~/.claude), matching the other agy-weave hooks.
set +e
input=$(cat)
fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)
[ -z "$fp" ] && exit 0

# Opt-out kill-switch (mirrors agy-seam-inject.sh).
if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  exit 0
fi

# Normalize slashes; fire only for spec/plan artifacts under docs/superpowers/.
norm=$(printf '%s' "$fp" | tr '\\' '/')
if printf '%s' "$norm" | grep -Eq 'docs/superpowers/(specs|plans)/.*\.md$'; then
  msg="AGY-AFTER: you just authored/edited a spec or plan. BEFORE presenting it to the user, run an adversarial panel over the FINISHED artifact — do NOT wait for the user to ask \"did agy check?\". Invoke the \`adversarial-panel-review\` skill (it carries the full procedure: seat/persona palette, the live-peer escalation round, fold-with-verification, the PANEL VERDICT, and the hard round cap). Load-bearing posture: stay adversarial (a panel is the review FLOOR, not the ceiling); VERIFY every bare factual claim the peer makes BY MEASUREMENT before folding (it makes confident false claims); neither fold-nor-dismiss on disagreement — negotiate; the user still owns the review gate. If the artifact is genuinely mid-draft (incomplete), defer until the final write."
  jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
fi
exit 0

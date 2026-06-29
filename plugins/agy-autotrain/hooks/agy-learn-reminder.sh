#!/usr/bin/env bash
# agy-LEARN reminder — shipped WITH the agy-autotrain plugin (portable: no machine-specific paths).
#
# The third agy discipline — CAPTURE general agy knowledge (agy-learn) — has no tool-event signal:
# "the agent learned an agy fact" cannot be matched like a file write or a skill invocation, so the
# capture step silently depends on memory and gets dropped. This hook nudges at SESSION BOUNDARIES
# instead: SessionStart (including right after a compaction) primes live capture; PreCompact catches
# anything not yet captured before it is summarized away.
#
# Fail-open: any error -> exit 0 (never block the session). Opt out with a `.no-agy` file in the
# working dir or ~/.claude. Registered by ../hooks.json via ${CLAUDE_PLUGIN_ROOT}.
set +e
event="${1:-SessionStart}"
input=$(cat 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)
[ -z "$cwd" ] && cwd="."

if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  exit 0
fi

case "$event" in
  PreCompact)
    msg="agy-LEARN check BEFORE COMPACTION: did you learn anything GENERAL about the agy peer this session (a capability, a latency/failure mode, or a way the DRIVER broke it) that is NOT yet captured? Uncaptured agy knowledge is LOST at compaction. If yes, capture it NOW via the agy-learn skill — a project-agnostic [General Rule] (ZERO project nouns), classified assumption|heuristic|anti-pattern, with no version stamp for general behavior. Knowledge accumulation is the agy-autotrain plugin's job — do not journal agy knowledge into ad-hoc notes."
    ;;
  *)
    event="SessionStart"
    msg="agy-autotrain is active: the MOMENT you learn something GENERAL about the agy peer (a capability, a latency/failure mode, or a prompting/driving anti-pattern), capture it IMMEDIATELY via the agy-learn skill — a project-agnostic [General Rule] (no project nouns), classified assumption|heuristic|anti-pattern. Capture is cheap and live; do not batch, and do not wait to be reminded. (agy-LEARN — the capture sibling of agy-FIRST and agy-AFTER.)"
    ;;
esac

jq -nc --arg e "$event" --arg m "$msg" '{hookSpecificOutput:{hookEventName:$e,additionalContext:$m}}'
exit 0

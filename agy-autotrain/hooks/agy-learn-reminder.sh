#!/usr/bin/env bash
# agy-LEARN reminder - shipped WITH the agy-autotrain plugin (portable: no machine-specific paths).
#
# The third agy discipline - CAPTURE general agy knowledge (agy-learn) - has no tool-event signal:
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

# BOTH home roots are checked, matching agy-curate-nudge.sh and agy-inbox-snapshot.sh - the two sibling
# hooks this plugin registers on the SAME SessionStart event. A parent that exports USERPROFILE without
# HOME leaves $HOME empty (measured: `env -u HOME bash --noprofile --norc` does NOT backfill it from
# USERPROFILE), so a bare $HOME lookup silenced the siblings and left THIS hook talking - the operator
# asks for silence and still gets nudged, which is the worst shape a kill switch can fail in because the
# reduced noise reads as success. A kill switch may only ever fail SAFE, toward silence, so widening the
# lookup can only honour an opt-out that was actually asked for; it can never re-arm a silenced hook.
# Pinned by the USERPROFILE-vs-HOME control in scripts/tests/agy-learn-reminder.Tests.ps1.
HOME_DIR="${USERPROFILE:-$HOME}"
if [ -f "$cwd/.no-agy" ] || [ -f "${HOME_DIR}/.claude/.no-agy" ] || [ -f "${HOME}/.claude/.no-agy" ]; then
  exit 0
fi

case "$event" in
  PreCompact)
    msg="agy-LEARN check BEFORE COMPACTION: did you learn anything GENERAL about the agy peer this session (a capability, a latency/failure mode, or a way the DRIVER broke it) that is NOT yet captured? Uncaptured agy knowledge is LOST at compaction. If yes, capture it NOW via the agy-learn skill - a project-agnostic [General Rule] (ZERO project nouns), classified assumption|heuristic|anti-pattern, with no version stamp for general behavior. Knowledge accumulation is the agy-autotrain plugin's job - do not journal agy knowledge into ad-hoc notes."
    ;;
  *)
    event="SessionStart"
    msg="agy-autotrain is active: the MOMENT you learn something GENERAL about the agy peer (a capability, a latency/failure mode, or a prompting/driving anti-pattern), capture it IMMEDIATELY via the agy-learn skill - a project-agnostic [General Rule] (no project nouns), classified assumption|heuristic|anti-pattern. Capture is cheap and live; do not batch, and do not wait to be reminded. (agy-LEARN - the capture sibling of agy-FIRST and agy-AFTER.)"
    ;;
esac

# The two events take DIFFERENT output shapes, and emitting the wrong one is not a soft failure --
# Claude Code rejects the payload outright, so the reminder never reaches the model and the operator
# sees a schema-validation dump instead. hookSpecificOutput is valid for SessionStart, PreToolUse,
# UserPromptSubmit, PostToolUse, PostToolBatch and Stop/SubagentStop; PreCompact is NOT among them and
# must use the top-level systemMessage field. (SessionStart was missing from this list until 2026-08-26 -
# and the default branch four lines below emits hookSpecificOutput with hookEventName:"SessionStart", so
# if the list had been right this hook's own primary path would be rejected outright. The list was
# incomplete, not the code; the code is the proof.)
case "$event" in
  PreCompact) jq -nc --arg m "$msg" '{systemMessage:$m}' ;;
  *)          jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}' ;;
esac
exit 0

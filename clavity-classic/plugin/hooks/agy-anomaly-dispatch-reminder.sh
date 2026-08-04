#!/usr/bin/env bash
# AGY-ANOMALIES dispatch reminder (plugin-shipped). PreToolUse(Agent|Task): carry the anomaly-relay
# obligation into every subagent dispatch. ISOLATED BY DESIGN -- agy-seam-inject.sh is not modified and
# not sourced. That hook is registered matcher "Skill" and keys its case on .tool_input.skill, which an
# Agent payload does not carry, so extending it would mean payload branching AND would push its
# implementer-only FILES clause at read-only reviewer subagents.
#
# THE GAP THIS CLOSES. Skill invocation is a ONE-SHOT event. Invoking subagent-driven-development, then
# compacting, then dispatching four subagents fires the seam injector's ANOMALY-CAPTURE arm ZERO times
# across exactly the work it governs. An earlier negotiation established BY MEASUREMENT that anomalies
# die at RELAY, not at noticing -- the driver compresses a subagent report into a summary -- so a
# PreCompact nudge is structurally too late for this loss: by compaction the report is already a
# two-line summary.
#
# FAIL OPEN ON EVERY PATH, AND THAT IS NOT A STYLE PREFERENCE. exit 2 is non-blocking for SessionStart
# but BLOCKING for PreToolUse (documented verbatim at agy-liveness-check.sh:8), so a non-zero exit here
# does not degrade a notification -- it HALTS EVERY SUBAGENT DISPATCH in the session. Both shipping
# PreToolUse hooks have zero non-zero exit paths; this one matches them. A test asserts that no
# exit with a non-zero status appears anywhere in this file.
#
# EMISSION = the JSON ENVELOPE at exit 0. MEASURED: plain stdout at exit 0 is SILENTLY DISCARDED, so a
# bare printf of the text produces no error, no output, and looks installed and working. PreToolUse takes
# hookSpecificOutput{hookEventName:"PreToolUse"} (precedent: agy-seam-inject.sh:71).
#
# THE DIRECTIVE CARRIES NO BACKTICK, APOSTROPHE, DOUBLE QUOTE OR BACKSLASH -- the first two are bash
# quoting hazards, the last two would break the hand-built envelope on the jq-absent path. Asserted at
# byte level against the EMITTED text. Measured on the sibling capture hook: a raw double quote in the
# message makes the jq-absent envelope malformed while the jq path escapes it, so the two channels
# silently stop agreeing. That is what the ban is for.
#
# NO TOOL-NAME GUARD: the matcher is the gate. Adding one would introduce a jq-absent branch that cannot
# determine the tool name and would have to emit anyway, buying nothing.
#
# Suppressed by .no-agy (workspace or global). Byte-identical across both driver plugins.
set +e
input=$(cat)

# ONE definition, used by BOTH emission paths, so the jq-absent fallback can never drift. Both halves of
# the obligation are present deliberately: an earlier draft carried only the return-side relay, which is
# compliance theater -- nothing instructed the subagent to produce the heading the driver is then told to
# look for, so the driver checks, finds nothing, and correctly concludes "no anomalies" from a question
# that was never asked.
msg='AGY-ANOMALIES/1 relay, both halves. (1) In the dispatch you are about to write, ask the subagent to report anything wrong it notices that is NOT its task, under a heading Anomalies noticed at the end of its final message, stated as a checkable fact, with an explicit none if it saw nothing. (2) When it returns, VERIFY each claimed anomaly by measurement and APPEND the verified ones to .clavity/local-anomalies.md BEFORE you write your summary. A verified anomaly that exists only in a chat message is lost the moment you compress that message.'

# jq is needed only to read cwd. Without it, STILL DELIVER the envelope rather than exiting silently: a
# silent exit is indistinguishable from a hook that is installed and has nothing to say. Kill-switch
# first, against the process cwd, since the payload cannot be parsed without jq.
if ! command -v jq >/dev/null 2>&1; then
  if [ -f "./.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then exit 0; fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$msg"
  exit 0
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)
[ -z "$cwd" ] && cwd="."

if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  exit 0
fi

jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
exit 0

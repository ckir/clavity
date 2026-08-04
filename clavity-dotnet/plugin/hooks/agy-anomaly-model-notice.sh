#!/usr/bin/env bash
# AGY-ANOMALIES SessionStart notice, MODEL half. Its sibling agy-anomaly-reminder.sh is the OWNER half:
# stderr at exit 2, because at SessionStart there is no user turn and stdout is absorbed into the model
# context where the owner never sees it. That same property is why the OWNER half cannot also serve the
# model -- stdout on an exit-2 hook is DISCARDED (measured). Two channels, two hooks, one matcher object:
# a matcher object's hooks array may hold several commands and exit status is PER-HOOK, so both fire on
# exactly the same occasions.
#
# The MODEL is the one who does the triage, so it has to learn the work exists. Counting logic mirrors
# agy-anomaly-reminder.sh deliberately, including its root resolution (:41-45) and its bracketed-bullet
# entry pattern (:58-70), so the two halves can never disagree about what is pending. A test runs BOTH
# hooks against the same repo and asserts the two counts match, because "mirrors it deliberately" is a
# claim about two separate files that nothing else would notice going out of step.
#
# Fail-open: any error -> exit 0. Suppressed by .no-agy (workspace or global).
set +e
input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)
[ -z "$cwd" ] && cwd="."

if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  exit 0
fi

root=$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
[ -n "$root" ] || root="$cwd"
f="$root/.clavity/local-anomalies.md"
[ -f "$f" ] || f="$cwd/.clavity/local-anomalies.md"
[ -f "$f" ] || exit 0

n=$(grep -c '^- \[[^]]*\]' "$f" 2>/dev/null)
rc=$?
# Unreadable is not "none", but this half must stay silent about it: the OWNER half already reports that
# case on stderr, and duplicating it here would put the same advisory on two channels.
if [ "$rc" -gt 1 ]; then exit 0; fi
[ -z "$n" ] && n=0
[ "$n" -eq 0 ] && exit 0

msg="AGY-ANOMALIES: $n untriaged in $f. Triage before new work via the open-issues skill: each entry is either PROMOTED to a tracked item with an owner, or DELETEd with a recorded reason. There is no parked state."
jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
exit 0

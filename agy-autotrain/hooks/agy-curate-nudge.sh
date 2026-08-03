#!/usr/bin/env bash
# agy-curate staleness nudge (spec §5.C-A). Fires on SessionStart; warns when the observations inbox has
# grown past a threshold. Escalating wording; snooze via ~/.clavity/.agy-curate-snooze (7-day). Fail-open.
set +e

THRESHOLD="${AGY_CURATE_NUDGE_THRESHOLD:-8}"        # entries in ## Pending before nudging (tunable)
MAX_AGE_DAYS="${AGY_CURATE_NUDGE_MAX_AGE_DAYS:-30}"  # oldest pending entry age (days) before nudging (tunable)
OBS="${CLAUDE_PLUGIN_ROOT}/knowledge/agy-observations.md"
HOME_DIR="${USERPROFILE:-$HOME}"
SNOOZE="${HOME_DIR}/.clavity/.agy-curate-snooze"

# Opt-out: a .no-agy marker in cwd or ~/.claude silences everything (mirror agy-learn-reminder.sh).
input="$(cat 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -f "${cwd}/.no-agy" ] && exit 0
[ -f "${HOME}/.claude/.no-agy" ] && exit 0

# Snooze: if the marker exists and is younger than 7 days, stay silent.
if [ -f "$SNOOZE" ]; then
  now="$(date +%s 2>/dev/null)"; mt="$(date -r "$SNOOZE" +%s 2>/dev/null)"
  if [ -n "$now" ] && [ -n "$mt" ] && [ "$((now - mt))" -lt 604800 ]; then exit 0; fi
fi

[ -f "$OBS" ] || exit 0
# Count entries under "## Pending" (lines beginning with "- ["), and find the OLDEST entry date
# (bullets carry a `· YYYY-MM-DD ·` stamp; lexicographic min == chronologically oldest).
# BOTH scans MUST be anchored to /^- \[/ - keep them symmetric. The `p=0` terminator is not enough on its
# own: nothing after "## Pending" starts with "## " (the section is followed by append-only drain-log HTML
# comments), so `p` stays 1 to EOF. An unanchored date scan therefore reads dates out of those comments and
# reports an "oldest pending entry" no bullet carries - which latched the age nudge ON permanently, because
# draining cannot remove a drain log. Pinned by scripts/tests/agy-curate-nudge.Tests.ps1.
count="$(awk '/^## Pending/{p=1;next} /^## /{p=0} p && /^- \[/{c++} END{print c+0}' "$OBS" 2>/dev/null)"
oldest="$(awk '/^## Pending/{p=1;next} /^## /{p=0} p && /^- \[/ && match($0,/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/){d=substr($0,RSTART,10); if(m==""||d<m)m=d} END{print m}' "$OBS" 2>/dev/null)"
[ -z "$count" ] && exit 0

# Age gate (spec §5.C-A: nudge on "N entries / an age threshold"): is the oldest pending entry too old?
age_stale=0
if [ -n "$oldest" ]; then
  now="$(date +%s 2>/dev/null)"; ots="$(date -d "$oldest" +%s 2>/dev/null)"
  if [ -n "$now" ] && [ -n "$ots" ] && [ "$(( (now - ots) / 86400 ))" -ge "$MAX_AGE_DAYS" ]; then age_stale=1; fi
fi

# Silent only if NEITHER threshold is exceeded.
if [ "$count" -lt "$THRESHOLD" ] && [ "$age_stale" -eq 0 ]; then exit 0; fi

if [ "$count" -ge "$((THRESHOLD * 2))" ]; then
  msg="agy-curate is OVERDUE: the observations inbox has ${count} pending entries (threshold ${THRESHOLD}). The driver is running on stale rules while the peer drifts. Run the agy-curate skill to drain the inbox now. (Snooze for 7 days: touch \"${SNOOZE}\".)"
elif [ "$count" -lt "$THRESHOLD" ] && [ "$age_stale" -eq 1 ]; then
  msg="agy-curate nudge: the observations inbox's oldest pending entry (${oldest}) is over ${MAX_AGE_DAYS} days old (only ${count} entries, under the count threshold). Run the agy-curate skill to drain it before the driver drifts on stale rules. (Snooze for 7 days: touch \"${SNOOZE}\".)"
else
  msg="agy-curate nudge: the observations inbox has ${count} pending entries (threshold ${THRESHOLD}). Consider running the agy-curate skill to drain it. (Snooze for 7 days: touch \"${SNOOZE}\".)"
fi

jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}' 2>/dev/null
exit 0

#!/usr/bin/env bash
# agy-curate staleness nudge (spec section 5.C-A). Fires on SessionStart; warns when the observations inbox has
# grown past a threshold. Escalating wording; snooze via ~/.clavity/.agy-curate-snooze (7-day). Fail-open.
set +e

THRESHOLD="${AGY_CURATE_NUDGE_THRESHOLD:-8}"        # entries in ## Pending before nudging (tunable)
MAX_AGE_DAYS="${AGY_CURATE_NUDGE_MAX_AGE_DAYS:-30}"  # oldest pending entry age (days) before nudging (tunable)
HOME_DIR="${USERPROFILE:-$HOME}"
# ROADMAP 14g: the canonical inbox is USER-LOCAL state, beside the golden-header files - NOT inside the
# plugin install tree. That tree exists in N copies (install, checkout, every worktree) with no reliable
# way to tell which one is live, which is why both skills had grown a resolution order and a "is this a
# checkout?" test. CLAUDE_PLUGIN_ROOT is deliberately NOT consulted here: a stale inbox left in a plugin
# tree must be IGNORED, not merged, not preferred. Pinned by a decoy in agy-curate-nudge.Tests.ps1 -
# that decoy is the control, and it fails loudly if this line ever reverts to the plugin root.
OBS="${HOME_DIR}/.clavity/agy-observations.md"
SNOOZE="${HOME_DIR}/.clavity/.agy-curate-snooze"

# Opt-out: a .no-agy marker in cwd or ~/.claude silences everything (mirror agy-learn-reminder.sh).
input="$(cat 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -f "${cwd}/.no-agy" ] && exit 0
# BOTH roots are checked on purpose, and the pair is load-bearing. The inbox path above resolves via
# ${USERPROFILE:-$HOME}, so a parent process that exports USERPROFILE WITHOUT HOME reads the inbox
# correctly yet looks for the opt-out marker at a path that cannot exist - silently DISARMING the kill
# switch. That is reachable, not theoretical: measured, `env -u HOME bash --noprofile --norc` leaves
# HOME empty and does NOT backfill it from USERPROFILE. A kill switch may only ever fail SAFE - toward
# silence - so widening the lookup can only honour an opt-out the operator actually asked for; it can
# never re-arm a hook they had silenced. Pinned by the USERPROFILE-vs-HOME control in the suite.
[ -f "${HOME_DIR}/.claude/.no-agy" ] && exit 0
[ -f "${HOME}/.claude/.no-agy" ] && exit 0

# Snooze: if the marker exists and is younger than 7 days, stay silent.
if [ -f "$SNOOZE" ]; then
  now="$(date +%s 2>/dev/null)"; mt="$(date -r "$SNOOZE" +%s 2>/dev/null)"
  if [ -n "$now" ] && [ -n "$mt" ] && [ "$((now - mt))" -lt 604800 ]; then exit 0; fi
fi

[ -f "$OBS" ] || exit 0
# Count entries under "## Pending" (lines beginning with "- ["), and find the OLDEST entry date
# (bullets are delimited by U+00B7 MIDDLE DOT, NOT an ASCII asterisk - the live inbox format, pinned
# by agy-curate-nudge.Tests.ps1; lexicographic min == chronologically oldest).
# BOTH scans MUST be anchored to /^- \[/ - keep them symmetric. The `p=0` terminator is not enough on its
# own: nothing after "## Pending" starts with "## " (the section is followed by append-only drain-log HTML
# comments), so `p` stays 1 to EOF. An unanchored date scan therefore reads dates out of those comments and
# reports an "oldest pending entry" no bullet carries - which latched the age nudge ON permanently, because
# draining cannot remove a drain log. Pinned by scripts/tests/agy-curate-nudge.Tests.ps1.
# BOTH RULES MUST MATCH THE CANONICAL READER, and the first attempt at this only fixed one of them.
# drain-lib.ps1's Get-PendingRegionLines OPENS on `^##\s+Pending\s*$` - an exact line - and CLOSES on any
# heading `^#{1,6}\s`. On 2026-08-26 these scans were changed to close on `^#+[ \t]`, and a comment here
# claimed the two readers now agreed. They did not: the OPEN rule was still a bare prefix match, so a
# heading like `## Pending entries (do not edit)` opened the region for bash and not for PowerShell, and
# the two readers of one file disagreed about which entries are pending in the direction nobody checked.
# Both rules are aligned now.
#
# ONE RESIDUAL DIVERGENCE, STATED RATHER THAN CLAIMED AWAY, because the earlier comment's mistake was
# claiming equivalence it had not established: `#+` accepts SEVEN OR MORE hashes where `#{1,6}` does not,
# and `[ \t]` is narrower than `\s`. Interval expressions are not portable across every awk this hook may
# meet, so the wider form stays - and seven hashes is not a markdown heading anyway, which is the reason
# the divergence is acceptable and not the reason it does not exist.
count="$(awk '/^## Pending[ \t]*$/{p=1;next} /^#+[ \t]/{p=0} p && /^- \[/{c++} END{print c+0}' "$OBS" 2>/dev/null)"
oldest="$(awk 'function flush(){ v=(stamp!=""?stamp:cur); if(v!=""){ if(m==""||v<m) m=v }; cur=""; stamp="" } /^## Pending[ \t]*$/{p=1;next} /^#+[ \t]/{ flush(); p=0 } p && /^- \[/ { flush(); inrec=1 } p && (/^[ \t]*$/ || /^[ \t]*<!--/) { flush(); inrec=0 } p && inrec { s=$0; while(match(s,/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)){ pre=substr(s,1,RSTART-1); d=substr(s,RSTART,10); s=substr(s,RSTART+10); sub(/[ \t]+$/,"",pre); if(s ~ /^[^0-9A-Za-z]*agy([ \t]|$)/ && pre !~ /[0-9A-Za-z]$/) stamp=d; cur=d } } END{ flush(); print m }' "$OBS" 2>/dev/null)"
[ -z "$count" ] && exit 0

# Age gate (spec section 5.C-A: nudge on "N entries / an age threshold"): is the oldest pending entry too old?
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

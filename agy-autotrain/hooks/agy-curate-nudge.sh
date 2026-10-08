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

# Days since the civil epoch (1970-01-01) for a year, month and day: Hinnant's days_from_civil, in plain bash-3.2-safe
# arithmetic. ROADMAP section 73: BSD/macOS date has no `date -d <date>` parse, so the age nudge below could never fire on a
# Mac; the GNU-only call is gone entirely. The result comes back in the global _DFC. It is a UTC day count, where `date -d`
# gave local midnight: the boundary can shift by up to the UTC offset, which a 30-day threshold absorbs.
# EVERY field takes 10#, the YEAR included: bash arithmetic reads a leading zero as octal, so a bare "0099" would die with
# "value too great for base" (month and day alone were guarded in the first draft of this function).
_dfc() {
  _y=$((10#$1)); _m=$((10#$2)); _d=$((10#$3))
  [ "$_m" -le 2 ] && _y=$((_y - 1))
  if [ "$_y" -ge 0 ]; then _era=$((_y / 400)); else _era=$(((_y - 399) / 400)); fi
  _yoe=$((_y - _era * 400))
  _doy=$(((153 * ((_m + 9) % 12) + 2) / 5 + _d - 1))
  _doe=$((_yoe * 365 + _yoe / 4 - _yoe / 100 + _doy))
  _DFC=$((_era * 146097 + _doe - 719468))
}

# Opt-out: a .no-agy marker in cwd or ~/.claude silences everything (mirror agy-learn-reminder.sh).
# PROCESS BUDGET (<=16 per run on Windows, ~200 ms each): `read` is a builtin (`$(cat)` costs two
# processes); `read -d ''` returns non-zero at EOF but still fills $input; a trailing newline is kept,
# harmless since $input only feeds jq. Here-string, not `printf | jq`, saves the pipeline's extra process.
# stdin: read -N needs bash >= 4.1; older bash (macOS /bin/bash 3.2) keeps the pre-Branch-20 read.
if [ -z "${CLAVITY_HOOK_BASH3:-}" ] && ((BASH_VERSINFO[0]*100+BASH_VERSINFO[1] >= 401)); then input=; while IFS= read -r -N 1048576 _c 2>/dev/null; do input+=$_c; done; input+=$_c; else input=$(cat 2>/dev/null); fi
cwd="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)"
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
  if [ -z "${CLAVITY_HOOK_BASH3:-}" ] && ((BASH_VERSINFO[0]*100+BASH_VERSINFO[1] >= 402)); then printf -v now '%(%s)T' -1 2>/dev/null; else now=$(date +%s); fi; mt="$(date -r "$SNOOZE" +%s 2>/dev/null)"
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
# BOTH RULES MUST MATCH THE CANONICAL READER, and it took THREE attempts to get there - which is the
# most useful thing this comment records. The first fixed only the CLOSE rule and claimed both agreed.
# The second anchored the OPEN rule to `^## Pending[ \t]*$` and still did not match: the canonical reader
# opens on `^##\s+Pending\s*$`, one-or-MORE whitespace, so `##  Pending` with two spaces opened the
# region for PowerShell and for neither reader here. Each attempt narrowed the gap and then asserted it
# was closed. It is `[ \t]+` now, which is the same set `\s+` means for this line.
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
# ONE awk computes both values (process budget: it was two awks, two processes each). The count rule is the
# old first program verbatim, folded into the bullet-open rule (`c++`) of the old second program; both
# programs had identical open/close rules, so the merged scan sees the same region. Output is
# "<count>|<oldest>" (a date is digits and '-', so '|' is unambiguous; `$(...)` would strip a trailing
# newline, which is why the separator is not a newline).
scan="$(awk 'function flush(){ v=(stamp!=""?stamp:cur); if(v!=""){ if(m==""||v<m) m=v }; cur=""; stamp="" } /^##[ \t]+Pending[ \t]*$/{p=1;next} /^#+[ \t]/{ flush(); p=0 } p && /^- \[/ { c++; flush(); inrec=1 } p && (/^[ \t]*$/ || /^[ \t]*<!--/) { flush(); inrec=0 } p && inrec { s=$0; while(match(s,/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)){ pre=substr(s,1,RSTART-1); d=substr(s,RSTART,10); s=substr(s,RSTART+10); sub(/[ \t]+$/,"",pre); if(s ~ /^[^0-9A-Za-z]*agy([ \t]|$)/ && pre !~ /[0-9A-Za-z]$/) stamp=d; cur=d } } END{ flush(); print c+0 "|" m }' "$OBS" 2>/dev/null)"
count=${scan%%|*}; oldest=${scan#*|}
[ -z "$scan" ] && exit 0

# Age gate (spec section 5.C-A: nudge on "N entries / an age threshold"): is the oldest pending entry too old?
age_stale=0
re_iso='^([0-9]{4})-([0-9]{2})-([0-9]{2})$'
if [[ $oldest =~ $re_iso ]]; then
  _mo=$((10#${BASH_REMATCH[2]})); _da=$((10#${BASH_REMATCH[3]})); _yr=$((10#${BASH_REMATCH[1]}))
  # Range-validate what `date -d` used to reject: an impossible date such as 2020-13-45 or 2020-02-30 must not arm the gate
  # (_dfc would fold a day past the end of its month into the next one). Days in the month, with the Gregorian leap rule.
  case $_mo in
    2) if (( _yr % 4 == 0 && (_yr % 100 != 0 || _yr % 400 == 0) )); then _dim=29; else _dim=28; fi ;;
    4|6|9|11) _dim=30 ;;
    *) _dim=31 ;;
  esac
  if [ "$_mo" -ge 1 ] && [ "$_mo" -le 12 ] && [ "$_da" -ge 1 ] && [ "$_da" -le "$_dim" ]; then
    if [ -z "${CLAVITY_HOOK_BASH3:-}" ] && ((BASH_VERSINFO[0]*100+BASH_VERSINFO[1] >= 402)); then printf -v now '%(%s)T' -1 2>/dev/null; else now=$(date +%s); fi
    _dfc "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    if [ -n "$now" ] && [ "$(( now / 86400 - _DFC ))" -ge "$MAX_AGE_DAYS" ]; then age_stale=1; fi
  fi
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

# PROCESS BUDGET: emitting the JSON in-shell saves a jq process on every nudge path. Byte-identical to
# `jq -nc` ONLY while $msg is printable ASCII (jq escapes only `\`, `"` and control characters, and passes
# the rest through), so anything outside space..tilde (a non-ASCII or control char in the USERPROFILE path,
# a DEL) falls back to jq. The `command -v` guard keeps the old "no jq -> print nothing" behaviour.
command -v jq >/dev/null 2>&1 || exit 0
LC_ALL=C   # byte-wise range below; last statement before exit, so nothing else is affected (no subshell: a fork costs a process)
if [[ $msg == *[^\ -~]* ]]; then
  jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}' 2>/dev/null
else
  esc=${msg//\\/\\\\}; esc=${esc//\"/\\\"}
  eol=$'\n'
  printf '%s%s' "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$esc\"}}" "$eol"
fi
exit 0

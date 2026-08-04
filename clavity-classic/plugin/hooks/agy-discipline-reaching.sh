#!/usr/bin/env bash
# AGY-ANOMALIES discipline-reaching recorder (plugin-shipped). SessionEnd.
# ROADMAP section 0 step 1a: the MEASURE half. It answers ONE question from recorded evidence, without
# asking any agent what it thinks happened: does the PreToolUse dispatch relay REACH a driver, and how
# often? Design + every measurement behind it: docs/superpowers/specs/2026-08-04-discipline-efficacy-design.md
#
# IT READS; IT NEVER ASKS A NUDGE HOOK TO REPORT. That is the load-bearing choice. The obvious design -
# each nudge hook increments a counter - puts a WRITE on a fail-open path, and the dispatch reminder in
# particular sits where a non-zero exit BLOCKS every subagent dispatch in the session. Here exactly one
# write happens, at session end, where nothing is blocked.
#
# WHY DETECTION IS STRUCTURE **PLUS** A STAMP, and not either alone. Three measured facts:
#   1. Free-text matching is invalid. The relay text occurred 470 times against ONE real dispatch, because
#      the JSONL re-serialises context, the text also appears in authored content, and the transcript is
#      SELF-REFERENTIAL (a control string went 1 -> 11 hits purely by being searched for).
#   2. Structure alone OVER-COUNTS. hookName is <Event>:<ToolName>, shared by every plugin registering on
#      that tool, and hook_additional_context carries NO field naming the script. MEASURED on a real
#      transcript: 6 structural matches on PreToolUse:Agent, of which ONE was ours - a 6x over-count.
#   3. So: filter STRUCTURALLY first (a typed attachment record), then discriminate on the stamp INSIDE
#      that record's content. Authored prose and the detector's own query text land in user/assistant
#      records, never inside a hook attachment, so the text match is scoped to a region no author and no
#      query can write to.
#
# FIRED vs REACHED are different records and both are recorded. hook_success means the hook EXECUTED (and
# carries `command`, which is how execution is attributed to this script); hook_additional_context means
# its words REACHED the model. `dispatch_fired > 0` with `dispatch_nudges == 0` is the v15 failure in a
# single row - every gate green, nothing delivered.
#
# NO precompact_* FIELDS, DELIBERATELY. MEASURED across 112 transcripts holding 82 compactions:
# "hookEvent":"PreCompact" appears ZERO times - PreCompact firings are never written to the transcript, so
# that channel's delivery is unobservable here. `compactions` records the OPPORTUNITY only. It is a
# denominator with no numerator: NEVER divide by it.
#
# A NULL IS NOT A ZERO. An unreadable transcript records null counts and a scan_status naming why, and the
# record STILL lands - a missing record and a degraded one must not look alike, and an unknown recorded as
# a measured zero is this item's own thesis inverted.
#
# Fail-open: any error -> exit 0. Suppressed by .no-agy (workspace or global) like every other hook.
# Byte-identical across both driver plugins (kept honest by scripts/check-seed-artifacts-synced.sh).
set +e
input=$(cat)

# jq is required to parse the payload at all - without it we cannot even learn where the transcript is, so
# there is nothing to record and no way to name the session. Exit silently. This is a known, accepted gap
# rather than a hidden one: a machine with no jq produces no rows, and the consumer reports rows RECORDED,
# never sessions RUN, so it can never mistake this for a measured zero.
command -v jq >/dev/null 2>&1 || exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)
[ -z "$cwd" ] && cwd="."
if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  exit 0
fi

root=$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
[ -n "$root" ] || root="$cwd"

sid=$(printf '%s'    "$input" | jq -r '.session_id // ""'     2>/dev/null)
reason=$(printf '%s' "$input" | jq -r '.reason // ""'         2>/dev/null)
tx=$(printf '%s'     "$input" | jq -r '.transcript_path // ""' 2>/dev/null)

# The stamp is a CONTRACT version, hand-bumped, identical in both drivers. It cannot be a BUILD version:
# the two drivers ship at different plugin versions while these bodies stay byte-identical, so a build
# literal is a parity break by construction (Option S, docs/agy-disciplines-marker-contract.md:13).
stamp='AGY-ANOMALIES/1'

# Bound the read. Past the cap we record nulls and SAY SO rather than truncating, because a truncated scan
# under-reports exactly the long sessions most likely to contain a nudge.
#
# THE COST MODEL IS BYTES-FED-TO-JQ, NOT LINES, AND THE FIRST DESIGN HERE BLEW THE BUDGET.
# It ran three separate two-stage scans, prefiltering `fired` on '"type":"hook_success"'. MEASURED on a
# real 176 MB transcript: 20,9s against a 10s budget - the hook would have been KILLED and no record would
# have landed, which is the silent zero this whole item exists to remove. The cause: hook_success records
# carry each hook's full stdout/stderr, so that prefilter matched 132 MB of the 176 MB file and jq had to
# parse nearly all of it (16,2s in that one stage). The greps were never the problem - all three together
# cost ~1,2s.
# The fix is ONE grep over a SELECTIVE pattern set, then ONE jq that classifies. Prefiltering `fired` on
# the command-field form instead of the record type takes that stage from 132 MB to 1,4 kB, and paying
# jq's ~1s start-up once instead of three times is the rest of it.
# Treat every figure here as an UPPER BOUND measured under load: the same CPU runs the session being torn
# down, so a quiet machine is faster and a busy one slower. That is also why the cap below is generous
# rather than tuned to the measurement.
max_bytes=629145600

nudges=null
fired=null
legacy=null
compactions=null
status='ok'

if [ -z "$tx" ] || [ ! -f "$tx" ]; then
  status='transcript_not_found'
elif [ ! -r "$tx" ]; then
  status='transcript_unreadable'
else
  size=$(wc -c < "$tx" 2>/dev/null)
  [ -n "$size" ] || size=0
  if [ "$size" -gt "$max_bytes" ]; then
    status='bounded_out'
  else
    # ONE grep over three SELECTIVE patterns, then ONE jq that classifies each surviving record.
    #
    # The `fired` pattern keys on the COMMAND FIELD, not on the record type, and that is the whole
    # performance fix. It is deliberately form-independent: `.{0,120}` spans whatever sits between
    # `bash ` and the script name, so it matches whether the plugin root is the literal
    # ${CLAUDE_PLUGIN_ROOT} or an expanded absolute path. The bound stops it running away across a
    # multi-megabyte stdout and re-matching a record that merely MENTIONS the script.
    #
    # The prefilter is only an optimisation; jq below is what makes the count CORRECT. Verified on a real
    # transcript: a prefilter alone yields 256 where the structural filter yields 1, because hook_success
    # records quote the script name inside other hooks' stdout, and a tool-call record carries its own
    # `command` field too. Never loosen the jq side to speed this up.
    classified=$(grep -E '"type":"hook_additional_context"|"isCompactSummary":true|"command":"bash .{0,120}agy-anomaly-dispatch-reminder' "$tx" 2>/dev/null \
      | jq -r --arg s "$stamp" '
          if (.type=="attachment"
              and .attachment.type=="hook_additional_context"
              and (.attachment.hookEvent // "")=="PreToolUse"
              and (((.attachment.content // "") | tostring) | contains($s)))
            then "N " + (.uuid // "")
          elif (.type=="attachment"
              and .attachment.type=="hook_success"
              and (((.attachment.command // "") | tostring) | contains("agy-anomaly-dispatch-reminder")))
            then "F " + (.uuid // "")
          elif (.type=="attachment"
              and .attachment.type=="hook_additional_context"
              and (.attachment.hookEvent // "")=="PreToolUse"
              and (((.attachment.content // "") | tostring) | contains("AGY-ANOMALIES")))
            then "L " + (.uuid // "")
          elif (.isCompactSummary==true)
            then "C " + (.uuid // "")
          else empty end' 2>/dev/null | sort -u)

    # Counting DISTINCT uuids is what removes the measured duplication (bounded at 2x: 87 of 1314).
    # `.content | tostring` above handles both shapes a real transcript uses - the field is an ARRAY of
    # strings in practice and a bare string in some records.
    nudges=$(printf '%s\n'      "$classified" | grep -c '^N ')
    fired=$(printf '%s\n'       "$classified" | grep -c '^F ')
    legacy=$(printf '%s\n'      "$classified" | grep -c '^L ')
    compactions=$(printf '%s\n' "$classified" | grep -c '^C ')

    # A count that failed to produce a number is an UNKNOWN, not a zero.
    case "$nudges"      in ''|*[!0-9]*) nudges=null;      status='transcript_unreadable' ;; esac
    case "$legacy"      in ''|*[!0-9]*) legacy=null;      status='transcript_unreadable' ;; esac
    case "$fired"       in ''|*[!0-9]*) fired=null;       status='transcript_unreadable' ;; esac
    case "$compactions" in ''|*[!0-9]*) compactions=null; status='transcript_unreadable' ;; esac
  fi
fi

out="$root/.clavity"
mkdir -p "$out" 2>/dev/null || exit 0

jq -nc \
  --arg sid "$sid" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg reason "$reason" \
  --arg status "$status" \
  --argjson nudges "$nudges" \
  --argjson fired "$fired"   --argjson legacy "$legacy" \
  --argjson compactions "$compactions" \
  '{v:1, session_id:$sid, timestamp:$ts, reason:$reason,
    dispatch_nudges:$nudges, dispatch_nudges_unstamped:$legacy,
    dispatch_fired:$fired, compactions:$compactions,
    scan_status:$status}' >> "$out/discipline-reaching.jsonl" 2>/dev/null

exit 0

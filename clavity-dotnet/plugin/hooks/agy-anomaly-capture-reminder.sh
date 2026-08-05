#!/usr/bin/env bash
# AGY-ANOMALIES capture reminder (plugin-shipped). PreCompact(manual|auto): the CAPTURE side of the
# discipline, addressed to the MODEL. Its sibling agy-anomaly-reminder.sh is the DRAIN side, addressed to
# the OWNER at SessionStart. Before this hook, the discipline had a drain push and no capture push: a
# driver working DIRECTLY -- not dispatching -- that noticed a defect got nothing from any hook at any
# moment, because the capture contract lived only inside a skill it had to decide to pull unprompted, at
# exactly the moment its attention is elsewhere by construction.
#
# EMISSION = the JSON ENVELOPE on stdout at exit 0, and the envelope is EVENT-SPECIFIC.
# MEASURED by a three-arm sentinel: plain stdout at exit 0 reaches the model NOT AT ALL (silently
# discarded), and stdout at exit 2 is dropped too -- only stderr survives there. So a hook written with a
# bare printf of the text produces no error, no output, and looks installed and working.
# hookSpecificOutput is INVALID for PreCompact: Claude Code rejects the payload outright and the owner
# sees a schema-validation dump instead of the reminder. PreCompact must use top-level systemMessage.
# The same split is documented and implemented at agy-autotrain/hooks/agy-learn-reminder.sh:32-40.
#
# THE MESSAGE CARRIES NO BACKTICK, APOSTROPHE, DOUBLE QUOTE OR BACKSLASH. The first two are bash quoting
# hazards (a backtick inside a double-quoted string is command substitution; an apostrophe terminates a
# single-quoted one), and the last two would break the hand-built JSON envelope on the jq-absent path
# below, which has no escaping machinery. All four are asserted at BYTE level against the EMITTED text by
# scripts/tests/agy-anomaly-capture-reminder.Tests.ps1. Markdown decoration buys nothing inside a prompt
# string, so it is removed rather than escaped.
#
# Fail-open: any error -> exit 0. Suppressed by .no-agy (workspace or global) like every other reminder.
# Byte-identical across both driver plugins (kept honest by scripts/check-seed-artifacts-synced.sh).
set +e
input=$(cat)

# ONE definition, used by BOTH emission paths, so the jq-absent fallback can never drift from the
# jq-present one. A test asserts the two paths deliver a byte-identical string.
msg='AGY-ANOMALIES/1 check BEFORE COMPACTION: did you VERIFY a defect this session that is OUTSIDE your current task and is not yet in .clavity/local-anomalies.md? Capture it now via the open-issues skill - one line: - [type] fact * path:LINE * DATE * task=<what you were doing>. Uncaptured anomalies are lost at compaction. NOT an anomaly: a test you expected to fail, an error in the work you are actively doing, or anything you have not verified by measurement. If nothing qualifies, do nothing - a speculative entry is worse than none, because it lands on a blocking triage gate.'

# jq is needed only to read cwd out of the payload. Without it, STILL DELIVER: emit the same message in a
# hand-built envelope rather than exiting silently. A silent exit here is precisely the invisible zero
# this hook exists to remove -- and it is invisible in both directions, because an absent nudge and a
# nudge with nothing to say look identical from outside. Honor the kill-switch FIRST (agy-anomaly-reminder.sh
# records the defect this ordering prevents: a machine that simply has no jq otherwise gets an
# unsuppressable nudge forever). cwd is recovered from the RAW payload with a bash regex, so this path is
# no longer blind to the session's workspace -- it used to test "./.no-agy", the PROCESS cwd, which is not
# necessarily the workspace at all.
if ! command -v jq >/dev/null 2>&1; then
  [[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && cwd=${BASH_REMATCH[1]}
  # Raw recovery keeps the JSON escaping, hence the DOUBLE-backslash pattern - see the note at the jq path.
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
  printf '{"systemMessage":"%s"}\n' "$msg"
  exit 0
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)
# THE NORMALIZATION FORM MUST MATCH THE EXTRACTION SOURCE. jq -r DECODES the JSON escaping, so cwd holds
# SINGLE backslashes here and the pattern is one escaped backslash; the degraded branch above reads the RAW
# payload, where the DOUBLE backslashes survive, and needs ${cwd//\\\\//}. MEASURED 2026-08-05: the raw form
# applied to a jq-decoded value matches nothing and leaves the path untouched - a silent no-op that looks
# exactly like a working fix. Do NOT unify the two spellings.
cwd_path=${cwd//\\//}
[ -z "$cwd_path" ] && cwd_path="."

[ -f "$HOME/.claude/.no-agy" ] && exit 0

# Repo root by walking up for .git, in-shell, so a .no-agy at the REPO ROOT is honoured when the session
# was launched from a subdirectory. The normalization above is load-bearing: ${_d%/*} strips on "/" only.
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

jq -nc --arg m "$msg" '{systemMessage:$m}'
exit 0

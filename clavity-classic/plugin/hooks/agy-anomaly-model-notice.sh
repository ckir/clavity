#!/usr/bin/env bash
# AGY-ANOMALIES SessionStart notice, MODEL half. Its sibling agy-anomaly-reminder.sh is the OWNER half:
# stderr at exit 2, because at SessionStart there is no user turn and stdout is absorbed into the model
# context where the owner never sees it. That same property is why the OWNER half cannot also serve the
# model -- stdout on an exit-2 hook is DISCARDED (measured). Two channels, two hooks, one matcher object:
# a matcher object's hooks array may hold several commands and exit status is PER-HOOK, so both fire on
# exactly the same occasions.
#
# The MODEL is the one who does the triage, so it has to learn the work exists. Counting logic mirrors
# agy-anomaly-reminder.sh deliberately, including its in-shell repo-root walk and its bracketed-bullet
# entry pattern, so the two halves can never disagree about what is pending. (Cited by CONTENT, not by
# line: the previous ":41-45" and ":58-70" both went stale the moment the root resolution moved, and a
# wrong line number sends the next reader to unrelated code.) A test runs BOTH
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
# THE NORMALIZATION FORM MUST MATCH THE EXTRACTION SOURCE. jq -r DECODES the JSON escaping, so cwd holds
# SINGLE backslashes here and the pattern is one escaped backslash. A hook that recovers cwd from the RAW
# payload with [[ =~ ]] keeps the DOUBLE backslashes and needs ${cwd//\\\\//} instead. MEASURED 2026-08-05:
# using the raw form on a jq-decoded value matches nothing and leaves the path untouched - a silent no-op
# that looks exactly like a working fix. Do NOT unify the two spellings.
cwd_path=${cwd//\\//}
[ -z "$cwd_path" ] && cwd_path="."

# The GLOBAL opt-out does not depend on the repo root, so it is checked first and cheaply.
[ -f "$HOME/.claude/.no-agy" ] && exit 0

# Resolve the root BEFORE the workspace kill-switch, so an opt-out at the repo root is honoured from a
# subdirectory. This hook already needed the root to find the anomalies file; it is now resolved once,
# in-shell, and reused - rather than keeping a second `git rev-parse` idiom that could disagree with it
# on a worktree or submodule, where .git is a file rather than a directory. The normalization above is
# load-bearing: ${_d%/*} strips on "/" only, so an un-normalized Windows path breaks the walk at once.
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

f="$root/.clavity/local-anomalies.md"
[ -f "$f" ] || f="$cwd_path/.clavity/local-anomalies.md"
[ -f "$f" ] || exit 0

n=$(grep -c '^- \[[^]]*\]' "$f" 2>/dev/null)
rc=$?
# Unreadable is not "none", but this half must stay silent about it: the OWNER half already reports that
# case on stderr, and duplicating it here would put the same advisory on two channels.
if [ "$rc" -gt 1 ]; then exit 0; fi
[ -z "$n" ] && n=0
[ "$n" -eq 0 ] && exit 0

msg="AGY-ANOMALIES/1: $n untriaged in $f. Triage before new work via the open-issues skill: each entry is either PROMOTED to a tracked item with an owner, or DELETEd with a recorded reason. There is no parked state."
jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
exit 0

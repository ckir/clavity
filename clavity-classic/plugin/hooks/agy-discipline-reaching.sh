#!/usr/bin/env bash
# AGY-ANOMALIES discipline-reaching recorder (plugin-shipped). SessionEnd. CAPTURE ONLY, NO SUBPROCESSES.
# ROADMAP section 0 step 1a. Design + measurements: docs/superpowers/specs/2026-08-04-discipline-efficacy-design.md
#
# IT CAPTURES; IT DOES NOT ANALYSE. One small row naming the session and its transcript, then stop. All
# scanning happens later in scripts/discipline-reaching-report.ps1, which runs on demand with no time limit.
#
# WHY IT IS WRITTEN WITHOUT jq, date, OR git - MEASURED, TWICE, ON SHIPPED CODE.
# v17 scanned the transcript here and was CANCELLED at teardown, writing nothing. The scan moved out, but
# the rewritten hook still cost ~1,4-1,5s (2 jq starts at ~0,5s each, plus git) and was CANCELLED AGAIN on
# a real exit. The diagnostic probe that DID survive cost 1,24-1,39s. So ~1,4s is not "the surviving band",
# it is the EDGE of it - and a hook that SOMETIMES writes is worse than one that never does, because it
# turns a missing row into an unanswerable question.
# So every subprocess is gone: field extraction is bash regex, the timestamp is bash's own %()T, the repo
# root is an in-shell walk. Only mkdir remains, and only when the directory is absent.
#
# WHY RAW PASSTHROUGH IS SAFE - the trick that removes jq from the WRITE side too. The payload already
# holds each value JSON-ESCAPED. Copying that escaped text straight into the output re-emits it
# byte-for-byte, so nothing is unescaped and re-escaped - which is exactly where the previous version
# corrupted Windows paths (@tsv doubled every backslash). `[^"]*` is the correct extractor because a double
# quote is an ILLEGAL character in a Windows filename, so no value here can contain one.
#
# A NULL IS NOT A ZERO. No transcript named => a NAMED status, never a count of zero, and the row still
# lands. A missing row and a degraded row must never look alike.
#
# Fail-open: any error -> exit 0. Suppressed by .no-agy (workspace or global) like every other hook.
# Byte-identical across both driver plugins (kept honest by scripts/check-seed-artifacts-synced.sh).
set +e
export TZ=UTC

# `read -d ''` slurps the whole stream and is a BUILTIN - no fork, unlike $(cat). It returns non-zero at
# EOF while still having set the variable, hence the `|| true`-style bare call under `set +e`.
# NOT $(</dev/stdin): that works when stdin is a FILE but not reliably when it is a PIPE under MSYS, and
# a hook is always piped. Measured - the file-redirect form passed a hand test and then wrote NOTHING for
# all eight piped cases in the suite, which is exactly the silent failure this hook must never have.
IFS= read -r -d '' input

# Raw, still-escaped extraction. No jq: see the header. An absent field stays empty, which the status
# logic below treats as "not named" rather than as zero.
cwd=''; sid=''; reason=''; tx=''
[[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]             && cwd=${BASH_REMATCH[1]}
[[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]      && sid=${BASH_REMATCH[1]}
[[ $input =~ \"reason\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]          && reason=${BASH_REMATCH[1]}
[[ $input =~ \"transcript_path\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && tx=${BASH_REMATCH[1]}

# cwd is the only value used as a PATH here, so it is the only one that must be unescaped. The rest pass
# through still-escaped and are never touched.
cwd_path=${cwd//\\\\//}
[ -z "$cwd_path" ] && cwd_path="."

# The GLOBAL opt-out does not depend on the repo root, so it is checked first and cheaply.
[ -f "$HOME/.claude/.no-agy" ] && exit 0

# Repo root by walking up for .git, in-shell. `git rev-parse --show-toplevel` is more precise but costs a
# process start, and process COUNT is the entire budget here. A .git entry matches as a directory (normal
# clone) or a file (worktree/submodule).
root=$cwd_path
_d=$cwd_path
while [ -n "$_d" ] && [ "$_d" != "/" ] && [ "$_d" != "." ]; do
  if [ -e "$_d/.git" ]; then root=$_d; break; fi
  _p=${_d%/*}
  [ "$_p" = "$_d" ] && break
  [ -z "$_p" ] && break
  _d=$_p
done

# NO REPOSITORY, NO ROW. $root is reassigned ONLY when the walk finds a .git, so a .git under $root here is
# exactly equivalent to "the walk succeeded" - no flag variable is needed, and testing $cwd_path instead
# would reintroduce the subdirectory bug fixed directly below. A session outside any repo has no project to
# attribute reaching to, so the row would be unattributable anyway.
[ -e "$root/.git" ] || exit 0

# WORKSPACE OPT-OUT, CHECKED AFTER THE WALK - this is the fix. Checking only $cwd_path meant a .no-agy at
# the repo ROOT did not suppress a session launched in a SUBDIRECTORY, while the write below still landed
# in that root. MEASURED: cwd=repo/src with repo/.no-agy present WROTE a row; cwd=repo wrote nothing.
# Both paths are tested: a .no-agy in a subdirectory still suppresses that subdirectory.
if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
  exit 0
fi

if [ -n "$tx" ]; then status='deferred'; else status='transcript_not_found'; fi

# printf's %()T is a bash builtin - no `date` process. TZ=UTC above makes it UTC.
printf -v ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1

out="$root/.clavity"
[ -d "$out" ] || mkdir -p "$out" 2>/dev/null || exit 0

# v:2 is the CAPTURE shape. v:1 was the analyse-at-SessionEnd shape and SHIPPED in v17, so both can coexist
# on an upgraded machine; the report reads each by its own version. Values are emitted exactly as they
# arrived - already escaped - so no re-escaping step exists to get wrong.
printf '{"v":2,"session_id":"%s","timestamp":"%s","reason":"%s","transcript_path":"%s","scan_status":"%s"}\n' \
  "$sid" "$ts" "$reason" "$tx" "$status" >> "$out/discipline-reaching.jsonl" 2>/dev/null

exit 0

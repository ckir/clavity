#!/usr/bin/env bash
# AGY-ANOMALIES discipline-reaching recorder (plugin-shipped). SessionStart. CAPTURE ONLY, NO SUBPROCESSES.
# ROADMAP section 0 step 1a. Design + measurements: docs/superpowers/specs/2026-08-05-sessionstart-capture-design.md
#
# IT CAPTURES; IT DOES NOT ANALYSE. One small row naming the session and its transcript, then stop. All
# scanning happens later in scripts/discipline-reaching-report.ps1, which runs on demand with no time limit.
#
# WHY IT IS WRITTEN WITHOUT jq, date, OR git.
# NOT because of teardown pressure - that was a wrong diagnosis that cost three rounds. The real cause of
# the v17 failure was that ${CLAUDE_PLUGIN_ROOT} DOES NOT RESOLVE at SessionEnd (cancelled 3/3 with the
# variable at 20,9s / 1,5s / 0,6s; an absolute path from the same manifest worked 2/2 - one axis varied,
# the other never). Duration was a confound: a SLOWER hook registered elsewhere survived.
# The subprocess-free form is kept anyway on its own merits: a hook that runs at EVERY session start should
# be cheap, and the rewrite carries three fixes worth keeping - byte-exact Windows paths, CR stripping, and
# pipe-safe stdin.
#
# WHY RAW PASSTHROUGH IS SAFE - the trick that removes jq from the WRITE side too. The payload already
# holds each value JSON-ESCAPED. Copying that escaped text straight into the output re-emits it
# byte-for-byte, so nothing is unescaped and re-escaped - which is exactly where an earlier version
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
cwd=''; sid=''; src=''; model=''; tx=''
[[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]             && cwd=${BASH_REMATCH[1]}
[[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]      && sid=${BASH_REMATCH[1]}
[[ $input =~ \"source\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]          && src=${BASH_REMATCH[1]}
[[ $input =~ \"model\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]           && model=${BASH_REMATCH[1]}
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

# v:3 is the SessionStart capture shape. v:1 (analyse-at-SessionEnd) SHIPPED in v17 and v:2 (SessionEnd
# capture) exists on dev machines, so all three can coexist on an upgraded machine; the report reads each by
# its own version rather than guessing. Values are emitted exactly as they arrived - already JSON-escaped by
# the caller - so no re-escaping step exists to get wrong. `model` is recorded and deliberately NOT reported:
# capture is the irreversible half, and a field not written at session N cannot be recovered at N+1.
printf '{"v":3,"session_id":"%s","timestamp":"%s","source":"%s","model":"%s","transcript_path":"%s","scan_status":"%s"}\n' \
  "$sid" "$ts" "$src" "$model" "$tx" "$status" >> "$out/discipline-reaching.jsonl" 2>/dev/null

exit 0

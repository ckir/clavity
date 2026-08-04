#!/usr/bin/env bash
# AGY-ANOMALIES discipline-reaching recorder (plugin-shipped). SessionEnd. CAPTURE ONLY.
# ROADMAP section 0 step 1a: the MEASURE half. Design + every measurement behind it:
# docs/superpowers/specs/2026-08-04-discipline-efficacy-design.md
#
# IT CAPTURES; IT DOES NOT ANALYSE. This hook writes ONE small row naming the session and its transcript,
# and stops. All scanning and counting happens later, in scripts/discipline-reaching-report.ps1, which runs
# on demand with no time limit at all.
#
# WHY THE SPLIT EXISTS - MEASURED ON SHIPPED CODE, v17, TWICE.
# The first version scanned the transcript here, at SessionEnd. It worked in every unit test and in every
# direct invocation, and then FAILED IN PRODUCTION: `SessionEnd hook ... failed: Hook cancelled`, on two
# consecutive real session exits, writing NOTHING. The control that identifies the cause was a diagnostic
# probe registered on the SAME event in the SAME environment: it did no scanning, took milliseconds, and
# wrote its row successfully both times. Fast hook survives, multi-second hook is cancelled.
# ==> SESSION TEARDOWN GIVES A HOOK FAR LESS TIME THAN ITS DECLARED `timeout`, so a SessionEnd hook must do
# only trivial work. Nothing here may read the transcript, and no future edit may reintroduce that.
# The failure mode is the worst available: a cancelled hook writes NO row, which is indistinguishable from
# a session that never ran - the silent zero this entire item exists to remove.
#
# WHY DEFERRING LOSES NOTHING: transcripts persist on disk after a session ends, so the analysis the report
# performs later sees exactly what a scan here would have seen.
#
# A NULL IS NOT A ZERO. If the payload names no transcript, that is recorded as a NAMED status, not as a
# count of zero, and the row still lands. A missing row and a degraded row must never look alike.
#
# Fail-open: any error -> exit 0. Suppressed by .no-agy (workspace or global) like every other hook.
# Byte-identical across both driver plugins (kept honest by scripts/check-seed-artifacts-synced.sh).
set +e
input=$(cat)

# jq is required to parse the payload at all - without it we cannot learn the session id or the transcript
# path, so there is nothing to record. Exit silently. This is a known, accepted gap rather than a hidden
# one: a machine with no jq produces no rows, and the report counts rows RECORDED, never sessions RUN, so
# it can never mistake this for a measured zero.
command -v jq >/dev/null 2>&1 || exit 0

# ONE jq call for every field. MEASURED: each jq start-up costs ~0.5s on this machine, so the obvious
# field-per-call shape cost ~2,5s in total - and 2,5s is NOT safe here. The probe that provably SURVIVED
# teardown did ~1,3s of work; the multi-second version was cancelled. Startup COUNT is the cost driver at
# this size, not the parsing.
#
# ONE FIELD PER LINE, AND **NEVER** @tsv. MEASURED on the first real row this hook ever wrote: @tsv escapes
# backslashes, so a Windows transcript_path came back doubled (C:\Users\...) and the recorded row named a
# path that cannot resolve. The row landed and was USELESS. @tsv earns that escaping by surviving values
# containing tabs or newlines; none of these four fields ever contains one, while ALL of them routinely
# contain backslashes - the wrong trade for this data. Raw line-per-field output is byte-exact.
{
  read -r cwd
  read -r sid
  read -r reason
  read -r tx
} <<EOF
$(printf '%s' "$input" | jq -r '.cwd // ".", .session_id // "", .reason // "", .transcript_path // ""' 2>/dev/null)
EOF

# STRIP THE TRAILING CR. MEASURED: jq on Windows writes CRLF, so every value read above ends in a carriage
# return. This was INVISIBLE under the previous @tsv shape, where a single line put the CR only on the LAST
# field; one-field-per-line puts one on ALL of them - including cwd, which then made mkdir fail on a path
# with an embedded CR and the hook exit SILENTLY, writing no row at all. Parameter expansion is used rather
# than `tr -d` because process COUNT is the budget this hook is fighting.
cwd=${cwd%$'\r'}
sid=${sid%$'\r'}
reason=${reason%$'\r'}
tx=${tx%$'\r'}
[ -z "$cwd" ] && cwd="."

if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  exit 0
fi

# Repo root by walking up for .git, in-shell. `git rev-parse --show-toplevel` is more precise but costs
# another process start, and process COUNT is what this hook is fighting: the probe that provably survived
# teardown measured 1238-1389ms, and every subprocess here is ~200-400ms of that budget. A `.git` entry is
# matched as either a directory (normal clone) or a file (worktree/submodule), which covers the layouts
# this ships into. Fallback stays cwd, exactly as before, so a non-repo cwd behaves identically.
root="$cwd"
_d="$cwd"
while [ -n "$_d" ] && [ "$_d" != "/" ]; do
  if [ -e "$_d/.git" ]; then root="$_d"; break; fi
  _p=$(dirname "$_d" 2>/dev/null)
  [ "$_p" = "$_d" ] && break
  _d="$_p"
done

# `deferred` says the transcript is named and awaits analysis. `transcript_not_found` is the one verdict
# knowable HERE without touching the file, and it is recorded as a status rather than as zeroed counts.
if [ -n "$tx" ]; then status='deferred'; else status='transcript_not_found'; fi

out="$root/.clavity"
mkdir -p "$out" 2>/dev/null || exit 0

# v:2 is the CAPTURE shape. v:1 was the analyse-at-SessionEnd shape and SHIPPED in v17, so rows of both
# kinds can coexist in one file on an upgraded machine; the report reads each by its own version rather
# than guessing. That is exactly what this field was added for.
# The timestamp comes from jq (`now|todate`) rather than a `date` subprocess - one less process to start.
# JSON is built by jq, never by printf: a Windows transcript_path carries backslashes that a hand-built
# envelope would emit unescaped and corrupt.
jq -nc   --arg sid "$sid"   --arg reason "$reason"   --arg tx "$tx"   --arg status "$status"   '{v:2, session_id:$sid, timestamp:(now|todate), reason:$reason,
    transcript_path:$tx, scan_status:$status}' >> "$out/discipline-reaching.jsonl" 2>/dev/null

exit 0

#!/usr/bin/env bash
# Reset the clavity once-per-session driver-guidance flag on a genuine fresh start (spec section 5.C-C first-ask
# delivery). Clears ONLY on source==startup so the next session re-delivers; sweeps stale flags. Fail-open.
set +e

# PROCESS BUDGET (<=16 per run on Windows, ~200 ms each): `read` is a builtin, `$(cat)` is two processes.
# `read -d ''` returns non-zero at EOF but still fills $input; a trailing newline is kept, harmless since
# $input only feeds a regex and jq below.
# stdin: read -N needs bash >= 4.1; older bash (macOS /bin/bash 3.2) keeps the pre-Branch-20 read.
if [ -z "${CLAVITY_HOOK_BASH3:-}" ] && ((BASH_VERSINFO[0]*100+BASH_VERSINFO[1] >= 401)); then input=; while IFS= read -r -N 1048576 _c 2>/dev/null; do input+=$_c; done; input+=$_c; else input=$(cat 2>/dev/null); fi

# cwd is recovered from the RAW payload, not via jq: without jq the old code left cwd empty and tested
# an absolute "/.no-agy", an undeclared degraded path in which the kill-switch silently did nothing.
[[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && cwd=${BASH_REMATCH[1]}
cwd_path=${cwd//\\\\//}
[ -z "$cwd_path" ] && cwd_path="."

# WIDENED, NOT SWAPPED - both homes are checked. This hook tested `${HOME}` here while resolving the
# directory it DELETES FROM as `${USERPROFILE:-$HOME}` further down: the only hook in the tree that used
# two different answers to "which home", and the only one whose missed opt-out destroys state rather than
# printing a line. On a box where the two differ, the switch could be honoured in a place the deletion
# never looked. Checking BOTH can only make the switch fire more often, which is the safe direction for a
# kill switch; swapping one for the other would have moved the blind spot rather than closed it.
HOME_DIR="${USERPROFILE:-$HOME}"
[ -f "${HOME}/.claude/.no-agy" ] && exit 0
[ -f "${HOME_DIR}/.claude/.no-agy" ] && exit 0

# Repo root by walking up for .git, in-shell. Normalization above is load-bearing: ${_d%/*} strips on
# "/" only, so without it this loop breaks on its first iteration and root never leaves cwd.
root=$cwd_path
# ONE stat gates the walk. On an unreachable share EVERY level pays an SMB timeout - MEASURED
# 2026-08-06: 20314ms walking an unreachable //server/share/a/b/c vs 9282ms gated. Do NOT replace
# this with a "//" prefix test: WSL repos are LIVE UNC paths (\\wsl.localhost\<distro>\...) and
# such a test would silently disable the root walk for them.
if [ -d "$cwd_path" ]; then
  _d=$cwd_path
  while [ -n "$_d" ] && [ "$_d" != "/" ] && [ "$_d" != "." ]; do
    if [ -e "$_d/.git" ]; then root=$_d; break; fi
    # Stop at the UNC volume root - //server/.git is not a valid path and statting it costs
    # another network round-trip for a result that can never be a repo.
    case "$_d" in //*/*/*) ;; //*) break ;; esac
    _p=${_d%/*}
    [ "$_p" = "$_d" ] && break
    [ -z "$_p" ] && break
    _d=$_p
  done
fi

# This hook DELETES a flag file, so a missed opt-out destroys state rather than printing a line - and
# the session key defaults to 'default' (below), so the destroyed flag can belong to a concurrent
# opted-in session.
if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
  exit 0
fi

# Only reset on a genuine fresh start.
# jq runs only here (after every .no-agy exit, which never used $source); here-string, not a pipe.
source="$(jq -r '.source // empty' <<<"$input" 2>/dev/null)"
[ "$source" = "startup" ] || exit 0

DIR="${CLAVITY_GOLDEN_HEADER:-${HOME_DIR}/.clavity}"   # HOME_DIR resolved once, at the kill switch above
KEY="${CLAVITY_SESSION:-${AGY_SESSION:-default}}"
# Was `printf | tr -c 'A-Za-z0-9_-' '_'`. LC_ALL=C makes the pattern substitution per-BYTE like tr, so a
# multibyte character still becomes one '_' per byte, not one per character.
LC_ALL=C
SAFE="${KEY//[^A-Za-z0-9_-]/_}"

# Clear this session's flag so the first ask of the new session re-delivers.
rm -f "${DIR}/.active-drive-session-${SAFE}" 2>/dev/null
# Self-healing GC: sweep only GENUINELY STALE flags (older than 7 days). Do NOT sweep by -empty: active
# flags are 0-byte too (Task 3.2 writes an empty file), so an -empty sweep would delete a concurrent
# session's LIVE flag and wrongly re-deliver. Age-scoping leaves active/recent flags untouched.
find "${DIR}" -maxdepth 1 -name '.active-drive-session-*' -type f -mtime +7 -delete 2>/dev/null
exit 0

#!/usr/bin/env bash
# Reset the clavity once-per-session driver-guidance flag on a genuine fresh start (spec §5.C-C first-ask
# delivery). Clears ONLY on source==startup so the next session re-delivers; sweeps stale flags. Fail-open.
set +e

input="$(cat 2>/dev/null)"
source="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -f "${cwd}/.no-agy" ] && exit 0
[ -f "${HOME}/.claude/.no-agy" ] && exit 0

# Only reset on a genuine fresh start.
[ "$source" = "startup" ] || exit 0

HOME_DIR="${USERPROFILE:-$HOME}"
DIR="${CLAVITY_GOLDEN_HEADER:-${HOME_DIR}/.clavity}"
KEY="${CLAVITY_SESSION:-${AGY_SESSION:-default}}"
SAFE="$(printf '%s' "$KEY" | tr -c 'A-Za-z0-9_-' '_')"

# Clear this session's flag so the first ask of the new session re-delivers.
rm -f "${DIR}/.active-drive-session-${SAFE}" 2>/dev/null
# Self-healing GC: sweep only GENUINELY STALE flags (older than 7 days). Do NOT sweep by -empty: active
# flags are 0-byte too (Task 3.2 writes an empty file), so an -empty sweep would delete a concurrent
# session's LIVE flag and wrongly re-deliver. Age-scoping leaves active/recent flags untouched.
find "${DIR}" -maxdepth 1 -name '.active-drive-session-*' -type f -mtime +7 -delete 2>/dev/null
exit 0

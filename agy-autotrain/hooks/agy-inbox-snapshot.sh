#!/usr/bin/env bash
# agy-autotrain inbox snapshot (AT-2). Fires on PreToolUse(Skill); when the skill being invoked is
# agy-curate, copies the observations inbox to a timestamped .bak BEFORE the drain empties it.
# Fail-open: any error exits 0 and never blocks the skill. A hook is reliably INVOKED, not reliably
# EFFECTIVE - a failed copy warns on stderr rather than failing silently.
set +e

KEEP="${AGY_INBOX_SNAPSHOT_KEEP:-5}"          # how many slots to retain (tunable)
OBS="${CLAUDE_PLUGIN_ROOT}/knowledge/agy-observations.md"

input=$(cat 2>/dev/null)

# Opt-out marker, mirroring agy-curate-nudge.sh.
[ -f "$HOME/.claude/.no-agy" ] && exit 0

# Which skill is being invoked? jq is primary; without it fall back to a FIELD-BOUNDED grep on the
# skill value. Never a bare substring: another skill could merely MENTION agy-curate in its args.
skill=""
if command -v jq >/dev/null 2>&1; then
  skill=$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null)
  case "$skill" in
    *agy-curate) ;;
    *) exit 0 ;;
  esac
else
  printf '%s' "$input" | grep -Eq '"skill"[[:space:]]*:[[:space:]]*"[^"]*agy-curate"' || exit 0
fi

[ -f "$OBS" ] || exit 0

# --- Three stateless invariants. Their shared purpose: the ring must never destroy its own history. ---

# 1. STRUCTURAL: header and section must both be present.
grep -q '^# agy observations inbox' "$OBS" || exit 0
grep -q '^## Pending' "$OBS" || exit 0

# 2. CONTENT: at least one parseable bullet. The class set is assumption|heuristic|anti-pattern, so the
# character class MUST include the hyphen - [a-z]+ does not match anti-pattern, which was 42 of the 79
# entries in the last real corpus. With [a-z] a valid anti-pattern-only inbox reads as malformed and
# gets no snapshot at all.
grep -Eq '^- \[[a-z-]+\]' "$OBS" || exit 0

# 3. DEDUP: never rotate when content is identical to the newest snapshot. Without this an aborted or
# re-run agy-curate burns a slot each time, so a few retries silently evict the whole history. It also
# bounds persistent corruption to ONE slot instead of five.
latest=$(ls -1t "${OBS}".*.bak 2>/dev/null | head -n 1)
if [ -n "$latest" ] && cmp -s "$OBS" "$latest"; then exit 0; fi

stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null) || exit 0
if ! cp "$OBS" "${OBS}.${stamp}.bak" 2>/dev/null; then
  printf '%s\n' "[AGY-INBOX-SNAPSHOT] could not write ${OBS}.${stamp}.bak - the drain will run UNPROTECTED" >&2
  exit 0
fi

# FIFO prune: keep the newest $KEEP slots.
ls -1t "${OBS}".*.bak 2>/dev/null | tail -n +$((KEEP + 1)) | while IFS= read -r old; do
  rm -f "$old" 2>/dev/null
done

exit 0

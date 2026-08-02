#!/usr/bin/env bash
# agy-autotrain inbox snapshot (AT-2). Fires on PreToolUse(Skill); when the skill being invoked is
# agy-curate, copies the observations inbox to a timestamped .bak BEFORE the drain empties it.
# Fail-open: any error exits 0 and never blocks the skill. A hook is reliably INVOKED, not reliably
# EFFECTIVE - a failed copy warns on stderr rather than failing silently.
set +e

KEEP="${AGY_INBOX_SNAPSHOT_KEEP:-5}"          # how many slots to retain (tunable)
# VALIDATE IT. KEEP feeds `tail -n +$((KEEP + 1))`, and bash evaluates a non-numeric name as 0, so a
# typo ("abc"), a negative, or a literal 0 all become `tail -n +1` - which lists EVERY slot and deletes
# them all, including the snapshot taken moments earlier. The knob meant to size the ring would silently
# destroy it, fail-open and exit 0, exactly the outcome the invariants below exist to prevent.
case "$KEEP" in ''|*[!0-9]*) KEEP=5 ;; esac
[ "$KEEP" -lt 1 ] && KEEP=5
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
# Scope the search to the Pending section. Unscoped, a bullet anywhere in the file - header prose, a
# future template change, a hand-edit - satisfies an invariant that is supposed to mean "Pending has
# something worth saving". No such line exists in the current corpus, so this is hardening, not a live
# defect; the dedup invariant below would in any case bound the damage to one slot.
sed -n '/^## Pending/,$p' "$OBS" | grep -Eq '^- \[[a-z-]+\]' || exit 0

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

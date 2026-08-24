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
# ROADMAP 14g: the canonical inbox is USER-LOCAL, beside the golden-header files - NOT in the plugin
# tree, which exists in N copies with no way to tell which is live. CLAUDE_PLUGIN_ROOT is deliberately
# NOT consulted; snapshotting the wrong copy is worse than not snapshotting, because it reads as a
# backup of a file that was never drained. Pinned by a decoy in agy-inbox-snapshot.Tests.ps1.
HOME_DIR="${USERPROFILE:-$HOME}"
OBS="${HOME_DIR}/.clavity/agy-observations.md"

input=$(cat 2>/dev/null)

# Opt-out marker, mirroring agy-curate-nudge.sh.
# BOTH roots are checked on purpose, and the pair is load-bearing. The inbox path above resolves via
# ${USERPROFILE:-$HOME}, so a parent process that exports USERPROFILE WITHOUT HOME reads the inbox
# correctly yet looks for the opt-out marker at a path that cannot exist - silently DISARMING the kill
# switch. That is reachable, not theoretical: measured, `env -u HOME bash --noprofile --norc` leaves
# HOME empty and does NOT backfill it from USERPROFILE. A kill switch may only ever fail SAFE - toward
# silence - so widening the lookup can only honour an opt-out the operator actually asked for; it can
# never re-arm a hook they had silenced. Pinned by the USERPROFILE-vs-HOME control in the suite.
[ -f "${HOME_DIR}/.claude/.no-agy" ] && exit 0
[ -f "${HOME}/.claude/.no-agy" ] && exit 0

# WHICH invocation is this? Two payload shapes reach this hook and they carry different fields:
#   PreToolUse       -> .tool_input.skill  (the Skill tool was called)
#   UserPromptSubmit -> .prompt            (the user typed the slash command)
# The slash-command path is the one the defect was measured on: 2026-08-03, invoking the curator as
# /agy-autotrain:agy-curate produced NO new .bak, because PreToolUse never fires for it.
#
# The match is done HERE, in the script, and NOT with a declarative "matcher" regex in hooks.json.
# Nothing establishes that a matcher is evaluated against prompt text for UserPromptSubmit: the schema
# permits the key syntactically, but both first-party plugins that register this event do so BARE and
# inspect the prompt in their own script. Building on the matcher would be an unchecked assumption, and
# it would fail SILENTLY -- the hook would simply never fire, which is the defect this closes, restored.
matched=""
if command -v jq >/dev/null 2>&1; then
  skill=$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null)
  case "$skill" in *agy-curate) matched=1 ;; esac
  if [ -z "$matched" ]; then
    prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)
    # ANCHORED at the start and bounded at the end. An unanchored match fires on a prompt that merely
    # discusses the curator, which is not an invocation and must not burn a snapshot slot.
    case "$prompt" in
      /agy-autotrain:agy-curate|/agy-autotrain:agy-curate\ *) matched=1 ;;
      /agy-curate|/agy-curate\ *) matched=1 ;;
    esac
  fi
else
  # FIELD-BOUNDED, never a bare substring -- same reasoning as the jq path above.
  if printf '%s' "$input" | grep -Eq '"skill"[[:space:]]*:[[:space:]]*"[^"]*agy-curate"'; then
    matched=1
  elif printf '%s' "$input" | grep -Eq '"prompt"[[:space:]]*:[[:space:]]*"/(agy-autotrain:)?agy-curate([[:space:]][^"]*)?"'; then
    matched=1
  fi
fi
[ -z "$matched" ] && exit 0

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

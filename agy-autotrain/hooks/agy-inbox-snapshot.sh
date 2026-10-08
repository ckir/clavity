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
# Base-10, explicitly: a leading zero ("08") passes the digit check above, and bash then reads it as
# OCTAL in arithmetic - $((KEEP + 1)) aborts "value too great for base" (measured 2026-10-07), the
# prune never runs, and the ring grows without bound. 10# makes the knob mean what the operator typed.
KEEP=$((10#$KEEP))
[ "$KEEP" -lt 1 ] && KEEP=5
# ROADMAP 14g: the canonical inbox is USER-LOCAL, beside the golden-header files - NOT in the plugin
# tree, which exists in N copies with no way to tell which is live. CLAUDE_PLUGIN_ROOT is deliberately
# NOT consulted; snapshotting the wrong copy is worse than not snapshotting, because it reads as a
# backup of a file that was never drained. Pinned by a decoy in agy-inbox-snapshot.Tests.ps1.
HOME_DIR="${USERPROFILE:-$HOME}"
OBS="${HOME_DIR}/.clavity/agy-observations.md"

# BUILTIN, not $(cat): no fork, and under an empty PATH nothing is written to stderr (the section-59
# shape; same idiom as agy-anomaly-reminder.sh:37). read -d '' returns non-zero at EOF while still
# having filled $input - a bare call under set +e.
IFS= read -r -d '' input

# Opt-out marker. NOT a full mirror of agy-curate-nudge.sh, and the difference is deliberate: that
# hook also honours a `.no-agy` in the payload's cwd, this one does not read `.cwd` at all. It fires
# on PreToolUse/UserPromptSubmit, where cwd does not carry the same meaning it has on SessionStart.
# The asymmetry is PINNED by 'is NOT disarmed by a .no-agy in the payload cwd' in
# scripts/tests/agy-inbox-snapshot.Tests.ps1 - so if it is ever made to match, that test reds and the
# change has to be deliberate. The previous wording claimed a mirror that did not exist, which would
# have sent a maintainer doing a consistency pass in exactly the wrong direction.
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
# ONE classifier, no jq and no grep - the raw payload already decides. JSON escaping is what makes the
# raw match safe (Branch 20, measured): a "skill" or "prompt" KEY smuggled inside a value arrives as
# \"skill\" - the backslash breaks the match - so only the real top-level/tool_input field can fire.
# FIELD-BOUNDED and, for the prompt, ANCHORED at the start and bounded at the end - same reasoning as
# the jq branch this replaces: a prompt that merely discusses the curator must not burn a slot.
matched=""
re_skill='"skill"[[:space:]]*:[[:space:]]*"[^"]*agy-curate"'
re_prompt='"prompt"[[:space:]]*:[[:space:]]*"/(agy-autotrain:)?agy-curate([[:space:]][^"]*)?"'
if [[ $input =~ $re_skill ]] || [[ $input =~ $re_prompt ]]; then matched=1; fi
[ -z "$matched" ] && exit 0

[ -f "$OBS" ] || exit 0

# --- Three stateless invariants. Their shared purpose: the ring must never destroy its own history. ---

# 1. STRUCTURAL: header and section must both be present (checked in the one builtin pass below).

# 2. CONTENT: at least one parseable bullet. The class set is assumption|heuristic|anti-pattern, so the
# character class MUST include the hyphen - [a-z]+ does not match anti-pattern, which was 42 of the 79
# entries in the last real corpus. With [a-z] a valid anti-pattern-only inbox reads as malformed and
# gets no snapshot at all.
# Scope the search to the Pending section. Unscoped, a bullet anywhere in the file - header prose, a
# future template change, a hand-edit - satisfies an invariant that is supposed to mean "Pending has
# something worth saving". No such line exists in the current corpus, so this is hardening, not a live
# defect; the dedup invariant below would in any case bound the damage to one slot.
# THE THIRD READER OF THIS SECTION, and until 2026-08-26 the only one with NO close rule at all: this
# scanned from the heading to END OF FILE, so a `- [x]` bullet in any later section - the append-only
# drain log lives down there - read as a pending entry and armed the snapshot for an inbox that had none.
# Same open and close rules as drain-lib.ps1's canonical reader and as agy-curate-nudge.sh.
# One builtin pass for invariants 1 and 2. Open/close rules match the canonical reader (drain-lib.ps1) and
# agy-curate-nudge.sh: open on '^##[ \t]+Pending[ \t]*$' (REAL tab - grep's bracket [ \t] matched literal
# 't'/'\' and disagreed with the awk it gated, measured 2026-10-07), close on any '^#+[ \t]' heading. The
# bullet class keeps the hyphen: anti-pattern must match.
hdr=0; pend=0; bullet=0; p=0
re_pending=$'^##[ \t]+Pending[ \t]*$'
re_close=$'^#+[ \t]'
re_bullet='^- \[[a-z-]+\]'
while IFS= read -r line || [ -n "$line" ]; do
  # A CRLF inbox (a Windows editor, a PowerShell drain) leaves a CR on every line, and the `$` in re_pending then never matches.
  # The pre-branch `grep -Eq` tolerated it on MSYS; a builtin `=~` does not (test-audit B21 R1, BS-1: old hook 1 .bak, this one 0).
  line=${line%$'\r'}
  case "$line" in '# agy observations inbox'*) hdr=1 ;; esac
  if [[ $line =~ $re_pending ]]; then p=1; pend=1; continue; fi
  if [[ $line =~ $re_close ]]; then p=0; continue; fi
  if [ "$p" -eq 1 ] && [[ $line =~ $re_bullet ]]; then bullet=1; fi
done 2>/dev/null < "$OBS"
[ "$hdr" -eq 1 ] || exit 0
[ "$pend" -eq 1 ] || exit 0
[ "$bullet" -eq 1 ] || exit 0

# 3. DEDUP: never rotate when content is identical to the newest snapshot. Without this an aborted or
# re-run agy-curate burns a slot each time, so a few retries silently evict the whole history. It also
# bounds persistent corruption to ONE slot instead of five.
# ONE listing, BEFORE the copy, serving BOTH consumers (fork 1C, owner-ruled 2026-10-07): its first
# entry is the dedup comparand, and - because the snapshot written below is strictly newest - the
# prune's surplus is exactly this OLD list from index KEEP-1 on. mtime order is kept deliberately
# (1B name-order was rejected: a hand-copied .bak or a moved clock would change which slot dies).
# bash-3-safe array fill: no mapfile.
baks=()
while IFS= read -r _b; do [ -n "$_b" ] && baks+=("$_b"); done < <(ls -1t "${OBS}".*.bak 2>/dev/null)
if [ "${#baks[@]}" -gt 0 ] && cmp -s "$OBS" "${baks[0]}"; then exit 0; fi

if [ -z "${CLAVITY_HOOK_BASH3:-}" ] && ((BASH_VERSINFO[0]*100+BASH_VERSINFO[1] >= 402)); then
  printf -v stamp '%(%Y%m%d-%H%M%S)T' -1 2>/dev/null
else
  stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null)
fi
[ -n "$stamp" ] || exit 0
if ! cp "$OBS" "${OBS}.${stamp}.bak" 2>/dev/null; then
  printf '%s\n' "[AGY-INBOX-SNAPSHOT] could not write ${OBS}.${stamp}.bak - the drain will run UNPROTECTED" >&2
  exit 0
fi

# FIFO prune, ONE rm for every surplus slot (fork 1A): after the cp there are ${#baks[@]}+1 slots;
# keep the newest $KEEP. 16 per-file rm processes (32 spawns) could never fit the 16-process ceiling.
# NEVER the file just written (panel R2, State Corruptor): two snapshots in the SAME second share a name, so
# the cp above overwrote a slot that is already in the pre-copy list - and with KEEP=1 the surplus slice starts
# at index 0, which would delete the fresh snapshot. The old `ls -1t | tail` re-listed AFTER the copy and kept it.
if [ "${#baks[@]}" -ge "$KEEP" ]; then
  surplus=()
  for _b in "${baks[@]:$((KEEP - 1))}"; do
    [ "$_b" = "${OBS}.${stamp}.bak" ] || surplus+=("$_b")
  done
  [ "${#surplus[@]}" -gt 0 ] && rm -f -- "${surplus[@]}" 2>/dev/null
fi

exit 0

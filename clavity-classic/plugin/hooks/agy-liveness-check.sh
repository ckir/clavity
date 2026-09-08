#!/usr/bin/env bash
# AGY-DISCIPLINES liveness/degradation notice (plugin-shipped, SP-D / spec Decision 3). SessionStart(startup):
# the agy-driving disciplines auto-fire only when superpowers is installed+enabled; if it is not -- or a
# .no-agy kill-switch is suppressing them -- the user must be told LOUDLY at boot, else the disciplines die
# silently. This is the ONE boot-time liveness surface (superpowers presence + .no-agy state + jq guard).
#
# EMISSION = the JSON ENVELOPE on stdout at exit 0, carrying `systemMessage`. This hook used stderr +
# `exit 2` until ROADMAP section 31, reasoning that stdout at SessionStart is absorbed into the model's
# context where the USER -- the one who has to act on the notice -- never sees it. THAT HALF WAS RIGHT
# ABOUT PLAIN STDOUT AND WRONG ABOUT THE ENVELOPE, and it is the same error, in the same words, that
# agy-anomaly-reminder.sh corrected on 2026-09-04: `systemMessage` is a USER-visible surface, while a
# non-zero SessionStart hook renders as a red "SessionStart:<source> hook error". So the old contract
# displayed every routine notice as a FAILING PLUGIN.
#
# ITS WORST INSTANCE WAS THE KILL-SWITCH ITSELF: `.no-agy` is the documented way to ask this plugin for
# quiet, and asking was what produced the red error -- at every single session start, forever. MEASURED
# 2026-09-08 with a control pair in a throwaway repo: with `.no-agy` present, exit 2 and a stderr line;
# with it removed, exit 0 and silence.
#
# WHICH SURFACE EACH NOTICE EARNS, settled by AGY-NEGOTIATE 2026-09-08. The criterion is not "is this
# true" but "does it demand an immediate corrective action from the OWNER":
#   an ACTIONABLE FAULT  - superpowers not live, jq missing, a personal hook overriding a shipped one -
#                          earns the owner's screen: `systemMessage` AND `additionalContext`.
#   a CHOSEN STATE       - `.no-agy` is present - earns `additionalContext` ONLY. It reports something
#                          the owner decided and cannot "fix" except by undoing their own decision, so
#                          announcing it at every start is noise by construction, and a boot notice that
#                          demands nothing trains people to stop reading the ones that do.
# NOTHING IS TRADED AWAY: the model still receives the suppressing PATH at boot, so "why are the
# disciplines not firing?" is answerable exactly. The alternative considered and rejected was total
# silence, which loses that. Both halves of the .no-agy decision were argued out with the peer and
# neither of us started where we ended.
#
# EXIT-CODE CONTRACT: every reachable end-state now exits 0, and stderr is never written. (1) healthy /
# superpowers live AND sole hook ownership -> exit 0, NO output at all; (2) an ACTIONABLE FAULT -> ONE
# envelope carrying both keys; (3) `.no-agy` with no override -> ONE envelope carrying additionalContext
# ONLY, so the owner sees nothing; (4) a shipped hook ALSO registered personally -> the ownership line
# reaches the owner even under .no-agy (D1 constraint 5), deliberately, so the kill-switch cannot hide an
# override - it rides in that SAME envelope rather than a second one, because a hook gets one stdout and
# a second JSON object on it would not parse.
# `set +e` is the fail-open guard: a mid-detection command failure does not abort the hook,
# it continues to the not-live advisory (exit 2) -- non-blocking for SessionStart and fail-toward-loud, the
# posture Decision 3 wants (a soft advisory beats a silent swallow for a liveness hook). NO blanket
# `trap ... ERR` -- it would swallow the settings-parse path and drop the advisory. The ONLY silent outcome is (1).
# Byte-identical across both driver plugins (kept honest by the seed-sync gate).
set +e
input=$(cat)

# --- jq guard. jq is needed to merge settings. Without it, honor the kill-switch (global + the session's
# REAL workspace, recovered from the raw payload) then emit ONE loud dep warning (never silent; we cannot
# do the superpowers check without jq). The old form tested "./.no-agy", the PROCESS cwd, which need not
# be the workspace - and it announced that literal string as the suppressing path whether or not it was. ---
if ! command -v jq >/dev/null 2>&1; then
  # Raw recovery keeps the JSON escaping, hence the DOUBLE-backslash pattern - see the note at the jq path.
  [[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && cwd=${BASH_REMATCH[1]}
  cwd_path=${cwd//\\\\//}
  [ -z "$cwd_path" ] && cwd_path="."
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
  # ROADMAP section 31, the cries-wolf class. These paths used stderr + `exit 2`. A non-zero SessionStart
  # hook renders as a RED "SessionStart:<source> hook error", so a routine notice was displayed as a
  # FAILING PLUGIN at every start - the identical defect agy-anomaly-reminder.sh was rewritten to end on
  # 2026-09-04, still live here because the fix was applied per-FILE rather than per-CLASS.
  #
  # Every message this hook used to emit, it still emits, under the same condition and with the same
  # text. What changed is the exit code, the stream, and - for the kill-switch alone - WHICH SURFACE it
  # reaches: see the surface criterion in the header. The folded defect about naming the ROOT `.no-agy`
  # path rather than the cwd one is therefore untouched and still pinned; the path is simply carried to
  # the model rather than announced to the owner.
  # ESCAPE BY HAND HERE, because this is the branch where jq is MISSING and the one value interpolated
  # into the envelope is a PATH - the only value in these messages that can legitimately carry a
  # backslash or a quote. `cwd_path` above already folds backslashes to forward slashes, so today no
  # shipped path reaches this, but a hook that emits malformed JSON fails in a way nobody can read.
  # Backslash FIRST, then quote: the other order would re-escape the backslash it just inserted.
  # CONTROL CHARACTERS ARE STRIPPED, NOT ESCAPED, and the capstone caught that they were neither. JSON
  # forbids a raw byte below 0x20 inside a string, so a path carrying a newline or a tab would emit an
  # envelope nothing can parse - and this is the branch with no jq to encode it properly. Escaping them
  # by hand would mean emitting \uXXXX from pure bash for a case no shipped path can reach; deleting
  # them keeps the envelope WELL-FORMED and the message merely less pretty, which is the right trade for
  # a degraded path whose entire job is to still say something.
  _json() { _v=${1//\\/\\\\}; _v=${_v//\"/\\\"}; _v=$(printf '%s' "$_v" | tr -d '\000-\037'); printf '%s' "$_v"; }
  # MODEL-ONLY, exactly as on the jq path: no `systemMessage` key, so the owner's terminal stays clean
  # while the model still learns the suppressing path. The degraded branch must not diverge from the
  # main one on WHO gets told - only on how the JSON is built.
  if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
    _s="$root/.no-agy"; [ -f "$_s" ] || _s="$cwd_path/.no-agy"
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"[AGY-DISCIPLINES] suppressed by .no-agy at %s"}}\n' "$(_json "$_s")"
    exit 0
  fi
  if [ -f "$HOME/.claude/.no-agy" ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"[AGY-DISCIPLINES] suppressed by .no-agy at %s"}}\n' "$(_json "$HOME/.claude/.no-agy")"
    exit 0
  fi
  # THE ENVELOPE IS BUILT WITH printf HERE, NOT jq, because this is the branch where jq is MISSING - a
  # message that needs jq to report that jq is absent could never be delivered. The text is a fixed
  # literal with no interpolation, so there is nothing in it that needs escaping.
  printf '%s\n' '{"systemMessage":"[AGY-DISCIPLINES] guard inactive: missing jq - cannot verify the disciplines will auto-fire; install jq"}'
  exit 0
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)

# THE NORMALIZATION FORM MUST MATCH THE EXTRACTION SOURCE. jq -r DECODES the JSON escaping, so cwd holds
# SINGLE backslashes here and the pattern is one escaped backslash; the degraded branch below reads the RAW
# payload, where the DOUBLE backslashes survive, and needs ${cwd//\\\\//}. MEASURED 2026-08-05: the raw form
# applied to a jq-decoded value matches nothing and leaves the path untouched - a silent no-op that looks
# exactly like a working fix. Do NOT unify the two spellings.
#
# Resolved HERE, above proj_dir, rather than just above the kill-switch: the walk needs the normalized
# value, and defining it late would leave proj_dir the only place in the file reading a raw $cwd.
cwd_path=${cwd//\\//}
[ -z "$cwd_path" ] && cwd_path="."

# Repo root by walking up for .git, in-shell, so a .no-agy at the REPO ROOT is honoured when the session
# was launched from a subdirectory. The normalization above is load-bearing: ${_d%/*} strips on "/" only.
# NOTE: $root is for the .no-agy check ONLY. It must not become the basis for proj_dir - CLAUDE_PROJECT_DIR
# and the session cwd are the contract for locating settings.json, not git-toplevel.
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

# --- superpowers enabled-check across Claude Code's settings hierarchy (more-specific scope wins per plugin
# key): project-local > project > user. Read ONLY files that exist (a missing settings file at a scope is
# NORMAL, not a not-live signal). superpowers is live iff the merged enabledPlugins has a key matching
# ^superpowers@ resolving to true (PREFIX match; the marketplace suffix is not guaranteed). Absent / false /
# corrupt-present -> the possibility-framed advisory (fail-toward-loud). ---
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
proj_dir="${CLAUDE_PROJECT_DIR:-$cwd_path}"
user_settings="$config_dir/settings.json"
proj_settings="$proj_dir/.claude/settings.json"
local_settings="$proj_dir/.claude/settings.local.json"

# Precedence: user (lowest) first, project-local (highest) last, so the later deep-merge overrides per key.
present=()
for f in "$user_settings" "$proj_settings" "$local_settings"; do
  [ -f "$f" ] && present+=("$f")
done

# --- D1 ownership: a hook this plugin ships must not ALSO be registered personally, or it double-fires.
# The shipped-hook list is derived at runtime from our own hooks.json -- a hardcoded list would fall out of
# sync the first time someone adds a hook, and the tests would keep passing. An unreadable hooks.json is
# reported, never treated as "no shipped hooks" (that would fail the check open). Each settings file is read
# independently: an unreadable one is named and the sweep CONTINUES, so a typo in a project file cannot mask
# a real duplicate in the user file. A settings file with no .hooks node is normal (fresh install) and silent.
ownership_note=""
shipped_json="$(dirname "$0")/hooks.json"
# Tokenizing happens INSIDE jq, which is already parsing the file. A printf|grep|tr|sort pipeline costs
# four extra processes, and this hook runs on every SessionStart: measured on Windows, bash itself is
# ~455ms and each additional fork ~126ms, so the pipeline form cost ~440ms EVERY time it ran -- once for
# this list plus once per settings file. Doing it in jq removes those forks entirely. Safe to word-split
# the result below: jq has already reduced it to names matching [a-z0-9._-]+\.sh, which cannot contain a
# glob character.
if ! shipped_names=$(jq -r '[.hooks[][].hooks[].command // empty | ascii_downcase | scan("[a-z0-9._-]+\\.sh")] | unique | join(" ")' "$shipped_json" 2>/dev/null); then
  ownership_note="[AGY-DISCIPLINES] shipped-hook list unreadable ($shipped_json) - cannot check hook ownership"
else
  for f in "${present[@]}"; do
    # TWO distinct failures, deliberately NOT merged into one message. A file that will not parse and a
    # file that parses but whose .hooks shape we no longer recognise are different problems with different
    # fixes, and collapsing them re-creates exactly what constraint 3 forbids: an empty result that is
    # indistinguishable from a query that no longer matches anything.
    if ! jq -e . "$f" >/dev/null 2>&1; then
      ownership_note="${ownership_note}[AGY-DISCIPLINES] settings unreadable ($f) - ownership not checked for it"$'\n'
      continue
    fi
    # ONE jq call yields the two shape counters AND the tokenized hook names, on ONE line, so `read`
    # splits it unambiguously with no fork. Emitting them as two LINES looked tidier but is a trap: when
    # the names are empty jq's second line is empty, command substitution strips the trailing newline,
    # and "${var#*$'\n'}" then finds no newline and returns the WHOLE string -- silently assigning the
    # counters to the names variable. It happened to stay harmless only because a shipped name can never
    # be a bare integer. One line plus `read -r a b rest` has no such edge.
    if ! personal_raw=$(jq -r '(.hooks // {}) as $h
                               | [$h[][].hooks[]]              as $entries
                               | [$entries[].command // empty] as $cmds
                               | "\($entries | length) \($cmds | length) \([$cmds[] | ascii_downcase | scan("[a-z0-9._-]+\\.sh")] | unique | join(" "))"' "$f" 2>/dev/null); then
      ownership_note="${ownership_note}[AGY-DISCIPLINES] schema unrecognised ($f) - .hooks is present but not the shape this check reads; ownership NOT verified for it"$'\n'
      continue
    fi
    read -r entry_count cmd_count personal <<<"$personal_raw"
    # Hook entries EXIST but not one carries a 'command' field -> the host renamed the key under us.
    # Staying silent here would be indistinguishable from "no collisions found", which is precisely the
    # fail-open the hooks.json guard above exists to prevent. A shape we no longer read is reported, not
    # treated as an empty result. (Some entries lacking 'command' is normal and stays silent; ALL of
    # them lacking it, with entries present, is not.)
    if [ "${entry_count:-0}" -gt 0 ] && [ "${cmd_count:-0}" -eq 0 ]; then
      ownership_note="${ownership_note}[AGY-DISCIPLINES] schema unrecognised ($f) - hook entries are present but none carries a 'command' field; ownership NOT verified for it"$'\n'
      continue
    fi
    # Compare script-name TOKENS, not substrings of the joined command blob. Substring matching both
    # OVER-fires (a longer name that merely CONTAINS a shipped name -- which is exactly the rename-and-trim
    # escape hatch the README prescribes, so it punished the documented fix) and UNDER-fires (a name
    # differing only in case, which on Windows/macOS is the SAME file the host will happily double-fire).
    # Space-pad both sides so a match is a WHOLE token, and fold case so a case-insensitive filesystem
    # cannot hide a collision. "$shipped" is quoted: unquoted it word-splits AND glob-expands against
    # the session's cwd, so a glob character in our own hooks.json could pull in unrelated local .sh files.
    personal_names=" $personal "
    for name in $shipped_names; do
      case "$personal_names" in
        *" $name "*) ownership_note="${ownership_note}[AGY-DISCIPLINES] $name is shipped by this plugin AND registered in $f - remove that registration, then restart or /clear this session"$'\n' ;;
      esac
    done
  done
fi

# --- .no-agy kill-switch: announce LOUDLY (naming the path) then STOP. NOT a silent early-exit (that
# reintroduces the silent-kill Decision 3 forbids); NOT a fall-through to the superpowers/jq notices (that
# would triple-spam one boot). One announce, then exit. ---
# ROADMAP section 31, the cries-wolf class. Every exit below used stderr + `exit 2`, which Claude Code
# renders as a RED "SessionStart:<source> hook error" - so this hook reported a HEALTHY, deliberately
# suppressed install as a broken plugin. agy-anomaly-reminder.sh was rewritten off that mechanism on
# 2026-09-04; this file was missed because the fix was applied per-FILE rather than per-CLASS, and the
# worst instance was the kill-switch: asking for silence was itself what produced the red error.
# _emit <user-visible text, may be EMPTY> <model text>
#
# THE TWO SURFACES ARE ADDRESSED SEPARATELY, and that is the whole point. MEASURED 2026-09-04, recorded
# at agy-anomaly-reminder.sh:16-23: `systemMessage` is what the OWNER sees; `hookSpecificOutput.
# additionalContext` is what the MODEL receives; plain stdout reaches neither.
#
# AN EMPTY FIRST ARGUMENT OMITS THE systemMessage KEY ENTIRELY, so the notice still reaches the model
# while the owner's terminal stays clean. That is what lets a fact be DIAGNOSTIC without being an ALERT.
# jq owns the escaping: these strings carry paths and the ownership note's own newlines.
_emit() {
  if [ -n "$1" ]; then
    jq -nc --arg u "$1" --arg m "$2" '{systemMessage:$u,hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
  else
    jq -nc --arg m "$2" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
  fi
  exit 0
}

if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  # THREE candidates now, so the reported path must be chosen from three. The old two-way fallback named
  # "$cwd/.no-agy" - a file that does not exist - whenever the REPO ROOT was the reason for suppression,
  # which is a defect in the one hook whose whole job is to say truthfully why the disciplines are off.
  suppressed="$root/.no-agy"
  [ -f "$suppressed" ] || suppressed="$cwd_path/.no-agy"
  [ -f "$suppressed" ] || suppressed="$HOME/.claude/.no-agy"
  _m="[AGY-DISCIPLINES] suppressed by .no-agy at $suppressed"
  # Constraint 5: ownership is reported EVEN under the kill-switch. A gate the policed party can switch
  # off is not a gate -- otherwise .no-agy plus a kept personal registration hides an override entirely.
  # ONE envelope carries both, because a hook gets one stdout and a second JSON object would not parse.
  [ -n "$ownership_note" ] && _m="$_m
$ownership_note"
  # THE SUPPRESSION NOTICE GOES TO THE MODEL ONLY. Settled by AGY-NEGOTIATE 2026-09-08, on a criterion
  # worth more than this one line: a boot-time notice earns the OWNER'S SCREEN only if it demands an
  # immediate corrective action. `.no-agy` demands none - it reports a state the owner chose and cannot
  # "fix" except by undoing their own decision - so announcing it at every start is noise by construction
  # and trains them to stop reading boot output, which is the same cries-wolf failure section 31 exists
  # to end, in a gentler colour.
  #
  # NOTHING IS TRADED AWAY, which is why this beats the plain silence I first wrote and reverted: the
  # MODEL still receives the path at boot, so "why are the disciplines not firing?" is answerable
  # immediately and exactly. The diagnostic survives; only the interruption goes.
  #
  # OWNERSHIP STILL REACHES THE OWNER because it DOES demand action - a personal registration of a
  # shipped hook is a live override, not a preference. So the user-visible argument is the ownership
  # note ALONE, and it is empty (hence no systemMessage key at all) whenever there is no override.
  _emit "$ownership_note" "$_m"
fi

live=0
if [ "${#present[@]}" -gt 0 ]; then
  if result=$(jq -s 'map(.enabledPlugins // {}) | reduce .[] as $m ({}; . * $m)
                     | to_entries | any(.[]; (.key | startswith("superpowers@")) and .value)' \
              "${present[@]}" 2>/dev/null) && [ "$result" = "true" ]; then
    live=1
  fi
fi

if [ "$live" = "1" ]; then
  [ -n "$ownership_note" ] && _emit "$ownership_note" "$ownership_note"
  exit 0   # healthy install AND sole ownership: SILENT
fi

# Not live: superpowers not detected as enabled (absent, disabled, corrupt settings, or CC changed the
# settings shape). Emit the advisory as a POSSIBILITY, never "disabled" as a certainty.
_msg="[AGY-DISCIPLINES] superpowers not detected as enabled - the agy disciplines will not auto-fire. Install/enable superpowers, or invoke agy-first / agy-capstone manually."
# Ownership is reported here too (same constraint-5 reasoning): a corrupt settings file elsewhere in the
# merge can drive live=0 (jq -s refuses to parse a bad file), which must not swallow an ownership finding
# already collected from a settings file that WAS readable. Both findings go in ONE envelope, because a
# hook gets one stdout and a second JSON object on it would not parse.
[ -n "$ownership_note" ] && _msg="$_msg
$ownership_note"
_emit "$_msg" "$_msg"

#!/usr/bin/env bash
# AGY-DISCIPLINES liveness/degradation notice (plugin-shipped, SP-D / spec Decision 3). SessionStart(startup):
# the agy-driving disciplines auto-fire only when superpowers is installed+enabled; if it is not -- or a
# .no-agy kill-switch is suppressing them -- the user must be told LOUDLY at boot, else the disciplines die
# silently. This is the ONE boot-time liveness surface (superpowers presence + .no-agy announce + jq guard).
#
# EMISSION = stderr + `exit 2`. For a SessionStart hook that is the ONLY documented USER-visible surface: the
# stderr renders in the transcript and execution CONTINUES (exit 2 is non-blocking for SessionStart, unlike
# PreToolUse). additionalContext/stdout would be injected into Claude's CONTEXT only and silently absorbed at
# boot (no user turn) -- the silent-drop Decision 3 forbids.
#
# EXIT-CODE CONTRACT: (1) healthy / superpowers live AND sole hook ownership -> exit 0, no stderr; (2) a
# DETECTION OUTCOME warranting a notice (superpowers not-live incl. corrupt/unreadable settings, .no-agy
# active, or jq missing) -> the line on stderr + exit 2; (3) a shipped hook ALSO registered personally, or
# an unreadable settings/hooks.json blocking that check -> the ownership line on stderr + exit 2. State (3)
# is reported even under .no-agy (D1 constraint 5) -- deliberately, so the kill-switch cannot hide an
# override. Every reachable end-state is one of those three explicit exits.
# `set +e` is the fail-open guard: a mid-detection command failure does not abort the hook,
# it continues to the not-live advisory (exit 2) -- non-blocking for SessionStart and fail-toward-loud, the
# posture Decision 3 wants (a soft advisory beats a silent swallow for a liveness hook). NO blanket
# `trap ... ERR` -- it would swallow the settings-parse path and drop the advisory. The ONLY silent outcome is (1).
# Byte-identical across both driver plugins (kept honest by the seed-sync gate).
set +e
input=$(cat)

# --- jq guard. jq is needed to parse cwd + merge settings. Without it, honor the kill-switch (global +
# process cwd) then emit ONE loud dep warning (never silent; we cannot do the superpowers check without jq). ---
if ! command -v jq >/dev/null 2>&1; then
  if [ -f "./.no-agy" ]; then
    printf '%s\n' "[AGY-DISCIPLINES] suppressed by .no-agy at ./.no-agy" >&2
    exit 2
  fi
  if [ -f "$HOME/.claude/.no-agy" ]; then
    printf '%s\n' "[AGY-DISCIPLINES] suppressed by .no-agy at $HOME/.claude/.no-agy" >&2
    exit 2
  fi
  printf '%s\n' "[AGY-DISCIPLINES] guard inactive: missing jq - cannot verify the disciplines will auto-fire; install jq" >&2
  exit 2
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)

# --- superpowers enabled-check across Claude Code's settings hierarchy (more-specific scope wins per plugin
# key): project-local > project > user. Read ONLY files that exist (a missing settings file at a scope is
# NORMAL, not a not-live signal). superpowers is live iff the merged enabledPlugins has a key matching
# ^superpowers@ resolving to true (PREFIX match; the marketplace suffix is not guaranteed). Absent / false /
# corrupt-present -> the possibility-framed advisory (fail-toward-loud). ---
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
proj_dir="${CLAUDE_PROJECT_DIR:-$cwd}"
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
if ! shipped=$(jq -r '[.hooks[][].hooks[].command] | join(" ")' "$shipped_json" 2>/dev/null); then
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
    if ! personal=$(jq -r '[(.hooks // {})[][].hooks[].command] | join(" ")' "$f" 2>/dev/null); then
      ownership_note="${ownership_note}[AGY-DISCIPLINES] schema unrecognised ($f) - .hooks is present but not the shape this check reads; ownership NOT verified for it"$'\n'
      continue
    fi
    for name in $(printf '%s\n' $shipped | grep -oE '[a-z0-9-]+\.sh' | sort -u); do
      case "$personal" in
        *"$name"*) ownership_note="${ownership_note}[AGY-DISCIPLINES] $name is shipped by this plugin AND registered in $f - remove that registration, then restart or /clear this session"$'\n' ;;
      esac
    done
  done
fi

# --- .no-agy kill-switch: announce LOUDLY (naming the path) then STOP. NOT a silent early-exit (that
# reintroduces the silent-kill Decision 3 forbids); NOT a fall-through to the superpowers/jq notices (that
# would triple-spam one boot). One announce, then exit. ---
if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  suppressed="$cwd/.no-agy"; [ -f "$suppressed" ] || suppressed="$HOME/.claude/.no-agy"
  printf '%s\n' "[AGY-DISCIPLINES] suppressed by .no-agy at $suppressed" >&2
  # Constraint 5: ownership is reported EVEN under the kill-switch. A gate the policed party can switch
  # off is not a gate -- otherwise .no-agy plus a kept personal registration hides an override entirely.
  [ -n "$ownership_note" ] && printf '%s' "$ownership_note" >&2
  exit 2
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
  if [ -n "$ownership_note" ]; then
    printf '%s' "$ownership_note" >&2
    exit 2
  fi
  exit 0   # healthy install AND sole ownership: SILENT
fi

# Not live: superpowers not detected as enabled (absent, disabled, corrupt settings, or CC changed the
# settings shape). Emit the advisory as a POSSIBILITY, never "disabled" as a certainty.
printf '%s\n' "[AGY-DISCIPLINES] superpowers not detected as enabled - the agy disciplines will not auto-fire. Install/enable superpowers, or invoke agy-first / agy-capstone manually." >&2
# Ownership is reported here too (same constraint-5 reasoning): a corrupt settings file elsewhere in the
# merge can drive live=0 (jq -s refuses to parse a bad file), which must not swallow an ownership finding
# already collected from a settings file that WAS readable.
[ -n "$ownership_note" ] && printf '%s' "$ownership_note" >&2
exit 2

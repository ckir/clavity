#!/usr/bin/env bash
# AGY consult-recovery reader (plugin-shipped). SessionStart(startup|resume|clear|compact). READ ONLY.
# section 15 workflow-position resilience. Design: docs/superpowers/specs/2026-08-13-workflow-position-resilience-design.md
#
# It surfaces UNCONCLUDED consult seams so a session that died leaves its successor able to resume. It
# reads seam EXISTENCE and AGE, never seam CONTENT. It WRITES NOTHING AT ALL - see the shield note below:
# spec section 6's "assert the shield" requirement is SUPERSEDED by the ROADMAP-31b zero-footprint gate for a
# read-only hook (round-1 panel finding, agy Axiom Breaker + verified).
#
# NAME: recovers interrupted CONSULTS only. NOT power-loss (unprovable + a system-wide sync per edit is
# prohibitively costly - owner ruling 2026-09-13, spec section 3f/section 3g), NOT implementation work (435/435 seams
# are consults), NOT decisions. Do not read the name as a broader promise.
#
# The guard prologue (stdin, cwd, .no-agy, root walk, 31b zero-footprint gate) is COPIED VERBATIM
# from agy-discipline-reaching.sh - see that file's comments for why each line is shaped as it is.
# Fail-open: any error -> exit 0. Byte-identical across both driver plugins (check-seed-artifacts-synced.sh).
set +e
export TZ=UTC

IFS= read -r -d '' input

cwd=''; sid=''
[[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]        && cwd=${BASH_REMATCH[1]}
[[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && sid=${BASH_REMATCH[1]}
cwd_path=${cwd//\\\\//}
[ -z "$cwd_path" ] && cwd_path="."

[ -f "$HOME/.claude/.no-agy" ] && exit 0

root=$cwd_path
if [ -d "$cwd_path" ]; then
  _d=$cwd_path
  while [ -n "$_d" ] && [ "$_d" != "/" ] && [ "$_d" != "." ]; do
    if [ -e "$_d/.git" ]; then root=$_d; break; fi
    case "$_d" in //*/*/*) ;; //*) break ;; esac
    _p=${_d%/*}
    [ "$_p" = "$_d" ] && break
    [ -z "$_p" ] && break
    _d=$_p
  done
fi

[ -e "$root/.git" ] || exit 0

if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
  exit 0
fi

# ROADMAP 31b zero-footprint gate: do NOTHING in a repo that never used the plugin. Prior use of
# .clavity/ IS the opt-in. This ALSO makes the "no seams dir" case correct: no .clavity -> exit 0.
[ -d "$root/.clavity" ] || exit 0

# NO SHIELD ASSERTION (round-1 panel, agy Axiom Breaker + verified). Spec section 6 said "assert the shield on
# every invocation" - but that predates ROADMAP-31b's zero-footprint gate above. Two facts kill the
# shield here: (1) if .clavity does NOT exist, the 31b gate already exited, so a shield assertion could
# only run by CREATING .clavity/.gitignore - the exact footprint 31b forbids; (2) if .clavity DOES exist,
# prior plugin use already asserted the shield (every discipline that writes a seam/marker goes through
# agy-mark.sh, which shields). And this reader WRITES NOTHING, so it has no write to protect. Contrast
# agy-discipline-reaching.sh:130 which keeps the shield: it WRITES .clavity/discipline-reaching.jsonl, so
# it needs the shield before its own write. This reader does not. So there is no shield block at all.

# Absent means empty. The reader NEVER creates seams/ or agy-marks/ (provisioning state on a machine that
# never ran a consult is the checkbox this design refuses). No seams dir -> nothing to surface.
seams_dir="$root/.clavity/seams"
[ -d "$seams_dir" ] || exit 0

# ENUMERATE with nullglob so an absent/empty seams dir yields an empty array and no subprocess cost.
shopt -s nullglob nocaseglob 2>/dev/null
_seams=( "$seams_dir"/*.md )
shopt -u nocaseglob 2>/dev/null
[ ${#_seams[@]} -eq 0 ] && exit 0

# The token list is the LITERAL closed table (spec section 3a) - never derived from agy-marks/.
_tokens='agy-capstone|agy-panel|agy-test-audit|agy-first'

# rank1[] = on-convention unconcluded "path|token|round"; rank2[] = off-convention paths;
# bad[]   = basenames failing the allowlist (reported as a bare count only).
rank1=(); rank2=(); bad=()
for _s in "${_seams[@]}"; do
  _base=${_s##*/}
  # PURE-BASH lowercase (bash 4+); NOT $(... | tr ...) which forks per seam in this hot loop.
  _lc=${_base,,}
  # Rule 1: a -REPLY file is never a candidate of its own.
  case "$_lc" in *-reply.md) continue ;; esac
  # FORMATTING allowlist (spec section 6): keep the startup line bounded/parseable. NOT a security boundary.
  case "$_base" in
    *[!A-Za-z0-9._-]*) bad+=( "$_base" ); continue ;;
  esac
  # Anchored FULL match against the lowercased basename; token from the literal alternation.
  if [[ $_lc =~ ^(${_tokens})-r([0-9]+)(-.+)?\.md$ ]]; then
    _tok=${BASH_REMATCH[1]}; _rnd=${BASH_REMATCH[2]}
    _marker="$root/.clavity/agy-marks/$_tok.head"
    # Concluded iff the seam's OWN marker is newer than it.
    if [ -e "$_marker" ] && [ "$_marker" -nt "$_s" ]; then
      continue
    fi
    rank1+=( "$_s|$_tok|$_rnd" )
  else
    rank2+=( "$_s" )
  fi
done

# Sort each rank most-recent-first by mtime. `ls -t` orders by mtime desc; feed it the paths.
_sort_by_mtime() { # prints most-recent-first
  ls -t -d "$@" 2>/dev/null
}

declare -A _meta   # path -> "token|round"
_r1_paths=()
for _e in "${rank1[@]}"; do
  _p=${_e%%|*}; _meta["$_p"]=${_e#*|}; _r1_paths+=( "$_p" )
done
_r1_sorted=(); if [ ${#_r1_paths[@]} -gt 0 ]; then while IFS= read -r _l; do _r1_sorted+=( "$_l" ); done < <(_sort_by_mtime "${_r1_paths[@]}"); fi
_r2_sorted=(); if [ ${#rank2[@]} -gt 0 ]; then while IFS= read -r _l; do _r2_sorted+=( "$_l" ); done < <(_sort_by_mtime "${rank2[@]}"); fi

# Degrade, never drop (capstone r1 F1; r2 R2-F2/R2-F3): if the external `ls` sort emitted nothing while
# candidates exist, fall back to the UNSORTED source - otherwise the remainder math below reads an empty
# array (0 - 0 = 0) and the hook goes SILENT on open seams, the one outcome this reader exists to prevent.
# This fires more readily than just ARG_MAX (r1's stated trigger): a seams dir with read-but-not-execute
# permission lets the glob match NAMES while `ls -t` cannot stat, so `ls` emits nothing at ANY seam count.
# The fallback order is bash-glob (alphabetical), NOT recency, so set a flag and say so below (R2-F3)
# rather than silently imply the shown seams are the most recent.
_ordering_lost=0
[ ${#_r1_sorted[@]} -eq 0 ] && [ ${#_r1_paths[@]} -gt 0 ] && { _r1_sorted=( "${_r1_paths[@]}" ); _ordering_lost=1; }
[ ${#_r2_sorted[@]} -eq 0 ] && [ ${#rank2[@]} -gt 0 ] && { _r2_sorted=( "${rank2[@]}" ); _ordering_lost=1; }

CAP=3
LINECAP=240
_lines=(); _shown=0; _shown_r1=0; _shown_r2=0
_age_of() { # $1 = seam path; echoes ", written N commits ago" or "" on failure (degrade, never drop)
  local _epoch _n
  _epoch=$(date -r "$1" +%s 2>/dev/null) || return 0
  [ -n "$_epoch" ] || return 0
  _n=$(git -C "$root" rev-list --count --since="@$_epoch" HEAD 2>/dev/null) || return 0
  [ -n "$_n" ] && printf ', written %s commits ago' "$_n"
}
_cap_line() { # $1 = line; truncate to LINECAP
  local _l=$1
  [ ${#_l} -le "$LINECAP" ] && { printf '%s' "$_l"; return 0; }
  printf '%s...(truncated)' "${_l:0:$LINECAP}"
}
for _p in "${_r1_sorted[@]}"; do
  [ "$_shown" -ge "$CAP" ] && break
  _tok=${_meta["$_p"]%%|*}; _rnd=${_meta["$_p"]#*|}
  _age=$(_age_of "$_p")
  # Case-robust reply probe (capstone r1 F2 + r2 R2-F1). The -reply.md exclusion (line ~84) matches the
  # LOWERCASED $_lc, so it is case-INsensitive; this probe must be equally flexible or a -REPLY.MD reply on
  # a case-SENSITIVE FS becomes a GHOST - excluded from candidates yet missed here, so the note silently
  # vanishes. r1 fixed only the SEAM extension (${_p%.md} missed a .MD seam even on Windows, MEASURED);
  # this closes the reply side too. Case-class glob on both the -REPLY token and its extension (nullglob at
  # line 68 -> empty array when there is no reply); the stem is QUOTED so a '[' in the repo path is literal.
  _rp=( "${_p%.[Mm][Dd]}"-[Rr][Ee][Pp][Ll][Yy].[Mm][Dd] )
  if [ ${#_rp[@]} -gt 0 ]; then
    _lines+=( "$(_cap_line "workflow position: $_tok r$_rnd ($_p)$_age. A -REPLY EXISTS on disk. It may or may not have been folded already - check before re-folding it. Read that seam and its -REPLY before starting new work, or say why you are not resuming it.")" )
  else
    _lines+=( "$(_cap_line "workflow position: $_tok r$_rnd ($_p)$_age. Read that seam before starting new work, or say why you are not resuming it.")" )
  fi
  _shown=$((_shown+1)); _shown_r1=$((_shown_r1+1))
done
for _p in "${_r2_sorted[@]}"; do
  [ "$_shown" -ge "$CAP" ] && break
  _age=$(_age_of "$_p")
  _lines+=( "$(_cap_line "an unrecognised seam exists ($_p)$_age. Read it before starting new work, or say why you are not resuming it.")" )
  _shown=$((_shown+1)); _shown_r2=$((_shown_r2+1))
done

_r1_rest=$(( ${#_r1_sorted[@]} - _shown_r1 ))
_r2_rest=$(( ${#_r2_sorted[@]} - _shown_r2 ))
[ "$_r1_rest" -gt 0 ] && _lines+=( "$_r1_rest more open seams are not shown. List .clavity/seams/ yourself before starting new work." )
[ "$_r2_rest" -gt 0 ] && _lines+=( "$_r2_rest unrecognised seams are not shown. If you are resuming work you cannot see listed above, list .clavity/seams/ yourself before starting." )
[ ${#bad[@]} -gt 0 ] && _lines+=( "${#bad[@]} unrecognised seams could not be named. If you are resuming work you cannot see listed above, list .clavity/seams/ yourself before starting." )

# R2-F3: if we fell back to name order, say so FIRST - the seams below are NOT ordered by recency, and
# without this the shown set silently implies it is the most recent.
[ "$_ordering_lost" -eq 1 ] && [ ${#_lines[@]} -gt 0 ] && _lines=( "the seam directory could not be ordered by recency (it could not be stat-ed); the seams below are in NAME order, not most-recent-first - list .clavity/seams/ yourself to check timestamps." "${_lines[@]}" )

# Nothing to say -> print NOTHING (spec section 3b: not a header, not an empty section).
[ ${#_lines[@]} -eq 0 ] && exit 0
_msg=$(printf '%s\n' "${_lines[@]}")

# jq owns the escaping ($_msg carries agent-authored PATHS). If jq is ABSENT, do NOT go silently mute:
# emit a FIXED-literal notice with NO interpolated path, mirroring agy-anomaly-reminder.sh:73-74.
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg m "$_msg" '{systemMessage:$m,hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
else
  _nm="[consult-recovery] guard inactive: missing jq - cannot list open consult seams; list .clavity/seams/ yourself before starting new work"
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$_nm" "$_nm"
fi
exit 0

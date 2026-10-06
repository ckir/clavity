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
#
# PROCESS BUDGET: this hook starts a bounded, seam-count-INDEPENDENT number of processes (every process
# costs ~200 ms on Windows Git Bash): the enumeration, classification, top-N selection and conclusion test are
# all bash builtins (`-nt`, `[[ ]]`, `printf -v`); only the SHOWN set (at most CAP=3 paths) costs externals -
# one `stat`, one `git log`, one `jq`. Needs bash >= 4.3 (namerefs).
set +e
export TZ=UTC

input=; while IFS= read -r -N 1048576 _c; do input+=$_c; done; input+=$_c

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

# ROADMAP section 39: the marker path comes from the SAME builder agy-mark.sh writes with. If it cannot be
# loaded no seam can be shown concluded, so every candidate is surfaced - the loud direction for a reader
# whose job is recovery. A lib that loads but does not define the builder counts as missing, otherwise the
# marker path collapses to $root/ and hides every seam (capstone Branch 2 round 1).
# `${0%[/\\]*}` rather than `$(dirname "$0")` (a fork). BACKSLASH counts as a separator, as msys dirname treats
# it: a Windows caller (the Pester suites, a backslash CLAUDE_PLUGIN_ROOT) hands bash `C:\x\hooks\h.sh`
# (MEASURED: `${0%/*}` returns it UNCHANGED, the lib is then not found and every seam reads as open).
# A separator-less $0 means the current directory, as dirname says.
_hd=${0%[/\\]*}; [ "$_hd" = "$0" ] && _hd=.
_marker_lib_ok=0
. "$_hd/agy-marker-lib.sh" 2>/dev/null && command -v agy_marker_rel >/dev/null 2>&1 && _marker_lib_ok=1

CAP=3
LINECAP=240

# Only the CAP most-recent candidates of each rank are ever shown, so only those are kept: a bounded
# insertion into a CAP-long list ordered by mtime (`-nt`, a builtin) replaces `ls -t` over the whole set.
# Seams are visited in glob (name) order and a new one enters only AHEAD of entries it is STRICTLY newer
# than, so equal mtimes keep name order - the same tie-break `ls -t` applies (mtime desc, then name).
# _top_insert <paths-array> <entries-array> <path> <entry>
_top_insert() {
  local -n _tp=$1 _te=$2
  local _np=$3 _ne=$4 _i _n=${#_tp[@]}
  # Full, and not strictly newer than the CAPth entry: cannot enter the top - one comparison, not CAP.
  if [ "$_n" -ge "$CAP" ] && ! [ "$_np" -nt "${_tp[CAP-1]}" ]; then return 0; fi
  for (( _i=0; _i<_n; _i++ )); do
    [ "$_np" -nt "${_tp[_i]}" ] && break
  done
  _tp=( "${_tp[@]:0:_i}" "$_np" "${_tp[@]:_i:CAP-1-_i}" )
  _te=( "${_te[@]:0:_i}" "$_ne" "${_te[@]:_i:CAP-1-_i}" )
}

# r1_* = on-convention unconcluded (path / "path|token|round"), r2_* = off-convention paths, each
# most-recent-first and at most CAP long; *_n = the FULL unconcluded count (the "+N more" arithmetic).
# bad[] = basenames failing the allowlist (reported as a bare count only).
_r1_p=(); _r1_e=(); _r1_n=0
_r2_p=(); _r2_e=(); _r2_n=0
bad=()
# Degrade, never drop (capstone r1 F1; r2 R2-F2/R2-F3): an unconcluded candidate that cannot be stat-ed
# (read-but-not-execute seams dir, a dangling link) makes every `-nt` comparison false, so the shown set is
# in NAME order, not recency - say so below rather than silently imply the shown seams are the most recent.
_ordering_lost=0
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
  # KEYWORD classification (owner-approved 2026-10-04; replaces the `agy-<token>-rN` name convention that
  # almost no real seam follows). The lowercased stem, wrapped in hyphens, is matched for WHOLE hyphen-
  # delimited words, in this precedence: test-audit|testaudit, capstone, panel|review, first.
  _w="-${_lc%.md}-"
  _tok=''
  if   [[ $_w == *-test-audit-* || $_w == *-testaudit-* ]]; then _tok=agy-test-audit
  elif [[ $_w == *-capstone-* ]];                           then _tok=agy-capstone
  elif [[ $_w == *-panel-* || $_w == *-review-* ]];         then _tok=agy-panel
  elif [[ $_w == *-first-* ]];                              then _tok=agy-first
  fi
  if [ -n "$_tok" ]; then
    # Round = the number of the LAST `-rN` word (greedy `.*`); none -> the literal `?` (printed "r?").
    _rnd='?'
    [[ $_w =~ .*-r([0-9]+)- ]] && _rnd=${BASH_REMATCH[1]}
    _marker=''
    if [ "$_marker_lib_ok" = 1 ]; then agy_marker_rel _mrel "$_tok"; _marker="$root/$_mrel"; fi
    # Concluded iff the seam's OWN marker is newer than it.
    if [ -n "$_marker" ] && [ -e "$_marker" ] && [ "$_marker" -nt "$_s" ]; then
      continue
    fi
    [ -e "$_s" ] || _ordering_lost=1
    _r1_n=$((_r1_n+1))
    _top_insert _r1_p _r1_e "$_s" "$_s|$_tok|$_rnd"
  else
    [ -e "$_s" ] || _ordering_lost=1
    _r2_n=$((_r2_n+1))
    _top_insert _r2_p _r2_e "$_s" "$_s"
  fi
done

# What is shown: rank 1 first, rank 2 fills what is left of CAP.
_shown_r1=${#_r1_p[@]}
_shown_r2=${#_r2_p[@]}
[ "$_shown_r2" -gt $((CAP-_shown_r1)) ] && _shown_r2=$((CAP-_shown_r1))
_show_p=( "${_r1_p[@]}" "${_r2_p[@]:0:_shown_r2}" )

# AGE of every shown seam in COMMITS (never wall-clock), with ONE `stat` and ONE `git log` for the whole
# shown set. Degrade, never drop: a seam that cannot be stat-ed, or a repo whose git cannot count (no commit
# yet), simply gets no age. The count per seam is the number of commits whose committer date is >= that
# seam's mtime second, taken from the one log of the OLDEST shown seam's window (`--since` keeps a commit
# whose date EQUALS the bound, so `>=` is the same predicate `rev-list --since` applies).
_ages=()
if [ ${#_show_p[@]} -gt 0 ]; then
  _so=$(stat -L -c '%Y %n' -- "${_show_p[@]}" 2>/dev/null)
  _st_e=(); _st_p=(); _min=''
  while IFS= read -r _l; do
    case ${_l%% *} in ''|*[!0-9]*) continue ;; esac
    _st_e+=( "${_l%% *}" ); _st_p+=( "${_l#* }" )
    if [ -z "$_min" ] || [ "${_l%% *}" -lt "$_min" ]; then _min=${_l%% *}; fi
  done <<< "$_so"
  if [ -n "$_min" ]; then
    _gout=$(git -C "$root" -c log.showSignature=false log --format=%ct --since="@$_min" HEAD 2>/dev/null) && {
      _cts=(); [ -n "$_gout" ] && mapfile -t _cts <<< "$_gout"
      for _i in "${!_show_p[@]}"; do
        for _j in "${!_st_p[@]}"; do
          [ "${_st_p[_j]}" = "${_show_p[_i]}" ] || continue
          _c=0
          for _t in "${_cts[@]}"; do (( _t >= _st_e[_j] )) && _c=$((_c+1)); done
          _ages[_i]=", written $_c commits ago"
          break
        done
      done
    }
  fi
fi

_cap_line_v() { # $1 = out-var, $2 = line; truncate to LINECAP
  local _cl_in=$2   # NOT `_l`: a local named like the caller's out-var would swallow the printf -v
  if [ ${#_cl_in} -le "$LINECAP" ]; then printf -v "$1" '%s' "$_cl_in"; else printf -v "$1" '%s...(truncated)' "${_cl_in:0:$LINECAP}"; fi
}
_lines=()
for (( _i=0; _i<_shown_r1; _i++ )); do
  _p=${_r1_p[_i]}; _e=${_r1_e[_i]}
  _rnd=${_e##*|}; _e=${_e%|*}; _tok=${_e##*|}
  _age=${_ages[_i]}
  # Case-robust reply probe (capstone r1 F2 + r2 R2-F1). The -reply.md exclusion (line ~125) matches the
  # LOWERCASED $_lc, so it is case-INsensitive; this probe must be equally flexible or a -REPLY.MD reply on
  # a case-SENSITIVE FS becomes a GHOST - excluded from candidates yet missed here, so the note silently
  # vanishes. r1 fixed only the SEAM extension (${_p%.md} missed a .MD seam even on Windows, MEASURED);
  # this closes the reply side too. Case-class glob on both the -REPLY token and its extension (nullglob at
  # line 73 -> empty array when there is no reply); the stem is QUOTED so a '[' in the repo path is literal.
  _rp=( "${_p%.[Mm][Dd]}"-[Rr][Ee][Pp][Ll][Yy].[Mm][Dd] )
  if [ ${#_rp[@]} -gt 0 ]; then
    _cap_line_v _l "workflow position: $_tok r$_rnd ($_p)$_age. A -REPLY EXISTS on disk. It may or may not have been folded already - check before re-folding it. Read that seam and its -REPLY before starting new work, or say why you are not resuming it."
  else
    _cap_line_v _l "workflow position: $_tok r$_rnd ($_p)$_age. Read that seam before starting new work, or say why you are not resuming it."
  fi
  _lines+=( "$_l" )
done
for (( _k=0; _k<_shown_r2; _k++ )); do
  _p=${_r2_p[_k]}
  _age=${_ages[_shown_r1+_k]}
  _cap_line_v _l "an unrecognised seam exists ($_p)$_age. Read it before starting new work, or say why you are not resuming it."
  _lines+=( "$_l" )
done

_r1_rest=$(( _r1_n - _shown_r1 ))
_r2_rest=$(( _r2_n - _shown_r2 ))
[ "$_r1_rest" -gt 0 ] && _lines+=( "$_r1_rest more open seams are not shown. List .clavity/seams/ yourself before starting new work." )
[ "$_r2_rest" -gt 0 ] && _lines+=( "$_r2_rest unrecognised seams are not shown. If you are resuming work you cannot see listed above, list .clavity/seams/ yourself before starting." )
[ ${#bad[@]} -gt 0 ] && _lines+=( "${#bad[@]} unrecognised seams could not be named. If you are resuming work you cannot see listed above, list .clavity/seams/ yourself before starting." )

# R2-F3: if we fell back to name order, say so FIRST - the seams below are NOT ordered by recency, and
# without this the shown set silently implies it is the most recent.
[ "$_ordering_lost" -eq 1 ] && [ ${#_lines[@]} -gt 0 ] && _lines=( "the seam directory could not be ordered by recency (it could not be stat-ed); the seams below are in NAME order, not most-recent-first - list .clavity/seams/ yourself to check timestamps." "${_lines[@]}" )

# Nothing to say -> print NOTHING (spec section 3b: not a header, not an empty section).
[ ${#_lines[@]} -eq 0 ] && exit 0
# `printf -v` (no fork); the trailing newline is stripped as `$(...)` did.
printf -v _msg '%s\n' "${_lines[@]}"
_msg=${_msg%$'\n'}

# jq owns the escaping ($_msg carries agent-authored PATHS). If jq is ABSENT, do NOT go silently mute:
# emit a FIXED-literal notice with NO interpolated path, mirroring agy-anomaly-reminder.sh:73-74.
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg m "$_msg" '{systemMessage:$m,hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
else
  # `msg_`-named ON PURPOSE (not `_nm`): the injected-context corpus invariant's Get-HookMessages binds
  # `msg[A-Za-z0-9_]*`, so naming this static fallback message that way makes it visible to the budget /
  # tag-hygiene checks. The PRIMARY message ($_msg above) is assembled at RUNTIME from the seam list, so it
  # has no static literal to extract - out of static scope by construction, and self-bounded by LINECAP.
  msg_jq_missing="[consult-recovery] guard inactive: missing jq - cannot list open consult seams; list .clavity/seams/ yourself before starting new work"
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$msg_jq_missing" "$msg_jq_missing"
fi
exit 0

#!/usr/bin/env bash
# AGY auto-fire hook (plugin-shipped). PreToolUse(Skill): inject a best-effort directive at each
# superpowers seam listed below. NO COUNT is written here on purpose -- the map IS the count, and
# a number kept beside the list it duplicates is the first thing to rot (this comment has already
# been wrong about it once).
#   *brainstorm*                     -> AGY-FIRST: run the discipline  (marker agy-first.head)
#   *finishing-a-development-branch* -> AGY-CAPSTONE: run the discipline (marker agy-capstone.head)
#   *subagent-driven-development* / *executing-plans*
#        -> ANOMALY-CAPTURE: carry the dispatch clause, and capture what comes back (no marker)
# The arms do NOT inject the same kind of thing: the first two say "run this discipline now", the
# third says "paste this clause into every dispatch and verify what comes back". Only the first
# two are debounced, by the HEAD-keyed marker their discipline skill writes
# (docs/agy-disciplines-marker-contract.md). The third is NOT structurally exempt from that
# lookup -- it runs it too, against .clavity/agy-marks/anomaly-dispatch.head -- but nothing ever
# writes that file, so the lookup finds nothing and the arm injects on every invocation.
# Every directive POINTS AT a skill rather than inlining it: the two discipline skills carry the
# per-transport consult clause, and the anomaly arm points at open-issues (a triage procedure,
# not an agy discipline, so it has no transport clause at all). Nothing transport-specific
# therefore lives in this file, and it is byte-identical across both driver plugins. This hook
# NEVER writes a marker (a PreToolUse hook fires before the consult and cannot know its outcome).
# Fail-open: any error -> exit 0 (never blocks the tool). Suppressed by .no-agy (cwd or
# ~/.claude). Without jq it degrades LOUD on a seam match (never a silent no-op).
set +e
# PROCESS BUDGET (Branch 20, hook spawn budget: at most 16 processes per run, bash's own 3 included): every process costs ~200ms on Windows, so this hook starts few. `read`
# is a builtin where `$(cat)` is a subshell plus an external (2 processes). Trailing newlines survive, which
# nothing below can see. No `2>/dev/null` is needed: `read` writes nothing to stderr.
# stdin: read -N needs bash >= 4.1; older bash (macOS /bin/bash 3.2) keeps the pre-Branch-20 read.
if [ -z "${CLAVITY_HOOK_BASH3:-}" ] && ((BASH_VERSINFO[0]*100+BASH_VERSINFO[1] >= 401)); then input=; while IFS= read -r -N 1048576 _c; do input+=$_c; done; input+=$_c; else input=$(cat); fi

# --- jq guard (spec Decision 4). jq is required to parse stdin + emit structured JSON.
# Without it, fall back to a FIELD-BOUNDED grep on the skill value (never a bare substring,
# which could false-match a seam name mentioned in another skill's args) and, ONLY on a seam
# match, emit a loud printf-hardcoded ASCII line so a disabled hook is never silent. ---
if ! command -v jq >/dev/null 2>&1; then
  # Kill-switch still honored. cwd is recovered from the RAW payload with a bash regex rather than falling
  # back to the PROCESS cwd, which need not be the session's workspace. Raw recovery keeps the JSON
  # escaping, hence the DOUBLE-backslash pattern - see the note at the jq path below.
  [[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && cwd=${BASH_REMATCH[1]}
  cwd_path=${cwd//\\\\//}
  [ -z "$cwd_path" ] && cwd_path="."
  # A FILE as cwd is resolved to its DIRECTORY, or the kill-switch does not fire. MEASURED 2026-09-12 with
  # both controls in a throwaway repo: the walk below is gated on `[ -d ]`, so a file cwd skipped it, and
  # `$cwd_path/.no-agy` is `<file>/.no-agy`, which never exists - the hook spoke (1189 bytes) where the
  # directory and a subdirectory were both correctly silent. Parameter expansion, not `dirname`: an empty
  # PATH must not turn an opt-out into a leak. `%/*` leaves nothing for a path at the root, hence the guard.
  [ -f "$cwd_path" ] && { cwd_path=${cwd_path%/*}; [ -z "$cwd_path" ] && cwd_path="/"; }
  [ -f "$HOME/.claude/.no-agy" ] && exit 0
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
  if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then exit 0; fi
  # One alternation, matched LINE BY LINE with the `[[ =~ ]]` builtin: four `printf | grep` pipelines cost
  # 3 processes each (12 on the common non-seam skill), and a per-line match is what grep did.
  _seamre='"skill"[[:space:]]*:[[:space:]]*"[^"]*(finishing-a-development-branch|brainstorm|subagent-driven-development|executing-plans)'
  _hit=0
  while IFS= read -r _line; do
    [[ $_line =~ $_seamre ]] && { _hit=1; break; }
  done <<<"$input"
  if [ "$_hit" = 1 ]; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[AGY-DISCIPLINES] guard inactive: missing jq - no seam directive will auto-fire (disciplines AND anomaly-capture)"}}'
  fi
  exit 0
fi

# ONE jq call for both fields, NUL-separated, read by builtins: exact for any string, and no fallback path
# that calls jq again (the prototype's fallback measured 17). -j writes no newline, so the Windows jq's CRLF
# never reaches a value. `$(...)` used to strip trailing newlines; the two expansions below keep that.
skill=; cwd=
{ IFS= read -r -d '' skill; IFS= read -r -d '' cwd; } < <(jq -j '(.tool_input.skill // ""), "\u0000", (.cwd // "."), "\u0000"' <<<"$input" 2>/dev/null)
skill=${skill%"${skill##*[!$'\n']}"}
cwd=${cwd%"${cwd##*[!$'\n']}"}

# THE NORMALIZATION FORM MUST MATCH THE EXTRACTION SOURCE. jq -r DECODES the JSON escaping, so cwd holds
# SINGLE backslashes here and the pattern is one escaped backslash; the degraded branch above reads the RAW
# payload, where the DOUBLE backslashes survive, and needs ${cwd//\\\\//}. MEASURED 2026-08-05: the raw form
# applied to a jq-decoded value matches nothing and leaves the path untouched - a silent no-op that looks
# exactly like a working fix. Do NOT unify the two spellings.
cwd_path=${cwd//\\//}
[ -z "$cwd_path" ] && cwd_path="."
# A FILE as cwd is resolved to its DIRECTORY - see the note on the degraded path above; the `[ -d ]` gate
# below is the same shape, so this path had the same hole and both were measured on 2026-09-12.
[ -f "$cwd_path" ] && { cwd_path=${cwd_path%/*}; [ -z "$cwd_path" ] && cwd_path="/"; }

# Opt-out kill-switch (mirrors agy-after-reminder.sh): .no-agy in the repo root, the session cwd, or
# ~/.claude. Global first - it needs no root.
[ -f "$HOME/.claude/.no-agy" ] && exit 0

# Repo root by walking up for .git, in-shell, so a .no-agy at the REPO ROOT is honoured when the session
# was launched from a subdirectory. The normalization above is load-bearing: ${_d%/*} strips on "/" only.
# $root IS FOR THIS CHECK AND NOTHING ELSE IN THIS FILE - see the debounce contract below, which forbids
# anchoring the marker to git-toplevel.
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

if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
  exit 0
fi

# Map the skill to a discipline seam. Non-seam skills -> silent exit 0.
case "$skill" in
  *finishing-a-development-branch*)                  discipline="agy-capstone" ;;
  *brainstorm*)                                      discipline="agy-first" ;;
  *subagent-driven-development*|*executing-plans*)   discipline="anomaly-dispatch" ;;
  *)                                                 exit 0 ;;
esac

# --- Debounce (docs/agy-disciplines-marker-contract.md). The marker is CWD-RELATIVE, anchored
# to the payload's session cwd EXACTLY as the discipline skills write it (a bare
# .clavity/agy-marks/<discipline>.head relative to the agent's cwd). Do NOT anchor to
# git-toplevel: that would diverge from the cwd-relative writer in a launched-from-subdir
# session and defeat the debounce. Inject UNLESS the marker exists AND its content == HEAD, or HEAD is
# the marker plus ledger-row commits only (see THE LEDGER-ROW CASE below).
# $cwd_path, NOT $root - the walked root exists above but using it HERE is the exact divergence this
# paragraph forbids. Normalized only, same directory. ---
head=$(git -C "$cwd_path" rev-parse HEAD 2>/dev/null)
# ROADMAP section 39: the relative path comes from the SAME builder the writer uses. If the builder cannot
# be loaded the debounce cannot run, so fall through and inject - the safe direction, as for an
# unresolvable HEAD below.
_rel=''
# dirname by parameter expansion: `$(dirname)` is 2 processes. Both separators count, because the host (and the
# Pester suites) can start this as `bash 'C:\x\h.sh'`, which msys dirname splits on `\`. "no separator" is `.`
# and a root-level script is `/`, exactly what dirname answers.
_hd=${0%[/\\]*}
if [ "$_hd" = "$0" ]; then _hd=.; elif [ -z "$_hd" ]; then _hd=/; fi
. "$_hd/agy-marker-lib.sh" 2>/dev/null && agy_marker_rel _rel "$discipline"
marker=''
[ -n "$_rel" ] && marker="$cwd_path/$_rel"
if [ -n "$head" ] && [ -n "$marker" ] && [ -f "$marker" ]; then
  # The WHOLE file, trailing newlines stripped - what `$(cat)` yielded, minus its 2 processes. The stderr
  # redirect comes BEFORE the file redirect so an unreadable marker is silent, as the `cat` form was.
  _m=''
  { IFS= read -r -d '' _m; } 2>/dev/null < "$marker"
  while [[ $_m == *$'\n' ]]; do _m=${_m%$'\n'}; done
  [ "$_m" = "$head" ] && exit 0
  # THE LEDGER-ROW CASE (capstone Branch 2 round 1, owner ruling 2026-09-30). The capstone and test-audit
  # skills write the REVIEWED sha and must commit their ledger row first, so HEAD is past the marker by
  # the time anyone finishes the branch, and strict equality re-injected a capstone that was already GREEN.
  # Forgive ONLY when HEAD descends from the marker and its tree differs from the marker's in nothing but
  # docs/agy-*-ledger.md files. Deliberately NOT agy-test-audit-reminder.sh's CODE_RE: that list has no .md
  # or .json, so it would forgive a SKILL.md or settings.json change - the files a capstone exists to
  # review. The hex check keeps a hand-edited marker from reaching git as an option (`--output=...`).
  # Every failure below (missing object, shallow clone, no git) leaves the seam injected.
  case "$_m" in
    ''|*[!0-9a-f]*) ;;
    *)
      if git -C "$cwd_path" merge-base --is-ancestor "$_m" "$head" 2>/dev/null; then
        # --no-renames: a rename lists only its NEW path, so moving src/x.sh onto a ledger path would read
        # as a ledger-only change. diff.relative=false: that user setting, from a subdirectory cwd, drops
        # every path outside the cwd, docs/ included. Both measured in capstone Branch 2 round 2.
        # The "every path is a ledger" test is a per-line `[[ =~ ]]` loop: `printf | grep -Evq` was 3 processes.
        _post=$(git -C "$cwd_path" -c core.quotePath=false -c diff.relative=false diff --no-renames --name-only "$_m" "$head" 2>/dev/null) &&
          [ -n "$_post" ] && {
            _ledgers=1
            while IFS= read -r _line; do
              [[ $_line =~ ^docs/agy-[a-z0-9-]+-ledger\.md$ ]] || { _ledgers=0; break; }
            done <<<"$_post"
            [ "$_ledgers" = 1 ]
          } &&
          exit 0
      fi
      ;;
  esac
fi
# If HEAD cannot resolve (no repo / no commits), fall through and inject (safe: re-fires;
# the skill cannot write a HEAD-keyed marker in that context either).

emit() { jq -n -c --arg ctx "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'; }

case "$discipline" in
  agy-first)
    emit 'AGY-FIRST auto-fire: you are at a design/scope/approach/sequencing fork (the brainstorming approaches step). BEFORE committing to a direction, invoke the `agy-first` skill to run a divergent, review-only consult of the live agy peer over this fork. Load-bearing posture (the skill carries the full procedure and your driver'"'"'s transport): frame the fork as a GOAL plus a checkable SUCCESS CRITERION under forcing-function divergence vectors, not a vague "be creative" dial; VERIFY every bare factual claim the peer makes BY MEASUREMENT before folding it (it makes confident false claims); NEGOTIATE on material disagreement rather than defer-or-dismiss; end with exactly one ASCII [VERDICT] token. Best-effort discipline: the user still owns the decision. If agy is unreachable, the skill'"'"'s SKIPPED-UNREACHABLE path applies - proceed, do not hang. SESSION POSTURE: reviews later in this work (capstone, test audit, panel) re-read the whole session context each round, so they run far leaner in a fresh session than at the end of a long one. Plan to commit first, then run them after /compact or in a new session.' ;;
  agy-capstone)
    emit 'AGY-CAPSTONE auto-fire: you are finishing a development branch (about to merge/PR). BEFORE you declare the work complete, invoke the `agy-capstone` skill to run a convergent, review-only agy review of the COMMITTED implementation (the executable code plus tests, NOT a plan artifact) in ROUNDS UNTIL GREEN. Load-bearing posture (the skill carries the full procedure and your driver'"'"'s transport): send the committed diff by filepath or git-range under adversarial lenses citing file:line; VERIFY every finding BY MEASUREMENT before folding it (the peer states false claims with confidence); fold the real ones, commit fixes, RE-RUN a fresh round with a do-not-re-raise ledger until a full round is GREEN; a human adjudicates GREEN (or an explicit round-cap waiver). End with exactly one ASCII [VERDICT] token. This catches executable-behaviour defects the pre-execution plan review structurally cannot. If agy is unreachable, the skill'"'"'s SKIPPED-UNREACHABLE path applies - proceed, do not hang. COST: this discipline re-reads the whole session context every round, so running it in a long session burns several times the tokens - and subscription quota - of running it fresh. If this session carries substantial history, do not run it inline: tell the user it runs about 5x leaner after /compact or in a fresh session, and follow their answer. This changes WHERE the review runs, never WHETHER.' ;;
  anomaly-dispatch)
    emit 'ANOMALY-CAPTURE: you are about to dispatch subagents. TWO obligations, and the second is the one that historically fails. (1) EVERY implementer dispatch you write MUST carry TWO clauses verbatim from the `open-issues` skill: the anomaly clause under "Dispatching a subagent", and the FILES clause naming every path that dispatch may touch. Then, when the subagent returns, compare the real change set against the list you gave it - a subagent has written outside its named set before, and the list is worthless without the diff. Record the SHA before you dispatch and check BOTH axes: `git status --short` for uncommitted writes AND `git log --stat <sha-before>..HEAD` for committed ones. A status check ALONE is not enough - most implementers COMMIT, and a committed write leaves the working tree clean (MEASURED: status prints nothing while `git show --stat HEAD` names the file). It asks the subagent to report anything wrong that is NOT its task under a `## Anomalies noticed` heading at the end of its final message, stated as a checkable fact, with an explicit `none` if it saw nothing. A subagent will not invoke that skill on its own, so the instruction has to travel IN the dispatch. (2) When a report comes back, VERIFY each claimed anomaly by measurement - open the file, run the command, reproduce it - and then APPEND the verified ones to .clavity/local-anomalies.md BEFORE you write your summary to the user. A subagent report is a claim, not evidence; and a verified anomaly that exists only in a chat message is lost the moment you compress that message. Capturing after summarizing is capturing never.' ;;
esac
exit 0

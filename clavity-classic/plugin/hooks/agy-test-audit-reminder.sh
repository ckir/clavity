#!/usr/bin/env bash
# AGY-TEST-AUDIT trigger (plugin-shipped). PostToolUse: after AGY-CAPSTONE reaches GREEN, nudge the
# test-exhaustiveness audit exactly once for this HEAD. Marker-gated (docs/agy-disciplines-marker-contract.md):
#   fire IFF  .clavity/agy-marks/agy-capstone.head   still describes HEAD - either it EQUALS HEAD, or it
#             is an ANCESTOR of HEAD and nothing executable landed since it (see gate() for why)
#        AND  .clavity/agy-marks/agy-test-audit.head  != HEAD   (audit not yet run at this HEAD)
#        AND  the reviewed range touched executable code / test paths (spec 4: docs-only must not nudge)
# This SEQUENCES capstone->audit structurally (the capstone marker is written ONLY on human-GREEN or a
# round-cap waiver), without touching the strict 1:1 agy-seam-inject.sh case statement. The directive POINTS
# AT the agy-test-audit skill (which carries the procedure + per-transport clause), so this file is
# byte-identical across both driver plugins. It NEVER writes a marker (a hook fires before the consult and
# cannot know its outcome). Fail-open: any error -> exit 0. Suppressed by .no-agy (cwd or ~/.claude).
# Without jq it degrades LOUD only when the gate would fire (never a silent no-op, never a false alarm).
set +e
input=$(cat)

DIR_CONST=".clavity/agy-marks"

# Shared gate: given a cwd, echo "fire" iff capstone-green-at-HEAD AND audit-not-done AND code/test changed.
gate() {
  local cwd="$1" head cap aud base changed post
  # The executable-path list, held ONCE and used twice below. Two copies would be two definitions of
  # "executable code" free to drift apart, and the second one only runs on a path nothing exercised until
  # 2026-08-26.
  local CODE_RE='\.(cs|fs|rs|ts|tsx|js|jsx|py|go|java|rb|c|h|cpp|hpp|sh|ps1)$'
  head=$(git -C "$cwd" rev-parse HEAD 2>/dev/null) || return 1
  [ -n "$head" ] || return 1
  cap=$(cat "$cwd/$DIR_CONST/agy-capstone.head" 2>/dev/null)
  [ -n "$cap" ] || return 1                              # capstone never reached GREEN in this tree
  if [ "$cap" != "$head" ]; then
    # THE LEDGER-ROW CASE. A strict "cap == head" was silenced by the capstone's OWN mandatory final step:
    # agy-capstone writes the reviewed tip to the marker and then requires a row in
    # docs/agy-capstone-ledger.md before a plan may be declared complete, and committing that row advances
    # HEAD. MEASURED 2026-08-26 in this repository: marker f29cd42, next commit f209632 "docs(ledger):
    # record ... GREEN", and this hook was silent for the 34 commits that followed - which is why two
    # test-audits were owed with nothing nudging for either. The discipline's completion step destroyed its
    # successor's trigger.
    #
    # So the GREEN is treated as still describing HEAD when the marker is an ANCESTOR of HEAD and nothing
    # executable landed since it. Both halves are load-bearing: without the ancestor test, a marker from an
    # abandoned branch (or a sha this tree does not contain) would satisfy the gate; without the code test,
    # any amount of new code would inherit a GREEN that never reviewed it. A failing git command returns
    # SILENT rather than firing - a nudge that cannot establish its own precondition is a false alarm.
    git -C "$cwd" merge-base --is-ancestor "$cap" "$head" 2>/dev/null || return 1
    post=$(git -C "$cwd" -c core.quotePath=false diff --name-only "$cap"..HEAD 2>/dev/null) || return 1
    printf '%s\n' "$post" | grep -Eqi "$CODE_RE" && return 1   # code landed after the reviewed tip
  fi
  aud=$(cat "$cwd/$DIR_CONST/agy-test-audit.head" 2>/dev/null)
  [ "$aud" = "$head" ] && return 1                       # audit already ran at this HEAD
  # Reviewed range: merge-base with an integration ref, else this commit's own files (on-branch / no ref).
  base=$(git -C "$cwd" merge-base HEAD "${CLAVITY_AUDIT_BASE_REF:-origin/main}" 2>/dev/null)
  [ -z "$base" ] && base=$(git -C "$cwd" merge-base HEAD main 2>/dev/null)
  if [ -n "$base" ] && [ "$base" != "$head" ]; then
    changed=$(git -C "$cwd" -c core.quotePath=false diff --name-only "$base"..HEAD 2>/dev/null)
  else
    changed=$(git -C "$cwd" -c core.quotePath=false show --name-only --format= HEAD 2>/dev/null)
  fi
  # Executable-code / test path heuristic. Empty match -> silent (docs/config/spec-only range, spec 4).
  printf '%s\n' "$changed" | grep -Eqi "$CODE_RE" || return 1
  echo fire
}

# --- jq guard. jq parses stdin (cwd) + emits structured JSON. Without it: honor the kill-switch, then run
# the gate against the PROCESS cwd; ONLY when it would fire, emit a loud hardcoded ASCII line. ---
if ! command -v jq >/dev/null 2>&1; then
  # Without jq we cannot parse JSON, but the gate itself needs the real cwd (not the process cwd, which
  # may be an unrelated directory) to find the right repo's HEAD/markers. Recover it from the raw payload
  # with the same bash-regex technique the recorder uses, in place of the previous `sed` capture: sed
  # returned the value with its JSON ESCAPING INTACT and nothing normalized it, so on Windows every
  # subsequent stat ran against a path that does not resolve. Raw recovery keeps the escaping, hence the
  # DOUBLE-backslash pattern here - see the note at the jq path below.
  [[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && cwd=${BASH_REMATCH[1]}
  cwd_path=${cwd//\\\\//}
  [ -z "$cwd_path" ] && cwd_path="."
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
  # Honor the kill-switch against the SAME cwd the gate uses (aligns with the jq path below).
  if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then exit 0; fi
  if [ "$(gate "$cwd_path")" = "fire" ]; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[AGY-DISCIPLINES] guard inactive: missing jq - the AGY-TEST-AUDIT reminder will not fire after capstone green"}}'
  fi
  exit 0
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)
# THE NORMALIZATION FORM MUST MATCH THE EXTRACTION SOURCE. jq -r DECODES the JSON escaping, so cwd holds
# SINGLE backslashes here and the pattern is one escaped backslash; the degraded branch above reads the RAW
# payload, where the DOUBLE backslashes survive, and needs ${cwd//\\\\//}. MEASURED 2026-08-05: the raw form
# applied to a jq-decoded value matches nothing and leaves the path untouched - a silent no-op that looks
# exactly like a working fix. Do NOT unify the two spellings.
cwd_path=${cwd//\\//}
[ -z "$cwd_path" ] && cwd_path="."

[ -f "$HOME/.claude/.no-agy" ] && exit 0

# Repo root by walking up for .git, in-shell, so a .no-agy at the REPO ROOT is honoured when the session
# was launched from a subdirectory. The normalization above is load-bearing: ${_d%/*} strips on "/" only.
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

# Opt-out kill-switch (mirrors agy-after-reminder.sh).
if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
  exit 0
fi

# gate() binds `local cwd="$1"` rather than reading the global, so passing the NORMALIZED path genuinely
# changes what it stats - checked, because if it had read the global this would be a silent no-op.
[ "$(gate "$cwd_path")" = "fire" ] || exit 0

emit() { jq -n -c --arg ctx "$1" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'; }
emit 'AGY-TEST-AUDIT auto-fire: AGY-CAPSTONE is GREEN at this HEAD and the branch changed executable code/tests. BEFORE you declare the branch done, invoke the `agy-test-audit` skill to convene the live agy peer to audit the TEST SUITES for coverage exhaustiveness (untested reachable behaviours, vacuous/weak assertions, missing edge cases) - the orthogonal question the capstone does NOT ask. Load-bearing posture (the skill carries the full procedure and your driver'"'"'s transport): point the peer at the diff'"'"'s real test+source files by filepath (never a pasted summary); VERIFY every claimed gap BY MEASUREMENT before folding (the peer over-counts and states false gaps with confidence); the OWNER scopes which gaps to close; the driver authors each test and proves it NON-VACUOUS with a logic mutant; log deferred gaps as tracked debt. End with exactly one ASCII [VERDICT] token. If closing a gap needs an implementation-source refactor, that invalidates the capstone GREEN - re-run AGY-CAPSTONE. If the peer is unreachable, halt-and-ask or abort `[VERDICT: agy-required-but-unreachable]` - never a silent pass. COST: this discipline re-reads the whole session context every round, so running it in a long session burns several times the tokens - and subscription quota - of running it fresh. If this session carries substantial history, do not run it inline: tell the user it runs about 5x leaner after /compact or in a fresh session, and follow their answer. This changes WHERE the review runs, never WHETHER.'
exit 0

#!/usr/bin/env bash
# PINNING-ASSERTION-STRENGTH (plugin-shipped). PostToolUse(Write|Edit): the FIRST time each test file is
# touched in a session, name the three structural assertion-strength smells and point at the canonical
# prose. This is NOT an agy discipline - it convenes no peer (ROADMAP.md:712), so it carries no AGY-
# prefix and emits an [ASSERTION-STRENGTH] tag. The procedure lives in agy-test-audit/SKILL.md Step 5;
# this hook only POINTS at it and never runs a review. Fail-open: any error -> exit 0. Suppressed by
# .no-agy (cwd, repo root, or ~/.claude), matching every other hook this plugin ships.
#
# THE DEBOUNCE MARKER IS NOT A DISCIPLINE MARKER. It must never live in .clavity/agy-marks/ and must never
# be named *.head - docs/agy-disciplines-marker-contract.md reserves those for a SKILL recording a
# completed consult. The reason that contract gives (a hook fires before the consult and cannot know its
# outcome) does not apply here: this records a fact the hook does know, that it already emitted.
# Precedent and full rationale: agy-anomaly-capture-reminder.sh:49-53.
set +e
input=$(cat)

# --- jq guard. Without jq, fall back to a FIELD-BOUNDED grep on the RAW payload and, ONLY on a test-file
# match, emit a loud hard-coded ASCII line so this is never a silent no-op. Kill-switch honored first. ---
if ! command -v jq >/dev/null 2>&1; then
  [[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && cwd=${BASH_REMATCH[1]}
  cwd_path=${cwd//\\\\//}
  [ -z "$cwd_path" ] && cwd_path="."
  [ -f "$HOME/.claude/.no-agy" ] && exit 0
  if [ -f "$cwd_path/.no-agy" ]; then exit 0; fi
  # THIS PATTERN MUST FIRE ON EXACTLY THE SAME SET AS THE `case` PREDICATE BELOW, and it is pinned by the
  # 'degraded predicate agrees with the primary predicate' test. MEASURED 2026-08-08: an earlier draft
  # used [Tt]ests?\.ps1, which fired on footests.ps1 and foo.Test.ps1 where the case stayed silent - the
  # degraded branch was MORE eager than the primary one, the exact direction the owner ruled against.
  # Anchor the separator before the stem and drop the optional s.
  if printf '%s' "$input" | grep -Eq '"(file_path|path)"[[:space:]]*:[[:space:]]*"[^"]*([./\\][Tt]ests\.ps1|[Tt]ests\.cs|[Tt]est\.cs|_test\.(py|rs)|[./\\]test_[^"\\/]*\.(py|rs))"'; then
    # DEBOUNCE THE DEGRADED BRANCH TOO, ONCE PER SESSION. agy-after-reminder.sh's degraded branch emits on
    # every match because a spec/plan write is RARE. A test-file write is not - on this trigger an
    # undebounced warning is the high-frequency spam this discipline exists to remove, rebuilt one layer
    # down. One warning per session is enough to tell the operator the guard is inactive.
    [[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && dsid=${BASH_REMATCH[1]}
    dsid=${dsid//[^A-Za-z0-9_-]/}
    [ -z "$dsid" ] && printf -v dsid 'day%(%Y%m%d)T' -1
    for _dc in "${TMPDIR:-/tmp}" "$HOME/.clavity-tmp"; do
      [ -d "$_dc" ] || mkdir -p "$_dc" 2>/dev/null
      _dw="$_dc/.clavity-assert-nojq-$dsid"
      [ -f "$_dw" ] && exit 0
      if : > "$_dw" 2>/dev/null; then
        printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[ASSERTION-STRENGTH] guard inactive: missing jq - the assertion-strength reminder will not fire on test-file writes this session"}}'
        exit 0
      fi
    done
    # No writable location: warn the OPERATOR on stderr rather than emit to the model on every edit.
    printf '%s\n' "[ASSERTION-STRENGTH] guard inactive: missing jq, and no writable marker location - reminder disabled" >&2
  fi
  exit 0
fi

fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)
[ -z "$fp" ] && exit 0

# THE NORMALIZATION FORM MUST MATCH THE EXTRACTION SOURCE - see agy-after-reminder.sh:53-57. jq -r DECODES
# the JSON escaping, so cwd holds SINGLE backslashes here; the degraded branch above recovers cwd from the
# RAW payload where the DOUBLE backslashes survive. Do NOT unify the two spellings.
cwd_path=${cwd//\\//}
[ -z "$cwd_path" ] && cwd_path="."

[ -f "$HOME/.claude/.no-agy" ] && exit 0

# Repo root by walking up for .git, in-shell, so a .no-agy at the REPO ROOT is honoured when the session
# was launched from a subdirectory. ONE stat gates the walk - on an unreachable share every level pays an
# SMB timeout (agy-after-reminder.sh:69-72, MEASURED).
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
if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then exit 0; fi

# --- STRICT test-file predicate (owner ruling 2026-08-08). Filename patterns ONLY; prefer false-NEGATIVES.
# An over-eager guard trains the operator to ignore it, which is how an earlier guard in this repo died
# (ROADMAP.md:714-716). Deliberately EXCLUDED: anything under a tests/ tree that does not match by NAME -
# fixtures, .json, .csproj, .md. Evaluated with a builtin `case`, no subprocess. ---
norm=${fp//\\//}
base=${norm##*/}
fire=0
case "$base" in
  *.Tests.ps1|*.tests.ps1)   fire=1 ;;
  *Tests.cs|*Test.cs)        fire=1 ;;
  test_*.py|*_test.py)       fire=1 ;;
  test_*.rs|*_test.rs)       fire=1 ;;
esac
[ "$fire" -eq 0 ] && exit 0

# --- Per-file, per-session debounce. Location and naming are constrained by the precedent quoted in the
# header. SANITIZE before any payload-derived value becomes a filename: the capture below is [^"]*, which
# admits "/" and "..", and an unchecked concatenation would let a payload choose where a file lands
# (agy-anomaly-capture-reminder.sh:82-87). ---
[[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && sid=${BASH_REMATCH[1]}
sid=${sid//[^A-Za-z0-9_-]/}
if [ -z "$sid" ]; then
  # NO-SESSION-ID BRANCH. Owner ruling 2026-08-08 accepted this fallback outright rather than probe for
  # the field. Degrade to per-day, NOT to per-edit: firing on every edit is the spam this discipline
  # exists to avoid. printf %(...)T is a bash builtin - no subprocess.
  printf -v sid 'day%(%Y%m%d)T' -1
fi

seen=""
for _cand in "${TMPDIR:-/tmp}" "$HOME/.clavity-tmp"; do
  [ -d "$_cand" ] || mkdir -p "$_cand" 2>/dev/null
  _s="$_cand/.clavity-assert-seen-$sid"
  # THE EXISTS AND CREATE CASES MUST STAY SEPARATE, and the prune belongs ONLY to create.
  # agy-anomaly-capture-reminder.sh:96 breaks on an EXISTING marker without pruning; only :97-108, the
  # create path, prunes, and :99-100 states why: "It runs at most once per session and only on the path
  # that just proved itself writable, so it never touches the hot path." Collapsing these into a single
  # `[ -f ] || : >` condition puts `find` - a SUBPROCESS - on EVERY test-file write, which is the hottest
  # path this plugin has. Do not re-merge them.
  if [ -f "$_s" ]; then seen=$_s; break; fi
  if : > "$_s" 2>/dev/null; then
    seen=$_s
    # -mtime +30, NOT +7: the markers of a session that is still OPEN are as old as that session, and this
    # prune runs from a DIFFERENT session (agy-anomaly-capture-reminder.sh:103-106).
    find "$_cand" -maxdepth 1 -name '.clavity-assert-*' -mtime +30 -delete 2>/dev/null
    break
  fi
done

if [ -z "$seen" ]; then
  # BOTH failure directions are bugs. Silent -> permanently inert, the exact defect this item removes.
  # Always-fire -> spam. So warn the OPERATOR on stderr and stay silent to the MODEL. STDERR AT EXIT 0,
  # never exit 2 (exit 2 is BLOCKING on some events) - agy-anomaly-capture-reminder.sh:66-80.
  printf '%s\n' "[ASSERTION-STRENGTH] cannot write a session marker under TMPDIR or HOME - the assertion-strength reminder is disabled for this session" >&2
  exit 0
fi

# Exact membership, no hashing and no slugging: a slug can collide and silently suppress a different file.
# Read with the `read` builtin - no fork on this per-edit path.
while IFS= read -r _line; do
  [ "$_line" = "$norm" ] && exit 0
done < "$seen"
printf '%s\n' "$norm" >> "$seen"

msg="[ASSERTION-STRENGTH] You just touched a test file. Three structural smells produce a GREEN test over broken code: (1) CARDINALITY over an ordered or filtered collection - assert boundary IDENTITY, not count. (2) A DUAL-PATH FALLBACK masked by the ambient environment - strip the dependency to force it. (3) A STRUCTURED-TOKEN matcher with no DISTRACTOR case - show it REJECTS a near-miss. The agy-test-audit skill, Step 5 (the audit round, item 5) carries the full procedure, including proving non-vacuity against a logic mutant."
jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
exit 0

#!/usr/bin/env bash
# AGY-TEST-AUDIT trigger (plugin-shipped). PostToolUse: after AGY-CAPSTONE reaches GREEN, nudge the
# test-exhaustiveness audit exactly once for this HEAD. Marker-gated (docs/agy-disciplines-marker-contract.md):
#   fire IFF  .clavity/agy-marks/agy-capstone.head   == HEAD   (capstone is GREEN at this HEAD)
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
  local cwd="$1" head cap aud base changed
  head=$(git -C "$cwd" rev-parse HEAD 2>/dev/null) || return 1
  [ -n "$head" ] || return 1
  cap=$(cat "$cwd/$DIR_CONST/agy-capstone.head" 2>/dev/null)
  [ "$cap" = "$head" ] || return 1                       # capstone not GREEN at this HEAD
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
  printf '%s\n' "$changed" | grep -Eqi '\.(cs|fs|rs|ts|tsx|js|jsx|py|go|java|rb|c|h|cpp|hpp|sh|ps1)$' || return 1
  echo fire
}

# --- jq guard. jq parses stdin (cwd) + emits structured JSON. Without it: honor the kill-switch, then run
# the gate against the PROCESS cwd; ONLY when it would fire, emit a loud hardcoded ASCII line. ---
if ! command -v jq >/dev/null 2>&1; then
  # Without jq we cannot parse JSON, but the gate itself needs the real cwd (not the process cwd, which
  # may be an unrelated directory) to find the right repo's HEAD/markers. Extract it with a field-bounded
  # sed on the raw payload (same spirit as agy-after-reminder.sh's grep on file_path/path); fall back to
  # the process cwd only if the field is absent.
  cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  [ -z "$cwd" ] && cwd="."
  # Honor the kill-switch against the SAME cwd the gate uses (aligns with the jq path below).
  if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then exit 0; fi
  if [ "$(gate "$cwd")" = "fire" ]; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[AGY-DISCIPLINES] guard inactive: missing jq - the AGY-TEST-AUDIT reminder will not fire after capstone green"}}'
  fi
  exit 0
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)
[ -z "$cwd" ] && cwd="."

# Opt-out kill-switch (mirrors agy-after-reminder.sh).
if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  exit 0
fi

[ "$(gate "$cwd")" = "fire" ] || exit 0

emit() { jq -n -c --arg ctx "$1" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'; }
emit 'AGY-TEST-AUDIT auto-fire: AGY-CAPSTONE is GREEN at this HEAD and the branch changed executable code/tests. BEFORE you declare the branch done, invoke the `agy-test-audit` skill to convene the live agy peer to audit the TEST SUITES for coverage exhaustiveness (untested reachable behaviours, vacuous/weak assertions, missing edge cases) - the orthogonal question the capstone does NOT ask. Load-bearing posture (the skill carries the full procedure and your driver'"'"'s transport): point the peer at the diff'"'"'s real test+source files by filepath (never a pasted summary); VERIFY every claimed gap BY MEASUREMENT before folding (the peer over-counts and states false gaps with confidence); the OWNER scopes which gaps to close; the driver authors each test and proves it NON-VACUOUS with a logic mutant; log deferred gaps as tracked debt. End with exactly one ASCII [VERDICT] token. If closing a gap needs an implementation-source refactor, that invalidates the capstone GREEN - re-run AGY-CAPSTONE. If the peer is unreachable, halt-and-ask or abort `[VERDICT: agy-required-but-unreachable]` - never a silent pass. COST: this discipline re-reads the whole session context every round, so running it in a long session burns several times the tokens - and subscription quota - of running it fresh. If this session carries substantial history, do not run it inline: tell the user it runs about 5x leaner after /compact or in a fresh session, and follow their answer. This changes WHERE the review runs, never WHETHER.'
exit 0

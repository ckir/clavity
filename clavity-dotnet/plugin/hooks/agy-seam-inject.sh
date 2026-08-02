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
input=$(cat)

# --- jq guard (spec Decision 4). jq is required to parse stdin + emit structured JSON.
# Without it, fall back to a FIELD-BOUNDED grep on the skill value (never a bare substring,
# which could false-match a seam name mentioned in another skill's args) and, ONLY on a seam
# match, emit a loud printf-hardcoded ASCII line so a disabled hook is never silent. ---
if ! command -v jq >/dev/null 2>&1; then
  # Kill-switch still honored (global; cwd falls back to the process cwd without jq).
  if [ -f "./.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then exit 0; fi
  if printf '%s' "$input" | grep -Eq '"skill"[[:space:]]*:[[:space:]]*"[^"]*finishing-a-development-branch' \
     || printf '%s' "$input" | grep -Eq '"skill"[[:space:]]*:[[:space:]]*"[^"]*brainstorm' \
     || printf '%s' "$input" | grep -Eq '"skill"[[:space:]]*:[[:space:]]*"[^"]*subagent-driven-development' \
     || printf '%s' "$input" | grep -Eq '"skill"[[:space:]]*:[[:space:]]*"[^"]*executing-plans'; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[AGY-DISCIPLINES] guard inactive: missing jq - no seam directive will auto-fire (disciplines AND anomaly-capture)"}}'
  fi
  exit 0
fi

skill=$(printf '%s' "$input" | jq -r '.tool_input.skill // ""' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)

# Opt-out kill-switch (mirrors agy-after-reminder.sh): .no-agy in the session cwd or ~/.claude.
if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
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
# session and defeat the debounce. Inject UNLESS the marker exists AND its content == HEAD. ---
head=$(git -C "$cwd" rev-parse HEAD 2>/dev/null)
marker="$cwd/.clavity/agy-marks/$discipline.head"
if [ -n "$head" ] && [ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$head" ]; then
  exit 0
fi
# If HEAD cannot resolve (no repo / no commits), fall through and inject (safe: re-fires;
# the skill cannot write a HEAD-keyed marker in that context either).

emit() { jq -n -c --arg ctx "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'; }

case "$discipline" in
  agy-first)
    emit 'AGY-FIRST auto-fire: you are at a design/scope/approach/sequencing fork (the brainstorming approaches step). BEFORE committing to a direction, invoke the `agy-first` skill to run a divergent, review-only consult of the live agy peer over this fork. Load-bearing posture (the skill carries the full procedure and your driver'"'"'s transport): frame the fork as a GOAL plus a checkable SUCCESS CRITERION under forcing-function divergence vectors, not a vague "be creative" dial; VERIFY every bare factual claim the peer makes BY MEASUREMENT before folding it (it makes confident false claims); NEGOTIATE on material disagreement rather than defer-or-dismiss; end with exactly one ASCII [VERDICT] token. Best-effort discipline: the user still owns the decision. If agy is unreachable, the skill'"'"'s SKIPPED-UNREACHABLE path applies - proceed, do not hang.' ;;
  agy-capstone)
    emit 'AGY-CAPSTONE auto-fire: you are finishing a development branch (about to merge/PR). BEFORE you declare the work complete, invoke the `agy-capstone` skill to run a convergent, review-only agy review of the COMMITTED implementation (the executable code plus tests, NOT a plan artifact) in ROUNDS UNTIL GREEN. Load-bearing posture (the skill carries the full procedure and your driver'"'"'s transport): send the committed diff by filepath or git-range under adversarial lenses citing file:line; VERIFY every finding BY MEASUREMENT before folding it (the peer states false claims with confidence); fold the real ones, commit fixes, RE-RUN a fresh round with a do-not-re-raise ledger until a full round is GREEN; a human adjudicates GREEN (or an explicit round-cap waiver). End with exactly one ASCII [VERDICT] token. This catches executable-behaviour defects the pre-execution plan review structurally cannot. If agy is unreachable, the skill'"'"'s SKIPPED-UNREACHABLE path applies - proceed, do not hang.' ;;
  anomaly-dispatch)
    emit 'ANOMALY-CAPTURE: you are about to dispatch subagents. TWO obligations, and the second is the one that historically fails. (1) EVERY implementer dispatch you write MUST carry TWO clauses verbatim from the `open-issues` skill: the anomaly clause under "Dispatching a subagent", and the FILES clause naming every path that dispatch may touch. Then, when the subagent returns, run `git status --short` and compare the real change set against the list you gave it - a subagent has written outside its named set before, and the list is worthless without the diff. It asks the subagent to report anything wrong that is NOT its task under a `## Anomalies noticed` heading at the end of its final message, stated as a checkable fact, with an explicit `none` if it saw nothing. A subagent will not invoke that skill on its own, so the instruction has to travel IN the dispatch. (2) When a report comes back, VERIFY each claimed anomaly by measurement - open the file, run the command, reproduce it - and then APPEND the verified ones to .clavity/local-anomalies.md BEFORE you write your summary to the user. A subagent report is a claim, not evidence; and a verified anomaly that exists only in a chat message is lost the moment you compress that message. Capturing after summarizing is capturing never.' ;;
esac
exit 0

#!/usr/bin/env bash
# docs-audit-reminder - SessionStart nudge for open docs-audit findings (backlog stub
# docs/backlog/docs-audit-findings-are-invisible-to-git.md, owner ruling 2026-09-30: both audit artifacts stay
# gitignored, the findings reach a later session through this hook, like the anomalies nudge).
# Reads the RENDERED view, not the JSON store: the view is filtered to the current roster (ROADMAP §47), the store
# is not, so counting the store would nag about retired docs forever. Needs no jq.
# Never fails a session start: every path exits 0.
set +e
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
view="$root/docs/docs-audit-findings.md"
[ -f "$view" ] || exit 0                      # the audit never ran on this machine -> silent

emit() {
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$1" "$1"
  exit 0
}

head -n 1 "$view" 2>/dev/null | grep -q '^# docs audit findings (GENERATED' ||
  emit "[DOCS-AUDIT] docs/docs-audit-findings.md exists but is not a recognisable generated view - open findings NOT counted. Re-run just docs-audit."

# CR-tolerant: the renderer writes LF (measured), but a view saved from an editor may be CRLF, and `$` would then
# miss every '(no findings)' line and inflate the count.
text=$(tr -d '\r' < "$view" 2>/dev/null)
findings=$(printf '%s\n' "$text" | grep -c '^- ')
empty=$(printf '%s\n' "$text" | grep -c '^- (no findings)$')
unconfirmed=$(printf '%s\n' "$text" | grep -cE '^## .+ — AUDIT-')
open=$(( ${findings:-0} - ${empty:-0} ))
[ "$open" -le 0 ] && [ "${unconfirmed:-0}" -le 0 ] && exit 0
emit "[DOCS-AUDIT] ${open} open finding(s) and ${unconfirmed:-0} unconfirmed doc(s) in docs/docs-audit-findings.md - read it and triage."

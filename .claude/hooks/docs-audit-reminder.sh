#!/usr/bin/env bash
# docs-audit-reminder - SessionStart nudge for open docs-audit findings (backlog stub
# docs/backlog/docs-audit-findings-are-invisible-to-git.md, owner ruling 2026-09-30: both audit artifacts stay
# gitignored, the findings reach a later session through this hook, like the anomalies nudge).
# Reads the RENDERED view, not the JSON store: the view is filtered to the current roster (ROADMAP §47), the store
# is not, so counting the store would nag about retired docs forever. Needs no jq.
# Never fails a session start: every path exits 0.
set +e
root="${CLAUDE_PROJECT_DIR:-$PWD}"
view="$root/docs/docs-audit-findings.md"
[ -f "$view" ] || exit 0                      # the audit never ran on this machine -> silent

emit() {
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$1" "$1"
  exit 0
}

# Branch 21: the first line is read with the `read` builtin (head + grep were 4 processes). A FAILED OPEN keeps the old
# behaviour - first stays empty, so an unreadable view is "not a recognisable generated view", never a silent pass.
# The group is NON-negated on purpose and 2>/dev/null comes BEFORE the < (redirect order): see agy-anomaly-reminder.sh
# for the measured trap in `if ! { :; } < file`.
first=''
{ IFS= read -r first || :; } 2>/dev/null < "$view"
# (A CR ending the header line cannot matter: the pattern below is a PREFIX match.)
case "$first" in '# docs audit findings (GENERATED'*) : ;; *)
  emit "[DOCS-AUDIT] docs/docs-audit-findings.md exists but is not a recognisable generated view - open findings NOT counted. Re-run just docs-audit." ;;
esac

# One builtin pass replaces tr + three greps. CR-tolerant: the renderer writes LF (measured), but a view saved from an
# editor may be CRLF, and an unstripped CR would defeat the '(no findings)' match and inflate the count. CR is stripped
# PER LINE (the old tr stripped it file-wide; only line-end CRs occur in a CRLF save, so both see the same lines).
findings=0; empty=0; unconfirmed=0
re_unc='^## .+ — AUDIT-'
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%$'\r'}
  case "$line" in
    '- (no findings)') findings=$((findings + 1)); empty=$((empty + 1)) ;;
    '- '*)             findings=$((findings + 1)) ;;
  esac
  [[ $line =~ $re_unc ]] && unconfirmed=$((unconfirmed + 1))
done 2>/dev/null < "$view"
open=$((findings - empty))
[ "$open" -le 0 ] && [ "$unconfirmed" -le 0 ] && exit 0
emit "[DOCS-AUDIT] ${open} open finding(s) and ${unconfirmed} unconfirmed doc(s) in docs/docs-audit-findings.md - read it and triage."

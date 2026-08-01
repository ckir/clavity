#!/usr/bin/env bash
# AGY-ANOMALIES triage reminder (plugin-shipped). SessionStart(startup): an agent that notices a defect
# while doing something ELSE appends one line to .clavity/local-anomalies.md; this hook is the drain side.
# It COUNTS the untriaged entries and DEMANDS triage. Both halves matter: a reminder that only says
# "capture more" and never says "drain" produces a growing pile -- that is the measured failure of the
# sibling agy-learn inbox, which reached 69 entries against a stated threshold of 8 because its reminder
# never counts anything and never asks anyone to clear it.
#
# EMISSION = stderr + `exit 2`, deliberately, matching agy-liveness-check.sh. At SessionStart there is no
# user turn, so additionalContext/stdout is absorbed into the model's context and the OWNER never sees it.
# The owner is the one who triages, so the notice has to reach a human surface. exit 2 is non-blocking for
# SessionStart.
#
# NOT gated on a marker or a relevance path: the anomalies file has no natural relevance gate, and firing
# once per session is already the quietest useful cadence. It is silent whenever there is nothing to say.
# Suppressed by .no-agy (workspace or global) like the other reminders. Byte-identical across both driver
# plugins (kept honest by the seed-sync gate).
set +e
input=$(cat)

# jq is needed to read cwd out of the payload. Without it, say so once rather than failing silently -- a
# silent failure here is indistinguishable from "no anomalies", which is the exact confusion this hook
# exists to prevent. HONOR THE KILL-SWITCH FIRST, exactly as agy-liveness-check.sh does at its lines
# 26-36: without this, a machine that simply has no jq gets an unsuppressable boot warning forever, and
# .no-agy -- the documented way to turn the disciplines off -- would not turn it off.
if ! command -v jq >/dev/null 2>&1; then
  if [ -f "./.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
    exit 0
  fi
  printf '%s\n' "[AGY-ANOMALIES] guard inactive: missing jq - cannot check for untriaged anomalies; install jq" >&2
  exit 2
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)

# Opt-out kill-switch (mirrors agy-after-reminder.sh): silent, no notice.
if [ -f "$cwd/.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then
  exit 0
fi

# Resolve the REPOSITORY ROOT the same way the capture snippet does, so both sides always agree. A
# spotter that had cd'd into a subdirectory writes to the root; if this hook looked only at the payload
# cwd it would miss an anomaly that was captured correctly. Fall back to cwd outside a git worktree.
root=$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
[ -n "$root" ] || root="$cwd"

f="$root/.clavity/local-anomalies.md"
[ -f "$f" ] || exit 0

# An ENTRY is a bullet whose first token is ANY bracketed word: "- [defect] ...". Prose, headings and
# plain bullets are not entries, so the file's own preamble cannot inflate the count. The bracket content
# is deliberately NOT restricted to [a-z]: an agent that writes "[Defect]" or "[tool misbehavior]" has
# still captured a real anomaly, and a stricter pattern would count it as zero -- silently discarding the
# very thing this hook exists to surface. Triage can correct a sloppy type; it cannot recover a dropped one.
#
# Present-but-unreadable is NOT "no anomalies", and it is detected from grep's EXIT CODE rather than from
# a `[ -r "$f" ]` test. MEASURED on Windows Git Bash: the shell's -r builtin does NOT consult Windows ACLs
# and calls an ACL-denied file readable, so an -r guard never fires there; the read then fails inside grep,
# the count coerces to zero, and the hook exits silently -- the exact indistinguishable-empty-result this
# hook exists to prevent, reintroduced by the guard meant to prevent it. grep's contract is POSIX and
# platform-independent: 0 = matched, 1 = matched nothing, anything greater = error.
n=$(grep -c '^- \[[^]]*\]' "$f" 2>/dev/null)
rc=$?
if [ "$rc" -gt 1 ]; then
  printf '%s\n' "[AGY-ANOMALIES] $f exists but cannot be read - untriaged anomalies NOT counted" >&2
  exit 2
fi
[ -z "$n" ] && n=0
[ "$n" -eq 0 ] && exit 0

# Read the capture date from its FIELD, not from anywhere on the line. The format is
#   - [type] fact * where * DATE * task=...
# so the date is the field before the last. Scanning the whole line for an ISO date would pick up a date
# written inside the prose ("truncates messages from 2024-01-01 format") and report an age that is a lie.
# The separator is written as a CHARACTER CLASS, ' [*] ', not as an escaped ' \* '. MEASURED: the escaped
# form makes awk warn "escape sequence \* treated as plain *" and emit garbage instead of the field, so
# the date silently comes back empty. The class form has no escaping ambiguity.
oldest=$(grep '^- \[[^]]*\]' "$f" 2>/dev/null \
  | awk -F' [*] ' 'NF>=4 { print $(NF-1) }' \
  | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort | head -1)
[ -n "$oldest" ] && oldest=" (oldest $oldest)"

printf '%s\n' "[AGY-ANOMALIES] $n untriaged$oldest in .clavity/local-anomalies.md. Triage before new work: each entry is either PROMOTED to a tracked ROADMAP item with an owner, or DELETEd with a recorded reason. There is no parked state. Use the open-issues skill." >&2
exit 2

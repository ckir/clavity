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
  # cwd is recovered from the RAW payload with a bash regex, so this path is no longer blind to the
  # session's workspace -- it used to test "./.no-agy", the PROCESS cwd, which need not be the workspace.
  # Raw recovery keeps the JSON escaping, hence the DOUBLE-backslash pattern - see the note at the jq path.
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
  if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
    exit 0
  fi
  printf '%s\n' "[AGY-ANOMALIES] guard inactive: missing jq - cannot check for untriaged anomalies; install jq" >&2
  exit 2
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

# Resolve the REPOSITORY ROOT the same way the capture snippet does, so both sides always agree. A
# capturing session cd'd into a subdirectory writes to the root; if this hook looked only at the payload
# cwd it would miss an anomaly that was captured correctly. Fall back to cwd outside a git worktree.
#
# The walk is in-shell rather than `git rev-parse --show-toplevel` for two reasons: it must run BEFORE the
# workspace kill-switch (so a .no-agy at the root is honoured from a subdirectory, which a check against
# the payload cwd alone cannot do), and a subprocess-per-boot is avoidable. A .git entry matches as a
# directory (normal clone) or a file (worktree/submodule), which `-e` covers and `-d` would not. The
# normalization above is load-bearing: ${_d%/*} strips on "/" only.
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

# Opt-out kill-switch (mirrors agy-after-reminder.sh): silent, no notice.
if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
  exit 0
fi

# Check the payload cwd as a SECOND candidate. Outside a git worktree the two sides fall back to
# different defaults -- this hook to the session's cwd, the capture snippet to the capturing session's own $PWD --
# and a file written under one would be invisible to the other. Trying both closes the common case at the
# cost of one extra stat. RESIDUAL LIMIT, stated rather than papered over: in a NON-git directory whose
# capturing session had cd'd into a SUBdirectory, the capture lands somewhere neither path names and this hook will
# not see it. Inside a git worktree -- which is every case this plugin actually ships into -- both sides
# resolve to the same toplevel and the ambiguity does not arise.
f="$root/.clavity/local-anomalies.md"
[ -f "$f" ] || f="$cwd_path/.clavity/local-anomalies.md"
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
# Anchor on the task= field and take the one before it, rather than counting from either end. MEASURED:
# counting from the LEFT breaks when the fact contains " * "; counting from the RIGHT with $(NF-1) breaks
# when the task does ("task=investigating * timeout" silently yields no date). Anchoring survives both,
# because task= is the only field with a fixed marker.
oldest=$(grep '^- \[[^]]*\]' "$f" 2>/dev/null \
  | awk -F' [*] ' '{ for (i=1; i<=NF; i++) if ($i ~ /^task=/) { print $(i-1); break } }' \
  | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort | head -1)
[ -n "$oldest" ] && oldest=" (oldest $oldest)"

# Name the RESOLVED path, not a relative one. The reader may have started the session in a subdirectory,
# and a notice that says ".clavity/local-anomalies.md" sends them to a path that does not exist from where
# they are standing -- at exactly the moment they are least inclined to go hunting for it.
printf '%s\n' "[AGY-ANOMALIES] $n untriaged$oldest in $f. Triage before new work: each entry is either PROMOTED to a tracked ROADMAP item with an owner, or DELETEd with a recorded reason. There is no parked state. Use the open-issues skill." >&2
exit 2

#!/usr/bin/env bash
# AGY-ANOMALIES capture reminder (plugin-shipped). PreCompact(manual|auto): the CAPTURE side of the
# discipline, addressed to the MODEL. Its sibling agy-anomaly-reminder.sh is the DRAIN side, addressed to
# the OWNER at SessionStart. Before this hook, the discipline had a drain push and no capture push: a
# driver working DIRECTLY -- not dispatching -- that noticed a defect got nothing from any hook at any
# moment, because the capture contract lived only inside a skill it had to decide to pull unprompted, at
# exactly the moment its attention is elsewhere by construction.
#
# EMISSION = the JSON ENVELOPE on stdout at exit 0, and the envelope is EVENT-SPECIFIC.
# MEASURED by a three-arm sentinel: plain stdout at exit 0 reaches the model NOT AT ALL (silently
# discarded), and stdout at exit 2 is dropped too -- only stderr survives there. So a hook written with a
# bare printf of the text produces no error, no output, and looks installed and working.
# hookSpecificOutput is INVALID for PreCompact: Claude Code rejects the payload outright and the owner
# sees a schema-validation dump instead of the reminder. PreCompact must use top-level systemMessage.
# The same split is documented and implemented at agy-autotrain/hooks/agy-learn-reminder.sh:32-40.
#
# THE MESSAGE CARRIES NO BACKTICK, APOSTROPHE, DOUBLE QUOTE OR BACKSLASH. The first two are bash quoting
# hazards (a backtick inside a double-quoted string is command substitution; an apostrophe terminates a
# single-quoted one), and the last two would break the hand-built JSON envelope on the jq-absent path
# below, which has no escaping machinery. All four are asserted at BYTE level against the EMITTED text by
# scripts/tests/agy-anomaly-capture-reminder.Tests.ps1. Markdown decoration buys nothing inside a prompt
# string, so it is removed rather than escaped.
#
# Fail-open: any error -> exit 0. Suppressed by .no-agy (workspace or global) like every other reminder.
# Byte-identical across both driver plugins (kept honest by scripts/check-seed-artifacts-synced.sh).
set +e
input=$(cat)

event="${1:-PreCompact}"

# TWO messages, ONE contract stamp. The stamp is what scripts/tests/agy-anomaly-contract-stamp.Tests.ps1
# pins and what scripts/discipline-reaching-report.ps1 counts, so it must appear in BOTH or the recorder
# under-counts the new channel silently -- the v15 failure signature, one channel over.
msg_precompact='AGY-ANOMALIES/1 check BEFORE COMPACTION: did you VERIFY a defect this session that is OUTSIDE your current task and is not yet in .clavity/local-anomalies.md? Capture it now via the open-issues skill - one line: - [type] fact * path:LINE * DATE * task=<what you were doing>. Uncaptured anomalies are lost at compaction. NOT an anomaly: a test you expected to fail, an error in the work you are actively doing, or anything you have not verified by measurement. If nothing qualifies, do nothing - a speculative entry is worse than none, because it lands on a blocking triage gate.'

msg_prompt='AGY-ANOMALIES/1 check: earlier in this session, did you VERIFY a defect that is OUTSIDE your current task and is not yet in .clavity/local-anomalies.md? Capture it now via the open-issues skill - one line: - [type] fact * path:LINE * DATE * task=<what you were doing>. NOT an anomaly: a test you expected to fail, an error in the work you are actively doing, or anything you have not verified by measurement. If nothing qualifies, do nothing - a speculative entry is worse than none, because it lands on a blocking triage gate.'

case "$event" in
  UserPromptSubmit) msg=$msg_prompt ;;
  *)                msg=$msg_precompact ;;
esac

# GATE (UserPromptSubmit only). Two conditions, both required:
#   (a) never on the first prompt of a session -- at that moment the driver has done no work and can have
#       observed nothing, and a prompt that arrives before anything could be noticed trains the reflexive
#       "none" answer that the capture-gap spec records at :65/:67 as worse than no prompt at all;
#   (b) at most once per session thereafter.
#
# THIS MARKER IS NOT A DISCIPLINE MARKER. It must never live in .clavity/agy-marks/, must never be read as
# evidence that anything was DELIVERED, and must never be named *.head. docs/agy-disciplines-marker-contract.md
# forbids a hook writing a .head marker, and gives the reason: a hook fires before the consult and cannot
# know its outcome. That reason does not apply here -- this records a fact the hook does know, that it
# already emitted -- but the two must stay visibly separate or the next reader will conflate them.
#
# NO SUBPROCESS ON THE PER-PROMPT PATH: the session id comes out of the payload with a bash regex, not jq
# and not git. MEASURED 2026-08-06 and recorded at :48-51 of this file: a per-invocation subprocess on a
# path that runs every turn is not affordable. The ONE exception is the prune below, which runs at most
# once per session on the first prompt -- not every turn -- and is the price of not growing a marker
# directory without bound.
if [ "$event" = "UserPromptSubmit" ]; then
  [[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && sid=${BASH_REMATCH[1]}
  # No session id -> no gate is possible -> stay SILENT rather than emit on every prompt. An ungated
  # emission here would fire on every turn forever, which is strictly worse than not firing.
  [ -z "$sid" ] && exit 0

  # THE MARKER WRITE MUST BE CHECKED, AND BOTH FAILURE DIRECTIONS ARE BUGS.
  #
  # If the marker cannot be written (temp missing, read-only, quota, a sandboxed TMPDIR):
  #   - exiting quiet means the reminder NEVER fires again -- installed, registered, permanently inert,
  #     with no signal. That is verbatim the defect this item exists to remove, rebuilt one layer down.
  #   - falling through to emit means the reminder fires on EVERY prompt for the rest of the session,
  #     which is the high-frequency spam this plan's own rationale calls worse than no prompt at all
  #     (capture-gap spec :65/:67). Trading a silent failure for a noisy one is not a fix.
  #
  # So: try a SECOND location before giving up, and if both fail, warn the OPERATOR on stderr and stay
  # silent to the MODEL. Precedent for exactly this shape is agy-inbox-snapshot.sh:60-63, which warns on
  # stderr when it cannot write its .bak rather than failing silently or looping.
  #
  # STDERR AT EXIT 0, never exit 2. Exit 2 is BLOCKING on some events, and blocking the user's prompt to
  # report a marker problem is catastrophically out of proportion.
  #
  # SANITIZE THE SESSION ID BEFORE IT BECOMES A FILENAME. The regex above captures [^"]* -- anything that
  # is not a quote, which includes "/" and "..". Concatenated into a path unchecked, a payload would get
  # to decide where a file lands. Strip to a safe set; if nothing survives, there is no usable key, so
  # exit rather than fall back to a shared name that would suppress every session on the machine.
  sid=${sid//[^A-Za-z0-9_-]/}
  [ -z "$sid" ] && exit 0

  # Try each location in order. The FIRST prompt of a session creates the marker and stays quiet; every
  # later prompt finds it and proceeds. An unusable location is skipped, so a broken TMPDIR costs the
  # fallback, not the discipline.
  seen=""
  for _cand in "${TMPDIR:-/tmp}" "$HOME/.clavity-tmp"; do
    [ -d "$_cand" ] || mkdir -p "$_cand" 2>/dev/null
    _s="$_cand/.clavity-anomaly-seen-$sid"
    if [ -f "$_s" ]; then seen=$_s; sent="$_cand/.clavity-anomaly-sent-$sid"; break; fi
    if : > "$_s" 2>/dev/null; then
      # (a) FIRST PROMPT of this session: marker now recorded, emit nothing this turn.
      # Prune this location while we are here. It runs at most once per session and only on the path that
      # just proved itself writable, so it never touches the hot path. $HOME/.clavity-tmp in particular has
      # NO OS temp reaper behind it -- without this, a machine with a broken TMPDIR grows two files per
      # session forever.
      # -mtime +30, NOT +7. The markers of a session that is still OPEN are as old as that session, and
      # this prune runs from a DIFFERENT session -- so too short a window deletes a live session's markers
      # and makes it emit a second time. 30 days is comfortably longer than any real session while still
      # bounding the directory.
      find "$_cand" -maxdepth 1 -name '.clavity-anomaly-*' -mtime +30 -delete 2>/dev/null
      exit 0
    fi
  done

  if [ -z "$seen" ]; then
    printf '%s\n' "[AGY-ANOMALIES] cannot write a session marker under TMPDIR or HOME - the direct-driver capture reminder is disabled for this session" >&2
    exit 0
  fi

  # (b) SUBSEQUENT PROMPTS: emit once, then never again.
  [ -f "$sent" ] && exit 0
  : > "$sent" 2>/dev/null
fi

# jq is needed only to read cwd out of the payload. Without it, STILL DELIVER: emit the same message in a
# hand-built envelope rather than exiting silently. A silent exit here is precisely the invisible zero
# this hook exists to remove -- and it is invisible in both directions, because an absent nudge and a
# nudge with nothing to say look identical from outside. Honor the kill-switch FIRST (agy-anomaly-reminder.sh
# records the defect this ordering prevents: a machine that simply has no jq otherwise gets an
# unsuppressable nudge forever). cwd is recovered from the RAW payload with a bash regex, so this path is
# no longer blind to the session's workspace -- it used to test "./.no-agy", the PROCESS cwd, which is not
# necessarily the workspace at all.
if ! command -v jq >/dev/null 2>&1; then
  [[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && cwd=${BASH_REMATCH[1]}
  # Raw recovery keeps the JSON escaping, hence the DOUBLE-backslash pattern - see the note at the jq path.
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
  if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then exit 0; fi
  case "$event" in
    UserPromptSubmit) printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$msg" ;;
    *)                printf '{"systemMessage":"%s"}\n' "$msg" ;;
  esac
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

if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
  exit 0
fi

case "$event" in
  UserPromptSubmit) jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$m}}' ;;
  *)                jq -nc --arg m "$msg" '{systemMessage:$m}' ;;
esac
exit 0

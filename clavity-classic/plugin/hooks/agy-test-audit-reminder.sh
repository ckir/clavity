#!/usr/bin/env bash
# AGY-TEST-AUDIT trigger (plugin-shipped). PostToolUse: after AGY-CAPSTONE reaches GREEN, nudge the
# test-exhaustiveness audit exactly once for this HEAD. Marker-gated (docs/agy-disciplines-marker-contract.md):
#   fire IFF  .clavity/agy-marks/agy-capstone.head   still describes HEAD - either it EQUALS HEAD, or it
#             is an ANCESTOR of HEAD and nothing executable landed since it (see gate() for why)
#        AND  .clavity/agy-marks/agy-test-audit.head  does NOT still describe HEAD, by the same rule
#             (an audit that covered the reviewed tip still covers a docs-only commit made after it)
#        AND  the reviewed range touched executable code / test paths (spec 4: docs-only must not nudge)
# This SEQUENCES capstone->audit structurally (the capstone marker is written ONLY on human-GREEN or a
# round-cap waiver), without touching the strict 1:1 agy-seam-inject.sh case statement. The directive POINTS
# AT the agy-test-audit skill (which carries the procedure + per-transport clause), so this file is
# byte-identical across both driver plugins. It NEVER writes a marker (a hook fires before the consult and
# cannot know its outcome); its only state is the per-session debounce file under $TMPDIR (see below). Fail-open: any error -> exit 0. Suppressed by .no-agy (cwd or ~/.claude).
# Without jq it degrades LOUD only when the gate would fire (never a silent no-op, never a false alarm).
set +e
# stderr is silenced ONCE, here: a per-command `2>/dev/null` inside a command substitution costs an extra
# process (MEASURED: `x=$(jq -r . 2>/dev/null)` 6 vs `x=$(jq -r .)` 5). Nothing in this hook writes to stderr.
exec 2>/dev/null
# PROCESS BUDGET (owner ruling: at most 16 processes per hook run, bash's own boot included; on this
# platform every process costs ~200ms and this hook runs after EVERY tool call). So: no `$(cat)` (2),
# no `$(dirname)` (2), no `printf | jq` / `printf | grep` pipelines (3 each), no command substitution
# around gate() (1) - the shell does that work itself with builtins, and the git work is batched into
# the fewest calls that answer the same questions.
# The payload is read into $input only when jq is ABSENT (the degraded branch parses it with bash regexes).
# With jq present, jq reads this hook's own stdin directly: feeding it from a variable (`<<<`) costs a
# third process (MEASURED: `$(jq <<<x)` 6 vs `$(jq)` 5 on a 3-process boot).
if command -v jq >/dev/null 2>&1; then _have_jq=1; else _have_jq=''; if [ -z "${CLAVITY_HOOK_BASH3:-}" ] && ((BASH_VERSINFO[0]*100+BASH_VERSINFO[1] >= 401)); then input=; while IFS= read -r -N 1048576 _c; do input+=$_c; done; input+=$_c; else input=$(cat); fi; fi

# DEBOUNCE (owner-approved): the directive is ~450 tokens and the gate holds for EVERY tool call until the
# audit is done, so it is emitted at most once per (session, HEAD). The state lives OUTSIDE the repo, in
# ${TMPDIR:-/tmp}/claude-agy-test-audit-reminder.<session_id>, and holds the HEAD sha last fired for - a
# new commit or a new session re-arms it. It is NOT a marker (it never gates anything but this hook's own
# repetition), so "never writes a marker" below still holds. Any failure to read or write it errs toward
# REMINDING, never toward silence.
_state=''; _head=''

# ROADMAP section 39: both marker paths come from the SAME builder agy-mark.sh writes with. If it cannot be
# loaded both stay empty, both reads come back empty, and the gate stays SILENT - it can then see no GREEN,
# which is the safe answer at this hook's capstone call site.
_cap_rel=''; _aud_rel=''
# dirname "$0" without the process. BOTH separators: the suites invoke hooks as `bash 'C:\x\hooks\h.sh'`,
# and msys dirname understands the backslash form where a bare ${0%/*} returns $0 unchanged.
_hd=${0%[/\\]*}; [ "$_hd" = "$0" ] && _hd=.
if . "$_hd/agy-marker-lib.sh" 2>/dev/null; then
  agy_marker_rel _cap_rel agy-capstone
  agy_marker_rel _aud_rel agy-test-audit
fi

# Byte-exact stand-in for  var=$(cat file 2>/dev/null)  without the process: ALL of the file, every trailing
# newline stripped. $1 = out-var, $2 = file. A missing/unreadable file leaves the var empty.
_slurp() {
  local _v=''
  { IFS= read -r -d '' _v < "$2"; } 2>/dev/null
  while [[ $_v == *$'\n' ]]; do _v=${_v%$'\n'}; done
  printf -v "$1" '%s' "$_v"
}

# gate() - sets _head and returns 0 iff the reminder should fire; returns 1 (silent) otherwise.
#
# Does a marker sha still describe HEAD? True when it IS HEAD, or is an ANCESTOR of HEAD with nothing
# executable landed since. BOTH markers age for the same reason and are forgiven by the same rule - which
# is the whole point of it being ONE rule applied to both.
#
# WHY IT IS SHARED. 2026-08-26, fced293 relaxed only the CAPSTONE marker, to stop the ledger row the
# capstone skill REQUIRES from silencing this nudge. That left the AUDIT marker strict, and so punished
# exactly the driver who did the right thing: run the audit at the reviewed tip, then commit the ledger
# row, and the nudge fired again demanding a second run. The obvious one-line repair - swap `aud == head`
# for `aud == cap` - fixes that case and breaks its mirror, an audit run AFTER the ledger row, which then
# nudges forever. Both orderings are legitimate. One rule, both markers.
#
# A failing git command answers "no" rather than "yes" - and READ THAT CAREFULLY, because the two markers
# want opposite things from it and the code is right in both places. For the capstone marker a "no" means
# "there is no GREEN covering HEAD", and it goes silent: nudging for an audit with no capstone behind it
# would be a false alarm. For the audit marker a "no" means "nothing shows this HEAD was audited", and it
# lets the hook FIRE: staying quiet there would silently drop an audit that is genuinely owed. Same
# answer, opposite safe directions.
#
# HOW IT IS COMPUTED (process budget - every git call is ~2 processes here, and the first version of this
# gate could start 40+). The questions are the same ones the one-call-each version asked; they are just
# batched, in this order, each call only when an earlier answer has not already settled the gate:
#   0. no capstone marker -> silent, before ANY process (the common case: this hook runs on every call).
#   1. ONE `cat-file --batch-check` resolves HEAD, both marker shas and every integration-ref candidate
#      (`<name>^{commit}`; a miss prints `<name> missing`, so nonexistent refs cost nothing later).
#   2. the DEBOUNCE check - HEAD is known, so a repeat call at an already-reminded HEAD stops here.
#   3. ONE `rev-list <markers> ^HEAD` answers "is the marker an ancestor of HEAD" for both markers at once:
#      a marker is an ancestor iff it is absent from the commits reachable from it but not from HEAD.
#   4. `merge-base HEAD <ref>` for the first candidate that exists AND shares history (the original chain
#      origin/main-or-$CLAVITY_AUDIT_BASE_REF, origin/HEAD, main, master).
#   5. ONE `diff-tree --stdin` lists the changed files of every range at once (marker..HEAD for each pending
#      marker, base..HEAD or - fallback - HEAD's own commit). Each block is headed by its first sha, and the
#      per-line regex below replaces `grep -Eqi` (grep is per line too, so `^`/`$` mean the same).
gate() {
  local cwd="$1" head cap aud base bkey capst audst capfull audfull oid line cur tips unreach out rc i
  local capcode=0 audcode=0 basecode=0 lst refname res
  # The executable-path list, held ONCE. Two copies would be two definitions of "executable code" free to
  # drift apart.
  # WHAT COUNTS AS EXECUTABLE. Until 2026-08-26 this listed seventeen source extensions and none of the
  # three things this repository gates ITSELF with: `agy-autotrain/installer/agy-autotrain.iss`, a Pascal
  # program that deletes user data; the `.yml` workflows; and the `justfile` that is the test gate. Both
  # readers of this list failed in the same direction: a range of such changes never nudged for an audit,
  # and a capstone GREEN was extended across them as though nothing executable had landed.
  #
  # The sentence here used to attribute that to "rounds 17, 18 and 19 all changed the .iss", which is
  # FALSE - measured with `git show --name-only`, none of those three folds touched it; the .iss changes
  # in this range came from earlier folds and from round 21. The defect was real and the fix is unchanged;
  # the provenance was invented, in a commit whose subject was other people's false claims. Naming the
  # FILE TYPES rather than the rounds also cannot rot: which commit changed what is a fact about history,
  # and this list is about what the repository is made of.
  local CODE_RE='(\.(cs|fs|rs|ts|tsx|js|jsx|py|go|java|rb|c|h|cpp|hpp|sh|ps1|psm1|psd1|iss|yml|yaml|bat|cmd|csproj|fsproj|props|targets|toml)$|(^|/)justfile$)'
  # THE LEDGER-ROW CASE, in one line each. agy-capstone writes the reviewed tip to its marker and then
  # REQUIRES a row in docs/agy-capstone-ledger.md before a plan may be declared complete; committing that
  # row advances HEAD. MEASURED 2026-08-26 in this repository: marker f29cd42, next commit f209632
  # "docs(ledger): record ... GREEN", silent for EVERY commit that followed - which is why two
  # test-audits were owed with nothing nudging for either.
  cap=''; [ -n "$_cap_rel" ] && _slurp cap "$cwd/$_cap_rel"
  [ -n "$cap" ] || return 1                       # no GREEN at all (also: no git repo, no marker lib)
  aud=''; [ -n "$_aud_rel" ] && _slurp aud "$cwd/$_aud_rel"

  # Step 1. A marker holding a newline (or nothing) cannot be one line of the batch: use a name that cannot
  # resolve, which is exactly what git would have answered for it.
  refname="${CLAVITY_AUDIT_BASE_REF:-origin/main}"
  lst=HEAD
  for oid in "$cap" "$aud" "$refname" origin/HEAD main master; do
    if [ -z "$oid" ] || [[ $oid == *$'\n'* ]]; then oid='?'; fi
    lst+=$'\n'"$oid^{commit}"
  done
  out=$(git -C "$cwd" cat-file --batch-check='%(objectname) %(objecttype)' <<<"$lst")
  res=(); while IFS= read -r _l; do res+=("$_l"); done <<<"$out"   # not mapfile: bash 3.2 has none
  _oid() { # $1 out-var, $2 index into the batch answer: the full commit sha, or empty if it did not resolve
    if [[ ${res[$2]-} =~ ^([0-9a-f]{40,64})\ commit$ ]]; then printf -v "$1" '%s' "${BASH_REMATCH[1]}"; else printf -v "$1" ''; fi
  }
  _oid head 0
  [ -n "$head" ] || return 1

  # Step 2. DEBOUNCE. Keyed on HEAD, so it can only run once HEAD is known. Equivalent to running the whole
  # gate first: a "no" and a debounced "yes" are both silent.
  if [ -n "$_state" ]; then
    out=''; { IFS= read -r out < "$_state"; } 2>/dev/null
    [ "$out" = "$head" ] && return 1
  fi

  # Per-marker state: y = describes HEAD, n = does not, p = pending (an ancestor test + a diff are owed).
  _oid capfull 1; _oid audfull 2
  capst=n; audst=n
  if [ "$cap" = "$head" ] || [ -n "$capfull" -a "$capfull" = "$head" ]; then capst=y; elif [ -n "$capfull" ]; then capst=p; fi
  if [ -z "$aud" ]; then audst=n
  elif [ "$aud" = "$head" ] || [ -n "$audfull" -a "$audfull" = "$head" ]; then audst=y
  elif [ -n "$audfull" ]; then audst=p; fi
  [ "$capst" = n ] && return 1                    # no GREEN that covers HEAD
  [ "$audst" = y ] && return 1                    # an audit already covers HEAD

  # Step 3. Ancestry, both markers in one call. A failing call answers "not an ancestor" for both.
  tips=''
  [ "$capst" = p ] && tips=$capfull
  [ "$audst" = p ] && tips="$tips $audfull"
  if [ -n "$tips" ]; then
    # shellcheck disable=SC2086  # $tips is two shas, split on purpose
    unreach=$(git -C "$cwd" rev-list $tips "^$head")
    rc=$?
    if [ $rc -ne 0 ]; then
      [ "$capst" = p ] && capst=n
      [ "$audst" = p ] && audst=n
    else
      [ "$capst" = p ] && [[ $unreach == *"$capfull"* ]] && capst=n
      [ "$audst" = p ] && [[ $unreach == *"$audfull"* ]] && audst=n
    fi
    [ "$capst" = n ] && return 1                  # the GREEN is not even on this history
  fi

  # Step 4. Reviewed range: merge-base with an integration ref, else this commit's own files (on-branch / no ref).
  # The chain after the first ref (capstone Branch 2 round 3, owner ruling 2026-09-30 after AGY-FIRST): a
  # repository whose integration branch is NOT main fell straight to HEAD's own commit, and after the
  # capstone's mandatory docs-only ledger commit that silenced an owed audit - measured in a `master` repo.
  # origin/HEAD is the remote's default branch, whatever it is called (set by `git clone`). A shallow clone
  # whose fork point is outside the fetched depth still reaches the HEAD-only fallback.
  base=''
  for i in 3 4 5 6; do
    _oid oid $i
    [ -n "$oid" ] || continue
    base=$(git -C "$cwd" merge-base "$head" "$oid")
    [ -n "$base" ] && break
  done

  # Step 5. Every range's file list in ONE call. --root and --cc make a single-commit line behave like
  # `git show --format= --name-only` (a root commit lists its files, a merge lists the combined diff).
  # --no-renames and diff.relative=false on EVERY name-only list in this file (capstone Branch 2 round 2,
  # measured): a rename lists only its new path, so src/x.sh -> docs/x.md hid a code change here and the
  # stale capstone still "covered" HEAD; diff.relative, from a subdirectory cwd, drops out-of-cwd paths.
  lst=''
  [ "$capst" = p ] && lst+="$capfull $head"$'\n'
  [ "$audst" = p ] && lst+="$audfull $head"$'\n'
  if [ -n "$base" ] && [ "$base" != "$head" ]; then bkey=$base; lst+="$base $head"; else bkey=$head; lst+="$head"; fi
  out=$(git -C "$cwd" -c core.quotePath=false -c diff.relative=false diff-tree --stdin --root --cc -r --no-renames --name-only <<<"$lst")
  [ $? -eq 0 ] || return 1
  local _nc=0; shopt -q nocasematch && _nc=1
  shopt -s nocasematch                            # grep -i
  cur=''
  while IFS= read -r line; do
    # A header is the first sha of an input line; only the shas WE sent count, so a path that merely looks
    # like a sha cannot re-attribute the lines after it.
    if [ -n "$line" ] && { [ "$line" = "$capfull" ] || [ "$line" = "$audfull" ] || [ "$line" = "$bkey" ]; }; then cur=$line; continue; fi
    [ -n "$cur" ] || continue
    if [[ $line =~ $CODE_RE ]]; then
      [ "$cur" = "$capfull" ] && capcode=1
      [ "$cur" = "$audfull" ] && audcode=1
      [ "$cur" = "$bkey" ] && basecode=1
    fi
  done <<<"$out"
  (( _nc )) || shopt -u nocasematch
  [ "$capst" = p ] && [ $capcode -eq 1 ] && return 1   # executable code landed after the GREEN: stale
  [ "$audst" = p ] && [ $audcode -eq 0 ] && return 1   # nothing executable since the audit: it still covers HEAD
  # Executable-code / test path heuristic. Empty match -> silent (docs/config/spec-only range, spec 4).
  [ $basecode -eq 1 ] || return 1
  _head=$head
  return 0
}

# Remember that we reminded for this HEAD. Called ONLY after the directive went out. ONE in-shell write of
# a 41-byte line: no mkdir (the file sits directly in $TMPDIR, which exists) and no tmp+mv - each of those
# is an external process (~2) and the firing path is already at 15 of the 16-process ceiling. The cost of
# not being atomic is a reader racing the truncate+write, seeing nothing or a partial sha, and reminding
# once more - the safe direction. A failed write (read-only/missing $TMPDIR) is swallowed: still reminds.
_remember() {
  [ -n "$_state" ] && [ -n "$_head" ] || return 0
  { printf '%s\n' "$_head" > "$_state"; } 2>/dev/null
  return 0
}

# State path for a session id. Same sanitising as the consult guard: anything outside A-Za-z0-9_- becomes
# `_`, empty becomes `default`. Spelled out rather than written as a range so a locale's collation order
# cannot widen it; the result cannot contain `/` or be `..`, so it cannot leave $TMPDIR.
_set_state() {
  local _ok='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-' _s="$1"
  _s=${_s//[^$_ok]/_}
  [ -n "$_s" ] || _s=default
  _state="${TMPDIR:-/tmp}/claude-agy-test-audit-reminder.$_s"
}

# --- jq guard. jq parses stdin (cwd) + emits structured JSON. Without it: honor the kill-switch, then run
# the gate against the PROCESS cwd; ONLY when it would fire, emit a loud hardcoded ASCII line. ---
if [ -z "$_have_jq" ]; then
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
  # The session id, from the RAW payload like the cwd above (it is sanitised to A-Za-z0-9_- either way).
  sid=''
  [[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && sid=${BASH_REMATCH[1]}
  _set_state "$sid"
  if gate "$cwd_path"; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[AGY-DISCIPLINES] guard inactive: missing jq - the AGY-TEST-AUDIT reminder will not fire after capstone green"}}'
    _remember
  fi
  exit 0
fi

# ONE jq call yields both fields (cwd, session_id), joined by \u0001 - a character no path or id contains.
# `$(...)` strips trailing newlines, which the old one-field-per-call form did to the cwd too.
out=$(jq -r '"\(.cwd // ".")\u0001\(.session_id // "")"')
cwd=${out%%$'\001'*}
sid=${out#*$'\001'}
while [[ $cwd == *$'\n' ]]; do cwd=${cwd%$'\n'}; done
_set_state "$sid"
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
gate "$cwd_path" || exit 0

# Same bytes as `jq -n -c --arg ctx "$1" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'`
# without the 2 processes (this is the FIRING path, the one that is closest to the 16-process ceiling).
# The text below is plain printable ASCII, so the only escapes JSON needs are backslash and double quote.
# A native Windows jq.exe ends its output with CRLF (MEASURED), a Linux jq with LF: keep each host's bytes.
emit() {
  local m=$1
  m=${m//\\/\\\\}
  m=${m//\"/\\\"}
  m=${m//$'\n'/\\n}; m=${m//$'\r'/\\r}; m=${m//$'\t'/\\t}
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$m"
}
emit 'AGY-TEST-AUDIT auto-fire: AGY-CAPSTONE is GREEN for this HEAD (its marker is AT HEAD, or behind it with nothing executable landed since) and the branch changed executable code/tests. BEFORE you declare the branch done, invoke the `agy-test-audit` skill to convene the live agy peer to audit the TEST SUITES for coverage exhaustiveness (untested reachable behaviours, vacuous/weak assertions, missing edge cases) - the orthogonal question the capstone does NOT ask. Load-bearing posture (the skill carries the full procedure and your driver'"'"'s transport): point the peer at the diff'"'"'s real test+source files by filepath (never a pasted summary); VERIFY every claimed gap BY MEASUREMENT before folding (the peer over-counts and states false gaps with confidence); the OWNER scopes which gaps to close; the driver authors each test and proves it NON-VACUOUS with a logic mutant; log deferred gaps as tracked debt. End with exactly one ASCII [VERDICT] token. If closing a gap needs an implementation-source refactor, that invalidates the capstone GREEN - re-run AGY-CAPSTONE. If the peer is unreachable, halt-and-ask or abort `[VERDICT: agy-required-but-unreachable]` - never a silent pass. COST: this discipline re-reads the whole session context every round, so running it in a long session burns several times the tokens - and subscription quota - of running it fresh. If this session carries substantial history, do not run it inline: tell the user it runs about 5x leaner after /compact or in a fresh session, and follow their answer. This changes WHERE the review runs, never WHETHER.'
_remember
exit 0

#!/usr/bin/env bash
# agy-consult VCS-diff guard, shared library.
# Sourced by agy-consult-guard-pre.sh (PreToolUse) and -post.sh (PostToolUse).
# Enforces the standing rule: an agy REVIEW-ONLY consult must make ZERO VCS changes.
# READ-ONLY - it only reports; it never reverts, stages, commits, or blocks. Fail-open.
#
# Consult channels & CATEGORIES:
#   sync     : MCP `agy_ask` tool  |  shell `clavity ask`      -> peer works INSIDE one blocking
#              call; Pre/Post bracket the mutation window exactly. PRECISE.
#   open     : shell `clavity send`      -> async initiator; peer works in a detached window.
#   terminal : shell `clavity await-reply` -> async close; compares the open baseline.
# Async (open/terminal) is BEST-EFFORT and biased toward DETECTION: it preserves the OLDEST
# in-flight baseline (never drops a mutation) and accepts a benign false-positive if the driver
# edits during the window. The airtight async fix belongs in the clavity WRAPPER (a separate future
# item), not this hook.
#
# DELIBERATELY OUT OF SCOPE (documented, not a silent gap):
#   - The MCP signal bus (`memory_signal_send`/`memory_signal_read`) - DIAGNOSTICS-only per policy,
#     and its tool_name cannot be filtered to `to=agy`/`from=agy`, so guarding it would let non-agy
#     bus traffic corrupt the async slot. The clavity async wrapper covers it instead.
#   - `clavity ring` - a bus poll, not a consult.
#   - .no-agy: this guard deliberately does NOT honour the kill-switch. .no-agy is a file IN THE REPO,
#     so a review-only consult that mutated version control could create it and thereby hide its own
#     write - post.sh would exit before diffing. A guard the untrusted actor can switch off is not a
#     guard. Same principle the ownership check follows (see clavity-classic/plugin/README.md), and it
#     is pinned by a test in scripts/tests/agy-consult-guard.Tests.ps1 so a later "consistency" pass
#     cannot add the check back unnoticed.
#
# TWO baseline slots per session (`.sync` and `.async`) so an interleaved sync consult can never
# destroy an in-flight async baseline.

# Async-baseline staleness TTL (minutes): a `send` whose terminal never arrived leaves a stale
# async baseline; a much-later terminal must not silently attribute the whole gap to the peer.
AGY_GUARD_TTL_MIN="${AGY_GUARD_TTL_MIN:-30}"

# Portable SHA (macOS ships `shasum -a 256`, not `sha256sum`). Reads stdin, echoes the hex digest,
# or `NOHASH` if NO hashing tool exists (so the caller warns LOUDLY rather than compare empties).
agy_guard_hash() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v shasum   >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else cat >/dev/null; printf 'NOHASH'
  fi
}
agy_guard_have_hash() { command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1; }

# --- ignored-path axis -------------------------------------------------------------------------
# `git status --porcelain` omits ignored files BY DESIGN, so a peer write to .clavity/, .env or
# .claude/settings.local.json was invisible to every other axis. These helpers close that.
#
# DELIMITER CONTRACT: the fingerprint joins fields with '|' and this axis joins components with ':'.
# NO value below may contain either character. A sentinel like 'ERROR:UNREADABLE' would shatter the
# inner parse and misalign the components at post.
#
# ABSENT and UNREADABLE must differ from each other AND from any digest. If "I could not look"
# produced the same bytes as "nothing changed", the two fingerprints would compare equal and the
# guard would report a CLEAN consult - the exact false confidence this axis exists to remove.
agy_guard_file_state() {
  local p="$1" s
  [ -e "$p" ] || { printf 'ABSENT'; return 0; }
  [ -r "$p" ] || { printf 'UNREADABLE'; return 0; }
  s=$(agy_guard_hash < "$p" 2>/dev/null) || s=''
  [ -n "$s" ] || s='UNREADABLE'
  printf '%s' "$s"
}

# Hash MANY files in ONE process, printing one digest per line IN THE ORDER GIVEN. Callers zip by
# POSITION and must never parse the filename column: coreutils escapes names containing a backslash
# or newline and prefixes such lines, so the name column is not a reliable key.
# MEASURED on Git Bash, the per-file form this replaces cost ~470ms PER ENTRY - 0 entries 493ms,
# 12 entries 5.835s, 100 entries 47.2s - and the census runs twice per consult. Process creation is
# the cost on Windows, not hashing, so the fix is fewer processes, not a faster hash.
agy_guard_hash_files() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum -- "$@" 2>/dev/null | cut -d' ' -f1
  elif command -v shasum   >/dev/null 2>&1; then shasum -a 256 -- "$@" 2>/dev/null | cut -d' ' -f1
  else return 1
  fi
}

# Top-level census of .clavity/. Carries the entry NAMES LITERALLY (not a hash of them) so post can
# say WHICH entry appeared or vanished; a one-way hash could only say "something changed".
#
# The two concurrent-append targets are emitted UNCONDITIONALLY at a constant state, whether or not
# they exist. Listing them only when present meant the FIRST-EVER capture by a concurrent session -
# which CREATES local-anomalies.md - changed the census and read as a breach. Their existence is
# exactly as concurrent as their contents. Recorded trade-off: this also hides their DELETION, which
# this guard could never attribute to the peer anyway, and a false breach report is the failure mode
# that trains an operator to ignore the guard entirely.
#
# Entries are GLOBBED, never read from `ls` line by line. A filename containing a NEWLINE splits into
# two phantom entries under a line-oriented read; both then resolve to ABSENT, so a later write to
# that file changes nothing and the guard stays silent - an evasion path in a breach detector. Such a
# name is illegal on Windows but legal on macOS and Linux, and this library ships to all three (see
# the shasum branch above). Newlines and carriage returns are also stripped from the recorded name,
# because an embedded newline would otherwise truncate post.sh's line-oriented `read` of the whole
# fingerprint and silently drop every axis after this one.
#
# Sorting is done once, through `sort` under LC_ALL=C, rather than by relying on glob collation:
# collation is locale-dependent, and a LANG difference between the pre and post environments would
# reorder the list and manufacture a false RED.
# Literal newline and carriage return, built once - see the note at their use site below.
AGY_GUARD_NL='
'
AGY_GUARD_CR=$(printf '')

agy_guard_census() {
  local d="$1" p e b st out sorted i
  [ -d "$d" ] || { printf 'ABSENT'; return 0; }
  [ -r "$d" ] || { printf 'UNREADABLE'; return 0; }

  local names=() states=() hp=() hi=() entries=()
  # Save and restore the caller's globbing options - this library is SOURCED into the hook's shell,
  # so leaving nullglob/dotglob set would silently change behaviour in the rest of that hook.
  local had_null=0 had_dot=0
  shopt -q nullglob && had_null=1
  shopt -q dotglob  && had_dot=1
  shopt -s nullglob dotglob

  for p in "$d"/*; do
    e=${p##*/}
    # Skip the two concurrent-append targets - but ONLY when they are files. A reviewer filed this
    # below its own severity floor and it is real: an unconditional `continue` meant a DIRECTORY
    # created under either name was skipped entirely, so its appearance did not register and
    # nothing beneath it was monitored. Directories now fall through and are recorded as DIR.
    if [ ! -d "$p" ]; then
      case "$e" in
        local-anomalies.md|discipline-reaching.jsonl) continue ;;
      esac
    fi
    b=${e//[|:,=]/_}
    # Literal control characters held in variables, NOT ANSI-C quoting inline in the PATTERN of
    # ${var//pat/repl}. A reviewer raised that bash 3.2 - which macOS still ships, and which this
    # `#!/usr/bin/env bash` file can land on - may not interpret $'\n' there, leaving the newline
    # in place. I could NOT measure that claim: there is no bash 3.2 on this machine, so it is
    # UNPROVEN rather than confirmed. This form is portable either way and costs nothing, and the
    # cost if the claim IS true is severe - the newline survives and post.sh's line-oriented read
    # then truncates the entire fingerprint, silently dropping every axis after this one.
    b=${b//$AGY_GUARD_NL/_}
    b=${b//$AGY_GUARD_CR/_}
    if   [ -d "$p" ];   then st='DIR'
    elif [ ! -f "$p" ]; then st='UNREADABLE'
    elif [ ! -r "$p" ]; then st='UNREADABLE'
    else st=''; hp+=("$p"); hi+=("${#names[@]}")
    fi
    names+=("$b")
    states+=("$st")
  done

  [ "$had_null" = 1 ] || shopt -u nullglob
  [ "$had_dot"  = 1 ] || shopt -u dotglob

  if [ "${#hp[@]}" -gt 0 ]; then
    local digests=() line
    while IFS= read -r line; do digests+=("$line"); done < <(agy_guard_hash_files "${hp[@]}")
    if [ "${#digests[@]}" -eq "${#hp[@]}" ]; then
      i=0; while [ "$i" -lt "${#hp[@]}" ]; do states[${hi[$i]}]="${digests[$i]}"; i=$((i+1)); done
    else
      # The batch returned a different number of digests than files handed to it: a file vanished
      # between the glob and the hash - .clavity/ is a CONCURRENT write area, so this races by
      # construction - or was locked by another process, or the tool refused the argument list.
      # Do NOT collapse every entry onto one constant. MEASURED with a verified mutant that always
      # emitted a single digest: marking them all UNREADABLE masked EVERY content change in the
      # directory for that consult. Names still moved, so a NEW file was still caught, but an
      # overwrite was not - and an overwrite of the shield is the case this axis exists for.
      # A guard that answers the same thing for every input has stopped answering. Fall back to
      # hashing each file on its own: slower, but only on this rare path, and correct.
      i=0
      while [ "$i" -lt "${#hp[@]}" ]; do
        states[${hi[$i]}]=$(agy_guard_file_state "${hp[$i]}")
        i=$((i+1))
      done
    fi
  fi

  i=0
  while [ "$i" -lt "${#names[@]}" ]; do entries+=("${names[$i]}=${states[$i]},"); i=$((i+1)); done

  out='discipline-reaching.jsonl=SKIP,local-anomalies.md=SKIP,'
  if [ "${#entries[@]}" -gt 0 ]; then
    sorted=$(printf '%s\n' "${entries[@]}" | LC_ALL=C sort)
    out="${out}${sorted//$'\n'/}"
  fi

  # Bounded: degrade to a digest rather than growing the fingerprint without limit, and SAY SO so a
  # reader knows enumeration is unavailable instead of assuming nothing appeared.
  if [ "${#out}" -gt 4096 ]; then
    printf 'CAPPED=%s' "$(printf '%s' "$out" | agy_guard_hash)"
  else
    printf '%s' "$out"
  fi
}

agy_guard_ignored() {
  local c="$1"
  printf '%s:%s:%s:%s' \
    "$(agy_guard_file_state "$c/.clavity/.gitignore")" \
    "$(agy_guard_file_state "$c/.env")" \
    "$(agy_guard_file_state "$c/.claude/settings.local.json")" \
    "$(agy_guard_census "$c/.clavity")"
}

# State dir mirrors remote-iteration-breaker.sh: /tmp is a clean POSIX dir under Git Bash.
# $1 = session_id (caller-sanitized)  $2 = slot ('sync'|'async')
agy_guard_state_file() {
  local base="${TMPDIR:-/tmp}/claude-agy-consult-guard"
  mkdir -p "$base" 2>/dev/null || return 1
  printf '%s/%s.%s' "$base" "$1" "$2"
}

# True (0) iff cwd is inside a git work tree. The drain T3 lesson: plumbing returns 128 both for
# "not a repo" and "absent object", so rev-parse --is-inside-work-tree is the only reliable test.
agy_guard_in_git_repo() {
  [ "$(git -C "$1" rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ]
}

# Classify a tool call. Echoes: sync | open | terminal | none.  $1=tool_name  $2=command-string.
agy_guard_category() {
  case "$1" in
    *agy_ask) echo sync; return ;;   # MCP consult tool (synchronous)
  esac
  local c="$2"
  # Anchor on COMMAND POSITION, not any occurrence. The previous form grepped the WHOLE command string,
  # so a command whose TEXT merely mentioned the consult CLI - a commit message, a heredoc - was
  # classified as a review-only consult, and the driver's own commit inside that same call was then
  # reported as the peer modifying version control. REPRODUCED: two identical commits differing only in
  # message text gave warn vs silent. A consult invocation can only start the string or follow a shell
  # separator, so require that.
  # Widened 2026-08-02 (capstone round 1): also allow an optional path prefix and a .exe suffix, so
  # `clavity.exe ask`, `/usr/bin/clavity ask` and `C:\bin\clavity.exe ask` classify. All three were
  # MEASURED silent before, i.e. the guard simply did not exist for them.
  # Deliberately NOT widened to treat `(` as a separator. That would catch `X=$(clavity ask ...)` but
  # would ALSO make a quoted `"(clavity ask )"` false-alarm - measured, exactly one for one, because both
  # hinge on the same character - and a false alarm is what trained the operator to ignore this guard in
  # the first place. The capture form is left undetected on purpose.
  # KNOWN BOUNDARY, accepted: grep is line-oriented, so a MULTILINE command whose second line begins with
  # `clavity ask` - a git commit message, say - classifies as a consult. In a real shell a newline IS a
  # command separator, so distinguishing the two needs quote-aware parsing this hook deliberately does not
  # attempt. The MCP path above is immune to all of this: it matches on tool NAME and returns before ever
  # reaching this regex.
  local anchor='(^|[;&|]|&&|\|\|)[[:space:]]*([[:graph:]]*[/\\])?clavity(\.exe)?[[:space:]]+'
  printf '%s' "$c" | grep -Eq "${anchor}ask([[:space:]]|$)"         && { echo sync;     return; }
  printf '%s' "$c" | grep -Eq "${anchor}send([[:space:]]|$)"        && { echo open;     return; }
  printf '%s' "$c" | grep -Eq "${anchor}await-reply([[:space:]]|$)" && { echo terminal; return; }
  echo none
}

# Emit the VCS baseline quad (7 axes) for the repo at $1. Each axis closes a smuggle vector found
# across two agy capstones:
#   head    : committed axis (a mid-consult commit moves HEAD)
#   status  : worktree + UNTRACKED (git status --porcelain lists ?? by default)
#   diff    : worktree + STAGED/index (git diff + git diff --cached)
#   stash   : refs/stash sha (stash leaves the other axes pristine)
#   refs    : all other refs sans stash (rogue tag/branch/notes move a pointer w/o touching HEAD)
#   gitmeta : .git/hooks/* + .git/config + .git/info/exclude (writing a hook arms code-exec;
#             appending to info/exclude hides new worktree files from `status`)
#   flags   : `git ls-files -v` non-`H` lines (`update-index --assume-unchanged`/`--skip-worktree`
#             mutate a tracked file while hiding it from status AND diff)
#   ignored : gitignored paths a review-only consult must not touch - the .clavity/ shield, .env,
#             .claude/settings.local.json, and a bounded top-level census of .clavity/. `git status`
#             omits all of these, which is why peer writes there were invisible.
agy_guard_quad() {
  local c="$1" head status diff stash refs gitmeta flags ignored gitdir
  head=$(git -C "$c" rev-parse HEAD 2>/dev/null)
  status=$(git -C "$c" status --porcelain 2>/dev/null | agy_guard_hash)
  diff=$( { git -C "$c" diff 2>/dev/null; git -C "$c" diff --cached 2>/dev/null; } | agy_guard_hash)
  stash=$(git -C "$c" rev-parse -q --verify refs/stash 2>/dev/null || echo none)
  refs=$(git -C "$c" show-ref 2>/dev/null | grep -v ' refs/stash$' | agy_guard_hash)
  gitdir=$(git -C "$c" rev-parse --absolute-git-dir 2>/dev/null)
  gitmeta=$( {
    if [ -d "$gitdir/hooks" ]; then
      find "$gitdir/hooks" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r h; do
        printf '%s\n' "$h"; cat "$h" 2>/dev/null
      done
    fi
    cat "$gitdir/config" 2>/dev/null
    cat "$gitdir/info/exclude" 2>/dev/null
  } | agy_guard_hash)
  flags=$(git -C "$c" ls-files -v 2>/dev/null | grep -Ev '^H ' | agy_guard_hash)
  ignored=$(agy_guard_ignored "$c")
  printf '%s|%s|%s|%s|%s|%s|%s|%s' "$head" "$status" "$diff" "$stash" "$refs" "$gitmeta" "$flags" "$ignored"
}

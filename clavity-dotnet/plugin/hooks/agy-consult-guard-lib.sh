#!/usr/bin/env bash
# ME1 — agy-consult VCS-diff guard, shared library.
# Sourced by agy-consult-guard-pre.sh (PreToolUse) and -post.sh (PostToolUse).
# Enforces the standing rule: an agy REVIEW-ONLY consult must make ZERO VCS changes.
# READ-ONLY — it only reports; it never reverts, stages, commits, or blocks. Fail-open.
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
#   - The MCP signal bus (`memory_signal_send`/`memory_signal_read`) — DIAGNOSTICS-only per policy,
#     and its tool_name cannot be filtered to `to=agy`/`from=agy`, so guarding it would let non-agy
#     bus traffic corrupt the async slot. The clavity async wrapper covers it instead.
#   - `clavity ring` — a bus poll, not a consult.
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
agy_guard_quad() {
  local c="$1" head status diff stash refs gitmeta flags gitdir
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
  printf '%s|%s|%s|%s|%s|%s|%s' "$head" "$status" "$diff" "$stash" "$refs" "$gitmeta" "$flags"
}

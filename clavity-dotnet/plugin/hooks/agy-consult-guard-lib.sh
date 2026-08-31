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
  # Resolve the tool ONCE, at function level. It used to be an if/elif/else INSIDE the chunk loop,
  # with the whole block piped into `cut`. That put `else return 1` on the left-hand side of a
  # pipeline, which bash runs in a SUBSHELL: the return exited the subshell, not the function.
  # MEASURED with a paired control - `f() { if false; then :; else return 1; fi | cat; ...; }` reaches
  # the line after the return and yields rc 0, while the same return outside a pipeline yields rc 1.
  # So with no hashing tool the function did not short-circuit: it looped over every remaining chunk
  # doing nothing and then reported success. Hoisting the check makes the return a real return, and
  # costs one `command -v` instead of one per chunk.
  local tool=''
  if   command -v sha256sum >/dev/null 2>&1; then tool='sha256sum'
  elif command -v shasum    >/dev/null 2>&1; then tool='shasum'
  else return 1
  fi

  # CHUNKED, 256 paths at a time. Expanding an unbounded array into one command is an E2BIG waiting
  # to happen as .clavity/seams/ accumulates briefs, and the failure was NOT benign: the batch would
  # return zero digests, the short-count path would drop to the per-file fallback, and that fallback
  # costs ~470ms per file - thousands of files would block the hook for HOURS and hang the consult
  # rather than merely slowing it. Chunking removes the trigger, so the per-file fallback stays what
  # it was meant to be: a rare path for genuine per-file errors.
  local batch=()
  while [ "$#" -gt 0 ]; do
    batch=()
    while [ "$#" -gt 0 ] && [ "${#batch[@]}" -lt 256 ]; do batch+=("$1"); shift; done
    # Strip a LEADING FILENAME ESCAPE from each digest line. GNU coreutils prefixes an output line
    # whose FILENAME contains a backslash or a newline, and `cut -d' ' -f1` then leaves that prefix
    # welded to the digest, while the per-file fallback reads from stdin and never carries it - so
    # the two paths would disagree for identical bytes and a pre/post pair straddling the fallback
    # boundary would report a false breach. The class stops at the first hex digit, and a digest is
    # hex throughout, so it removes the escape and cannot touch the digest.
    if [ "$tool" = 'sha256sum' ]; then sha256sum -- "${batch[@]}" 2>/dev/null
    else                              shasum -a 256 -- "${batch[@]}" 2>/dev/null
    fi | cut -d' ' -f1 | sed 's/^[^0-9a-fA-F]*//'
  done
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
AGY_GUARD_CR=$(printf '\r')
AGY_GUARD_BS=$(printf '\134')

# One digest covering every file under a directory, contents AND relative paths, so a rename is
# caught as well as an edit. Used for seams/, which is MONITORED but must not be ENUMERATED: this
# repository already holds 706 briefs there and the set only grows, so listing them per-file produced
# a ~69 KB census - over any sane cap, which collapsed the WHOLE census to a single CAPPED digest and
# destroyed the per-entry naming for every other directory too. One entry keeps naming everywhere
# else while still detecting any change here.
# sort -z before hashing: readdir order is not stable across machines or filesystems.
agy_guard_dir_digest() {
  local dd="$1" p h
  [ -d "$dd" ] || { printf 'ABSENT'; return 0; }
  [ -r "$dd" ] || { printf 'UNREADABLE'; return 0; }

  # NO xargs. A reviewer found that `xargs -0 -r` is a GNU extension: macOS xargs rejects -r, this
  # pipeline sends its stderr to /dev/null, and the hash of the resulting EMPTY stream is the
  # constant e3b0c442... - MEASURED. The digest would then never change again, so the guard would go
  # permanently blind on macOS while reporting clean. A guard that fails open certifies exactly what
  # it stopped checking. agy_guard_hash_files already handles the sha256sum/shasum split portably.
  local files=()
  while IFS= read -r -d '' p; do files+=("$dd/$p"); done < <(
    cd "$dd" 2>/dev/null && find . -type f -print0 2>/dev/null | LC_ALL=C sort -z)

  # The digest covers TWO streams: the full entry LISTING - every path, whatever its type - and the
  # CONTENTS of the regular files. The listing is what catches a rename, a new subdirectory, or a
  # new symlink, none of which `-type f` alone would see. Replacing a regular file with a symlink of
  # the same name is caught too, because that path then drops out of the hashed set and the content
  # stream is one digest shorter. sort -z because readdir order is not stable across filesystems.
  if [ "${#files[@]}" -gt 0 ]; then
    local digests=() line
    while IFS= read -r line; do digests+=("$line"); done < <(agy_guard_hash_files "${files[@]}")
    # A short count means the batch did not answer for every file: a file vanished mid-read, one was
    # locked, or the argument list was refused. Do NOT hash a truncated stream into a plausible
    # digest - and do NOT return a bare sentinel either.
    #
    # Returning 'UNREADABLE' here was a CONSTANT-ANSWER defect, and the third of its kind in this
    # file. Both the pre and the post hook would return the same 'UNREADABLE', they would compare
    # EQUAL, and the guard would report a clean consult while seams/ changed underneath it - the
    # monitor blinded permanently on any repository big enough to reach the failure. That the census
    # already falls back per-file here and this function did not was an inconsistency, not a design.
    # Reachability is bounded but real: 5000 files hash fine, and the ceiling was NOT established
    # (the 20000-file fixture timed out before the measurement could run), so the cliff's distance
    # is unknown rather than proven far away - which is exactly why the fallback must not be a
    # constant.
    if [ "${#digests[@]}" -ne "${#files[@]}" ]; then
      digests=()
      for p in "${files[@]}"; do digests+=("$(agy_guard_file_state "$p")"); done
    fi
    h=$( { (cd "$dd" 2>/dev/null && find . -print0 2>/dev/null | LC_ALL=C sort -z)
           printf '%s\n' "${digests[@]}"; } | agy_guard_hash )
  else
    h=$( (cd "$dd" 2>/dev/null && find . -print0 2>/dev/null | LC_ALL=C sort -z) | agy_guard_hash )
  fi
  [ -n "$h" ] || h='UNREADABLE'
  printf '%s' "$h"
}

# Percent-encode a census entry name. INJECTIVE, unlike collapsing reserved characters onto '_',
# which MEASURED as a lost detection: two names colliding onto one string let a content swap between
# them produce a byte-identical census. '%' MUST be encoded first or the mapping stops being
# injective. Newline and carriage return are encoded too - an embedded newline would otherwise
# truncate post.sh's line-oriented read of the whole fingerprint, silently dropping every later axis.
agy_guard_encode_name() {
  local b="$1"
  b=${b//%/%25}
  b=${b//|/%7C}
  b=${b//:/%3A}
  b=${b//,/%2C}
  b=${b//=/%3D}
  b=${b//"$AGY_GUARD_NL"/%0A}
  b=${b//"$AGY_GUARD_CR"/%0D}
  printf '%s' "$b"
}

agy_guard_census() {
  local d="$1" p rel b st out sorted i
  [ -d "$d" ] || { printf 'ABSENT'; return 0; }
  [ -r "$d" ] || { printf 'UNREADABLE'; return 0; }

  # Normalise trailing slashes BEFORE anything derives from $d. MEASURED with `dir/`: the -path
  # prune matched nothing, so scratch/ was walked and hashed, AND `${p#"$d/"}` failed to strip, so
  # every entry name came out as an absolute path - machine-specific, enormous, and different from
  # the same directory addressed without the slash.
  while [ "$d" != "/" ] && [ "${d%/}" != "$d" ]; do d=${d%/}; done

  # Escape glob metacharacters for the -path patterns below. `find -path` matches with fnmatch, not
  # literally: MEASURED, a repository path containing '[' made the prune silently match nothing.
  # This restores the FAST path; it is not what makes the exclusion correct - see the loop.
  local dpat=${d//"$AGY_GUARD_BS"/"$AGY_GUARD_BS$AGY_GUARD_BS"}
  dpat=${dpat//[/"$AGY_GUARD_BS"[}
  dpat=${dpat//\*/"$AGY_GUARD_BS"\*}
  dpat=${dpat//\?/"$AGY_GUARD_BS"\?}

  local names=() states=() hp=() hi=() entries=()

  # RECURSIVE, excluding scratch/ and seams/. The census was top-level only, and a reviewer called
  # that an architectural flaw across two rounds while I refuted it twice on "nothing executes from
  # .clavity/" - a refutation whose grep only covered the plugin directories. MEASURED on the third
  # round: .claude/settings.local.json wired THREE mode-755 scripts under .clavity/scratch/ as live
  # SessionStart / SessionEnd hooks. A top-level census records only `scratch=DIR`, so overwriting a
  # script this machine EXECUTES was invisible to the guard. Owner ruled 2026-08-31 to widen.
  #
  # ONLY scratch/ is excluded: it is where the peer is TOLD to write, so hashing it would turn
  # every sanctioned write into a breach report, and a false alarm is what teaches an operator to
  # ignore this guard. It is still listed as an entry - `-prune -print0` prints the directory itself
  # before skipping its contents - so DELETING it is still caught.
  #
  # seams/ is MONITORED, but as a SINGLE AGGREGATE DIGEST rather than per file. Owner ruled
  # 2026-08-31 that it must be watched: the peer only READS seams/, and a brief there is an
  # instruction to a FUTURE review round, so a peer able to rewrite one unobserved could inject
  # instructions into the very loop that is meant to be checking it. Enumerating it per-file was
  # MEASURED at ~69 KB of census on this repository's 706 briefs, which capped the whole census and
  # destroyed per-entry naming everywhere else - so it is watched, not listed.
  #
  # -print0 / read -d '' rather than a line-oriented read: a filename containing a newline would
  # otherwise split into two phantom entries, which is the round-1 defect this file already carries
  # a fix for. Paths are recorded relative to .clavity/ so the entry names say WHERE.
  while IFS= read -r -d '' p; do
    rel=${p#"$d/"}
    # THE EXCLUSION IS ENFORCED HERE, on the relative path, not by the find prune. The prune is a
    # PERFORMANCE optimisation and its -path argument is a GLOB over a path we do not control:
    # MEASURED, it silently matched nothing when the repository path contained '[' or when $d
    # carried a trailing slash, and scratch/ was then walked and hashed - turning every sanctioned
    # peer write into a breach report. A boundary that depends on shell pattern matching is not a
    # boundary. If the prune fails the walk gets slower (measured 11s against 0.5s on this tree) and
    # stays CORRECT, which is the right way round for a guard.
    # ONLY scratch/ is exempt. seams/ is MONITORED - owner ruled 2026-08-31, reversing the earlier
    # "exclude both". The asymmetry is the point: the peer is told to WRITE in scratch/, so hashing
    # it would turn every sanctioned write into a breach report. It is told only to READ seams/, and
    # MEASURED across four consults this session, every brief was written BEFORE agy_ask fired the
    # pre-hook, so seams/ is stable across the window and monitoring it costs no false alarm.
    # What it buys: a brief is an INSTRUCTION TO A FUTURE ROUND, so a peer that could rewrite one
    # unobserved could inject instructions into the review loop that is supposed to be checking it.
    case "$rel" in
      scratch)     ;;                      # record the directory itself, so deleting it is caught
      scratch/*)   continue ;;             # never record its contents
      seams)       st=$(agy_guard_dir_digest "$p")
                   names+=("seams"); states+=("$st"); continue ;;
      seams/*)     continue ;;             # covered by the aggregate above, never listed per-file
    esac
    # The two concurrent-append targets are exempt only as FILES, and only at the top level.
    case "$rel" in
      local-anomalies.md|discipline-reaching.jsonl) [ -d "$p" ] || continue ;;
    esac
    # Extracted into agy_guard_encode_name so it can be tested directly. It USED to be inline, and
    # the only test covering it drove it through a real FILENAME - which on Windows can never contain
    # '|' or ':'. MEASURED: deleting the lines that encode those two left the whole suite GREEN at
    # 35/35. The row proved only that ',' and '=' were handled, while its own comment claimed all
    # four were covered "by the same single tr" - a tr that no longer existed. A function can be
    # called with any string; a fixture can only be given a name the filesystem will accept.
    b=$(agy_guard_encode_name "$rel")
    if   [ -d "$p" ];   then st='DIR'
    elif [ ! -f "$p" ]; then st='UNREADABLE'
    elif [ ! -r "$p" ]; then st='UNREADABLE'
    else st=''; hp+=("$p"); hi+=("${#names[@]}")
    fi
    names+=("$b")
    states+=("$st")
  done < <(find "$d" -mindepth 1 \( -path "$dpat/scratch" -o -path "$dpat/seams" \) -prune -print0 -o -print0 2>/dev/null)

  if [ "${#hp[@]}" -gt 0 ]; then
    local digests=() line
    while IFS= read -r line; do digests+=("$line"); done < <(agy_guard_hash_files "${hp[@]}")
    if [ "${#digests[@]}" -eq "${#hp[@]}" ]; then
      i=0; while [ "$i" -lt "${#hp[@]}" ]; do states[${hi[$i]}]="${digests[$i]}"; i=$((i+1)); done
    else
      # The batch returned a different number of digests than files handed to it: a file vanished
      # between the walk and the hash - .clavity/ is a CONCURRENT write area, so this races by
      # construction - or was locked by another process, or the tool refused the argument list.
      # Do NOT collapse every entry onto one constant. MEASURED with a verified mutant that always
      # emitted a single digest: marking them all UNREADABLE masked EVERY content change in the
      # directory for that consult. Names still moved, so a NEW file was still caught, but an
      # overwrite was not - and an overwrite of the shield is the case this axis exists for.
      # A guard that answers the same thing for every input has stopped answering. Fall back to
      # hashing each file on its own: slower, but only on this rare path, and correct.
      #
      # ACCEPTED LIMIT, stated rather than implied: neither path is a point-in-time snapshot. A
      # reviewer argued this fallback is worse because it abandons the batch hash's atomicity - but
      # the batch has none either: `sha256sum f1 f2 f3` is ONE process reading the files in
      # sequence. Widening the window changes the odds, not the kind. A concurrent writer that
      # restores a file to its baseline exactly while it is being read can hide a change from any
      # before/after fingerprint, and this guard already states it cannot attribute a change to the
      # peer rather than to a concurrent session.
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
    # Sort once, under LC_ALL=C: collation is locale-dependent, and a LANG difference between the
    # pre and post environments would reorder the list and manufacture a false RED.
    sorted=$(printf '%s\n' "${entries[@]}" | LC_ALL=C sort)
    out="${out}${sorted//"$AGY_GUARD_NL"/}"
  fi

  # Bounded: degrade to a digest rather than growing the fingerprint without limit, and SAY SO so a
  # reader knows enumeration is unavailable instead of assuming nothing appeared. CAPPED still
  # DETECTS a change; it just cannot NAME the entry, and naming is the whole reason this axis carries
  # entry names literally instead of a single hash.
  #
  # The limit is 64 KiB, not the 4096 this started at. 4096 was sized when the census was top-level
  # only. MEASURED once seams/ became monitored: this repository's .clavity/ produces ~56 KB of
  # census, so a 4096 cap put every real consult permanently into CAPPED - detection intact, every
  # entry name gone, on the one tree the guard actually runs against. The fingerprint is written to
  # a temp file and compared as a string; 64 KiB there costs nothing worth measuring.
  if [ "${#out}" -gt 65536 ]; then
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

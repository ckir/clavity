#!/usr/bin/env bash
# AGY-ANOMALIES discipline-reaching recorder (plugin-shipped). SessionStart. CAPTURE ONLY.
# ROADMAP section 0 step 1a. Design + measurements: docs/superpowers/specs/2026-08-05-sessionstart-capture-design.md
#
# IT CAPTURES; IT DOES NOT ANALYSE. One small row naming the session and its transcript, then stop. All
# scanning happens later in scripts/discipline-reaching-report.ps1, which runs on demand with no time limit.
#
# WHY THE EXTRACTION IS WRITTEN WITHOUT jq, date, OR git.
# NOT because of teardown pressure - that was a wrong diagnosis that cost three rounds. The real cause of
# the v17 failure was that ${CLAUDE_PLUGIN_ROOT} DOES NOT RESOLVE at SessionEnd (cancelled 3/3 with the
# variable at 20,9s / 1,5s / 0,6s; an absolute path from the same manifest worked 2/2 - one axis varied,
# the other never). Duration was a confound: a SLOWER hook registered elsewhere survived.
# The subprocess-free form is kept for the PARSE and the ROOT WALK on its own merits: a hook that runs at
# EVERY session start should be cheap, and the rewrite carries three fixes worth keeping - byte-exact
# Windows paths, CR stripping, and pipe-safe stdin.
#
# ONE EXCEPTION, ADDED DELIBERATELY (ROADMAP 14c): the .clavity shield assertion below sources
# agy-shield-lib.sh, which does spawn processes. It is placed AFTER every early exit, so it runs only
# once the walk has already proved this is a real repository - the header's 20314ms unreachable-share
# measurement is about the WALK, which is complete by then. This hook is registered with "timeout": 10
# in hooks.json; keep any future addition on the far side of those exits for the same reason.
#
# WHY RAW PASSTHROUGH IS SAFE - the trick that removes jq from the WRITE side too. The payload already
# holds each value JSON-ESCAPED. Copying that escaped text straight into the output re-emits it
# byte-for-byte, so nothing is unescaped and re-escaped - which is exactly where an earlier version
# corrupted Windows paths (@tsv doubled every backslash). `[^"]*` is the correct extractor because a double
# quote is an ILLEGAL character in a Windows filename, so no value here can contain one.
#
# A NULL IS NOT A ZERO. No transcript named => a NAMED status, never a count of zero, and the row still
# lands. A missing row and a degraded row must never look alike.
#
# Fail-open: any error -> exit 0. Suppressed by .no-agy (workspace or global) like every other hook.
# Byte-identical across both driver plugins (kept honest by scripts/check-seed-artifacts-synced.sh).
set +e
export TZ=UTC

# `read -d ''` slurps the whole stream and is a BUILTIN - no fork, unlike $(cat). It returns non-zero at
# EOF while still having set the variable, hence the `|| true`-style bare call under `set +e`.
# NOT $(</dev/stdin): that works when stdin is a FILE but not reliably when it is a PIPE under MSYS, and
# a hook is always piped. Measured - the file-redirect form passed a hand test and then wrote NOTHING for
# all eight piped cases in the suite, which is exactly the silent failure this hook must never have.
IFS= read -r -d '' input

# Raw, still-escaped extraction. No jq: see the header. An absent field stays empty, which the status
# logic below treats as "not named" rather than as zero.
cwd=''; sid=''; src=''; model=''; tx=''
[[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]             && cwd=${BASH_REMATCH[1]}
[[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]      && sid=${BASH_REMATCH[1]}
[[ $input =~ \"source\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]          && src=${BASH_REMATCH[1]}
[[ $input =~ \"model\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]           && model=${BASH_REMATCH[1]}
[[ $input =~ \"transcript_path\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && tx=${BASH_REMATCH[1]}

# cwd is the only value used as a PATH here, so it is the only one that must be unescaped. The rest pass
# through still-escaped and are never touched.
cwd_path=${cwd//\\\\//}
[ -z "$cwd_path" ] && cwd_path="."

# The GLOBAL opt-out does not depend on the repo root, so it is checked first and cheaply.
[ -f "$HOME/.claude/.no-agy" ] && exit 0

# Repo root by walking up for .git, in-shell. `git rev-parse --show-toplevel` is more precise but costs a
# process start, and process COUNT is the entire budget here. A .git entry matches as a directory (normal
# clone) or a file (worktree/submodule).
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

# NO REPOSITORY, NO ROW. $root is reassigned ONLY when the walk finds a .git, so a .git under $root here is
# exactly equivalent to "the walk succeeded" - no flag variable is needed, and testing $cwd_path instead
# would reintroduce the subdirectory bug fixed directly below. A session outside any repo has no project to
# attribute reaching to, so the row would be unattributable anyway.
[ -e "$root/.git" ] || exit 0

# WORKSPACE OPT-OUT, CHECKED AFTER THE WALK - this is the fix. Checking only $cwd_path meant a .no-agy at
# the repo ROOT did not suppress a session launched in a SUBDIRECTORY, while the write below still landed
# in that root. MEASURED: cwd=repo/src with repo/.no-agy present WROTE a row; cwd=repo wrote nothing.
# Both paths are tested: a .no-agy in a subdirectory still suppresses that subdirectory.
if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
  exit 0
fi

# ROADMAP section 31b: ZERO FOOTPRINT IN A REPOSITORY THAT NEVER ASKED FOR THIS PLUGIN.
# This hook is registered GLOBALLY, so it fires at every session start in every directory on the machine.
# Until now it created `.clavity/` unconditionally, which meant installing the plugin in one profile
# silently added an untracked directory to every repository opened there - MEASURED per hook in fresh
# throwaway repos: of the three clavity hooks on this matcher, the two siblings create nothing and this
# one created a directory.
#
# THE OPT-IN IS PRIOR USE, NOT A NEW SETTING. A repository that actually uses the disciplines already has
# `.clavity/` - every discipline writes a seam, a marker or a scratch dir through agy-mark.sh, which
# creates and shields it. So "the directory already exists" IS the signal that this workspace asked for
# the plugin, and it needs no configuration file, no environment variable and nothing to remember.
#
# `.no-agy` REMAINS THE OPT-OUT and is checked above, deliberately FIRST: a repository that has used the
# plugin before and has since asked for silence must stay silent, so the two gates are not interchangeable
# and their order is not cosmetic.
#
# THE COST, STATED: a brand-new clavity repository records nothing until some other clavity operation
# creates the directory. That is one lost session row in exchange for touching no unrelated repository
# ever, and reaching is a longitudinal signal that survives one missing row.
[ -d "$root/.clavity" ] || exit 0

if [ -n "$tx" ]; then status='deferred'; else status='transcript_not_found'; fi

# printf's %()T is a bash builtin - no `date` process. TZ=UTC above makes it UTC.
printf -v ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1

out="$root/.clavity"

# ROADMAP 14c: assert the shield BEFORE creating or writing anything under .clavity/. Sourced, not
# executed - the helper returns and never exits, so it cannot terminate this hook. It always returns 0;
# its value carries no information and must not be branched on. $sid is the payload's session_id (:42),
# forwarded as the debounce key so a persistent fault is reported once per session rather than on every
# start; an empty $sid legally disables debouncing.
. "$(dirname "$0")/agy-shield-lib.sh" 2>/dev/null || true
if command -v agy_shield >/dev/null 2>&1; then
  agy_shield "$root" ".clavity/discipline-reaching.jsonl" "$sid"
else
  # FALLBACK, and its absence was a real asymmetry. If the helper is missing, unreadable, or contains a
  # syntax error, `|| true` swallows the failure and `command -v` correctly reports it gone - and without
  # this branch the hook would proceed to write into an UNSHIELDED .clavity/ and exit 0 with nothing said.
  # The old content-blind idiom is a weak shield; no shield at all is the leak this item exists to stop.
  #
  # PANEL R2 - THIS FALLBACK USES THE SAFE APPEND, NOT THE SHIPPED IDIOM. Round 1 proved
  # `[ -f ] || printf '%s\n' '*' >>` corrupts a shield whose last line has no trailing newline (measured:
  # `foo.txt` + `*` -> the single line `foo.txt*`). Round 1's own fix then pasted that unpatched idiom
  # into this brand-new else branch, recreating the defect it had just closed one task over. A fix is
  # unreviewed code; this is what that costs when it is not re-reviewed.
  mkdir -p "$root/.clavity" 2>/dev/null
  # `! -s` COVERS MISSING **AND** EMPTY IN ONE TEST, and that is the whole point. PANEL R3 measured that
  # the round-2 form - `if [ ! -f ] ... elif [ -s ] ...` - ran NEITHER branch for a shield that exists at
  # zero bytes, leaving an EMPTIED shield unrestored. That is the literal 14d defect, reintroduced in the
  # fallback by the fix for the previous round's defect. Third consecutive round in which a fix created
  # one; do not "simplify" this test back apart.
  if [ ! -s "$root/.clavity/.gitignore" ]; then
    printf '%s\n' '*' 2>/dev/null >> "$root/.clavity/.gitignore"
  elif ! grep -qx '*' "$root/.clavity/.gitignore" 2>/dev/null; then
    printf '\n%s\n' '*' 2>/dev/null >> "$root/.clavity/.gitignore"
  fi
  # AND THE FALLBACK MUST CHECK ITS OWN WRITE. Neither append above is tested, and the `2>/dev/null`
  # that stops the redirect-order leak also swallows the OS error, so a failed write was indistinguishable
  # from a successful one. MEASURED (capstone round 2b) with the helper absent and .clavity/.gitignore
  # denied write: the hook exited 0 in COMPLETE SILENCE, the shield never gained its `*`, the jsonl was
  # written anyway, and `git check-ignore` reported it NOT ignored. The PRIMARY path warns twice in that
  # same case - so the fallback was strictly weaker at the one thing the comment above says it exists to
  # guarantee, which is the fourth consecutive round in which this branch's fix carried its own defect.
  #
  # The check is `grep`, not the append's exit status, because the QUESTION is "is the shield asserted",
  # not "did my write return 0" - an unreadable shield is equally unprotected and must warn too. Same
  # `agy-shield:` prefix and same stderr channel as agy-shield-lib.sh:107, deliberately: one failure, one
  # vocabulary, whichever path produced it.
  # TWO CAUSES, TWO MESSAGES, because grep's exit code distinguishes them and a single message cannot.
  # MEASURED under WSL (capstone round 2d) with `chmod 200` and both preconditions probed - writable=YES,
  # readable=NO: the append SUCCEEDS, the verify grep fails, and the first version of this diagnostic told
  # the operator to "check that it is a regular, WRITABLE file" while the file was writable all along and
  # the real fault was READ permission. That is the precise failure agy-shield-lib.sh:214-220 already
  # records folding once - "a diagnostic that names the wrong cause is worse than a vague one, because it
  # is actionable and wrong" - and this branch reproduced it two rounds later.
  #
  # grep's exit code IS the unreadability oracle, and it is the same one agy-ledger-lib.sh uses: 0 matched,
  # 1 matched nothing, GREATER THAN 1 could not read. Not `[ -r ]`, which does not consult Windows ACLs.
  # AND EXISTENCE IS ITS OWN CAUSE, ahead of both of them. `grep` on a MISSING file also exits 2, so a
  # directory this process cannot write - .clavity/ exists, which is why the gate at :116 let us here, but
  # is read-only - produces no .gitignore at all and lands in the unreadable arm. MEASURED under WSL with
  # `chmod 500 .clavity` (capstone round 2e): the file did not exist and the operator was told to check
  # the permissions of a regular file, which is an impossible errand. Existence first, then permission.
  grep -qx '*' "$root/.clavity/.gitignore" 2>/dev/null
  _dr_rc=$?
  if [ ! -e "$root/.clavity/.gitignore" ]; then
    printf 'agy-shield: %s\n' "could not CREATE $root/.clavity/.gitignore - .clavity/ is NOT protected and is exposed to git. The shield file does not exist, so this is not a permission problem on the FILE: check that $root/.clavity/ is a writable directory." >&2
  elif [ "$_dr_rc" -gt 1 ]; then
    printf 'agy-shield: %s\n' "could not READ $root/.clavity/.gitignore, so whether .clavity/ is shielded cannot be determined - assume it is exposed to git. Check that it is a regular file THIS process can read; it may be writable and still unreadable." >&2
  elif [ "$_dr_rc" -ne 0 ]; then
    printf 'agy-shield: %s\n' "could not assert the shield in $root/.clavity/.gitignore - .clavity/ is NOT protected and is exposed to git. Check that it is a regular, writable file whose contents include a bare '*'." >&2
  elif ! git -C "$root" check-ignore -q ".clavity/discipline-reaching.jsonl" 2>/dev/null; then
    # THE CONFIG BEING RIGHT IS NOT THE DIRECTORY BEING SAFE. A bare `*` cannot hide a file git already
    # TRACKS, so a force-added file inside .clavity/ keeps leaking while the shield reads as perfect -
    # and every arm above answers "asserted" and falls silent. MEASURED under WSL (capstone round 2e):
    # shield contains `*`, one file force-added, `git check-ignore` says NOT ignored, fallback silent.
    # The primary helper checks this; the fallback checked only its own configuration, which made it
    # silent in exactly the state the whole branch exists to shout about.
    #
    # ONE git PROCESS, and only here. The header's budget rule is about the ROOT WALK, and it already
    # licenses the shield assertion to spawn (:17-21). This runs only on the degraded path, only after
    # the shield has been confirmed present and correct, so the common case still costs nothing. The
    # remedy is quoted verbatim because a gitignore rule cannot supply it - same wording as
    # agy-shield-lib.sh:416, one vocabulary whichever path reports it.
    printf 'agy-shield: %s\n' "$root/.clavity/.gitignore is correct, but git still does NOT ignore .clavity/discipline-reaching.jsonl - a file inside .clavity/ is TRACKED and a gitignore rule cannot hide it. That file needs: git rm --cached -- .clavity/discipline-reaching.jsonl" >&2
  fi
fi

[ -d "$out" ] || mkdir -p "$out" 2>/dev/null || exit 0

# v:3 is the SessionStart capture shape. v:1 (analyse-at-SessionEnd) SHIPPED in v17 and v:2 (SessionEnd
# capture) exists on dev machines, so all three can coexist on an upgraded machine; the report reads each by
# its own version rather than guessing. Values are emitted exactly as they arrived - already JSON-escaped by
# the caller - so no re-escaping step exists to get wrong. model is recorded and deliberately NOT reported:
# capture is the irreversible half. model is written when the payload carries it - startup and compact
# payloads do, resume payloads do not (MEASURED 2026-08-05: the first real post-install row was
# source=resume with an empty model). The hook records what it is handed; an empty model is DATA, not a bug.
# The previous wording here asserted that a field not written at session N cannot be recovered later, which
# is false for exactly that case and would send a reader hunting a capture bug that does not exist.
printf '{"v":3,"session_id":"%s","timestamp":"%s","source":"%s","model":"%s","transcript_path":"%s","scan_status":"%s"}\n' \
  "$sid" "$ts" "$src" "$model" "$tx" "$status" 2>/dev/null >> "$out/discipline-reaching.jsonl"

exit 0

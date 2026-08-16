#!/usr/bin/env bash
# Sanctioned writer for <cwd>/.clavity/ (plugin-shipped). RUN as a process, never sourced - so `exit`
# is correct here, the exact opposite of agy-shield-lib.sh's return-only rule, and the difference is
# load-bearing: the helper runs inside a PreToolUse chain where a non-zero exit BLOCKS an agent, while
# this script is invoked by a skill, where a refusal blocks nothing. DO NOT HARMONISE THEM.
#
# ANCHORED TO THE INVOKING CWD, NOT git-toplevel. agy-seam-inject.sh:124 reads the debounce marker at
# "$cwd_path/.clavity/agy-marks/<discipline>.head", and its comment at :118-122 forbids the git root by
# name: a toplevel writer against that cwd reader diverges in any launched-from-subdir session and
# defeats the debounce, so the discipline re-fires forever. (open-issues/SKILL.md:63-67 legitimately
# uses toplevel for local-anomalies.md, whose reader resolves the root the same way. Two files, two
# anchors, both correct.)
#
# Modes:
#   head    <discipline> <sha>                    -> .clavity/agy-marks/<discipline>.head
#   log     <discipline> <status> <sha> [text...] -> append one line to .clavity/agy-marks/skipped.log
#   prepare <relpath>                             -> create + shield the parent of .clavity/<relpath>
#
# Exit codes: 0 wrote; 1 REFUSED, nothing written; 2 the write itself failed partway. A caller must be
# able to tell "refused" from "wrote", and one non-zero cannot express that.

set -u

mode=${1:-}

# THE LOG LINE IS BUILT BEFORE ANYTHING CAN REFUSE, and panel R10 is why. The helper-load checks below
# fire _die_refuse BEFORE `case "$mode"` is ever evaluated, so a `log` invocation that failed there lost
# its payload entirely - and the test row asserting "a refused log emits BOTH the line and the reason"
# was asserting behaviour the control flow made impossible. `skipped.log` has NO re-fire path, so a
# refused write destroys a record with nothing to recreate it; the obligation therefore binds on EVERY
# refusal path, not only the ones inside the log branch. Built once here, which is also what makes the
# "the script owns the line format" contract true rather than aspirational.
_pending_log=''
if [ "$mode" = 'log' ]; then
    _pl_disc=${2:-}; _pl_status=${3:-}; _pl_sha=${4:-}
    _pl_text=''
    [ $# -gt 4 ] && _pl_text=${*:5}
    printf -v _pl_ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1 2>/dev/null || _pl_ts=$(TZ=UTC date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
    if [ -n "$_pl_text" ]; then
        _pending_log=$(printf '%s  %s  %s  HEAD=%s  %s' "$_pl_ts" "$_pl_disc" "$_pl_status" "$_pl_sha" "$_pl_text")
    else
        _pending_log=$(printf '%s  %s  %s  HEAD=%s' "$_pl_ts" "$_pl_disc" "$_pl_status" "$_pl_sha")
    fi
fi

_die_refuse() {
    printf 'agy-mark: REFUSED - %s\n' "$1" >&2
    # A refused `log` must ALSO surface the line it could not write, on EVERY refusal path.
    [ -n "$_pending_log" ] && printf 'agy-mark: LOG LINE NOT WRITTEN -\n  %s\n' "$_pending_log" >&2
    exit 1
}

[ -n "$mode" ] || _die_refuse 'no mode given (expected head|log|prepare)'

root=$PWD
[ -d "$root" ] || _die_refuse "cwd does not resolve: [$root]"

# IT VALIDATES ITS OWN ARGUMENTS - it cannot delegate this. The 4.1 helper returns 0 on a validation
# fault BY CONTRACT, so this script would receive success and proceed to write. <discipline> and
# <relpath> are interpolated into a path, so a value containing / or .. escapes the directory.
_check_discipline() {
    case "$1" in
        ''|*[!A-Za-z0-9._-]*) _die_refuse "discipline must match [A-Za-z0-9._-]+, got: [$1]" ;;
        .|..)                 _die_refuse "discipline must not be a path segment alias: [$1]" ;;
    esac
}
_check_relpath() {
    case "$1" in
        '')    _die_refuse 'relpath is empty' ;;
        /*)    _die_refuse "relpath must not start with '/': [$1]" ;;
        *..*)  _die_refuse "relpath must not contain '..': [$1]" ;;
        # A TRAILING SLASH IS THE DOCUMENTED TRAP, AND IT WAS DOCUMENTED WITHOUT BEING ENFORCED.
        # `prepare` resolves its target with `dirname`, so `scratch/<topic>/` creates `.clavity/scratch`
        # and NOT `.clavity/scratch/<topic>` - the discipline's next write then fails mid-run, far from
        # the mistake. Every call site substitutes `<PATH>` BY HAND, so the mistake is the caller's to
        # make and a prose warning is the only thing standing in front of it.
        # This is NOT a directory mode and NOT a dummy-file convention - both are forbidden a few lines
        # below the warning. It rejects one malformed ARGUMENT, loudly, naming it, exactly as the
        # class-`validation` contract requires - and it leaves a legal file path untouched.
        */)    _die_refuse "relpath must name a FILE, not a directory - it ends in '/': [$1] (pass a concrete file that will live in that directory, e.g. scratch/<topic>/notes.md)" ;;
    esac
}

# Load the shield helper. Hard-wired: there is no way to skip it. Its return value carries no
# information (it is always 0) and must not be branched on.
_lib="$(dirname "$0")/agy-shield-lib.sh"
[ -f "$_lib" ] || _die_refuse "shield helper not found beside this script: [$_lib]"
# shellcheck source=agy-shield-lib.sh
. "$_lib" 2>/dev/null || _die_refuse "shield helper could not be sourced: [$_lib]"
command -v agy_shield >/dev/null 2>&1 || _die_refuse "shield helper loaded but agy_shield is not defined: [$_lib]"

_key=${AGY_SESSION_ID:-}

case "$mode" in
    head)
        discipline=${2:-}; sha=${3:-}
        _check_discipline "$discipline"
        [ -n "$sha" ] || _die_refuse 'head requires a sha argument'
        rel=".clavity/agy-marks/$discipline.head"
        agy_shield "$root" "$rel" "$_key"
        # EVERY mode creates the directory it writes into. The helper's Stage A1 creates .clavity/ and
        # NOTHING BELOW IT, and this batch removes the skills' own mkdir instructions, so without this
        # a fresh clone fails "No such file or directory" on the first discipline that runs.
        mkdir -p "$root/.clavity/agy-marks" 2>/dev/null || _die_refuse 'could not create .clavity/agy-marks'
        # BARE sha and nothing else (docs/agy-disciplines-marker-contract.md:18).
        printf '%s' "$sha" > "$root/$rel" 2>/dev/null || { printf 'agy-mark: write FAILED partway for %s\n' "$rel" >&2; exit 2; }
        exit 0
        ;;
    log)
        discipline=$_pl_disc; status=$_pl_status
        rel=".clavity/agy-marks/skipped.log"
        # THE SCRIPT OWNS THE LINE FORMAT, and it is built exactly ONCE - up at the top, before any
        # refusal path can run. Callers must NOT pass a preformatted line: moving the shape here is the
        # entire point of having a script, and leaving it in the callers keeps copies of a format that
        # must agree. $_pending_log IS that line.
        line=$_pending_log
        # log has NO re-fire path - skipped.log is a durable audit breadcrumb - so a refused or failed
        # write destroys a record with nothing to recreate it. Emit BOTH the line AND the reason on
        # stderr. This binds on exit 1 AND on exit 2: in both cases the record did not reach disk.
        _log_lost() { printf 'agy-mark: LOG LINE NOT WRITTEN - %s\n  %s\n' "$1" "$line" >&2; }
        case "$discipline" in
            ''|*[!A-Za-z0-9._-]*) _log_lost "discipline must match [A-Za-z0-9._-]+, got: [$discipline]"; exit 1 ;;
        esac
        [ -n "$status" ] || { _log_lost 'no status given'; exit 1; }
        agy_shield "$root" "$rel" "$_key"
        mkdir -p "$root/.clavity/agy-marks" 2>/dev/null || { _log_lost 'could not create .clavity/agy-marks'; exit 1; }
        # ONE printf >>, never read-modify-write: two sessions can be open on the same repository, and a
        # single short append is atomic on POSIX, so concurrent writers interleave lines rather than
        # corrupting them.
        printf '%s\n' "$line" >> "$root/$rel" 2>/dev/null || { _log_lost 'the append itself failed'; exit 2; }
        exit 0
        ;;
    prepare)
        relpath=${2:-}
        _check_relpath "$relpath"
        rel=".clavity/$relpath"
        agy_shield "$root" "$rel" "$_key"
        _parent=$(dirname "$root/$rel")
        mkdir -p "$_parent" 2>/dev/null || _die_refuse "could not create $_parent"
        exit 0
        ;;
    *)
        _die_refuse "unknown mode: [$mode] (expected head|log|prepare)"
        ;;
esac

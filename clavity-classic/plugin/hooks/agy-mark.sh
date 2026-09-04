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
# Exit codes: 0 wrote; NON-ZERO did not. The reason is on stderr, and the reason is the point.
#
# THE MESSAGES, IN FULL, BECAUSE THEY ARE NOW THE ENTIRE CONTRACT. A caller that reads only one of them
# misclassifies the others. CAPSTONE ROUND 5 REWROTE THIS BLOCK because the previous version was wrong in
# two ways that mattered exactly here, where the exit code no longer discriminates anything:
#
#   "REFUSED - <reason>"
#       Emitted by _die_refuse. The old text glossed this as "fix the arguments", which is FALSE for two
#       paths: head's and prepare's `mkdir -p ... || _die_refuse` are ENVIRONMENTAL failures, not argument
#       faults, and they carry this prefix. Read it as "this run refused to write", not as "you passed a
#       bad argument".
#       NOT emitted by log mode's OWN validation - see below. MEASURED: `log "bad discipline" ...` emits
#       only the LOG LINE prefix, while `head "bad discipline" ...` emits only REFUSED.
#
#   "write FAILED for <path> - the filesystem rejected it"
#       HEAD mode only; attempted and rejected by the filesystem. Escalate.
#
#   "LOG LINE NOT WRITTEN - <reason>"
#       LOG mode. The <reason> discriminates, and the prefix alone decides NOTHING:
#         "the filesystem rejected the append"  -> attempted and rejected; escalate.
#         anything else ("could not create .clavity/agy-marks", "no status given", ...) -> a refusal.
#
# WHICH PREFIXES APPEAR TOGETHER, which the old block did not say and a caller cannot guess:
#   log refused BEFORE its branch is reached (helper missing, no mode, bad cwd) -> BOTH prefixes, REFUSED
#       first, then the line it could not write.
#   log refused BY ITS OWN validation (bad discipline, no status)              -> LOG LINE prefix ONLY.
#   head or prepare refused, for any reason                                    -> REFUSED only.
#
# PRECONDITION A CALLER CANNOT SEE FROM THE ARGUMENTS: this script reads $AGY_SESSION_ID from the
# environment and passes it to the shield helper as a debounce key. Unset is legal and means "do not
# debounce" for the notice path - but see the sweep-gate comment in agy-shield-lib.sh, where an empty key
# has a different and deliberately-documented consequence.
#
# THIS USED TO BE A TRI-STATE (1 refused before trying, 2 attempted and rejected) and roadmap 19 collapsed
# it, on a measurement rather than taste: every call site across agy-first, agy-capstone and agy-test-audit
# either spells it `if ! bash .../agy-mark.sh ...; then <echo>; exit 1; fi` or ignores the status entirely.
# `if !` is a TWO-outcome construct, so every non-zero already collapsed to "abort", and the `then` blocks
# contain nothing but an echo and an exit - no cleanup that could vary by failure kind. Both failures are
# terminally fatal with no programmatic recovery: refused means this script's own caller is malformed,
# rejected means it cannot write the repo-anchored state the discipline requires and has no legal fallback
# location. The caller pattern was evidence the API was over-designed, not that the callers were buggy.
#
# WHAT THE COLLAPSE COST, AND WHERE IT WENT. The exit code no longer distinguishes a refusal from a
# rejected write, so the stderr messages carry that burden alone and MUST NOT be merged or reworded -
# agy-mark.Tests.ps1 asserts each by its distinct text for exactly this reason. Note also that a rejected
# write is not "failed partway": with `>` and `>>` the SHELL opens the target BEFORE the command runs, so
# an unopenable target fails with printf never executing and ZERO bytes written. MEASURED: a directory
# target reports "Is a directory" and writes nothing. The question the message answers is WHO stopped the
# write, not how much of it landed.

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
    # NEWLINES ARE STRIPPED FROM EVERY INTERPOLATED FIELD, and capstone round 3 found why. This file
    # OWNS the one-line record format - that is the stated reason the format lives here rather than in
    # the callers - but it interpolated caller-supplied text into it without ever enforcing "one line".
    # The <finding> argument at the agy-capstone skill's log call is DRIVER-SUPPLIED prose, so a newline
    # in it is ordinary, not hostile. MEASURED: one call carrying a two-line finding produced FOUR lines
    # in skipped.log, one of them a syntactically perfect `WAIVED` record. That is not cosmetic. The
    # ledger convention corrected in c5477ad reads this file to decide whether a capstone was waived
    # inside a given range, by looking for a WAIVED line whose HEAD is in that range - so a forged line
    # here manufactures exactly the false attestation the whole discipline exists to prevent.
    # Replaced with a space rather than deleted: the finding text stays readable, and the record stays
    # one line. `${var//}` is a bashism, which this script already relies on two lines up (`${*:5}`).
    # THE SEPARATOR IS FLATTENED TOO, NOT ONLY THE LINE BREAK - capstone round 4. Stripping newlines
    # closed the "forge a second RECORD" hole and left the "disturb the FIELDS of this record" one open:
    # the format separates fields with TWO SPACES, so two spaces inside a caller-supplied value shift every
    # column after it, and a reader that scans for a status rather than indexing to it can be fooled inside
    # a single line. Same principle as the newline: this script owns the record format, so it owns the
    # bytes that define the format. Runs are collapsed to one space rather than removed, so the text stays
    # readable. Tabs go too - not a separator here, but no reader expects one mid-record.
    # ALL FOUR FIELDS, and the previous version's comment claimed "every interpolated field" while covering
    # three - `_pl_disc` is interpolated into the same line and was not flattened. It cannot reach
    # skipped.log (the validator rejects anything outside [A-Za-z0-9._-], and MEASURED: a newline in it
    # refuses the write and the file is never created) but it DOES reach the stderr record that a refused
    # log emits, which is the copy an operator is expected to keep. A forged-looking line there is the same
    # defect one surface over.
    _pl_flat=''
    _pl_flatten() {
        _pl_flat=${1//[$'\n\r\t']/ }
        while :; do
            case "$_pl_flat" in
                *"  "*) _pl_flat=${_pl_flat//"  "/ } ;;
                *)      break ;;
            esac
        done
    }
    _pl_flatten "$_pl_disc";   _pl_disc=$_pl_flat
    _pl_flatten "$_pl_status"; _pl_status=$_pl_flat
    _pl_flatten "$_pl_sha";    _pl_sha=$_pl_flat
    _pl_flatten "$_pl_text";   _pl_text=$_pl_flat
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
# THE SHA IS VALIDATED TOO, and the marker contract is why. docs/agy-disciplines-marker-contract.md:18
# says the content is "the commit sha from `git rev-parse HEAD` at consult time, and nothing else". The
# code wrote whatever it was handed, verbatim - MEASURED (capstone round 5): a two-line argument produced
# a TWO-LINE marker file and exit 0, so the file silently stopped being what its own contract says it is.
# Every real call site passes "$(git rev-parse HEAD)", so this refuses nothing that happens today; it
# stops a caller from making the marker unreadable to the hook that consumes it. Checked AFTER the
# non-empty test so the "head requires a sha argument" message survives for the empty case.
_check_sha() {
    case "$1" in
        *[!0-9a-fA-F]*) _die_refuse "sha must be hexadecimal and nothing else, got: [$1]" ;;
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
        _check_sha "$sha"
        rel=".clavity/agy-marks/$discipline.head"
        agy_shield "$root" "$rel" "$_key"
        # EVERY mode creates the directory it writes into. The helper's Stage A1 creates .clavity/ and
        # NOTHING BELOW IT, and this batch removes the skills' own mkdir instructions, so without this
        # a fresh clone fails "No such file or directory" on the first discipline that runs.
        mkdir -p "$root/.clavity/agy-marks" 2>/dev/null || _die_refuse 'could not create .clavity/agy-marks'
        # BARE sha and nothing else (docs/agy-disciplines-marker-contract.md:18).
        printf '%s' "$sha" 2>/dev/null > "$root/$rel" || { printf 'agy-mark: write FAILED for %s - the filesystem rejected it\n' "$rel" >&2; exit 1; }
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
        # stderr. This binds on EVERY non-zero exit, refusal and rejection alike: in both cases the record
        # did not reach disk, and since roadmap 19 collapsed the tri-state the exit code no longer says
        # which happened - the reason passed to _log_lost is what distinguishes them.
        _log_lost() { printf 'agy-mark: LOG LINE NOT WRITTEN - %s\n  %s\n' "$1" "$line" >&2; }
        case "$discipline" in
            ''|*[!A-Za-z0-9._-]*) _log_lost "discipline must match [A-Za-z0-9._-]+, got: [$discipline]"; exit 1 ;;
        esac
        [ -n "$status" ] || { _log_lost 'no status given'; exit 1; }
        # THE SHA IS VALIDATED HERE TOO, and capstone round 9 caught that it was not. Round 5 added
        # _check_sha and wired it into `head` ONLY, so `log` accepted anything: MEASURED, `not-a-sha` was
        # flattened and written straight into the HEAD= field of skipped.log, exit 0, while the identical
        # argument to `head` was refused. One fact, two modes, folded into one - the same incomplete-fold
        # shape round 8 caught one file over.
        # REFUSED THROUGH _log_lost, NOT _check_sha, and the difference is the contract this file now
        # documents in its header: a refusal from log's OWN validation emits the LOG LINE prefix alone,
        # while _check_sha calls _die_refuse and would add a REFUSED line that the header says log-mode
        # validation does not produce. Reusing the head-mode helper here would have been the tidier-looking
        # change and would have falsified the documentation in the same commit that relied on it.
        # AN EMPTY SHA IS STILL ACCEPTED, deliberately: `log` has no re-fire path, so refusing destroys an
        # audit record with nothing to recreate it, and this file already ranks recording above refusing
        # for that reason. Only a MALFORMED sha is rejected.
        case "$_pl_sha" in
            *[!0-9a-fA-F]*) _log_lost "sha must be hexadecimal and nothing else, got: [$_pl_sha]"; exit 1 ;;
        esac
        agy_shield "$root" "$rel" "$_key"
        mkdir -p "$root/.clavity/agy-marks" 2>/dev/null || { _log_lost 'could not create .clavity/agy-marks'; exit 1; }
        # ONE printf >>, never read-modify-write: two sessions can be open on the same repository, and a
        # single short append is atomic on POSIX, so concurrent writers interleave lines rather than
        # corrupting them.
        printf '%s\n' "$line" 2>/dev/null >> "$root/$rel" || { _log_lost 'the filesystem rejected the append'; exit 1; }
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
    stamp)
        # Record whether a design consult and the review that follows it shared one agy cascade.
        # THIS IS A RECORD, NOT A GATE. It always exits 0 on a well-formed call, including
        # SHARED-CONTEXT. Owner ruling 2026-09-04: "record isolation, do not gate on it" - a blocking
        # step here would recreate the skip-pressure the mandatory consult exists to remove.
        discipline="${2:-}"
        consult_id="${3:-}"
        review_id="${4:-}"
        if [ -z "$discipline" ] || [ -z "$consult_id" ] || [ -z "$review_id" ]; then
            echo "agy-mark stamp: need <discipline> <consult-cascade-id> <review-cascade-id>" >&2
            exit 64
        fi
        # A cascade id containing whitespace corrupts the log line's POSITIONAL fields below (a
        # reader parsing field 5 as the isolation token would read a fragment of the id instead).
        # Reject at the door - do NOT reformat the record; its field order and separators are a
        # contract other rows already exist in. $discipline occupies field 2 and is exactly as
        # exposed to this corruption as $consult_id/$review_id are - unlike head)/log), this arm
        # never routes $discipline through _check_discipline, so nothing else in this file catches it.
        case "$discipline" in
            *[[:space:]]*)
                echo "agy-mark stamp: discipline must not contain whitespace, got: [$discipline]" >&2
                exit 64
                ;;
        esac
        case "$consult_id" in
            *[[:space:]]*)
                echo "agy-mark stamp: consult-cascade-id must not contain whitespace, got: [$consult_id]" >&2
                exit 64
                ;;
        esac
        case "$review_id" in
            *[[:space:]]*)
                echo "agy-mark stamp: review-cascade-id must not contain whitespace, got: [$review_id]" >&2
                exit 64
                ;;
        esac
        if [ "$consult_id" = "$review_id" ]; then
            isolation="SHARED-CONTEXT"
        else
            isolation="ISOLATED"
        fi
        # CREATE THE DIRECTORY FIRST. AGY-AFTER round 2 (Cascade Analyst) caught this as BLOCKING:
        # without it, `>>` into a missing .clavity/agy-marks fails with "No such file or directory"
        # and the arm exits NON-ZERO on a fresh clone or the very first consult - turning the one step
        # that is explicitly "a record, never a gate" into an accidental blocker. VERIFIED: this file
        # has NO shared mkdir; the head, log and prepare arms each do their own.
        #
        # A FAILED MKDIR STILL MUST NOT GATE. head) and prepare) call _die_refuse here because their
        # write is load-bearing; ours is not, so a genuinely unwritable directory degrades to a warning
        # on stderr and exit 0 rather than blocking the round.
        mkdir -p "$root/.clavity/agy-marks" 2>/dev/null || {
            echo "agy-mark stamp: could not create .clavity/agy-marks - isolation NOT recorded" >&2
            exit 0
        }
        # Append with >>, never >. Two sessions can be open on one repository, and a truncating
        # writer silently eats the other's row.
        printf '%s %s consult=%s review=%s %s %s\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$discipline" "$consult_id" "$review_id" \
            "$isolation" "$(git rev-parse HEAD 2>/dev/null || echo unknown)" \
            >> "$root/.clavity/agy-marks/consults.log" 2>/dev/null || {
            echo "agy-mark stamp: could not write consults.log - isolation NOT recorded" >&2
            exit 0
        }
        exit 0
        ;;
    *)
        _die_refuse "unknown mode: [$mode] (expected head|log|prepare)"
        ;;
esac

#!/usr/bin/env bash
# The ledger reader for the ROADMAP section 27 marker-write gate.
#
# SOURCED, NEVER EXECUTED. It must not call `exit`: agy-mark.sh sources it, and an exit here kills the
# caller mid-run. This is the same rule agy-shield-lib.sh follows and the opposite of agy-mark.sh's own,
# which IS a process. DO NOT HARMONISE THEM.
#
# WHAT THIS PROVES, AND WHAT IT DOES NOT. It proves a ledger row records a sha as the RIGHT-HAND END of
# its range. It does NOT prove an audit happened - a fabricated row passes, and the spec says so from its
# first section. The value is narrower and real: it converts a sin of OMISSION (forgetting the row) into
# a sin of COMMISSION (writing a decoy), and agents forget far more readily than they fabricate.
#
# WHY THIS IS A REGEX AND NOT A PARSER. It used to be a ~200-line awk markdown parser: fence tracking,
# tilde and nested fences, info strings, contiguous-block state, CRLF normalisation, indentation bounds,
# hex validation and a `git rev-parse` round-trip per candidate row. The live peer argued four times that
# the machinery was disproportionate to the failure it guards - an agent forgetting to append one line -
# and the owner ruled the GATE stays while the PARSER goes.
#
# THE REPLACEMENT WAS MEASURED AGAINST THE PARSER ON REAL DATA, not reasoned about: over all 38 reviewed
# tips in docs/agy-capstone-ledger.md, queried with the full 40-character shas the gate actually receives,
# both answer FOUND 38 times out of 38. Two false-pass classes that a cell-wide search reopens are closed
# here and pinned by tests: a fold sha appearing in a range cell's trailing PROSE (`e60ad19`), and a
# range's LEFT endpoint (`49be0c4`) - neither of which the ledger records as a reviewed tip.
#
# WHY THE MATCH IS ANCHORED WHERE IT IS. `^ {0,3}\|` is a table row at CommonMark's 0-3 space indent. The
# date-shaped SECOND column is what distinguishes a record from the header row and from the 3-column
# anomaly table that shares this file. The range must then be the FIRST thing in the third column, which
# is what stops the trailing parenthetical prose from authenticating anything: range cells legitimately
# carry further ranges in that prose (docs/agy-capstone-ledger.md:69 cites `f9f2998..e60ad19`), and
# scanning the whole cell lets a fold commit mentioned in passing authenticate a marker.
#
# WHY AN ALTERNATION OF PREFIXES RATHER THAN `git rev-parse`. The ledger writes 7-character shas; the gate
# is called with 40. Matching the query's every prefix of length 7..40 is EXACT - the row token must be a
# prefix of the sha under test - and it removes git from this path entirely. That deletes a folded defect
# by construction: `git rev-parse` resolves ANY ref, so a branch literally NAMED `deadbeef` once resolved
# to HEAD and authenticated a marker the ledger never recorded. No ref lookup, no moving target.
#
# ACCEPTED LIMITATIONS, all of the same shape - each needs the row to have been WRITTEN, which is not the
# omission this gate defends against:
#   - a row inside a fenced code block now MATCHES. The old parser refused it (capstone round 1). MEASURED
#     2026-09-07: neither shipped ledger contains a single fence line, so this is a future risk, not a
#     live one, and it is the same bargain already accepted below.
#   - a COMPLETE table inside a container that preserves leading pipes (`<div>`, a lazy blockquote,
#     `<details>`) reads as live. OWNER-RULED twice, 2026-09-07.
#   - a row without a leading pipe is ignored; a record kept only as a `##` heading is invisible.

# agy_ledger_path <git-root> <discipline>
# Echoes the convention path. Performs NO existence check.
#
# THE DISCIPLINE STRING IS USED RAW, AND THAT IS LOAD-BEARING. Capstone round 6 argued that a
# mis-cased discipline is a gate bypass, because a case-INSENSITIVE filesystem resolves
# docs/Agy-Capstone-ledger.md to the real ledger while a case-SENSITIVE one does not and answers
# NO-LEDGER. MEASURED on both: the divergence is real - exit 1 on Windows, exit 0 on Linux - but no
# bypass is achieved, because agy-mark.sh derives the MARKER path from THE SAME STRING
# (.clavity/agy-marks/<discipline>.head). The mis-cased run writes Agy-Capstone.head, which no
# reader consults, so the gate simply re-arms.
#
# The two paths agree BY CONSTRUCTION: same string, same filesystem, same case semantics. Wherever
# the ledger resolves, the marker counts; wherever it does not, the marker is not read either.
# DO NOT normalise the discipline for one path without normalising it for the other - doing so to
# only one of them converts this non-issue into a real bypass.
agy_ledger_path() {
    printf '%s/docs/%s-ledger.md' "$1" "$2"
}

# agy_ledger_lookup <cwd> <discipline> <sha>
# Echoes exactly one of:
#   NO-LEDGER          - this discipline owns no ledger here, so the gate does not apply
#   FOUND              - a record's range right-endpoint is a prefix of <sha>
#   ABSENT mentioned=0 - no record matches and the sha appears NOWHERE in the file
#   ABSENT mentioned=1 - no record matches, but the sha DOES appear in the file: in prose, as a range's
#                        LEFT endpoint, or in a range that is not first in its column. The two answers
#                        exist because one static refusal was measured WRONG for half its causes
#                        (capstone round 6), and the advice has to name what actually happened.
#   UNREADABLE         - the ledger exists but cannot be read, so NO claim can be made
# ALWAYS returns 0. The caller decides what to do; this function only answers.
agy_ledger_lookup() {
    local _agl_cwd=$1 _agl_disc=$2 _agl_sha=$3
    local _agl_root _agl_file _agl_alt _agl_i _agl_rx _agl_rc _agl_short

    # The MARKER is cwd-anchored (agy-mark.sh:140, and its header at :7-12 forbids git-toplevel BY NAME,
    # because agy-seam-inject.sh:124 reads the marker relative to cwd). The LEDGER is not: it exists only
    # at the git root. Two anchors, deliberately. If there is no git root - no repo, or no git on PATH -
    # there is no ledger to find, so the gate does not apply and agy-mark.sh stays git-optional.
    _agl_root=$(git -C "$_agl_cwd" rev-parse --show-toplevel 2>/dev/null) || { printf 'NO-LEDGER'; return 0; }
    [ -n "$_agl_root" ] || { printf 'NO-LEDGER'; return 0; }

    _agl_file=$(agy_ledger_path "$_agl_root" "$_agl_disc")
    [ -f "$_agl_file" ] || { printf 'NO-LEDGER'; return 0; }

    # A NON-HEX OR TOO-SHORT QUERY CANNOT BE A SHA, and must not reach the regex - it would be interpreted
    # as PATTERN TEXT rather than as a literal. Refuse instead; this function never fails open.
    case "$_agl_sha" in
        ''|*[!0-9a-fA-F]*) printf 'ABSENT mentioned=0'; return 0 ;;
    esac
    [ ${#_agl_sha} -ge 7 ] || { printf 'ABSENT mentioned=0'; return 0; }

    # Every prefix of the query from 7 characters to its full length. The row's endpoint must be one of
    # them, which is what lets an abbreviated ledger entry match a full sha WITHOUT resolving anything.
    _agl_alt=''
    _agl_i=7
    while [ "$_agl_i" -le ${#_agl_sha} ]; do
        _agl_alt="${_agl_alt:+$_agl_alt|}${_agl_sha:0:$_agl_i}"
        _agl_i=$((_agl_i + 1))
    done

    # The optional `[` and backtick carry the link and padded-bracket forms capstone round 3 folded
    # (`[ deadbeef ]`, `[x](url)`). The trailing class is what forbids a LEFT endpoint: a bare token
    # followed by a dot is the near side of a range, not the far side, and must not match.
    _agl_rx='^[ ]{0,3}\|[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*\|[[:space:]]*`?(\[[[:space:]]*)?`?'
    _agl_rx="${_agl_rx}([0-9a-fA-F]+\\^?\\.\\.)?(${_agl_alt})([^0-9a-fA-F.]|\$)"

    # GREP'S EXIT CODE IS THE UNREADABILITY ORACLE, and that is the established idiom in this plugin:
    # agy-anomaly-reminder.sh:139-144 chose it over `[ -r ]` for the same reason and says so - the shell's
    # -r builtin does NOT consult Windows ACLs and calls an ACL-denied file readable. MEASURED 2026-09-07:
    # `cat` failed with Permission denied while `[ -r ]` answered true. grep's contract is POSIX and
    # platform-independent - 0 matched, 1 matched nothing, greater than 1 error.
    grep -Eqi "$_agl_rx" "$_agl_file" 2>/dev/null
    _agl_rc=$?
    [ "$_agl_rc" -le 1 ] || { printf 'UNREADABLE'; return 0; }
    [ "$_agl_rc" -eq 0 ] && { printf 'FOUND'; return 0; }

    # THE DIAGNOSTIC PASS. A bare refusal cannot tell "you never wrote the row" from "you wrote it wrong",
    # and capstone rounds 6 and 7 both folded defects where the advice did not match the cause. -F is
    # fixed-string ON PURPOSE: the short sha is data here, not a pattern.
    _agl_short=${_agl_sha:0:7}
    if grep -Fqi "$_agl_short" "$_agl_file" 2>/dev/null; then
        printf 'ABSENT mentioned=1'
    else
        printf 'ABSENT mentioned=0'
    fi
    return 0
}

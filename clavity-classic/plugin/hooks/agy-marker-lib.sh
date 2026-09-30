#!/usr/bin/env bash
# The ONE place the debounce-marker path is built (ROADMAP section 39).
#
# SOURCED, NEVER EXECUTED - it must not call `exit`: agy-mark.sh (a process) and three fail-open hooks
# source it. The writer (agy-mark.sh) and every reader (agy-seam-inject.sh, agy-test-audit-reminder.sh,
# agy-consult-recovery.sh) each used to build `.clavity/agy-marks/<discipline>.head` on its own, and the
# invariant that they agree - the SAME discipline string, unmodified, in the SAME shape - was asserted
# nowhere. A one-sided change (a writer that lowercases, a reader that does not) would land the marker where
# no reader looks; on a case-insensitive filesystem the two names even resolve to one file, so the
# divergence would show only on the case-sensitive platforms CI does not run. Building the path in one
# function makes that divergence impossible by construction rather than detectable by a test.
# The discipline string is used RAW - agy-ledger-lib.sh derives the ledger path from the same string, and
# its comment explains why normalising either path alone would turn a non-issue into a bypass.
#
# agy_marker_rel <out-var> <discipline>
# Sets <out-var> to the marker path relative to the caller's anchor. `printf -v` rather than command
# substitution: two callers are hooks that run on every tool call, and each fork costs ~126ms on Windows.
agy_marker_rel() {
    printf -v "$1" '.clavity/agy-marks/%s.head' "$2"
}
